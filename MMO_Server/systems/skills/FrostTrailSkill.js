const BaseSkill = require('./BaseSkill');

class FrostTrailSkill extends BaseSkill {
    constructor() {
        super("FROST-TRAIL");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG && state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData[this.name] : { duration: 6, radius: 120, cd: 12 };
        const duration = (config.duration || 6) * 1000;
        const skillEndTime = Date.now() + duration; 
        
        socket.emit('gameNotification', { msg: "¡ESTELA DE HIELO ACTIVADA!", type: "info" });
        
        let lastX = -9999; 
        let lastY = -9999;

        const trailInterval = setInterval(() => {
            const currentPlayer = state.players[socket.id];
            if (!currentPlayer || Date.now() >= skillEndTime) {
                clearInterval(trailInterval);
                return;
            }
            
            const dist = Math.hypot(currentPlayer.x - lastX, currentPlayer.y - lastY);
            if (dist > 25) {
                const areaId = `frost_${state.nextAreaId++}`;
                state.activeAreas[areaId] = {
                    id: areaId,
                    x: currentPlayer.x,
                    y: currentPlayer.y,
                    radius: 35, 
                    type: 'ICE',
                    ownerId: socket.id,
                    slowAmount: config.slow_amount || 0.6,
                    endTime: skillEndTime, 
                    zone: currentPlayer.zone
                };
                
                io.to(`zone_${currentPlayer.zone}`).emit('spawnArea', state.activeAreas[areaId]);
                lastX = currentPlayer.x;
                lastY = currentPlayer.y;
            }
        }, 100);

        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = FrostTrailSkill;
