const User = require('../models/User');
const Logger = require('../utils/logger');

function registerHousingHandlers(socket, io, state) {
    const { players } = state;

    // Helper para obtener configuración en caliente del servidor
    const getHousingConfig = () => {
        return state.SERVER_CONFIG?.housingConfig || {
            levelRequired: 5,
            cost: 10000,
            currency: 'hubs',
            gridSize: 10,
            placeableItems: []
        };
    };

    // 1. DESBLOQUEAR / COMPRAR CASAR
    socket.on('buyHousing', async () => {
        if (!socket.dbUser) return;
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            if (user.gameData.housing?.unlocked) {
                return socket.emit('gameNotification', { msg: 'Ya tienes el Housing desbloqueado.', type: 'info' });
            }

            const config = getHousingConfig();

            // Validar Nivel
            if (user.gameData.level < config.levelRequired) {
                return socket.emit('gameNotification', { msg: `Requieres nivel ${config.levelRequired} para comprar el Housing.`, type: 'error' });
            }

            // Validar Dinero
            const currencyKey = config.currency === 'ohcu' ? 'ohcu' : 'hubs';
            const cost = config.cost || 0;

            if (user.gameData[currencyKey] < cost) {
                return socket.emit('gameNotification', { msg: `Fondos insuficientes. Requeres ${cost} ${currencyKey.toUpperCase()}.`, type: 'error' });
            }

            // Cobrar y Desbloquear
            user.gameData[currencyKey] -= cost;
            if (!user.gameData.housing) {
                user.gameData.housing = { unlocked: false, placedObjects: [] };
            }
            user.gameData.housing.unlocked = true;

            user.markModified(`gameData.${currencyKey}`);
            user.markModified('gameData.housing');
            await user.save();
            socket.dbUser = user;

            // Sincronizar en RAM y emitir inventario actualizado
            const p = players[socket.id];
            if (p) {
                p[currencyKey] = user.gameData[currencyKey];
            }

            const { getCategorizedInventory } = require('./inventoryHandlers');
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) {
                user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            } else {
                Object.assign(eByShipObj, user.gameData.equippedByShip);
            }

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });

            socket.emit('housingState', user.gameData.housing);
            socket.emit('gameNotification', { msg: '¡Housing adquirido con éxito! Bienvenido a tu nuevo hogar.', type: 'success' });
        } catch (e) {
            Logger.error('HOUSING', 'Error en buyHousing: ' + e.message);
        }
    });

    // 2. OBTENER ESTADO DEL HOUSING
    socket.on('getHousingState', async () => {
        if (!socket.dbUser) return;
        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            if (!user.gameData.housing) {
                user.gameData.housing = { unlocked: false, placedObjects: [] };
            }

            socket.emit('housingState', user.gameData.housing);
        } catch (e) {
            Logger.error('HOUSING', 'Error en getHousingState: ' + e.message);
        }
    });

    // 3. COLOCAR/COMPRAR OBJETO EN LA GRILLA
    socket.on('placeHousingObject', async (data) => {
        if (!socket.dbUser || !data) return;
        try {
            const { itemType, x, z, rotation } = data; // x, z en rango 0..gridSize-1
            const cellX = parseInt(x);
            const cellZ = parseInt(z);
            const rot = parseInt(rotation) || 0;

            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            if (!user.gameData.housing?.unlocked) {
                return socket.emit('gameNotification', { msg: 'Primero debes comprar el Housing.', type: 'error' });
            }

            const config = getHousingConfig();

            // Validar límites de grilla
            if (cellX < 0 || cellX >= config.gridSize || cellZ < 0 || cellZ >= config.gridSize) {
                return socket.emit('gameNotification', { msg: 'Coordenadas fuera del límite de la grilla.', type: 'error' });
            }

            // Validar que el objeto exista en la configuración
            const itemConfig = config.placeableItems.find(it => it.id === itemType);
            if (!itemConfig) {
                return socket.emit('gameNotification', { msg: 'Tipo de objeto no configurado o inválido.', type: 'error' });
            }

            // Validar colisión (que no haya otro objeto en la misma celda)
            const placedList = user.gameData.housing.placedObjects || [];
            const hasCollision = placedList.some(obj => obj.x === cellX && obj.z === cellZ);
            if (hasCollision) {
                return socket.emit('gameNotification', { msg: 'Ya existe un objeto en esa celda de la grilla.', type: 'error' });
            }

            // Validar costos
            const currencyKey = itemConfig.currency === 'ohcu' ? 'ohcu' : 'hubs';
            const cost = itemConfig.cost || 0;

            if (user.gameData[currencyKey] < cost) {
                return socket.emit('gameNotification', { msg: `Hubs u Ohcu insuficientes para comprar este objeto.`, type: 'error' });
            }

            // Debitar fondos
            user.gameData[currencyKey] -= cost;

            // Generar ID único para este objeto en la colocación
            const placementId = 'obj_' + Date.now() + '_' + Math.floor(Math.random() * 1000);
            const newPlacedObj = {
                id: placementId,
                itemType,
                x: cellX,
                z: cellZ,
                rotation: rot
            };

            user.gameData.housing.placedObjects.push(newPlacedObj);

            user.markModified(`gameData.${currencyKey}`);
            user.markModified('gameData.housing');
            await user.save();
            socket.dbUser = user;

            // Sincronizar RAM y emitir inventario actualizado
            const p = players[socket.id];
            if (p) {
                p[currencyKey] = user.gameData[currencyKey];
            }

            const { getCategorizedInventory } = require('./inventoryHandlers');
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) {
                user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            } else {
                Object.assign(eByShipObj, user.gameData.equippedByShip);
            }

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });

            socket.emit('housingState', user.gameData.housing);
            socket.emit('gameNotification', { msg: `${itemConfig.name} colocado con éxito.`, type: 'success' });
        } catch (e) {
            Logger.error('HOUSING', 'Error en placeHousingObject: ' + e.message);
        }
    });

    // 4. RETIRAR OBJETO DE LA GRILLA (REINTEGRA EL 50% DEL COSTO)
    socket.on('removeHousingObject', async (data) => {
        if (!socket.dbUser || !data) return;
        try {
            const { id } = data; // id del objeto colocado

            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const placedList = user.gameData.housing?.placedObjects || [];
            const idx = placedList.findIndex(obj => obj.id === id);

            if (idx === -1) {
                return socket.emit('gameNotification', { msg: 'Objeto no encontrado en el Housing.', type: 'error' });
            }

            const obj = placedList[idx];
            const config = getHousingConfig();
            const itemConfig = config.placeableItems.find(it => it.id === obj.itemType);

            // Reintegrar 50%
            if (itemConfig) {
                const currencyKey = itemConfig.currency === 'ohcu' ? 'ohcu' : 'hubs';
                const refund = Math.floor((itemConfig.cost || 0) * 0.5);
                user.gameData[currencyKey] += refund;
                user.markModified(`gameData.${currencyKey}`);
                
                const p = players[socket.id];
                if (p) {
                    p[currencyKey] = user.gameData[currencyKey];
                }
            }

            // Remover del listado
            user.gameData.housing.placedObjects.splice(idx, 1);
            user.markModified('gameData.housing');
            await user.save();
            socket.dbUser = user;

            // Sincronizar clientes
            const { getCategorizedInventory } = require('./inventoryHandlers');
            const eByShipObj = {};
            if (user.gameData.equippedByShip instanceof Map) {
                user.gameData.equippedByShip.forEach((v, k) => { eByShipObj[k] = v; });
            } else {
                Object.assign(eByShipObj, user.gameData.equippedByShip);
            }

            socket.emit('inventoryData', {
                player: { ...JSON.parse(JSON.stringify(user.gameData)), equippedByShip: eByShipObj, inventoryByCategory: getCategorizedInventory(user.gameData.inventory) }
            });

            socket.emit('housingState', user.gameData.housing);
            socket.emit('gameNotification', { msg: 'Objeto removido y 50% del costo reembolsado.', type: 'success' });
        } catch (e) {
            Logger.error('HOUSING', 'Error en removeHousingObject: ' + e.message);
        }
    });

    // 5. MOVER/ROTAR OBJETO EXISTENTE
    socket.on('moveHousingObject', async (data) => {
        if (!socket.dbUser || !data) return;
        try {
            const { id, x, z, rotation } = data;
            const cellX = parseInt(x);
            const cellZ = parseInt(z);
            const rot = parseInt(rotation) || 0;

            const user = await User.findById(socket.dbUser._id);
            if (!user) return;

            const config = getHousingConfig();

            // Validar límites de grilla
            if (cellX < 0 || cellX >= config.gridSize || cellZ < 0 || cellZ >= config.gridSize) {
                return socket.emit('gameNotification', { msg: 'Coordenadas fuera del límite de la grilla.', type: 'error' });
            }

            const placedList = user.gameData.housing?.placedObjects || [];
            const idx = placedList.findIndex(obj => obj.id === id);

            if (idx === -1) {
                return socket.emit('gameNotification', { msg: 'Objeto no encontrado en el Housing.', type: 'error' });
            }

            // Validar que la celda destino esté libre (o sea el mismo objeto)
            const hasCollision = placedList.some(obj => obj.id !== id && obj.x === cellX && obj.z === cellZ);
            if (hasCollision) {
                return socket.emit('gameNotification', { msg: 'Esa celda de la grilla ya está ocupada.', type: 'error' });
            }

            // Actualizar coordenadas y rotación
            placedList[idx].x = cellX;
            placedList[idx].z = cellZ;
            placedList[idx].rotation = rot;

            user.markModified('gameData.housing');
            await user.save();
            socket.dbUser = user;

            socket.emit('housingState', user.gameData.housing);
            socket.emit('gameNotification', { msg: 'Objeto reubicado con éxito.', type: 'info' });
        } catch (e) {
            Logger.error('HOUSING', 'Error en moveHousingObject: ' + e.message);
        }
    });
}

module.exports = { registerHousingHandlers };
