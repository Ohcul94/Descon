/**
 * statCalculator.js
 * Calcula las estadísticas finales de un jugador sumando base + ítems + habilidades.
 */

function calculateFinalStats(player, config) {
    if (!player || !config) return;

    // 1. Obtener Base de la Nave
    const shipId = player.currentShipId || 1;
    const model = config.shipModels.find(m => m.id === shipId);
    
    let baseHp = 2000;
    let baseShield = 1000;
    let baseSpeed = 400;

    if (model) {
        baseHp = model.hp || 2000;
        baseShield = model.shield || 1000;
        baseSpeed = model.speed || 400;
    }

    // 2. Sumar ítems equipados (Baterías de vida, Escudos, Motores)
    let itemHp = 0;
    let itemShield = 0;
    let itemSpeed = 0;

    if (player.equipped) {
        // Escudos (Slot 's')
        if (Array.isArray(player.equipped.s)) {
            player.equipped.s.forEach(item => {
                itemShield += (item.base || 0);
            });
        }
        // Motores (Slot 'e')
        if (Array.isArray(player.equipped.e)) {
            player.equipped.e.forEach(item => {
                itemSpeed += (item.base || 0);
            });
        }
        // En el futuro se pueden sumar HP de módulos extra (Slot 'x')
        if (Array.isArray(player.equipped.x)) {
            player.equipped.x.forEach(item => {
                itemHp += (item.base || 0);
            });
        }
    }

    // 3. Aplicar Bonificaciones de Habilidades (Skill Tree)
    // Engineering[0] = HP %, Engineering[1] = Shield %
    const eng = player.skillTree?.engineering || [0, 0, 0, 0, 0, 0, 0, 0];
    const hpBonus = 1.0 + ((eng[0] || 0) * 0.02); // 2% por punto
    const shBonus = 1.0 + ((eng[1] || 0) * 0.02); // 2% por punto

    // 4. Calcular Totales Finales
    player.maxHp = Math.ceil((baseHp + itemHp) * hpBonus);
    player.maxShield = Math.ceil((baseShield + itemShield) * shBonus);
    player.speed = baseSpeed + itemSpeed;

    // Sanity Check: Mantener vida actual dentro de los límites
    if (player.hp > player.maxHp) player.hp = player.maxHp;
    if (player.shield > player.maxShield) player.shield = player.maxShield;

    // Guardar bases para referencia si es necesario
    player.baseHp = baseHp;
    player.baseShield = baseShield;
}

module.exports = { calculateFinalStats };
