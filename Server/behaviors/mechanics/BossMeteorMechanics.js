// Server/behaviors/mechanics/BossMeteorMechanics.js
// v411: Mecánica modular de lluvia de meteoritos y debuffs configurables

const altarDefenseManager = require('../../systems/altarDefenseManager');

function _applyMeteorDebuffs(p, mech, io) {
    if (!mech.debuffsList || !Array.isArray(mech.debuffsList)) return;
    mech.debuffsList.forEach(d => {
        if (d.type === 'bleed') {
            p.isBleeding = true;
            p.bleedEndTime = Date.now() + (Number(d.duration) || 4000);
            p.bleedDps = Number(d.dps) || 30;
            p.bleedInterval = Number(d.tickInterval) || 1000;
            p.lastBleedTick = Date.now();
            io.to(p.socketId).emit('gameNotification', { msg: `🩸 ¡El meteorito te hizo sangrar!`, type: "warning" });
        }
        else if (d.type === 'poison') {
            p.isPoisoned = true;
            p.poisonEndTime = Date.now() + (Number(d.duration) || 4000);
            p.poisonDps = Number(d.dps) || 20;
            p.poisonInterval = Number(d.tickInterval) || 1000;
            p.lastPoisonTick = Date.now();
            io.to(p.socketId).emit('gameNotification', { msg: `🤢 ¡El meteorito te envenenó!`, type: "warning" });
        }
        else if (d.type === 'stun') {
            const stunDur = Number(d.duration) || 1500;
            p.isStunned = true;
            p.stunEndTime = Date.now() + stunDur;
            io.to(p.socketId).emit('stunState', { active: true, duration: stunDur });
        }
        else if (d.type === 'slow') {
            const slowAmt = Number(d.amount) || 50;
            const slowDur = Number(d.duration) || 2500;
            const isPct = d.isPercentage !== false;
            p.isSlowed = true;
            p.slowEndTime = Date.now() + slowDur;
            p.slowPoints = slowAmt;
            p.slowIsPercentage = isPct;
            p.lastSlowTime = Date.now();
            io.to(p.socketId).emit('slowState', { active: true, amount: slowAmt, isPercentage: isPct, duration: slowDur });
        }
    });
}

