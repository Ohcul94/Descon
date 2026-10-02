/**
 * debuffUtils.js
 * Helper centralizado para aplicar debuffs declarativos (mech.debuffsList).
 *
 * Motivo: los mismos bloques de bleed/poison/stun/slow estaban duplicados en 6 lugares
 * (BaseAI x4, BossMeteorMechanics, BossDefenseMechanics). Acá se unifican y se agregan
 * dos efectos nuevos:
 *   - root    -> inmoviliza el movimiento (NO rompe casteo, NO bloquea skills)
 *   - silence -> silencia disparos y skills
 *
 * Unidades normalizadas del proyecto:
 *   duration / tickInterval -> ms
 *   dps                     -> pts/s
 *   amount (slow)           -> px/s o % según isPercentage
 */

const nowMs = () => Date.now();

/**
 * Aplica un debuff individual sobre un jugador.
 * @param {object} p      jugador (state.players[socketId])
 * @param {object} d      entrada de debuffsList { type, duration, dps, tickInterval, amount, isPercentage }
 * @param {object} io     instancia de Socket.IO
 * @param {string} source texto del causante para la notificación ("El gusano", "El meteorito", ...)
 * @returns {boolean} true si aplicó algún efecto
 */
function applyDebuff(p, d, io, source) {
    if (!p || !d || !d.type) return false;
    // Invulnerable / fuera de dimensión: no recibe debuffs (misma regla que el código original)
    if (p.isInvulnerable || p.inStrangeDimension) return false;

    const who = source || 'La mecánica';
    const notify = (msg, type) => {
        if (io && p.socketId) io.to(p.socketId).emit('gameNotification', { msg, type: type || 'warning' });
    };
    const dur = (v, def) => {
        const n = Number(v);
        return isFinite(n) && n > 0 ? n : def;
    };

    switch (d.type) {
        // ----------------------------------------------------------------------------------
        // SANGRADO - daño por tick con intervalo configurable
        // ----------------------------------------------------------------------------------
        case 'bleed': {
            const bleedDur = dur(d.duration, 4000);
            const tickInt = dur(d.tickInterval, 1000);
            p.isBleeding = true;
            p.bleedEndTime = nowMs() + bleedDur;
            p.bleedDps = Number(d.dps) || 30;
            p.bleedInterval = tickInt;
            p.lastBleedTick = nowMs();
            if (io && p.socketId) io.to(p.socketId).emit('statusEffectsSync', { bleed: bleedDur });
            notify(`🩸 ¡${who} te hizo sangrar! Perdiendo ${p.bleedDps} HP cada ${tickInt}ms.`, 'warning');
            return true;
        }

        // ----------------------------------------------------------------------------------
        // VENENO - mismo esquema que sangrado pero con flag propio
        // ----------------------------------------------------------------------------------
        case 'poison': {
            const poisonDur = dur(d.duration, 4000);
            const tickInt = dur(d.tickInterval, 1000);
            p.isPoisoned = true;
            p.poisonEndTime = nowMs() + poisonDur;
            p.poisonDps = Number(d.dps) || 20;
            p.poisonInterval = tickInt;
            p.lastPoisonTick = nowMs();
            if (io && p.socketId) io.to(p.socketId).emit('statusEffectsSync', { poison: poisonDur });
            notify(`🤢 ¡${who} te envenenó! Perdiendo ${p.poisonDps} HP cada ${tickInt}ms.`, 'warning');
            return true;
        }

        // ----------------------------------------------------------------------------------
        // PARÁLISIS - bloquea todo (movimiento + casteo + acciones)
        // ----------------------------------------------------------------------------------
        case 'stun': {
            const stunDur = dur(d.duration, 1500);
            p.isStunned = true;
            p.stunEndTime = nowMs() + stunDur;
            if (io && p.socketId) io.to(p.socketId).emit('stunState', { active: true, duration: stunDur });
            notify(`⚡ ¡${who} te paralizó!`, 'error');
            return true;
        }

        // ----------------------------------------------------------------------------------
        // RALENTIZACIÓN - fija (px/s) o porcentual (%)
        // ----------------------------------------------------------------------------------
        case 'slow': {
            const slowDur = dur(d.duration, 2500);
            const slowAmt = Number(d.amount) || 50;
            const isPct = d.isPercentage !== false;
            p.isSlowed = true;
            p.slowEndTime = nowMs() + slowDur;
            p.slowPoints = slowAmt;
            p.slowIsPercentage = isPct;
            p.lastSlowTime = nowMs();
            if (io && p.socketId) {
                io.to(p.socketId).emit('slowState', {
                    active: true, amount: slowAmt, isPercentage: isPct, duration: slowDur
                });
            }
            notify(`🐢 ¡${who} te ralentizó! Velocidad reducida en ${slowAmt}${isPct ? '%' : ' px/s'}.`, 'warning');
            return true;
        }

        // ----------------------------------------------------------------------------------
        // INMOVILIZACIÓN (ROOT) - solo bloquea el movimiento.
        // NO cancela casteos en curso ni impide disparar/usar skills.
        // Opcionalmente puede hacer daño por tick mientras dura (d.dps + d.tickInterval).
        // ----------------------------------------------------------------------------------
        case 'root': {
            const rootDur = dur(d.duration, 3000);
            p.isRooted = true;
            p.rootEndTime = nowMs() + rootDur;
            // Daño por tick opcional mientras está enraizado
            const rootDps = Number(d.dps) || 0;
            if (rootDps > 0) {
                p.rootDps = rootDps;
                p.rootInterval = dur(d.tickInterval, 1000);
                p.lastRootTick = nowMs();
            } else {
                p.rootDps = 0;
                p.rootInterval = 0;
                p.lastRootTick = 0;
            }
            if (io && p.socketId) io.to(p.socketId).emit('rootState', { active: true, duration: rootDur });
            notify(`🌱 ¡${who} te enraizó! No podés moverte durante ${Math.round(rootDur / 1000)}s.`, 'error');
            return true;
        }

        // ----------------------------------------------------------------------------------
        // SILENCIO - bloquea disparos y habilidades hasta silencedUntil.
        // silencedUntil es la fuente de verdad (isSilenced es solo un flag corto).
        // ----------------------------------------------------------------------------------
        case 'silence': {
            const silenceDur = dur(d.duration, 3000);
            p.isSilenced = true;
            p.silencedUntil = nowMs() + silenceDur;
            p.lastSilenceTime = nowMs();
            if (io && p.socketId) io.to(p.socketId).emit('silenceState', { active: true, duration: silenceDur });
            notify(`🔇 ¡${who} te silenció! No podés disparar ni usar skills por ${Math.round(silenceDur / 1000)}s.`, 'error');
            return true;
        }

        default:
            return false;
    }
}

