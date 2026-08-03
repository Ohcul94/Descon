let socket;
let chatSocket = null;
let config = {};

let currentAmmoTab = 'laser';
let currentEnemySubTab = 'regular';
let currentModeTab = localStorage.getItem('admin_last_mode_tab') || 'hunting';
let currentSkillTab = localStorage.getItem('admin_last_skill_tab') || 'Ataque';
let currentMechTab = 'attack';
let selectedEnemyId = null;
let selectedLootEnemyId = null;
let selectedMapId = null;
let folderToggledThisClick = null;

let currentSessionSubTab = 'online';
let currentSessionPage = 0;
let lastSessionsTotal = 0;
let focusedRadarItem = null;
let activeArenaMapId = null;
let activeArenaPillarIndex = null;
let activeArenaSpawnIndex = null;
let telemetryInterval = null;

let selectedDetailPlayer = null;
let currentDetailPage = 0;
let lastDetailTotal = 0;

// v370.1: Entorno de servidor activo (local o cloud)
const SERVER_URLS = {
    local: 'http://127.0.0.1:3333',
    cloud: 'http://138.2.241.76:3333'
};
let activeEnv = localStorage.getItem('admin_env') || 'local';
let socketLocal = null;
let socketCloud = null;
let activePerformanceEnv = localStorage.getItem('admin_perf_env') || 'local';

function setEnv(env) {
    activeEnv = env;
    localStorage.setItem('admin_env', env);
    const btnLocal = document.getElementById('env-local');
    const btnCloud = document.getElementById('env-cloud');
    const urlDisplay = document.getElementById('env-url-display');
    if (!btnLocal || !btnCloud) return;
    if (env === 'local') {
        btnLocal.style.background = 'var(--primary)';
        btnLocal.style.color = '#000';
        btnCloud.style.background = 'rgba(255,255,255,0.05)';
        btnCloud.style.color = 'var(--text-muted)';
        if (urlDisplay) urlDisplay.textContent = '127.0.0.1:3333';
    } else {
        btnCloud.style.background = '#f0a500';
        btnCloud.style.color = '#000';
        btnLocal.style.background = 'rgba(255,255,255,0.05)';
        btnLocal.style.color = 'var(--text-muted)';
        if (urlDisplay) urlDisplay.textContent = '138.2.241.76:3333';
    }
}

function showTab(tabId) {
    localStorage.setItem('admin_last_tab', tabId);

    if (telemetryInterval) {
        clearInterval(telemetryInterval);
        telemetryInterval = null;
    }

    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));

    // Limpiar clases active de todos los links del sidebar (principales y sub-links)
    document.querySelectorAll('.nav-link').forEach(b => b.classList.remove('active'));
    // Limpiar clases active de todas las carpetas del menú
    document.querySelectorAll('.nav-folder').forEach(f => f.classList.remove('active'));

    const view = document.getElementById('view-' + tabId);
    if (view) view.classList.add('active');

    // Resaltar el link del sidebar (sea sub-link o principal) que coincida con el tab o sub-tab activo
    let sidebarLink;
    if (tabId === 'ammo') {
        sidebarLink = document.querySelector(`.nav-link[onclick*="setAmmoTab"][onclick*="${currentAmmoTab}"]:not([onclick*="toggleFolder"])`);
        if (!sidebarLink) sidebarLink = document.querySelector(`.nav-link[onclick*="showTab('ammo')"]`);
    } else if (tabId === 'skills') {
        sidebarLink = document.querySelector(`.nav-link[onclick*="setSkillTab"][onclick*="${currentSkillTab}"]`);
        if (!sidebarLink) sidebarLink = document.querySelector(`.nav-link[onclick*="showTab('skills')"]`);
    } else if (tabId === 'mechanics') {
        sidebarLink = document.querySelector(`.nav-link[onclick*="setMechTab"][onclick*="${currentMechTab}"]`);
        if (!sidebarLink) sidebarLink = document.querySelector(`.nav-link[onclick*="showTab('mechanics')"]`);
    } else if (tabId === 'modes') {
        sidebarLink = document.querySelector(`.nav-link[onclick*="setModeTab"][onclick*="${currentModeTab}"]`);
        if (!sidebarLink) sidebarLink = document.querySelector(`.nav-link[onclick*="showTab('modes')"]`);
    } else {
        sidebarLink = document.querySelector(`.nav-link[onclick*="showTab('${tabId}')"]`);
    }
    if (sidebarLink) sidebarLink.classList.add('active');

    // Mapeo inteligente y dinámico de carpetas (nav-folder) activas según el tab actual
    const folderMapping = {
        'maps': 'folder-maps', 'map-detail': 'folder-maps',
        'enemies': 'folder-enemies', 'enemy-detail': 'folder-enemies',
        'mechanics': 'folder-mechanics',
        'ammo': 'folder-market', 'weapons': 'folder-market', 'shields': 'folder-market', 'engines': 'folder-market',
        'skills': 'folder-skills',
        'modes': 'folder-modes',
        'loot': 'folder-loot',
        'enemy-loot': 'folder-loot',
        'crafting-recipes': 'folder-crafting',
        'crafting-materials': 'folder-crafting'
    };
    const parentFolderId = folderMapping[tabId];
    if (parentFolderId) {
        const folderEl = document.getElementById(parentFolderId);
        if (folderEl) {
            if (parentFolderId !== folderToggledThisClick) {
                folderEl.classList.add('show'); // Forzar despliegue visual de la carpeta si no se clickeó para colapsar
            }
            const folderHeader = folderEl.previousElementSibling;
            if (folderHeader && folderHeader.classList.contains('nav-folder')) {
                if (folderEl.classList.contains('show')) {
                    folderHeader.classList.add('active');
                } else {
                    folderHeader.classList.remove('active');
                }
                const chevron = folderHeader.querySelector('.chevron');
                if (chevron) {
                    chevron.innerText = folderEl.classList.contains('show') ? '▼' : '▶';
                }
            }
        }
    }

    // Resetear flag al final del procesamiento de navegación
    folderToggledThisClick = null;

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
        'modes': 'Configuración de Modos de Juego',
        'loot': 'Sistema de Recompensas (Loot)',
        'enemy-loot': 'Configuración de Botín del Enemigo',
        'crafting-recipes': 'Recetas de Crafteo',
        'crafting-materials': 'Materiales de Crafteo',
        'quests': 'Misiones de la Galaxia',
        'battlepass': 'Pase de Batalla',
        'chat-global': 'Transmisión y Chat Global',
        'ranking': 'Sistema de Clasificación'
    };
    document.getElementById('current-view-title').innerText = titles[tabId] || 'Configuración';

    if (tabId === 'json') document.getElementById('json-editor').value = JSON.stringify(config, null, 4);
    if (tabId === 'sessions' || tabId === 'users' || tabId === 'performance') {
        if (currentSessionSubTab === 'online') socket.emit('getOnlinePlayers');
        else if (currentSessionSubTab === 'history') socket.emit('getSessions', { page: currentSessionPage });
        else if (currentSessionSubTab === 'users') socket.emit('getRegisteredUsers');
        else if (currentSessionSubTab === 'performance') {
            triggerPerformanceRequest();
            telemetryInterval = setInterval(() => {
                if (currentSessionSubTab === 'performance') {
                    triggerPerformanceRequest();
                }
            }, 2500);
        }
    }

    // Refrescar tab actual
    refreshCurrentTab();

    // Sincronizar el árbol del sidebar en caliente
    if (typeof updateSidebar === 'function') {
        updateSidebar();
    }
}

