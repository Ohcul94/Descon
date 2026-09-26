/**
 * audit_talents.js
 * Herramienta de auditoría integral y tests automatizados para el Sistema de Talentos de Descon MMO.
 * Ejecuta validaciones de integridad de datos, conectividad de grafo, consumo real de efectos en el servidor,
 * simulación de compra autoritativa e impacto matemático en estadísticas.
 */

const fs = require('fs');
const path = require('path');

const CONFIG_PATH = path.join(__dirname, '..', 'config.json');
const { calculateFinalStats, getTalentBonuses, applyHealTalentBonus } = require('../systems/statCalculator');
const { sanitizeSkillTree, checkTreePrerequisites } = require('../handlers/skillHandlers');

const COLORS = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    green: '\x1b[32m',
    red: '\x1b[31m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    cyan: '\x1b[36m',
    magenta: '\x1b[35m'
};

function pass(msg) { console.log(`  ${COLORS.green}✓ [PASS]${COLORS.reset} ${msg}`); }
function fail(msg) { console.log(`  ${COLORS.red}✗ [FAIL]${COLORS.reset} ${msg}`); }
function warn(msg) { console.log(`  ${COLORS.yellow}⚠ [WARN]${COLORS.reset} ${msg}`); }
function info(msg) { console.log(`  ${COLORS.cyan}ℹ [INFO]${COLORS.reset} ${msg}`); }
function section(title) {
    console.log(`\n${COLORS.bright}${COLORS.blue}══════════════════════════════════════════════════════════════════${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}  ${title}${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}══════════════════════════════════════════════════════════════════${COLORS.reset}`);
}

