const Logger = require('../utils/logger');
const User = require('../models/User');

class ArenaManager {
    constructor() {
        this.io = null;
        this.state = null;
        
        this.queue = []; // Array de socketIds
        this.matches = new Map(); // matchId -> matchState
        this.checkInterval = null;
    }

    init(io, state) {
        this.io = io;
        this.state = state;
        
        if (this.checkInterval) clearInterval(this.checkInterval);
        this.checkInterval = setInterval(() => this.update(), 1000);
        
        Logger.success('ARENA', 'ArenaManager inicializado correctamente con reglas avanzadas.');
    }

    joinQueue(socketId) {
        const p = this.state.players[socketId];
        if (!p) return { success: false, error: 'Piloto no encontrado.' };

        if (this.queue.includes(socketId)) {
            return { success: false, error: 'Ya estás en la cola de arenas.' };
        }

        // Verificar si ya está en una partida activa
        for (const [matchId, match] of this.matches) {
            if (match.players.some(pl => pl.socketId === socketId)) {
                return { success: false, error: 'Ya estás en una partida activa.' };
            }
        }

        // Soporte para ingresar en grupo (party de a 3) o solos
        const myUid = socketId; // Usamos el socket ID como referencia
        const playerObj = this.state.players[socketId];
        
        let partyId = null;
        // Buscar si está en party
        if (this.state.playerParty && playerObj.user) {
            // Buscar por el _id de usuario de la db si existe
            const dbUser = [...this.io.sockets.sockets.values()].find(s => s.id === socketId)?.dbUser;
            if (dbUser) {
                const uid = dbUser._id.toString();
                partyId = this.state.playerParty[uid];
            }
        }

        if (partyId && this.state.parties && this.state.parties[partyId]) {
            const party = this.state.parties[partyId];
            
            // Validar que el grupo no exceda de 3 pilotos
            if (party.members.length > 3) {
                this.io.to(socketId).emit('gameNotification', {
                    msg: 'El grupo excede el límite de 3 pilotos para Arenas.',
                    type: 'error'
                });
                return { success: false, error: 'Grupo excede límite.' };
            }

            // Conseguir los sockets de los miembros online
            const onlineMembersSids = party.members.map(uid => {
                const foundSocket = [...this.io.sockets.sockets.values()].find(s => s.dbUser && s.dbUser._id.toString() === uid);
                return foundSocket ? foundSocket.id : null;
            }).filter(Boolean);

            // Inscribir a todos los miembros online en la cola
            let addedCount = 0;
            onlineMembersSids.forEach(memSid => {
                if (!this.queue.includes(memSid)) {
                    this.queue.push(memSid);
                    addedCount++;
                    this.io.to(memSid).emit('arenaQueueJoined', { queueCount: this.queue.length });
                    this.io.to(memSid).emit('gameNotification', {
                        msg: 'Te has unido a la cola de arenas con tu grupo.',
                        type: 'info'
                    });
                }
            });

            Logger.info('ARENA', `Grupo inscrito (${addedCount} pilotos) por líder de grupo. Cola actual: ${this.queue.length}`);
            this.broadcastQueueCount();
            this.checkMatchmaking();
            return { success: true };
        }

        // Entrada individual (Solo)
        this.queue.push(socketId);
        Logger.info('ARENA', `Piloto ${p.user} se unió solo a la cola PvP. Cola actual: ${this.queue.length}`);
        
        this.io.to(socketId).emit('arenaQueueJoined', { queueCount: this.queue.length });
        this.broadcastQueueCount();

        this.checkMatchmaking();
        return { success: true };
    }

    leaveQueue(socketId) {
        const index = this.queue.indexOf(socketId);
        if (index !== -1) {
            this.queue.splice(index, 1);
            Logger.info('ARENA', `Socket ${socketId} salió de la cola PvP.`);
            this.io.to(socketId).emit('arenaQueueLeft');
            this.broadcastQueueCount();
            return { success: true };
        }
        return { success: false, error: 'No estabas en la cola.' };
    }

    broadcastQueueCount() {
        this.io.emit('arenaQueueUpdate', { count: this.queue.length });
    }

    checkMatchmaking() {
        const arenasConfig = this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.gameModes && this.state.SERVER_CONFIG.gameModes.arenas;
        if (!arenasConfig || !arenasConfig.enabled) return;

        const minPlayers = Number(arenasConfig.minPlayers) || 2;
        const maxPlayers = Number(arenasConfig.maxPlayers) || 6;

        // Si hay suficientes jugadores para arrancar una partida
        if (this.queue.length >= minPlayers) {
            const countToTake = Math.min(this.queue.length, maxPlayers);
            const matchedSocketIds = this.queue.splice(0, countToTake);
            this.startMatch(matchedSocketIds);
        }
    }

