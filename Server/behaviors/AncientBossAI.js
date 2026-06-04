// AncientBossAI.js - Redirigido a BaseAI para usar mecánicas del Admin Dash
const BaseAI = require('./BaseAI');

module.exports = class AncientBossAI extends BaseAI {
    constructor(enemy, config, state) {
        super(enemy, config, state);
        this.noAggroStartTime = 0;
    }

    update(grid, players, now, io) {
        // Ejecutar comportamiento estándar de BaseAI (movimiento, disparo, defensas, etc.)
        super.update(grid, players, now, io);

        // Reset de HP y Escudo tras el tiempo configurado fuera de combate (regenDelayMs)
        let target = this.getNearestPlayer(grid, players);
        if (!target) {
            if (this.noAggroStartTime === 0) {
                this.noAggroStartTime = now;
            }
            const delayMs = (this.config && this.config.regenDelayMs !== undefined) ? Number(this.config.regenDelayMs) : 30000;
            if (now - this.noAggroStartTime > delayMs) {
                if (this.enemy.hp < this.enemy.maxHp || this.enemy.shield < this.enemy.maxShield) {
                    console.log(`[BOSS-AI] Reset de HP y Escudo para Ancient Titán (${delayMs / 1000}s sin aggro)`);
                    this.enemy.hp = this.enemy.maxHp;
                    this.enemy.shield = this.enemy.maxShield;
                }
                this.noAggroStartTime = 0;
            }
        } else {
            this.noAggroStartTime = 0;
        }
    }
};
