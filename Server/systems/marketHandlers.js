const MarketListing = require('../models/MarketListing');
const User = require('../models/User');
const { getPlayerRAMAdapter } = require('../utils/ramAdapter');
const { checkCombatLock, getMasterItemConfig, sendInventoryData } = require('./inventoryHandlers');

/**
 * v500.0: MERCADO / CASA DE SUBASTAS CENTRALIZADA
 * - Publicación: el ítem se REMUEVE del inventario al instante (anti-dupe).
 * - Compra: mutex en memoria por listing + re-verificación contra MongoDB dentro
 *   de la sección crítica (protege incluso contra dos procesos sobre el mismo Atlas).
 * - Impuesto de venta (sink de oro) y tasas configurables desde AdminDash.
 * - Expiración: worker periódico devuelve ítems no vendidos al buzón del vendedor.
 */

let systemStarted = false;
const listingLocks = new Map();
let activeCache = [];
let lastCacheLoad = 0;
let expiryTimer = null;
let refreshTimer = null;

function getMarketConfig(state) {
    return state.SERVER_CONFIG?.marketConfig || {};
}

function getAccessZoneId(state) {
    const cfg = getMarketConfig(state);
    return cfg.accessZoneId !== undefined ? cfg.accessZoneId : 1;
}

function isZoneAllowed(p, state) {
    const target = String(getAccessZoneId(state));
    const cur = String(p.zone !== undefined ? p.zone : 1);
    return cur === target;
}

function normalizeSellableItem(item) {
    const copy = JSON.parse(JSON.stringify(item));
    return copy;
}

function isMarketTradable(item, state) {
    if (!item) return false;
    const cfg = getMarketConfig(state);
    if (cfg.enabled === false) return false;
    if (item.soulbound === true) return false;
    const master = getMasterItemConfig(item.id, state.SERVER_CONFIG);
    if (master && master.soulbound === true) return false;
    if (Array.isArray(cfg.blockedItemIds) && cfg.blockedItemIds.includes(item.id)) return false;
    return true;
}

function acquireLock(listingId) {
    if (listingLocks.has(listingId)) return false;
    listingLocks.set(listingId, true);
    return true;
}

function releaseLock(listingId) {
    listingLocks.delete(listingId);
}

// ---------------------------------------------------------------------------
// CACHE RAM DE PUBLICACIONES ACTIVAS (lecturas rápidas, patron RAM-first)
// ---------------------------------------------------------------------------
async function refreshActiveCache(state) {
    try {
        const docs = await MarketListing.find({ status: 'active' })
            .sort({ listedAt: -1 })
            .limit(500)
            .lean();
        activeCache = docs || [];
        lastCacheLoad = Date.now();
    } catch (e) {
        console.error('[MARKET-CACHE] Error cargando publicaciones activas:', e.message);
    }
}

function upsertCache(listing) {
    const idx = activeCache.findIndex(l => String(l._id) === String(listing._id));
    const plain = typeof listing.toObject === 'function' ? listing.toObject() : listing;
    if (idx >= 0) activeCache[idx] = plain;
    else activeCache.unshift(plain);
    if (activeCache.length > 500) activeCache.pop();
}

function removeFromCache(listingId) {
    activeCache = activeCache.filter(l => String(l._id) !== String(listingId));
}

function toPublicListing(doc) {
    const item = doc.item || {};
    return {
        _id: String(doc._id),
        sellerName: doc.sellerName || 'Desconocido',
        item: {
            id: item.id,
            name: item.name,
            icon: item.icon || "",
            rarity: item.rarity || 0,
            color: item.color || "#ffffff",
            type: item.type || "utility",
            base: item.base || 0,
            hpMod: item.hpMod || 0,
            hpModType: item.hpModType || 'percent',
            speedMod: item.speedMod || 0,
            speedModType: item.speedModType || 'percent',
            shieldMod: item.shieldMod || 0,
            shieldModType: item.shieldModType || 'percent',
            dmgMod: item.dmgMod || 0,
            dmgModType: item.dmgModType || 'percent'
        },
        price: doc.price,
        currency: doc.currency,
        amount: doc.amount || 1,
        status: doc.status,
        listedAt: doc.listedAt,
        expiresAt: doc.expiresAt ? doc.expiresAt.getTime() : null
    };
}

