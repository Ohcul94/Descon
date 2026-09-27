/**
 * audit_fireball_mechanic.js
 * Auditoría de la mecánica "Bola de Fuego Dinámica" (type: fireball) - v901.0
 * Ubicación: E:\Descon\Tests\audit_fireball_mechanic.js
 *
 * Verifica:
 *  1) Integridad de la cadena de verdad AdminDash -> Server -> Cliente (Godot).
 *  2) Comportamiento autoritativo de Server/behaviors/mechanics/FireballMechanics.js
 *     mediante una simulación de ticks (carga -> spawn -> movimiento -> daño -> expiración -> CD).
 *
 * Ejecución: node Tests/audit_fireball_mechanic.js
 */

const fs = require('fs');
const path = require('path');

let SERVER_DIR = path.resolve(__dirname, '..', 'Server');
if (!fs.existsSync(SERVER_DIR)) SERVER_DIR = path.resolve(__dirname, '..', '..', 'Server');
const ROOT = path.resolve(SERVER_DIR, '..');
const CLIENT_DIR = path.join(ROOT, 'descon');
const ADMIN_DIR = path.join(ROOT, 'AdminDash');

const COLORS = {
    reset: '\x1b[0m', bright: '\x1b[1m', green: '\x1b[32m', red: '\x1b[31m',
    yellow: '\x1b[33m', blue: '\x1b[34m'
};

let passed = 0, failed = 0, warnings = 0;
function pass(msg) { passed++; console.log(`  ${COLORS.green}✓ [PASS]${COLORS.reset} ${msg}`); }
function fail(msg) { failed++; console.log(`  ${COLORS.red}✗ [FAIL]${COLORS.reset} ${msg}`); }
function warn(msg) { warnings++; console.log(`  ${COLORS.yellow}! [WARN]${COLORS.reset} ${msg}`); }
function section(title) {
    console.log(`\n${COLORS.bright}${COLORS.blue}${'═'.repeat(64)}${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}  ${title}${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}${'═'.repeat(64)}${COLORS.reset}`);
}
function check(cond, okMsg, failMsg) { cond ? pass(okMsg) : fail(failMsg); }

const read = (p) => fs.readFileSync(p, 'utf8');

// ══════════════════════════════════════════════════════════════════════════════
// 1. INTEGRIDAD DE LA CADENA DE VERDAD
// ══════════════════════════════════════════════════════════════════════════════
section('1. INTEGRIDAD AdminDash -> Server -> Cliente (Godot)');

const cfg = JSON.parse(read(path.join(SERVER_DIR, 'config.json')));
const lib = (cfg.mechanicsLib || {});
check(!!lib.fireball, 'config.json tiene mechanicsLib.fireball', 'config.json NO tiene mechanicsLib.fireball');

const REQUIRED_FIELDS = [
    'activationMode', 'activationHPs', 'activationIntervalMs', 'startDelay', 'castTimeMs',
    'castInterruptible', 'fireRange', 'cooldown', 'duration', 'areaRadius', 'areaMode',
    'speed', 'radius', 'damage_per_tick', 'tick_interval'
];
if (lib.fireball) {
    const missing = REQUIRED_FIELDS.filter(f => !(lib.fireball.fields || []).includes(f));
    check(missing.length === 0, `fields completos en config.json (${REQUIRED_FIELDS.length})`,
        `fields faltantes en config.json: ${missing.join(', ')}`);
    const dupes = (lib.fireball.fields || []).filter((f, i, a) => a.indexOf(f) !== i);
    check(dupes.length === 0, 'sin campos duplicados', `campos duplicados: ${dupes.join(', ')}`);
    check(typeof lib.fireball.label === 'string' && lib.fireball.label.length > 0,
        `label en español: "${lib.fireball.label}"`, 'label faltante en config.json');
}

const defs = read(path.join(ADMIN_DIR, 'js', 'definitions.js'));
check(/"fireball"\s*:\s*\{\s*label/.test(defs),
    'definitions.js define DEFAULT_MECHANICS_LIB.fireball',
    'definitions.js NO define DEFAULT_MECHANICS_LIB.fireball');
const defFields = (defs.match(/"fireball"\s*:\s*\{[^}]*fields:\s*\[([^\]]*)\]/) || [])[1] || '';
const missingInDef = REQUIRED_FIELDS.filter(f => !new RegExp(`["']${f}["']`).test(defFields));
check(missingInDef.length === 0, 'definitions.js lista los mismos campos',
    `definitions.js le faltan: ${missingInDef.join(', ')}`);

