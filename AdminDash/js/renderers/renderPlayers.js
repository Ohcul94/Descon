// AdminDash/js/renderers/renderPlayers.js
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
            expRequirements: Array(30).fill(0).map((_, i) => (i + 1) * 1000),
            sphereOrbitRadius: 350,
            sphereOrbitSpeed: 1.5
        };
    }
    // v680.0: Desbloqueo de slots de esferas por requisitos (4 slots)
    if (!Array.isArray(config.pilotConfig.sphereSlotRequirements) || config.pilotConfig.sphereSlotRequirements.length < 4) {
        const existing = config.pilotConfig.sphereSlotRequirements || [];
        while (existing.length < 4) existing.push({ name: `Slot ${existing.length + 1}`, requirements: [] });
        config.pilotConfig.sphereSlotRequirements = existing;
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
        <div class="card">
            <h4 style="color:var(--accent); margin-bottom:1rem;">🛰️ ÓRBITA DE ESFERAS ALREDEDOR DE LA NAVE</h4>
            <div style="font-size:0.68rem; opacity:0.6; margin-bottom:0.8rem;">Mismo comportamiento que la mecánica "Ataque Orbital": radio en PX, velocidad en rad/s, conversión a 3D con scale_factor + correction_z del mapa. Muestra los valores en uso actualmente; cámbialos cuando quieras y guarda.</div>
            <div class="form-grid">
                <div class="field"><label>RADIO DE ÓRBITA (PX)</label>
                    <input type="number" step="10" min="1" value="${config.pilotConfig.sphereOrbitRadius ?? 350}" onchange="config.pilotConfig.sphereOrbitRadius = parseFloat(this.value)" style="font-family:'JetBrains Mono'; font-weight:bold; color:var(--primary);">
                </div>
                <div class="field"><label>VEL. GIRO (RAD/S)</label>
                    <input type="number" step="0.1" min="0.1" value="${config.pilotConfig.sphereOrbitSpeed ?? 1.5}" onchange="config.pilotConfig.sphereOrbitSpeed = parseFloat(this.value)" style="font-family:'JetBrains Mono'; font-weight:bold; color:var(--primary);">
                </div>
            </div>
        </div>
        <div class="card">
            <h4 style="color:var(--accent); margin-bottom:1rem;">🔮 DESBLOQUEO DE ESFERAS ORBITALES</h4>
            <div style="font-size:0.68rem; opacity:0.6; margin-bottom:0.8rem;">Cada slot se desbloquea cumpliendo sus requisitos (nivel, misión completada, desbloqueo o esferas). Sin requisitos = disponible desde el inicio. El servidor valida siempre; nadie puede abrir un slot por hack.</div>
            ${[0,1,2,3].map(slotIdx => `
                <div style="background:rgba(0,0,0,0.15); border:1px solid rgba(255,255,255,0.06); border-radius:8px; padding:12px; margin-bottom:12px;">
                    <div style="display:flex; align-items:center; gap:8px; margin-bottom:4px;">
                        <span style="color:#c792ea; font-weight:bold; font-size:0.75rem; min-width:70px;">SLOT ${slotIdx + 1}</span>
                        <input type="text" value="${reqAttrEscape((config.pilotConfig.sphereSlotRequirements[slotIdx] || {}).name || '')}" placeholder="Nombre del slot (ej: Núcleo de Combate)" style="flex:1; min-width:120px; background:#1a1a2e; color:#fff; border:1px solid rgba(255,255,255,0.15); border-radius:4px; padding:2px 6px; font-size:0.65rem;" onchange="config.pilotConfig.sphereSlotRequirements[${slotIdx}].name = this.value">
                    </div>
                    ${requirementsSectionHtml('req_slot_' + slotIdx, 'config.pilotConfig.sphereSlotRequirements[' + slotIdx + ']')}
                </div>
            `).join('')}
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
