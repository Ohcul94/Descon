// MechanicBossAI.js (Dungeon Boss Exclusivo)
const BaseAI = require('./BaseAI');

module.exports = class MechanicBossAI extends BaseAI {
    applyMovementLogic(target, dist, angle, now) {
        let speed = this.config.speed || 3.0;

        // Fase 1: Movimiento Base
        if (this.enemy.hp > this.enemy.maxHp * 0.5) {
            // Orbita alrededor del jugador
            const idealDist = 400;
            if (dist > idealDist) {
                this.enemy.x += Math.cos(angle) * speed;
                this.enemy.y += Math.sin(angle) * speed;
            } else {
                // Rotación lateral si está muy cerca
                this.enemy.x += Math.cos(angle + Math.PI/2) * speed;
                this.enemy.y += Math.sin(angle + Math.PI/2) * speed;
            }
        } 
        // Fase 2: Escudo y Evasión (Por debajo del 50%)
        else {
            speed *= 0.8; // Más lento pero impredecible
            const retreatAngle = angle + Math.PI; // Alejar
            this.enemy.x += Math.cos(retreatAngle) * speed;
            this.enemy.y += Math.sin(retreatAngle) * speed;
            
            // Opcional: Podríamos regenerar escudo si hace falta
        }

        this.enemy.rotation = angle + Math.PI / 2;
    }

    applyFiringLogic(io, zoneStr) {
        const now = Date.now();
        // Activa escudo visual si HP < 50%
        this.isInvulnerable = false; // Aquí puedes encender invulnerabilidad mecánica
        
        // Fase 2: Disparo en Anillo (Burst multidireccional)
        if (this.enemy.hp < this.enemy.maxHp * 0.5) {
            if (now - this.enemy.nextShotTime > 0) {
                // Dispara balas en 8 direcciones
                for(let i=0; i<8; i++) {
                    const fireAngle = (Math.PI / 4) * i;
                    const dmg = this.config.bulletDamage * 0.5; // Menos daño pero muchas balas
                    io.to(zoneStr).emit('serverEnemyFire', {
                        id: this.enemy.id,
                        x: this.enemy.x, y: this.enemy.y,
                        rotation: fireAngle, dmg: dmg
                    });
                }
                this.enemy.nextShotTime = now + 4000; // Cadencia pesada
            }
        } else {
            // Disparo normal hacia el objetivo (heredado pero modificado)
            if (now - this.enemy.nextShotTime > 0) {
                io.to(zoneStr).emit('serverEnemyFire', {
                    id: this.enemy.id,
                    x: this.enemy.x, y: this.enemy.y,
                    rotation: this.enemy.rotation,
                    dmg: this.config.bulletDamage
                });
                this.enemy.nextShotTime = now + 1500;
            }
        }
    }
};
