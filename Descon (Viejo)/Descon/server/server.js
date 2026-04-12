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
const bcrypt = require('bcrypt'); // Criptografía Pro v35.0

// Importación de Cerebros de IA (v85.20 Professional Architecture)
const ChaseAI = require('./behaviors/ChaseAI');
const OrbitAI = require('./behaviors/OrbitAI');
const BossAI = require('./behaviors/BossAI');
const AncientBossAI = require('./behaviors/AncientBossAI');

// Configuración
const PORT = process.env.PORT || 3333;
const CONFIG_FILE = path.join(__dirname, 'config.json');

// Conexión a MongoDB
mongoose.connect(process.env.MONGODB_URI)
    .then(() => console.log('\x1b[32m[DB]\x1b[0m Conectado a MongoDB Atlas'))
    .catch(err => {
        console.error('\x1b[31m[DB]\x1b[0m Error de conexión:', err.message);
        console.log('Asegurate de que MongoDB esté corriendo o que el URI en .env sea correcto.');
    });

// Asegurar que archivos existan
if (!fs.existsSync(CONFIG_FILE)) fs.writeJsonSync(CONFIG_FILE, null);

// Servir archivos estáticos desde la carpeta 'public'
app.use(express.static(path.join(__dirname, '../public')));

let players = {};
let activeSessions = new Map(); // username (lower) -> socket.id v33.0
let enemies = {};
let nextPlayerNum = 1;
let SERVER_CONFIG = null; // Memoria de configuración global v47.0
let parties = {}; // dbId -> { members: [dbIds], names: [strings] }
let playerParty = {}; // dbId -> leaderDbId

// Cargar configuración inicial
fs.readJson(CONFIG_FILE).then(config => {
    SERVER_CONFIG = config;
    console.log('\x1b[35m[SERVER]\x1b[0m Configuración maestro cargada.');
}).catch(() => {
    console.log('\x1b[33m[SERVER]\x1b[0m Usando configuración por defecto (config.json no encontrado).');
});

// Función para spawnear enemigos en el servidor (v107.10: Posición Dinámica)
function serverSpawnEnemy(zone = 1, forceType = null, posX = null, posY = null) {
    if (!forceType && zone === 1 && Object.keys(enemies).filter(e => enemies[e].zone === 1).length >= 15) return;
    const id = 'enemy_' + (zone === 2 || forceType === 4 ? 'titan_' : '') + Date.now() + Math.floor(Math.random() * 1000);
    const type = forceType || (zone === 2 ? 4 : (Math.floor(Math.random() * 3) + 1));

    const initialHp = (type === 5 ? 200000 : (type === 4 ? 100000 : (type * 2000)));
    const initialShield = (type === 5 ? 100000 : (type === 4 ? 50000 : (type * 1000)));

    const e = {
        id, type, zone,
        x: posX || ((zone === 2 || zone === 3) ? (zone === 2 ? 1000 : 1250) : (Math.random() * 3400 + 300)),
        y: posY || ((zone === 2 || zone === 3) ? (zone === 2 ? 1000 : 1250) : (Math.random() * 3400 + 300)),
        hp: initialHp,
        maxHp: initialHp,
        shield: initialShield,
        maxShield: initialShield,
        rotation: 0,
        lastHit: 0,
        lastDash: 0,
        shotsInBurst: 0,
        nextShotTime: 0
    };

    // Asignar Inteligencia Artificial según Tipo (v85.20 / v87.20 / v98.50 Ancient / v102.10 Brain)
    const aiConfig = { bulletDamage: (type * 100), fireRate: 2000, speed: (type === 1 ? 4.5 : 3.5) };
    if (type === 5) e.ai = new AncientBossAI(e, aiConfig); // NUEVO Cerebro Ancient v102.10
    else if (type === 4) e.ai = new BossAI(e, aiConfig); // Jefe Lord Titán v87.20
    else if (type === 1) e.ai = new ChaseAI(e, aiConfig);
    else e.ai = new OrbitAI(e, aiConfig);

    enemies[id] = e;

    // Enviar solo datos de renderizado para evitar referencias circulares (v86.00)
    const { ai, ...spawnData } = e;
    io.emit('enemySpawn', spawnData);
}

// Spawn inicial y periódico
setInterval(serverSpawnEnemy, 5000);
for (let i = 0; i < 10; i++) serverSpawnEnemy();

// GUARDIANÍA DE JEFES (Asegurar 1 BOSS siempre en su mapa v89.50 / v98.50)
let lastTitanDeath = 0;
let lastAncientDeath = 0;
setInterval(() => {
    // Guardián Titán (Zona 1)
    const hasTitan = Object.values(enemies).some(e => e.type === 4);
    if (!hasTitan && Date.now() - lastTitanDeath > 3000) {
        serverSpawnEnemy(1, 4);
    }
    // Guardián Ancient (Zona 3)
    const hasAncient = Object.values(enemies).some(e => e.type === 5);
    if (!hasAncient && Date.now() - lastAncientDeath > 3000) {
        serverSpawnEnemy(3, 5);
    }
}, 1000);

