const User = require('../models/User');
const Logger = require('../utils/logger');
const { onZoneChanged } = require('../systems/questHandlers');

// v268.75: Sanitización de datos para evitar Circular References y Crash de Terminal
const getCleanPlayerData = (p, id) => {
    if (!p) return null;
    try {
        // v268.80: Deep clone total para eliminar referencias circulares y evitar el crash de terminal
        return JSON.parse(JSON.stringify({
            id: id,
            user: p.user || 'Unknown',
            x: p.x || 0,
            y: p.y || 0,
            hp: p.hp || 0,
            maxHp: p.maxHp || 0,
            sh: (p.sh !== undefined) ? p.sh : (p.shield || 0),
            maxSh: (p.maxSh !== undefined) ? p.maxSh : (p.maxShield || 0),
            zone: p.zone,
            spheres: p.spheres || [],
            status_effects: p.status_effects || {},
            clanTag: p.clanTag || "",
            currentShipId: p.currentShipId || 1,
            pvpEnabled: !!p.pvpEnabled,
            isInvulnerable: !!p.isInvulnerable
        }));
    } catch (e) {
        console.error("Error sanitizing player data:", e);
        return null;
    }
};

// v268.80: Helper para limpiar datos de enemigos
const getCleanEnemyData = (e, id) => {
    try {
        return JSON.parse(JSON.stringify({
            id: id,
            type: e.type,
            x: e.x,
            y: e.y,
            hp: e.hp,
            maxHp: e.maxHp,
            sh: e.sh || e.shield,
            status_effects: e.status_effects || {},
            isDead: !!e.isDead,
            isInvulnerable: !!e.isInvulnerable
        }));
    } catch (err) {
        return null;
    }
};

