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
        this.attackCooldownMs = config.attackCooldownMs !== undefined ? config.attackCooldownMs : 2000;
        
        // Forzar agresividad para que persiga activamente
        this.enemy.isAggressive = true;
    }

    getSpeed() {
        const baseSpeed = (this.config.cloneSpeed || 200) * 0.033;
        const slowMult = this.enemy.slowMultiplier || 1.0;
        return baseSpeed * slowMult;
    }

    applyMovementLogic(target, dist, angle, now, io) {
        const parent = this.state.enemies[this.parentEnemyId];
        if (!parent || parent.hp <= 0) {
            this.detonate(now, io);
            return;
        }

        const speed = this.getSpeed();

        if (this.enemy.role === "heal") {
            // El clon curador corre hacia el enemigo padre
            const distToParent = Math.hypot(parent.x - this.enemy.x, parent.y - this.enemy.y);
            const angleToParent = Math.atan2(parent.y - this.enemy.y, parent.x - this.enemy.x);

            if (now >= this.endTime) {
                this.detonate(now, io);
                return;
            }

            if (distToParent >= 60) {
                this.enemy.isMoving = true;
                this.enemy.x += Math.cos(angleToParent) * speed;
                this.enemy.y += Math.sin(angleToParent) * speed;
                this.enemy.rotation = angleToParent + Math.PI / 2;
            } else {
                this.enemy.isMoving = false;
            }
        } else {
            // El clon de daño persigue al jugador
            if (now >= this.endTime) {
                this.detonate(now, io);
                return;
            }

            if (dist >= 60) {
                this.enemy.isMoving = true;
                this.enemy.x += Math.cos(angle) * speed;
                this.enemy.y += Math.sin(angle) * speed;
                this.enemy.rotation = angle + Math.PI / 2;
            } else {
                this.enemy.isMoving = false;
            }
        }
    }

    applyCombatLogic(target, dist, angle, now, io, grid, players) {
        if (!target || !this._inCombat) return;

        // Cooldown entre ataques visuales configurado individualmente
        if (now - (this.lastVisualAttackTime || 0) > this.attackCooldownMs) {
            this.lastVisualAttackTime = now;

            // Elegir una mecánica de ataque visual al azar de entre toda la biblioteca compatible con el cliente
            const visualMechanics = ["laser", "missile", "ice_missile", "mine", "circle_cast", "cone_cast", "mega_laser"];
            const chosen = visualMechanics[Math.floor(Math.random() * visualMechanics.length)];
            const zoneStr = `zone_${this.enemy.zone}`;

            if (chosen === "laser") {
                io.to(zoneStr).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y,
                    angle: angle, damage: 0
                });
            } else if (chosen === "missile" || chosen === "ice_missile") {
                io.to(zoneStr).emit('serverEnemyFire', {
                    enemyId: this.enemy.id, targetId: target.socketId || target.id,
                    enemyType: this.enemy.type,
                    x: this.enemy.x, y: this.enemy.y, angle: angle,
                    type: chosen === "missile" ? "missile" : "ice_missile", isHoming: true, life: 120,
                    damage: 0
                });
            } else if (chosen === "mine") {
                const offsetAngle = Math.random() * Math.PI * 2;
                const mDist = 50 + Math.random() * 100;
                const mx = target.x + Math.cos(offsetAngle) * mDist;
                const my = target.y + Math.sin(offsetAngle) * mDist;
                io.to(zoneStr).emit('serverEnemyFire', {
                    enemyId: this.enemy.id,
                    enemyType: this.enemy.type,
                    x: mx, y: my, angle: 0, type: 'mine', damage: 0,
                    bulletSpeed: 1200,
                    range: 1100,
                    deceleration: 2.0,
                    explosionRadius: 150,
                    lifetimeMs: 10000
                });
            } else if (chosen === "circle_cast") {
                io.to(zoneStr).emit('serverEnemyAction', {
                    id: this.enemy.id, action: "circle_charging", duration: 1000, range: 150
                });
                setTimeout(() => {
                    const activeClone = this.state.enemies[this.enemy.id];
                    if (activeClone && activeClone.hp > 0) {
                        io.to(zoneStr).emit('serverEnemyAction', {
                            id: this.enemy.id, action: "circle_fire", x: this.enemy.x, y: this.enemy.y, range: 150, damage: 0
                        });
                    }
                }, 1000);
            } else if (chosen === "cone_cast") {
                io.to(zoneStr).emit('serverEnemyAction', {
                    id: this.enemy.id, action: "cone_charging", duration: 1000, coneAngle: 60, range: 400, angle: angle
                });
                setTimeout(() => {
                    const activeClone = this.state.enemies[this.enemy.id];
                    if (activeClone && activeClone.hp > 0) {
                        io.to(zoneStr).emit('serverEnemyAction', {
                            id: this.enemy.id, action: "cone_fire", x: this.enemy.x, y: this.enemy.y, coneAngle: 60, range: 400, angle: angle, damage: 0
                        });
                    }
                }, 1000);
            } else if (chosen === "mega_laser") {
                io.to(zoneStr).emit('serverEnemyAction', {
                    id: this.enemy.id, action: "charging", duration: 1000, angle: angle, range: 1500
                });
                setTimeout(() => {
                    const activeClone = this.state.enemies[this.enemy.id];
                    if (activeClone && activeClone.hp > 0) {
                        io.to(zoneStr).emit('serverEnemyAction', {
                            id: this.enemy.id, action: "locked", duration: 500, angle: angle, range: 1500, damage: 0
                        });
                    }
                }, 1000);
            }
        }
    }

    update(grid, players, now, io) {
        // Verificar si el padre sigue existiendo y con vida
        const parent = this.state.enemies[this.parentEnemyId];
        if (!parent || parent.hp <= 0) {
            this.detonate(now, io);
            return;
        }

        // Sincronizar estado de combate con el del padre antes de super.update
        if (parent.ai) {
            this._inCombat = parent.ai._inCombat;
        } else {
            this._inCombat = false;
        }

        // Si el padre salió de combate, el clon se autodestruye inmediatamente
        if (!this._inCombat) {
            this.detonate(now, io);
            return;
        }

        // Si el tiempo expiró, detonar
        if (now >= this.endTime && !this.exploded) {
            this.detonate(now, io);
            return;
        }
        
        super.update(grid, players, now, io);
        
        if (now >= this.endTime && !this.exploded) {
            this.detonate(now, io);
        }
    }

    detonate(now, io) {
        if (this.exploded) return;
        this.exploded = true;

        if (!io) return;

        const zone = this.enemy.zone;
        const explosionRadius = 150;

        // 1. Si es clon de DAÑO: Explotar y hacer daño a los jugadores
        if (this.enemy.role === "damage") {
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
                        if (p.hp <= 0) this._killPlayer(p, io);

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
        }

        // 2. Si es clon de CURACIÓN: Curar al enemigo padre (el boss/real)
        if (this.enemy.role === "heal") {
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

                // Efecto visual de absorción (leech) de la curación al padre
                io.to(`zone_${zone}`).emit('bossEffect', { 
                    type: 'leech', 
                    from: this.enemy.id, 
                    to: parent.id,
                    x: this.enemy.x,
                    y: this.enemy.y
                });
            }
        }

        // Eliminar clon de la existencia
        io.to(`zone_${zone}`).emit('enemyDead', { id: this.enemy.id });
        delete this.state.enemies[this.enemy.id];
    }
};
