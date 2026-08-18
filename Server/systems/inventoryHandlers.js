const User = require('../models/User');
const { getPlayerRAMAdapter } = require('../utils/ramAdapter'); // v6.02
const { calculateFinalStats } = require('./statCalculator'); // v266.135: Recalcular al equipar
const { getMasterItemConfig: getMasterItemConfigFull, getSkillMasterConfig, checkRequirements } = require('./equipRequirements'); // v400.0: Requisitos de equipamiento
const visibilityGuard = require('./visibilityGuard'); // v620.0: Ojito de visibilidad de ítems

/**
 * v262.450: HELPER DE CATEGORIZACIÓN ESTÁNDAR (Minúsculas para Godot)
 */
function getCategorizedInventory(inventory) {
    const categories = { weapons: [], modules: [], resources: [], others: [] };
    if (!inventory || !Array.isArray(inventory)) return categories;

    inventory.forEach(item => {
        const id = (item.id || "").toLowerCase();
        
        if (id.startsWith('las') || id.startsWith('w')) {
            item.type = "weapon"; 
            categories.weapons.push(item);
        } else if (id.startsWith('sh') || id.startsWith('s')) {
            item.type = "shield";
            categories.modules.push(item);
        } else if (id.startsWith('en') || id.startsWith('e')) {
            item.type = "engine";
            categories.modules.push(item);
        } else if (id.startsWith('mat_') || (item.type && item.type.toLowerCase() === 'resource')) {
            item.type = "resource";
            categories.resources.push(item);
        } else {
            if (!item.type) item.type = "utility";
            item.type = item.type.toLowerCase();
            categories.others.push(item);
        }
    });
    return categories;
}

function getMasterItemConfig(itemId, serverConfig) {
    const id = (itemId || "").toLowerCase();
    if (id.startsWith('mat_')) {
        return (serverConfig.shopItems?.resources || []).find(r => r.id === itemId);
    }
    if (id.startsWith('recipe_')) {
        return (serverConfig.craftingRecipes || []).find(r => r.id === itemId);
    }
    const allShopItems = [
        ...(serverConfig.shopItems?.weapons || []),
        ...(serverConfig.shopItems?.shields || []),
        ...(serverConfig.shopItems?.engines || []),
        ...(serverConfig.shopItems?.extra || []),
        ...(serverConfig.shopItems?.extras || []),
        ...(serverConfig.shopItems?.spheres || []),
        ...(serverConfig.shopItems?.resources || [])
    ];
    let found = allShopItems.find(item => item.id === itemId);
    if (found) return found;
    
    return (serverConfig.craftingRecipes || []).find(r => r.id === itemId);
}

