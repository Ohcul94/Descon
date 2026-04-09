// BossAI.js (Cerebro del Titán v87.10)
const BaseAI = require('./BaseAI');

module.exports = class BossAI extends BaseAI {
    constructor(enemy, config) {
        super(enemy, config);
        this.currentPhase = 1; // 1: Laser, 2: Ram/Teleport, 3: Missiles
        this.phaseTimer = 0;
        this.nextPhaseTime = Date.now() + 5000; // La primera fase dura 5 seg
        this.isRamming = false;
        this.isWaiting = false;
        this.combatStartTime = 0; // Inicio de cronómetro para Modo Ryze
        this.isRyze = false;
        this.noAggroStartTime = 0; // Timer para reset de HP/SH v93.00
        
        // Cooldowns independientes para Multitasking (v94.00)
        this.nextLaserTime = 0;
        this.nextMissileTime = 0;
        this.nextRamTime = 0;
    }

    update(players, now, io) {
        let target = this.getNearestPlayer(players);
        if (!target) {
            this.combatStartTime = 0; // Fuera de combate, reset Rage v91.20
            this.isRyze = false;
            this.enemy.isRyze = false;

            // Lógica de Reset de Vida tras 5s (v93.00)
            if (this.noAggroStartTime === 0) this.noAggroStartTime = now;
            if (now - this.noAggroStartTime > 5000) {
                if (this.enemy.hp < this.enemy.maxHp || this.enemy.shield < this.enemy.maxShield) {
                    this.enemy.hp = this.enemy.maxHp;
                    this.enemy.shield = this.enemy.maxShield;
                }
                this.noAggroStartTime = 0;
            }
            return;
        }

        // Si hay target, resetear el timer de "no agro"
        this.noAggroStartTime = 0;

        // Iniciar cronómetro de combate
        if (this.combatStartTime === 0) this.combatStartTime = now;

        // ACTIVAR MODO RYZE (v91.20: Tras 20 segundos)
        if (!this.isRyze && (now - this.combatStartTime > 20000)) {
            this.isRyze = true;
            this.enemy.isRyze = true; // Sincronía con el servidor para emitir
        }

        const dist = Math.hypot(target.x - this.enemy.x, target.y - this.enemy.y);
        const angle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);

        if (this.isRyze) {
            // --- CAOS TOTAL: TODAS LAS MECÁNICAS AL MISMO TIEMPO (v94.00) ---
            this.phaseLasers(target, dist, angle, now, io);
            this.phaseRamTeleport(target, dist, angle, now, io);
            this.phaseHomingMissiles(players, dist, angle, now, io);
            return;
        }

        if (now > this.nextPhaseTime) {
            this.changePhase(now, io);
        }

        if (this.isWaiting) return; // Pausa de 2 segundos entre fases

        // Ejecutar Lógica de Fase
        switch (this.currentPhase) {
            case 1: this.phaseLasers(target, dist, angle, now, io); break;
            case 2: this.phaseRamTeleport(target, dist, angle, now, io); break;
            case 3: this.phaseHomingMissiles(players, dist, angle, now, io); break;
        }

        // Regeneración Pro del Boss (v87.10)
        if (now - (this.enemy.lastHit || 0) > 4000) {
            this.enemy.shield = Math.min(this.enemy.maxShield, this.enemy.shield + (this.enemy.maxShield * 0.02));
        }
    }

    changePhase(now, io) {
        if (!this.isWaiting && !this.isRyze) {
            // Entrar en pausa de 2 segundos (Solo si NO es Modo Ryze)
            this.isWaiting = true;
            this.nextPhaseTime = now + 2000;
        } else {
            // Cambiar a la fase real
            this.isWaiting = false;
            this.currentPhase = (this.currentPhase % 3) + 1;
            this.isRamming = false; // Reset de estados
            
            // Definir duración de la nueva fase (En Ryze son más cortas pero seguidas)
            const durations = this.isRyze ? { 1: 3000, 2: 2000, 3: 1000 } : { 1: 5000, 2: 3000, 3: 4000 };
            this.nextPhaseTime = now + durations[this.currentPhase];
            
            // Notificar Phase Change (Opcional visual)
            io.to(`zone_${this.enemy.zone}`).emit('bossPhase', { id: this.enemy.id, phase: this.currentPhase });
        }
    }

    // --- FASE 1: Ráfaga Triple ---
    phaseLasers(target, dist, angle, now, io) {
        if (now > (this.nextLaserTime || 0)) {
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                enemyId: this.enemy.id, targetId: target.id,
                x: this.enemy.x, y: this.enemy.y, angle: angle,
                damage: this.isRyze ? 1000 : 500 // Daño de BOSS
            });
            this.nextLaserTime = now + (this.isRyze ? 200 : 600); // Fuego ametralladora en RAGE
        }
        if (!this.isRyze) {
            this.enemy.rotation = angle + Math.PI / 2;
            const orbit = angle + Math.PI / 2;
            this.enemy.x += Math.cos(orbit) * 2;
            this.enemy.y += Math.sin(orbit) * 2;
        }
    }

    // --- FASE 2: Embestida y Teletransportación ---
    phaseRamTeleport(target, dist, angle, now, io) {
        if (!this.isRamming && now > (this.nextRamTime || 0)) {
            this.isRamming = true;
            this.ramStartTime = now;
        }

        const ramDuration = this.isRyze ? 600 : 1000;
        if (this.isRamming) {
            if (now < this.ramStartTime + ramDuration) {
                // Embestida: Velocidad Extrema (v87.10)
                this.enemy.x += Math.cos(angle) * (this.isRyze ? 20 : 15);
                this.enemy.y += Math.sin(angle) * (this.isRyze ? 20 : 15);
                this.enemy.rotation = angle + Math.PI / 2;
            } else {
                // Teleportación Final (v87.10)
                const sideAngle = Math.random() * Math.PI * 2;
                this.enemy.x = target.x + Math.cos(sideAngle) * (this.isRyze ? 300 : 400);
                this.enemy.y = target.y + Math.sin(sideAngle) * (this.isRyze ? 300 : 400);
                this.isRamming = false;
                this.nextRamTime = now + (this.isRyze ? 1000 : 3000); 
                if (!this.isRyze) this.nextPhaseTime = now; 
            }
        }
    }

    // --- FASE 3: Misiles Teledirigidos (v90.20 Multijugador) ---
    phaseHomingMissiles(players, dist, angle, now, io) {
        if (now > (this.nextMissileTime || 0)) {
            // Buscar TODOS los jugadores en la zona (v90.20)
            const nearbyPlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone);
            
            nearbyPlayers.forEach(p => {
                const pAngle = Math.atan2(p.y - this.enemy.y, p.x - this.enemy.x);
                    io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                        enemyId: this.enemy.id, targetId: p.id,
                        x: this.enemy.x, y: this.enemy.y, angle: pAngle,
                        type: 'missile', isHoming: true, life: 240, // 4 seg
                        damage: this.isRyze ? 2400 : 1200 // DOBLE DAÑO EN MODO RYZE v91.20
                    });
            });

            this.nextMissileTime = now + (this.isRyze ? 1500 : 4000); 
        }
        if (!this.isRyze) this.enemy.rotation = angle + Math.PI / 2;
    }
};
