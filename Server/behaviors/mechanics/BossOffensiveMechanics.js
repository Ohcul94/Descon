// Server/behaviors/mechanics/BossOffensiveMechanics.js
// v413-v414: Mecánicas ofensivas modulares de jefes (Ejecución directa y Ascensión telúrica)

function _handleExecutionLogic(mech, mId, now, io, players) {
    if (!io) return false;
    const state = this.enemy.mechState[mId] || { nextShotTime: 0, triggeredHPs: {}, casting: false, castEndTime: 0, castTargets: [] };
    this.enemy.mechState[mId] = state;

    const enemyFireRange = Number(this.config?.fireRange || this.enemy?.fireRange || 800);
    const fireRange = (mech.fireRange !== undefined && Number(mech.fireRange) > 0) ? Number(mech.fireRange) : enemyFireRange;
    // Generic cast gate (per mechanic, default 0 = instant)
    if (mech.castTimeMs !== undefined && Number(mech.castTimeMs) > 0) {
        const isBusy = this._handleGenericCast(mech, mId, now, io);
        if (isBusy && this._isGenericCastType(mech.type)) {
            return true;
        }
    }
    const targetCount = Math.max(1, parseInt(mech.targetCount, 10) || 1);
    const targetMode = mech.targetMode || "proximity";
    const cooldown = mech.cooldown !== undefined ? Number(mech.cooldown) : 12000;
    const intervalMsRaw = mech.activationIntervalMs !== undefined ? Number(mech.activationIntervalMs) : 8000;
    const intervalMs = intervalMsRaw > 0 ? intervalMsRaw : cooldown;
    const castTimeMs = mech.castTimeMs !== undefined ? Number(mech.castTimeMs) : 700;
    const pointAndClick = !!mech.isPointAndClick;
    const skullSpeed = Number(mech.skullSpeed) || (pointAndClick ? 1800 : 450);

    if (state.nextShotTime === undefined || state.nextShotTime === 0) {
        state.nextShotTime = now + (mech.startDelay || 0);
    }

    const interval = mech.activationMode !== "time" && mech.activationMode !== "hp"
        ? intervalMs : cooldown;

    // 1) Si está en casteo activo, disparar la calavera al terminar el warnTime
    if (state.casting) {
        if (now >= state.castEndTime) {
            state.casting = false;
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "death_cast_end",
                mId: mId
            });
            state.castTargets.forEach(t => {
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: t.socketId,
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y,
                    angle: Math.atan2(t.y - this.enemy.y, t.x - this.enemy.x),
                    bulletType: "execution",
                    bulletSpeed: skullSpeed,
                    damage: 999999,
                    targetX: t.x, targetY: t.y,
                    isHoming: pointAndClick,
                    turnSpeed: pointAndClick ? 8.0 : 1.0,
                    range: fireRange,
                    executionMode: pointAndClick ? "point_click" : "esquivable"
                });
            });
            state.castTargets = [];
            state.nextShotTime = now + cooldown;
        }
        return false;
    }

    const hpPercent = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;

    // 2) Gate de activación
    if (mech.activationMode === "time") {
        if (now < state.nextShotTime) { this.enemy.mechState[mId] = state; return false; }
    } else {
        const thresholds = Array.isArray(mech.activationHPs) && mech.activationHPs.length > 0
            ? mech.activationHPs.map(Number).filter(v => !isNaN(v)) : [50];
        if (!state.triggeredHPs) state.triggeredHPs = {};
        for (const hpVal of thresholds) {
            if (hpPercent > hpVal && state.triggeredHPs[hpVal]) state.triggeredHPs[hpVal] = false;
        }
        let shouldActivate = false;
        if (now > state.nextShotTime) {
            for (const hpVal of thresholds) {
                if (hpPercent <= hpVal) {
                    shouldActivate = true;
                    state.triggeredHPs[hpVal] = true;
                    break;
                }
            }
        }
        if (!shouldActivate) { this.enemy.mechState[mId] = state; return false; }
    }

    // 3) Seleccionar objetivos en rango de visión
    const targets = this._selectMeteorTargets(players, fireRange, targetCount, targetMode, mech);
    if (targets.length === 0) {
        state.nextShotTime = now + interval;
        this.enemy.mechState[mId] = state;
        return false;
    }

    // 4) Iniciar casteo: marcar a los objetivos con la calavera
    state.casting = true;
    state.castEndTime = now + castTimeMs;
    state.castTargets = targets;
    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
        id: this.enemy.id,
        action: "death_cast_start",
        mId: mId,
        castTimeMs: castTimeMs,
        executionMode: pointAndClick ? "point_click" : "esquivable",
        targets: targets.map(t => ({ socketId: t.socketId, x: t.x, y: t.y }))
    });

    io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { msg: '☠️ ¡Una calavera marcó a alguien!', type: 'warning' });

    state.nextShotTime = now + (state.castEndTime - now) + cooldown;
    this.enemy.mechState[mId] = state;
    return false;
}

