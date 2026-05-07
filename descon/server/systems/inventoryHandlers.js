const User = require('../models/User');

/**
 * v262.450: HELPER DE CATEGORIZACIÓN ESTÁNDAR (Minúsculas para Godot)
 */
function getCategorizedInventory(inventory) {
    const categories = { weapons: [], modules: [], resources: [], others: [] };
    if (!inventory || !Array.isArray(inventory)) return categories;

    inventory.forEach(item => {
        const id = (item.id || "").toLowerCase();
        
        // Sincronización estricta con los tipos de Godot (lowercase)
        if (id.startsWith('las') || id.startsWith('w')) {
            item.type = "weapon"; 
            categories.weapons.push(item);
        } else if (id.startsWith('sh') || id.startsWith('s')) {
            item.type = "shield";
            categories.modules.push(item);
        } else if (id.startsWith('en') || id.startsWith('e')) {
            item.type = "engine";
            categories.modules.push(item);
        } else {
            if (!item.type) item.type = "utility";
            item.type = item.type.toLowerCase();
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
    
    // COMPRA DE ÍTEMS
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
                let type = (itemConfig.type || "utility").toLowerCase();
                const id = itemConfig.id.toLowerCase();
                if (id.startsWith('las') || id.startsWith('w')) type = "weapon";
                else if (id.startsWith('sh') || id.startsWith('s')) type = "shield";
                else if (id.startsWith('en') || id.startsWith('e')) type = "engine";

                user.gameData.inventory.push({
                    id: itemConfig.id,
                    name: itemConfig.name,
                    type: type,
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

    // EQUIPAR ÍTEM
    socket.on('equipItem', async (raw_data) => {
        if (!socket.dbUser) return;
        try {
            const data = (typeof raw_data === 'object' && raw_data.instanceId) ? raw_data : raw_data;
            const instanceId = data.instanceId;
            const shipId = (typeof data.shipId === 'object') ? (data.shipId.id || data.shipId.shipId) : data.shipId;

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

            if (shipEquip[slot].length >= max) {
                return socket.emit('authError', `BODEGA LLENA: No hay más espacio para ${slot.toUpperCase()}`);
            }

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
        const now = Date.now();
        const COMBAT_DELAY = 60000;
        const lastCombat = p.lastCombatTime || 0;
        const diff = now - lastCombat;

        if (diff < COMBAT_DELAY) {
            const remaining = Math.ceil((COMBAT_DELAY - diff) / 1000);
            return socket.emit('gameNotification', { 
                msg: `ERROR: Sistemas de armas calientes. Espera ${remaining}s fuera de combate para cambiar.`, 
                type: 'error' 
            });
        }

        try {
            let shipId = raw_shipId;
            if (typeof raw_shipId === 'object' && raw_shipId !== null) {
                shipId = raw_shipId.shipId || raw_shipId.id || 1;
            }
            
            const user = await User.findById(socket.dbUser._id);
            const targetId = parseInt(shipId);
            if (!user || !user.gameData.ownedShips.includes(targetId)) return;

            user.gameData.currentShipId = targetId;
            const shipKey = targetId.toString();
            let equip = getShipEquip(user, shipKey);

            user.gameData.equipped = JSON.parse(JSON.stringify(equip));
            
            user.markModified('gameData.currentShipId');
            user.markModified('gameData.equipped');
            user.markModified('gameData'); 

            await user.save();
            socket.dbUser = user;

            const model = state.SERVER_CONFIG.shipModels.find(s => s.id === targetId);
            if (model && p) {
                p.type = targetId;
                p.currentShipId = targetId;
                p.baseHp = model.hp || 2000; 
                p.baseShield = model.shield || 1000;
                const eng = p.skillTree?.engineering || [0, 0];
                const bonusHp = 1.0 + ((eng[0] || 0) * 0.02);
                const bonusSh = 1.0 + ((eng[1] || 0) * 0.02);
                p.maxHp = Math.ceil(p.baseHp * bonusHp);
                p.maxShield = Math.ceil(p.baseShield * bonusSh);
                p.hp = p.maxHp; p.shield = p.maxShield;
                p.equipped = user.gameData.equipped;

                io.to(`zone_${p.zone}`).emit('playerStatSync', { id: socket.id, hp: p.hp, shield: p.shield, maxHp: p.maxHp, maxShield: p.maxShield });
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
            
            const item = shipEquip[data.category].splice(idx, 1)[0];
            user.gameData.inventory.push(item);
            
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

    // v262.600: SISTEMA DE VENTA (Reciclaje al 50% de HUBS)
    socket.on('sellItem', async (data) => {
        if (!socket.dbUser) return;
        try {
            const { instanceId } = data;
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const idx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
            if (idx === -1) return;

            const item = user.gameData.inventory[idx];
            
            let originalPrice = 0;
            const allItems = [
                ...(state.SERVER_CONFIG.shopItems.weapons || []),
                ...(state.SERVER_CONFIG.shopItems.shields || []),
                ...(state.SERVER_CONFIG.shopItems.engines || []),
                ...(state.SERVER_CONFIG.shopItems.extra || [])
            ];
            
            const configItem = allItems.find(i => i.id === item.id);
            if (configItem && configItem.prices && configItem.prices.hubs) {
                originalPrice = configItem.prices.hubs;
            }

            const refund = Math.floor(originalPrice / 2);
            user.gameData.inventory.splice(idx, 1);
            user.gameData.hubs += refund;

            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });

            socket.emit('gameNotification', { msg: `VENDIDO POR ${refund} HUBS`, type: 'success' });
        } catch (e) { console.error(e); }
    });
}

module.exports = { registerInventoryHandlers, getCategorizedInventory };
