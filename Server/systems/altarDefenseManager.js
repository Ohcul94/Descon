const Logger = require('../utils/logger');
const spawnValidator = require('../utils/spawnValidator');

class AltarDefenseManager {
    constructor() {
        this.io = null;
        this.state = null;
        this.aiManager = null;
        
        this.activeMatch = null;
        this.checkInterval = null;
    }

    init(io, state, aiManager) {
        this.io = io;
        this.state = state;
        this.aiManager = aiManager;
        
        // Loop de chequeo del estado del evento cada 1.5 segundos
        if (this.checkInterval) clearInterval(this.checkInterval);
        this.checkInterval = setInterval(() => this.update(), 1500);
        
        Logger.success('ALTAR', 'AltarDefenseManager inicializado de forma autoritativa.');
    }

    startMatch(zoneId, membersList) {
        const adConfig = this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.gameModes && this.state.SERVER_CONFIG.gameModes.altar_defense;
        if (!adConfig) {
            Logger.error('ALTAR', `¡CRÍTICO! gameModes.altar_defense NO EXISTE en la config. La partida no se puede crear. Asegúrate de que el AdminDash o el server.js la inicialicen.`);
            return;
        }
        Logger.info('ALTAR', `startMatch() invocado — zoneId=${zoneId}, members=${membersList.length}, waves=${(adConfig.waves||[]).length}, spawners=${(adConfig.spawners||[]).length}`);

        // Purgar cualquier enemigo previo que estuviese en esta zona por residuo
        this.purgeEnemiesInZone(zoneId);

        const waveInterval = Number(adConfig.waveInterval) || 15000;
        const spawnLockTime = Number(adConfig.spawnLockTime) || 5000;

        const mapConfig = (this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.mapsConfig)
            ? this.state.SERVER_CONFIG.mapsConfig[zoneId]
            : null;

        // v770.7: Fuente única de verdad para altar y puertas = mapsConfig.objects (Editor 3D)
        // Se elimina hardcode de adConfig.altarPos / adConfig.exitPortals del AdminDash
        // v770.12: spawners también exclusivos Editor 3D tipo spawner (Puerta3)
        let altarPos = { x: 5000, y: 5000 };
        let exitPortals = [];
        let altarSpawners = [];
        if (mapConfig && Array.isArray(mapConfig.objects)) {
            const altarObj = mapConfig.objects.find(obj => obj.type === 'altar');
            if (altarObj) {
                altarPos = { x: Number(altarObj.x) || 5000, y: Number(altarObj.y) || 5000 };
                Logger.info('ALTAR', `Posición del altar cargada desde mapsConfig.objects (3D): [${altarPos.x}, ${altarPos.y}]`);
            } else if (adConfig.altarPos) {
                altarPos = { x: Number(adConfig.altarPos.x) || 5000, y: Number(adConfig.altarPos.y) || 5000 };
                Logger.warn('ALTAR', `No hay objeto tipo 'altar' en mapsConfig[${zoneId}].objects - usando fallback de config: [${altarPos.x}, ${altarPos.y}].`);
            }
            const doorObjects = mapConfig.objects.filter(obj => obj.type === 'door' || obj.type === 'portal');
            if (doorObjects.length > 0) {
                exitPortals = doorObjects.map((obj, idx) => ({
                    label: obj.label || `Escape${idx + 1}`,
                    radius: obj.radius || 150,
                    x: obj.x,
                    y: obj.y
                }));
                Logger.info('ALTAR', `Cargados ${exitPortals.length} portales de escape desde mapsConfig.objects (3D).`);
            } else {
                Logger.warn('ALTAR', `No hay puertas tipo 'door' en mapsConfig[${zoneId}].objects - Coloca puertas en el Editor 3D.`);
            }
            const spawnerObjs = mapConfig.objects.filter(obj => obj.type === 'spawner' || obj.type === 'enemy_spawner');
            if (spawnerObjs.length > 0) {
                altarSpawners = spawnerObjs.map(obj => ({
                    label: obj.label || `Spawner`,
                    radius: Number(obj.radius) || 500,
                    x: Number(obj.x) || 5000,
                    y: Number(obj.y) || 5000,
                    enemyId: String(obj.enemyId || "1"),
                    count: parseInt(obj.count) || 10
                }));
                Logger.info('ALTAR', `Cargados ${altarSpawners.length} spawners de enemigos desde mapsConfig.objects (Puerta3).`);
            } else if (adConfig.spawners && adConfig.spawners.length > 0) {
                altarSpawners = adConfig.spawners;
                Logger.warn('ALTAR', `No hay spawners tipo 'spawner' en mapsConfig[${zoneId}].objects - usando fallback adConfig.spawners (${altarSpawners.length}). Migra a Puerta3 en Editor 3D.`);
            } else {
                Logger.warn('ALTAR', `No hay spawners tipo 'spawner' en mapsConfig[${zoneId}].objects - Coloca Puerta3 tipo spawner en el Editor 3D.`);
            }
        } else if (adConfig.altarPos) {
            altarPos = { x: Number(adConfig.altarPos.x) || 5000, y: Number(adConfig.altarPos.y) || 5000 };
            if (adConfig.spawners && adConfig.spawners.length > 0) altarSpawners = adConfig.spawners;
        } else if (adConfig.spawners && adConfig.spawners.length > 0) {
            altarSpawners = adConfig.spawners;
        }

        // Inicializar el Altar State con coordenadas autoritativas del Editor 3D
        this.state.altarState = {
            hp: Number(adConfig.altarHp) || 10000,
            maxHp: Number(adConfig.altarHp) || 10000,
            shield: Number(adConfig.altarShield) || 5000,
            maxShield: Number(adConfig.altarShield) || 5000,
            zone: zoneId,
            x: altarPos.x,
            y: altarPos.y
        };
        adConfig.altarPos = { x: altarPos.x, y: altarPos.y };

        this.activeMatch = {
            zoneId: zoneId,
            members: membersList,
            currentWaveIndex: 0,
            waves: adConfig.waves || [],
            waveInterval: waveInterval,
            spawnLockTime: spawnLockTime,
            
            status: 'spawn_lock', // 'spawn_lock', 'wave_active', 'waiting_next_wave', 'finished'
            statusEndTime: Date.now() + spawnLockTime,
            exitPortals: exitPortals,
            altarPos: altarPos,
            altarSpawners: altarSpawners,
            // v770.3: tracking para evitar cierre prematuro de oleada antes de que spawneen
            waveSpawnedCount: 0,
            waveExpectedCount: 0,
            waveStartTime: 0
        };
        // Mantener adConfig.spawners sincronizado para inspección / compatibilidad retro
        if (altarSpawners.length > 0) adConfig.spawners = altarSpawners;


        Logger.info('ALTAR', `Partida de Defensa al Altar iniciada en zona ${zoneId}. altarPos=[${altarPos.x},${altarPos.y}], portales=${exitPortals.length}, oleadas=${(adConfig.waves||[]).length}, spawnLock=${spawnLockTime}ms.`);
        
        // Emitir los estados iniciales
        setTimeout(() => {
            this.emitAltarState();
            this.emitPortals([]); // Sin portales al inicio
        }, 800);
    }

