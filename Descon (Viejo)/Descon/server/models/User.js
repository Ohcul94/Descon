const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
    username: { type: String, required: true, unique: true, lowercase: true, index: true },
    password: { type: String, required: true },
    createdAt: { type: Date, default: Date.now },
    lastLogin: { type: Date, default: Date.now },
    
    // Progresión del Jugador
    gameData: {
        hubs: { type: Number, default: 0 },
        ohcu: { type: Number, default: 0 },
        inventory: { type: Array, default: [] },
        equipped: {
            w: { type: Array, default: [] }, // Armas
            s: { type: Array, default: [] }, // Escudos
            e: { type: Array, default: [] }, // Motores
            x: { type: Array, default: [] }  // Extras
        },
        ownedShips: { type: [Number], default: [1] },
        maxShips: { type: Number, default: 2 },
        currentShipId: { type: Number, default: 1 },
        ammo: {
            laser: { type: [Number], default: [1000, 0, 0, 0, 0, 0] },
            missile: { type: [Number], default: [50, 0, 0, 0, 0, 0] },
            mine: { type: [Number], default: [10, 0, 0, 0, 0, 0] }
        },
        selectedAmmo: {
            laser: { type: Number, default: 0 },
            missile: { type: Number, default: 0 },
            mine: { type: Number, default: 0 }
        },
        lastPos: {
            x: { type: Number, default: 2000 },
            y: { type: Number, default: 2000 }
        },
        hp: { type: Number, default: 2000 },
        maxHp: { type: Number, default: 2000 },
        shield: { type: Number, default: 1000 },
        maxShield: { type: Number, default: 1000 },
        level: { type: Number, default: 1 },
        exp: { type: Number, default: 0 },
        skillPoints: { type: Number, default: 0 },
        skillTree: {
            engineering: { type: [Number], default: [0, 0, 0, 0, 0, 0, 0, 0] },
            combat: { type: [Number], default: [0, 0, 0, 0, 0, 0, 0, 0] },
            science: { type: [Number], default: [0, 0, 0, 0, 0, 0, 0, 0] }
        },
        zone: { type: Number, default: 1 }, // Registro de Sector v69.8
        hudConfig: { type: Object, default: {} },
        hudPositions: { type: Object, default: {} }
    }
});

module.exports = mongoose.model('User', UserSchema);
