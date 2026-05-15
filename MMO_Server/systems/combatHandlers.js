const User = require('../models/User');
const { handleEnemyDeath } = require('./enemyLogic');
const SkillManager = require('./skills/SkillManager');
const StealthSkill = require('./skills/StealthSkill');
const BlinkSkill = require('./skills/BlinkSkill');
const FrostTrailSkill = require('./skills/FrostTrailSkill');
const SmokeBombSkill = require('./skills/SmokeBombSkill');
const InvulnerabilitySkill = require('./skills/InvulnerabilitySkill');
const HealSkill = require('./skills/HealSkill');
const DamageSkill = require('./skills/DamageSkill');
const BuffSkill = require('./skills/BuffSkill');

// v247.20: Registro de Habilidades Modulares
SkillManager.registerSkill(new StealthSkill());
SkillManager.registerSkill(new BlinkSkill());
SkillManager.registerSkill(new FrostTrailSkill());
SkillManager.registerSkill(new SmokeBombSkill());
SkillManager.registerSkill(new InvulnerabilitySkill());

// Habilidades de Curación/Soporte
SkillManager.registerSkill(new HealSkill("ESCUDO CELULAR"));
SkillManager.registerSkill(new HealSkill("FORTALEZA-X"));
SkillManager.registerSkill(new HealSkill("AUTO-REPARACIÓN"));
SkillManager.registerSkill(new HealSkill("NANO-REGENERACIÓN"));

// Habilidades Ofensivas
SkillManager.registerSkill(new DamageSkill("PLASMA BLAST"));

// Habilidades de Estado/Buffs
SkillManager.registerSkill(new BuffSkill("REFLECT-Ω"));
SkillManager.registerSkill(new BuffSkill("TURBO-IMPULSO"));
SkillManager.registerSkill(new BuffSkill("HYPER-DASH"));

/**
 * registerCombatHandlers
 * Maneja toda la lógica de combate: disparos, habilidades y daño.
 */
