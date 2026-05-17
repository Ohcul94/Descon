/**
 * ExtractionManager.js
 * Sistema de alto nivel para gestionar partidas de extracción (Raids) en Node.js con Socket.io.
 * Diseñado con arquitectura autoritativa y persistencia controlada en MongoDB.
 */

const User = require('../models/User');
const Logger = require('../utils/logger');
const { calculateFinalStats } = require('./statCalculator');

class ExtractionManager {
    constructor() {
        this.matches = new Map(); // Almacena las instancias activas de extracción
        this.queue = [];          // Cola de espera para el Matchmaker
        this.io = null;
        this.state = null;
        this.aiManager = null;
        this.matchmakingInterval = null;
        
        // v2.5: Variables para el Matchmaker Dinámico
        this.countdownActive = false;
        this.countdownValue = 0;
        this.countdownTarget = 30; 
    }

    /**
     * Inicializa el manager con las referencias globales del servidor.
     */
    init(io, state, aiManager) {
        this.io = io;
        this.state = state;
        this.aiManager = aiManager;
        
        // Iniciar el ciclo del Matchmaker cada 2 segundos para mayor respuesta
        if (this.matchmakingInterval) clearInterval(this.matchmakingInterval);
        this.matchmakingInterval = setInterval(() => this.processQueue(), 2000);
        
        Logger.success('EXTRACT', 'Sistema de Extracción y Matchmaker Pro inicializados.');
    }

    /**
     * Crea una nueva partida de extracción con parámetros fijos y puntos de extracción.
     * @param {Number} mapBaseId ID del mapa base (ej: 2)
     */
    createExtractionMatch(mapBaseId) {
        const matchId = `extract_${mapBaseId}_${Date.now()}`;
        
        // v2.1: LEER CONFIGURACIÓN DINÁMICA DEL ADMIN PANEL
        const extConfig = (this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.gameModes) 
            ? this.state.SERVER_CONFIG.gameModes.extraction 
            : null;

        const maxPlayers = extConfig ? (extConfig.maxPlayers || 21) : 21;
        const radius = extConfig ? (extConfig.extractRadius || 150) : 150;
        
        // Mapear puntos del config a la instancia
        const extractionPoints = (extConfig && extConfig.extractPoints)
            ? extConfig.extractPoints.map((p, idx) => ({ id: idx + 1, x: p.x, y: p.y, radius: radius, label: p.label }))
            : [
                { id: 1, x: 1500, y: 1500, radius: 150, label: "Alfa" },
                { id: 2, x: 8500, y: 8500, radius: 150, label: "Beta" },
                { id: 3, x: 5000, y: 500, radius: 150, label: "Gamma" }
            ];

        const matchData = {
            id: matchId,
            baseMap: mapBaseId,
            maxPlayers: maxPlayers,
            startTime: Date.now(),
            duration: 15 * 60 * 1000, // 15 minutos de Raid
            players: [], // Lista de socket.ids en la partida
            extractionPoints: extractionPoints,
            isActive: true
        };

        this.matches.set(matchId, matchData);
        Logger.info('EXTRACT', `Nueva Raid creada: ${matchId} (Mapa: ${mapBaseId})`);
        
        // v2.2: Inicializar celdas de AOI para optimización (5 zonas)
        matchData.sectors = { 1: [], 2: [], 3: [], 4: [], 5: [] };

        // v2.6: SPAWN DE ENEMIGOS CONFIGURADOS
        if (extConfig && extConfig.spawners && this.aiManager) {
            let totalSpawned = 0;
            extConfig.spawners.forEach(s => {
                const count = parseInt(s.count) || 5;
                const radius = parseInt(s.radius) || 500;
                const enemyId = parseInt(s.enemyId) || 1;

                for (let i = 0; i < count; i++) {
                    const rx = (parseInt(s.x) || 5000) + (Math.random() - 0.5) * radius * 2;
                    const ry = (parseInt(s.y) || 5000) + (Math.random() - 0.5) * radius * 2;
                    
                    // Asegurar que rx/ry están dentro de los límites del mapa (0-10000)
                    const finalX = Math.min(9900, Math.max(100, rx));
                    const finalY = Math.min(9900, Math.max(100, ry));

                    this.aiManager.serverSpawnEnemy(matchId, enemyId, finalX, finalY);
                    totalSpawned++;
                }
            });
            Logger.info('EXTRACT', `¡Infantería Desplegada! ${totalSpawned} enemigos spawneados en la Raid ${matchId}`);
        }

        return matchId;
    }