function _handleAscensionLogic(mech, mId, target, dist, angle, now, io, players) {
    if (!io) return false;
    const state = this.enemy.mechState[mId] || { nextShotTime: 0, triggeredHPs: {}, casting: false, castEndTime: 0, castTargets: [], jumps: [] };
    this.enemy.mechState[mId] = state;
    if (!state.jumps) state.jumps = [];

    const enemyFireRange = Number(this.config?.fireRange || this.enemy?.fireRange || 800);
    const fireRange = (mech.fireRange !== undefined && Number(mech.fireRange) > 0) ? Number(mech.fireRange) : enemyFireRange;
    // Generic cast gate (per mechanic, default 0 = instant)
    if (mech.castTimeMs !== undefined && Number(mech.castTimeMs) > 0) {
        const isBusy = this._handleGenericCast(mech, mId, now, io);
        if (isBusy && this._isGenericCastType(mech.type)) {
            return true;
        }
    }
    const targetCount = Math.max(1, parseInt(mech.targetCount, 10) || 1);
    const targetMode = mech.targetMode || "proximity";
    const cooldown = mech.cooldown !== undefined ? Number(mech.cooldown) : 12000;
    const intervalMsRaw = mech.activationIntervalMs !== undefined ? Number(mech.activationIntervalMs) : 8000;
    const intervalMs = intervalMsRaw > 0 ? intervalMsRaw : cooldown;
    const castTimeMs = mech.castTimeMs !== undefined ? Number(mech.castTimeMs) : 1500;
    const airTimeMs = mech.airTimeMs !== undefined ? Number(mech.airTimeMs) : 2000;
    const warnDelayMs = mech.warnDelayMs !== undefined ? Number(mech.warnDelayMs) : 600;
    const warnTimeMs = mech.warnTimeMs !== undefined ? Number(mech.warnTimeMs) : 1200;
    const radius = mech.radius || 250;
    const landingDamage = (mech.bulletDamage !== undefined ? Number(mech.bulletDamage) : 150) * (this.damageMult || 1);

    const zonePlayers = () => Object.values(players || {}).filter(p => String(p.zone) === String(this.enemy.zone) && !p.isDead && !p.isInvisible);

    // 1) Procesar saltos activos
    for (let i = state.jumps.length - 1; i >= 0; i--) {
        const jp = state.jumps[i];
        if (now >= jp.startTime && now < jp.landTime) {
            const riseFrac = Math.min(1.0, Math.max(0.0, (now - jp.startTime) / Math.max(1, airTimeMs * 0.35)));
            this.enemy.x = jp.startX + (jp.endX - jp.startX) * riseFrac;
            this.enemy.y = jp.startY + (jp.endY - jp.startY) * riseFrac;
            if (riseFrac >= 1.0) {
                this.enemy.x = jp.endX;
                this.enemy.y = jp.endY;
            }
        }
        if (now >= jp.landTime) {
            this.enemy.x = jp.endX;
            this.enemy.y = jp.endY;
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "ascension_impact",
                x: jp.endX,
                y: jp.endY,
                radius: radius,
                damage: landingDamage,
                mId: mId + "_" + jp.id
            });

            // Aplicar daño de aterrizaje a los jugadores dentro del área
            zonePlayers().forEach(p => {
                const d = Math.hypot(p.x - jp.endX, p.y - jp.endY);
                if (d > radius) return;
                p.lastCombatTime = Date.now();
                if (p.shield >= landingDamage) {
                    p.shield -= landingDamage;
                } else {
                    p.hp -= (landingDamage - p.shield);
                    p.shield = 0;
                }
                if (p.hp < 0) p.hp = 0;
                if (p.hp <= 0) this._killPlayer(p, io);

                // v400.30: Reflejo autoritativo
                if (p.reflectActive && !p.isInvulnerable) {
                    const reflectedDmg = Math.round(landingDamage * 0.8);
                    if (reflectedDmg > 0) {
                        if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                        else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                        if (this.enemy.hp < 0) this.enemy.hp = 0;
                        io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', {
                            id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield
                        });
                    }
                }

                io.to(p.socketId).emit('environmentDamage', { damage: landingDamage });
                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: p.socketId,
                    hp: Math.ceil(p.hp),
                    shield: Math.ceil(p.shield),
                    isDead: p.isDead
                });
            });

            state.jumps.splice(i, 1);
        }
    }

    if (state.jumps.length === 0 && this.enemy._ascendingUntil && now >= this.enemy._ascendingUntil) {
        delete this.enemy._ascendingUntil;
    }

    // 2) Si está casteando: al terminar el casteo, el enemigo salta
    if (state.casting) {
        if (now >= state.castEndTime) {
            state.casting = false;
            state.isCharging = false;
            state.ascensionCast = false;
            state.castTargets.forEach(t => {
                const jumpId = Date.now() + "_" + Math.floor(Math.random() * 1000);
                const landTime = now + airTimeMs;
                const settleMs = 700;
                this.enemy._ascendingUntil = Math.max(this.enemy._ascendingUntil || 0, landTime + settleMs);
                state.jumps.push({
                    id: jumpId,
                    startX: this.enemy.x,
                    startY: this.enemy.y,
                    endX: Math.round(t.x),
                    endY: Math.round(t.y),
                    startTime: now,
                    landTime: landTime
                });
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "ascension_leap",
                    mId: mId,
                    startX: this.enemy.x,
                    startY: this.enemy.y,
                    endX: Math.round(t.x),
                    endY: Math.round(t.y),
                    targetId: t.socketId,
                    airTimeMs: airTimeMs,
                    warnDelayMs: warnDelayMs,
                    warnTimeMs: warnTimeMs,
                    landTime: landTime,
                    radius: radius,
                    damage: landingDamage
                });
            });
            state.castTargets = [];
            state.nextShotTime = now + cooldown;
        }
        return false;
    }

    // 3) Gate de activación
    if (state.nextShotTime === undefined || state.nextShotTime === 0) {
        state.nextShotTime = now + (mech.startDelay || 0);
    }
    if (mech.activationMode === "time") {
        if (now < state.nextShotTime) { this.enemy.mechState[mId] = state; return false; }
    } else {
        const hpPercent = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;
        const thresholds = Array.isArray(mech.activationHPs) && mech.activationHPs.length > 0
            ? mech.activationHPs.map(Number).filter(v => !isNaN(v)) : [50];
        if (!state.triggeredHPs) state.triggeredHPs = {};
        for (const hpVal of thresholds) {
            if (hpPercent > hpVal && state.triggeredHPs[hpVal]) state.triggeredHPs[hpVal] = false;
        }
        let shouldActivate = false;
        if (now > state.nextShotTime) {
            for (const hpVal of thresholds) {
                if (hpPercent <= hpVal) {
                    shouldActivate = true;
                    state.triggeredHPs[hpVal] = true;
                    break;
                }
            }
        }
        if (!shouldActivate) { this.enemy.mechState[mId] = state; return false; }
    }

    // 4) Seleccionar objetivos e iniciar el casteo
    if (target && dist <= fireRange && now > state.nextShotTime) {
        const targets = this._selectMeteorTargets(players, fireRange, targetCount, targetMode, mech);
        if (targets.length > 0) {
            state.casting = true;
            state.isCharging = true;
            state.ascensionCast = true;
            state.castEndTime = now + castTimeMs;
            state.castTargets = targets;
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "ascension_cast",
                mId: mId,
                castTimeMs: castTimeMs,
                targets: targets.map(t => ({ socketId: t.socketId, x: Math.round(t.x), y: Math.round(t.y) }))
            });
            state.nextShotTime = now + (state.castEndTime - now) + cooldown;
        }
    }

    this.enemy.mechState[mId] = state;
    return false;
}

