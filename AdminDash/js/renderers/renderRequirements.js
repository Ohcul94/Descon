// AdminDash/js/renderers/renderRequirements.js
// v400.0: Sistema de Requisitos de Equipamiento (nivel, misiones completadas, desbloqueos)
// Cada ítem/habilidad soporta un array `requirements` con condiciones que TODAS deben cumplirse (AND).
const REQUIREMENTS_TYPES = [
    { value: 'level', label: 'Nivel mínimo' },
    { value: 'quest_completed', label: 'Misión completada' },
    { value: 'unlock', label: 'Desbloqueo especial' },
    { value: 'spheres', label: 'Esferas de colores' }
];
const REQ_SECTIONS = {};

function reqAttrEscape(str) {
    return String(str).replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/</g, '&lt;');
}
function reqSectionIdSanitize(id) {
    return String(id).replace(/[^a-zA-Z0-9_-]/g, '_');
}
function reqGetItem(secId) {
    const expr = REQ_SECTIONS[secId];
    if (!expr) return null;
    try { return eval(expr); } catch (e) { return null; }
}
function reqAdd(secId) {
    let item = reqGetItem(secId);
    const expr = REQ_SECTIONS[secId];
    if (!item && expr) {
        try { eval(expr + ' = {}'); item = reqGetItem(secId); } catch (e) { return; }
    }
    if (!item) return;
    if (!Array.isArray(item.requirements)) item.requirements = [];
    item.requirements.push({ type: 'level', min: 1 });
    renderRequirementsSection(secId);
}
function reqRemove(secId, idx) {
    const item = reqGetItem(secId);
    if (!item || !Array.isArray(item.requirements)) return;
    item.requirements.splice(idx, 1);
    renderRequirementsSection(secId);
}
function reqSetType(secId, idx, type) {
    const item = reqGetItem(secId);
    if (!item || !Array.isArray(item.requirements)) return;
    const req = item.requirements[idx];
    req.type = type;
    if (type === 'level') { if (req.min === undefined) req.min = 1; delete req.questId; delete req.key; delete req.label; delete req.esferas; }
    else if (type === 'quest_completed') { if (req.questId === undefined) req.questId = ''; delete req.min; delete req.key; delete req.label; delete req.esferas; }
    else if (type === 'unlock') { if (req.key === undefined) req.key = ''; if (req.label === undefined) req.label = ''; delete req.min; delete req.questId; delete req.esferas; }
    else if (type === 'spheres') { if (!Array.isArray(req.esferas) || req.esferas.length === 0) req.esferas = [{ color: 'verde', count: 1 }]; delete req.min; delete req.questId; delete req.key; delete req.label; }
    renderRequirementsSection(secId);
}
function reqSetValue(secId, idx, key, value) {
    const item = reqGetItem(secId);
    if (!item || !Array.isArray(item.requirements)) return;
    const req = item.requirements[idx];
    if (key === 'min') req.min = parseInt(value) || 1;
    else if (key === 'questId') req.questId = value;
    else if (key === 'key') req.key = value;
    else if (key === 'label') req.label = value;
}