function addItemToInventory(user, itemData, serverConfig, quantity = 1) {
    const master = getMasterItemConfig(itemData.id, serverConfig);
    const maxStack = master ? parseInt(master.maxStack) || 1 : 1;
    // v500.0: Propagación del flag soulbound desde el config maestro (Mercado)
    const soulbound = master ? master.soulbound === true : itemData.soulbound === true;
    
    if (maxStack > 1) {
        let remainingToAdd = quantity;
        for (let i = 0; i < user.gameData.inventory.length; i++) {
            const currentItem = user.gameData.inventory[i];
            if (currentItem.id === itemData.id) {
                const currentAmount = parseInt(currentItem.amount) || 1;
                if (currentAmount < maxStack) {
                    const spaceInStack = maxStack - currentAmount;
                    const toAdd = Math.min(spaceInStack, remainingToAdd);
                    currentItem.amount = currentAmount + toAdd;
                    remainingToAdd -= toAdd;
                    if (remainingToAdd <= 0) break;
                }
            }
        }
        
        while (remainingToAdd > 0) {
            const maxSlots = user.gameData.inventoryMaxSlots || serverConfig.inventoryConfig?.defaultMaxSlots || 30;
            if (user.gameData.inventory.length >= maxSlots) {
                return remainingToAdd;
            }
            
            const toAdd = Math.min(maxStack, remainingToAdd);
            user.gameData.inventory.push({
                ...JSON.parse(JSON.stringify(itemData)),
                instanceId: Date.now() + Math.random().toString(36).substr(2, 5),
                amount: toAdd,
                soulbound: soulbound
            });
            remainingToAdd -= toAdd;
        }
        return 0;
    } else {
        let remainingToAdd = quantity;
        while (remainingToAdd > 0) {
            const maxSlots = user.gameData.inventoryMaxSlots || serverConfig.inventoryConfig?.defaultMaxSlots || 30;
            if (user.gameData.inventory.length >= maxSlots) {
                return remainingToAdd;
            }
            user.gameData.inventory.push({
                ...JSON.parse(JSON.stringify(itemData)),
                instanceId: Date.now() + Math.random().toString(36).substr(2, 5),
                amount: 1,
                soulbound: soulbound
            });
            remainingToAdd--;
        }
        return 0;
    }
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

// v262.700: Helper Global de Validación de Combate
function checkCombatLock(p) {
    const now = Date.now();
    const COMBAT_DELAY = (Number(p.zone) === 1) ? 10000 : 60000;
    const lastCombat = p.lastCombatTime || 0;
    const diff = now - lastCombat;
    if (diff < COMBAT_DELAY) {
        return { 
            locked: true, 
            remaining: Math.ceil((COMBAT_DELAY - diff) / 1000) 
        };
    }
    return { locked: false };
}

function sendInventoryData(socket, user, config) {
    if (!user) return;
    const eByShipObj = {};
    if (user.gameData.equippedByShip instanceof Map) {
        user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
    } else {
        Object.assign(eByShipObj, user.gameData.equippedByShip || {});
    }
    const isAdmin = !!(socket && socket.dbUser && socket.dbUser.username && socket.dbUser.username.toLowerCase() === 'caelli94');
    const sanitized = isAdmin ? {
        ...JSON.parse(JSON.stringify(user.gameData)),
        equippedByShip: eByShipObj
    } : visibilityGuard.sanitizeGameDataForClient({
        ...JSON.parse(JSON.stringify(user.gameData)),
        equippedByShip: eByShipObj
    }, config || global.__SERVER_CONFIG__);
    socket.emit('inventoryData', {
        player: { 
            ...sanitized, 
            inventoryByCategory: getCategorizedInventory(sanitized.inventory || []) 
        }
    });
}


function registerInventoryHandlers(socket, io, state) {
    global.__SERVER_CONFIG__ = state.SERVER_CONFIG; // v620.0: Config global para sanitización en sendInventoryData

    // v263.010: CONSULTA DE EQUIPAMIENTO POR NAVE (sin necesidad de activarla)
    socket.on('getShipEquip', async (shipId) => {
        if (!socket.dbUser) return;
        try {
            const user = getPlayerRAMAdapter(state.players[socket.id]);
            if (!user) return;

            const targetId = parseInt(shipId);
            const key = String(targetId);
            let equip = { w: [], s: [], e: [], x: [] };

            // Si es la nave activa, usar equipped (fuente de verdad)
            if (targetId === user.gameData.currentShipId) {
                equip = user.gameData.equipped || equip;
            } else {
                // Intentar desde equippedByShip (Map o Object)
                if (user.gameData.equippedByShip instanceof Map) {
                    equip = user.gameData.equippedByShip.get(key) || equip;
                } else if (user.gameData.equippedByShip) {
                    equip = user.gameData.equippedByShip[key] || equip;
                }
            }

            // console.log(`[SHIP-EQUIP] ${user.username} consultó nave ${key}: w=${equip.w?.length||0} s=${equip.s?.length||0} e=${equip.e?.length||0}`);
            // v620.0: Ojito de visibilidad — ítems ocultos no se muestran en la bodega de la nave
            const isAdmin = !!(socket && socket.dbUser && socket.dbUser.username && socket.dbUser.username.toLowerCase() === 'caelli94');
            if (!isAdmin) {
                equip = visibilityGuard.sanitizeEquipForClient(equip, state.SERVER_CONFIG);
            }
            socket.emit('shipEquipData', { shipId: targetId, equip });
        } catch (e) { console.error('[SHIP-EQUIP ERROR]', e); }
    });

    // COMPRA DE ÍTEMS
    socket.on('buyItem', async (data) => {
        if (!socket.dbUser) return;
        try {
            const { category, itemId, currency, amount } = data;
            const user = getPlayerRAMAdapter(state.players[socket.id]);
            if (!user) return;

            const p = state.players[socket.id];
            if (p && p.isExtracting) {
                return socket.emit('gameNotification', { msg: 'TIENDA BLOQUEADA: No puedes comprar durante una Raid.', type: 'error' });
            }

            console.log(`[SHOP-DEBUG] Iniciando compra: User=${user.username}, Cat=${category}, Item=${itemId}, Amount=${amount}, Currency=${currency}`);
            console.log(`[SHOP-DEBUG] Fondos actuales: Hubs=${user.gameData.hubs}, Ohcu=${user.gameData.ohcu}`);

            let itemConfig = null;
            const isShip = category === 'ships' || category === 'ship';

            if (category === 'ammo') {
                for (const type in state.SERVER_CONFIG.shopItems.ammo) {
                    const found = state.SERVER_CONFIG.shopItems.ammo[type].find(i => i.id === itemId);
                    if (found) { itemConfig = found; break; }
                }
            } else if (isShip) {
                const targetShipId = parseInt(itemId);
                itemConfig = state.SERVER_CONFIG.shipModels.find(s => s.id === targetShipId);
            } else if (state.SERVER_CONFIG.shopItems[category]) {
                itemConfig = state.SERVER_CONFIG.shopItems[category].find(i => i.id === itemId);
            }

            if (!itemConfig) {
                console.log(`[SHOP-DEBUG] Error: Item ${itemId} no encontrado en config.`);
                return socket.emit('authError', 'ITEM NO ENCONTRADO');
            }

            // v620.0: Ojito de visibilidad — ítems hidden son incomprables incluso por cliente hackeado
            const isAdmin = !!(socket && socket.dbUser && socket.dbUser.username && socket.dbUser.username.toLowerCase() === 'caelli94');
            if (itemConfig.hidden && !isAdmin) {
                return socket.emit('authError', 'ITEM NO ENCONTRADO');
            }

            if (isShip) {
                const targetShipId = parseInt(itemId);
                if (user.gameData.ownedShips.includes(targetShipId)) {
                    return socket.emit('gameNotification', { msg: 'ERROR: Ya posees esta nave.', type: 'error' });
                }
            }

            const price = itemConfig.prices[currency] || 0;
            const totalPrice = category === 'ammo' ? Math.floor((parseInt(amount)/100)*price) : price;
            console.log(`[SHOP-DEBUG] Precio calculado: ${totalPrice} ${currency}`);

            if ((user.gameData[currency] || 0) < totalPrice) {
                console.log(`[SHOP-DEBUG] Error: Fondos insuficientes (${user.gameData[currency]} < ${totalPrice})`);
                return socket.emit('authError', 'FONDOS INSUFICIENTES');
            }

            user.gameData[currency] -= totalPrice;

            if (isShip) {
                const targetShipId = parseInt(itemId);
                user.gameData.ownedShips.push(targetShipId);
                user.markModified('gameData.ownedShips');

                if (!user.gameData.equippedByShip) user.gameData.equippedByShip = {};
                let ebs = user.gameData.equippedByShip;
                
                let hasKey = false;
                if (typeof ebs.get === 'function') {
                    hasKey = ebs.has(String(targetShipId));
                } else {
                    hasKey = ebs[String(targetShipId)];
                }

                if (!hasKey) {
                    if (typeof ebs.set === 'function') {
                        ebs.set(String(targetShipId), { w: [], s: [], e: [], x: [] });
                    } else {
                        ebs[String(targetShipId)] = { w: [], s: [], e: [], x: [] };
                    }
                    user.markModified('gameData.equippedByShip');
                }
                console.log(`[SHOP-DEBUG] Nave comprada y añadida: ${itemConfig.name}`);
            } else if (category !== 'ammo') {
                let type = (itemConfig.type || "utility").toLowerCase();
                const id = itemConfig.id.toLowerCase();
                if (id.startsWith('las') || id.startsWith('w')) type = "weapon";
                else if (id.startsWith('sh') || id.startsWith('s')) type = "shield";
                else if (id.startsWith('en') || id.startsWith('e')) type = "engine";

                const newItem = {
                    id: itemConfig.id,
                    name: itemConfig.name,
                    type: type,
                    base: itemConfig.base || 0,
                    hpMod: itemConfig.hpMod || 0,
                    hpModType: itemConfig.hpModType || 'percent',
                    speedMod: itemConfig.speedMod || 0,
                    speedModType: itemConfig.speedModType || 'percent',
                    shieldMod: itemConfig.shieldMod || 0,
                    shieldModType: itemConfig.shieldModType || 'percent',
                    dmgMod: itemConfig.dmgMod || 0,
                    dmgModType: itemConfig.dmgModType || 'percent',
                    instanceId: Date.now() + Math.random().toString(36).substr(2, 5),
                    rarity: itemConfig.rarity || 0,
                    color: itemConfig.color || "#ffffff",
                    icon: itemConfig.icon || ""
                };

                const remaining = addItemToInventory(user, newItem, state.SERVER_CONFIG, 1);
                if (remaining > 0) {
                    user.gameData[currency] += totalPrice;
                    return socket.emit('gameNotification', { msg: `INVENTARIO LLENO: Desbloquea más slots.`, type: 'error' });
                }
                user.markModified('gameData.inventory');
                console.log(`[SHOP-DEBUG] Item normal añadido al inventario: ${itemConfig.name}`);
            } else {
                let ammoType = "mine";
                if (itemId.startsWith("am_l")) ammoType = "laser";
                else if (itemId.startsWith("am_me")) ammoType = "melee";
                else if (itemId.startsWith("am_m")) ammoType = "missile";
                else if (itemId.startsWith("am_n")) ammoType = "mine";
                else if (itemId.startsWith("am_h")) ammoType = "heal";
                else if (itemId.startsWith("am_s")) ammoType = "siphon";
                else if (itemId.startsWith("am_el")) ammoType = "electron";
                else if (itemId.startsWith("am_e")) ammoType = "emp";

                const tierIndex = parseInt(itemId.slice(-1)) - 1;
                
                if (!user.gameData.ammo) {
                    user.gameData.ammo = { 
                        laser: [0,0,0,0,0,0], 
                        missile: [0,0,0,0,0,0], 
                        mine: [0,0,0,0,0,0],
                        melee: [0,0,0,0,0,0],
                        heal: [0,0,0,0,0,0],
                        siphon: [0,0,0,0,0,0],
                        emp: [0,0,0,0,0,0],
                        electron: [0,0,0,0,0,0]
                    };
                }
                if (!user.gameData.ammo[ammoType]) user.gameData.ammo[ammoType] = [0,0,0,0,0,0];

                const oldAmmo = user.gameData.ammo[ammoType][tierIndex] || 0;
                // v269.90: Mongoose Array Tracking Fix
                const newArr = [...user.gameData.ammo[ammoType]];
                newArr[tierIndex] = oldAmmo + parseInt(amount || 0);
                user.gameData.ammo[ammoType] = newArr;

                console.log(`[SHOP-DEBUG] Munición ${ammoType}[${tierIndex}] actualizada: ${oldAmmo} -> ${newArr[tierIndex]}`);
                user.markModified(`gameData.ammo.${ammoType}`);
                user.markModified('gameData.ammo');
            }

            user.markModified('gameData.hubs');
            user.markModified('gameData.ohcu');
            user.markModified('gameData');
            
            console.log(`[SHOP-DEBUG] Intentando guardar en DB...`);
            await user.save();
            console.log(`[SHOP-DEBUG] ¡Guardado exitoso!`);
            socket.dbUser = user;

            // v269.100: Sincronización crítica RAM <-> DB
            if (p) {
                p.ammo = JSON.parse(JSON.stringify(user.gameData.ammo));
                p.hubs = user.gameData.hubs;
                p.ohcu = user.gameData.ohcu;
                p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));
                console.log(`[SHOP-DEBUG] RAM sincronizada para ${user.username}`);
            }

            sendInventoryData(socket, user);
            console.log(`[SHOP-DEBUG] Evento inventoryData enviado al cliente.`);
        } catch (e) { console.error(e); }
    });

    // EQUIPAR ÍTEM
    socket.on('equipItem', async (raw_data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];
        
        if (p.isProcessingInventory) {
            return socket.emit('gameNotification', { msg: 'Transacción en curso. Espera un momento.', type: 'error' });
        }
        
        if (p.isExtracting) {
            sendInventoryData(socket, socket.dbUser);
            return socket.emit('gameNotification', { msg: 'EQUIPO BLOQUEADO: No puedes modificar tu nave en combate de extracción.', type: 'error' });
        }

        const lock = checkCombatLock(p);
        if (lock.locked) {
            sendInventoryData(socket, socket.dbUser);
            return socket.emit('gameNotification', { 
                msg: `ERROR: Sistemas calientes. Espera ${lock.remaining}s para equipar.`, 
                type: 'error' 
            });
        }

        try {
            p.isProcessingInventory = true;
            const data = (typeof raw_data === 'object' && raw_data.instanceId) ? raw_data : raw_data;
            const instanceId = data.instanceId;
            const shipId = (typeof data.shipId === 'object') ? (data.shipId.id || data.shipId.shipId) : data.shipId;            const user = getPlayerRAMAdapter(p);
            if (!user) return;
            const idx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
            if (idx === -1) {
                sendInventoryData(socket, user);
                return;
            }

            const item = user.gameData.inventory[idx];
            const id = (item.id || "").toLowerCase();
            const itemType = (item.type || "").toLowerCase();

            const isResource = id.startsWith('mat_') || itemType === 'resource';
            const isRecipe = id.startsWith('recipe_') || itemType === 'recipe';
            if (isResource || isRecipe) {
                sendInventoryData(socket, user);
                return socket.emit('authError', 'LOS MATERIALES Y RECETAS NO PUEDEN EQUIPARSE');
            }

            let slot = 'x';
            if (id.startsWith('las') || id.startsWith('w')) slot = 'w';
            else if (id.startsWith('sh') || id.startsWith('s')) slot = 's';
            else if (id.startsWith('en') || id.startsWith('e')) slot = 'e';

            const targetId = shipId ? parseInt(shipId) : user.gameData.currentShipId;
            const shipKey = targetId.toString();
            // v308.1: Clonamos shipEquip para evitar mutación directa de Mongoose y asegurar nueva referencia
            let shipEquip = JSON.parse(JSON.stringify(getShipEquip(user, shipKey)));

            const shipModel = state.SERVER_CONFIG.shipModels.find(s => s.id === targetId);
            const max = (shipModel && shipModel.slots) ? (shipModel.slots[slot] || 1) : 1;

            if (shipEquip[slot].length >= max) {
                sendInventoryData(socket, user);
                return socket.emit('authError', `BODEGA LLENA: No hay más espacio para ${slot.toUpperCase()}`);
            }

            // v400.0: Requisitos de equipamiento (nivel, misiones completadas, etc.)
            const masterItem = getMasterItemConfigFull(item.id, state.SERVER_CONFIG);
            // v620.0: Ojito de visibilidad — ítems hidden no pueden equiparse ni armarse
            const isAdmin = !!(socket && socket.dbUser && socket.dbUser.username && socket.dbUser.username.toLowerCase() === 'caelli94');
            if (masterItem && masterItem.hidden && !isAdmin) {
                sendInventoryData(socket, user);
                return socket.emit('gameNotification', { msg: 'EQUIPAMIENTO BLOQUEADO: Ítem no disponible.', type: 'error' });
            }
            if (masterItem && masterItem.requirements && masterItem.requirements.length > 0) {
                const reqCheck = checkRequirements(p, masterItem.requirements, state.SERVER_CONFIG);
                if (!reqCheck.ok) {
                    sendInventoryData(socket, user);
                    return socket.emit('gameNotification', { msg: `EQUIPAMIENTO BLOQUEADO: ${reqCheck.msg}`, type: 'error' });
                }
            }

            user.gameData.inventory.splice(idx, 1);
            shipEquip[slot].push(item);
            
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.set(shipKey, shipEquip);
            else user.gameData.equippedByShip[shipKey] = shipEquip;

            if (targetId === user.gameData.currentShipId) user.gameData.equipped = shipEquip;

            user.markModified('gameData.equippedByShip'); // v308.2: Marcar el mapa explícitamente como modificado
            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            // Sincronizar RAM (p) para persistencia en desconexión (F5)
            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));
            p.equipped = JSON.parse(JSON.stringify(user.gameData.equipped));

            // v266.135: Recalcular Stats en RAM e informar al cliente solo si es la nave activa
            if (targetId === user.gameData.currentShipId) {
                p.equipped = shipEquip;
                calculateFinalStats(p, state.SERVER_CONFIG);
                io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                    id: socket.id, 
                    hp: p.hp, shield: p.shield, 
                    maxHp: p.maxHp, maxShield: p.maxShield 
                });
            }

            sendInventoryData(socket, user);
        } catch (e) { console.error(e); }
        finally {
            p.isProcessingInventory = false;
        }
    });

    // CAMBIAR NAVE
    socket.on('switchShip', async (raw_shipId) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];
        
        const lock = checkCombatLock(p);
        if (lock.locked) {
            return socket.emit('gameNotification', { 
                msg: `ERROR: Sistemas de armas calientes. Espera ${lock.remaining}s fuera de combate para cambiar.`, 
                type: 'error' 
            });
        }

        try {
            let shipId = raw_shipId;
            if (typeof raw_shipId === 'object' && raw_shipId !== null) {
                shipId = raw_shipId.shipId || raw_shipId.id || 1;
            }
            const user = getPlayerRAMAdapter(p);
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
                p.equipped = user.gameData.equipped;

                // v266.135: Usar el calculador centralizado
                calculateFinalStats(p, state.SERVER_CONFIG);
                p.hp = p.maxHp; p.shield = p.maxShield;

                io.to(`zone_${p.zone}`).emit('playerStatSync', { id: socket.id, hp: p.hp, shield: p.shield, maxHp: p.maxHp, maxShield: p.maxShield });
                
                // v315.0: Emitir el payload completo de presentación a la zona para evitar desincronías y el bug de UNKNOWN
                const shipUpdatePayload = {
                    id:             socket.id,
                    type:           p.type,
                    currentShipId:  p.currentShipId,
                    pvpEnabled:     !!p.pvpEnabled,
                    user:           p.user || 'Unknown',
                    username:       p.user || 'Unknown',
                    x:              Math.round(p.x),
                    y:              Math.round(p.y),
                    rotation:       Math.round((p.rotation || 0) * 100) / 100,
                    hp:             Math.ceil(p.hp || 0),
                    shield:         Math.ceil(p.shield || 0),
                    sh:             Math.ceil(p.shield || 0),
                    maxHp:          p.maxHp || 0,
                    maxShield:      p.maxShield || 0,
                    zone:           p.zone,
                    clanTag:        p.clanTag || '',
                    isInvisible:    !!p.isInvisible,
                    isInvulnerable: !!p.isInvulnerable,
                    isDead:         !!p.isDead,
                    spheres:        p.spheres || []
                };
                io.to(`zone_${p.zone}`).emit('playerUpdated', shipUpdatePayload);
            }

            sendInventoryData(socket, user);
        } catch (e) { console.error(e); }
    });

    socket.on('unequipItem', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];
        
        if (p.isProcessingInventory) {
            return socket.emit('gameNotification', { msg: 'Transacción en curso. Espera un momento.', type: 'error' });
        }
        
        if (p.isExtracting) {
            sendInventoryData(socket, socket.dbUser);
            return socket.emit('gameNotification', { msg: 'BODEGA BLOQUEADA: Extrae primero para modificar tu equipo.', type: 'error' });
        }

        const lock = checkCombatLock(p);
        if (lock.locked) {
            sendInventoryData(socket, socket.dbUser);
            return socket.emit('gameNotification', { 
                msg: `ERROR: Sistemas calientes. Espera ${lock.remaining}s para desequipar.`, 
                type: 'error' 
            });
        }

        try {
            p.isProcessingInventory = true;
            const user = getPlayerRAMAdapter(p);
            if (!user) return;
            const targetId = data.shipId ? parseInt(data.shipId) : user.gameData.currentShipId;
            const shipKey = targetId.toString();
            // v308.1: Clonamos shipEquip para evitar mutación directa de Mongoose y asegurar nueva referencia
            let shipEquip = JSON.parse(JSON.stringify(getShipEquip(user, shipKey)));
            
            const idx = shipEquip[data.category].findIndex(it => it.instanceId === data.instanceId);
            if (idx === -1) {
                sendInventoryData(socket, user);
                return;
            }
            
            const item = shipEquip[data.category].splice(idx, 1)[0];
            user.gameData.inventory.push(item);
            
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.set(shipKey, shipEquip);
            else user.gameData.equippedByShip[shipKey] = shipEquip;
            
            if (targetId === user.gameData.currentShipId) user.gameData.equipped = shipEquip;
            
            user.markModified('gameData.equippedByShip'); // v308.2: Marcar el mapa explícitamente como modificado
            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            // Sincronizar RAM (p) para persistencia en desconexión (F5)
            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));
            p.equipped = JSON.parse(JSON.stringify(user.gameData.equipped));
            
            // v266.135: Recalcular Stats tras desequipar solo si es la nave activa
            if (targetId === user.gameData.currentShipId) {
                p.equipped = shipEquip;
                calculateFinalStats(p, state.SERVER_CONFIG);
                io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                    id: socket.id, 
                    hp: p.hp, shield: p.shield, 
                    maxHp: p.maxHp, maxShield: p.maxShield 
                });
            }

            sendInventoryData(socket, user);
        } catch (e) { console.error(e); }
        finally {
            p.isProcessingInventory = false;
        }
    });

    socket.on('sellItem', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];

        if (p.isProcessingInventory) {
            return socket.emit('gameNotification', { msg: 'Transacción en curso. Espera un momento.', type: 'error' });
        }

        // v262.720: Candado de Combate también para Venta
        const lock = checkCombatLock(p);
        if (lock.locked) {
            return socket.emit('gameNotification', { 
                msg: `ERROR: Sistemas calientes. No puedes vender mientras estás en combate.`, 
                type: 'error' 
            });
        }

        try {
            p.isProcessingInventory = true;
            const { instanceId, quantity } = data;
            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            const idx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
            if (idx === -1) return;

            const item = user.gameData.inventory[idx];
            const amount = parseInt(item.amount) || 1;
            const quantityToSell = quantity ? Math.min(parseInt(quantity) || 1, amount) : amount;
            
            let originalPrice = 0;
            const configItem = getMasterItemConfig(item.id, state.SERVER_CONFIG);
            if (configItem && configItem.prices && configItem.prices.hubs) {
                originalPrice = configItem.prices.hubs;
            }

            const refund = Math.floor(originalPrice / 2) * quantityToSell;
            
            if (quantityToSell < amount) {
                item.amount = amount - quantityToSell;
            } else {
                user.gameData.inventory.splice(idx, 1);
            }
            user.gameData.hubs += refund;

            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            // Sincronizar RAM (p) para persistencia en desconexión (F5)
            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));
            p.hubs = user.gameData.hubs;

            sendInventoryData(socket, user);

            socket.emit('gameNotification', { msg: `VENDIDO POR ${refund} HUBS`, type: 'success' });
        } catch (e) { console.error(e); }
        finally {
            p.isProcessingInventory = false;
        }
    });

    socket.on('splitStack', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];
        
        if (p.isProcessingInventory) {
            return socket.emit('gameNotification', { msg: 'Transacción en curso. Espera un momento.', type: 'error' });
        }

        const lock = checkCombatLock(p);
        if (lock.locked) {
            return socket.emit('gameNotification', { msg: 'Sistemas calientes. No puedes separar ítems en combate.', type: 'error' });
        }

        try {
            p.isProcessingInventory = true;
            const { instanceId, quantity } = data;
            const qtyToSplit = parseInt(quantity) || 1;
            if (qtyToSplit <= 0) return;

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            const idx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
            if (idx === -1) return;

            const item = user.gameData.inventory[idx];
            const amount = parseInt(item.amount) || 1;

            if (qtyToSplit >= amount) {
                return socket.emit('gameNotification', { msg: 'Cantidad inválida para separar.', type: 'error' });
            }

            const maxSlots = user.gameData.inventoryMaxSlots || state.SERVER_CONFIG.inventoryConfig?.defaultMaxSlots || 30;
            if (user.gameData.inventory.length >= maxSlots) {
                return socket.emit('gameNotification', { msg: 'INVENTARIO LLENO: No hay espacio para crear un nuevo stack.', type: 'error' });
            }

            item.amount = amount - qtyToSplit;

            const newItem = {
                ...JSON.parse(JSON.stringify(item)),
                instanceId: Date.now() + Math.random().toString(36).substr(2, 5),
                amount: qtyToSplit
            };
            user.gameData.inventory.push(newItem);

            user.markModified('gameData.inventory');
            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));

            sendInventoryData(socket, user);
            socket.emit('gameNotification', { msg: 'Ítem separado con éxito', type: 'success' });
        } catch (e) {
            console.error('[SPLIT-STACK-ERROR]', e);
        } finally {
            p.isProcessingInventory = false;
        }
    });

    // v262.730: GESTIÓN DE ESFERAS AUTORITATIVA + BLOQUEO DE COMBATE
    socket.on('equipSphere', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];

        const lock = checkCombatLock(p);
        if (lock.locked) {
            sendInventoryData(socket, socket.dbUser);
            return socket.emit('gameNotification', { 
                msg: `ERROR: Esferas calientes. Espera ${lock.remaining}s para cambiar habilidades.`, 
                type: 'error' 
            });
        }

        try {
            const { sphereId, skill } = data;
            if (sphereId < 0 || sphereId > 3) return;

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            if (!user.gameData.spheres) user.gameData.spheres = [];
            
            // v400.0: Requisitos de equipamiento de habilidades (nivel, misiones completadas, etc.)
            if (skill && skill.skill_name) {
                const skillMaster = getSkillMasterConfig(skill.skill_name, state.SERVER_CONFIG);
                if (skillMaster && skillMaster.config && skillMaster.config.requirements && skillMaster.config.requirements.length > 0) {
                    const reqCheck = checkRequirements(p, skillMaster.config.requirements, state.SERVER_CONFIG);
                    if (!reqCheck.ok) {
                        sendInventoryData(socket, user);
                        return socket.emit('gameNotification', { msg: `HABILIDAD BLOQUEADA: ${reqCheck.msg}`, type: 'error' });
                    }
                }
            }

            // v680.0: Desbloqueo de slots de esferas por requisitos (nivel, misiones, etc.)
            // El servidor es la fuente autoritativa: nadie puede equipar en un slot bloqueado.
            const pilotCfg = state.SERVER_CONFIG?.pilotConfig || {};
            const slotReqs = (Array.isArray(pilotCfg.sphereSlotRequirements) && pilotCfg.sphereSlotRequirements[sphereId])
                ? (pilotCfg.sphereSlotRequirements[sphereId].requirements || [])
                : [];
            if (slotReqs.length > 0) {
                const slotCheck = checkRequirements(p, slotReqs, state.SERVER_CONFIG);
                if (!slotCheck.ok) {
                    sendInventoryData(socket, user);
                    return socket.emit('gameNotification', { msg: `ESFERA BLOQUEADA: ${slotCheck.msg}`, type: 'error' });
                }
            }

            // v262.735: Blindaje de datos. Si el slot no existe, lo creamos.
            while (user.gameData.spheres.length <= sphereId) {
                user.gameData.spheres.push({ name: `Slot ${user.gameData.spheres.length + 1}`, type: "any", color: "#ffffff", equipped: null });
            }

            user.gameData.spheres[sphereId].equipped = skill;
            user.markModified('gameData.spheres');
            await user.save();

            socket.dbUser = user;
            p.spheres = JSON.parse(JSON.stringify(user.gameData.spheres)); // Sincronizar RAM (Safe Copy)

            sendInventoryData(socket, user);
            console.log(`[SPHERE] ${user.username} equipó ${skill.skill_name} en slot ${sphereId}`);
        } catch (e) { console.error("[SPHERE-ERROR]", e); }
    });

    socket.on('unequipSphere', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];

        const lock = checkCombatLock(p);
        if (lock.locked) {
            sendInventoryData(socket, socket.dbUser);
            return socket.emit('gameNotification', { 
                msg: `ERROR: Esferas bloqueadas en combate.`, 
                type: 'error' 
            });
        }

        try {
            const { sphereId } = data;
            const user = getPlayerRAMAdapter(p);
            if (!user || !user.gameData.spheres || !user.gameData.spheres[sphereId]) return;

            user.gameData.spheres[sphereId].equipped = null;
            user.markModified('gameData.spheres');
            await user.save();

            socket.dbUser = user;
            p.spheres = JSON.parse(JSON.stringify(user.gameData.spheres));

            sendInventoryData(socket, user);
        } catch (e) { console.error("[SPHERE-UNEQUIP-ERROR]", e); }
    });

    // HANDLER DE CRAFTEO AUTORITATIVO
    socket.on('craftItem', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];

        if (p.isExtracting) {
            return socket.emit('gameNotification', { msg: 'BODEGA BLOQUEADA: No puedes craftear durante una Raid de extracción.', type: 'error' });
        }
        const lock = checkCombatLock(p);
        if (lock.locked) {
            return socket.emit('gameNotification', { 
                msg: `ERROR: Sistemas calientes. Espera ${lock.remaining}s fuera de combate para craftear.`, 
                type: 'error' 
            });
        }

        try {
            const { recipeId } = data;
            const recipes = state.SERVER_CONFIG.craftingRecipes || [];
            const recipe = recipes.find(r => r.id === recipeId);
            
            if (!recipe) {
                return socket.emit('gameNotification', { msg: 'Error: Receta no encontrada.', type: 'error' });
            }

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            const hubsCost = recipe.costHubs || 0;
            const ohcuCost = recipe.costOhcu || 0;

            if ((user.gameData.hubs || 0) < hubsCost) {
                return socket.emit('gameNotification', { msg: 'FONDOS INSUFICIENTES: Faltan Hubs.', type: 'error' });
            }
            if ((user.gameData.ohcu || 0) < ohcuCost) {
                return socket.emit('gameNotification', { msg: 'FONDOS INSUFICIENTES: Faltan OHCU.', type: 'error' });
            }

            const inventory = user.gameData.inventory || [];
            const materialsCount = {};
            inventory.forEach(it => {
                const id = it.id;
                materialsCount[id] = (materialsCount[id] || 0) + (parseInt(it.amount) || 1);
            });

            const ingredients = recipe.ingredients || [];
            for (const ing of ingredients) {
                const ownedAmount = materialsCount[ing.itemId] || 0;
                if (ownedAmount < ing.amount) {
                    return socket.emit('gameNotification', { msg: `MATERIALES INSUFICIENTES: Requiere más cantidad de un ingrediente.`, type: 'error' });
                }
            }

            const resultCategory = recipe.resultCategory.toLowerCase();
            const resultItemId = recipe.resultItemId;
            const isShip = resultCategory === 'ships' || resultCategory === 'ship';
            const isAmmo = resultCategory === 'ammo';
            
            let craftedItemConfig = null;
            if (!isShip && !isAmmo) {
                const allItems = [
                    ...(state.SERVER_CONFIG.shopItems.weapons || []),
                    ...(state.SERVER_CONFIG.shopItems.shields || []),
                    ...(state.SERVER_CONFIG.shopItems.engines || []),
                    ...(state.SERVER_CONFIG.shopItems.extra || []),
                    ...(state.SERVER_CONFIG.shopItems.spheres || []),
                    ...(state.SERVER_CONFIG.shopItems.resources || [])
                ];
                craftedItemConfig = allItems.find(i => i.id === resultItemId);
                if (!craftedItemConfig) {
                    return socket.emit('gameNotification', { msg: 'ERROR: Ítem resultante no configurado en el servidor.', type: 'error' });
                }
                // v620.0: Ojito de visibilidad — ítems hidden no se pueden fabricar
                if (craftedItemConfig.hidden) {
                    return socket.emit('gameNotification', { msg: 'ERROR: Receta no disponible.', type: 'error' });
                }
                
                let type = (craftedItemConfig.type || "utility").toLowerCase();
                const id = craftedItemConfig.id.toLowerCase();
                if (id.startsWith('las') || id.startsWith('w')) type = "weapon";
                else if (id.startsWith('sh') || id.startsWith('s')) type = "shield";
                else if (id.startsWith('en') || id.startsWith('e')) type = "engine";

                const newItem = {
                    id: craftedItemConfig.id,
                    name: craftedItemConfig.name,
                    type: type,
                    base: craftedItemConfig.base || 0,
                    instanceId: "",
                    rarity: craftedItemConfig.rarity || 0,
                    color: craftedItemConfig.color || "#ffffff",
                    icon: craftedItemConfig.icon || ""
                };

                // Dry run check
                const tempUser = { gameData: { inventory: JSON.parse(JSON.stringify(user.gameData.inventory)), inventoryMaxSlots: user.gameData.inventoryMaxSlots } };
                ingredients.forEach(ing => {
                    let toRemove = ing.amount;
                    for (let i = tempUser.gameData.inventory.length - 1; i >= 0; i--) {
                        if (tempUser.gameData.inventory[i].id === ing.itemId) {
                            const currentAmount = parseInt(tempUser.gameData.inventory[i].amount) || 1;
                            if (currentAmount <= toRemove) {
                                tempUser.gameData.inventory.splice(i, 1);
                                toRemove -= currentAmount;
                            } else {
                                tempUser.gameData.inventory[i].amount = currentAmount - toRemove;
                                toRemove = 0;
                            }
                            if (toRemove === 0) break;
                        }
                    }
                });

                const remaining = addItemToInventory(tempUser, newItem, state.SERVER_CONFIG, recipe.resultAmount || 1);
                if (remaining > 0) {
                    return socket.emit('gameNotification', { msg: `INVENTARIO LLENO: Libera espacio para recibir el ítem fabricado.`, type: 'error' });
                }
            }

            // Descontar dinero
            user.gameData.hubs = (user.gameData.hubs || 0) - hubsCost;
            user.gameData.ohcu = (user.gameData.ohcu || 0) - ohcuCost;

            // Consumir ingredientes
            ingredients.forEach(ing => {
                let toRemove = ing.amount;
                for (let i = user.gameData.inventory.length - 1; i >= 0; i--) {
                    if (user.gameData.inventory[i].id === ing.itemId) {
                        const currentAmount = parseInt(user.gameData.inventory[i].amount) || 1;
                        if (currentAmount <= toRemove) {
                            user.gameData.inventory.splice(i, 1);
                            toRemove -= currentAmount;
                        } else {
                            user.gameData.inventory[i].amount = currentAmount - toRemove;
                            toRemove = 0;
                        }
                        if (toRemove === 0) break;
                    }
                }
            });

            const resultAmount = recipe.resultAmount || 1;
            
            if (isShip) {
                const shipId = parseInt(resultItemId);
                // v620.0: Ojito de visibilidad — naves hidden no se pueden fabricar
                const shipMaster = (state.SERVER_CONFIG.shipModels || []).find(s => String(s.id) === String(shipId));
                if (shipMaster && shipMaster.hidden) {
                    return socket.emit('gameNotification', { msg: 'ERROR: Receta no disponible.', type: 'error' });
                }
                if (!user.gameData.ownedShips.includes(shipId)) {
                    user.gameData.ownedShips.push(shipId);
                    user.markModified('gameData.ownedShips');
                    if (!user.gameData.equippedByShip) user.gameData.equippedByShip = {};
                    let ebs = user.gameData.equippedByShip;
                    let hasKey = (ebs instanceof Map) ? ebs.has(String(shipId)) : ebs[String(shipId)];
                    if (!hasKey) {
                        if (ebs instanceof Map) ebs.set(String(shipId), { w: [], s: [], e: [], x: [] });
                        else ebs[String(shipId)] = { w: [], s: [], e: [], x: [] };
                        user.markModified('gameData.equippedByShip');
                    }
                } else {
                    return socket.emit('gameNotification', { msg: 'ERROR: Ya posees esta nave.', type: 'error' });
                }
            } else if (isAmmo) {
                // v620.0: Ojito de visibilidad — munición hidden no se puede fabricar
                if (visibilityGuard.isItemConfigHidden(state.SERVER_CONFIG, 'ammo', resultItemId)) {
                    return socket.emit('gameNotification', { msg: 'ERROR: Receta no disponible.', type: 'error' });
                }
                let ammoType = "mine";
                if (resultItemId.startsWith("am_l")) ammoType = "laser";
                else if (resultItemId.startsWith("am_me")) ammoType = "melee";
                else if (resultItemId.startsWith("am_m")) ammoType = "missile";
                else if (resultItemId.startsWith("am_n")) ammoType = "mine";
                else if (resultItemId.startsWith("am_h")) ammoType = "heal";
                else if (resultItemId.startsWith("am_s")) ammoType = "siphon";
                else if (resultItemId.startsWith("am_e")) ammoType = "emp";

                const tierIndex = parseInt(resultItemId.slice(-1)) - 1;
                
                if (!user.gameData.ammo) {
                    user.gameData.ammo = { 
                        laser: [0,0,0,0,0,0], 
                        missile: [0,0,0,0,0,0], 
                        mine: [0,0,0,0,0,0],
                        melee: [0,0,0,0,0,0],
                        heal: [0,0,0,0,0,0],
                        siphon: [0,0,0,0,0,0],
                        emp: [0,0,0,0,0,0]
                    };
                }
                if (!user.gameData.ammo[ammoType]) user.gameData.ammo[ammoType] = [0,0,0,0,0,0];

                const oldAmmo = user.gameData.ammo[ammoType][tierIndex] || 0;
                const newArr = [...user.gameData.ammo[ammoType]];
                newArr[tierIndex] = oldAmmo + resultAmount;
                user.gameData.ammo[ammoType] = newArr;

                user.markModified(`gameData.ammo.${ammoType}`);
                user.markModified('gameData.ammo');
            } else {
                let type = (craftedItemConfig.type || "utility").toLowerCase();
                const id = craftedItemConfig.id.toLowerCase();
                if (id.startsWith('las') || id.startsWith('w')) type = "weapon";
                else if (id.startsWith('sh') || id.startsWith('s')) type = "shield";
                else if (id.startsWith('en') || id.startsWith('e')) type = "engine";

                const newItem = {
                    id: craftedItemConfig.id,
                    name: craftedItemConfig.name,
                    type: type,
                    base: craftedItemConfig.base || 0,
                    instanceId: Date.now() + Math.random().toString(36).substr(2, 5),
                    rarity: craftedItemConfig.rarity || 0,
                    color: craftedItemConfig.color || "#ffffff",
                    icon: craftedItemConfig.icon || ""
                };

                addItemToInventory(user, newItem, state.SERVER_CONFIG, resultAmount);
            }

            user.markModified('gameData.inventory');
            user.markModified('gameData.hubs');
            user.markModified('gameData.ohcu');
            user.markModified('gameData');

            await user.save();
            socket.dbUser = user;

            p.ammo = JSON.parse(JSON.stringify(user.gameData.ammo));
            p.hubs = user.gameData.hubs;
            p.ohcu = user.gameData.ohcu;
            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));

            sendInventoryData(socket, user);

            socket.emit('gameNotification', { msg: `¡CRAFTEO EXITOSO: ${recipe.name}!`, type: 'success' });
        } catch (e) {
            console.error('[CRAFTING-ERROR]', e);
            socket.emit('gameNotification', { msg: 'Error interno al procesar el crafteo.', type: 'error' });
        }
    });
}

module.exports = { registerInventoryHandlers, getCategorizedInventory, checkCombatLock, getMasterItemConfig, addItemToInventory, sendInventoryData };
