// Server/systems/ThreatTable.js
/**
 * ThreatTable.js
 * Sistema de Agro y Amenaza Profesional AAA para Descon MMORPG.
 * 
 * Implementa la arquitectura estándar de Threat Table de los grandes MMORPGs (WoW, FFXIV):
 * - Tabla de amenaza por entidad (daño, curación, mitigación/tanqueo).
 * - Histéresis y Umbrales de despegue (Peel Thresholds): 110% en melee, 130% a rango para evitar 'ping-pong' errático.
 * - Provocación autoritativa (Taunt) con fijación de objetivo + equiparación de amenaza máxima con bonus.
 * - Multiplicador de Rol de Tanque (Tank Stance / Aura de Tanqueo).
 * - Distribución de amenaza de curación entre enemigos cercanos en combate.
 * - Decaimiento de amenaza (Threat Decay) para agresores inactivos.
 * - Limpieza inmediata al morir, entrar en sigilo/invisibilidad o salir de zona/leash.
 * - Integración con Altar en modalidades Altar Defense / Altar Rush.
 * - Configuración reactiva en tiempo real desde AdminDash (config.json).
 */

const DEFAULT_AGGRO_CONFIG = {
    enabled: true,
    damageThreatMultiplier: 1.0,         // 1 daño infligido = 1 pt de amenaza base
    healingThreatMultiplier: 0.5,        // 1 curación = 0.5 pts de amenaza repartida entre enemigos
    tankDamageTakenMultiplier: 1.5,      // 1 daño recibido/mitigado = 1.5 pts de amenaza para el tanque
    tankRoleThreatMultiplier: 3.5,       // Bono multiplicador pasivo de amenaza para tanques (3.5x)
    meleePeelThreshold: 1.10,            // Requiere 110% de amenaza para quitarle el agro al objetivo actual en melee
    rangedPeelThreshold: 1.30,           // Requiere 130% de amenaza para quitarle el agro a distancia
    meleeRangeThreshold: 250,            // Radio en px considerado cuerpo a cuerpo
    threatDecayRatePercent: 5,           // Decaimiento de 5% por segundo tras inactividad
    threatDecayDelayMs: 5000,            // Milisegundos de inactividad antes de comenzar decaimiento
    tauntBonusPercent: 10,               // Bonus de amenaza que recibe el tanque sobre el top actual (+10%)
    initialPullThreat: 100,              // Amenaza inicial al avistar a un jugador agresivo
    healingThreatRadius: 1000,           // Radio de percepción de curación por enemigos
    altarBaseThreat: 500                 // Amenaza base del Altar en modo Defensa del Altar
};

class ThreatTable {
    constructor(enemy, state) {
        this.enemy = enemy;
        this.state = state;
        this.entries = new Map(); // socketId -> { threat, damageThreat, healThreat, tankThreat, lastActionTime, name }
        this.currentTargetId = null;
        this.tauntTargetId = null;
        this.tauntEndTime = 0;
        this.lastDecayTime = Date.now();
    }

    /**
     * Obtiene la configuración de agro efectiva combinando servidor global + overrides del enemigo
     */
    getConfig() {
        const globalCfg = (this.state && this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.aggroConfig) 
            ? this.state.SERVER_CONFIG.aggroConfig 
            : DEFAULT_AGGRO_CONFIG;

        const enemyCfg = this.enemy.config || (this.state?.SERVER_CONFIG?.enemyModels?.[this.enemy.type?.toString()]) || {};

        if (enemyCfg.useCustomAggro) {
            return {
                ...globalCfg,
                damageThreatMultiplier: enemyCfg.aggroDamageMult !== undefined ? Number(enemyCfg.aggroDamageMult) : globalCfg.damageThreatMultiplier,
                healingThreatMultiplier: enemyCfg.aggroHealMult !== undefined ? Number(enemyCfg.aggroHealMult) : globalCfg.healingThreatMultiplier,
                tankDamageTakenMultiplier: enemyCfg.aggroTankMult !== undefined ? Number(enemyCfg.aggroTankMult) : globalCfg.tankDamageTakenMultiplier,
                meleePeelThreshold: enemyCfg.aggroPeelThreshold !== undefined ? Number(enemyCfg.aggroPeelThreshold) : globalCfg.meleePeelThreshold,
                immuneToTaunt: !!enemyCfg.immuneToTaunt
            };
        }

        return globalCfg;
    }

