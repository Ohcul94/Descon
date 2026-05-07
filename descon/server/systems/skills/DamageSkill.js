const BaseSkill = require('./BaseSkill');

class DamageSkill extends BaseSkill {
    constructor(name) {
        super(name);
    }

    execute(p, data, { io, state, socket }) {
        const res = this.getTarget(p, data, state, socket);
        if (!res) return;
        const { target } = res;
        
        const powerValue = data.powerValue || 0;
        let actual_val = 0;

        if (this.name === "PLASMA BLAST") {
            if (target !== p) {
                const oldH = target.hp || 0;
                target.hp -= powerValue;
                if (target.hp < 0) target.hp = 0;
                actual_val = oldH - target.hp;
            }
        }

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

module.exports = DamageSkill;
