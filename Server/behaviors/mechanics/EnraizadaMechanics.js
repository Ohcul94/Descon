// Server/behaviors/mechanics/EnraizadaMechanics.js
// v902.0: ENRAIZADA - raíces que brotan del piso y abrazan a la(s) nave(s).
//
// Efecto: INMOVILIZA al objetivo (root) durante mech.rootDuration ms.
//   - El root NO rompe casteos en curso ni bloquea skills (decisión de diseño).
//   - Daño único opcional al atrapar (mech.trapDamage).
//   - Daño por tick opcional mientras dura el root (mech.rootDps + mech.rootTickInterval).
//
// Unidades normalizadas del proyecto:
//   rootDuration / rootTickInterval / cooldown / castTimeMs / startDelay -> ms
//   trapRadius / fireRange                                               -> px
//   trapDamage / rootDps                                                 -> pts
//   targetCount                                                          -> uds

function _handleEnraizadaLogic(mech, mId, target, dist, angle, now, io, players) {
    if (!io) return false;
    const state = this.enemy.mechState[mId] || {
        nextShotTime: 0,
        isCharging: false,
        isLocked: false,
        targets: []
    };
    this.enemy.mechState[mId] = state;

    const enemyFireRange = Number(this.config?.fireRange || this.enemy?.fireRange || 800);
    const fireRange = (mech.fireRange !== undefined && Number(mech.fireRange) > 0) ? Number(mech.fireRange) : enemyFireRange;
    const trapRadius = Math.max(1, Number(mech.trapRadius) || 140);
    const rootDuration = Math.max(200, Number(mech.rootDuration) || 4000);
    const trapDamage = Math.max(0, Number(mech.trapDamage) || 0);
    const rootDps = Math.max(0, Number(mech.rootDps) || 0);
    const rootTickInterval = Math.max(100, Number(mech.rootTickInterval) || 1000);
    const cooldown = mech.cooldown !== undefined ? Number(mech.cooldown) : 10000;
    const targetCount = Math.max(1, parseInt(mech.targetCount, 10) || 1);
    const targetMode = mech.targetMode || "highest_threat";
    const warnTimeMs = Math.max(0, Number(mech.castTimeMs || 0));

    const zoneStr = `zone_${this.enemy.zone}`;

    // 1) Cooldown post-ataque
    if (state.isLocked) {
        if (now < state.lockEndTime) return false;
        state.isLocked = false;
        state.targets = [];
        state.nextShotTime = now + cooldown;
        this.enemy.mechState[mId] = state;
        return false;
    }

    // 2) Gate de activación (solo cuando no está casteando)
    if (!state.isCharging) {
        if (now < (state.nextShotTime || 0)) return false;
        if (dist > fireRange) return false;
        if (!this._passesActivationGate(mech, state, now, (this.enemy.hp / this.enemy.maxHp) * 100)) return false;
    }

    // 3) Seleccionar objetivos
    const targets = this._selectTargets(players, fireRange, targetCount, targetMode, mech);
    if (targets.length === 0 && !state.isCharging) {
        state.nextShotTime = now + 1000;
        this.enemy.mechState[mId] = state;
        return false;
    }

    // 4) Iniciar casteo (aviso visual previo a las raíces)
    if (!state.isCharging) {
        state.isCharging = true;
        state.castEndTime = now + warnTimeMs;
        state.targets = targets.map(t => t.socketId);

        io.to(zoneStr).emit('serverEnemyAction', {
            id: this.enemy.id,
            action: "enraizada_start",
            mId: mId,
            castTimeMs: warnTimeMs,
            radius: trapRadius,
            x: this.enemy.x,
            y: this.enemy.y,
            targets: targets.map(t => ({ id: t.socketId, x: t.x, y: t.y }))
        });

        if (warnTimeMs > 0) {
            io.to(zoneStr).emit('enemyCastStart', {
                id: this.enemy.id,
                mId: mId,
                type: "enraizada",
                castTimeMs: warnTimeMs,
                x: this.enemy.x,
                y: this.enemy.y
            });
        }

        this.enemy.mechState[mId] = state;
        return true;
    }

    // 5) Durante el casteo: esperar a que termine el aviso
    if (state.isCharging && now < state.castEndTime) {
        return true;
    }

    // 6) Fin del casteo -> BROTES: aplicar root (+ daños) a los objetivos
    if (state.isCharging && now >= state.castEndTime) {
        state.isCharging = false;
        state.isLocked = true;
        state.lockEndTime = now + cooldown;
        state.nextShotTime = now + cooldown;

        if (warnTimeMs > 0) {
            io.to(zoneStr).emit('enemyCastEnd', {
                id: this.enemy.id,
                mId: mId,
                type: "enraizada"
            });
        }

        const snapTargets = (state.targets && state.targets.length)
            ? state.targets.map(id => players[id]).filter(Boolean)
            : targets;

        const trapped = [];
        snapTargets.forEach(t => {
            if (!t || t.isDead || t.isInvisible || t.inStrangeDimension || t.isInvulnerable) return;
            if (!players[t.socketId]) return;

            // Raíz (solo bloquea movimiento)
            t.isRooted = true;
            t.rootEndTime = now + rootDuration;
            t.rootDps = rootDps;
            t.rootInterval = rootTickInterval;
            t.lastRootTick = now;
            io.to(t.socketId).emit('rootState', { active: true, duration: rootDuration });
            io.to(t.socketId).emit('statusEffectsSync', { root: rootDuration });
            io.to(t.socketId).emit('gameNotification', {
                msg: `🌱 ¡Raíces del suelo te atraparon! Enraizado ${Math.round(rootDuration / 1000)}s.`,
                type: "error"
            });

            // Daño único al atrapar (opcional)
            let finalDamage = 0;
            if (trapDamage > 0) {
                t.lastCombatTime = now;
                if (t.shield >= trapDamage) {
                    t.shield -= trapDamage;
                } else {
                    t.hp -= (trapDamage - t.shield);
                    t.shield = 0;
                }
                if (t.hp < 0) t.hp = 0;
                if (t.hp <= 0 && !t.isDead) {
                    t.isDead = true;
                }
                finalDamage = trapDamage;
                io.to(t.socketId).emit('environmentDamage', { damage: trapDamage });
                io.to(t.socketId).emit('playerStatSync', {
                    id: t.socketId,
                    hp: Math.ceil(t.hp),
                    shield: Math.ceil(t.shield),
                    isDead: t.isDead
                });
            }

            trapped.push({ id: t.socketId, x: t.x, y: t.y, damage: finalDamage, dead: !!t.isDead });
        });

        // VFX: brotes de raíces en cada posición atrapada
        io.to(zoneStr).emit('serverEnemyAction', {
            id: this.enemy.id,
            action: "enraizada_end",
            mId: mId,
            radius: trapRadius,
            duration: rootDuration,
            x: this.enemy.x,
            y: this.enemy.y,
            trapped: trapped
        });

        this.enemy.mechState[mId] = state;
        return true;
    }

    return false;
}

module.exports = {
    _handleEnraizadaLogic
};
