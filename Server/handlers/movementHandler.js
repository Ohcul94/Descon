const Logger = require('../utils/logger');
const { checkCombatLock } = require('../systems/inventoryHandlers');

const { normalizeZone } = require('../utils/zoneUtils');

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

// v530.0: Obtener límites lógicos del mapa (borde de nebulosa) para clamp autoritativo
// v531.0: NEBULOSA FANTASMA — clamp desactivado server-side (solo visual para referencia de pixeles AdminDash)
const ENABLE_BORDER_CLAMP = false; // false = fantasma visual-only (paso libre), true = choque duro autoritativo
const getMapBounds = (zone, state) => {
    const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
    const zStr = String(zone);
    // 1) MapsConfig directo (la mayoría de mapas estáticos y extracción)
    if (maps[zStr]) {
        const cfg = maps[zStr];
        const w = parseFloat(cfg.width);
        const h = parseFloat(cfg.height);
        if (!isNaN(w) && w > 0) {
            return { w: w, h: (!isNaN(h) && h > 0) ? h : w };
        }
    }
    // 2) GameModes (altar, arenas, extracción) - para zonas especiales o fallback
    const gm = state.SERVER_CONFIG && state.SERVER_CONFIG.gameModes;
    if (gm) {
        if (gm.extraction && Array.isArray(gm.extraction.maps) && gm.extraction.maps.map(n => String(n)).includes(zStr)) {
            return { w: parseFloat(gm.extraction.width) || 20000, h: parseFloat(gm.extraction.height) || 20000 };
        }
        if (gm.altar_defense && Array.isArray(gm.altar_defense.maps) && gm.altar_defense.maps.map(n => String(n)).includes(zStr)) {
            return { w: parseFloat(gm.altar_defense.width) || 10000, h: parseFloat(gm.altar_defense.height) || 10000 };
        }
        if (gm.arenas) {
            if (gm.arenas.mapConfigs && gm.arenas.mapConfigs[zStr]) {
                const ac = gm.arenas.mapConfigs[zStr];
                return { w: parseFloat(ac.width) || 10000, h: parseFloat(ac.height) || 10000 };
            }
            if (Array.isArray(gm.arenas.maps) && gm.arenas.maps.map(n => String(n)).includes(zStr)) {
                return { w: 10000, h: 10000 };
            }
        }
    }
    // 3) Zonas string dinámicas
    if (typeof zone === 'string') {
        if (zone.startsWith('arena_')) return { w: 10000, h: 10000 };
        if (zone.startsWith('extract_')) return { w: parseFloat(maps['10'] && maps['10'].width) || 20000, h: parseFloat(maps['10'] && maps['10'].height) || 20000 };
        if (zone.startsWith('dungeon')) return { w: 4000, h: 4000 };
    }
    return { w: 4000, h: 4000 };
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

        // v421.0: Descartar movimiento si el servidor sabe que el jugador está muerto
        if (p.isDead) return;

        // v311.0: Filtrar movimientos desactualizados si la zona del cliente no coincide con la del servidor.
        // Esto evita desincronizaciones cuando se procesan paquetes viejos en vuelo durante un cambio de zona.
        if (movementData.zone !== undefined && normalizeZone(movementData.zone) !== normalizeZone(p.zone)) {
            return;
        }

        if (p.isFrozen) {
            movementData.x = p.x;
            movementData.y = p.y;
        }
        // ==== CASTEO: cancelar si CC activo ====
        if (p.pendingCast) {
            const nowCC = Date.now();
            const isCC = !!(p.isStunned || (p.stunEndTime && nowCC < p.stunEndTime) || p.isFeared || (p.fearEndTime && nowCC < p.fearEndTime) || p.isPolymorphed || (p.polyEndTime && nowCC < p.polyEndTime) || p.isDead);
            if (isCC) {
                if (p.pendingCastTimeout) { try{ clearTimeout(p.pendingCastTimeout);}catch(e){} }
                const was = p.pendingCast;
                p.pendingCast = null;
                p.pendingCastTimeout = null;
                const info = { id: socket.id, type: was.type };
                // broadcast cancel (best effort)
                try {
                    const isSpecialCC = typeof p.zone === 'string' && (p.zone.startsWith('arena_') || p.zone.startsWith('extract_') || p.zone.startsWith('dungeon'));
                    if (isSpecialCC) socket.to(`zone_${p.zone}`).emit('playerCastCancel', info);
                    else {
                        const CELL=500; const fCx=Math.floor(p.x/CELL); const fCy=Math.floor(p.y/CELL);
                        const zonePlayers=state.playersByZone[p.zone]||{};
                        Object.values(zonePlayers).forEach(other=>{
                            if(other.socketId===socket.id) return;
                            const oCx=Math.floor(other.x/CELL); const oCy=Math.floor(other.y/CELL);
                            if(Math.abs(fCx-oCx)<=3 && Math.abs(fCy-oCy)<=3) io.to(other.socketId).emit('playerCastCancel', info);
                        });
                    }
                    socket.emit('castCancelled', { reason: 'cc' });
                } catch(e){}
            }
        }
        // ==== CASTEO: congelar movimiento (Anti-Hack) ====
        if (p.pendingCast) {
            const nowC = Date.now();
            const castEnd = p.pendingCast.startTime + p.pendingCast.duration;
            if (nowC < castEnd) {
                // durante casteo, forzar posicion al punto de inicio del casteo
                movementData.x = p.pendingCast.x;
                movementData.y = p.pendingCast.y;
                // fijar rotacion al angulo de casteo (sincronizar hacia el disparo)
                if (p.pendingCast.angle !== undefined) {
                    movementData.rotation = p.pendingCast.angle;
                }
                // opcional: mantener lastPos sin actualizar para no ensuciar trail
                // no aplicar anti-speedhack para este frame (ya esta congelado)
            } else {
                // casteo expirado sin disparo, limpiar
                if (p.pendingCastTimeout) { try{ clearTimeout(p.pendingCastTimeout);}catch(e){} }
                p.pendingCast = null;
                p.pendingCastTimeout = null;
            }
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

        // v531.0: Nebulosa FANTASMA — clamp DESACTIVADO (solo visual). Paso libre más allá del borde.
        // Si quieres reactivar el choque duro, cambia ENABLE_BORDER_CLAMP a true.
        if (ENABLE_BORDER_CLAMP) {
            const bounds = getMapBounds(p.zone, state);
            const margin = 25.0; // radio de colisión del jugador (match cliente 80/2 - buffer)
            const clampedX = Math.max(margin, Math.min(bounds.w - margin, Number(movementData.x)));
            const clampedY = Math.max(margin, Math.min(bounds.h - margin, Number(movementData.y)));
            if (clampedX !== Number(movementData.x) || clampedY !== Number(movementData.y)) {
                // Loguear intento de traspasar nebulosa
                const lastLog = socket.lastBorderLog || 0;
                if (now - lastLog > 3000) {
                    Logger.debug('BORDER', `Jugador ${p.user} intentó cruzar nebulosa en zona ${p.zone}: (${movementData.x},${movementData.y}) -> clamp (${clampedX},${clampedY})`);
                    socket.lastBorderLog = now;
                }
                movementData.x = clampedX;
                movementData.y = clampedY;
                // Informar al cliente que fue corregido (rubberband suave)
                socket.emit('playerStatSync', { id: socket.id, x: clampedX, y: clampedY, hp: p.hp, shield: p.shield, maxHp: p.maxHp, maxShield: p.maxShield });
            }
        }

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
        
        // v410.5: Limpiar de forma autoritativa todos los debuffs y estados alterados en respawn
        p.isPolymorphed = false;
        p.polyEndTime = 0;
        p.polyCanMove = true;
        p.polyCanUseSkills = true;
        
        p.isSlowed = false; p.slowPoints = 0; p.slowEndTime = 0;
        p.isStunned = false; p.stunEndTime = 0;
        p.isBleeding = false; p.bleedEndTime = 0;
        p.isPoisoned = false; p.poisonEndTime = 0;
        p.isFrozen = false; p.freezeEndTime = 0;
        p.isFeared = false; p.fearEndTime = 0;
        p.forcedTarget = null; p.tauntEndTime = 0;
        
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
        
        // v_fix_dead: Validar zona — nunca persistir zonas especiales (arena_, extract_, dungeon_)
        if (respawnData.zone) {
            const rz = Number(respawnData.zone);
            p.zone = (!isNaN(rz) && rz > 0 && rz < 1000) ? rz : 1;
        }
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

            // v421.0: Notificar a los aliados en la zona antigua que este jugador abandonó el mapa al revivir
            socket.to(`zone_${oldZone}`).emit('playerDisconnected', socket.id);

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

        // v410.5: Enviar playerStatSync a toda la zona para forzar el reset visual
        // de la polimorfia (y otros debuffs) en las pantallas de los aliados
        io.to(`zone_${p.zone}`).emit('playerStatSync', {
            id: socket.id,
            isDead: false,
            isPolymorphed: false,
            polymorphed: false,
            polyDuration: 0,
            polyCanMove: true,
            polyCanUseSkills: true,
            isStunned: false,
            isSlowed: false,
            isFrozen: false,
            isFeared: false,
            hp: p.hp,
            shield: p.shield,
            maxHp: p.maxHp,
            maxShield: p.maxShield
        });

        // v410.7: Forzar la limpieza de slow y stun en el cliente local del jugador al revivir
        socket.emit('slowState', { active: false });
        socket.emit('stunState', { active: false });

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
