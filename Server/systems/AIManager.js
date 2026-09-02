const ChaseAI = require('../behaviors/ChaseAI');
const OrbitAI = require('../behaviors/OrbitAI');
const BossAI = require('../behaviors/BossAI');
const AncientBossAI = require('../behaviors/BossAI');
const MechanicBossAI = require('../behaviors/BossAI');
const SniperAI = require('../behaviors/SniperAI');
const ChargerAI = require('../behaviors/ChargerAI');
const GravityAI = require('../behaviors/GravityAI');
const ProwlerAI = require('../behaviors/ProwlerAI');
const ZigZagAI = require('../behaviors/ZigZagAI');
const Logger = require('../utils/logger');
const spawnValidator = require('../utils/spawnValidator');

/**
 * AIManager
 * Gestiona el spawn y la lógica de los enemigos.
 */
class AIManager {
    constructor(io, state, hordeManager) {
        this.io = io;
        this.state = state;
        this.hordeManager = hordeManager;
    }

    serverSpawnEnemy(zone = 1, forceType = null, posX = null, posY = null, forceName = null, isHorde = false, spawnerId = null, spawnerSlot = null, spawnerInterval = null) {
        const { enemies, SERVER_CONFIG } = this.state;
        
        const isHordeZone = this.hordeManager && this.hordeManager.config.active && this.hordeManager.config.map === zone;
        
        if (!forceType && zone === 2 && Object.keys(enemies).filter(e => enemies[e].zone === 2).length >= 15) return;
        
        let type = forceType || (Math.floor(Math.random() * 3) + 1);
        if (typeof type === 'string' && !isNaN(Number(type))) {
            type = Number(type);
        }
        let cfg = (SERVER_CONFIG && SERVER_CONFIG.enemyModels) ? SERVER_CONFIG.enemyModels[type.toString()] : null;
        if (!cfg && typeof type === 'string' && SERVER_CONFIG && SERVER_CONFIG.enemyModels) {
            const baseKey = type.split('-')[0].trim();
            if (SERVER_CONFIG.enemyModels[baseKey]) {
                cfg = SERVER_CONFIG.enemyModels[baseKey];
            }
        }
        
        const maps = (this.state && this.state.SERVER_CONFIG) ? (this.state.SERVER_CONFIG.mapsConfig || this.state.SERVER_CONFIG.maps || this.state.SERVER_CONFIG.mapData || {}) : {};
        let mapCfg = maps[zone] || maps[zone.toString()];
        if (!mapCfg) {
            mapCfg = Object.values(maps).find(m => m.name === zone || m.name === `Mapa ${zone}` || m.name === zone.toString());
        }
        
        const extremeAggro = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'extreme_aggression') : null;
        const multiplicadorMech = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'multiplicador') : null;
        const multiplicadorMult = multiplicadorMech ? (parseFloat(multiplicadorMech.multiplier) || 1) : 1;
        const hpMult = (extremeAggro ? (parseFloat(extremeAggro.healthMult) || 1) : 1) * multiplicadorMult;

        const isBoss = (typeof type === 'number' && type >= 101) || (cfg && cfg.isBoss);
        const id = 'enemy_' + (isBoss ? 'boss_' : '') + Date.now() + Math.floor(Math.random() * 1000);
        
        const name = forceName || (cfg ? cfg.name : (type === 101 ? "Lord Titán" : (type === 4 ? "Enemigo 4" : (type === 5 ? "Boss2" : (type === 6 ? "Boss3" : "Enemigo")))));

        const numericType = typeof type === 'number' ? type : parseInt(type) || 1;
        const initialHp = (cfg ? cfg.hp : (type === 6 ? 150000 : (type === 5 ? 200000 : (type === 101 ? 100000 : (numericType * 2000))))) * hpMult;
        const initialShield = (cfg ? cfg.shield : (type === 6 ? 75000 : (type === 5 ? 100000 : (type === 101 ? 50000 : (numericType * 1000))))) * hpMult;

        const mapWidth = (mapCfg && mapCfg.width) ? mapCfg.width : 4000;
        const mapHeight = (mapCfg && mapCfg.height) ? mapCfg.height : 4000;

        let finalX = posX !== null ? posX : (zone === 9 ? 2000 : (Math.random() * (mapWidth - 600) + 300));
        let finalY = posY !== null ? posY : (zone === 9 ? 2000 : (Math.random() * (mapHeight - 600) + 300));

        // Validación final: si el punto calculado cae dentro de collider, intentar recolocar
        // (cubre el fallback random sin spawner y cualquier pos forzada que no pasó por findValidSpawnPosition)
        if (spawnValidator.isPointBlocked(finalX, finalY, zone, this.state)) {
            const alt = spawnValidator.findValidSpawnPosition(finalX, finalY, 350, zone, this.state, { maxAttempts: 25 });
            if (alt) { finalX = alt.x; finalY = alt.y; }
            else {
                // último recurso: muestreo dentro del mapa hasta hallar punto libre
                let found = false;
                for (let k = 0; k < 40; k++) {
                    const rx = Math.random() * (mapWidth - 600) + 300;
                    const ry = Math.random() * (mapHeight - 600) + 300;
                    if (!spawnValidator.isPointBlocked(rx, ry, zone, this.state)) { finalX = rx; finalY = ry; found = true; break; }
                }
                if (!found) Logger.warn('SPAWN', `serverSpawnEnemy zona ${zone} no encontró punto libre, mantiene [${Math.round(finalX)},${Math.round(finalY)}] dentro de colisión`);
            }
        }

        const e = {
            id, type, zone, name,
            isHorde,
            x: finalX,
            y: finalY,
            startX: finalX,
            startY: finalY,
            hp: initialHp,
            maxHp: initialHp,
            shield: initialShield,
            maxShield: initialShield,
            rotation: 0,
            lastHit: 0,
            lastDash: 0,
            shotsInBurst: 0,
            nextShotTime: 0,
            isInvulnerable: false,
            spawnerId,
            spawnerSlot,
            spawnerInterval
        };

        // v268.850: Soporte para Fases de Movimiento (Priorizar velocidad de la fase 0)
        let rawSpeed = 3.5;
        if (cfg) {
            if (cfg.movementPhases && cfg.movementPhases.length > 0) {
                rawSpeed = cfg.movementPhases[0].speed || cfg.speed || 3.5;
            } else {
                rawSpeed = cfg.speed || 3.5;
            }
        } else {
            rawSpeed = (type === 1 ? 4.5 : 3.5);
        }

        const movSpeed = rawSpeed * 0.033;
        // v500.3: NO mezclar phase0 dentro de aiConfig — evitar que campos de la fase de
        // movimiento (stopDist, idealDist, startDelay, etc.) pisen valores raíz del cfg
        // (regenDelayMs, regenIntervalMs, hpRegenPercent, etc.).
        // La fase 0 se aplica dinámicamente en BaseAI._evaluatePhaseConditions al primer tick.
        const aiConfig = cfg ? { ...cfg, speed: movSpeed } : { bulletDamage: (numericType * 100), fireRate: 2000, speed: movSpeed, bulletSpeed: 800 };
        
        // v266.230: Asignación Dinámica de Cerebros basada en Configuración
        // v500.3: movementType se obtiene de cfg.movementAI o del tipo de la fase 0
        const phase0Type = (cfg && cfg.movementPhases && cfg.movementPhases[0]) ? cfg.movementPhases[0].type : null;
        const movementType = cfg ? (cfg.movementAI || phase0Type) : null;

        const AI_MAP = {
            "chase": ChaseAI,
            "sniper": SniperAI,
            "orbit": OrbitAI,
            "charger": ChargerAI,
            "gravity": GravityAI,
            "boss": BossAI,
            "ancient": AncientBossAI,
            "mechanic": MechanicBossAI,
            "prowler": ProwlerAI,
            "zigzag": ZigZagAI
        };

        if (movementType && AI_MAP[movementType]) {
            e.ai = new AI_MAP[movementType](e, aiConfig, this.state);
        } else {
            // Fallback para tipos hardcodeados antiguos si no hay config
            if (numericType === 103 || numericType === 102 || numericType === 101) e.ai = new BossAI(e, aiConfig, this.state); 
            else if (numericType === 8 || numericType === 3) e.ai = new ChargerAI(e, aiConfig, this.state);
            else if (numericType === 6 || numericType === 7) e.ai = new GravityAI(e, aiConfig, this.state);
            else if (numericType === 5 || numericType === 2 || numericType === 12) e.ai = new SniperAI(e, aiConfig, this.state); 
            else if (numericType === 1 || numericType === 9 || numericType === 13 || numericType === 4) e.ai = new ChaseAI(e, aiConfig, this.state); 
            else e.ai = new OrbitAI(e, aiConfig, this.state);
        }

        enemies[id] = e;

        const { ai, _hookSafetyTimeout, ...spawnData } = e;
        Logger.debug('SPAWN', `Enemigo ${name} [${type}] creado en Zona ${zone} (x:${Math.floor(finalX)}, y:${Math.floor(finalY)})`);
        this.io.to(`zone_${zone}`).emit('enemySpawn', spawnData);
        return e;
    }

    runGuardians() {
        // v266.400: Ecosistema Dinámico Basado en Cartografía
        if (this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.mapsConfig) {
            const maps = this.state.SERVER_CONFIG.mapsConfig;
            Object.keys(maps).forEach(mapId => {
                // v2.9.2: Ignorar mapas de eventos (10 para extracción, 9 para pvp arena, 11 para defensa del altar) del respawn genérico
                if (Number(mapId) === 10 || Number(mapId) === 9 || Number(mapId) === 11) return;
                
                const mCfg = maps[mapId];
                
                // v2.4: Omitir spawns en zonas sin jugadores activos
                if (!this.state.playersByZone[mapId] || Object.keys(this.state.playersByZone[mapId]).length === 0) return;

                if (mCfg.spawns && mCfg.spawns.length > 0) {
                    mCfg.spawns.forEach((s, idx) => {
                        // Asegurar identificador único del spawner
                        if (!s.id) {
                            s.id = `spawn_${mapId}_idx_${idx}_type_${s.type}`;
                        }

                        const count = s.count || 1;
                        for (let slot = 0; slot < count; slot++) {
                            const isAlive = Object.values(this.state.enemies).some(
                                e => e.zone == mapId && e.spawnerId === s.id && e.spawnerSlot === slot && e.hp > 0
                            );

                            if (!isAlive) {
                                const slotKey = `${s.id}_slot_${slot}`;
                                const respawnAt = this.state.spawnerCooldowns ? this.state.spawnerCooldowns[slotKey] : 0;
                                const now = Date.now();

                                if (!respawnAt || now >= respawnAt) {
                                    if (this.state.spawnerCooldowns) {
                                        delete this.state.spawnerCooldowns[slotKey];
                                    }

                                    // Determinar coordenadas según el modo
                                    let posX = null;
                                    let posY = null;

                                    if (s.spawnMode === 'fixed' && s.x !== undefined && s.y !== undefined) {
                                        // Incluso el modo fijo se valida: si cae dentro de pared, se desplaza al punto libre más cercano
                                        if (spawnValidator.isPointBlocked(s.x, s.y, mapId, this.state)) {
                                            const fallback = spawnValidator.findValidSpawnPosition(s.x, s.y, 120, mapId, this.state, { maxAttempts: 20 });
                                            if (fallback) { posX = fallback.x; posY = fallback.y; }
                                            else { posX = s.x; posY = s.y; Logger.warn('SPAWN', `Fixed spawn ${s.id} en zona ${mapId} está dentro de estructura y no se encontró alternativa cercana`); }
                                        } else {
                                            posX = s.x;
                                            posY = s.y;
                                        }
                                    } else if (s.spawnMode === 'random' && s.x !== undefined && s.y !== undefined && s.radius !== undefined && s.radius > 0) {
                                        const valid = spawnValidator.findValidSpawnPosition(s.x, s.y, s.radius, mapId, this.state, { maxAttempts: 35 });
                                        if (valid) {
                                            posX = valid.x;
                                            posY = valid.y;
                                        } else {
                                            // Fallback: sampling clásico pero igualmente fuera de estructura no garantizado
                                            const angle = Math.random() * Math.PI * 2;
                                            const r = Math.random() * s.radius;
                                            posX = s.x + Math.cos(angle) * r;
                                            posY = s.y + Math.sin(angle) * r;
                                            Logger.warn('SPAWN', `No se halló punto libre para ${s.id} en zona ${mapId} — se usa random sin filtro`);
                                        }
                                    }

                                    this.serverSpawnEnemy(
                                        parseInt(mapId),
                                        s.type,
                                        posX,
                                        posY,
                                        null,
                                        false,
                                        s.id,
                                        slot,
                                        s.intervalMs || 5000
                                    );
                                }
                            }
                        }
                    });
                }
            });
        }

    }
}

module.exports = AIManager;
