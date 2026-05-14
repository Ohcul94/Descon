const BaseSkill = require('./BaseSkill');

class SmokeBombSkill extends BaseSkill {
    constructor() {
        super("SMOKE-BOMB");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData[this.name] : { duration: 6, radius: 180 };
        const areaId = `area_${state.nextAreaId++}`;
        
        state.activeAreas[areaId] = {
            id: areaId,
            x: p.x,
            y: p.y,
            radius: config.radius || 180,
            type: 'SMOKE',
            ownerId: socket.id,
            endTime: Date.now() + (config.duration * 1000),
            zone: p.zone
        };
        
        io.to(`zone_${p.zone}`).emit('spawnArea', state.activeAreas[areaId]);
        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = SmokeBombSkill;
