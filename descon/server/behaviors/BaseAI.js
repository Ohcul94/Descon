// BaseAI.js (Cerebro General v85.10)
module.exports = class BaseAI {
    constructor(enemy, config) {
        this.enemy = enemy;
        this.config = config;
        this.lastAction = 0;
    }

    update(grid, players, now, io) {
        // v247.10: Optimización de búsqueda de objetivos vía Grid
        let target = this.getNearestPlayer(grid, players);
        if (!target) return;

        const dist = Math.hypot(target.x - this.enemy.x, target.y - this.enemy.y);
        const angle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);

        this.applyCombatLogic(target, dist, angle, now, io);
        this.applyMovementLogic(target, dist, angle, now);
        
        // Regeneración pasiva standard v82.10
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
                    // v266.220: Pasar datos extra de la mecánica (Slow, etc)
                    slowAmount: mech.slowAmount || 0,
                    slowDuration: mech.slowDuration || 0
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
