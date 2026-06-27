const User = require('../models/User');
const { sendInventoryData } = require('./inventoryHandlers');

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

    if (isFullDrop || isPartialDrop) {
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
            
            // 2. Recolectar de ítems equipados del usuario en DB (Solo si es full_drop)
            if (isFullDrop && user.gameData.equipped) {
                const slots = ['w', 's', 'e', 'x'];
                slots.forEach(slot => {
                    if (user.gameData.equipped[slot] && Array.isArray(user.gameData.equipped[slot])) {
                        user.gameData.equipped[slot].forEach(item => {
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
            if (isFullDrop) {
                p.equipped = { w: [], s: [], e: [], x: [] };
            }

            // 5. Vaciar en la Base de Datos (MongoDB) de forma autoritativa
            user.gameData.inventory = [];
            if (isFullDrop) {
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
        const isPvPMandatory = mapCfg.pvpMode === 'mandatory' || mapCfg.pvpMode === 'full_drop' || mapCfg.pvpMode === 'partial_drop';
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
