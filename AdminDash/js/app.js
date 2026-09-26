let socket;
let chatSocket = null;
let config = {};
window.config = config;

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
let usernameHidden = false;
let currentLoggedUser = '';
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
        'ammo': 'folder-market', 'weapons': 'folder-market', 'shields': 'folder-market', 'engines': 'folder-market', 'spheres': 'folder-market', 'market': 'folder-market',
        'skills': 'folder-skills',
        'modes': 'folder-modes',
        'loot': 'folder-loot',
        'enemy-loot': 'folder-loot',
        'crafting-recipes': 'folder-crafting',
        'crafting-materials': 'folder-crafting',
        'crafting-categories': 'folder-crafting'
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
        'shields': 'Mercado: Escudos', 'engines': 'Mercado: Propulsión', 'spheres': 'Mercado: Esferas', 'market': 'Regulador de Mercado',
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
        'crafting-categories': 'Categorías de Crafteo',
        'quests': 'Misiones de la Galaxia',
        'battlepass': 'Pase de Batalla',
        'chat-global': 'Transmisión y Chat Global',
        'ranking': 'Sistema de Clasificación',
        'bugreports': 'Reportes de Bugs'
    };
    document.getElementById('current-view-title').innerText = titles[tabId] || 'Configuración';

    if (tabId === 'json') document.getElementById('json-editor').value = JSON.stringify(config, null, 4);
    if (tabId === 'bugreports') loadBugReports();
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

    // v2.1: Si es el mapa de talentos, garantizar sincronización de resolución y centrado
    if (tabId === 'talent-mapper') {
        setTimeout(() => {
            if (typeof syncTalentCanvasSize === 'function') syncTalentCanvasSize();
            if (typeof renderTalentMapper === 'function') renderTalentMapper();
            if (typeof renderTalentMapperSideList === 'function') renderTalentMapperSideList();
        }, 60);
    }

    // Sincronizar el árbol del sidebar en caliente
    if (typeof updateSidebar === 'function') {
        updateSidebar();
    }
}

window.enterOfflineMode = function(targetTab = 'talent-mapper') {
    const overlay = document.getElementById('login-overlay');
    if (overlay) overlay.style.display = 'none';
    if (!config || Object.keys(config).length === 0) {
        config = {};
        patchMechanicsLib();
    }
    document.getElementById('conn-dot').classList.add('online');
    document.getElementById('conn-text').innerText = '💻 MODO PREVIEW';
    if (typeof showTab === 'function') {
        showTab(targetTab);
    }
};

window.onload = () => {
    // Soporte para apertura directa en modo offline/preview (útil para desarrollo o verificación)
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.get('preview') || urlParams.get('offline') || urlParams.get('bypass')) {
        window.enterOfflineMode(urlParams.get('tab') || 'talent-mapper');
        return;
    }

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

