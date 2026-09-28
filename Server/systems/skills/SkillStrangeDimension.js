const BaseSkill = require('./BaseSkill');

/**
 * SkillStrangeDimension.js
 * Habilidad de Defensa: Dimensión Extraña
 * 
 * Teleporta al jugador a una dimensión paralela tenebrosa con estética violeta.
 * Oculta aliados y elementos del entorno normal, permitiendo crear/summonear
 * enemigos dentro de esa dimensión paralela.
 * 
 * Configuraciones:
 * - targets: Enemigos válidos como objetivos de convocatoria
 * - cd: Cooldown en ms
 * - activation: Tiempo de activación en ms
 * - duration: Duración en la dimensión extraña (ms)
 * - range: Rango máximo del efecto
 */

class SkillStrangeDimension extends BaseSkill {
    constructor() {
        super("DIMENSIÓN EXTRAÑA");
    }

    /**
     * Ejecuta la mecánica de Dimensión Extraña.
     * @param {Object} p - Jugador que usa la habilidad
     * @param {Object} data - Datos enviados desde el cliente
     * @param {Object} context - Contexto del servidor (io, state, socket)
     */
    execute(p, data, { io, state, socket }) {
        const skillConfig = state.SERVER_CONFIG?.skillsData?.["DIMENSIÓN EXTRAÑA"] || {};
        
        // Leer configuraciones desde el skillData
        const cd = skillConfig.cd || 30000;
        const activationMs = skillConfig.activation || 1000;
        const duration = skillConfig.duration || 5000;
        const range = skillConfig.range || 500;
        const targets = skillConfig.targets || { enemies: true, bosses: true, players: false };
        const summonConfig = skillConfig.summonConfig || { canSummon: true, enemyTypes: [] };

        // Validar rango (seguridad del lado del servidor)
        const targetX = (data.posX !== undefined) ? data.posX : p.x;
        const targetY = (data.posY !== undefined) ? data.posY : p.y;
        const dist = Math.hypot(targetX - p.x, targetY - p.y);
        
        if (dist > range + 50) {
            console.log("[STRANGE_DIMENSION] Objetivo fuera de rango");
            return;
        }

        // Marcar al jugador como estar en dimensión extraña e invulnerable
        p.inStrangeDimension = true;
        p.isInvulnerable = true;
        p.strangeDimensionTimer = Date.now() + duration;
        p.strangeDimensionConfig = {
            duration: duration,
            range: range,
            targets: targets,
            summonConfig: summonConfig,
            activatedAt: Date.now()
        };

        // Obtener enemigos cercanos para posible convocatoria
        const nearbyEnemies = state.grid.getNearbyEntities(
            { x: p.x, y: p.y },
            range,
            'enemies'
        );

        // Filtrar enemigos válidos según targets configurados
        const validTargets = nearbyEnemies.filter(e => {
            if (e.type >= 101 || e.isBoss) {
                return targets.bosses !== false;
            }
            return targets.enemies !== false;
        });

        // Sincronizar posición del jugador
        p.x = targetX;
        p.y = targetY;
        p.justTeleported = true;
        p.authorizedTeleport = { x: p.x, y: p.y, zone: p.zone, timestamp: Date.now(), dimension: "extraña" };
        p.lastMoveTime = Date.now();

        // Emitir evento de red para sincronizar VFX en todos los clientes de la zona
        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', {
            id: socket.id,
            skillName: this.name,
            pos: { x: p.x, y: p.y },
            targetId: socket.id,
            powerValue: duration,
            dimensionData: {
                duration: duration,
                targets: targets,
                summonConfig: summonConfig,
                validTargets: validTargets.map(e => ({
                    id: e.id,
                    type: e.type,
                    x: e.x,
                    y: e.y
                }))
            }
        });

        // Informar al jugador su estado de dimensión
        socket.emit('playerStatSync', {
            id: socket.id,
            x: p.x,
            y: p.y,
            hp: p.hp,
            shield: p.shield,
            maxHp: p.maxHp,
            maxShield: p.shield,
            inStrangeDimension: true,
            strangeDimensionDuration: duration
        });

        // Programar salida de la dimensión
        setTimeout(() => {
            this._exitDimension(p, socket, io, state);
        }, duration + 1000); // 1s extra para transición visual

        // Broadcast de uso
        this.broadcastUsage(p, data, { io, socket });
    }

    /**
     * Salida de la dimensión extraña - restaura al jugador al mundo normal
     */
    _exitDimension(p, socket, io, state) {
        if (!p) return;
        
        p.inStrangeDimension = false;
        p.isInvulnerable = false;
        p.strangeDimensionTimer = null;
        p.strangeDimensionConfig = null;

        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', {
            id: socket.id,
            skillName: this.name + "_EXIT",
            pos: { x: p.x, y: p.y },
            targetId: socket.id
        });

        socket.emit('playerStatSync', {
            id: socket.id,
            x: p.x,
            y: p.y,
            inStrangeDimension: false
        });
    }

    /**
     * Convocar enemigos dentro de la dimensión extraña
     * @param {Object} p - Jugador
     * @param {Array} enemyTypes - Tipos de enemigos a convocar
     * @param {Object} context - Contexto del servidor
     */
    summonEnemies(p, enemyTypes, { io, state, socket }) {
        if (!p.inStrangeDimension) return;

        const skillConfig = state.SERVER_CONFIG?.skillsData?.["DIMENSIÓN EXTRAÑA"] || {};
        const summonConfig = skillConfig.summonConfig || {};
        const range = p.strangeDimensionConfig?.range || 500;

        const spawnedEnemies = [];
        
        for (const type of enemyTypes) {
            const enemyData = state.SERVER_CONFIG?.enemyModels?.[type];
            if (!enemyData) continue;

            // Spawnear enemigos en posición aleatoria cerca del jugador
            const angle = Math.random() * TAU;
            const dist = Math.random() * range * 0.5;
            const spawnX = p.x + Math.cos(angle) * dist;
            const spawnY = p.y + Math.sin(angle) * dist;

            const enemy = {
                type: type,
                x: spawnX,
                y: spawnY,
                zone: p.zone,
                isInStrangeDimension: true,
                spawnerId: socket.id,
                hp: enemyData.hp,
                shield: enemyData.shield || 0,
                speed: enemyData.speed,
                ...enemyData
            };

            state.enemies[enemy.id] = enemy;
            spawnedEnemies.push(enemy);

            // Emitir evento para que los clientes vean al enemigo en la dimensión
            io.to(`zone_${p.zone}`).emit('enemySpawned', {
                enemy: enemy,
                dimension: 'extraña'
            });
        }

        return spawnedEnemies;
    }
}

module.exports = SkillStrangeDimension;
