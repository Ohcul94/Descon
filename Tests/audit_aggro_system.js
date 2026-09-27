/**
 * audit_aggro_system.js
 * Test Suite de Auditoría para el Sistema de Agro y Amenaza AAA (Descon MMORPG).
 * Ubicación: E:\Descon\Tests\audit_aggro_system.js
 */

const fs = require('fs');
const path = require('path');
const { ThreatTable, DEFAULT_AGGRO_CONFIG } = require('../Server/systems/ThreatTable');
const BaseAI = require('../Server/behaviors/BaseAI');
const BossAI = require('../Server/behaviors/BossAI');

const COLORS = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    green: '\x1b[32m',
    red: '\x1b[31m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    cyan: '\x1b[36m'
};

function pass(msg) { console.log(`  ${COLORS.green}✓ [PASS]${COLORS.reset} ${msg}`); }
function fail(msg) { console.log(`  ${COLORS.red}✗ [FAIL]${COLORS.reset} ${msg}`); }
function section(title) {
    console.log(`\n${COLORS.bright}${COLORS.blue}══════════════════════════════════════════════════════════════════${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}  ${title}${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}══════════════════════════════════════════════════════════════════${COLORS.reset}`);
}

let passed = 0;
let failed = 0;

function assert(condition, message) {
    if (condition) {
        pass(message);
        passed++;
    } else {
        fail(message);
        failed++;
    }
}

section("1. INICIALIZACIÓN Y CONFIGURACIÓN DEL SISTEMA DE AGRO");

const mockEnemy = {
    id: "mob_1",
    type: 1,
    zone: 2,
    x: 1000,
    y: 1000,
    hp: 10000,
    maxHp: 10000,
    shield: 0,
    maxShield: 0,
    config: {
        speed: 3.5,
        visionRange: 800,
        leashRange: 1500
    }
};

const mockState = {
    SERVER_CONFIG: {
        aggroConfig: { ...DEFAULT_AGGRO_CONFIG },
        enemyModels: {}
    },
    players: {},
    enemies: {},
    playerParty: {},
    parties: {}
};

const threatTable = new ThreatTable(mockEnemy, mockState);
assert(threatTable !== null, "Instancia de ThreatTable creada correctamente");
assert(threatTable.getConfig().enabled === true, "Sistema de agro habilitado por defecto");
assert(threatTable.getConfig().damageThreatMultiplier === 1.0, "Multiplicador de daño base = 1.0");
assert(threatTable.getConfig().healingThreatMultiplier === 0.5, "Multiplicador de curación base = 0.5");
assert(threatTable.getConfig().tankDamageTakenMultiplier === 1.5, "Multiplicador de daño recibido por tanque = 1.5");
assert(threatTable.getConfig().tankRoleThreatMultiplier === 2.5, "Multiplicador de rol tanque = 2.5");
assert(threatTable.getConfig().sphereBlueThreatBonus === 0.50, "Bono por esfera azul = +50%");
assert(threatTable.getConfig().sphereRedThreatBonus === 0.15, "Bono por esfera roja = +15%");
assert(threatTable.getConfig().sphereGreenThreatBonus === 0.25, "Bono por esfera verde = +25%");
assert(threatTable.getConfig().sphereYellowThreatBonus === 0.10, "Bono por esfera amarilla = +10%");

section("2. DETERMINACIÓN AUTORITATIVA DEL ROL TANQUE POR ESFERAS AZULES");

// Jugador A: 2 esferas azules (Build Tanque)
const partyTankPlayer = {
    id: "uid_tank",
    dbId: "uid_tank",
    socketId: "sock_ptank",
    user: "MegaTank",
    zone: 2,
    spheres: [
        { type: "azul" },
        { type: "azul" },
        { type: "amarilla" }
    ]
};

