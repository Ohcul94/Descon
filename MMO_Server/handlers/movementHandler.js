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

function registerMovementHandlers(socket, io, state) {
    const { players, enemies } = state;

    // EVENTO DE MOVIMIENTO DE JUGADORES
    socket.on('playerMovement', async (movementData) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];

        // v200.30: ANTI-SPEEDHACK (Validación de Distancia)
        if (!p.speed && state.SERVER_CONFIG) {
            const ship = state.SERVER_CONFIG.shipModels.find(s => s.id === p.currentShipId);
            p.speed = ship ? ship.speed : 500;
        }

        // v210.0: ANTI-SPEEDHACK (Ajuste de Precisión)
        const dx = movementData.x - p.x;
        const dy = movementData.y - p.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        
        if (distance >= 1100 && !p.justBlinked && !p.isAdmin) { 
            // console.log(`[HACK] Teletransporte detectado en ${p.user}: ${distance}px`);
            return;
        }
        
        if (p.justBlinked) p.justBlinked = false; // Reset tras el bypass

        p.x = movementData.x;
        p.y = movementData.y;
        p.lastPos = { x: p.x, y: p.y }; // v221.60: Sincronía constante de posición
        p.rotation = movementData.rotation;

        if (movementData.selectedAmmo) p.selectedAmmo = movementData.selectedAmmo;

        let oldZone = p.zone !== undefined ? p.zone : 1;
        let targetZone = oldZone;

        // Si el jugador está en Extracción, ignoramos cambios de zona desde playerMovement (el servidor es la autoridad absoluta)
        if (!p.isExtracting && movementData.zone !== undefined) {
            targetZone = movementData.zone;
        }

        // Convertir a número solo si es un string enteramente numérico (para compatibilidad con zonas normales de ID numérico)
        if (typeof oldZone === 'string' && !isNaN(oldZone) && oldZone.trim() !== '') {
            oldZone = Number(oldZone);
        }
        if (typeof targetZone === 'string' && !isNaN(targetZone) && targetZone.trim() !== '') {
            targetZone = Number(targetZone);
        }

        p.zone = targetZone;

        if (oldZone !== targetZone) {
            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${targetZone}`);
            
            // Notificar a los que ya estaban que llegamos nosotros
            const broadcastTarget = `zone_${targetZone}`;
            socket.to(broadcastTarget).emit('newPlayer', { 
                ...p, 
                id: socket.id, 
                spheres: p.spheres,
                isInvisible: p.isInvisible 
            });

            Logger.debug('ZONE-SYNC', `${p.user} entró a zona ${targetZone}. Enviando estado en 350ms...`);
            setTimeout(() => {
                const currentPlayersInZone = {};
                Object.keys(players).forEach(pId => {
                    const otherP = players[pId];
                    if (normalizeZone(otherP.zone) === normalizeZone(targetZone) && pId !== socket.id) {
                        currentPlayersInZone[pId] = {
                            ...otherP,
                            id: pId,
                            zone: targetZone,
                            maxHp: otherP.maxHp || 2000,
                            maxShield: otherP.maxShield || 1000,
                            spheres: otherP.spheres
                        };
                    }
                });

                const cleanEnemiesInZone = {};
                Object.values(enemies).forEach(e => {
                    if (normalizeZone(e.zone) === normalizeZone(targetZone)) {
                        const { ai, ...data } = e;
                        cleanEnemiesInZone[e.id] = data;
                    }
                });

                const playerCount = Object.keys(currentPlayersInZone).length;
                const enemyCount = Object.keys(cleanEnemiesInZone).length;
                Logger.debug('ZONE-SYNC', `Enviando a ${p.user}: ${playerCount} jugadores, ${enemyCount} enemigos en zona ${targetZone}`);
                
                socket.emit('currentPlayers', currentPlayersInZone);
                socket.emit('currentEnemies', cleanEnemiesInZone);
            }, 350);
        }

        // v2.2: OPTIMIZACIÓN DE RED POR SECTORES (AOI) EN ZONA DE EXTRACCIÓN O MAPA 10 (VISIBILIDAD ROBUSTA DIRECTA)
        socket.broadcast.to(`zone_${p.zone}`).emit('playerMoved', { 
            ...p, 
            id: socket.id, 
            spheres: p.spheres,
            isInvisible: p.isInvisible 
        });
    });

    // EVENTO DE RESPAWN DE JUGADORES
    socket.on('playerRespawn', (respawnData) => {
        if (!players[socket.id]) return;
        const p = players[socket.id];
        p.isDead = false;
        p.hp = respawnData.hp || p.maxHp || 1000;
        p.shield = respawnData.sh || p.maxShield || 500;
        p.x = respawnData.x || 2000;
        p.y = respawnData.y || 2000;
        
        if (respawnData.zone) p.zone = Number(respawnData.zone);

        const respawnPayload = { ...p, id: socket.id, isDead: false };
        socket.to(`zone_${p.zone}`).emit('newPlayer', respawnPayload);
        socket.to(`zone_${p.zone}`).emit('playerStatSync', {
            id: socket.id,
            hp: p.hp,
            shield: p.shield,
            isDead: false,
            spheres: p.spheres
        });
    });
}

module.exports = {
    registerMovementHandlers
};
