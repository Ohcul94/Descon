// OrbitAI.js (Cerebro de Enjambre/Flanqueo v85.11)
const BaseAI = require('./BaseAI');

module.exports = class OrbitAI extends BaseAI {
    constructor(enemy, config) {
        super(enemy, config);
        this.orbitRadius = config.orbitRadius || 250;
        this.orbitDir = Math.random() > 0.5 ? 1 : -1;
    }

    applyMovementLogic(target, dist, angle, now) {
        // Táctica: Rodear al objetivo (Swarm Tactic)
        const targetDist = this.orbitRadius;
        const speed = this.config.speed || 3.0; // Los que rodean suelen ser un poco más lentos que los kamikaze

        if (dist > targetDist + 50) {
            // Acercarse
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < targetDist - 50) {
            // Alejarse un poco si está muy cerca
            this.enemy.x -= Math.cos(angle) * speed;
            this.enemy.y -= Math.sin(angle) * speed;
        }

        // Movimiento Orbital (Flanqueo v84.0)
        const orbitAngle = angle + (Math.PI / 2 * this.orbitDir);
        this.enemy.x += Math.cos(orbitAngle) * speed * 0.8;
        this.enemy.y += Math.sin(orbitAngle) * speed * 0.8;

        this.enemy.rotation = angle + Math.PI / 2;
        
        // Mecánica de Evasión Integrada (v82.0)
        if (this.enemy.hp < this.enemy.maxHp * 0.25 && now - (this.enemy.lastDash || 0) > 10000) {
            const dashAngle = angle + (Math.PI / 2 + (Math.random() - 0.5));
            this.enemy.x += Math.cos(dashAngle) * 200;
            this.enemy.y += Math.sin(dashAngle) * 200;
            this.enemy.lastDash = now;
        }
    }
};
