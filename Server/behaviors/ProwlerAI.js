// ProwlerAI.js (Cerebro Merodeador v1.0)
const BaseAI = require('./BaseAI');

module.exports = class ProwlerAI extends BaseAI {
    constructor(enemy, config, state) {
        super(enemy, config, state);
        
        // Parámetros de patrulla configurables con valores por defecto y sanitización de tipos
        this.patrolRange = config.patrolRange !== undefined ? Number(config.patrolRange) : 300;
        
        // Evitar basura como 150 y forzar fallback
        this.changeTrigger = (config.changeTrigger === 'time' || config.changeTrigger === 'distance') ? config.changeTrigger : 'time';
        this.changeType = (config.changeType === 'random' || config.changeType === 'reverse' || config.changeType === 'orthogonal') ? config.changeType : 'random';
        
        this.changeInterval = config.changeInterval !== undefined ? Number(config.changeInterval) : 4000; // default 4000ms

        // Estado interno del merodeador
        this.currentAngle = Math.random() * Math.PI * 2;
        this.lastChangeTime = Date.now();
        this.lastChangeX = enemy.x;
        this.lastChangeY = enemy.y;
    }

    applyMovementLogic(target, dist, angle, now) {
        if (this.enemy.isHooking) return;

        // Si estamos en combate (target activo), perseguimos al jugador de forma agresiva
        if (target && target.id !== "altar") {
            const speed = this.getSpeed();
            const stopDist = 120;
            if (dist > stopDist) {
                this.enemy.x += Math.cos(angle) * speed;
                this.enemy.y += Math.sin(angle) * speed;
            } else if (dist < stopDist - 20) {
                this.enemy.x -= Math.cos(angle) * (speed * 0.5);
                this.enemy.y -= Math.sin(angle) * (speed * 0.5);
            }
            this.enemy.rotation = angle + Math.PI / 2;
            return;
        }

        // Si no hay target, patrullamos de forma autónoma
        const speed = this.getSpeed();
        let shouldChange = false;

        if (this.changeTrigger === 'time') {
            if (now - this.lastChangeTime >= this.changeInterval) {
                shouldChange = true;
            }
        } else if (this.changeTrigger === 'distance') {
            const traveled = Math.hypot(this.enemy.x - this.lastChangeX, this.enemy.y - this.lastChangeY);
            if (traveled >= this.changeInterval) {
                shouldChange = true;
            }
        }

        // Control territorial (leash / patrol range local) para que no se salga de su área
        const distFromSpawn = Math.hypot(this.enemy.x - this.enemy.startX, this.enemy.y - this.enemy.startY);
        const outOfBounds = distFromSpawn > this.patrolRange;

        if (shouldChange || outOfBounds) {
            if (outOfBounds) {
                // Si se sale del rango, forzar el ángulo apuntando de vuelta al spawn original
                this.currentAngle = Math.atan2(this.enemy.startY - this.enemy.y, this.enemy.startX - this.enemy.x);
            } else {
                // Aplicar el tipo de giro seleccionado
                if (this.changeType === 'random') {
                    this.currentAngle = Math.random() * Math.PI * 2;
                } else if (this.changeType === 'reverse') {
                    this.currentAngle = this.currentAngle + Math.PI;
                } else if (this.changeType === 'orthogonal') {
                    this.currentAngle = this.currentAngle + (Math.random() > 0.5 ? Math.PI / 2 : -Math.PI / 2);
                } else {
                    this.currentAngle = Math.random() * Math.PI * 2;
                }
            }

            // Limitar ángulo en [-PI, PI]
            while (this.currentAngle < -Math.PI) this.currentAngle += Math.PI * 2;
            while (this.currentAngle > Math.PI) this.currentAngle -= Math.PI * 2;

            this.lastChangeTime = now;
            this.lastChangeX = this.enemy.x;
            this.lastChangeY = this.enemy.y;
        }
        // Detección y rebote en límites físicos del mapa
        const maps = (this.state && this.state.SERVER_CONFIG && this.state.SERVER_CONFIG.mapsConfig) ? this.state.SERVER_CONFIG.mapsConfig : {};
        const mapCfg = maps[this.enemy.zone] || {};
        const mapWidth = Number(mapCfg.width) || 4000;
        const mapHeight = Number(mapCfg.height) || 4000;
        const margin = 80;
        let hitBorder = false;

        // Calcular siguiente posición teórica
        let nextX = this.enemy.x + Math.cos(this.currentAngle) * speed;
        let nextY = this.enemy.y + Math.sin(this.currentAngle) * speed;

        if (nextX <= margin) {
            nextX = margin;
            hitBorder = true;
        } else if (nextX >= mapWidth - margin) {
            nextX = mapWidth - margin;
            hitBorder = true;
        }

        if (nextY <= margin) {
            nextY = margin;
            hitBorder = true;
        } else if (nextY >= mapHeight - margin) {
            nextY = mapHeight - margin;
            hitBorder = true;
        }

        if (hitBorder) {
            // Rebotar apuntando hacia el centro del mapa
            this.currentAngle = Math.atan2(mapHeight / 2 - this.enemy.y, mapWidth / 2 - this.enemy.x);
            while (this.currentAngle < -Math.PI) this.currentAngle += Math.PI * 2;
            while (this.currentAngle > Math.PI) this.currentAngle -= Math.PI * 2;

            this.lastChangeTime = now;
            this.lastChangeX = this.enemy.x;
            this.lastChangeY = this.enemy.y;
        }

        // Movimiento paso a paso
        this.enemy.x = nextX;
        this.enemy.y = nextY;
        this.enemy.rotation = this.currentAngle + Math.PI / 2;
    }
};