// ============================================================
// v650.0: Editor dinámico de requisito "Esferas de colores"
// El piloto debe tener N esferas de cada color (mezcla libre, 1 a 4 esferas en total).
// Formato generado: { "type": "spheres", "esferas": [ { "color": "verde", "count": 2 }, ... ] }
// ============================================================
const SPHERE_COLOR_OPTIONS = [
    { value: 'verde', label: '🟢 Verde' },
    { value: 'azul', label: '🔵 Azul' },
    { value: 'roja', label: '🔴 Roja' },
    { value: 'amarilla', label: '🟡 Amarilla' }
];
function sphereColorOptions(selected) {
    return SPHERE_COLOR_OPTIONS.map(c => `<option value="${c.value}" ${selected === c.value ? 'selected' : ''}>${c.label}</option>`).join('');
}
function reqSphereTotal(req) {
    return (Array.isArray(req.esferas) ? req.esferas : []).reduce((s, e) => s + (Number(e && e.count) || 0), 0);
}
function reqSetSphere(secId, idx, ei, key, value) {
    const item = reqGetItem(secId);
    if (!item || !Array.isArray(item.requirements)) return;
    const req = item.requirements[idx];
    if (!Array.isArray(req.esferas) || !req.esferas[ei]) return;
    if (key === 'color') req.esferas[ei].color = value;
    else if (key === 'count') req.esferas[ei].count = Math.min(4, Math.max(1, parseInt(value) || 1));
    renderRequirementsSection(secId);
}
function reqAddSphere(secId, idx) {
    const item = reqGetItem(secId);
    if (!item || !Array.isArray(item.requirements)) return;
    const req = item.requirements[idx];
    if (!Array.isArray(req.esferas)) req.esferas = [];
    if (reqSphereTotal(req) >= 4) return; // Máximo 4 esferas (una por slot orbital)
    req.esferas.push({ color: 'verde', count: 1 });
    renderRequirementsSection(secId);
}
function reqRemoveSphere(secId, idx, ei) {
    const item = reqGetItem(secId);
    if (!item || !Array.isArray(item.requirements)) return;
    const req = item.requirements[idx];
    if (!Array.isArray(req.esferas)) return;
    req.esferas.splice(ei, 1);
    if (req.esferas.length === 0) req.esferas = [{ color: 'verde', count: 1 }];
    renderRequirementsSection(secId);
}
function requirementsSpheresFieldHtml(secId, idx, req) {
    const list = Array.isArray(req.esferas) ? req.esferas : [];
    const total = list.reduce((s, e) => s + (Number(e && e.count) || 0), 0);
    let sphereRows = '';
    list.forEach((e, ei) => {
        sphereRows += `
            <div style="display:flex; gap:6px; align-items:center;">
                <select style="width:130px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:2px 4px; font-size:0.68rem;" onchange="reqSetSphere('${secId}', ${idx}, ${ei}, 'color', this.value)">${sphereColorOptions(e && e.color)}</select>
                <select style="width:110px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:2px 4px; font-size:0.68rem;" onchange="reqSetSphere('${secId}', ${idx}, ${ei}, 'count', this.value)">${[1, 2, 3, 4].map(n => `<option value="${n}" ${Number(e && e.count) === n ? 'selected' : ''}>${n} ${n === 1 ? 'esfera' : 'esferas'}</option>`).join('')}</select>
                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:11px;" title="Quitar color" onclick="reqRemoveSphere('${secId}', ${idx}, ${ei})">✕</button>
            </div>`;
    });
    const addBtn = total >= 4
        ? `<button disabled style="background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:not-allowed; border-radius:4px; padding:2px 8px; font-size:0.6rem; opacity:0.4;" title="Máximo 4 esferas (una por slot orbital)">+ ESFERA</button>`
        : `<button style="background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; padding:2px 8px; font-size:0.6rem;" onclick="reqAddSphere('${secId}', ${idx})" title="Agregar otro color">+ ESFERA</button>`;
    return `
        <div style="flex:1; display:flex; flex-direction:column; gap:4px; min-width:240px;">
            ${sphereRows || '<span style="font-size:0.65rem; opacity:0.5;">Sin esferas requeridas.</span>'}
            <div style="display:flex; gap:10px; align-items:center;">
                ${addBtn}
                <span style="font-size:0.6rem; ${total > 4 ? 'color:#ff5555; font-weight:bold;' : 'opacity:0.6;'}" title="Total de esferas exigidas (máx. 4, una por slot orbital)">Total: ${total} / 4 esferas</span>
            </div>
        </div>`;
}
function requirementsTypeOptions(selected) {
    return REQUIREMENTS_TYPES.map(t => `<option value="${t.value}" ${selected === t.value ? 'selected' : ''}>${t.label}</option>`).join('');
}
function requirementsQuestOptions(selectedId) {
    const quests = (typeof config !== 'undefined' && Array.isArray(config.questsConfig)) ? config.questsConfig : [];
    if (!quests.length) return `<option value="">(Sin misiones configuradas)</option>`;
    let html = `<option value="">— Seleccionar misión —</option>`;
    quests.forEach(q => {
        const qid = q.id || '';
        html += `<option value="${reqAttrEscape(qid)}" ${String(selectedId || '') === String(qid) ? 'selected' : ''}>${reqAttrEscape(q.name || qid)} (${reqAttrEscape(qid)})</option>`;
    });
    return html;
}
function requirementsSectionHtml(secId, itemExpr) {
    if (itemExpr !== undefined) REQ_SECTIONS[secId] = itemExpr;
    const item = reqGetItem(secId);
    const reqs = (item && Array.isArray(item.requirements)) ? item.requirements : [];
    let rows = '';
    reqs.forEach((req, idx) => {
        const type = req.type || 'level';
        let valueField = '';
        if (type === 'level') {
            valueField = `<input type="number" min="1" value="${req.min !== undefined ? req.min : 1}" style="width:90px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:2px 4px;" onchange="reqSetValue('${secId}', ${idx}, 'min', this.value)">`;
        } else if (type === 'quest_completed') {
            valueField = `<select style="flex:1; min-width:220px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:2px 4px;" onchange="reqSetValue('${secId}', ${idx}, 'questId', this.value)">${requirementsQuestOptions(req.questId)}</select>`;
        } else if (type === 'unlock') {
            valueField = `
                <input type="text" value="${reqAttrEscape(req.key || '')}" placeholder="Clave: item:w_laser_1 | skill:X | map:2 | talent:combat:0" title="Clave del desbloqueo. La misión debe otorgarla con el mismo tipo y ID." style="flex:1; min-width:180px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:2px 4px; font-size:0.65rem;" onchange="reqSetValue('${secId}', ${idx}, 'key', this.value)">
                <input type="text" value="${reqAttrEscape(req.label || '')}" placeholder="Nombre visible (ej: Cañón de Plasma)" title="Nombre que verá el jugador al intentar usar el objeto" style="flex:1; min-width:120px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:2px 4px; font-size:0.65rem;" onchange="reqSetValue('${secId}', ${idx}, 'label', this.value)">
            `;
        } else if (type === 'spheres') {
            // v650.0: Editor dinámico de esferas (mezcla de colores, 1 a 4 esferas total)
            valueField = requirementsSpheresFieldHtml(secId, idx, req);
        }
        rows += `
            <div style="display:flex; gap:8px; align-items:center; margin-bottom:6px; flex-wrap:wrap;">
                <select style="width:170px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:2px 4px; font-size:0.68rem;" onchange="reqSetType('${secId}', ${idx}, this.value)">${requirementsTypeOptions(type)}</select>
                ${valueField}
                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:11px;" title="Quitar requisito" onclick="reqRemove('${secId}', ${idx})">✕</button>
            </div>`;
    });
    return `
        <div id="${secId}" class="field full" style="margin-top:1rem; padding-top:1rem; border-top:1px solid rgba(255,255,255,0.05); background:rgba(0,0,0,0.12); border-radius:8px; padding:12px;">
            <label style="color:var(--accent); font-size:0.6rem; font-weight:bold; display:flex; align-items:center; gap:5px; margin-bottom:0.8rem; letter-spacing:1px; opacity:0.8;">
                <span style="font-size:10px;">🔒</span> REQUISITOS DE EQUIPAMIENTO
            </label>
            ${rows || '<div style="font-size:0.68rem; opacity:0.45; margin-bottom:6px;">Sin requisitos: cualquier piloto puede equiparlo.</div>'}
            <button class="btn" style="padding:4px 10px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px;" onclick="reqAdd('${secId}')">+ AGREGAR REQUISITO</button>
        </div>`;
}
function renderRequirementsSection(secId) {
    const el = document.getElementById(secId);
    if (!el) return;
    const html = requirementsSectionHtml(secId);
    const tmp = document.createElement('div');
    tmp.innerHTML = html;
    const fresh = tmp.firstElementChild;
    el.replaceWith(fresh);
}

