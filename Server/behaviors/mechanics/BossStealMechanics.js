// Server/behaviors/mechanics/BossStealMechanics.js
// v410-v412: Mecánicas modulares de robo de escudo (shield_steal) y robo de vida (life_steal)

function _handleShieldStealLogic(mech, mId, now, io, players) {
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || {
        nextReadyTime: now + (mech.startDelay || 0),
        isActive: false,
        endTime: 0,
        targetId: "",
        lastStealTime: 0,
        triggeredHPs: {},
        combatStartTime: null,
        fired: false,
        firedShotTime: 0,
        nextShotTime: 0,
        type: "shield_steal"
    };
    this.enemy.defState[mId] = state;
    this.enemy._shieldStealMId = mId;

    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
    const stealRange = mech.fireRange || 800;

    // Resetear al salir de combate / limpieza de link
    if (!this._inCombat) {
        if (state.isActive) {
            state.isActive = false;
            const oldTarget = state.targetId;
            state.targetId = "";
            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", {
                id: this.enemy.id, action: "shield_steal_end", mId: mId, targetId: oldTarget
            });
        }
        state.triggeredHPs = {};
        state.combatStartTime = null;
        state.fired = false;
        state.nextReadyTime = now + (mech.startDelay || 0);
        return;
    }
    if (this._inCombat && !state.combatStartTime) {
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

    const cooldown = (mech.cooldown !== undefined ? Number(mech.cooldown) : 12000);
    const stealMode = mech.stealMode || "flat";
    const stealAmount = mech.stealAmount !== undefined ? Number(mech.stealAmount) : (stealMode === "percent" ? 25 : 100);
    const stealIntervalMs = (mech.stealIntervalMs !== undefined ? Number(mech.stealIntervalMs) : 1000);
    const linkDuration = (mech.duration !== undefined ? Number(mech.duration) : 5000);
    const speedValue = mech.bulletSpeed || 700;
    const targetMode = mech.targetMode || "proximity";

    // Si el proyectil ya se disparó pero nunca impactó (escapó / murió / se fue de rango),
    // liberar el estado para volver a intentarlo tras el cooldown.
    if (state.fired && !state.isActive && state.firedShotTime) {
        const flightLimit = (stealRange / speedValue) * 1000 + 2500;
        if (now - state.firedShotTime >= flightLimit) {
            state.fired = false;
            state.nextReadyTime = now + cooldown;
        }
    }

    // 1. Si hay un vínculo activo, procesarlo: robar escudo por ticks y expirar
    if (state.isActive && state.targetId) {
        const target = players ? players[state.targetId] : null;

        // Expirar si el jugador no existe, está muerto, se fue de la zona o pasó el tiempo
        if (!target || target.isDead || target.zone !== this.enemy.zone || now >= state.endTime) {
            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", {
                id: this.enemy.id, action: "shield_steal_end", mId: mId, targetId: state.targetId
            });
            state.isActive = false;
            state.targetId = "";
            state.fired = false;
            state.firedShotTime = 0;
            state.nextReadyTime = now + cooldown;
            this.enemy.defState[mId] = state;
            return;
        }

        // Tick de robo de escudo (porcentual del maxShield del jugador o plano)
        if (now - state.lastStealTime >= stealIntervalMs) {
            state.lastStealTime = now;

            let stolen = 0;
            if (stealMode === "percent") {
                stolen = Math.min(Math.ceil((target.maxShield || 0) * (stealAmount / 100)), target.shield);
            } else {
                stolen = Math.min(stealAmount, target.shield);
            }

            if (stolen > 0) {
                target.shield -= stolen;
                target.lastCombatTime = Date.now();

                // Si el robo alimenta el escudo del propio enemigo (configurable)
                if (mech.giveToEnemy !== false) {
                    const oldSh = this.enemy.shield;
                    if (this.enemy.shield < this.enemy.maxShield) {
                        this.enemy.shield = Math.min(this.enemy.maxShield, this.enemy.shield + stolen);
                    }
                    // Siempre emitir, aunque sea +0 (escudo lleno) para mostrar texto celeste al cliente
                    io.to(`zone_${this.enemy.zone}`).emit("enemyHealed", {
                        id: this.enemy.id, hp: this.enemy.hp, shield: this.enemy.shield,
                        amount: Math.max(0, this.enemy.shield - oldSh)
                    });
                }

                io.to(target.socketId).emit("environmentDamage", { damage: stolen, isShield: true });
                io.to(`zone_${target.zone}`).emit("playerStatSync", {
                    id: target.socketId, hp: Math.ceil(target.hp), shield: Math.ceil(target.shield),
                    maxHp: target.maxHp, maxShield: target.maxShield, isDead: target.isDead,
                    suppressDamagePopup: true
                });

                io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", {
                    id: this.enemy.id, action: "shield_steal_tick",
                    targetId: target.socketId, amount: stolen, mId: mId,
                    ex: this.enemy.x, ey: this.enemy.y
                });
            }
        }
        this.enemy.defState[mId] = state;
        return;
    }

    // 2) Activación de la mecánica
    let shouldActivate = false;
    if (!state.isActive && !state.fired && now >= state.nextReadyTime && this._inCombat) {
        if (mech.activationMode === "time") {
            shouldActivate = true;
        } else if (state.combatStartTime) {
            let thresholds = [];
            if (Array.isArray(mech.activationHPs)) {
                thresholds = mech.activationHPs.map(Number).filter(v => !isNaN(v));
            } else if (mech.activationHP !== undefined) {
                thresholds = [Number(mech.activationHP)];
            } else {
                thresholds = [50];
            }
            if (state.triggeredHPs === undefined) state.triggeredHPs = {};
            for (const hpVal of thresholds) {
                if (hpPercent <= hpVal) {
                    shouldActivate = true;
                    state.triggeredHPs[hpVal] = true;
                    break;
                }
            }
        }
    }

    if (shouldActivate && now >= state.nextShotTime) {
        const selected = this._selectTargets(players, stealRange, 1, targetMode, mech);
        const chosen = selected.length > 0 ? selected[0] : null;

        if (chosen) {
            const dmgForBullet = mech.bulletDamage !== undefined ? Number(mech.bulletDamage) : 10;
            state.fired = true;
            state.firedShotTime = now;
            state.nextShotTime = now + cooldown;
            state.nextShotWait = now + (mech.nextShotMs !== undefined ? Number(mech.nextShotMs) : 0);

            const ang = Math.atan2(chosen.y - this.enemy.y, chosen.x - this.enemy.x);
            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyFire", {
                enemyId: this.enemy.id,
                targetId: chosen.socketId,
                enemyType: this.enemy.type,
                x: this.enemy.x, y: this.enemy.y, angle: ang,
                bulletSpeed: mech.bulletSpeed || 700,
                bulletType: "shield_steal",
                damage: dmgForBullet * (this.damageMult || 1),
                isHoming: mech.isPointAndClick === true,
                turnSpeed: mech.turnSpeed || 3.0,
                lifetimeMs: mech.lifetimeMs || (stealRange / speedValue) * 1000 + 1500,
                range: stealRange
            });
        }
        this.enemy.defState[mId] = state;
    }

    this.enemy.defState[mId] = state;
}

