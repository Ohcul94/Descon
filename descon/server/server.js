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

// Importaci├│n de Cerebros de IA (v85.20 Professional Architecture)
const ChaseAI = require('./behaviors/ChaseAI');
const OrbitAI = require('./behaviors/OrbitAI');
const BossAI = require('./behaviors/BossAI');
const AncientBossAI = require('./behaviors/AncientBossAI');
const MechanicBossAI = require('./behaviors/MechanicBossAI'); // Nuevo Jefe Dungeon
const HordeManager = require('./events/HordeManager'); // v245.01: Gestor de Eventos
const SniperAI = require('./behaviors/SniperAI'); // v248.01: Tipo 2
const ChargerAI = require('./behaviors/ChargerAI'); // v248.01: Tipo 3
const GravityAI = require('./behaviors/GravityAI'); // v251.01: Tipo 7 (Elite CC)

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
let activeAreas = {}; // v260.50: Zonas de efecto persistentes (Humo, Minas, etc)
let nextAreaId = 1;
let nextPlayerNum = 1;
let SERVER_CONFIG = null; // Memoria de configuraci├│n global v47.0
let parties = {}; // dbId -> { members: [dbIds], names: [strings] }
let playerParty = {}; // dbId -> leaderDbId
const hordeManager = new HordeManager(io, serverSpawnEnemy, enemies); // v245.02: Instancia global

// v243.15: Helper para serializar datos de clan con roles y estados
async function getClanDataPayload(clanId) {
    try {
        const clan = await Clan.findById(clanId)
            .populate('members', 'username gameData.level gameData.clanRole')
            .populate('requests', 'username gameData.level')
            .populate('sentInvites', 'username gameData.level');
        if (!clan) return null;

        const membersWithStatus = clan.members.map(m => {
            const isOnline = Array.from(activeSessions.keys()).includes(m.username.toLowerCase());
            
            // v243.30: Identificación robusta del Líder (Prioridad ID sobre campo opcional clanRole)
            let role = m.gameData?.clanRole || 'member';
            if (clan.leader && m._id.toString() === clan.leader.toString()) {
                role = 'leader';
            }
            
            return {
                id: m._id,
                username: m.username,
                level: m.gameData?.level || 1,
                role: role,
                online: isOnline
            };
        });

        const requestsData = (clan.requests || []).map(r => ({
            id: r._id,
            username: r.username,
            level: r.gameData?.level || 1
        }));

        const sentInvitesData = (clan.sentInvites || []).map(i => ({
            id: i._id,
            username: i.username,
            level: i.gameData?.level || 1
        }));

        // v244.112: Ordenar: Online Primero > Rol (Líder > Oficial > Miembro)
        membersWithStatus.sort((a, b) => {
            if (a.online !== b.online) return a.online ? -1 : 1; // Online arriba
            const weights = { 'leader': 0, 'officer': 1, 'member': 2 };
            return weights[a.role] - weights[b.role];
        });

        return {
            id: clan._id,
            name: clan.name,
            tag: clan.tag,
            leader: clan.leader,
            members: membersWithStatus,
            requests: requestsData,
            sentInvites: sentInvitesData, // v244.99: Seguimiento de invitaciones enviadas
            joinType: clan.joinType || 'open',
            maxMembers: clan.maxMembers || 20
        };
    } catch (e) {
        console.error("Error obteniendo datos de clan:", e);
        return null;
    }
}

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
        num: nextPlayerNum++,
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
        getClanDataPayload(user.gameData.clanId).then(clanData => {
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
    SERVER_CONFIG = config;
    console.log('\x1b[35m[SERVER]\x1b[0m Configuraci├│n maestro cargada.');
    if (SERVER_CONFIG && SERVER_CONFIG.hordeConfig) hordeManager.updateConfig(SERVER_CONFIG.hordeConfig);
}).catch(() => {
    console.log('\x1b[33m[SERVER]\x1b[0m Usando configuraci├│n por defecto (config.json no encontrado).');
});

// Funci├│n para spawnear enemigos en el servidor (v107.10: Posici├│n Din├ímica)
// Función para spawnear enemigos en el servidor (v107.10: Posición Dinámica)
function serverSpawnEnemy(zone = 1, forceType = null, posX = null, posY = null, forceName = null, isHorde = false) {
    // v245.05: Permitir spawn en cualquier zona si el evento de hordas está activo en esa zona
    const isHordeZone = hordeManager && hordeManager.config.active && hordeManager.config.map === zone;
    
    if (zone != 1 && zone != 8 && zone != 7 && !isHordeZone) {
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
        isHorde, // v247.01: Identificador para IA agresiva
        x: finalX,
        y: finalY,
        hp: initialHp,
        maxHp: initialHp,
        shield: initialShield,
        maxShield: initialShield,
        rotation: 0,
        lastHit: 0,
        lastDash: 0,
        isHorde: (zone === 6), // v253.10: Visión global si estamos en mapa de hordas
        shotsInBurst: 0,
        nextShotTime: 0
    };

    const bulletDmg = cfg ? cfg.bulletDamage : (type * 100);
    const fireR = cfg ? cfg.fireRate : 2000;
    const movSpeed = cfg ? (cfg.speed * 0.033) : (type === 1 ? 4.5 : 3.5);

    // v250.01: IMPORTANTE - Clonar el config y sobreescribir la velocidad con la procesada
    const aiConfig = cfg ? { ...cfg, speed: movSpeed } : { bulletDamage: (type * 100), fireRate: 2000, speed: movSpeed, bulletSpeed: 800 };
    
    if (type === 11) e.ai = new MechanicBossAI(e, aiConfig); 
    else if (type === 10) e.ai = new AncientBossAI(e, aiConfig); 
    else if (type === 4) e.ai = new BossAI(e, aiConfig); 
    else if (type === 8 || type === 3) e.ai = new ChargerAI(e, aiConfig); // v252.12: Tipos 3 y 8
    else if (type === 6 || type === 7) e.ai = new GravityAI(e, aiConfig); // v252.12: Tipos 6 y 7
    else if (type === 5 || type === 2) e.ai = new SniperAI(e, aiConfig);  // v252.12: Tipos 2 y 5
    else if (type === 1 || type === 9) e.ai = new ChaseAI(e, aiConfig);   // v252.12: Tipos 1 y 9
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
            else if (e.type === 5) t2Count++; // v254: Usando IDs sincronizados
            else if (e.type === 8) t3Count++;
        }
    });

    if (t1Count < 4) serverSpawnEnemy(1, 1);
    if (t2Count < 4) serverSpawnEnemy(1, 5);
    if (t3Count < 4) serverSpawnEnemy(1, 8);
}, 5000);

