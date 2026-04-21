// ChaseAI.js (Cerebro Kamikaze v85.12)
const BaseAI = require('./BaseAI');

module.exports = class ChaseAI extends BaseAI {
    applyMovementLogic(target, dist, angle, now) {
        let speed = this.config.speed || 4.5;
        
        // Efecto Kamikaze: Acelerar cuando está cerca
        const targetDist = 150;
        if (dist < targetDist) speed *= 1.5;

        if (dist > 50) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        }

        this.enemy.rotation = angle + Math.PI / 2;
        
        // Evasión Lateral Táctica
        if (this.enemy.hp < this.enemy.maxHp * 0.15 && now - (this.enemy.lastDash || 0) > 8000) {
            const dashAngle = angle + (Math.PI / 2 + (Math.random() - 0.5));
            this.enemy.x += Math.cos(dashAngle) * 250;
            this.enemy.y += Math.sin(dashAngle) * 250;
            this.enemy.lastDash = now;
        }
    }
};