function toggleUsernameVisibility() {
    usernameHidden = !usernameHidden;
    const btn = document.getElementById('eye-toggle');
    const text = document.getElementById('conn-text');
    if (usernameHidden) {
        btn.textContent = '🙈';
        btn.title = 'Mostrar nombre';
        const envLabel = activeEnv === 'cloud' ? '☁️ SERVER' : '💻 LOCAL';
        text.innerText = envLabel;
    } else {
        btn.textContent = '👁';
        btn.title = 'Ocultar nombre';
        if (currentLoggedUser) {
            const envLabel = activeEnv === 'cloud' ? `☁️ SERVER: ${currentLoggedUser.toUpperCase()}` : `💻 LOCAL: ${currentLoggedUser.toUpperCase()}`;
            text.innerText = envLabel;
        }
    }
}

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

    // v500.0: Casa de Subastas (Mercado) — lista de publicaciones para moderación
    socket.on('adminMarketListings', (data) => {
        window.marketListings = (data && data.listings) ? data.listings : [];
        if (document.getElementById('view-market').classList.contains('active')) renderMarket();
    });

    // v1.1: Reportes de Bugs - se escuchan desde AMBOS servidores (local y cloud)
    const setupBugReportSocket = (sock, source) => {
        sock.on('bugReportsList', (data) => {
            mergeBugReports((data || []).map(r => ({ ...r, source })), true, source);
        });
        sock.on('bugReportReceived', (report) => {
            if (!report) return;
            mergeBugReports([{ ...report, source }], false);
            if (!document.getElementById('view-bugreports').classList.contains('active')) {
                const srcTag = source === 'cloud' ? '☁️ SERVER' : '💻 LOCAL';
                showToast(`🐛 NUEVO REPORTE DE BUG DE ${String(report.nick || '').toUpperCase()} (${srcTag})`);
            }
        });
    };
    setupBugReportSocket(socketLocal, 'local');
    setupBugReportSocket(socketCloud, 'cloud');

    socket.on('loginSuccess', (data) => {
        socket.emit('getAssetFiles');
        loadBugReports(); // v1.1: Cargar reportes de bugs de ambos servidores
        if (remember) {
            localStorage.setItem('admin_user', user);
            localStorage.setItem('admin_pass', pass);
        } else {
            localStorage.removeItem('admin_user');
            localStorage.removeItem('admin_pass');
        }
        document.getElementById('login-overlay').style.display = 'none';
        currentLoggedUser = user;
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
                    expRequirements: Array(30).fill(0).map((_, i) => (i + 1) * 1000),
                    sphereSlotRequirements: Array.from({ length: 4 }, (_, i) => ({ name: `Slot ${i + 1}`, requirements: [] }))
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

            // v600.0: Talentos que requieren desbloqueo por misión
            if (!config.talentsLockedConfig) {
                config.talentsLockedConfig = JSON.parse(JSON.stringify(DEFAULT_TALENTS_LOCKED_CONFIG));
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

            // v500.0: Inicializar configuración de la Casa de Subastas (Mercado)
            if (!config.marketConfig) {
                config.marketConfig = JSON.parse(JSON.stringify(DEFAULT_MARKET_CONFIG));
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
        usernameHidden = false;
        const eyeBtn = document.getElementById('eye-toggle');
        if (eyeBtn) { eyeBtn.textContent = '👁'; eyeBtn.title = 'Ocultar/Mostrar nombre'; }
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

// v1.1: Reportes de Bugs - acciones del dashboard (apuntan al servidor de origen del reporte)
function loadBugReports() {
    if (socketLocal && socketLocal.connected) socketLocal.emit('getBugReports');
    if (socketCloud && socketCloud.connected) socketCloud.emit('getBugReports');
}

function bugReportSocket(source) {
    const sock = source === 'cloud' ? socketCloud : socketLocal;
    return (sock && sock.connected) ? sock : null;
}

function deleteBugReport(id, source) {
    if (!confirm(`¿Eliminar el reporte de bug #${id}${source === 'cloud' ? ' (☁️ SERVER)' : ' (💻 LOCAL)'}? Esta acción es permanente.`)) return;
    const sock = bugReportSocket(source);
    if (sock) sock.emit('deleteBugReport', { id });
}

function setBugReportStatus(id, status, source) {
    const sock = bugReportSocket(source);
    if (sock) sock.emit('setBugReportStatus', { id, status });
}

function getFilter() {
    return (document.getElementById('global-filter')?.value || '').toLowerCase();
}

window.filterTalentCreator = function() {
    renderTalentCreator();
};

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

window.toggleMechCard = function(enemyId, listName, idx) {
    const m = config.enemyModels[enemyId]?.[listName]?.[idx];
    if (!m) return;
    m._collapsed = !m._collapsed;
    const chevron = document.getElementById(`mc-chevron-${enemyId}-${listName}-${idx}`);
    const body = document.getElementById(`mc-body-${enemyId}-${listName}-${idx}`);
    if (chevron) chevron.classList.toggle('collapsed', !!m._collapsed);
    if (body) body.classList.toggle('collapsed', !!m._collapsed);
};
window.toggleAllMechCards = function(enemyId, listName, collapse) {
    const list = config.enemyModels[enemyId]?.[listName];
    if (!list) return;
    list.forEach(m => { m._collapsed = collapse; });
    renderEnemyDetail();
};

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
            else if (f === 'visionRange') config.enemyModels[id].movementPhases[idx][f] = 800;
            else if (f === 'targetPriority') config.enemyModels[id].movementPhases[idx][f] = 'all';
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

// v500.0: Gestión de Condiciones de Fases Dinámicas
function updateMovementPhaseCondition(enemyId, phaseIdx, conditionKey, value) {
    const phase = config.enemyModels[enemyId].movementPhases[phaseIdx];
    if (!phase.conditions) phase.conditions = {};
    if (value === '' || value === null || value === undefined) {
        delete phase.conditions[conditionKey];
        if (Object.keys(phase.conditions).length === 0) {
            delete phase.conditions;
        }
    } else {
        phase.conditions[conditionKey] = value;
    }
}

function addMechanic(enemyId) {
    if (!config.enemyModels[enemyId].mechanics) config.enemyModels[enemyId].mechanics = [];
    config.enemyModels[enemyId].mechanics.push({
        type: "laser",
        castTimeMs: 0,
        castInterruptible: true,
        activationMode: "time",
        activationHPs: [50],
        activationIntervalMs: 0,
        bulletDamage: 10,
        bulletSpeed: 800,
        fireRange: 600,
        fireRate: 1000,
        startDelay: 0
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
        castTimeMs: 0,
        castInterruptible: true,
        activationMode: "time",
        activationHPs: [50],
        activationIntervalMs: 0,
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
            if (f === 'castTimeMs') mech[f] = 0;
            else if (f === 'castInterruptible') mech[f] = true;
            else if (f === 'reductionPercentage') mech[f] = 10;
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
            else if (f === 'activationMode') mech[f] = 'time';
            else if (f === 'activationHPs') mech[f] = [50];
            else if (f === 'activationIntervalMs') mech[f] = 0;
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
            else if (f === 'targetSphereColor') mech[f] = '';
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
            if (f === 'radius') mech[f] = newType === 'ascension' ? 250 : 250;
            else if (f === 'damage') mech[f] = newType === 'spin_ring' ? 100 : (newType === 'circle_cast' ? 500 : 15);
            else if (f === 'intervalMs') mech[f] = 1000;
            else if (f === 'duration') mech[f] = 5000;
            else if (f === 'cooldown') mech[f] = newType === 'summoning' ? 30000 : (newType === 'spin_ring' ? 4000 : (newType === 'circle_cast' ? 5000 : 10000));
            else if (f === 'bulletDamage') mech[f] = newType === 'ascension' ? 150 : 10;
            else if (f === 'bulletSpeed') mech[f] = 800;
            else if (f === 'fireRange') mech[f] = newType === 'circle_cast' ? 300 : 600;
            else if (f === 'fireRate') mech[f] = 1000;
            else if (f === 'burstShots') mech[f] = 1;
            else if (f === 'aimDelayMs') mech[f] = 1000;
            else if (f === 'coneFollow') mech[f] = false;
            else if (f === 'lockTimeMs') mech[f] = newType === 'circle_cast' ? 800 : 0;
            else if (f === 'castTimeMs') mech[f] = 0;
            else if (f === 'castInterruptible') mech[f] = true;
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
            else if (f === 'activationMode') mech[f] = 'time';
            else if (f === 'activationHPs') mech[f] = [50];
            else if (f === 'activationIntervalMs') mech[f] = 0;
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
            else if (f === 'warnTimeMs') mech[f] = newType === 'ascension' ? 2200 : 1200;
            else if (f === 'undergroundMs') mech[f] = 2500;
            else if (f === 'targetMode') mech[f] = newType === 'burrow' ? 'proximity' : 'proximity';
            else if (f === 'targetSphereColor') mech[f] = '';
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
             else if (f === 'targetCount') mech[f] = newType === 'execution' ? 3 : 1;
             else if (f === 'castTimeMs') mech[f] = 0;
              else if (f === 'castInterruptible') mech[f] = true;
             else if (f === 'turnSpeed') mech[f] = newType === 'execution' ? 1.9 : 1.2;
             else if (f === 'airTimeMs') mech[f] = newType === 'ascension' ? 2000 : 2000;
             else if (f === 'warnDelayMs') mech[f] = newType === 'ascension' ? 0 : 600;
             else if (f === 'slowAmount') mech[f] = 30;
             else if (f === 'slowIsPercentage') mech[f] = false;
             else if (f === 'stunDuration') mech[f] = 1500;
             else if (f === 'arcAngle') mech[f] = 120;
             else if (f === 'fullCircle') mech[f] = false;
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

// ============================================================================
// CARTROGRAFÍA: SELECCIÓN, COLAPSO, BORRADO CON TECLA SUPR Y MODALES DE AGREGADO
// ============================================================================

window._mapSelection = null;              // { kind: 'spawn'|'door'|'ambience', index }
window._mapCardExpanded = window._mapCardExpanded || {};  // claves: 'spawn-i'|'door-i'|'amb-i'
window._highlightedAmbienceIdx = null;

function isMapCardExpanded(key) {
    if (!(key in window._mapCardExpanded)) window._mapCardExpanded[key] = false;
    return window._mapCardExpanded[key];
}

function toggleMapCard(key) {
    window._mapCardExpanded[key] = !window._mapCardExpanded[key];
    renderMapDetail();
    if (window._mapSelection) selectMapItem(window._mapSelection.kind, window._mapSelection.index);
}

// Seleccionar un ítem del mapa (desde el radar o desde la lista) y resaltarlo
function selectMapItem(kind, idx) {
    window._mapSelection = { kind, index: idx };
    const prefixes = { spawn: 'card-map-spawn-', door: 'card-map-obj-', market: 'card-map-obj-', ambience: 'card-map-amb-' };
    document.querySelectorAll('[id^="card-map-spawn-"], [id^="card-map-obj-"], [id^="card-map-amb-"]').forEach(el => {
        el.style.boxShadow = '';
        el.style.borderColor = '';
        el.style.background = '';
    });
    const card = document.getElementById((prefixes[kind] || 'card-map-') + idx);
    if (card) {
        card.style.borderColor = 'var(--accent)';
        card.style.boxShadow = '0 0 25px rgba(6, 182, 212, 0.45)';
        card.style.background = 'rgba(6, 182, 212, 0.08)';
    }
    if (kind === 'spawn') {
        focusedRadarItem = { type: 'map-spawn', index: idx };
        window._highlightedMapObj = null;
        window._highlightedAmbienceIdx = null;
    } else if (kind === 'door' || kind === 'market') {
        window._highlightedMapObj = idx;
        focusedRadarItem = null;
        window._highlightedAmbienceIdx = null;
    } else {
        window._highlightedAmbienceIdx = idx;
        focusedRadarItem = null;
        window._highlightedMapObj = null;
    }
}

// Abrir modal de confirmación de eliminación (usado por tecla Supr y botón ✕)
async function requestMapDelete(kind, idx) {
    const m = config.mapsConfig[selectedMapId];
    if (!m) return;
    let title = '⚠️ ELIMINACIÓN';
    let msg = '';
    if (kind === 'spawn') {
        const s = m.spawns && m.spawns[idx];
        if (!s) return;
        const en = s.type ? config.enemyModels[s.type] : null;
        const enName = en ? `[ID ${s.type}] ${en.name}` : (s.type ? `ID ${s.type}` : 'Sin enemigo asignado');
        const modeName = s.spawnMode === 'polygon' ? 'Polígono personalizado' : (s.spawnMode === 'random' ? (s.radius > 0 ? 'Aleatorio en un área' : 'Aleatorio (todo el mapa)') : 'Fijo');
        msg = `SE ELIMINARÁ ESTE ENEMIGO:\n\n👾 ${enName}\nModo: ${modeName}\nCant. Máx: ${s.count}\nUbicación: X ${s.x !== undefined ? s.x : 1000}, Y ${s.y !== undefined ? s.y : 1000}\n\n¿Confirmás la eliminación?`;
        title = '⚠️ ELIMINAR ENEMIGO';
    } else if (kind === 'door') {
        const o = m.objects && m.objects[idx];
        if (!o) return;
        msg = `SE ELIMINARÁ ESTA PUERTA:\n\n🚪 ${o.label || 'Puerta'}\nUbicación: X ${o.x || 0}, Y ${o.y || 0}\n\n¿Confirmás la eliminación?`;
        title = '⚠️ ELIMINAR PUERTA';
    } else if (kind === 'market') {
        const o = m.objects && m.objects[idx];
        if (!o) return;
        msg = `SE ELIMINARÁ ESTE MERCADO:\n\n🛒 ${o.label || 'Mercado'}\nUbicación: X ${o.x || 0}, Y ${o.y || 0}\n\n¿Confirmás la eliminación?`;
        title = '⚠️ ELIMINAR MERCADO';
    } else if (kind === 'ambience') {
        const a = m.ambience && m.ambience[idx];
        if (!a) return;
        const lib = AMBIENCE_LIB[a.type] || { label: a.type, icon: '🌍' };
        msg = `SE ELIMINARÁ ESTA MECÁNICA DE AMBIENTE:\n\n${lib.icon || ''} ${lib.label || a.type}\n\nEs una mecánica GLOBAL del mapa (afecta a toda la zona).\n\n¿Confirmás la eliminación?`;
        title = '⚠️ ELIMINAR MECÁNICA';
    } else {
        return;
    }

    const ok = await openConfirm(msg, title);
    if (!ok) return;

    if (kind === 'spawn') m.spawns.splice(idx, 1);
    else if (kind === 'door' || kind === 'market') m.objects.splice(idx, 1);
    else if (kind === 'ambience') m.ambience.splice(idx, 1);

    window._mapSelection = null;
    focusedRadarItem = null;
    window._highlightedMapObj = null;
    window._highlightedAmbienceIdx = null;
    renderMapDetail();
}

// ============================================================================
// MODALES DE AGREGADO (ENEMIGO / PUERTA / MECÁNICA DE AMBIENTE)
// ============================================================================

const AMBIENCE_FIELD_LABELS = {
    damage: "Daño (HP)", intervalMs: "Intervalo (ms)",
    spawnInterval: "Cadencia (ms)",
    duration: "Duración Efecto (ms)",
    radius: "Tamaño Vórtice (px)",
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
    penaltyFixed: "Penalización Curación Fija",
    visibility: "Visibilidad (%)",
    dashPenalty: "Penalización Dash (px/s)"
};

function defaultAmbienceField(f) {
    if (f === 'spawnInterval') return 15000;
    if (f === 'duration') return 5000;
    if (f === 'radius') return 300;
    if (f === 'shakeIntensity') return 10;
    if (f === 'staticIntensity') return 0.3;
    if (f === 'slowPercentage') return 30;
    if (f === 'damage') return 10;
    if (f === 'intervalMs') return 500;
    if (f === 'multiplier') return 2;
    if (f === 'penaltyPercentage') return 50;
    if (f === 'visibility') return 100;
    if (f === 'dashPenalty') return 30;
    return 0;
}

// ========== POLYGON SPAWN ZONE HELPERS ==========
function parsePolygonString(str) {
    if (!str || !str.trim()) return null;
    const lines = str.trim().split('\n');
    const points = [];
    for (const line of lines) {
        const parts = line.trim().split(',');
        if (parts.length >= 2) {
            const x = parseFloat(parts[0].trim());
            const y = parseFloat(parts[1].trim());
            if (!isNaN(x) && !isNaN(y)) {
                points.push({ x, y });
            }
        }
    }
    return points.length >= 3 ? points : null;
}

function formatPolygon(polygon) {
    if (!polygon || !polygon.length) return '';
    return polygon.map(p => `${Math.round(p.x)},${Math.round(p.y)}`).join('\n');
}

function parsePolygonInput(value, idx) {
    const m = config.mapsConfig[selectedMapId];
    if (!m || !m.spawns[idx]) return;
    const polygon = parsePolygonString(value);
    if (polygon) {
        m.spawns[idx].polygon = polygon;
        // Actualizar centroide
        const cx = polygon.reduce((a,p)=>a+p.x,0)/polygon.length;
        const cy = polygon.reduce((a,p)=>a+p.y,0)/polygon.length;
        m.spawns[idx].x = Math.round(cx);
        m.spawns[idx].y = Math.round(cy);
    }
}

function clearPolygon(idx) {
    const m = config.mapsConfig[selectedMapId];
    if (!m || !m.spawns[idx]) return;
    m.spawns[idx].polygon = [];
    const ta = document.getElementById(`spawn-polygon-${idx}`);
    if (ta) ta.value = '';
    renderMapDetail();
}

// ========== MODO DIBUJO DE POLÍGONO (ENFOQUE SIMPLE) ==========
// Cuando el usuario quiere dibujar, cerramos el modal completamente,
// dibujamos sobre el radar, y al guardar/cancelar volvemos a abrir el modal.

let polygonDrawMode = false;
let polygonDrawTargetIdx = -1; // -1 = nuevo spawn, >=0 = editando existente
let polygonDrawPoints = [];
let drawToolbar = null; // Referencia al toolbar de controles

// ===== Toolbar de controles fija durante el dibujo =====
function createDrawToolbar() {
    // Remover toolbar anterior si existe
    if (drawToolbar) {
        drawToolbar.remove();
        drawToolbar = null;
    }
    
    const toolbar = document.createElement('div');
    toolbar.id = 'polygon-draw-toolbar';
    toolbar.style.cssText = `
        position: fixed;
        bottom: 20px;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(0,0,0,0.7);
        border: 1px solid rgba(255,255,255,0.2);
        border-radius: 8px;
        padding: 8px 16px;
        z-index: 99998;
        font-family: 'Outfit', sans-serif;
        display: flex;
        gap: 12px;
        color: #fff;
        box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    `;
    
    const btnCancel = document.createElement('button');
    btnCancel.innerText = '❌ Cancelar';
    btnCancel.style.cssText = `
        background: #ff5f57;
        border: none;
        color: white;
        padding: 6px 14px;
        border-radius: 4px;
        font-size: 0.75rem;
        cursor: pointer;
        min-width: 80px;
    `;
    btnCancel.onmouseover = () => btnCancel.style.background = '#ff6b6b';
    btnCancel.onmouseout = () => btnCancel.style.background = '#ff5f57';
    btnCancel.onclick = cancelPolygonDraw;
    
    const btnGuardar = document.createElement('button');
    btnGuardar.innerText = '✅ Guardar';
    btnGuardar.style.cssText = `
        background: #10b981;
        border: none;
        color: #0a0f1a;
        padding: 6px 14px;
        border-radius: 4px;
        font-size: 0.75rem;
        font-weight: bold;
        cursor: pointer;
        min-width: 80px;
    `;
    btnGuardar.onmouseover = () => btnGuardar.style.background = '#20c990';
    btnGuardar.onmouseout = () => btnGuardar.style.background = '#10b981';
    btnGuardar.onclick = finishPolygonDraw;
    
    toolbar.appendChild(btnCancel);
    toolbar.appendChild(btnGuardar);
    document.body.appendChild(toolbar);
    drawToolbar = toolbar;
}

function removeDrawToolbar() {
    if (drawToolbar) {
        drawToolbar.remove();
        drawToolbar = null;
    }
}

// ===== Iniciar modo dibujo =====
// Cierra el modal completamente y entra en modo dibujo sobre el radar
function startPolygonDraw(idx) {
    const overlay = document.getElementById('map-add-overlay');
    if (overlay) overlay.style.display = 'none';
    window._mapAddKind = null;
    
    const m = config.mapsConfig[selectedMapId];
    if (!m || !m.spawns || !m.spawns[idx]) {
        showToast('⚠️ Error: no se encontró el spawn para editar.');
        return;
    }
    
    polygonDrawMode = true;
    polygonDrawTargetIdx = idx;
    polygonDrawPoints = (m.spawns[idx].polygon || []).map(p => ({x: p.x, y: p.y}));
    
    createDrawToolbar();
    
    const canvas = document.getElementById('map-radar-canvas');
    if (canvas) {
        canvas.style.cursor = 'crosshair';
        canvas.title = 'Modo dibujo activo. Click para añadir vértice. ESC: cancelar.';
    }
}

// Para nuevo spawn (desde el botón "+ AÑADIR ESPECIE")
function startPolygonDrawForNew() {
    // No entrar a dibujar sin especie seleccionada: el spawn nuevo nace de ese dato
    const enemyId = document.getElementById('map-add-enemy-id')?.value;
    if (!enemyId) {
        showToast('⚠️ Seleccioná un tipo de enemigo primero.', 'ERROR', '⚠️');
        return;
    }
    const overlay = document.getElementById('map-add-overlay');
    if (overlay) overlay.style.display = 'none';
    window._mapAddKind = null;
    
    polygonDrawMode = true;
    polygonDrawTargetIdx = -1;
    polygonDrawPoints = [];
    
    createDrawToolbar();
    
    const canvas = document.getElementById('map-radar-canvas');
    if (canvas) {
        canvas.style.cursor = 'crosshair';
        canvas.title = 'Modo dibujo activo. Click para añadir vértice. ESC: cancelar.';
    }
}

// ===== Cancelar dibujo =====
function cancelPolygonDraw() {
    const wasEditing = polygonDrawTargetIdx >= 0; // Guardar ANTES de resetear
    polygonDrawMode = false;
    polygonDrawTargetIdx = -1;
    polygonDrawPoints = [];
    removeDrawToolbar();
    
    const canvas = document.getElementById('map-radar-canvas');
    if (canvas) {
        canvas.style.cursor = 'crosshair';
        canvas.title = '';
    }
    
    // Solo reabrir modal si era un spawn nuevo (no estaba editando uno existente)
    if (!wasEditing) {
        setTimeout(() => openMapAddModal('enemy'), 100);
    }
    showToast('❌ Dibujo cancelado.', 'OPERACIÓN CANCELADA', '✕');
}

// ===== Guardar polígono: agregar/editar spawn y volver al ecosistema =====
function finishPolygonDraw() {
    if (polygonDrawPoints.length < 3) {
        showToast('⚠️ Se necesitan al menos 3 vértices para un polígono válido.', 'ERROR', '⚠️');
        return false;
    }
    const savedVerts = polygonDrawPoints.length;
    
    const m = config.mapsConfig[selectedMapId];
    if (!m) return false;
    
    const targetIdx = polygonDrawTargetIdx;
    const pts = polygonDrawPoints.map(p => ({x: p.x, y: p.y}));
    const cx = pts.reduce((a,p) => a + p.x, 0) / pts.length;
    const cy = pts.reduce((a,p) => a + p.y, 0) / pts.length;
    let newIdx = -1;
    
    if (targetIdx >= 0) {
        // Editando spawn existente → convertirlo a zona polígono (aparición random dentro)
        if (!m.spawns[targetIdx]) return false;
        m.spawns[targetIdx].polygon = pts;
        m.spawns[targetIdx].spawnMode = 'polygon';
        m.spawns[targetIdx].radius = 0;
        m.spawns[targetIdx].x = Math.round(cx);
        m.spawns[targetIdx].y = Math.round(cy);
        newIdx = targetIdx;
    } else {
        // Nuevo spawn: especie que aparece random dentro del polígono dibujado,
        // respetando cantidad de slots e intervalo de respawn del formulario
        const enemyId = document.getElementById('map-add-enemy-id')?.value;
        if (!enemyId) {
            showToast('⚠️ Seleccioná un tipo de enemigo primero.', 'ERROR', '⚠️');
            return false;
        }
        if (!m.spawns) m.spawns = [];
        m.spawns.push({
            id: 'spawn_' + Date.now() + Math.floor(Math.random() * 1000),
            type: enemyId,
            count: parseInt(document.getElementById('map-add-count')?.value) || 5,
            intervalMs: parseInt(document.getElementById('map-add-interval')?.value) || 5000,
            spawnMode: 'polygon',
            x: Math.round(cx),
            y: Math.round(cy),
            radius: parseInt(document.getElementById('map-add-radius')?.value) || 300,
            polygon: pts
        });
        newIdx = m.spawns.length - 1;
        window._mapCardExpanded[`spawn-${newIdx}`] = true;
    }
    
    // Hecho: salir del modo dibujo, cerrar el modal y mostrar el ECOSISTEMA
    // con la especie recién agregada/editada seleccionada
    removeDrawToolbar();
    polygonDrawMode = false;
    polygonDrawTargetIdx = -1;
    polygonDrawPoints = [];
    
    const canvas = document.getElementById('map-radar-canvas');
    if (canvas) {
        canvas.style.cursor = 'crosshair';
        canvas.title = '';
    }
    
    closeMapAddModal();
    renderMapDetail();
    selectMapItem('spawn', newIdx);
    showToast('✅ Polígono guardado con ' + savedVerts + ' vértices.');
    return true;
}

// ===== Teclado: ESC para cancelar, Enter para guardar =====
window.addEventListener('keydown', (e) => {
    if (!polygonDrawMode) return;
    
    if (e.key === 'Escape') {
        e.preventDefault();
        cancelPolygonDraw();
    } else if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        finishPolygonDraw();
    }
});

// Point-in-polygon test (ray casting)
function pointInPolygon(px, py, polygon) {
    if (!polygon || polygon.length < 3) return false;
    let inside = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        const xi = polygon[i].x, yi = polygon[i].y;
        const xj = polygon[j].x, yj = polygon[j].y;
        const intersect = ((yi > py) !== (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
        if (intersect) inside = !inside;
    }
    return inside;
}

// Distancia punto a segmento
function distPointToSegment(px, py, x1, y1, x2, y2) {
    const dx = x2 - x1, dy = y2 - y1;
    const len2 = dx*dx + dy*dy;
    if (len2 === 0) return Math.hypot(px - x1, py - y1);
    let t = ((px - x1) * dx + (py - y1) * dy) / len2;
    t = Math.max(0, Math.min(1, t));
    const projX = x1 + t * dx, projY = y1 + t * dy;
    return Math.hypot(px - projX, py - projY);
}

function mapAddRadarPos() {
    const rx = parseInt(document.getElementById('map-radar-x')?.value);
    const ry = parseInt(document.getElementById('map-radar-y')?.value);
    return {
        x: !isNaN(rx) ? rx : 5000,
        y: !isNaN(ry) ? ry : 5000
    };
}

function openMapAddModal(kind) {
    const m = config.mapsConfig[selectedMapId];
    if (!m) return;
    window._mapAddKind = kind;
    const body = document.getElementById('map-add-modal-body');
    const title = document.getElementById('map-add-modal-title');
    const pos = mapAddRadarPos();

    if (kind === 'enemy') {
        title.innerText = '➕ AGREGAR ENEMIGO';
        body.innerHTML = `
            <div style="font-size:0.8rem; color:#64748b; margin-bottom:1.2rem; line-height:1.5;">Elegí la especie, el modo de aparición y dónde se ubicará. Podés hacer clic en el <strong style="color:var(--accent);">radar táctico</strong> para copiar las coordenadas automáticamente.</div>
            <div class="field" style="margin-bottom:1rem; overflow:visible;">
                <label>👾 TIPO DE ENEMIGO</label>
                <input type="hidden" id="map-add-enemy-id" value="">
                ${renderSearchableEnemySelect('', (newId) => { document.getElementById('map-add-enemy-id').value = newId; }, 'var(--success)', 'map-add-enemy')}
            </div>
            <div class="field" style="margin-bottom:1rem;">
                <label>MODO DE APARICIÓN</label>
                <select id="map-add-spawn-mode" onchange="toggleMapAddSpawnMode(this.value)">
                    <option value="random_global">🌍 Aleatorio (En todo el mapa)</option>
                    <option value="random_zone" selected>⭕ Aleatorio en un área (Centro + Radio)</option>
                    <option value="polygon">📐 Zona Personalizada (Polígono)</option>
                    <option value="fixed">📍 Fijo (Coordenadas Exactas)</option>
                </select>
            </div>
            <div class="form-grid" style="display:grid; grid-template-columns:1fr 1fr; gap:12px;">
                <div class="field"><label>Cant. Máx (slots)</label><input type="number" id="map-add-count" value="5"></div>
                <div class="field"><label>Intervalo Respawn (ms)</label><input type="number" id="map-add-interval" value="5000"></div>
            </div>
            <div id="map-add-pos-fields" style="display:grid; grid-template-columns:1fr 1fr; gap:12px; margin-top:12px;">
                <div class="field"><label>Coordenada X</label><input type="number" id="map-add-x" value="${pos.x}"></div>
                <div class="field"><label>Coordenada Y</label><input type="number" id="map-add-y" value="${pos.y}"></div>
            </div>
            <div id="map-add-radius-field" class="field" style="margin-top:12px;"><label>Radio de Área de Spawn (px)</label><input type="number" id="map-add-radius" value="300"></div>
            <div id="map-add-polygon-field" class="field" style="margin-top:12px; display:none;">
                <label>Vértices del Polígono (X,Y por línea)</label>
                <textarea id="map-add-polygon" style="width:100%; height:80px; background:#0a0f1a; border:1px solid rgba(16,185,129,0.3); border-radius:4px; color:#10b981; font-family:monospace; font-size:0.7rem; padding:6px; resize:vertical;" placeholder="Ej: 1000,2000&#10;1500,2000&#10;1500,2500&#10;1000,2500"></textarea>
                <div style="font-size:0.6rem; color:#64748b; margin-top:4px; display:flex; gap:8px; flex-wrap:wrap;">
                    <button class="btn btn-secondary" style="padding:2px 8px; font-size:0.6rem;" onclick="startPolygonDrawForNew()">✏️ Dibujar en Radar</button>
                    <button class="btn btn-secondary" style="padding:2px 8px; font-size:0.6rem;" onclick="document.getElementById('map-add-polygon').value=''">🗑️ Limpiar</button>
                </div>
            </div>
        `;
    } else if (kind === 'door') {
        title.innerText = '➕ AGREGAR PUERTA / WARP';
        const zoneOptions = Object.keys(config.mapsConfig)
            .filter(id => id !== selectedMapId && config.mapsConfig[id].visible !== false)
            .map(id => `<option value="${id}">${config.mapsConfig[id].name} (ID: ${id})</option>`)
            .join('');
        body.innerHTML = `
            <div style="font-size:0.8rem; color:#64748b; margin-bottom:1.2rem; line-height:1.5;">Configurá la puerta y su warp de destino. Podés hacer clic en el <strong style="color:var(--accent);">radar táctico</strong> para copiar las coordenadas automáticamente.</div>
            <div class="field" style="margin-bottom:1rem;"><label>🚪 ETIQUETA</label><input type="text" id="map-add-door-label" value="Puerta" placeholder="Nombre de la puerta"></div>
            <div class="form-grid" style="display:grid; grid-template-columns:1fr 1fr; gap:12px;">
                <div class="field"><label>Pos X</label><input type="number" id="map-add-x" value="${pos.x}"></div>
                <div class="field"><label>Pos Y</label><input type="number" id="map-add-y" value="${pos.y}"></div>
            </div>
            <div class="field" style="margin-top:12px;"><label>Zona Destino (Warp)</label><select id="map-add-door-zone"><option value="">-- Seleccionar Zona --</option>${zoneOptions}</select></div>
            <div class="form-grid" style="display:grid; grid-template-columns:1fr 1fr; gap:12px; margin-top:12px;">
                <div class="field"><label>Warp X destino</label><input type="number" id="map-add-door-tx" value="5000"></div>
                <div class="field"><label>Warp Y destino</label><input type="number" id="map-add-door-ty" value="5000"></div>
            </div>
        `;
    } else if (kind === 'market') {
        title.innerText = '➕ AGREGAR TERMINAL DE MERCADO';
        body.innerHTML = `
            <div style="font-size:0.8rem; color:#ffd700; margin-bottom:1.2rem; line-height:1.5;">Configurá una terminal interactiva para la Casa de Subastas. Los jugadores podrán interactuar con ella en el juego haciendo doble clic. Podés hacer clic en el <strong style="color:var(--accent);">radar táctico</strong> para copiar las coordenadas automáticamente.</div>
            <div class="field" style="margin-bottom:1rem;"><label>🛒 ETIQUETA / NOMBRE</label><input type="text" id="map-add-market-label" value="Mercado" placeholder="Nombre de la terminal"></div>
            <div class="form-grid" style="display:grid; grid-template-columns:1fr 1fr; gap:12px;">
                <div class="field"><label>Pos X</label><input type="number" id="map-add-x" value="${pos.x}"></div>
                <div class="field"><label>Pos Y</label><input type="number" id="map-add-y" value="${pos.y}"></div>
            </div>
            <div class="field" style="margin-top:12px;"><label>Asset (ruta .glb de Godot)</label>
                <input type="text" id="map-add-market-asset" value="res://assets/Mapas/Mapa1/Estructuras/3D/Decorativo3/Decorativo3.glb" placeholder="Ruta del asset .glb">
            </div>
            <div class="field" style="margin-top:12px;"><label>Altura Y Offset</label><input type="number" step="0.1" id="map-add-market-yoffset" value="0.0"></div>
        `;
    } else if (kind === 'ambience') {
        title.innerText = '➕ AGREGAR MECÁNICA DE AMBIENTE';
        const typeOptions = Object.keys(AMBIENCE_LIB).map(t => `<option value="${t}">${AMBIENCE_LIB[t].icon || '🌍'} ${AMBIENCE_LIB[t].label}</option>`).join('');
        body.innerHTML = `
            <div style="font-size:0.8rem; color:#64748b; margin-bottom:1.2rem; line-height:1.5;">Las mecánicas de ambiente afectan a <strong>TODO el mapa</strong> (no tienen posición). Elegí el tipo y ajustá sus parámetros.</div>
            <div class="field" style="margin-bottom:1rem;">
                <label>☢️ TIPO DE MECÁNICA</label>
                <select id="map-add-amb-type" onchange="refreshMapAddAmbFields(this.value)">${typeOptions}</select>
            </div>
            <div id="map-add-amb-fields"></div>
        `;
        refreshMapAddAmbFields('radiation');
    }

    document.getElementById('map-add-overlay').style.display = 'flex';
}

function closeMapAddModal() {
    document.getElementById('map-add-overlay').style.display = 'none';
    window._mapAddKind = null;
}

function toggleMapAddSpawnMode(mode) {
    const pos = document.getElementById('map-add-pos-fields');
    const rad = document.getElementById('map-add-radius-field');
    const poly = document.getElementById('map-add-polygon-field');
    if (pos) pos.style.display = (mode === 'random_global' || mode === 'polygon') ? 'none' : 'grid';
    if (rad) rad.style.display = (mode === 'random_zone') ? 'block' : 'none';
    if (poly) poly.style.display = (mode === 'polygon') ? 'block' : 'none';
}

function refreshMapAddAmbFields(type) {
    const container = document.getElementById('map-add-amb-fields');
    if (!container) return;
    const lib = AMBIENCE_LIB[type];
    if (!lib) { container.innerHTML = ''; return; }
    container.innerHTML = `
        <div style="font-size:0.7rem; color:#888; margin-bottom:0.8rem;">${lib.desc || ''}</div>
        <div class="form-grid" style="display:grid; grid-template-columns:1fr 1fr; gap:12px;">
            ${lib.fields.map(f => `
                <div class="field">
                    <label>${AMBIENCE_FIELD_LABELS[f] || f}</label>
                    <input type="number" step="0.1" id="map-add-amb-${f}" value="${defaultAmbienceField(f)}">
                </div>
            `).join('')}
        </div>
    `;
}

function confirmMapAdd() {
    const kind = window._mapAddKind;
    const m = config.mapsConfig[selectedMapId];
    if (!m || !kind) return;
    let newIdx = -1;

    if (kind === 'enemy') {
        const type = document.getElementById('map-add-enemy-id').value;
        if (!type) { showToast('⚠️ Seleccioná un tipo de enemigo primero.'); return; }
        const mode = document.getElementById('map-add-spawn-mode').value;
        if (!m.spawns) m.spawns = [];
        const spawnData = {
            id: 'spawn_' + Date.now() + Math.floor(Math.random() * 1000),
            type: type,
            count: parseInt(document.getElementById('map-add-count').value) || 5,
            intervalMs: parseInt(document.getElementById('map-add-interval').value) || 5000,
            spawnMode: mode === 'fixed' ? 'fixed' : (mode === 'polygon' ? 'polygon' : 'random'),
            x: parseInt(document.getElementById('map-add-x').value) || 0,
            y: parseInt(document.getElementById('map-add-y').value) || 0,
            radius: mode === 'random_global' ? 0 : (parseInt(document.getElementById('map-add-radius').value) || 300)
        };
        if (mode === 'polygon') {
            spawnData.polygon = parsePolygonString(document.getElementById('map-add-polygon').value);
            if (!spawnData.polygon || spawnData.polygon.length < 3) {
                showToast('⚠️ Un polígono necesita al menos 3 vértices. Dibujá en el radar o ingresá coordenadas.', 'ERROR', '⚠️');
                return;
            }
            // Calcular centroide para referencia
            const cx = spawnData.polygon.reduce((a,p)=>a+p.x,0)/spawnData.polygon.length;
            const cy = spawnData.polygon.reduce((a,p)=>a+p.y,0)/spawnData.polygon.length;
            spawnData.x = Math.round(cx);
            spawnData.y = Math.round(cy);
        }
        m.spawns.push(spawnData);
        newIdx = m.spawns.length - 1;
        window._mapCardExpanded[`spawn-${newIdx}`] = true;
    } else if (kind === 'door') {
        if (!m.objects) m.objects = [];
        m.objects.push({
            type: 'door',
            label: document.getElementById('map-add-door-label').value || 'Puerta',
            x: parseInt(document.getElementById('map-add-x').value) || 0,
            y: parseInt(document.getElementById('map-add-y').value) || 0,
            assetPath: 'res://assets/Puertas/3D/Puerta2/Puerta2.glb',
            targetZoneId: document.getElementById('map-add-door-zone').value,
            targetX: parseInt(document.getElementById('map-add-door-tx').value) || 5000,
            targetY: parseInt(document.getElementById('map-add-door-ty').value) || 5000,
            scale: 1.0,
            rotY: 0,
            yOffset: 2.5
        });
        newIdx = m.objects.length - 1;
        window._mapCardExpanded[`door-${newIdx}`] = true;
    } else if (kind === 'market') {
        if (!m.objects) m.objects = [];
        m.objects.push({
            type: 'market',
            label: document.getElementById('map-add-market-label').value || 'Mercado',
            x: parseInt(document.getElementById('map-add-x').value) || 0,
            y: parseInt(document.getElementById('map-add-y').value) || 0,
            assetPath: document.getElementById('map-add-market-asset').value || 'res://assets/Mapas/Mapa1/Estructuras/3D/Decorativo3/Decorativo3.glb',
            scale: 2.0,
            rotY: 0,
            yOffset: parseFloat(document.getElementById('map-add-market-yoffset').value) || 0.0
        });
        newIdx = m.objects.length - 1;
        window._mapCardExpanded[`market-${newIdx}`] = true;
    } else if (kind === 'ambience') {
        const type = document.getElementById('map-add-amb-type').value;
        if (!m.ambience) m.ambience = [];
        const hazard = { type: type };
        const lib = AMBIENCE_LIB[type];
        if (lib) {
            lib.fields.forEach(f => {
                const inp = document.getElementById(`map-add-amb-${f}`);
                hazard[f] = inp ? (parseFloat(inp.value) || 0) : defaultAmbienceField(f);
            });
        }
        m.ambience.push(hazard);
        newIdx = m.ambience.length - 1;
        window._mapCardExpanded[`amb-${newIdx}`] = true;
    }

    closeMapAddModal();
    renderMapDetail();
    if (newIdx >= 0) selectMapItem(kind === 'enemy' ? 'spawn' : kind, newIdx);
}

// Duplicar un ítem del mapa (Ctrl+D o botón ⧉ de la tarjeta)
function duplicateMapItem(kind, idx) {
    const m = config.mapsConfig[selectedMapId];
    if (!m) return;
    let newIdx = -1;

    if (kind === 'spawn') {
        const s = m.spawns && m.spawns[idx];
        if (!s) return;
        if (!m.spawns) m.spawns = [];
        const clone = JSON.parse(JSON.stringify(s));
        clone.id = 'spawn_' + Date.now() + Math.floor(Math.random() * 1000);
        m.spawns.push(clone);
        newIdx = m.spawns.length - 1;
        window._mapCardExpanded[`spawn-${newIdx}`] = true;
    } else if (kind === 'door') {
        const o = m.objects && m.objects[idx];
        if (!o) return;
        if (!m.objects) m.objects = [];
        m.objects.push(JSON.parse(JSON.stringify(o)));
        newIdx = m.objects.length - 1;
        window._mapCardExpanded[`door-${newIdx}`] = true;
    } else if (kind === 'market') {
        const o = m.objects && m.objects[idx];
        if (!o) return;
        if (!m.objects) m.objects = [];
        m.objects.push(JSON.parse(JSON.stringify(o)));
        newIdx = m.objects.length - 1;
        window._mapCardExpanded[`market-${newIdx}`] = true;
    } else if (kind === 'ambience') {
        const a = m.ambience && m.ambience[idx];
        if (!a) return;
        if (!m.ambience) m.ambience = [];
        m.ambience.push(JSON.parse(JSON.stringify(a)));
        newIdx = m.ambience.length - 1;
        window._mapCardExpanded[`amb-${newIdx}`] = true;
    } else {
        return;
    }

    renderMapDetail();
    if (newIdx >= 0) {
        selectMapItem(kind, newIdx);
    }
}

// ============================================================================
// TECLADO GLOBAL: SUPR para eliminar lo seleccionado en Cartografía + ESC para cerrar modales
// ============================================================================

function handleGlobalKeydown(e) {
    if (e.key === 'Escape') {
        // Modales de Talentos y Esferas
        const skillParamOverlay = document.getElementById('skill-param-picker-overlay');
        if (skillParamOverlay) { if (typeof closeSkillParamPickerModal === 'function') closeSkillParamPickerModal(); else skillParamOverlay.remove(); return; }

        const effectPickerOverlay = document.getElementById('effect-picker-overlay');
        if (effectPickerOverlay) { if (typeof closeEffectPickerModal === 'function') closeEffectPickerModal(); else effectPickerOverlay.remove(); return; }

        const sphereStatModal = document.getElementById('sphere-stat-picker-modal');
        if (sphereStatModal && sphereStatModal.style.display === 'flex') { if (typeof closeSphereStatPickerModal === 'function') closeSphereStatPickerModal(); else sphereStatModal.style.display = 'none'; return; }

        const talentCreateModal = document.getElementById('talent-create-modal');
        if (talentCreateModal && talentCreateModal.style.display === 'flex') { if (typeof closeTalentModal === 'function') closeTalentModal(); else talentCreateModal.style.display = 'none'; return; }

        const talentCatModal = document.getElementById('talent-categories-modal');
        if (talentCatModal && talentCatModal.style.display === 'flex') { if (typeof closeTalentCategoriesModal === 'function') closeTalentCategoriesModal(); else talentCatModal.style.display = 'none'; return; }

        // Modales existentes
        const addOverlay = document.getElementById('map-add-overlay');
        if (addOverlay && addOverlay.style.display === 'flex') { closeMapAddModal(); return; }
        const confirmOverlay = document.getElementById('confirm-overlay');
        if (confirmOverlay && confirmOverlay.style.display === 'flex') { closeConfirm(false); return; }
        const threatOverlay = document.getElementById('threat-add-overlay');
        if (threatOverlay && threatOverlay.style.display === 'flex') { closeThreatAddModal(); return; }
        return;
    }

    if (e.key !== 'Delete' && e.key !== 'Backspace' && !((e.ctrlKey || e.metaKey) && (e.key === 'd' || e.key === 'D'))) return;

    const view = document.getElementById('view-map-detail');
    if (!view || !view.classList.contains('active')) return;

    const t = document.activeElement;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)) return;

    e.preventDefault();

    // Ctrl+D: duplicar el ítem seleccionado de Cartografía
    if ((e.ctrlKey || e.metaKey) && (e.key === 'd' || e.key === 'D')) {
        const addOverlay = document.getElementById('map-add-overlay');
        if (addOverlay && addOverlay.style.display === 'flex') return;
        const confirmOverlay = document.getElementById('confirm-overlay');
        if (confirmOverlay && confirmOverlay.style.display === 'flex') return;
        const sel = window._mapSelection;
        if (!sel) {
            showToast('⚠️ Seleccioná primero un enemigo, puerta o mecánica para duplicarla (clic en el radar o en la lista).');
            return;
        }
        duplicateMapItem(sel.kind, sel.index);
        return;
    }

    const sel = window._mapSelection;
    if (!sel) {
        showToast('⚠️ Seleccioná primero un enemigo, puerta o mecánica (clic en el radar o en la lista).');
        return;
    }
    requestMapDelete(sel.kind, sel.index);
}

window.addEventListener('keydown', handleGlobalKeydown);

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

function patchMechanicsLib() {
    if (!config) return;

    if (!config.housingConfig) {
        config.housingConfig = JSON.parse(JSON.stringify(DEFAULT_HOUSING_CONFIG));
    }

    if (!config.talentsConfig) {
        config.talentsConfig = {
            talents: [],
            nodes: {},
            connections: [],
            categories: JSON.parse(JSON.stringify(DEFAULT_CATEGORIES))
        };
    }

    if (!config.talentsConfig.categories || !Array.isArray(config.talentsConfig.categories) || config.talentsConfig.categories.length === 0) {
        config.talentsConfig.categories = JSON.parse(JSON.stringify(DEFAULT_CATEGORIES));
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
                        if (s.spawnMode === 'random_global') {
                            s.spawnMode = 'random';
                            s.radius = 0;
                        } else if (s.spawnMode === 'random_zone') {
                            s.spawnMode = 'random';
                            if (!s.radius || s.radius === 0) s.radius = 300;
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
                    // v900.0: migrar sonido (hybrid: default de libreria)
                    if (config[item.configKey][type].sound === undefined) config[item.configKey][type].sound = item.base[type].sound || "";
                    if (config[item.configKey][type].soundVolumePercent === undefined) config[item.configKey][type].soundVolumePercent = item.base[type].soundVolumePercent || 50;
                    if (config[item.configKey][type].soundMaxDist === undefined) config[item.configKey][type].soundMaxDist = item.base[type].soundMaxDist || 1200;
                }
            }
        }
    });
    // v900.0: migrar sonido de skills
    if (config.skillsData) {
        for (let sn in config.skillsData) {
            const sd = config.skillsData[sn];
            if (sd.sound === undefined) sd.sound = "";
            if (sd.soundVolumePercent === undefined) sd.soundVolumePercent = sd.soundVolume !== undefined ? sd.soundVolume : 50;
            if (sd.soundMaxDist === undefined) sd.soundMaxDist = 1400;
        }
    }

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
    window.config = config;

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
        if (!ml.fields.includes("beamWidth")) ml.fields.push("beamWidth");
    }
    if (config.mechanicsLib && config.mechanicsLib.ice_storm) {
        if (!config.mechanicsLib.ice_storm.fields.includes("slowDuration")) {
            const idx = config.mechanicsLib.ice_storm.fields.indexOf("slowIsPercentage");
            if (idx !== -1) config.mechanicsLib.ice_storm.fields.splice(idx + 1, 0, "slowDuration");
            else config.mechanicsLib.ice_storm.fields.push("slowDuration");
        }
    }
    if (config.enemyModels) {
        for (const eid in config.enemyModels) {
            const mechs = config.enemyModels[eid].mechanics || [];
            for (const m of mechs) {
                if (m.type === 'mega_laser' && (m.beamWidth === undefined || m.beamWidth === null)) {
                    m.beamWidth = 40;
                }
                if (m.type === 'ice_storm' && (m.slowDuration === undefined || m.slowDuration === null)) {
                    m.slowDuration = 2000;
                }
            }
        }
    }
    if (config.skillsData && config.skillsData["VÍNCULO VITAL"]) {
        const s = config.skillsData["VÍNCULO VITAL"];
        if (s.breakRange === undefined) s.breakRange = 500;
        if (s.tickInterval === undefined) s.tickInterval = 1000;
    }
    renderAll();
}

function showToast(msg, title = 'OPERACIÓN EXITOSA', icon = '✓') {
    document.getElementById('toast-msg').innerText = msg;
    const t = document.getElementById('toast-title');
    if (t) t.innerText = title;
    const i = document.getElementById('toast-icon');
    if (i) i.innerText = icon;
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
        window._confirmResolve = resolve;
        document.getElementById('confirm-title').innerText = title;
        document.getElementById('confirm-msg').innerText = msg;
        document.getElementById('confirm-overlay').style.display = 'flex';

        const okBtn = document.getElementById('confirm-ok-btn');
        const newOkBtn = okBtn.cloneNode(true); // Limpiar listeners viejos
        okBtn.parentNode.replaceChild(newOkBtn, okBtn);

        newOkBtn.onclick = () => {
            document.getElementById('confirm-overlay').style.display = 'none';
            const r = window._confirmResolve;
            window._confirmResolve = null;
            if (r) r(true);
        };
    });
}

