const BaseSkill = require('./BaseSkill');

class ProvocacionSkill extends BaseSkill {
    constructor() {
        super("PROVOCACION");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG.skillsData && state.SERVER_CONFIG.skillsData[this.name])
            ? state.SERVER_CONFIG.skillsData[this.name]
            : { cd: 15000, range: 450, radius: 220, taunt_duration: 4000 };

        // Calcular posición del taunt limitada por el rango
        let targetX = p.x;
        let targetY = p.y;

        const targetPosX = (data && typeof data.posX === 'number') ? data.posX : (data && typeof data.x === 'number' ? data.x : null);
        const targetPosY = (data && typeof data.posY === 'number') ? data.posY : (data && typeof data.y === 'number' ? data.y : null);

        if (targetPosX !== null && targetPosY !== null) {
            const dx = targetPosX - p.x;
            const dy = targetPosY - p.y;
            const dist = Math.hypot(dx, dy);
            const maxRange = config.range || 450;

            if (dist > maxRange) {
                const angle = Math.atan2(dy, dx);
                targetX = p.x + Math.cos(angle) * maxRange;
                targetY = p.y + Math.sin(angle) * maxRange;
            } else {
                targetX = targetPosX;
                targetY = targetPosY;
            }
        }

        const radius = config.radius || 220;
        const tauntDuration = config.taunt_duration || 4000;
        const affectedEnemies = [];

        // Obtener enemigos cercanos a través de la grilla espacial
        if (state.grid) {
            const { enemies: nearbyEnemies } = state.grid.getNearbyEntities(targetX, targetY);
            nearbyEnemies.forEach(e => {
                if (e.zone === p.zone && e.hp > 0) {
                    const d = Math.hypot(e.x - targetX, e.y - targetY);
                    if (d <= radius) {
                        e.forcedTarget = socket.id;
                        e.tauntEndTime = Date.now() + tauntDuration;
                        affectedEnemies.push(e.id);
                    }
                }
            });
        }

        // Emitir evento de red para sincronizar el VFX en el cliente
        io.to(`zone_${p.zone}`).emit('tauntEvent', {
            casterId: socket.id,
            x: targetX,
            y: targetY,
            radius: radius,
            duration: tauntDuration,
            affectedEnemies: affectedEnemies
        });

        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = ProvocacionSkill;