function _handleMeteorLogic(mech, mId, target, dist, angle, now, io, players) {
    if (!io) return false;
    const state = this.enemy.mechState[mId] || { nextShotTime: 0, triggeredHPs: {}, meteorList: [] };
    const fireRange = mech.fireRange || 800;

    // Generic cast gate (per mechanic, default 0 = instant)
    if (mech.castTimeMs !== undefined && Number(mech.castTimeMs) > 0) {
        const isBusy = this._handleGenericCast(mech, mId, now, io);
        if (isBusy && this._isGenericCastType(mech.type)) {
            return true;
        }
    }
    const meteorCount = Math.max(1, parseInt(mech.meteorCount, 10) || 3);
    const warnTimeMs = mech.warnTimeMs || 1200;
    const fallHeight = mech.fallHeight || 800;
    const fallSpeed = mech.fallSpeed || 600;
    const meteorSize = mech.meteorSize || 60;
    const explosionRadius = mech.explosionRadius || 150;
    const bulletDamage = (mech.bulletDamage || 200) * (this.damageMult || 1);
    const targetMode = mech.targetMode || "proximity";
    const cooldown = mech.cooldown || 10000;
    const fallTimeMs = (fallHeight / Math.max(1, fallSpeed)) * 1000;
    const persistentZone = !!mech.persistentZone;
    const zoneDamage = (mech.zoneDamage || 0) * (this.damageMult || 1);
    const zoneTickMs = mech.zoneTickMs || 1000;
    const zoneDuration = mech.zoneDuration || 4000;

    if (!state.meteorList) state.meteorList = [];

    const zonePlayers = () => Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);

    // 1. Procesar meteoritos activos (impacto)
    for (let i = state.meteorList.length - 1; i >= 0; i--) {
        const mt = state.meteorList[i];
        if (now >= mt.landTime) {
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "meteor_impact",
                x: mt.x,
                y: mt.y,
                radius: explosionRadius,
                meteorSize: meteorSize,
                damage: bulletDamage,
                mId: mId + "_" + mt.id
            });

            // Aplicar daño a jugadores dentro del radio de impacto
            zonePlayers().forEach(p => {
                const d = Math.hypot(p.x - mt.x, p.y - mt.y);
                if (d > explosionRadius) return;
                p.lastCombatTime = Date.now();
                if (p.shield >= bulletDamage) {
                    p.shield -= bulletDamage;
                } else {
                    p.hp -= (bulletDamage - p.shield);
                    p.shield = 0;
                }
                if (p.hp < 0) p.hp = 0;
                if (p.hp <= 0) this._killPlayer(p, io);

                // v400.30: Reflejo autoritativo
                if (p.reflectActive && !p.isInvulnerable) {
                    const reflectedDmg = Math.round(bulletDamage * 0.8);
                    if (reflectedDmg > 0) {
                        if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                        else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                        if (this.enemy.hp < 0) this.enemy.hp = 0;
                        io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', {
                            id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield
                        });
                    }
                }

                io.to(p.socketId).emit('environmentDamage', { damage: bulletDamage });
                this._applyMeteorDebuffs(p, mech, io);
                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: p.socketId,
                    hp: Math.ceil(p.hp),
                    shield: Math.ceil(p.shield),
                    isDead: p.isDead
                });
            });

            // Daño al Altar si el meteorito impacta dentro del radio de explosión
            const altarState = this.state.altarState;
            if (altarState && altarState.hp > 0 && String(altarState.zone) === String(this.enemy.zone)) {
                const altarX = Number(altarState.x) || 5000;
                const altarY = Number(altarState.y) || 5000;
                const dAltar = Math.hypot(altarX - mt.x, altarY - mt.y);
                if (dAltar <= explosionRadius) {
                    altarDefenseManager.applyDamageToAltar(bulletDamage, this.enemy.zone);
                }
            }

            state.meteorList.splice(i, 1);

            // Crear zona persistente si está habilitada
            if (persistentZone && zoneDuration > 0) {
                if (!state.activeZones) state.activeZones = [];
                const zoneId = mId + "_z_" + mt.id;
                state.activeZones.push({
                    id: zoneId, x: mt.x, y: mt.y,
                    endTime: now + zoneDuration,
                    lastTick: now
                });
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "meteor_zone_start",
                    x: mt.x, y: mt.y,
                    radius: explosionRadius,
                    zoneDamage: zoneDamage,
                    zoneDuration: zoneDuration,
                    zoneTickMs: zoneTickMs,
                    mId: zoneId
                });
            }
        }
    }

    // Procesar zonas activas (daño por tick + expiración)
    if (state.activeZones && state.activeZones.length > 0) {
        for (let i = state.activeZones.length - 1; i >= 0; i--) {
            const z = state.activeZones[i];
            if (now >= z.endTime) {
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "meteor_zone_end",
                    mId: z.id
                });
                state.activeZones.splice(i, 1);
            } else if (now - z.lastTick >= zoneTickMs) {
                z.lastTick = now;
                zonePlayers().forEach(p => {
                    const d = Math.hypot(p.x - z.x, p.y - z.y);
                    if (d > explosionRadius) return;
                    p.lastCombatTime = Date.now();
                    if (p.shield >= zoneDamage) {
                        p.shield -= zoneDamage;
                    } else {
                        p.hp -= (zoneDamage - p.shield);
                        p.shield = 0;
                    }
                    if (p.hp < 0) p.hp = 0;
                    if (p.hp <= 0) this._killPlayer(p, io);
                    if (p.reflectActive && !p.isInvulnerable) {
                        const reflectedDmg = Math.round(zoneDamage * 0.8);
                        if (reflectedDmg > 0) {
                            if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                            else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                            if (this.enemy.hp < 0) this.enemy.hp = 0;
                            io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', {
                                id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield
                            });
                        }
                    }
                    io.to(p.socketId).emit('environmentDamage', { damage: zoneDamage });
                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: p.socketId, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield), isDead: p.isDead
                    });
                });
            }
        }
    }

    // 2. Gate de activación (startDelay + modo HP o tiempo)
    if (state.nextShotTime === undefined || state.nextShotTime === 0) {
        state.nextShotTime = now + (mech.startDelay || 0);
    }
    if (mech.activationMode !== "time") {
        const hpPercent = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;
        const thresholds = Array.isArray(mech.activationHPs) && mech.activationHPs.length > 0
            ? mech.activationHPs.map(Number).filter(v => !isNaN(v))
            : [70];
        if (!state.triggeredHPs) state.triggeredHPs = {};
        for (const hpVal of thresholds) {
            if (hpPercent > hpVal && state.triggeredHPs[hpVal]) {
                state.triggeredHPs[hpVal] = false;
            }
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
        if (!shouldActivate) {
            this.enemy.mechState[mId] = state;
            return state.meteorList.length > 0;
        }
    }

    // 3. Iniciar la lluvia de meteoritos
    if (target && dist <= fireRange && now > state.nextShotTime) {
        const targets = this._selectMeteorTargets(players, fireRange, meteorCount, targetMode, mech);
        if (targets.length > 0) {
            const landTime = now + warnTimeMs + fallTimeMs;
            const targetsPayload = targets.map(t => ({ x: Math.round(t.x), y: Math.round(t.y), targetId: t.socketId }));

            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "meteor_summon",
                x: this.enemy.x,
                y: this.enemy.y,
                targets: targetsPayload,
                warnTimeMs: warnTimeMs,
                fallHeight: fallHeight,
                fallSpeed: fallSpeed,
                meteorSize: meteorSize,
                radius: explosionRadius,
                damage: bulletDamage,
                targetMode: targetMode,
                mId: mId
            });

            targets.forEach(t => {
                state.meteorList.push({
                    id: Date.now() + "_" + Math.floor(Math.random() * 1000),
                    x: Math.round(t.x),
                    y: Math.round(t.y),
                    landTime: landTime
                });
            });

            state.nextShotTime = now + (mech.activationMode === "time" ? (mech.activationIntervalMs || cooldown) : cooldown);
        }
    }

    this.enemy.mechState[mId] = state;
    return state.meteorList.length > 0;
}

module.exports = {
    _handleMeteorLogic,
    _applyMeteorDebuffs
};
