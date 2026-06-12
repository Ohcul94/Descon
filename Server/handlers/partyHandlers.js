const Logger = require('../utils/logger');

function registerPartyHandlers(socket, io, state) {
    const { players, parties, playerParty } = state;

    // SISTEMA DE PARTIES (GRUPOS) v63.1 - Con guardas anti-crash
    socket.on('inviteToParty', (targetName) => {
        try {
            if (!targetName || typeof targetName !== 'string') return;
            const cleanTarget = targetName.trim().toLowerCase();
            
            // Buscar el piloto en la lista oficial de jugadores del juego
            const targetPlayer = Object.values(players).find(p => p.user && p.user.toLowerCase() === cleanTarget);
            if (!targetPlayer) return socket.emit('authError', 'PILOTO NO ENCONTRADO O FUERA DE LÍNEA');

            const targetSocket = io.sockets.sockets.get(targetPlayer.socketId);
            if (!targetSocket) return socket.emit('authError', 'PILOTO NO ENCONTRADO O FUERA DE LÍNEA');
            if (targetSocket.id === socket.id) return socket.emit('authError', 'NO PUEDES INVITARTE A TI MISMO');
            if (!players[socket.id]) return;

            targetSocket.emit('partyInvitation', {
                from: players[socket.id].user || 'Desconocido',
                fromId: socket.id
            });
        } catch (e) { console.error("Error en inviteToParty:", e); }
    });

    socket.on('acceptParty', (leaderSid) => {
        try {
            const leaderSocket = io.sockets.sockets.get(leaderSid);
            if (!leaderSocket || !leaderSocket.dbUser || !socket.dbUser) return socket.emit('authError', 'PILOTO NO DISPONIBLE');

            const leaderUid = leaderSocket.dbUser._id.toString();
            const myUid = socket.dbUser._id.toString();

            let partyId = playerParty[leaderUid];
            if (!partyId) {
                // Crear nueva party
                partyId = leaderUid;
                parties[partyId] = { id: partyId, members: [leaderUid], names: [leaderSocket.dbUser.username.toUpperCase()] };
                playerParty[leaderUid] = partyId;
            }

            if (parties[partyId].members.includes(myUid)) return;
            if (parties[partyId].members.length >= 8) return socket.emit('authError', 'EL GRUPO ESTÁ LLENO (MAX 8)');

            parties[partyId].members.push(myUid);
            parties[partyId].names.push(socket.dbUser.username.toUpperCase());
            playerParty[myUid] = partyId;

            io.emit('partyUpdate', parties[partyId]);
            io.emit('chatMessage', {
                sender: 'SYSTEM', msg: `${socket.dbUser.username.toUpperCase()} se ha unido al grupo.`, channel: 'team', senderId: 'server'
            });
        } catch (e) {
            console.error("Error en acceptParty:", e);
        }
    });

    socket.on('leaveParty', () => {
        try {
            if (!socket.dbUser) return;
            const myUid = socket.dbUser._id.toString();
            const partyId = playerParty[myUid];
            if (!partyId || !parties[partyId]) return;

            const name = socket.dbUser.username.toUpperCase();
            parties[partyId].members = parties[partyId].members.filter(m => m !== myUid);
            parties[partyId].names = parties[partyId].names.filter(n => n !== name);

            if (parties[partyId].members.length <= 1) {
                parties[partyId].members.forEach(m => delete playerParty[m]);
                delete parties[partyId];
                io.emit('partyUpdate', null);
            } else {
                io.emit('partyUpdate', parties[partyId]);
            }
            delete playerParty[myUid];
            socket.emit('partyUpdate', null);
        } catch (e) {
            console.error("Error en leaveParty:", e);
        }
    });

    socket.on('kickFromParty', (targetUid) => {
        try {
            if (!socket.dbUser) return;
            const myUid = socket.dbUser._id.toString();
            const partyId = playerParty[myUid];
            
            // Solo el líder puede kickear (id de la party == líderUid)
            if (!partyId || partyId !== myUid || !parties[partyId]) return;
            if (targetUid === myUid) return; // No se puede kickear a sí mismo

            const targetIndex = parties[partyId].members.indexOf(targetUid);
            if (targetIndex === -1) return;

            parties[partyId].members.splice(targetIndex, 1);
            parties[partyId].names.splice(targetIndex, 1);
            delete playerParty[targetUid];

            if (parties[partyId].members.length <= 1) {
                parties[partyId].members.forEach(m => delete playerParty[m]);
                delete parties[partyId];
                io.emit('partyUpdate', null);
            } else {
                io.emit('partyUpdate', parties[partyId]);
            }
            
            // Avisar específicamente al expulsado
            const targetSocketId = Object.keys(players).find(sid => players[sid].dbId === targetUid);
            if (targetSocketId) io.to(targetSocketId).emit('partyUpdate', null);
            
        } catch (e) {
            console.error("Error en kickFromParty:", e);
        }
    });
}

module.exports = { registerPartyHandlers };
