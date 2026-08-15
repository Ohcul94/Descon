// v400.0: Sistema de Requisitos de Equipamiento
// Cada ítem/habilidad puede declarar un array `requirements` en su master config:
//   [
//     { "type": "level", "min": 10 },
//     { "type": "quest_completed", "questId": "quest_1" }
//   ]
// TODAS las condiciones deben cumplirse (AND). Ítems sin `requirements` = sin restricción.

function getAmmoMasterConfig(itemId, serverConfig) {
    const id = (itemId || "").toLowerCase();
    const ammo = (serverConfig && serverConfig.shopItems && serverConfig.shopItems.ammo) || {};
    for (let sub in ammo) {
        const list = ammo[sub];
        if (!Array.isArray(list)) continue;
        const found = list.find(a => a && String(a.id).toLowerCase() === id);
        if (found) return found;
    }
    return null;
}

function getMasterItemConfig(itemId, serverConfig) {
    const id = (itemId || "").toLowerCase();
    if (id.startsWith('am_')) {
        return getAmmoMasterConfig(itemId, serverConfig);
    }
    if (id.startsWith('mat_')) {
        return (serverConfig.shopItems?.resources || []).find(r => r.id === itemId);
    }
    if (id.startsWith('recipe_')) {
        return (serverConfig.craftingRecipes || []).find(r => r.id === itemId);
    }
    const allShopItems = [
        ...(serverConfig.shopItems?.weapons || []),
        ...(serverConfig.shopItems?.shields || []),
        ...(serverConfig.shopItems?.engines || []),
        ...(serverConfig.shopItems?.extra || []),
        ...(serverConfig.shopItems?.resources || [])
    ];
    let found = allShopItems.find(item => item.id === itemId);
    if (found) return found;

    return (serverConfig.craftingRecipes || []).find(r => r.id === itemId);
}

function getSkillMasterConfig(skillName, serverConfig) {
    const skills = (serverConfig && serverConfig.skillsData) || {};
    if (!skillName) return null;
    const needle = String(skillName).toUpperCase().trim().replace(/Ó/g, 'O').replace(/É/g, 'E').replace(/Í/g, 'I').replace(/Á/g, 'A').replace(/Ú/g, 'U').replace(/Ü/g, 'U');
    for (let key in skills) {
        const keyNorm = String(key).toUpperCase().trim().replace(/Ó/g, 'O').replace(/É/g, 'E').replace(/Í/g, 'I').replace(/Á/g, 'A').replace(/Ú/g, 'U').replace(/Ü/g, 'U');
        if (keyNorm === needle) return { name: key, config: skills[key] };
    }
    return null;
}

function checkRequirements(p, requirements, serverConfig) {
    if (!requirements || !Array.isArray(requirements) || requirements.length === 0) return { ok: true, msg: '' };
    if (!p) return { ok: false, msg: 'Datos de jugador no disponibles.' };

    for (const req of requirements) {
        if (!req || typeof req !== 'object') continue;
        const type = String(req.type || '').toLowerCase();

        if (type === 'level') {
            const min = parseInt(req.min);
            if (!isNaN(min) && (p.level || 1) < min) {
                return { ok: false, msg: `REQUIERE NIVEL ${min}` };
            }
        } else if (type === 'quest_completed') {
            const questId = String(req.questId || '');
            if (!questId) continue;
            const completed = (p.quests && Array.isArray(p.quests.completed)) ? p.quests.completed : [];
            const has = completed.some(id => String(id) === questId);
            if (!has) {
                const questName = (serverConfig && serverConfig.questsConfig || []).find(q => String(q.id) === questId);
                return { ok: false, msg: `REQUIERE MISIÓN COMPLETADA: ${questName ? questName.name : questId}` };
            }
        } else if (type === 'unlock') {
            // v600.0: Desbloqueo otorgado por misión (ej: key "item:w_laser_1", "skill:Provocación")
            const key = String(req.key || '');
            if (!key) continue;
            const unlocks = (p.unlocks && Array.isArray(p.unlocks)) ? p.unlocks : [];
            const has = unlocks.some(k => String(k) === key);
            if (!has) {
                const label = req.label || key;
                return { ok: false, msg: `REQUIERE DESBLOQUEO: ${label}` };
            }
        }
        // Tipos desconocidos se ignoran (retrocompatibilidad)
    }
    return { ok: true, msg: '' };
}

module.exports = { getMasterItemConfig, getAmmoMasterConfig, getSkillMasterConfig, checkRequirements };