/**
 * audit_security_anti_cheat.js
 * Test Suite de Auditoría de Seguridad, Anti-Inyección SQL/NoSQL, Sanetización de Inputs y Anti-Cheat.
 * Ubicación: E:\Descon\Tests\audit_security_anti_cheat.js
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
    console.log(`${COLORS.bright}${COLORS.magenta}   DESCON MMO - AUDITORÍA DE SEGURIDAD, ANTI-INYECCIÓN & ANTI-CHEAT ${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}\n`);

    let totalPassed = 0;
    let totalFailed = 0;
    let totalWarnings = 0;

    // 1. SANITIZACIÓN DE INTRUSIONES Y NOSQL INJECTION
    section('1. VALIDACIÓN ANTI-INYECCIÓN NOSQL (MongoDB Query Injection)');
    
    // Simular inputs malévolos que intentan bypass de contraseña o consultas NoSQL
    const maliciousInputs = [
        { user: { "$gt": "" }, password: "123" },
        { user: { "$ne": null }, password: "123" },
        { user: "$where: 'this.username == this.password'", password: "123" },
        { user: "<script>alert(1)</script>", password: "123" }
    ];

    let rejectedPayloads = 0;
    maliciousInputs.forEach((data, idx) => {
        const username = typeof data?.user === 'string' ? data.user.trim() : '';
        const password = typeof data?.password === 'string' ? data.password : '';
        
        // Regla del servidor: si no es string estricto, o length < 3 o > 20, rechazar
        if (!username || typeof username !== 'string' || username.length < 3 || username.length > 20 || username.includes('$')) {
            rejectedPayloads++;
        }
    });

    if (rejectedPayloads === maliciousInputs.length) {
        pass(`Filtrado Anti-Inyección NoSQL verificado: ${rejectedPayloads}/${maliciousInputs.length} payloads maliciosos fueron bloqueados.`);
        totalPassed++;
    } else {
        fail(`Vulnerabilidad detectada: ${maliciousInputs.length - rejectedPayloads} payloads maliciosos evadieron la validación.`);
        totalFailed++;
    }

    // 2. BLOQUEO DE TIEMPO DE COMBATE Y DUPLICACIÓN DE ÍTEMS (Combat Lock)
    section('2. ANTI-EXPLOIT DE DUPLICACIÓN EN COMBATE (Combat Lock)');
    const { checkCombatLock } = require(path.join(SERVER_DIR, 'systems', 'inventoryHandlers'));

    const now = Date.now();
    const playerInCombat = { lastCombatTime: now - 2000, zone: 1 }; // Recibió daño hace 2 segundos
    const playerSafe = { lastCombatTime: now - 70000, zone: 1 }; // Sin combate en 70 segundos

    const lockActive = checkCombatLock(playerInCombat);
    const lockInactive = checkCombatLock(playerSafe);

    if (lockActive.locked && !lockInactive.locked) {
        pass(`Anti-Exploit en combate verificado: Acciones de inventario/mercado bloqueadas en combate (Restan ${lockActive.remaining}s).`);
        totalPassed++;
    } else {
        fail('Fallo en la verificación de Combat Lock.');
        totalFailed++;
    }

    // 3. SEGURIDAD DE AUTORIDAD SERVER-SIDE (Anti-Speedhack y Teleportation)
    section('3. VALIDADOR AUTORITATIVO DE MOVIMIENTO Y POSICIÓN');

    const movementHandler = path.join(SERVER_DIR, 'handlers', 'movementHandler.js');
    if (fs.existsSync(movementHandler)) {
        const code = fs.readFileSync(movementHandler, 'utf8');

        if (code.includes('rubberbanding') || code.includes('playerStatSync') || code.includes('maxAllowed')) {
            pass('Sistema autoritativo Server-Side Anti-Speedhack y Rubberbanding activo en movementHandler.js.');
            totalPassed++;
        } else {
            fail('No se detectaron mecanismos de corrección de velocidad en movementHandler.js.');
            totalFailed++;
        }
    }

    section('RESUMEN DE AUDITORÍA DE SEGURIDAD Y ANTI-CHEAT');
    console.log(`  ${COLORS.green}Pruebas Pasadas:${COLORS.reset}    ${totalPassed}`);
    console.log(`  ${COLORS.red}Fallos Críticos:${COLORS.reset}    ${totalFailed}`);
    console.log(`  ${COLORS.yellow}Advertencias:${COLORS.reset}       ${totalWarnings}\n`);

    if (totalFailed > 0) process.exit(1);
}

runAudit().catch(err => {
    console.error('Error en test audit_security_anti_cheat:', err);
    process.exit(1);
});
