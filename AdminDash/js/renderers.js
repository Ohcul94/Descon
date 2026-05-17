function refreshCurrentTab() {
    const active = document.querySelector('.view.active');
    if(!active) return;
    const tabId = active.id.replace('view-', '');
    const renderMap = {
        'ships': renderShips, 'enemies': renderEnemies, 'ammo': renderAmmo, 'weapons': renderWeapons, 
        'shields': renderShields, 'engines': renderEngines, 'skills': renderSkills, 
        'mechanics': renderMechanicsLib, 'maps': renderMaps, 'users': renderRegisteredUsers,
        'pilot': renderPilot,
        'modes': renderModes,
        'sessions': () => (currentSessionSubTab === 'online' ? renderOnlinePlayers() : renderSessions())
    };
    if(renderMap[tabId]) renderMap[tabId]();
}

function renderAll() {
    if(!config) return;
    renderShips(); renderEnemies(); renderSkills(); renderMechanicsLib();
    renderMaps(); renderAmmo(); renderWeapons(); renderShields(); renderEngines();
    renderPilot();
    renderModes();
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
            const isCurrentOpen = baseSelectedId === id;
            
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
                subLink.innerText = `🔫 ${t.label}`;
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
                                    const moveLabels = { speed:"Velocidad (px/s)", stopDist:"Frenado (px)", idealDist:"Rango Seguro (px)", orbitRadius:"Radio Órbita (px)", chargeCooldown: "Recarga Dash (ms)", activationHP: "Activación HP (%)", explosionDamage: "Daño Explosión", duration: "Duración (ms)", cooldown: "Recarga (ms)", startDelay: "Retraso Inicio (ms)", explodeOnDeath: "Explotar al morir", radius: "Radio del Aura (px)", speedBonus: "Bono de Velocidad (px/s)", intervalMs: "Intervalo de Tick (ms)", affectsEnemies: "Afectar a otros Enemigos", affectsBosses: "Afectar a Bosses" };
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
                                        staticTime: "Tiempo Estático (ms)",
                                        radius: "Radio del Aura (px)",
                                        damage: "Daño por Pulso (pts)",
                                        intervalMs: "Intervalo de Tick (ms)",
                                        duration: "Duración Total (ms)",
                                        cooldown: "Recarga (ms)",
                                        pullSpeed: "Vel. Atracción (px/s)",
                                        stunDuration: "Duración Stun (ms)",
                                        postHookWaitMs: "Espera Post-Gancho (ms)",
                                        hookMissWaitMs: "Espera por Fallo (ms)",
                                        startDelay: "Retraso Inicio (ms)",
                                        activationHP: "Activación por HP (%)",
                                        reductionPercentage: "Reducción de Daño (%)",
                                        shieldRegen: "Regen. de Escudo (pts/s)",
                                        healAmount: "Curación por Pulso (pts)",
                                        speedBonus: "Bono de Velocidad (px/s)",
                                        explosionDamage: "Daño de Explosión (pts)"
                                    };
                                    if (f === 'isHoming') return `<div class="field" style="grid-column: 1 / -1; background: rgba(239, 68, 68, 0.05); padding: 10px; border-radius: 8px; flex-direction: column; gap: 12px; border: 1px solid rgba(239, 68, 68, 0.2);"><div style="display:flex; align-items:center; gap:12px;"><input type="checkbox" ${m[f] ? 'checked' : ''} style="width:20px; height:20px; cursor:pointer;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].isHoming = this.checked; renderEnemyDetail();"><label style="margin:0; font-size: 0.85rem; color: #ef4444; cursor:pointer;">ACTIVAR SEGUIMIENTO AL OBJETIVO</label></div>${m.isHoming ? `<div style="padding-top: 10px; border-top: 1px solid rgba(239, 68, 68, 0.2);"><label style="font-size: 0.65rem; color: var(--text-dim);">AGILIDAD DE GIRO (RAD/S)</label><input type="number" step="0.1" value="${m.turnSpeed || 2.5}" style="background:rgba(0,0,0,0.3); margin-top:5px;" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].turnSpeed = parseFloat(this.value)"></div>` : ''}</div>`;
                                    if (f === 'turnSpeed') return '';
                                    return `<div class="field"><label>${fieldLabelsMap[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].mechanics[${idx}].${f} = parseFloat(this.value)"></div>`;
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
                                        radius: "Radio del Aura (px)",
                                        healAmount: "Cura por Pulso (pts)",
                                        intervalMs: "Intervalo de Tick (ms)",
                                        activationHP: "Activación por HP (%)",
                                        affectsEnemies: "Afectar a otros Enemigos", 
                                        affectsBosses: "Afectar a Bosses",
                                        activationHP: "Activación por HP (%)"
                                    };
                                    if (['affectsEnemies', 'affectsBosses'].includes(f)) return `<div class="field" style="display:flex; align-items:center; gap:10px; border:none; background:transparent;"><input type="checkbox" ${m[f] ? 'checked' : ''} onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].${f} = this.checked"><label style="margin:0;">${defLabels[f]}</label></div>`;
                                    return `<div class="field"><label>${defLabels[f] || f}</label><input type="number" step="0.1" value="${m[f] || 0}" onchange="config.enemyModels['${selectedEnemyId}'].defenseMechanics[${idx}].${f} = parseFloat(this.value)"></div>`;
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
    const MECHANICS_LIB = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const MOVEMENT_LIB = config.movementLib || DEFAULT_MOVEMENT_LIB;
    const DEFENSE_LIB = config.defenseLib || DEFAULT_DEFENSE_LIB;

    const grid = document.getElementById('mechanics-lib-grid'); if(!grid) return;
    grid.innerHTML = '';
    const f = getFilter();
    const fieldLabels = { 
        "bulletDamage": "Daño", 
        "bulletSpeed": "Velocidad", 
        "fireRange": "Alcance", 
        "fireRate": "Cadencia", 
        "staticTime": "Tiempo Estático",
        "reductionPercentage": "Reducción Daño",
        "shieldRegen": "Regen. Escudo",
        "duration": "Duración (ms)",
        "cooldown": "Recarga (ms)",
        "radius": "Radio de Acción (px)",
        "damage": "Daño por Pulso (pts)",
        "healAmount": "Cura por Pulso (pts)",
        "speedBonus": "Bono Velocidad (px/s)",
        "intervalMs": "Intervalo (ms)"
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
                    radius: "Radio Acción/Visión (px)"
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
                                        respawnSpeedBonus: "Bono de Respawn (ms)"
                                    };
                                    let val = a[f];
                                    if (val === undefined) {
                                        // Inicializar si no existe
                                        if (f === 'spawnInterval') val = 10000;
                                        else if (f === 'duration') val = 5000;
                                        else if (f === 'radius') val = 250;
                                        else val = 0;
                                        config.mapsConfig[selectedMapId].ambience[idx][f] = val;
                                    }
                                    return `
                                    <div class="field">
                                        <label>${labels[f] || f}</label>
                                        <input type="number" step="0.1" value="${val}" 
                                               onchange="config.mapsConfig['${selectedMapId}'].ambience[${idx}].${f} = parseFloat(this.value)">
                                    </div>`;
                                }).join('')}
                            </div>
                        </div>`;
                    }).join('')}
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
        
        // v1.9.2: Filtrar por Esfera seleccionada
        if (s.type !== currentSkillTab) continue;

        if (f && !name.toLowerCase().includes(f) && !JSON.stringify(s).toLowerCase().includes(f)) continue;
        const card = document.createElement('div'); card.className = 'card';
        if(!s.targetFilters) s.targetFilters = { allies: true, enemies: false, bosses: false, players: true };
        card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                <div class="field" style="flex-grow:1;"><label>Protocolo</label><input type="text" value="${s.name || name}" style="color:var(--accent); font-weight:bold; background:transparent; border:none;" readonly></div>
            </div>
            <div class="form-grid">
                <div class="field"><label>Tipo</label><select onchange="config.skillsData['${name}'].type = this.value"><option value="Defensa" ${s.type==='Defensa'?'selected':''}>Defensa</option><option value="Curación" ${s.type==='Curación'?'selected':''}>Curación</option><option value="Ataque" ${s.type==='Ataque'?'selected':''}>Ataque</option><option value="Utilidad" ${s.type==='Utilidad'?'selected':''}>Utilidad</option></select></div>
                <div class="field"><label>Cooldown (ms)</label><input type="number" value="${s.cd}" onchange="config.skillsData['${name}'].cd = parseInt(this.value)"></div>
                <div class="field"><label>Puntos (pts)</label><input type="number" value="${s.amount || 0}" onchange="config.skillsData['${name}'].amount = parseInt(this.value)"></div>
                <div class="field"><label>Rango (px)</label><input type="number" value="${s.range || 0}" onchange="config.skillsData['${name}'].range = parseInt(this.value)"></div>
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
}

function renderModes() {
    if (!config.gameModes) {
        config.gameModes = {
            hunting: { enabled: true, targets: [], rewardMult: 1.2 },
            extraction: { enabled: true, zones: [], difficulty: 1 },
            arenas: { enabled: true, maps: [], minPlayers: 2 }
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
                                <div style="background:rgba(6,182,212,0.05); border:1px solid rgba(6,182,212,0.2); border-radius:8px; padding:10px;">
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
                                <div style="background:rgba(0,210,255,0.05); border:1px solid rgba(0,210,255,0.2); border-radius:8px; padding:10px;">
                                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                        <input type="text" value="${p.label}" onchange="config.gameModes.extraction.extractPoints[${idx}].label = this.value" style="background:none; border:none; color:var(--primary); font-weight:bold; font-size:0.75rem; width:70%;">
                                        <button onclick="config.gameModes.extraction.extractPoints.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                    </div>
                                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:5px;">
                                        <div class="field"><label>X</label><input type="number" id="ep-x-${idx}" value="${p.x}" onchange="config.gameModes.extraction.extractPoints[${idx}].x = parseInt(this.value)"></div>
                                        <div class="field"><label>Y</label><input type="number" id="ep-y-${idx}" value="${p.y}" onchange="config.gameModes.extraction.extractPoints[${idx}].y = parseInt(this.value)"></div>
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
                                <div style="background:rgba(255,49,49,0.05); border:1px solid rgba(255,49,49,0.2); border-radius:8px; padding:10px;">
                                    <div style="display:flex; flex-direction:column; gap:8px; margin-bottom:8px;">
                                        <div style="display:flex; justify-content:space-between; align-items:center;">
                                            <input type="text" value="${s.label || 'Zona '+ (idx+1)}" onchange="config.gameModes.extraction.spawners[${idx}].label = this.value; renderModes();" style="background:none; border:none; color:var(--danger); font-weight:bold; font-size:0.75rem; width:85%;">
                                            <button onclick="config.gameModes.extraction.spawners.splice(${idx},1); renderModes();" style="background:none; border:none; color:var(--danger); cursor:pointer;">✕</button>
                                        </div>
                                        <select onchange="config.gameModes.extraction.spawners[${idx}].enemyId = this.value; renderModes();" style="background:rgba(255,49,49,0.1); border:1px solid rgba(255,49,49,0.2); color:var(--danger); font-size:0.7rem; width:100%; padding:4px; border-radius:4px; cursor:pointer;">
                                            ${Object.keys(config.enemyModels).map(id => `<option value="${id}" ${s.enemyId === id ? 'selected' : ''}>${config.enemyModels[id].name}</option>`).join('')}
                                        </select>
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
                        <h4 style="color:var(--primary); margin:0;">🛰️ RADAR DE POSICIONAMIENTO GLOBAL</h4>
                        <div style="display:flex; gap:10px;">
                            <button id="btn-radar-spawn" class="btn ${radarMode === 'spawn' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('spawn')">MODO SPAWN</button>
                            <button id="btn-radar-spawner" class="btn ${radarMode === 'spawner' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('spawner')">MODO AMENAZA</button>
                            <button id="btn-radar-extract" class="btn ${radarMode === 'extract' ? 'btn-primary' : 'btn-secondary'}" style="padding: 5px 20px; font-size:0.75rem;" onclick="setRadarMode('extract')">MODO ESCAPE</button>
                        </div>
                    </div>
                    
                    <div style="display:grid; grid-template-columns: 1fr 400px; gap:30px;">
                        <div id="radar-container" style="position:relative; width:600px; height:600px; margin:0 auto; background:#000; border:1px solid var(--primary); border-radius:10px; overflow:hidden; cursor:crosshair;">
                            <canvas id="radar-canvas"></canvas>
                        </div>
                        
                        <div style="display:flex; flex-direction:column; gap:15px; background:rgba(255,255,255,0.02); padding:25px; border-radius:10px;">
                            <label style="color:var(--accent); font-size:0.85rem; margin-bottom:15px; display:block; border-bottom:1px solid rgba(255,255,255,0.1); padding-bottom:10px; font-weight:bold;">🛠️ HERRAMIENTA DE DESPLIEGUE</label>
                            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:15px;">
                                <div class="field"><label>Coord X</label><input type="number" id="radar-x" value="0"></div>
                                <div class="field"><label>Coord Y</label><input type="number" id="radar-y" value="0"></div>
                            </div>
                            <div id="radar-spawn-opts" style="display:${radarMode === 'spawn' ? 'block' : 'none'}">
                                <div class="field" style="margin-top:10px;"><label>Nombre</label><input type="text" id="radar-spawn-label" value="Punto Spawn"></div>
                                <div class="field" style="margin-top:5px;"><label>Radio Burbuja</label><input type="number" id="radar-spawn-radius" value="500"></div>
                            </div>
                            <div id="radar-spawner-opts" style="display:${radarMode === 'spawner' ? 'block' : 'none'}">
                                <div class="field" style="margin-top:10px;"><label>Nombre Zona</label><input type="text" id="radar-spawner-label" value="Zona de Amenaza"></div>
                                <div class="field" style="margin-top:10px;"><label>Enemigo</label>
                                    <select id="spawner-enemy-select" style="width:100%; font-size:0.8rem; background:#111; color:white; border:1px solid #333; padding:8px;">
                                        ${Object.keys(config.enemyModels).map(id => `<option value="${id}">${config.enemyModels[id].name}</option>`).join('')}
                                    </select>
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
    } else if (currentModeTab === 'arenas') {
        content.innerHTML = `
            <div class="card" style="grid-column: span 2;">
                <h3 style="color:#ff3131; margin-bottom: 0.5rem;">⚔️ MODO ARENAS (PVP)</h3>
                <p style="opacity:0.7; margin-bottom:1.5rem;">Configuración de combates competitivos en entornos controlados.</p>
                <div class="form-grid">
                    <div class="field">
                        <label>Estado del Modo</label>
                        <select onchange="config.gameModes.arenas.enabled = this.value === 'true'">
                            <option value="true" ${config.gameModes.arenas.enabled ? 'selected' : ''}>Activo</option>
                            <option value="false" ${!config.gameModes.arenas.enabled ? 'selected' : ''}>Inactivo</option>
                        </select>
                    </div>
                    <div class="field">
                        <label>Jugadores Mínimos por Partida</label>
                        <input type="number" value="${config.gameModes.arenas.minPlayers}" 
                               onchange="config.gameModes.arenas.minPlayers = parseInt(this.value)">
                    </div>
                </div>
            </div>
            <div class="card">
                <h4 style="color:#ff3131; margin-bottom: 1rem;">🏟️ MAPAS DE ARENA</h4>
                <p style="font-size:0.8rem; opacity:0.6;">IDs de mapas reservados para duelos PvP.</p>
                <input type="text" placeholder="Ej: 9, 10" value="${config.gameModes.arenas.maps.join(', ')}"
                       onchange="config.gameModes.arenas.maps = this.value.split(',').map(v => v.trim())"
                       style="margin-top:10px;">
            </div>
        `;
    }
}
