const User = require('../models/User');
const { getPlayerRAMAdapter } = require('../utils/ramAdapter');
const Logger = require('../utils/logger');
const { calculateFinalStats } = require('../systems/statCalculator');

/**
 * Sanitiza autoritativamente el árbol de talentos y los puntos del usuario.
 * Garantiza:
 * - Solo categorías válidas según talentsConfig.categories.
 * - Limpieza de claves prototípicas o categorías corruptas/inyectadas.
 * - Longitud del array de cada categoría acorde a la cantidad de talentos reales configurados.
 * - Clamping rígido de cada nivel entre 0 y el maxLevel configurado del talento.
 * - skillPoints como entero mayor o igual a cero.
 * Devuelve { spentPoints, skillPoints }.
 */
function sanitizeSkillTree(user, talentsConfig) {
    if (!user || !user.gameData) return { spentPoints: 0, skillPoints: 0 };

    const tc = talentsConfig || {};
    const categories = Array.isArray(tc.categories) ? tc.categories : [];
    const validCatIds = categories.map(c => c.id);
    const talents = Array.isArray(tc.talents) ? tc.talents : [];

    // Garantizar que skillPoints sea un entero no negativo
    let pts = Math.floor(Number(user.gameData.skillPoints) || 0);
    if (pts < 0 || isNaN(pts)) pts = 0;
    user.gameData.skillPoints = pts;

    let tree = user.gameData.skillTree;
    if (!tree || typeof tree !== 'object' || Array.isArray(tree)) {
        tree = {};
    }

    const cleanTree = {};
    let totalSpent = 0;

    for (const catId of validCatIds) {
        const talentsInCat = talents.filter(t => t.category === catId);
        const branch = Array.isArray(tree[catId]) ? tree[catId] : [];
        const cleanBranch = [];

        for (let i = 0; i < talentsInCat.length; i++) {
            const talent = talentsInCat[i];
            const maxLvl = Number(talent.maxLevel) || 5;
            let currentLvl = Math.floor(Number(branch[i]) || 0);
            if (currentLvl < 0 || isNaN(currentLvl)) currentLvl = 0;
            if (currentLvl > maxLvl) currentLvl = maxLvl;

            cleanBranch.push(currentLvl);
            totalSpent += currentLvl;
        }

        cleanTree[catId] = cleanBranch;
    }

    user.gameData.skillTree = cleanTree;
    return { spentPoints: totalSpent, skillPoints: pts };
}

/**
 * Verifica si un talento cumple con los requisitos de conexión del árbol de talentos (Topología de Grafo).
 * Si tiene conexiones de entrada (hijo de otros nodos), requiere que al menos un padre tenga nivel >= 1.
 */
function checkTreePrerequisites(targetTalent, skillTree, talentsConfig) {
    if (!targetTalent || !talentsConfig) return true;
    const connections = Array.isArray(talentsConfig.connections) ? talentsConfig.connections : [];
    const incoming = connections.filter(c => c && c.to && String(c.to) === String(targetTalent.id));

    // Si no tiene conexiones entrantes, es un nodo raíz/inicial desbloqueado
    if (incoming.length === 0) return true;

    const talents = Array.isArray(talentsConfig.talents) ? talentsConfig.talents : [];
    const tree = skillTree || {};

    for (const conn of incoming) {
        const parentId = String(conn.from);
        const parentTalent = talents.find(t => t && String(t.id) === parentId);
        if (!parentTalent) continue;

        const parentCat = parentTalent.category;
        const talentsInCat = talents.filter(t => t.category === parentCat);
        const parentIdx = talentsInCat.findIndex(t => String(t.id) === parentId);
        if (parentIdx === -1) continue;

        const parentBranch = Array.isArray(tree[parentCat]) ? tree[parentCat] : [];
        const parentLvl = Number(parentBranch[parentIdx]) || 0;
        if (parentLvl > 0) {
            return true; // Al menos un padre válido tiene puntos invertidos
        }
    }

    return false;
}

