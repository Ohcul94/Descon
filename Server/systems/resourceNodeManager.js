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

function getMaterialScale(mat, fallback = 1.0) {
    if (!mat) return fallback;
    const isVal = (mat.iconScale !== undefined && mat.iconScale !== null && mat.iconScale !== '') ? Number(mat.iconScale) : null;
    const sVal = (mat.scale !== undefined && mat.scale !== null && mat.scale !== '') ? Number(mat.scale) : null;
    if (isVal !== null && isFinite(isVal) && isVal > 0) return isVal;
    if (sVal !== null && isFinite(sVal) && sVal > 0) return sVal;
    return fallback;
}

// Tiempo de recolección en MILISEGUNDOS (como el resto del sistema).
// Los valores < 100 se interpretan como segundos legacy y se convierten.
function getGatherTime(mat) {
    const t = Number(mat.gatherTime);
    if (!isFinite(t) || t <= 0) return 3000;
    return Math.round(t < 100 ? t * 1000 : t);
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

        const validNodeIds = new Set();

        mCfg.resources.forEach((cfg, idx) => {
            if (!cfg || !cfg.resourceId) return;
            const count = Math.max(1, parseInt(cfg.count) || 1);
            const intervalMs = Math.max(5000, parseInt(cfg.intervalMs) || 60000);
            const amount = Math.max(1, parseInt(cfg.amount) || 1);

            // Stacks: 'fixed' (por defecto x1) o 'variable' (rango aleatorio min - max)
            const stacksMode = cfg.stacksMode === 'variable' ? 'variable' : 'fixed';
            const stacks = Math.max(1, parseInt(cfg.stacks) || 1);
            const stacksMin = Math.max(1, parseInt(cfg.stacksMin) || 1);
            const stacksMax = Math.max(stacksMin, parseInt(cfg.stacksMax) || 1);

            // Asset 3D, icono y escala se obtienen exclusivamente del material (Crafteo → Materiales)
            const mat = getMaterial(state, cfg.resourceId);
            const resolvedAssetPath = (mat && mat.assetPath ? String(mat.assetPath).trim() : '');
            const resolvedIcon = (mat && mat.icon ? String(mat.icon).trim() : '');
            const resolvedScale = getMaterialScale(mat, 1.0);
            const resolvedCanFloat = (mat && mat.canFloat === true);

            for (let slot = 0; slot < count; slot++) {
                const nodeId = `res_${zone}_${idx}_${slot}`;
                validNodeIds.add(nodeId);

                const configuredTotal = stacksMode === 'variable'
                    ? (Math.floor(Math.random() * (stacksMax - stacksMin + 1)) + stacksMin)
                    : stacks;

                if (zoneNodes[nodeId]) {
                    const node = zoneNodes[nodeId];
                    node.resourceId = cfg.resourceId;
                    node.assetPath = resolvedAssetPath;
                    node.icon = resolvedIcon;
                    node.scale = resolvedScale;
                    node.canFloat = resolvedCanFloat;
                    node.amount = amount;
                    node.intervalMs = intervalMs;
                    if (cfg.rotY !== undefined && cfg.rotY !== null && cfg.rotY !== '') node.rotY = Number(cfg.rotY);
                    if (cfg.yOffset !== undefined && cfg.yOffset !== null && cfg.yOffset !== '') node.yOffset = Number(cfg.yOffset);

                    const oldStacks = node.stacks;
                    const oldStacksMode = node.stacksMode;
                    const oldStacksMin = node.stacksMin;
                    const oldStacksMax = node.stacksMax;

                    node.stacksMode = stacksMode;
                    node.stacks = stacks;
                    node.stacksMin = stacksMin;
                    node.stacksMax = stacksMax;

                    // Si cambiaron las opciones de stacks en la configuración o el total actual difiere:
                    const stacksChanged = (oldStacks !== stacks || oldStacksMode !== stacksMode || oldStacksMin !== stacksMin || oldStacksMax !== stacksMax);
                    if (stacksChanged || !node.totalStacks || node.totalStacks <= 0) {
                        node.totalStacks = configuredTotal;
                        if (node.active && !node.collecting) {
                            node.remainingStacks = configuredTotal;
                        } else if (node.remainingStacks > configuredTotal) {
                            node.remainingStacks = configuredTotal;
                        }
                    }
                    continue;
                }

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
                    assetPath: resolvedAssetPath,
                    icon: resolvedIcon,
                    scale: resolvedScale,
                    canFloat: resolvedCanFloat,
                    rotY: cfg.rotY !== undefined && cfg.rotY !== null && cfg.rotY !== '' ? Number(cfg.rotY) : 0,
                    yOffset: cfg.yOffset !== undefined && cfg.yOffset !== null && cfg.yOffset !== '' ? Number(cfg.yOffset) : 0,
                    stacksMode: stacksMode,
                    stacks: stacks,
                    stacksMin: stacksMin,
                    stacksMax: stacksMax,
                    totalStacks: configuredTotal,
                    remainingStacks: configuredTotal,
                    active: true,
                    respawnAt: 0,
                    collecting: null
                };
            }
        });

        // Limpiar nodos que ya no pertenezcan a la configuración activa
        Object.keys(zoneNodes).forEach(id => {
            if (!validNodeIds.has(id)) {
                delete zoneNodes[id];
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
        const mat = getMaterial(this.state, node.resourceId);
        const resolvedScale = getMaterialScale(mat, Number(node.scale) || 1.0);
        const resolvedAssetPath = (mat && mat.assetPath ? String(mat.assetPath).trim() : (node.assetPath || ''));
        const resolvedIcon = (mat && mat.icon ? String(mat.icon).trim() : (node.icon || ''));
        const resolvedCanFloat = (mat && mat.canFloat !== undefined ? !!mat.canFloat : !!node.canFloat);

        return {
            id: node.id,
            resourceId: node.resourceId,
            x: Math.round(node.x),
            y: Math.round(node.y),
            amount: node.amount,
            spawnMode: node.spawnMode,
            radius: node.radius,
            assetPath: resolvedAssetPath,
            icon: resolvedIcon,
            scale: resolvedScale,
            canFloat: resolvedCanFloat,
            rotY: node.rotY,
            yOffset: node.yOffset,
            active: node.active,
            respawnAt: node.respawnAt || 0,
            stacksMode: node.stacksMode || 'fixed',
            totalStacks: node.totalStacks || 1,
            remainingStacks: (node.remainingStacks !== undefined) ? node.remainingStacks : (node.totalStacks || 1)
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
                        const mCfg = getZoneCfg(state, node.zone);
                        const cfg = mCfg && mCfg.resources && mCfg.resources[node.cfgIdx];
                        if (cfg) {
                            const sMode = cfg.stacksMode === 'variable' ? 'variable' : 'fixed';
                            const sFixed = Math.max(1, parseInt(cfg.stacks) || 1);
                            const sMin = Math.max(1, parseInt(cfg.stacksMin) || 1);
                            const sMax = Math.max(sMin, parseInt(cfg.stacksMax) || 1);
                            node.stacksMode = sMode;
                            node.stacks = sFixed;
                            node.stacksMin = sMin;
                            node.stacksMax = sMax;
                            if (sMode === 'variable') {
                                node.totalStacks = Math.floor(Math.random() * (sMax - sMin + 1)) + sMin;
                            } else {
                                node.totalStacks = sFixed;
                            }
                        } else {
                            if (node.stacksMode === 'variable') {
                                const sMin = Math.max(1, parseInt(node.stacksMin) || 1);
                                const sMax = Math.max(sMin, parseInt(node.stacksMax) || 1);
                                node.totalStacks = Math.floor(Math.random() * (sMax - sMin + 1)) + sMin;
                            } else {
                                node.totalStacks = Math.max(1, parseInt(node.stacks) || 1);
                            }
                        }
                        node.remainingStacks = node.totalStacks;

                        // Si el modo de spawn no era fixed, reubicar posición en el área
                        if (node.spawnMode !== 'fixed' && cfg) {
                            const newPos = this.resolvePosition(cfg, node.zone);
                            node.x = newPos.x;
                            node.y = newPos.y;
                        }

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
                if (!node.active || (node.remainingStacks !== undefined && node.remainingStacks <= 0)) {
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

                if (!node.active || (node.remainingStacks !== undefined && node.remainingStacks <= 0)) {
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
                const gatherMs = getGatherTime(mat);
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
                    icon: mat.icon || '',
                    assetPath: mat.assetPath || ''
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

                // Descontar un stack por cada canal completado
                const curRemaining = (node.remainingStacks !== undefined) ? node.remainingStacks : 1;
                node.remainingStacks = Math.max(0, curRemaining - 1);
                node.collecting = null;

                const eByShipObj = {};
                if (user.gameData.equippedByShip instanceof Map) user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                else Object.assign(eByShipObj, user.gameData.equippedByShip);

                if (node.remainingStacks > 0) {
                    // El nodo sigue activo con stacks restantes
                    node.active = true;
                    this.io.to(`zone_${node.zone}`).emit('resourceNodeUpdated', {
                        id: node.id,
                        remainingStacks: node.remainingStacks,
                        totalStacks: node.totalStacks || 1
                    });

                    socket.emit('resourceCollected', {
                        nodeId: node.id,
                        resourceId: node.resourceId,
                        name: newItem.name,
                        amount: amount,
                        remainingStacks: node.remainingStacks,
                        totalStacks: node.totalStacks || 1
                    });

                    socket.emit('inventoryData', {
                        player: {
                            ...JSON.parse(JSON.stringify(user.gameData)),
                            equippedByShip: eByShipObj,
                            inventoryByCategory: getCategorizedInventory(user.gameData.inventory)
                        }
                    });

                    Logger.info('RESOURCE', `${p.user} recolectó stack (${node.remainingStacks}/${node.totalStacks} restantes) de ${amount}x ${newItem.name} del nodo ${node.id}.`);
                    socket.emit('gameNotification', {
                        msg: `Recolectado: ${amount}x ${newItem.name} (${node.remainingStacks}/${node.totalStacks} restantes)`,
                        type: 'success'
                    });
                } else {
                    // Se agotaron todos los stacks: activar cooldown de respawn
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
                        amount: amount,
                        remainingStacks: 0,
                        totalStacks: node.totalStacks || 1
                    });

                    socket.emit('inventoryData', {
                        player: {
                            ...JSON.parse(JSON.stringify(user.gameData)),
                            equippedByShip: eByShipObj,
                            inventoryByCategory: getCategorizedInventory(user.gameData.inventory)
                        }
                    });

                    Logger.info('RESOURCE', `${p.user} agotó el nodo ${node.id}: recolectó ${amount}x ${newItem.name}.`);
                    socket.emit('gameNotification', {
                        msg: `¡Nodo agotado! Recolectado: ${amount}x ${newItem.name}`,
                        type: 'success'
                    });
                }
            } catch (err) {
                console.error('[RESOURCE-COLLECT-ERR]', err);
            }
        });
    }
}

module.exports = ResourceNodeManager;
module.exports.getInteractRange = getInteractRange;