// ---------------------------------------------------------------------------
// BUZÓN DEL MERCADO (entregas offline + devoluciones)
// ---------------------------------------------------------------------------
function newMailboxEntry(type, payload) {
    return {
        _id: Date.now().toString(36) + Math.random().toString(36).substr(2, 5),
        type: type,
        date: Date.now(),
        ...payload
    };
}

async function findOnlinePlayerByDbId(state, dbId) {
    const uid = String(dbId);
    for (const sid in state.players) {
        const p = state.players[sid];
        if (p && String(p.dbId || (p.id ? p.id.toString() : '')) === uid) return p;
    }
    return null;
}

function pushMailboxEntry(p, entry) {
    if (!p.marketMailbox) p.marketMailbox = [];
    p.marketMailbox.push(entry);
    if (p.marketMailbox.length > 100) p.marketMailbox.splice(0, p.marketMailbox.length - 100);
}

async function deliverToSellerMailbox(state, io, sellerId, sellerName, listing) {
    const entry = newMailboxEntry('item', {
        reason: 'PUBLICACIÓN NO VENDIDA',
        item: { ...normalizeSellableItem(listing.item), amount: listing.amount || 1 },
        amount: listing.amount || 1,
        listingId: String(listing._id)
    });
    const online = await findOnlinePlayerByDbId(state, sellerId);
    if (online) {
        pushMailboxEntry(online, entry);
        const user = getPlayerRAMAdapter(online);
        if (user) { user.markModified('gameData.marketMailbox'); await user.save(); }
        const sellerSocket = io.sockets.sockets.get(Object.keys(state.players).find(sid => state.players[sid] === online));
        if (sellerSocket) sellerSocket.emit('marketMailboxUpdated', { mailbox: online.marketMailbox || [] });
    } else {
        try {
            await User.updateOne({ _id: sellerId }, { $push: { 'gameData.marketMailbox': entry } });
        } catch (e) {
            console.error('[MARKET-MAILBOX] Error entregando ítem a buzón offline:', e.message);
        }
    }
}

async function creditSeller(state, io, sellerId, currency, amount, reason, itemName) {
    const net = Math.floor(amount);
    const entry = newMailboxEntry('sale', {
        reason: reason,
        currency: currency,
        amount: net,
        itemName: itemName || ''
    });
    const online = await findOnlinePlayerByDbId(state, sellerId);
    if (online) {
        if (currency === 'ohcu') online.ohcu = (online.ohcu || 0) + net;
        else online.hubs = (online.hubs || 0) + net;
        pushMailboxEntry(online, entry);
        const user = getPlayerRAMAdapter(online);
        if (user) { user.markModified('gameData.marketMailbox'); await user.save(); }
        const sellerSocket = io.sockets.sockets.get(Object.keys(state.players).find(sid => state.players[sid] === online));
        if (sellerSocket) {
            sellerSocket.emit('walletData', { hubs: online.hubs, ohcu: online.ohcu });
            sellerSocket.emit('marketMailboxUpdated', { mailbox: online.marketMailbox || [] });
        }
    } else {
        try {
            await User.updateOne(
                { _id: sellerId },
                { $inc: { ['gameData.' + currency]: net }, $push: { 'gameData.marketMailbox': entry } }
            );
        } catch (e) {
            console.error('[MARKET-CREDIT] Error acreditando venta offline:', e.message);
        }
    }
}

function broadcastMarketUpdate(io, payload) {
    io.emit('marketUpdate', payload);
}

