const Logger = require('../utils/logger');
const { checkCombatLock } = require('../systems/inventoryHandlers');

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

const getStatusEffects = (ent) => {
    const now = Date.now();
    return {
        slowed: !!(ent.isSlowed || (ent.slowEndTime && now < ent.slowEndTime)),
        stunned: !!(ent.isStunned || (ent.stunEndTime && now < ent.stunEndTime)),
        bleeding: !!(ent.isBleeding || (ent.bleedEndTime && now < ent.bleedEndTime)),
        poisoned: !!(ent.isPoisoned || (ent.poisonEndTime && now < ent.poisonEndTime)),
        frozen: !!(ent.isFrozen || (ent.freezeEndTime && now < ent.freezeEndTime)),
        feared: !!(ent.isFeared || (ent.fearEndTime && now < ent.fearEndTime)),
        provoked: !!(ent.forcedTarget && ent.tauntEndTime && now < ent.tauntEndTime),
        polymorphed: !!(ent.isPolymorphed || (ent.polyEndTime && now < ent.polyEndTime))
    };
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
        isDead: !!p.isDead,
        status_effects: Object.assign(getStatusEffects(p), p.status_effects || {})
    });

    const getLightMovementPayload = (p, id) => ({
        id,
        x: Math.round(p.x),
        y: Math.round(p.y),
        rotation: Math.round((p.rotation || 0) * 100) / 100,
        hp: Math.ceil(p.hp || 0),
        sh: Math.ceil(p.shield || 0),
        zone: p.zone,
        status_effects: Object.assign(getStatusEffects(p), p.status_effects || {})
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
        // Limitamos dt a 0.2s para evitar exploits de lag-switch, y reducimos tolerancia a 100px por seguridad
        const maxAllowed = (shipSpeed * Math.min(0.2, dt)) + 100;
        
        if (distance > maxAllowed && !p.justBlinked && !p.isAdmin) { 
            const lastLog = socket.lastSecurityLogTime || 0;
            if (now - lastLog > 5000) {
                Logger.warn('SECURITY', `Movimiento sospechoso detectado en [${p.user}]: distancia ${Math.round(distance)}px, máx permitido ${Math.round(maxAllowed)}px (dt: ${dt.toFixed(3)}s)`);
                socket.lastSecurityLogTime = now;
            }
            
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

        if (movementData.selectedAmmo && movementData.selectedAmmo !== p.selectedAmmo) {
            const lock = checkCombatLock(p);
            if (lock.locked) {
                socket.emit('gameNotification', { 
                    msg: `ERROR: Sistemas de armas calientes. Espera ${lock.remaining}s para cambiar de munición.`, 
                    type: 'error' 
                });
                socket.emit('playerStatSync', {
                    id: socket.id,
                    selectedAmmo: p.selectedAmmo
                });
            } else {
                p.selectedAmmo = movementData.selectedAmmo;
            }
        }

        // v314.0: Blindaje de Seguridad - El servidor es la única autoridad del mapa.
        // Se elimina el cambio de zona desde playerMovement para evitar teletransporte no autorizado (hacks).
        const currentZone = p.zone;
        const movPayload = getLightMovementPayload(p, socket.id);
        const isSpecialZone = typeof currentZone === 'string' && (currentZone.startsWith('arena_') || currentZone.startsWith('extract_') || currentZone.startsWith('dungeon'));

        if (isSpecialZone) {
            // Broadcast completo a la zona
            socket.broadcast.to(`zone_${currentZone}`).emit('playerMoved', movPayload);
        } else {
            // Obtener rango de visión dinámico configurado en el Admin Dash para el modelo de la nave
            let playerVision = 1500;
            if (state.SERVER_CONFIG && state.SERVER_CONFIG.shipModels) {
                const ship = state.SERVER_CONFIG.shipModels.find(s => s.id === p.currentShipId);
                if (ship && ship.vision !== undefined) {
                    playerVision = Number(ship.vision);
                }
            }

            // AOI dinámico por celdas usando el GridManager espacial
            const CELL_SIZE = 500;
            const cellRange = Math.ceil(playerVision / CELL_SIZE);
            const pCx = Math.floor(p.x / CELL_SIZE);
            const pCy = Math.floor(p.y / CELL_SIZE);

            const notifiedSockets = new Set();

            for (let dx = -cellRange; dx <= cellRange; dx++) {
                for (let dy = -cellRange; dy <= cellRange; dy++) {
                    const key = `${currentZone}_${pCx + dx},${pCy + dy}`;
                    const cell = state.grid.grid.get(key);
                    if (cell && cell.players) {
                        cell.players.forEach(other => {
                            if (other.socketId && other.socketId !== socket.id && !notifiedSockets.has(other.socketId)) {
                                notifiedSockets.add(other.socketId);
                                io.to(other.socketId).emit('playerMoved', movPayload);
                            }
                        });
                    }
                }
            }
        }
    });

    // EVENTO DE RESPAWN DE JUGADORES
    socket.on('playerRespawn', (respawnData) => {
        if (!players[socket.id]) return;
        const p = players[socket.id];
        
        const oldZone = p.zone;
        p.isDead = false;
        p.isDeadDropProcessed = false;
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