function closeConfirm(val) {
    document.getElementById('confirm-overlay').style.display = 'none';
    const r = window._confirmResolve;
    window._confirmResolve = null;
    if (r) r(!!val);
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

    // Actualizar visual de botones (Defensa del Altar) - v770.4: solo spawn/spawner (altar y portales en 3D)
    const btnAdSpawn = document.getElementById('btn-radar-ad-spawn');
    const btnAdSpawner = document.getElementById('btn-radar-ad-spawner');

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

    const modeText = document.getElementById('radar-mode-text');
    if (modeText) modeText.innerText = mode === 'spawner' ? 'SPAWNER' : (mode === 'spawn' ? 'SPAWN' : 'ESCAPE');

    // Toggle options display
    if (document.getElementById('radar-spawner-opts')) document.getElementById('radar-spawner-opts').style.display = mode === 'spawner' ? 'block' : 'none';
    if (document.getElementById('radar-extract-opts')) document.getElementById('radar-extract-opts').style.display = mode === 'extract' ? 'block' : 'none';
    if (document.getElementById('radar-spawn-opts')) document.getElementById('radar-spawn-opts').style.display = mode === 'spawn' ? 'block' : 'none';

    if (document.getElementById('radar-ad-spawn-opts')) document.getElementById('radar-ad-spawn-opts').style.display = mode === 'ad-spawn' ? 'block' : 'none';
    if (document.getElementById('radar-ad-spawner-opts')) document.getElementById('radar-ad-spawner-opts').style.display = mode === 'ad-spawner' ? 'block' : 'none';
}

