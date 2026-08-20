// v400.0: Sistema de Requisitos de Equipamiento
// Cada ítem/habilidad puede declarar un array `requirements` en su master config:
//   [
//     { "type": "level", "min": 10 },
//     { "type": "quest_completed", "questId": "quest_1" },
//     { "type": "spheres", "esferas": [ { "color": "verde", "count": 2 }, { "color": "azul", "count": 1 } ] }
//   ]
// TODAS las condiciones deben cumplirse (AND). Ítems sin `requirements` = sin restricción.
// v650.0: Nuevo tipo `spheres` — el piloto debe tener equipadas N esferas de determinados
// colores (mezcla dinámica de 1 a 4 esferas, en cualquier orden/color).
// El color de cada esfera se deriva del tipo de habilidad equipada en ese slot:
//   Ataque → Roja | Defensa → Azul | Curación → Verde | Utilidad/Movimiento → Amarilla

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
        } else if (type === 'spheres') {
            // v650.0: Esferas de colores. Formato:
            //   { "type": "spheres", "esferas": [ { "color": "verde", "count": 2 }, { "color": "azul", "count": 1 } ] }
            // El piloto debe tener AL MENOS esas esferas de cada color entre sus 4 slots orbitales.
            const needed = Array.isArray(req.esferas) ? req.esferas : [];
            if (!needed.length) continue; // Sin esferas configuradas → condición ignorada
            const counts = countPlayerSphereColors(p.spheres);
            
            // Agrupar y sumar requisitos por color para evitar bypass cuando se pide el mismo color varias veces
            const summedNeeded = {};
            for (const n of needed) {
                if (!n || typeof n !== 'object') continue;
                const color = normalizeSphereColor(n.color);
                const count = parseInt(n.count);
                if (!color || isNaN(count) || count <= 0) continue;
                summedNeeded[color] = (summedNeeded[color] || 0) + count;
            }

            let anyReal = false;
            for (const color in summedNeeded) {
                anyReal = true;
                const count = summedNeeded[color];
                if ((counts[color] || 0) < count) {
                    return { ok: false, msg: `REQUIERE ${buildSphereRequirementMsg(needed)}` };
                }
            }
            if (!anyReal) continue; // Requisito mal formado → se ignora (retrocompatibilidad)
        }
        // Tipos desconocidos se ignoran (retrocompatibilidad)
    }
    return { ok: true, msg: '' };
}

// ============================================================
// v650.0: Esferas de colores (requisito de equipamiento de habilidades)
// El color de una esfera se deriva del tipo de habilidad equipada:
//   Ataque → Roja | Defensa → Azul | Curación → Verde | Utilidad/Movimiento → Amarilla
// También se respeta un `type` explícito en la esfera si coincide con un color conocido.
// ============================================================
const SPHERE_COLOR_ALIASES = {
    'roja': 'roja', 'rojo': 'roja', 'red': 'roja',
    'azul': 'azul', 'blue': 'azul',
    'verde': 'verde', 'green': 'verde',
    'amarilla': 'amarilla', 'amarillo': 'amarilla', 'yellow': 'amarilla'
};

function normalizeSphereColor(raw) {
    if (!raw) return '';
    const n = String(raw).toLowerCase().trim()
        .replace(/ó/g, 'o').replace(/é/g, 'e').replace(/í/g, 'i').replace(/á/g, 'a').replace(/ú/g, 'u').replace(/ü/g, 'u');
    return SPHERE_COLOR_ALIASES[n] || '';
}

function sphereColorFromSkillType(skillType) {
    const t = String(skillType || '').toLowerCase()
        .replace(/ó/g, 'o').replace(/é/g, 'e').replace(/í/g, 'i').replace(/á/g, 'a').replace(/ú/g, 'u').replace(/ü/g, 'u');
    if (t === 'ataque') return 'roja';
    if (t === 'defensa') return 'azul';
    if (t === 'curacion') return 'verde';
    return 'amarilla'; // Utilidad / Movimiento / cualquier otro tipo
}

function getSphereColor(sphere) {
    if (!sphere || typeof sphere !== 'object') return '';
    // 0) v760.0: Esfera FÍSICA instalada en el slot (ítem crafteado) — fuente de verdad del color
    if (sphere.sphere && typeof sphere.sphere === 'object') {
        const installed = normalizeSphereColor(sphere.sphere.type || sphere.sphere.sphereColor || '');
        if (installed) return installed;
    }
    // 1) Tipo explícito de la esfera (futuro: esferas teñidas de un color fijo)
    const explicit = normalizeSphereColor(sphere.type);
    if (explicit) return explicit;
    // 2) Color derivado del tipo de habilidad equipada en ese slot
    if (sphere.equipped && typeof sphere.equipped === 'object' && sphere.equipped.type) {
        return sphereColorFromSkillType(sphere.equipped.type);
    }
    return '';
}

function countPlayerSphereColors(spheres) {
    const counts = {};
    if (!Array.isArray(spheres)) return counts;
    for (const s of spheres) {
        const c = getSphereColor(s);
        if (c) counts[c] = (counts[c] || 0) + 1;
    }
    return counts;
}

const SPHERE_COLOR_LABELS = { 'roja': 'ROJA', 'azul': 'AZUL', 'verde': 'VERDE', 'amarilla': 'AMARILLA' };

function sphereColorLabel(color, count) {
    const single = SPHERE_COLOR_LABELS[color] || color.toUpperCase();
    const plural = color === 'azul' ? 'AZULES' : single + 'S';
    return `${count} ESFERA${count > 1 ? 'S' : ''} ${count > 1 ? plural : single}`;
}

// Construye el mensaje respetando el orden en que se configuraron los colores:
//   "2 ESFERAS VERDES Y 1 AZUL" | "3 ESFERAS VERDES" | "1 ESFERA ROJA"
function buildSphereRequirementMsg(needed) {
    const summed = {};
    const order = []; // Mantener el orden de aparición original
    for (const n of needed) {
        if (!n || typeof n !== 'object') continue;
        const color = normalizeSphereColor(n.color);
        const count = parseInt(n.count);
        if (!color || isNaN(count) || count <= 0) continue;
        if (summed[color] === undefined) {
            summed[color] = 0;
            order.push(color);
        }
        summed[color] += count;
    }

    const parts = [];
    for (const color of order) {
        const count = summed[color];
        parts.push(sphereColorLabel(color, count));
    }
    if (!parts.length) return 'ESFERAS DE COLORES';
    if (parts.length === 1) return parts[0];
    return parts.slice(0, -1).join(', ') + ' Y ' + parts[parts.length - 1];
}

module.exports = { getMasterItemConfig, getAmmoMasterConfig, getSkillMasterConfig, checkRequirements, getSphereColor, countPlayerSphereColors, normalizeSphereColor, sphereColorFromSkillType };