// Server/behaviors/mechanics/BossPuzzleMechanics.js
// Mecánicas modulares de puzzles, pilares, colores, orbes de agua, clones e invocaciones de jefes

const { normalizeZone } = require('../../utils/zoneUtils');

function _handleBossPillarsLogic(mech, mId, now, io) {
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || { 
        nextReadyTime: now + (mech.startDelay || 0), 
        isActive: false, 
        endTime: 0,
        pillars: [],
        lastHealTime: 0,
        triggeredHPs: {},
        combatStartTime: null
    };
    this.enemy.defState[mId] = state;

    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;

    if (!this._inCombat) {
        state.triggeredHPs = {};
        state.combatStartTime = null;
        state.nextReadyTime = now + (mech.startDelay || 0);
    } else if (this._inCombat && !state.combatStartTime) {
        state.combatStartTime = now;
        if (mech.activationMode === "time") {
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
        }
    }

    if (state.isActive) {
        const activePillars = state.pillars.filter(pid => this.state.enemies[pid] && this.state.enemies[pid].hp > 0);

        if (activePillars.length === 0) {
            state.isActive = false;
            this._isDefenseSkillActive = false;
            this.enemy.isInvulnerable = false;
            state.pillars = [];
            state.nextReadyTime = now + (mech.cooldown || 30000);
            this.enemy.lastHit = now;

            io.to(`zone_${this.enemy.zone}`).emit("vfx_invulnerable", { id: this.enemy.id, active: false });
            io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
                msg: `🛡️ ¡Pilares del Boss destruidos! La barrera ha caído.`, 
                type: "success" 
            });
        } else {
            const interval = mech.healIntervalMs || 2000;
            if (now - state.lastHealTime >= interval) {
                state.lastHealTime = now;
                const healPct = mech.healPercentPerTick !== undefined ? mech.healPercentPerTick : 1;
                const healAmount = this.enemy.maxHp * (healPct / 100);
                const oldHp = this.enemy.hp;
                
                if (healAmount > 0) {
                    this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + healAmount);
                    io.to(`zone_${this.enemy.zone}`).emit('enemyHealed', { 
                        id: this.enemy.id, 
                        hp: this.enemy.hp, 
                        amount: Math.max(0, this.enemy.hp - oldHp),
                        healType: 'hp'
                    });

                    activePillars.forEach(pid => {
                        const pillar = this.state.enemies[pid];
                        io.to(`zone_${this.enemy.zone}`).emit('bossEffect', { 
                            type: 'leech', 
                            from: pid, 
                            to: this.enemy.id,
                            x: pillar ? pillar.x : this.enemy.x,
                            y: pillar ? pillar.y : this.enemy.y
                        });
                    });
                }
            }

            if (now >= state.endTime) {
                const healPctPerPillar = mech.healPercentPerPillarOnExpiry || 5;
                const finalHealPct = activePillars.length * healPctPerPillar;
                const healAmount = this.enemy.maxHp * (finalHealPct / 100);
                const oldHp = this.enemy.hp;
                this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + healAmount);

                io.to(`zone_${this.enemy.zone}`).emit('enemyHealed', { 
                    id: this.enemy.id, 
                    hp: this.enemy.hp, 
                    amount: Math.max(0, this.enemy.hp - oldHp),
                    healType: 'hp'
                });

                activePillars.forEach(pid => {
                    const pillar = this.state.enemies[pid];
                    io.to(`zone_${this.enemy.zone}`).emit('bossEffect', { 
                        type: 'leech', 
                        from: pid, 
                        to: this.enemy.id,
                        x: pillar ? pillar.x : this.enemy.x,
                        y: pillar ? pillar.y : this.enemy.y
                    });
                    io.to(`zone_${this.enemy.zone}`).emit('enemyDead', { id: pid });
                    delete this.state.enemies[pid];
                });

                state.isActive = false;
                this._isDefenseSkillActive = false;
                this.enemy.isInvulnerable = false;
                state.pillars = [];
                state.nextReadyTime = now + (mech.cooldown || 30000);
                this.enemy.lastHit = now;

                io.to(`zone_${this.enemy.zone}`).emit("vfx_invulnerable", { id: this.enemy.id, active: false });
                io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
                    msg: `⏳ Tiempo expirado. Pilares retirados y Boss regenerado.`, 
                    type: "warning" 
                });
            }
        }
    }

    let shouldActivate = false;
    if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
        if (mech.activationMode === "time") {
            shouldActivate = true;
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
        this._isDefenseSkillActive = true;
        this.enemy.isInvulnerable = true;
        
        state.endTime = now + (mech.duration || 15000);
        state.lastHealTime = now;
        state.pillars = [];
        
        if (mech.activationMode !== "time") {
            state.nextReadyTime = now + (mech.cooldown || 30000);
        }

        const pillarCount = mech.pillarCount || 3;
        const radius = mech.spawnRadius || 350;
        const pType = mech.pillarType || 200;

        const pCfg = (this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.enemyModels) 
            ? this.state.SERVER_CONFIG.enemyModels[pType.toString()] 
            : null;

        let hp = mech.pillarHp || (pCfg ? pCfg.hp : 5000);
        let shield = mech.pillarShield || (pCfg ? pCfg.shield : 0);
        let pName = mech.pillarName || (pCfg ? pCfg.name : "Pilar Protector");

        for (let i = 0; i < pillarCount; i++) {
            const angle = (i / pillarCount) * Math.PI * 2;
            const px = this.enemy.x + Math.cos(angle) * radius;
            const py = this.enemy.y + Math.sin(angle) * radius;
            const pillarId = `pillar_${this.enemy.id}_${i}_${Date.now()}`;

            const pillarObj = {
                id: pillarId,
                type: pType,
                zone: this.enemy.zone,
                name: pName,
                x: px,
                y: py,
                startX: px,
                startY: py,
                hp: hp,
                maxHp: hp,
                shield: shield,
                maxShield: shield,
                rotation: angle,
                lastHit: 0,
                isInvulnerable: false
            };

            this.state.enemies[pillarId] = pillarObj;
            state.pillars.push(pillarId);

            io.to(`zone_${this.enemy.zone}`).emit('enemySpawn', pillarObj);
        }

        io.to(`zone_${this.enemy.zone}`).emit("vfx_invulnerable", { 
            id: this.enemy.id, 
            active: true, 
            duration: mech.duration || 15000 
        });

        io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
            msg: `🚨 ¡El Boss invocó Pilares de Protección! Destrúyalos. 🚨`, 
            type: "error" 
        });
    }
}

