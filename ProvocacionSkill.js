// e:/Descon/MMO_Server/skills/ProvocacionSkill.js
const BaseSkill = require('./BaseSkill');
const Logger = require('../utils/logger');

class ProvocacionSkill extends BaseSkill {
    constructor(skillData) {
        super(skillData);
        this.type = skillData.type || 'Defensa';
        this.cd = skillData.cd || 15000; // Cooldown en ms
        this.range = skillData.range || 450; // Rango máximo para lanzar la habilidad
        this.radius = skillData.radius || 220; // Radio del área de efecto
        this.taunt_duration = skillData.taunt_duration || 4000; // Duración de la provocación en ms
    }

    execute(caster, targetPosition, state, io) {
        if (!caster || !state || !io) {
            Logger.error('SKILL', `ProvocacionSkill.execute: Parámetros inválidos. caster: ${!!caster}, state: ${!!state}, io: ${!!io}`);
            return false;
        }

        const casterId = caster.id;
        const casterZone = caster.zone;
        const now = Date.now();

        // Calcular posición final limitada por el rango
        const dx = targetPosition.x - caster.x;
        const dy = targetPosition.y - caster.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        
        let skill_x = targetPosition.x;
        let skill_y = targetPosition.y;
        
        if (dist > this.range) {
            const angle = Math.atan2(dy, dx);
            skill_x = caster.x + Math.cos(angle) * this.range;
            skill_y = caster.y + Math.sin(angle) * this.range;
        }

        const affectedEnemies = [];
        const tauntEndTime = now + this.taunt_duration;

        // Buscar enemigos en el área (Uso de state.enemies si no hay grid activo)
        const enemies = state.enemies || {};
        for (const id in enemies) {
            const enemy = enemies[id];
            if (enemy.zone === casterZone) {
                const distToSkill = Math.sqrt(Math.pow(enemy.x - skill_x, 2) + Math.pow(enemy.y - skill_y, 2));
                if (distToSkill <= this.radius) {
                    // Aplicar lógica de Provocación
                    enemy.forcedTarget = casterId;
                    enemy.tauntEndTime = tauntEndTime;
                    affectedEnemies.push(id);
                }
            }
        }

        // Emitir evento de red para el VFX en los clientes
        io.to(`zone_${casterZone}`).emit('tauntEvent', { 
            casterId, x: skill_x, y: skill_y, 
            radius: this.radius, duration: this.taunt_duration, 
            affectedEnemies 
        });

        return true;
    }
}

module.exports = ProvocacionSkill;
