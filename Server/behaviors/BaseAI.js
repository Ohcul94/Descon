const normalizeZone = (z) => {
    if (z === undefined || z === null) return 1;
    if (typeof z === 'string') {
        if (z.startsWith('extract_')) {
            const parts = z.split('_');
            return parseInt(parts[1]) || 10;
        }
        if (z.startsWith('dungeon_') || z.startsWith('dungeon')) {
            return 99;
        }
        if (!isNaN(z) && z.trim() !== '') {
            return Number(z);
        }
        return z;
    }
    return z;
};

module.exports = class BaseAI {
    constructor(enemy, config, state) {
        this.enemy = enemy;
        this.config = config;
        this.state = state;
        this.lastAction = 0;
        this._isDefenseSkillActive = false; // v269.195: Flag interno único para IA
    }

    update(grid, players, now, io) {
        const cfg = this.config;
        if (!cfg) return;

        // v3.0: Soporte de Leash Range (Rango de Retorno al Spawn) e Interrupción de Retorno
        if (this.enemy.startX === undefined) this.enemy.startX = this.enemy.x;
        if (this.enemy.startY === undefined) this.enemy.startY = this.enemy.y;

        const leashRange = Number(cfg.leashRange) || 0;

        // v266.999: Detección de Agresividad Extrema Ambiental (Búsqueda Ultra-Robusta)
        let zoneId = this.enemy.zone;
        if (typeof zoneId === 'string' && zoneId.startsWith('extract_')) {
            zoneId = parseInt(zoneId.split('_')[1]) || 10;
        } else if (typeof zoneId === 'string' && zoneId.startsWith('dungeon')) {
            zoneId = 99;
        }
        const currentConfig = (this.state && this.state.SERVER_CONFIG) ? this.state.SERVER_CONFIG : {};
        const maps = currentConfig.mapsConfig || currentConfig.maps || currentConfig.mapData || {};
        
        // Intentar encontrar el mapa por ID (2), String ("2") o Nombre ("Mapa 2")
        let mapCfg = maps[zoneId] || (zoneId !== undefined ? maps[zoneId.toString()] : null);
        if (!mapCfg && zoneId !== undefined) {
            mapCfg = Object.values(maps).find(m => m.name === zoneId || m.name === `Mapa ${zoneId}` || m.name === zoneId.toString());
        }

        const extremeAggro = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'extreme_aggression') : null;
        const multiplicadorMech = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'multiplicador') : null;
        const multiplicadorMult = multiplicadorMech ? (parseFloat(multiplicadorMech.multiplier) || 1) : 1;
        
        this.ambienceBoost = extremeAggro || null;
        this.multiplicadorMult = multiplicadorMult;
        this.damageMult = (extremeAggro ? (parseFloat(extremeAggro.damageMult) || 1) : 1) * multiplicadorMult;
        
        // v266.999: Si hay ambiente extremo, el bicho ES agresivo por definición
        const isAggressive = (this.ambienceBoost) ? true : (cfg.aggressive === true);
        this.enemy.isAggressive = isAggressive; // Restaurar propiedad para otros sistemas

        // v266.999: Inyectar velocidad ambiental dinámicamente
        if (!this._baseSpeed) this._baseSpeed = cfg.speed || 3.5;
        const speedMult = (this.ambienceBoost ? (parseFloat(this.ambienceBoost.speedMult) || 1) : 1) * multiplicadorMult;
        cfg.speed = this._baseSpeed * speedMult;
        
        // v266.580: Inicialización de seguridad para nuevos enemigos
        if (this.enemy.lastSuccessHit === undefined) this.enemy.lastSuccessHit = 0;
        if (this.enemy.lastHit === undefined) this.enemy.lastHit = 0;

        // Búsqueda de objetivo potencial (Visión Pasiva)
        let potentialTarget = this.getNearestPlayer(grid, players);
        
        // Lógica de AGRO (Quién tiene la atención del bicho)
        let activeTarget = null;
        let isRevenge = false;

        const altarDefenseConfig = this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.gameModes && this.state.SERVER_CONFIG.gameModes.altar_defense;
        const isAltarZone = altarDefenseConfig && altarDefenseConfig.maps && altarDefenseConfig.maps.map(Number).includes(Number(this.enemy.zone));
        const focusTarget = this.enemy.focusTarget || 'players'; // 'players' o 'altar'

        // 1. REGLA PRIORITARIA: Provocación (Taunt)
        if (this.enemy.forcedTarget && players[this.enemy.forcedTarget] && now < this.enemy.tauntEndTime) {
            const tauntPlayer = players[this.enemy.forcedTarget];
            if (!tauntPlayer.isDead && !tauntPlayer.isInvisible) {
                activeTarget = tauntPlayer;
            }
        }

        // 2. Si el foco es Altar, ir directamente al altar (ignorando proximidad ordinaria)
        if (!activeTarget && focusTarget === 'altar' && isAltarZone && altarDefenseConfig.altarPos) {
            const altarHp = (this.state.altarState ? this.state.altarState.hp : 1) || 1;
            if (altarHp > 0) {
                activeTarget = {
                    id: "altar",
                    x: Number(altarDefenseConfig.altarPos.x) || 5000,
                    y: Number(altarDefenseConfig.altarPos.y) || 5000,
                    hp: altarHp,
                    isDead: false,
                    isInvisible: false
                };
            }
        }

        // 2.5. Si el foco es Altar con Aggro, intentar priorizar jugadores en rango de visión; si no, ir al Altar
        if (!activeTarget && focusTarget === 'altar_aggro' && isAltarZone && altarDefenseConfig.altarPos) {
            let playerTarget = null;
            
            // A. Primero revisar si hay un agresor por venganza activa
            if (this.enemy.lastHitter && players[this.enemy.lastHitter]) {
                const idleTime = now - (this.enemy.lastHit || 0);
                const idleLimit = (this.ambienceBoost) ? 30000 : (cfg.chaseIdleTimeout || 10000); 
                if (idleTime < idleLimit) {
                    const p = players[this.enemy.lastHitter];
                    if (!p.isDead && !p.isInvisible) {
                        playerTarget = p;
                        isRevenge = true;
                    }
                }
            }
            
            // B. Si no hay venganza, buscar el jugador más cercano en el rango de visión
            if (!playerTarget && potentialTarget) {
                const distToPlayer = Math.hypot(potentialTarget.x - this.enemy.x, potentialTarget.y - this.enemy.y);
                const configVision = cfg ? Number(cfg.visionRange) : 0;
                const visionRange = this.ambienceBoost ? 50000 : (configVision > 0 ? configVision : (this.enemy.isHorde ? 10000 : 800));
                if (distToPlayer <= visionRange && !potentialTarget.isDead && !potentialTarget.isInvisible) {
                    playerTarget = potentialTarget;
                }
            }
            
            if (playerTarget) {
                activeTarget = playerTarget;
            } else {
                const altarHp = (this.state.altarState ? this.state.altarState.hp : 1) || 1;
                if (altarHp > 0) {
                    activeTarget = {
                        id: "altar",
                        x: Number(altarDefenseConfig.altarPos.x) || 5000,
                        y: Number(altarDefenseConfig.altarPos.y) || 5000,
                        hp: altarHp,
                        isDead: false,
                        isInvisible: false
                    };
                }
            }
        }

        // 3. Si el foco es Players (o si el altar ya fue destruido), aplicar agro de represalia y proximidad
        if (!activeTarget) {
            // REPRESALIA: Prioridad al que me pegó (Si el idleLimit no expiró)
            if (this.enemy.lastHitter && players[this.enemy.lastHitter]) {
                const p = players[this.enemy.lastHitter];
                const idleTime = now - (this.enemy.lastHit || 0);
                
                // Si chaseIdleTimeout es 0 en el panel, significa desactivado (sin timeout de abandono)
                const idleLimit = cfg.chaseIdleTimeout !== undefined ? Number(cfg.chaseIdleTimeout) : 10000;
                
                const distToP = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                const configVision = cfg ? Number(cfg.visionRange) : 0;
                const visionRange = this.ambienceBoost ? 50000 : (configVision > 0 ? configVision : (this.enemy.isHorde ? 10000 : 800));

                const outOfSight = cfg.stopOnOutOfSight && distToP > visionRange;
                const idleExpired = idleLimit > 0 && idleTime >= idleLimit;

                if (!outOfSight && !idleExpired) {
                    activeTarget = p;
                    isRevenge = true;
                } else {
                    this.enemy.lastHitter = null; 
                }
            }

            // PROXIMIDAD: Si soy agresivo y no tengo venganza pendiente, busco al más cercano
            if (!activeTarget && isAggressive) {
                activeTarget = potentialTarget;
            }
        }

        // 4. FALLBACK DE ALTAR DEFENSE: Si es zona de Altar Defense y aún no hay target, apuntar al altar como último recurso
        if (!activeTarget && isAltarZone && altarDefenseConfig.altarPos) {
            const altarHp = (this.state.altarState ? this.state.altarState.hp : 1) || 1;
            if (altarHp > 0) {
                activeTarget = {
                    id: "altar",
                    x: Number(altarDefenseConfig.altarPos.x) || 5000,
                    y: Number(altarDefenseConfig.altarPos.y) || 5000,
                    hp: altarHp,
                    isDead: false,
                    isInvisible: false
                };
            }
        }

        // v3.0: EVALUAR INTERRUPCIÓN DEL REGRESO AL SPAWN (Soft Leash)
        if (this.enemy.returningToSpawn && activeTarget) {
            const targetDistFromSpawn = Math.hypot(activeTarget.x - this.enemy.startX, activeTarget.y - this.enemy.startY);
            const targetDistToEnemy = Math.hypot(activeTarget.x - this.enemy.x, activeTarget.y - this.enemy.y);
            const configVision = cfg ? Number(cfg.visionRange) : 0;
            const visionRange = this.ambienceBoost ? 50000 : (configVision > 0 ? configVision : (this.enemy.isHorde ? 10000 : 800));

            // Si el target está dentro del rango territorial de spawn y está al alcance de visión o le acaba de pegar
            if (targetDistFromSpawn <= leashRange && (targetDistToEnemy < visionRange || isRevenge)) {
                this.enemy.returningToSpawn = false; // Interrumpir el regreso
            }
        }

        // v3.0: EVALUAR EXCESO DE RANGO (Leash Range Check)
        if (leashRange > 0 && !this.enemy.returningToSpawn && !this._isDefenseSkillActive) {
            const distFromSpawn = Math.hypot(this.enemy.x - this.enemy.startX, this.enemy.y - this.enemy.startY);
            
            // También verificar si el target actual se paró fuera del leashRange del bicho (kiteo)
            let isTargetOutOfLeash = false;
            if (activeTarget) {
                const targetDistFromSpawn = Math.hypot(activeTarget.x - this.enemy.startX, activeTarget.y - this.enemy.startY);
                if (targetDistFromSpawn > leashRange) {
                    isTargetOutOfLeash = true;
                }
            }

            if (distFromSpawn > leashRange || isTargetOutOfLeash) {
                this.enemy.returningToSpawn = true;
                this.enemy.lastHitter = null; // Olvidar agresor para forzar retorno
                activeTarget = null;
            }
        }

        // v3.9: Determinar si el bicho está en combate activo
        const lastCombatTime = Math.max(this.enemy.lastHit || 0, this.enemy.lastSuccessHit || 0);
        const delayMs = cfg.regenDelayMs !== undefined ? Number(cfg.regenDelayMs) : (cfg.regenDelaySec !== undefined ? Number(cfg.regenDelaySec) * 1000 : 5000);
        
        // En combate si ha recibido/hecho daño hace poco, o si tiene un target activo al que está persiguiendo (y no es el altar)
        const hasActivePlayerTarget = activeTarget && activeTarget.id !== "altar" && !activeTarget.isDead && !activeTarget.isInvisible;
        this._inCombat = (!this.enemy.returningToSpawn) && (((now - lastCombatTime) < delayMs) || !!hasActivePlayerTarget);

        // Lógica de Regeneración Autoritaria (Fuera de Combate / Ocioso)
        if (!this._inCombat) {
            if (this.enemy.lastRegenTime === undefined) this.enemy.lastRegenTime = now;
            const regenInterval = cfg.regenIntervalMs !== undefined ? Number(cfg.regenIntervalMs) : 1000;
            const elapsedMs = now - this.enemy.lastRegenTime;

            if (elapsedMs >= regenInterval) {
                const ticks = Math.floor(elapsedMs / regenInterval);
                this.enemy.lastRegenTime = now - (elapsedMs % regenInterval); // Mantener el remanente de ms
                const hpRegen = cfg.hpRegenPercent !== undefined ? Number(cfg.hpRegenPercent) : 3;
                const shieldRegen = cfg.shieldRegenPercent !== undefined ? Number(cfg.shieldRegenPercent) : 5;
                
                const oldHp = this.enemy.hp;
                const oldShield = this.enemy.shield;
                let changed = false;

                if (hpRegen > 0 && this.enemy.hp < this.enemy.maxHp) {
                    this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + (this.enemy.maxHp * (hpRegen / 100) * ticks));
                    if (this.enemy.hp !== oldHp) changed = true;
                }
                if (shieldRegen > 0 && this.enemy.shield < this.enemy.maxShield) {
                    this.enemy.shield = Math.min(this.enemy.maxShield, this.enemy.shield + (this.enemy.maxShield * (shieldRegen / 100) * ticks));
                    if (this.enemy.shield !== oldShield) changed = true;
                }

                if (changed) {
                    io.to(`zone_${this.enemy.zone}`).emit('enemyHealed', { 
                        id: this.enemy.id, 
                        hp: this.enemy.hp, 
                        shield: this.enemy.shield,
                        amount: Math.max(0, this.enemy.hp - oldHp) 
                    });
                }
            }
        } else {
            // Si está en combate, actualizar lastRegenTime para evitar acumulaciones masivas al salir de combate
            this.enemy.lastRegenTime = now;
        }

        // v269.195: PROCESAR DEFENSAS (Solo si está en combate activo)
        if (this._inCombat) {
            const defMechanics = cfg.defenseMechanics || [];
            defMechanics.forEach((mech, idx) => {
                const mId = `def_${idx}`;
                if (mech.type === "invulnerability") {
                    this._handleInvulnerabilityLogic(mech, mId, now, io);
                } else if (mech.type === "boss_pillars") {
                    this._handleBossPillarsLogic(mech, mId, now, io);
                } else if (mech.type === "boss_colors") {
                    this._handleBossColorsLogic(mech, mId, now, io, players);
                } else if (mech.type === "boss_water_orbs") {
                    this._handleBossWaterOrbsLogic(mech, mId, now, io, grid, players);
                } else if (mech.type === "invisibility") {
                    this._handleInvisibilityLogic(mech, mId, now, io);
                } else if (mech.type === "duplicado") {
                    this._handleDuplicadoLogic(mech, mId, now, io);
                } else if (mech.type === "wall_dome") {
                    this._handleWallDomeLogic(mech, mId, now, io);
                } else if (mech.type && mech.type.startsWith("aura_")) {
                    this._handleAuraLogic(mech, mId, now, io, grid, players);
                }
            });
        } else {
            // v3.9.1: Si sale de combate, asegurar desactivar cualquier aura visual activa
            const defMechanics = cfg.defenseMechanics || [];
            defMechanics.forEach((mech, idx) => {
                const mId = `def_${idx}`;
                if (this.enemy.auraState && this.enemy.auraState[mId] && this.enemy.auraState[mId].isActive) {
                    this.enemy.auraState[mId].isActive = false;
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAura', {
                        id: this.enemy.id, mId: mId, active: false
                    });
                }
                if (mech.type === "wall_dome" && this.enemy.defState && this.enemy.defState[mId] && this.enemy.defState[mId].isActive) {
                    this.enemy.defState[mId].isActive = false;
                    io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", { 
                        id: this.enemy.id, 
                        action: "wall_dome_end",
                        mId: mId
                    });
                }
            });
        }

        // v3.0: PROCESAR REGRESO AL SPAWN
        if (this.enemy.returningToSpawn) {
            const distToSpawn = Math.hypot(this.enemy.startX - this.enemy.x, this.enemy.startY - this.enemy.y);
            if (distToSpawn < 50) {
                this.enemy.returningToSpawn = false;
                this.enemy.isMoving = false;
            } else {
                this.enemy.isMoving = true;
                const angleToSpawn = Math.atan2(this.enemy.startY - this.enemy.y, this.enemy.startX - this.enemy.x);
                const speed = this.getSpeed();
                this.enemy.x += Math.cos(angleToSpawn) * speed;
                this.enemy.y += Math.sin(angleToSpawn) * speed;
                this.enemy.rotation = angleToSpawn + Math.PI / 2;
                
                // Regeneración masiva en el regreso (estilo MMO Evasión Fuera de Combate)
                if (this.enemy.lastRegenTime === undefined) this.enemy.lastRegenTime = 0;
                const regenInterval = cfg.regenIntervalMs !== undefined ? Number(cfg.regenIntervalMs) : 1000;
                
                if (now - this.enemy.lastRegenTime >= regenInterval) {
                    this.enemy.lastRegenTime = now;
                    const hpRegen = cfg.hpRegenPercent !== undefined ? Number(cfg.hpRegenPercent) : 3;
                    const shieldRegen = cfg.shieldRegenPercent !== undefined ? Number(cfg.shieldRegenPercent) : 5;
                    
                    const oldHp = this.enemy.hp;
                    const oldShield = this.enemy.shield;
                    let changed = false;

                    if (hpRegen > 0 && this.enemy.hp < this.enemy.maxHp) {
                        this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + (this.enemy.maxHp * (hpRegen / 100)));
                        if (this.enemy.hp !== oldHp) changed = true;
                    }
                    if (shieldRegen > 0 && this.enemy.shield < this.enemy.maxShield) {
                        this.enemy.shield = Math.min(this.enemy.maxShield, this.enemy.shield + (this.enemy.maxShield * (shieldRegen / 100)));
                        if (this.enemy.shield !== oldShield) changed = true;
                    }

                    if (changed) {
                        io.to(`zone_${this.enemy.zone}`).emit('enemyHealed', { 
                            id: this.enemy.id, 
                            hp: this.enemy.hp, 
                            shield: this.enemy.shield,
                            amount: Math.max(0, this.enemy.hp - oldHp) 
                        });
                    }
                }
                return; // Omitir el resto del procesamiento de ataque
            }
        }

        // v266.970: Lógica de Fases de Movimiento (Kamikaze Check)
        const phases = cfg.movementPhases || [];
        const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
        const kamikazePhase = phases.find(p => p.type === 'kamikaze');

        if (kamikazePhase && hpPercent <= (kamikazePhase.activationHP || 30)) {
            if (!this.enemy.isKamikazeActive) {
                this.enemy.isKamikazeActive = true;
                this.enemy.kamikazeStartTime = now;
                this.enemy.isRamming = true;
                
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id, action: "kamikaze_start", duration: kamikazePhase.duration || 5000
                });
            }
        }

        // v266.999: Si hay mecánicas activas O es Agresividad Extrema, NO PODEMOS soltar el flujo
        const hasActiveMech = this.enemy.mechState && Object.values(this.enemy.mechState).some(m => m.isActive || m.isCharging || m.isLocked || m.isFiring);
        const isExtreme = !!this.ambienceBoost;
        
        const isProwler = (cfg.movementAI === 'prowler') || (cfg.movementPhases && cfg.movementPhases[0] && cfg.movementPhases[0].type === 'prowler');
        if ((!activeTarget || activeTarget.isDead || activeTarget.isInvisible) && !hasActiveMech && !isExtreme && !isProwler) {
            this.enemy.isMoving = false;
            return;
        }
        
        this.enemy.isMoving = true;

        // v266.999: Valores seguros si el target desapareció pero el ataque sigue
        const dist = activeTarget ? Math.hypot(activeTarget.x - this.enemy.x, activeTarget.y - this.enemy.y) : 99999;
        const targetAngle = activeTarget ? Math.atan2(activeTarget.y - this.enemy.y, activeTarget.x - this.enemy.x) : this.enemy.rotation;

        // Lógica de Persistencia (Basada en Dashboard)
        const configVision = cfg ? Number(cfg.visionRange) : 0;
        const visionRange = configVision > 0 ? configVision : 800;
        const canSee = activeTarget && dist <= visionRange;
        if (!isExtreme && !cfg.chaseUntilDeath && cfg.stopOnOutOfSight && !canSee && !hasActiveMech && !isProwler) {
            this.enemy.isMoving = false;
            return;
        }

        // v266.975: Ejecución del Estado Kamikaze (Prioridad sobre combate normal)
        if (this.enemy.isKamikazeActive) {
            if (this.enemy.isHooking) return;
            const kP = (cfg.movementPhases || []).find(p => p.type === 'kamikaze') || {};
            let speed = (kP.speed !== undefined) ? (kP.speed * 0.033) : (cfg.speed || 3.5) * 1.5;
            const duration = kP.duration || 5000;

            if (now - this.enemy.kamikazeStartTime > duration || (activeTarget && dist < 60)) {
                this.enemy.hp = 0;
                this.enemy.forceExplosion = true;
                return;
            }

            this.enemy.x += Math.cos(targetAngle) * speed;
            this.enemy.y += Math.sin(targetAngle) * speed;
            this.enemy.rotation = targetAngle + Math.PI / 2;
            return; 
        }
        
        // v266.999: Rotación de Cuerpo - Mirar SIEMPRE al objetivo (v266.999) (Ignorar si está canalizando, disparando o en retraso de re-apuntado)
        const hasCastingMech = this.enemy.mechState && Object.values(this.enemy.mechState).some(m => m.isCharging || m.isLocked || m.isFiring || (m.aimReadyTime && now < m.aimReadyTime));
        if (!hasCastingMech) {
            if (this.enemy.rotation === undefined) this.enemy.rotation = targetAngle;
            const turnSpeed = 5.0; // Velocidad de giro del cuerpo
            const delta = 0.1; 
            let diff = targetAngle - this.enemy.rotation;
            while (diff < -Math.PI) diff += Math.PI * 2;
            while (diff > Math.PI) diff -= Math.PI * 2;
            
            const step = turnSpeed * delta;
            if (Math.abs(diff) < step) {
                this.enemy.rotation = targetAngle;
            } else {
                this.enemy.rotation += Math.sign(diff) * step;
            }
        }

        // v269.120: BLOQUEO TOTAL DURANTE EL GANCHO (Inmovilidad y Silencio de Armas)
        if (this.enemy.isHooking) {
            this.enemy.rotation = targetAngle + Math.PI / 2;
            this.enemy.isMoving = false;
            return;
        }

        // v268.810: Procesar combate y movimiento
        this.applyCombatLogic(activeTarget, dist, targetAngle, now, io, grid, players);
        
        // Bloquear movimiento físico en todas las IAs si está cargando/canalizando un ataque
        const isChargingAttack = this.enemy.mechState && Object.values(this.enemy.mechState).some(m => m.isCharging);
        if (isChargingAttack) {
            this.enemy.isMoving = false;
        } else if (activeTarget) {
            this.enemy.isMoving = true;
            this.applyMovementLogic(activeTarget, dist, targetAngle, now, io);
        } else if (isProwler) {
            this.enemy.isMoving = true;
            this.applyMovementLogic(null, 0, 0, now, io);
        }

        // v3.6: Forzar rotación fija si hay una mecánica activa que restrinja el apuntado (por aimDelayMs, lock o fire)
        let forcedRotation = null;
        if (this.enemy.mechState) {
            for (const mId in this.enemy.mechState) {
                const m = this.enemy.mechState[mId];
                if (m.isLocked || m.isFiring || (m.aimReadyTime && now < m.aimReadyTime)) {
                    if (m.lockedAngle !== undefined) {
                        forcedRotation = m.lockedAngle + Math.PI / 2;
                    }
                }
            }
        }
        if (forcedRotation !== null) {
            this.enemy.rotation = forcedRotation;
        }

    }


    getNearestPlayer(grid, players) {
        // v303.0: Retornar al jugador provocador si el taunt sigue activo
        if (this.enemy.forcedTarget && players[this.enemy.forcedTarget] && Date.now() < this.enemy.tauntEndTime) {
            const tauntPlayer = players[this.enemy.forcedTarget];
            if (!tauntPlayer.isDead && !tauntPlayer.isInvisible) {
                return tauntPlayer;
            }
        }

        let closest = null;
        // v3.0: Rango de visión dinámico configurable desde el Panel de Admin
        const configVision = this.config ? Number(this.config.visionRange) : 0;
        const visionRange = this.ambienceBoost ? 50000 : (configVision > 0 ? configVision : (this.enemy.isHorde ? 10000 : 800));
        let minDist = visionRange; 
        
        // v266.999: Búsqueda exhaustiva sin Grid si es extremo
        const targetList = Object.values(players || {});
        const maps = (this.state && this.state.SERVER_CONFIG) ? (this.state.SERVER_CONFIG.mapsConfig || this.state.SERVER_CONFIG.maps || this.state.SERVER_CONFIG.mapData || {}) : {};
        
        for (const p of targetList) {
            // v269.71: Ignorar jugadores si no soy agresivo (considerando ambiente extremo) y no estoy en combate
            if (!this.enemy.isAggressive && !this._inCombat) continue;
            
            // v266.999: Búsqueda Global (Si el jugador está en una zona extrema, el bicho lo detecta)
            let pZone = parseInt(p.zone);
            if (isNaN(pZone)) {
                if (typeof p.zone === 'string' && p.zone.startsWith('extract_')) {
                    pZone = parseInt(p.zone.split('_')[1]) || 10;
                } else if (typeof p.zone === 'string' && p.zone.startsWith('dungeon')) {
                    pZone = 99;
                } else {
                    pZone = 0;
                }
            }

            let eZone = parseInt(this.enemy.zone);
            if (isNaN(eZone)) {
                if (typeof this.enemy.zone === 'string' && this.enemy.zone.startsWith('extract_')) {
                    eZone = parseInt(this.enemy.zone.split('_')[1]) || 10;
                } else if (typeof this.enemy.zone === 'string' && this.enemy.zone.startsWith('dungeon')) {
                    eZone = 99;
                } else {
                    eZone = 0;
                }
            }
            
            // Verificamos si la zona del JUGADOR es extrema
            const pMapCfg = maps[pZone] || maps[pZone.toString()];
            const pIsExtreme = (pMapCfg && pMapCfg.ambience && pMapCfg.ambience.some(a => a.type === 'extreme_aggression'));

            if (!p || p.isDead) continue;
            
            // Invisibilidad: Respeto absoluto solicitado por el usuario (v266.999)
            if (p.isInvisible) continue; 
            
            // Si no estamos en la misma zona y la zona del jugador NO es extrema, ignoramos
            const isSameZone = (normalizeZone(p.zone) === normalizeZone(this.enemy.zone));
            if (!isSameZone && !pIsExtreme) continue;

            const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
            if (d < minDist) {
                minDist = d;
                closest = p;
            }
        }
        return closest;
    }

    applyCombatLogic(target, dist, angle, now, io, grid, players) {
        if ((this.enemy.isInvisible || this.enemy.isCamouflaged) && this.enemy.keepAttackingWhenInvis === false) {
            return false;
        }
        // v266.220: Sistema de Rotación de Mecánicas Modulares
        if (!this.enemy.spawnTime) this.enemy.spawnTime = now;
        if (!this.enemy.mechState) this.enemy.mechState = {};

        const mechanics = this.config.mechanics || [];
        let isBusy = false;
        
        // Si no hay mecánicas nuevas, usar el fallback del config raíz (compatibilidad)
        if (mechanics.length === 0) {
            return this._executeMechanic(this.config, "default", target, dist, angle, now, io, players);
        }

        mechanics.forEach((mech, idx) => {
            const mId = `mech_${idx}`;
            const timeSinceSpawn = now - this.enemy.spawnTime;
            if (timeSinceSpawn < (mech.startDelay || 0)) return;

            if (mech.type && mech.type.startsWith("aura_")) {
                this._handleAuraLogic(mech, mId, now, io, grid, players);
            } else if (this._executeMechanic(mech, mId, target, dist, angle, now, io, players)) {
                isBusy = true;
            }
        });

        // v268.800: Procesar mecánicas de Movimiento (Auras)
        const movPhases = this.config.movementPhases || [];
        movPhases.forEach((mech, idx) => {
            const mId = `mov_${idx}`;
            if (mech.type && mech.type.startsWith("aura_")) {
                this._handleAuraLogic(mech, mId, now, io, grid, players);
            }
        });

        return isBusy;
    }

    _handleAuraLogic(mech, mId, now, io, grid, players) {
        if (!this.enemy.auraState) this.enemy.auraState = {};
        const state = this.enemy.auraState[mId] || { nextStartTime: now + (mech.startDelay || 0), isActive: false, endTime: 0, lastTickTime: 0 };

        // 1. Gestión de Ciclo (Activar/Desactivar)
        const threshold = mech.activationHP || 100;
        const currentHPPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
        const hpMet = currentHPPercent <= threshold;

        if (!state.isActive && now >= state.nextStartTime && hpMet) {
            state.isActive = true;
            state.endTime = now + (mech.duration || 5000);
            state.lastTickTime = 0;
            
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAura', {
                id: this.enemy.id, mId: mId, type: mech.type, radius: mech.radius || 200, duration: mech.duration || 5000, active: true
            });
        } else if (state.isActive && now >= state.endTime) {
            state.isActive = false;
            state.nextStartTime = now + (mech.cooldown || 10000);
            
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAura', {
                id: this.enemy.id, mId: mId, active: false
            });
        }

        // 2. Ejecución de Efecto (Ticks para Daño/Cura, Constante para Velocidad)
        if (state.isActive) {
            if (mech.type === "aura_speed") {
                this._applyAuraEffect(mech, grid, players, io);
            } else {
                const interval = mech.intervalMs || 1000;
                if (now - state.lastTickTime >= interval) {
                    state.lastTickTime = now;
                    this._applyAuraEffect(mech, grid, players, io);
                }
            }
        }
        this.enemy.auraState[mId] = state;
    }

    _applyAuraEffect(mech, grid, players, io) {
        const radius = mech.radius || 200;
        const { players: nearbyPlayers, enemies: nearbyEnemies } = grid.getNearbyEntities(this.enemy.x, this.enemy.y, this.enemy.zone);

        if (mech.type === "aura_damage") {
            nearbyPlayers.forEach(p => {
                if (p.zone === this.enemy.zone && !p.isDead) {
                    const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                    if (d <= radius) {
                        const dmg = (mech.damage || 100) * (this.damageMult || 1);
                        p.lastCombatTime = Date.now();
                        if (p.shield >= dmg) p.shield -= dmg;
                        else { p.hp -= (dmg - p.shield); p.shield = 0; }
                        if (p.hp < 0) p.hp = 0;
                        
                        io.to(p.socketId).emit('environmentDamage', { damage: dmg });
                        io.to(`zone_${p.zone}`).emit('playerStatSync', { id: p.socketId, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield) });
                    }
                }
            });
        } else if (mech.type === "aura_heal") {
            const heal = mech.healAmount || 500;
            const affectsEnemies = !!mech.affectsEnemies;
            const affectsBosses = !!mech.affectsBosses;

            // Primero a sí mismo siempre (es el dueño)
            const oldHpOwner = this.enemy.hp;
            this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + heal);
            io.to(`zone_${this.enemy.zone}`).emit('enemyHealed', { 
                id: this.enemy.id, 
                hp: this.enemy.hp, 
                amount: Math.max(0, this.enemy.hp - oldHpOwner) 
            });

            // A otros cercanos
            nearbyEnemies.forEach(e => {
                if (e.id !== this.enemy.id && e.zone === this.enemy.zone && e.hp > 0) {
                    const d = Math.hypot(e.x - this.enemy.x, e.y - this.enemy.y);
                    if (d <= radius) {
                        const isBoss = e.type >= 101;
                        if ((isBoss && affectsBosses) || (!isBoss && affectsEnemies)) {
                            const oldHp = e.hp;
                            e.hp = Math.min(e.maxHp, e.hp + heal);
                            io.to(`zone_${e.zone}`).emit('enemyHealed', { 
                                id: e.id, 
                                hp: e.hp, 
                                amount: Math.max(0, e.hp - oldHp) 
                            });
                        }
                    }
                }
            });
        } else if (mech.type === "aura_speed") {
            const speedBonus = mech.speedBonus || 2.0;
            const affectsEnemies = !!mech.affectsEnemies;
            const affectsBosses = !!mech.affectsBosses;

            // El dueño siempre recibe el bono
            this.enemy.auraSpeedBonus = (this.enemy.auraSpeedBonus || 0) + speedBonus;

            nearbyEnemies.forEach(e => {
                if (e.id !== this.enemy.id && e.zone === this.enemy.zone && e.hp > 0) {
                    const d = Math.hypot(e.x - this.enemy.x, e.y - this.enemy.y);
                    if (d <= radius) {
                        const isBoss = e.type >= 101;
                        if ((isBoss && affectsBosses) || (!isBoss && affectsEnemies)) {
                            e.auraSpeedBonus = (e.auraSpeedBonus || 0) + speedBonus;
                        }
                    }
                }
            });
        }
    }

    _executeMechanic(mech, mId, target, dist, angle, now, io, players) {
        if (!io) return;
        const state = this.enemy.mechState[mId] || { nextShotTime: 0, shotsInBurst: 0, isCharging: false, isActive: false };
        const hasActiveBombs = state.activeBombsList && state.activeBombsList.length > 0;
        if (!target && !state.isCharging && !state.isLocked && !state.isFiring && !state.isActive && !hasActiveBombs) return;
        
        const zoneStr = `zone_${this.enemy.zone}`;
        const type = mech.type || 'orbital';
        const fireRange = mech.fireRange || 800;

        // v266.998: PRIORIDAD ATÓMICA - Si ya empezó, TERMINA
        if (state.isActive && mech.type === "orbital_strike") {
            this._handleOrbitalStrikeLogic(mech, state, mId, now, io);
            this.enemy.mechState[mId] = state;
            return true;
        }

        if (mech.type === "summoning") {
            this._handleSummoningLogic(mech, mId, now, io);
            return false;
        }
        
        if (mech.type === "survival_dome") {
            return this._handleSurvivalDomeLogic(mech, mId, target, dist, angle, now, io, players);
        }

        if (dist > fireRange && !state.isCharging && !state.isActive) return false;

        // Mecánica de Sueño Inducido (Sleep)
        if (mech.type === "sleep") {
            const cooldown = mech.cooldown || 10000;
            if (now > state.nextShotTime) {
                const range = mech.fireRange || 600;
                const targetCount = mech.targetCount || 1;
                const targetMode = mech.targetMode || "proximity";
                const sleepDuration = mech.duration || 5000;
                const slowPct = mech.slowPercentage !== undefined ? mech.slowPercentage : 60;
                const slowDur = mech.slowDuration !== undefined ? mech.slowDuration : 1500;
                const dmgPerSecond = mech.damagePerSecond || 0;
                const nightmareMult = mech.nightmareMultiplier !== undefined ? mech.nightmareMultiplier : 2.0;
                const wakeOnDmg = mech.wakeOnDamage !== false;

                let zonePlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);
                zonePlayers = zonePlayers.filter(p => {
                    const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                    return d <= range;
                });

                if (zonePlayers.length > 0) {
                    if (targetMode === "proximity") {
                        zonePlayers.sort((a, b) => {
                            const dA = Math.hypot(a.x - this.enemy.x, a.y - this.enemy.y);
                            const dB = Math.hypot(b.x - this.enemy.x, b.y - this.enemy.y);
                            return dA - dB;
                        });
                    } else if (targetMode === "max_hp") {
                        zonePlayers.sort((a, b) => b.maxHp - a.maxHp);
                    } else if (targetMode === "missing_hp") {
                        zonePlayers.sort((a, b) => {
                            const missingA = a.maxHp - a.hp;
                            const missingB = b.maxHp - b.hp;
                            return missingB - missingA;
                        });
                    } else if (targetMode === "random") {
                        zonePlayers.sort(() => Math.random() - 0.5);
                    }

                    const selectedTargets = zonePlayers.slice(0, targetCount);

                    selectedTargets.forEach(p => {
                        p.isAsleep = true;
                        p.sleepEndTime = now + sleepDuration;
                        p.sleepNextTickDmgTime = now + 1000;
                        p.sleepDmgPerSecond = dmgPerSecond;
                        p.nightmareMultiplier = nightmareMult;
                        p.sleepWakeOnDamage = wakeOnDmg;

                        // Aplicar somnolencia progresiva
                        if (slowPct > 0 && slowDur > 0) {
                            p.isSlowed = true;
                            p.slowPoints = slowPct;
                            p.lastSlowTime = now;
                            p.slowEndTime = now + slowDur;
                            io.to(p.socketId).emit('slowState', { active: true, amount: slowPct });
                            io.to(p.socketId).emit('gameNotification', { msg: `💤 ¡Te sentís somnoliento! Ralentizado ${slowPct}% por ${slowDur}ms...`, type: "warning" });
                        }

                        setTimeout(() => {
                            if (p && p.isAsleep && !p.isDead && p.sleepEndTime > Date.now()) {
                                p.isStunned = true;
                                p.stunEndTime = p.sleepEndTime;
                                io.to(p.socketId).emit('stunState', { active: true, duration: p.sleepEndTime - Date.now(), isSleep: true });
                                io.to(p.socketId).emit('gameNotification', { msg: "💤 ¡Te quedaste dormido! 💤", type: "error" });
                            }
                        }, slowDur);
                    });

                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "sleep_cast",
                        type: "sleep",
                        range: range,
                        targets: selectedTargets.map(p => p.socketId)
                    });

                    state.nextShotTime = now + cooldown;
                }
            }
            this.enemy.mechState[mId] = state;
            return false;
        }

        if (mech.type === "orbital_strike") {
            if (now > state.nextShotTime) {
                this._handleOrbitalStrikeLogic(mech, state, mId, now, io);
                this.enemy.mechState[mId] = state;
                return true;
            }
        }

        // v266.600: Lógica de Precarga para Mega Láser
        if (mech.type === "mega_laser") {
            const chargeTime = (mech.chargeTimeMs !== undefined) ? mech.chargeTimeMs : 2000;
            const lockTime = (mech.lockTimeMs !== undefined) ? mech.lockTimeMs : 500;
            const lifetime = (mech.lifetimeMs !== undefined) ? mech.lifetimeMs : 1000;

            if (!state.isCharging && !state.isLocked && !state.isFiring && now > state.nextShotTime) {
                // FASE 1: CARGA (Te sigue apuntando y moviéndose)
                state.isCharging = true;
                state.chargeEndTime = now + chargeTime;
                
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "charging",
                    type: "mega_laser",
                    duration: chargeTime + lockTime, 
                    angle: angle,
                    range: mech.fireRange || 800,
                    targetId: target?.id || target?.socketId || "" // v266.730: Tracking en tiempo real
                });
            } else if (state.isCharging && now > state.chargeEndTime) {
                // FASE 2: BLOQUEO (Se detiene el apuntado, ventana de esquiva)
                state.isCharging = false;
                state.isLocked = true;
                state.lockedAngle = angle; // Fijamos la mira AQUÍ
                state.lockEndTime = now + lockTime; 

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "locked",
                    type: "mega_laser",
                    duration: lockTime, 
                    angle: state.lockedAngle,
                    range: mech.fireRange || 800,
                    targetId: target?.id || target?.socketId || ""
                });
            } else if (state.isLocked && now > state.lockEndTime) {
                // FASE 3: DISPARO (Sale el rayo)
                state.isLocked = false;
                state.isFiring = true;
                state.fireEndTime = now + lifetime;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target?.id || target?.socketId || "",
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, 
                    angle: state.lockedAngle,
                    bulletSpeed: mech.bulletSpeed || 2000, 
                    bulletType: "mega_laser",
                    damage: (mech.bulletDamage || 500) * (this.damageMult || 1),
                    lifetimeMs: lifetime,
                    range: mech.fireRange || 800 // v266.715: Sincronía de Rango para el Proyectil
                });
            } else if (state.isFiring && now > state.fireEndTime) {
                state.isFiring = false;
                state.nextShotTime = now + (mech.fireRate || 5000);
            }
            
            this.enemy.mechState[mId] = state;

            // v266.930: Seguimiento de rotación DURANTE la carga
            if (state.isCharging) {
                this.enemy.rotation = angle + Math.PI / 2;
            }

            // v266.695: Inmovilidad durante BLOQUEO y DISPARO
            if (state.isLocked || state.isFiring) {
                this.enemy.rotation = (state.lockedAngle || angle) + Math.PI / 2;
                return true; 
            }
            return false; 
        }

        // Mecánica de Lanzamiento de Bombas (Bomba de Área)
        if (mech.type === "bomb") {
            const fireRange = mech.fireRange || 800;
            const bombCount = mech.bombCount || 3;
            const bombDelay = mech.bombDelayMs || 500;
            const fuseTime = mech.fuseTimeMs || 1000;
            const bulletSpeed = mech.bulletSpeed || 600;
            const bulletDamage = (mech.bulletDamage || 300) * (this.damageMult || 1);
            const explosionRadius = mech.radius || 150;
            const cooldown = mech.cooldown || 5000;

            if (!state.activeBombsList) state.activeBombsList = [];

            // 1. Procesar bombas activas (vuelo, aterrizaje, detonación)
            for (let i = state.activeBombsList.length - 1; i >= 0; i--) {
                const b = state.activeBombsList[i];
                if (now >= b.explodeTime) {
                    // DETONACIÓN EN EL SERVIDOR
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "bomb_explode",
                        x: b.targetX,
                        y: b.targetY,
                        radius: explosionRadius,
                        damage: bulletDamage,
                        mId: mId + "_" + b.id
                    });

                    // Calcular daño a jugadores dentro del radio
                    const zonePlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);
                    zonePlayers.forEach(p => {
                        const d = Math.hypot(p.x - b.targetX, p.y - b.targetY);
                        if (d <= explosionRadius) {
                            p.lastCombatTime = Date.now();
                            if (p.shield >= bulletDamage) {
                                p.shield -= bulletDamage;
                            } else {
                                p.hp -= (bulletDamage - p.shield);
                                p.shield = 0;
                            }
                            if (p.hp < 0) p.hp = 0;
                            if (p.hp <= 0) p.isDead = true;

                            io.to(p.socketId).emit('environmentDamage', { damage: bulletDamage });
                            io.to(`zone_${p.zone}`).emit('playerStatSync', {
                                id: p.socketId,
                                hp: Math.ceil(p.hp),
                                shield: Math.ceil(p.shield),
                                isDead: p.isDead
                            });
                        }
                    });

                    state.activeBombsList.splice(i, 1);
                }
            }

            // 2. Iniciar y lanzar ráfagas
            if (target && dist <= fireRange) {
                if (!state.isFiringBurst && now > state.nextShotTime) {
                    state.isFiringBurst = true;
                    state.bombsFired = 0;
                    state.nextBombTime = now;
                }

                if (state.isFiringBurst && now >= state.nextBombTime) {
                    const travelTime = (dist / bulletSpeed) * 1000;
                    const landTime = now + travelTime;
                    const explodeTime = landTime + fuseTime;

                    const newBomb = {
                        id: Date.now() + "_" + Math.floor(Math.random() * 1000),
                        startX: this.enemy.x,
                        startY: this.enemy.y,
                        targetX: target.x,
                        targetY: target.y,
                        landTime: landTime,
                        explodeTime: explodeTime
                    };

                    state.activeBombsList.push(newBomb);

                    // Notificar al cliente del lanzamiento de la bomba
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "throw_bomb",
                        startX: newBomb.startX,
                        startY: newBomb.startY,
                        targetX: newBomb.targetX,
                        targetY: newBomb.targetY,
                        travelTimeMs: travelTime,
                        fuseTimeMs: fuseTime,
                        radius: explosionRadius,
                        mId: mId + "_" + newBomb.id
                    });

                    state.bombsFired++;
                    if (state.bombsFired >= bombCount) {
                        state.isFiringBurst = false;
                        state.nextShotTime = now + cooldown;
                    } else {
                        state.nextBombTime = now + bombDelay;
                    }
                }
            }

            this.enemy.mechState[mId] = state;
            return state.isFiringBurst || state.activeBombsList.length > 0;
        }

        // v3.6: Mecánica de Cono Casteable (Autoritativo del Servidor)
        if (mech.type === "cone_cast") {
            const chargeTime = (mech.castTimeMs !== undefined) ? mech.castTimeMs : 2000;
            const castSpeed = (mech.castSpeed !== undefined && mech.castSpeed > 0) ? mech.castSpeed : 1.0;
            const actualDuration = chargeTime / castSpeed;
            const cooldown = (mech.cooldown !== undefined) ? mech.cooldown : 5000;

            if (!state.isCharging && now > state.nextShotTime) {
                // FASE 1: INICIO DE CARGA
                if (!target) return false; // Se necesita un objetivo inicial
                
                state.isCharging = true;
                state.chargeEndTime = now + actualDuration;
                state.lockedAngle = angle; // Ángulo inicial
                
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "cone_charging",
                    type: "cone_cast",
                    duration: actualDuration,
                    range: mech.fireRange || 400,
                    coneAngle: mech.coneAngle || 60,
                    damage: (mech.damage || 100) * (this.damageMult || 1),
                    stunDuration: mech.stunDuration || 0,
                    coneFollow: !!mech.coneFollow,
                    lockTimeMs: mech.lockTimeMs || 0
                });
            } else if (state.isCharging && now > state.chargeEndTime) {
                // FASE 2: DETONACIÓN (DAÑO Y STUN EN EL SERVIDOR)
                state.isCharging = false;
                state.nextShotTime = now + cooldown;
                state.aimReadyTime = now + (mech.aimDelayMs !== undefined ? mech.aimDelayMs : 1000);

                const faceAngle = state.lockedAngle !== undefined ? state.lockedAngle : (this.enemy.rotation - Math.PI / 2);
                const halfAngleRad = ((mech.coneAngle || 60) * Math.PI / 180) / 2;
                const radius = mech.fireRange || 400;
                const dmg = (mech.damage || 100) * (this.damageMult || 1);
                const stunDur = mech.stunDuration || 0;

                // Avisar al cliente para reproducir animación de explosión en cono
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "cone_fire",
                    type: "cone_cast",
                    angle: faceAngle,
                    range: radius,
                    coneAngle: mech.coneAngle || 60
                });

                // Calcular jugadores golpeados
                const zonePlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);
                zonePlayers.forEach(p => {
                    const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                    if (d <= radius) {
                        let diff = Math.atan2(p.y - this.enemy.y, p.x - this.enemy.x) - faceAngle;
                        while (diff < -Math.PI) diff += Math.PI * 2;
                        while (diff > Math.PI) diff -= Math.PI * 2;

                        if (Math.abs(diff) <= halfAngleRad) {
                            // Aplicar daño
                            p.lastCombatTime = Date.now();
                            if (p.shield >= dmg) {
                                p.shield -= dmg;
                            } else {
                                p.hp -= (dmg - p.shield);
                                p.shield = 0;
                            }
                            if (p.hp < 0) p.hp = 0;
                            if (p.hp <= 0) p.isDead = true;

                            // Aplicar stun si stunDur > 0
                            if (stunDur > 0 && !p.isInvulnerable) {
                                p.isStunned = true;
                                p.stunEndTime = Date.now() + stunDur;
                                io.to(p.socketId).emit('stunState', { active: true, duration: stunDur });
                            }

                            // Sincronizar stats del jugador golpeado
                            io.to(p.socketId).emit('environmentDamage', { damage: dmg });
                            io.to(`zone_${p.zone}`).emit('playerStatSync', {
                                id: p.socketId,
                                hp: Math.ceil(p.hp),
                                shield: Math.ceil(p.shield),
                                isDead: p.isDead,
                                isInvulnerable: p.isInvulnerable,
                                isInvisible: p.isInvisible,
                                spheres: p.spheres || []
                            });
                        }
                    }
                });
            }

            this.enemy.mechState[mId] = state;

            // Durante la carga, actualizar rotación
            if (state.isCharging) {
                const timeLeft = state.chargeEndTime - now;
                const shouldTrack = !!mech.coneFollow && timeLeft > (mech.lockTimeMs || 0) && target;
                
                if (shouldTrack) {
                    state.lockedAngle = angle;
                }
                
                this.enemy.rotation = (state.lockedAngle !== undefined ? state.lockedAngle : angle) + Math.PI / 2;
                return true; // Retorna true para indicar que el enemigo está ocupado ejecutando la mecánica
            }

            return false;
        }

        // Mecánica de Explosión Circular (circle_cast)
        if (mech.type === "circle_cast") {
            const chargeTime = (mech.castTimeMs !== undefined) ? mech.castTimeMs : 2000;
            const cooldown = (mech.cooldown !== undefined) ? mech.cooldown : 5000;
            const radius = mech.fireRange || 300;
            const lockTimeMs = mech.lockTimeMs !== undefined ? mech.lockTimeMs : 800;

            if (!state.isCharging && now > state.nextShotTime) {
                // FASE 1: INICIO DE CARGA
                state.isCharging = true;
                state.chargeEndTime = now + chargeTime;
                state.lockedX = this.enemy.x;
                state.lockedY = this.enemy.y;
                state.isPositionLocked = false;
                
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "circle_charging",
                    type: "circle_cast",
                    duration: chargeTime,
                    range: radius,
                    damage: (mech.damage || 500) * (this.damageMult || 1),
                    lockTimeMs: lockTimeMs,
                    x: this.enemy.x,
                    y: this.enemy.y
                });
            } else if (state.isCharging) {
                const timeLeft = state.chargeEndTime - now;
                if (timeLeft <= 0) {
                    // FASE 3: DETONACIÓN
                    state.isCharging = false;
                    state.nextShotTime = now + cooldown;

                    // Si no se había bloqueado antes, bloquear ahora en el punto de detonación
                    if (!state.isPositionLocked) {
                        state.lockedX = this.enemy.x;
                        state.lockedY = this.enemy.y;
                        state.isPositionLocked = true;
                    }

                    const dmg = (mech.damage || 500) * (this.damageMult || 1);

                    // Avisar al cliente para reproducir animación de explosión circular
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "circle_fire",
                        type: "circle_cast",
                        x: state.lockedX,
                        y: state.lockedY,
                        range: radius
                    });

                    // Calcular jugadores golpeados alrededor del punto de fijación
                    const zonePlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);
                    zonePlayers.forEach(p => {
                        const d = Math.hypot(p.x - state.lockedX, p.y - state.lockedY);
                        if (d <= radius) {
                            p.lastCombatTime = Date.now();
                            if (p.shield >= dmg) {
                                p.shield -= dmg;
                            } else {
                                p.hp -= (dmg - p.shield);
                                p.shield = 0;
                            }
                            if (p.hp < 0) p.hp = 0;
                            if (p.hp <= 0) p.isDead = true;

                            // Sincronizar stats del jugador golpeado
                            io.to(p.socketId).emit('environmentDamage', { damage: dmg });
                            io.to(`zone_${p.zone}`).emit('playerStatSync', {
                                id: p.socketId,
                                hp: Math.ceil(p.hp),
                                shield: Math.ceil(p.shield),
                                isDead: p.isDead,
                                isInvulnerable: p.isInvulnerable,
                                isInvisible: p.isInvisible,
                                spheres: p.spheres || []
                            });
                        }
                    });
                } else {
                    // FASE 2: RASTREO / FIJACIÓN
                    if (timeLeft > lockTimeMs) {
                        // Sigue la posición del jefe
                        state.lockedX = this.enemy.x;
                        state.lockedY = this.enemy.y;
                    } else if (!state.isPositionLocked) {
                        // Se acaba de congelar la posición
                        state.lockedX = this.enemy.x;
                        state.lockedY = this.enemy.y;
                        state.isPositionLocked = true;
                    }
                }
            }

            this.enemy.mechState[mId] = state;
            return state.isCharging;
        }

        // Mecánica de Reflect (Reflejo de Daño)
        if (mech.type === "reflect") {
            const cooldown = mech.cooldown || mech.fireRate || 10000;
            const duration = mech.duration || 3000;
            const reflectMult = mech.reflect_mult !== undefined ? mech.reflect_mult : 0.8;

            if (!state.isActive && now > state.nextShotTime) {
                state.isActive = true;
                state.endTime = now + duration;
                this.enemy.reflectActive = true;
                this.enemy.reflectMult = reflectMult;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "reflect_start",
                    duration: duration,
                    reflect_mult: reflectMult
                });
            } else if (state.isActive && now > state.endTime) {
                state.isActive = false;
                this.enemy.reflectActive = false;
                state.nextShotTime = now + cooldown;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "reflect_end"
                });
            }

            this.enemy.mechState[mId] = state;
            return state.isActive;
        }

        // Mecánica de Lillia Q (spin_ring)
        if (mech.type === "spin_ring") {
            const cooldown = mech.cooldown !== undefined ? mech.cooldown : 5000;
            const radius = mech.radius !== undefined ? mech.radius : 250;
            const damage = (mech.damage !== undefined ? mech.damage : 100) * (this.damageMult || 1);
            const spinSpeed = mech.spinSpeed !== undefined ? mech.spinSpeed : 4.0;
            
            // La duración del giro completo es 2*PI / velocidad de giro
            const duration = (2 * Math.PI / spinSpeed) * 1000;

            if (!state.isActive && now > state.nextShotTime) {
                state.isActive = true;
                state.startTime = now;
                state.endTime = now + duration;
                state.nextShotTime = Infinity; // Bloquear casteo durante el giro
                
                // Compensar offset de rotación según la IA para que el orbe empiece en el frente visual exacto de la nave
                const hasRotationOffset = (this.config.movementAI === 'chase' || this.config.movementAI === 'sniper' || this.enemy.type === 1 || this.enemy.type === 9 || this.enemy.type === 13 || this.enemy.type === 4 || this.enemy.type === 5 || this.enemy.type === 2 || this.enemy.type === 12);
                const rotOffset = hasRotationOffset ? (Math.PI / 2) : 0;
                state.startAngle = (angle !== undefined ? angle : (this.enemy.rotation || 0)) + rotOffset;

                // Notificar al cliente para que cree la visual del spin_ring y ejecute la física local
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target?.id || target?.socketId || "",
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y,
                    angle: state.startAngle,
                    bulletSpeed: 0, // velocidad de traslación es 0 porque orbita
                    bulletType: "spin_ring",
                    lifetimeMs: duration,
                    damage: damage,
                    range: radius,
                    isOrbiting: true,
                    orbitRadius: radius,
                    orbitSpeed: spinSpeed,
                    orbitAngleOffset: state.startAngle
                });
            }

            if (state.isActive) {
                if (now > state.endTime) {
                    state.isActive = false;
                    state.nextShotTime = now + cooldown; // Cooldown empieza al terminar el giro
                }
            }

            this.enemy.mechState[mId] = state;
            return false;
        }

        if (now > state.nextShotTime) {
            const burstLimit = (mech.type === "laser") ? 3 : 1; 
            if (state.shotsInBurst < burstLimit) {
                const currentAngle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);
                
                // v266.240: Compatibilidad de tipos para el cliente Godot

                const modelCfg = (this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.enemyModels) ? this.state.SERVER_CONFIG.enemyModels[this.enemy.type.toString()] : null;
                const fallbackDmg = modelCfg ? (modelCfg.bulletDamage !== undefined ? modelCfg.bulletDamage : (modelCfg.damage !== undefined ? modelCfg.damage : (this.enemy.type * 100))) : (this.enemy.type * 100);

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target?.id || target?.socketId || "",
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, angle: currentAngle,
                    bulletSpeed: mech.bulletSpeed || 800, 
                    bulletType: mech.type || "laser",
                    damage: (mech.bulletDamage || fallbackDmg) * (this.damageMult || 1),
                    // v266.220: Pasar datos extra de la mecánica (Slow, Combustible, Giro)
                    slowAmount: mech.slowAmount || 0,
                    slowDuration: mech.slowDuration || 0,
                    lifetimeMs: mech.lifetimeMs || 0,
                    turnSpeed: mech.turnSpeed || 2.5,
                    isHoming: !!mech.isHoming,
                    stunDuration: mech.stunDuration || 0,
                    range: mech.fireRange || 800
                });

                // v269.110: Inmovilidad al Lanzar Gancho
                if (mech.type === "hook") {
                    this.enemy.isHooking = true;
                    // Seguridad: Si falla, recuperar movimiento según config (def 2000ms)
                    const missWait = mech.hookMissWaitMs || 2000;
                    if (this.enemy._hookSafetyTimeout) clearTimeout(this.enemy._hookSafetyTimeout);
                    this.enemy._hookSafetyTimeout = setTimeout(() => {
                        this.enemy.isHooking = false;
                    }, missWait);
                }

                state.shotsInBurst++;
                state.nextShotTime = now + 150;
            } else {
                state.shotsInBurst = 0;
                state.nextShotTime = now + (mech.fireRate || 2000);
            }
        }
        this.enemy.mechState[mId] = state;
    }

    getSpeed() {
        const speedMult = this.ambienceBoost ? (this.ambienceBoost.speedMult || 1) : 1;
        const multiplicadorMult = this.multiplicadorMult || 1;
        const baseSpeed = (this.config.speed || 3.5) * speedMult * multiplicadorMult;
        const slowMult = this.enemy.slowMultiplier || 1.0;
        
        // v268.830: El bono viene en px/s del panel, convertir a px/tick (* 0.033)
        const auraBonus = (this.enemy.auraSpeedBonus || 0) * 0.033;
        
        let spinSpeedBuff = 0;
        if (this.enemy.spinSpeedBuffEndTime && Date.now() < this.enemy.spinSpeedBuffEndTime) {
            spinSpeedBuff = (this.enemy.spinSpeedBuffAmount || 0) * 0.033;
        }
        
        let finalSpeed = (baseSpeed + auraBonus + spinSpeedBuff) * slowMult;
        if (this.enemy.isInvisSpeedModifierActive && this.enemy.invisSpeedMultiplier !== undefined) {
            finalSpeed *= this.enemy.invisSpeedMultiplier;
        }
        return finalSpeed;
    }

    applyMovementLogic(target, dist, angle, now) {
        if (this.enemy.isHooking) return;

        // v3.6: No moverse si estamos cargando/canalizando un ataque (ej: cone_cast o mega_laser)
        const hasCastingMech = this.enemy.mechState && Object.values(this.enemy.mechState).some(m => m.isCharging);
        if (hasCastingMech) {
            this.enemy.isMoving = false;
            return;
        }

        const speed = this.getSpeed();
        const stopDist = 120; 
        
        if (dist > stopDist) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < stopDist - 20) {
            this.enemy.x -= Math.cos(angle) * (speed * 0.5);
            this.enemy.y -= Math.sin(angle) * (speed * 0.5);
        }
        
        this.enemy.rotation = angle + Math.PI / 2;
    }

    _handleOrbitalStrikeLogic(mech, state, mId, now, io) {
        const orbitDuration = mech.orbitDuration || 3000;
        const staticTime = mech.staticTime || 1000;
        const fireRate = mech.fireRate || 5000;
        const radius = mech.orbitRadius || 180;
        const speed = mech.orbitSpeed || 2.0;
        const count = mech.circleCount || 4;

        if (!state.isActive) {
            // FASE 1: INICIO
            state.isActive = true;
            state.isOrbiting = true;
            state.orbitStartTime = now;
            state.orbitEndTime = now + orbitDuration;
            
            const strikeId = Date.now().toString();
            state.strikeId = strikeId;

            for (let i = 0; i < count; i++) {
                const angleOffset = (i * Math.PI * 2 / count);
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id, 
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, 
                    angle: angleOffset,
                    bulletSpeed: mech.bulletSpeed || 1200, 
                    bulletType: "orbital_mine",
                    strikeId: strikeId, 
                    damage: (mech.bulletDamage || 100) * (this.damageMult || 1), 
                    range: mech.fireRange || 1000,
                    isOrbiting: true,
                    orbitRadius: radius,
                    orbitSpeed: speed,
                    orbitAngleOffset: angleOffset
                });
            }

            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                id: this.enemy.id, action: "orbital_strike_start", strikeId: strikeId
            });
        } else {
            // PROCESAR FASES EXISTENTES
            if (state.isOrbiting && now > state.orbitEndTime) {
                state.isOrbiting = false;
                state.isStatic = true;
                state.staticEndTime = now + staticTime;
                
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id, action: "orbital_strike_static", duration: staticTime
                });
            } else if (state.isStatic && now > state.staticEndTime) {
                state.isStatic = false;
                state.isFiring = true;
                state.fireEndTime = now + 500; 
                state.nextShotTime = now + fireRate;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id, action: "orbital_strike_fire"
                });
            } else if (state.isFiring && now > state.fireEndTime) {
                state.isFiring = false;
                state.isActive = false; // FIN DEL CICLO
            }
        }
    }

    // v269.180: Lógica de Invulnerabilidad (NPC/Boss)
    _handleInvulnerabilityLogic(mech, mId, now, io) {
        if (!this.enemy.defState) this.enemy.defState = {};
        const state = this.enemy.defState[mId] || { 
            nextReadyTime: now + (mech.startDelay || 0), 
            isActive: false, 
            endTime: 0 
        };
        this.enemy.defState[mId] = state;

        // Resetear triggers y timers si salimos de combate
        if (!this._inCombat) {
            state.isActive = false;
            state.nextReadyTime = now + (mech.startDelay || 0);
        }

        // 2. Activar si cumple condiciones (v269.195: Fallback a 100 si es 0/null)
        const triggerHP = mech.activationHP || 100;
        if (!state.isActive && now >= state.nextReadyTime && this._inCombat && hpPercent <= triggerHP) {
            state.isActive = true;
            this._isDefenseSkillActive = true;
            this.enemy.isInvulnerable = true; // Sincronía para el cliente
            
            state.endTime = now + (mech.duration || 3000);
            state.nextReadyTime = now + (mech.duration || 3000) + (mech.cooldown || 10000);
            
            io.to(`zone_${this.enemy.zone}`).emit("vfx_invulnerable", { 
                id: this.enemy.id, 
                active: true, 
                duration: mech.duration || 3000 
            });
            // console.log(`[AI] ${this.enemy.id} activó Invulnerabilidad (${mech.duration}ms)`);
        }
    }

    _handleInvisibilityLogic(mech, mId, now, io) {
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

        // Resetear triggers y timers si salimos de combate
        if (!this._inCombat) {
            state.triggeredHPs = {};
            state.combatStartTime = null;
            state.nextReadyTime = now + (mech.startDelay || 0);
            state.isActive = false;
        } else if (this._inCombat && !state.combatStartTime) {
            state.combatStartTime = now;
            if (mech.activationMode === "time") {
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            }
        }

        // 1. Terminar si ya pasó el tiempo de la invisibilidad
        if (state.isActive && now >= state.endTime) {
            state.isActive = false;
            this.enemy.isInvisible = false;
            this.enemy.isCamouflaged = false;
            this.enemy.isInvisSpeedModifierActive = false;
            
            if (mech.activationMode === "time") {
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            } else {
                state.nextReadyTime = now + (mech.cooldown || 10000);
            }

            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyInvis", { 
                id: this.enemy.id, 
                active: false 
            });
        }

        // 2. Activar si cumple condiciones
        let shouldActivate = false;
        if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
            if (mech.activationMode === "time") {
                shouldActivate = true;
            } else {
                // Modo HP (por defecto)
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
                    if (hpPercent <= hpVal && !state.triggeredHPs[hpVal]) {
                        shouldActivate = true;
                        state.triggeredHPs[hpVal] = true;
                        break;
                    }
                }
            }
        }

        if (shouldActivate) {
            state.isActive = true;
            state.endTime = now + (mech.duration || 5000);
            
            const isCamo = mech.invisType === "camouflage";
            if (isCamo) {
                this.enemy.isCamouflaged = true;
                this.enemy.isInvisible = false;
            } else {
                this.enemy.isInvisible = true;
                this.enemy.isCamouflaged = false;
            }

            if (mech.changeSpeed) {
                this.enemy.isInvisSpeedModifierActive = true;
                this.enemy.invisSpeedMultiplier = mech.invisSpeedMultiplier !== undefined ? Number(mech.invisSpeedMultiplier) : 1.0;
            } else {
                this.enemy.isInvisSpeedModifierActive = false;
            }

            this.enemy.keepAttackingWhenInvis = mech.keepAttacking !== false;

            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyInvis", { 
                id: this.enemy.id, 
                active: true,
                invisType: mech.invisType || "invisibility",
                duration: mech.duration || 5000 
            });
        }
    }

    // Mecánica de Pilares Defensivos para Bosses
    _handleBossPillarsLogic(mech, mId, now, io) {
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

        // Resetear triggers y timers si salimos de combate
        if (!this._inCombat) {
            state.triggeredHPs = {};
            state.combatStartTime = null;
            state.nextReadyTime = now + (mech.startDelay || 0);
        } else if (this._inCombat && !state.combatStartTime) {
            state.combatStartTime = now;
            // Si el modo es por tiempo y recién entramos en combate, programamos la primera activación
            if (mech.activationMode === "time") {
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            }
        }

        // 1. Si la mecánica está activa, procesamos el estado de los pilares
        if (state.isActive) {
            // Forzar que el Boss permanezca en combate activo para evitar la regeneración pasiva fuera de combate mientras los pilares estén vivos
            this.enemy.lastHit = now;

            // Filtrar los pilares que siguen existiendo y tienen vida en el servidor
            const activePillars = state.pillars.filter(pid => this.state.enemies[pid] && this.state.enemies[pid].hp > 0);

            if (activePillars.length === 0) {
                // Éxito: Todos los pilares fueron destruidos
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
                // Curación periódica mientras los pilares estén vivos
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
                            amount: Math.max(0, this.enemy.hp - oldHp) 
                        });

                        // Efecto visual de curación (leech) de cada pilar al Boss en cada tick
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

                // Si se acaba el tiempo de la mecánica
                if (now >= state.endTime) {
                    // Curación de castigo por cada pilar que quede con vida
                    const healPctPerPillar = mech.healPercentPerPillarOnExpiry || 5;
                    const finalHealPct = activePillars.length * healPctPerPillar;
                    const healAmount = this.enemy.maxHp * (finalHealPct / 100);
                    const oldHp = this.enemy.hp;
                    this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + healAmount);

                    io.to(`zone_${this.enemy.zone}`).emit('enemyHealed', { 
                        id: this.enemy.id, 
                        hp: this.enemy.hp, 
                        amount: Math.max(0, this.enemy.hp - oldHp) 
                    });

                    // Eliminar los pilares restantes de la zona
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

        // 2. Activar si cumple condiciones
        let shouldActivate = false;
        if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
            if (mech.activationMode === "time") {
                shouldActivate = true;
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            } else {
                // Modo HP (por defecto)
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
                    if (hpPercent <= hpVal && !state.triggeredHPs[hpVal]) {
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
            const pType = mech.pillarType || 200; // Tipo de enemigo asignado al pilar

            // Cargar modelo del enemigo que actúa como pilar
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

                // Emitir spawn al cliente
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

    _handleBossColorsLogic(mech, mId, now, io, players) {
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

        // Resetear triggers y timers si salimos de combate
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
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            }
        }

        // 1. Si está activa, comprobar si expira
        if (state.isActive) {
            this.enemy.lastHit = now;

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

        // 2. Activar si cumple condiciones
        let shouldActivate = false;
        if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
            if (mech.activationMode === "time") {
                shouldActivate = true;
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            } else {
                // Modo HP (por defecto)
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
                    if (hpPercent <= hpVal && !state.triggeredHPs[hpVal]) {
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

    _handleBossWaterOrbsLogic(mech, mId, now, io, grid, players) {
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
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            }
        }

        if (state.isActive) {
            this.enemy.lastHit = now;

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
            if (orbSpeedVal <= 0) orbSpeedVal = 150; // Fallback para evitar que se queden quietas si es 0
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
                            if (p.hp <= 0) p.isDead = true;

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
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
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
                    if (hpPercent <= hpVal && !state.triggeredHPs[hpVal]) {
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

    _handleDuplicadoLogic(mech, mId, now, io) {
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

        // Resetear triggers y timers si salimos de combate
        if (!this._inCombat) {
            state.triggeredHPs = {};
            state.combatStartTime = null;
            state.nextReadyTime = now + (mech.startDelay || 0);
            state.isActive = false;
        } else if (this._inCombat && !state.combatStartTime) {
            state.combatStartTime = now;
            if (mech.activationMode === "time") {
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            }
        }

        // 1. Si la mecánica está activa, comprobar si expira
        if (state.isActive) {
            if (now >= state.endTime) {
                state.isActive = false;
                if (mech.activationMode !== "time") {
                    state.nextReadyTime = now + (mech.cooldown || 30000);
                }
            }
        }

        // 2. Activar si cumple condiciones
        let shouldActivate = false;
        if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
            if (mech.activationMode === "time") {
                shouldActivate = true;
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            } else {
                // Modo HP (por defecto)
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
                    if (hpPercent <= hpVal && !state.triggeredHPs[hpVal]) {
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
            const CloneAI = require('./CloneAI');

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

    _handleSummoningLogic(mech, mId, now, io) {
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

        // Resetear triggers y timers si salimos de combate
        if (!this._inCombat) {
            state.triggeredHPs = {};
            state.combatStartTime = null;
            state.nextReadyTime = now + (mech.startDelay || 0);
            state.isActive = false;
        } else if (this._inCombat && !state.combatStartTime) {
            state.combatStartTime = now;
            if (mech.activationMode === "time") {
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            }
        }

        // 1. Si la mecánica está activa, comprobar si expira
        if (state.isActive) {
            if (mech.summonDurationMode === "timed" && now >= state.endTime) {
                state.isActive = false;
                if (mech.activationMode !== "time") {
                    state.nextReadyTime = now + (mech.cooldown || 30000);
                }
            }
        }

        // 2. Activar si cumple condiciones
        let shouldActivate = false;
        if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
            if (mech.activationMode === "time") {
                shouldActivate = true;
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            } else {
                // Modo HP (por defecto)
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
                    if (hpPercent <= hpVal && !state.triggeredHPs[hpVal]) {
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

                // Resolver tipo aleatorio
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

                // Si no se pudo resolver un tipo válido, usamos el ID 1 como fallback
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

                // Asignar el comportamiento de IA cargando el cerebro correspondiente
                const moveAI = enemyCfg.movementAI || 'chase';
                let BrainClass;
                try {
                    BrainClass = require(`./${moveAI.charAt(0).toUpperCase() + moveAI.slice(1)}AI`);
                } catch(e) {
                    BrainClass = require('./ChaseAI');
                }
                summonObj.ai = new BrainClass(summonObj, enemyCfg, this.state);
                this.state.enemies[summonId] = summonObj;

                // Si tiene duración limitada, programar su destrucción
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

    _handleSurvivalDomeLogic(mech, mId, target, dist, angle, now, io, players) {
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
            const minOffset = safeRadius + 80; // Margen de seguridad para que el domo no toque el cuerpo del Boss
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
            
            // Sonido de alerta global
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
                    // Distancia al enemigo para saber si está en el radio de la explosión
                    const distToEnemy = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                    if (distToEnemy <= state.fireRange) {
                        // Distancia al domo seguro
                        const distToSafe = Math.hypot(p.x - state.safeX, p.y - state.safeY);
                        if (distToSafe > state.safeRadius) {
                            // Está FUERA de la zona segura: Recibe daño y debuffs
                            p.lastCombatTime = Date.now();
                            if (p.shield >= dmg) {
                                p.shield -= dmg;
                            } else {
                                p.hp -= (dmg - p.shield);
                                p.shield = 0;
                            }
                            if (p.hp < 0) p.hp = 0;
                            if (p.hp <= 0) p.isDead = true;

                            io.to(p.socketId).emit('environmentDamage', { damage: dmg });

                            // Aplicar Debuffs dinámicos desde debuffsList (Sangrado, Veneno, Parálisis, Slow)
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

                            // Sincronizar stats del jugador
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
            return true; // Sigue ocupado (inmóvil) durante la carga
        }

        return false;
    }

    _handleWallDomeLogic(mech, mId, now, io) {
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

        // Mantener sincronizado el radio
        state.radius = mech.radius || 300;

        const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;

        // Resetear triggers y timers si salimos de combate
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
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            }
        }

        // 1. Terminar si expira el tiempo
        if (state.isActive && now >= state.endTime) {
            state.isActive = false;
            
            if (mech.activationMode === "time") {
                const interval = Number(mech.activationIntervalMs) || 30000;
                state.nextReadyTime = now + interval;
            } else {
                state.nextReadyTime = now + (mech.cooldown || 10000);
            }

            io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", { 
                id: this.enemy.id, 
                action: "wall_dome_end",
                mId: mId
            });
        }

        // 2. Activar si cumple condiciones
        let shouldActivate = false;
        if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
            if (mech.activationMode === "time") {
                shouldActivate = true;
            } else {
                // Modo HP
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
                    if (hpPercent <= hpVal && !state.triggeredHPs[hpVal]) {
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
};
