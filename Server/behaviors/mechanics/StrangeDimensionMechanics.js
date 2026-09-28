// Server/behaviors/mechanics/StrangeDimensionMechanics.js
// v904.0: Mecánica Defensiva/Mística - Dimensión Extraña (Strange Dimension)
// Manejo autoritativo de startDelay, activationMode ("time" u "hp"), castMs, duration y cooldown.

module.exports = {
    _handleStrangeDimensionLogic: function(mech, mId, target, dist, now, io, players) {
        if (!this.enemy.strangeDimensionState) {
            this.enemy.strangeDimensionState = {};
        }
        let state = this.enemy.strangeDimensionState[mId];

        const startDelay = Number(mech.startDelay || 0);
        const cd = Number(mech.cooldown !== undefined ? mech.cooldown : 25000);
        const castMs = Number(mech.castTimeMs !== undefined ? mech.castTimeMs : 1000);
        const rawDur = Number(mech.duration !== undefined ? mech.duration : 5000);
        const durationMs = rawDur < 100 ? (rawDur * 1000.0) : rawDur;
        const enemyFireRange = Number(this.config?.fireRange || this.enemy?.fireRange || 1500);
        const fireRange = (mech.fireRange !== undefined && Number(mech.fireRange) > 0) ? Number(mech.fireRange) : enemyFireRange;
        const targetCount = Math.max(1, Number(mech.targetCount || 1));
        const targetMode = mech.targetMode || "highest_threat";
        const castInterruptible = mech.castInterruptible === true || mech.castInterruptible === 'true';
        const roomName = `zone_${this.enemy.zoneId || this.enemy.zone || 1}`;

        if (!state) {
            state = {
                isCharging: false,
                isActive: false,
                chargeEndTime: 0,
                activeEndTime: 0,
                nextShotTime: (mech.activationMode === "hp") ? 0 : (now + startDelay),
                triggeredHPs: {},
                combatStartTime: now,
                capturedTargets: []
            };
            this.enemy.strangeDimensionState[mId] = state;
        }

        const clearTargetsDimension = (targetIds) => {
            (targetIds || []).forEach(tId => {
                const pObj = players[tId];
                if (pObj) {
                    pObj.inStrangeDimension = false;
                    pObj.isInvulnerable = false;
                    if (io) {
                        io.to(`zone_${pObj.zone}`).emit('playerStatSync', {
                            id: tId,
                            inStrangeDimension: false,
                            isInvulnerable: false
                        });
                    }
                }
            });
        };

        // Si sale de combate
        if (!this._inCombat) {
            if (state.isActive) {
                state.isActive = false;
                clearTargetsDimension(state.capturedTargets);
                if (io) {
                    io.to(roomName).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        mId: mId,
                        action: 'strange_dimension_expire',
                        type: 'strange_dimension',
                        targetIds: state.capturedTargets,
                        silent: false
                    });
                }
            }
            state.isCharging = false;
            state.triggeredHPs = {};
            state.nextShotTime = (mech.activationMode === "hp") ? 0 : (now + startDelay);
            return false;
        }

        // Chequeo de interrupción por CC (Control de Masas)
        if (castInterruptible && (state.isCharging || state.isActive)) {
            if (this.enemy.isStunned || this.enemy.isFeared || this.enemy.isPolymorphed || this.enemy.isAsleep) {
                state.isCharging = false;
                state.isActive = false;
                clearTargetsDimension(state.capturedTargets);
                state.nextShotTime = now + cd;
                if (io) {
                    io.to(roomName).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        mId: mId,
                        action: 'strange_dimension_expire',
                        type: 'strange_dimension',
                        targetIds: state.capturedTargets,
                        interrupted: true,
                        silent: false
                    });
                }
                return false;
            }
        }

        const activateDimension = () => {
            state.isCharging = false;
            state.isActive = true;
            state.activeEndTime = now + durationMs;
            state.nextShotTime = state.activeEndTime + cd;

            let targets = this._selectTargets(players, fireRange, targetCount, targetMode, mech);
            if ((!targets || targets.length === 0) && target) {
                targets = [target];
            }
            if (!targets || targets.length === 0) {
                const zonePlayers = Object.values(players || {}).filter(p => String(p.zone) === String(this.enemy.zone) && !p.isDead);
                if (zonePlayers.length > 0) targets = zonePlayers.slice(0, targetCount);
            }
            state.capturedTargets = (targets || []).map(p => p.socketId || p.id).filter(Boolean);

            state.capturedTargets.forEach(tId => {
                const pObj = players[tId];
                if (pObj) {
                    pObj.inStrangeDimension = true;
                    pObj.isInvulnerable = true;
                    if (io) {
                        io.to(`zone_${pObj.zone}`).emit('playerStatSync', {
                            id: tId,
                            inStrangeDimension: true,
                            isInvulnerable: true
                        });
                    }
                }
            });

            if (io) {
                io.to(roomName).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    mId: mId,
                    action: 'strange_dimension_start',
                    type: 'strange_dimension',
                    duration: durationMs / 1000.0,
                    durationMs: durationMs,
                    targetIds: state.capturedTargets,
                    x: this.enemy.x,
                    y: this.enemy.y,
                    silent: false
                });
            }
        };

        // 1. Durante la carga / casteo
        if (state.isCharging) {
            if (now >= state.chargeEndTime) {
                activateDimension();
            }
            return true;
        }

        // 2. Mientras la dimensión está activa
        if (state.isActive) {
            if (now >= state.activeEndTime) {
                state.isActive = false;
                clearTargetsDimension(state.capturedTargets);

                if (io) {
                    io.to(roomName).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        mId: mId,
                        action: 'strange_dimension_expire',
                        type: 'strange_dimension',
                        targetIds: state.capturedTargets,
                        silent: false
                    });
                }
            }
            return true;
        }

        // 3. Inicio / disparo de la mecánica
        // Activación por HP si está en modo hp
        const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
        if (mech.activationMode === "hp") {
            let thresholds = [];
            if (Array.isArray(mech.activationHPs)) {
                thresholds = mech.activationHPs.map(Number).filter(v => !isNaN(v));
            } else if (mech.activationHP !== undefined) {
                thresholds = [Number(mech.activationHP)];
            } else {
                thresholds = [50];
            }
            if (!state.triggeredHPs) state.triggeredHPs = {};
            let passesHP = false;
            let triggeredVal = null;
            for (const hpVal of thresholds) {
                if (hpPercent <= hpVal && !state.triggeredHPs[hpVal]) {
                    passesHP = true;
                    triggeredVal = hpVal;
                    break;
                }
            }
            if (!passesHP) return false;

            // Al pasar el umbral de HP por primera vez:
            state.triggeredHPs[triggeredVal] = true;
            state.nextShotTime = now + startDelay;
        }

        // Evaluación de disparo (startDelay transcurrido o cooldown finalizado)
        if (now >= state.nextShotTime) {
            if (castMs > 0) {
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
            } else {
                activateDimension();
            }
            return true;
        }

        return false;
    }
};
