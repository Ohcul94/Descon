/**
 * entitySanitizer.js
 * Sanitizador centralizado de entidades (Players y Enemies) para Socket.IO.
 * 
 * Previene circular references (ThreatTable, AI, State, Timers), fugas de memoria
 * y el crash crítico de Node.js "RangeError: Maximum call stack size exceeded" en socket.io-parser.
 */

const getStatusEffects = (ent) => {
    if (!ent) return {};
    const now = Date.now();
    return {
        slowed: !!(ent.isSlowed || (ent.slowEndTime && now < ent.slowEndTime)),
        stunned: !!(ent.isStunned || (ent.stunEndTime && now < ent.stunEndTime)),
        bleeding: !!(ent.isBleeding || (ent.bleedEndTime && now < ent.bleedEndTime)),
        poisoned: !!(ent.isPoisoned || (ent.poisonEndTime && now < ent.poisonEndTime)),
        frozen: !!(ent.isFrozen || (ent.freezeEndTime && now < ent.freezeEndTime)),
        feared: !!(ent.isFeared || (ent.fearEndTime && now < ent.fearEndTime)),
        provoked: !!(ent.forcedTarget && ent.tauntEndTime && now < ent.tauntEndTime),
        polymorphed: !!(ent.isPolymorphed || (ent.polyEndTime && now < ent.polyEndTime)),
        rooted: !!(ent.isRooted || (ent.rootEndTime && now < ent.rootEndTime)),
        silenced: !!(ent.isSilenced || (ent.silencedUntil && now < ent.silencedUntil))
    };
};

const getCleanPlayerData = (p, id) => {
    if (!p) return null;
    try {
        const pId = String(id || p.id || p.socketId || '');
        return JSON.parse(JSON.stringify({
            id: pId,
            socketId: p.socketId || pId,
            user: p.user || 'Unknown',
            x: Number(p.x) || 0,
            y: Number(p.y) || 0,
            rotation: Number(p.rotation) || 0,
            hp: Number(p.hp) || 0,
            maxHp: Number(p.maxHp) || 2000,
            sh: (p.sh !== undefined) ? Number(p.sh) : Number(p.shield || 0),
            maxSh: (p.maxSh !== undefined) ? Number(p.maxSh) : Number(p.maxShield || 1000),
            zone: p.zone,
            spheres: Array.isArray(p.spheres) ? p.spheres : [],
            status_effects: Object.assign(getStatusEffects(p), p.status_effects || {}),
            clanTag: p.clanTag || "",
            clanId: p.clanId || null,
            currentShipId: p.currentShipId || 1,
            speed: Number(p.speed) || 300,
            pvpEnabled: !!p.pvpEnabled,
            isInvulnerable: !!p.isInvulnerable,
            isDead: !!p.isDead
        }));
    } catch (e) {
        console.error("[entitySanitizer] Error al sanitizar player data:", e);
        return null;
    }
};

const getCleanEnemyData = (e, id) => {
    if (!e) return null;
    try {
        const eId = String(id || e.id || '');
        return JSON.parse(JSON.stringify({
            id: eId,
            name: e.name || 'Enemy',
            type: e.type,
            x: Number(e.x) || 0,
            y: Number(e.y) || 0,
            rotation: Number(e.rotation) || 0,
            hp: Number(e.hp) || 0,
            maxHp: Number(e.maxHp) || 1000,
            sh: (e.sh !== undefined) ? Number(e.sh) : Number(e.shield || 0),
            shield: (e.shield !== undefined) ? Number(e.shield) : Number(e.sh || 0),
            maxShield: (e.maxShield !== undefined) ? Number(e.maxShield) : Number(e.maxSh || 0),
            maxSh: (e.maxSh !== undefined) ? Number(e.maxSh) : Number(e.maxShield || 0),
            zone: e.zone,
            status_effects: Object.assign(getStatusEffects(e), e.status_effects || {}),
            isDead: !!e.isDead,
            isBoss: !!e.isBoss,
            isInvulnerable: !!e.isInvulnerable
        }));
    } catch (err) {
        console.error("[entitySanitizer] Error al sanitizar enemy data:", err);
        return null;
    }
};

module.exports = {
    getStatusEffects,
    getCleanPlayerData,
    getCleanEnemyData
};
