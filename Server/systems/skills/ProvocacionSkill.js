// Server/systems/skills/ProvocacionSkill.js
const BaseSkill = require('./BaseSkill');

class ProvocacionSkill extends BaseSkill {
    /**
     * Constructor estructurado para enfoque Data-Driven (Dashboard)
     * @param {Object} skillData - Configuración directa proveniente del AdminDash / JSON
     */
    constructor(skillData = {}) {
        // Pasamos el nombre sanitizado a la clase padre
        super("PROVOCACION");

        // Inicializamos las propiedades de forma limpia con los datos del Dashboard
        // Si no existen, el operador OR asigna un Fallback seguro (un "por defecto")
        this.type = skillData.type || "Ataque";
        this.cd = skillData.cd || 2000;
        this.range = skillData.range || 450;
        this.radius = skillData.radius || 220;
        this.taunt_duration = skillData.taunt_duration || 4000;
    }

    /**
     * Ejecuta la lógica autoritativa de la habilidad en el Servidor
     */
    execute(p, data, { io, state, socket }) {
        // Calcular posición del taunt limitada por el rango máximo configurado
        let targetX = p.x;
        let targetY = p.y;

        // Normalización de las coordenadas enviadas por el cliente
        const targetPosX = (data && typeof data.posX === 'number') ? data.posX : (data && typeof data.x === 'number' ? data.x : null);
        const targetPosY = (data && typeof data.posY === 'number') ? data.posY : (data && typeof data.y === 'number' ? data.y : null);

        if (targetPosX !== null && targetPosY !== null) {
            const dx = targetPosX - p.x;
            const dy = targetPosY - p.y;
            const dist = Math.hypot(dx, dy);
            const maxRange = this.range; // Usamos la propiedad limpia del objeto

            if (dist > maxRange) {
                const angle = Math.atan2(dy, dx);
                targetX = p.x + Math.cos(angle) * maxRange;
                targetY = p.y + Math.sin(angle) * maxRange;
            } else {
                targetX = targetPosX;
                targetY = targetPosY;
            }
        }

        const radius = this.radius; // Usamos la propiedad limpia del objeto
        const tauntDuration = this.taunt_duration; // Usamos la propiedad limpia del objeto
        const affectedEnemies = [];

        // Obtener enemigos cercanos de forma eficiente a través de la grilla espacial (Anti-Lag)
        if (state.grid) {
            const { enemies: nearbyEnemies } = state.grid.getNearbyEntities(targetX, targetY, p.zone);
            nearbyEnemies.forEach(e => {
                if (e.zone === p.zone && e.hp > 0) {
                    const d = Math.hypot(e.x - targetX, e.y - targetY);
                    if (d <= radius) {
                        // Aplicación del estado de provocación autoritativo
                        e.forcedTarget = socket.id;
                        e.tauntEndTime = Date.now() + tauntDuration;
                        affectedEnemies.push(e.id);
                    }
                }
            });
        }

        // Emitir evento de red optimizado para sincronizar el VFX en los clientes de la zona
        io.to(`zone_${p.zone}`).emit('tauntEvent', {
            casterId: socket.id,
            x: targetX,
            y: targetY,
            radius: radius,
            duration: tauntDuration,
            affectedEnemies: affectedEnemies
        });

        // Registrar el uso global del skill
        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = ProvocacionSkill;