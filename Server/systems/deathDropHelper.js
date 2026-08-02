const User = require('../models/User');
const { sendInventoryData } = require('./inventoryHandlers');
const { calculateFinalStats } = require('./statCalculator');

/**
 * Procesa la pérdida de todos los ítems equipados e inventario si el mapa tiene activado 'full_drop',
 * o solo inventario si es 'partial_drop'. Lee directamente de la base de datos para asegurar consistencia.
 * @param {Object} p Objeto del jugador en memoria (state.players[socket.id])
 * @param {Object} io Objeto global de socket.io
 * @param {Object} state Estado global del servidor
 */
async function checkAndProcessDeathDrop(p, io, state) {
    if (!p || p.isDeadDropProcessed) return;

    const mapCfg = state.SERVER_CONFIG?.mapsConfig?.[p.zone];
    const isFullDrop = mapCfg?.pvpMode === 'full_drop';
    const isPartialDrop = mapCfg?.pvpMode === 'partial_drop';
    const isInferno = mapCfg?.pvpMode === 'inferno';

    if (isFullDrop || isPartialDrop || isInferno) {
        p.isDeadDropProcessed = true; // Evitar procesamiento duplicado

        try {
            const user = await User.findById(p.dbId || p.id);
            if (!user) return;

            const droppedItems = [];
            
            // 1. Recolectar del inventario del usuario en DB (Siempre)
            if (user.gameData.inventory && Array.isArray(user.gameData.inventory)) {
                user.gameData.inventory.forEach(item => {
                    if (item) droppedItems.push(item);
                });
            }
            
            // 2. Recolectar de ítems equipados del usuario en DB (full_drop e inferno)
            const dropEquipped = isFullDrop || isInferno;
            if (dropEquipped) {
                const currentShipIdStr = String(user.gameData.currentShipId || 1);
                
                // Intentar leer de equippedByShip en la DB
                let shipEquip = { w: [], s: [], e: [], x: [] };
                if (user.gameData.equippedByShip) {
                    if (typeof user.gameData.equippedByShip.get === 'function') {
                        shipEquip = user.gameData.equippedByShip.get(currentShipIdStr) || shipEquip;
                    } else {
                        shipEquip = user.gameData.equippedByShip[currentShipIdStr] || shipEquip;
                    }
                }
                
                // Fallback a equipped si ebs está vacío
                const hasEquippedItems = (shipEquip.w && shipEquip.w.length > 0) || (shipEquip.s && shipEquip.s.length > 0) || (shipEquip.e && shipEquip.e.length > 0);
                if (!hasEquippedItems && user.gameData.equipped) {
                    shipEquip = user.gameData.equipped;
                }

                const slots = ['w', 's', 'e', 'x'];
                slots.forEach(slot => {
                    if (shipEquip[slot] && Array.isArray(shipEquip[slot])) {
                        shipEquip[slot].forEach(item => {
                            if (item) droppedItems.push(item);
                        });
                    }
                });
            }

            // 3. Si hay ítems, spawnearlos en el suelo como un cofre físico interactivo
            if (droppedItems.length > 0) {
                const lootId = `loot_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`;
                const expirationMs = state.SERVER_CONFIG?.lootConfig?.expirationMs || 300000;
                const expiresAt = Date.now() + expirationMs;

                const lootDrop = {
                    id: lootId,
                    zone: p.zone,
                    x: Math.floor(p.x),
                    y: Math.floor(p.y),
                    items: JSON.parse(JSON.stringify(droppedItems)),
                    createdAt: Date.now(),
                    expiresAt: expiresAt
                };

                state.lootDrops[lootId] = lootDrop;
                
                io.to(`zone_${p.zone}`).emit('lootSpawned', {
                    id: lootId,
                    x: lootDrop.x,
                    y: lootDrop.y,
                    zone: lootDrop.zone,
                    expiresAt: expiresAt
                });
                
                console.log(`[PVP-DROP] Jugador ${p.user} dropeó ${droppedItems.length} ítems en zona ${p.zone} (${mapCfg.pvpMode})`);
            }

            // 4. Vaciar en RAM
            p.inventory = [];
            if (dropEquipped) {
                p.equipped = { w: [], s: [], e: [], x: [] };
                const currentShipIdStr = String(p.currentShipId || user.gameData.currentShipId || 1);
                if (p.equippedByShip) {
                    p.equippedByShip[currentShipIdStr] = { w: [], s: [], e: [], x: [] };
                }
                // v309.2: Recalcular stats tras perder equipamiento y sincronizar con la zona
                calculateFinalStats(p, state.SERVER_CONFIG);
                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: p.socketId,
                    hp: p.hp,
                    shield: p.shield,
                    maxHp: p.maxHp,
                    maxShield: p.maxShield
                });
            }

            // 5. Vaciar en la Base de Datos (MongoDB) de forma autoritativa
            user.gameData.inventory = [];
            if (dropEquipped) {
                user.gameData.equipped = { w: [], s: [], e: [], x: [] };
                
                const currentShipIdStr = String(user.gameData.currentShipId || 1);
                if (user.gameData.equippedByShip) {
                    if (user.gameData.equippedByShip instanceof Map) {
                        user.gameData.equippedByShip.set(currentShipIdStr, { w: [], s: [], e: [], x: [] });
                    } else {
                        user.gameData.equippedByShip[currentShipIdStr] = { w: [], s: [], e: [], x: [] };
                    }
                    user.markModified('gameData.equippedByShip');
                }
                user.markModified('gameData.equipped');
            }

            // 6. MODO INFIERNO: destruir la nave actual y forzar respawn al lobby
            if (isInferno) {
                const defaultShipId = state.SERVER_CONFIG?.pilotConfig?.startingShipId ?? 1;
                const currentShip = user.gameData.currentShipId || defaultShipId;
                const shipModel = state.SERVER_CONFIG?.shipModels?.find(s => s.id === currentShip);
                const shipName = shipModel?.name || `Nave #${currentShip}`;

                // Remover la nave actual de ownedShips (excepto si es la default)
                if (currentShip !== defaultShipId && user.gameData.ownedShips.includes(currentShip)) {
                    user.gameData.ownedShips = user.gameData.ownedShips.filter(id => id !== currentShip);
                    user.markModified('gameData.ownedShips');

                    // Limpiar equipamiento asociado a esa nave
                    if (user.gameData.equippedByShip) {
                        if (user.gameData.equippedByShip instanceof Map) {
                            user.gameData.equippedByShip.delete(String(currentShip));
                        } else {
                            delete user.gameData.equippedByShip[String(currentShip)];
                        }
                        user.markModified('gameData.equippedByShip');
                    }

                    console.log(`[INFERNO] Nave ${shipName} (ID: ${currentShip}) destruida permanentemente a ${p.user}`);
                }

                // Reset a la nave por defecto
                user.gameData.currentShipId = defaultShipId;
                const defaultShipKey = String(defaultShipId);
                user.markModified('gameData.currentShipId');

                // Asegurar que la nave default tenga entrada en equippedByShip
                if (user.gameData.equippedByShip) {
                    if (user.gameData.equippedByShip instanceof Map) {
                        if (!user.gameData.equippedByShip.has(defaultShipKey)) {
                            user.gameData.equippedByShip.set(defaultShipKey, { w: [], s: [], e: [], x: [] });
                        }
                    } else {
                        if (!user.gameData.equippedByShip[defaultShipKey]) {
                            user.gameData.equippedByShip[defaultShipKey] = { w: [], s: [], e: [], x: [] };
                        }
                    }
                    user.markModified('gameData.equippedByShip');
                }

                // Forzar respawn al lobby
                const lobbyZone = state.SERVER_CONFIG?.pilotConfig?.startingMapId ?? 1;
                const oldZone = p.zone;

                user.gameData.zone = lobbyZone;
                p.zone = lobbyZone;
                p.x = 2000;
                p.y = 2000;

                // Aplicar stats de la nave default
                p.currentShipId = defaultShipId;
                p.type = defaultShipId;
                calculateFinalStats(p, state.SERVER_CONFIG);

                // Emitir eventos de destrucción de nave al cliente y teletransportar
                const sock = io.sockets.sockets.get(p.socketId);
                if (sock) {
                    // Notificar destrucción de nave
                    sock.emit('shipDestroyed', {
                        shipId: currentShip,
                        shipName: shipName,
                        newShipId: defaultShipId
                    });
                    sock.emit('gameNotification', {
                        msg: `💀 ¡INFIERNO! Tu nave ${shipName} ha sido DESTRUIDA. Has perdido todo.`,
                        type: 'error'
                    });

                    // Teletransportar al lobby
                    sock.leave(`zone_${oldZone}`);
                    sock.join(`zone_${lobbyZone}`);

                    if (state.playersByZone[oldZone] && state.playersByZone[oldZone][p.socketId]) {
                        delete state.playersByZone[oldZone][p.socketId];
                    }
                    if (!state.playersByZone[lobbyZone]) {
                        state.playersByZone[lobbyZone] = {};
                    }
                    state.playersByZone[lobbyZone][p.socketId] = p;

                    sock.emit('changeZoneDone', { zoneId: lobbyZone, x: p.x, y: p.y });
                    sock.to(`zone_${oldZone}`).emit('playerDisconnected', p.socketId);
                    sock.to(`zone_${lobbyZone}`).emit('newPlayer', {
                        id: p.socketId,
                        user: p.user,
                        x: p.x,
                        y: p.y,
                        hp: p.hp,
                        maxHp: p.maxHp,
                        sh: p.shield,
                        maxSh: p.maxShield,
                        zone: lobbyZone
                    });

                    // Resetear estado de muerte
                    p.isDead = false;
                    p.isDeadDropProcessed = false;
                }
            }
            
            user.markModified('gameData.inventory');
            user.markModified('gameData');
            await user.save();

            // Sincronizar visualmente al cliente local su inventario vacío
            const socket = io.sockets.sockets.get(p.socketId);
            if (socket) {
                sendInventoryData(socket, user);
            }
        } catch (err) {
            console.error("[PVP-DROP] Error al procesar muerte y vaciar base de datos:", err);
        }
    }
}

