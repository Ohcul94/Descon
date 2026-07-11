/**
 * rankingHandlers.js
 * Sistema de Clasificación / Ranking - Tracking, cálculo y administración.
 */

async function addRankingKill(userId, enemyType, rankingPoints, state) {
    if (!rankingPoints || rankingPoints <= 0) return;
    try {
        const User = require('mongoose').model('User');
        const user = await User.findById(userId);
        if (!user) return;

        if (!user.gameData.rankingData) {
            user.gameData.rankingData = { monsters_killed: 0, events_completed: 0 };
        }

        user.gameData.rankingData.monsters_killed = (user.gameData.rankingData.monsters_killed || 0) + rankingPoints;
        user.markModified('gameData.rankingData');

        // Cache en memoria para cálculos rápidos
        if (!state.rankingCache) state.rankingCache = {};
        if (!state.rankingCache[userId]) state.rankingCache[userId] = { monsters_killed: 0, events_completed: 0 };
        state.rankingCache[userId].monsters_killed = (state.rankingCache[userId].monsters_killed || 0) + rankingPoints;

        await user.save();
    } catch (err) {
        console.error('[RANKING] Error al sumar puntos de kill:', err.message);
    }
}

async function addRankingEvent(userId, state) {
    try {
        const User = require('mongoose').model('User');
        const user = await User.findById(userId);
        if (!user) return;

        if (!user.gameData.rankingData) {
            user.gameData.rankingData = { monsters_killed: 0, events_completed: 0 };
        }

        user.gameData.rankingData.events_completed = (user.gameData.rankingData.events_completed || 0) + 1;
        user.markModified('gameData.rankingData');

        if (!state.rankingCache) state.rankingCache = {};
        if (!state.rankingCache[userId]) state.rankingCache[userId] = { monsters_killed: 0, events_completed: 0 };
        state.rankingCache[userId].events_completed = (state.rankingCache[userId].events_completed || 0) + 1;

        await user.save();
    } catch (err) {
        console.error('[RANKING] Error al sumar evento:', err.message);
    }
}

async function calculateRankings(category, state, limit = 10) {
    try {
        const User = require('mongoose').model('User');

        let sortField = 'gameData.rankingData.' + category;
        if (category === 'level') {
            sortField = 'gameData.level';
        }

        const projection = {
            username: 1,
            'gameData.level': 1,
            'gameData.rankingData': 1
        };

        const users = await User.find({}, projection)
            .sort({ [sortField]: -1 })
            .limit(limit)
            .lean();

        return users.map((u, idx) => {
            let points = 0;
            if (category === 'level') {
                points = u.gameData?.level || 0;
            } else if (category === 'monsters_killed') {
                points = u.gameData?.rankingData?.monsters_killed || 0;
            } else if (category === 'events_completed') {
                points = u.gameData?.rankingData?.events_completed || 0;
            } else {
                points = u.gameData?.rankingData?.[category] || 0;
            }

            return {
                rank: idx + 1,
                username: u.username,
                points: points,
                level: u.gameData?.level || 1
            };
        });
    } catch (err) {
        console.error('[RANKING] Error al calcular ranking:', err.message);
        return [];
    }
}

