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

const { countPlayerSphereColors } = require('./equipRequirements');

const DEFAULT_AGGRO_CONFIG = {
    enabled: true,
    damageThreatMultiplier: 1.0,         // 1 daño infligido = 1 pt de amenaza base
    healingThreatMultiplier: 0.5,        // 1 curación = 0.5 pts de amenaza repartida entre enemigos
    tankDamageTakenMultiplier: 1.5,      // 1 daño recibido/mitigado = 1.5 pts de amenaza base
    tankRoleThreatMultiplier: 2.5,       // Multiplicador extra de rol tanque otorgado al jugador con más esferas azules del grupo (2.5x)
    sphereBlueThreatBonus: 0.50,         // +50% amenaza por cada esfera azul equipada (Defensa/Tanqueo)
    sphereRedThreatBonus: 0.15,          // +15% amenaza por cada esfera roja equipada (Ataque/DPS)
    sphereGreenThreatBonus: 0.25,        // +25% amenaza por cada esfera verde equipada (Curación/Soporte)
    sphereYellowThreatBonus: 0.10,       // +10% amenaza por cada esfera amarilla equipada (Utilidad/Movilidad)
    meleePeelThreshold: 1.10,            // Requiere 110% de amenaza para quitarle el agro al objetivo actual en melee
    rangedPeelThreshold: 1.30,           // Requiere 130% de amenaza para quitarle el agro a distancia
    meleeRangeThreshold: 250,            // Radio en px considerado cuerpo a cuerpo
    threatDecayRatePercent: 5,           // Decaimiento de 5% por segundo tras inactividad
    threatDecayDelayMs: 5000,            // Milisegundos de inactividad antes de comenzar decaimiento
    tauntBonusPercent: 10,               // Bonus de amenaza que recibe el tanque sobre el top actual (+10%)
    initialPullThreat: 100,              // Amenaza inicial al avistar a un jugador agresivo
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
     * Calcula el área o radio de visión efectivo del enemigo (considerando Boss, Horda o Modificador Ambiental)
     */
    getEffectiveVisionRange() {
        if (!this.enemy) return 800;
        if (this.enemy.ai && this.enemy.ai.ambienceBoost) return 50000;
        if (this.enemy.isHorde) return 10000;
        const cfgVision = Number(this.enemy.config?.visionRange);
        if (!isNaN(cfgVision) && cfgVision > 0) return cfgVision;
        if (this.enemy.isBoss || this.enemy.aiType === 'boss') return 2000;
        return 800;
    }

    /**
     * Determina autoritativamente si un jugador califica como el Tanque del grupo.
     * En lugar de depender de un simple rol de texto en la party, se basa en las esferas azules
     * (Defensa). El jugador con la mayor cantidad de esferas azules del grupo/party (mínimo 1 esfera azul)
     * es consagrado como el Tanque oficial del grupo.
     * Si juega en solitario, requiere al menos 1 esfera azul.
     */
    isGroupTank(player) {
        if (!player) return false;
        const counts = countPlayerSphereColors(player.spheres);
        const playerBlues = counts.azul || 0;
        if (playerBlues <= 0) return false; // Sin esferas azules no puede ser tanque

        // Si el jugador está en Party, comparar con todos los miembros de la party en el estado
        if (this.state && this.state.playerParty && this.state.parties) {
            const pUid = player.dbId || (player.id ? player.id.toString() : null);
            if (pUid) {
                const partyId = this.state.playerParty[pUid];
                const party = partyId ? this.state.parties[partyId] : null;
                if (party && Array.isArray(party.members) && party.members.length > 1) {
                    for (const memberInfo of party.members) {
                        const mUid = typeof memberInfo === 'object' ? memberInfo.id : memberInfo;
                        if (!mUid || String(mUid) === String(pUid)) continue;

                        // Buscar objeto de jugador activo
                        let memberPlayer = null;
                        if (this.state.players) {
                            for (const sid in this.state.players) {
                                const cand = this.state.players[sid];
                                const candUid = cand.dbId || (cand.id ? cand.id.toString() : null);
                                if (String(candUid) === String(mUid)) {
                                    memberPlayer = cand;
                                    break;
                                }
                            }
                        }

                        if (memberPlayer) {
                            // Si están en zonas distintas, solo compiten los que estén en la misma zona del enemigo
                            if (this.enemy && memberPlayer.zone !== undefined && String(memberPlayer.zone) !== String(this.enemy.zone)) {
                                continue;
                            }
                            const memberBlues = (countPlayerSphereColors(memberPlayer.spheres).azul || 0);
                            if (memberBlues > playerBlues) {
                                return false; // Otro miembro tiene más esferas azules
                            }
                        }
                    }
                    return true; // Es el miembro con más esferas azules (o empatado en el tope)
                }
            }
        }

        // Jugador en solitario o sin compañeros en zona: tener al menos 1 esfera azul le otorga el rol tanque
        return playerBlues > 0;
    }

    /**
     * Calcula el multiplicador total de amenaza para un jugador basándose en:
     * 1. Esferas equipadas (Azules = Defensa/Tanqueo, Rojas = Ataque/DPS, Verdes = Curación/Soporte, Amarillas = Utilidad).
     * 2. Bono de Rol Tanque si es el miembro con más esferas azules del grupo.
     */
    getPlayerThreatMultiplier(player, actionType = 'all') {
        if (!player) return 1.0;
        const cfg = this.getConfig();
        const counts = countPlayerSphereColors(player.spheres);

        const blues = counts.azul || 0;
        const reds = counts.roja || 0;
        const greens = counts.verde || 0;
        const yellows = counts.amarilla || 0;

        const blueBonus = Number(cfg.sphereBlueThreatBonus !== undefined ? cfg.sphereBlueThreatBonus : 0.50);
        const redBonus = Number(cfg.sphereRedThreatBonus !== undefined ? cfg.sphereRedThreatBonus : 0.15);
        const greenBonus = Number(cfg.sphereGreenThreatBonus !== undefined ? cfg.sphereGreenThreatBonus : 0.25);
        const yellowBonus = Number(cfg.sphereYellowThreatBonus !== undefined ? cfg.sphereYellowThreatBonus : 0.10);

        // Suma de bonos pasivos por cada esfera orbital
        let sphereMult = 1.0 + (blues * blueBonus) + (reds * redBonus) + (greens * greenBonus) + (yellows * yellowBonus);

        // Bono de Tanque del Grupo (+ esferas azules)
        if (this.isGroupTank(player)) {
            const tankRoleMult = Number(cfg.tankRoleThreatMultiplier !== undefined ? cfg.tankRoleThreatMultiplier : 2.5);
            sphereMult *= tankRoleMult;
        }

        return Math.max(0.1, sphereMult);
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
     * Invocado cuando un jugador golpea al enemigo (desde cualquier distancia)
     */
    addDamageThreat(socketId, damage, playerObj = null) {
        if (!socketId || !damage || damage <= 0) return 0;
        const cfg = this.getConfig();
        if (cfg.enabled === false) return 0;

        const p = playerObj || (this.state?.players?.[socketId]);
        const pName = p ? (p.user || p.username || 'Jugador') : 'Jugador';
        const playerThreatMult = this.getPlayerThreatMultiplier(p, 'damage');

        const threatGain = damage * (cfg.damageThreatMultiplier !== undefined ? cfg.damageThreatMultiplier : 1.0) * playerThreatMult;

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
        const playerThreatMult = this.getPlayerThreatMultiplier(p, 'healing');

        // En MMOs AAA, la curación genera amenaza distribuida entre todos los enemigos que perciben la curación
        const enemyCount = Math.max(1, activeEnemiesCount);
        const threatGain = ((healAmount * (cfg.healingThreatMultiplier !== undefined ? cfg.healingThreatMultiplier : 0.5)) / enemyCount) * playerThreatMult;

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
        const playerThreatMult = this.getPlayerThreatMultiplier(p, 'tank');

        // Los tanques generan agro masivo por absorber y resistir ataques del enemigo
        const baseTankMult = cfg.tankDamageTakenMultiplier !== undefined ? cfg.tankDamageTakenMultiplier : 1.5;
        const threatGain = damageTaken * baseTankMult * playerThreatMult;

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

    /**
     * Retorna la amenaza acumulada de un socketId específico (aplicando decay previo)
     */
    getThreat(socketId) {
        if (!socketId) return 0;
        this.decay(Date.now());
        const entry = this.entries.get(socketId);
        return (entry && typeof entry.threat === 'number') ? entry.threat : 0;
    }
}

module.exports = {
    ThreatTable,
    DEFAULT_AGGRO_CONFIG
};
