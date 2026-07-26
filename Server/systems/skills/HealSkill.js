const BaseSkill = require('./BaseSkill');
const combatTracker = require('../combatTracker');

class HealSkill extends BaseSkill {
    constructor(name) {
        super(name);
    }

    execute(p, data, { io, state, socket }) {
        const res = this.getTarget(p, data, state, socket);
        if (!res) return;
        const { target } = res;
        
        const powerValue = data.powerValue || 0;
        let actual_val = 0;

        if (this.name === "ESCUDO CELULAR" || this.name === "FORTALEZA-X") {
            const ms = target.maxShield || 2000;
            const oldS = target.shield || 0;
            target.shield = Math.min(oldS + powerValue, ms);
            actual_val = target.shield - oldS;
        } else {
            // HP: AUTO-REPARACIÓN, NANO-REGENERACIÓN
            const maps = (state.SERVER_CONFIG && state.SERVER_CONFIG.mapsConfig) ? state.SERVER_CONFIG.mapsConfig : {};
            const mapCfg = maps[target.zone] || maps[target.zone.toString()];
            const healPenaltyMech = (mapCfg && Array.isArray(mapCfg.ambience)) ? mapCfg.ambience.find(a => a.type === 'healing_penalty') : null;
            let finalPower = powerValue;
            if (healPenaltyMech) {
                if (healPenaltyMech.penaltyPercentage !== undefined && healPenaltyMech.penaltyPercentage !== "") {
                    const pct = parseFloat(healPenaltyMech.penaltyPercentage) || 0;
                    finalPower = finalPower * (1 - pct / 100);
                }
                if (healPenaltyMech.penaltyFixed !== undefined && healPenaltyMech.penaltyFixed !== "") {
                    const fixed = parseFloat(healPenaltyMech.penaltyFixed) || 0;
                    finalPower = Math.max(0, finalPower - fixed);
                }
            }

            const mh = target.maxHp || 3000;
            const oldH = target.hp || 0;
            target.hp = Math.min(oldH + finalPower, mh);
            actual_val = target.hp - oldH;
        }

        // v266.360: Stacks y temporizador de curación para el HUD de estados
        target.healEndTime = Date.now() + 5000;
        target.healStacks = Math.min((target.healStacks || 0) + 1, 5);

        if (actual_val > 0 && target.socketId) {
            combatTracker.trackHealingDone(p.socketId || socket.id, target.socketId, actual_val, 'skill_heal', state);
        }

        if (target.socketId) {
            io.to(`zone_${target.zone}`).emit('playerStatSync', {
                id: target.socketId,
                hp: Math.ceil(target.hp),
                shield: Math.ceil(target.shield),
                isDead: target.hp <= 0
            });
        }
        
        this.broadcastUsage(p, data, { io, socket }, actual_val);
    }
}

module.exports = HealSkill;
