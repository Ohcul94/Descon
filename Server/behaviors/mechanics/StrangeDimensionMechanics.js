// Server/behaviors/mechanics/StrangeDimensionMechanics.js
// v902.0: Mecánica Defensiva/Mística - Dimensión Extraña (Strange Dimension)
// IMPORTANTE: Emite 'serverEnemyAction' (no 'enemy_action') para que el cliente Godot lo reciba
// a través de NetworkManager.enemy_action signal (mapeado desde serverEnemyAction).

module.exports = {
    _handleStrangeDimensionLogic: function(mech, mId, target, dist, now, io, players) {
        if (!this.enemy.strangeDimensionState) {
            this.enemy.strangeDimensionState = {};
        }
        let state = this.enemy.strangeDimensionState[mId];
        if (!state) {
            state = {
                isCharging: false,
                isActive: false,
                chargeEndTime: 0,
                activeEndTime: 0,
                nextShotTime: 0,
                capturedTargets: []
            };
            this.enemy.strangeDimensionState[mId] = state;
        }

        const cd = Number(mech.cooldown || 25000);
        const castMs = Number(mech.castTimeMs || 1200);
        const durationMs = Number(mech.duration || 5.0) * 1000.0;
        const fireRange = Number(mech.fireRange || this.enemy.fireRange || 1000);
        const targetCount = Math.max(1, Number(mech.targetCount || 1));
        const targetMode = mech.targetMode || "highest_threat";
        const castInterruptible = mech.castInterruptible === true || mech.castInterruptible === 'true';
        const roomName = `zone_${this.enemy.zoneId || this.enemy.zone || 0}`;

        // Chequeo de interrupción por CC (Control de Masas)
        if (castInterruptible && (state.isCharging || state.isActive)) {
            if (this.enemy.isStunned || this.enemy.isFeared || this.enemy.isPolymorphed) {
                state.isCharging = false;
                state.isActive = false;
                state.nextShotTime = now + cd;
                if (io) {
                    io.to(roomName).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        mId: mId,
                        action: 'strange_dimension_expire',
                        type: 'strange_dimension',
                        interrupted: true,
                        silent: false
                    });
                }
                return false;
            }
        }

        // 1. Durante la carga / casteo
        if (state.isCharging) {
            if (now >= state.chargeEndTime) {
                state.isCharging = false;
                state.isActive = true;
                state.activeEndTime = now + durationMs;
                state.nextShotTime = state.activeEndTime + cd;

                // Seleccionar los objetivos capturados que entrarán en la dimensión extraña
                const targets = this._selectTargets(players, fireRange, targetCount, targetMode, mech);
                state.capturedTargets = targets.map(p => p.socketId);

                // Ocurre en el mismo lugar — no hay teletransporte, el efecto es local
                if (io) {
                    io.to(roomName).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        mId: mId,
                        action: 'strange_dimension_start',
                        type: 'strange_dimension',
                        duration: durationMs / 1000.0,
                        targetIds: state.capturedTargets,
                        x: this.enemy.x,
                        y: this.enemy.y,
                        silent: false
                    });
                }
            }
            return true; // Ocupado
        }

        // 2. Mientras la dimensión está activa
        if (state.isActive) {
            if (now >= state.activeEndTime) {
                state.isActive = false;

                if (io) {
                    io.to(roomName).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        mId: mId,
                        action: 'strange_dimension_expire',
                        type: 'strange_dimension',
                        silent: false
                    });
                }
            }
            return true; // Sigue activa
        }

        // 3. Inicio de la mecánica si no está en cooldown
        if (now >= state.nextShotTime) {
            const startDelay = Number(mech.startDelay || 0);
            if (!state.delayEndTime) {
                state.delayEndTime = now + startDelay;
                return true;
            }
            if (now < state.delayEndTime) return true;

            state.delayEndTime = 0;
            state.isCharging = true;
            state.chargeEndTime = now + castMs;

            if (io) {
                io.to(roomName).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    mId: mId,
                    action: 'strange_dimension_charge',
                    type: 'strange_dimension',
                    castMs: castMs,
                    silent: true
                });
            }
            return true;
        }

        return false;
    }
};