    /**
     * Determina si un jugador tiene rol o armamento de Tanque
     */
    isPlayerTank(p) {
        if (!p) return false;
        // 1. Rol asignado en Party (WoW / FFXIV style)
        if (this.state && this.state.playerParty && this.state.parties) {
            const pUid = p.dbId || (p.id ? p.id.toString() : null);
            if (pUid) {
                const partyId = this.state.playerParty[pUid];
                if (partyId && this.state.parties[partyId] && this.state.parties[partyId].roles) {
                    if (this.state.parties[partyId].roles[pUid] === 'tank') return true;
                }
            }
        }
        // 2. Munición o Armamento Melee de Tanque
        if (p.equippedAmmo && String(p.equippedAmmo).startsWith('am_m')) return true;
        if (p.selectedAmmo && String(p.selectedAmmo).startsWith('am_m')) return true;
        if (p.role === 'tank') return true;
        return false;
    }

    /**
     * Registra o actualiza una entrada en la tabla
     */
    _getOrCreateEntry(targetId, playerName = 'Desconocido') {
        let entry = this.entries.get(targetId);
        if (!entry) {
            entry = {
                targetId: targetId,
                threat: 0,
                damageThreat: 0,
                healThreat: 0,
                tankThreat: 0,
                lastActionTime: Date.now(),
                name: playerName
            };
            this.entries.set(targetId, entry);
        }
        return entry;
    }

    /**
     * 1. GENERACIÓN DE AGRO POR DAÑO
     * Invocado cuando un jugador golpea al enemigo
     */
    addDamageThreat(socketId, damage, playerObj = null) {
        if (!socketId || !damage || damage <= 0) return 0;
        const cfg = this.getConfig();
        if (cfg.enabled === false) return 0;

        const p = playerObj || (this.state?.players?.[socketId]);
        const pName = p ? (p.user || p.username || 'Jugador') : 'Jugador';
        const isTank = this.isPlayerTank(p);

        const roleMult = isTank ? (cfg.tankRoleThreatMultiplier || 3.5) : 1.0;
        const threatGain = damage * (cfg.damageThreatMultiplier !== undefined ? cfg.damageThreatMultiplier : 1.0) * roleMult;

        const entry = this._getOrCreateEntry(socketId, pName);
        entry.threat += threatGain;
        entry.damageThreat += threatGain;
        entry.lastActionTime = Date.now();

        // Actualizar último impacto y combate en el enemigo
        this.enemy.lastHit = Date.now();
        this.enemy.lastHitter = socketId;

        return threatGain;
    }

    /**
     * 2. GENERACIÓN DE AGRO POR CURACIÓN
     * Invocado cuando un jugador cura a un aliado o a sí mismo
     */
    addHealingThreat(healerSocketId, healAmount, activeEnemiesCount = 1, healerObj = null) {
        if (!healerSocketId || !healAmount || healAmount <= 0) return 0;
        const cfg = this.getConfig();
        if (cfg.enabled === false) return 0;

        const p = healerObj || (this.state?.players?.[healerSocketId]);
        const pName = p ? (p.user || p.username || 'Sanador') : 'Sanador';

        // En MMOs AAA, la curación genera amenaza distribuida entre todos los enemigos activos
        const enemyCount = Math.max(1, activeEnemiesCount);
        const threatGain = (healAmount * (cfg.healingThreatMultiplier !== undefined ? cfg.healingThreatMultiplier : 0.5)) / enemyCount;

        const entry = this._getOrCreateEntry(healerSocketId, pName);
        entry.threat += threatGain;
        entry.healThreat += threatGain;
        entry.lastActionTime = Date.now();

        return threatGain;
    }

    /**
     * 3. GENERACIÓN DE AGRO POR TANQUEO (Mitigación / Recibir Daño)
     * Invocado cuando el enemigo golpea al jugador
     */
    addTankingThreat(victimSocketId, damageTaken, victimObj = null) {
        if (!victimSocketId || !damageTaken || damageTaken <= 0) return 0;
        const cfg = this.getConfig();
        if (cfg.enabled === false) return 0;

        const p = victimObj || (this.state?.players?.[victimSocketId]);
        const pName = p ? (p.user || p.username || 'Tanque') : 'Tanque';
        const isTank = this.isPlayerTank(p);

        // Los tanques generan agro masivo por absorber y resistir ataques del enemigo
        const baseTankMult = cfg.tankDamageTakenMultiplier !== undefined ? cfg.tankDamageTakenMultiplier : 1.5;
        const roleMult = isTank ? (cfg.tankRoleThreatMultiplier || 3.5) : 1.0;
        const threatGain = damageTaken * baseTankMult * roleMult;

        const entry = this._getOrCreateEntry(victimSocketId, pName);
        entry.threat += threatGain;
        entry.tankThreat += threatGain;
        entry.lastActionTime = Date.now();

        return threatGain;
    }

