// Server/behaviors/mechanics/BossDefenseMechanics.js
// Mecánicas defensivas modulares de jefes (Domo de supervivencia, Muro de energía y Reflejo)

function _handleSurvivalDomeLogic(mech, mId, target, dist, angle, now, io, players) {
    if (!this.enemy.mechState) this.enemy.mechState = {};
    const state = this.enemy.mechState[mId] || { 
        nextShotTime: now + (mech.startDelay || 0), 
        isCharging: false,
        isPostCastWaiting: false,
        chargeEndTime: 0,
        postCastEndTime: 0,
        safeX: 0,
        safeY: 0,
        safeRadius: mech.safeRadius || 150,
        fireRange: mech.fireRange || 800
    };
    this.enemy.mechState[mId] = state;

    // Cancelar o prevenir la mecánica si el enemigo no está en combate
    if (!this._inCombat) {
        if (state.isCharging || state.isPostCastWaiting) {
            state.isCharging = false;
            state.isPostCastWaiting = false;
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "survival_dome_fire", // limpia el domo en el cliente
                mId: mId
            });
        }
        state.nextShotTime = now + (mech.startDelay || 0);
        return false;
    }

    // Si ya pasó el tiempo de inmovilidad post-explosión
    if (state.isPostCastWaiting && now >= state.postCastEndTime) {
        state.isPostCastWaiting = false;
    }

    // Si está inmovilizado post-casteo, el enemigo se queda quieto
    if (state.isPostCastWaiting) {
        return true;
    }

    if (!state.isCharging && now >= state.nextShotTime && this._inCombat) {
        // FASE 1: INICIO DE CARGA Y CÁLCULO DE LA ZONA SEGURA (Domo)
        state.isCharging = true;
        const castTime = Number(mech.castTimeMs) || 3000;
        state.chargeEndTime = now + castTime;
        state.safeRadius = Number(mech.safeRadius) || 150;
        state.fireRange = Number(mech.fireRange) || 800;

        // Calcular ubicación random del domo que no coincida con el enemigo (fuera de él)
        const safeRadius = Number(mech.safeRadius) || 150;
        const maxOffset = Math.max(safeRadius + 150, Number(mech.maxOffset) || 350);
        const minOffset = safeRadius + 80;
        const randomAngle = Math.random() * Math.PI * 2;
        const randomDist = minOffset + Math.random() * (maxOffset - minOffset);
        state.safeX = this.enemy.x + Math.cos(randomAngle) * randomDist;
        state.safeY = this.enemy.y + Math.sin(randomAngle) * randomDist;

        // Notificar el inicio de la carga del domo
        io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
            id: this.enemy.id,
            action: "survival_dome_charging",
            mId: mId,
            duration: castTime,
            safeX: state.safeX,
            safeY: state.safeY,
            safeRadius: state.safeRadius,
            fireRange: state.fireRange
        });
        
        io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
            msg: `⚠️ ¡Alerta! El Boss está cargando un ataque masivo. ¡Busca refugio en el Domo Seguro! ⚠️`, 
            type: "error" 
        });
    } 
    
    if (state.isCharging) {
        if (now >= state.chargeEndTime) {
            // FASE 2: DETONACIÓN (EXPLOSIÓN Y APLICACIÓN DE DAÑO / DEBUFFS)
            state.isCharging = false;
            
            const cooldown = Number(mech.cooldown) || 10000;
            state.nextShotTime = now + cooldown;

            const postWait = Number(mech.postCastWaitMs) || 1000;
            if (postWait > 0) {
                state.isPostCastWaiting = true;
                state.postCastEndTime = now + postWait;
            }

            // Notificar detonación
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "survival_dome_fire",
                mId: mId,
                safeX: state.safeX,
                safeY: state.safeY,
                safeRadius: state.safeRadius,
                fireRange: state.fireRange
            });

            // Evaluar jugadores afectados
            const dmg = (Number(mech.damage) || 500) * (this.damageMult || 1);
            const zonePlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead);
            
            zonePlayers.forEach(p => {
                const distToEnemy = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                if (distToEnemy <= state.fireRange) {
                    const distToSafe = Math.hypot(p.x - state.safeX, p.y - state.safeY);
                    if (distToSafe > state.safeRadius) {
                        p.lastCombatTime = Date.now();
                        if (p.shield >= dmg) {
                            p.shield -= dmg;
                        } else {
                            p.hp -= (dmg - p.shield);
                            p.shield = 0;
                        }
                        if (p.hp < 0) p.hp = 0;
                        if (p.hp <= 0) this._killPlayer(p, io);

                        io.to(p.socketId).emit('environmentDamage', { damage: dmg });

                        if (mech.debuffsList && Array.isArray(mech.debuffsList)) {
                            mech.debuffsList.forEach(d => {
                                if (d.type === 'bleed') {
                                    const bleedDps = Number(d.dps) || 30;
                                    const bleedDur = Number(d.duration) || 4000;
                                    const tickInt = Number(d.tickInterval) || 1000;
                                    p.isBleeding = true;
                                    p.bleedEndTime = Date.now() + bleedDur;
                                    p.bleedDps = bleedDps;
                                    p.bleedInterval = tickInt;
                                    p.lastBleedTick = Date.now();
                                    io.to(p.socketId).emit('gameNotification', { 
                                        msg: `🩸 ¡Sufres de Sangrado! perdiendo ${bleedDps} HP cada ${tickInt}ms.`, 
                                        type: "warning" 
                                    });
                                }
                                else if (d.type === 'poison') {
                                    const poisonDps = Number(d.dps) || 20;
                                    const poisonDur = Number(d.duration) || 4000;
                                    const tickInt = Number(d.tickInterval) || 1000;
                                    p.isPoisoned = true;
                                    p.poisonEndTime = Date.now() + poisonDur;
                                    p.poisonDps = poisonDps;
                                    p.poisonInterval = tickInt;
                                    p.lastPoisonTick = Date.now();
                                    io.to(p.socketId).emit('gameNotification', { 
                                        msg: `🤢 ¡Has sido envenenado! perdiendo ${poisonDps} HP cada ${tickInt}ms.`, 
                                        type: "warning" 
                                    });
                                }
                                else if (d.type === 'stun') {
                                    const stunDuration = Number(d.duration) || 1500;
                                    p.isStunned = true;
                                    p.stunEndTime = Date.now() + stunDuration;
                                    io.to(p.socketId).emit('stunState', { active: true, duration: stunDuration });
                                    io.to(p.socketId).emit('gameNotification', { 
                                        msg: `⚡ ¡Has sido paralizado!`, 
                                        type: "error" 
                                    });
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
                                    io.to(p.socketId).emit('gameNotification', { 
                                        msg: `🐢 ¡Ralentizado! Velocidad reducida en ${slowAmt}${isPct ? '%' : ' px/s'}.`, 
                                        type: "warning" 
                                    });
                                }
                            });
                        }

                        io.to(`zone_${p.zone}`).emit('playerStatSync', {
                            id: p.socketId,
                            hp: Math.ceil(p.hp),
                            shield: Math.ceil(p.shield),
                            isDead: p.isDead
                        });
                    }
                }
            });
        }
        return true;
    }

    return false;
}

