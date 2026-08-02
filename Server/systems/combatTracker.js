const Logger = require('../utils/logger');

function initCombatTracker(state) {
    state.combatTracker = {};
    state._combatMeterBroadcastCounter = 0;
}

function getPartyOrId(p, state) {
    const pUid = p.dbId || (p.id ? p.id.toString() : null);
    if (!pUid) return null;
    const partyId = state.playerParty && state.playerParty[pUid];
    return partyId || pUid;
}

function ensureGroup(groupId, p, state) {
    if (!state.combatTracker[groupId]) {
        state.combatTracker[groupId] = {
            startTime: Date.now(),
            zone: p.zone,
            members: {}
        };
    }
    const group = state.combatTracker[groupId];
    const pUid = p.dbId || (p.id ? p.id.toString() : null);
    if (!pUid) return null;
    if (!group.members[pUid]) {
        group.members[pUid] = {
            name: p.user || p.username || 'DESCONOCIDO',
            damageDone: 0,
            damageTaken: 0,
            healingDone: 0,
            healingReceived: 0
        };
    }
    return group;
}

function trackDamageDealt(attackerSocketId, targetId, amount, type, state) {
    if (!amount || amount <= 0) return;
    const p = state.players[attackerSocketId];
    if (!p) return;
    const groupId = getPartyOrId(p, state);
    if (!groupId) return;
    const group = ensureGroup(groupId, p, state);
    if (!group) return;
    const pUid = p.dbId || (p.id ? p.id.toString() : null);
    if (!pUid || !group.members[pUid]) return;
    group.members[pUid].damageDone += Math.round(amount);
}

function trackDamageTaken(victimSocketId, attackerId, amount, type, state) {
    if (!amount || amount <= 0) return;
    const p = state.players[victimSocketId];
    if (!p) return;
    const groupId = getPartyOrId(p, state);
    if (!groupId) return;
    const group = ensureGroup(groupId, p, state);
    if (!group) return;
    const pUid = p.dbId || (p.id ? p.id.toString() : null);
    if (!pUid || !group.members[pUid]) return;
    group.members[pUid].damageTaken += Math.round(amount);
}

function trackHealingDone(healerSocketId, targetId, amount, type, state) {
    if (!amount || amount <= 0) return;
    const p = state.players[healerSocketId];
    if (!p) return;
    const groupId = getPartyOrId(p, state);
    if (!groupId) return;
    const group = ensureGroup(groupId, p, state);
    if (!group) return;
    const pUid = p.dbId || (p.id ? p.id.toString() : null);
    if (!pUid || !group.members[pUid]) return;
    group.members[pUid].healingDone += Math.round(amount);
    // v400.60: Acumulador persistente para target "mayor curación" (Sambullida)
    p.healingDoneTotal = (p.healingDoneTotal || 0) + Math.round(amount);

    if (targetId && targetId !== healerSocketId) {
        const target = state.players[targetId];
        if (target) {
            const tGroupId = getPartyOrId(target, state);
            if (tGroupId === groupId) {
                const tUid = target.dbId || (target.id ? target.id.toString() : null);
                if (tUid && group.members[tUid]) {
                    group.members[tUid].healingReceived += Math.round(amount);
                }
            }
        }
    }
}

function trackHealingReceived(victimSocketId, amount, state) {
    if (!amount || amount <= 0) return;
    const p = state.players[victimSocketId];
    if (!p) return;
    const groupId = getPartyOrId(p, state);
    if (!groupId) return;
    const group = ensureGroup(groupId, p, state);
    if (!group) return;
    const pUid = p.dbId || (p.id ? p.id.toString() : null);
    if (!pUid || !group.members[pUid]) return;
    group.members[pUid].healingReceived += Math.round(amount);
}

function broadcastCombatMeterUpdates(io, state) {
    state._combatMeterBroadcastCounter = (state._combatMeterBroadcastCounter || 0) + 1;
    if (state._combatMeterBroadcastCounter % 2 !== 0) return;

    const now = Date.now();
    for (const groupId in state.combatTracker) {
        const group = state.combatTracker[groupId];
        if (!group || !group.members) continue;

        let hasRecentActivity = false;
        for (const uid in group.members) {
            const m = group.members[uid];
            if (m.damageDone > 0 || m.damageTaken > 0 || m.healingDone > 0) {
                hasRecentActivity = true;
                break;
            }
        }
        if (!hasRecentActivity) continue;

        const elapsed = (now - group.startTime) / 1000;
        const payload = { members: {}, elapsed: Math.round(elapsed * 10) / 10 };

        for (const uid in group.members) {
            const m = group.members[uid];
            payload.members[uid] = {
                n: m.name,
                dd: m.damageDone,
                dt: m.damageTaken,
                hd: m.healingDone,
                hr: m.healingReceived
            };
        }

        const isParty = state.parties && state.parties[groupId];
        if (isParty) {
            for (const memberUid of isParty.members) {
                const memberPlayer = Object.values(state.players).find(p => {
                    const pUid = p.dbId || (p.id ? p.id.toString() : null);
                    return pUid === memberUid;
                });
                if (memberPlayer) {
                    io.to(memberPlayer.socketId).emit('combatMeterUpdate', payload);
                }
            }
        } else {
            const soloPlayer = Object.values(state.players).find(p => {
                const pUid = p.dbId || (p.id ? p.id.toString() : null);
                return pUid === groupId;
            });
            if (soloPlayer) {
                io.to(soloPlayer.socketId).emit('combatMeterUpdate', payload);
            }
        }
    }
}

function resetCombatGroup(groupId, state) {
    if (state.combatTracker[groupId]) {
        state.combatTracker[groupId].startTime = Date.now();
        for (const uid in state.combatTracker[groupId].members) {
            const m = state.combatTracker[groupId].members[uid];
            m.damageDone = 0;
            m.damageTaken = 0;
            m.healingDone = 0;
            m.healingReceived = 0;
        }
    }
}

function getGroupData(groupId, state) {
    return state.combatTracker[groupId] || null;
}

function cleanupEmptyGroups(state) {
    const now = Date.now();
    for (const groupId in state.combatTracker) {
        const group = state.combatTracker[groupId];
        if (!group || !group.members) continue;
        const hasAnyActivity = Object.values(group.members).some(m =>
            m.damageDone > 0 || m.damageTaken > 0 || m.healingDone > 0
        );
        if (!hasAnyActivity && (now - group.startTime) > 300000) {
            delete state.combatTracker[groupId];
        }
    }
}

module.exports = {
    initCombatTracker,
    trackDamageDealt,
    trackDamageTaken,
    trackHealingDone,
    trackHealingReceived,
    broadcastCombatMeterUpdates,
    resetCombatGroup,
    getGroupData,
    cleanupEmptyGroups
};