function _onEnemyShieldStealHit(targetId, mech, mId, now, io) {
    if (!mech) mech = {};
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || {};
    state.isActive = true;
    state.targetId = targetId;
    state.lastStealTime = now;
    state.endTime = now + (mech.duration || 5000);
    this.enemy.defState[mId] = state;

    const stealMode = mech.stealMode || "flat";
    const stealAmount = mech.stealAmount !== undefined ? Number(mech.stealAmount) : (stealMode === "percent" ? 25 : 100);
    io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", {
        id: this.enemy.id, action: "shield_steal_start",
        mId: mId, targetId: targetId,
        duration: mech.duration || 5000,
        stealMode: stealMode,
        stealAmount: stealAmount,
        ex: this.enemy.x, ey: this.enemy.y
    });
}

function findShieldStealMech() {
    const defs = this.config.defenseMechanics || [];
    const idx = defs.findIndex(d => d.type === "shield_steal");
    if (idx === -1) return null;
    return { mech: defs[idx], mId: `def_${idx}` };
}

function _handleLifeStealLogic(mech, mId, now, io, players) {
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || {
        nextReadyTime: now + (mech.startDelay || 0),
        isActive: false,
        endTime: 0,
        targetId: "",
        lastStealTime: 0,
        triggeredHPs: {},
        combatStartTime: null,
        fired: false,
        firedShotTime: 0,
        nextShotTime: 0,
        type: "life_steal"
    };
    this.enemy.defState[mId] = state;
    this.enemy._lifeStealMId = mId;

    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
    const stealRange = mech.fireRange || 800;

    // Resetear al salir de combate / limpieza de link
    if (!this._inCombat) {
        if (state.isActive) {
            state.isActive = false;
            const oldTarget = state.targetId;
            state.targetId = "";
            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", {
                id: this.enemy.id, action: "life_steal_end", mId: mId, targetId: oldTarget
            });
        }
        state.triggeredHPs = {};
        state.combatStartTime = null;
        state.fired = false;
        state.nextReadyTime = now + (mech.startDelay || 0);
        return;
    }
    if (this._inCombat && !state.combatStartTime) {
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

    const cooldown = (mech.cooldown !== undefined ? Number(mech.cooldown) : 12000);
    const stealMode = mech.stealMode || "flat";
    const stealAmount = mech.stealAmount !== undefined ? Number(mech.stealAmount) : (stealMode === "percent" ? 25 : 100);
    const stealIntervalMs = (mech.stealIntervalMs !== undefined ? Number(mech.stealIntervalMs) : 1000);
    const linkDuration = (mech.duration !== undefined ? Number(mech.duration) : 5000);
    const speedValue = mech.bulletSpeed || 700;
    const targetMode = mech.targetMode || "proximity";

    // Si el proyectil ya se disparó pero nunca impactó, liberar estado
    if (state.fired && !state.isActive && state.firedShotTime) {
        const flightLimit = (stealRange / speedValue) * 1000 + 2500;
        if (now - state.firedShotTime >= flightLimit) {
            state.fired = false;
            state.nextReadyTime = now + cooldown;
        }
    }

    // 1. Si hay un vínculo activo, procesarlo: robar vida por ticks y expirar
    if (state.isActive && state.targetId) {
        const target = players ? players[state.targetId] : null;

        if (!target || target.isDead || target.zone !== this.enemy.zone || now >= state.endTime) {
            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", {
                id: this.enemy.id, action: "life_steal_end", mId: mId, targetId: state.targetId
            });
            state.isActive = false;
            state.targetId = "";
            state.fired = false;
            state.firedShotTime = 0;
            state.nextReadyTime = now + cooldown;
            this.enemy.defState[mId] = state;
            return;
        }

        // Tick de robo de vida
        if (now - state.lastStealTime >= stealIntervalMs) {
            state.lastStealTime = now;

            let stolen = 0;
            if (stealMode === "percent") {
                stolen = Math.min(Math.ceil((target.maxHp || 0) * (stealAmount / 100)), target.hp);
            } else {
                stolen = Math.min(stealAmount, target.hp);
            }

            if (stolen > 0) {
                target.hp -= stolen;
                target.lastCombatTime = Date.now();
                if (target.hp < 0) target.hp = 0;
                if (target.hp <= 0) target.isDead = true;

                if (mech.giveToEnemy !== false) {
                    const oldHp = this.enemy.hp;
                    if (this.enemy.hp < this.enemy.maxHp) {
                        this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + stolen);
                    }
                    io.to(`zone_${this.enemy.zone}`).emit("enemyHealed", {
                        id: this.enemy.id, hp: this.enemy.hp, shield: this.enemy.shield,
                        amount: Math.max(0, this.enemy.hp - oldHp),
                        isLifeSteal: true
                    });
                }

                io.to(target.socketId).emit("environmentDamage", { damage: stolen, isLifeSteal: true });
                io.to(`zone_${target.zone}`).emit("playerStatSync", {
                    id: target.socketId, hp: Math.ceil(target.hp), shield: Math.ceil(target.shield),
                    maxHp: target.maxHp, maxShield: target.maxShield, isDead: target.isDead,
                    suppressDamagePopup: true
                });

                io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", {
                    id: this.enemy.id, action: "life_steal_tick",
                    targetId: target.socketId, amount: stolen, mId: mId,
                    ex: this.enemy.x, ey: this.enemy.y
                });
            }
        }
        this.enemy.defState[mId] = state;
        return;
    }

    // 2) Activación de la mecánica
    let shouldActivate = false;
    if (!state.isActive && !state.fired && now >= state.nextReadyTime && this._inCombat) {
        if (mech.activationMode === "time") {
            shouldActivate = true;
        } else if (state.combatStartTime) {
            let thresholds = [];
            if (Array.isArray(mech.activationHPs)) {
                thresholds = mech.activationHPs.map(Number).filter(v => !isNaN(v));
            } else if (mech.activationHP !== undefined) {
                thresholds = [Number(mech.activationHP)];
            } else {
                thresholds = [50];
            }
            if (state.triggeredHPs === undefined) state.triggeredHPs = {};
            for (const hpVal of thresholds) {
                if (hpPercent <= hpVal) {
                    shouldActivate = true;
                    state.triggeredHPs[hpVal] = true;
                    break;
                }
            }
        }
    }

    if (shouldActivate && now >= state.nextShotTime) {
        const selected = this._selectTargets(players, stealRange, 1, targetMode, mech);
        const chosen = selected.length > 0 ? selected[0] : null;

        if (chosen) {
            const dmgForBullet = mech.bulletDamage !== undefined ? Number(mech.bulletDamage) : 10;
            state.fired = true;
            state.firedShotTime = now;
            state.nextShotTime = now + cooldown;
            state.nextShotWait = now + (mech.nextShotMs !== undefined ? Number(mech.nextShotMs) : 0);

            const ang = Math.atan2(chosen.y - this.enemy.y, chosen.x - this.enemy.x);
            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyFire", {
                enemyId: this.enemy.id,
                targetId: chosen.socketId,
                enemyType: this.enemy.type,
                x: this.enemy.x, y: this.enemy.y, angle: ang,
                bulletSpeed: mech.bulletSpeed || 700,
                bulletType: "life_steal",
                damage: dmgForBullet * (this.damageMult || 1),
                isHoming: mech.isPointAndClick === true,
                turnSpeed: mech.turnSpeed || 3.0,
                lifetimeMs: mech.lifetimeMs || (stealRange / speedValue) * 1000 + 1500,
                range: stealRange
            });
        }
        this.enemy.defState[mId] = state;
    }

    this.enemy.defState[mId] = state;
}

function _onEnemyLifeStealHit(targetId, mech, mId, now, io) {
    if (!mech) mech = {};
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || {};
    state.isActive = true;
    state.targetId = targetId;
    state.lastStealTime = now;
    state.endTime = now + (mech.duration || 5000);
    this.enemy.defState[mId] = state;

    const stealMode = mech.stealMode || "flat";
    const stealAmount = mech.stealAmount !== undefined ? Number(mech.stealAmount) : (stealMode === "percent" ? 25 : 100);
    io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", {
        id: this.enemy.id, action: "life_steal_start",
        mId: mId, targetId: targetId,
        duration: mech.duration || 5000,
        stealMode: stealMode,
        stealAmount: stealAmount,
        ex: this.enemy.x, ey: this.enemy.y
    });
}

function findLifeStealMech() {
    const defs = this.config.defenseMechanics || [];
    const idx = defs.findIndex(d => d.type === "life_steal");
    if (idx === -1) return null;
    return { mech: defs[idx], mId: `def_${idx}` };
}

module.exports = {
    _handleShieldStealLogic,
    _onEnemyShieldStealHit,
    findShieldStealMech,
    _handleLifeStealLogic,
    _onEnemyLifeStealHit,
    findLifeStealMech
};
