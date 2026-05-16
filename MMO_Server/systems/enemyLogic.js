/**
 * enemyLogic.js
 * Lógica compartida para procesamiento de muertes, explosiones y loot de enemigos.
 */
const User = require('../models/User');

function executeEnemyExplosion(enemy, io, state) {
    const cfg = state.SERVER_CONFIG && state.SERVER_CONFIG.enemyModels ? state.SERVER_CONFIG.enemyModels[enemy.type] : null;
    if (!cfg) return;

    const kamikazePhase = (cfg.movementPhases || []).find(p => p.type === 'kamikaze');
    if (!kamikazePhase) return;

    const damage = kamikazePhase.explosionDamage || 500;
    const radius = 250;

    io.to(`zone_${enemy.zone}`).emit('enemyExploded', {
        id: enemy.id,
        x: enemy.x, y: enemy.y,
        damage: damage, radius: radius
    });

    Object.values(state.players).forEach(p => {
        if (p.zone !== enemy.zone || p.isDead) return;
        const dist = Math.hypot(p.x - enemy.x, p.y - enemy.y);
        if (dist <= radius) {
            if (p.shield >= damage) p.shield -= damage;
            else { p.hp -= (damage - p.shield); p.shield = 0; }
            if (p.hp <= 0) { p.hp = 0; p.isDead = true; }
            p.lastCombatTime = Date.now();
            io.to(`zone_${p.zone}`).emit('playerStatSync', { 
                id: p.socketId, hp: Math.max(0, p.hp), shield: p.shield, 
                maxHp: p.maxHp, maxShield: p.maxShield, isDead: p.isDead
            });
            io.to(p.socketId).emit('environmentDamage', { damage: damage });
        }
    });
}

async function handleEnemyDeath(enemyId, io, state, killerSocketId = null) {
    const enemy = state.enemies[enemyId];
    if (!enemy || enemy.isDeadProcessed) return;
    
    enemy.isDying = true;
    enemy.isDeadProcessed = true;
    
    const cfg = state.SERVER_CONFIG && state.SERVER_CONFIG.enemyModels ? state.SERVER_CONFIG.enemyModels[enemy.type] : {};

    // Explosión Kamikaze
    const kamikazePhase = (cfg.movementPhases || []).find(p => p.type === 'kamikaze');
    if (kamikazePhase) {
        if (enemy.forceExplosion || kamikazePhase.explodeOnDeath) {
            executeEnemyExplosion(enemy, io, state);
        }
    }

    let h_loot = (cfg.rewardHubs !== undefined) ? cfg.rewardHubs : (enemy.type * 500);
    let o_loot = (cfg.rewardOhcu !== undefined) ? cfg.rewardOhcu : (enemy.type * 10);
    let e_loot = (cfg.rewardExp !== undefined) ? cfg.rewardExp : (enemy.type * 100);

    if (enemy.name && enemy.name.toUpperCase().includes("CLONE")) {
        h_loot = 0; o_loot = 0; e_loot = 0;
    }

    io.to(`zone_${enemy.zone}`).emit('enemyDead', { id: enemyId, killer: killerSocketId });

    // REPARTO DE LOOT COOPERATIVO (Portado de combatHandlers.js)
    try {
        const killer = killerSocketId ? state.players[killerSocketId] : null;
        if (!killer || !killerSocketId) {
            delete state.enemies[enemyId];
            return;
        }

        const killerUid = killer.db_id;
        let membersToRewardSockets = [];
        
        // Buscar el socket real de killer para emitir
        const killerSocket = io.sockets.sockets.get(killerSocketId);
        if (killerSocket) membersToRewardSockets.push(killerSocket);

        const partyId = state.playerParty[killerUid];
        if (partyId && state.parties[partyId]) {
            for (const mUid of state.parties[partyId].members) {
                const mUidStr = mUid.toString();
                if (mUidStr === killerUid) continue; 
                
                let sid = state.activeSessions.get(mUidStr);
                if (sid) {
                    const s = io.sockets.sockets.get(sid);
                    if (s && state.players[s.id]) {
                        const pM = state.players[s.id];
                        const distToE = Math.hypot(pM.x - enemy.x, pM.y - enemy.y);
                        if (pM.zone === enemy.zone && distToE <= 2500) membersToRewardSockets.push(s);
                    }
                }
            }
        }

        const shareCount = membersToRewardSockets.length;
        const shared_h = Math.floor(h_loot / shareCount);
        const shared_o = Math.floor(o_loot / shareCount);
        const shared_e = Math.floor(e_loot / shareCount);

        for (const memberSocket of membersToRewardSockets) {
            const memP = state.players[memberSocket.id];
            const user = await User.findOne({ id: memP.db_id });
            
            if (user && memP) {
                user.gameData.hubs += shared_h;
                user.gameData.ohcu += shared_o;
                user.gameData.exp += shared_e;

                memberSocket.emit('enemyKillSession', { hubs: shared_h, ohcu: shared_o, exp: shared_e, killer: killerSocketId });

                const getExpReq = (lvl) => {
                    if (state.SERVER_CONFIG?.pilotConfig?.expRequirements) {
                        const reqs = state.SERVER_CONFIG.pilotConfig.expRequirements;
                        return reqs[lvl - 1] || Math.floor(1000 * Math.pow(lvl, 1.5));
                    }
                    return Math.floor(1000 * Math.pow(lvl, 1.5));
                };

                let nextLevelExp = getExpReq(user.gameData.level);
                while (user.gameData.exp >= nextLevelExp && user.gameData.level < 100) {
                    user.gameData.exp -= nextLevelExp;
                    user.gameData.level++;
                    user.gameData.skillPoints++;
                    memberSocket.emit('gameNotification', { msg: `NIVEL ${user.gameData.level} ALCANZADO!`, type: 'success' });
                    nextLevelExp = getExpReq(user.gameData.level);
                }

                memP.hubs = user.gameData.hubs;
                memP.ohcu = user.gameData.ohcu;
                memP.exp = user.gameData.exp;
                memP.level = user.gameData.level;
                memP.skillPoints = user.gameData.skillPoints;

                await user.save();
                memberSocket.emit('inventoryData', { player: user.gameData });
            }
        }
    } catch (err) {
        console.error("[LOOT-ERR] Error en reparto de loot compartido:", err);
    }

    delete state.enemies[enemyId];
    if (enemy.type === 4) state.lastTitanDeath = Date.now();
}

module.exports = {
    executeEnemyExplosion,
    handleEnemyDeath
};
