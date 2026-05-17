let socket;
let config = {};

let currentAmmoTab = 'laser';
let currentEnemySubTab = 'regular';
let currentModeTab = 'hunting';
let currentSkillTab = 'Ataque';
let currentMechTab = 'attack';
let selectedEnemyId = null;
let selectedMapId = null;

let currentSessionSubTab = 'online';
let currentSessionPage = 0;
let lastSessionsTotal = 0;

let selectedDetailPlayer = null;
let currentDetailPage = 0;
let lastDetailTotal = 0;

function showTab(tabId) {
    localStorage.setItem('admin_last_tab', tabId);
    
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    
    // Limpiar clases active de todos los links principales de primer nivel
    document.querySelectorAll('.nav-link:not(.sub)').forEach(b => b.classList.remove('active'));
    // Limpiar clases active de todas las carpetas del menú
    document.querySelectorAll('.nav-folder').forEach(f => f.classList.remove('active'));
    
    const view = document.getElementById('view-' + tabId);
    if(view) view.classList.add('active');
    
    // Resaltar link principal si existe y NO es un sub-enlace
    const sidebarLink = document.querySelector(`.nav-link[onclick*="showTab('${tabId}')"]:not(.sub)`);
    if(sidebarLink) sidebarLink.classList.add('active');

    // Mapeo inteligente y dinámico de carpetas (nav-folder) activas según el tab actual
    const folderMapping = {
        'maps': 'folder-maps', 'map-detail': 'folder-maps',
        'enemies': 'folder-enemies', 'enemy-detail': 'folder-enemies',
        'mechanics': 'folder-mechanics',
        'ammo': 'folder-market', 'weapons': 'folder-market', 'shields': 'folder-market', 'engines': 'folder-market',
        'skills': 'folder-skills',
        'modes': 'folder-modes'
    };
    const parentFolderId = folderMapping[tabId];
    if (parentFolderId) {
        const folderEl = document.getElementById(parentFolderId);
        if (folderEl) {
            const folderHeader = folderEl.previousElementSibling;
            if (folderHeader && folderHeader.classList.contains('nav-folder')) {
                folderHeader.classList.add('active');
            }
        }
    }
    
    const titles = { 
        'ships': 'Configuración de Naves', 'enemies': 'Gestión de Amenazas', 
        'ammo': 'Mercado: Municiones', 'weapons': 'Mercado: Armamento',
        'shields': 'Mercado: Escudos', 'engines': 'Mercado: Propulsión',
        'skills': 'Protocolos de Combate', 'mechanics': 'Librería de Mecánicas',
        'maps': 'Cartografía Estelar', 'json': 'Núcleo del Sistema',
        'sessions': 'Auditoría de Sesiones Estelares',
        'users': 'Gestión de Pilotos Registrados',
        'enemy-detail': 'Editor de Entidad', 'map-detail': 'Configuración de Zona',
        'pilot': 'Perfil Maestro del Piloto',
        'modes': 'Configuración de Modos de Juego'
    };
    document.getElementById('current-view-title').innerText = titles[tabId] || 'Configuración';
    
    if(tabId === 'json') document.getElementById('json-editor').value = JSON.stringify(config, null, 4);
    if(tabId === 'sessions' || tabId === 'users') {
        if (currentSessionSubTab === 'online') socket.emit('getOnlinePlayers');
        else if (currentSessionSubTab === 'history') socket.emit('getSessions', { page: currentSessionPage });
        else if (currentSessionSubTab === 'users') socket.emit('getRegisteredUsers');
    }
    refreshCurrentTab();
}

window.onload = () => {
    const savedUser = localStorage.getItem('admin_user');
    const savedPass = localStorage.getItem('admin_pass');
    if(savedUser && savedPass) {
        document.getElementById('admin-user').value = savedUser;
        document.getElementById('admin-pass').value = savedPass;
        document.getElementById('remember-me').checked = true;
        connect(); 
    }
};

