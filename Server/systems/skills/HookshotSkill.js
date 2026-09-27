const BaseSkill = require('./BaseSkill');

class HookshotSkill extends BaseSkill {
    constructor() {
        super("HOOKSHOT");
    }

    execute(p, data, { io, state, socket }) {
        const skillConfig = (state.SERVER_CONFIG?.skillsData?.[this.name] || {});
        const damage = this.getEffectiveAttr(p, skillConfig, 'amount', skillConfig.amount || 300);
        const rawPullSpeed = this.getEffectiveAttr(p, skillConfig, 'pull_speed', skillConfig.pull_speed || 1500);
        const pullSpeed = Math.max(1200, Number(rawPullSpeed) || 1500);

        p._hookshotDamage = damage;
        p._hookshotPullSpeed = pullSpeed;

        this.broadcastUsage(p, data, { io, socket }, damage);
        return true;
    }
}

module.exports = HookshotSkill;
