const BaseSkill = require('./BaseSkill');
const Logger = require('../../utils/logger');

class ResurreccionSkill extends BaseSkill {
    constructor() {
        super("RESURRECCIÓN");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG.skillsData && state.SERVER_CONFIG.skillsData[this.name]) 
            ? state.SERVER_CONFIG.skillsData[this.name] 
            : { cd: 45000, revive_hp_pct: 50, revive_shield_pct: 20, range: 500, radius: 200 };

        // Obtener posición del centro del círculo
        const targetPosX = (data && typeof data.posX === 'number') ? data.posX : (data && typeof data.x === 'number' ? data.x : null);
        const targetPosY = (data && typeof data.posY === 'number') ? data.posY : (data && typeof data.y === 'number' ? data.y : null);

        if (targetPosX === null || targetPosY === null) {
            Logger.warn('SKILL', `Intento de Resurrección sin posición por: [${p.user}]`);
            return;
        }

        // Limitar la posición del casteo al rango máximo de la habilidad
        let targetX = p.x;
        let targetY = p.y;
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

        const areaRadius = config.radius || 200;
        const reviveHpPct = config.revive_hp_pct || 50;
        const reviveShieldPct = config.revive_shield_pct || 20;
        const filters = config.targetFilters || { allies: true, enemies: false, bosses: false, players: true, clan: true };

        // 1. Emitir la animación de resurrección en el área para todos en la zona (SpawnArea visual temporal)
        const areaId = `area_res_${state.nextAreaId++}`;
        const visualArea = {
            id: areaId,
            x: targetX,
            y: targetY,
            radius: areaRadius,
            type: 'HEAL_ZONE', // Reutilizamos el efecto verde de curación en el cliente
            ownerId: socket.id,
            endTime: Date.now() + 1500, // Duración corta para el destello visual de resurrección
            zone: p.zone,
            targetFilters: filters
        };
        io.to(`zone_${p.zone}`).emit('spawnArea', visualArea);

        // Programar la remoción visual
        setTimeout(() => {
            io.to(`zone_${p.zone}`).emit('removeArea', { id: areaId });
        }, 1500);

        // 2. Buscar jugadores muertos en el radio
        let revivedCount = 0;
        Object.keys(state.players).forEach(pId => {
            const targetPlayer = state.players[pId];
            if (!targetPlayer || targetPlayer.zone !== p.zone || pId === socket.id) return;

            // Verificar si está muerto
            if (!targetPlayer.isDead && targetPlayer.hp > 0) return;

            // Medir distancia al centro del círculo
            const distanceToCenter = Math.hypot(targetPlayer.x - targetX, targetPlayer.y - targetY);
            if (distanceToCenter > areaRadius) return;

            // Validar filtros (Aliados, Clan, etc.)
            let isValidTarget = false;
            const sameClan = (p.clanId && targetPlayer.clanId && String(p.clanId) === String(targetPlayer.clanId));
            const isAlly = sameClan || (!p.pvpEnabled && !targetPlayer.pvpEnabled);
            const isEnemy = !sameClan && (p.pvpEnabled || targetPlayer.pvpEnabled);

            if (sameClan && filters.clan) isValidTarget = true;
            else if (isAlly && filters.allies) isValidTarget = true;
            else if (isEnemy && (filters.enemies || filters.players)) isValidTarget = true;
            else if (!isAlly && !isEnemy && filters.players) isValidTarget = true;

            if (!isValidTarget) return;

            // ¡REVIVIR AL JUGADOR!
            targetPlayer.isDead = false;
            targetPlayer.hp = targetPlayer.maxHp * (reviveHpPct / 100.0);
            targetPlayer.shield = targetPlayer.maxShield * (reviveShieldPct / 100.0);
            targetPlayer.lastCombatTime = Date.now();

            // Sincronizar estado al resucitado y a la zona
            const targetSocket = io.sockets.sockets.get(pId);
            if (targetSocket) {
                // Notificar resurrección al cliente resucitado
                targetSocket.emit('gameNotification', { msg: `¡Has sido resucitado por ${p.user.toUpperCase()}!`, type: 'success' });
            }

            io.to(`zone_${p.zone}`).emit('playerStatSync', {
                id: pId,
                x: targetPlayer.x,
                y: targetPlayer.y,
                hp: Math.ceil(targetPlayer.hp),
                shield: Math.ceil(targetPlayer.shield),
                maxHp: targetPlayer.maxHp,
                maxShield: targetPlayer.maxShield,
                isDead: false,
                spheres: targetPlayer.spheres || []
            });

            revivedCount++;
            Logger.info('SKILL', `[RESURRECCIÓN] ${p.user} resucitó a ${targetPlayer.user} en zona ${p.zone}`);
        });

        if (revivedCount > 0) {
            socket.emit('gameNotification', { msg: `¡Resucitaste a ${revivedCount} aliado(s)!`, type: 'success' });
        } else {
            socket.emit('gameNotification', { msg: "No se encontraron aliados caídos en el área.", type: 'warning' });
        }

        // Notificar el casteo de la habilidad
        this.broadcastUsage(p, data, { io, socket }, revivedCount);
    }
}

module.exports = ResurreccionSkill;