function highlightCard(type, index) {
    focusedRadarItem = { type, index };
    // Limpiar resaltados anteriores de cualquier tipo
    document.querySelectorAll('[id^="card-spawn-"], [id^="card-extract-"], [id^="card-spawner-"], [id^="card-ad-spawn-"], [id^="card-ad-spawner-"], [id^="card-map-spawn-"]').forEach(el => {
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
    }
}

function initRadar() {
    const canvas = document.getElementById('radar-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const container = document.getElementById('radar-container');

    const isAltarDefense = (currentModeTab === 'altar_defense');
    const modeData = isAltarDefense ? config.gameModes.altar_defense : config.gameModes.extraction;

    // Fondo del mapa: ya no se usa mixboard-image (eliminada). Se deja fondo negro sólido.
    const bgImage = new Image();
    bgImage.src = ''; // sin textura - draw() usará fillRect '#000'

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

            // 1. Spawn Points (Altar y Portales ahora en 3D, no en radar)
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

            // 2. Spawners - v770.12: solo visual, edición exclusiva Editor 3D Puerta3
            const spawners = ad.spawners || [];
            for (let i = 0; i < spawners.length; i++) {
                const pos = worldToCanvas(spawners[i].x, spawners[i].y);
                const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
                if (dist < 15) {
                    highlightCard('ad-spawner', i);
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
            if (dragItem.type === 'ad-spawn') {
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

            // v770.4: Altar ahora en 3D (mapsConfig.objects), no en radar AdminDash
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

            // v770.4: Puertas de escape ahora en 3D (mapsConfig.objects), no en radar AdminDash
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
        if (radarMode === 'ad-spawn') {
            if (!ad.spawnPoints) ad.spawnPoints = [];
            ad.spawnPoints.push({
                x, y,
                label: document.getElementById('radar-ad-spawn-label').value,
                radius: parseInt(document.getElementById('radar-ad-spawn-radius').value || 200)
            });
        } else if (radarMode === 'ad-spawner') {
            // v770.12: Deshabilitado - spawners ahora exclusivos Editor 3D Puerta3
            alert('Los spawners de Defensa del Altar ahora se gestionan exclusivamente desde el Editor 3D (res://tools/MapEditor3D_Evento_2_Defensa_Altar.tscn) usando objetos tipo spawner (Puerta3).');
            return;
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
    config.enemyModels[enemyId].lootDrops.push({ itemId: "", chance: 0.1, amount: 1 });
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

function updateLootDropAmount(enemyId, idx, amount) {
    if (!config.enemyModels[enemyId] || !config.enemyModels[enemyId].lootDrops) return;
    config.enemyModels[enemyId].lootDrops[idx].amount = Math.max(1, parseInt(amount) || 1);
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

function updateLootDropAmountFromLootConfig(enemyId, idx, amount) {
    updateLootDropAmount(enemyId, idx, amount);
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

function updateLootDropAmountFromEnemyLoot(enemyId, idx, amount) {
    updateLootDropAmount(enemyId, idx, amount);
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

    // Estado persistente de Zoom y Panning por zona
    if (!window._mapRadarState) window._mapRadarState = {};
    if (!window._mapRadarState[selectedMapId]) {
        window._mapRadarState[selectedMapId] = { zoom: 1.0, pan: { x: 0, y: 0 } };
    }
    const radarState = window._mapRadarState[selectedMapId];

    // Estados de interacción
    let isDragging = false;
    let dragItem = null;
    let isPanning = false;
    let panStart = { x: 0, y: 0 };

    const updateZoomBadge = () => {
        const badge = document.getElementById('radar-zoom-badge');
        if (badge) {
            badge.innerText = Math.round(radarState.zoom * 100) + '%';
        }
    };
    updateZoomBadge();

    // Función para limitar zoom entre 100% y 500% y restringir paneo dentro del mapa
    const clampPanAndZoom = () => {
        radarState.zoom = Math.min(Math.max(1.0, radarState.zoom), 5.0);
        if (radarState.zoom <= 1.0) {
            radarState.pan.x = 0;
            radarState.pan.y = 0;
        } else {
            const minPanX = canvas.width * (1 - radarState.zoom);
            const maxPanX = 0;
            radarState.pan.x = Math.min(maxPanX, Math.max(minPanX, radarState.pan.x));

            const minPanY = canvas.height * (1 - radarState.zoom);
            const maxPanY = 0;
            radarState.pan.y = Math.min(maxPanY, Math.max(minPanY, radarState.pan.y));
        }
    };

    // Controles globales accesibles por botones en la UI (Mínimo 100%, Máximo 500%)
    window.zoomRadarIn = () => {
        const cx = canvas.width / 2;
        const cy = canvas.height / 2;
        const oldZoom = radarState.zoom;
        const newZoom = Math.min(5.0, oldZoom * 1.25);
        radarState.pan.x = cx - (cx - radarState.pan.x) * (newZoom / oldZoom);
        radarState.pan.y = cy - (cy - radarState.pan.y) * (newZoom / oldZoom);
        radarState.zoom = newZoom;
        clampPanAndZoom();
        updateZoomBadge();
    };

    window.zoomRadarOut = () => {
        const cx = canvas.width / 2;
        const cy = canvas.height / 2;
        const oldZoom = radarState.zoom;
        const newZoom = Math.max(1.0, oldZoom / 1.25);
        radarState.pan.x = cx - (cx - radarState.pan.x) * (newZoom / oldZoom);
        radarState.pan.y = cy - (cy - radarState.pan.y) * (newZoom / oldZoom);
        radarState.zoom = newZoom;
        clampPanAndZoom();
        updateZoomBadge();
    };

    window.resetRadarZoom = () => {
        radarState.zoom = 1.0;
        radarState.pan.x = 0;
        radarState.pan.y = 0;
        updateZoomBadge();
    };

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

    // Límites reales del terreno (sincronizados desde Godot o fallback)
    const minX = m.minX !== undefined ? Number(m.minX) : 0;
    const minY = m.minY !== undefined ? Number(m.minY) : 0;
    const worldW = (m.width && Number(m.width) > 0) ? Number(m.width) : 10000;
    const worldH = (m.height && Number(m.height) > 0) ? Number(m.height) : 10000;

    // Convertir de coordenadas de mundo a coordenadas de canvas respetando el origen minX, minY, zoom y pan
    const worldToCanvas = (wx, wy) => {
        const baseX = ((wx - minX) / worldW) * canvas.width;
        const baseY = ((wy - minY) / worldH) * canvas.height;
        return {
            x: (baseX * radarState.zoom) + radarState.pan.x,
            y: (baseY * radarState.zoom) + radarState.pan.y
        };
    };

    // Convertir de canvas a mundo respetando el origen minX, minY, zoom y pan
    const canvasToWorld = (cx, cy) => {
        const baseX = (cx - radarState.pan.x) / radarState.zoom;
        const baseY = (cy - radarState.pan.y) / radarState.zoom;
        return {
            wx: minX + (baseX / canvas.width) * worldW,
            wy: minY + (baseY / canvas.height) * worldH
        };
    };

    // Caché de imágenes de terreno del radar para rendimiento óptimo
    if (!window._radarTerrainImages) window._radarTerrainImages = {};
    const imgKey = 'zone_' + selectedMapId;
    let terrainImg = window._radarTerrainImages[imgKey];
    const expectedSrc = m.terrainImage || ('assets/maps/terrain_zone_' + selectedMapId + '.png');
    if (!terrainImg || terrainImg.datasetSrc !== expectedSrc) {
        terrainImg = new Image();
        terrainImg.datasetSrc = expectedSrc;
        terrainImg.src = expectedSrc;
        window._radarTerrainImages[imgKey] = terrainImg;
    }

    // Zoom con la rueda del mouse centrado en la posición del cursor (Mínimo 100%, Máximo 500%)
    canvas.onwheel = (e) => {
        e.preventDefault();
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        const zoomSpeed = 0.15;
        const zoomFactor = e.deltaY < 0 ? (1 + zoomSpeed) : (1 / (1 + zoomSpeed));
        const oldZoom = radarState.zoom;
        const newZoom = Math.min(Math.max(1.0, oldZoom * zoomFactor), 5.0);

        radarState.pan.x = mouseX - (mouseX - radarState.pan.x) * (newZoom / oldZoom);
        radarState.pan.y = mouseY - (mouseY - radarState.pan.y) * (newZoom / oldZoom);
        radarState.zoom = newZoom;

        clampPanAndZoom();
        updateZoomBadge();
    };

    // Evitar menú contextual para permitir paneo libre con clic derecho
    canvas.oncontextmenu = (e) => {
        e.preventDefault();
        return false;
    };

    canvas.onmousedown = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        // ===== MODO DIBUJO DE POLÍGONO =====
        if (polygonDrawMode) {
            if (e.button === 0) { // Click izquierdo: añadir vértice
                e.preventDefault();
                const world = canvasToWorld(mouseX, mouseY);
                polygonDrawPoints.push({ x: Math.round(world.wx), y: Math.round(world.wy) });
                // Actualizar preview en textarea si editando existente
                if (polygonDrawTargetIdx >= 0) {
                    const ta = document.getElementById(`spawn-polygon-${polygonDrawTargetIdx}`);
                    if (ta) ta.value = formatPolygon(polygonDrawPoints);
                } else {
                    const ta = document.getElementById('map-add-polygon');
                    if (ta) ta.value = formatPolygon(polygonDrawPoints);
                }
                renderMapDetail(); // Redibujar para mostrar preview
                return;
            } else if (e.button === 2) { // Click derecho: finalizar polígono
                e.preventDefault();
                finishPolygonDraw();
                return;
            }
        }

        // Si hay un modal de agregado abierto, copiar las coordenadas del clic al modal
        const addOverlay = document.getElementById('map-add-overlay');
        if (addOverlay && addOverlay.style.display === 'flex') {
            const world = canvasToWorld(mouseX, mouseY);
            const xi = document.getElementById('map-add-x');
            const yi = document.getElementById('map-add-y');
            if (xi) xi.value = Math.round(world.wx);
            if (yi) yi.value = Math.round(world.wy);
            document.getElementById('map-radar-x').value = Math.round(world.wx);
            document.getElementById('map-radar-y').value = Math.round(world.wy);
            return;
        }

        // ------ MODO MOVER: primero chequear objetos ------
        const objects = m.objects || [];
        for (let i = 0; i < objects.length; i++) {
            const obj = objects[i];
            const pos = worldToCanvas(obj.x || 0, obj.y || 0);
            if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 14) {
                isDragging = true;
                dragItem = { type: 'map-obj', index: i };
                canvas.style.cursor = 'grabbing';
                selectMapItem('door', i);
                return;
            }
        }

        // Buscar en Spawns de este mapa
        const spawns = m.spawns || [];
        for (let i = 0; i < spawns.length; i++) {
            const s = spawns[i];
            if (s.spawnMode === 'random' && (!s.radius || s.radius === 0) && (!s.polygon || s.polygon.length < 3)) continue;

            // Si es polígono, chequear vértices primero
            if (s.spawnMode === 'polygon' && s.polygon && s.polygon.length >= 3) {
                const polyPoints = s.polygon.map(p => worldToCanvas(p.x, p.y));
                for (let vi = 0; vi < polyPoints.length; vi++) {
                    const vp = polyPoints[vi];
                    if (Math.hypot(vp.x - mouseX, vp.y - mouseY) < 10) {
                        isDragging = true;
                        dragItem = { type: 'map-spawn-vertex', index: i, vertexIndex: vi };
                        canvas.style.cursor = 'grabbing';
                        selectMapItem('spawn', i);
                        return;
                    }
                }
            }

            const sx = s.x !== undefined ? s.x : 0;
            const sy = s.y !== undefined ? s.y : 0;
            const pos = worldToCanvas(sx, sy);
            const dist = Math.hypot(pos.x - mouseX, pos.y - mouseY);
            
            if (dist < 16) {
                isDragging = true;
                dragItem = { type: 'map-spawn', index: i };
                canvas.style.cursor = 'grabbing';
                selectMapItem('spawn', i);
                return;
            }
        }

        // Si no agarró ningún objeto ni spawn, capturar coordenadas del radar e iniciar paneo con clic izquierdo
        const world = canvasToWorld(mouseX, mouseY);
        const rxInput = document.getElementById('map-radar-x');
        const ryInput = document.getElementById('map-radar-y');
        if (rxInput) rxInput.value = Math.round(world.wx);
        if (ryInput) ryInput.value = Math.round(world.wy);

        isPanning = true;
        panStart = { x: e.clientX, y: e.clientY };
        canvas.style.cursor = 'grabbing';
    };

    window.onmousemove = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mouseX = Math.max(0, Math.min(canvas.width, e.clientX - rect.left));
        const mouseY = Math.max(0, Math.min(canvas.height, e.clientY - rect.top));
        const world = canvasToWorld(mouseX, mouseY);

        if (isPanning) {
            if (radarState.zoom > 1.0) {
                const dx = e.clientX - panStart.x;
                const dy = e.clientY - panStart.y;
                radarState.pan.x += dx;
                radarState.pan.y += dy;
                clampPanAndZoom();
            }
            panStart = { x: e.clientX, y: e.clientY };
            return;
        }

        if (isDragging && dragItem) {
            if (dragItem.type === 'map-obj') {
                const obj = m.objects[dragItem.index];
                if (obj) {
                    obj.x = Math.round(world.wx);
                    obj.y = Math.round(world.wy);
                    const ix = document.querySelector(`input[onchange*="objects[${dragItem.index}].x"], input[oninput*="objects[${dragItem.index}].x"]`);
                    const iy = document.querySelector(`input[onchange*="objects[${dragItem.index}].y"], input[oninput*="objects[${dragItem.index}].y"]`);
                    if (ix) ix.value = obj.x;
                    if (iy) iy.value = obj.y;
                    const rxInput = document.getElementById('map-radar-x');
                    const ryInput = document.getElementById('map-radar-y');
                    if (rxInput) rxInput.value = obj.x;
                    if (ryInput) ryInput.value = obj.y;
                }
            } else if (dragItem.type === 'map-spawn') {
                const s = m.spawns[dragItem.index];
                if (s) {
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
            } else if (dragItem.type === 'map-spawn-vertex') {
                const s = m.spawns[dragItem.index];
                if (s && s.polygon && s.polygon[dragItem.vertexIndex]) {
                    s.polygon[dragItem.vertexIndex].x = Math.round(world.wx);
                    s.polygon[dragItem.vertexIndex].y = Math.round(world.wy);
                    // Actualizar textarea
                    const ta = document.getElementById(`spawn-polygon-${dragItem.index}`);
                    if (ta) ta.value = formatPolygon(s.polygon);
                    // Recalcular centroide
                    const cx = s.polygon.reduce((a,p)=>a+p.x,0)/s.polygon.length;
                    const cy = s.polygon.reduce((a,p)=>a+p.y,0)/s.polygon.length;
                    s.x = Math.round(cx);
                    s.y = Math.round(cy);
                }
            }
        } else {
            window.lastMouseWorldX = Math.round(world.wx);
            window.lastMouseWorldY = Math.round(world.wy);

            if (e.target === canvas) {
                let hoveringItem = false;
                const objects = m.objects || [];
                for (let i = 0; i < objects.length; i++) {
                    const pos = worldToCanvas(objects[i].x || 0, objects[i].y || 0);
                    if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 14) {
                        hoveringItem = true;
                        break;
                    }
                }
                if (!hoveringItem) {
                    const spawns = m.spawns || [];
                    for (let i = 0; i < spawns.length; i++) {
                        const s = spawns[i];
                        // Chequear vértices de polígono
                        if (s.spawnMode === 'polygon' && s.polygon && s.polygon.length >= 3) {
                            const polyPoints = s.polygon.map(p => worldToCanvas(p.x, p.y));
                            for (let vi = 0; vi < polyPoints.length; vi++) {
                                if (Math.hypot(polyPoints[vi].x - mouseX, polyPoints[vi].y - mouseY) < 10) {
                                    hoveringItem = true;
                                    break;
                                }
                            }
                            if (hoveringItem) break;
                        }
                        const pos = worldToCanvas(s.x || 0, s.y || 0);
                        if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 16) {
                            hoveringItem = true;
                            break;
                        }
                    }
                }
                if (!hoveringItem && polygonDrawMode) {
                    canvas.style.cursor = 'crosshair';
                } else {
                    canvas.style.cursor = hoveringItem ? 'grab' : 'crosshair';
                }
            }
        }
    };

    window.onmouseup = () => {
        if (isDragging) {
            isDragging = false;
            dragItem = null;
            canvas.style.cursor = 'crosshair';
        }
        if (isPanning) {
            isPanning = false;
            canvas.style.cursor = 'crosshair';
        }
    };

    // Teclas para modo dibujo de polígono
    const handleKeyDown = (e) => {
        if (polygonDrawMode) {
            if (e.key === 'Escape') {
                cancelPolygonDraw();
            } else if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                finishPolygonDraw();
            } else if (e.key === 'z' && (e.ctrlKey || e.metaKey)) {
                // Undo último vértice
                if (polygonDrawPoints.length > 0) {
                    polygonDrawPoints.pop();
                    if (polygonDrawTargetIdx >= 0) {
                        const ta = document.getElementById(`spawn-polygon-${polygonDrawTargetIdx}`);
                        if (ta) ta.value = formatPolygon(polygonDrawPoints);
                    } else {
                        const ta = document.getElementById('map-add-polygon');
                        if (ta) ta.value = formatPolygon(polygonDrawPoints);
                    }
                    renderMapDetail();
                }
            }
        }
    };
    window.addEventListener('keydown', handleKeyDown);
    
    // Cleanup al cerrar el detalle del mapa
    const originalRenderMapDetail = window.renderMapDetail;
    window.renderMapDetail = function() {
        // NO cancelar el modo dibujo acá - redibujar normalmente y que el modo persista
        return originalRenderMapDetail.apply(this, arguments);
    };

    const draw = () => {
        if (!document.getElementById('map-radar-canvas')) return;
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // 1. Fondo del canvas oscuro de alta gama
        ctx.fillStyle = '#060a14';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // Coordenadas en pantalla del rectángulo del terreno con zoom y pan
        const pTopLeft = worldToCanvas(minX, minY);
        const pBottomRight = worldToCanvas(minX + worldW, minY + worldH);
        const terrainW = pBottomRight.x - pTopLeft.x;
        const terrainH = pBottomRight.y - pTopLeft.y;

        // Tinte de fondo del terreno delimitado
        ctx.fillStyle = m.color ? m.color + '12' : 'rgba(6, 182, 212, 0.05)';
        ctx.fillRect(pTopLeft.x, pTopLeft.y, terrainW, terrainH);

        // 2. Textura topográfica real de Godot (relieve 3D) si está cargada
        if (terrainImg && terrainImg.complete && terrainImg.naturalWidth > 0) {
            ctx.save();
            ctx.globalAlpha = 0.88;
            ctx.drawImage(terrainImg, pTopLeft.x, pTopLeft.y, terrainW, terrainH);
            ctx.restore();
        }

        // Borde del sector de mapa
        ctx.strokeStyle = m.color || 'rgba(6, 182, 212, 0.5)';
        ctx.lineWidth = 1.5;
        ctx.strokeRect(pTopLeft.x, pTopLeft.y, terrainW, terrainH);

        // 3. Grid cibernético alineado con las coordenadas reales del mundo (cada 2000px)
        const gridSpacing = 2000;
        ctx.strokeStyle = m.color ? m.color + '20' : 'rgba(6, 182, 212, 0.12)';
        ctx.lineWidth = 1;
        ctx.font = '9px monospace';
        ctx.fillStyle = 'rgba(6, 182, 212, 0.5)';
        ctx.textAlign = 'left';

        const startX = Math.ceil(minX / gridSpacing) * gridSpacing;
        for (let gx = startX; gx <= minX + worldW; gx += gridSpacing) {
            const pTop = worldToCanvas(gx, minY);
            const pBot = worldToCanvas(gx, minY + worldH);
            ctx.beginPath();
            ctx.moveTo(pTop.x, pTop.y);
            ctx.lineTo(pBot.x, pBot.y);
            ctx.stroke();
            if (pTop.x >= 0 && pTop.x <= canvas.width) {
                ctx.fillText(Math.round(gx).toString(), pTop.x + 3, Math.max(12, Math.min(canvas.height - 4, pTop.y + 11)));
            }
        }

        const startY = Math.ceil(minY / gridSpacing) * gridSpacing;
        for (let gy = startY; gy <= minY + worldH; gy += gridSpacing) {
            const pLeft = worldToCanvas(minX, gy);
            const pRight = worldToCanvas(minX + worldW, gy);
            ctx.beginPath();
            ctx.moveTo(pLeft.x, pLeft.y);
            ctx.lineTo(pRight.x, pRight.y);
            ctx.stroke();
            if (pLeft.y >= 0 && pLeft.y <= canvas.height) {
                ctx.fillText(Math.round(gy).toString(), Math.max(4, pLeft.x + 4), pLeft.y - 3);
            }
        }

        // Ejes X=0 y Y=0 sutilmente destacados si están dentro de los límites
        if (minX <= 0 && minX + worldW >= 0) {
            const p0_top = worldToCanvas(0, minY);
            const p0_bot = worldToCanvas(0, minY + worldH);
            ctx.strokeStyle = 'rgba(255, 255, 255, 0.35)';
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.moveTo(p0_top.x, p0_top.y);
            ctx.lineTo(p0_bot.x, p0_bot.y);
            ctx.stroke();
        }
        if (minY <= 0 && minY + worldH >= 0) {
            const p0_left = worldToCanvas(minX, 0);
            const p0_right = worldToCanvas(minX + worldW, 0);
            ctx.strokeStyle = 'rgba(255, 255, 255, 0.35)';
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.moveTo(p0_left.x, p0_left.y);
            ctx.lineTo(p0_right.x, p0_right.y);
            ctx.stroke();
        }

        // ========== 4. DIBUJAR SPAWNS ==========
        const spawns = m.spawns || [];
        spawns.forEach((s, idx) => {
            if (s.spawnMode === 'random' && (!s.radius || s.radius === 0) && (!s.polygon || s.polygon.length < 3)) return;

            const sx = s.x !== undefined ? s.x : 0;
            const sy = s.y !== undefined ? s.y : 0;
            const pos = worldToCanvas(sx, sy);
            const isFocused = focusedRadarItem && focusedRadarItem.type === 'map-spawn' && focusedRadarItem.index === idx;
            const isSelected = isDragging && dragItem && dragItem.type === 'map-spawn' && dragItem.index === idx;

            const model = config.enemyModels ? (config.enemyModels[s.type] || { name: 'Enemigo ' + s.type }) : { name: 'Enemigo ' + s.type };
            const isBoss = (model.isBoss === true) || (Number(s.type) >= 101) || (s.type === '10' || s.type === '11');

            // --- DIBUJAR POLÍGONO PERSONALIZADO ---
            if (s.spawnMode === 'polygon' && s.polygon && s.polygon.length >= 3) {
                const polyColor = isBoss ? '#a640ff' : '#10b981';
                const polyPoints = s.polygon.map(p => worldToCanvas(p.x, p.y));
                
                // Relleno del polígono
                ctx.fillStyle = isBoss ? 'rgba(168, 85, 247, 0.1)' : 'rgba(16, 185, 129, 0.08)';
                ctx.beginPath();
                ctx.moveTo(polyPoints[0].x, polyPoints[0].y);
                for (let i = 1; i < polyPoints.length; i++) {
                    ctx.lineTo(polyPoints[i].x, polyPoints[i].y);
                }
                ctx.closePath();
                ctx.fill();
                
                // Borde del polígono
                ctx.strokeStyle = polyColor + (isSelected || isFocused ? 'cc' : '80');
                ctx.lineWidth = (isSelected || isFocused) ? 2.5 : 1.5;
                ctx.beginPath();
                ctx.moveTo(polyPoints[0].x, polyPoints[0].y);
                for (let i = 1; i < polyPoints.length; i++) {
                    ctx.lineTo(polyPoints[i].x, polyPoints[i].y);
                }
                ctx.closePath();
                ctx.stroke();
                
                // Vértices del polígono
                ctx.fillStyle = polyColor;
                polyPoints.forEach((p, vi) => {
                    ctx.beginPath();
                    ctx.arc(p.x, p.y, isSelected || isFocused ? 6 : 4, 0, Math.PI * 2);
                    ctx.fill();
                    // Número de vértice
                    ctx.fillStyle = '#fff';
                    ctx.font = 'bold 8px monospace';
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.fillText((vi + 1).toString(), p.x, p.y);
                    ctx.textBaseline = 'alphabetic';
                    ctx.fillStyle = polyColor;
                });
            }

            // Radio de dispersión de spawn si existe (escalado con zoom)
            if (s.spawnMode === 'random' && s.radius > 0) {
                const radiusCanvas = ((s.radius / worldW) * canvas.width) * radarState.zoom;
                ctx.fillStyle = isBoss ? 'rgba(168, 85, 247, 0.08)' : 'rgba(16, 185, 129, 0.05)';
                ctx.strokeStyle = isBoss ? 'rgba(168, 85, 247, 0.35)' : 'rgba(16, 185, 129, 0.25)';
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, radiusCanvas, 0, Math.PI * 2);
                ctx.fill();
                ctx.stroke();
            }

            // Escala y radio proporcional acorde al espacio físico en el minimapa
            const entScale = model.scale ? Number(model.scale) : (isBoss ? 6.0 : 2.0);
            const dotR = isBoss ? Math.max(5.0, Math.min(14.0, 4.0 * (entScale / 6.0))) : 4.0;
            const mainColor = isBoss ? '#a640ff' : '#10b981';
            const ringColor = isBoss ? '#c084fc' : '#34d399';

            if (isSelected || isFocused) {
                const pulse = 3 + Math.sin(Date.now() / 180) * 2;
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, dotR + 8 + pulse, 0, Math.PI * 2);
                ctx.strokeStyle = mainColor;
                ctx.lineWidth = 2;
                ctx.stroke();
            }

            // Halo exterior translúcido
            ctx.fillStyle = (isSelected || isFocused) ? '#fff' : (isBoss ? 'rgba(168, 85, 247, 0.25)' : 'rgba(16, 185, 129, 0.2)');
            ctx.strokeStyle = ringColor;
            ctx.lineWidth = isSelected ? 2.5 : 1.5;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, dotR + 3, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();

            // Núcleo del enemigo
            ctx.fillStyle = mainColor;
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, dotR, 0, Math.PI * 2);
            ctx.fill();

            // Núcleo blanco nítido para bosses
            if (isBoss) {
                ctx.fillStyle = '#ffffff';
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, Math.min(2.5, dotR * 0.35), 0, Math.PI * 2);
                ctx.fill();
            }

            // Etiqueta de nombre
            ctx.fillStyle = isBoss ? '#e9d5ff' : '#10b981';
            ctx.font = `bold ${isBoss ? 10 : 9}px Outfit`;
            ctx.textAlign = 'center';
            ctx.fillText(model.name, pos.x, pos.y - (dotR + 7));
        });

        // ========== 5. DIBUJAR OBJETOS DEL MUNDO ==========
        const OBJECT_STYLES = {
            chest:  { color: '#ffd700', glow: 'rgba(255,215,0,0.3)', icon: 'B', size: 9 },
            door:   { color: '#00d2ff', glow: 'rgba(0,210,255,0.3)', icon: 'P', size: 10 },
            tower:  { color: '#ff8c00', glow: 'rgba(255,140,0,0.3)', icon: 'T', size: 9 },
            wall:   { color: '#a87c52', glow: 'rgba(168,124,82,0.3)', icon: '🧱', size: 9 },
            market: { color: '#ffd700', glow: 'rgba(255,215,0,0.35)', icon: '🛒', size: 10 },
            altar:  { color: '#00ff88', glow: 'rgba(0,255,136,0.35)', icon: 'A', size: 10 },
            nexus:  { color: '#ef4444', glow: 'rgba(239,68,68,0.35)', icon: 'N', size: 10 },
            pillar: { color: '#3b82f6', glow: 'rgba(59,130,246,0.35)', icon: 'P', size: 9 }
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

            ctx.fillStyle = style.color;
            ctx.font = 'bold 10px Outfit';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(style.icon, pos.x, pos.y);
            ctx.textBaseline = 'alphabetic';

            const labelText = obj.label || obj.type.toUpperCase();
            ctx.fillStyle = style.color;
            ctx.font = '8px Outfit';
            ctx.textAlign = 'center';
            ctx.fillText(labelText, pos.x, pos.y + 19);

            if (obj.type === 'door' && obj.targetZoneId) {
                const destZoneName = config.mapsConfig[obj.targetZoneId] ? config.mapsConfig[obj.targetZoneId].name : `Zona ${obj.targetZoneId}`;
                ctx.fillStyle = 'rgba(0,210,255,0.7)';
                ctx.font = '7px Outfit';
                ctx.textAlign = 'center';
                ctx.fillText(`→ ${destZoneName}`, pos.x, pos.y + 28);
            }
        });

        // ========== PREVIEW DE POLÍGONO EN DIBUJO ==========
        if (polygonDrawMode && polygonDrawPoints.length > 0) {
            const polyPoints = polygonDrawPoints.map(p => worldToCanvas(p.x, p.y));
            const previewColor = '#10b981';
            
            // Dibujar aristas completadas
            if (polyPoints.length > 1) {
                ctx.strokeStyle = previewColor + '80';
                ctx.lineWidth = 2;
                ctx.setLineDash([8, 4]);
                ctx.beginPath();
                ctx.moveTo(polyPoints[0].x, polyPoints[0].y);
                for (let i = 1; i < polyPoints.length; i++) {
                    ctx.lineTo(polyPoints[i].x, polyPoints[i].y);
                }
                ctx.stroke();
                ctx.setLineDash([]);
            }
            
            // Línea de preview al mouse actual
            if (window.lastMouseWorldX !== undefined && window.lastMouseWorldY !== undefined) {
                const mouseCanvas = worldToCanvas(window.lastMouseWorldX, window.lastMouseWorldY);
                ctx.strokeStyle = previewColor + 'cc';
                ctx.lineWidth = 2;
                ctx.setLineDash([6, 6]);
                ctx.beginPath();
                ctx.moveTo(polyPoints[polyPoints.length - 1].x, polyPoints[polyPoints.length - 1].y);
                ctx.lineTo(mouseCanvas.x, mouseCanvas.y);
                // Si hay más de 2 puntos, mostrar línea de cierre
                if (polyPoints.length >= 2) {
                    ctx.moveTo(mouseCanvas.x, mouseCanvas.y);
                    ctx.lineTo(polyPoints[0].x, polyPoints[0].y);
                }
                ctx.stroke();
                ctx.setLineDash([]);
            }
            
            // Vértices colocados
            ctx.fillStyle = previewColor;
            polyPoints.forEach((p, vi) => {
                ctx.beginPath();
                ctx.arc(p.x, p.y, 6, 0, Math.PI * 2);
                ctx.fill();
                ctx.fillStyle = '#fff';
                ctx.font = 'bold 8px monospace';
                ctx.textAlign = 'center';
                ctx.textBaseline = 'middle';
                ctx.fillText((vi + 1).toString(), p.x, p.y);
                ctx.textBaseline = 'alphabetic';
                ctx.fillStyle = previewColor;
            });
            
            // Texto de ayuda
            ctx.fillStyle = 'rgba(16, 185, 129, 0.9)';
            ctx.font = 'bold 11px Outfit';
            ctx.textAlign = 'center';
            ctx.fillText(`📐 Dibujando: ${polyPoints.length} vértices  |  Click: Añadir  |  Click derecho/Enter: Finalizar  |  ESC: Cancelar  |  Ctrl+Z: Deshacer`, 
                canvas.width / 2, 30);
        }

        // Coordenadas flotantes y nivel de zoom en la barra inferior
        ctx.fillStyle = 'rgba(255, 255, 255, 0.85)';
        ctx.font = '10px monospace';
        ctx.textAlign = 'left';
        const coordsText = (window.lastMouseWorldX !== undefined && window.lastMouseWorldY !== undefined)
            ? `X: ${window.lastMouseWorldX} Y: ${window.lastMouseWorldY}`
            : `X: 0 Y: 0`;
        const zoomText = `🔍 ${Math.round(radarState.zoom * 100)}%`;
        ctx.fillText(`${coordsText}  |  ${zoomText}`, 10, canvas.height - 10);

        requestAnimationFrame(draw);
    };
    draw();
}

