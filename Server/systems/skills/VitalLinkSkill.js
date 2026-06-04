const BaseSkill = require('./BaseSkill');

class VitalLinkSkill extends BaseSkill {
    constructor() {
        super("VÍNCULO VITAL");
    }

    execute(p, data, { io, state, socket }) {
        let config = { cd: 15000, amount: 250, duration: 10000, range: 350, breakRange: 500, tickInterval: 1000, targetFilters: { allies: true, enemies: false, bosses: false, players: true } };
        if (state.SERVER_CONFIG && state.SERVER_CONFIG.skillsData && state.SERVER_CONFIG.skillsData[this.name]) {
            config = state.SERVER_CONFIG.skillsData[this.name];
        }

        const duration = config.duration || 10000;
        const breakRange = config.breakRange || 500;
        const castRange = config.range || 350;
        const amount = config.amount || 250;
        const tickInterval = config.tickInterval || 1000;
        const filters = config.targetFilters || { allies: true, enemies: false, bosses: false, players: true };

        // Validar Target
        const targetId = data.targetId;
        if (!targetId) {
            socket.emit('gameNotification', { msg: "Se requiere un objetivo válido para vincular el lazo.", type: "error" });
            return false;
        }

        // BLOQUEO EXPLICITO: No se puede auto-lanzar a uno mismo
        if (targetId === socket.id || targetId === p.socketId) {
            socket.emit('gameNotification', { msg: "No puedes vincular el lazo vital a ti mismo.", type: "error" });
            return false;
        }

        // Buscar Target en jugadores y NPCs enemigos
        let target = state.players[targetId];
        let isEnemyNPC = false;
        if (!target && state.enemies && state.enemies[targetId]) {
            target = state.enemies[targetId];
            isEnemyNPC = true;
        }

        if (!target || target.isDead) {
            socket.emit('gameNotification', { msg: "El objetivo seleccionado no está disponible o ya fue destruido.", type: "error" });
            return false;
        }

        // Validar zona
        const targetZone = isEnemyNPC ? target.zoneId : target.zone;
        if (targetZone !== p.zone) {
            socket.emit('gameNotification', { msg: "El objetivo seleccionado está en otra zona.", type: "error" });
            return false;
        }

        // Determinar si es aliado o enemigo
        let is_ally = false;
        if (!isEnemyNPC) {
            if (target.socketId === p.socketId) {
                is_ally = true;
            } else {
                if (p.clanId && target.clanId && String(p.clanId) === String(target.clanId)) is_ally = true;
                const pUid = p.id ? p.id.toString() : null;
                const tUid = target.id ? target.id.toString() : null;
                if (pUid && tUid && state.playerParty[pUid] && state.playerParty[pUid] === state.playerParty[tUid]) is_ally = true;
            }
        }

        // Validar dinámicamente según filtros de la habilidad (allies / enemies / bosses / players)
        let isValidTargetType = false;
        if (isEnemyNPC) {
            const isBoss = target.type === 4 || target.type === 10 || target.type === 11;
            if (isBoss && filters.bosses) isValidTargetType = true;
            else if (!isBoss && filters.enemies) isValidTargetType = true;
        } else {
            if (is_ally) {
                if (filters.allies) isValidTargetType = true;
            } else {
                if (filters.enemies || filters.players) isValidTargetType = true;
            }
        }

        if (!isValidTargetType) {
            socket.emit('gameNotification', { msg: "El objetivo seleccionado no es un aliado o tipo de nave válido para este lazo.", type: "error" });
            return false;
        }

        // Validar distancia de casteo
        const dist = Math.hypot(target.x - p.x, target.y - p.y);
        if (dist > castRange) {
            socket.emit('gameNotification', { msg: "El objetivo seleccionado está fuera del rango de casteo.", type: "error" });
            return false;
        }

        // Spawnear el area del Lazo Vital Curativo
        const areaId = `link_${state.nextAreaId++}`;
        state.activeAreas[areaId] = {
            id: areaId,
            type: 'VITAL_LINK',
            ownerId: socket.id,
            targetId: targetId,
            radius: breakRange,
            amount: amount,
            tickInterval: tickInterval,
            endTime: Date.now() + duration,
            lastTickTime: Date.now(),
            zone: p.zone
        };

        io.to(`zone_${p.zone}`).emit('spawnArea', state.activeAreas[areaId]);
        
        socket.emit('gameNotification', { msg: "¡VÍNCULO VITAL ESTABLECIDO CON ÉXITO!", type: "info" });
        return true;
    }
}

module.exports = VitalLinkSkill;