function connect() {
    const user = document.getElementById('admin-user').value;
    const pass = document.getElementById('admin-pass').value;
    const remember = document.getElementById('remember-me').checked;
    const btn = document.querySelector('#login-overlay button');
    const err = document.getElementById('login-error');

    // Siempre conectar LOCAL para desarrollo
    const targetUrl = "http://127.0.0.1:3333";
    
    btn.innerText = "CONECTANDO A LOCAL...";
    socket = io(targetUrl);

    socket.on('connect', () => socket.emit('login', { user, password: pass, isAdmin: true }));

    socket.on('adminConfigUpdated', (data) => {
        config = data;
        patchMechanicsLib();
        renderAll();
    });

    socket.on('sessionsHistory', (data) => {
        lastSessionsTotal = data.total;
        currentSessionPage = data.page;
        renderSessions(data.sessions);
        document.getElementById('page-indicator').innerText = `PÁGINA ${currentSessionPage + 1} de ${Math.ceil(lastSessionsTotal/50)}`;
    });

    socket.on('playerSessionsDetail', (data) => {
        lastDetailTotal = data.total;
        currentDetailPage = data.page;
        renderPlayerSessionsModal(data);
    });

    socket.on('onlinePlayersList', (data) => {
        renderOnlinePlayers(data);
    });

    socket.on('registeredUsersList', (data) => {
        renderRegisteredUsers(data);
    });

    socket.on('loginSuccess', (data) => {
        if(remember) {
            localStorage.setItem('admin_user', user);
            localStorage.setItem('admin_pass', pass);
        } else {
            localStorage.removeItem('admin_user');
            localStorage.removeItem('admin_pass');
        }
        document.getElementById('login-overlay').style.display = 'none';
        document.getElementById('conn-dot').classList.add('online');
        document.getElementById('conn-text').innerText = "ONLINE: " + user.toUpperCase();
        if(data.adminConfig) { 
            config = data.adminConfig; 
            // v1.9: Inicializar configuración de piloto si es nueva
            if (!config.pilotConfig) {
                config.pilotConfig = {
                    startingHubs: 0,
                    startingOhcu: 0,
                    startingShipId: 1,
                    startingMapId: 1,
                    startingAmmo: {
                        laser: [1000, 0, 0, 0, 0, 0],
                        missile: [50, 0, 0, 0, 0, 0],
                        mine: [10, 0, 0, 0, 0, 0]
                    },
                    expRequirements: Array(30).fill(0).map((_, i) => (i + 1) * 1000)
                };
            }

            // v2.1: Inicializar estructura de Modos de Juego si no existe
            if (!config.gameModes) {
                config.gameModes = {
                    hunting: { enabled: true, targets: [], rewardMult: 1.2 },
                    extraction: { 
                        enabled: true, 
                        maxPlayers: 21, 
                        countdownTime: 10, 
                        extractRadius: 150,
                        maps: [2],
                        extractPoints: [
                            { x: 1500, y: 1500, label: "Punto Alfa" },
                            { x: 8500, y: 8500, label: "Punto Beta" },
                            { x: 5000, y: 500, label: "Punto Gamma" }
                        ]
                    },
                    arenas: { enabled: true, maps: [], minPlayers: 2 }
                };
            }
            patchMechanicsLib();
            renderAll(); 
        }
        
        // v267.200: Restaurar última vista tras login
        const lastTab = localStorage.getItem('admin_last_tab') || 'ships';
        const lastMap = localStorage.getItem('admin_last_map');
        const lastEnemy = localStorage.getItem('admin_last_enemy');
        const lastSessionTab = localStorage.getItem('admin_last_session_tab');
        
        if (lastTab === 'map-detail' && lastMap) selectMap(lastMap);
        else if (lastTab === 'enemy-detail' && lastEnemy) selectEnemy(lastEnemy);
        else if (lastTab === 'sessions' || lastTab === 'users') {
            if (lastSessionTab) setSessionSubTab(lastSessionTab);
            else showTab(lastTab);
        }
        else showTab(lastTab);
    });

    socket.on('disconnect', () => {
        document.getElementById('conn-dot').classList.remove('online');
        document.getElementById('conn-text').innerText = "OFFLINE";
    });

    socket.on('connect_error', (e) => {
        err.innerText = "ERROR DE CONEXIÓN: Verifica el servidor.";
        err.style.display = 'block';
        btn.innerText = "REINTENTAR";
    });

    socket.on('authError', (msg) => {
        err.innerText = msg;
        err.style.display = 'block';
        btn.innerText = "REINTENTAR";
    });
}

function getFilter() { 
    return (document.getElementById('global-filter')?.value || '').toLowerCase(); 
}

function toggleFolder(id, event) {
    if (event) event.stopPropagation();
    const el = document.getElementById(id);
    if (!el) return;
    
    el.classList.toggle('show');
    
    // Buscar el chevron en el elemento que disparó el click
    const header = document.querySelector(`[onclick*="${id}"]`);
    if (header) {
        const chevron = header.querySelector('.chevron');
        if (chevron) {
            chevron.innerText = el.classList.contains('show') ? '▼' : '▶';
        }
    }
}

function selectMap(id) {
    selectedMapId = id;
    localStorage.setItem('admin_last_map', id);
    localStorage.setItem('admin_last_tab', 'map-detail');
    showTab('map-detail');
    renderMapDetail();
}

function setAmmoTab(tab, btn) {
    currentAmmoTab = tab;
    if (btn) {
        document.querySelectorAll('.nav-link.sub').forEach(l => l.classList.remove('active'));
        btn.classList.add('active');
    }
    renderAmmo();
}

function setEnemySubTab(tab, btn) {
    currentEnemySubTab = tab;
    if (btn) {
        document.querySelectorAll('.nav-link.sub').forEach(l => l.classList.remove('active'));
        btn.classList.add('active');
    }
    renderEnemies();
}

function setModeTab(tab, btn) {
    currentModeTab = tab;
    if (btn) {
        document.querySelectorAll('.nav-link.sub').forEach(l => l.classList.remove('active'));
        btn.classList.add('active');
    }
    renderModes();
}