    /**
     * 4. MECÁNICA DE PROVOCACIÓN (TAUNT) AAA
     * Fija el objetivo obligatoriamente y eleva la amenaza del tanque al top + bonus
     */
    applyTaunt(tankSocketId, durationMs = 4000, bonusPercent = null) {
        if (!tankSocketId) return false;
        const cfg = this.getConfig();
        if (cfg.enabled === false || cfg.immuneToTaunt) return false;

        const now = Date.now();
        const p = this.state?.players?.[tankSocketId];
        const pName = p ? (p.user || p.username || 'Tanque') : 'Tanque';

        // 1. Obtener la amenaza más alta de la tabla actualmente
        let highestThreat = 0;
        for (const [id, e] of this.entries.entries()) {
            if (id !== tankSocketId && e.threat > highestThreat) {
                highestThreat = e.threat;
            }
        }

        // 2. Establecer el valor de amenaza del tanque al máximo + bonus porcentual
        const bonusPct = bonusPercent !== null ? bonusPercent : (cfg.tauntBonusPercent !== undefined ? cfg.tauntBonusPercent : 10);
        const bonusMult = 1.0 + (bonusPct / 100);
        const newTankThreat = Math.max(highestThreat * bonusMult, (this.entries.get(tankSocketId)?.threat || 0) + (highestThreat * 0.1) + 100);

        const entry = this._getOrCreateEntry(tankSocketId, pName);
        entry.threat = Math.max(entry.threat, newTankThreat);
        entry.tankThreat += (newTankThreat - entry.threat);
        entry.lastActionTime = now;

        // 3. Fijación de Provocación temporal autoritativa
        this.tauntTargetId = tankSocketId;
        this.tauntEndTime = now + durationMs;
        this.currentTargetId = tankSocketId;

        // Sincronizar con campos legacy del enemigo
        this.enemy.forcedTarget = tankSocketId;
        this.enemy.tauntEndTime = this.tauntEndTime;

        return true;
    }

    /**
     * 5. AGRO INICIAL POR AVISTAMIENTO (Pull)
     */
    addPullThreat(socketId, playerObj = null) {
        if (!socketId) return;
        const cfg = this.getConfig();
        if (cfg.enabled === false) return;
        const initial = cfg.initialPullThreat !== undefined ? cfg.initialPullThreat : 100;
        const p = playerObj || (this.state?.players?.[socketId]);
        const pName = p ? (p.user || p.username || 'Jugador') : 'Jugador';

        const entry = this._getOrCreateEntry(socketId, pName);
        if (entry.threat < initial) {
            entry.threat = initial;
            entry.lastActionTime = Date.now();
        }
    }

    /**
     * 6. DECAIMIENTO DE AMENAZA (Threat Decay)
     * Reduce lentamente el agro de jugadores que han dejado de actuar
     */
    decay(now = Date.now()) {
        const cfg = this.getConfig();
        if (cfg.enabled === false) return;

        const dtSec = (now - this.lastDecayTime) / 1000;
        if (dtSec < 1.0) return; // Procesar una vez por segundo
        this.lastDecayTime = now;

        const decayRate = (cfg.threatDecayRatePercent !== undefined ? cfg.threatDecayRatePercent : 5) / 100;
        const decayDelay = cfg.threatDecayDelayMs !== undefined ? cfg.threatDecayDelayMs : 5000;

        for (const [id, entry] of this.entries.entries()) {
            if ((now - entry.lastActionTime) > decayDelay) {
                entry.threat = Math.max(0, entry.threat * (1 - decayRate * dtSec));
                if (entry.threat < 1) {
                    this.entries.delete(id);
                }
            }
        }
    }