const normalizeZone = (z) => {
    if (z === undefined || z === null) return 1;
    if (typeof z === 'string') {
        if (z.startsWith('extract_')) {
            const parts = z.split('_');
            return parseInt(parts[1]) || 10;
        }
        if (z.startsWith('dungeon_') || z.startsWith('dungeon')) {
            return 99;
        }
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
        if (!p.isAdmin) return; // Protección Admin

        const newZone = data.zone || 1;
        const oldZone = p.zone;
        console.log(`[ADMIN-WARP] ${p.user} saltando a Zona ${newZone}`);

        socket.leave(`zone_${oldZone}`);
        socket.join(`zone_${newZone}`);

        // Update playersByZone index
        if (state.playersByZone[oldZone] && state.playersByZone[oldZone][socket.id]) {
            delete state.playersByZone[oldZone][socket.id];
        }
        if (!state.playersByZone[newZone]) {
            state.playersByZone[newZone] = {};
        }
        state.playersByZone[newZone][socket.id] = p;

        p.zone = newZone;
        p.x = 2000;
        p.y = 2000;
        onZoneChanged(socket.id, newZone, state, io);

        // v238.41: Persistencia Administrativa Instantánea
        try {
            await User.updateOne({ _id: socket.dbUser._id }, { $set: { "gameData.zone": newZone } });
        } catch (e) { console.error("Error persistiendo Warp:", e); }

        socket.emit('changeZoneDone', newZone);
        socket.to(`zone_${oldZone}`).emit('playerDisconnected', socket.id);
        socket.to(`zone_${newZone}`).emit('newPlayer', getCleanPlayerData(p, socket.id));

        // v268.66: Sincronización Unificada y Purga Administrativa
        // v2.3: Usar playersByZone en lugar de iterar todos los jugadores — O(N_zona) vs O(N_total)
        const currentPlayersInZone = {};
        const zonePlayersIndex = state.playersByZone[newZone] || {};
        Object.keys(zonePlayersIndex).forEach(pId => {
            if (pId !== socket.id) {
                currentPlayersInZone[pId] = getCleanPlayerData(zonePlayersIndex[pId], pId);
            }
        });

        const zoneEnemies = {};
        let purgeCount = 0;
        Object.keys(enemies).forEach(id => {
            const e = enemies[id];
            if (normalizeZone(e.zone) === normalizeZone(newZone)) {
                if (e.hp <= 0 || e.isDead || !e.ai) {
                    delete enemies[id];
                    purgeCount++;
                } else {
                zoneEnemies[id] = getCleanEnemyData(e, id);
                }
            }
        });

        if (purgeCount > 0) Logger.debug('ADMIN-CLEANUP', `Zona ${newZone}: ${purgeCount} residuos purgados.`);

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

        // v2.9: Si venía de una extracción activa, verificar si está cerca de un portal de escape para darle la victoria
        if (p.isExtracting) {
            const extractionManager = require('../systems/extractionManager');
            const match = extractionManager.matches.get(p.zone);
            let nearPortal = false;
            
            if (match) {
                for (const ep of match.extractionPoints) {
                    const dx = p.x - ep.x;
                    const dy = p.y - ep.y;
                    const distSq = dx * dx + dy * dy;
                    const checkRadius = ep.proximityRadius || ep.radius || 150;
                    
                    if (distSq < checkRadius * checkRadius) {
                        nearPortal = true;
                        break;
                    }
                }
            }
            
            if (nearPortal) {
                // Extracción exitosa hacia la zona/mapa seleccionada
                await extractionManager.handleExtractionSuccess(socket.id, p.zone, zoneId);
            } else {
                // Cancelado/Fuerza bruta: devuelto al lobby sin items de raid
                extractionManager.returnToHangar(socket.id, p.zone);
            }
            return;
        }

        const oldZone = (p.zone !== undefined ? p.zone : 1);
        if (Number(oldZone) === Number(zoneId)) return; // Evitar cobro si ya está ahí

        // Bloqueo de salto manual a mapas de evento (Extracción)
        if (Number(zoneId) === 10 || Number(zoneId) === 11) {
            socket.emit('authError', 'ACCESO RESTRINGIDO: Ingreso exclusivo mediante evento de extracción (F2)');
            return;
        }

        // Bloqueo de entrada a Housing (Hangar Privado) desde zonas no permitidas
        if (Number(zoneId) === 100) {
            const config = state.SERVER_CONFIG?.housingConfig || {};
            const allowedZones = config.allowedZones || [1]; // Por defecto solo lobby (1)
            if (!allowedZones.includes(Number(oldZone))) {
                socket.emit('authError', 'NO SE PERMITE EL ACCESO AL HANGAR PRIVADO DESDE ESTE SECTOR');
                return;
            }
        }

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

            // v268.80: Clonación profunda para evitar Circular References y crash de terminal
            const inventoryCopy = JSON.parse(JSON.stringify(user.gameData));
            socket.emit('inventoryData', { player: inventoryCopy });
            socket.emit('changeZoneDone', zoneId);

            const newSize = (Number(zoneId) === 1 ? 2000 : 4000);

            // Gestión de Habitaciones v75.0 (Optimization)
            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${zoneId}`);

            // Update playersByZone index
            if (state.playersByZone[oldZone] && state.playersByZone[oldZone][socket.id]) {
                delete state.playersByZone[oldZone][socket.id];
            }
            if (!state.playersByZone[zoneId]) {
                state.playersByZone[zoneId] = {};
            }
            state.playersByZone[zoneId][socket.id] = p;

            p.zone = zoneId;
            p.x = newSize / 2;
            p.y = newSize / 2;
            onZoneChanged(socket.id, zoneId, state, io);

            Logger.info('ZONE', `Jugador [${p.user}] saltó al Sector [${zoneId}] - Costo: ${COST} OHCU`);

            // Avisar a la vieja zona que se fue y a la nueva que llegó
            socket.to(`zone_${oldZone}`).emit('playerDisconnected', socket.id);
            socket.to(`zone_${zoneId}`).emit('newPlayer', getCleanPlayerData(p, socket.id));

            // v268.66: Sincronización Unificada y Purga de Entidades Muertas
            // v2.3: Usar playersByZone en lugar de iterar todos los jugadores — O(N_zona) vs O(N_total)
            const currentPlayersInZone = {};
            const destZoneIndex = state.playersByZone[zoneId] || {};
            Object.keys(destZoneIndex).forEach(pId => {
                if (pId !== socket.id) {
                    currentPlayersInZone[pId] = getCleanPlayerData(destZoneIndex[pId], pId);
                }
            });

            const zoneEnemies = {};
            let purgeCount = 0;
            Object.keys(enemies).forEach(id => {
                const e = enemies[id];
                if (normalizeZone(e.zone) === normalizeZone(zoneId)) {
                    if (e.hp <= 0 || e.isDead || !e.ai) {
                        delete enemies[id];
                        purgeCount++;
                    } else {
                        zoneEnemies[id] = getCleanEnemyData(e, id);
                    }
                }
            });

            if (purgeCount > 0) Logger.debug('CLEANUP', `Sector ${zoneId}: ${purgeCount} entidades muertas purgadas.`);
            Logger.debug('ZONE-SYNC', `${p.user} en zona ${zoneId}. Enviando ${Object.keys(currentPlayersInZone).length} pilotos y ${Object.keys(zoneEnemies).length} enemigos.`);
            
            setTimeout(() => {
                if (socket.connected) {
                    socket.emit('currentPlayers', currentPlayersInZone);
                    socket.emit('currentEnemies', zoneEnemies);
                }
            }, 500);

            socket.emit('gameNotification', { msg: `Salto exitoso a Sector ${zoneId}`, type: 'success' });
        } catch (e) {
            console.error("Error en changeZone:", e);
        }
    });
}
module.exports = {
    registerZoneHandlers
};
