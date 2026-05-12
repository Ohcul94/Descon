function refreshCurrentTab() {
    const active = document.querySelector('.view.active');
    if(!active) return;
    const tabId = active.id.replace('view-', '');
    const renderMap = {
        'ships': renderShips, 'enemies': renderEnemies, 'ammo': renderAmmo, 'weapons': renderWeapons, 
        'shields': renderShields, 'engines': renderEngines, 'skills': renderSkills, 
        'mechanics': renderMechanicsLib, 'maps': renderMaps
    };
    if(renderMap[tabId]) renderMap[tabId]();
}

function renderAll() {
    if(!config) return;
    renderShips(); renderEnemies(); renderSkills(); renderMechanicsLib();
    renderMaps(); renderAmmo(); renderWeapons(); renderShields(); renderEngines();
}

function renderAmmo() {
    const grid = document.getElementById('ammo-grid'); grid.innerHTML = '';
    const f = getFilter();
    
    const type = currentAmmoTab;
    const multipliers = config.ammoMultipliers[type] || [];
    const shopItems = (config.shopItems.ammo && config.shopItems.ammo[type]) ? config.shopItems.ammo[type] : [];

    multipliers.forEach((m, i) => {
        const item = shopItems[i] || { name: `Tier ${i+1}`, range: 0, cooldown: 1000, prices: { hubs:0, ohcu:0 } };
        if(item.cooldown === undefined) item.cooldown = 1000;
        if(item.bulletSpeed === undefined) item.bulletSpeed = 800;
        if(!item.mechanics) item.mechanics = [];
        
        if(f && !item.name.toLowerCase().includes(f) && !JSON.stringify(item).toLowerCase().includes(f)) return;

        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div class="card-tag">TIER ${i+1}</div>
            <div class="field full"><label>Nombre Comercial</label><input type="text" value="${item.name}" onchange="config.shopItems.ammo['${type}'][${i}].name = this.value"></div>
            
            <div class="form-grid" style="margin-top:1.5rem;">
                <div class="field"><label>Mult. Daño (x)</label><input type="number" step="0.1" value="${m}" style="color:var(--accent); font-weight:bold;" onchange="config.ammoMultipliers['${type}'][${i}] = parseFloat(this.value)"></div>
                <div class="field"><label>Alcance (px)</label><input type="number" value="${item.range || 0}" onchange="config.shopItems.ammo['${type}'][${i}].range = parseInt(this.value)"></div>
                <div class="field"><label>Vel. Bala (px/s)</label><input type="number" value="${item.bulletSpeed}" onchange="config.shopItems.ammo['${type}'][${i}].bulletSpeed = parseInt(this.value)"></div>
                <div class="field"><label>Cooldown (ms)</label><input type="number" value="${item.cooldown}" onchange="config.shopItems.ammo['${type}'][${i}].cooldown = parseInt(this.value)"></div>
            </div>
            
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
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div class="card-tag">ID: ${w.id}</div>
            <div class="field full"><label>Nombre del Arma</label><input type="text" value="${w.name}" onchange="config.shopItems.weapons[${i}].name = this.value"></div>
            <div class="form-grid" style="margin-top:1rem;">
                <div class="field"><label>Daño Base (pts)</label><input type="number" value="${w.base}" onchange="config.shopItems.weapons[${i}].base = parseInt(this.value)"></div>
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
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div class="card-tag">ID: ${s.id}</div>
            <div class="field full"><label>Nombre del Escudo</label><input type="text" value="${s.name}" onchange="config.shopItems.shields[${i}].name = this.value"></div>
            <div class="form-grid" style="margin-top:1rem;">
                <div class="field"><label>Escudo Base (pts)</label><input type="number" value="${s.base}" onchange="config.shopItems.shields[${i}].base = parseInt(this.value)"></div>
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
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div class="card-tag">ID: ${e.id}</div>
            <div class="field full"><label>Nombre del Motor</label><input type="text" value="${e.name}" onchange="config.shopItems.engines[${i}].name = this.value"></div>
            <div class="form-grid" style="margin-top:1rem;">
                <div class="field"><label>Empuje Base (px/s)</label><input type="number" value="${e.base}" onchange="config.shopItems.engines[${i}].base = parseInt(this.value)"></div>
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
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `
            <div class="card-tag">#ID ${ship.id}</div>
            <div class="field full"><label>Nombre de la Nave</label><input type="text" value="${ship.name}" onchange="config.shipModels[${idx}].name = this.value"></div>
            <div class="form-grid" style="margin-top: 1.5rem;">
                <div class="field"><label>HP Total (pts)</label><input type="number" value="${ship.hp}" onchange="config.shipModels[${idx}].hp = parseInt(this.value)"></div>
                <div class="field"><label>Escudo Total (pts)</label><input type="number" value="${ship.shield}" onchange="config.shipModels[${idx}].shield = parseInt(this.value)"></div>
                <div class="field"><label>Velocidad (px/s)</label><input type="number" value="${ship.speed}" onchange="config.shipModels[${idx}].speed = parseInt(this.value)"></div>
            </div>
            <div class="form-grid" style="margin-top: 1rem; padding-top: 1rem; border-top: 1px solid #333;">
                <div class="field"><label>Slots Armas (W)</label><input type="number" value="${ship.slots.w || 0}" onchange="config.shipModels[${idx}].slots.w = parseInt(this.value)"></div>
                <div class="field"><label>Slots Escudos (S)</label><input type="number" value="${ship.slots.s || 0}" onchange="config.shipModels[${idx}].slots.s = parseInt(this.value)"></div>
                <div class="field"><label>Slots Motores (E)</label><input type="number" value="${ship.slots.e || 0}" onchange="config.shipModels[${idx}].slots.e = parseInt(this.value)"></div>
                <div class="field"><label>Slots Extras (X)</label><input type="number" value="${ship.slots.x || 0}" onchange="config.shipModels[${idx}].slots.x = parseInt(this.value)"></div>
            </div>
            <div class="price-group">
                <div class="field"><label>Precio Hubs (qty)</label><input type="number" value="${ship.prices.hubs}" onchange="config.shipModels[${idx}].prices.hubs = parseInt(this.value)"></div>
                <div class="field"><label>Precio Ohcu (qty)</label><input type="number" value="${ship.prices.ohcu}" onchange="config.shipModels[${idx}].prices.ohcu = parseInt(this.value)"></div>
            </div>
        `;
        grid.appendChild(card);
    });
}

