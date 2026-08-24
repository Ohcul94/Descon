const BaseSkill = require('./BaseSkill');

class BlinkSkill extends BaseSkill {
    constructor() {
        super("BLINK");
    }

    execute(p, data, { io, state, socket }) {
        const targetX = (data.posX !== undefined) ? data.posX : (data.pos ? data.pos.x : p.x);
        const targetY = (data.posY !== undefined) ? data.posY : (data.pos ? data.pos.y : p.y);

        const dx = targetX - p.x;
        const dy = targetY - p.y;
        const dist = Math.hypot(dx, dy);

        // Obtener el rango de la habilidad desde la configuración (por defecto 450)
        const skillConfig = state.SERVER_CONFIG?.skillsData?.[this.name] || { range: 450 };
        const maxRange = skillConfig.range || 450;

        let finalX = targetX;
        let finalY = targetY;

        // Tolerancia de 10% por jitter y latencia de red
        if (dist > maxRange * 1.1) {
            const ratio = maxRange / dist;
            finalX = p.x + dx * ratio;
            finalY = p.y + dy * ratio;
        }

        // v530.0: Clamp al borde de la nebulosa — Blink no puede atravesar el muro perimetral
        {
            const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
            const zStr = String(p.zone);
            let bounds = null;
            if (maps[zStr]) {
                const cfg = maps[zStr];
                const w = parseFloat(cfg.width);
                const h = parseFloat(cfg.height);
                if (!isNaN(w) && w > 0) bounds = { w: w, h: (!isNaN(h) && h > 0) ? h : w };
            }
            if (!bounds) {
                const gm = state.SERVER_CONFIG && state.SERVER_CONFIG.gameModes;
                if (gm && gm.extraction && Array.isArray(gm.extraction.maps) && gm.extraction.maps.map(n => String(n)).includes(zStr)) {
                    bounds = { w: parseFloat(gm.extraction.width) || 20000, h: parseFloat(gm.extraction.height) || 20000 };
                } else if (gm && gm.altar_defense && Array.isArray(gm.altar_defense.maps) && gm.altar_defense.maps.map(n => String(n)).includes(zStr)) {
                    bounds = { w: parseFloat(gm.altar_defense.width) || 10000, h: parseFloat(gm.altar_defense.height) || 10000 };
                } else if (typeof p.zone === 'string' && p.zone.startsWith('arena_')) {
                    bounds = { w: 10000, h: 10000 };
                } else if (typeof p.zone === 'string' && p.zone.startsWith('extract_')) {
                    bounds = { w: parseFloat(maps['10'] && maps['10'].width) || 20000, h: parseFloat(maps['10'] && maps['10'].height) || 20000 };
                }
            }
            if (bounds) {
                const margin = 25.0;
                finalX = Math.max(margin, Math.min(bounds.w - margin, finalX));
                finalY = Math.max(margin, Math.min(bounds.h - margin, finalY));
            }
        }

        p.x = finalX;
        p.y = finalY;
        p.justBlinked = true; // v266.700: Bypass anti-cheat
        
        // Sincronización inmediata para que los demás vean el salto
        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', { 
            id: socket.id, 
            skillName: this.name, 
            pos: { x: p.x, y: p.y },
            targetId: socket.id 
        });

        // Informar al propio jugador su posición final autoritativa en el servidor
        socket.emit('playerStatSync', {
            id: socket.id,
            x: p.x,
            y: p.y,
            hp: p.hp,
            shield: p.shield,
            maxHp: p.maxHp,
            maxShield: p.maxShield
        });
    }
}

module.exports = BlinkSkill;
