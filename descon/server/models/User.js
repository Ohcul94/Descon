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
        // v210.60: EQUIPAMIENTO ÚNICO POR NAVE
        equippedByShip: { 
            type: Map, 
            of: Object, 
            default: {
                "1": { w: [], s: [], e: [], x: [] }
            } 
        },
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
        hudPositions: { type: Object, default: {} },
        hudLayouts: { type: Array, default: [] }, // v266.130: Soporte para múltiples slots (máx 4)
        spheres: { type: Array, default: [
            { "name": "Alfa", "type": "w", "color": "#ffe031", "equipped": null },
            { "name": "Beta", "type": "s", "color": "#31dfff", "equipped": null },
            { "name": "Gamma", "type": "e", "color": "#3bff31", "equipped": null }
        ]},
        pvpEnabled: { type: Boolean, default: false }, // v220.95: Persistencia de combate
        clanId: { type: mongoose.Schema.Types.ObjectId, ref: 'Clan', default: null }, // v242.10: Integración de Clanes
        clanRole: { type: String, enum: ['leader', 'officer', 'member'], default: 'member' }, // v243.10: Rangos de Flota
        pendingClanRequests: { type: Array, default: [] }, // v244.102: Persistencia de solicitudes
        receivedClanInvites: { type: Array, default: [] } // v244.102: Persistencia de invitaciones
    }
});

module.exports = mongoose.model('User', UserSchema);