window.onload = () => {
    // Inicializar el selector de entorno al cargar
    setEnv(activeEnv);

    const savedUser = localStorage.getItem('admin_user');
    const savedPass = localStorage.getItem('admin_pass');
    if (savedUser && savedPass) {
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
    const btn = document.querySelector('#login-overlay button[onclick="connect()"]');
    const err = document.getElementById('login-error');

    const targetUrl = SERVER_URLS[activeEnv] || SERVER_URLS.local;
    const envLabel = activeEnv === 'cloud' ? '☁️ SERVER' : '💻 LOCAL';

    if (socket) socket.disconnect();
    if (socketLocal) socketLocal.disconnect();
    if (socketCloud) socketCloud.disconnect();

    btn.innerText = `CONECTANDO A ${envLabel.toUpperCase()}...`;

    // Conexiones de telemetría paralela dedicadas
    socketLocal = io(SERVER_URLS.local);
    socketCloud = io(SERVER_URLS.cloud);

    // El socket de operación principal apunta a la selección del Login
    socket = activeEnv === 'cloud' ? socketCloud : socketLocal;

    // Login en socket principal (bloqueante / decisivo para el Login)
    socket.on('connect', () => socket.emit('login', { user, password: pass, isAdmin: true }));

    // Conectar y loguear el secundario de forma asíncrona / silenciosa
    socketLocal.on('connect', () => {
        if (activeEnv !== 'local') {
            socketLocal.emit('login', { user, password: pass, isAdmin: true });
        }
    });
    socketCloud.on('connect', () => {
        if (activeEnv !== 'cloud') {
            socketCloud.emit('login', { user, password: pass, isAdmin: true });
        }
    });

    // Direccionamiento dinámico de telemetrías
    socketLocal.on('serverPerformanceData', (data) => {
        if (activePerformanceEnv === 'local' && currentSessionSubTab === 'performance') {
            if (typeof renderPerformance === 'function') renderPerformance(data);
        }
    });
    socketCloud.on('serverPerformanceData', (data) => {
        if (activePerformanceEnv === 'cloud' && currentSessionSubTab === 'performance') {
            if (typeof renderPerformance === 'function') renderPerformance(data);
        }
    });

    // Operaciones del Dashboard atadas al socket del entorno principal
    socket.on('adminConfigUpdated', (data) => {
        config = data;
        patchMechanicsLib();
        syncChatGlobalToggle();
        renderAll();
    });

    socket.on('sessionsHistory', (data) => {
        lastSessionsTotal = data.total;
        currentSessionPage = data.page;
        renderSessions(data.sessions);
        document.getElementById('page-indicator').innerText = `PÁGINA ${currentSessionPage + 1} de ${Math.ceil(lastSessionsTotal / 50)}`;
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

    socket.on('assetFilesList', (data) => {
        if (data && !data.error) {
            window.allAssetFiles = data;
        } else {
            console.warn("Could not load asset files list:", data ? data.error : "Unknown error");
            window.allAssetFiles = [];
        }
    });

    socket.on('loginSuccess', (data) => {
        socket.emit('getAssetFiles');
        if (remember) {
            localStorage.setItem('admin_user', user);
            localStorage.setItem('admin_pass', pass);
        } else {
            localStorage.removeItem('admin_user');
            localStorage.removeItem('admin_pass');
        }
        document.getElementById('login-overlay').style.display = 'none';
        const envLabelText = activeEnv === 'cloud' ? `☁️ SERVER: ${user.toUpperCase()}` : `💻 LOCAL: ${user.toUpperCase()}`;
        document.getElementById('conn-dot').classList.add('online');
        document.getElementById('conn-text').innerText = envLabelText;
        if (data.adminConfig) {
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

            // Inicializar configuración global de botín
            if (!config.lootConfig) {
                config.lootConfig = {
                    interactRange: 400,
                    expirationMs: 300000,
                    serverAuthoritative: true,
                    pvpDropEnabled: false
                };
            }

            // Inicializar configuración de Chat Global
            if (!config.chatConfig) {
                config.chatConfig = {
                    globalChatEnabled: true
                };
            }

            // Inicializar configuración de Misiones
            if (!config.questsConfig) {
                config.questsConfig = JSON.parse(JSON.stringify(DEFAULT_QUESTS_CONFIG));
            }
            if (!config.questsGlobalConfig) {
                config.questsGlobalConfig = JSON.parse(JSON.stringify(DEFAULT_QUESTS_GLOBAL_CONFIG));
            }

            // Inicializar configuración del Pase de Batalla
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

            if (!config.rankingConfig) {
                config.rankingConfig = JSON.parse(JSON.stringify(DEFAULT_RANKING_CONFIG));
            }

            patchMechanicsLib();
            syncChatGlobalToggle();
            renderAll();
        }

        // Conectar el socket del chat global dedicado de forma automática tras loguearse
        const savedChatServer = localStorage.getItem('admin_chat_server_url') || "http://127.0.0.1:3333";
        const chatSelect = document.getElementById('chat-server-select');
        if (chatSelect) chatSelect.value = savedChatServer;
        changeChatServer(savedChatServer);

        // v267.200: Restaurar última vista tras login
        const lastTab = localStorage.getItem('admin_last_tab') || 'ships';
        const lastMap = localStorage.getItem('admin_last_map');
        const lastEnemy = localStorage.getItem('admin_last_enemy');
        const lastLootEnemy = localStorage.getItem('admin_last_loot_enemy');
        const lastSessionTab = localStorage.getItem('admin_last_session_tab');

        if (lastTab === 'map-detail' && lastMap) selectMap(lastMap);
        else if (lastTab === 'enemy-detail' && lastEnemy) selectEnemy(lastEnemy);
        else if (lastTab === 'enemy-loot' && lastLootEnemy) selectLootEnemy(lastLootEnemy);
        else if (lastTab === 'sessions' || lastTab === 'users') {
            if (lastSessionTab) setSessionSubTab(lastSessionTab);
            else showTab(lastTab);
        }
        else showTab(lastTab);

        // Si la pestaña actual tras el login es performance, expandimos la subcarpeta y activamos el tab visual
        if (lastSessionTab === 'performance' || lastTab === 'performance') {
            setTimeout(() => {
                const subperf = document.getElementById('subfolder-performance');
                if (subperf) subperf.classList.add('show');
                const activeBtn = document.getElementById('nav-performance-' + activePerformanceEnv);
                if (activeBtn) activeBtn.classList.add('active');
            }, 100);
        }
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
    folderToggledThisClick = id; // Registrar que esta carpeta fue alterada en este clic

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
    localStorage.setItem('admin_last_mode_tab', tab);
    if (btn) {
        document.querySelectorAll('.nav-link.sub').forEach(l => l.classList.remove('active'));
        btn.classList.add('active');
    }
    renderModes();
}

function setSkillTab(tab, btn) {
    currentSkillTab = tab;
    localStorage.setItem('admin_last_skill_tab', tab);
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
    else if (tab === 'performance') showTab('performance');
    else showTab('sessions');

    // Actualizar estados visuales en el sidebar
    document.querySelectorAll('#folder-audit .nav-link').forEach(b => b.classList.remove('active'));

    if (tab === 'performance') {
        const subFolder = document.getElementById('subfolder-performance');
        if (subFolder) subFolder.classList.add('show');

        const linkEl = document.getElementById('nav-performance-' + activePerformanceEnv);
        if (linkEl) linkEl.classList.add('active');

        const parentLink = document.getElementById('nav-sessions-performance');
        if (parentLink) parentLink.classList.add('active');
    } else {
        const linkEl = document.getElementById('nav-sessions-' + tab);
        if (linkEl) linkEl.classList.add('active');
    }

    // Limpiar telemetryInterval anterior
    if (telemetryInterval) {
        clearInterval(telemetryInterval);
        telemetryInterval = null;
    }

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
    } else if (tab === 'performance') {
        triggerPerformanceRequest();
        telemetryInterval = setInterval(() => {
            if (currentSessionSubTab === 'performance') {
                triggerPerformanceRequest();
            }
        }, 2500);
    }
}

function triggerPerformanceRequest() {
    if (activePerformanceEnv === 'local') {
        if (socketLocal && socketLocal.connected) socketLocal.emit('getServerPerformance');
    } else {
        if (socketCloud && socketCloud.connected) socketCloud.emit('getServerPerformance');
    }
}

function setPerformanceEnv(env, btn) {
    activePerformanceEnv = env;
    localStorage.setItem('admin_perf_env', env);

    // Limpiar contenedor para evitar ver datos viejos de otra instancia al conmutar
    const container = document.getElementById('perf-aaa-container');
    if (container) {
        container.innerHTML = `<div style="color:#555; font-style:italic; padding:2rem; text-align:center;">Esperando datos de telemetria de ${env.toUpperCase() === 'CLOUD' ? 'SERVER' : 'LOCAL'}...</div>`;
    }

    setSessionSubTab('performance');
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
    localStorage.removeItem('admin_perf_env');
    if (socketLocal) socketLocal.disconnect();
    if (socketCloud) socketCloud.disconnect();
    location.reload();
}

function addAmmoMechanic(type, idx) {
    if (!config.shopItems.ammo[type][idx].mechanics) config.shopItems.ammo[type][idx].mechanics = [];
    config.shopItems.ammo[type][idx].mechanics.push({ type: "bleed", damagePerSecond: 5, duration: 3000 });
    renderAmmo();
}

function addMovementPhase(id) {
    if (!config.enemyModels[id].movementPhases) config.enemyModels[id].movementPhases = [];
    config.enemyModels[id].movementPhases.push({ type: "chase", speed: 3.5, stopDist: 150, startDelay: 2000 });
}

function removeMovementPhase(id, idx) {
    config.enemyModels[id].movementPhases.splice(idx, 1);
}

function updateMovementPhaseType(id, idx, type) {
    config.enemyModels[id].movementPhases[idx].type = type;
    const lib = (config.movementLib && config.movementLib[type]) ? config.movementLib[type] : DEFAULT_MOVEMENT_LIB[type];
    lib.fields.forEach(f => {
        if (config.enemyModels[id].movementPhases[idx][f] === undefined) {
            if (f === 'speed') config.enemyModels[id].movementPhases[idx][f] = 3.5;
            else if (f === 'radius') config.enemyModels[id].movementPhases[idx][f] = 200;
            else if (f === 'speedBonus') config.enemyModels[id].movementPhases[idx][f] = 50;
            else if (f === 'intervalMs') config.enemyModels[id].movementPhases[idx][f] = 500;
            else if (f === 'duration') config.enemyModels[id].movementPhases[idx][f] = 5000;
            else if (f === 'cooldown') config.enemyModels[id].movementPhases[idx][f] = 10000;
            else if (f === 'affectsEnemies') config.enemyModels[id].movementPhases[idx][f] = false;
            else if (f === 'affectsBosses') config.enemyModels[id].movementPhases[idx][f] = false;
            else if (f === 'changeTrigger') config.enemyModels[id].movementPhases[idx][f] = 'time';
            else if (f === 'changeType') config.enemyModels[id].movementPhases[idx][f] = 'random';
            else if (f === 'changeInterval') config.enemyModels[id].movementPhases[idx][f] = 4000;
            else if (f === 'patrolRange') config.enemyModels[id].movementPhases[idx][f] = 300;
            else if (f === 'amplitude') config.enemyModels[id].movementPhases[idx][f] = 100;
            else if (f === 'frequency') config.enemyModels[id].movementPhases[idx][f] = 1.5;
            else config.enemyModels[id].movementPhases[idx][f] = 150;
        }
    });
}

function moveMovementPhase(id, idx, dir) {
    const arr = config.enemyModels[id].movementPhases;
    const newIdx = idx + dir;
    if (newIdx < 0 || newIdx >= arr.length) return;
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
            else if (f === 'invisType') mech[f] = 'invisibility';
            else if (f === 'keepAttacking') mech[f] = true;
            else if (f === 'changeSpeed') mech[f] = false;
            else if (f === 'invisSpeedMultiplier') mech[f] = 1.0;
            else if (f === 'activationMode') mech[f] = 'hp';
            else if (f === 'activationHPs') mech[f] = [50];
            else if (f === 'activationIntervalMs') mech[f] = 30000;
            else if (f === 'cloneCount') mech[f] = 3;
            else if (f === 'cloneHp') mech[f] = 1000;
            else if (f === 'cloneShield') mech[f] = 200;
            else if (f === 'cloneSpeed') mech[f] = 200;
            else if (f === 'cloneDuration') mech[f] = 8000;
            else if (f === 'cloneExplosionDamage') mech[f] = 500;
            else if (f === 'cloneHealAmount') mech[f] = 1000;
            else if (f === 'cloneExplodeOnExpiry') mech[f] = true;
            else if (f === 'spawnRadius') mech[f] = 150;
            else if (f === 'reflect_mult') mech[f] = 0.8;
            else if (f === 'fireRange') mech[f] = 700;
            else if (f === 'bulletSpeed') mech[f] = 700;
            else if (f === 'bulletDamage') mech[f] = 10;
            else if (f === 'stealMode') mech[f] = 'flat';
            else if (f === 'stealAmount') mech[f] = 100;
            else if (f === 'stealIntervalMs') mech[f] = 1000;
            else if (f === 'targetMode') mech[f] = 'proximity';
            else if (f === 'giveToEnemy') mech[f] = true;
            else if (f === 'startDelay') mech[f] = 0;
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
            else if (f === 'damage') mech[f] = newType === 'spin_ring' ? 100 : (newType === 'circle_cast' ? 500 : 15);
            else if (f === 'intervalMs') mech[f] = 1000;
            else if (f === 'duration') mech[f] = 5000;
            else if (f === 'cooldown') mech[f] = newType === 'summoning' ? 30000 : (newType === 'spin_ring' ? 4000 : (newType === 'circle_cast' ? 5000 : 10000));
            else if (f === 'bulletDamage') mech[f] = 10;
            else if (f === 'bulletSpeed') mech[f] = 800;
            else if (f === 'fireRange') mech[f] = newType === 'circle_cast' ? 300 : 600;
            else if (f === 'fireRate') mech[f] = 1000;
            else if (f === 'burstShots') mech[f] = 1;
            else if (f === 'aimDelayMs') mech[f] = 1000;
            else if (f === 'coneFollow') mech[f] = false;
            else if (f === 'lockTimeMs') mech[f] = newType === 'circle_cast' ? 800 : 0;
            else if (f === 'castTimeMs') mech[f] = 2000;
            else if (f === 'bombCount') mech[f] = 3;
            else if (f === 'bombDelayMs') mech[f] = 500;
            else if (f === 'fuseTimeMs') mech[f] = 1000;
            else if (f === 'reflect_mult') mech[f] = 0.8;
            else if (f === 'spinSpeed') mech[f] = 4.0;
            else if (f === 'speedBuffAmount') mech[f] = 150;
            else if (f === 'speedBuffDuration') mech[f] = 3000;
            else if (f === 'applySlow') mech[f] = false;
            else if (f === 'slowPercentage') mech[f] = 40;
            else if (f === 'slowDuration') mech[f] = 2000;
            else if (f === 'activationMode') mech[f] = 'hp';
            else if (f === 'activationHPs') mech[f] = [50];
            else if (f === 'activationIntervalMs') mech[f] = 30000;
            else if (f === 'summonCount') mech[f] = 3;
            else if (f === 'spawnRadius') mech[f] = 150;
            else if (f === 'summonDurationMode') mech[f] = 'until_death';
            else if (f === 'summonDurationMs') mech[f] = 10000;
            else if (f === 'summonsList') mech[f] = ['random_base', 'random_base', 'random_base'];
            else if (f === 'safeRadius') mech[f] = 150;
            else if (f === 'maxOffset') mech[f] = 300;
            else if (f === 'postCastWaitMs') mech[f] = 1000;
            else if (f === 'debuffsList') mech[f] = [];
            else if (f === 'projectileCount') mech[f] = 3;
            else if (f === 'spreadAngle') mech[f] = 60;
            else if (f === 'parkTimeMs') mech[f] = 1000;
            else if (f === 'returnDamage') mech[f] = 10;
            else if (f === 'wallWidth') mech[f] = 140;
            else if (f === 'wallStartOffset') mech[f] = 50;
            else if (f === 'pushForce') mech[f] = 250;
            else if (f === 'burrowSpeed') mech[f] = 550;
            else if (f === 'burstMode') mech[f] = 'burst';
            else if (f === 'zoneDuration') mech[f] = 4000;
            else if (f === 'zoneTickMs') mech[f] = 500;
            else if (f === 'zoneDamage') mech[f] = 25;
            else if (f === 'warnTimeMs') mech[f] = 1200;
            else if (f === 'undergroundMs') mech[f] = 2500;
            else if (f === 'targetMode') mech[f] = newType === 'burrow' ? 'proximity' : 'proximity';
            else if (f === 'bulletCount') mech[f] = newType === 'polymorph' ? 5 : 1;
            else if (f === 'polyDuration') mech[f] = 8000;
            else if (f === 'isPointAndClick') mech[f] = newType === 'polymorph' ? false : false;
            else if (f === 'canMove') mech[f] = newType === 'polymorph' ? false : true;
            else if (f === 'canUseSkills') mech[f] = newType === 'polymorph' ? false : true;
            else if (f === 'meteorCount') mech[f] = 3;
            else if (f === 'fallHeight') mech[f] = 800;
            else if (f === 'fallSpeed') mech[f] = 600;
            else if (f === 'meteorSize') mech[f] = 60;
            else if (f === 'explosionRadius') mech[f] = 150;
            else if (f === 'warnTimeMs') mech[f] = 1200;
            else if (f === 'persistentZone') mech[f] = false;
            else if (f === 'zoneDamage') mech[f] = 25;
            else if (f === 'zoneTickMs') mech[f] = 1000;
            else if (f === 'zoneDuration') mech[f] = 4000;
            else mech[f] = 0;
        }
    });
    renderEnemyDetail();
}

function moveMechanic(enemyId, idx, dir) {
    const list = config.enemyModels[enemyId].mechanics;
    if (dir === -1 && idx > 0) {
        [list[idx - 1], list[idx]] = [list[idx], list[idx - 1]];
    } else if (dir === 1 && idx < list.length - 1) {
        [list[idx + 1], list[idx]] = [list[idx], list[idx + 1]];
    }
    renderEnemies();
}

function addAmbience(id) {
    if (!config.mapsConfig[id].ambience) config.mapsConfig[id].ambience = [];
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
        else if (f === 'multiplier') newHazard[f] = 2;
        else if (f === 'penaltyPercentage') newHazard[f] = 50;
        else if (f === 'penaltyFixed') newHazard[f] = 0;
        else newHazard[f] = 0;
    });

    config.mapsConfig[mapId].ambience[idx] = newHazard;
    renderMapDetail();
}

