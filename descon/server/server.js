require('dotenv').config();
const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http);
const path = require('path');
const fs = require('fs-extra');
const mongoose = require('mongoose');

// Modelos y M├│dulos de Seguridad
const User = require('./models/User');
const bcrypt = require('bcrypt'); // Criptograf├¡a Pro v35.0

// Importaci├│n de Cerebros de IA (v85.20 Professional Architecture)
const ChaseAI = require('./behaviors/ChaseAI');
const OrbitAI = require('./behaviors/OrbitAI');
const BossAI = require('./behaviors/BossAI');
const AncientBossAI = require('./behaviors/AncientBossAI');
const MechanicBossAI = require('./behaviors/MechanicBossAI'); // Nuevo Jefe Dungeon

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

let players = {};
let activeSessions = new Map(); // username (lower) -> socket.id v33.0
let enemies = {};
let nextPlayerNum = 1;
let SERVER_CONFIG = null; // Memoria de configuraci├│n global v47.0
let parties = {}; // dbId -> { members: [dbIds], names: [strings] }
let playerParty = {}; // dbId -> leaderDbId

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
    SERVER_CONFIG = config;
    console.log('\x1b[35m[SERVER]\x1b[0m Configuraci├│n maestro cargada.');
}).catch(() => {
    console.log('\x1b[33m[SERVER]\x1b[0m Usando configuraci├│n por defecto (config.json no encontrado).');
});