// ============================================================================
// LOGICA DE TALENTOS Y MAPA DE CONEXIONES (TREE MAP)
// ============================================================================

var talentMapperTool = 'select'; // 'select' o 'connect'
var selectedTalentNodeId = null;
var connectStartNodeId = null;
var talentPanOffset = { x: 0, y: 0 };
var talentZoom = 1.0; // Zoom level (1.0 = 100%)
window.talentMapperTool = talentMapperTool;
window.selectedTalentNodeId = selectedTalentNodeId;
window.connectStartNodeId = connectStartNodeId;
window.talentPanOffset = talentPanOffset;
window.talentZoom = talentZoom;
const TALENT_ZOOM_MIN = 0.15;
const TALENT_ZOOM_MAX = 4.0;

// Bounds del árbol - calculados a partir de los nodos colocados
function getNodeBounds() {
    const nodes = config.talentsConfig.nodes || {};
    const entries = Object.values(nodes);
    if (entries.length === 0) return null;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const pos of entries) {
        minX = Math.min(minX, pos.x);
        minY = Math.min(minY, pos.y);
        maxX = Math.max(maxX, pos.x);
        maxY = Math.max(maxY, pos.y);
    }
    const PAD = 200;
    return { minX: minX - PAD, minY: minY - PAD, maxX: maxX + PAD, maxY: maxY + PAD };
}

