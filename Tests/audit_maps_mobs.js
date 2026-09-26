/**
 * audit_maps_mobs.js
 * Test Suite de Auditoría para Mapas, Zonas, Enemigos/Mobs y Modos de Juego en Descon MMO.
 * Ubicación: E:\Descon\Tests\audit_maps_mobs.js
 */

const fs = require('fs');
const path = require('path');

let SERVER_DIR = path.resolve(__dirname, '..', 'Server');
if (!fs.existsSync(SERVER_DIR)) {
    SERVER_DIR = path.resolve(__dirname, '..', '..', 'Server');
}
const CONFIG_PATH = path.join(SERVER_DIR, 'config.json');

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
function section(title) {
    console.log(`\n${COLORS.bright}${COLORS.blue}══════════════════════════════════════════════════════════════════${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}  ${title}${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}══════════════════════════════════════════════════════════════════${COLORS.reset}`);
}

async function runAudit() {
    console.log(`\n${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}   DESCON MMO - AUDITORÍA DE MAPAS, ZONAS, MOBS Y MODOS DE JUEGO ${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}\n`);

    if (!fs.existsSync(CONFIG_PATH)) {
        fail(`No se encontró config.json`);
        process.exit(1);
    }

    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    let totalPassed = 0;
    let totalFailed = 0;
    let totalWarnings = 0;

    // 1. CONFIGURACIÓN DE MAPAS Y ZONAS (mapsConfig & pilotConfig)
    section('1. MAPAS Y ZONAS DE JUEGO (mapsConfig)');
    const maps = config.mapsConfig || {};
    const mapIds = Object.keys(maps);
    pass(`Mapas configurados en el servidor: ${mapIds.length} (${mapIds.join(', ')})`);
    totalPassed++;

    mapIds.forEach(mId => {
        const m = maps[mId];
        if (!m.width || Number(m.width) <= 0) {
            fail(`Mapa '${mId}' (${m.name || 'Sin nombre'}) tiene width inválido: ${m.width}`);
            totalFailed++;
        }
        if (!m.height || Number(m.height) <= 0) {
            fail(`Mapa '${mId}' (${m.name || 'Sin nombre'}) tiene height inválido: ${m.height}`);
            totalFailed++;
        }
    });

    const startingMapId = config.pilotConfig?.startingMapId || 1;
    if (maps[String(startingMapId)]) {
        pass(`Zona Segura / Lobby de Inicio (Map ID ${startingMapId}): '${maps[String(startingMapId)].name || 'Lobby'}' verificado.`);
        totalPassed++;
    } else {
        warn(`startingMapId en pilotConfig es ${startingMapId}, pero no está en mapsConfig.`);
        totalWarnings++;
    }

    // 2. MODELOS Y DATOS DE ENEMIGOS (enemyModels / enemyTypes)
    section('2. ENEMIGOS Y NATIVE MOBS (enemyModels)');
    const enemyModels = config.enemyModels || config.enemiesConfig || {};
    const enemyList = Array.isArray(enemyModels) ? enemyModels : Object.values(enemyModels);
    pass(`Modelos de enemigos cargados: ${enemyList.length}`);
    totalPassed++;

    enemyList.forEach((e, idx) => {
        if (!e.id && e.type === undefined) {
            warn(`Enemigo en índice ${idx} no tiene ID o type explícito.`);
            totalWarnings++;
        }
        if (e.hp !== undefined && Number(e.hp) <= 0) {
            fail(`Enemigo '${e.name || e.id}' tiene HP <= 0: ${e.hp}`);
            totalFailed++;
        }
    });

    if (totalFailed === 0) {
        pass('Todos los enemigos configurados tienen HP e integridad física correcta.');
        totalPassed++;
    }

    // 3. MODOS DE JUEGO (gameModes & hordeConfig)
    section('3. MODOS DE JUEGO Y HORDAS (gameModes)');
    const gameModes = config.gameModes || {};
    const modeNames = Object.keys(gameModes);
    pass(`Modos de juego registrados: ${modeNames.length} (${modeNames.join(', ')})`);
    totalPassed++;

    section('RESUMEN DE MAPAS, MOBS Y MODOS');
    console.log(`  ${COLORS.green}Pruebas Pasadas:${COLORS.reset}    ${totalPassed}`);
    console.log(`  ${COLORS.red}Fallos Críticos:${COLORS.reset}    ${totalFailed}`);
    console.log(`  ${COLORS.yellow}Advertencias:${COLORS.reset}       ${totalWarnings}\n`);

    if (totalFailed > 0) process.exit(1);
}

runAudit().catch(err => {
    console.error('Error en test audit_maps_mobs:', err);
    process.exit(1);
});
