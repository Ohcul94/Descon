/**
 * questHandlers.js
 * Sistema de misiones autoritativo del lado del servidor.
 */
const User = require('../models/User');
const { getPlayerRAMAdapter } = require('../utils/ramAdapter'); // v6.02
const Logger = require('../utils/logger');
const { awardBattlePassExpServer } = require('./battlePassHandlers');
const fs = require('fs-extra');
const path = require('path');

// Helper para obtener los requisitos de EXP por nivel (igual que en enemyLogic.js)
const getExpRequiredForLevel = (lvl, state) => {
    if (state.SERVER_CONFIG?.pilotConfig?.expRequirements) {
        const reqs = state.SERVER_CONFIG.pilotConfig.expRequirements;
        return reqs[lvl - 1] || Math.floor(1000 * Math.pow(lvl, 1.5));
    }
    return Math.floor(1000 * Math.pow(lvl, 1.5));
};

// Verificar y resetear diarias y semanales de forma individual
const checkQuestResets = (p, dbUser) => {
    if (!dbUser.gameData.quests) {
        dbUser.gameData.quests = { active: [], completed: [], lastDailyReset: null, lastWeeklyReset: null };
    }
    const questsState = dbUser.gameData.quests;
    const now = new Date();
    let modified = false;

    // Reset Diario (Cada 24 horas)
    if (!questsState.lastDailyReset) {
        questsState.lastDailyReset = now;
        modified = true;
    } else {
        const diffMs = now - new Date(questsState.lastDailyReset);
        if (diffMs >= 24 * 60 * 60 * 1000) {
            // Eliminar misiones diarias de las completadas
            const questsConfig = p.SERVER_CONFIG?.questsConfig || [];
            const dailyIds = questsConfig.filter(q => q.type === 'daily').map(q => String(q.id));
            
            questsState.completed = questsState.completed.filter(id => !dailyIds.includes(String(id)));
            questsState.lastDailyReset = now;
            modified = true;
            Logger.info('QUESTS', `Reseteadas misiones diarias para el piloto ${dbUser.username}`);
        }
    }

    // Reset Semanal (Cada 7 días)
    if (!questsState.lastWeeklyReset) {
        questsState.lastWeeklyReset = now;
        modified = true;
    } else {
        const diffMs = now - new Date(questsState.lastWeeklyReset);
        if (diffMs >= 7 * 24 * 60 * 60 * 1000) {
            // Eliminar misiones semanales de las completadas
            const questsConfig = p.SERVER_CONFIG?.questsConfig || [];
            const weeklyIds = questsConfig.filter(q => q.type === 'weekly').map(q => String(q.id));
            
            questsState.completed = questsState.completed.filter(id => !weeklyIds.includes(String(id)));
            questsState.lastWeeklyReset = now;
            modified = true;
            Logger.info('QUESTS', `Reseteadas misiones semanales para el piloto ${dbUser.username}`);
        }
    }

    return modified;
};

