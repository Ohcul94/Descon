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
        if (!isNaN(z) && z.trim() !== '') {
            return Number(z);
        }
        return z;
    }
    return z;
};


function startGameLoop(io, state, aiManager) {
    const grid = state.grid;
    
    // v262.70: Monitor de Performance (Profiling)
    let lastTickTime = Date.now();
    let tickCount = 0;
    let totalTickTime = 0;

    // 1. LOOP DE IA Y MOVIMIENTO (33ms ~ 30fps para suavidad)
    setInterval(() => {
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

        for (const id in enemies) {
            const e = enemies[id];
            if (e.hp <= 0) {
                if (!e.isDeadProcessed) handleEnemyDeath(id, io, state);
                continue;
            }

            // v262.35: IA Inteligente (LOD) - Forzar actualización si hay mecánicas activas o Agresividad Extrema
            const { players: nearbyPs } = grid.getNearbyEntities(e.x, e.y);
            const isNearPlayer = nearbyPs.some(p => normalizeZone(p.zone) === normalizeZone(e.zone));
            const hasActiveMech = e.mechState && Object.values(e.mechState).some(m => m.isActive);
            
            // v266.999: Detección de Agresividad Extrema para Bypass de LOD
            const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
            const mapCfg = maps[e.zone] || maps[e.zone.toString()];
            const isExtreme = mapCfg && mapCfg.ambience && mapCfg.ambience.some(a => a.type === 'extreme_aggression');

            if (isNearPlayer || hasActiveMech || isExtreme || (now % 1000 < 33)) {
                if (e.ai) e.ai.update(grid, players, now, io);
            }

            // v247.12: Repulsión física optimizada vía Grid
            const { enemies: nearbyEnemies } = grid.getNearbyEntities(e.x, e.y);
            nearbyEnemies.forEach(other => {
                if (e.id !== other.id && normalizeZone(e.zone) === normalizeZone(other.zone)) {
                    const dx = e.x - other.x;
                    const dy = e.y - other.y;
                    const d = Math.hypot(dx, dy);
                    if (d < 45) { // Distancia de repulsión
                        const force = (45 - d) * 0.05;
                        e.x += (dx / d) * force;
                        e.y += (dy / d) * force;
                    }
                }
            });
        }

        // v262.30: Broadcast por AOI (Area of Interest) - 5x5 Celdas (2500px x 2500px)
        Object.values(players).forEach(p => {
            if (!p.zone) return;
            
            const aoiData = {};
            let count = 0;

            // Rango de 2 celdas a la redonda (total 5x5) para cubrir pantallas 4K/Ultra-wide
            const cx = Math.floor(p.x / 500);
            const cy = Math.floor(p.y / 500);

            for (let dx = -2; dx <= 2; dx++) {
                for (let dy = -2; dy <= 2; dy++) {
                    const key = `${cx + dx},${cy + dy}`;
                    const cell = grid.grid.get(key);
                    if (cell) {
                        cell.enemies.forEach(e => {
                            if (normalizeZone(e.zone) === normalizeZone(p.zone)) {
                                aoiData[e.id] = {
                                    id: e.id, x: e.x, y: e.y, rotation: e.rotation,
                                    hp: e.hp, shield: e.shield, zone: e.zone, type: e.type,
                                    name: e.name, isRage: e.isRage, isRamming: e.ai && e.ai.isRamming,
                                    isInvulnerable: e.isInvulnerable // v269.180: Sincronía visual
                                };
                                count++;
                            }
                        });
                    }
                }
            }

            if (count > 0) {
                io.to(p.socketId).emit('enemiesMoved', aoiData);
            }
        });

        // v262.70: Métricas de Ciclo
        const end = Date.now();
        const duration = end - start;
        totalTickTime += duration;
        tickCount++;

        if (duration > 33) {
            Logger.warn('PERF', `Tick lento: ${duration}ms (Presión en CPU o Red)`);
        }

        // Loguear promedio cada 10 segundos (300 ticks aprox)
        /*
        if (tickCount >= 300) {
            const avg = (totalTickTime / tickCount).toFixed(2);
            const memory = (process.memoryUsage().heapUsed / 1024 / 1024).toFixed(2);
            // console.log(`\x1b[36m[SERVER-STATS]\x1b[0m Avg Tick: ${avg}ms | RAM: ${memory}MB | Online: ${Object.keys(players).length}`);
            tickCount = 0;
            totalTickTime = 0;
        }
        */
    }, 33);

    // 2. LOOP DE REGENERACIÓN (1s)
    setInterval(() => {
        const { players } = state;
        const now = Date.now();

        Object.values(players).forEach(p => {
            if (p.hp <= 0) return;

            let changed = false;

            const timeSinceCombat = now - (p.lastCombatTime || 0);
            if (timeSinceCombat > 10000) { // 10s fuera de combate
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

            // Sync obligatorio solo si hubo cambios por ambiente o regen
            if (changed) {
                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: p.socketId, 
                    hp: Math.ceil(p.hp), 
                    shield: Math.ceil(p.shield),
                    maxHp: p.maxHp, // v270.0: Enviar máximos para evitar bugs visuales de 65k
                    maxShield: p.maxShield,
                    isInvisible: p.isInvisible,
                    isSlowed: p.isSlowed // v266.351
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

        // v247.1: Re-poblar el grid espacial cada 100ms (Optimización v6)
        grid.clear();
        Object.values(players).forEach(p => grid.insert(p, 'player'));
        Object.values(enemies).forEach(e => grid.insert(e, 'enemy'));

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
                                
                                // v267.500: Spawnear debajo de CADA jugador
                                Object.values(players).forEach(p => {
                                    if (String(p.zone) === String(zoneId) && p.hp > 0) {
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
        Object.values(players).forEach(p => {
            const wasBlinded = p.isBlinded;
            if (now - (p.lastBlindTime || 0) > 200) p.isBlinded = false;
            if (wasBlinded && !p.isBlinded) io.to(p.socketId).emit('blindState', { active: false });

            const wasSlowed = p.isSlowed;
            if (now - (p.lastSlowTime || 0) > 400 && (!p.slowEndTime || now > p.slowEndTime)) {
                p.isSlowed = false;
                p.slowPoints = 0;
            }

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

            const { players: nearbyPlayers, enemies: nearbyEnemies } = grid.getNearbyEntities(area.x, area.y);

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
                        }
                    }
                }
            });
        }
    }, 100);
}

module.exports = { startGameLoop };
