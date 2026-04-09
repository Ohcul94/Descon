// AncientBossAI.js (Cerebro Táctico de Élite v115.20)
const BaseAI = require('./BaseAI');

module.exports = class AncientBossAI extends BaseAI {
    constructor(enemy, config) {
        super(enemy, config);
        this.timers = { nova: 0, rifts: 0, leech: 0, mines: 0, pulses: 0, shield: 0, clones: 0 };
        this.activeRifts = [];
        this.abilityIndex = 0;
        this.nextAbilityTime = 0;
        this.combatStartTime = 0;
    }

    update(players, now, io) {
        let target = this.getNearestPlayer(players);
        if (!target) {
            this.combatStartTime = 0; this.activeRifts = [];
            return;
        }

        if (this.combatStartTime === 0) this.combatStartTime = now;
        if (!this.isRyze && (now - this.combatStartTime > 30000)) this.isRyze = true;

        this.handleAreaDamage(players, now, io);
        this.handleMovement(target);

        if (this.isRyze) this.runRageMode(players, target, now, io);
        else this.runRotation(players, target, now, io);
    }

    handleMovement(target) {
        const angle = Math.atan2(target.y - this.enemy.y, target.x - this.enemy.x);
        const dist = Math.hypot(this.enemy.x - target.x, this.enemy.y - target.y);
        this.enemy.rotation = angle + Math.PI / 2;
        if (dist > 600) {
            this.enemy.x += Math.cos(angle) * 4.5;
            this.enemy.y += Math.sin(angle) * 4.5;
        } else {
            const orbit = angle + Math.PI / 2;
            this.enemy.x += Math.cos(orbit) * 2.5;
            this.enemy.y += Math.sin(orbit) * 2.5;
        }
    }

    handleAreaDamage(players, now, io) {
        const nearby = Object.values(players).filter(p => p.zone === this.enemy.zone);
        
        // 1. Vórtices: DAÑO PRECIOSO v115.20 (Rando 90px para visual de 80px)
        this.activeRifts = this.activeRifts.filter(r => r.expiry > now);
        this.activeRifts.forEach(r => {
            nearby.forEach(p => {
                const dist = Math.hypot(p.x - r.x, p.y - r.y);
                if (dist < 400) { 
                    const force = (400 - dist) / 150; // Succión suave
                    const angle = Math.atan2(r.y - p.y, r.x - p.x);
                    p.x += Math.cos(angle) * force;
                    p.y += Math.sin(angle) * force;
                    
                    // DAÑO MILIMÉTRICO (Solo si está en el círculo violeta de 80-90px)
                    if (dist < 90) this.applyDamage(p, 450, now, io);
                    
                    io.to(p.socketId).emit('playerStatSync', { x: p.x, y: p.y, hp: p.hp, shield: p.shield, lastHit: now });
                }
            });
        });
    }

    applyDamage(player, amount, now, io) {
        if (player.isDead) return;
        player.shield -= amount;
        if (player.shield < 0) { player.hp += player.shield; player.shield = 0; }
        
        // v115.20: ENTRAR EN COMBATE (Bloqueo de recarga)
        player.lastHit = now;

        if (player.hp <= 0) {
            player.hp = 0; player.isDead = true;
            if (io) io.to(player.socketId).emit('playerStatSync', { hp: 0, shield: 0, isDead: true, lastHit: now });
            return;
        }

        if (io) io.to(player.socketId).emit('playerStatSync', { hp: player.hp, shield: player.shield, lastHit: now });
    }

    runRotation(players, target, now, io) {
        if (now < this.nextAbilityTime) return;
        const ab = ['useNova', 'useRifts', 'useLeech', 'useMines', 'usePulses', 'useShield', 'useClones'];
        this[ab[this.abilityIndex % ab.length]](players, target, now, io);
        this.abilityIndex++;
        this.nextAbilityTime = now + 2500;
    }

    runRageMode(players, target, now, io) {
        if (now > this.timers.nova) { this.useNova(players, target, now, io); this.timers.nova = now + 6000; }
        if (now > this.timers.rifts) { this.useRifts(players, target, now, io); this.timers.rifts = now + 6000; }
        if (now > this.timers.mines) { this.useMines(players, target, now, io); this.timers.mines = now + 6000; }
        if (now > this.timers.pulses) { this.usePulses(players, target, now, io); this.timers.pulses = now + 800; }
    }

    useNova(players, target, now, io) {
        io.to(`zone_${this.enemy.zone}`).emit('bossEffect', { type: 'vacuum', x: this.enemy.x, y: this.enemy.y, radius: 1200 });
        setTimeout(() => {
            Object.values(players).forEach(p => {
                if (p.zone === this.enemy.zone && Math.hypot(p.x-this.enemy.x, p.y-this.enemy.y) < 1200) {
                    this.applyDamage(p, 5500, now, io);
                }
            });
        }, 800); // Sincronizado con visual v114.10
    }

    useRifts(players, target, now, io) {
        const rx = target.x + (Math.random()-0.5)*350; 
        const ry = target.y + (Math.random()-0.5)*350;
        this.activeRifts.push({ x: rx, y: ry, expiry: now + 8000 });
        io.to(`zone_${this.enemy.zone}`).emit('bossEffect', { type: 'rift', x: rx, y: ry, duration: 8000 });
    }

    useLeech(players, target, now, io) {
        this.applyDamage(target, 12000, now, io);
        this.enemy.hp = Math.min(this.enemy.maxHp, this.enemy.hp + 12000);
        io.to(`zone_${this.enemy.zone}`).emit('bossEffect', { type: 'leech', from: this.enemy.id, to: target.id });
    }

    useMines(players, target, now, io) {
        for(let i=0; i<10; i++) {
            const angle = Math.random()*Math.PI*2;
            io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
                enemyId: this.enemy.id, targetId: target.id, x: this.enemy.x, y: this.enemy.y,
                angle, type: 'mine', speed: 8, life: 600, damage: 5000, isHoming: true
            });
        }
    }

    usePulses(players, target, now, io) {
        io.to(`zone_${this.enemy.zone}`).emit('serverEnemyFire', {
            enemyId: this.enemy.id, targetId: target.id, x: this.enemy.x, y: this.enemy.y,
            angle: Math.atan2(target.y-this.enemy.y, target.x-this.enemy.x), type: 'laser', isHoming: true, damage: 3500
        });
    }

    useShield(players, target, now, io) { this.isCountering = true; setTimeout(()=>this.isCountering=false, 4000); }
    useClones(players, target, now, io) { 
        if (global.serverSpawnEnemy) {
            global.serverSpawnEnemy(this.enemy.zone, 6, this.enemy.x+400, this.enemy.y+400); 
        }
    }
};