    update() {
        if (!this.activeMatch || this.activeMatch.status === 'finished') return;

        const match = this.activeMatch;
        const now = Date.now();

        // Contar enemigos vivos de Defensa al Altar en la zona
        const currentEnemies = Object.values(this.state.enemies).filter(e => Number(e.zone) === Number(match.zoneId) && e.hp > 0);

        if (match.status === 'spawn_lock') {
            if (now >= match.statusEndTime) {
                // Termina el spawn lock, arranca la primera oleada
                Logger.info('ALTAR', `Spawn lock terminado. Iniciando oleada 1 de ${match.waves.length}.`);
                this.startWave(0);
            }
        } 
        else if (match.status === 'wave_active') {
            // v770.3: No cerrar la oleada si aún no spawneó nada o si quedan spawns pendientes (evita victoria instantánea cuando el spawn falla o es staggered)
            const graceMs = 3500; // tiempo mínimo desde inicio de oleada antes de poder cerrarla
            const hasGracePassed = !match.waveStartTime || (now - match.waveStartTime) >= graceMs;
            const allSpawned = match.waveSpawnedCount >= match.waveExpectedCount;
            // Solo completar si ya spawneó al menos 1, pasó la gracia, todos los esperados ya salieron y no quedan vivos
            if (currentEnemies.length === 0 && hasGracePassed && match.waveSpawnedCount > 0 && allSpawned) {
                this.completeWave();
            } else if (currentEnemies.length === 0 && match.waveSpawnedCount === 0 && hasGracePassed) {
                // Fallback diagnóstico: si tras la gracia sigue en 0 spawneados, loguear y no cerrar inmediatamente (esperar siguiente tick)
                Logger.warn('ALTAR', `Oleada ${match.currentWaveIndex+1} sin enemigos spawneados aún (expected ${match.waveExpectedCount}, spawned ${match.waveSpawnedCount}) - esperando...`);
            }
        } 
        else if (match.status === 'waiting_next_wave') {
            // Mandar notificaciones de cuenta regresiva
            const timeLeftSec = Math.max(0, Math.ceil((match.statusEndTime - now) / 1000));
            if (timeLeftSec > 0 && timeLeftSec % 5 === 0) {
                this.io.to(`zone_${match.zoneId}`).emit('gameNotification', {
                    msg: `Puertas de escape activas. Próxima oleada en ${timeLeftSec} segundos...`,
                    type: 'info'
                });
            }

            if (now >= match.statusEndTime) {
                // Iniciar la siguiente oleada
                this.startWave(match.currentWaveIndex + 1);
            }
        }
    }

