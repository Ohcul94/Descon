// Server/behaviors/mechanics/WhipSummonMechanics.js
// Latigo Dominante - Golpea a un objetivo N veces a una cadencia dada

function _handleWhipSummonLogic(mech, mId, target, dist, angle, now, io, players) {
    if (!io) return false;
    const state = this.enemy.mechState[mId] || {
        nextShotTime: 0,
        hitsDone: 0,
        isCharging: false,
        isLocked: false,
        currentTarget: null
    };
    this.enemy.mechState[mId] = state;

    const enemyFireRange = Number(this.config?.fireRange || this.enemy?.fireRange || 800);
    const fireRange = (mech.fireRange !== undefined && Number(mech.fireRange) > 0) ? Number(mech.fireRange) : enemyFireRange;
    const cooldown = mech.cooldown !== undefined ? Number(mech.cooldown) : 12000;
    const hits = Math.max(1, parseInt(mech.hits, 10) || 3);
    const cadence = Number(mech.cadence) || 300;
    const damage = (mech.damage !== undefined ? Number(mech.damage) : 50) * (this.damageMult || 1);
    const targetCount = Math.max(1, parseInt(mech.targetCount, 10) || 1);
    const targetMode = mech.targetMode || "nearest";
    const warnTimeMs = Math.max(0, Number(mech.castTimeMs || 500));
    const radius = Number(mech.radius || 50);

    const zoneStr = `zone_${this.enemy.zone}`;

    // Generic cast gate (parallel, internal type)
    if (warnTimeMs > 0) {
        const isBusy = this._handleGenericCast(mech, mId, now, io);
        if (isBusy && this._isGenericCastType(mech.type)) {
            return true;
        }
    }

    // 1) Si está bloqueado post-ataque (cooldown entre ciclos de látigo)
    if (state.isLocked) {
        if (now < state.lockEndTime) return false;
        state.isLocked = false;
        state.hitsDone = 0;
        state.currentTarget = null;
        state.nextShotTime = now + cooldown;
        this.enemy.mechState[mId] = state;
        return false;
    }

    // 2) Gate de activación (solo cuando no está cargando)
    if (!state.isCharging) {
        if (now < (state.nextShotTime || 0)) return false;
        if (dist > fireRange) return false;
        if (!this._passesActivationGate(mech, state, now, (this.enemy.hp / this.enemy.maxHp) * 100)) return false;
    }

    // 3) Seleccionar objetivos
    const targets = this._selectTargets(players, fireRange, targetCount, targetMode, mech);
    if (targets.length === 0) {
        state.nextShotTime = now + 1000;
        this.enemy.mechState[mId] = state;
        return false;
    }

    const selectedTarget = targets[0];

    // 4) Iniciar casteo (warnTimeMs)
    if (!state.isCharging) {
        state.isCharging = true;
        state.castEndTime = now + warnTimeMs;
        state.currentTarget = selectedTarget;
        state.hitsDone = 0;

        io.to(zoneStr).emit('serverEnemyAction', {
            id: this.enemy.id,
            action: "whip_summon_start",
            mId: mId,
            castTimeMs: warnTimeMs,
            targetId: selectedTarget.socketId,
            targetX: selectedTarget.x,
            targetY: selectedTarget.y,
            hits: hits,
            cadence: cadence,
            damage: Math.round(damage),
            range: radius
        });

        io.to(zoneStr).emit('enemyCastStart', {
            id: this.enemy.id,
            mId: mId,
            type: "whip_summon",
            castTimeMs: warnTimeMs,
            x: this.enemy.x,
            y: this.enemy.y
        });

        this.enemy.mechState[mId] = state;
        return true;
    }

    // 5) Durante el casteo: esperar a que termine
    if (state.isCharging && now < state.castEndTime) {
        return true;
    }

    // 6) Cast terminado: disparar los N golpes
    state.isCharging = false;
    state.isLocked = true;
    state.lockEndTime = now + (hits * cadence);
    state.hitsDone = 0;
    state.currentTarget = selectedTarget;

    io.to(zoneStr).emit('enemyCastEnd', {
        id: this.enemy.id,
        mId: mId,
        type: "whip_summon"
    });

    // Emitir todos los golpes del látigo (server-authoritative)
    const enemyId = this.enemy.id;
    const enemyType = this.enemy.type;
    const ex = this.enemy.x;
    const ey = this.enemy.y;
    const shotAngle = Math.atan2(selectedTarget.y - ey, selectedTarget.x - ex);

    for (let i = 0; i < hits; i++) {
        io.to(zoneStr).emit('serverEnemyFire', {
            enemyId: enemyId,
            targetId: selectedTarget.socketId,
            enemyType: enemyType,
            x: ex, y: ey,
            angle: shotAngle,
            bulletSpeed: 1500,
            bulletType: "whip",
            damage: Math.round(damage),
            hitIndex: i,
            totalHits: hits,
            targetX: selectedTarget.x,
            targetY: selectedTarget.y,
            range: 300
        });
    }

    // Aplicar daño server-authoritative a todos los targets
    const allTargets = Array.isArray(targets) ? targets : [targets];
    allTargets.forEach(t => {
        if (t && !t.isDead && !t.isInvisible) {
            if (t.shield >= damage) {
                t.shield -= damage;
            } else {
                t.hp -= (damage - t.shield);
                t.shield = 0;
            }
            if (t.hp < 0) t.hp = 0;
            if (t.hp <= 0 && !t.isDead) {
                t.isDead = true;
            }
            t.lastCombatTime = Date.now();
            io.to(t.socketId).emit('environmentDamage', { damage: Math.round(damage) });
            io.to(t.socketId).emit('playerStatSync', {
                id: t.socketId,
                hp: Math.ceil(t.hp),
                shield: Math.ceil(t.shield),
                isDead: t.isDead
            });
        }
    });

    this.enemy.mechState[mId] = state;
    return true;
}

module.exports = {
    _handleWhipSummonLogic
};
