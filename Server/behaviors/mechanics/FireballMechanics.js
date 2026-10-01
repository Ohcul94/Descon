// Server/behaviors/mechanics/FireballMechanics.js
// v901.0: Bola de Fuego Dinámica (esfera solar que deambula por un área determinada)
//
// Verdad de configuración: AdminDash (mechanicsLib['fireball'] + instancia en enemyModels).
// Verdad de ejecución: ESTE SERVIDOR. El cliente Godot solo renderiza el VFX (FireballSunVisual)
// a partir de los eventos serverEnemyAction que emite este módulo.
//
// Campos del Admin:
//   areaRadius  -> radio del área donde deambula la bola
//   areaMode    -> 'enemy' (alrededor del enemigo) | 'target' (sobre el objetivo)
//   radius      -> tamaño de la bola (= radio de daño)
//   speed       -> velocidad de la bola (px/s)
//   damage_per_tick / tick_interval -> daño y cadencia
//   duration    -> duración total de la bola (ms)
//   cooldown    -> enfriamiento tras expirar (ms)
//   castTimeMs  -> carga/telegrafiado previo al spawn (ms)

const altarDefenseManager = require('../../systems/altarDefenseManager');
const { recordPlayerCombat } = require('../../utils/partyUtils');

// Cadencia mínima de sincronización de posición hacia los clientes (ms)
const POS_SYNC_INTERVAL = 100;
// Cadencia mínima de tick de daño (ms) para no saturar la red a 30 TPS
const MIN_TICK_INTERVAL = 250;
// Máximo de vida de un waypoint antes de elegir uno nuevo (ms)
const WAYPOINT_MAX_AGE = 3500;

function _num(v, fallback) {
    return (v !== undefined && v !== null && !isNaN(Number(v))) ? Number(v) : fallback;
}

function _pickWaypoint(state, areaRadius) {
    // Distribución uniforme dentro del círculo del área (sqrt evita concentración en el centro)
    const r = Math.sqrt(Math.random()) * areaRadius;
    const a = Math.random() * Math.PI * 2;
    state.wpX = state.areaX + Math.cos(a) * r;
    state.wpY = state.areaY + Math.sin(a) * r;
    state.wpTime = Date.now();
}

/**
 * Aplica daño autoritativo a un jugador impactado por la bola o por sus rayos.
 */
function _dealDirectDamage(ai, p, dmg, now, io, source = "fireball") {
    if (!p || p.isDead || p.isInvulnerable || p.inStrangeDimension || dmg <= 0) return;

    recordPlayerCombat(p, ai.state, now);
    p.lastCombatTime = now;

    // Reparto escudo -> casco (autoritativo)
    const initialShield = p.shield || 0;
    if (initialShield >= dmg) {
        p.shield -= dmg;
    } else {
        p.hp -= (dmg - initialShield);
        p.shield = 0;
    }
    if (p.hp < 0) p.hp = 0;

    // Sistema de Agro: registrar daño recibido por tanque / jugador
    if (ai.enemy && ai.enemy.threatTable) {
        ai.enemy.threatTable.addTankingThreat(p.socketId, dmg, p);
    }

    if (p.hp <= 0) {
        ai._killPlayer(p, io);
    }

    // Reflejo autoritativo
    if (p.reflectActive && !p.isInvulnerable) {
        const reflectMult = 0.8;
        const reflectedDmg = Math.round(dmg * reflectMult);
        if (reflectedDmg > 0 && ai.enemy) {
            if (ai.enemy.shield >= reflectedDmg) ai.enemy.shield -= reflectedDmg;
            else { ai.enemy.hp -= (reflectedDmg - (ai.enemy.shield || 0)); ai.enemy.shield = 0; }
            if (ai.enemy.hp < 0) ai.enemy.hp = 0;
            io.to(`zone_${ai.enemy.zone}`).emit('enemyDamaged', {
                id: ai.enemy.id, hp: Math.max(0, ai.enemy.hp), shield: ai.enemy.shield
            });
        }
    }

    io.to(p.socketId).emit('environmentDamage', { damage: dmg, source: source });
    io.to(`zone_${p.zone}`).emit('playerStatSync', {
        id: p.socketId,
        hp: Math.ceil(p.hp),
        shield: Math.ceil(p.shield),
        isDead: p.isDead,
        isInvulnerable: p.isInvulnerable,
        isInvisible: p.isInvisible,
        spheres: p.spheres || []
    });
}

