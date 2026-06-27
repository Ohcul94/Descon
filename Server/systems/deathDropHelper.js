const User = require('../models/User');
const { sendInventoryData } = require('./inventoryHandlers');

/**
 * Procesa la pérdida de todos los ítems equipados e inventario si el mapa tiene activado 'full_drop'.
 * @param {Object} p Objeto del jugador en memoria (state.players[socket.id])
 * @param {Object} io Objeto global de socket.io
 * @param {Object} state Estado global del servidor
 */
async function checkAndProcessDeathDrop(p, io, state) {
    if (!p || p.isDeadDropProcessed) return;

    const mapCfg = state.SERVER_CONFIG?.mapsConfig?.[p.zone];
    if (mapCfg?.pvpMode === 'full_drop') {
        p.isDeadDropProcessed = true; // Evitar procesamiento duplicado

        const droppedItems = [];
        
        // 1. Recolectar del inventario del jugador
        if (p.inventory && Array.isArray(p.inventory)) {
            p.inventory.forEach(item => {
                if (item) droppedItems.push(item);
            });
        }
        
        // 2. Recolectar de ítems equipados en la nave actual
        if (p.equipped) {
            const slots = ['w', 's', 'e', 'x'];
            slots.forEach(slot => {
                if (p.equipped[slot] && Array.isArray(p.equipped[slot])) {
                    p.equipped[slot].forEach(item => {
                        if (item) droppedItems.push(item);
                    });
                }
            });
        }

        // 3. Si hay ítems, spawnearlos en el suelo como un cofre físico
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
            
            console.log(`[PVP-DROP] Jugador ${p.user} dropeó ${droppedItems.length} ítems en zona ${p.zone}`);
        }

        // 4. Vaciar en RAM
        p.inventory = [];
        p.equipped = { w: [], s: [], e: [], x: [] };

        // 5. Vaciar en la Base de Datos (MongoDB) de forma autoritativa
        try {
            const user = await User.findById(p.dbId || p.id);
            if (user) {
                user.gameData.inventory = [];
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
                
                user.markModified('gameData.inventory');
                user.markModified('gameData.equipped');
                user.markModified('gameData');
                await user.save();

                // Intentar obtener el socket del jugador para forzar sincronización visual de inventario
                const socket = io.sockets.sockets.get(p.socketId);
                if (socket) {
                    sendInventoryData(socket, user);
                }
            }
        } catch (err) {
            console.error("[PVP-DROP] Error al vaciar base de datos de muerte:", err);
        }
    }
}

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
        const isPvPMandatory = mapCfg.pvpMode === 'mandatory' || mapCfg.pvpMode === 'full_drop';
        if (isPvPMandatory) {
            p.pvpEnabled = true;
            io.to(`zone_${p.zone}`).emit('playerUpdated', {
                id:             socket.id,
                pvpEnabled:     true,
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
                currentShipId:  p.currentShipId || 1,
                isInvisible:    !!p.isInvisible,
                isInvulnerable: !!p.isInvulnerable,
                isDead:         !!p.isDead,
                spheres:        p.spheres || []
            });
            console.log(`[PVP-RULES] PvP forzado a ACTIVO para ${p.user} en zona ${p.zone}`);
        }

        // B. Aplicar invulnerabilidad al entrar si está configurado
        if (mapCfg.giveInvulnerabilityOnEntry) {
            const durationSec = parseInt(mapCfg.invulnerabilityDuration) || 5;
            p.isInvulnerable = true;
            io.to(`zone_${p.zone}`).emit('playerUpdated', {
                id: socket.id,
                isInvulnerable: true
            });
            
            socket.emit('gameNotification', {
                msg: `🔒 Invulnerabilidad activada por ${durationSec}s`,
                type: 'info'
            });

            if (p.invulnerabilityEntryTimeout) {
                clearTimeout(p.invulnerabilityEntryTimeout);
            }

            p.invulnerabilityEntryTimeout = setTimeout(() => {
                p.isInvulnerable = false;
                io.to(`zone_${p.zone}`).emit('playerUpdated', {
                    id: socket.id,
                    isInvulnerable: false
                });
                socket.emit('gameNotification', {
                    msg: `🔓 Invulnerabilidad desactivada`,
                    type: 'warning'
                });
                p.invulnerabilityEntryTimeout = null;
            }, durationSec * 1000);
        }
    }
}

module.exports = {
    checkAndProcessDeathDrop,
    applyZoneRules
};