function setSkillTab(tab, btn) {
    currentSkillTab = tab;
    if (btn) {
        document.querySelectorAll('.nav-link.sub').forEach(l => l.classList.remove('active'));
        btn.classList.add('active');
    }
    renderSkills();
}

function setMechTab(tab, btn) {
    currentMechTab = tab;
    if (btn) {
        document.querySelectorAll('.nav-link.sub').forEach(l => l.classList.remove('active'));
        btn.classList.add('active');
    }
    renderMechanicsLib();
}

function selectEnemy(id) {
    selectedEnemyId = id;
    localStorage.setItem('admin_last_enemy', id);
    localStorage.setItem('admin_last_tab', 'enemy-detail');
    showTab('enemy-detail');
    renderEnemyDetail();
}

function setSessionSubTab(tab) {
    currentSessionSubTab = tab;
    localStorage.setItem('admin_last_session_tab', tab);
    if (tab === 'users') showTab('users');
    else showTab('sessions');
    
    // Actualizar estados visuales en el sidebar
    document.querySelectorAll('#folder-audit .nav-link').forEach(b => b.classList.remove('active'));
    document.getElementById('nav-sessions-' + tab).classList.add('active');
    
    if (tab === 'online') {
        socket.emit('getOnlinePlayers');
        document.getElementById('pagination-controls').style.display = 'none';
        document.getElementById('th-session-extra').innerText = 'LATENCIA';
        document.getElementById('th-session-ip-total').innerText = 'DIRECCIÓN IP';
    } else if (tab === 'history') {
        currentSessionPage = 0;
        socket.emit('getSessions', { page: currentSessionPage });
        document.getElementById('pagination-controls').style.display = 'flex';
        document.getElementById('th-session-extra').innerText = 'ÚLTIMA SALIDA';
        document.getElementById('th-session-ip-total').innerText = 'TOTAL SESIONES';
    } else if (tab === 'users') {
        socket.emit('getRegisteredUsers');
    }
}

function openPlayerSessionsModal(username) {
    selectedDetailPlayer = username;
    currentDetailPage = 0;
    socket.emit('getPlayerSessions', { username: username, page: 0 });
    document.getElementById('player-sessions-overlay').style.display = 'flex';
    document.getElementById('modal-player-name').innerText = `HISTORIAL: ${username.toUpperCase()}`;
}

function closePlayerSessionsModal() {
    document.getElementById('player-sessions-overlay').style.display = 'none';
}

function changePlayerDetailPage(dir) {
    const newPage = currentDetailPage + dir;
    if (newPage < 0) return;
    if (newPage >= Math.ceil(lastDetailTotal / 30)) return;
    
    currentDetailPage = newPage;
    socket.emit('getPlayerSessions', { username: selectedDetailPlayer, page: newPage });
}

function changeSessionPage(dir) {
    const newPage = currentSessionPage + dir;
    if (newPage < 0) return;
    if (newPage >= Math.ceil(lastSessionsTotal / 50)) return;
    
    currentSessionPage = newPage;
    socket.emit('getSessions', { page: currentSessionPage });
}

function logout() {
    localStorage.removeItem('admin_user');
    localStorage.removeItem('admin_pass');
    localStorage.removeItem('admin_last_tab');
    location.reload();
}

function addAmmoMechanic(type, idx) {
    if(!config.shopItems.ammo[type][idx].mechanics) config.shopItems.ammo[type][idx].mechanics = [];
    config.shopItems.ammo[type][idx].mechanics.push({ type: "bleed", damagePerSecond: 5, duration: 3000 });
    renderAmmo();
}

function addMovementPhase(id) {
    if(!config.enemyModels[id].movementPhases) config.enemyModels[id].movementPhases = [];
    config.enemyModels[id].movementPhases.push({ type: "chase", speed: 3.5, stopDist: 150, startDelay: 2000 });
}

function removeMovementPhase(id, idx) {
    config.enemyModels[id].movementPhases.splice(idx, 1);
}

function updateMovementPhaseType(id, idx, type) {
    config.enemyModels[id].movementPhases[idx].type = type;
    const lib = (config.movementLib && config.movementLib[type]) ? config.movementLib[type] : DEFAULT_MOVEMENT_LIB[type];
    lib.fields.forEach(f => {
        if(config.enemyModels[id].movementPhases[idx][f] === undefined) {
            if (f === 'speed') config.enemyModels[id].movementPhases[idx][f] = 3.5;
            else if (f === 'radius') config.enemyModels[id].movementPhases[idx][f] = 200;
            else if (f === 'speedBonus') config.enemyModels[id].movementPhases[idx][f] = 50;
            else if (f === 'intervalMs') config.enemyModels[id].movementPhases[idx][f] = 500;
            else if (f === 'duration') config.enemyModels[id].movementPhases[idx][f] = 5000;
            else if (f === 'cooldown') config.enemyModels[id].movementPhases[idx][f] = 10000;
            else if (f === 'affectsEnemies') config.enemyModels[id].movementPhases[idx][f] = false;
            else if (f === 'affectsBosses') config.enemyModels[id].movementPhases[idx][f] = false;
            else config.enemyModels[id].movementPhases[idx][f] = 150;
        }
    });
}