function getTreeCenter() {
    const nodes = config.talentsConfig.nodes || {};
    const entries = Object.values(nodes);
    if (entries.length === 0) return { x: 0, y: 0 };
    let sx = 0, sy = 0;
    for (const pos of entries) { sx += pos.x; sy += pos.y; }
    return { x: sx / entries.length, y: sy / entries.length };
}

function clampPanOffset() {
    // No forzar nada — solo evitar que se pierda completamente la vista
    // El usuario puede mover libremente, solo se limita al zoom reset
}
var isPanningTalents = false;
var panStart = { x: 0, y: 0 };
var isDraggingTalentNode = false;
var dragNodeId = null;
var talentMapperCanvasInitialized = false;
var talentMapperHoveredNode = null; // Nodo bajo el cursor
var talentMapperSearchTerm = ''; // Filtro de búsqueda
window.talentMapperHoveredNode = talentMapperHoveredNode;
window.talentMapperSearchTerm = talentMapperSearchTerm;

// Tamaños de nodos por tipo (estilo POE2)
const NODE_TYPES = {
    small:    { radius: 22, iconSize: '16px', labelSize: '9px',  glowIntensity: 0.3, borderWidth: 2, label: 'Pequeño' },
    notable:  { radius: 30, iconSize: '20px', labelSize: '10px', glowIntensity: 0.6, borderWidth: 3, label: 'Notable' },
    keystone: { radius: 40, iconSize: '28px', labelSize: '12px', glowIntensity: 1.0, borderWidth: 4, label: 'Clave' }
};

// ═══════════════════════════════════════════════
// SISTEMA DE CATEGORÍAS / RAMAS DINÁMICAS
// ═══════════════════════════════════════════════

const DEFAULT_CATEGORIES = [
    { id: 'engineering', name: 'Ingeniería', color: '#00d2ff', emoji: '🛠️' },
    { id: 'combat', name: 'Combate', color: '#ff3131', emoji: '⚔️' },
    { id: 'science', name: 'Ciencia', color: '#be31ff', emoji: '🔬' }
];

window.darkenHexColor = function(hex, factor = 0.35) {
    if (!hex || typeof hex !== 'string') return '#0a1428';
    let clean = hex.replace('#', '');
    if (clean.length === 3) clean = clean.split('').map(c => c + c).join('');
    if (clean.length !== 6) return '#0a1428';
    const num = parseInt(clean, 16);
    let r = Math.max(0, Math.floor(((num >> 16) & 255) * factor));
    let g = Math.max(0, Math.floor(((num >> 8) & 255) * factor));
    let b = Math.max(0, Math.floor((num & 255) * factor));
    return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
};

window.getCategories = function() {
    if (!config.talentsConfig) config.talentsConfig = {};
    if (!config.talentsConfig.categories || !Array.isArray(config.talentsConfig.categories) || config.talentsConfig.categories.length === 0) {
        config.talentsConfig.categories = JSON.parse(JSON.stringify(DEFAULT_CATEGORIES));
    }
    return config.talentsConfig.categories;
};

window.getCategoryById = function(id) {
    const cats = window.getCategories();
    return cats.find(c => c.id === id) || cats[0] || { id: 'default', name: 'General', color: '#00d2ff', emoji: '⭐' };
};

window.getCategoryColor = function(catId) {
    return window.getCategoryById(catId).color || '#00d2ff';
};

window.getCategoryEmoji = function(catId) {
    return window.getCategoryById(catId).emoji || '⭐';
};

window.getCategoryName = function(catId) {
    return window.getCategoryById(catId).name || catId;
};

window.renderCategoriesPanel = function() {
    const targets = [
        document.getElementById('talent-categories-panel'),
        document.getElementById('talent-categories-modal-content')
    ].filter(Boolean);

    if (targets.length === 0) return;

    const cats = window.getCategories();
    const talents = (config.talentsConfig && config.talentsConfig.talents) ? config.talentsConfig.talents : [];

    const html = `
        <div class="card" style="background: rgba(12, 20, 36, 0.7); border: 1px solid rgba(0, 210, 255, 0.2); border-radius: 10px; padding: 1.2rem; box-shadow: 0 8px 32px rgba(0,0,0,0.4); margin-bottom: 1.5rem;">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; flex-wrap: wrap; gap: 10px;">
                <div>
                    <div style="color: var(--primary); font-size: 0.95rem; font-weight: bold; letter-spacing: 0.5px; display: flex; align-items: center; gap: 8px;">
                        <span>📁 RAMAS DEL ÁRBOL DE TALENTOS</span>
                        <span style="font-size: 0.7rem; background: rgba(0,210,255,0.15); color: var(--primary); padding: 2px 8px; border-radius: 12px; font-weight: normal;">${cats.length} activas</span>
                    </div>
                    <div style="font-size: 0.72rem; color: var(--text-dim); margin-top: 3px;">
                        Personaliza los nombres, colores, iconos e identificadores de tus ramas. Todo cambio actualiza el mapa y los filtros en vivo.
                    </div>
                </div>
                <button class="btn btn-primary" style="padding: 6px 14px; font-size: 0.75rem;" onclick="addCategory()">
                    ➕ NUEVA RAMA
                </button>
            </div>

            <div style="display: flex; flex-direction: column; gap: 8px; margin-top: 10px;">
                ${cats.map((c, i) => {
                    const assignedCount = talents.filter(t => t.category === c.id).length;
                    return `
                    <div style="display: flex; gap: 10px; align-items: center; background: rgba(255,255,255,0.03); padding: 8px 12px; border-radius: 8px; border: 1px solid ${c.color}40; flex-wrap: wrap; transition: border-color 0.2s;">
                        <!-- Emoji/Icono -->
                        <div style="display: flex; flex-direction: column;">
                            <span style="font-size: 0.65rem; color: #888; margin-bottom: 2px;">Icono</span>
                            <input type="text" value="${c.emoji || '⭐'}" title="Emoji o Icono" style="width: 44px; text-align: center; font-size: 1.25rem; background: rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.1); border-radius: 6px; padding: 4px;" onchange="updateCategory(${i}, 'emoji', this.value)">
                        </div>

                        <!-- Nombre de la Rama -->
                        <div style="flex: 2; min-width: 150px; display: flex; flex-direction: column;">
                            <span style="font-size: 0.65rem; color: #888; margin-bottom: 2px;">Nombre de la Rama</span>
                            <input type="text" value="${reqAttrEscape(c.name)}" placeholder="Nombre de la rama" style="width: 100%; font-size: 0.85rem; font-weight: bold; color: white; background: rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.1); border-radius: 6px; padding: 6px 10px;" onchange="updateCategory(${i}, 'name', this.value)">
                        </div>

                        <!-- ID Técnico -->
                        <div style="flex: 1; min-width: 130px; display: flex; flex-direction: column;">
                            <span style="font-size: 0.65rem; color: #888; margin-bottom: 2px;">ID Técnico (slug)</span>
                            <input type="text" value="${reqAttrEscape(c.id)}" placeholder="id_unico" style="width: 100%; font-size: 0.75rem; font-family: 'JetBrains Mono', monospace; color: var(--accent); background: rgba(0,0,0,0.4); border: 1px solid rgba(255,255,255,0.1); border-radius: 6px; padding: 6px 8px;" onchange="updateCategory(${i}, 'id', this.value)">
                        </div>

                        <!-- Selector de Color -->
                        <div style="display: flex; flex-direction: column; align-items: center;">
                            <span style="font-size: 0.65rem; color: #888; margin-bottom: 2px;">Color</span>
                            <div style="display: flex; align-items: center; gap: 6px;">
                                <input type="color" value="${c.color || '#00d2ff'}" title="Color de la rama" style="width: 36px; height: 32px; border: none; border-radius: 6px; cursor: pointer; background: transparent; padding: 0;" onchange="updateCategory(${i}, 'color', this.value)">
                                <span style="font-size: 0.7rem; font-family: 'JetBrains Mono'; color: ${c.color};">${c.color}</span>
                            </div>
                        </div>

                        <!-- Contador de Talentos -->
                        <div style="display: flex; flex-direction: column; align-items: center; min-width: 70px;">
                            <span style="font-size: 0.65rem; color: #888; margin-bottom: 2px;">Talentos</span>
                            <span style="font-size: 0.72rem; padding: 4px 8px; border-radius: 12px; background: ${c.color}20; color: ${c.color}; border: 1px solid ${c.color}40; font-weight: bold;">
                                ${assignedCount}
                            </span>
                        </div>

                        <!-- Botón Eliminar -->
                        <div style="display: flex; flex-direction: column; justify-content: flex-end;">
                            <button class="btn btn-secondary" style="background: rgba(255,59,48,0.1); border-color: rgba(255,59,48,0.3); color: #ff3b30; padding: 6px 10px; font-size: 0.75rem;" onclick="removeCategory(${i})" title="Eliminar esta rama">
                                🗑️
                            </button>
                        </div>
                    </div>
                    `;
                }).join('')}
            </div>
        </div>
    `;

    targets.forEach(el => { el.innerHTML = html; });
};

window.addCategory = function() {
    const cats = window.getCategories();
    const newIdx = cats.length + 1;
    const colors = ['#00d2ff', '#ff3131', '#be31ff', '#10b981', '#f59e0b', '#ec4899', '#06b6d4', '#8b5cf6'];
    const chosenColor = colors[newIdx % colors.length];
    const emojis = ['🌟', '🛡️', '⚡', '🌀', '🔮', '🧬', '🚀', '🔥'];
    const chosenEmoji = emojis[newIdx % emojis.length];

    const id = 'rama_' + Date.now().toString(36);
    cats.push({
        id: id,
        name: `Nueva Rama ${newIdx}`,
        color: chosenColor,
        emoji: chosenEmoji
    });

    window.renderCategoriesPanel();
    if (typeof renderTalentCreator === 'function') renderTalentCreator();
    if (typeof renderTalentMapper === 'function') renderTalentMapper();
    if (typeof updateBranchStats === 'function') updateBranchStats();
};

window.removeCategory = function(idx) {
    const cats = window.getCategories();
    if (cats.length <= 1) {
        alert('Debe existir al menos una rama de talentos.');
        return;
    }

    const targetCat = cats[idx];
    const talents = (config.talentsConfig && config.talentsConfig.talents) ? config.talentsConfig.talents : [];
    const assignedCount = talents.filter(t => t.category === targetCat.id).length;

    const remainingCats = cats.filter((_, i) => i !== idx);
    const fallbackCat = remainingCats[0];

    const confirmMsg = assignedCount > 0
        ? `¿Eliminar la rama "${targetCat.name}"? Los ${assignedCount} talentos asignados se reasignarán automáticamente a "${fallbackCat.name}".`
        : `¿Eliminar la rama "${targetCat.name}"?`;

    if (!confirm(confirmMsg)) return;

    cats.splice(idx, 1);

    // Reasignar talentos huérfanos a la rama remanente
    talents.forEach(t => {
        if (t.category === targetCat.id) {
            t.category = fallbackCat.id;
        }
    });

    // Reasignar en talentos sellados si aplica
    if (config.talentsLockedConfig && Array.isArray(config.talentsLockedConfig)) {
        config.talentsLockedConfig.forEach(t => {
            if (t.category === targetCat.id) t.category = fallbackCat.id;
        });
    }

    window.renderCategoriesPanel();
    if (typeof renderTalentCreator === 'function') renderTalentCreator();
    if (typeof renderTalentMapper === 'function') renderTalentMapper();
    if (typeof updateBranchStats === 'function') updateBranchStats();
};

window.updateCategory = function(idx, field, value) {
    const cats = window.getCategories();
    if (!cats[idx]) return;

    const oldCat = cats[idx];
    const oldId = oldCat.id;

    if (field === 'id') {
        const cleanId = String(value).trim().toLowerCase().replace(/[^a-z0-9_-]/g, '_');
        if (!cleanId) return;
        if (cleanId !== oldId && cats.some((c, i) => i !== idx && c.id === cleanId)) {
            alert('El ID técnico ya está en uso por otra rama.');
            window.renderCategoriesPanel();
            return;
        }
        oldCat.id = cleanId;

        // Migrar automáticamente todos los talentos vinculados al nuevo ID
        const talents = (config.talentsConfig && config.talentsConfig.talents) ? config.talentsConfig.talents : [];
        talents.forEach(t => {
            if (t.category === oldId) t.category = cleanId;
        });

        if (config.talentsLockedConfig && Array.isArray(config.talentsLockedConfig)) {
            config.talentsLockedConfig.forEach(t => {
                if (t.category === oldId) t.category = cleanId;
            });
        }
    } else {
        oldCat[field] = value;
    }

    window.renderCategoriesPanel();
    if (typeof renderTalentCreator === 'function') renderTalentCreator();
    if (typeof renderTalentMapper === 'function') renderTalentMapper();
    if (typeof updateBranchStats === 'function') updateBranchStats();
};

window.openTalentCategoriesModal = function() {
    let modal = document.getElementById('talent-categories-modal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'talent-categories-modal';
        modal.style.cssText = 'display: flex; position: fixed; inset: 0; background: rgba(0,0,0,0.8); backdrop-filter: blur(8px); z-index: 10000; align-items: center; justify-content: center; padding: 20px;';
        modal.innerHTML = `
            <div style="background: #091220; border: 1px solid rgba(0, 210, 255, 0.3); border-radius: 14px; width: 100%; max-width: 820px; max-height: 90vh; display: flex; flex-direction: column; overflow: hidden; box-shadow: 0 10px 40px rgba(0,0,0,0.8);">
                <div style="display: flex; justify-content: space-between; align-items: center; padding: 1rem 1.5rem; border-bottom: 1px solid rgba(255,255,255,0.08); background: rgba(255,255,255,0.02);">
                    <h3 style="margin: 0; color: var(--primary); font-size: 1.15rem; display: flex; align-items: center; gap: 8px;">
                        <span>📁 CONFIGURACIÓN DE RAMAS DE TALENTOS</span>
                    </h3>
                    <button class="btn btn-secondary" style="padding: 4px 10px; font-size: 0.8rem;" onclick="closeTalentCategoriesModal()">✕ CERRAR</button>
                </div>
                <div id="talent-categories-modal-content" style="flex: 1; overflow-y: auto; padding: 1.5rem;"></div>
            </div>
        `;
        document.body.appendChild(modal);
    }
    modal.style.display = 'flex';
    window.renderCategoriesPanel();
};

window.closeTalentCategoriesModal = function() {
    const modal = document.getElementById('talent-categories-modal');
    if (modal) modal.style.display = 'none';
};

function addNewTalent() {
    document.getElementById('talent-create-modal').style.display = 'flex';
    document.getElementById('cm-name').value = '';
    document.getElementById('cm-desc').value = '';
    document.getElementById('cm-icon').value = '🌳';
    // Poblar categorías dinámicamente
    const catSelect = document.getElementById('cm-category');
    const cats = (typeof getCategories === 'function') ? getCategories() : [];
    catSelect.innerHTML = cats.map(c => `<option value="${c.id}">${c.emoji} ${c.name}</option>`).join('');
    catSelect.value = cats[0]?.id || 'default';
    document.getElementById('cm-nodeType').value = 'small';
    document.getElementById('cm-maxLevel').value = '1';
    window._cmEffects = [];
    window._cmEffectFilter = '';
    cmRenderEffects();
    cmUpdateMaxLevel();
}

window.closeTalentModal = function() {
    document.getElementById('talent-create-modal').style.display = 'none';
};

window.cmUpdateMaxLevel = function() {
    const t = document.getElementById('cm-nodeType').value;
    const map = { small: 1, notable: 2, keystone: 3 };
    document.getElementById('cm-maxLevel').value = map[t] || 1;
};

window.cmAddEffect = function() {
    if (typeof window.openEffectPickerModal === 'function') {
        window.openEffectPickerModal(null, (selected) => {
            if (!Array.isArray(window._cmEffects)) window._cmEffects = [];
            if (!window._cmEffects.some(e => e.key === selected.key)) {
                window._cmEffects.push({
                    key: selected.key,
                    val: selected.val,
                    flat: selected.flat,
                    label: selected.label,
                    icon: selected.icon
                });
                cmRenderEffects();
            }
        });
    }
};

window.cmRemoveEffect = function(i) {
    if (Array.isArray(window._cmEffects)) {
        window._cmEffects.splice(i, 1);
        cmRenderEffects();
    }
};

window.cmUpdateEffectVal = function(i, newVal) {
    if (!window._cmEffects || !window._cmEffects[i]) return;
    const isFlat = !!window._cmEffects[i].flat;
    window._cmEffects[i].val = isFlat ? (parseFloat(newVal) || 0) : ((parseFloat(newVal) || 0) / 100);
};

window.cmToggleEffectFlat = function(i) {
    if (!window._cmEffects || !window._cmEffects[i]) return;
    const oldFlat = !!window._cmEffects[i].flat;
    const oldVal = window._cmEffects[i].val;
    if (oldFlat) {
        window._cmEffects[i].flat = false;
        window._cmEffects[i].val = oldVal / 100;
    } else {
        window._cmEffects[i].flat = true;
        window._cmEffects[i].val = oldVal * 100;
    }
    cmRenderEffects();
};

