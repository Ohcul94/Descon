/**
 * audit_quests.js
 * Test Suite de Auditoría para Misiones, Recompensas y Desbloqueos en Descon MMO.
 * Ubicación: E:\Descon\Tests\audit_quests.js
 */

const fs = require('fs');
const path = require('path');

let SERVER_DIR = path.resolve(__dirname, '..', '..', 'Server');
if (!fs.existsSync(SERVER_DIR)) {
    SERVER_DIR = path.resolve(__dirname, '..', 'Server');
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
    console.log(`${COLORS.bright}${COLORS.magenta}   DESCON MMO - AUDITORÍA DE MISIONES, RECOMPENSAS Y UNLOCKS ${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}\n`);

    if (!fs.existsSync(CONFIG_PATH)) {
        fail(`No se encontró config.json`);
        process.exit(1);
    }

    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    let totalPassed = 0;
    let totalFailed = 0;
    let totalWarnings = 0;

    // 1. ESTRUCTURA DE MISIONES (questsConfig)
    section('1. ESTRUCTURA Y VALIDACIÓN DE MISIONES');
    const questsConfig = Array.isArray(config.questsConfig) ? config.questsConfig : [];
    pass(`Misiones configuradas totales: ${questsConfig.length}`);
    totalPassed++;

    const questIdMap = new Set();
    const validTypes = ['main', 'side', 'daily', 'weekly'];

    questsConfig.forEach((q, idx) => {
        if (!q.id) {
            fail(`Misión en índice ${idx} no tiene ID.`);
            totalFailed++;
        } else if (questIdMap.has(String(q.id))) {
            fail(`ID de misión duplicado: '${q.id}'`);
            totalFailed++;
        } else {
            questIdMap.add(String(q.id));
        }

        if (q.type && !validTypes.includes(q.type)) {
            warn(`Misión '${q.id}' (${q.title || q.name}) tiene un tipo no estándar: '${q.type}'`);
            totalWarnings++;
        }

        // Recompensas
        const rewards = q.rewards || {};
        if (rewards.xp !== undefined && rewards.xp < 0) {
            fail(`Misión '${q.id}' otorga XP negativa: ${rewards.xp}`);
            totalFailed++;
        }
        if (rewards.hubs !== undefined && rewards.hubs < 0) {
            fail(`Misión '${q.id}' otorga Hubs negativos: ${rewards.hubs}`);
            totalFailed++;
        }

        // Objetivos / Targets
        if (Array.isArray(q.targets)) {
            q.targets.forEach((tgt, tIdx) => {
                if (!tgt.targetId && !tgt.type) {
                    warn(`Misión '${q.id}' tiene objetivo [${tIdx}] incompleto.`);
                    totalWarnings++;
                }
                if (tgt.count !== undefined && tgt.count <= 0) {
                    fail(`Misión '${q.id}' tiene conteo de objetivo <= 0: ${tgt.count}`);
                    totalFailed++;
                }
            });
        }
    });

    if (totalFailed === 0) {
        pass('Todas las misiones configuradas tienen IDs únicos y recompensas válidas.');
        totalPassed++;
    }

    // 2. DESBLOQUEOS POR MISIÓN Y TALENTOS
    section('2. CLAVES DE DESBLOQUEO (talentsLockedConfig)');
    const lockedTalents = Array.isArray(config.talentsLockedConfig) ? config.talentsLockedConfig : [];
    pass(`Talentos sellados por misión: ${lockedTalents.length}`);
    totalPassed++;

    lockedTalents.forEach(entry => {
        if (!entry.category || entry.index === undefined) {
            fail(`Entrada en talentsLockedConfig mal estructurada: ${JSON.stringify(entry)}`);
            totalFailed++;
        }
    });

    section('RESUMEN DE MISIONES Y UNLOCKS');
    console.log(`  ${COLORS.green}Pruebas Pasadas:${COLORS.reset}    ${totalPassed}`);
    console.log(`  ${COLORS.red}Fallos Críticos:${COLORS.reset}    ${totalFailed}`);
    console.log(`  ${COLORS.yellow}Advertencias:${COLORS.reset}       ${totalWarnings}\n`);

    if (totalFailed > 0) process.exit(1);
}

runAudit().catch(err => {
    console.error('Error en test audit_quests:', err);
    process.exit(1);
});