// LOOP DE IA Y MOVIMIENTO GLOBAL (v85.20 Modular AI Engine)
setInterval(() => {
    const now = Date.now();
    const enemiesByZone = { 1: [], 2: [], 3: [] };
    const zoneMoveData = { 1: {}, 2: {}, 3: {} };

    // Clasificación Inicial O(n) - Un solo pase
    for (const id in enemies) {
        const e = enemies[id];
        if (e.hp > 0) enemiesByZone[e.zone].push(e);
    }

    // Proceso por Zona (Ahorro del 900% en CPU)
    for (let z = 1; z <= 3; z++) {
        const zoneList = enemiesByZone[z];
        const listLen = zoneList.length;

        for (let i = 0; i < listLen; i++) {
            const e = zoneList[i];

            // 1. Actualizar IA
            if (e.ai) e.ai.update(players, now, io);

            // 2. Repulsión Física (Solo contra naves de su propia zona)
            for (let j = i + 1; j < listLen; j++) {
                const other = zoneList[j];
                const dx = e.x - other.x;
                const dy = e.y - other.y;
                const distSq = dx * dx + dy * dy;

                if (distSq < 2025) { // 45px al cuadrado
                    const pushAngle = Math.atan2(dy, dx);
                    const force = 1.2;
                    e.x += Math.cos(pushAngle) * force;
                    e.y += Math.sin(pushAngle) * force;
                    other.x -= Math.cos(pushAngle) * force;
                    other.y -= Math.sin(pushAngle) * force;
                }
            }

            // 3. Preparar datos de Red
            zoneMoveData[z][e.id] = {
                id: e.id, x: e.x, y: e.y, rotation: e.rotation,
                hp: e.hp, shield: e.shield, zone: e.zone, type: e.type,
                isRyze: e.isRyze || false,
                isRamming: e.ai && e.ai.isRamming,
                isCountering: e.isCountering || false,
                isInvulnerable: e.isInvulnerable || false
            };
        }

        // Broadcast Segmentado
        if (listLen > 0) {
            io.to(`zone_${z}`).emit('enemiesMoved', zoneMoveData[z]);
        }
    }

    // v164.68: BUCLE DE REGENERACIÓN AUTORITATIVA (Jugadores 10% HP/SH)
    Object.values(players).forEach(p => {
        const delay = p.regenDelay || 5000;
        if (!p.isDead && (now - (p.lastCombatTime || 0)) > delay) {
            let changed = false;
            const regenAmountHp = p.maxHp * 0.01; // v164.87: 1% HP per second (Legacy Balance)
            const regenAmountSh = p.maxShield * 0.02; // v164.87: 2% SH per second (Legacy Balance)

            // Regenerar Escudo (Prioridad 1)
            if (p.shield < p.maxShield) {
                p.shield += (regenAmountSh / 30.0);
                if (p.shield > p.maxShield) p.shield = p.maxShield; // v164.80: Forzar tope 100%
                changed = true;
            }
            // Regenerar Integridad (Prioridad 2)
            if (p.hp < p.maxHp) {
                p.hp += (regenAmountHp / 30.0);
                if (p.hp > p.maxHp) p.hp = p.maxHp; // v164.80: Forzar tope 100%
                changed = true;
            }

            // v192.10: Sincronía Diferencial (Optimización de Ancho de Banda)
            if (changed && now - (p.lastRegenSync || 0) > 1000) {
                const diffHp = Math.abs(p.hp - (p.lastSyncHp || 0));
                const diffSh = Math.abs(p.shield - (p.lastSyncSh || 0));

                // Solo mandamos paquete si varió más del 1.5% (Evitar spam de red)
                if (diffHp > (p.maxHp * 0.015) || diffSh > (p.maxShield * 0.015)) {
                    p.lastRegenSync = now;
                    p.lastSyncHp = p.hp;
                    p.lastSyncSh = p.shield;
                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: p.socketId,
                        hp: Math.ceil(p.hp),
                        shield: Math.ceil(p.shield),
                        spheres: p.spheres, // v214.195: Sincronía visual continua
                        isDead: false
                    });
                }
            }
        }
    });
}, 33);

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
            socket.dbUser = newUser;
            socket.emit('authSuccess', { user: username, msg: '¡Identidad blindada y grabada en la Galaxia!' });
            console.log(`Usuario registrado (Cifrado): ${username}`);
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
            socket.dbUser = user;

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
                // Si el de la nave está vacío pero el global tiene algo, rescatar el global (Fail-safe)
                if ((!raw.w || raw.w.length == 0) && (user.gameData.equipped && user.gameData.equipped.w && user.gameData.equipped.w.length > 0)) {
                    raw = user.gameData.equipped;
                }
                return JSON.parse(JSON.stringify(raw));
            })();

            players[socket.id] = {
                id: dbId,
                socketId: socket.id,
                num: nextPlayerNum++,
                user: username,
                x: user.gameData.lastPos?.x || 0,
                y: user.gameData.lastPos?.y || 0,
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
                spheres: user.gameData.spheres || [
                    { "name": "Alfa", "type": "w", "color": "#ffe031", "equipped": null },
                    { "name": "Beta", "type": "s", "color": "#31dfff", "equipped": null },
                    { "name": "Gamma", "type": "e", "color": "#3bff31", "equipped": null }
                ],
                hudConfig: user.gameData.hudConfig || {},
                hudPositions: user.gameData.hudPositions || {},
                hubs: user.gameData.hubs || 0,
                ohcu: user.gameData.ohcu || 0,
                exp: user.gameData.exp || 0,
                currentShipId: user.gameData.currentShipId || 1,
                zone: user.gameData.zone || 1
            };

            // v196.60: Recalcular Stats con Talentos al Login (Fix Relogueo)
            const p_ref = players[socket.id];
            const hpBonus = 1.0 + ((p_ref.skillTree.engineering[0] || 0) * 0.02);
            const shBonus = 1.0 + ((p_ref.skillTree.engineering[1] || 0) * 0.02);
            p_ref.maxHp = Math.ceil(baseHp * hpBonus);
            p_ref.maxShield = Math.ceil(baseSh * shBonus);

            // Cargar Configuración Admin (v39.0 - Sincronizada con Login)
            // v196.00: Sincronía de Configuración Admin
            let adminConfig = null;
            try { adminConfig = await fs.readJson(CONFIG_FILE); } catch (e) { }


            // v210.120: Serialización POJO para que Godot entienda el Mapa de Flota (v210.122: Asegurar POJO)
            const eByShipObj = {};
            if (user.gameData.equippedByShip) {
                if (user.gameData.equippedByShip instanceof Map) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                } else {
                    Object.assign(eByShipObj, user.gameData.equippedByShip);
                }
            }

            socket.emit('loginSuccess', {
                id: dbId, // Identidad Galáctica v123.20
                socketId: socket.id,
                user: username,
                gameData: {
                    ...user.gameData.toObject(),
                    equippedByShip: eByShipObj,
                    equipped: user.gameData.equipped // Asegurar sincronía de nave activa
                },
                adminConfig: adminConfig
            });

            // Unirse a la 'room' de su zona actual para optimización v75.0
            const userZone = players[socket.id].zone || 1;
            socket.join(`zone_${userZone}`);

            console.log(`DESCON: Piloto [${username}] logueado. Zona: ${userZone}. Jugadores totales: ${Object.keys(players).length}`);

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

            // v186.25: BROADCAST AGRESIVO - Usar io.emit global para asegurar visibilidad total
            const playerSpawnData = { ...players[socket.id], id: socket.id };

            // Sincronía con delay mínimo para asegurar que el cliente procesó el loginSuccess
            setTimeout(() => {
                socket.emit('currentPlayers', currentPlayersInZone);
                socket.emit('currentEnemies', cleanEnemiesInZone);
                
                // v214.110: BROADCAST SELECTIVO (Avisar a los demás, pero no a mí mismo, yo ya tengo loginSuccess)
                socket.broadcast.emit('newPlayer', { ...playerSpawnData, spheres: p_ref.spheres });
                console.log(`[NET] Piloto ${username} anunciado a la galaxia.`);
            }, 100);
            console.log(`Usuario logueado: ${username}`);

            // v135.30: Reconectar y NOTIFICAR a todos el regreso del aliado
            if (playerParty[dbId]) {
                const pid = playerParty[dbId];
                if (parties[pid]) {
                    // Notificar a todos que el grupo está completo de nuevo
                    setTimeout(() => {
                        io.emit('partyUpdate', parties[pid]);
                        io.emit('chatMessage', { sender: 'SYSTEM', msg: `${username.toUpperCase()} ha vuelto a la flota.`, channel: 'team', senderId: 'server' });
                    }, 500);
                }
            }
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

            // v214.151: RECALCULO MATEMÁTICO DE PUNTOS (Fix Nivel vs Puntos)
            let spent = 0;
            if (p.skillTree) {
                for (let cat in p.skillTree) {
                    if (Array.isArray(p.skillTree[cat])) {
                        p.skillTree[cat].forEach(v => spent += (v || 0));
                    }
                }
            }
            p.skillPoints = Math.max(0, (p.level - 1) - spent);
            
            // Forzar Atómicos (Riqueza y Nivel)
            updateFields["gameData.hubs"] = p.hubs;
            updateFields["gameData.ohcu"] = p.ohcu;
            updateFields["gameData.exp"] = p.exp;
            updateFields["gameData.level"] = p.level;
            updateFields["gameData.skillPoints"] = p.skillPoints;

            await User.updateOne({ _id: socket.dbUser._id }, { $set: updateFields });
            console.log(`[SAVE] Progreso de ${p.user} blindado. Lvl: ${p.level}, Puntos: ${p.skillPoints}`);
        } catch (e) { console.error("Error guardando progreso:", e); }
    });

    // SISTEMA ADMIN: GUARDAR CONFIGURACIÓN GLOBAL
    socket.on('saveAdminConfig', async (config) => {
        try {
            await fs.writeJson(CONFIG_FILE, config, { spaces: 4 });
            SERVER_CONFIG = config; // Actualizar memoria v47.0
            console.log(`\x1b[35m[ADMIN]\x1b[0m Configuración guardada en disco por ${players[socket.id] ? players[socket.id].user : 'Admin'}.`);
        } catch (e) { console.error("Error guardando config:", e); }
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

    // SISTEMA DE COMBATE MULTIPLAYER (v62.0)
    // v200.20: SISTEMA DE DAÑO AUTORITATIVO (Anti-Cheat Server-Side)
    socket.on('playerFire', (fireData) => {
        const p = players[socket.id];
        if (!p || !SERVER_CONFIG) return;

        // v200.35: VALIDACIÓN DE CADENCIA (Anti-RapidFire Hack)
        const now = Date.now();
        const lastFire = p.lastFireTime || 0;
        const cooldownMs = 800; // 1s teórico - 200ms de tolerancia por lag
        if (now - lastFire < cooldownMs) {
            // console.log(`[HACK] Cadencia de tiro sospechosa en ${p.user}`);
            return; // Bloqueo de ráfagas ilegales
        }
        p.lastFireTime = now;

        // 1. Validar Munición (Si no tiene en el servidor, el disparo es inválido)
        const ammoType = fireData.type || 'laser';
        const ammoTier = fireData.ammoType || 0;
        if (!p.ammo || !p.ammo[ammoType] || p.ammo[ammoType][ammoTier] <= 0) {
            return; // Bloqueo de disparo sin balas (Server level)
        }

        // Descontar munición en el servidor
        p.ammo[ammoType][ammoTier] -= 1;

        // 2. Calcular Daño Legítimo (Ignorar lo que diga el cliente)
        let baseDamage = 100;
        if (p.equipped && p.equipped.w) {
            baseDamage = 0;
            p.equipped.w.forEach(item => {
                const masterItem = SERVER_CONFIG.shopItems.weapons.find(w => w.id === item.id);
                if (masterItem) baseDamage += (masterItem.base || 0);
            });
        }
        if (baseDamage <= 0) baseDamage = 100;

        const mults = SERVER_CONFIG.ammoMultipliers[ammoType] || [1];
        const multiplier = mults[ammoTier] || 1;
        const finalAuthorizedDamage = baseDamage * multiplier;

        fireData.damageBoost = finalAuthorizedDamage;

        socket.to(`zone_${p.zone}`).emit('playerFire', {
            id: socket.id,
            ...fireData
        });
    });

    // v200.12: SISTEMA DE HABILIDADES DE ESFERAS (Sincronía Autoritaria)
    socket.on('playerSphereSkill', (data) => {
        const p = players[socket.id];
        if (!p || !p.spheres) return;

        const now = Date.now();
        const sphereIdx = data.id !== undefined ? data.id : -1;
        if (sphereIdx < 0 || sphereIdx >= 3) return;

        // v210.5: VALIDACIÓN DE COOLDOWN (Anti-Skill Spam)
        if (!p.sphereCooldowns) p.sphereCooldowns = [0, 0, 0];
        const lastUsed = p.sphereCooldowns[sphereIdx];
        const skillCooldown = 4800; // 5s oficiales - 200ms de gracia por lag

        if (now - lastUsed < skillCooldown) {
            // console.log(`[SPHERES] Rechazando skill de ${p.user}: Cooldown pendiente.`);
            return;
        }

        // v200.45: VALIDACIÓN DE PODER (Ignorar powerValue del cliente)
        let healAmt = 0;
        const sphere = p.spheres[sphereIdx];
        if (sphere && sphere.equipped) {
            // Si es un objeto serializado (login de-serialized) o dict
            healAmt = sphere.equipped.power_value || 0;
        }

        if (healAmt <= 0) return; // Hack detected or no skill equipped

        p.sphereCooldowns[sphereIdx] = now; // Registrar uso legítimo

        if (data.skillName === "ESCUDO CELULAR") {
            p.shield = Math.min((p.shield || 0) + healAmt, p.maxShield || 2000);
        } else if (data.skillName === "AUTO-REPARACIÓN") {
            p.hp = Math.min((p.hp || 0) + healAmt, p.maxHp || 3000);
        }

        // v200.12: Sincronía Crítica - Forzar actualización inmediata para evitar rollback
        p.lastSyncHp = p.hp;
        p.lastSyncSh = p.shield;

        io.to(`zone_${p.zone}`).emit('playerStatSync', {
            id: socket.id,
            hp: Math.ceil(p.hp),
            shield: Math.ceil(p.shield),
            spheres: p.spheres,
            isDead: false
        });

        console.log(`[SPHERES] Piloto ${p.user} usó ${data.skillName}. Cooldown iniciado.`);
    });

    // ENVIAR CONFIG AL CONECTAR
    fs.readJson(CONFIG_FILE).then(config => {
        if (config) socket.emit('adminConfigLoaded', config);
    }).catch(e => { /* Config por defecto en cliente */ });

    // SISTEMA DE TIENDA Y ADQUISICIÓN v164.2 (Sync Godot/Phaser)
    socket.on('buyItem', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        try {
            const { category, itemId, currency, amount } = data;
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            // Buscar el item en la config del servidor (v164.3 Fix: Godot/Phaser ID Sync)
            let itemConfig = null;
            if (category === 'ships') {
                itemConfig = SERVER_CONFIG.shipModels.find(m => m.id == itemId || m.name.toLowerCase() == itemId.toString().toLowerCase());
            } else if (category === 'ammo') {
                const type = itemId.split('_')[1].substring(0, 1);
                const fullType = type === 'l' ? 'laser' : (type === 'm' ? 'missile' : 'mine');
                itemConfig = SERVER_CONFIG.shopItems.ammo[fullType].find(m => m.id === itemId);
            } else {
                // Buscar por ID exacto o por el ID que envía Godot (ej: las1, sh2, en3)
                itemConfig = SERVER_CONFIG.shopItems[category].find(m => m.id == itemId);
                if (!itemConfig) {
                    // Fallback: Si Godot envía el nombre o un ID transformado
                    itemConfig = SERVER_CONFIG.shopItems[category].find(m => m.name.toLowerCase() == itemId.toString().toLowerCase());
                }
            }

            if (!itemConfig) {
                console.log(`[SHOP] Error: Item ${itemId} no encontrado en categoría ${category}`);
                return socket.emit('authError', 'ITEM NO ENCONTRADO EN LA GALAXIA');
            }

            const pricePerUnit = itemConfig.prices[currency];
            const totalPrice = category === 'ammo' ? Math.floor((amount / 100.0) * pricePerUnit) : pricePerUnit;

            if (user.gameData[currency] < totalPrice) {
                return socket.emit('authError', `FONDOS INSUFICIENTES DE ${currency.toUpperCase()}`);
            }

            // Deducción de Fondos
            user.gameData[currency] -= totalPrice;

            // Entrega del Ítem (v164.3 Fix: Persistence delivery)
            if (category === 'ships') {
                const shipIdNum = parseInt(itemConfig.id);
                if (user.gameData.ownedShips.includes(shipIdNum)) {
                    return socket.emit('authError', 'YA POSEES ESTA NAVE');
                }
                user.gameData.ownedShips.push(shipIdNum);
            } else if (category === 'ammo') {
                const typeKey = itemId.split('_')[1].substring(0, 1) === 'l' ? 'laser' : (itemId.split('_')[1].substring(0, 1) === 'm' ? 'missile' : 'mine');
                const tier = itemConfig.tier || 0;
                if (!user.gameData.ammo) user.gameData.ammo = { laser: [0, 0, 0, 0, 0, 0], missile: [0, 0, 0, 0, 0, 0], mine: [0, 0, 0, 0, 0, 0] };
                user.gameData.ammo[typeKey][tier] = (user.gameData.ammo[typeKey][tier] || 0) + (amount || 1000);
            } else {
                // Crear instancia única con ID para el inventario
                const newItem = {
                    id: itemConfig.id,
                    name: itemConfig.name,
                    type: itemConfig.type || (category === 'weapons' ? 'w' : (category === 'shields' ? 's' : (category === 'engines' ? 'e' : 'x'))),
                    base: itemConfig.base,
                    instanceId: Date.now() + Math.random().toString(36).substr(2, 5)
                };
                if (!user.gameData.inventory) user.gameData.inventory = [];
                user.gameData.inventory.push(newItem);
            }

            // v214.125: PERSISTENCIA TOTAL (Fuerza a Mongo a grabar arrays/objetos profundos)
            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            if (players[socket.id]) {
                players[socket.id].hubs = user.gameData.hubs;
                players[socket.id].ohcu = user.gameData.ohcu;
                players[socket.id].ammo = user.gameData.ammo;
            }

            // Notificar éxito y enviar inventario fresco (v164.7 Godot Sync Absolute)
            const responseData = {
                player: user.gameData
            };
            socket.emit('inventoryData', responseData);
            // socket.emit('loginSuccess', { id: user._id.toString(), user: user.username, gameData: user.gameData }); // ELIMINADO v164.11: Evita el reset de posición al comprar

            console.log(`[SHOP] Compra exitosa: ${user.username} compró ${itemId}`);
        } catch (e) {
            console.error("Error en buyItem:", e);
            socket.emit('authError', 'ERROR EN LA COMPRA - REINTENTE');
        }
    });

    // SISTEMA DE DISTRIBUCIÓN DE TALENTOS v164.2 (Clon commit 30671f + ANTI-HACK)
    socket.on('investSkill', async (data) => {
        if (!socket.dbUser) return;
        try {
            const { category, index } = data;
            if (index < 0 || index > 7) return;

            const user = await User.findById(socket.dbUser._id);
            if (!user || user.gameData.skillPoints <= 0) return socket.emit('gameNotification', { msg: 'SIN PUNTOS DE HABILIDAD', type: 'warn' });

            // v214.50: ANTI-HACK (Validar integridad del árbol)
            let totalSpent = 0;
            if (user.gameData.skillTree) {
                Object.values(user.gameData.skillTree).forEach(branch => {
                    if (Array.isArray(branch)) branch.forEach(val => totalSpent += val);
                });
            }
            if (totalSpent >= user.gameData.level) {
                return socket.emit('gameNotification', { msg: 'LIMITE DE TALENTOS ALCANZADO POR NIVEL', type: 'warn' });
            }

            if (user.gameData.skillTree[category][index] < 5) {
                user.gameData.skillTree[category][index]++;
                user.gameData.skillPoints--;

                // Persistencia de Oro
                user.markModified('gameData.skillTree');
                user.markModified('gameData');
                await user.save();

                socket.dbUser = user;
                if (players[socket.id]) {
                    const p = players[socket.id];
                    p.skillTree = user.gameData.skillTree;
                    p.skillPoints = user.gameData.skillPoints;

                    // Recalcular con bases reales
                    const hpBonus = 1.0 + ((p.skillTree.engineering[0] || 0) * 0.02);
                    const shBonus = 1.0 + ((p.skillTree.engineering[1] || 0) * 0.02);
                    p.maxHp = Math.ceil((p.baseHp || 2000) * hpBonus);
                    p.maxShield = Math.ceil((p.baseShield || 1000) * shBonus);

                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: socket.id,
                        hp: p.hp, shield: p.shield,
                        maxHp: p.maxHp, maxShield: p.maxShield, 
                        isDead: false,
                        spheres: p.spheres
                    });
                }
                socket.emit('inventoryData', { player: user.gameData });
            }
        } catch (e) { console.error("Error en investSkill seguro:", e); }
    });

    socket.on('resetSkills', async () => {
        if (!socket.dbUser || !players[socket.id]) return;
        try {
            const p = players[socket.id];
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            if (user.gameData.ohcu < 5000) return socket.emit('gameNotification', { msg: 'OHCU INSUFICIENTE PARA RESET', type: 'warn' });

            user.gameData.ohcu -= 5000;
            user.gameData.skillPoints = (p.level || 1) - 1;
            user.gameData.skillTree = {
                engineering: [0, 0, 0, 0, 0, 0, 0, 0],
                combat: [0, 0, 0, 0, 0, 0, 0, 0],
                science: [0, 0, 0, 0, 0, 0, 0, 0]
            };

            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            p.ohcu = user.gameData.ohcu;
            p.skillPoints = user.gameData.skillPoints;
            p.skillTree = user.gameData.skillTree;
            p.maxHp = p.baseHp || 2000;
            p.maxShield = p.baseShield || 1000;

            socket.emit('inventoryData', { player: user.gameData });
            io.to(`zone_${p.zone}`).emit('playerStatSync', {
                id: socket.id, hp: p.hp, shield: p.shield,
                maxHp: p.maxHp, maxShield: p.maxShield, isDead: false,
                spheres: p.spheres
            });
        } catch (e) { console.error("Error en resetSkills:", e); }
    });

    // SISTEMA DE EQUIPAMIENTO v164.8 (Persistence Sync)
    socket.on('equipItem', async (data) => {
        if (!socket.dbUser) return;
        try {
            const { instanceId, category, shipId } = data; // v210.100: shipId opcional
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const targetShipId = shipId ? parseInt(shipId) : user.gameData.currentShipId;
            if (!user.gameData.ownedShips.includes(targetShipId)) return socket.emit('authError', 'NAVE NO POSEÍDA');

            const itemIdx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
            if (itemIdx === -1) return socket.emit('authError', 'ÍTEM NO ENCONTRADO EN BODEGA');

            const item = user.gameData.inventory[itemIdx];
            const type = item.type; // w, s, e, x

            // Validar Slots de la nave objetivo (v210.101)
            const currentShip = SERVER_CONFIG.shipModels.find(m => m.id === targetShipId);
            const maxSlots = (currentShip && currentShip.slots) ? (currentShip.slots[type] || 0) : 0;

            // Obtener el buffer de equipo de esa nave específica
            if (!user.gameData.equippedByShip) user.gameData.equippedByShip = new Map();
            let shipEquip = user.gameData.equippedByShip.get(targetShipId.toString()) || { w: [], s: [], e: [], x: [] };

            if (!shipEquip[type]) shipEquip[type] = [];
            if (shipEquip[type].length >= maxSlots) {
                return socket.emit('authError', 'SLOTS DE EQUIPAMIENTO LLENOS EN ESTA NAVE');
            }

            // Mover de inventario a equipado
            shipEquip[type].push(item);
            user.gameData.inventory.splice(itemIdx, 1);

            // Actualizar mapa y campo global si es la nave activa
            user.gameData.equippedByShip.set(targetShipId.toString(), JSON.parse(JSON.stringify(shipEquip)));
            if (targetShipId === user.gameData.currentShipId) {
                user.gameData.equipped = JSON.parse(JSON.stringify(shipEquip));
                user.markModified('gameData.equipped');
            }

            user.markModified('gameData.equippedByShip');
            user.markModified('gameData.inventory');
            await user.save();
            socket.dbUser = user;

            // v210.102: Serialización POJO para enviar al cliente
            const eByShipObj = {};
            user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });

            const responseData = {
                player: {
                    ...user.gameData.toObject(),
                    equippedByShip: eByShipObj,
                    equipped: user.gameData.equipped // Siempre enviar el de la nave activa para el Player.gd
                }
            };
            socket.emit('inventoryData', responseData);

            if (players[socket.id] && targetShipId === user.gameData.currentShipId) {
                players[socket.id].inventory = user.gameData.inventory;
                players[socket.id].equipped = JSON.parse(JSON.stringify(user.gameData.equipped));
            }
        } catch (e) { console.error("Error en equipItem:", e); }
    });

    socket.on('unequipItem', async (data) => {
        if (!socket.dbUser) return;
        try {
            const { category, index, shipId } = data; // v210.110: shipId opcional
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const targetShipId = shipId ? parseInt(shipId) : user.gameData.currentShipId;
            const shipKey = targetShipId.toString();

            // v210.111: Obtener equipo de la nave específica
            if (!user.gameData.equippedByShip) user.gameData.equippedByShip = new Map();
            let shipEquip = user.gameData.equippedByShip.get(shipKey);

            // Fallback si es la activa y no está en el mapa aún
            if (!shipEquip && targetShipId === user.gameData.currentShipId) {
                shipEquip = JSON.parse(JSON.stringify(user.gameData.equipped || { w: [], s: [], e: [], x: [] }));
            }

            if (!shipEquip || !shipEquip[category] || !shipEquip[category][index]) return;

            const item = shipEquip[category][index];
            user.gameData.inventory.push(item);
            shipEquip[category].splice(index, 1);

            // v210.71: Sincronía Per-Ship (Guardar cambio en el cajón)
            user.gameData.equippedByShip.set(shipKey, JSON.parse(JSON.stringify(shipEquip)));

            // Si es la activa, actualizar también el global legacy
            if (targetShipId === user.gameData.currentShipId) {
                user.gameData.equipped = JSON.parse(JSON.stringify(shipEquip));
                user.markModified('gameData.equipped');
            }

            user.markModified('gameData.equippedByShip');
            user.markModified('gameData.inventory');
            await user.save();
            socket.dbUser = user;

            // v210.112: Serialización POJO (Map -> Object)
            const eByShipObj = {};
            user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });

            const responseData = {
                player: {
                    ...user.gameData.toObject(),
                    equippedByShip: eByShipObj,
                    equipped: user.gameData.equipped
                }
            };
            socket.emit('inventoryData', responseData);

            // v164.12: Actualizar RAM del server para evitar desvios
            if (players[socket.id] && targetShipId === user.gameData.currentShipId) {
                players[socket.id].inventory = user.gameData.inventory;
                players[socket.id].equipped = JSON.parse(JSON.stringify(user.gameData.equipped));
            }
        } catch (e) { console.error("Error en unequipItem:", e); }
    });

    // v214.190: Desequipar Esferas Orbitales
    socket.on('unequipSphere', async (data) => {
        if (!socket.dbUser) return;
        const { sphereId } = data; // 0, 1 o 2
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            if (!user.gameData.spheres) user.gameData.spheres = [];
            
            // v214.191: Saneamiento de Desequipamiento (Asegurar que el slot existe antes de limpiar)
            if (user.gameData.spheres[sphereId]) {
                user.gameData.spheres[sphereId].equipped = null;
                user.markModified('gameData.spheres');
                await user.save();
                socket.dbUser = user;

                // Sync RAM local del servidor
                if (players[socket.id]) {
                    players[socket.id].spheres = user.gameData.spheres;
                }

                // Notificar al dueño del cambio
                socket.emit('inventoryData', {
                    player: {
                        ...user.gameData.toObject(),
                        equipped: user.gameData.equipped,
                        spheres: user.gameData.spheres
                    }
                });
                
                // v214.192: BROADCAST CRÍTICO (Notificar a los aliados para que oculten la esfera)
                socket.broadcast.emit('playerStatSync', {
                    id: socket.id,
                    spheres: user.gameData.spheres
                });
                
                console.log(`[SPHERES] ${user.username} desequipó esfera ${sphereId}. Sincronía enviada.`);
            }
        } catch (e) { console.error("Error en unequipSphere:", e); }
    });

    socket.on('latencyUpdate', (ms) => {
        if (players[socket.id]) {
            players[socket.id].latency = ms;
        }
    });

    // v210.10: Cambiar Nave en el Hangar
    socket.on('switchShip', async (data) => {
        const p = players[socket.id];
        if (!p || !socket.dbUser) return;
        const shipId = parseInt(data.shipId);

        try {
            const user = await User.findById(socket.dbUser._id);
            if (user && user.gameData.ownedShips.includes(shipId)) {
                // v210.11: Bloqueo en Combate (Safe Switch)
                const now = Date.now();
                if (p.lastHit && now - p.lastHit < 10000) {
                    socket.emit('authError', 'ALERTA DE COMBATE: Espera 10s fuera de combate para cambiar de nave.');
                    return;
                }

                // v210.83: INTERCAMBIO DE EQUIPAMIENTO CON CLONADO (Aislamiento Total)
                // 1. Respaldar equipo de la nave vieja (Garantizar POJO)
                const oldShipId = user.gameData.currentShipId.toString();
                const newShipId = shipId.toString();

                if (!user.gameData.equippedByShip) user.gameData.equippedByShip = new Map();

                // Normalizar entrada antes de guardar
                let currentEquip = JSON.parse(JSON.stringify(user.gameData.equipped || { w: [], s: [], e: [], x: [] }));
                user.gameData.equippedByShip.set(oldShipId, currentEquip);

                // 2. Cargar equipo de la nave nueva (Soporte Map/Obj)
                let newEquip = null;
                const ebs = user.gameData.equippedByShip;
                if (typeof ebs.get === 'function') { newEquip = ebs.get(newShipId); }
                else { newEquip = ebs[newShipId]; }

                if (newEquip && (newEquip.w || newEquip.s || newEquip.e || newEquip.x)) {
                    user.gameData.equipped = JSON.parse(JSON.stringify(newEquip));
                } else {
                    user.gameData.equipped = { w: [], s: [], e: [], x: [] };
                }

                p.currentShipId = shipId;
                p.equipped = JSON.parse(JSON.stringify(user.gameData.equipped));
                user.gameData.currentShipId = shipId;

                // v210.200: Recalcular Stats de la Nave Nueva + Talentos
                const newShipData = SERVER_CONFIG.shipModels.find(s => s.id === shipId) || { hp: 2000, shield: 1000 };
                const hpBonus = 1.0 + ((p.skillTree?.engineering[0] || 0) * 0.02);
                const shBonus = 1.0 + ((p.skillTree?.engineering[1] || 0) * 0.02);

                p.maxHp = Math.ceil((newShipData.hp || 2000) * hpBonus);
                p.maxShield = Math.ceil((newShipData.shield || 1000) * shBonus);
                p.hp = p.maxHp; // Curación completa al cambiar de nave (Standard v6)
                p.shield = p.maxShield;

                user.markModified('gameData.equippedByShip');
                await user.save();
                socket.dbUser = user;

                // v210.91: Serialización POJO (Map -> Object) para Socket.io
                const eByShipObj = {};
                if (user.gameData.equippedByShip) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                }

                socket.emit('inventoryData', {
                    player: {
                        ...user.gameData.toObject(),
                        equipped: user.gameData.equipped,
                        equippedByShip: eByShipObj
                    }
                });

                // v210.201: BROADCAST SELECTIVO (Avisar a los aliados del cambio de nave/stats)
                socket.broadcast.emit('playerShipChanged', { id: socket.id, shipId: shipId });
                socket.broadcast.emit('playerStatSync', {
                    id: socket.id,
                    hp: p.hp,
                    shield: p.shield,
                    maxHp: p.maxHp,
                    maxShield: p.maxShield,
                    spheres: p.spheres,
                    isDead: false
                });

                console.log(`[HANGAR] Piloto ${p.user} cambió a Nave ${shipId}. Stats Sync: ${p.maxHp} HP / ${p.maxShield} SH`);
            }
        } catch (e) { console.error("Error selectShip:", e); }
    });

    socket.on('playerMovement', async (movementData) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];

        // v200.30: ANTI-SPEEDHACK (Validación de Distancia)
        if (!p.speed && SERVER_CONFIG) {
            const ship = SERVER_CONFIG.shipModels.find(s => s.id === p.currentShipId);
            p.speed = ship ? ship.speed : 500;
        }
        // v210.0: ANTI-SPEEDHACK (Ajuste de Precisión)
        const dx = movementData.x - p.x;
        const dy = movementData.y - p.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        if (distance >= 1100) { // Umbral realista para compensar lag y naves rápidas
            console.log(`[HACK] Teletransporte detectado en ${p.user}: ${distance}px`);
            return;
        }

        p.x = movementData.x;
        p.y = movementData.y;
        p.rotation = movementData.rotation;
        if (movementData.selectedAmmo) p.selectedAmmo = movementData.selectedAmmo;

        const oldZone = Number(p.zone || 1);
        const targetZone = Number(movementData.zone || 1);
        p.zone = targetZone;

        if (oldZone !== targetZone) {
            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${targetZone}`);
            socket.to(`zone_${targetZone}`).emit('newPlayer', { ...p, id: socket.id, spheres: p.spheres });
        }

        socket.to(`zone_${p.zone}`).emit('playerMoved', { ...p, id: socket.id, spheres: p.spheres });
    });

    socket.on('playerRespawn', (respawnData) => {
        if (!players[socket.id]) return;
        const p = players[socket.id];
        p.isDead = false;
        p.hp = respawnData.hp || p.maxHp || 1000;
        p.shield = respawnData.sh || p.maxShield || 500;
        p.x = respawnData.x || 2000;
        p.y = respawnData.y || 2000;
        // v186.27: Sincronía de Resurrección Global (Evita "Otra Dimensión")
        if (respawnData.zone) p.zone = Number(respawnData.zone);

        console.log(`DESCON: Piloto [${p.user}] ha reaparecido en Zona [${p.zone}]`);

        const respawnPayload = { ...p, id: socket.id, isDead: false };
        // Broadcast global para asegurar que todos los clientes lo vean/recreen
        io.emit('newPlayer', respawnPayload);
        io.emit('playerStatSync', {
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

    socket.on('enemyHit', async (data) => {
        const { enemyId, bulletId } = data;
        const enemy = enemies[enemyId];
        const p = players[socket.id];
        if (!enemy || !p || !SERVER_CONFIG || p.isDead) return;

        // v210.200: ANTI-FAR-HIT (Validación de Distancia de Disparo)
        const dist = Math.hypot(p.x - enemy.x, p.y - enemy.y);
        if (dist > 1500) {
            // console.log(`[HACK] Intento de daño remoto bloqueado: ${p.user} a ${enemyId} (${dist}px)`);
            return;
        }

        if (enemy.ai && enemy.ai.isInvulnerable) return;

        // v200.31: Daño Autoritativo Recalculado
        let baseDamage = 100;
        if (p.equipped && p.equipped.w) {
            baseDamage = 0;
            p.equipped.w.forEach(it => {
                const master = SERVER_CONFIG.shopItems.weapons.find(w => w.id === it.id);
                if (master) baseDamage += (master.base || 0);
            });
        }
        if (baseDamage <= 0) baseDamage = 100;

        // Bonificación de Habilidad: LÁSER SOBRECARGA (Com_1)
        const skillBonus = 1.0 + ((p.skillTree?.combat[0] || 0) * 0.03);

        const tier = (p.selectedAmmo && p.selectedAmmo.laser) ? p.selectedAmmo.laser : 0;
        const finalDamage = baseDamage * ((SERVER_CONFIG.ammoMultipliers["laser"] || [1])[tier] || 1) * skillBonus;

        if (enemy.shield >= finalDamage) {
            enemy.shield -= finalDamage;
        } else {
            enemy.hp -= (finalDamage - enemy.shield);
            enemy.shield = 0;
        }
        enemy.lastHit = Date.now();
        enemy.lastHitter = socket.id;

        if (enemy.hp <= 0) {
            // v210.201: PREVENCIÓN DE LOOT DUPLICADO / FRAUDE
            const cfg = SERVER_CONFIG.enemyModels[enemy.type] || {};
            const h_loot = cfg.rewardHubs || (enemy.type * 500);
            const o_loot = cfg.rewardOhcu || (enemy.type * 10);
            const e_loot = cfg.rewardExp || (enemy.type * 100);

            // Emitir muerte a la zona
            io.to(`zone_${enemy.zone}`).emit('enemyDead', { id: enemyId, hubs: h_loot, ohcu: o_loot, exp: e_loot, killer: socket.id, bulletId });

            // v210.201: REPARTO DE LOOT COOPERATIVO (PARTY SYSTEM)
            try {
                const killerUid = socket.dbUser._id.toString();
                const partyId = playerParty[killerUid];
                let membersToReward = [socket]; // Por defecto solo el asesino

                if (partyId && parties[partyId]) {
                    // Filtrar miembros de la party que estén online, en la misma zona y cerca (2000px)
                    membersToReward = parties[partyId].members
                        .map(uid => [...io.sockets.sockets.values()].find(s => s.dbUser && s.dbUser._id.toString() === uid))
                        .filter(s => {
                            if (!s || !players[s.id]) return false;
                            const pMem = players[s.id];
                            const distToEnemy = Math.hypot(pMem.x - enemy.x, pMem.y - enemy.y);
                            return pMem.zone === enemy.zone && distToEnemy <= 2000;
                        });
                    
                    // Asegurar que al menos el asesino sea incluido si por alguna razón el filtro falla
                    if (membersToReward.length === 0) membersToReward = [socket];
                }

                const shareCount = membersToReward.length;
                const shared_h = Math.floor(h_loot / shareCount);
                const shared_o = Math.floor(o_loot / shareCount);
                const shared_e = Math.floor(e_loot / shareCount);

                for (const memberSocket of membersToReward) {
                    const memP = players[memberSocket.id];
                    const user = await User.findById(memP.id);
                    if (user) {
                        user.gameData.hubs += shared_h;
                        user.gameData.ohcu += shared_o;
                        user.gameData.exp += shared_e;

                        // Chequeo de Level Up Autoritativo
                        const nextLevelExp = Math.floor(1000 * Math.pow(user.gameData.level, 1.5));
                        if (user.gameData.exp >= nextLevelExp) {
                            user.gameData.level++;
                            user.gameData.skillPoints++;
                            memberSocket.emit('gameNotification', { msg: `¡NIVEL ${user.gameData.level} ALCANZADO!`, type: 'success' });
                        }

                        user.markModified('gameData');
                        await user.save();

                        // Actualizar RAM
                        memP.hubs = user.gameData.hubs;
                        memP.ohcu = user.gameData.ohcu;
                        memP.exp = user.gameData.exp;
                        memP.level = user.gameData.level;
                        memP.skillPoints = user.gameData.skillPoints;

                        memberSocket.emit('inventoryData', { player: user.gameData });

                        // Feedback por chat si es party
                        if (shareCount > 1) {
                            memberSocket.emit('chatMessage', {
                                sender: 'SISTEMA',
                                msg: `Recibiste ${shared_e} EXP (Reparto de Grupo)`,
                                channel: 'team',
                                senderId: 'server'
                            });
                        }
                    }
                }
            } catch (e) { console.error("Error loot cooperativo:", e); }
            delete enemies[enemyId];
        } else {
            io.to(`zone_${enemy.zone}`).emit('enemyDamaged', { id: enemyId, hp: enemy.hp, shield: enemy.shield, bulletId });
        }
    });

    // SISTEMA DE DAÑO RECIBIDO SINCRONIZADO v125.31 (Identity Aware)
    socket.on('playerHitByEnemy', (data) => {
        const p = players[socket.id];
        if (p && !p.isDead && SERVER_CONFIG) {
            const enemyType = data.enemyType || 1;
            const attackerType = data.attackerType || 'enemy';
            let dmg = data.damage || 0;

            // v201.20: Validación de Atacante (Anti-Cheat vs Sincronía)
            if (attackerType === 'enemy') {
                const cfg = SERVER_CONFIG.enemyModels[enemyType];
                dmg = cfg ? cfg.bulletDamage : 50;
            } else if (attackerType === 'combat_ping') {
                dmg = 0; // Es solo para resetear el delay de regeneración
            }
            if (p.shield >= dmg) p.shield -= dmg;
            else { p.hp -= (dmg - p.shield); p.shield = 0; }
            if (p.hp <= 0) { p.hp = 0; p.isDead = true; }
            p.lastCombatTime = Date.now();
            p.regenDelay = (attackerType === 'remote') ? 15000 : 5000;
            io.to(`zone_${p.zone}`).emit('playerStatSync', { id: socket.id, hp: p.hp, shield: p.shield, maxHp: p.maxHp, maxShield: p.maxShield, isDead: p.isDead, spheres: p.spheres });
        }
    });



    // Removido de aquí - ahora se envía en 'login' para evitar Race Conditions

    socket.on('changeZone', (zoneId) => {
        if (!players[socket.id]) return;

        const oldZone = players[socket.id].zone || 1;
        const newSize = (zoneId === 1 ? 4000 : 2000);

        // Gestión de Habitaciones v75.0 (Optimization)
        socket.leave(`zone_${oldZone}`);
        socket.join(`zone_${zoneId}`);

        players[socket.id].zone = zoneId;
        players[socket.id].x = newSize / 2;
        players[socket.id].y = newSize / 2;

        console.log(`DESCON: Jugador [${socket.id}] cambió a Sector [${zoneId}]`);

        // Avisar a la vieja zona que se fue y a la nueva que llegó
        socket.to(`zone_${oldZone}`).emit('playerDisconnected', socket.id);
        socket.to(`zone_${zoneId}`).emit('newPlayer', { ...players[socket.id], spheres: players[socket.id].spheres });

        // Si entra a la zona 2 (Boss Titan), spawnearlo si no existe
        if (zoneId === 2) {
            const hasBoss = Object.values(enemies).some(e => e.zone === 2 && e.type === 4);
            if (!hasBoss) serverSpawnEnemy(2, 4); // Zone 2, Type 4 (Titan)
        }

        // Si entra a la zona 3 (Ancient Dungeon), spawnear Boss Tier 5
        if (zoneId === 3) {
            const hasBoss = Object.values(enemies).some(e => e.zone === 3 && e.type === 5);
            if (!hasBoss) serverSpawnEnemy(3, 5); // Zone 3, Type 5 (Ancient)
        }

        // ENVIAR ESTADO DE ENEMIGOS DE LA NUEVA ZONA v59.0 (v92.10 Fix: Evitar Ref. Circulares)
        const zoneEnemies = {};
        Object.keys(enemies).forEach(id => {
            if (enemies[id].zone === zoneId) {
                const { ai, ...cleanData } = enemies[id];
                zoneEnemies[id] = cleanData;
            }
        });
        socket.emit('currentEnemies', zoneEnemies);
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

                // v189.96: PERSISTENCIA INSTANTÁNEA (DB Atlas Write)
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

            if (!targetSocket) return socket.emit('authError', 'PILOTO NO ENCONTRADO O FUERA DE LÍNEA');
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
            if (parties[partyId].members.length >= 8) return socket.emit('authError', 'EL GRUPO ESTÁ LLENO (MAX 8)');

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

// v105.11: Exposición para IAs Modulares
global.serverSpawnEnemy = serverSpawnEnemy;

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

// v192.60: Helpers de Optimización de Proximidad
function _trigger_boss_explosion(e) {
    io.to(`zone_${e.zone}`).emit('bossEffect', { type: 'vacuum', x: e.x, y: e.y, radius: 500 });
    Object.values(players).forEach(p => {
        if (p.zone === e.zone && Math.hypot(p.x - e.x, p.y - e.y) < 500) {
            p.shield -= 3000; if (p.shield < 0) { p.hp += p.shield; p.shield = 0; }
            io.to(p.socketId).emit('playerStatSync', { hp: p.hp, shield: p.shield, isDead: p.hp <= 0 });
        }
    });
    io.to(`zone_${e.zone}`).emit('enemyDead', { id: e.id, killerId: 'server' });
    delete enemies[e.id];
}


// v210.250: BONO ÚNICO DE EMERGENCIA (200k OHCU para Caelli94)
async function _give_emergency_bonus() {
    try {
        const User = require('./models/User'); // Asegurar acceso al modelo
        const result = await User.findOneAndUpdate(
            { username: "caelli94" },
            { $inc: { "gameData.ohcu": 200000 } },
            { new: true }
        );
        if (result) {
            console.log(`\x1b[32m[BONUS] 200,000 OHCU acreditados a ${result.username} por única vez.\x1b[0m`);
            // Nota: Este script se ejecuta una vez al arrancar, pero $inc sumará cada vez que reinicies el servidor
            // Si quieres que sea REALMENTE una sola vez, deberías comentar esto después del primer reinicio.
        }
    } catch (e) { console.error("Error en bono:", e); }
}
// Ejecutar ahora para dar el bono
//_give_emergency_bonus(); 

http.listen(PORT, '0.0.0.0', () => {
    const ip = getLocalIP();
    console.log(`\x1b[36m+----------------------------------------------+`);
    console.log(`|  DESCON v6 - SERVIDOR MULTIPLAYER ACTIVO     |`);
    console.log(`|  IP: http://${ip}:${PORT}                    |`);
    console.log(`+----------------------------------------------+\x1b[0m\n`);
});