window.renderSearchableEnemySelect = function(currentValue, onChangeCallback, borderCSSColor = 'var(--success)', extraId = '') {
    const currentEn = currentValue ? config.enemyModels[currentValue] : null;
    const currentName = currentEn ? `[ID ${currentValue}] ${currentEn.name}` : (currentValue ? `ID ${currentValue}` : '');
    const dropdownId = `dropdown-select-${extraId}`;
    const inputId = `dropdown-search-${extraId}`;
    const listId = `dropdown-list-${extraId}`;

    // Programar la función de filtrado dinámico en la ventana global de forma única
    window[`filterDropdown_${extraId}`] = function(query) {
        const list = document.getElementById(listId);
        if (!list) return;
        list.innerHTML = '';
        const q = query.toLowerCase();

        for(let id in config.enemyModels) {
            if (id.includes('-')) continue; // Ocultar sub-tiers del primer nivel
            
            const en = config.enemyModels[id];
            const matches = en.name.toLowerCase().includes(q) || id.includes(q);
            if (q && !matches) continue;
            
            const isBoss = parseInt(id) >= 100;
            const row = document.createElement('div');
            row.style.padding = '8px 12px';
            row.style.cursor = 'pointer';
            row.style.borderBottom = '1px solid rgba(255,255,255,0.02)';
            row.style.display = 'flex';
            row.style.flexDirection = 'column';
            row.style.gap = '5px';
            
            row.onmouseenter = () => row.style.background = `${borderCSSColor}1a`;
            row.onmouseleave = () => row.style.background = 'transparent';

            const titleSpan = document.createElement('span');
            titleSpan.innerHTML = `<strong>[ID ${id}]</strong> ${en.name}`;
            titleSpan.style.color = isBoss ? 'var(--accent)' : borderCSSColor;
            titleSpan.style.fontSize = '0.85rem';
            row.appendChild(titleSpan);

            if (isBoss) {
                row.onclick = () => {
                    onChangeCallback(id);
                    document.getElementById(inputId).value = `[ID ${id}] ${en.name}`;
                    list.style.display = 'none';
                };
            } else {
                const tierContainer = document.createElement('div');
                tierContainer.style.display = 'flex';
                tierContainer.style.gap = '6px';
                tierContainer.style.marginTop = '4px';
                tierContainer.style.flexWrap = 'wrap';

                const tiers = [
                    { suffix: '', label: 'Base', val: id },
                    { suffix: '-A', label: 'Tier A', val: `${id}-A` },
                    { suffix: '-B', label: 'Tier B', val: `${id}-B` },
                    { suffix: '-C', label: 'Tier C', val: `${id}-C` },
                    { suffix: '-D', label: 'Tier D', val: `${id}-D` }
                ];

                tiers.forEach(t => {
                    const enModel = config.enemyModels[t.val] || en;
                    const tierName = enModel.name || `${en.name} ${t.label}`;
                    
                    const btn = document.createElement('button');
                    btn.className = 'btn';
                    btn.innerText = t.label;
                    btn.style.padding = '3px 8px';
                    btn.style.fontSize = '0.7rem';
                    btn.style.background = `${borderCSSColor}26`;
                    btn.style.border = `1px solid ${borderCSSColor}4d`;
                    btn.style.color = 'var(--text)';
                    btn.style.cursor = 'pointer';
                    btn.style.borderRadius = '4px';
                    btn.style.transition = 'all 0.15s';
                    
                    btn.onmouseenter = () => {
                        btn.style.background = borderCSSColor;
                        btn.style.color = '#000';
                    };
                    btn.onmouseleave = () => {
                        btn.style.background = `${borderCSSColor}26`;
                        btn.style.color = 'var(--text)';
                    };

                    btn.onclick = (e) => {
                        e.stopPropagation();
                        onChangeCallback(t.val);
                        document.getElementById(inputId).value = `[ID ${t.val}] ${tierName}`;
                        list.style.display = 'none';
                    };

                    tierContainer.appendChild(btn);
                });

                row.appendChild(tierContainer);
            }
            list.appendChild(row);
        }

        if (list.children.length === 0) {
            const noResult = document.createElement('div');
            noResult.innerText = 'No se encontraron enemigos';
            noResult.style.padding = '10px';
            noResult.style.color = '#888';
            noResult.style.fontSize = '0.8rem';
            list.appendChild(noResult);
        }
    };

    // Agregamos un event listener global para cerrar este dropdown específico
    document.addEventListener('click', function(e) {
        const list = document.getElementById(listId);
        const searchInput = document.getElementById(inputId);
        if (list && searchInput && !list.contains(e.target) && e.target !== searchInput) {
            list.style.display = 'none';
        }
    });

    return `
        <div style="position: relative; width: 100%; display: flex; flex-direction: column;">
            <div style="position: relative; display: flex; align-items: center; width: 100%;">
                <input type="text" id="${inputId}" value="${currentName}" 
                       placeholder="🔍 Escribí para filtrar enemigo..." 
                       style="background:#0f172a; color:${borderCSSColor}; font-weight:bold; padding-right: 30px; border: 1px solid ${borderCSSColor}33; width: 100%; border-radius: 8px; outline: none;"
                       onfocus="document.querySelectorAll('.folder-content[id^=dropdown-list-]').forEach(el=>el.style.display='none'); document.getElementById('${listId}').style.display = 'block'; window['filterDropdown_${extraId}'](this.value);"
                       oninput="window['filterDropdown_${extraId}'](this.value);">
                <span style="position: absolute; right: 10px; cursor: pointer; color: ${borderCSSColor}; font-size: 0.8rem;" 
                      onclick="const el = document.getElementById('${listId}'); const cur = el.style.display; document.querySelectorAll('.folder-content[id^=dropdown-list-]').forEach(x=>x.style.display='none'); el.style.display = cur === 'block' ? 'none' : 'block';">▼</span>
            </div>
            
            <div id="${listId}" class="folder-content" 
                 style="display: none; position: absolute; left: 0; right: 0; top: 100%; z-index: 999999; 
                        max-height: 250px; overflow-y: auto; background: #0f172a; border: 1px solid ${borderCSSColor}; 
                        padding: 5px; box-shadow: 0 15px 30px rgba(0,0,0,0.6); margin-top: 5px; border-radius: 8px; width: 100%;">
            </div>
        </div>
    `;
};
window.updateAdPhaseTotal = function(waveIdx, phaseIdx) {
    const wave = config.gameModes.altar_defense.waves[waveIdx];
    if (!wave || !wave.phases || !wave.phases[phaseIdx]) return;
    const ph = wave.phases[phaseIdx];
    
    let totalCount = 0;
    for (let key in ph.spawnerDistribution) {
        totalCount += ph.spawnerDistribution[key] || 0;
    }
    ph.count = totalCount;
    
    const span = document.getElementById(`ad-phase-total-${waveIdx}-${phaseIdx}`);
    if (span) {
        span.innerText = totalCount;
    }
};

