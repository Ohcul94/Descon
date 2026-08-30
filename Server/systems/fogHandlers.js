const User = require('../models/User');
const Logger = require('../utils/logger');

// v800.0: SISTEMA DE NIEBLA DE GUERRA PERSISTENTE (God of War - niebla gris degradada)
// Grilla 64x64 = 4096 celdas por mapa. Cada celda = y*GRID_RES + x
// La niebla se guarda por zona (exploredMaps: Map<zoneId, Number[]>)
// Anticheat: solo se aceptan celdas dentro del rango de visión + margen, y rate-limited.

const GRID_RES = 64;
const MAX_CELLS_PER_UPDATE = 200; // Anti-spam: máximo 200 celdas nuevas por paquete
const MAX_UPDATES_PER_MIN = 30;   // 30 updates/min = cada 2s aprox
const VISION_MARGIN = 1.5;        // Permitir 50% extra por lag/interpolación

// Cache de límites de mapa para validación anticheat (similar a movementHandler)
const getMapBounds = (zone, state) => {
    const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
    const zStr = String(zone);
    if (maps[zStr]) {
        const cfg = maps[zStr];
        const w = parseFloat(cfg.width);
        const h = parseFloat(cfg.height);
        if (!isNaN(w) && w > 0) {
            return { w: w, h: (!isNaN(h) && h > 0) ? h : w };
        }
    }
    const gm = state.SERVER_CONFIG && state.SERVER_CONFIG.gameModes;
    if (gm) {
        if (gm.extraction && Array.isArray(gm.extraction.maps) && gm.extraction.maps.map(n => String(n)).includes(zStr)) {
            return { w: parseFloat(gm.extraction.width) || 20000, h: parseFloat(gm.extraction.height) || 20000 };
        }
        if (gm.altar_defense && Array.isArray(gm.altar_defense.maps) && gm.altar_defense.maps.map(n => String(n)).includes(zStr)) {
            return { w: parseFloat(gm.altar_defense.width) || 10000, h: parseFloat(gm.altar_defense.height) || 10000 };
        }
        if (gm.arenas) {
            if (gm.arenas.mapConfigs && gm.arenas.mapConfigs[zStr]) {
                const ac = gm.arenas.mapConfigs[zStr];
                return { w: parseFloat(ac.width) || 10000, h: parseFloat(ac.height) || 10000 };
            }
            if (Array.isArray(gm.arenas.maps) && gm.arenas.maps.map(n => String(n)).includes(zStr)) {
                return { w: 10000, h: 10000 };
            }
        }
    }
    if (typeof zone === 'string') {
        if (zone.startsWith('arena_')) return { w: 10000, h: 10000 };
        if (zone.startsWith('extract_')) return { w: parseFloat(maps['10'] && maps['10'].width) || 20000, h: parseFloat(maps['10'] && maps['10'].height) || 20000 };
        if (zone.startsWith('dungeon')) return { w: 4000, h: 4000 };
    }
    return { w: 4000, h: 4000 };
};

// Convierte índice de celda a coordenadas centradas en mundo
const cellToWorldPos = (cellIdx, bounds) => {
    const x = cellIdx % GRID_RES;
    const y = Math.floor(cellIdx / GRID_RES);
    const cellW = bounds.w / GRID_RES;
    const cellH = bounds.h / GRID_RES;
    return {
        x: (x + 0.5) * cellW,
        y: (y + 0.5) * cellH
    };
};

// Obtiene visión del jugador (dinámica por nave)
const getPlayerVision = (p, state) => {
    let vision = 1300;
    if (state.SERVER_CONFIG && state.SERVER_CONFIG.shipModels) {
        const ship = state.SERVER_CONFIG.shipModels.find(s => s.id === p.currentShipId);
        if (ship && ship.vision !== undefined) vision = Number(ship.vision);
    }
    // Bonus por talentos/skills podría ir aquí
    return vision;
};

