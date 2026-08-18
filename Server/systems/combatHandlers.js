const User = require('../models/User');
const Logger = require('../utils/logger');
const { handleEnemyDeath } = require('./enemyLogic');
const { calculateFinalStats } = require('./statCalculator');
const { checkAndProcessDeathDrop } = require('./deathDropHelper');
const SkillManager = require('./skills/SkillManager');
const altarDefenseManager = require('./altarDefenseManager');
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
const ResurreccionSkill = require('./skills/ResurreccionSkill');
const FearSphereSkill = require('./skills/FearSphereSkill');
const combatTracker = require('./combatTracker');
const { checkRequirements } = require('./equipRequirements'); // v400.0: Requisitos de equipamiento (munición)
const visibilityGuard = require('./visibilityGuard'); // v620.0: Ojito de visibilidad de ítems

// v301.4: Soporte unificado de habilidades de resurrección


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
SkillManager.registerSkill(new ResurreccionSkill());
SkillManager.registerSkill(new FearSphereSkill());


// Habilidades de Curación/Soporte
SkillManager.registerSkill(new HealSkill("ESCUDO CELULAR"));
SkillManager.registerSkill(new HealSkill("AUTO-REPARACIÓN"));
SkillManager.registerSkill(new HealSkill("NANO-REGENERACIÓN"));

// Habilidades Ofensivas

// Habilidades de Estado/Buffs
SkillManager.registerSkill(new BuffSkill("REFLECT-OMEGA"));
SkillManager.registerSkill(new BuffSkill("TURBO-IMPULSO"));
SkillManager.registerSkill(new BuffSkill("HYPER-DASH"));

/**
 * registerCombatHandlers
 * Maneja toda la lógica de combate: disparos, habilidades y daño.
 */
