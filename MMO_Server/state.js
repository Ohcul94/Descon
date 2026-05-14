const GridManager = require('./systems/GridManager');

module.exports = {
    grid: new GridManager(500),
    players: {},
    activeSessions: new Map(),
    enemies: {},
    activeAreas: {},
    parties: {},
    playerParty: {},
    
    // Configuraciones y contadores
    SERVER_CONFIG: null,
    nextAreaId: 1,
    nextPlayerNum: 1,
    
    // Timers y estados globales de respawn
    lastTitanDeath: 0,
    lastAncientDeath: 0
};