const appJs = read(path.join(ADMIN_DIR, 'js', 'app.js'));
check(/newType === 'fireball' \? 90/.test(appJs), 'app.js: radius por defecto 90',
    'app.js no define radius=90 para fireball');
check(/f === 'areaRadius'\) mech\[f\] = 350/.test(appJs), 'app.js: areaRadius por defecto 350',
    'app.js no define areaRadius=350');
check(/f === 'areaMode'\) mech\[f\] = 'enemy'/.test(appJs), "app.js: areaMode por defecto 'enemy'",
    "app.js no define areaMode='enemy'");
check(/f === 'tick_interval'\) mech\[f\] = 800/.test(appJs), 'app.js: tick_interval por defecto 800',
    'app.js no define tick_interval=800');
check(/f === 'damage_per_tick'\) mech\[f\] = 30/.test(appJs), 'app.js: damage_per_tick por defecto 30',
    'app.js no define damage_per_tick=30');

const ren = read(path.join(ADMIN_DIR, 'js', 'renderers', 'renderEnemies.js'));
check(/areaRadius:/.test(ren) && /areaMode:/.test(ren),
    'renderEnemies.js etiqueta areaRadius y areaMode',
    'renderEnemies.js no etiqueta areaRadius/areaMode');
check(/f === 'areaMode'/i.test(ren) && /<option value="enemy"/.test(ren),
    'renderEnemies.js renderiza select para areaMode',
    'renderEnemies.js no renderiza select para areaMode');

const rmech = read(path.join(ADMIN_DIR, 'js', 'renderers', 'renderMechanics.js'));
check(/"areaRadius"\s*:\s*"[^"]+"/.test(rmech) && /"areaMode"\s*:\s*"[^"]+"/.test(rmech),
    'renderMechanics.js tiene etiquetas de catálogo para areaRadius/areaMode',
    'renderMechanics.js NO tiene etiquetas para areaRadius/areaMode');

const baseAI = read(path.join(SERVER_DIR, 'behaviors', 'BaseAI.js'));
check(/require\('\.\/mechanics\/FireballMechanics'\)/.test(baseAI),
    'BaseAI.js requiere FireballMechanics', 'BaseAI.js no requiere FireballMechanics');
check(/mech\.type === "fireball"/.test(baseAI) && /_handleFireballLogic\.call/.test(baseAI),
    'BaseAI.js despacha mech.type === "fireball"', 'BaseAI.js no despacha fireball');
