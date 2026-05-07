/**
 * BaseSkill.js
 * Clase base para todas las habilidades del servidor.
 * v1.0 - Estructura modular para reducir deuda técnica.
 */

class BaseSkill {
    constructor(name, config = {}) {
        this.name = name;
        this.config = config;
    }

    /**
     * Lógica de ejecución de la habilidad.
     * @param {Object} p - Objeto del jugador que usa la habilidad.
     * @param {Object} data - Datos enviados desde el cliente (pos, target, etc).
     * @param {Object} context - Contexto del servidor (io, state, socket).
     */
    execute(p, data, { io, state, socket }) {
        // Implementar en subclases
    }

    /**
     * Sincronización visual para otros jugadores.
     */
    broadcastUsage(p, data, { io, socket }) {
        io.to(`zone_${p.zone}`).emit('remotePlayerUsedSkill', {
            id: socket.id,
            skillName: this.name,
            targetId: data.targetId || socket.id,
            pos: data.pos || null
        });
    }
}

module.exports = BaseSkill;
