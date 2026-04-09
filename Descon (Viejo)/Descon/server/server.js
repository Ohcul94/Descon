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
    const id = 'enemy_' + (zone === 2 || forceType === 4 ? 'titan_' : '') + Date.now() + Math.floor(Math.random()*1000);
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
for(let i=0; i<10; i++) serverSpawnEnemy();

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
    Object.values(enemies).forEach(e => {
        // Lógica de Criaturas Temporales / Clones v108.30
        if (e.type === 6) {
            e.cloneLife = (e.cloneLife || 15000) - 33;
            if (e.cloneLife <= 0 && !e.isDead) {
                e.isDead = true; 
                // Explosión de Área al expirar
                io.to(`zone_${e.zone}`).emit('bossEffect', { type: 'vacuum', x: e.x, y: e.y, radius: 500 });
                Object.values(players).forEach(p => {
                    if (p.zone === e.zone && Math.hypot(p.x - e.x, p.y - e.y) < 500) {
                        p.shield -= 3000; if (p.shield < 0) { p.hp += p.shield; p.shield = 0; }
                        io.to(p.socketId).emit('playerStatSync', { hp: p.hp, shield: p.shield });
                    }
                });
                io.to(`zone_${e.zone}`).emit('enemyDead', { id: e.id, killerId: 'server' });
                delete enemies[e.id];
                return;
            }
        }

        if (e.ai) {
            e.ai.update(players, now, io);
        }

        // Colisión Simple entre enemigos (Repulsión)
        Object.values(enemies).forEach(other => {
            if (e === other || e.zone !== other.zone) return;
            const d = Math.hypot(e.x - other.x, e.y - other.y);
            if (d < 45) { 
                const pushAngle = Math.atan2(e.y - other.y, e.x - other.x);
                e.x += Math.cos(pushAngle) * 1.2;
                e.y += Math.sin(pushAngle) * 1.2;
            }
        });
    });

    // v192.05: SISTEMA DE AUTOSAVE EN BATCH (Optimización Gemini)
    // Reducimos las escrituras a MongoDB Atlas para no agotar los IOPS
    setInterval(async () => {
        const playerList = Object.values(players);
        for (const p of playerList) {
            try {
                await User.updateOne(
                    { _id: p.id },
                    { $set: { 
                        "gameData.lastPos.x": Math.floor(p.x),
                        "gameData.lastPos.y": Math.floor(p.y),
                        "gameData.hp": Math.ceil(p.hp),
                        "gameData.shield": Math.ceil(p.shield),
                        "gameData.zone": p.zone
                    }}
                );
            } catch(e) {}
        }
        if (playerList.length > 0) console.log(`\x1b[34m[AUTOSAVE]\x1b[0m ${playerList.length} naves guardadas.`);
    }, 60000);
    
    if (Object.keys(enemies).length > 0) {
        // Reducir carga de red enviando solo lo necesario para renderizado v85.20
        const moveData = {};
        Object.values(enemies).forEach(e => {
            if (e.hp > 0) {
                moveData[e.id] = { 
                    id: e.id, x: e.x, y: e.y, rotation: e.rotation, 
                    hp: e.hp, shield: e.shield, zone: e.zone, type: e.type,
                    isRyze: e.isRyze || false, // Flag de Furia v91.30
                    isRamming: e.ai && e.ai.isRamming, // Flag de Embestida v91.30
                    isCountering: e.isCountering || false, // v103.30
                    isInvulnerable: e.isInvulnerable || false
                };
            }
        });
        io.emit('enemiesMoved', moveData);
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
            } catch(e) {}

            players[socket.id] = {
                id: dbId,
                socketId: socket.id,
                num: nextPlayerNum++,
                user: username,
                x: user.gameData.lastPos.x, 
                y: user.gameData.lastPos.y, 
                rotation: 0,
                hp: user.gameData.hp || baseHp, 
                maxHp: user.gameData.maxHp || baseHp, 
                shield: user.gameData.shield || baseSh, 
                maxShield: user.gameData.maxShield || baseSh,
                ammo: user.gameData.ammo || {}, 
                selectedAmmo: user.gameData.selectedAmmo || { laser: 0, missile: 0, mine: 0 },
                zone: user.gameData.zone || 1,
                hudConfig: user.gameData.hudConfig || {},
                hudPositions: user.gameData.hudPositions || {}
            };

            // Cargar Configuración Admin (v39.0 - Sincronizada con Login)
            let adminConfig = null;
            try { adminConfig = await fs.readJson(CONFIG_FILE); } catch(e) {}

            socket.emit('loginSuccess', { 
                id: dbId, // Identidad Galáctica v123.20
                socketId: socket.id,
                user: username, 
                gameData: user.gameData,
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
                        maxShield: p.maxShield || 1000
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
                io.emit('newPlayer', playerSpawnData); 
                console.log(`[NET] Broadcast global de ${username} enviado.`);
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
                socket.emit('inventoryData', { player: user.gameData });
                console.log(`[SYNC] Inventario enviado a ${user.username} (${user.gameData.inventory.length} ítems)`);
            }
        } catch (e) { console.error("Error en getInventory:", e); }
    });

    // GUARDAR PROGRESO (MongoDB)
        socket.on('saveProgress', async (gameData) => {
        if (!socket.dbUser || !gameData) return;
        try {
            // v164.81: Sincronía en Caliente (RAM Update)
            if (players[socket.id]) {
                const p = players[socket.id];
                p.hp = gameData.hp !== undefined ? gameData.hp : p.hp;
                p.shield = gameData.shield !== undefined ? gameData.shield : p.shield;
                p.maxHp = gameData.maxHp !== undefined ? gameData.maxHp : p.maxHp;
                p.maxShield = gameData.maxShield !== undefined ? gameData.maxShield : p.maxShield;
                p.selectedAmmo = gameData.selectedAmmo || p.selectedAmmo;
                p.level = gameData.level || p.level;
            }

            // v164.75: Persistencia de Capacidad Máxima (Sync Hangar/Talents)
            await User.updateOne(
                { _id: socket.dbUser._id },
                { 
                    $set: { 
                        "gameData.hp": gameData.hp,
                        "gameData.shield": gameData.shield,
                        "gameData.maxHp": gameData.maxHp,
                        "gameData.maxShield": gameData.maxShield,
                        "gameData.level": gameData.level,
                        "gameData.exp": gameData.exp,
                        "gameData.ammo": gameData.ammo,
                        "gameData.selectedAmmo": gameData.selectedAmmo
                    } 
                }
            );
        } catch (e) { console.error("Error guardando progreso:", e); }
    });

    // SISTEMA ADMIN: GUARDAR CONFIGURACIÓN GLOBAL
    socket.on('saveAdminConfig', async (config) => {
        try {
            await fs.writeJson(CONFIG_FILE, config, { spaces: 4 });
            SERVER_CONFIG = config; // Actualizar memoria v47.0
            io.emit('adminConfigUpdated', config); // Avisar a todos
            console.log(`\x1b[35m[ADMIN]\x1b[0m Configuración guardada en disco.`);
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
    socket.on('playerFire', (fireData) => {
        const p = players[socket.id];
        if (!p) return;

        // Deducción Instantánea en el Servidor v68.2 (Anti-F5 Abuso de Munición)
        const type = fireData.type || 'laser';
        const tier = fireData.tier || 0;
        if (p.ammo && p.ammo[type] && p.ammo[type][tier] !== undefined) {
            if (p.ammo[type][tier] > 0) {
                p.ammo[type][tier]--;
            }
        }

        // v164.94: Sincronización Godot (Ruteo exacto a NetworkManager.gd)
        socket.to(`zone_${p.zone}`).emit('playerFire', {
            id: socket.id,
            ...fireData
        });
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
			const totalPrice = category === 'ammo' ? Math.floor((amount/100.0) * pricePerUnit) : pricePerUnit;
			
			if (user.gameData[currency] < totalPrice) {
				return socket.emit('authError', `FONDOS INSUFICIENTES DE ${currency.toUpperCase()}`);
			}
 
			// Deducción de Fondos
			user.gameData[currency] -= totalPrice;
 
			// Entrega del Ítem (v164.3 Fix: Persistence delivery)
			if (category === 'ships') {
				const shipIdNum = parseInt(itemConfig.id);
				if (!user.gameData.ownedShips.includes(shipIdNum)) {
					user.gameData.ownedShips.push(shipIdNum);
				}
			} else if (category === 'ammo') {
				const typeKey = itemId.split('_')[1].substring(0, 1) === 'l' ? 'laser' : (itemId.split('_')[1].substring(0, 1) === 'm' ? 'missile' : 'mine');
				const tier = itemConfig.tier || 0;
				if (!user.gameData.ammo) user.gameData.ammo = { laser: [0,0,0,0,0,0], missile: [0,0,0,0,0,0], mine: [0,0,0,0,0,0] };
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
 
			await user.save();
			socket.dbUser = user;
			
			if (players[socket.id]) {
				players[socket.id].hubs = user.gameData.hubs;
				players[socket.id].ohcu = user.gameData.ohcu;
				players[socket.id].ammo = user.gameData.ammo;
			}

			// Notificar éxito y enviar inventario fresco (v164.7 Godot Sync Absolute)
			const responseData = {
				player: {
					hubs: user.gameData.hubs,
					ohcu: user.gameData.ohcu,
					inventory: user.gameData.inventory,
					items: user.gameData.inventory, 
					equipped: user.gameData.equipped,
					skillTree: user.gameData.skillTree,
					skillPoints: user.gameData.skillPoints,
					ownedShips: user.gameData.ownedShips,
					currentShipId: user.gameData.currentShipId
				}
			};
			socket.emit('inventoryData', responseData);
			// socket.emit('loginSuccess', { id: user._id.toString(), user: user.username, gameData: user.gameData }); // ELIMINADO v164.11: Evita el reset de posición al comprar
			
			console.log(`[SHOP] Compra exitosa: ${user.username} compró ${itemId}`);
		} catch (e) { 
			console.error("Error en buyItem:", e); 
			socket.emit('authError', 'ERROR EN LA COMPRA - REINTENTE');
		}
	});
 
	// SISTEMA DE DISTRIBUCIÓN DE TALENTOS v164.2
	socket.on('investSkill', async (data) => {
		if (!socket.dbUser) return;
		try {
			const { category, index } = data;
			const user = await User.findById(socket.dbUser._id);
			if (!user || user.gameData.skillPoints <= 0) return socket.emit('authError', 'SIN PUNTOS DE HABILIDAD');
 
			if (user.gameData.skillTree[category][index] < 5) {
				user.gameData.skillTree[category][index]++;
				user.gameData.skillPoints--;
				await user.save();
				socket.dbUser = user;
				socket.emit('inventoryData', { player: user.gameData });
			}
		} catch (e) { console.error("Error en investSkill:", e); }
	});

	// SISTEMA DE EQUIPAMIENTO v164.8 (Persistence Sync)
	socket.on('equipItem', async (data) => {
		if (!socket.dbUser) return;
		try {
			const { instanceId, category } = data; // category es w, s, e, x
			const user = await User.findById(socket.dbUser._id);
			if (!user) return;

			const itemIdx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
			if (itemIdx === -1) return socket.emit('authError', 'ÍTEM NO ENCONTRADO EN BODEGA');

			const item = user.gameData.inventory[itemIdx];
			const type = item.type; // w, s, e, x
			
			// Validar Slots de la nave actual
			const currentShip = SERVER_CONFIG.shipModels.find(m => m.id === user.gameData.currentShipId);
			const maxSlots = (currentShip && currentShip.slots) ? (currentShip.slots[type] || 0) : 0;
			
			if (!user.gameData.equipped[type]) user.gameData.equipped[type] = [];
			if (user.gameData.equipped[type].length >= maxSlots) {
				return socket.emit('authError', 'SLOTS DE EQUIPAMIENTO LLENOS');
			}

			// Mover de inventario a equipado
			user.gameData.equipped[type].push(item);
			user.gameData.inventory.splice(itemIdx, 1);
			
			user.markModified('gameData.equipped');
			user.markModified('gameData.inventory');
			await user.save();
			socket.dbUser = user;

			const responseData = { player: user.gameData };
			socket.emit('inventoryData', responseData);

			// v164.80: Actualizar RAM del server INMEDIATAMENTE tras equipar
			if (players[socket.id]) {
				players[socket.id].inventory = user.gameData.inventory;
				players[socket.id].equipped = user.gameData.equipped;
				// Los máximos se actualizarán vía saveProgress desde el cliente en el próximo tick
			}
		} catch (e) { console.error("Error en equipItem:", e); }
	});

	socket.on('unequipItem', async (data) => {
		if (!socket.dbUser) return;
		try {
			const { category, index } = data;
			const user = await User.findById(socket.dbUser._id);
			if (!user) return;

			if (!user.gameData.equipped[category] || !user.gameData.equipped[category][index]) return;

			const item = user.gameData.equipped[category][index];
			user.gameData.inventory.push(item);
			user.gameData.equipped[category].splice(index, 1);

			user.markModified('gameData.equipped');
			user.markModified('gameData.inventory');
			await user.save();
			socket.dbUser = user;

			const responseData = { player: user.gameData };
			socket.emit('inventoryData', responseData);
			
			// v164.12: Actualizar RAM del server para evitar desvios
			if (players[socket.id]) {
				players[socket.id].inventory = user.gameData.inventory;
				players[socket.id].equipped = user.gameData.equipped;
			}
		} catch (e) { console.error("Error en unequipItem:", e); }
	});
 
	socket.on('latencyUpdate', (ms) => {
        if (players[socket.id]) {
            players[socket.id].latency = ms;
        }
    });

    socket.on('playerMovement', async (movementData) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];
        
        players[socket.id].x = movementData.x;
        players[socket.id].y = movementData.y;
        players[socket.id].rotation = movementData.rotation;
        const oldZone = Number(players[socket.id].zone || 1);
        const targetZone = Number(movementData.zone || 1);
        players[socket.id].zone = targetZone;

        if (oldZone !== targetZone) {
            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${targetZone}`);
            // v186.17: No emitir playerDisconnected aquí para evitar el bug de "1 online"
            // La vieja zona simplemente dejará de recibir playerMoved
            socket.to(`zone_${targetZone}`).emit('newPlayer', { ...players[socket.id], id: socket.id });
            console.log(`DESCON: Socket [${p.user}] auto-ruteado a Sector [${targetZone}]`);
        }
        
        // Sincronizar selección de munición para deducción en server v68.3
        if (movementData.selectedAmmo) {
            players[socket.id].selectedAmmo = movementData.selectedAmmo;
        }

        socket.to(`zone_${players[socket.id].zone}`).emit('playerMoved', { ...players[socket.id], id: socket.id });

        socket.to(`zone_${players[socket.id].zone}`).emit('playerMoved', { ...players[socket.id], id: socket.id });
        
        // PERSISTENCIA DE MOVIMIENTO ELIMINADA (Optimización de Escalado)
        // El guardado ahora se maneja vía Batch cada 60s
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
            isDead: false
        });
    });

    socket.on('ping_custom', () => {
        socket.emit('pong_custom', {});
    });

    socket.on('enemyHit', async (data) => {
        const { enemyId, damage, bulletId } = data; // bulletId para sincronización visual v73.90
        const enemy = enemies[enemyId];
        const killerId = socket.id;
        if (enemy) {
            // Punto 7: Mecánicas Defensivas de Boss v102.10
            if (enemy.ai && enemy.ai.isInvulnerable) return; // Inmune
            if (enemy.ai && enemy.ai.isCountering) {
                // Reflejar daño al atacante
                const p = players[killerId];
                if (p) {
                    p.shield -= damage;
                    if (p.shield < 0) { p.hp += p.shield; p.shield = 0; }
                }
                return; 
            }

            if (enemy.shield >= damage) {
                enemy.shield -= damage;
            } else {
                enemy.hp -= (damage - enemy.shield);
                enemy.shield = 0;
            }
            enemy.lastHit = Date.now();
            
            if (enemy.hp <= 0) {
                // Obtener recompensas desde la config global con fallback robusto v48.0
                const cfgModel = (SERVER_CONFIG && SERVER_CONFIG.enemyModels) ? SERVER_CONFIG.enemyModels[enemy.type] : null;
                
                const hubs = (cfgModel && cfgModel.rewardHubs !== undefined) ? cfgModel.rewardHubs : (enemy.type * 500);
                const ohcu = (cfgModel && cfgModel.rewardOhcu !== undefined) ? cfgModel.rewardOhcu : (enemy.type * 10);
                const exp = (cfgModel && cfgModel.rewardExp !== undefined) ? cfgModel.rewardExp : (enemy.type * 100);

                const killerId = socket.id;
                const partyId = playerParty[killerId];
                
                if (partyId && parties[partyId]) {
                    const party = parties[partyId];
                    const num = party.members.length;
                    const sharedRewards = {
                        hubs: Math.floor(hubs / num),
                        ohcu: Math.floor(ohcu / num),
                        exp: Math.floor(exp / num),
                        isShared: true,
                        members: party.members
                    };
                    io.to(`zone_${enemy.zone}`).emit('enemyDead', { id: enemyId, ...sharedRewards, killer: killerId, bulletId }); // Sincronía Room v75.0
                } else {
                    io.to(`zone_${enemy.zone}`).emit('enemyDead', { id: enemyId, hubs, ohcu, exp, isShared: false, killer: killerId, bulletId });
                }
                
                // v164.15: ACREDITACIÓN DE RECOMPENSAS (Persistence Sync)
                if (players[killerId] && socket.dbUser) {
                    const p = players[killerId];
                    const killerDbId = p.id;
                    try {
                        await User.updateOne(
                            { _id: killerDbId },
                            { 
                                $inc: { 
                                    "gameData.hubs": hubs,
                                    "gameData.ohcu": ohcu,
                                    "gameData.exp": exp
                                } 
                            }
                        );
                        // Actualizar en memoria para que el cliente lo vea sin reloguear
                        p.hubs = (p.hubs || (socket.dbUser.gameData ? socket.dbUser.gameData.hubs : 0)) + hubs;
                        p.ohcu = (p.ohcu || (socket.dbUser.gameData ? socket.dbUser.gameData.ohcu : 0)) + ohcu;
                        p.exp = (p.exp || (socket.dbUser.gameData ? socket.dbUser.gameData.exp : 0)) + exp;
                        
                        // Notificar al cliente específico para actualización de HUD
                        io.to(killerId).emit('rewardReceived', { hubs, ohcu, exp });
                        console.log(`[LOOT] ${p.user} recibió: ${hubs} HUBS, ${ohcu} OHCU, ${exp} EXP`);
                    } catch (e) { console.error("Error acreditando loot:", e); }
                }

                if (enemy.type === 4) lastTitanDeath = Date.now(); 
                if (enemy.type === 5) lastAncientDeath = Date.now(); // Cronómetro Ancient 3s v98.50
                delete enemies[enemyId];
            } else {
                io.to(`zone_${enemy.zone}`).emit('enemyDamaged', { id: enemyId, hp: enemy.hp, shield: enemy.shield, bulletId }); // Sincronía Room v75.0
            }
        }
    });

    // SISTEMA DE DAÑO RECIBIDO SINCRONIZADO v125.31 (Identity Aware)
    socket.on('playerHitByEnemy', (data) => {
        const p = players[socket.id];
        if (p && !p.isDead) {
            const dmg = data.damage || 0;
            const attackerType = data.attackerType || 'enemy';

            if (p.shield >= dmg) p.shield -= dmg;
            else { p.hp -= (dmg - p.shield); p.shield = 0; }
            if (p.hp <= 0) { p.hp = 0; p.isDead = true; }
            
            // v164.86: Penalización de Regeneración Diferenciada
            p.lastCombatTime = Date.now();
            p.regenDelay = (attackerType === 'remote') ? 15000 : 5000;

            io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                id: p.socketId, 
                hp: p.hp, 
                shield: p.shield, 
                maxHp: p.maxHp,
                maxShield: p.maxShield,
                isDead: p.isDead 
            });
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
        socket.to(`zone_${zoneId}`).emit('newPlayer', players[socket.id]);

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
                                "gameData.hudConfig": p.hudConfig || {},
                                "gameData.hudPositions": p.hudPositions || {}
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

http.listen(PORT, '0.0.0.0', () => {
    const ip = getLocalIP();
    console.log(`\x1b[36m+----------------------------------------------+`);
    console.log(`|  DESCON v6 - SERVIDOR MULTIPLAYER ACTIVO     |`);
    console.log(`|  IP: http://${ip}:${PORT}                    |`);
    console.log(`+----------------------------------------------+\x1b[0m\n`);
});
