/**
 * state.js
 * Gestor de Estado Global para el Servidor Descon
 * v1.0 - Modularización Inicial
 */

module.exports = {
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
