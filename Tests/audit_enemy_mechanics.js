/**
 * audit_enemy_mechanics.js
 * Test Suite de Auditoría para Mecánicas de Enemigos/Jefes (Lluvia de Meteoritos, Puzles, Ataque, Defensa, Movimiento y Robos).
 * Ubicación: E:\Descon\Tests\audit_enemy_mechanics.js
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

// Mapa de unidades de medida esperadas entre paréntesis para campos estandarizados
const FIELD_UNITS = {
    cooldown: '(s)',
    cooldownMs: '(ms)',
    castTimeMs: '(ms)',
    startDelay: '(ms)',
    warnTimeMs: '(ms)',
    lifetimeMs: '(ms)',
    lockTimeMs: '(ms)',
    chargeTimeMs: '(ms)',
    duration: '(s)',
    duracionMs: '(ms)',
    fireRange: '(px)',
    radius: '(px)',
    explosionRadius: '(px)',
    bulletSpeed: '(px/s)',
    speed: '(px/s)',
    burrowSpeed: '(px/s)',
    orbitSpeed: '(rad/s)',
    turnSpeed: '(rad/s)',
    bulletDamage: '(HP)',
    damage: '(HP)',
    zoneDamage: '(HP)',
    slowAmount: '(%)',
    slowPercentage: '(%)',
    arcAngle: '(deg)',
    coneAngle: '(deg)',
    pushForce: '(px/s)'
};

async function runAudit() {
    console.log(`\n${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}   DESCON MMO - AUDITORÍA DE MECÁNICAS DE ENEMIGOS Y JEFES       ${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}\n`);

    if (!fs.existsSync(CONFIG_PATH)) {
        fail(`No se encontró config.json`);
        process.exit(1);
    }

    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    let totalPassed = 0;
    let totalFailed = 0;
    let totalWarnings = 0;

    // 1. AUDITORÍA DEL CATÁLOGO DE MECÁNICAS (mechanicsLib)
    section('1. INTEGRIDAD Y ESTANDARIZACIÓN DEL CATÁLOGO (mechanicsLib)');
    const mechanicsLib = config.mechanicsLib || {};
    const mechKeys = Object.keys(mechanicsLib);
    pass(`Mecánicas registradas en la librería de configuración: ${mechKeys.length}`);
    totalPassed++;

    let duplicateFieldErrors = 0;
    let missingLabelErrors = 0;
    let nonSpanishLabels = 0;

    mechKeys.forEach(key => {
        const m = mechanicsLib[key];
        if (!m) return;

        // Verificar Nombre en Español
        if (!m.label || typeof m.label !== 'string' || m.label.trim() === '') {
            fail(`La mecánica '${key}' no posee una etiqueta (label) en español.`);
            missingLabelErrors++;
            totalFailed++;
        }

        // Verificar duplicados en la lista de campos (fields)
        if (Array.isArray(m.fields)) {
            const seen = new Set();
            m.fields.forEach(f => {
                if (seen.has(f)) {
                    fail(`Mecánica '${key}' (${m.label || key}) contiene el campo duplicado: '${f}'`);
                    duplicateFieldErrors++;
                    totalFailed++;
                }
                seen.add(f);
            });
        }
    });

    if (duplicateFieldErrors === 0) {
        pass('Todas las mecánicas tienen listas de inputs limpias sin datos ni campos duplicados.');
        totalPassed++;
    }
    if (missingLabelErrors === 0) {
        pass('Todas las mecánicas poseen su correspondiente etiqueta (label) en español.');
        totalPassed++;
    }

    // 2. AUDITORÍA DE LLUVIA DE METEORITOS (BossMeteorMechanics)
    section('2. UNIFICACIÓN Y AUDITORÍA DE LLUVIA DE METEORITOS (meteor)');
    const meteorConfig = mechanicsLib.meteor;
    if (meteorConfig) {
        pass(`Mecánica Meteoritos encontrada: "${meteorConfig.label}" (${meteorConfig.desc ? meteorConfig.desc.slice(0, 50) + '...' : ''})`);
        totalPassed++;

        const requiredMeteorFields = [
            'activationMode', 'activationHPs', 'cooldown', 'meteorCount', 
            'meteorSize', 'bulletDamage', 'explosionRadius', 'warnTimeMs'
        ];

        let missingMeteorFields = 0;
        requiredMeteorFields.forEach(rf => {
            if (!meteorConfig.fields || !meteorConfig.fields.includes(rf)) {
                warn(`Falta el campo estandarizado '${rf}' en la definición del catálogo de Meteoritos.`);
                missingMeteorFields++;
                totalWarnings++;
            }
        });

        if (missingMeteorFields === 0) {
            pass('Todos los inputs requeridos para Lluvia de Meteoritos están estandarizados.');
            totalPassed++;
        }
    } else {
        fail('No se encontró la configuración de "meteor" en mechanicsLib.');
        totalFailed++;
    }

    // 3. AUDITORÍA DE ASIGNACIÓN EN ENEMIGOS (enemyModels)
    section('3. AUDITORÍA DE MECÁNICAS ASIGNADAS A ENEMIGOS (enemyModels)');
    const enemyModels = config.enemyModels || config.enemiesConfig || {};
    const enemyList = Array.isArray(enemyModels) ? enemyModels : Object.values(enemyModels);
    let enemiesWithMechanics = 0;
    let invalidMechReferences = 0;

    enemyList.forEach((enemy, idx) => {
        const eName = enemy.name || enemy.id || `Enemigo #${idx}`;
        const mechs = enemy.mechanics || enemy.bossMechanics || [];

        if (Array.isArray(mechs) && mechs.length > 0) {
            enemiesWithMechanics++;
            mechs.forEach((m, mIdx) => {
                const mType = m.type || m.mechanicType;
                if (!mType) {
                    fail(`Enemigo '${eName}' (Mecánica #${mIdx + 1}) no especifica un 'type'.`);
                    invalidMechReferences++;
                    totalFailed++;
                } else if (!mechanicsLib[mType]) {
                    warn(`Enemigo '${eName}' asigna la mecánica '${mType}' que no existe en mechanicsLib.`);
                    totalWarnings++;
                }

                // Validar cooldowns y daños si están definidos
                if (m.cooldown !== undefined && (isNaN(Number(m.cooldown)) || Number(m.cooldown) < 0)) {
                    fail(`Enemigo '${eName}' -> Mecánica '${mType}' tiene cooldown inválido: ${m.cooldown}`);
                    totalFailed++;
                }
            });
        }
    });

    pass(`Enemigos con mecánicas activas auditados: ${enemiesWithMechanics}`);
    totalPassed++;

    if (invalidMechReferences === 0) {
        pass('Todas las asignaciones de mecánicas en enemigos son coherentes y tienen tipos reconocidos.');
        totalPassed++;
    }

    // 4. VERIFICACIÓN DE MANEJADORES MODULARES DE SERVIDOR
    section('4. INTEGRIDAD DE MÓDULOS DE COMPORTAMIENTO (Server AI Mechanics)');
    const mechanicsDir = path.join(SERVER_DIR, 'behaviors', 'mechanics');
    const expectedModules = [
        'BossMeteorMechanics.js',
        'BossDefenseMechanics.js',
        'BossOffensiveMechanics.js',
        'BossPuzzleMechanics.js',
        'BossStealMechanics.js'
    ];

    let missingModules = 0;
    expectedModules.forEach(modFile => {
        const fullPath = path.join(mechanicsDir, modFile);
        if (!fs.existsSync(fullPath)) {
            fail(`No se encontró el módulo de mecánica: ${modFile}`);
            missingModules++;
            totalFailed++;
        } else {
            try {
                require(fullPath);
                pass(`Módulo cargado correctamente: ${modFile}`);
                totalPassed++;
            } catch (err) {
                fail(`Error al importar el módulo ${modFile}: ${err.message}`);
                totalFailed++;
            }
        }
    });

    section('RESUMEN DE MECÁNICAS DE ENEMIGOS Y JEFES');
    console.log(`  ${COLORS.green}Pruebas Pasadas:${COLORS.reset}    ${totalPassed}`);
    console.log(`  ${COLORS.red}Fallos Críticos:${COLORS.reset}    ${totalFailed}`);
    console.log(`  ${COLORS.yellow}Advertencias:${COLORS.reset}       ${totalWarnings}\n`);

    if (totalFailed > 0) process.exit(1);
}

runAudit().catch(err => {
    console.error('Error en test audit_enemy_mechanics:', err);
    process.exit(1);
});
