// Server/behaviors/mechanics/WhipSummonMechanics.js
// Látigo Dominante - Golpea a un objetivo N veces a una cadencia dada

function _handleWhipSummonLogic(mech, mId, target, dist, angle, now, io, players) {
    if (!io) return false;
    const state = this.enemy.mechState[mId] || {
        nextShotTime: 0,
        hitsDone: 0,
        isCharging: false,
        isStriking: false,
        isLocked: false,
        currentTarget: null,
        nextHitTime: 0
    };
    this.enemy.mechState[mId] = state;

    const enemyFireRange = Number(this.config?.fireRange || this.enemy?.fireRange || 800);
    const fireRange = (mech.fireRange !== undefined && Number(mech.fireRange) > 0) ? Number(mech.fireRange) : enemyFireRange;
    const cooldown = mech.cooldown !== undefined ? Number(mech.cooldown) : 12000;
    const hits = Math.max(1, parseInt(mech.hits, 10) || 3);
    const cadence = Math.max(100, Number(mech.cadence) || 300);
    const damage = (mech.damage !== undefined ? Number(mech.damage) : 50) * (this.damageMult || 1);
    const targetCount = Math.max(1, parseInt(mech.targetCount, 10) || 1);
    const targetMode = mech.targetMode || "highest_threat";
    const warnTimeMs = Math.max(0, Number(mech.castTimeMs || 500));

    const zoneStr = `zone_${this.enemy.zone}`;

    // 1) Cooldown post-ataque
    if (state.isLocked) {
        if (now < state.lockEndTime) return false;
        state.isLocked = false;
        state.isStriking = false;
        state.hitsDone = 0;
        state.currentTarget = null;
        state.nextShotTime = now + cooldown;
        this.enemy.mechState[mId] = state;
        return false;
    }

    // 2) Gate de activación (cuando no está cargando ni realizando la serie de golpes)
    if (!state.isCharging && !state.isStriking) {
        if (now < (state.nextShotTime || 0)) return false;
        if (dist > fireRange) return false;
        if (!this._passesActivationGate(mech, state, now, (this.enemy.hp / this.enemy.maxHp) * 100)) return false;
    }

    // 3) Seleccionar objetivos
    const targets = this._selectTargets(players, fireRange, targetCount, targetMode, mech);
    if (targets.length === 0 && !state.isStriking) {
        state.nextShotTime = now + 1000;
        this.enemy.mechState[mId] = state;
        return false;
    }

    const selectedTarget = (targets.length > 0) ? targets[0] : state.currentTarget;
    if (!selectedTarget) return false;

    // 4) Iniciar casteo (warnTimeMs)
    if (!state.isCharging && !state.isStriking) {
        state.isCharging = true;
        state.castEndTime = now + warnTimeMs;
        state.currentTarget = selectedTarget;
        state.hitsDone = 0;

        const totalCastTimeMs = warnTimeMs + (hits * cadence);

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
            range: fireRange
        });

        io.to(zoneStr).emit('enemyCastStart', {
            id: this.enemy.id,
            mId: mId,
            type: "whip_summon",
            castTimeMs: totalCastTimeMs,
            x: this.enemy.x,
            y: this.enemy.y
        });

        this.enemy.mechState[mId] = state;
        return true;
    }

    // 5) Durante el casteo: esperar a que termine el tiempo de advertencia
    if (state.isCharging && now < state.castEndTime) {
        return true;
    }

    // 6) Transición de casteo a ráfaga de golpes
    if (state.isCharging && now >= state.castEndTime) {
        state.isCharging = false;
        state.isStriking = true;
        state.hitsDone = 0;
        state.nextHitTime = now;
    }

    // 7) Ejecutar golpes sucesivos a la cadencia correspondiente
    if (state.isStriking) {
        if (now >= state.nextHitTime && state.hitsDone < hits) {
            const curTarget = (targets.length > 0) ? targets[0] : state.currentTarget;
            if (!curTarget || curTarget.isDead || (curTarget.socketId && !players[curTarget.socketId])) {
                state.isStriking = false;
                state.isLocked = true;
                state.lockEndTime = now + cooldown;
                state.nextShotTime = now + cooldown;
                io.to(zoneStr).emit('enemyCastEnd', {
                    id: this.enemy.id,
                    mId: mId,
                    type: "whip_summon"
                });
                this.enemy.mechState[mId] = state;
                return false;
            }

            state.hitsDone++;
            state.nextHitTime = now + cadence;

            const targetX = curTarget ? curTarget.x : this.enemy.x;
            const targetY = curTarget ? curTarget.y : this.enemy.y;
            const targetId = curTarget ? curTarget.socketId : null;

            // Emitir evento visual de golpe
            io.to(zoneStr).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "whip_summon_hit",
                mId: mId,
                hitIndex: state.hitsDone - 1,
                totalHits: hits,
                targetId: targetId,
                targetX: targetX,
                targetY: targetY,
                x: this.enemy.x,
                y: this.enemy.y,
                damage: Math.round(damage)
            });

            // Aplicar daño server-authoritative
            const allTargets = (targets.length > 0) ? targets : (state.currentTarget ? [state.currentTarget] : []);
            allTargets.forEach(t => {
                if (t && !t.isDead && !t.isInvisible && !t.inStrangeDimension && !t.isInvulnerable) {
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

            // Si se completaron todos los golpes, finalizar ataque
            if (state.hitsDone >= hits) {
                state.isStriking = false;
                state.isLocked = true;
                state.lockEndTime = now + cooldown;
                state.nextShotTime = now + cooldown;

                io.to(zoneStr).emit('enemyCastEnd', {
                    id: this.enemy.id,
                    mId: mId,
                    type: "whip_summon"
                });
            }
        }
        this.enemy.mechState[mId] = state;
        return true;
    }

    return false;
}

module.exports = {
    _handleWhipSummonLogic
};