function cmRenderEffects() {
    const container = document.getElementById('cm-effects-list');
    if (!container) return;

    if (!Array.isArray(window._cmEffects) || window._cmEffects.length === 0) {
        container.innerHTML = '<div style="font-size:0.75rem; color:#666; text-align:center; padding:14px; border:1px dashed rgba(255,255,255,0.1); border-radius:8px; background:rgba(0,0,0,0.15);">Sin efectos asignados. Hacé clic en "+ EFECTO" para elegir o crear uno.</div>';
        return;
    }

    const catColors = { combate:'#ff3131', defensa:'#00d2ff', utilidad:'#f0c040', economía:'#10b981', 'curación':'#4ade80', unlock:'#a855f7', desbloqueo:'#a855f7', skill:'#f97316', weapon:'#ef4444', ammo:'#f43f5e', custom:'#38bdf8' };

    let html = '';
    window._cmEffects.forEach((e, i) => {
        const isFlat = !!e.flat;
        const numVal = isFlat ? e.val : (e.val * 100);
        const cleanVal = (typeof formatCleanNumber === 'function') ? formatCleanNumber(numVal, 2) : (Number.isInteger(numVal) ? numVal : parseFloat(numVal.toFixed(2)));
        const cat = window.TALENT_EFFECTS_CATALOG ? window.TALENT_EFFECTS_CATALOG[e.key] : null;
        const parsed = (typeof _parseDynamicKey === 'function') ? _parseDynamicKey(e.key) : null;
        const isUnlock = e.key.startsWith('unlock:');

        let displayName = e.label || e.key;
        let displayIcon = e.icon || '✨';
        let catColor = '#888';

        if (cat) {
            displayName = cat.label;
            displayIcon = cat.icon;
            catColor = catColors[cat.cat] || '#888';
        } else if (parsed) {
            const cfg = (typeof config !== 'undefined' ? config : (window.config || {})) || {};
            if (parsed.type === 'skill') {
                const sk = cfg.skillsData ? cfg.skillsData[parsed.id] : null;
                const attrMeta = window.SKILL_ATTRS ? window.SKILL_ATTRS[parsed.attr] : null;
                displayName = `${sk ? sk.name : parsed.id} → ${attrMeta ? attrMeta.label : parsed.attr}`;
                displayIcon = '🌀';
                catColor = '#f97316';
            } else if (parsed.type === 'weapon') {
                const weps = cfg.shopItems && cfg.shopItems.weapons ? cfg.shopItems.weapons : [];
                const w = weps.find(x => x.id === parsed.id);
                const attrMeta = window.WEAPON_ATTRS ? window.WEAPON_ATTRS[parsed.attr] : null;
                displayName = `${w ? w.name : parsed.id} → ${attrMeta ? attrMeta.label : parsed.attr}`;
                displayIcon = '🔫';
                catColor = '#ef4444';
            } else if (parsed.type === 'ammo') {
                const attrMeta = window.AMMO_ATTRS ? window.AMMO_ATTRS[parsed.attr] : null;
                displayName = `Munición ${parsed.id} → ${attrMeta ? attrMeta.label : parsed.attr}`;
                displayIcon = '💥';
                catColor = '#f43f5e';
            }
        } else if (isUnlock) {
            catColor = '#a855f7';
            displayIcon = '🔓';
        }

        html += `
        <div style="display:flex; gap:8px; align-items:center; background:rgba(255,255,255,0.02); padding:6px 10px; border-radius:8px; border:1px solid ${catColor}30; transition:all 0.15s;">
            <span style="font-size:1.2rem; flex-shrink:0;">${displayIcon}</span>
            <div style="flex:1; min-width:0;">
                <div style="font-size:0.75rem; font-weight:bold; color:var(--text); white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${displayName}</div>
                <div style="font-size:0.6rem; color:#888; font-family:'JetBrains Mono'; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${e.key}</div>
            </div>
            ${isUnlock ? `
                <span style="font-size:0.65rem; font-weight:bold; padding:2px 8px; border-radius:4px; background:rgba(168,85,247,0.15); color:#a855f7; border:1px solid rgba(168,85,247,0.3);">🔓 DESBLOQUEO</span>
            ` : `
                <div style="display:flex; align-items:center; gap:4px;">
                    <input type="number" step="0.01" value="${cleanVal}" style="width:75px; text-align:center; font-size:0.8rem; padding:4px 6px; border-radius:4px; background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.12); color:white; font-family:'JetBrains Mono';" onchange="cmUpdateEffectVal(${i}, this.value)">
                    <button type="button" onclick="cmToggleEffectFlat(${i})" style="min-width:38px; padding:3px 6px; font-size:0.65rem; border-radius:4px; cursor:pointer; font-weight:bold; border:1px solid ${isFlat ? 'rgba(255,150,50,0.4)' : 'rgba(0,210,255,0.4)'}; background:${isFlat ? 'rgba(255,150,50,0.15)' : 'rgba(0,210,255,0.15)'}; color:${isFlat ? '#ff9632' : '#00d2ff'};">${isFlat ? 'FIJO' : '%'}</button>
                </div>
            `}
            <button type="button" style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.9rem; padding:2px 6px;" onclick="cmRemoveEffect(${i})" title="Quitar efecto">✕</button>
        </div>`;
    });

    container.innerHTML = html;
}

window.confirmCreateTalent = function() {
    const name = document.getElementById('cm-name').value.trim();
    if (!name) { document.getElementById('cm-name').style.borderColor = '#ff4444'; return; }
    const id = 'talent_' + Date.now();
    const effects = {};
    const effectsMeta = {};
    (window._cmEffects || []).forEach(e => {
        if (e.key) {
            effects[e.key] = e.val;
            if (e.flat) {
                effectsMeta[e.key] = { flat: true };
            }
        }
    });
    const newTalent = {
        id: id,
        name: name,
        desc: document.getElementById('cm-desc').value.trim(),
        category: document.getElementById('cm-category').value,
        maxLevel: parseInt(document.getElementById('cm-maxLevel').value) || 5,
        effects: effects,
        effectsMeta: Object.keys(effectsMeta).length > 0 ? effectsMeta : undefined,
        icon: document.getElementById('cm-icon').value || '🌳'
    };
    if (!config.talentsConfig.talents) config.talentsConfig.talents = [];
    config.talentsConfig.talents.push(newTalent);
    // Pre-posicionar en el mapper
    if (!config.talentsConfig.nodes) config.talentsConfig.nodes = {};
    config.talentsConfig.nodes[id] = { x: 0, y: 0, nodeType: document.getElementById('cm-nodeType').value };
    closeTalentModal();
    renderTalentCreator();
    renderTalentMapper();
};

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
    clampPanOffset();
    renderTalentMapper();
}

function setTalentMapperTool(tool) {
    talentMapperTool = tool;
    connectStartNodeId = null;
    const btns = ['select', 'connect', 'disconnect'];
    btns.forEach(b => {
        const btn = document.getElementById('btn-talent-tool-' + b);
        if (btn) {
            btn.classList.remove('btn-primary');
            btn.classList.add('btn-secondary');
        }
    });
    const active = document.getElementById('btn-talent-tool-' + tool);
    if (active) {
        active.classList.remove('btn-secondary');
        active.classList.add('btn-primary');
    }
    const canvas = document.getElementById('talent-mapper-canvas');
    if (canvas) {
        canvas.style.cursor = tool === 'select' ? 'grab' : (tool === 'connect' ? 'crosshair' : 'crosshair');
    }
    renderTalentMapper();
}

function clearTalentMapperSelections() {
    selectedTalentNodeId = null;
    connectStartNodeId = null;
    document.getElementById('talent-node-editor-card').style.display = 'none';
    renderTalentMapper();
}

// ─── ZOOM FUNCTIONS ───
window.talentMapperZoom = function(delta) {
    const canvas = document.getElementById('talent-mapper-canvas');
    const parent = canvas ? canvas.parentElement : null;
    const rect = parent ? parent.getBoundingClientRect() : { width: 800, height: 600 };
    const centerX = (rect.width > 0 ? rect.width : 800) / 2;
    const centerY = (rect.height > 0 ? rect.height : 600) / 2;

    const oldZoom = talentZoom;
    const zoomFactor = delta > 0 ? 1.25 : 0.8;
    talentZoom = Math.max(TALENT_ZOOM_MIN, Math.min(TALENT_ZOOM_MAX, parseFloat((talentZoom * zoomFactor).toFixed(2))));
    
    // Ajustar pan offset para hacer zoom hacia el centro del visor
    const zoomRatio = talentZoom / oldZoom;
    talentPanOffset.x = centerX - (centerX - talentPanOffset.x) * zoomRatio;
    talentPanOffset.y = centerY - (centerY - talentPanOffset.y) * zoomRatio;
    
    updateZoomDisplay();
    renderTalentMapper();
};

window.talentMapperZoomReset = function() {
    talentZoom = 1.0;
    // Centrar la vista en el origen (0,0) del mundo con precisión
    const canvas = document.getElementById('talent-mapper-canvas');
    if (canvas && canvas.parentElement) {
        const rect = canvas.parentElement.getBoundingClientRect();
        talentPanOffset.x = (rect.width > 0 ? rect.width : 800) / 2;
        talentPanOffset.y = (rect.height > 0 ? rect.height : 600) / 2;
    } else {
        talentPanOffset = { x: 400, y: 300 };
    }
    updateZoomDisplay();
    renderTalentMapper();
};

function updateZoomDisplay() {
    const el = document.getElementById('talent-zoom-level');
    if (el) el.textContent = Math.round(talentZoom * 100) + '%';
}

// ─── SEARCH/FILTER ───
window.filterTalentMapperList = function() {
    const input = document.getElementById('talent-mapper-search');
    talentMapperSearchTerm = input ? input.value.toLowerCase() : '';
    renderTalentMapper();
};

// ─── FORMATEO NUMÉRICO LIMPIO (sin .0 innecesario) ───
window.formatCleanNumber = function(val, maxDecimals = 2) {
    if (val === null || val === undefined || isNaN(val)) return '0';
    const num = parseFloat(val);
    const factor = Math.pow(10, maxDecimals);
    const rounded = Math.round(num * factor) / factor;
    return Number(rounded.toFixed(maxDecimals)).toString();
};

window.formatCleanStat = function(val, isFlat = false, showPlus = true) {
    const num = parseFloat(val) || 0;
    const prefix = (num > 0.0001 && showPlus) ? '+' : (num < -0.0001 ? '-' : '');
    const absVal = Math.abs(num);
    if (isFlat) {
        return prefix + formatCleanNumber(absVal, 2) + 's';
    } else {
        return prefix + formatCleanNumber(absVal * 100, 2) + '%';
    }
};

// ─── ORDENAMIENTO DE TALENTOS: MAPEADOS PRIMERO, LUEGO POR TAMAÑO ───
window.getNodeTypeRank = function(nodeType) {
    if (nodeType === 'keystone') return 3;
    if (nodeType === 'notable') return 2;
    return 1; // 'small'
};

window.sortTalentsMappedAndSize = function(talentsList, nodesMap) {
    return talentsList.slice().sort((a, b) => {
        const aMapped = !!(nodesMap && nodesMap[a.id]);
        const bMapped = !!(nodesMap && nodesMap[b.id]);
        
        // 1. Primero los ya mapeados
        if (aMapped !== bMapped) {
            return aMapped ? -1 : 1;
        }
        
        // 2. Ordenados por tamaño (keystone > notable > small)
        const aType = (nodesMap && nodesMap[a.id]?.nodeType) || a.nodeType || 'small';
        const bType = (nodesMap && nodesMap[b.id]?.nodeType) || b.nodeType || 'small';
        const aRank = window.getNodeTypeRank(aType);
        const bRank = window.getNodeTypeRank(bType);
        if (aRank !== bRank) {
            return bRank - aRank; // Mayor tamaño primero
        }
        
        // 3. Desempate alfabético
        return (a.name || '').localeCompare(b.name || '');
    });
};

// ─── TOOLTIP ───
function showTalentTooltip(nodeId, mouseX, mouseY) {
    const tooltip = document.getElementById('talent-node-tooltip');
    if (!tooltip) return;
    
    const node = config.talentsConfig.nodes[nodeId];
    if (!node) return;
    
    const talent = (config.talentsConfig.talents || []).find(t => t.id === nodeId);
    if (!talent) return;
    
    const typeInfo = NODE_TYPES[node.nodeType || 'small'] || NODE_TYPES.small;
    const catColor = getCategoryColor(talent.category) || '#888888';
    const catLabel = getCategoryName(talent.category) || talent.category;
    
    let effectsHTML = '';
    if (talent.effects && Object.keys(talent.effects).length > 0) {
        const effectLabels = {
            hp_pct: '❤️ Vida Máx', sh_pct: '🛡️ Escudo Máx', hp_regen: '💚 Regen HP', shield_regen: '💙 Regen Escudo',
            armor_pct: '🔩 Armadura', energy_efficiency: '⚡ Eficiencia Energía', repair_cost_reduction: '💸 Costo Reparación',
            stability: '🛸 Estabilidad', laser_dmg_pct: '🔫 Daño Láser', crit_chance: '🎯 Prob. Crítico',
            crit_dmg: '💥 Daño Crítico', ammo_bonus_pct: '💣 Munición', accuracy_pct: '👁️ Puntería',
            ignore_shield_pct: '⚡ Perforación', fire_rate_pct: '⚔️ Cadencia', evasion_pct: '🏃 Evasión',
            speed_pct: '🚀 Velocidad', minimap_range: '📡 Rango Minimapa', ohcu_kill_bonus: '💎 Bonus OHCU',
            shop_discount: '🏪 Descuento', cooldown_reduction: '❄️ CD Habilidades (%)', cooldown_reduction_flat: '⏱️ CD Habilidades (fijo)',
            cast_time_reduction: '⚡ Cast Time (%)', cast_time_reduction_flat: '⏱️ Cast Time (fijo)',
            group_bonus: '👥 Bonus Grupo',
            boss_loot_bonus: '🎯 Loot Bosses', dash_distance: '🌀 Distancia Dash', dmg_pct: '⚔️ Daño Total',
            custom_stat: '⚙️ Custom'
        };
        effectsHTML = Object.entries(talent.effects).map(([key, val]) => {
            const label = effectLabels[key] || key;
            const isFlat = key.endsWith('_flat');
            const maxLvl = talent.maxLevel || 5;
            const totalVal = val * maxLvl;
            const perLvlStr = formatCleanStat(val, isFlat, true);
            const maxStr = formatCleanStat(totalVal, isFlat, true);
            const display = `${perLvlStr}/nvl <span style="color:#8899aa;">(máx ${maxStr})</span>`;
            return `<div style="color: #10b981; font-size: 0.75rem;">${label}: <strong>${display}</strong></div>`;
        }).join('');
    }
    
    tooltip.innerHTML = `
        <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 8px; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 8px;">
            <span style="display:inline-flex; width:32px; height:32px; align-items:center; justify-content:center; flex-shrink:0;">${assetIconHtml(talent.icon, { size: 32, fallback: '🌀', emojiSize: '26px', emptyHtml: '🌳', style: 'width:32px;height:32px;object-fit:contain;border-radius:8px;border:1px solid rgba(255,255,255,0.12);background:rgba(0,0,0,0.3);' })}</span>
            <div>
                <div style="font-weight: bold; color: ${catColor}; font-size: 0.9rem;">${talent.name}</div>
                <div style="font-size: 0.7rem; color: #888;">${catLabel} • ${typeInfo.label} (Nivel ${(talent.currentLevel || 0)}/${talent.maxLevel || 5})</div>
            </div>
        </div>
        <div style="font-size: 0.78rem; color: #ccc; margin-bottom: 8px;">${talent.desc || 'Sin descripción'}</div>
        ${effectsHTML ? `<div style="margin-top: 6px; padding-top: 6px; border-top: 1px solid rgba(255,255,255,0.05);">${effectsHTML}</div>` : ''}
        <div style="font-size: 0.65rem; color: #666; margin-top: 8px; font-style: italic;">Doble clic: editar • Click izq: seleccionar</div>
    `;
    
    // Posicionar tooltip evitando que se salga del canvas
    const container = document.getElementById('talent-mapper-container');
    const rect = container.getBoundingClientRect();
    let left = mouseX + 20;
    let top = mouseY - 10;
    
    // Si se sale por la derecha, mostrar a la izquierda
    if (left + 280 > rect.width) left = mouseX - 300;
    // Si se sale por abajo, mostrar arriba
    if (top + 200 > rect.height) top = mouseY - 200;
    
    tooltip.style.left = Math.max(10, left) + 'px';
    tooltip.style.top = Math.max(10, top) + 'px';
    tooltip.style.display = 'block';
}

function hideTalentTooltip() {
    const tooltip = document.getElementById('talent-node-tooltip');
    if (tooltip) tooltip.style.display = 'none';
    talentMapperHoveredNode = null;
}

// ─── BRANCH STATS ───
function updateBranchStats() {
    const talents = config.talentsConfig.talents || [];
    const cats = getCategories();
    let stats = {};
    cats.forEach(c => stats[c.id] = 0);
    
    talents.forEach(t => {
        if (t.currentLevel && t.currentLevel > 0) {
            stats[t.category] = (stats[t.category] || 0) + t.currentLevel;
        }
    });
    
    const container = document.getElementById('talent-branch-stats');
    if (!container) return;
    let html = cats.map(c => 
        `<span style="color: ${c.color};">${c.emoji} ${c.name}: <strong id="stat-${c.id}">${stats[c.id] || 0}</strong> pts</span>`
    ).join('');
    const total = Object.values(stats).reduce((a, b) => a + b, 0);
    html += `<span style="color: var(--accent);">📊 Total: <strong id="stat-total">${total}</strong> pts</span>`;
    container.innerHTML = html;
}

