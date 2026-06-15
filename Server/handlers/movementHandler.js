const Logger = require('../utils/logger');

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

function registerMovementHandlers(socket, io, state) {
    const { players, enemies } = state;

    const getMovementPayload = (p, id) => ({
        id,
        user: p.user || 'Unknown',
        username: p.user || 'Unknown',
        x: Math.round(p.x),
        y: Math.round(p.y),
        rotation: Math.round((p.rotation || 0) * 100) / 100,
        hp: Math.ceil(p.hp || 0),
        shield: Math.ceil(p.shield || 0),
        sh: Math.ceil(p.shield || 0),
        maxHp: p.maxHp || 0,
        maxShield: p.maxShield || 0,
        zone: p.zone,
        clanTag: p.clanTag || "",
        currentShipId: p.currentShipId || 1,
        pvpEnabled: !!p.pvpEnabled,
        isInvisible: !!p.isInvisible,
        isInvulnerable: !!p.isInvulnerable,
        isDead: !!p.isDead
    });

    const getLightMovementPayload = (p, id) => ({
        id,
        x: Math.round(p.x),
        y: Math.round(p.y),
        rotation: Math.round((p.rotation || 0) * 100) / 100,
        hp: Math.ceil(p.hp || 0),
        sh: Math.ceil(p.shield || 0),
        zone: p.zone
    });

    // EVENTO DE MOVIMIENTO DE JUGADORES
    socket.on('playerMovement', async (movementData) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];

        // v311.0: Filtrar movimientos desactualizados si la zona del cliente no coincide con la del servidor.
        // Esto evita desincronizaciones cuando se procesan paquetes viejos en vuelo durante un cambio de zona.
        if (movementData.zone !== undefined && normalizeZone(movementData.zone) !== normalizeZone(p.zone)) {
            return;
        }

        if (p.isFrozen) {
            movementData.x = p.x;
            movementData.y = p.y;
        }

        const now = Date.now();
        if (!p.lastMoveTime) p.lastMoveTime = now;
        const dt = Math.max(0.01, (now - p.lastMoveTime) / 1000);
        p.lastMoveTime = now;

        // v200.30: ANTI-SPEEDHACK (Validación de Distancia)
        if (!p.speed && state.SERVER_CONFIG) {
            const ship = state.SERVER_CONFIG.shipModels.find(s => s.id === p.currentShipId);
            p.speed = ship ? ship.speed : 500;
        }

        // v210.0: ANTI-SPEEDHACK (Ajuste de Precisión Dinámico con Tolerancia)
        const dx = movementData.x - p.x;
        const dy = movementData.y - p.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        
        const shipSpeed = p.speed || 500;
        const maxAllowed = (shipSpeed * dt) + 200; // Tolerancia de 200px por jitter/latencia
        
        if (distance > maxAllowed && !p.justBlinked && !p.isAdmin) { 
            Logger.warn('SECURITY', `Movimiento sospechoso detectado en [${p.user}]: distancia ${Math.round(distance)}px, máx permitido ${Math.round(maxAllowed)}px (dt: ${dt.toFixed(3)}s)`);
            
            // Forzar corrección de posición (rubberbanding) enviando las coordenadas reales del servidor
            socket.emit('playerStatSync', {
                id: socket.id,
                x: p.x,
                y: p.y,
                hp: p.hp,
                shield: p.shield,
                maxHp: p.maxHp,
                maxShield: p.maxShield,
                spheres: p.spheres || []
            });
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
            // v380.0: Actualizar indexación playersByZone
            if (state.playersByZone[oldZone] && state.playersByZone[oldZone][socket.id]) {
                delete state.playersByZone[oldZone][socket.id];
            }
            if (!state.playersByZone[targetZone]) {
                state.playersByZone[targetZone] = {};
            }
            state.playersByZone[targetZone][socket.id] = p;

            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${targetZone}`);
            
            // Notificar a los que ya estaban que llegamos nosotros
            const broadcastTarget = `zone_${targetZone}`;
            socket.to(broadcastTarget).emit('newPlayer', {
                ...getMovementPayload(p, socket.id),
                spheres: p.spheres || []
            });

            Logger.debug('ZONE-SYNC', `${p.user} entró a zona ${targetZone}. Enviando estado en 350ms...`);
            setTimeout(() => {
                const currentPlayersInZone = {};
                Object.keys(players).forEach(pId => {
                    const otherP = players[pId];
                    if (String(otherP.zone) === String(targetZone) && pId !== socket.id) {
                        currentPlayersInZone[pId] = {
                            ...getMovementPayload(otherP, pId),
                            zone: targetZone,
                            spheres: otherP.spheres || []
                        };
                    }
                });

                const cleanEnemiesInZone = {};
                Object.values(enemies).forEach(e => {
                    if (String(e.zone) === String(targetZone)) {
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
        socket.broadcast.to(`zone_${p.zone}`).emit('playerMoved', getLightMovementPayload(p, socket.id));
    });

    // EVENTO DE RESPAWN DE JUGADORES
    socket.on('playerRespawn', (respawnData) => {
        if (!players[socket.id]) return;
        const p = players[socket.id];
        
        const oldZone = p.zone;
        p.isDead = false;
        p.hp = respawnData.hp || p.maxHp || 1000;
        p.shield = respawnData.sh || p.maxShield || 500;
        
        let targetX = respawnData.x || 2000;
        let targetY = respawnData.y || 2000;

        if (typeof p.zone === 'string' && p.zone.startsWith('arena_')) {
            const arenaManager = require('../systems/arenaManager');
            const arenaMatch = arenaManager.matches.get(p.zone);
            if (arenaMatch) {
                let spawn = null;
                const teamSpawns = (arenaMatch.spawns || []).filter(s => s.team === p.team);
                if (teamSpawns.length > 0) {
                    const mode = arenaMatch.spawnMode || 'random';
                    if (mode === 'random') {
                        const rIdx = Math.floor(Math.random() * teamSpawns.length);
                        spawn = teamSpawns[rIdx];
                    } else if (mode === 'closest') {
                        let minDist = Infinity;
                        let selected = teamSpawns[0];
                        teamSpawns.forEach(s => {
                            const dist = Math.hypot(s.x - p.x, s.y - p.y);
                            if (dist < minDist) {
                                minDist = dist;
                                selected = s;
                            }
                        });
                        spawn = selected;
                    } else {
                        spawn = teamSpawns[0];
                    }
                } else {
                    spawn = (p.team === 'red') ? arenaMatch.spawnRed : arenaMatch.spawnBlue;
                }

                const radius = spawn.radius || 200;
                const angle = Math.random() * Math.PI * 2;
                const r = Math.random() * radius;
                targetX = spawn.x + Math.cos(angle) * r;
                targetY = spawn.y + Math.sin(angle) * r;

                // Invulnerabilidad temporal al reaparecer
                const arenasConfig = state.SERVER_CONFIG && state.SERVER_CONFIG.gameModes && state.SERVER_CONFIG.gameModes.arenas;
                const invulMs = (arenasConfig && arenasConfig.respawnInvulnerabilityMs) ? parseInt(arenasConfig.respawnInvulnerabilityMs) : 3000;
                
                p.isInvulnerable = true;
                setTimeout(() => {
                    if (players[socket.id]) {
                        players[socket.id].isInvulnerable = false;
                    }
                }, invulMs);
            }
        }

        p.x = targetX;
        p.y = targetY;
        
        if (respawnData.zone) p.zone = Number(respawnData.zone);
        const targetZone = p.zone;

        if (oldZone !== targetZone) {
            // v380.0: Actualizar indexación playersByZone
            if (state.playersByZone[oldZone] && state.playersByZone[oldZone][socket.id]) {
                delete state.playersByZone[oldZone][socket.id];
            }
            if (!state.playersByZone[targetZone]) {
                state.playersByZone[targetZone] = {};
            }
            state.playersByZone[targetZone][socket.id] = p;

            socket.leave(`zone_${oldZone}`);
            socket.join(`zone_${targetZone}`);
            
            socket.emit('changeZoneDone', { zoneId: targetZone, x: p.x, y: p.y });
            
            // Enviar lista de jugadores y enemigos de la nueva zona
            setTimeout(() => {
                const currentPlayersInZone = {};
                Object.keys(players).forEach(pId => {
                    const otherP = players[pId];
                    if (String(otherP.zone) === String(targetZone) && pId !== socket.id) {
                        currentPlayersInZone[pId] = {
                            ...getMovementPayload(otherP, pId),
                            zone: targetZone,
                            spheres: otherP.spheres || []
                        };
                    }
                });

                const cleanEnemiesInZone = {};
                Object.values(enemies).forEach(e => {
                    if (String(e.zone) === String(targetZone)) {
                        const { ai, ...data } = e;
                        cleanEnemiesInZone[e.id] = data;
                    }
                });
                
                socket.emit('currentPlayers', currentPlayersInZone);
                socket.emit('currentEnemies', cleanEnemiesInZone);
            }, 350);
        }

        const respawnPayload = {
            ...getMovementPayload(p, socket.id),
            isDead: false,
            spheres: p.spheres || []
        };
        socket.to(`zone_${p.zone}`).emit('newPlayer', respawnPayload);
    });
}

module.exports = {
    registerMovementHandlers
};