function addMapSpawn(id) {
    if (!config.mapsConfig[id].spawns) config.mapsConfig[id].spawns = [];
    const uniqueId = 'spawn_' + Date.now() + Math.floor(Math.random() * 1000);
    config.mapsConfig[id].spawns.push({
        id: uniqueId,
        type: "",
        count: 5,
        intervalMs: 5000,
        spawnMode: "random",
        x: 1000,
        y: 1000,
        radius: 300
    });
}

function patchMechanicsLib() {
    if (!config) return;

    if (!config.housingConfig) {
        config.housingConfig = JSON.parse(JSON.stringify(DEFAULT_HOUSING_CONFIG));
    }

    if (!config.talentsConfig) {
        config.talentsConfig = {
            talents: [],
            nodes: {},
            connections: []
        };
    }

    if (!config.talentsConfig.talents || config.talentsConfig.talents.length === 0) {
        const DEFAULT_TALENTS = [
            { id: "eng_1", name: "REFUERZO DE CASCO", desc: "+2% HP por nivel", category: "engineering", maxLevel: 5, effects: { hp_pct: 0.02 }, icon: "🛡️" },
            { id: "eng_2", name: "ESCUDO DINÁMICO", desc: "+2% Escudo por nivel", category: "engineering", maxLevel: 5, effects: { sh_pct: 0.02 }, icon: "🔵" },
            { id: "eng_3", name: "REGEN EMERGENGIA", desc: "+5% HP Reparación", category: "engineering", maxLevel: 5, effects: { hp_regen: 0.05 }, icon: "🔧" },
            { id: "eng_4", name: "CAPACITOR OHCU", desc: "+5% Shield Regen", category: "engineering", maxLevel: 5, effects: { shield_regen: 0.05 }, icon: "🔋" },
            { id: "eng_5", name: "PLACAS NANOBOTS", desc: "+1% Armadura total", category: "engineering", maxLevel: 5, effects: { armor_pct: 0.01 }, icon: "⚙️" },
            { id: "eng_6", name: "REACTOR FUSIÓN", desc: "+3% Eficiencia Energía", category: "engineering", maxLevel: 5, effects: { energy_efficiency: 0.03 }, icon: "⚛️" },
            { id: "eng_7", name: "MANTE GALÁCTICO", desc: "-5% Costo Reparación", category: "engineering", maxLevel: 5, effects: { repair_cost_reduction: 0.05 }, icon: "💸" },
            { id: "eng_8", name: "ESTABL FLOTANTE", desc: "+1% Estabilidad (Vel)", category: "engineering", maxLevel: 5, effects: { stability: 0.01 }, icon: "🛸" },

            { id: "com_1", name: "LÁSER SOBRECARGA", desc: "+3% Daño Láser", category: "combat", maxLevel: 5, effects: { laser_dmg_pct: 0.03 }, icon: "🔫" },
            { id: "com_2", name: "MIRILLA TÁCTICA", desc: "+2% Prob. Crítico", category: "combat", maxLevel: 5, effects: { crit_chance: 0.02 }, icon: "🎯" },
            { id: "com_3", name: "FURIA DEL PILOTO", desc: "+5% Daño Crítico", category: "combat", maxLevel: 5, effects: { crit_dmg: 0.05 }, icon: "🔥" },
            { id: "com_4", name: "CARGA PROYECTIL", desc: "+5% Bonus Munición", category: "combat", maxLevel: 5, effects: { ammo_bonus_pct: 0.05 }, icon: "💣" },
            { id: "com_5", name: "DISPARO PRECISIÓN", desc: "+2% Puntería", category: "combat", maxLevel: 5, effects: { accuracy_pct: 0.02 }, icon: "👁️" },
            { id: "com_6", name: "PERFORACIÓN TÉRM", desc: "+3% Ignorar Escudo", category: "combat", maxLevel: 5, effects: { ignore_shield_pct: 0.03 }, icon: "⚡" },
            { id: "com_7", name: "CADENCIA MILITAR", desc: "-2% CD de Disparo", category: "combat", maxLevel: 5, effects: { fire_rate_pct: 0.02 }, icon: "⚔️" },
            { id: "com_8", name: "BLINDAJE ATAQUE", desc: "+1% Evasión en Combate", category: "combat", maxLevel: 5, effects: { evasion_pct: 0.01 }, icon: "🛡️" },

            { id: "sci_1", name: "MOTORES FUSIÓN", desc: "+1.5% Velocidad Base", category: "science", maxLevel: 5, effects: { speed_pct: 0.015 }, icon: "🚀" },
            { id: "sci_2", name: "ESCÁNER TÁCTICO", desc: "+10% Rango Minimapa", category: "science", maxLevel: 5, effects: { minimap_range: 0.10 }, icon: "📡" },
            { id: "sci_3", name: "MINERÍA OHCU", desc: "+5% OHCU de Kills", category: "science", maxLevel: 5, effects: { ohcu_kill_bonus: 0.05 }, icon: "💎" },
            { id: "sci_4", name: "MERCADO GALÁXIA", desc: "-2% Descuento Tienda", category: "science", maxLevel: 5, effects: { shop_discount: 0.02 }, icon: "🏪" },
            { id: "sci_5", name: "ENFRIAMIENTO RÁP", desc: "-3% CD Habilidades", category: "science", maxLevel: 5, effects: { cooldown_reduction: 0.03 }, icon: "❄️" },
            { id: "sci_6", name: "SINCRONÍA TACT", desc: "+1% Bonus en Grupo", category: "science", maxLevel: 5, effects: { group_bonus: 0.01 }, icon: "👥" },
            { id: "sci_7", name: "SENSORES PRECI", desc: "+5% Loot de Bosses", category: "science", maxLevel: 5, effects: { boss_loot_bonus: 0.05 }, icon: "🔬" },
            { id: "sci_8", name: "SALTO HIPERESP", desc: "+10% Distancia Dash", category: "science", maxLevel: 5, effects: { dash_distance: 0.10 }, icon: "🌀" }
        ];
        config.talentsConfig.talents = DEFAULT_TALENTS;
    }

    // Normalizar spawners de mapas para asegurar IDs y modos de respawn por unidad
    if (config.mapsConfig) {
        Object.keys(config.mapsConfig).forEach(mapId => {
            const m = config.mapsConfig[mapId];
            if (m) {
                if (m.width === undefined) m.width = 10000;
                if (m.height === undefined) m.height = 10000;
                if (m.spawns) {
                    m.spawns.forEach((s, idx) => {
                        if (!s.id) {
                            s.id = `spawn_${mapId}_idx_${idx}_type_${s.type}`;
                        }
                        if (!s.spawnMode) {
                            s.spawnMode = "random";
                        }
                        if (s.x === undefined) s.x = 1000;
                        if (s.y === undefined) s.y = 1000;
                        if (s.radius === undefined) s.radius = 300;
                    });
                }
            }
        });
    }

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
                    if (config[item.configKey][type].label === undefined) {
                        config[item.configKey][type].label = item.base[type].label;
                    }
                    if (config[item.configKey][type].icon === undefined) {
                        config[item.configKey][type].icon = item.base[type].icon;
                    }
                }
            }
        }
    });

    // Sincronizar y persistir AMMO_MECH_LIB
    if (!config.ammoMechLib) {
        config.ammoMechLib = JSON.parse(JSON.stringify(AMMO_MECH_LIB));
    } else {
        for (let type in AMMO_MECH_LIB) {
            if (!config.ammoMechLib[type]) {
                config.ammoMechLib[type] = JSON.parse(JSON.stringify(AMMO_MECH_LIB[type]));
            } else {
                config.ammoMechLib[type].fields = [...AMMO_MECH_LIB[type].fields];
                if (config.ammoMechLib[type].label === undefined) {
                    config.ammoMechLib[type].label = AMMO_MECH_LIB[type].label;
                }
                if (config.ammoMechLib[type].icon === undefined) {
                    config.ammoMechLib[type].icon = AMMO_MECH_LIB[type].icon;
                }
            }
        }
    }
    AMMO_MECH_LIB = config.ammoMechLib;

    // Sincronizar y persistir AMBIENCE_LIB
    if (!config.ambienceLib) {
        config.ambienceLib = JSON.parse(JSON.stringify(AMBIENCE_LIB));
    } else {
        for (let type in AMBIENCE_LIB) {
            if (!config.ambienceLib[type]) {
                config.ambienceLib[type] = JSON.parse(JSON.stringify(AMBIENCE_LIB[type]));
            } else {
                config.ambienceLib[type].fields = [...AMBIENCE_LIB[type].fields];
                if (config.ambienceLib[type].label === undefined) {
                    config.ambienceLib[type].label = AMBIENCE_LIB[type].label;
                }
                if (config.ambienceLib[type].icon === undefined) {
                    config.ambienceLib[type].icon = AMBIENCE_LIB[type].icon;
                }
            }
        }
    }
    AMBIENCE_LIB = config.ambienceLib;

    // Parches específicos de campos (retrocompatibilidad)
    if (config.mechanicsLib && config.mechanicsLib.laser) {
        if (!config.mechanicsLib.laser.fields.includes("isHoming")) config.mechanicsLib.laser.fields.push("isHoming");
        if (!config.mechanicsLib.laser.fields.includes("turnSpeed")) config.mechanicsLib.laser.fields.push("turnSpeed");
        if (!config.mechanicsLib.laser.fields.includes("burstShots")) config.mechanicsLib.laser.fields.push("burstShots");
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
    if (config.skillsData && config.skillsData["VÍNCULO VITAL"]) {
        const s = config.skillsData["VÍNCULO VITAL"];
        if (s.breakRange === undefined) s.breakRange = 500;
        if (s.tickInterval === undefined) s.tickInterval = 1000;
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

function syncChatGlobalToggle() {
    const cb = document.getElementById('chat-global-enabled-toggle');
    if (cb) {
        cb.checked = !!(config.chatConfig && config.chatConfig.globalChatEnabled);
    }
}

function toggleChatGlobalStatus(checked) {
    if (!config.chatConfig) {
        config.chatConfig = {};
    }
    config.chatConfig.globalChatEnabled = checked;
    saveConfig();
}

function connectChatSocket(targetUrl) {
    if (chatSocket) {
        chatSocket.disconnect();
    }

    console.log("[CHAT-CONNECT] Conectando socket de chat a:", targetUrl);
    chatSocket = io(targetUrl);

    chatSocket.on('connect', () => {
        const user = document.getElementById('admin-user').value || localStorage.getItem('admin_user');
        const pass = document.getElementById('admin-pass').value || localStorage.getItem('admin_pass');
        chatSocket.emit('login', { user: user, password: pass, isAdmin: true });
        console.log("[CHAT-SOCKET] Conectado exitosamente y autenticado en:", targetUrl);
    });

    chatSocket.on('chatMessage', (data) => {
        if (data.channel === 'global') {
            appendGlobalChatMessage(data);
        }
    });

    chatSocket.on('disconnect', () => {
        console.log("[CHAT-SOCKET] Desconectado de:", targetUrl);
    });

    chatSocket.on('connect_error', () => {
        console.error("[CHAT-SOCKET] Error de conexión con:", targetUrl);
    });
}

function changeChatServer(url) {
    localStorage.setItem('admin_chat_server_url', url);
    const log = document.getElementById('chat-global-log');
    if (log) {
        log.innerHTML = `<div style="color: #888; font-style: italic;">Conectando a servidor de chat (${url.includes("138.2.241.76") ? "Oracle Cloud" : "Local"})...</div>`;
    }
    connectChatSocket(url);
}

function sendAdminGlobalMessage() {
    const input = document.getElementById('chat-global-admin-input');
    if (!input) return;
    const msg = input.value.trim();
    if (!msg) return;

    if (chatSocket && chatSocket.connected) {
        chatSocket.emit('adminGlobalMessage', { msg: msg });
    } else {
        showToast("ERROR: El socket del chat no está conectado a este servidor.");
    }
    input.value = '';
}

function appendGlobalChatMessage(data) {
    const log = document.getElementById('chat-global-log');
    if (!log) return;

    if (log.innerHTML.includes('Conectando al canal de comunicación...')) {
        log.innerHTML = '';
    }

    const msgDiv = document.createElement('div');
    msgDiv.style.padding = '6px 10px';
    msgDiv.style.borderBottom = '1px solid rgba(255,255,255,0.02)';
    msgDiv.style.borderRadius = '4px';
    msgDiv.style.background = 'rgba(255,255,255,0.01)';

    const time = new Date().toLocaleTimeString();

    let senderColor = 'var(--primary)';
    if (data.sender === 'Caelli94' || data.sender === 'SYSTEM') {
        senderColor = 'var(--accent)';
    }

    msgDiv.innerHTML = `
        <span style="color: #555; margin-right: 8px; font-size: 0.8rem;">[${time}]</span>
        <strong style="color: ${senderColor}; margin-right: 5px;">${data.sender}:</strong>
        <span style="color: #ccc;">${data.msg}</span>
    `;

    log.appendChild(msgDiv);
    log.scrollTop = log.scrollHeight;
}

function saveConfig() {
    if (!socket || !socket.connected) {
        showToast("ERROR: No hay conexión con el servidor cósmico.");
        return;
    }

    if (document.getElementById('view-json').classList.contains('active')) {
        try { config = JSON.parse(document.getElementById('json-editor').value); }
        catch (e) { showToast("ERROR JSON: " + e.message); return; }
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

    // Actualizar visual de botones (Extracción)
    const btnSpawn = document.getElementById('btn-radar-spawn');
    const btnSpawner = document.getElementById('btn-radar-spawner');
    const btnExtract = document.getElementById('btn-radar-extract');

    if (btnSpawn) {
        if (mode === 'spawn') {
            btnSpawn.classList.remove('btn-secondary');
            btnSpawn.classList.add('btn-primary');
        } else {
            btnSpawn.classList.remove('btn-primary');
            btnSpawn.classList.add('btn-secondary');
        }
    }
    if (btnSpawner) {
        if (mode === 'spawner') {
            btnSpawner.classList.remove('btn-secondary');
            btnSpawner.classList.add('btn-primary');
        } else {
            btnSpawner.classList.remove('btn-primary');
            btnSpawner.classList.add('btn-secondary');
        }
    }
    if (btnExtract) {
        if (mode === 'extract') {
            btnExtract.classList.remove('btn-secondary');
            btnExtract.classList.add('btn-primary');
        } else {
            btnExtract.classList.remove('btn-primary');
            btnExtract.classList.add('btn-secondary');
        }
    }

    // Actualizar visual de botones (Defensa del Altar)
    const btnAdAltar = document.getElementById('btn-radar-ad-altar');
    const btnAdSpawn = document.getElementById('btn-radar-ad-spawn');
    const btnAdSpawner = document.getElementById('btn-radar-ad-spawner');
    const btnAdPortal = document.getElementById('btn-radar-ad-portal');

    if (btnAdAltar) {
        if (mode === 'ad-altar') {
            btnAdAltar.classList.remove('btn-secondary');
            btnAdAltar.classList.add('btn-primary');
        } else {
            btnAdAltar.classList.remove('btn-primary');
            btnAdAltar.classList.add('btn-secondary');
        }
    }
    if (btnAdSpawn) {
        if (mode === 'ad-spawn') {
            btnAdSpawn.classList.remove('btn-secondary');
            btnAdSpawn.classList.add('btn-primary');
        } else {
            btnAdSpawn.classList.remove('btn-primary');
            btnAdSpawn.classList.add('btn-secondary');
        }
    }
    if (btnAdSpawner) {
        if (mode === 'ad-spawner') {
            btnAdSpawner.classList.remove('btn-secondary');
            btnAdSpawner.classList.add('btn-primary');
        } else {
            btnAdSpawner.classList.remove('btn-primary');
            btnAdSpawner.classList.add('btn-secondary');
        }
    }
    if (btnAdPortal) {
        if (mode === 'ad-portal') {
            btnAdPortal.classList.remove('btn-secondary');
            btnAdPortal.classList.add('btn-primary');
        } else {
            btnAdPortal.classList.remove('btn-primary');
            btnAdPortal.classList.add('btn-secondary');
        }
    }

    const modeText = document.getElementById('radar-mode-text');
    if (modeText) modeText.innerText = mode === 'spawner' ? 'SPAWNER' : (mode === 'spawn' ? 'SPAWN' : 'ESCAPE');

    // Toggle options display
    if (document.getElementById('radar-spawner-opts')) document.getElementById('radar-spawner-opts').style.display = mode === 'spawner' ? 'block' : 'none';
    if (document.getElementById('radar-extract-opts')) document.getElementById('radar-extract-opts').style.display = mode === 'extract' ? 'block' : 'none';
    if (document.getElementById('radar-spawn-opts')) document.getElementById('radar-spawn-opts').style.display = mode === 'spawn' ? 'block' : 'none';

    if (document.getElementById('radar-ad-altar-opts')) document.getElementById('radar-ad-altar-opts').style.display = mode === 'ad-altar' ? 'block' : 'none';
    if (document.getElementById('radar-ad-spawn-opts')) document.getElementById('radar-ad-spawn-opts').style.display = mode === 'ad-spawn' ? 'block' : 'none';
    if (document.getElementById('radar-ad-spawner-opts')) document.getElementById('radar-ad-spawner-opts').style.display = mode === 'ad-spawner' ? 'block' : 'none';
    if (document.getElementById('radar-ad-portal-opts')) document.getElementById('radar-ad-portal-opts').style.display = mode === 'ad-portal' ? 'block' : 'none';
}

function highlightCard(type, index) {
    focusedRadarItem = { type, index };
    // Limpiar resaltados anteriores de cualquier tipo
    document.querySelectorAll('[id^="card-spawn-"], [id^="card-extract-"], [id^="card-spawner-"], [id^="card-ad-spawn-"], [id^="card-ad-spawner-"], [id^="card-ad-portal-"], [id^="card-map-spawn-"]').forEach(el => {
        el.style.boxShadow = 'none';
        el.style.borderColor = 'rgba(255,255,255,0.1)';
        if (el.id.includes('spawn') && !el.id.includes('ad-') && !el.id.includes('map-')) {
            el.style.background = 'rgba(6,182,212,0.05)';
            el.style.borderColor = 'rgba(6,182,212,0.2)';
        } else if (el.id.includes('map-spawn')) {
            el.style.background = 'rgba(16,185,129,0.05)';
            el.style.borderColor = 'rgba(16,185,129,0.2)';
        } else if (el.id.includes('extract')) {
            el.style.background = 'rgba(0,210,255,0.05)';
            el.style.borderColor = 'rgba(0,210,255,0.2)';
        } else if (el.id.includes('ad-spawn')) {
            el.style.background = 'rgba(6,182,212,0.05)';
            el.style.borderColor = 'rgba(6,182,212,0.2)';
        } else if (el.id.includes('ad-spawner')) {
            el.style.background = 'rgba(255,49,49,0.05)';
            el.style.borderColor = 'rgba(255,49,49,0.2)';
        } else if (el.id.includes('ad-portal')) {
            el.style.background = 'rgba(0,210,255,0.05)';
            el.style.borderColor = 'rgba(0,210,255,0.2)';
        } else {
            el.style.background = 'rgba(255,49,49,0.05)';
            el.style.borderColor = 'rgba(255,49,49,0.2)';
        }
    });

    const cardId = `card-${type}-${index}`;
    const card = document.getElementById(cardId);
    if (card) {
        // Darle un resplandor glow cian de alta gama y borde cian activo
        card.style.borderColor = 'var(--accent)';
        card.style.boxShadow = '0 0 25px rgba(6, 182, 212, 0.45)';
        card.style.background = 'rgba(6, 182, 212, 0.08)';

        // Auto-scroll suave hasta que la tarjeta sea 100% visible en el listado colapsable
        card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
}

function initRadar() {
    const canvas = document.getElementById('radar-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const container = document.getElementById('radar-container');

    const isAltarDefense = (currentModeTab === 'altar_defense');
    const modeData = isAltarDefense ? config.gameModes.altar_defense : config.gameModes.extraction;

    // Cargar imagen de fondo del mapa coordinada con la escena de Godot (sólo para extracción)
    const bgImage = new Image();
    if (!isAltarDefense) {
        bgImage.src = 'assets/mixboard-image.png';
    }

    // Dimensiones dinámicas del mapa en píxeles (por defecto 10000)
    const worldW = (modeData && modeData.width) ? modeData.width : 10000;
    const worldH = (modeData && modeData.height) ? modeData.height : 10000;

    // Estado de arrastre
    let isDragging = false;
    let dragItem = null;

    const updateCanvasSize = () => {
        const w = container.clientWidth;
        const h = container.clientHeight;
        if (w > 0 && h > 0) {
            canvas.width = w;
            canvas.height = h;
        } else {
            canvas.width = 600;
            canvas.height = 600;
        }
    };
    window.addEventListener('resize', updateCanvasSize);
    updateCanvasSize();

    // Convertir de coordenadas de mundo a coordenadas de canvas
    const worldToCanvas = (wx, wy) => ({
        x: (wx / worldW) * canvas.width,
        y: (wy / worldH) * canvas.height
    });

    // Convertir de canvas a mundo
    const canvasToWorld = (cx, cy) => ({
        wx: (cx / canvas.width) * worldW,
        wy: (cy / canvas.height) * worldH
    });

    canvas.onmousedown = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        if (isAltarDefense) {
            const ad = config.gameModes.altar_defense;

            // 1. Altar
            if (ad.altarPos) {
                const pos = worldToCanvas(ad.altarPos.x, ad.altarPos.y);
                const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
                if (dist < 15) {
                    isDragging = true;
                    dragItem = { type: 'ad-altar' };
                    canvas.style.cursor = 'grabbing';
                    return;
                }
            }

            // 2. Spawn Points
            const spawnPoints = ad.spawnPoints || [];
            for (let i = 0; i < spawnPoints.length; i++) {
                const pos = worldToCanvas(spawnPoints[i].x, spawnPoints[i].y);
                const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
                if (dist < 15) {
                    isDragging = true;
                    dragItem = { type: 'ad-spawn', index: i };
                    canvas.style.cursor = 'grabbing';
                    highlightCard('ad-spawn', i);
                    return;
                }
            }

            // 3. Spawners
            const spawners = ad.spawners || [];
            for (let i = 0; i < spawners.length; i++) {
                const pos = worldToCanvas(spawners[i].x, spawners[i].y);
                const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
                if (dist < 15) {
                    isDragging = true;
                    dragItem = { type: 'ad-spawner', index: i };
                    canvas.style.cursor = 'grabbing';
                    highlightCard('ad-spawner', i);
                    return;
                }
            }

            // 4. Puertas de Escape (Exit Portals)
            const exitPortals = ad.exitPortals || [];
            for (let i = 0; i < exitPortals.length; i++) {
                const pos = worldToCanvas(exitPortals[i].x, exitPortals[i].y);
                const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
                if (dist < 15) {
                    isDragging = true;
                    dragItem = { type: 'ad-portal', index: i };
                    canvas.style.cursor = 'grabbing';
                    highlightCard('ad-portal', i);
                    return;
                }
            }
        } else {
            // 1. Buscar en Puntos de Extracción
            const points = config.gameModes.extraction.extractPoints || [];
            for (let i = 0; i < points.length; i++) {
                const pos = worldToCanvas(points[i].x, points[i].y);
                const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
                if (dist < 15) {
                    isDragging = true;
                    dragItem = { type: 'extract', index: i };
                    canvas.style.cursor = 'grabbing';
                    highlightCard('extract', i);
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
                    highlightCard('spawner', i);
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
                    highlightCard('spawn', i);
                    return;
                }
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

        if (isAltarDefense) {
            const ad = config.gameModes.altar_defense;
            if (dragItem.type === 'ad-altar') {
                ad.altarPos.x = Math.round(world.wx);
                ad.altarPos.y = Math.round(world.wy);
                const ix = document.getElementById('ad-altar-x');
                const iy = document.getElementById('ad-altar-y');
                if (ix) ix.value = ad.altarPos.x;
                if (iy) iy.value = ad.altarPos.y;
            } else if (dragItem.type === 'ad-spawn') {
                const sw = ad.spawnPoints[dragItem.index];
                sw.x = Math.round(world.wx);
                sw.y = Math.round(world.wy);
                const ix = document.getElementById(`ad-spw-x-${dragItem.index}`);
                const iy = document.getElementById(`ad-spw-y-${dragItem.index}`);
                if (ix) ix.value = sw.x;
                if (iy) iy.value = sw.y;
            } else if (dragItem.type === 'ad-spawner') {
                const s = ad.spawners[dragItem.index];
                s.x = Math.round(world.wx);
                s.y = Math.round(world.wy);
                const ix = document.getElementById(`ad-sp-x-${dragItem.index}`);
                const iy = document.getElementById(`ad-sp-y-${dragItem.index}`);
                if (ix) ix.value = s.x;
                if (iy) iy.value = s.y;
            } else if (dragItem.type === 'ad-portal') {
                const ep = ad.exitPortals[dragItem.index];
                ep.x = Math.round(world.wx);
                ep.y = Math.round(world.wy);
                const ix = document.getElementById(`ad-pt-x-${dragItem.index}`);
                const iy = document.getElementById(`ad-pt-y-${dragItem.index}`);
                if (ix) ix.value = ep.x;
                if (iy) iy.value = ep.y;
            }
        } else {
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

        // Dibujar imagen de fondo del mapa o fondo negro
        if (bgImage.complete && bgImage.naturalWidth !== 0) {
            ctx.drawImage(bgImage, 0, 0, canvas.width, canvas.height);
        } else {
            ctx.fillStyle = '#000';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
        }

        // Dibujar Grid fino
        ctx.strokeStyle = 'rgba(0, 210, 255, 0.08)';
        ctx.lineWidth = 1;
        const gridDivisions = 10;
        for (let i = 1; i < gridDivisions; i++) {
            if (i === gridDivisions / 2) continue;
            ctx.beginPath();
            ctx.moveTo((canvas.width / gridDivisions) * i, 0);
            ctx.lineTo((canvas.width / gridDivisions) * i, canvas.height);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(0, (canvas.height / gridDivisions) * i);
            ctx.lineTo(canvas.width, (canvas.height / gridDivisions) * i);
            ctx.stroke();
        }

        // Dibujar líneas divisoria centrales
        ctx.strokeStyle = 'rgba(0, 140, 170, 0.35)';
        ctx.lineWidth = 3;

        ctx.beginPath();
        ctx.moveTo(canvas.width / 2, 0);
        ctx.lineTo(canvas.width / 2, canvas.height);
        ctx.stroke();

        ctx.beginPath();
        ctx.moveTo(0, canvas.height / 2);
        ctx.lineTo(canvas.width, canvas.height / 2);
        ctx.stroke();

        ctx.fillStyle = 'rgba(0, 210, 255, 0.3)';
        for (let i = 1; i < gridDivisions; i++) {
            for (let j = 1; j < gridDivisions; j++) {
                const px = (canvas.width / gridDivisions) * i;
                const py = (canvas.height / gridDivisions) * j;

                ctx.beginPath();
                ctx.arc(px, py, 2.5, 0, Math.PI * 2);
                ctx.fill();
            }
        }

        if (isAltarDefense) {
            const ad = config.gameModes.altar_defense;

            // Dibujar Altar - Verde
            if (ad.altarPos) {
                const pos = worldToCanvas(ad.altarPos.x, ad.altarPos.y);
                const isSelected = isDragging && dragItem && dragItem.type === 'ad-altar';
                ctx.fillStyle = isSelected ? '#fff' : 'rgba(74, 222, 128, 0.3)';
                ctx.strokeStyle = '#4ade80';
                ctx.lineWidth = 3;
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, 14, 0, Math.PI * 2);
                ctx.fill();
                ctx.stroke();

                ctx.fillStyle = '#4ade80';
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, 5, 0, Math.PI * 2);
                ctx.fill();

                ctx.fillStyle = '#4ade80';
                ctx.font = 'bold 11px Outfit';
                ctx.textAlign = 'center';
                ctx.fillText("ALTAR", pos.x, pos.y - 20);
            }

            // Dibujar Spawn de Jugadores - Amarillo
            if (ad.spawnPoints) {
                ad.spawnPoints.forEach((p, idx) => {
                    const pos = worldToCanvas(p.x, p.y);
                    const radiusCanvas = ((p.radius || 200) / worldW) * canvas.width;
                    const isSelected = isDragging && dragItem && dragItem.type === 'ad-spawn' && dragItem.index === idx;

                    ctx.beginPath();
                    ctx.setLineDash([5, 5]);
                    ctx.arc(pos.x, pos.y, radiusCanvas, 0, Math.PI * 2);
                    ctx.strokeStyle = 'rgba(255, 204, 0, 0.4)';
                    ctx.stroke();
                    ctx.setLineDash([]);

                    const isFocused = focusedRadarItem && focusedRadarItem.type === 'ad-spawn' && focusedRadarItem.index === idx;
                    if (isFocused) {
                        const pulse = 4 + Math.sin(Date.now() / 150) * 3;
                        ctx.beginPath();
                        ctx.arc(pos.x, pos.y, radiusCanvas + pulse, 0, Math.PI * 2);
                        ctx.strokeStyle = 'rgba(6, 182, 212, 0.85)';
                        ctx.lineWidth = 2.5;
                        ctx.stroke();
                    }

                    ctx.beginPath();
                    ctx.arc(pos.x, pos.y, 6, 0, Math.PI * 2);
                    ctx.fillStyle = isSelected ? '#fff' : '#ffcc00';
                    ctx.fill();
                    ctx.strokeStyle = '#ffcc00';
                    ctx.stroke();

                    ctx.fillStyle = '#ffcc00';
                    ctx.font = '10px Outfit';
                    ctx.textAlign = 'center';
                    ctx.fillText(p.label || 'Spawn', pos.x, pos.y - 12);
                });
            }

            // Dibujar Spawners - Rojo
            if (ad.spawners) {
                ad.spawners.forEach((s, idx) => {
                    const pos = worldToCanvas(s.x, s.y);
                    const radiusCanvas = (s.radius / worldW) * canvas.width;
                    const isSelected = isDragging && dragItem && dragItem.type === 'ad-spawner' && dragItem.index === idx;

                    const isFocused = focusedRadarItem && focusedRadarItem.type === 'ad-spawner' && focusedRadarItem.index === idx;
                    if (isFocused) {
                        const pulse = 4 + Math.sin(Date.now() / 150) * 3;
                        ctx.beginPath();
                        ctx.arc(pos.x, pos.y, radiusCanvas + pulse, 0, Math.PI * 2);
                        ctx.strokeStyle = 'rgba(6, 182, 212, 0.85)';
                        ctx.lineWidth = 2.5;
                        ctx.stroke();
                    }

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

                    ctx.fillStyle = '#ff3131';
                    ctx.font = 'bold 11px Outfit';
                    ctx.textAlign = 'center';
                    ctx.fillText(s.label || ('Zona ' + (idx + 1)), pos.x, pos.y - radiusCanvas - 6);
                });
            }

            // Dibujar exitPortals (Puertas de escape) - Celeste/Azul
            if (ad.exitPortals) {
                ad.exitPortals.forEach((ep, idx) => {
                    const pos = worldToCanvas(ep.x, ep.y);
                    const radiusCanvas = ((ep.radius || 150) / worldW) * canvas.width;
                    const isSelected = isDragging && dragItem && dragItem.type === 'ad-portal' && dragItem.index === idx;

                    const isFocused = focusedRadarItem && focusedRadarItem.type === 'ad-portal' && focusedRadarItem.index === idx;
                    if (isFocused) {
                        const pulse = 4 + Math.sin(Date.now() / 150) * 3;
                        ctx.beginPath();
                        ctx.arc(pos.x, pos.y, radiusCanvas + pulse, 0, Math.PI * 2);
                        ctx.strokeStyle = 'rgba(6, 182, 212, 0.85)';
                        ctx.lineWidth = 2.5;
                        ctx.stroke();
                    }

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
                    ctx.fillText(ep.label || 'Puerta', pos.x, pos.y - 15);
                });
            }
        } else {
            // Dibujar Spawn Points (Players) - AMARILLO
            if (config.gameModes.extraction.spawnPoints) {
                config.gameModes.extraction.spawnPoints.forEach((p, idx) => {
                    const pos = worldToCanvas(p.x, p.y);
                    const radiusCanvas = (p.radius / worldW) * canvas.width;
                    const isSelected = isDragging && dragItem && dragItem.type === 'spawn' && dragItem.index === idx;

                    ctx.beginPath();
                    ctx.setLineDash([5, 5]);
                    ctx.arc(pos.x, pos.y, radiusCanvas, 0, Math.PI * 2);
                    ctx.strokeStyle = 'rgba(255, 204, 0, 0.4)';
                    ctx.stroke();
                    ctx.setLineDash([]);

                    const isFocused = focusedRadarItem && focusedRadarItem.type === 'spawn' && focusedRadarItem.index === idx;
                    if (isFocused) {
                        const pulse = 4 + Math.sin(Date.now() / 150) * 3;
                        ctx.beginPath();
                        ctx.arc(pos.x, pos.y, radiusCanvas + pulse, 0, Math.PI * 2);
                        ctx.strokeStyle = 'rgba(6, 182, 212, 0.85)';
                        ctx.lineWidth = 2.5;
                        ctx.stroke();
                    }

                    ctx.beginPath();
                    ctx.arc(pos.x, pos.y, 6, 0, Math.PI * 2);
                    ctx.fillStyle = isSelected ? '#fff' : '#ffcc00';
                    ctx.fill();
                    ctx.strokeStyle = '#ffcc00';
                    ctx.stroke();

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

                const isFocused = focusedRadarItem && focusedRadarItem.type === 'extract' && focusedRadarItem.index === idx;
                if (isFocused) {
                    const pulse = 4 + Math.sin(Date.now() / 150) * 3;
                    ctx.beginPath();
                    ctx.arc(pos.x, pos.y, 8 + pulse, 0, Math.PI * 2);
                    ctx.strokeStyle = 'rgba(6, 182, 212, 0.85)';
                    ctx.lineWidth = 2.5;
                    ctx.stroke();
                }

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
                const radiusCanvas = (s.radius / worldW) * canvas.width;

                const isFocused = focusedRadarItem && focusedRadarItem.type === 'spawner' && focusedRadarItem.index === idx;
                if (isFocused) {
                    const pulse = 4 + Math.sin(Date.now() / 150) * 3;
                    ctx.beginPath();
                    ctx.arc(pos.x, pos.y, radiusCanvas + pulse, 0, Math.PI * 2);
                    ctx.strokeStyle = 'rgba(6, 182, 212, 0.85)';
                    ctx.lineWidth = 2.5;
                    ctx.stroke();
                }

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

                ctx.fillStyle = '#ff3131';
                ctx.font = 'bold 11px Outfit';
                ctx.textAlign = 'center';
                ctx.fillText(s.label || ('Zona ' + (idx + 1)), pos.x, pos.y - radiusCanvas - 6);
            });
        }

        requestAnimationFrame(draw);
    };
    draw();
}

function addFromRadar() {
    const x = parseInt(document.getElementById('radar-x').value);
    const y = parseInt(document.getElementById('radar-y').value);
    const isAltarDefense = (currentModeTab === 'altar_defense');

    if (isAltarDefense) {
        const ad = config.gameModes.altar_defense;
        if (radarMode === 'ad-altar') {
            ad.altarPos = { x, y };
            const ix = document.getElementById('ad-altar-x');
            const iy = document.getElementById('ad-altar-y');
            if (ix) ix.value = x;
            if (iy) iy.value = y;
        } else if (radarMode === 'ad-spawn') {
            if (!ad.spawnPoints) ad.spawnPoints = [];
            ad.spawnPoints.push({
                x, y,
                label: document.getElementById('radar-ad-spawn-label').value,
                radius: parseInt(document.getElementById('radar-ad-spawn-radius').value || 200)
            });
        } else if (radarMode === 'ad-spawner') {
            if (!ad.spawners) ad.spawners = [];
            ad.spawners.push({
                x, y,
                label: document.getElementById('radar-ad-spawner-label').value,
                radius: parseInt(document.getElementById('radar-ad-radius').value)
            });
        } else if (radarMode === 'ad-portal') {
            if (!ad.exitPortals) ad.exitPortals = [];
            ad.exitPortals.push({
                x, y,
                label: document.getElementById('radar-ad-portal-label').value,
                radius: parseInt(document.getElementById('radar-ad-portal-radius').value || 150)
            });
        }
    } else {
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
                label: document.getElementById('radar-label').value,
                proximityRadius: 300,
                targetZone: "1"
            });
        } else if (radarMode === 'spawn') {
            if (!config.gameModes.extraction.spawnPoints) config.gameModes.extraction.spawnPoints = [];
            config.gameModes.extraction.spawnPoints.push({
                x, y,
                label: document.getElementById('radar-spawn-label').value,
                radius: parseInt(document.getElementById('radar-spawn-radius').value)
            });
        }
    }
    renderModes();
}

function addAltarDefenseMap() {
    const select = document.getElementById('add-ad-map-select');
    if (!select) return;
    const mapId = parseInt(select.value);
    if (!config.gameModes.altar_defense.maps) config.gameModes.altar_defense.maps = [];
    if (!config.gameModes.altar_defense.maps.includes(mapId)) {
        config.gameModes.altar_defense.maps.push(mapId);
        renderModes();
    }
}

function addAltarDefenseWave() {
    const ad = config.gameModes.altar_defense;
    if (!ad.waves) ad.waves = [];
    ad.waves.push({
        name: `Oleada ${ad.waves.length + 1}`,
        delayMs: 5000,
        phases: [
            {
                name: "Fase 1",
                enemyId: "",
                count: 5,
                spawnerIndex: "random",
                spawnType: "together",
                staggerDelayMs: 500,
                startDelayMs: 0,
                focusTarget: "altar",
                spawnerDistribution: {
                    random: 5
                }
            }
        ]
    });
    renderModes();
}

/******************************************************************************
* RENDERER: MODOS DE JUEGO (ADICIONALES)
******************************************************************************/

function addAltarDefensePhase(waveIdx) {
    const waves = config.gameModes.altar_defense.waves;
    if (!waves || !waves[waveIdx]) return;
    if (!waves[waveIdx].phases) waves[waveIdx].phases = [];
    waves[waveIdx].phases.push({
        name: `Fase ${waves[waveIdx].phases.length + 1}`,
        enemyId: "",
        count: 5,
        spawnerIndex: "random",
        spawnType: "together",
        staggerDelayMs: 500,
        startDelayMs: 0,
        focusTarget: "altar",
        spawnerDistribution: {
            random: 5
        }
    });
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

// FUNCIONES AUXILIARES DE LOOT DROPS (v1.0)
function addLootDrop(enemyId, shouldRenderEnemyDetail = true) {
    if (!config.enemyModels[enemyId]) return;
    if (!config.enemyModels[enemyId].lootDrops) {
        config.enemyModels[enemyId].lootDrops = [];
    }
    config.enemyModels[enemyId].lootDrops.push({ itemId: "", chance: 0.1 });
    if (shouldRenderEnemyDetail) renderEnemyDetail();
}

function removeLootDrop(enemyId, idx, shouldRenderEnemyDetail = true) {
    if (!config.enemyModels[enemyId] || !config.enemyModels[enemyId].lootDrops) return;
    config.enemyModels[enemyId].lootDrops.splice(idx, 1);
    if (shouldRenderEnemyDetail) renderEnemyDetail();
}

function updateLootDropItem(enemyId, idx, itemId) {
    if (!config.enemyModels[enemyId] || !config.enemyModels[enemyId].lootDrops) return;
    config.enemyModels[enemyId].lootDrops[idx].itemId = itemId;
}

function updateLootDropChance(enemyId, idx, chance) {
    if (!config.enemyModels[enemyId] || !config.enemyModels[enemyId].lootDrops) return;
    config.enemyModels[enemyId].lootDrops[idx].chance = parseFloat(chance) / 100;
}

// FUNCIONES PUENTE PARA LOOT CONFIG
function addLootDropFromLootConfig(enemyId) {
    addLootDrop(enemyId, false);
    renderLootConfig();
}

function removeLootDropFromLootConfig(enemyId, idx) {
    removeLootDrop(enemyId, idx, false);
    renderLootConfig();
}

function updateLootDropItemFromLootConfig(enemyId, idx, itemId) {
    updateLootDropItem(enemyId, idx, itemId);
}

function updateLootDropChanceFromLootConfig(enemyId, idx, chance) {
    updateLootDropChance(enemyId, idx, chance);
}

function selectLootEnemy(id) {
    selectedLootEnemyId = id;
    localStorage.setItem('admin_last_loot_enemy', id);
    localStorage.setItem('admin_last_tab', 'enemy-loot');
    showTab('enemy-loot');
    renderEnemyLootDetail();
}

function addLootDropFromEnemyLoot(enemyId) {
    addLootDrop(enemyId, false);
    renderEnemyLootDetail();
}

function removeLootDropFromEnemyLoot(enemyId, idx) {
    removeLootDrop(enemyId, idx, false);
    renderEnemyLootDetail();
}

function updateLootDropItemFromEnemyLoot(enemyId, idx, itemId) {
    updateLootDropItem(enemyId, idx, itemId);
}

function updateLootDropChanceFromEnemyLoot(enemyId, idx, chance) {
    updateLootDropChance(enemyId, idx, chance);
}

window.collapsedWaves = window.collapsedWaves || {};
window.toggleWaveCollapse = function (idx) {
    window.collapsedWaves[idx] = !window.collapsedWaves[idx];
    renderModes();
};

function initMapRadar() {
    const canvas = document.getElementById('map-radar-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const container = document.getElementById('map-radar-container');

    const m = config.mapsConfig[selectedMapId];
    if (!m) return;

    // Estado de arrastre
    let isDragging = false;
    let dragItem = null;
    // Modo de colocación de objetos: null = solo mover/spawn, 'chest'|'door'|'tower'
    window._mapRadarObjectMode = window._mapRadarObjectMode || null;

    const updateCanvasSize = () => {
        const w = container.clientWidth;
        const h = container.clientHeight;
        if (w > 0 && h > 0) {
            canvas.width = w;
            canvas.height = h;
        } else {
            canvas.width = 400;
            canvas.height = 400;
        }
    };
    window.addEventListener('resize', updateCanvasSize);
    updateCanvasSize();

    // Convertir de coordenadas de mundo a coordenadas de canvas leyendo dinámicamente las dimensiones del mapa
    const worldToCanvas = (wx, wy) => {
        const worldW = m.width || 10000;
        const worldH = m.height || 10000;
        return {
            x: (wx / worldW) * canvas.width,
            y: (wy / worldH) * canvas.height
        };
    };

    // Convertir de canvas a mundo leyendo dinámicamente las dimensiones del mapa
    const canvasToWorld = (cx, cy) => {
        const worldW = m.width || 10000;
        const worldH = m.height || 10000;
        return {
            wx: (cx / canvas.width) * worldW,
            wy: (cy / canvas.height) * worldH
        };
    };

    canvas.onmousedown = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        // ------ MODO COLOCAR OBJETO ------
        if (window._mapRadarObjectMode) {
            const world = canvasToWorld(mouseX, mouseY);
            if (!m.objects) m.objects = [];

            // Solo Puertas: el resto de objetos se colocan/escalan en el editor 3D de Godot (MapEditor3D)
            m.objects.push({
                type: 'door',
                label: 'Puerta',
                x: Math.round(world.wx),
                y: Math.round(world.wy),
                assetPath: 'res://assets/Puertas/3D/Puerta2/Puerta2.glb',
                targetZoneId: '',
                targetX: 5000,
                targetY: 5000,
                scale: 1.0,
                rotY: 0,
                yOffset: 2.5
            });
            renderMapDetail();
            return;
        }

        // ------ MODO MOVER: primero chequear objetos ------
        const objects = m.objects || [];
        for (let i = 0; i < objects.length; i++) {
            const obj = objects[i];
            const pos = worldToCanvas(obj.x || 0, obj.y || 0);
            if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 12) {
                isDragging = true;
                dragItem = { type: 'map-obj', index: i };
                canvas.style.cursor = 'grabbing';
                highlightMapObject(i);
                return;
            }
        }

        // Buscar en Spawns de este mapa
        const spawns = m.spawns || [];
        for (let i = 0; i < spawns.length; i++) {
            const s = spawns[i];
            // Omitir spawns globales (random sin radio) ya que no tienen posición física real en el radar
            if (s.spawnMode === 'random' && (!s.radius || s.radius === 0)) continue;

            const sx = s.x !== undefined ? s.x : 1000;
            const sy = s.y !== undefined ? s.y : 1000;
            const pos = worldToCanvas(sx, sy);
            const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
            
            // Si hace clic en un spawn (dentro de 15px del centro)
            if (dist < 15) {
                isDragging = true;
                dragItem = { type: 'map-spawn', index: i };
                canvas.style.cursor = 'grabbing';
                highlightCard('map-spawn', i);
                return;
            }
        }

        // Si no agarró nada, capturar coordenadas del radar para mostrar
        const world = canvasToWorld(mouseX, mouseY);
        const rxInput = document.getElementById('map-radar-x');
        const ryInput = document.getElementById('map-radar-y');
        if (rxInput) rxInput.value = Math.round(world.wx);
        if (ryInput) ryInput.value = Math.round(world.wy);
    };

    window.onmousemove = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mouseX = Math.max(0, Math.min(canvas.width, e.clientX - rect.left));
        const mouseY = Math.max(0, Math.min(canvas.height, e.clientY - rect.top));
        const world = canvasToWorld(mouseX, mouseY);

        if (isDragging && dragItem) {
            if (dragItem.type === 'map-obj') {
                const obj = m.objects[dragItem.index];
                if (obj) {
                    obj.x = Math.round(world.wx);
                    obj.y = Math.round(world.wy);
                    const ix = document.getElementById(`map-obj-x-${dragItem.index}`);
                    const iy = document.getElementById(`map-obj-y-${dragItem.index}`);
                    if (ix) ix.value = obj.x;
                    if (iy) iy.value = obj.y;
                    const rxInput = document.getElementById('map-radar-x');
                    const ryInput = document.getElementById('map-radar-y');
                    if (rxInput) rxInput.value = obj.x;
                    if (ryInput) ryInput.value = obj.y;
                }
            } else if (dragItem.type === 'map-spawn') {
                const s = m.spawns[dragItem.index];
                s.x = Math.round(world.wx);
                s.y = Math.round(world.wy);
                const ix = document.querySelector(`input[onchange*="spawns[${dragItem.index}].x"], input[oninput*="spawns[${dragItem.index}].x"]`);
                const iy = document.querySelector(`input[onchange*="spawns[${dragItem.index}].y"], input[oninput*="spawns[${dragItem.index}].y"]`);
                if (ix) ix.value = s.x;
                if (iy) iy.value = s.y;
                const rxInput = document.getElementById('map-radar-x');
                const ryInput = document.getElementById('map-radar-y');
                if (rxInput) rxInput.value = s.x;
                if (ryInput) ryInput.value = s.y;
            }
        } else {
            // Mostrar coordenadas flotantes al mover el mouse si no arrastra
            window.lastMouseWorldX = Math.round(world.wx);
            window.lastMouseWorldY = Math.round(world.wy);
        }
    };

    window.onmouseup = () => {
        if (isDragging) {
            isDragging = false;
            dragItem = null;
            canvas.style.cursor = window._mapRadarObjectMode ? 'cell' : 'crosshair';
        }
    };

    const draw = () => {
        if (!document.getElementById('map-radar-canvas')) return;
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        const worldW = m.width || 10000;
        const worldH = m.height || 10000;

        // Fondo del radar oscuro de alta gama
        ctx.fillStyle = '#0a0f1d';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // Dibujar Grid cibernético fino
        ctx.strokeStyle = m.color ? m.color + '15' : 'rgba(6, 182, 212, 0.08)';
        ctx.lineWidth = 1;
        const gridDivisions = 10;
        for (let i = 1; i < gridDivisions; i++) {
            ctx.beginPath();
            ctx.moveTo((canvas.width / gridDivisions) * i, 0);
            ctx.lineTo((canvas.width / gridDivisions) * i, canvas.height);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(0, (canvas.height / gridDivisions) * i);
            ctx.lineTo(canvas.width, (canvas.height / gridDivisions) * i);
            ctx.stroke();
        }

        // Líneas divisoria centrales
        ctx.strokeStyle = m.color ? m.color + '40' : 'rgba(6, 182, 212, 0.35)';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(canvas.width / 2, 0);
        ctx.lineTo(canvas.width / 2, canvas.height);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(0, canvas.height / 2);
        ctx.lineTo(canvas.width, canvas.height / 2);
        ctx.stroke();

        // Círculos concéntricos de radar sonar
        ctx.strokeStyle = m.color ? m.color + '20' : 'rgba(6, 182, 212, 0.15)';
        ctx.lineWidth = 1.5;
        const circles = [0.15, 0.3, 0.45];
        circles.forEach(rMult => {
            ctx.beginPath();
            ctx.arc(canvas.width / 2, canvas.height / 2, canvas.width * rMult, 0, Math.PI * 2);
            ctx.stroke();
        });

        // ========== CINTURÓN DE ASTEROIDES / BARRERA ORBITAL ==========
        try {
            const rockKey = `rocks_${selectedMapId}_${canvas.width}_${canvas.height}`;
            if (!window._rockCache) window._rockCache = {};
            if (!window._rockCache[rockKey]) {
                const wRocks = [];
                const rockCount = 400;
                const borderPxW = canvas.width * 0.06;
                const borderPxH = canvas.height * 0.06;
                let s = parseInt(selectedMapId || '1') * 7919 + 13;
                const rng = () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };

                for (let i = 0; i < rockCount; i++) {
                    const side = Math.floor(rng() * 4);
                    const t = rng();
                    const depthPxX = rng() * borderPxW;
                    const depthPxY = rng() * borderPxH;
                    let cx, cy;
                    if (side === 0) {
                        cx = t * canvas.width;
                        cy = depthPxY;
                    } else if (side === 1) {
                        cx = t * canvas.width;
                        cy = canvas.height - depthPxY;
                    } else if (side === 2) {
                        cx = depthPxX;
                        cy = t * canvas.height;
                    } else {
                        cx = canvas.width - depthPxX;
                        cy = t * canvas.height;
                    }
                    const sizePx = 3 + rng() * 12;
                    const bright = 80 + Math.floor(rng() * 100);
                    const color = `rgb(${bright},${bright + 8},${bright + 18})`;
                    const alpha = 0.4 + rng() * 0.6;
                    const pts = 5 + Math.floor(rng() * 4);
                    const verts = [];
                    for (let j = 0; j < pts; j++) {
                        const angle = (j / pts) * Math.PI * 2;
                        const rv = sizePx * (0.4 + rng() * 0.6);
                        verts.push({ ox: Math.cos(angle) * rv, oy: Math.sin(angle) * rv });
                    }
                    wRocks.push({ cx, cy, color, alpha, verts });
                }
                window._rockCache[rockKey] = wRocks;
            }
            const rocks = window._rockCache[rockKey];
            for (let i = 0; i < rocks.length; i++) {
                const r = rocks[i];
                ctx.fillStyle = r.color;
                ctx.globalAlpha = r.alpha;
                ctx.beginPath();
                for (let j = 0; j < r.verts.length; j++) {
                    const px = r.cx + r.verts[j].ox;
                    const py = r.cy + r.verts[j].oy;
                    if (j === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                }
                ctx.closePath();
                ctx.fill();
            }
            ctx.globalAlpha = 1.0;
        } catch(e) {
            console.warn("Rock border error:", e);
        }

        // ========== DIBUJAR SPAWNS ==========
        const spawns = m.spawns || [];
        spawns.forEach((s, idx) => {
            if (s.spawnMode === 'random' && (!s.radius || s.radius === 0)) return;

            const sx = s.x !== undefined ? s.x : 1000;
            const sy = s.y !== undefined ? s.y : 1000;
            const pos = worldToCanvas(sx, sy);
            const isSelected = isDragging && dragItem && dragItem.type === 'map-spawn' && dragItem.index === idx;

            if (s.spawnMode === 'random' && s.radius > 0) {
                const radiusCanvas = (s.radius / worldW) * canvas.width;
                ctx.fillStyle = 'rgba(16, 185, 129, 0.05)';
                ctx.strokeStyle = 'rgba(16, 185, 129, 0.2)';
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, radiusCanvas, 0, Math.PI * 2);
                ctx.fill();
                ctx.stroke();
            }

            ctx.fillStyle = isSelected ? '#fff' : 'rgba(16, 185, 129, 0.2)';
            ctx.strokeStyle = '#10b981';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 10, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();

            ctx.fillStyle = '#10b981';
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 3.5, 0, Math.PI * 2);
            ctx.fill();

            const model = config.enemyModels[s.type] || { name: 'Enemigo ' + s.type };
            ctx.fillStyle = '#10b981';
            ctx.font = 'bold 9px Outfit';
            ctx.textAlign = 'center';
            ctx.fillText(model.name, pos.x, pos.y - 14);
        });

        // ========== DIBUJAR OBJETOS DEL MUNDO ==========
        const OBJECT_STYLES = {
            chest: { color: '#ffd700', glow: 'rgba(255,215,0,0.3)', icon: 'B', size: 9 },
            door:  { color: '#00d2ff', glow: 'rgba(0,210,255,0.3)', icon: 'P', size: 10 },
            tower: { color: '#ff8c00', glow: 'rgba(255,140,0,0.3)', icon: 'T', size: 9 },
            wall:  { color: '#a87c52', glow: 'rgba(168,124,82,0.3)', icon: '🧱', size: 9 }
        };
        const objects = m.objects || [];
        objects.forEach((obj, idx) => {
            const pos = worldToCanvas(obj.x || 0, obj.y || 0);
            const isSelected = isDragging && dragItem && dragItem.type === 'map-obj' && dragItem.index === idx;
            const isHighlighted = window._highlightedMapObj === idx;
            const style = OBJECT_STYLES[obj.type] || { color: '#aaa', glow: 'rgba(200,200,200,0.2)', icon: 'O', size: 9 };

            if (isSelected || isHighlighted) {
                const pulse = 3 + Math.sin(Date.now() / 180) * 2;
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, 14 + pulse, 0, Math.PI * 2);
                ctx.strokeStyle = style.color;
                ctx.lineWidth = 2;
                ctx.stroke();
            }

            ctx.fillStyle = style.glow;
            ctx.strokeStyle = style.color;
            ctx.lineWidth = isSelected ? 2.5 : 1.5;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 11, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();

            ctx.fillStyle = isSelected ? '#fff' : style.color;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, 4, 0, Math.PI * 2);
            ctx.fill();

            ctx.fillStyle = '#fff';
            ctx.font = `bold ${style.size}px Outfit`;
            ctx.textAlign = 'center';
            ctx.fillText(style.icon, pos.x, pos.y + 3);

            const label = obj.label || (obj.type === 'door' ? 'Puerta' : obj.type === 'chest' ? 'Baúl' : 'Torre');
            ctx.fillStyle = style.color;
            ctx.font = '8px Outfit';
            ctx.textAlign = 'center';
            ctx.fillText(label, pos.x, pos.y - 16);

            if (obj.type === 'door' && obj.targetZoneId) {
                const destZoneName = config.mapsConfig[obj.targetZoneId]?.name || `Zona ${obj.targetZoneId}`;
                ctx.fillStyle = 'rgba(0,210,255,0.7)';
                ctx.font = '7px Outfit';
                ctx.textAlign = 'center';
                ctx.fillText(`→ ${destZoneName}`, pos.x, pos.y + 22);
            }
        });

        if (window._mapRadarObjectMode) {
            const modeStyle = OBJECT_STYLES[window._mapRadarObjectMode];
            ctx.fillStyle = modeStyle ? modeStyle.color : '#fff';
            ctx.font = 'bold 10px Outfit';
            ctx.textAlign = 'left';
            ctx.fillText(`MODO: COLOCAR ${window._mapRadarObjectMode.toUpperCase()}  (clic para colocar)`, 8, 16);
        }

        if (window.lastMouseWorldX !== undefined && window.lastMouseWorldY !== undefined) {
            ctx.fillStyle = 'rgba(255, 255, 255, 0.6)';
            ctx.font = '10px monospace';
            ctx.textAlign = 'left';
            ctx.fillText(`X: ${window.lastMouseWorldX} Y: ${window.lastMouseWorldY}`, 10, canvas.height - 10);
        }

        requestAnimationFrame(draw);
    };
    draw();
}