/**
 * Aplica una lista de debuffs (mech.debuffsList) sobre un jugador.
 * Respeta las protecciones de invulnerabilidad/dimensión por entrada.
 * @returns {number} cantidad de debuffs aplicados
 */
function applyDebuffsList(p, debuffsList, io, source) {
    if (!p || !Array.isArray(debuffsList) || debuffsList.length === 0) return 0;
    let applied = 0;
    for (const d of debuffsList) {
        if (applyDebuff(p, d, io, source)) applied++;
    }
    return applied;
}

/**
 * Limpia TODO estado alterado de un jugador (respawn / cambio de zona / muerte).
 * Cubre los debuffs clásicos + los nuevos root y silence.
 */
function clearAllDebuffs(p) {
    if (!p) return;
    p.isBleeding = false; p.bleedEndTime = 0; p.bleedDps = 0; p.bleedInterval = 0; p.lastBleedTick = 0;
    p.isPoisoned = false; p.poisonEndTime = 0; p.poisonDps = 0; p.poisonInterval = 0; p.lastPoisonTick = 0;
    p.isStunned = false; p.stunEndTime = 0;
    p.isSlowed = false; p.slowPoints = 0; p.slowEndTime = 0; p.slowIsPercentage = false; p.lastSlowTime = 0;
    p.isFrozen = false; p.freezeEndTime = 0;
    p.isFeared = false; p.fearEndTime = 0;
    p.isPolymorphed = false; p.polyEndTime = 0;
    p.polyCanMove = true; p.polyCanUseSkills = true;
    p.forcedTarget = null; p.tauntEndTime = 0;
    // NUEVOS
    p.isRooted = false; p.rootEndTime = 0; p.rootDps = 0; p.rootInterval = 0; p.lastRootTick = 0;
    p.isSilenced = false; p.silencedUntil = 0; p.lastSilenceTime = 0;
}

module.exports = {
    applyDebuff,
    applyDebuffsList,
    clearAllDebuffs
};
