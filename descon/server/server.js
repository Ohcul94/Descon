require('dotenv').config();
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

// Modelos y Módulos de Seguridad
const User = require('./models/User');
const Clan = require('./models/Clan'); // v242.10: Gestión de Flotas
const bcrypt = require('bcrypt'); // Criptografía Pro v35.0

// v1.1: Handlers y Sistemas Modulares
const { getClanDataPayload, registerClanHandlers } = require('./events/clanHandlers');
const { registerCombatHandlers } = require('./systems/combatHandlers');
const { registerInventoryHandlers } = require('./systems/inventoryHandlers');
const AIManager = require('./systems/AIManager');
const { startGameLoop } = require('./systems/gameLoop');
const HordeManager = require('./events/HordeManager');
const { calculateFinalStats } = require('./systems/statCalculator'); // v266.135: Sistema de Stats Dinámicos

// Configuraci├│n
const PORT = process.env.PORT || 3333;
const CONFIG_FILE = path.join(__dirname, 'config.json');

// Conexi├│n a MongoDB
mongoose.connect(process.env.MONGODB_URI)
    .then(() => console.log('\x1b[32m[DB]\x1b[0m Conectado a MongoDB Atlas'))
    .catch(err => {
        console.error('\x1b[31m[DB]\x1b[0m Error de conexi├│n:', err.message);
        console.log('Asegurate de que MongoDB est├® corriendo o que el URI en .env sea correcto.');
    });

// Asegurar que archivos existan
if (!fs.existsSync(CONFIG_FILE)) fs.writeJsonSync(CONFIG_FILE, null);

// Middleware para que Godot Web funcione (SharedArrayBuffer support) v1.0
app.use((req, res, next) => {
    res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
    res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
    next();
});

// Servir archivos est├íticos desde la carpeta 'public'
app.use(express.static(path.join(__dirname, 'public')));

const state = require('./state');
const { players, activeSessions, enemies, activeAreas, parties, playerParty } = state;

// v1.4: Inicialización de Sistemas Maestros
const aiManager = new AIManager(io, state, null);
const hordeManager = new HordeManager(io, (...args) => aiManager.serverSpawnEnemy(...args), enemies);
aiManager.hordeManager = hordeManager;

// v1.5: Inicio del Corazón del Servidor
startGameLoop(io, state, aiManager);

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
        }
    }
    activeSessions.set(lowName, socket.id);

    user.lastLogin = new Date();
    await user.save();

    socket.dbUser = user;
    // Sanity Check: Si el jugador estaba muerto o sin vida, revivirlo v67.0
    if (!user.gameData.hp || user.gameData.hp <= 0) {
        user.gameData.hp = user.gameData.maxHp || 2000;
        user.gameData.shield = user.gameData.maxShield || 1000;
        console.log(`[REVIVE] Piloto ${username} regenerado por deslogueo/muerte.`);
    }

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

    players[socket.id] = {
        id: dbId,
        socketId: socket.id,
        num: state.nextPlayerNum++,
        user: username,
        clanTag: clanTag, // v244.110: Siglas para el NameTag
        x: user.gameData.lastPos?.x || (user.gameData.zone === 1 ? 1000 : 2000),
        y: user.gameData.lastPos?.y || (user.gameData.zone === 1 ? 1000 : 2000),
        rotation: 0,
        hp: user.gameData.hp || baseHp,
        maxHp: baseHp,
        shield: user.gameData.shield || baseSh,
        maxShield: baseSh,
        level: user.gameData.level || 1,
        skillPoints: user.gameData.skillPoints || 0,
        skillTree: user.gameData.skillTree || {
            engineering: [0, 0, 0, 0, 0, 0, 0, 0],
            combat: [0, 0, 0, 0, 0, 0, 0, 0],
            science: [0, 0, 0, 0, 0, 0, 0, 0]
        },
        baseHp: baseHp,
        baseShield: baseSh,
        ammo: user.gameData.ammo || { laser: [1000, 0, 0, 0, 0, 0], missile: [50, 0, 0, 0, 0, 0], mine: [10, 0, 0, 0, 0, 0] },
        equipped: resolvedEquip,
        spheres: user.gameData.spheres,
        hudConfig: user.gameData.hudConfig || {},
        hudPositions: user.gameData.hudPositions || {},
        hudLayouts: user.gameData.hudLayouts || [], // v266.130: Slots múltiples
        hubs: user.gameData.hubs || 0,
        ohcu: user.gameData.ohcu || 0,
        exp: user.gameData.exp || 0,
        clanId: user.gameData.clanId, // v244.110: Mantener referencia para filtros de combate
        currentShipId: user.gameData.currentShipId || 1,
        zone: user.gameData.zone || 1,
        pvpEnabled: !!user.gameData.pvpEnabled,
        lastPos: { x: user.gameData.lastPos?.x || 2000, y: user.gameData.lastPos?.y || 2000 },
        lastPvpCombatTime: 0,
        lastCombatTime: 0,
        clanId: user.gameData.clanId,
        isInvulnerable: false,
        isAdmin: (user.username.toLowerCase() === "caelli94") // v266.700: Bypass Maestro
    };

    const p_ref = players[socket.id];
    
    // v266.135: Cálculo Maestro de Stats (Base + Ítems + Skills)
    calculateFinalStats(p_ref, state.SERVER_CONFIG);

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

    // v262.210: MIGRACIÓN Y CATEGORIZACIÓN (Fix de ítems viejos y Admin Panel)
    const { getCategorizedInventory } = require('./systems/inventoryHandlers');
    if (!user.gameData.inventory) user.gameData.inventory = [];
    
    // v266.140: Sincronización PROFUNDA (Inventory + Equipped)
    const allShopItems = [
        ...(state.SERVER_CONFIG.shopItems.weapons || []),
        ...(state.SERVER_CONFIG.shopItems.shields || []),
        ...(state.SERVER_CONFIG.shopItems.engines || []),
        ...(state.SERVER_CONFIG.shopItems.extra || [])
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

    const categorized = getCategorizedInventory(user.gameData.inventory);

    socket.emit('loginSuccess', {
        id: dbId,
        socketId: socket.id,
        user: username,
        clanTag: clanTag,
        gameData: {
            ...JSON.parse(JSON.stringify(user.gameData)),
            equippedByShip: eByShipObj,
            equipped: user.gameData.equipped,
            inventoryByCategory: categorized
        },
        adminConfig: adminConfig
    });

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
            const { ai, ...data } = e;
            cleanEnemiesInZone[e.id] = data;
        }
    });

    const playerSpawnData = { ...players[socket.id], id: socket.id };
    setTimeout(() => {
        socket.emit('currentPlayers', currentPlayersInZone);
        socket.emit('currentEnemies', cleanEnemiesInZone);
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
    console.log(`[AUTH] Piloto [${username}] inicializado con éxito.`);
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
    state.SERVER_CONFIG = config;
    
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
    
    console.log('\x1b[35m[SERVER]\x1b[0m Configuración maestro cargada y habilidades inyectadas.');
    if (state.SERVER_CONFIG && state.SERVER_CONFIG.hordeConfig) hordeManager.updateConfig(state.SERVER_CONFIG.hordeConfig);
}).catch(() => {
    console.log('\x1b[33m[SERVER]\x1b[0m Usando configuraci├│n por defecto (config.json no encontrado).');
});


