const Logger = require('../utils/logger');
const spawnValidator = require('../utils/spawnValidator');
const { getPlayerRAMAdapter } = require('../utils/ramAdapter');
const { addItemToInventory, getCategorizedInventory } = require('./inventoryHandlers');

/**
 * resourceNodeManager.js
 * Nodos de recursos recolectables (Cartografía → Recursos).
 * El servidor mantiene los nodos por zona, valida el canal de recolección
 * (tiempo + distancia) y otorga el material al completarse.
 */

function getInteractRange(state) {
    return state.SERVER_CONFIG?.lootConfig?.interactRange || 400;
}

function getMaterials(state) {
    return (state.SERVER_CONFIG && state.SERVER_CONFIG.shopItems && state.SERVER_CONFIG.shopItems.resources) || [];
}

function getMaterial(state, resourceId) {
    const id = String(resourceId);
    return getMaterials(state).find(m => String(m.id) === id) || null;
}

function getGatherTime(mat) {
    const t = Number(mat.gatherTime);
    return (isFinite(t) && t > 0) ? t : 3;
}

function getZoneCfg(state, zone) {
    const mc = state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig;
    if (!mc) return null;
    return mc[zone] !== undefined ? mc[zone] : (mc[String(zone)] !== undefined ? mc[String(zone)] : null);
}

// ===== Utilidades de polígono (misma lógica que AIManager) =====
function pointInPolygon(poly, px, py) {
    let inside = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        const xi = poly[i].x, yi = poly[i].y;
        const xj = poly[j].x, yj = poly[j].y;
        const intersect = ((yi > py) !== (yj > py)) &&
            (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
        if (intersect) inside = !inside;
    }
    return inside;
}

function randomPointInPolygon(poly) {
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const p of poly) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
    }
    for (let i = 0; i < 40; i++) {
        const rx = minX + Math.random() * (maxX - minX);
        const ry = minY + Math.random() * (maxY - minY);
        if (pointInPolygon(poly, rx, ry)) return { x: rx, y: ry };
    }
    let sx = 0, sy = 0;
    for (const p of poly) { sx += p.x; sy += p.y; }
    return { x: sx / poly.length, y: sy / poly.length };
}

class ResourceNodeManager {
    constructor(io, state) {
        this.io = io;
        this.state = state;
        if (!this.state.resourceNodes) this.state.resourceNodes = {};
    }

    // ======================================================================
    // POSICIONES (misma lógica que los spawns de enemigos)
    // ======================================================================
    resolvePosition(cfg, zone) {
        const state = this.state;
        let posX = null;
        let posY = null;

        if (cfg.spawnMode === 'fixed' && cfg.x !== undefined && cfg.y !== undefined) {
            if (spawnValidator.isPointBlocked(cfg.x, cfg.y, zone, state)) {
                const fallback = spawnValidator.findValidSpawnPosition(cfg.x, cfg.y, 120, zone, state, { maxAttempts: 20 });
                if (fallback) { posX = fallback.x; posY = fallback.y; }
                else { posX = cfg.x; posY = cfg.y; }
            } else {
                posX = cfg.x;
                posY = cfg.y;
            }
        } else if (cfg.spawnMode === 'polygon' && Array.isArray(cfg.polygon) && cfg.polygon.length >= 3) {
            let chosen = null;
            let lastCand = null;
            for (let a = 0; a < 12 && !chosen; a++) {
                const cand = randomPointInPolygon(cfg.polygon);
                lastCand = cand;
                if (cand && !spawnValidator.isPointBlocked(cand.x, cand.y, zone, state)) chosen = cand;
            }
            if (chosen) { posX = chosen.x; posY = chosen.y; }
            else if (lastCand) { posX = lastCand.x; posY = lastCand.y; }
        } else {
            // 'random' con radio, o 'random' global (radius 0 / sin radio) dentro de los límites del mapa
            const hasCenter = cfg.x !== undefined && cfg.y !== undefined;
            const radius = Number(cfg.radius) || 0;
            if (hasCenter && radius > 0) {
                const valid = spawnValidator.findValidSpawnPosition(cfg.x, cfg.y, radius, zone, state, { maxAttempts: 35 });
                if (valid) {
                    posX = valid.x;
                    posY = valid.y;
                } else {
                    const angle = Math.random() * Math.PI * 2;
                    const r = Math.random() * radius;
                    posX = cfg.x + Math.cos(angle) * r;
                    posY = cfg.y + Math.sin(angle) * r;
                }
            } else {
                const mCfg = getZoneCfg(state, zone) || {};
                const minX = (mCfg.minX !== undefined) ? Number(mCfg.minX) : 0;
                const minY = (mCfg.minY !== undefined) ? Number(mCfg.minY) : 0;
                const mapWidth = mCfg.width ? Number(mCfg.width) : 4000;
                const mapHeight = mCfg.height ? Number(mCfg.height) : 4000;
                let found = false;
                for (let k = 0; k < 40 && !found; k++) {
                    const rx = minX + Math.random() * (mapWidth - 600) + 300;
                    const ry = minY + Math.random() * (mapHeight - 600) + 300;
                    if (!spawnValidator.isPointBlocked(rx, ry, zone, state)) { posX = rx; posY = ry; found = true; }
                }
                if (!found) {
                    posX = hasCenter ? cfg.x : (minX + mapWidth / 2);
                    posY = hasCenter ? cfg.y : (minY + mapHeight / 2);
                }
            }
        }

        return { x: Math.round(posX || 0), y: Math.round(posY || 0) };
    }

