/**
 * spawnValidator.js
 * Validador de posiciones de spawn que evita estructuras/colisiones.
 * Espejo exacto de la lógica de colisión 2D de BaseMap.gd
 *   descon/scripts/systems/BaseMap.gd:1818-1928  (colliders manuales)
 *   y descon/scripts/systems/BaseMap.gd:2838-2868 (CSGBox elipse)
 *
 * NO toca colliders: solo muestrea puntos y rechaza los que caen dentro
 * de rects/elipses/polígonos generados desde mapsConfig.objects.
 */
const Logger = require('./logger');

const CORRECTION_Z = 1.41421356; // BaseMap.gd:54
const DEFAULT_ENEMY_RADIUS = 42; // radio del círculo del enemigo + margen
const EXTRA_MARGIN = 18; // margen extra para que no spawnee pegado a la pared

// Cache por zoneId: { version, obstacles: [...] }
const _cache = new Map();

// Tipos que SÍ bloquean. door/portal/spawn son Area2D (layer 0) no bloquean movimiento.
const BLOCKED_TYPES = new Set(['wall', 'tower', 'altar', 'chest', 'vault', 'nexus']);
const IGNORED_TYPES = new Set(['door', 'portal', 'spawn', 'decor', 'extract']);

// --- Geometría ---
function _degToRad(d) { return d * Math.PI / 180; }

function _pointInRotatedRect(px, py, cx, cy, w, h, rotRad, marginX, marginY) {
    const dx = px - cx;
    const dy = py - cy;
    const cos = Math.cos(-rotRad);
    const sin = Math.sin(-rotRad);
    const rx = dx * cos - dy * sin;
    const ry = dx * sin + dy * cos;
    const hx = (w * 0.5) + marginX;
    const hy = (h * 0.5) + marginY;
    return Math.abs(rx) <= hx && Math.abs(ry) <= hy;
}

function _pointInRotatedEllipse(px, py, cx, cy, rx, ry, rotRad, margin) {
    const dx = px - cx;
    const dy = py - cy;
    const cos = Math.cos(-rotRad);
    const sin = Math.sin(-rotRad);
    const rxLocal = dx * cos - dy * sin;
    const ryLocal = dx * sin + dy * cos;
    const erx = rx + margin;
    const ery = ry + margin;
    if (erx <= 0 || ery <= 0) return false;
    return (rxLocal * rxLocal) / (erx * erx) + (ryLocal * ryLocal) / (ery * ery) <= 1.0;
}

// Ray-casting point in polygon (polygon = array de {x,y} relativos al centro, ya rotados si aplica)
// polyWorld = puntos en coordenadas mundo
function _pointInPolygon(px, py, polyWorld, margin = 0) {
    // Si hay margen, expandimos aproximando: si está dentro con margen=0 ya está bloqueado,
    // para margen >0 hacemos check de distancia a aristas (simple: si punto a < margin de algún segmento => bloqueado)
    let inside = false;
    for (let i = 0, j = polyWorld.length - 1; i < polyWorld.length; j = i++) {
        const xi = polyWorld[i].x, yi = polyWorld[i].y;
        const xj = polyWorld[j].x, yj = polyWorld[j].y;
        const intersect = ((yi > py) !== (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi + 1e-9) + xi);
        if (intersect) inside = !inside;
    }
    if (inside) return true;
    if (margin > 0) {
        // distancia mínima a arista < margin => también bloqueado (pegado a pared)
        let minDistSq = Infinity;
        for (let i = 0, j = polyWorld.length - 1; i < polyWorld.length; j = i++) {
            const x1 = polyWorld[j].x, y1 = polyWorld[j].y;
            const x2 = polyWorld[i].x, y2 = polyWorld[i].y;
            const dx = x2 - x1, dy = y2 - y1;
            const len2 = dx * dx + dy * dy;
            if (len2 === 0) continue;
            let t = ((px - x1) * dx + (py - y1) * dy) / len2;
            t = Math.max(0, Math.min(1, t));
            const projX = x1 + t * dx, projY = y1 + t * dy;
            const ddx = px - projX, ddy = py - projY;
            const dsq = ddx * ddx + ddy * ddy;
            if (dsq < minDistSq) minDistSq = dsq;
        }
        return Math.sqrt(minDistSq) <= margin;
    }
    return false;
}