    startMatch(socketIds) {
        const arenasConfig = this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.gameModes && this.state.SERVER_CONFIG.gameModes.arenas;
        const targetMapId = (arenasConfig && arenasConfig.maps && arenasConfig.maps.length > 0) ? parseInt(arenasConfig.maps[0]) : 11;
        
        const matchId = `arena_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
        
        // Cargar configuración de nexos y pilares de este mapa
        const mapArenaCfg = (arenasConfig && arenasConfig.mapConfigs && arenasConfig.mapConfigs[targetMapId]) 
            ? arenasConfig.mapConfigs[targetMapId] 
            : {
                width: 10000,
                height: 10000,
                nexusRed: { x: 2000, y: 5000, hp: 10000, shield: 5000 },
                nexusBlue: { x: 8000, y: 5000, hp: 10000, shield: 5000 },
                spawns: [
                    { name: "Spawn Rojo 1", team: "red", x: 2000, y: 5000, radius: 200 },
                    { name: "Spawn Azul 1", team: "blue", x: 8000, y: 5000, radius: 200 }
                ],
                pillars: []
            };

        if (!mapArenaCfg.spawns || mapArenaCfg.spawns.length === 0) {
            mapArenaCfg.spawns = [
                { name: "Spawn Rojo 1", team: "red", x: mapArenaCfg.nexusRed?.x || 2000, y: mapArenaCfg.nexusRed?.y || 5000, radius: 200 },
                { name: "Spawn Azul 1", team: "blue", x: mapArenaCfg.nexusBlue?.x || 8000, y: mapArenaCfg.nexusBlue?.y || 5000, radius: 200 }
            ];
        }

        const spawnMode = (arenasConfig && arenasConfig.spawnMode) ? arenasConfig.spawnMode : 'random';

        // Dividir los jugadores en equipos (Rojo y Azul)
        const playersList = [];
        socketIds.forEach((sid, idx) => {
            const team = (idx % 2 === 0) ? 'red' : 'blue';
            playersList.push({ socketId: sid, team: team });
        });

        // Configuración de tiempos
        const countdownTime = 5000; // Cuenta regresiva de 5 segundos
        const spawnLockTime = (arenasConfig && arenasConfig.spawnLockTime) ? parseInt(arenasConfig.spawnLockTime) : 10000;
        const matchDuration = (arenasConfig && arenasConfig.matchDuration) ? parseInt(arenasConfig.matchDuration) : 600000;

        const selectSpawnPoint = (team, pX, pY) => {
            const teamSpawns = mapArenaCfg.spawns.filter(s => s.team === team);
            if (teamSpawns.length === 0) {
                return team === 'red' ? { x: 2000, y: 5000, radius: 200 } : { x: 8000, y: 5000, radius: 200 };
            }
            if (spawnMode === 'random') {
                const rIdx = Math.floor(Math.random() * teamSpawns.length);
                return teamSpawns[rIdx];
            } else if (spawnMode === 'closest') {
                const refX = pX !== undefined ? pX : (team === 'red' ? (mapArenaCfg.nexusRed?.x || 2000) : (mapArenaCfg.nexusBlue?.x || 8000));
                const refY = pY !== undefined ? pY : (team === 'red' ? (mapArenaCfg.nexusRed?.y || 5000) : (mapArenaCfg.nexusBlue?.y || 5000));
                let minDist = Infinity;
                let selected = teamSpawns[0];
                teamSpawns.forEach(s => {
                    const dist = Math.hypot(s.x - refX, s.y - refY);
                    if (dist < minDist) {
                        minDist = dist;
                        selected = s;
                    }
                });
                return selected;
            }
            return teamSpawns[0];
        };

        // Inicializar Estado de la Partida
        const matchState = {
            id: matchId,
            zoneId: matchId,
            mapId: targetMapId,
            players: playersList,
            width: mapArenaCfg.width || 10000,
            height: mapArenaCfg.height || 10000,
            
            // Tiempos
            spawnLockTime: spawnLockTime,
            matchDuration: matchDuration,
            status: 'countdown',
            statusEndTime: Date.now() + countdownTime,
            matchEndTime: 0,
            
            spawns: mapArenaCfg.spawns,
            spawnMode: spawnMode,
            
            spawnRed: mapArenaCfg.spawns.find(s => s.team === 'red') || { x: 2000, y: 5000, radius: 200 },
            spawnBlue: mapArenaCfg.spawns.find(s => s.team === 'blue') || { x: 8000, y: 5000, radius: 200 },

            nexuses: {
                red: {
                    hp: mapArenaCfg.nexusRed?.hp || 10000,
                    maxHp: mapArenaCfg.nexusRed?.hp || 10000,
                    shield: mapArenaCfg.nexusRed?.shield || 5000,
                    maxShield: mapArenaCfg.nexusRed?.shield || 5000,
                    x: mapArenaCfg.nexusRed?.x || 2000,
                    y: mapArenaCfg.nexusRed?.y || 5000
                },
                blue: {
                    hp: mapArenaCfg.nexusBlue?.hp || 10000,
                    maxHp: mapArenaCfg.nexusBlue?.hp || 10000,
                    shield: mapArenaCfg.nexusBlue?.shield || 5000,
                    maxShield: mapArenaCfg.nexusBlue?.shield || 5000,
                    x: mapArenaCfg.nexusBlue?.x || 8000,
                    y: mapArenaCfg.nexusBlue?.y || 5000
                }
            },
            // Pilares de defensa dinámicos
            pillars: (mapArenaCfg.pillars || []).map((p, pIdx) => ({
                id: `pillar_${pIdx}`,
                name: p.name || `Pilar ${pIdx + 1}`,
                team: p.team || 'red',
                x: p.x,
                y: p.y,
                hp: p.hp || 3000,
                maxHp: p.hp || 3000,
                shield: p.shield || 1500,
                maxShield: p.shield || 1500,
                damage: p.damage || 150,
                range: p.range || 600,
                ammoType: p.ammoType || 'laser',
                attackType: p.attackType || 'fast',
                lastAttackTime: 0
            }))
        };

        this.matches.set(matchId, matchState);
        Logger.info('ARENA', `Partida PvP ${matchId} iniciada. Estado: Countdown.`);

        // Warp de jugadores
        playersList.forEach(async (pl) => {
            const targetSocket = this.io.sockets.sockets.get(pl.socketId);
            const playerObj = this.state.players[pl.socketId];
            if (targetSocket && playerObj) {
                const oldZone = playerObj.zone;
                
                // Determinar punto de spawn aleatorio dentro del radio del equipo
                const spawn = selectSpawnPoint(pl.team);
                const angle = Math.random() * Math.PI * 2;
                const r = Math.random() * (spawn.radius || 100);
                const targetX = spawn.x + Math.cos(angle) * r;
                const targetY = spawn.y + Math.sin(angle) * r;

                // Desvincular de zona previa
                if (this.state.playersByZone[oldZone] && this.state.playersByZone[oldZone][pl.socketId]) {
                    delete this.state.playersByZone[oldZone][pl.socketId];
                }
                
                // Sincronizar en memoria
                if (!this.state.playersByZone[matchId]) {
                    this.state.playersByZone[matchId] = {};
                }
                this.state.playersByZone[matchId][pl.socketId] = playerObj;

                playerObj.zone = matchId;
                playerObj.x = targetX;
                playerObj.y = targetY;
                playerObj.pvpEnabled = true; 
                playerObj.team = pl.team; 
                playerObj.isFrozen = true; // Congelado al iniciar

                targetSocket.leave(`zone_${oldZone}`);
                targetSocket.join(`zone_${matchId}`);

                // Notificar inicio
                targetSocket.emit('changeZoneDone', { zoneId: matchId, x: playerObj.x, y: playerObj.y });
                targetSocket.emit('arenaMatchStarted', {
                    matchId: matchId,
                    mapId: targetMapId,   // ← ID del mapa base (ej: 9) para lookup de objetos 3D
                    team: pl.team,
                    nexuses: matchState.nexuses,
                    pillars: matchState.pillars
                });
            }
        });

        this.broadcastQueueCount();
        this.emitArenaState(matchId);
    }

    update() {
        const now = Date.now();

        for (const [matchId, match] of this.matches) {
            if (match.status === 'finished') continue;

            // 1. Cuenta Regresiva de Inicio
            if (match.status === 'countdown') {
                const remainingSec = Math.max(0, Math.ceil((match.statusEndTime - now) / 1000));
                
                this.io.to(`zone_${match.zoneId}`).emit('arenaCountdown', { remaining: remainingSec });
                this.io.to(`zone_${match.zoneId}`).emit('gameNotification', {
                    msg: `La batalla comienza en ${remainingSec} segundos...`,
                    type: 'info'
                });

                if (now >= match.statusEndTime) {
                    match.status = 'spawn_lock';
                    match.statusEndTime = now + match.spawnLockTime;
                    this.io.to(`zone_${match.zoneId}`).emit('gameNotification', {
                        msg: `¡PREPARADOS! Barrera protectora activa por ${match.spawnLockTime / 1000}s.`,
                        type: 'warning'
                    });
                }
                continue;
            }

            // 2. Barrera de Seguridad (Spawn Lock)
            if (match.status === 'spawn_lock') {
                const remainingLock = Math.max(0, Math.ceil((match.statusEndTime - now) / 1000));
                
                this.io.to(`zone_${match.zoneId}`).emit('arenaCountdown', { remaining: remainingLock, label: 'Barrera' });

                if (now >= match.statusEndTime) {
                    match.status = 'active';
                    match.matchEndTime = now + match.matchDuration;
                    
                    // Descongelar jugadores
                    match.players.forEach(pl => {
                        const pObj = this.state.players[pl.socketId];
                        if (pObj) pObj.isFrozen = false;
                    });

                    this.io.to(`zone_${match.zoneId}`).emit('gameNotification', {
                        msg: `🚨 ¡LUCHEN! Las barreras han caído. 🚨`,
                        type: 'success'
                    });
                }
                continue;
            }

            // 3. Partida Activa
            if (match.status === 'active') {
                // Control del tiempo de la partida
                if (now >= match.matchEndTime) {
                    // Fin del tiempo: Determinar ganador por HP de Nexos
                    const redNexusHp = match.nexuses.red.hp;
                    const blueNexusHp = match.nexuses.blue.hp;
                    let winner = 'draw';
                    if (redNexusHp > blueNexusHp) winner = 'red';
                    else if (blueNexusHp > redNexusHp) winner = 'blue';

                    this.endMatch(matchId, winner);
                    continue;
                }

                // Ataque de Pilares
                match.pillars.forEach(pillar => {
                    if (pillar.hp <= 0) return;

                    let cooldown = 1000;
                    if (pillar.attackType === 'heavy') cooldown = 2000;
                    else if (pillar.attackType === 'area') cooldown = 1500;

                    if (now - pillar.lastAttackTime < cooldown) return;

                    let bestTarget = null;
                    let minDist = pillar.range;

                    match.players.forEach(pl => {
                        const pObj = this.state.players[pl.socketId];
                        if (pObj && !pObj.isDead && pl.team !== pillar.team) {
                            const dist = Math.hypot(pObj.x - pillar.x, pObj.y - pillar.y);
                            if (dist < minDist) {
                                minDist = dist;
                                bestTarget = pObj;
                            }
                        }
                    });

                    if (bestTarget) {
                        pillar.lastAttackTime = now;
                        
                        this.io.to(`zone_${match.zoneId}`).emit('pillarAttack', {
                            pillarId: pillar.id,
                            targetId: bestTarget.socketId,
                            x: pillar.x,
                            y: pillar.y,
                            type: pillar.ammoType,
                            damage: pillar.damage
                        });

                        if (!bestTarget.isInvulnerable) {
                            const dmg = pillar.damage;
                            if (bestTarget.shield >= dmg) {
                                bestTarget.shield -= dmg;
                            } else {
                                bestTarget.hp -= (dmg - bestTarget.shield);
                                bestTarget.shield = 0;
                            }
                            if (bestTarget.hp <= 0) {
                                bestTarget.hp = 0;
                                bestTarget.isDead = true;
                            }
                            bestTarget.lastCombatTime = now;

                            this.io.to(`zone_${match.zoneId}`).emit('playerStatSync', {
                                id: bestTarget.socketId,
                                hp: Math.ceil(bestTarget.hp),
                                shield: Math.ceil(bestTarget.shield),
                                maxHp: bestTarget.maxHp,
                                maxShield: bestTarget.maxShield,
                                isDead: bestTarget.isDead
                            });
                        }
                    }
                });
            }

            this.emitArenaState(matchId);
        }
    }

    handleArenaHit(socketId, data) {
        const match = this.matches.get(data.matchId);
        if (!match || match.status !== 'active') return;

        const p = this.state.players[socketId];
        if (!p || p.isDead) return;

        const dmg = parseFloat(data.damage) || 0;
        if (dmg <= 0) return;

        if (data.entityId === 'nexus_red' || data.entityId === 'nexus_blue') {
            const targetTeam = (data.entityId === 'nexus_red') ? 'red' : 'blue';
            if (p.team === targetTeam) return; 

            const nexus = match.nexuses[targetTeam];
            if (nexus.hp <= 0) return;

            if (nexus.shield >= dmg) {
                nexus.shield -= dmg;
            } else {
                nexus.hp -= (dmg - nexus.shield);
                nexus.shield = 0;
            }

            if (nexus.hp <= 0) {
                nexus.hp = 0;
                this.endMatch(match.id, (targetTeam === 'red') ? 'blue' : 'red');
            }
        } 
        else if (data.entityId.startsWith('pillar_')) {
            const pillar = match.pillars.find(pil => pil.id === data.entityId);
            if (!pillar || pillar.hp <= 0) return;

            if (p.team === pillar.team) return;

            if (pillar.shield >= dmg) {
                pillar.shield -= dmg;
            } else {
                pillar.hp -= (dmg - pillar.shield);
                pillar.shield = 0;
            }
            if (pillar.hp <= 0) {
                pillar.hp = 0;
                this.io.to(`zone_${match.zoneId}`).emit('gameNotification', {
                    msg: `💥 ¡El ${pillar.name} de defensa del equipo ${pillar.team.toUpperCase()} ha sido destruido!`,
                    type: 'warning'
                });
            }
        }

        this.emitArenaState(match.id);
    }

    emitArenaState(matchId) {
        const match = this.matches.get(matchId);
        if (!match) return;

        const now = Date.now();
        const remainingTime = match.status === 'active' 
            ? Math.max(0, Math.ceil((match.matchEndTime - now) / 1000))
            : 0;

        this.io.to(`zone_${match.zoneId}`).emit('arenaStateUpdate', {
            nexuses: match.nexuses,
            remainingTime: remainingTime,
            status: match.status,
            pillars: match.pillars.map(p => ({
                id: p.id,
                hp: p.hp,
                maxHp: p.maxHp,
                shield: p.shield,
                maxShield: p.maxShield
            }))
        });
    }

    endMatch(matchId, winningTeam) {
        const match = this.matches.get(matchId);
        if (!match || match.status === 'finished') return;

        match.status = 'finished';
        Logger.info('ARENA', `Partida ${matchId} finalizada. Ganador: Equipo ${winningTeam.toUpperCase()}`);

        let finishMsg = `🏆 ¡VICTORIA PARA EL EQUIPO ${winningTeam.toUpperCase()}! 🏆`;
        if (winningTeam === 'draw') {
            finishMsg = `⌛ ¡EMPATE! Se acabó el tiempo y ambos nexos siguen en pie. ⌛`;
        }

        this.io.to(`zone_${match.zoneId}`).emit('gameNotification', {
            msg: finishMsg,
            type: 'success'
        });

        this.io.to(`zone_${match.zoneId}`).emit('arenaFinished', { winningTeam: winningTeam });

        // Transportar de vuelta al lobby (Zona 1) después de 5 segundos
        setTimeout(() => {
            const targetZoneId = 1;
            match.players.forEach(async (pl) => {
                const targetSocket = this.io.sockets.sockets.get(pl.socketId);
                const playerObj = this.state.players[pl.socketId];
                if (targetSocket && playerObj) {
                    playerObj.isFrozen = false; // Descongelar por seguridad

                    targetSocket.leave(`zone_${matchId}`);
                    targetSocket.join(`zone_${targetZoneId}`);

                    if (this.state.playersByZone[matchId] && this.state.playersByZone[matchId][pl.socketId]) {
                        delete this.state.playersByZone[matchId][pl.socketId];
                    }
                    if (!this.state.playersByZone[targetZoneId]) {
                        this.state.playersByZone[targetZoneId] = {};
                    }
                    this.state.playersByZone[targetZoneId][pl.socketId] = playerObj;

                    playerObj.zone = targetZoneId;
                    playerObj.x = 2000;
                    playerObj.y = 2000;
                    playerObj.team = null; 

                    targetSocket.emit('changeZoneDone', { zoneId: targetZoneId, x: 2000, y: 2000 });
                    
                    targetSocket.to(`zone_${targetZoneId}`).emit('newPlayer', {
                        id: targetSocket.id,
                        user: playerObj.user,
                        x: playerObj.x,
                        y: playerObj.y,
                        hp: playerObj.hp,
                        maxHp: playerObj.maxHp,
                        sh: playerObj.sh || playerObj.shield,
                        maxSh: playerObj.maxSh || playerObj.maxShield,
                        zone: playerObj.zone,
                        spheres: playerObj.spheres || [],
                        clanTag: playerObj.clanTag || ""
                    });
                }
            });

            this.matches.delete(matchId);
        }, 5000);
    }
}

module.exports = new ArenaManager();
