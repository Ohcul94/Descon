const BaseSkill = require('./BaseSkill');

class HealBeaconSkill extends BaseSkill {
    constructor() {
        super("BALIZA DE CURACION");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG.skillsData && state.SERVER_CONFIG.skillsData[this.name]) 
            ? state.SERVER_CONFIG.skillsData[this.name] 
            : { duration: 8000, pulse_interval: 1500, heal_amount: 250, range: 500, radius: 200 };
        
        const areaId = `area_${state.nextAreaId++}`;
        
        // Calcular posición limitada por el rango de la habilidad
        let targetX = p.x;
        let targetY = p.y;
        
        const targetPosX = (data && typeof data.posX === 'number') ? data.posX : (data && typeof data.x === 'number' ? data.x : null);
        const targetPosY = (data && typeof data.posY === 'number') ? data.posY : (data && typeof data.y === 'number' ? data.y : null);
        
        if (targetPosX !== null && targetPosY !== null) {
            const dx = targetPosX - p.x;
            const dy = targetPosY - p.y;
            const dist = Math.hypot(dx, dy);
            const maxRange = config.range || 500;
            
            if (dist > maxRange) {
                const angle = Math.atan2(dy, dx);
                targetX = p.x + Math.cos(angle) * maxRange;
                targetY = p.y + Math.sin(angle) * maxRange;
            } else {
                targetX = targetPosX;
                targetY = targetPosY;
            }
        }

        let durationMs = config.duration || 8000;
        // Si el valor se configuró erróneamente en segundos (ej. 8 en lugar de 8000)
        if (durationMs < 1000) {
            durationMs *= 1000;
        }

        // Crear la baliza activa en el estado del servidor
        state.activeAreas[areaId] = {
            id: areaId,
            x: targetX,
            y: targetY,
            radius: config.radius || 200,
            pulse_interval: config.pulse_interval || 1500,
            heal_amount: config.heal_amount || 250,
            type: 'HEAL_BEACON',
            ownerId: socket.id,
            endTime: Date.now() + durationMs,
            zone: p.zone,
            lastPulseTime: 0 // Se inicializa para disparar el primer pulso inmediatamente
        };
        
        io.to(`zone_${p.zone}`).emit('spawnArea', state.activeAreas[areaId]);
        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = HealBeaconSkill;
