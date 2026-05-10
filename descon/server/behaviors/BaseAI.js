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
        const angle = Math.atan2(activeTarget.y - this.enemy.y, activeTarget.x - this.enemy.x);

        this.applyCombatLogic(activeTarget, dist, angle, now, io);
        this.applyMovementLogic(activeTarget, dist, angle, now);
        
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
        
        // Si no hay mecánicas nuevas, usar el fallback del config raíz (compatibilidad)
        if (mechanics.length === 0) {
            this._executeMechanic(this.config, "default", target, dist, angle, now, io);
            return;
        }

        mechanics.forEach((mech, idx) => {
            const mId = `mech_${idx}`;
            // v266.225: Verificar Retraso de Inicio (Start Delay)
            const timeSinceSpawn = now - this.enemy.spawnTime;
            if (timeSinceSpawn < (mech.startDelay || 0)) return;

            this._executeMechanic(mech, mId, target, dist, angle, now, io);
        });
    }

    _executeMechanic(mech, mId, target, dist, angle, now, io) {
        const state = this.enemy.mechState[mId] || { nextShotTime: 0, shotsInBurst: 0 };
        const fireRange = mech.fireRange || 800;

        if (dist > fireRange) return;

        if (now > state.nextShotTime) {
            const burstLimit = (mech.type === "laser") ? 3 : 1; 
            if (state.shotsInBurst < burstLimit) {
                const currentAngle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);
                
                // v266.240: Compatibilidad de tipos para el cliente Godot

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target.id,
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, angle: currentAngle,
                    bulletSpeed: mech.bulletSpeed || 800, 
                    bulletType: mech.type || "laser",
                    damage: mech.bulletDamage || (this.enemy.type * 100),
                    // v266.220: Pasar datos extra de la mecánica (Slow, Combustible, Giro)
                    slowAmount: mech.slowAmount || 0,
                    slowDuration: mech.slowDuration || 0,
                    lifetimeMs: mech.lifetimeMs || 0,
                    turnSpeed: mech.turnSpeed || 2.5
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