// ---------------------------------------------------------------------------
// ENTREGA AL INVENTARIO DEL COMPRADOR (respeta maxStack y conserva instanceId)
// ---------------------------------------------------------------------------
function deliverItemToInventory(user, itemSnapshot, serverConfig, quantity) {
    const master = getMasterItemConfig(itemSnapshot.id, serverConfig);
    const maxStack = master ? parseInt(master.maxStack) || 1 : 1;
    let remaining = quantity;

    if (maxStack > 1) {
        for (let i = 0; i < user.gameData.inventory.length; i++) {
            const cur = user.gameData.inventory[i];
            if (cur.id === itemSnapshot.id) {
                const curAmt = parseInt(cur.amount) || 1;
                if (curAmt < maxStack) {
                    const space = maxStack - curAmt;
                    const toAdd = Math.min(space, remaining);
                    cur.amount = curAmt + toAdd;
                    remaining -= toAdd;
                    if (remaining <= 0) break;
                }
            }
        }
        while (remaining > 0) {
            const maxSlots = user.gameData.inventoryMaxSlots || serverConfig.inventoryConfig?.defaultMaxSlots || 30;
            if (user.gameData.inventory.length >= maxSlots) return remaining;
            const toAdd = Math.min(maxStack, remaining);
            user.gameData.inventory.push({
                ...normalizeSellableItem(itemSnapshot),
                instanceId: Date.now() + Math.random().toString(36).substr(2, 5),
                amount: toAdd
            });
            remaining -= toAdd;
        }
        return 0;
    } else {
        while (remaining > 0) {
            const maxSlots = user.gameData.inventoryMaxSlots || serverConfig.inventoryConfig?.defaultMaxSlots || 30;
            if (user.gameData.inventory.length >= maxSlots) return remaining;
            user.gameData.inventory.push({
                ...normalizeSellableItem(itemSnapshot),
                instanceId: itemSnapshot.instanceId || (Date.now() + Math.random().toString(36).substr(2, 5)),
                amount: 1
            });
            remaining--;
        }
        return 0;
    }
}

// ---------------------------------------------------------------------------
// WORKER DE EXPIRACIÓN
// ---------------------------------------------------------------------------
async function processExpiredListings(io, state) {
    const now = new Date();
    let docs;
    try {
        docs = await MarketListing.find({ status: 'active', expiresAt: { $lt: now } }).limit(50);
    } catch (e) {
        console.error('[MARKET-EXPIRE] Error consultando vencidos:', e.message);
        return;
    }
    if (!docs || docs.length === 0) return;

    for (const listing of docs) {
        listing.status = 'expired';
        try {
            await listing.save();
        } catch (e) {
            console.error('[MARKET-EXPIRE] Error guardando expiración:', e.message);
            continue;
        }
        removeFromCache(String(listing._id));
        await deliverToSellerMailbox(state, io, listing.sellerId, listing.sellerName, listing);
        broadcastMarketUpdate(io, { _id: String(listing._id), status: 'expired' });
        console.log(`[MARKET-EXPIRE] Publicación ${listing._id} de ${listing.sellerName} expirada. Ítem devuelto al buzón.`);
    }
}

function initMarketSystem(io, state) {
    if (systemStarted) return;
    systemStarted = true;

    refreshActiveCache(state);

    // Timers recursivos: leen la config en cada ciclo para soportar recarga en caliente
    const expiryLoop = async () => {
        try { await processExpiredListings(io, state); } catch (e) { console.error('[MARKET-EXPIRE] Error en ciclo:', e.message); }
        const cfg = getMarketConfig(state);
        expiryTimer = setTimeout(expiryLoop, cfg.expiryCheckIntervalMs || 60000);
    };
    expiryTimer = setTimeout(expiryLoop, getMarketConfig(state).expiryCheckIntervalMs || 60000);

    const refreshLoop = async () => {
        await refreshActiveCache(state);
        const cfg = getMarketConfig(state);
        refreshTimer = setTimeout(refreshLoop, cfg.cacheRefreshIntervalMs || 300000);
    };
    refreshTimer = setTimeout(refreshLoop, getMarketConfig(state).cacheRefreshIntervalMs || 300000);

    console.log('[MARKET] Sistema de Mercado inicializado. Worker de expiración y cache activos.');
}

