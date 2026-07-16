require('dotenv').config();
const mongoose = require('mongoose');
const User = require('./models/User');
const Clan = require('./models/Clan');
const { calculateFinalStats } = require('./systems/statCalculator');
const fs = require('fs-extra');
const path = require('path');

const CONFIG_FILE = path.join(__dirname, 'config.json');

const state = {
    SERVER_CONFIG: {},
    nextPlayerNum: 1,
    players: {}
};

async function testUser(username) {
    console.log(`\nProbando login simulado para: ${username}`);
    const user = await User.findOne({ username: username.toLowerCase() });
    if (!user) {
        console.log("Usuario no encontrado.");
        return;
    }

    const socket = {
        id: 'mock-socket-id',
        handshake: { address: '127.0.0.1' },
        emit: (event, data) => console.log(`   [Emit] ${event}`),
        join: (room) => console.log(`   [Join] ${room}`),
        broadcast: {
            to: (room) => ({
                emit: (event, data) => console.log(`   [Broadcast.to(${room})] ${event}`)
            })
        }
    };

    try {
        const lowName = username.toLowerCase();
        user.lastLogin = new Date();
        socket.dbUser = user;
        const dbId = user._id.toString();

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

        const p_ref = {
            id: dbId,
            socketId: socket.id,
            num: state.nextPlayerNum++,
            user: username,
            x: 2000,
            y: 2000,
            rotation: 0,
            hp: baseHp,
            maxHp: baseHp,
            shield: baseSh,
            maxShield: baseSh,
            level: user.gameData.level || 1,
            skillTree: user.gameData.skillTree || {
                engineering: [0, 0, 0, 0, 0, 0, 0, 0],
                combat: [0, 0, 0, 0, 0, 0, 0, 0],
                science: [0, 0, 0, 0, 0, 0, 0, 0]
            },
            baseHp: baseHp,
            baseShield: baseSh,
            ammo: {},
            equipped: resolvedEquip,
            spheres: user.gameData.spheres,
            currentShipId: user.gameData.currentShipId || 1,
            zone: user.gameData.zone || 1
        };

        calculateFinalStats(p_ref, state.SERVER_CONFIG);
        console.log("   ¡ÉXITO SIMULADO!");
    } catch (err) {
        console.error("   ¡FALLÓ EN BACKEND!", err);
    }
}

async function run() {
    try {
        const config = await fs.readJson(CONFIG_FILE);
        state.SERVER_CONFIG = config || {};
        await mongoose.connect(process.env.MONGODB_URI);
        console.log("Conectado para pruebas.");
        
        await testUser('player5');
        await testUser('caelli94');
    } catch (e) {
        console.error("Fallo general:", e);
    } finally {
        await mongoose.disconnect();
    }
}

run();
