let socket;
let config = {};

let currentAmmoTab = 'laser';
let currentEnemySubTab = 'regular';
let currentMechTab = 'attack';
let selectedEnemyId = null;
let selectedMapId = null;

function showTab(tabId) {
    localStorage.setItem('admin_last_tab', tabId);
    
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    document.querySelectorAll('.nav-link').forEach(b => b.classList.remove('active'));
    
    const view = document.getElementById('view-' + tabId);
    if(view) view.classList.add('active');
    
    // v267.950: Sincronizar Sidebar (aunque se llame por código)
    const sidebarLink = document.querySelector(`.nav-link[onclick*="showTab('${tabId}')"]`);
    if(sidebarLink) sidebarLink.classList.add('active');
    
    const titles = { 
        'ships': 'Configuración de Naves', 'enemies': 'Gestión de Amenazas', 
        'ammo': 'Mercado: Municiones', 'weapons': 'Mercado: Armamento',
        'shields': 'Mercado: Escudos', 'engines': 'Mercado: Propulsión',
        'skills': 'Protocolos de Combate', 'mechanics': 'Librería de Mecánicas',
        'maps': 'Cartografía Estelar', 'json': 'Núcleo del Sistema',
        'enemy-detail': 'Editor de Entidad', 'map-detail': 'Configuración de Zona'
    };
    document.getElementById('current-view-title').innerText = titles[tabId] || 'Configuración';
    
    if(tabId === 'json') document.getElementById('json-editor').value = JSON.stringify(config, null, 4);
    refreshCurrentTab();
}

function toggleFolder(id) {
    const el = document.getElementById(id);
    el.classList.toggle('show');
    const chevron = el.previousElementSibling.querySelector('.chevron');
    chevron.innerText = el.classList.contains('show') ? '▼' : '▶';
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
        renderAll();
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
        if(data.adminConfig) { config = data.adminConfig; renderAll(); }
        
        // v267.200: Restaurar última vista tras login
        const lastTab = localStorage.getItem('admin_last_tab') || 'ships';
        const lastMap = localStorage.getItem('admin_last_map');
        const lastEnemy = localStorage.getItem('admin_last_enemy');
        
        if (lastTab === 'map-detail' && lastMap) selectMap(lastMap);
        else if (lastTab === 'enemy-detail' && lastEnemy) selectEnemy(lastEnemy);
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

function getFilter() { return (document.getElementById('global-filter')?.value || '').toLowerCase(); }

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
        btn.parentElement.querySelectorAll('.btn-subtab').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
    }
    renderAmmo();
}

function setEnemySubTab(tab) {
    currentEnemySubTab = tab;
    renderEnemies();
}

function setMechTab(tab) {
    currentMechTab = tab;
    renderMechanicsLib();
}

function selectEnemy(id) {
    selectedEnemyId = id;
    localStorage.setItem('admin_last_enemy', id);
    localStorage.setItem('admin_last_tab', 'enemy-detail');
    showTab('enemy-detail');
    renderEnemyDetail();
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
    const m = MOVEMENT_LIB[type];
    m.fields.forEach(f => {
        if(config.enemyModels[id].movementPhases[idx][f] === undefined) {
            config.enemyModels[id].movementPhases[idx][f] = (f==='speed'?3.5:150);
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

function updateMechanicType(enemyId, idx, newType) {
    config.enemyModels[enemyId].mechanics[idx].type = newType;
    renderEnemies();
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
    } else if (config.mechanicsLib) {
        config.mechanicsLib.mega_laser = {
            label: "Mega Láser (Lux)",
            icon: "🔆",
            desc: "Rayo grueso que requiere precarga.",
            fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "chargeTimeMs", "lockTimeMs", "lifetimeMs", "turnSpeed", "startDelay"]
        };
    }
    if (config.movementLib && !config.movementLib.kamikaze) {
        config.movementLib.kamikaze = MOVEMENT_LIB.kamikaze;
    }
}
setTimeout(patchMechanicsLib, 1000);

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