function _handleBossColorsLogic(mech, mId, now, io, players) {
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || { 
        nextReadyTime: now + (mech.startDelay || 0), 
        isActive: false, 
        endTime: 0,
        triggeredHPs: {},
        combatStartTime: null
    };
    this.enemy.defState[mId] = state;

    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;

    if (!this._inCombat) {
        state.triggeredHPs = {};
        state.combatStartTime = null;
        state.nextReadyTime = now + (mech.startDelay || 0);
        if (state.isActive) {
            io.to(`zone_${this.enemy.zone}`).emit('bossColorsEnd', { bossId: this.enemy.id });
            state.isActive = false;
            this._isDefenseSkillActive = false;
            this.enemy.colorState = null;
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

    if (state.isActive) {
        if (now >= state.endTime) {
            state.isActive = false;
            this._isDefenseSkillActive = false;
            this.enemy.colorState = null;
            state.nextReadyTime = now + (mech.cooldown || 30000);
            this.enemy.lastHit = now;

            io.to(`zone_${this.enemy.zone}`).emit('bossColorsEnd', { bossId: this.enemy.id });
            io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
                msg: `🎨 La barrera de colores del Boss ha desaparecido.`, 
                type: "info" 
            });
        }
    }

    let shouldActivate = false;
    if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
        if (mech.activationMode === "time") {
            shouldActivate = true;
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
        this._isDefenseSkillActive = true;
        
        const duration = mech.duration || 15000;
        state.endTime = now + duration;
        if (mech.activationMode !== "time") {
            state.nextReadyTime = now + (mech.cooldown || 30000);
        }

        const colors = ["roja", "azul", "verde", "amarilla", "violeta"];
        const bossColor = colors[Math.floor(Math.random() * colors.length)];
        
        const radius = mech.radius || 1200;
        const playerColors = {};
        
        const nearbyPlayers = Object.values(players || {}).filter(p => {
            const sameZone = (normalizeZone(p.zone) === normalizeZone(this.enemy.zone));
            if (!sameZone || p.isDead) return false;
            const dist = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
            return dist <= radius;
        });

        nearbyPlayers.forEach(p => {
            const pColor = colors[Math.floor(Math.random() * colors.length)];
            playerColors[p.socketId] = pColor;
            p.colorState = pColor;
        });

        this.enemy.colorState = {
            bossColor: bossColor,
            playerColors: playerColors,
            endTime: state.endTime
        };

        io.to(`zone_${this.enemy.zone}`).emit('bossColorsStart', {
            bossId: this.enemy.id,
            bossColor: bossColor,
            playerColors: playerColors,
            duration: duration
        });

        io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
            msg: `🎨 ¡El Boss activó una Barrera de Colores! Coincide tu color para dañarlo.`, 
            type: "error" 
        });
    }
}

