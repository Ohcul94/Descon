const User = require('../models/User');
const { getCategorizedInventory, checkCombatLock } = require('./inventoryHandlers');

/**
 * v300.001: SISTEMA DE COMERCIO (TRADE) SEGURO
 * Gestiona intercambios directos entre jugadores.
 */

const activeTrades = {}; // Almacena el estado de los trades en curso: { tradeId: { p1, p2, items1, items2, ready1, ready2 } }

function registerTradeHandlers(socket, io, state) {

    // 1. SOLICITAR TRADE
    socket.on('tradeInvite', (targetSocketId) => {
        const p1 = state.players[socket.id];
        const p2 = state.players[targetSocketId];

        if (!p1 || !p2) return;
        if (socket.id === targetSocketId) return;

        // Validar distancia (opcional, pero recomendado)
        const dist = Math.hypot(p1.x - p2.x, p1.y - p2.y);
        if (dist > 500) {
            return socket.emit('gameNotification', { msg: "DEMASIADO LEJOS PARA COMERCIAR", type: "error" });
        }

        // Validar si ya están en un trade
        if (p1.inTrade || p2.inTrade) {
            return socket.emit('gameNotification', { msg: "JUGADOR OCUPADO", type: "error" });
        }

        // v300.002: BLOQUEO DE COMBATE
        const lock1 = checkCombatLock(p1);
        if (lock1.locked) {
            return socket.emit('gameNotification', { msg: `ESTÁS EN COMBATE (${lock1.remaining}s)`, type: "error" });
        }

        console.log(`[TRADE] ${p1.user} invitó a ${p2.user}`);
        io.to(targetSocketId).emit('tradeInvitationReceived', {
            fromId: socket.id,
            fromName: p1.user
        });
        
        socket.emit('gameNotification', { msg: `INVITACIÓN ENVIADA A ${p2.user.toUpperCase()}`, type: "info" });

    });

    // 2. ACEPTAR INVITACIÓN
    socket.on('tradeAcceptInvite', (fromSocketId) => {
        const p1 = state.players[fromSocketId];
        const p2 = state.players[socket.id];

        if (!p1 || !p2 || p1.inTrade || p2.inTrade) return;

        // v300.002: BLOQUEO DE COMBATE (Ambos)
        const lock1 = checkCombatLock(p1);
        const lock2 = checkCombatLock(p2);
        if (lock1.locked || lock2.locked) {
            return socket.emit('gameNotification', { msg: "NO SE PUEDE COMERCIAR EN COMBATE", type: "error" });
        }

        const tradeId = `trade_${Date.now()}_${socket.id}`;
        activeTrades[tradeId] = {
            p1: fromSocketId,
            p2: socket.id,
            items1: [],
            items2: [],
            ready1: false,
            ready2: false,
            locked: false // Para evitar race conditions al procesar el final
        };

        p1.inTrade = tradeId;
        p2.inTrade = tradeId;

        io.to(fromSocketId).emit('tradeStarted', { tradeId, partnerName: p2.user, partnerId: socket.id });
        io.to(socket.id).emit('tradeStarted', { tradeId, partnerName: p1.user, partnerId: fromSocketId });
        
        console.log(`[TRADE] Sesión iniciada: ${tradeId} entre ${p1.user} y ${p2.user}`);

    });

    // 3. CANCELAR TRADE
    const cancelTrade = (tradeId, reason = "COMERCIO CANCELADO") => {
        const trade = activeTrades[tradeId];
        if (!trade) return;

        [trade.p1, trade.p2].forEach(sid => {
            if (state.players[sid]) {
                state.players[sid].inTrade = null;
                io.to(sid).emit('tradeCancelled', { reason });
            }
        });

        delete activeTrades[tradeId];
    };

    socket.on('tradeCancel', () => {
        const p = state.players[socket.id];
        if (p && p.inTrade) cancelTrade(p.inTrade);
    });

    // 4. ACTUALIZAR ITEMS EN LA MESA
    socket.on('tradeUpdateItems', (items) => {
        const p = state.players[socket.id];
        if (!p || !p.inTrade) return;

        const tradeId = p.inTrade;
        const trade = activeTrades[tradeId];
        if (!trade || trade.locked) return;

        // Resetear "Ready" si alguien cambia algo
        trade.ready1 = false;
        trade.ready2 = false;

        if (trade.p1 === socket.id) {
            trade.items1 = items;
        } else {
            trade.items2 = items;
        }

        console.log(`[TRADE-SYNC] ${p.user} actualizó oferta: ${items.length} items.`);

        // v300.800: BÚSQUEDA EXHAUSTIVA (Bodega + Todas las naves)
        const fullItems = items.map(instId => findItemAnywhere(socket.dbUser, instId)).filter(i => !!i);

        // Sincronizar con el otro jugador
        const partnerId = (trade.p1 === socket.id) ? trade.p2 : trade.p1;
        io.to(partnerId).emit('tradePartnerUpdate', { items: fullItems, partnerReady: false });
        socket.emit('tradePartnerUpdate', { partnerReady: false });
    });

    // 5. CONFIRMAR (READY)
    socket.on('tradeConfirm', (isReady) => {
        const p = state.players[socket.id];
        if (!p || !p.inTrade) return;

        const tradeId = p.inTrade;
        const trade = activeTrades[tradeId];
        if (!trade || trade.locked) return;

        if (trade.p1 === socket.id) trade.ready1 = isReady;
        else trade.ready2 = isReady;

        const partnerId = (trade.p1 === socket.id) ? trade.p2 : trade.p1;
        io.to(partnerId).emit('tradePartnerReady', isReady);

        // Si AMBOS están listos, intentar ejecutar
        if (trade.ready1 && trade.ready2) {
            executeTrade(tradeId, io, state);
        }
    });

    // Sincronía de inventario gestionada centralmente en server.js para paridad con Hangar.

}

