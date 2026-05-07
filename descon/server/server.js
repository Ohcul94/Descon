require('dotenv').config();
const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http);
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
        x: user.gameData.lastPos?.x || 2000,
        y: user.gameData.lastPos?.y || 2000,
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
        isInvulnerable: false
    };

    const p_ref = players[socket.id];
    const hpBonus = 1.0 + ((p_ref.skillTree.engineering[0] || 0) * 0.02);
    const shBonus = 1.0 + ((p_ref.skillTree.engineering[1] || 0) * 0.02);
    p_ref.maxHp = Math.ceil(baseHp * hpBonus);
    p_ref.maxShield = Math.ceil(baseSh * shBonus);

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

    socket.emit('loginSuccess', {
        id: dbId,
        socketId: socket.id,
        user: username,
        clanTag: clanTag, // v244.110: Siglas para el NameTag local
        gameData: {
            ...JSON.parse(JSON.stringify(user.gameData)),
            equippedByShip: eByShipObj,
            equipped: user.gameData.equipped
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
            const user = await User.findOne({ username });

            if (!user) {
                return socket.emit('authError', 'Usuario o contraseña incorrectos.');
            }

            // COMPARACIÓN CRIPTOGRÁFICA (v35.0)
            const isMatch = await bcrypt.compare(data.password, user.password);
            if (!isMatch) {
                return socket.emit('authError', 'Credenciales inválidas en la Galaxia.');
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
                // v210.121: Sincronía de Mapa para Godot
                const eByShipObj = {};
                if (user.gameData.equippedByShip) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                }

                socket.emit('inventoryData', {
                    player: {
                        ...user.gameData.toObject(),
                        equippedByShip: eByShipObj,
                        equipped: user.gameData.equipped
                    }
                });
                console.log(`[SYNC] Inventario enviado a ${user.username} (Flota Sincronizada)`);
            }
        } catch (e) { console.error("Error en getInventory:", e); }
    });

    // GUARDAR PROGRESO (MongoDB)
    socket.on('saveProgress', async (gameData) => {
        if (!socket.dbUser || !gameData) return;
        try {
            const p = players[socket.id];
            if (!p) return;

            // v214.150: SINCRONÍA AUTORITATIVA TOTAL
            if (gameData.inventory && gameData.inventory.length > 0) p.inventory = gameData.inventory;
            if (gameData.spheres) p.spheres = gameData.spheres;
            if (gameData.equipped) p.equipped = gameData.equipped;
            if (gameData.skillTree) p.skillTree = gameData.skillTree;
            if (gameData.lastPos) p.lastPos = gameData.lastPos;

            const updateFields = {};

            // Campos de Red/Stat
            updateFields["gameData.hp"] = gameData.hp !== undefined ? gameData.hp : p.hp;
            updateFields["gameData.shield"] = gameData.shield !== undefined ? gameData.shield : p.shield;
            updateFields["gameData.ammo"] = gameData.ammo || p.ammo;
            updateFields["gameData.lastPos"] = p.lastPos;

            // Persistencia de Inventario y Flota
            updateFields["gameData.inventory"] = p.inventory;
            updateFields["gameData.spheres"] = p.spheres;
            updateFields["gameData.skillTree"] = p.skillTree;

            const shipId = p.currentShipId.toString();
            updateFields[`gameData.equippedByShip.${shipId}`] = p.equipped;
            updateFields["gameData.equipped"] = p.equipped;
            updateFields["gameData.zone"] = p.zone || 1; // v238.40: Persistencia de Mapa


            // v214.152: Persistencia Atómica de nivel y puntos (Sin recálculo destructivo)
            updateFields["gameData.hubs"] = p.hubs;
            updateFields["gameData.ohcu"] = p.ohcu;
            updateFields["gameData.exp"] = p.exp;
            updateFields["gameData.level"] = p.level;
            updateFields["gameData.skillPoints"] = p.skillPoints !== undefined ? p.skillPoints : (user.gameData.skillPoints || 0);

            const result = await User.updateOne({ _id: socket.dbUser._id }, { $set: updateFields });
            console.log(`[SAVE] Progreso de ${p.user} guardado. Lvl: ${p.level}, Puntos: ${p.skillPoints}`);

        } catch (e) { console.error("Error guardando progreso:", e); }
    });

    // v243.15: Helper para serializar datos de clan con roles y estados

    // v242.20: GESTIÓN DE CLANES (FLOTAS) - Modularizado en events/clanHandlers.js
    registerClanHandlers(socket, io, state);

    // SISTEMA ADMIN: GUARDAR CONFIGURACIÓN GLOBAL
    socket.on('saveAdminConfig', async (config) => {
        try {
            await fs.writeJson(CONFIG_FILE, config, { spaces: 4 });
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
        if (distance >= 1100) { 
            console.log(`[HACK] Teletransporte detectado en ${p.user}: ${distance}px`);
            return;
        }

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

        const oldZone = Number(p.zone || 1);
        const targetZone = (movementData.zone !== undefined) ? Number(movementData.zone) : oldZone;
        p.zone = targetZone;

        if (oldZone !== targetZone) {
            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${targetZone}`);
            socket.to(`zone_${targetZone}`).emit('newPlayer', { 
                ...p, 
                id: socket.id, 
                spheres: p.spheres,
                isInvisible: p.isInvisible // v245.88: Sincronía de Sigilo en cambio de mapa
            });
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

        const oldZone = p.zone || 1;
        if (Number(oldZone) === Number(zoneId)) return; // Evitar cobro si ya est├í ah├¡

        try {
            const User = require('./models/User');
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            // v215.50: Cobro por Salto de Sector
            const COST = 10;
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

            // Sincronizar enemigos locales
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
        serverSpawnEnemy(dungeonZoneId, 6, 1000, 1000);

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

            if (socket.dbUser) {
                try {
                    await User.updateOne(
                        { _id: socket.dbUser._id },
                        {
                            $set: {
                                "gameData.lastPos.x": Math.floor(p.x),
                                "gameData.lastPos.y": Math.floor(p.y),
                                "gameData.hp": Math.ceil(p.hp || 0),
                                "gameData.shield": Math.ceil(p.shield || 0),
                                "gameData.zone": p.zone || 1,
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
                } catch (e) { console.error("Error guardando estado final:", e); }
            }

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

    socket.on('saveHudLayout', (data) => {
        if (players[socket.id]) {
            players[socket.id].hudConfig = data.config;
            players[socket.id].hudPositions = data.positions;
            console.log(`[HUD] Config global guardada para ${players[socket.id].user}`);
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