function _handleWallDomeLogic(mech, mId, now, io) {
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || { 
        nextReadyTime: now + (mech.startDelay || 0), 
        isActive: false, 
        endTime: 0,
        triggeredHPs: {},
        combatStartTime: null,
        type: "wall_dome",
        radius: mech.radius || 300
    };
    this.enemy.defState[mId] = state;

    state.radius = mech.radius || 300;
    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;

    if (!this._inCombat) {
        state.triggeredHPs = {};
        state.combatStartTime = null;
        state.nextReadyTime = now + (mech.startDelay || 0);
        if (state.isActive) {
            state.isActive = false;
            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", { 
                id: this.enemy.id, 
                action: "wall_dome_end",
                mId: mId
            });
        }
    } else if (this._inCombat && !state.combatStartTime) {
        state.combatStartTime = now;
        if (mech.activationMode === "time") {
            const raw = this._getRawInterval(mech);
            if (raw === 0) {
                state.nextReadyTime = now + (Number(mech.startDelay) || 0);
            } else {
                state.nextReadyTime = now + raw;
            }
        }
    }

    if (state.isActive && now >= state.endTime) {
        state.isActive = false;
        
        if (mech.activationMode === "time") {
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
        } else {
            state.nextReadyTime = now + (mech.cooldown || 10000);
        }

        io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", { 
            id: this.enemy.id, 
            action: "wall_dome_end",
            mId: mId
        });
    }

    let shouldActivate = false;
    if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
        if (mech.activationMode === "time") {
            shouldActivate = true;
        } else {
            let thresholds = [];
            if (Array.isArray(mech.activationHPs)) {
                thresholds = mech.activationHPs.map(Number).filter(v => !isNaN(v));
            } else if (mech.activationHP !== undefined) {
                thresholds = [Number(mech.activationHP)];
            } else {
                thresholds = [50];
            }

            if (!state.triggeredHPs) {
                state.triggeredHPs = {};
            }

            for (const hpVal of thresholds) {
                if (hpPercent <= hpVal) {
                    shouldActivate = true;
                    state.triggeredHPs[hpVal] = true;
                    break;
                }
            }
        }
    }

    if (shouldActivate) {
        state.isActive = true;
        const duration = mech.duration || 10000;
        state.endTime = now + duration;
        
        io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", { 
            id: this.enemy.id, 
            action: "wall_dome_start",
            mId: mId,
            radius: state.radius,
            duration: duration
        });

        io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
            msg: `🛡️ ¡El Boss levantó un Muro de Energía! Entrá al área (${state.radius}px) para dañarlo. 🛡️`, 
            type: "warning" 
        });
    }
}