// ---------------------------------------------------------------------------
// REGISTRO DE EVENTOS SOCKET
// ---------------------------------------------------------------------------
function registerMarketHandlers(socket, io, state) {

    // CONSULTA GLOBAL DE MERCADO (listados + mis publicaciones + buzón + config pública)
    socket.on('getMarketData', async () => {
        const p = state.players[socket.id];
        if (!p || !p.dbId) return;
        if (!isZoneAllowed(p, state)) {
            return socket.emit('gameNotification', { msg: 'El Mercado solo está disponible en el Lobby.', type: 'error' });
        }

        if (Date.now() - lastCacheLoad > (getMarketConfig(state).cacheRefreshIntervalMs || 300000)) {
            await refreshActiveCache(state);
        }

        const myListings = await MarketListing.find({ sellerId: p.dbId }).sort({ listedAt: -1 }).limit(50).lean();
        const cfg = getMarketConfig(state);

        socket.emit('marketData', {
            config: {
                enabled: cfg.enabled !== false,
                sellTaxPercent: cfg.sellTaxPercent || 0,
                listingFeeHubs: cfg.listingFeeHubs || 0,
                listingFeeOhcu: cfg.listingFeeOhcu || 0,
                listingDurationHours: cfg.listingDurationHours || 48,
                maxActiveListingsPerPlayer: cfg.maxActiveListingsPerPlayer || 10,
                minPriceHubs: cfg.minPriceHubs || 0,
                maxPriceHubs: cfg.maxPriceHubs || 0,
                minPriceOhcu: cfg.minPriceOhcu || 0,
                maxPriceOhcu: cfg.maxPriceOhcu || 0,
                allowSelfBuy: !!cfg.allowSelfBuy
            },
            listings: activeCache.map(toPublicListing),
            myListings: (myListings || []).map(l => ({ ...toPublicListing(l), instanceId: l.item?.instanceId || null })),
            mailbox: p.marketMailbox || []
        });
    });

    // PUBLICAR ÍTEM EN EL MERCADO
    socket.on('createMarketListing', async (data) => {
        const p = state.players[socket.id];
        if (!p || !p.dbId) return;
        if (!isZoneAllowed(p, state)) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'El Mercado solo está disponible en el Lobby.' });
        }
        if (p.isProcessingInventory) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'Transacción en curso. Espera un momento.' });
        }
        const lock = checkCombatLock(p);
        if (lock.locked) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: `Sistemas calientes. Espera ${lock.remaining}s para publicar.` });
        }

        const cfg = getMarketConfig(state);
        if (cfg.enabled === false) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'El Mercado está cerrado por mantenimiento.' });
        }

        const { instanceId, amount, price, currency } = data || {};
        if (!instanceId || !price || price <= 0 || (currency !== 'hubs' && currency !== 'ohcu')) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'Datos de publicación inválidos.' });
        }

        const user = getPlayerRAMAdapter(p);
        const idx = user.gameData.inventory.findIndex(it => it.instanceId === instanceId);
        if (idx === -1) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'Ítem no encontrado en tu inventario.' });
        }
        const item = user.gameData.inventory[idx];
        if (!isMarketTradable(item, state)) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'Este ítem es de misión o está bloqueado. No se puede comerciar.' });
        }

        const maxAmount = parseInt(item.amount) || 1;
        const qty = amount ? Math.min(Math.max(1, parseInt(amount) || 1), maxAmount) : maxAmount;

        const minP = currency === 'ohcu' ? (cfg.minPriceOhcu || 1) : (cfg.minPriceHubs || 10);
        const maxP = currency === 'ohcu' ? (cfg.maxPriceOhcu || 0) : (cfg.maxPriceHubs || 0);
        const totalPrice = Math.floor(price * qty);
        if (totalPrice < minP) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: `Precio mínimo por esta moneda: ${minP}.` });
        }
        if (maxP > 0 && totalPrice > maxP) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: `Precio máximo permitido: ${maxP}.` });
        }

        const activeCount = await MarketListing.countDocuments({ sellerId: p.dbId, status: 'active' });
        if (activeCount >= (cfg.maxActiveListingsPerPlayer || 10)) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: `Máximo de publicaciones activas: ${cfg.maxActiveListingsPerPlayer || 10}.` });
        }

        const fee = currency === 'ohcu' ? (cfg.listingFeeOhcu || 0) : (cfg.listingFeeHubs || 0);
        const playerFunds = currency === 'ohcu' ? (user.gameData.ohcu || 0) : (user.gameData.hubs || 0);
        if (fee > 0 && playerFunds < fee) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: `Necesitas ${fee} ${currency.toUpperCase()} para pagar la tasa de publicación.` });
        }

        // --- REMOVER ÍTEM DEL INVENTARIO INMEDIATAMENTE (anti-dupe) ---
        if (qty < maxAmount) {
            item.amount = maxAmount - qty;
        } else {
            user.gameData.inventory.splice(idx, 1);
        }
        if (fee > 0) {
            if (currency === 'ohcu') user.gameData.ohcu -= fee;
            else user.gameData.hubs -= fee;
        }

        const itemSnapshot = normalizeSellableItem(item);
        itemSnapshot.amount = qty;

        const listing = new MarketListing({
            sellerId: p.dbId,
            sellerName: p.user || 'Piloto',
            item: itemSnapshot,
            price: Math.floor(price),
            currency: currency,
            amount: qty,
            status: 'active',
            expiresAt: new Date(Date.now() + ((cfg.listingDurationHours || 48) * 3600 * 1000))
        });

        try {
            await listing.save();
        } catch (e) {
            // ROLLBACK: devolver el ítem al inventario
            console.error('[MARKET-CREATE] Error guardando publicación, rollback:', e.message);
            deliverItemToInventory(user, itemSnapshot, state.SERVER_CONFIG, qty);
            if (fee > 0) {
                if (currency === 'ohcu') user.gameData.ohcu += fee;
                else user.gameData.hubs += fee;
            }
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'Error interno al publicar. Intenta de nuevo.' });
        }

        user.markModified('gameData.inventory');
        user.markModified('gameData');
        await user.save();
        socket.dbUser = user;

        p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));
        if (currency === 'ohcu') p.ohcu = user.gameData.ohcu;
        else p.hubs = user.gameData.hubs;

        upsertCache(listing);
        sendInventoryData(socket, user);
        broadcastMarketUpdate(io, toPublicListing(listing));
        socket.emit('marketPurchaseResult', {
            ok: true,
            msg: `¡Publicado! ${qty}x ${itemSnapshot.name || itemSnapshot.id} por ${Math.floor(price)} ${currency.toUpperCase()}.`
        });
    });

    // CANCELAR PUBLICACIÓN PROPIA
    socket.on('cancelMarketListing', async (data) => {
        const p = state.players[socket.id];
        if (!p || !p.dbId) return;
        if (!isZoneAllowed(p, state)) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'El Mercado solo está disponible en el Lobby.' });
        }

        const listingId = data?.listingId;
        if (!listingId) return;
        const listing = await MarketListing.findById(listingId);
        if (!listing || String(listing.sellerId) !== String(p.dbId)) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'Publicación no encontrada.' });
        }
        if (listing.status !== 'active') {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'Esta publicación ya no está activa.' });
        }

        listing.status = 'cancelled';
        await listing.save();
        removeFromCache(String(listing._id));

        const user = getPlayerRAMAdapter(p);
        const leftover = deliverItemToInventory(user, listing.item, state.SERVER_CONFIG, listing.amount || 1);
        if (leftover > 0) {
            await deliverToSellerMailbox(state, io, p.dbId, p.user, listing);
        }

        user.markModified('gameData.inventory');
        await user.save();
        socket.dbUser = user;
        p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));

        sendInventoryData(socket, user);
        broadcastMarketUpdate(io, { _id: String(listing._id), status: 'cancelled' });
        socket.emit('marketPurchaseResult', { ok: true, msg: 'Publicación cancelada. Ítem devuelto a tu inventario.' });
    });

    // COMPRAR PUBLICACIÓN (TRANSACCIÓN ATÓMICA)
    socket.on('buyMarketListing', async (data) => {
        const p = state.players[socket.id];
        if (!p || !p.dbId) return;
        if (!isZoneAllowed(p, state)) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'El Mercado solo está disponible en el Lobby.' });
        }
        if (p.isProcessingInventory) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'Transacción en curso. Espera un momento.' });
        }
        const lock = checkCombatLock(p);
        if (lock.locked) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: `Sistemas calientes. Espera ${lock.remaining}s para comprar.` });
        }

        const cfg = getMarketConfig(state);
        if (cfg.enabled === false) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'El Mercado está cerrado por mantenimiento.' });
        }

        const listingId = data?.listingId;
        if (!listingId) return;

        if (!acquireLock(String(listingId))) {
            return socket.emit('marketPurchaseResult', { ok: false, msg: 'Transacción en curso para esta publicación.' });
        }

        try {
            // Re-verificación autoritativa contra MongoDB dentro de la sección crítica
            const listing = await MarketListing.findById(listingId);
            if (!listing || listing.status !== 'active') {
                removeFromCache(String(listingId));
                return socket.emit('marketPurchaseResult', { ok: false, msg: 'Este ítem ya fue adquirido por otro jugador.' });
            }
            if (!cfg.allowSelfBuy && String(listing.sellerId) === String(p.dbId)) {
                return socket.emit('marketPurchaseResult', { ok: false, msg: 'No puedes comprar tus propias publicaciones.' });
            }

            const user = getPlayerRAMAdapter(p);
            const total = listing.price * (listing.amount || 1);
            const funds = listing.currency === 'ohcu' ? (user.gameData.ohcu || 0) : (user.gameData.hubs || 0);
            if (funds < total) {
                return socket.emit('marketPurchaseResult', { ok: false, msg: `No tienes suficientes ${listing.currency.toUpperCase()}.` });
            }

            // Entregar ítem al comprador ANTES de debitar (si no cabe, abortar sin cambios)
            const leftover = deliverItemToInventory(user, listing.item, state.SERVER_CONFIG, listing.amount || 1);
            if (leftover > 0) {
                return socket.emit('marketPurchaseResult', { ok: false, msg: 'Inventario lleno. Libera espacio antes de comprar.' });
            }

            // Todo verificado: aplicar la transacción en memoria (sin awaits entre check y mutación)
            if (listing.currency === 'ohcu') user.gameData.ohcu -= total;
            else user.gameData.hubs -= total;

            listing.status = 'sold';
            listing.soldAt = new Date();
            listing.buyerId = p.dbId;

            // Impuesto de venta (sink de oro) - porcentaje configurable
            const taxPct = cfg.sellTaxPercent || 0;
            const sellerNet = Math.floor(total * (100 - taxPct) / 100);

            await listing.save();
            user.markModified('gameData.inventory');
            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));
            if (listing.currency === 'ohcu') p.ohcu = user.gameData.ohcu;
            else p.hubs = user.gameData.hubs;

            removeFromCache(String(listing._id));
            sendInventoryData(socket, user);
            socket.emit('walletData', { hubs: p.hubs, ohcu: p.ohcu });

            await creditSeller(state, io, listing.sellerId, listing.currency, sellerNet, 'VENTA EN EL MERCADO', listing.item?.name || listing.item?.id);
            broadcastMarketUpdate(io, { _id: String(listing._id), status: 'sold' });

            socket.emit('marketPurchaseResult', {
                ok: true,
                msg: `¡Compra exitosa! ${listing.amount}x ${listing.item?.name || listing.item?.id} por ${total} ${listing.currency.toUpperCase()}.`
            });
        } catch (e) {
            console.error('[MARKET-BUY] Error en compra:', e);
            socket.emit('marketPurchaseResult', { ok: false, msg: 'Error interno al procesar la compra.' });
        } finally {
            releaseLock(String(listingId));
        }
    });

    // RECLAMAR BUZÓN DEL MERCADO (ítems devueltos / notificaciones)
    socket.on('claimMarketMailbox', async (data) => {
        const p = state.players[socket.id];
        if (!p || !p.dbId) return;
        const user = getPlayerRAMAdapter(p);
        const mailbox = user.gameData.marketMailbox || [];
        if (mailbox.length === 0) return;

        const entryId = data?.entryId;
        const claimedIds = [];
        const remaining = [];

        for (const entry of mailbox) {
            if (entryId && entry._id !== entryId) {
                remaining.push(entry);
                continue;
            }
            if (entry.type === 'item' && entry.item) {
                const leftover = deliverItemToInventory(user, entry.item, state.SERVER_CONFIG, entry.amount || 1);
                if (leftover > 0) {
                    remaining.push(entry);
                    continue;
                }
            }
            claimedIds.push(entry._id);
        }

        user.gameData.marketMailbox = remaining;
        user.markModified('gameData.marketMailbox');
        await user.save();
        socket.dbUser = user;
        p.marketMailbox = JSON.parse(JSON.stringify(remaining));

        if (claimedIds.length > 0) {
            sendInventoryData(socket, user);
        }
        socket.emit('marketMailboxUpdated', { mailbox: remaining });
    });

    // ---- PANEL ADMIN: VER PUBLICACIONES (SOLO GRAN MAESTRO) ----
    socket.on('adminGetMarketListings', async (data) => {
        if (!socket.dbUser || String(socket.dbUser.username || '').toLowerCase() !== 'caelli94') return;
        const limit = Math.min(parseInt(data?.limit) || 100, 200);
        const status = data?.status;
        const filter = status ? { status: status } : {};
        const docs = await MarketListing.find(filter).sort({ listedAt: -1 }).limit(limit).lean();
        socket.emit('adminMarketListings', {
            listings: docs.map(d => ({
                ...toPublicListing(d),
                sellerId: String(d.sellerId),
                buyerId: d.buyerId ? String(d.buyerId) : null,
                soldAt: d.soldAt || null
            }))
        });
    });

    // ---- PANEL ADMIN: CANCELAR PUBLICACIÓN (MODERACIÓN) ----
    socket.on('adminCancelMarketListing', async (data) => {
        if (!socket.dbUser || String(socket.dbUser.username || '').toLowerCase() !== 'caelli94') return;
        const listingId = data?.listingId;
        if (!listingId) return;
        const listing = await MarketListing.findById(listingId);
        if (!listing) return socket.emit('gameNotification', { msg: 'Publicación no encontrada.', type: 'error' });
        if (listing.status === 'active') {
            listing.status = 'cancelled';
            await listing.save();
            removeFromCache(String(listing._id));
            await deliverToSellerMailbox(state, io, listing.sellerId, listing.sellerName, listing);
            broadcastMarketUpdate(io, { _id: String(listing._id), status: 'cancelled' });
            socket.emit('gameNotification', { msg: `Publicación ${listing._id} cancelada. Ítem devuelto a ${listing.sellerName}.`, type: 'success' });
        } else {
            socket.emit('gameNotification', { msg: 'La publicación ya no está activa.', type: 'error' });
        }
    });
}

module.exports = { registerMarketHandlers, initMarketSystem, isMarketTradable, refreshActiveCache };