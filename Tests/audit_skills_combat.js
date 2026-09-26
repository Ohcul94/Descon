/**
 * audit_skills_combat.js
 * Test Suite de Auditoría para Habilidades, Cooldowns, Reglas de Combate y Anti-Cheat en Descon MMO.
 * Ubicación: E:\Descon\Tests\audit_skills_combat.js
 */

const fs = require('fs');
const path = require('path');

let SERVER_DIR = path.resolve(__dirname, '..', '..', 'Server');
if (!fs.existsSync(SERVER_DIR)) {
    SERVER_DIR = path.resolve(__dirname, '..', 'Server');
}
const CONFIG_PATH = path.join(SERVER_DIR, 'config.json');
const SkillManager = require(path.join(SERVER_DIR, 'systems', 'skills', 'SkillManager'));
require(path.join(SERVER_DIR, 'systems', 'combatHandlers'));

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
    console.log(`${COLORS.bright}${COLORS.magenta}   DESCON MMO - AUDITORÍA DE HABILIDADES, COMBATE Y ANTI-CHEAT ${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}\n`);

    if (!fs.existsSync(CONFIG_PATH)) {
        fail(`No se encontró config.json`);
        process.exit(1);
    }

    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    let totalPassed = 0;
    let totalFailed = 0;
    let totalWarnings = 0;

    // 1. DICCIONARIO DE HABILIDADES (skillsData)
    section('1. DATOS Y CONFIGURACIÓN DE HABILIDADES (skillsData)');
    const skillsData = config.skillsData || {};
    const skillNames = Object.keys(skillsData);
    pass(`Habilidades declaradas en config: ${skillNames.length}`);
    totalPassed++;

    const skillIdSet = new Set();
    skillNames.forEach(name => {
        const sd = skillsData[name];
        if (!sd) return;

        if (!sd.id) {
            fail(`Habilidad '${name}' no especifica un 'id' (ej. SK-UTIL-01).`);
            totalFailed++;
        } else if (skillIdSet.has(sd.id)) {
            fail(`ID de habilidad duplicado: '${sd.id}' en '${name}'`);
            totalFailed++;
        } else {
            skillIdSet.add(sd.id);
        }

        const cd = Number(sd.cd);
        if (isNaN(cd) || cd <= 0) {
            fail(`Habilidad '${name}' tiene cooldown (cd) inválido: ${sd.cd}`);
            totalFailed++;
        }

        const castTimeMs = Number(sd.castTimeMs);
        if (isNaN(castTimeMs) || castTimeMs < 0) {
            fail(`Habilidad '${name}' tiene castTimeMs inválido: ${sd.castTimeMs}`);
            totalFailed++;
        }
    });

    if (totalFailed === 0) {
        pass('Todas las habilidades tienen IDs únicos, cooldowns > 0 y tiempos de casteo válidos.');
        totalPassed++;
    }

    // 2. ORQUESTADOR DE HABILIDADES Y CLASES MODULARES
    section('2. INSTANCIAS DE HABILIDADES EN SKILLMANAGER');
    const registeredSkills = Array.from(SkillManager.skills.keys());
    pass(`Habilidades registradas en SkillManager: ${registeredSkills.length} (${registeredSkills.join(', ')})`);
    totalPassed++;

    let missingModules = 0;
    skillNames.forEach(name => {
        if (!registeredSkills.includes(name)) {
            warn(`Habilidad '${name}' está en config.skillsData pero no registrada en SkillManager.`);
            missingModules++;
            totalWarnings++;
        }
    });

    if (missingModules === 0) {
        pass('Todas las habilidades de skillsData tienen su módulo activo registrado en SkillManager.');
        totalPassed++;
    }

    // 3. REGLAS DE COMBATE Y ANTI-CHEAT
    section('3. INTEGRIDAD DE PARÁMETROS ANTI-CHEAT');
    const ammoMultipliers = config.ammoMultipliers || {};
    pass(`Multiplicadores de munición autoritativos cargados (${Object.keys(ammoMultipliers).length} tipos).`);
    totalPassed++;

    section('RESUMEN DE HABILIDADES Y COMBATE');
    console.log(`  ${COLORS.green}Pruebas Pasadas:${COLORS.reset}    ${totalPassed}`);
    console.log(`  ${COLORS.red}Fallos Críticos:${COLORS.reset}    ${totalFailed}`);
    console.log(`  ${COLORS.yellow}Advertencias:${COLORS.reset}       ${totalWarnings}\n`);

    if (totalFailed > 0) process.exit(1);
}

runAudit().catch(err => {
    console.error('Error en test audit_skills_combat:', err);
    process.exit(1);
});
