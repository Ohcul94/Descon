// GravityAI.js (Cerebro de Control de Masas v1.0)
const BaseAI = require('./BaseAI');

module.exports = class GravityAI extends BaseAI {
    constructor(enemy, config, state) {
        super(enemy, config, state);
        this.vortexCooldown = 6000;
        this.lastVortexTime = 0;
        this.vortexDuration = 2500;
        this.isVortexActive = false;
    }

    applyMovementLogic(target, dist, angle, now) {
        const speed = this.config.speed || 2.0;

        // Mantener una distancia media (no quiere chocar, quiere atraerte)
        if (dist > 400) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < 300) {
            this.enemy.x -= Math.cos(angle) * speed;
            this.enemy.y -= Math.sin(angle) * speed;
        }

        // Lógica del Vórtice
        if (!this.isVortexActive && now - this.lastVortexTime > this.vortexCooldown) {
            this.isVortexActive = true;
            this.lastVortexTime = now;
            // Avisar al cliente que empiece el efecto visual
            // (Asumimos que el servidor tiene acceso a 'io' vía update)
        }

        if (this.isVortexActive) {
            if (now - this.lastVortexTime < this.vortexDuration) {
                // SUCCIÓN: Mover al jugador hacia el enemigo
                // Esto lo hacemos modificando directamente al target (jugador)
                const pullForce = 3.5; 
                target.x -= Math.cos(angle) * pullForce;
                target.y -= Math.sin(angle) * pullForce;
            } else {
                this.isVortexActive = false;
            }
        }

        this.enemy.rotation = angle + Math.PI / 2;
    }
};