const entryInvulTimeouts = new Map();

/**
 * Aplica reglas de zona al entrar a un mapa (PvP forzado, invulnerabilidad al ingresar).
 * @param {Object} p Objeto del jugador en memoria
 * @param {Object} socket Socket del jugador
 * @param {Object} io Objeto global de socket.io
 * @param {Object} state Estado global del servidor
 */
function applyZoneRules(p, socket, io, state) {
    if (!p || !state.SERVER_CONFIG) return;

    const mapCfg = state.SERVER_CONFIG.mapsConfig?.[p.zone];
    if (mapCfg) {
        // A. Forzar PvP si es obligatorio
        const isPvPMandatory = mapCfg.pvpMode === 'mandatory' || mapCfg.pvpMode === 'full_drop' || mapCfg.pvpMode === 'partial_drop' || mapCfg.pvpMode === 'inferno';
        if (isPvPMandatory) {
            p.pvpEnabled = true;
            console.log(`[PVP-RULES] PvP forzado a ACTIVO para ${p.user} en zona ${p.zone}`);
        }

        // B. Aplicar invulnerabilidad al entrar si está configurado
        if (mapCfg.giveInvulnerabilityOnEntry) {
            const durationMs = parseInt(mapCfg.invulnerabilityDuration) || 5000;
            p.isInvulnerable = true;
            
            // Enviamos notificación informativa al jugador local
            socket.emit('gameNotification', {
                msg: `🔒 Invulnerabilidad activada por ${(durationMs / 1000).toFixed(1)}s`,
                type: 'info'
            });

            if (entryInvulTimeouts.has(socket.id)) {
                clearTimeout(entryInvulTimeouts.get(socket.id));
            }

            const timeoutRef = setTimeout(() => {
                p.isInvulnerable = false;
                
                // Emitimos actualización correctiva mediante playerStatSync para no crear ghost players
                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: socket.id,
                    isInvulnerable: false
                });
                
                socket.emit('gameNotification', {
                    msg: `🔓 Invulnerabilidad desactivada`,
                    type: 'warning'
                });
                entryInvulTimeouts.delete(socket.id);
            }, durationMs);

            entryInvulTimeouts.set(socket.id, timeoutRef);
        }
    }
}

module.exports = {
    checkAndProcessDeathDrop,
    applyZoneRules
};
