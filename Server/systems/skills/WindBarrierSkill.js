const BaseSkill = require('./BaseSkill');

class WindBarrierSkill extends BaseSkill {
    constructor() {
        super("BARRERA DE VIENTO");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG.skillsData && state.SERVER_CONFIG.skillsData[this.name]) 
            ? state.SERVER_CONFIG.skillsData[this.name] 
            : { duration: 6, width: 150, range: 400, targetFilters: { allies: false, enemies: true, bosses: false, players: false } };
        
        const areaId = `area_${state.nextAreaId++}`;
        
        // Calcular posición de casteo limitada por el rango de la habilidad
        let targetX = p.x;
        let targetY = p.y;
        
        const targetPosX = (data && typeof data.posX === 'number') ? data.posX : (data && typeof data.x === 'number' ? data.x : null);
        const targetPosY = (data && typeof data.posY === 'number') ? data.posY : (data && typeof data.y === 'number' ? data.y : null);
        
        if (targetPosX !== null && targetPosY !== null) {
            const dx = targetPosX - p.x;
            const dy = targetPosY - p.y;
            const dist = Math.hypot(dx, dy);
            const maxRange = config.range || 400;
            
            if (dist > maxRange) {
                const angle = Math.atan2(dy, dx);
                targetX = p.x + Math.cos(angle) * maxRange;
                targetY = p.y + Math.sin(angle) * maxRange;
            } else {
                targetX = targetPosX;
                targetY = targetPosY;
            }
        }

        const dx = targetX - p.x;
        const dy = targetY - p.y;
        const angle = Math.atan2(dy, dx);

        let durationMs = config.duration || 6;
        if (durationMs < 1000) {
            durationMs *= 1000;
        }

        // Crear la barrera de viento activa en el estado del servidor
        state.activeAreas[areaId] = {
            id: areaId,
            x: targetX,
            y: targetY,
            radius: config.width || 150, // Usado para que el cliente dibuje las partículas y el anillo
            width: config.width || 150,
            angle: angle,
            type: 'WIND_BARRIER',
            ownerId: socket.id,
            endTime: Date.now() + durationMs,
            zone: p.zone,
            targetFilters: config.targetFilters || { allies: false, enemies: true, bosses: false, players: false }
        };
        
        io.to(`zone_${p.zone}`).emit('spawnArea', state.activeAreas[areaId]);
        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = WindBarrierSkill;
