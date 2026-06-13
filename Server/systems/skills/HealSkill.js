const BaseSkill = require('./BaseSkill');

class HealSkill extends BaseSkill {
    constructor(name) {
        super(name);
    }

    execute(p, data, { io, state, socket }) {
        const res = this.getTarget(p, data, state, socket);
        if (!res) return;
        const { target } = res;
        
        const powerValue = data.powerValue || 0;
        let actual_val = 0;

        if (this.name === "ESCUDO CELULAR" || this.name === "FORTALEZA-X") {
            const ms = target.maxShield || 2000;
            const oldS = target.shield || 0;
            target.shield = Math.min(oldS + powerValue, ms);
            actual_val = target.shield - oldS;
        } else {
            // HP: AUTO-REPARACIÓN, NANO-REGENERACIÓN
            const mh = target.maxHp || 3000;
            const oldH = target.hp || 0;
            target.hp = Math.min(oldH + powerValue, mh);
            actual_val = target.hp - oldH;
        }

        // v266.360: Stacks y temporizador de curación para el HUD de estados
        target.healEndTime = Date.now() + 5000;
        target.healStacks = Math.min((target.healStacks || 0) + 1, 5);

        if (target.socketId) {
            io.to(`zone_${target.zone}`).emit('playerStatSync', {
                id: target.socketId,
                hp: Math.ceil(target.hp),
                shield: Math.ceil(target.shield),
                isDead: target.hp <= 0
            });
        }
        
        this.broadcastUsage(p, data, { io, socket }, actual_val);
    }
}

module.exports = HealSkill;
