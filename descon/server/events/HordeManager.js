class HordeManager {
    constructor(io, serverSpawnEnemy, enemies) {
        this.io = io;
        this.serverSpawnEnemy = serverSpawnEnemy;
        this.enemies = enemies;
        this.config = {
            active: false,
            map: 6,
            currentWaveIndex: 0,
            timeBetweenWaves: 10,
            waves: []
        };
        this.isWaitingNextWave = false;
        this.init();
    }

    init() {
        // Loop de chequeo de estado de la horda
        setInterval(() => this.update(), 2000);
    }

    updateConfig(newConfig) {
        if (!newConfig) return;
        this.config = { ...this.config, ...newConfig };
        console.log("[HORDE] Configuración actualizada desde el Admin Panel.");
    }

    update() {
        if (!this.config.active) return;

        // Contar enemigos vivos en el mapa del evento
        const currentEnemiesInZone = Object.values(this.enemies).filter(e => e.zone === this.config.map && e.hp > 0);
        
        // Si no quedan enemigos y no estamos esperando la siguiente wave, la disparamos
        if (currentEnemiesInZone.length === 0 && !this.isWaitingNextWave) {
            this.startNextWave();
        }
    }

    startNextWave() {
        if (!this.config.waves || this.config.waves.length === 0) {
            console.log("[HORDE] Error: No hay oleadas configuradas.");
            this.config.active = false;
            return;
        }

        // Si ya pasamos la última oleada, victoria
        if (this.config.currentWaveIndex >= this.config.waves.length) {
            this.io.to(`zone_${this.config.map}`).emit('gameNotification', { 
                msg: "¡TODAS LAS OLEADAS COMPLETADAS! EL SECTOR ESTÁ SEGURO.", 
                type: 'success' 
            });
            this.config.active = false;
            this.isWaitingNextWave = false;
            return;
        }

        this.isWaitingNextWave = true;
        const waveData = this.config.waves[this.config.currentWaveIndex];
        
        console.log(`[HORDE] Preparando Oleada: ${waveData.name} (${this.config.currentWaveIndex + 1}/${this.config.waves.length})`);
        
        this.io.to(`zone_${this.config.map}`).emit('gameNotification', { 
            msg: `¡${waveData.name.toUpperCase()} COMPLETADA! Próxima en ${this.config.timeBetweenWaves} segundos...`, 
            type: 'info' 
        });

        setTimeout(() => {
            if (!this.config.active) {
                this.isWaitingNextWave = false;
                return;
            }
            this.spawnWave();
            this.isWaitingNextWave = false;
            this.config.currentWaveIndex++; // Avanzar al siguiente para la próxima vez
        }, this.config.timeBetweenWaves * 1000);
    }

    spawnWave() {
        const waveData = this.config.waves[this.config.currentWaveIndex];
        if (!waveData) return;

        console.log(`[HORDE] Spawneando Oleada: ${waveData.name}`);
        
        waveData.enemies.forEach(enCfg => {
            const type = parseInt(enCfg.type);
            const count = parseInt(enCfg.count);
            
            for (let i = 0; i < count; i++) {
                const x = Math.random() * 3400 + 300;
                const y = Math.random() * 3400 + 300;
                this.serverSpawnEnemy(this.config.map, type, x, y, null, true);
            }
        });
        
        this.io.to(`zone_${this.config.map}`).emit('gameNotification', { 
            msg: `¡ALERTA! ${waveData.name.toUpperCase()} INICIADA`, 
            type: 'warning' 
        });
    }

    stopEvent() {
        this.config.active = false;
        this.config.currentWaveIndex = 0;
        this.isWaitingNextWave = false;
        
        // Limpieza forzada de la zona
        let count = 0;
        for (const id in this.enemies) {
            if (this.enemies[id].zone === this.config.map) {
                this.io.to(`zone_${this.config.map}`).emit('enemyDeath', { id: id });
                delete this.enemies[id];
                count++;
            }
        }
        console.log(`[HORDE] Evento finalizado. ${count} entidades purgadas del sector ${this.config.map}.`);
    }
}

module.exports = HordeManager;
