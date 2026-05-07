const Clan = require('../models/Clan');
const User = require('../models/User');

/**
 * Helper para obtener los datos completos de un clan
 */
async function getClanDataPayload(clanId, state) {
    try {
        const clan = await Clan.findById(clanId)
            .populate('members', 'username gameData.level gameData.clanRole')
            .populate('requests', 'username gameData.level')
            .populate('sentInvites', 'username gameData.level');
        if (!clan) return null;

        const membersWithStatus = clan.members.map(m => {
            const isOnline = Array.from(state.activeSessions.keys()).includes(m.username.toLowerCase());
            
            let role = m.gameData?.clanRole || 'member';
            if (clan.leader && m._id.toString() === clan.leader.toString()) {
                role = 'leader';
            }
            
            return {
                id: m._id,
                username: m.username,
                level: m.gameData?.level || 1,
                role: role,
                online: isOnline
            };
        });

        const requestsData = (clan.requests || []).map(r => ({
            id: r._id,
            username: r.username,
            level: r.gameData?.level || 1
        }));

        const sentInvitesData = (clan.sentInvites || []).map(i => ({
            id: i._id,
            username: i.username,
            level: i.gameData?.level || 1
        }));

        membersWithStatus.sort((a, b) => {
            if (a.online !== b.online) return a.online ? -1 : 1; 
            const weights = { 'leader': 0, 'officer': 1, 'member': 2 };
            return weights[a.role] - weights[b.role];
        });

        return {
            id: clan._id,
            name: clan.name,
            tag: clan.tag,
            leader: clan.leader,
            members: membersWithStatus,
            requests: requestsData,
            sentInvites: sentInvitesData, 
            joinType: clan.joinType || 'open',
            maxMembers: clan.maxMembers || 20
        };
    } catch (e) {
        console.error("Error obteniendo datos de clan:", e);
        return null;
    }
}

/**
 * Registra todos los manejadores de eventos de clan para un socket
 */