function moveMovementPhase(id, idx, dir) {
    const arr = config.enemyModels[id].movementPhases;
    const newIdx = idx + dir;
    if(newIdx < 0 || newIdx >= arr.length) return;
    [arr[idx], arr[newIdx]] = [arr[newIdx], arr[idx]];
}

function addMechanic(enemyId) {
    if (!config.enemyModels[enemyId].mechanics) config.enemyModels[enemyId].mechanics = [];
    config.enemyModels[enemyId].mechanics.push({
        type: "laser",
        bulletDamage: 10,
        bulletSpeed: 800,
        fireRange: 600,
        fireRate: 1000
    });
    renderEnemies();
}

function removeMechanic(enemyId, idx) {
    if (config.enemyModels[enemyId].mechanics.length <= 1) {
        alert("El enemigo debe tener al menos una mecánica.");
        return;
    }
    config.enemyModels[enemyId].mechanics.splice(idx, 1);
    renderEnemies();
}

function addDefenseMechanic(enemyId) {
    if (!config.enemyModels[enemyId].defenseMechanics) config.enemyModels[enemyId].defenseMechanics = [];
    config.enemyModels[enemyId].defenseMechanics.push({
        type: "basic_defense",
        reductionPercentage: 10,
        shieldRegen: 5,
        duration: 5000,
        cooldown: 10000,
        startDelay: 0
    });
    renderEnemyDetail();
}

function removeDefenseMechanic(enemyId, idx) {
    config.enemyModels[enemyId].defenseMechanics.splice(idx, 1);
    renderEnemyDetail();
}

function updateDefenseMechanicType(enemyId, idx, newType) {
    const mech = config.enemyModels[enemyId].defenseMechanics[idx];
    mech.type = newType;
    
    // Inicializar campos según la LIB
    const lib = (config.defenseLib && config.defenseLib[newType]) ? config.defenseLib[newType] : DEFAULT_DEFENSE_LIB[newType];
    lib.fields.forEach(f => {
        if (mech[f] === undefined) {
            if (f === 'reductionPercentage') mech[f] = 10;
            else if (f === 'shieldRegen') mech[f] = 5;
            else if (f === 'radius') mech[f] = 300;
            else if (f === 'healAmount') mech[f] = 20;
            else if (f === 'intervalMs') mech[f] = 500;
            else if (f === 'duration') mech[f] = 5000;
            else if (f === 'cooldown') mech[f] = 10000;
            else if (f === 'affectsEnemies') mech[f] = false;
            else if (f === 'affectsBosses') mech[f] = false;
            else mech[f] = 0;
        }
    });
    renderEnemyDetail();
}

function moveDefenseMechanic(enemyId, idx, dir) {
    const list = config.enemyModels[enemyId].defenseMechanics;
    const newIdx = idx + dir;
    if (newIdx < 0 || newIdx >= list.length) return;
    [list[idx], list[newIdx]] = [list[newIdx], list[idx]];
    renderEnemyDetail();
}

function updateMechanicType(enemyId, idx, newType) {
    const mech = config.enemyModels[enemyId].mechanics[idx];
    mech.type = newType;
    const lib = (config.mechanicsLib && config.mechanicsLib[newType]) ? config.mechanicsLib[newType] : DEFAULT_MECHANICS_LIB[newType];
    lib.fields.forEach(f => {
        if (mech[f] === undefined) {
            if (f === 'radius') mech[f] = 250;
            else if (f === 'damage') mech[f] = 15;
            else if (f === 'intervalMs') mech[f] = 1000;
            else if (f === 'duration') mech[f] = 5000;
            else if (f === 'cooldown') mech[f] = 10000;
            else if (f === 'bulletDamage') mech[f] = 10;
            else if (f === 'bulletSpeed') mech[f] = 800;
            else if (f === 'fireRange') mech[f] = 600;
            else if (f === 'fireRate') mech[f] = 1000;
            else mech[f] = 0;
        }
    });
    renderEnemyDetail();
}

function moveMechanic(enemyId, idx, dir) {
    const list = config.enemyModels[enemyId].mechanics;
    if (dir === -1 && idx > 0) {
        [list[idx-1], list[idx]] = [list[idx], list[idx-1]];
    } else if (dir === 1 && idx < list.length - 1) {
        [list[idx+1], list[idx]] = [list[idx], list[idx+1]];
    }
    renderEnemies();
}

function addAmbience(id) {
    if(!config.mapsConfig[id].ambience) config.mapsConfig[id].ambience = [];
    config.mapsConfig[id].ambience.push({ type: "radiation", damage: 10, intervalMs: 300 });
}

