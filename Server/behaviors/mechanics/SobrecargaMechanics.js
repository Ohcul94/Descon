// Server/behaviors/mechanics/SobrecargaMechanics.js
// Mecánica Defensiva - Sobrecarga
// El enemigo acumula energía verde (casteo) y al completarse detona una explosión
// verde que CURA (a sí mismo y opcionalmente a aliados en rango) y, si damageEnabled,
// daña a los jugadores dentro de explosionRadius.
// Manejo autoritativo de startDelay, activationMode ("time" u "hp"), castTimeMs,
// interrupción por CC, cooldown y salida de combate.

function _handleSobrecargaLogic(mech, mId, now, io, grid, players) {
    if (!io) return false;
    if (!this.enemy.mechState) this.enemy.mechState = {};

    let state = this.enemy.mechState[mId];
    if (!state) {
        state = {
            isCharging: false,
            chargeEndTime: 0,
            nextReadyTime: 0,
            triggeredHPs: {},
            combatStartTime: null
        };
        this.enemy.mechState[mId] = state;
    }

    const zoneStr = `zone_${this.enemy.zone}`;
    const startDelay = Number(mech.startDelay || 0);
    const cooldown = Number(mech.cooldown !== undefined ? mech.cooldown : 15000);
    const castMs = Math.max(0, Number(mech.castTimeMs || 0));
    const castInterruptible = mech.castInterruptible !== false;
    const healMode = mech.healMode === 'percent' ? 'percent' : 'flat';
    const healAmountValue = Number(mech.healAmount !== undefined ? mech.healAmount : 500);
    const healAlliesEnabled = mech.healAlliesEnabled === true;
    const healRange = Number(mech.healRange !== undefined ? mech.healRange : 300);
    const affectsEnemies = !!mech.affectsEnemies;
    const affectsBosses = !!mech.affectsBosses;
    const damageEnabled = mech.damageEnabled === true;
    const explosionRadius = Number(mech.explosionRadius !== undefined ? mech.explosionRadius : 250);
    const explosionDamage = Number(mech.damage !== undefined ? mech.damage : 100) * (this.damageMult || 1);

    const cancelCharge = (applyCooldown) => {
        if (state.isCharging) {
            io.to(zoneStr).emit('enemyCastCancel', { id: this.enemy.id, mId: mId, type: 'sobrecarga' });
            io.to(zoneStr).emit('serverEnemyAction', {
                id: this.enemy.id,
                mId: mId,
                action: 'sobrecarga_cancel',
                type: 'sobrecarga',
                silent: true
            });
        }
        state.isCharging = false;
        state.chargeEndTime = 0;
        if (applyCooldown) state.nextReadyTime = now + cooldown;
    };

    // --- Fuera de combate: limpiar carga y estado transitorio -----------------
    if (!this._inCombat) {
        cancelCharge(false);
        state.combatStartTime = null;
        state.triggeredHPs = {};
        state.nextReadyTime = 0;
        return false;
    }

    // --- Primer tick en combate: arrancar el retardo de inicio ----------------
    if (!state.combatStartTime) {
        state.combatStartTime = now;
        if (mech.activationMode === 'time' || mech.activationMode === undefined) {
            state.nextReadyTime = now + startDelay;
        }
    }

    // --- Interrupción por CC (Control de Masas) -------------------------------
    if (castInterruptible && state.isCharging) {
        if (this.enemy.isStunned || this.enemy.isFeared || this.enemy.isPolymorphed || this.enemy.isAsleep) {
            cancelCharge(true);
            return false;
        }
    }

    const computeHeal = (target) => {
        if (healMode === 'percent') {
            const maxHp = Number(target.maxHp || this.enemy.maxHp || 0);
            return Math.max(0, maxHp * (healAmountValue / 100));
        }
        return Math.max(0, healAmountValue);
    };

    const applyHealToEnemy = (e) => {
        if (!e || e.hp <= 0) return 0;
        const oldHp = e.hp;
        e.hp = Math.min(e.maxHp, e.hp + computeHeal(e));
        const amount = Math.max(0, e.hp - oldHp);
        if (amount > 0) {
            io.to(zoneStr).emit('enemyHealed', {
                id: e.id,
                hp: e.hp,
                amount: amount
            });
        }
        return amount;
    };

    const resolveBurst = (wasCasting) => {
        state.isCharging = false;
        state.chargeEndTime = 0;
        state.nextReadyTime = now + cooldown;

        // 1) Barra de casteo: terminar antes de mostrar la detonación
        if (wasCasting) {
            io.to(zoneStr).emit('enemyCastEnd', { id: this.enemy.id, mId: mId, type: 'sobrecarga' });
        }

        // 2) CURACIÓN: el dueño siempre se cura a sí mismo
        const healed = applyHealToEnemy(this.enemy);

        // 3) CURACIÓN opcional a aliados cercanos
        if (healAlliesEnabled && healRange > 0 && grid && typeof grid.getNearbyEntities === 'function') {
            const { enemies: nearbyEnemies } = grid.getNearbyEntities(this.enemy.x, this.enemy.y, this.enemy.zone);
            (nearbyEnemies || []).forEach(e => {
                if (!e || e.id === this.enemy.id) return;
                if (String(e.zone) !== String(this.enemy.zone) || e.hp <= 0) return;
                const d = Math.hypot(e.x - this.enemy.x, e.y - this.enemy.y);
                if (d > healRange) return;
                const isBoss = Number(e.type) >= 101;
                if ((isBoss && affectsBosses) || (!isBoss && affectsEnemies)) {
                    applyHealToEnemy(e);
                }
            });
        }

        // 4) DAÑO opcional de la explosión a jugadores cercanos
        let damagedPlayers = 0;
        if (damageEnabled && explosionRadius > 0) {
            const lobbyZoneId = Number(this.state?.SERVER_CONFIG?.pilotConfig?.startingMapId || 1);
            const { players: nearbyPlayers } = grid && typeof grid.getNearbyEntities === 'function'
                ? grid.getNearbyEntities(this.enemy.x, this.enemy.y, this.enemy.zone)
                : { players: Object.values(players || {}) };
            (nearbyPlayers || []).forEach(p => {
                if (!p || p.isDead) return;
                if (String(p.zone) !== String(this.enemy.zone)) return;
                if (Number(p.zone) === lobbyZoneId) return;
                if (p.isInvulnerable || p.inStrangeDimension || p.isInvisible) return;
                const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                if (d > explosionRadius) return;

                const dmg = Math.round(explosionDamage);
                if (dmg <= 0) return;
                p.lastCombatTime = Date.now();
                if (p.shield >= dmg) {
                    p.shield -= dmg;
                } else {
                    p.hp -= (dmg - p.shield);
                    p.shield = 0;
                }
                if (p.hp < 0) p.hp = 0;
                if (p.hp <= 0) this._killPlayer(p, io);
                damagedPlayers++;

                io.to(p.socketId).emit('environmentDamage', { damage: dmg, source: 'sobrecarga' });
                io.to(zoneStr).emit('playerStatSync', {
                    id: p.socketId,
                    hp: Math.ceil(p.hp),
                    shield: Math.ceil(p.shield),
                    isDead: p.isDead,
                    isInvulnerable: p.isInvulnerable,
                    isInvisible: p.isInvisible,
                    spheres: p.spheres || []
                });
            });
        }

        // 5) VFX de detonación verde en el cliente (sonido de la mecánica)
        io.to(zoneStr).emit('serverEnemyAction', {
            id: this.enemy.id,
            mId: mId,
            action: 'sobrecarga_burst',
            type: 'sobrecarga',
            x: this.enemy.x,
            y: this.enemy.y,
            heal: Math.round(healed),
            healMode: healMode,
            radius: explosionRadius,
            damageEnabled: damageEnabled,
            damagedPlayers: damagedPlayers
        });

        return true;
    };

    // --- Carga en curso -------------------------------------------------------
    if (state.isCharging) {
        if (now < state.chargeEndTime) return true; // ocupado cargando
        return resolveBurst(true);
    }

    // --- Carga interrumpida externamente (burrow/_interruptActiveMechanics) ---
    if (state.chargeEndTime > 0) {
        state.chargeEndTime = 0;
        state.nextReadyTime = now + cooldown;
        io.to(zoneStr).emit('serverEnemyAction', {
            id: this.enemy.id,
            mId: mId,
            action: 'sobrecarga_cancel',
            type: 'sobrecarga',
            silent: true
        });
        return false;
    }

    // --- Gate de activación (startDelay + modo time/hp + cooldown) ------------
    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
    if (!this._passesActivationGate(mech, state, now, hpPercent)) return false;
    if (now < (state.nextReadyTime || 0)) return false;

    // --- Iniciar la carga -----------------------------------------------------
    if (castMs > 0) {
        state.isCharging = true;
        state.chargeEndTime = now + castMs;

        // enemyCastStart -> barra de casteo del cliente
        io.to(zoneStr).emit('enemyCastStart', {
            id: this.enemy.id,
            mId: mId,
            type: 'sobrecarga',
            castTimeMs: castMs,
            x: this.enemy.x,
            y: this.enemy.y
        });
        // serverEnemyAction -> VFX de energía verde acumulándose (sin sonido)
        io.to(zoneStr).emit('serverEnemyAction', {
            id: this.enemy.id,
            mId: mId,
            action: 'sobrecarga_charge',
            type: 'sobrecarga',
            castMs: castMs,
            silent: true
        });
        return true;
    }

    // Sin tiempo de casteo: detonar al instante
    return resolveBurst(false);
}

module.exports = {
    _handleSobrecargaLogic
};
