require('dotenv').config(); // v6.01 - Auto-trigger reload
const express = require('express');
const app = express();
const http = require('http').createServer(app);
const cors = require('cors');
app.use(cors());
const io = require('socket.io')(http, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});
const path = require('path');
const fs = require('fs-extra');
const mongoose = require('mongoose');
const Logger = require('./utils/logger');

const normalizeZone = (z) => {
    if (z === undefined || z === null) return 1;
    if (typeof z === 'string') {
        if (z.startsWith('extract_')) {
            const parts = z.split('_');
            return parseInt(parts[1]) || 10;
        }
        if (z.startsWith('dungeon_') || z.startsWith('dungeon')) {
            return 99;
        }
        if (!isNaN(z) && z.trim() !== '') {
            return Number(z);
        }
        return z;
    }
    return z;
};

// Modelos y Módulos de Seguridad
const User = require('./models/User');
const Session = require('./models/Session'); // v302.8: Auditoría de Sesiones
const Clan = require('./models/Clan'); // v242.10: Gestión de Flotas
const bcrypt = require('bcrypt'); // Criptografía Pro v35.0

// v1.1: Handlers y Sistemas Modulares
const { getClanDataPayload, registerClanHandlers } = require('./events/clanHandlers');
const { registerCombatHandlers } = require('./systems/combatHandlers');
const { registerInventoryHandlers } = require('./systems/inventoryHandlers');
const { applyZoneRules } = require('./systems/deathDropHelper');
const { registerTradeHandlers } = require('./systems/tradeHandlers');
const { registerZoneHandlers } = require('./handlers/zoneHandler');
const { registerMovementHandlers } = require('./handlers/movementHandler');
const { registerVaultHandlers } = require('./systems/vaultHandlers');
const { registerPartyHandlers } = require('./handlers/partyHandlers');
const { registerSkillHandlers } = require('./handlers/skillHandlers');
const { registerHousingHandlers } = require('./systems/housingHandlers');

const AIManager = require('./systems/AIManager');
const { startGameLoop } = require('./systems/gameLoop');
const HordeManager = require('./events/HordeManager');
const { calculateFinalStats } = require('./systems/statCalculator'); // v266.135: Sistema de Stats Dinámicos
const extractionManager = require('./systems/extractionManager');
const lootManager = require('./systems/lootManager');
const altarDefenseManager = require('./systems/altarDefenseManager');
const arenaManager = require('./systems/arenaManager');


// Configuración
const PORT = process.env.PORT || 3333;
const CONFIG_FILE = path.join(__dirname, 'config.json');
const CLIENT_CONFIG_KEYS = [
    'vaultConfig',
    'inventoryConfig',
    'ammoMultipliers',
    'hordeConfig',
    'mapsConfig',
    'shipModels',
    'shopItems',
    'skillsData',
    'pilotConfig',
    'gameModes',
    'craftingRecipes',
    'housingConfig',
    'questsConfig',
    'enemyModels',
    'mechanicsLib',
    'movementLib',
    'defenseLib',
    'ammoMechLib',
    'ambienceLib',
    'talentsConfig'
];

const buildClientConfig = (config) => {
    if (!config || typeof config !== 'object') return config;
    const clientConfig = {};
    CLIENT_CONFIG_KEYS.forEach(key => {
        if (config[key] !== undefined) clientConfig[key] = config[key];
    });
    return clientConfig;
};

const isAdminSocket = (socket) => {
    return !!(socket && socket.dbUser && socket.dbUser.username && socket.dbUser.username.toLowerCase() === 'caelli94');
};

const emitConfigForSocket = (socket, eventName, config) => {
    socket.emit(eventName, isAdminSocket(socket) ? config : buildClientConfig(config));
};

const broadcastConfigUpdate = (io, config) => {
    io.sockets.sockets.forEach(socket => {
        emitConfigForSocket(socket, 'adminConfigUpdated', config);
    });
};

// Conexi├│n a MongoDB
mongoose.connect(process.env.MONGODB_URI)
    .then(() => {
        Logger.success('DB', 'Conectado a MongoDB Atlas');
        startServer();
    })
    .catch(err => {
        Logger.error('DB', `Error de conexión: ${err.message}`);
        console.log('Asegurate de que MongoDB esté corriendo o que el URI en .env sea correcto.');
    });

// Asegurar que archivos existan
if (!fs.existsSync(CONFIG_FILE)) fs.writeJsonSync(CONFIG_FILE, null);

// Middleware para que Godot Web funcione (SharedArrayBuffer support) v1.0
app.use((req, res, next) => {
    res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
    res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
    next();
});

// Servir archivos estáticos desde la carpeta 'public'
app.use(express.static(path.join(__dirname, 'public')));
app.use('/assets', express.static(path.join(__dirname, '../descon/assets')));

app.post('/api/upload-asset', express.json({ limit: '20mb' }), async (req, res) => {
    try {
        const { fileName, fileData } = req.body;
        if (!fileName || !fileData) {
            return res.status(400).json({ error: 'Faltan parámetros fileName o fileData' });
        }
        const targetDir = path.join(__dirname, '../descon/assets/Crafteo');
        await fs.ensureDir(targetDir);
        const filePath = path.join(targetDir, fileName);
        const buffer = Buffer.from(fileData, 'base64');
        await fs.writeFile(filePath, buffer);
        const godotPath = `res://assets/Crafteo/${fileName}`;
        console.log(`[ASSET UPLOAD] Guardado asset local en ${filePath}`);
        return res.json({ success: true, path: godotPath });
    } catch (err) {
        console.error('[ASSET UPLOAD ERROR]', err);
        return res.status(500).json({ error: err.message });
    }
});

// v1.0: Endpoint para resolver la ruta res:// de un asset existente sin copiarlo
// Busca recursivamente en la carpeta de assets del proyecto y devuelve la ruta Godot
app.get('/api/find-asset', async (req, res) => {
    const { fileName } = req.query;
    if (!fileName) return res.status(400).json({ error: 'Parámetro fileName requerido' });

    const assetsDir = path.join(__dirname, '../descon/assets');
    const projectRoot = path.join(__dirname, '../descon');

    const findFileRecursive = async (dir, name) => {
        let entries;
        try {
            entries = await fs.readdir(dir, { withFileTypes: true });
        } catch (e) {
            return null;
        }
        for (const entry of entries) {
            const fullPath = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                const found = await findFileRecursive(fullPath, name);
                if (found) return found;
            } else if (entry.name === name) {
                return fullPath;
            }
        }
        return null;
    };

    try {
        const found = await findFileRecursive(assetsDir, fileName);
        if (!found) {
            return res.json({ success: false, error: `"${fileName}" no encontrado en los assets del proyecto. Asegurate de que el archivo esté dentro de la carpeta descon/assets.` });
        }
        // Convertir la ruta absoluta a ruta res:// de Godot
        const relative = path.relative(projectRoot, found).replace(/\\/g, '/');
        const godotPath = `res://${relative}`;
        console.log(`[FIND ASSET] Resuelto: ${fileName} → ${godotPath}`);
        return res.json({ success: true, path: godotPath });
    } catch (err) {
        console.error('[FIND ASSET ERROR]', err);
        return res.status(500).json({ error: err.message });
    }
});

const state = require('./state');
const { players, activeSessions, enemies, activeAreas, parties, playerParty } = state;

// v370.1: Inicializar monitores de rendimiento AAA en RAM
state.performance = {
    // Tick metrics
    avgTickTime: 0,
    maxTickTime: 0,
    lastTickDuration: 0,
    p99TickTime: 0,   // Percentil 99 de latencia de tick
    p50TickTime: 0,   // Mediana real del tick
    // CPU / Memoria
    memoryUsage: {},
    cpuUsage: 0,
    rssHistory: [],   // Últimos 60 samples de RSS (MB)
    heapHistory: [],  // Últimos 60 samples de heapUsed (MB)
    // Red — bytes globales
    network: {
        totalBytesSent: 0,
        totalBytesReceived: 0
    },
    // PPS (Paquetes por Segundo) — globales del proceso
    ppsIn: 0,
    ppsOut: 0,
    // Acumuladores internos entre intervalos
    _pktIn: 0,
    _pktOut: 0,
    _bytesOutAcc: 0,  // Acumulador de egreso en el intervalo
    _bytesInAcc: 0
};

let lastCpuUsage = process.cpuUsage();
let lastCpuTime = Date.now();

// v370.1: Intervalo AAA de métricas (2s)
setInterval(() => {
    const elapsedMs = Date.now() - lastCpuTime;
    if (elapsedMs <= 0) return;
    const usage = process.cpuUsage(lastCpuUsage);
    lastCpuUsage = process.cpuUsage();
    lastCpuTime = Date.now();
    
    // CPU del proceso Node.js (no de la VM completa)
    const totalMs = (usage.user + usage.system) / 1000;
    const cpusCount = require('os').cpus().length || 1;
    const percent = (totalMs / elapsedMs) * 100 / cpusCount;
    state.performance.cpuUsage = parseFloat(percent.toFixed(2));
    
    // Memoria — sample actual
    const mem = process.memoryUsage();
    const rssMB  = parseFloat((mem.rss      / 1024 / 1024).toFixed(2));
    const heapMB = parseFloat((mem.heapUsed / 1024 / 1024).toFixed(2));
    state.performance.memoryUsage = {
        heapUsed:  heapMB,
        heapTotal: parseFloat((mem.heapTotal / 1024 / 1024).toFixed(2)),
        rss:       rssMB
    };
    
    // Historial circular de memoria (máx 60 puntos = 2 minutos)
    state.performance.rssHistory.push(rssMB);
    state.performance.heapHistory.push(heapMB);
    if (state.performance.rssHistory.length  > 60) state.performance.rssHistory.shift();
    if (state.performance.heapHistory.length > 60) state.performance.heapHistory.shift();
    
    // PPS calculado sobre el intervalo de 2s
    const elapsedSec = elapsedMs / 1000;
    state.performance.ppsIn  = parseFloat((state.performance._pktIn  / elapsedSec).toFixed(1));
    state.performance.ppsOut = parseFloat((state.performance._pktOut / elapsedSec).toFixed(1));
    state.performance._pktIn  = 0;
    state.performance._pktOut = 0;
    
    // Sincronizar acumuladores de bytes al contador global
    state.performance.network.totalBytesSent     += state.performance._bytesOutAcc;
    state.performance.network.totalBytesReceived += state.performance._bytesInAcc;
    state.performance._bytesOutAcc = 0;
    state.performance._bytesInAcc  = 0;
}, 2000);

// v370.0: Almacenamiento de invitaciones activas de Defensa del Altar
const altarDefenseInvites = new Map();