// v254.20: Bloqueo de Respawn Automático en Zona de Hordas
setInterval(() => {
    // No hacer nada en Zona 6, el HordeManager se encarga de todo.
}, 5000);

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
            // v240.80: REGEN DELAY DE 60 SEGUNDOS (Solicitado por Usuario)
            const delay = 60000; 
            
            // v239.12: RECALCULADO DINÁMICO EN CADA TICK (Garantía de Sincronía Total)
            // v240.81: Protección contra desincronía de baseHp
            const baseHp = p.baseHp || (p.currentShipConfig ? p.currentShipConfig.hp : 2000);
            const baseShield = p.baseShield || (p.currentShipConfig ? p.currentShipConfig.shield : 1000);
            
            const hpBonus = 1.0 + ((p.skillTree?.engineering[0] || 0) * 0.02);
            const shBonus = 1.0 + ((p.skillTree?.engineering[1] || 0) * 0.02);
            p.maxHp = Math.ceil(baseHp * hpBonus);
            p.maxShield = Math.ceil(baseShield * shBonus);

            // v240.67: DEPURACIÓN AGRESIVA DE DAÑO FANTASMA
            if (!p._lastHpDebug) p._lastHpDebug = p.hp;
            if (p.hp < p._lastHpDebug - 0.01) { 
                const diff = p._lastHpDebug - p.hp;
                // v240.86: Log de depuración eliminado para producción
            }
            p._lastHpDebug = p.hp;

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
                        isInvulnerable: p.isInvulnerable || false,
                        maxHp: p.maxHp, // v240.66: Enviar siempre máximos para evitar caps en cliente
                        maxShield: p.maxShield,
                        spheres: p.spheres, 
                        isDead: false
                    });
                }
            }
        }
    });
}, 33);

