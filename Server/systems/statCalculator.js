/**
 * statCalculator.js
 * Calcula las estadísticas finales de un jugador sumando base + ítems + habilidades.
 */

function calculateFinalStats(player, config) {
    if (!player || !config) return;

    // 1. Obtener Base de la Nave
    const shipId = player.currentShipId || 1;
    const model = config.shipModels.find(m => m.id === shipId);
    
    let baseHp = 2000;
    let baseShield = 1000;
    let baseSpeed = 400;

    if (model) {
        baseHp = model.hp || 2000;
        baseShield = model.shield || 1000;
        baseSpeed = model.speed || 400;
    }

    // 2. Sumar ítems equipados y modificadores (porcentuales y planos)
    let itemHp = 0;
    let itemShield = 0;
    let itemSpeed = 0;
    let hpModFlat = 0;       // de Armas (w) y Motores (e), tipo "flat"
    let hpModPct = 0;        // de Armas (w) y Motores (e), tipo "percent"
    let speedModFlat = 0;    // de Armas (w) y Motores (e), tipo "flat"
    let speedModPct = 0;     // de Armas (w) y Motores (e), tipo "percent"
    let shieldModFlat = 0;   // de Escudos (s), tipo "flat"
    let shieldModPct = 0;    // de Escudos (s), tipo "percent"

    // Helper para leer modificador desde el ítem o desde el master config (fallback)
    // Solo hace fallback si el campo NO existe en el ítem (ítems viejos pre-cambio)
    function readMod(item, fieldName, masterList) {
        if (masterList) {
            const master = masterList.find(m => String(m.id) === String(item.id));
            if (master && master[fieldName] !== undefined) {
                return {
                    val: Number(master[fieldName]) || 0,
                    type: master[fieldName + 'Type'] || 'percent'
                };
            }
        }
        if (item.hasOwnProperty(fieldName) || item[fieldName] !== undefined) {
            return {
                val: Number(item[fieldName]) || 0,
                type: item[fieldName + 'Type'] || 'percent'
            };
        }
        return { val: 0, type: 'percent' };
    }

    if (player.equipped) {
        // Armas (Slot 'w') - base ataque | modifica Velocidad y Vida
        if (Array.isArray(player.equipped.w)) {
            const masterWeapons = config?.shopItems?.weapons;
            player.equipped.w.forEach(item => {
                const sp = readMod(item, 'speedMod', masterWeapons);
                if (sp.type === 'flat') speedModFlat += sp.val;
                else speedModPct += sp.val;
                const hp = readMod(item, 'hpMod', masterWeapons);
                if (hp.type === 'flat') hpModFlat += hp.val;
                else hpModPct += hp.val;
            });
        }
        // Escudos (Slot 's') - base escudo | modifica Vida y Velocidad
        if (Array.isArray(player.equipped.s)) {
            const masterShields = config?.shopItems?.shields;
            player.equipped.s.forEach(item => {
                itemShield += (Number(item.base) || 0);
                const hp = readMod(item, 'hpMod', masterShields);
                if (hp.type === 'flat') hpModFlat += hp.val;
                else hpModPct += hp.val;
                const sp = readMod(item, 'speedMod', masterShields);
                if (sp.type === 'flat') speedModFlat += sp.val;
                else speedModPct += sp.val;
            });
        }
        // Motores (Slot 'e') - base velocidad | modifica Escudo y Vida
        if (Array.isArray(player.equipped.e)) {
            const masterEngines = config?.shopItems?.engines;
            player.equipped.e.forEach(item => {
                itemSpeed += (Number(item.base) || 0);
                const sh = readMod(item, 'shieldMod', masterEngines);
                if (sh.type === 'flat') shieldModFlat += sh.val;
                else shieldModPct += sh.val;
                const hp = readMod(item, 'hpMod', masterEngines);
                if (hp.type === 'flat') hpModFlat += hp.val;
                else hpModPct += hp.val;
            });
        }
        // Módulos extra (Slot 'x') - base vida
        if (Array.isArray(player.equipped.x)) {
            player.equipped.x.forEach(item => {
                itemHp += (Number(item.base) || 0);
            });
        }
    }

    // 3. Aplicar Bonificaciones de Habilidades (Skill Tree)
    // Engineering[0] = HP %, Engineering[1] = Shield %
    const eng = player.skillTree?.engineering || [0, 0, 0, 0, 0, 0, 0, 0];
    const hpBonus = 1.0 + ((eng[0] || 0) * 0.02); // 2% por punto
    const shBonus = 1.0 + ((eng[1] || 0) * 0.02); // 2% por punto

    // 4. Aplicar Modificadores de Equipamiento (flat y percent)
    const hpModMult = 1.0 + (hpModPct / 100);
    const speedModMult = 1.0 + (speedModPct / 100);
    const shieldModMult = 1.0 + (shieldModPct / 100);

    // 5. Calcular Totales Finales
    player.maxHp = Math.round((baseHp + itemHp + hpModFlat) * hpBonus * hpModMult);
    player.maxShield = Math.round((baseShield + itemShield + shieldModFlat) * shBonus * shieldModMult);
    
    let currentSpeed = (baseSpeed + itemSpeed + speedModFlat) * speedModMult;
    if (player.electronSpeedBuffEndTime && player.electronSpeedBuffEndTime > Date.now()) {
        const bonusPct = (player.electronSpeedBuffPct || 0) / 100;
        const stacks = player.electronSpeedBuffStacks || 1;
        currentSpeed = Math.round(currentSpeed * (1.0 + (bonusPct * stacks)));
    }
    player.speed = Math.round(currentSpeed);

    // Sanity Check: Mantener vida actual dentro de los límites
    if (player.hp > player.maxHp) player.hp = player.maxHp;
    if (player.shield > player.maxShield) player.shield = player.maxShield;

    // Guardar bases para referencia si es necesario
    player.baseHp = baseHp;
    player.baseShield = baseShield;
}

module.exports = { calculateFinalStats };