// Jugador B: 1 esfera azul, 2 rojas (Off-tank / Bruiser)
const partyBruiserPlayer = {
    id: "uid_bruiser",
    dbId: "uid_bruiser",
    socketId: "sock_pbruiser",
    user: "Bruiser",
    zone: 2,
    spheres: [
        { type: "azul" },
        { type: "roja" },
        { type: "roja" }
    ]
};

// Jugador C: 0 esferas azules, 4 rojas (DPS puro)
const partyDpsPlayer = {
    id: "uid_dps",
    dbId: "uid_dps",
    socketId: "sock_pdps",
    user: "GlassCannon",
    zone: 2,
    spheres: [
        { type: "roja" },
        { type: "roja" },
        { type: "roja" },
        { type: "roja" }
    ]
};

mockState.players["sock_ptank"] = partyTankPlayer;
mockState.players["sock_pbruiser"] = partyBruiserPlayer;
mockState.players["sock_pdps"] = partyDpsPlayer;

// Configurar Party compartida
mockState.playerParty["uid_tank"] = "party_1";
mockState.playerParty["uid_bruiser"] = "party_1";
mockState.playerParty["uid_dps"] = "party_1";
mockState.parties["party_1"] = {
    members: ["uid_tank", "uid_bruiser", "uid_dps"]
};

assert(threatTable.isGroupTank(partyTankPlayer) === true, "Jugador con mayor cantidad de esferas azules (2) es consagrado como Tanque del grupo");
assert(threatTable.isGroupTank(partyBruiserPlayer) === false, "Jugador con 1 esfera azul no es tanque al haber un miembro con más azules");
assert(threatTable.isGroupTank(partyDpsPlayer) === false, "Jugador sin esferas azules nunca recibe rol tanque");

// Multiplicador del tanque: base + 2 azules (2*0.50) + 1 amarilla (0.10) = 2.10 * 2.5 (bono tanque) = 5.25x
const tankMultiplier = threatTable.getPlayerThreatMultiplier(partyTankPlayer);
assert(Math.abs(tankMultiplier - (2.10 * 2.5)) < 0.001, `Multiplicador total del tanque con esferas = 5.25x: obtenido ${tankMultiplier.toFixed(2)}x`);

// Multiplicador DPS: 1.0 + 4*0.15 = 1.6x
const dpsMultiplier = threatTable.getPlayerThreatMultiplier(partyDpsPlayer);
assert(Math.abs(dpsMultiplier - 1.60) < 0.001, `Multiplicador total de DPS con 4 esferas rojas = 1.60x: obtenido ${dpsMultiplier.toFixed(2)}x`);

section("3. GENERACIÓN DE AMENAZA POR DAÑO (DPS) Y DISTANCIA");

const dpsPlayer = { socketId: "sock_dps", user: "MagoRayo", zone: 2, x: 3500, y: 1000, hp: 1000, maxHp: 1000, isDead: false, isInvisible: false, spheres: [{ type: "roja" }] };
mockState.players["sock_dps"] = dpsPlayer;

// Daño desde 2500px de distancia: genera amenaza autoritativa de inmediato
const dmgThreat = threatTable.addDamageThreat(dpsPlayer.socketId, 500, dpsPlayer);
const expectedDpsThreat = 500 * (1.0 + 0.15); // 500 * 1.15 = 575
assert(dmgThreat === expectedDpsThreat, `Daño a distancia genera amenaza inmediata con bono de esfera roja: esperado ${expectedDpsThreat}, obtenido ${dmgThreat}`);
assert(threatTable.entries.get(dpsPlayer.socketId).threat === expectedDpsThreat, "Entrada en la tabla refleja puntos de amenaza");

section("4. GENERACIÓN DE AMENAZA POR TANQUEO Y MITIGACIÓN");

const tankPlayer = { socketId: "sock_tank", user: "PaladinTanque", zone: 2, x: 1050, y: 1000, hp: 5000, maxHp: 5000, isDead: false, isInvisible: false, spheres: [{ type: "azul" }, { type: "azul" }] };
mockState.players["sock_tank"] = tankPlayer;

