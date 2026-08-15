const User = require('../models/User');

/**
 * v6.02: Adaptador autoritativo en memoria (RAM) para el modelo de Mongoose.
 * Permite mantener la compatibilidad con el código actual que opera sobre el objeto de Mongoose,
 * pero redirige todas las lecturas/escrituras directamente a la RAM del servidor.
 * Al llamar a .save(), realiza una actualización atómica asíncrona no bloqueante en background.
 */
function getPlayerRAMAdapter(p) {
    if (!p) return null;
    return {
        _id: p.id,
        username: p.user,
        gameData: {
            get hubs() { return p.hubs; },
            set hubs(v) { p.hubs = v; },

            get ohcu() { return p.ohcu; },
            set ohcu(v) { p.ohcu = v; },

            get inventory() { return p.inventory || []; },
            set inventory(v) { p.inventory = v; },

            get equipped() { return p.equipped || { w: [], s: [], e: [], x: [] }; },
            set equipped(v) { p.equipped = v; },

            get ownedShips() { return p.ownedShips || [1]; },
            set ownedShips(v) { p.ownedShips = v; },

            get currentShipId() { return p.currentShipId || 1; },
            set currentShipId(v) { p.currentShipId = v; },

            get equippedByShip() { return p.equippedByShip || {}; },
            set equippedByShip(v) { p.equippedByShip = v; },

            get ammo() { return p.ammo || {}; },
            set ammo(v) { p.ammo = v; },

            get selectedAmmo() { return p.selectedAmmo || {}; },
            set selectedAmmo(v) { p.selectedAmmo = v; },

            get lastPos() { return p.lastPos || { x: 2000, y: 2000 }; },
            set lastPos(v) { p.lastPos = v; },

            get hp() { return p.hp; },
            set hp(v) { p.hp = v; },

            get maxHp() { return p.maxHp; },
            set maxHp(v) { p.maxHp = v; },

            get shield() { return p.shield; },
            set shield(v) { p.shield = v; },

            get maxShield() { return p.maxShield; },
            set maxShield(v) { p.maxShield = v; },

            get level() { return p.level || 1; },
            set level(v) { p.level = v; },

            get exp() { return p.exp || 0; },
            set exp(v) { p.exp = v; },

            get skillPoints() { return p.skillPoints || 0; },
            set skillPoints(v) { p.skillPoints = v; },

            get skillTree() { return p.skillTree || { engineering: [], combat: [], science: [] }; },
            set skillTree(v) { p.skillTree = v; },

            get zone() { return p.zone || 1; },
            set zone(v) { p.zone = v; },

            get hudConfig() { return p.hudConfig || {}; },
            set hudConfig(v) { p.hudConfig = v; },

            get hudPositions() { return p.hudPositions || {}; },
            set hudPositions(v) { p.hudPositions = v; },

            get hudLayouts() { return p.hudLayouts || []; },
            set hudLayouts(v) { p.hudLayouts = v; },

            get spheres() { return p.spheres || []; },
            set spheres(v) { p.spheres = v; },

            get pvpEnabled() { return !!p.pvpEnabled; },
            set pvpEnabled(v) { p.pvpEnabled = !!v; },

            get clanId() { return p.clanId; },
            set clanId(v) { p.clanId = v; },

            get vaultItems() { return p.vaultItems || []; },
            set vaultItems(v) { p.vaultItems = v; },

            get vaultUnlockedTabs() { return p.vaultUnlockedTabs || 1; },
            set vaultUnlockedTabs(v) { p.vaultUnlockedTabs = v; },

            get inventoryMaxSlots() { return p.inventoryMaxSlots || 30; },
            set inventoryMaxSlots(v) { p.inventoryMaxSlots = v; },

            get quests() { return p.quests || { active: [], completed: [], lastDailyReset: null, lastWeeklyReset: null }; },
            set quests(v) { p.quests = v; },

            get unlocks() { return p.unlocks || []; },
            set unlocks(v) { p.unlocks = v; },

            get battlePass() { return p.battlePass || { level: 1, exp: 0, isVip: false, claimedFree: [], claimedVip: [] }; },
            set battlePass(v) { p.battlePass = v; },

            get rankingData() { return p.rankingData || { monsters_killed: 0, events_completed: 0 }; },
            set rankingData(v) { p.rankingData = v; },

            get housing() { return p.housing || { unlocked: false, placedObjects: [] }; },
            set housing(v) { p.housing = v; },

            get marketMailbox() { return p.marketMailbox || []; },
            set marketMailbox(v) { p.marketMailbox = v; }
        },
        markModified(path) {
            // En memoria la mutación es directa y JS detecta los cambios automáticamente.
            // No requiere acción del mapper de Mongoose.
        },
        save: async function() {
            // Guardado atómico no bloqueante en background (sin await)
            User.updateOne(
                { _id: p.id },
                {
                    $set: {
                        "gameData.inventory": p.inventory,
                        "gameData.vaultItems": p.vaultItems,
                        "gameData.vaultUnlockedTabs": p.vaultUnlockedTabs,
                        "gameData.inventoryMaxSlots": p.inventoryMaxSlots,
                        "gameData.ownedShips": p.ownedShips,
                        "gameData.equippedByShip": p.equippedByShip,
                        "gameData.equipped": p.equipped,
                        "gameData.ammo": p.ammo,
                        "gameData.selectedAmmo": p.selectedAmmo,
                        "gameData.hubs": p.hubs,
                        "gameData.ohcu": p.ohcu,
                        "gameData.level": p.level,
                        "gameData.exp": p.exp,
                        "gameData.skillPoints": p.skillPoints,
                        "gameData.skillTree": p.skillTree,
                        "gameData.spheres": p.spheres,
                        "gameData.quests": p.quests,
                        "gameData.unlocks": p.unlocks || [],
                        "gameData.battlePass": p.battlePass,
                        "gameData.rankingData": p.rankingData,
                        "gameData.housing": p.housing || { unlocked: false, placedObjects: [] },
                        "gameData.marketMailbox": p.marketMailbox || []
                    }
                }
            ).catch(err => {
                console.error(`[RAM-ADAPTER-SAVE-ERR] Error al persistir en background para ${p.user}:`, err.message);
            });
            return this;
        },
        toObject: function() {
            // Para casos de deserialización como logs o payloads crudos
            return {
                _id: p.id,
                username: p.user,
                gameData: {
                    hubs: p.hubs,
                    ohcu: p.ohcu,
                    inventory: p.inventory,
                    equipped: p.equipped,
                    ownedShips: p.ownedShips,
                    currentShipId: p.currentShipId,
                    equippedByShip: p.equippedByShip,
                    ammo: p.ammo,
                    selectedAmmo: p.selectedAmmo,
                    lastPos: p.lastPos,
                    hp: p.hp,
                    maxHp: p.maxHp,
                    shield: p.shield,
                    maxShield: p.maxShield,
                    level: p.level,
                    exp: p.exp,
                    skillPoints: p.skillPoints,
                    skillTree: p.skillTree,
                    zone: p.zone,
                    hudConfig: p.hudConfig,
                    hudPositions: p.hudPositions,
                    hudLayouts: p.hudLayouts,
                    spheres: p.spheres,
                    pvpEnabled: p.pvpEnabled,
                    clanId: p.clanId,
                    vaultItems: p.vaultItems,
                    vaultUnlockedTabs: p.vaultUnlockedTabs,
                    inventoryMaxSlots: p.inventoryMaxSlots,
                    quests: p.quests,
                    unlocks: p.unlocks || [],
                    battlePass: p.battlePass,
                    rankingData: p.rankingData,
                    housing: p.housing || { unlocked: false, placedObjects: [] },
                    marketMailbox: p.marketMailbox || []
                }
            };
        }
    };
}

module.exports = { getPlayerRAMAdapter };
