// SniperAI.js (Cerebro de Hostigamiento v1.0)
const BaseAI = require('./BaseAI');

module.exports = class SniperAI extends BaseAI {
    constructor(enemy, config) {
        super(enemy, config);
        this.idealDist = 450; // Distancia preferida del francotirador
    }

    applyMovementLogic(target, dist, angle, now) {
        const speed = this.config.speed || 3.0;
        const idealDist = this.config.idealDist || 450;
        
        // Lógica de Mantenimiento de Distancia (Kiting)
        if (dist > idealDist + 50) {
            // Demasiado lejos, acercarse un poco
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < idealDist - 50) {
            // Demasiado cerca, alejarse (Retirada táctica)
            this.enemy.x -= Math.cos(angle) * (speed * 1.2);
            this.enemy.y -= Math.sin(angle) * (speed * 1.2);
        } else {
            // Distancia ideal: Orbitar lentamente para no ser un blanco estático
            const orbitAngle = angle + Math.PI / 2;
            this.enemy.x += Math.cos(orbitAngle) * (speed * 0.5);
            this.enemy.y += Math.sin(orbitAngle) * (speed * 0.5);
        }
    }
}
