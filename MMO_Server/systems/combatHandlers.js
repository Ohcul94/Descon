const User = require('../models/User');
const Logger = require('../utils/logger');
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
const AlphaRegenSkill = require('./skills/AlphaRegenSkill');
const VitalLinkSkill = require('./skills/VitalLinkSkill');
const WindBarrierSkill = require('./skills/WindBarrierSkill');
const HealBeaconSkill = require('./skills/HealBeaconSkill');
const ProvocacionSkill = require('./skills/ProvocacionSkill');


// v247.20: Registro de Habilidades Modulares
SkillManager.registerSkill(new StealthSkill());
SkillManager.registerSkill(new BlinkSkill());
SkillManager.registerSkill(new FrostTrailSkill());
SkillManager.registerSkill(new SmokeBombSkill());
SkillManager.registerSkill(new InvulnerabilitySkill());
SkillManager.registerSkill(new AlphaRegenSkill());
SkillManager.registerSkill(new VitalLinkSkill());
SkillManager.registerSkill(new WindBarrierSkill());
SkillManager.registerSkill(new HealBeaconSkill());
SkillManager.registerSkill(new ProvocacionSkill());


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

        // v270.0: Blindaje de Habilidad (Verificar que el jugador la posea equipada)
        let hasSkillEquipped = false;
        if (p.spheres && Array.isArray(p.spheres)) {
            hasSkillEquipped = p.spheres.some(s => s.equipped && (
                (s.equipped.skill_name && s.equipped.skill_name.toUpperCase() === data.skillName.toUpperCase()) ||
                (s.equipped.name && s.equipped.name.toUpperCase() === data.skillName.toUpperCase())
            ));
        }

        if (!hasSkillEquipped && !p.isAdmin) {
            Logger.warn('SECURITY', `Uso no autorizado de habilidad: [${p.user}] intentó usar "${data.skillName}" sin tenerla equipada.`);
            return;
        }

        const now = Date.now();
        if (!p.sphereCooldowns) p.sphereCooldowns = [0, 0, 0, 0];
        const lastUse = p.sphereCooldowns[sphereIdx] || 0;
        
        const cd_val = (state.SERVER_CONFIG.skillsData && state.SERVER_CONFIG.skillsData[data.skillName]) ? state.SERVER_CONFIG.skillsData[data.skillName].cd : 10000;
        const cd_ms = (cd_val < 100) ? (cd_val * 1000) : cd_val;
        if (now - lastUse < cd_ms) return;

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
        if (enemy.isInvulnerable || (enemy.ai && enemy.ai._isDefenseSkillActive)) return;

        let weaponsBase = 0;
        if (p.equipped && p.equipped.w) {
            p.equipped.w.forEach(it => {
                const master = state.SERVER_CONFIG.shopItems.weapons.find(w => w.id === it.id);
                if (master) weaponsBase += (master.base || 0);
            });
        }
        if (weaponsBase === 0) weaponsBase = 100; // Fallback

        // Encontrar el multiplicador máximo absoluto disponible en toda la munición que el jugador posee
        let maxAmmoMult = 1;
        if (p.ammo) {
            Object.keys(p.ammo).forEach(type => {
                const mults = state.SERVER_CONFIG.ammoMultipliers[type] || [1];
                p.ammo[type].forEach((qty, tier) => {
                    if (qty > 0 && mults[tier] > maxAmmoMult) {
                        maxAmmoMult = mults[tier];
                    }
                });
            });
        }

        // Permitimos un 50% extra para críticos/buffs del cliente
        let maxAllowed = weaponsBase * maxAmmoMult * 1.5;
        if (maxAllowed < 1000) maxAllowed = 1000;
        
        let finalDamage = parseFloat(damage) || 100;
        if (finalDamage > maxAllowed && !p.isAdmin) {
            Logger.warn('SECURITY', `Daño PvE excedido de [${p.user}] a enemigo [${enemy.name}]: reportado ${finalDamage}, máx permitido ${Math.round(maxAllowed)} (base: ${weaponsBase}, mult: ${maxAmmoMult})`);
            finalDamage = maxAllowed;
        }

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

                // El daño recibido no puede ser inferior al daño real del enemigo (anti-GodMode/anti-mitigación hack)
                // a menos que sea 0 por invulnerabilidad
                if (p.isInvulnerable) {
                    dmg = 0;
                } else {
                    if (dmg < authorizedMaxDmg * 0.9 || dmg > (authorizedMaxDmg + 5)) {
                        dmg = authorizedMaxDmg;
                    }
                }

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

                        // v269.120: STUN UNIFICADO (Desde el impacto hasta el final de la penalización)
                        const stunDur = (data.stunDuration || 2000);
                        p.isStunned = true;
                        p.stunEndTime = Date.now() + pullDurationMs + stunDur;

                        // Emitir el tirón inmediatamente para el cliente
                        io.to(`zone_${p.zone}`).emit('hookPulled', { 
                            victimId: p.socketId, 
                            attackerId: attacker.id,
                            pullSpeed: pullSpeed
                        });

                        io.to(p.socketId).emit('stunState', { active: true, duration: pullDurationMs + stunDur });

                        // Programar el fin del tirón (Atracción física)
                        setTimeout(() => {
                            // 1. ATRAER FÍSICAMENTE en el servidor
                            const angleToAttacker = Math.atan2(attacker.y - p.y, attacker.x - p.x);
                            p.x = attacker.x - Math.cos(angleToAttacker) * 100;
                            p.y = attacker.y - Math.sin(angleToAttacker) * 100;
                            
                            // v269.65: Espera configurable del bicho
                            const postWait = mech?.postHookWaitMs || 500;
                            
                            if (attacker._hookSafetyTimeout) {
                                clearTimeout(attacker._hookSafetyTimeout);
                                attacker._hookSafetyTimeout = null;
                            }

                            setTimeout(() => {
                                attacker.isHooking = false;
                            }, postWait);
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

                // v270.0: Validación de Distancia en PvP
                const dist = Math.hypot(attacker.x - victim.x, attacker.y - victim.y);
                if (dist > 1800) {
                    Logger.warn('SECURITY', `Intento de PvP a distancia inválida: [${attacker.user}] -> [${victim.user}] (Distancia: ${Math.round(dist)}px)`);
                    return;
                }

                const now = Date.now();
                
                // Calcular daño teórico máximo para el atacante
                let baseDmg = 100;
                if (attacker.equipped && attacker.equipped.w) {
                    baseDmg = 0;
                    attacker.equipped.w.forEach(item => {
                        const masterItem = state.SERVER_CONFIG.shopItems.weapons.find(w => w.id === item.id);
                        if (masterItem) baseDmg += (masterItem.base || 0);
                    });
                    if (baseDmg === 0) baseDmg = 100;
                }

                // Determinar multiplicador de munición seleccionada por el atacante
                const attackerAmmoType = attacker.selectedAmmo || 'laser';
                const mults = state.SERVER_CONFIG.ammoMultipliers[attackerAmmoType] || [1];
                let maxMultiplier = 1;
                if (attacker.ammo && attacker.ammo[attackerAmmoType]) {
                    attacker.ammo[attackerAmmoType].forEach((qty, tier) => {
                        if (qty > 0 && mults[tier] > maxMultiplier) {
                            maxMultiplier = mults[tier];
                        }
                    });
                }
                
                const finalMaxTheoreticalDamage = baseDmg * maxMultiplier;
                const maxAllowedDmg = finalMaxTheoreticalDamage * 1.5; // 50% extra para críticos/buffs del cliente

                let dmg = parseFloat(data.damage) || 50;
                if (dmg > maxAllowedDmg && !attacker.isAdmin) {
                    Logger.warn('SECURITY', `Daño PvP excedido de [${attacker.user}] a [${victim.user}]: reportado ${dmg}, máx permitido ${Math.round(maxAllowedDmg)} (base: ${baseDmg}, mult: ${maxMultiplier})`);
                    dmg = maxAllowedDmg; // Truncar al máximo permitido
                }
                
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