function updateAmbienceType(mapId, idx, newType) {
    const hazard = config.mapsConfig[mapId].ambience[idx];
    hazard.type = newType;
    
    // Limpiar campos específicos del tipo anterior para evitar basura
    const lib = AMBIENCE_LIB[newType];
    const newHazard = { type: newType };
    
    // Inicializar campos requeridos con valores por defecto
    lib.fields.forEach(f => {
        if (f === 'spawnInterval') newHazard[f] = 15000;
        else if (f === 'duration') newHazard[f] = 5000;
        else if (f === 'radius') newHazard[f] = 300;
        else if (f === 'shakeIntensity') newHazard[f] = 10;
        else if (f === 'staticIntensity') newHazard[f] = 0.3;
        else if (f === 'slowPercentage') newHazard[f] = 30;
        else if (f === 'slowFixed') newHazard[f] = 0;
        else if (f === 'damage') newHazard[f] = 10;
        else if (f === 'intervalMs') newHazard[f] = 500;
        else newHazard[f] = 0;
    });
    
    config.mapsConfig[mapId].ambience[idx] = newHazard;
    renderMapDetail();
}

function addMapSpawn(id) {
    if(!config.mapsConfig[id].spawns) config.mapsConfig[id].spawns = [];
    config.mapsConfig[id].spawns.push({ type: "1", count: 5, intervalMs: 5000 });
}

function patchMechanicsLib() {
    if (!config) return;

    // v268.600: Sincronización automática usando constantes BASE para evitar sobrescritura
    const libsMap = [
        { configKey: 'mechanicsLib', base: DEFAULT_MECHANICS_LIB },
        { configKey: 'movementLib', base: DEFAULT_MOVEMENT_LIB },
        { configKey: 'defenseLib', base: DEFAULT_DEFENSE_LIB }
    ];

    libsMap.forEach(item => {
        if (!config[item.configKey]) {
            config[item.configKey] = JSON.parse(JSON.stringify(item.base));
        } else {
            for (let type in item.base) {
                if (!config[item.configKey][type]) {
                    config[item.configKey][type] = JSON.parse(JSON.stringify(item.base[type]));
                } else {
                    // v268.620: Forzar sincronización de la estructura de campos
                    config[item.configKey][type].fields = [...item.base[type].fields];
                    config[item.configKey][type].label = item.base[type].label;
                    config[item.configKey][type].icon = item.base[type].icon;
                }
            }
        }
    });

    // Parches específicos de campos (retrocompatibilidad)
    if (config.mechanicsLib && config.mechanicsLib.laser) {
        if (!config.mechanicsLib.laser.fields.includes("isHoming")) config.mechanicsLib.laser.fields.push("isHoming");
        if (!config.mechanicsLib.laser.fields.includes("turnSpeed")) config.mechanicsLib.laser.fields.push("turnSpeed");
    }
    if (config.mechanicsLib && config.mechanicsLib.missile) {
        if (!config.mechanicsLib.missile.fields.includes("lifetimeMs")) config.mechanicsLib.missile.fields.push("lifetimeMs");
        if (!config.mechanicsLib.missile.fields.includes("turnSpeed")) config.mechanicsLib.missile.fields.push("turnSpeed");
        if (!config.mechanicsLib.missile.fields.includes("isHoming")) config.mechanicsLib.missile.fields.push("isHoming");
    }
    if (config.mechanicsLib && config.mechanicsLib.ice_missile) {
        if (!config.mechanicsLib.ice_missile.fields.includes("lifetimeMs")) config.mechanicsLib.ice_missile.fields.push("lifetimeMs");
        if (!config.mechanicsLib.ice_missile.fields.includes("turnSpeed")) config.mechanicsLib.ice_missile.fields.push("turnSpeed");
        if (!config.mechanicsLib.ice_missile.fields.includes("isHoming")) config.mechanicsLib.ice_missile.fields.push("isHoming");
    }
    if (config.mechanicsLib && config.mechanicsLib.mega_laser) {
        const ml = config.mechanicsLib.mega_laser;
        if (!ml.fields.includes("lifetimeMs")) ml.fields.push("lifetimeMs");
        if (!ml.fields.includes("turnSpeed")) ml.fields.push("turnSpeed");
        if (!ml.fields.includes("lockTimeMs")) ml.fields.push("lockTimeMs");
        if (!ml.fields.includes("isHoming")) ml.fields.push("isHoming");
    }
    renderAll();
}

function showToast(msg) {
    document.getElementById('toast-msg').innerText = msg;
    document.getElementById('toast-overlay').style.display = 'flex';
}

function hideToast() {
    document.getElementById('toast-overlay').style.display = 'none';
}

function saveConfig() {
    if(!socket || !socket.connected) {
        showToast("ERROR: No hay conexión con el servidor cósmico.");
        return;
    }

    if(document.getElementById('view-json').classList.contains('active')) {
        try { config = JSON.parse(document.getElementById('json-editor').value); } 
        catch(e) { showToast("ERROR JSON: " + e.message); return; }
    }
    
    console.log("Enviando configuración al servidor...", config);
    socket.emit('saveAdminConfig', config);
    showToast("Configuración Local Sincronizada.");
}