    // ======================================================================
    // CREACIÓN / INSTANCIA DE NODOS
    // ======================================================================
    ensureZoneNodes(zone) {
        const state = this.state;
        const mCfg = getZoneCfg(state, zone);
        if (!mCfg || !Array.isArray(mCfg.resources) || mCfg.resources.length === 0) {
            if (state.resourceNodes[zone] === undefined) state.resourceNodes[zone] = {};
            return state.resourceNodes[zone];
        }

        if (!state.resourceNodes[zone]) state.resourceNodes[zone] = {};
        const zoneNodes = state.resourceNodes[zone];

        mCfg.resources.forEach((cfg, idx) => {
            if (!cfg || !cfg.resourceId) return;
            const count = Math.max(1, parseInt(cfg.count) || 1);
            const intervalMs = Math.max(5000, parseInt(cfg.intervalMs) || 60000);
            const amount = Math.max(1, parseInt(cfg.amount) || 1);

            for (let slot = 0; slot < count; slot++) {
                const nodeId = `res_${zone}_${idx}_${slot}`;
                if (zoneNodes[nodeId]) continue;

                const pos = this.resolvePosition(cfg, zone);
                zoneNodes[nodeId] = {
                    id: nodeId,
                    zone: Number(zone),
                    cfgIdx: idx,
                    slot: slot,
                    resourceId: cfg.resourceId,
                    x: pos.x,
                    y: pos.y,
                    amount: amount,
                    intervalMs: intervalMs,
                    spawnMode: cfg.spawnMode || 'fixed',
                    radius: Number(cfg.radius) || 0,
                    polygon: Array.isArray(cfg.polygon) && cfg.polygon.length >= 3 ? cfg.polygon.map(p => ({ x: p.x, y: p.y })) : null,
                    assetPath: cfg.assetPath || null,
                    icon: cfg.icon || null,
                    scale: cfg.scale !== undefined && cfg.scale !== null && cfg.scale !== '' ? Number(cfg.scale) : 1,
                    rotY: cfg.rotY !== undefined && cfg.rotY !== null && cfg.rotY !== '' ? Number(cfg.rotY) : 0,
                    yOffset: cfg.yOffset !== undefined && cfg.yOffset !== null && cfg.yOffset !== '' ? Number(cfg.yOffset) : 0,
                    active: true,
                    respawnAt: 0,
                    collecting: null
                };
            }
        });

        return zoneNodes;
    }

    getNode(zone, nodeId) {
        const zoneNodes = this.state.resourceNodes ? this.state.resourceNodes[zone] : null;
        if (!zoneNodes) return null;
        return zoneNodes[nodeId] || null;
    }