async function distributeRewardsForCategory(category, state, io) {
    try {
        const rankingCfg = state.SERVER_CONFIG?.rankingConfig;
        if (!rankingCfg || !rankingCfg.categories) return;

        const catConfig = rankingCfg.categories.find(c => c.id === category);
        if (!catConfig || !catConfig.rewards || catConfig.rewards.length === 0) return;

        const rankings = await calculateRankings(category, state, catConfig.rewards.length);
        const User = require('mongoose').model('User');

        for (const entry of rankings) {
            const rewardConfig = catConfig.rewards.find(r => r.rank === entry.rank);
            if (!rewardConfig) continue;

            const user = await User.findOne({ username: entry.username });
            if (!user) continue;

            // Aplicar recompensas
            if (rewardConfig.hubs) user.gameData.hubs = (user.gameData.hubs || 0) + rewardConfig.hubs;
            if (rewardConfig.ohcu) user.gameData.ohcu = (user.gameData.ohcu || 0) + rewardConfig.ohcu;
            if (rewardConfig.exp) user.gameData.exp = (user.gameData.exp || 0) + rewardConfig.exp;

            // Items
            if (rewardConfig.items && rewardConfig.items.length > 0) {
                for (const item of rewardConfig.items) {
                    if (item.id && item.qty) {
                        for (let i = 0; i < item.qty; i++) {
                            user.gameData.inventory.push({ id: item.id });
                        }
                    }
                }
            }

            // Battle Pass EXP
            if (rewardConfig.bpExp) {
                try {
                    const { awardBattlePassExpServer } = require('./battlePassHandlers');
                    await awardBattlePassExpServer(user, rewardConfig.bpExp, state);
                } catch (bpErr) {
                    console.error('[RANKING] Error al dar BP exp:', bpErr.message);
                }
            }

            user.markModified('gameData');

            // Sincronizar stats en memoria si el jugador está online
            const playerSocketId = Object.keys(state.players).find(k => state.players[k]?.id === user._id.toString());
            if (playerSocketId) {
                const p = state.players[playerSocketId];
                if (p) {
                    p.hubs = user.gameData.hubs;
                    p.ohcu = user.gameData.ohcu;
                    p.exp = user.gameData.exp;
                }
                const sock = io.sockets.sockets.get(playerSocketId);
                if (sock) {
                    sock.emit('gameNotification', {
                        msg: `🏆 ¡Has quedado #${entry.rank} en "${catConfig.name}"! Recompensa entregada.`,
                        type: 'success'
                    });
                    sock.emit('inventoryData', { player: user.gameData });
                }
            }

            await user.save();
        }

        // Resetear puntajes después de distribuir
        await resetCategoryScores(category, state);

        console.log(`[RANKING] Recompensas distribuidas para categoría "${category}".`);
    } catch (err) {
        console.error('[RANKING] Error al distribuir rewards:', err.message);
    }
}

async function resetCategoryScores(category, state) {
    try {
        const User = require('mongoose').model('User');

        if (category === 'level') return; // Level nunca se resetea

        const resetField = 'gameData.rankingData.' + category;
        await User.updateMany({}, { $set: { [resetField]: 0 } });

        // Limpiar caché
        if (state.rankingCache) {
            for (const uid of Object.keys(state.rankingCache)) {
                if (state.rankingCache[uid][category] !== undefined) {
                    state.rankingCache[uid][category] = 0;
                }
            }
        }

        console.log(`[RANKING] Puntajes de "${category}" reseteados.`);
    } catch (err) {
        console.error('[RANKING] Error al resetear scores:', err.message);
    }
}

function registerRankingHandlers(socket, io, state) {
    // Inicializar caché de ranking si no existe
    if (!state.rankingCache) {
        state.rankingCache = {};
    }
    if (!state.rankingTimers) {
        state.rankingTimers = {};
    }

    // Admin: Obtener datos de ranking
    socket.on('getRankings', async (data) => {
        try {
            const category = data?.category || 'monsters_killed';
            const rankings = await calculateRankings(category, state, 10);
            socket.emit('rankingsData', { category, rankings });
        } catch (err) {
            console.error('[RANKING] Error en getRankings:', err.message);
            socket.emit('rankingsData', { category: data?.category, rankings: [] });
        }
    });

    // Admin: Resetear ranking manualmente (con distribución de rewards)
    socket.on('adminResetRanking', async (data) => {
        if (!socket.dbUser || socket.dbUser.username.toLowerCase() !== "caelli94") {
            return socket.emit('gameNotification', { msg: 'ACCESO DENEGADO.', type: 'error' });
        }

        const category = data?.category;
        if (!category) {
            return socket.emit('gameNotification', { msg: 'Especificá una categoría.', type: 'error' });
        }

        try {
            await distributeRewardsForCategory(category, state, io);
            socket.emit('gameNotification', {
                msg: `🏆 Ranking "${category}" reseteado y recompensas distribuidas.`,
                type: 'success'
            });
        } catch (err) {
            console.error('[RANKING] Error en reset admin:', err.message);
            socket.emit('gameNotification', { msg: 'Error al resetear ranking.', type: 'error' });
        }
    });
}

module.exports = {
    registerRankingHandlers,
    addRankingKill,
    addRankingEvent,
    calculateRankings,
    distributeRewardsForCategory,
    resetCategoryScores
};