    startWave(waveIdx) {
        const match = this.activeMatch;
        if (!match || waveIdx >= match.waves.length) return;

        match.currentWaveIndex = waveIdx;
        match.status = 'wave_active';
        match.statusEndTime = 0;
        match.waveStartTime = Date.now();
        match.waveSpawnedCount = 0;
        match.waveExpectedCount = 0;

        // 1. Cerrar los portales de escape inmediatamente
        this.emitPortals([]);
        this.io.to(`zone_${match.zoneId}`).emit('gameNotification', {
            msg: `🚨 ¡ALERTA! Puertas bloqueadas. Comienza la OLEADA ${waveIdx + 1} 🚨`,
            type: 'warning'
        });

        // 2. Spawnear los enemigos de esta oleada
        const waveData = match.waves[waveIdx];
        if (waveData) {
            Logger.info('ALTAR', `Spawneando Oleada ${waveIdx + 1}: ${waveData.name || 'Horda'}`);
            
            const adConfig = this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.gameModes && this.state.SERVER_CONFIG.gameModes.altar_defense;
            // v770.12: Spawners exclusivos Editor 3D (Puerta3) -> match.altarSpawners, fallback a adConfig para migración
            let enemySpawners = null;
            if (match.altarSpawners && match.altarSpawners.length > 0) {
                enemySpawners = match.altarSpawners;
            } else if (adConfig && adConfig.spawners && adConfig.spawners.length > 0) {
                enemySpawners = adConfig.spawners;
            }
            
            let phasesToRun = [];
            if (Array.isArray(waveData.phases) && waveData.phases.length > 0) {
                phasesToRun = waveData.phases;
            } else {
                // Retrocompatibilidad con formato plano o legacy array de enemigos
                let legacyEnemies = [];
                if (Array.isArray(waveData.enemies)) {
                    legacyEnemies = waveData.enemies;
                } else if (waveData.enemyId !== undefined) {
                    legacyEnemies = [{
                        type: waveData.enemyId,
                        count: waveData.count || 10,
                        spawnerIndex: waveData.spawnerIndex !== undefined ? waveData.spawnerIndex : 'random',
                        spawnType: waveData.spawnType || 'together',
                        staggerDelayMs: waveData.staggerDelayMs || 500
                    }];
                }
                
                // Mapear legacyEnemies a fases virtuales con startDelayMs: 0
                phasesToRun = legacyEnemies.map((le, lIdx) => ({
                    name: `Fase Legacy ${lIdx+1}`,
                    enemyId: le.type,
                    count: le.count,
                    spawnerIndex: le.spawnerIndex,
                    spawnType: le.spawnType,
                    staggerDelayMs: le.staggerDelayMs,
                    startDelayMs: 0,
                    focusTarget: waveData.focusTarget || le.focusTarget || 'altar'
                }));
            }

            // Calcular de forma síncrona el total de enemigos esperados en la oleada
            let expectedTotal = 0;
            phasesToRun.forEach(phase => {
                const count = parseInt(phase.count) || 0;
                if (phase.spawnerDistribution && typeof phase.spawnerDistribution === 'object') {
                    Object.values(phase.spawnerDistribution).forEach(c => {
                        expectedTotal += (parseInt(c) || 0);
                    });
                } else {
                    expectedTotal += count;
                }
            });
            match.waveExpectedCount = Math.max(expectedTotal, 1);

            phasesToRun.forEach(phase => {
                const startDelay = phase.startDelayMs !== undefined ? parseInt(phase.startDelayMs) : 0;
                
                setTimeout(() => {
                    // Si el estado de la partida cambió o se canceló, salir
                    if (!this.activeMatch || this.activeMatch.currentWaveIndex !== waveIdx || this.activeMatch.status !== 'wave_active') return;

                    // v770.6: Preservar sufijo de variante (5-B, 6-C, 10-A etc) - no usar parseInt
                    const type = (phase.enemyId !== undefined && phase.enemyId !== null && String(phase.enemyId).trim() !== "") ? String(phase.enemyId).trim() : String(phase.type || "1").trim();
                    const count = parseInt(phase.count);
                    const spawnerIdx = phase.spawnerIndex;
                    const spawnType = phase.spawnType || 'together';
                    const staggerDelayMs = phase.staggerDelayMs || 500;

                    const spawnOne = (forcedSpawnerIdx) => {
                        if (!this.activeMatch || this.activeMatch.currentWaveIndex !== waveIdx || this.activeMatch.status !== 'wave_active') return;

                        let x = match.altarPos.x;
                        let y = match.altarPos.y;
                        
                        let targetSpawner = null;
                        if (enemySpawners) {
                            const activeSpawnerIdx = forcedSpawnerIdx !== undefined ? forcedSpawnerIdx : spawnerIdx;
                            if (activeSpawnerIdx !== undefined && activeSpawnerIdx !== 'random') {
                                const idxInt = parseInt(activeSpawnerIdx);
                                if (idxInt >= 0 && idxInt < enemySpawners.length) {
                                    targetSpawner = enemySpawners[idxInt];
                                }
                            }
                            // Fallback a random si es 'random' o si el índice es inválido
                            if (!targetSpawner) {
                                targetSpawner = enemySpawners[Math.floor(Math.random() * enemySpawners.length)];
                            }
                        }

                        if (targetSpawner) {
                            const radius = targetSpawner.radius || 200;
                            const valid = spawnValidator.findValidSpawnPosition(targetSpawner.x, targetSpawner.y, radius, match.zoneId, this.state, { maxAttempts: 30 });
                            if (valid) { x = valid.x; y = valid.y; }
                            else {
                                const angle = Math.random() * Math.PI * 2;
                                const r = Math.random() * radius;
                                x = targetSpawner.x + Math.cos(angle) * r;
                                y = targetSpawner.y + Math.sin(angle) * r;
                            }
                        } else {
                            // Fallback: Spawnear alrededor del altar
                            const valid = spawnValidator.findValidSpawnPosition(match.altarPos.x, match.altarPos.y, 1600, match.zoneId, this.state, { maxAttempts: 25 });
                            // Hacemos un muestreo en anillo 1600-2100 evitando obstáculos
                            let found = null;
                            for (let k = 0; k < 30; k++) {
                                const angle = Math.random() * Math.PI * 2;
                                const dist = Math.random() * 500 + 1600;
                                const tx = match.altarPos.x + Math.cos(angle) * dist;
                                const ty = match.altarPos.y + Math.sin(angle) * dist;
                                if (!spawnValidator.isPointBlocked(tx, ty, match.zoneId, this.state)) { found = { x: tx, y: ty }; break; }
                            }
                            if (found) { x = found.x; y = found.y; }
                            else if (valid) {
                                // valid está dentro de 0-1600, buscar anillo externo: si no hay hueco en 1600-2100, usar valid desplazado
                                const angle = Math.random() * Math.PI * 2;
                                const dist = Math.random() * 500 + 1600;
                                x = match.altarPos.x + Math.cos(angle) * dist;
                                y = match.altarPos.y + Math.sin(angle) * dist;
                            } else {
                                const angle = Math.random() * Math.PI * 2;
                                const dist = Math.random() * 500 + 900;
                                x = match.altarPos.x + Math.cos(angle) * dist;
                                y = match.altarPos.y + Math.sin(angle) * dist;
                            }
                        }
                        // Seguridad final: si aun así cayó en pared, recolocar con validador
                        if (spawnValidator.isPointBlocked(x, y, match.zoneId, this.state)) {
                            const fb = spawnValidator.findValidSpawnPosition(x, y, 300, match.zoneId, this.state, { maxAttempts: 20 });
                            if (fb) { x = fb.x; y = fb.y; }
                        }
                        
                        const enemy = this.aiManager.serverSpawnEnemy(match.zoneId, type, x, y, null, true);
                        if (enemy) {
                            // Inyectar focusTarget a nivel de enemigo desde la fase (con fallback a la oleada o 'altar')
                            enemy.focusTarget = phase.focusTarget || waveData.focusTarget || 'altar';
                            Logger.info('ALTAR', `  -> Enemigo ${enemy.id} tipo ${type} spawneado en [${Math.round(x)},${Math.round(y)}] zona ${match.zoneId} focus ${enemy.focusTarget}`);
                            return enemy;
                        } else {
                            Logger.warn('ALTAR', `  -> FALLÓ spawn tipo ${type} en [${Math.round(x)},${Math.round(y)}] zona ${match.zoneId}`);
                            return null;
                        }
                    };

                    // Calcular la cola de spawners de forma detallada
                    let spawnQueue = [];
                    if (phase.spawnerDistribution && typeof phase.spawnerDistribution === 'object') {
                        Object.keys(phase.spawnerDistribution).forEach(key => {
                            const spCount = parseInt(phase.spawnerDistribution[key]) || 0;
                            const targetSp = key === 'random' ? 'random' : parseInt(key);
                            for (let i = 0; i < spCount; i++) {
                                spawnQueue.push(targetSp);
                            }
                        });
                    } 
                    
                    // Fallback si la cola quedó vacía por configuraciones viejas
                    if (spawnQueue.length === 0) {
                        if (spawnerIdx !== undefined && spawnerIdx !== 'random') {
                            const specificCount = Math.min(count, phase.spawnerSpecificCount !== undefined ? parseInt(phase.spawnerSpecificCount) : count);
                            const restCount = Math.max(0, count - specificCount);
                            
                            for (let i = 0; i < specificCount; i++) {
                                spawnQueue.push(spawnerIdx);
                            }
                            for (let i = 0; i < restCount; i++) {
                                spawnQueue.push('random');
                            }
                        } else {
                            for (let i = 0; i < count; i++) {
                                spawnQueue.push('random');
                            }
                        }
                    }

                    Logger.info('ALTAR', `Fase "${phase.name||'?'}" programada: ${spawnQueue.length} enemigos (total oleada ${match.waveExpectedCount}) startDelay ${startDelay}ms type ${spawnType}`);

                    if (spawnType === 'staggered' && staggerDelayMs > 0) {
                        spawnQueue.forEach((spId, i) => {
                            setTimeout(() => {
                                const en = spawnOne(spId);
                                if (en) match.waveSpawnedCount++;
                                else Logger.warn('ALTAR', `Spawn falló fase "${phase.name}" idx ${spId} en zona ${match.zoneId}`);
                            }, i * staggerDelayMs);
                        });
                    } else {
                        spawnQueue.forEach(spId => {
                            const en = spawnOne(spId);
                            if (en) match.waveSpawnedCount++;
                            else Logger.warn('ALTAR', `Spawn falló fase "${phase.name}" idx ${spId} en zona ${match.zoneId}`);
                        });
                    }
                }, startDelay);
            });
        }
    }

