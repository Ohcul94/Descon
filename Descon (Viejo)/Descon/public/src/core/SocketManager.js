export default class SocketManager {
    constructor(scene) {
        this.scene = scene;
        this.socket = window.socket || io();
        this.setupListeners();
    }

    setupListeners() {
        this.socket.on('currentPlayers', (players) => {
            Object.keys(players).forEach(id => {
                if (id === this.socket.id) {
                    // El jugador local se maneja en la escena
                } else {
                    this.scene.events.emit('spawnRemotePlayer', players[id]);
                }
            });
        });

        this.socket.on('newPlayer', info => {
            this.scene.events.emit('spawnRemotePlayer', info);
        });

        this.socket.on('playerMoved', data => {
            this.scene.events.emit('remotePlayerMoved', data);
        });

        this.socket.on('enemyDamaged', data => {
            this.scene.events.emit('enemyDamaged', data);
        });

        this.socket.on('playerFired', data => {
            this.scene.events.emit('remotePlayerFired', data);
        });

        this.socket.on('playerDisconnected', id => {
            this.scene.events.emit('removeRemotePlayer', id);
        });

        this.socket.on('currentEnemies', (enemies) => {
            Object.keys(enemies).forEach(id => {
                this.scene.events.emit('enemySpawn', enemies[id]);
            });
        });

        this.socket.on('enemySpawn', (enemy) => {
            this.scene.events.emit('enemySpawn', enemy);
        });

        // Redundantes v104.10 eliminados

        this.socket.on('enemyDamaged', (data) => {
            this.scene.events.emit('enemyDamaged', data);
        });

        this.socket.on('enemyDead', (data) => {
            this.scene.events.emit('serverEnemyDead', data);
        });
        
        this.socket.on('enemiesMoved', (data) => this.scene.events.emit('enemiesMoved', data));
        
        // v104.00: Cañería de Habilidades del Ancient Boss
        this.socket.on('bossEffect', (data) => this.scene.events.emit('bossEffect', data));

        this.socket.on('playerStatSync', (data) => this.scene.events.emit('playerStatSync', data));
        
        this.socket.on('serverEnemyFire', (data) => {
            this.scene.events.emit('serverEnemyFire', data);
        });

        // Eventos de Grupo v65.0
        this.socket.on('partyInvitation', (data) => {
            this.scene.events.emit('partyInvitation', data);
        });

        this.socket.on('partyUpdate', (party) => {
            this.scene.events.emit('partyUpdate', party);
        });

        this.socket.on('adminConfigUpdated', config => {
            this.scene.events.emit('configUpdated', config);
        });

        this.socket.on('adminConfigLoaded', config => {
            this.scene.events.emit('configUpdated', config);
        });

        // Ping/Pong para MS v66.6 (Precisión Milimétrica)
        this.socket.on('pong_custom', () => {
            const latency = Math.round(performance.now() - this.pingStartPerf);
            const msVal = document.getElementById('ms-val');
            if (msVal) msVal.innerText = latency > 0 ? latency : 1;
            
            // Reportar al servidor para que otros lo vean (v69.1)
            if (this.scene.player) {
                this.scene.player.latency = latency;
                this.scene.player.drawBars();
                this.socket.emit('latencyUpdate', latency);
            }
        });

        setInterval(() => {
            this.pingStartPerf = performance.now();
            this.socket.emit('ping_custom');
        }, 2000);
    }

    emitMovement(data) {
        this.socket.emit('playerMovement', data);
    }

    emitFire(data) {
        this.socket.emit('playerFire', data);
    }

    emitEnemyHit(enemyId, damage, bulletId = null) {
        this.socket.emit('enemyHit', { enemyId, damage, bulletId });
    }

    emitSave(data) {
        this.socket.emit('saveProgress', data);
    }
}
