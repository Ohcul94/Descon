/**
 * GridManager.js
 * Sistema de Spatial Hashing para optimizar colisiones y efectos de área.
 * v1.0 - Reducción de complejidad O(N*M) a O(N)
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

    clear() {
        this.grid.clear();
    }

    insert(entity, type) {
        const key = this._getKey(entity.x, entity.y, entity.zone);
        if (!this.grid.has(key)) {
            this.grid.set(key, { players: [], enemies: [], areas: [] });
        }
        const cell = this.grid.get(key);
        if (type === 'player') cell.players.push(entity);
        else if (type === 'enemy') cell.enemies.push(entity);
        else if (type === 'area') cell.areas.push(entity);
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