// --- Construcción de obstáculos desde mapsConfig ---
function _resolveMapCfg(zoneId, state) {
    const maps = (state && state.SERVER_CONFIG) ? (state.SERVER_CONFIG.mapsConfig || {}) : {};
    let cfg = maps[zoneId] || maps[String(zoneId)];
    if (cfg) return cfg;
    // Soporte para instancias dinámicas: extract_10_...  -> mapa base 10
    const zid = String(zoneId);
    if (zid.startsWith('extract_')) {
        const parts = zid.split('_');
        if (parts.length >= 2) {
            const base = parts[1];
            cfg = maps[base] || maps[String(base)];
            if (cfg) return cfg;
        }
    }
    // Arena: arena_xxx ?
    if (zid.startsWith('arena_')) {
        const base = zid.split('_')[1];
        cfg = maps[base] || maps[String(base)];
        if (cfg) return cfg;
    }
    return null;
}

function _buildObstaclesForZone(zoneId, state) {
    const mapCfg = _resolveMapCfg(zoneId, state);
    if (!mapCfg) return [];

    const objs = Array.isArray(mapCfg.objects) ? mapCfg.objects : [];
    const obstacles = [];
    const mapW = mapCfg.width ? Number(mapCfg.width) : 4000;
    const mapH = mapCfg.height ? Number(mapCfg.height) : 4000;

    for (const obj of objs) {
        const typeRaw = String(obj.type || '').toLowerCase();
        // Ignorar decor y portales que no bloquean fisicamente
        if (IGNORED_TYPES.has(typeRaw)) continue;
        // Si no es bloqueante y no tiene colisión explícita, saltar
        const hasExplicitCollider = Array.isArray(obj.colliders) && obj.colliders.length > 0;
        const hasColType = typeof obj.colType === 'string' && obj.colType !== '';
        const hasColSize = (Number(obj.colWidth) > 0 || Number(obj.colHeight) > 0);
        if (!BLOCKED_TYPES.has(typeRaw) && !hasExplicitCollider && !hasColType && !hasColSize) {
            // Para objetos sin type conocido pero con colisión (caso legacy), tratarlos si tienen colisión
            // Si es 'wall' o tiene colisión, es bloqueante. Si no tiene nada, es decor => skip
            if (typeRaw !== 'wall' && typeRaw !== '') continue;
        }
        // Para market/chest que son Area2D sin StaticBody, pero sus colliders SÍ representan paredes internas
        // (ej. Mercado en Map1 tiene 5 rects). Los incluimos igual como bloqueantes porque visualmente es estructura.
        // El cliente en _spawn_objects_from_custom_scene crea los child colliders como walls separados,
        // pero en mapsConfig ya vienen embebidos como obj.colliders => los usamos.

        const scaleVal = parseFloat(obj.scale) || 1.0;
        const rotY = parseFloat(obj.rotY) || 0;
        let objX = parseFloat(obj.x) || 0;
        let objY = parseFloat(obj.y) || 0;
        // Hotfix: Altar1 de Mapa 2 tiene desfase servidor/cliente (tscn 3236,1306 vs json 2320,2327) — forzar posición real de la escena
        // Si no se corrige, el validator deja libre el área visual del altar y los enemigos spawnean debajo.
        if ((String(zoneId) === '2') && String(obj.label) === 'Altar1') {
            objX = 3205.49;
            objY = 1284.40;
        }

        if (hasExplicitCollider) {
            for (const c of obj.colliders) {
                const cType = String(c.type || 'rect').toLowerCase();
                const cW = parseFloat(c.width) || 0;
                const cH = parseFloat(c.height) || 0;
                const offX = parseFloat(c.offsetX) || 0;
                const offY = parseFloat(c.offsetY) || 0;
                const cRot = parseFloat(c.rot) || 0;

                // sub_offset = Vector2(offX, offY) * scale rotated by -rotY  (BaseMap.gd:1829)
                const radRotY = _degToRad(-rotY);
                const cosRY = Math.cos(radRotY), sinRY = Math.sin(radRotY);
                const offRX = (offX * scaleVal) * cosRY - (offY * scaleVal) * sinRY;
                const offRY = (offX * scaleVal) * sinRY + (offY * scaleVal) * cosRY;
                const cx = objX + offRX;
                const cy = objY + offRY;
                const rotRad = _degToRad(-(rotY + cRot));

                if (cType === 'circle') {
                    let rx = cW * scaleVal * 0.5;
                    let ry = cH * scaleVal * 0.5;
                    if (ry <= 0 || Math.abs(ry - rx) < 0.01) ry = rx / CORRECTION_Z;
                    // Altares y estructuras centrales: ampliar zona prohibida para cubrir base visual (espinas)
                    const isAltar = typeRaw === 'altar' || String(obj.label||'').toLowerCase().includes('altar');
                    if (isAltar) { rx *= 1.65; ry *= 1.65; }
                    obstacles.push({ kind: 'ellipse', cx, cy, rx, ry, rot: rotRad, label: obj.label });
                } else {
                    let w = cW * scaleVal;
                    let h = cH * scaleVal;
                    if (w <= 0 || h <= 0) continue;
                    const isAltar = typeRaw === 'altar' || String(obj.label||'').toLowerCase().includes('altar');
                    if (isAltar) { w *= 1.65; h *= 1.65; }
                    obstacles.push({ kind: 'rect', cx, cy, w, h, rot: rotRad, label: obj.label });
                }
            }
        } else {
            // Single collider o autodetect fallback
            const colType = String(obj.colType || '').toLowerCase();
            const colWraw = parseFloat(obj.colWidth) || 0;
            const colHraw = parseFloat(obj.colHeight) || 0;
            const offXraw = parseFloat(obj.colOffsetX) || 0;
            const offYraw = parseFloat(obj.colOffsetY) || 0;
            const colRotRaw = parseFloat(obj.colRot) || 0;

            // Si no hay datos de colisión y es un wall genérico (assetPath vacío tipo CSGBox3D),
            // BaseMap.gd hace fallback a 100*scale x 20*scale cuando no puede calcular AABB.
            // Para replicar sin el modelo, usamos ese fallback si colType vacío y sin medidas.
            let isCircle = false;
            let w = 0, h = 0;
            let useFallback = false;

            if (colType === 'circle') {
                isCircle = true;
                w = colWraw * scaleVal;
                h = colHraw * scaleVal;
                if (h <= 0 || Math.abs(h - w) < 0.01) h = w / CORRECTION_Z;
            } else if (colType === 'rect') {
                w = colWraw * scaleVal;
                h = colHraw * scaleVal;
            } else {
                // Autodetect: sin colType => intentar inferir. Si tiene medidas, usarlas.
                if (colWraw > 0 && colHraw > 0) {
                    w = colWraw * scaleVal;
                    h = colHraw * scaleVal;
                    const ratio = w / (h || 1);
                    if (ratio >= 0.82 && ratio <= 1.22) isCircle = true;
                    if (isCircle && Math.abs(h - w) < 0.01) h = w / CORRECTION_Z;
                } else {
                    // Fallback idéntico a BaseMap.gd línea 1918-1920
                    // Solo para type wall/tower/altar donde el glb no trajo medidas
                    if (typeRaw === 'altar') {
                        isCircle = true;
                        w = 240.0;
                        h = 240.0 / CORRECTION_Z;
                        useFallback = true;
                    } else if (typeRaw === 'wall' || typeRaw === 'tower') {
                        w = 100.0 * scaleVal;
                        h = 20.0 * scaleVal;
                        useFallback = true;
                    } else {
                        continue; // sin colisión útil
                    }
                }
            }
            if (w <= 0 || h <= 0) continue;

            // offset solo si no es fallback (fallback offset 0)
            let offRX = 0, offRY = 0;
            if (!useFallback) {
                const radRotY = _degToRad(-rotY);
                const cosRY = Math.cos(radRotY), sinRY = Math.sin(radRotY);
                offRX = (offXraw * scaleVal) * cosRY - (offYraw * scaleVal) * sinRY;
                offRY = (offXraw * scaleVal) * sinRY + (offYraw * scaleVal) * cosRY;
            }
            const cx = objX + offRX;
            const cy = objY + offRY;
            const rotRad = _degToRad(-(rotY + colRotRaw));

            if (isCircle) {
                let rx = w * 0.5;
                let ry = h * 0.5;
                const isAltar = typeRaw === 'altar' || String(obj.label||'').toLowerCase().includes('altar');
                if (isAltar) { rx *= 1.65; ry *= 1.65; }
                obstacles.push({ kind: 'ellipse', cx, cy, rx, ry, rot: rotRad, label: obj.label });
            } else {
                let w2 = w; let h2 = h;
                const isAltar = typeRaw === 'altar' || String(obj.label||'').toLowerCase().includes('altar');
                if (isAltar) { w2 *= 1.65; h2 *= 1.65; }
                obstacles.push({ kind: 'rect', cx, cy, w: w2, h: h2, rot: rotRad, label: obj.label });
            }
        }
    }

    // (Opcional) Añadir bordes físicos si el mapa tiene perimeter walls activos.
    // BaseMap.gd:enable_physical_border = false por defecto (fantasma). No bloquea.
    // Si tu mapa los activa, se añadirían 4 rects. Aquí los ignoramos para no encerrar spawns,
    // pero sí validamos límites del mapa (0..width, 0..height) con margen.
    return obstacles;
}