function _handleBossWaterOrbsLogic(mech, mId, now, io, grid, players) {
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || { 
        nextReadyTime: now + (mech.startDelay || 0), 
        isActive: false, 
        endTime: 0,
        orbs: [],
        triggeredHPs: {},
        combatStartTime: null
    };
    this.enemy.defState[mId] = state;

    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;

    if (!this._inCombat) {
        if (state.orbs.length > 0) {
            state.orbs.forEach(oid => {
                if (this.state.enemies[oid]) {
                    io.to(`zone_${this.enemy.zone}`).emit('enemyDead', { id: oid });
                    delete this.state.enemies[oid];
                }
            });
        }
        state.orbs = [];
        state.triggeredHPs = {};
        state.combatStartTime = null;
        state.nextReadyTime = now + (mech.startDelay || 0);
        if (state.isActive) {
            state.isActive = false;
            this._isDefenseSkillActive = false;
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

    if (state.isActive) {
        state.orbs = state.orbs.filter(oid => this.state.enemies[oid]);

        if (state.orbs.length === 0 || now >= state.endTime) {
            state.isActive = false;
            this._isDefenseSkillActive = false;
            
            state.orbs.forEach(oid => {
                if (this.state.enemies[oid]) {
                    io.to(`zone_${this.enemy.zone}`).emit('enemyDead', { id: oid });
                    delete this.state.enemies[oid];
                }
            });
            
            state.orbs = [];
            state.nextReadyTime = now + (mech.cooldown || 30000);
            this.enemy.lastHit = now;
            return;
        }

        let orbSpeedVal = mech.orbSpeed !== undefined ? Number(mech.orbSpeed) : 150;
        if (orbSpeedVal <= 0) orbSpeedVal = 150;
        const speed = orbSpeedVal * 0.033;
        const dmg = (mech.playerDamage !== undefined ? Number(mech.playerDamage) : 150) * (this.damageMult || 1);
        const healPct = mech.bossHealPercent !== undefined ? Number(mech.bossHealPercent) : 5;

        state.orbs.forEach(oid => {
            const orb = this.state.enemies[oid];
            if (!orb) return;

            const angle = Math.atan2(this.enemy.y - orb.y, this.enemy.x - orb.x);
            orb.x += Math.cos(angle) * speed;
            orb.y += Math.sin(angle) * speed;
            orb.rotation = angle + Math.PI / 2;

            const distToBoss = Math.hypot(this.enemy.x - orb.x, this.enemy.y - orb.y);
            if (distToBoss < 50) {
                const healAmount = this.enemy.maxHp * (healPct / 100);
                const oldHp = this.enemy.hp;
                this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + healAmount);

                io.to(`zone_${this.enemy.zone}`).emit('enemyHealed', { 
                    id: this.enemy.id, 
                    hp: this.enemy.hp, 
                    amount: Math.max(0, this.enemy.hp - oldHp) 
                });

                io.to(`zone_${this.enemy.zone}`).emit('enemyDead', { id: oid });
                delete this.state.enemies[oid];
                return;
            }

            const { players: nearbyPlayers } = grid.getNearbyEntities(orb.x, orb.y, this.enemy.zone);
            for (const p of nearbyPlayers) {
                if (p.zone === this.enemy.zone && !p.isDead) {
                    const distToP = Math.hypot(p.x - orb.x, p.y - orb.y);
                    if (distToP <= 60) {
                        p.lastCombatTime = Date.now();
                        if (p.shield >= dmg) p.shield -= dmg;
                        else { p.hp -= (dmg - p.shield); p.shield = 0; }
                        if (p.hp < 0) p.hp = 0;
                        if (p.hp <= 0) this._killPlayer(p, io);

                        if (p.reflectActive && !p.isInvulnerable) {
                            const reflectMult = 0.8;
                            const reflectedDmg = Math.round(dmg * reflectMult);
                            if (reflectedDmg > 0) {
                                if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                                else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                                if (this.enemy.hp < 0) this.enemy.hp = 0;
                                io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', {
                                    id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield
                                });
                            }
                        }

                        io.to(p.socketId).emit('environmentDamage', { damage: dmg });
                        io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                            id: p.socketId, 
                            hp: Math.ceil(p.hp), 
                            shield: Math.ceil(p.shield),
                            isDead: p.isDead
                        });

                        io.to(`zone_${this.enemy.zone}`).emit('enemyDead', { id: oid });
                        delete this.state.enemies[oid];
                        
                        io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
                            msg: `💧 ¡Orbe de agua interceptada! Evitaste que cure al Boss.`, 
                            type: "info" 
                        });
                        break;
                    }
                }
            }
        });
    }

    let shouldActivate = false;
    if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
        if (mech.activationMode === "time") {
            shouldActivate = true;
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
        this._isDefenseSkillActive = true;

        state.endTime = now + (mech.duration || 20000);
        state.orbs = [];
        
        if (mech.activationMode !== "time") {
            state.nextReadyTime = now + (mech.cooldown || 30000);
        }

        const orbCount = mech.orbCount || 4;
        const radius = mech.spawnRadius || 500;

        for (let i = 0; i < orbCount; i++) {
            const angle = (i / orbCount) * Math.PI * 2 + (Math.random() * 0.5);
            const ox = this.enemy.x + Math.cos(angle) * radius;
            const oy = this.enemy.y + Math.sin(angle) * radius;
            const orbId = `orb_${this.enemy.id}_${i}_${Date.now()}`;

            const orbObj = {
                id: orbId,
                type: 201,
                zone: this.enemy.zone,
                name: "Orbe de Agua",
                x: ox,
                y: oy,
                startX: ox,
                startY: oy,
                hp: 9999,
                maxHp: 9999,
                shield: 0,
                maxShield: 0,
                rotation: angle + Math.PI,
                lastHit: 0,
                isInvulnerable: true
            };

            this.state.enemies[orbId] = orbObj;
            state.orbs.push(orbId);

            io.to(`zone_${this.enemy.zone}`).emit('enemySpawn', orbObj);
        }

        io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
            msg: `💧 ¡El Boss invoca Orbes de Agua! ¡Intercéptalas antes de que lo curen! 💧`, 
            type: "warning" 
        });
    }
}