// Tanque solitario con 2 esferas azules: esfera mult = 1.0 + 2*0.50 = 2.0x, tank role = 2.5x => total mult = 5.0x
// Daño recibido = 400 * 1.5 (base mitigación) * 5.0 = 3000 puntos
const tankThreat = threatTable.addTankingThreat(tankPlayer.socketId, 400, tankPlayer);
assert(tankThreat === 400 * 1.5 * 5.0, `Mitigación de daño para tanque con esferas azules genera 3000 pts: obtenido ${tankThreat}`);
assert(threatTable.entries.get(tankPlayer.socketId).threat === 3000, "Entrada del tanque refleja 3000 puntos acumulados");

section("5. RANGO DE VISIÓN DINÁMICO Y PERCEPCIÓN DE CURACIÓN");

assert(threatTable.getEffectiveVisionRange() === 800, "Enemigo regular: rango de visión efectivo = 800px");
mockEnemy.config.visionRange = 1500;
assert(threatTable.getEffectiveVisionRange() === 1500, "Enemigo personalizado: rango de visión efectivo = 1500px");
mockEnemy.isBoss = true;
delete mockEnemy.config.visionRange;
assert(threatTable.getEffectiveVisionRange() === 2000, "Boss: rango de visión efectivo = 2000px");
mockEnemy.isBoss = false;
mockEnemy.config.visionRange = 800;

const healPlayer = { socketId: "sock_healer", user: "ClerigoVerde", zone: 2, x: 1400, y: 1000, hp: 1200, maxHp: 1200, isDead: false, isInvisible: false, spheres: [{ type: "verde" }, { type: "verde" }] };
mockState.players["sock_healer"] = healPlayer;

// Sanador con 2 esferas verdes: 1.0 + 2*0.25 = 1.50x
// Cura 1000 de vida con 2 enemigos activos: ((1000 * 0.5) / 2) * 1.50 = 375 puntos
const healThreat = threatTable.addHealingThreat(healPlayer.socketId, 1000, 2, healPlayer);
assert(healThreat === 375, `Curación de 1000 con 2 esferas verdes repartida en 2 enemigos genera 375 pts: obtenido ${healThreat}`);

section("6. SELECCIÓN DE OBJETIVO CON HISTÉRESIS (PEEL THRESHOLDS AAA)");

// Establecer valores controlados para verificar histéresis:
// Tanque: 2000 pts (distancia 50px - Melee)
// DPS: 500 pts
threatTable.entries.get(tankPlayer.socketId).threat = 2000;
threatTable.entries.get(dpsPlayer.socketId).threat = 500;
tankPlayer.x = 1050; // a 50px (Melee)

let target = threatTable.getTopThreatTarget(mockState.players);
assert(target && target.socketId === "sock_tank", "El Tanque tiene el agro prioritario (2000 pts)");

// DPS ataca y sube a 2100 pts en Melee (distancia 100px):
// El umbral de Melee es 110%: 2000 * 1.10 = 2200 pts requeridos para despegue (Peel).
dpsPlayer.x = 1100; // a 100px del bicho (Melee)
threatTable.entries.get(dpsPlayer.socketId).threat = 2100;
target = threatTable.getTopThreatTarget(mockState.players);
assert(target && target.socketId === "sock_tank", "Histéresis Melee: DPS con 2100 no supera el 110% (2200). El bicho NO cambia erráticamente de objetivo");

// DPS ráfaga masiva y alcanza 2300 pts (supera los 2200 requeridos):
threatTable.entries.get(dpsPlayer.socketId).threat = 2300;
target = threatTable.getTopThreatTarget(mockState.players);
assert(target && target.socketId === "sock_dps", "Despegue exitoso: DPS con 2300 pts (>110%) roba el agro limpiamente");

