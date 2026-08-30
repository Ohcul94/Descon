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
            mine: { type: [Number], default: [10, 0, 0, 0, 0, 0] },
            melee: { type: [Number], default: [0, 0, 0, 0, 0, 0] },
            heal: { type: [Number], default: [0, 0, 0, 0, 0, 0] },
            siphon: { type: [Number], default: [0, 0, 0, 0, 0, 0] },
            emp: { type: [Number], default: [0, 0, 0, 0, 0, 0] },
            electron: { type: [Number], default: [0, 0, 0, 0, 0, 0] }
        },
        selectedAmmo: {
            laser: { type: Number, default: 0 },
            missile: { type: Number, default: 0 },
            mine: { type: Number, default: 0 },
            melee: { type: Number, default: 0 },
            heal: { type: Number, default: 0 },
            siphon: { type: Number, default: 0 },
            emp: { type: Number, default: 0 },
            electron: { type: Number, default: 0 }
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
        zone: { type: Number, default: 1 },
        hudConfig: { type: Object, default: {} },
        hudPositions: { type: Object, default: {} },
        hudLayouts: { type: Array, default: [] }, // v266.130: Soporte para múltiples slots (máx 4)
        spheres: { type: Array, default: [
            { "name": "Slot 1", "type": "any", "color": "#ffffff", "sphere": null, "equipped": null },
            { "name": "Slot 2", "type": "any", "color": "#ffffff", "sphere": null, "equipped": null },
            { "name": "Slot 3", "type": "any", "color": "#ffffff", "sphere": null, "equipped": null },
            { "name": "Slot 4", "type": "any", "color": "#ffffff", "sphere": null, "equipped": null }
        ]},
        pvpEnabled: { type: Boolean, default: false }, // v220.95: Persistencia de combate
        clanId: { type: mongoose.Schema.Types.ObjectId, ref: 'Clan', default: null }, // v242.10: Integración de Clanes
        clanRole: { type: String, enum: ['leader', 'officer', 'member'], default: 'member' }, // v243.10: Rangos de Flota
        pendingClanRequests: { type: Array, default: [] }, // v244.102: Persistencia de solicitudes
        receivedClanInvites: { type: Array, default: [] }, // v244.102: Persistencia de invitaciones
        isPremium: { type: Boolean, default: false }, // v305.0: Estatus de Piloto de Elite
        // v350.0: BAÚL DE SEGURIDAD PERSONAL
        vaultItems: { type: Array, default: [] },
        vaultUnlockedTabs: { type: Number, default: 1 },
        inventoryMaxSlots: { type: Number, default: 30 },
        housing: {
            unlocked: { type: Boolean, default: false },
            placedObjects: { type: Array, default: [] }
        },
        quests: {
            active: { type: Array, default: [] },
            completed: { type: Array, default: [] },
            lastDailyReset: { type: Date, default: null },
            lastWeeklyReset: { type: Date, default: null }
        },
        // v600.0: Desbloqueos obtenidos por misiones (portales, armas, habilidades, talentos)
        unlocks: { type: Array, default: [] },
        battlePass: {
            level: { type: Number, default: 1 },
            exp: { type: Number, default: 0 },
            isVip: { type: Boolean, default: false },
            vipActiveUntil: { type: Date, default: null },
            claimedFree: { type: [Number], default: [] },
            claimedVip: { type: [Number], default: [] },
            lastDailyClaim: { type: Date, default: null }
        },
        // v450.0: Sistema de Clasificación / Ranking
        rankingData: {
            monsters_killed: { type: Number, default: 0 },
            events_completed: { type: Number, default: 0 }
        },
        // v500.0: MERCADO / CASA DE SUBASTAS - Buzón de entrega
        marketMailbox: { type: Array, default: [] },
        // v1.0: MENSAJES Y RESPUESTAS DE SOPORTE (BUGS)
        supportMailbox: { type: Array, default: [] },
        // v800.0: NIEBLA DE GUERRA - Mapas explorados por zona (grilla persistente)
        // Formato Map<String zoneId, Number[] cellIndices> donde cell = y*GRID_RES + x, GRID_RES=64
        exploredMaps: { type: Map, of: [Number], default: {} },
        exploredAt: { type: Map, of: Date, default: {} }
    }
});

module.exports = mongoose.model('User', UserSchema);