io.on('connection', (socket) => {
    const clientIP = socket.handshake.address;
    console.log(`DESCON: Nueva conexión [${socket.id}] desde IP [${clientIP}]`);
    socket.dbUser = null;

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

            const newUser = new User({
                username,
                password: hashedPassword
            });

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
                console.log(`[DEBUG-AUTH] Verificando Admin: ${user.username} (Input: ${username})`);
                if (user.username.toLowerCase() !== "caelli94") {
                    console.warn(`[DEBUG-AUTH] Denegado: ${user.username.toLowerCase()} no es caelli94`);
                    return socket.emit('authError', 'No tienes permisos de Gran Maestro.');
                }
                const adminConfig = await fs.readJson(CONFIG_FILE);
                console.log(`[ADMIN-AUTH] Gran Maestro ${username} conectado desde el Command Center.`);
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

    // v164.10: CONSULTA DE INVENTARIO (Sincronía Godot F1)
    socket.on('getInventory', async () => {
        if (!socket.dbUser) return;
        try {
            const user = await User.findById(socket.dbUser._id);
            if (user) {
                socket.dbUser = user;
                const { getCategorizedInventory } = require('./systems/inventoryHandlers');

                // v263.000: MIGRACIÓN AUTOMÁTICA - Sincronizar equipped → equippedByShip
                // Garantiza que la nave activa siempre tenga sus datos en el mapa por nave
                const currentKey = String(user.gameData.currentShipId || 1);
                const currentEquipped = user.gameData.equipped || { w: [], s: [], e: [], x: [] };
                
                let needsSave = false;
                if (!user.gameData.equippedByShip) {
                    user.gameData.equippedByShip = {};
                    needsSave = true;
                }
                
                // Leer el mapa (Map o Object)
                const eByShipObj = {};
                if (user.gameData.equippedByShip instanceof Map) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                } else {
                    Object.assign(eByShipObj, user.gameData.equippedByShip);
                }

                // Si la nave activa no tiene datos en el mapa, copiarlos desde equipped
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
                    // Persistir en DB para que no se repita
                    if (user.gameData.equippedByShip instanceof Map) {
                        user.gameData.equippedByShip.set(currentKey, eByShipObj[currentKey]);
                    } else {
                        user.gameData.equippedByShip[currentKey] = eByShipObj[currentKey];
                    }
                    user.markModified('gameData.equippedByShip');
                    needsSave = true;
                    console.log(`[MIGRACIÓN] Nave ${currentKey} de ${user.username}: equipamiento sincronizado al mapa.`);
                }

                if (needsSave) await user.save();

                socket.emit('inventoryData', {
                    player: {
                        ...JSON.parse(JSON.stringify(user.gameData)),
                        equippedByShip: eByShipObj,
                        inventoryByCategory: getCategorizedInventory(user.gameData.inventory)
                    }
                });
                console.log(`[SYNC] Inventario sincronizado para ${user.username}. Naves en mapa: ${Object.keys(eByShipObj).join(', ')}`);
            }
        } catch (e) { console.error("Error en getInventory:", e); }
    });

    // v262.100: FUNCIÓN MAESTRA DE PERSISTENCIA (Autoridad del Servidor)
    const savePlayerToDB = async (socketId) => {
        const p = players[socketId];
        const socket = io.sockets.sockets.get(socketId);
        if (!p || !socket || !socket.dbUser) return;

        try {
            await User.updateOne(
                { _id: socket.dbUser._id },
                {
                    $set: {
                        "gameData.lastPos.x": Math.floor(p.x),
                        "gameData.lastPos.y": Math.floor(p.y),
                        "gameData.hp": Math.ceil(p.hp || 0),
                        "gameData.shield": Math.ceil(p.shield || 0),
                        "gameData.zone": (p.zone !== undefined ? p.zone : 1),
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

    // GUARDAR PROGRESO (Sincronía Autoritativa)
    socket.on('saveProgress', async () => {
        await savePlayerToDB(socket.id);
    });

    // v262.120: AUTO-SAVE GLOBAL (Cada 5 minutos)
    setInterval(async () => {
        const socketIds = Object.keys(players);
        console.log(`[AUTO-SAVE] Iniciando guardado masivo de ${socketIds.length} pilotos...`);
        
        for (let i = 0; i < socketIds.length; i++) {
            // Distribuimos el guardado (uno cada 50ms) para no saturar el event loop
            await new Promise(resolve => setTimeout(resolve, 50));
            await savePlayerToDB(socketIds[i]);
        }
        console.log(`[AUTO-SAVE] Guardado masivo completado.`);
    }, 5 * 60 * 1000); // 5 Minutos

    // v243.15: Helper para serializar datos de clan con roles y estados

    // v242.20: GESTIÓN DE CLANES (FLOTAS) - Modularizado en events/clanHandlers.js
    registerClanHandlers(socket, io, state);

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
            if (config.enemyModels && config.enemyModels["4"]) {
                console.log(`[ADMIN] Guardando RageTimer para Boss1: ${config.enemyModels["4"].rageTimer}s`);
            }
            
            // v245.10: Sincronizar configuración de hordas con el gestor
            if (config.hordeConfig) hordeManager.updateConfig(config.hordeConfig);
            
            // v3.9: Sincronía en Caliente (Update global memory)
            state.SERVER_CONFIG = config;
            
            console.log(`\x1b[35m[ADMIN]\x1b[0m Configuración guardada en disco y RAM.`);
            
            // v226.30: PURGA DE ENTIDADES PARA EVITAR FANTASMAS (Sincronía Limpia)
            // Notificar a todos los clientes que limpien su zona
            io.emit('adminConfigUpdated', config);
            io.emit('changeZoneDone', 1); // Forzar limpieza visual en clientes (Zona dummy para disparar el signal)
            
            // Vaciar enemigos en RAM para que el respawn los recree con nuevos datos
            Object.keys(enemies).forEach(id => delete enemies[id]);
            console.log(`[ADMIN] Purgados ${Object.keys(enemies).length} enemigos antiguos para re-sincronización.`);
            
        } catch (e) { console.error("Error guardando config:", e); }
    });
    
    // v266.999: Purga Administrativa de Enemigos (Botón de Pánico)
    socket.on('adminPurgeEnemies', () => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") return;
        const count = Object.keys(enemies).length;
        Object.keys(enemies).forEach(id => delete enemies[id]);
        console.log(`[ADMIN] Purga manual ejecutada por Caelli94. ${count} enemigos eliminados.`);
        io.emit('gameNotification', { msg: `PURGA COMPLETADA: ${count} enemigos eliminados.`, type: 'success' });
    });

    // v236.40: WARP ADMINISTRATIVO (Teletransporte Instantáneo)
    socket.on('warpToZone', async (data) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];
        if (p.user !== "Caelli94") return; // Protección Admin

        const newZone = data.zone || 1;
        const oldZone = p.zone;
        console.log(`[ADMIN-WARP] ${p.user} saltando a Zona ${newZone}`);

        socket.leave(`zone_${oldZone}`);
        socket.join(`zone_${newZone}`);

        p.zone = newZone;
        p.x = 2000;
        p.y = 2000;

        // v238.41: Persistencia Administrativa Instantánea
        try {
            const User = require('./models/User');
            await User.updateOne({ _id: socket.dbUser._id }, { $set: { "gameData.zone": newZone } });
        } catch (e) { console.error("Error persistiendo Warp:", e); }


        socket.emit('changeZoneDone', newZone);
        socket.to(`zone_${oldZone}`).emit('playerDisconnected', socket.id);
        io.to(`zone_${newZone}`).emit('newPlayer', { ...p, id: socket.id });
    });

    // v245.20: LISTENERS DE EVENTOS DE HORDAS
    socket.on('startHordeEvent', () => {
        if (!players[socket.id] || players[socket.id].user !== "Caelli94") return;
        if (state.SERVER_CONFIG && state.SERVER_CONFIG.hordeConfig) {
            state.SERVER_CONFIG.hordeConfig.active = true;
            hordeManager.updateConfig(state.SERVER_CONFIG.hordeConfig);
            console.log("[ADMIN] Evento de Hordas iniciado manualmente.");
            socket.emit('gameNotification', { msg: 'EVENTO DE HORDAS INICIADO', type: 'success' });
        }
    });

    socket.on('stopHordeEvent', () => {
        if (!players[socket.id] || players[socket.id].user !== "Caelli94") return;
        hordeManager.stopEvent();
        if (state.SERVER_CONFIG && state.SERVER_CONFIG.hordeConfig) state.SERVER_CONFIG.hordeConfig.active = false;
        socket.emit('gameNotification', { msg: 'EVENTO DETENIDO Y ZONA LIMPIADA', type: 'warning' });
    });

    socket.on('ping_custom', () => {

        socket.emit('pong_custom');
    });

    // SISTEMA DE CHAT v60.0
    socket.on('chatMessage', (data) => {
        if (!players[socket.id]) return;
        const sender = players[socket.id].user;
        const msg = data.msg.substring(0, 50); // Límite de 50 caracteres (v60.0)

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

    // v1.2: SISTEMA DE COMBATE Y HABILIDADES - Modularizado en systems/combatHandlers.js
    registerCombatHandlers(socket, io, state);

    // ENVIAR CONFIG AL CONECTAR
    fs.readJson(CONFIG_FILE).then(config => {
        if (config) socket.emit('adminConfigLoaded', config);
    }).catch(e => { /* Config por defecto en cliente */ });

    // v1.3: SISTEMA DE INVENTARIO Y ECONOMÍA - Modularizado en systems/inventoryHandlers.js
    registerInventoryHandlers(socket, io, state);

    // v220.81: TOGGLE PVP CONSENSUADO
    socket.on('togglePvP', async (enabled) => {
        const p = players[socket.id];
        if (!p) return;
        
        // v222.45: ANTI-COMBAT-LOG (Solo si intenta desactivar PVP)
        if (enabled === false && p.pvpEnabled === true) {
            const now = Date.now();
            const timeSincePvp = now - (p.lastPvpCombatTime || 0);
            
            if (timeSincePvp < 30000) {
                const remaining = Math.ceil((30000 - timeSincePvp) / 1000);
                return socket.emit('gameNotification', { 
                    msg: `┬íCOMBATE RECIENTE! Espera ${remaining}s para entrar en modo Seguro.`, 
                    type: "error" 
                });
            }
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
        
        // Avisar a todos incluyendo al due├▒o (para visual local)
        io.emit('playerUpdated', { id: socket.id, pvpEnabled: p.pvpEnabled });
        console.log(`[PVP] Piloto ${p.user} modo: ${enabled ? 'ACTIVO' : 'SEGURO'}`);
    });

    socket.on('latencyUpdate', (ms) => {
        if (players[socket.id]) {
            players[socket.id].latency = ms;
        }
    });

    // El cambio de nave (switchShip) está modularizado arriba.

    socket.on('playerMovement', async (movementData) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];

        // v200.30: ANTI-SPEEDHACK (Validaci├│n de Distancia)
        if (!p.speed && state.SERVER_CONFIG) {
            const ship = state.SERVER_CONFIG.shipModels.find(s => s.id === p.currentShipId);
            p.speed = ship ? ship.speed : 500;
        }

        // v210.0: ANTI-SPEEDHACK (Ajuste de Precisión)
        const dx = movementData.x - p.x;
        const dy = movementData.y - p.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        
        if (distance >= 1100 && !p.justBlinked && !p.isAdmin) { 
            console.log(`[HACK] Teletransporte detectado en ${p.user}: ${distance}px`);
            return;
        }
        
        if (p.justBlinked) p.justBlinked = false; // Reset tras el bypass

        p.x = movementData.x;
        p.y = movementData.y;
        p.lastPos = { x: p.x, y: p.y }; // v221.60: Sincron├¡a constante de posici├│n
        p.rotation = movementData.rotation;

        // v240.10: Sincron├¡a de Stats en Movimiento (Evita Reset al Disparar)
        // v240.65: Sincronía de Stats DESACTIVADA (El Servidor es Autoridad para evitar Ghost Bleeding)
        // if (movementData.hp !== undefined) p.hp = parseFloat(movementData.hp);
        // if (movementData.sh !== undefined) p.shield = parseFloat(movementData.sh);
        // v240.68: Bloqueo de Máximos desde el cliente (Autoridad Total del Servidor)
        // if (movementData.maxHp !== undefined) p.maxHp = parseFloat(movementData.maxHp);
        // if (movementData.maxSh !== undefined) p.maxShield = parseFloat(movementData.maxSh);
        // else if (movementData.maxShield !== undefined) p.maxShield = parseFloat(movementData.maxShield);

        if (movementData.selectedAmmo) p.selectedAmmo = movementData.selectedAmmo;

        const oldZone = Number(p.zone !== undefined ? p.zone : 1);
        const targetZone = (movementData.zone !== undefined) ? Number(movementData.zone) : oldZone;
        p.zone = targetZone;

        if (oldZone !== targetZone) {
            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${targetZone}`);
            
            // Notificar a los que ya estaban que llegamos nosotros
            socket.to(`zone_${targetZone}`).emit('newPlayer', { 
                ...p, 
                id: socket.id, 
                spheres: p.spheres,
                isInvisible: p.isInvisible 
            });

            // v268.55: FIX DE VISIBILIDAD - Delay para dar tiempo al cliente de procesar
            // changeZoneDone (que llega por el canal de warp) y actualizar su zona local
            // antes de recibir la lista de jugadores actuales.
            console.log(`[ZONE-SYNC] ${p.user} entró a zona ${targetZone}. Enviando estado en 350ms...`);
            setTimeout(() => {
                const currentPlayersInZone = {};
                Object.keys(players).forEach(pId => {
                    const otherP = players[pId];
                    if (otherP.zone === targetZone && pId !== socket.id) {
                        currentPlayersInZone[pId] = {
                            ...otherP,
                            id: pId,
                            zone: targetZone,
                            maxHp: otherP.maxHp || 2000,
                            maxShield: otherP.maxShield || 1000,
                            spheres: otherP.spheres
                        };
                    }
                });

                const cleanEnemiesInZone = {};
                Object.values(enemies).forEach(e => {
                    if (e.zone === targetZone) {
                        const { ai, ...data } = e;
                        cleanEnemiesInZone[e.id] = data;
                    }
                });

                const playerCount = Object.keys(currentPlayersInZone).length;
                const enemyCount = Object.keys(cleanEnemiesInZone).length;
                console.log(`[ZONE-SYNC] Enviando a ${p.user}: ${playerCount} jugadores, ${enemyCount} enemigos en zona ${targetZone}`);
                
                socket.emit('currentPlayers', currentPlayersInZone);
                socket.emit('currentEnemies', cleanEnemiesInZone);
            }, 350);
        }

        // v262.97: Restaurando Visibilidad Total (Fix Minimapa y Sincronía)
        socket.broadcast.to(`zone_${p.zone}`).emit('playerMoved', { 
            ...p, 
            id: socket.id, 
            spheres: p.spheres,
            isInvisible: p.isInvisible 
        });
    });

    socket.on('playerRespawn', (respawnData) => {
        if (!players[socket.id]) return;
        const p = players[socket.id];
        p.isDead = false;
        p.hp = respawnData.hp || p.maxHp || 1000;
        p.shield = respawnData.sh || p.maxShield || 500;
        p.x = respawnData.x || 2000;
        p.y = respawnData.y || 2000;
        // v186.27: Sincron├¡a de Resurrecci├│n Global (Evita "Otra Dimensi├│n")
        if (respawnData.zone) p.zone = Number(respawnData.zone);

        console.log(`DESCON: Piloto [${p.user}] ha reaparecido en Zona [${p.zone}]`);

        const respawnPayload = { ...p, id: socket.id, isDead: false };
        // v186.27: Sincron├¡a de Resurrecci├│n SEGMENTADA
        socket.to(`zone_${p.zone}`).emit('newPlayer', respawnPayload);
        socket.to(`zone_${p.zone}`).emit('playerStatSync', {
            id: socket.id,
            hp: p.hp,
            shield: p.shield,
            isDead: false,
            spheres: p.spheres
        });
    });

    socket.on('ping_custom', () => {
        socket.emit('pong_custom', {});
    });

    // Los eventos de daño (enemyHit, playerHitByEnemy, playerHitByPlayer) están modularizados arriba.

    socket.on('changeZone', async (zoneId) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];

        const oldZone = (p.zone !== undefined ? p.zone : 1);
        if (Number(oldZone) === Number(zoneId)) return; // Evitar cobro si ya est├í ah├¡

        try {
            const User = require('./models/User');
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            // Leer configuración de mapas (si existe)
            let COST = (Number(zoneId) > 2) ? 10 : 0;
            let minLevel = 1;
            
            if (state.SERVER_CONFIG.mapsConfig && state.SERVER_CONFIG.mapsConfig[zoneId]) {
                COST = state.SERVER_CONFIG.mapsConfig[zoneId].warpCost || 0;
                minLevel = state.SERVER_CONFIG.mapsConfig[zoneId].minLevel || 1;
            }

            // Validar Nivel
            if (user.gameData.level < minLevel) {
                socket.emit('authError', `REQUIERES NIVEL ${minLevel} PARA ENTRAR A ESTE SECTOR`);
                return;
            }

            // v215.50: Cobro dinámico por Salto de Sector
            if (user.gameData.ohcu < COST) {
                socket.emit('authError', 'OHCU INSUFICIENTES PARA EL SALTO');
                return;
            }

            user.gameData.ohcu -= COST;
            user.gameData.zone = zoneId; // v238.42: Persistencia de Sector en Salto
            user.markModified('gameData.ohcu');
            user.markModified('gameData.zone');
            await user.save();

            socket.dbUser = user;
            p.ohcu = user.gameData.ohcu;

            // Notificar nuevo balance y confirmar cambio de zona para limpieza de entidades
            socket.emit('inventoryData', { player: user.gameData });
            socket.emit('changeZoneDone', zoneId);

            const newSize = (Number(zoneId) === 1 ? 4000 : 2000);

            // Gesti├│n de Habitaciones v75.0 (Optimization)
            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${zoneId}`);

            p.zone = zoneId;
            p.x = newSize / 2;
            p.y = newSize / 2;

            console.log(`DESCON: Jugador [${p.user}] salt├│ al Sector [${zoneId}] - Costo: ${COST} OHCU`);

            // Avisar a la vieja zona que se fue y a la nueva que lleg├│
            socket.to(`zone_${oldZone}`).emit('playerDisconnected', socket.id);
            socket.to(`zone_${zoneId}`).emit('newPlayer', { ...p, id: socket.id, spheres: p.spheres });

            // v225.50: Configuraci├│n de Jefes deshabilitada por ahora en zonas superiores
            
            // v225.70: LIMPIEZA DE RESIDUOS - Asegurar que no hay enemigos en mapas 2-8
            if (Number(zoneId) >= 2) {
                Object.keys(enemies).forEach(eid => {
                    if (enemies[eid].zone === zoneId) delete enemies[eid];
                });
                console.log(`[CLEANUP] Zona ${zoneId} purgada al entrar jugador.`);
            }

            // v268.60: FIX DEFINITIVO - Sincronizar jugadores actuales en la zona destino
            // Este es el canal real de cambio de mapa, aquí va el fix de visibilidad.
            const currentPlayersInZone = {};
            Object.keys(players).forEach(pId => {
                const otherP = players[pId];
                if (Number(otherP.zone) === Number(zoneId) && pId !== socket.id) {
                    const { ai, ...cleanP } = otherP; // Evitar referencias circulares
                    currentPlayersInZone[pId] = {
                        ...cleanP,
                        id: pId,
                        zone: Number(zoneId), // Asegurar que la zona es la correcta
                        maxHp: otherP.maxHp || 2000,
                        maxShield: otherP.maxShield || 1000,
                        spheres: otherP.spheres || []
                    };
                }
            });
            
            const playerCount = Object.keys(currentPlayersInZone).length;
            console.log(`[ZONE-SYNC] ${p.user} llegó a zona ${zoneId}. Enviando ${playerCount} pilotos en 500ms...`);
            
            // Delay para que el cliente termine de procesar changeZoneDone antes de recibir jugadores
            setTimeout(() => {
                socket.emit('currentPlayers', currentPlayersInZone);
                console.log(`[ZONE-SYNC] currentPlayers enviado a ${p.user}: ${playerCount} pilotos.`);
            }, 500);

            // Sincronizar enemigos de la zona (inmediato, el cliente ya sabe manejarlos)
            const zoneEnemies = {};
            Object.keys(enemies).forEach(id => {
                if (enemies[id].zone === zoneId) {
                    const { ai, ...cleanData } = enemies[id];
                    zoneEnemies[id] = cleanData;
                }
            });
            socket.emit('currentEnemies', zoneEnemies);
            socket.emit('gameNotification', { msg: `Salto exitoso a Sector ${zoneId}`, type: 'success' });

        } catch (e) {
            console.error("Error en changeZone:", e);
        }
    });

    // SISTEMA DE TALENTOS (v300.70)
    socket.on('investSkill', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;
            
            let pts = user.gameData.skillPoints || 0;
            if (pts <= 0) return;
            
            const cat = data.category;
            const idx = data.index;
            if (!user.gameData.skillTree) user.gameData.skillTree = { engineering: [0,0,0,0,0,0,0,0], combat: [0,0,0,0,0,0,0,0], science: [0,0,0,0,0,0,0,0] };
            
            const branch = user.gameData.skillTree[cat] || [];
            
            // Autocompletado del array para evitar errores de índice out-of-bounds
            while (branch.length <= idx) branch.push(0);
            
            if (branch[idx] >= 5) return;
            
            branch[idx] += 1;
            user.gameData.skillTree[cat] = branch;
            user.gameData.skillPoints = pts - 1;
            
            // v300.75: Triple validación de guardado
            user.markModified('gameData.skillTree');
            user.markModified('gameData.skillPoints');
            user.markModified('gameData');
            
            // v300.90: ¡ACTUALIZAR RAM! (El bug mortal de sobreescritura)
            players[socket.id].skillTree = user.gameData.skillTree;
            players[socket.id].skillPoints = user.gameData.skillPoints;
            
            await user.save();
            console.log(`[DATABASE] Talento '${cat}' [${idx}] guardado para ${user.username}. Restantes: ${user.gameData.skillPoints}`);
            
            socket.dbUser = user;
            
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip || {});
            
            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj }
            });
        } catch(e) { console.error('[TALENT_ERROR]', e); }
    });

    socket.on('resetSkills', async () => {
        if (!socket.dbUser || !players[socket.id]) return;
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;
            
            const RESET_COST = 5000;
            if ((user.gameData.ohcu || 0) < RESET_COST) {
                return socket.emit('gameNotification', { msg: 'OHCU INSUFICIENTE PARA RESETEAR', type: 'error' });
            }
            
            let spent = 0;
            const tree = user.gameData.skillTree || { engineering: [], combat: [], science: [] };
            
            ['engineering', 'combat', 'science'].forEach(cat => {
                if (tree[cat] && Array.isArray(tree[cat])) {
                    tree[cat].forEach(lvl => { spent += lvl; });
                }
                tree[cat] = [0,0,0,0,0,0,0,0];
            });
            
            if (spent === 0) return socket.emit('gameNotification', { msg: 'NO HAY HABILIDADES PARA RESETEAR', type: 'error' });
            
            user.gameData.ohcu -= RESET_COST;
            user.gameData.skillPoints = (user.gameData.skillPoints || 0) + spent;
            user.gameData.skillTree = tree;
            
            user.markModified('gameData');
            
            // v300.90: ¡ACTUALIZAR RAM! 
            players[socket.id].skillTree = user.gameData.skillTree;
            players[socket.id].skillPoints = user.gameData.skillPoints;
            players[socket.id].ohcu = user.gameData.ohcu;
            
            await user.save();
            console.log(`[DATABASE] Árbol de habilidades reseteado para ${user.username}. Puntos devueltos: ${spent}`);
            
            socket.dbUser = user;
            
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip || {});
            
            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj }
            });
            socket.emit('gameNotification', { msg: 'ÁRBOL DE HABILIDADES RESETEADO', type: 'success' });
            
        } catch(e) { console.error('[RESET_SKILL_ERROR]', e); }
    });

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

            // Mandar confirmaci├│n de entrada mediante chat o notificaci├│n
            s.emit('gameNotification', { msg: 'Ingresando a Dungeon Privada...', type: 'alert' });
        });

        console.log(`[DUNGEON] Party teleportada a instancia: ${dungeonZoneId} con ${playersToMove.length} miembros.`);
    });
    socket.on('disconnect', async () => {
        if (players[socket.id]) {
            const p = players[socket.id];
            const username = p.user;
            console.log(`Desconectado: ${username}`);

            // v262.110: Guardado Autoritativo Final
            await savePlayerToDB(socket.id);

            delete players[socket.id];
            if (username) activeSessions.delete(username.toLowerCase());
            io.emit('playerDisconnected', socket.id);
            
            // v242.16: Notificar a la flota la desconexión del piloto
            if (p.clanId) {
                io.to(`clan_${p.clanId}`).emit('clanMemberStatus', { user: username, online: false });
            }
            
            // v220.11: ACTUALIZACI├ôN GLOBAL DE ONLINE AL SALIR
            io.emit('onlineCount', Object.keys(players).length);

            // v138.10: No borrar de la party al desconectar (F5 Persistence)
            const uid = socket.dbUser ? socket.dbUser._id.toString() : null;
            if (uid && playerParty[uid]) {
                const pid = playerParty[uid];
                if (parties[pid]) {
                    // Solo marcar como desconectado, NO borrar del grupo
                    io.emit('chatMessage', { sender: 'SYSTEM', msg: `${username.toUpperCase()} OFFLINE.`, channel: 'team', senderId: 'server' });
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
                
                console.log(`[HUD] Guardado Slot ${data.slotIndex} para ${players[socket.id].user}`);

                if (socket.dbUser) {
                    try {
                        const updatePath = `gameData.hudLayouts.${data.slotIndex}`;
                        const updateObj = { [updatePath]: players[socket.id].hudLayouts[data.slotIndex] };
                        updateObj["gameData.hudPositions"] = players[socket.id].hudPositions;
                        
                        await User.updateOne({ _id: socket.dbUser._id }, { $set: updateObj });
                        console.log(`[HUD-SLOT] Persistencia exitosa en DB para slot ${data.slotIndex}`);
                    } catch (e) { console.error("[HUD-SLOT-SAVE] Error DB:", e); }
                }
                return;
            }

            if (data.config !== undefined) players[socket.id].hudConfig = data.config;
            if (data.positions !== undefined) players[socket.id].hudPositions = data.positions;
            console.log(`[HUD] Config global recibida de ${players[socket.id].user}`);
            
            if (socket.dbUser) {
                try {
                    const updateObj = {};
                    if (data.config !== undefined) updateObj["gameData.hudConfig"] = data.config;
                    if (data.positions !== undefined) updateObj["gameData.hudPositions"] = data.positions;
                    
                    if (Object.keys(updateObj).length > 0) {
                        await User.updateOne({ _id: socket.dbUser._id }, { $set: updateObj });
                        console.log(`[HUD] Config global persistida en DB para ${players[socket.id].user}`);
                    }
                } catch (e) {
                    console.error("[HUD-SAVE] Error DB:", e);
                }
            }
        }
    });

    socket.on('saveHUD', async (data) => {
        if (players[socket.id] && socket.dbUser) {
            try {
                if (!players[socket.id].hudPositions) players[socket.id].hudPositions = {};
                players[socket.id].hudPositions[data.id] = data.pos;

                // v189.96: PERSISTENCIA INSTANT├üNEA (DB Atlas Write)
                const updatePath = `gameData.hudPositions.${data.id}`;
                await User.updateOne(
                    { _id: socket.dbUser._id },
                    { $set: { [updatePath]: data.pos } }
                );

                console.log(`[HUD-DB] Registro guardado: ${data.id} para ${players[socket.id].user}`);
            } catch (e) { console.error("Error en persistencia HUD:", e); }
        }
    });

    // SISTEMA DE PARTIES (GRUPOS) v63.1 - Con guardas anti-crash
    socket.on('inviteToParty', (targetName) => {
        try {
            if (!targetName || typeof targetName !== 'string') return;
            const targetSocket = [...io.sockets.sockets.values()].find(s => s.dbUser && s.dbUser.username === targetName.toLowerCase());

            if (!targetSocket) return socket.emit('authError', 'PILOTO NO ENCONTRADO O FUERA DE L├ìNEA');
            if (targetSocket.id === socket.id) return socket.emit('authError', 'NO PUEDES INVITARTE A TI MISMO');
            if (!players[socket.id]) return;

            targetSocket.emit('partyInvitation', {
                from: players[socket.id].user || 'Desconocido',
                fromId: socket.id
            });
        } catch (e) { console.error("Error en inviteToParty:", e); }
    });

    socket.on('acceptParty', (leaderSid) => {
        try {
            const leaderSocket = io.sockets.sockets.get(leaderSid);
            if (!leaderSocket || !leaderSocket.dbUser || !socket.dbUser) return socket.emit('authError', 'PILOTO NO DISPONIBLE');

            const leaderUid = leaderSocket.dbUser._id.toString();
            const myUid = socket.dbUser._id.toString();

            let partyId = playerParty[leaderUid];
            if (!partyId) {
                // Crear nueva party (v134.50 Persistence dbId Based)
                partyId = leaderUid;
                parties[partyId] = { id: partyId, members: [leaderUid], names: [leaderSocket.dbUser.username.toUpperCase()] };
                playerParty[leaderUid] = partyId;
            }

            if (parties[partyId].members.includes(myUid)) return;
            if (parties[partyId].members.length >= 8) return socket.emit('authError', 'EL GRUPO EST├ü LLENO (MAX 8)');

            parties[partyId].members.push(myUid);
            parties[partyId].names.push(socket.dbUser.username.toUpperCase());
            playerParty[myUid] = partyId;

            io.emit('partyUpdate', parties[partyId]);
            io.emit('chatMessage', {
                sender: 'SYSTEM', msg: `${socket.dbUser.username.toUpperCase()} se ha unido al grupo.`, channel: 'team', senderId: 'server'
            });
        } catch (e) {
            console.error("Error en acceptParty:", e);
        }
    });

    socket.on('leaveParty', () => {
        try {
            if (!socket.dbUser) return;
            const myUid = socket.dbUser._id.toString();
            const partyId = playerParty[myUid];
            if (!partyId || !parties[partyId]) return;

            const name = socket.dbUser.username.toUpperCase();
            parties[partyId].members = parties[partyId].members.filter(m => m !== myUid);
            parties[partyId].names = parties[partyId].names.filter(n => n !== name);

            if (parties[partyId].members.length <= 1) {
                parties[partyId].members.forEach(m => delete playerParty[m]);
                delete parties[partyId];
                io.emit('partyUpdate', null);
            } else {
                io.emit('partyUpdate', parties[partyId]);
            }
            delete playerParty[myUid];
            socket.emit('partyUpdate', null);
        } catch (e) {
            console.error("Error en leaveParty:", e);
        }
    });

    socket.on('kickFromParty', (targetUid) => {
        try {
            if (!socket.dbUser) return;
            const myUid = socket.dbUser._id.toString();
            const partyId = playerParty[myUid];
            
            // Solo el líder puede kickear (id de la party == líderUid)
            if (!partyId || partyId !== myUid || !parties[partyId]) return;
            if (targetUid === myUid) return; // No se puede kickear a sí mismo

            const targetIndex = parties[partyId].members.indexOf(targetUid);
            if (targetIndex === -1) return;

            parties[partyId].members.splice(targetIndex, 1);
            parties[partyId].names.splice(targetIndex, 1);
            delete playerParty[targetUid];

            if (parties[partyId].members.length <= 1) {
                parties[partyId].members.forEach(m => delete playerParty[m]);
                delete parties[partyId];
                io.emit('partyUpdate', null);
            } else {
                io.emit('partyUpdate', parties[partyId]);
            }
            
            // Avisar específicamente al expulsado
            const targetSocketId = Object.keys(players).find(sid => players[sid].dbId === targetUid);
            if (targetSocketId) io.to(targetSocketId).emit('partyUpdate', null);
            
        } catch (e) {
            console.error("Error en kickFromParty:", e);
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

http.listen(PORT, '0.0.0.0', () => {
    const ip = getLocalIP();
    console.log(`\x1b[36m+----------------------------------------------+`);
    console.log(`|  DESCON v6 - SERVIDOR MULTIPLAYER ACTIVO     |`);
    console.log(`|  IP: http://${ip}:${PORT}                    |`);
    console.log(`+----------------------------------------------+\x1b[0m\n`);
});
