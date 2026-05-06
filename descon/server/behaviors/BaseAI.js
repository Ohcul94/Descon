// BaseAI.js (Cerebro General v85.10)
module.exports = class BaseAI {
    constructor(enemy, config) {
        this.enemy = enemy;
        this.config = config;
        this.lastAction = 0;
    }

    update(players, now, io) {
        // Encontrar objetivo más cercano
        let target = this.getNearestPlayer(players);
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

    getNearestPlayer(players) {
        let closest = null;
        let minDist = this.enemy.isHorde ? 10000 : 800; 
        
        for (const id in players) {
            const p = players[id];
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
        if (dist > 1000) return; // Rango aumentado para hordas

        if (now > (this.enemy.nextShotTime || 0)) {
            if ((this.enemy.shotsInBurst || 0) < 3) {
                // Recalcular ángulo exacto al disparar para evitar "disparar a la nada"
                const currentAngle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);
                const bSpeed = this.config.bulletSpeed || 800; 

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target.id,
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, angle: currentAngle,
                    bulletSpeed: bSpeed, 
                    damage: (this.config && this.config.bulletDamage) ? this.config.bulletDamage : (this.enemy.type * 100)
                });
                this.enemy.shotsInBurst = (this.enemy.shotsInBurst || 0) + 1;
                this.enemy.nextShotTime = now + 150;
            } else {
                this.enemy.shotsInBurst = 0;
                this.enemy.nextShotTime = now + (this.config.fireRate || 2000);
            }
        }
    }

    applyMovementLogic(target, dist, angle, now) {
        // v250.10: Suavizado de proximidad para evitar efecto "imán"
        const speed = this.config.speed || 3.5;
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
