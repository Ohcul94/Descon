// ChaseAI.js (Cerebro Kamikaze v85.12)
const BaseAI = require('./BaseAI');

module.exports = class ChaseAI extends BaseAI {
    applyMovementLogic(target, dist, angle, now) {
        let speed = this.config.speed || 4.5;
        
        // Efecto Kamikaze: Eliminado para evitar efecto "imán" y sincronizar con velocidad del jugador
        const targetDist = 150;
        // if (dist < targetDist) speed *= 1.5; 

        const stopDist = 80;
        if (dist > stopDist) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < stopDist - 20) {
            // Repulsión para no quedarse "encimado"
            this.enemy.x -= Math.cos(angle) * (speed * 0.4);
            this.enemy.y -= Math.sin(angle) * (speed * 0.4);
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
