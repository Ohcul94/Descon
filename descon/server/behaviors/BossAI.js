// BossAI.js (Cerebro del Titán v87.10)
const BaseAI = require('./BaseAI');

module.exports = class BossAI extends BaseAI {
    constructor(enemy, config) {
        super(enemy, config);
        this.currentPhase = 1; // 1: Laser, 2: Ram/Teleport, 3: Missiles
        this.phaseTimer = 0;
        this.nextPhaseTime = Date.now() + 5000;
        this.isRamming = false;
        this.isWaiting = false;
        this.combatStartTime = 0; 
        this.isRage = false;
        this.noAggroStartTime = 0;
        
        this.nextLaserTime = 0;
        this.nextMissileTime = 0;
        this.nextRamTime = 0;
    }

    update(players, now, io) {
        let target = this.getNearestPlayer(players);
        if (!target) {
            if (this.noAggroStartTime === 0) this.noAggroStartTime = now;
            
            // v239.02: Reset de 10 segundos solicitado
            if (now - this.noAggroStartTime > 10000) {
                if (this.enemy.hp < this.enemy.maxHp || this.enemy.shield < this.enemy.maxShield) {
                    console.log(`[BOSS-AI] Reset TOTAL (Phase/HP/Clones) para ${this.enemy.name}`);
                    
                    // 1. Reset Stats
                    this.enemy.hp = this.enemy.maxHp;
                    this.enemy.shield = this.enemy.maxShield;
                    
                    // 2. Reset AI State (Volver a Phase 1)
                    this.isRage = false;
                    this.enemy.isRage = false;
                    this.combatStartTime = 0;
                    this.currentPhase = 1;
                    this.isRamming = false;
                    this.isWaiting = false;
                    this.nextPhaseTime = now + 5000;
                    this.nextLaserTime = 0;
                    this.nextMissileTime = 0;
                    this.nextRamTime = 0;
                    
                    // 3. Limpieza de Clones y Proyectiles
                    if (global.serverDespawnClones) global.serverDespawnClones(this.enemy.zone);
                    if (global.serverClearProjectiles) global.serverClearProjectiles(this.enemy.zone, this.enemy.id);
                }
                this.noAggroStartTime = 0;
            }
            return;
        }
        
        this.noAggroStartTime = 0;
        if (this.combatStartTime === 0) this.combatStartTime = now;

        const angle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);
        this.enemy.rotation = angle + Math.PI / 2; // MIRAR SIEMPRE AL TARGET (v238.95)

        const rTime = this.config.rageTimer;
        const rageLimit = (rTime > 0) ? (rTime * 1000) : Infinity; 
        if (!this.isRage && (now - this.combatStartTime > rageLimit)) {
            this.isRage = true;
            this.enemy.isRage = true;
        }

        const dist = Math.hypot(target.x - this.enemy.x, target.y - this.enemy.y);

        if (this.isRage) {
            this.phaseLasers(target, dist, angle, now, io);
            this.phaseRamTeleport(target, dist, angle, now, io);
            this.phaseHomingMissiles(players, dist, angle, now, io);
            return;
        }

        if (now > this.nextPhaseTime) {
            this.changePhase(now, io);
        }

        if (this.isWaiting) return;

        switch (this.currentPhase) {
            case 1: this.phaseLasers(target, dist, angle, now, io); break;
            case 2: this.phaseRamTeleport(target, dist, angle, now, io); break;
            case 3: this.phaseHomingMissiles(players, dist, angle, now, io); break;
        }

        if (now - (this.enemy.lastHit || 0) > 4000) {
            this.enemy.shield = Math.min(this.enemy.maxShield, this.enemy.shield + (this.enemy.maxShield * 0.02));
        }
    }

    changePhase(now, io) {
        if (!this.isWaiting && !this.isRage) {
            this.isWaiting = true;
            this.nextPhaseTime = now + 2000;
        } else {
            this.isWaiting = false;
            this.currentPhase = (this.currentPhase % 3) + 1;
            this.isRamming = false;
            
            const durations = this.isRage ? { 1: 3000, 2: 2000, 3: 1000 } : { 1: 5000, 2: 3000, 3: 4000 };
            this.nextPhaseTime = now + durations[this.currentPhase];
            
            io.to(`zone_${this.enemy.zone}`).emit('bossPhase', { id: this.enemy.id, phase: this.currentPhase });
        }
    }

    phaseLasers(target, dist, angle, now, io) {
        if (now > (this.nextLaserTime || 0)) {
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                enemyId: this.enemy.id, targetId: target.id,
                x: this.enemy.x, y: this.enemy.y, angle: angle,
                damage: this.isRage ? (this.config.bulletDamage * 1.5) : this.config.bulletDamage
            });
            this.nextLaserTime = now + (this.isRage ? 200 : 600);
        }
        if (!this.isRage) {
            const orbit = angle + Math.PI / 2;
            this.enemy.x += Math.cos(orbit) * 2;
            this.enemy.y += Math.sin(orbit) * 2;
        }
    }

    phaseRamTeleport(target, dist, angle, now, io) {
        if (!this.isRamming && now > (this.nextRamTime || 0)) {
            this.isRamming = true;
            this.ramStartTime = now;
        }

        const ramDuration = this.isRage ? 600 : 1000;
        if (this.isRamming) {
            if (now < this.ramStartTime + ramDuration) {
                this.enemy.x += Math.cos(angle) * (this.isRage ? 20 : 15);
                this.enemy.y += Math.sin(angle) * (this.isRage ? 20 : 15);
            } else {
                const sideAngle = Math.random() * Math.PI * 2;
                this.enemy.x = target.x + Math.cos(sideAngle) * (this.isRage ? 300 : 400);
                this.enemy.y = target.y + Math.sin(sideAngle) * (this.isRage ? 300 : 400);
                this.isRamming = false;
                this.nextRamTime = now + (this.isRage ? 1000 : 3000); 
                if (!this.isRage) this.nextPhaseTime = now; 
            }
        }
    }

    phaseHomingMissiles(players, dist, angle, now, io) {
        if (now > (this.nextMissileTime || 0)) {
            const nearbyPlayers = Object.values(players || {}).filter(p => p.zone === this.enemy.zone);
            nearbyPlayers.forEach(p => {
                const pAngle = Math.atan2(p.y - this.enemy.y, p.x - this.enemy.x);
                io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                    enemyId: this.enemy.id, targetId: p.id,
                    x: this.enemy.x, y: this.enemy.y, angle: pAngle,
                    type: 'missile', isHoming: true, life: 240, 
                    damage: this.isRage ? (this.config.bulletDamage * 2.5) : (this.config.bulletDamage * 1.5)
                });
            });
            this.nextMissileTime = now + (this.isRage ? 1500 : 4000); 
        }
    }
};
