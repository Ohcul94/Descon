/**
 * partyUtils.js - Helpers para party (escuadrón)
 * Centraliza la lógica de verificación de party para evitar duplicación.
 */

function getPartyIdByUid(uid, state) {
    if (!uid || !state || !state.playerParty) return null;
    return state.playerParty[String(uid)] || null;
}

function getPartyIdBySocketId(socketId, state) {
    if (!socketId || !state || !state.players) return null;
    const p = state.players[socketId];
    if (!p) return null;
    const uid = p.dbId || (p.dbUser && p.dbUser._id ? String(p.dbUser._id) : null);
    if (!uid) return null;
    return getPartyIdByUid(uid, state);
}

function areInSameParty(uid1, uid2, state) {
    if (!uid1 || !uid2 || !state || !state.playerParty) return false;
    const pid1 = getPartyIdByUid(uid1, state);
    const pid2 = getPartyIdByUid(uid2, state);
    return !!pid1 && pid1 === pid2;
}

function areInSamePartyBySocket(socketId1, socketId2, state) {
    if (!socketId1 || !socketId2 || !state || !state.players) return false;
    const p1 = state.players[socketId1];
    const p2 = state.players[socketId2];
    if (!p1 || !p2) return false;
    const uid1 = p1.dbId || (p1.dbUser && p1.dbUser._id ? String(p1.dbUser._id) : null);
    const uid2 = p2.dbId || (p2.dbUser && p2.dbUser._id ? String(p2.dbUser._id) : null);
    if (!uid1 || !uid2) return false;
    return areInSameParty(uid1, uid2, state);
}

function isFriendlyFireEnabled(mapCfg) {
    if (!mapCfg) return false;
    if (mapCfg.friendlyFire !== undefined) return !!mapCfg.friendlyFire;
    // Por defecto: fuego amigo DESACTIVADO (party protegida). Activar solo si el Admin lo habilita explícitamente.
    return false;
}

function getPartyVisionRadius(player, state) {
    if (!player) return 1650;
    let playerVision = 1300;
    if (state && state.SERVER_CONFIG && state.SERVER_CONFIG.shipModels) {
        const ship = state.SERVER_CONFIG.shipModels.find(s => s && s.id === player.currentShipId);
        if (ship && ship.vision !== undefined) {
            playerVision = Number(ship.vision);
        }
    }
    return Math.max(playerVision * 1.25, 1650);
}

/**
 * Registra una acción de combate directo en el jugador y propaga el estado de combate
 * a los miembros de su Party que estén en la misma zona dentro del rango de visión.
 */
function recordPlayerCombat(player, state, now = Date.now()) {
    try {
        if (!player) return;
        player.lastDirectCombatTime = now;
        player.lastCombatTime = now;

        if (!state || !state.parties || !state.players) return;
        const partyId = getPartyIdBySocketId(player.socketId, state);
        if (!partyId || !state.parties[partyId]) return;

        const party = state.parties[partyId];
        if (!party || !party.members || party.members.length <= 1) return;

        const myUid = String(player.dbId || (player.dbUser && player.dbUser._id) || player.id || '');
        const myVision = getPartyVisionRadius(player, state);

        for (const mUid of party.members) {
            if (!mUid) continue;
            const mUidStr = String(mUid);
            if (mUidStr === myUid) continue;

            const mPlayer = Object.values(state.players).find(pl => 
                pl && String(pl.dbId || (pl.dbUser && pl.dbUser._id) || pl.id || '') === mUidStr
            );

            if (mPlayer && !mPlayer.isDead && String(mPlayer.zone) === String(player.zone)) {
                if (player.x !== undefined && player.y !== undefined && mPlayer.x !== undefined && mPlayer.y !== undefined) {
                    const dist = Math.hypot(player.x - mPlayer.x, player.y - mPlayer.y);
                    const maxVision = Math.max(myVision, getPartyVisionRadius(mPlayer, state));
                    if (dist <= maxVision) {
                        mPlayer.lastCombatTime = now;
                    }
                }
            }
        }
    } catch (err) {
        console.error("Error en recordPlayerCombat:", err);
    }
}

/**
 * Actualiza en cada ciclo del servidor el estado de combate compartido de los grupos (Parties).
 * Si algún miembro de la party está en combate directo activo (< 10s desde su última acción),
 * todos los miembros de la party en la misma zona que estén dentro de su rango de visión se mantienen
 * en combate (lastCombatTime = now).
 * Si un miembro se aleja fuera del rango de visión, su contador para salir de combate empezará a contar
 * desde el momento en que se alejó. Si reingresa a visión, su contador se reestablece de inmediato.
 */
function updatePartyCombatLoop(state, now) {
    try {
        if (!state || !state.parties || !state.players) return;
        const COMBAT_TIMEOUT = 10000; // 10 segundos autoritativos para salir de combate

        for (const partyId in state.parties) {
            const party = state.parties[partyId];
            if (!party || !party.members || party.members.length <= 1) continue;

            // Obtener miembros conectados y vivos
            const onlineMembers = [];
            for (const mUid of party.members) {
                if (!mUid) continue;
                const mUidStr = String(mUid);
                const pl = Object.values(state.players).find(p => 
                    p && String(p.dbId || (p.dbUser && p.dbUser._id) || p.id || '') === mUidStr
                );
                if (pl && !pl.isDead && pl.zone !== undefined && pl.x !== undefined && pl.y !== undefined) {
                    onlineMembers.push(pl);
                }
            }

            if (onlineMembers.length <= 1) continue;

            // Agrupar por zona
            const byZone = {};
            for (const pl of onlineMembers) {
                const z = String(pl.zone);
                if (!byZone[z]) byZone[z] = [];
                byZone[z].push(pl);
            }

            for (const z in byZone) {
                const zoneMembers = byZone[z];
                if (zoneMembers.length <= 1) continue;

                // Identificar miembros con combate directo activo
                const inDirectCombat = zoneMembers.filter(m => (now - (m.lastDirectCombatTime || 0)) < COMBAT_TIMEOUT);
                if (inDirectCombat.length === 0) continue;

                // Para cada miembro no combatiente directo, verificar si está en rango de visión de algún combatiente activo
                for (const pl of zoneMembers) {
                    if (inDirectCombat.includes(pl)) continue;

                    const plVision = getPartyVisionRadius(pl, state);
                    const isNearCombatant = inDirectCombat.some(combatant => {
                        const maxR = Math.max(plVision, getPartyVisionRadius(combatant, state));
                        const dist = Math.hypot(pl.x - combatant.x, pl.y - combatant.y);
                        return dist <= maxR;
                    });

                    if (isNearCombatant) {
                        pl.lastCombatTime = now;
                    }
                }
            }
        }
    } catch (err) {
        console.error("Error en updatePartyCombatLoop:", err);
    }
}

module.exports = {
    getPartyIdByUid,
    getPartyIdBySocketId,
    areInSameParty,
    areInSamePartyBySocket,
    isFriendlyFireEnabled,
    getPartyVisionRadius,
    recordPlayerCombat,
    updatePartyCombatLoop
};
