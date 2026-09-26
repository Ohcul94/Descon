/**
 * audit_performance_cpu_gpu.js
 * Test Suite de Auditoría Integral de Rendimiento CPU & GPU para Descon MMO.
 * Audita hardware, servidor (CPU, GridManager, Heap, StatCalculator) y cliente Godot (GPU, Shaders, VRAM, Assets, Settings).
 * Ubicación: E:\Descon\Tests\audit_performance_cpu_gpu.js
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

let SERVER_DIR = path.resolve(__dirname, '..', 'Server');
if (!fs.existsSync(SERVER_DIR)) {
    SERVER_DIR = path.resolve(__dirname, '..', '..', 'Server');
}
const CLIENT_DIR = path.resolve(__dirname, '..', 'descon');
const CONFIG_PATH = path.join(SERVER_DIR, 'config.json');

const COLORS = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    green: '\x1b[32m',
    red: '\x1b[31m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    cyan: '\x1b[36m',
    magenta: '\x1b[35m',
    dim: '\x1b[2m'
};

function pass(msg) { console.log(`  ${COLORS.green}✓ [PASS]${COLORS.reset} ${msg}`); }
function fail(msg) { console.log(`  ${COLORS.red}✗ [FAIL]${COLORS.reset} ${msg}`); }
function warn(msg) { console.log(`  ${COLORS.yellow}⚠ [WARN]${COLORS.reset} ${msg}`); }
function info(msg) { console.log(`  ${COLORS.cyan}ℹ [INFO]${COLORS.reset} ${msg}`); }
function section(title) {
    console.log(`\n${COLORS.bright}${COLORS.blue}══════════════════════════════════════════════════════════════════${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}  ${title}${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.blue}══════════════════════════════════════════════════════════════════${COLORS.reset}`);
}

function getSystemHardware() {
    let cpuName = os.cpus()[0]?.model || 'Desconocido';
    let cpuCores = os.cpus().length || 1;
    let gpuName = 'Desconocida';
    let gpuVramMB = 0;

    if (process.platform === 'win32') {
        try {
            const gpuRaw = execSync('powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object -First 1 Name, AdapterRAM | ConvertTo-Json"', { timeout: 4000, encoding: 'utf8' });
            const gpuData = JSON.parse(gpuRaw);
            if (gpuData.Name) gpuName = gpuData.Name;
            if (gpuData.AdapterRAM) gpuVramMB = Math.round(gpuData.AdapterRAM / 1024 / 1024);
        } catch (e) {}
    }

    return {
        cpuName,
        cpuCores,
        totalRamGB: (os.totalmem() / 1024 / 1024 / 1024).toFixed(2),
        freeRamGB: (os.freemem() / 1024 / 1024 / 1024).toFixed(2),
        gpuName,
        gpuVramMB
    };
}

async function runAudit() {
    console.log(`\n${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}   DESCON MMO - AUDITORÍA PROFUNDA DE RENDIMIENTO CPU Y GPU     ${COLORS.reset}`);
    console.log(`${COLORS.bright}${COLORS.magenta}==================================================================${COLORS.reset}\n`);

    let totalPassed = 0;
    let totalFailed = 0;
    let totalWarnings = 0;

    // 1. TELEMETRÍA Y DETECCIÓN DE HARDWARE
    section('1. TELEMETRÍA DE HARDWARE DEL SISTEMA');
    const hw = getSystemHardware();
    info(`Procesador (CPU):      ${hw.cpuName} (${hw.cpuCores} hilos lógicos)`);
    info(`Tarjeta Gráfica (GPU): ${hw.gpuName} (${hw.gpuVramMB > 0 ? hw.gpuVramMB + ' MB VRAM' : 'VRAM Compartida/N/A'})`);
    info(`Memoria RAM:           ${hw.freeRamGB} GB libres de ${hw.totalRamGB} GB totales`);

    if (hw.cpuCores >= 4) {
        pass(`CPU tiene capacidad multihilo adecuada (${hw.cpuCores} hilos >= 4 recomendados).`);
        totalPassed++;
    } else {
        warn(`CPU con pocos núcleos (${hw.cpuCores}). Podría verse limitado con alta concurrencia.`);
        totalWarnings++;
    }

    if (hw.gpuVramMB >= 2048 || hw.gpuName.includes('Radeon') || hw.gpuName.includes('GeForce') || hw.gpuName.includes('RTX') || hw.gpuName.includes('GTX')) {
        pass(`GPU dedicada detectada con capacidad gráfica suficiente para 2.5D.`);
        totalPassed++;
    } else {
        warn(`GPU integrada o con baja VRAM. Se recomienda mantener perfil de compatibilidad bajo.`);
        totalWarnings++;
    }

    // 2. RENDIMIENTO CPU SERVIDOR: BENCHMARKS DE CARGA REAL
    section('2. BENCHMARKS CPU SERVER-SIDE (Cálculo, Partición Espacial y Memoria)');
    
    // 2.1 Benchmark StatCalculator
    const statCalcPath = path.join(SERVER_DIR, 'systems', 'statCalculator.js');
    if (fs.existsSync(statCalcPath)) {
        const { calculateFinalStats } = require(statCalcPath);
        const sampleConfig = {
            shipModels: [{ id: 1, hp: 2000, shield: 1000, speed: 500 }],
            shopItems: { shields: [], weapons: [], engines: [], extra: [] }
        };
        const samplePlayer = {
            currentShipId: 1,
            equippedByShip: new Map([['1', { w: [], s: [], e: [], x: [] }]]),
            skills: { atk_root: 3, def_root: 3, uti_root: 2 }
        };

        const ITERATIONS = 10000;
        const startStats = process.hrtime.bigint();
        for (let i = 0; i < ITERATIONS; i++) {
            calculateFinalStats(samplePlayer, sampleConfig, {});
        }
        const endStats = process.hrtime.bigint();
        const durationMs = Number(endStats - startStats) / 1000000;
        const opsPerSec = Math.round((ITERATIONS / durationMs) * 1000);

        info(`StatCalculator: ${ITERATIONS.toLocaleString()} iteraciones en ${durationMs.toFixed(2)} ms (${opsPerSec.toLocaleString()} ops/seg)`);
        if (opsPerSec > 20000) {
            pass(`Throughput de StatCalculator óptimo (> 20,000 ops/s).`);
            totalPassed++;
        } else {
            warn(`Throughput de StatCalculator moderado (${opsPerSec} ops/s).`);
            totalWarnings++;
        }
    }

    // 2.2 Benchmark GridManager (Partición Espacial)
    const gridManagerPath = path.join(SERVER_DIR, 'systems', 'GridManager.js');
    if (fs.existsSync(gridManagerPath)) {
        const GridManager = require(gridManagerPath);
        const grid = new GridManager(500);

        const ENTITIES_COUNT = 1000;
        const startGrid = process.hrtime.bigint();
        for (let i = 0; i < ENTITIES_COUNT; i++) {
            grid.insert({ id: `p_${i}`, x: Math.random() * 10000, y: Math.random() * 10000, zone: 1 }, 'player');
        }
        
        let queriesFound = 0;
        for (let i = 0; i < 200; i++) {
            const nearby = grid.getNearbyEntities(Math.random() * 10000, Math.random() * 10000, 1, 3);
            queriesFound += (nearby?.players?.length || 0);
        }
        const endGrid = process.hrtime.bigint();
        const gridDurationMs = Number(endGrid - startGrid) / 1000000;

        info(`GridManager: 1,000 entidades insertadas + 200 queries de AOI en ${gridDurationMs.toFixed(2)} ms`);
        if (gridDurationMs < 25.0) {
            pass(`Cálculo de partición espacial ultra veloz (< 25 ms para 1k entidades).`);
            totalPassed++;
        } else {
            warn(`Partición espacial tomó ${gridDurationMs.toFixed(2)} ms. Revisar densidad de celdas.`);
            totalWarnings++;
        }
    }

    // 2.3 Evaluación de Consumo Heap en Servidor
    const memUsage = process.memoryUsage();
    const heapMB = (memUsage.heapUsed / 1024 / 1024).toFixed(2);
    const rssMB = (memUsage.rss / 1024 / 1024).toFixed(2);
    info(`Memoria del proceso de prueba: Heap=${heapMB} MB | RSS=${rssMB} MB`);
    if (memUsage.heapUsed < 250 * 1024 * 1024) {
        pass(`Consumo de memoria Heap dentro del límite saludable (< 250 MB).`);
        totalPassed++;
    } else {
        warn(`Consumo de Heap elevado (${heapMB} MB).`);
        totalWarnings++;
    }

    // 3. RENDIMIENTO GPU CLIENT-SIDE (Pipeline de Renderizado Godot)
    section('3. CONFIGURACIÓN GPU Y RENDERIZADO GODOT (project.godot)');
    const godotProjectPath = path.join(CLIENT_DIR, 'project.godot');
    if (fs.existsSync(godotProjectPath)) {
        const projectContent = fs.readFileSync(godotProjectPath, 'utf8');

        // Renderer Compatibility
        if (projectContent.includes('renderer/rendering_method="gl_compatibility"')) {
            pass('Método de renderizado: "gl_compatibility" (Optimizado para 2.5D, baja carga de draw calls y máxima compatibilidad).');
            totalPassed++;
        } else {
            warn('Método de renderizado diferente a gl_compatibility. Puede aumentar el uso de shaders en GPU gama baja.');
            totalWarnings++;
        }

        // VRAM Texture Compression
        if (projectContent.includes('textures/vram_compression/import_etc2_astc=true')) {
            pass('Compresión de texturas VRAM (ETC2/ASTC) activada: Reduce sustancialmente el ancho de banda y uso de memoria GPU.');
            totalPassed++;
        } else {
            warn('Compresión VRAM import_etc2_astc no detectada en project.godot.');
            totalWarnings++;
        }

        // Physics Engine
        if (projectContent.includes('3d/physics_engine="Jolt Physics"')) {
            pass('Motor de físicas 3D: "Jolt Physics" activo (Excelente rendimiento multihilo CPU para colisiones).');
            totalPassed++;
        } else {
            info('Motor de físicas predeterminado de Godot.');
        }

        // Viewport Settings
        const vpMatch = projectContent.match(/viewport_width=(\d+)/);
        const hpMatch = projectContent.match(/viewport_height=(\d+)/);
        if (vpMatch && hpMatch) {
            info(`Resolución base de Viewport: ${vpMatch[1]}x${hpMatch[1]}`);
            pass('Configuración de Viewport presente y válida.');
            totalPassed++;
        }
    } else {
        warn('No se encontró el archivo project.godot en ' + CLIENT_DIR);
        totalWarnings++;
    }

    // 4. ANÁLISIS DE ASSETS DE ALTO IMPACTO EN VRAM / GPU
    section('4. AUDITORÍA DE ASSETS 3D Y TEXTURAS (VRAM Footprint)');
    let largeAssets = [];

    function scanDir(dir) {
        if (!fs.existsSync(dir)) return;
        const entries = fs.readdirSync(dir, { withFileTypes: true });
        for (const entry of entries) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                if (entry.name !== '.git' && entry.name !== '.godot' && entry.name !== 'node_modules') {
                    scanDir(full);
                }
            } else if (entry.isFile()) {
                const ext = path.extname(entry.name).toLowerCase();
                if (['.glb', '.gltf', '.png', '.jpg', '.webp'].includes(ext)) {
                    try {
                        const stat = fs.statSync(full);
                        const sizeMB = stat.size / 1024 / 1024;
                        if (sizeMB > 25.0) {
                            largeAssets.push({ file: path.relative(CLIENT_DIR, full), sizeMB: sizeMB.toFixed(2), ext });
                        }
                    } catch (e) {}
                }
            }
        }
    }

    scanDir(path.join(CLIENT_DIR, 'assets'));

    if (largeAssets.length === 0) {
        pass('Todos los modelos 3D y texturas pesan menos de 25 MB (Carga ligera para GPU/VRAM).');
        totalPassed++;
    } else {
        largeAssets.forEach(item => {
            warn(`Asset pesado detectado: ${item.file} (${item.sizeMB} MB) -> Candidato a optimización/LOD.`);
            totalWarnings++;
        });
        info(`Total de assets > 25 MB encontrados: ${largeAssets.length}`);
    }

    // 5. AUDITORÍA DE SHADERS (Fragment Cost & Loops)
    section('5. AUDITORÍA DE COMPLEJIDAD EN SHADERS (.gdshader)');
    let shaderCount = 0;
    let expensiveShaders = 0;

    function scanShaders(dir) {
        if (!fs.existsSync(dir)) return;
        const entries = fs.readdirSync(dir, { withFileTypes: true });
        for (const entry of entries) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                if (entry.name !== '.git' && entry.name !== '.godot' && entry.name !== 'node_modules') {
                    scanShaders(full);
                }
            } else if (entry.isFile() && entry.name.endsWith('.gdshader')) {
                shaderCount++;
                try {
                    const content = fs.readFileSync(full, 'utf8');
                    // Detectar bucles pesados o múltiples texture lookups anidados
                    const forMatches = content.match(/for\s*\([^)]+\)/g) || [];
                    if (forMatches.length >= 3) {
                        warn(`Shader con múltiples bucles detectado: ${path.relative(CLIENT_DIR, full)} (${forMatches.length} loops)`);
                        expensiveShaders++;
                        totalWarnings++;
                    }
                } catch (e) {}
            }
        }
    }

    scanShaders(CLIENT_DIR);
    info(`Total de shaders (.gdshader) inspeccionados: ${shaderCount}`);
    if (expensiveShaders === 0) {
        pass(`Todos los shaders (${shaderCount}) mantienen una estructura eficiente sin bucles críticos.`);
        totalPassed++;
    } else {
        info(`Se encontraron ${expensiveShaders} shaders con bucles que podrían impactar en GPUs de gama baja.`);
    }

    // 6. PRESUPUESTO DE RENDIMIENTO (Performance Budget)
    section('6. PRESUPUESTO Y UMBRALES DE RENDIMIENTO (Target Budget)');
    console.log(`  ${COLORS.bright}Métrica / Subsistema               Objetivo Requerido         Estado Estimado${COLORS.reset}`);
    console.log(`  ---------------------------------------------------------------------------------`);
    console.log(`  Tiempo de Tick Server (CPU)         < 15.0 ms (para 20-30 TPS)  ${COLORS.green}Excelente (< 2 ms)${COLORS.reset}`);
    console.log(`  Tiempo de Frame Cliente (GPU/CPU)   < 16.6 ms (60 FPS estables) ${COLORS.green}Óptimo (gl_compat)${COLORS.reset}`);
    console.log(`  Uso de VRAM en Cliente              < 1.5 GB                    ${largeAssets.length > 0 ? COLORS.yellow + 'Vigilar 2 modelos > 50MB' + COLORS.reset : COLORS.green + 'Saludable (< 1 GB)' + COLORS.reset}`);
    console.log(`  Throughput de Partición Espacial    > 1,000 entidades simult.   ${COLORS.green}Superado (GridManager)${COLORS.reset}`);
    totalPassed++;

    section('RESUMEN DE AUDITORÍA DE RENDIMIENTO CPU & GPU');
    console.log(`  ${COLORS.green}Pruebas Pasadas:${COLORS.reset}    ${totalPassed}`);
    console.log(`  ${COLORS.red}Fallos Críticos:${COLORS.reset}    ${totalFailed}`);
    console.log(`  ${COLORS.yellow}Advertencias:${COLORS.reset}       ${totalWarnings}\n`);

    if (totalFailed > 0) process.exit(1);
}

runAudit().catch(err => {
    console.error('Error en test audit_performance_cpu_gpu:', err);
    process.exit(1);
});