// Activar/desactivar modo de colocación de puerta en el radar del mapa
function setMapRadarObjectMode(type) {
    window._mapRadarObjectMode = type;
    const hint = document.getElementById('map-radar-mode-hint');
    const canvas = document.getElementById('map-radar-canvas');
    if (type) {
        const labels = { door: '🚪 Puerta' };
        if (hint) hint.innerHTML = `<span style="color:#ffd700;">MODO: Haz clic en el radar para colocar ${labels[type] || type}. Presioná "Mover" para salir.</span>`;
        if (canvas) canvas.style.cursor = 'cell';
    } else {
        if (hint) hint.textContent = '🖱️ Arrastra puertas/spawns u objetos o haz clic para ver coordenadas.';
        if (canvas) canvas.style.cursor = 'crosshair';
    }
}

// Agregar puerta al mapa desde el botón del panel
function addMapObject(mapId) {
    if (!config.mapsConfig[mapId]) return;
    if (!config.mapsConfig[mapId].objects) config.mapsConfig[mapId].objects = [];
    const radarX = parseInt(document.getElementById('map-radar-x')?.value) || 5000;
    const radarY = parseInt(document.getElementById('map-radar-y')?.value) || 5000;

    config.mapsConfig[mapId].objects.push({
        type: 'door',
        label: 'Puerta',
        x: radarX,
        y: radarY,
        assetPath: 'res://assets/Puertas/3D/Puerta2/Puerta2.glb',
        targetZoneId: '',
        targetX: 5000,
        targetY: 5000,
        scale: 1.0,
        rotY: 0,
        yOffset: 2.5
    });
}