    /**
     * Matchmaker: Agrega a un jugador a la cola.
     */
    addToQueue(socketId) {
        if (!this.queue.includes(socketId)) {
            this.queue.push(socketId);
            this.io.to(socketId).emit('extraction_queue_joined', { position: Math.floor(this.queue.length) });
            Logger.info('MATCH', `Jugador ${socketId} se unió a la cola de extracción.`);

            // v2.8: Si ya hay cuenta atrás, avisarle al que entra
            if (this.countdownActive) {
                this.io.to(socketId).emit('extraction_match_countdown', { 
                    remaining: Math.max(0, Math.floor(this.countdownValue / 1000)),
                    players: this.queue.length,
                    minPlayers: 0 // Ya se alcanzó
                });
            }
        }
    }

    /**
     * Procesa la cola y crea partidas.
     */
    processQueue() {
        if (this.queue.length === 0) {
            this.countdownActive = false;
            return;
        }

        const extConfig = (this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.gameModes) 
            ? this.state.SERVER_CONFIG.gameModes.extraction 
            : null;
        
        const minToStart = extConfig ? (extConfig.minPlayers || 2) : 2;
        const maxPerMatch = extConfig ? (extConfig.maxPlayers || 21) : 21;
        const startCountdown = extConfig ? (extConfig.startCountdown || 30000) : 30000; // Default 30s en MS

        // Caso A: Llenamos la partida al máximo inmediatamente
        if (this.queue.length >= maxPerMatch) {
            this.startMatchNow(maxPerMatch);
            this.countdownActive = false;
            return;
        }

        // Caso B: Tenemos el mínimo, iniciamos o actualizamos cuenta regresiva
        if (this.queue.length >= minToStart) {
            if (!this.countdownActive) {
                this.countdownActive = true;
                this.countdownValue = startCountdown;
                this.countdownTarget = startCountdown;
                Logger.info('MATCH', `Mínimo de jugadores alcanzado (${this.queue.length}). Iniciando cuenta regresiva: ${this.countdownValue}ms`);
            } else {
                this.countdownValue -= 2000; // Bajamos 2000ms porque el intervalo es 2s
                
                // Notificar a los jugadores en cola (convertimos a segundos para la UI si es necesario, o enviamos ms)
                this.queue.forEach(sid => {
                    this.io.to(sid).emit('extraction_match_countdown', { 
                        remaining: Math.max(0, Math.floor(this.countdownValue / 1000)),
                        players: this.queue.length,
                        minPlayers: minToStart
                    });
                });

                if (this.countdownValue <= 0) {
                    this.startMatchNow(this.queue.length);
                    this.countdownActive = false;
                }
            }
        } else {
            // No hay suficientes jugadores
            if (this.countdownActive) {
                Logger.warn('MATCH', `Cuenta regresiva cancelada: un jugador salió y ya no hay el mínimo (${this.queue.length}/${minToStart})`);
                this.countdownActive = false;
                this.queue.forEach(sid => {
                    this.io.to(sid).emit('extraction_match_cancelled', { reason: 'No hay suficientes pilotos en cola.' });
                });
            }
        }
    }

    /**
     * Inicia una partida con los jugadores actuales en cola.
     */
    startMatchNow(count) {
        const extConfig = (this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.gameModes) 
            ? this.state.SERVER_CONFIG.gameModes.extraction 
            : null;
            
        const playersForMatch = this.queue.splice(0, count);
        const enabledMaps = (extConfig && extConfig.maps && extConfig.maps.length > 0) ? extConfig.maps : [10];
        const mapId = enabledMaps[Math.floor(Math.random() * enabledMaps.length)];
        
        const matchId = this.createExtractionMatch(mapId);
        
        // v2.9: Asignar spawns aleatorios únicos
        let availableSpawns = (extConfig && extConfig.spawnPoints && extConfig.spawnPoints.length > 0) 
            ? [...extConfig.spawnPoints] 
            : [{ x: 5000, y: 5000 }]; // Fallback
            
        // Mezclar spawns (Fisher-Yates)
        for (let i = availableSpawns.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [availableSpawns[i], availableSpawns[j]] = [availableSpawns[j], availableSpawns[i]];
        }

        playersForMatch.forEach((sid, idx) => {
            // Asignar spawn (si hay menos puntos que jugadores, repetir aleatoriamente)
            const spawn = availableSpawns[idx % availableSpawns.length];
            this.joinMatch(sid, matchId, spawn);
            this.io.to(sid).emit('extraction_match_found', { matchId });
        });
        
        Logger.success('MATCH', `¡RAID INICIADA! ${playersForMatch.length} jugadores enviados al Mapa ${mapId}.`);
    }

