/**
 * GameLoop
 * El corazón del servidor. Maneja los intervalos de tiempo para IA, regeneración y limpieza.
 */
function startGameLoop(io, state, aiManager) {
    const grid = state.grid;
    
    // 1. LOOP DE IA Y MOVIMIENTO (33ms ~ 30fps para suavidad)
    setInterval(() => {
        const now = Date.now();
        const { enemies, players } = state;

        // v247.11: Actualizar grid para IA y Colisiones (Frecuencia 30fps)
        grid.clear();
        Object.values(players).forEach(p => grid.insert(p, 'player'));
        Object.values(enemies).forEach(e => { if (e.hp > 0) grid.insert(e, 'enemy'); });

        const zoneMoveData = {};

        for (const id in enemies) {
            const e = enemies[id];
            if (e.hp <= 0) continue;

            // v262.35: IA Inteligente (LOD - Level of Detail)
            // Solo procesar IA si hay jugadores cerca o cada 1 segundo (ahorro masivo de CPU)
            const { players: nearbyPs } = grid.getNearbyEntities(e.x, e.y);
            const isNearPlayer = nearbyPs.some(p => p.zone === e.zone);
            
            if (isNearPlayer || (now % 1000 < 33)) {
                if (e.ai) e.ai.update(grid, players, now, io);
            }

            // v247.12: Repulsión física optimizada vía Grid
            const { enemies: nearbyEnemies } = grid.getNearbyEntities(e.x, e.y);
            nearbyEnemies.forEach(other => {
                if (e.id !== other.id && e.zone === other.zone) {
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
                            if (e.zone === p.zone) {
                                aoiData[e.id] = {
                                    id: e.id, x: e.x, y: e.y, rotation: e.rotation,
                                    hp: e.hp, shield: e.shield, zone: e.zone, type: e.type,
                                    name: e.name, isRage: e.isRage, isRamming: e.ai && e.ai.isRamming
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
    }, 33);

    // 2. LOOP DE REGENERACIÓN (1s)
    setInterval(() => {
        const { players } = state;
        const now = Date.now();

        Object.values(players).forEach(p => {
            if (p.hp <= 0) return;

            const timeSinceCombat = now - (p.lastCombatTime || 0);
            if (timeSinceCombat > 10000) { // 10s fuera de combate
                const regenAmount = p.maxHp * 0.05;
                const shieldRegen = p.maxShield * 0.08;

                if (p.hp < p.maxHp) {
                    p.hp = Math.min(p.maxHp, p.hp + regenAmount);
                }
                if (p.shield < p.maxShield) {
                    p.shield = Math.min(p.maxShield, p.shield + shieldRegen);
                }

                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: p.socketId, 
                    hp: Math.ceil(p.hp), 
                    shield: Math.ceil(p.shield),
                    isInvisible: p.isInvisible // v245.89: Persistencia de Sigilo en Loop
                });
            }
        });
    }, 1000);

    // 3. LOOP DE GUARDIANÍA (5s)
    setInterval(() => {
        aiManager.runGuardians();
        
        // Limpieza de Áreas expiradas
        const now = Date.now();
        for (const aid in state.activeAreas) {
            if (state.activeAreas[aid].endTime < now) {
                io.to(`zone_${state.activeAreas[aid].zone}`).emit('removeArea', { id: aid });
                delete state.activeAreas[aid];
            }
        }
    }, 5000);
    
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
            
            const wasBlinded = p.isBlinded;
            if (now - (p.lastBlindTime || 0) > 200) p.isBlinded = false;
            if (wasBlinded && !p.isBlinded) io.to(p.socketId).emit('blindState', { active: false });

            const wasSlowed = p.isSlowed;
            if (now - (p.lastSlowTime || 0) > 400) {
                p.isSlowed = false;
                p.slowPoints = 0;
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

        // C. Procesar Áreas Activas
        for (const id in activeAreas) {
            const area = activeAreas[id];
            
            // v247.2: Solo procesar entidades en celdas adyacentes (Spatial Hashing)
            const { players: nearbyPlayers, enemies: nearbyEnemies } = grid.getNearbyEntities(area.x, area.y);

            // Efectos a Jugadores
            nearbyPlayers.forEach(p => {
                if (p.zone === area.zone && !p.isDead) {
                    const dx = p.x - area.x;
                    const dy = p.y - area.y;
                    const distSq = dx * dx + dy * dy;
                    
                    if (distSq < (area.radius * area.radius)) {
                        const owner = players[area.ownerId];
                        let is_ally = (p.socketId === area.ownerId);
                        if (owner && !is_ally) {
                            if (p.clanId && owner.clanId && String(p.clanId) === String(owner.clanId)) is_ally = true;
                            
                            const pUid = p.id ? p.id.toString() : null;
                            const oUid = owner.id ? owner.id.toString() : null;
                            if (pUid && oUid && state.playerParty[pUid] && state.playerParty[pUid] === state.playerParty[oUid]) {
                                is_ally = true;
                            }
                        }

                        if (area.type === 'SMOKE' && !is_ally) {
                            p.isSilenced = true;
                            p.lastSilenceTime = now;
                            if (!p.isBlinded) {
                                p.isBlinded = true;
                                io.to(p.socketId).emit('blindState', { active: true });
                            }
                            p.lastBlindTime = now;
                        } else if (area.type === 'ICE' && !is_ally) {
                            const prevSlow = p.isSlowed;
                            p.isSlowed = true;
                            p.lastSlowTime = now;
                            p.slowPoints = (area.slowAmount || 0.5) * 100;
                            
                            if (!prevSlow) {
                                io.to(p.socketId).emit('slowState', { active: true, amount: p.slowPoints });
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
                        }
                    }
                }
            });
        }
    }, 100);
}

module.exports = { startGameLoop };
