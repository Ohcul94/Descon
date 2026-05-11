// BaseAI.js (Cerebro General v85.10)
module.exports = class BaseAI {
    constructor(enemy, config) {
        this.enemy = enemy;
        this.config = config;
        this.lastAction = 0;
    }

    update(grid, players, now, io) {
        const cfg = this.config;
        const isAggressive = cfg.aggressive !== false;
        
        // v266.580: Inicialización de seguridad para nuevos enemigos
        if (!this.enemy.lastSuccessHit) this.enemy.lastSuccessHit = now;
        if (!this.enemy.lastHit) this.enemy.lastHit = 0;

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

        if (!activeTarget || activeTarget.isDead || activeTarget.isInvisible) return;

        // v266.570: REGLAS DE RETIRADA (Chase Rules)
        if (!cfg.chaseUntilDeath) {
            const dist = Math.hypot(activeTarget.x - this.enemy.x, activeTarget.y - this.enemy.y);
            
            // 1. Fuera de Visión (venga de donde venga)
            const visionLimit = (cfg.fireRange || 800) * 1.5;
            if (cfg.stopOnOutOfSight !== false && dist > visionLimit) {
                this.enemy.lastHitter = null;
                return;
            }

            // 2. Tiempo sin acertar (Frustración) - Solo aplica si es > 0
            if (cfg.chaseMissTimeout > 0 && !isRevenge) {
                const missTime = now - (this.enemy.lastSuccessHit || 0);
                if (missTime > cfg.chaseMissTimeout) return;
            }
        }

        const dist = Math.hypot(activeTarget.x - this.enemy.x, activeTarget.y - this.enemy.y);
        const targetAngle = Math.atan2(activeTarget.y - this.enemy.y, activeTarget.x - this.enemy.x);
        
        // v266.650: Apuntado Gradual (Aim Speed)
        if (this.enemy.rotation === undefined) this.enemy.rotation = targetAngle;
        
        // Obtenemos la agilidad de giro de la primera mecánica disponible (o 5.0 por defecto)
        const firstMech = cfg.mechanics ? cfg.mechanics[0] : null;
        const turnSpeed = firstMech ? (firstMech.turnSpeed || 5.0) : 5.0;
        
        // Simular rotación (delta de tiempo aproximado 100ms por ciclo de IA)
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

        // v266.920: Pasar el targetAngle PURO para disparos precisos, ignorando la rotación visual 3D
        if (this.applyCombatLogic(activeTarget, dist, targetAngle, now, io)) {
            return; // v266.696: Bloqueo de movimiento por estado de disparo/carga
        }
        this.applyMovementLogic(activeTarget, dist, targetAngle, now); // v266.690: Movimiento directo al target, rotación gradual visual
        
        // Regeneración pasiva standard
        if (now - (this.enemy.lastHit || 0) > 5000 && this.enemy.shield < this.enemy.maxShield) {
            this.enemy.shield = Math.min(this.enemy.maxShield, this.enemy.shield + (this.enemy.maxShield * 0.01));
        }
    }

    getNearestPlayer(grid, players) {
        let closest = null;
        let minDist = this.enemy.isHorde ? 10000 : 800; 
        
        // v247.10: Si hay grid, limitamos la búsqueda a celdas adyacentes
        const targets = (grid && !this.enemy.isHorde) ? grid.getNearbyEntities(this.enemy.x, this.enemy.y).players : Object.values(players);

        for (const p of targets) {
            if (!p || p.isDead || p.zone !== this.enemy.zone || p.isInvisible) continue;
            
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
            // v266.225: Verificar Retraso de Inicio (Start Delay)
            const timeSinceSpawn = now - this.enemy.spawnTime;
            if (timeSinceSpawn < (mech.startDelay || 0)) return;

            if (this._executeMechanic(mech, mId, target, dist, angle, now, io)) {
                isBusy = true;
            }
        });
        return isBusy;
    }

    _executeMechanic(mech, mId, target, dist, angle, now, io) {
        const state = this.enemy.mechState[mId] || { nextShotTime: 0, shotsInBurst: 0, isCharging: false };
        const fireRange = mech.fireRange || 800;

        if (dist > fireRange && !state.isCharging) return false;

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
                    damage: mech.bulletDamage || (this.enemy.type * 100),
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
        const baseSpeed = this.config.speed || 3.5;
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
};