    /**
     * AOI: Calcula el sector (1-5) basado en la posición X.
     * Dividimos el mapa de 10000px en 5 franjas de 2000px.
     */
    getSector(x) {
        return Math.min(5, Math.max(1, Math.floor(x / 2000) + 1));
    }

    /**
     * Gestiona el cambio de sector de un jugador para optimizar red.
     */
    updatePlayerSector(socket, x) {
        const p = this.state.players[socket.id];
        if (!p || !p.isExtracting) return;

        const newSector = this.getSector(x);
        const oldSector = p.currentSector || 1;

        if (newSector !== oldSector) {
            socket.leave(`zone_${p.zone}_sector_${oldSector}`);
            socket.join(`zone_${p.zone}_sector_${newSector}`);
            p.currentSector = newSector;
            
            // Notificar a los del nuevo sector que aparecimos
            socket.to(`zone_${p.zone}_sector_${newSector}`).emit('newPlayer', { ...p, id: socket.id });
            
            Logger.debug('AOI', `Piloto ${p.user} cambió del Sector ${oldSector} al ${newSector}`);
        }
        return newSector;
    }

    /**
     * Saca a un jugador de la cola.
     */
    leaveQueue(socketId) {
        this.queue = this.queue.filter(id => id !== socketId);
        Logger.info('MATCH', `Jugador ${socketId} salió de la cola.`);
    }

    /**
     * Une a un jugador a una partida específica y congela su estado real.
     */
    async joinMatch(socketId, matchId, spawnPoint = null) {
        const match = this.matches.get(matchId);
        const p = this.state.players[socketId];
        const socket = this.io.sockets.sockets.get(socketId);

        if (!match || !p || !socket) return { success: false, error: 'No se pudo encontrar la partida o el jugador.' };
        if (match.players.length >= match.maxPlayers) return { success: false, error: 'La instancia de extracción está llena.' };

        const oldZone = p.zone;
        socket.leave(`zone_${oldZone}`);
        
        // v3.0: Aplicar el spawn point asignado
        if (spawnPoint) {
            p.x = spawnPoint.x;
            p.y = spawnPoint.y;
            p.lastPos = { x: p.x, y: p.y };
        }

        // Guardar estado original de PvP y forzar modo Combate (PvP)
        p.originalPvpEnabled = !!p.pvpEnabled;
        p.pvpEnabled = true;
        this.io.emit('playerUpdated', { id: socketId, pvpEnabled: true });

        // Configurar estado de extracción en RAM
        p.zone = matchId;
        p.isExtracting = true;
        p.extractionTimer = 0; 
        p.tempInventory = []; 
        p.inExtractionPoint = null; 

        // v2.2: Inicializar sector AOI
        const sector = this.getSector(p.x);
        p.currentSector = sector;

        match.players.push(socketId);
        socket.join(`zone_${matchId}`);

        // Notificar cambio de zona al cliente con coordenadas personalizadas de spawn
        socket.emit('changeZoneDone', {
            zoneId: matchId,
            x: p.x,
            y: p.y
        });

        // --- SYNC: Recopilar otros jugadores en la misma Raid ---
        const currentPlayersInZone = {};
        Object.keys(this.state.players).forEach(pId => {
            const otherP = this.state.players[pId];
            if (otherP.zone === matchId && pId !== socketId) {
                const { ai, ...cleanP } = otherP; // Evitar referencias circulares
                currentPlayersInZone[pId] = {
                    ...cleanP,
                    id: pId,
                    zone: matchId,
                    maxHp: otherP.maxHp || 2000,
                    maxShield: otherP.maxShield || 1000,
                    spheres: otherP.spheres || []
                };
            }
        });

        // --- SYNC: Recopilar enemigos en la misma Raid ---
        const zoneEnemies = {};
        Object.keys(this.state.enemies).forEach(id => {
            if (this.state.enemies[id].zone === matchId) {
                const { ai, ...cleanData } = this.state.enemies[id];
                zoneEnemies[id] = cleanData;
            }
        });

        // Retardo controlado (300ms) para permitir que el cliente Godot instancie el mapa antes de recibir entidades
        setTimeout(() => {
            if (socket.connected) {
                socket.emit('currentPlayers', currentPlayersInZone);
                socket.emit('currentEnemies', zoneEnemies);
                Logger.debug('EXTRACT', `Sincronía inicial enviada a ${p.user}: ${Object.keys(currentPlayersInZone).length} pilotos, ${Object.keys(zoneEnemies).length} enemigos.`);
            }
        }, 300);

        // Notificar a todos los otros pilotos de la Raid
        socket.to(`zone_${matchId}`).emit('newPlayer', { ...p, id: socketId });

        Logger.info('EXTRACT', `Piloto [${p.user}] entró a la Raid ${matchId} en Pos [${p.x}, ${p.y}]`);
        return { success: true };
    }

