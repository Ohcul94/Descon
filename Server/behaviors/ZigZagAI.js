// ZigZagAI.js (Cerebro ZigZag v1.0)
const BaseAI = require('./BaseAI');

module.exports = class ZigZagAI extends BaseAI {
    constructor(enemy, config, state) {
        super(enemy, config, state);
        this.amplitude = config.amplitude !== undefined ? config.amplitude : 100;
        this.frequency = config.frequency !== undefined ? config.frequency : 1.5;
        this.stopDist = config.stopDist !== undefined ? config.stopDist : 150;
    }

    applyMovementLogic(target, dist, angle, now) {
        const speed = this.getSpeed();
        const stopDist = this.stopDist;

        if (dist > stopDist) {
            // Dirección unitaria hacia el objetivo
            const dirX = Math.cos(angle);
            const dirY = Math.sin(angle);

            // Vector perpendicular para el desplazamiento lateral
            const perpX = -dirY;
            const perpY = dirX;

            // Oscilación senoidal lateral
            // now está en milisegundos, por lo que now / 1000 nos da los segundos transcurridos
            const timeSec = now / 1000;
            const phase = 2 * Math.PI * this.frequency * timeSec;
            const lateralSpeedMult = Math.cos(phase);

            // Avance frontal del tick
            const stepForwardX = dirX * speed;
            const stepForwardY = dirY * speed;

            // Desplazamiento lateral del tick (derivada de la amplitud senoidal escalada para el delta de tiempo ~33ms)
            const stepLateralX = perpX * (this.amplitude * 2 * Math.PI * this.frequency) * lateralSpeedMult * 0.033;
            const stepLateralY = perpY * (this.amplitude * 2 * Math.PI * this.frequency) * lateralSpeedMult * 0.033;

            this.enemy.x += stepForwardX + stepLateralX;
            this.enemy.y += stepForwardY + stepLateralY;
        } else if (dist < stopDist - 20) {
            // Repulsión para no quedarse encimado
            this.enemy.x -= Math.cos(angle) * (speed * 0.4);
            this.enemy.y -= Math.sin(angle) * (speed * 0.4);
        }

        this.enemy.rotation = angle + Math.PI / 2;

        // Evasión Lateral Táctica al tener baja vida (estilo ChaseAI)
        if (this.enemy.hp < this.enemy.maxHp * 0.15 && now - (this.enemy.lastDash || 0) > 8000) {
            const dashAngle = angle + (Math.PI / 2 + (Math.random() - 0.5));
            this.enemy.x += Math.cos(dashAngle) * 250;
            this.enemy.y += Math.sin(dashAngle) * 250;
            this.enemy.lastDash = now;
        }
    }
};