// Resaltar visualmente la tarjeta de objeto en el panel
function highlightMapObject(idx) {
    window._highlightedMapObj = idx;
    document.querySelectorAll('[id^="card-map-obj-"]').forEach(el => {
        el.style.boxShadow = '';
        el.style.borderColor = '';
    });
    const card = document.getElementById(`card-map-obj-${idx}`);
}

// ============================================================================
// LOGICA DE TALENTOS Y MAPA DE CONEXIONES (TREE MAP)
// ============================================================================

let talentMapperTool = 'select'; // 'select' o 'connect'
let selectedTalentNodeId = null;
let connectStartNodeId = null;
let talentPanOffset = { x: 0, y: 0 };
let isPanningTalents = false;
let panStart = { x: 0, y: 0 };
let isDraggingTalentNode = false;
let dragNodeId = null;
let talentMapperCanvasInitialized = false;

function addNewTalent() {
    const id = 'talent_' + Date.now();
    const newTalent = {
        id: id,
        name: 'Nuevo Talento',
        desc: '+1% HP por nivel',
        category: 'engineering',
        maxLevel: 5,
        effects: {
            hp_pct: 0.01
        },
        icon: '🌳'
    };
    if (!config.talentsConfig.talents) config.talentsConfig.talents = [];
    config.talentsConfig.talents.push(newTalent);
    renderTalentCreator();
    renderTalentMapper();
}

