/**
 * GameLoop
 * El corazón del servidor. Maneja los intervalos de tiempo para IA, regeneración y limpieza.
 */
function startGameLoop(io, state, aiManager) {
    
    // 1. LOOP DE IA Y MOVIMIENTO (33ms ~ 30fps para suavidad)
    setInterval(() => {
        const now = Date.now();
        const { enemies, players } = state;
        const zoneMoveData = {};

        for (const id in enemies) {
            const e = enemies[id];
            if (e.hp <= 0) continue;

            // Actualizar IA
            if (e.ai) e.ai.update(players, now, io);

            // Repulsión física entre enemigos
            Object.values(enemies).forEach(other => {
                if (e.id !== other.id && e.zone === other.zone && other.hp > 0) {
                    const dx = e.x - other.x;
                    const dy = e.y - other.y;
                    const distSq = dx * dx + dy * dy;
                    if (distSq < 2025) {
                        const pushAngle = Math.atan2(dy, dx);
                        const force = 0.8;
                        e.x += Math.cos(pushAngle) * force;
                        e.y += Math.sin(pushAngle) * force;
                    }
                }
            });

            if (!zoneMoveData[e.zone]) zoneMoveData[e.zone] = {};
            zoneMoveData[e.zone][e.id] = {
                id: e.id, x: e.x, y: e.y, rotation: e.rotation,
                hp: e.hp, shield: e.shield, zone: e.zone, type: e.type,
                name: e.name, isRage: e.isRage, isRamming: e.ai && e.ai.isRamming
            };
        }

        // Broadcast por zona
        for (const z in zoneMoveData) {
            io.to(`zone_${z}`).emit('enemiesMoved', zoneMoveData[z]);
        }
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

        // A. Reset temporal de flags para Jugadores
        Object.entries(players).forEach(([pSocketId, p]) => {
            if (now - (p.lastSilenceTime || 0) > 200) p.isSilenced = false;
            
            const wasBlinded = p.isBlinded;
            if (now - (p.lastBlindTime || 0) > 200) p.isBlinded = false;
            if (wasBlinded && !p.isBlinded) io.to(pSocketId).emit('blindState', { active: false });

            const wasSlowed = p.isSlowed;
            if (now - (p.lastSlowTime || 0) > 400) {
                p.isSlowed = false;
                p.slowPoints = 0;
            }
            if (wasSlowed !== p.isSlowed) {
                io.to(pSocketId).emit('slowState', { active: p.isSlowed, amount: p.slowPoints });
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
            
            // Efectos a Jugadores
            Object.entries(players).forEach(([pSocketId, p]) => {
                if (p.zone === area.zone && !p.isDead) {
                    const dx = p.x - area.x;
                    const dy = p.y - area.y;
                    const distSq = dx * dx + dy * dy;
                    
                    if (distSq < (area.radius * area.radius)) {
                        const owner = players[area.ownerId];
                        let is_ally = (pSocketId === area.ownerId);
                        if (owner && !is_ally) {
                            if (p.clanId != null && owner.clanId != null && p.clanId == owner.clanId) is_ally = true;
                        }

                        if (area.type === 'SMOKE' && !is_ally) {
                            p.isSilenced = true;
                            p.lastSilenceTime = now;
                            if (!p.isBlinded) {
                                p.isBlinded = true;
                                io.to(pSocketId).emit('blindState', { active: true });
                            }
                            p.lastBlindTime = now;
                        } else if (area.type === 'ICE' && !is_ally) {
                            const prevSlow = p.isSlowed;
                            p.isSlowed = true;
                            p.lastSlowTime = now;
                            p.slowPoints = (area.slowAmount || 0.5) * 100;
                            
                            if (!prevSlow) {
                                io.to(pSocketId).emit('slowState', { active: true, amount: p.slowPoints });
                            }
                        }
                    }
                }
            });

            // Efectos a Enemigos
            Object.values(enemies).forEach(e => {
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