    completeWave() {
        const match = this.activeMatch;
        if (!match) return;

        Logger.info('ALTAR', `Oleada ${match.currentWaveIndex + 1} completada.`);

        // 1. Abrir las puertas de escape
        this.emitPortals(match.exitPortals);

        // 2. Verificar si era la última oleada
        if (match.currentWaveIndex >= match.waves.length - 1) {
            // ¡Victoria Total!
            match.status = 'finished';
            this.io.to(`zone_${match.zoneId}`).emit('gameNotification', {
                msg: "🏆 ¡TODAS LAS OLEADAS COMPLETADAS! EL ALTAR HA SIDO PROTEGIDO. 🏆",
                type: 'success'
            });
            
            // Devolver a todos al lobby tras 5 segundos
            setTimeout(() => this.endMatch(true), 5000);
        } else {
            // Esperar el intervalo para la siguiente oleada
            match.status = 'waiting_next_wave';
            match.statusEndTime = Date.now() + match.waveInterval;

            this.io.to(`zone_${match.zoneId}`).emit('gameNotification', {
                msg: `🟢 ¡Oleada ${match.currentWaveIndex + 1} completada! Las puertas al Lobby están ABIERTAS por ${Math.ceil(match.waveInterval/1000)}s 🟢`,
                type: 'success'
            });
        }
    }