// Ahora Tanque está a rango distancia (>250px) y necesita 130% para robar de nuevo:
// Requiere: 2300 * 1.30 = 2990 pts
tankPlayer.x = 1600; // a 600px del bicho (Rango)
threatTable.entries.get(tankPlayer.socketId).threat = 2800;
target = threatTable.getTopThreatTarget(mockState.players);
assert(target && target.socketId === "sock_dps", "Histéresis Rango: Tanque con 2800 no supera el 130% (2990) desde lejos. El DPS mantiene el agro");

threatTable.entries.get(tankPlayer.socketId).threat = 3100;
target = threatTable.getTopThreatTarget(mockState.players);
assert(target && target.socketId === "sock_tank", "Tanque con 3100 pts (>130%) recupera el agro desde la distancia");

section("6. PROVOCACIÓN (TAUNT) AUTORITATIVA");

// DPS vuelve a 10000 de amenaza (supera al tanque por mucho)
threatTable.entries.get(dpsPlayer.socketId).threat = 10000;
target = threatTable.getTopThreatTarget(mockState.players);
assert(target && target.socketId === "sock_dps", "DPS recuperó el agro con 10000 pts");

// Tanque usa Provocación (Taunt):
// Debe igualar la amenaza máxima (10000) + bonus 10% = 11000 pts y fijar objetivo
threatTable.applyTaunt(tankPlayer.socketId, 4000, 10);
assert(threatTable.entries.get(tankPlayer.socketId).threat >= 11000, `Taunt eleva la amenaza del tanque al top + bonus: ${threatTable.entries.get(tankPlayer.socketId).threat} pts`);
target = threatTable.getTopThreatTarget(mockState.players);
assert(target && target.socketId === "sock_tank", "El Taunt fija inmediatamente al tanque como objetivo principal");

section("7. PURGA DE AGRO POR MUERTE E INVISIBILIDAD");

// Simular que el tanque muere
tankPlayer.isDead = true;
target = threatTable.getTopThreatTarget(mockState.players);
assert(target && target.socketId === "sock_dps", "Al morir el tanque, el mob cambia instantáneamente al segundo en la tabla (DPS)");

// Simular que el DPS entra en Sigilo (Invisibilidad)
dpsPlayer.isInvisible = true;
target = threatTable.getTopThreatTarget(mockState.players);
assert(target && target.socketId === "sock_healer", "Al hacerse invisible el DPS, el mob ataca al sanador visible");

section("8. INTEGRACIÓN CON BASEAI Y BOSSAI");

const aiEnemy = {
    id: "boss_101",
    type: 101,
    zone: 2,
    x: 2000,
    y: 2000,
    hp: 50000,
    maxHp: 50000,
    shield: 10000,
    maxShield: 10000,
    config: {
        isBoss: true,
        speed: 4.0,
        visionRange: 1200
    }
};

const baseAI = new BaseAI(aiEnemy, aiEnemy.config, mockState);
assert(baseAI.threatTable !== undefined, "BaseAI instancia e inicializa threatTable automáticamente");
assert(aiEnemy.threatTable === baseAI.threatTable, "aiEnemy.threatTable comparte la misma instancia autoritativa");

const bossAI = new BossAI(aiEnemy, aiEnemy.config, mockState);
assert(bossAI.threatTable !== undefined, "BossAI hereda threatTable autoritativa correctamente");

section("9. BALANCE DINÁMICO POR ENEMIGO (CUSTOM OVERRIDES)");

const customEnemy = {
    id: "mob_custom",
    type: 99,
    zone: 2,
    x: 500,
    y: 500,
    config: {
        useCustomAggro: true,
        aggroDamageMult: 2.5,
        aggroHealMult: 1.0,
        aggroTankMult: 4.0,
        aggroPeelThreshold: 1.5,
        immuneToTaunt: true
    }
};

