const BaseSkill = require('./BaseSkill');

class BlinkSkill extends BaseSkill {
    constructor() {
        super("BLINK");
    }

    execute(p, data, { io, state, socket }) {
        const targetX = (data.posX !== undefined) ? data.posX : (data.pos ? data.pos.x : p.x);
        const targetY = (data.posY !== undefined) ? data.posY : (data.pos ? data.pos.y : p.y);

        const dx = targetX - p.x;
        const dy = targetY - p.y;
        const dist = Math.hypot(dx, dy);

        // Obtener el rango de la habilidad desde la configuración (por defecto 450)
        const skillConfig = state.SERVER_CONFIG?.skillsData?.[this.name] || { range: 450 };
        const maxRange = skillConfig.range || 450;

        let finalX = targetX;
        let finalY = targetY;

        // Tolerancia de 10% por jitter y latencia de red
        if (dist > maxRange * 1.1) {
            const ratio = maxRange / dist;
            finalX = p.x + dx * ratio;
            finalY = p.y + dy * ratio;
        }

        p.x = finalX;
        p.y = finalY;
        p.justBlinked = true; // v266.700: Bypass anti-cheat
        
        // Sincronización inmediata para que los demás vean el salto
        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', { 
            id: socket.id, 
            skillName: this.name, 
            pos: { x: p.x, y: p.y },
            targetId: socket.id 
        });

        // Informar al propio jugador su posición final autoritativa en el servidor
        socket.emit('playerStatSync', {
            id: socket.id,
            x: p.x,
            y: p.y,
            hp: p.hp,
            shield: p.shield,
            maxHp: p.maxHp,
            maxShield: p.maxShield,
            spheres: p.spheres || []
        });
    }
}

module.exports = BlinkSkill;