// v1.4: Inicialización de Sistemas Maestros
const aiManager = new AIManager(io, state, null);
const hordeManager = new HordeManager(io, (...args) => aiManager.serverSpawnEnemy(...args), enemies);
aiManager.hordeManager = hordeManager;

// v1.5: Inicio del Corazón del Servidor
extractionManager.init(io, state, aiManager);
altarDefenseManager.init(io, state, aiManager);
arenaManager.init(io, state);
startGameLoop(io, state, aiManager);
lootManager.startCleanupTimer(io, state);


// v243.15: Helper para serializar datos de clan con roles y estados
// v243.15: getClanDataPayload ahora reside en events/clanHandlers.js

// v244.20: Función Maestra de Inicialización de Sesión (Login/Register)
const handleUserLogin = async (socket, user, username) => {
    // SEGURIDAD ANTI-MULTILOGIN v33.0: Desconectar sesión anterior (Case Insensitive)
    const lowName = username.toLowerCase();
    if (activeSessions.has(lowName)) {
        const oldSocketId = activeSessions.get(lowName);
        const oldSocket = io.sockets.sockets.get(oldSocketId);
        if (oldSocket) {
            oldSocket.emit('authError', 'SESIÓN CERRADA: Se ha detectado un nuevo ingreso con esta cuenta.');
            oldSocket.disconnect();
        } else {
        }
        // v301.7: Purga física inmediata de la sesión y jugador anterior para evitar clones fantasmas en reconexiones rápidas
        if (players[oldSocketId]) {
            const oldP = players[oldSocketId];
            if (state.playersByZone[oldP.zone] && state.playersByZone[oldP.zone][oldSocketId]) {
                delete state.playersByZone[oldP.zone][oldSocketId];
            }
            await savePlayerToDB(oldSocketId);
            io.to(`zone_${oldP.zone}`).emit('playerDisconnected', oldSocketId);
            delete players[oldSocketId];
        } else {
        }
    } else {
    }
    activeSessions.set(lowName, socket.id);

    user.lastLogin = new Date();
    // v305.1: Actualizar última conexión (Eliminado guardado redundante aquí para consolidar abajo)
    
    socket.dbUser = user;

    const dbId = user._id.toString();

    // v190.85: Sincronía de Stats Base desde Admin Config (server-side start)
    let baseHp = 2000; let baseSh = 1000;
    const shipId = user.gameData.currentShipId || 1;
    try {
        const config = await fs.readJson(CONFIG_FILE);
        if (config && config.shipModels) {
            const model = config.shipModels.find(m => m.id === shipId);
            if (model) {
                baseHp = model.hp; baseSh = model.shield;
            }
        }
    } catch (e) { }

    // v214.120: Sincronía Maestra al Login (Garantizar que 'equipped' global no esté vacío)
    const resolvedEquip = (function () {
        const ebs = user.gameData.equippedByShip;
        const sid = (user.gameData.currentShipId || 1).toString();
        let raw = { w: [], s: [], e: [], x: [] };
        if (ebs) {
            if (typeof ebs.get === 'function') { raw = ebs.get(sid) || raw; }
            else { raw = ebs[sid] || raw; }
        }
        if ((!raw.w || raw.w.length == 0) && (user.gameData.equipped && user.gameData.equipped.w && user.gameData.equipped.w.length > 0)) {
            raw = user.gameData.equipped;
        }
        return JSON.parse(JSON.stringify(raw));
    })();

    // v235.50: Migración Híbrida de Slots (Garantizar 4 slots para todos)
    if (!user.gameData.spheres || user.gameData.spheres.length < 4) {
        if (!user.gameData.spheres) user.gameData.spheres = [];
        while (user.gameData.spheres.length < 4) {
            const idx = user.gameData.spheres.length + 1;
            user.gameData.spheres.push({ "name": `Slot ${idx}`, "type": "any", "color": "#ffffff", "equipped": null });
        }
        user.markModified('gameData.spheres');
        await user.save();
    }

    // v266.130: Inicialización de Slots de Layout del HUD (Máx 4)
    if (!user.gameData.hudLayouts || user.gameData.hudLayouts.length < 4) {
        if (!user.gameData.hudLayouts) user.gameData.hudLayouts = [];
        while (user.gameData.hudLayouts.length < 4) {
            const idx = user.gameData.hudLayouts.length + 1;
            user.gameData.hudLayouts.push({ "id": idx, "name": `Layout ${idx}`, "positions": {} });
        }
        user.markModified('gameData.hudLayouts');
        await user.save();
    }

    // v244.110: Obtener Siglas del Clan para visualización in-game
    let clanTag = "";
    if (user.gameData.clanId) {
        try {
            const clan = await Clan.findById(user.gameData.clanId);
            if (clan) clanTag = clan.tag;
        } catch (e) { console.error("Error obteniendo tag para login:", e); }
    }

    const pc = state.SERVER_CONFIG?.pilotConfig || {};
    const startShip = pc.startingShipId || 1;
    const startZone = pc.startingMapId || 1;

    // Normalización de munición y selectedAmmo (Garantizar compatibilidad con cuentas existentes)
    const rawUser = user.toObject({ defaults: false });
    const rawAmmo = rawUser.gameData ? rawUser.gameData.ammo : null;
    const rawSelected = rawUser.gameData ? rawUser.gameData.selectedAmmo : null;

    let ammoModified = false;
    var ammoReset = false;
    if (!rawAmmo || typeof rawAmmo === 'string' || rawAmmo instanceof String) {
        ammoReset = true;
    } else if (!rawAmmo.laser) {
        ammoReset = true;
    }

    if (ammoReset) {
        user.gameData.ammo = undefined;
        user.gameData.ammo = {
            laser: [1000, 0, 0, 0, 0, 0],
            missile: [50, 0, 0, 0, 0, 0],
            mine: [10, 0, 0, 0, 0, 0],
            melee: [0, 0, 0, 0, 0, 0],
            heal: [0, 0, 0, 0, 0, 0],
            siphon: [0, 0, 0, 0, 0, 0],
            emp: [0, 0, 0, 0, 0, 0],
            electron: [0, 0, 0, 0, 0, 0]
        };
        ammoModified = true;
    }

    const defaultAmmo = {
        laser: [1000, 0, 0, 0, 0, 0],
        missile: [50, 0, 0, 0, 0, 0],
        mine: [10, 0, 0, 0, 0, 0],
        melee: [0, 0, 0, 0, 0, 0],
        heal: [0, 0, 0, 0, 0, 0],
        siphon: [0, 0, 0, 0, 0, 0],
        emp: [0, 0, 0, 0, 0, 0],
        electron: [0, 0, 0, 0, 0, 0]
    };
    
    // Si no se reseteó por completo, normalizar tiers
    if (!ammoReset) {
        for (const key in defaultAmmo) {
            if (!user.gameData.ammo[key] || !Array.isArray(user.gameData.ammo[key]) || user.gameData.ammo[key].length < 6) {
                var baseArr = Array.isArray(user.gameData.ammo[key]) ? user.gameData.ammo[key] : [];
                while (baseArr.length < 6) {
                    baseArr.push(key === "laser" && baseArr.length === 0 ? 1000 : (key === "missile" && baseArr.length === 0 ? 50 : (key === "mine" && baseArr.length === 0 ? 10 : 0)));
                }
                user.gameData.ammo[key] = baseArr;
                ammoModified = true;
            }
        }
    }

    var selectedReset = false;
    if (!rawSelected || typeof rawSelected === 'string' || rawSelected instanceof String) {
        selectedReset = true;
    } else if (rawSelected.laser === undefined) {
        selectedReset = true;
    }

    if (selectedReset) {
        user.gameData.selectedAmmo = undefined;
        user.gameData.selectedAmmo = { laser: 0, missile: 0, mine: 0, melee: 0, heal: 0, siphon: 0, emp: 0, electron: 0 };
        ammoModified = true;
    } else {
        const defaultSelected = { laser: 0, missile: 0, mine: 0, melee: 0, heal: 0, siphon: 0, emp: 0, electron: 0 };
        for (const key in defaultSelected) {
            if (user.gameData.selectedAmmo[key] === undefined) {
                user.gameData.selectedAmmo[key] = defaultSelected[key];
                ammoModified = true;
            }
        }
    }

    if (ammoModified) {
        user.markModified('gameData.ammo');
        user.markModified('gameData.selectedAmmo');
        await user.save();
    }

    players[socket.id] = {
        id: dbId,
        dbId: dbId,
        socketId: socket.id,
        num: state.nextPlayerNum++,
        user: username,
        clanTag: clanTag, // v244.110: Siglas para el NameTag
        x: user.gameData.lastPos?.x || (user.gameData.zone === startZone ? 1000 : 2000),
        y: user.gameData.lastPos?.y || (user.gameData.zone === startZone ? 1000 : 2000),
        rotation: 0,
        hp: (user.gameData.hp !== undefined) ? user.gameData.hp : baseHp,
        maxHp: baseHp,
        shield: (user.gameData.shield !== undefined) ? user.gameData.shield : baseSh,
        maxShield: baseSh,
        level: user.gameData.level || 1,
        skillPoints: user.gameData.skillPoints || 0,
        skillTree: JSON.parse(JSON.stringify(user.gameData.skillTree || {
            engineering: [0, 0, 0, 0, 0, 0, 0, 0],
            combat: [0, 0, 0, 0, 0, 0, 0, 0],
            science: [0, 0, 0, 0, 0, 0, 0, 0]
        })),
        baseHp: baseHp,
        baseShield: baseSh,
        ammo: JSON.parse(JSON.stringify(user.gameData.ammo)),
        equipped: resolvedEquip,
        spheres: JSON.parse(JSON.stringify(user.gameData.spheres || [])),
        hudConfig: JSON.parse(JSON.stringify(user.gameData.hudConfig || {})),
        hudPositions: JSON.parse(JSON.stringify((user.gameData.hudPositions && Object.keys(user.gameData.hudPositions).length > 0) ? user.gameData.hudPositions : (pc.defaultLayout || {}))),
        hudLayouts: JSON.parse(JSON.stringify(user.gameData.hudLayouts || [])), // v266.130: Slots múltiples
        hubs: (user.gameData.hubs !== undefined) ? user.gameData.hubs : (pc.startingHubs || 0),
        ohcu: (user.gameData.ohcu !== undefined) ? user.gameData.ohcu : (pc.startingOhcu || 0),
        exp: user.gameData.exp || 0,
        clanId: user.gameData.clanId, // v244.110: Mantener referencia para filtros de combate
        currentShipId: user.gameData.currentShipId || startShip,
        zone: user.gameData.zone || startZone,
        pvpEnabled: !!user.gameData.pvpEnabled,
        lastPos: { x: user.gameData.lastPos?.x || 2000, y: user.gameData.lastPos?.y || 2000 },
        lastPvpCombatTime: 0,
        lastCombatTime: 0,
        clanId: user.gameData.clanId,
        isInvulnerable: false,
        isDead: (user.gameData.hp !== undefined && user.gameData.hp <= 0),
        isAdmin: (user.username.toLowerCase() === "caelli94") // v266.700: Bypass Maestro
    };

    const p_ref = players[socket.id];
    
    // v266.135: Cálculo Maestro de Stats (Base + Ítems + Skills)
    calculateFinalStats(p_ref, state.SERVER_CONFIG);

    // Aplicar reglas de zona (PvP obligatorio, etc) al loguear
    applyZoneRules(p_ref, socket, io, state);

    // Indexar jugador en playersByZone
    const loginZone = p_ref.zone || 1;
    if (!state.playersByZone[loginZone]) {
        state.playersByZone[loginZone] = {};
    }
    state.playersByZone[loginZone][socket.id] = p_ref;

    let adminConfig = null;
    try { adminConfig = await fs.readJson(CONFIG_FILE); } catch (e) { }

    const eByShipObj = {};
    if (user.gameData.equippedByShip) {
        if (user.gameData.equippedByShip instanceof Map) {
            user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
        } else {
            Object.assign(eByShipObj, user.gameData.equippedByShip);
        }
    }

    // v262.210: MIGRACIÓN (Fix de ítems viejos)
    if (!user.gameData.inventory) user.gameData.inventory = [];
    
    // v266.140: Sincronización PROFUNDA (Inventory + Equipped)
    const allShopItems = [
        ...(state.SERVER_CONFIG.shopItems.weapons || []),
        ...(state.SERVER_CONFIG.shopItems.shields || []),
        ...(state.SERVER_CONFIG.shopItems.engines || []),
        ...(state.SERVER_CONFIG.shopItems.extra || []),
        ...(state.SERVER_CONFIG.shopItems.resources || [])
    ];

    let modified = false;
    const syncItem = (item) => {
        const master = allShopItems.find(w => w.id === item.id);
        if (master) {
            item.name = master.name || item.name;
            item.type = (master.type || item.type || "utility").toLowerCase();
            item.base = master.base || item.base || 0;
            item.color = master.color || item.color;
            item.rarity = master.rarity || item.rarity || 0;
            if (!item.icon) item.icon = master.icon;
            return true;
        }
        return false;
    };

    user.gameData.inventory.forEach(item => {
        if (!item.instanceId) {
            item.instanceId = Date.now() + Math.random().toString(36).substr(2, 5);
            modified = true;
        }
        if (syncItem(item)) modified = true;
    });

    // Sincronizar también ítems ya equipados en el mapa de naves
    if (user.gameData.equippedByShip) {
        const ebs = user.gameData.equippedByShip;
        const keys = (ebs instanceof Map) ? Array.from(ebs.keys()) : Object.keys(ebs);
        keys.forEach(k => {
            const shipEquip = (ebs instanceof Map) ? ebs.get(k) : ebs[k];
            ['w', 's', 'e', 'x'].forEach(slot => {
                if (shipEquip[slot]) shipEquip[slot].forEach(item => {
                    if (syncItem(item)) modified = true;
                });
            });
        });
    }

    if (modified) {
        user.markModified('gameData.inventory');
        user.markModified('gameData.equippedByShip');
        await user.save();
    }

    const loginPayload = {
        id: dbId,
        socketId: socket.id,
        user: username,
        clanTag: clanTag,
        pvpEnabled: !!p_ref.pvpEnabled,
        isInvulnerable: !!p_ref.isInvulnerable,
        gameData: {
            ...JSON.parse(JSON.stringify(user.gameData)),
            pvpEnabled: !!p_ref.pvpEnabled, // SYNC FIX: Usar el valor real en memoria (forzado por reglas de zona en login)
            isInvulnerable: !!p_ref.isInvulnerable,
            equippedByShip: JSON.parse(JSON.stringify(eByShipObj)),
            equipped: JSON.parse(JSON.stringify(user.gameData.equipped || { w: [], s: [], e: [], x: [] }))
        },
        adminConfig: buildClientConfig(adminConfig)
    };
    socket.emit('loginSuccess', loginPayload);

    if (user.gameData.clanId) {
        socket.join(`clan_${user.gameData.clanId}`);
        getClanDataPayload(user.gameData.clanId, state).then(clanData => {
            if (clanData) socket.emit('clanData', clanData);
        });
        io.to(`clan_${user.gameData.clanId}`).emit('clanMemberStatus', { user: username, online: true });
    }

    const userZone = p_ref.zone || 1;
    socket.join(`zone_${userZone}`);

    const currentPlayersInZone = {};
    Object.keys(players).forEach(pId => {
        const p = players[pId];
        if (p.zone === userZone) {
            currentPlayersInZone[pId] = {
                ...p,
                id: pId,
                maxHp: p.maxHp || 2000,
                maxShield: p.maxShield || 1000,
                spheres: p.spheres
            };
        }
    });

    const cleanEnemiesInZone = {};
    Object.values(enemies).forEach(e => {
        if (e.zone === userZone) {
            const { ai, _hookSafetyTimeout, ...data } = e;
            cleanEnemiesInZone[e.id] = data;
        }
    });

    const playerSpawnData = { ...players[socket.id], id: socket.id };
    setTimeout(() => {
        socket.emit('currentPlayers', currentPlayersInZone);
        socket.emit('currentEnemies', cleanEnemiesInZone);
        
        // Sincronizar botines activos de la zona al loguear
        if (state.lootDrops) {
            Object.keys(state.lootDrops).forEach(lootId => {
                const drop = state.lootDrops[lootId];
                if (String(drop.zone) === String(userZone)) {
                    socket.emit('lootSpawned', {
                        id: drop.id,
                        x: drop.x,
                        y: drop.y,
                        zone: drop.zone,
                        expiresAt: drop.expiresAt
                    });
                }
            });
        }
        
        socket.broadcast.to(`zone_${userZone}`).emit('newPlayer', { ...playerSpawnData, spheres: p_ref.spheres });
        io.emit('onlineCount', Object.keys(players).length);
    }, 100);

    if (playerParty[dbId]) {
        const pid = playerParty[dbId];
        if (parties[pid]) {
            setTimeout(() => {
                io.emit('partyUpdate', parties[pid]);
                io.emit('chatMessage', { sender: 'SYSTEM', msg: `${username.toUpperCase()} ha vuelto a la flota.`, channel: 'team', senderId: 'server' });
            }, 500);
        }
    }
    Logger.success('AUTH', `Piloto [${username}] inicializado con éxito.`);

    // v302.9: Registro de Sesión Profesional
    try {
        const newSession = new Session({
            userId: user._id,
            username: username,
            ip: socket.handshake.address || "0.0.0.0",
            loginAt: new Date()
        });
        const savedSession = await newSession.save();
        socket.currentSessionId = savedSession._id;
    } catch (e) {
        console.error("[SESSION-ERR] No se pudo registrar el inicio de sesión:", e);
    }
};

