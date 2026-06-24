/**
 * GameLoop
 * El corazón del servidor. Maneja los intervalos de tiempo para IA, regeneración y limpieza.
 */
const { handleEnemyDeath } = require('./enemyLogic');
const Logger = require('../utils/logger');
const extractionManager = require('./extractionManager');

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


function startGameLoop(io, state, aiManager) {
    const grid = state.grid;
    
    // v370.1: Monitor de Performance AAA (Profiling con Percentiles)
    let lastTickTime = Date.now();
    let tickCount    = 0;
    let totalTickTime = 0;
    const TICK_SAMPLE_SIZE = 300;            // ~10s de historia a 30fps
    const tickSamples = [];                  // Array circular de duraciones de tick
    let loopCounter  = 0;

    // 1. LOOP DE IA Y MOVIMIENTO (33ms ~ 30fps para suavidad)
    setInterval(() => {
        loopCounter++;
        const start = Date.now();
        const now = start;
        const { enemies, players } = state;

        // v247.11: Actualizar grid para IA y Colisiones (Frecuencia 30fps)
        grid.clear();
        Object.values(players).forEach(p => grid.insert(p, 'player'));
        Object.values(enemies).forEach(e => { if (e.hp > 0) grid.insert(e, 'enemy'); });

        const zoneMoveData = {};
        
        // v268.820: Resetear bonos de aura acumulativos antes de procesar IAs
        Object.values(enemies).forEach(e => { e.auraSpeedBonus = 0; });

        // v312.0: Cachear zonas con agresividad extrema una sola vez por tick en tiempo O(N_mapas)
        const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
        const extremeZones = new Set();
        Object.keys(maps).forEach(zoneId => {
            const mapCfg = maps[zoneId];
            if (mapCfg && mapCfg.ambience && mapCfg.ambience.some(a => a.type === 'extreme_aggression')) {
                extremeZones.add(String(zoneId));
            }
        });

        // LOBBY OPTIMIZATION: determinar la zona de Lobby una sola vez por tick
        const lobbyZoneId = Number(state.SERVER_CONFIG?.pilotConfig?.startingMapId || 1);

        // v2.3: Optimización de IA por Zonas Activas — CPU 0% en zonas sin jugadores
        // Construir Set de zonas con al menos 1 jugador conectado (O(N_mapas_activos))
        const activeZones = new Set();
        Object.keys(state.playersByZone || {}).forEach(zoneId => {
            if (state.playersByZone[zoneId] && Object.keys(state.playersByZone[zoneId]).length > 0) {
                activeZones.add(String(zoneId));
            }
        });

        // v2.4: Despawn de enemigos en zonas vacías para liberar RAM y contadores
        // Si no hay jugadores en una zona, destruimos sus enemigos. AIManager los regenerará al entrar alguien.
        for (const eId in state.enemies) {
            const e = state.enemies[eId];
            if (!activeZones.has(String(e.zone))) {
                if (e.ai && typeof e.ai.cleanUp === 'function') e.ai.cleanUp();
                state.grid.remove(e, 'enemy');
                delete state.enemies[eId];
            }
        }

        for (const id in enemies) {
            const e = enemies[id];

            // Procesar muertes pendientes siempre, sin importar si hay jugadores en la zona
            if (e.hp <= 0) {
                if (!e.isDeadProcessed) handleEnemyDeath(id, io, state);
                continue;
            }

            // LOBBY OPTIMIZATION: saltar IA para enemigos en la zona del Lobby (no hay combate)
            if (Number(e.zone) === lobbyZoneId) continue;

            // v2.3: SKIP completo si la zona del enemigo no tiene jugadores activos
            // Excepción: mecánicas activas o ProwlerAI que deben seguir aunque la zona esté vacía
            const zoneHasPlayers = activeZones.has(String(e.zone));
            const hasActiveMech = e.mechState && Object.values(e.mechState).some(m => m.isActive);
            const isProwler = e.ai && e.ai.constructor.name === 'ProwlerAI';

            if (!zoneHasPlayers && !hasActiveMech && !isProwler) continue;

            // Normalizar zona del enemigo una sola vez por ciclo
            const eZoneNormalized = normalizeZone(e.zone);

            // v262.35: IA Inteligente (LOD) - Forzar actualización si hay mecánicas activas o Agresividad Extrema
            const { players: nearbyPs } = grid.getNearbyEntities(e.x, e.y, e.zone);
            const isNearPlayer = nearbyPs.some(p => normalizeZone(p.zone) === eZoneNormalized);
            
            // v266.999: Detección de Agresividad Extrema para Bypass de LOD (Usando Set optimizado O(1))
            const isExtreme = extremeZones.has(String(e.zone));

            if (isNearPlayer || hasActiveMech || isExtreme || isProwler || (now % 1000 < 33)) {
                if (e.ai) e.ai.update(grid, players, now, io);
            }

            // v247.12: Repulsión física optimizada vía Grid
            const { enemies: nearbyEnemies } = grid.getNearbyEntities(e.x, e.y, e.zone);
            nearbyEnemies.forEach(other => {
                if (e.id !== other.id && eZoneNormalized === normalizeZone(other.zone)) {
                    const dx = e.x - other.x;
                    const dy = e.y - other.y;
                    const d = Math.hypot(dx, dy);
                    if (d > 0 && d < 45) { // Distancia de repulsión
                        const force = (45 - d) * 0.05;
                        e.x += (dx / d) * force;
                        e.y += (dy / d) * force;
                    } else if (d === 0) {
                        // v313.0: Evitar NaN si dos enemigos están en la misma posición exacta
                        const angle = Math.random() * Math.PI * 2;
                        e.x += Math.cos(angle) * 2;
                        e.y += Math.sin(angle) * 2;
                    }
                }
            });
        }


        // v262.30: Broadcast por AOI (Area of Interest) - 5x5 Celdas (2500px x 2500px) a 15 FPS con Delta Compression
        const isNetworkTick = (loopCounter % 2 === 0);

        if (isNetworkTick) {
            Object.values(players).forEach(p => {
                if (!p.zone) return;
                // LOBBY OPTIMIZATION: no enviar enemiesMoved a jugadores del Lobby (no hay IAs activas ahí)
                if (Number(p.zone) === lobbyZoneId) return;

                if (!p._lastSentEnemies) {
                    p._lastSentEnemies = {};
                }
                
                let playerVision = 1300;
                if (state.SERVER_CONFIG && state.SERVER_CONFIG.shipModels) {
                    const ship = state.SERVER_CONFIG.shipModels.find(s => s.id === p.currentShipId);
                    if (ship && ship.vision !== undefined) {
                        playerVision = Number(ship.vision);
                    }
                }

                const currentAoiEnemyIds = new Set();
                const aoiData = {};
                let count = 0;

                // Rango dinámico de celdas a la redonda según el rango de visión de la nave
                const cellRange = Math.ceil(playerVision / 500);
                const cx = Math.floor(p.x / 500);
                const cy = Math.floor(p.y / 500);
                const pZoneNormalized = normalizeZone(p.zone);

                for (let dx = -cellRange; dx <= cellRange; dx++) {
                    for (let dy = -cellRange; dy <= cellRange; dy++) {
                        const key = `${p.zone}_${cx + dx},${cy + dy}`;
                        const cell = grid.grid.get(key);
                        if (cell) {
                            cell.enemies.forEach(e => {
                                if (String(e.zone) === String(p.zone) && enemies[e.id] && enemies[e.id].hp > 0) {
                                    // Filtro de Distancia Euclidiana dinámico según la visión de la nave
                                    const dist = Math.hypot(p.x - e.x, p.y - e.y);
                                    if (dist > playerVision) return;

                                    currentAoiEnemyIds.add(e.id);
                                    
                                    // Precision Reduction: Redondear posiciones y rotaciones para achicar el JSON de red
                                    const roundedX = Math.round(e.x);
                                    const roundedY = Math.round(e.y);
                                    const roundedRot = Math.round(e.rotation * 100) / 100;
                                    const roundedHp = Math.round(e.hp);
                                    const roundedShield = Math.round(e.shield);
                                    const isRamming = !!(e.ai && e.ai.isRamming);
                                    const isInvulnerable = !!e.isInvulnerable;
                                    const isRage = !!e.isRage;
                                    const isInvisible = !!e.isInvisible;
                                    const isCamouflaged = !!e.isCamouflaged;

                                    // Delta Compression: Validar si el estado cambio sustancialmente
                                    const last = p._lastSentEnemies[e.id];
                                    let shouldSend = false;

                                    if (!last) {
                                        shouldSend = true;
                                    } else {
                                        const posChanged = Math.abs(last.x - roundedX) >= 2 || Math.abs(last.y - roundedY) >= 2;
                                        const rotChanged = Math.abs(last.rotation - roundedRot) >= 0.05;
                                        const stateChanged = last.hp !== roundedHp || 
                                                             last.shield !== roundedShield || 
                                                             last.isRage !== isRage || 
                                                             last.isRamming !== isRamming || 
                                                             last.isInvulnerable !== isInvulnerable ||
                                                             last.isInvisible !== isInvisible ||
                                                             last.isCamouflaged !== isCamouflaged;

                                        if (posChanged || rotChanged || stateChanged) {
                                            shouldSend = true;
                                        }
                                    }

                                    if (shouldSend) {
                                        aoiData[e.id] = {
                                            id: e.id,
                                            x: roundedX,
                                            y: roundedY,
                                            rotation: roundedRot,
                                            hp: roundedHp,
                                            shield: roundedShield,
                                            zone: e.zone,
                                            isRage: isRage,
                                            isRamming: isRamming,
                                            isInvulnerable: isInvulnerable,
                                            isInvisible: isInvisible,
                                            isCamouflaged: isCamouflaged
                                        };
                                        if (!last) {
                                            aoiData[e.id].type = e.type;
                                            aoiData[e.id].name = e.name;
                                        }
                                        p._lastSentEnemies[e.id] = {
                                            x: roundedX,
                                            y: roundedY,
                                            rotation: roundedRot,
                                            hp: roundedHp,
                                            shield: roundedShield,
                                            isRage: isRage,
                                            isRamming: isRamming,
                                            isInvulnerable: isInvulnerable,
                                            isInvisible: isInvisible,
                                            isCamouflaged: isCamouflaged
                                        };
                                        count++;
                                    }
                                }
                            });
                        }
                    }
                }

                // Cleanup de cache RAM para enemigos fuera del rango del jugador
                for (const cachedId in p._lastSentEnemies) {
                    if (!currentAoiEnemyIds.has(Number(cachedId)) && !currentAoiEnemyIds.has(cachedId)) {
                        delete p._lastSentEnemies[cachedId];
                    }
                }

                if (count > 0) {
                    io.to(p.socketId).emit('enemiesMoved', aoiData);
                }
            });
        }

        // v370.1: Métricas de Ciclo con Percentiles AAA
        const end      = Date.now();
        const duration = end - start;
        totalTickTime += duration;
        tickCount++;

        // Acumular en array circular para cálculo de percentiles
        tickSamples.push(duration);
        if (tickSamples.length > TICK_SAMPLE_SIZE) tickSamples.shift();

        if (state.performance) {
            state.performance.lastTickDuration = duration;
            state.performance.maxTickTime = Math.max(state.performance.maxTickTime || 0, duration);
        }

        if (duration > 33) {
            Logger.warn('PERF', `Tick lento: ${duration}ms (Presión en CPU o Red)`);
        }

        if (tickCount >= TICK_SAMPLE_SIZE) {
            if (state.performance) {
                state.performance.avgTickTime = parseFloat((totalTickTime / tickCount).toFixed(2));
                state.performance.maxTickTime = 0; // Reset cada ventana de 300 ticks

                // Calcular P50 y P99 sobre el array de muestras acumulado
                if (tickSamples.length >= 2) {
                    const sorted = [...tickSamples].sort((a, b) => a - b);
                    const p50Idx = Math.floor(sorted.length * 0.50);
                    const p99Idx = Math.min(Math.floor(sorted.length * 0.99), sorted.length - 1);
                    state.performance.p50TickTime = sorted[p50Idx];
                    state.performance.p99TickTime = sorted[p99Idx];
                }
            }
            tickCount    = 0;
            totalTickTime = 0;
        }
    }, 33);

    // 2. LOOP DE REGENERACIÓN (1s)
    setInterval(() => {
        const { players } = state;
        const now = Date.now();

        Object.values(players).forEach(p => {
            if (p.hp <= 0) return;

            let changed = false;

            // v266.360: Procesamiento de Sueño (Sleep Mechanic)
            if (p.isAsleep) {
                // Verificar si expiró el sueño
                if (now >= p.sleepEndTime) {
                    p.isAsleep = false;
                    p.isStunned = false;
                    p.sleepEndTime = 0;
                    p.sleepDmgPerSecond = 0;
                    io.to(p.socketId).emit('stunState', { active: false });
                    io.to(p.socketId).emit('gameNotification', { msg: "💤 Te has despertado.", type: "info" });
                    changed = true;
                } else {
                    // Aplicar daño por segundo del sueño si corresponde
                    if (p.sleepDmgPerSecond > 0 && now >= p.sleepNextTickDmgTime) {
                        p.sleepNextTickDmgTime = now + 1000;
                        const dmg = p.sleepDmgPerSecond;
                        p.lastCombatTime = now;
                        if (p.shield >= dmg) {
                            p.shield -= dmg;
                        } else {
                            p.hp -= (dmg - p.shield);
                            p.shield = 0;
                        }
                        if (p.hp < 0) p.hp = 0;
                        if (p.hp <= 0) {
                            p.isDead = true;
                            p.isAsleep = false;
                            p.isStunned = false;
                            io.to(p.socketId).emit('stunState', { active: false });
                        }
                        
                        io.to(p.socketId).emit('environmentDamage', { damage: dmg });
                        changed = true;
                    }
                }
            }

            const timeSinceCombat = now - (p.lastCombatTime || 0);
            if (timeSinceCombat > 10000 && !p.isAsleep) { // 10s fuera de combate y no durmiendo
                const regenAmount = p.maxHp * 0.05;
                const shieldRegen = p.maxShield * 0.08;

                if (p.hp < p.maxHp) {
                    p.hp = Math.min(p.maxHp, p.hp + regenAmount);
                    changed = true;
                }
                if (p.shield < p.maxShield) {
                    p.shield = Math.min(p.maxShield, p.shield + shieldRegen);
                    changed = true;
                }
            }

            // Daño por Debuffs de Sangrado y Veneno con ticks dinámicos (v268.830)
            let debuffDmg = 0;
            if (p.bleedEndTime && now < p.bleedEndTime && p.bleedDps) {
                const interval = p.bleedInterval || 1000;
                const lastTick = p.lastBleedTick || (now - 1000);
                const elapsed = now - lastTick;
                if (elapsed >= interval) {
                    const ticks = Math.floor(elapsed / interval);
                    debuffDmg += p.bleedDps * ticks;
                    p.lastBleedTick = lastTick + (ticks * interval);
                }
            } else if (p.bleedEndTime && now >= p.bleedEndTime) {
                p.bleedEndTime = 0;
                p.bleedDps = 0;
                p.bleedInterval = 0;
            }

            if (p.poisonEndTime && now < p.poisonEndTime && p.poisonDps) {
                const interval = p.poisonInterval || 1000;
                const lastTick = p.lastPoisonTick || (now - 1000);
                const elapsed = now - lastTick;
                if (elapsed >= interval) {
                    const ticks = Math.floor(elapsed / interval);
                    debuffDmg += p.poisonDps * ticks;
                    p.lastPoisonTick = lastTick + (ticks * interval);
                }
            } else if (p.poisonEndTime && now >= p.poisonEndTime) {
                p.poisonEndTime = 0;
                p.poisonDps = 0;
                p.poisonInterval = 0;
            }

            if (debuffDmg > 0) {
                p.lastCombatTime = now;
                if (p.shield >= debuffDmg) {
                    p.shield -= debuffDmg;
                } else {
                    p.hp -= (debuffDmg - p.shield);
                    p.shield = 0;
                }
                if (p.hp < 0) p.hp = 0;
                if (p.hp <= 0) p.isDead = true;

                io.to(p.socketId).emit('environmentDamage', { damage: debuffDmg });
                changed = true;
            }

            // Simular estados de sangrado (Bleed) si recibió daño de radiación recientemente
            if (p.hazardCooldowns && Object.keys(p.hazardCooldowns).length > 0) {
                const hasRecentRad = Object.values(p.hazardCooldowns).some(t => now - t < 1500);
                if (hasRecentRad && (!p.bleedEndTime || now > p.bleedEndTime)) {
                    p.bleedEndTime = now + 4000;
                    p.bleedDps = 25; // DPS default de radiacion
                }
            }
            // Sincronizar estados activos al cliente para el visualizador del HUD
            // v266.360: El veneno del sueño (Poison) solo se activa si hay daño por segundo
            if (p.isAsleep && p.sleepDmgPerSecond > 0) {
                p.poisonEndTime = p.sleepEndTime;
                p.poisonDps = p.sleepDmgPerSecond;
            } else if (!p.isAsleep && (!p.poisonEndTime || now >= p.poisonEndTime)) {
                p.poisonEndTime = 0;
                p.poisonDps = 0;
            }

            // Sincronizar estados activos al cliente para el visualizador del HUD
            const activeSlow = p.slowEndTime ? Math.max(0, p.slowEndTime - now) : 0;
            const activeStun = p.stunEndTime ? Math.max(0, p.stunEndTime - now) : 0;
            const activeHeal = p.healEndTime ? Math.max(0, p.healEndTime - now) : 0;
            if (activeHeal <= 0) p.healStacks = 0;
            const activeBleed = p.bleedEndTime ? Math.max(0, p.bleedEndTime - now) : 0;
            const activePoison = p.poisonEndTime ? Math.max(0, p.poisonEndTime - now) : 0;

            io.to(p.socketId).emit('statusEffectsSync', {
                slow: activeSlow,
                stun: activeStun,
                heal: activeHeal,
                healStacks: p.healStacks || 0,
                bleed: activeBleed,
                poison: activePoison
            });

            // Sync obligatorio solo si hubo cambios por ambiente o regen o sueño
            if (changed) {
                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: p.socketId, 
                    hp: Math.ceil(p.hp), 
                    shield: Math.ceil(p.shield),
                    maxHp: p.maxHp, 
                    maxShield: p.maxShield,
                    isInvisible: p.isInvisible,
                    isSlowed: p.isSlowed
                });
            }
        });
    }, 1000);

    // 3. LOOP DE GUARDIANÍA (1s para Respawn Dinámico v266.999)
    setInterval(() => {
        aiManager.runGuardians();
        
        // v2.0: Procesar Lógica de Extracción (1Hz)
        extractionManager.updateLoop();
        
        // Limpieza de Áreas expiradas
        const now = Date.now();
        for (const aid in state.activeAreas) {
            if (state.activeAreas[aid].endTime < now) {
                io.to(`zone_${state.activeAreas[aid].zone}`).emit('removeArea', { id: aid });
                delete state.activeAreas[aid];
            }
        }
    }, 1000);
    
    // 4. LOOP DE EFECTOS DE ÁREA (100ms)
    setInterval(() => {
        const now = Date.now();
        const { players, enemies, activeAreas } = state;

        // v270.0: Optimización - No limpiar ni re-poblar el grid aquí. 
        // El loop principal de 33ms ya actualiza state.grid de manera constante a 30fps.

        // A. Reset temporal de flags para Jugadores
        Object.values(players).forEach(p => {
            if (now - (p.lastSilenceTime || 0) > 200) p.isSilenced = false;
        });
            
        // v267.500: PROCESAR MECÁNICAS GLOBALES DE MAPA (Sincronizadas)
        if (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) {
            if (!state.mapTimers) state.mapTimers = {};
            
            Object.keys(state.SERVER_CONFIG.mapsConfig).forEach(zoneId => {
                const mapConfig = state.SERVER_CONFIG.mapsConfig[zoneId];
                if (mapConfig.ambience && mapConfig.ambience.length > 0) {
                    mapConfig.ambience.forEach((hazard, idx) => {
                        if (hazard.type === 'vortex_hazard') {
                            const tKey = `vortex_${zoneId}_${idx}`;
                            const lastSpawnEnd = state.mapTimers[tKey] || 0; 
                            const interval = hazard.spawnInterval || 10000;

                            if (now - lastSpawnEnd >= interval) {
                                const duration = hazard.duration || 8000;
                                state.mapTimers[tKey] = now + duration; // El próximo intervalo cuenta desde el fin
                                
                                // v267.500: Spawnear debajo de CADA jugador (Optimizado)
                                const playersInZone = state.playersByZone[zoneId] ? Object.values(state.playersByZone[zoneId]) : [];
                                playersInZone.forEach(p => {
                                    if (p.hp > 0) {
                                        const areaId = `vortex_${zoneId}_${p.user}_${Date.now()}`;
                                        state.activeAreas[areaId] = {
                                            id: areaId,
                                            zone: zoneId,
                                            type: 'VORTEX_HAZARD',
                                            x: p.x,
                                            y: p.y,
                                            radius: hazard.radius || 300,
                                            pullForce: hazard.pullForce || 8,
                                            damage: hazard.damage || 500,
                                            damageInterval: hazard.damageInterval || 1000,
                                            endTime: now + duration,
                                            ownerId: 'environment'
                                        };
                                        io.to(`zone_${zoneId}`).emit('spawnArea', state.activeAreas[areaId]);
                                    }
                                });
                            }
                        }
                        else if (hazard.type === 'blindness_hazard') {
                            const tKey = `blind_${zoneId}_${idx}`;
                            const lastEnd = state.mapTimers[tKey] || 0;
                            const interval = hazard.spawnInterval || 15000;

                            if (now - lastEnd >= interval) {
                                Logger.debug('AMB', `Disparando Ceguera en zona ${zoneId} (Intervalo: ${interval}ms)`);
                                const duration = hazard.duration || 5000;
                                state.mapTimers[tKey] = now + duration;
                                
                                // v267.900: Emitir evento de ceguera sincronizado a toda la zona
                                io.to(`zone_${zoneId}`).emit('blindnessEvent', {
                                    duration: duration,
                                    radius: hazard.radius || 150
                                });
                                // console.log(`[MAP-EVENT] Ceguera de Vacío activada en Zona ${zoneId} por ${duration}ms`);
                            }
                        }
                        else if (hazard.type === 'interferencia_hazard') {
                            const tKey = `inter_${zoneId}_${idx}`;
                            const lastEnd = state.mapTimers[tKey] || 0;
                            const interval = hazard.spawnInterval || 20000;

                            if (now - lastEnd >= interval) {
                                const duration = hazard.duration || 4000;
                                state.mapTimers[tKey] = now + duration;
                                
                                io.to(`zone_${zoneId}`).emit('interferenceEvent', {
                                    duration: duration,
                                    shakeIntensity: hazard.shakeIntensity || 10.0,
                                    staticIntensity: hazard.staticIntensity || 0.4
                                });
                                // console.log(`[MAP-EVENT] 📡 INTERFERENCIA activada en Zona ${zoneId} por ${duration}ms`);
                            }
                        }
                        else if (hazard.type === 'freeze_hazard') {
                            const tKey = `freeze_${zoneId}_${idx}`;
                            const lastEnd = state.mapTimers[tKey] || 0;
                            const interval = hazard.spawnInterval || 25000;

                            if (now - lastEnd >= interval) {
                                const duration = hazard.duration || 6000;
                                state.mapTimers[tKey] = now + duration;
                                
                                io.to(`zone_${zoneId}`).emit('freezeEvent', {
                                    duration: duration,
                                    slowPercentage: hazard.slowPercentage || 0,
                                    slowFixed: hazard.slowFixed || 0
                                });
                                // console.log(`[MAP-EVENT] ❄️ CONGELACIÓN activada en Zona ${zoneId} por ${duration}ms`);
                            }
                        }
                    });
                }
            });
        }

        // B. Procesar Jugadores (Daño/Ambiente local)
        const lobbyZoneIdArea = Number(state.SERVER_CONFIG?.pilotConfig?.startingMapId || 1);
        Object.values(players).forEach(p => {
            const wasBlinded = p.isBlinded;
            if (now - (p.lastBlindTime || 0) > 200) p.isBlinded = false;
            if (wasBlinded && !p.isBlinded) io.to(p.socketId).emit('blindState', { active: false });

            const wasSlowed = p.isSlowed;
            if (now - (p.lastSlowTime || 0) > 400 && (!p.slowEndTime || now > p.slowEndTime)) {
                p.isSlowed = false;
                p.slowPoints = 0;
            }

            // LOBBY OPTIMIZATION: saltar todos los efectos ambientales para jugadores del Lobby
            if (Number(p.zone) !== lobbyZoneIdArea) {
                const mapConfig = state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig ? state.SERVER_CONFIG.mapsConfig[p.zone] : null;
                if (mapConfig && mapConfig.ambience && p.hp > 0) {
                    mapConfig.ambience.forEach((hazard, idx) => {
                        const dmg = hazard.damage || hazard.damagePerSecond || 0;
                        const interval = hazard.intervalMs || 1000;
                        
                        if (hazard.type === 'radiation' && dmg > 0) {
                            if (!p.hazardCooldowns) p.hazardCooldowns = {};
                            const hKey = `rad_${idx}`;
                            const lastHit = p.hazardCooldowns[hKey] || 0;
                            if (now - lastHit >= interval) {
                                p.hazardCooldowns[hKey] = now;
                                p.lastCombatTime = now;
                                if (p.shield >= dmg) p.shield -= dmg;
                                else { p.hp -= (dmg - p.shield); p.shield = 0; }
                                if (p.hp < 0) p.hp = 0;
                                io.to(p.socketId).emit('environmentDamage', { damage: dmg });
                                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                                    id: p.socketId, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield),
                                    maxHp: p.maxHp, maxShield: p.maxShield, isInvisible: p.isInvisible, isSlowed: p.isSlowed
                                });
                            }
                        }
                        else if (hazard.type === 'nebula' && hazard.slowPercentage) {
                            p.isSlowed = true;
                            p.lastSlowTime = now;
                            p.slowPoints = hazard.slowPercentage;
                        }
                    });
                }
            }
            
            if (wasSlowed !== p.isSlowed) {
                io.to(p.socketId).emit('slowState', { active: p.isSlowed, amount: p.slowPoints });
            }
        });

        // B. Reset temporal de flags para Enemigos
        Object.values(enemies).forEach(e => {
            if (now - (e.lastSilenceTime || 0) > 200) e.isSilenced = false;
            if (now - (e.lastSlowTime || 0) > 200) {
                e.isSlowed = false;
                e.slowMultiplier = 1.0;
            }
        });

        // C. Procesar Áreas Activas y Limpieza
        for (const id in activeAreas) {
            const area = activeAreas[id];

            // v267.300: Limpieza de Áreas Expiradas
            if (now >= (area.endTime || 0)) {
                io.to(`zone_${area.zone}`).emit('removeArea', { id });
                delete activeAreas[id];
                Logger.debug('VORTEX', `Area ${id} expired and removed.`);
                continue;
            }

            // SOPORTE DE BALIZA DE CURACIÓN (Pulsos Periódicos de Sanación)
            if (area.type === 'HEAL_BEACON') {
                if (now - (area.lastPulseTime || 0) >= (area.pulse_interval || 1500)) {
                    area.lastPulseTime = now;
                    
                    // Emitir evento de pulso a la zona para VFX en el cliente
                    io.to(`zone_${area.zone}`).emit('beaconPulse', { id: area.id, radius: area.radius });
                    
                    const healVal = area.heal_amount || 250;
                    const owner = players[area.ownerId];
                    const filters = area.targetFilters || { allies: true, enemies: false, bosses: false, players: true };
                    
                    // Obtener tanto jugadores como enemigos cercanos
                    const { players: nearbyPlayers, enemies: nearbyEnemies } = grid.getNearbyEntities(area.x, area.y, area.zone);
                    
                    // 1. Curar jugadores según filtros (aliados, enemigos PvP, jugadores neutrales)
                    nearbyPlayers.forEach(p => {
                        if (String(p.zone) === String(area.zone) && !p.isDead) {
                            const dx = p.x - area.x;
                            const dy = p.y - area.y;
                            const dist = Math.hypot(dx, dy);
                            
                            if (dist < area.radius) {
                                const sameClan = (owner && p.clanId && owner.clanId && String(p.clanId) === String(owner.clanId));
                                const pUid = p.id ? p.id.toString() : null;
                                const oUid = owner ? (owner.id ? owner.id.toString() : null) : null;
                                const sameParty = (pUid && oUid && state.playerParty[pUid] && state.playerParty[pUid] === state.playerParty[oUid]);
                                
                                const isDirectAlly = (p.socketId === area.ownerId) || sameClan || sameParty;
                                const isAlly = isDirectAlly || (owner && !owner.pvpEnabled && !p.pvpEnabled);
                                const isEnemy = !isDirectAlly && owner && (owner.pvpEnabled || p.pvpEnabled);
                                
                                let isValid = false;
                                if (isAlly && filters.allies) isValid = true;
                                else if (isEnemy && (filters.enemies || filters.players)) isValid = true;
                                else if (!isAlly && !isEnemy && filters.players) isValid = true;
                                
                                if (isValid) {
                                    const oldH = p.hp;
                                    p.hp = Math.min(p.maxHp, p.hp + healVal);
                                    const actualHeal = p.hp - oldH;
                                    
                                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                                        id: p.socketId,
                                        hp: Math.ceil(p.hp),
                                        shield: Math.ceil(p.shield),
                                        maxHp: p.maxHp,
                                        maxShield: p.maxShield
                                    });
                                    
                                    io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', {
                                        id: area.ownerId,
                                        skillName: 'BALIZA DE CURACION',
                                        targetId: p.socketId,
                                        powerValue: actualHeal
                                    });
                                }
                            }
                        }
                    });
                    
                    // 2. Curar enemigos NPCs según filtros (enemies y bosses)
                    nearbyEnemies.forEach(e => {
                        if (String(e.zone) === String(area.zone) && e.hp > 0) {
                            const dx = e.x - area.x;
                            const dy = e.y - area.y;
                            const dist = Math.hypot(dx, dy);
                            
                            if (dist < area.radius) {
                                const isBoss = !!e.isBoss || e.type === 4 || e.type === 10 || e.type === 11 || (typeof e.type === 'number' && e.type >= 100);
                                let isValid = false;
                                if (isBoss && filters.bosses) isValid = true;
                                else if (!isBoss && filters.enemies) isValid = true;
                                
                                if (isValid) {
                                    const oldH = e.hp;
                                    const maxHp = e.maxHp || (state.SERVER_CONFIG && state.SERVER_CONFIG.enemyModels && state.SERVER_CONFIG.enemyModels[e.type] ? state.SERVER_CONFIG.enemyModels[e.type].hp : 1000);
                                    e.hp = Math.min(maxHp, e.hp + healVal);
                                    const actualHeal = e.hp - oldH;
                                    
                                    // Emitir remotePlayerUsedSkill para mostrar el texto curativo sobre el enemigo
                                    io.to(`zone_${e.zone}`).emit('remotePlayerUsedSkill', {
                                        id: area.ownerId,
                                        skillName: 'BALIZA DE CURACION',
                                        targetId: e.id,
                                        powerValue: actualHeal
                                    });
                                }
                            }
                        }
                    });
                }
                continue; // La baliza de curación no colisiona físicamente con los enemigos
            }

            // SOPORTE DE VÍNCULO VITAL (Lazo Curativo Continuo)
            if (area.type === 'VITAL_LINK') {
                const owner = players[area.ownerId];
                let target = players[area.targetId];
                let isEnemyNPC = false;
                if (!target && enemies[area.targetId]) {
                    target = enemies[area.targetId];
                    isEnemyNPC = true;
                }

                // Si alguno murió o se desconectó, romper el lazo
                if (!owner || owner.isDead || !target || target.isDead) {
                    io.to(`zone_${area.zone}`).emit('removeArea', { id });
                    delete activeAreas[id];
                    continue;
                }

                const targetZone = isEnemyNPC ? target.zoneId : target.zone;
                if (owner.zone !== targetZone) {
                    io.to(`zone_${area.zone}`).emit('removeArea', { id });
                    delete activeAreas[id];
                    continue;
                }

                // Validar distancia máxima
                const dist = Math.hypot(target.x - owner.x, target.y - owner.y);
                if (dist > area.radius) {
                    io.to(`zone_${area.zone}`).emit('removeArea', { id });
                    delete activeAreas[id];
                    
                    io.to(area.ownerId).emit('gameNotification', { msg: "¡VÍNCULO VITAL ROTO! Te alejaste demasiado.", type: "warning" });
                    if (!isEnemyNPC) {
                        io.to(area.targetId).emit('gameNotification', { msg: "¡VÍNCULO VITAL ROTO! Te alejaste demasiado.", type: "warning" });
                    }
                    continue;
                }

                // Procesar tick de curación periódica
                if (now - (area.lastTickTime || 0) >= (area.tickInterval || 1000)) {
                    const oldH = target.hp;
                    target.hp = Math.min(target.maxHp, target.hp + (area.amount || 250));
                    const actualHeal = target.hp - oldH;

                    if (!isEnemyNPC) {
                        // Sync estadísticas del receptor jugador
                        io.to(`zone_${target.zone}`).emit('playerStatSync', {
                            id: target.socketId,
                            hp: Math.ceil(target.hp),
                            shield: Math.ceil(target.shield),
                            maxHp: target.maxHp,
                            maxShield: target.maxShield
                        });
                    }

                    // Notificar números verdes de curación sobre el receptor (jugador o NPC)
                    io.to(`zone_${owner.zone}`).emit('remotePlayerUsedSkill', {
                        id: area.ownerId,
                        skillName: 'VÍNCULO VITAL',
                        targetId: area.targetId,
                        powerValue: actualHeal
                    });

                    area.lastTickTime = now;
                }
                continue; // El lazo vital no necesita colisionar físicamente con el grid
            }

            const { players: nearbyPlayers, enemies: nearbyEnemies } = grid.getNearbyEntities(area.x, area.y, area.zone);

            // Efectos a Jugadores
            nearbyPlayers.forEach(p => {
                if (String(p.zone) === String(area.zone) && !p.isDead) {
                    const dx = p.x - area.x;
                    const dy = p.y - area.y;
                    const distSq = dx * dx + dy * dy;
                    const dist = Math.sqrt(distSq);
                    
                    if (dist < area.radius) {
                        const owner = players[area.ownerId];
                        let is_ally = (p.socketId === area.ownerId);
                        if (owner && !is_ally) {
                            if (p.clanId && owner.clanId && String(p.clanId) === String(owner.clanId)) is_ally = true;
                            const pUid = p.id ? p.id.toString() : null;
                            const oUid = owner.id ? owner.id.toString() : null;
                            if (pUid && oUid && state.playerParty[pUid] && state.playerParty[pUid] === state.playerParty[oUid]) is_ally = true;
                        }

                        if (area.type === 'SMOKE' && !is_ally) {
                            p.isSilenced = true; p.lastSilenceTime = now;
                            if (!p.isBlinded) { p.isBlinded = true; io.to(p.socketId).emit('blindState', { active: true }); }
                            p.lastBlindTime = now;
                        } else if (area.type === 'ICE' && !is_ally) {
                            const prevSlow = p.isSlowed;
                            p.isSlowed = true; p.lastSlowTime = now;
                            p.slowPoints = (area.slowAmount || 0.5) * 100;
                            if (!prevSlow) io.to(p.socketId).emit('slowState', { active: true, amount: p.slowPoints });
                        } else if (area.type === 'HEAL_ZONE') {
                            let isValidTarget = false;
                            const filters = area.filters || { allies: true, enemies: false, bosses: false, players: true };
                            if (is_ally) {
                                if (filters.allies) isValidTarget = true;
                            } else {
                                if (filters.enemies || filters.players) isValidTarget = true;
                            }

                            if (isValidTarget) {
                                const oldH = p.hp;
                                const healVal = area.amount || 1500;
                                p.hp = Math.min(p.maxHp, p.hp + healVal);
                                const actualHeal = p.hp - oldH;

                                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                                    id: p.socketId,
                                    hp: Math.ceil(p.hp),
                                    shield: Math.ceil(p.shield),
                                    maxHp: p.maxHp,
                                    maxShield: p.maxShield
                                });

                                io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', {
                                    id: area.ownerId,
                                    skillName: 'REGENERACIÓN ALFA',
                                    targetId: p.socketId,
                                    powerValue: actualHeal
                                });

                                io.to(`zone_${area.zone}`).emit('removeArea', { id });
                                delete activeAreas[id];
                            }
                        }
                        // v267.800: EFECTO FÍSICO DEL VÓRTICE AMBIENTAL SINCRO 1:1
                        if (area.type === 'VORTEX_HAZARD') {
                            // 1. Succión Literal (Fuerza en PX/S)
                            const pullBase = (area.pullForce || 400); 
                            const proximityMult = 1.0 + (1.0 - dist / area.radius);
                            
                            // El servidor corre a 10fps (100ms), así que dividimos por 10
                            const pullPerTick = (pullBase * proximityMult) / 10;
                            
                            const angle = Math.atan2(area.y - p.y, area.x - p.x);
                            p.x += Math.cos(angle) * pullPerTick;
                            p.y += Math.sin(angle) * pullPerTick;

                            // 2. Daño periódico
                            if (!p.hazardCooldowns) p.hazardCooldowns = {};
                            const dmgKey = `vortex_dmg_${area.id}`;
                            const lastDmg = p.hazardCooldowns[dmgKey] || 0;
                            const dmgInterval = area.damageInterval || 1000;

                            if (now - lastDmg >= dmgInterval) {
                                p.hazardCooldowns[dmgKey] = now;
                                const dmg = area.damage || 500;
                                p.lastCombatTime = now;
                                if (p.shield >= dmg) p.shield -= dmg;
                                else { p.hp -= (dmg - p.shield); p.shield = 0; }
                                if (p.hp < 0) p.hp = 0;

                                io.to(p.socketId).emit('environmentDamage', { damage: dmg });
                                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                                    id: p.socketId, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield),
                                    maxHp: p.maxHp, maxShield: p.maxShield, isDead: p.hp <= 0
                                });
                            }

                            // Sincronizar posición forzada por succión
                            io.to(p.socketId).emit('playerStatSync', { id: p.socketId, x: p.x, y: p.y });
                        }
                        
                        // v2.5: Repulsión Física Plana por Barrera de Viento
                        if (area.type === 'WIND_BARRIER' && !is_ally) {
                            const filters = area.targetFilters || { allies: false, enemies: true, bosses: false, players: false };
                            if (filters.players) {
                                const areaAngle = area.angle || 0;
                                const halfW = (area.width || 150) / 2;
                                const perpAngle = areaAngle + Math.PI / 2;
                                
                                const ax = area.x + Math.cos(perpAngle) * halfW;
                                const ay = area.y + Math.sin(perpAngle) * halfW;
                                const bx = area.x - Math.cos(perpAngle) * halfW;
                                const by = area.y - Math.sin(perpAngle) * halfW;
                                
                                const thickness = 50; // Grosor de colisión del viento
                                
                                const abx = bx - ax;
                                const aby = by - ay;
                                const apx = p.x - ax;
                                const apy = p.y - ay;
                                
                                const ab2 = abx * abx + aby * aby;
                                let dist = 999999;
                                let nx = 0;
                                let ny = 0;
                                
                                if (ab2 === 0) {
                                    const pdx = p.x - ax;
                                    const pdy = p.y - ay;
                                    dist = Math.hypot(pdx, pdy);
                                    if (dist > 0) { nx = pdx / dist; ny = pdy / dist; }
                                } else {
                                    let t = (apx * abx + apy * aby) / ab2;
                                    t = Math.max(0, Math.min(1, t));
                                    const cx = ax + t * abx;
                                    const cy = ay + t * aby;
                                    
                                    const pdx = p.x - cx;
                                    const pdy = p.y - cy;
                                    dist = Math.hypot(pdx, pdy);
                                    if (dist > 0) { nx = pdx / dist; ny = pdy / dist; }
                                }
                                
                                if (dist < thickness) {
                                    const pushSpeed = 30; // 300px/s para impedir el cruce
                                    p.x += nx * pushSpeed;
                                    p.y += ny * pushSpeed;
                                    io.to(p.socketId).emit('playerStatSync', { id: p.socketId, x: p.x, y: p.y });
                                }
                            }
                        }
                    }
                }

            });

            // Efectos a Enemigos
            nearbyEnemies.forEach(e => {
                if (e.zone === area.zone && e.hp > 0) {
                    const dx = e.x - area.x;
                    const dy = e.y - area.y;
                    const distSq = dx * dx + dy * dy;
                    if (distSq < (area.radius * area.radius)) {
                        if (area.type === 'SMOKE') {
                            e.isSilenced = true;
                            e.lastSilenceTime = now;
                        } else if (area.type === 'ICE') {
                            e.isSlowed = true;
                            e.lastSlowTime = now;
                            e.slowMultiplier = area.slowAmount || 0.5;
                        } else if (area.type === 'WIND_BARRIER') {
                            const filters = area.targetFilters || { allies: false, enemies: true, bosses: false, players: false };
                            const isBoss = !!e.isBoss;
                            const shouldRepel = isBoss ? filters.bosses : filters.enemies;
                            if (shouldRepel) {
                                const areaAngle = area.angle || 0;
                                const halfW = (area.width || 150) / 2;
                                const perpAngle = areaAngle + Math.PI / 2;
                                
                                const ax = area.x + Math.cos(perpAngle) * halfW;
                                const ay = area.y + Math.sin(perpAngle) * halfW;
                                const bx = area.x - Math.cos(perpAngle) * halfW;
                                const by = area.y - Math.sin(perpAngle) * halfW;
                                
                                const thickness = 50; // Grosor de colisión del viento
                                
                                const abx = bx - ax;
                                const aby = by - ay;
                                const apx = e.x - ax;
                                const apy = e.y - ay;
                                
                                const ab2 = abx * abx + aby * aby;
                                let dist = 999999;
                                let nx = 0;
                                let ny = 0;
                                
                                if (ab2 === 0) {
                                    const edx = e.x - ax;
                                    const edy = e.y - ay;
                                    dist = Math.hypot(edx, edy);
                                    if (dist > 0) { nx = edx / dist; ny = edy / dist; }
                                } else {
                                    let t = (apx * abx + apy * aby) / ab2;
                                    t = Math.max(0, Math.min(1, t));
                                    const cx = ax + t * abx;
                                    const cy = ay + t * aby;
                                    
                                    const edx = e.x - cx;
                                    const edy = e.y - cy;
                                    dist = Math.hypot(edx, edy);
                                    if (dist > 0) { nx = edx / dist; ny = edy / dist; }
                                }
                                
                                if (dist < thickness) {
                                    const pushSpeed = 30; // 300px/s para impedir que lo cruce
                                    e.x += nx * pushSpeed;
                                    e.y += ny * pushSpeed;
                                }
                            }
                        }
                    }
                }

            });
        }
    }, 100);
}

module.exports = { startGameLoop };