function openConfirm(msg, title = "CONFIRMACIÓN") {
    return new Promise((resolve) => {
        document.getElementById('confirm-title').innerText = title;
        document.getElementById('confirm-msg').innerText = msg;
        document.getElementById('confirm-overlay').style.display = 'flex';
        
        const okBtn = document.getElementById('confirm-ok-btn');
        const newOkBtn = okBtn.cloneNode(true); // Limpiar listeners viejos
        okBtn.parentNode.replaceChild(newOkBtn, okBtn);
        
        newOkBtn.onclick = () => {
            document.getElementById('confirm-overlay').style.display = 'none';
            resolve(true);
        };
    });
}

function closeConfirm(val) {
    document.getElementById('confirm-overlay').style.display = 'none';
    // Nota: El resolve se maneja en el onclick del botón OK. 
    // Si es falso, simplemente cerramos y no resolvemos (o resolvemos false si fuera necesario)
}

async function deployToCloud() {
    if (!config) return;
    const user = document.getElementById('admin-user').value;
    const pass = document.getElementById('admin-pass').value;

    const confirmed = await openConfirm(
        "¿Estás seguro de desplegar TODA la configuración local al Servidor de Producción (Oracle)?\n\nEsto afectará a todos los jugadores activos.",
        "🚀 DESPLIEGUE A NUBE"
    );
    
    if (!confirmed) return;

    showToast("🚀 INICIANDO DESPLIEGUE A NUBE...");
    
    // Crear conexión temporal a Oracle
    const cloudSocket = io("http://138.2.241.76:3333");
    
    cloudSocket.on('connect', () => {
        cloudSocket.emit('login', { user, password: pass, isAdmin: true });
    });

    cloudSocket.on('loginSuccess', () => {
        console.log("[CLOUD-DEPLOY] Login exitoso. Enviando config...");
        cloudSocket.emit('saveAdminConfig', config);
        showToast("✅ DESPLIEGUE EXITOSO: La nube ha sido actualizada.");
        setTimeout(() => { cloudSocket.disconnect(); }, 1000);
    });

    cloudSocket.on('authError', (msg) => {
        showToast("❌ ERROR DE AUTENTICACIÓN EN NUBE: " + msg);
        cloudSocket.disconnect();
    });

    cloudSocket.on('connect_error', () => {
        showToast("❌ ERROR: No se pudo alcanzar el servidor de Oracle.");
        cloudSocket.disconnect();
    });
}

function addExtractionMap() {
    const mapId = document.getElementById('add-ext-map-select').value;
    if (!config.gameModes.extraction.maps.includes(parseInt(mapId))) {
        config.gameModes.extraction.maps.push(parseInt(mapId));
        renderModes();
    }
}

function addExtractionMechanic() {
    const mech = document.getElementById('add-ext-mech-select').value;
    if (!config.gameModes.extraction.mechanics) config.gameModes.extraction.mechanics = [];
    if (!config.gameModes.extraction.mechanics.includes(mech)) {
        config.gameModes.extraction.mechanics.push(mech);
        renderModes();
    }
}

function toggleExtractionMap(id, enabled) {
    if (!config.gameModes.extraction.maps) config.gameModes.extraction.maps = [];
    if (enabled) {
        if (!config.gameModes.extraction.maps.includes(id)) config.gameModes.extraction.maps.push(id);
    } else {
        config.gameModes.extraction.maps = config.gameModes.extraction.maps.filter(m => m !== id);
    }
}

let radarMode = 'spawner'; // 'spawner' o 'extract'
function setRadarMode(mode) {
    radarMode = mode;
    
    // Actualizar visual de botones
    const btnSpawner = document.getElementById('btn-radar-spawner');
    const btnExtract = document.getElementById('btn-radar-extract');
    
    if (btnSpawner && btnExtract) {
        if (mode === 'spawner') {
            btnSpawner.classList.replace('btn-secondary', 'btn-primary');
            btnExtract.classList.replace('btn-primary', 'btn-secondary');
        } else {
            btnSpawner.classList.replace('btn-primary', 'btn-secondary');
            btnExtract.classList.replace('btn-secondary', 'btn-primary');
        }
    }

    const modeText = document.getElementById('radar-mode-text');
    if (modeText) modeText.innerText = mode === 'spawner' ? 'SPAWNER' : (mode === 'spawn' ? 'SPAWN' : 'ESCAPE');
    
    document.getElementById('radar-spawner-opts').style.display = mode === 'spawner' ? 'block' : 'none';
    document.getElementById('radar-extract-opts').style.display = mode === 'extract' ? 'block' : 'none';
    document.getElementById('radar-spawn-opts').style.display = mode === 'spawn' ? 'block' : 'none';
}

