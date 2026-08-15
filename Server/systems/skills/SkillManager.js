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
        if (!skill) return false;

        // v600.0: Validar requisitos de la habilidad (nivel, misión, desbloqueo)
        try {
            const { getSkillMasterConfig, checkRequirements } = require('../equipRequirements');
            const serverConfig = (context && context.state) ? context.state.SERVER_CONFIG : null;
            const cfg = getSkillMasterConfig(skillName, serverConfig);
            if (cfg && Array.isArray(cfg.config.requirements) && cfg.config.requirements.length > 0) {
                const reqCheck = checkRequirements(player, cfg.config.requirements, serverConfig);
                if (!reqCheck.ok) {
                    if (context && context.socket) {
                        context.socket.emit('gameNotification', { msg: `HABILIDAD BLOQUEADA: ${reqCheck.msg}`, type: 'error' });
                    }
                    return false;
                }
            }
        } catch (e) {
            // Si falla la validación, se permite el uso (retrocompatibilidad)
        }

        skill.execute(player, data, context);
        return true;
    }
}

// Singleton para fácil acceso
module.exports = new SkillManager();