// Función principal para registrar los manejadores del socket
function registerQuestHandlers(socket, io, state) {
    
    // Obtener estado completo de misiones del jugador
    socket.on('getQuestsState', async () => {
        try {
            const p = state.players[socket.id];
            if (!p) return;

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            let modified = checkQuestResets(state, user);
            if (modified) {
                user.markModified('gameData.quests');
                await user.save();
            }

            socket.emit('questsStateData', {
                active: user.gameData.quests?.active || [],
                completed: user.gameData.quests?.completed || [],
                unlocks: user.gameData.unlocks || []
            });
        } catch (e) {
            Logger.error('QUESTS', `Error en getQuestsState: ${e.message}`);
        }
    });

    // Aceptar misión
    socket.on('acceptQuest', async (data) => {
        try {
            const questId = String(data.questId);
            const p = state.players[socket.id];
            if (!p) return;

            // Misiones solo se pueden aceptar en el Lobby (zona 1)
            if (Number(p.zone) !== 1) {
                return socket.emit('gameNotification', { msg: 'Solo puedes aceptar misiones en el Lobby / Hangar.', type: 'error' });
            }

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            const questsConfig = state.SERVER_CONFIG?.questsConfig || [];
            const questDef = questsConfig.find(q => String(q.id) === questId);

            if (!questDef) {
                return socket.emit('gameNotification', { msg: 'Misión no encontrada en los registros estelares.', type: 'error' });
            }

            if (!user.gameData.quests) {
                user.gameData.quests = { active: [], completed: [], lastDailyReset: null, lastWeeklyReset: null };
            }

            const activeQuests = user.gameData.quests.active || [];
            const completedQuests = user.gameData.quests.completed || [];

            if (activeQuests.some(q => String(q.id) === questId)) {
                return socket.emit('gameNotification', { msg: 'Esta misión ya está activa en tu bitácora.', type: 'error' });
            }

            if (completedQuests.includes(questId)) {
                return socket.emit('gameNotification', { msg: 'Ya completaste esta misión.', type: 'error' });
            }

            // Límite de misiones activas simultáneas
            const maxActive = state.SERVER_CONFIG?.questsGlobalConfig?.maxActiveQuests || 3;
            if (activeQuests.length >= maxActive) {
                return socket.emit('gameNotification', { msg: `Límite alcanzado. Máximo ${maxActive} misiones activas simultáneas.`, type: 'error' });
            }

            // Si es de recolectar ítems, podemos comprobar el progreso inicial inmediatamente
            let initialProgress = 0;
            if (questDef.targetType === 'collect') {
                const inventory = user.gameData.inventory || [];
                const itemQty = inventory.filter(item => String(item.id) === String(questDef.targetId)).length;
                initialProgress = Math.min(itemQty, questDef.targetAmount);
            }

            user.gameData.quests.active.push({
                id: questId,
                progress: initialProgress,
                acceptedAt: new Date()
            });

            user.markModified('gameData.quests');
            await user.save();

            socket.emit('gameNotification', { msg: `Misión aceptada: ${questDef.name}`, type: 'success' });
            
            // Sincronizar estado
            socket.emit('questsStateData', {
                active: user.gameData.quests.active,
                completed: user.gameData.quests.completed,
                unlocks: user.gameData.unlocks || []
            });

        } catch (e) {
            Logger.error('QUESTS', `Error en acceptQuest: ${e.message}`);
        }
    });

    // Cancelar/Abandonar misión (en cualquier lugar)
    socket.on('abandonQuest', async (data) => {
        try {
            const questId = String(data.questId);
            const p = state.players[socket.id];
            if (!p) return;

            const user = getPlayerRAMAdapter(p);
            if (!user || !user.gameData.quests) return;

            const activeIndex = user.gameData.quests.active.findIndex(q => String(q.id) === questId);
            if (activeIndex === -1) {
                return socket.emit('gameNotification', { msg: 'Misión no encontrada en tu bitácora.', type: 'error' });
            }

            user.gameData.quests.active.splice(activeIndex, 1);
            user.markModified('gameData.quests');
            await user.save();

            socket.emit('gameNotification', { msg: 'Misión abandonada.', type: 'warning' });

            // Sincronizar estado
            socket.emit('questsStateData', {
                active: user.gameData.quests.active,
                completed: user.gameData.quests.completed,
                unlocks: user.gameData.unlocks || []
            });

        } catch (e) {
            Logger.error('QUESTS', `Error en abandonQuest: ${e.message}`);
        }
    });

    // Reclamar recompensa de misión
    socket.on('claimQuestReward', async (data) => {
        try {
            const questId = String(data.questId);
            const p = state.players[socket.id];
            if (!p) return;

            const user = getPlayerRAMAdapter(p);
            if (!user) return;

            if (!user.gameData.quests) return;

            const activeIndex = user.gameData.quests.active.findIndex(q => String(q.id) === questId);
            if (activeIndex === -1) {
                return socket.emit('gameNotification', { msg: 'Misión no encontrada o no aceptada.', type: 'error' });
            }

            const activeQuest = user.gameData.quests.active[activeIndex];
            const questsConfig = state.SERVER_CONFIG?.questsConfig || [];
            const questDef = questsConfig.find(q => String(q.id) === questId);

            if (!questDef) {
                return socket.emit('gameNotification', { msg: 'Definición de misión no encontrada.', type: 'error' });
            }

            // Validar progreso de forma autoritativa
            let isCompleted = false;

            if (questDef.targetType === 'kill' || questDef.targetType === 'event') {
                isCompleted = activeQuest.progress >= questDef.targetAmount;
            } else if (questDef.targetType === 'explore') {
                if (questDef.targetX !== undefined && questDef.targetY !== undefined && questDef.targetX !== null && questDef.targetY !== null) {
                    const dist = Math.hypot(p.x - questDef.targetX, p.y - questDef.targetY);
                    if (Number(p.zone) !== Number(questDef.targetId) || dist > 300) {
                        return socket.emit('gameNotification', { msg: 'No estás en el punto de exploración requerido.', type: 'error' });
                    }
                    isCompleted = true;
                } else {
                    isCompleted = activeQuest.progress >= 1;
                }
            } else if (questDef.targetType === 'collect') {
                // Para recolección, contamos los ítems en su inventario físico en el server
                const inventory = user.gameData.inventory || [];
                const itemQty = inventory.filter(item => String(item.id) === String(questDef.targetId)).length;
                isCompleted = itemQty >= questDef.targetAmount;
            } else if (questDef.targetType === 'housing') {
                // Verificar si tiene el objeto colocado en el housing
                const placed = user.gameData.housing ? user.gameData.housing.placedObjects : [];
                isCompleted = Array.isArray(placed) && placed.some(obj => String(obj.id) === String(questDef.targetId));
            }

            if (!isCompleted) {
                return socket.emit('gameNotification', { msg: 'No has cumplido todos los objetivos de la misión.', type: 'error' });
            }

            // vNEW: Validar la selección de recompensa por elección ANTES de otorgar
            // cualquier cosa, para no dejar la misión a medias si la selección es inválida.
            const preReward = questDef.reward || {};
            const prePool = Array.isArray(preReward.items) ? preReward.items : [];
            const preSelCount = parseInt(preReward.selectableCount) || 0;
            if (preSelCount > 0 && preSelCount < prePool.length) {
                const preSelection = Array.isArray(data.selection) ? data.selection : [];
                if (preSelection.length !== preSelCount) {
                    return socket.emit('gameNotification', { msg: `Debes seleccionar exactamente ${preSelCount} ítems de recompensa.`, type: 'error' });
                }
                const preUsed = {};
                for (const s of preSelection) {
                    const i = parseInt(s);
                    if (isNaN(i) || i < 0 || i >= prePool.length || preUsed[i]) {
                        return socket.emit('gameNotification', { msg: 'Selección de recompensa inválida.', type: 'error' });
                    }
                    preUsed[i] = true;
                }
            }

            // Si es de recolección (collect), consumimos los ítems requeridos de su inventario
            if (questDef.targetType === 'collect') {
                let countToRemove = questDef.targetAmount;
                const newInventory = [];
                for (const item of user.gameData.inventory) {
                    if (String(item.id) === String(questDef.targetId) && countToRemove > 0) {
                        countToRemove--;
                    } else {
                        newInventory.push(item);
                    }
                }
                user.gameData.inventory = newInventory;
                user.markModified('gameData.inventory');
                p.inventory = newInventory;
            }

            // Quitar de activa y agregar a completadas
            user.gameData.quests.active.splice(activeIndex, 1);
            if (!user.gameData.quests.completed.includes(questId)) {
                user.gameData.quests.completed.push(questId);
            }

            // Otorgar recompensas
            const reward = questDef.reward || {};
            const expReward = parseInt(reward.exp) || 0;
            const hubsReward = parseInt(reward.hubs) || 0;
            const ohcuReward = parseInt(reward.ohcu) || 0;

            user.gameData.hubs += hubsReward;
            user.gameData.ohcu += ohcuReward;
            user.gameData.exp += expReward;

            const bpXpSources = state.SERVER_CONFIG?.battlePassConfig?.xpSources;
            if (bpXpSources && bpXpSources.questExp) {
                const bpResult = await awardBattlePassExpServer(user, bpXpSources.questExp, state);
                if (bpResult.leveledUp) {
                    socket.emit('gameNotification', { msg: `🎖️ ¡Subiste al Nivel ${bpResult.newLevel} del Pase de Batalla!`, type: 'success' });
                }
            }

            p.hubs = user.gameData.hubs;
            p.ohcu = user.gameData.ohcu;
            p.exp = user.gameData.exp;

            // Procesar subida de nivel si aplica
            let nextLevelExp = getExpRequiredForLevel(user.gameData.level, state);
            while (user.gameData.exp >= nextLevelExp && user.gameData.level < 100) {
                user.gameData.exp -= nextLevelExp;
                user.gameData.level++;
                user.gameData.skillPoints++;
                socket.emit('gameNotification', { msg: `¡NIVEL ${user.gameData.level} ALCANZADO!`, type: 'success' });
                nextLevelExp = getExpRequiredForLevel(user.gameData.level, state);
            }

            p.level = user.gameData.level;
            p.skillPoints = user.gameData.skillPoints;

            // v600.0: Otorgar desbloqueos de recompensa (🔓 portales, objetos, habilidades, talentos)
            if (Array.isArray(reward.unlocks) && reward.unlocks.length > 0) {
                const unlockSystem = require('./unlockSystem');
                const granted = unlockSystem.grantUnlockRewards(user, reward.unlocks);
                p.unlocks = user.gameData.unlocks || [];
                user.markModified('gameData.unlocks');
                granted.forEach(g => {
                    socket.emit('gameNotification', { msg: `🔓 ¡DESBLOQUEO OBTENIDO: ${g.label}`, type: 'success' });
                });
                if (granted.length > 0) {
                    socket.emit('unlocksUpdated', p.unlocks);
                }
            }

            // Dar ítems de recompensa si tiene
            if (Array.isArray(reward.items) && reward.items.length > 0) {
                if (!user.gameData.inventory) user.gameData.inventory = [];

                // vNEW: Recompensa por elección. Si selectableCount está entre 1 y (items-1),
                // el jugador elige exactamente esa cantidad de ítems del pozo.
                const pool = reward.items;
                const selCount = parseInt(reward.selectableCount) || 0;
                let chosenPool = pool;

                if (selCount > 0 && selCount < pool.length) {
                    const selection = Array.isArray(data.selection) ? data.selection : [];
                    if (selection.length !== selCount) {
                        return socket.emit('gameNotification', { msg: `Debes seleccionar exactamente ${selCount} ítems de recompensa.`, type: 'error' });
                    }
                    const usedIdx = {};
                    for (const s of selection) {
                        const i = parseInt(s);
                        if (isNaN(i) || i < 0 || i >= pool.length || usedIdx[i]) {
                            return socket.emit('gameNotification', { msg: 'Selección de recompensa inválida.', type: 'error' });
                        }
                        usedIdx[i] = true;
                    }
                    chosenPool = selection.map(i => pool[i]);
                }

                // Obtener definición maestra de ítems (shop + municiones) para nombres/iconos
                const allShopItems = [
                    ...(state.SERVER_CONFIG.shopItems.weapons || []),
                    ...(state.SERVER_CONFIG.shopItems.shields || []),
                    ...(state.SERVER_CONFIG.shopItems.engines || []),
                    ...(state.SERVER_CONFIG.shopItems.extra || []),
                    ...(state.SERVER_CONFIG.shopItems.resources || [])
                ];
                const ammoDefs = state.SERVER_CONFIG.shopItems.ammo || {};
                for (const k in ammoDefs) {
                    if (Array.isArray(ammoDefs[k])) allShopItems.push(...ammoDefs[k]);
                }

                const { addItemToInventory } = require('./inventoryHandlers');
                chosenPool.forEach(rewItem => {
                    const master = allShopItems.find(i => String(i.id) === String(rewItem.id));
                    const qty = parseInt(rewItem.qty) || 1;

                    const newItem = {
                        id: rewItem.id,
                        instanceId: "",
                        name: master ? master.name : `Ítem ${rewItem.id}`,
                        type: master ? (master.type || "utility").toLowerCase() : "utility",
                        base: master ? (master.base || 0) : 0,
                        color: master ? master.color : "#ffffff",
                        rarity: master ? (master.rarity || 0) : 0,
                        icon: master ? master.icon : ""
                    };
                    addItemToInventory(user, newItem, state.SERVER_CONFIG, qty);
                });
                user.markModified('gameData.inventory');
                p.inventory = user.gameData.inventory;
            }

            user.markModified('gameData.quests');
            await user.save();

            // Emitir actualización de inventario y datos
            const eByShipObj = {};
            if (user.gameData.equippedByShip) {
                if (user.gameData.equippedByShip instanceof Map) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                } else {
                    Object.assign(eByShipObj, user.gameData.equippedByShip);
                }
            }

            socket.emit('inventoryData', {
                player: {
                    ...JSON.parse(JSON.stringify(user.gameData)),
                    equippedByShip: eByShipObj
                }
            });

            socket.emit('gameNotification', { msg: `Recompensa de misión reclamada con éxito!`, type: 'success' });

            // Sincronizar estado de misiones
            socket.emit('questsStateData', {
                active: user.gameData.quests.active,
                completed: user.gameData.quests.completed,
                unlocks: user.gameData.unlocks || []
            });

        } catch (e) {
            Logger.error('QUESTS', `Error en claimQuestReward: ${e.message}`);
        }
    });
}

