const BaseSkill = require('./BaseSkill');

class BuffSkill extends BaseSkill {
    constructor(name) {
        super(name);
    }

    execute(p, data, { io, state, socket }) {
        // En este MMO, habilidades como REFLECT, TURBO o DASH 
        // dependen fuertemente de la sincronización visual para que otros las vean.
        
        // v262.50: Sincronización de Buffs
        if (this.name === "REFLECT-Ω") {
            p.reflectActive = true;
            setTimeout(() => { p.reflectActive = false; }, 5000); // Duración estimada
        }

        this.broadcastUsage(p, data, { io, socket });
    }
}

module.exports = BuffSkill;
