const BaseSkill = require('./BaseSkill');

class BlinkSkill extends BaseSkill {
    constructor() {
        super("BLINK");
    }

    execute(p, data, { io, state, socket }) {
        const targetX = (data.posX !== undefined) ? data.posX : (data.pos ? data.pos.x : p.x);
        const targetY = (data.posY !== undefined) ? data.posY : (data.pos ? data.pos.y : p.y);

        p.x = targetX;
        p.y = targetY;
        p.justBlinked = true; // v266.700: Bypass anti-cheat
        
        // Sincronización inmediata para que los demás vean el salto
        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', { 
            id: socket.id, 
            skillName: this.name, 
            pos: { x: p.x, y: p.y },
            targetId: socket.id 
        });
    }
}

module.exports = BlinkSkill;
