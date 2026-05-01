// ChargerAI.js (Cerebro de Embestida v1.0)
const BaseAI = require('./BaseAI');

module.exports = class ChargerAI extends BaseAI {
    constructor(enemy, config) {
        super(enemy, config);
        this.isCharging = false;
        this.chargeStartTime = 0;
        this.chargeCooldown = 4000 + Math.random() * 2000;
        this.lastChargeTime = 0;
        this.chargeDirection = 0;
    }

    applyMovementLogic(target, dist, angle, now) {
        let speed = this.config.speed || 3.5;

        // Si ya está embistiendo
        if (this.isCharging) {
            const chargeDuration = 600; // ms de duración del dash
            if (now - this.chargeStartTime < chargeDuration) {
                // Durante la embestida, velocidad x4
                this.enemy.x += Math.cos(this.chargeDirection) * (speed * 4);
                this.enemy.y += Math.sin(this.chargeDirection) * (speed * 4);
                return; 
            } else {
                this.isCharging = false;
                this.lastChargeTime = now;
            }
        }

        // Decidir si empezar una embestida
        // Condición: Cerca del jugador (dist < 500) y cooldown listo
        if (!this.isCharging && dist < 500 && now - this.lastChargeTime > this.chargeCooldown) {
            this.isCharging = true;
            this.chargeStartTime = now;
            this.chargeDirection = angle; // Fija la dirección al inicio del dash
            return;
        }

        // Movimiento normal de persecución
        if (dist > 30) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        }
        
        this.enemy.rotation = angle + Math.PI / 2;
    }
};
