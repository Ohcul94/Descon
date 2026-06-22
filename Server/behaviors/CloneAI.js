// CloneAI.js (Cerebro de Clon / Duplicado v1.0)
const BaseAI = require('./BaseAI');

module.exports = class CloneAI extends BaseAI {
    constructor(enemy, config, state) {
        super(enemy, config, state);
        this.parentEnemyId = config.parentEnemyId;
        this.cloneExplosionDamage = config.cloneExplosionDamage !== undefined ? config.cloneExplosionDamage : 500;
        this.cloneHealAmount = config.cloneHealAmount !== undefined ? config.cloneHealAmount : 1000;
        this.cloneDuration = config.cloneDuration !== undefined ? config.cloneDuration : 8000;
        this.cloneExplodeOnExpiry = config.cloneExplodeOnExpiry !== false;
        
        this.spawnTime = Date.now();
        this.endTime = this.spawnTime + this.cloneDuration;
        this.exploded = false;
        
        // Forzar agresividad para que persiga activamente
        this.enemy.isAggressive = true;
    }

    getSpeed() {
        const baseSpeed = (this.config.cloneSpeed || 200) * 0.033;
        const slowMult = this.enemy.slowMultiplier || 1.0;
        return baseSpeed * slowMult;
    }

    applyMovementLogic(target, dist, angle, now) {
        // Si ya expiró el tiempo, o si estamos muy cerca del jugador objetivo, detonar
        if (now >= this.endTime || dist < 60) {
            this.detonate(now);
            return;
        }

        const speed = this.getSpeed();
        // Moverse directamente hacia el jugador sin frenado para explotar en su cara
        this.enemy.x += Math.cos(angle) * speed;
        this.enemy.y += Math.sin(angle) * speed;
        this.enemy.rotation = angle + Math.PI / 2;
        this.enemy.isMoving = true;
    }

    update(grid, players, now, io) {
        // Si el tiempo expiró y no hay jugadores cerca, detonamos igual al expirar
        if (now >= this.endTime && !this.exploded) {
            this.detonate(now);
            return;
        }
        
        super.update(grid, players, now, io);
        
        // Si por alguna razón no se actualizó el movimiento (por falta de target) pero el tiempo expiró
        if (now >= this.endTime && !this.exploded) {
            this.detonate(now);
        }
    }

    detonate(now) {
        if (this.exploded) return;
        this.exploded = true;

        const io = this.state.io || global.io;
        if (!io) return;

        const zone = this.enemy.zone;
        const explosionRadius = 150;
        const damage = this.cloneExplosionDamage;

        // VFX de explosión en el cliente
        io.to(`zone_${zone}`).emit('serverEnemyAction', {
            id: this.enemy.id,
            action: "bomb_explode",
            x: this.enemy.x,
            y: this.enemy.y,
            radius: explosionRadius,
            damage: damage,
            mId: `clone_explode_${this.enemy.id}`
        });

        // Aplicar daño a los jugadores dentro del radio de explosión
        if (this.cloneExplodeOnExpiry) {
            const zonePlayers = Object.values(this.state.players || {}).filter(p => p.zone === zone && !p.isDead && !p.isInvisible);
            zonePlayers.forEach(p => {
                const d = Math.hypot(p.x - this.enemy.x, p.y - this.enemy.y);
                if (d <= explosionRadius) {
                    p.lastCombatTime = Date.now();
                    if (p.shield >= damage) {
                        p.shield -= damage;
                    } else {
                        p.hp -= (damage - p.shield);
                        p.shield = 0;
                    }
                    if (p.hp < 0) p.hp = 0;
                    if (p.hp <= 0) p.isDead = true;

                    io.to(p.socketId).emit('environmentDamage', { damage: damage });
                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: p.socketId,
                        hp: Math.ceil(p.hp),
                        shield: Math.ceil(p.shield),
                        isDead: p.isDead
                    });
                }
            });
        }

        // Absorción: Curar al enemigo original
        const parent = this.state.enemies[this.parentEnemyId];
        if (parent && parent.hp > 0 && this.cloneHealAmount > 0) {
            const oldHp = parent.hp;
            parent.hp = Math.min(parent.maxHp, parent.hp + this.cloneHealAmount);
            
            // Sincronizar curación
            io.to(`zone_${zone}`).emit('enemyHealed', { 
                id: parent.id, 
                hp: parent.hp, 
                amount: Math.max(0, parent.hp - oldHp) 
            });

            // Efecto visual de absorción (leech)
            io.to(`zone_${zone}`).emit('bossEffect', { 
                type: 'leech', 
                from: this.enemy.id, 
                to: parent.id,
                x: this.enemy.x,
                y: this.enemy.y
            });
        }

        // Eliminar clon de la existencia
        io.to(`zone_${zone}`).emit('enemyDead', { id: this.enemy.id });
        delete this.state.enemies[this.enemy.id];
    }
};