function _handleReflectLogic(mech, mId, now, io) {
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || { 
        nextReadyTime: now + (mech.startDelay || 0), 
        isActive: false, 
        endTime: 0,
        triggeredHPs: {},
        combatStartTime: null,
        type: "reflect"
    };
    this.enemy.defState[mId] = state;

    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;

    if (!this._inCombat) {
        state.triggeredHPs = {};
        state.combatStartTime = null;
        state.nextReadyTime = now + (mech.startDelay || 0);
        if (state.isActive) {
            state.isActive = false;
            this.enemy.reflectActive = false;
            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", { 
                id: this.enemy.id, 
                action: "reflect_end",
                mId: mId
            });
        }
    } else if (this._inCombat && !state.combatStartTime) {
        state.combatStartTime = now;
        if (mech.activationMode === "time") {
            const raw = this._getRawInterval(mech);
            if (raw === 0) {
                state.nextReadyTime = now + (Number(mech.startDelay) || 0);
            } else {
                state.nextReadyTime = now + raw;
            }
        }
    }

    if (state.isActive && now >= state.endTime) {
        state.isActive = false;
        this.enemy.reflectActive = false;
        
        if (mech.activationMode === "time") {
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
        } else {
            state.nextReadyTime = now + (mech.cooldown || 10000);
        }

        io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", { 
            id: this.enemy.id, 
            action: "reflect_end",
            mId: mId
        });
    }

    let shouldActivate = false;
    if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
        if (mech.activationMode === "time") {
            shouldActivate = true;
        } else {
            let thresholds = [];
            if (Array.isArray(mech.activationHPs)) {
                thresholds = mech.activationHPs.map(Number).filter(v => !isNaN(v));
            } else if (mech.activationHP !== undefined) {
                thresholds = [Number(mech.activationHP)];
            } else {
                thresholds = [50];
            }

            if (!state.triggeredHPs) {
                state.triggeredHPs = {};
            }

            for (const hpVal of thresholds) {
                if (hpPercent <= hpVal) {
                    shouldActivate = true;
                    state.triggeredHPs[hpVal] = true;
                    break;
                }
            }
        }
    }

    if (shouldActivate) {
        state.isActive = true;
        const duration = mech.duration || 3000;
        state.endTime = now + duration;
        
        const reflectMult = mech.reflect_mult !== undefined ? Number(mech.reflect_mult) : 0.8;
        this.enemy.reflectActive = true;
        this.enemy.reflectMult = reflectMult;

        io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", { 
            id: this.enemy.id, 
            action: "reflect_start",
            duration: duration,
            reflect_mult: reflectMult,
            mId: mId
        });
    }
}

module.exports = {
    _handleSurvivalDomeLogic,
    _handleWallDomeLogic,
    _handleReflectLogic
};