// Helper para actualizar progreso al matar un enemigo
async function onEnemyKilled(socketId, enemyType, state, io) {
    try {
        const p = state.players[socketId];
        if (!p) return;

        const user = getPlayerRAMAdapter(p);
        if (!user || !user.gameData.quests) return;

        const activeQuests = user.gameData.quests.active || [];
        const questsConfig = state.SERVER_CONFIG?.questsConfig || [];
        let modified = false;

        for (const activeQuest of activeQuests) {
            const questDef = questsConfig.find(q => String(q.id) === String(activeQuest.id));
            if (questDef && questDef.targetType === 'kill' && String(questDef.targetId) === String(enemyType)) {
                if (activeQuest.progress < questDef.targetAmount) {
                    activeQuest.progress++;
                    modified = true;
                    
                    const socket = io.sockets.sockets.get(socketId);
                    if (socket) {
                        socket.emit('gameNotification', {
                            msg: `Misión: ${questDef.name} (${activeQuest.progress}/${questDef.targetAmount})`,
                            type: 'info'
                        });
                    }
                }
            }
        }

        if (modified) {
            user.markModified('gameData.quests');
            await user.save();

            const socket = io.sockets.sockets.get(socketId);
            if (socket) {
                socket.emit('questsStateData', {
                    active: user.gameData.quests.active,
                    completed: user.gameData.quests.completed
                });
            }
        }
    } catch (e) {
        Logger.error('QUESTS', `Error en onEnemyKilled: ${e.message}`);
    }
}