function deleteTalent(id) {
    // Eliminar de la lista de creador
    config.talentsConfig.talents = config.talentsConfig.talents.filter(t => t.id !== id);
    // Eliminar de los nodos del mapa
    if (config.talentsConfig.nodes && config.talentsConfig.nodes[id]) {
        delete config.talentsConfig.nodes[id];
    }
    // Eliminar conexiones
    if (config.talentsConfig.connections) {
        config.talentsConfig.connections = config.talentsConfig.connections.filter(c => c.from !== id && c.to !== id);
    }
    if (selectedTalentNodeId === id) {
        selectedTalentNodeId = null;
        document.getElementById('talent-node-editor-card').style.display = 'none';
    }
    renderTalentCreator();
    renderTalentMapper();
}

function setTalentMapperTool(tool) {
    talentMapperTool = tool;
    const btnSelect = document.getElementById('btn-talent-tool-select');
    const btnConnect = document.getElementById('btn-talent-tool-connect');
    if (btnSelect && btnConnect) {
        if (tool === 'select') {
            btnSelect.classList.remove('btn-secondary');
            btnSelect.classList.add('btn-primary');
            btnConnect.classList.remove('btn-primary');
            btnConnect.classList.add('btn-secondary');
        } else {
            btnConnect.classList.remove('btn-secondary');
            btnConnect.classList.add('btn-primary');
            btnSelect.classList.remove('btn-primary');
            btnSelect.classList.add('btn-secondary');
        }
    }
}

