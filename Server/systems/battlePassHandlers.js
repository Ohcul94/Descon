function registerBattlePassHandlers(socket, io, state) {

    socket.on('getBattlePassState', async () => {
        try {
            const User = require('mongoose').model('User');
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const bpData = user.gameData.battlePass || {
                level: 1, exp: 0, isVip: false,
                vipActiveUntil: null,
                claimedFree: [], claimedVip: [],
                lastDailyClaim: null
            };

            const config = state.SERVER_CONFIG;
            const battlePassConfig = (config && config.battlePassConfig) ? config.battlePassConfig : null;

            socket.emit('battlePassState', {
                battlePass: bpData,
                config: battlePassConfig
            });
        } catch (err) {
            console.error('[BATTLEPASS] Error al obtener estado:', err);
        }
    });

    socket.on('claimBattlePassReward', async (data) => {
        try {
            const User = require('mongoose').model('User');
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const level = parseInt(data.level);
            const track = data.track;
            const bpConfig = state.SERVER_CONFIG && state.SERVER_CONFIG.battlePassConfig;
            if (!bpConfig || !bpConfig.levels) return;

            const levelConfig = bpConfig.levels.find(l => l.level === level);
            if (!levelConfig) {
                return socket.emit('gameNotification', { msg: 'Nivel no encontrado en la configuración del Pase de Batalla.', type: 'error' });
            }

            let bp = user.gameData.battlePass || {};
            if (!bp.claimedFree) bp.claimedFree = [];
            if (!bp.claimedVip) bp.claimedVip = [];

            if (track === 'free') {
                if (bp.claimedFree.includes(level)) {
                    return socket.emit('gameNotification', { msg: 'Ya reclamaste esta recompensa gratuita.', type: 'error' });
                }
                if (bp.level < level) {
                    return socket.emit('gameNotification', { msg: 'No has alcanzado este nivel aún.', type: 'error' });
                }
                const reward = levelConfig.freeReward;
                if (reward) {
                    await applyReward(user, reward, socket, bpConfig);
                    bp.claimedFree.push(level);
                }
            } else if (track === 'vip') {
                if (!bp.isVip) {
                    return socket.emit('gameNotification', { msg: 'No tienes el Pase VIP activo.', type: 'error' });
                }
                if (bp.claimedVip.includes(level)) {
                    return socket.emit('gameNotification', { msg: 'Ya reclamaste esta recompensa VIP.', type: 'error' });
                }
                if (bp.level < level) {
                    return socket.emit('gameNotification', { msg: 'No has alcanzado este nivel aún.', type: 'error' });
                }
                const reward = levelConfig.vipReward;
                if (reward) {
                    await applyReward(user, reward, socket, bpConfig);
                    bp.claimedVip.push(level);
                }
            }

            user.gameData.battlePass = bp;
            await user.save();

            socket.emit('battlePassState', {
                battlePass: bp,
                config: bpConfig
            });
        } catch (err) {
            console.error('[BATTLEPASS] Error al reclamar:', err);
        }
    });

    socket.on('buyBattlePassVip', async () => {
        try {
            const User = require('mongoose').model('User');
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const bpConfig = state.SERVER_CONFIG && state.SERVER_CONFIG.battlePassConfig;
            if (!bpConfig) return;

            let bp = user.gameData.battlePass || {};
            if (bp.isVip) {
                return socket.emit('gameNotification', { msg: 'Ya tienes el Pase VIP activo.', type: 'info' });
            }

            const costHubs = bpConfig.vipCostHubs || 50000;
            const costOhcu = bpConfig.vipCostOhcu || 200;

            if ((user.gameData.hubs || 0) < costHubs) {
                return socket.emit('gameNotification', { msg: `No tienes suficientes Hubs. Necesitas ${costHubs} Hubs.`, type: 'error' });
            }
            if ((user.gameData.ohcu || 0) < costOhcu) {
                return socket.emit('gameNotification', { msg: `No tienes suficientes Ohcu. Necesitas ${costOhcu} Ohcu.`, type: 'error' });
            }

            user.gameData.hubs -= costHubs;
            user.gameData.ohcu -= costOhcu;

            const durationMs = (bpConfig.seasonDurationDays || 30) * 24 * 60 * 60 * 1000;
            bp.isVip = true;
            bp.vipActiveUntil = new Date(Date.now() + durationMs);

            user.gameData.battlePass = bp;
            await user.save();

            socket.emit('gameNotification', { msg: '🎉 ¡Pase de Batalla VIP adquirido! Disfrutá de las recompensas exclusivas.', type: 'success' });
            socket.emit('battlePassState', {
                battlePass: bp,
                config: bpConfig
            });
            socket.emit('walletData', { hubs: user.gameData.hubs, ohcu: user.gameData.ohcu });
        } catch (err) {
            console.error('[BATTLEPASS] Error al comprar VIP:', err);
        }
    });

    socket.on('addBattlePassExp', async (data) => {
        try {
            const User = require('mongoose').model('User');
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const amount = parseInt(data.amount) || 0;
            if (amount <= 0) return;

            const bpConfig = state.SERVER_CONFIG && state.SERVER_CONFIG.battlePassConfig;
            if (!bpConfig || !bpConfig.levels) return;

            let bp = user.gameData.battlePass || {};
            if (!bp.level) bp.level = 1;
            if (!bp.exp) bp.exp = 0;

            bp.exp += amount;

            const maxLevel = bpConfig.maxLevel || 50;
            let leveledUp = false;
            while (bp.level < maxLevel) {
                const levelConfig = bpConfig.levels.find(l => l.level === bp.level);
                if (!levelConfig) break;
                const required = levelConfig.expRequired || 2000;
                if (bp.exp >= required) {
                    bp.exp -= required;
                    bp.level++;
                    leveledUp = true;
                } else {
                    break;
                }
            }

            if (bp.level >= maxLevel) {
                bp.exp = 0;
            }

            user.gameData.battlePass = bp;
            await user.save();

            if (leveledUp) {
                socket.emit('gameNotification', { msg: `🎖️ ¡Subiste al Nivel ${bp.level} del Pase de Batalla!`, type: 'success' });
            }

            socket.emit('battlePassState', {
                battlePass: bp,
                config: bpConfig
            });
        } catch (err) {
            console.error('[BATTLEPASS] Error al añadir EXP:', err);
        }
    });
}

