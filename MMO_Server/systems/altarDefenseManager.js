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
        if (waveData && Array.isArray(waveData.enemies)) {
            Logger.info('ALTAR', `Spawneando Oleada ${waveIdx + 1}: ${waveData.name || 'Horda'}`);
            
            waveData.enemies.forEach(enCfg => {
                const type = parseInt(enCfg.type);
                const count = parseInt(enCfg.count);
                
                for (let i = 0; i < count; i++) {
                    // Spawnear alrededor del altar (ej. en un radio de 900px a 1400px para que viajen)
                    const angle = Math.random() * Math.PI * 2;
                    const dist = Math.random() * 500 + 900;
                    const x = match.altarPos.x + Math.cos(angle) * dist;
                    const y = match.altarPos.y + Math.sin(angle) * dist;
                    this.aiManager.serverSpawnEnemy(match.zoneId, type, x, y, null, true);
                }
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