// Funci├│n para spawnear enemigos en el servidor (v107.10: Posici├│n Din├ímica)
// Función para spawnear enemigos en el servidor (v107.10: Posición Dinámica)
function serverSpawnEnemy(zone = 1, forceType = null, posX = null, posY = null, forceName = null) {
    // v236.20: Permitir Zona 1, Zona 7 (Boss2) y Zona 8 (Testing Boss)
    if (zone != 1 && zone != 8 && zone != 7) {
        console.log(`[SPAWN] Bloqueado intento en Zona ${zone}`);
        return null;
    }


    if (!forceType && zone === 1 && Object.keys(enemies).filter(e => enemies[e].zone === 1).length >= 15) return;
    
    const id = 'enemy_' + (zone >= 2 ? 'boss_' : '') + Date.now() + Math.floor(Math.random() * 1000);
    const type = forceType || (Math.floor(Math.random() * 3) + 1);

    const cfg = (SERVER_CONFIG && SERVER_CONFIG.enemyModels) ? SERVER_CONFIG.enemyModels[type.toString()] : null;
    const name = forceName || (cfg ? cfg.name : (type === 4 ? "Boss1" : (type === 5 ? "Boss2" : (type === 6 ? "Boss3" : "Enemigo"))));

    
    
    const initialHp = cfg ? cfg.hp : (type === 6 ? 150000 : (type === 5 ? 200000 : (type === 4 ? 100000 : (type * 2000))));
    const initialShield = cfg ? cfg.shield : (type === 6 ? 75000 : (type === 5 ? 100000 : (type === 4 ? 50000 : (type * 1000))));

    // v236.21: Posicionamiento centralizado para Bosses en mapas fijos
    const finalX = posX || (zone === 8 ? 2000 : (Math.random() * 3400 + 300));
    const finalY = posY || (zone === 8 ? 2000 : (Math.random() * 3400 + 300));

    const e = {
        id, type, zone, name,
        x: finalX,
        y: finalY,
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

    const bulletDmg = cfg ? cfg.bulletDamage : (type * 100);
    const fireR = cfg ? cfg.fireRate : 2000;
    const movSpeed = (type === 1 ? 4.5 : 3.5);

    const aiConfig = cfg ? cfg : { bulletDamage: (type * 100), fireRate: 2000, speed: (type === 1 ? 4.5 : 3.5) };
    
    if (type === 6) e.ai = new MechanicBossAI(e, aiConfig); 
    else if (type === 5) e.ai = new AncientBossAI(e, aiConfig); 
    else if (type === 4) e.ai = new BossAI(e, aiConfig); 
    else if (type === 1) e.ai = new ChaseAI(e, aiConfig);
    else e.ai = new OrbitAI(e, aiConfig);

    enemies[id] = e;

    const { ai, ...spawnData } = e;
    io.to(`zone_${zone}`).emit('enemySpawn', spawnData);
}

// GUARDIANÍA DE SPAWN ZONA 1 (4x T1, 4x T2, 4x T3)
setInterval(() => {
    let t1Count = 0; let t2Count = 0; let t3Count = 0;
    Object.values(enemies).forEach(e => {
        if (e.zone === 1 && e.hp > 0) {
            if (e.type === 1) t1Count++;
            else if (e.type === 2) t2Count++;
            else if (e.type === 3) t3Count++;
        }
    });

    if (t1Count < 4) serverSpawnEnemy(1, 1);
    if (t2Count < 4) serverSpawnEnemy(1, 2);
    if (t3Count < 4) serverSpawnEnemy(1, 3);
}, 2000);

// GUARDIANÍA DE JEFES (Asegurar 1 BOSS siempre en su mapa)
let lastTitanDeath = 0;
let lastAncientDeath = 0;
setInterval(() => {
    // Guardián Titán (Zona 1 - MiniBoss)
    const hasTitanZ1 = Object.values(enemies).some(e => e.type === 4 && e.zone === 1);
    if (!hasTitanZ1 && Date.now() - lastTitanDeath > 10000) {
        serverSpawnEnemy(1, 4);
    }
    
    // v236.25: Guardián Boss1 en Mapa 8 (Dungeon de Pruebas)
    const boss8 = Object.values(enemies).find(e => e.type === 4 && e.zone === 8);
    if (!boss8) {
        serverSpawnEnemy(8, 4, 2000, 2000);
    } else {
        boss8.name = "Boss1"; // v238.60: Forzar nombre exacto
    }

    // v238.98: Guardián Boss2 en Mapa 7 (Garantizar 1 solo jefe real)
    const boss7s = Object.values(enemies).filter(e => e.type === 5 && e.zone === 7 && e.name === "Boss2");
    if (boss7s.length === 0) {
        serverSpawnEnemy(7, 5, 2000, 2000, "Boss2");
    } else if (boss7s.length > 1) {
        // Purga de duplicados (Dejar solo el primero)
        boss7s.slice(1).forEach(dup => {
            delete enemies[dup.id];
            io.to(`zone_7`).emit('removeEntity', { id: dup.id });
        });
    }


}, 3000);


// LOOP DE IA Y MOVIMIENTO GLOBAL (v85.20 Modular AI Engine)
setInterval(() => {
    const now = Date.now();
    const enemiesByZone = {};
    const zoneMoveData = {};

    // Clasificaci├│n Inicial O(n) - Un solo pase (Soporte infinito de zonas)
    for (const id in enemies) {
        const e = enemies[id];
        if (e.hp > 0) {
            if (!enemiesByZone[e.zone]) {
                enemiesByZone[e.zone] = [];
                zoneMoveData[e.zone] = {};
            }
            enemiesByZone[e.zone].push(e);
        }
    }

    // Proceso por Zona (Dungeons incluidas)
    for (const z in enemiesByZone) {
        const zoneList = enemiesByZone[z];
        const listLen = zoneList.length;

        for (let i = 0; i < listLen; i++) {
            const e = zoneList[i];

            // 1. Actualizar IA
            if (e.ai) e.ai.update(players, now, io);

            // 2. Repulsi├│n F├¡sica (Solo contra naves de su propia zona)
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
                name: e.name, // v238.30: Sincronía de identidad persistente
                isRage: e.isRage || false,
                isRamming: e.ai && e.ai.isRamming,
                isCountering: e.isCountering || false,
                isInvulnerable: e.isInvulnerable || false
            };
            


        }

        // Broadcast Segmentado
        if (Object.keys(zoneMoveData[z]).length > 0) {
            io.to(`zone_${z}`).emit('enemiesMoved', zoneMoveData[z]);
        }
    }

    // v164.68: BUCLE DE REGENERACI├ôN AUTORITATIVA (Jugadores 10% HP/SH)
    Object.values(players).forEach(p => {
            const delay = p.regenDelay || 5000;
            
            // v239.12: RECALCULADO DINÁMICO EN CADA TICK (Garantía de Sincronía Total)
            const hpBonus = 1.0 + ((p.skillTree?.engineering[0] || 0) * 0.02);
            const shBonus = 1.0 + ((p.skillTree?.engineering[1] || 0) * 0.02);
            p.maxHp = Math.ceil((p.baseHp || 2000) * hpBonus);
            p.maxShield = Math.ceil((p.baseShield || 1000) * shBonus);

            if (!p.isDead && (now - (p.lastCombatTime || 0)) > delay) {
                let changed = false;
                const regenAmountHp = p.maxHp * 0.01; 
                const regenAmountSh = p.maxShield * 0.02; 

            // Regenerar Escudo (Prioridad 1)
            if (p.shield < p.maxShield) {
                p.shield += (regenAmountSh / 30.0);
                if (p.shield > p.maxShield) p.shield = p.maxShield; 
                changed = true;
            }
            // Regenerar Integridad (Prioridad 2)
            if (p.hp < p.maxHp) {
                p.hp += (regenAmountHp / 30.0);
                if (p.hp > p.maxHp) p.hp = p.maxHp; 
                changed = true;
            }
            
            // v239.10: Limpieza de Desync (Si por algún bug HP > maxHp, corregir silenciosamente)
            if (p.hp > p.maxHp + 1) { 
                p.hp = p.maxHp; 
                changed = true; 
            }
            if (p.shield > p.maxShield + 1) {
                p.shield = p.maxShield;
                changed = true;
            }

            // v192.10: Sincron├¡a Diferencial (Optimizaci├│n de Ancho de Banda)
            if (changed && now - (p.lastRegenSync || 0) > 1000) {
                const diffHp = Math.abs(p.hp - (p.lastSyncHp || 0));
                const diffSh = Math.abs(p.shield - (p.lastSyncSh || 0));

                // Solo mandamos paquete si vari├│ m├ís del 1.5% (Evitar spam de red)
                if (diffHp > (p.maxHp * 0.015) || diffSh > (p.maxShield * 0.015)) {
                    p.lastRegenSync = now;
                    p.lastSyncHp = p.hp;
                    p.lastSyncSh = p.shield;
                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: p.socketId,
                        hp: Math.ceil(p.hp),
                        shield: Math.ceil(p.shield),
                        spheres: p.spheres, // v214.195: Sincron├¡a visual continua
                        isDead: false
                    });
                }
            }
        }
    });
}, 33);