function registerCombatHandlers(socket, io, state) {
    
    // Helper para leer dmgMod desde el ítem o master config (shields y engines)
    function readDmgMod(item) {
        const catKey = String(item.id).toLowerCase().startsWith('en') ? 'engines' : 'shields';
        if (state?.SERVER_CONFIG?.shopItems?.[catKey]) {
            const master = state.SERVER_CONFIG.shopItems[catKey].find(sh => String(sh.id) === String(item.id));
            if (master && master.dmgMod !== undefined) {
                return {
                    val: Number(master.dmgMod) || 0,
                    type: master.dmgModType || 'percent'
                };
            }
        }
        if (item.hasOwnProperty('dmgMod') || item.dmgMod !== undefined) {
            return {
                val: Number(item.dmgMod) || 0,
                type: item.dmgModType || 'percent'
            };
        }
        return { val: 0, type: 'percent' };
    }
    
    // SISTEMA DE DAÑO AUTORITATIVO (Anti-Cheat Server-Side)
    socket.on('playerFire', (fireData) => {
        const p = state.players[socket.id];
        if (!p || !state.SERVER_CONFIG) return;

        const lobbyZoneId = Number(state.SERVER_CONFIG?.pilotConfig?.startingMapId || 1);
        if (Number(p.zone) === lobbyZoneId) return;

        if (p.isSilenced || p.silencedUntil > Date.now()) return;

        // v308: Soporte dinámico para nuevas municiones
        const ammoType = fireData.type || 'laser';
        const ammoTier = (fireData.ammoType !== undefined) ? fireData.ammoType : 0;
        
        const validTypes = ['laser', 'missile', 'mine', 'melee', 'heal', 'siphon', 'emp', 'electron'];
        const typeKey = validTypes.includes(ammoType) ? ammoType : 'laser';

        // v400.0: Requisitos de equipamiento de munición (nivel, misiones, etc.)
        const ammoList = (state.SERVER_CONFIG.shopItems && state.SERVER_CONFIG.shopItems.ammo) ? state.SERVER_CONFIG.shopItems.ammo[typeKey] : null;
        const ammoMaster = (ammoList && Array.isArray(ammoList)) ? ammoList[ammoTier] : null;

        // v314.0: Rate Limiting de Disparos (Anti-Cheat Cooldown Autoritativo dinámico desde Admin Dash)
        const now = Date.now();
        p.lastFireTimes = p.lastFireTimes || {};
        const lastFire = p.lastFireTimes[typeKey] || 0;
        
        let cooldownMs = 120; // Límite mínimo/fallback entre disparos
        if (ammoMaster && ammoMaster.cooldown !== undefined) {
            // Aplicamos una tolerancia de lag del 10% para no desconectar a jugadores legítimos
            cooldownMs = Math.max(120, (Number(ammoMaster.cooldown) || 120) * 0.9);
        }
        
        if (now - lastFire < cooldownMs && !p.isAdmin) {
            return;
        }
        p.lastFireTimes[typeKey] = now;

        if (!p.ammo || !p.ammo[typeKey] || (p.ammo[typeKey][ammoTier] || 0) <= 0) {
            return; 
        }
        // v620.0: Ojito de visibilidad — munición hidden no puede dispararse ni siquiera con cliente hackeado (excepto admins)
        if (ammoMaster && ammoMaster.hidden && !p.isAdmin) {
            return;
        }
        if (ammoMaster && ammoMaster.requirements && ammoMaster.requirements.length > 0) {
            const reqCheck = checkRequirements(p, ammoMaster.requirements, state.SERVER_CONFIG);
            if (!reqCheck.ok) {
                socket.emit('gameNotification', { msg: `MUNICIÓN BLOQUEADA: ${reqCheck.msg}`, type: 'error' });
                return;
            }
        }

        p.ammo[typeKey][ammoTier]--;
        
        // Guardar munición activa en el jugador en el servidor para validar mecánicas en los impactos
        p.selectedAmmo = typeKey;
        p.selectedAmmoTier = ammoTier;

        const shipId = p.currentShipId || 1;
        const model = state.SERVER_CONFIG.shipModels ? state.SERVER_CONFIG.shipModels.find(m => m.id === shipId) : null;
        let baseDamage = (model && model.baseDmg !== undefined) ? Number(model.baseDmg) : 100;

        if (p.equipped && p.equipped.w) {
            p.equipped.w.forEach(item => {
                // v620.0: Ojito de visibilidad — armas hidden no aportan daño (excepto admins)
                const masterItem = (state.SERVER_CONFIG && state.SERVER_CONFIG.shopItems && state.SERVER_CONFIG.shopItems.weapons)
                    ? state.SERVER_CONFIG.shopItems.weapons.find(w => String(w.id) === String(item.id)) : null;
                if (masterItem && masterItem.hidden && !p.isAdmin) return;
                let baseVal = item.base || 0;
                if (!baseVal && masterItem) baseVal = masterItem.base || 0;
                baseDamage += Number(baseVal) || 0;
            });
        }

        // Modificador de daño desde escudos y motores (dmgMod)
        let dmgModFlat = 0;
        let dmgModPct = 0;
        if (p.equipped) {
            ['s', 'e'].forEach(cat => {
                if (Array.isArray(p.equipped[cat])) {
                    p.equipped[cat].forEach(item => {
                        const mod = readDmgMod(item);
                        if (mod.type === 'flat') dmgModFlat += mod.val;
                        else dmgModPct += mod.val;
                    });
                }
            });
        }
        const dmgModMult = 1.0 + (dmgModPct / 100);

        const mults = state.SERVER_CONFIG.ammoMultipliers[typeKey] || [1];
        const multiplier = mults[ammoTier] || 1;
        const finalAuthorizedDamage = Math.round((baseDamage * multiplier * dmgModMult) + dmgModFlat);

        const pData = {
            id: socket.id,
            bulletId: fireData.bulletId,
            damage: Math.round(finalAuthorizedDamage),
            x: Math.round(fireData.x),
            y: Math.round(fireData.y),
            angle: Math.round((fireData.angle || 0) * 100) / 100,
            rotation: Math.round((fireData.rotation || 0) * 100) / 100,
            type: ammoType,
            ammoType: ammoTier,
            targetId: fireData.targetId,
            range: Math.round(fireData.range !== undefined ? fireData.range : 600.0)
        };

        // v2.4: AOI adaptativo para playerFire
        // - Zonas especiales (arena_, extract_): broadcast completo para que todos vean los disparos
        // - Zonas normales: filtro por 3 celdas de radio
        const isSpecialZoneFire = typeof p.zone === 'string' && (p.zone.startsWith('arena_') || p.zone.startsWith('extract_') || p.zone.startsWith('dungeon'));
        if (isSpecialZoneFire) {
            socket.to(`zone_${p.zone}`).emit('playerFire', pData);
        } else {
            const FIRE_CELL_SIZE = 500;
            const fCx = Math.floor(p.x / FIRE_CELL_SIZE);
            const fCy = Math.floor(p.y / FIRE_CELL_SIZE);
            const zonePlayers = state.playersByZone[p.zone] || {};
            Object.values(zonePlayers).forEach(other => {
                if (other.socketId === socket.id) return;
                const oCx = Math.floor(other.x / FIRE_CELL_SIZE);
                const oCy = Math.floor(other.y / FIRE_CELL_SIZE);
                if (Math.abs(fCx - oCx) <= 3 && Math.abs(fCy - oCy) <= 3) {
                    io.to(other.socketId).emit('playerFire', pData);
                }
            });
        }


    });

    // SISTEMA DE HABILIDADES DE ESFERAS (Soporte Polimórfico v262.10)
    socket.on('playerSphereSkill', async (data) => {
        const p = state.players[socket.id];
        if (!p || p.isDead || !state.SERVER_CONFIG) return;

        const lobbyZoneId = Number(state.SERVER_CONFIG?.pilotConfig?.startingMapId || 1);
        if (Number(p.zone) === lobbyZoneId) return;

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

    // IMPACTO DE ESFERA DE TERROR (Mecanismo Autoritativo)
    socket.on('fearSphereHit', async (data) => {
        const p = state.players[socket.id];
        if (!p || p.isDead || !state.SERVER_CONFIG) return;
        
        const lobbyZoneId = Number(state.SERVER_CONFIG?.pilotConfig?.startingMapId || 1);
        if (Number(p.zone) === lobbyZoneId) return;

        const targetId = data.enemyId || data.victimId;
        const target = state.enemies[targetId] || state.players[targetId];
        if (!target || target.hp <= 0) return;

        // 1. Aplicar daño
        const damage = Number(data.damage) || 500;
        let actualDmg = 0;
        const oldHp = target.hp || 0;
        if (target.shield >= damage) {
            target.shield -= damage;
        } else {
            target.hp -= (damage - target.shield);
            target.shield = 0;
        }
        if (target.hp < 0) target.hp = 0;
        actualDmg = Math.ceil(oldHp - target.hp);

        // 2. Aplicar Fear (Miedo)
        const durationMs = Number(data.duration) || 3000;
        target.isFeared = true;
        target.fearEndTime = Date.now() + durationMs;

        if (target.socketId) {
            io.to(target.socketId).emit('stunState', { active: true, duration: durationMs, isFear: true });
            io.to(target.socketId).emit('gameNotification', { msg: "😱 ¡ESTÁS BAJO EFECTO DE TERROR! Tus controles se han invertido.", type: "error" });
        }

        // Sincronizar stats del target
        io.to(`zone_${target.zone}`).emit('playerStatSync', {
            id: target.socketId || target.id,
            hp: Math.ceil(target.hp),
            shield: Math.ceil(target.shield),
            isDead: target.hp <= 0,
            isFeared: true
        });

        io.to(`zone_${p.zone}`).emit('enemyDamaged', { id: target.id, hp: Math.max(0, target.hp), shield: target.shield, bulletId: "fear_hit" });
    });

    // IMPACTO EN ENEMIGO
    socket.on('enemyHit', async (data) => {
        const { enemyId, bulletId, damage } = data;
        const enemy = state.enemies[enemyId];
        const p = state.players[socket.id];
        if (!enemy || !p || !state.SERVER_CONFIG || p.isDead) return;

        // v314.0: Rate Limiting de Impactos (Anti-Cheat Damager)
        const now = Date.now();
        p.lastHitTimes = p.lastHitTimes || {};
        const lastHit = p.lastHitTimes[enemyId] || 0;
        const minHitCooldown = 120; // 120ms mínimo entre impactos en el mismo objetivo
        if (now - lastHit < minHitCooldown && !p.isAdmin) {
            return;
        }
        p.lastHitTimes[enemyId] = now;

        const lobbyZoneId = Number(state.SERVER_CONFIG?.pilotConfig?.startingMapId || 1);
        if (Number(p.zone) === lobbyZoneId) return;

        const dist = Math.hypot(p.x - enemy.x, p.y - enemy.y);
        if (dist > 1800) return;
        let isBlocked = enemy.isInvulnerable;
        if (enemy.ai && enemy.ai._isDefenseSkillActive) {
            if (enemy.colorState) {
                const requiredColor = enemy.colorState.bossColor;
                const playerColor = p.colorState;
                if (playerColor !== requiredColor) {
                    isBlocked = true;
                    socket.emit('combatLog', `⚠️ La barrera del Boss es ${requiredColor.toUpperCase()}. ¡Tu color actual es ${playerColor ? playerColor.toUpperCase() : "NINGUNO"}!`);
                }
            } else {
                isBlocked = true;
            }
        }

        // Verificar si el Muro de Energía (wall_dome) está activo y el jugador está fuera del área
        let isOutsideDome = false;
        let activeDomeRadius = 300;
        if (enemy.defState) {
            for (const mId in enemy.defState) {
                const s = enemy.defState[mId];
                if (s.isActive && s.type === "wall_dome") {
                    activeDomeRadius = s.radius || 300;
                    if (dist > activeDomeRadius) {
                        isOutsideDome = true;
                        break;
                    }
                }
            }
        }

        if (isBlocked || isOutsideDome) {
            enemy.lastHit = Date.now();
            p.lastCombatTime = Date.now();
            if (isOutsideDome) {
                socket.emit('combatLog', `⚠️ El enemigo está protegido por un Muro de Energía. Debes ingresar al área (${Math.round(activeDomeRadius)}px) para hacerle daño.`);
            }
            return;
        }

        const shipId = p.currentShipId || 1;
        const model = state.SERVER_CONFIG.shipModels ? state.SERVER_CONFIG.shipModels.find(m => m.id === shipId) : null;
        let weaponsBase = (model && model.baseDmg !== undefined) ? Number(model.baseDmg) : 100; // Daño base de la nave

        if (p.equipped && p.equipped.w) {
            p.equipped.w.forEach(it => {
                let baseVal = it.base || 0;
                if (!baseVal && state.SERVER_CONFIG && state.SERVER_CONFIG.shopItems && state.SERVER_CONFIG.shopItems.weapons) {
                    const master = state.SERVER_CONFIG.shopItems.weapons.find(w => String(w.id) === String(it.id));
                    if (master) baseVal = master.base || 0;
                }
                weaponsBase += Number(baseVal) || 0;
            });
        }

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

        // Modificador de daño desde escudos y motores (dmgMod)
        let dmgModFlat = 0;
        let dmgModPct = 0;
        if (p.equipped) {
            ['s', 'e'].forEach(cat => {
                if (Array.isArray(p.equipped[cat])) {
                    p.equipped[cat].forEach(item => {
                        const mod = readDmgMod(item);
                        if (mod.type === 'flat') dmgModFlat += mod.val;
                        else dmgModPct += mod.val;
                    });
                }
            });
        }
        const dmgModMult = 1.0 + (dmgModPct / 100);

        // Permitimos un 50% extra para críticos/buffs del cliente
        let maxAllowed = (weaponsBase * maxAmmoMult + dmgModFlat) * dmgModMult * 1.5;
        if (maxAllowed < 1000) maxAllowed = 1000;
        
        let finalDamage = parseFloat(damage) || 100;
        const isReflect = !!data.isReflect;
        if (finalDamage > maxAllowed && !p.isAdmin && !isReflect) {
            Logger.warn('SECURITY', `Daño PvE excedido de [${p.user}] a enemigo [${enemy.name}]: reportado ${finalDamage}, máx permitido ${Math.round(maxAllowed)} (base: ${weaponsBase}, mult: ${maxAmmoMult})`);
            finalDamage = maxAllowed;
        }

        const activeAmmo = p.selectedAmmo || 'laser';
        const activeTier = p.selectedAmmoTier !== undefined ? p.selectedAmmoTier : 0;
        const ammoList = state.SERVER_CONFIG.shopItems?.ammo?.[activeAmmo] || [];
        const ammoConfig = ammoList[activeTier] || {};


        if (isReflect) {
            // Daño directo de reflejo (no activa efectos de munición equipada como curación/sifón)
            if (enemy.shield >= finalDamage) enemy.shield -= finalDamage;
            else { enemy.hp -= (finalDamage - enemy.shield); enemy.shield = 0; }
            finalDamage = 0; // Se aplicó el daño directamente, evitar doble aplicación abajo
        } else if (activeAmmo === 'heal') {
            // Curativa: Restaura HP y Escudo al propio jugador en PvE
            const healPct = (ammoConfig.healPctPvE !== undefined ? ammoConfig.healPctPvE : 40) / 100;
            const healAmount = finalDamage * healPct;

            const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
            const mapCfg = maps[p.zone] || maps[p.zone.toString()];
            const healPenaltyMech = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'healing_penalty') : null;
            let finalHealAmount = healAmount;
            if (healPenaltyMech) {
                if (healPenaltyMech.penaltyPercentage !== undefined && healPenaltyMech.penaltyPercentage !== "") {
                    const pct = parseFloat(healPenaltyMech.penaltyPercentage) || 0;
                    finalHealAmount = finalHealAmount * (1 - pct / 100);
                }
                if (healPenaltyMech.penaltyFixed !== undefined && healPenaltyMech.penaltyFixed !== "") {
                    const fixed = parseFloat(healPenaltyMech.penaltyFixed) || 0;
                    finalHealAmount = Math.max(0, finalHealAmount - fixed);
                }
            }

            const oldHp = p.hp;
            const oldShield = p.shield;
            p.hp = Math.min(p.maxHp, p.hp + finalHealAmount);
            p.shield = Math.min(p.maxShield, p.shield + finalHealAmount);
            const actualHeal = Math.ceil((p.hp - oldHp) + (p.shield - oldShield));
            
            io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                id: socket.id, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield), 
                maxHp: p.maxHp, maxShield: p.maxShield, isDead: p.isDead,
                isInvulnerable: p.isInvulnerable, isInvisible: p.isInvisible,
                healPopup: actualHeal
            });
            combatTracker.trackHealingDone(socket.id, socket.id, actualHeal, 'ammo_heal', state);
            finalDamage = 0; // No le hace daño al enemigo
        } else {
            if (activeAmmo === 'siphon') {
                // Vampírica (Sifón): cura una porción del daño infligido al atacante
                const siphonPct = (ammoConfig.siphonPct !== undefined ? ammoConfig.siphonPct : 25) / 100;
                const siphonAmount = finalDamage * siphonPct;
                const oldHp = p.hp;
                const oldShield = p.shield;
                p.hp = Math.min(p.maxHp, p.hp + siphonAmount);
                p.shield = Math.min(p.maxShield, p.shield + siphonAmount);
                const actualHeal = Math.ceil((p.hp - oldHp) + (p.shield - oldShield));
                
                io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                    id: socket.id, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield), 
                    maxHp: p.maxHp, maxShield: p.maxShield, isDead: p.isDead,
                    isInvulnerable: p.isInvulnerable, isInvisible: p.isInvisible,
                    healPopup: actualHeal
                });
                combatTracker.trackHealingDone(socket.id, socket.id, actualHeal, 'ammo_siphon', state);
            } else if (activeAmmo === 'emp') {
                // EMP: Silencia la IA del bicho durante el tiempo configurado
                const silenceMs = ammoConfig.silenceDurationMs !== undefined ? ammoConfig.silenceDurationMs : 3000;
                enemy.isSilenced = true;
                enemy.silencedUntil = Date.now() + silenceMs;
            } else if (activeAmmo === 'melee') {
                // Melee: Aplica una ralentización inmediata (microparálisis) al enemigo
                const slowMs = ammoConfig.slowDurationMs !== undefined ? ammoConfig.slowDurationMs : 1000;
                enemy.isSlowed = true;
                enemy.slowEndTime = Date.now() + slowMs;
            } else if (activeAmmo === 'electron') {
                // Electron: Otorga velocidad de movimiento acumulable al jugador al impactar
                const buffPct = ammoConfig.speedBuffPct !== undefined ? ammoConfig.speedBuffPct : 15;
                const buffDuration = ammoConfig.speedBuffDurationMs !== undefined ? ammoConfig.speedBuffDurationMs : 3000;
                const maxStacks = ammoConfig.speedBuffMaxStacks !== undefined ? ammoConfig.speedBuffMaxStacks : 4;
                
                p.electronSpeedBuffActive = true;
                p.electronSpeedBuffPct = buffPct;
                p.electronSpeedBuffDurationMs = buffDuration;
                p.electronSpeedBuffMaxStacks = maxStacks;
                
                const now = Date.now();
                if (p.electronSpeedBuffEndTime && p.electronSpeedBuffEndTime > now) {
                    p.electronSpeedBuffStacks = Math.min((p.electronSpeedBuffStacks || 0) + 1, maxStacks);
                } else {
                    p.electronSpeedBuffStacks = 1;
                }
                p.electronSpeedBuffEndTime = now + buffDuration;
                
                // Recalcular estadísticas del jugador para que tenga efecto
                calculateFinalStats(p, state.SERVER_CONFIG);
                
                // Sincronizar stats del jugador con la nueva velocidad
                io.to(`zone_${p.zone}`).emit('playerStatSync', {
                    id: socket.id,
                    speed: p.speed,
                    electronSpeedBuff: {
                        duration: buffDuration,
                        pct: buffPct,
                        stacks: p.electronSpeedBuffStacks
                    }
                });
            }

            if (enemy.reflectActive) {
                const reflectMult = enemy.reflectMult !== undefined ? enemy.reflectMult : 0.8;
                const reflectedDmg = Math.round(finalDamage * reflectMult);
                if (reflectedDmg > 0 && !p.isInvulnerable) {
                    if (p.shield >= reflectedDmg) p.shield -= reflectedDmg;
                    else { p.hp -= (reflectedDmg - p.shield); p.shield = 0; }
                    if (p.hp <= 0) { p.hp = 0; p.isDead = true; }
                    p.lastCombatTime = Date.now();
                    combatTracker.trackDamageTaken(socket.id, enemyId, reflectedDmg, 'reflect', state);
                    
                    socket.emit('environmentDamage', { damage: reflectedDmg });
                    
                    io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                        id: socket.id, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield), 
                        maxHp: p.maxHp, maxShield: p.maxShield, isDead: p.isDead,
                        isInvulnerable: !!p.isInvulnerable, isInvisible: !!p.isInvisible
                    });
                    
                    socket.emit('combatLog', `⚠️ ¡Daño reflejado! Recibiste ${reflectedDmg} de daño.`);
                    
                    io.to(`zone_${p.zone}`).emit('serverEnemyAction', {
                        id: enemy.id,
                        action: "reflect_trigger",
                        targetId: socket.id,
                        damage: reflectedDmg
                    });
                }
            }

            if (enemy.shield >= finalDamage) enemy.shield -= finalDamage;
            else { enemy.hp -= (finalDamage - enemy.shield); enemy.shield = 0; }
            combatTracker.trackDamageDealt(socket.id, enemyId, finalDamage, 'pve', state);

            // v400.60: Registro de daño individual por jugador al enemigo (usado en mecánicas tipo "burrow" al elegir target "más daño hace")
            if (!enemy.playerDamage) enemy.playerDamage = {};
            enemy.playerDamage[socket.id] = (enemy.playerDamage[socket.id] || 0) + finalDamage;
        }
        
        enemy.lastHit = Date.now();
        enemy.lastHitter = socket.id;
        p.lastCombatTime = Date.now();

        socket.emit('enemyDamaged', { id: enemyId, hp: Math.max(0, enemy.hp), shield: enemy.shield, bulletId });

        if (enemy.hp <= 0 && !enemy.isDeadProcessed) {
            handleEnemyDeath(enemyId, io, state, socket.id);
        }
    });

    // DAÑO POR ENEMIGO
    socket.on('playerHitByEnemy', (data) => {
        const p = state.players[socket.id];
        if (p && !p.isDead && state.SERVER_CONFIG) {
            const lobbyZoneId = Number(state.SERVER_CONFIG?.pilotConfig?.startingMapId || 1);
            if (Number(p.zone) === lobbyZoneId) return;

            const attackerType = data.attackerType || 'enemy';
            if (attackerType === 'remote' || attackerType === 'player') return;
            
            // v371.1: Resolución autoritativa del tipo de enemigo en el servidor para evitar desincronización por anti-cheat
            const attackerId = data.attackerId || data.enemyId || data.senderId;
            const isClone = attackerId && attackerId.startsWith('clone_');
            
            let enemyType = 1;
            if (attackerId && state.enemies[attackerId]) {
                enemyType = state.enemies[attackerId].type;
            } else if (data.enemyType !== undefined) {
                enemyType = data.enemyType;
            }
            
            let dmg = data.damage || 0;

            // v410: ROBADOR DE ESCUDO (shield_steal) - El impacto no hace daño,
            // crea el vínculo de robo de escudo en el enemigo (autoritativo)
            if (attackerType === 'enemy' && data.bulletType === 'shield_steal') {
                const attackerEnemy = state.enemies[attackerId];
                if (attackerEnemy && attackerEnemy.ai && typeof attackerEnemy.ai._onEnemyShieldStealHit === 'function') {
                    const cfg = state.SERVER_CONFIG.enemyModels[enemyType];
                    let mech = null;
                    if (cfg && cfg.defenseMechanics && Array.isArray(cfg.defenseMechanics)) {
                        mech = cfg.defenseMechanics.find(m => m.type === 'shield_steal') || null;
                    }
                    const mId = attackerEnemy._shieldStealMId || 'def_shield_steal';
                    attackerEnemy.ai._onEnemyShieldStealHit(p.socketId, mech, mId, Date.now(), io, state);
                    p.lastCombatTime = Date.now();
                }
                return;
            }

            // v412: ROBADOR DE VIDA (life_steal) - El impacto no hace daño,
            // crea el vínculo de robo de vida en el enemigo (autoritativo)
            if (attackerType === 'enemy' && data.bulletType === 'life_steal') {
                const attackerEnemy = state.enemies[attackerId];
                if (attackerEnemy && attackerEnemy.ai && typeof attackerEnemy.ai._onEnemyLifeStealHit === 'function') {
                    const cfg = state.SERVER_CONFIG.enemyModels[enemyType];
                    let mech = null;
                    if (cfg && cfg.defenseMechanics && Array.isArray(cfg.defenseMechanics)) {
                        mech = cfg.defenseMechanics.find(m => m.type === 'life_steal') || null;
                    }
                    const mId = attackerEnemy._lifeStealMId || 'def_life_steal';
                    attackerEnemy.ai._onEnemyLifeStealHit(p.socketId, mech, mId, Date.now(), io, state);
                    p.lastCombatTime = Date.now();
                }
                return;
            }

            // v410: POLIMORFIA - Aplicar estado de transformación al impacto
            if (attackerType === 'enemy' && data.bulletType === 'polymorph') {
                const attackerEnemy = state.enemies[attackerId];
                if (attackerEnemy) {
                    // Buscar la mecánica polymorph en el enemigo para obtener la configuración
                    const cfg = state.SERVER_CONFIG.enemyModels[enemyType];
                    let matchingMech = null;
                    if (cfg && cfg.mechanics) {
                        matchingMech = cfg.mechanics.find(m => m.type === 'polymorph');
                    }
                    
                    const polyDuration = matchingMech ? matchingMech.polyDuration || 4000 : (data.polyDuration || 4000);
                    // Si encontramos la config, la usamos. Si no, usamos el fallback del cliente (true = no bloquear)
                    const canMove = matchingMech ? (matchingMech.canMove !== undefined ? matchingMech.canMove : false) : (data.polyCanMove !== undefined ? !!data.polyCanMove : false);
                    const canUseSkills = matchingMech ? (matchingMech.canUseSkills !== undefined ? matchingMech.canUseSkills : true) : (data.polyCanUseSkills !== undefined ? !!data.polyCanUseSkills : true);
                    
                    // Aplicar estado de polimorfia
                    p.isPolymorphed = true;
                    p.polyEndTime = Date.now() + polyDuration;
                    p.polyCanMove = canMove;
                    p.polyCanUseSkills = canUseSkills;
                    
                    // Sincronizar al cliente
                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: p.socketId,
                        isPolymorphed: true,
                        polymorphed: true,
                        polyEndTime: p.polyEndTime,
                        polyDuration: polyDuration, // Duración configurada original
                        polyCanMove: p.polyCanMove,
                        polyCanUseSkills: p.polyCanUseSkills
                    });
                    
                    // Si hay daño configurado, aplicarlo
                    if (matchingMech && matchingMech.bulletDamage > 0) {
                        dmg = matchingMech.bulletDamage;
                    } else {
                        dmg = 0; // Polimorfia pura sin daño
                    }
                    
                    io.to(p.socketId).emit('gameNotification', { 
                        msg: `🟦 ¡Has sido transformado en un cubo! Duración: ${polyDuration}ms`, 
                        type: "warning" 
                    });
                    
                     p.lastCombatTime = Date.now();
                }
                return;
            }

            // v413: EJECUCIÓN DIRECTA (Execution / Death) - si la calavera impacta, muerte instantánea.
            // Ignora escudo y vida: el jugador es limpiado (hp=0, shield=0, isDead=true).
            if (attackerType === 'enemy' && data.bulletType === 'execution') {
                const attackerEnemy = state.enemies[attackerId];
                if (attackerEnemy && !p.isDead) {
                    // Reset de slow/stun de somnolencia por si existía
                    p.isSlowed = false; p.slowPoints = 0; p.slowEndTime = 0;
                    io.to(p.socketId).emit('slowState', { active: false, isSleep: false });

                    p.hp = 0;
                    p.shield = 0;
                    p.isDead = true;
                    p.isStunned = true;
                    p.stunEndTime = Date.now() + 4000;

                    io.to(p.socketId).emit('stunState', { active: true, duration: 4000, isSleep: false });
                    io.to(p.socketId).emit('gameNotification', { msg: '☠️ ¡Ejecución directa! Has sido ejecutado por una calavera.', type: 'error' });

                    checkAndProcessDeathDrop(p, io, state);

                    io.to(`zone_${p.zone}`).emit('playerStatSync', {
                        id: p.socketId, hp: 0, shield: 0,
                        maxHp: p.maxHp, maxShield: p.maxShield,
                        isDead: p.isDead, isStunned: true
                    });
                }
                p.lastCombatTime = Date.now();
                return;
            }

            if (attackerType === 'enemy') {
                const cfg = state.SERVER_CONFIG.enemyModels[enemyType];
                let baseDmg = isClone ? 0 : (cfg ? cfg.bulletDamage : 50);
                
                if (!isClone && cfg && cfg.mechanics && data.bulletType) {
                    const searchType = data.bulletType === 'orbital_mine' ? 'orbital_strike' : data.bulletType;
                    const matchingMech = cfg.mechanics.find(m => m.type === searchType);
                    if (matchingMech) {
                        if (matchingMech.type === 'spin_ring') {
                            baseDmg = matchingMech.damage !== undefined ? matchingMech.damage : 100;
                        } else if (matchingMech.bulletDamage !== undefined) {
                            baseDmg = matchingMech.bulletDamage;
                        } else if (matchingMech.damage !== undefined) {
                            baseDmg = matchingMech.damage;
                        }
                    }
                }
                
                // v266.550: Registrar éxito del enemigo para reglas de persecución
                const attackerId = data.attackerId || data.enemyId || data.senderId;
                if (attackerId && state.enemies[attackerId]) {
                    state.enemies[attackerId].lastSuccessHit = Date.now();
                }

                // v266.999: Blindaje de Daño Ambiental (Permitir daño x2, x3 si el mapa es extremo)
                const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
                const mapCfg = maps[p.zone] || maps[p.zone.toString()];
                const extremeAggro = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'extreme_aggression') : null;
                const multiplicadorMech = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'multiplicador') : null;
                const multiplicadorMult = multiplicadorMech ? (parseFloat(multiplicadorMech.multiplier) || 1) : 1;
                const damageMult = (extremeAggro ? (parseFloat(extremeAggro.damageMult) || 1) : 1) * multiplicadorMult;
                
                const authorizedMaxDmg = baseDmg * damageMult;

                // El daño recibido no puede ser inferior al daño real del enemigo (anti-GodMode/anti-mitigación hack)
                // a menos que sea 0 por invulnerabilidad o si es un clon
                if (p.isInvulnerable || isClone) {
                    dmg = 0;
                } else {
                    if (dmg < authorizedMaxDmg * 0.9 || dmg > (authorizedMaxDmg + 5)) {
                        dmg = authorizedMaxDmg;
                    }
                }

                // v266.250: Verificación de Tipo de Bala (Solo aplica slow si la bala coincide y no es clon)
                if (cfg && !isClone) {
                    let sAmount = 0;
                    let sDuration = 0;
                    let stunDuration = 0;
                    let isPct = false;

                    // Buscar la mecánica específica que corresponde a la bala que impactó
                    if (cfg.mechanics) {
                        const matchingMech = cfg.mechanics.find(m => m.type === data.bulletType);
                        if (matchingMech) {
                            if (matchingMech.type === "spin_ring") {
                                if (matchingMech.applySlow) {
                                    sAmount = matchingMech.slowPercentage || 0;
                                    sDuration = matchingMech.slowDuration || 0;
                                    isPct = !!matchingMech.slowIsPercentage;
                                }
                            } else {
                                sAmount = matchingMech.slowAmount || 0;
                                sDuration = matchingMech.slowDuration || 0;
                                stunDuration = matchingMech.stunDuration || 0;
                            }
                        }
                    }

                    // Fallback a la raíz si no hay mecánicas modulares (retrocompatibilidad)
                    if (sAmount === 0 && cfg.slowAmount > 0 && data.bulletType !== "spin_ring") {
                        sAmount = cfg.slowAmount;
                        sDuration = cfg.slowDuration || 3000;
                    }

                    if (sAmount > 0) {
                        p.isSlowed = true;
                        p.slowPoints = sAmount;
                        p.lastSlowTime = Date.now();
                        p.slowEndTime = Date.now() + sDuration;
                        p.slowIsPercentage = isPct;
                        
                        io.to(p.socketId).emit('slowState', { active: true, amount: sAmount, isPercentage: isPct, duration: sDuration });
                    }
                }

                // Otorgar el buff de velocidad al enemigo cuando el orbe spin_ring golpea al jugador
                if (data.bulletType === "spin_ring" && attackerId && state.enemies[attackerId]) {
                    const enemyObj = state.enemies[attackerId];
                    if (cfg && cfg.mechanics) {
                        const matchingMech = cfg.mechanics.find(m => m.type === "spin_ring");
                        if (matchingMech) {
                            const speedBuffAmount = matchingMech.speedBuffAmount !== undefined ? matchingMech.speedBuffAmount : 150;
                            const speedBuffDuration = matchingMech.speedBuffDuration !== undefined ? matchingMech.speedBuffDuration : 3000;
                            
                            if (speedBuffAmount > 0 && speedBuffDuration > 0) {
                                enemyObj.spinSpeedBuffActive = true;
                                enemyObj.spinSpeedBuffAmount = speedBuffAmount;
                                enemyObj.spinSpeedBuffEndTime = Date.now() + speedBuffDuration;
                                
                                io.to(`zone_${p.zone}`).emit('serverEnemyAction', {
                                    id: enemyObj.id,
                                    action: "speed_buff",
                                    duration: speedBuffDuration,
                                    speedBonus: speedBuffAmount
                                });
                            }
                        }
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

            if (p.isAsleep && p.sleepWakeOnDamage !== false) {
                dmg = dmg * (p.nightmareMultiplier || 2.0);
                p.isAsleep = false;
                p.isStunned = false;
                p.sleepEndTime = 0;
                p.sleepDmgPerSecond = 0;
                io.to(p.socketId).emit('stunState', { active: false });
                io.to(p.socketId).emit('gameNotification', { msg: "💥 ¡PESADILLA! Te despertás abruptamente tras recibir daño extra.", type: "warning" });
            }

            if (p.isInvulnerable) dmg = 0;

            const dmgTakenFinal = dmg;
            if (p.shield >= dmg) p.shield -= dmg;
            else { p.hp -= (dmg - p.shield); p.shield = 0; }
            if (p.hp <= 0) {
                p.hp = 0;
                p.isDead = true;
                checkAndProcessDeathDrop(p, io, state);
            }
            p.lastCombatTime = Date.now();
            p.regenDelay = (attackerType === 'remote') ? 15000 : 5000;
            if (dmgTakenFinal > 0) {
                combatTracker.trackDamageTaken(socket.id, attackerId, dmgTakenFinal, 'pve', state);
            }
            
            io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                id: socket.id, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield), 
                maxHp: p.maxHp, maxShield: p.maxShield, isDead: p.isDead,
                isInvulnerable: p.isInvulnerable, isInvisible: p.isInvisible // v245.93: Blindaje de Sigilo en PvE
            });
        }
    });

    // PVP: DAÑO ENTRE JUGADORES
    socket.on('playerHitByPlayer', (data) => {
        const victim = state.players[data.victimId];
        const attacker = state.players[socket.id];
        
        if (victim && attacker && !victim.isDead && !attacker.isDead) {
            const lobbyZoneId = Number(state.SERVER_CONFIG?.pilotConfig?.startingMapId || 1);
            if (Number(attacker.zone) === lobbyZoneId || Number(victim.zone) === lobbyZoneId) return;

            console.log(`[PVP-HIT-IN] ${attacker.user} (pvpEnabled: ${attacker.pvpEnabled}) atacó a ${victim.user} (pvpEnabled: ${victim.pvpEnabled}, isInvulnerable: ${victim.isInvulnerable}) | Daño: ${data.damage}`);
            if (victim.pvpEnabled && attacker.pvpEnabled) {
                // v314.0: Rate Limiting de Impactos en PvP (Anti-Cheat Instakill)
                const now = Date.now();
                attacker.lastPvpHitTimes = attacker.lastPvpHitTimes || {};
                const lastPvpHit = attacker.lastPvpHitTimes[data.victimId] || 0;
                const minPvpHitCooldown = 200; // 200ms mínimo entre golpes PvP al mismo objetivo
                if (now - lastPvpHit < minPvpHitCooldown && !attacker.isAdmin) {
                    return;
                }
                attacker.lastPvpHitTimes[data.victimId] = now;

                if (victim.isInvulnerable) {
                    // v270.20: Enviar actualización de stats reales correctivas de la víctima a todos en la zona (incluyendo el atacante)
                    // para reajustar/corregir cualquier daño predictivo de 100 local en sus clientes
                    io.to(`zone_${victim.zone}`).emit('playerStatSync', {
                        id: data.victimId,
                        hp: Math.ceil(victim.hp),
                        shield: Math.ceil(victim.shield),
                        maxHp: victim.maxHp,
                        maxShield: victim.maxShield,
                        isDead: victim.isDead,
                        isInvulnerable: true,
                        isInvisible: victim.isInvisible
                    });
                    return;
                }

                // v270.0: Validación de Distancia en PvP
                const dist = Math.hypot(attacker.x - victim.x, attacker.y - victim.y);
                if (dist > 1800) {
                    Logger.warn('SECURITY', `Intento de PvP a distancia inválida: [${attacker.user}] -> [${victim.user}] (Distancia: ${Math.round(dist)}px)`);
                    return;
                }

                // Calcular daño teórico máximo para el atacante
                let baseDmg = 100;
                if (attacker.equipped && attacker.equipped.w) {
                    attacker.equipped.w.forEach(item => {
                        let baseVal = item.base || 0;
                        if (!baseVal && state.SERVER_CONFIG && state.SERVER_CONFIG.shopItems && state.SERVER_CONFIG.shopItems.weapons) {
                            const masterItem = state.SERVER_CONFIG.shopItems.weapons.find(w => String(w.id) === String(item.id));
                            if (masterItem) baseVal = masterItem.base || 0;
                        }
                        baseDmg += Number(baseVal) || 0;
                    });
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
                
                // Modificador de daño desde escudos y motores (dmgMod)
                let dmgModFlat = 0;
                let dmgModPct = 0;
                if (attacker.equipped) {
                    ['s', 'e'].forEach(cat => {
                        if (Array.isArray(attacker.equipped[cat])) {
                            attacker.equipped[cat].forEach(item => {
                                const mod = readDmgMod(item);
                                if (mod.type === 'flat') dmgModFlat += mod.val;
                                else dmgModPct += mod.val;
                            });
                        }
                    });
                }
                const dmgModMult = 1.0 + (dmgModPct / 100);

                const finalMaxTheoreticalDamage = (baseDmg * maxMultiplier + dmgModFlat) * dmgModMult;
                const maxAllowedDmg = finalMaxTheoreticalDamage * 1.5; // 50% extra para críticos/buffs del cliente

                const isReflect = !!data.isReflect;
                let dmg = parseFloat(data.damage) || 50;
                if (dmg > maxAllowedDmg && !attacker.isAdmin && !isReflect) {
                    Logger.warn('SECURITY', `Daño PvP excedido de [${attacker.user}] a [${victim.user}]: reportado ${dmg}, máx permitido ${Math.round(maxAllowedDmg)} (base: ${baseDmg}, mult: ${maxMultiplier})`);
                    dmg = maxAllowedDmg; // Truncar al máximo permitido
                }
                
                const attackerAmmoTier = attacker.selectedAmmoTier !== undefined ? attacker.selectedAmmoTier : 0;
                const attackerAmmoList = state.SERVER_CONFIG.shopItems?.ammo?.[attackerAmmoType] || [];
                const attackerAmmoConfig = attackerAmmoList[attackerAmmoTier] || {};

                if (isReflect) {
                    // Daño directo de reflejo en PvP (no activa curación ni sifones de la munición del atacante)
                    // dmg sigue intacto para aplicarse a la víctima abajo
                } else if (attackerAmmoType === 'heal') {
                    // Soporte: Cura a la víctima y al atacante usando los porcentajes configurados
                    const healVictimPct = (attackerAmmoConfig.healPctVictimPvP !== undefined ? attackerAmmoConfig.healPctVictimPvP : 80) / 100;
                    const healAttackerPct = (attackerAmmoConfig.healPctAttackerPvP !== undefined ? attackerAmmoConfig.healPctAttackerPvP : 30) / 100;
                    const healVictim = dmg * healVictimPct;
                    const healAttacker = dmg * healAttackerPct;

                    const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
                    
                    // Penalización de curación para la víctima
                    const victimMapCfg = maps[victim.zone] || maps[victim.zone.toString()];
                    const victimHealPenaltyMech = (victimMapCfg && Array.isArray(victimMapCfg.ambience)) ? victimMapCfg.ambience.find(a => a.type === 'healing_penalty') : null;
                    let finalHealVictim = healVictim;
                    if (victimHealPenaltyMech) {
                        if (victimHealPenaltyMech.penaltyPercentage !== undefined && victimHealPenaltyMech.penaltyPercentage !== "") {
                            const pct = parseFloat(victimHealPenaltyMech.penaltyPercentage) || 0;
                            finalHealVictim = finalHealVictim * (1 - pct / 100);
                        }
                        if (victimHealPenaltyMech.penaltyFixed !== undefined && victimHealPenaltyMech.penaltyFixed !== "") {
                            const fixed = parseFloat(victimHealPenaltyMech.penaltyFixed) || 0;
                            finalHealVictim = Math.max(0, finalHealVictim - fixed);
                        }
                    }

                    // Penalización de curación para el atacante
                    const attackerMapCfg = maps[attacker.zone] || maps[attacker.zone.toString()];
                    const attackerHealPenaltyMech = (attackerMapCfg && Array.isArray(attackerMapCfg.ambience)) ? attackerMapCfg.ambience.find(a => a.type === 'healing_penalty') : null;
                    let finalHealAttacker = healAttacker;
                    if (attackerHealPenaltyMech) {
                        if (attackerHealPenaltyMech.penaltyPercentage !== undefined && attackerHealPenaltyMech.penaltyPercentage !== "") {
                            const pct = parseFloat(attackerHealPenaltyMech.penaltyPercentage) || 0;
                            finalHealAttacker = finalHealAttacker * (1 - pct / 100);
                        }
                        if (attackerHealPenaltyMech.penaltyFixed !== undefined && attackerHealPenaltyMech.penaltyFixed !== "") {
                            const fixed = parseFloat(attackerHealPenaltyMech.penaltyFixed) || 0;
                            finalHealAttacker = Math.max(0, finalHealAttacker - fixed);
                        }
                    }
                    
                    victim.hp = Math.min(victim.maxHp, victim.hp + finalHealVictim);
                    victim.shield = Math.min(victim.maxShield, victim.shield + finalHealVictim);
                    
                    attacker.hp = Math.min(attacker.maxHp, attacker.hp + finalHealAttacker);
                    attacker.shield = Math.min(attacker.maxShield, attacker.shield + finalHealAttacker);
                    
                    combatTracker.trackHealingDone(socket.id, data.victimId, Math.round(finalHealVictim), 'pvp_heal_ammo', state);
                    combatTracker.trackHealingDone(socket.id, socket.id, Math.round(finalHealAttacker), 'pvp_heal_ammo', state);
                    
                    io.to(`zone_${attacker.zone}`).emit('playerStatSync', { 
                        id: socket.id, hp: Math.ceil(attacker.hp), shield: Math.ceil(attacker.shield), 
                        maxHp: attacker.maxHp, maxShield: attacker.maxShield, isDead: attacker.isDead,
                        isInvisible: attacker.isInvisible, isInvulnerable: !!attacker.isInvulnerable
                    });
                    dmg = 0; // No le causa daño a la víctima
                } else {
                    if (attackerAmmoType === 'siphon') {
                        // Sifón: Roba vida y cura al atacante
                        const siphonPct = (attackerAmmoConfig.siphonPct !== undefined ? attackerAmmoConfig.siphonPct : 25) / 100;
                        const siphonAmount = dmg * siphonPct;
                        attacker.hp = Math.min(attacker.maxHp, attacker.hp + siphonAmount);
                        attacker.shield = Math.min(attacker.maxShield, attacker.shield + siphonAmount);
                        combatTracker.trackHealingDone(socket.id, socket.id, Math.round(siphonAmount), 'pvp_siphon', state);
                        
                        io.to(`zone_${attacker.zone}`).emit('playerStatSync', { 
                            id: socket.id, hp: Math.ceil(attacker.hp), shield: Math.ceil(attacker.shield), 
                            maxHp: attacker.maxHp, maxShield: attacker.maxShield, isDead: attacker.isDead,
                            isInvisible: attacker.isInvisible, isInvulnerable: !!attacker.isInvulnerable
                        });
                    } else if (attackerAmmoType === 'emp') {
                        // EMP: Silencia a la víctima durante el tiempo configurado
                        const silenceMs = attackerAmmoConfig.silenceDurationMs !== undefined ? attackerAmmoConfig.silenceDurationMs : 3000;
                        victim.isSilenced = true;
                        victim.silencedUntil = Date.now() + silenceMs;
                        
                        setTimeout(() => {
                            if (state.players[data.victimId]) {
                                state.players[data.victimId].isSilenced = false;
                            }
                        }, silenceMs);
                        
                        io.to(data.victimId).emit('gameNotification', { msg: `🚨 ¡SILENCIADO POR PULSO EMP (${silenceMs}ms)! 🚨`, type: "error" });
                    } else if (attackerAmmoType === 'melee') {
                        // Melee: Ralentiza a la víctima
                        const slowMs = attackerAmmoConfig.slowDurationMs !== undefined ? attackerAmmoConfig.slowDurationMs : 1000;
                        const slowAmt = attackerAmmoConfig.slowAmount !== undefined ? attackerAmmoConfig.slowAmount : 200;
                        victim.isSlowed = true;
                        victim.slowEndTime = Date.now() + slowMs;
                        victim.slowIsPercentage = false;
                        io.to(data.victimId).emit('slowState', { active: true, amount: slowAmt, isPercentage: false, duration: slowMs });
                    } else if (attackerAmmoType === 'electron') {
                        // Electron: Otorga velocidad de movimiento acumulable al atacante
                        const buffPct = attackerAmmoConfig.speedBuffPct !== undefined ? attackerAmmoConfig.speedBuffPct : 15;
                        const buffDuration = attackerAmmoConfig.speedBuffDurationMs !== undefined ? attackerAmmoConfig.speedBuffDurationMs : 3000;
                        const maxStacks = attackerAmmoConfig.speedBuffMaxStacks !== undefined ? attackerAmmoConfig.speedBuffMaxStacks : 4;
                        
                        attacker.electronSpeedBuffActive = true;
                        attacker.electronSpeedBuffPct = buffPct;
                        attacker.electronSpeedBuffDurationMs = buffDuration;
                        attacker.electronSpeedBuffMaxStacks = maxStacks;
                        
                        const now = Date.now();
                        if (attacker.electronSpeedBuffEndTime && attacker.electronSpeedBuffEndTime > now) {
                            attacker.electronSpeedBuffStacks = Math.min((attacker.electronSpeedBuffStacks || 0) + 1, maxStacks);
                        } else {
                            attacker.electronSpeedBuffStacks = 1;
                        }
                        attacker.electronSpeedBuffEndTime = now + buffDuration;
                        
                        // Recalcular estadísticas del atacante
                        calculateFinalStats(attacker, state.SERVER_CONFIG);
                        
                        // Sincronizar stats del atacante
                        io.to(attacker.socketId).emit('playerStatSync', {
                            id: attacker.socketId,
                            speed: attacker.speed,
                            electronSpeedBuff: {
                                duration: buffDuration,
                                pct: buffPct,
                                stacks: attacker.electronSpeedBuffStacks
                            }
                        });
                    }

                    if (victim.isAsleep && victim.sleepWakeOnDamage !== false) {
                        dmg = dmg * (victim.nightmareMultiplier || 2.0);
                        victim.isAsleep = false;
                        victim.isStunned = false;
                        victim.sleepEndTime = 0;
                        victim.sleepDmgPerSecond = 0;
                        io.to(data.victimId).emit('stunState', { active: false });
                        io.to(data.victimId).emit('gameNotification', { msg: "💥 ¡PESADILLA! Te despertás abruptamente tras recibir daño extra.", type: "warning" });
                    }

                    if (victim.shield >= dmg) victim.shield -= dmg;
                    else { victim.hp -= (dmg - victim.shield); victim.shield = 0; }
                    combatTracker.trackDamageDealt(socket.id, data.victimId, Math.round(dmg), 'pvp', state);
                    combatTracker.trackDamageTaken(data.victimId, socket.id, Math.round(dmg), 'pvp', state);
                }
                
                if (victim.hp <= 0) {
                    victim.hp = 0;
                    victim.isDead = true;
                    checkAndProcessDeathDrop(victim, io, state);
                }
                
                victim.lastCombatTime = now;
                attacker.lastCombatTime = now;
                victim.lastPvpCombatTime = now;
                attacker.lastPvpCombatTime = now;
                victim.regenDelay = 15000;
                
                io.to(`zone_${victim.zone}`).emit('playerStatSync', { 
                    id: data.victimId, hp: Math.ceil(victim.hp), shield: Math.ceil(victim.shield), 
                    maxHp: victim.maxHp, maxShield: victim.maxShield, isDead: victim.isDead,
                    isInvisible: victim.isInvisible, isInvulnerable: !!victim.isInvulnerable
                });
            } else {
                // v270.25: Forzar sincronización correctiva de la víctima si el PvP está bloqueado/seguro
                // para que el atacante no se quede con la barra de vida desincronizada predictivamente en su pantalla
                io.to(`zone_${victim.zone}`).emit('playerStatSync', { 
                    id: data.victimId, hp: Math.ceil(victim.hp), shield: Math.ceil(victim.shield), 
                    maxHp: victim.maxHp, maxShield: victim.maxShield, isDead: victim.isDead,
                    isInvisible: victim.isInvisible, isInvulnerable: !!victim.isInvulnerable
                });

                if (!attacker.pvpEnabled) {
                    socket.emit('gameNotification', { msg: "PVP BLOQUEADO: Tu modo combate est├í SEGURO", type: "warning" });
                } else if (!victim.pvpEnabled) {
                    socket.emit('gameNotification', { msg: "PVP BLOQUEADO: El objetivo est├í en modo SEGURO", type: "warning" });
                }
            }
        }
    });

    // SISTEMA DE DEFENSA DEL ALTAR: IMPACTO AL ALTAR
    socket.on('altarHit', (hitData) => {
        try {
            const p = state.players[socket.id];
            if (!p || p.isDead || !state.SERVER_CONFIG) return;

            const altarDefenseConfig = state.SERVER_CONFIG && state.SERVER_CONFIG.gameModes && state.SERVER_CONFIG.gameModes.altar_defense;
            if (!altarDefenseConfig) return;

            const isAltarZone = altarDefenseConfig.maps && altarDefenseConfig.maps.map(Number).includes(Number(p.zone));
            if (!isAltarZone) return;

            // Inicializar el estado del altar en memoria del servidor si es la primera vez
            if (!state.altarState) {
                state.altarState = {
                    hp: Number(altarDefenseConfig.altarHp) || 10000,
                    maxHp: Number(altarDefenseConfig.altarHp) || 10000,
                    shield: Number(altarDefenseConfig.altarShield) || 5000,
                    maxShield: Number(altarDefenseConfig.altarShield) || 5000,
                    zone: p.zone
                };
            }

            let dmg = parseFloat(hitData.damage) || 0;
            if (dmg <= 0) return;

            let altar = state.altarState;
            if (altar.shield >= dmg) {
                altar.shield -= dmg;
            } else {
                altar.hp -= (dmg - altar.shield);
                altar.shield = 0;
            }

            if (altar.hp <= 0) {
                altar.hp = 0;
                
                io.to(`zone_${p.zone}`).emit('gameNotification', { 
                    msg: "🚨 ¡EL ALTAR HA SIDO DESTRUIDO! MISIÓN FALLIDA. 🚨", 
                    type: 'error' 
                });

                // Devolver a todos los jugadores en la zona al Lobby (Zona 1) después de 3 segundos
                setTimeout(() => {
                    altarDefenseManager.endMatch(false);
                }, 3000);
            }

            // Emitir la actualización del estado del altar a todos en el sector
            io.to(`zone_${p.zone}`).emit('altarStateUpdate', {
                hp: Math.max(0, Math.ceil(altar.hp)),
                maxHp: altar.maxHp,
                shield: Math.max(0, Math.ceil(altar.shield)),
                maxShield: altar.maxShield
            });

        } catch (e) {
            console.error("Error en altarHit:", e);
        }
    });

}

module.exports = {
    registerCombatHandlers
};
