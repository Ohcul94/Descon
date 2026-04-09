// CombatSystem.js (Architecture v123.51 Precise Modular Engine)
export default class CombatSystem {
    constructor(scene) {
        this.scene = scene;
    }

    get bullets() {
        return this.scene.bullets || [];
    }

    update(delta) {
        const bullets = this.bullets;
        for (let i = bullets.length - 1; i >= 0; i--) {
            const b = bullets[i];
            
            // v119.10: NullGuard Crítico
            if (!b || b.destroyed || !b.parent) { 
                bullets.splice(i, 1); 
                continue; 
            }
            
            // v116.20: Motor Homing Modularizado
            if (b.isHoming && b.targetId) {
                // v123.51: Búsqueda de Target por ID Inmutable (DNI Galáctico)
                let target = null;
                if (b.targetId === this.scene.player.id) {
                    target = this.scene.player;
                } else {
                    // Buscar en remotos (recorriendo el Map por ID de Player v123.51)
                    for (const [sid, p] of this.scene.entities.remotePlayers) {
                        if (p.id === b.targetId) { target = p; break; }
                    }
                }

                if (target && target.container && !target.container.destroyed && !target.isDead) {
                    const tx = target.container.x;
                    const ty = target.container.y;
                    const angleToTarget = Math.atan2(ty - b.y, tx - b.x);
                    const currentAngle = Math.atan2(b.vy, b.vx);
                    const diff = Math.atan2(Math.sin(angleToTarget - currentAngle), Math.cos(angleToTarget - currentAngle));
                    const newAngle = currentAngle + diff * 0.1;
                    const speed = Math.hypot(b.vx, b.vy) || 12;
                    b.vx = Math.cos(newAngle) * speed;
                    b.vy = Math.sin(newAngle) * speed;
                    b.rotation = newAngle + Math.PI / 2;
                }
            }

            b.x += b.vx * delta;
            b.y += b.vy * delta;
            b.life -= delta;

            // IMPACTO CON ENEMIGOS
            if (b.owner === 'player' || b.owner === 'remote-player') {
                this.scene.entities.enemies.forEach(enemy => {
                    if (!enemy || !enemy.container || enemy.isDead || enemy.container.destroyed) return;
                    const dist = Math.hypot(b.x - enemy.container.x, b.y - enemy.container.y);
                    if (dist < 50) {
                        if (b.owner === 'player') {
                            enemy.takeDamage(b.damage);
                            this.scene.showDamageText(enemy.container.x, enemy.container.y, b.damage, false);
                            if (this.scene.socketManager) this.scene.socketManager.emitEnemyHit(enemy.id, b.damage, b.id);
                        }
                        b.life = 0;
                    }
                });
            }

            // IMPACTO CON JUGADORES (Balas de Enemigos) v123.51 (Autoridad de DNI Inmutable)
            if (b.owner === 'server' || b.owner === 'enemy') {
                // 1. Detección Local (Solo yo reporto MI daño)
                const player = this.scene.player;
                if (player && !player.isDead) {
                    // v126.20: Si la bala tiene target, solo el target chequea daño real
                    if (!b.targetId || b.targetId === player.id) {
                        const distP = Math.hypot(b.x - player.container.x, b.y - player.container.y);
                        if (distP < 50) { // Radio de 50 para seguridad táctica v126.20
                            player.takeDamage(b.damage);
                            this.scene.showDamageText(player.container.x, player.container.y, b.damage, true);
                            if (this.scene.socketManager) this.scene.socketManager.socket.emit('playerHitByEnemy', { damage: b.damage });
                            b.life = 0;
                        }
                    }
                }

                // 2. Detección de Aliados (Solo Visual Predictive / Sin reportar)
                if (b.life > 0) {
                    for (const [id, p] of this.scene.entities.remotePlayers) {
                        if (!p || p.isDead || !p.container || !p.container.visible) continue;
                        
                        // v128.10: Radio de 60 para compensar latencia de posición remota
                        const distR = Math.hypot(b.x - p.container.x, b.y - p.container.y);
                        if (distR < 60) { 
                            this.scene.showDamageText(p.container.x, p.container.y, b.damage, true);
                            b.life = 0;
                            b.destroy(); // Destrucción Inmediata v128.10
                            bullets.splice(i, 1);
                            break; 
                        }
                    }
                }
            }

            if (b.life <= 0) {
                b.destroy();
                bullets.splice(i, 1);
            }
        }
    }
}