function initRadar() {
    const canvas = document.getElementById('radar-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const container = document.getElementById('radar-container');
    const scale = canvas.width / 10000;
    
    // Estado de arrastre
    let isDragging = false;
    let dragItem = null; // { type: 'extract'|'spawner'|'spawn', index: number }

    const updateCanvasSize = () => {
        canvas.width = container.clientWidth;
        canvas.height = container.clientHeight;
    };
    window.addEventListener('resize', updateCanvasSize);
    updateCanvasSize();

    // Convertir de coordenadas de mundo (10000) a coordenadas de canvas
    const worldToCanvas = (wx, wy) => ({
        x: (wx / 10000) * canvas.width,
        y: (wy / 10000) * canvas.height
    });

    // Convertir de canvas a mundo
    const canvasToWorld = (cx, cy) => ({
        wx: (cx / canvas.width) * 10000,
        wy: (cy / canvas.height) * 10000
    });

    canvas.onmousedown = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        // 1. Buscar en Puntos de Extracción
        const points = config.gameModes.extraction.extractPoints || [];
        for (let i = 0; i < points.length; i++) {
            const pos = worldToCanvas(points[i].x, points[i].y);
            const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
            if (dist < 15) { // Radio de colisión para agarrar
                isDragging = true;
                dragItem = { type: 'extract', index: i };
                canvas.style.cursor = 'grabbing';
                return;
            }
        }

        // 2. Buscar en Amenazas (Spawners)
        const spawners = config.gameModes.extraction.spawners || [];
        for (let i = 0; i < spawners.length; i++) {
            const pos = worldToCanvas(spawners[i].x, spawners[i].y);
            const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
            if (dist < 15) {
                isDragging = true;
                dragItem = { type: 'spawner', index: i };
                canvas.style.cursor = 'grabbing';
                return;
            }
        }

        // 3. Buscar en Spawn Points (Players)
        const spawnPoints = config.gameModes.extraction.spawnPoints || [];
        for (let i = 0; i < spawnPoints.length; i++) {
            const pos = worldToCanvas(spawnPoints[i].x, spawnPoints[i].y);
            const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
            if (dist < 15) {
                isDragging = true;
                dragItem = { type: 'spawn', index: i };
                canvas.style.cursor = 'grabbing';
                return;
            }
        }

        // Si no agarró nada, capturar coordenadas para el input de "Fijar"
        const world = canvasToWorld(mouseX, mouseY);
        document.getElementById('radar-x').value = Math.round(world.wx);
        document.getElementById('radar-y').value = Math.round(world.wy);
    };

    window.onmousemove = (e) => {
        if (!isDragging || !dragItem) return;
        
        const rect = canvas.getBoundingClientRect();
        const mouseX = Math.max(0, Math.min(canvas.width, e.clientX - rect.left));
        const mouseY = Math.max(0, Math.min(canvas.height, e.clientY - rect.top));
        const world = canvasToWorld(mouseX, mouseY);

        if (dragItem.type === 'extract') {
            const p = config.gameModes.extraction.extractPoints[dragItem.index];
            p.x = Math.round(world.wx);
            p.y = Math.round(world.wy);
            const ix = document.getElementById(`ep-x-${dragItem.index}`);
            const iy = document.getElementById(`ep-y-${dragItem.index}`);
            if (ix) ix.value = p.x;
            if (iy) iy.value = p.y;
        } else if (dragItem.type === 'spawner') {
            const s = config.gameModes.extraction.spawners[dragItem.index];
            s.x = Math.round(world.wx);
            s.y = Math.round(world.wy);
            const ix = document.getElementById(`sp-x-${dragItem.index}`);
            const iy = document.getElementById(`sp-y-${dragItem.index}`);
            if (ix) ix.value = s.x;
            if (iy) iy.value = s.y;
        } else if (dragItem.type === 'spawn') {
            const sw = config.gameModes.extraction.spawnPoints[dragItem.index];
            sw.x = Math.round(world.wx);
            sw.y = Math.round(world.wy);
            const ix = document.getElementById(`spw-x-${dragItem.index}`);
            const iy = document.getElementById(`spw-y-${dragItem.index}`);
            if (ix) ix.value = sw.x;
            if (iy) iy.value = sw.y;
        }
    };

    window.onmouseup = () => {
        if (isDragging) {
            isDragging = false;
            dragItem = null;
            canvas.style.cursor = 'crosshair';
        }
    };

    const draw = () => {
        if (!document.getElementById('radar-canvas')) return;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        // Dibujar Grid
        ctx.strokeStyle = 'rgba(0, 210, 255, 0.1)';
        ctx.lineWidth = 1;
        for (let i = 1; i < 5; i++) {
            ctx.beginPath();
            ctx.moveTo((canvas.width / 5) * i, 0);
            ctx.lineTo((canvas.width / 5) * i, canvas.height);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(0, (canvas.height / 5) * i);
            ctx.lineTo(canvas.width, (canvas.height / 5) * i);
            ctx.stroke();
        }

        // Dibujar Spawn Points (Players) - AMARILLO
        if (config.gameModes.extraction.spawnPoints) {
            config.gameModes.extraction.spawnPoints.forEach((p, idx) => {
                const pos = worldToCanvas(p.x, p.y);
                const radiusCanvas = (p.radius / 10000) * canvas.width;
                const isSelected = isDragging && dragItem && dragItem.type === 'spawn' && dragItem.index === idx;

                // Burbuja (Dashed)
                ctx.beginPath();
                ctx.setLineDash([5, 5]);
                ctx.arc(pos.x, pos.y, radiusCanvas, 0, Math.PI * 2);
                ctx.strokeStyle = 'rgba(255, 204, 0, 0.4)';
                ctx.stroke();
                ctx.setLineDash([]);

                // Punto
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, 6, 0, Math.PI * 2);
                ctx.fillStyle = isSelected ? '#fff' : '#ffcc00';
                ctx.fill();
                ctx.strokeStyle = '#ffcc00';
                ctx.stroke();

                // Etiqueta
                ctx.fillStyle = '#ffcc00';
                ctx.font = '10px Outfit';
                ctx.textAlign = 'center';
                ctx.fillText(p.label || 'Spawn', pos.x, pos.y - 12);
            });
        }

        // Dibujar Puntos de Extracción - AZUL
        const points = config.gameModes.extraction.extractPoints || [];
        points.forEach((p, idx) => {
            const pos = worldToCanvas(p.x, p.y);
            const isSelected = isDragging && dragItem && dragItem.type === 'extract' && dragItem.index === idx;
            
            ctx.fillStyle = isSelected ? '#fff' : 'rgba(0, 210, 255, 0.3)';
            ctx.strokeStyle = '#00d2ff';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 8, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#00d2ff';
            ctx.font = '10px Outfit';
            ctx.textAlign = 'center';
            ctx.fillText(p.label, pos.x, pos.y - 15);
        });

        // Dibujar Spawners - ROJO
        const spawners = config.gameModes.extraction.spawners || [];
        spawners.forEach((s, idx) => {
            const pos = worldToCanvas(s.x, s.y);
            const isSelected = isDragging && dragItem && dragItem.type === 'spawner' && dragItem.index === idx;
            const radiusCanvas = (s.radius / 10000) * canvas.width;

            ctx.fillStyle = isSelected ? '#fff' : 'rgba(255, 49, 49, 0.1)';
            ctx.strokeStyle = '#ff3131';
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, radiusCanvas, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#ff3131';
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 5, 0, Math.PI * 2);
            ctx.fill();

            // Etiqueta de Zona - Siempre por encima del radio
            ctx.fillStyle = '#ff3131';
            ctx.font = 'bold 11px Outfit';
            ctx.textAlign = 'center';
            ctx.fillText(s.label || 'Zona Enemiga', pos.x, pos.y - radiusCanvas - 6);
        });

        requestAnimationFrame(draw);
    };
    draw();
}

