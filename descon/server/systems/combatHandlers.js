const User = require('../models/User');
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

        if (enemy.hp <= 0 && !enemy.isDying) {
            enemy.isDying = true;
            const cfg = state.SERVER_CONFIG.enemyModels[enemy.type] || {};
            let h_loot = (cfg.rewardHubs !== undefined) ? cfg.rewardHubs : (enemy.type * 500);
            let o_loot = (cfg.rewardOhcu !== undefined) ? cfg.rewardOhcu : (enemy.type * 10);
            let e_loot = (cfg.rewardExp !== undefined) ? cfg.rewardExp : (enemy.type * 100);

            if (enemy.name && enemy.name.toUpperCase().includes("CLONE")) {
                h_loot = 0; o_loot = 0; e_loot = 0;
            }

            io.to(`zone_${enemy.zone}`).emit('enemyDead', { id: enemyId, killer: socket.id, bulletId, finalDamage: finalDamage });

            // REPARTO DE LOOT COOPERATIVO
            try {
                const killerUid = socket.dbUser?._id.toString();
                if (!killerUid) return;

                let membersToReward = [socket]; 
                const partyId = state.playerParty[killerUid];

                if (partyId && state.parties[partyId]) {
                    const onlinePartyMembers = [];
                    for (const mUid of state.parties[partyId].members) {
                        const mUidStr = mUid.toString();
                        if (mUidStr === killerUid) continue; 
                        
                        let sid = state.activeSessions.get(mUidStr);
                        if (sid) {
                            const s = io.sockets.sockets.get(sid);
                            if (s && state.players[s.id]) {
                                const pM = state.players[s.id];
                                const distToE = Math.hypot(pM.x - enemy.x, pM.y - enemy.y);
                                if (pM.zone === enemy.zone && distToE <= 2500) onlinePartyMembers.push(s);
                            }
                        }
                    }
                    membersToReward = membersToReward.concat(onlinePartyMembers);
                }

                const shareCount = membersToReward.length;
                const shared_h = Math.floor(h_loot / shareCount);
                const shared_o = Math.floor(o_loot / shareCount);
                const shared_e = Math.floor(e_loot / shareCount);

                for (const memberSocket of membersToReward) {
                    if (!memberSocket || !memberSocket.dbUser) continue;
                    const memP = state.players[memberSocket.id];
                    const user = await User.findById(memberSocket.dbUser._id.toString());
                    
                    if (user && memP) {
                        user.gameData.hubs += shared_h;
                        user.gameData.ohcu += shared_o;
                        user.gameData.exp += shared_e;

                        memberSocket.emit('enemyKillSession', { hubs: shared_h, ohcu: shared_o, exp: shared_e, killer: socket.id });

                        // v262.135: Subida de Nivel (Autoridad del Servidor)
                        let nextLevelExp = Math.floor(1000 * Math.pow(user.gameData.level, 1.5));
                        while (user.gameData.exp >= nextLevelExp && user.gameData.level < 100) {
                            user.gameData.exp -= nextLevelExp;
                            user.gameData.level++;
                            user.gameData.skillPoints++;
                            memberSocket.emit('gameNotification', { msg: `NIVEL ${user.gameData.level} ALCANZADO!`, type: 'success' });
                            nextLevelExp = Math.floor(1000 * Math.pow(user.gameData.level, 1.5));
                        }

                        // Actualizar RAM (players) - El Auto-Save usará estos datos
                        memP.hubs = user.gameData.hubs;
                        memP.ohcu = user.gameData.ohcu;
                        memP.exp = user.gameData.exp;
                        memP.level = user.gameData.level;
                        memP.skillPoints = user.gameData.skillPoints;

                        memberSocket.emit('inventoryData', { player: user.gameData });
                    }
                }
            } catch (e) { console.error("Error loot cooperativo:", e); }
            delete state.enemies[enemyId];
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
                if (data.attackerId && state.enemies[data.attackerId]) {
                    state.enemies[data.attackerId].lastSuccessHit = Date.now();
                }

                // v262.140: Parche Anti-Inmortalidad
                // Si el cliente manda daño 0 o sospechosamente bajo, aplicamos daño base
                if (dmg <= 0 || dmg > baseDmg) dmg = baseDmg;

                // v266.250: Verificación de Tipo de Bala (Solo aplica slow si la bala coincide)
                if (cfg) {
                    let sAmount = 0;
                    let sDuration = 0;

                    // Buscar la mecánica específica que corresponde a la bala que impactó
                    if (cfg.mechanics) {
                        const matchingMech = cfg.mechanics.find(m => m.type === data.bulletType);
                        if (matchingMech) {
                            sAmount = matchingMech.slowAmount || 0;
                            sDuration = matchingMech.slowDuration || 0;
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