    /**
     * El "Latido" del sistema. Se ejecuta cada 1s desde el gameLoop principal.
     */
    updateLoop() {
        const now = Date.now();

        this.matches.forEach((match, matchId) => {
            // 0. Notificar tiempo restante global de la Raid a todos los participantes
            const remainingMatchTime = Math.max(0, Math.floor((match.duration - (now - match.startTime)) / 1000));
            this.io.to(`zone_${matchId}`).emit('raid_time_update', { 
                remaining: remainingMatchTime,
                total: Math.floor(match.duration / 1000)
            });

            // 1. Verificar si la partida expiró por tiempo
            if (now - match.startTime > match.duration) {
                this.handleMatchTimeout(matchId);
                return;
            }

            // 2. Procesar jugadores en la instancia
            match.players.forEach(socketId => {
                const p = this.state.players[socketId];
                if (!p) return;

                // REGLA DE AUTORIDAD: Si el piloto muere, procesar pérdida de raid inmediatamente
                if (p.hp <= 0) {
                    this.handlePilotDeath(socketId, matchId);
                    return;
                }

                let inAnyPoint = false;

                // Verificar proximidad a puntos de extracción
                match.extractionPoints.forEach(ep => {
                    const dx = p.x - ep.x;
                    const dy = p.y - ep.y;
                    const distSq = dx * dx + dy * dy;

                    if (distSq < ep.radius * ep.radius) {
                        inAnyPoint = true;
                        
                        // Si es el primer segundo o cambió de punto, resetear/notificar
                        const extConfig = (this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.gameModes) 
                            ? this.state.SERVER_CONFIG.gameModes.extraction 
                            : null;
                        const targetTime = extConfig ? (extConfig.countdownTime || 10000) : 10000; // MS

                        if (p.inExtractionPoint !== ep.id) {
                            p.inExtractionPoint = ep.id;
                            p.extractionTimer = 0;
                            this.io.to(socketId).emit('extraction_start', { epId: ep.id, time: Math.floor(targetTime / 1000), label: ep.label });
                        }

                        p.extractionTimer += 1000; // Sumamos 1000ms porque el loop principal es 1s

                        // Éxito: Llegó al tiempo objetivo
                        if (p.extractionTimer >= targetTime) {
                            this.handleExtractionSuccess(socketId, matchId);
                        } else {
                            // Feedback visual al cliente (countdown en segundos para comodidad del user)
                            this.io.to(socketId).emit('extraction_countdown', { remaining: Math.max(0, Math.floor((targetTime - p.extractionTimer) / 1000)) });
                        }
                    }
                });

                // Si salió del radio, cancelar inmediatamente
                if (!inAnyPoint && p.inExtractionPoint !== null) {
                    p.inExtractionPoint = null;
                    p.extractionTimer = 0;
                    this.io.to(socketId).emit('extraction_cancelled', { reason: 'Te moviste fuera de la zona.' });
                }
            });

            // 3. Limpieza de instancia vacía
            if (match.players.length === 0 && now - match.startTime > 30000) {
                this.matches.delete(matchId);
                Logger.debug('EXTRACT', `Instancia ${matchId} eliminada por inactividad.`);
                
                // v2.7: Eliminar enemigos de esta instancia
                for (const eid in this.state.enemies) {
                    if (this.state.enemies[eid].zone === matchId) {
                        delete this.state.enemies[eid];
                    }
                }
            }
        });
    }

    /**
     * Procesa la extracción exitosa: Persistencia en DB y retorno al Hangar.
     */
    async handleExtractionSuccess(socketId, matchId) {
        const p = this.state.players[socketId];
        const match = this.matches.get(matchId);
        if (!p || !match) return;

        Logger.success('EXTRACT', `¡Extracción Exitosa! Piloto [${p.user}] evacuó con ${p.tempInventory.length} items.`);

        try {
            // Escritura limpia y autoritativa en MongoDB Atlas
            await User.updateOne(
                { _id: p.id },
                { 
                    $push: { "gameData.inventory": { $each: p.tempInventory } },
                    $set: { 
                        "gameData.zone": 1, 
                        "gameData.lastPos": { x: 2000, y: 2000 },
                        "gameData.hp": p.hp,
                        "gameData.shield": p.shield
                    }
                }
            );

            // Actualizar inventario en el objeto p en RAM
            if (!p.inventory) p.inventory = [];
            p.inventory.push(...p.tempInventory);

            this.io.to(socketId).emit('extraction_final_success', { items: p.tempInventory });
            this.returnToHangar(socketId, matchId);

        } catch (err) {
            Logger.error('EXTRACT', `Error persistiendo extracción de ${p.user}: ${err.message}`);
        }
    }

