window.resolveAssetWebUrl = function(iconPath) {
    if (!iconPath) return '';
    let path = iconPath;
    const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';
    if (path.includes('res://assets/')) {
        return path.replace('res://assets/', activeURL + '/assets/');
    }
    let idx = path.indexOf('assets/');
    if (idx !== -1) {
        return activeURL + '/' + path.substring(idx);
    }
    return path;
};

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


function refreshCurrentTab() {
    if(!config || Object.keys(config).length === 0) return;
    const active = document.querySelector('.view.active');
    if(!active) return;
    const tabId = active.id.replace('view-', '');
    const renderMap = {
        'ships': renderShips, 'enemies': renderEnemies, 'ammo': renderAmmo, 'weapons': renderWeapons, 
        'shields': renderShields, 'engines': renderEngines, 'skills': renderSkills, 
        'mechanics': renderMechanicsLib, 'maps': renderMaps, 'users': renderRegisteredUsers,
        'pilot': renderPilot,
        'modes': renderModes,
        'loot': renderLootConfig,
        'enemy-loot': renderEnemyLootDetail,
        'crafting-recipes': renderCrafting,
        'crafting-materials': renderCrafting,
        'housing': renderHousing,
        'quests': renderQuests,
        'battlepass': renderBattlePass,
        'talent-creator': renderTalentCreator,
        'talent-mapper': renderTalentMapper,
        'sessions': () => (currentSessionSubTab === 'online' ? renderOnlinePlayers() : renderSessions()),
        'ranking': renderRanking
    };
    if(renderMap[tabId]) renderMap[tabId]();
}

function renderAll() {
    if(!config || Object.keys(config).length === 0) return;
    renderShips(); renderEnemies(); renderSkills(); renderMechanicsLib();
    renderMaps(); renderAmmo(); renderWeapons(); renderShields(); renderEngines();
    renderPilot();
    renderModes();
    renderLootConfig();
    renderCrafting();
    renderHousing();
    renderQuests();
    renderBattlePass();
    renderRanking();
}

function renderAmmo() {
    const grid = document.getElementById('ammo-grid'); grid.innerHTML = '';
    const f = getFilter();
    
    const type = currentAmmoTab;
    const multipliers = config.ammoMultipliers[type] || [];
    const shopItems = (config.shopItems.ammo && config.shopItems.ammo[type]) ? config.shopItems.ammo[type] : [];

    const descMap = {
        'laser': '🔦 <strong>Láser:</strong> Proyectil estándar directo. Daño enfocado a distancia media/larga.',
        'mine': '💣 <strong>Mina:</strong> Munición explosiva de proximidad. Ideal para control de zonas o defensa.',
        'missile': '🚀 <strong>Misil:</strong> Misil teledirigido de largo alcance con gran capacidad destructiva.',
        'melee': '👊 <strong>Melee (Tanque):</strong> Ataque cuerpo a cuerpo de muy corto alcance. Ralentiza (paraliza) al enemigo al impactar.',
        'heal': '💚 <strong>Curativa:</strong> Restaura HP y Escudo al propio jugador en PvE. En PvP, cura al aliado impactado y una porción a vos.',
        'siphon': '🧛 <strong>Vampírica (Sifón):</strong> Inflige daño al enemigo y te cura un porcentaje del daño causado.',
        'emp': '⚡ <strong>Pulso EMP:</strong> Silencia habilidades y mecánicas de la IA del enemigo o silencia a jugadores en PvP.',
        'electron': '⚛️ <strong>Electrón:</strong> Lanza una bomba de energía en parábola que explota en área al caer. Si golpea enemigos, te otorga velocidad de movimiento acumulable.'
    };

    const descDiv = document.createElement('div');
    descDiv.style.gridColumn = '1 / -1';
    descDiv.style.background = 'rgba(255, 255, 255, 0.02)';
    descDiv.style.border = '1px solid rgba(255, 255, 255, 0.05)';
    descDiv.style.padding = '1rem';
    descDiv.style.borderRadius = '8px';
    descDiv.style.marginBottom = '1rem';
    descDiv.style.color = '#ccc';
    descDiv.style.fontSize = '0.9rem';
    descDiv.innerHTML = descMap[type] || 'Configuración de munición.';
    grid.appendChild(descDiv);

    multipliers.forEach((m, i) => {
        const item = shopItems[i] || { name: `Tier ${i+1}`, range: 0, cooldown: 1000, prices: { hubs:0, ohcu:0 } };
        if(item.cooldown === undefined) item.cooldown = 1000;
        if(item.bulletSpeed === undefined) item.bulletSpeed = 800;
        if(!item.mechanics) item.mechanics = [];
        
        if(f && !item.name.toLowerCase().includes(f) && !JSON.stringify(item).toLowerCase().includes(f)) return;

        const ammoIconKey = type + '_' + i;
        if (!config.shopItems.ammo_icons) config.shopItems.ammo_icons = {};
        const ammoIconPath = config.shopItems.ammo_icons[ammoIconKey] || '';
        const ammoIconWeb = resolveAssetWebUrl(ammoIconPath);
        const ammoIconPreview = ammoIconWeb
            ? `<img src="${ammoIconWeb}" style="width:64px; height:64px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:64px; height:64px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.6rem; text-align:center; padding:2px;">Sin Ícono</div>`;

        let extraFieldsHTML = '';
        if (type === 'emp') {
            extraFieldsHTML = `
                <div class="field full" style="margin-top: 1rem;">
                    <label>Duración del Silencio (ms)</label>
                    <input type="number" value="${item.silenceDurationMs !== undefined ? item.silenceDurationMs : 3000}" onchange="config.shopItems.ammo['${type}'][${i}].silenceDurationMs = parseInt(this.value)">
                </div>
            `;
        } else if (type === 'heal') {
            extraFieldsHTML = `
                <div class="form-grid" style="margin-top: 1rem; grid-template-columns: 1fr 1fr 1fr;">
                    <div class="field"><label>Curación PvE (%)</label><input type="number" value="${item.healPctPvE !== undefined ? item.healPctPvE : 40}" onchange="config.shopItems.ammo['${type}'][${i}].healPctPvE = parseInt(this.value)"></div>
                    <div class="field"><label>Curación Aliado PvP (%)</label><input type="number" value="${item.healPctVictimPvP !== undefined ? item.healPctVictimPvP : 80}" onchange="config.shopItems.ammo['${type}'][${i}].healPctVictimPvP = parseInt(this.value)"></div>
                    <div class="field"><label>Cura Propia PvP (%)</label><input type="number" value="${item.healPctAttackerPvP !== undefined ? item.healPctAttackerPvP : 30}" onchange="config.shopItems.ammo['${type}'][${i}].healPctAttackerPvP = parseInt(this.value)"></div>
                </div>
            `;
        } else if (type === 'siphon') {
            extraFieldsHTML = `
                <div class="field full" style="margin-top: 1rem;">
                    <label>Eficacia de Sifón / Robo de Vida (%)</label>
                    <input type="number" value="${item.siphonPct !== undefined ? item.siphonPct : 25}" onchange="config.shopItems.ammo['${type}'][${i}].siphonPct = parseInt(this.value)">
                </div>
            `;
        } else if (type === 'melee') {
            extraFieldsHTML = `
                <div class="form-grid" style="margin-top: 1rem; grid-template-columns: 1fr 1fr;">
                    <div class="field"><label>Duración Slow (ms)</label><input type="number" value="${item.slowDurationMs !== undefined ? item.slowDurationMs : 1000}" onchange="config.shopItems.ammo['${type}'][${i}].slowDurationMs = parseInt(this.value)"></div>
                    <div class="field"><label>Cantidad Ralentización (pts)</label><input type="number" value="${item.slowAmount !== undefined ? item.slowAmount : 200}" onchange="config.shopItems.ammo['${type}'][${i}].slowAmount = parseInt(this.value)"></div>
                </div>
            `;
        } else if (type === 'electron') {
            extraFieldsHTML = `
                <div class="form-grid" style="margin-top: 1rem; grid-template-columns: 1fr 1fr 1fr 1fr;">
                    <div class="field"><label>Radio de Explosión (px)</label><input type="number" value="${item.explosionRadius !== undefined ? item.explosionRadius : 120}" onchange="config.shopItems.ammo['${type}'][${i}].explosionRadius = parseInt(this.value)"></div>
                    <div class="field"><label>Velocidad Otorgada (%)</label><input type="number" value="${item.speedBuffPct !== undefined ? item.speedBuffPct : 15}" onchange="config.shopItems.ammo['${type}'][${i}].speedBuffPct = parseInt(this.value)"></div>
                    <div class="field"><label>Duración de Velocidad (ms)</label><input type="number" value="${item.speedBuffDurationMs !== undefined ? item.speedBuffDurationMs : 3000}" onchange="config.shopItems.ammo['${type}'][${i}].speedBuffDurationMs = parseInt(this.value)"></div>
                    <div class="field"><label>Stacks Máximos (cant)</label><input type="number" value="${item.speedBuffMaxStacks !== undefined ? item.speedBuffMaxStacks : 4}" onchange="config.shopItems.ammo['${type}'][${i}].speedBuffMaxStacks = parseInt(this.value)"></div>
                </div>
            `;
        }

        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div class="card-tag">TIER ${i+1}</div>
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${ammoIconPreview}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload('${ammoIconKey}', 'ammo_icon')">🖼️ ICONO</button>
                    ${ammoIconPath ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="delete config.shopItems.ammo_icons['${ammoIconKey}']; renderAmmo();">✕ Quitar</button>` : ''}
                </div>
                <div style="flex-grow:1;">
                    <div class="field full"><label>Nombre Comercial</label><input type="text" value="${item.name}" onchange="config.shopItems.ammo['${type}'][${i}].name = this.value"></div>
                </div>
            </div>
            
            <div class="form-grid" style="margin-top:1.5rem;">
                <div class="field"><label>Mult. Daño (x)</label><input type="number" step="0.1" value="${m}" style="color:var(--accent); font-weight:bold;" onchange="config.ammoMultipliers['${type}'][${i}] = parseFloat(this.value)"></div>
                <div class="field"><label>Alcance (px)</label><input type="number" value="${item.range || 0}" onchange="config.shopItems.ammo['${type}'][${i}].range = parseInt(this.value)"></div>
                <div class="field"><label>Vel. Bala (px/s)</label><input type="number" value="${item.bulletSpeed}" onchange="config.shopItems.ammo['${type}'][${i}].bulletSpeed = parseInt(this.value)"></div>
                <div class="field"><label>Cooldown (ms)</label><input type="number" value="${item.cooldown}" onchange="config.shopItems.ammo['${type}'][${i}].cooldown = parseInt(this.value)"></div>
            </div>

            ${extraFieldsHTML}
            
            <div style="margin-top: 1.5rem; padding-top: 1rem; border-top: 1px solid #333;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                    <label style="color:var(--accent); font-size: 0.7rem; font-weight:bold;">✨ EFECTOS DE IMPACTO</label>
                    <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.6rem;" onclick="addAmmoMechanic('${type}', ${i})">+ EFECTO</button>
                </div>
                <div id="ammo-mech-${type}-${i}">
                    ${item.mechanics.map((me, midx) => `
                        <div style="background:rgba(255,255,255,0.03); padding:8px; border-radius:6px; margin-bottom:8px; border:1px solid rgba(255,255,255,0.05); position:relative;">
                            <button style="position:absolute; top:4px; right:4px; background:none; border:none; color:#ff4444; cursor:pointer; font-size:10px;" onclick="config.shopItems.ammo['${type}'][${i}].mechanics.splice(${midx},1); renderAmmo();">✕</button>
                            <select style="background:transparent; border:none; color:var(--accent); font-size:0.7rem; font-weight:bold; cursor:pointer;" onchange="config.shopItems.ammo['${type}'][${i}].mechanics[${midx}].type = this.value; renderAmmo();">
                                ${Object.keys(AMMO_MECH_LIB).map(mt => `<option value="${mt}" ${me.type===mt?'selected':''}>${AMMO_MECH_LIB[mt].icon} ${AMMO_MECH_LIB[mt].label}</option>`).join('')}
                            </select>
                            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px; margin-top:5px;">
                                ${AMMO_MECH_LIB[me.type || 'bleed'].fields.map(fld => `
                                    <div class="field" style="margin:0;"><label style="font-size:9px;">${fld}</label><input type="number" value="${me[fld] || 0}" style="font-size:10px; height:20px;" onchange="config.shopItems.ammo['${type}'][${i}].mechanics[${midx}].${fld} = parseInt(this.value)"></div>
                                `).join('')}
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>

            <div class="price-group" style="margin-top:1rem; border-top:1px solid #333; padding-top:1rem;">
                <div class="field"><label>Hubs (qty)</label><input type="number" value="${item.prices.hubs}" onchange="config.shopItems.ammo['${type}'][${i}].prices.hubs = parseInt(this.value)"></div>
                <div class="field"><label>Ohcu (qty)</label><input type="number" value="${item.prices.ohcu}" onchange="config.shopItems.ammo['${type}'][${i}].prices.ohcu = parseInt(this.value)"></div>
            </div>
        `;
        grid.appendChild(card);
    });
}

function renderWeapons() {
    const grid = document.getElementById('weapons-grid'); grid.innerHTML = '';
    const f = getFilter();
    config.shopItems.weapons.forEach((w, i) => {
        if(f && !w.name.toLowerCase().includes(f) && !w.id.toLowerCase().includes(f)) return;
        const iconWeb = resolveAssetWebUrl(w.icon || '');
        const iconPreview = iconWeb
            ? `<img src="${iconWeb}" style="width:72px; height:72px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:72px; height:72px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.7rem; text-align:center; padding:4px;">Sin Ícono</div>`;
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div class="card-tag">ID: ${w.id}</div>
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${iconPreview}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload(${i}, 'weapon_icon')">🖼️ ICONO</button>
                    ${w.icon ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="config.shopItems.weapons[${i}].icon=''; renderWeapons();">✕ Quitar</button>` : ''}
                </div>
                <div style="flex-grow:1;">
                    <div class="field full"><label>Nombre del Arma</label><input type="text" value="${w.name}" onchange="config.shopItems.weapons[${i}].name = this.value"></div>
                </div>
            </div>
            <div class="form-grid" style="margin-top:1rem;">
                <div class="field"><label>Daño Base (pts)</label><input type="number" value="${w.base}" onchange="config.shopItems.weapons[${i}].base = parseInt(this.value)"></div>
                <div class="field full"><label>Mod. Velocidad</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${w.speedMod || 0}" onchange="config.shopItems.weapons[${i}].speedMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.weapons[${i}].speedModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(w.speedModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(w.speedModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field full"><label>Mod. Vida</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${w.hpMod || 0}" onchange="config.shopItems.weapons[${i}].hpMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.weapons[${i}].hpModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(w.hpModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(w.hpModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field"><label>Precio Hubs (qty)</label><input type="number" value="${w.prices.hubs}" onchange="config.shopItems.weapons[${i}].prices.hubs = parseInt(this.value)"></div>
                <div class="field"><label>Precio Ohcu (qty)</label><input type="number" value="${w.prices.ohcu}" onchange="config.shopItems.weapons[${i}].prices.ohcu = parseInt(this.value)"></div>
            </div>
        `;
        grid.appendChild(card);
    });
}

function renderShields() {
    const grid = document.getElementById('shields-grid'); grid.innerHTML = '';
    const f = getFilter();
    config.shopItems.shields.forEach((s, i) => {
        if(f && !s.name.toLowerCase().includes(f) && !s.id.toLowerCase().includes(f) && !JSON.stringify(s).toLowerCase().includes(f)) return;
        const iconWeb = resolveAssetWebUrl(s.icon || '');
        const iconPreview = iconWeb
            ? `<img src="${iconWeb}" style="width:72px; height:72px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:72px; height:72px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.7rem; text-align:center; padding:4px;">Sin Ícono</div>`;
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div class="card-tag">ID: ${s.id}</div>
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${iconPreview}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload(${i}, 'shield_icon')">🖼️ ICONO</button>
                    ${s.icon ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="config.shopItems.shields[${i}].icon=''; renderShields();">✕ Quitar</button>` : ''}
                </div>
                <div style="flex-grow:1;">
                    <div class="field full"><label>Nombre del Escudo</label><input type="text" value="${s.name}" onchange="config.shopItems.shields[${i}].name = this.value"></div>
                </div>
            </div>
            <div class="form-grid" style="margin-top:1rem;">
                <div class="field"><label>Escudo Base (pts)</label><input type="number" value="${s.base}" onchange="config.shopItems.shields[${i}].base = parseInt(this.value)"></div>
                <div class="field full"><label>Mod. Vida</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${s.hpMod || 0}" onchange="config.shopItems.shields[${i}].hpMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.shields[${i}].hpModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(s.hpModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(s.hpModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field full"><label>Mod. Velocidad</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${s.speedMod || 0}" onchange="config.shopItems.shields[${i}].speedMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.shields[${i}].speedModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(s.speedModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(s.speedModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field"><label>Precio Hubs (qty)</label><input type="number" value="${s.prices.hubs}" onchange="config.shopItems.shields[${i}].prices.hubs = parseInt(this.value)"></div>
                <div class="field"><label>Precio Ohcu (qty)</label><input type="number" value="${s.prices.ohcu}" onchange="config.shopItems.shields[${i}].prices.ohcu = parseInt(this.value)"></div>
            </div>
        `;
        grid.appendChild(card);
    });
}

function renderEngines() {
    const grid = document.getElementById('engines-grid'); grid.innerHTML = '';
    const f = getFilter();
    config.shopItems.engines.forEach((e, i) => {
        if(f && !e.name.toLowerCase().includes(f) && !e.id.toLowerCase().includes(f) && !JSON.stringify(e).toLowerCase().includes(f)) return;
        const iconWeb = resolveAssetWebUrl(e.icon || '');
        const iconPreview = iconWeb
            ? `<img src="${iconWeb}" style="width:72px; height:72px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:72px; height:72px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.7rem; text-align:center; padding:4px;">Sin Ícono</div>`;
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div class="card-tag">ID: ${e.id}</div>
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${iconPreview}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload(${i}, 'engine_icon')">🖼️ ICONO</button>
                    ${e.icon ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="config.shopItems.engines[${i}].icon=''; renderEngines();">✕ Quitar</button>` : ''}
                </div>
                <div style="flex-grow:1;">
                    <div class="field full"><label>Nombre del Motor</label><input type="text" value="${e.name}" onchange="config.shopItems.engines[${i}].name = this.value"></div>
                </div>
            </div>
            <div class="form-grid" style="margin-top:1rem;">
                <div class="field"><label>Velocidad Base (px/s)</label><input type="number" value="${e.base}" onchange="config.shopItems.engines[${i}].base = parseInt(this.value)"></div>
                <div class="field full"><label>Mod. Escudo</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${e.shieldMod || 0}" onchange="config.shopItems.engines[${i}].shieldMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.engines[${i}].shieldModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(e.shieldModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(e.shieldModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field full"><label>Mod. Vida</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${e.hpMod || 0}" onchange="config.shopItems.engines[${i}].hpMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.engines[${i}].hpModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(e.hpModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(e.hpModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field full"><label>Mod. Daño</label><div style="display:flex;gap:6px;align-items:center;"><input type="number" value="${e.dmgMod || 0}" onchange="config.shopItems.engines[${i}].dmgMod = parseFloat(this.value)" style="flex:1;min-width:80px;"><select onchange="config.shopItems.engines[${i}].dmgModType = this.value" style="width:auto;min-width:55px;max-width:65px;font-size:0.65rem;background:#1a1a2e;color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:4px;padding:2px 4px;"><option value="percent" ${(e.dmgModType||'percent')==='percent'?'selected':''}>%</option><option value="flat" ${(e.dmgModType||'percent')==='flat'?'selected':''}>FIJO</option></select></div></div>
                <div class="field"><label>Precio Hubs (qty)</label><input type="number" value="${e.prices.hubs}" onchange="config.shopItems.engines[${i}].prices.hubs = parseInt(this.value)"></div>
                <div class="field"><label>Precio Ohcu (qty)</label><input type="number" value="${e.prices.ohcu}" onchange="config.shopItems.engines[${i}].prices.ohcu = parseInt(this.value)"></div>
            </div>
        `;
        grid.appendChild(card);
    });
}

function renderShips() {
    const grid = document.getElementById('ships-grid'); grid.innerHTML = '';
    const f = getFilter();
    config.shipModels.forEach((ship, idx) => {
        if(f && !ship.name.toLowerCase().includes(f) && !ship.id.toString().includes(f)) return;
        
        const shipIconWeb = resolveAssetWebUrl(ship.icon || '');
        const previewHtml = shipIconWeb ? `<img src="${shipIconWeb}" style="width:80px; height:80px; object-fit:contain; border-radius:6px; border:1px solid rgba(255,255,255,0.1); background:rgba(0,0,0,0.2);" onerror="this.style.display='none';">` : `<div style="width:80px; height:80px; border:1px dashed rgba(255,255,255,0.15); border-radius:6px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.75rem;">Sin Icono</div>`;

        const card = document.createElement('div'); card.className = 'card';
        card.style.position = 'relative';
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 8px;">
                <div style="background:rgba(255,255,255,0.06); color:#888; border:1px solid rgba(255,255,255,0.1); border-radius:4px; padding:2px 6px; font-size:0.75rem; font-family:'JetBrains Mono'; font-weight:bold;">#ID ${ship.id}</div>
                <div style="display:flex; gap:12px; align-items:center;">
                    <!-- Switch de visibilidad -->
                    <button style="background:none; border:none; color:${ship.hidden ? '#ff9f0a' : '#00d2ff'}; cursor:pointer; font-size:0.75rem; font-weight:bold; display:flex; align-items:center; gap:4px;" onclick="toggleShipVisibility(${idx})">
                        ${ship.hidden ? '🙈 OCULTO' : '👁️ VISIBLE'}
                    </button>
                    <!-- Eliminar -->
                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.75rem; font-weight:bold;" onclick="removeShip(${idx})">
                        ✕ ELIMINAR
                    </button>
                </div>
            </div>
            
            <div style="display:flex; gap:15px; align-items:flex-start; margin-top:0.5rem;">
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${previewHtml}
                    <button class="btn" style="padding:4px 8px; font-size:0.65rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.2); color:var(--primary); cursor:pointer; border-radius:4px;" onclick="openAssetPicker(${idx}, 'ship_icon')">🖼️ ICONO</button>
                </div>
                <div style="flex-grow:1; display:flex; flex-direction:column; gap:10px;">
                    <div class="field"><label>Nombre de la Nave</label><input type="text" value="${ship.name}" onchange="config.shipModels[${idx}].name = this.value"></div>
                    <div class="field">
                        <label>Ruta Asset 3D (.glb)</label>
                        <div style="display:flex; gap:8px; align-items:center; width:100%;">
                            <input type="text" value="${ship.assetPath || ''}" placeholder="res://assets/Personajes/3D/Nave..." onchange="config.shipModels[${idx}].assetPath = this.value" style="flex-grow:1; margin:0;">
                            <button class="btn btn-primary" style="padding:8px 12px; font-size:0.75rem; flex-shrink:0; background:var(--accent); border-color:var(--accent);" onclick="triggerAssetUpload(${idx}, 'ship_glb')">📁 SELECCIONAR GLB</button>
                        </div>
                    </div>
                </div>
            </div>

            <h5 style="color:var(--accent); margin:15px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(6,182,212,0.15); padding-bottom:2px;">⚙️ ROTACIÓN 3D INICIAL</h5>
            <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr; gap:10px; margin-bottom:15px; display:grid;">
                <div class="field"><label>Rotación X (grados)</label><input type="number" value="${ship.rotX || 0}" onchange="config.shipModels[${idx}].rotX = parseFloat(this.value) || 0"></div>
                <div class="field"><label>Rotación Y (grados)</label><input type="number" value="${ship.rotY || 0}" onchange="config.shipModels[${idx}].rotY = parseFloat(this.value) || 0"></div>
                <div class="field"><label>Rotación Z (grados)</label><input type="number" value="${ship.rotZ || 0}" onchange="config.shipModels[${idx}].rotZ = parseFloat(this.value) || 0"></div>
            </div>

            <h5 style="color:var(--primary); margin:15px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(0,210,255,0.15); padding-bottom:2px;">📊 ESTADÍSTICAS</h5>
            <div class="form-grid" style="margin-top: 0.5rem; display:grid;">
                <div class="field"><label>HP Total (pts)</label><input type="number" value="${ship.hp}" onchange="config.shipModels[${idx}].hp = parseInt(this.value)"></div>
                <div class="field"><label>Escudo Total (pts)</label><input type="number" value="${ship.shield}" onchange="config.shipModels[${idx}].shield = parseInt(this.value)"></div>
                <div class="field"><label>Velocidad (px/s)</label><input type="number" value="${ship.speed}" onchange="config.shipModels[${idx}].speed = parseInt(this.value)"></div>
                <div class="field"><label>Rango de Visión (px)</label><input type="number" value="${ship.vision || 1300}" onchange="config.shipModels[${idx}].vision = parseInt(this.value)"></div>
            </div>
            <div class="form-grid" style="margin-top: 1rem; padding-top: 1rem; border-top: 1px solid #333; display:grid;">
                <div class="field"><label>Slots Armas (W)</label><input type="number" value="${ship.slots.w || 0}" onchange="config.shipModels[${idx}].slots.w = parseInt(this.value)"></div>
                <div class="field"><label>Slots Escudos (S)</label><input type="number" value="${ship.slots.s || 0}" onchange="config.shipModels[${idx}].slots.s = parseInt(this.value)"></div>
                <div class="field"><label>Slots Motores (E)</label><input type="number" value="${ship.slots.e || 0}" onchange="config.shipModels[${idx}].slots.e = parseInt(this.value)"></div>
                <div class="field"><label>Slots Extras (X)</label><input type="number" value="${ship.slots.x || 0}" onchange="config.shipModels[${idx}].slots.x = parseInt(this.value)"></div>
            </div>
            <div class="price-group" style="display:flex; gap:15px; margin-top:1rem;">
                <div class="field" style="flex:1;"><label>Precio Hubs (qty)</label><input type="number" value="${ship.prices.hubs}" onchange="config.shipModels[${idx}].prices.hubs = parseInt(this.value)"></div>
                <div class="field" style="flex:1;"><label>Precio Ohcu (qty)</label><input type="number" value="${ship.prices.ohcu}" onchange="config.shipModels[${idx}].prices.ohcu = parseInt(this.value)"></div>
            </div>
        `;
        grid.appendChild(card);
    });
}

window.toggleShipVisibility = function(idx) {
    config.shipModels[idx].hidden = !config.shipModels[idx].hidden;
    renderShips();
};

window.addNewShip = function() {
    if (!config.shipModels) config.shipModels = [];
    let maxId = 0;
    config.shipModels.forEach(s => {
        if (s.id > maxId) maxId = s.id;
    });
    
    const newShip = {
        id: maxId + 1,
        name: "Nueva Nave N" + (maxId + 1),
        assetPath: "res://assets/Personajes/3D/Nave" + (maxId + 1) + "/Nave" + (maxId + 1) + ".glb",
        icon: "",
        rotX: 0,
        rotY: 0,
        rotZ: 0,
        hp: 3000,
        shield: 1000,
        speed: 300,
        vision: 1300,
        slots: {
            w: 1,
            s: 1,
            e: 1,
            x: 1
        },
        prices: {
            hubs: 10000,
            ohcu: 100
        }
    };
    config.shipModels.push(newShip);
    renderShips();
};

window.removeShip = function(idx) {
    if (!config.shipModels) return;
    if (confirm(`¿Estás seguro de que deseas eliminar la nave "${config.shipModels[idx].name}"?`)) {
        config.shipModels.splice(idx, 1);
        renderShips();
    }
};

function updateSidebar() {
    const enemyList = document.getElementById('sidebar-enemies-list');
    const bossList = document.getElementById('sidebar-bosses-list');
    const mapList = document.getElementById('sidebar-maps-list');
    if(!enemyList || !bossList || !mapList) return;
    
    // Preservar el estado cerrado/abierto de las carpetas al re-renderizar
    const closedFolders = new Set();
    document.querySelectorAll('.folder-content').forEach(el => {
        if (el.id && !el.classList.contains('show')) {
            closedFolders.add(el.id);
        }
    });

    const searchTerm = (document.getElementById('sidebar-search')?.value || '').toLowerCase();
    enemyList.innerHTML = ''; bossList.innerHTML = ''; mapList.innerHTML = '';

    // Mapas
    for(let id in config.mapsConfig) {
        const m = config.mapsConfig[id];
        if(searchTerm && !m.name.toLowerCase().includes(searchTerm)) continue;
        const link = document.createElement('div');
        link.className = 'nav-link sub ' + (selectedMapId === id ? 'active' : '');
        link.innerHTML = `<span style="color:${m.color}">■</span> ${m.name}`;
        link.onclick = () => selectMap(id);
        mapList.appendChild(link);
    }

    // Enemigos
    const baseSelectedId = selectedEnemyId ? selectedEnemyId.split('-')[0] : '';
    const tiers = [
        { suffix: '', label: 'Base (x1)' },
        { suffix: '-A', label: 'Tier A (x2)' },
        { suffix: '-B', label: 'Tier B (x3)' },
        { suffix: '-C', label: 'Tier C (x4)' },
        { suffix: '-D', label: 'Tier D (x5)' }
    ];

    for(let id in config.enemyModels) {
        if (id.includes('-')) continue; // Ocultar variantes sub-tier de la iteración principal
        
        const en = config.enemyModels[id];
        const matches = en.name.toLowerCase().includes(searchTerm) || id.includes(searchTerm);
        if (!matches) continue;

        if (parseInt(id) < 100) {
            const isCurrentOpen = baseSelectedId === id && !closedFolders.has(`subfolder-enemy-${id}`);
            
            // Contenedor de grupo
            const groupContainer = document.createElement('div');
            groupContainer.className = 'enemy-group';
            groupContainer.style.display = 'flex';
            groupContainer.style.flexDirection = 'column';

            // Enlace del Enemigo Base (Carpeta de nivel medio)
            const parentLink = document.createElement('div');
            parentLink.className = 'nav-link sub ' + (isCurrentOpen ? 'active' : '');
            parentLink.style.display = 'flex';
            parentLink.style.justifyContent = 'space-between';
            parentLink.style.alignItems = 'center';
            parentLink.style.cursor = 'pointer';
            
            parentLink.innerHTML = `
                <span>👾 ${en.name || 'Enemigo '+id}</span>
                <span class="chevron" style="font-size: 0.65rem; transition: transform 0.2s;">${isCurrentOpen ? '▼' : '▶'}</span>
            `;

            parentLink.onclick = (e) => {
                toggleFolder(`subfolder-enemy-${id}`, e);
                selectEnemy(id);
            };
            groupContainer.appendChild(parentLink);

            // Sub-carpeta colapsable con misma estética que subfolder-ammo
            const subContainer = document.createElement('div');
            subContainer.id = `subfolder-enemy-${id}`;
            subContainer.className = 'folder-content ' + (isCurrentOpen ? 'show' : '');
            subContainer.style.paddingLeft = '1rem';
            subContainer.style.borderLeft = '1px solid #333';
            subContainer.style.marginLeft = '0.5rem';

            tiers.forEach(t => {
                const subId = `${id}${t.suffix}`;
                const isSubActive = selectedEnemyId === subId;

                const subLink = document.createElement('div');
                subLink.className = 'nav-link sub ' + (isSubActive ? 'active' : '');
                subLink.innerText = `👾 ${t.label}`;
                subLink.style.cursor = 'pointer';
                
                subLink.onclick = (e) => {
                    e.stopPropagation();
                    selectEnemy(subId);
                };

                subContainer.appendChild(subLink);
            });

            groupContainer.appendChild(subContainer);
            enemyList.appendChild(groupContainer);
        } else {
            // Bosses
            const link = document.createElement('div');
            link.className = 'nav-link sub ' + (selectedEnemyId === id ? 'active' : '');
            link.innerText = `💀 ${en.name || 'Boss '+id}`;
            link.onclick = () => selectEnemy(id);
            bossList.appendChild(link);
        }
    }
}

function renderEnemies() {
    const MECHANICS_LIB = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const MOVEMENT_LIB = config.movementLib || DEFAULT_MOVEMENT_LIB;

    updateSidebar();
    const grid = document.getElementById('enemies-grid'); grid.innerHTML = '';
    
    // Botón de Purga Total
    const purgeBtn = document.createElement('button');
    purgeBtn.className = 'btn';
    purgeBtn.style.background = '#ff4444';
    purgeBtn.style.marginBottom = '1rem';
    purgeBtn.style.width = '100%';
    purgeBtn.innerText = '🔥 PURGAR TODOS LOS ENEMIGOS DEL SERVIDOR';
    purgeBtn.onclick = () => {
        if(confirm('¿Estás seguro? Esto eliminará a todos los bichos de todos los mapas.')) {
            socket.emit('adminPurgeEnemies');
        }
    };
    grid.appendChild(purgeBtn);

    const f = getFilter();

    for(let id in config.enemyModels) {
        if (id.includes('-')) continue; // Ocultar variantes sub-tier de la grilla principal
        
        const en = config.enemyModels[id];
        const eid = parseInt(id);
        if (currentEnemySubTab === 'regular' && eid >= 100) continue;
        if (currentEnemySubTab === 'boss' && eid < 100) continue;
        
        const matches = en.name.toLowerCase().includes(f) || id.includes(f) || JSON.stringify(en).toLowerCase().includes(f);
        if (f && !matches) continue;

        const card = document.createElement('div'); card.className = 'card';
        card.style.cursor = 'pointer';
        card.onclick = () => selectEnemy(id);
        card.innerHTML = `
            <div class="card-tag">#ID ${id}</div>
            <h3>${en.name}</h3>
            <p style="font-size:0.8rem; opacity:0.6;">IA: ${en.movementAI || 'chase'}</p>
            <div style="margin-top:1rem; color:var(--accent); font-weight:bold; font-size:0.7rem;">Configurar Detalles</div>
        `;
        grid.appendChild(card);
    }
}

function renderEnemyDetail() {
    updateSidebar();
    const MECHANICS_LIB = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const MOVEMENT_LIB = config.movementLib || DEFAULT_MOVEMENT_LIB;
    const DEFENSE_LIB = config.defenseLib || DEFAULT_DEFENSE_LIB;

    const container = document.getElementById('enemy-detail-container');
    const baseId = selectedEnemyId ? selectedEnemyId.split('-')[0] : '';
    const tiers = [
        { suffix: '', label: 'Base (x1)' },
        { suffix: '-A', label: 'Tier A (x2)', mult: 2, key: 'A' },
        { suffix: '-B', label: 'Tier B (x3)', mult: 3, key: 'B' },
        { suffix: '-C', label: 'Tier C (x4)', mult: 4, key: 'C' },
        { suffix: '-D', label: 'Tier D (x5)', mult: 5, key: 'D' }
    ];

    if (baseId && parseInt(baseId) < 100) {
        const parentModel = config.enemyModels[baseId];
        if (parentModel) {
            tiers.forEach(t => {
                if (t.suffix === '') return;
                const tierId = `${baseId}${t.suffix}`;
                if (!config.enemyModels[tierId]) {
                    const clone = JSON.parse(JSON.stringify(parentModel));
                    clone.name = `${parentModel.name || 'Enemigo ' + baseId} ${t.key}`;
                    clone.hp = parentModel.hp * t.mult;
                    clone.shield = parentModel.shield * t.mult;
                    if (clone.bulletDamage !== undefined) clone.bulletDamage = parentModel.bulletDamage * t.mult;
                    if (clone.rewardExp !== undefined) clone.rewardExp = parentModel.rewardExp * t.mult;
                    if (clone.rewardHubs !== undefined) clone.rewardHubs = parentModel.rewardHubs * t.mult;
                    if (clone.rewardOhcu !== undefined) clone.rewardOhcu = parentModel.rewardOhcu * t.mult;
                    if (Array.isArray(clone.mechanics)) {
                        clone.mechanics.forEach(m => {
                            if (m.bulletDamage !== undefined) m.bulletDamage = m.bulletDamage * t.mult;
                            if (m.damage !== undefined) m.damage = m.damage * t.mult;
                        });
                    }
                    config.enemyModels[tierId] = clone;
                }
            });
        }
    }

    const en = config.enemyModels[selectedEnemyId];
    if(!en) return;

    if (!en.mechanics) {
        en.mechanics = [{ type: "laser", bulletDamage: 10, bulletSpeed: 800, fireRange: 600, fireRate: 1000, startDelay: 0 }];
    }
    if (!en.movementPhases) {
        en.movementPhases = [{ type: en.movementAI || "chase", speed: en.speed || 3.5, stopDist: en.stopDist || 150, startDelay: 0 }];
    }
    if (!en.defenseMechanics) en.defenseMechanics = [];

    container.innerHTML = `
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 2rem; align-items: start;">
            <div class="col">
                <div class="card" style="width:100%; margin-bottom: 2rem;">
                    <div class="field full"><label>NOMBRE DE LA ENTIDAD (#ID ${selectedEnemyId})</label><input type="text" value="${en.name}" style="font-size: 1.5rem; color:var(--accent);" onchange="config.enemyModels['${selectedEnemyId}'].name = this.value; updateSidebar();"></div>
                    <div class="form-grid" style="margin-top:1rem; padding-bottom: 1rem; border-bottom: 1px solid #333;">
                        <div class="field"><label>HP (pts)</label><input type="number" value="${en.hp}" onchange="config.enemyModels['${selectedEnemyId}'].hp = parseInt(this.value)"></div>
                        <div class="field"><label>Escudo (pts)</label><input type="number" value="${en.shield}" onchange="config.enemyModels['${selectedEnemyId}'].shield = parseInt(this.value)"></div>
                    </div>
                    <div class="price-group" style="margin-top:1rem;">
                        <div class="field"><label>Exp (pts)</label><input type="number" value="${en.rewardExp || 0}" onchange="config.enemyModels['${selectedEnemyId}'].rewardExp = parseInt(this.value)"></div>
                        <div class="field"><label>Hubs (pts)</label><input type="number" value="${en.rewardHubs || 0}" onchange="config.enemyModels['${selectedEnemyId}'].rewardHubs = parseInt(this.value)"></div>
                        <div class="field"><label style="color:var(--primary);">Ohcu (qty)</label><input type="number" value="${en.rewardOhcu || 0}" onchange="config.enemyModels['${selectedEnemyId}'].rewardOhcu = parseInt(this.value)"></div>
                        <div class="field"><label style="color:var(--accent);">Probabilidad de Cofre (%)</label><input type="number" min="0" max="100" step="1" value="${en.chestDropChance !== undefined ? Math.round(en.chestDropChance * 100) : 10}" onchange="config.enemyModels['${selectedEnemyId}'].chestDropChance = parseFloat(this.value) / 100"></div>
                        <div class="field"><label style="color:var(--warning);">🏆 Pts Ranking</label><input type="number" value="${en.rankingPoints !== undefined ? en.rankingPoints : parseInt(selectedEnemyId.split('-')[0])}" onchange="config.enemyModels['${selectedEnemyId}'].rankingPoints = parseInt(this.value)"></div>
                    </div>
                </div>
                <div class="card" style="width:100%; margin-bottom: 2rem; border-color: var(--accent); background: rgba(6, 182, 212, 0.1);">
                    <label style="color:var(--accent); font-size: 0.7rem; font-weight:bold; margin-bottom:1rem; display:block;">🧠 COMPORTAMIENTO GLOBAL</label>
                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
                        <div class="field" style="display:flex; align-items:center; gap:10px; background:transparent; border:none;">
                            <input type="checkbox" ${en.aggressive ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].aggressive = this.checked">
                            <label style="margin:0;">Agresivo (Ataca al ver)</label>
                        </div>
                        <div class="field" style="display:flex; align-items:center; gap:10px; background:transparent; border:none;">
                            <input type="checkbox" ${en.chaseUntilDeath ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].chaseUntilDeath = this.checked">
                            <label style="margin:0;">Persistir hasta morir</label>
                        </div>
                        <div class="field" style="display:flex; align-items:center; gap:10px; background:transparent; border:none;">
                            <input type="checkbox" ${en.stopOnOutOfSight ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].stopOnOutOfSight = this.checked">
                            <label style="margin:0;">Parar si no hay visión</label>
                        </div>
                        <div class="field"><label>Timeout Abandono (ms)</label><input type="number" value="${en.chaseIdleTimeout || 0}" onchange="config.enemyModels['${selectedEnemyId}'].chaseIdleTimeout = parseInt(this.value)"></div>
                        <div class="field"><label>Rango de Visión (px)</label><input type="number" value="${en.visionRange || 800}" onchange="config.enemyModels['${selectedEnemyId}'].visionRange = parseInt(this.value)"></div>
                        <div class="field"><label>Rango de Retorno al Spawn (px)</label><input type="number" value="${en.leashRange || 0}" onchange="config.enemyModels['${selectedEnemyId}'].leashRange = parseInt(this.value)"></div>
                        <div class="field"><label>Regeneración de Vida Fuera de Combate (%)</label><input type="number" value="${en.hpRegenPercent !== undefined ? en.hpRegenPercent : 3}" onchange="config.enemyModels['${selectedEnemyId}'].hpRegenPercent = parseFloat(this.value)"></div>
                        <div class="field"><label>Regeneración de Escudo Fuera de Combate (%)</label><input type="number" value="${en.shieldRegenPercent !== undefined ? en.shieldRegenPercent : 5}" onchange="config.enemyModels['${selectedEnemyId}'].shieldRegenPercent = parseFloat(this.value)"></div>
                        <div class="field"><label>Tiempo Espera Fuera de Combate (ms)</label><input type="number" value="${en.regenDelayMs !== undefined ? en.regenDelayMs : (en.regenDelaySec !== undefined ? en.regenDelaySec * 1000 : 5000)}" onchange="config.enemyModels['${selectedEnemyId}'].regenDelayMs = parseInt(this.value); delete config.enemyModels['${selectedEnemyId}'].regenDelaySec;"></div>
                        <div class="field"><label>Intervalo de Regeneración (ms)</label><input type="number" value="${en.regenIntervalMs !== undefined ? en.regenIntervalMs : 1000}" onchange="config.enemyModels['${selectedEnemyId}'].regenIntervalMs = parseInt(this.value)"></div>
                    </div>
                </div>
                <div style="margin-bottom: 1rem; display:flex; justify-content:space-between; align-items:center;">
                    <label style="color:#eab308; font-size: 0.8rem; font-weight:bold;">🏃 CICLO DE MOVIMIENTO</label>
                    <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:#eab308; box-shadow: 0 4px 15px rgba(234, 179, 8, 0.3);" onclick="addMovementPhase('${selectedEnemyId}'); renderEnemyDetail();">+ AGREGAR FASE</button>
                </div>
                <div id="move-list-${selectedEnemyId}">
                    ${en.movementPhases.map((m, idx) => `
                        <div class="card" style="margin-bottom:1rem; position:relative; padding: 1rem; background: rgba(234, 179, 8, 0.05); border: 1px solid rgba(234, 179, 8, 0.2);">
                            <div style="position:absolute; top:8px; right:8px; display:flex; gap:10px;">
                                <button style="background:none; border:none; color:#eab308; cursor:pointer; font-weight:bold;" onclick="moveMovementPhase('${selectedEnemyId}', ${idx}, -1); renderEnemyDetail();">SUBIR</button>
                                <button style="background:none; border:none; color:#eab308; cursor:pointer; font-weight:bold;" onclick="moveMovementPhase('${selectedEnemyId}', ${idx}, 1); renderEnemyDetail();">BAJAR</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="removeMovementPhase('${selectedEnemyId}', ${idx}); renderEnemyDetail();">✕</button>
                            </div>
                            <div class="field full">
                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" onchange="updateMovementPhaseType('${selectedEnemyId}', ${idx}, this.value); renderEnemyDetail();">
                                    ${Object.keys(MOVEMENT_LIB).map(type => `<option value="${type}" ${m.type === type ? 'selected' : ''} style="background:#0f172a; color:white;">${MOVEMENT_LIB[type].icon} ${MOVEMENT_LIB[type].label}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-grid" style="margin-top:1rem;">
                                ${MOVEMENT_LIB[m.type || 'chase'].fields.map(f => {
                                    const moveLabels = { speed:"Velocidad (px/s)", stopDist:"Frenado (px)", idealDist:"Rango Seguro (px)", orbitRadius:"Radio Órbita (px)", chargeCooldown: "Recarga Dash (ms)", activationHP: "Activación HP (%)", explosionDamage: "Daño Explosión", duration: "Duración (ms)", cooldown: "Recarga (ms)", startDelay: "Retraso Inicio (ms)", explodeOnDeath: "Explotar al morir", radius: "Radio del Aura (px)", speedBonus: "Bono de Velocidad (px/s)", intervalMs: "Intervalo de Tick (ms)", affectsEnemies: "Afectar a otros Enemigos", affectsBosses: "Afectar a Bosses", patrolRange: "Rango de Patrulla (px)", changeInterval: "Frecuencia del Cambio (ms / px)", amplitude: "Amplitud (px)", frequency: "Frecuencia (Hz)" };
                                    if (f === 'changeTrigger') {
                                        const val = m[f] || 'time';
                                        return `<div class="field"><label>Criterio de Cambio</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].changeTrigger = this.value; renderEnemyDetail();">
                                            <option value="time" ${val === 'time' ? 'selected' : ''}>⏳ Tiempo</option>
                                            <option value="distance" ${val === 'distance' ? 'selected' : ''}>📏 Recorrido</option>
                                        </select></div>`;
                                    }
                                    if (f === 'changeType') {
                                        const val = m[f] || 'random';
                                        return `<div class="field"><label>Tipo de Giro</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].changeType = this.value; renderEnemyDetail();">
                                            <option value="random" ${val === 'random' ? 'selected' : ''}>🔀 Aleatorio</option>
                                            <option value="reverse" ${val === 'reverse' ? 'selected' : ''}>🔄 Invertir Sentido (180°)</option>
                                            <option value="orthogonal" ${val === 'orthogonal' ? 'selected' : ''}>📐 Giro 90°</option>
                                        </select></div>`;
                                    }
                                    if (['explodeOnDeath', 'affectsEnemies', 'affectsBosses'].includes(f)) return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;"><input type="checkbox" ${m[f] ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].${f} = this.checked"><label style="margin:0;">${moveLabels[f]}</label></div>`;
                                    return `<div class="field"><label>${moveLabels[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].${f} = parseFloat(this.value)"></div>`;
                                }).join('')}
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
            <div class="col">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                    <label style="color:#ef4444; font-size: 0.8rem; font-weight:bold;">⚔️ MECÁNICAS DE ATAQUE ACTIVAS</label>
                    <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:#ef4444; box-shadow: 0 4px 15px rgba(239, 68, 68, 0.3);" onclick="addMechanic('${selectedEnemyId}'); renderEnemyDetail();">+ AGREGAR ARMA</button>
                </div>
                <div id="mech-list-${selectedEnemyId}">
                    ${en.mechanics.map((m, idx) => `
                        <div class="card" style="margin-bottom: 1rem; position:relative; padding: 1rem; background: rgba(239, 68, 68, 0.05); border: 1px solid rgba(239, 68, 68, 0.2);">
                            <div style="position:absolute; top:8px; right:8px; display:flex; gap:10px;">
                                <button style="background:none; border:none; color:#ef4444; cursor:pointer; font-weight:bold;" onclick="moveMechanic('${selectedEnemyId}', ${idx}, -1); renderEnemyDetail();">SUBIR</button>
                                <button style="background:none; border:none; color:#ef4444; cursor:pointer; font-weight:bold;" onclick="moveMechanic('${selectedEnemyId}', ${idx}, 1); renderEnemyDetail();">BAJAR</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="removeMechanic('${selectedEnemyId}', ${idx}); renderEnemyDetail();">✕</button>
                            </div>
                            <div class="field full">
                                <select style="background:#0f172a; border:none; color:#ef4444; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" onchange="updateMechanicType('${selectedEnemyId}', ${idx}, this.value); renderEnemyDetail();">
                                    ${Object.keys(MECHANICS_LIB).map(type => `<option value="${type}" ${m.type === type ? 'selected' : ''} style="background:#0f172a; color:white;">${MECHANICS_LIB[type].icon} ${MECHANICS_LIB[type].label}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-grid" style="margin-top:1rem;">
                                ${MECHANICS_LIB[m.type || 'laser'].fields.map(f => {
const fieldLabelsMap = { 
                                           bulletDamage: m.type === 'bomb' ? "Daño de Explosión (pts)" : (m.type === 'worm_boomerang' ? "Daño de Ida (pts)" : (m.type === 'wind_wall' ? "Daño al Arrollar (pts)" : (m.type === 'burrow' ? "Daño al Emerger (pts)" : (m.type === 'meteor' ? "Daño del Meteorito (pts)" : "Daño (pts)")))), 
                                           bulletSpeed: m.type === 'bomb' ? "Velocidad de Bomba (px/s)" : (m.type === 'wind_wall' ? "Vel. Pared de Viento (px/s)" : (m.type === 'burrow' ? "Vel. de Zambullida (px/s)" : "Vel. Bala (px/s)")), 
                                           fireRange: m.type === 'bomb' ? "Alcance de Lanzamiento (px)" : (m.type === 'circle_cast' ? "Radio de Explosión (px)" : (m.type === 'reflect' ? "Alcance de Activación (px)" : (m.type === 'survival_dome' ? "Radio de la Explosión (px)" : (m.type === 'wind_wall' ? "Alcance de la Pared (px)" : (m.type === 'burrow' ? "Alcance de Selección de Objetivo (px)" : "Alcance (px)"))))),
                                          fireRate: "Cadencia (ms)", 
                                      burstShots: "Proyectiles por Ráfaga (uds)", 
                                          slowAmount: "Ralentización (pts)", 
                                          slowDuration: "Duración de Ralentización (ms)", 
                                          startDelay: "Delay Inicio (ms)", 
                                          lifetimeMs: "Combustible (ms)", 
                                          turnSpeed: "Agilidad de Giro (rad/s)", 
                                          chargeTimeMs: "Tiempo de Carga (ms)", 
                                          lockTimeMs: m.type === 'circle_cast' ? "Tiempo Fijo / Estático (ms)" : "Tiempo de Bloqueo (ms)", 
                                          isHoming: "Seguimiento (Homing)",
                                          orbitSpeed: "Vel. de Giro (rad/s)",
                                          circleCount: "Cant. de Círculos (uds)",
                                          orbitRadius: "Radio de Órbita (px)",
                                          orbitDuration: "Tiempo de Giro (ms)",
                                          staticTime: "Tiempo Estático (ms)",
                                           radius: m.type === 'spin_ring' ? "Radio del Círculo (px)" : (m.type === 'bomb' ? "Radio de Explosión (px)" : (m.type === 'wall_dome' ? "Radio del Domo (px)" : (m.type === 'burrow' ? "Radio del Círculo de Daño (px)" : "Radio del Aura (px)"))),
                                          damage: m.type === 'survival_dome' ? "Daño de la Explosión (pts)" : "Daño (pts)",
                                          intervalMs: "Intervalo de Tick (ms)",
                                          duration: m.type === 'sleep' ? "Duración del Sueño (ms)" : (m.type === 'reflect' ? "Duración del Escudo (ms)" : "Duración Total (ms)"),
                                          cooldown: "Enfriamiento (CD) (ms)",
                                          pullSpeed: "Vel. Atracción (px/s)",
                                          stunDuration: "Duración de Stun (ms)",
                                          safeRadius: "Radio del Domo Seguro (px)",
                                          maxOffset: "Radio Máximo de Dispersión (px)",
                                          castTimeMs: m.type === 'circle_cast' ? "Tiempo de Carga (ms)" : "Tiempo de Casteo (ms)",
                                          postCastWaitMs: "Espera Post-Explosión del Enemigo (ms)",
                                          applyBleed: "Aplicar Debuff: Sangrado",
                                          bleedDurationMs: "Duración del Sangrado (ms)",
                                          bleedDps: "Daño por Segundo de Sangrado (pts/s)",
                                          applyStun: "Aplicar Debuff: Parálisis",
                                          stunDurationMs: "Duración de la Parálisis (ms)",
                                          applyPoison: "Aplicar Debuff: Veneno",
                                          poisonDurationMs: "Duración del Veneno (ms)",
                                          poisonDps: "Daño por Segundo de Veneno (pts/s)",
                                          postHookWaitMs: "Espera Post-Gancho (ms)",
                                          hookMissWaitMs: "Espera por Fallo (ms)",
                                           bulletCount: m.type === 'polymorph' ? "Cantidad de Cubos (uds)" : "Cantidad de Proyectiles (uds)",
                                           isPointAndClick: m.type === 'polymorph' ? "Apuntado y Disparado (Sí/No)" : "Apuntado y Disparado",
                                           polyDuration: "Duración del Polimorfismo (ms)",
                                           canMove: "Puede Moverse (Sí/No)",
                                           canUseSkills: "Puede Usar Habilidades (Sí/No)",
                                           meteorCount: m.type === 'meteor' ? "Cantidad de Meteoritos (uds)" : "Cantidad de Meteoritos (uds)",
                                           fallHeight: "Altura de Caída (px)",
                                           fallSpeed: "Velocidad de Caída (px/s)",
                                           meteorSize: "Tamaño del Meteorito (px)",
                                           explosionRadius: "Radio de Explosión (px)",
                                           warnTimeMs: m.type === 'burrow' ? "Duración del Círculo de Aviso (ms)" : (m.type === 'meteor' ? "Tiempo de Aviso en el Piso (ms)" : "Tiempo de Aviso (ms)"),
                                           persistentZone: m.type === 'meteor' ? "¿Dejar Zona Persistente en el Piso? (Sí/No)" : "¿Zona Persistente? (Sí/No)",
                                           zoneDamage: "Daño por Tick de Zona (pts)",
                                           zoneTickMs: "Intervalo de Tick de Zona (ms)",
                                           zoneDuration: "Duración de la Zona en el Piso (ms)",
                                           activationHP: "Activación por HP (%)",
                                          reductionPercentage: "Reducción de Daño (%)",
                                          shieldRegen: "Regen. de Escudo (pts/s)",
                                          healAmount: "Curación por Pulso (pts)",
                                          speedBonus: "Bono de Velocidad (px/s)",
                                          explosionDamage: "Daño de Explosión (pts)",
                                           castTimeMs: m.type === 'circle_cast' ? "Tiempo de Carga (ms)" : (m.type === 'wind_wall' ? "Tiempo de Carga de la Pared (ms)" : (m.type === 'burrow' ? "Tiempo de Hundimiento (ms)" : "Tiempo de Casteo (ms)")),
                                          castSpeed: "Velocidad de Casteo (x)",
                                          coneAngle: "Ángulo del Cono (grados)",
                                          coneFollow: "Seguimiento Dinámico (Homing)",
                                          lockTimeMs: m.type === 'circle_cast' ? "Tiempo Fijo / Estático (ms)" : "Tiempo de Bloqueo (ms)",
                                          aimDelayMs: "Espera de Apuntado (ms)",
                                          bombCount: "Cantidad de Bombas (uds)",
                                          bombDelayMs: "Espera entre Bombas (ms)",
                                          fuseTimeMs: "Retardo de Explosión (ms)",
                                          targetCount: "Cantidad de Objetivos (uds)",
                                          slowPercentage: m.slowIsPercentage ? "Porcentaje de Ralentización (%)" : "Ralentización Fija (pts)",
                                          damagePerSecond: "Daño por Segundo (pts/s)",
                                          nightmareMultiplier: "Multiplicador de Pesadilla (x)",
                                          wakeOnDamage: "Despierta al Recibir Daño (Sí/No)",
                                          reflect_mult: "Multiplicador de Reflejo (x)",
                                          spinSpeed: "Velocidad de Giro (rad/s)",
                                          speedBuffAmount: "Bono Velocidad Movimiento Dueño (px/s)",
                                          speedBuffDuration: "Duración Bono Velocidad Dueño (ms)",
                                          applySlow: "Aplicar Ralentización al Enemigo",
                                          slowIsPercentage: "Ralentización es Porcentual (si no, es Fija)",
                                          slowDuration: "Duración de Ralentización (ms)",
                                          activationMode: "Modo de Activación",
                                          activationHPs: "Activadores de Vida (%)",
                                          activationIntervalMs: "Intervalo de Activación en Combate (ms)",
                                          summonCount: "Cantidad de Invocaciones (uds)",
                                          spawnRadius: "Radio de Invocación (px)",
                                          summonDurationMode: "Modo de Duración de Invocación",
                                          summonDurationMs: "Tiempo de Vida de Invocación (ms)",
                                           summonsList: "Lista de Esbirros Invocados",
                                            tick_interval: "Intervalo de Tick (ms)",
                                            damage_per_tick: "Daño por Tick (pts)",
                                            slow_amount: "Ralentización (0-1)",
                                            projectileCount: "Cantidad de Gusanos (uds)",
                                            spreadAngle: "Ángulo del Abanico (grados)",
                                            parkTimeMs: "Tiempo Quieto en el Extremo (ms)",
                                            returnDamage: "Daño de Vuelta (pts)",
                                             wallWidth: "Ancho de la Pared (px)",
                                             wallStartOffset: "Spawn Adelante del Enemigo (px)",
                                             pushForce: "Distancia de Expulsión (px)",
                                             burrowSpeed: "Vel. Viaje Subterráneo (px/s)",
                                             undergroundMs: "Tiempo Bajo Tierra en el Destino (ms)",
                                             burstMode: "Modo del Círculo de Daño",
                                             zoneDuration: "Duración de Zona Persistente (ms)",
                                             zoneTickMs: "Intervalo de Tick de Zona (ms)",
                                             zoneDamage: "Daño por Tick de Zona (pts)"
                                        };
                                     if (f === 'activationMode') {
                                         const mode = m.activationMode || 'hp';
                                         return `
                                             <div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.05); padding: 10px; border-radius: 8px; border: 1px solid rgba(239, 68, 68, 0.2); display: flex; flex-direction: column; gap: 8px;">
                                                 <label style="color:#ef4444; font-weight:bold; font-size:0.75rem;">MODO DE ACTIVACIÓN</label>
                                                 <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationMode = this.value; if(this.value === 'time') { delete config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs; } else { delete config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationIntervalMs; } renderEnemyDetail();">
                                                     <option value="hp" ${mode === 'hp' ? 'selected' : ''}>🩸 Por Porcentaje de Vida (HP)</option>
                                                     <option value="time" ${mode === 'time' ? 'selected' : ''}>⏳ Por Tiempo en Combate</option>
                                                 </select>
                                             </div>
                                         `;
                                     }
                                     if (f === 'activationHPs') {
                                         if (m.activationMode === 'time') return '';
                                         const hps = m.activationHPs || [50];
                                         m.activationHPs = hps;
                                         return `
                                             <div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(239, 68, 68, 0.2); display: flex; flex-direction: column; gap: 10px;">
                                                 <div style="display:flex; justify-content:space-between; align-items:center;">
                                                     <label style="color:#ef4444; font-size:0.75rem;">ACTIVADORES DE VIDA (%)</label>
                                                     <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.65rem; background:#ef4444;" onclick="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs.push(50); renderEnemyDetail();">+ AGREGAR HP</button>
                                                 </div>
                                                 <div style="display:flex; flex-wrap:wrap; gap:8px;">
                                                     ${hps.map((hpVal, hpIdx) => `
                                                         <div style="display:flex; align-items:center; gap:4px; background:#0f172a; padding:4px 8px; border-radius:4px; border:1px solid #334155;">
                                                             <input type="number" value="${hpVal}" style="width:55px; background:transparent; border:none; color:white; text-align:center; padding:0; font-size:0.8rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs[${hpIdx}] = parseFloat(this.value)">
                                                             <span style="color:var(--text-dim); font-size:0.8rem;">%</span>
                                                             <button style="background:none; border:none; color:#ef4444; font-weight:bold; cursor:pointer; font-size:0.8rem; margin-left:4px;" onclick="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationHPs.splice(${hpIdx}, 1); renderEnemyDetail();">✕</button>
                                                         </div>
                                                     `).join('')}
                                                 </div>
                                             </div>
                                         `;
                                     }
                                     if (f === 'activationIntervalMs') {
                                         if (m.activationMode !== 'time') return '';
                                         const interval = m.activationIntervalMs || 30000;
                                         m.activationIntervalMs = interval;
                                         return `
                                             <div class="field" style="grid-column: 1 / -1;"><label>Intervalo de Activación en Combate (ms)</label><input type="number" value="${interval}" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].activationIntervalMs = parseInt(this.value)"></div>
                                         `;
                                     }
                                     if (f === 'summonDurationMode') {
                                         const mode = m.summonDurationMode || 'until_death';
                                         return `
                                             <div class="field" style="grid-column: 1 / -1;"><label>Modo de Duración de Refuerzos</label>
                                                 <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].summonDurationMode = this.value; renderEnemyDetail();">
                                                     <option value="until_death" ${mode === 'until_death' ? 'selected' : ''}>🧟 Hasta ser destruidos</option>
                                                     <option value="timed" ${mode === 'timed' ? 'selected' : ''}>⏳ Por tiempo limitado</option>
                                                 </select>
                                             </div>
                                         `;
                                     }
                                     if (f === 'summonDurationMs') {
                                         if (m.summonDurationMode !== 'timed') return '';
                                         return `<div class="field"><label>Tiempo de Vida de Invocación (ms)</label><input type="number" value="${m.summonDurationMs || 10000}" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].summonDurationMs = parseInt(this.value)"></div>`;
                                     }
                                     if (f === 'summonsList') {
                                         const count = parseInt(m.summonCount) || 1;
                                         if (!m.summonsList) m.summonsList = [];
                                         while (m.summonsList.length < count) {
                                             m.summonsList.push("random_base");
                                         }
                                         if (m.summonsList.length > count) {
                                             m.summonsList.splice(count);
                                         }
                                         
                                         return `
                                             <div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(239, 68, 68, 0.2); display: flex; flex-direction: column; gap: 10px;">
                                                 <label style="color:#ef4444; font-size:0.75rem; font-weight:bold;">CONFIGURACIÓN INDIVIDUAL DE ESBIRROS</label>
                                                 <div class="form-grid" style="display:grid; grid-template-columns: 1fr; gap:8px;">
                                                     ${m.summonsList.map((choice, sIdx) => {
                                                         return `
                                                             <div style="display:flex; flex-direction:column; gap:4px; background:#0f172a; padding:8px; border-radius:6px; border:1px solid #334155;">
                                                                 <label style="font-size:0.65rem; color:var(--text-dim);">Esbirro #${sIdx + 1}</label>
                                                                 <select style="background:#0f172a; border:none; color:white; font-size:0.8rem; width:100%;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].summonsList[${sIdx}] = this.value; renderEnemyDetail();">
                                                                     <option value="random_base" ${choice === 'random_base' ? 'selected' : ''}>🔀 Servidor (Cualquier Regular Base)</option>
                                                                     <option value="random_boss" ${choice === 'random_boss' ? 'selected' : ''}>💀 Servidor (Cualquier Boss)</option>
                                                                     <option value="random_tier_a" ${choice === 'random_tier_a' ? 'selected' : ''}>⭐ Servidor (Cualquier Tier A)</option>
                                                                     <option value="random_tier_b" ${choice === 'random_tier_b' ? 'selected' : ''}>⭐⭐ Servidor (Cualquier Tier B)</option>
                                                                     <option value="random_tier_c" ${choice === 'random_tier_c' ? 'selected' : ''}>⭐⭐⭐ Servidor (Cualquier Tier C)</option>
                                                                     <option value="random_tier_d" ${choice === 'random_tier_d' ? 'selected' : ''}>⭐⭐⭐⭐ Servidor (Cualquier Tier D)</option>
                                                                     <option value="random" ${choice === 'random' ? 'selected' : ''}>🌀 Servidor (Cualquier Enemigo)</option>
                                                                     ${Object.keys(config.enemyModels || {}).map(id => {
                                                                         const enName = config.enemyModels[id].name || 'Enemigo';
                                                                         return `<option value="${id}" ${choice === id ? 'selected' : ''}>${enName} (#${id})</option>`;
                                                                     }).join('')}
                                                                 </select>
                                                             </div>
                                                         `;
                                                     }).join('')}
                                                 </div>
                                             </div>
                                         `;
                                     }
                                     if (f === 'isHoming') return `<div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.05); padding: 10px; border-radius: 8px; flex-direction: column; gap: 12px; border: 1px solid rgba(239, 68, 68, 0.2);"><div style="display:flex; align-items:center; gap:12px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:20px; height:20px; cursor:pointer;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].isHoming = this.checked; renderEnemyDetail();"><label style="margin:0; font-size: 0.85rem; color: #ef4444; cursor:pointer;">ACTIVAR SEGUIMIENTO AL OBJETIVO</label></div>${m.isHoming ? `<div style="padding-top: 10px; border-top: 1px solid rgba(239, 68, 68, 0.2);"><label style="font-size: 0.65rem; color: var(--text-dim);">AGILIDAD DE GIRO (RAD/S)</label><input type="number" step="0.1" value="${m.turnSpeed || 2.5}" style="background:rgba(0,0,0,0.3); margin-top:5px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].turnSpeed = parseFloat(this.value)"></div>` : ''}</div>`;
                                     if (f === 'coneFollow') return `<div class="field" style="display:flex; flex-direction:column; gap:8px;"><label>${fieldLabelsMap[f] || f}</label><div style="display:flex; align-items:center; height:40px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].coneFollow = this.checked; renderEnemyDetail();"></div></div>`;
                                     if (f === 'wakeOnDamage') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] !== false ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].wakeOnDamage = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                     if (f === 'applySlow') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].applySlow = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
if (f === 'slowIsPercentage') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].slowIsPercentage = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                      if (f === 'isPointAndClick') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].isPointAndClick = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                      if (f === 'canMove') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].canMove = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                       if (f === 'canUseSkills') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].canUseSkills = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                       if (f === 'persistentZone') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:10px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:22px; height:22px; cursor:pointer; margin:0;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].persistentZone = this.checked; renderEnemyDetail();"><label style="margin:0; cursor:pointer;">${fieldLabelsMap[f] || f}</label></div>`;
                                      
                                       if (f === 'debuffsList') {
                                          if (!m.debuffsList) m.debuffsList = [];
                                          return `
                                              <div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(239, 68, 68, 0.2); display: flex; flex-direction: column; gap: 10px;">
                                                  <div style="display:flex; justify-content:space-between; align-items:center;">
                                                       <label style="color:#ef4444; font-size:0.75rem; font-weight:bold;">EFECTOS ALTERADOS (DEBUFFS) ${m.type === 'worm_boomerang' ? 'AL IMPACTAR EN LA VUELTA' : (m.type === 'wind_wall' ? 'AL ARROLLAR AL JUGADOR' : (m.type === 'burrow' ? 'AL EMERGER / EN LA ZONA' : (m.type === 'meteor' ? 'AL IMPACTAR EL METEORITO' : 'AL EXPLOTAR')))}</label>
                                                      <div style="display:flex; gap:5px;">
                                                          <select id="new-debuff-select-${idx}" style="background:#0f172a; color:white; font-size:0.75rem; border-radius:4px; padding:2px 4px; border:1px solid #334155;">
                                                              <option value="bleed">🩸 Sangrado</option>
                                                              <option value="poison">🤢 Veneno</option>
                                                              <option value="stun">⚡ Parálisis</option>
                                                              <option value="slow">🐢 Ralentización (Slow)</option>
                                                          </select>
                                                          <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.65rem; background:#ef4444;" onclick="const type = document.getElementById('new-debuff-select-${idx}').value; const debuffDefaults = { bleed: { type: 'bleed', dps: 30, duration: 4000, tickInterval: 1000 }, poison: { type: 'poison', dps: 20, duration: 4000, tickInterval: 1000 }, stun: { type: 'stun', duration: 1500 }, slow: { type: 'slow', amount: 50, duration: 2500, isPercentage: true } }; config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList.push(JSON.parse(JSON.stringify(debuffDefaults[type]))); renderEnemyDetail();">+ AGREGAR DEBUFF</button>
                                                      </div>
                                                  </div>
                                                  <div style="display:grid; grid-template-columns: 1fr; gap:8px;">
                                                      ${m.debuffsList.map((d, dIdx) => {
                                                          let fieldsHtml = '';
                                                          if (d.type === 'bleed' || d.type === 'poison') {
                                                              fieldsHtml = `
                                                                  <div style="display:grid; grid-template-columns: 1fr 1fr 1fr; gap:8px; width:100%;">
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Daño (pts/tick)</label>
                                                                          <input type="number" value="${d.dps || 20}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].dps = parseInt(this.value)">
                                                                      </div>
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Duración (ms)</label>
                                                                          <input type="number" value="${d.duration || 4000}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].duration = parseInt(this.value)">
                                                                      </div>
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Intervalo Tick (ms)</label>
                                                                          <input type="number" value="${d.tickInterval || 1000}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].tickInterval = parseInt(this.value)">
                                                                      </div>
                                                                  </div>
                                                              `;
                                                          } else if (d.type === 'stun') {
                                                              fieldsHtml = `
                                                                  <div style="display:grid; grid-template-columns: 1fr; gap:8px; width:100%;">
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Duración de Parálisis (ms)</label>
                                                                          <input type="number" value="${d.duration || 1500}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].duration = parseInt(this.value)">
                                                                      </div>
                                                                  </div>
                                                              `;
                                                          } else if (d.type === 'slow') {
                                                              fieldsHtml = `
                                                                  <div style="display:grid; grid-template-columns: 1fr 1fr 1fr; gap:8px; width:100%;">
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Cantidad de Ralentización</label>
                                                                          <input type="number" value="${d.amount || 50}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].amount = parseInt(this.value)">
                                                                      </div>
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Duración (ms)</label>
                                                                          <input type="number" value="${d.duration || 2500}" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].duration = parseInt(this.value)">
                                                                      </div>
                                                                      <div>
                                                                          <label style="font-size:0.65rem; color:var(--text-dim);">Tipo de Ralentización</label>
                                                                          <select style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList[${dIdx}].isPercentage = this.value === 'percent';">
                                                                              <option value="percent" ${d.isPercentage !== false ? 'selected' : ''}>% Porcentaje</option>
                                                                              <option value="fixed" ${d.isPercentage === false ? 'selected' : ''}>🔢 Fijo (px/s)</option>
                                                                          </select>
                                                                      </div>
                                                                  </div>
                                                              `;
                                                          }

                                                          return `
                                                              <div style="display:flex; flex-direction:column; gap:6px; background:#0f172a; padding:8px; border-radius:6px; border:1px solid #334155; position:relative;">
                                                                  <div style="display:flex; justify-content:space-between; align-items:center; border-bottom: 1px solid #1e293b; padding-bottom: 4px;">
                                                                      <span style="font-size:0.75rem; font-weight:bold; color:#ef4444;">
                                                                          ${d.type === 'bleed' ? '🩸 Sangrado' : (d.type === 'poison' ? '🤢 Veneno' : (d.type === 'stun' ? '⚡ Parálisis' : '🐢 Ralentización (Slow)'))}
                                                                      </span>
                                                                      <button style="background:none; border:none; color:#ef4444; font-weight:bold; cursor:pointer; font-size:0.8rem;" onclick="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].debuffsList.splice(${dIdx}, 1); renderEnemyDetail();">✕</button>
                                                                  </div>
                                                                  ${fieldsHtml}
                                                              </div>
                                                          `;
                                                      }).join('')}
                                                  </div>
                                              </div>
                                          `;
                                      }
                                     
                                      if (f === 'targetMode') {
                                          const val = m[f] || 'proximity';
                                          if (m.type === 'burrow' || m.type === 'meteor') {
                                              return `<div class="field"><label>${m.type === 'meteor' ? 'Criterio de Selección de Objetivos' : 'Selección de Objetivo'}</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].targetMode = this.value; renderEnemyDetail();">
                                              <option value="proximity" ${val === 'proximity' ? 'selected' : ''}>📏 Proximidad (Más cercano)</option>
                                              <option value="random" ${val === 'random' ? 'selected' : ''}>🔀 Aleatorio</option>
                                              <option value="farthest" ${val === 'farthest' ? 'selected' : ''}>📐 Más Lejano</option>
                                              <option value="lowest_hp" ${val === 'lowest_hp' ? 'selected' : ''}>❤️ Menos Vida</option>
                                              <option value="highest_hp" ${val === 'highest_hp' ? 'selected' : ''}>💪 Más Vida</option>
                                              <option value="highest_damage" ${val === 'highest_damage' ? 'selected' : ''}>⚔️ Mayor Daño Causado</option>
                                              <option value="highest_heal" ${val === 'highest_heal' ? 'selected' : ''}>💚 Mayor Curación</option>
                                          </select></div>`;
                                          }
                                         return `<div class="field"><label>Criterio de Selección</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].targetMode = this.value; renderEnemyDetail();">
                                             <option value="proximity" ${val === 'proximity' ? 'selected' : ''}>📏 Proximidad (Más cercano)</option>
                                             <option value="random" ${val === 'random' ? 'selected' : ''}>🔀 Aleatorio</option>
                                             <option value="max_hp" ${val === 'max_hp' ? 'selected' : ''}>❤️ Vida Máxima Mayor</option>
                                             <option value="missing_hp" ${val === 'missing_hp' ? 'selected' : ''}>💔 Vida Faltante Mayor</option>
                                         </select></div>`;
                                     }
                                     if (f === 'burstMode') {
                                         const val = m[f] || 'burst';
                                         return `<div class="field"><label>Modo del Círculo de Daño</label><select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].burstMode = this.value; renderEnemyDetail();">
                                             <option value="burst" ${val === 'burst' ? 'selected' : ''}>💥 Golpe Único al Emerger</option>
                                             <option value="zone" ${val === 'zone' ? 'selected' : ''}>🌀 Zona Persistente (Daño en el Piso)</option>
                                         </select></div>`;
                                     }
                                     if (f === 'turnSpeed') return '';
                                      if ((f === 'zoneTickMs' || f === 'zoneDuration' || f === 'zoneDamage') && (m.burstMode || 'burst') !== 'zone' && !m.persistentZone) return '';
                                     return `<div class="field"><label>${fieldLabelsMap[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].${f} = parseFloat(this.value); if ('${f}' === 'summonCount') renderEnemyDetail();"></div>`;
                                }).join('')}
                            </div>
                        </div>
                    `).join('')}
                </div>

                <div style="display:flex; justify-content:space-between; align-items:center; margin-top:2rem; margin-bottom:1rem;">
                    <label style="color:#3b82f6; font-size: 0.8rem; font-weight:bold;">🛡️ MECÁNICAS DE DEFENSA ACTIVAS</label>
                    <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background: #3b82f6; box-shadow: 0 4px 15px rgba(59, 130, 246, 0.3);" onclick="addDefenseMechanic('${selectedEnemyId}')">+ AGREGAR DEFENSA</button>
                </div>
                <div id="defense-mech-list-${selectedEnemyId}">
                    ${en.defenseMechanics.map((m, idx) => `
                        <div class="card" style="margin-bottom: 1rem; position:relative; padding: 1rem; background: rgba(59, 130, 246, 0.05); border: 1px solid rgba(59, 130, 246, 0.2);">
                            <div style="position:absolute; top:8px; right:8px; display:flex; gap:10px;">
                                <button style="background:none; border:none; color:#3b82f6; cursor:pointer; font-weight:bold;" onclick="moveDefenseMechanic('${selectedEnemyId}', ${idx}, -1)">SUBIR</button>
                                <button style="background:none; border:none; color:#3b82f6; cursor:pointer; font-weight:bold;" onclick="moveDefenseMechanic('${selectedEnemyId}', ${idx}, 1)">BAJAR</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="removeDefenseMechanic('${selectedEnemyId}', ${idx})">✕</button>
                            </div>
                            <div class="field full">
                                <select style="background:#0f172a; border:none; color:#3b82f6; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" onchange="updateDefenseMechanicType('${selectedEnemyId}', ${idx}, this.value)">
                                    ${Object.keys(DEFENSE_LIB).map(type => `<option value="${type}" ${m.type === type ? 'selected' : ''} style="background:#0f172a; color:white;">${DEFENSE_LIB[type].icon} ${DEFENSE_LIB[type].label}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-grid" style="margin-top:1rem;">
                                ${DEFENSE_LIB[m.type || 'basic_defense'].fields.map(f => {
                                    const defLabels = { 
                                        reductionPercentage: "Reducción (%)", 
                                        shieldRegen: "Regen. Escudo (pts/s)", 
                                        duration: "Duración (ms)", 
                                        cooldown: "Recarga (ms)", 
                                        startDelay: "Retraso Inicio (ms)",
                                        reflect_mult: "Multiplicador de Reflejo (x)",
                                        activationMode: "Modo de Activación",
                                        activationHPs: "Activadores de Vida (%)",
                                        activationIntervalMs: "Intervalo de Activación en Combate (ms)",
                                        radius: m.type === 'wall_dome' ? "Radio del Domo (px)" : "Radio del Aura (px)",
                                        healAmount: "Cura por Pulso (pts)",
                                        intervalMs: "Intervalo de Tick (ms)",
                                        activationHP: "Activación por HP (%)",
                                        affectsEnemies: "Afectar a otros Enemigos", 
                                        affectsBosses: "Afectar a Bosses",
                                        pillarCount: "Cantidad de Pilares (uds)",
                                        pillarType: "Tipo de Pilar (ID)",
                                        pillarHp: "Vida del Pilar (pts)",
                                        pillarShield: "Escudo del Pilar (pts)",
                                        pillarName: "Nombre del Pilar",
                                        spawnRadius: "Distancia de Spawn (px)",
                                        healIntervalMs: "Intervalo Curación (ms)",
                                        healPercentPerTick: "Curación por Tick (%)",
                                        healPercentPerPillarOnExpiry: "Curación por Pilar Restante (%)",
                                        orbCount: "Cantidad de Orbes (uds)",
                                        orbSpeed: "Velocidad de Orbes (px/s)",
                                        playerDamage: "Daño al Jugador (HP)",
                                        bossHealPercent: "Curación al Boss por Orbe (%)",
                                        invisType: "Tipo de Ocultamiento",
                                        keepAttacking: "Ataca Invisible",
                                        changeSpeed: "Modificar Velocidad",
                                        invisSpeedMultiplier: "Multiplicador de Velocidad (x)",
                                        cloneCount: "Cantidad de Clones (uds)",
                                        cloneHp: "Vida de Clones (pts)",
                                        cloneShield: "Escudo de Clones (pts)",
                                        cloneSpeed: "Velocidad de Clones (px/s)",
                                        cloneDuration: "Duración de Clones (ms)",
                                        cloneExplosionDamage: "Daño de Explosión (pts)",
                                        cloneHealAmount: "Curación al original (pts)",
                                        cloneExplodeOnExpiry: "Perseguir y explotar al expirar",
                                        fireRange: "Distancia de Disparo (px)",
                                        bulletSpeed: "Velocidad del Proyectil (px/s)",
                                        bulletDamage: "Daño del Proyectil (pts)",
                                        stealMode: "Modo de Robo",
                                        stealAmount: "Cantidad de Robo",
                                        stealIntervalMs: "Intervalo de Robo (ms)",
                                        targetMode: "Selección del Objetivo",
                                        giveToEnemy: "Transferir Escudo Robado al Enemigo"
                                    };
                                    if (f === 'invisType') {
                                        const type = m.invisType || 'invisibility';
                                        m.invisType = type;
                                        return `
                                            <div class="field" style="grid-column: 1 / -1;"><label>Tipo de Ocultamiento</label>
                                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].invisType = this.value; renderEnemyDetail();">
                                                    <option value="invisibility" ${type === 'invisibility' ? 'selected' : ''}>👤 Invisibilidad (Totalmente Oculto)</option>
                                                    <option value="camouflage" ${type === 'camouflage' ? 'selected' : ''}>👻 Camuflaje (Transparente)</option>
                                                </select>
                                            </div>
                                        `;
                                    }
                                    if (f === 'keepAttacking') {
                                        const checked = m.keepAttacking !== false;
                                        if (m.keepAttacking === undefined) m.keepAttacking = true;
                                        return `
                                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                                                <input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].keepAttacking = this.checked">
                                                <label style="margin:0;">Seguir atacando mientras está invisible</label>
                                            </div>
                                        `;
                                    }
                                    if (f === 'changeSpeed') {
                                        const checked = !!m.changeSpeed;
                                        if (m.changeSpeed === undefined) m.changeSpeed = false;
                                        return `
                                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                                                <input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].changeSpeed = this.checked; renderEnemyDetail();">
                                                <label style="margin:0;">Modificar velocidad de movimiento</label>
                                            </div>
                                        `;
                                    }
                                    if (f === 'invisSpeedMultiplier') {
                                        if (!m.changeSpeed) return '';
                                        const mult = m.invisSpeedMultiplier !== undefined ? m.invisSpeedMultiplier : 1.0;
                                        m.invisSpeedMultiplier = mult;
                                        return `
                                            <div class="field"><label>Multiplicador de Velocidad (x)</label>
                                                <input type="number" step="0.1" value="${mult}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].invisSpeedMultiplier = parseFloat(this.value)">
                                            </div>
                                        `;
                                    }
                                    if (f === 'activationMode') {
                                        const mode = m.activationMode || 'hp';
                                        return `
                                            <div class="field" style="grid-column: 1 / -1; background: rgba(59, 130, 246, 0.05); padding: 10px; border-radius: 8px; border: 1px solid rgba(59, 130, 246, 0.2); display: flex; flex-direction: column; gap: 8px;">
                                                <label style="color:#60a5fa; font-weight:bold; font-size:0.75rem;">MODO DE ACTIVACIÓN</label>
                                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationMode = this.value; if(this.value === 'time') { delete config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs; } else { delete config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationIntervalMs; } renderEnemyDetail();">
                                                    <option value="hp" ${mode === 'hp' ? 'selected' : ''}>🩸 Por Porcentaje de Vida (HP)</option>
                                                    <option value="time" ${mode === 'time' ? 'selected' : ''}>⏳ Por Tiempo en Combate</option>
                                                </select>
                                            </div>
                                        `;
                                    }
                                    if (f === 'activationHPs') {
                                        if (m.activationMode === 'time') return '';
                                        const hps = m.activationHPs || [70];
                                        m.activationHPs = hps;
                                        return `
                                            <div class="field" style="grid-column: 1 / -1; background: rgba(59, 130, 246, 0.02); padding: 10px; border-radius: 8px; border: 1px dashed rgba(59, 130, 246, 0.2); display: flex; flex-direction: column; gap: 10px;">
                                                <div style="display:flex; justify-content:space-between; align-items:center;">
                                                    <label style="color:#60a5fa; font-size:0.75rem;">ACTIVADORES DE VIDA (%)</label>
                                                    <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.65rem; background:#3b82f6;" onclick="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs.push(50); renderEnemyDetail();">+ AGREGAR HP</button>
                                                </div>
                                                <div style="display:flex; flex-wrap:wrap; gap:8px;">
                                                    ${hps.map((hpVal, hpIdx) => `
                                                        <div style="display:flex; align-items:center; gap:4px; background:#0f172a; padding:4px 8px; border-radius:4px; border:1px solid #334155;">
                                                            <input type="number" value="${hpVal}" style="width:55px; background:transparent; border:none; color:white; text-align:center; padding:0; font-size:0.8rem;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs[${hpIdx}] = parseFloat(this.value)">
                                                            <span style="color:var(--text-dim); font-size:0.8rem;">%</span>
                                                            <button style="background:none; border:none; color:#ef4444; font-weight:bold; cursor:pointer; font-size:0.8rem; margin-left:4px;" onclick="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationHPs.splice(${hpIdx}, 1); renderEnemyDetail();">✕</button>
                                                        </div>
                                                    `).join('')}
                                                </div>
                                            </div>
                                        `;
                                    }
                                    if (f === 'activationIntervalMs') {
                                        if (m.activationMode !== 'time') return '';
                                        const interval = m.activationIntervalMs || 45000;
                                        m.activationIntervalMs = interval;
                                        return `
                                            <div class="field" style="grid-column: 1 / -1;"><label>Intervalo de Activación en Combate (ms)</label><input type="number" value="${interval}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].activationIntervalMs = parseInt(this.value)"></div>
                                        `;
                                    }
                                    if (['affectsEnemies', 'affectsBosses', 'cloneExplodeOnExpiry'].includes(f)) {
                                         const checked = f === 'cloneExplodeOnExpiry' ? m[f] !== false : !!m[f];
                                         return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;"><input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].${f} = this.checked"><label style="margin:0;">${defLabels[f]}</label></div>`;
                                    }
                                    if (f === 'pillarName') return `<div class="field" style="grid-column: 1 / -1;"><label>${defLabels[f] || f}</label><input type="text" value="${m[f] || 'Pilar Protector'}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].${f} = this.value"></div>`;
                                    if (f === 'stealMode') {
                                        const mode = m.stealMode || 'flat';
                                        return `
                                            <div class="field" style="grid-column: 1 / -1;"><label>Modo de Robo de Escudo</label>
                                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].stealMode = this.value; renderEnemyDetail();">
                                                    <option value="flat" ${mode === 'flat' ? 'selected' : ''}>📏 Plano (pts por tick)</option>
                                                    <option value="percent" ${mode === 'percent' ? 'selected' : ''}>📊 Porcentual (del escudo max del jugador)</option>
                                                </select>
                                            </div>
                                        `;
                                    }
                                    if (f === 'targetMode') {
                                        const tmode = m.targetMode || 'proximity';
                                        return `
                                            <div class="field" style="grid-column: 1 / -1;"><label>Selección del Objetivo</label>
                                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].targetMode = this.value; renderEnemyDetail();">
                                                    <option value="proximity" ${tmode === 'proximity' ? 'selected' : ''}>📍 Más Cercano</option>
                                                    <option value="random" ${tmode === 'random' ? 'selected' : ''}>🎲 Aleatorio</option>
                                                    <option value="lowest_hp" ${tmode === 'lowest_hp' ? 'selected' : ''}>🥶 Menor Vida (%)</option>
                                                    <option value="highest_hp" ${tmode === 'highest_hp' ? 'selected' : ''}>🫀 Mayor Vida (%)</option>
                                                    <option value="highest_shield" ${tmode === 'highest_shield' ? 'selected' : ''}>💠 Mayor Escudo</option>
                                                    <option value="highest_damage" ${tmode === 'highest_damage' ? 'selected' : ''}>⚔️ Mayor Daño Causado</option>
                                                </select>
                                            </div>
                                        `;
                                    }
                                    if (f === 'giveToEnemy') {
                                        const checked = m.giveToEnemy !== false;
                                        if (m.giveToEnemy === undefined) m.giveToEnemy = true;
                                        return `
                                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                                                <input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].giveToEnemy = this.checked">
                                                <label style="margin:0;">Transferir Escudo Robado al Enemigo</label>
                                            </div>
                                        `;
                                    }
                                    if (f === 'isPointAndClick') {
                                        const checked = m.isPointAndClick === true;
                                        return `
                                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; grid-column: 1 / -1;">
                                                <input type="checkbox" ${checked ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].isPointAndClick = this.checked">
                                                <label style="margin:0; cursor:pointer;">Apuntado Directo (Point & Click / Inesquivable)</label>
                                            </div>
                                        `;
                                    }
                                    return `<div class="field"><label>${defLabels[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].${f} = parseFloat(this.value)"></div>`;
                                }).join('')}
                            </div>
                            ${m.type === 'duplicado' ? (function() {
                                 if (!m.clonesList) m.clonesList = [];
                                 const cloneCount = parseInt(m.cloneCount) || 1;
                                 while (m.clonesList.length < cloneCount) {
                                     m.clonesList.push({
                                         hp: 1000,
                                         shield: 200,
                                         role: "damage",
                                         value: 500
                                     });
                                 }
                                 if (m.clonesList.length > cloneCount) {
                                     m.clonesList.splice(cloneCount);
                                 }
                                 return `
                                     <div style="margin-top:1.5rem; padding-top:1rem; border-top:1px dashed rgba(59, 130, 246, 0.3);">
                                         <h5 style="color:#60a5fa; font-size:0.8rem; font-weight:bold; margin-bottom:1rem;">👥 CONFIGURACIÓN INDIVIDUAL DE CLONES</h5>
                                         <div style="display:flex; flex-direction:column; gap:10px;">
                                             ${m.clonesList.map((c, cloneIdx) => `
                                                 <div style="background:rgba(59, 130, 246, 0.02); padding:10px; border-radius:6px; border:1px solid rgba(59, 130, 246, 0.15);">
                                                     <div style="font-weight:bold; font-size:0.75rem; color:#93c5fd; margin-bottom:8px;">Clon #${cloneIdx + 1}</div>
                                                     <div class="form-grid" style="display:grid; grid-template-columns:1fr 1fr 1fr 1fr 1fr; gap:8px;">
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">HP (pts)</label>
                                                             <input type="number" value="${c.hp || 1000}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].hp = parseInt(this.value) || 0">
                                                         </div>
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">Escudo (pts)</label>
                                                             <input type="number" value="${c.shield || 200}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].shield = parseInt(this.value) || 0">
                                                         </div>
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">Rol / Función</label>
                                                             <select style="background:#0f172a; border:none; color:white; border-radius:4px; padding:4px; font-size:0.75rem;" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].role = this.value; renderEnemyDetail();">
                                                                 <option value="damage" ${c.role === 'damage' ? 'selected' : ''}>💥 Daño</option>
                                                                 <option value="heal" ${c.role === 'heal' ? 'selected' : ''}>💚 Curación</option>
                                                             </select>
                                                         </div>
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">${c.role === 'heal' ? 'Cura al original' : 'Daño explosión'}</label>
                                                             <input type="number" value="${c.value || 500}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].value = parseInt(this.value) || 0">
                                                         </div>
                                                         <div class="field" style="margin:0;"><label style="font-size:0.65rem;">Recarga Ataque (ms)</label>
                                                             <input type="number" value="${c.attackCooldownMs || 2000}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].clonesList[${cloneIdx}].attackCooldownMs = parseInt(this.value) || 2000">
                                                         </div>
                                                     </div>
                                                 </div>
                                             `).join('')}
                                         </div>
                                     </div>
                                 `;
                             })() : ''}
                        </div>
                    `).join('')}
                </div>

                <div style="display:flex; justify-content:space-between; align-items:center; margin-top:2rem; margin-bottom:1rem;">
                    <label style="color:var(--accent); font-size: 0.8rem; font-weight:bold;">🎁 CONFIGURACIÓN DE BOTÍN (LOOT DROPS)</label>
                    <div style="display: flex; gap: 10px; align-items: center;">
                        <button class="btn btn-primary" style="padding: 4px 10px; font-size: 0.65rem;" onclick="showLootTabForEnemy('${selectedEnemyId}')">🔍 Balancear en pantalla completa</button>
                        <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background: var(--accent); border-color: var(--accent); box-shadow: 0 4px 15px rgba(6, 182, 212, 0.3);" onclick="addLootDropFromComponent('${selectedEnemyId}', 'loot-table-component-threats')">+ AGREGAR DROP</button>
                    </div>
                </div>
                <div id="loot-table-component-threats" style="background: rgba(255,255,255,0.01); padding: 10px; border-radius: 8px;">
                    <!-- Rendered dynamically by component -->
                </div>
            </div>
        </div>
    `;
    setTimeout(() => {
        window.renderLootTableComponent(selectedEnemyId, 'loot-table-component-threats');
    }, 50);
}

function renderMechanicsLib() {
    const MECHANICS_LIB = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const MOVEMENT_LIB = config.movementLib || DEFAULT_MOVEMENT_LIB;
    const DEFENSE_LIB = config.defenseLib || DEFAULT_DEFENSE_LIB;

    const grid = document.getElementById('mechanics-lib-grid'); if(!grid) return;
    grid.innerHTML = '';
    const f = getFilter();
    const fieldLabels = { 
        "bulletDamage": "Daño", 
        "bulletSpeed": "Velocidad", 
        "fireRange": "Alcance (px)", 
        "fireRate": "Cadencia", 
        "burstShots": "Proyectiles por Ráfaga (uds)", 
        "staticTime": "Tiempo Estático",
        "reductionPercentage": "Reducción Daño",
        "shieldRegen": "Regen. Escudo",
        "duration": "Duración (ms)",
        "cooldown": "Enfriamiento (CD) (ms)",
        "radius": "Radio de Acción (px)",
        "damage": "Daño (pts)",
        "healAmount": "Cura por Pulso (pts)",
        "speedBonus": "Bono Velocidad (px/s)",
        "intervalMs": "Intervalo (ms)",
        "castTimeMs": "Tiempo de Casteo (ms)",
        "castSpeed": "Velocidad de Casteo (x)",
        "coneAngle": "Ángulo del Cono (grados)",
        "stunDuration": "Duración de Stun (ms)",
        "coneFollow": "Seguimiento Dinámico (Homing)",
        "lockTimeMs": "Tiempo de Bloqueo (ms)",
        "aimDelayMs": "Espera de Apuntado (ms)",
        "reflect_mult": "Multiplicador de Reflejo (x)",
        "activationMode": "Modo de Activación",
        "activationHPs": "Activadores de Vida (%)",
        "activationIntervalMs": "Intervalo de Activación en Combate (ms)",
        "summonCount": "Cantidad de Invocaciones (uds)",
        "spawnRadius": "Radio de Invocación (px)",
        "summonDurationMode": "Modo de Duración de Invocación",
        "summonDurationMs": "Tiempo de Vida de Invocación (ms)",
        "summonsList": "Lista de Esbirros Invocados",
        "tick_interval": "Intervalo de Tick (ms)",
        "damage_per_tick": "Daño por Tick (pts)",
        "slow_amount": "Ralentización (0-1)",
        "radius": "Radio (px)",
        "projectileCount": "Cantidad de Gusanos (uds)",
        "spreadAngle": "Ángulo del Abanico (grados)",
        "parkTimeMs": "Tiempo Quieto en el Extremo (ms)",
        "returnDamage": "Daño de Vuelta (pts)",
        "wallWidth": "Ancho de la Pared (px)",
        "wallStartOffset": "Spawn Adelante del Enemigo (px)",
        "pushForce": "Distancia de Expulsión (px)"
    };

    if (currentMechTab === 'attack') {
        for(let type in MECHANICS_LIB) {
            const m = MECHANICS_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f) && !JSON.stringify(m).toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.mechanicsLib['${type}'].label = this.value; renderAll();"></div><div class="field full" style="margin-top:0.5rem;"><label>Descripción</label><input type="text" value="${m.desc || ''}" onchange="config.mechanicsLib['${type}'].desc = this.value"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => fieldLabels[fl] || fl).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    } else if (currentMechTab === 'defense') {
        for(let type in DEFENSE_LIB) {
            const m = DEFENSE_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f) && !JSON.stringify(m).toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.defenseLib['${type}'].label = this.value; renderAll();"></div><div class="field full" style="margin-top:0.5rem;"><label>Descripción</label><input type="text" value="${m.desc || ''}" onchange="config.defenseLib['${type}'].desc = this.value"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => fieldLabels[fl] || fl).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    } else if (currentMechTab === 'ammo') {
        for(let type in AMMO_MECH_LIB) {
            const m = AMMO_MECH_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Efecto Proyectil</label><input type="text" value="${m.label}" onchange="AMMO_MECH_LIB['${type}'].label = this.value; renderAll();"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">PARÁMETROS AFECTADOS:</strong> ${m.fields.map(fl => { const labels = { bulletDamage: "Daño", bulletSpeed: "Velocidad", fireRange: "Rango", fireRate: "Cadencia", startDelay: "Retraso", lifetimeMs: "Combustible (ms)", slowAmount: "Ralentización", slowDuration: "Duración Slow (ms)", turnSpeed: "Agilidad de Giro (rad/s)", chargeTimeMs: "Tiempo Carga (ms)" }; return labels[fl] || fl; }).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    } else if (currentMechTab === 'ambience') {
        for(let type in AMBIENCE_LIB) {
            const m = AMBIENCE_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            const al = { damagePerSecond: "Daño/Seg", slowPercentage: "Slow Ambient", visibility: "Visibilidad", dashPenalty: "Penalidad Dash", damageMult: "Mult. Daño", speedMult: "Mult. Velocidad", healthMult: "Mult. Vida", respawnSpeedBonus: "Velocidad Respawn (%)" };
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Efecto de Ambiente</label><input type="text" value="${m.label}" onchange="AMBIENCE_LIB['${type}'].label = this.value; renderAll();"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">PARÁMETROS AFECTADOS:</strong> ${m.fields.map(fl => {
                const labels = { 
                    damage: "Daño (pts)", 
                    intervalMs: "Intervalo (ms)", 
                    slowPercentage: "Slow (%)", 
                    visibility: "Visibilidad (px)", 
                    dashPenalty: "Penalidad Dash (%)", 
                    lifetimeMs: "Combustible (ms)", 
                    damageMult: "Mult. Daño (x)", 
                    speedMult: "Mult. Velocidad (x)", 
                    healthMult: "Mult. Vida/Escudo (x)", 
                    respawnSpeedBonus: "Velocidad Respawn (%)",
                    spawnInterval: "Frecuencia/Cadencia (ms)",
                    duration: "Duración Efecto (ms)",
                    pullForce: "Fuerza Atracción (px/s)",
                    damageInterval: "Intervalo Daño (ms)",
                    radius: "Radio Acción/Visión (px)",
                    multiplier: "Multiplicador General (x)"
                };
                return labels[fl] || fl;
            }).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    } else {
        for(let type in MOVEMENT_LIB) {
            const m = MOVEMENT_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            const ml = { speed:"Velocidad", stopDist:"Frenado", idealDist:"Rango", orbitRadius:"Órbita", chargeCooldown: "Dash", activationHP: "Activación HP (%)", explosionDamage: "Daño Explosión", duration: "Duración", explodeOnDeath: "Auto-Detonar" };
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.movementLib['${type}'].label = this.value; renderAll();"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => ml[fl] || fl).join(' • ')}</div>`;
            grid.appendChild(card);
        }
    }
}

function renderMapDetail() {
    const container = document.getElementById('map-detail-container');
    const m = config.mapsConfig[selectedMapId];
    if(!m) return;
    if(!m.ambience) m.ambience = [];

    container.innerHTML = `
        <div style="display: grid; grid-template-columns: 1fr 1.2fr 1.2fr; gap: 1.5rem; align-items: start;">
            <div class="col">
                <div class="card" style="width:100%;">
                    <div style="display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:1rem;">
                        <div class="field" style="flex:1; margin:0;"><label>NOMBRE DE LA ZONA</label><input type="text" value="${m.name}" style="font-size: 1.5rem; color:var(--accent);" onchange="config.mapsConfig['${selectedMapId}'].name = this.value; updateSidebar();"></div>
                        <button onclick="toggleMapVisibility('${selectedMapId}'); renderMapDetail();" 
                                title="${m.visible !== false ? 'Mapa Activo (Visible en Godot)' : 'Mapa Inactivo (Oculto en Godot)'}"
                                style="background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); color:${m.visible !== false ? 'var(--primary)' : '#64748b'}; cursor:pointer; font-size:1.4rem; padding:10px 14px; border-radius:8px; margin-top:20px; transition:all 0.2s; display:flex; align-items:center; justify-content:center; height:50px;">
                            ${m.visible !== false ? '👁️' : '🕶️'}
                        </button>
                    </div>
                    <div class="field full" style="margin-top:1rem;"><label>DESCRIPCIÓN DE HISTORIA</label><textarea onchange="config.mapsConfig['${selectedMapId}'].desc = this.value" style="height:100px; width:100%; background:rgba(0,0,0,0.2); border:1px solid #333; color:white; padding:10px; border-radius:8px;">${m.desc || ''}</textarea></div>
                    <div class="form-grid" style="margin-top:1rem;">
                        <div class="field"><label>Nivel Mín. (lvl)</label><input type="number" value="${m.minLevel}" oninput="config.mapsConfig['${selectedMapId}'].minLevel = parseInt(this.value) || 0"></div>
                        <div class="field"><label>Costo Warp (Hubs)</label><input type="number" value="${m.warpCost}" oninput="config.mapsConfig['${selectedMapId}'].warpCost = parseInt(this.value) || 0"></div>
                        <div class="field"><label>Color de Radar</label><input type="color" value="${m.color || '#00d2ff'}" oninput="config.mapsConfig['${selectedMapId}'].color = this.value; updateSidebar();" style="height:40px;"></div>
                        <div class="field"><label>Multiplicador de Drop (x)</label><input type="number" step="0.1" min="0" value="${m.dropMultiplier !== undefined ? m.dropMultiplier : 1}" oninput="config.mapsConfig['${selectedMapId}'].dropMultiplier = parseFloat(this.value) || 1"></div>
                    </div>
                    <div style="margin-top: 1.5rem; padding-top: 1.2rem; border-top: 1px solid rgba(255,255,255,0.05);">
                        <label style="color:var(--accent); font-size: 0.65rem; font-weight:bold; letter-spacing:1px; display:block; margin-bottom:0.8rem;">⚔️ CONFIGURACIÓN DE PVP Y SEGURIDAD</label>
                        <div class="form-grid">
                            <div class="field" style="grid-column: span 2;">
                                <label>Modo de PvP</label>
                                <select onchange="config.mapsConfig['${selectedMapId}'].pvpMode = this.value; renderMapDetail();" style="background:#0f172a; border:1px solid #334155; color:white; width:100%; font-size:0.8rem; border-radius:4px; padding:6px; margin-top:4px;">
                                    <option value="tranquila" ${m.pvpMode === 'tranquila' || !m.pvpMode ? 'selected' : ''}>🕊️ Zona Tranquila (PVP Opcional)</option>
                                    <option value="mandatory" ${m.pvpMode === 'mandatory' ? 'selected' : ''}>⚔️ PVP Obligatorio</option>
                                    <option value="partial_drop" ${m.pvpMode === 'partial_drop' ? 'selected' : ''}>🎒 PVP Obligatorio + Partial Drop (Inventario)</option>
                                    <option value="full_drop" ${m.pvpMode === 'full_drop' ? 'selected' : ''}>💀 PVP Obligatorio + Full Drop</option>
                                    <option value="inferno" ${m.pvpMode === 'inferno' ? 'selected' : ''}>🔥 INFIERNO - Pierdes TODO + Nave destruida</option>
                                </select>
                            </div>
                            ${(m.pvpMode === 'tranquila' || !m.pvpMode) ? `
                            <div class="field" style="grid-column: span 2;">
                                <label>Cooldown Cambio de Combate (ms)</label>
                                <input type="number" min="0" value="${m.pvpToggleCooldown !== undefined ? m.pvpToggleCooldown : 30000}" oninput="config.mapsConfig['${selectedMapId}'].pvpToggleCooldown = parseInt(this.value) || 0">
                            </div>
                            ` : ''}
                            ${(m.pvpMode === 'mandatory' || m.pvpMode === 'full_drop' || m.pvpMode === 'partial_drop' || m.pvpMode === 'inferno') ? `
                            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; grid-column: span 2; margin-top:8px;">
                                <input type="checkbox" id="give-invul-entry" ${m.giveInvulnerabilityOnEntry ? 'checked' : ''} onchange="config.mapsConfig['${selectedMapId}'].giveInvulnerabilityOnEntry = this.checked; renderMapDetail();">
                                <label style="margin:0; cursor:pointer;" for="give-invul-entry">🛡️ Dar invulnerabilidad al entrar</label>
                            </div>
                            ${m.giveInvulnerabilityOnEntry ? `
                            <div class="field" style="grid-column: span 2;">
                                <label>Tiempo de Invulnerabilidad (ms)</label>
                                <input type="number" min="1" value="${m.invulnerabilityDuration || 5000}" oninput="config.mapsConfig['${selectedMapId}'].invulnerabilityDuration = parseInt(this.value) || 5000">
                            </div>
                            ` : ''}
                            ` : ''}
                        </div>
                    </div>
                    <div style="margin-top: 1.5rem; padding-top: 1.2rem; border-top: 1px solid rgba(255,255,255,0.05);">
                        <label style="color:var(--accent); font-size: 0.65rem; font-weight:bold; letter-spacing:1px; display:block; margin-bottom:0.8rem;">📐 DIMENSIONES DEL MAPA EN PÍXELES</label>
                        <div class="form-grid">
                            <div class="field"><label>Ancho (Width - px)</label><input type="number" value="${m.width || 10000}" oninput="config.mapsConfig['${selectedMapId}'].width = parseInt(this.value)"></div>
                            <div class="field"><label>Alto (Height - px)</label><input type="number" value="${m.height || 10000}" oninput="config.mapsConfig['${selectedMapId}'].height = parseInt(this.value)"></div>
                        </div>
                    </div>
                    ${(() => {
                        // Normalizar datos: migrar formato antiguo → nuevo
                        const hours = (m.allowedHours || []).map(g => {
                            if (g.hours) return g; // ya en formato nuevo
                            return {
                                days: g.days || [0,1,2,3,4,5,6],
                                hours: [{ start: g.start || "00:00", end: g.end || "00:00" }]
                            };
                        });
                        const dayLabels = ['DO','LU','MA','MI','JU','VI','SA'];
                        const dayValues = [0,1,2,3,4,5,6];
                        return `
                    <div style="margin-top: 1.5rem; padding-top: 1.2rem; border-top: 1px solid rgba(255,255,255,0.05);">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.8rem;">
                            <label style="color:var(--accent); font-size: 0.65rem; font-weight:bold; letter-spacing:1px; margin:0;">🕒 RESTRICCIÓN DE HORARIOS (SERVER)</label>
                            <div style="display:flex; align-items:center; gap:8px;">
                                <input type="checkbox" id="time-restrictions-enabled" ${m.timeRestrictionsEnabled ? 'checked' : ''} 
                                       onchange="toggleTimeRestrictions('${selectedMapId}', this.checked)" style="width:16px; height:16px; cursor:pointer; accent-color:var(--accent);">
                                <label for="time-restrictions-enabled" style="margin:0; cursor:pointer; font-size:0.75rem; color:var(--text-dim);">Activar</label>
                            </div>
                        </div>
                        ${m.timeRestrictionsEnabled ? `
                        <div style="background:rgba(0,0,0,0.25); padding:1rem; border-radius:10px; border:1px solid rgba(255,255,255,0.05); margin-bottom:1rem;">
                            <div id="allowed-hours-list" style="display:flex; flex-direction:column; gap:10px; margin-bottom:1.2rem; max-height:320px; overflow-y:auto;">
                                ${hours.length === 0 ? '<span style="font-size:0.75rem; color:#64748b; font-style:italic;">No hay horarios configurados. El sector será inaccesible.</span>' : ''}
                                ${hours.map((group, gIdx) => {
                                    const days = group.days || [0,1,2,3,4,5,6];
                                    const isAllDays = days.length === 7;
                                    const isEditing = window._editingGroupIndex === gIdx;
                                    if (isEditing) {
                                        return `
                                        <div style="display:flex; flex-direction:column; gap:6px; background:rgba(0,0,0,0.3); padding:8px 12px; border-radius:6px; border:1px solid var(--primary);">
                                            <div style="display:flex; justify-content:space-between; align-items:center;">
                                                <span style="color:var(--accent); font-size:0.6rem; font-weight:bold; letter-spacing:1px;">EDITAR GRUPO</span>
                                                <div style="display:flex; gap:6px;">
                                                    <button style="background:none; border:none; color:#00ff88; cursor:pointer; font-weight:bold; font-size:1rem; padding:2px 6px;" 
                                                            title="Confirmar Grupo" onclick="saveScheduleGroup('${selectedMapId}', ${gIdx})">✓</button>
                                                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-weight:bold; font-size:0.95rem; padding:2px 6px;" 
                                                            title="Cancelar" onclick="cancelScheduleGroupEdit()">✕</button>
                                                </div>
                                            </div>
                                            <div style="display:flex; align-items:center; gap:4px; flex-wrap:wrap;">
                                                ${dayValues.map(d => `
                                                    <label style="display:flex; align-items:center; gap:2px; cursor:pointer; font-size:0.65rem; color:${days.includes(d) ? 'var(--accent)' : '#64748b'}; font-weight:${days.includes(d) ? 'bold' : 'normal'}; padding:2px 4px; border-radius:4px; background:${days.includes(d) ? 'rgba(6,182,212,0.15)' : 'transparent'}; border:1px solid ${days.includes(d) ? 'var(--accent)' : 'rgba(255,255,255,0.05)'};">
                                                        <input type="checkbox" class="edit-grp-day-${gIdx}" value="${d}" ${days.includes(d) ? 'checked' : ''} 
                                                               onchange="window._updateGroupDays(${gIdx})" style="width:12px; height:12px; margin:0; accent-color:var(--accent);">
                                                        ${dayLabels[d]}
                                                    </label>
                                                `).join('')}
                                                <label style="display:flex; align-items:center; gap:2px; cursor:pointer; font-size:0.65rem; color:${isAllDays ? 'var(--accent)' : '#64748b'}; font-weight:${isAllDays ? 'bold' : 'normal'}; padding:2px 6px; border-radius:4px; background:${isAllDays ? 'rgba(6,182,212,0.15)' : 'transparent'}; border:1px solid ${isAllDays ? 'var(--accent)' : 'rgba(255,255,255,0.05)'}; margin-left:4px;">
                                                    <input type="checkbox" class="edit-grp-all-${gIdx}" ${isAllDays ? 'checked' : ''} 
                                                           onchange="window._toggleGroupAllDays(${gIdx})" style="width:12px; height:12px; margin:0; accent-color:var(--accent);">
                                                    TODOS
                                                </label>
                                            </div>
                                            <div style="display:flex; flex-direction:column; gap:4px; padding-left:8px; border-left:2px solid rgba(6,182,212,0.2);">
                                                ${(group.hours || []).map((hr, hIdx) => `
                                                    <div style="display:flex; align-items:center; gap:6px; background:rgba(255,255,255,0.03); padding:4px 8px; border-radius:4px;">
                                                        <span style="font-size:0.55rem; color:#888; min-width:60px;">RANGO ${hIdx+1}</span>
                                                        <input type="time" id="edit-hr-start-${gIdx}-${hIdx}" value="${hr.start}" style="padding:2px 4px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.75rem; width:90px; font-family:'JetBrains Mono', monospace;">
                                                        <span style="color:var(--text-dim); font-size:0.75rem;">➔</span>
                                                        <input type="time" id="edit-hr-end-${gIdx}-${hIdx}" value="${hr.end}" style="padding:2px 4px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.75rem; width:90px; font-family:'JetBrains Mono', monospace;">
                                                        <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.8rem; padding:0 4px;" 
                                                                title="Eliminar Horario" onclick="removeGroupHour('${selectedMapId}', ${gIdx}, ${hIdx})">✕</button>
                                                    </div>
                                                `).join('')}
                                                <div style="display:flex; align-items:center; gap:6px; margin-top:2px;">
                                                    <input type="time" id="edit-new-hr-start-${gIdx}" style="padding:2px 4px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.7rem; width:90px; font-family:'JetBrains Mono', monospace;">
                                                    <span style="color:var(--text-dim); font-size:0.7rem;">➔</span>
                                                    <input type="time" id="edit-new-hr-end-${gIdx}" style="padding:2px 4px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.7rem; width:90px; font-family:'JetBrains Mono', monospace;">
                                                    <button style="background:none; border:none; color:#00ff88; cursor:pointer; font-size:0.7rem; padding:2px 6px; border:1px solid rgba(0,255,136,0.3); border-radius:4px;" 
                                                            title="Añadir Horario a Grupo" onclick="addHourToGroup('${selectedMapId}', ${gIdx})">+ HORARIO</button>
                                                </div>
                                            </div>
                                        </div>
                                        `;
                                    } else {
                                        return `
                                        <div style="display:flex; flex-direction:column; gap:6px; background:rgba(255,255,255,0.02); padding:8px 12px; border-radius:6px; border:1px solid rgba(255,255,255,0.03);">
                                            <div style="display:flex; justify-content:space-between; align-items:flex-start;">
                                                <div style="display:flex; align-items:center; gap:4px; flex-wrap:wrap;">
                                                    ${isAllDays 
                                                        ? '<span style="font-size:0.6rem; color:var(--accent); font-weight:bold; letter-spacing:0.5px; padding:2px 6px; border-radius:4px; background:rgba(6,182,212,0.1); border:1px solid rgba(6,182,212,0.2);">TODOS LOS DÍAS</span>'
                                                        : dayLabels.map((label, i) => `
                                                            <span style="font-size:0.6rem; color:${days.includes(i) ? 'var(--accent)' : '#334155'}; font-weight:${days.includes(i) ? 'bold' : 'normal'}; padding:2px 5px; border-radius:3px; background:${days.includes(i) ? 'rgba(6,182,212,0.1)' : 'transparent'}; border:1px solid ${days.includes(i) ? 'rgba(6,182,212,0.2)' : 'rgba(255,255,255,0.03)'};">${label}</span>
                                                        `).join('')
                                                    }
                                                </div>
                                                <div style="display:flex; gap:4px;">
                                                    <button style="background:none; border:none; color:#ffb000; cursor:pointer; font-weight:bold; font-size:0.85rem; padding:2px 6px;" 
                                                            title="Editar Grupo" onclick="editScheduleGroup('${selectedMapId}', ${gIdx})">✏️</button>
                                                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-weight:bold; font-size:0.85rem; padding:2px 6px;" 
                                                            title="Eliminar Grupo" onclick="removeScheduleGroup('${selectedMapId}', ${gIdx})">✕</button>
                                                </div>
                                            </div>
                                            <div style="display:flex; flex-direction:column; gap:3px; padding-left:8px; border-left:2px solid rgba(255,255,255,0.06);">
                                                ${(group.hours || []).map(hr => `
                                                    <span style="font-size:0.75rem; font-family:'JetBrains Mono', monospace; color:var(--primary); font-weight:bold;">${hr.start} ➔ ${hr.end}</span>
                                                `).join('')}
                                            </div>
                                        </div>
                                        `;
                                    }
                                }).join('')}
                            </div>
                            <div style="display:flex; flex-direction:column; gap:8px; padding-top:0.8rem; border-top:1px solid rgba(255,255,255,0.05);">
                                <span style="color:var(--accent); font-size:0.6rem; font-weight:bold; letter-spacing:1px;">NUEVO GRUPO DE DÍAS</span>
                                <div style="display:flex; align-items:center; gap:4px; flex-wrap:wrap;">
                                    ${dayLabels.map((label, i) => `
                                        <label style="display:flex; align-items:center; gap:2px; cursor:pointer; font-size:0.65rem; color:#64748b; padding:2px 4px; border-radius:4px; border:1px solid rgba(255,255,255,0.05);">
                                            <input type="checkbox" id="new-day-${i}" value="${i}" style="width:12px; height:12px; margin:0; accent-color:var(--accent);">
                                            ${label}
                                        </label>
                                    `).join('')}
                                    <label style="display:flex; align-items:center; gap:2px; cursor:pointer; font-size:0.65rem; color:#64748b; padding:2px 6px; border-radius:4px; border:1px solid rgba(255,255,255,0.05); margin-left:4px;">
                                        <input type="checkbox" id="new-day-all" style="width:12px; height:12px; margin:0; accent-color:var(--accent);" onchange="window._toggleNewAllDays()">
                                        TODOS
                                    </label>
                                </div>
                                <div style="display:flex; gap:10px; align-items:flex-end;">
                                    <div class="field" style="margin:0; flex:1;"><label style="font-size:0.6rem; color:#888;">INICIO</label><input type="time" id="new-range-start" style="padding:6px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.8rem; width:100%;"></div>
                                    <div class="field" style="margin:0; flex:1;"><label style="font-size:0.6rem; color:#888;">FIN</label><input type="time" id="new-range-end" style="padding:6px; background:#0f172a; border:1px solid #334155; color:white; border-radius:4px; font-size:0.8rem; width:100%;"></div>
                                    <button class="btn btn-primary" style="padding:6px 12px; font-size:0.7rem; height:32px; margin:0;" onclick="addScheduleGroup('${selectedMapId}')">+ AÑADIR GRUPO</button>
                                </div>
                            </div>
                        </div>
                        ` : ''}
                    </div>
                    `;
                    })()}
                </div>
            </div>
            
            <div class="col">
                <div class="card" style="width:100%; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px;">
                    <label style="color:var(--accent); font-size: 0.75rem; font-weight:bold; letter-spacing:1px; width:100%; text-align:left;">🛰️ RADAR TÁCTICO DEL MAPA</label>
                    <div id="map-radar-container" style="position:relative; width:100%; aspect-ratio: 1; background:#000; border:2px solid var(--accent); border-radius:10px; overflow:hidden; cursor:crosshair; box-shadow: 0 0 20px rgba(6, 182, 212, 0.15);">
                        <canvas id="map-radar-canvas" style="width: 100%; height: 100%; display: block;"></canvas>
                    </div>
                    <div style="display:flex; gap:10px; width:100%;">
                        <div class="field" style="flex:1;"><label>Radar X</label><input type="number" id="map-radar-x" value="0" readonly></div>
                        <div class="field" style="flex:1;"><label>Radar Y</label><input type="number" id="map-radar-y" value="0" readonly></div>
                    </div>
                    <div style="display:flex; gap:6px; flex-wrap:wrap; width:100%; justify-content:center;">
                        <button class="btn btn-secondary" style="padding:3px 10px; font-size:0.65rem; border-color:rgba(0,210,255,0.4); color:#00d2ff;" onclick="setMapRadarObjectMode('door')">🚪 Puerta</button>
                        <button class="btn btn-secondary" style="padding:3px 10px; font-size:0.65rem;" onclick="setMapRadarObjectMode(null)">✋ Mover</button>
                    </div>
                    <div id="map-radar-mode-hint" style="font-size:0.65rem; color:#888; text-align:center; width:100%;">
                        🚪 Modo Puerta: haz clic en el radar para colocarla. 🖱️ Arrastra puertas/spawns para moverlos. Paredes, baúles y torres se colocan/escalan en el editor 3D de Godot.
                    </div>
                </div>
            </div>

            <div class="col">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;"><label style="color:var(--accent); font-size: 0.8rem; font-weight:bold;">☢️ MECÁNICAS DE AMBIENTE (HAZARDS)</label><button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem;" onclick="addAmbience('${selectedMapId}'); renderMapDetail();">+ AGREGAR EFECTO</button></div>
                        <div id="ambience-list" style="margin-bottom: 2rem;">
                    ${m.ambience.map((a, idx) => {
                        const lib = AMBIENCE_LIB[a.type || 'radiation'];
                        return `
                        <div class="card" style="margin-bottom:1rem; padding:1rem; position:relative;">
                            <div style="position:absolute; top:8px; right:8px;">
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="config.mapsConfig['${selectedMapId}'].ambience.splice(${idx},1); renderMapDetail();">✕</button>
                            </div>
                            <div class="field full">
                                <label style="font-size: 0.6rem; color: #888;">TIPO DE EFECTO</label>
                                <select style="background:#0f172a; border:none; color:var(--accent); font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" 
                                        onchange="updateAmbienceType('${selectedMapId}', ${idx}, this.value)">
                                    ${Object.keys(AMBIENCE_LIB).map(type => `<option value="${type}" ${a.type === type ? 'selected' : ''}>${AMBIENCE_LIB[type].icon} ${AMBIENCE_LIB[type].label}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-grid" style="margin-top:1rem;">
                                ${lib.fields.map(f => {
                                    const isBlind = a.type === 'blindness_hazard';
                                    const isInter = a.type === 'interferencia_hazard';
                                    const labels = { 
                                        damage: "Daño (HP)", intervalMs: "Intervalo (ms)", 
                                        spawnInterval: "Cadencia (ms)", 
                                        duration: isBlind ? "Duración Ceguera (ms)" : "Duración Efecto (ms)", 
                                        radius: isBlind ? "Radio Visión (px)" : "Tamaño Vórtice (px)", 
                                        pullForce: "Fuerza Atracción (px/s)",
                                        damageInterval: "Intervalo Daño (ms)",
                                        shakeIntensity: "Potencia Temblor Cámara",
                                        staticIntensity: "Fuerza Rayas Pantalla",
                                        slowPercentage: "Reducción por % (0-100)",
                                        slowFixed: "Reducción Fija (PX/S)",
                                        damageMult: "Multiplicador de Daño (x)",
                                        speedMult: "Multiplicador de Velocidad (x)",
                                        healthMult: "Multiplicador de Vida (x)",
                                        respawnSpeedBonus: "Bono de Respawn (ms)",
                                        multiplier: "Multiplicador General (x)",
                                        penaltyPercentage: "Penalización Curación (%)",
                                        penaltyFixed: "Penalización Curación Fija"
                                    };
                                    let val = a[f];
                                    if (val === undefined) {
                                        // Inicializar si no existe
                                        if (f === 'spawnInterval') val = 10000;
                                        else if (f === 'duration') val = 5000;
                                        else if (f === 'radius') val = 250;
                                        else if (f === 'penaltyPercentage') val = 50;
                                        else if (f === 'penaltyFixed') val = 0;
                                        else val = 0;
                                        config.mapsConfig[selectedMapId].ambience[idx][f] = val;
                                    }
                                    return `
                                    <div class="field">
                                        <label>${labels[f] || f}</label>
                                        <input type="number" step="0.1" value="${val}" 
                                               oninput="config.mapsConfig['${selectedMapId}'].ambience[${idx}].${f} = parseFloat(this.value) || 0">
                        </div>`
                    }).join('')}
                            </div>
                        </div>`;
                    }).join('')}
                </div>
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;"><label style="color:var(--success); font-size: 0.8rem; font-weight:bold;">👾 ECOSISTEMA DE ENEMIGOS</label><button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:var(--success);" onclick="addMapSpawn('${selectedMapId}'); renderMapDetail();">+ AÑADIR ESPECIE</button></div>
                <div id="spawns-list">
                    ${(m.spawns || []).map((s, idx) => `
                        <div class="card" id="card-map-spawn-${idx}" onclick="highlightCard('map-spawn', ${idx})" style="margin-bottom:1rem; padding:1rem; position:relative; border-color: rgba(16, 185, 129, 0.2); overflow: visible; transition: all 0.3s ease; cursor:pointer;">
                            <div style="position:absolute; top:8px; right:8px; z-index: 10;">
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="config.mapsConfig['${selectedMapId}'].spawns.splice(${idx},1); renderMapDetail();">✕</button>
                            </div>
                            <div class="form-grid" style="overflow: visible;">
                                <div class="field" style="grid-column: span 2; overflow: visible;">
                                    <label>Tipo de Enemigo</label>
                                    ${renderSearchableEnemySelect(s.type, (newId) => {
                                        config.mapsConfig[selectedMapId].spawns[idx].type = newId;
                                    }, 'var(--success)', `map-spawn-${idx}`)}
                                </div>
                                <div class="field">
                                    <label>Cant. Máx (slots)</label>
                                    <input type="number" value="${s.count}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].count = parseInt(this.value) || 0">
                                </div>
                                <div class="field">
                                    <label>Intervalo Respawn (ms)</label>
                                    <input type="number" value="${s.intervalMs}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].intervalMs = parseInt(this.value) || 0">
                                </div>
                                <div class="field" style="grid-column: span 2;">
                                    <label>Modo de Aparición (Respawn)</label>
                                    <select style="background:#0f172a; border:none; color:var(--success); font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;"
                                            onchange="const val = this.value;
                                                      const s = config.mapsConfig['${selectedMapId}'].spawns[${idx}];
                                                      if (val === 'random_global') { s.spawnMode = 'random'; s.radius = 0; }
                                                      else if (val === 'random_zone') { s.spawnMode = 'random'; if (!s.radius || s.radius === 0) s.radius = 500; }
                                                      else if (val === 'fixed') { s.spawnMode = 'fixed'; }
                                                      renderMapDetail();">
                                        <option value="random_global" ${s.spawnMode === 'random' && (!s.radius || s.radius === 0) ? 'selected' : ''}>🌍 Aleatorio (En todo el mapa)</option>
                                        <option value="random_zone" ${s.spawnMode === 'random' && s.radius > 0 ? 'selected' : ''}>⭕ Aleatorio en un área (Centro + Radio)</option>
                                        <option value="fixed" ${s.spawnMode === 'fixed' ? 'selected' : ''}>📍 Fijo (Coordenadas Exactas)</option>
                                    </select>
                                </div>
                                ${s.spawnMode === 'fixed' || (s.spawnMode === 'random' && s.radius > 0) ? `
                                <div class="field">
                                    <label>Coordenada Centro X</label>
                                    <input type="number" value="${s.x !== undefined ? s.x : 1000}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].x = parseInt(this.value) || 0">
                                </div>
                                <div class="field">
                                    <label>Coordenada Centro Y</label>
                                    <input type="number" value="${s.y !== undefined ? s.y : 1000}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].y = parseInt(this.value) || 0">
                                </div>
                                ` : ''}
                                ${s.spawnMode === 'random' && s.radius > 0 ? `
                                <div class="field" style="grid-column: span 2;">
                                    <label>Radio de Área de Spawn (px)</label>
                                    <input type="number" value="${s.radius}" oninput="config.mapsConfig['${selectedMapId}'].spawns[${idx}].radius = parseInt(this.value) || 0">
                                </div>
                                ` : ''}
                            </div>
                        </div>
                    `).join('')}
                </div>

                <!-- ========== CONFIGURADOR DE PUERTAS / WARPS ========== -->
                <div style="margin-top: 2rem; padding-top: 1.5rem; border-top: 1px solid rgba(0,210,255,0.1);">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
                        <label style="color:#00d2ff; font-size: 0.8rem; font-weight:bold;">🚪 CONFIGURADOR DE PUERTAS / WARPS</label>
                        <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:var(--accent); border-color:var(--accent);" onclick="addMapObject('${selectedMapId}'); renderMapDetail();">+ AGREGAR PUERTA</button>
                    </div>
                    <div style="font-size:0.65rem; color:#64748b; margin-bottom:1rem;">
                        Paredes, baúles, torres y demás objetos se colocan y escalan en el editor 3D de Godot (MapEditor3D) e importan aquí como referencia visual en el radar.
                    </div>
                    <div id="map-objects-list">
                    ${(m.objects || []).map((obj, idx) => obj.type !== 'door' ? '' : `
                        <div class="card" id="card-map-obj-${idx}" style="margin-bottom:0.8rem; padding:1rem; position:relative;
                            border-left: 3px solid #00d2ff40; background: rgba(0,0,0,0.2); cursor:pointer;"
                            onclick="highlightMapObject(${idx})">
                            <div style="position:absolute; top:6px; right:6px;">
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem;" onclick="event.stopPropagation(); config.mapsConfig['${selectedMapId}'].objects.splice(${idx},1); renderMapDetail();">✕</button>
                            </div>
                            <div style="font-size:0.65rem; color:#00d2ff; font-weight:bold; letter-spacing:1px; margin-bottom:0.7rem;">🚪 PUERTA/WARP</div>
                            <div class="form-grid">
                                <div class="field" style="grid-column:span 2;">
                                    <label>Etiqueta</label>
                                    <input type="text" value="${obj.label || ''}" placeholder="Nombre de la puerta"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].label = this.value">
                                </div>
                                <div class="field">
                                    <label>Pos X</label>
                                    <input type="number" id="map-obj-x-${idx}" value="${obj.x || 0}"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].x = parseInt(this.value) || 0">
                                </div>
                                <div class="field">
                                    <label>Pos Y</label>
                                    <input type="number" id="map-obj-y-${idx}" value="${obj.y || 0}"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].y = parseInt(this.value) || 0">
                                </div>
                                <div class="field" style="grid-column:span 2;">
                                    <label>Asset (ruta .glb)</label>
                                    <div style="display:flex; gap:6px; align-items:center;">
                                        <input type="text" value="${obj.assetPath || 'res://assets/Puertas/3D/Puerta2/Puerta2.glb'}" placeholder="Ruta al archivo .glb del asset"
                                               oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].assetPath = this.value" style="flex:1; margin:0;">
                                        <button class="btn btn-primary" style="padding:5px 10px; font-size:0.65rem; flex-shrink:0; background:var(--accent); border-color:var(--accent);" onclick="triggerMapObjAssetPick('${selectedMapId}', ${idx})">📁</button>
                                    </div>
                                </div>
                                <div class="field" style="grid-column:span 2; border-top:1px solid rgba(0,210,255,0.2); padding-top:0.7rem; margin-top:0.3rem;">
                                    <label style="color:#00d2ff; font-size:0.6rem; font-weight:bold;">🌀 CONFIGURACIÓN DE WARP</label>
                                </div>
                                <div class="field" style="grid-column:span 2;">
                                    <label>Zona Destino</label>
                                    <select style="background:#0f172a; border:none; color:#00d2ff; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:6px;"
                                            onchange="config.mapsConfig['${selectedMapId}'].objects[${idx}].targetZoneId = this.value">
                                        <option value="">-- Seleccionar Zona --</option>
                                        ${Object.keys(config.mapsConfig)
                                            .filter(id => id !== selectedMapId && (config.mapsConfig[id].visible !== false || (obj.targetZoneId || '') == id))
                                            .map(id => `<option value="${id}" ${(obj.targetZoneId || '') == id ? 'selected' : ''}>${config.mapsConfig[id].name} (ID: ${id})</option>`)
                                            .join('')}
                                    </select>
                                </div>
                                <div class="field">
                                    <label>Warp X destino</label>
                                    <input type="number" value="${obj.targetX || 5000}" placeholder="5000"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].targetX = parseInt(this.value) || 0">
                                </div>
                                <div class="field">
                                    <label>Warp Y destino</label>
                                    <input type="number" value="${obj.targetY || 5000}" placeholder="5000"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].targetY = parseInt(this.value) || 0">
                                </div>
                                <div class="field" style="grid-column:span 2; border-top:1px solid rgba(0,210,255,0.2); padding-top:0.7rem; margin-top:0.3rem;">
                                    <label style="color:#00d2ff; font-size:0.6rem; font-weight:bold;">📐 CONFIGURACIÓN 3D</label>
                                </div>
                                <div class="field">
                                    <label>Rotación Y (grados)</label>
                                    <input type="number" value="${obj.rotY || 0}" placeholder="0"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].rotY = parseFloat(this.value) || 0">
                                </div>
                                <div class="field">
                                    <label>Escala (x1 = tamaño base)</label>
                                    <input type="number" step="0.1" min="0.1" value="${obj.scale || 1}" placeholder="1"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].scale = parseFloat(this.value) || 1">
                                </div>
                                <div class="field" style="grid-column:span 2;">
                                    <label>Y Offset (altura sobre el suelo)</label>
                                    <input type="number" step="0.1" value="${obj.yOffset !== undefined ? obj.yOffset : 2.5}" placeholder="2.5"
                                           oninput="config.mapsConfig['${selectedMapId}'].objects[${idx}].yOffset = parseFloat(this.value) || 0">
                                </div>
                            </div>
                        </div>`
                    ).join('')}
                    </div>
                </div>
            </div>
        </div>
    `;
    setTimeout(initMapRadar, 100);
}

function renderMaps() {
    const grid = document.getElementById('maps-grid'); grid.innerHTML = '';
    const f = getFilter();
    for(let id in config.mapsConfig) {
        const m = config.mapsConfig[id];
        // Mapas 10 y 11 ahora visibles en cartografía
        if (f && !m.name.toLowerCase().includes(f)) continue;
        
        const isVisible = m.visible !== false;
        const eyeColor = isVisible ? 'var(--primary)' : '#64748b';
        const eyeTitle = isVisible ? 'Mapa Activo (Visible en Godot)' : 'Mapa Inactivo (Oculto en Godot)';
        const cardOpacity = isVisible ? '1' : '0.5';

        const card = document.createElement('div'); card.className = 'card';
        card.style.cursor = 'pointer'; card.onclick = () => selectMap(id);
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
                <div class="card-tag" style="margin:0;">#ID ${id}</div>
                <button onclick="event.stopPropagation(); toggleMapVisibility('${id}')" 
                        title="${eyeTitle}" 
                        style="background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); color:${eyeColor}; cursor:pointer; font-size:1rem; padding:4px 8px; border-radius:6px; transition:all 0.2s; display:flex; align-items:center; gap:4px;">
                    ${isVisible ? '👁️' : '🕶️'}
                </button>
            </div>
            <div style="width:100%; height:4px; background:${m.color}; margin-bottom:1rem; border-radius:2px; opacity:${cardOpacity};"></div>
            <h3 style="opacity:${cardOpacity};">${m.name}</h3>
            <p style="font-size:0.8rem; opacity:${isVisible ? '0.6' : '0.35'};">${m.desc || 'Sin descripción'}</p>
            <div style="margin-top:1rem; color:var(--accent); font-weight:bold; font-size:0.7rem; opacity:${cardOpacity};">Configurar Zona</div>
        `;
        grid.appendChild(card);
    }
}

window.toggleMapVisibility = function(id) {
    if (!config || !config.mapsConfig || !config.mapsConfig[id]) return;
    const m = config.mapsConfig[id];
    m.visible = (m.visible === false) ? true : false;
    saveConfig();
    renderMaps();
    updateSidebar();
};

function renderSkills() {
    const grid = document.getElementById('skills-grid'); grid.innerHTML = '';
    const f = getFilter();
    for(let name in config.skillsData) {
        const s = config.skillsData[name];
        
        // v1.9.2: Filtrar por Esfera seleccionada
        if (s.type !== currentSkillTab) continue;

        if (f && !name.toLowerCase().includes(f) && !JSON.stringify(s).toLowerCase().includes(f)) continue;
        const card = document.createElement('div'); card.className = 'card';
        if(!s.targetFilters) s.targetFilters = { allies: true, enemies: false, bosses: false, players: true, clan: false };
        if(s.targetFilters.clan === undefined) s.targetFilters.clan = false;

        // Ícono actual
        const skillIconWeb = resolveAssetWebUrl(s.icon || '');
        const iconPreviewHtml = skillIconWeb
            ? `<img src="${skillIconWeb}" style="width:72px; height:72px; object-fit:contain; border-radius:10px; border:1px solid rgba(255,255,255,0.12); background:rgba(0,0,0,0.3);" onerror="this.style.display='none';">`
            : `<div style="width:72px; height:72px; border:1px dashed rgba(255,255,255,0.15); border-radius:10px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.7rem; text-align:center; padding:4px;">Sin Ícono</div>`;

        card.innerHTML = `
            <div style="display:flex; gap:16px; align-items:flex-start; margin-bottom:1rem;">
                <!-- Columna ícono -->
                <div style="flex-shrink:0; display:flex; flex-direction:column; align-items:center; gap:6px;">
                    ${iconPreviewHtml}
                    <button class="btn" style="padding:4px 8px; font-size:0.62rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; white-space:nowrap;" onclick="triggerAssetUpload('${name}', 'skill_icon')">🖼️ ÍCONO</button>
                    ${s.icon ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060; cursor:pointer; border-radius:4px;" onclick="config.skillsData['${name}'].icon=''; renderSkills();">✕ Quitar</button>` : ''}
                </div>
                <!-- Columna nombre + tipo -->
                <div style="flex-grow:1;">
                    <div class="field" style="margin-bottom:0.5rem;"><label>Protocolo (ID Interno)</label><input type="text" value="${name}" style="color:var(--accent); font-weight:bold; background:transparent; border:none;" readonly></div>
                    <div class="field full" style="margin-bottom:0.5rem;"><label>Nombre Público</label><input type="text" value="${s.name || name}" onchange="config.skillsData['${name}'].name = this.value; renderAll();"></div>
                    <div class="field full"><label>Descripción</label><input type="text" value="${s.desc || ''}" onchange="config.skillsData['${name}'].desc = this.value"></div>
                </div>
            </div>
            <div class="form-grid">
                <div class="field"><label>Tipo</label><select onchange="config.skillsData['${name}'].type = this.value"><option value="Defensa" ${s.type==='Defensa'?'selected':''}>Defensa</option><option value="Curación" ${s.type==='Curación'?'selected':''}>Curación</option><option value="Ataque" ${s.type==='Ataque'?'selected':''}>Ataque</option><option value="Utilidad" ${s.type==='Utilidad'?'selected':''}>Utilidad</option></select></div>
                <div class="field"><label>Cooldown (ms)</label><input type="number" value="${s.cd}" onchange="config.skillsData['${name}'].cd = parseInt(this.value)"></div>
                <div class="field"><label>Puntos (pts)</label><input type="number" value="${s.amount || 0}" onchange="config.skillsData['${name}'].amount = parseInt(this.value)"></div>
                <div class="field"><label>Rango (px)</label><input type="number" value="${s.range || 0}" onchange="config.skillsData['${name}'].range = parseInt(this.value)"></div>
                ${s.duration !== undefined ? `<div class="field"><label>Duración (ms)</label><input type="number" value="${s.duration}" onchange="config.skillsData['${name}'].duration = parseInt(this.value)"></div>` : ''}
                ${s.radius !== undefined ? `<div class="field"><label>Radio/Área (px)</label><input type="number" value="${s.radius}" onchange="config.skillsData['${name}'].radius = parseInt(this.value)"></div>` : ''}
                ${s.speed !== undefined ? `<div class="field"><label>Velocidad (px/s)</label><input type="number" value="${s.speed}" onchange="config.skillsData['${name}'].speed = parseInt(this.value)"></div>` : ''}
                ${s.width !== undefined ? `<div class="field"><label>Ancho (px)</label><input type="number" value="${s.width}" onchange="config.skillsData['${name}'].width = parseInt(this.value)"></div>` : ''}
                ${s.breakRange !== undefined ? `<div class="field"><label>Rango de Ruptura (px)</label><input type="number" value="${s.breakRange}" onchange="config.skillsData['${name}'].breakRange = parseInt(this.value)"></div>` : ''}
                ${s.tickInterval !== undefined ? `<div class="field"><label>Intervalo Tick (ms)</label><input type="number" value="${s.tickInterval}" onchange="config.skillsData['${name}'].tickInterval = parseInt(this.value)"></div>` : ''}
                ${s.pulse_interval !== undefined ? `<div class="field"><label>Intervalo Pulso (ms)</label><input type="number" value="${s.pulse_interval}" onchange="config.skillsData['${name}'].pulse_interval = parseInt(this.value)"></div>` : ''}
                ${s.heal_amount !== undefined ? `<div class="field"><label>Sanación Onda</label><input type="number" value="${s.heal_amount}" onchange="config.skillsData['${name}'].heal_amount = parseInt(this.value)"></div>` : ''}
                ${s.taunt_duration !== undefined ? `<div class="field"><label>Duración Provocación (ms)</label><input type="number" value="${s.taunt_duration}" onchange="config.skillsData['${name}'].taunt_duration = parseInt(this.value)"></div>` : ''}
                ${s.revive_hp_pct !== undefined ? `<div class="field"><label>Vida al Revivir (%)</label><input type="number" value="${s.revive_hp_pct}" onchange="config.skillsData['${name}'].revive_hp_pct = parseInt(this.value)"></div>` : ''}
                ${s.revive_shield_pct !== undefined ? `<div class="field"><label>Escudo al Revivir (%)</label><input type="number" value="${s.revive_shield_pct}" onchange="config.skillsData['${name}'].revive_shield_pct = parseInt(this.value)"></div>` : ''}
            </div>
            <div style="margin-top: 1.5rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.05); background: rgba(0,0,0,0.1); border-radius: 8px; padding: 12px;">
                <label style="color:var(--accent); font-size: 0.6rem; font-weight:bold; display:flex; align-items:center; gap:5px; margin-bottom:1rem; letter-spacing: 1px; opacity: 0.8;">
                    <span style="font-size:10px;">🎯</span> PROTOCOLOS DE FILTRADO
                </label>
                <div style="display:grid; grid-template-columns: 1fr 1fr; gap: 12px;">
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.allies?'checked':''} onchange="config.skillsData['${name}'].targetFilters.allies = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Aliados</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.enemies?'checked':''} onchange="config.skillsData['${name}'].targetFilters.enemies = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Enemigos</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.bosses?'checked':''} onchange="config.skillsData['${name}'].targetFilters.bosses = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Bosses</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.players?'checked':''} onchange="config.skillsData['${name}'].targetFilters.players = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Jugadores</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px; cursor:pointer;" onclick="this.querySelector('input').click()">
                        <input type="checkbox" style="width:14px; height:14px; cursor:pointer; accent-color:var(--accent);" ${s.targetFilters.clan?'checked':''} onchange="config.skillsData['${name}'].targetFilters.clan = this.checked" onclick="event.stopPropagation()">
                        <span style="font-size:0.75rem; color:rgba(255,255,255,0.7); font-weight:500;">Gente del Clan</span>
                    </div>
                </div>
            </div>
        `;
        grid.appendChild(card);
    }
}
let lastSessionsData = [];
let lastOnlineData = [];
function renderOnlinePlayers(data) {
    if (data) lastOnlineData = data;
    const list = document.getElementById('sessions-list');
    if (!list) return;
    list.innerHTML = '';
    const f = getFilter();

    lastOnlineData.forEach(p => {
        if (f && !p.username.toLowerCase().includes(f) && !p.ip.includes(f)) return;

        const row = document.createElement('tr');
        row.style.borderBottom = '1px solid rgba(255,255,255,0.03)';
        
        const loginTime = new Date(p.loginAt);
        const fecha = loginTime.toLocaleDateString('es-AR', { day:'2-digit', month:'2-digit', year:'2-digit' });
        const hora = loginTime.toLocaleTimeString('es-AR', { hour:'2-digit', minute:'2-digit', hour12: false });
        
        const diffMs = Date.now() - loginTime;
        const durMin = Math.floor(diffMs / 60000);
        
        const latColor = p.latency < 100 ? 'var(--success)' : (p.latency < 250 ? 'var(--warning)' : 'var(--danger)');

        row.innerHTML = `
            <td style="padding: 1.5rem; font-weight: bold; color: var(--primary);">${p.username.toUpperCase()}</td>
            <td style="padding: 1.5rem; opacity: 0.7;">${p.ip}</td>
            <td style="padding: 1.5rem;">
                <div style="display:flex; flex-direction:column;">
                    <span style="font-weight:600;">${fecha}</span>
                    <span style="font-size:0.75rem; opacity:0.6;">${hora}hs</span>
                </div>
            </td>
            <td style="padding: 1.5rem; font-weight: bold; color: ${latColor}; font-family: 'JetBrains Mono';">${p.latency}ms</td>
            <td style="padding: 1.5rem;"><span class="card-tag" style="position:static; background:rgba(0,210,255,0.1); color:var(--primary);">${durMin} min</span></td>
            <td style="padding: 1.5rem;">
                <div style="display:flex; flex-direction:column; gap:2px;">
                    <span style="font-size:0.7rem; color:var(--accent); font-weight:bold;">LVL: ${p.level || '--'}</span>
                    <span style="font-size:0.7rem; opacity:0.6;">ZONA: ${p.zone || '--'}</span>
                </div>
            </td>
        `;
        list.appendChild(row);
    });
}

function renderSessions(data) {
    if (data) lastSessionsData = data;
    const list = document.getElementById('sessions-list');
    if (!list) return;
    list.innerHTML = '';
    const f = getFilter();

    lastSessionsData.forEach(item => {
        const s = item.lastSession;
        if (!s) return;
        if (f && !s.username.toLowerCase().includes(f) && !s.ip.includes(f)) return;

        const row = document.createElement('tr');
        row.style.borderBottom = '1px solid rgba(255,255,255,0.03)';
        
        const formatDate = (date) => {
            if (!date) return null;
            const d = new Date(date);
            const fecha = d.toLocaleDateString('es-AR', { day:'2-digit', month:'2-digit', year:'2-digit' });
            const hora = d.toLocaleTimeString('es-AR', { hour:'2-digit', minute:'2-digit', hour12: false });
            return `<div style="display:flex; flex-direction:column;">
                        <span style="font-weight:600;">${fecha}</span>
                        <span style="font-size:0.75rem; opacity:0.6;">${hora}hs</span>
                    </div>`;
        };

        const loginHtml = formatDate(s.loginAt);
        const logoutHtml = s.logoutAt ? formatDate(s.logoutAt) : '<span style="color:var(--success); font-weight:bold; font-size:0.75rem;">🛰️ EN ÓRBITA</span>';
        
        row.innerHTML = `
            <td style="padding: 1.5rem;">
                <button class="btn-link" style="color: var(--primary); font-weight: bold; border:none; background:none; cursor:pointer; font-size: 0.9rem; padding:0; text-align:left;" onclick="openPlayerSessionsModal('${s.username}')">
                    ${s.username.toUpperCase()}
                </button>
            </td>
            <td style="padding: 1.5rem; font-weight: bold; font-family: 'JetBrains Mono';">${item.totalSessions} SESIONES</td>
            <td style="padding: 1.5rem;">${loginHtml}</td>
            <td style="padding: 1.5rem;">${logoutHtml}</td>
            <td style="padding: 1.5rem;"><span class="card-tag" style="position:static; background:rgba(0,210,255,0.1); color:var(--primary); font-family:'JetBrains Mono'">${s.durationMinutes || 0} min</span></td>
            <td style="padding: 1.5rem;">
                <div style="display:flex; flex-direction:column; gap:2px;">
                    <span style="font-size:0.7rem; color:var(--accent); font-weight:bold;">LVL: ${s.levelAtLogout || '--'}</span>
                    <span style="font-size:0.7rem; opacity:0.6;">ZONA: ${s.zoneAtLogout || '--'}</span>
                </div>
            </td>
        `;
        list.appendChild(row);
    });
}

function renderPlayerSessionsModal(data) {
    const list = document.getElementById('modal-sessions-list');
    if (!list) return;
    list.innerHTML = '';
    
    document.getElementById('modal-page-indicator').innerText = `PÁGINA ${data.page + 1} de ${Math.ceil(data.total / 30)}`;

    data.sessions.forEach(s => {
        const row = document.createElement('tr');
        row.style.borderBottom = '1px solid rgba(255,255,255,0.03)';
        
        const formatDate = (date) => {
            if (!date) return null;
            const d = new Date(date);
            const fecha = d.toLocaleDateString('es-AR', { day:'2-digit', month:'2-digit', year:'2-digit' });
            const hora = d.toLocaleTimeString('es-AR', { hour:'2-digit', minute:'2-digit', hour12: false });
            return `<div style="display:flex; flex-direction:column;">
                        <span style="font-weight:600;">${fecha}</span>
                        <span style="font-size:0.75rem; opacity:0.6;">${hora}hs</span>
                    </div>`;
        };

        const loginHtml = formatDate(s.loginAt);
        const logoutHtml = s.logoutAt ? formatDate(s.logoutAt) : '<span style="color:var(--success); font-weight:bold; font-size:0.7rem;">EN ÓRBITA</span>';

        row.innerHTML = `
            <td style="padding: 1.2rem; font-family: 'JetBrains Mono'; opacity: 0.8;">${s.ip}</td>
            <td style="padding: 1.2rem;">${loginHtml}</td>
            <td style="padding: 1.2rem;">${logoutHtml}</td>
            <td style="padding: 1.2rem;"><span class="card-tag" style="position:static; background:rgba(0,210,255,0.05); color:var(--primary); font-size:0.7rem;">${s.durationMinutes || 0} min</span></td>
            <td style="padding: 1.2rem;">
                <div style="display:flex; flex-direction:column; gap:1px;">
                    <span style="font-size:0.65rem; color:var(--accent);">LVL: ${s.levelAtLogout || '--'}</span>
                    <span style="font-size:0.65rem; opacity:0.6;">ZONA: ${s.zoneAtLogout || '--'}</span>
                </div>
            </td>
        `;
        list.appendChild(row);
    });
}

let lastUsersData = [];
function renderRegisteredUsers(data) {
    if (data) lastUsersData = data;
    const list = document.getElementById('users-list');
    if (!list) return;
    list.innerHTML = '';
    const f = getFilter();

    lastUsersData.forEach(u => {
        if (f && !u.username.toLowerCase().includes(f)) return;

        const row = document.createElement('tr');
        row.style.borderBottom = '1px solid rgba(255,255,255,0.03)';
        
        // Calcular inactividad
        const last = new Date(u.lastLogin);
        const diffMs = Date.now() - last;
        const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
        
        let inactividadText = "";
        let inactividadColor = "var(--success)";
        
        if (diffDays === 0) inactividadText = "Hoy mismo";
        else if (diffDays === 1) inactividadText = "Ayer";
        else {
            inactividadText = `Hace ${diffDays} días`;
            if (diffDays > 7) inactividadColor = "var(--warning)";
            if (diffDays > 30) inactividadColor = "var(--danger)";
        }

        const premiumBadge = u.isPremium 
            ? '<span class="card-tag" style="position:static; background:rgba(255,215,0,0.1); color:#ffd700; border:1px solid rgba(255,215,0,0.2);">💎 PREMIUM</span>' 
            : '<span class="card-tag" style="position:static; background:rgba(255,255,255,0.05); color:#666;">BÁSICO</span>';

        row.innerHTML = `
            <td style="padding: 1.5rem; font-weight: bold; color: var(--primary);">${u.username.toUpperCase()}</td>
            <td style="padding: 1.5rem; color: ${inactividadColor}; font-weight: 500;">${inactividadText}</td>
            <td style="padding: 1.5rem;">${premiumBadge}</td>
            <td style="padding: 1.5rem; font-family: 'JetBrains Mono'; font-weight: bold; color: var(--accent);">LVL ${u.level}</td>
            <td style="padding: 1.5rem; font-family: 'JetBrains Mono'; opacity: 0.9;">${u.ohcu.toLocaleString()} OHCUL</td>
            <td style="padding: 1.5rem; font-family: 'JetBrains Mono'; color: #3bff31;">${u.hubs.toLocaleString()} HUBS</td>
            <td style="padding: 1.5rem; opacity: 0.8;">Sector ${u.zone} sector</td>
        `;
        list.appendChild(row);
    });
}

window.updateVaultPrice = function(index, key, val) {
    if (!config.vaultConfig) {
        config.vaultConfig = {};
    }
    if (!config.vaultConfig.unlockPrices) {
        config.vaultConfig.unlockPrices = [0, 5000, 15000, 45000, 100000];
    }
    if (!config.vaultConfig.unlockPrices[index] || typeof config.vaultConfig.unlockPrices[index] !== 'object') {
        const prevHubs = typeof config.vaultConfig.unlockPrices[index] === 'number' ? config.vaultConfig.unlockPrices[index] : 0;
        config.vaultConfig.unlockPrices[index] = { hubs: prevHubs, ohcu: 0 };
    }
    config.vaultConfig.unlockPrices[index][key] = parseInt(val) || 0;
};

window.updateInventoryPrice = function(key, val) {
    if (!config.inventoryConfig) {
        config.inventoryConfig = {};
    }
    if (!config.inventoryConfig.unlockSlotPrice || typeof config.inventoryConfig.unlockSlotPrice !== 'object') {
        const prevHubs = typeof config.inventoryConfig.unlockSlotPrice === 'number' ? config.inventoryConfig.unlockSlotPrice : 1000;
        config.inventoryConfig.unlockSlotPrice = { hubs: prevHubs, ohcu: 0 };
    }
    config.inventoryConfig.unlockSlotPrice[key] = parseInt(val) || 0;
};

function renderPilot() {
    if (!config.pilotConfig) {
        config.pilotConfig = {
            startingHubs: 0,
            startingOhcu: 0,
            startingShipId: 1,
            startingMapId: 1,
            expRequirements: Array(30).fill(0).map((_, i) => (i + 1) * 1000)
        };
    }
    
    if (!config.vaultConfig) {
        config.vaultConfig = {
            defaultTabs: 1,
            slotsPerTab: 30,
            unlockPrices: [
                { hubs: 0, ohcu: 0 },
                { hubs: 5000, ohcu: 0 },
                { hubs: 15000, ohcu: 5 },
                { hubs: 45000, ohcu: 10 },
                { hubs: 100000, ohcu: 20 }
            ]
        };
    }
    
    if (!config.inventoryConfig) {
        config.inventoryConfig = {
            defaultMaxSlots: 30,
            unlockSlotPrice: { hubs: 1000, ohcu: 0 }
        };
    }
    
    const container = document.getElementById('pilot-config-container');
    if(!container) return;
    
    container.innerHTML = `
        <div class="card">
            <h4 style="color:var(--primary); margin-bottom:1rem;">💰 RECURSOS INICIALES</h4>
            <div class="form-grid">
                <div class="field"><label>Hubs Iniciales</label><input type="number" value="${config.pilotConfig.startingHubs}" onchange="config.pilotConfig.startingHubs = parseInt(this.value)"></div>
                <div class="field"><label>Ohcu Iniciales</label><input type="number" value="${config.pilotConfig.startingOhcu}" onchange="config.pilotConfig.startingOhcu = parseInt(this.value)"></div>
            </div>
        </div>
        <div class="card">
            <h4 style="color:var(--accent); margin-bottom:1rem;">🚀 DESPLIEGUE INICIAL</h4>
            <div class="form-grid">
                <div class="field"><label>Nave de Nacimiento</label>
                    <select onchange="config.pilotConfig.startingShipId = parseInt(this.value)">
                        ${config.shipModels.map(s => `<option value="${s.id}" ${config.pilotConfig.startingShipId == s.id ? 'selected' : ''}>${s.name}</option>`).join('')}
                    </select>
                </div>
                <div class="field"><label>Mapa de Nacimiento</label>
                    <select onchange="config.pilotConfig.startingMapId = parseInt(this.value)">
                        ${Object.keys(config.mapsConfig).map(id => `<option value="${id}" ${config.pilotConfig.startingMapId == id ? 'selected' : ''}>${config.mapsConfig[id].name}</option>`).join('')}
                    </select>
                </div>
            </div>
        </div>
        <div class="card">
            <h4 style="color:var(--primary); margin-bottom:1rem;">📦 CONFIGURACIÓN DE BAÚLES</h4>
            <div class="form-grid">
                <div class="field"><label>Pestañas Iniciales (Defecto)</label>
                    <input type="number" value="${config.vaultConfig.defaultTabs}" onchange="config.vaultConfig.defaultTabs = parseInt(this.value)">
                </div>
                <div class="field"><label>Slots por Pestaña</label>
                    <input type="number" value="${config.vaultConfig.slotsPerTab}" onchange="config.vaultConfig.slotsPerTab = parseInt(this.value)">
                </div>
            </div>
            <div style="margin-top:1rem;">
                <label style="font-weight:bold; font-size:0.9rem; color:var(--accent); display:block; margin-bottom:0.5rem;">Costo de Desbloqueo (Hubs / Ohcu por Pestaña)</label>
                <div class="form-grid">
                    ${[1, 2, 3, 4].map(idx => {
                        const price = config.vaultConfig.unlockPrices[idx] || { hubs: 0, ohcu: 0 };
                        const hubsVal = typeof price === 'object' ? (price.hubs ?? 0) : price;
                        const ohcuVal = typeof price === 'object' ? (price.ohcu ?? 0) : 0;
                        return `
                            <div class="field" style="border: 1px solid rgba(255,255,255,0.05); padding: 8px; border-radius: 6px;">
                                <label style="color: var(--primary); font-weight: 600;">Pestaña ${idx + 1}</label>
                                <div style="display: flex; gap: 8px; margin-top: 4px;">
                                    <div style="flex: 1;">
                                        <label style="font-size: 8px; opacity: 0.6; margin-bottom: 2px;">Hubs</label>
                                        <input type="number" value="${hubsVal}" onchange="updateVaultPrice(${idx}, 'hubs', this.value)" style="height: 28px; font-size: 0.85rem; padding: 2px 6px;">
                                    </div>
                                    <div style="flex: 1;">
                                        <label style="font-size: 8px; opacity: 0.6; margin-bottom: 2px;">Ohcu</label>
                                        <input type="number" value="${ohcuVal}" onchange="updateVaultPrice(${idx}, 'ohcu', this.value)" style="height: 28px; font-size: 0.85rem; padding: 2px 6px;">
                                    </div>
                                </div>
                            </div>
                        `;
                    }).join('')}
                </div>
            </div>
        </div>
        <div class="card">
            <h4 style="color:var(--primary); margin-bottom:1rem;">🎒 CONFIGURACIÓN DE INVENTARIO</h4>
            <div class="form-grid">
                <div class="field"><label>Slots de Bodega (Defecto)</label>
                    <input type="number" value="${config.inventoryConfig.defaultMaxSlots}" onchange="config.inventoryConfig.defaultMaxSlots = parseInt(this.value)">
                </div>
                <div class="field" style="border: 1px solid rgba(255,255,255,0.05); padding: 8px; border-radius: 6px;">
                    <label style="color: var(--accent); font-weight: 600;">Costo de Expansión por Slot</label>
                    <div style="display: flex; gap: 8px; margin-top: 4px;">
                        <div style="flex: 1;">
                            <label style="font-size: 8px; opacity: 0.6; margin-bottom: 2px;">Hubs</label>
                            <input type="number" value="${typeof config.inventoryConfig.unlockSlotPrice === 'object' ? (config.inventoryConfig.unlockSlotPrice.hubs ?? 0) : config.inventoryConfig.unlockSlotPrice}" onchange="updateInventoryPrice('hubs', this.value)" style="height: 28px; font-size: 0.85rem; padding: 2px 6px;">
                        </div>
                        <div style="flex: 1;">
                            <label style="font-size: 8px; opacity: 0.6; margin-bottom: 2px;">Ohcu</label>
                            <input type="number" value="${typeof config.inventoryConfig.unlockSlotPrice === 'object' ? (config.inventoryConfig.unlockSlotPrice.ohcu ?? 0) : 0}" onchange="updateInventoryPrice('ohcu', this.value)" style="height: 28px; font-size: 0.85rem; padding: 2px 6px;">
                        </div>
                    </div>
                </div>
            </div>
        </div>
    `;

    // v1.9.1: Render Ammo Grid
    const ammoGrid = document.getElementById('starting-ammo-grid');
    if(ammoGrid) {
        if(!config.pilotConfig.startingAmmo) {
            config.pilotConfig.startingAmmo = {
                laser: [1000, 0, 0, 0, 0, 0],
                missile: [50, 0, 0, 0, 0, 0],
                mine: [10, 0, 0, 0, 0, 0]
            };
        }
        
        const types = [
            { id: 'laser', name: '🔦 LÁSERES', color: '#31dfff' },
            { id: 'missile', name: '🚀 MISILES', color: '#ff5500' },
            { id: 'mine', name: '💣 MINAS', color: '#ffe031' }
        ];
        
        ammoGrid.innerHTML = types.map(t => `
            <div class="ammo-col">
                <h5 style="color:${t.color}; margin-bottom:1rem; border-bottom:1px solid ${t.color}33; padding-bottom:5px;">${t.name}</h5>
                ${[0,1,2,3,4,5].map(tier => `
                    <div class="field" style="margin-bottom:10px;">
                        <label style="font-size:0.7rem;">Tier ${tier + 1}</label>
                        <input type="number" value="${config.pilotConfig.startingAmmo[t.id][tier]}" 
                               onchange="config.pilotConfig.startingAmmo['${t.id}'][${tier}] = parseInt(this.value)"
                               style="border-color:${t.color}66; color:${t.color}; font-family:'JetBrains Mono';">
                    </div>
                `).join('')}
            </div>
        `).join('');
    }

    const expGrid = document.getElementById('exp-grid');
    if(!expGrid) return;
    expGrid.innerHTML = '';
    for (let i = 0; i < 30; i++) {
        const field = document.createElement('div');
        field.className = 'field';
        field.innerHTML = `
            <label>Nivel ${i + 1} <span style="opacity:0.5; font-size:0.6rem;">(EXP Requerida)</span></label>
            <input type="number" value="${config.pilotConfig.expRequirements[i] || 0}" 
                   onchange="config.pilotConfig.expRequirements[${i}] = parseInt(this.value)"
                   style="font-family:'JetBrains Mono'; font-weight:bold; color:var(--primary); font-size: 1.1rem;">
        `;
        expGrid.appendChild(field);
    }

    // Inicializar el maquetador visual del HUD
    initWebHUDDesigner();
}

function renderBattlePass() {
    if (!config.battlePassConfig) {
        const niveles = [];
        for (let i = 0; i < 50; i++) {
            niveles.push({
                level: i + 1,
                expRequired: (i + 1) * 2000,
                freeReward: null,
                vipReward: null
            });
        }
        config.battlePassConfig = {
            enabled: true,
            seasonName: "Tempada 1: Alborada Galáctica",
            seasonDurationDays: 30,
            maxLevel: 50,
            vipCostHubs: 50000,
            vipCostOhcu: 200,
            xpSources: {
                killExp: 50,
                bossKillExp: 200,
                questExp: 100,
                extractionExp: 500,
                dailyBonusExp: 1000
            },
            levels: niveles
        };
    }

    const bp = config.battlePassConfig;

    const container = document.getElementById('battlepass-config-container');
    if (!container) return;

    container.innerHTML = `
        <div class="card">
            <h4 style="color:var(--accent); margin-bottom:1rem;">⚙️ CONFIGURACIÓN GENERAL</h4>
            <div class="form-grid">
                <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                    <input type="checkbox" id="bp-enabled" ${bp.enabled ? 'checked' : ''} onchange="config.battlePassConfig.enabled = this.checked">
                    <label for="bp-enabled" style="margin:0; cursor:pointer;">Pase de Batalla Activado</label>
                </div>
                <div class="field full"><label>Nombre de la Temporada</label><input type="text" value="${bp.seasonName}" onchange="config.battlePassConfig.seasonName = this.value"></div>
                <div class="field"><label>Duración (días)</label><input type="number" value="${bp.seasonDurationDays}" onchange="config.battlePassConfig.seasonDurationDays = parseInt(this.value)"></div>
                <div class="field"><label>Nivel Máximo</label><input type="number" value="${bp.maxLevel}" onchange="config.battlePassConfig.maxLevel = parseInt(this.value)"></div>
            </div>
        </div>
        <div class="card">
            <h4 style="color:var(--primary); margin-bottom:1rem;">👑 COSTO VIP</h4>
            <div class="form-grid">
                <div class="field"><label>Precio Hubs</label><input type="number" value="${bp.vipCostHubs}" onchange="config.battlePassConfig.vipCostHubs = parseInt(this.value)"></div>
                <div class="field"><label>Precio Ohcu</label><input type="number" value="${bp.vipCostOhcu}" onchange="config.battlePassConfig.vipCostOhcu = parseInt(this.value)"></div>
            </div>
            <h4 style="color:var(--accent); margin-top:2rem; margin-bottom:1rem;">📈 FUENTES DE EXP</h4>
            <div class="form-grid">
                <div class="field"><label>EXP por Kill Normal</label><input type="number" value="${bp.xpSources.killExp}" onchange="config.battlePassConfig.xpSources.killExp = parseInt(this.value)"></div>
                <div class="field"><label>EXP por Boss Kill</label><input type="number" value="${bp.xpSources.bossKillExp}" onchange="config.battlePassConfig.xpSources.bossKillExp = parseInt(this.value)"></div>
                <div class="field"><label>EXP por Misión</label><input type="number" value="${bp.xpSources.questExp}" onchange="config.battlePassConfig.xpSources.questExp = parseInt(this.value)"></div>
                <div class="field"><label>EXP por Extracción</label><input type="number" value="${bp.xpSources.extractionExp}" onchange="config.battlePassConfig.xpSources.extractionExp = parseInt(this.value)"></div>
                <div class="field"><label>EXP Diaria (Bonus)</label><input type="number" value="${bp.xpSources.dailyBonusExp}" onchange="config.battlePassConfig.xpSources.dailyBonusExp = parseInt(this.value)"></div>
            </div>
        </div>
    `;

    // Renderizar niveles
    const levelsContainer = document.getElementById('battlepass-levels-container');
    if (!levelsContainer) return;
    levelsContainer.innerHTML = '';

    const headerCard = document.createElement('div');
    headerCard.className = 'card';
    headerCard.style.width = '100%';
    headerCard.style.marginBottom = '1.5rem';
    headerCard.innerHTML = `
        <h3 style="color: var(--accent); margin-bottom: 1rem; display: flex; align-items: center; gap: 10px;">
            🎯 NIVELES DEL PASE DE BATALLA
            <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem;" onclick="addBattlePassLevel()">+ AGREGAR NIVEL</button>
            <button class="btn btn-secondary" style="padding: 4px 12px; font-size: 0.7rem; background:#ef4444; border-color:#ef4444;" onclick="regenerateBattlePassLevels()">🔄 REGENERAR</button>
        </h3>
        <p style="font-size:0.85rem; color:#aaa; line-height:1.4;">
            Configurá las recompensas de cada nivel del Pase de Batalla. Cada nivel tiene una recompensa <strong style="color:var(--primary);">GRATUITA</strong> 
            y una <strong style="color:var(--accent);">VIP</strong>. Hacé clic en "EDITAR RECOMPENSA" para configurar items, hubs, ohcu o exp.
        </p>
    `;
    levelsContainer.appendChild(headerCard);

    const levelsGrid = document.createElement('div');
    levelsGrid.style.display = 'grid';
    levelsGrid.style.gridTemplateColumns = 'repeat(auto-fill, minmax(300px, 1fr))';
    levelsGrid.style.gap = '1rem';
    levelsContainer.appendChild(levelsGrid);

    const levels = bp.levels || [];
    levels.forEach((lvl, idx) => {
        const card = document.createElement('div');
        card.className = 'card';
        card.style.position = 'relative';
        card.style.borderLeft = '3px solid ' + (lvl.freeReward || lvl.vipReward ? 'var(--accent)' : '#333');

        const freeLabel = lvl.freeReward ? formatRewardPreview(lvl.freeReward) : 'Sin recompensa';
        const vipLabel = lvl.vipReward ? formatRewardPreview(lvl.vipReward) : 'Sin recompensa';

        card.innerHTML = `
            <div style="position:absolute; top:8px; right:8px; display:flex; gap:6px;">
                <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem;" onclick="removeBattlePassLevel(${idx})" title="Eliminar nivel">✕</button>
            </div>
            <div class="card-tag" style="background:rgba(6,182,212,0.15); color:var(--accent);">NIVEL ${lvl.level}</div>
            <div class="field full" style="margin-top:0.8rem;">
                <label>EXP Requerida</label>
                <input type="number" value="${lvl.expRequired}" onchange="config.battlePassConfig.levels[${idx}].expRequired = parseInt(this.value)">
            </div>
            <div style="margin-top:1rem; padding-top:0.8rem; border-top:1px solid rgba(255,255,255,0.05);">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
                    <span style="color:var(--primary); font-size:0.8rem; font-weight:bold;">🆓 GRATUITO</span>
                    <button class="btn btn-primary" style="padding:2px 8px; font-size:0.6rem;" onclick="editBattlePassReward(${idx}, 'free')">EDITAR</button>
                </div>
                <div style="font-size:0.75rem; color:#aaa; background:rgba(0,0,0,0.2); padding:6px; border-radius:4px; min-height:30px;">
                    ${freeLabel}
                </div>
            </div>
            <div style="margin-top:0.8rem; padding-top:0.8rem; border-top:1px solid rgba(255,255,255,0.05);">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
                    <span style="color:var(--accent); font-size:0.8rem; font-weight:bold;">👑 VIP</span>
                    <button class="btn btn-primary" style="padding:2px 8px; font-size:0.6rem;" onclick="editBattlePassReward(${idx}, 'vip')">EDITAR</button>
                </div>
                <div style="font-size:0.75rem; color:#aaa; background:rgba(0,0,0,0.2); padding:6px; border-radius:4px; min-height:30px;">
                    ${vipLabel}
                </div>
            </div>
        `;
        levelsGrid.appendChild(card);
    });
}

function formatRewardPreview(reward) {
    if (!reward) return '<span style="color:#555;">Vacío</span>';
    const parts = [];
    if (reward.hubs) parts.push(`💰 ${reward.hubs} Hubs`);
    if (reward.ohcu) parts.push(`💎 ${reward.ohcu} Ohcu`);
    if (reward.exp) parts.push(`📈 ${reward.exp} EXP`);
    if (reward.itemName) parts.push(`📦 ${reward.itemName}${reward.itemAmount ? ' x' + reward.itemAmount : ''}`);
    if (reward.shipId) parts.push(`🚀 Nave ID: ${reward.shipId}`);
    if (reward.isPremium) parts.push('👑 VIP Gratis');
    return parts.length > 0 ? parts.join(' | ') : '<span style="color:#555;">Vacío</span>';
}

function addBattlePassLevel() {
    if (!config.battlePassConfig) config.battlePassConfig = {};
    if (!config.battlePassConfig.levels) config.battlePassConfig.levels = [];
    const lastLvl = config.battlePassConfig.levels.length > 0
        ? config.battlePassConfig.levels[config.battlePassConfig.levels.length - 1]
        : { level: 0, expRequired: 0 };
    config.battlePassConfig.levels.push({
        level: lastLvl.level + 1,
        expRequired: lastLvl.expRequired + 2000,
        freeReward: null,
        vipReward: null
    });
    renderBattlePass();
}

function removeBattlePassLevel(idx) {
    if (!config.battlePassConfig || !config.battlePassConfig.levels) return;
    config.battlePassConfig.levels.splice(idx, 1);
    renderBattlePass();
}

function regenerateBattlePassLevels() {
    if (!config.battlePassConfig) return;
    const maxLevel = config.battlePassConfig.maxLevel || 50;
    const niveles = [];
    for (let i = 0; i < maxLevel; i++) {
        niveles.push({
            level: i + 1,
            expRequired: (i + 1) * 2000,
            freeReward: null,
            vipReward: null
        });
    }
    config.battlePassConfig.levels = niveles;
    renderBattlePass();
}

function editBattlePassReward(levelIdx, track) {
    const bp = config.battlePassConfig;
    if (!bp || !bp.levels || !bp.levels[levelIdx]) return;

    const rewardKey = track === 'free' ? 'freeReward' : 'vipReward';
    const current = bp.levels[levelIdx][rewardKey] || {};

    const overlay = document.createElement('div');
    overlay.style.cssText = 'position:fixed; inset:0; background:rgba(0,0,0,0.85); backdrop-filter:blur(8px); z-index:100000; display:flex; align-items:center; justify-content:center; padding:2rem;';
    overlay.id = 'bp-reward-overlay';

    const card = document.createElement('div');
    card.className = 'card';
    card.style.cssText = 'max-width:500px; width:100%; padding:2rem;';

    card.innerHTML = `
        <h3 style="color:var(--accent); margin-bottom:1.5rem;">🎁 EDITAR RECOMPENSA ${track === 'free' ? 'GRATUITA' : 'VIP'} - NIVEL ${bp.levels[levelIdx].level}</h3>
        <div class="form-grid">
            <div class="field"><label>Hubs</label><input type="number" id="bp-reward-hubs" value="${current.hubs || 0}"></div>
            <div class="field"><label>Ohcu</label><input type="number" id="bp-reward-ohcu" value="${current.ohcu || 0}"></div>
            <div class="field"><label>EXP</label><input type="number" id="bp-reward-exp" value="${current.exp || 0}"></div>
            <div class="field full"><label>Nombre del Ítem</label><input type="text" id="bp-reward-item-name" value="${current.itemName || ''}" placeholder="Ej: laser_01"></div>
            <div class="field"><label>Cantidad del Ítem</label><input type="number" id="bp-reward-item-amount" value="${current.itemAmount || 1}"></div>
            <div class="field"><label>ID de Nave</label><input type="number" id="bp-reward-ship-id" value="${current.shipId || 0}" placeholder="0 = ninguna"></div>
            <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;">
                <input type="checkbox" id="bp-reward-is-premium" ${current.isPremium ? 'checked' : ''}>
                <label for="bp-reward-is-premium" style="margin:0; cursor:pointer;">Desbloquear VIP (solo para recompensa gratuita)</label>
            </div>
        </div>
        <div style="display:flex; gap:15px; margin-top:2rem; justify-content:flex-end;">
            <button class="btn btn-secondary" onclick="closeBattlePassRewardEditor()">CANCELAR</button>
            <button class="btn btn-primary" onclick="saveBattlePassReward(${levelIdx}, '${track}')">GUARDAR</button>
        </div>
    `;

    overlay.appendChild(card);
    document.body.appendChild(overlay);
}

function saveBattlePassReward(levelIdx, track) {
    const rewardKey = track === 'free' ? 'freeReward' : 'vipReward';
    const hubs = parseInt(document.getElementById('bp-reward-hubs').value) || 0;
    const ohcu = parseInt(document.getElementById('bp-reward-ohcu').value) || 0;
    const exp = parseInt(document.getElementById('bp-reward-exp').value) || 0;
    const itemName = document.getElementById('bp-reward-item-name').value.trim();
    const itemAmount = parseInt(document.getElementById('bp-reward-item-amount').value) || 1;
    const shipId = parseInt(document.getElementById('bp-reward-ship-id').value) || 0;
    const isPremium = document.getElementById('bp-reward-is-premium').checked;

    const reward = {};
    if (hubs > 0) reward.hubs = hubs;
    if (ohcu > 0) reward.ohcu = ohcu;
    if (exp > 0) reward.exp = exp;
    if (itemName) { reward.itemName = itemName; reward.itemAmount = itemAmount; }
    if (shipId > 0) reward.shipId = shipId;
    if (isPremium) reward.isPremium = true;

    config.battlePassConfig.levels[levelIdx][rewardKey] = Object.keys(reward).length > 0 ? reward : null;
    closeBattlePassRewardEditor();
    renderBattlePass();
}

function closeBattlePassRewardEditor() {
    const overlay = document.getElementById('bp-reward-overlay');
    if (overlay) overlay.remove();
}

const HUD_ELEMENTS_CONFIG = {
    "CenterStats":           { name: "🧬 STATS (CenterStats)", x: 1063,  y: 21,  w: 250, h: 140 },
    "ChatUI":                { name: "💬 CHAT (ChatUI)", x: 12,    y: 545, w: 320, h: 200 },
    "RadarWindow":           { name: "🛰️ RADAR (RadarWindow)", x: 1066,  y: 564, w: 220, h: 220 },
    "SkillsContainer":       { name: "🔥 SKILLS (SkillsContainer)", x: 101,   y: 684, w: 575, h: 65 },
    "PartyHUD":              { name: "👥 PARTY (PartyHUD)", x: 10,    y: 120, w: 220, h: 200 },
    "ControlBar":            { name: "⚙️ MENÚS (ControlBar)", x: 10,    y: 745, w: 340, h: 45 },
    "StatusEffects":         { name: "✨ ESTADOS (StatusEffects)", x: 390,   y: 620, w: 500, h: 55 },
    "CamTouchPadContainer":  { name: "🎥 CÁMARA (CamTouchPad)", x: 1060,  y: 250, w: 190, h: 230 },
    "TargetFrame":           { name: "🎯 ENEMIGO (TargetFrame)", x: 540,  y: 80,  w: 200, h: 65 },
    "CombatMeter":           { name: "⚔️ COMBAT (CombatMeter)", x: 940,  y: 180, w: 340, h: 220 },
    "TopLeft":               { name: "📈 DIAGNÓSTICOS (TopLeft)", x: 10,    y: 10,  w: 180, h: 120 }
};
 
function initWebHUDDesigner() {
    const canvas = document.getElementById('web-hud-canvas');
    if (!canvas) return;
 
    if (!config.pilotConfig.defaultLayout) {
        // Inicializar con los defaults idénticos a los de fábrica de Godot
        config.pilotConfig.defaultLayout = {
            "TopLeft":         { "x": 10,    "y": 10,    "scale": 0.5, "alpha": 1.0 },
            "PartyHUD":        { "x": 10,    "y": 120,   "scale": 0.5, "alpha": 1.0 },
            "ControlBar":      { "x": 10,    "y": 745,   "scale": 0.5, "alpha": 1.0, "rows": 2 },
            "StatusEffects":   { "x": 390,   "y": 620,   "scale": 0.5, "alpha": 1.0 },
            "CamTouchPadContainer":  { "x": 1060,  "y": 250,   "scale": 0.5, "alpha": 1.0 },
            "TargetFrame":     { "x": 540,   "y": 80,    "scale": 0.5, "alpha": 1.0 },
            "CombatMeter":     { "x": 940,   "y": 180,   "scale": 0.5, "alpha": 1.0 }
        };
    } else {
        if (!config.pilotConfig.defaultLayout["TargetFrame"]) {
            config.pilotConfig.defaultLayout["TargetFrame"] = { "x": 540, "y": 80, "scale": 0.5, "alpha": 1.0 };
        }
        if (!config.pilotConfig.defaultLayout["CombatMeter"]) {
            config.pilotConfig.defaultLayout["CombatMeter"] = { "x": 940, "y": 180, "scale": 0.5, "alpha": 1.0 };
        }
    }

    const layout = config.pilotConfig.defaultLayout;
    
    // Sincronizar el selector de filas de la barra de menús
    const rowsSel = document.getElementById('web-hud-controlbar-rows');
    if (rowsSel) {
        const currentRows = (layout["ControlBar"] && layout["ControlBar"].rows) || 2;
        rowsSel.value = currentRows;
    }

    canvas.innerHTML = `
        <div class="hud-canvas-axis-h"></div>
        <div class="hud-canvas-axis-v"></div>
    `; // Limpiar y meter ejes centrales

    // Dibujar cada elemento en el lienzo
    Object.keys(HUD_ELEMENTS_CONFIG).forEach(winId => {
        const spec = JSON.parse(JSON.stringify(HUD_ELEMENTS_CONFIG[winId]));
        const state = layout[winId] || { x: spec.x, y: spec.y };
        
        // Convertir coordenadas del plano de 1280x800 al canvas de 640x400 (Escala 0.5)
        const webX = state.x / 2.0;
        const webY = state.y / 2.0;
        const webW = spec.w / 2.0;
        const webH = spec.h / 2.0;

        const el = document.createElement('div');
        el.className = 'hud-element';
        el.id = `web-hud-${winId}`;
        el.innerText = spec.name;
        el.style.width = `${webW}px`;
        el.style.height = `${webH}px`;
        el.style.left = `${webX}px`;
        el.style.top = `${webY}px`;

        // Lógica premium de arrastre Drag & Drop en JS
        el.addEventListener('mousedown', (e) => {
            e.preventDefault();
            const startX = e.clientX;
            const startY = e.clientY;
            const elemLeft = el.offsetLeft;
            const elemTop = el.offsetTop;

            const onMouseMove = (moveEvent) => {
                let dx = moveEvent.clientX - startX;
                let dy = moveEvent.clientY - startY;

                let newLeft = elemLeft + dx;
                let newTop = elemTop + dy;

                // Limitar el movimiento estrictamente dentro del canvas (640x400)
                const maxLeft = 640 - webW;
                const maxTop = 400 - webH;

                newLeft = Math.max(0, Math.min(newLeft, maxLeft));
                newTop = Math.max(0, Math.min(newTop, maxTop));

                el.style.left = `${newLeft}px`;
                el.style.top = `${newTop}px`;

                // Guardar la coordenada escalada de vuelta a la base de 1280x800 en memoria
                if (!layout[winId]) layout[winId] = { scale: 0.5, alpha: 1.0 };
                
                if (winId === "SkillsContainer") {
                    const oldX = layout[winId].x !== undefined ? layout[winId].x : spec.x;
                    const oldY = layout[winId].y !== undefined ? layout[winId].y : spec.y;
                    const newX = Math.round(newLeft * 2.0);
                    const newY = Math.round(newTop * 2.0);
                    const dx = newX - oldX;
                    const dy = newY - oldY;

                    const slots = ["LaserSlot", "MissileSlot", "MineSlot", "Sphere1Slot", "Sphere2Slot", "Sphere3Slot", "Sphere4Slot"];
                    slots.forEach(slotId => {
                        if (!layout[slotId]) {
                            const defaultSlots = {
                                "LaserSlot":       { "x": 364.5, "y": 714 },
                                "MissileSlot":     { "x": 449.5, "y": 714 },
                                "MineSlot":        { "x": 534.5, "y": 714 },
                                "Sphere1Slot":     { "x": 619.5, "y": 714 },
                                "Sphere2Slot":     { "x": 704.5, "y": 714 },
                                "Sphere3Slot":     { "x": 789.5, "y": 714 },
                                "Sphere4Slot":     { "x": 874.5, "y": 714 }
                            };
                            layout[slotId] = { 
                                x: defaultSlots[slotId].x, 
                                y: defaultSlots[slotId].y, 
                                scale: 0.5, 
                                alpha: 1.0 
                            };
                        }
                        layout[slotId].x = Math.round(layout[slotId].x + dx);
                        layout[slotId].y = Math.round(layout[slotId].y + dy);
                    });
                }
                
                layout[winId].x = Math.round(newLeft * 2.0);
                layout[winId].y = Math.round(newTop * 2.0);
            };

            const onMouseUp = () => {
                document.removeEventListener('mousemove', onMouseMove);
                document.removeEventListener('mouseup', onMouseUp);
            };

            document.addEventListener('mousemove', onMouseMove);
            document.addEventListener('mouseup', onMouseUp);
        });

        canvas.appendChild(el);
    });
}

window.updateWebHUDControlBarRows = function(val) {
    const rows = parseInt(val) || 2;
    if (!config.pilotConfig.defaultLayout) config.pilotConfig.defaultLayout = {};
    if (!config.pilotConfig.defaultLayout["ControlBar"]) config.pilotConfig.defaultLayout["ControlBar"] = { scale: 0.5, alpha: 1.0 };
    config.pilotConfig.defaultLayout["ControlBar"].rows = rows;
    
    // Actualizar tamaño de la caja en el canvas
    const el = document.getElementById('web-hud-ControlBar');
    if (el) {
        // Escala 0.5
        const w = (rows === 2 ? 260 : 420) / 2.0;
        const h = (rows === 2 ? 85 : 45) / 2.0;
        el.style.width = `${w}px`;
        el.style.height = `${h}px`;
    }
};

function renderModes() {
    if (!config.gameModes) {
        config.gameModes = {
            hunting: { enabled: true, targets: [], rewardMult: 1.2 },
            extraction: { enabled: true, zones: [], difficulty: 1 },
            arenas: { enabled: true, maps: [], minPlayers: 2 }
        };
    }
    if (!config.gameModes.altar_defense) {
        config.gameModes.altar_defense = {
            enabled: true,
            maxPlayers: 4,
            altarHp: 10000,
            altarShield: 5000,
            maps: [],
            altarPos: { x: 5000, y: 5000 },
            spawnPoints: [],
            spawners: [],
            waves: [],
            width: 10000,
            height: 10000
        };
    }

    const content = document.getElementById('modes-content');
    if (!content) return;

    if (currentModeTab === 'hunting') {
        content.innerHTML = `
            <div class="card" style="grid-column: span 2;">
                <h3 style="color:var(--accent); margin-bottom: 0.5rem;">🔫 MODO CACERÍA</h3>
                <p style="opacity:0.7; margin-bottom:1.5rem;">Configuración de eventos de eliminación de objetivos prioritarios.</p>
                <div class="form-grid">
                    <div class="field">
                        <label>Estado del Modo</label>
                        <select onchange="config.gameModes.hunting.enabled = this.value === 'true'">
                            <option value="true" ${config.gameModes.hunting.enabled ? 'selected' : ''}>Activo</option>
                            <option value="false" ${!config.gameModes.hunting.enabled ? 'selected' : ''}>Inactivo</option>
                        </select>
                    </div>
                    <div class="field">
                        <label>Multiplicador de Recompensa</label>
                        <input type="number" step="0.1" value="${config.gameModes.hunting.rewardMult}" 
                               onchange="config.gameModes.hunting.rewardMult = parseFloat(this.value)">
                    </div>
                </div>
            </div>
            <div class="card">
                <h4 style="color:var(--primary); margin-bottom: 1rem;">🎯 OBJETIVOS PRIORITARIOS</h4>
                <p style="font-size:0.8rem; opacity:0.6;">Lista de IDs de enemigos que activan el bono de cacería.</p>
                <input type="text" placeholder="Ej: 101, 102, 103" value="${config.gameModes.hunting.targets.join(', ')}"
                       onchange="config.gameModes.hunting.targets = this.value.split(',').map(v => v.trim())"
                       style="margin-top:10px;">
            </div>
        `;
    } else if (currentModeTab === 'extraction') {
        if (!config.gameModes.extraction.minPlayers) config.gameModes.extraction.minPlayers = 2;
        if (!config.gameModes.extraction.startCountdown) config.gameModes.extraction.startCountdown = 30000;
        if (!config.gameModes.extraction.maxPlayers) config.gameModes.extraction.maxPlayers = 21;
        if (!config.gameModes.extraction.countdownTime) config.gameModes.extraction.countdownTime = 600000;
        if (!config.gameModes.extraction.extractRadius) config.gameModes.extraction.extractRadius = 150;
        if (!config.gameModes.extraction.spawnLockTime) config.gameModes.extraction.spawnLockTime = 10000;
        if (!config.gameModes.extraction.maps) config.gameModes.extraction.maps = [10];
        if (!config.gameModes.extraction.spawners) config.gameModes.extraction.spawners = [];
        if (!config.gameModes.extraction.spawnPoints) config.gameModes.extraction.spawnPoints = [];
        if (!config.gameModes.extraction.mechanics) config.gameModes.extraction.mechanics = [];
        config.gameModes.extraction.mechanics = config.gameModes.extraction.mechanics.filter(Boolean);
        if (!config.gameModes.extraction.extractPoints) {
            config.gameModes.extraction.extractPoints = [
                { x: 1500, y: 1500, label: "Punto Alfa" },
                { x: 8500, y: 1500, label: "Punto Beta" }
            ];
        }

        content.innerHTML = `
            <div style="grid-column: 1 / -1; display:flex; flex-direction:column; gap:20px; width:100%; padding-bottom:40px;">
                
                <!-- NIVEL 1: REGLAS Y MAPAS -->
                <div style="display:grid; grid-template-columns: 1fr 1fr; gap:20px;">
                    <!-- REGLAS MAESTRAS -->
                    <div class="card" style="margin:0;">
                        <h3 style="color:var(--primary); margin-bottom: 0.5rem;">📦 MODO EXTRACCIÓN (REGLAS MAESTRAS)</h3>
                        <p style="opacity:0.7; margin-bottom:1.5rem;">Configuración del emparejador y tiempos globales.</p>
                        <div class="form-grid" style="grid-template-columns: repeat(4, 1fr);">
                            <div class="field"><label>Estado</label>
                                <select onchange="config.gameModes.extraction.enabled = this.value === 'true'">
                                    <option value="true" ${config.gameModes.extraction.enabled ? 'selected' : ''}>ACTIVO</option>
                                    <option value="false" ${!config.gameModes.extraction.enabled ? 'selected' : ''}>DESACTIVADO</option>
                                </select>
                            </div>
                            <div class="field"><label>Mín. Pilotos</label><input type="number" value="${config.gameModes.extraction.minPlayers}" onchange="config.gameModes.extraction.minPlayers = parseInt(this.value)"></div>
                            <div class="field"><label>Máx. Pilotos</label><input type="number" value="${config.gameModes.extraction.maxPlayers}" onchange="config.gameModes.extraction.maxPlayers = parseInt(this.value)"></div>
                            <div class="field"><label>Inicio (ms)</label><input type="number" step="1000" value="${config.gameModes.extraction.startCountdown}" onchange="config.gameModes.extraction.startCountdown = parseInt(this.value)"></div>
                            <div class="field"><label>Extracción (ms)</label><input type="number" step="1000" value="${config.gameModes.extraction.countdownTime}" onchange="config.gameModes.extraction.countdownTime = parseInt(this.value)"></div>
                            <div class="field"><label>Bloqueo Spawn (ms)</label><input type="number" step="1000" value="${config.gameModes.extraction.spawnLockTime}" onchange="config.gameModes.extraction.spawnLockTime = parseInt(this.value)" style="color:var(--accent); font-weight:bold;"></div>
                            <div class="field"><label>Radio Ext. (px)</label><input type="number" value="${config.gameModes.extraction.extractRadius}" onchange="config.gameModes.extraction.extractRadius = parseInt(this.value)"></div>
                        </div>
                    </div>

                    <!-- MAPAS HABILITADOS -->
                    <div class="card" style="margin:0;">
                        <h3 style="color:var(--primary); margin-bottom: 0.5rem;">🗺️ MAPAS PARA EXTRACCIÓN</h3>
                        <p style="opacity:0.6; margin-bottom:1.5rem;">Selecciona los mapas donde el modo estará activo.</p>
                        <div style="display:flex; gap:10px; margin-bottom:15px;">
                            <select id="add-ext-map-select" style="font-size:0.8rem; flex:1;">
                                <option value="" disabled selected hidden>🔍 Seleccionar mapa...</option>
                                ${Object.keys(config.mapsConfig).map(id => `<option value="${id}">${config.mapsConfig[id].name}</option>`).join('')}
                            </select>
                            <button class="btn btn-primary" style="padding:4px 15px; font-size:0.7rem;" onclick="addExtractionMap()">+ AÑADIR MAPA</button>
                        </div>
                        <div style="display:flex; flex-wrap:wrap; gap:8px; max-height:100px; overflow-y:auto;">
                            ${config.gameModes.extraction.maps.map((mapId, idx) => `
                                <div style="background:rgba(255,255,255,0.05); padding:6px 12px; border-radius:20px; border:1px solid rgba(255,255,255,0.1); display:flex; align-items:center; gap:10px; font-size:0.75rem;">
                                    <span>${config.mapsConfig[mapId]?.name || 'ID '+mapId}</span>
                                    <button onclick="config.gameModes.extraction.maps.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                </div>

                <!-- NIVEL 2: 4 COLUMNAS -->
                <div style="display:grid; grid-template-columns: repeat(4, 1fr); gap:20px;">
                    <!-- SPAWN POINTS (PLAYERS) -->
                    <div class="card" style="margin:0; border-top: 3px solid var(--accent);">
                        <h4 style="color:var(--accent); margin-bottom:1rem;">📍 SPAWN DE JUGADORES</h4>
                        <div style="display:flex; flex-direction:column; gap:8px; max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${(config.gameModes.extraction.spawnPoints || []).map((p, idx) => `
                                <div id="card-spawn-${idx}" onclick="highlightCard('spawn', ${idx})" style="background:rgba(6,182,212,0.05); border:1px solid rgba(6,182,212,0.2); border-radius:8px; padding:10px; transition: all 0.3s ease; cursor:pointer;">
                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                        <input type="text" value="${p.label || 'Punto #'+(idx+1)}" onchange="config.gameModes.extraction.spawnPoints[${idx}].label = this.value" style="background:none; border:none; color:var(--accent); font-weight:bold; font-size:0.7rem; width:70%;">
                                        <button onclick="config.gameModes.extraction.spawnPoints.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px;">
                                        <div class="field"><label>X</label><input type="number" id="spw-x-${idx}" value="${p.x}" onchange="config.gameModes.extraction.spawnPoints[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Y</label><input type="number" id="spw-y-${idx}" value="${p.y}" onchange="config.gameModes.extraction.spawnPoints[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                    <div class="field" style="margin-top:5px;"><label>Radio Burbuja</label><input type="number" value="${p.radius}" onchange="config.gameModes.extraction.spawnPoints[${idx}].radius = parseInt(this.value)"></div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <!-- PUNTOS DE ESCAPE -->
                    <div class="card" style="margin:0;">
                        <h4 style="color:var(--primary); margin-bottom:1rem;">🛰️ PUNTOS DE ESCAPE</h4>
                        <div style="display:flex; flex-direction:column; gap:8px; max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${config.gameModes.extraction.extractPoints.map((p, idx) => `
                                <div id="card-extract-${idx}" onclick="highlightCard('extract', ${idx})" style="background:rgba(0,210,255,0.05); border:1px solid rgba(0,210,255,0.2); border-radius:8px; padding:10px; transition: all 0.3s ease; cursor:pointer; overflow: visible;">
                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                        <input type="text" value="${p.label}" onchange="config.gameModes.extraction.extractPoints[${idx}].label = this.value" style="background:none; border:none; color:var(--primary); font-weight:bold; font-size:0.75rem; width:70%;">
                                        <button onclick="config.gameModes.extraction.extractPoints.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px; margin-bottom:8px;">
                                        <div class="field"><label>Coord X (px)</label><input type="number" id="ep-x-${idx}" value="${p.x}" onchange="config.gameModes.extraction.extractPoints[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Coord Y (px)</label><input type="number" id="ep-y-${idx}" value="${p.y}" onchange="config.gameModes.extraction.extractPoints[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                    <div class="field" style="margin-bottom:8px; overflow: visible; width: 100%;">
                                        <label>Mapa de Destino</label>
                                        ${renderSearchableMapSelect(p.targetZone || "1", (newId) => {
                                            config.gameModes.extraction.extractPoints[idx].targetZone = newId;
                                        }, 'var(--primary)', `ext-map-${idx}`)}
                                    </div>
                                    <div class="field">
                                        <label>Radio de Proximidad (px)</label>
                                        <input type="number" value="${p.proximityRadius || 300}" onchange="config.gameModes.extraction.extractPoints[${idx}].proximityRadius = parseInt(this.value)">
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <!-- AMENAZAS -->
                    <div class="card" style="margin:0;">
                        <h4 style="color:var(--danger); margin-bottom:1rem;">👾 AMENAZAS DESPLEGADAS</h4>
                        <div style="display:flex; flex-direction:column; gap:10px; max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${config.gameModes.extraction.spawners.map((s, idx) => `
                                <div id="card-spawner-${idx}" onclick="highlightCard('spawner', ${idx})" style="background:rgba(255,49,49,0.05); border:1px solid rgba(255,49,49,0.2); border-radius:8px; padding:10px; overflow: visible; transition: all 0.3s ease; cursor:pointer;">
                                    <div style="display:flex; flex-direction:column; gap:8px; margin-bottom:8px; overflow: visible;">
                                        <div style="display:flex; justify-content:space-between; align-items:center;">
                                            <input type="text" value="${s.label || 'Zona '+ (idx+1)}" onchange="config.gameModes.extraction.spawners[${idx}].label = this.value; renderModes();" style="background:none; border:none; color:var(--danger); font-weight:bold; font-size:0.75rem; width:85%;">
                                            <button onclick="config.gameModes.extraction.spawners.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                        </div>
                                        <div style="overflow: visible; width: 100%;">
                                            ${renderSearchableEnemySelect(s.enemyId, (newId) => {
                                                config.gameModes.extraction.spawners[idx].enemyId = newId;
                                                renderModes();
                                            }, 'var(--danger)', `ext-spawn-${idx}`)}
                                        </div>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px;">
                                        <div class="field"><label>Cant.</label><input type="number" value="${s.count}" onchange="config.gameModes.extraction.spawners[${idx}].count = parseInt(this.value)"></div>
                                        <div class="field"><label>Radio</label><input type="number" value="${s.radius}" onchange="config.gameModes.extraction.spawners[${idx}].radius = parseInt(this.value)"></div>
                                        <div class="field"><label>Coord X</label><input type="number" id="sp-x-${idx}" value="${s.x}" onchange="config.gameModes.extraction.spawners[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Coord Y</label><input type="number" id="sp-y-${idx}" value="${s.y}" onchange="config.gameModes.extraction.spawners[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <!-- MECÁNICAS -->
                    <div class="card" style="margin:0;">
                        <h4 style="color:var(--accent); margin-bottom:1rem;">🌍 MECÁNICAS</h4>
                        <p style="opacity:0.6; font-size:0.7rem; margin-bottom:1rem;">Efectos de ambiente de tu librería.</p>
                        <div style="display:flex; gap:10px; margin-bottom:15px;">
                            <select id="add-ext-mech-select" style="font-size:0.7rem; flex:1;">
                                ${Object.keys(AMBIENCE_LIB).map(type => `<option value="${type}">${AMBIENCE_LIB[type].icon || '🌍'} ${AMBIENCE_LIB[type].label}</option>`).join('')}
                            </select>
                            <button class="btn btn-primary" style="padding:4px 10px; font-size:0.6rem;" onclick="addExtractionMechanic()">+ ACTIVAR</button>
                        </div>
                        <div style="display:flex; flex-direction:column; gap:8px;">
                            ${(config.gameModes.extraction.mechanics || []).map((m, idx) => `
                                <div style="background:rgba(6,182,212,0.1); border:1px solid var(--accent); padding:10px; border-radius:8px; display:flex; justify-content:space-between; align-items:center;">
                                    <span style="color:var(--accent); font-weight:bold; font-size:0.7rem;">${AMBIENCE_LIB[m]?.icon || ''} ${(AMBIENCE_LIB[m]?.label || m).toUpperCase()}</span>
                                    <button onclick="config.gameModes.extraction.mechanics.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                </div>

                <!-- NIVEL 3: RADAR GLOBAL -->
                <div class="card" style="margin:0;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.5rem;">
                        <div style="display:flex; align-items:center; gap:20px;">
                            <h4 style="color:var(--primary); margin:0;">🛰️ RADAR DE POSICIONAMIENTO GLOBAL</h4>
                            <div style="display:flex; align-items:center; gap:10px; background:rgba(255,255,255,0.03); padding:4px 12px; border-radius:8px; border:1px solid rgba(255,255,255,0.05);">
                                <label style="font-size:0.65rem; color:var(--accent); font-weight:bold; letter-spacing:1px; margin:0;">DIMENSIONES MUNDO (PX):</label>
                                <div style="display:flex; align-items:center; gap:5px;">
                                    <span style="font-size:0.65rem; opacity:0.6;">W:</span>
                                    <input type="number" value="${config.gameModes.extraction.width || 10000}" 
                                           onchange="config.gameModes.extraction.width = parseInt(this.value); renderModes();" 
                                           style="width:70px; background:rgba(0,0,0,0.3); border:1px solid #333; color:white; font-size:0.75rem; text-align:center; padding:2px; border-radius:4px; font-weight:bold; font-family:'JetBrains Mono',monospace;">
                                </div>
                                <div style="display:flex; align-items:center; gap:5px; margin-left:10px;">
                                    <span style="font-size:0.65rem; opacity:0.6;">H:</span>
                                    <input type="number" value="${config.gameModes.extraction.height || 10000}" 
                                           onchange="config.gameModes.extraction.height = parseInt(this.value); renderModes();" 
                                           style="width:70px; background:rgba(0,0,0,0.3); border:1px solid #333; color:white; font-size:0.75rem; text-align:center; padding:2px; border-radius:4px; font-weight:bold; font-family:'JetBrains Mono',monospace;">
                                </div>
                            </div>
                        </div>
                        <div style="display:flex; gap:10px;">
                            <button id="btn-radar-spawn" class="btn ${radarMode === 'spawn' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('spawn')">MODO SPAWN</button>
                            <button id="btn-radar-spawner" class="btn ${radarMode === 'spawner' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('spawner')">MODO AMENAZA</button>
                            <button id="btn-radar-extract" class="btn ${radarMode === 'extract' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('extract')">MODO ESCAPE</button>
                        </div>
                    </div>
                    
                    <div style="display:flex; flex-wrap:wrap; justify-content:center; gap:30px; width:100%;">
                        <div id="radar-container" style="position:relative; width:600px; height:600px; background:#000; border:2px solid var(--primary); border-radius:10px; overflow:hidden; cursor:crosshair; box-shadow: 0 0 20px rgba(0, 210, 255, 0.15);">
                            <canvas id="radar-canvas" width="600" height="600" style="width: 100%; height: 100%; display: block;"></canvas>
                        </div>
                        
                        <div style="flex:1; min-width:350px; display:flex; flex-direction:column; gap:15px; background:rgba(255,255,255,0.02); padding:25px; border-radius:10px; overflow: visible;">
                            <label style="color:var(--accent); font-size:0.85rem; margin-bottom:15px; display:block; border-bottom:1px solid rgba(255,255,255,0.1); padding-bottom:10px; font-weight:bold; overflow: visible;">🛠️ HERRAMIENTA DE DESPLIEGUE</label>
                            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:15px;">
                                <div class="field"><label>Coord X</label><input type="number" id="radar-x" value="0"></div>
                                <div class="field"><label>Coord Y</label><input type="number" id="radar-y" value="0"></div>
                            </div>
                            <div id="radar-spawn-opts" style="display:${radarMode === 'spawn' ? 'block' : 'none'}">
                                <div class="field" style="margin-top:10px;"><label>Nombre</label><input type="text" id="radar-spawn-label" value="Punto Spawn"></div>
                                <div class="field" style="margin-top:5px;"><label>Radio Burbuja</label><input type="number" id="radar-spawn-radius" value="500"></div>
                            </div>
                            <div id="radar-spawner-opts" style="display:${radarMode === 'spawner' ? 'block' : 'none'}; overflow: visible;">
                                <div class="field" style="margin-top:10px;"><label>Nombre Zona</label><input type="text" id="radar-spawner-label" value="Zona de Amenaza"></div>
                                <div class="field" style="margin-top:10px; overflow: visible;">
                                    <label>Enemigo</label>
                                    <input type="hidden" id="spawner-enemy-select" value="${config.gameModes.extraction.spawners[0]?.enemyId || '1'}">
                                    ${renderSearchableEnemySelect(config.gameModes.extraction.spawners[0]?.enemyId || '1', (newId) => {
                                        document.getElementById('spawner-enemy-select').value = newId;
                                    }, 'var(--accent)', 'radar-spawn-select')}
                                </div>
                                <div class="field" style="margin-top:10px;"><label>Cantidad</label><input type="number" id="radar-count" value="10"></div>
                                <div class="field" style="margin-top:10px;"><label>Radio</label><input type="number" id="radar-radius" value="500"></div>
                            </div>
                            <div id="radar-extract-opts" style="display:${radarMode === 'extract' ? 'block' : 'none'}">
                                <div class="field" style="margin-top:10px;"><label>Etiqueta</label><input type="text" id="radar-label" value="Punto Nuevo"></div>
                            </div>
                            <button class="btn btn-primary" style="width:100%; margin-top:20px; padding:15px; font-weight:bold;" onclick="addFromRadar()">FIJAR EN EL MAPA</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        setTimeout(initRadar, 100);
    } else if (currentModeTab === 'altar_defense') {
        const ad = config.gameModes.altar_defense;
        if (!ad.maxPlayers) ad.maxPlayers = 4;
        if (!ad.minPlayers) ad.minPlayers = 2;
        if (!ad.altarHp) ad.altarHp = 10000;
        if (!ad.altarShield) ad.altarShield = 5000;
        if (!ad.partyAcceptTimeout) ad.partyAcceptTimeout = 10000;
        if (ad.waveInterval === undefined) ad.waveInterval = 30000;
        if (ad.spawnLockTime === undefined) ad.spawnLockTime = 10000;
        if (ad.matchDuration === undefined) ad.matchDuration = 600000;
        if (ad.loseLootOnDeath === undefined) ad.loseLootOnDeath = true;
        if (!ad.maps) ad.maps = [];
        if (!ad.altarPos) ad.altarPos = { x: 5000, y: 5000 };
        if (!ad.spawnPoints) ad.spawnPoints = [];
        if (!ad.spawners) ad.spawners = [];
        if (!ad.exitPortals) ad.exitPortals = [];
        if (!ad.waves) ad.waves = [];

        content.innerHTML = `
            <div style="grid-column: 1 / -1; display:flex; flex-direction:column; gap:20px; width:100%; padding-bottom:40px;">
                
                <!-- NIVEL 1: REGLAS Y MAPAS -->
                <div style="display:grid; grid-template-columns: 1.2fr 0.8fr; gap:20px;">
                    <!-- REGLAS MAESTRAS -->
                    <div class="card" style="margin:0;">
                        <h3 style="color:var(--primary); margin-bottom: 0.5rem;">🛡️ DEFENSA DEL ALTAR (REGLAS MAESTRAS)</h3>
                        <p style="opacity:0.7; margin-bottom:1.5rem;">Configura las reglas básicas y temporizadores del modo de juego.</p>
                        <div class="form-grid" style="grid-template-columns: repeat(5, 1fr); gap: 15px;">
                            <div class="field"><label>Estado</label>
                                <select onchange="config.gameModes.altar_defense.enabled = this.value === 'true'">
                                    <option value="true" ${ad.enabled ? 'selected' : ''}>ACTIVO</option>
                                    <option value="false" ${!ad.enabled ? 'selected' : ''}>DESACTIVADO</option>
                                </select>
                            </div>
                            <div class="field"><label>Mín. Pilotos Party</label><input type="number" value="${ad.minPlayers}" onchange="config.gameModes.altar_defense.minPlayers = parseInt(this.value)"></div>
                            <div class="field"><label>Máx. Pilotos Party</label><input type="number" value="${ad.maxPlayers}" onchange="config.gameModes.altar_defense.maxPlayers = parseInt(this.value)"></div>
                            <div class="field"><label>Vida del Altar</label><input type="number" value="${ad.altarHp}" onchange="config.gameModes.altar_defense.altarHp = parseInt(this.value)"></div>
                            <div class="field"><label>Escudo del Altar</label><input type="number" value="${ad.altarShield}" onchange="config.gameModes.altar_defense.altarShield = parseInt(this.value)"></div>
                            
                            <div class="field"><label>Tiempo Aceptar (ms)</label><input type="number" step="1000" value="${ad.partyAcceptTimeout}" onchange="config.gameModes.altar_defense.partyAcceptTimeout = parseInt(this.value)"></div>
                            <div class="field"><label>Intervalo Oleadas (ms)</label><input type="number" step="1000" value="${ad.waveInterval}" onchange="config.gameModes.altar_defense.waveInterval = parseInt(this.value)"></div>
                            <div class="field"><label>Bloqueo de Spawn (ms)</label><input type="number" step="1000" value="${ad.spawnLockTime}" onchange="config.gameModes.altar_defense.spawnLockTime = parseInt(this.value)"></div>
                            <div class="field"><label>Duración Partida (ms)</label><input type="number" step="5000" value="${ad.matchDuration}" onchange="config.gameModes.altar_defense.matchDuration = parseInt(this.value)"></div>
                            <div></div> <!-- Celda vacía para completar la fila de 5 -->
                            
                            <div class="field" style="grid-column: span 5; display: flex; align-items: center; gap: 15px; background: rgba(255,255,255,0.02); padding: 10px 15px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.05); margin-top: 5px;">
                                <label style="margin: 0; cursor: pointer; display: flex; align-items: center; gap: 10px; font-weight: bold; color: var(--text);">
                                    <input type="checkbox" ${ad.loseLootOnDeath ? 'checked' : ''} onchange="config.gameModes.altar_defense.loseLootOnDeath = this.checked" style="width: 18px; height: 18px; cursor: pointer;">
                                    💀 Perder Loot al morir (Modo Hardcore)
                                </label>
                                <span style="font-size: 0.75rem; opacity: 0.6; flex: 1;">Si está desactivado, los jugadores mantendrán su loot temporal al morir o fallar (ideal para aprender las mecánicas).</span>
                            </div>
                        </div>
                    </div>

                    <!-- MAPAS HABILITADOS -->
                    <div class="card" style="margin:0;">
                        <h3 style="color:var(--primary); margin-bottom: 0.5rem;">🗺️ MAPAS PARA DEFENSA DEL ALTAR</h3>
                        <p style="opacity:0.6; margin-bottom:1.5rem;">Selecciona los mapas donde se habilitará esta mecánica.</p>
                        <div style="display:flex; gap:10px; margin-bottom:15px;">
                            <select id="add-ad-map-select" style="font-size:0.8rem; flex:1;">
                                <option value="" disabled selected hidden>🔍 Seleccionar mapa...</option>
                                ${Object.keys(config.mapsConfig).map(id => `<option value="${id}">${config.mapsConfig[id].name}</option>`).join('')}
                            </select>
                            <button class="btn btn-primary" style="padding:4px 15px; font-size:0.7rem;" onclick="addAltarDefenseMap()">+ AÑADIR MAPA</button>
                        </div>
                        <div style="display:flex; flex-wrap:wrap; gap:8px; max-height:140px; overflow-y:auto;">
                            ${ad.maps.map((mapId, idx) => `
                                <div style="background:rgba(255,255,255,0.05); padding:6px 12px; border-radius:20px; border:1px solid rgba(255,255,255,0.1); display:flex; align-items:center; gap:10px; font-size:0.75rem;">
                                    <span>${config.mapsConfig[mapId]?.name || 'ID '+mapId}</span>
                                    <button onclick="config.gameModes.altar_defense.maps.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                </div>

                <!-- NIVEL 2: CONFIGURACIÓN DE POSICIONAMIENTOS -->
                <div style="display:grid; grid-template-columns: repeat(4, 1fr); gap:20px;">
                    <!-- ALTAR POSITION -->
                    <div class="card" style="margin:0; border-top: 3px solid var(--success);">
                        <h4 style="color:var(--success); margin-bottom:1rem;">🏛️ POSICIÓN DEL ALTAR</h4>
                        <p style="opacity:0.6; font-size:0.75rem; margin-bottom:15px;">Coordenadas centrales del altar a defender.</p>
                        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px; margin-bottom: 10px;">
                            <div class="field"><label>Coord X</label><input type="number" id="ad-altar-x" value="${ad.altarPos.x}" onchange="config.gameModes.altar_defense.altarPos.x = parseInt(this.value); renderModes();"></div>
                            <div class="field"><label>Coord Y</label><input type="number" id="ad-altar-y" value="${ad.altarPos.y}" onchange="config.gameModes.altar_defense.altarPos.y = parseInt(this.value); renderModes();"></div>
                        </div>
                        <div style="text-align:center; font-size:0.7rem; color:var(--success); opacity:0.8;">
                            Usa el Radar de Posicionamiento para reubicarlo arrastrando su estrella o haciendo clic.
                        </div>
                    </div>

                    <!-- SPAWN POINTS (PLAYERS) -->
                    <div class="card" style="margin:0; border-top: 3px solid var(--accent);">
                        <h4 style="color:var(--accent); margin-bottom:1rem;">📍 SPAWN DE JUGADORES</h4>
                        <div style="display:flex; flex-direction:column; gap:8px; max-height:280px; overflow-y:auto; padding-right:5px;">
                            ${(ad.spawnPoints || []).map((p, idx) => `
                                <div id="card-ad-spawn-${idx}" onclick="highlightCard('ad-spawn', ${idx})" style="background:rgba(6,182,212,0.05); border:1px solid rgba(6,182,212,0.2); border-radius:8px; padding:10px; transition: all 0.3s ease; cursor:pointer;">
                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                        <input type="text" value="${p.label || 'Punto #'+(idx+1)}" onchange="config.gameModes.altar_defense.spawnPoints[${idx}].label = this.value" style="background:none; border:none; color:var(--accent); font-weight:bold; font-size:0.7rem; width:70%;">
                                        <button onclick="config.gameModes.altar_defense.spawnPoints.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px;">
                                        <div class="field"><label>X</label><input type="number" id="ad-spw-x-${idx}" value="${p.x}" onchange="config.gameModes.altar_defense.spawnPoints[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Y</label><input type="number" id="ad-spw-y-${idx}" value="${p.y}" onchange="config.gameModes.altar_defense.spawnPoints[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                    <div class="field" style="margin-top:5px;"><label>Radio Burbuja</label><input type="number" value="${p.radius || 200}" onchange="config.gameModes.altar_defense.spawnPoints[${idx}].radius = parseInt(this.value)"></div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <!-- AMENAZAS / ENEMIGOS -->
                    <div class="card" style="margin:0; border-top: 3px solid var(--danger);">
                        <h4 style="color:var(--danger); margin-bottom:1rem;">👾 SPAWNERS DE ENEMIGOS</h4>
                        <div style="display:flex; flex-direction:column; gap:10px; max-height:280px; overflow-y:auto; padding-right:5px;">
                            ${(ad.spawners || []).map((s, idx) => `
                                <div id="card-ad-spawner-${idx}" onclick="highlightCard('ad-spawner', ${idx})" style="background:rgba(255,49,49,0.05); border:1px solid rgba(255,49,49,0.2); border-radius:8px; padding:10px; overflow: visible; transition: all 0.3s ease; cursor:pointer;">
                                    <div style="display:flex; flex-direction:column; gap:8px; margin-bottom:8px; overflow: visible;">
                                        <div style="display:flex; justify-content:space-between; align-items:center;">
                                            <input type="text" value="${s.label || 'Zona '+ (idx+1)}" onchange="config.gameModes.altar_defense.spawners[${idx}].label = this.value; renderModes();" style="background:none; border:none; color:var(--danger); font-weight:bold; font-size:0.75rem; width:85%;">
                                            <button onclick="config.gameModes.altar_defense.spawners.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                        </div>
                                        <div style="overflow: visible; width: 100%;">
                                            ${renderSearchableEnemySelect(s.enemyId, (newId) => {
                                                config.gameModes.altar_defense.spawners[idx].enemyId = newId;
                                                renderModes();
                                            }, 'var(--danger)', `ad-spawn-${idx}`)}
                                        </div>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px;">
                                        <div class="field"><label>Cant.</label><input type="number" value="${s.count}" onchange="config.gameModes.altar_defense.spawners[${idx}].count = parseInt(this.value)"></div>
                                        <div class="field"><label>Radio</label><input type="number" value="${s.radius}" onchange="config.gameModes.altar_defense.spawners[${idx}].radius = parseInt(this.value)"></div>
                                        <div class="field"><label>Coord X</label><input type="number" id="ad-sp-x-${idx}" value="${s.x}" onchange="config.gameModes.altar_defense.spawners[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Coord Y</label><input type="number" id="ad-sp-y-${idx}" value="${s.y}" onchange="config.gameModes.altar_defense.spawners[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <!-- PUERTAS DE ESCAPE (PORTALS) -->
                    <div class="card" style="margin:0; border-top: 3px solid #00d2ff;">
                        <h4 style="color:#00d2ff; margin-bottom:1rem;">🚪 PUERTAS DE ESCAPE (LOBBY)</h4>
                        <div style="display:flex; flex-direction:column; gap:8px; max-height:280px; overflow-y:auto; padding-right:5px;">
                            ${(ad.exitPortals || []).map((ep, idx) => `
                                <div id="card-ad-portal-${idx}" onclick="highlightCard('ad-portal', ${idx})" style="background:rgba(0,210,255,0.05); border:1px solid rgba(0,210,255,0.2); border-radius:8px; padding:10px; transition: all 0.3s ease; cursor:pointer;">
                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                        <input type="text" value="${ep.label || 'Puerta #'+(idx+1)}" onchange="config.gameModes.altar_defense.exitPortals[${idx}].label = this.value" style="background:none; border:none; color:#00d2ff; font-weight:bold; font-size:0.7rem; width:70%;">
                                        <button onclick="config.gameModes.altar_defense.exitPortals.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px;">
                                        <div class="field"><label>Coord X</label><input type="number" id="ad-pt-x-${idx}" value="${ep.x}" onchange="config.gameModes.altar_defense.exitPortals[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Coord Y</label><input type="number" id="ad-pt-y-${idx}" value="${ep.y}" onchange="config.gameModes.altar_defense.exitPortals[${idx}].y = parseInt(this.value)"></div>
                                    </div>
                                    <div class="field" style="margin-top:5px;"><label>Radio Proximidad</label><input type="number" value="${ep.radius || 150}" onchange="config.gameModes.altar_defense.exitPortals[${idx}].radius = parseInt(this.value)"></div>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                </div>

                <!-- NIVEL 3: CONFIGURACIÓN DE OLEADAS (WAVES) -->
                <div class="card" style="margin:0; border-top: 3px solid var(--accent);">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.5rem;">
                        <h4 style="color:var(--accent); margin:0;">🌊 CONFIGURACIÓN DE OLEADAS (WAVES)</h4>
                        <button class="btn btn-primary" style="padding: 5px 20px; font-size:0.75rem;" onclick="addAltarDefenseWave()">+ AÑADIR OLEADA</button>
                    </div>
                    <div style="display:flex; flex-direction:column; gap:20px; max-height:500px; overflow-y:auto; padding-right:5px;">
                        ${ad.waves.map((w, idx) => {
                            const isCollapsed = window.collapsedWaves && window.collapsedWaves[idx];
                            return `
                            <div class="card" style="background:rgba(255,255,255,0.02); border:1px solid rgba(255,255,255,0.05); border-radius:10px; padding:15px; margin:0; position:relative; overflow: visible;">
                                <div style="display:flex; justify-content:space-between; align-items:center; cursor:pointer;" onclick="toggleWaveCollapse(${idx})">
                                    <div style="display:flex; align-items:center; gap:10px; width:80%;">
                                        <span style="font-size:0.8rem; color:var(--text-dim);">${isCollapsed ? '▶' : '▼'}</span>
                                        <input type="text" value="${w.name || 'Oleada ' + (idx + 1)}" onchange="config.gameModes.altar_defense.waves[${idx}].name = this.value; event.stopPropagation();" onclick="event.stopPropagation();" style="background:none; border:none; color:var(--primary); font-weight:bold; font-size:0.95rem; width:80%;">
                                    </div>
                                    <div style="display:flex; align-items:center; gap:10px;">
                                        <button onclick="config.gameModes.altar_defense.waves.splice(${idx},1); renderModes(); event.stopPropagation();" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:1.1rem;">✕</button>
                                    </div>
                                </div>
                                
                                <div style="display: ${isCollapsed ? 'none' : 'flex'}; flex-direction:column; gap:15px; margin-top:15px; overflow: visible;">
                                    <div style="display:grid; grid-template-columns: 1fr; gap:10px;">
                                        <div class="field">
                                            <label>Delay de Inicio de Oleada (ms)</label>
                                            <input type="number" step="1000" value="${w.delayMs || 5000}" onchange="config.gameModes.altar_defense.waves[${idx}].delayMs = parseInt(this.value)">
                                        </div>
                                    </div>
                                    
                                    <!-- FASES DENTRO DE LA OLEADA -->
                                    <div style="border-top: 1px solid rgba(255,255,255,0.05); padding-top:10px;">
                                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
                                            <h5 style="color:var(--text); margin:0; font-size:0.85rem;">Fases de la Oleada</h5>
                                            <button class="btn btn-secondary" style="padding: 2px 10px; font-size:0.65rem;" onclick="addAltarDefensePhase(${idx})">+ AÑADIR FASE</button>
                                        </div>
                                        <div style="display:flex; flex-direction:column; gap:12px;">
                                            ${(w.phases || []).map((ph, phIdx) => {
                                                if (!ph.spawnerDistribution) {
                                                    ph.spawnerDistribution = {};
                                                }
                                                // Calcular cantidad total sumando la distribución
                                                let totalCount = 0;
                                                for (let key in ph.spawnerDistribution) {
                                                    totalCount += ph.spawnerDistribution[key] || 0;
                                                }
                                                ph.count = totalCount;

                                                return `
                                                <div style="background:rgba(255,255,255,0.01); border:1px solid rgba(255,255,255,0.03); border-radius:8px; padding:12px; position:relative; overflow: visible;">
                                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                                        <input type="text" value="${ph.name || 'Fase ' + (phIdx + 1)}" onchange="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].name = this.value" style="background:none; border:none; color:var(--accent); font-weight:bold; font-size:0.8rem; width:70%;">
                                                        <button onclick="config.gameModes.altar_defense.waves[${idx}].phases.splice(${phIdx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:0.9rem;">✕</button>
                                                    </div>
                                                    
                                                    <div style="display:flex; flex-direction:column; gap:10px; overflow: visible;">
                                                        <div style="overflow: visible; width: 100%;">
                                                            <label style="font-size:0.7rem; color:var(--text-dim); display:block; margin-bottom:4px;">Enemigo a Spawnear</label>
                                                            ${renderSearchableEnemySelect(ph.enemyId || '', (newId) => {
                                                                config.gameModes.altar_defense.waves[idx].phases[phIdx].enemyId = newId;
                                                            }, 'var(--accent)', `ad-wave-${idx}-phase-${phIdx}`)}
                                                        </div>
                                                        
                                                        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
                                                            <div class="field">
                                                                <label>Foco Objetivo</label>
                                                                <select onchange="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].focusTarget = this.value">
                                                                    <option value="altar" ${ph.focusTarget === 'altar' ? 'selected' : ''}>Altar (Puro)</option>
                                                                    <option value="altar_aggro" ${ph.focusTarget === 'altar_aggro' ? 'selected' : ''}>Altar (con Aggro)</option>
                                                                    <option value="players" ${ph.focusTarget === 'players' ? 'selected' : ''}>Jugadores</option>
                                                                </select>
                                                            </div>
                                                            <div class="field">
                                                                <label>Tipo Spawn</label>
                                                                <select onchange="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].spawnType = this.value; renderModes();">
                                                                    <option value="together" ${ph.spawnType === 'together' ? 'selected' : ''}>Todos juntos</option>
                                                                    <option value="staggered" ${ph.spawnType === 'staggered' ? 'selected' : ''}>Escalonados</option>
                                                                </select>
                                                            </div>
                                                        </div>

                                                        <div style="display:grid; grid-template-columns: ${ph.spawnType === 'staggered' ? '1fr 1fr' : '1fr'}; gap:10px;">
                                                            <div class="field">
                                                                <label>Delay Inicio Fase (ms)</label>
                                                                <input type="number" step="100" value="${ph.startDelayMs || 0}" onchange="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].startDelayMs = parseInt(this.value)">
                                                            </div>
                                                            ${ph.spawnType === 'staggered' ? `
                                                            <div class="field">
                                                                <label>Delay Escalonamiento (ms)</label>
                                                                <input type="number" step="100" value="${ph.staggerDelayMs || 500}" onchange="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].staggerDelayMs = parseInt(this.value)">
                                                            </div>
                                                            ` : ''}
                                                        </div>

                                                        <!-- DISTRIBUCIÓN DE SPAWNERS -->
                                                        <div style="background:rgba(0,0,0,0.2); padding:8px; border-radius:6px; border:1px solid rgba(255,255,255,0.03);">
                                                            <label style="font-size:0.7rem; color:var(--accent); font-weight:bold; display:block; margin-bottom:6px;">Distribución de Enemigos por Spawner</label>
                                                            <div style="display:flex; flex-direction:column; gap:6px;">
                                                                <!-- Random Pool -->
                                                                <div style="display:flex; justify-content:space-between; align-items:center;">
                                                                    <span style="font-size:0.7rem; opacity:0.8;">Random (Cualquier zona)</span>
                                                                    <input type="number" min="0" value="${ph.spawnerDistribution.random || 0}" 
                                                                           oninput="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].spawnerDistribution.random = parseInt(this.value) || 0; updateAdPhaseTotal(${idx}, ${phIdx});"
                                                                           style="width:60px; text-align:center; font-size:0.75rem; background:rgba(0,0,0,0.5); border:1px solid #333; color:white; border-radius:4px; padding:2px;">
                                                                </div>
                                                                <!-- Spawners específicos -->
                                                                ${ad.spawners.map((sp, spIdx) => {
                                                                    const val = ph.spawnerDistribution[spIdx] || 0;
                                                                    return `
                                                                    <div style="display:flex; justify-content:space-between; align-items:center;">
                                                                        <span style="font-size:0.7rem; opacity:0.8; max-width:180px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">[${spIdx}] ${sp.label || 'Zona ' + (spIdx + 1)}</span>
                                                                        <input type="number" min="0" value="${val}" 
                                                                               oninput="config.gameModes.altar_defense.waves[${idx}].phases[${phIdx}].spawnerDistribution[${spIdx}] = parseInt(this.value) || 0; updateAdPhaseTotal(${idx}, ${phIdx});"
                                                                               style="width:60px; text-align:center; font-size:0.75rem; background:rgba(0,0,0,0.5); border:1px solid #333; color:white; border-radius:4px; padding:2px;">
                                                                    </div>
                                                                    `;
                                                                }).join('')}
                                                            </div>
                                                            <div style="margin-top:8px; border-top:1px solid rgba(255,255,255,0.05); padding-top:4px; display:flex; justify-content:space-between; align-items:center;">
                                                                <span style="font-size:0.7rem; font-weight:bold; color:var(--text);">Total Enemigos en Fase:</span>
                                                                <span id="ad-phase-total-${idx}-${phIdx}" style="font-size:0.75rem; font-weight:bold; color:var(--success);">${totalCount}</span>
                                                            </div>
                                                        </div>

                                                    </div>
                                                </div>
                                                `;
                                            }).join('')}
                                        </div>
                                    </div>
                                </div>
                            </div>
                            `;
                        }).join('')}
                    </div>
                </div>

                <!-- NIVEL 4: RADAR GLOBAL -->
                <div class="card" style="margin:0;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.5rem;">
                        <div style="display:flex; align-items:center; gap:20px;">
                            <h4 style="color:var(--primary); margin:0;">🛰️ RADAR DE POSICIONAMIENTO GLOBAL (ALTAR)</h4>
                            <div style="display:flex; align-items:center; gap:10px; background:rgba(255,255,255,0.03); padding:4px 12px; border-radius:8px; border:1px solid rgba(255,255,255,0.05);">
                                <label style="font-size:0.65rem; color:var(--accent); font-weight:bold; letter-spacing:1px; margin:0;">DIMENSIONES MUNDO (PX):</label>
                                <div style="display:flex; align-items:center; gap:5px;">
                                    <span style="font-size:0.65rem; opacity:0.6;">W:</span>
                                    <input type="number" value="${ad.width || 10000}" 
                                           onchange="config.gameModes.altar_defense.width = parseInt(this.value); renderModes();" 
                                           style="width:70px; background:rgba(0,0,0,0.3); border:1px solid #333; color:white; font-size:0.75rem; text-align:center; padding:2px; border-radius:4px; font-weight:bold; font-family:'JetBrains Mono',monospace;">
                                </div>
                                <div style="display:flex; align-items:center; gap:5px; margin-left:10px;">
                                    <span style="font-size:0.65rem; opacity:0.6;">H:</span>
                                    <input type="number" value="${ad.height || 10000}" 
                                           onchange="config.gameModes.altar_defense.height = parseInt(this.value); renderModes();" 
                                           style="width:70px; background:rgba(0,0,0,0.3); border:1px solid #333; color:white; font-size:0.75rem; text-align:center; padding:2px; border-radius:4px; font-weight:bold; font-family:'JetBrains Mono',monospace;">
                                </div>
                            </div>
                        </div>
                        <div style="display:flex; gap:10px;">
                            <button id="btn-radar-ad-altar" class="btn ${radarMode === 'ad-altar' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('ad-altar')">MODO ALTAR</button>
                            <button id="btn-radar-ad-spawn" class="btn ${radarMode === 'ad-spawn' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('ad-spawn')">MODO SPAWN</button>
                            <button id="btn-radar-ad-spawner" class="btn ${radarMode === 'ad-spawner' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('ad-spawner')">MODO AMENAZA</button>
                            <button id="btn-radar-ad-portal" class="btn ${radarMode === 'ad-portal' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('ad-portal')">MODO PUERTA</button>
                        </div>
                    </div>
                    
                    <div style="display:flex; flex-wrap:wrap; justify-content:center; gap:30px; width:100%;">
                        <div id="radar-container" style="position:relative; width:600px; height:600px; background:#000; border:2px solid var(--primary); border-radius:10px; overflow:hidden; cursor:crosshair; box-shadow: 0 0 20px rgba(0, 210, 255, 0.15);">
                            <canvas id="radar-canvas" width="600" height="600" style="width: 100%; height: 100%; display: block;"></canvas>
                        </div>
                        
                        <div style="flex:1; min-width:350px; display:flex; flex-direction:column; gap:15px; background:rgba(255,255,255,0.02); padding:25px; border-radius:10px; overflow: visible;">
                            <label style="color:var(--accent); font-size:0.85rem; margin-bottom:15px; display:block; border-bottom:1px solid rgba(255,255,255,0.1); padding-bottom:10px; font-weight:bold; overflow: visible;">🛠️ HERRAMIENTA DE DESPLIEGUE</label>
                            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:15px;">
                                <div class="field"><label>Coord X</label><input type="number" id="radar-x" value="0"></div>
                                <div class="field"><label>Coord Y</label><input type="number" id="radar-y" value="0"></div>
                            </div>
                            <div id="radar-ad-altar-opts" style="display:${radarMode === 'ad-altar' ? 'block' : 'none'}">
                                <p style="font-size:0.75rem; color:#aaa;">Haz clic en el mapa y presiona "Fijar" para mover la base del Altar.</p>
                            </div>
                            <div id="radar-ad-spawn-opts" style="display:${radarMode === 'ad-spawn' ? 'block' : 'none'}">
                                <div class="field" style="margin-top:10px;"><label>Nombre</label><input type="text" id="radar-ad-spawn-label" value="Punto Spawn"></div>
                                <div class="field" style="margin-top:5px;"><label>Radio Burbuja</label><input type="number" id="radar-ad-spawn-radius" value="200"></div>
                            </div>
                            <div id="radar-ad-spawner-opts" style="display:${radarMode === 'ad-spawner' ? 'block' : 'none'}; overflow: visible;">
                                <div class="field" style="margin-top:10px;"><label>Nombre Zona</label><input type="text" id="radar-ad-spawner-label" value="Zona de Invasión"></div>
                                <div class="field" style="margin-top:10px; overflow: visible;">
                                    <label>Enemigo</label>
                                    <input type="hidden" id="ad-spawner-enemy-select" value="${ad.spawners[0]?.enemyId || '1'}">
                                    ${renderSearchableEnemySelect(ad.spawners[0]?.enemyId || '1', (newId) => {
                                        document.getElementById('ad-spawner-enemy-select').value = newId;
                                    }, 'var(--accent)', 'radar-ad-spawn-select')}
                                </div>
                                <div class="field" style="margin-top:10px;"><label>Cantidad</label><input type="number" id="radar-ad-count" value="10"></div>
                                <div class="field" style="margin-top:10px;"><label>Radio</label><input type="number" id="radar-ad-radius" value="500"></div>
                            </div>
                            <div id="radar-ad-portal-opts" style="display:${radarMode === 'ad-portal' ? 'block' : 'none'}">
                                <div class="field" style="margin-top:10px;"><label>Nombre Portal</label><input type="text" id="radar-ad-portal-label" value="Puerta de Escape"></div>
                                <div class="field" style="margin-top:5px;"><label>Radio Proximidad</label><input type="number" id="radar-ad-portal-radius" value="150"></div>
                            </div>
                            <button class="btn btn-primary" style="width:100%; margin-top:20px; padding:15px; font-weight:bold;" onclick="addFromRadar()">FIJAR EN EL MAPA</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        setTimeout(initRadar, 100);
    } else if (currentModeTab === 'arenas') {
        if (!config.gameModes.arenas) {
            config.gameModes.arenas = { enabled: true, maps: [], minPlayers: 2 };
        }
        if (!config.gameModes.arenas.maps) config.gameModes.arenas.maps = [];
        if (!config.gameModes.arenas.mapConfigs) config.gameModes.arenas.mapConfigs = {};

        // Sincronizar mapa activo si no está fijado
        if (!activeArenaMapId && config.gameModes.arenas.maps.length > 0) {
            activeArenaMapId = config.gameModes.arenas.maps[0];
        }
        const mapCfg = activeArenaMapId ? config.gameModes.arenas.mapConfigs[activeArenaMapId] : null;

        let leftColPillarsHtml = '';
        let pillarDetailHtml = '';
        let leftColSpawnsHtml = '';
        let spawnDetailHtml = '';

        if (mapCfg) {
            if (!mapCfg.pillars) mapCfg.pillars = [];
            if (!mapCfg.spawns) mapCfg.spawns = [];
            
            leftColPillarsHtml = mapCfg.pillars.map((p, idx) => `
                <div onclick="selectArenaPillar(${idx})" style="background:${activeArenaPillarIndex === idx ? 'rgba(6,182,212,0.15)' : 'rgba(255,255,255,0.02)'}; border:1px solid ${activeArenaPillarIndex === idx ? 'var(--accent)' : 'rgba(255,255,255,0.06)'}; border-radius:8px; padding:10px; cursor:pointer; margin-bottom:8px; transition:all 0.2s;">
                    <div style="display:flex; justify-content:space-between; align-items:center;">
                        <span style="color:${p.team === 'red' ? '#ff3131' : '#31b6ff'}; font-weight:bold; font-size:0.8rem;">${p.name}</span>
                        <button onclick="event.stopPropagation(); removeArenaPillar(${idx});" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:0.9rem;">✕</button>
                    </div>
                    <div style="font-size:0.7rem; opacity:0.6; margin-top:4px;">
                        Pos: (${p.x}, ${p.y}) | Rango: ${p.range}
                    </div>
                </div>
            `).join('');

            leftColSpawnsHtml = mapCfg.spawns.map((s, idx) => `
                <div onclick="selectArenaSpawn(${idx})" style="background:${activeArenaSpawnIndex === idx ? 'rgba(236,72,153,0.15)' : 'rgba(255,255,255,0.02)'}; border:1px solid ${activeArenaSpawnIndex === idx ? 'var(--pink)' : 'rgba(255,255,255,0.06)'}; border-radius:8px; padding:10px; cursor:pointer; margin-bottom:8px; transition:all 0.2s;">
                    <div style="display:flex; justify-content:space-between; align-items:center;">
                        <span style="color:${s.team === 'red' ? '#ff3131' : '#31b6ff'}; font-weight:bold; font-size:0.8rem;">${s.name || 'Spawn ' + (idx + 1)}</span>
                        <button onclick="event.stopPropagation(); removeArenaSpawn(${idx});" style="background:none; border:none; color:var(--danger); cursor:pointer; font-size:0.9rem;">✕</button>
                    </div>
                    <div style="font-size:0.7rem; opacity:0.6; margin-top:4px;">
                        Pos: (${s.x}, ${s.y}) | Radio: ${s.radius}px
                    </div>
                </div>
            `).join('');

            if (activeArenaPillarIndex !== null && mapCfg.pillars[activeArenaPillarIndex]) {
                const pil = mapCfg.pillars[activeArenaPillarIndex];
                pillarDetailHtml = `
                    <div class="card" style="margin:0; border-top:3px solid var(--accent);">
                        <h4 style="color:var(--accent); margin-bottom:1rem;">🗼 DETALLES DEL PILAR</h4>
                        <div class="form-grid" style="grid-template-columns:1fr; gap:10px;">
                            <div class="field"><label>Nombre del Pilar</label>
                                <input type="text" value="${pil.name}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].name = this.value; renderModes();">
                            </div>
                            <div class="field"><label>Equipo Propietario</label>
                                <select onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].team = this.value; renderModes();">
                                    <option value="red" ${pil.team === 'red' ? 'selected' : ''}>Rojo (Red)</option>
                                    <option value="blue" ${pil.team === 'blue' ? 'selected' : ''}>Azul (Blue)</option>
                                </select>
                            </div>
                            <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px;">
                                <div class="field"><label>Coord X</label><input type="number" id="pillar-x" value="${pil.x}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].x = parseInt(this.value); renderModes();"></div>
                                <div class="field"><label>Coord Y</label><input type="number" id="pillar-y" value="${pil.y}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].y = parseInt(this.value); renderModes();"></div>
                            </div>
                            <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px;">
                                <div class="field"><label>Daño por Disparo</label><input type="number" value="${pil.damage}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].damage = parseInt(this.value); renderModes();"></div>
                                <div class="field"><label>Rango de Ataque</label><input type="number" value="${pil.range}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].range = parseInt(this.value); renderModes();"></div>
                            </div>
                            <div class="field"><label>Tipo de Munición</label>
                                <select onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].ammoType = this.value; renderModes();">
                                    <option value="laser" ${pil.ammoType === 'laser' ? 'selected' : ''}>🔦 Láser</option>
                                    <option value="missile" ${pil.ammoType === 'missile' ? 'selected' : ''}>🚀 Misil</option>
                                    <option value="mine" ${pil.ammoType === 'mine' ? 'selected' : ''}>💣 Mina</option>
                                </select>
                            </div>
                            <div class="field"><label>Tipo de Ataque</label>
                                <select onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillars[activeArenaPillarIndex].attackType = this.value; renderModes();">
                                    <option value="fast" ${pil.attackType === 'fast' ? 'selected' : ''}>⚡ Rápido (1s CD)</option>
                                    <option value="heavy" ${pil.attackType === 'heavy' ? 'selected' : ''}>💥 Pesado (2s CD)</option>
                                    <option value="area" ${pil.attackType === 'area' ? 'selected' : ''}>🌀 Área (1.5s CD)</option>
                                </select>
                            </div>
                        </div>
                    </div>
                `;
            } else {
                pillarDetailHtml = `
                    <div class="card" style="margin:0; opacity:0.6; display:flex; align-items:center; justify-content:center; height:100%; border:1px dashed rgba(255,255,255,0.1);">
                        <p style="text-align:center; font-style:italic; font-size:0.85rem;">Selecciona un pilar de la lista o el Canvas para editar sus propiedades.</p>
                    </div>
                `;
            }

            if (activeArenaSpawnIndex !== null && mapCfg.spawns[activeArenaSpawnIndex]) {
                const sp = mapCfg.spawns[activeArenaSpawnIndex];
                spawnDetailHtml = `
                    <div class="card" style="margin:0; border-top:3px solid var(--pink);">
                        <h4 style="color:var(--pink); margin-bottom:1rem;">📍 DETALLES DEL SPAWN</h4>
                        <div class="form-grid" style="grid-template-columns:1fr; gap:10px;">
                            <div class="field"><label>Nombre del Spawn</label>
                                <input type="text" value="${sp.name || ''}" placeholder="Ej: Spawn Rojo 1" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].name = this.value; renderModes();">
                            </div>
                            <div class="field"><label>Equipo Destinatario</label>
                                <select onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].team = this.value; renderModes();">
                                    <option value="red" ${sp.team === 'red' ? 'selected' : ''}>Rojo (Red)</option>
                                    <option value="blue" ${sp.team === 'blue' ? 'selected' : ''}>Azul (Blue)</option>
                                </select>
                            </div>
                            <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px;">
                                <div class="field"><label>Coord X</label><input type="number" id="spawn-x" value="${sp.x}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].x = parseInt(this.value); renderModes();"></div>
                                <div class="field"><label>Coord Y</label><input type="number" id="spawn-y" value="${sp.y}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].y = parseInt(this.value); renderModes();"></div>
                            </div>
                            <div class="field">
                                <label>Radio en Píxeles (Burbuja)</label>
                                <input type="number" value="${sp.radius || 200}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].spawns[activeArenaSpawnIndex].radius = parseInt(this.value); renderModes();">
                            </div>
                        </div>
                    </div>
                `;
            } else {
                spawnDetailHtml = `
                    <div class="card" style="margin:0; opacity:0.6; display:flex; align-items:center; justify-content:center; height:100%; border:1px dashed rgba(255,255,255,0.1);">
                        <p style="text-align:center; font-style:italic; font-size:0.85rem;">Selecciona un spawn de la lista o el Canvas para editar sus propiedades.</p>
                    </div>
                `;
            }

            content.innerHTML = `
            <!-- PARTE 1: REGLAS Y MAPAS -->
            <div style="grid-column: 1 / -1; display:grid; grid-template-columns: 1.2fr 0.8fr; gap:20px;">
                <div class="card" style="margin:0;">
                    <h3 style="color:#ff3131; margin-bottom: 0.5rem;">⚔️ MODO ARENAS (PVP)</h3>
                    <p style="opacity:0.7; margin-bottom:1.5rem;">Configura el emparejamiento básico y tiempos del modo arenas.</p>
                    <div class="form-grid" style="grid-template-columns: repeat(4, 1fr); gap:10px;">
                        <div class="field">
                            <label>Estado del Modo</label>
                            <select onchange="config.gameModes.arenas.enabled = this.value === 'true'">
                                <option value="true" ${config.gameModes.arenas.enabled ? 'selected' : ''}>Activo</option>
                                <option value="false" ${!config.gameModes.arenas.enabled ? 'selected' : ''}>Inactivo</option>
                            </select>
                        </div>
                        <div class="field">
                            <label>Pilotos Mínimos</label>
                            <input type="number" value="${config.gameModes.arenas.minPlayers || 2}" onchange="config.gameModes.arenas.minPlayers = parseInt(this.value)">
                        </div>
                        <div class="field">
                            <label>Pilotos Máximos</label>
                            <input type="number" value="${config.gameModes.arenas.maxPlayers || 6}" onchange="config.gameModes.arenas.maxPlayers = parseInt(this.value)">
                        </div>
                        <div class="field">
                            <label>Selección Respawn</label>
                            <select onchange="config.gameModes.arenas.spawnMode = this.value">
                                <option value="random" ${config.gameModes.arenas.spawnMode === 'random' ? 'selected' : ''}>🎲 Aleatorio (Random)</option>
                                <option value="closest" ${config.gameModes.arenas.spawnMode === 'closest' ? 'selected' : ''}>📍 Más Cercano (Closest)</option>
                                <option value="first" ${config.gameModes.arenas.spawnMode === 'first' ? 'selected' : ''}>1️⃣ Primer Spawn (First)</option>
                            </select>
                        </div>
                        <div class="field">
                            <label>Duración Partida (ms)</label>
                            <input type="number" step="1000" value="${config.gameModes.arenas.matchDuration || 600000}" onchange="config.gameModes.arenas.matchDuration = parseInt(this.value)">
                        </div>
                        <div class="field">
                            <label>Bloqueo Spawn (ms)</label>
                            <input type="number" step="1000" value="${config.gameModes.arenas.spawnLockTime || 10000}" onchange="config.gameModes.arenas.spawnLockTime = parseInt(this.value)">
                        </div>
                        <div class="field">
                            <label>Invul. al Revivir (ms)</label>
                            <input type="number" step="500" value="${config.gameModes.arenas.respawnInvulnerabilityMs || 3000}" onchange="config.gameModes.arenas.respawnInvulnerabilityMs = parseInt(this.value)">
                        </div>
                    </div>
                </div>

                <div class="card" style="margin:0;">
                    <h3 style="color:var(--primary); margin-bottom: 0.5rem;">🏟️ MAPAS DE ARENAS</h3>
                    <p style="opacity:0.6; margin-bottom:1.5rem;">Selecciona y añade mapas PvP competitivos.</p>
                    <div style="display:flex; gap:10px; margin-bottom:15px;">
                        <select id="arena-map-select-add" style="font-size:0.8rem; flex:1;">
                            <option value="" disabled selected hidden>🔍 Seleccionar mapa...</option>
                            ${Object.keys(config.mapsConfig).map(id => `<option value="${id}">${config.mapsConfig[id].name} (ID ${id})</option>`).join('')}
                        </select>
                        <button class="btn btn-primary" style="padding:4px 15px; font-size:0.7rem;" onclick="addArenaMap(document.getElementById('arena-map-select-add').value)">+ AÑADIR MAPA</button>
                    </div>
                    
                    <div style="display:flex; gap:10px; align-items:center;">
                        <label style="font-weight:bold; font-size:0.8rem;">Mapa Activo para Configurar:</label>
                        <select onchange="selectArenaMap(this.value)" style="font-size:0.8rem; flex:1; max-width:200px;">
                            <option value="">Ninguno</option>
                            ${config.gameModes.arenas.maps.map(id => `<option value="${id}" ${activeArenaMapId === id ? 'selected' : ''}>${config.mapsConfig[id]?.name || 'ID '+id}</option>`).join('')}
                        </select>
                    </div>
                </div>
            </div>

            <!-- PARTE 2: CONFIGURACIÓN ESPECÍFICA DEL MAPA -->
            ${mapCfg ? `
                <div style="grid-column: 1 / -1; display:grid; grid-template-columns: 1fr 1.2fr; gap:20px; margin-top:10px;">
                    <div class="card" style="margin:0; max-height: 520px; overflow-y: auto;">
                        <h4 style="color:#ff3131; margin-bottom:1rem;">📐 DIMENSIONES (MAPA ${activeArenaMapId})</h4>
                        <div class="form-grid" style="grid-template-columns:1fr 1fr; gap:10px; margin-bottom:15px;">
                            <div class="field"><label>Ancho (W px)</label><input type="number" value="${mapCfg.width || 10000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].width = parseInt(this.value); renderModes();"></div>
                            <div class="field"><label>Alto (H px)</label><input type="number" value="${mapCfg.height || 10000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].height = parseInt(this.value); renderModes();"></div>
                        </div>

                        <!-- NEXO ROJO -->
                        <h5 style="color:#ff3131; border-bottom:1px solid rgba(255,49,49,0.2); padding-bottom:4px; margin-bottom:10px;">🔴 NEXO ROJO (RED)</h5>
                        <div class="form-grid" style="grid-template-columns:1fr 1fr; gap:10px; margin-bottom:15px;">
                            <div class="field"><label>Vida Máx</label><input type="number" value="${mapCfg.nexusRed?.hp || 10000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusRed.hp = parseInt(this.value)"></div>
                            <div class="field"><label>Escudo Máx</label><input type="number" value="${mapCfg.nexusRed?.shield || 5000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusRed.shield = parseInt(this.value)"></div>
                            <div class="field"><label>Posición X</label><input type="number" id="nexus-red-x" value="${mapCfg.nexusRed?.x || 2000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusRed.x = parseInt(this.value); renderModes();"></div>
                            <div class="field"><label>Posición Y</label><input type="number" id="nexus-red-y" value="${mapCfg.nexusRed?.y || 5000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusRed.y = parseInt(this.value); renderModes();"></div>
                        </div>

                        <!-- NEXO AZUL -->
                        <h5 style="color:#31b6ff; border-bottom:1px solid rgba(49,182,255,0.2); padding-bottom:4px; margin-bottom:10px; margin-top:10px;">🔵 NEXO AZUL (BLUE)</h5>
                        <div class="form-grid" style="grid-template-columns:1fr 1fr; gap:10px; margin-bottom:15px;">
                            <div class="field"><label>Vida Máx</label><input type="number" value="${mapCfg.nexusBlue?.hp || 10000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusBlue.hp = parseInt(this.value)"></div>
                            <div class="field"><label>Escudo Máx</label><input type="number" value="${mapCfg.nexusBlue?.shield || 5000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusBlue.shield = parseInt(this.value)"></div>
                            <div class="field"><label>Posición X</label><input type="number" id="nexus-blue-x" value="${mapCfg.nexusBlue?.x || 8000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusBlue.x = parseInt(this.value); renderModes();"></div>
                            <div class="field"><label>Posición Y</label><input type="number" id="nexus-blue-y" value="${mapCfg.nexusBlue?.y || 5000}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusBlue.y = parseInt(this.value); renderModes();"></div>
                        </div>

                        <!-- CONFIGURACIÓN DE RECURSOS 3D -->
                        <h5 style="color:var(--accent); border-bottom:1px solid rgba(6,182,212,0.2); padding-bottom:4px; margin-bottom:10px; margin-top:15px;">📦 ASSETS 3D AUTORITATIVOS</h5>
                        <div class="form-grid" style="grid-template-columns:1fr; gap:10px;">
                            <div class="field"><label>Ruta Asset Nexos (.glb)</label>
                                <input type="text" value="${mapCfg.nexusAsset || 'E:\\\\Descon\\\\descon\\\\assets\\\\Arenas PVP\\\\3D\\\\Nexos\\\\Nexo1\\\\Nexo1.glb'}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].nexusAsset = this.value">
                            </div>
                            <div class="field"><label>Ruta Asset Pilares/Torres (.glb)</label>
                                <input type="text" value="${mapCfg.pillarAsset || 'E:\\\\Descon\\\\descon\\\\assets\\\\Arenas PVP\\\\3D\\\\Torres\\\\Torre1\\\\Torre1.glb'}" onchange="config.gameModes.arenas.mapConfigs[activeArenaMapId].pillarAsset = this.value">
                            </div>
                        </div>
                    </div>

                    <div class="card" style="margin:0; display:flex; flex-direction:column; justify-content:center; align-items:center;">
                        <h4 style="color:var(--primary); margin-bottom:1rem; align-self:flex-start;">🗺️ RADAR INTERACTIVO DE LA ARENA</h4>
                        <div id="arena-radar-container" style="position:relative; width:100%; max-width:480px; height:330px; background:#000; border:2px solid var(--primary); border-radius:10px; overflow:hidden; cursor:crosshair; box-shadow: 0 0 20px rgba(0, 210, 255, 0.15);">
                            <canvas id="arena-radar-canvas" style="width: 100%; height: 100%; display: block;"></canvas>
                        </div>
                        <div style="display:flex; gap:15px; margin-top:10px; font-size:0.75rem;">
                            <span>🔴 Nexo Rojo</span>
                            <span>🔵 Nexo Azul</span>
                            <span>⚪ Torres</span>
                            <span>🛡️ Spawns</span>
                        </div>
                    </div>
                </div>

                <!-- SECCIÓN DE CONFIGURACIÓN DE PILARES DE DEFENSA -->
                <div style="grid-column: 1 / -1; display:grid; grid-template-columns: 1fr 1.2fr 1fr; gap:20px; margin-top:20px; border-top:1px solid rgba(255,255,255,0.05); padding-top:20px;">
                    <!-- LISTADO DE PILARES -->
                    <div class="card" style="margin:0;">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                            <h4 style="color:var(--primary); margin:0;">🗼 PILARES DE DEFENSA</h4>
                            <button class="btn btn-primary" style="padding:4px 10px; font-size:0.65rem;" onclick="addArenaPillar()">+ AÑADIR PILAR</button>
                        </div>
                        <div style="max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${leftColPillarsHtml || '<p style="font-style:italic; font-size:0.8rem; opacity:0.6;">No hay pilares creados aún.</p>'}
                        </div>
                    </div>

                    <!-- EXPLICACIÓN RADAR -->
                    <div class="card" style="margin:0; display:flex; flex-direction:column; justify-content:center; align-items:center;">
                        <div style="font-size:0.8rem; text-align:center; padding:10px;">
                            <p style="font-weight:bold; color:var(--accent); font-size:0.95rem; margin-bottom:10px;">💡 CÓMO USAR EL RADAR DE ARENAS</p>
                            <p style="opacity:0.8; margin-bottom:5px;">1. **Arrastra** los Nexos Rojo y Azul para ubicarlos en el plano 2D.</p>
                            <p style="opacity:0.8; margin-bottom:5px;">2. **Añade** pilares y spawns, y **arrástralos** a su posición ideal en el Canvas.</p>
                            <p style="opacity:0.8; margin-bottom:5px;">3. Selecciona cualquier pilar o spawn para editar sus propiedades avanzadas.</p>
                        </div>
                    </div>

                    <!-- EDICIÓN DE PILAR DETALLE -->
                    <div style="display:flex; flex-direction:column;">
                        ${pillarDetailHtml}
                    </div>
                </div>

                <!-- SECCIÓN DE CONFIGURACIÓN DE PUNTOS DE RESPAWN -->
                <div style="grid-column: 1 / -1; display:grid; grid-template-columns: 1fr 1.2fr 1fr; gap:20px; margin-top:20px; border-top:1px solid rgba(255,255,255,0.05); padding-top:20px;">
                    <!-- LISTADO DE SPAWNS -->
                    <div class="card" style="margin:0;">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                            <h4 style="color:var(--pink); margin:0;">📍 PUNTOS DE RESPAWN</h4>
                            <button class="btn btn-primary" style="padding:4px 10px; font-size:0.65rem; background:var(--pink); border-color:var(--pink);" onclick="addArenaSpawn()">+ AÑADIR SPAWN</button>
                        </div>
                        <div style="max-height:300px; overflow-y:auto; padding-right:5px;">
                            ${leftColSpawnsHtml || '<p style="font-style:italic; font-size:0.8rem; opacity:0.6;">No hay spawns creados aún.</p>'}
                        </div>
                    </div>

                    <div class="card" style="margin:0; opacity:0.4; display:flex; align-items:center; justify-content:center; height:100%; border:1px dashed rgba(255,255,255,0.1);">
                        <p style="text-align:center; font-style:italic; font-size:0.85rem;">Puedes crear múltiples zonas de reaparición para cada facción.</p>
                    </div>

                    <!-- EDICIÓN DE SPAWN DETALLE -->
                    <div style="display:flex; flex-direction:column;">
                        ${spawnDetailHtml}
                    </div>
                </div>
            ` : `
                <div class="card" style="grid-column: span 2; margin-top:10px; text-align:center; padding:40px; border:1px dashed rgba(255,255,255,0.1);">
                    <p style="font-style:italic; opacity:0.7;">Por favor, añade o selecciona un mapa de arena de la lista superior para comenzar a configurar.</p>
                </div>
            `}
        `;

        if (mapCfg) {
            setTimeout(initArenaRadar, 100);
        }
    }
}
}

function renderLootConfig() {
    updateLootSidebar();
    if (!config || !config.lootConfig) return;
    
    const rangeInput = document.getElementById('loot-interact-range');
    const expInput = document.getElementById('loot-expiration-ms');
    const authCheck = document.getElementById('loot-server-auth');
    const pvpCheck = document.getElementById('loot-pvp-drop');
    
    if (rangeInput) rangeInput.value = config.lootConfig.interactRange || 400;
    if (expInput) expInput.value = config.lootConfig.expirationMs || 300000;
    if (authCheck) authCheck.checked = config.lootConfig.serverAuthoritative !== false;
    if (pvpCheck) pvpCheck.checked = !!config.lootConfig.pvpDropEnabled;

    // Resumen visual de tablas de botín por enemigo
    const summaryGrid = document.getElementById('loot-summary-grid');
    if (!summaryGrid) return;
    summaryGrid.innerHTML = '';

    if (!config.enemyModels) return;

    const sortedIds = Object.keys(config.enemyModels).sort((a, b) => parseInt(a) - parseInt(b));
    let totalEnemiesWithDrops = 0;

    sortedIds.forEach(enemyId => {
        const en = config.enemyModels[enemyId];
        if (!en) return;

        const dropCount = (en.lootDrops && en.lootDrops.length) || 0;
        const isBoss = parseInt(enemyId) >= 100;
        const accentColor = isBoss ? 'var(--accent)' : 'var(--success)';
        const typeLabel = isBoss ? '💀 BOSS' : '👾 REGULAR';

        if (dropCount > 0) totalEnemiesWithDrops++;

        const card = document.createElement('div');
        card.style.cssText = `
            background: rgba(255,255,255,0.02); 
            border: 1px solid rgba(255,255,255,0.06); 
            border-radius: 10px; 
            padding: 1rem 1.2rem; 
            cursor: pointer; 
            transition: all 0.25s;
            display: flex;
            justify-content: space-between;
            align-items: center;
        `;
        card.onmouseenter = function() { 
            this.style.borderColor = 'rgba(6,182,212,0.35)'; 
            this.style.background = 'rgba(6,182,212,0.05)'; 
            this.style.transform = 'translateY(-2px)'; 
        };
        card.onmouseleave = function() { 
            this.style.borderColor = 'rgba(255,255,255,0.06)'; 
            this.style.background = 'rgba(255,255,255,0.02)'; 
            this.style.transform = 'translateY(0)'; 
        };
        card.onclick = () => selectLootEnemy(enemyId);

        card.innerHTML = `
            <div>
                <span style="font-size: 0.6rem; color: ${accentColor}; font-weight: bold;">${typeLabel}</span>
                <div style="font-size: 0.95rem; color: #fff; font-weight: 600; margin-top: 2px;">${en.name || 'Enemigo ' + enemyId}</div>
                <span style="font-size: 0.7rem; color: var(--text-dim);">#ID ${enemyId}</span>
            </div>
            <div style="text-align: center;">
                <div style="font-size: 1.5rem; font-weight: bold; color: ${dropCount > 0 ? accentColor : 'var(--text-dim)'};">${dropCount}</div>
                <div style="font-size: 0.55rem; color: var(--text-dim); text-transform: uppercase;">Drops</div>
            </div>
        `;
        summaryGrid.appendChild(card);
    });
}


function updateLootSidebar() {
    const enemyList = document.getElementById('sidebar-loot-enemies-list');
    const bossList = document.getElementById('sidebar-loot-bosses-list');
    if (!enemyList || !bossList) return;

    enemyList.innerHTML = '';
    bossList.innerHTML = '';

    if (!config || !config.enemyModels) return;

    // Preservar el estado cerrado/abierto de las carpetas de botín
    const closedFolders = new Set();
    document.querySelectorAll('.folder-content').forEach(el => {
        if (el.id && !el.classList.contains('show')) {
            closedFolders.add(el.id);
        }
    });

    const sortedIds = Object.keys(config.enemyModels).sort((a, b) => parseInt(a) - parseInt(b));
    const baseSelectedId = selectedLootEnemyId ? selectedLootEnemyId.split('-')[0] : '';
    const tiers = [
        { suffix: '', label: 'Base (x1)' },
        { suffix: '-A', label: 'Tier A (x2)' },
        { suffix: '-B', label: 'Tier B (x3)' },
        { suffix: '-C', label: 'Tier C (x4)' },
        { suffix: '-D', label: 'Tier D (x5)' }
    ];

    sortedIds.forEach(id => {
        if (id.includes('-')) return; // Omitir variantes en la iteración principal del sidebar
        
        const en = config.enemyModels[id];
        if (!en) return;

        const isBoss = parseInt(id) >= 100;

        if (!isBoss) {
            const isCurrentOpen = baseSelectedId === id && !closedFolders.has(`subfolder-loot-enemy-${id}`);
            
            // Contenedor del grupo de botín
            const groupContainer = document.createElement('div');
            groupContainer.className = 'enemy-group';
            groupContainer.style.display = 'flex';
            groupContainer.style.flexDirection = 'column';

            // Enlace del Enemigo Base (Carpeta)
            const parentLink = document.createElement('div');
            parentLink.className = 'nav-link sub ' + (isCurrentOpen ? 'active' : '');
            parentLink.style.display = 'flex';
            parentLink.style.justifyContent = 'space-between';
            parentLink.style.alignItems = 'center';
            parentLink.style.cursor = 'pointer';
            
            parentLink.innerHTML = `
                <span>👾 ${en.name || 'Enemigo '+id}</span>
                <span class="chevron" style="font-size: 0.65rem; transition: transform 0.2s;">${isCurrentOpen ? '▼' : '▶'}</span>
            `;

            parentLink.onclick = (e) => {
                toggleFolder(`subfolder-loot-enemy-${id}`, e);
                selectLootEnemy(id);
            };
            groupContainer.appendChild(parentLink);

            // Sub-carpeta colapsable para variantes de botín
            const subContainer = document.createElement('div');
            subContainer.id = `subfolder-loot-enemy-${id}`;
            subContainer.className = 'folder-content ' + (isCurrentOpen ? 'show' : '');
            subContainer.style.paddingLeft = '1rem';
            subContainer.style.borderLeft = '1px solid #333';
            subContainer.style.marginLeft = '0.5rem';

            tiers.forEach(t => {
                const subId = `${id}${t.suffix}`;
                const subEn = config.enemyModels[subId];
                if (!subEn) return;
                
                const isSubActive = selectedLootEnemyId === subId;
                const subDropCount = (subEn.lootDrops && subEn.lootDrops.length) || 0;

                const subLink = document.createElement('div');
                subLink.className = 'nav-link sub ' + (isSubActive ? 'active' : '');
                subLink.style.display = 'flex';
                subLink.style.justifyContent = 'space-between';
                subLink.style.alignItems = 'center';
                subLink.style.cursor = 'pointer';
                subLink.innerHTML = `
                    <span>👾 ${t.label}</span>
                    <span style="font-size: 0.55rem; opacity: 0.5; background: rgba(255,255,255,0.05); padding: 1px 4px; border-radius: 3px;">${subDropCount} drops</span>
                `;
                
                subLink.onclick = (e) => {
                    e.stopPropagation();
                    selectLootEnemy(subId);
                };

                subContainer.appendChild(subLink);
            });

            groupContainer.appendChild(subContainer);
            enemyList.appendChild(groupContainer);
        } else {
            // Bosses
            const dropCount = (en.lootDrops && en.lootDrops.length) || 0;
            const isActive = selectedLootEnemyId === id;
            const link = document.createElement('div');
            link.className = 'nav-link sub ' + (isActive ? 'active' : '');
            link.style.cursor = 'pointer';
            link.style.display = 'flex';
            link.style.justifyContent = 'space-between';
            link.style.alignItems = 'center';
            link.innerHTML = `
                <span>💀 ${en.name || 'Boss '+id}</span>
                <span style="font-size: 0.6rem; opacity: 0.5; background: rgba(255,255,255,0.05); padding: 2px 6px; border-radius: 4px;">${dropCount} drops</span>
            `;
            link.onclick = () => selectLootEnemy(id);
            bossList.appendChild(link);
        }
    });
}

function renderEnemyLootDetail() {
    updateLootSidebar();
    const container = document.getElementById('enemy-loot-detail-container');
    if (!container) return;

    const enemyId = selectedLootEnemyId;
    if (!enemyId || !config.enemyModels[enemyId]) {
        container.innerHTML = '<div style="color: var(--text-dim); text-align: center; padding: 4rem;">Seleccioná un enemigo del sidebar para configurar su botín.</div>';
        return;
    }

    const en = config.enemyModels[enemyId];
    if (!en.lootDrops) en.lootDrops = [];

    const isBoss = parseInt(enemyId) >= 100;
    const badgeColor = isBoss ? 'var(--accent)' : 'var(--success)';
    const badgeText = isBoss ? 'BOSS' : 'REGULAR';

    const totalChance = en.lootDrops.reduce((sum, ld) => sum + (ld.chance || 0), 0);
    const avgDrops = totalChance.toFixed(2);

    container.innerHTML = `
        <div class="card" style="width: 100%; margin-bottom: 2rem; border-left: 4px solid ${badgeColor};">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
                <div>
                    <span style="background: ${badgeColor}20; color: ${badgeColor}; padding: 3px 10px; border-radius: 6px; font-size: 0.7rem; font-weight: bold; margin-right: 12px;">${badgeText}</span>
                    <strong style="font-size: 1.4rem; color: #fff;">${en.name}</strong>
                    <span style="color: var(--text-dim); font-size: 0.85rem; margin-left: 8px;">(#ID ${enemyId})</span>
                </div>
                <div style="display: flex; gap: 1rem; align-items: center;">
                    <div style="text-align: center; background: rgba(255,255,255,0.03); padding: 8px 16px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.05);">
                        <div style="font-size: 0.6rem; color: var(--text-dim); text-transform: uppercase;">Items Configurados</div>
                        <div style="font-size: 1.3rem; font-weight: bold; color: var(--accent);">${en.lootDrops.length}</div>
                    </div>
                    <div style="text-align: center; background: rgba(255,255,255,0.03); padding: 8px 16px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.05);">
                        <div style="font-size: 0.6rem; color: var(--text-dim); text-transform: uppercase;">Drops Promedio</div>
                        <div style="font-size: 1.3rem; font-weight: bold; color: var(--primary);"><select id="asset-picker-select" size="12" style="flex:1; overflow-y:auto; padding:8px 12px; width:100%; background:rgba(255,255,255,0.02); color:white; border:1px solid rgba(255,255,255,0.1); border-radius:8px;">
                <!-- Options will be filled dynamically -->
            </select></div>
                </div>
            </div>

            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.05);">
                <label style="color: var(--accent); font-size: 0.75rem; font-weight: bold;">🎁 TABLA DE RECOMPENSAS</label>
                <button class="btn btn-primary" style="padding: 6px 16px; font-size: 0.75rem; background: var(--accent); border-color: var(--accent);" onclick="addLootDropFromComponent('${enemyId}', 'enemy-loot-detail-container')">+ AGREGAR RECOMPENSA</button>
            </div>

            <div id="enemy-loot-drops-list" style="display: grid; grid-template-columns: 1fr; gap: 12px;">
                <!-- Rendered dynamically by component -->
            </div>
        </div>
    `;
    window.renderLootTableComponent(enemyId, 'enemy-loot-drops-list');
}

// ==========================================
// MÓDULO DE CRAFTEO Y CREACIÓN (ADMIN DASH)
// ==========================================

window.renderCrafting = function() {
    // Inicializar secciones si no existen
    if (!config.shopItems) config.shopItems = {};
    if (!config.shopItems.resources) {
        config.shopItems.resources = [
            { id: "mat_iron", name: "Mineral de Hierro", desc: "Material básico para fundiciones espaciales.", prices: { hubs: 100, ohcu: 0 }, icon: "res://assets/Materiales/Hierro.png", color: "#9ca3af", type: "resource" },
            { id: "mat_copper", name: "Mineral de Cobre", desc: "Utilizado para componentes electrónicos.", prices: { hubs: 200, ohcu: 0 }, icon: "res://assets/Materiales/Cobre.png", color: "#b45309", type: "resource" },
            { id: "mat_plasma", name: "Núcleo de Plasma", desc: "Esencia energética altamente inestable.", prices: { hubs: 1000, ohcu: 5 }, icon: "res://assets/Materiales/Plasma.png", color: "#06b6d4", type: "resource" },
            { id: "mat_darkmatter", name: "Materia Oscura", desc: "Elemento exótico usado para tecnologías avanzadas.", prices: { hubs: 5000, ohcu: 25 }, icon: "res://assets/Materiales/MateriaOscura.png", color: "#d946ef", type: "resource" }
        ];
    }
    if (!config.craftingRecipes) {
        config.craftingRecipes = [];
    }

    const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';

    function resolveAssetWebUrl(iconPath) {
        if (!iconPath) return '';
        let path = iconPath.replace(/\\/g, '/');
        if (path.includes('res://assets/')) {
            return path.replace('res://assets/', activeURL + '/assets/');
        }
        let idx = path.indexOf('assets/');
        if (idx !== -1) {
            return activeURL + '/' + path.substring(idx);
        }
        return iconPath;
    }

    // --- RENDERIZAR MATERIALES ---
    const resourcesList = document.getElementById('crafting-resources-list');
    if (resourcesList) {
        resourcesList.innerHTML = '';
        
        config.shopItems.resources.forEach((res, idx) => {
            const div = document.createElement('div');
            div.style.background = 'rgba(255,255,255,0.02)';
            div.style.padding = '1.5rem';
            div.style.borderRadius = '10px';
            div.style.border = '1px solid rgba(255,255,255,0.05)';
            div.style.position = 'relative';
            
            const resIconWeb = resolveAssetWebUrl(res.icon);
            const previewImgHTML = resIconWeb ? `<img src="${resIconWeb}" style="width:130px; height:130px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.15); background: rgba(0,0,0,0.3); display: block;" onerror="this.style.display='none';">` : `<div style="width:130px; height:130px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.75rem;">Sin Icono</div>`;
            
            div.innerHTML = `
                <button style="position:absolute; top:8px; right:8px; background:none; border:none; color:#ff4444; cursor:pointer; font-size:16px;" onclick="removeCraftingResource(${idx})">✕</button>
                <div style="display: flex; gap: 20px; align-items: flex-start;">
                    <!-- Preview Image -->
                    <div style="flex-shrink: 0; display: flex; align-items: center; justify-content: center;">
                        ${previewImgHTML}
                    </div>
                    
                    <!-- Form Fields -->
                    <div style="flex-grow: 1; display: flex; flex-direction: column; gap: 10px;">
                        <div class="form-grid" style="grid-template-columns: 1fr 1.5fr; gap:10px; display: grid;">
                            <div class="field"><label>ID de Recurso</label><input type="text" value="${res.id}" onchange="config.shopItems.resources[${idx}].id = this.value; renderCrafting();"></div>
                            <div class="field"><label>Nombre del Material</label><input type="text" value="${res.name}" onchange="config.shopItems.resources[${idx}].name = this.value; renderCrafting();"></div>
                        </div>
                        <div class="field" style="width: 100%;"><label>Descripción</label><input type="text" value="${res.desc || ''}" style="width: 100%;" onchange="config.shopItems.resources[${idx}].desc = this.value;"></div>
                        <div class="field" style="width: 100%;"><label>Icono (Asset del Servidor)</label>
                            <div style="display: flex; gap: 10px; align-items: center; width: 100%;">
                                <div style="flex-grow:1; background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.08); border-radius:6px; padding:8px 12px; font-family:'JetBrains Mono'; font-size:0.75rem; color:${res.icon ? 'var(--primary)' : 'rgba(255,255,255,0.25)'}; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${res.icon || '-- Sin asset asignado --'}</div>
                                <button class="btn btn-primary" style="padding:8px 15px; font-size:0.75rem; flex-shrink:0; background:var(--accent); border-color:var(--accent); white-space:nowrap;" onclick="openAssetPicker(${idx}, 'resource')">🖼 SELECCIONAR ASSET</button>
                            </div>
                        </div>
                        
                        <div style="display: flex; gap: 15px; align-items: center; width: 100%;">
                            <div class="field" style="width: 70px; margin:0; flex-shrink: 0;"><label>Escala</label><input type="number" step="0.1" min="0.1" value="${res.iconScale || 1.0}" style="width: 100%;" onchange="config.shopItems.resources[${idx}].iconScale = parseFloat(this.value) || 1.0;"></div>
                            <div class="field" style="width: 50px; margin:0; flex-shrink: 0;"><label>Color</label><input type="color" value="${res.color || '#ffffff'}" style="height:38px; width:100%; padding:0; border:none; background:none; cursor:pointer;" onchange="config.shopItems.resources[${idx}].color = this.value;"></div>
                            <div class="field" style="width: 90px; margin:0; flex-shrink: 0;"><label>Límite Stack</label><input type="number" min="1" value="${res.maxStack || 1}" onchange="config.shopItems.resources[${idx}].maxStack = parseInt(this.value) || 1;"></div>
                            <div class="field" style="width: 110px; margin:0; flex-shrink: 0;"><label>Precio (Hubs)</label><input type="number" max="9999999" value="${res.prices ? (res.prices.hubs || 0) : 0}" oninput="if(this.value.length > 7) this.value = this.value.slice(0, 7);" onchange="if(!config.shopItems.resources[${idx}].prices) config.shopItems.resources[${idx}].prices = {hubs:0, ohcu:0}; config.shopItems.resources[${idx}].prices.hubs = parseInt(this.value) || 0;"></div>
                            <div class="field" style="width: 110px; margin:0; flex-shrink: 0;"><label>Precio (Ohcu)</label><input type="number" max="9999999" value="${res.prices ? (res.prices.ohcu || 0) : 0}" oninput="if(this.value.length > 7) this.value = this.value.slice(0, 7);" onchange="if(!config.shopItems.resources[${idx}].prices) config.shopItems.resources[${idx}].prices = {hubs:0, ohcu:0}; config.shopItems.resources[${idx}].prices.ohcu = parseInt(this.value) || 0;"></div>
                        </div>
                    </div>
                </div>
            `;
            resourcesList.appendChild(div);
        });
    }

    // --- OBTENER TODOS LOS ÍTEMS DEL JUEGO PARA EL SELECTOR ---
    const allGameItems = [];
    if (config.shipModels) {
        config.shipModels.forEach(s => allGameItems.push({ id: String(s.id), name: `[NAVE] ${s.name}`, category: 'ships' }));
    }
    if (config.shopItems) {
        if (config.shopItems.weapons) {
            config.shopItems.weapons.forEach(w => allGameItems.push({ id: w.id, name: `[ARMA] ${w.name}`, category: 'weapons' }));
        }
        if (config.shopItems.shields) {
            config.shopItems.shields.forEach(s => allGameItems.push({ id: s.id, name: `[ESCUDO] ${s.name}`, category: 'shields' }));
        }
        if (config.shopItems.engines) {
            config.shopItems.engines.forEach(e => allGameItems.push({ id: e.id, name: `[MOTOR] ${e.name}`, category: 'engines' }));
        }
        if (config.shopItems.extras) {
            config.shopItems.extras.forEach(x => allGameItems.push({ id: x.id, name: `[EXTRA] ${x.name}`, category: 'extras' }));
        }
        if (config.shopItems.ammo) {
            for (let sub in config.shopItems.ammo) {
                config.shopItems.ammo[sub].forEach(a => allGameItems.push({ id: a.id, name: `[MUNI] ${sub.toUpperCase()} - ${a.name}`, category: 'ammo' }));
            }
        }
        if (config.shopItems.resources) {
            config.shopItems.resources.forEach(r => allGameItems.push({ id: r.id, name: `[RECURSO] ${r.name}`, category: 'resources' }));
        }
    }

    // --- RENDERIZAR RECETAS ---
    const recipesList = document.getElementById('crafting-recipes-list');
    if (recipesList) {
        recipesList.innerHTML = '';
        config.craftingRecipes.forEach((recipe, idx) => {
            const div = document.createElement('div');
            div.style.background = 'rgba(255,255,255,0.02)';
            div.style.padding = '1.5rem';
            div.style.borderRadius = '12px';
            div.style.border = '1px solid rgba(255,255,255,0.05)';
            div.style.position = 'relative';

            // Construir select de item resultante
            const selectOptions = allGameItems.map(item => {
                const isSelected = (recipe.resultItemId === item.id && recipe.resultCategory === item.category);
                return `<option value="${item.category}:${item.id}" ${isSelected ? 'selected' : ''}>${item.name}</option>`;
            }).join('');

            // Ingredientes
            const ingredientsHTML = (recipe.ingredients || []).map((ing, ingIdx) => {
                const matSelectOptions = config.shopItems.resources.map(r => {
                    return `<option value="${r.id}" ${ing.itemId === r.id ? 'selected' : ''}>${r.name} (${r.id})</option>`;
                }).join('');

                return `
                    <div style="display: flex; gap: 10px; align-items: center; margin-bottom: 8px;">
                        <select style="background: #0f172a; border: 1px solid rgba(255,255,255,0.1); color: white; padding: 6px 10px; border-radius: 6px; flex: 2;" onchange="updateCraftingRecipeIngredientItem(${idx}, ${ingIdx}, this.value)">
                            <option value="">-- Seleccionar Material --</option>
                            ${matSelectOptions}
                        </select>
                        <input type="number" min="1" value="${ing.amount}" style="background: #0f172a; border: 1px solid rgba(255,255,255,0.1); color: white; padding: 6px 10px; border-radius: 6px; width: 80px; text-align: center;" onchange="updateCraftingRecipeIngredientQty(${idx}, ${ingIdx}, this.value)">
                        <button style="background: rgba(255,68,68,0.1); border: 1px solid rgba(255,68,68,0.2); color: #ff4444; border-radius: 6px; padding: 6px 12px; cursor: pointer;" onclick="removeCraftingRecipeIngredient(${idx}, ${ingIdx})">✕</button>
                    </div>
                `;
            }).join('');

            let resultIcon = '';
            if (recipe.resultCategory === 'ships') {
                const s = config.shipModels?.find(ship => String(ship.id) === String(recipe.resultItemId));
                resultIcon = s ? s.icon : '';
            } else if (recipe.resultCategory === 'ammo') {
                for (let sub in config.shopItems?.ammo || {}) {
                    const a = config.shopItems.ammo[sub].find(item => item.id === recipe.resultItemId);
                    if (a) { resultIcon = a.icon; break; }
                }
            } else {
                const list = config.shopItems?.[recipe.resultCategory] || [];
                const it = list.find(item => item.id === recipe.resultItemId);
                resultIcon = it ? it.icon : '';
            }
            // Usar icono propio de la receta si existe, sino el del item resultante
            const recipeOwnIcon = recipe.icon || '';
            const recipeDisplayIcon = recipeOwnIcon || resultIcon;
            const recipeIconWeb = resolveAssetWebUrl(recipeDisplayIcon);
            const recipePreviewImgHTML = recipeIconWeb ? `<img src="${recipeIconWeb}" style="width:110px; height:110px; object-fit:contain; border-radius:8px; border:1px solid rgba(255,255,255,0.15); background: rgba(0,0,0,0.3); display: block;" onerror="this.style.display='none';">` : `<div style="width:110px; height:110px; border:1px dashed rgba(255,255,255,0.15); border-radius:8px; display:flex; align-items:center; justify-content:center; color:rgba(255,255,255,0.2); font-size:0.75rem;">Sin Icono</div>`;

            div.innerHTML = `
                <button style="position:absolute; top:12px; right:12px; background:none; border:none; color:#ff4444; cursor:pointer; font-size:18px;" onclick="removeCraftingRecipe(${idx})">✕ ELIMINAR RECETA</button>
                <div style="display: flex; gap: 20px; align-items: flex-start;">
                    <!-- Preview Image + Asset Picker para la receta -->
                    <div style="flex-shrink: 0; display: flex; flex-direction:column; align-items: center; justify-content: center; gap:8px;">
                        ${recipePreviewImgHTML}
                        <button class="btn" style="padding:5px 10px; font-size:0.65rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.2); color:var(--primary); white-space:nowrap; cursor:pointer; border-radius:6px; width:110px;" onclick="openAssetPicker(${idx}, 'recipe')">🖼 ICONO RECETA</button>
                        ${recipeOwnIcon ? `<button style="padding:3px 8px; font-size:0.6rem; background:none; border:1px solid rgba(255,68,68,0.3); color:#ff6b6b; border-radius:4px; cursor:pointer; width:110px;" onclick="config.craftingRecipes[${idx}].icon=''; renderCrafting();">✕ Quitar icono</button>` : ''}
                    </div>
                    
                    <!-- Form Fields -->
                    <div style="flex-grow: 1; display: flex; flex-direction: column; gap: 10px;">
                        <div class="form-grid" style="grid-template-columns: 1fr 1.5fr 50px; gap:15px; display: grid;">
                            <div class="field"><label>ID Única de Receta</label><input type="text" value="${recipe.id}" onchange="config.craftingRecipes[${idx}].id = this.value;"></div>
                            <div class="field"><label>Nombre Visual de la Receta</label><input type="text" value="${recipe.name}" onchange="config.craftingRecipes[${idx}].name = this.value;"></div>
                            <div class="field" style="width: 50px; margin:0; flex-shrink: 0;"><label>Color</label><input type="color" value="${recipe.color || '#ffffff'}" style="height:38px; width:100%; padding:0; border:none; background:none; cursor:pointer;" onchange="config.craftingRecipes[${idx}].color = this.value;"></div>
                        </div>
                        <div class="field" style="width:100%;"><label>Descripción de Receta</label><input type="text" value="${recipe.desc || ''}" style="width:100%;" onchange="config.craftingRecipes[${idx}].desc = this.value;"></div>
                        
                        <div class="form-grid" style="grid-template-columns: 2fr 1fr; gap:15px; display: grid; align-items:center;">
                            <div class="field">
                                <label>Objeto Resultante a Fabricar</label>
                                <select style="background: #0f172a; border: 1px solid rgba(255,255,255,0.1); color: white; font-weight: bold; cursor: pointer; width: 100%; border-radius: 6px; padding: 8px 10px; font-size: 0.85rem;" onchange="updateCraftingRecipeResultItem(${idx}, this.value); renderCrafting();">
                                    <option value="">-- Seleccionar Objeto del Juego --</option>
                                    ${selectOptions}
                                </select>
                            </div>
                            <div class="field"><label>Cantidad Fabricada</label><input type="number" min="1" value="${recipe.resultAmount || 1}" onchange="config.craftingRecipes[${idx}].resultAmount = parseInt(this.value)"></div>
                        </div>

                         <div style="display: flex; gap: 15px; align-items: center; width: 100%;">
                            <div class="field" style="width: 70px; margin:0; flex-shrink: 0;"><label>Escala</label><input type="number" step="0.1" min="0.1" value="${recipe.iconScale || 1.0}" style="width:100%;" onchange="config.craftingRecipes[${idx}].iconScale = parseFloat(this.value) || 1.0;"></div>
                            <div class="field" style="width: 90px; margin:0; flex-shrink: 0;"><label>Límite Stack</label><input type="number" min="1" value="${recipe.maxStack || 1}" onchange="config.craftingRecipes[${idx}].maxStack = parseInt(this.value) || 1;"></div>
                            <div class="field" style="flex-grow:1; margin:0;"><label>Costo de Hubs (qty)</label><input type="number" value="${recipe.costHubs || 0}" onchange="config.craftingRecipes[${idx}].costHubs = parseInt(this.value)"></div>
                            <div class="field" style="flex-grow:1; margin:0;"><label>Costo de Ohcu (qty)</label><input type="number" value="${recipe.costOhcu || 0}" onchange="config.craftingRecipes[${idx}].costOhcu = parseInt(this.value)"></div>
                        </div>

                        <div style="margin-top: 15px; padding-top: 10px; border-top: 1px solid rgba(255,255,255,0.05); width: 100%;">
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
                                <label style="color:var(--accent); font-size: 0.75rem; font-weight:bold;">⚙️ INGREDIENTES REQUERIDOS</label>
                                <button class="btn btn-primary" style="padding: 2px 8px; font-size: 0.65rem;" onclick="addCraftingRecipeIngredient(${idx})">+ AGREGAR INGREDIENTE</button>
                            </div>
                            <div id="recipe-ingredients-${idx}">
                                ${ingredientsHTML}
                            </div>
                        </div>
                    </div>
                </div>
            `;
            recipesList.appendChild(div);
        });
    }
};

window.addCraftingResource = function() {
    const newId = "mat_new_" + Math.random().toString(36).substr(2, 5);
    config.shopItems.resources.push({
        id: newId,
        name: "Nuevo Material",
        desc: "Descripción del nuevo material.",
        prices: { hubs: 100, ohcu: 0 },
        icon: "res://assets/Materiales/Hierro.png",
        color: "#ffffff",
        type: "resource"
    });
    renderCrafting();
};

window.removeCraftingResource = function(idx) {
    if (confirm("¿Estás seguro de eliminar este material? Esto podría afectar las recetas que lo utilicen.")) {
        config.shopItems.resources.splice(idx, 1);
        renderCrafting();
    }
};

window.addCraftingRecipe = function() {
    const newId = "recipe_new_" + Math.random().toString(36).substr(2, 5);
    config.craftingRecipes.push({
        id: newId,
        name: "Nueva Receta",
        desc: "Descripción de la nueva receta.",
        resultItemId: "",
        resultCategory: "weapons",
        resultAmount: 1,
        costHubs: 1000,
        costOhcu: 0,
        ingredients: []
    });
    renderCrafting();
};

window.removeCraftingRecipe = function(idx) {
    if (confirm("¿Deseas eliminar esta receta de crafteo?")) {
        config.craftingRecipes.splice(idx, 1);
        renderCrafting();
    }
};

window.addCraftingRecipeIngredient = function(recipeIdx) {
    if (!config.craftingRecipes[recipeIdx].ingredients) {
        config.craftingRecipes[recipeIdx].ingredients = [];
    }
    config.craftingRecipes[recipeIdx].ingredients.push({
        itemId: "",
        amount: 1
    });
    renderCrafting();
};

window.removeCraftingRecipeIngredient = function(recipeIdx, ingIdx) {
    config.craftingRecipes[recipeIdx].ingredients.splice(ingIdx, 1);
    renderCrafting();
};

window.updateCraftingRecipeIngredientItem = function(recipeIdx, ingIdx, value) {
    config.craftingRecipes[recipeIdx].ingredients[ingIdx].itemId = value;
};

window.updateCraftingRecipeIngredientQty = function(recipeIdx, ingIdx, value) {
    config.craftingRecipes[recipeIdx].ingredients[ingIdx].amount = parseInt(value) || 1;
};

window.updateCraftingRecipeResultItem = function(recipeIdx, value) {
    if (!value) {
        config.craftingRecipes[recipeIdx].resultCategory = "weapons";
        config.craftingRecipes[recipeIdx].resultItemId = "";
        return;
    }
    const [category, id] = value.split(':');
    config.craftingRecipes[recipeIdx].resultCategory = category;
    config.craftingRecipes[recipeIdx].resultItemId = id;
};

function formatBytes(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatDuration(ms) {
    const totalSecs = Math.floor(ms / 1000);
    const hrs = Math.floor(totalSecs / 3600);
    const mins = Math.floor((totalSecs % 3600) / 60);
    const secs = totalSecs % 60;
    
    let parts = [];
    if (hrs > 0) parts.push(`${hrs}h`);
    if (mins > 0 || hrs > 0) parts.push(`${mins}m`);
    parts.push(`${secs}s`);
    return parts.join(' ');
}

window.renderPerformance = function(data) {
    const perf = data.performance || {};
    const container = document.getElementById('perf-aaa-container');
    if (!container) return;

    // Helper para sparklines SVG autoescalables
    function generateSparkline(history, color) {
        if (!history || history.length === 0) {
            return `<svg viewBox="0 0 100 30" width="100%" height="30"><text x="50%" y="50%" text-anchor="middle" fill="#555" font-size="8">Sin datos</text></svg>`;
        }
        const max = Math.max(...history) || 1;
        const min = Math.min(...history) || 0;
        const range = max - min || 1;
        const width = 100;
        const height = 30;
        const points = history.map((val, idx) => {
            const x = (idx / (history.length - 1)) * width;
            const y = height - ((val - min) / range) * (height - 4) - 2;
            return `${x.toFixed(1)},${y.toFixed(1)}`;
        }).join(' ');
        
        return `
            <svg viewBox="0 0 100 30" width="100%" height="35" style="overflow:visible;">
                <polyline fill="none" stroke="${color}" stroke-width="1.5" points="${points}" />
                <circle cx="100" cy="${(height - ((history[history.length - 1] - min) / range) * (height - 4) - 2).toFixed(1)}" r="2" fill="${color}" />
            </svg>
        `;
    }

    // 1. Análisis de Alertas Automáticas
    let alerts = [];
    
    // Alerta CPU
    if (perf.cpuUsage >= 70) {
        alerts.push({
            type: 'danger',
            icon: '🔥',
            title: 'USO CRÍTICO DE CPU',
            desc: `La CPU del servidor está en ${perf.cpuUsage}%. Reducí la cantidad de entidades activas.`
        });
    } else if (perf.cpuUsage >= 55) {
        alerts.push({
            type: 'warning',
            icon: '⚠️',
            title: 'CPU ELEVADA',
            desc: `Uso de CPU en ${perf.cpuUsage}%. Monitorear de cerca.`
        });
    }

    // Alerta Latencia de Tick
    const p99 = perf.p99TickTime || 0;
    if (p99 >= 33) {
        alerts.push({
            type: 'danger',
            icon: '⏱️',
            title: 'TICK P99 CRÍTICO (STUTTERS)',
            desc: `El percentil 99 de ticks está en ${p99.toFixed(1)} ms. El juego está experimentando tirones graves de físicas/colisiones.`
        });
    } else if (p99 >= 20) {
        alerts.push({
            type: 'warning',
            icon: '⏳',
            title: 'TICK P99 ELEVADO',
            desc: `Latencia P99 en ${p99.toFixed(1)} ms. Posible sobrecarga leve en el bucle principal.`
        });
    }

    // Alerta PPS de Entrada
    const ppsIn = perf.ppsIn || 0;
    if (ppsIn >= 8000) {
        alerts.push({
            type: 'danger',
            icon: '📡',
            title: 'SATURACIÓN DE RED (PPS IN CRÍTICO)',
            desc: `Recibiendo ${ppsIn.toLocaleString()} paquetes/seg. Posible ataque de denegación de servicio o exploit de spam de red.`
        });
    }

    // Alerta Fuga de Memoria (Detección de tendencia creciente en RSS)
    let memoryLeakAlert = false;
    let memLeakGrowth = 0;
    if (perf.rssHistory && perf.rssHistory.length >= 20) {
        const history = perf.rssHistory;
        const len = history.length;
        const initialSamples = history.slice(0, 5);
        const finalSamples = history.slice(len - 5);
        const avgInitial = initialSamples.reduce((a, b) => a + b, 0) / initialSamples.length;
        const avgFinal = finalSamples.reduce((a, b) => a + b, 0) / finalSamples.length;
        if (avgInitial > 0 && avgFinal > avgInitial) {
            memLeakGrowth = ((avgFinal - avgInitial) / avgInitial) * 100;
            if (memLeakGrowth >= 20) {
                memoryLeakAlert = true;
                alerts.push({
                    type: 'danger',
                    icon: '🧠',
                    title: 'FUGA DE MEMORIA DETECTADA (LEAK)',
                    desc: `El uso de RAM RSS ha crecido un +${memLeakGrowth.toFixed(1)}% en las últimas muestras. Posible fuga a largo plazo.`
                });
            }
        }
    }

    // Renderizado del HTML
    let html = '';

    // SECCIÓN 1: PANEL DE ALERTAS
    if (alerts.length > 0) {
        html += `
            <div class="perf-section-title" style="margin: 0 0 1rem 0; color: #ff5555; font-size: 0.9rem; font-weight: bold; letter-spacing: 1px; display: flex; align-items: center; gap: 8px;">
                🔔 ANÁLISIS DE ALERTAS EN TIEMPO REAL
            </div>
            <div style="display: flex; flex-direction: column; gap: 10px; margin-bottom: 2rem;">
        `;
        alerts.forEach(alert => {
            const borderCol = alert.type === 'danger' ? '#ef4444' : '#f59e0b';
            const bgCol = alert.type === 'danger' ? 'rgba(239, 68, 68, 0.05)' : 'rgba(245, 158, 11, 0.05)';
            const titleCol = alert.type === 'danger' ? '#f87171' : '#fbbf24';
            html += `
                <div style="border-left: 4px solid ${borderCol}; background: ${bgCol}; padding: 1rem; border-radius: 4px 8px 8px 4px; display: flex; align-items: flex-start; gap: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);">
                    <div style="font-size: 1.4rem; line-height: 1;">${alert.icon}</div>
                    <div style="flex: 1;">
                        <h4 style="margin: 0 0 4px 0; color: ${titleCol}; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px; font-weight: 700;">${alert.title}</h4>
                        <p style="margin: 0; font-size: 0.8rem; color: #ccc; line-height: 1.4;">${alert.desc}</p>
                    </div>
                </div>
            `;
        });
        html += `</div>`;
    } else {
        html += `
            <div style="border-left: 4px solid #10b981; background: rgba(16, 185, 129, 0.03); padding: 0.75rem 1rem; border-radius: 4px 8px 8px 4px; display: flex; align-items: center; gap: 10px; margin-bottom: 2rem; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
                <div style="color: #10b981; font-size: 1.1rem;">✅</div>
                <div style="color: #a7f3d0; font-size: 0.8rem; font-weight: 600;">SISTEMA ESTABLE: Todas las métricas de red, CPU, RAM y latencia están dentro del rango operativo seguro.</div>
            </div>
        `;
    }

    // SECCIÓN 2: TARJETAS GENERALES Y DETALLES DEL PROCESO
    const uptimeStr = formatDuration(data.uptimeMs || 0);
    html += `
        <div class="perf-section-title" style="margin: 0 0 1rem 0; color: var(--accent); font-size: 0.9rem; font-weight: bold; letter-spacing: 1px;">
            📊 TELEMETRÍA GENERAL DEL PROCESO
        </div>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:var(--primary); font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">PILOTOS ONLINE</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${data.playersCount !== undefined ? data.playersCount : '--'}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Jugadores en mapas / lobby</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#ef4444; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">ENEMIGOS ACTIVOS</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${data.enemiesCount !== undefined ? data.enemiesCount : '--'}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">IAs simuladas por AIManager</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#eab308; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">ÁREAS ACTIVAS</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${data.activeAreas !== undefined ? data.activeAreas : '--'}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Grillas AOI cargadas</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#3bff31; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">UPTIME DE INSTANCIA</h4>
                <div style="font-size:1.2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff; height: 2.2rem; display: flex; align-items: center;">${uptimeStr}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Tiempo desde el último inicio</p>
            </div>
        </div>
    `;

    // SECCIÓN 3: TICK TIMES (P99, P50, Avg, Max)
    const p99Val = perf.p99TickTime || 0;
    const p50Val = perf.p50TickTime || 0;
    const avgVal = perf.avgTickTime || 0;
    const maxVal = perf.maxTickTime || 0;

    const p99Color = p99Val >= 33 ? '#ef4444' : (p99Val >= 20 ? '#fbbf24' : '#10b981');
    const p50Color = p50Val >= 16 ? '#ef4444' : (p50Val >= 10 ? '#fbbf24' : '#10b981');
    const avgColor = avgVal >= 16 ? '#ef4444' : (avgVal >= 10 ? '#fbbf24' : '#10b981');

    html += `
        <div class="perf-section-title" style="margin: 0 0 1rem 0; color: var(--accent); font-size: 0.9rem; font-weight: bold; letter-spacing: 1px;">
            ⏱️ ANÁLISIS DE CICLOS DE JUEGO (TICK LATENCY)
        </div>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:${p99Color}; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Percentil 99 (P99)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:${p99Color};">${p99Val.toFixed(1)} ms</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Peor escenario de latencia</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:${p50Color}; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Mediana (P50)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:${p50Color};">${p50Val.toFixed(1)} ms</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Valor típico del Loop</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:${avgColor}; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Promedio (Avg)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:${avgColor};">${avgVal.toFixed(1)} ms</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Promedio móvil ponderado</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#a855f7; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Pico Histórico (Max)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${maxVal.toFixed(1)} ms</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Mayor pico de procesamiento</p>
            </div>
        </div>
    `;

    // SECCIÓN 4: MÉTRICAS DE RED EN TIEMPO REAL
    const incomingPps = perf.ppsIn || 0;
    const outgoingPps = perf.ppsOut || 0;
    const incomingBytes = formatBytes(perf.network?.totalBytesReceived || 0);
    const outgoingBytes = formatBytes(perf.network?.totalBytesSent || 0);

    html += `
        <div class="perf-section-title" style="margin: 0 0 1rem 0; color: var(--accent); font-size: 0.9rem; font-weight: bold; letter-spacing: 1px;">
            📡 TELEMETRÍA DE RED (BANDWIDTH & PACKETS)
        </div>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:var(--primary); font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Paquetes Entrantes (PPS In)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${incomingPps.toLocaleString()} <span style="font-size: 0.9rem; opacity: 0.7;">pkts/s</span></div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Tasa de entrada actual</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#f43f5e; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Paquetes Salientes (PPS Out)</h4>
                <div style="font-size:2rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff;">${outgoingPps.toLocaleString()} <span style="font-size: 0.9rem; opacity: 0.7;">pkts/s</span></div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Tasa de salida actual</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#3bff31; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Total Tráfico Recibido</h4>
                <div style="font-size:1.8rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff; height: 2.2rem; display: flex; align-items: center;">⬇️ ${incomingBytes}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Acumulado de bajada (Ingreso)</p>
            </div>
            <div class="card" style="background: rgba(0,210,255,0.03); border: 1px solid rgba(0,210,255,0.12); padding: 1.25rem;">
                <h4 style="margin:0 0 8px 0; color:#3bff31; font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">Total Tráfico Enviado</h4>
                <div style="font-size:1.8rem; font-weight:700; font-family:'JetBrains Mono'; color:#fff; height: 2.2rem; display: flex; align-items: center;">⬆️ ${outgoingBytes}</div>
                <p style="margin:4px 0 0 0; font-size:0.75rem; opacity:0.6;">Acumulado de subida (Egreso)</p>
            </div>
        </div>
    `;

    // SECCIÓN 5: CPU Y MEMORIA (SPARKLINES HISTÓRICOS)
    const rssVal = perf.memoryUsage?.rss || 0;
    const heapVal = perf.memoryUsage?.heapUsed || 0;
    const heapTot = perf.memoryUsage?.heapTotal || 0;
    const cpuPct = perf.cpuUsage || 0;

    html += `
        <div class="perf-section-title" style="margin: 0 0 1rem 0; color: var(--accent); font-size: 0.9rem; font-weight: bold; letter-spacing: 1px;">
            💻 RENDIMIENTO DE RECURSOS DEL SISTEMA
        </div>
        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 1.5rem; margin-bottom: 2rem;">
            <!-- Uso de CPU -->
            <div class="card" style="background: rgba(0,210,255,0.02); border: 1px solid rgba(0,210,255,0.12); padding: 1.5rem; display: flex; flex-direction: column; justify-content: space-between;">
                <div>
                    <h4 style="margin:0 0 10px 0; color:var(--primary); font-size:0.75rem; text-transform:uppercase; letter-spacing:1px;">USO DE CPU DEL PROCESO</h4>
                    <div style="font-size:2.5rem; font-weight:800; font-family:'JetBrains Mono'; color:#fff; margin-bottom: 1rem;">${cpuPct}%</div>
                </div>
                <div>
                    <div style="width: 100%; height: 8px; background: rgba(255,255,255,0.05); border-radius: 4px; overflow: hidden; margin-bottom: 6px;">
                        <div style="width: ${cpuPct}%; height: 100%; background: ${cpuPct >= 70 ? 'var(--danger)' : (cpuPct >= 50 ? 'var(--warning)' : 'var(--primary)')}; border-radius: 4px; transition: width 0.3s ease;"></div>
                    </div>
                    <p style="margin:0; font-size:0.7rem; opacity:0.6;">Carga actual sobre el núcleo asignado</p>
                </div>
            </div>

            <!-- Historial de Memoria con Sparklines SVG -->
            <div class="card" style="background: rgba(0,210,255,0.02); border: 1px solid rgba(0,210,255,0.12); padding: 1.5rem;">
                <h4 style="margin:0 0 15px 0; color:var(--accent); font-size:0.75rem; text-transform:uppercase; letter-spacing:1px; display: flex; justify-content: space-between;">
                    <span>📈 HISTORIAL Y TENDENCIA DE MEMORIA</span>
                    <span style="font-family: 'JetBrains Mono'; font-weight: normal; color: #aaa; text-transform: none;">Últimos 120s (Muestras de 2s)</span>
                </h4>
                
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
                    <!-- RSS Sparkline -->
                    <div style="background: rgba(0,0,0,0.15); padding: 10px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.02);">
                        <div style="display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 5px;">
                            <span style="font-size: 0.75rem; font-weight: bold; color: #60a5fa;">RAM RSS (Física)</span>
                            <span style="font-family: 'JetBrains Mono'; font-size: 0.85rem; font-weight: bold; color: #fff;">${rssVal.toFixed(1)} MB</span>
                        </div>
                        <div style="margin-top: 5px; min-height: 40px;">
                            ${generateSparkline(perf.rssHistory, '#60a5fa')}
                        </div>
                        <p style="margin: 5px 0 0 0; font-size: 0.65rem; opacity: 0.5; text-align: right;">rss footprint</p>
                    </div>

                    <!-- Heap Sparkline -->
                    <div style="background: rgba(0,0,0,0.15); padding: 10px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.02);">
                        <div style="display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 5px;">
                            <span style="font-size: 0.75rem; font-weight: bold; color: #f472b6;">V8 Heap (JS)</span>
                            <span style="font-family: 'JetBrains Mono'; font-size: 0.85rem; font-weight: bold; color: #fff;">${heapVal.toFixed(1)} / ${heapTot.toFixed(1)} MB</span>
                        </div>
                        <div style="margin-top: 5px; min-height: 40px;">
                            ${generateSparkline(perf.heapHistory, '#f472b6')}
                        </div>
                        <p style="margin: 5px 0 0 0; font-size: 0.65rem; opacity: 0.5; text-align: right;">heap usage</p>
                    </div>
                </div>
            </div>
        </div>
    `;

    // SECCIÓN 6: AUDITORÍA DE ANCHO DE BANDA POR PILOTO
    html += `
        <div class="card" style="width: 100%; padding: 0; overflow: hidden; margin-top: 1rem; border: 1px solid rgba(255,255,255,0.05); background: rgba(0,0,0,0.2);">
            <div style="padding: 1.5rem; border-bottom: 1px solid rgba(255,255,255,0.05); display:flex; justify-content:space-between; align-items:center;">
                <h3 style="margin:0; color:var(--primary); font-size: 0.95rem; font-weight: bold;">🕵️ AUDITORÍA DE ANCHO DE BANDA DETALLADA POR PILOTO</h3>
                <span style="font-size:0.8rem; color:#aaa; font-style: italic;">Consumo de red granular y estimación por hora</span>
            </div>
            <table style="width: 100%; border-collapse: collapse; font-size: 0.9rem; text-align: left;">
                <thead style="background: rgba(255,255,255,0.03); border-bottom: 1px solid rgba(255,255,255,0.05);">
                    <tr>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Piloto</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Dirección IP</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Zona</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Uptime Conexión</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Datos Recibidos</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Datos Enviados</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Paquetes (Rx / Tx)</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Latencia</th>
                        <th style="padding: 1rem 1.2rem; font-size: 0.75rem; text-transform: uppercase; color: var(--accent);">Consumo Est. / Hora</th>
                    </tr>
                </thead>
                <tbody>
    `;

    const f = getFilter();
    let shownPlayersCount = 0;

    if (!data.playerStats || data.playerStats.length === 0) {
        html += `
            <tr>
                <td colspan="9" style="padding:3rem; text-align:center; color:#666; font-style:italic;">No hay pilotos en órbita en este momento.</td>
            </tr>
        `;
    } else {
        data.playerStats.forEach(p => {
            if (f && !p.username.toLowerCase().includes(f) && !p.ip.includes(f)) return;
            shownPlayersCount++;

            const timeOnline = formatDuration(p.durationMs);
            const recBytes = formatBytes(p.bytesReceived);
            const sentBytes = formatBytes(p.bytesSent);
            const estPerHour = formatBytes(p.totalPerHour || 0);

            const latColor = p.latency < 80 ? '#10b981' : (p.latency < 180 ? '#fbbf24' : '#ef4444');
            const zoneLabel = p.zone !== undefined ? p.zone : 'Desconocida';

            html += `
                <tr style="border-bottom: 1px solid rgba(255,255,255,0.03); transition: background 0.2s;" onmouseover="this.style.background='rgba(255,255,255,0.02)'" onmouseout="this.style.background='transparent'">
                    <td style="padding: 1rem 1.2rem; font-weight: bold; color: var(--primary); font-family: 'JetBrains Mono';">${p.username.toUpperCase()}</td>
                    <td style="padding: 1rem 1.2rem; font-family: 'JetBrains Mono'; opacity: 0.7; font-size: 0.8rem;">${p.ip}</td>
                    <td style="padding: 1rem 1.2rem; font-size: 0.85rem;"><span class="card-tag" style="position:static; background:rgba(234,179,8,0.1); color:#fbbf24; font-size:0.75rem; border: 1px solid rgba(234,179,8,0.25);">${zoneLabel}</span></td>
                    <td style="padding: 1rem 1.2rem; font-size: 0.85rem;">${timeOnline}</td>
                    <td style="padding: 1rem 1.2rem; color: #a5f3fc; font-family: 'JetBrains Mono'; font-size: 0.85rem;">${recBytes}</td>
                    <td style="padding: 1rem 1.2rem; color: #fed7aa; font-family: 'JetBrains Mono'; font-size: 0.85rem;">${sentBytes}</td>
                    <td style="padding: 1rem 1.2rem; font-family: 'JetBrains Mono'; font-size: 0.8rem; opacity: 0.8;">
                        <span style="color: #60a5fa;">⬇️ ${(p.pktReceived || 0).toLocaleString()}</span> / 
                        <span style="color: #f472b6;">⬆️ ${(p.pktSent || 0).toLocaleString()}</span>
                    </td>
                    <td style="padding: 1rem 1.2rem; font-weight: bold; color: ${latColor}; font-family: 'JetBrains Mono'; font-size: 0.85rem;">${p.latency}ms</td>
                    <td style="padding: 1rem 1.2rem; font-weight: bold; color: #3bff31; font-family: 'JetBrains Mono'; font-size: 0.85rem;">${estPerHour}/h</td>
                </tr>
            `;
        });

        if (shownPlayersCount === 0) {
            html += `
                <tr>
                    <td colspan="9" style="padding:3rem; text-align:center; color:#666; font-style:italic;">Ningún piloto coincide con el filtro: "${f}"</td>
                </tr>
            `;
        }
    }

    html += `
                </tbody>
            </table>
        </div>
    `;

    container.innerHTML = html;
};

// ==========================================
// FUNCIONES AUXILIARES DEL MODO ARENA
// ==========================================

window.addArenaMap = function(mapId) {
    if (!mapId) return;
    const idInt = parseInt(mapId);
    if (!config.gameModes.arenas) {
        config.gameModes.arenas = { enabled: true, maps: [], minPlayers: 2 };
    }
    if (!config.gameModes.arenas.maps) config.gameModes.arenas.maps = [];
    if (!config.gameModes.arenas.maps.includes(idInt)) {
        config.gameModes.arenas.maps.push(idInt);
        if (!config.gameModes.arenas.mapConfigs) config.gameModes.arenas.mapConfigs = {};
        config.gameModes.arenas.mapConfigs[idInt] = {
            width: 10000,
            height: 10000,
            nexusRed: { x: 2000, y: 5000, hp: 10000, shield: 5000 },
            nexusBlue: { x: 8000, y: 5000, hp: 10000, shield: 5000 },
            pillars: []
        };
        activeArenaMapId = idInt;
        activeArenaPillarIndex = null;
        renderModes();
    }
};

window.selectArenaMap = function(mapId) {
    activeArenaMapId = mapId ? parseInt(mapId) : null;
    activeArenaPillarIndex = null;
    renderModes();
};

window.addArenaPillar = function() {
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg) return;
    if (!mapCfg.pillars) mapCfg.pillars = [];
    
    const newPillar = {
        name: `Pilar ${mapCfg.pillars.length + 1}`,
        team: 'red',
        x: Math.round(mapCfg.width / 2),
        y: Math.round(mapCfg.height / 2),
        damage: 150,
        range: 600,
        ammoType: 'laser',
        attackType: 'fast',
        hp: 3000,
        shield: 1500
    };
    mapCfg.pillars.push(newPillar);
    activeArenaPillarIndex = mapCfg.pillars.length - 1;
    renderModes();
};

window.removeArenaPillar = function(idx) {
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg || !mapCfg.pillars) return;
    mapCfg.pillars.splice(idx, 1);
    activeArenaPillarIndex = null;
    renderModes();
};

window.selectArenaPillar = function(idx) {
    activeArenaPillarIndex = idx;
    renderModes();
};

window.addArenaSpawn = function() {
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg) return;
    if (!mapCfg.spawns) mapCfg.spawns = [];
    
    const newSpawn = {
        name: `Spawn ${mapCfg.spawns.length + 1}`,
        team: 'red',
        x: Math.round(mapCfg.width / 2),
        y: Math.round(mapCfg.height / 2),
        radius: 200
    };
    mapCfg.spawns.push(newSpawn);
    activeArenaSpawnIndex = mapCfg.spawns.length - 1;
    renderModes();
};

window.removeArenaSpawn = function(idx) {
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg || !mapCfg.spawns) return;
    mapCfg.spawns.splice(idx, 1);
    activeArenaSpawnIndex = null;
    renderModes();
};

window.selectArenaSpawn = function(idx) {
    activeArenaSpawnIndex = idx;
    renderModes();
};

function initArenaRadar() {
    const canvas = document.getElementById('arena-radar-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const container = document.getElementById('arena-radar-container');
    
    if (!activeArenaMapId) return;
    const mapCfg = config.gameModes.arenas.mapConfigs[activeArenaMapId];
    if (!mapCfg) return;

    const worldW = mapCfg.width || 10000;
    const worldH = mapCfg.height || 10000;

    let isDragging = false;
    let dragItem = null; // { type: 'nexus_red' | 'nexus_blue' | 'pillar' | 'spawn', index: idx }

    const updateCanvasSize = () => {
        const w = container.clientWidth;
        const h = container.clientHeight;
        if (w > 0 && h > 0) {
            canvas.width = w;
            canvas.height = h;
        }
    };
    updateCanvasSize();

    const worldToCanvas = (wx, wy) => ({
        x: (wx / worldW) * canvas.width,
        y: (wy / worldH) * canvas.height
    });

    const canvasToWorld = (cx, cy) => ({
        wx: (cx / canvas.width) * worldW,
        wy: (cy / canvas.height) * worldH
    });

    const draw = () => {
        ctx.fillStyle = '#05070a';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // Draw grid
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        ctx.lineWidth = 1;
        const gridCount = 10;
        for (let i = 1; i < gridCount; i++) {
            // vertical
            const x = (i / gridCount) * canvas.width;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, canvas.height);
            ctx.stroke();

            // horizontal
            const y = (i / gridCount) * canvas.height;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(canvas.width, y);
            ctx.stroke();
        }

        // Draw Spawns
        if (mapCfg.spawns) {
            mapCfg.spawns.forEach((s, idx) => {
                const pos = worldToCanvas(s.x, s.y);
                const isSelected = activeArenaSpawnIndex === idx;
                const rad = ((s.radius || 200) / worldW) * canvas.width;
                
                ctx.fillStyle = s.team === 'red' ? 'rgba(255, 49, 49, 0.05)' : 'rgba(49, 182, 255, 0.05)';
                ctx.strokeStyle = isSelected ? '#ffffff' : (s.team === 'red' ? 'rgba(255, 49, 49, 0.4)' : 'rgba(49, 182, 255, 0.4)');
                ctx.lineWidth = isSelected ? 2 : 1;
                ctx.setLineDash([2, 5]);
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, rad, 0, Math.PI * 2);
                ctx.fill();
                ctx.stroke();
                ctx.setLineDash([]);

                ctx.fillStyle = s.team === 'red' ? '#ff3131' : '#31b6ff';
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, 4, 0, Math.PI * 2);
                ctx.fill();

                ctx.fillStyle = '#ffffff';
                ctx.font = '8px sans-serif';
                ctx.textAlign = 'center';
                ctx.fillText(s.name || `Spawn ${idx + 1}`, pos.x, pos.y - 8);
            });
        }

        // Draw Red Nexus
        if (mapCfg.nexusRed) {
            const pos = worldToCanvas(mapCfg.nexusRed.x, mapCfg.nexusRed.y);
            ctx.fillStyle = 'rgba(255, 49, 49, 0.2)';
            ctx.strokeStyle = '#ff3131';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 15, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#ff3131';
            ctx.font = 'bold 9px sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('NEXO ROJO', pos.x, pos.y - 20);
        }

        // Draw Blue Nexus
        if (mapCfg.nexusBlue) {
            const pos = worldToCanvas(mapCfg.nexusBlue.x, mapCfg.nexusBlue.y);
            ctx.fillStyle = 'rgba(49, 182, 255, 0.2)';
            ctx.strokeStyle = '#31b6ff';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 15, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#31b6ff';
            ctx.font = 'bold 9px sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('NEXO AZUL', pos.x, pos.y - 20);
        }

        // Draw Pillars
        if (mapCfg.pillars) {
            mapCfg.pillars.forEach((p, idx) => {
                const pos = worldToCanvas(p.x, p.y);
                const isSelected = activeArenaPillarIndex === idx;
                
                ctx.strokeStyle = p.team === 'red' ? 'rgba(255, 49, 49, 0.25)' : 'rgba(49, 182, 255, 0.25)';
                ctx.lineWidth = isSelected ? 2 : 1;
                if (isSelected) {
                    ctx.setLineDash([4, 4]);
                } else {
                    ctx.setLineDash([]);
                }
                ctx.beginPath();
                const canvasRange = (p.range / worldW) * canvas.width;
                ctx.arc(pos.x, pos.y, canvasRange, 0, Math.PI * 2);
                ctx.stroke();
                ctx.setLineDash([]);

                if (isSelected) {
                    ctx.fillStyle = p.team === 'red' ? 'rgba(255, 49, 49, 0.03)' : 'rgba(49, 182, 255, 0.03)';
                    ctx.beginPath();
                    ctx.arc(pos.x, pos.y, canvasRange, 0, Math.PI * 2);
                    ctx.fill();
                }

                ctx.fillStyle = p.team === 'red' ? 'rgba(255, 49, 49, 0.4)' : 'rgba(49, 182, 255, 0.4)';
                ctx.strokeStyle = isSelected ? '#ffffff' : (p.team === 'red' ? '#ff3131' : '#31b6ff');
                ctx.lineWidth = isSelected ? 3 : 1.5;
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, 8, 0, Math.PI * 2);
                ctx.fill();
                ctx.stroke();

                ctx.fillStyle = '#ffffff';
                ctx.font = '8px monospace';
                ctx.textAlign = 'center';
                ctx.fillText(p.name, pos.x, pos.y - 12);
            });
        }
    };

    draw();

    canvas.onmousedown = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        // Check if clicked Red Nexus
        if (mapCfg.nexusRed) {
            const pos = worldToCanvas(mapCfg.nexusRed.x, mapCfg.nexusRed.y);
            if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 15) {
                isDragging = true;
                dragItem = { type: 'nexus_red' };
                canvas.style.cursor = 'grabbing';
                return;
            }
        }

        // Check if clicked Blue Nexus
        if (mapCfg.nexusBlue) {
            const pos = worldToCanvas(mapCfg.nexusBlue.x, mapCfg.nexusBlue.y);
            if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 15) {
                isDragging = true;
                dragItem = { type: 'nexus_blue' };
                canvas.style.cursor = 'grabbing';
                return;
            }
        }

        // Check if clicked a Pillar
        if (mapCfg.pillars) {
            for (let i = 0; i < mapCfg.pillars.length; i++) {
                const p = mapCfg.pillars[i];
                const pos = worldToCanvas(p.x, p.y);
                if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 12) {
                    isDragging = true;
                    dragItem = { type: 'pillar', index: i };
                    activeArenaPillarIndex = i;
                    activeArenaSpawnIndex = null;
                    canvas.style.cursor = 'grabbing';
                    draw();
                    return;
                }
            }
        }

        // Check if clicked a Spawn
        if (mapCfg.spawns) {
            for (let i = 0; i < mapCfg.spawns.length; i++) {
                const s = mapCfg.spawns[i];
                const pos = worldToCanvas(s.x, s.y);
                if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 12) {
                    isDragging = true;
                    dragItem = { type: 'spawn', index: i };
                    activeArenaSpawnIndex = i;
                    activeArenaPillarIndex = null;
                    canvas.style.cursor = 'grabbing';
                    draw();
                    return;
                }
            }
        }
    };

    canvas.onmousemove = (e) => {
        if (!isDragging || !dragItem) return;
        const rect = canvas.getBoundingClientRect();
        const mouseX = Math.max(0, Math.min(canvas.width, e.clientX - rect.left));
        const mouseY = Math.max(0, Math.min(canvas.height, e.clientY - rect.top));
        const world = canvasToWorld(mouseX, mouseY);

        if (dragItem.type === 'nexus_red') {
            mapCfg.nexusRed.x = Math.round(world.wx);
            mapCfg.nexusRed.y = Math.round(world.wy);
            const ix = document.getElementById('nexus-red-x');
            const iy = document.getElementById('nexus-red-y');
            if (ix) ix.value = mapCfg.nexusRed.x;
            if (iy) iy.value = mapCfg.nexusRed.y;
        } 
        else if (dragItem.type === 'nexus_blue') {
            mapCfg.nexusBlue.x = Math.round(world.wx);
            mapCfg.nexusBlue.y = Math.round(world.wy);
            const ix = document.getElementById('nexus-blue-x');
            const iy = document.getElementById('nexus-blue-y');
            if (ix) ix.value = mapCfg.nexusBlue.x;
            if (iy) iy.value = mapCfg.nexusBlue.y;
        } 
        else if (dragItem.type === 'pillar') {
            const p = mapCfg.pillars[dragItem.index];
            if (p) {
                p.x = Math.round(world.wx);
                p.y = Math.round(world.wy);
                const ix = document.getElementById('pillar-x');
                const iy = document.getElementById('pillar-y');
                if (ix) ix.value = p.x;
                if (iy) iy.value = p.y;
            }
        }
        else if (dragItem.type === 'spawn') {
            const s = mapCfg.spawns[dragItem.index];
            if (s) {
                s.x = Math.round(world.wx);
                s.y = Math.round(world.wy);
                const ix = document.getElementById('spawn-x');
                const iy = document.getElementById('spawn-y');
                if (ix) ix.value = s.x;
                if (iy) iy.value = s.y;
            }
        }
        draw();
    };

    const stopDrag = () => {
        if (isDragging) {
            isDragging = false;
            dragItem = null;
            canvas.style.cursor = 'crosshair';
            renderModes();
        }
    };

    canvas.onmouseup = stopDrag;
    canvas.onmouseleave = stopDrag;
}
window.initArenaRadar = initArenaRadar;

window.renderHousing = function() {
    if (!config.housingConfig) {
        config.housingConfig = JSON.parse(JSON.stringify(DEFAULT_HOUSING_CONFIG));
    }
    const hc = config.housingConfig;
    
    // Rellenar campos globales
    const minLvlInput = document.getElementById('housing-min-level');
    if (minLvlInput) minLvlInput.value = hc.levelRequired || 1;
    
    const costInput = document.getElementById('housing-cost');
    if (costInput) costInput.value = hc.cost || 0;
    
    const currencySelect = document.getElementById('housing-currency');
    if (currencySelect) currencySelect.value = hc.currency || 'hubs';
    
    const gridSizeInput = document.getElementById('housing-grid-size');
    if (gridSizeInput) gridSizeInput.value = hc.gridSize || 10;
    
    // Render catálogo de items
    const list = document.getElementById('housing-items-list');
    if (!list) return;
    list.innerHTML = '';
    
    const f = getFilter();
    
    (hc.placeableItems || []).forEach((item, idx) => {
        if (f && !item.name.toLowerCase().includes(f) && !item.id.toLowerCase().includes(f)) return;
        
        const div = document.createElement('div');
        div.className = 'card';
        div.style.background = 'rgba(255,255,255,0.02)';
        div.style.padding = '1.5rem';
        div.style.border = '1px solid rgba(255,255,255,0.05)';
        div.style.position = 'relative';
        
        div.innerHTML = `
            <div style="position:absolute; top:15px; right:15px;">
                <button class="btn btn-secondary" style="background:var(--danger); border:none; padding:4px 10px;" onclick="removeHousingItem(${idx})">✕ ELIMINAR</button>
            </div>
            <div class="form-grid" style="display:grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap:15px;">
                <div class="field"><label>ID Objeto</label><input type="text" value="${item.id}" onchange="config.housingConfig.placeableItems[${idx}].id = this.value"></div>
                <div class="field"><label>Nombre</label><input type="text" value="${item.name}" onchange="config.housingConfig.placeableItems[${idx}].name = this.value"></div>
                <div class="field"><label>Costo</label><input type="number" value="${item.cost}" onchange="config.housingConfig.placeableItems[${idx}].cost = parseInt(this.value)"></div>
                <div class="field">
                    <label>Moneda</label>
                    <select onchange="config.housingConfig.placeableItems[${idx}].currency = this.value" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%; cursor:pointer;">
                        <option value="hubs" ${item.currency === 'hubs' ? 'selected' : ''}>HUBS</option>
                        <option value="ohcu" ${item.currency === 'ohcu' ? 'selected' : ''}>OHCU</option>
                    </select>
                </div>
            </div>
            
            <div class="field full" style="margin-top:15px;">
                <label>Ruta Modelo 3D (.glb)</label>
                <div style="display:flex; gap:8px; align-items:center; width:100%;">
                    <input type="text" value="${item.model}" onchange="config.housingConfig.placeableItems[${idx}].model = this.value" style="font-family:'JetBrains Mono'; flex-grow:1; margin:0;">
                    <button class="btn btn-primary" style="padding:8px 12px; font-size:0.75rem; flex-shrink:0; background:var(--accent); border-color:var(--accent);" onclick="triggerAssetUpload(${idx}, 'housing_glb')">📁 SELECCIONAR GLB</button>
                </div>
            </div>

            <h5 style="color:var(--accent); margin:15px 0 5px; font-size:0.75rem; border-bottom:1px solid rgba(6,182,212,0.15); padding-bottom:2px;">⚙️ ROTACIÓN 3D INICIAL</h5>
            <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr 1fr; gap:10px; margin-bottom:15px; display:grid; align-items:center;">
                <div class="field"><label>Rotación X (grados)</label><input type="number" value="${item.rotX || 0}" onchange="config.housingConfig.placeableItems[${idx}].rotX = parseFloat(this.value) || 0"></div>
                <div class="field"><label>Rotación Y (grados)</label><input type="number" value="${item.rotY || 0}" onchange="config.housingConfig.placeableItems[${idx}].rotY = parseFloat(this.value) || 0"></div>
                <div class="field"><label>Rotación Z (grados)</label><input type="number" value="${item.rotZ || 0}" onchange="config.housingConfig.placeableItems[${idx}].rotZ = parseFloat(this.value) || 0"></div>
                <div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent; margin-top:20px; padding:0;">
                    <input type="checkbox" id="item-light-${idx}" ${item.isLight ? 'checked' : ''} onchange="config.housingConfig.placeableItems[${idx}].isLight = this.checked">
                    <label for="item-light-${idx}" style="margin-bottom:0; cursor:pointer; font-weight:bold;">¿Luz Dinámica?</label>
                </div>
            </div>
        `;
        list.appendChild(div);
    });
};

window.addHousingItem = function() {
    if (!config.housingConfig.placeableItems) config.housingConfig.placeableItems = [];
    config.housingConfig.placeableItems.push({
        id: "decor_" + Date.now().toString().slice(-4),
        name: "Nuevo Objeto 3D",
        cost: 100,
        currency: "hubs",
        model: "res://assets/3d/decor.glb",
        rotX: 0,
        rotY: 0,
        rotZ: 0,
        isLight: false
    });
    renderHousing();
};

window.removeHousingItem = function(idx) {
    if (!config.housingConfig.placeableItems) return;
    config.housingConfig.placeableItems.splice(idx, 1);
    renderHousing();
};

window.renderQuests = function() {
    if (!config.questsConfig) {
        config.questsConfig = JSON.parse(JSON.stringify(DEFAULT_QUESTS_CONFIG));
    }
    if (!config.questsGlobalConfig) {
        config.questsGlobalConfig = JSON.parse(JSON.stringify(DEFAULT_QUESTS_GLOBAL_CONFIG));
    }

    const maxActiveInput = document.getElementById('quests-max-active');
    if (maxActiveInput) {
        maxActiveInput.value = config.questsGlobalConfig.maxActiveQuests || 3;
    }
    
    const list = document.getElementById('quests-list');
    if (!list) return;
    list.innerHTML = '';
    
    const f = getFilter();
    
    config.questsConfig.forEach((quest, idx) => {
        if (f && !quest.name.toLowerCase().includes(f) && !quest.id.toLowerCase().includes(f) && !quest.desc.toLowerCase().includes(f)) return;
        
        const div = document.createElement('div');
        div.className = 'card';
        div.style.background = 'rgba(255,255,255,0.02)';
        div.style.padding = '1.5rem';
        div.style.border = '1px solid rgba(255,255,255,0.05)';
        div.style.position = 'relative';
        
        // Items render helper
        if (!quest.reward) quest.reward = { exp: 0, hubs: 0, ohcu: 0, items: [] };
        if (!quest.reward.items) quest.reward.items = [];
        
        let rewardItemsHTML = (quest.reward.items || []).map((item, itemIdx) => `
            <div style="display:flex; gap:10px; align-items:center; margin-bottom:5px; background:rgba(255,255,255,0.02); padding:5px; border-radius:6px;">
                <div class="field" style="margin:0; flex:2;"><label style="font-size:9px;">ID Ítem</label><input type="text" value="${item.id}" style="font-size:0.75rem; padding:4px;" onchange="config.questsConfig[${idx}].reward.items[${itemIdx}].id = this.value"></div>
                <div class="field" style="margin:0; flex:1;"><label style="font-size:9px;">Cant.</label><input type="number" value="${item.qty}" style="font-size:0.75rem; padding:4px;" onchange="config.questsConfig[${idx}].reward.items[${itemIdx}].qty = Math.floor(Math.max(1, parseInt(this.value) || 1))"></div>
                <button class="btn" style="background:var(--danger); border:none; padding:4px 8px; font-size:10px; margin-top:15px; cursor:pointer;" onclick="config.questsConfig[${idx}].reward.items.splice(${itemIdx}, 1); renderQuests();">✕</button>
            </div>
        `).join('');

        // Generar Select HTML para Objetivo según el tipo
        let targetSelectorHTML = '';
        if (quest.targetType === 'explore') {
            let mapOptions = `<option value="" ${!quest.targetId ? 'selected' : ''}>-- Seleccionar Mapa --</option>`;
            for (let mapId in config.mapsConfig) {
                mapOptions += `<option value="${mapId}" ${String(quest.targetId).trim().toLowerCase() === String(mapId).trim().toLowerCase() ? 'selected' : ''}>[Sector ${mapId}] ${config.mapsConfig[mapId].name}</option>`;
            }
            targetSelectorHTML = `
                <div class="field">
                    <label>Mapa a Explorar</label>
                    <select onchange="config.questsConfig[${idx}].targetId = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                        ${mapOptions}
                    </select>
                </div>
                <div class="form-grid" style="grid-template-columns: 1fr 1fr; gap:10px; width: 100%;">
                    <div class="field"><label>Coordenada X (Opcional)</label><input type="number" value="${quest.targetX !== undefined ? quest.targetX : ''}" placeholder="Ej: 2000" onchange="config.questsConfig[${idx}].targetX = this.value ? Math.floor(parseInt(this.value)) : undefined"></div>
                    <div class="field"><label>Coordenada Y (Opcional)</label><input type="number" value="${quest.targetY !== undefined ? quest.targetY : ''}" placeholder="Ej: 2000" onchange="config.questsConfig[${idx}].targetY = this.value ? Math.floor(parseInt(this.value)) : undefined"></div>
                </div>
            `;
        } else if (quest.targetType === 'kill') {
            let enemyOptions = `<option value="" ${!quest.targetId ? 'selected' : ''}>-- Seleccionar Enemigo --</option>`;
            for (let enemyId in config.enemyModels) {
                // Traer absolutamente todos los monstruos incluyendo sub-tiers (1-D, 2-C, etc)
                enemyOptions += `<option value="${enemyId}" ${String(quest.targetId).trim().toLowerCase() === String(enemyId).trim().toLowerCase() ? 'selected' : ''}>[ID ${enemyId}] ${config.enemyModels[enemyId].name}</option>`;
            }
            targetSelectorHTML = `
                <div class="field">
                    <label>Monstruo / Enemigo</label>
                    <select onchange="config.questsConfig[${idx}].targetId = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                        ${enemyOptions}
                    </select>
                </div>
            `;
        } else if (quest.targetType === 'event') {
            const eventOptions = `
                <option value="" ${!quest.targetId ? 'selected' : ''}>-- Seleccionar Evento --</option>
                <option value="extraction_win" ${String(quest.targetId).trim().toLowerCase() === 'extraction_win' ? 'selected' : ''}>🏆 Ganar Extracción (F2)</option>
                <option value="altar_defense_win" ${String(quest.targetId).trim().toLowerCase() === 'altar_defense_win' ? 'selected' : ''}>🗼 Completar Defensa del Altar</option>
                <option value="arena_win" ${String(quest.targetId).trim().toLowerCase() === 'arena_win' ? 'selected' : ''}>⚔️ Ganar Arena PVP</option>
            `;
            targetSelectorHTML = `
                <div class="field">
                    <label>Evento Requerido</label>
                    <select onchange="config.questsConfig[${idx}].targetId = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                        ${eventOptions}
                    </select>
                </div>
            `;
        } else if (quest.targetType === 'housing') {
            let housingOptions = `<option value="" ${!quest.targetId ? 'selected' : ''}>-- Seleccionar Objeto --</option>`;
            if (config.housingConfig && Array.isArray(config.housingConfig.placeableItems)) {
                config.housingConfig.placeableItems.forEach(item => {
                    housingOptions += `<option value="${item.id}" ${String(quest.targetId).trim().toLowerCase() === String(item.id).trim().toLowerCase() ? 'selected' : ''}>🏠 ${item.name} (ID: ${item.id})</option>`;
                });
            }
            targetSelectorHTML = `
                <div class="field">
                    <label>Objeto de Housing</label>
                    <select onchange="config.questsConfig[${idx}].targetId = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                        ${housingOptions}
                    </select>
                </div>
            `;
        } else {
            // Recolectar items o genérico
            targetSelectorHTML = `
                <div class="field">
                    <label>ID del Ítem</label>
                    <input type="text" value="${quest.targetId || ''}" placeholder="Ej: w_laser_1" onchange="config.questsConfig[${idx}].targetId = this.value">
                </div>
            `;
        }

        div.innerHTML = `
            <div style="position:absolute; top:15px; right:15px;">
                <button class="btn btn-secondary" style="background:var(--danger); border:none; padding:4px 10px;" onclick="removeQuest(${idx})">✕ ELIMINAR MISIÓN</button>
            </div>
            
            <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr; gap:15px;">
                <div class="field"><label>ID Misión</label><input type="text" value="${quest.id}" onchange="config.questsConfig[${idx}].id = this.value"></div>
                <div class="field"><label>Nombre</label><input type="text" value="${quest.name}" onchange="config.questsConfig[${idx}].name = this.value"></div>
                <div class="field">
                    <label>Clasificación</label>
                    <select onchange="config.questsConfig[${idx}].type = this.value; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                        <option value="story" ${quest.type === 'story' ? 'selected' : ''}>Historia 📖</option>
                        <option value="daily" ${quest.type === 'daily' ? 'selected' : ''}>Diaria ⏳</option>
                        <option value="weekly" ${quest.type === 'weekly' ? 'selected' : ''}>Semanal 📅</option>
                    </select>
                </div>
            </div>
            
            <div class="field full" style="margin-top:10px;"><label>Descripción</label><input type="text" value="${quest.desc}" onchange="config.questsConfig[${idx}].desc = this.value"></div>
            
            <div style="margin-top:1.5rem; padding-top:1.2rem; border-top:1px solid rgba(255,255,255,0.05); display:grid; grid-template-columns: 1.2fr 1fr; gap:2rem;">
                <!-- Columna Objetivo -->
                <div>
                    <h4 style="color:var(--accent); font-size:0.8rem; font-weight:bold; margin-bottom:10px;">🎯 OBJETIVO DE LA MISIÓN</h4>
                    <div class="form-grid" style="grid-template-columns: 1fr; gap:12px;">
                        <div class="field">
                            <label>Tipo de Objetivo</label>
                            <select onchange="config.questsConfig[${idx}].targetType = this.value; config.questsConfig[${idx}].targetId = ''; renderQuests();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width: 100%;">
                                <option value="kill" ${quest.targetType === 'kill' ? 'selected' : ''}>⚔️ Matar Enemigos</option>
                                <option value="collect" ${quest.targetType === 'collect' ? 'selected' : ''}>📦 Recolectar Ítems</option>
                                <option value="explore" ${quest.targetType === 'explore' ? 'selected' : ''}>🗺️ Explorar Zona</option>
                                <option value="event" ${quest.targetType === 'event' ? 'selected' : ''}>🏆 Evento Especial</option>
                                <option value="housing" ${quest.targetType === 'housing' ? 'selected' : ''}>🏠 Colocar Housing</option>
                            </select>
                        </div>
                        
                        ${targetSelectorHTML}
                        
                        <div class="field">
                            <label>Cantidad Requerida</label>
                            <input type="number" value="${quest.targetAmount || 1}" onchange="config.questsConfig[${idx}].targetAmount = Math.floor(Math.max(1, parseInt(this.value) || 1))">
                        </div>
                    </div>
                </div>
                
                <!-- Columna Recompensas -->
                <div>
                    <h4 style="color:var(--success); font-size:0.8rem; font-weight:bold; margin-bottom:10px;">🎁 RECOMPENSAS</h4>
                    <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr; gap:10px; margin-bottom:15px;">
                        <div class="field"><label>EXP</label><input type="number" value="${quest.reward.exp}" onchange="config.questsConfig[${idx}].reward.exp = Math.floor(Math.max(0, parseInt(this.value) || 0))"></div>
                        <div class="field"><label>HUBS</label><input type="number" value="${quest.reward.hubs}" onchange="config.questsConfig[${idx}].reward.hubs = Math.floor(Math.max(0, parseInt(this.value) || 0))"></div>
                        <div class="field"><label>OHCU</label><input type="number" value="${quest.reward.ohcu}" onchange="config.questsConfig[${idx}].reward.ohcu = Math.floor(Math.max(0, parseInt(this.value) || 0))"></div>
                    </div>
                    
                    <div>
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                            <label style="font-size:0.75rem; color:#aaa; font-weight:bold;">📦 Ítems Recompensa</label>
                            <button class="btn btn-primary" style="padding:2px 8px; font-size:9px;" onclick="config.questsConfig[${idx}].reward.items.push({id:'', qty:1}); renderQuests();">+ Añadir Ítem</button>
                        </div>
                        <div style="max-height:120px; overflow-y:auto; padding-right:5px;">
                            ${rewardItemsHTML}
                        </div>
                    </div>
                </div>
            </div>
        `;
        list.appendChild(div);
    });
};

window.addNewQuest = function() {
    if (!config.questsConfig) config.questsConfig = [];
    config.questsConfig.push({
        id: "quest_" + Date.now().toString().slice(-4),
        name: "Nueva Misión Galáctica",
        desc: "Descripción de la misión.",
        type: "story",
        targetType: "kill",
        targetId: "",
        targetAmount: 5,
        reward: {
            exp: 100,
            hubs: 500,
            ohcu: 1,
            items: []
        }
    });
    renderQuests();
};

window.removeQuest = function(idx) {
    if (!config.questsConfig) return;
    config.questsConfig.splice(idx, 1);
    renderQuests();
};

window.triggerAssetUpload = function(idx, type = 'resource') {
    const input = document.createElement('input');
    input.type = 'file';

    // Tipos que NO deben copiar el archivo — solo resuelven la ruta res://
    const resolveOnlyTypes = ['ship_glb', 'ship_icon', 'housing_glb', 'skill_icon', 'talent_icon', 'weapon_icon', 'shield_icon', 'engine_icon', 'ammo_icon'];
    const isResolveOnly = resolveOnlyTypes.includes(type);

    if (type === 'ship_glb' || type === 'housing_glb') {
        input.accept = '.glb';
    } else {
        input.accept = 'image/*';
    }

    input.onchange = async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';

        // ── MODO RESOLVE-ONLY: Solo buscar el archivo en el proyecto, sin copiarlo ──
        if (isResolveOnly) {
            try {
                const response = await fetch(`${activeURL}/api/find-asset?fileName=${encodeURIComponent(file.name)}`);
                const result = await response.json();

                if (result.success && result.path) {
                    if (type === 'ship_icon') {
                        config.shipModels[idx].icon = result.path;
                    } else if (type === 'ship_glb') {
                        config.shipModels[idx].assetPath = result.path;
                    } else if (type === 'housing_glb') {
                        config.housingConfig.placeableItems[idx].model = result.path;
                    } else if (type === 'skill_icon') {
                        // idx = skill name (key in skillsData)
                        if (!config.skillsData[idx]) config.skillsData[idx] = {};
                        config.skillsData[idx].icon = result.path;
                    } else if (type === 'weapon_icon') {
                        config.shopItems.weapons[idx].icon = result.path;
                    } else if (type === 'shield_icon') {
                        config.shopItems.shields[idx].icon = result.path;
                    } else if (type === 'engine_icon') {
                        config.shopItems.engines[idx].icon = result.path;
                    } else if (type === 'ammo_icon') {
                        if (!config.shopItems.ammo_icons) config.shopItems.ammo_icons = {};
                        config.shopItems.ammo_icons[idx] = result.path;
                    } else if (type === 'talent_icon') {
                        config.talentsConfig.talents[idx].icon = result.path;
                    }
                    if (type === 'ship_icon' || type === 'ship_glb') {
                        renderShips();
                    } else if (type === 'housing_glb') {
                        renderHousing();
                    } else if (type === 'weapon_icon') {
                        renderWeapons();
                    } else if (type === 'shield_icon') {
                        renderShields();
                    } else if (type === 'engine_icon') {
                        renderEngines();
                    } else if (type === 'ammo_icon') {
                        renderAmmo();
                    } else if (type === 'skill_icon') {
                        renderSkills();
                    } else if (type === 'talent_icon') {
                        renderTalentCreator();
                    }
                } else {
                    alert('❌ ' + (result.error || 'No se pudo encontrar el archivo en los assets del proyecto.\n\nAsegurate de que el archivo ya esté copiado dentro de la carpeta descon/assets antes de seleccionarlo.'));
                }
            } catch (err) {
                console.error(err);
                alert('Error al conectar con el servidor local para resolver la ruta del asset.');
            }
            return; // No continuar con el flujo de upload
        }

        // ── MODO UPLOAD: Leer el archivo y copiarlo al servidor (crafteo / recursos) ──
        const reader = new FileReader();
        reader.onload = async () => {
            const base64Data = reader.result.split(',')[1];
            
            try {
                const response = await fetch(`${activeURL}/api/upload-asset`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        fileName: file.name,
                        fileData: base64Data
                    })
                });
                
                const result = await response.json();
                if (result.success && result.path) {
                    if (type === 'resource') {
                        config.shopItems.resources[idx].icon = result.path;
                    } else if (type === 'recipe') {
                        config.craftingRecipes[idx].icon = result.path;
                    }
                    
                    // Solicitar la lista de assets actualizada mediante socket
                    const activeSocket = (activeEnv === 'cloud') ? socketCloud : socketLocal;
                    if (activeSocket && activeSocket.connected) {
                        activeSocket.emit('getAssetFiles');
                    }
                    
                    alert('Asset importado con éxito!');
                    renderCrafting();
                } else {
                    alert('Error al importar el asset: ' + (result.error || 'Desconocido'));
                }
            } catch (err) {
                console.error(err);
                alert('Error al conectar con el servidor para subir el archivo.');
            }
        };
        reader.readAsDataURL(file);
    };
    input.click();
};

// ─── ASSET PICKER ───────────────────────────────────────────────────────────
window._assetPickerState = { idx: 0, type: 'resource' };

window.openAssetPicker = function(idx, type) {
    window.triggerAssetUpload(idx, type);
};

window.closeAssetPicker = function() {
    const overlay = document.getElementById('asset-picker-overlay');
    if (overlay) overlay.style.display = 'none';
};

// Seleccionar GLB para un objeto del mundo (chest, door, tower, wall) sin copiar el archivo
window.triggerMapObjAssetPick = async function(mapId, objIdx) {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.glb,.png,.jpg,.webp';
    input.onchange = async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';
        try {
            const response = await fetch(`${activeURL}/api/find-asset?fileName=${encodeURIComponent(file.name)}`);
            const result = await response.json();
            if (result.success && result.path) {
                config.mapsConfig[mapId].objects[objIdx].assetPath = result.path;
                renderMapDetail();
            } else {
                alert('❌ ' + (result.error || 'Archivo no encontrado en los assets del proyecto.\n\nAsegurate de que el archivo ya esté dentro de la carpeta descon/assets.'));
            }
        } catch (err) {
            console.error(err);
            alert('Error al conectar con el servidor local.');
        }
    };
    input.click();
};

// Confirm selection from asset picker
window.confirmAssetPicker = function() {
    const select = document.getElementById('asset-picker-select');
    if (!select) return;
    const chosen = select.value;
    if (chosen) {
        selectAssetFromPicker(chosen);
    }
};

window.filterAssetPicker = function() {
    const activeURL = SERVER_URLS[activeEnv] || 'http://127.0.0.1:3333';
    const select = document.getElementById('asset-picker-select');
    const countEl = document.getElementById('asset-picker-count');
    if (!select) return;

    const query = (document.getElementById('asset-picker-search')?.value || '').toLowerCase();
    const folderFilter = (document.getElementById('asset-picker-folder')?.value || '').toLowerCase();
    const allFiles = window.allAssetFiles || [];

    const filtered = allFiles.filter(p => {
        const lower = p.toLowerCase();
        const folderMatch = !folderFilter || lower.includes('/' + folderFilter + '/');
        const searchMatch = !query || lower.includes(query);
        return folderMatch && searchMatch;
    });

    if (countEl) countEl.textContent = `${filtered.length} asset${filtered.length !== 1 ? 's' : ''}`;

    // Clear previous options
    select.innerHTML = '';
    if (filtered.length === 0) {
        const opt = document.createElement('option');
        opt.textContent = 'No se encontraron assets';
        opt.disabled = true;
        select.appendChild(opt);
        return;
    }

    filtered.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p;
        const filename = p.split('/').pop();
        opt.textContent = filename;
        select.appendChild(opt);
    });

};

window.selectAssetFromPicker = function(path) {
    const { idx, type } = window._assetPickerState;
    if (type === 'resource') {
        config.shopItems.resources[idx].icon = path;
    } else if (type === 'recipe') {
        config.craftingRecipes[idx].icon = path;
    }
    closeAssetPicker();
    renderCrafting();
};

window.showLootTabForEnemy = function(enemyId) {
    window.selectedLootEnemyId = enemyId;
    showTab('enemy-loot');
};

window.renderLootTableComponent = function(enemyId, containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const en = config.enemyModels[enemyId];
    if (!en) return;
    if (!en.lootDrops) en.lootDrops = [];

    const allItems = [
        ...(config.shopItems?.weapons || []),
        ...(config.shopItems?.shields || []),
        ...(config.shopItems?.engines || []),
        ...(config.shopItems?.extra || []),
        ...(config.shopItems?.resources || []).map(r => ({ ...r, type: 'resource' })),
        ...(config.craftingRecipes || []).map(rc => ({ ...rc, type: 'recipe' }))
    ];

    container.innerHTML = `
        <div style="display: grid; grid-template-columns: 1fr; gap: 10px;">
            ${en.lootDrops.length === 0 ? `
                <div style="color: var(--text-dim); font-size: 0.8rem; padding: 1.5rem; text-align: center; background: rgba(255,255,255,0.01); border-radius: 6px; border: 1px dashed rgba(255,255,255,0.08);">
                    ⚠️ No hay drops configurados para este enemigo. Agregá ítems con el botón.
                </div>
            ` : en.lootDrops.map((ld, idx) => {
                const selectedItem = allItems.find(it => it.id === ld.itemId);
                const chancePercent = Math.round((ld.chance || 0.1) * 100);
                const barColor = chancePercent >= 50 ? 'var(--success)' : (chancePercent >= 20 ? 'var(--primary)' : 'var(--accent)');
                return `
                <div style="background: rgba(255,255,255,0.02); padding: 1rem 1.2rem; border-radius: 10px; border: 1px solid rgba(255,255,255,0.05); display: grid; grid-template-columns: 2fr 1fr 80px auto; gap: 15px; align-items: center; transition: all 0.2s;" onmouseenter="this.style.borderColor='rgba(6,182,212,0.3)'; this.style.background='rgba(6,182,212,0.03)'" onmouseleave="this.style.borderColor='rgba(255,255,255,0.05)'; this.style.background='rgba(255,255,255,0.02)'">
                    <div style="display: flex; flex-direction: column; gap: 4px;">
                        <label style="font-size: 0.6rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 1px;">ÍTEM DE RECOMPENSA</label>
                        <input type="text" placeholder="🔍 Buscar por nombre o ID..." style="background: #0a0e1a; border: 1px solid rgba(255,255,255,0.08); color: white; border-radius: 6px; padding: 6px 10px; font-size: 0.75rem; margin-bottom: 4px;" oninput="
                            const query = this.value.toLowerCase().trim();
                            const select = this.nextElementSibling;
                            for (let opt of select.options) {
                                if (opt.value === '') continue;
                                const text = opt.textContent.toLowerCase();
                                const val = opt.value.toLowerCase();
                                const isMatch = text.includes(query) || val.includes(query);
                                opt.style.display = isMatch ? '' : 'none';
                            }
                        ">
                        <select style="background: #0a0e1a; border: 1px solid rgba(255,255,255,0.08); color: white; font-weight: bold; cursor: pointer; width: 100%; border-radius: 6px; padding: 8px 10px; font-size: 0.85rem;" onchange="updateLootDropItemFromComponent('${enemyId}', ${idx}, this.value, '${containerId}')">
                            <option value="">-- Seleccionar Item --</option>
                            ${allItems.map(it => `<option value="${it.id}" ${ld.itemId === it.id ? 'selected' : ''}>[${(it.type || 'MOD').toUpperCase()}] ${it.name} (${it.id})</option>`).join('')}
                        </select>
                        ${selectedItem ? `<span style="font-size: 0.65rem; color: var(--text-dim);">Tipo: ${(selectedItem.type || 'módulo').toUpperCase()} | Rareza: ${selectedItem.rarity || 0}</span>` : ''}
                    </div>
                    <div style="display: flex; flex-direction: column; gap: 4px;">
                        <label style="font-size: 0.65rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 1px;">PROBABILIDAD</label>
                        <div style="display: flex; align-items: center; gap: 8px;">
                            <input type="number" min="0" max="100" step="1" value="${chancePercent}" style="background: #0a0e1a; border: 1px solid rgba(255,255,255,0.08); color: white; border-radius: 6px; padding: 8px 10px; width: 80px; font-size: 0.9rem; font-weight: bold;" onchange="updateLootDropChanceFromComponent('${enemyId}', ${idx}, this.value, '${containerId}')">
                            <span style="font-size: 0.85rem; color: var(--text-dim);">%</span>
                        </div>
                        <div style="height: 4px; background: rgba(255,255,255,0.05); border-radius: 2px; overflow: hidden; margin-top: 4px;">
                            <div style="height: 100%; width: ${chancePercent}%; background: ${barColor}; border-radius: 2px; transition: width 0.3s;"></div>
                        </div>
                    </div>
                    <div style="display: flex; flex-direction: column; align-items: center; gap: 2px;">
                        <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size: 1.2rem; font-weight: bold; margin-top: 15px;" onclick="removeLootDropFromComponent('${enemyId}', ${idx}, '${containerId}')">✕</button>
                    </div>
                </div>
                `;
            }).join('')}
        </div>
    `;
};

window.addLootDropFromComponent = function(enemyId, containerId) {
    const en = config.enemyModels[enemyId];
    if (!en) return;
    if (!en.lootDrops) en.lootDrops = [];
    en.lootDrops.push({ itemId: '', chance: 0.1 });
    if (containerId === 'enemy-loot-detail-container') {
        renderEnemyLootDetail();
    } else {
        renderEnemyDetail();
    }
};

window.updateLootDropItemFromComponent = function(enemyId, idx, value, containerId) {
    const en = config.enemyModels[enemyId];
    if (!en || !en.lootDrops[idx]) return;
    en.lootDrops[idx].itemId = value;
    if (containerId === 'enemy-loot-detail-container') {
        renderEnemyLootDetail();
    } else {
        renderEnemyDetail();
    }
};

window.updateLootDropChanceFromComponent = function(enemyId, idx, value, containerId) {
    const en = config.enemyModels[enemyId];
    if (!en || !en.lootDrops[idx]) return;
    en.lootDrops[idx].chance = (parseFloat(value) || 0) / 100;
    if (containerId === 'enemy-loot-detail-container') {
        renderEnemyLootDetail();
    } else {
        renderEnemyDetail();
    }
};
window.removeLootDropFromComponent = function(enemyId, idx, containerId) {
    const en = config.enemyModels[enemyId];
    if (!en || !en.lootDrops) return;
    en.lootDrops.splice(idx, 1);
    if (containerId === 'enemy-loot-detail-container') {
        renderEnemyLootDetail();
    } else {
        renderEnemyDetail();
    }
};

window.renderTalentCreator = function() {
    const grid = document.getElementById('talents-creator-grid');
    if (!grid) return;
    grid.innerHTML = '';

    const f = getFilter();
    const talents = config.talentsConfig.talents || [];

    talents.forEach((t, idx) => {
        if (f && !t.name.toLowerCase().includes(f) && !t.desc.toLowerCase().includes(f)) return;

        const isPlaced = config.talentsConfig.nodes && config.talentsConfig.nodes[t.id];
        const statusBadge = isPlaced 
            ? `<span style="background:rgba(16,185,129,0.15); color:#10b981; border:1px solid rgba(16,185,129,0.3); padding:3px 8px; border-radius:4px; font-size:0.75rem; font-weight:bold;">📍 MAPEADO</span>` 
            : `<span style="background:rgba(239,68,68,0.15); color:#ef4444; border:1px solid rgba(239,68,68,0.3); padding:3px 8px; border-radius:4px; font-size:0.75rem; font-weight:bold;">⚠️ NO MAPEADO</span>`;

        const card = document.createElement('div');
        card.className = 'card';
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; border-bottom:1px solid rgba(255,255,255,0.05); padding-bottom:8px;">
                <div style="font-family:'JetBrains Mono'; font-size:0.75rem; color:#888;">ID: ${t.id}</div>
                <div style="display:flex; gap:10px; align-items:center;">
                    ${statusBadge}
                    <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-weight:bold; font-size:0.8rem;" onclick="deleteTalent('${t.id}')">✕ ELIMINAR</button>
                </div>
            </div>

            <div class="form-grid" style="display:grid; grid-template-columns: 80px 1fr; gap:12px;">
                <div class="field" style="display:flex; flex-direction:column; gap:4px; align-items:center;">
                    <label style="width:100%;">Icono</label>
                    <input type="text" value="${t.icon || '🌳'}" style="font-size:1.5rem; text-align:center; width:100%;" onchange="config.talentsConfig.talents[${idx}].icon = this.value; renderTalentCreator();">
                    <button class="btn" style="padding:2px 4px; font-size:0.6rem; background:rgba(0,210,255,0.08); border:1px solid rgba(0,210,255,0.25); color:var(--primary); cursor:pointer; border-radius:4px; width:100%; text-align:center;" onclick="triggerAssetUpload(${idx}, 'talent_icon')">🖼️ PNG</button>
                </div>
                <div class="field">
                    <label>Nombre del Talento</label>
                    <input type="text" value="${t.name}" onchange="config.talentsConfig.talents[${idx}].name = this.value">
                </div>
            </div>

            <div class="field full" style="margin-top:10px;">
                <label>Descripción</label>
                <textarea rows="2" style="width:100%; background:var(--surface); border:1px solid rgba(255,255,255,0.1); border-radius:8px; color:white; padding:8px;" onchange="config.talentsConfig.talents[${idx}].desc = this.value">${t.desc}</textarea>
            </div>

            <div class="form-grid" style="display:grid; grid-template-columns: 1fr 1fr; gap:12px; margin-top:10px;">
                <div class="field">
                    <label>Categoría</label>
                    <select onchange="config.talentsConfig.talents[${idx}].category = this.value; renderTalentCreator();" style="width:100%; background:var(--surface); border:1px solid rgba(255,255,255,0.1); border-radius:8px; color:white; padding:10px;">
                        <option value="engineering" ${t.category==='engineering'?'selected':''}>🛠️ Ingeniería</option>
                        <option value="combat" ${t.category==='combat'?'selected':''}>⚔️ Combate</option>
                        <option value="science" ${t.category==='science'?'selected':''}>🔬 Ciencia</option>
                    </select>
                </div>
                <div class="field">
                    <label>Nivel Máximo</label>
                    <input type="number" value="${t.maxLevel || 5}" onchange="config.talentsConfig.talents[${idx}].maxLevel = parseInt(this.value)">
                </div>
            </div>

            <div style="margin-top:15px; border-top:1px solid #333; padding-top:10px;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                    <label style="color:var(--accent); font-size:0.75rem; font-weight:bold;">⚡ EFECTOS Y BUFFS (POR NIVEL)</label>
                    <button class="btn btn-primary" style="padding:2px 8px; font-size:0.65rem;" onclick="addTalentEffect(${idx})">+ EFECTO</button>
                </div>
                <div id="talent-effects-${idx}">
                    ${Object.entries(t.effects || {}).map(([key, val]) => `
                        <div style="display:flex; gap:8px; align-items:center; margin-bottom:6px; background:rgba(255,255,255,0.02); padding:6px; border-radius:6px; border:1px solid rgba(255,255,255,0.05);">
                            <select style="flex:1; background:transparent; border:none; color:white; font-size:0.8rem;" onchange="updateTalentEffectKey(${idx}, '${key}', this.value)">
                                <option value="hp_pct" ${key==='hp_pct'?'selected':''}>Vida Máxima (+%)</option>
                                <option value="sh_pct" ${key==='sh_pct'?'selected':''}>Escudo Máximo (+%)</option>
                                <option value="hp_regen" ${key==='hp_regen'?'selected':''}>HP Reparación (+%)</option>
                                <option value="shield_regen" ${key==='shield_regen'?'selected':''}>Regen Escudo (+%)</option>
                                <option value="armor_pct" ${key==='armor_pct'?'selected':''}>Armadura Total (+%)</option>
                                <option value="energy_efficiency" ${key==='energy_efficiency'?'selected':''}>Eficiencia Energía (+%)</option>
                                <option value="repair_cost_reduction" ${key==='repair_cost_reduction'?'selected':''}>Costo Reparación (-%)</option>
                                <option value="stability" ${key==='stability'?'selected':''}>Estabilidad Vuelo (+%)</option>
                                <option value="laser_dmg_pct" ${key==='laser_dmg_pct'?'selected':''}>Daño Láser (+%)</option>
                                <option value="crit_chance" ${key==='crit_chance'?'selected':''}>Prob. Crítico (+%)</option>
                                <option value="crit_dmg" ${key==='crit_dmg'?'selected':''}>Daño Crítico (+%)</option>
                                <option value="ammo_bonus_pct" ${key==='ammo_bonus_pct'?'selected':''}>Munición Extra (+%)</option>
                                <option value="accuracy_pct" ${key==='accuracy_pct'?'selected':''}>Puntería (+%)</option>
                                <option value="ignore_shield_pct" ${key==='ignore_shield_pct'?'selected':''}>Perforación Escudo (+%)</option>
                                <option value="fire_rate_pct" ${key==='fire_rate_pct'?'selected':''}>Cadencia Disparo (+%)</option>
                                <option value="evasion_pct" ${key==='evasion_pct'?'selected':''}>Evasión Combate (+%)</option>
                                <option value="speed_pct" ${key==='speed_pct'?'selected':''}>Velocidad Base (+%)</option>
                                <option value="minimap_range" ${key==='minimap_range'?'selected':''}>Rango Minimapa (+%)</option>
                                <option value="ohcu_kill_bonus" ${key==='ohcu_kill_bonus'?'selected':''}>Bonus OHCU Kills (+%)</option>
                                <option value="shop_discount" ${key==='shop_discount'?'selected':''}>Descuento Tienda (+%)</option>
                                <option value="cooldown_reduction" ${key==='cooldown_reduction'?'selected':''}>CD Habilidades (-%)</option>
                                <option value="group_bonus" ${key==='group_bonus'?'selected':''}>Bonus en Grupo (+%)</option>
                                <option value="boss_loot_bonus" ${key==='boss_loot_bonus'?'selected':''}>Loot de Bosses (+%)</option>
                                <option value="dash_distance" ${key==='dash_distance'?'selected':''}>Distancia Dash (+%)</option>
                            </select>
                            <input type="number" step="0.001" value="${val}" style="width:90px; text-align:right; font-size:0.8rem; padding:4px;" onchange="config.talentsConfig.talents[${idx}].effects['${key}'] = parseFloat(this.value)">
                            <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="deleteTalentEffect(${idx}, '${key}')">✕</button>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        grid.appendChild(card);
    });
};

window.addTalentEffect = function(talentIdx) {
    const t = config.talentsConfig.talents[talentIdx];
    if (!t.effects) t.effects = {};
    const unusedKeys = ['hp_pct', 'sh_pct', 'dmg_pct', 'speed_pct', 'crit_chance', 'crit_dmg', 'cooldown_reduction'].filter(k => !t.effects[k]);
    const keyToAdd = unusedKeys.length > 0 ? unusedKeys[0] : 'custom_stat_' + Date.now();
    t.effects[keyToAdd] = 0.01;
    renderTalentCreator();
};

window.updateTalentEffectKey = function(talentIdx, oldKey, newKey) {
    const t = config.talentsConfig.talents[talentIdx];
    if (t.effects[newKey] !== undefined) return; // Clave duplicada
    const val = t.effects[oldKey];
    delete t.effects[oldKey];
    t.effects[newKey] = val;
    renderTalentCreator();
};

window.deleteTalentEffect = function(talentIdx, key) {
    const t = config.talentsConfig.talents[talentIdx];
    delete t.effects[key];
    renderTalentCreator();
};

window.renderTalentMapper = function(connectingMousePos = null) {
    const canvas = document.getElementById('talent-mapper-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');

    // Limpiar canvas
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Dibujar rejilla (Grid)
    ctx.strokeStyle = 'rgba(0, 210, 255, 0.04)';
    ctx.lineWidth = 1;
    const gridSpacing = 40;
    const offsetX = talentPanOffset.x % gridSpacing;
    const offsetY = talentPanOffset.y % gridSpacing;

    for (let x = offsetX; x < canvas.width; x += gridSpacing) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, canvas.height);
        ctx.stroke();
    }
    for (let y = offsetY; y < canvas.height; y += gridSpacing) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(canvas.width, y);
        ctx.stroke();
    }

    // Dibujar Conexiones Existentes
    const connections = config.talentsConfig.connections || [];
    const nodes = config.talentsConfig.nodes || {};

    ctx.lineWidth = 3;
    connections.forEach(conn => {
        const fromNode = nodes[conn.from];
        const toNode = nodes[conn.to];
        if (fromNode && toNode) {
            const startX = fromNode.x + talentPanOffset.x;
            const startY = fromNode.y + talentPanOffset.y;
            const endX = toNode.x + talentPanOffset.x;
            const endY = toNode.y + talentPanOffset.y;

            // Gradiente cian neón para las conexiones
            const grad = ctx.createLinearGradient(startX, startY, endX, endY);
            grad.addColorStop(0, 'rgba(0, 210, 255, 0.6)');
            grad.addColorStop(1, 'rgba(6, 182, 212, 0.6)');
            
            ctx.strokeStyle = grad;
            ctx.shadowColor = 'rgba(0, 210, 255, 0.5)';
            ctx.shadowBlur = 8;
            ctx.beginPath();
            ctx.moveTo(startX, startY);
            ctx.lineTo(endX, endY);
            ctx.stroke();
            ctx.shadowBlur = 0; // Reset
        }
    });

    // Dibujar previsualización de conexión en progreso
    if (connectStartNodeId && connectingMousePos && nodes[connectStartNodeId]) {
        const startNode = nodes[connectStartNodeId];
        const startX = startNode.x + talentPanOffset.x;
        const startY = startNode.y + talentPanOffset.y;

        ctx.strokeStyle = 'rgba(255, 215, 0, 0.8)';
        ctx.lineWidth = 2;
        ctx.setLineDash([5, 5]);
        ctx.beginPath();
        ctx.moveTo(startX, startY);
        ctx.lineTo(connectingMousePos.x, connectingMousePos.y);
        ctx.stroke();
        ctx.setLineDash([]); // Reset
    }

    // Dibujar Nodos
    const talents = config.talentsConfig.talents || [];
    ctx.shadowBlur = 0;

    for (const [id, pos] of Object.entries(nodes)) {
        const t = talents.find(x => x.id === id);
        if (!t) continue;

        const screenX = pos.x + talentPanOffset.x;
        const screenY = pos.y + talentPanOffset.y;

        // Determinar colores por categoría
        let catColor = '#00d2ff'; // Engineering
        if (t.category === 'combat') catColor = '#ff3131';
        else if (t.category === 'science') catColor = '#be31ff';

        const isSelected = selectedTalentNodeId === id;

        // Efecto glow si está seleccionado
        if (isSelected) {
            ctx.shadowColor = catColor;
            ctx.shadowBlur = 15;
            ctx.strokeStyle = '#ffffff';
            ctx.lineWidth = 4;
        } else {
            ctx.strokeStyle = catColor;
            ctx.lineWidth = 2;
        }

        // Círculo del Nodo
        ctx.fillStyle = '#060d1a';
        ctx.beginPath();
        ctx.arc(screenX, screenY, 30, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        ctx.shadowBlur = 0; // Reset

        // Emoji en el centro
        ctx.font = '22px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(t.icon || '🌳', screenX, screenY);

        // Nombre del talento abajo
        ctx.font = 'bold 11px Outfit, sans-serif';
        ctx.fillStyle = isSelected ? '#ffffff' : 'rgba(255, 255, 255, 0.8)';
        ctx.fillText(t.name, screenX, screenY + 45);
    }

    // Renderizar listado de talentos no colocados en el panel lateral
    const unplacedList = document.getElementById('talent-mapper-unplaced-list');
    if (unplacedList) {
        unplacedList.innerHTML = '';
        talents.forEach(t => {
            if (nodes[t.id]) return; // Ya colocado

            const item = document.createElement('div');
            item.className = 'card';
            item.style.padding = '10px';
            item.style.margin = '0';
            item.style.cursor = 'pointer';
            item.style.display = 'flex';
            item.style.alignItems = 'center';
            item.style.justifyContent = 'space-between';
            item.style.border = '1px solid rgba(255,255,255,0.05)';
            item.style.background = 'rgba(255,255,255,0.02)';
            
            // Doble click para colocar
            item.ondblclick = () => placeTalentOnMap(t.id);
            
            item.innerHTML = `
                <div style="display:flex; gap:10px; align-items:center;">
                    <span style="font-size:1.5rem;">${t.icon || '🌳'}</span>
                    <div>
                        <div style="font-weight:bold; font-size:0.85rem; color:var(--text);">${t.name}</div>
                        <div style="font-size:0.7rem; color:var(--text-dim);">${t.category.toUpperCase()}</div>
                    </div>
                </div>
                <button class="btn btn-primary" style="padding:4px 8px; font-size:0.7rem; margin:0;" onclick="placeTalentOnMap('${t.id}')">Colocar</button>
            `;
            unplacedList.appendChild(item);
        });

        if (unplacedList.children.length === 0) {
            unplacedList.innerHTML = '<div style="color:var(--text-dim); text-align:center; padding:2rem; font-size:0.85rem;">Todos los talentos han sido mapeados.</div>';
        }
    }

    // Inicializar canvas del mapper la primera vez que se renderice
    if (!canvas.onmousedown) {
        initTalentMapper();
    }
};

// ─── TOGLE ACTIVAR ───
window.toggleTimeRestrictions = function(mapId, enabled) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId]) return;
    config.mapsConfig[mapId].timeRestrictionsEnabled = enabled;
    if (enabled && !config.mapsConfig[mapId].allowedHours) {
        config.mapsConfig[mapId].allowedHours = [];
    }
    saveConfig();
    renderMapDetail();
};

// ─── HELPERS DE DÍAS ───
window._toggleNewAllDays = function() {
    const allCb = document.getElementById('new-day-all');
    const isChecked = allCb.checked;
    [0,1,2,3,4,5,6].forEach(i => {
        const cb = document.getElementById('new-day-' + i);
        if (cb) cb.checked = isChecked;
    });
};

window._updateGroupDays = function(gIdx) {
    const dayCbs = [0,1,2,3,4,5,6].map(i => document.querySelector(`.edit-grp-day-${gIdx}[value="${i}"]`));
    const allCb = document.querySelector(`.edit-grp-all-${gIdx}`);
    const allChecked = dayCbs.every(cb => cb && cb.checked);
    if (allCb) allCb.checked = allChecked;
};

window._toggleGroupAllDays = function(gIdx) {
    const allCb = document.querySelector(`.edit-grp-all-${gIdx}`);
    const isChecked = allCb.checked;
    [0,1,2,3,4,5,6].forEach(i => {
        const cb = document.querySelector(`.edit-grp-day-${gIdx}[value="${i}"]`);
        if (cb) cb.checked = isChecked;
    });
};

window._getNewGroupDays = function() {
    const dayCbs = [0,1,2,3,4,5,6].map(i => document.getElementById('new-day-' + i));
    const allCb = document.getElementById('new-day-all');
    if (!dayCbs.every(Boolean)) return [0,1,2,3,4,5,6];
    const checked = dayCbs.filter(cb => cb.checked).map(cb => parseInt(cb.value));
    if (checked.length === 7 || (allCb && allCb.checked)) return [0,1,2,3,4,5,6];
    return checked;
};

window._getEditGroupDays = function(gIdx) {
    const dayCbs = [0,1,2,3,4,5,6].map(i => document.querySelector(`.edit-grp-day-${gIdx}[value="${i}"]`));
    if (!dayCbs.every(Boolean)) return [0,1,2,3,4,5,6];
    const checked = dayCbs.filter(cb => cb.checked).map(cb => parseInt(cb.value));
    const allCb = document.querySelector(`.edit-grp-all-${gIdx}`);
    if (checked.length === 7 || (allCb && allCb.checked)) return [0,1,2,3,4,5,6];
    return checked;
};

// ─── AÑADIR GRUPO NUEVO ───
window.addScheduleGroup = function(mapId) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId]) return;
    const start = document.getElementById('new-range-start').value;
    const end = document.getElementById('new-range-end').value;
    if (!start || !end) {
        showToast("ERROR: Completá Inicio y Fin del horario.");
        return;
    }
    const days = window._getNewGroupDays();
    if (days.length === 0) {
        showToast("ERROR: Seleccioná al menos un día.");
        return;
    }
    if (!config.mapsConfig[mapId].allowedHours) {
        config.mapsConfig[mapId].allowedHours = [];
    }
    config.mapsConfig[mapId].allowedHours.push({ days, hours: [{ start, end }] });
    saveConfig();
    renderMapDetail();
};

// ─── EDITAR GRUPO ───
window.editScheduleGroup = function(mapId, gIdx) {
    window._editingGroupIndex = gIdx;
    renderMapDetail();
};

window.cancelScheduleGroupEdit = function() {
    window._editingGroupIndex = -1;
    renderMapDetail();
};

window.saveScheduleGroup = function(mapId, gIdx) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId] || !config.mapsConfig[mapId].allowedHours) return;
    
    const days = window._getEditGroupDays(gIdx);
    if (days.length === 0) {
        showToast("ERROR: Seleccioná al menos un día.");
        return;
    }
    
    const group = config.mapsConfig[mapId].allowedHours[gIdx];
    const hours = (group.hours || [{ start: "00:00", end: "00:00" }]).map((hr, hIdx) => {
        const startEl = document.getElementById(`edit-hr-start-${gIdx}-${hIdx}`);
        const endEl = document.getElementById(`edit-hr-end-${gIdx}-${hIdx}`);
        if (startEl && endEl) {
            return { start: startEl.value, end: endEl.value };
        }
        return hr;
    });
    
    config.mapsConfig[mapId].allowedHours[gIdx] = { days, hours };
    window._editingGroupIndex = -1;
    saveConfig();
    renderMapDetail();
};

// ─── AÑADIR HORARIO A GRUPO EN EDICIÓN ───
window.addHourToGroup = function(mapId, gIdx) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId] || !config.mapsConfig[mapId].allowedHours) return;
    const startEl = document.getElementById(`edit-new-hr-start-${gIdx}`);
    const endEl = document.getElementById(`edit-new-hr-end-${gIdx}`);
    if (!startEl || !endEl) return;
    const start = startEl.value;
    const end = endEl.value;
    if (!start || !end) {
        showToast("ERROR: Completá Inicio y Fin del nuevo horario.");
        return;
    }
    if (!config.mapsConfig[mapId].allowedHours[gIdx].hours) {
        config.mapsConfig[mapId].allowedHours[gIdx].hours = [];
    }
    config.mapsConfig[mapId].allowedHours[gIdx].hours.push({ start, end });
    // Limpiar campos después de añadir
    startEl.value = '';
    endEl.value = '';
    saveConfig();
    renderMapDetail();
};

// ─── ELIMINAR HORARIO DE GRUPO ───
window.removeGroupHour = function(mapId, gIdx, hIdx) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId] || !config.mapsConfig[mapId].allowedHours) return;
    const group = config.mapsConfig[mapId].allowedHours[gIdx];
    if (!group || !group.hours) return;
    group.hours.splice(hIdx, 1);
    if (group.hours.length === 0) {
        group.hours = [{ start: "00:00", end: "00:00" }];
    }
    saveConfig();
    renderMapDetail();
};

// ─── ELIMINAR GRUPO COMPLETO ───
window.removeScheduleGroup = function(mapId, gIdx) {
    if (!config || !config.mapsConfig || !config.mapsConfig[mapId] || !config.mapsConfig[mapId].allowedHours) return;
    config.mapsConfig[mapId].allowedHours.splice(gIdx, 1);
    saveConfig();
    renderMapDetail();
};

// ═══════════════════════════════════════════════════════════════════════════════
// SISTEMA DE CLASIFICACIÓN / RANKING
// ═══════════════════════════════════════════════════════════════════════════════

function renderRanking() {
    if (!config.rankingConfig) {
        config.rankingConfig = JSON.parse(JSON.stringify(DEFAULT_RANKING_CONFIG));
    }
    const rc = config.rankingConfig;

    const configContainer = document.getElementById('ranking-config-container');
    const listContainer = document.getElementById('ranking-categories-container');
    if (!configContainer || !listContainer) return;

    const f = getFilter();

    // ── Config Global ──
    configContainer.innerHTML = `
        <div class="card" style="width: 100%;">
            <h3 style="color: var(--primary); margin-bottom: 1.5rem; display: flex; align-items: center; gap: 10px;">
                🏆 CONFIGURACIÓN GLOBAL DE CLASIFICACIÓN
            </h3>
            <p style="font-size:0.85rem; color:#aaa; margin-bottom:1.5rem; line-height:1.4;">
                Configurá las categorías de ranking, las recompensas por posición y el intervalo de reinicio.
                Cada categoría acumula puntos de forma independiente (<strong style="color:var(--accent);">Monstruos</strong>, 
                <strong style="color:var(--accent);">Eventos</strong>, <strong style="color:var(--accent);">Nivel</strong>).
                Los puntos de ranking por monstruo se configuran en el editor de cada enemigo.
            </p>
        </div>
        <div class="card" style="width: 100%; border-color: rgba(6,182,212,0.2); background: rgba(6,182,212,0.03);">
            <div style="display:flex; justify-content:space-between; align-items:center;">
                <h3 style="color: var(--accent); margin:0; display: flex; align-items: center; gap: 10px;">
                    📊 VISTA PREVIA DEL RANKING
                </h3>
                <button class="btn btn-primary" onclick="emitGetRankings()" style="padding: 8px 16px; font-size: 0.75rem;">
                    🔄 REFRESCAR DATOS
                </button>
            </div>
            <div id="ranking-preview" style="margin-top: 1rem; font-size: 0.85rem; color: #aaa;">
                Seleccioná una categoría abajo y presioná "VER RANKING" para ver los líderes actuales.
            </div>
        </div>
    `;

    // ── Categorías ──
    listContainer.innerHTML = '';

    const headerCard = document.createElement('div');
    headerCard.className = 'card';
    headerCard.style.width = '100%';
    headerCard.style.marginBottom = '1.5rem';
    headerCard.innerHTML = `
        <h3 style="color: var(--primary); margin-bottom: 1rem; display: flex; align-items: center; gap: 10px;">
            🏅 CATEGORÍAS DE CLASIFICACIÓN
            <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem;" onclick="addRankingCategory()">+ AGREGAR CATEGORÍA</button>
        </h3>
        <p style="font-size:0.85rem; color:#aaa; line-height:1.4;">
            Cada categoría tiene su propia tabla de posiciones y recompensas. 
            Los intervalos de reinicio definen cada cuánto se reparten las recompensas y se resetean los puntajes.
        </p>
    `;
    listContainer.appendChild(headerCard);

    const categoriesDiv = document.createElement('div');
    categoriesDiv.style.display = 'flex';
    categoriesDiv.style.flexDirection = 'column';
    categoriesDiv.style.gap = '2rem';
    listContainer.appendChild(categoriesDiv);

    const categories = rc.categories || [];
    categories.forEach((cat, catIdx) => {
        if (f && !cat.name.toLowerCase().includes(f) && !cat.id.toLowerCase().includes(f)) return;

        const catCard = document.createElement('div');
        catCard.className = 'card';
        catCard.style.position = 'relative';
        catCard.style.borderLeft = '4px solid var(--accent)';

        if (!cat.rewards) cat.rewards = [];

        let rewardsHTML = cat.rewards.map((rw, rIdx) => {
            let itemsHTML = (rw.items || []).map((item, iIdx) => `
                <div style="display:flex; gap:8px; align-items:center; margin-bottom:4px; background:rgba(255,255,255,0.02); padding:4px 8px; border-radius:6px;">
                    <div class="field" style="margin:0; flex:2;"><label style="font-size:8px;">ID Ítem</label><input type="text" value="${item.id}" style="font-size:0.7rem; padding:3px;" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items[${iIdx}].id = this.value"></div>
                    <div class="field" style="margin:0; flex:1;"><label style="font-size:8px;">Cant.</label><input type="number" value="${item.qty}" style="font-size:0.7rem; padding:3px;" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items[${iIdx}].qty = Math.floor(Math.max(1, parseInt(this.value) || 1))"></div>
                    <button class="btn" style="background:var(--danger); border:none; padding:2px 6px; font-size:9px; margin-top:12px; cursor:pointer;" onclick="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items.splice(${iIdx}, 1); renderRanking();">✕</button>
                </div>
            `).join('');

            return `
                <div style="background:rgba(0,0,0,0.2); border-radius:12px; padding:1rem; margin-bottom:0.8rem; border:1px solid rgba(255,255,255,0.05); position:relative;">
                    <div style="position:absolute; top:8px; right:8px; display:flex; gap:6px;">
                        <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.8rem;" onclick="removeRankingReward(${catIdx}, ${rIdx})" title="Eliminar posición">✕</button>
                    </div>
                    <div style="display:flex; align-items:center; gap:12px; margin-bottom:0.8rem;">
                        <span style="background:var(--accent); color:#000; font-weight:bold; font-size:0.8rem; padding:4px 12px; border-radius:20px;">#${rw.rank}</span>
                        <span style="color:var(--text-dim); font-size:0.75rem;">POSICIÓN</span>
                    </div>
                    <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr 1fr 1fr; gap:8px;">
                        <div class="field"><label>Hubs</label><input type="number" value="${rw.hubs || 0}" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].hubs = parseInt(this.value)"></div>
                        <div class="field"><label>OHCU</label><input type="number" value="${rw.ohcu || 0}" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].ohcu = parseInt(this.value)"></div>
                        <div class="field"><label>EXP</label><input type="number" value="${rw.exp || 0}" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].exp = parseInt(this.value)"></div>
                        <div class="field"><label>EXP BP</label><input type="number" value="${rw.bpExp || 0}" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].bpExp = parseInt(this.value)"></div>
                    </div>
                    <div style="margin-top:0.5rem;">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:4px;">
                            <label style="font-size:9px; color:var(--text-dim);">📦 Ítems</label>
                            <button class="btn btn-primary" style="padding:2px 8px; font-size:8px;" onclick="if(!config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items) config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items = []; config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items.push({id:'', qty:1}); renderRanking();">+ Item</button>
                        </div>
                        <div style="max-height:100px; overflow-y:auto;">
                            ${itemsHTML}
                        </div>
                    </div>
                </div>
            `;
        }).join('');

        const resetOptions = [
            { value: 'daily', label: 'Diario' },
            { value: 'weekly', label: 'Semanal' },
            { value: 'monthly', label: 'Mensual' },
            { value: 'never', label: 'Nunca (manual)' }
        ];

        catCard.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.2rem; padding-bottom:0.8rem; border-bottom:1px solid rgba(255,255,255,0.05);">
                <div style="font-family:'JetBrains Mono'; font-size:0.7rem; color:var(--text-dim); opacity:0.6;">ID: ${cat.id}</div>
                <div style="display:flex; gap:8px; align-items:center;">
                    <button class="btn btn-primary" style="padding:4px 10px; font-size:0.6rem; background:rgba(6,182,212,0.2); border:1px solid rgba(6,182,212,0.3); color:var(--accent);" onclick="viewRankingPreview('${cat.id}')">📊 VER RANKING</button>
                    <button class="btn btn-danger" style="padding:4px 10px; font-size:0.6rem;" onclick="removeRankingCategory(${catIdx})">✕ ELIMINAR</button>
                </div>
            </div>
            <div style="margin-bottom:1.5rem; display:flex; align-items:center; gap:15px;">
                <div style="font-size:2.5rem; line-height:1;">${cat.icon || '🏆'}</div>
                <div style="flex:1;">
                    <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr; gap:12px;">
                        <div class="field">
                            <label>Nombre</label>
                            <input type="text" value="${cat.name}" onchange="config.rankingConfig.categories[${catIdx}].name = this.value">
                        </div>
                        <div class="field">
                            <label>Icono</label>
                            <input type="text" value="${cat.icon || ''}" placeholder="Ej: 👾" onchange="config.rankingConfig.categories[${catIdx}].icon = this.value" style="font-size:1.2rem;">
                        </div>
                        <div class="field">
                            <label>Intervalo de Reinicio</label>
                            <select onchange="config.rankingConfig.categories[${catIdx}].resetInterval = this.value; renderRanking();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width:100%;">
                                ${resetOptions.map(opt => `<option value="${opt.value}" ${cat.resetInterval === opt.value ? 'selected' : ''}>${opt.label}</option>`).join('')}
                            </select>
                        </div>
                    </div>
                </div>
            </div>

            <div style="border-top:1px solid rgba(255,255,255,0.05); padding-top:1rem;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                    <h4 style="color:var(--accent); font-size:0.8rem; font-weight:bold; margin:0;">🎁 RECOMPENSAS POR POSICIÓN</h4>
                    <button class="btn btn-primary" style="padding:4px 12px; font-size:0.65rem;" onclick="addRankingReward(${catIdx})">+ AGREGAR POSICIÓN</button>
                </div>
                <div style="display:flex; flex-direction:column; gap:4px;">
                    ${rewardsHTML || '<div style="color:#555; font-style:italic; font-size:0.8rem; padding:0.5rem;">No hay recompensas configuradas. Hacé clic en "+ AGREGAR POSICIÓN".</div>'}
                </div>
            </div>
        `;
        categoriesDiv.appendChild(catCard);
    });

    if (categories.length === 0) {
        const emptyMsg = document.createElement('div');
        emptyMsg.style.cssText = 'color:#555; font-style:italic; padding:2rem; text-align:center; font-size:0.9rem;';
        emptyMsg.innerText = 'No hay categorías de ranking. Hacé clic en "+ AGREGAR CATEGORÍA" para comenzar.';
        categoriesDiv.appendChild(emptyMsg);
    }
}

// ─── FUNCIONES GLOBALES DE RANKING ───

window.addRankingCategory = function() {
    if (!config.rankingConfig) {
        config.rankingConfig = JSON.parse(JSON.stringify(DEFAULT_RANKING_CONFIG));
    }
    if (!config.rankingConfig.categories) config.rankingConfig.categories = [];

    const newId = 'cat_' + Date.now();
    config.rankingConfig.categories.push({
        id: newId,
        name: 'Nueva Categoría',
        icon: '🏆',
        resetInterval: 'weekly',
        rewards: [
            { rank: 1, hubs: 10000, ohcu: 50, exp: 5000, bpExp: 2000, items: [] },
            { rank: 2, hubs: 5000, ohcu: 25, exp: 2500, bpExp: 1000, items: [] },
            { rank: 3, hubs: 2500, ohcu: 10, exp: 1000, bpExp: 500, items: [] }
        ]
    });
    renderRanking();
};

window.removeRankingCategory = function(catIdx) {
    if (!config.rankingConfig || !config.rankingConfig.categories) return;
    config.rankingConfig.categories.splice(catIdx, 1);
    renderRanking();
};

window.addRankingReward = function(catIdx) {
    if (!config.rankingConfig || !config.rankingConfig.categories) return;
    const cat = config.rankingConfig.categories[catIdx];
    if (!cat) return;
    if (!cat.rewards) cat.rewards = [];

    const nextRank = cat.rewards.length > 0 ? Math.max(...cat.rewards.map(r => r.rank)) + 1 : 1;
    cat.rewards.push({
        rank: nextRank,
        hubs: 0,
        ohcu: 0,
        exp: 0,
        bpExp: 0,
        items: []
    });
    renderRanking();
};

window.removeRankingReward = function(catIdx, rIdx) {
    if (!config.rankingConfig || !config.rankingConfig.categories) return;
    const cat = config.rankingConfig.categories[catIdx];
    if (!cat || !cat.rewards) return;
    cat.rewards.splice(rIdx, 1);
    // Re-indexar ranks
    cat.rewards.forEach((r, i) => r.rank = i + 1);
    renderRanking();
};

window.viewRankingPreview = function(categoryId) {
    const preview = document.getElementById('ranking-preview');
    if (!preview) return;
    preview.innerHTML = `<div style="color:#888; font-style:italic;">Solicitando datos del ranking <strong>${categoryId}</strong>...</div>`;

    if (typeof socket !== 'undefined' && socket && socket.connected) {
        socket.off('rankingsData');
        socket.on('rankingsData', (data) => {
            if (data.category !== categoryId) return;
            if (!data.rankings || data.rankings.length === 0) {
                preview.innerHTML = `<div style="color:#555; font-style:italic;">No hay datos de ranking para esta categoría aún.</div>`;
                return;
            }
            let html = `<div style="display:flex; flex-direction:column; gap:6px;">`;
            const medals = ['🥇', '🥈', '🥉'];
            data.rankings.forEach((entry, idx) => {
                const medal = idx < 3 ? medals[idx] : `#${idx + 1}`;
                html += `
                    <div style="display:flex; align-items:center; gap:12px; background:rgba(255,255,255,0.02); padding:8px 12px; border-radius:8px; border:1px solid rgba(255,255,255,0.05);">
                        <span style="font-size:1.2rem;">${medal}</span>
                        <strong style="flex:1; color:var(--text);">${entry.username}</strong>
                        <span style="color:var(--accent); font-weight:bold; font-family:'JetBrains Mono';">${entry.points} pts</span>
                    </div>
                `;
            });
            html += `</div>`;
            preview.innerHTML = html;
        });
        socket.emit('getRankings', { category: categoryId });
    } else {
        preview.innerHTML = `<div style="color:#ff4444;">ERROR: No hay conexión con el servidor.</div>`;
    }
};

window.emitGetRankings = function() {
    const preview = document.getElementById('ranking-preview');
    if (preview) {
        preview.innerHTML = `<div style="color:#888; font-style:italic;">Seleccioná una categoría y hacé clic en "VER RANKING".</div>`;
    }
};

