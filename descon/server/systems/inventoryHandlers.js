const User = require('../models/User');

/**
 * registerInventoryHandlers
 * Maneja compras, equipamiento, talentos y naves.
 */
function registerInventoryHandlers(socket, io, state) {
    
    // SISTEMA DE TIENDA Y ADQUISICIÓN
    socket.on('buyItem', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        try {
            const { category, itemId, currency, amount } = data;
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            if (!user.gameData[currency] && user.gameData[currency] !== 0) return socket.emit('authError', 'MONEDA INVALIDA');

            let itemConfig = null;
            if (category === 'ammo') {
                for (const type in state.SERVER_CONFIG.shopItems.ammo) {
                    const found = state.SERVER_CONFIG.shopItems.ammo[type].find(i => i.id === itemId);
                    if (found) { itemConfig = found; break; }
                }
            } else if (category === 'ships') {
                itemConfig = state.SERVER_CONFIG.shipModels.find(s => s.id === itemId);
            } else if (state.SERVER_CONFIG.shopItems[category]) {
                itemConfig = state.SERVER_CONFIG.shopItems[category].find(i => i.id === itemId);
            }

            if (!itemConfig) return socket.emit('authError', 'ITEM NO ENCONTRADO EN LA GALAXIA');

            if (category === 'ships') {
                const shipIdNum = parseInt(itemConfig.id);
                if (user.gameData.ownedShips.includes(shipIdNum)) {
                    return socket.emit('authError', 'YA POSEES ESTA NAVE');
                }
            }

            const pricePerUnit = itemConfig.prices[currency];
            const qty = parseInt(amount) || 1000;
            const totalPrice = category === 'ammo' ? Math.floor((qty / 100.0) * pricePerUnit) : pricePerUnit;

            if (user.gameData[currency] < totalPrice) {
                return socket.emit('authError', `FONDOS INSUFICIENTES DE ${currency.toUpperCase()}`);
            }

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

            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            const p = state.players[socket.id];
            if (p) {
                p.hubs = user.gameData.hubs;
                p.ohcu = user.gameData.ohcu;
                p.ammo = JSON.parse(JSON.stringify(user.gameData.ammo));
            }

            const eByShipObj = {};
            if (user.gameData.equippedByShip) {
                user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            }

            socket.emit('inventoryData', {
                player: { ...user.gameData.toObject(), equippedByShip: eByShipObj }
            });

            socket.emit('gameNotification', { msg: `COMPRA EXITOSA: ${itemConfig.name.toUpperCase()}`, type: 'success' });
        } catch (e) { console.error("Error en buyItem:", e); }
    });

    // ÁRBOL DE TALENTOS (SKILL TREE)
    socket.on('investSkill', async (data) => {
        if (!socket.dbUser) return;
        const { branch, index } = data; 
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user || user.gameData.skillPoints <= 0) return;

            if (!user.gameData.skillTree) user.gameData.skillTree = { engineering: [0, 0, 0, 0, 0], combat: [0, 0, 0, 0, 0], utility: [0, 0, 0, 0, 0] };
            if (!user.gameData.skillTree[branch]) return;
            
            if (user.gameData.skillTree[branch][index] >= 5) return;

            user.gameData.skillTree[branch][index]++;
            user.gameData.skillPoints--;

            user.markModified('gameData.skillTree');
            user.markModified('gameData.skillPoints');
            await user.save();
            socket.dbUser = user;

            const p = state.players[socket.id];
            if (p) {
                p.skillTree = user.gameData.skillTree;
                p.skillPoints = user.gameData.skillPoints;

                const hpBonus = 1.0 + ((p.skillTree.engineering[0] || 0) * 0.02);
                const shBonus = 1.0 + ((p.skillTree.engineering[1] || 0) * 0.02);
                p.maxHp = Math.ceil((p.baseHp || 2000) * hpBonus);
                p.maxShield = Math.ceil((p.baseShield || 1000) * shBonus);

                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: socket.id, hp: p.hp, shield: p.shield, maxHp: p.maxHp, maxShield: p.maxShield, spheres: p.spheres
                });
            }

            socket.emit('inventoryData', { player: user.gameData });
        } catch (e) { console.error("Error en investSkill:", e); }
    });

    socket.on('resetSkills', async () => {
        if (!socket.dbUser) return;
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            let totalInvested = 0;
            const tree = user.gameData.skillTree || {};
            for (const b in tree) {
                tree[b].forEach(val => { totalInvested += val; });
                tree[b] = [0, 0, 0, 0, 0];
            }

            user.gameData.skillPoints += totalInvested;
            user.gameData.skillTree = tree;
            user.markModified('gameData.skillTree');
            user.markModified('gameData.skillPoints');
            await user.save();
            socket.dbUser = user;

            const p = state.players[socket.id];
            if (p) {
                p.skillTree = user.gameData.skillTree;
                p.skillPoints = user.gameData.skillPoints;
                p.maxHp = p.baseHp || 2000;
                p.maxShield = p.baseShield || 1000;
                if (p.hp > p.maxHp) p.hp = p.maxHp;
                if (p.shield > p.maxShield) p.shield = p.maxShield;

                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: socket.id, hp: p.hp, shield: p.shield, maxHp: p.maxHp, maxShield: p.maxShield, spheres: p.spheres
                });
            }

            socket.emit('inventoryData', { player: user.gameData });
            socket.emit('gameNotification', { msg: "TALENTOS REINICIADOS", type: "info" });
        } catch (e) { console.error("Error en resetSkills:", e); }
    });

    // EQUIPAMIENTO DE MÓDULOS
    socket.on('equipItem', async (data) => {
        if (!socket.dbUser) return;
        try {
            const { category, index, shipId } = data; 
            const user = await User.findById(socket.dbUser._id);
            if (!user || !user.gameData.inventory[index]) return;

            const targetShipId = shipId ? parseInt(shipId) : user.gameData.currentShipId;
            const shipKey = targetShipId.toString();

            if (!user.gameData.equippedByShip) user.gameData.equippedByShip = new Map();
            let shipEquip = user.gameData.equippedByShip.get(shipKey);

            if (!shipEquip && targetShipId === user.gameData.currentShipId) {
                shipEquip = JSON.parse(JSON.stringify(user.gameData.equipped || { w: [], s: [], e: [], x: [] }));
            }
            if (!shipEquip) shipEquip = { w: [], s: [], e: [], x: [] };

            const shipModel = state.SERVER_CONFIG.shipModels.find(s => s.id === targetShipId);
            const maxSlots = shipModel ? (shipModel.slots ? shipModel.slots[category] : 2) : 2;

            if (shipEquip[category].length >= maxSlots) {
                return socket.emit('authError', 'NO HAY SLOTS DISPONIBLES');
            }

            const item = user.gameData.inventory.splice(index, 1)[0];
            shipEquip[category].push(item);

            user.gameData.equippedByShip.set(shipKey, JSON.parse(JSON.stringify(shipEquip)));

            if (targetShipId === user.gameData.currentShipId) {
                user.gameData.equipped = JSON.parse(JSON.stringify(shipEquip));
                user.markModified('gameData.equipped');
            }

            user.markModified('gameData.equippedByShip');
            user.markModified('gameData.inventory');
            await user.save();
            socket.dbUser = user;

            const eByShipObj = {};
            user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });

            socket.emit('inventoryData', {
                player: { ...user.gameData.toObject(), equippedByShip: eByShipObj, equipped: user.gameData.equipped }
            });

            if (state.players[socket.id] && targetShipId === user.gameData.currentShipId) {
                state.players[socket.id].inventory = user.gameData.inventory;
                state.players[socket.id].equipped = JSON.parse(JSON.stringify(user.gameData.equipped));
            }
        } catch (e) { console.error("Error en equipItem:", e); }
    });

    socket.on('unequipItem', async (data) => {
        if (!socket.dbUser) return;
        try {
            const { category, index, shipId } = data;
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const targetShipId = shipId ? parseInt(shipId) : user.gameData.currentShipId;
            const shipKey = targetShipId.toString();

            if (!user.gameData.equippedByShip) user.gameData.equippedByShip = new Map();
            let shipEquip = user.gameData.equippedByShip.get(shipKey);

            if (!shipEquip && targetShipId === user.gameData.currentShipId) {
                shipEquip = JSON.parse(JSON.stringify(user.gameData.equipped || { w: [], s: [], e: [], x: [] }));
            }

            if (!shipEquip || !shipEquip[category] || !shipEquip[category][index]) return;

            const item = shipEquip[category][index];
            user.gameData.inventory.push(item);
            shipEquip[category].splice(index, 1);

            user.gameData.equippedByShip.set(shipKey, JSON.parse(JSON.stringify(shipEquip)));

            if (targetShipId === user.gameData.currentShipId) {
                user.gameData.equipped = JSON.parse(JSON.stringify(shipEquip));
                user.markModified('gameData.equipped');
            }

            user.markModified('gameData.equippedByShip');
            user.markModified('gameData.inventory');
            await user.save();
            socket.dbUser = user;

            const eByShipObj = {};
            user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });

            socket.emit('inventoryData', {
                player: { ...user.gameData.toObject(), equippedByShip: eByShipObj, equipped: user.gameData.equipped }
            });

            if (state.players[socket.id] && targetShipId === user.gameData.currentShipId) {
                state.players[socket.id].inventory = user.gameData.inventory;
                state.players[socket.id].equipped = JSON.parse(JSON.stringify(user.gameData.equipped));
            }
        } catch (e) { console.error("Error en unequipItem:", e); }
    });

    // GESTIÓN DE ESFERAS
    socket.on('equipSphere', async (data) => {
        if (!socket.dbUser) return;
        const { sphereId, skill } = data; 
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            if (!user.gameData.spheres || user.gameData.spheres.length < 4) {
                user.gameData.spheres = [{}, {}, {}, {}];
            }
            user.gameData.spheres[sphereId] = { equipped: skill };
            user.markModified('gameData.spheres');
            await user.save();
            socket.dbUser = user;

            if (state.players[socket.id]) {
                state.players[socket.id].spheres = user.gameData.spheres;
            }

            socket.emit('inventoryData', { player: user.gameData });
        } catch (e) { console.error("Error en equipSphere:", e); }
    });

    socket.on('unequipSphere', async (data) => {
        if (!socket.dbUser) return;
        const { sphereId } = data;
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;
            if (user.gameData.spheres && user.gameData.spheres[sphereId]) {
                user.gameData.spheres[sphereId] = {};
                user.markModified('gameData.spheres');
                await user.save();
                socket.dbUser = user;
                if (state.players[socket.id]) state.players[socket.id].spheres = user.gameData.spheres;
                socket.emit('inventoryData', { player: user.gameData });
            }
        } catch (e) { console.error("Error en unequipSphere:", e); }
    });

    // CAMBIO DE NAVE
    socket.on('switchShip', async (shipId) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];
        
        const now = Date.now();
        const timeSinceCombat = now - (p.lastCombatTime || 0);
        if (timeSinceCombat < 10000) {
            return socket.emit('gameNotification', { msg: `EN COMBATE: ESPERA ${Math.ceil((10000 - timeSinceCombat)/1000)}s`, type: 'warning' });
        }

        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user || !user.gameData.ownedShips.includes(parseInt(shipId))) return;

            user.gameData.currentShipId = parseInt(shipId);
            
            if (!user.gameData.equippedByShip) user.gameData.equippedByShip = new Map();
            const shipKey = shipId.toString();
            let shipEquip = user.gameData.equippedByShip.get(shipKey);
            
            if (!shipEquip) {
                shipEquip = { w: [], s: [], e: [], x: [] };
                user.gameData.equippedByShip.set(shipKey, shipEquip);
            }
            
            user.gameData.equipped = JSON.parse(JSON.stringify(shipEquip));
            user.markModified('gameData.currentShipId');
            user.markModified('gameData.equipped');
            user.markModified('gameData.equippedByShip');
            await user.save();
            socket.dbUser = user;

            const shipModel = state.SERVER_CONFIG.shipModels.find(s => s.id === parseInt(shipId));
            if (shipModel) {
                p.type = parseInt(shipId);
                p.baseHp = shipModel.hp || 2000;
                p.baseShield = shipModel.shield || 1000;
                p.equipped = user.gameData.equipped;

                const hpBonus = 1.0 + ((p.skillTree.engineering[0] || 0) * 0.02);
                const shBonus = 1.0 + ((p.skillTree.engineering[1] || 0) * 0.02);
                p.maxHp = Math.ceil(p.baseHp * hpBonus);
                p.maxShield = Math.ceil(p.baseShield * shBonus);
                
                p.hp = p.maxHp;
                p.shield = p.maxShield;

                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: socket.id, hp: p.hp, shield: p.shield, maxHp: p.maxHp, maxShield: p.maxShield, spheres: p.spheres
                });
                io.emit('playerUpdated', { id: socket.id, type: p.type });
            }

            const eByShipObj = {};
            user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            socket.emit('inventoryData', { player: { ...user.gameData.toObject(), equippedByShip: eByShipObj } });
            socket.emit('gameNotification', { msg: `NAVE CAMBIADA CON ÉXITO`, type: 'success' });

        } catch (e) { console.error("Error en switchShip:", e); }
    });
}

module.exports = {
    registerInventoryHandlers
};
