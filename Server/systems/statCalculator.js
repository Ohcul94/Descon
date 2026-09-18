/**
 * statCalculator.js
 * Calcula las estadísticas finales de un jugador sumando base + ítems + talentos.
 * v2.0: Soporte dinámico para árbol visual de talentos.
 */
const security = require('../utils/security');

/**
 * Calcula los bonuses de talentos desde el skillTree y talentsConfig.
 * Todos los valores se guardan como decimal (0.02 = 2% por nivel).
 */
function getTalentBonuses(skillTree, talentsConfig) {
    const bonuses = {
        hp_pct: 0, sh_pct: 0, dmg_pct: 0, speed_pct: 0,
        hp_regen: 0, shield_regen: 0, armor_pct: 0,
        energy_efficiency: 0, stability: 0,
        crit_chance: 0, crit_dmg: 0,
        fire_rate_pct: 0, evasion_pct: 0,
        cooldown_reduction: 0, cooldown_reduction_flat: 0,
        cast_time_reduction: 0, cast_time_reduction_flat: 0,
        ignore_shield_pct: 0, accuracy_pct: 0,
        ammo_bonus_pct: 0, laser_dmg_pct: 0,
        repair_cost_reduction: 0, minimap_range: 0,
        ohcu_kill_bonus: 0, shop_discount: 0,
        group_bonus: 0, boss_loot_bonus: 0,
        dash_distance: 0
    };

    // Asegurar que skillTree tenga arrays para todas las categorías conocidas
    const talentsConfig2 = talentsConfig || {};
    const categories = talentsConfig2.categories || [];
    const tree = skillTree || {};
    categories.forEach(c => {
        if (!tree[c.id] || !Array.isArray(tree[c.id])) {
            tree[c.id] = [0,0,0,0,0,0,0,0];
        }
    });

    if (!talentsConfig2.talents || !Array.isArray(talentsConfig2.talents)) {
        return bonuses;
    }

    const talents = talentsConfig2.talents;
    for (const t of talents) {
        const cat = t.category || '';
        const branch = tree[cat] || [];
        const talentsInCat = talents.filter(x => x.category === cat);
        const idx = talentsInCat.indexOf(t);
        if (idx === -1 || idx >= branch.length) continue;
        const lvl = branch[idx] || 0;
        if (lvl <= 0) continue;
        const effects = t.effects || {};
        for (const [key, val] of Object.entries(effects)) {
            if (bonuses.hasOwnProperty(key)) {
                bonuses[key] += val * lvl;
            }
        }
    }

    return bonuses;
}

function calculateFinalStats(player, config) {
    if (!player || !config) return;

    const isAdmin = !!(player.isAdmin || security.isAdmin(player.user));

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

    // 2. Sumar ítems equipados y modificadores
    let itemHp = 0;
    let itemShield = 0;
    let itemSpeed = 0;
    let hpModFlat = 0;
    let hpModPct = 0;
    let speedModFlat = 0;
    let speedModPct = 0;
    let shieldModFlat = 0;
    let shieldModPct = 0;

    function readMod(item, fieldName, masterList) {
        if (masterList) {
            const master = masterList.find(m => String(m.id) === String(item.id));
            if (master && master.hidden && !isAdmin) return { val: 0, type: 'percent' };
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

    function isHiddenItem(item, masterList) {
        if (!masterList) return false;
        const master = masterList.find(m => String(m.id) === String(item.id));
        return !!(master && master.hidden && !isAdmin);
    }

    if (player.equipped) {
        if (Array.isArray(player.equipped.w)) {
            const masterWeapons = config?.shopItems?.weapons;
            player.equipped.w.forEach(item => {
                if (isHiddenItem(item, masterWeapons)) return;
                const sp = readMod(item, 'speedMod', masterWeapons);
                if (sp.type === 'flat') speedModFlat += sp.val;
                else speedModPct += sp.val;
                const hp = readMod(item, 'hpMod', masterWeapons);
                if (hp.type === 'flat') hpModFlat += hp.val;
                else hpModPct += hp.val;
            });
        }
        if (Array.isArray(player.equipped.s)) {
            const masterShields = config?.shopItems?.shields;
            player.equipped.s.forEach(item => {
                if (isHiddenItem(item, masterShields)) return;
                itemShield += (Number(item.base) || 0);
                const hp = readMod(item, 'hpMod', masterShields);
                if (hp.type === 'flat') hpModFlat += hp.val;
                else hpModPct += hp.val;
                const sp = readMod(item, 'speedMod', masterShields);
                if (sp.type === 'flat') speedModFlat += sp.val;
                else speedModPct += sp.val;
            });
        }
        if (Array.isArray(player.equipped.e)) {
            const masterEngines = config?.shopItems?.engines;
            player.equipped.e.forEach(item => {
                if (isHiddenItem(item, masterEngines)) return;
                itemSpeed += (Number(item.base) || 0);
                const sh = readMod(item, 'shieldMod', masterEngines);
                if (sh.type === 'flat') shieldModFlat += sh.val;
                else shieldModPct += sh.val;
                const hp = readMod(item, 'hpMod', masterEngines);
                if (hp.type === 'flat') hpModFlat += hp.val;
                else hpModPct += hp.val;
            });
        }
        if (Array.isArray(player.equipped.x)) {
            const masterExtras = config?.shopItems?.extra;
            player.equipped.x.forEach(item => {
                if (isHiddenItem(item, masterExtras)) return;
                itemHp += (Number(item.base) || 0);
            });
        }
    }

    // 3. Bonificaciones de Talentos (dinámico desde config)
    const talentsConfig = config?.talentsConfig;
    const skillTree = player.skillTree || {};
    const talentBonuses = getTalentBonuses(skillTree, talentsConfig);

    // 4. Aplicar Modificadores de Equipamiento
    const hpModMult = 1.0 + (hpModPct / 100);
    const speedModMult = 1.0 + (speedModPct / 100);
    const shieldModMult = 1.0 + (shieldModPct / 100);

    // 5. Calcular Totales Finales (base + items) * (1 + talent_bonus) * (1 + item_mod)
    player.maxHp = Math.round((baseHp + itemHp + hpModFlat) * (1.0 + talentBonuses.hp_pct) * hpModMult);
    player.maxShield = Math.round((baseShield + itemShield + shieldModFlat) * (1.0 + talentBonuses.sh_pct) * shieldModMult);
    
    let currentSpeed = (baseSpeed + itemSpeed + speedModFlat) * speedModMult * (1.0 + talentBonuses.speed_pct);
    if (player.electronSpeedBuffEndTime && player.electronSpeedBuffEndTime > Date.now()) {
        const bonusPct = (player.electronSpeedBuffPct || 0) / 100;
        const stacks = player.electronSpeedBuffStacks || 1;
        currentSpeed = currentSpeed * (1.0 + (bonusPct * stacks));
    }
    player.speed = Math.round(currentSpeed);

    // 6. Guardar talent bonuses para uso en gameLoop (regen, etc.)
    player._talentBonuses = talentBonuses;

    // Sanity Check
    if (player.hp > player.maxHp) player.hp = player.maxHp;
    if (player.shield > player.maxShield) player.shield = player.maxShield;

    player.baseHp = baseHp;
    player.baseShield = baseShield;
}

module.exports = { calculateFinalStats, getTalentBonuses };
