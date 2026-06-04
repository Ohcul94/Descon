const BaseSkill = require('./BaseSkill');

class AlphaRegenSkill extends BaseSkill {
    constructor() {
        super("REGENERACIÓN ALFA");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG && state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData[this.name] : { cd: 20000, amount: 1500, duration: 60000, radius: 100, range: 0 };
        
        const duration = config.duration || 60000;
        const radius = config.radius || 100;
        const amount = config.amount || 1500;
        const range = config.range || 0;
        const targetFilters = config.targetFilters || { allies: true, bosses: false, enemies: false, players: true };

        // Posición de destino autoritativa (con soporte para rango máximo)
        let targetX = p.x;
        let targetY = p.y;

        if (data.posX !== undefined && data.posY !== undefined) {
            const dx = data.posX - p.x;
            const dy = data.posY - p.y;
            const dist = Math.hypot(dx, dy);
            
            if (range > 0 && dist > range) {
                const angle = Math.atan2(dy, dx);
                targetX = p.x + Math.cos(angle) * range;
                targetY = p.y + Math.sin(angle) * range;
            } else {
                targetX = data.posX;
                targetY = data.posY;
            }
        }

        const areaId = `heal_${state.nextAreaId++}`;
        state.activeAreas[areaId] = {
            id: areaId,
            x: targetX,
            y: targetY,
            radius: radius,
            type: 'HEAL_ZONE',
            ownerId: socket.id,
            amount: amount,
            filters: targetFilters,
            endTime: Date.now() + duration,
            zone: p.zone
        };

        io.to(`zone_${p.zone}`).emit('spawnArea', state.activeAreas[areaId]);
        
        socket.emit('gameNotification', { msg: "¡PROYECTIL CURATIVO LANZADO HACIA EL OBJETIVO!", type: "info" });

    }
}

module.exports = AlphaRegenSkill;