function _handleDuplicadoLogic(mech, mId, now, io) {
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || { 
        nextReadyTime: now + (mech.startDelay || 0), 
        isActive: false, 
        endTime: 0,
        triggeredHPs: {},
        combatStartTime: null
    };
    this.enemy.defState[mId] = state;

    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;

    if (!this._inCombat) {
        state.triggeredHPs = {};
        state.combatStartTime = null;
        state.nextReadyTime = now + (mech.startDelay || 0);
        state.isActive = false;
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

    if (state.isActive) {
        if (now >= state.endTime) {
            state.isActive = false;
            if (mech.activationMode !== "time") {
                state.nextReadyTime = now + (mech.cooldown || 30000);
            }
        }
    }

    let shouldActivate = false;
    if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
        if (mech.activationMode === "time") {
            shouldActivate = true;
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
        let duration = Number(mech.cloneDuration) || 8000;
        state.endTime = now + duration;
        if (mech.activationMode !== "time") {
            state.nextReadyTime = now + (mech.cooldown || 30000);
        }

        const cloneCount = Number(mech.cloneCount) || 3;
        const radius = Number(mech.spawnRadius) || 150;
        const CloneAI = require('../CloneAI');

        io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
            msg: `👥 ¡El enemigo se ha duplicado! Cuidado con los clones.`, 
            type: "warning" 
        });

        const clonesList = mech.clonesList || [];

        for (let i = 0; i < cloneCount; i++) {
            const angle = (i / cloneCount) * Math.PI * 2 + (Math.random() * 0.5);
            const cx = this.enemy.x + Math.cos(angle) * radius;
            const cy = this.enemy.y + Math.sin(angle) * radius;
            const cloneId = `clone_${this.enemy.id}_${i}_${Date.now()}`;

            const customClone = clonesList[i] || { hp: 1000, shield: 200, role: "damage", value: 500 };
            const isHeal = customClone.role === "heal";

            const cloneObj = {
                id: cloneId,
                type: this.enemy.type,
                zone: this.enemy.zone,
                name: isHeal ? `💚 ${this.enemy.name} (CLON CURADOR)` : `💥 ${this.enemy.name} (CLON DE DAÑO)`,
                role: customClone.role,
                x: cx,
                y: cy,
                startX: cx,
                startY: cy,
                hp: Number(customClone.hp) || 1000,
                maxHp: Number(customClone.hp) || 1000,
                shield: Number(customClone.shield) || 0,
                maxShield: Number(customClone.shield) || 0,
                rotation: angle,
                lastHit: 0,
                isInvulnerable: false
            };

            const cloneConfig = {
                aggressive: true,
                cloneSpeed: Number(mech.cloneSpeed) || 200,
                cloneDuration: duration,
                cloneExplosionDamage: isHeal ? 0 : (Number(customClone.value) || 500),
                cloneHealAmount: isHeal ? (Number(customClone.value) || 1000) : 0,
                cloneExplodeOnExpiry: mech.cloneExplodeOnExpiry !== false,
                parentEnemyId: this.enemy.id,
                attackCooldownMs: Number(customClone.attackCooldownMs) || 2000
            };

            cloneObj.ai = new CloneAI(cloneObj, cloneConfig, this.state);
            this.state.enemies[cloneId] = cloneObj;

            const { ai, ...spawnData } = cloneObj;
            io.to(`zone_${this.enemy.zone}`).emit('enemySpawn', spawnData);
        }
    }
}

