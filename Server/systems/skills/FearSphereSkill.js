const BaseSkill = require('./BaseSkill');

class FearSphereSkill extends BaseSkill {
    constructor() {
        super("ESFERA DE TERROR");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG.skillsData && state.SERVER_CONFIG.skillsData[this.name])
            ? state.SERVER_CONFIG.skillsData[this.name]
            : { cd: 15000, amount: 500, range: 600, radius: 150, duration: 3000, speed: 800 };

        // Al ser apuntable (Directional), data contiene posX, posY y el ángulo de apuntado
        const angle = (data.angle !== undefined) ? data.angle : p.rotation;

        this.broadcastUsage(p, { ...data, angle }, { io, socket }, config.amount || 500);
    }

    broadcastUsage(p, data, { io, socket }, powerValue = 0) {
        const payload = {
            id: socket.id,
            skillName: this.name,
            targetId: data.targetId || socket.id,
            powerValue: powerValue,
            angle: data.angle !== undefined ? data.angle : p.rotation,
            posX: data.posX || p.x,
            posY: data.posY || p.y
        };

        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', payload);
    }
}

module.exports = FearSphereSkill;
