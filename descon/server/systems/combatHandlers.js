const User = require('../models/User');

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

        const ammoType = fireData.ammoType || 'laser';
        const ammoTier = fireData.ammoTier || 0;
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
            rotation: fireData.rotation,
            ammoType: ammoType,
            ammoTier: ammoTier,
            targetId: fireData.targetId
        };

        socket.to(`zone_${p.zone}`).emit('remotePlayerFired', pData);
    });

    // SISTEMA DE HABILIDADES DE ESFERAS (Soporte Polimórfico v262.10)
    socket.on('playerSphereSkill', (data) => {
        const p = state.players[socket.id];
        if (!p || p.isDead || !state.SERVER_CONFIG) return;

        const sphereIdx = data.sphereIdx;
        if (sphereIdx < 0 || sphereIdx > 3) return;

        const now = Date.now();
        if (!p.sphereCooldowns) p.sphereCooldowns = [0, 0, 0, 0];
        const lastUse = p.sphereCooldowns[sphereIdx] || 0;
        
        const cd_sec = (state.SERVER_CONFIG.skillsData && state.SERVER_CONFIG.skillsData[data.skillName]) ? state.SERVER_CONFIG.skillsData[data.skillName].cd : 10;
        if (now - lastUse < (cd_sec * 1000)) return;

        const powerValue = data.powerValue || 0;
        if (powerValue <= 0 && data.skillName !== "SMOKE-BOMB" && data.skillName !== "STEALTH" && data.skillName !== "FROST-TRAIL") return; 

        let skillConfig = (state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData[data.skillName] : null;
        
        const fallbacks = {
            "ESCUDO CELULAR": { canTargetOthers: true, targetFilters: { allies: true, enemies: false, bosses: false, players: true } },
            "FORTALEZA-X": { canTargetOthers: true, targetFilters: { allies: true, enemies: false, bosses: false, players: true } },
            "AUTO-REPARACIÓN": { canTargetOthers: true, targetFilters: { allies: true, enemies: false, bosses: false, players: true } },
            "NANO-REGENERACIÓN": { canTargetOthers: true, targetFilters: { allies: true, enemies: false, bosses: false, players: true } },
            "TURBO-IMPULSO": { canTargetOthers: true, targetFilters: { allies: true, enemies: false, bosses: false, players: true } },
            "PLASMA BLAST": { canTargetOthers: true, targetFilters: { allies: false, enemies: true, bosses: true, players: true } }
        };
        
        if (fallbacks[data.skillName]) {
            if (!skillConfig) skillConfig = {};
            skillConfig.canTargetOthers = fallbacks[data.skillName].canTargetOthers;
            skillConfig.targetFilters = fallbacks[data.skillName].targetFilters;
        }

        let target = p; 
        let isRemote = false;

        if (skillConfig && skillConfig.canTargetOthers) {
            if (!data.targetId) return;

            const targetPlayer = state.players[data.targetId];
            const targetEnemy = state.enemies[data.targetId];
            const potentialTarget = targetPlayer || targetEnemy;

            if (!potentialTarget || potentialTarget.hp <= 0) return;

            if (data.targetId !== socket.id && skillConfig.range && skillConfig.range > 0) {
                const dx = p.x - potentialTarget.x;
                const dy = p.y - potentialTarget.y;
                const dist = Math.sqrt(dx * dx + dy * dy);
                if (dist > skillConfig.range + 50) {
                    return; 
                }
            }

            if (data.targetId === socket.id) {
                target = p;
            } else {
                const filters = skillConfig.targetFilters || { allies: true, enemies: false, bosses: false, players: true };
                let isValid = false;

                if (targetPlayer) {
                    const sameClan = (p.clanId && targetPlayer.clanId && p.clanId.toString() === targetPlayer.clanId.toString());
                    const isAlly = sameClan || (!p.pvpEnabled && !targetPlayer.pvpEnabled);
                    const isEnemy = !sameClan && (p.pvpEnabled || targetPlayer.pvpEnabled);
                    
                    if (isAlly && filters.allies) isValid = true;
                    else if (isEnemy && (filters.enemies || filters.players)) isValid = true;
                    else if (!isAlly && !isEnemy && filters.players) isValid = true;
                } else if (targetEnemy) {
                    const isBoss = targetEnemy.type === 4 || targetEnemy.type === 10 || targetEnemy.type === 11;
                    if (isBoss && filters.bosses) isValid = true;
                    else if (!isBoss && filters.enemies) isValid = true;
                }

                if (isValid) {
                    target = potentialTarget;
                    isRemote = true;
                } else {
                    return; 
                }
            }
        }

        p.sphereCooldowns[sphereIdx] = now; 
        let actual_val = powerValue;

        if (data.skillName === "ESCUDO CELULAR" || data.skillName === "FORTALEZA-X") {
            const ms = target.maxShield || 2000;
            const oldS = target.shield || 0;
            target.shield = Math.min(oldS + powerValue, ms);
            actual_val = target.shield - oldS;
        } else if (data.skillName === "AUTO-REPARACIÓN" || data.skillName === "NANO-REGENERACIÓN") {
            const mh = target.maxHp || 3000;
            const oldH = target.hp || 0;
            target.hp = Math.min(oldH + powerValue, mh);
            actual_val = target.hp - oldH;
        } else if (data.skillName === "PLASMA BLAST") {
            if (target !== p) {
                const oldH = target.hp || 0;
                target.hp -= powerValue;
                if (target.hp < 0) target.hp = 0;
                actual_val = oldH - target.hp;
            }
        } else if (data.skillName === "SMOKE-BOMB") {
            const areaId = `area_${state.nextAreaId++}`;
            const config = (state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData["SMOKE-BOMB"] : { duration: 6, radius: 180 };
            
            state.activeAreas[areaId] = {
                id: areaId,
                x: p.x,
                y: p.y,
                radius: config.radius || 180,
                type: 'SMOKE',
                ownerId: socket.id,
                endTime: Date.now() + (config.duration * 1000),
                zone: p.zone
            };
            
            io.to(`zone_${p.zone}`).emit('spawnArea', state.activeAreas[areaId]);
        } else if (data.skillName === "STEALTH") {
            const config = (state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData["STEALTH"] : { duration: 8 };
            const duration = (config.duration || 8) * 1000;
            
            p.isInvisible = true;
            socket.emit('gameNotification', { msg: "┬íSIGILO ACTIVADO!", type: "info" });
            
            setTimeout(() => {
                const currentPlayer = state.players[socket.id];
                if (currentPlayer) {
                    currentPlayer.isInvisible = false;
                    io.to(`zone_${currentPlayer.zone}`).emit('remoteStatSync', {
                        id: socket.id,
                        isInvisible: false
                    });
                }
            }, duration);
            
            p.hasStealthTimer = true; 
            io.to(`zone_${p.zone}`).emit('remoteStatSync', { id: socket.id, isInvisible: true });
        } else if (data.skillName === "FROST-TRAIL") {
            const config = (state.SERVER_CONFIG && state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData["FROST-TRAIL"] : { duration: 6, radius: 120, cd: 12 };
            const duration = (config.duration || 6) * 1000;
            const skillEndTime = Date.now() + duration; 
            
            socket.emit('gameNotification', { msg: "¡ESTELA DE HIELO ACTIVADA!", type: "info" });
            
            let lastX = -9999; // Forzar el primer spawn
            let lastY = -9999;

            const trailInterval = setInterval(() => {
                const currentPlayer = state.players[socket.id];
                if (!currentPlayer || Date.now() >= skillEndTime) {
                    clearInterval(trailInterval);
                    return;
                }
                
                const dist = Math.hypot(currentPlayer.x - lastX, currentPlayer.y - lastY);
                if (dist > 25) {
                    const areaId = `frost_${state.nextAreaId++}`;
                    state.activeAreas[areaId] = {
                        id: areaId,
                        x: currentPlayer.x,
                        y: currentPlayer.y,
                        radius: 35, 
                        type: 'ICE',
                        ownerId: socket.id,
                        slowAmount: config.slow_amount || 0.6,
                        endTime: skillEndTime, // v246.5: Todo el rastro desaparece al terminar el skill
                        zone: currentPlayer.zone
                    };
                    
                    io.to(`zone_${currentPlayer.zone}`).emit('spawnArea', state.activeAreas[areaId]);
                    lastX = currentPlayer.x;
                    lastY = currentPlayer.y;
                }
            }, 100);
        }

        if (target.socketId) {
            target.lastSyncHp = target.hp;
            target.lastSyncSh = target.shield;

            io.to(`zone_${target.zone}`).emit('playerStatSync', {
                id: target.socketId,
                hp: Math.ceil(target.hp),
                shield: Math.ceil(target.shield),
                spheres: target.spheres,
                isDead: target.hp <= 0
            });
        }

        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', {
            id: socket.id,
            skillName: data.skillName,
            powerValue: actual_val,
            targetId: isRemote ? data.targetId : socket.id
        });

        const s_data = (state.SERVER_CONFIG.skillsData) ? state.SERVER_CONFIG.skillsData[data.skillName] || {} : {};
        
        if (data.skillName === "INVULNERABILIDAD") {
            p.isInvulnerable = true;
            const syncData = { id: socket.id, hp: Math.ceil(p.hp), shield: Math.ceil(p.shield), isInvulnerable: true };
            io.to(`zone_${p.zone}`).emit('playerStatSync', syncData);

            const duration = (s_data.duration || 2) * 1000;
            setTimeout(() => {
                p.isInvulnerable = false;
                io.to(`zone_${p.zone}`).emit('playerStatSync', { id: socket.id, isInvulnerable: false });
            }, duration);
        } else if (data.skillName === "BLINK") {
            if (data.pos) {
                p.x = data.pos.x;
                p.y = data.pos.y;
                io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', { 
                    id: socket.id, 
                    skillName: data.skillName, 
                    pos: { x: p.x, y: p.y },
                    targetId: socket.id 
                });
            }
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
            let h_loot = cfg.rewardHubs || (enemy.type * 500);
            let o_loot = cfg.rewardOhcu || (enemy.type * 10);
            let e_loot = cfg.rewardExp || (enemy.type * 100);

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

                        let nextLevelExp = Math.floor(1000 * Math.pow(user.gameData.level, 1.5));
                        while (user.gameData.exp >= nextLevelExp && user.gameData.level < 100) {
                            user.gameData.exp -= nextLevelExp;
                            user.gameData.level++;
                            user.gameData.skillPoints++;
                            memberSocket.emit('gameNotification', { msg: `NIVEL ${user.gameData.level} ALCANZADO!`, type: 'success' });
                            nextLevelExp = Math.floor(1000 * Math.pow(user.gameData.level, 1.5));
                        }

                        user.markModified('gameData');
                        await user.save();

                        memP.hubs = user.gameData.hubs;
                        memP.ohcu = user.gameData.ohcu;
                        memP.exp = user.gameData.exp;
                        memP.level = user.gameData.level;
                        memP.skillPoints = user.gameData.skillPoints;

                        const hpBonus = 1.0 + ((memP.skillTree.engineering[0] || 0) * 0.02);
                        const shBonus = 1.0 + ((memP.skillTree.engineering[1] || 0) * 0.02);
                        memP.maxHp = Math.ceil((memP.baseHp || 2000) * hpBonus);
                        memP.maxShield = Math.ceil((memP.baseShield || 1000) * shBonus);

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
                if (dmg <= 0 || dmg > baseDmg) dmg = baseDmg;
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
