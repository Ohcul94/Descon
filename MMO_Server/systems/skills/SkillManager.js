/**
 * SkillManager.js
 * Orquestador de habilidades. Centraliza la ejecución y el registro.
 */

class SkillManager {
    constructor() {
        this.skills = new Map();
    }

    registerSkill(skillInstance) {
        this.skills.set(skillInstance.name, skillInstance);
    }

    useSkill(skillName, player, data, context) {
        const skill = this.skills.get(skillName);
        if (skill) {
            skill.execute(player, data, context);
            return true;
        }
        return false;
    }
}

// Singleton para fácil acceso
module.exports = new SkillManager();