function registerCombatHandlers(socket, io, state) {
    
    // SISTEMA DE DAÑO AUTORITATIVO (Anti-Cheat Server-Side)
    socket.on('playerFire', (fireData) => {
        const p = state.players[socket.id];
        if (!p || !state.SERVER_CONFIG) return;

        if (p.isSilenced) return;

        // v262.55: Mapeo corregido según Player.gd
        // Cliente envía "type" para el nombre (laser/missile) y "ammoType" para el nivel (0,1,2)
        const ammoType = fireData.type || 'laser';
        const ammoTier = (fireData.ammoType !== undefined) ? fireData.ammoType : 0;
        const typeKey = (ammoType === 'laser') ? 'laser' : (ammoType === 'missile' ? 'missile' : 'mine');

        if (!p.ammo || !p.ammo[typeKey] || (p.ammo[typeKey][ammoTier] || 0) <= 0) {
            return; 
        }

        p.ammo[typeKey][ammoTier]--;

        let baseDamage = 100;
        if (p.equipped && p.equipped.w) {
            baseDamage = 0;
            p.equipped.w.forEach(item => {
                const masterItem = state.SERVER_CONFIG.shopItems.weapons.find(w => w.id === item.id);
                if (masterItem) baseDamage += (masterItem.base || 0);
            });
        }

        const mults = state.SERVER_CONFIG.ammoMultipliers[ammoType] || [1];
        const multiplier = mults[ammoTier] || 1;
        const finalAuthorizedDamage = baseDamage * multiplier;

        const pData = {
            id: socket.id,
            bulletId: fireData.bulletId,
            damage: finalAuthorizedDamage,
            x: fireData.x,
            y: fireData.y,
            angle: fireData.angle,
            rotation: fireData.rotation,
            type: ammoType,
            ammoType: ammoTier,
            targetId: fireData.targetId
        };

        socket.to(`zone_${p.zone}`).emit('playerFire', pData);
    });

    // SISTEMA DE HABILIDADES DE ESFERAS (Soporte Polimórfico v262.10)
    socket.on('playerSphereSkill', async (data) => {
        const p = state.players[socket.id];
        if (!p || p.isDead || !state.SERVER_CONFIG) return;

        const sphereIdx = (data.id !== undefined) ? data.id : data.sphereIdx;
        if (sphereIdx === undefined || sphereIdx < 0 || sphereIdx > 3) return;

        const now = Date.now();
        if (!p.sphereCooldowns) p.sphereCooldowns = [0, 0, 0, 0];
        const lastUse = p.sphereCooldowns[sphereIdx] || 0;
        
        const cd_sec = (state.SERVER_CONFIG.skillsData && state.SERVER_CONFIG.skillsData[data.skillName]) ? state.SERVER_CONFIG.skillsData[data.skillName].cd : 10;
        if (now - lastUse < (cd_sec * 1000)) return;

        // Actualizar cooldown antes de ejecutar para evitar spam
        p.sphereCooldowns[sphereIdx] = now;

        // v247.20: Sistema Modular de Habilidades (Prioridad)
        const handled = SkillManager.useSkill(data.skillName, p, data, { io, state, socket });
        if (!handled) {
            console.warn(`[SKILL] Habilidad no reconocida o no migrada: ${data.skillName}`);
        }
    });

    // IMPACTO EN ENEMIGO
    socket.on('enemyHit', async (data) => {
        const { enemyId, bulletId, damage } = data;
        const enemy = state.enemies[enemyId];
        const p = state.players[socket.id];
        if (!enemy || !p || !state.SERVER_CONFIG || p.isDead) return;

        const dist = Math.hypot(p.x - enemy.x, p.y - enemy.y);
        if (dist > 1800) return;
        if (enemy.ai && enemy.ai.isInvulnerable) return;

        let finalDamage = parseFloat(damage) || 100;
        let maxAllowed = 5000; 
        if (p.equipped && p.equipped.w) {
            let weaponsBase = 0;
            p.equipped.w.forEach(it => {
                const master = state.SERVER_CONFIG.shopItems.weapons.find(w => w.id === it.id);
                if (master) weaponsBase += (master.base || 0);
                else weaponsBase += 500;
            });
            if (weaponsBase > 0) maxAllowed = weaponsBase * 40; 
        }
        
        if (finalDamage > maxAllowed) finalDamage = maxAllowed;

        if (enemy.shield >= finalDamage) enemy.shield -= finalDamage;
        else { enemy.hp -= (finalDamage - enemy.shield); enemy.shield = 0; }
        
        enemy.lastHit = Date.now();
        enemy.lastHitter = socket.id;
        p.lastCombatTime = Date.now();

        io.to(`zone_${enemy.zone}`).emit('enemyDamaged', { id: enemyId, hp: Math.max(0, enemy.hp), shield: enemy.shield, bulletId });

        if (enemy.hp <= 0 && !enemy.isDeadProcessed) {
            handleEnemyDeath(enemyId, io, state, socket.id);
        }
    });

    // DAÑO POR ENEMIGO
    socket.on('playerHitByEnemy', (data) => {
        const p = state.players[socket.id];
        if (p && !p.isDead && state.SERVER_CONFIG) {
            const attackerType = data.attackerType || 'enemy';
            if (attackerType === 'remote' || attackerType === 'player') return;
            
            const enemyType = data.enemyType || 1;
            let dmg = data.damage || 0;

            if (attackerType === 'enemy') {
                const cfg = state.SERVER_CONFIG.enemyModels[enemyType];
                const baseDmg = cfg ? cfg.bulletDamage : 50;
                
                // v266.550: Registrar éxito del enemigo para reglas de persecución
                const attackerId = data.attackerId || data.enemyId || data.senderId;
                if (attackerId && state.enemies[attackerId]) {
                    state.enemies[attackerId].lastSuccessHit = Date.now();
                }

                // v266.999: Blindaje de Daño Ambiental (Permitir daño x2, x3 si el mapa es extremo)
                const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
                const mapCfg = maps[p.zone] || maps[p.zone.toString()];
                const extremeAggro = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'extreme_aggression') : null;
                const damageMult = extremeAggro ? (parseFloat(extremeAggro.damageMult) || 1) : 1;
                
                const authorizedMaxDmg = baseDmg * damageMult;

                // Si el cliente manda daño 0 o sospechosamente alto (más que el autorizado por el mapa), normalizamos
                if (dmg <= 0 || dmg > (authorizedMaxDmg + 5)) dmg = authorizedMaxDmg;

                // v266.250: Verificación de Tipo de Bala (Solo aplica slow si la bala coincide)
                if (cfg) {
                    let sAmount = 0;
                    let sDuration = 0;
                    let stunDuration = 0;

                    // Buscar la mecánica específica que corresponde a la bala que impactó
                    if (cfg.mechanics) {
                        const matchingMech = cfg.mechanics.find(m => m.type === data.bulletType);
                        if (matchingMech) {
                            sAmount = matchingMech.slowAmount || 0;
                            sDuration = matchingMech.slowDuration || 0;
                            stunDuration = matchingMech.stunDuration || 0;
                        }
                    }

                    // Fallback a la raíz si no hay mecánicas modulares (retrocompatibilidad)
                    if (sAmount === 0 && cfg.slowAmount > 0) {
                        sAmount = cfg.slowAmount;
                        sDuration = cfg.slowDuration || 3000;
                    }

                    if (sAmount > 0) {
                        p.isSlowed = true;
                        p.slowPoints = sAmount;
                        p.lastSlowTime = Date.now();
                        p.slowEndTime = Date.now() + sDuration;
                        
                        io.to(p.socketId).emit('slowState', { active: true, amount: sAmount });
                    }
                }

                // v268.900: Lógica de Gancho (Hook)
                if (data.bulletType === "hook") {
                    const attackerId = data.attackerId || data.enemyId || data.senderId;
                    const attacker = state.enemies[attackerId];
                    if (attacker) {
                        const mech = cfg.mechanics ? cfg.mechanics.find(m => m.type === "hook") : null;
                        const pullSpeed = (mech?.pullSpeed || 1500);
                        
                        // v266.695: Inmovilidad TOTAL durante el lanzamiento
                        attacker.isHooking = true;
                        
                        // Calcular tiempo de viaje estimado (en ms)
                        const dist = Math.sqrt(Math.pow(attacker.x - p.x, 2) + Math.pow(attacker.y - p.y, 2));
                        const pullDurationMs = Math.min(1000, Math.max(100, (dist / pullSpeed) * 1000));
                        
                        // Emitir el tirón inmediatamente para el cliente
                        io.to(`zone_${p.zone}`).emit('hookPulled', { 
                            victimId: p.socketId, 
                            attackerId: attacker.id,
                            pullSpeed: pullSpeed
                        });

                        // Programar el fin del tirón y el inicio del Stun
                        setTimeout(() => {
                            // 1. ATRAER FÍSICAMENTE en el servidor (al final del pull)
                            const angleToAttacker = Math.atan2(attacker.y - p.y, attacker.x - p.x);
                            p.x = attacker.x - Math.cos(angleToAttacker) * 100;
                            p.y = attacker.y - Math.sin(angleToAttacker) * 100;
                            
                            // 2. STUN: Paralizar al jugador DESPUÉS de llegar al bicho
                            const stunDur = data.stunDuration || 2000;
                            p.isStunned = true;
                            p.stunEndTime = Date.now() + stunDur;
                            
                            // v269.65: Espera configurable antes de recuperar el movimiento
                            const postWait = mech?.postHookWaitMs || 500;
                            setTimeout(() => {
                                attacker.isHooking = false; // Recién ahora el bicho puede moverse
                            }, postWait);
                            
                            io.to(p.socketId).emit('stunState', { active: true, duration: stunDur });
                        }, pullDurationMs);
                    }
                }
            }
            if (p.isInvulnerable) dmg = 0;

            if (p.shield >= dmg) p.shield -= dmg;
            else { p.hp -= (dmg - p.shield); p.shield = 0; }
            if (p.hp <= 0) { p.hp = 0; p.isDead = true; }
            p.lastCombatTime = Date.now();
            p.regenDelay = (attackerType === 'remote') ? 15000 : 5000;
            
            io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                id: socket.id, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield), 
                maxHp: p.maxHp, maxShield: p.maxShield, isDead: p.isDead,
                isInvulnerable: p.isInvulnerable, isInvisible: p.isInvisible, // v245.93: Blindaje de Sigilo en PvE
                spheres: p.spheres || [] 
            });
        }
    });

    // PVP: DAÑO ENTRE JUGADORES
    socket.on('playerHitByPlayer', (data) => {
        const victim = state.players[data.victimId];
        const attacker = state.players[socket.id];
        
        if (victim && attacker && !victim.isDead && !attacker.isDead) {
            if (victim.pvpEnabled && attacker.pvpEnabled) {
                if (victim.isInvulnerable) return;
                const now = Date.now();
                let dmg = data.damage || 50;
                
                if (victim.shield >= dmg) victim.shield -= dmg;
                else { victim.hp -= (dmg - victim.shield); victim.shield = 0; }
                
                if (victim.hp <= 0) { victim.hp = 0; victim.isDead = true; }
                
                victim.lastCombatTime = now;
                attacker.lastCombatTime = now;
                victim.lastPvpCombatTime = now;
                attacker.lastPvpCombatTime = now;
                victim.regenDelay = 15000;
                
                io.to(`zone_${victim.zone}`).emit('playerStatSync', { 
                    id: data.victimId, hp: victim.hp, shield: victim.shield, 
                    maxHp: victim.maxHp, maxShield: victim.maxShield, isDead: victim.isDead,
                    isInvisible: victim.isInvisible, // v245.94: Blindaje de Sigilo en PvP
                    spheres: victim.spheres
                });
            } else {
                if (!attacker.pvpEnabled) {
                    socket.emit('gameNotification', { msg: "PVP BLOQUEADO: Tu modo combate est├í SEGURO", type: "warning" });
                } else if (!victim.pvpEnabled) {
                    socket.emit('gameNotification', { msg: "PVP BLOQUEADO: El objetivo est├í en modo SEGURO", type: "warning" });
                }
            }
        }
    });


}

module.exports = {
    registerCombatHandlers
};