// v239.01: Exportar globales para IAs complejas (v239.03 Fix Init Order)
global.enemies = enemies;
global.serverDespawnClones = (zone) => {
    for (const eid in enemies) {
        if (enemies[eid] && enemies[eid].zone === zone && enemies[eid].name.toUpperCase().includes("CLONE")) {
            io.to(`zone_${zone}`).emit('enemyDeath', eid);
            delete enemies[eid];
        }
    }
};

global.serverClearProjectiles = (zone, bossId) => {
    io.to(`zone_${zone}`).emit('clearEnemyProjectiles', { bossId });
};

// Cargar configuraci├│n inicial
fs.readJson(CONFIG_FILE).then(config => {
    state.SERVER_CONFIG = config || {};
    
    // Inyectar Configuración del Modo Arenas (PvP) por defecto si falta
    if (!state.SERVER_CONFIG.gameModes) state.SERVER_CONFIG.gameModes = {};
    if (!state.SERVER_CONFIG.gameModes.arenas) {
        state.SERVER_CONFIG.gameModes.arenas = {
            enabled: true,
            minPlayers: 2,
            maxPlayers: 6,
            matchDuration: 600000,
            spawnLockTime: 10000,
            maps: ["11"],
            mapConfigs: {
                "11": {
                    width: 10000,
                    height: 10000,
                    nexusRed: { x: 2000, y: 5000, hp: 10000, shield: 5000 },
                    nexusBlue: { x: 8000, y: 5000, hp: 10000, shield: 5000 },
                    spawns: [
                        { name: "Spawn Rojo 1", team: "red", x: 2000, y: 5000, radius: 200 },
                        { name: "Spawn Azul 1", team: "blue", x: 8000, y: 5000, radius: 200 }
                    ],
                    nexusAsset: "E:\\\\Descon\\\\descon\\\\assets\\\\Arenas PVP\\\\3D\\\\Nexos\\\\Nexo1\\\\Nexo1.glb",
                    pillarAsset: "E:\\\\Descon\\\\descon\\\\assets\\\\Arenas PVP\\\\3D\\\\Torres\\\\Torre1\\\\Torre1.glb",
                    pillars: []
                }
            }
        };
        // Guardar configuración para persistir la inyección inicial de arenas
        fs.writeJson(CONFIG_FILE, state.SERVER_CONFIG, { spaces: 4 }).catch(err => {
            console.error("[SERVER] Error al guardar inyección de arenas en config.json:", err);
        });
    }

    // v8.0: Inyección de Habilidades Nativas (Asegurar persistencia tras reinicio)
    if (!state.SERVER_CONFIG.skillsData) state.SERVER_CONFIG.skillsData = {};
    if (!state.SERVER_CONFIG.skillsData["FROST-TRAIL"]) {
        state.SERVER_CONFIG.skillsData["FROST-TRAIL"] = {
            "name": "FROST-TRAIL",
            "type": "Defensa",
            "cd": 15,
            "duration": 5,
            "slow_amount": 0.5, // 50 Puntos de slow
            "radius": 40,
            "canTargetOthers": false
        };
    }
    if (!state.SERVER_CONFIG.skillsData["BARRERA DE VIENTO"]) {
        state.SERVER_CONFIG.skillsData["BARRERA DE VIENTO"] = {
            "name": "BARRERA DE VIENTO",
            "type": "Defensa",
            "cd": 20000,
            "duration": 6,
            "width": 150,
            "range": 400,
            "canTargetOthers": false,
            "targetFilters": {
                "allies": false,
                "enemies": true,
                "bosses": false,
                "players": false
            }
        };
    }
    if (!state.SERVER_CONFIG.skillsData["BALIZA DE CURACION"]) {
        state.SERVER_CONFIG.skillsData["BALIZA DE CURACION"] = {
            "name": "BALIZA DE CURACION",
            "type": "Curación",
            "cd": 18000,
            "duration": 8000,
            "pulse_interval": 1500,
            "heal_amount": 250,
            "range": 500,
            "radius": 200,
            "canTargetOthers": false,
            "targetFilters": {
                "allies": true,
                "enemies": false,
                "bosses": false,
                "players": true
            }
        };
    }
	if (!state.SERVER_CONFIG.skillsData["PROVOCACION"]) {
        state.SERVER_CONFIG.skillsData["PROVOCACION"] = {
            "name": "PROVOCACION",
            "type": "Defensa",
            "cd": 15000,
            "range": 450,
            "radius": 220,
            "taunt_duration": 4000,
            "canTargetOthers": false,
            "targetFilters": {
                "allies": false,
                "enemies": true,
                "bosses": true,
                "players": false
            }
        };
    }
    if (!state.SERVER_CONFIG.skillsData["RESURRECCIÓN"]) {
        state.SERVER_CONFIG.skillsData["RESURRECCIÓN"] = {
            "name": "RESURRECCIÓN",
            "type": "Utilidad",
            "cd": 45000,
            "revive_hp_pct": 50,
            "revive_shield_pct": 20,
            "range": 500,
            "radius": 200,
            "canTargetOthers": true,
            "targetFilters": {
                "allies": true,
                "enemies": false,
                "bosses": false,
                "players": true,
                "clan": true
            }
        };
    }
    if (!state.SERVER_CONFIG.skillsData["ESFERA DE TERROR"]) {
        state.SERVER_CONFIG.skillsData["ESFERA DE TERROR"] = {
            "name": "ESFERA DE TERROR",
            "type": "Ataque",
            "cd": 15000,
            "amount": 500,
            "range": 600,
            "radius": 150,
            "duration": 3000,
            "speed": 800,
            "canTargetOthers": false,
            "targetFilters": {
                "allies": false,
                "enemies": true,
                "bosses": true,
                "players": true,
                "clan": false
            },
            "desc": "Lanza una esfera de energía oscura que daña y aterroriza al objetivo, invirtiendo su movimiento.",
            "icon": ""
        };
    }

    
    console.log('\x1b[35m[SERVER]\x1b[0m Configuración maestro cargada y habilidades inyectadas.');
    if (state.SERVER_CONFIG && state.SERVER_CONFIG.hordeConfig) hordeManager.updateConfig(state.SERVER_CONFIG.hordeConfig);
}).catch(() => {
    Logger.warn('SERVER', 'Usando configuración por defecto (config.json no encontrado).');
});