window.renderSearchableMapSelect = function(currentValue, onChangeCallback, borderCSSColor = 'var(--primary)', extraId = '') {
    const currentMap = config.mapsConfig[currentValue];
    const currentName = currentMap ? `[ID ${currentValue}] ${currentMap.name}` : `ID ${currentValue}`;
    const dropdownId = `dropdown-select-${extraId}`;
    const inputId = `dropdown-search-${extraId}`;
    const listId = `dropdown-list-${extraId}`;

    // Programar la función de filtrado dinámico en la ventana global de forma única
    window[`filterMapDropdown_${extraId}`] = function(query) {
        const list = document.getElementById(listId);
        if (!list) return;
        list.innerHTML = '';
        const q = query.toLowerCase();

        // Asegurar que lobby (1) siempre esté disponible
        if (!config.mapsConfig["1"]) {
            config.mapsConfig["1"] = { name: "Lobby / Hangar", color: "var(--primary)" };
        }

        for(let id in config.mapsConfig) {
            const mapObj = config.mapsConfig[id];
            const matches = mapObj.name.toLowerCase().includes(q) || id.includes(q);
            if (q && !matches) continue;
            
            const row = document.createElement('div');
            row.style.padding = '8px 12px';
            row.style.cursor = 'pointer';
            row.style.borderBottom = '1px solid rgba(255,255,255,0.02)';
            row.style.display = 'flex';
            row.style.flexDirection = 'column';
            row.style.gap = '5px';
            
            row.onmouseenter = () => row.style.background = `${borderCSSColor}1a`;
            row.onmouseleave = () => row.style.background = 'transparent';

            const titleSpan = document.createElement('span');
            titleSpan.innerHTML = `<strong>[ID ${id}]</strong> ${mapObj.name}`;
            titleSpan.style.color = borderCSSColor;
            titleSpan.style.fontSize = '0.85rem';
            row.appendChild(titleSpan);

            row.onclick = () => {
                onChangeCallback(id);
                document.getElementById(inputId).value = `[ID ${id}] ${mapObj.name}`;
                list.style.display = 'none';
            };
            
            list.appendChild(row);
        }

        if (list.children.length === 0) {
            const noResult = document.createElement('div');
            noResult.innerText = 'No se encontraron mapas';
            noResult.style.padding = '10px';
            noResult.style.color = '#888';
            noResult.style.fontSize = '0.8rem';
            list.appendChild(noResult);
        }
    };

    // Agregamos un event listener global para cerrar este dropdown específico
    document.addEventListener('click', function(e) {
        const list = document.getElementById(listId);
        const searchInput = document.getElementById(inputId);
        if (list && searchInput && !list.contains(e.target) && e.target !== searchInput) {
            list.style.display = 'none';
        }
    });

    return `
        <div style="position: relative; width: 100%; display: flex; flex-direction: column;">
            <div style="position: relative; display: flex; align-items: center; width: 100%;">
                <input type="text" id="${inputId}" value="${currentName}" 
                       placeholder="🔍 Escribí para filtrar mapa..." 
                       style="background:#0f172a; color:${borderCSSColor}; font-weight:bold; padding-right: 30px; border: 1px solid ${borderCSSColor}33; width: 100%; border-radius: 8px; outline: none; font-size: 0.75rem;"
                       onfocus="document.querySelectorAll('.folder-content[id^=dropdown-list-]').forEach(el=>el.style.display='none'); document.getElementById('${listId}').style.display = 'block'; window['filterMapDropdown_${extraId}'](this.value);"
                       oninput="window['filterMapDropdown_${extraId}'](this.value);">
                <span style="position: absolute; right: 10px; cursor: pointer; color: ${borderCSSColor}; font-size: 0.8rem;" 
                      onclick="const el = document.getElementById('${listId}'); const cur = el.style.display; document.querySelectorAll('.folder-content[id^=dropdown-list-]').forEach(x=>x.style.display='none'); el.style.display = cur === 'block' ? 'none' : 'block';">▼</span>
            </div>
            
            <div id="${listId}" class="folder-content" 
                 style="display: none; position: absolute; left: 0; right: 0; top: 100%; z-index: 999999; 
                        max-height: 200px; overflow-y: auto; background: #0f172a; border: 1px solid ${borderCSSColor}; 
                        padding: 5px; box-shadow: 0 15px 30px rgba(0,0,0,0.6); margin-top: 5px; border-radius: 8px; width: 100%;">
            </div>
        </div>
    `;
};
