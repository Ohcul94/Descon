const BaseSkill = require('./BaseSkill');

class StealthSkill extends BaseSkill {
    constructor() {
        super("STEALTH");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData["STEALTH"] : { duration: 8 };
        const duration = (config.duration || 8) * 1000;
        
        p.isInvisible = true;
        socket.emit('gameNotification', { msg: "¡SIGILO ACTIVADO!", type: "info" });
        
        setTimeout(() => {
            const currentPlayer = state.players[socket.id];
            if (currentPlayer) {
                currentPlayer.isInvisible = false;
                io.to(`zone_${currentPlayer.zone}`).emit('remoteStatSync', {
                    id: socket.id,
                    isInvisible: false
                });
            }
        }, duration);
        
        p.hasStealthTimer = true; 
        io.to(`zone_${p.zone}`).emit('remoteStatSync', { id: socket.id, isInvisible: true });
        
        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = StealthSkill;
