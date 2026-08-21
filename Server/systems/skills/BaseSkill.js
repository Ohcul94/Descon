/**
 * BaseSkill.js
 * Clase base para todas las habilidades del servidor.
 * v1.0 - Estructura modular para reducir deuda técnica.
 */

class BaseSkill {
    constructor(name, config = {}) {
        this.name = name;
        this.config = config;
    }

    /**
     * Lógica de ejecución de la habilidad.
     * @param {Object} p - Objeto del jugador que usa la habilidad.
     * @param {Object} data - Datos enviados desde el cliente (pos, target, etc).
     * @param {Object} context - Contexto del servidor (io, state, socket).
     */
    execute(p, data, { io, state, socket }) {
        // Implementar en subclases
    }

    /**
     * Resuelve el objetivo de la habilidad basado en la configuración.
     */
    getTarget(p, data, state, socket) {
        const skillConfig = (state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData[this.name] : {};
        let target = p;
        let isRemote = false;

        if (skillConfig && skillConfig.canTargetOthers) {
            if (!data.targetId) return { target: p, isRemote: false };

            const targetPlayer = state.players[data.targetId];
            const targetEnemy = state.enemies[data.targetId];
            const potentialTarget = targetPlayer || targetEnemy;

            if (!potentialTarget || potentialTarget.hp <= 0) return null;

            // Validación de Rango
            if (data.targetId !== socket.id && skillConfig.range && skillConfig.range > 0) {
                const dist = Math.hypot(p.x - potentialTarget.x, p.y - potentialTarget.y);
                if (dist > skillConfig.range + 50) return null;
            }

            if (data.targetId === socket.id) {
                target = p;
            } else {
                const filters = skillConfig.targetFilters || { allies: true, enemies: false, bosses: false, players: true };
                let isValid = false;

                if (targetPlayer) {
                    const sameClan = (p.clanId && targetPlayer.clanId && String(p.clanId) === String(targetPlayer.clanId));
                    // v650.0: Party siempre es aliado (fuego amigo bloqueado salvo friendlyFire)
                    let sameParty = false;
                    try {
                        const pid1 = state.playerParty ? state.playerParty[String(p.dbId || p.dbUser?._id || '')] : null;
                        const pid2 = state.playerParty ? state.playerParty[String(targetPlayer.dbId || targetPlayer.dbUser?._id || '')] : null;
                        // Fallback por socketId si dbId no está disponible
                        if (!pid1 || !pid2) {
                            const sid1 = p.socketId || p.id;
                            const sid2 = targetPlayer.socketId || targetPlayer.id;
                            if (sid1 && sid2 && state.players && state.players[sid1] && state.players[sid2]) {
                                const uid1 = state.players[sid1].dbId || String(state.players[sid1].dbUser?._id || '');
                                const uid2 = state.players[sid2].dbId || String(state.players[sid2].dbUser?._id || '');
                                const ppid1 = state.playerParty ? state.playerParty[String(uid1)] : null;
                                const ppid2 = state.playerParty ? state.playerParty[String(uid2)] : null;
                                sameParty = !!ppid1 && ppid1 === ppid2;
                            } else {
                                sameParty = !!pid1 && pid1 === pid2;
                            }
                        } else {
                            sameParty = !!pid1 && pid1 === pid2;
                        }
                    } catch (e) { sameParty = false; }
                    const isAlly = sameClan || sameParty || (!p.pvpEnabled && !targetPlayer.pvpEnabled);
                    const isEnemy = !sameClan && !sameParty && (p.pvpEnabled || targetPlayer.pvpEnabled);
                    
                    if (isAlly && filters.allies) isValid = true;
                    else if (isEnemy && (filters.enemies || filters.players)) isValid = true;
                    else if (!isAlly && !isEnemy && filters.players) isValid = true;
                } else if (targetEnemy) {
                    const isBoss = targetEnemy.type === 4 || targetEnemy.type === 10 || targetEnemy.type === 11;
                    if (isBoss && filters.bosses) isValid = true;
                    else if (!isBoss && filters.enemies) isValid = true;
                }

                if (isValid) {
                    target = potentialTarget;
                    isRemote = true;
                } else {
                    return null;
                }
            }
        }
        return { target, isRemote };
    }

    /**
     * Sincronización visual para otros jugadores.
     */
    broadcastUsage(p, data, { io, socket }, powerValue = 0) {
        const payload = {
            id: socket.id,
            skillName: this.name,
            targetId: data.targetId || socket.id,
            powerValue: powerValue
        };

        // v247.25: Soporte especial para coordenadas (BLINK)
        if (this.name === "BLINK") {
            payload.pos = { x: p.x, y: p.y };
        }

        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', payload);
    }
}

module.exports = BaseSkill;