function _handleSummoningLogic(mech, mId, now, io) {
    if (!this.enemy.defState) this.enemy.defState = {};
    const state = this.enemy.defState[mId] || { 
        nextReadyTime: now + (mech.startDelay || 0), 
        isActive: false, 
        endTime: 0,
        triggeredHPs: {},
        combatStartTime: null
    };
    this.enemy.defState[mId] = state;

    const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;

    if (!this._inCombat) {
        state.triggeredHPs = {};
        state.combatStartTime = null;
        state.nextReadyTime = now + (mech.startDelay || 0);
        state.isActive = false;
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

    if (state.isActive) {
        if (mech.summonDurationMode === "timed" && now >= state.endTime) {
            state.isActive = false;
            if (mech.activationMode !== "time") {
                state.nextReadyTime = now + (mech.cooldown || 30000);
            }
        }
    }

    let shouldActivate = false;
    if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
        if (mech.activationMode === "time") {
            shouldActivate = true;
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
        let duration = Number(mech.summonDurationMs) || 10000;
        state.endTime = now + duration;
        if (mech.activationMode !== "time") {
            state.nextReadyTime = now + (mech.cooldown || 30000);
        }

        const summonCount = Number(mech.summonCount) || 3;
        const radius = Number(mech.spawnRadius) || 150;

        io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { 
            msg: `🧟 ¡El enemigo ha invocado refuerzos! 🧟`, 
            type: "warning" 
        });

        const summonsList = mech.summonsList || [];

        for (let i = 0; i < summonCount; i++) {
            const angle = (i / summonCount) * Math.PI * 2 + (Math.random() * 0.5);
            const sx = this.enemy.x + Math.cos(angle) * radius;
            const sy = this.enemy.y + Math.sin(angle) * radius;
            const summonId = `summon_${this.enemy.id}_${i}_${Date.now()}`;

            const choice = summonsList[i] || "random_base";
            let selectedType = null;

            const allTypes = Object.keys(this.state.SERVER_CONFIG.enemyModels).filter(id => !id.includes('-'));
            
            if (choice === "random") {
                selectedType = allTypes[Math.floor(Math.random() * allTypes.length)];
            } else if (choice === "random_base") {
                const regularTypes = allTypes.filter(id => parseInt(id) < 100);
                selectedType = regularTypes[Math.floor(Math.random() * regularTypes.length)];
            } else if (choice === "random_boss") {
                const bossTypes = allTypes.filter(id => parseInt(id) >= 100);
                selectedType = bossTypes[Math.floor(Math.random() * bossTypes.length)];
            } else if (choice === "random_tier_a") {
                const bases = allTypes.filter(id => parseInt(id) < 100);
                const tierATypes = bases.map(id => `${id}-A`).filter(id => this.state.SERVER_CONFIG.enemyModels[id]);
                selectedType = tierATypes[Math.floor(Math.random() * tierATypes.length)];
            } else if (choice === "random_tier_b") {
                const bases = allTypes.filter(id => parseInt(id) < 100);
                const tierBTypes = bases.map(id => `${id}-B`).filter(id => this.state.SERVER_CONFIG.enemyModels[id]);
                selectedType = tierBTypes[Math.floor(Math.random() * tierBTypes.length)];
            } else if (choice === "random_tier_c") {
                const bases = allTypes.filter(id => parseInt(id) < 100);
                const tierCTypes = bases.map(id => `${id}-C`).filter(id => this.state.SERVER_CONFIG.enemyModels[id]);
                selectedType = tierCTypes[Math.floor(Math.random() * tierCTypes.length)];
            } else if (choice === "random_tier_d") {
                const bases = allTypes.filter(id => parseInt(id) < 100);
                const tierDTypes = bases.map(id => `${id}-D`).filter(id => this.state.SERVER_CONFIG.enemyModels[id]);
                selectedType = tierDTypes[Math.floor(Math.random() * tierDTypes.length)];
            } else {
                selectedType = choice;
            }

            if (!selectedType || !this.state.SERVER_CONFIG.enemyModels[selectedType]) {
                selectedType = "1";
            }

            const enemyCfg = this.state.SERVER_CONFIG.enemyModels[selectedType];
            
            const summonObj = {
                id: summonId,
                type: isNaN(parseInt(selectedType)) ? selectedType : parseInt(selectedType),
                typeString: selectedType.toString(),
                zone: this.enemy.zone,
                name: `🧟 ${enemyCfg.name || 'Invocación'}`,
                x: sx,
                y: sy,
                startX: sx,
                startY: sy,
                hp: Number(enemyCfg.hp) || 1000,
                maxHp: Number(enemyCfg.hp) || 1000,
                shield: Number(enemyCfg.shield) || 0,
                maxShield: Number(enemyCfg.shield) || 0,
                rotation: angle,
                lastHit: 0,
                isInvulnerable: false
            };

            const moveAI = enemyCfg.movementAI || 'chase';
            let BrainClass;
            try {
                BrainClass = require(`../${moveAI.charAt(0).toUpperCase() + moveAI.slice(1)}AI`);
            } catch(e) {
                BrainClass = require('../ChaseAI');
            }
            summonObj.ai = new BrainClass(summonObj, enemyCfg, this.state);
            this.state.enemies[summonId] = summonObj;

            if (mech.summonDurationMode === "timed") {
                setTimeout(() => {
                    if (this.state.enemies[summonId]) {
                        io.to(`zone_${this.enemy.zone}`).emit('enemyDead', { id: summonId });
                        delete this.state.enemies[summonId];
                    }
                }, duration);
            }

            const { ai, ...spawnData } = summonObj;
            io.to(`zone_${this.enemy.zone}`).emit('enemySpawn', spawnData);
        }
    }
}

module.exports = {
    _handleBossPillarsLogic,
    _handleBossColorsLogic,
    _handleBossWaterOrbsLogic,
    _handleDuplicadoLogic,
    _handleSummoningLogic
};
