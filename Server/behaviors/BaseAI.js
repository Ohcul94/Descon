const sphereUtils = require('../systems/equipRequirements');
const { checkAndProcessDeathDrop } = require('../systems/deathDropHelper');

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
        this._currentPhaseIndex = 0; // v500.0: Índice de fase dinámica activa
        this._lastMovementType = null; // v500.0: Último tipo de movimiento asignado
        this.baseConfig = { ...config }; // v500.1: Guardar copia de configuración base
    }

    // v_fix_dead: Helper centralizado para matar jugadores desde IA de bosses
    // Garantiza que checkAndProcessDeathDrop se llame siempre (drop de items en mapas full_drop/partial_drop/inferno)
    _killPlayer(p, io) {
        if (p.isDead) return; // Ya estaba muerto, no re-procesar
        p.isDead = true;
        checkAndProcessDeathDrop(p, io, this.state);
    }

    // v900.1: Helpers unificados de activación (genérico por CD o HP, soporta interval 0 = startDelay+cooldown)
    _getRawInterval(mech) {
        if (mech.activationIntervalMs === undefined || mech.activationIntervalMs === null || mech.activationIntervalMs === '') return 0;
        const v = Number(mech.activationIntervalMs);
        return isNaN(v) ? 0 : v;
    }
    _getEffectiveInterval(mech) {
        const raw = this._getRawInterval(mech);
        if (raw > 0) return raw;
        const cd = Number(mech.cooldown !== undefined ? mech.cooldown : (mech.fireRate !== undefined ? mech.fireRate : 5000));
        if (isNaN(cd) || cd < 0) return 0;
        return cd;
    }
    _getHPThresholds(mech) {
        if (Array.isArray(mech.activationHPs) && mech.activationHPs.length > 0) {
            return mech.activationHPs.map(Number).filter(v => !isNaN(v));
        }
        if (mech.activationHP !== undefined && mech.activationHP !== null && mech.activationHP !== '') {
            const v = Number(mech.activationHP);
            if (!isNaN(v)) return [v];
        }
        // Compat legacy single HP field or default
        return [50];
    }
    // Gate genérico para cualquier mecánica (respeta hp fix: permite re-disparo tras cooldown aunque hp siga por debajo)
    _passesActivationGate(mech, state, now, hpPercent) {
        // Si la mecánica no declara activationMode (configs viejas) => siempre activa (compat)
        if (!mech || mech.activationMode === undefined) {
            // Compat: si tiene legacy activationHP singular y sin mode, tratar como hp
            if (mech.activationHP !== undefined) {
                const thresholds = this._getHPThresholds(mech);
                if (!state.triggeredHPs) state.triggeredHPs = {};
                // Reset si sube por encima
                for (const hpVal of thresholds) {
                    if (hpPercent > hpVal && state.triggeredHPs[hpVal]) state.triggeredHPs[hpVal] = false;
                }
                if (now < (state.nextReadyTime || 0)) return false;
                for (const hpVal of thresholds) {
                    if (hpPercent <= hpVal) {
                        state.triggeredHPs[hpVal] = true;
                        return true;
                    }
                }
                return false;
            }
            return true;
        }
        const mode = mech.activationMode;
        if (mode === 'time') {
            if (now < (state.nextReadyTime || 0)) return false;
            // En modo tiempo, no hay check de HP, solo timer (startDelay+interval/cooldown manejado fuera)
            return true;
        } else {
            // Modo HP (preserva fix 22/08: re-armable tras cooldown)
            const thresholds = this._getHPThresholds(mech);
            if (!state.triggeredHPs) state.triggeredHPs = {};
            for (const hpVal of thresholds) {
                if (hpPercent > hpVal && state.triggeredHPs[hpVal]) state.triggeredHPs[hpVal] = false;
            }
            if (now < (state.nextReadyTime || 0)) return false;
            for (const hpVal of thresholds) {
                if (hpPercent <= hpVal) {
                    state.triggeredHPs[hpVal] = true;
                    return true;
                }
            }
            return false;
        }
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
                // Si chaseIdleTimeout es 0 o no está definido para Bosses, desactivar timeout de abandono (0)
                // de lo contrario, minions normales tienen fallback de 10000ms.
                const isBoss = !!cfg.isBoss;
                const idleLimit = cfg.chaseIdleTimeout !== undefined ? Number(cfg.chaseIdleTimeout) : (isBoss ? 0 : 10000);
                
                const distToP = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                const configVision = cfg ? Number(cfg.visionRange) : 0;
                const visionRange = this.ambienceBoost ? 50000 : (configVision > 0 ? configVision : (this.enemy.isHorde ? 10000 : 800));

                const outOfSight = cfg.stopOnOutOfSight && distToP > visionRange;
                const idleExpired = !cfg.chaseUntilDeath && idleLimit > 0 && idleTime >= idleLimit;

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

        // Manejar el inicio de persecución (chaseStartTime) si hay un target activo válido
        // v500.2: NO poner a null al perder el target — guardar el último timestamp activo
        // para que regenDelayMs cuente correctamente desde que se perdió el contacto.
        const hasActivePlayerTarget = activeTarget && activeTarget.id !== "altar" && !activeTarget.isDead && !activeTarget.isInvisible;
        if (hasActivePlayerTarget) {
            // Mientras hay target activo, actualizar el timestamp constantemente
            this.enemy.chaseStartTime = now;
        }
        // Al perder el target NO se toca chaseStartTime — queda con el último valor
        // para que el timer de regenDelayMs empiece a contar desde ese momento.

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
                this._interruptActiveMechanics(now, io);
                this.enemy.lastHitter = null; // Olvidar agresor para forzar retorno
                activeTarget = null;
            }
        }

        // v3.9: Determinar si el bicho está en combate activo
        const lastCombatTime = Math.max(
            this.enemy.lastHit || 0, 
            this.enemy.lastSuccessHit || 0, 
            this.enemy.chaseStartTime || 0
        );
        const delayMs = cfg.regenDelayMs !== undefined ? Number(cfg.regenDelayMs) : (cfg.regenDelaySec !== undefined ? Number(cfg.regenDelaySec) * 1000 : 5000);
        
        let inTime = (now - lastCombatTime) < delayMs;

        // Si "stopOnOutOfSight" está activo y no hay ningún target de jugador activo a la vista, o si el agresor está fuera de visión, se anula el tiempo de combate activo inmediatamente
        if (cfg.stopOnOutOfSight) {
            const hasVisualTarget = activeTarget && activeTarget.id !== "altar" && !activeTarget.isDead && !activeTarget.isInvisible;
            if (!hasVisualTarget) {
                inTime = false;
            } else if (this.enemy.lastHitter && players[this.enemy.lastHitter]) {
                const p = players[this.enemy.lastHitter];
                const dist = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                const configVision = cfg ? Number(cfg.visionRange) : 0;
                const visionRange = this.ambienceBoost ? 50000 : (configVision > 0 ? configVision : 800);
                if (dist > visionRange) {
                    inTime = false;
                }
            }
        }

        // En combate estrictamente si ha recibido/hecho daño dentro del delay configurado (independientemente de tener target visual activo)
        this._inCombat = (!this.enemy.returningToSpawn) && inTime;

        // Si salimos de combate por expirar el delay de inactividad de daño:
        // - Si el enemigo es agresivo al ver (isAggressive) y el target sigue a la vista en rango, no debe huir; regenerará pero seguirá atacando.
        // - Si no es agresivo o no hay target visual en rango de visión, forzar el retorno al spawn (Evasión).
        if (!this._inCombat && !this.enemy.returningToSpawn) {
            const hasVisualTarget = activeTarget && activeTarget.id !== "altar" && !activeTarget.isDead && !activeTarget.isInvisible;
            let targetInVision = false;
            
            if (hasVisualTarget) {
                const distToTarget = Math.hypot(activeTarget.x - this.enemy.x, activeTarget.y - this.enemy.y);
                const configVision = cfg ? Number(cfg.visionRange) : 0;
                const visionRange = this.ambienceBoost ? 50000 : (configVision > 0 ? configVision : 800);
                if (distToTarget <= visionRange) {
                    targetInVision = true;
                }
            }

            const shouldEvade = !isAggressive || !hasVisualTarget || !targetInVision;

            if (shouldEvade && (this.enemy.lastHitter || activeTarget)) {
                this.enemy.returningToSpawn = true;
                this._interruptActiveMechanics(now, io);
                this.enemy.lastHitter = null;
                activeTarget = null;
            }
        }

        // v3.9.2: Si no está en combate, no tiene target, no tiene lastHitter, no es prowler y está lejos de su spawn, regresar al spawn de forma segura
        // v500.0: isProwler considera la fase activa actual (no solo phase[0])
        const earlyPhase = (cfg.movementPhases || [])[this.enemy._currentPhaseIndex || 0];
        let isProwler = (cfg.movementAI === 'prowler') || (earlyPhase && earlyPhase.type === 'prowler');
        const distFromSpawn = Math.hypot(this.enemy.x - this.enemy.startX, this.enemy.y - this.enemy.startY);
        if (!this._inCombat && !activeTarget && !this.enemy.lastHitter && !this.enemy.returningToSpawn && !isProwler && distFromSpawn > 50) {
            this.enemy.returningToSpawn = true;
            this._interruptActiveMechanics(now, io);
        }

        // Lógica de Regeneración Autoritaria (Fuera de Combate / Ocioso)
        if (!this._inCombat && !this._isDefenseSkillActive) {
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
                // Generic cast for defense
                if (mech.castTimeMs !== undefined && Number(mech.castTimeMs) > 0) {
                    const castMs = Math.max(0, Number(mech.castTimeMs||0));
                    if (!this.enemy.genericCastState) this.enemy.genericCastState={};
                    let g=this.enemy.genericCastState[mId]; if(!g) g=this.enemy.genericCastState[mId]={isCasting:false};
                    const interruptible = mech.castInterruptible!==false;
                    const isCC = !!(this.enemy.isStunned||this.enemy.isFeared||this.enemy.isPolymorphed||this.enemy.isAsleep);
                    
                    if(g.isCasting){
                        if(isCC && interruptible){ g.isCasting=false; this.enemy._castFreezeCount=Math.max(0,(this.enemy._castFreezeCount||1)-1); io.to(`zone_${this.enemy.zone}`).emit(`enemyCastCancel`,{id:this.enemy.id,mId,type:mech.type}); /* allow */ }
                        else if(now < g.castEndTime){ return; }
                        else { g.isCasting=false; this.enemy._castFreezeCount=Math.max(0,(this.enemy._castFreezeCount||1)-1); io.to(`zone_${this.enemy.zone}`).emit(`enemyCastEnd`,{id:this.enemy.id,mId,type:mech.type}); }
                    } else {
                        // Validaciones previas para evitar casteo si no cumple condiciones de activación (cooldown, HP, etc)
                        if (!this.enemy.defState) this.enemy.defState = {};
                        let state = this.enemy.defState[mId];
                        if (!state) {
                            state = { nextReadyTime: now + (mech.startDelay || 0), isActive: false, endTime: 0, triggeredHPs: {}, combatStartTime: now, type: mech.type };
                            this.enemy.defState[mId] = state;
                        }
                        if (state.isActive) return;
                        if (now < state.nextReadyTime) return;
                        
                        const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
                        let passesActivation = false;
                        if (mech.activationMode === "time") {
                            passesActivation = true;
                        } else {
                            let thresholds = [];
                            if (Array.isArray(mech.activationHPs)) {
                                thresholds = mech.activationHPs.map(Number).filter(v => !isNaN(v));
                            } else if (mech.activationHP !== undefined) {
                                thresholds = [Number(mech.activationHP)];
                            } else {
                                thresholds = [50];
                            }
                            for (const hpVal of thresholds) {
                                if (hpPercent <= hpVal) {
                                    passesActivation = true;
                                    break;
                                }
                            }
                        }
                        if (!passesActivation) return;
                        
                        // start casting, block this tick
                        g.isCasting=true; g.castEndTime=now+castMs; g.startTime=now; this.enemy._castFreezeCount=(this.enemy._castFreezeCount||0)+1; io.to(`zone_${this.enemy.zone}`).emit(`enemyCastStart`,{id:this.enemy.id,mId,type:mech.type,castTimeMs:castMs,x:this.enemy.x,y:this.enemy.y}); return;
                    }
                }
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
                } else if (mech.type === "reflect") {
                    this._handleReflectLogic(mech, mId, now, io);
                } else if (mech.type === "shield_steal") {
                    this._handleShieldStealLogic(mech, mId, now, io, players);
                } else if (mech.type === "life_steal") {
                    this._handleLifeStealLogic(mech, mId, now, io, players);
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
                if (mech.type === "reflect" && this.enemy.defState && this.enemy.defState[mId] && this.enemy.defState[mId].isActive) {
                    this.enemy.defState[mId].isActive = false;
                    this.enemy.reflectActive = false;
                    io.to(`zone_${this.enemy.zone}`).emit("serverEnemyAction", { 
                        id: this.enemy.id, 
                        action: "reflect_end",
                        mId: mId
                    });
                }
            });
        }

        // v3.0: PROCESAR REGRESO AL SPAWN
        if (this.enemy.returningToSpawn) {
            this._interruptActiveMechanics(now, io);
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

        // v500.0: Sistema de Fases Dinámicas por Condiciones
        const phases = cfg.movementPhases || [];
        const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
        const shieldPercent = this.enemy.maxShield > 0 ? (this.enemy.shield / this.enemy.maxShield) * 100 : 100;

        // Evaluar qué fase debería estar activa según condiciones
        const newPhaseIndex = this._evaluatePhaseConditions(phases, now, hpPercent, shieldPercent);

        // Si la fase cambió, actualizar config y notificar
        if (newPhaseIndex !== (this.enemy._currentPhaseIndex || 0)) {
            const prevIndex = this.enemy._currentPhaseIndex || 0;
            this.enemy._currentPhaseIndex = newPhaseIndex;
            this._currentPhaseIndex = newPhaseIndex;
            const newPhase = phases[newPhaseIndex];

            // Restaurar configuración base para evitar arrastrar overrides de fases previas
            this.config = { ...this.baseConfig };

            if (newPhase) {
                // Actualizar parámetros de movimiento en el config del cerebro
                const phaseKeys = ['speed', 'stopDist', 'idealDist', 'orbitRadius',
                    'chargeCooldown', 'amplitude', 'frequency', 'patrolRange',
                    'changeTrigger', 'changeInterval', 'changeType', 'duration',
                    'explosionDamage', 'activationHP', 'explodeOnDeath', 'radius',
                    'speedBonus', 'intervalMs', 'affectsEnemies', 'affectsBosses'];
                phaseKeys.forEach(k => {
                    if (newPhase[k] !== undefined) {
                        if (k === 'speed') {
                            // La velocidad de la fase viene en px/s del panel.
                            // Convertimos a px/tick y también actualizamos _baseSpeed,
                            // para que la línea cfg.speed = this._baseSpeed * speedMult
                            // no restaure la velocidad de la fase anterior en el siguiente tick.
                            this.config[k] = newPhase[k] * 0.033;
                            this._baseSpeed = this.config[k]; // ← clave: sincronizar _baseSpeed
                        } else {
                            this.config[k] = newPhase[k];
                        }
                    }
                });

                // Actualizar tipo de movimiento si cambió
                const newType = newPhase.type;
                if (newType && newType !== this._lastMovementType) {
                    this._lastMovementType = newType;
                    this.enemy.movementType = newType;
                }

                // Notificar cambio de fase a clientes (para efectos visuales)
                io.to(`zone_${this.enemy.zone}`).emit('enemyPhaseChange', {
                    id: this.enemy.id,
                    phaseIndex: newPhaseIndex,
                    phaseType: newPhase.type,
                    totalPhases: phases.length
                });
            }
        }

        // Lógica Kamikaze (preservada, integrada al sistema de fases)
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
        const hasActiveMech = this.enemy.mechState && Object.values(this.enemy.mechState).some(m => m.isActive || m.isCharging || m.isLocked || m.isFiring)
            || (this.enemy._ascendingUntil && now < this.enemy._ascendingUntil);
        const isExtreme = !!this.ambienceBoost;
        
        // v500.0: isProwler ahora considera la fase activa actual (no solo phase[0])
        const activePhase = phases[this.enemy._currentPhaseIndex || 0];
        const activePhaseType = activePhase ? activePhase.type : null;
        isProwler = (cfg.movementAI === 'prowler') || (activePhaseType === 'prowler');
        if ((!activeTarget || activeTarget.isDead || activeTarget.isInvisible) && !hasActiveMech && !isExtreme && !isProwler) {
            this.enemy.isMoving = false;
            return;
        }
        
        this.enemy.isMoving = true;

        // v266.999: Valores seguros si el target desapareció pero el ataque sigue
        const dist = activeTarget ? Math.hypot(activeTarget.x - this.enemy.x, activeTarget.y - this.enemy.y) : 99999;
        let targetAngle = activeTarget ? Math.atan2(activeTarget.y - this.enemy.y, activeTarget.x - this.enemy.x) : this.enemy.rotation;
        
        // v313.5: Lógica de miedo (Fear) - Invertir el ángulo de dirección
        const isFeared = this.enemy.isFeared && now < (this.enemy.fearEndTime || 0);
        if (isFeared) {
            targetAngle = targetAngle + Math.PI;
        } else if (this.enemy.isFeared) {
            this.enemy.isFeared = false;
        }

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
        // v414.5: Durante el casteo de Ascensión Telúrica el enemigo NO se congela: el
        // giro normal lo mantiene apuntando al jugador activo (la mecánica no escribe
        // rotación propia, nunca hace snap hacia un target de cast estático).
        const hasCastingMech = this.enemy.mechState && Object.values(this.enemy.mechState).some(m => !m.ascensionCast && (m.isCharging || m.isLocked || m.isFiring || (m.aimReadyTime && now < m.aimReadyTime)));
        if (!hasCastingMech) {
            const desiredRotation = targetAngle + Math.PI / 2;
            if (this.enemy.rotation === undefined) this.enemy.rotation = desiredRotation;
            const turnSpeed = 5.0; // Velocidad de giro del cuerpo
            const delta = 0.1; 
            let diff = desiredRotation - this.enemy.rotation;
            // v414.5: Durante el vuelo de Ascensión Telúrica el enemigo planea ARRIBA del
            // target (distancia 2D casi nula): atan2 es degenerado ahí y haría girar el
            // asset sin control para cualquier lado. Mantener la rotación fija si está a
            // menos de 40px del objetivo; si el jugador huye, sí lo persigue con la mirada.
            const isAscendingNow = this.enemy._ascendingUntil && now < this.enemy._ascendingUntil;
            if (!(isAscendingNow && dist < 40)) {
                while (diff < -Math.PI) diff += Math.PI * 2;
                while (diff > Math.PI) diff -= Math.PI * 2;
                
                const step = turnSpeed * delta;
                if (Math.abs(diff) < step) {
                    this.enemy.rotation = desiredRotation;
                } else {
                    this.enemy.rotation += Math.sign(diff) * step;
                }
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
        
        // Generic cast freeze (si cualquier mecanica esta casteando)
        const hasGenericCast = this.enemy._castFreezeCount && this.enemy._castFreezeCount > 0;
        // Bloquear movimiento físico en todas las IAs si está cargando/canalizando un ataque o viajando bajo tierra (burrow)
        // v414.2: También durante el vuelo de Ascensión Telúrica (el enemigo vuela al destino, no camina)
        const isChargingAttack = (this.enemy.mechState && Object.values(this.enemy.mechState).some(m => m.isCharging || m.isSlashing)) || hasGenericCast;
        const isAscendingFlight = this.enemy._ascendingUntil && now < this.enemy._ascendingUntil;
        if (isChargingAttack || this.enemy.isBurrowed || isAscendingFlight || this.enemy._lockActions) {
            this.enemy.isMoving = false;
        } else if (activeTarget) {
            this.enemy.isMoving = true;
            this.executeActiveMovementLogic(activeTarget, dist, targetAngle, now, io);
        } else if (isProwler) {
            this.enemy.isMoving = true;
            this.executeActiveMovementLogic(null, 0, 0, now, io);
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
        
        const maps = (this.state && this.state.SERVER_CONFIG) ? (this.state.SERVER_CONFIG.mapsConfig || this.state.SERVER_CONFIG.maps || this.state.SERVER_CONFIG.mapData || {}) : {};

        // v2.5: Optimización de Visión usando el GridManager local para rangos razonables (<= 2000px)
        if (visionRange <= 2000 && grid && typeof grid.cellSize === 'number') {
            const cx = Math.floor(this.enemy.x / grid.cellSize);
            const cy = Math.floor(this.enemy.y / grid.cellSize);
            const cellRange = Math.ceil(visionRange / grid.cellSize);
            const currentZone = this.enemy.zone;
            const scannedSockets = new Set();

            for (let dx = -cellRange; dx <= cellRange; dx++) {
                for (let dy = -cellRange; dy <= cellRange; dy++) {
                    const key = `${currentZone}_${cx + dx},${cy + dy}`;
                    const cell = grid.grid.get(key);
                    if (cell && cell.players) {
                        cell.players.forEach(p => {
                            if (p.isDead || p.isInvisible || scannedSockets.has(p.socketId)) return;
                            scannedSockets.add(p.socketId);

                            if (!this.enemy.isAggressive && !this._inCombat) return;

                            const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                            if (d < minDist) {
                                minDist = d;
                                closest = p;
                            }
                        });
                    }
                }
            }
        } else {
            // Fallback: Búsqueda lineal global para rangos extremos (Hordas, Mapas de Evento o Visión Extrema)
            const targetList = Object.values(players || {});
            
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

                if (!p || p.isDead || p.isInvisible) continue;
                
                // Si no estamos en la misma zona y la zona del jugador NO es extrema, ignoramos
                const isSameZone = (normalizeZone(p.zone) === normalizeZone(this.enemy.zone));
                if (!isSameZone && !pIsExtreme) continue;

                const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                if (d < minDist) {
                    minDist = d;
                    closest = p;
                }
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

            // v400.600: Mientras el enemigo está bajo tierra (burrow), silenciar el resto de
            // mecánicas ofensivas. _lockActions cubre desde el inicio del hundimiento;
            // isBurrowed cubre viaje/espera. Las auras/efectos persistentes siguen su ciclo.
            const burrowLock = this.enemy.isBurrowed || this.enemy._lockActions;
            if (burrowLock && mech.type !== "burrow" && !(mech.type && mech.type.startsWith("aura_"))) return;

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

    // v400.600: Interrupción AAA al iniciar la Zambullida.
    // Cancela las canalizaciones/casticos en curso del resto de mecánicas (descarta daño/efecto),
    // resetea sus flags a reposo y avisa al cliente para limpiar los indicadores de carga.
    // Los cooldowns (nextShotTime) NO se tocan: siguen corriendo mientras el enemigo está oculto.
    // Las auras y efectos persistentes ya activos (wall_dome, reflect, invulnerability, auras)
    // se dejan intactos para que sigan su ciclo (decisión AAA).
    _interruptActiveMechanics(now, io, skipMId) {
        // Clear generic casts as well
        if (this.enemy.genericCastState) {
            for (const gId in this.enemy.genericCastState) {
                if (gId === skipMId) continue;
                const gs = this.enemy.genericCastState[gId];
                if (gs && gs.isCasting) {
                    gs.isCasting=false;
                    this.enemy._castFreezeCount = Math.max(0,(this.enemy._castFreezeCount||1)-1);
                    io.to(`zone_${this.enemy.zone}`).emit(`enemyCastCancel`,{id:this.enemy.id,mId:gId});
                }
            }
        }
        if (!this.enemy.mechState) return;
        const zoneStr = `zone_${this.enemy.zone}`;
        for (const mId in this.enemy.mechState) {
            if (mId === skipMId) continue;
            const st = this.enemy.mechState[mId];
            if (!st) continue;
            const isBusy = st.isCharging || st.isLocked || st.isFiring || st.isActive
                || (st.activeBombsList && st.activeBombsList.length > 0)
                || (st.activeWorms && st.activeWorms.length > 0)
                || st.activeWindWall;
            if (!isBusy) continue;

            st.isCharging = false;
            st.isLocked = false;
            st.isFiring = false;
            st.isActive = false;
            if (st.activeBombsList) st.activeBombsList = [];
            if (st.activeWorms) st.activeWorms = [];
            if (st.activeWindWall) { st.activeWindWall = null; }
            if (st.isFiringBurst !== undefined) st.isFiringBurst = false;
            if (st.isCasting !== undefined) st.isCasting = false;
            if (mId.startsWith('mech_')) {
                // No tocar `mechState[mech_<i>]` para burrow (se maneja sola); resto a visual limpio
            }

            io.to(zoneStr).emit('serverEnemyAction', {
                id: this.enemy.id,
                action: "mech_interrupt",
                type: "burrow",
                mId: mId
            });
        }

        // Si el enemigo estaba en lanzamiento de gancho, liberarlo
        if (this.enemy.isHooking) {
            if (this.enemy._hookSafetyTimeout) clearTimeout(this.enemy._hookSafetyTimeout);
            this.enemy.isHooking = false;
        }
    }

    _handleAuraLogic(mech, mId, now, io, grid, players) {
        if (!this.enemy.auraState) this.enemy.auraState = {};
        const state = this.enemy.auraState[mId] || { nextStartTime: now + (mech.startDelay || 0), isActive: false, endTime: 0, lastTickTime: 0, activationTriggeredHPs: {} };

        // 1. Gestión de Ciclo (Activar/Desactivar) — Soporta activationMode genérico (time/hp) + legacy activationHP
        let hpMet = true;
        let activationPass = false;
        if (mech.activationMode === "time") {
            // Tiempo en combate: respeta startDelay + interval (0 = cooldown) y requiere estar en combate si está definido
            if (mech.activationMode !== undefined && !this._inCombat) {
                hpMet = false;
            } else {
                hpMet = now >= state.nextStartTime;
            }
            activationPass = hpMet;
        } else if (mech.activationMode === "hp") {
            if (!this._inCombat) {
                hpMet = false;
                activationPass = false;
            } else {
                const thresholds = this._getHPThresholds(mech);
                const currentHPPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
                // Reset si sube por encima
                for (const hpVal of thresholds) {
                    if (currentHPPercent > hpVal && state.activationTriggeredHPs[hpVal]) state.activationTriggeredHPs[hpVal] = false;
                }
                if (now < state.nextStartTime) {
                    hpMet = false;
                } else {
                    hpMet = false;
                    for (const hpVal of thresholds) {
                        if (currentHPPercent <= hpVal) { hpMet = true; state.activationTriggeredHPs[hpVal]=true; break; }
                    }
                }
                activationPass = hpMet;
            }
        } else {
            const threshold = mech.activationHP !== undefined ? Number(mech.activationHP) : 100;
            const currentHPPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
            hpMet = currentHPPercent <= threshold;
            activationPass = hpMet && now >= state.nextStartTime;
        }

        if (!state.isActive && activationPass) {
            state.isActive = true;
            state.endTime = now + (mech.duration || 5000);
            state.lastTickTime = 0;
            
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAura', {
                id: this.enemy.id, mId: mId, type: mech.type, radius: mech.radius || 200, duration: mech.duration || 5000, active: true
            });
        } else if (state.isActive && now >= state.endTime) {
            state.isActive = false;
            if (mech.activationMode === "time") {
                state.nextStartTime = now + this._getEffectiveInterval(mech);
            } else {
                state.nextStartTime = now + (mech.cooldown || 10000);
            }
            
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

                        // v400.30: Reflejo autoritativo de habilidades directas en servidor
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

    // v372.2: Distancia de un punto a un segmento (colisión por barrido para gusanos rápidos)
    _distPointToSegment(px, py, ax, ay, bx, by) {
        const abx = bx - ax;
        const aby = by - ay;
        const apx = px - ax;
        const apy = py - ay;
        const lenSq = abx * abx + aby * aby;
        let t = lenSq > 0 ? (apx * abx + apy * aby) / lenSq : 0;
        t = Math.max(0, Math.min(1, t));
        const cx = ax + abx * t;
        const cy = ay + aby * t;
        return Math.hypot(px - cx, py - cy);
    }

    _isGenericCastType(type) {
        // Types with internal cast handling (their own charge) - generic runs in parallel (double bar)
        const internal = ["cone_cast","circle_cast","survival_dome","ice_storm","wind_wall","burrow","execution","ascension","melee_slash"];
        return !internal.includes(type);
    }
    _handleGenericCast(mech, mId, now, io) {
        const castMs = Math.max(0, Number(mech.castTimeMs || 0));
        if (castMs <= 0) return false; // no cast, not busy
        if (!this.enemy.genericCastState) this.enemy.genericCastState = {};
        let gState = this.enemy.genericCastState[mId];
        if (!gState) {
            gState = {isCasting:false, castEndTime:0, startTime:0};
            this.enemy.genericCastState[mId] = gState;
        }
        const castInterruptible = mech.castInterruptible !== false; // default true
        const isCC = !!(this.enemy.isStunned || this.enemy.isFeared || this.enemy.isPolymorphed || this.enemy.isAsleep);
        const isInternal = !this._isGenericCastType(mech.type);
        if (gState.isCasting) {
            if (isCC && castInterruptible) {
                // cancel
                gState.isCasting = false;
                this.enemy._castFreezeCount = Math.max(0, (this.enemy._castFreezeCount||1)-1);
                io.to(`zone_${this.enemy.zone}`).emit(`enemyCastCancel`, {id: this.enemy.id, mId, type: mech.type});
                return false;
            }
            if (now < gState.castEndTime) {
                // still casting
                // For internal types, generic runs in parallel, do not block specific handler
                if (isInternal) return false;
                return true;
            } else {
                gState.isCasting = false;
                this.enemy._castFreezeCount = Math.max(0, (this.enemy._castFreezeCount||1)-1);
                io.to(`zone_${this.enemy.zone}`).emit(`enemyCastEnd`, {id: this.enemy.id, mId, type: mech.type});
                return false;
            }
        } else {
            // not yet casting, should we start?
            // Only start if mechanic is about to fire (we are in _executeMechanic which means it wants to fire)
            // For non-internal types, we delay firing: start cast now and block
            // For internal types, we start parallel and do NOT block (return false to let internal start)
            const isInternal = !this._isGenericCastType(mech.type);
            if (isInternal) {
                // parallel: start generic casting but do not block specific handler
                gState.isCasting = true;
                gState.castEndTime = now + castMs;
                gState.startTime = now;
                this.enemy._castFreezeCount = (this.enemy._castFreezeCount||0)+1;
                io.to(`zone_${this.enemy.zone}`).emit(`enemyCastStart`, {id: this.enemy.id, mId, type: mech.type, castTimeMs: castMs, x: this.enemy.x, y: this.enemy.y});
                return false; // not busy for internal, let internal also start
            } else {
                // blocking: start and block
                gState.isCasting = true;
                gState.castEndTime = now + castMs;
                gState.startTime = now;
                this.enemy._castFreezeCount = (this.enemy._castFreezeCount||0)+1;
                io.to(`zone_${this.enemy.zone}`).emit(`enemyCastStart`, {id: this.enemy.id, mId, type: mech.type, castTimeMs: castMs, x: this.enemy.x, y: this.enemy.y});
                return true; // busy, will fire next tick after cast
            }
        }
    }
    _executeMechanic(mech, mId, target, dist, angle, now, io, players) {
        if (!io) return;
        const state = this.enemy.mechState[mId] || { nextShotTime: 0, shotsInBurst: 0, isCharging: false, isActive: false };
        const hasActiveBombs = state.activeBombsList && state.activeBombsList.length > 0;
        const hasActiveWorms = state.activeWorms && state.activeWorms.length > 0;
        if (!target && mech.type !== "polymorph" && !state.isCharging && !state.isLocked && !state.isFiring && !state.isActive && !hasActiveBombs && !hasActiveWorms && !state.activeWindWall) return;
        
        const zoneStr = `zone_${this.enemy.zone}`;
        const type = mech.type || 'orbital';
        const fireRange = mech.fireRange || 800;
        // Validaciones previas para evitar iniciar casteo de ataque si la habilidad no está lista (cooldown, rango, etc)
        const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
        const isCastingNow = this.enemy.genericCastState && this.enemy.genericCastState[mId] && this.enemy.genericCastState[mId].isCasting;
        
        if (!isCastingNow) {
            if (now < (state.nextShotTime || 0)) return false;
            if (dist > fireRange && !state.isCharging && !state.isActive && mech.type !== "polymorph") return false;
            if (!this._passesActivationGate(mech, state, now, hpPercent)) return false;
        }

        // Generic cast gate (per mechanic, default 0 = instant)
        if (mech.castTimeMs !== undefined && Number(mech.castTimeMs) > 0) {
            const isBusy = this._handleGenericCast(mech, mId, now, io);
            if (isBusy && this._isGenericCastType(mech.type)) {
                return true;
            }
        }

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
        if (mech.type === "execution") {
            return this._handleExecutionLogic(mech, mId, now, io, players);
        }
        if (mech.type === "ascension") {
            return this._handleAscensionLogic(mech, mId, target, dist, angle, now, io, players);
        }

        if (mech.type === "meteor") {
            return this._handleMeteorLogic(mech, mId, target, dist, angle, now, io, players);
        }

        if (dist > fireRange && !state.isCharging && !state.isActive && mech.type !== "polymorph") return false;

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

                // v410.6: Selección unificada de objetivos (incluye más esferas / color de esfera)
                const selectedTargets = this._selectTargets(players, range, targetCount, targetMode, mech);

                if (selectedTargets.length > 0) {
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
                            io.to(p.socketId).emit('slowState', { active: true, amount: slowPct, isSleep: true });
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
                        ex: this.enemy.x, ey: this.enemy.y,
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
                    targetId: target?.socketId || target?.id || "" // v266.730: Tracking en tiempo real
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
                    targetId: target?.socketId || target?.id || ""
                });
            } else if (state.isLocked && now > state.lockEndTime) {
                // FASE 3: DISPARO (Sale el rayo)
                state.isLocked = false;
                state.isFiring = true;
                state.fireEndTime = now + lifetime;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: target?.socketId || target?.id || "",
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
        // Generic cast gate (per mechanic, default 0 = instant)
        if (mech.castTimeMs !== undefined && Number(mech.castTimeMs) > 0) {
            const isBusy = this._handleGenericCast(mech, mId, now, io);
            if (isBusy && this._isGenericCastType(mech.type)) {
                return true;
            }
        }
            const bombCount = mech.bombCount || 3;
            const bombDelay = mech.bombDelayMs || 500;
            const fuseTime = mech.fuseTimeMs ?? 1000;
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
                            if (p.hp <= 0) this._killPlayer(p, io);

                            // v400.30: Reflejo autoritativo de habilidades directas en servidor
                            if (p.reflectActive && !p.isInvulnerable) {
                                const reflectMult = 0.8;
                                const reflectedDmg = Math.round(bulletDamage * reflectMult);
                                if (reflectedDmg > 0) {
                                    if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                                    else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                                    if (this.enemy.hp < 0) this.enemy.hp = 0;
                                    io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', {
                                        id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield
                                    });
                                }
                            }

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
            const actualDuration = (mech.castTimeMs !== undefined) ? Number(mech.castTimeMs) : 2000;
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
                            if (p.hp <= 0) this._killPlayer(p, io);

                            // v400.30: Reflejo autoritativo de habilidades directas en servidor
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
                            if (p.hp <= 0) this._killPlayer(p, io);

                            // v400.30: Reflejo autoritativo de habilidades directas en servidor
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

        // Mecánica de Tormenta de Hielo (ice_storm)
        if (mech.type === "ice_storm") {
            const chargeTime = (mech.castTimeMs !== undefined) ? mech.castTimeMs : 1500;
            const cooldown = (mech.cooldown !== undefined) ? mech.cooldown : 10000;
            const stormRadius = mech.radius || 300;
            const fireRange = mech.fireRange || 600;
            const lockTimeMs = mech.lockTimeMs !== undefined ? mech.lockTimeMs : 500;
            const duration = (mech.duration !== undefined) ? mech.duration : 5000;
            const tickInterval = (mech.tick_interval !== undefined) ? mech.tick_interval : 1000;
            const dmgPerTick = (mech.damage_per_tick !== undefined) ? mech.damage_per_tick : 50;
            const slowAmount = (mech.slow_amount !== undefined) ? mech.slow_amount : 0.4;

            if (!state.isActive && !state.isCharging && now > state.nextShotTime) {
                // FASE 1: INICIO DE CARGA — elegir un jugador objetivo dentro del alcance
                const zonePlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);
                let target = null;
                let minDist = fireRange;
                zonePlayers.forEach(p => {
                    const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                    if (d <= minDist) {
                        minDist = d;
                        target = p;
                    }
                });
                if (!target) {
                    this.enemy.mechState[mId] = state;
                    return false;
                }

                state.isCharging = true;
                state.chargeEndTime = now + chargeTime;
                state.lockedX = target.x;
                state.lockedY = target.y;
                state.targetId = target.socketId;
                state.isPositionLocked = false;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "ice_storm_charging",
                    type: "ice_storm",
                    duration: chargeTime,
                    range: stormRadius,
                    damagePerTick: dmgPerTick * (this.damageMult || 1),
                    slowAmount: slowAmount,
                    tickInterval: tickInterval,
                    stormDuration: duration,
                    targetX: target.x,
                    targetY: target.y,
                    x: this.enemy.x,
                    y: this.enemy.y
                });
            } else if (state.isCharging) {
                const timeLeft = state.chargeEndTime - now;
                if (timeLeft <= 0) {
                    // FASE 3: TORMENTA DESPLEGADA
                    state.isCharging = false;
                    state.isActive = true;
                    state.activeEndTime = now + duration;
                    state.lastTickTime = now;

                    if (!state.isPositionLocked) {
                        const target = Object.values(players || {}).find(p => p.socketId === state.targetId && !p.isDead && !p.isInvisible);
                        if (target) {
                            state.lockedX = target.x;
                            state.lockedY = target.y;
                        }
                    }

                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "ice_storm_deploy",
                        type: "ice_storm",
                        x: state.lockedX,
                        y: state.lockedY,
                        range: stormRadius,
                        duration: duration
                    });
                } else {
                    // FASE 2: RASTREO / FIJACIÓN
                    const target = Object.values(players || {}).find(p => p.socketId === state.targetId && !p.isDead && !p.isInvisible);
                    if (timeLeft > lockTimeMs) {
                        if (target) {
                            state.lockedX = target.x;
                            state.lockedY = target.y;
                        }
                    } else if (!state.isPositionLocked) {
                        if (target) {
                            state.lockedX = target.x;
                            state.lockedY = target.y;
                        }
                        state.isPositionLocked = true;
                    }
                }
            } else if (state.isActive) {
                if (now >= state.activeEndTime) {
                    // FASE 4: EXPIRACIÓN
                    state.isActive = false;
                    state.nextShotTime = now + cooldown;

                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "ice_storm_expire",
                        type: "ice_storm",
                        x: state.lockedX,
                        y: state.lockedY
                    });
                } else {
                    // Tick de daño + slow periódico
                    if (now - state.lastTickTime >= tickInterval) {
                        state.lastTickTime = now;

                        const dmg = dmgPerTick * (this.damageMult || 1);
                        const zonePlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);
                        zonePlayers.forEach(p => {
                            const d = Math.hypot(p.x - state.lockedX, p.y - state.lockedY);
                            if (d <= stormRadius) {
                                // Aplicar slow
                                const prevSlow = p.isSlowed;
                                p.isSlowed = true;
                                p.lastSlowTime = now;
                                p.slowPoints = slowAmount * 100;
                                if (!prevSlow) io.to(p.socketId).emit('slowState', { active: true, amount: p.slowPoints });

                                // Aplicar daño
                                p.lastCombatTime = Date.now();
                                if (p.shield >= dmg) {
                                    p.shield -= dmg;
                                } else {
                                    p.hp -= (dmg - p.shield);
                                    p.shield = 0;
                                }
                                if (p.hp < 0) p.hp = 0;
                                if (p.hp <= 0) this._killPlayer(p, io);

                                // Reflejo autoritativo
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

                                // Sincronizar stats
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
                    }
                }
            }

            this.enemy.mechState[mId] = state;
            return state.isCharging || state.isActive;
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
                    targetId: target?.socketId || target?.id || "",
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

        // v269.500: Mecánica de Gusanos Bumerán (worm_boomerang)
        if (mech.type === "worm_boomerang") {
            const cooldown = mech.cooldown || mech.fireRate || 8000;
            const count = mech.projectileCount || 3;
            const spreadRad = ((mech.spreadAngle || 60) * Math.PI) / 180;
            const speed = mech.bulletSpeed || 600;
            const range = mech.fireRange || 600;
            const parkTimeMs = mech.parkTimeMs !== undefined ? mech.parkTimeMs : 1000;
            const outDmg = (mech.bulletDamage || 10) * (this.damageMult || 1);
            const returnDmg = (mech.returnDamage || 10) * (this.damageMult || 1);
            const hitRadius = 35;
            const zonePlayers = () => Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);

            if (!state.activeWorms) state.activeWorms = [];

            const applyWormDamage = (p, dmg) => {
                p.lastCombatTime = Date.now();
                if (p.shield >= dmg) {
                    p.shield -= dmg;
                } else {
                    p.hp -= (dmg - p.shield);
                    p.shield = 0;
                }
                if (p.hp < 0) p.hp = 0;
                if (p.hp <= 0) this._killPlayer(p, io);

                // v400.30: Reflejo autoritativo de habilidades directas en servidor
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
                    isDead: p.isDead,
                    isInvulnerable: p.isInvulnerable,
                    isInvisible: p.isInvisible,
                    spheres: p.spheres || []
                });
            };

            const applyWormDebuffs = (p) => {
                if (!mech.debuffsList || !Array.isArray(mech.debuffsList)) return;
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
                            msg: `🩸 ¡El gusano te muerde! Sangrando ${bleedDps} HP cada ${tickInt}ms.`,
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
                            msg: `🤢 ¡El gusano te envenena! perdiendo ${poisonDps} HP cada ${tickInt}ms.`,
                            type: "warning"
                        });
                    }
                    else if (d.type === 'stun') {
                        const stunDuration = Number(d.duration) || 1500;
                        p.isStunned = true;
                        p.stunEndTime = Date.now() + stunDuration;
                        io.to(p.socketId).emit('stunState', { active: true, duration: stunDuration });
                        io.to(p.socketId).emit('gameNotification', {
                            msg: `⚡ ¡El gusano te paraliza!`,
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
                            msg: `🐢 ¡Ralentizado por el gusano! Velocidad reducida en ${slowAmt}${isPct ? '%' : ' px/s'}.`,
                            type: "warning"
                        });
                    }
                });
            };

            // FASE 1: LANZAMIENTO DEL ABANICO
            if (state.activeWorms.length === 0 && !state.isActive && now > state.nextShotTime && target && dist <= (mech.fireRange || 800)) {
                state.isActive = true;
                state.activeWorms = [];
                const centerAngle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);
                const step = count > 1 ? spreadRad / (count - 1) : 0;
                const clientWorms = [];

                for (let i = 0; i < count; i++) {
                    const offset = (i - (count - 1) / 2) * step;
                    const wormAngle = centerAngle + offset;
                    const worm = {
                        id: Date.now() + "_" + i,
                        startX: this.enemy.x,
                        startY: this.enemy.y,
                        x: this.enemy.x,
                        y: this.enemy.y,
                        angle: wormAngle,
                        speed: speed,
                        range: range,
                        phase: "out",
                        dist: 0,
                        parkEndTime: 0,
                        outHit: new Set(),
                        retHit: new Set(),
                        lastSim: now
                    };
                    state.activeWorms.push(worm);
                    clientWorms.push({
                        id: worm.id,
                        startX: worm.startX,
                        startY: worm.startY,
                        angle: wormAngle,
                        speed: speed,
                        range: range,
                        parkTimeMs: parkTimeMs,
                        damage: outDmg,
                        returnDamage: returnDmg
                    });
                }

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "worm_volley",
                    mId: mId,
                    worms: clientWorms
                });

                this.enemy.mechState[mId] = state;
                return true;
            }

            // FASE 2: SIMULACIÓN POR TICK (tiempo real + homing + colisión por barrido)
            if (state.activeWorms.length > 0) {
                for (let i = state.activeWorms.length - 1; i >= 0; i--) {
                    const w = state.activeWorms[i];
                    // v372.2: Delta REAL entre ticks (evita que el daño llegue tarde si el tick se atrasa)
                    let dt = (now - (w.lastSim || now)) / 1000;
                    if (dt <= 0) dt = 0.033;
                    if (dt > 0.1) dt = 0.1;
                    w.lastSim = now;

                    const prevX = w.x;
                    const prevY = w.y;
                    const hitPhase = w.phase;
                    let stationary = false;

                    if (w.phase === "out") {
                        w.dist += w.speed * dt;
                        if (w.dist >= w.range) {
                            w.dist = w.range;
                            w.phase = "park";
                            w.parkEndTime = now + parkTimeMs;
                        }
                        w.x = w.startX + Math.cos(w.angle) * w.dist;
                        w.y = w.startY + Math.sin(w.angle) * w.dist;
                    } else if (w.phase === "park") {
                        if (now >= w.parkEndTime) w.phase = "return";
                        stationary = true;
                    } else if (w.phase === "return") {
                        // v372.2: Homing hacia la posición ACTUAL del enemigo (no al origen del disparo)
                        const dx = this.enemy.x - w.x;
                        const dy = this.enemy.y - w.y;
                        const dd = Math.hypot(dx, dy);
                        const step = w.speed * dt;
                        if (dd <= Math.max(step, hitRadius)) {
                            state.activeWorms.splice(i, 1);
                            continue;
                        }
                        w.x += (dx / dd) * step;
                        w.y += (dy / dd) * step;
                    }

                    zonePlayers().forEach(p => {
                        const d = stationary
                            ? Math.hypot(p.x - w.x, p.y - w.y)
                            : this._distPointToSegment(p.x, p.y, prevX, prevY, w.x, w.y);
                        if (d > hitRadius) return;

                        if (hitPhase === "out" && !w.outHit.has(p.socketId)) {
                            w.outHit.add(p.socketId);
                            applyWormDamage(p, outDmg);
                        } else if (hitPhase === "return" && !w.retHit.has(p.socketId)) {
                            w.retHit.add(p.socketId);
                            applyWormDamage(p, returnDmg);
                            applyWormDebuffs(p);
                        }
                    });
                }

                // FASE 3: FIN DE LA RÁFAGA
                if (state.activeWorms.length === 0) {
                    state.isActive = false;
                    state.nextShotTime = now + cooldown;
                }
                this.enemy.mechState[mId] = state;
                return state.activeWorms.length > 0;
            }

            this.enemy.mechState[mId] = state;
            return false;
        }

        // Mecánica de Aluvión de Viento (wind_wall)
        if (mech.type === "wind_wall") {
            const cooldown = mech.cooldown || 8000;
            const castTimeMs = mech.castTimeMs !== undefined ? mech.castTimeMs : 2000;
            const speed = mech.bulletSpeed || 500;
            const range = mech.fireRange || 500;
            const width = mech.wallWidth || 140;
            const dmg = (mech.bulletDamage !== undefined ? Number(mech.bulletDamage) : 10) * (this.damageMult || 1);
            const pushDist = (mech.pushForce !== undefined ? Number(mech.pushForce) : 250);
            const startOffset = (mech.wallStartOffset !== undefined ? Number(mech.wallStartOffset) : 50);
            const zonePlayers = () => Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);

            const applyWindDebuffs = (p) => {
                if (!mech.debuffsList || !Array.isArray(mech.debuffsList)) return;
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
                        io.to(p.socketId).emit('gameNotification', { msg: `🩸 ¡El viento cortante te desgarra! Sangrando ${bleedDps} HP cada ${tickInt}ms.`, type: "warning" });
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
                        io.to(p.socketId).emit('gameNotification', { msg: `🤢 ¡Partículas tóxicas en el viento! Perdiendo ${poisonDps} HP cada ${tickInt}ms.`, type: "warning" });
                    }
                    else if (d.type === 'stun') {
                        const stunDuration = Number(d.duration) || 1500;
                        p.isStunned = true;
                        p.stunEndTime = Date.now() + stunDuration;
                        io.to(p.socketId).emit('stunState', { active: true, duration: stunDuration });
                        io.to(p.socketId).emit('gameNotification', { msg: `⚡ ¡El viento te marea! Paralizado.`, type: "error" });
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
                        io.to(p.socketId).emit('gameNotification', { msg: `🐢 ¡La ráfaga te arrastra! Velocidad reducida en ${slowAmt}${isPct ? '%' : ' px/s'}.`, type: "warning" });
                    }
                });
            };

            const hitPlayer = (p, ww) => {
                p.lastCombatTime = Date.now();
                if (p.shield >= dmg) {
                    p.shield -= dmg;
                } else {
                    p.hp -= (dmg - p.shield);
                    p.shield = 0;
                }
                if (p.hp < 0) p.hp = 0;
                if (p.hp <= 0) this._killPlayer(p, io);

                // v400.30: Reflejo autoritativo
                if (p.reflectActive && !p.isInvulnerable) {
                    const reflectedDmg = Math.round(dmg * 0.8);
                    if (reflectedDmg > 0) {
                        if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                        else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                        if (this.enemy.hp < 0) this.enemy.hp = 0;
                        io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', { id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield });
                    }
                }

                io.to(p.socketId).emit('environmentDamage', { damage: dmg });

                // Expulsión hacia afuera (dirección de vuelo de la pared)
                const dx = Math.cos(ww.angle);
                const dy = Math.sin(ww.angle);
                p.x += dx * ww.pushDist;
                p.y += dy * ww.pushDist;

                io.to(`zone_${p.zone}`).emit('windPush', {
                    victimId: p.socketId,
                    dirX: dx,
                    dirY: dy,
                    distance: ww.pushDist
                });

                applyWindDebuffs(p);

                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: p.socketId,
                    hp: Math.ceil(p.hp),
                    shield: Math.ceil(p.shield),
                    isDead: p.isDead,
                    isInvulnerable: p.isInvulnerable,
                    isInvisible: p.isInvisible,
                    spheres: p.spheres || []
                });
            };

            // FASE 1: CARGA EN PANTALLA
            if (!state.isCharging && !state.activeWindWall && now > state.nextShotTime && target && dist <= fireRange) {
                state.isCharging = true;
                state.chargeAngle = angle;
                state.chargeEndTime = now + castTimeMs;
                state.activeWindWall = null;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "wind_charging",
                    type: "wind_wall",
                    wallId: mId,
                    duration: castTimeMs,
                    angle: angle,
                    range: range,
                    width: width,
                    launchOffset: startOffset,
                    targetId: target?.id || target?.socketId || ""
                });
            } else if (state.isCharging && now > state.chargeEndTime) {
                // FASE 2: DISPARO DE LA PARED (ligeramente adelantada del enemigo)
                state.isCharging = false;
                state.isActive = true;
                const fireAngle = state.chargeAngle !== undefined ? state.chargeAngle : angle;
                const sx = this.enemy.x + Math.cos(fireAngle) * startOffset;
                const sy = this.enemy.y + Math.sin(fireAngle) * startOffset;
                state.activeWindWall = {
                    startX: sx,
                    startY: sy,
                    x: sx,
                    y: sy,
                    angle: fireAngle,
                    speed: speed,
                    range: range,
                    width: width,
                    pushDist: pushDist,
                    dist: 0,
                    lastSim: now,
                    hit: new Set()
                };
                this.enemy.rotation = fireAngle + Math.PI / 2;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "wind_fire",
                    type: "wind_wall",
                    wallId: mId,
                    x: sx,
                    y: sy,
                    angle: fireAngle,
                    speed: speed,
                    range: range,
                    width: width,
                    launchOffset: startOffset
                });
                this.enemy.mechState[mId] = state;
                return true;
            }

            // FASE 3: SIMULACIÓN DE LA PARED EN MOVIMIENTO
            if (state.activeWindWall) {
                const ww = state.activeWindWall;
                let dt = (now - (ww.lastSim || now)) / 1000;
                if (dt <= 0) dt = 0.033;
                if (dt > 0.1) dt = 0.1;
                ww.lastSim = now;

                const prevX = ww.x;
                const prevY = ww.y;
                ww.dist += ww.speed * dt;
                if (ww.dist >= ww.range) ww.dist = ww.range;
                ww.x = ww.startX + Math.cos(ww.angle) * ww.dist;
                ww.y = ww.startY + Math.sin(ww.angle) * ww.dist;

                if (!ww.hit) ww.hit = new Set();

                zonePlayers().forEach(p => {
                    if (ww.hit.has(p.socketId)) return;
                    const d = this._distPointToSegment(p.x, p.y, prevX, prevY, ww.x, ww.y);
                    if (d > (ww.width / 2)) return;
                    ww.hit.add(p.socketId);
                    hitPlayer(p, ww);
                });

                if (ww.dist >= ww.range) {
                    state.activeWindWall = null;
                    state.isActive = false;
                    state.nextShotTime = now + cooldown;
                    this.enemy.mechState[mId] = state;
                    return false;
                }
                this.enemy.mechState[mId] = state;
                return true;
            }

            this.enemy.mechState[mId] = state;
            return false;
        }

        // 🪓 Mecánica Melee - Hachazo Corto Alcance (melee_slash) — 7 = C (arco frontal o giro 360° configurable)
        // Pega directo en el área (no carga un área): solo anticipación visual y golpe instantáneo.
        // Stun/Parálisis se gestiona vía debuffsList (no hay campo stunDuration separado).
        if (mech.type === "melee_slash") {
            const cooldown = mech.cooldown !== undefined ? Number(mech.cooldown) : 2500;
            const startDelay = mech.startDelay !== undefined ? Number(mech.startDelay) : 600;
            const castTimeMs = mech.castTimeMs !== undefined ? Number(mech.castTimeMs) : 350;
            const fireRange = mech.fireRange !== undefined ? Number(mech.fireRange) : 140;
            const arcAngle = mech.arcAngle !== undefined ? Number(mech.arcAngle) : 120;
            const fullCircle = !!mech.fullCircle;
            const bulletDamage = (mech.bulletDamage !== undefined ? Number(mech.bulletDamage) : 80) * (this.damageMult || 1);
            const pushForce = mech.pushForce !== undefined ? Number(mech.pushForce) : 0;
            // Compat: si queda arcRadius viejo en config, ignorarlo y usar fireRange como radio de impacto
            const impactRadius = fireRange;

            if (state.nextShotTime === undefined || state.nextShotTime === 0) {
                state.nextShotTime = now + startDelay;
            }

            // FASE 1: Iniciar anticipación si hay target en alcance
            if (!state.isCharging && now >= state.nextShotTime && target && dist <= fireRange) {
                state.isCharging = true;
                state.chargeEndTime = now + castTimeMs;
                state.chargeAngle = angle;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "melee_charging",
                    type: "melee_slash",
                    mId: mId,
                    castTimeMs: castTimeMs,
                    arcAngle: fullCircle ? 360 : arcAngle,
                    arcRadius: impactRadius,
                    fireRange: fireRange,
                    fullCircle: fullCircle,
                    x: this.enemy.x,
                    y: this.enemy.y,
                    angle: angle,
                    targetId: target.socketId || target.id || ""
                });
                this.enemy.mechState[mId] = state;
                return true;
            }

            // FASE 2: Anticipación terminada → golpe instantáneo en el área
            if (state.isCharging && now >= state.chargeEndTime) {
                state.isCharging = false;
                const slashAngle = state.chargeAngle !== undefined ? state.chargeAngle : angle;
                const halfAngleRad = fullCircle ? Math.PI : ((arcAngle * Math.PI / 180) / 2);

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "melee_slash",
                    type: "melee_slash",
                    mId: mId,
                    arcAngle: fullCircle ? 360 : arcAngle,
                    arcRadius: impactRadius,
                    fireRange: fireRange,
                    fullCircle: fullCircle,
                    x: this.enemy.x,
                    y: this.enemy.y,
                    angle: slashAngle,
                    damage: bulletDamage
                });

                // Daño instantáneo a jugadores dentro del arco/círculo
                const zonePlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);
                zonePlayers.forEach(p => {
                    const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                    if (d > impactRadius) return;
                    if (!fullCircle) {
                        let diff = Math.atan2(p.y - this.enemy.y, p.x - this.enemy.x) - slashAngle;
                        while (diff < -Math.PI) diff += Math.PI * 2;
                        while (diff > Math.PI) diff -= Math.PI * 2;
                        if (Math.abs(diff) > halfAngleRad) return;
                    }
                    if (p.isInvulnerable) return;
                    p.lastCombatTime = Date.now();
                    if (p.shield >= bulletDamage) {
                        p.shield -= bulletDamage;
                    } else {
                        p.hp -= (bulletDamage - p.shield);
                        p.shield = 0;
                    }
                    if (p.hp < 0) p.hp = 0;
                    if (p.hp <= 0) this._killPlayer(p, io);
                    if (p.reflectActive && !p.isInvulnerable) {
                        const reflectedDmg = Math.round(bulletDamage * 0.8);
                        if (reflectedDmg > 0) {
                            if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                            else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                            if (this.enemy.hp < 0) this.enemy.hp = 0;
                            io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', { id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield });
                        }
                    }
                    if (pushForce > 0 && !p.isDead) {
                        const pushAngle = Math.atan2(p.y - this.enemy.y, p.x - this.enemy.x);
                        p.x += Math.cos(pushAngle) * pushForce;
                        p.y += Math.sin(pushAngle) * pushForce;
                        io.to(`zone_${p.zone}`).emit('windPush', { victimId: p.socketId, dirX: Math.cos(pushAngle), dirY: Math.sin(pushAngle), distance: pushForce });
                    }
                    // Stun/Parálisis ahora solo vía debuffsList (abajo)
                    if (mech.debuffsList && Array.isArray(mech.debuffsList)) {
                        mech.debuffsList.forEach(d => {
                            if (d.type === 'bleed') {
                                p.isBleeding = true;
                                p.bleedEndTime = Date.now() + (Number(d.duration) || 4000);
                                p.bleedDps = Number(d.dps) || 30;
                                p.bleedInterval = Number(d.tickInterval) || 1000;
                                p.lastBleedTick = Date.now();
                            } else if (d.type === 'stun') {
                                p.isStunned = true;
                                p.stunEndTime = Date.now() + (Number(d.duration) || 1500);
                                io.to(p.socketId).emit('stunState', { active: true, duration: Number(d.duration) || 1500 });
                            } else if (d.type === 'slow') {
                                p.isSlowed = true;
                                p.slowEndTime = Date.now() + (Number(d.duration) || 2500);
                                p.slowPoints = Number(d.amount) || 50;
                                p.slowIsPercentage = d.isPercentage !== false;
                                p.lastSlowTime = Date.now();
                                io.to(p.socketId).emit('slowState', { active: true, amount: p.slowPoints, isPercentage: p.slowIsPercentage, duration: Number(d.duration) || 2500 });
                            }
                        });
                    }
                    io.to(p.socketId).emit('environmentDamage', { damage: bulletDamage });
                    io.to(`zone_${p.zone}`).emit('playerStatSync', { id: p.socketId, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield), isDead: p.isDead });
                });

                state.nextShotTime = now + cooldown;
                this.enemy.mechState[mId] = state;
                return true;
            }

            if (state.isCharging) {
                this.enemy.rotation = (state.chargeAngle !== undefined ? state.chargeAngle : angle) + Math.PI / 2;
                this.enemy.mechState[mId] = state;
                return true;
            }

            this.enemy.mechState[mId] = state;
            return false;
        }

        // Mecánica de Zambullida Telúrica (burrow)
        // El enemigo se hunde bajo el piso, viaja subterráneamente hacia un target
        // (seleccionable por criterio) y emerge creando un círculo de daño con
        // radio configurable (burst único o zona persistente) + debuffs configurables.
        if (mech.type === "burrow") {
            const cooldown = mech.cooldown || 9000;
            const diveTimeMs = mech.castTimeMs !== undefined ? Number(mech.castTimeMs) : 1500;
            const travelSpeed = mech.burrowSpeed !== undefined ? Number(mech.burrowSpeed) : 600;
            const targetRange = mech.fireRange || 800;
            const radius = mech.radius !== undefined ? Number(mech.radius) : 250;
            const dmg = (mech.bulletDamage !== undefined ? Number(mech.bulletDamage) : 25) * (this.damageMult || 1);
            const burstMode = mech.burstMode || "burst";
            const zoneDamage = (mech.zoneDamage !== undefined ? Number(mech.zoneDamage) : 25) * (this.damageMult || 1);
            const zoneDuration = mech.zoneDuration !== undefined ? Number(mech.zoneDuration) : 4000;
            const zoneTickMs = mech.zoneTickMs !== undefined ? Number(mech.zoneTickMs) : 1000;
            const warnTimeMs = mech.warnTimeMs !== undefined ? Number(mech.warnTimeMs) : 1200;
            const undergroundMs = mech.undergroundMs !== undefined ? Number(mech.undergroundMs) : 2500;
            const targetMode = mech.targetMode || "proximity";
            const zonePlayers = () => Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);

            const applyBurrowDebuffs = (p) => {
                if (!mech.debuffsList || !Array.isArray(mech.debuffsList)) return;
                mech.debuffsList.forEach(d => {
                    if (d.type === 'bleed') {
                        p.isBleeding = true;
                        p.bleedEndTime = Date.now() + (Number(d.duration) || 4000);
                        p.bleedDps = Number(d.dps) || 30;
                        p.bleedInterval = Number(d.tickInterval) || 1000;
                        p.lastBleedTick = Date.now();
                        io.to(p.socketId).emit('gameNotification', { msg: `🩸 ¡Las grietas del suelo te desgarran! Sangrando ${p.bleedDps} HP cada ${p.bleedInterval}ms.`, type: "warning" });
                    }
                    else if (d.type === 'poison') {
                        p.isPoisoned = true;
                        p.poisonEndTime = Date.now() + (Number(d.duration) || 4000);
                        p.poisonDps = Number(d.dps) || 20;
                        p.poisonInterval = Number(d.tickInterval) || 1000;
                        p.lastPoisonTick = Date.now();
                        io.to(p.socketId).emit('gameNotification', { msg: `🤢 ¡El subsuelo emite toxinas! Perdiendo ${p.poisonDps} HP cada ${p.poisonInterval}ms.`, type: "warning" });
                    }
                    else if (d.type === 'stun') {
                        const stunDur = Number(d.duration) || 1500;
                        p.isStunned = true;
                        p.stunEndTime = Date.now() + stunDur;
                        io.to(p.socketId).emit('stunState', { active: true, duration: stunDur });
                        io.to(p.socketId).emit('gameNotification', { msg: `⚡ ¡El temblor te paraliza!`, type: "error" });
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
                        io.to(p.socketId).emit('gameNotification', { msg: `🐢 ¡El suelo te succiona! Velocidad reducida en ${slowAmt}${isPct ? '%' : ' px/s'}.`, type: "warning" });
                    }
                });
            };

            const applyCircleDamage = (cx, cy, hitSet, dmgVal = dmg) => {
                zonePlayers().forEach(p => {
                    if (hitSet && hitSet.has(p.socketId)) return;
                    const d = Math.hypot(p.x - cx, p.y - cy);
                    if (d > radius) return;
                    if (hitSet) hitSet.add(p.socketId);
                    p.lastCombatTime = Date.now();
                    const applied = dmgVal;
                    if (p.shield >= applied) {
                        p.shield -= applied;
                    } else {
                        p.hp -= (applied - p.shield);
                        p.shield = 0;
                    }
                    if (p.hp < 0) p.hp = 0;
                    if (p.hp <= 0) this._killPlayer(p, io);

                    // v400.30: Reflejo autoritativo
                    if (p.reflectActive && !p.isInvulnerable) {
                        const reflectedDmg = Math.round(applied * 0.8);
                        if (reflectedDmg > 0) {
                            if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                            else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                            if (this.enemy.hp < 0) this.enemy.hp = 0;
                            io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', { id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield });
                        }
                    }

                    io.to(p.socketId).emit('environmentDamage', { damage: applied });
                    applyBurrowDebuffs(p);
                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: p.socketId,
                        hp: Math.ceil(p.hp),
                        shield: Math.ceil(p.shield),
                        isDead: p.isDead,
                        isInvulnerable: p.isInvulnerable,
                        isInvisible: p.isInvisible,
                        spheres: p.spheres || []
                    });
                });
            };

            // v410.6: Selección unificada de objetivos (proximidad, aleatorio, vida,
            // daño, curación, MÁS ESFERAS o color de esfera)
            const selectBurrowTarget = () => {
                const sel = this._selectTargets(players, targetRange, 1, targetMode, mech);
                return sel.length > 0 ? sel[0] : null;
            };

            // FASE 0: INICIO DE LA ZAMBILLIDA (elegir target y hundirse)
            if (!state.isDiving && !state.isTraveling && !state.isActive && now > state.nextShotTime) {
                const chosen = selectBurrowTarget();
                if (!chosen) {
                    this.enemy.mechState[mId] = state;
                    return false;
                }
                state.isDiving = true;
                state.isActive = true;
                state.diveEndTime = now + diveTimeMs;
                state.targetId = chosen.socketId;
                state.targetX = chosen.x;
                state.targetY = chosen.y;
                state.hitPlayers = new Set();

                // v400.600: Al comenzar el hundimiento el enemigo bloquea el resto de mecánicas
                // ofensivas y cancela en el instante las canalizaciones en curso.
                // OJO: usamos _lockActions (no isBurrowed) para no interrumpir la
                // animación visual de hundirse: el AOI/egameLoop siguen con isBurrowed=false
                // hasta que el viaje comienza, y recién ahí el cliente oculta el modelo.
                this.enemy._lockActions = true;
                this._interruptActiveMechanics(now, io, mId);

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "burrow_dive",
                    type: "burrow",
                    duration: diveTimeMs,
                    targetX: state.targetX,
                    targetY: state.targetY,
                    radius: radius,
                    targetMode: targetMode,
                    targetId: state.targetId
                });
                this.enemy.mechState[mId] = state;
                return true;
            }

            // FASE 1: TERMINÓ DE HUNDIRSE -> COMIENZA EL VIAJE SUBTERRÁNEO
            if (state.isDiving && now >= state.diveEndTime) {
                state.isDiving = false;
                state.isTraveling = true;
                state.startX = this.enemy.x;
                state.startY = this.enemy.y;
                state.lastSim = now;

                // v400.600: El viaje comienza bajo tierra: aquí sí marcamos isBurrowed para
                // que el cliente oculte el modelo (el hundimiento ya terminó).
                this.enemy.isBurrowed = true;

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "burrow_travel",
                    type: "burrow",
                    startX: state.startX,
                    startY: state.startY,
                    targetX: state.targetX,
                    targetY: state.targetY,
                    speed: travelSpeed
                });
                this.enemy.mechState[mId] = state;
                return true;
            }

            // FASE 2: VIAJE SUBTERRÁNEO (simulación con delta real)
            if (state.isTraveling) {
                let dt = (now - (state.lastSim || now)) / 1000;
                if (dt <= 0) dt = 0.033;
                if (dt > 0.1) dt = 0.1;
                state.lastSim = now;

                // v400.500: Re-localización en vivo del objetivo mientras viaja.
                // La mecánica siempre persigue al jugador seleccionado: si sigue vivo y en rango,
                // se actualiza el destino a su posición actual (nunca aparece "en cualquier lado").
                // Si el objetivo ya no es válido o se alejó demasiado, se cancela la emboscada.
                let targetP = state.targetId ? (players[state.targetId] || null) : null;
                const targetValid = targetP && !targetP.isDead && !targetP.isInvisible && targetP.zone === this.enemy.zone
                    && Math.hypot(targetP.x - this.enemy.x, targetP.y - this.enemy.y) <= targetRange * 1.75
                    && Math.hypot(targetP.x - state.startX, targetP.y - state.startY) <= targetRange * 2.5;
                if (!targetValid) {
                    state.isTraveling = false;
                    state.isActive = false;
                    state.nextShotTime = now + cooldown * 0.5;
                    this.enemy.isBurrowed = false;
                    this.enemy._lockActions = false;
                    this.enemy.mechState[mId] = state;
                    return false;
                }
                state.targetX = targetP.x;
                state.targetY = targetP.y;

                const dx = state.targetX - this.enemy.x;
                const dy = state.targetY - this.enemy.y;
                const dd = Math.hypot(dx, dy);
                const step = travelSpeed * dt;
                if (dd <= Math.max(step, 1)) {
                    this.enemy.x = state.targetX;
                    this.enemy.y = state.targetY;
                    this.enemy.rotation = Math.atan2(dy, dx) + Math.PI / 2;
                    state.isTraveling = false;
                    state.isWarning = true;
                    // Tiempo total bajo tierra en el destino; el círculo de aviso aparece
                    // en el último tramo antes de salir (warnTimeMs)
                    state.warnEndTime = now + undergroundMs;
                    state.warnStartTime = now + Math.max(0, undergroundMs - warnTimeMs);
                    state.warnSent = false;
                } else {
                    this.enemy.x += (dx / dd) * step;
                    this.enemy.y += (dy / dd) * step;
                    this.enemy.rotation = Math.atan2(dy, dx) + Math.PI / 2;
                }
                this.enemy.mechState[mId] = state;
                return true;
            }

            // FASE 3: WARNING (primer llega el enemigo oculto; al acercarse el momento de salir
            // se dibuja el círculo de peligro y en warnEndTime emerge rompiendo el suelo)
            if (state.isWarning) {
                if (!state.warnSent && now >= state.warnStartTime) {
                    state.warnSent = true;
                    // El enemigo sigue Oculto bajo tierra; solo se dibuja el círculo de peligro en el piso
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "burrow_warn",
                        type: "burrow",
                        x: this.enemy.x,
                        y: this.enemy.y,
                        radius: radius,
                        warns: state.warnEndTime - now
                    });
                }
                if (now >= state.warnEndTime) {
                    state.isWarning = false;
                    state.isEmerging = true;
                    state.emergeEndTime = now + 600;
                    state.zoneEndTime = now + zoneDuration;
                    state.lastTick = now;
                    this.enemy.isBurrowed = false;
                    this.enemy._lockActions = false;

                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "burrow_emerge",
                        type: "burrow",
                        x: this.enemy.x,
                        y: this.enemy.y,
                        radius: radius,
                        damage: dmg,
                        burstMode: burstMode,
                        zoneDamage: zoneDamage,
                        zoneDuration: zoneDuration,
                        zoneTickMs: zoneTickMs
                    });

                    // Daño de SALIDA: siempre se aplica al emerger (otrá cantidad para burst/zone)
                    applyCircleDamage(this.enemy.x, this.enemy.y, state.hitPlayers, dmg);
                }
                this.enemy.mechState[mId] = state;
                return true;
            }

            // FASE 4: ZONA PERSISTENTE (tick de daño con zoneDamage mientras dure)
            if (state.isEmerging) {
                if (burstMode === "burst") {
                    // Burst ya se aplicó al emerger: la mecánica termina aquí
                    state.isEmerging = false;
                    state.isActive = false;
                    state.nextShotTime = now + cooldown;
                    this.enemy.mechState[mId] = state;
                    return false;
                }
                if (now < state.zoneEndTime) {
                    if (now - state.lastTick >= zoneTickMs) {
                        state.lastTick = now;
                        // En zona, cada tick vuelve a afectar a quien entra (sin hitSet permanente), con zoneDamage
                        applyCircleDamage(this.enemy.x, this.enemy.y, null, zoneDamage);
                    }
                } else if (now >= state.zoneEndTime) {
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "burrow_zone_end",
                        type: "burrow",
                        x: this.enemy.x,
                        y: this.enemy.y
                    });
                    state.isEmerging = false;
                    state.isActive = false;
                    state.nextShotTime = now + cooldown;
                    this.enemy.mechState[mId] = state;
                    return false;
                }
                this.enemy.mechState[mId] = state;
                return true;
            }

            this.enemy.mechState[mId] = state;
            return false;
        }

        // Polymorph: resetear triggeredHPs si HP sube por encima de umbrales, y manejar startDelay
        if (mech.type === "polymorph") {
            if (!state.triggeredHPs) state.triggeredHPs = {};
            const hpPercent = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;
            const thresholds = Array.isArray(mech.activationHPs) && mech.activationHPs.length > 0
                ? mech.activationHPs.map(Number).filter(v => !isNaN(v))
                : [70];
            // Resetear triggers si HP sube por encima
            for (const hpVal of thresholds) {
                if (hpPercent > hpVal && state.triggeredHPs[hpVal]) {
                    state.triggeredHPs[hpVal] = false;
                }
            }
            // startDelay: inicializar nextShotTime si es la primera vez
            if (state.nextShotTime === undefined || state.nextShotTime === 0) {
                state.nextShotTime = now + (mech.startDelay || 0);
            }
        }

        // v900.1: Gate genérico de activación para TODAS las mecánicas de ataque con activador (time 0 = startDelay+cooldown, hp preserva fix)
        if (mech.activationMode !== undefined && !["polymorph","meteor","execution","ascension","summoning"].includes(mech.type)) {
            if (state.activationNextTime === undefined) state.activationNextTime = now + (Number(mech.startDelay) || 0);
            const hpPercentGen = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;
            const thresholdsGen = this._getHPThresholds(mech);
            if (!state.activationTriggeredHPs) state.activationTriggeredHPs = {};
            for (const hpVal of thresholdsGen) {
                if (hpPercentGen > hpVal && state.activationTriggeredHPs[hpVal]) state.activationTriggeredHPs[hpVal] = false;
            }
            let actPass = false;
            // Respetar estado de combate para ambos modos (Por Tiempo en Combate / Por HP en Combate)
            if (!this._inCombat) {
                actPass = false;
                // Mantener timer deslizante con startDelay mientras está fuera de combate (estética prolija)
                state.activationNextTime = now + (Number(mech.startDelay) || 0);
            } else if (mech.activationMode === "time") {
                if (now >= state.activationNextTime) actPass = true;
            } else {
                if (now >= state.activationNextTime) {
                    for (const hpVal of thresholdsGen) {
                        if (hpPercentGen <= hpVal) { actPass = true; state.activationTriggeredHPs[hpVal]=true; break; }
                    }
                }
            }
            if (!actPass) {
                this.enemy.mechState[mId] = state;
                return false;
            }
            // Marcar re-armado del timer de activación según modo (se re-arme tras el disparo)
            state._pendingActivationRearm = true;
        }

        if (now > state.nextShotTime) {
            // Polymorph: soporte para activationMode (time/hp) y activationHPs
            if (mech.type === "polymorph" && mech.activationMode !== "time") {
                const hpPercent = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;
                const thresholds = Array.isArray(mech.activationHPs) && mech.activationHPs.length > 0
                    ? mech.activationHPs.map(Number).filter(v => !isNaN(v))
                    : [70];
                
                // Inicializar triggeredHPs si no existe
                if (!state.triggeredHPs) state.triggeredHPs = {};
                
                let shouldActivate = false;
                for (const hpVal of thresholds) {
                    if (hpPercent <= hpVal) {
                        shouldActivate = true;
                        state.triggeredHPs[hpVal] = true;
                        break;
                    }
                }
                if (!shouldActivate) {
                    this.enemy.mechState[mId] = state;
                    return false;
                }
            }
            
            // v410.5: Nº de proyectiles por ráfaga configurable (burstShots). Default: 1.
            // Polymorph usa bulletCount en lugar de burstShots
            let burstLimit = 1;
            if (mech.type === "polymorph" && mech.bulletCount !== undefined) {
                burstLimit = Math.max(1, parseInt(mech.bulletCount, 10) || 1);
            } else if (mech.burstShots !== undefined && mech.burstShots !== null && mech.burstShots !== '') {
                burstLimit = Math.max(1, parseInt(mech.burstShots, 10) || 1);
            }

            // v410.6: Polymorph - Selección de objetivos configurable
            // (targetMode: proximidad/aleatorio/más esferas/color de esfera... + targetCount)
            let polyTargets = null;
            if (mech.type === "polymorph") {
                polyTargets = this._selectTargets(players, mech.fireRange || 800, mech.targetCount || 1, mech.targetMode || "proximity", mech);
                if (!polyTargets || polyTargets.length === 0) {
                    state.shotsInBurst = 0;
                    state.nextShotTime = now + (this._getRawInterval(mech) > 0 ? this._getRawInterval(mech) : (mech.cooldown || 20000));
                    this.enemy.mechState[mId] = state;
                    return false;
                }
            }

            if (state.shotsInBurst < burstLimit) {
                // El disparo de la ráfaga apunta al objetivo seleccionado (rota entre los targets)
                let aimTarget = target;
                if (polyTargets && polyTargets.length > 0) {
                    aimTarget = polyTargets[state.shotsInBurst % polyTargets.length];
                }
                if (!aimTarget) {
                    this.enemy.mechState[mId] = state;
                    return false;
                }
                const currentAngle = Math.atan2(aimTarget.y - this.enemy.y, aimTarget.x - this.enemy.x);
                
                // v266.240: Compatibilidad de tipos para el cliente Godot

                const modelCfg = (this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.enemyModels) ? this.state.SERVER_CONFIG.enemyModels[this.enemy.type.toString()] : null;
                const fallbackDmg = modelCfg ? (modelCfg.bulletDamage !== undefined ? modelCfg.bulletDamage : (modelCfg.damage !== undefined ? modelCfg.damage : (this.enemy.type * 100))) : (this.enemy.type * 100);

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    targetId: aimTarget?.socketId || aimTarget?.id || "",
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, angle: currentAngle,
                    bulletSpeed: mech.bulletSpeed || 800, 
                    bulletType: mech.type || "laser",
                    damage: (mech.bulletDamage !== undefined && mech.bulletDamage !== null ? mech.bulletDamage : fallbackDmg) * (this.damageMult || 1),
                    // v266.220: Pasar datos extra de la mecánica (Slow, Combustible, Giro)
                    slowAmount: mech.slowAmount || 0,
                    slowDuration: mech.slowDuration || 0,
                    lifetimeMs: mech.lifetimeMs || 0,
                    turnSpeed: mech.turnSpeed || 2.5,
                    isHoming: mech.type === "polymorph" ? !!mech.isPointAndClick : !!mech.isHoming,
                    stunDuration: mech.stunDuration || 0,
                    range: mech.fireRange || 800,
                    // Polymorph fields
                    polyDuration: mech.polyDuration || 0,
                    canMove: mech.canMove !== undefined ? mech.canMove : false,
                    canUseSkills: mech.canUseSkills !== undefined ? mech.canUseSkills : false
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
                if (mech.type === "polymorph") {
                    if (mech.activationMode === "time") {
                        state.nextShotTime = now + (this._getRawInterval(mech) > 0 ? this._getRawInterval(mech) : (mech.cooldown || 20000));
                    } else {
                        state.nextShotTime = now + (mech.cooldown || 20000);
                    }
                } else {
                    state.nextShotTime = now + (mech.fireRate || 2000);
                    if (state._pendingActivationRearm) {
                        if (mech.activationMode === "time") {
                            state.activationNextTime = now + this._getEffectiveInterval(mech);
                        } else {
                            state.activationNextTime = now + (mech.cooldown || mech.fireRate || 5000);
                        }
                        state._pendingActivationRearm = false;
                    }
                }
            }
        }
        this.enemy.mechState[mId] = state;
    }

    // v411: METEORITO - Lluvia de meteoritos que se invocan desde el cielo.
    // Tras un aviso en el piso (warnTimeMs) caen sobre los objetivos seleccionados,
    // infligen daño en área y pueden aplicar debuffs configurables.
    _handleMeteorLogic(mech, mId, target, dist, angle, now, io, players) {
        if (!io) return false;
        const state = this.enemy.mechState[mId] || { nextShotTime: 0, triggeredHPs: {}, meteorList: [] };
        const fireRange = mech.fireRange || 800;
        // Generic cast gate (per mechanic, default 0 = instant)
        if (mech.castTimeMs !== undefined && Number(mech.castTimeMs) > 0) {
            const isBusy = this._handleGenericCast(mech, mId, now, io);
            if (isBusy && this._isGenericCastType(mech.type)) {
                return true;
            }
        }
        const meteorCount = Math.max(1, parseInt(mech.meteorCount, 10) || 3);
        const warnTimeMs = mech.warnTimeMs || 1200;
        const fallHeight = mech.fallHeight || 800;
        const fallSpeed = mech.fallSpeed || 600;
        const meteorSize = mech.meteorSize || 60;
        const explosionRadius = mech.explosionRadius || 150;
        const bulletDamage = (mech.bulletDamage || 200) * (this.damageMult || 1);
        const targetMode = mech.targetMode || "proximity";
        const cooldown = mech.cooldown || 10000;
        const fallTimeMs = (fallHeight / Math.max(1, fallSpeed)) * 1000;
        const persistentZone = !!mech.persistentZone;
        const zoneDamage = (mech.zoneDamage || 0) * (this.damageMult || 1);
        const zoneTickMs = mech.zoneTickMs || 1000;
        const zoneDuration = mech.zoneDuration || 4000;

        if (!state.meteorList) state.meteorList = [];

        const zonePlayers = () => Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);

        // 1. Procesar meteoritos activos (impacto)
        for (let i = state.meteorList.length - 1; i >= 0; i--) {
            const mt = state.meteorList[i];
            if (now >= mt.landTime) {
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "meteor_impact",
                    x: mt.x,
                    y: mt.y,
                    radius: explosionRadius,
                    meteorSize: meteorSize,
                    damage: bulletDamage,
                    mId: mId + "_" + mt.id
                });

                // Aplicar daño a jugadores dentro del radio de impacto
                zonePlayers().forEach(p => {
                    const d = Math.hypot(p.x - mt.x, p.y - mt.y);
                    if (d > explosionRadius) return;
                    p.lastCombatTime = Date.now();
                    if (p.shield >= bulletDamage) {
                        p.shield -= bulletDamage;
                    } else {
                        p.hp -= (bulletDamage - p.shield);
                        p.shield = 0;
                    }
                    if (p.hp < 0) p.hp = 0;
                    if (p.hp <= 0) this._killPlayer(p, io);

                    // v400.30: Reflejo autoritativo
                    if (p.reflectActive && !p.isInvulnerable) {
                        const reflectedDmg = Math.round(bulletDamage * 0.8);
                        if (reflectedDmg > 0) {
                            if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                            else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                            if (this.enemy.hp < 0) this.enemy.hp = 0;
                            io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', {
                                id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield
                            });
                        }
                    }

                    io.to(p.socketId).emit('environmentDamage', { damage: bulletDamage });
                    this._applyMeteorDebuffs(p, mech, io);
                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: p.socketId,
                        hp: Math.ceil(p.hp),
                        shield: Math.ceil(p.shield),
                        isDead: p.isDead
                    });
                });

                state.meteorList.splice(i, 1);

                // Crear zona persistente si está habilitada
                if (persistentZone && zoneDuration > 0) {
                    if (!state.activeZones) state.activeZones = [];
                    const zoneId = mId + "_z_" + mt.id;
                    state.activeZones.push({
                        id: zoneId, x: mt.x, y: mt.y,
                        endTime: now + zoneDuration,
                        lastTick: now
                    });
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "meteor_zone_start",
                        x: mt.x, y: mt.y,
                        radius: explosionRadius,
                        zoneDamage: zoneDamage,
                        zoneDuration: zoneDuration,
                        zoneTickMs: zoneTickMs,
                        mId: zoneId
                    });
                }
            }
        }

        // Procesar zonas activas (daño por tick + expiración)
        if (state.activeZones && state.activeZones.length > 0) {
            for (let i = state.activeZones.length - 1; i >= 0; i--) {
                const z = state.activeZones[i];
                if (now >= z.endTime) {
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "meteor_zone_end",
                        mId: z.id
                    });
                    state.activeZones.splice(i, 1);
                } else if (now - z.lastTick >= zoneTickMs) {
                    z.lastTick = now;
                    zonePlayers().forEach(p => {
                        const d = Math.hypot(p.x - z.x, p.y - z.y);
                        if (d > explosionRadius) return;
                        p.lastCombatTime = Date.now();
                        if (p.shield >= zoneDamage) {
                            p.shield -= zoneDamage;
                        } else {
                            p.hp -= (zoneDamage - p.shield);
                            p.shield = 0;
                        }
                        if (p.hp < 0) p.hp = 0;
                        if (p.hp <= 0) this._killPlayer(p, io);
                        if (p.reflectActive && !p.isInvulnerable) {
                            const reflectedDmg = Math.round(zoneDamage * 0.8);
                            if (reflectedDmg > 0) {
                                if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                                else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                                if (this.enemy.hp < 0) this.enemy.hp = 0;
                                io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', {
                                    id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield
                                });
                            }
                        }
                        io.to(p.socketId).emit('environmentDamage', { damage: zoneDamage });
                        io.to(`zone_${p.zone}`).emit('playerStatSync', {
                            id: p.socketId, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield), isDead: p.isDead
                        });
                    });
                }
            }
        }

        // 2. Gate de activación (startDelay + modo HP o tiempo)
        if (state.nextShotTime === undefined || state.nextShotTime === 0) {
            state.nextShotTime = now + (mech.startDelay || 0);
        }
        if (mech.activationMode !== "time") {
            const hpPercent = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;
            const thresholds = Array.isArray(mech.activationHPs) && mech.activationHPs.length > 0
                ? mech.activationHPs.map(Number).filter(v => !isNaN(v))
                : [70];
            if (!state.triggeredHPs) state.triggeredHPs = {};
            // Resetear triggers si HP sube por encima
            for (const hpVal of thresholds) {
                if (hpPercent > hpVal && state.triggeredHPs[hpVal]) {
                    state.triggeredHPs[hpVal] = false;
                }
            }
            let shouldActivate = false;
            if (now > state.nextShotTime) {
                for (const hpVal of thresholds) {
                    if (hpPercent <= hpVal) {
                        shouldActivate = true;
                        state.triggeredHPs[hpVal] = true;
                        break;
                    }
                }
            }
            if (!shouldActivate) {
                this.enemy.mechState[mId] = state;
                return state.meteorList.length > 0;
            }
        }

        // 3. Iniciar la lluvia de meteoritos
        if (target && dist <= fireRange && now > state.nextShotTime) {
            const targets = this._selectMeteorTargets(players, fireRange, meteorCount, targetMode, mech);
            if (targets.length > 0) {
                const landTime = now + warnTimeMs + fallTimeMs;
                const targetsPayload = targets.map(t => ({ x: Math.round(t.x), y: Math.round(t.y), targetId: t.socketId }));

                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "meteor_summon",
                    x: this.enemy.x,
                    y: this.enemy.y,
                    targets: targetsPayload,
                    warnTimeMs: warnTimeMs,
                    fallHeight: fallHeight,
                    fallSpeed: fallSpeed,
                    meteorSize: meteorSize,
                    radius: explosionRadius,
                    damage: bulletDamage,
                    targetMode: targetMode,
                    mId: mId
                });

                targets.forEach(t => {
                    state.meteorList.push({
                        id: Date.now() + "_" + Math.floor(Math.random() * 1000),
                        x: Math.round(t.x),
                        y: Math.round(t.y),
                        landTime: landTime
                    });
                });

                state.nextShotTime = now + (mech.activationMode === "time" ? (mech.activationIntervalMs || cooldown) : cooldown);
            }
        }

         this.enemy.mechState[mId] = state;
        return state.meteorList.length > 0;
    }

    // v413: EJECUCIÓN DIRECTA (Death / Instant Kill)
    // Por tiempo en combate (o por HP), selecciona jugadores en rango y les lanza
    // una calavera proyectil (bulletType "execution"). Si impacta -> muerte instantánea
    // (ignora escudo y vida). point_and_click = calavera rápida + homing (ineludible);
    // esquivable = calavera lenta sin homing fuerte (dodgeable).
    _handleExecutionLogic(mech, mId, now, io, players) {
        if (!io) return false;
        const state = this.enemy.mechState[mId] || { nextShotTime: 0, triggeredHPs: {}, casting: false, castEndTime: 0, castTargets: [] };
        this.enemy.mechState[mId] = state;

        const fireRange = mech.fireRange || 800;
        // Generic cast gate (per mechanic, default 0 = instant)
        if (mech.castTimeMs !== undefined && Number(mech.castTimeMs) > 0) {
            const isBusy = this._handleGenericCast(mech, mId, now, io);
            if (isBusy && this._isGenericCastType(mech.type)) {
                return true;
            }
        }
        const targetCount = Math.max(1, parseInt(mech.targetCount, 10) || 1);
        const targetMode = mech.targetMode || "proximity";
        const cooldown = mech.cooldown !== undefined ? Number(mech.cooldown) : 12000;
        const intervalMsRaw = mech.activationIntervalMs !== undefined ? Number(mech.activationIntervalMs) : 8000;
        const intervalMs = intervalMsRaw > 0 ? intervalMsRaw : cooldown;
        const castTimeMs = mech.castTimeMs !== undefined ? Number(mech.castTimeMs) : 700;
        const pointAndClick = !!mech.isPointAndClick;
        const skullSpeed = Number(mech.skullSpeed) || (pointAndClick ? 1800 : 450);

        if (state.nextShotTime === undefined || state.nextShotTime === 0) {
            state.nextShotTime = now + (mech.startDelay || 0);
        }

        const interval = mech.activationMode !== "time" && mech.activationMode !== "hp"
            ? intervalMs : (mech.activationMode === "time" ? intervalMs : cooldown);

        // 1) Si está en casteo activo, disparar la calavera al terminar el warnTime
        if (state.casting) {
            if (now >= state.castEndTime) {
                state.casting = false;
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "death_cast_end",
                    mId: mId
                });
                state.castTargets.forEach(t => {
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                        enemyId: this.enemy.id,
                        targetId: t.socketId,
                        enemyType: this.enemy.type,
                        x: this.enemy.x, y: this.enemy.y,
                        angle: Math.atan2(t.y - this.enemy.y, t.x - this.enemy.x),
                        bulletType: "execution",
                        bulletSpeed: skullSpeed,
                        damage: 999999,
                        targetX: t.x, targetY: t.y,
                        isHoming: pointAndClick,
                        turnSpeed: pointAndClick ? 8.0 : 1.0,
                        range: fireRange,
                        executionMode: pointAndClick ? "point_click" : "esquivable"
                    });
                });
                state.castTargets = [];
                state.nextShotTime = now + cooldown;
            }
            return false;
        }

        const hpPercent = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;

        // 2) Gate de activación
        if (mech.activationMode === "time") {
            if (now < state.nextShotTime) { this.enemy.mechState[mId] = state; return false; }
        } else {
            const thresholds = Array.isArray(mech.activationHPs) && mech.activationHPs.length > 0
                ? mech.activationHPs.map(Number).filter(v => !isNaN(v)) : [50];
            if (!state.triggeredHPs) state.triggeredHPs = {};
            for (const hpVal of thresholds) {
                if (hpPercent > hpVal && state.triggeredHPs[hpVal]) state.triggeredHPs[hpVal] = false;
            }
            let shouldActivate = false;
            if (now > state.nextShotTime) {
                for (const hpVal of thresholds) {
                    if (hpPercent <= hpVal) {
                        shouldActivate = true;
                        state.triggeredHPs[hpVal] = true;
                        break;
                    }
                }
            }
            if (!shouldActivate) { this.enemy.mechState[mId] = state; return false; }
        }

        // 3) Seleccionar objetivos en rango de visión
        const targets = this._selectMeteorTargets(players, fireRange, targetCount, targetMode, mech);
        if (targets.length === 0) {
            state.nextShotTime = now + interval;
            this.enemy.mechState[mId] = state;
            return false;
        }

        // 4) Iniciar casteo: marcar a los objetivos con la calavera
        state.casting = true;
        state.castEndTime = now + castTimeMs;
        state.castTargets = targets;
        io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
            id: this.enemy.id,
            action: "death_cast_start",
            mId: mId,
            castTimeMs: castTimeMs,
            executionMode: pointAndClick ? "point_click" : "esquivable",
            targets: targets.map(t => ({ socketId: t.socketId, x: t.x, y: t.y }))
        });

        io.to(`zone_${this.enemy.zone}`).emit('gameNotification', { msg: '☠️ ¡Una calavera marcó a alguien!', type: 'warning' });

        state.nextShotTime = now + (state.castEndTime - now) + cooldown;
        this.enemy.mechState[mId] = state;
        return false;
    }

    // v414: ASCENSIÓN TELÚRICA (Ascension / Fly & Fall)
    // Inversa de la Zambullida: el ENEMIGO salta hacia el cielo (tiempo de casteo),
    // vuela hasta el objetivo (tiempo en el aire), el área de aterrizaje aparece
    // (tiempo de espera del área) y se marca (tiempo marcando el área) mientras
    // el enemigo cae: daño de aterrizaje en el área sobre los jugadores.
    _handleAscensionLogic(mech, mId, target, dist, angle, now, io, players) {
        if (!io) return false;
        const state = this.enemy.mechState[mId] || { nextShotTime: 0, triggeredHPs: {}, casting: false, castEndTime: 0, castTargets: [], jumps: [] };
        this.enemy.mechState[mId] = state;
        if (!state.jumps) state.jumps = [];

        const fireRange = mech.fireRange || 800;
        // Generic cast gate (per mechanic, default 0 = instant)
        if (mech.castTimeMs !== undefined && Number(mech.castTimeMs) > 0) {
            const isBusy = this._handleGenericCast(mech, mId, now, io);
            if (isBusy && this._isGenericCastType(mech.type)) {
                return true;
            }
        }
        const targetCount = Math.max(1, parseInt(mech.targetCount, 10) || 1);
        const targetMode = mech.targetMode || "proximity";
        const cooldown = mech.cooldown !== undefined ? Number(mech.cooldown) : 12000;
        const intervalMsRaw = mech.activationIntervalMs !== undefined ? Number(mech.activationIntervalMs) : 8000;
        const intervalMs = intervalMsRaw > 0 ? intervalMsRaw : cooldown;
        const castTimeMs = mech.castTimeMs !== undefined ? Number(mech.castTimeMs) : 1500;
        const airTimeMs = mech.airTimeMs !== undefined ? Number(mech.airTimeMs) : 2000;
        const warnDelayMs = mech.warnDelayMs !== undefined ? Number(mech.warnDelayMs) : 600;
        const warnTimeMs = mech.warnTimeMs !== undefined ? Number(mech.warnTimeMs) : 1200;
        const radius = mech.radius || 250;
        const landingDamage = (mech.bulletDamage !== undefined ? Number(mech.bulletDamage) : 150) * (this.damageMult || 1);

        const zonePlayers = () => Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);

        // 1) Procesar saltos activos: el enemigo se eleva rápido y queda planeando sobre
        //    el destino; al cumplirse el CD aéreo (airTimeMs) cae en la zona del target.
        for (let i = state.jumps.length - 1; i >= 0; i--) {
            const jp = state.jumps[i];
            // Elevación rápida + desplazamiento al destino en el primer 35% del vuelo,
            // luego queda planeando (en el aire) sobre el área marcada hasta el impacto
            if (now >= jp.startTime && now < jp.landTime) {
                const riseFrac = Math.min(1.0, Math.max(0.0, (now - jp.startTime) / Math.max(1, airTimeMs * 0.35)));
                this.enemy.x = jp.startX + (jp.endX - jp.startX) * riseFrac;
                this.enemy.y = jp.startY + (jp.endY - jp.startY) * riseFrac;
                if (riseFrac >= 1.0) {
                    this.enemy.x = jp.endX;
                    this.enemy.y = jp.endY;
                }
            }
            if (now >= jp.landTime) {
                // Aterrizar físicamente en el destino
                this.enemy.x = jp.endX;
                this.enemy.y = jp.endY;
                // Avisar el fin del área marcada + notificar el aterrizaje
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "ascension_impact",
                    x: jp.endX,
                    y: jp.endY,
                    radius: radius,
                    damage: landingDamage,
                    mId: mId + "_" + jp.id
                });

                // Aplicar daño de aterrizaje a los jugadores dentro del área
                zonePlayers().forEach(p => {
                    const d = Math.hypot(p.x - jp.endX, p.y - jp.endY);
                    if (d > radius) return;
                    p.lastCombatTime = Date.now();
                    if (p.shield >= landingDamage) {
                        p.shield -= landingDamage;
                    } else {
                        p.hp -= (landingDamage - p.shield);
                        p.shield = 0;
                    }
                    if (p.hp < 0) p.hp = 0;
                    if (p.hp <= 0) this._killPlayer(p, io);

                    // v400.30: Reflejo autoritativo
                    if (p.reflectActive && !p.isInvulnerable) {
                        const reflectedDmg = Math.round(landingDamage * 0.8);
                        if (reflectedDmg > 0) {
                            if (this.enemy.shield >= reflectedDmg) this.enemy.shield -= reflectedDmg;
                            else { this.enemy.hp -= (reflectedDmg - this.enemy.shield); this.enemy.shield = 0; }
                            if (this.enemy.hp < 0) this.enemy.hp = 0;
                            io.to(`zone_${this.enemy.zone}`).emit('enemyDamaged', {
                                id: this.enemy.id, hp: Math.max(0, this.enemy.hp), shield: this.enemy.shield
                            });
                        }
                    }

                    io.to(p.socketId).emit('environmentDamage', { damage: landingDamage });
                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: p.socketId,
                        hp: Math.ceil(p.hp),
                        shield: Math.ceil(p.shield),
                        isDead: p.isDead
                    });
                });

                state.jumps.splice(i, 1);
            }
        }

        // v414.2: Limpiar el bloqueo de vuelo cuando ya no hay saltos activos y expiró el reposo
        if (state.jumps.length === 0 && this.enemy._ascendingUntil && now >= this.enemy._ascendingUntil) {
            delete this.enemy._ascendingUntil;
        }

        // 2) Si está casteando: al terminar el casteo, el enemigo salta (empezar el vuelo)
        if (state.casting) {
            // v414.5: Durante el casteo NO se escribe ninguna rotación aquí. La rotación
            // normal del AI (bloque de cuerpo, excluido del congelado vía ascensionCast)
            // mantiene apuntando al jugador activo: solo sigue al objetivo, jamás hace snap.
            if (now >= state.castEndTime) {
                state.casting = false;
                state.isCharging = false;
                state.ascensionCast = false;
                state.castTargets.forEach(t => {
                    const jumpId = Date.now() + "_" + Math.floor(Math.random() * 1000);
                    // v414.3: El enemigo cae cuando se cumple el CD aéreo (airTimeMs) desde el salto.
                    // El área de caída se marca en el piso en cuanto termina el casteo.
                    const landTime = now + airTimeMs;
                    // v414.2: Bloquear el movimiento normal mientras el enemigo vuela al destino
                    // (y un breve reposo tras aterrizar para que se aprecie el impacto)
                    const settleMs = 700;
                    this.enemy._ascendingUntil = Math.max(this.enemy._ascendingUntil || 0, landTime + settleMs);
                    state.jumps.push({
                        id: jumpId,
                        startX: this.enemy.x,
                        startY: this.enemy.y,
                        endX: Math.round(t.x),
                        endY: Math.round(t.y),
                        startTime: now,
                        landTime: landTime
                    });
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                        id: this.enemy.id,
                        action: "ascension_leap",
                        mId: mId,
                        startX: this.enemy.x,
                        startY: this.enemy.y,
                        endX: Math.round(t.x),
                        endY: Math.round(t.y),
                        targetId: t.socketId,
                        airTimeMs: airTimeMs,
                        warnDelayMs: warnDelayMs,
                        warnTimeMs: warnTimeMs,
                        landTime: landTime,
                        radius: radius,
                        damage: landingDamage
                    });
                });
                state.castTargets = [];
                state.nextShotTime = now + cooldown;
            }
            return false;
        }

        // 3) Gate de activación
        if (state.nextShotTime === undefined || state.nextShotTime === 0) {
            state.nextShotTime = now + (mech.startDelay || 0);
        }
        if (mech.activationMode === "time") {
            if (now < state.nextShotTime) { this.enemy.mechState[mId] = state; return false; }
        } else {
            const hpPercent = this.enemy.maxHp > 0 ? (this.enemy.hp / this.enemy.maxHp) * 100 : 100;
            const thresholds = Array.isArray(mech.activationHPs) && mech.activationHPs.length > 0
                ? mech.activationHPs.map(Number).filter(v => !isNaN(v)) : [50];
            if (!state.triggeredHPs) state.triggeredHPs = {};
            for (const hpVal of thresholds) {
                if (hpPercent > hpVal && state.triggeredHPs[hpVal]) state.triggeredHPs[hpVal] = false;
            }
            let shouldActivate = false;
            if (now > state.nextShotTime) {
                for (const hpVal of thresholds) {
                    if (hpPercent <= hpVal) {
                        shouldActivate = true;
                        state.triggeredHPs[hpVal] = true;
                        break;
                    }
                }
            }
            if (!shouldActivate) { this.enemy.mechState[mId] = state; return false; }
        }

        // 4) Seleccionar objetivos (el enemigo aterriza sobre el primero) e iniciar el casteo
        if (target && dist <= fireRange && now > state.nextShotTime) {
            const targets = this._selectMeteorTargets(players, fireRange, targetCount, targetMode, mech);
            if (targets.length > 0) {
                state.casting = true;
                state.isCharging = true;
                state.ascensionCast = true;
                state.castEndTime = now + castTimeMs;
                state.castTargets = targets;
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
                    id: this.enemy.id,
                    action: "ascension_cast",
                    mId: mId,
                    castTimeMs: castTimeMs,
                    targets: targets.map(t => ({ socketId: t.socketId, x: Math.round(t.x), y: Math.round(t.y) }))
                });
                state.nextShotTime = now + (state.castEndTime - now) + cooldown;
            }
        }

        this.enemy.mechState[mId] = state;
        return false;
    }

    // v410.6: Selección UNIFICADA de objetivos para cualquier mecánica ofensiva.
    // Soporta todos los criterios existentes + el nuevo de esferas:
    //   sphere_color    -> SOLO jugadores con esferas del color configurado (targetSphereColor),
    //                      ordenados por el que tenga MÁS esferas de ese color
    // El color (targetSphereColor) SOLO se aplica cuando el modo es "sphere_color".
    _selectTargets(players, fireRange, count, mode, mech) {
        const mechCfg = mech || {};
        const selMode = mode || "proximity";
        const selCount = Math.max(1, parseInt(count, 10) || 1);

        let pool = Object.values(players || {}).filter(p => p.zone === this.enemy.zone && !p.isDead && !p.isInvisible);
        pool = pool.filter(p => Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y) <= (fireRange || 800));
        if (pool.length === 0) return [];

        // v410.6: Modo "Por Color de Esfera": solo jugadores con esferas del color elegido,
        // priorizando al que tenga MÁS esferas de ese color (ej: el que más esferas verdes tiene)
        if (selMode === "sphere_color") {
            const sphereColor = sphereUtils.normalizeSphereColor(mechCfg.targetSphereColor);
            if (sphereColor) {
                pool = pool.filter(p => this._playerSphereColorCount(p, sphereColor) > 0);
                if (pool.length === 0) return [];
                pool.sort((a, b) => this._playerSphereColorCount(b, sphereColor) - this._playerSphereColorCount(a, sphereColor));
                return pool.slice(0, Math.min(selCount, pool.length));
            }
            // Sin color configurado -> cae a proximidad
        }

        if (selMode === "random") {
            for (let i = pool.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [pool[i], pool[j]] = [pool[j], pool[i]];
            }
        } else if (selMode === "farthest") {
            pool.sort((a, b) => Math.hypot(b.x - this.enemy.x, b.y - this.enemy.y) - Math.hypot(a.x - this.enemy.x, a.y - this.enemy.y));
        } else if (selMode === "lowest_hp") {
            pool.sort((a, b) => (a.hp / Math.max(1, a.maxHp)) - (b.hp / Math.max(1, b.maxHp)));
        } else if (selMode === "highest_hp") {
            pool.sort((a, b) => (b.hp / Math.max(1, b.maxHp)) - (a.hp / Math.max(1, a.maxHp)));
        } else if (selMode === "max_hp") {
            pool.sort((a, b) => (b.maxHp || 0) - (a.maxHp || 0));
        } else if (selMode === "missing_hp") {
            pool.sort((a, b) => ((b.maxHp || 0) - (b.hp || 0)) - ((a.maxHp || 0) - (a.hp || 0)));
        } else if (selMode === "highest_damage") {
            const dmgMap = this.enemy.playerDamage || {};
            pool.sort((a, b) => (dmgMap[b.socketId] || 0) - (dmgMap[a.socketId] || 0));
        } else if (selMode === "highest_heal") {
            pool.sort((a, b) => (b.healingDoneTotal || 0) - (a.healingDoneTotal || 0));
        } else if (selMode === "highest_shield") {
            pool.sort((a, b) => (b.shield || 0) - (a.shield || 0));
        } else { // proximidad
            pool.sort((a, b) => Math.hypot(a.x - this.enemy.x, a.y - this.enemy.y) - Math.hypot(b.x - this.enemy.x, b.y - this.enemy.y));
        }
        return pool.slice(0, Math.min(selCount, pool.length));
    }

    // Cantidad de esferas de UN color específico que tiene el jugador
    _playerSphereColorCount(p, color) {
        if (!p || !Array.isArray(p.spheres)) return 0;
        let count = 0;
        for (const s of p.spheres) {
            if (!s || typeof s !== 'object') continue;
            const c = sphereUtils.getSphereColor(s);
            if (c && c === color) count++;
        }
        return count;
    }

    // ¿El jugador tiene al menos una esfera del color indicado (roja/azul/verde/amarilla)?
    _playerHasSphereColor(p, color) {
        return this._playerSphereColorCount(p, color) > 0;
    }

    // Selecciona N objetivos para la lluvia de meteoritos según el criterio configurado
    _selectMeteorTargets(players, fireRange, count, mode, mech) {
        return this._selectTargets(players, fireRange, count, mode, mech || {});
    }

    // Aplica debuffs configurables al jugador impactado por un meteorito
    _applyMeteorDebuffs(p, mech, io) {
        if (!mech.debuffsList || !Array.isArray(mech.debuffsList)) return;
        mech.debuffsList.forEach(d => {
            if (d.type === 'bleed') {
                p.isBleeding = true;
                p.bleedEndTime = Date.now() + (Number(d.duration) || 4000);
                p.bleedDps = Number(d.dps) || 30;
                p.bleedInterval = Number(d.tickInterval) || 1000;
                p.lastBleedTick = Date.now();
                io.to(p.socketId).emit('gameNotification', { msg: `🩸 ¡El meteorito te hizo sangrar!`, type: "warning" });
            }
            else if (d.type === 'poison') {
                p.isPoisoned = true;
                p.poisonEndTime = Date.now() + (Number(d.duration) || 4000);
                p.poisonDps = Number(d.dps) || 20;
                p.poisonInterval = Number(d.tickInterval) || 1000;
                p.lastPoisonTick = Date.now();
                io.to(p.socketId).emit('gameNotification', { msg: `🤢 ¡El meteorito te envenenó!`, type: "warning" });
            }
            else if (d.type === 'stun') {
                const stunDur = Number(d.duration) || 1500;
                p.isStunned = true;
                p.stunEndTime = Date.now() + stunDur;
                io.to(p.socketId).emit('stunState', { active: true, duration: stunDur });
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
            }
        });
    }

    // v500.0: Evaluador de Condiciones de Fases Dinámicas
    // Determina qué fase del movementPhases[] debería estar activa según condiciones.
    // Retorna el índice de la primera fase cuyas condiciones se cumplen, priorizando las condicionales sobre las de por defecto.
    _evaluatePhaseConditions(phases, now, hpPercent, shieldPercent) {
        let fallbackIndex = 0;
        // Encontrar la primera fase sin condiciones como fallback (por defecto la 0)
        for (let i = 0; i < phases.length; i++) {
            if (!phases[i].conditions) {
                fallbackIndex = i;
                break;
            }
        }

        // Buscar primero alguna fase con condiciones que se cumpla
        for (let i = 0; i < phases.length; i++) {
            const p = phases[i];
            if (!p.conditions) continue; // Evaluar primero las que tienen condiciones

            const c = p.conditions;
            let matches = true;

            // engagement check: idle / combat / returning
            if (c.engagement) {
                if (c.engagement === 'idle' && this._inCombat) matches = false;
                if (c.engagement === 'combat' && !this._inCombat) matches = false;
                if (c.engagement === 'returning' && !this.enemy.returningToSpawn) matches = false;
            }
            if (!matches) continue;

            // HP check
            if (c.hpPercentBelow !== undefined && c.hpPercentBelow !== null) {
                if (hpPercent > c.hpPercentBelow) continue;
            }

            // Shield check
            if (c.shieldPercentBelow !== undefined && c.shieldPercentBelow !== null) {
                if (shieldPercent > c.shieldPercentBelow) continue;
            }

            // Tiempo en combate check
            if (c.timeInCombatMs !== undefined && c.timeInCombatMs !== null) {
                const combatTime = now - (this.enemy.chaseStartTime || now);
                if (combatTime < c.timeInCombatMs) continue;
            }

            // Tiempo desde spawn check
            if (c.timeSinceSpawnMs !== undefined && c.timeSinceSpawnMs !== null) {
                const spawnElapsed = now - (this.enemy.spawnTime || now);
                if (spawnElapsed < c.timeSinceSpawnMs) continue;
            }

            return i; // La primera fase con condiciones que se cumpla gana
        }
        return fallbackIndex; // Fallback si no se cumple ninguna con condiciones
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
            endTime: 0,
            combatStartTime: null
        };
        this.enemy.defState[mId] = state;

        const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;

        // Resetear si salimos de combate
        if (!this._inCombat) {
            state.isActive = false;
            this._isDefenseSkillActive = false;
            this.enemy.isInvulnerable = false;
            state.combatStartTime = null;
            state.nextReadyTime = now + (mech.startDelay || 0);
        } else if (!state.combatStartTime) {
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

        // Desactivar si expiró la duración
        if (state.isActive) {
            if (now > state.endTime) {
                state.isActive = false;
                this._isDefenseSkillActive = false;
                this.enemy.isInvulnerable = false;

                if (mech.activationMode === "time") {
                    state.nextReadyTime = now + this._getEffectiveInterval(mech);
                } else {
                    state.nextReadyTime = now + (mech.cooldown || 10000);
                }

                io.to(`zone_${this.enemy.zone}`).emit("vfx_invulnerable", { 
                    id: this.enemy.id, 
                    active: false 
                });
            }
            return;
        }

        if (now < state.nextReadyTime) return;

        let shouldActivate = false;

        if (mech.activationMode === "time") {
            shouldActivate = true;
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
        } else {
            const thresholds = (mech.activationHPs && mech.activationHPs.length > 0)
                ? mech.activationHPs
                : [mech.activationHP || 70];
            for (const hpVal of thresholds) {
                if (hpPercent <= Number(hpVal)) {
                    shouldActivate = true;
                    break;
                }
            }
        }

        if (shouldActivate) {
            state.isActive = true;
            this._isDefenseSkillActive = true;
            this.enemy.isInvulnerable = true;
            state.endTime = now + (mech.duration || 3000);

            io.to(`zone_${this.enemy.zone}`).emit("vfx_invulnerable", { 
                id: this.enemy.id, 
                active: true, 
                duration: mech.duration || 3000 
            });
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
                const raw = this._getRawInterval(mech);
                if (raw === 0) {
                    state.nextReadyTime = now + (Number(mech.startDelay) || 0);
                } else {
                    state.nextReadyTime = now + raw;
                }
            }
        }

        // 1. Terminar si ya pasó el tiempo de la invisibilidad
        if (state.isActive && now >= state.endTime) {
            state.isActive = false;
            this.enemy.isInvisible = false;
            this.enemy.isCamouflaged = false;
            this.enemy.isInvisSpeedModifierActive = false;
            
            if (mech.activationMode === "time") {
                    state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
                    state.nextReadyTime = now + this._getEffectiveInterval(mech);
                }
        }

        // 1. Si la mecánica está activa, procesamos el estado de los pilares
        if (state.isActive) {

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
                            amount: Math.max(0, this.enemy.hp - oldHp),
                            healType: 'hp'
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
                        amount: Math.max(0, this.enemy.hp - oldHp),
                        healType: 'hp'
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
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
                const raw = this._getRawInterval(mech);
                if (raw === 0) {
                    state.nextReadyTime = now + (Number(mech.startDelay) || 0);
                } else {
                    state.nextReadyTime = now + raw;
                }
            }
        }

        // 1. Si está activa, comprobar si expira
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

        // 2. Activar si cumple condiciones
        let shouldActivate = false;
        if (!state.isActive && now >= state.nextReadyTime && this._inCombat) {
            if (mech.activationMode === "time") {
            shouldActivate = true;
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
                            if (p.hp <= 0) this._killPlayer(p, io);

                            // v400.30: Reflejo autoritativo de habilidades directas en servidor
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
                const raw = this._getRawInterval(mech);
                if (raw === 0) {
                    state.nextReadyTime = now + (Number(mech.startDelay) || 0);
                } else {
                    state.nextReadyTime = now + raw;
                }
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
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
                const raw = this._getRawInterval(mech);
                if (raw === 0) {
                    state.nextReadyTime = now + (Number(mech.startDelay) || 0);
                } else {
                    state.nextReadyTime = now + raw;
                }
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
            state.nextReadyTime = now + this._getEffectiveInterval(mech);
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
                            if (p.hp <= 0) this._killPlayer(p, io);

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
                const raw = this._getRawInterval(mech);
                if (raw === 0) {
                    state.nextReadyTime = now + (Number(mech.startDelay) || 0);
                } else {
                    state.nextReadyTime = now + raw;
                }
            }
        }

        // 1. Terminar si expira el tiempo
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

    _handleReflectLogic(mech, mId, now, io) {
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

        // Resetear triggers y timers si salimos de combate
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

        // 1. Terminar si expira el tiempo
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

    // v410: ROBADOR DE ESCUDO (shield_steal) - Defensa que dispara un homing y,
    // al impactar, vincula al objetivo durante un tiempo robándole escudo por ticks.
    _handleShieldStealLogic(mech, mId, now, io, players) {
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

                // El porcentaje se calcula contra el ESCUDO MÁXIMO del jugador (pregunta respondida)
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

        // 2) Activación de la mecánica (igual patrón que Reflect/WaterOrbs)
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
            // v410.6: Selección unificada de objetivos (incluye más esferas / color de esfera)
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

        // El vínculo real se arma al impactar el proyectil (en combatHandlers -> onShieldStealHit)
        this.enemy.defState[mId] = state;
    }

    // v410: Llamado por combatHandlers.js cuando el proyectil shield_steal impacta al jugador
    _onEnemyShieldStealHit(targetId, mech, mId, now, io) {
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

    // v410: Devuelve el índice de la mecánica shield_steal en defenseMechanics (o null)
    findShieldStealMech() {
        const defs = this.config.defenseMechanics || [];
        const idx = defs.findIndex(d => d.type === "shield_steal");
        if (idx === -1) return null;
        return { mech: defs[idx], mId: `def_${idx}` };
    }

    // v412: ROBADOR DE VIDA (life_steal) - Igual que shield_steal pero roba VIDA
    // (HP) al jugador por ticks y se la transfiere al enemigo. Visual verde.
    _handleLifeStealLogic(mech, mId, now, io, players) {
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

        // Si el proyectil ya se disparó pero nunca impactó (escapó / murió / se fue de rango),
        // liberar el estado para volver a intentarlo tras el cooldown.
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

            // Expirar si el jugador no existe, está muerto, se fue de la zona o pasó el tiempo
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

            // Tick de robo de vida (porcentual del maxHp del jugador o plano)
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

                    // Si el robo alimenta la vida del propio enemigo (configurable)
                    if (mech.giveToEnemy !== false) {
                        const oldHp = this.enemy.hp;
                        if (this.enemy.hp < this.enemy.maxHp) {
                            this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + stolen);
                        }
                        // Siempre emitir, aunque sea +0 (vida llena) para mostrar texto verde al cliente
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

        // 2) Activación de la mecánica (igual patrón que Reflect/WaterOrbs)
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
            // v410.6: Selección unificada de objetivos (incluye más esferas / color de esfera)
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

        // El vínculo real se arma al impactar el proyectil (en combatHandlers -> onLifeStealHit)
        this.enemy.defState[mId] = state;
    }

    // v412: Llamado por combatHandlers.js cuando el proyectil life_steal impacta al jugador
    _onEnemyLifeStealHit(targetId, mech, mId, now, io) {
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

    // v412: Devuelve el índice de la mecánica life_steal en defenseMechanics (o null)
    findLifeStealMech() {
        const defs = this.config.defenseMechanics || [];
        const idx = defs.findIndex(d => d.type === "life_steal");
        if (idx === -1) return null;
        return { mech: defs[idx], mId: `def_${idx}` };
    }

    // v500.4: Despachador de movimiento dinámico basado en la fase activa del ciclo
    executeActiveMovementLogic(target, dist, angle, now, io) {
        if (this.enemy.isHooking) return;

        // Bloquear movimiento si estamos canalizando
        const hasCastingMech = this.enemy.mechState && Object.values(this.enemy.mechState).some(m => m.isCharging);
        if (hasCastingMech) {
            this.enemy.isMoving = false;
            return;
        }

        const phases = this.config.movementPhases || [];
        const currentPhase = phases[this.enemy._currentPhaseIndex || 0];
        const activeType = currentPhase ? currentPhase.type : (this.config.movementAI || 'chase');

        switch (activeType) {
            case 'chase':
                this._applyChaseMovement(target, dist, angle, now);
                break;
            case 'sniper':
                this._applySniperMovement(target, dist, angle, now);
                break;
            case 'orbit':
                this._applyOrbitMovement(target, dist, angle, now);
                break;
            case 'charger':
                this._applyChargerMovement(target, dist, angle, now);
                break;
            case 'zigzag':
                this._applyZigZagMovement(target, dist, angle, now);
                break;
            case 'prowler':
                this._applyProwlerMovement(target, dist, angle, now);
                break;
            case 'kamikaze':
                this._applyKamikazeMovement(target, dist, angle, now);
                break;
            case 'aura_speed':
                this._applyChaseMovement(target, dist, angle, now);
                break;
            case 'boss':
                if (typeof this.applyMovementLogic === 'function') {
                    this.applyMovementLogic(target, dist, angle, now, io);
                } else {
                    this._applyChaseMovement(target, dist, angle, now);
                }
                break;
            default:
                if (typeof this.applyMovementLogic === 'function') {
                    this.applyMovementLogic(target, dist, angle, now, io);
                } else {
                    this._applyChaseMovement(target, dist, angle, now);
                }
                break;
        }
    }

    _applyChaseMovement(target, dist, angle, now) {
        const speed = this.getSpeed();
        const stopDist = this.config.stopDist || 80;
        if (dist > stopDist) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < stopDist - 20) {
            this.enemy.x -= Math.cos(angle) * (speed * 0.4);
            this.enemy.y -= Math.sin(angle) * (speed * 0.4);
        }
        this.enemy.rotation = angle + Math.PI / 2;

        if (this.enemy.hp < this.enemy.maxHp * 0.15 && now - (this.enemy.lastDash || 0) > 8000) {
            const dashAngle = angle + (Math.PI / 2 + (Math.random() - 0.5));
            this.enemy.x += Math.cos(dashAngle) * 250;
            this.enemy.y += Math.sin(dashAngle) * 250;
            this.enemy.lastDash = now;
        }
    }

    _applySniperMovement(target, dist, angle, now) {
        const speed = this.getSpeed();
        const idealDist = this.config.idealDist || 450;
        
        if (dist > idealDist + 50) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < idealDist - 50) {
            this.enemy.x -= Math.cos(angle) * (speed * 1.2);
            this.enemy.y -= Math.sin(angle) * (speed * 1.2);
        } else {
            const orbitAngle = angle + Math.PI / 2;
            this.enemy.x += Math.cos(orbitAngle) * (speed * 0.5);
            this.enemy.y += Math.sin(orbitAngle) * (speed * 0.5);
        }
        this.enemy.rotation = angle + Math.PI / 2;
    }

    _applyOrbitMovement(target, dist, angle, now) {
        const orbitRadius = this.config.orbitRadius || 250;
        if (this._orbitDir === undefined) {
            this._orbitDir = Math.random() > 0.5 ? 1 : -1;
        }
        const speed = this.getSpeed();

        if (dist > orbitRadius + 50) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        } else if (dist < orbitRadius - 50) {
            this.enemy.x -= Math.cos(angle) * speed;
            this.enemy.y -= Math.sin(angle) * speed;
        }

        const orbitAngle = angle + (Math.PI / 2 * this._orbitDir);
        this.enemy.x += Math.cos(orbitAngle) * speed * 0.8;
        this.enemy.y += Math.sin(orbitAngle) * speed * 0.8;

        this.enemy.rotation = angle + Math.PI / 2;

        if (this.enemy.hp < this.enemy.maxHp * 0.25 && now - (this.enemy.lastDash || 0) > 10000) {
            const dashAngle = angle + (Math.PI / 2 + (Math.random() - 0.5));
            this.enemy.x += Math.cos(dashAngle) * 200;
            this.enemy.y += Math.sin(dashAngle) * 200;
            this.enemy.lastDash = now;
        }
    }

    _applyChargerMovement(target, dist, angle, now) {
        const speed = this.getSpeed();
        const chargeCooldown = (this.config.chargeCooldown || 4000) + Math.random() * 2000;

        if (this._chargerIsCharging) {
            const chargeDuration = 600;
            if (now - this._chargerStartTime < chargeDuration) {
                this.enemy.x += Math.cos(this._chargerDirection) * (speed * 4);
                this.enemy.y += Math.sin(this._chargerDirection) * (speed * 4);
                return;
            } else {
                this._chargerIsCharging = false;
                this._chargerLastChargeTime = now;
            }
        }

        if (!this._chargerIsCharging && dist < 500 && now - (this._chargerLastChargeTime || 0) > chargeCooldown) {
            this._chargerIsCharging = true;
            this._chargerStartTime = now;
            this._chargerDirection = angle;
            return;
        }

        if (dist > 30) {
            this.enemy.x += Math.cos(angle) * speed;
            this.enemy.y += Math.sin(angle) * speed;
        }
        this.enemy.rotation = angle + Math.PI / 2;
    }

    _applyZigZagMovement(target, dist, angle, now) {
        const speed = this.getSpeed();
        const stopDist = this.config.stopDist || 150;
        const amplitude = this.config.amplitude !== undefined ? this.config.amplitude : 100;
        const frequency = this.config.frequency !== undefined ? this.config.frequency : 1.5;

        if (dist > stopDist) {
            const dirX = Math.cos(angle);
            const dirY = Math.sin(angle);
            const perpX = -dirY;
            const perpY = dirX;

            const timeSec = now / 1000;
            const phase = 2 * Math.PI * frequency * timeSec;
            const lateralSpeedMult = Math.cos(phase);

            const stepForwardX = dirX * speed;
            const stepForwardY = dirY * speed;

            const stepLateralX = perpX * (amplitude * 2 * Math.PI * frequency) * lateralSpeedMult * 0.033;
            const stepLateralY = perpY * (amplitude * 2 * Math.PI * frequency) * lateralSpeedMult * 0.033;

            this.enemy.x += stepForwardX + stepLateralX;
            this.enemy.y += stepForwardY + stepLateralY;
        } else if (dist < stopDist - 20) {
            this.enemy.x -= Math.cos(angle) * (speed * 0.4);
            this.enemy.y -= Math.sin(angle) * (speed * 0.4);
        }

        this.enemy.rotation = angle + Math.PI / 2;

        if (this.enemy.hp < this.enemy.maxHp * 0.15 && now - (this.enemy.lastDash || 0) > 8000) {
            const dashAngle = angle + (Math.PI / 2 + (Math.random() - 0.5));
            this.enemy.x += Math.cos(dashAngle) * 250;
            this.enemy.y += Math.sin(dashAngle) * 250;
            this.enemy.lastDash = now;
        }
    }

    _applyProwlerMovement(target, dist, angle, now) {
        if (target && target.id !== "altar") {
            this._applyChaseMovement(target, dist, angle, now);
            return;
        }

        const speed = this.getSpeed();
        const patrolRange = this.config.patrolRange !== undefined ? Number(this.config.patrolRange) : 300;
        const changeTrigger = (this.config.changeTrigger === 'time' || this.config.changeTrigger === 'distance') ? this.config.changeTrigger : 'time';
        const changeType = (this.config.changeType === 'random' || this.config.changeType === 'reverse' || this.config.changeType === 'orthogonal') ? this.config.changeType : 'random';
        const changeInterval = this.config.changeInterval !== undefined ? Number(this.config.changeInterval) : 4000;

        if (this._prowlerAngle === undefined) {
            this._prowlerAngle = Math.random() * Math.PI * 2;
            this._prowlerLastChangeTime = now;
            this._prowlerLastChangeX = this.enemy.x;
            this._prowlerLastChangeY = this.enemy.y;
        }

        let shouldChange = false;
        if (changeTrigger === 'time') {
            if (now - this._prowlerLastChangeTime >= changeInterval) {
                shouldChange = true;
            }
        } else if (changeTrigger === 'distance') {
            const traveled = Math.hypot(this.enemy.x - this._prowlerLastChangeX, this.enemy.y - this._prowlerLastChangeY);
            if (traveled >= changeInterval) {
                shouldChange = true;
            }
        }

        const distFromSpawn = Math.hypot(this.enemy.x - this.enemy.startX, this.enemy.y - this.enemy.startY);
        const outOfBounds = distFromSpawn > patrolRange;

        if (shouldChange || outOfBounds) {
            if (outOfBounds) {
                this._prowlerAngle = Math.atan2(this.enemy.startY - this.enemy.y, this.enemy.startX - this.enemy.x);
            } else {
                if (changeType === 'random') {
                    this._prowlerAngle = Math.random() * Math.PI * 2;
                } else if (changeType === 'reverse') {
                    this._prowlerAngle = this._prowlerAngle + Math.PI;
                } else if (changeType === 'orthogonal') {
                    this._prowlerAngle = this._prowlerAngle + (Math.random() > 0.5 ? Math.PI / 2 : -Math.PI / 2);
                } else {
                    this._prowlerAngle = Math.random() * Math.PI * 2;
                }
            }

            while (this._prowlerAngle < -Math.PI) this._prowlerAngle += Math.PI * 2;
            while (this._prowlerAngle > Math.PI) this._prowlerAngle -= Math.PI * 2;

            this._prowlerLastChangeTime = now;
            this._prowlerLastChangeX = this.enemy.x;
            this._prowlerLastChangeY = this.enemy.y;
        }

        const maps = (this.state && this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.mapsConfig) ? this.state.SERVER_CONFIG.mapsConfig : {};
        const mapCfg = maps[this.enemy.zone] || {};
        const mapWidth = Number(mapCfg.width) || 4000;
        const mapHeight = Number(mapCfg.height) || 4000;
        const margin = 80;
        let hitBorder = false;

        let nextX = this.enemy.x + Math.cos(this._prowlerAngle) * speed;
        let nextY = this.enemy.y + Math.sin(this._prowlerAngle) * speed;

        if (nextX <= margin) {
            nextX = margin;
            hitBorder = true;
        } else if (nextX >= mapWidth - margin) {
            nextX = mapWidth - margin;
            hitBorder = true;
        }

        if (nextY <= margin) {
            nextY = margin;
            hitBorder = true;
        } else if (nextY >= mapHeight - margin) {
            nextY = mapHeight - margin;
            hitBorder = true;
        }

        if (hitBorder) {
            this._prowlerAngle = Math.atan2(mapHeight / 2 - this.enemy.y, mapWidth / 2 - this.enemy.x);
            while (this._prowlerAngle < -Math.PI) this._prowlerAngle += Math.PI * 2;
            while (this._prowlerAngle > Math.PI) this._prowlerAngle -= Math.PI * 2;

            this._prowlerLastChangeTime = now;
            this._prowlerLastChangeX = this.enemy.x;
            this._prowlerLastChangeY = this.enemy.y;
        }

        this.enemy.x = nextX;
        this.enemy.y = nextY;
        this.enemy.rotation = this._prowlerAngle + Math.PI / 2;
    }

    _applyKamikazeMovement(target, dist, angle, now) {
        this._applyChaseMovement(target, dist, angle, now);
    }
};