const customThreat = new ThreatTable(customEnemy, mockState);
const customCfg = customThreat.getConfig();
assert(customCfg.damageThreatMultiplier === 2.5, "Custom Override: Daño = 2.5x");
assert(customCfg.healingThreatMultiplier === 1.0, "Custom Override: Curación = 1.0x");
assert(customCfg.tankDamageTakenMultiplier === 4.0, "Custom Override: Tanqueo = 4.0x");
assert(customCfg.meleePeelThreshold === 1.5, "Custom Override: Peel = 1.5x (150%)");
assert(customCfg.immuneToTaunt === true, "Custom Override: Inmune a Taunt");

const tauntResult = customThreat.applyTaunt("sock_tank", 4000);
assert(tauntResult === false, "Enemigo inmune a Taunt rechaza la provocación");

section("10. VERIFICACIÓN DE REACTIVIDAD DINÁMICA DE CADA PARÁMETRO (HOT-RELOAD EN VIVO)");

const dynEnemy = { id: "mob_dyn", zone: 2, x: 1000, y: 1000, hp: 10000, maxHp: 10000, config: { visionRange: 800 } };
const dynTable = new ThreatTable(dynEnemy, mockState);

const pTester = { socketId: "sock_tester", user: "Tester", zone: 2, x: 1050, y: 1000, hp: 1000, maxHp: 1000, spheres: [] };
mockState.players["sock_tester"] = pTester;

// 1. Dinámico: damageThreatMultiplier
mockState.SERVER_CONFIG.aggroConfig.damageThreatMultiplier = 3.0;
const dynDmg = dynTable.addDamageThreat("sock_tester", 100, pTester);
assert(dynDmg === 300, `Cambio dinámico en damageThreatMultiplier (3.0): 100 daño genera ${dynDmg} pts (esperado 300)`);

// 2. Dinámico: healingThreatMultiplier
mockState.SERVER_CONFIG.aggroConfig.healingThreatMultiplier = 2.0;
dynTable.entries.clear();
const dynHeal = dynTable.addHealingThreat("sock_tester", 100, 1, pTester);
assert(dynHeal === 200, `Cambio dinámico en healingThreatMultiplier (2.0): 100 cura genera ${dynHeal} pts (esperado 200)`);

// 3. Dinámico: tankDamageTakenMultiplier
mockState.SERVER_CONFIG.aggroConfig.tankDamageTakenMultiplier = 5.0;
dynTable.entries.clear();
const dynTankMit = dynTable.addTankingThreat("sock_tester", 100, pTester);
assert(dynTankMit === 500, `Cambio dinámico en tankDamageTakenMultiplier (5.0): 100 daño recibido genera ${dynTankMit} pts (esperado 500)`);

// 4. Dinámico: sphereBlueThreatBonus
pTester.spheres = [{ type: "azul" }, { type: "azul" }]; // 2 esferas azules
mockState.SERVER_CONFIG.aggroConfig.sphereBlueThreatBonus = 1.0; // +100% por azul
mockState.SERVER_CONFIG.aggroConfig.tankRoleThreatMultiplier = 1.0; // neutralizar rol para aislar esfera
const dynBlueMult = dynTable.getPlayerThreatMultiplier(pTester);
assert(dynBlueMult === 3.0, `Cambio dinámico en sphereBlueThreatBonus (1.00): 2 azules = 3.0x mult (esperado 3.0, obtenido ${dynBlueMult})`);

// 5. Dinámico: tankRoleThreatMultiplier
mockState.SERVER_CONFIG.aggroConfig.tankRoleThreatMultiplier = 4.0;
const dynTankRoleMult = dynTable.getPlayerThreatMultiplier(pTester);
assert(dynTankRoleMult === 3.0 * 4.0, `Cambio dinámico en tankRoleThreatMultiplier (4.0): mult = 12.0x (esperado 12.0, obtenido ${dynTankRoleMult})`);

