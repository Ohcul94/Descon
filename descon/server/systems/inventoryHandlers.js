const User = require('../models/User');

/**
 * v262.350: HELPER DE CATEGORIZACIÓN ULTRA-SEGURO
 * Fuerza los tipos para que Godot no tire errores de 'Utility'
 */
function getCategorizedInventory(inventory) {
    const categories = { weapons: [], modules: [], resources: [], others: [] };
    if (!inventory || !Array.isArray(inventory)) return categories;

    inventory.forEach(item => {
        const id = (item.id || "").toLowerCase();
        
        // CORRECCIÓN DINÁMICA: Si el ID dice que es un láser, lo tratamos como Weapon
        if (id.startsWith('las') || id.startsWith('w')) {
            item.type = "Weapon";
            categories.weapons.push(item);
        } else if (id.startsWith('sh') || id.startsWith('s')) {
            item.type = "Shield";
            categories.modules.push(item);
        } else if (id.startsWith('en') || id.startsWith('e') || id.startsWith('m')) {
            item.type = "Engine";
            categories.modules.push(item);
        } else {
            categories.others.push(item);
        }
    });
    return categories;
}

function getShipEquip(user, shipKey) {
    if (!user.gameData.equippedByShip) return { w: [], s: [], e: [], x: [] };
    let data = null;
    if (typeof user.gameData.equippedByShip.get === 'function') {
        data = user.gameData.equippedByShip.get(shipKey);
    } else {
        data = user.gameData.equippedByShip[shipKey];
    }
    return data || { w: [], s: [], e: [], x: [] };
}

