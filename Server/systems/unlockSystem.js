/**
 * unlockSystem.js
 * Sistema de Desbloqueos (Unlocks) v600.0
 * Permite que las recompensas de misiones habiliten contenido:
 *   - map    -> key "map:2"          (acceso a portal/sector)
 *   - item   -> key "item:w_laser_1" (uso de objeto/arma/equipo)
 *   - skill  -> key "skill:Provocación" (uso de habilidad)
 *   - talent -> key "talent:combat:0"   (invertir en talento)
 *   - generic-> key "generic:custom"    (personalizado para el futuro)
 */

// Construye la clave canónica de desbloqueo
function buildUnlockKey(type, targetId) {
    const t = String(type || 'generic').toLowerCase().trim();
    const id = String(targetId || '').trim();
    if (t === 'talent') {
        // El targetId viene como "categoria:indice" (ej: "combat:3")
        return 'talent:' + id;
    }
    if (t === 'map') return 'map:' + id;
    if (t === 'item') return 'item:' + id;
    if (t === 'skill') return 'skill:' + id;
    return 'generic:' + id;
}

// Obtiene el array de desbloqueos del usuario
function getUnlocks(user) {
    if (!user || !user.gameData) return [];
    if (!Array.isArray(user.gameData.unlocks)) {
        user.gameData.unlocks = [];
    }
    return user.gameData.unlocks;
}

// Verifica si el usuario posee una clave de desbloqueo
function hasUnlock(user, key) {
    const unlocks = getUnlocks(user);
    const needle = String(key || '').trim();
    if (!needle) return true;
    return unlocks.some(k => String(k).trim() === needle);
}

// Otorga desbloqueos declarados en la recompensa de una misión.
// reward.unlocks = [ { type, targetId, label }, ... ]
// Devuelve el array de desbloqueos nuevos otorgados (con su label para notificación).
function grantUnlockRewards(user, unlocks) {
    const granted = [];
    if (!Array.isArray(unlocks) || unlocks.length === 0) return granted;

    const current = getUnlocks(user);
    const already = new Set(current.map(k => String(k).trim()));

    for (const u of unlocks) {
        if (!u || typeof u !== 'object') continue;
        const type = String(u.type || 'generic').toLowerCase().trim();
        const targetId = String(u.targetId || '').trim();
        if (!targetId) continue;

        const key = buildUnlockKey(type, targetId);
        if (already.has(key)) continue;

        current.push(key);
        already.add(key);
        granted.push({
            key: key,
            type: type,
            targetId: targetId,
            label: String(u.label || key)
        });
    }

    user.gameData.unlocks = current;
    return granted;
}

module.exports = {
    buildUnlockKey,
    getUnlocks,
    hasUnlock,
    grantUnlockRewards
};