// Helper para actualizar progreso al cambiar de zona/explorar
async function onZoneChanged(socketId, zoneId, state, io) {
    try {
        const p = state.players[socketId];
        if (!p) return;

        const user = getPlayerRAMAdapter(p);
        if (!user || !user.gameData.quests) return;

        const activeQuests = user.gameData.quests.active || [];
        const questsConfig = state.SERVER_CONFIG?.questsConfig || [];
        let modified = false;

        for (const activeQuest of activeQuests) {
            const questDef = questsConfig.find(q => String(q.id) === String(activeQuest.id));
            if (questDef && questDef.targetType === 'explore' && String(questDef.targetId) === String(zoneId)) {
                // Solo marcar como explorada automáticamente si no requiere coordenadas específicas de destino
                if (questDef.targetX === undefined || questDef.targetY === undefined || questDef.targetX === null || questDef.targetY === null) {
                    if (activeQuest.progress < 1) {
                        activeQuest.progress = 1;
                        modified = true;
                        
                        const socket = io.sockets.sockets.get(socketId);
                        if (socket) {
                            socket.emit('gameNotification', {
                                msg: `¡Objetivo explorado!: ${questDef.name}`,
                                type: 'info'
                            });
                        }
                    }
                }
            }
        }

        if (modified) {
            user.markModified('gameData.quests');
            await user.save();

            const socket = io.sockets.sockets.get(socketId);
            if (socket) {
                socket.emit('questsStateData', {
                    active: user.gameData.quests.active,
                    completed: user.gameData.quests.completed
                });
            }
        }
    } catch (e) {
        Logger.error('QUESTS', `Error en onZoneChanged: ${e.message}`);
    }
}

