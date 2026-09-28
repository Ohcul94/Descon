// Server/behaviors/mechanics/StrangeDimensionMechanics.js
// v900.0: Mecánica Defensiva/Mística - Dimensión Extraña (Strange Dimension)

module.exports = {
    _handleStrangeDimensionLogic: function(mech, mId, target, dist, now, io, players) {
        if (!this.enemy.strangeDimensionState) {
            this.enemy.strangeDimensionState = {};
        }
        let state = this.enemy.strangeDimensionState[mId];
        if (!state) {
            state = {
                isCharging: false,
                isActive: false,
                chargeEndTime: 0,
                activeEndTime: 0,
                nextShotTime: 0
            };
            this.enemy.strangeDimensionState[mId] = state;
        }

        const cd = Number(mech.cooldown || 25000);
        const castMs = Number(mech.castTimeMs || 1000);
        const durationMs = Number(mech.duration || 5.0) * 1000.0;
        const roomName = `zone_${this.enemy.zoneId || 0}`;

        // 1. Durante la carga / casteo
        if (state.isCharging) {
            if (now >= state.chargeEndTime) {
                state.isCharging = false;
                state.isActive = true;
                state.activeEndTime = now + durationMs;
                state.nextShotTime = state.activeEndTime + cd;

                // Emitir activación de la dimensión a los clientes
                if (io) {
                    io.to(roomName).emit('enemy_action', {
                        id: this.enemy.id,
                        action: 'strange_dimension_start',
                        type: 'strange_dimension',
                        duration: durationMs / 1000.0,
                        x: this.enemy.x,
                        y: this.enemy.y
                    });
                }
            }
            return true; // Ocupado
        }

        // 2. Mientras la dimensión está activa
        if (state.isActive) {
            if (now >= state.activeEndTime) {
                state.isActive = false;
                if (io) {
                    io.to(roomName).emit('enemy_action', {
                        id: this.enemy.id,
                        action: 'strange_dimension_expire',
                        type: 'strange_dimension'
                    });
                }
            }
            return true; // Sigue activa
        }

        // 3. Inicio de la mecánica si no está en cooldown
        if (now >= state.nextShotTime) {
            const startDelay = Number(mech.startDelay || 0);
            if (!state.delayEndTime) {
                state.delayEndTime = now + startDelay;
                return true;
            }
            if (now < state.delayEndTime) return true;

            state.delayEndTime = 0;
            state.isCharging = true;
            state.chargeEndTime = now + castMs;

            if (io) {
                io.to(roomName).emit('enemy_action', {
                    id: this.enemy.id,
                    action: 'strange_dimension_charge',
                    type: 'strange_dimension',
                    castMs: castMs,
                    silent: true
                });
            }
            return true;
        }

        return false;
    }
};