    /**
     * 7. SELECCIÓN DE OBJETIVO TOP CON HISTÉRESIS (Anti-Jitter / Peel Threshold)
     * Decide qué jugador debe ser el objetivo principal del enemigo
     */
    getTopThreatTarget(players, options = {}) {
        const now = Date.now();
        this.decay(now);

        const cfg = this.getConfig();
        if (cfg.enabled === false) return null;

        // A. Verificar Provocación (Taunt) activa y prioritaria
        if (this.tauntTargetId && now < this.tauntEndTime) {
            const tauntPlayer = players[this.tauntTargetId];
            if (tauntPlayer && !tauntPlayer.isDead && !tauntPlayer.isInvisible) {
                this.currentTargetId = this.tauntTargetId;
                return tauntPlayer;
            }
            // Si el provocador murió o se volvió invisible, expirar el taunt
            this.tauntTargetId = null;
            this.tauntEndTime = 0;
            if (this.enemy.forcedTarget) this.enemy.forcedTarget = null;
        }

        // B. Filtrar candidatos válidos (Vivos, Visibles, en misma Zona y dentro de Leash)
        const candidates = [];
        const leashRange = Number(this.enemy.config?.leashRange) || 0;
        const visionRange = Number(this.enemy.config?.visionRange) || 800;

        for (const [socketId, entry] of this.entries.entries()) {
            const p = players[socketId];
            if (!p || p.isDead || p.isInvisible) {
                // Jugador muerto o en sigilo no es objetivo válido
                continue;
            }
            if (String(p.zone) !== String(this.enemy.zone)) {
                continue;
            }

            const distToEnemy = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);

            // Verificar Leash si aplica
            if (leashRange > 0 && this.enemy.startX !== undefined) {
                const distFromSpawn = Math.hypot(p.x - this.enemy.startX, p.y - this.enemy.startY);
                if (distFromSpawn > leashRange) continue;
            }

            candidates.push({
                player: p,
                socketId: socketId,
                threat: entry.threat,
                distance: distToEnemy
            });
        }

        if (candidates.length === 0) {
            this.currentTargetId = null;
            return null;
        }

        // C. Ordenar candidatos por amenaza descendente
        candidates.sort((a, b) => b.threat - a.threat);
        const topCandidate = candidates[0];

        // D. Si no hay objetivo actual o el objetivo actual ya no es candidato válido, toma agro el top
        const currentTargetCandidate = this.currentTargetId 
            ? candidates.find(c => c.socketId === this.currentTargetId) 
            : null;

        if (!currentTargetCandidate) {
            this.currentTargetId = topCandidate.socketId;
            return topCandidate.player;
        }

        // E. Si el top es el mismo que el actual, mantenerlo
        if (topCandidate.socketId === this.currentTargetId) {
            return currentTargetCandidate.player;
        }

        // F. HISTÉRESIS (Peel Threshold AAA):
        // Para que un nuevo atacante robe el agro al objetivo actual, su amenaza debe superar
        // a la del objetivo actual por el umbral configurado (110% en melee, 130% a rango).
        const meleeDist = cfg.meleeRangeThreshold !== undefined ? cfg.meleeRangeThreshold : 250;
        const isMelee = topCandidate.distance <= meleeDist;
        const requiredMultiplier = isMelee 
            ? (cfg.meleePeelThreshold !== undefined ? cfg.meleePeelThreshold : 1.10)
            : (cfg.rangedPeelThreshold !== undefined ? cfg.rangedPeelThreshold : 1.30);

        const requiredThreat = currentTargetCandidate.threat * requiredMultiplier;

        if (topCandidate.threat >= requiredThreat) {
            // Despegue de agro exitoso (Peel)
            this.currentTargetId = topCandidate.socketId;
            return topCandidate.player;
        }

        // Mantener objetivo actual si no se superó el umbral de histéresis
        return currentTargetCandidate.player;
    }

    /**
     * Limpia la amenaza de un jugador específico (muerte, desconexión, desvanecimiento)
     */
    clearTarget(socketId) {
        if (!socketId) return;
        this.entries.delete(socketId);
        if (this.currentTargetId === socketId) this.currentTargetId = null;
        if (this.tauntTargetId === socketId) {
            this.tauntTargetId = null;
            this.tauntEndTime = 0;
            if (this.enemy.forcedTarget === socketId) this.enemy.forcedTarget = null;
        }
    }

    /**
     * Reseteo completo de la tabla (Evasión, Retorno al Spawn, Reset del Boss)
     */
    reset() {
        this.entries.clear();
        this.currentTargetId = null;
        this.tauntTargetId = null;
        this.tauntEndTime = 0;
        this.lastDecayTime = Date.now();
        if (this.enemy.forcedTarget) this.enemy.forcedTarget = null;
    }

    /**
     * Retorna una instantánea limpia de la tabla para depuración o interfaces HUD
     */
    getThreatSnapshot() {
        const list = [];
        let total = 0;
        for (const [id, entry] of this.entries.entries()) {
            list.push({ ...entry });
            total += entry.threat;
        }
        list.sort((a, b) => b.threat - a.threat);
        return {
            currentTargetId: this.currentTargetId,
            tauntTargetId: this.tauntTargetId,
            tauntEndTime: this.tauntEndTime,
            totalThreat: total,
            entries: list
        };
    }
}

module.exports = {
    ThreatTable,
    DEFAULT_AGGRO_CONFIG
};