io.on('connection', (socket) => {
    const clientIP = socket.handshake.address;
    console.log(`DESCON: Nueva conexi├│n [${socket.id}] desde IP [${clientIP}]`);
    socket.dbUser = null;

    // REGISTRO DE USUARIO (MongoDB)
    socket.on('register', async (data) => {
        try {
            const username = data.user;
            const existingUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });

            if (existingUser) {
                return socket.emit('authError', 'Ese usuario ya existe.');
            }

            // ENCRIPTACI├ôN DE CONTRASE├æA (v35.0)
            const hashedPassword = await bcrypt.hash(data.password, 10);

            const newUser = new User({
                username,
                password: hashedPassword
            });

            await newUser.save();
            socket.dbUser = newUser;
            socket.emit('authSuccess', { user: username, msg: '┬íIdentidad blindada y grabada en la Galaxia!' });
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
                return socket.emit('authError', 'Usuario o contrase├▒a incorrectos.');
            }

            // COMPARACI├ôN CRIPTOGR├üFICA (v35.0)
            const isMatch = await bcrypt.compare(data.password, user.password);
            if (!isMatch) {
                return socket.emit('authError', 'Credenciales inv├ílidas en la Galaxia.');
            }

            // SEGURIDAD ANTI-MULTILOGIN v33.0: Desconectar sesi├│n anterior (Case Insensitive)
            const lowName = username.toLowerCase();
            if (activeSessions.has(lowName)) {
                const oldSocketId = activeSessions.get(lowName);
                const oldSocket = io.sockets.sockets.get(oldSocketId);
                if (oldSocket) {
                    oldSocket.emit('authError', 'SESI├ôN CERRADA: Se ha detectado un nuevo ingreso con esta cuenta.');
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

            // v190.85: Sincron├¡a de Stats Base desde Admin Config (server-side start)
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

            // v214.120: Sincron├¡a Maestra al Login (Garantizar que 'equipped' global no est├® vac├¡o)
            const resolvedEquip = (function () {
                const ebs = user.gameData.equippedByShip;
                const sid = (user.gameData.currentShipId || 1).toString();
                let raw = { w: [], s: [], e: [], x: [] };
                if (ebs) {
                    if (typeof ebs.get === 'function') { raw = ebs.get(sid) || raw; }
                    else { raw = ebs[sid] || raw; }
                }
                // Si el de la nave est├í vac├¡o pero el global tiene algo, rescatar el global (Fail-safe)
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
                spheres: user.gameData.spheres,

                hudConfig: user.gameData.hudConfig || {},
                hudPositions: user.gameData.hudPositions || {},
                hubs: user.gameData.hubs || 0,
                ohcu: user.gameData.ohcu || 0,
                exp: user.gameData.exp || 0,
                currentShipId: user.gameData.currentShipId || 1,
                zone: user.gameData.zone || 1,
                pvpEnabled: !!user.gameData.pvpEnabled,
                lastPos: { x: user.gameData.lastPos?.x || 2000, y: user.gameData.lastPos?.y || 2000 },
                lastPvpCombatTime: 0
            };

            // v196.60: Recalcular Stats con Talentos al Login (Fix Relogueo)
            const p_ref = players[socket.id];
            const hpBonus = 1.0 + ((p_ref.skillTree.engineering[0] || 0) * 0.02);
            const shBonus = 1.0 + ((p_ref.skillTree.engineering[1] || 0) * 0.02);
            p_ref.maxHp = Math.ceil(baseHp * hpBonus);
            p_ref.maxShield = Math.ceil(baseSh * shBonus);

            // Cargar Configuraci├│n Admin (v39.0 - Sincronizada con Login)
            // v196.00: Sincron├¡a de Configuraci├│n Admin
            let adminConfig = null;
            try { adminConfig = await fs.readJson(CONFIG_FILE); } catch (e) { }


            // v210.120: Serializaci├│n POJO para que Godot entienda el Mapa de Flota (v210.122: Asegurar POJO)
            const eByShipObj = {};
            if (user.gameData.equippedByShip) {
                if (user.gameData.equippedByShip instanceof Map) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                } else {
                    Object.assign(eByShipObj, user.gameData.equippedByShip);
                }
            }

            socket.emit('loginSuccess', {
                id: dbId, // Identidad Gal├íctica v123.20
                socketId: socket.id,
                user: username,
                gameData: {
                    ...user.gameData.toObject(),
                    equippedByShip: eByShipObj,
                    equipped: user.gameData.equipped // Asegurar sincron├¡a de nave activa
                },
                adminConfig: adminConfig
            });

            // Unirse a la 'room' de su zona actual para optimizaci├│n v75.0
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

            // Sincron├¡a con delay m├¡nimo para asegurar que el cliente proces├│ el loginSuccess
            setTimeout(() => {
                socket.emit('currentPlayers', currentPlayersInZone);
                socket.emit('currentEnemies', cleanEnemiesInZone);

                // v214.110: BROADCAST SEGMENTADO (Avisar solo a los de mi zona)
                socket.broadcast.to(`zone_${userZone}`).emit('newPlayer', { ...playerSpawnData, spheres: p_ref.spheres });
                
                // v220.12: ACTUALIZACI├ôN GLOBAL DE ONLINE AL ENTRAR
                io.emit('onlineCount', Object.keys(players).length);
            }, 100);
            console.log(`Usuario logueado: ${username}`);

            // v135.30: Reconectar y NOTIFICAR a todos el regreso del aliado
            if (playerParty[dbId]) {
                const pid = playerParty[dbId];
                if (parties[pid]) {
                    // Notificar a todos que el grupo est├í completo de nuevo
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

    // v164.10: CONSULTA DE INVENTARIO (Sincron├¡a Godot F1)
    socket.on('getInventory', async () => {
        if (!socket.dbUser) return;
        try {
            const user = await User.findById(socket.dbUser._id);
            if (user) {
                socket.dbUser = user;
                // v210.121: Sincron├¡a de Mapa para Godot
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

            // v214.150: SINCRON├ìA AUTORITATIVA TOTAL
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

    // SISTEMA ADMIN: GUARDAR CONFIGURACI├ôN GLOBAL
    socket.on('saveAdminConfig', async (config) => {
        try {
            await fs.writeJson(CONFIG_FILE, config, { spaces: 4 });
            SERVER_CONFIG = config; 
            if (config.enemyModels && config.enemyModels["4"]) {
                console.log(`[ADMIN] Guardando RageTimer para Boss1: ${config.enemyModels["4"].rageTimer}s`);
            }
            console.log(`\x1b[35m[ADMIN]\x1b[0m Configuraci├│n guardada en disco por ${players[socket.id] ? players[socket.id].user : 'Admin'}.`);
            
            // v226.30: PURGA DE ENTIDADES PARA EVITAR FANTASMAS (Sincron├¡a Limpia)
            // Notificar a todos los clientes que limpien su zona
            io.emit('adminConfigUpdated', config);
            io.emit('changeZoneDone', 1); // Forzar limpieza visual en clientes (Zona dummy para disparar el signal)
            
            // Vaciar enemigos en RAM para que el respawn los recree con nuevos datos
            Object.keys(enemies).forEach(id => delete enemies[id]);
            console.log(`[ADMIN] Purgados ${Object.keys(enemies).length} enemigos antiguos para re-sincronizaci├│n.`);
            
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

    socket.on('ping_custom', () => {

        socket.emit('pong_custom');
    });

    // SISTEMA DE CHAT v60.0
    socket.on('chatMessage', (data) => {
        if (!players[socket.id]) return;
        const sender = players[socket.id].user;
        const msg = data.msg.substring(0, 50); // L├¡mite de 50 caracteres (v60.0)

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
            socket.emit('chatMessage', { ...responseData, msg: `${msg} (Sin compa├▒eros activos)` });
        }
    });

    // SISTEMA DE COMBATE MULTIPLAYER (v62.0)
    // v200.20: SISTEMA DE DA├æO AUTORITATIVO (Anti-Cheat Server-Side)
    socket.on('playerFire', (fireData) => {
        const p = players[socket.id];
        if (!p || !SERVER_CONFIG) return;

        // v200.35: VALIDACI├ôN DE CADENCIA (Anti-RapidFire Hack)
        const now = Date.now();
        const lastFire = p.lastFireTime || 0;
        const cooldownMs = 800; // 1s te├│rico - 200ms de tolerancia por lag
        if (now - lastFire < cooldownMs) {
            // console.log(`[HACK] Cadencia de tiro sospechosa en ${p.user}`);
            return; // Bloqueo de r├ífagas ilegales
        }
        p.lastFireTime = now;

        // 1. Validar Munici├│n (Si no tiene en el servidor, el disparo es inv├ílido)
        const ammoType = fireData.type || 'laser';
        const ammoTier = fireData.ammoType || 0;
        if (!p.ammo || !p.ammo[ammoType] || p.ammo[ammoType][ammoTier] <= 0) {
            return; // Bloqueo de disparo sin balas (Server level)
        }

        // Descontar munici├│n en el servidor
        p.ammo[ammoType][ammoTier] -= 1;

        // 2. Calcular Da├▒o Leg├¡timo (Ignorar lo que diga el cliente)
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

    // v200.12: SISTEMA DE HABILIDADES DE ESFERAS (Sincron├¡a Autoritaria)
    socket.on('playerSphereSkill', (data) => {
        const p = players[socket.id];
        if (!p || !p.spheres) return;

        const now = Date.now();
        const sphereIdx = data.id !== undefined ? data.id : -1;
        if (sphereIdx < 0 || sphereIdx >= 4) return;

        // v210.5: VALIDACIÓN DE COOLDOWN (Anti-Skill Spam)
        if (!p.sphereCooldowns) p.sphereCooldowns = [0, 0, 0, 0];
        const lastUsed = p.sphereCooldowns[sphereIdx];
        const skillCooldown = 4800; // 5s oficiales - 200ms de gracia por lag

        if (now - lastUsed < skillCooldown) {
            // console.log(`[SPHERES] Rechazando skill de ${p.user}: Cooldown pendiente.`);
            return;
        }

        // v200.45: VALIDACI├ôN DE PODER (Ignorar powerValue del cliente)
        let healAmt = 0;
        const sphere = p.spheres[sphereIdx];
        if (sphere && sphere.equipped) {
            // Si es un objeto serializado (login de-serialized) o dict
            healAmt = sphere.equipped.power_value || 0;
        }

        if (healAmt <= 0) return; // Hack detected or no skill equipped

        p.sphereCooldowns[sphereIdx] = now; // Registrar uso leg├¡timo

        let actual_heal = 0;

        if (data.skillName === "ESCUDO CELULAR") {
            const ms = p.maxShield || 2000;
            actual_heal = Math.min(healAmt, ms - (p.shield || 0));
            p.shield = Math.min((p.shield || 0) + healAmt, ms);
        } else if (data.skillName === "AUTO-REPARACIÓN") {
            const mh = p.maxHp || 3000;
            actual_heal = Math.min(healAmt, mh - (p.hp || 0));
            p.hp = Math.min((p.hp || 0) + healAmt, mh);
        } else if (data.skillName === "ATAQUE_ESFERA" || data.skillName === "REFLECT-Ω" || data.skillName === "REFLECT-O") {
            // v235.00: Lógica de Ataque (El cliente procesa visual, server autoriza valor)
            actual_heal = healAmt;
        } else {
            actual_heal = healAmt || data.powerValue || 0;
        }

        actual_heal = Math.max(0, actual_heal);

        // v200.12: Sincron├¡a Cr├¡tica - Forzar actualizaci├│n inmediata para evitar rollback
        p.lastSyncHp = p.hp;
        p.lastSyncSh = p.shield;

        io.to(`zone_${p.zone}`).emit('playerStatSync', {
            id: socket.id,
            hp: Math.ceil(p.hp),
            shield: Math.ceil(p.shield),
            spheres: p.spheres,
            isDead: false
        });

        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', {
            id: socket.id,
            skillName: data.skillName,
            powerValue: actual_heal
        });

        console.log(`[SPHERES] Piloto ${p.user} us├│ ${data.skillName}. Cooldown iniciado.`);
    });

    // ENVIAR CONFIG AL CONECTAR
    fs.readJson(CONFIG_FILE).then(config => {
        if (config) socket.emit('adminConfigLoaded', config);
    }).catch(e => { /* Config por defecto en cliente */ });

    // SISTEMA DE TIENDA Y ADQUISICI├ôN v164.2 (Sync Godot/Phaser)
    socket.on('buyItem', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        try {
            const { category, itemId, currency, amount } = data;
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            if (!user.gameData[currency] && user.gameData[currency] !== 0) return socket.emit('authError', 'MONEDA INVALIDA');

            // 1. LOCALIZAR ITEM CONFIG (v222.85: B├║squeda unificada y limpia)
            let itemConfig = null;
            if (category === 'ammo') {
                for (const type in SERVER_CONFIG.shopItems.ammo) {
                    const found = SERVER_CONFIG.shopItems.ammo[type].find(i => i.id === itemId);
                    if (found) { itemConfig = found; break; }
                }
            } else if (SERVER_CONFIG.shopItems[category]) {
                itemConfig = SERVER_CONFIG.shopItems[category].find(i => i.id === itemId);
            }

            if (!itemConfig) return socket.emit('authError', 'ITEM NO ENCONTRADO EN LA GALAXIA');

            // 2. CALCULO DE PRECIOS Y VALIDACI├ôN
            const pricePerUnit = itemConfig.prices[currency];
            const qty = parseInt(amount) || 1000;
            const totalPrice = category === 'ammo' ? Math.floor((qty / 100.0) * pricePerUnit) : pricePerUnit;

            if (user.gameData[currency] < totalPrice) {
                return socket.emit('authError', `FONDOS INSUFICIENTES DE ${currency.toUpperCase()}`);
            }

            // 3. PROCESAR TRANSACCI├ôN
            user.gameData[currency] -= totalPrice;

            if (category === 'ships') {
                const shipIdNum = parseInt(itemConfig.id);
                if (!user.gameData.ownedShips.includes(shipIdNum)) {
                    user.gameData.ownedShips.push(shipIdNum);
                }
            } else if (category === 'ammo') {
                const typeKey = itemId.split('_')[1].substring(0, 1) === 'l' ? 'laser' : (itemId.split('_')[1].substring(0, 1) === 'm' ? 'missile' : 'mine');
                const tier = itemConfig.tier || 0;
                if (!user.gameData.ammo) user.gameData.ammo = { laser: [0, 0, 0, 0, 0, 0], missile: [0, 0, 0, 0, 0, 0], mine: [0, 0, 0, 0, 0, 0] };
                user.gameData.ammo[typeKey][tier] = (user.gameData.ammo[typeKey][tier] || 0) + qty;
            } else {
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

            // 4. PERSISTENCIA Y SINCRONIZACI├ôN RAM
            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            if (players[socket.id]) {
                players[socket.id].hubs = user.gameData.hubs;
                players[socket.id].ohcu = user.gameData.ohcu;
                players[socket.id].ammo = user.gameData.ammo;
            }

            // 5. RESPUESTA AL CLIENTE
            socket.emit('inventoryData', { player: user.gameData });
            console.log(`[SHOP] ${user.username} compr├│ ${itemId} (${qty} unidades)`);

        } catch (e) {
            console.error("Error en buyItem:", e);
            socket.emit('authError', 'ERROR EN LA TRANSACCI├ôN');
        }
    });

    // SISTEMA DE DISTRIBUCI├ôN DE TALENTOS v164.2 (Clon commit 30671f + ANTI-HACK)
    socket.on('investSkill', async (data) => {
        if (!socket.dbUser) return;
        try {
            const { category, index } = data;
            if (index < 0 || index > 7) return;

            const user = await User.findById(socket.dbUser._id);
            if (!user || user.gameData.skillPoints <= 0) return socket.emit('gameNotification', { msg: 'SIN PUNTOS DE HABILIDAD', type: 'warn' });

            // v214.51: Validación robusta del límite de nivel (Safe Sum)
            let totalSpent = 0;
            const branches = ['engineering', 'combat', 'science'];
            if (user.gameData.skillTree) {
                branches.forEach(cat => {
                    const branch = user.gameData.skillTree[cat];
                    if (Array.isArray(branch)) {
                        branch.forEach(val => totalSpent += (val || 0));
                    }
                });
            }
            
            if (totalSpent >= user.gameData.level) {
                return socket.emit('gameNotification', { msg: 'LÍMITE DE TALENTOS ALCANZADO POR NIVEL', type: 'warn' });
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
            if (!user.gameData.ownedShips.includes(targetShipId)) return socket.emit('authError', 'NAVE NO POSE├ìDA');

            const itemIdx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
            if (itemIdx === -1) return socket.emit('authError', '├ìTEM NO ENCONTRADO EN BODEGA');

            const item = user.gameData.inventory[itemIdx];
            const type = item.type; // w, s, e, x

            // Validar Slots de la nave objetivo (v210.101)
            const currentShip = SERVER_CONFIG.shipModels.find(m => m.id === targetShipId);
            const maxSlots = (currentShip && currentShip.slots) ? (currentShip.slots[type] || 0) : 0;

            // Obtener el buffer de equipo de esa nave espec├¡fica
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

            // v210.102: Serializaci├│n POJO para enviar al cliente
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

            // v210.111: Obtener equipo de la nave espec├¡fica
            if (!user.gameData.equippedByShip) user.gameData.equippedByShip = new Map();
            let shipEquip = user.gameData.equippedByShip.get(shipKey);

            // Fallback si es la activa y no est├í en el mapa a├║n
            if (!shipEquip && targetShipId === user.gameData.currentShipId) {
                shipEquip = JSON.parse(JSON.stringify(user.gameData.equipped || { w: [], s: [], e: [], x: [] }));
            }

            if (!shipEquip || !shipEquip[category] || !shipEquip[category][index]) return;

            const item = shipEquip[category][index];
            user.gameData.inventory.push(item);
            shipEquip[category].splice(index, 1);

            // v210.71: Sincron├¡a Per-Ship (Guardar cambio en el caj├│n)
            user.gameData.equippedByShip.set(shipKey, JSON.parse(JSON.stringify(shipEquip)));

            // Si es la activa, actualizar tambi├®n el global legacy
            if (targetShipId === user.gameData.currentShipId) {
                user.gameData.equipped = JSON.parse(JSON.stringify(shipEquip));
                user.markModified('gameData.equipped');
            }

            user.markModified('gameData.equippedByShip');
            user.markModified('gameData.inventory');
            await user.save();
            socket.dbUser = user;

            // v210.112: Serializaci├│n POJO (Map -> Object)
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

    // v214.210: Equipar Habilidades en Esferas Orbitales
    socket.on('equipSphere', async (data) => {
        if (!socket.dbUser) return;
        const { sphereId, skill } = data; // sphereId: 0-3, skill: { skill_name, power_value }
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            if (!user.gameData.spheres || user.gameData.spheres.length < 4) {
                if (!user.gameData.spheres) user.gameData.spheres = [];
                while (user.gameData.spheres.length < 4) {
                    const idx = user.gameData.spheres.length + 1;
                    user.gameData.spheres.push({ "name": `Slot ${idx}`, "type": "any", "color": "#ffffff", "equipped": null });
                }
                user.markModified('gameData.spheres');
                await user.save();
            }



            if (sphereId >= 0 && sphereId < user.gameData.spheres.length) {
                user.gameData.spheres[sphereId].equipped = skill;
                user.markModified('gameData.spheres');
                await user.save();
                socket.dbUser = user;

                // v236.10: Actualizar RAM con copia plana para evitar desync de referencias
                if (players[socket.id]) {
                    players[socket.id].spheres = JSON.parse(JSON.stringify(user.gameData.spheres));
                }

                // Sincronizar con el cliente de forma explícita
                socket.emit('inventoryData', {
                    player: {
                        ...user.gameData.toObject(),
                        equipped: user.gameData.equipped,
                        spheres: JSON.parse(JSON.stringify(user.gameData.spheres))
                    }
                });

                console.log(`[SPHERES] ${user.username} guardó ${skill.skill_name} en DB y RAM.`);
            }

        } catch (e) { console.error("Error en equipSphere:", e); }
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

                // Notificar al due├▒o del cambio
                socket.emit('inventoryData', {
                    player: {
                        ...user.gameData.toObject(),
                        equipped: user.gameData.equipped,
                        spheres: user.gameData.spheres
                    }
                });

                // v214.192: BROADCAST SEGMENTADO (Notificar solo a los aliados de zona)
                socket.to(`zone_${user.gameData.zone || 1}`).emit('playerStatSync', {
                    id: socket.id,
                    spheres: user.gameData.spheres
                });

                console.log(`[SPHERES] ${user.username} desequip├│ esfera ${sphereId}. Sincron├¡a enviada.`);
            }
        } catch (e) { console.error("Error en unequipSphere:", e); }
    });

    // v235.35: Sincronizaci├│n de Habilidades Activas (Visuales para Aliados)
    socket.on('playerSphereSkill', (data) => {
        const p = players[socket.id];
        if (p) {
            // Broadcast a la zona para que otros clientes activen los visuales
            socket.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', {
                id: socket.id,
                skillName: data.skillName,
                powerValue: data.powerValue
            });
            console.log(`[SKILL-SYNC] ${p.user} activ├│ ${data.skillName} - Retransmitiendo a zona ${p.zone}`);
        }
    });

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
                p.hp = p.maxHp; // Curaci├│n completa al cambiar de nave (Standard v6)
                p.shield = p.maxShield;

                user.markModified('gameData.equippedByShip');
                await user.save();
                socket.dbUser = user;

                // v210.91: Serializaci├│n POJO (Map -> Object) para Socket.io
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

                // v210.201: BROADCAST SEGMENTADO (Solo zona local)
                const zoneRoom = `zone_${p.zone}`;
                socket.to(zoneRoom).emit('playerShipChanged', { id: socket.id, shipId: shipId });
                socket.to(zoneRoom).emit('playerStatSync', {
                    id: socket.id,
                    hp: p.hp,
                    shield: p.shield,
                    maxHp: p.maxHp,
                    maxShield: p.maxShield,
                    spheres: p.spheres,
                    zone: p.zone,
                    isDead: false
                });

                console.log(`[HANGAR] Piloto ${p.user} cambi├│ a Nave ${shipId}. Stats Sync: ${p.maxHp} HP / ${p.maxShield} SH`);
            }
        } catch (e) { console.error("Error selectShip:", e); }
    });

    socket.on('playerMovement', async (movementData) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];

        // v200.30: ANTI-SPEEDHACK (Validaci├│n de Distancia)
        if (!p.speed && SERVER_CONFIG) {
            const ship = SERVER_CONFIG.shipModels.find(s => s.id === p.currentShipId);
            p.speed = ship ? ship.speed : 500;
        }
        // v210.0: ANTI-SPEEDHACK (Ajuste de Precisi├│n)
        const dx = movementData.x - p.x;
        const dy = movementData.y - p.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        if (distance >= 1100) { // Umbral realista para compensar lag y naves r├ípidas
            console.log(`[HACK] Teletransporte detectado en ${p.user}: ${distance}px`);
            return;
        }

        p.x = movementData.x;
        p.y = movementData.y;
        p.lastPos = { x: p.x, y: p.y }; // v221.60: Sincron├¡a constante de posici├│n
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

    socket.on('enemyHit', async (data) => {
        const { enemyId, bulletId, damage } = data; // v222.10: Recibir da├▒o real del cliente
        const enemy = enemies[enemyId];
        const p = players[socket.id];
        if (!enemy || !p || !SERVER_CONFIG || p.isDead) return;

        // v210.200: ANTI-FAR-HIT
        const dist = Math.hypot(p.x - enemy.x, p.y - enemy.y);
        if (dist > 1800) return;

        if (enemy.ai && enemy.ai.isInvulnerable) return;

        // v222.11: VALIDACI├ôN DE DA├æO (Confiar pero verificar)
        let finalDamage = parseFloat(damage) || 100;
        
        // Anti-Cheat b├ísico: Recalcular m├íximo posible para este jugador
        let maxAllowed = 200; 
        if (p.equipped && p.equipped.w) {
            let weaponsBase = 0;
            p.equipped.w.forEach(it => {
                const master = SERVER_CONFIG.shopItems.weapons.find(w => w.id === it.id);
                if (master) weaponsBase += (master.base || 0);
            });
            if (weaponsBase > 0) {
                // Multiplicador m├íximo: Munici├│n T6 (15x) + Talento Full (1.3x aprox)
                maxAllowed = weaponsBase * 20; 
            }
        }
        
        // Si el da├▒o del cliente es sospechoso, caparlo al m├íximo permitido
        if (finalDamage > maxAllowed) {
            console.log(`[SECURITY] Da├▒o sospechoso de ${p.user}: ${finalDamage} (Max: ${maxAllowed})`);
            finalDamage = maxAllowed;
        }

        if (enemy.shield >= finalDamage) {
            enemy.shield -= finalDamage;
        } else {
            enemy.hp -= (finalDamage - enemy.shield);
            enemy.shield = 0;
        }
        enemy.lastHit = Date.now();
        enemy.lastHitter = socket.id;

        // v226.10: SIEMPRE enviar se├▒al de da├▒o antes de evaluar muerte para que el cliente vea el pop-up
        io.to(`zone_${enemy.zone}`).emit('enemyDamaged', { id: enemyId, hp: Math.max(0, enemy.hp), shield: enemy.shield, bulletId });

        if (enemy.hp <= 0 && !enemy.isDying) {
            enemy.isDying = true; // v228.60: BLOQUEO DE CONCURRENCIA (Evita doble loot por balas r├ípidas)
            
            // v210.201: PREVENCI├ôN DE LOOT DUPLICADO / FRAUDE
            const cfg = SERVER_CONFIG.enemyModels[enemy.type] || {};
            let h_loot = cfg.rewardHubs || (enemy.type * 500);
            let o_loot = cfg.rewardOhcu || (enemy.type * 10);
            let e_loot = cfg.rewardExp || (enemy.type * 100);

            // v239.08: Los clones NO dan recompensa (Mecánica de Boss pura)
            if (enemy.name && enemy.name.toUpperCase().includes("CLONE")) {
                h_loot = 0; o_loot = 0; e_loot = 0;
            }

            // Emitir muerte a la zona (Solo visual, SIN valores de loot para evitar confusi├│n en el HUD)
            io.to(`zone_${enemy.zone}`).emit('enemyDead', { id: enemyId, killer: socket.id, bulletId, finalDamage: finalDamage });

            // v229.25: REPARTO DE LOOT COOPERATIVO (STRICT PARTY FINAL-FIX)
            try {
                const killerUid = socket.dbUser?._id.toString();
                if (!killerUid) return;

                let membersToReward = [socket]; 
                const partyId = playerParty[killerUid];

                if (partyId && parties[partyId]) {
                    const onlinePartyMembers = [];
                    // v229.26: Verificaci├│n de Integridad de la Flota (dbId Based)
                    for (const mUid of parties[partyId].members) {
                        const mUidStr = mUid.toString();
                        if (mUidStr === killerUid) continue; 
                        
                        // v229.27: B├║squeda de socket por UID en el mapa de sesiones activa
                        let sid = activeSessions.get(mUidStr);
                        
                        // FALLBACK: Si no est├í por UID, buscar por username (Falla de legado v130)
                        if (!sid) {
                            const foundSocket = Array.from(io.sockets.sockets.values()).find(s => s.dbUser && s.dbUser._id.toString() === mUidStr);
                            if (foundSocket) sid = foundSocket.id;
                        }

                        if (sid) {
                            const s = io.sockets.sockets.get(sid);
                            if (s && players[s.id]) {
                                const pM = players[s.id];
                                const distToE = Math.hypot(pM.x - enemy.x, pM.y - enemy.y);
                                
                                // Misma zona y proximidad (2500px)
                                if (pM.zone === enemy.zone && distToE <= 2500) {
                                    onlinePartyMembers.push(s);
                                }
                            }
                        }
                    }
                    membersToReward = membersToReward.concat(onlinePartyMembers);
                }

                // C├üLCULO DE DIVISI├ôN REAL
                const shareCount = membersToReward.length;
                const shared_h = Math.floor(h_loot / shareCount);
                const shared_o = Math.floor(o_loot / shareCount);
                const shared_e = Math.floor(e_loot / shareCount);

                // LOG DE VERIFICACI├ôN
                console.log(`[LOOT-FIX] Killer: ${socket.dbUser.username} | Repartiendo entre ${shareCount} miembros. Share individual: ${shared_e} EXP`);

                // v228.91: PROCESAMIENTO SINCRONIZADO DE RECOMPENSAS (REPLICA TOTAL)
                for (const memberSocket of membersToReward) {
                    if (!memberSocket || !memberSocket.dbUser) continue;
                    
                    const memP = players[memberSocket.id];
                    const user = await User.findById(memberSocket.dbUser._id.toString());
                    
                    if (user && memP) {
                        user.gameData.hubs += shared_h;
                        user.gameData.ohcu += shared_o;
                        user.gameData.exp += shared_e;

                        // Notificar el Share REAL al cliente. Este valor es el que el HUD usa para el cartel.
                        memberSocket.emit('enemyKillSession', { 
                            hubs: shared_h, 
                            ohcu: shared_o, 
                            exp: shared_e,
                            killer: socket.id 
                        });

                        // Chequeo de Level Up Autoritativo
                        let nextLevelExp = Math.floor(1000 * Math.pow(user.gameData.level, 1.5));
                        while (user.gameData.exp >= nextLevelExp && user.gameData.level < 100) {
                            user.gameData.exp -= nextLevelExp;
                            user.gameData.level++;
                            user.gameData.skillPoints++;
                            memberSocket.emit('gameNotification', { msg: `NIVEL ${user.gameData.level} ALCANZADO!`, type: 'success' });
                            nextLevelExp = Math.floor(1000 * Math.pow(user.gameData.level, 1.5));
                        }

                        user.markModified('gameData');
                        await user.save();

                        // Sincronizar RAM (Importante para que el pr├│ximo kill parta de valores correctos)
                        memP.hubs = user.gameData.hubs;
                        memP.ohcu = user.gameData.ohcu;
                        memP.exp = user.gameData.exp;
                        memP.level = user.gameData.level;
                        memP.skillPoints = user.gameData.skillPoints;

                        // v239.10: Forzar recalcular hp/shield máximo al subir de nivel
                        const hpBonus = 1.0 + ((memP.skillTree.engineering[0] || 0) * 0.02);
                        const shBonus = 1.0 + ((memP.skillTree.engineering[1] || 0) * 0.02);
                        memP.maxHp = Math.ceil((memP.baseHp || 2000) * hpBonus);
                        memP.maxShield = Math.ceil((memP.baseShield || 1000) * shBonus);

                        memberSocket.emit('inventoryData', { player: user.gameData });
                        console.log(`[LOOT-FIX] Recompensa entregada a: ${user.username} (+${shared_e} EXP)`);
                    }
                }
            } catch (e) { console.error("Error loot cooperativo:", e); }
            delete enemies[enemyId];
        }
    });

    // SISTEMA DE DA├æO RECIBIDO SINCRONIZADO v125.31 (Identity Aware)
    socket.on('playerHitByEnemy', (data) => {
        const p = players[socket.id];
        if (p && !p.isDead && SERVER_CONFIG) {
            const attackerType = data.attackerType || 'enemy';
            
            // v221.25: BLOQUEO RADICAL DE DA├æO NO-AUTORIZADO
            // Si el atacante es un jugador (remote), NO usamos este evento.
            if (attackerType === 'remote' || attackerType === 'player') {
                return; // Ignorar. El da├▒o entre jugadores SOLO por playerHitByPlayer
            }
            
            const enemyType = data.enemyType || 1;
            let dmg = data.damage || 0;

            // v239.11: Validación con Respeto a Nerfs
            if (attackerType === 'enemy') {
                const cfg = SERVER_CONFIG.enemyModels[enemyType];
                const baseDmg = cfg ? cfg.bulletDamage : 50;
                if (dmg <= 0 || dmg > baseDmg) dmg = baseDmg;
            } else if (attackerType === 'combat_ping') {
                dmg = 0;
            }
            if (p.shield >= dmg) p.shield -= dmg;
            else { p.hp -= (dmg - p.shield); p.shield = 0; }
            if (p.hp <= 0) { p.hp = 0; p.isDead = true; }
            p.lastCombatTime = Date.now();
            p.regenDelay = (attackerType === 'remote') ? 15000 : 5000;
            const syncData = { 
                id: socket.id, 
                hp: Math.ceil(p.hp), 
                shield: Math.ceil(p.shield), 
                maxHp: p.maxHp, 
                maxShield: p.maxShield, 
                isDead: p.isDead,
                spheres: p.spheres || [] // v239.12: Garantizar flujo de esferas
            };
            io.to(`zone_${p.zone}`).emit('playerStatSync', syncData);
        }
    });

    // v220.82: REGLA DE ORO PVP - Ambos deben tenerlo activo
    socket.on('playerHitByPlayer', (data) => {
        const victim = players[data.victimId];
        const attacker = players[socket.id];
        
        if (victim && attacker && !victim.isDead && !attacker.isDead) {
            // v221.30: Consentimiento Mutuo + Notificaci├│n
            if (victim.pvpEnabled && attacker.pvpEnabled) {
                const now = Date.now();
                let dmg = data.damage || 50;
                
                // L├│gica de mitigaci├│n (Escudo primero)
                if (victim.shield >= dmg) {
                    victim.shield -= dmg;
                } else {
                    victim.hp -= (dmg - victim.shield);
                    victim.shield = 0;
                }
                
                if (victim.hp <= 0) {
                    victim.hp = 0;
                    victim.isDead = true;
                }
                
                victim.lastCombatTime = now;
                attacker.lastCombatTime = now;
                victim.lastPvpCombatTime = now; // v222.41: Exclusivo PvP
                attacker.lastPvpCombatTime = now; // v222.41: Exclusivo PvP
                
                victim.regenDelay = 15000;
                
                // Sincronizar stats de la v├¡ctima con TODOS en su zona
                io.to(`zone_${victim.zone}`).emit('playerStatSync', { 
                    id: data.victimId, 
                    hp: victim.hp, 
                    shield: victim.shield, 
                    maxHp: victim.maxHp, 
                    maxShield: victim.maxShield, 
                    isDead: victim.isDead,
                    spheres: victim.spheres
                });
                
                console.log(`[PVP] ${attacker.user} da├▒├│ a ${victim.user}: ${dmg} DMG`);
            } else {
                // Notificar al atacante por qu├® no hay da├▒o
                if (!attacker.pvpEnabled) {
                    socket.emit('gameNotification', { msg: "PVP BLOQUEADO: Tu modo combate est├í SEGURO", type: "warning" });
                } else if (!victim.pvpEnabled) {
                    socket.emit('gameNotification', { msg: "PVP BLOQUEADO: El objetivo est├í en modo SEGURO", type: "warning" });
                }
            }
        }
    });

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

// v105.11: Exposici├│n para IAs Modulares
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

// v192.60: Helpers de Optimizaci├│n de Proximidad
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


// v210.250: BONO ├ÜNICO DE EMERGENCIA (200k OHCU para Caelli94)
async function _give_emergency_bonus() {
    try {
        const User = require('./models/User'); // Asegurar acceso al modelo
        const result = await User.findOneAndUpdate(
            { username: "Player3" },
            { $inc: { "gameData.ohcu": 200000 } },
            { new: true }
        );
        if (result) {
            console.log(`\x1b[32m[BONUS] 200,000 OHCU acreditados a ${result.username} por ├║nica vez.\x1b[0m`);
            // Nota: Este script se ejecuta una vez al arrancar, pero $inc sumar├í cada vez que reinicies el servidor
            // Si quieres que sea REALMENTE una sola vez, deber├¡as comentar esto despu├®s del primer reinicio.
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
