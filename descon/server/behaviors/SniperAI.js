// SniperAI.js (Cerebro de Hostigamiento v1.0)
const BaseAI = require('./BaseAI');

module.exports = class SniperAI extends BaseAI {
    constructor(enemy, config) {
        super(enemy, config);
        this.idealDist = 450; // Distancia preferida del francotirador
    }

    applyMovementLogic(target, dist, angle, now) {
        const speed = this.config.speed || 3.0;
        
        // Lógica de Mantenimiento de Distancia (Kiting)
        if (dist > this.idealDist + 50) {
            // Demasiado lejos, acercarse un poco
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < this.idealDist - 50) {
            // Demasiado cerca, alejarse (Retirada táctica)
            this.enemy.x -= Math.cos(angle) * (speed * 1.2);
            this.enemy.y -= Math.sin(angle) * (speed * 1.2);
        } else {
            // Distancia ideal: Orbitar lentamente para no ser un blanco estático
            const orbitAngle = angle + Math.PI / 2;
            this.enemy.x += Math.cos(orbitAngle) * (speed * 0.5);
            this.enemy.y += Math.sin(orbitAngle) * (speed * 0.5);
        }

        this.enemy.rotation = angle + Math.PI / 2;
    }

    applyCombatLogic(target, dist, angle, now, io) {
        if (dist > 1000) return;

        if (now > (this.enemy.nextShotTime || 0)) {
            const isIceSniper = (this.enemy.type == 2);
            const burstLimit = isIceSniper ? 1 : 3; 

            if ((this.enemy.shotsInBurst || 0) < burstLimit) {
                const currentAngle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);
                const bSpeed = isIceSniper ? 500 : (this.config.bulletSpeed || 800); 
                const bType = isIceSniper ? "ice_missile" : "laser";

                if (isIceSniper && now % 5000 < 33) {
                    console.log(`[DEBUG-ICE] Enemigo ${this.enemy.id} disparando hielo a ${target.user}`);
                }

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target.id,
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, angle: currentAngle,
                    bulletSpeed: bSpeed, 
                    bulletType: bType,
                    damage: (this.config && this.config.bulletDamage) ? this.config.bulletDamage : (this.enemy.type * 100)
                });
                this.enemy.shotsInBurst = (this.enemy.shotsInBurst || 0) + 1;
                this.enemy.nextShotTime = now + (isIceSniper ? 2000 : 150);
            } else {
                this.enemy.shotsInBurst = 0;
                this.enemy.nextShotTime = now + (this.config.fireRate || 2000);
            }
        }
    }
}
