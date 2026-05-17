const User = require('../models/User');
const Logger = require('../utils/logger');

const normalizeZone = (z) => {
    if (typeof z === 'string') {
        if (!isNaN(z) && z.trim() !== '') {
            return Number(z);
        }
        return z;
    }
    return z;
};

function registerZoneHandlers(socket, io, state) {
    const { players, enemies } = state;

    // v236.40: WARP ADMINISTRATIVO (Teletransporte Instantáneo)
    socket.on('warpToZone', async (data) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];
        if (p.user !== "Caelli94") return; // Protección Admin

        const newZone = data.zone || 1;
        const oldZone = p.zone;
        console.log(`[ADMIN-WARP] ${p.user} saltando a Zona ${newZone}`);

        socket.leave(`zone_${oldZone}`);
        socket.join(`zone_${newZone}`);

        p.zone = newZone;
        p.x = 2000;
        p.y = 2000;

        // v238.41: Persistencia Administrativa Instantánea
        try {
            await User.updateOne({ _id: socket.dbUser._id }, { $set: { "gameData.zone": newZone } });
        } catch (e) { console.error("Error persistiendo Warp:", e); }

        socket.emit('changeZoneDone', newZone);
        socket.to(`zone_${oldZone}`).emit('playerDisconnected', socket.id);
        socket.to(`zone_${newZone}`).emit('newPlayer', { ...p, id: socket.id, spheres: p.spheres });

        // --- SYNC: Recopilar otros jugadores en la nueva zona ---
        const currentPlayersInZone = {};
        Object.keys(players).forEach(pId => {
            const otherP = players[pId];
            if (normalizeZone(otherP.zone) === normalizeZone(newZone) && pId !== socket.id) {
                const { ai, ...cleanP } = otherP;
                currentPlayersInZone[pId] = {
                    ...cleanP,
                    id: pId,
                    zone: newZone,
                    maxHp: otherP.maxHp || 2000,
                    maxShield: otherP.maxShield || 1000,
                    spheres: otherP.spheres || []
                };
            }
        });

        // --- SYNC: Recopilar enemigos en la nueva zona ---
        const zoneEnemies = {};
        Object.keys(enemies).forEach(eid => {
            const e = enemies[eid];
            if (normalizeZone(e.zone) === normalizeZone(newZone)) {
                const { ai, ...cleanData } = e;
                zoneEnemies[eid] = cleanData;
            }
        });

        setTimeout(() => {
            if (socket.connected) {
                socket.emit('currentPlayers', currentPlayersInZone);
                socket.emit('currentEnemies', zoneEnemies);
            }
        }, 300);
    });

    // CAMBIO DE ZONA TRADICIONAL
    socket.on('changeZone', async (zoneId) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];

        // v2.9: Si venía de una extracción activa, limpiarlo en ExtractionManager y forzar retorno seguro
        if (p.isExtracting) {
            const extractionManager = require('../systems/extractionManager');
            extractionManager.returnToHangar(socket.id, p.zone);
            return;
        }

        const oldZone = (p.zone !== undefined ? p.zone : 1);
        if (Number(oldZone) === Number(zoneId)) return; // Evitar cobro si ya está ahí

        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            // Leer configuración de mapas (si existe)
            let COST = (Number(zoneId) > 2) ? 10 : 0;
            let minLevel = 1;
            
            if (state.SERVER_CONFIG.mapsConfig && state.SERVER_CONFIG.mapsConfig[zoneId]) {
                COST = state.SERVER_CONFIG.mapsConfig[zoneId].warpCost || 0;
                minLevel = state.SERVER_CONFIG.mapsConfig[zoneId].minLevel || 1;
            }

            // Validar Nivel
            if (user.gameData.level < minLevel) {
                socket.emit('authError', `REQUIERES NIVEL ${minLevel} PARA ENTRAR A ESTE SECTOR`);
                return;
            }

            // v215.50: Cobro dinámico por Salto de Sector
            if (user.gameData.ohcu < COST) {
                socket.emit('authError', 'OHCU INSUFICIENTES PARA EL SALTO');
                return;
            }

            user.gameData.ohcu -= COST;
            user.gameData.zone = zoneId; // v238.42: Persistencia de Sector en Salto
            user.markModified('gameData.ohcu');
            user.markModified('gameData.zone');
            await user.save();

            socket.dbUser = user;
            p.ohcu = user.gameData.ohcu;

            // Notificar nuevo balance y confirmar cambio de zona para limpieza de entidades
            socket.emit('inventoryData', { player: user.gameData });
            socket.emit('changeZoneDone', zoneId);

            const newSize = (Number(zoneId) === 1 ? 2000 : 4000);

            // Gestión de Habitaciones v75.0 (Optimization)
            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${zoneId}`);

            p.zone = zoneId;
            p.x = newSize / 2;
            p.y = newSize / 2;

            Logger.info('ZONE', `Jugador [${p.user}] saltó al Sector [${zoneId}] - Costo: ${COST} OHCU`);

            // Avisar a la vieja zona que se fue y a la nueva que llegó
            socket.to(`zone_${oldZone}`).emit('playerDisconnected', socket.id);
            socket.to(`zone_${zoneId}`).emit('newPlayer', { ...p, id: socket.id, spheres: p.spheres });

            // v225.70: LIMPIEZA DE RESIDUOS - Solo borrar si están muertos o corruptos (Evita resetear bichos vivos)
            if (Number(zoneId) >= 2) {
                let purgeCount = 0;
                Object.keys(enemies).forEach(eid => {
                    const e = enemies[eid];
                    if (e && e.zone === zoneId && (e.hp <= 0 || !e.ai)) {
                        delete enemies[eid];
                        purgeCount++;
                    }
                });
                if (purgeCount > 0) Logger.debug('CLEANUP', `Zona ${zoneId}: ${purgeCount} residuos purgados.`);
            }

            // v268.60: FIX DEFINITIVO - Sincronizar jugadores actuales en la zona destino
            const currentPlayersInZone = {};
            Object.keys(players).forEach(pId => {
                const otherP = players[pId];
                if (normalizeZone(otherP.zone) === normalizeZone(zoneId) && pId !== socket.id) {
                    const { ai, ...cleanP } = otherP; // Evitar referencias circulares
                    currentPlayersInZone[pId] = {
                        ...cleanP,
                        id: pId,
                        zone: zoneId, // Asegurar que la zona es la correcta
                        maxHp: otherP.maxHp || 2000,
                        maxShield: otherP.maxShield || 1000,
                        spheres: otherP.spheres || []
                    };
                }
            });
            
            const playerCount = Object.keys(currentPlayersInZone).length;
            Logger.debug('ZONE-SYNC', `${p.user} llegó a zona ${zoneId}. Enviando ${playerCount} pilotos en 500ms...`);
            
            // Delay para que el cliente termine de procesar changeZoneDone antes de recibir jugadores
            setTimeout(() => {
                socket.emit('currentPlayers', currentPlayersInZone);
                Logger.debug('ZONE-SYNC', `currentPlayers enviado a ${p.user}: ${playerCount} pilotos.`);
            }, 500);

            // Sincronizar enemigos de la zona (inmediato, el cliente ya sabe manejarlos)
            const zoneEnemies = {};
            Object.keys(enemies).forEach(id => {
                if (normalizeZone(enemies[id].zone) === normalizeZone(zoneId)) {
                    const { ai, ...cleanData } = enemies[id];
                    zoneEnemies[id] = cleanData;
                }
            });
            socket.emit('currentEnemies', zoneEnemies);
            socket.emit('gameNotification', { msg: `Salto exitoso a Sector ${zoneId}`, type: 'success' });

        } catch (e) {
            console.error("Error en changeZone:", e);
        }
    });
}

module.exports = {
    registerZoneHandlers
};