function registerSkillHandlers(socket, io, state) {
    const { players } = state;

    // SISTEMA DE TALENTOS AUTORITATIVO (v300.95 - Blindado Anti-Hacks)
    socket.on('investSkill', async (data) => {
        if (!socket.dbUser || !players[socket.id] || !data || typeof data !== 'object') return;

        // 1. Candado atómico anti-concurrencia y anti-spam de paquetes por socket
        if (socket._investSkillLock) {
            return socket.emit('gameNotification', { msg: 'Procesando asignación previa...', type: 'warn' });
        }
        socket._investSkillLock = true;

        try {
            const cat = String(data.category || '').trim();
            const idx = parseInt(data.index, 10);

            // 2. Validación estricta de parámetros
            const talentsConfig = state.SERVER_CONFIG?.talentsConfig || {};
            const validCategories = (talentsConfig.categories || []).map(c => c.id);

            if (!validCategories.includes(cat) || isNaN(idx) || idx < 0) {
                console.warn(`[SECURITY-ALERT] Inyección denegada a ${players[socket.id].user}: parámetros corruptos (cat: '${cat}', idx: ${data.index})`);
                return socket.emit('gameNotification', { msg: 'ACCIÓN DENEGADA: Parámetros de talento corruptos.', type: 'error' });
            }

            const talentsInCat = (talentsConfig.talents || []).filter(t => t.category === cat);
            if (idx >= talentsInCat.length) {
                console.warn(`[SECURITY-ALERT] Inyección denegada a ${players[socket.id].user}: índice fuera de rango (${idx}/${talentsInCat.length}) en categoría '${cat}'`);
                return socket.emit('gameNotification', { msg: 'ACCIÓN DENEGADA: Talento inexistente.', type: 'error' });
            }

            const targetTalent = talentsInCat[idx];
            if (!targetTalent) {
                return socket.emit('gameNotification', { msg: 'ACCIÓN DENEGADA: Talento no identificado.', type: 'error' });
            }

            // 3. Obtener adaptador autoritativo de RAM
            const user = getPlayerRAMAdapter(players[socket.id]);
            if (!user) return;

            // 4. Sanitizar el árbol y puntos antes de cualquier cálculo
            sanitizeSkillTree(user, talentsConfig);

            // 5. Validar puntos de talento disponibles
            const pts = Number(user.gameData.skillPoints) || 0;
            if (pts <= 0) {
                return socket.emit('gameNotification', { msg: 'No tienes puntos de talento disponibles.', type: 'warn' });
            }

            // 6. Validar nivel actual vs maxLevel configurado (evitar sobrepasar el límite del talento)
            const branch = user.gameData.skillTree[cat] || [];
            const currentLvl = Number(branch[idx]) || 0;
            const maxLvl = Number(targetTalent.maxLevel) || 5;

            if (currentLvl >= maxLvl) {
                return socket.emit('gameNotification', { msg: `Nivel máximo alcanzado (${currentLvl}/${maxLvl}) para '${targetTalent.name || 'este talento'}'.`, type: 'warn' });
            }

            // 7. Validar desbloqueo por misiones (talentsLockedConfig)
            const lockedConfig = (state.SERVER_CONFIG && Array.isArray(state.SERVER_CONFIG.talentsLockedConfig)) ? state.SERVER_CONFIG.talentsLockedConfig : [];
            const lockedEntry = lockedConfig.find(t => String(t.category) === cat && Number(t.index) === idx);
            if (lockedEntry) {
                const unlocks = (user.gameData.unlocks && Array.isArray(user.gameData.unlocks)) ? user.gameData.unlocks : [];
                const unlockKey = 'talent:' + cat + ':' + idx;
                if (!unlocks.includes(unlockKey)) {
                    return socket.emit('gameNotification', { msg: `🔒 TALENTO BLOQUEADO: ${lockedEntry.name || 'Este talento'} está sellado. Requiere completar su misión.`, type: 'error' });
                }
            }

            // 8. Validar requisitos de conexión de árbol autoritativamente en el servidor
            if (currentLvl === 0 && !checkTreePrerequisites(targetTalent, user.gameData.skillTree, talentsConfig)) {
                console.warn(`[SECURITY-ALERT] Inyección denegada a ${players[socket.id].user}: evasión de pre-requisitos de árbol en '${targetTalent.name || targetTalent.id}'`);
                return socket.emit('gameNotification', { msg: 'ACCIÓN DENEGADA: Debes invertir en un talento conectado previo.', type: 'error' });
            }

            // 9. Aplicar inversión de punto autoritativamente
            branch[idx] = currentLvl + 1;
            user.gameData.skillTree[cat] = branch;
            user.gameData.skillPoints = pts - 1;

            user.markModified('gameData.skillTree');
            user.markModified('gameData.skillPoints');
            user.markModified('gameData');

            // 10. Actualizar RAM de forma síncrona
            players[socket.id].skillTree = user.gameData.skillTree;
            players[socket.id].skillPoints = user.gameData.skillPoints;

            // 11. Recalcular estadísticas autoritativas en el servidor
            calculateFinalStats(players[socket.id], state.SERVER_CONFIG);

            // 12. Persistir en base de datos
            await user.save();
            Logger.debug('DATABASE', `Talento '${cat}' [${idx}] (${targetTalent.name}) invertido para ${user.username}. Nivel: ${branch[idx]}/${maxLvl}. Puntos restantes: ${user.gameData.skillPoints}`);

            socket.dbUser = user;

            const eByShipObj = {};
            if (user.gameData.equippedByShip) {
                if (user.gameData.equippedByShip instanceof Map) {
                    user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
                } else {
                    Object.assign(eByShipObj, user.gameData.equippedByShip);
                }
            }

            // 13. Sincronizar cliente y mapa
            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj }
            });
            if (io && typeof io.to === 'function') {
                io.to(`zone_${players[socket.id].zone || 1}`).emit('playerStatSync', {
                    id: socket.id,
                    hp: players[socket.id].hp,
                    shield: players[socket.id].shield,
                    maxHp: players[socket.id].maxHp,
                    maxShield: players[socket.id].maxShield
                });
            }

        } catch (e) {
            Logger.error('TALENT', e.message);
        } finally {
            socket._investSkillLock = false;
        }
    });

    // RESET DE TALENTOS AUTORITATIVO (v300.95 - Blindado Anti-Hacks)
    socket.on('resetSkills', async () => {
        if (!socket.dbUser || !players[socket.id]) return;

        if (socket._investSkillLock) {
            return socket.emit('gameNotification', { msg: 'Operación en curso...', type: 'warn' });
        }
        socket._investSkillLock = true;

        try {
            const user = getPlayerRAMAdapter(players[socket.id]);
            if (!user) return;

            const talentsConfig = state.SERVER_CONFIG?.talentsConfig || {};
            const RESET_COST = 5000;

            const currentOhcu = Number(user.gameData.ohcu) || 0;
            if (currentOhcu < RESET_COST) {
                return socket.emit('gameNotification', { msg: `OHCU INSUFICIENTE PARA RESETEAR (Requiere ${RESET_COST.toLocaleString()} OHCU)`, type: 'error' });
            }

            // 1. Sanitizar previamente el árbol para obtener el conteo exacto y legítimo de puntos gastados
            const { spentPoints } = sanitizeSkillTree(user, talentsConfig);

            if (spentPoints <= 0) {
                return socket.emit('gameNotification', { msg: 'NO HAY HABILIDADES PARA RESETEAR', type: 'warn' });
            }

            // 2. Descontar costo en OHCU y devolver exactamente los puntos gastados
            user.gameData.ohcu = currentOhcu - RESET_COST;
            user.gameData.skillPoints = (Number(user.gameData.skillPoints) || 0) + spentPoints;

            // 3. Reiniciar a 0 todas las ramas de categorías válidas
            const categories = Array.isArray(talentsConfig.categories) ? talentsConfig.categories : [];
            const talents = Array.isArray(talentsConfig.talents) ? talentsConfig.talents : [];
            const resetTree = {};

            for (const c of categories) {
                const count = talents.filter(t => t.category === c.id).length;
                resetTree[c.id] = new Array(count).fill(0);
            }
            user.gameData.skillTree = resetTree;

            user.markModified('gameData.skillTree');
            user.markModified('gameData.skillPoints');
            user.markModified('gameData.ohcu');
            user.markModified('gameData');

            // 4. Actualizar RAM
            players[socket.id].skillTree = user.gameData.skillTree;
            players[socket.id].skillPoints = user.gameData.skillPoints;
            players[socket.id].ohcu = user.gameData.ohcu;

            // 5. Recalcular estadísticas después del reseteo
            calculateFinalStats(players[socket.id], state.SERVER_CONFIG);

            await user.save();
            Logger.info('TALENT', `Árbol de talentos reseteado para ${user.username}. Puntos devueltos: ${spentPoints}. OHCU restante: ${user.gameData.ohcu}`);

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
            if (io && typeof io.to === 'function') {
                io.to(`zone_${players[socket.id].zone || 1}`).emit('playerStatSync', {
                    id: socket.id,
                    hp: players[socket.id].hp,
                    shield: players[socket.id].shield,
                    maxHp: players[socket.id].maxHp,
                    maxShield: players[socket.id].maxShield
                });
            }
            socket.emit('gameNotification', { msg: `ÁRBOL RESETEADO: Se devolvieron ${spentPoints} puntos de talento.`, type: 'success' });

        } catch (e) {
            Logger.error('SKILL-RESET', e.message);
        } finally {
            socket._investSkillLock = false;
        }
    });
}

module.exports = { registerSkillHandlers, sanitizeSkillTree, checkTreePrerequisites };
