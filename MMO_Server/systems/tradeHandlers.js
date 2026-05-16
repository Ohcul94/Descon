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
            trade.items1 = items; // items es un array de instanceIds o objetos breves
        } else {
            trade.items2 = items;
        }

        // Sincronizar con el otro jugador
        const partnerId = (trade.p1 === socket.id) ? trade.p2 : trade.p1;
        io.to(partnerId).emit('tradePartnerUpdate', { items, partnerReady: false });
        socket.emit('tradePartnerUpdate', { partnerReady: false }); // Reset local ready state
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
        const user1 = await User.findById(state.players[trade.p1].dbId);
        const user2 = await User.findById(state.players[trade.p2].dbId);

        if (!user1 || !user2) throw new Error("USUARIO NO ENCONTRADO");

        // VALIDACIÓN DE SEGURIDAD: Verificar que los items realmente existen en los inventarios
        const validateItems = (user, itemInstances) => {
            return itemInstances.every(instId => user.gameData.inventory.some(it => it.instanceId === instId));
        };

        if (!validateItems(user1, trade.items1) || !validateItems(user2, trade.items2)) {
            throw new Error("ÍTEMS NO ENCONTRADOS EN BODEGA (¿EQUIPADOS?)");
        }

        // PROCESAR INTERCAMBIO
        const itemsFrom1 = [];
        trade.items1.forEach(instId => {
            const idx = user1.gameData.inventory.findIndex(it => it.instanceId === instId);
            itemsFrom1.push(user1.gameData.inventory.splice(idx, 1)[0]);
        });

        const itemsFrom2 = [];
        trade.items2.forEach(instId => {
            const idx = user2.gameData.inventory.findIndex(it => it.instanceId === instId);
            itemsFrom2.push(user2.gameData.inventory.splice(idx, 1)[0]);
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

module.exports = { registerTradeHandlers };