    /**
     * Procesa la muerte del piloto: Pérdida de items de raid y penalización.
     */
    async handlePilotDeath(socketId, matchId) {
        const p = this.state.players[socketId];
        if (!p) return;

        Logger.warn('EXTRACT', `Piloto [${p.user}] murió en la Raid.`);

        try {
            await User.updateOne(
                { _id: p.id },
                { 
                    $set: { 
                        "gameData.hp": 0, 
                        "gameData.zone": 1,
                        "gameData.lastPos": { x: 2000, y: 2000 }
                    } 
                }
            );

            p.tempInventory = []; // Limpieza de RAM
            this.io.to(socketId).emit('extraction_failed', { reason: 'PILOTO CAÍDO EN COMBATE' });
            this.returnToHangar(socketId, matchId);

        } catch (err) {
            Logger.error('EXTRACT', `Error en muerte de ${p.user}: ${err.message}`);
        }
    }

    /**
     * Saca al jugador de la instancia y lo devuelve al Hangar Seguro.
     */
    returnToHangar(socketId, matchId) {
        const p = this.state.players[socketId];
        const match = this.matches.get(matchId);
        const socket = this.io.sockets.sockets.get(socketId);

        if (match) {
            match.players = match.players.filter(id => id !== socketId);
        }

        if (p && socket) {
            socket.leave(`zone_${matchId}`);
            p.zone = 1;
            p.x = 1000;
            p.y = 1000;
            p.isExtracting = false;
            p.tempInventory = [];
            p.extractionTimer = 0;

            // Restaurar PvP original
            p.pvpEnabled = p.originalPvpEnabled !== undefined ? p.originalPvpEnabled : false;
            this.io.emit('playerUpdated', { id: socketId, pvpEnabled: p.pvpEnabled });

            socket.join(`zone_1`);
            socket.emit('changeZoneDone', 1);

            // v3.0: Enviar jugadores y enemigos actuales de la Zona 1 (Lobby) para perfecta sincronía al volver
            const currentPlayersInZone = {};
            Object.keys(this.state.players).forEach(id => {
                if (Number(this.state.players[id].zone) === 1 && id !== socketId) {
                    currentPlayersInZone[id] = {
                        id: id,
                        dbId: this.state.players[id].id,
                        user: this.state.players[id].user,
                        x: this.state.players[id].x,
                        y: this.state.players[id].y,
                        zone: this.state.players[id].zone,
                        hp: this.state.players[id].hp,
                        maxHp: this.state.players[id].maxHp,
                        shield: this.state.players[id].shield,
                        maxShield: this.state.players[id].maxShield,
                        shipType: this.state.players[id].shipType,
                        spheres: this.state.players[id].spheres,
                        pvpEnabled: this.state.players[id].pvpEnabled
                    };
                }
            });
            socket.emit('currentPlayers', currentPlayersInZone);

            const zoneEnemies = {};
            Object.keys(this.state.enemies).forEach(id => {
                if (Number(this.state.enemies[id].zone) === 1) {
                    const { ai, ...cleanData } = this.state.enemies[id];
                    zoneEnemies[id] = cleanData;
                }
            });
            socket.emit('currentEnemies', zoneEnemies);
            
            // Re-sincronizar stats finales
            calculateFinalStats(p, this.state.SERVER_CONFIG);
            
            this.io.to(`zone_1`).emit('newPlayer', { ...p, id: socketId });
        }
    }

    /**
     * Si se acaba el tiempo de la Raid, todos los que no salieron mueren (Mecánica Hardcore).
     */
    handleMatchTimeout(matchId) {
        const match = this.matches.get(matchId);
        if (!match) return;

        Logger.warn('EXTRACT', `¡TIEMPO AGOTADO! La instancia ${matchId} se está colapsando.`);
        
        const playersToEject = [...match.players];
        playersForMatch.forEach(sid => {
            this.handlePilotDeath(sid, matchId);
        });

        this.matches.delete(matchId);
    }
}

module.exports = new ExtractionManager();
