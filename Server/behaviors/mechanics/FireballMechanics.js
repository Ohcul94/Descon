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

function _applyFireballDamage(ai, state, radius, dmg, now, io, players, pullCfg) {
    const zonePlayers = Object.values(players || {}).filter(p =>
        String(p.zone) === String(ai.enemy.zone) && !p.isDead && !p.isInvisible);

    zonePlayers.forEach(p => {
        const d = Math.hypot(p.x - state.x, p.y - state.y);
        if (d > radius) return;

        recordPlayerCombat(p, ai.state, now);

        if (p.isInvulnerable) return;

        // Reparto escudo -> casco (autoritativo)
        if (p.shield >= dmg) {
            p.shield -= dmg;
        } else {
            p.hp -= (dmg - p.shield);
            p.shield = 0;
        }
        if (p.hp < 0) p.hp = 0;
        if (p.hp <= 0) ai._killPlayer(p, io);

        // Reflejo autoritativo
        if (p.reflectActive) {
            const reflectMult = 0.8;
            const reflectedDmg = Math.round(dmg * reflectMult);
            if (reflectedDmg > 0) {
                if (ai.enemy.shield >= reflectedDmg) ai.enemy.shield -= reflectedDmg;
                else { ai.enemy.hp -= (reflectedDmg - ai.enemy.shield); ai.enemy.shield = 0; }
                if (ai.enemy.hp < 0) ai.enemy.hp = 0;
                io.to(`zone_${ai.enemy.zone}`).emit('enemyDamaged', {
                    id: ai.enemy.id, hp: Math.max(0, ai.enemy.hp), shield: ai.enemy.shield
                });
            }
        }

        io.to(p.socketId).emit('environmentDamage', { damage: dmg });
        io.to(`zone_${p.zone}`).emit('playerStatSync', {
            id: p.socketId,
            hp: Math.ceil(p.hp),
            shield: Math.ceil(p.shield),
            isDead: p.isDead,
            isInvulnerable: p.isInvulnerable,
            isInvisible: p.isInvisible
        });
    });

    // Daño al Altar (modo defensa) si cae dentro del radio de la bola
    const altarState = ai.state.altarState;
    if (altarState && altarState.hp > 0 && String(altarState.zone) === String(ai.enemy.zone)) {
        const altarX = Number(altarState.x) || 5000;
        const altarY = Number(altarState.y) || 5000;
        if (Math.hypot(altarX - state.x, altarY - state.y) <= radius) {
            altarDefenseManager.applyDamageToAltar(dmg, ai.enemy.zone);
        }
    }
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
    const pullEnabled = mech.pullEnabled === true;
    const pullRadius = Math.max(0, _num(mech.pullRadius, 250));
    const pullStrength = Math.max(0, _num(mech.pullStrength, 180));
    const rayDmg = Math.max(0, _num(mech.ray_damage, 20)) * (ai.damageMult || 1);
    const dmgPerTick = _num(mech.damage_per_tick, 30) * (ai.damageMult || 1);
    const pullCfg = { enabled: pullEnabled, radius: pullRadius, rayDmg: rayDmg };
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
        state.lastTick = spawnNow;
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
            duration: duration
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

    // FASE 3: BOLA ACTIVA (movimiento + daño por ticks)
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

        // Sincronización de posición (silenciosa para no repetir el sonido de la mecánica)
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

        // Daño por tick
        if (now - (state.lastTick || 0) >= tickInterval) {
            state.lastTick = now;
            _applyFireballDamage(ai, state, radius, dmgPerTick, now, io, players, pullCfg);
        }
        // Emisión de atracción cada tick si está habilitada
        if (pullEnabled) {
            const zonePlayers = Object.values(players || {}).filter(p =>
                String(p.zone) === String(ai.enemy.zone) && !p.isDead && !p.isInvisible);
            zonePlayers.forEach(p => {
                const d = Math.hypot(p.x - state.x, p.y - state.y);
                if (d <= pullRadius && d > 0) {
                    io.to(p.socketId).emit('fireball_pull', {
                        attackerId: ai.enemy.id,
                        mId: mId,
                        ballX: state.x,
                        ballY: state.y,
                        pullSpeed: pullStrength,
                        duration: 600
                    });
                }
            });
        }
    }

    ai.enemy.mechState[mId] = state;
    return state.isCharging || state.isActive;
}

module.exports = { _handleFireballLogic };