    endMatch(success = false) {
        if (!this.activeMatch) return;
        const match = this.activeMatch;
        match.status = 'finished';

        // Warpear de vuelta a todos los jugadores en la zona al Lobby (Zona 1)
        const targetZoneId = 1;
        const zonePlayers = Object.values(this.state.players).filter(pl => Number(pl.zone) === Number(match.zoneId));
        
        zonePlayers.forEach(async pl => {
            const plSocket = [...this.io.sockets.sockets.values()].find(s => s.id === pl.socketId);
            if (plSocket) {
                plSocket.leave(`zone_${pl.zone}`);
                plSocket.join(`zone_${targetZoneId}`);

                // Update playersByZone index
                if (this.state.playersByZone[pl.zone] && this.state.playersByZone[pl.zone][pl.socketId]) {
                    delete this.state.playersByZone[pl.zone][pl.socketId];
                }
                if (!this.state.playersByZone[targetZoneId]) {
                    this.state.playersByZone[targetZoneId] = {};
                }
                this.state.playersByZone[targetZoneId][pl.socketId] = pl;

                pl.zone = targetZoneId;
                pl.x = 2000;
                pl.y = 2000;
                plSocket.emit('changeZoneDone', { zoneId: targetZoneId, x: 2000, y: 2000 });
                plSocket.to(`zone_${targetZoneId}`).emit('newPlayer', {
                    id: plSocket.id,
                    user: pl.user,
                    x: pl.x,
                    y: pl.y,
                    hp: pl.hp,
                    maxHp: pl.maxHp,
                    sh: pl.sh || pl.shield,
                    maxSh: pl.maxSh || pl.maxShield,
                    zone: pl.zone,
                    spheres: pl.spheres || [],
                    clanTag: pl.clanTag || ""
                });
            }
        });

        // Limpiar la zona
        this.purgeEnemiesInZone(match.zoneId);
        this.state.altarState = null;
        this.activeMatch = null;

        Logger.info('ALTAR', `Partida finalizada en zona ${match.zoneId}. Victoria: ${success}.`);
    }