// v260.70: BUCLE DE ÁREAS Y ESTADOS (Humo, Silencio, Ceguera)
setInterval(() => {
    const now = Date.now();
    
    // Reset temporal de flags (v2.1: Más agresivo para respuesta instantánea)
    Object.values(players).forEach(p => {
        if (now - (p.lastSilenceTime || 0) > 200) p.isSilenced = false;
        
        const wasBlinded = p.isBlinded;
        if (now - (p.lastBlindTime || 0) > 200) p.isBlinded = false;
        
        if (wasBlinded && !p.isBlinded) {
            io.to(p.socketId).emit('blindState', { active: false });
        }
    });
    
    Object.values(enemies).forEach(e => {
        if (now - (e.lastSilenceTime || 0) > 200) e.isSilenced = false;
    });

    const areasToDelete = [];
    for (const id in activeAreas) {
        const area = activeAreas[id];
        if (now > area.endTime) {
            areasToDelete.push(id);
            io.to(`zone_${area.zone}`).emit('removeArea', { id });
            continue;
        }

        // Efectos a Jugadores
        Object.values(players).forEach(p => {
            if (p.zone === area.zone && !p.isDead && p.socketId !== area.ownerId) {
                const dx = p.x - area.x;
                const dy = p.y - area.y;
                const distSq = dx * dx + dy * dy;
                if (distSq < (area.radius * area.radius)) {
                    p.isSilenced = true;
                    p.lastSilenceTime = now;
                    
                    if (!p.isBlinded) {
                        p.isBlinded = true;
                        io.to(p.socketId).emit('blindState', { active: true });
                    }
                    p.lastBlindTime = now;
                }
            }
        });

        // Efectos a Enemigos
        Object.values(enemies).forEach(e => {
            if (e.zone === area.zone && e.hp > 0) {
                const dx = e.x - area.x;
                const dy = e.y - area.y;
                const distSq = dx * dx + dy * dy;
                if (distSq < (area.radius * area.radius)) {
                    e.isSilenced = true;
                    e.lastSilenceTime = now;
                }
            }
        });
    }
    areasToDelete.forEach(id => delete activeAreas[id]);
}, 100);

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

    // v242.20: GESTIÓN DE CLANES (FLOTAS)
    socket.on('leaveClan', async () => {
        if (!socket.dbUser || !players[socket.id]) return;
        const p = players[socket.id];
        if (!p.clanId) return;

        try {
            const user = await User.findById(socket.dbUser._id);
            const clan = await Clan.findById(p.clanId);
            if (!clan) return;

            // Remover miembro
            clan.members.pull(user._id);
            
            // v243.98: Lógica de Herencia/Disolución Automática
            if (clan.members.length === 0) {
                await Clan.deleteOne({ _id: clan._id });
                console.log(`[CLAN] Flota ${clan.name} eliminada (sin miembros).`);
            } else {
                // Si el que se va es el líder, pasar la corona al siguiente
                if (clan.leader.toString() === user._id.toString()) {
                    clan.leader = clan.members[0];
                    const newLeader = await User.findById(clan.leader);
                    if (newLeader) {
                        newLeader.gameData.clanRole = 'leader';
                        await newLeader.save();
                    }
                }
                await clan.save();
                
                // Notificar a los que quedan
                const payload = await getClanDataPayload(clan._id);
                io.to(`clan_${clan._id}`).emit('clanData', payload);
                io.to(`clan_${clan._id}`).emit('clanMemberStatus', { user: user.username, online: false });
            }

            user.gameData.clanId = null;
            user.gameData.clanRole = null;
            await user.save();

            socket.leave(`clan_${p.clanId}`);
            p.clanId = null;
            p.clanTag = ""; // v244.110: Limpiar tag al salir
            io.emit('playerUpdated', { id: socket.id, clanTag: "" }); // v244.111
            socket.emit('clanData', null);
            socket.emit('gameNotification', { msg: 'HAS ABANDONADO LA FLOTA', type: 'info' });

        } catch (e) { console.error("Error leaveClan:", e); }
    });

    socket.on('disbandClan', async () => {
        if (!socket.dbUser || !players[socket.id]) return;
        const p = players[socket.id];
        if (!p.clanId) return;

        try {
            const clan = await Clan.findById(p.clanId);
            if (!clan) return;

            if (clan.leader.toString() !== socket.dbUser._id.toString()) {
                return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER PUEDE DISOLVER LA FLOTA', type: 'error' });
            }

            // Notificar a todos y sacarlos
            io.to(`clan_${clan._id}`).emit('clanData', null);
            io.to(`clan_${clan._id}`).emit('gameNotification', { msg: 'LA FLOTA HA SIDO DISUELTA POR EL LÍDER', type: 'info' });

            // Limpiar usuarios en DB
            await User.updateMany({ "gameData.clanId": clan._id }, { $set: { "gameData.clanId": null, "gameData.clanRole": null } });

            // Limpiar en RAM y Rooms
            const roomName = `clan_${clan._id}`;
            const room = io.sockets.adapter.rooms.get(roomName);
            if (room) {
                const sids = Array.from(room);
                sids.forEach(sid => {
                    if (players[sid]) {
                        players[sid].clanId = null;
                        players[sid].clanTag = ""; // v244.110: Limpiar tag de todos los miembros
                        io.emit('playerUpdated', { id: sid, clanTag: "" }); // v244.111
                    }
                    const s = io.sockets.sockets.get(sid);
                    if (s) s.leave(roomName);
                });
            }

            await Clan.deleteOne({ _id: clan._id });
            console.log(`[CLAN] Flota ${clan.name} disuelta por ${socket.dbUser.username}`);
        } catch (e) { console.error("Error disbandClan:", e); }
    });

    socket.on('setClanJoinType', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        const { type } = data; // 'open' or 'invite'
        if (type !== 'open' && type !== 'invite') return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER PUEDE CAMBIAR ESTO', type: 'error' });

            clan.joinType = type;
            await clan.save();
            
            const payload = await getClanDataPayload(clan._id);
            io.to(`clan_${clan._id}`).emit('clanData', payload);
            socket.emit('gameNotification', { msg: `MODO DE INGRESO: ${type.toUpperCase()}`, type: 'success' });
        } catch (e) { console.error("Error setClanJoinType:", e); }
    });

    socket.on('kickClanMember', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        const { username } = data;
        if (!username) return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER PUEDE EXPULSAR', type: 'error' });

            const targetUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });
            if (!targetUser) return;

            if (targetUser._id.toString() === clan.leader.toString()) return;

            // Remover de la lista de miembros
            clan.members = clan.members.filter(m => m.toString() !== targetUser._id.toString());
            await clan.save();

            // Limpiar data del usuario
            targetUser.gameData.clanId = null;
            targetUser.gameData.clanRole = 'member';
            await targetUser.save();

            // Notificar al expulsado si está online
            const targetSocketId = activeSessions.get(username.toLowerCase());
            if (targetSocketId) {
                const targetSocket = io.sockets.sockets.get(targetSocketId);
                if (targetSocket) {
                    targetSocket.leave(`clan_${clan._id}`);
                    if (players[targetSocketId]) {
                        players[targetSocketId].clanId = null;
                        players[targetSocketId].clanTag = ""; // v244.110: Limpiar tag del expulsado
                        io.emit('playerUpdated', { id: targetSocketId, clanTag: "" }); // v244.111
                    }
                    targetSocket.emit('clanData', null);
                    targetSocket.emit('gameNotification', { msg: 'HAS SIDO EXPULSADO DE LA FLOTA', type: 'warning' });
                }
            }

            const payload = await getClanDataPayload(clan._id);
            io.to(`clan_${clan._id}`).emit('clanData', payload);
            socket.emit('gameNotification', { msg: `MIEMBRO EXPULSADO: ${username.toUpperCase()}`, type: 'success' });
        } catch (e) { console.error("Error kickClanMember:", e); }
    });

    socket.on('handleClanRequest', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        const { username, action } = data; // action: 'accept' or 'deny'
        if (!username || !action) return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER PUEDE GESTIONAR SOLICITUDES', type: 'error' });

            const targetUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });
            if (!targetUser) return;

            // Remover de solicitudes
            clan.requests = clan.requests.filter(r => r.toString() !== targetUser._id.toString());

            // v244.92: Limpiar solicitud en el usuario (Garantizar consistencia)
            if (targetUser.gameData && targetUser.gameData.pendingClanRequests) {
                targetUser.gameData.pendingClanRequests = targetUser.gameData.pendingClanRequests.filter(
                    req => req.id.toString() !== clan._id.toString()
                );
                targetUser.markModified('gameData.pendingClanRequests');
                await targetUser.save();
                
                // v244.94: Sincronía Instantánea con el Aplicante (Limpiar su lista de pendientes)
                const targetSocketId = activeSessions.get(username.toLowerCase());
                if (targetSocketId) {
                    const targetSocket = io.sockets.sockets.get(targetSocketId);
                    if (targetSocket) targetSocket.emit('inventoryData', { gameData: targetUser.gameData });
                }
            }

            if (action === 'accept') {
                if (clan.members.length >= clan.maxMembers) {
                    return socket.emit('gameNotification', { msg: 'CLAN LLENO', type: 'error' });
                }
                if (!clan.members.includes(targetUser._id)) {
                    clan.members.push(targetUser._id);
                    targetUser.gameData.clanId = clan._id;
                    targetUser.gameData.clanRole = 'member';
                    
                    // v244.98: Limpiar todo rastro de reclutamiento al unirse
                    targetUser.gameData.pendingClanRequests = [];
                    targetUser.gameData.receivedClanInvites = [];
                    targetUser.markModified('gameData.pendingClanRequests');
                    targetUser.markModified('gameData.receivedClanInvites');
                    
                    await targetUser.save();
                    
                    const targetSocketId = activeSessions.get(username.toLowerCase());
                    if (targetSocketId) {
                        const targetSocket = io.sockets.sockets.get(targetSocketId);
                        if (targetSocket) {
                            targetSocket.join(`clan_${clan._id}`);
                            if (players[targetSocketId]) {
                                players[targetSocketId].clanId = clan._id;
                                players[targetSocketId].clanTag = clan.tag; // v244.110
                                io.emit('playerUpdated', { id: targetSocketId, clanTag: clan.tag }); // v244.111
                            }
                            targetSocket.emit('gameNotification', { msg: `¡HAS SIDO ACEPTADO EN [${clan.tag}]!`, type: 'success' });
                        }
                    }
                }
            }

            await clan.save();
            const payload = await getClanDataPayload(clan._id);
            io.to(`clan_${clan._id}`).emit('clanData', payload);
            socket.emit('gameNotification', { msg: `SOLICITUD ${action === 'accept' ? 'ACEPTADA' : 'RECHAZADA'}: ${username.toUpperCase()}`, type: 'success' });
        } catch (e) { console.error("Error handleClanRequest:", e); }
    });

    socket.on('createClan', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        const { name, tag } = data;
        try {
            const existing = await Clan.findOne({ $or: [{ name }, { tag: tag.toUpperCase() }] });
            if (existing) return socket.emit('gameNotification', { msg: 'NOMBRE O TAG YA REGISTRADO', type: 'error' });

            const user = await User.findById(socket.dbUser._id);
            if (user.gameData.clanId) return socket.emit('gameNotification', { msg: 'YA PERTENECES A UNA FLOTA', type: 'error' });

            const newClan = new Clan({
                name,
                tag: tag.toUpperCase(),
                leader: user._id,
                members: [user._id]
            });
            await newClan.save();

            user.gameData.clanId = newClan._id;
            user.gameData.clanRole = 'leader'; // v243.11: Fundador es Líder
            
            // v244.98: Limpiar reclutamiento al fundar
            user.gameData.pendingClanRequests = [];
            user.gameData.receivedClanInvites = [];
            user.markModified('gameData.pendingClanRequests');
            user.markModified('gameData.receivedClanInvites');
            
            user.markModified('gameData.clanId');
            user.markModified('gameData.clanRole');
            await user.save();

            players[socket.id].clanId = newClan._id;
            players[socket.id].clanTag = newClan.tag; // v244.110
            io.emit('playerUpdated', { id: socket.id, clanTag: newClan.tag }); // v244.111: Broadcast instantáneo
            socket.join(`clan_${newClan._id}`);
            
            // Refrescar datos
            const clanData = await getClanDataPayload(newClan._id);
            socket.emit('clanData', clanData);
            socket.emit('gameNotification', { msg: `FLOTA [${tag}] FUNDADA CON ÉXITO`, type: 'success' });
            console.log(`[CLAN] ${user.username} fundó ${name} [${tag}]`);
        } catch (e) { console.error("Error createClan:", e); }
    });

    socket.on('inviteToClan', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        const { username } = data;
        if (!username) return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER PUEDE INVITAR', type: 'error' });

            if (clan.members.length >= (clan.maxMembers || 20)) {
                return socket.emit('gameNotification', { msg: 'FLOTA LLENA', type: 'error' });
            }

            const targetUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });
            if (!targetUser) return socket.emit('gameNotification', { msg: 'PILOTO NO ENCONTRADO', type: 'error' });

            if (targetUser.gameData.clanId) {
                return socket.emit('gameNotification', { msg: 'EL PILOTO YA PERTENECE A UNA FLOTA', type: 'error' });
            }

            // v244.95: Evitar duplicados en invitaciones recibidas
            if (!targetUser.gameData.receivedClanInvites) targetUser.gameData.receivedClanInvites = [];
            if (targetUser.gameData.receivedClanInvites.some(inv => inv.id.toString() === clan._id.toString())) {
                return socket.emit('gameNotification', { msg: 'YA ENVIASTE UNA INVITACIÓN A ESTE PILOTO', type: 'info' });
            }

            targetUser.gameData.receivedClanInvites.push({ id: clan._id, tag: clan.tag, name: clan.name });
            targetUser.markModified('gameData.receivedClanInvites');
            await targetUser.save();

            // v244.99: Registrar también en el clan para seguimiento del líder
            if (!clan.sentInvites) clan.sentInvites = [];
            if (!clan.sentInvites.includes(targetUser._id)) {
                clan.sentInvites.push(targetUser._id);
                await clan.save();
            }

            // Notificar al invitado si está online
            const targetSocketId = activeSessions.get(username.toLowerCase());
            if (targetSocketId) {
                const targetSocket = io.sockets.sockets.get(targetSocketId);
                if (targetSocket) {
                    const targetGD = JSON.parse(JSON.stringify(targetUser.gameData));
                    targetSocket.emit('inventoryData', { player: { gameData: targetGD } });
                    targetSocket.emit('gameNotification', { msg: `¡HAS SIDO INVITADO A LA FLOTA [${clan.tag}]!`, type: 'info' });
                }
            }

            socket.emit('gameNotification', { msg: `INVITACIÓN ENVIADA A ${username.toUpperCase()}`, type: 'success' });
            
            // v244.99: Actualizar UI del Líder inmediatamente para ver su nueva invitación enviada
            const leaderPayload = await getClanDataPayload(clan._id);
            socket.emit('clanData', leaderPayload);
        } catch (e) { console.error("Error inviteToClan:", e); }
    });

    socket.on('cancelClanInvite', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        const { username } = data;
        if (!username) return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return;

            const targetUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });
            if (!targetUser) return;

            // 1. Quitar del Clan
            if (clan.sentInvites) {
                clan.sentInvites = clan.sentInvites.filter(id => id.toString() !== targetUser._id.toString());
                await clan.save();
            }

            // 2. Quitar del Usuario
            if (targetUser.gameData && targetUser.gameData.receivedClanInvites) {
                targetUser.gameData.receivedClanInvites = targetUser.gameData.receivedClanInvites.filter(inv => inv.id.toString() !== clan._id.toString());
                targetUser.markModified('gameData.receivedClanInvites');
                await targetUser.save();
                
                // Notificar al usuario si está online para limpiar su UI
                const targetSocketId = activeSessions.get(username.toLowerCase());
                if (targetSocketId) {
                    const targetSocket = io.sockets.sockets.get(targetSocketId);
                    if (targetSocket) targetSocket.emit('inventoryData', { gameData: targetUser.gameData });
                }
            }

            const payload = await getClanDataPayload(clan._id);
            socket.emit('clanData', payload);
            socket.emit('gameNotification', { msg: `INVITACIÓN CANCELADA: ${username.toUpperCase()}`, type: 'warning' });
        } catch (e) { console.error("Error cancelClanInvite:", e); }
    });

    socket.on('handleClanInvite', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        const { clanId, action } = data; // action: 'accept' or 'deny'
        if (!clanId || !action) return;

        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user.gameData.receivedClanInvites) return;

            // Remover la invitación respondida
            user.gameData.receivedClanInvites = user.gameData.receivedClanInvites.filter(inv => inv.id.toString() !== clanId.toString());
            user.markModified('gameData.receivedClanInvites');

            if (action === 'accept') {
                if (user.gameData.clanId) return socket.emit('gameNotification', { msg: 'YA PERTENECES A UNA FLOTA', type: 'error' });
                
                const clan = await Clan.findById(clanId);
                if (!clan) return socket.emit('gameNotification', { msg: 'LA FLOTA YA NO EXISTE', type: 'error' });

                // v244.99: Limpiar también del registro del clan
                if (clan.sentInvites) {
                    clan.sentInvites = clan.sentInvites.filter(id => id.toString() !== user._id.toString());
                    await clan.save();
                }

                if (clan.members.length >= (clan.maxMembers || 20)) {
                    return socket.emit('gameNotification', { msg: 'LA FLOTA ESTÁ LLENA', type: 'error' });
                }

                if (!clan.members.includes(user._id)) {
                    clan.members.push(user._id);
                    await clan.save();
                }

                user.gameData.clanId = clan._id;
                user.gameData.clanRole = 'member';
                
                // Si acepta una, limpiar todas sus solicitudes enviadas a otros clanes
                user.gameData.pendingClanRequests = [];
                user.markModified('gameData.pendingClanRequests');
                
                players[socket.id].clanId = clan._id;
                socket.join(`clan_${clan._id}`);

                const payload = await getClanDataPayload(clan._id);
                io.to(`clan_${clan._id}`).emit('clanData', payload);
                socket.emit('gameNotification', { msg: `¡BIENVENIDO A [${clan.tag}]!`, type: 'success' });
            }

            await user.save();
            // Actualizar UI del usuario (Limpiar listas de invitaciones/pendientes)
            socket.emit('inventoryData', { gameData: user.gameData });
        } catch (e) { console.error("Error handleClanInvite:", e); }
    });

    socket.on('getClanData', async () => {
        if (!socket.dbUser || !players[socket.id]) return;
        const p = players[socket.id];
        if (!p.clanId) return socket.emit('clanData', null);

        try {
            const payload = await getClanDataPayload(p.clanId);
            socket.emit('clanData', payload);
        } catch (e) { console.error("Error getClanData:", e); }
    });

    socket.on('joinClan', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        const { tag } = data;
        try {
            const clan = await Clan.findOne({ tag: tag.toUpperCase() });
            if (!clan) return socket.emit('gameNotification', { msg: 'FLOTA NO ENCONTRADA', type: 'error' });

            const user = await User.findById(socket.dbUser._id);
            if (user.gameData.clanId) return socket.emit('gameNotification', { msg: 'YA PERTENECES A UNA FLOTA', type: 'error' });

            // v243.75: Validación de Límites y Tipo de Ingreso
            if (clan.members.length >= (clan.maxMembers || 20)) {
                return socket.emit('gameNotification', { msg: 'LA FLOTA ESTÁ LLENA (MÁX 20)', type: 'error' });
            }

            if (clan.joinType === 'invite') {
                // v243.76: Sistema de Solicitudes
                if (!clan.requests) clan.requests = [];
                if (clan.requests.some(r => r.toString() === user._id.toString())) {
                    return socket.emit('gameNotification', { msg: 'YA ENVIASTE UNA SOLICITUD', type: 'info' });
                }

                // v244.90: Limitar solicitudes (Máx 3)
                if (!user.gameData.pendingClanRequests) user.gameData.pendingClanRequests = [];
                if (user.gameData.pendingClanRequests.length >= 3) {
                    return socket.emit('gameNotification', { msg: 'MÁXIMO 3 SOLICITUDES PENDIENTES', type: 'error' });
                }

                clan.requests.push(user._id);
                await clan.save();

                // Registrar en el usuario para que sepa a quién le envió
                user.gameData.pendingClanRequests.push({ id: clan._id, tag: clan.tag, name: clan.name });
                user.markModified('gameData.pendingClanRequests');
                await user.save();

                // v244.93: Notificar al aplicante para que vea su lista actualizada de inmediato
                // v244.102: Asegurar objeto plano para socket.io y envolver en player para consistencia
                const updatedGameData = JSON.parse(JSON.stringify(user.gameData));
                socket.emit('inventoryData', { player: { gameData: updatedGameData } });

                // v244.91: Sincronía Instantánea con el Clan (Líder verá la solicitud al toque)
                const payload = await getClanDataPayload(clan._id);
                io.to(`clan_${clan._id}`).emit('clanData', payload);

                return socket.emit('gameNotification', { msg: 'SOLICITUD ENVIADA AL LÍDER', type: 'success' });
            }

            clan.members.push(user._id);
            await clan.save();

            user.gameData.clanId = clan._id;
            user.gameData.clanRole = 'member'; // v243.12: Ingresa como miembro raso
            
            // v244.98: Limpiar reclutamiento al unirse (Auto-Join)
            user.gameData.pendingClanRequests = [];
            user.gameData.receivedClanInvites = [];
            user.markModified('gameData.pendingClanRequests');
            user.markModified('gameData.receivedClanInvites');
            
            user.markModified('gameData.clanId');
            user.markModified('gameData.clanRole');
            await user.save();

            players[socket.id].clanId = clan._id;
            players[socket.id].clanTag = clan.tag; // v244.110
            io.emit('playerUpdated', { id: socket.id, clanTag: clan.tag }); // v244.111
            socket.join(`clan_${clan._id}`);
            
            const payload = await getClanDataPayload(clan._id);
            io.to(`clan_${clan._id}`).emit('clanData', payload);
            io.to(`clan_${clan._id}`).emit('clanMemberStatus', { user: user.username, online: true });
        } catch (e) { console.error("Error joinClan:", e); }
    });

    socket.on('cancelClanRequest', async (data) => {
        if (!socket.dbUser || !players[socket.id]) return;
        const { tag } = data;
        if (!tag) return;

        try {
            const clan = await Clan.findOne({ tag: tag.toUpperCase() });
            if (!clan) return;

            const user = await User.findById(socket.dbUser._id);
            if (!user) return;
            
            // 1. Quitar del Clan
            if (clan.requests) {
                clan.requests = clan.requests.filter(rid => rid.toString() !== user._id.toString());
                await clan.save();
                
                // Notificar al Líder si está online
                const payload = await getClanDataPayload(clan._id);
                io.to(`clan_${clan._id}`).emit('clanData', payload);
            }

            // 2. Quitar del Usuario
            if (user.gameData && user.gameData.pendingClanRequests) {
                user.gameData.pendingClanRequests = user.gameData.pendingClanRequests.filter(req => req.tag !== tag.toUpperCase());
                user.markModified('gameData.pendingClanRequests');
                await user.save();
                
                const updatedGD = JSON.parse(JSON.stringify(user.gameData));
                socket.emit('inventoryData', { player: { gameData: updatedGD } });
            }

            socket.emit('gameNotification', { msg: `SOLICITUD CANCELADA: [${tag.toUpperCase()}]`, type: 'warning' });
        } catch (e) { console.error("Error cancelClanRequest:", e); }
    });

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
            SERVER_CONFIG = config;
            
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
        if (SERVER_CONFIG && SERVER_CONFIG.hordeConfig) {
            SERVER_CONFIG.hordeConfig.active = true;
            hordeManager.updateConfig(SERVER_CONFIG.hordeConfig);
            console.log("[ADMIN] Evento de Hordas iniciado manualmente.");
            socket.emit('gameNotification', { msg: 'EVENTO DE HORDAS INICIADO', type: 'success' });
        }
    });

    socket.on('stopHordeEvent', () => {
        if (!players[socket.id] || players[socket.id].user !== "Caelli94") return;
        hordeManager.stopEvent();
        if (SERVER_CONFIG && SERVER_CONFIG.hordeConfig) SERVER_CONFIG.hordeConfig.active = false;
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

    // SISTEMA DE COMBATE MULTIPLAYER (v62.0)
    // v200.20: SISTEMA DE DAÑO AUTORITATIVO (Anti-Cheat Server-Side)
    socket.on('playerFire', (fireData) => {
        const p = players[socket.id];
        if (!p || !SERVER_CONFIG) return;

        // v260.66: BLOQUEO POR SILENCIO
        if (p.isSilenced) return;

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
        
        // v260.65: BLOQUEO POR SILENCIO
        if (p.isSilenced) {
            return socket.emit('gameNotification', { msg: "¡ESTÁS SILENCIADO!", type: "error" });
        }
        
        p.lastCombatTime = Date.now(); // v240.62: Habilidades resetean contador de cambio de nave
        
        const now = Date.now();
        const sphereIdx = data.id !== undefined ? data.id : -1;
        if (sphereIdx < 0 || sphereIdx >= 4) return;

        // v210.5: VALIDACIÓN DE COOLDOWN (Anti-Skill Spam)
        if (!p.sphereCooldowns) p.sphereCooldowns = [0, 0, 0, 0];
        const lastUsed = p.sphereCooldowns[sphereIdx];
        const skillCooldown = 4800; // 5s oficiales - 200ms de gracia por lag

        if (now - lastUsed < skillCooldown) {
            return;
        }

        // v200.45: VALIDACIÓN DE PODER (Ignorar powerValue del cliente)
        let powerValue = 0;
        const sphere = p.spheres[sphereIdx];
        if (sphere && sphere.equipped) {
            powerValue = sphere.equipped.power_value || 0;
        }

        if (powerValue <= 0) return; // Hack detected or no skill equipped

        // v3.8: SOPORTE PARA OBJETIVOS REMOTOS (Aliados/Enemigos) v262.10
        let skillConfig = (SERVER_CONFIG && SERVER_CONFIG.skillsData) ? SERVER_CONFIG.skillsData[data.skillName] : null;
        
        // v4.9.1: Sobrescribir siempre con el fallback para evitar que un caché antiguo con canTargetOthers=false rompa el servidor
        const fallbacks = {
            "ESCUDO CELULAR": { canTargetOthers: true, targetFilters: { allies: true, enemies: false, bosses: false, players: true } },
            "AUTO-REPARACIÓN": { canTargetOthers: true, targetFilters: { allies: true, enemies: false, bosses: false, players: true } },
            "NANO-REGENERACIÓN": { canTargetOthers: true, targetFilters: { allies: true, enemies: false, bosses: false, players: true } },
            "TURBO-IMPULSO": { canTargetOthers: true, targetFilters: { allies: true, enemies: false, bosses: false, players: true } },
            "PLASMA BLAST": { canTargetOthers: true, targetFilters: { allies: false, enemies: true, bosses: true, players: true } }
        };
        
        if (fallbacks[data.skillName]) {
            if (!skillConfig) skillConfig = {};
            skillConfig.canTargetOthers = fallbacks[data.skillName].canTargetOthers;
            skillConfig.targetFilters = fallbacks[data.skillName].targetFilters;
        }

        let target = p; // Por defecto el usuario
        let isRemote = false;

        if (skillConfig && skillConfig.canTargetOthers) {
            // v4.4: Si es una habilidad dirigida y no hay targetId o es inválido, abortar
            if (!data.targetId) return;

            const targetPlayer = players[data.targetId];
            const targetEnemy = enemies[data.targetId];
            const potentialTarget = targetPlayer || targetEnemy;

            if (!potentialTarget || potentialTarget.hp <= 0) return;

            // v4.8: Validación de rango en el servidor
            if (data.targetId !== socket.id && skillConfig.range && skillConfig.range > 0) {
                const dx = p.x - potentialTarget.x;
                const dy = p.y - potentialTarget.y;
                const dist = Math.sqrt(dx * dx + dy * dy);
                if (dist > skillConfig.range + 50) {
                    console.log(`[SPHERES] Rango excedido: ${dist} > ${skillConfig.range}`);
                    return; // Abortar si está fuera de rango (con 50px de tolerancia)
                }
            }

            // Si el objetivo es uno mismo, siempre es válido (v3.9.1)
            if (data.targetId === socket.id) {
                target = p;
            } else {
                // Validar Filtros
                const filters = skillConfig.targetFilters || { allies: true, enemies: false, bosses: false, players: true };
                let isValid = false;

                if (targetPlayer) {
                    const sameClan = (p.clanId && targetPlayer.clanId && p.clanId.toString() === targetPlayer.clanId.toString());
                    const isAlly = sameClan || (!p.pvpEnabled && !targetPlayer.pvpEnabled);
                    const isEnemy = !sameClan && (p.pvpEnabled || targetPlayer.pvpEnabled);
                    
                    if (isAlly && filters.allies) isValid = true;
                    else if (isEnemy && (filters.enemies || filters.players)) isValid = true;
                    else if (!isAlly && !isEnemy && filters.players) isValid = true;
                } else if (targetEnemy) {
                    const isBoss = targetEnemy.type === 4 || targetEnemy.type === 10 || targetEnemy.type === 11;
                    if (isBoss && filters.bosses) isValid = true;
                    else if (!isBoss && filters.enemies) isValid = true;
                }

                if (isValid) {
                    target = potentialTarget;
                    isRemote = true;
                } else {
                    return; // Filtros no coinciden, abortar
                }
            }
        }

        p.sphereCooldowns[sphereIdx] = now; // Registrar uso legítimo
        let actual_val = powerValue;

        // Aplicar Efectos (v3.8.5: Soporte Polimórfico)
        if (data.skillName === "ESCUDO CELULAR" || data.skillName === "FORTALEZA-X") {
            const ms = target.maxShield || 2000;
            const oldS = target.shield || 0;
            target.shield = Math.min(oldS + powerValue, ms);
            actual_val = target.shield - oldS;
        } else if (data.skillName === "AUTO-REPARACIÓN" || data.skillName === "NANO-REGENERACIÓN") {
            const mh = target.maxHp || 3000;
            const oldH = target.hp || 0;
            target.hp = Math.min(oldH + powerValue, mh);
            actual_val = target.hp - oldH;
        } else if (data.skillName === "PLASMA BLAST") {
            // Daño directo a enemigo/jugador hostil
            if (target !== p) {
                const oldH = target.hp || 0;
                target.hp -= powerValue;
                if (target.hp < 0) target.hp = 0;
                actual_val = oldH - target.hp; // Valor positivo de daño
            }
        } else if (data.skillName === "SMOKE-BOMB") {
            const areaId = `area_${nextAreaId++}`;
            const config = (SERVER_CONFIG && SERVER_CONFIG.skillsData) ? SERVER_CONFIG.skillsData["SMOKE-BOMB"] : { duration: 6, radius: 180 };
            
            activeAreas[areaId] = {
                id: areaId,
                x: p.x,
                y: p.y,
                radius: config.radius || 180,
                type: 'SMOKE',
                ownerId: socket.id,
                endTime: Date.now() + (config.duration * 1000),
                zone: p.zone
            };
            
            io.to(`zone_${p.zone}`).emit('spawnArea', activeAreas[areaId]);
            console.log(`[SKILL] ${p.user} lanzó BOMBA DE HUMO en Zona ${p.zone}`);
        }

        // Sincronizar stats si el objetivo es un jugador
        if (target.socketId) {
            target.lastSyncHp = target.hp;
            target.lastSyncSh = target.shield;

            io.to(`zone_${target.zone}`).emit('playerStatSync', {
                id: target.socketId,
                hp: Math.ceil(target.hp),
                shield: Math.ceil(target.shield),
                spheres: target.spheres,
                isDead: target.hp <= 0
            });
        }

        // Notificar visualmente a la zona
        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', {
            id: socket.id,
            skillName: data.skillName,
            powerValue: actual_val,
            targetId: isRemote ? data.targetId : socket.id
        });

        const s_data = (SERVER_CONFIG && SERVER_CONFIG.skillsData) ? SERVER_CONFIG.skillsData[data.skillName] || {} : {};
        
        if (data.skillName === "INVULNERABILIDAD") {
            p.isInvulnerable = true;
            console.log(`[SKILL] ${p.user} es ahora INVULNERABLE`);
            
            // v2.7: Sync inmediato para feedback instantáneo
            const syncData = { 
                id: socket.id, 
                hp: Math.ceil(p.hp), 
                shield: Math.ceil(p.shield), 
                isInvulnerable: true 
            };
            io.to(`zone_${p.zone}`).emit('playerStatSync', syncData);

            const duration = (s_data.duration || 2) * 1000;
            setTimeout(() => {
                p.isInvulnerable = false;
                console.log(`[SKILL] ${p.user} ya no es invulnerable`);
                const endSync = { id: socket.id, isInvulnerable: false };
                io.to(`zone_${p.zone}`).emit('playerStatSync', endSync);
            }, duration);
        } else if (data.skillName === "BLINK") {
            // v2.9: Sincronía autoritativa de Teletransporte
            if (data.pos) {
                p.x = data.pos.x;
                p.y = data.pos.y;
                console.log(`[SKILL] ${p.user} se teletransportó a ${p.x}, ${p.y}`);
                // Forzar broadcast de posición
                io.to(`zone_${p.zone}`).emit('playerMoveSync', { id: socket.id, x: p.x, y: p.y, rot: p.rot });
            }
        }

        console.log(`[SPHERES] Piloto ${p.user} usó ${data.skillName} (Target: ${isRemote ? (target.user || target.name) : 'Self'}).`);
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

            if (!user.gameData[currency] && user.gameData[currency] !== 0) return socket.emit('authError', 'MONEDA INVALIDA');

            // 1. LOCALIZAR ITEM CONFIG (v222.85: Búsqueda unificada y limpia)
            let itemConfig = null;
            if (category === 'ammo') {
                for (const type in SERVER_CONFIG.shopItems.ammo) {
                    const found = SERVER_CONFIG.shopItems.ammo[type].find(i => i.id === itemId);
                    if (found) { itemConfig = found; break; }
                }
            } else if (category === 'ships') {
                itemConfig = SERVER_CONFIG.shipModels.find(s => s.id === itemId);
            } else if (SERVER_CONFIG.shopItems[category]) {
                itemConfig = SERVER_CONFIG.shopItems[category].find(i => i.id === itemId);
            }

            if (!itemConfig) return socket.emit('authError', 'ITEM NO ENCONTRADO EN LA GALAXIA');

            // 2. VALIDACIONES PREVIAS (Para no descontar moneda si no procede)
            if (category === 'ships') {
                const shipIdNum = parseInt(itemConfig.id);
                if (user.gameData.ownedShips.includes(shipIdNum)) {
                    return socket.emit('authError', 'YA POSEES ESTA NAVE');
                }
            }

            // 3. CALCULO DE PRECIOS Y VALIDACIÓN DE FONDOS
            const pricePerUnit = itemConfig.prices[currency];
            const qty = parseInt(amount) || 1000;
            const totalPrice = category === 'ammo' ? Math.floor((qty / 100.0) * pricePerUnit) : pricePerUnit;

            if (user.gameData[currency] < totalPrice) {
                return socket.emit('authError', `FONDOS INSUFICIENTES DE ${currency.toUpperCase()}`);
            }

            // 4. PROCESAR TRANSACCIÓN
            user.gameData[currency] -= totalPrice;

            if (category === 'ships') {
                const shipIdNum = parseInt(itemConfig.id);
                user.gameData.ownedShips.push(shipIdNum);
            } else if (category === 'ammo') {
                const typeKey = itemId.split('_')[1].substring(0, 1) === 'l' ? 'laser' : (itemId.split('_')[1].substring(0, 1) === 'm' ? 'missile' : 'mine');
                const tier = itemConfig.tier || 0;
                if (!user.gameData.ammo) user.gameData.ammo = { laser: [0, 0, 0, 0, 0, 0], missile: [0, 0, 0, 0, 0, 0], mine: [0, 0, 0, 0, 0, 0] };
                user.gameData.ammo[typeKey][tier] = (user.gameData.ammo[typeKey][tier] || 0) + qty;
            } else {
                const newItem = {
                    id: itemConfig.id,
                    name: itemConfig.name,
                    "type": "Utility",
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

            // 5. RESPUESTA AL CLIENTE (v241.20: Usar toObject para garantizar arrays limpios)
            socket.emit('inventoryData', { player: user.gameData.toObject() });
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
                // v240.85: Bloqueo de Combate Estricto (60s)
                const now = Date.now();
                const COMBAT_DELAY = 60000;
                const lastCombat = p.lastCombatTime || 0;
                const diff = now - lastCombat;

                if (diff < COMBAT_DELAY) {
                    const remaining = Math.ceil((COMBAT_DELAY - diff) / 1000);
                    socket.emit('gameNotification', { 
                        msg: `ERROR: Sistemas de armas calientes. Espera ${remaining}s fuera de combate para cambiar.`, 
                        type: 'error' 
                    });
                    console.log(`[HANGAR] Cambio bloqueado para ${p.user}. Faltan ${remaining}s.`);
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
                const newShipData = SERVER_CONFIG.shipModels.find(s => s.id === shipId) || { hp: 3000, shield: 1000 };
                
                // v240.31: ACTUALIZAR STATS BASE (Crucial para el bucle de regen v239.12)
                p.baseHp = newShipData.hp || 3000;
                p.baseShield = newShipData.shield || 1000;

                const hpBonus = 1.0 + ((p.skillTree?.engineering[0] || 0) * 0.02);
                const shBonus = 1.0 + ((p.skillTree?.engineering[1] || 0) * 0.02);

                p.maxHp = Math.ceil(p.baseHp * hpBonus);
                p.maxShield = Math.ceil(p.baseShield * shBonus);
                
                // v240.21: Persistencia de Vida/Escudo (No recargar al 100%)
                p.hp = Math.min(p.hp, p.maxHp);
                p.shield = Math.min(p.shield, p.maxShield);

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

                // v240.65: BROADCAST GLOBAL (Usar io.to para incluir al sender)
                const zoneRoom = `zone_${p.zone}`;
                io.to(zoneRoom).emit('playerShipChanged', { id: socket.id, shipId: shipId });
                io.to(zoneRoom).emit('playerStatSync', {
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

        // v254.40: VALIDACIÓN DE DAÑO RELAJADA (Evita Desync en Hordas)
        let finalDamage = parseFloat(damage) || 100;
        
        // Anti-Cheat: Subimos el base de 200 a 5000 para no romper el juego avanzado
        let maxAllowed = 5000; 
        if (p.equipped && p.equipped.w) {
            let weaponsBase = 0;
            p.equipped.w.forEach(it => {
                // Buscamos en toda la tienda (weapons, pero también fallback por si cambió el ID)
                const master = SERVER_CONFIG.shopItems.weapons.find(w => w.id === it.id);
                if (master) weaponsBase += (master.base || 0);
                else weaponsBase += 500; // v254.41: Fallback generoso para no capar daño
            });
            if (weaponsBase > 0) {
                // Multiplicador: Munici├│n T6 (15x) + Críticos + Habilidades
                maxAllowed = weaponsBase * 40; 
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
        p.lastCombatTime = Date.now(); // v240.22: Marcar combate al acertar objetivo

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
            if (p.isInvulnerable) {
                // v2.6: Forzar daño 0 pero seguir flujo para feedback (0 en rojo)
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
                isInvulnerable: p.isInvulnerable,
                spheres: p.spheres || [] 
            };
            io.to(`zone_${p.zone}`).emit('playerStatSync', syncData);
        }
    });

    // v220.82: REGLA DE ORO PVP - Ambos deben tenerlo activo
    socket.on('playerHitByPlayer', (data) => {
        const victim = players[data.victimId];
        const attacker = players[socket.id];
        
        if (victim && attacker && !victim.isDead && !attacker.isDead) {
            // v221.30: Consentimiento Mutuo + Notificación
            if (victim.pvpEnabled && attacker.pvpEnabled) {
                if (victim.isInvulnerable) return; // Inmunidad total v2.6
                const now = Date.now();
                let dmg = data.damage || 50;
                
                // Lógica de mitigación (Escudo primero)
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
                
                victim.lastCombatTime = Date.now(); // v240.61: Recibir daño de jugador resetea timer
                attacker.lastCombatTime = Date.now(); // v240.61: Atacar a jugador resetea timer
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