async function applyReward(user, reward, socket, bpConfig) {
    if (!reward || !user) return;

    if (reward.hubs) {
        user.gameData.hubs = (user.gameData.hubs || 0) + reward.hubs;
    }
    if (reward.ohcu) {
        user.gameData.ohcu = (user.gameData.ohcu || 0) + reward.ohcu;
    }
    if (reward.exp) {
        let bp = user.gameData.battlePass || {};
        bp.exp = (bp.exp || 0) + reward.exp;
    }
    if (reward.itemName) {
        if (!user.gameData.inventory) user.gameData.inventory = [];
        user.gameData.inventory.push({
            id: reward.itemName,
            name: reward.itemName,
            type: 'battlepass',
            base: 1,
            amount: reward.itemAmount || 1,
            rarity: 'unique'
        });
    }
    if (reward.shipId && reward.shipId > 0) {
        if (!user.gameData.ownedShips) user.gameData.ownedShips = [1];
        if (!user.gameData.ownedShips.includes(reward.shipId)) {
            user.gameData.ownedShips.push(reward.shipId);
        }
    }
    if (reward.isPremium) {
        let bp = user.gameData.battlePass || {};
        const durationMs = (bpConfig && bpConfig.seasonDurationDays || 30) * 24 * 60 * 60 * 1000;
        bp.isVip = true;
        bp.vipActiveUntil = new Date(Date.now() + durationMs);
        user.gameData.battlePass = bp;
    }

    socket.emit('walletData', { hubs: user.gameData.hubs, ohcu: user.gameData.ohcu });
}

async function awardBattlePassExpServer(user, amount, state) {
    if (!user || !amount || amount <= 0) return { leveledUp: false };

    const bpConfig = state.SERVER_CONFIG && state.SERVER_CONFIG.battlePassConfig;
    if (!bpConfig || !bpConfig.levels) return { leveledUp: false };

    let bp = user.gameData.battlePass || {};
    if (!bp.level) bp.level = 1;
    if (!bp.exp) bp.exp = 0;
    if (!bp.claimedFree) bp.claimedFree = [];
    if (!bp.claimedVip) bp.claimedVip = [];

    bp.exp += amount;

    const maxLevel = bpConfig.maxLevel || 50;
    let leveledUp = false;
    while (bp.level < maxLevel) {
        const levelConfig = bpConfig.levels.find(l => l.level === bp.level);
        if (!levelConfig) break;
        const required = levelConfig.expRequired || 2000;
        if (bp.exp >= required) {
            bp.exp -= required;
            bp.level++;
            leveledUp = true;
        } else {
            break;
        }
    }

    if (bp.level >= maxLevel) bp.exp = 0;

    user.gameData.battlePass = bp;
    return { leveledUp, newLevel: bp.level };
}

module.exports = { registerBattlePassHandlers, awardBattlePassExpServer };
