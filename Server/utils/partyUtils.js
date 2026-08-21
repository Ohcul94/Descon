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

module.exports = {
    getPartyIdByUid,
    getPartyIdBySocketId,
    areInSameParty,
    areInSamePartyBySocket,
    isFriendlyFireEnabled
};