function getObstaclesForZone(zoneId, state) {
    const key = String(zoneId);
    const cfg = _resolveMapCfg(zoneId, state);
    const objCount = cfg?.objects ? cfg.objects.length : -1;
    const mapW = cfg?.width || 0;
    const mapH = cfg?.height || 0;
    const cached = _cache.get(key);
    if (cached && cached.objCount === objCount && cached.mapW === mapW && cached.mapH === mapH) {
        return cached.obstacles;
    }
    const obstacles = _buildObstaclesForZone(zoneId, state);
    _cache.set(key, { objCount, mapW, mapH, obstacles });
    if (obstacles.length > 0) {
        Logger.debug('SPAWN-VALIDATOR', `Cache reconstruida zona ${zoneId}: ${obstacles.length} colisiones bloqueantes`);
    }
    return obstacles;
}

function isPointBlocked(px, py, zoneId, state, enemyRadius = DEFAULT_ENEMY_RADIUS) {
    const obstacles = getObstaclesForZone(zoneId, state);
    const margin = enemyRadius + EXTRA_MARGIN;
    // Límites del mapa (evitar spawnear fuera con margen)
    const cfg = _resolveMapCfg(zoneId, state);
    if (cfg) {
        const w = Number(cfg.width) || 4000;
        const h = Number(cfg.height) || 4000;
        if (px < margin || py < margin || px > w - margin || py > h - margin) return true;
    }
    for (const obs of obstacles) {
        if (obs.kind === 'rect') {
            if (_pointInRotatedRect(px, py, obs.cx, obs.cy, obs.w, obs.h, obs.rot, margin, margin)) return true;
        } else if (obs.kind === 'ellipse') {
            if (_pointInRotatedEllipse(px, py, obs.cx, obs.cy, obs.rx, obs.ry, obs.rot, margin)) return true;
        } else if (obs.kind === 'poly') {
            if (_pointInPolygon(px, py, obs.polyWorld, margin)) return true;
        }
    }
    return false;
}

