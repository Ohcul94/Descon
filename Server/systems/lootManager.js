const User = require('../models/User');
const { getPlayerRAMAdapter } = require('../utils/ramAdapter'); // v6.02

/**
 * lootManager.js
 * Sistema de botín autoritativo para el servidor del MMO.
 * Maneja la generación de drops de bicho, inspección segura, reclamos e intervalos de limpieza.
 */

function getInteractRange(state) {
    return state.SERVER_CONFIG?.lootConfig?.interactRange || 400;
}
function getExpirationMs(state) {
    return state.SERVER_CONFIG?.lootConfig?.expirationMs || 300000;
}
function isServerAuthoritative(state) {
    return state.SERVER_CONFIG?.lootConfig?.serverAuthoritative !== false;
}function spawnLootFromEnemy(enemy, io, state, killerSocketId = null) {
    try {
        const cfg = state.SERVER_CONFIG && state.SERVER_CONFIG.enemyModels ? state.SERVER_CONFIG.enemyModels[enemy.type] : null;
        if (!cfg) {
            return;
        }

        const lootDrops = Array.isArray(cfg.lootDrops) ? cfg.lootDrops : [];

        // 1. Obtener la probabilidad del enemigo y el multiplicador del mapa/zona
        const chestDropChance = cfg.chestDropChance !== undefined ? cfg.chestDropChance : 0.1;
        const zoneCfg = state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig ? state.SERVER_CONFIG.mapsConfig[enemy.zone] : null;
        const zoneMultiplier = zoneCfg && zoneCfg.dropMultiplier !== undefined ? zoneCfg.dropMultiplier : 1.0;

        const finalSpawnChance = chestDropChance * zoneMultiplier;

        // 2. Tirada de cofre. Si falla, no spawnea nada.
        if (Math.random() > finalSpawnChance) {
            // console.log(`[LOOT-SPAWN] Enemigo ${enemy.type} en zona ${enemy.zone} no soltó cofre (Chance combinada: ${finalSpawnChance.toFixed(2)})`);
            return;
        }

        const droppedItems = [];
        const allShopItems = [
            ...(state.SERVER_CONFIG.shopItems?.weapons || []),
            ...(state.SERVER_CONFIG.shopItems?.shields || []),
            ...(state.SERVER_CONFIG.shopItems?.engines || []),
            ...(state.SERVER_CONFIG.shopItems?.extra || []),
            ...(state.SERVER_CONFIG.shopItems?.resources || [])
        ];

        lootDrops.forEach(dropCfg => {
            const chance = dropCfg.chance !== undefined ? dropCfg.chance : 0.1;
            if (Math.random() <= chance) {
                // Buscar el ítem en la configuración maestra para obtener todos los campos requeridos
                const master = allShopItems.find(item => item.id === dropCfg.itemId);
                // v620.0: Ojito de visibilidad — ítems hidden no caen como botín
                if (master && master.hidden) return;
                if (master) {
                    let type = (master.type || "utility").toLowerCase();
                    const id = master.id.toLowerCase();
                    if (id.startsWith('las') || id.startsWith('w')) type = "weapon";
                    else if (id.startsWith('sh') || id.startsWith('s')) type = "shield";
                    else if (id.startsWith('en') || id.startsWith('e')) type = "engine";

                    droppedItems.push({
                        id: master.id,
                        name: master.name,
                        type: type,
                        base: master.base || 0,
                        instanceId: Date.now() + Math.random().toString(36).substr(2, 5),
                        rarity: master.rarity || 0,
                        color: master.color || "#ffffff",
                        icon: master.icon || ""
                    });
                }
            }
        });

        // 3. Si la tirada de cofre fue exitosa pero no cayó ningún ítem, garantizamos el de mayor probabilidad (si hay configurados)
        if (droppedItems.length === 0 && lootDrops.length > 0) {
            let bestDrop = lootDrops[0];
            lootDrops.forEach(d => {
                const dChance = d.chance !== undefined ? d.chance : 0.1;
                const bestChance = bestDrop.chance !== undefined ? bestDrop.chance : 0.1;
                if (dChance > bestChance) {
                    bestDrop = d;
                }
            });

            const master = allShopItems.find(item => item.id === bestDrop.itemId);
            // v620.0: Ojito de visibilidad — ítems hidden no caen como botín garantizado
            if (master && master.hidden) {
                return;
            }
            if (master) {
                let type = (master.type || "utility").toLowerCase();
                const id = master.id.toLowerCase();
                if (id.startsWith('las') || id.startsWith('w')) type = "weapon";
                else if (id.startsWith('sh') || id.startsWith('s')) type = "shield";
                else if (id.startsWith('en') || id.startsWith('e')) type = "engine";

                droppedItems.push({
                    id: master.id,
                    name: master.name,
                    type: type,
                    base: master.base || 0,
                    instanceId: Date.now() + Math.random().toString(36).substr(2, 5),
                    rarity: master.rarity || 0,
                    color: master.color || "#ffffff",
                    icon: master.icon || ""
                });
                // console.log(`[LOOT-SPAWN] Garantizado ítem ${master.id} para evitar cofre vacío.`);
            }
        }

        // Generar el contenedor físico de botín (siempre que la tirada inicial haya tenido éxito)
        if (true) {
            const lootId = `loot_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`;
            const expiresAt = Date.now() + getExpirationMs(state);


            const lootDrop = {
                id: lootId,
                zone: enemy.zone,
                x: Math.floor(enemy.x),
                y: Math.floor(enemy.y),
                items: droppedItems,
                createdAt: Date.now(),
                expiresAt: expiresAt
            };

            state.lootDrops[lootId] = lootDrop;

            // console.log(`[LOOT-SPAWN] Creado botín ${lootId} en zona ${enemy.zone} (${lootDrop.x}, ${lootDrop.y}) con ${droppedItems.length} ítems.`);

            // Notificar a los jugadores de la zona sobre la presencia del botín físico
            io.to(`zone_${enemy.zone}`).emit('lootSpawned', {
                id: lootId,
                x: lootDrop.x,
                y: lootDrop.y,
                zone: lootDrop.zone,
                expiresAt: expiresAt
            });
        }
    } catch (err) {
        console.error("[LOOT-SPAWN-ERR] Error al intentar spawnear botín de enemigo:", err);
    }
}

