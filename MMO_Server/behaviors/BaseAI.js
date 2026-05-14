// BaseAI.js (Cerebro General v85.10)
module.exports = class BaseAI {
    constructor(enemy, config, state) {
        this.enemy = enemy;
        this.config = config;
        this.state = state;
        this.lastAction = 0;
    }

    update(grid, players, now, io) {
        const cfg = this.config;
        
        // v266.999: Detección de Agresividad Extrema Ambiental (Búsqueda Ultra-Robusta)
        const zoneId = this.enemy.zone;
        const currentConfig = (this.state && this.state.SERVER_CONFIG) ? this.state.SERVER_CONFIG : {};
        const maps = currentConfig.mapsConfig || currentConfig.maps || currentConfig.mapData || {};
        
        // Intentar encontrar el mapa por ID (2), String ("2") o Nombre ("Mapa 2")
        let mapCfg = maps[zoneId] || maps[zoneId.toString()];
        if (!mapCfg) {
            mapCfg = Object.values(maps).find(m => m.name === zoneId || m.name === `Mapa ${zoneId}` || m.name === zoneId.toString());
        }

        const extremeAggro = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'extreme_aggression') : null;
        
        this.ambienceBoost = extremeAggro || null;
        
        // v266.999: Si hay ambiente extremo, el bicho ES agresivo por definición
        const isAggressive = (this.ambienceBoost) ? true : (cfg.aggressive !== false);
        this.enemy.isAggressive = isAggressive; // Restaurar propiedad para otros sistemas

        // v266.999: Inyectar velocidad ambiental dinámicamente
        if (!this._baseSpeed) this._baseSpeed = cfg.speed || 3.5;
        const speedMult = this.ambienceBoost ? (parseFloat(this.ambienceBoost.speedMult) || 1) : 1;
        cfg.speed = this._baseSpeed * speedMult;
        
        // v266.580: Inicialización de seguridad para nuevos enemigos
        if (!this.enemy.lastSuccessHit) this.enemy.lastSuccessHit = now;
        if (!this.enemy.lastHit) this.enemy.lastHit = 0;

        // v266.970: Lógica de Fases de Movimiento (Kamikaze Check)
        const phases = cfg.movementPhases || [];
        const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
        const kamikazePhase = phases.find(p => p.type === 'kamikaze');

        if (kamikazePhase && hpPercent <= (kamikazePhase.activationHP || 30)) {
            if (!this.enemy.isKamikazeActive) {
                this.enemy.isKamikazeActive = true;
                this.enemy.kamikazeStartTime = now;
                this.enemy.isRamming = true;
                
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id, action: "kamikaze_start", duration: kamikazePhase.duration || 5000
                });
            }
        }

        // v266.550: Búsqueda de objetivo potencial (Visión Pasiva)
        let potentialTarget = this.getNearestPlayer(grid, players);
        
        // v266.560: Lógica de AGRO (Quién tiene la atención del bicho)
        let activeTarget = null;
        let isRevenge = false;

        // 1. REPRESALIA: Prioridad al que me pegó (Si el idleLimit no expiró)
        if (this.enemy.lastHitter && players[this.enemy.lastHitter]) {
            const idleTime = now - (this.enemy.lastHit || 0);
            const idleLimit = (this.ambienceBoost) ? 30000 : (cfg.chaseIdleTimeout || 10000); 
            
            if (idleTime < idleLimit) {
                activeTarget = players[this.enemy.lastHitter];
                isRevenge = true;
            } else {
                this.enemy.lastHitter = null; 
            }
        }

        // 2. PROXIMIDAD: Si soy agresivo y no tengo venganza pendiente, busco al más cercano
        if (!activeTarget && isAggressive) {
            activeTarget = potentialTarget;
        }

        // v266.999: Si hay mecánicas activas O es Agresividad Extrema, NO PODEMOS soltar el flujo
        const hasActiveMech = this.enemy.mechState && Object.values(this.enemy.mechState).some(m => m.isActive);
        const isExtreme = !!this.ambienceBoost;
        
        if ((!activeTarget || activeTarget.isDead || activeTarget.isInvisible) && !hasActiveMech && !isExtreme) {
            this.enemy.isMoving = false;
            return;
        }
        
        this.enemy.isMoving = true;

        // v266.999: Valores seguros si el target desapareció pero el ataque sigue
        const dist = activeTarget ? Math.hypot(activeTarget.x - this.enemy.x, activeTarget.y - this.enemy.y) : 99999;
        const targetAngle = activeTarget ? Math.atan2(activeTarget.y - this.enemy.y, activeTarget.x - this.enemy.x) : this.enemy.rotation;

        // v266.999: Lógica de Persistencia (Basada en Dashboard)
        const canSee = activeTarget && dist < (cfg.fireRange || 1000) * 1.5;
        if (!isExtreme && !cfg.chaseUntilDeath && cfg.stopOnOutOfSight && !canSee && !isRevenge) {
            this.enemy.isMoving = false;
            return;
        }

        // v266.975: Ejecución del Estado Kamikaze (Prioridad sobre combate normal)
        if (this.enemy.isKamikazeActive) {
            const kP = (cfg.movementPhases || []).find(p => p.type === 'kamikaze') || {};
            let speed = (kP.speed !== undefined) ? (kP.speed * 0.033) : (cfg.speed || 3.5) * 1.5;
            const duration = kP.duration || 5000;

            if (now - this.enemy.kamikazeStartTime > duration || (activeTarget && dist < 60)) {
                this.enemy.hp = 0;
                this.enemy.forceExplosion = true;
                return;
            }

            this.enemy.x += Math.cos(targetAngle) * speed;
            this.enemy.y += Math.sin(targetAngle) * speed;
            this.enemy.rotation = targetAngle + Math.PI / 2;
            return; 
        }
        
        // v266.999: Rotación de Cuerpo - Mirar SIEMPRE al objetivo (v266.999)
        if (this.enemy.rotation === undefined) this.enemy.rotation = targetAngle;
        const turnSpeed = 5.0; // Velocidad de giro del cuerpo
        const delta = 0.1; 
        let diff = targetAngle - this.enemy.rotation;
        while (diff < -Math.PI) diff += Math.PI * 2;
        while (diff > Math.PI) diff -= Math.PI * 2;
        
        const step = turnSpeed * delta;
        if (Math.abs(diff) < step) {
            this.enemy.rotation = targetAngle;
        } else {
            this.enemy.rotation += Math.sign(diff) * step;
        }

        // v268.810: Procesar combate y movimiento
        this.applyCombatLogic(activeTarget, dist, targetAngle, now, io, grid, players);
        
        if (activeTarget) {
            this.applyMovementLogic(activeTarget, dist, targetAngle, now);
        }
        
        // Regeneración pasiva standard
        if (now - (this.enemy.lastHit || 0) > 5000 && this.enemy.shield < this.enemy.maxShield) {
            this.enemy.shield = Math.min(this.enemy.maxShield, this.enemy.shield + (this.enemy.maxShield * 0.01));
        }
    }

    applyMovementLogic(target, dist, angle, now) {
        // v266.999: Lógica de Persecución Base (Fallback)
        // Si el bicho no tiene una clase de movimiento específica, al menos que te siga
        let speed = this.config.speed || 3.5;
        const stopDist = 80;

        if (dist > stopDist) {
            this.enemy.x += Math.cos(angle) * (speed * 1);
            this.enemy.y += Math.sin(angle) * (speed * 1);
        }
        
        this.enemy.rotation = angle + Math.PI / 2;
    }

    getNearestPlayer(grid, players) {
        let closest = null;
        // v266.999: Si hay Agresividad Extrema, el rango de visión es GLOBAL (50k px)
        const visionRange = this.ambienceBoost ? 50000 : (this.enemy.isHorde ? 10000 : 800);
        let minDist = visionRange; 
        
        // v266.999: Búsqueda exhaustiva sin Grid si es extremo
        const targetList = Object.values(players || {});
        const maps = (this.state && this.state.SERVER_CONFIG) ? (this.state.SERVER_CONFIG.mapsConfig || this.state.SERVER_CONFIG.maps || this.state.SERVER_CONFIG.mapData || {}) : {};
        
        for (const p of targetList) {
            // v266.999: Búsqueda Global (Si el jugador está en una zona extrema, el bicho lo detecta)
            const pZone = parseInt(p.zone);
            const eZone = parseInt(this.enemy.zone);
            
            // Verificamos si la zona del JUGADOR es extrema
            const pMapCfg = maps[pZone] || maps[pZone.toString()];
            const pIsExtreme = (pMapCfg && pMapCfg.ambience && pMapCfg.ambience.some(a => a.type === 'extreme_aggression'));

            if (!p || p.isDead) continue;
            
            // Invisibilidad: Respeto absoluto solicitado por el usuario (v266.999)
            if (p.isInvisible) continue; 
            
            // Si no estamos en la misma zona y la zona del jugador NO es extrema, ignoramos
            if (pZone !== eZone && !pIsExtreme) continue;

            const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
            if (d < minDist) {
                minDist = d;
                closest = p;
            }
        }
        return closest;
    }

    applyCombatLogic(target, dist, angle, now, io, grid, players) {
        // v266.220: Sistema de Rotación de Mecánicas Modulares
        if (!this.enemy.spawnTime) this.enemy.spawnTime = now;
        if (!this.enemy.mechState) this.enemy.mechState = {};

        const mechanics = this.config.mechanics || [];
        let isBusy = false;
        
        // Si no hay mecánicas nuevas, usar el fallback del config raíz (compatibilidad)
        if (mechanics.length === 0) {
            return this._executeMechanic(this.config, "default", target, dist, angle, now, io);
        }

        mechanics.forEach((mech, idx) => {
            const mId = `mech_${idx}`;
            const timeSinceSpawn = now - this.enemy.spawnTime;
            if (timeSinceSpawn < (mech.startDelay || 0)) return;

            if (mech.type && mech.type.startsWith("aura_")) {
                this._handleAuraLogic(mech, mId, now, io, grid, players);
            } else if (this._executeMechanic(mech, mId, target, dist, angle, now, io)) {
                isBusy = true;
            }
        });

        // v268.800: Procesar mecánicas de Defensa y Movimiento (Auras)
        const defMechanics = this.config.defenseMechanics || [];
        defMechanics.forEach((mech, idx) => {
            const mId = `def_${idx}`;
            if (mech.type && mech.type.startsWith("aura_")) {
                this._handleAuraLogic(mech, mId, now, io, grid, players);
            }
        });

        const movPhases = this.config.movementPhases || [];
        movPhases.forEach((mech, idx) => {
            const mId = `mov_${idx}`;
            if (mech.type && mech.type.startsWith("aura_")) {
                this._handleAuraLogic(mech, mId, now, io, grid, players);
            }
        });

        return isBusy;
    }

    _handleAuraLogic(mech, mId, now, io, grid, players) {
        if (!this.enemy.auraState) this.enemy.auraState = {};
        const state = this.enemy.auraState[mId] || { nextStartTime: now + (mech.startDelay || 0), isActive: false, endTime: 0, lastTickTime: 0 };

        // 1. Gestión de Ciclo (Activar/Desactivar)
        const threshold = mech.activationHP || 100;
        const currentHPPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
        const hpMet = currentHPPercent <= threshold;

        if (!state.isActive && now >= state.nextStartTime && hpMet) {
            state.isActive = true;
            state.endTime = now + (mech.duration || 5000);
            state.lastTickTime = 0;
            
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAura', {
                id: this.enemy.id, mId: mId, type: mech.type, radius: mech.radius || 200, duration: mech.duration || 5000, active: true
            });
        } else if (state.isActive && now >= state.endTime) {
            state.isActive = false;
            state.nextStartTime = now + (mech.cooldown || 10000);
            
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAura', {
                id: this.enemy.id, mId: mId, active: false
            });
        }

        // 2. Ejecución de Efecto (Ticks para Daño/Cura, Constante para Velocidad)
        if (state.isActive) {
            if (mech.type === "aura_speed") {
                this._applyAuraEffect(mech, grid, players, io);
            } else {
                const interval = mech.intervalMs || 1000;
                if (now - state.lastTickTime >= interval) {
                    state.lastTickTime = now;
                    this._applyAuraEffect(mech, grid, players, io);
                }
            }
        }
        this.enemy.auraState[mId] = state;
    }

    _applyAuraEffect(mech, grid, players, io) {
        const radius = mech.radius || 200;
        const { players: nearbyPlayers, enemies: nearbyEnemies } = grid.getNearbyEntities(this.enemy.x, this.enemy.y);

        if (mech.type === "aura_damage") {
            nearbyPlayers.forEach(p => {
                if (p.zone === this.enemy.zone && !p.isDead) {
                    const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                    if (d <= radius) {
                        const dmg = mech.damage || 100;
                        p.lastCombatTime = Date.now();
                        if (p.shield >= dmg) p.shield -= dmg;
                        else { p.hp -= (dmg - p.shield); p.shield = 0; }
                        if (p.hp < 0) p.hp = 0;
                        
                        io.to(p.socketId).emit('environmentDamage', { damage: dmg });
                        io.to(`zone_${p.zone}`).emit('playerStatSync', { id: p.socketId, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield) });
                    }
                }
            });
        } else if (mech.type === "aura_heal") {
            const heal = mech.healAmount || 500;
            const affectsEnemies = !!mech.affectsEnemies;
            const affectsBosses = !!mech.affectsBosses;

            // Primero a sí mismo siempre (es el dueño)
            const oldHpOwner = this.enemy.hp;
            this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + heal);
            io.to(`zone_${this.enemy.zone}`).emit('enemyHealed', { 
                id: this.enemy.id, 
                hp: this.enemy.hp, 
                amount: Math.max(0, this.enemy.hp - oldHpOwner) 
            });

            // A otros cercanos
            nearbyEnemies.forEach(e => {
                if (e.id !== this.enemy.id && e.zone === this.enemy.zone && e.hp > 0) {
                    const d = Math.hypot(e.x - this.enemy.x, e.y - this.enemy.y);
                    if (d <= radius) {
                        const isBoss = e.type >= 101;
                        if ((isBoss && affectsBosses) || (!isBoss && affectsEnemies)) {
                            const oldHp = e.hp;
                            e.hp = Math.min(e.maxHp, e.hp + heal);
                            io.to(`zone_${e.zone}`).emit('enemyHealed', { 
                                id: e.id, 
                                hp: e.hp, 
                                amount: Math.max(0, e.hp - oldHp) 
                            });
                        }
                    }
                }
            });
        } else if (mech.type === "aura_speed") {
            const speedBonus = mech.speedBonus || 2.0;
            const affectsEnemies = !!mech.affectsEnemies;
            const affectsBosses = !!mech.affectsBosses;

            // El dueño siempre recibe el bono
            this.enemy.auraSpeedBonus = (this.enemy.auraSpeedBonus || 0) + speedBonus;

            nearbyEnemies.forEach(e => {
                if (e.id !== this.enemy.id && e.zone === this.enemy.zone && e.hp > 0) {
                    const d = Math.hypot(e.x - this.enemy.x, e.y - this.enemy.y);
                    if (d <= radius) {
                        const isBoss = e.type >= 101;
                        if ((isBoss && affectsBosses) || (!isBoss && affectsEnemies)) {
                            e.auraSpeedBonus = (e.auraSpeedBonus || 0) + speedBonus;
                        }
                    }
                }
            });
        }
    }

    _executeMechanic(mech, mId, target, dist, angle, now, io) {
        if (!target || !io) return; // Seguridad v266.999
        
        const zoneStr = `zone_${this.enemy.zone}`;
        const type = mech.type || 'orbital';
        const state = this.enemy.mechState[mId] || { nextShotTime: 0, shotsInBurst: 0, isCharging: false, isActive: false };
        const fireRange = mech.fireRange || 800;

        // v266.998: PRIORIDAD ATÓMICA - Si ya empezó, TERMINA
        if (state.isActive) {
            this._handleOrbitalStrikeLogic(mech, state, mId, now, io);
            this.enemy.mechState[mId] = state;
            return true;
        }

        if (dist > fireRange && !state.isCharging) return false;

        if (mech.type === "orbital_strike") {
            if (now > state.nextShotTime) {
                this._handleOrbitalStrikeLogic(mech, state, mId, now, io);
                this.enemy.mechState[mId] = state;
                return true;
            }
        }

        // v266.600: Lógica de Precarga para Mega Láser
        if (mech.type === "mega_laser") {
            const chargeTime = (mech.chargeTimeMs !== undefined) ? mech.chargeTimeMs : 2000;
            const lockTime = (mech.lockTimeMs !== undefined) ? mech.lockTimeMs : 500;
            const lifetime = (mech.lifetimeMs !== undefined) ? mech.lifetimeMs : 1000;

            if (!state.isCharging && !state.isLocked && !state.isFiring && now > state.nextShotTime) {
                // FASE 1: CARGA (Te sigue apuntando y moviéndose)
                state.isCharging = true;
                state.chargeEndTime = now + chargeTime;
                
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "charging",
                    type: "mega_laser",
                    duration: chargeTime + lockTime, 
                    angle: angle,
                    range: mech.fireRange || 800,
                    targetId: target.id || target.socketId || "" // v266.730: Tracking en tiempo real
                });
            } else if (state.isCharging && now > state.chargeEndTime) {
                // FASE 2: BLOQUEO (Se detiene el apuntado, ventana de esquiva)
                state.isCharging = false;
                state.isLocked = true;
                state.lockedAngle = angle; // Fijamos la mira AQUÍ
                state.lockEndTime = now + lockTime; 

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "locked",
                    type: "mega_laser",
                    duration: lockTime, 
                    angle: state.lockedAngle,
                    range: mech.fireRange || 800,
                    targetId: target.id || target.socketId || ""
                });
            } else if (state.isLocked && now > state.lockEndTime) {
                // FASE 3: DISPARO (Sale el rayo)
                state.isLocked = false;
                state.isFiring = true;
                state.fireEndTime = now + lifetime;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target.id || target.socketId || "",
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, 
                    angle: state.lockedAngle,
                    bulletSpeed: mech.bulletSpeed || 2000, 
                    bulletType: "mega_laser",
                    damage: mech.bulletDamage || 500,
                    lifetimeMs: lifetime,
                    range: mech.fireRange || 800 // v266.715: Sincronía de Rango para el Proyectil
                });
            } else if (state.isFiring && now > state.fireEndTime) {
                state.isFiring = false;
                state.nextShotTime = now + (mech.fireRate || 5000);
            }
            
            this.enemy.mechState[mId] = state;

            // v266.930: Seguimiento de rotación DURANTE la carga
            if (state.isCharging) {
                this.enemy.rotation = angle + Math.PI / 2;
            }

            // v266.695: Inmovilidad durante BLOQUEO y DISPARO
            if (state.isLocked || state.isFiring) {
                this.enemy.rotation = state.lockedAngle + Math.PI / 2;
                return true; 
            }
            return false; 
        }

        if (now > state.nextShotTime) {
            const burstLimit = (mech.type === "laser") ? 3 : 1; 
            if (state.shotsInBurst < burstLimit) {
                const currentAngle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);
                
                // v266.240: Compatibilidad de tipos para el cliente Godot

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target.id || target.socketId || "",
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, angle: currentAngle,
                    bulletSpeed: mech.bulletSpeed || 800, 
                    bulletType: mech.type || "laser",
                    damage: (mech.bulletDamage || (this.enemy.type * 100)) * (this.ambienceBoost ? (parseFloat(this.ambienceBoost.damageMult) || 1) : 1),
                    // v266.220: Pasar datos extra de la mecánica (Slow, Combustible, Giro)
                    slowAmount: mech.slowAmount || 0,
                    slowDuration: mech.slowDuration || 0,
                    lifetimeMs: mech.lifetimeMs || 0,
                    turnSpeed: mech.turnSpeed || 2.5,
                    isHoming: !!mech.isHoming,
                    range: mech.fireRange || 800
                });

                state.shotsInBurst++;
                state.nextShotTime = now + 150;
            } else {
                state.shotsInBurst = 0;
                state.nextShotTime = now + (mech.fireRate || 2000);
            }
        }
        this.enemy.mechState[mId] = state;
    }

    getSpeed() {
        const speedMult = this.ambienceBoost ? (this.ambienceBoost.speedMult || 1) : 1;
        const baseSpeed = (this.config.speed || 3.5) * speedMult;
        const slowMult = this.enemy.slowMultiplier || 1.0;
        
        // v268.830: El bono viene en px/s del panel, convertir a px/tick (* 0.033)
        const auraBonus = (this.enemy.auraSpeedBonus || 0) * 0.033;
        
        return (baseSpeed + auraBonus) * slowMult;
    }

    applyMovementLogic(target, dist, angle, now) {
        const speed = this.getSpeed();
        const stopDist = 120; 
        
        if (dist > stopDist) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < stopDist - 20) {
            this.enemy.x -= Math.cos(angle) * (speed * 0.5);
            this.enemy.y -= Math.sin(angle) * (speed * 0.5);
        }
        
        this.enemy.rotation = angle + Math.PI / 2;
    }

    _handleOrbitalStrikeLogic(mech, state, mId, now, io) {
        const orbitDuration = mech.orbitDuration || 3000;
        const staticTime = mech.staticTime || 1000;
        const fireRate = mech.fireRate || 5000;
        const radius = mech.orbitRadius || 180;
        const speed = mech.orbitSpeed || 2.0;
        const count = mech.circleCount || 4;

        if (!state.isActive) {
            // FASE 1: INICIO
            state.isActive = true;
            state.isOrbiting = true;
            state.orbitStartTime = now;
            state.orbitEndTime = now + orbitDuration;
            
            const strikeId = Date.now().toString();
            state.strikeId = strikeId;

            for (let i = 0; i < count; i++) {
                const angleOffset = (i * Math.PI * 2 / count);
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id, 
                    x: this.enemy.x, y: this.enemy.y, 
                    angle: angleOffset,
                    bulletSpeed: mech.bulletSpeed || 1200, 
                    bulletType: "orbital_mine",
                    strikeId: strikeId, 
                    damage: (mech.bulletDamage || 100) * (this.ambienceBoost ? (parseFloat(this.ambienceBoost.damageMult) || 1) : 1), 
                    range: mech.fireRange || 1000,
                    isOrbiting: true,
                    orbitRadius: radius,
                    orbitSpeed: speed,
                    orbitAngleOffset: angleOffset
                });
            }

            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                id: this.enemy.id, action: "orbital_strike_start", strikeId: strikeId
            });
        } else {
            // PROCESAR FASES EXISTENTES
            if (state.isOrbiting && now > state.orbitEndTime) {
                state.isOrbiting = false;
                state.isStatic = true;
                state.staticEndTime = now + staticTime;
                
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id, action: "orbital_strike_static", duration: staticTime
                });
            } else if (state.isStatic && now > state.staticEndTime) {
                state.isStatic = false;
                state.isFiring = true;
                state.fireEndTime = now + 500; 
                state.nextShotTime = now + fireRate;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id, action: "orbital_strike_fire"
                });
            } else if (state.isFiring && now > state.fireEndTime) {
                state.isFiring = false;
                state.isActive = false; // FIN DEL CICLO
            }
        }
    }
};
