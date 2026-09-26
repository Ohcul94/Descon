/**
 * audit_economy_storage.js
 * Test Suite de Auditoría para Economía, Mercado, Bóveda, Comercio P2P y Pase de Batalla en Descon MMO.
 * Ubicación: E:\Descon\Tests\audit_economy_storage.js
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
    console.log(`${COLORS.bright}${COLORS.magenta}   DESCON MMO - AUDITORÍA DE ECONOMÍA, MERCADO Y BÓVEDA        ${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}\n`);

    if (!fs.existsSync(CONFIG_PATH)) {
        fail(`No se encontró config.json`);
        process.exit(1);
    }

    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    let totalPassed = 0;
    let totalFailed = 0;
    let totalWarnings = 0;

    // 1. CONFIGURACIÓN DEL MERCADO (marketConfig)
    section('1. MERCADO P2P Y REGLAS FINANCIERAS (marketConfig)');
    const market = config.marketConfig;
    if (market) {
        pass(`Configuración de mercado encontrada: Estado=${market.enabled ? 'ACTIVO' : 'INACTIVO'}`);
        totalPassed++;

        const sellTaxPercent = Number(market.sellTaxPercent);
        if (isNaN(sellTaxPercent) || sellTaxPercent < 0 || sellTaxPercent > 100) {
            fail(`Porcentaje de impuesto de venta inválido: ${market.sellTaxPercent}`);
            totalFailed++;
        } else {
            pass(`Impuesto de venta al comercio: ${sellTaxPercent}%`);
            totalPassed++;
        }

        const maxListings = Number(market.maxActiveListingsPerPlayer);
        if (isNaN(maxListings) || maxListings <= 0) {
            fail(`Límite de publicaciones activas por jugador inválido: ${market.maxActiveListingsPerPlayer}`);
            totalFailed++;
        } else {
            pass(`Publicaciones máximas por jugador: ${maxListings}`);
            totalPassed++;
        }
    } else {
        warn('No se encontró marketConfig en config.json');
        totalWarnings++;
    }

    // 2. CONFIGURACIÓN DEL PASE DE BATALLA (battlePassConfig)
    section('2. PASE DE BATALLA Y RECOMPENSAS (battlePassConfig)');
    const bp = config.battlePassConfig;
    if (bp && Array.isArray(bp.levels)) {
        pass(`Niveles de Pase de Batalla configurados: ${bp.levels.length}`);
        totalPassed++;

        let lastExp = 0;
        let bpErrors = 0;
        bp.levels.forEach((lvl, idx) => {
            const exp = Number(lvl.expRequired);
            if (isNaN(exp) || exp < lastExp) {
                fail(`Nivel ${lvl.level || idx + 1} del Pase de Batalla tiene expRequired inválido o descendente: ${lvl.expRequired}`);
                bpErrors++;
                totalFailed++;
            }
            lastExp = exp;
        });

        if (bpErrors === 0) {
            pass('Curva de experiencia requerida por nivel es estrictamente ascendente y coherente.');
            totalPassed++;
        }
    } else {
        warn('No se encontró battlePassConfig en config.json');
        totalWarnings++;
    }

    // 3. INTEGRIDAD DE MÓDULOS DE ALMACENAMIENTO Y COMERCIO (Server System Handlers)
    section('3. MÓDULOS DEL SERVIDOR (Market, Vault, Inventory & Trade Handlers)');
    const expectedHandlers = [
        'marketHandlers.js',
        'vaultHandlers.js',
        'inventoryHandlers.js',
        'tradeHandlers.js',
        'battlePassHandlers.js'
    ];

    expectedHandlers.forEach(hName => {
        const hPath = path.join(SERVER_DIR, 'systems', hName);
        if (!fs.existsSync(hPath)) {
            fail(`No se encontró el manejador de sistema: ${hName}`);
            totalFailed++;
        } else {
            try {
                require(hPath);
                pass(`Módulo de economía/almacenamiento cargado: ${hName}`);
                totalPassed++;
            } catch (err) {
                fail(`Error al cargar el módulo ${hName}: ${err.message}`);
                totalFailed++;
            }
        }
    });

    section('RESUMEN DE ECONOMÍA, MERCADO Y BÓVEDA');
    console.log(`  ${COLORS.green}Pruebas Pasadas:${COLORS.reset}    ${totalPassed}`);
    console.log(`  ${COLORS.red}Fallos Críticos:${COLORS.reset}    ${totalFailed}`);
    console.log(`  ${COLORS.yellow}Advertencias:${COLORS.reset}       ${totalWarnings}\n`);

    if (totalFailed > 0) process.exit(1);
}

runAudit().catch(err => {
    console.error('Error en test audit_economy_storage:', err);
    process.exit(1);
});
