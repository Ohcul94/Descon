const BaseSkill = require('./BaseSkill');

class BuffSkill extends BaseSkill {
    constructor(name) {
        super(name);
    }

    execute(p, data, { io, state, socket }) {
        // En este MMO, habilidades como REFLECT, TURBO o DASH 
        // dependen fuertemente de la sincronización visual para que otros las vean.

        // v262.50 / v266.70: REFLECT aplica al objetivo resuelto (self o aliado/enemigo)
        if (this.name === "REFLECT-OMEGA") {
            const res = this.getTarget(p, data, state, socket);
            if (!res) return;
            const { target } = res;

            const skillConfig = (state.SERVER_CONFIG && state.SERVER_CONFIG.skillsData)
                ? state.SERVER_CONFIG.skillsData[this.name]
                : {};
            let durationMs = skillConfig.duration !== undefined ? skillConfig.duration : 3000;
            if (durationMs < 1000) durationMs = durationMs * 1000;

            const mult = skillConfig.reflect_mult !== undefined ? skillConfig.reflect_mult : 0.8;

            target.reflectActive = true;
            target.reflectMult = mult;
            if (target._reflectTimeout) clearTimeout(target._reflectTimeout);
            target._reflectTimeout = setTimeout(() => {
                target.reflectActive = false;
                target.reflectMult = undefined;
                target._reflectTimeout = null;
            }, durationMs);

            // Broadcast con el target resuelto (no el raw data.targetId)
            const resolvedTargetId = (target === p)
                ? socket.id
                : (target.socketId || target.id || data.targetId || socket.id);
            this.broadcastUsage(p, { ...data, targetId: resolvedTargetId }, { io, socket });
            return;
        }

        // TURBO-IMPULSO, HYPER-DASH y otros buffs: solo broadcast visual
        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = BuffSkill;