function _handleChoqueDevastadorLogic(mech, mId, target, dist, angle, now, io, players) {
    if (!io) return false;
    const state = this.enemy.mechState[mId] || {
        nextShotTime: 0, triggeredHPs: {},
        nextReadyTime: (mech.activationMode === "time") ? now + this._getEffectiveInterval(mech) : 0,
        phase: "idle", telegraphStart: 0, chargeStart: 0,
        chargeAngle: 0, chargeDirX: 0, chargeDirY: 0,
        hitPlayers: [], distanceTraveled: 0
    };
    this.enemy.mechState[mId] = state;

    const zoneStr = `zone_${this.enemy.zone}`;
    const enemyFireRange = Number(this.config?.fireRange || this.enemy?.fireRange || 800);
    const fireRange = (mech.range !== undefined && Number(mech.range) > 0) ? Number(mech.range) : enemyFireRange;
    const cooldown = mech.cooldown !== undefined ? Number(mech.cooldown) : 10000;
    const chargeSpeed = Number(mech.speed) || 600;
    const chargeDurationMs = Number(mech.duration) || 1200;
    const chargeRange = Number(mech.range) || 900;
    const width = Number(mech.radius) || 200;
    const bulletDamage = (mech.damage !== undefined ? Number(mech.damage) : 200) * (this.damageMult || 1);
    const telegraphDurationMs = Number(mech.warnTimeMs) || 0;
    const pushOnHit = !!mech.pushOnHit;
    const pushForce = Number(mech.pushForce) || 200;
    const castTimeMs = Math.max(0, Number(mech.castTimeMs || 0));

    // Generic cast gate (parallel, internal type)
    if (castTimeMs > 0) {
        const isBusy = this._handleGenericCast(mech, mId, now, io);
        if (isBusy && this._isGenericCastType(mech.type)) {
            return true;
        }
    }

    // ---- IDLE: Verificar activation gate ----
    if (state.phase === "idle") {
        if (now < (state.nextShotTime || 0)) return false;
        if (dist > fireRange) return false;
        if (!this._inCombat && mech.activationMode === "time") {
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
        }
        const hpPercent = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;
        if (!this._passesActivationGate(mech, state, now, hpPercent)) return false;

        // Iniciar telegraph
        state.phase = "telegraph";
        state.telegraphStart = now;
        state.chargeAngle = angle;
        state.chargeDirX = Math.cos(angle);
        state.chargeDirY = Math.sin(angle);
        state.hitPlayers = [];
        state.distanceTraveled = 0;

        io.to(zoneStr).emit('serverEnemyAction', {
            id: this.enemy.id,
            action: "choque_devastador_start",
            mId: mId,
            x: Math.round(this.enemy.x),
            y: Math.round(this.enemy.y),
            angle: Math.round(angle * 100) / 100,
            radius: width,
            range: chargeRange,
            warnTimeMs: telegraphDurationMs,
            duration: chargeDurationMs
        });
        this.enemy.mechState[mId] = state;
        return true;
    }

    // ---- TELEGRAPH: Esperar duración del marcador ----
    if (state.phase === "telegraph") {
        if (now - state.telegraphStart < telegraphDurationMs) {
            return true; // seguir esperando
        }
        // Transición a charge
        state.phase = "charging";
        state.chargeStart = now;
        state.hitPlayers = [];
        state.distanceTraveled = 0;

        io.to(zoneStr).emit('serverEnemyAction', {
            id: this.enemy.id,
            action: "choque_devastador_charge",
            mId: mId,
            angle: Math.round(state.chargeAngle * 100) / 100,
            speed: chargeSpeed,
            duration: chargeDurationMs
        });
        this.enemy.mechState[mId] = state;
        return true;
    }

    // ---- CHARGING: Mover y detectar colisiones ----
    if (state.phase === "charging") {
        const elapsed = now - state.chargeStart;
        if (elapsed >= chargeDurationMs || state.distanceTraveled >= chargeRange) {
            // Fin de carga
            state.phase = "idle";
            state.nextShotTime = now + cooldown;
            state.nextReadyTime = now + cooldown;
            this.enemy._castFreezeCount = Math.max(0, (this.enemy._castFreezeCount || 1) - 1);

            io.to(zoneStr).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "choque_devastador_end",
                mId: mId
            });
            this.enemy.mechState[mId] = state;
            return false;
        }

        // Mover enemigo
        const step = chargeSpeed * 0.033; // ~30fps tick
        this.enemy.x += state.chargeDirX * step;
        this.enemy.y += state.chargeDirY * step;
        state.distanceTraveled += step;
        this.enemy.rotation = state.chargeAngle + Math.PI / 2;

        // Broadcast posición durante la carga
        io.to(zoneStr).emit('enemyUpdated', {
            id: this.enemy.id,
            x: Math.round(this.enemy.x),
            y: Math.round(this.enemy.y),
            rotation: Math.round(this.enemy.rotation * 100) / 100
        });

        // Detectar colisión con jugadores
        const zonePlayers = Object.values(players || {}).filter(
            p => String(p.zone) === String(this.enemy.zone) && !p.isDead
        );
        const halfWidth = width / 2;

        for (const p of zonePlayers) {
            if (state.hitPlayers.includes(p.socketId)) continue;

            const dx = p.x - this.enemy.x;
            const dy = p.y - this.enemy.y;
            const playerDist = Math.hypot(dx, dy);

            if (playerDist <= halfWidth) {
                state.hitPlayers.push(p.socketId);

                // Aplicar daño
                let actualDmg = bulletDamage;
                if (p.shield >= actualDmg) {
                    p.shield -= actualDmg;
                } else {
                    const remainder = actualDmg - p.shield;
                    p.shield = 0;
                    p.hp -= remainder;
                }
                if (p.hp < 0) p.hp = 0;
                if (p.hp <= 0 && !p.isDead) {
                    p.isDead = true;
                }

                io.to(p.socketId).emit('environmentDamage', { damage: Math.round(bulletDamage) });
                io.to(p.socketId).emit('playerStatSync', {
                    id: p.socketId,
                    hp: Math.ceil(p.hp),
                    shield: Math.ceil(p.shield),
                    maxHp: p.maxHp,
                    maxShield: p.maxShield,
                    isDead: p.isDead,
                    isInvulnerable: !!p.isInvulnerable,
                    isInvisible: !!p.isInvisible
                });

                io.to(zoneStr).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "choque_devastador_impact",
                    targetId: p.socketId,
                    damage: Math.round(bulletDamage),
                    x: Math.round(p.x),
                    y: Math.round(p.y)
                });

                // Push opcional
                if (pushOnHit && playerDist > 0) {
                    const pushDirX = dx / playerDist;
                    const pushDirY = dy / playerDist;
                    p.x += pushDirX * pushForce;
                    p.y += pushDirY * pushForce;
                    io.to(p.socketId).emit('windPush', {
                        victimId: p.socketId,
                        dirX: pushDirX,
                        dirY: pushDirY,
                        distance: pushForce
                    });
                }

                p.lastCombatTime = Date.now();
            }
        }

        this.enemy.mechState[mId] = state;
        return true;
    }

    return false;
}

module.exports = {
    _handleExecutionLogic,
    _handleAscensionLogic,
    _handleChoqueDevastadorLogic
};