// Helper para procesar bajas de enemigos sobre un objeto user ya cargado (evita race conditions)
function processEnemyKillsForUser(user, enemyType, state, socket) {
    if (!user || !user.gameData || !user.gameData.quests) return false;
    const activeQuests = user.gameData.quests.active || [];
    const questsConfig = state.SERVER_CONFIG?.questsConfig || [];
    let modified = false;

    for (const activeQuest of activeQuests) {
        const questDef = questsConfig.find(q => String(q.id) === String(activeQuest.id));
        if (questDef && questDef.targetType === 'kill' && String(questDef.targetId) === String(enemyType)) {
            if (activeQuest.progress < questDef.targetAmount) {
                activeQuest.progress++;
                modified = true;
                if (socket) {
                    socket.emit('gameNotification', {
                        msg: `Misión: ${questDef.name} (${activeQuest.progress}/${questDef.targetAmount})`,
                        type: 'info'
                    });
                    socket.emit('questsStateData', {
                        active: user.gameData.quests.active,
                        completed: user.gameData.quests.completed,
                        unlocks: user.gameData.unlocks || []
                    });
                }
            }
        }
    }

    if (modified) {
        user.markModified('gameData.quests');
    }
    return modified;
}

function processEventWinForUser(user, eventType, state, socket) {
    if (!user || !user.gameData || !user.gameData.quests) return false;
    const activeQuests = user.gameData.quests.active || [];
    const questsConfig = state.SERVER_CONFIG?.questsConfig || [];
    let modified = false;

    for (const activeQuest of activeQuests) {
        const questDef = questsConfig.find(q => String(q.id) === String(activeQuest.id));
        if (questDef && questDef.targetType === 'event' && String(questDef.targetId) === String(eventType)) {
            if (activeQuest.progress < questDef.targetAmount) {
                activeQuest.progress++;
                modified = true;
                if (socket) {
                    socket.emit('gameNotification', {
                        msg: `Misión: ${questDef.name} (${activeQuest.progress}/${questDef.targetAmount})`,
                        type: 'info'
                    });
                    socket.emit('questsStateData', {
                        active: user.gameData.quests.active,
                        completed: user.gameData.quests.completed,
                        unlocks: user.gameData.unlocks || []
                    });
                }
            }
        }
    }

    if (modified) {
        user.markModified('gameData.quests');
    }
    return modified;
}

module.exports = {
    registerQuestHandlers,
    onEnemyKilled,
    onZoneChanged,
    processEnemyKillsForUser,
    processEventWinForUser
};