function clearTalentMapperSelections() {
    selectedTalentNodeId = null;
    connectStartNodeId = null;
    document.getElementById('talent-node-editor-card').style.display = 'none';
    renderTalentMapper();
}

function placeTalentOnMap(talentId) {
    if (!config.talentsConfig.nodes) config.talentsConfig.nodes = {};
    
    // Obtener dimensiones del canvas para centrarlo
    const canvas = document.getElementById('talent-mapper-canvas');
    let cx = 400;
    let cy = 300;
    if (canvas) {
        cx = (canvas.width / 2) - talentPanOffset.x;
        cy = (canvas.height / 2) - talentPanOffset.y;
    }

    config.talentsConfig.nodes[talentId] = {
        x: Math.round(cx),
        y: Math.round(cy)
    };
    renderTalentMapper();
}

function removeTalentFromMap(talentId) {
    if (config.talentsConfig.nodes && config.talentsConfig.nodes[talentId]) {
        delete config.talentsConfig.nodes[talentId];
    }
    if (config.talentsConfig.connections) {
        config.talentsConfig.connections = config.talentsConfig.connections.filter(c => c.from !== talentId && c.to !== talentId);
    }
    if (selectedTalentNodeId === talentId) {
        selectedTalentNodeId = null;
        document.getElementById('talent-node-editor-card').style.display = 'none';
    }
    renderTalentMapper();
}

