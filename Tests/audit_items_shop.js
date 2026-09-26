/**
 * audit_items_shop.js
 * Test Suite de Auditoría para Tienda, Ítems, Naves y Crafting en Descon MMO.
 * Ubicación: E:\Descon\Tests\audit_items_shop.js
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
    console.log(`${COLORS.bright}${COLORS.magenta}   DESCON MMO - AUDITORÍA DE TIENDA, ÍTEMS, NAVES Y CRAFTING ${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}\n`);

    if (!fs.existsSync(CONFIG_PATH)) {
        fail(`No se encontró config.json`);
        process.exit(1);
    }

    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    let totalPassed = 0;
    let totalFailed = 0;
    let totalWarnings = 0;

    // 1. MODELOS DE NAVES (shipModels)
    section('1. MODELOS DE NAVES (shipModels)');
    const shipModels = Array.isArray(config.shipModels) ? config.shipModels : [];
    pass(`Modelos de nave cargados: ${shipModels.length}`);
    totalPassed++;

    const shipIdMap = new Set();
    shipModels.forEach((m, idx) => {
        if (!m.id) { fail(`Nave index ${idx} no tiene ID`); totalFailed++; }
        else if (shipIdMap.has(m.id)) { fail(`ID de nave duplicado: ${m.id}`); totalFailed++; }
        else shipIdMap.add(m.id);

        if (!m.hp || m.hp <= 0) { fail(`Nave '${m.name || m.id}' tiene HP nulo o <= 0`); totalFailed++; }
        if (!m.shield || m.shield < 0) { fail(`Nave '${m.name || m.id}' tiene Escudo inválido`); totalFailed++; }
        if (!m.speed || m.speed <= 0) { fail(`Nave '${m.name || m.id}' tiene Velocidad nula o <= 0`); totalFailed++; }
    });
    if (totalFailed === 0) pass('Todos los modelos de nave tienen HP, Escudo y Velocidad válidos.');

    // 2. TIENDA E ÍTEMS (shopItems)
    section('2. TIENDA E ÍTEMS DE EQUIPAMIENTO (shopItems)');
    const shop = config.shopItems || {};
    const categories = ['weapons', 'shields', 'engines', 'extra', 'spheres', 'drones'];
    const itemMasterMap = new Map();

    categories.forEach(cat => {
        const list = Array.isArray(shop[cat]) ? shop[cat] : [];
        pass(`Categoría de tienda '${cat}': ${list.length} ítems configurados.`);
        totalPassed++;

        list.forEach((item, idx) => {
            if (!item || typeof item !== 'object') return;
            if (!item.id) {
                fail(`Ítem en '${cat}' índice ${idx} no tiene 'id'`);
                totalFailed++;
            } else if (itemMasterMap.has(String(item.id))) {
                fail(`ID de ítem duplicado en tienda: '${item.id}'`);
                totalFailed++;
            } else {
                itemMasterMap.set(String(item.id), { ...item, shopCategory: cat });
            }

            // Validar precios
            if (item.hubs === undefined && item.price === undefined && item.cost === undefined && !item.hidden) {
                warn(`Ítem '${item.id}' (${item.name}) no especifica precio claro en hubs.`);
                totalWarnings++;
            }
        });
    });

    // 3. RECETAS DE CRAFTING (craftingRecipes)
    section('3. RECETAS DE CRAFTING (craftingRecipes)');
    const recipes = Array.isArray(config.craftingRecipes) ? config.craftingRecipes : [];
    pass(`Recetas de crafting cargadas: ${recipes.length}`);
    totalPassed++;

    recipes.forEach((r, idx) => {
        if (!r.id) { fail(`Receta index ${idx} sin ID`); totalFailed++; }
        if (r.resultItem && !itemMasterMap.has(String(r.resultItem))) {
            warn(`Receta '${r.id}' produce el ítem resultItem '${r.resultItem}' que no está en shopItems.`);
            totalWarnings++;
        }
        if (Array.isArray(r.materials)) {
            r.materials.forEach(mat => {
                if (!mat.id || !mat.count || mat.count <= 0) {
                    fail(`Receta '${r.id}' tiene un material inválido: ${JSON.stringify(mat)}`);
                    totalFailed++;
                }
            });
        }
    });

    section('RESUMEN DE TIENDA E ÍTEMS');
    console.log(`  ${COLORS.green}Pruebas Pasadas:${COLORS.reset}    ${totalPassed}`);
    console.log(`  ${COLORS.red}Fallos Críticos:${COLORS.reset}    ${totalFailed}`);
    console.log(`  ${COLORS.yellow}Advertencias:${COLORS.reset}       ${totalWarnings}\n`);

    if (totalFailed > 0) process.exit(1);
}

runAudit().catch(err => {
    console.error('Error en test audit_items_shop:', err);
    process.exit(1);
});