    serialize(node) {
        return {
            id: node.id,
            resourceId: node.resourceId,
            x: Math.round(node.x),
            y: Math.round(node.y),
            amount: node.amount,
            spawnMode: node.spawnMode,
            radius: node.radius,
            assetPath: node.assetPath,
            icon: node.icon,
            scale: node.scale,
            rotY: node.rotY,
            yOffset: node.yOffset,
            active: node.active,
            respawnAt: node.respawnAt || 0
        };
    }

    sendZoneNodes(socket, zone) {
        try {
            const zoneNodes = this.ensureZoneNodes(zone);
            const list = Object.keys(zoneNodes).map(id => this.serialize(zoneNodes[id]));
            socket.emit('resourceNodes', { zone: Number(zone), nodes: list });
        } catch (err) {
            console.error('[RESOURCE-NODES-SEND-ERR]', err);
        }
    }

    // ======================================================================
    // TICK (1s): respawn + liberación de canales colgados
    // ======================================================================
    updateLoop() {
        try {
            const state = this.state;
            const now = Date.now();
            if (!state.resourceNodes) return;

            Object.keys(state.resourceNodes).forEach(zone => {
                const zoneNodes = state.resourceNodes[zone];
                const hasPlayers = state.playersByZone[zone] && Object.keys(state.playersByZone[zone]).length > 0;

                // Zona sin jugadores: limpiar canales activos (los nodos quedan en memoria)
                if (!hasPlayers) {
                    Object.keys(zoneNodes).forEach(id => { if (zoneNodes[id].collecting) zoneNodes[id].collecting = null; });
                    return;
                }

                Object.keys(zoneNodes).forEach(id => {
                    const node = zoneNodes[id];

                    // Canal colgado (desconexión / cambio de zona / alejamiento)
                    if (node.collecting) {
                        const cp = state.players[node.collecting.socketId];
                        const stale = !cp
                            || String(cp.zone) !== String(node.zone)
                            || Math.hypot(cp.x - node.x, cp.y - node.y) > getInteractRange(state)
                            || (now - node.collecting.startedAt) > 30000;
                        if (stale) {
                            const owner = node.collecting.socketId;
                            node.collecting = null;
                            const s = this.io.sockets.sockets.get(owner);
                            if (s) s.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'interrupted' });
                        }
                    }

                    // Respawn
                    if (!node.active && node.respawnAt && now >= node.respawnAt) {
                        node.active = true;
                        node.respawnAt = 0;
                        node.collecting = null;
                        this.io.to(`zone_${node.zone}`).emit('resourceNodeSpawned', this.serialize(node));
                    }
                });
            });
        } catch (err) {
            console.error('[RESOURCE-NODE-TICK-ERR]', err);
        }
    }

    // ======================================================================
    // HANDLERS DE SOCKET
    // ======================================================================
    registerHandlers(socket, io) {
        const state = this.state;

        // INICIAR CANAL DE RECOLECCIÓN
        socket.on('startCollectResource', (data) => {
            try {
                const p = state.players[socket.id];
                if (!p || !data || !data.nodeId) return;
                const node = this.getNode(p.zone, data.nodeId);
                if (!node) return;
                if (!node.active) {
                    return socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'inactive' });
                }

                const mat = getMaterial(state, node.resourceId);
                if (!mat || mat.recolectable !== true) {
                    return socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'not_recolectable' });
                }

                const dist = Math.hypot(p.x - node.x, p.y - node.y);
                if (dist > getInteractRange(state)) {
                    return socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'too_far' });
                }

                if (node.collecting && node.collecting.socketId !== socket.id) {
                    return socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'busy' });
                }
                if (node.collecting && node.collecting.socketId === socket.id) {
                    // Reintento idempotente: reenviar confirmación
                    return socket.emit('resourceCollectStarted', { nodeId: node.id, gatherTime: getGatherTime(mat), amount: node.amount });
                }

                node.collecting = { socketId: socket.id, startedAt: Date.now(), x: p.x, y: p.y };
                socket.emit('resourceCollectStarted', { nodeId: node.id, gatherTime: getGatherTime(mat), amount: node.amount });
            } catch (err) {
                console.error('[RESOURCE-START-ERR]', err);
            }
        });

        // CANCELAR CANAL
        socket.on('cancelCollectResource', (data) => {
            try {
                const p = state.players[socket.id];
                if (!p || !data || !data.nodeId) return;
                const node = this.getNode(p.zone, data.nodeId);
                if (!node || !node.collecting || node.collecting.socketId !== socket.id) return;
                node.collecting = null;
                socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'cancelled' });
            } catch (err) {
                console.error('[RESOURCE-CANCEL-ERR]', err);
            }
        });

        // COMPLETAR RECOLECCIÓN
        socket.on('collectResource', async (data) => {
            try {
                if (!socket.dbUser || !state.players[socket.id]) return;
                const p = state.players[socket.id];
                if (!data || !data.nodeId) return;

                const node = this.getNode(p.zone, data.nodeId);
                if (!node) return;

                if (!node.active) {
                    return socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'inactive' });
                }

                const mat = getMaterial(state, node.resourceId);
                if (!mat || mat.recolectable !== true) {
                    return socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'not_recolectable' });
                }

                if (!node.collecting || node.collecting.socketId !== socket.id) {
                    return socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'no_channel' });
                }

                // El canal debe haber durado el tiempo configurado (con 200ms de tolerancia)
                const gatherMs = getGatherTime(mat) * 1000;
                const elapsed = Date.now() - node.collecting.startedAt;
                if (elapsed < gatherMs - 200) {
                    return socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'too_fast' });
                }

                // Segunda validación de distancia (el jugador debe seguir junto al nodo)
                const dist = Math.hypot(p.x - node.x, p.y - node.y);
                if (dist > getInteractRange(state)) {
                    node.collecting = null;
                    return socket.emit('resourceCollectCancelled', { nodeId: node.id, reason: 'too_far' });
                }

                const user = getPlayerRAMAdapter(p);
                if (!user) return;

                const newItem = {
                    id: mat.id,
                    instanceId: "",
                    name: mat.name || `Material ${mat.id}`,
                    type: (mat.type || 'resource').toLowerCase(),
                    base: mat.base || 0,
                    color: mat.color || '#ffffff',
                    rarity: mat.rarity || 0,
                    icon: mat.icon || ''
                };

                const amount = Math.max(1, parseInt(node.amount) || 1);
                const remaining = addItemToInventory(user, newItem, state.SERVER_CONFIG, amount);
                if (remaining > 0) {
                    return socket.emit('gameNotification', { msg: 'INVENTARIO LLENO: Desbloquea más slots para recolectar.', type: 'error' });
                }

                user.markModified('gameData.inventory');
                user.markModified('gameData');
                await user.save();
                socket.dbUser = user;
                p.inventory = JSON.parse(JSON.stringify(user.gameData.inventory));

                // Agotar el nodo y programar reaparición
                node.collecting = null;
                node.active = false;
                node.respawnAt = Date.now() + node.intervalMs;

                this.io.to(`zone_${node.zone}`).emit('resourceNodeDepleted', {
                    id: node.id,
                    respawnAt: node.respawnAt
                });

                socket.emit('resourceCollected', {
                    nodeId: node.id,
                    resourceId: node.resourceId,
                    name: newItem.name,
                    amount: amount
                });

                const eByShipObj = {};
                if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                else Object.assign(eByShipObj, user.gameData.equippedByShip);

                socket.emit('inventoryData', {
                    player: {
                        ...JSON.parse(JSON.stringify(user.gameData)),
                        equippedByShip: eByShipObj,
                        inventoryByCategory: getCategorizedInventory(user.gameData.inventory)
                    }
                });

                Logger.info('RESOURCE', `${p.user} recolectó ${amount}x ${newItem.name} del nodo ${node.id}.`);
                socket.emit('gameNotification', { msg: `Recolectado: ${amount}x ${newItem.name}`, type: 'success' });
            } catch (err) {
                console.error('[RESOURCE-COLLECT-ERR]', err);
            }
        });
    }
}

module.exports = ResourceNodeManager;
module.exports.getInteractRange = getInteractRange;