function initTalentMapper() {
    const canvas = document.getElementById('talent-mapper-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const container = document.getElementById('talent-mapper-container');

    const updateCanvasSize = () => {
        const w = canvas.parentElement.clientWidth;
        const h = canvas.parentElement.clientHeight;
        if (w > 0 && h > 0) {
            canvas.width = w;
            canvas.height = h;
        }
    };
    
    if (!talentMapperCanvasInitialized) {
        window.addEventListener('resize', updateCanvasSize);
        talentMapperCanvasInitialized = true;
    }
    updateCanvasSize();

    // Mouse event positions
    let mousePos = { x: 0, y: 0 };

    const getNodeAtPosition = (mx, my) => {
        if (!config.talentsConfig.nodes) return null;
        const radius = 30; // Radio del círculo del talento
        for (const [id, pos] of Object.entries(config.talentsConfig.nodes)) {
            const screenX = pos.x + talentPanOffset.x;
            const screenY = pos.y + talentPanOffset.y;
            const dist = Math.hypot(screenX - mx, screenY - my);
            if (dist <= radius) {
                return id;
            }
        }
        return null;
    };

    canvas.onmousedown = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mx = e.clientX - rect.left;
        const my = e.clientY - rect.top;
        mousePos = { x: mx, y: my };

        const clickedNodeId = getNodeAtPosition(mx, my);

        if (clickedNodeId) {
            if (talentMapperTool === 'select') {
                isDraggingTalentNode = true;
                dragNodeId = clickedNodeId;
                selectedTalentNodeId = clickedNodeId;
                canvas.style.cursor = 'grabbing';
                showTalentNodeEditor(clickedNodeId);
            } else if (talentMapperTool === 'connect') {
                connectStartNodeId = clickedNodeId;
            }
        } else {
            // Panning
            isPanningTalents = true;
            panStart = { x: e.clientX, y: e.clientY };
            canvas.style.cursor = 'move';
        }
        renderTalentMapper();
    };

    canvas.onmousemove = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mx = e.clientX - rect.left;
        const my = e.clientY - rect.top;
        mousePos = { x: mx, y: my };

        if (isDraggingTalentNode && dragNodeId) {
            config.talentsConfig.nodes[dragNodeId].x = Math.round(mx - talentPanOffset.x);
            config.talentsConfig.nodes[dragNodeId].y = Math.round(my - talentPanOffset.y);
            renderTalentMapper();
        } else if (isPanningTalents) {
            const dx = e.clientX - panStart.x;
            const dy = e.clientY - panStart.y;
            talentPanOffset.x += dx;
            talentPanOffset.y += dy;
            panStart = { x: e.clientX, y: e.clientY };
            renderTalentMapper();
        } else if (connectStartNodeId) {
            renderTalentMapper(mousePos);
        }
    };

    canvas.onmouseup = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mx = e.clientX - rect.left;
        const my = e.clientY - rect.top;

        if (isDraggingTalentNode) {
            isDraggingTalentNode = false;
            dragNodeId = null;
            canvas.style.cursor = 'grab';
        } else if (isPanningTalents) {
            isPanningTalents = false;
            canvas.style.cursor = 'grab';
        } else if (connectStartNodeId) {
            const clickedNodeId = getNodeAtPosition(mx, my);
            if (clickedNodeId && clickedNodeId !== connectStartNodeId) {
                // Crear conexión si no existe
                if (!config.talentsConfig.connections) config.talentsConfig.connections = [];
                const exists = config.talentsConfig.connections.some(c => 
                    (c.from === connectStartNodeId && c.to === clickedNodeId) ||
                    (c.from === clickedNodeId && c.to === connectStartNodeId)
                );
                if (!exists) {
                    config.talentsConfig.connections.push({
                        from: connectStartNodeId,
                        to: clickedNodeId
                    });
                }
            }
            connectStartNodeId = null;
            renderTalentMapper();
        }
    };

    renderTalentMapper();
}

function showTalentNodeEditor(nodeId) {
    const card = document.getElementById('talent-node-editor-card');
    const content = document.getElementById('talent-node-editor-content');
    if (!card || !content) return;

    const talent = config.talentsConfig.talents.find(t => t.id === nodeId);
    if (!talent) return;

    card.style.display = 'block';
    
    // Generar campos de edición rápida del nodo mapeado
    content.innerHTML = `
        <div style="font-size:1.8rem; text-align:center; margin-bottom:10px;">${talent.icon || '🌳'}</div>
        <div style="font-weight:bold; color:var(--accent); text-align:center; margin-bottom:15px;">${talent.name}</div>
        <div class="field">
            <label>Posición X</label>
            <input type="number" value="${config.talentsConfig.nodes[nodeId].x}" onchange="config.talentsConfig.nodes['${nodeId}'].x = parseInt(this.value); renderTalentMapper();">
        </div>
        <div class="field">
            <label>Posición Y</label>
            <input type="number" value="${config.talentsConfig.nodes[nodeId].y}" onchange="config.talentsConfig.nodes['${nodeId}'].y = parseInt(this.value); renderTalentMapper();">
        </div>
        <div style="display:flex; flex-direction:column; gap:10px; margin-top:20px;">
            <button class="btn btn-secondary" style="background:#ff3b30; border-color:#ff3b30; color:white; margin:0;" onclick="removeTalentFromMap('${nodeId}')">❌ Quitar del Mapa</button>
        </div>
    `;
}