function startCleanupTimer(io, state) {
    // Revisar y purgar botines expirados cada 10 segundos
    setInterval(() => {
        try {
            const now = Date.now();
            Object.keys(state.lootDrops).forEach(lootId => {
                const drop = state.lootDrops[lootId];
                if (drop && now > drop.expiresAt) {
                    // console.log(`[LOOT-CLEANUP] Purgando botín expirado: ${lootId} de zona ${drop.zone}`);
                    io.to(`zone_${drop.zone}`).emit('lootDespawned', { id: lootId });
                    delete state.lootDrops[lootId];
                }
            });
        } catch (err) {
            console.error("[LOOT-CLEANUP-ERR] Error en el intervalo de limpieza de loot:", err);
        }
    }, 10000);
}

function registerLootHandlers(socket, io, state) {
    const { getCategorizedInventory } = require('./inventoryHandlers');

    // INSPECCIONAR EL BOTÍN
    socket.on('inspectLoot', (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        try {
            const { lootId } = data;
            const drop = state.lootDrops[lootId];
            if (!drop) {
                return socket.emit('gameNotification', { msg: 'El botín ya no existe o ha expirado.', type: 'error' });
            }

            const p = state.players[socket.id];
            if (p.zone !== drop.zone) return;

            const dist = Math.hypot(p.x - drop.x, p.y - drop.y);
            if (isServerAuthoritative(state) && dist > getInteractRange(state)) {
                return socket.emit('gameNotification', { msg: 'Estás demasiado lejos para inspeccionar el botín.', type: 'error' });
            }

            // Enviar contenido solo al jugador que está inspeccionando
            socket.emit('lootContent', { lootId, items: drop.items });
        } catch (err) {
            console.error("[LOOT-INSPECT-ERR]", err);
        }
    });

    // RECOGER TODO EL BOTÍN
    socket.on('claimAllLoot', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        try {
            const { lootId } = data;
            const drop = state.lootDrops[lootId];
            if (!drop) {
                return socket.emit('gameNotification', { msg: 'El botín ya no existe o ha expirado.', type: 'error' });
            }

            const p = state.players[socket.id];
            if (p.zone !== drop.zone) return;

            const dist = Math.hypot(p.x - drop.x, p.y - drop.y);
            if (isServerAuthoritative(state) && dist > getInteractRange(state)) {
                return socket.emit('gameNotification', { msg: 'Estás demasiado lejos para recoger el botín.', type: 'error' });
            }


            const user = getPlayerRAMAdapter(p);
            if (!user) return;
 
            let claimedCount = 0;
            const { addItemToInventory } = require('./inventoryHandlers');

            while (drop.items.length > 0) {
                const item = drop.items[0];
                const amount = parseInt(item.amount) || 1;
                const remaining = addItemToInventory(user, item, state.SERVER_CONFIG, amount);
                if (remaining === 0) {
                    drop.items.shift();
                    claimedCount += amount;
                } else if (remaining < amount) {
                    item.amount = remaining;
                    claimedCount += (amount - remaining);
                    break;
                } else {
                    break;
                }
            }

            if (claimedCount === 0) {
                return socket.emit('gameNotification', { msg: `INVENTARIO LLENO: Desbloquea más slots.`, type: 'error' });
            }

            user.markModified('gameData.inventory');
            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;
 
            // Sincronizar RAM local
            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));
 
            console.log(`[LOOT-CLAIM] Jugador ${p.user} recogió ${claimedCount} ítems del botín ${lootId}.`);
 
            // Notificar éxito al cliente y actualizar su inventario
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);
 
            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });
 
            if (drop.items.length === 0) {
                socket.emit('gameNotification', { msg: '¡Has recogido todos los ítems!', type: 'success' });
                // Remover el botín de la zona y de memoria
                io.to(`zone_${drop.zone}`).emit('lootDespawned', { id: lootId });
                delete state.lootDrops[lootId];
            } else {
                socket.emit('gameNotification', { msg: `Recogidos ${claimedCount} ítems. Inventario lleno, quedaron más en el cofre.`, type: 'warning' });
                // Enviar contenido actualizado del botín
                socket.emit('lootContent', { lootId, items: drop.items });
            }
        } catch (err) {
            console.error("[LOOT-CLAIM-ALL-ERR]", err);
        }
    });

    // RECOGER UN ÍTEM INDIVIDUAL
    socket.on('claimLootItem', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        try {
            const { lootId, instanceId } = data;
            const drop = state.lootDrops[lootId];
            if (!drop) {
                return socket.emit('gameNotification', { msg: 'El botín ya no existe o ha expirado.', type: 'error' });
            }

            const p = state.players[socket.id];
            if (p.zone !== drop.zone) return;

            const dist = Math.hypot(p.x - drop.x, p.y - drop.y);
            if (isServerAuthoritative(state) && dist > getInteractRange(state)) {
                return socket.emit('gameNotification', { msg: 'Estás demasiado lejos para recoger el ítem.', type: 'error' });
            }

            const itemIndex = drop.items.findIndex(item => item.instanceId === instanceId);
            if (itemIndex === -1) {
                return socket.emit('gameNotification', { msg: 'El ítem ya no se encuentra en el botín.', type: 'error' });
            }

            const user = getPlayerRAMAdapter(p);
            if (!user) return;
 
            // Validar espacio de inventario e intentar añadir el ítem
            const { addItemToInventory } = require('./inventoryHandlers');
            const item = drop.items[itemIndex];
            const amount = parseInt(item.amount) || 1;
            const remaining = addItemToInventory(user, item, state.SERVER_CONFIG, amount);
            
            if (remaining > 0) {
                if (remaining < amount) {
                    item.amount = remaining;
                    user.markModified('gameData.inventory');
                    user.markModified('gameData');
                    await user.save();
                    socket.dbUser = user;
                    p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));
                    
                    const eByShipObj = {};
                    if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                    else Object.assign(eByShipObj, user.gameData.equippedByShip);
                    socket.emit('inventoryData', {
                        player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
                    });
                    socket.emit('lootContent', { lootId, items: drop.items });
                    return socket.emit('gameNotification', { msg: `Recogido parcialmente. Inventario lleno.`, type: 'warning' });
                }
                return socket.emit('gameNotification', { msg: `INVENTARIO LLENO: Desbloquea más slots para recoger este ítem.`, type: 'error' });
            }

            // Extraer ítem del drop por completo
            drop.items.splice(itemIndex, 1);
            user.markModified('gameData.inventory');
            user.markModified('gameData');
            await user.save();
            socket.dbUser = user;

            // Sincronizar RAM
            p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));

            console.log(`[LOOT-CLAIM] Jugador ${p.user} recogió ítem ${item.name} (${instanceId}) del botín ${lootId}.`);

            // Responder e inventorySync
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            else Object.assign(eByShipObj, user.gameData.equippedByShip);

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });
            socket.emit('gameNotification', { msg: `Recogido: ${item.name}`, type: 'success' });

            if (drop.items.length === 0) {
                // Si ya no quedan ítems, remover el botín
                io.to(`zone_${drop.zone}`).emit('lootDespawned', { id: lootId });
                delete state.lootDrops[lootId];
            } else {
                // Si aún quedan, notificar la lista actualizada al jugador
                socket.emit('lootContent', { lootId, items: drop.items });
            }
        } catch (err) {
            console.error("[LOOT-CLAIM-ITEM-ERR]", err);
        }
    });
}

module.exports = {
    spawnLootFromEnemy,
    startCleanupTimer,
    registerLootHandlers
};
