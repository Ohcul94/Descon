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
        
        // v266.999: Detección de Agresividad Extrema Ambiental (Blindado Total)
        const zoneId = this.enemy.zone;
        const currentConfig = (this.state && this.state.SERVER_CONFIG) ? this.state.SERVER_CONFIG : {};
        const maps = currentConfig.mapsConfig || {};
        const mapCfg = maps[zoneId] || maps[zoneId.toString()];
        const extremeAggro = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'extreme_aggression') : null;
        
        this.ambienceBoost = extremeAggro || null;
        
        // Log de Diagnóstico (Solo cuando hay cambio de estado o detección inicial)
        if (this.ambienceBoost && !this._lastAmbienceLog) {
            console.log(`[EXTREME-AGGRO] Activado en Zona ${zoneId}. Mults -> Daño: ${this.ambienceBoost.damageMult}, Velocidad: ${this.ambienceBoost.speedMult}, Vida: ${this.ambienceBoost.healthMult}`);
            this._lastAmbienceLog = true;
        }

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

        if (this.enemy.lastHitter && players[this.enemy.lastHitter]) {
            const idleTime = now - (this.enemy.lastHit || 0);
            const idleLimit = cfg.chaseIdleTimeout || 0; // 0 = Desactivado
            
            if (idleLimit === 0 || idleTime < idleLimit) {
                activeTarget = players[this.enemy.lastHitter];
                isRevenge = true;
            } else {
                this.enemy.lastHitter = null; 
            }
        }

        // Si no está en modo venganza (o se le pasó el enojo) y es agresivo, busca al más cercano
        if (!activeTarget && isAggressive) {
            activeTarget = potentialTarget;
        }

        // v266.999: Si hay mecánicas activas O es Agresividad Extrema, NO PODEMOS soltar el flujo
        const hasActiveMech = this.enemy.mechState && Object.values(this.enemy.mechState).some(m => m.isActive);
        const isExtreme = !!this.ambienceBoost;
        
        if ((!activeTarget || activeTarget.isDead || activeTarget.isInvisible) && !hasActiveMech && !isExtreme) return;

        // v266.999: Valores seguros si el target desapareció pero el ataque sigue
        const dist = activeTarget ? Math.hypot(activeTarget.x - this.enemy.x, activeTarget.y - this.enemy.y) : 99999;
        const targetAngle = activeTarget ? Math.atan2(activeTarget.y - this.enemy.y, activeTarget.x - this.enemy.x) : this.enemy.rotation;

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
        
        // v266.999: Simular rotación (delta de tiempo aproximado 100ms por ciclo de IA)
        if (this.enemy.rotation === undefined) this.enemy.rotation = targetAngle;
        const firstMech = cfg.mechanics ? cfg.mechanics[0] : null;
        const turnSpeed = firstMech ? (firstMech.turnSpeed || 5.0) : 5.0;
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

        // v266.920: Procesar combate pero NO bloquear movimiento (salvo que la mecánica sea estática por diseño)
        this.applyCombatLogic(activeTarget, dist, targetAngle, now, io);
        
        if (activeTarget) {
            this.applyMovementLogic(activeTarget, dist, targetAngle, now);
        }
        
        // Regeneración pasiva standard
        if (now - (this.enemy.lastHit || 0) > 5000 && this.enemy.shield < this.enemy.maxShield) {
            this.enemy.shield = Math.min(this.enemy.maxShield, this.enemy.shield + (this.enemy.maxShield * 0.01));
        }
    }

    getNearestPlayer(grid, players) {
        let closest = null;
        // v266.999: Si hay Agresividad Extrema, el rango de visión es GLOBAL y exhaustivo
        const visionRange = this.ambienceBoost ? 50000 : (this.enemy.isHorde ? 10000 : 800);
        let minDist = visionRange; 
        
        // v266.999: Si es extremo, buscamos en todos los jugadores del servidor, no solo los "cercanos"
        const targets = (grid && !this.ambienceBoost && !this.enemy.isHorde) ? grid.getNearbyEntities(this.enemy.x, this.enemy.y).players : Object.values(players);

        for (const p of targets) {
            // v266.999: Si hay Agresividad Extrema, ignoramos la invisibilidad. El bicho TE HUELE.
            if (!p || p.isDead || p.zone !== this.enemy.zone) continue;
            if (p.isInvisible && !this.ambienceBoost) continue; 
            
            // v252.22: Validación de Integridad del Target
            if (typeof p.x !== 'number' || typeof p.y !== 'number') continue;
            if (!p.user) continue; 

            const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
            if (d < minDist) {
                minDist = d;
                closest = p;
            }
        }
        return closest;
    }

    applyCombatLogic(target, dist, angle, now, io) {
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

            if (this._executeMechanic(mech, mId, target, dist, angle, now, io)) {
                isBusy = true;
            }
        });
        return isBusy;
    }

    _executeMechanic(mech, mId, target, dist, angle, now, io) {
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

    applyMovementLogic(target, dist, angle, now) {
        // v250.10: Suavizado de proximidad para evitar efecto "imán"
        // v266.999: Multiplicador de Velocidad Ambiental
        const speedMult = this.ambienceBoost ? (this.ambienceBoost.speedMult || 1) : 1;
        const baseSpeed = (this.config.speed || 3.5) * speedMult;
        const slowMult = this.enemy.slowMultiplier || 1.0;
        const speed = baseSpeed * slowMult;
        
        const stopDist = 120; // Distancia de seguridad aumentada
        
        if (dist > stopDist) {
            // Si está lejos, se acerca normal
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < stopDist - 20) {
            // Si se pegó demasiado, retrocede un poquito (Repulsión natural)
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