// 6. Dinámico: sphereRedThreatBonus
const pRed = { socketId: "p_red", zone: 2, x: 1000, y: 1000, spheres: [{ type: "roja" }, { type: "roja" }] };
mockState.SERVER_CONFIG.aggroConfig.sphereRedThreatBonus = 0.40;
const dynRedMult = dynTable.getPlayerThreatMultiplier(pRed);
assert(Math.abs(dynRedMult - 1.80) < 0.001, `Cambio dinámico en sphereRedThreatBonus (0.40): 2 rojas = 1.80x (esperado 1.80, obtenido ${dynRedMult.toFixed(2)})`);

// 7. Dinámico: sphereGreenThreatBonus
const pGreen = { socketId: "p_green", zone: 2, x: 1000, y: 1000, spheres: [{ type: "verde" }] };
mockState.SERVER_CONFIG.aggroConfig.sphereGreenThreatBonus = 0.60;
const dynGreenMult = dynTable.getPlayerThreatMultiplier(pGreen);
assert(Math.abs(dynGreenMult - 1.60) < 0.001, `Cambio dinámico en sphereGreenThreatBonus (0.60): 1 verde = 1.60x (esperado 1.60, obtenido ${dynGreenMult.toFixed(2)})`);

// 8. Dinámico: sphereYellowThreatBonus
const pYellow = { socketId: "p_yellow", zone: 2, x: 1000, y: 1000, spheres: [{ type: "amarilla" }] };
mockState.SERVER_CONFIG.aggroConfig.sphereYellowThreatBonus = 0.30;
const dynYellowMult = dynTable.getPlayerThreatMultiplier(pYellow);
assert(Math.abs(dynYellowMult - 1.30) < 0.001, `Cambio dinámico en sphereYellowThreatBonus (0.30): 1 amarilla = 1.30x (esperado 1.30, obtenido ${dynYellowMult.toFixed(2)})`);

// 9. Dinámico: initialPullThreat
mockState.SERVER_CONFIG.aggroConfig.initialPullThreat = 800;
dynTable.entries.clear();
dynTable.addPullThreat("sock_tester", pTester);
assert(dynTable.entries.get("sock_tester").threat === 800, `Cambio dinámico en initialPullThreat (800): agro inicial asignado = 800 pts`);

// 10. Dinámico: tauntBonusPercent
mockState.SERVER_CONFIG.aggroConfig.tauntBonusPercent = 50;
dynTable.entries.get("sock_tester").threat = 1000;
const pTank2 = { socketId: "sock_tank2", zone: 2, x: 1000, y: 1000, spheres: [{ type: "azul" }] };
mockState.players["sock_tank2"] = pTank2;
dynTable.applyTaunt("sock_tank2", 4000);
assert(dynTable.entries.get("sock_tank2").threat === 1500, `Cambio dinámico en tauntBonusPercent (50%): Taunt sobre 1000 eleva a 1500 pts`);

// 11. Dinámico: enabled = false (Apagado global)
mockState.SERVER_CONFIG.aggroConfig.enabled = false;
dynTable.entries.clear();
const offDmg = dynTable.addDamageThreat("sock_tester", 500, pTester);
assert(offDmg === 0 && dynTable.entries.size === 0, `Cambio dinámico enabled = false: Desactiva por completo la generación de amenaza`);
mockState.SERVER_CONFIG.aggroConfig.enabled = true; // restaurar

section("RESUMEN DE AUDITORÍA");
console.log(`\n  Total de Pruebas: ${passed + failed}`);
console.log(`  ${COLORS.green}Aprobadas: ${passed}${COLORS.reset}`);
console.log(`  ${failed > 0 ? COLORS.red : COLORS.green}Fallidas: ${failed}${COLORS.reset}`);

if (failed === 0) {
    console.log(`\n${COLORS.bright}${COLORS.green}👑 TODAS LAS PRUEBAS DEL SISTEMA DE AGRO AAA PASARON CON ÉXITO.${COLORS.reset}\n`);
    process.exit(0);
} else {
    console.log(`\n${COLORS.bright}${COLORS.red}❌ SE ENCONTRARON FALLAS EN EL SISTEMA DE AGRO.${COLORS.reset}\n`);
    process.exit(1);
}