function registerClanHandlers(socket, io, state) {
    // ABANDONAR CLAN
    socket.on('leaveClan', async () => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];
        if (!p.clanId) return;

        try {
            const user = await User.findById(socket.dbUser._id);
            const clan = await Clan.findById(p.clanId);
            if (!clan) return;

            clan.members.pull(user._id);
            
            if (clan.members.length === 0) {
                await Clan.deleteOne({ _id: clan._id });
                console.log(`[CLAN] Flota ${clan.name} eliminada (sin miembros).`);
            } else {
                if (clan.leader.toString() === user._id.toString()) {
                    clan.leader = clan.members[0];
                    const newLeader = await User.findById(clan.leader);
                    if (newLeader) {
                        newLeader.gameData.clanRole = 'leader';
                        await newLeader.save();
                    }
                }
                await clan.save();
                
                const payload = await getClanDataPayload(clan._id, state);
                io.to(`clan_${clan._id}`).emit('clanData', payload);
                io.to(`clan_${clan._id}`).emit('clanMemberStatus', { user: user.username, online: false });
            }

            user.gameData.clanId = null;
            user.gameData.clanRole = null;
            await user.save();

            socket.leave(`clan_${p.clanId}`);
            p.clanId = null;
            p.clanTag = ""; 
            io.emit('playerUpdated', { id: socket.id, clanTag: "" }); 
            socket.emit('clanData', null);
            socket.emit('gameNotification', { msg: 'HAS ABANDONADO LA FLOTA', type: 'info' });

        } catch (e) { console.error("Error leaveClan:", e); }
    });

    // DISOLVER CLAN
    socket.on('disbandClan', async () => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];
        if (!p.clanId) return;

        try {
            const clan = await Clan.findById(p.clanId);
            if (!clan) return;

            if (clan.leader.toString() !== socket.dbUser._id.toString()) {
                return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER PUEDE DISOLVER LA FLOTA', type: 'error' });
            }

            io.to(`clan_${clan._id}`).emit('clanData', null);
            io.to(`clan_${clan._id}`).emit('gameNotification', { msg: 'LA FLOTA HA SIDO DISUELTA POR EL LÍDER', type: 'info' });

            await User.updateMany({ "gameData.clanId": clan._id }, { $set: { "gameData.clanId": null, "gameData.clanRole": null } });

            const roomName = `clan_${clan._id}`;
            const room = io.sockets.adapter.rooms.get(roomName);
            if (room) {
                const sids = Array.from(room);
                sids.forEach(sid => {
                    if (state.players[sid]) {
                        state.players[sid].clanId = null;
                        state.players[sid].clanTag = ""; 
                        io.emit('playerUpdated', { id: sid, clanTag: "" }); 
                    }
                    const s = io.sockets.sockets.get(sid);
                    if (s) s.leave(roomName);
                });
            }

            await Clan.deleteOne({ _id: clan._id });
            console.log(`[CLAN] Flota ${clan.name} disuelta por ${socket.dbUser.username}`);
        } catch (e) { console.error("Error disbandClan:", e); }
    });

    // CAMBIAR TIPO DE INGRESO
    socket.on('setClanJoinType', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const { type } = data; 
        if (type !== 'open' && type !== 'invite') return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER PUEDE CAMBIAR ESTO', type: 'error' });

            clan.joinType = type;
            await clan.save();
            
            const payload = await getClanDataPayload(clan._id, state);
            io.to(`clan_${clan._id}`).emit('clanData', payload);
            socket.emit('gameNotification', { msg: `MODO DE INGRESO: ${type.toUpperCase()}`, type: 'success' });
        } catch (e) { console.error("Error setClanJoinType:", e); }
    });

    // EXPULSAR MIEMBRO
    socket.on('kickClanMember', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const { username } = data;
        if (!username) return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER PUEDE EXPULSAR', type: 'error' });

            const targetUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });
            if (!targetUser) return;

            if (targetUser._id.toString() === clan.leader.toString()) return;

            clan.members = clan.members.filter(m => m.toString() !== targetUser._id.toString());
            await clan.save();

            targetUser.gameData.clanId = null;
            targetUser.gameData.clanRole = 'member';
            await targetUser.save();

            const targetSocketId = state.activeSessions.get(username.toLowerCase());
            if (targetSocketId) {
                const targetSocket = io.sockets.sockets.get(targetSocketId);
                if (targetSocket) {
                    targetSocket.leave(`clan_${clan._id}`);
                    if (state.players[targetSocketId]) {
                        state.players[targetSocketId].clanId = null;
                        state.players[targetSocketId].clanTag = ""; 
                        io.emit('playerUpdated', { id: targetSocketId, clanTag: "" }); 
                    }
                    targetSocket.emit('clanData', null);
                    targetSocket.emit('gameNotification', { msg: 'HAS SIDO EXPULSADO DE LA FLOTA', type: 'warning' });
                }
            }

            const payload = await getClanDataPayload(clan._id, state);
            io.to(`clan_${clan._id}`).emit('clanData', payload);
            socket.emit('gameNotification', { msg: `MIEMBRO EXPULSADO: ${username.toUpperCase()}`, type: 'success' });
        } catch (e) { console.error("Error kickClanMember:", e); }
    });

    // GESTIONAR SOLICITUD
    socket.on('handleClanRequest', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const { username, action } = data; 
        if (!username || !action) return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return socket.emit('gameNotification', { msg: 'SOLO EL LÍDER PUEDE GESTIONAR SOLICITUDES', type: 'error' });

            const targetUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });
            if (!targetUser) return;

            clan.requests = clan.requests.filter(r => r.toString() !== targetUser._id.toString());

            if (targetUser.gameData && targetUser.gameData.pendingClanRequests) {
                targetUser.gameData.pendingClanRequests = targetUser.gameData.pendingClanRequests.filter(
                    req => req.id.toString() !== clan._id.toString()
                );
                targetUser.markModified('gameData.pendingClanRequests');
                await targetUser.save();
                
                const targetSocketId = state.activeSessions.get(username.toLowerCase());
                if (targetSocketId) {
                    const targetSocket = io.sockets.sockets.get(targetSocketId);
                    if (targetSocket) targetSocket.emit('inventoryData', { gameData: targetUser.gameData });
                }
            }

            if (action === 'accept') {
                if (clan.members.length >= clan.maxMembers) {
                    return socket.emit('gameNotification', { msg: 'CLAN LLENO', type: 'error' });
                }
                if (!clan.members.includes(targetUser._id)) {
                    clan.members.push(targetUser._id);
                    targetUser.gameData.clanId = clan._id;
                    targetUser.gameData.clanRole = 'member';
                    
                    targetUser.gameData.pendingClanRequests = [];
                    targetUser.gameData.receivedClanInvites = [];
                    targetUser.markModified('gameData.pendingClanRequests');
                    targetUser.markModified('gameData.receivedClanInvites');
                    
                    await targetUser.save();
                    
                    const targetSocketId = state.activeSessions.get(username.toLowerCase());
                    if (targetSocketId) {
                        const targetSocket = io.sockets.sockets.get(targetSocketId);
                        if (targetSocket) {
                            targetSocket.join(`clan_${clan._id}`);
                            if (state.players[targetSocketId]) {
                                state.players[targetSocketId].clanId = clan._id;
                                state.players[targetSocketId].clanTag = clan.tag; 
                                io.emit('playerUpdated', { id: targetSocketId, clanTag: clan.tag }); 
                            }
                            targetSocket.emit('gameNotification', { msg: `┬íHAS SIDO ACEPTADO EN [${clan.tag}]!`, type: 'success' });
                        }
                    }
                }
            }

            await clan.save();
            const payload = await getClanDataPayload(clan._id, state);
            io.to(`clan_${clan._id}`).emit('clanData', payload);
            socket.emit('gameNotification', { msg: `SOLICITUD ${action === 'accept' ? 'ACEPTADA' : 'RECHAZADA'}: ${username.toUpperCase()}`, type: 'success' });
        } catch (e) { console.error("Error handleClanRequest:", e); }
    });

    // CREAR CLAN
    socket.on('createClan', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const { name, tag } = data;
        try {
            const existing = await Clan.findOne({ $or: [{ name }, { tag: tag.toUpperCase() }] });
            if (existing) return socket.emit('gameNotification', { msg: 'NOMBRE O TAG YA REGISTRADO', type: 'error' });

            const user = await User.findById(socket.dbUser._id);
            if (user.gameData.clanId) return socket.emit('gameNotification', { msg: 'YA PERTENECES A UNA FLOTA', type: 'error' });

            const newClan = new Clan({
                name,
                tag: tag.toUpperCase(),
                leader: user._id,
                members: [user._id]
            });
            await newClan.save();

            user.gameData.clanId = newClan._id;
            user.gameData.clanRole = 'leader'; 
            
            user.gameData.pendingClanRequests = [];
            user.gameData.receivedClanInvites = [];
            user.markModified('gameData.pendingClanRequests');
            user.markModified('gameData.receivedClanInvites');
            
            user.markModified('gameData.clanId');
            user.markModified('gameData.clanRole');
            await user.save();

            state.players[socket.id].clanId = newClan._id;
            state.players[socket.id].clanTag = newClan.tag; 
            io.emit('playerUpdated', { id: socket.id, clanTag: newClan.tag }); 
            socket.join(`clan_${newClan._id}`);
            
            const clanData = await getClanDataPayload(newClan._id, state);
            socket.emit('clanData', clanData);
            socket.emit('gameNotification', { msg: `FLOTA [${tag}] FUNDADA CON ├ëXITO`, type: 'success' });
            console.log(`[CLAN] ${user.username} fund├│ ${name} [${tag}]`);
        } catch (e) { console.error("Error createClan:", e); }
    });

    // INVITAR AL CLAN
    socket.on('inviteToClan', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const { username } = data;
        if (!username) return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return socket.emit('gameNotification', { msg: 'SOLO EL L├ìDER PUEDE INVITAR', type: 'error' });

            if (clan.members.length >= (clan.maxMembers || 20)) {
                return socket.emit('gameNotification', { msg: 'FLOTA LLENA', type: 'error' });
            }

            const targetUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });
            if (!targetUser) return socket.emit('gameNotification', { msg: 'PILOTO NO ENCONTRADO', type: 'error' });

            if (targetUser.gameData.clanId) {
                return socket.emit('gameNotification', { msg: 'EL PILOTO YA PERTENECE A UNA FLOTA', type: 'error' });
            }

            if (!targetUser.gameData.receivedClanInvites) targetUser.gameData.receivedClanInvites = [];
            if (targetUser.gameData.receivedClanInvites.some(inv => inv.id.toString() === clan._id.toString())) {
                return socket.emit('gameNotification', { msg: 'YA ENVIASTE UNA INVITACI├ôN A ESTE PILOTO', type: 'info' });
            }

            targetUser.gameData.receivedClanInvites.push({ id: clan._id, tag: clan.tag, name: clan.name });
            targetUser.markModified('gameData.receivedClanInvites');
            await targetUser.save();

            if (!clan.sentInvites) clan.sentInvites = [];
            if (!clan.sentInvites.includes(targetUser._id)) {
                clan.sentInvites.push(targetUser._id);
                await clan.save();
            }

            const targetSocketId = state.activeSessions.get(username.toLowerCase());
            if (targetSocketId) {
                const targetSocket = io.sockets.sockets.get(targetSocketId);
                if (targetSocket) {
                    const targetGD = JSON.parse(JSON.stringify(targetUser.gameData));
                    targetSocket.emit('inventoryData', { player: { gameData: targetGD } });
                    targetSocket.emit('gameNotification', { msg: `┬íHAS SIDO INVITADO A LA FLOTA [${clan.tag}]!`, type: 'info' });
                }
            }

            socket.emit('gameNotification', { msg: `INVITACI├ôN ENVIADA A ${username.toUpperCase()}`, type: 'success' });
            
            const leaderPayload = await getClanDataPayload(clan._id, state);
            socket.emit('clanData', leaderPayload);
        } catch (e) { console.error("Error inviteToClan:", e); }
    });

    // CANCELAR INVITACIÓN
    socket.on('cancelClanInvite', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const { username } = data;
        if (!username) return;

        try {
            const clan = await Clan.findOne({ leader: socket.dbUser._id });
            if (!clan) return;

            const targetUser = await User.findOne({ username: { $regex: new RegExp("^" + username + "$", "i") } });
            if (!targetUser) return;

            if (clan.sentInvites) {
                clan.sentInvites = clan.sentInvites.filter(id => id.toString() !== targetUser._id.toString());
                await clan.save();
            }

            if (targetUser.gameData && targetUser.gameData.receivedClanInvites) {
                targetUser.gameData.receivedClanInvites = targetUser.gameData.receivedClanInvites.filter(inv => inv.id.toString() !== clan._id.toString());
                targetUser.markModified('gameData.receivedClanInvites');
                await targetUser.save();
                
                const targetSocketId = state.activeSessions.get(username.toLowerCase());
                if (targetSocketId) {
                    const targetSocket = io.sockets.sockets.get(targetSocketId);
                    if (targetSocket) targetSocket.emit('inventoryData', { gameData: targetUser.gameData });
                }
            }

            const payload = await getClanDataPayload(clan._id, state);
            socket.emit('clanData', payload);
            socket.emit('gameNotification', { msg: `INVITACI├ôN CANCELADA: ${username.toUpperCase()}`, type: 'warning' });
        } catch (e) { console.error("Error cancelClanInvite:", e); }
    });

    // RESPONDER INVITACIÓN
    socket.on('handleClanInvite', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const { clanId, action } = data; 
        if (!clanId || !action) return;

        try {
            const user = await User.findById(socket.dbUser._id);
            if (!user.gameData.receivedClanInvites) return;

            user.gameData.receivedClanInvites = user.gameData.receivedClanInvites.filter(inv => inv.id.toString() !== clanId.toString());
            user.markModified('gameData.receivedClanInvites');

            if (action === 'accept') {
                if (user.gameData.clanId) return socket.emit('gameNotification', { msg: 'YA PERTENECES A UNA FLOTA', type: 'error' });
                
                const clan = await Clan.findById(clanId);
                if (!clan) return socket.emit('gameNotification', { msg: 'LA FLOTA YA NO EXISTE', type: 'error' });

                if (clan.sentInvites) {
                    clan.sentInvites = clan.sentInvites.filter(id => id.toString() !== user._id.toString());
                    await clan.save();
                }

                if (clan.members.length >= (clan.maxMembers || 20)) {
                    return socket.emit('gameNotification', { msg: 'LA FLOTA EST├ü LLENA', type: 'error' });
                }

                if (!clan.members.includes(user._id)) {
                    clan.members.push(user._id);
                    await clan.save();
                }

                user.gameData.clanId = clan._id;
                user.gameData.clanRole = 'member';
                
                user.gameData.pendingClanRequests = [];
                user.markModified('gameData.pendingClanRequests');
                
                state.players[socket.id].clanId = clan._id;
                socket.join(`clan_${clan._id}`);

                const payload = await getClanDataPayload(clan._id, state);
                io.to(`clan_${clan._id}`).emit('clanData', payload);
                socket.emit('gameNotification', { msg: `┬íBIENVENIDO A [${clan.tag}]!`, type: 'success' });
            }

            await user.save();
            socket.emit('inventoryData', { gameData: user.gameData });
        } catch (e) { console.error("Error handleClanInvite:", e); }
    });

    // OBTENER DATOS DE CLAN
    socket.on('getClanData', async () => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const p = state.players[socket.id];
        if (!p.clanId) return socket.emit('clanData', null);

        try {
            const payload = await getClanDataPayload(p.clanId, state);
            socket.emit('clanData', payload);
        } catch (e) { console.error("Error getClanData:", e); }
    });

    // UNIRSE AL CLAN (Auto-Join o Solicitud)
    socket.on('joinClan', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const { tag } = data;
        try {
            const clan = await Clan.findOne({ tag: tag.toUpperCase() });
            if (!clan) return socket.emit('gameNotification', { msg: 'FLOTA NO ENCONTRADA', type: 'error' });

            const user = await User.findById(socket.dbUser._id);
            if (user.gameData.clanId) return socket.emit('gameNotification', { msg: 'YA PERTENECES A UNA FLOTA', type: 'error' });

            if (clan.members.length >= (clan.maxMembers || 20)) {
                return socket.emit('gameNotification', { msg: 'LA FLOTA EST├ü LLENA (M├üX 20)', type: 'error' });
            }

            if (clan.joinType === 'invite') {
                if (!clan.requests) clan.requests = [];
                if (clan.requests.some(r => r.toString() === user._id.toString())) {
                    return socket.emit('gameNotification', { msg: 'YA ENVIASTE UNA SOLICITUD', type: 'info' });
                }

                if (!user.gameData.pendingClanRequests) user.gameData.pendingClanRequests = [];
                if (user.gameData.pendingClanRequests.length >= 3) {
                    return socket.emit('gameNotification', { msg: 'M├üXIMO 3 SOLICITUDES PENDIENTES', type: 'error' });
                }

                clan.requests.push(user._id);
                await clan.save();

                user.gameData.pendingClanRequests.push({ id: clan._id, tag: clan.tag, name: clan.name });
                user.markModified('gameData.pendingClanRequests');
                await user.save();

                const updatedGameData = JSON.parse(JSON.stringify(user.gameData));
                socket.emit('inventoryData', { player: { gameData: updatedGameData } });

                const payload = await getClanDataPayload(clan._id, state);
                io.to(`clan_${clan._id}`).emit('clanData', payload);

                return socket.emit('gameNotification', { msg: 'SOLICITUD ENVIADA AL L├ìDER', type: 'success' });
            }

            clan.members.push(user._id);
            await clan.save();

            user.gameData.clanId = clan._id;
            user.gameData.clanRole = 'member'; 
            
            user.gameData.pendingClanRequests = [];
            user.gameData.receivedClanInvites = [];
            user.markModified('gameData.pendingClanRequests');
            user.markModified('gameData.receivedClanInvites');
            
            user.markModified('gameData.clanId');
            user.markModified('gameData.clanRole');
            await user.save();

            state.players[socket.id].clanId = clan._id;
            state.players[socket.id].clanTag = clan.tag; 
            io.emit('playerUpdated', { id: socket.id, clanTag: clan.tag }); 
            socket.join(`clan_${clan._id}`);
            
            const payload = await getClanDataPayload(clan._id, state);
            io.to(`clan_${clan._id}`).emit('clanData', payload);
            io.to(`clan_${clan._id}`).emit('clanMemberStatus', { user: user.username, online: true });
        } catch (e) { console.error("Error joinClan:", e); }
    });

    // CANCELAR SOLICITUD
    socket.on('cancelClanRequest', async (data) => {
        if (!socket.dbUser || !state.players[socket.id]) return;
        const { tag } = data;
        if (!tag) return;

        try {
            const clan = await Clan.findOne({ tag: tag.toUpperCase() });
            if (!clan) return;

            const user = await User.findById(socket.dbUser._id);
            if (!user) return;
            
            if (clan.requests) {
                clan.requests = clan.requests.filter(rid => rid.toString() !== user._id.toString());
                await clan.save();
                
                const payload = await getClanDataPayload(clan._id, state);
                io.to(`clan_${clan._id}`).emit('clanData', payload);
            }

            if (user.gameData && user.gameData.pendingClanRequests) {
                user.gameData.pendingClanRequests = user.gameData.pendingClanRequests.filter(req => req.tag !== tag.toUpperCase());
                user.markModified('gameData.pendingClanRequests');
                await user.save();
                
                const updatedGD = JSON.parse(JSON.stringify(user.gameData));
                socket.emit('inventoryData', { player: { gameData: updatedGD } });
            }

            socket.emit('gameNotification', { msg: `SOLICITUD CANCELADA: [${tag.toUpperCase()}]`, type: 'warning' });
        } catch (e) { console.error("Error cancelClanRequest:", e); }
    });
}

module.exports = {
    getClanDataPayload,
    registerClanHandlers
};
