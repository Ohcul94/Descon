const BaseSkill = require('./BaseSkill');

class FrostTrailSkill extends BaseSkill {
    constructor() {
        super("FROST-TRAIL");
    }

    execute(p, data, { io, state, socket }) {
        const config = (state.SERVER_CONFIG && state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData[this.name] : {};

        // Duracion: el config la guarda en segundos (6). Si el admin pone ms (>=100), se respeta como ms.
        const durationRaw = Number(config.duration);
        const duration = (Number.isFinite(durationRaw) && durationRaw > 0)
            ? (durationRaw >= 100 ? durationRaw : durationRaw * 1000)
            : 6000;
        const skillEndTime = Date.now() + duration;

        // Todo configurable desde el AdminDash: radio del camino, slow y a quienes frena
        const radius = Math.max(30, Math.min(Number(config.radius) || 60, 200));
        const slowAmount = Number.isFinite(Number(config.slow_amount)) ? Number(config.slow_amount) : 0.5;
        const targetFilters = config.targetFilters || { allies: false, enemies: true, players: true, bosses: false };
        const spacing = Math.max(22, Math.min(radius * 0.4, 55));

        socket.emit('gameNotification', { msg: "¡ESTELA DE HIELO ACTIVADA!", type: "info" });

        const spawnPatch = (x, y, dirX, dirY, zone, speed) => {
            const areaId = `frost_${state.nextAreaId++}`;
            state.activeAreas[areaId] = {
                id: areaId,
                x,
                y,
                radius,
                type: 'ICE',
                ownerId: socket.id,
                slowAmount,
                targetFilters,
                dirX,
                dirY,
                skillName: 'FROST-TRAIL',
                speed,
                endTime: skillEndTime,
                zone
            };
            io.to(`zone_${zone}`).emit('spawnArea', state.activeAreas[areaId]);
        };

        // Primer tramo bajo los pies al activar
        let lastX = p.x;
        let lastY = p.y;
        let lastT = Date.now();
        spawnPatch(lastX, lastY, 0, 0, p.zone, 0);

        const trailInterval = setInterval(() => {
            const currentPlayer = state.players[socket.id];
            if (!currentPlayer || Date.now() >= skillEndTime) {
                clearInterval(trailInterval);
                return;
            }

            const nowT = Date.now();
            const dx = currentPlayer.x - lastX;
            const dy = currentPlayer.y - lastY;
            const dist = Math.hypot(dx, dy);
            if (dist < spacing) return;

            // Evitar pintar una linea larguisima tras teleports/blinks
            if (dist > 500) {
                lastX = currentPlayer.x;
                lastY = currentPlayer.y;
                lastT = nowT;
                return;
            }

            // Velocidad real (px/s) para el color del tramo
            const tickSpeed = dist / Math.max((nowT - lastT) / 1000.0, 0.001);
            lastT = nowT;

            // Interpolar tramos a lo largo del recorrido para que el camino sea continuo
            const inv = 1 / dist;
            const dirX = dx * inv;
            const dirY = dy * inv;
            const steps = Math.min(Math.floor(dist / spacing), 10);
            for (let i = 1; i <= steps; i++) {
                const d = i * spacing;
                spawnPatch(lastX + dirX * d, lastY + dirY * d, dirX, dirY, currentPlayer.zone, tickSpeed);
            }
            lastX += dirX * steps * spacing;
            lastY += dirY * steps * spacing;
        }, 80);

        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = FrostTrailSkill;