const internalMatch = baseAI.match(/const internal = \[([^\]]*)\]/);
const internalList = (internalMatch ? internalMatch[1] : '').split(',').map(s => s.trim().replace(/['"]/g, ''));
check(internalList.includes('fireball'),
    'fireball está en la lista internal (cast genérico en paralelo)',
    'fireball NO está en la lista internal de BaseAI.js');

const em = read(path.join(CLIENT_DIR, 'scripts', 'systems', 'EntityManager.gd'));
['fireball_charge', 'fireball_spawn', 'fireball_move', 'fireball_expire'].forEach(a => {
    check(em.includes(`"${a}"`), `EntityManager.gd maneja el evento "${a}"`,
        `EntityManager.gd NO maneja "${a}"`);
});
check(/active_fireballs/.test(em), 'EntityManager.gd mantiene active_fireballs',
    'EntityManager.gd no mantiene active_fireballs');
check(/data\.get\("silent", false\)/.test(em),
    'EntityManager.gd respeta el flag "silent" (evita spam de sonido)',
    'EntityManager.gd no respeta el flag "silent"');

const visualPath = path.join(CLIENT_DIR, 'scripts', 'systems', 'FireballSunVisual.gd');
check(fs.existsSync(visualPath), 'Existe descon/scripts/systems/FireballSunVisual.gd',
    'NO existe FireballSunVisual.gd');
if (fs.existsSync(visualPath)) {
    const v = read(visualPath);
    ['func setup(', 'func setup_charge(', 'func set_target(', 'func finish('].forEach(sig => {
        check(v.includes(sig), `FireballSunVisual.gd expone ${sig.slice(5, -1)}()`,
            `FireballSunVisual.gd NO expone ${sig.slice(5, -1)}()`);
    });
    check(/tree_exiting\.connect/.test(v),
        'FireballSunVisual.gd libera sus copias 3D al salir del árbol',
        'FireballSunVisual.gd NO libera sus copias 3D');
    check(/_duration \+ 2\.0/.test(v),
        'FireballSunVisual.gd tiene autoliberación de seguridad por duración',
        'FireballSunVisual.gd NO tiene autoliberación de seguridad');
    check(/spawn_explosion/.test(v), 'FireballSunVisual.gd remata con spawn_explosion al expirar',
        'FireballSunVisual.gd no remata con spawn_explosion');
}

// ══════════════════════════════════════════════════════════════════════════════
// 2. SIMULACIÓN DE LA LÓGICA AUTORITATIVA
// ══════════════════════════════════════════════════════════════════════════════
section('2. SIMULACIÓN DE LÓGICA (carga -> spawn -> movimiento -> daño -> expiración -> CD)');

const fireball = require(path.join(SERVER_DIR, 'behaviors', 'mechanics', 'FireballMechanics.js'));
check(typeof fireball._handleFireballLogic === 'function',
    'FireballMechanics exporta _handleFireballLogic', 'FireballMechanics NO exporta _handleFireballLogic');

// Config base. radius se amplía a propósito (400 > areaRadius 350) para que el
// escenario de daño sea determinista: la bola se mueve de forma aleatoria dentro
// del área y así todo el área queda cubierta por el radio de daño.
const MECH = {
    activationMode: 'time', activationHPs: [50], activationIntervalMs: 0,
    startDelay: 0, castTimeMs: 1200, castInterruptible: true,
    fireRange: 600, cooldown: 12000, duration: 6000,
    areaRadius: 350, areaMode: 'enemy', speed: 180,
    radius: 400, damage_per_tick: 30, tick_interval: 800
};

function makeWorld(opts = {}) {
    const emitted = [];
    const io = { to: (room) => ({ emit: (event, data) => emitted.push({ room, event, data }) }) };
    const players = {
        pIn: { socketId: 'pIn', zone: '7', x: opts.inX ?? 5000, y: opts.inY ?? 5000, hp: 500, shield: 0, isDead: false, isInvisible: false, isInvulnerable: false, reflectActive: false },
        pOut: { socketId: 'pOut', zone: '7', x: 6000, y: 6000, hp: 500, shield: 0, isDead: false, isInvisible: false, isInvulnerable: false, reflectActive: false },
        pOtherZone: { socketId: 'pOther', zone: '9', x: 5000, y: 5000, hp: 500, shield: 0, isDead: false, isInvisible: false, isInvulnerable: false, reflectActive: false }
    };
    const killed = [];
    const ai = {
        config: { fireRange: 600 },
        damageMult: 1,
        state: { parties: {}, players },
        enemy: { id: 'e1', zone: '7', x: 5000, y: 5000, hp: 1000, maxHp: 1000, shield: 0, mechState: {} },
        _killPlayer: (p) => { killed.push(p.socketId); p.isDead = true; p.hp = 0; }
    };
    return { ai, io, players, emitted, killed };
}

// Stub de daño al Altar (el módulo se cachea, se reemplaza el método de instancia)
const altarMod = require(path.join(SERVER_DIR, 'systems', 'altarDefenseManager'));
const realAltar = altarMod.applyDamageToAltar;
let altarHits = [];
altarMod.applyDamageToAltar = function (dmg, zone) { altarHits.push({ dmg, zone }); };

const M_ID = 'mech_0';
const t0 = Date.now();
const world = makeWorld();
const target = { x: world.ai.enemy.x, y: world.ai.enemy.y };
const call = (now, mech = MECH, w = world) =>
    fireball._handleFireballLogic.call(w.ai, mech, M_ID, target, 100, now, w.io, w.players);
// El socket siempre emite "serverEnemyAction"; el subtipo va en data.action.
// El helper acepta tanto el nombre del evento como el de la acción.
const events = (w, name) => w.emitted.filter(e => e.event === name || (e.data && e.data.action === name));

// ── Fase 0: inicio de carga ──────────────────────────────────────────────────
const r0 = call(t0);
check(r0 === true, 'al iniciar devuelve true (ocupado)', 'al iniciar no devolvió true');
check(events(world, 'fireball_charge').length === 1, 'emite exactamente un fireball_charge',
    `emitió ${events(world, 'fireball_charge').length} fireball_charge`);
const chargeEv = events(world, 'fireball_charge')[0];
if (chargeEv) {
    check(chargeEv.data.silent === true, 'fireball_charge es silencioso (sin spam de sonido)',
        'fireball_charge no tiene silent:true');
    check(chargeEv.data.chargeMs === MECH.castTimeMs, 'fireball_charge incluye chargeMs', 'fireball_charge sin chargeMs');
    check(chargeEv.data.areaRadius === MECH.areaRadius, 'fireball_charge incluye areaRadius', 'fireball_charge sin areaRadius');
    check(chargeEv.data.radius === MECH.radius, 'fireball_charge incluye radius (tamaño de la bola)',
        'fireball_charge sin radius');
    check(chargeEv.data.x === world.ai.enemy.x && chargeEv.data.y === world.ai.enemy.y,
        'areaMode=enemy centra el área en el enemigo', 'el área no está centrada en el enemigo');
    check(chargeEv.room === 'zone_7', 'emite en zone_7', `emitió en ${chargeEv.room}`);
}

// ── Fase 1: durante la carga ─────────────────────────────────────────────────
let spawnedDuringCharge = false;
for (let now = t0 + 50; now < t0 + MECH.castTimeMs; now += 50) {
    call(now);
    if (events(world, 'fireball_spawn').length > 0) spawnedDuringCharge = true;
}
check(!spawnedDuringCharge, 'no hace spawn antes de terminar la carga', 'hizo spawn durante la carga');
check(events(world, 'fireball_charge').length === 1, 'no re-emite fireball_charge en cada tick',
    `re-emitió charge ${events(world, 'fireball_charge').length} veces`);

// ── Fase 2: spawn ────────────────────────────────────────────────────────────
call(t0 + MECH.castTimeMs);
const spawnEv = events(world, 'fireball_spawn')[0];
check(events(world, 'fireball_spawn').length === 1, 'emite un único fireball_spawn tras la carga',
    `emitió ${events(world, 'fireball_spawn').length} fireball_spawn`);
if (spawnEv) {
    check(spawnEv.data.silent === undefined, 'fireball_spawn es audible (sin silent)',
        'fireball_spawn tiene silent');
    check(spawnEv.data.areaX === world.ai.enemy.x && spawnEv.data.areaY === world.ai.enemy.y,
        'spawn incluye areaX/areaY', 'spawn sin areaX/areaY');
    check(spawnEv.data.duration === MECH.duration, 'spawn incluye duration', 'spawn sin duration');
    check(spawnEv.data.speed === MECH.speed, 'spawn incluye speed', 'spawn sin speed');
    check(spawnEv.data.x === spawnEv.data.areaX && spawnEv.data.y === spawnEv.data.areaY,
        'la bola nace en el centro del área', 'la bola no nace en el centro del área');
}

// ── Fase 3: vida completa de la bola (radio grande => daño determinista) ─────
let maxDistFromCenter = 0;
const distinct = new Set();
for (let now = t0 + MECH.castTimeMs; now <= t0 + MECH.castTimeMs + MECH.duration + 200; now += 50) {
    call(now);
    const ms = events(world, 'fireball_move');
    if (ms.length > 0) {
        const d = ms[ms.length - 1].data;
        const dist = Math.hypot(d.x - spawnEv.data.areaX, d.y - spawnEv.data.areaY);
        if (dist > maxDistFromCenter) maxDistFromCenter = dist;
        distinct.add(`${Math.round(d.x)}_${Math.round(d.y)}`);
    }
}
const moves = events(world, 'fireball_move').length;
check(moves > 10, `emite fireball_move periódicamente (${moves} en ~6s)`,
    `solo ${moves} fireball_move en ~6s`);
const moveEv = events(world, 'fireball_move')[0];
check(!!moveEv && moveEv.data.silent === true, 'fireball_move es silencioso',
    'fireball_move no tiene silent:true');
check(distinct.size > 5, `la bola cambia de posición (${distinct.size} posiciones distintas)`,
    `la bola no se movió (${distinct.size} posiciones)`);
check(maxDistFromCenter <= MECH.areaRadius + 1e-6,
    `la bola permanece dentro del área (máx ${maxDistFromCenter.toFixed(1)}px <= ${MECH.areaRadius}px)`,
    `la bola salió del área (${maxDistFromCenter.toFixed(1)}px > ${MECH.areaRadius}px)`);
const expectedMoves = Math.floor(MECH.duration / 100);
check(moves <= expectedMoves * 1.5,
    `sincronización acotada (~1 cada 100ms, esperados ~${expectedMoves})`,
    `demasiados fireball_move (${moves} > ${Math.round(expectedMoves * 1.5)})`);

// Daño por tick (radius=400 cubre todo el área: el jugador central siempre es alcanzable)
const pIn = world.players.pIn, pOut = world.players.pOut, pOther = world.players.pOtherZone;
check(pIn.hp < 500, `el jugador dentro del radio recibe daño (hp=${pIn.hp})`,
    'el jugador dentro del radio NO recibió daño');
check(pOut.hp === 500, 'el jugador fuera del radio NO recibe daño',
    `el jugador fuera del radio perdió hp (${pOut.hp})`);
check(pOther.hp === 500, 'el jugador de otra zona NO recibe daño',
    `otra zona recibió daño (${pOther.hp})`);
const envDmg = world.emitted.filter(e => e.event === 'environmentDamage');
check(envDmg.length > 0 && envDmg.every(e => e.room === 'pIn'),
    `environmentDamage solo al jugador afectado (${envDmg.length} eventos)`,
    `environmentDamage mal dirigido: ${[...new Set(envDmg.map(e => e.room))].join(',')}`);
check(world.emitted.some(e => e.event === 'playerStatSync'),
    'emite playerStatSync para sincronizar HP', 'no emite playerStatSync');
const expectedTicks = Math.floor(MECH.duration / MECH.tick_interval);
check(envDmg.length <= expectedTicks + 2,
    `ticks de daño acotados por tick_interval (${envDmg.length} <= ~${expectedTicks})`,
    `ticks de daño excesivos (${envDmg.length} > ~${expectedTicks})`);
check(pIn.hp > 0, 'el jugador sobrevive al ciclo completo (no muere de un tick)',
    'el jugador murió: daño/tick desbalanceado');

// ── Daño al Altar (modo defensa) ─────────────────────────────────────────────
altarHits = [];
const altarWorld = makeWorld();
altarWorld.ai.state.altarState = { hp: 5000, zone: '7', x: 5000, y: 5000 };
for (let now = t0; now <= t0 + MECH.castTimeMs + MECH.duration + 200 && altarHits.length === 0; now += 50) {
    fireball._handleFireballLogic.call(altarWorld.ai, MECH, M_ID, target, 100, now, altarWorld.io, altarWorld.players);
}
check(altarHits.length > 0, 'aplica daño al Altar cuando cae dentro del radio',
    'NO aplicó daño al Altar dentro del radio');

// ── Fase 4: expiración + cooldown ────────────────────────────────────────────
const expire = events(world, 'fireball_expire');
check(expire.length === 1, `emite un único fireball_expire (${expire.length})`,
    `emitió ${expire.length} fireball_expire`);
if (expire[0]) check(expire[0].data.silent === true, 'fireball_expire es silencioso',
    'fireball_expire no tiene silent:true');

const stateAfter = world.ai.enemy.mechState[M_ID];
check(stateAfter && stateAfter.isActive === false, 'isActive=false tras expirar',
    'isActive sigue true tras expirar');
const expectedNextShot = t0 + MECH.castTimeMs + MECH.duration + MECH.cooldown;
check(stateAfter && stateAfter.nextShotTime === expectedNextShot,
    'nextShotTime = fin de la bola + cooldown', 'nextShotTime fuera de lo esperado');

const rBlocked = call(stateAfter.nextShotTime - 1000);
check(rBlocked === false && events(world, 'fireball_charge').length === 1,
    'no relanza otra bola dentro del cooldown', 'relanzó otra bola dentro del cooldown');

const rSecond = call(stateAfter.nextShotTime + 10);
check(rSecond === true && events(world, 'fireball_charge').length === 2,
    'relanza la mecánica al vencer el cooldown', 'no relanzó tras vencer el cooldown');

// ── Casos límite ─────────────────────────────────────────────────────────────
const idleWorld = makeWorld();
idleWorld.ai.enemy.mechState[M_ID] = { nextShotTime: 0, isCharging: false, isActive: false };
const rNoTarget = fireball._handleFireballLogic.call(idleWorld.ai, MECH, M_ID, null, Infinity, t0, idleWorld.io, idleWorld.players);
check(rNoTarget === false, 'sin objetivo y sin bola activa devuelve false',
    'sin objetivo no devolvió false');

const farWorld = makeWorld();
farWorld.ai.enemy.mechState[M_ID] = { nextShotTime: 0, isCharging: false, isActive: false };
const rFar = fireball._handleFireballLogic.call(farWorld.ai, MECH, M_ID, { x: 99999, y: 99999 }, 99999, t0, farWorld.io, farWorld.players);
check(rFar === false, 'fuera de fireRange no inicia la carga', 'inició estando fuera de rango');

// Con bola activa y sin objetivo, la lógica sigue viva (isActive en isOngoing)
const orphanWorld = makeWorld();
orphanWorld.ai.enemy.mechState[M_ID] = { nextShotTime: 0, isCharging: false, isActive: false };
const rOrphan1 = fireball._handleFireballLogic.call(orphanWorld.ai, MECH, M_ID, target, 100, t0, orphanWorld.io, orphanWorld.players);
const rOrphan2 = fireball._handleFireballLogic.call(orphanWorld.ai, MECH, M_ID, null, Infinity, t0 + MECH.castTimeMs, orphanWorld.io, orphanWorld.players);
check(rOrphan1 === true && rOrphan2 === true,
    'con bola activa sigue en true aunque desaparezca el objetivo',
    'la bola dejó de estar activa al perder el objetivo');

const multiWorld = makeWorld();
for (let now = t0; now <= t0 + 500; now += 100) {
    fireball._handleFireballLogic.call(multiWorld.ai, MECH, 'mech_0', target, 100, now, multiWorld.io, multiWorld.players);
    fireball._handleFireballLogic.call(multiWorld.ai, MECH, 'mech_1', target, 100, now, multiWorld.io, multiWorld.players);
}
const multiCharge = events(multiWorld, 'fireball_charge');
const multiIds = new Set(multiCharge.map(e => e.data.mId));
check(multiCharge.length === 2 && multiIds.size === 2,
    'dos instancias (mech_0/mech_1) coexisten con su propio estado',
    `instancias cruzadas: ${multiCharge.length} charges, mIds=${[...multiIds].join(',')}`);

const tgtWorld = makeWorld();
const tgtMech = Object.assign({}, MECH, { areaMode: 'target' });
const tgt = { x: 7000, y: 7100 };
fireball._handleFireballLogic.call(tgtWorld.ai, tgtMech, M_ID, tgt, 100, t0, tgtWorld.io, tgtWorld.players);
const tgtCharge = events(tgtWorld, 'fireball_charge')[0];
check(!!tgtCharge && tgtCharge.data.x === tgt.x && tgtCharge.data.y === tgt.y,
    'areaMode=target centra el área en la posición del objetivo',
    'areaMode=target no centró el área en el objetivo');

// radio de daño configurable: con el área fija (areaRadius=0) y radius=100,
// un jugador a 250px del centro no debe ser alcanzable.
const smallWorld = makeWorld({ inX: 5250, inY: 5000 });
const smallMech = Object.assign({}, MECH, { areaRadius: 0, radius: 100, duration: 2000 });
for (let now = t0; now <= t0 + MECH.castTimeMs + 2000 + 200; now += 50) {
    fireball._handleFireballLogic.call(smallWorld.ai, smallMech, M_ID, target, 100, now, smallWorld.io, smallWorld.players);
}
check(smallWorld.players.pIn.hp === 500,
    'radius=100 no alcanza a un jugador a 250px del centro',
    `radius=100 alcanzó a un jugador a 250px (hp=${smallWorld.players.pIn.hp})`);
const smallMoves = events(smallWorld, 'fireball_move');
const smallStuck = smallMoves.length > 0 && smallMoves.every(e => e.data.x === 5000 && e.data.y === 5000);
check(smallStuck, 'areaRadius=0 deja la bola fija en el centro (sin movimiento)',
    `areaRadius=0 igualmente se movió (${smallMoves.length} eventos)`);

// ── Restaurar stub real ──────────────────────────────────────────────────────
altarMod.applyDamageToAltar = realAltar;

// ══════════════════════════════════════════════════════════════════════════════
section('RESUMEN - BOLA DE FUEGO DINÁMICA (fireball)');
console.log(`  Pruebas Pasadas:    ${COLORS.green}${passed}${COLORS.reset}`);
console.log(`  Fallos Críticos:    ${failed ? COLORS.red + failed + COLORS.reset : failed}`);
console.log(`  Advertencias:       ${warnings ? COLORS.yellow + warnings + COLORS.reset : warnings}`);
console.log('');

if (failed > 0) process.exit(1);
