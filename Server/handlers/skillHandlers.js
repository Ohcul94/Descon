const User = require('../models/User');
const { getPlayerRAMAdapter } = require('../utils/ramAdapter'); // v6.02
const Logger = require('../utils/logger');

function registerSkillHandlers(socket, io, state) {
    const { players } = state;
    const CONFIG_FILE = require('path').join(__dirname, '../config.json');
    const fs = require('fs-extra');

    // SISTEMA DE TALENTOS (v300.70)
    socket.on('investSkill', async (data) => {
        if (!socket.dbUser || !players[socket.id] || !data) return;
        
        const cat = data.category;
        const idx = parseInt(data.index);
        
        // Blindaje de Seguridad v314.0: Validar categoría e índice
        const validCategories = ["engineering", "combat", "science"];
        if (!validCategories.includes(cat) || isNaN(idx) || idx < 0 || idx > 7) {
            console.warn(`[SECURITY-ALERT] Intento de inyección de talento inválido por parte de: ${players[socket.id].user} (Categoría: ${cat}, Índice: ${data.index})`);
            return socket.emit('gameNotification', { msg: 'ACCIÓN DENEGADA: Parámetros de talento corruptos.', type: 'error' });
        }

        try {
            const user = getPlayerRAMAdapter(players[socket.id]);
            if (!user) return;
            
            let pts = user.gameData.skillPoints || 0;
            if (pts <= 0) return;
            
            // v600.0: Validar desbloqueo de talento (si está en talentsLockedConfig)
            const lockedConfig = (state.SERVER_CONFIG && Array.isArray(state.SERVER_CONFIG.talentsLockedConfig)) ? state.SERVER_CONFIG.talentsLockedConfig : [];
            const lockedEntry = lockedConfig.find(t => String(t.category) === cat && Number(t.index) === idx);
            if (lockedEntry) {
                const unlocks = (user.gameData.unlocks && Array.isArray(user.gameData.unlocks)) ? user.gameData.unlocks : [];
                const unlockKey = 'talent:' + cat + ':' + idx;
                if (!unlocks.includes(unlockKey)) {
                    return socket.emit('gameNotification', { msg: `🔒 TALENTO BLOQUEADO: ${lockedEntry.name || 'Este talento'} está sellado. Desbloquéalo completando su misión.`, type: 'error' });
                }
            }
            
            if (!user.gameData.skillTree) user.gameData.skillTree = { engineering: [0,0,0,0,0,0,0,0], combat: [0,0,0,0,0,0,0,0], science: [0,0,0,0,0,0,0,0] };
            
            const branch = user.gameData.skillTree[cat] || [];
            
            // Autocompletado seguro del array de talento (tamaño fijo 8)
            while (branch.length < 8) branch.push(0);
            
            if (branch[idx] >= 5) return;
            
            branch[idx] += 1;
            user.gameData.skillTree[cat] = branch;
            user.gameData.skillPoints = pts - 1;
            
            // v300.75: Triple validación de guardado
            user.markModified('gameData.skillTree');
            user.markModified('gameData.skillPoints');
            user.markModified('gameData');
            
            // v300.90: ¡ACTUALIZAR RAM!
            players[socket.id].skillTree = user.gameData.skillTree;
            players[socket.id].skillPoints = user.gameData.skillPoints;
            
            await user.save();
            Logger.debug('DATABASE', `Talento '${cat}' [${idx}] guardado para ${user.username}. Restantes: ${user.gameData.skillPoints}`);
            
            socket.dbUser = user;
            
            const eByShipObj = {};
            if (user.gameData.equippedByShip) {
                if (user.gameData.equippedByShip instanceof Map) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                } else {
                    Object.assign(eByShipObj, user.gameData.equippedByShip);
                }
            }
            
            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj }
            });
        } catch(e) { Logger.error('TALENT', e.message); }
    });

    socket.on('resetSkills', async () => {
        if (!socket.dbUser || !players[socket.id]) return;
        try {
            const user = getPlayerRAMAdapter(players[socket.id]);
            if (!user) return;
            
            const RESET_COST = 5000;
            if ((user.gameData.ohcu || 0) < RESET_COST) {
                return socket.emit('gameNotification', { msg: 'OHCU INSUFICIENTE PARA RESETEAR', type: 'error' });
            }
            
            let spent = 0;
            const tree = user.gameData.skillTree || { engineering: [], combat: [], science: [] };
            
            ['engineering', 'combat', 'science'].forEach(cat => {
                if (tree[cat] && Array.isArray(tree[cat])) {
                    tree[cat].forEach(lvl => { spent += lvl; });
                }
                tree[cat] = [0,0,0,0,0,0,0,0];
            });
            
            if (spent === 0) return socket.emit('gameNotification', { msg: 'NO HAY HABILIDADES PARA RESETEAR', type: 'error' });
            
            user.gameData.ohcu -= RESET_COST;
            user.gameData.skillPoints = (user.gameData.skillPoints || 0) + spent;
            user.gameData.skillTree = tree;
            
            user.markModified('gameData');
            
            // v300.90: ¡ACTUALIZAR RAM! 
            players[socket.id].skillTree = user.gameData.skillTree;
            players[socket.id].skillPoints = user.gameData.skillPoints;
            players[socket.id].ohcu = user.gameData.ohcu;
            
            await user.save();
            Logger.debug('DATABASE', `Árbol de habilidades reseteado para ${user.username}. Puntos devueltos: ${spent}`);
            
            socket.dbUser = user;
            
            const eByShipObj = {};
            if (user.gameData.equippedByShip) {
                if (user.gameData.equippedByShip instanceof Map) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                } else {
                    Object.assign(eByShipObj, user.gameData.equippedByShip);
                }
            }
            
            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj }
            });
            socket.emit('gameNotification', { msg: 'ÁRBOL DE HABILIDADES RESETEADO', type: 'success' });
            
        } catch(e) { Logger.error('SKILL-RESET', e.message); }
    });
}

module.exports = { registerSkillHandlers };
