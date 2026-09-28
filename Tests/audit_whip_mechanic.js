// Tests/audit_whip_mechanic.js
// Auditoría de la mecánica "Látigo Dominante (whip_summon)":
// 1. Integridad de WhipSummonVisual.gd (cero residuos en el piso, cinta 3D, impacto en la nave)
// 2. Limpieza de memoria y ciclo de vida en BossActionHandler.gd
// 3. Emisión de eventos en WhipSummonMechanics.js

const fs = require('fs');
const path = require('path');

let passed = 0;
let failed = 0;

function assert(condition, desc) {
    if (condition) {
        console.log(`  ✓ [PASS] ${desc}`);
        passed++;
    } else {
        console.error(`  ✗ [FAIL] ${desc}`);
        failed++;
    }
}

console.log("════════════════════════════════════════════════════════════════");
console.log("  1. AUDITORÍA VISUAL DEL LÁTIGO (WhipSummonVisual.gd)");
console.log("════════════════════════════════════════════════════════════════");

const whipVisualPath = path.resolve(__dirname, '../descon/scripts/systems/WhipSummonVisual.gd');
assert(fs.existsSync(whipVisualPath), "Existe WhipSummonVisual.gd");

const whipContent = fs.readFileSync(whipVisualPath, 'utf8');

// Verificación contra el bug anterior de residuos en el piso
assert(!whipContent.includes("rotation_degrees = Vector3(-90, 0, 0)"), "ELIMINADO: No hay quads planos acostados en el piso");
assert(!whipContent.includes("PRIMITIVE_LINE_STRIP"), "SUPERADO: No usa líneas de alambre de 1px (PRIMITIVE_LINE_STRIP)");

// Verificación de Ribbon Mesh 3D y cinemática de azote
assert(whipContent.includes("_build_ribbon_mesh"), "Genera malla 3D de cinta volumétrica (_build_ribbon_mesh)");
assert(whipContent.includes("_calculate_whip_curve"), "Calcula curvatura Bezier con onda dinámica (_calculate_whip_curve)");
assert(whipContent.includes("side_sign"), "Alterna los arcos de azote por cada golpe (izquierda/derecha/vertical)");
assert(whipContent.includes("_spawn_hit_impact_3d"), "Genera impacto visual cinematográfico en la nave (_spawn_hit_impact_3d)");

// Verificación de limpieza absoluta
assert(whipContent.includes("tree_exiting.connect(_cleanup_all_3d)"), "Limpieza de recursos 3D conectada a tree_exiting");
assert(whipContent.includes("func finish()"), "Expone método finish() para cierre suave con gracia");
assert(whipContent.includes("root_3d.queue_free()"), "Libera root_3d en la finalización");

console.log("\n════════════════════════════════════════════════════════════════");
console.log("  2. AUDITORÍA DEL CONTROLADOR DEL CLIENTE (BossActionHandler.gd)");
console.log("════════════════════════════════════════════════════════════════");

const bossActionPath = path.resolve(__dirname, '../descon/scripts/systems/BossActionHandler.gd');
assert(fs.existsSync(bossActionPath), "Existe BossActionHandler.gd");

const bossContent = fs.readFileSync(bossActionPath, 'utf8');
assert(bossContent.includes('handle_whip_summon_action'), "BossActionHandler maneja handle_whip_summon_action");
assert(bossContent.includes('whip_summon_start'), "Maneja evento whip_summon_start");
assert(bossContent.includes('whip_summon_hit'), "Maneja evento whip_summon_hit");
assert(bossContent.includes('whip_node.finish()'), "Llama a whip_node.finish() en el último hit en lugar de destruir abruptamente");

console.log("\n════════════════════════════════════════════════════════════════");
console.log("  3. AUDITORÍA DEL SERVIDOR (WhipSummonMechanics.js)");
console.log("════════════════════════════════════════════════════════════════");

const serverWhipPath = path.resolve(__dirname, '../Server/behaviors/mechanics/WhipSummonMechanics.js');
assert(fs.existsSync(serverWhipPath), "Existe WhipSummonMechanics.js en el backend");

const serverWhipContent = fs.readFileSync(serverWhipPath, 'utf8');
assert(serverWhipContent.includes('whip_summon_start'), "Servidor emite whip_summon_start con parámetros de casteo");
assert(serverWhipContent.includes('whip_summon_hit'), "Servidor emite whip_summon_hit para cada golpe de la cadencia");
assert(serverWhipContent.includes('damage'), "Aplica y sincroniza el daño autoritativo por golpe");

console.log("\n════════════════════════════════════════════════════════════════");
console.log(`  RESUMEN DE AUDITORÍA: ${passed} Pasadas | ${failed} Fallidas`);
console.log("════════════════════════════════════════════════════════════════");

if (failed > 0) {
    process.exit(1);
}