// v262.100: FUNCIÓN MAESTRA DE PERSISTENCIA (Autoridad del Servidor)
const savePlayerToDB = async (socketId) => {
    const p = players[socketId];
    if (!p || !p.id) return;

    // v2.0: REGLA DE CONGELACIÓN - Si está en extracción, la DB no se toca hasta el éxito/muerte
    if (p.isExtracting) return;

    try {
        await User.updateOne(
            { _id: p.id },
            {
                $set: {
                    "gameData.lastPos.x": Math.floor(p.x),
                    "gameData.lastPos.y": Math.floor(p.y),
                    "gameData.hp": Math.ceil(p.hp !== undefined ? p.hp : 0),
                    "gameData.shield": Math.ceil(p.shield !== undefined ? p.shield : 0),
                    "gameData.zone": (typeof p.zone === 'string' ? (p.zone.startsWith('arena_') || p.zone.startsWith('extract_') ? 1 : (isNaN(parseInt(p.zone)) ? 1 : parseInt(p.zone))) : (p.zone !== undefined ? p.zone : 1)),
                    "gameData.ammo": p.ammo,
                    "gameData.selectedAmmo": p.selectedAmmo,
                    "gameData.inventory": p.inventory,
                    "gameData.equipped": p.equipped,
                    "gameData.spheres": p.spheres,
                    "gameData.hubs": p.hubs,
                    "gameData.ohcu": p.ohcu,
                    "gameData.level": p.level,
                    "gameData.exp": p.exp,
                    "gameData.skillPoints": p.skillPoints,
                    "gameData.skillTree": p.skillTree,
                    "gameData.hudConfig": p.hudConfig || {},
                    "gameData.hudPositions": p.hudPositions || {},
                    "gameData.currentShipId": p.currentShipId || 1
                }
            }
        );
        // console.log(`[DB-SAFE] Perfil de ${p.user} actualizado.`);
    } catch (e) {
        console.error(`Error crítico guardando a ${p.user}:`, e);
    }
};

// v262.120: AUTO-SAVE GLOBAL (Cada 5 minutos)
setInterval(async () => {
    const socketIds = Object.keys(players);
    // console.log(`[AUTO-SAVE] Iniciando guardado masivo de ${socketIds.length} pilotos...`);
    
    for (let i = 0; i < socketIds.length; i++) {
        // Distribuimos el guardado (uno cada 50ms) para no saturar el event loop
        await new Promise(resolve => setTimeout(resolve, 50));
        await savePlayerToDB(socketIds[i]);
    }
    // console.log(`[AUTO-SAVE] Guardado masivo completado.`);
}, 5 * 60 * 1000); // 5 Minutos


