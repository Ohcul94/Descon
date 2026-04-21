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
        let minDist = 800; // Rango de visión táctica
        Object.values(players).forEach(p => {
            if (p.zone !== this.enemy.zone) return;
            const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
            if (d < minDist) { minDist = d; closest = p; }
        });
        return closest;
    }

    applyCombatLogic(target, dist, angle, now, io) {
        if (dist > 600) return; // Fuera de rango de fuego

        if (now > (this.enemy.nextShotTime || 0)) {
            if ((this.enemy.shotsInBurst || 0) < 3) {
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target.id,
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, angle: angle,
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
        // Por defecto: Chase (Persecución)
        if (dist > 50) {
            this.enemy.x += Math.cos(angle) * 3.5;
            this.enemy.y += Math.sin(angle) * 3.5;
        }
        this.enemy.rotation = angle + Math.PI / 2;
    }
};