function _handleFireballLogic(mech, mId, target, dist, now, io, players) {
    if (!io) return false;

    const ai = this;
    const state = ai.enemy.mechState[mId] || { nextShotTime: 0, isCharging: false, isActive: false };
    ai.enemy.mechState[mId] = state;

    const enemyFireRange = Number(ai.config?.fireRange || ai.enemy?.fireRange || 800);
    const fireRange = (mech.fireRange !== undefined && Number(mech.fireRange) > 0) ? Number(mech.fireRange) : enemyFireRange;
    const cooldown = _num(mech.cooldown, 12000);
    const duration = _num(mech.duration, 6000);
    const areaRadius = Math.max(0, _num(mech.areaRadius, 350));
    const radius = Math.max(10, _num(mech.radius, 90));
    const speed = Math.max(0, _num(mech.speed, 180));
    const tickInterval = Math.max(MIN_TICK_INTERVAL, _num(mech.tick_interval, 800));
    const pullEnabled = mech.pullEnabled === true || mech.pullEnabled === 'true' || mech.pullEnabled === 1;
    const pullRadius = Math.max(0, _num(mech.pullRadius, 400));
    const pullStrength = Math.max(0, _num(mech.pullStrength, 180));
    const rayDmg = Math.max(0, _num(mech.ray_damage, 20)) * (ai.damageMult || 1);
    
    // Soporte inteligente de daño: damage_per_tick > damage > bulletDamage > default 30
    const rawDamage = _num(mech.damage_per_tick, _num(mech.damage, _num(mech.bulletDamage, 30)));
    const dmgPerTick = Math.max(1, rawDamage) * (ai.damageMult || 1);

    const chargeTime = Math.max(0, _num(mech.castTimeMs, 1200));
    const areaMode = (mech.areaMode === 'target') ? 'target' : 'enemy';
    const zoneRoom = `zone_${ai.enemy.zone}`;

    const spawnFireball = (spawnNow) => {
        state.isCharging = false;
        state.isActive = true;
        state.activeEnd = spawnNow + duration;
        state.x = state.areaX;
        state.y = state.areaY;
        state.lastSim = spawnNow;
        state.lastEmit = spawnNow;
        state.playerLastDamage = {};
        state.playerLastRayDamage = {};
        state.lastAltarTick = 0;
        _pickWaypoint(state, areaRadius);

        io.to(zoneRoom).emit('serverEnemyAction', {
            id: ai.enemy.id,
            mId: mId,
            action: 'fireball_spawn',
            type: 'fireball',
            x: state.x,
            y: state.y,
            areaX: state.areaX,
            areaY: state.areaY,
            areaRadius: areaRadius,
            radius: radius,
            speed: speed,
            duration: duration,
            pullEnabled: pullEnabled,
            pullRadius: pullRadius,
            pullStrength: pullStrength,
            ray_damage: rayDmg
        });
    };

    // FASE 1: TELEGRAFIADO / CARGA
    if (!state.isCharging && !state.isActive) {
        if (now < (state.nextShotTime || 0)) return false;
        if (!target || dist > fireRange) return false;

        state.areaX = (areaMode === 'target') ? target.x : ai.enemy.x;
        state.areaY = (areaMode === 'target') ? target.y : ai.enemy.y;

        if (chargeTime <= 0) {
            spawnFireball(now);
        } else {
            state.isCharging = true;
            state.chargeEnd = now + chargeTime;
            io.to(zoneRoom).emit('serverEnemyAction', {
                id: ai.enemy.id,
                mId: mId,
                action: 'fireball_charge',
                type: 'fireball',
                silent: true,
                x: state.areaX,
                y: state.areaY,
                areaRadius: areaRadius,
                radius: radius,
                duration: duration,
                chargeMs: chargeTime
            });
        }

        ai.enemy.mechState[mId] = state;
        return state.isCharging || state.isActive;
    }

    // FASE 2: FIN DE LA CARGA -> SPAWN
    if (state.isCharging) {
        if (now >= state.chargeEnd) {
            spawnFireball(now);
        }
        ai.enemy.mechState[mId] = state;
        return true;
    }

    // FASE 3: BOLA ACTIVA (movimiento + detección continua de daño por ticks)
    if (state.isActive) {
        if (now >= state.activeEnd) {
            // FASE 4: EXPIRACIÓN
            state.isActive = false;
            state.nextShotTime = now + cooldown;
            io.to(zoneRoom).emit('serverEnemyAction', {
                id: ai.enemy.id,
                mId: mId,
                action: 'fireball_expire',
                type: 'fireball',
                silent: true
            });
            ai.enemy.mechState[mId] = state;
            return false;
        }

        // Delta real entre ticks (con tope para picos de latencia del loop)
        let dt = (now - (state.lastSim || now)) / 1000;
        if (dt <= 0) dt = 0.033;
        if (dt > 0.1) dt = 0.1;
        state.lastSim = now;

        // Movimiento hacia el waypoint dentro del área
        if (state.wpX === undefined) _pickWaypoint(state, areaRadius);
        const wdx = state.wpX - state.x;
        const wdy = state.wpY - state.y;
        const wpDist = Math.hypot(wdx, wdy);
        const step = speed * dt;
        if (wpDist <= Math.max(step, 6)) {
            _pickWaypoint(state, areaRadius);
        } else {
            state.x += (wdx / wpDist) * step;
            state.y += (wdy / wpDist) * step;
        }
        if (now - (state.wpTime || now) > WAYPOINT_MAX_AGE) {
            _pickWaypoint(state, areaRadius);
        }

        // Sincronización de posición hacia los clientes
        if (now - (state.lastEmit || 0) >= POS_SYNC_INTERVAL) {
            state.lastEmit = now;
            io.to(zoneRoom).emit('serverEnemyAction', {
                id: ai.enemy.id,
                mId: mId,
                action: 'fireball_move',
                type: 'fireball',
                silent: true,
                x: state.x,
                y: state.y
            });
        }

        // Inicializar mapas de daño por jugador si no existen
        if (!state.playerLastDamage) state.playerLastDamage = {};
        if (!state.playerLastRayDamage) state.playerLastRayDamage = {};

        // Chequeo continuo de daño por contacto con la bola
        const zonePlayers = Object.values(players || {}).filter(p =>
            String(p.zone) === String(ai.enemy.zone) && !p.isDead && !p.isInvisible);

        zonePlayers.forEach(p => {
            const d = Math.hypot(p.x - state.x, p.y - state.y);
            const playerRadius = Number(p.radius || 35);
            const hitRadius = radius + playerRadius;

            // 1. Daño directo por contacto con la esfera solar:
            // Al hacer contacto, el primer impacto es INMEDIATO, luego sigue cada tickInterval
            if (d <= hitRadius) {
                const lastHit = state.playerLastDamage[p.socketId] || 0;
                if (now - lastHit >= tickInterval) {
                    state.playerLastDamage[p.socketId] = now;
                    _dealDirectDamage(ai, p, dmgPerTick, now, io, "fireball");
                }
            }

            // 2. Daño periódico por rayos si pullEnabled está activo y está en el rango
            if (pullEnabled && pullRadius > 0 && d <= pullRadius) {
                if (rayDmg > 0) {
                    state.playerLastRayDamage = state.playerLastRayDamage || {};
                    const lastRay = state.playerLastRayDamage[p.socketId] || 0;
                    if (now - lastRay >= tickInterval) {
                        state.playerLastRayDamage[p.socketId] = now;
                        _dealDirectDamage(ai, p, rayDmg, now, io, "fireball_ray");
                    }
                }
            }
        });

        // 3. Daño al Altar si cae dentro del radio de la bola
        const altarState = ai.state.altarState;
        if (altarState && altarState.hp > 0 && String(altarState.zone) === String(ai.enemy.zone)) {
            const altarX = Number(altarState.x) || 5000;
            const altarY = Number(altarState.y) || 5000;
            if (Math.hypot(altarX - state.x, altarY - state.y) <= (radius + 60)) {
                const lastAltar = state.lastAltarTick || 0;
                if (now - lastAltar >= tickInterval) {
                    state.lastAltarTick = now;
                    altarDefenseManager.applyDamageToAltar(dmgPerTick, ai.enemy.zone);
                }
            }
        }
    }

    ai.enemy.mechState[mId] = state;
    return state.isCharging || state.isActive;
}

module.exports = { _handleFireballLogic };