function addFromRadar() {
    const x = parseInt(document.getElementById('radar-x').value);
    const y = parseInt(document.getElementById('radar-y').value);
    
    if (radarMode === 'spawner') {
        config.gameModes.extraction.spawners.push({
            x, y,
            label: document.getElementById('radar-spawner-label').value,
            enemyId: document.getElementById('spawner-enemy-select').value,
            count: parseInt(document.getElementById('radar-count').value),
            radius: parseInt(document.getElementById('radar-radius').value)
        });
    } else if (radarMode === 'extract') {
        config.gameModes.extraction.extractPoints.push({
            x, y,
            label: document.getElementById('radar-label').value
        });
    } else if (radarMode === 'spawn') {
        if (!config.gameModes.extraction.spawnPoints) config.gameModes.extraction.spawnPoints = [];
        config.gameModes.extraction.spawnPoints.push({
            x, y,
            label: document.getElementById('radar-spawn-label').value,
            radius: parseInt(document.getElementById('radar-spawn-radius').value)
        });
    }
    renderModes();
}

function addExtractionMechanic() {
    const select = document.getElementById('add-ext-mech-select');
    if (!select) return;
    const type = select.value;
    if (!config.gameModes.extraction.mechanics) config.gameModes.extraction.mechanics = [];
    if (!config.gameModes.extraction.mechanics.includes(type)) {
        config.gameModes.extraction.mechanics.push(type);
        renderModes();
    }
}

function addExtractionMap() {
    const select = document.getElementById('add-ext-map-select');
    if (!select) return;
    const mapId = parseInt(select.value);
    if (!config.gameModes.extraction.maps) config.gameModes.extraction.maps = [];
    if (!config.gameModes.extraction.maps.includes(mapId)) {
        config.gameModes.extraction.maps.push(mapId);
        renderModes();
    }
}

function toggleSidebar() {
    const nav = document.getElementById('sidebar');
    nav.classList.toggle('collapsed');
    
    const btn = document.getElementById('sidebar-toggle');
    if (nav.classList.contains('collapsed')) {
        btn.innerHTML = '⮕';
        btn.style.color = 'var(--accent)';
        btn.style.background = 'rgba(6, 182, 212, 0.1)';
    } else {
        btn.innerHTML = '☰';
        btn.style.color = 'var(--text-dim)';
        btn.style.background = 'rgba(255, 255, 255, 0.05)';
    }
}