/**
 * Busca posición válida dentro de un círculo (cx,cy,radius) evitando obstáculos.
 * @param {number} cx centro X
 * @param {number} cy centro Y
 * @param {number} radius radio del área
 * @param {string|number} zoneId
 * @param {object} state
 * @param {object} opts { maxAttempts, enemyRadius, extraMargin, useUniformDisk }
 * @returns {{x:number,y:number}|null} punto válido o null si no se encontró (fallback a centro si está libre)
 */
function findValidSpawnPosition(cx, cy, radius, zoneId, state, opts = {}) {
    const maxAttempts = opts.maxAttempts ?? 30;
    const enemyRadius = opts.enemyRadius ?? DEFAULT_ENEMY_RADIUS;
    const useUniformDisk = opts.useUniformDisk ?? true;

    if (radius <= 0) {
        return isPointBlocked(cx, cy, zoneId, state, enemyRadius) ? null : { x: cx, y: cy };
    }

    // Intento 1: muestreo aleatorio uniforme en disco (rejection sampling)
    for (let i = 0; i < maxAttempts; i++) {
        const angle = Math.random() * Math.PI * 2;
        // uniforme en disco = sqrt(random) * R (si false => más densidad en centro como el código original)
        const r = useUniformDisk ? Math.sqrt(Math.random()) * radius : Math.random() * radius;
        let px = cx + Math.cos(angle) * r;
        let py = cy + Math.sin(angle) * r;
        // clamp a límites antes de chequear bloqueo para no rechazar innecesario que luego se clampea
        if (!isPointBlocked(px, py, zoneId, state, enemyRadius)) {
            return { x: px, y: py };
        }
    }

    // Intento 2: muestreo sistemático en anillos (determinista) para no depender del RNG cuando el área está muy obstruida
    const rings = [0.2, 0.45, 0.70, 0.85, 1.0];
    const anglesPerRing = 16;
    for (const fr of rings) {
        const r = radius * fr;
        for (let a = 0; a < anglesPerRing; a++) {
            const angle = (a / anglesPerRing) * Math.PI * 2 + (fr * 0.37); // pequeño offset para no repetir
            const px = cx + Math.cos(angle) * r;
            const py = cy + Math.sin(angle) * r;
            if (!isPointBlocked(px, py, zoneId, state, enemyRadius)) {
                return { x: px, y: py };
            }
        }
    }

    // Intento 3: ray-march hacia afuera desde el centro buscando el primer punto libre en dirección aleatoria
    // Útil si el centro está libre pero el anillo muestreado cayó en paredes.
    if (!isPointBlocked(cx, cy, zoneId, state, enemyRadius)) {
        return { x: cx, y: cy };
    }
    // Si hasta el centro está bloqueado, intentar desplazar el centro mismo fuera del obstáculo
    // buscando en 32 direcciones a distancia radius*0.15 (cerca)
    for (let a = 0; a < 32; a++) {
        const angle = (a / 32) * Math.PI * 2;
        const px = cx + Math.cos(angle) * (radius * 0.15);
        const py = cy + Math.sin(angle) * (radius * 0.15);
        if (!isPointBlocked(px, py, zoneId, state, enemyRadius)) {
            return { x: px, y: py };
        }
    }

    // Intento 4: expandir progresivamente más allá del radio original (para spawns fijos dentro de pared)
    // El área original puede estar 100% bloqueada (pared más grande que el radio). Buscamos hasta 3x el radio,
    // pero para radios muy pequeños (<60) ampliar hasta 300px absolutos para salir de estructuras grandes.
    const expandSteps = [1.4, 2.0, 3.0, 5.0];
    for (const mult of expandSteps) {
        let expR = radius * mult;
        if (radius < 60) expR = Math.max(expR, 180 + mult * 20); // garantizar breakout mínimo
        for (let a = 0; a < 32; a++) {
            const angle = (a / 32) * Math.PI * 2;
            const px = cx + Math.cos(angle) * expR;
            const py = cy + Math.sin(angle) * expR;
            if (!isPointBlocked(px, py, zoneId, state, enemyRadius)) {
                Logger.debug('SPAWN-VALIDATOR', `Punto expandido x${mult} (${Math.round(expR)}px) zona ${zoneId} @ [${Math.round(px)},${Math.round(py)}]`);
                return { x: px, y: py };
            }
        }
    }
    // Último recurso: muestreo aleatorio amplio alrededor (hasta 700px o radius*5) para escapar de clusters/altares gigantes
    const farRadius = Math.max(700, radius * 5);
    for (let i = 0; i < 60; i++) {
        const angle = Math.random() * Math.PI * 2;
        const r = (radius * 1.2) + Math.random() * (farRadius - radius * 1.2);
        const px = cx + Math.cos(angle) * r;
        const py = cy + Math.sin(angle) * r;
        if (!isPointBlocked(px, py, zoneId, state, enemyRadius)) {
            return { x: px, y: py };
        }
    }

    // Fallback: devolver null y que el caller decida (mantener posición original con warning)
    Logger.warn('SPAWN-VALIDATOR', `No se encontró punto libre en zona ${zoneId} centro [${Math.round(cx)},${Math.round(cy)}] r=${radius} tras ${maxAttempts} intentos + barrido + expansión.`);
    return null;
}

function clearCache(zoneId = null) {
    if (zoneId === null) _cache.clear();
    else _cache.delete(String(zoneId));
}

module.exports = {
    CORRECTION_Z,
    DEFAULT_ENEMY_RADIUS,
    EXTRA_MARGIN,
    getObstaclesForZone,
    isPointBlocked,
    findValidSpawnPosition,
    clearCache
};
