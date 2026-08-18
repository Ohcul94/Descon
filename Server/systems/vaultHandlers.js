const User = require('../models/User');
const { getPlayerRAMAdapter } = require('../utils/ramAdapter'); // v6.02
const visibilityGuard = require('./visibilityGuard'); // v620.0: Ojito de visibilidad de ítems

function parsePrice(priceConfig) {
    if (priceConfig && typeof priceConfig === 'object') {
        return {
            hubs: parseInt(priceConfig.hubs) || 0,
            ohcu: parseInt(priceConfig.ohcu) || 0
        };
    }
    const val = parseInt(priceConfig) || 0;
    return { hubs: val, ohcu: 0 };
}

function registerVaultHandlers(socket, io, state) {
    // 1. OBTENER DATOS DEL BAÚL
    socket.on('getVaultData', async () => {
        if (!socket.dbUser) return;
        try {
            const p = state.players[socket.id];
            if (!p) return;

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            // Seguridad: El baúl solo está accesible físicamente en el Lobby (Zona 1)
            if (p.zone !== 1) {
                return socket.emit('gameNotification', { msg: 'ACCESO RESTRINGIDO: El baúl solo está disponible en el Lobby.', type: 'error' });
            }

            // Inicializar campos si no existen
            if (!user.gameData.vaultItems) user.gameData.vaultItems = [];
            if (user.gameData.vaultUnlockedTabs === undefined || user.gameData.vaultUnlockedTabs === null) {
                user.gameData.vaultUnlockedTabs = state.SERVER_CONFIG.vaultConfig?.defaultTabs || 1;
            }
            if (user.gameData.inventoryMaxSlots === undefined || user.gameData.inventoryMaxSlots === null) {
                user.gameData.inventoryMaxSlots = state.SERVER_CONFIG.inventoryConfig?.defaultMaxSlots || 30;
            }
 
            // v620.0: Ojito de visibilidad — ítems hidden no se muestran en el baúl (excepto para admins)
            const isAdmin = !!(socket && socket.dbUser && socket.dbUser.username && socket.dbUser.username.toLowerCase() === 'caelli94');
            const vaultItemsFiltered = Array.isArray(user.gameData.vaultItems)
                ? user.gameData.vaultItems.filter(it => {
                    if (!it || it.id === undefined || it.id === null) return true;
                    if (isAdmin) return true;
                    return !visibilityGuard.isItemConfigHidden(state.SERVER_CONFIG, 'weapons', it.id)
                        && !visibilityGuard.isItemConfigHidden(state.SERVER_CONFIG, 'shields', it.id)
                        && !visibilityGuard.isItemConfigHidden(state.SERVER_CONFIG, 'engines', it.id)
                        && !visibilityGuard.isItemConfigHidden(state.SERVER_CONFIG, 'extra', it.id)
                        && !visibilityGuard.isItemConfigHidden(state.SERVER_CONFIG, 'ammo', it.id);
                  })
                : user.gameData.vaultItems;

            socket.emit('vaultData', {
                items: vaultItemsFiltered,
                unlockedTabs: user.gameData.vaultUnlockedTabs,
                inventoryMaxSlots: user.gameData.inventoryMaxSlots,
                vaultConfig: state.SERVER_CONFIG.vaultConfig || { defaultTabs: 1, slotsPerTab: 30, unlockPrices: [0, 5000, 15000, 45000, 100000] },
                inventoryConfig: state.SERVER_CONFIG.inventoryConfig || { defaultMaxSlots: 30, unlockSlotPrice: 1000 }
            });
        } catch (e) {
            console.error('[VAULT ERROR] getVaultData:', e);
        }
    });

    // 2. GUARDAR ÍTEM EN EL BAÚL
    socket.on('storeVaultItem', async (data) => {
        if (!socket.dbUser || !data) return;
        if (socket.isProcessingVaultTransaction) return;
        socket.isProcessingVaultTransaction = true;
        try {
            const { instanceId, tab } = data;
            const targetTab = parseInt(tab);
            if (isNaN(targetTab) || targetTab < 0) return;

            const p = state.players[socket.id];
            if (!p) return;

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            if (p.zone !== 1) {
                return socket.emit('gameNotification', { msg: 'ACCESO RESTRINGIDO: El baúl solo está disponible en el Lobby.', type: 'error' });
            }

            // Validar que la pestaña esté desbloqueada
            const unlockedTabs = user.gameData.vaultUnlockedTabs || 1;
            if (targetTab >= unlockedTabs) {
                return socket.emit('gameNotification', { msg: 'ERROR: Esta pestaña está bloqueada.', type: 'error' });
            }

            // Validar espacio en la pestaña
            const vaultConfig = state.SERVER_CONFIG.vaultConfig || { slotsPerTab: 30 };
            const slotsPerTab = vaultConfig.slotsPerTab || 30;
            const itemsInTab = (user.gameData.vaultItems || []).filter(it => it.tab === targetTab).length;
            if (itemsInTab >= slotsPerTab) {
                return socket.emit('gameNotification', { msg: `PESTAÑA LLENA: No puedes guardar más de ${slotsPerTab} ítems en esta pestaña.`, type: 'error' });
            }

            // Buscar en el inventario del jugador
            const invIdx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
            if (invIdx === -1) {
                return socket.emit('gameNotification', { msg: 'ERROR: El ítem no está en tu inventario.', type: 'error' });
            }

            const item = user.gameData.inventory[invIdx];
            
            // Retirar de inventario, asignar tab, e insertar en el baúl
            user.gameData.inventory.splice(invIdx, 1);
            item.tab = targetTab;
            if (!user.gameData.vaultItems) user.gameData.vaultItems = [];
            user.gameData.vaultItems.push(item);

            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            // Sincronizar estado en memoria RAM
            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));

            // Sincronizar clientes
            const { getCategorizedInventory } = require('./inventoryHandlers');
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });

            socket.emit('vaultUpdated', {
                items: user.gameData.vaultItems,
                unlockedTabs: user.gameData.vaultUnlockedTabs,
                inventoryMaxSlots: user.gameData.inventoryMaxSlots || state.SERVER_CONFIG.inventoryConfig?.defaultMaxSlots || 30
            });

            socket.emit('gameNotification', { msg: `ÍTEM GUARDADO EN PESTAÑA ${targetTab + 1}`, type: 'success' });
        } catch (e) {
            console.error('[VAULT ERROR] storeVaultItem:', e);
        } finally {
            socket.isProcessingVaultTransaction = false;
        }
    });

    // 3. RETIRAR ÍTEM DEL BAÚL
    socket.on('withdrawVaultItem', async (data) => {
        if (!socket.dbUser || !data) return;
        if (socket.isProcessingVaultTransaction) return;
        socket.isProcessingVaultTransaction = true;
        try {
            const { instanceId } = data;
            const p = state.players[socket.id];
            if (!p) return;

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            if (p.zone !== 1) {
                return socket.emit('gameNotification', { msg: 'ACCESO RESTRINGIDO: El baúl solo está disponible en el Lobby.', type: 'error' });
            }

            // Buscar en el baúl
            const vaultItems = user.gameData.vaultItems || [];
            const vaultIdx = vaultItems.findIndex(it => it.instanceId === instanceId);
            if (vaultIdx === -1) {
                return socket.emit('gameNotification', { msg: 'ERROR: El ítem no se encuentra en el baúl.', type: 'error' });
            }

            // Validar espacio de inventario
            const maxSlots = user.gameData.inventoryMaxSlots || state.SERVER_CONFIG.inventoryConfig?.defaultMaxSlots || 30;
            if (user.gameData.inventory.length >= maxSlots) {
                return socket.emit('gameNotification', { msg: `INVENTARIO LLENO: Desbloquea más de ${maxSlots} slots para retirar este ítem.`, type: 'error' });
            }
 
            const item = vaultItems[vaultIdx];

            // Retirar del baúl y regresar al inventario (limpiando propiedad tab)
            user.gameData.vaultItems.splice(vaultIdx, 1);
            delete item.tab;
            user.gameData.inventory.push(item);

            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            // Sincronizar estado en memoria RAM
            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));

            // Sincronizar clientes
            const { getCategorizedInventory } = require('./inventoryHandlers');
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });

            socket.emit('vaultUpdated', {
                items: user.gameData.vaultItems,
                unlockedTabs: user.gameData.vaultUnlockedTabs,
                inventoryMaxSlots: user.gameData.inventoryMaxSlots || state.SERVER_CONFIG.inventoryConfig?.defaultMaxSlots || 30
            });

            socket.emit('gameNotification', { msg: 'ÍTEM RETIRADO AL INVENTARIO', type: 'success' });
        } catch (e) {
            console.error('[VAULT ERROR] withdrawVaultItem:', e);
        } finally {
            socket.isProcessingVaultTransaction = false;
        }
    });

    // 4. DESBLOQUEAR PESTAÑA DEL BAÚL
    socket.on('unlockVaultTab', async () => {
        if (!socket.dbUser) return;
        if (socket.isProcessingVaultTransaction) return;
        socket.isProcessingVaultTransaction = true;
        try {
            const p = state.players[socket.id];
            if (!p) return;

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            if (p.zone !== 1) {
                return socket.emit('gameNotification', { msg: 'ACCESO RESTRINGIDO: El baúl solo está disponible en el Lobby.', type: 'error' });
            }

            if (user.gameData.vaultUnlockedTabs === undefined || user.gameData.vaultUnlockedTabs === null) user.gameData.vaultUnlockedTabs = 1;
            const nextTabIdx = user.gameData.vaultUnlockedTabs;

            const vaultConfig = state.SERVER_CONFIG.vaultConfig || { unlockPrices: [0, 5000, 15000, 45000, 100000] };
            const prices = vaultConfig.unlockPrices || [0, 5000, 15000, 45000, 100000];

            if (nextTabIdx >= prices.length) {
                return socket.emit('gameNotification', { msg: 'LÍMITE ALCANZADO: Has desbloqueado el máximo de pestañas posibles.', type: 'error' });
            }

            const rawPrice = prices[nextTabIdx];
            const price = parsePrice(rawPrice);

            if (price.hubs === 0 && price.ohcu === 0) {
                return socket.emit('gameNotification', { msg: 'BLOQUEADO: Esta pestaña debe adquirirse de otra forma.', type: 'error' });
            }

            if (price.hubs > 0 && user.gameData.hubs < price.hubs) {
                return socket.emit('gameNotification', { msg: `FONDOS INSUFICIENTES: Necesitas ${price.hubs} Hubs para desbloquear esta pestaña.`, type: 'error' });
            }
            if (price.ohcu > 0 && user.gameData.ohcu < price.ohcu) {
                return socket.emit('gameNotification', { msg: `FONDOS INSUFICIENTES: Necesitas ${price.ohcu} Ohcu para desbloquear esta pestaña.`, type: 'error' });
            }

            // Debitar e incrementar pestañas
            if (price.hubs > 0) user.gameData.hubs -= price.hubs;
            if (price.ohcu > 0) user.gameData.ohcu -= price.ohcu;
            user.gameData.vaultUnlockedTabs += 1;

            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            // Sincronizar estado en memoria RAM
            p.hubs = user.gameData.hubs;
            p.ohcu = user.gameData.ohcu;

            // Sincronizar clientes
            const { getCategorizedInventory } = require('./inventoryHandlers');
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });

            socket.emit('vaultUpdated', {
                items: user.gameData.vaultItems,
                unlockedTabs: user.gameData.vaultUnlockedTabs,
                inventoryMaxSlots: user.gameData.inventoryMaxSlots || state.SERVER_CONFIG.inventoryConfig?.defaultMaxSlots || 30
            });

            socket.emit('gameNotification', { msg: `PESTAÑA ${nextTabIdx + 1} DESBLOQUEADA`, type: 'success' });
        } catch (e) {
            console.error('[VAULT ERROR] unlockVaultTab:', e);
        } finally {
            socket.isProcessingVaultTransaction = false;
        }
    });
 
    // 5. DESBLOQUEAR SLOT DE INVENTARIO ADICIONAL
    socket.on('unlockInventorySlot', async () => {
        if (!socket.dbUser) return;
        if (socket.isProcessingVaultTransaction) return;
        socket.isProcessingVaultTransaction = true;
        try {
            const p = state.players[socket.id];
            if (!p) return;

            const user = getPlayerRAMAdapter(p);
            if (!user) return;
 
            if (p.zone !== 1) {
                return socket.emit('gameNotification', { msg: 'ACCESO RESTRINGIDO: Solo puedes desbloquear slots en el Lobby.', type: 'error' });
            }
 
            if (user.gameData.inventoryMaxSlots === undefined || user.gameData.inventoryMaxSlots === null) {
                user.gameData.inventoryMaxSlots = state.SERVER_CONFIG.inventoryConfig?.defaultMaxSlots || 30;
            }
 
            const inventoryConfig = state.SERVER_CONFIG.inventoryConfig || { defaultMaxSlots: 30, unlockSlotPrice: 1000 };
            const rawPrice = inventoryConfig.unlockSlotPrice || 1000;
            const price = parsePrice(rawPrice);

            if (price.hubs === 0 && price.ohcu === 0) {
                return socket.emit('gameNotification', { msg: 'BLOQUEADO: Este slot debe adquirirse de otra forma.', type: 'error' });
            }

            if (price.hubs > 0 && user.gameData.hubs < price.hubs) {
                return socket.emit('gameNotification', { msg: `FONDOS INSUFICIENTES: Necesitas ${price.hubs} Hubs para desbloquear 1 slot de inventario.`, type: 'error' });
            }
            if (price.ohcu > 0 && user.gameData.ohcu < price.ohcu) {
                return socket.emit('gameNotification', { msg: `FONDOS INSUFICIENTES: Necesitas ${price.ohcu} Ohcu para desbloquear 1 slot de inventario.`, type: 'error' });
            }
 
            // Debitar e incrementar slots
            if (price.hubs > 0) user.gameData.hubs -= price.hubs;
            if (price.ohcu > 0) user.gameData.ohcu -= price.ohcu;
            user.gameData.inventoryMaxSlots += 1;
 
            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;
 
            // Sincronizar estado en memoria RAM
            p.hubs = user.gameData.hubs;
            p.ohcu = user.gameData.ohcu;
 
            // Sincronizar clientes
            const { getCategorizedInventory } = require('./inventoryHandlers');
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);
 
            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });
 
            socket.emit('vaultUpdated', {
                items: user.gameData.vaultItems,
                unlockedTabs: user.gameData.vaultUnlockedTabs,
                inventoryMaxSlots: user.gameData.inventoryMaxSlots
            });
 
            socket.emit('gameNotification', { msg: `SLOT DE INVENTARIO ADICIONAL DESBLOQUEADO (${user.gameData.inventoryMaxSlots} Slots Máx)`, type: 'success' });
        } catch (e) {
            console.error('[VAULT ERROR] unlockInventorySlot:', e);
        } finally {
            socket.isProcessingVaultTransaction = false;
        }
    });
}

module.exports = { registerVaultHandlers };