function registerInventoryHandlers(socket, io, state) {
    
    // TIENDA
    socket.on('buyItem', async (data) => {
        if (!socket.dbUser) return;
        try {
            const { category, itemId, currency, amount } = data;
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            let itemConfig = null;
            if (category === 'ammo') {
                for (const type in state.SERVER_CONFIG.shopItems.ammo) {
                    const found = state.SERVER_CONFIG.shopItems.ammo[type].find(i => i.id === itemId);
                    if (found) { itemConfig = found; break; }
                }
            } else if (state.SERVER_CONFIG.shopItems[category]) {
                itemConfig = state.SERVER_CONFIG.shopItems[category].find(i => i.id === itemId);
            }

            if (!itemConfig) return socket.emit('authError', 'ITEM NO ENCONTRADO');

            const price = itemConfig.prices[currency] || 0;
            const totalPrice = category === 'ammo' ? Math.floor((parseInt(amount)/100)*price) : price;

            if ((user.gameData[currency] || 0) < totalPrice) return socket.emit('authError', 'FONDOS INSUFICIENTES');

            user.gameData[currency] -= totalPrice;

            if (category !== 'ammo') {
                user.gameData.inventory.push({
                    id: itemConfig.id,
                    name: itemConfig.name,
                    type: itemConfig.type || "Utility",
                    base: itemConfig.base || 0,
                    instanceId: Date.now() + Math.random().toString(36).substr(2, 5),
                    rarity: itemConfig.rarity || 0,
                    color: itemConfig.color || "#ffffff",
                    icon: itemConfig.icon || "res://assets/items/placeholder.png"
                });
            }

            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });
        } catch (e) { console.error(e); }
    });

    // EQUIPAR
    socket.on('equipItem', async (raw_data) => {
        if (!socket.dbUser) return;
        try {
            // v262.360: Extraer ID si mandan un objeto de Godot
            const data = (typeof raw_data === 'object' && raw_data.instanceId) ? raw_data : raw_data;
            const instanceId = data.instanceId;
            const shipId = (typeof data.shipId === 'object') ? data.shipId.id : data.shipId;

            const user = await User.findById(socket.dbUser._id);
            const idx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
            if (idx === -1) return;

            const item = user.gameData.inventory[idx];
            const id = (item.id || "").toLowerCase();

            let slot = 'x';
            if (id.startsWith('las') || id.startsWith('w')) slot = 'w';
            else if (id.startsWith('sh') || id.startsWith('s')) slot = 's';
            else if (id.startsWith('en') || id.startsWith('e')) slot = 'e';

            const targetId = shipId ? parseInt(shipId) : user.gameData.currentShipId;
            const shipKey = targetId.toString();
            let shipEquip = getShipEquip(user, shipKey);

            const shipModel = state.SERVER_CONFIG.shipModels.find(s => s.id === targetId);
            const max = (shipModel && shipModel.slots) ? (shipModel.slots[slot] || 1) : 1;

            if (shipEquip[slot].length >= max) return socket.emit('authError', 'BODEGA LLENA');

            user.gameData.inventory.splice(idx, 1);
            shipEquip[slot].push(item);
            
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.set(shipKey, shipEquip);
            else user.gameData.equippedByShip[shipKey] = shipEquip;

            if (targetId === user.gameData.currentShipId) user.gameData.equipped = shipEquip;

            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });
        } catch (e) { console.error(e); }
    });

    // CAMBIAR NAVE
    socket.on('switchShip', async (raw_shipId) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];
        
        // v240.85: Bloqueo de Combate Estricto (60s) - Restaurado desde Commit e58e470
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
            console.log(`\x1b[33m[HANGAR]\x1b[0m Cambio bloqueado para ${p.user}. Faltan ${remaining}s.`);
            return;
        }

        try {
            // v262.360: Extraer ID si mandan un objeto de Godot [object Object]
            let shipId = raw_shipId;
            if (typeof raw_shipId === 'object' && raw_shipId !== null) {
                shipId = raw_shipId.shipId || raw_shipId.id || 1;
            }
            
            console.log(`[SHIP] Procesando cambio a nave: ${shipId} (Raw: ${JSON.stringify(raw_shipId)})`);
            
            const user = await User.findById(socket.dbUser._id);
            const targetId = parseInt(shipId);
            if (!user || !user.gameData.ownedShips.includes(targetId)) return;

            user.gameData.currentShipId = targetId;
            const shipKey = targetId.toString();
            let equip = getShipEquip(user, shipKey);

            user.gameData.equipped = JSON.parse(JSON.stringify(equip));
            
            // v262.380: Marcado de modificación ultra-preciso para evitar reversión
            user.markModified('gameData.currentShipId');
            user.markModified('gameData.equipped');
            user.markModified('gameData'); 

            await user.save();
            socket.dbUser = user;
            console.log(`[SHIP] Persistencia confirmada para ${user.username} en nave ${targetId}`);

            const p = state.players[socket.id];
            const model = state.SERVER_CONFIG.shipModels.find(s => s.id === targetId);
            if (model && p) {
                p.type = targetId;
                p.currentShipId = targetId; // v262.390: Sincronía con Auto-Save
                p.baseHp = model.hp || 2000; 
                p.baseShield = model.shield || 1000;

                // v262.370: Cálculos ultra-seguros para evitar NaN en Godot
                const eng = p.skillTree?.engineering || [0, 0];
                const bonusHp = 1.0 + ((eng[0] || 0) * 0.02);
                const bonusSh = 1.0 + ((eng[1] || 0) * 0.02);

                p.maxHp = Math.ceil(p.baseHp * bonusHp);
                p.maxShield = Math.ceil(p.baseShield * bonusSh);
                p.hp = p.maxHp; 
                p.shield = p.maxShield;
                p.equipped = user.gameData.equipped;

                io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                    id: socket.id, 
                    hp: p.hp, 
                    shield: p.shield, 
                    maxHp: p.maxHp, 
                    maxShield: p.maxShield 
                });
                io.emit('playerUpdated', { id: socket.id, type: p.type });
            }

            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);

            socket.emit('inventoryData', { 
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) } 
            });
        } catch (e) { console.error(e); }
    });

    socket.on('unequipItem', async (data) => {
        if (!socket.dbUser) return;
        try {
            const user = await User.findById(socket.dbUser._id);
            const targetId = data.shipId ? parseInt(data.shipId) : user.gameData.currentShipId;
            const shipKey = targetId.toString();
            let shipEquip = getShipEquip(user, shipKey);
            const idx = shipEquip[data.category].findIndex(it => it.instanceId === data.instanceId);
            if (idx === -1) return;
            user.gameData.inventory.push(shipEquip[data.category].splice(idx, 1)[0]);
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.set(shipKey, shipEquip);
            else user.gameData.equippedByShip[shipKey] = shipEquip;
            if (targetId === user.gameData.currentShipId) user.gameData.equipped = shipEquip;
            user.markModified('gameData'); await user.save();
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);
            socket.emit('inventoryData', { player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) } });
        } catch (e) { }
    });
}

module.exports = { registerInventoryHandlers, getCategorizedInventory };