io.on('connection', (socket) => {
    const clientIP = socket.handshake.address;
    Logger.info('CONN', `Nueva conexión [${socket.id}] desde IP [${clientIP}]`);
    socket.dbUser = null;

    // v370.1: Auditoría de Ancho de Banda y Telemetría AAA
    socket.bytesSent     = 0;
    socket.bytesReceived = 0;
    socket.pktSent       = 0;
    socket.pktReceived   = 0;
    socket.connectTime   = Date.now();

    // Interceptar tráfico ENTRANTE a nivel de Engine.io
    // 'packet' se emite por cada paquete decodificado (PPS real)
    socket.conn.on('packet', (packet) => {
        if (packet && packet.data) {
            const size = typeof packet.data === 'string'
                ? Buffer.byteLength(packet.data)
                : (packet.data.byteLength || packet.data.length || 0);
            socket.bytesReceived += size;
            socket.pktReceived++;
            if (state.performance) {
                state.performance._pktIn++;
                state.performance._bytesInAcc += size;
            }
        }
    });

    // Interceptar tráfico SALIENTE a nivel de Engine.io
    // v370.1 FIX: Engine.io v4+ llama write(data, options) donde data es Buffer/string directo,
    // no un objeto { data }. Interceptamos 'packetCreate' para el conteo real de egreso.
    socket.conn.on('packetCreate', (packet) => {
        if (!packet) return;
        let size = 0;
        if (packet.data) {
            size = typeof packet.data === 'string'
                ? Buffer.byteLength(packet.data)
                : (packet.data.byteLength || packet.data.length || 0);
        } else if (typeof packet === 'string') {
            size = Buffer.byteLength(packet);
        } else if (Buffer.isBuffer(packet)) {
            size = packet.length;
        }
        socket.bytesSent += size;
        socket.pktSent++;
        if (state.performance) {
            state.performance._pktOut++;
            state.performance._bytesOutAcc += size;
        }
    });

    // REGISTRO DE USUARIO (MongoDB)
    socket.on('register', async (data) => {
        try {
            const username = data.user;
            const existingUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });

            if (existingUser) {
                return socket.emit('authError', 'Ese usuario ya existe.');
            }

            // ENCRIPTACIÓN DE CONTRASEÑA (v35.0)
            const hashedPassword = await bcrypt.hash(data.password, 10);

            const pc = state.SERVER_CONFIG?.pilotConfig || {};
            const startShip = pc.startingShipId ?? 1;

            const newUser = new User({
                username,
                password: hashedPassword
            });

            // v1.9: Aplicar configuración inicial desde Admin Panel
            newUser.gameData.hubs = pc.startingHubs ?? 0;
            newUser.gameData.ohcu = pc.startingOhcu ?? 0;
            newUser.gameData.currentShipId = startShip;
            newUser.gameData.zone = pc.startingMapId ?? 1;
            newUser.gameData.ownedShips = [startShip];
            
            // v1.9.1: Aplicar munición inicial
            if (pc.startingAmmo) {
                newUser.gameData.ammo = JSON.parse(JSON.stringify(pc.startingAmmo));
            }
            
            // Inicializar equipamiento por nave para la nave inicial
            if (!newUser.gameData.equippedByShip) newUser.gameData.equippedByShip = new Map();
            newUser.gameData.equippedByShip.set(String(startShip), { w: [], s: [], e: [], x: [] });

            await newUser.save();
            socket.emit('authSuccess', { user: username, msg: '¡Identidad blindada y grabada en la Galaxia!' });
            await handleUserLogin(socket, newUser, username);
            console.log(`Usuario registrado y logueado: ${username}`);
        } catch (e) {
            console.error("Error en registro:", e);
            socket.emit('authError', 'Error interno del servidor.');
        }
    });

    // LOGIN DE USUARIO (MongoDB)
    socket.on('login', async (data) => {
        try {
            const username = data.user;
            const user = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });

            if (!user) {
                return socket.emit('authError', 'Usuario o contraseña incorrectos.');
            }

            // COMPARACIÓN CRIPTOGRÁFICA (v35.0)
            const isMatch = await bcrypt.compare(data.password, user.password);
            if (!isMatch) {
                return socket.emit('authError', 'Credenciales inválidas en la Galaxia.');
            }

            // v266.210: Gestión de Login Administrativo (Sin spawn de nave)
            if (data.isAdmin) {
                socket.dbUser = user;
                Logger.debug('AUTH', `Verificando Admin: ${user.username} (Input: ${username})`);
                if (user.username.toLowerCase() !== "caelli94") {
                    Logger.warn('SECURITY', `Denegado: ${user.username.toLowerCase()} no es caelli94`);
                    return socket.emit('authError', 'No tienes permisos de Gran Maestro.');
                }
                const adminConfig = await fs.readJson(CONFIG_FILE);
                Logger.success('ADMIN', `Gran Maestro ${username} conectado desde el Command Center.`);
                return socket.emit('loginSuccess', {
                    user: username,
                    adminConfig: adminConfig
                });
            }

            await handleUserLogin(socket, user, username);
        } catch (e) {
            console.error("Error en login:", e);
            socket.emit('authError', 'Error interno del servidor.');
        }
    });

    // v164.10: CONSULTA DE INVENTARIO (Sincronía Godot F1 / Hangar)
    socket.on('getInventory', async () => {
        try {
            // v300.185: Búsqueda robusta. Si dbUser falla, buscamos en el estado global de jugadores
            var userId = socket.dbUser ? socket.dbUser._id : null;
            if (!userId && state.players[socket.id]) {
                userId = state.players[socket.id].dbId;
            }
            
            // console.log(`[SERVER-LOG] getInventory procesando para Socket: ${socket.id} | UserID: ${userId}`);
            
            if (!userId) {
                // console.log("[SERVER-LOG] ERROR: No se pudo identificar al usuario para este socket.");
                return;
            }

            const user = await User.findById(userId);
            if (user) {
                socket.dbUser = user; // Re-sincronizar socket para futuras peticiones
                const { getCategorizedInventory } = require('./systems/inventoryHandlers');

                const invCount = user.gameData.inventory ? user.gameData.inventory.length : 0;
                // console.log(`[SERVER-LOG] Enviando ${invCount} items a Socket: ${socket.id}`);

                // v263.000: MIGRACIÓN AUTOMÁTICA - Sincronizar equipped → equippedByShip
                const currentKey = String(user.gameData.currentShipId || 1);
                const currentEquipped = user.gameData.equipped || { w: [], s: [], e: [], x: [] };
                
                let needsSave = false;
                if (!user.gameData.equippedByShip) {
                    user.gameData.equippedByShip = {};
                    needsSave = true;
                }
                
                const eByShipObj = {};
                if (user.gameData.equippedByShip instanceof Map) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                } else {
                    Object.assign(eByShipObj, user.gameData.equippedByShip);
                }

                const activeInMap = eByShipObj[currentKey];
                const activeHasItems = currentEquipped && (
                    (currentEquipped.w && currentEquipped.w.length > 0) ||
                    (currentEquipped.s && currentEquipped.s.length > 0) ||
                    (currentEquipped.e && currentEquipped.e.length > 0)
                );
                const mapEmpty = !activeInMap || (
                    (!activeInMap.w || activeInMap.w.length === 0) &&
                    (!activeInMap.s || activeInMap.s.length === 0) &&
                    (!activeInMap.e || activeInMap.e.length === 0)
                );

                if (activeHasItems && mapEmpty) {
                    eByShipObj[currentKey] = JSON.parse(JSON.stringify(currentEquipped));
                    if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.set(currentKey, eByShipObj[currentKey]);
                    else user.gameData.equippedByShip[currentKey] = eByShipObj[currentKey];
                    user.markModified('gameData.equippedByShip');
                    needsSave = true;
                }

                if (needsSave) await user.save();

                socket.emit('inventoryData', {
                    player: {
                        ...JSON.parse(JSON.stringify(user.gameData)),
                        equippedByShip: eByShipObj,
                        inventoryByCategory: getCategorizedInventory(user.gameData.inventory)
                    }
                });
            }
        } catch (e) { console.error("Error en getInventory:", e); }
    });

    // GUARDAR PROGRESO (Sincronía Autoritativa con Cooldown de 30s)
    socket.on('saveProgress', async () => {
        const now = Date.now();
        if (socket.lastSaveTime && (now - socket.lastSaveTime < 30000)) {
            return; // Evita spam de escrituras en la base de datos
        }
        socket.lastSaveTime = now;
        await savePlayerToDB(socket.id);
    });

    // v243.15: Helper para serializar datos de clan con roles y estados

    // v242.20: GESTIÓN DE CLANES (FLOTAS) - Modularizado en events/clanHandlers.js
    registerClanHandlers(socket, io, state);

    // Registrar manejadores del sistema de botín autoritativo
    lootManager.registerLootHandlers(socket, io, state);

    // v350.0: Registrar manejadores del baúl de almacenamiento personal
    registerVaultHandlers(socket, io, state);

    // Registrar manejadores del sistema de Housing 3D
    registerHousingHandlers(socket, io, state);

    // Registrar manejadores del sistema de Misiones (v380)
    const { registerQuestHandlers } = require('./systems/questHandlers');
    registerQuestHandlers(socket, io, state);


    // SISTEMA ADMIN: GUARDAR CONFIGURACIÓN GLOBAL (PROTEGIDO)
    socket.on('saveAdminConfig', async (config) => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") {
            console.warn(`[SECURITY-ALERT] Intento de guardado de config no autorizado de: ${socket.id}`);
            return socket.emit('gameNotification', { msg: 'ACCESO DENEGADO: No tienes permisos de Gran Maestro.', type: 'error' });
        }
        
        console.log(`[ADMIN-SAVE] Recibida nueva configuración de: ${socket.dbUser.username}`);
        try {
            await fs.writeJson(CONFIG_FILE, config, { spaces: 4 });
            console.log(`[ADMIN-SAVE] Archivo ${CONFIG_FILE} guardado con éxito.`);
            if (config.enemyModels && config.enemyModels["101"]) {
                console.log(`[ADMIN] Guardando RageTimer para Lord Titán: ${config.enemyModels["101"].rageTimer}s`);
            }
            
            // v245.10: Sincronizar configuración de hordas con el gestor
            if (config.hordeConfig) hordeManager.updateConfig(config.hordeConfig);
            
            // v3.9: Sincronía en Caliente (Update global memory)
            state.SERVER_CONFIG = config;
            
            console.log(`\x1b[35m[ADMIN]\x1b[0m Configuración guardada en disco y RAM.`);
            
            // v226.30: PURGA DE ENTIDADES PARA EVITAR FANTASMAS (Sincronía Limpia)
            // Notificar la config sin simular un cambio de zona: el cliente trata
            // changeZoneDone como teletransporte real y puede desincronizar usuarios.
            broadcastConfigUpdate(io, config);
            
            // Vaciar enemigos en RAM para que el respawn los recree con nuevos datos
            const oldEnemyCount = Object.keys(enemies).length;
            Object.keys(enemies).forEach(id => {
                const e = enemies[id];
                if (state.grid) state.grid.remove(e, 'enemy');
                io.to(`zone_${e.zone}`).emit('enemyDead', { id: id });
                delete enemies[id];
            });
            console.log(`[ADMIN] Purgados ${oldEnemyCount} enemigos antiguos para re-sincronización.`);
            
        } catch (e) { console.error("Error guardando config:", e); }
    });
    
    // v266.999: Purga Administrativa de Enemigos (Botón de Pánico)
    socket.on('adminPurgeEnemies', () => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") return;
        const count = Object.keys(enemies).length;
        Object.keys(enemies).forEach(id => {
            const e = enemies[id];
            if (state.grid) state.grid.remove(e, 'enemy');
            io.to(`zone_${e.zone}`).emit('enemyDead', { id: id });
            delete enemies[id];
        });
        console.log(`[ADMIN] Purga manual ejecutada por Caelli94. ${count} enemigos eliminados.`);
        io.emit('gameNotification', { msg: `PURGA COMPLETADA: ${count} enemigos eliminados.`, type: 'success' });
    });

    // v370.2: Listado de assets en tiempo real para simplificar configuración
    socket.on('getAssetFiles', async () => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") {
            return socket.emit('assetFilesList', { error: 'Unauthorized' });
        }
        try {
            const assetsDir = path.join(__dirname, '../descon/assets');
            const fileList = [];
            const walk = async (dir) => {
                const files = await fs.readdir(dir);
                for (const file of files) {
                    const fullPath = path.join(dir, file);
                    const stat = await fs.stat(fullPath);
                    if (stat.isDirectory()) {
                        await walk(fullPath);
                    } else {
                        const ext = path.extname(file).toLowerCase();
                        if (['.png', '.jpg', '.jpeg', '.svg', '.tga', '.glb', '.gltf'].includes(ext)) {
                            const rel = path.relative(assetsDir, fullPath).replace(/\\/g, '/');
                            fileList.push('res://assets/' + rel);
                        }
                    }
                }
            };
            if (await fs.pathExists(assetsDir)) {
                await walk(assetsDir);
            }
            socket.emit('assetFilesList', fileList);
        } catch (e) {
            console.error("Error scanning asset files:", e);
            socket.emit('assetFilesList', { error: e.message });
        }
    });

    // v304.0: Auditoría Agrupada por Piloto (Bitácora Maestra)
    socket.on('getSessions', async (data) => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") return;
        try {
            const page = data && data.page ? parseInt(data.page) : 0;
            const limit = 50;

            // Pipeline para agrupar por usuario y obtener su última sesión
            const agg = [
                { $sort: { loginAt: -1 } },
                { $group: {
                    _id: "$username",
                    lastSession: { $first: "$$ROOT" },
                    totalSessions: { $sum: 1 },
                    avgDuration: { $avg: "$durationMinutes" }
                }},
                { $sort: { "lastSession.loginAt": -1 } },
                { $skip: page * limit },
                { $limit: limit }
            ];

            const groupedSessions = await Session.aggregate(agg);
            const totalCountArr = await Session.aggregate([{ $group: { _id: "$username" } }, { $count: "count" }]);
            const total = totalCountArr[0] ? totalCountArr[0].count : 0;

            socket.emit('sessionsHistory', { sessions: groupedSessions, total, page });
        } catch (e) {
            console.error("[ADMIN-SESSIONS] Error en agregación:", e);
        }
    });

    // v304.1: Historial Detallado de un Piloto Específico (para Modal)
    socket.on('getPlayerSessions', async (data) => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") return;
        if (!data || !data.username) return;
        try {
            const page = data.page || 0;
            const limit = 30;
            const sessions = await Session.find({ username: data.username })
                .sort({ loginAt: -1 })
                .skip(page * limit)
                .limit(limit);
            
            const total = await Session.countDocuments({ username: data.username });
            socket.emit('playerSessionsDetail', { username: data.username, sessions, total, page });
        } catch (e) {
            console.error("[ADMIN-PLAYER-SESSIONS] Error:", e);
        }
    });

    // v303.2: Monitor de Jugadores Online en Tiempo Real
    socket.on('getOnlinePlayers', () => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") return;
        const onlineList = Object.keys(players).map(id => {
            const p = players[id];
            const s = io.sockets.sockets.get(id);
            return {
                socketId: id,
                username: p.user,
                ip: s ? s.handshake.address : "0.0.0.0",
                zone: p.zone,
                level: p.level,
                latency: p.latency || 0,
                loginAt: s ? (s.loginAt || Date.now()) : Date.now()
            };
        });
        socket.emit('onlinePlayersList', onlineList);
    });

    // v306.0: Telemetría de Rendimiento de Instancia y Consumo por Jugador
    socket.on('getServerPerformance', () => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") return;
        
        const now = Date.now();
        const playerStats = Object.keys(players).map(id => {
            const p = players[id];
            const s = io.sockets.sockets.get(id);
            if (!s) return null;
            
            const durationMs   = now - (s.connectTime || now);
            const durationHours = Math.max(durationMs / (1000 * 60 * 60), 1 / 3600); // Mínimo 1s para evitar /0
            
            const sent     = s.bytesSent     || 0;
            const received = s.bytesReceived || 0;
            const total    = sent + received;
            
            return {
                socketId:        id,
                username:        p.user || 'Desconocido',
                ip:              s.handshake.address || '0.0.0.0',
                zone:            p.zone || 0,
                connectTime:     s.connectTime || now,
                durationMs,
                bytesSent:       sent,
                bytesReceived:   received,
                totalBytes:      total,
                sentPerHour:     sent     / durationHours,
                receivedPerHour: received / durationHours,
                totalPerHour:    total    / durationHours,
                pktSent:         s.pktSent     || 0,
                pktReceived:     s.pktReceived || 0,
                latency:         p.latency || 0
            };
        }).filter(Boolean);
        
        // Clonar performance omitiendo acumuladores internos (no útiles en el cliente)
        const perfSnapshot = Object.assign({}, state.performance);
        delete perfSnapshot._pktIn;
        delete perfSnapshot._pktOut;
        delete perfSnapshot._bytesOutAcc;
        delete perfSnapshot._bytesInAcc;
        
        socket.emit('serverPerformanceData', {
            performance:  perfSnapshot,
            playersCount: Object.keys(players).length,
            enemiesCount: Object.keys(enemies).length,
            // v2.4: Áreas activas reales = Zonas que tienen al menos 1 jugador
            activeAreas:  Object.keys(state.playersByZone || {}).filter(z => Object.keys(state.playersByZone[z]).length > 0).length,
            uptimeMs:     process.uptime() * 1000,
            playerStats
        });
    });

    // v305.2: Gestión de Pilotos Registrados
    socket.on('getRegisteredUsers', async () => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") return;
        try {
            const users = await User.find({}, 'username lastLogin gameData.level gameData.ohcu gameData.hubs gameData.isPremium gameData.zone')
                .sort({ lastLogin: -1 });
            
            const list = users.map(u => ({
                username: u.username,
                lastLogin: u.lastLogin,
                level: u.gameData.level || 1,
                ohcu: u.gameData.ohcu || 0,
                hubs: u.gameData.hubs || 0,
                zone: u.gameData.zone || 1,
                isPremium: !!u.gameData.isPremium
            }));
            
            socket.emit('registeredUsersList', list);
        } catch (e) {
            console.error("[ADMIN-USERS] Error al obtener lista:", e);
        }
    });

    // Registro de Manejadores de Zonas (changeZone, warpToZone)
    registerZoneHandlers(socket, io, state);

    // v245.20: LISTENERS DE EVENTOS DE HORDAS
    socket.on('startHordeEvent', () => {
        if (!players[socket.id] || !players[socket.id].isAdmin) return;
        if (state.SERVER_CONFIG && state.SERVER_CONFIG.hordeConfig) {
            state.SERVER_CONFIG.hordeConfig.active = true;
            hordeManager.updateConfig(state.SERVER_CONFIG.hordeConfig);
            console.log("[ADMIN] Evento de Hordas iniciado manualmente.");
            socket.emit('gameNotification', { msg: 'EVENTO DE HORDAS INICIADO', type: 'success' });
        }
    });

    // ==========================================
    // SISTEMA DE EXTRACCIÓN (NUEVO)
    // ==========================================
    socket.on('joinExtractionMatch', async (data) => {
        const p = state.players[socket.id];
        if (!p) return;

        // Si no hay partidas activas del mapa solicitado, creamos una
        const mapId = data.mapId || 2;
        let matchId = null;

        // Buscar una partida existente con espacio
        for (const [id, m] of extractionManager.matches) {
            if (m.baseMap === mapId && m.players.length < m.maxPlayers) {
                matchId = id;
                break;
            }
        }

        if (!matchId) {
            matchId = extractionManager.createExtractionMatch(mapId);
        }

        const result = await extractionManager.joinMatch(socket.id, matchId);
        if (!result.success) {
            socket.emit('gameNotification', { msg: result.error, type: 'error' });
        }
    });

    socket.on('stopHordeEvent', () => {
        if (!players[socket.id] || !players[socket.id].isAdmin) return;
        hordeManager.stopEvent();
        if (state.SERVER_CONFIG && state.SERVER_CONFIG.hordeConfig) state.SERVER_CONFIG.hordeConfig.active = false;
        socket.emit('gameNotification', { msg: 'EVENTO DETENIDO Y ZONA LIMPIADA', type: 'warning' });
    });

    socket.on('ping_custom', () => {

        socket.emit('pong_custom');
    });

    const isLocalServer = () => {
        if (process.platform === 'win32') return true;
        return !__dirname.includes('/home/ubuntu');
    };

    const isChatGlobalActive = () => {
        if (isLocalServer()) return true;
        const adminOnline = Object.values(state.players).some(p => p.user && p.user.toLowerCase() === 'caelli94');
        const enabledInConfig = state.SERVER_CONFIG?.chatConfig?.globalChatEnabled ?? false;
        return enabledInConfig || adminOnline;
    };

    // SISTEMA DE CHAT v60.0
    socket.on('chatMessage', (data) => {
        if (!players[socket.id]) return;
        const sender = players[socket.id].user;
        const msg = data.msg.substring(0, 50);

        if (data.channel === 'global') {
            if (!isChatGlobalActive()) {
                return socket.emit('chatMessage', { sender: 'SYSTEM', msg: 'El Chat Global está desactivado temporalmente.', channel: 'global' });
            }
        }

        // v300.080: COMANDOS DE CHAT
        if (msg.toLowerCase().startsWith('/trade ')) {
            const targetName = msg.substring(7).trim().toLowerCase();
            const targetP = Object.values(state.players).find(p => p.user && p.user.toLowerCase() === targetName);
            if (targetP) {
                const targetId = Object.keys(state.players).find(k => state.players[k] === targetP);
                const p1 = state.players[socket.id];
                io.to(targetId).emit('tradeInvitationReceived', { fromId: socket.id, fromName: p1.user });
                socket.emit('gameNotification', { msg: `INVITACIÓN ENVIADA A ${targetP.user.toUpperCase()}`, type: "info" });
                return;
            } else {
                return socket.emit('chatMessage', { sender: 'SYSTEM', msg: `ERROR: Piloto '${targetName}' no encontrado.`, channel: 'global' });
            }
        }

        if (msg.toLowerCase().startsWith('/party ')) {
            const targetName = msg.substring(7).trim().toLowerCase();
            const targetPlayer = Object.values(state.players).find(p => p.user && p.user.toLowerCase() === targetName);
            if (targetPlayer) {
                const targetSocket = io.sockets.sockets.get(targetPlayer.socketId);
                if (targetSocket) {
                    if (targetSocket.id === socket.id) {
                        return socket.emit('chatMessage', { sender: 'SYSTEM', msg: `ERROR: No puedes invitarte a ti mismo.`, channel: 'global' });
                    }
                    targetSocket.emit('partyInvitation', {
                        from: players[socket.id].user || 'Desconocido',
                        fromId: socket.id
                    });
                    socket.emit('gameNotification', { msg: `INVITACIÓN DE GRUPO ENVIADA A ${targetPlayer.user.toUpperCase()}`, type: "info" });
                    return;
                }
            }
            return socket.emit('chatMessage', { sender: 'SYSTEM', msg: `ERROR: Piloto '${targetName}' no encontrado o fuera de línea.`, channel: 'global' });
        }



        const responseData = {
            sender: sender,
            senderId: socket.id,
            msg: msg,
            channel: data.channel || 'global'
        };

        if (data.channel === 'global') {
            io.emit('chatMessage', responseData);
        } else if (data.channel === 'region') {
            // Region is current zone
            const zone = players[socket.id].zone || 1;
            Object.keys(players).forEach(id => {
                if (players[id].zone === zone) {
                    io.to(id).emit('chatMessage', responseData);
                }
            });
        } else if (data.channel === 'team') {
            // v164.33: Quitar redundancia de [EQUIPO] (el cliente ya pone el tag)
            socket.emit('chatMessage', { ...responseData, msg: `${msg} (Sin compañeros activos)` });
        }
    });
    // TRANSMISIÓN ADMINISTRATIVA DESDE EL PANEL DE CONTROL
    socket.on('adminGlobalMessage', (data) => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") return;
        const msg = data.msg.substring(0, 100);
        
        io.emit('chatMessage', {
            sender: 'Caelli94',
            senderId: socket.id,
            msg: msg,
            channel: 'global'
        });
        
        io.emit('gameNotification', {
            msg: `Caelli94: ${msg}`,
            type: 'admin_notification'
        });
    });

    // v1.2: SISTEMA DE COMBATE Y HABILIDADES - Modularizado en systems/combatHandlers.js
    registerCombatHandlers(socket, io, state);

    // ENVIAR CONFIG AL CONECTAR
    fs.readJson(CONFIG_FILE).then(config => {
        if (config) emitConfigForSocket(socket, 'adminConfigLoaded', config);
    }).catch(e => { /* Config por defecto en cliente */ });

    // v1.3: SISTEMA DE INVENTARIO Y ECONOMÍA - Modularizado en systems/inventoryHandlers.js
    registerInventoryHandlers(socket, io, state);
    registerTradeHandlers(socket, io, state);


    // v220.81: TOGGLE PVP CONSENSUADO
    socket.on('togglePvP', async (enabled) => {
        const p = players[socket.id];
        if (!p) return;
        
        // Bloquear desactivación o cambio manual en zonas con PvP obligatorio
        const cleanZone = normalizeZone(p.zone);
        const mapCfg = state.SERVER_CONFIG?.mapsConfig?.[cleanZone];
        const isPvPMandatory = mapCfg?.pvpMode === 'mandatory' || mapCfg?.pvpMode === 'full_drop' || mapCfg?.pvpMode === 'partial_drop';
        if (isPvPMandatory) {
            return socket.emit('gameNotification', { 
                msg: `¡MODO COMBATE OBLIGATORIO! No puedes cambiar el modo de combate en este sector.`, 
                type: "error" 
            });
        }
        
        // v3.1: Bloquear cambios manuales de PvP dentro de la Raid de Extracción
        if (p.isExtracting) {
            return socket.emit('gameNotification', { 
                msg: `¡MODO EXTRACCIÓN! No puedes cambiar el modo de combate dentro de la Raid.`, 
                type: "error" 
            });
        }
        
        // v222.45: ANTI-COMBAT-LOG / COOLDOWN DE COMBATE (Cualquier cambio de modo de combate)
        const now = Date.now();
        const timeSincePvp = now - (p.lastPvpCombatTime || 0);
        
        // v400.30: Cooldown dinámico configurado por mapa desde el Admin Dash (por defecto 30000ms)
        const cooldownMs = mapCfg && mapCfg.pvpToggleCooldown !== undefined ? mapCfg.pvpToggleCooldown : 30000;
        
        if (timeSincePvp < cooldownMs) {
            const remaining = Math.ceil((cooldownMs - timeSincePvp) / 1000);
            return socket.emit('gameNotification', { 
                msg: `¡COMBATE RECIENTE! Espera ${remaining}s para cambiar tu modo de combate.`, 
                type: "error" 
            });
        }

        p.pvpEnabled = !!enabled;
        
        // v220.97: PERSISTENCIA EN DB
        if (socket.dbUser) {
            try {
                const user = await User.findById(socket.dbUser._id);
                if (user) {
                    user.gameData.pvpEnabled = !!enabled;
                    user.markModified('gameData');
                    await user.save();
                }
            } catch (e) { console.error("[PVP-SAVE] Error:", e); }
        }
        
        // v2.4: Notificar a la zona con TODOS los datos de presentación del jugador.
        // Si playerUpdated solo lleva { id, pvpEnabled }, el cliente Godot re-instancia la nave
        // con valores por defecto (ship Tier 1, "Unknown") porque no tiene currentShipId ni username.
        const pvpUpdatePayload = {
            id:             socket.id,
            pvpEnabled:     p.pvpEnabled,
            // Campos de presentación — sin estos el cliente muestra nave Tier 1 y "Unknown"
            user:           p.user || 'Unknown',
            username:       p.user || 'Unknown',
            x:              Math.round(p.x),
            y:              Math.round(p.y),
            rotation:       Math.round((p.rotation || 0) * 100) / 100,
            hp:             Math.ceil(p.hp || 0),
            shield:         Math.ceil(p.shield || 0),
            sh:             Math.ceil(p.shield || 0),
            maxHp:          p.maxHp || 0,
            maxShield:      p.maxShield || 0,
            zone:           p.zone,
            clanTag:        p.clanTag || '',
            currentShipId:  p.currentShipId || 1,
            isInvisible:    !!p.isInvisible,
            isInvulnerable: !!p.isInvulnerable,
            isDead:         !!p.isDead,
            spheres:        p.spheres || []
        };
        io.to(`zone_${p.zone}`).emit('playerUpdated', pvpUpdatePayload);
        console.log(`[PVP] Piloto ${p.user} modo: ${enabled ? 'ACTIVO' : 'SEGURO'}`);
    });

    socket.on('latencyUpdate', (ms) => {
        if (players[socket.id]) {
            players[socket.id].latency = ms;
        }
    });

    // v2.2: EVENTOS DE MATCHMAKING DE EXTRACCIÓN
    socket.on('joinExtractionQueue', () => {
        extractionManager.addToQueue(socket.id);
    });

    socket.on('leaveExtractionQueue', () => {
        extractionManager.leaveQueue(socket.id);
    });

    // Eventos de Arenas PvP
    socket.on('joinArenaQueue', () => {
        arenaManager.joinQueue(socket.id);
    });

    socket.on('leaveArenaQueue', () => {
        arenaManager.leaveQueue(socket.id);
    });

    socket.on('arenaHit', (data) => {
        arenaManager.handleArenaHit(socket.id, data);
    });

    // El cambio de nave (switchShip) está modularizado arriba.

    // Registro de Manejadores de Movimiento y Respawn (playerMovement, playerRespawn)
    registerMovementHandlers(socket, io, state);

    // SISTEMA DE TALENTOS Y HABILIDADES (Modularizado)
    registerSkillHandlers(socket, io, state);

    // SISTEMA DE DUNGEONS BLINDADAS (Instancias Privadas)
    socket.on('enterDungeon', () => {
        if (!socket.dbUser || !players[socket.id]) return;
        const myUid = socket.dbUser._id.toString();
        const p = players[socket.id];

        // Crear un ID de zona ├║nica para la Dungeon
        const dungeonZoneId = `dungeon_${Date.now()}_${Math.floor(Math.random() * 1000)}`;

        // Chequear si el jugador est├í en Party
        const partyId = playerParty[myUid];
        let playersToMove = [socket]; // Solo ├®l por defecto

        if (partyId && parties[partyId]) {
            // Mover a todos los miembros de la party que est├®n online y en la misma zona actual
            playersToMove = parties[partyId].members
                .map(uid => [...io.sockets.sockets.values()].find(s => s.dbUser && s.dbUser._id.toString() === uid))
                .filter(s => s && players[s.id] && players[s.id].zone === p.zone);
        }

        // Spawnear al Boss en la instancia Privada (Center at 1000,1000 for 2000x2000 room)
        aiManager.serverSpawnEnemy(dungeonZoneId, 6, 1000, 1000);

        // Teletransportar a los elegidos a la Dungeon
        playersToMove.forEach(s => {
            const memP = players[s.id];
            const oldZone = memP.zone;

            if (state.playersByZone[oldZone] && state.playersByZone[oldZone][s.id]) {
                delete state.playersByZone[oldZone][s.id];
            }
            if (!state.playersByZone[dungeonZoneId]) {
                state.playersByZone[dungeonZoneId] = {};
            }
            state.playersByZone[dungeonZoneId][s.id] = memP;

            s.leave(`zone_${oldZone}`);
            s.join(`zone_${dungeonZoneId}`);
            memP.zone = dungeonZoneId;
            memP.x = 500; // Aparecen un poco alejados del centro (Boss)
            memP.y = 1000;

            s.to(`zone_${oldZone}`).emit('playerDisconnected', s.id);
            s.to(`zone_${dungeonZoneId}`).emit('newPlayer', { ...memP, spheres: memP.spheres });

            // Forzar actualizaci├│n total al cliente
            s.emit('changeZoneDone', dungeonZoneId); // Opcional, por si el cliente lo necesita

            // Mandarle el estado de los enemigos (El Boss que acabamos de spawnear)
            const zoneEnemies = {};
            Object.keys(enemies).forEach(id => {
                if (enemies[id].zone === dungeonZoneId) {
                    const { ai, ...cleanData } = enemies[id];
                    zoneEnemies[id] = cleanData;
                }
            });
            s.emit('currentEnemies', zoneEnemies);

            // Mandar confirmación de entrada mediante chat o notificación
            s.emit('gameNotification', { msg: 'Ingresando a Dungeon Privada...', type: 'alert' });
        });

        Logger.info('DUNGEON', `Party teleportada a instancia: ${dungeonZoneId} con ${playersToMove.length} miembros.`);
    });
    
    socket.on('disconnect', async () => {
        // v2.2: Salir de la cola de extracción si estaba en ella
        extractionManager.leaveQueue(socket.id);

        const p = players[socket.id];
        if (p) {
            Logger.info('CONN', `Conexión perdida con [${p.user}] - ID: ${socket.id}`);
            
            // v303.0: Finalizar Auditoría de Sesión
            if (socket.currentSessionId) {
                try {
                    const logoutTime = new Date();
                    const session = await Session.findById(socket.currentSessionId);
                    if (session) {
                        const diffMs = logoutTime - session.loginAt;
                        session.logoutAt = logoutTime;
                        session.durationMinutes = Math.floor(diffMs / 60000);
                        let zoneNum = 1;
                        if (p.zone !== undefined) {
                            if (typeof p.zone === 'string' && p.zone.startsWith('extract_')) {
                                const parts = p.zone.split('_');
                                zoneNum = parseInt(parts[1]) || 1;
                            } else {
                                zoneNum = parseInt(p.zone) || 1;
                            }
                        }
                        session.zoneAtLogout = zoneNum;
                        session.levelAtLogout = p.level || 1;
                        await session.save();
                    }
                } catch (e) { Logger.error('SESSION', `Error al cerrar sesión: ${e.message}`); }
            }

            // Avisar a su clan que se fue
            if (p.clanId) {
                io.to(`clan_${p.clanId}`).emit('clanMemberStatus', { user: p.user, online: false });
            }
            
            if (state.playersByZone[p.zone] && state.playersByZone[p.zone][socket.id]) {
                delete state.playersByZone[p.zone][socket.id];
            }
            await savePlayerToDB(socket.id);
            socket.broadcast.emit('playerDisconnected', socket.id);
            delete players[socket.id];
            
            if (p.user) activeSessions.delete(p.user.toLowerCase());
            io.emit('onlineCount', Object.keys(players).length);
            // v138.10: No borrar de la party al desconectar (F5 Persistence)
            const uid = socket.dbUser ? socket.dbUser._id.toString() : null;
            if (uid && playerParty[uid]) {
                const pid = playerParty[uid];
                if (parties[pid]) {
                    // Solo marcar como desconectado, NO borrar del grupo
                    io.emit('chatMessage', { sender: 'SYSTEM', msg: `${p.user.toUpperCase()} OFFLINE.`, channel: 'team', senderId: 'server' });
                }
            }
        }
    });

    socket.on('saveHudLayout', async (data) => {
        if (players[socket.id]) {
            // v266.130: Guardado en slot específico
            if (data.slotIndex !== undefined && data.slotIndex >= 0 && data.slotIndex < 4) {
                if (!players[socket.id].hudLayouts) players[socket.id].hudLayouts = [];
                
                // Asegurar que el slot exista
                if (!players[socket.id].hudLayouts[data.slotIndex]) {
                    players[socket.id].hudLayouts[data.slotIndex] = { name: data.name || `Layout ${data.slotIndex + 1}`, positions: {} };
                }
                
                const slot = players[socket.id].hudLayouts[data.slotIndex];
                if (data.name) slot.name = data.name;
                if (data.positions) slot.positions = data.positions;
                
                // Sincronizar el layout activo para persistencia global
                players[socket.id].hudPositions = data.positions || players[socket.id].hudPositions;
                
                Logger.debug('HUD', `Guardado Slot ${data.slotIndex} para ${players[socket.id].user}`);

                if (socket.dbUser) {
                    try {
                        const updatePath = `gameData.hudLayouts.${data.slotIndex}`;
                        const updateObj = { [updatePath]: players[socket.id].hudLayouts[data.slotIndex] };
                        updateObj["gameData.hudPositions"] = players[socket.id].hudPositions;
                        
                        await User.updateOne({ _id: socket.dbUser._id }, { $set: updateObj });
                        Logger.debug('HUD-SLOT', `Persistencia exitosa en DB para slot ${data.slotIndex}`);
                    } catch (e) { Logger.error('HUD-SAVE', e.message); }
                }
                return;
            }

            if (data.config !== undefined) players[socket.id].hudConfig = data.config;
            if (data.positions !== undefined) players[socket.id].hudPositions = data.positions;
            Logger.debug('HUD', `Config global recibida de ${players[socket.id].user}`);
            
            if (socket.dbUser) {
                try {
                    const updateObj = {};
                    if (data.config !== undefined) updateObj["gameData.hudConfig"] = data.config;
                    if (data.positions !== undefined) updateObj["gameData.hudPositions"] = data.positions;
                    
                    if (Object.keys(updateObj).length > 0) {
                        await User.updateOne({ _id: socket.dbUser._id }, { $set: updateObj });
                        Logger.debug('HUD', `Config global persistida en DB para ${players[socket.id].user}`);
                    }
                } catch (e) {
                    Logger.error('HUD-SAVE', e.message);
                }
            }
        }
    });

    socket.on('saveHUD', async (data) => {
        if (players[socket.id] && socket.dbUser) {
            try {
                if (!players[socket.id].hudPositions) players[socket.id].hudPositions = {};
                players[socket.id].hudPositions[data.id] = data.pos;

                // v189.96: PERSISTENCIA INSTANTÁNEA (DB Atlas Write)
                const updatePath = `gameData.hudPositions.${data.id}`;
                await User.updateOne(
                    { _id: socket.dbUser._id },
                    { $set: { [updatePath]: data.pos } }
                );

                Logger.debug('HUD-DB', `Registro guardado: ${data.id} para ${players[socket.id].user}`);
            } catch (e) { Logger.error('HUD-PERSIST', e.message); }
        }
    });

    // SISTEMA DE PARTIES (GRUPOS) (Modularizado)
    registerPartyHandlers(socket, io, state);

    // ==========================================
    // SISTEMA DE DEFENSA DEL ALTAR
    // ==========================================
    
    function cancelAltarDefenseInvite(partyId, reason) {
        const invite = altarDefenseInvites.get(partyId);
        if (invite) {
            if (invite.timeoutTimer) clearTimeout(invite.timeoutTimer);
            invite.membersList.forEach(mUid => {
                const targetSocketId = Object.keys(players).find(sid => players[sid].id === mUid);
                if (targetSocketId) {
                    io.to(targetSocketId).emit('altarDefenseCancelled', { reason: reason });
                }
            });
            altarDefenseInvites.delete(partyId);
        }
    }

    async function warpPartyToAltarDefense(membersList) {
        try {
            const altarDefenseConfig = state.SERVER_CONFIG && state.SERVER_CONFIG.gameModes && state.SERVER_CONFIG.gameModes.altar_defense;
            const targetZoneId = (altarDefenseConfig && altarDefenseConfig.maps && altarDefenseConfig.maps[0]) ? parseInt(altarDefenseConfig.maps[0]) : 9;

            // Iniciar la partida en el AltarDefenseManager de forma autoritativa
            altarDefenseManager.startMatch(targetZoneId, membersList);

            const spawnPoints = (altarDefenseConfig && altarDefenseConfig.spawnPoints && altarDefenseConfig.spawnPoints.length > 0) 
                ? altarDefenseConfig.spawnPoints 
                : [{ x: 5000, y: 5000 }];

            let spawnIdx = 0;
            for (const mUid of membersList) {
                const targetSocket = [...io.sockets.sockets.values()].find(s => {
                    const p = players[s.id];
                    return p && p.id === mUid;
                });
                if (targetSocket) {
                    targetSocket.emit('altarDefenseSuccess', {});

                    const p = players[targetSocket.id];
                    if (p) {
                        const oldZone = p.zone;
                        const spawn = spawnPoints[spawnIdx % spawnPoints.length];
                        const targetX = spawn ? parseInt(spawn.x) : 5000;
                        const targetY = spawn ? parseInt(spawn.y) : 5000;
                        spawnIdx++;

                        if (Number(oldZone) !== Number(targetZoneId)) {
                            await User.updateOne({ _id: p.id }, { $set: { "gameData.zone": targetZoneId } });

                            targetSocket.leave(`zone_${oldZone}`);
                            targetSocket.join(`zone_${targetZoneId}`);

                            p.zone = targetZoneId;
                            p.x = targetX;
                            p.y = targetY;

                            targetSocket.emit('changeZoneDone', { zoneId: targetZoneId, x: targetX, y: targetY });
                            targetSocket.to(`zone_${oldZone}`).emit('playerDisconnected', targetSocket.id);

                            const currentPlayersInZone = {};
                            Object.keys(players).forEach(pId => {
                                const otherP = players[pId];
                                if (normalizeZone(otherP.zone) === normalizeZone(targetZoneId) && pId !== targetSocket.id) {
                                    currentPlayersInZone[pId] = {
                                        id: pId,
                                        user: otherP.user,
                                        x: otherP.x,
                                        y: otherP.y,
                                        hp: otherP.hp,
                                        maxHp: otherP.maxHp,
                                        sh: otherP.sh || otherP.shield,
                                        maxSh: otherP.maxSh || otherP.maxShield,
                                        zone: otherP.zone,
                                        spheres: otherP.spheres || [],
                                        clanTag: otherP.clanTag || ""
                                    };
                                }
                            });

                            const zoneEnemies = {};
                            Object.keys(enemies).forEach(id => {
                                const e = enemies[id];
                                if (normalizeZone(e.zone) === normalizeZone(targetZoneId)) {
                                    zoneEnemies[id] = {
                                        id: id,
                                        type: e.type,
                                        x: e.x,
                                        y: e.y,
                                        hp: e.hp,
                                        maxHp: e.maxHp,
                                        sh: e.sh || e.shield
                                    };
                                }
                            });

                            setTimeout(() => {
                                if (targetSocket.connected) {
                                    targetSocket.emit('currentPlayers', currentPlayersInZone);
                                    targetSocket.emit('currentEnemies', zoneEnemies);
                                }
                            }, 400);

                            targetSocket.to(`zone_${targetZoneId}`).emit('newPlayer', {
                                id: targetSocket.id,
                                user: p.user,
                                x: p.x,
                                y: p.y,
                                hp: p.hp,
                                maxHp: p.maxHp,
                                sh: p.sh || p.shield,
                                maxSh: p.maxSh || p.maxShield,
                                zone: p.zone,
                                spheres: p.spheres || [],
                                clanTag: p.clanTag || ""
                            });
                        }
                    }
                }
            }
        } catch (err) {
            console.error("Error warpeando party a Defensa del Altar:", err);
        }
    }

    socket.on('registerAltarDefenseParty', () => {
        try {
            if (!socket.dbUser || !players[socket.id]) return;
            const myUid = socket.dbUser._id.toString();
            const partyId = playerParty[myUid];

            if (!partyId || !parties[partyId]) {
                return socket.emit('gameNotification', { msg: 'DEBES ESTAR EN UN GRUPO PARA REGISTRARTE', type: 'error' });
            }

            // Validar que sea el líder
            if (partyId !== myUid) {
                return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER DEL GRUPO PUEDE INSCRIBIR AL GRUPO', type: 'error' });
            }

            const party = parties[partyId];
            
            // Limpiar cualquier invitación previa pendiente para esta party
            if (altarDefenseInvites.has(partyId)) {
                const prev = altarDefenseInvites.get(partyId);
                if (prev.timeoutTimer) clearTimeout(prev.timeoutTimer);
                altarDefenseInvites.delete(partyId);
            }

            const timeoutMs = (state.SERVER_CONFIG && state.SERVER_CONFIG.gameModes && state.SERVER_CONFIG.gameModes.altar_defense && state.SERVER_CONFIG.gameModes.altar_defense.partyAcceptTimeout) || 10000;
            const minPlayers = (state.SERVER_CONFIG && state.SERVER_CONFIG.gameModes && state.SERVER_CONFIG.gameModes.altar_defense && state.SERVER_CONFIG.gameModes.altar_defense.minPlayers) !== undefined 
                ? parseInt(state.SERVER_CONFIG.gameModes.altar_defense.minPlayers) 
                : 2;

            if (party.members.length < minPlayers) {
                return socket.emit('gameNotification', { msg: `SE REQUIEREN AL MENOS ${minPlayers} MIEMBROS EN EL GRUPO PARA ESTE EVENTO`, type: 'error' });
            }

            if (party.members.length <= 1) {
                // Éxito directo si solo está el líder (warpearlo directo)
                return warpPartyToAltarDefense([myUid]);
            }

            // Crear invitación en memoria
            const inviteState = {
                partyId: partyId,
                leaderId: myUid,
                leaderName: socket.dbUser.username.toUpperCase(),
                acceptedMembers: new Set([myUid]),
                totalMembers: party.members.length,
                membersList: [...party.members],
                timeoutTimer: setTimeout(() => {
                    cancelAltarDefenseInvite(partyId, "Tiempo de espera agotado.");
                }, timeoutMs)
            };

            altarDefenseInvites.set(partyId, inviteState);

            // Notificar a todos los miembros de la party (excepto el líder)
            party.members.forEach(mUid => {
                if (mUid !== myUid) {
                    const targetSocketId = Object.keys(players).find(sid => players[sid].id === mUid);
                    if (targetSocketId) {
                        io.to(targetSocketId).emit('altarDefenseInvitation', {
                            timeoutMs: timeoutMs,
                            leaderName: socket.dbUser.username.toUpperCase()
                        });
                    }
                }
            });

            socket.emit('gameNotification', { msg: 'INVITACIONES ENVIADAS AL GRUPO', type: 'info' });

        } catch (e) {
            console.error("Error en registerAltarDefenseParty:", e);
        }
    });

    socket.on('acceptAltarDefenseInvite', () => {
        try {
            if (!socket.dbUser) return;
            const myUid = socket.dbUser._id.toString();
            const partyId = playerParty[myUid];

            if (!partyId) return;
            const invite = altarDefenseInvites.get(partyId);
            if (!invite || !invite.membersList.includes(myUid)) return;

            invite.acceptedMembers.add(myUid);

            if (invite.acceptedMembers.size === invite.totalMembers) {
                if (invite.timeoutTimer) clearTimeout(invite.timeoutTimer);
                
                // Teletransportar a todo el grupo al evento
                warpPartyToAltarDefense(invite.membersList);

                altarDefenseInvites.delete(partyId);
            }
        } catch (e) {
            console.error("Error en acceptAltarDefenseInvite:", e);
        }
    });

    socket.on('rejectAltarDefenseInvite', () => {
        try {
            if (!socket.dbUser) return;
            const myUid = socket.dbUser._id.toString();
            const partyId = playerParty[myUid];

            if (!partyId) return;
            const invite = altarDefenseInvites.get(partyId);
            if (!invite) return;

            cancelAltarDefenseInvite(partyId, `Inscripción rechazada por ${socket.dbUser.username.toUpperCase()}`);
        } catch (e) {
            console.error("Error en rejectAltarDefenseInvite:", e);
        }
    });
});

// v1.6: Helpers de Sistema
const os = require('os');
function getLocalIP() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) return iface.address;
        }
    }
    return 'localhost';
}

function startServer() {
    http.listen(PORT, '0.0.0.0', () => {
        const ip = getLocalIP();
        Logger.system(`+----------------------------------------------+`);
        Logger.system(`|  DESCON v6 - SERVIDOR MULTIPLAYER ACTIVO     |`);
        Logger.system(`|  IP: http://${ip}:${PORT}                    |`);
        Logger.system(`+----------------------------------------------+`);
    });
}
// v1.10.2: Nodemon Watcher Trigger Line.