    purgeEnemiesInZone(zoneId) {
        let count = 0;
        Object.keys(this.state.enemies).forEach(enemyId => {
            if (Number(this.state.enemies[enemyId].zone) === Number(zoneId)) {
                this.io.to(`zone_${zoneId}`).emit('enemyDeath', { id: enemyId });
                delete this.state.enemies[enemyId];
                count++;
            }
        });
        if (count > 0) Logger.info('ALTAR', `Limpieza de zona: ${count} enemigos purgados.`);
    }

    emitAltarState() {
        if (!this.activeMatch || !this.state.altarState) return;
        const altar = this.state.altarState;
        this.io.to(`zone_${this.activeMatch.zoneId}`).emit('altarStateUpdate', {
            hp: Math.max(0, Math.ceil(altar.hp)),
            maxHp: altar.maxHp,
            shield: Math.max(0, Math.ceil(altar.shield)),
            maxShield: altar.maxShield
        });
    }

    emitPortals(portals) {
        if (!this.activeMatch) return;
        this.io.to(`zone_${this.activeMatch.zoneId}`).emit('updateExitPortals', portals);
    }

    applyDamageToAltar(damage, zoneId = null) {
        let dmg = parseFloat(damage) || 0;
        if (dmg <= 0) return;

        const altar = this.state.altarState;
        if (!altar) return;

        const targetZone = zoneId !== null ? zoneId : (this.activeMatch ? this.activeMatch.zoneId : altar.zone);

        if (altar.shield >= dmg) {
            altar.shield -= dmg;
        } else {
            altar.hp -= (dmg - altar.shield);
            altar.shield = 0;
        }

        if (altar.hp <= 0) {
            altar.hp = 0;
            if (this.io) {
                this.io.to(`zone_${targetZone}`).emit('gameNotification', { 
                    msg: "🚨 ¡EL ALTAR HA SIDO DESTRUIDO! MISIÓN FALLIDA. 🚨", 
                    type: 'error' 
                });
            }
            setTimeout(() => {
                this.endMatch(false);
            }, 3000);
        }

        if (this.io) {
            this.io.to(`zone_${targetZone}`).emit('altarStateUpdate', {
                hp: Math.max(0, Math.ceil(altar.hp)),
                maxHp: altar.maxHp,
                shield: Math.max(0, Math.ceil(altar.shield)),
                maxShield: altar.maxShield
            });
        }
    }
}

module.exports = new AltarDefenseManager();