// ─── SINCRONIZACIÓN DE RESOLUCIÓN Y TAMAÑO HIDPI ───
window.syncTalentCanvasSize = function() {
    const canvas = document.getElementById('talent-mapper-canvas');
    if (!canvas || !canvas.parentElement) return { w: 800, h: 600, dpr: 1 };
    
    const parent = canvas.parentElement;
    const rect = parent.getBoundingClientRect();
    const w = Math.floor(rect.width > 0 ? rect.width : (parent.clientWidth || 800));
    const h = Math.floor(rect.height > 0 ? rect.height : (parent.clientHeight || 600));
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5); // Soporte HiDPI / Retina nítido
    
    const targetW = Math.round(w * dpr);
    const targetH = Math.round(h * dpr);
    
    if (canvas.width !== targetW || canvas.height !== targetH) {
        canvas.width = targetW;
        canvas.height = targetH;
    }
    canvas.style.width = w + 'px';
    canvas.style.height = h + 'px';
    
    return { w, h, dpr };
};

function placeTalentOnMap(talentId) {
    if (!config.talentsConfig.nodes) config.talentsConfig.nodes = {};
    
    const canvas = document.getElementById('talent-mapper-canvas');
    let cx = 0;
    let cy = 0;
    if (canvas && canvas.parentElement) {
        const rect = canvas.parentElement.getBoundingClientRect();
        const centerX = (rect.width > 0 ? rect.width : 800) / 2;
        const centerY = (rect.height > 0 ? rect.height : 600) / 2;
        cx = (centerX - talentPanOffset.x) / talentZoom;
        cy = (centerY - talentPanOffset.y) / talentZoom;
    }

    config.talentsConfig.nodes[talentId] = {
        x: Math.round(cx),
        y: Math.round(cy),
        nodeType: 'small'
    };
    clampPanOffset();
    if (typeof renderTalentCreator === 'function') renderTalentCreator();
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
    clampPanOffset();
    if (typeof renderTalentCreator === 'function') renderTalentCreator();
    renderTalentMapper();
}

function initTalentMapper() {
    const canvas = document.getElementById('talent-mapper-canvas');
    if (!canvas) return;
    if (canvas._talentMapperInitialized) return;
    canvas._talentMapperInitialized = true;

    const updateCanvasSize = () => {
        syncTalentCanvasSize();
        renderTalentMapper();
    };
    
    if (!talentMapperCanvasInitialized) {
        window.addEventListener('resize', updateCanvasSize);
        talentMapperCanvasInitialized = true;
    }
    const { w, h } = syncTalentCanvasSize();

    // Centrar cámara en el origen (0,0) la primera vez
    if (talentPanOffset.x === 0 && talentPanOffset.y === 0) {
        talentPanOffset.x = w / 2;
        talentPanOffset.y = h / 2;
    }

    // Desactivar menú contextual del navegador para permitir paneo limpio con click derecho
    canvas.oncontextmenu = (e) => e.preventDefault();

    // Mouse event positions
    let mousePos = { x: 0, y: 0 };

    // Convertir coordenadas de pantalla a coordenadas del mundo
    const screenToWorld = (screenX, screenY) => ({
        x: (screenX - talentPanOffset.x) / talentZoom,
        y: (screenY - talentPanOffset.y) / talentZoom
    });

    // Helper inverso para hit-testing preciso en pantalla
    const worldToScreen = (wx, wy) => ({
        x: wx * talentZoom + talentPanOffset.x,
        y: wy * talentZoom + talentPanOffset.y
    });

    const getNodeAtPosition = (mx, my) => {
        if (!config.talentsConfig.nodes) return null;
        
        // Buscar en orden inverso (últimos dibujados primero)
        const nodeEntries = Object.entries(config.talentsConfig.nodes);
        for (let i = nodeEntries.length - 1; i >= 0; i--) {
            const [id, pos] = nodeEntries[i];
            const nodeType = pos.nodeType || 'small';
            const typeInfo = NODE_TYPES[nodeType] || NODE_TYPES.small;
            
            // Hit-test en coordenadas visibles de pantalla
            const s = worldToScreen(pos.x, pos.y);
            const radiusOnScreen = Math.max(typeInfo.radius * talentZoom, typeInfo.radius * 0.35);
            const dist = Math.hypot(s.x - mx, s.y - my);
            if (dist <= radiusOnScreen + 6) {
                return id;
            }
        }
        return null;
    };

    // Buscar conexión más cercana a un punto (en píxeles de pantalla)
    const getConnectionAtPosition = (mx, my) => {
        const conns = config.talentsConfig.connections || [];
        const nds = config.talentsConfig.nodes || {};
        let bestDist = 14; // radio de tolerancia en píxeles de pantalla
        let bestIdx = -1;
        conns.forEach((conn, i) => {
            const from = nds[conn.from];
            const to = nds[conn.to];
            if (!from || !to) return;
            const start = worldToScreen(from.x, from.y);
            const end = worldToScreen(to.x, to.y);
            
            const dx = end.x - start.x;
            const dy = end.y - start.y;
            const lenSq = dx * dx + dy * dy;
            let t = lenSq > 0 ? ((mx - start.x) * dx + (my - start.y) * dy) / lenSq : 0;
            t = Math.max(0, Math.min(1, t));
            const px = start.x + t * dx;
            const py = start.y + t * dy;
            const dist = Math.hypot(mx - px, my - py);
            if (dist < bestDist) {
                bestDist = dist;
                bestIdx = i;
            }
        });
        return bestIdx;
    };

    canvas.onmousedown = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mx = e.clientX - rect.left;
        const my = e.clientY - rect.top;
        mousePos = { x: mx, y: my };

        // Click derecho: si toca conexión, desconecta; si no, inicia paneo libre
        if (e.button === 2) {
            e.preventDefault();
            const connIdx = getConnectionAtPosition(mx, my);
            if (connIdx >= 0) {
                config.talentsConfig.connections.splice(connIdx, 1);
                renderTalentMapper();
                return;
            }
            isPanningTalents = true;
            panStart = { x: e.clientX, y: e.clientY };
            canvas.style.cursor = 'move';
            return;
        }

        // Click con rueda del ratón (botón central): paneo libre
        if (e.button === 1) {
            e.preventDefault();
            isPanningTalents = true;
            panStart = { x: e.clientX, y: e.clientY };
            canvas.style.cursor = 'move';
            return;
        }

        const clickedNodeId = getNodeAtPosition(mx, my);

        if (clickedNodeId) {
            if (talentMapperTool === 'select' || talentMapperTool === undefined) {
                if (e.detail === 2) {
                    showTalentNodeEditor(clickedNodeId);
                } else {
                    isDraggingTalentNode = true;
                    dragNodeId = clickedNodeId;
                    selectedTalentNodeId = clickedNodeId;
                    canvas.style.cursor = 'grabbing';
                    showTalentNodeEditor(clickedNodeId);
                }
            } else if (talentMapperTool === 'connect') {
                connectStartNodeId = clickedNodeId;
            } else if (talentMapperTool === 'disconnect') {
                // En modo desconectar, clic en nodo elimina todas sus conexiones
                if (!config.talentsConfig.connections) config.talentsConfig.connections = [];
                config.talentsConfig.connections = config.talentsConfig.connections.filter(c => c.from !== clickedNodeId && c.to !== clickedNodeId);
                renderTalentMapper();
            }
        } else {
            // En modo desconectar, clic en vacío puede cortar conexión cercana
            if (talentMapperTool === 'disconnect') {
                const connIdx = getConnectionAtPosition(mx, my);
                if (connIdx >= 0) {
                    config.talentsConfig.connections.splice(connIdx, 1);
                    renderTalentMapper();
                    return;
                }
            }
            // Panning normal con click izquierdo en fondo vacío
            isPanningTalents = true;
            panStart = { x: e.clientX, y: e.clientY };
            canvas.style.cursor = 'move';
            selectedTalentNodeId = null;
            document.getElementById('talent-node-editor-card').style.display = 'none';
        }
        renderTalentMapper();
    };

    canvas.onmousemove = (e) => {
        const rect = canvas.getBoundingClientRect();
        const mx = e.clientX - rect.left;
        const my = e.clientY - rect.top;
        mousePos = { x: mx, y: my };

        if (isDraggingTalentNode && dragNodeId) {
            const world = screenToWorld(mx, my);
            config.talentsConfig.nodes[dragNodeId].x = Math.round(world.x);
            config.talentsConfig.nodes[dragNodeId].y = Math.round(world.y);
            renderTalentMapper(null, { canvasOnly: true });
        } else if (isPanningTalents) {
            const dx = e.clientX - panStart.x;
            const dy = e.clientY - panStart.y;
            talentPanOffset.x += dx;
            talentPanOffset.y += dy;
            panStart = { x: e.clientX, y: e.clientY };
            clampPanOffset();
            renderTalentMapper(null, { canvasOnly: true });
        } else if (connectStartNodeId) {
            renderTalentMapper(mousePos, { canvasOnly: true });
        } else {
            // Hover detection para tooltip
            const hoveredNode = getNodeAtPosition(mx, my);
            if (hoveredNode !== talentMapperHoveredNode) {
                talentMapperHoveredNode = hoveredNode;
                if (hoveredNode) {
                    canvas.style.cursor = talentMapperTool === 'connect' ? 'crosshair' : 'pointer';
                    showTalentTooltip(hoveredNode, mx, my);
                } else {
                    canvas.style.cursor = 'grab';
                    hideTalentTooltip();
                }
                renderTalentMapper(null, { canvasOnly: true });
            } else if (hoveredNode) {
                showTalentTooltip(hoveredNode, mx, my);
            }
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
            renderTalentMapper(); // estructura cambió (pos nodos)
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

    // Zoom fluido exponencial con rueda del mouse hacia la posición del cursor
    canvas.addEventListener('wheel', (e) => {
        e.preventDefault();
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;
        
        const oldZoom = talentZoom;
        const zoomFactor = e.deltaY < 0 ? 1.15 : (1 / 1.15);
        talentZoom = Math.max(TALENT_ZOOM_MIN, Math.min(TALENT_ZOOM_MAX, parseFloat((talentZoom * zoomFactor).toFixed(2))));
        
        // Zoom focalizado en la posición del cursor del ratón
        const zoomRatio = talentZoom / oldZoom;
        talentPanOffset.x = mouseX - (mouseX - talentPanOffset.x) * zoomRatio;
        talentPanOffset.y = mouseY - (mouseY - talentPanOffset.y) * zoomRatio;
        
        clampPanOffset();
        updateZoomDisplay();
        renderTalentMapper(null, { canvasOnly: true });
    }, { passive: false });

    // Ocultar tooltip y detener paneo al salir del canvas
    canvas.onmouseleave = () => {
        isPanningTalents = false;
        isDraggingTalentNode = false;
        hideTalentTooltip();
    };

    // Drag & Drop: arrastrar talentos desde el panel al canvas
    canvas.ondragover = (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'copy';
    };
    canvas.ondrop = (e) => {
        e.preventDefault();
        const talentId = e.dataTransfer.getData('text/plain');
        if (!talentId) return;
        const rect = canvas.getBoundingClientRect();
        const mx = e.clientX - rect.left;
        const my = e.clientY - rect.top;
        const world = screenToWorld(mx, my);
        if (!config.talentsConfig.nodes) config.talentsConfig.nodes = {};
        config.talentsConfig.nodes[talentId] = {
            x: Math.round(world.x),
            y: Math.round(world.y),
            nodeType: 'small'
        };
        if (typeof renderTalentCreator === 'function') renderTalentCreator();
        renderTalentMapper();
    };

    // Loop de animación para nodos notable/keystone (glow pulsante, aura rotatoria)
    let lastTalentAnimFrame = 0;
    const talentAnimLoop = (ts) => {
        if (ts - lastTalentAnimFrame > 33) {
            lastTalentAnimFrame = ts;
            const canvasEl = document.getElementById('talent-mapper-canvas');
            if (canvasEl && canvasEl.offsetParent !== null) {
                const nodes = config.talentsConfig.nodes || {};
                const hasAnimatedNodes = Object.values(nodes).some(n => n.nodeType === 'notable' || n.nodeType === 'keystone');
                if (hasAnimatedNodes || selectedTalentNodeId || talentMapperHoveredNode || connectStartNodeId) {
                    // Solo canvas: NO repintar la lista lateral (rompería los clics)
                    renderTalentMapper(null, { canvasOnly: true });
                }
            }
        }
        requestAnimationFrame(talentAnimLoop);
    };
    requestAnimationFrame(talentAnimLoop);

    renderTalentMapper();
}

function showTalentNodeEditor(nodeId) {
    const card = document.getElementById('talent-node-editor-card');
    const content = document.getElementById('talent-node-editor-content');
    if (!card || !content) return;

    const talent = config.talentsConfig.talents.find(t => t.id === nodeId);
    if (!talent) return;

    const nodeData = (config.talentsConfig.nodes || {})[nodeId];
    const currentType = nodeData?.nodeType || 'small';

    card.style.display = 'block';
    try { card.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); } catch (e) {}
    
    // Generar campos de edición rápida del nodo mapeado
    content.innerHTML = `
        <div style="font-size: 1.8rem; text-align:center; margin-bottom: 10px; display:flex; justify-content:center;">${assetIconHtml(talent.icon, { size: 40, fallback: '🌀', emojiSize: '32px', emptyHtml: '🌳', style: 'width:40px;height:40px;object-fit:contain;border-radius:10px;border:1px solid rgba(255,255,255,0.12);background:rgba(0,0,0,0.3);' })}</div>
        <div style="font-weight:bold; color:var(--accent); text-align:center; margin-bottom: 15px;">${talent.name}</div>
        
        <div class="field" style="margin-bottom: 12px;">
            <label style="color: var(--accent); font-size: 0.75rem; margin-bottom: 4px; display: block;">🏷️ Tipo de Nodo</label>
            <select onchange="updateTalentNodeType('${nodeId}', this.value)" style="width: 100%; background: var(--surface); border: 1px solid rgba(255,255,255,0.1); border-radius: 6px; color: white; padding: 8px; font-size: 0.8rem;">
                <option value="small" ${currentType === 'small' ? 'selected' : ''}>🟢 Pequeño (Básico)</option>
                <option value="notable" ${currentType === 'notable' ? 'selected' : ''}>🟡 Notable (Importante)</option>
                <option value="keystone" ${currentType === 'keystone' ? 'selected' : ''}>🔴 Clave (Cambio de Build)</option>
            </select>
            <div style="font-size: 0.65rem; color: #888; margin-top: 4px;">${NODE_TYPES[currentType]?.label || 'Pequeño'} - Radio: ${NODE_TYPES[currentType]?.radius || 22}px</div>
        </div>
        
        <div class="field" style="margin-bottom: 12px;">
            <label style="color: var(--text-dim); font-size: 0.75rem; margin-bottom: 4px; display: block;">📍 Posición X</label>
            <input type="number" value="${nodeData?.x || 0}" onchange="config.talentsConfig.nodes['${nodeId}'].x = parseInt(this.value); renderTalentMapper();" style="width: 100%; background: var(--surface); border: 1px solid rgba(255,255,255,0.1); border-radius: 6px; color: white; padding: 8px; font-size: 0.8rem;">
        </div>
        
        <div class="field" style="margin-bottom: 12px;">
            <label style="color: var(--text-dim); font-size: 0.75rem; margin-bottom: 4px; display: block;">📍 Posición Y</label>
            <input type="number" value="${nodeData?.y || 0}" onchange="config.talentsConfig.nodes['${nodeId}'].y = parseInt(this.value); renderTalentMapper();" style="width: 100%; background: var(--surface); border: 1px solid rgba(255,255,255,0.1); border-radius: 6px; color: white; padding: 8px; font-size: 0.8rem;">
        </div>
        
        <div style="display:flex; flex-direction:column; gap:10px; margin-top: 20px; padding-top: 15px; border-top: 1px solid rgba(255,255,255,0.1);">
            <button class="btn btn-secondary" style="background:#ff3b30; border-color:#ff3b30; color:white; margin:0;" onclick="removeTalentFromMap('${nodeId}')">❌ Quitar del Mapa</button>
        </div>
    `;
}
window.showTalentNodeEditor = showTalentNodeEditor;

window.updateTalentNodeType = function(nodeId, newType) {
    if (!config.talentsConfig.nodes || !config.talentsConfig.nodes[nodeId]) return;
    config.talentsConfig.nodes[nodeId].nodeType = newType;
    renderTalentMapper();
    showTalentNodeEditor(nodeId);
    if (typeof renderTalentCreator === 'function') renderTalentCreator();
};

window.submitBugReply = function(id, source) {
    const inputEl = document.getElementById(`reply-input-${id}-${source}`);
    if (!inputEl) return;
    const replyText = inputEl.value.trim();
    if (!replyText) {
        showToast("ERROR: La respuesta no puede estar vacía.");
        return;
    }
    
    const sock = bugReportSocket(source);
    if (sock) {
        sock.emit('replyToBugReport', { id, replyText });
        inputEl.value = '';
    } else {
        showToast("ERROR: Conexión no disponible con el servidor.");
    }
};

window.closeBugReport = function(id, source) {
    if (!confirm(`¿Finalizar y cerrar definitivamente el reporte de bug #${id}? El usuario ya no podrá responder.`)) return;
    const sock = bugReportSocket(source);
    if (sock) {
        sock.emit('closeBugReport', { id });
    } else {
        showToast("ERROR: Conexión no disponible con el servidor.");
    }
};