function updateSidebar() {
    const enemyList = document.getElementById('sidebar-enemies-list');
    const bossList = document.getElementById('sidebar-bosses-list');
    const mapList = document.getElementById('sidebar-maps-list');
    if(!enemyList || !bossList || !mapList) return;
    
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
    for(let id in config.enemyModels) {
        const en = config.enemyModels[id];
        const matches = en.name.toLowerCase().includes(searchTerm) || id.includes(searchTerm);
        if (!matches) continue;

        const link = document.createElement('div');
        link.className = 'nav-link sub ' + (selectedEnemyId === id ? 'active' : '');
        link.innerText = `${en.name || 'Enemigo '+id}`;
        link.onclick = () => selectEnemy(id);
        
        if (parseInt(id) < 100) enemyList.appendChild(link);
        else bossList.appendChild(link);
    }
}

function renderEnemies() {
    if (config.mechanicsLib) MECHANICS_LIB = config.mechanicsLib;
    if (config.movementLib) MOVEMENT_LIB = config.movementLib;

    updateSidebar();
    const grid = document.getElementById('enemies-grid'); grid.innerHTML = '';
    const f = getFilter();

    for(let id in config.enemyModels) {
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
    const container = document.getElementById('enemy-detail-container');
    const en = config.enemyModels[selectedEnemyId];
    if(!en) return;

    if (!en.mechanics) {
        en.mechanics = [{ type: "laser", bulletDamage: 10, bulletSpeed: 800, fireRange: 600, fireRate: 1000, startDelay: 0 }];
    }
    if (!en.movementPhases) {
        en.movementPhases = [{ type: en.movementAI || "chase", speed: en.speed || 3.5, stopDist: en.stopDist || 150, startDelay: 0 }];
    }

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
                        <div class="field"><label>Exp (pts)</label><input type="number" value="${en.rewardExp}" onchange="config.enemyModels['${selectedEnemyId}'].rewardExp = parseInt(this.value)"></div>
                        <div class="field"><label>Hubs (pts)</label><input type="number" value="${en.rewardHubs}" onchange="config.enemyModels['${selectedEnemyId}'].rewardHubs = parseInt(this.value)"></div>
                    </div>
                </div>
                <div style="margin-bottom: 1rem; display:flex; justify-content:space-between; align-items:center;">
                    <label style="color:var(--accent); font-size: 0.8rem; font-weight:bold;">🏃 CICLO DE MOVIMIENTO</label>
                    <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem;" onclick="addMovementPhase('${selectedEnemyId}'); renderEnemyDetail();">+ AGREGAR FASE</button>
                </div>
                <div id="move-list-${selectedEnemyId}">
                    ${en.movementPhases.map((m, idx) => `
                        <div class="card" style="margin-bottom:1rem; position:relative; padding: 1rem; background: rgba(6, 182, 212, 0.05); border: 1px solid rgba(6, 182, 212, 0.2);">
                            <div style="position:absolute; top:8px; right:8px; display:flex; gap:10px;">
                                <button style="background:none; border:none; color:var(--accent); cursor:pointer; font-weight:bold;" onclick="moveMovementPhase('${selectedEnemyId}', ${idx}, -1); renderEnemyDetail();">SUBIR</button>
                                <button style="background:none; border:none; color:var(--accent); cursor:pointer; font-weight:bold;" onclick="moveMovementPhase('${selectedEnemyId}', ${idx}, 1); renderEnemyDetail();">BAJAR</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="removeMovementPhase('${selectedEnemyId}', ${idx}); renderEnemyDetail();">✕</button>
                            </div>
                            <div class="field full">
                                <select style="background:#0f172a; border:none; color:white; font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" onchange="updateMovementPhaseType('${selectedEnemyId}', ${idx}, this.value); renderEnemyDetail();">
                                    ${Object.keys(MOVEMENT_LIB).map(type => `<option value="${type}" ${m.type === type ? 'selected' : ''} style="background:#0f172a; color:white;">${MOVEMENT_LIB[type].icon} ${MOVEMENT_LIB[type].label}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-grid" style="margin-top:1rem;">
                                <div class="field"><label>Retraso Inicio (ms)</label><input type="number" value="${m.startDelay || 0}" onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].startDelay = parseInt(this.value)"></div>
                                ${MOVEMENT_LIB[m.type || 'chase'].fields.map(f => {
                                    const moveLabels = { speed:"Velocidad (px/s)", stopDist:"Frenado (px)", idealDist:"Rango Seguro (px)", orbitRadius:"Radio Órbita (px)", chargeCooldown: "Recarga Dash (ms)", activationHP: "Activación HP (%)", explosionDamage: "Daño Explosión", duration: "Duración Máxima (ms)", explodeOnDeath: "Explotar al morir" };
                                    if (f === 'explodeOnDeath') return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;"><input type="checkbox" ${m[f] ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].explodeOnDeath = this.checked"><label style="margin:0;">${moveLabels[f]}</label></div>`;
                                    return `<div class="field"><label>${moveLabels[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].movementPhases[${idx}].${f} = parseFloat(this.value)"></div>`;
                                }).join('')}
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
            <div class="col">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                    <label style="color:var(--accent); font-size: 0.8rem; font-weight:bold;">⚔️ MECÁNICAS DE ATAQUE ACTIVAS</label>
                    <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem;" onclick="addMechanic('${selectedEnemyId}'); renderEnemyDetail();">+ AGREGAR ARMA</button>
                </div>
                <div id="mech-list-${selectedEnemyId}">
                    ${en.mechanics.map((m, idx) => `
                        <div class="card" style="margin-bottom: 1rem; position:relative; padding: 1rem;">
                            <div style="position:absolute; top:8px; right:8px; display:flex; gap:10px;">
                                <button style="background:none; border:none; color:var(--accent); cursor:pointer; font-weight:bold;" onclick="moveMechanic('${selectedEnemyId}', ${idx}, -1); renderEnemyDetail();">SUBIR</button>
                                <button style="background:none; border:none; color:var(--accent); cursor:pointer; font-weight:bold;" onclick="moveMechanic('${selectedEnemyId}', ${idx}, 1); renderEnemyDetail();">BAJAR</button>
                                <button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="removeMechanic('${selectedEnemyId}', ${idx}); renderEnemyDetail();">✕</button>
                            </div>
                            <div class="field full">
                                <select style="background:#0f172a; border:none; color:var(--accent); font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" onchange="updateMechanicType('${selectedEnemyId}', ${idx}, this.value); renderEnemyDetail();">
                                    ${Object.keys(MECHANICS_LIB).map(type => `<option value="${type}" ${m.type === type ? 'selected' : ''} style="background:#0f172a; color:white;">${MECHANICS_LIB[type].icon} ${MECHANICS_LIB[type].label}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-grid" style="margin-top:1rem;">
                                ${MECHANICS_LIB[m.type || 'laser'].fields.map(f => {
                                    const fieldLabelsMap = { 
                                        bulletDamage: "Daño (pts)", 
                                        bulletSpeed: "Vel. Bala (px/s)", 
                                        fireRange: "Alcance (px)", 
                                        fireRate: "Cadencia (ms)", 
                                        slowAmount: "Slow (pts)", 
                                        slowDuration: "Slow Dur. (ms)", 
                                        startDelay: "Delay Inicio (ms)", 
                                        lifetimeMs: "Combustible (ms)", 
                                        turnSpeed: "Agilidad de Giro (rad/s)", 
                                        chargeTimeMs: "Tiempo de Carga (ms)", 
                                        lockTimeMs: "Tiempo de Bloqueo (ms)", 
                                        isHoming: "Seguimiento (Homing)",
                                        orbitSpeed: "Vel. de Giro (rad/s)",
                                        circleCount: "Cant. de Círculos (uds)",
                                        orbitRadius: "Radio de Órbita (px)",
                                        orbitDuration: "Tiempo de Giro (ms)",
                                        staticTime: "Tiempo Estático (ms)"
                                    };
                                    if (f === 'isHoming') return `<div class="field" style="grid-column: 1 / -1; background: rgba(6, 182, 212, 0.05); padding: 10px; border-radius: 8px; flex-direction: column; gap: 12px; border: 1px solid rgba(6, 182, 212, 0.2);"><div style="display:flex; align-items:center; gap:12px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:20px; height:20px; cursor:pointer;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].isHoming = this.checked; renderEnemyDetail();"><label style="margin:0; font-size: 0.85rem; color: var(--accent); cursor:pointer;">ACTIVAR SEGUIMIENTO AL OBJETIVO</label></div>${m.isHoming ? `<div style="padding-top: 10px; border-top: 1px solid rgba(6, 182, 212, 0.2);"><label style="font-size: 0.65rem; color: var(--text-dim);">AGILIDAD DE GIRO (RAD/S)</label><input type="number" step="0.1" value="${m.turnSpeed || 2.5}" style="background:rgba(0,0,0,0.3); margin-top:5px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].turnSpeed = parseFloat(this.value)"></div>` : ''}</div>`;
                                    if (f === 'turnSpeed') return '';
                                    return `<div class="field"><label>${fieldLabelsMap[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].${f} = parseFloat(this.value)"></div>`;
                                }).join('')}
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
        </div>
    `;
}

function renderMechanicsLib() {
    if (config.mechanicsLib) MECHANICS_LIB = config.mechanicsLib;
    const grid = document.getElementById('mechanics-lib-grid'); if(!grid) return;
    grid.innerHTML = '';
    const f = getFilter();
    const fieldLabels = { 
        "bulletDamage": "Daño", 
        "bulletSpeed": "Velocidad", 
        "fireRange": "Alcance", 
        "fireRate": "Cadencia", 
        "startDelay": "Delay", 
        "slowAmount": "Ralentización", 
        "slowDuration": "Duración Slow",
        "orbitSpeed": "Vel. Giro",
        "circleCount": "Cant. Círculos",
        "orbitRadius": "Radio Órbita",
        "orbitDuration": "Tiempo Giro",
        "staticTime": "Tiempo Estático"
    };

    if (currentMechTab === 'attack') {
        for(let type in MECHANICS_LIB) {
            const m = MECHANICS_LIB[type];
            if (f && !m.label.toLowerCase().includes(f) && !type.toLowerCase().includes(f) && !JSON.stringify(m).toLowerCase().includes(f)) continue;
            const card = document.createElement('div'); card.className = 'card';
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Nombre Público</label><input type="text" value="${m.label}" onchange="config.mechanicsLib['${type}'].label = this.value; renderAll();"></div><div class="field full" style="margin-top:0.5rem;"><label>Descripción</label><input type="text" value="${m.desc || ''}" onchange="config.mechanicsLib['${type}'].desc = this.value"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">CAMPOS:</strong> ${m.fields.map(fl => fieldLabels[fl] || fl).join(' • ')}</div>`;
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
            const al = { damagePerSecond: "Daño/Seg", slowPercentage: "Slow Ambient", visibility: "Visibilidad", dashPenalty: "Penalidad Dash" };
            card.innerHTML = `<div style="font-size: 2rem; margin-bottom: 1rem;">${m.icon}</div><div class="field full"><label>Efecto de Ambiente</label><input type="text" value="${m.label}" onchange="AMBIENCE_LIB['${type}'].label = this.value; renderAll();"></div><div style="font-size: 0.7rem; border-top: 1px solid #444; padding-top: 1rem; color: var(--text-dim); margin-top: 1rem;"><strong style="color:var(--accent);">PARÁMETROS AFECTADOS:</strong> ${m.fields.map(fl => al[fl] || fl).join(' • ')}</div>`;
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
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 2rem; align-items: start;">
            <div class="col">
                <div class="card" style="width:100%;">
                    <div class="field full"><label>NOMBRE DE LA ZONA</label><input type="text" value="${m.name}" style="font-size: 1.5rem; color:var(--accent);" onchange="config.mapsConfig['${selectedMapId}'].name = this.value; updateSidebar();"></div>
                    <div class="field full" style="margin-top:1rem;"><label>DESCRIPCIÓN DE HISTORIA</label><textarea onchange="config.mapsConfig['${selectedMapId}'].desc = this.value" style="height:100px; width:100%; background:rgba(0,0,0,0.2); border:1px solid #333; color:white; padding:10px; border-radius:8px;">${m.desc || ''}</textarea></div>
                    <div class="form-grid" style="margin-top:1rem;">
                        <div class="field"><label>Nivel Mín. (lvl)</label><input type="number" value="${m.minLevel}" onchange="config.mapsConfig['${selectedMapId}'].minLevel = parseInt(this.value)"></div>
                        <div class="field"><label>Costo Warp (Hubs)</label><input type="number" value="${m.warpCost}" onchange="config.mapsConfig['${selectedMapId}'].warpCost = parseInt(this.value)"></div>
                        <div class="field"><label>Color de Radar</label><input type="color" value="${m.color}" onchange="config.mapsConfig['${selectedMapId}'].color = this.value; updateSidebar();" style="height:40px;"></div>
                    </div>
                </div>
            </div>
            <div class="col">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;"><label style="color:var(--accent); font-size: 0.8rem; font-weight:bold;">☢️ MECÁNICAS DE AMBIENTE (HAZARDS)</label><button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem;" onclick="addAmbience('${selectedMapId}'); renderMapDetail();">+ AGREGAR EFECTO</button></div>
                <div id="ambience-list" style="margin-bottom: 2rem;">
                    ${m.ambience.map((a, idx) => `
                        <div class="card" style="margin-bottom:1rem; padding:1rem; position:relative;"><div style="position:absolute; top:8px; right:8px;"><button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="config.mapsConfig['${selectedMapId}'].ambience.splice(${idx},1); renderMapDetail();">✕</button></div><div class="field full"><select style="background:#0f172a; border:none; color:var(--accent); font-weight:bold; cursor:pointer; width:100%; border-radius:4px; padding:4px;" onchange="config.mapsConfig['${selectedMapId}'].ambience[${idx}].type = this.value; renderMapDetail();">${Object.keys(AMBIENCE_LIB).map(type => `<option value="${type}" ${a.type === type ? 'selected' : ''}>${AMBIENCE_LIB[type].icon} ${AMBIENCE_LIB[type].label}</option>`).join('')}</select></div><div class="form-grid" style="margin-top:1rem;">${AMBIENCE_LIB[a.type || 'radiation'].fields.map(f => { const labels = { damage: "Daño (pts)", intervalMs: "Intervalo (ms)", slowPercentage: "Slow (%)", visibility: "Visibilidad (px)", dashPenalty: "Penalidad Dash (%)", lifetimeMs: "Combustible (ms)" }; return `<div class="field"><label>${labels[f] || f}</label><input type="number" value="${a[f] || 0}" onchange="config.mapsConfig['${selectedMapId}'].ambience[${idx}].${f} = parseInt(this.value)"></div>`; }).join('')}</div></div>
                    `).join('')}
                </div>
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;"><label style="color:var(--success); font-size: 0.8rem; font-weight:bold;">👾 ECOSISTEMA DE ENEMIGOS</label><button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem; background:var(--success);" onclick="addMapSpawn('${selectedMapId}'); renderMapDetail();">+ AÑADIR ESPECIE</button></div>
                <div id="spawns-list">
                    ${(m.spawns || []).map((s, idx) => `<div class="card" style="margin-bottom:1rem; padding:1rem; position:relative; border-color: rgba(16, 185, 129, 0.2);"><div style="position:absolute; top:8px; right:8px;"><button style="background:none; border:none; color:#ff4444; cursor:pointer;" onclick="config.mapsConfig['${selectedMapId}'].spawns.splice(${idx},1); renderMapDetail();">✕</button></div><div class="form-grid"><div class="field" style="grid-column: span 2;"><label>Tipo de Enemigo</label><select style="background:#0f172a; color:var(--success); font-weight:bold;" onchange="config.mapsConfig['${selectedMapId}'].spawns[${idx}].type = this.value">${Object.keys(config.enemyModels).map(id => `<option value="${id}" ${s.type == id ? 'selected' : ''}>[ID ${id}] ${config.enemyModels[id].name}</option>`).join('')}</select></div><div class="field"><label>Cant. Máx</label><input type="number" value="${s.count}" onchange="config.mapsConfig['${selectedMapId}'].spawns[${idx}].count = parseInt(this.value)"></div><div class="field"><label>Intervalo (ms)</label><input type="number" value="${s.intervalMs}" onchange="config.mapsConfig['${selectedMapId}'].spawns[${idx}].intervalMs = parseInt(this.value)"></div></div></div>`).join('')}
                </div>
            </div>
        </div>
    `;
}

function renderMaps() {
    const grid = document.getElementById('maps-grid'); grid.innerHTML = '';
    const f = getFilter();
    for(let id in config.mapsConfig) {
        const m = config.mapsConfig[id];
        if (f && !m.name.toLowerCase().includes(f)) continue;
        const card = document.createElement('div'); card.className = 'card';
        card.style.cursor = 'pointer'; card.onclick = () => selectMap(id);
        card.innerHTML = `<div class="card-tag">#ID ${id}</div><div style="width:100%; height:4px; background:${m.color}; margin-bottom:1rem; border-radius:2px;"></div><h3>${m.name}</h3><p style="font-size:0.8rem; opacity:0.6;">${m.desc || 'Sin descripción'}</p><div style="margin-top:1rem; color:var(--accent); font-weight:bold; font-size:0.7rem;">Configurar Zona</div>`;
        grid.appendChild(card);
    }
}

function renderSkills() {
    const grid = document.getElementById('skills-grid'); grid.innerHTML = '';
    const f = getFilter();
    for(let name in config.skillsData) {
        const s = config.skillsData[name];
        if (f && !name.toLowerCase().includes(f) && !JSON.stringify(s).toLowerCase().includes(f)) continue;
        const card = document.createElement('div'); card.className = 'card';
        card.innerHTML = `<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;"><div class="field" style="flex-grow:1;"><label>Protocolo</label><input type="text" value="${s.name || name}" style="color:var(--accent); font-weight:bold; background:transparent; border:none;" readonly></div></div><div class="form-grid"><div class="field"><label>Tipo</label><select onchange="config.skillsData['${name}'].type = this.value"><option value="Defensa" ${s.type==='Defensa'?'selected':''}>Defensa</option><option value="Curación" ${s.type==='Curación'?'selected':''}>Curación</option><option value="Ataque" ${s.type==='Ataque'?'selected':''}>Ataque</option><option value="Utilidad" ${s.type==='Utilidad'?'selected':''}>Utilidad</option></select></div><div class="field"><label>Cooldown (ms)</label><input type="number" value="${s.cd}" onchange="config.skillsData['${name}'].cd = parseInt(this.value)"></div><div class="field"><label>Puntos (pts)</label><input type="number" value="${s.amount || 0}" onchange="config.skillsData['${name}'].amount = parseInt(this.value)"></div><div class="field"><label>Rango (px)</label><input type="number" value="${s.range || 0}" onchange="config.skillsData['${name}'].range = parseInt(this.value)"></div></div>`;
        grid.appendChild(card);
    }
}