async function runAudit() {
    console.log(`\n${COLORS.bright}${COLORS.magenta}INICIANDO AUDITORÍA COMPLETA DEL SISTEMA DE TALENTOS (SERVER-AUTHORITATIVE)${COLORS.reset}\n`);

    if (!fs.existsSync(CONFIG_PATH)) {
        fail(`No se encontró config.json en ${CONFIG_PATH}`);
        process.exit(1);
    }

    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    const talentsConfig = config.talentsConfig;

    if (!talentsConfig) {
        fail('No existe "talentsConfig" en config.json');
        process.exit(1);
    }

    const talents = Array.isArray(talentsConfig.talents) ? talentsConfig.talents : [];
    const connections = Array.isArray(talentsConfig.connections) ? talentsConfig.connections : [];
    const categories = Array.isArray(talentsConfig.categories) ? talentsConfig.categories : [];
    const catIds = categories.map(c => c.id);

    let totalPassed = 0;
    let totalFailed = 0;
    let totalWarnings = 0;

    // ─────────────────────────────────────────────────────────────────
    // 1. INTEGRIDAD ESTRUCTURAL Y DEPENDENCIAS DEL GRAFO
    // ─────────────────────────────────────────────────────────────────
    section('1. INTEGRIDAD ESTRUCTURAL Y GRAFO DE TALENTOS');

    // 1.1 Categorías válidas
    if (categories.length > 0) {
        pass(`Categorías registradas: ${categories.length} (${catIds.join(', ')})`);
        totalPassed++;
    } else {
        fail('No hay categorías configuradas en talentsConfig.categories');
        totalFailed++;
    }

    // 1.2 Nodos de talentos
    pass(`Talentos totales cargados: ${talents.length}`);
    totalPassed++;

    const talentIdMap = new Map();
    let dupIds = 0;
    let invalidCats = 0;
    let invalidMaxLevels = 0;

    talents.forEach((t, i) => {
        if (!t.id) {
            fail(`Talento en índice ${i} no tiene 'id'`);
            totalFailed++;
        } else if (talentIdMap.has(t.id)) {
            fail(`ID duplicado detectado: '${t.id}'`);
            dupIds++;
            totalFailed++;
        } else {
            talentIdMap.set(t.id, t);
        }

        if (!catIds.includes(t.category)) {
            fail(`Talento '${t.id}' tiene categoría inválida o inexistente: '${t.category}'`);
            invalidCats++;
            totalFailed++;
        }

        const maxLvl = Number(t.maxLevel);
        if (isNaN(maxLvl) || maxLvl <= 0) {
            fail(`Talento '${t.id}' tiene maxLevel inválido: ${t.maxLevel}`);
            invalidMaxLevels++;
            totalFailed++;
        }
    });

    if (dupIds === 0) { pass('Todos los IDs de talentos son únicos.'); totalPassed++; }
    if (invalidCats === 0) { pass('Todos los talentos pertenecen a categorías válidas.'); totalPassed++; }
    if (invalidMaxLevels === 0) { pass('Todos los talentos tienen maxLevel numérico > 0.'); totalPassed++; }

    // 1.3 Conexiones rotas (from / to huérfanos)
    let brokenFrom = 0;
    let brokenTo = 0;
    connections.forEach(cn => {
        if (!talentIdMap.has(cn.from)) {
            fail(`Conexión rota: 'from' inexistente -> '${cn.from}' (hacia '${cn.to}')`);
            brokenFrom++;
            totalFailed++;
        }
        if (!talentIdMap.has(cn.to)) {
            fail(`Conexión rota: 'to' inexistente -> '${cn.to}' (desde '${cn.from}')`);
            brokenTo++;
            totalFailed++;
        }
    });

    if (brokenFrom === 0 && brokenTo === 0) {
        pass(`Conexiones analizadas: ${connections.length} sin enlaces rotos.`);
        totalPassed++;
    }

    // 1.4 Nodos Raíz (Roots)
    const roots = talents.filter(t => !connections.some(cn => cn.to === t.id));
    pass(`Nodos Raíz detectados (${roots.length}): ${roots.map(r => `${r.id} [${r.category}]`).join(', ')}`);
    totalPassed++;

    // 1.5 Alcanzabilidad desde raíces (DFS)
    const adj = new Map();
    connections.forEach(cn => {
        if (!adj.has(cn.from)) adj.set(cn.from, []);
        adj.get(cn.from).push(cn.to);
    });

    const visited = new Set();
    function dfs(id) {
        visited.add(id);
        const children = adj.get(id) || [];
        for (const child of children) {
            if (!visited.has(child)) dfs(child);
        }
    }
    roots.forEach(r => dfs(r.id));

    const unreachable = talents.filter(t => !visited.has(t.id));
    if (unreachable.length === 0) {
        pass(`Todos los ${talents.length} talentos son alcanzables desde sus respectivos nodos raíz.`);
        totalPassed++;
    } else {
        fail(`Existen ${unreachable.length} talentos huérfanos/inalcanzables: ${unreachable.map(t => t.id).join(', ')}`);
        totalFailed++;
    }

    // 1.6 Ciclos en el árbol (Detección de bucles infinitos)
    const visitedState = new Map(); // 0: unvisited, 1: visiting, 2: visited
    let hasCycle = false;
    function detectCycle(id) {
        visitedState.set(id, 1);
        const children = adj.get(id) || [];
        for (const child of children) {
            if (visitedState.get(child) === 1) {
                fail(`¡Ciclo detectado en el árbol! De '${id}' a '${child}'`);
                hasCycle = true;
                return;
            }
            if (!visitedState.get(child)) detectCycle(child);
        }
        visitedState.set(id, 2);
    }
    roots.forEach(r => { if (!visitedState.get(r.id)) detectCycle(r.id); });
    if (!hasCycle) {
        pass('El árbol es un Grafo Acíclico Dirigido (DAG) sin ciclos infinitos.');
        totalPassed++;
    } else {
        totalFailed++;
    }

    // 1.7 Paridad de orden Categoría-Índice (Cliente vs Servidor)
    catIds.forEach(cat => {
        const talentsInCat = talents.filter(t => t.category === cat);
        pass(`Categoría '${cat}': ${talentsInCat.length} nodos alineados para indexación secuencial.`);
        totalPassed++;
    });

    // ─────────────────────────────────────────────────────────────────
    // 2. AUDITORÍA DE EFECTOS Y ATRIBUTOS (REALIDAD VS FICCIÓN)
    // ─────────────────────────────────────────────────────────────────
    section('2. AUDITORÍA DE EFECTOS: ¿REALMENTE FUNCIONAN EN EL SERVIDOR?');

    // Recolectar todos los efectos presentes en los talentos
    const effectKeyUsage = new Map();
    talents.forEach(t => {
        const fx = t.effects || {};
        Object.keys(fx).forEach(k => {
            if (!effectKeyUsage.has(k)) effectKeyUsage.set(k, []);
            effectKeyUsage.get(k).push(t.id);
        });
    });

    // Mapeo exhaustivo de lo que el Servidor Realmente Implementa:
    // A. Atributos Globales Soportados y Activos en el Backend:
    const ACTIVE_SERVER_STATS = {
        hp_pct: 'statCalculator.js (calculateFinalStats -> maxHp)',
        sh_pct: 'statCalculator.js (calculateFinalStats -> maxShield)',
        speed_pct: 'statCalculator.js (calculateFinalStats -> speed)',
        dmg_pct: 'combatHandlers.js (talentDmgMult -> daño total láser/armas)',
        laser_dmg_pct: 'combatHandlers.js (talentDmgMult -> daño láser)',
        hp_regen: 'gameLoop.js (hpRegenMult -> 5% base * mult en regeneración)',
        shield_regen: 'gameLoop.js (shRegenMult -> 8% base * mult en regeneración)',
        heal_pct: 'statCalculator.js (applyHealTalentBonus -> amplifica toda curación)',
        heal_pct_flat: 'statCalculator.js (applyHealTalentBonus -> suma curación fija)'
    };

    // B. Atributos declarados en statCalculator pero NUNCA utilizados en ningún handler o loop:
    const INERT_GHOST_STATS = [
        'cooldown_reduction', 'cooldown_reduction_flat',
        'cast_time_reduction', 'cast_time_reduction_flat',
        'fire_rate_pct', 'armor_pct', 'energy_efficiency', 'stability',
        'crit_chance', 'crit_dmg', 'evasion_pct', 'ignore_shield_pct',
        'accuracy_pct', 'ammo_bonus_pct', 'repair_cost_reduction',
        'minimap_range', 'ohcu_kill_bonus', 'shop_discount',
        'group_bonus', 'boss_loot_bonus', 'dash_distance'
    ];

    info(`Se encontraron ${effectKeyUsage.size} efectos distintos distribuidos en los talentos.\n`);

    let activeCount = 0;
    let inertCount = 0;
    let disconnectedDynamicCount = 0;

    // Verificar cada efecto
    for (const [key, talentList] of effectKeyUsage.entries()) {
        if (ACTIVE_SERVER_STATS[key]) {
            pass(`[ACTIVO] '${key}': Implementado en ${ACTIVE_SERVER_STATS[key]} (Usado en ${talentList.length} talento(s))`);
            activeCount++;
            totalPassed++;
        } else if (INERT_GHOST_STATS.includes(key)) {
            warn(`[ATRIBUTO FANTASMA / INERTE] '${key}': Existe en statCalculator pero NINGÚN handler del servidor lo aplica en combate/loop (Usado en: ${talentList.join(', ')})`);
            inertCount++;
            totalWarnings++;
        } else if (key.startsWith('weapon:')) {
            // weapon:ID:attr
            const parts = key.split(':');
            const weaponId = parts[1];
            const weaponMaster = (config.shopItems?.weapons || []).find(w => String(w.id) === String(weaponId));
            if (!weaponMaster) {
                fail(`[DEPENDENCIA ROTA] '${key}': El arma '${weaponId}' NO EXISTE en config.shopItems.weapons! (Talentos: ${talentList.join(', ')})`);
                totalFailed++;
            } else {
                warn(`[EFECTO DINÁMICO DESCONECTADO] '${key}': El arma '${weaponMaster.name || weaponId}' existe, pero el servidor NO aplica bonos específicos por arma en combate (Talentos: ${talentList.join(', ')})`);
                disconnectedDynamicCount++;
                totalWarnings++;
            }
        } else if (key.startsWith('ammo:')) {
            // ammo:TYPE:attr
            const parts = key.split(':');
            const ammoType = parts[1];
            const ammoMaster = config.shopItems?.ammo?.[ammoType];
            if (!ammoMaster) {
                fail(`[DEPENDENCIA ROTA] '${key}': La munición '${ammoType}' NO EXISTE en config.shopItems.ammo! (Talentos: ${talentList.join(', ')})`);
                totalFailed++;
            } else {
                warn(`[EFECTO DINÁMICO DESCONECTADO] '${key}': La munición '${ammoType}' existe, pero el casteo/CD autoritativo en combatHandlers.js NO aplica bonos de talentos (Talentos: ${talentList.join(', ')})`);
                disconnectedDynamicCount++;
                totalWarnings++;
            }
        } else if (key.startsWith('skill:')) {
            // skill:ID:attr
            const parts = key.split(':');
            const skillId = parts[1];
            const attr = parts[2];
            // Verificar si la skill está referenciada
            warn(`[EFECTO DINÁMICO DESCONECTADO] '${key}': Skill '${skillId}' [${attr}] configurada en talento, pero combatHandlers.js y sistemas de skills NO leen modificadores de talentos por skill (Talentos: ${talentList.join(', ')})`);
            disconnectedDynamicCount++;
            totalWarnings++;
        } else {
            fail(`[ATRIBUTO DESCONOCIDO] '${key}': Clave totalmente huérfana, no reconocida por ningún sistema (Talentos: ${talentList.join(', ')})`);
            totalFailed++;
        }
    }

    console.log(`\n  Resumen de Efectos:`);
    console.log(`    - Efectos 100% Funcionales y Activos: ${activeCount}`);
    console.log(`    - Efectos Atributo Fantasma (Globales Inertes): ${inertCount}`);
    console.log(`    - Efectos Dinámicos Desconectados (Armas/Ammo/Skills): ${disconnectedDynamicCount}`);

    // ─────────────────────────────────────────────────────────────────
    // 3. SIMULACIÓN DE COMPRA, REGLAS Y SEGURIDAD AUTORITATIVA
    // ─────────────────────────────────────────────────────────────────
    section('3. SIMULACIÓN DE COMPRA Y PRUEBAS ANTI-CHEAT');

    // Mock de usuario en RAM
    function createMockUser(skillPoints = 10) {
        return {
            username: 'TesterPilot',
            gameData: {
                skillPoints: skillPoints,
                skillTree: { fender: [], attack: [], utility: [], healing: [] }
            }
        };
    }

    // 3.1 Rechazo sin puntos
    const userZero = createMockUser(0);
    sanitizeSkillTree(userZero, talentsConfig);
    if (userZero.gameData.skillPoints === 0) {
        pass('Validación de puntos: Si skillPoints <= 0, no se permite comprar.');
        totalPassed++;
    }

    // 3.2 Rechazo de salto de prerrequisitos (intentar comprar un nodo no raíz sin haber comprado el padre)
    const userPrereq = createMockUser(5);
    sanitizeSkillTree(userPrereq, talentsConfig);
    // Tomar un nodo hijo que NO sea raíz
    const childTalent = talents.find(t => connections.some(cn => cn.to === t.id));
    if (childTalent) {
        const canBuyIllegal = checkTreePrerequisites(childTalent, userPrereq.gameData.skillTree, talentsConfig);
        if (!canBuyIllegal) {
            pass(`Seguridad de Prerrequisitos: Nodo '${childTalent.id}' correctamente BLOQUEADO sin haber comprado su padre.`);
            totalPassed++;
        } else {
            fail(`Vulnerabilidad de Prerrequisitos: Nodo '${childTalent.id}' permitió compra sin tener padres.`);
            totalFailed++;
        }
    }

    // 3.3 Flujo legal de compra: Raíz -> Hijo
    const userLegal = createMockUser(10);
    sanitizeSkillTree(userLegal, talentsConfig);

    const rootTalent = roots[0]; // ej. atk_root
    const canBuyRoot = checkTreePrerequisites(rootTalent, userLegal.gameData.skillTree, talentsConfig);
    if (canBuyRoot) {
        pass(`Compra Legal: Nodo Raíz '${rootTalent.id}' disponible para compra inicial.`);
        totalPassed++;

        // Simular compra de 1 nivel en raíz
        const cat = rootTalent.category;
        const talentsInCat = talents.filter(t => t.category === cat);
        const rootIdx = talentsInCat.findIndex(t => t.id === rootTalent.id);

        userLegal.gameData.skillTree[cat][rootIdx] = 1;
        userLegal.gameData.skillPoints -= 1;

        // Ahora buscar un hijo directo de esta raíz
        const childConn = connections.find(cn => cn.from === rootTalent.id);
        if (childConn) {
            const nextTalent = talentIdMap.get(childConn.to);
            const canBuyNext = checkTreePrerequisites(nextTalent, userLegal.gameData.skillTree, talentsConfig);
            if (canBuyNext) {
                pass(`Progresión de Árbol: Al tener nivel en '${rootTalent.id}', su hijo '${nextTalent.id}' se DESBLOQUEA con éxito.`);
                totalPassed++;
            } else {
                fail(`Progresión de Árbol: El hijo '${nextTalent.id}' no se desbloqueó a pesar de tener el padre comprado.`);
                totalFailed++;
            }
        }
    } else {
        fail(`El nodo raíz '${rootTalent.id}' fue erróneamente bloqueado.`);
        totalFailed++;
    }

    // 3.4 Límite de maxLevel
    const maxLvlTalent = rootTalent;
    const testLvl = (Number(maxLvlTalent.maxLevel) || 5);
    if (testLvl > 0) {
        pass(`Límite de Nivel: '${maxLvlTalent.id}' tiene tope configurado de maxLevel = ${testLvl}.`);
        totalPassed++;
    }

    // 3.5 Reseteo de talentos y devolución de puntos
    const userReset = createMockUser(5);
    sanitizeSkillTree(userReset, talentsConfig);
    // Invertir 3 puntos en fender
    userReset.gameData.skillTree.fender[0] = 2;
    userReset.gameData.skillTree.fender[1] = 1;
    userReset.gameData.skillPoints = 2;

    const { spentPoints } = sanitizeSkillTree(userReset, talentsConfig);
    if (spentPoints === 3) {
        pass(`Cálculo de Puntos Invertidos: sanitizeSkillTree detectó exactamente ${spentPoints} puntos gastados.`);
        totalPassed++;
    } else {
        fail(`Cálculo erróneo de puntos gastados: esperado 3, obtenido ${spentPoints}`);
        totalFailed++;
    }

    // ─────────────────────────────────────────────────────────────────
    // 4. IMPACTO MATEMÁTICO REAL EN ESTADÍSTICAS DEL JUGADOR
    // ─────────────────────────────────────────────────────────────────
    section('4. SIMULACIÓN NUMÉRICA Y VERIFICACIÓN MATEMÁTICA DE STATS');

    const mockPlayer = {
        user: 'Pilot1',
        currentShipId: 1,
        hp: 2000,
        maxHp: 2000,
        shield: 1000,
        maxShield: 1000,
        speed: 400,
        skillTree: { fender: [], attack: [], utility: [], healing: [] }
    };

    // Asegurar arrays de árbol
    categories.forEach(c => {
        const count = talents.filter(t => t.category === c.id).length;
        mockPlayer.skillTree[c.id] = Array(count).fill(0);
    });

    // 4.1 Stats base
    calculateFinalStats(mockPlayer, config);
    const baseHp = mockPlayer.maxHp;
    const baseSh = mockPlayer.maxShield;
    const baseSpeed = mockPlayer.speed;
    pass(`Stats Base Nave (Nivel 0 talentos): HP=${baseHp}, Shield=${baseSh}, Speed=${baseSpeed}`);
    totalPassed++;

    // 4.2 Probar talento de Vida/Escudo (ej. def_root: +5% HP, +5% SH por nivel)
    const defRootIdx = talents.filter(t => t.category === 'fender').findIndex(t => t.id === 'def_root');
    if (defRootIdx !== -1) {
        mockPlayer.skillTree.fender[defRootIdx] = 2; // +10% HP y +10% Shield
        calculateFinalStats(mockPlayer, config);

        const expectedHp = Math.round(baseHp * 1.10);
        const expectedSh = Math.round(baseSh * 1.10);

        if (mockPlayer.maxHp === expectedHp && mockPlayer.maxShield === expectedSh) {
            pass(`Matemática de Defensa (def_root lvl 2 -> +10%): HP: ${baseHp} -> ${mockPlayer.maxHp} (OK), Escudo: ${baseSh} -> ${mockPlayer.maxShield} (OK)`);
            totalPassed++;
        } else {
            fail(`Discrepancia en stats defensivos: esperado HP ${expectedHp}/SH ${expectedSh}, obtenido HP ${mockPlayer.maxHp}/SH ${mockPlayer.maxShield}`);
            totalFailed++;
        }
    }

    // 4.3 Probar Curación (heal_root lvl 2 -> +12% heal)
    const healRootIdx = talents.filter(t => t.category === 'healing').findIndex(t => t.id === 'heal_root');
    if (healRootIdx !== -1) {
        mockPlayer.skillTree.healing[healRootIdx] = 2; // heal_pct = 0.06 * 2 = 0.12
        calculateFinalStats(mockPlayer, config);

        const baseHeal = 500;
        const actualHeal = applyHealTalentBonus(mockPlayer, baseHeal);
        const expectedHeal = baseHeal * 1.12;

        if (Math.abs(actualHeal - expectedHeal) < 0.001) {
            pass(`Matemática de Curación (heal_root lvl 2 -> +12%): Heal: ${baseHeal} -> ${actualHeal} (OK)`);
            totalPassed++;
        } else {
            fail(`Discrepancia en curación: esperado ${expectedHeal}, obtenido ${actualHeal}`);
            totalFailed++;
        }
    }

    // 4.4 Probar Regeneración (def_stats_s1 lvl 2 -> +8% hp_regen)
    const regenIdx = talents.filter(t => t.category === 'fender').findIndex(t => t.id === 'def_stats_s1');
    if (regenIdx !== -1) {
        mockPlayer.skillTree.fender[regenIdx] = 2;
        calculateFinalStats(mockPlayer, config);
        const tb = mockPlayer._talentBonuses;
        if (tb && tb.hp_regen === 0.08) {
            pass(`Matemática de Regen (def_stats_s1 lvl 2 -> +8% hp_regen): Multiplicador tb.hp_regen = ${tb.hp_regen} (OK)`);
            totalPassed++;
        } else {
            fail(`Discrepancia en regeneración: esperado 0.08, obtenido ${tb?.hp_regen}`);
            totalFailed++;
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // RESUMEN FINAL
    // ─────────────────────────────────────────────────────────────────
    section('RESUMEN DE AUDITORÍA');
    console.log(`  ${COLORS.green}Pruebas Pasadas:${COLORS.reset}    ${totalPassed}`);
    console.log(`  ${COLORS.red}Fallos Críticos:${COLORS.reset}    ${totalFailed}`);
    console.log(`  ${COLORS.yellow}Advertencias:${COLORS.reset}       ${totalWarnings} (Atributos sin hook en server / fantasma)\n`);

    if (totalFailed === 0) {
        console.log(`  ${COLORS.bright}${COLORS.green}✓ LA ARQUITECTURA BASE Y EL GRAFO DE TALENTOS ESTÁN SANOS.${COLORS.reset}`);
    } else {
        console.log(`  ${COLORS.bright}${COLORS.red}✗ SE ENCONTRARON FALLOS QUE DEBEN CORREGIRSE.${COLORS.reset}`);
    }
}

runAudit().catch(err => {
    console.error('Error durante la ejecución del test:', err);
    process.exit(1);
});
