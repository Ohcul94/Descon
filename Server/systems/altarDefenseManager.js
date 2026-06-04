const Logger = require('../utils/logger');

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
        if (!adConfig) return;

        // Purgar cualquier enemigo previo que estuviese en esta zona por residuo
        this.purgeEnemiesInZone(zoneId);

        // Inicializar el Altar State
        this.state.altarState = {
            hp: Number(adConfig.altarHp) || 10000,
            maxHp: Number(adConfig.altarHp) || 10000,
            shield: Number(adConfig.altarShield) || 5000,
            maxShield: Number(adConfig.altarShield) || 5000,
            zone: zoneId
        };

        const waveInterval = Number(adConfig.waveInterval) || 15000;
        const spawnLockTime = Number(adConfig.spawnLockTime) || 5000;

        this.activeMatch = {
            zoneId: zoneId,
            members: membersList,
            currentWaveIndex: 0,
            waves: adConfig.waves || [],
            waveInterval: waveInterval,
            spawnLockTime: spawnLockTime,
            
            status: 'spawn_lock', // 'spawn_lock', 'wave_active', 'waiting_next_wave', 'finished'
            statusEndTime: Date.now() + spawnLockTime,
            exitPortals: adConfig.exitPortals || [],
            altarPos: adConfig.altarPos || { x: 5000, y: 5000 }
        };

        Logger.info('ALTAR', `Partida de Defensa al Altar iniciada en zona ${zoneId}. Esperando fin de barrera de seguridad (${spawnLockTime}ms).`);
        
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
                this.startWave(0);
            }
        } 
        else if (match.status === 'wave_active') {
            // Verificar si todos los enemigos de la oleada fueron eliminados
            if (currentEnemies.length === 0) {
                this.completeWave();
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
            const enemySpawners = (adConfig && adConfig.spawners && adConfig.spawners.length > 0)
                ? adConfig.spawners
                : null;
            
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

            phasesToRun.forEach(phase => {
                const startDelay = phase.startDelayMs !== undefined ? parseInt(phase.startDelayMs) : 0;
                
                setTimeout(() => {
                    // Si el estado de la partida cambió o se canceló, salir
                    if (!this.activeMatch || this.activeMatch.currentWaveIndex !== waveIdx || this.activeMatch.status !== 'wave_active') return;

                    const type = parseInt(phase.enemyId || phase.type);
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
                            const angle = Math.random() * Math.PI * 2;
                            const r = Math.random() * radius;
                            x = targetSpawner.x + Math.cos(angle) * r;
                            y = targetSpawner.y + Math.sin(angle) * r;
                        } else {
                            // Fallback: Spawnear alrededor del altar
                            const angle = Math.random() * Math.PI * 2;
                            const dist = Math.random() * 500 + 900;
                            x = match.altarPos.x + Math.cos(angle) * dist;
                            y = match.altarPos.y + Math.sin(angle) * dist;
                        }
                        
                        const enemy = this.aiManager.serverSpawnEnemy(match.zoneId, type, x, y, null, true);
                        if (enemy) {
                            // Inyectar focusTarget a nivel de enemigo desde la fase (con fallback a la oleada o 'altar')
                            enemy.focusTarget = phase.focusTarget || waveData.focusTarget || 'altar';
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

                    if (spawnType === 'staggered' && staggerDelayMs > 0) {
                        spawnQueue.forEach((spId, i) => {
                            setTimeout(() => {
                                spawnOne(spId);
                            }, i * staggerDelayMs);
                        });
                    } else {
                        spawnQueue.forEach(spId => {
                            spawnOne(spId);
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
}

module.exports = new AltarDefenseManager();
