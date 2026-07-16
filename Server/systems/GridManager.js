/**
 * GridManager.js
 * Sistema de Spatial Hashing para optimizar colisiones y efectos de área.
 * v2.0 - Grilla Reactiva Persistente (elimina la reconstrucción por clear() en cada tick)
 *        Reducción de complejidad O(N*M) a O(N) + eliminación de GC pressure por volatilidad
 */

class GridManager {
    constructor(cellSize = 500) {
        this.cellSize = cellSize;
        this.grid = new Map();
    }

    _getKey(x, y, zone = 1) {
        const cx = Math.floor(x / this.cellSize);
        const cy = Math.floor(y / this.cellSize);
        return `${zone}_${cx},${cy}`;
    }

    _getOrCreateCell(key) {
        if (!this.grid.has(key)) {
            this.grid.set(key, { players: [], enemies: [], areas: [] });
        }
        return this.grid.get(key);
    }

    // v2.0: Mantener compatibilidad con el código legacy que llama clear() en el gameLoop.
    // Reutiliza los objetos de celda y arrays para mitigar la recolección de basura (GC Pressure).
    // Si la grilla crece demasiado, se vacía por completo para evitar acumulación de claves viejas.
    clear() {
        if (this.grid.size > 2000) {
            this.grid.clear();
        } else {
            for (const cell of this.grid.values()) {
                cell.players.length = 0;
                cell.enemies.length = 0;
                cell.areas.length = 0;
            }
        }
    }

    insert(entity, type) {
        const key = this._getKey(entity.x, entity.y, entity.zone);
        const cell = this._getOrCreateCell(key);
        if (type === 'player') {
            // Evitar duplicados en modo reactivo
            if (!cell.players.includes(entity)) cell.players.push(entity);
        } else if (type === 'enemy') {
            if (!cell.enemies.includes(entity)) cell.enemies.push(entity);
        } else if (type === 'area') {
            if (!cell.areas.includes(entity)) cell.areas.push(entity);
        }
    }

    /**
     * v2.0: Elimina una entidad de su celda actual en la grilla.
     * Necesario para la grilla reactiva: al moverse o cambiar de zona,
     * la entidad se remueve de la celda vieja antes de insertarse en la nueva.
     * @param {object} entity - La entidad con propiedades x, y, zone
     * @param {string} type - 'player', 'enemy' o 'area'
     */
    remove(entity, type) {
        const key = this._getKey(entity.x, entity.y, entity.zone);
        const cell = this.grid.get(key);
        if (!cell) return;

        if (type === 'player') {
            const idx = cell.players.indexOf(entity);
            if (idx !== -1) cell.players.splice(idx, 1);
        } else if (type === 'enemy') {
            const idx = cell.enemies.indexOf(entity);
            if (idx !== -1) cell.enemies.splice(idx, 1);
        } else if (type === 'area') {
            const idx = cell.areas.indexOf(entity);
            if (idx !== -1) cell.areas.splice(idx, 1);
        }

        // Limpiar celdas vacías para evitar acumulación de claves muertas en el Map
        if (cell.players.length === 0 && cell.enemies.length === 0 && cell.areas.length === 0) {
            this.grid.delete(key);
        }
    }

    /**
     * v2.0: Actualiza la posición de una entidad en la grilla de forma reactiva.
     * Solo hace trabajo si la entidad cambió de celda. Ideal para llamar en movementHandler.
     * @param {object} entity - La entidad (debe tener x, y, zone actualizados)
     * @param {string} type - 'player' o 'enemy'
     * @param {number|string} oldX - Posición X anterior (antes de actualizar)
     * @param {number|string} oldY - Posición Y anterior
     * @param {number|string} oldZone - Zona anterior
     */
    updateEntity(entity, type, oldX, oldY, oldZone) {
        const oldKey = this._getKey(oldX, oldY, oldZone);
        const newKey = this._getKey(entity.x, entity.y, entity.zone);

        // Si la celda no cambió, no hay nada que hacer (cero costo)
        if (oldKey === newKey) return;

        // Remover de la celda vieja
        const oldCell = this.grid.get(oldKey);
        if (oldCell) {
            const arr = oldCell[type === 'player' ? 'players' : 'enemies'];
            const idx = arr.indexOf(entity);
            if (idx !== -1) arr.splice(idx, 1);
            if (oldCell.players.length === 0 && oldCell.enemies.length === 0 && oldCell.areas.length === 0) {
                this.grid.delete(oldKey);
            }
        }

        // Insertar en la celda nueva
        const newCell = this._getOrCreateCell(newKey);
        const newArr = newCell[type === 'player' ? 'players' : 'enemies'];
        if (!newArr.includes(entity)) newArr.push(entity);
    }

    getNearbyEntities(x, y, zone = 1) {
        const cx = Math.floor(x / this.cellSize);
        const cy = Math.floor(y / this.cellSize);
        
        let nearbyPlayers = [];
        let nearbyEnemies = [];

        // Revisar celda actual y las 8 adyacentes (bloque 3x3)
        for (let dx = -1; dx <= 1; dx++) {
            for (let dy = -1; dy <= 1; dy++) {
                const key = `${zone}_${cx + dx},${cy + dy}`;
                const cell = this.grid.get(key);
                if (cell) {
                    nearbyPlayers = nearbyPlayers.concat(cell.players);
                    nearbyEnemies = nearbyEnemies.concat(cell.enemies);
                }
            }
        }

        return { players: nearbyPlayers, enemies: nearbyEnemies };
    }
}

module.exports = GridManager;