function registerFogHandlers(socket, io, state) {
    const { players } = state;

    // Cliente pide datos de niebla al entrar a una zona
    socket.on('requestFog', async (data) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];
        const zone = String(data && data.zone ? data.zone : p.zone);
        // Lazy init si no existe
        if (!p.exploredMaps) p.exploredMaps = {};
        // Si es primera vez, puede venir vacío; asegurar tipo
        if (typeof p.exploredMaps === 'object' && p.exploredMaps instanceof Map) {
            // Mongoose Map -> convertir a objeto plano para serializar
            const arr = p.exploredMaps.get(zone) || [];
            socket.emit('fogData', { zone, cells: arr, gridRes: GRID_RES });
            return;
        }
        const cells = p.exploredMaps[zone] || [];
        // Limitar tamaño de respuesta (máx 4096)
        socket.emit('fogData', { zone, cells: cells.slice(0, 4096), gridRes: GRID_RES });
        Logger.debug('FOG', `Enviando niebla zona ${zone} a ${p.user}: ${cells.length} celdas`);
    });

    // Cliente envía nuevas celdas exploradas
    socket.on('updateFog', async (data) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];
        if (!data || !data.zone || !Array.isArray(data.cells)) return;

        const zone = String(data.zone);
        let cells = data.cells;

        // Rate limit
        const now = Date.now();
        if (!socket._fogRate) socket._fogRate = { count: 0, windowStart: now };
        if (now - socket._fogRate.windowStart > 60000) {
            socket._fogRate.count = 0;
            socket._fogRate.windowStart = now;
        }
        socket._fogRate.count++;
        if (socket._fogRate.count > MAX_UPDATES_PER_MIN) {
            Logger.warn('FOG-SECURITY', `Rate limit niebla excedido por ${p.user} (${socket._fogRate.count}/min)`);
            return;
        }

        // Validar tamaño
        if (cells.length === 0) return;
        if (cells.length > MAX_CELLS_PER_UPDATE) {
            Logger.warn('FOG-SECURITY', `Paquete niebla demasiado grande de ${p.user}: ${cells.length} > ${MAX_CELLS_PER_UPDATE}, truncando`);
            cells = cells.slice(0, MAX_CELLS_PER_UPDATE);
        }

        // Validar que las celdas sean números válidos dentro de grilla
        const validCells = [];
        for (let c of cells) {
            const ci = Number(c);
            if (!Number.isInteger(ci) || ci < 0 || ci >= GRID_RES * GRID_RES) continue;
            validCells.push(ci);
        }
        if (validCells.length === 0) return;

        // Inicializar estructuras si no existen
        if (!p.exploredMaps) p.exploredMaps = {};
        if (!p.exploredAt) p.exploredAt = {};

        // Soporte para Map de Mongoose vs objeto plano RAM
        let currentArr;
        let isMongooseMap = false;
        if (p.exploredMaps instanceof Map) {
            isMongooseMap = true;
            currentArr = p.exploredMaps.get(zone) || [];
        } else {
            currentArr = p.exploredMaps[zone] || [];
        }

        const existingSet = new Set(currentArr);
        const bounds = getMapBounds(zone, state);
        const vision = getPlayerVision(p, state);
        const maxDist = vision * VISION_MARGIN;
        const maxDistSq = maxDist * maxDist;

        let added = 0;
        let rejected = 0;

        for (let ci of validCells) {
            if (existingSet.has(ci)) continue; // Ya explorada, no contar

            // Anticheat: verificar que la celda esté cerca del jugador (dentro de visión + margen)
            // Esto evita que el cliente envíe celdas arbitrarias y revele todo el mapa
            const cellPos = cellToWorldPos(ci, bounds);
            const dx = cellPos.x - p.x;
            const dy = cellPos.y - p.y;
            const distSq = dx * dx + dy * dy;

            // Permitir también si está cerca de aliados? No, solo visión propia
            // Para no ser demasiado estricto con lag, permitimos celdas hasta maxDist
            if (distSq > maxDistSq) {
                rejected++;
                // Loguear solo ocasionalmente para no spamear
                if (rejected <= 3) {
                    Logger.debug('FOG-SECURITY', `Celda ${ci} rechazada para ${p.user}: dist ${Math.sqrt(distSq).toFixed(0)} > ${maxDist.toFixed(0)} (vision ${vision})`);
                }
                continue;
            }

            existingSet.add(ci);
            added++;
        }

        if (rejected > 5) {
            Logger.warn('FOG-SECURITY', `${p.user} envió ${rejected} celdas fuera de rango (posible cheat o desfase) zona ${zone}`);
        }

        if (added === 0) return;

        const newArr = [...existingSet];

        // Actualizar RAM
        if (isMongooseMap) {
            p.exploredMaps.set(zone, newArr);
        } else {
            p.exploredMaps[zone] = newArr;
        }
        if (p.exploredAt instanceof Map) {
            p.exploredAt.set(zone, new Date());
        } else {
            p.exploredAt[zone] = new Date();
        }

        // Persistir de forma asíncrona (no bloqueante)
        // Usamos updateOne con $set para no reescribir todo el documento
        const updateKey = `gameData.exploredMaps.${zone}`;
        const updateAtKey = `gameData.exploredAt.${zone}`;
        User.updateOne(
            { _id: p.id },
            { $set: { [updateKey]: newArr, [updateAtKey]: new Date() } }
        ).catch(err => {
            Logger.error('FOG-DB', `Error guardando niebla ${p.user} zona ${zone}: ${err.message}`);
        });

        if (added > 0) {
            Logger.debug('FOG', `${p.user} exploró +${added} celdas zona ${zone} (total ${newArr.length}/4096)`);
        }

        // Confirmar al cliente (opcional, para sync)
        // socket.emit('fogAck', { zone, added, total: newArr.length });
    });

    // Reset de niebla (admin o comando de debug)
    socket.on('resetFog', async (data) => {
        if (!players[socket.id] || !socket.dbUser) return;
        const p = players[socket.id];
        const zone = data && data.zone ? String(data.zone) : null;
        if (!zone) {
            // Reset todo
            if (!p.isAdmin) return; // Solo admin puede resetear todo
            p.exploredMaps = {};
            p.exploredAt = {};
            await User.updateOne({ _id: p.id }, { $set: { "gameData.exploredMaps": {}, "gameData.exploredAt": {} } });
            socket.emit('fogData', { zone: "all", cells: [], gridRes: GRID_RES });
            Logger.info('FOG', `Niebla reseteada completa para ${p.user} por admin`);
        } else {
            // Reset solo una zona
            if (p.exploredMaps instanceof Map) {
                p.exploredMaps.delete(zone);
                if (p.exploredAt instanceof Map) p.exploredAt.delete(zone);
            } else {
                delete p.exploredMaps[zone];
                delete p.exploredAt[zone];
            }
            await User.updateOne({ _id: p.id }, { $unset: { [`gameData.exploredMaps.${zone}`]: 1, [`gameData.exploredAt.${zone}`]: 1 } });
            socket.emit('fogData', { zone, cells: [], gridRes: GRID_RES });
            Logger.info('FOG', `Niebla zona ${zone} reseteada para ${p.user}`);
        }
    });
}

module.exports = { registerFogHandlers, GRID_RES };