async function executeTrade(tradeId, io, state) {
    const trade = activeTrades[tradeId];
    if (!trade || trade.locked) return;
    trade.locked = true;

    try {
        const user1 = await User.findById(state.players[trade.p1].id);
        const user2 = await User.findById(state.players[trade.p2].id);

        if (!user1 || !user2) throw new Error("USUARIO NO ENCONTRADO");

        // VALIDACIÓN DE SEGURIDAD EXHAUSTIVA
        const validateItems = (user, itemInstances) => {
            return itemInstances.every(instId => findItemAnywhere(user, instId) !== null);
        };

        if (!validateItems(user1, trade.items1) || !validateItems(user2, trade.items2)) {
            throw new Error("ÍTEMS NO ENCONTRADOS EN LA CUENTA");
        }

        // PROCESAR INTERCAMBIO
        const itemsFrom1 = [];
        trade.items1.forEach(instId => {
            // Buscar y extraer de donde sea que esté
            const item = extractItemAnywhere(user1, instId);
            if (item) itemsFrom1.push(item);
        });

        const itemsFrom2 = [];
        trade.items2.forEach(instId => {
            const item = extractItemAnywhere(user2, instId);
            if (item) itemsFrom2.push(item);
        });

        // Entregar
        user1.gameData.inventory.push(...itemsFrom2);
        user2.gameData.inventory.push(...itemsFrom1);

        user1.markModified('gameData.inventory');
        user2.markModified('gameData.inventory');

        await user1.save();
        await user2.save();

        // Actualizar RAM de los jugadores
        state.players[trade.p1].inventory = user1.gameData.inventory;
        state.players[trade.p2].inventory = user2.gameData.inventory;

        // Informar éxito
        [trade.p1, trade.p2].forEach(sid => {
            const u = sid === trade.p1 ? user1 : user2;
            const p = state.players[sid];
            p.inTrade = null;
            
            const eByShipObj = {};
            if (u.gameData.equippedByShip instanceof Map) u.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, u.gameData.equippedByShip);

            io.to(sid).emit('tradeSuccess', {
                msg: "¡COMERCIO COMPLETADO CON ÉXITO!",
                inventoryData: {
                    player: { ...JSON.parse(JSON.stringify(u.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(u.gameData.inventory) }
                }
            });
        });

        delete activeTrades[tradeId];
        console.log(`[TRADE] Éxito: ${tradeId}`);

    } catch (e) {
        console.error("[TRADE EXECUTE ERROR]", e);
        const tradeData = activeTrades[tradeId];
        if (tradeData) {
            [tradeData.p1, tradeData.p2].forEach(sid => {
                io.to(sid).emit('tradeCancelled', { reason: "ERROR CRÍTICO EN EL PROCESO" });
                if (state.players[sid]) state.players[sid].inTrade = null;
            });
            delete activeTrades[tradeId];
        }
    }
}

function findItemAnywhere(user, instId) {
    if (!user || !user.gameData) return null;
    
    // 1. Buscar en inventario
    const invItem = user.gameData.inventory.find(it => it.instanceId === instId);
    if (invItem) return invItem;
    
    // 2. Buscar en naves (equippedByShip)
    if (user.gameData.equippedByShip) {
        const ebs = user.gameData.equippedByShip;
        const ships = (ebs instanceof Map) ? Array.from(ebs.values()) : Object.values(ebs);
        for (const shipEq of ships) {
            for (const cat in shipEq) {
                if (Array.isArray(shipEq[cat])) {
                    const found = shipEq[cat].find(it => it.instanceId === instId);
                    if (found) return found;
                }
            }
        }
    }
    return null;
}

function extractItemAnywhere(user, instId) {
    // Buscar en inventario y sacarlo
    const idx = user.gameData.inventory.findIndex(it => it.instanceId === instId);
    if (idx !== -1) return user.gameData.inventory.splice(idx, 1)[0];
    
    // Si no está en inventario, buscar en naves y sacarlo de ahí (esto lo desequipa de paso)
    if (user.gameData.equippedByShip) {
        const ebs = user.gameData.equippedByShip;
        const keys = (ebs instanceof Map) ? Array.from(ebs.keys()) : Object.keys(ebs);
        for (const k of keys) {
            const shipEq = (ebs instanceof Map) ? ebs.get(k) : ebs[k];
            for (const cat in shipEq) {
                if (Array.isArray(shipEq[cat])) {
                    const sidx = shipEq[cat].findIndex(it => it.instanceId === instId);
                    if (sidx !== -1) {
                        const item = shipEq[cat].splice(sidx, 1)[0];
                        user.markModified('gameData.equippedByShip');
                        return item;
                    }
                }
            }
        }
    }
    return null;
}

function unequipFromAllShips(user, instId) {
    // 1. Limpiar de nave activa
    const eq = user.gameData.equipped;
    if (eq) {
        Object.keys(eq).forEach(cat => {
            if (Array.isArray(eq[cat])) {
                user.gameData.equipped[cat] = eq[cat].filter(it => it.instanceId !== instId);
            }
        });
    }

    // 2. Limpiar de equippedByShip (Mapa o Objeto)
    if (user.gameData.equippedByShip) {
        if (typeof user.gameData.equippedByShip.get === 'function') {
            user.gameData.equippedByShip.forEach((shipEq, shipId) => {
                Object.keys(shipEq).forEach(cat => {
                    if (Array.isArray(shipEq[cat])) {
                        shipEq[cat] = shipEq[cat].filter(it => it.instanceId !== instId);
                    }
                });
            });
        } else {
            Object.keys(user.gameData.equippedByShip).forEach(shipId => {
                const shipEq = user.gameData.equippedByShip[shipId];
                Object.keys(shipEq).forEach(cat => {
                    if (Array.isArray(shipEq[cat])) {
                        shipEq[cat] = shipEq[cat].filter(it => it.instanceId !== instId);
                    }
                });
            });
        }
    }
    user.markModified('gameData.equipped');
    user.markModified('gameData.equippedByShip');
}

module.exports = { registerTradeHandlers };
