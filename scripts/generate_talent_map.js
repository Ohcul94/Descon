/**
 * Genera el mapa de talentos:
 * 4 ramas (keystone) → 2 notables → 2 smalls por notable
 * Sin conexiones entre ramas. Respeta distancias mínimas.
 */
const fs = require('fs');
const path = require('path');

const CONFIG_PATH = path.join(__dirname, '..', 'Server', 'config.json');

// ── Geometría (coordenadas de mundo, y hacia abajo como en el canvas) ──
const D_KESTONE_FROM_CENTER = 170; // keystone → centro
const D_MED_FROM_KESTONE = 165;    // keystone → notable
const D_SMALL_FROM_MED = 135;      // notable → small
const SPREAD_MED_DEG = 36;         // ángulo ± entre los 2 notables
const SPREAD_SMALL_DEG = 32;       // ángulo ± entre los 2 smalls de un notable

const RADII = { keystone: 40, notable: 30, small: 22 };
// Distancia mínima entre centros para no solapar (radios + holgura de texto)
const MIN_GAP = {
  'keystone-keystone': 120,
  'keystone-notable': 100,
  'keystone-small': 95,
  'notable-notable': 90,
  'notable-small': 80,
  'small-small': 70,
};

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function minGap(t1, t2) {
  const k = [t1, t2].sort().join('-');
  return MIN_GAP[k] || 70;
}

function pol(cx, cy, r, deg) {
  const rad = (deg * Math.PI) / 180;
  return { x: Math.round(cx + r * Math.cos(rad)), y: Math.round(cy + r * Math.sin(rad)) };
}

// ── Estructura de ramas ──
// Cada rama: angulo base (grados), id, talentos con posiciones relativas
const BRANCHES = [
  {
    id: 'attack',
    angle: 90, // abajo
    root: {
      id: 'atk_root',
      name: 'ATAQUE',
      desc: 'Nodo maestro de combate. +4% Daño Total por nivel.',
      icon: '⚔️',
      maxLevel: 3,
      effects: { dmg_pct: 0.04 },
    },
    mediums: [
      {
        id: 'atk_m1',
        name: 'CANALIZADOR LÁSER',
        desc: '+3% Daño Láser por nivel. Potencia los haces de energía.',
        icon: '🔫',
        maxLevel: 5,
        effects: { laser_dmg_pct: 0.03 },
        smalls: [
          {
            id: 'atk_m1_s1',
            name: 'PERFORACIÓN TÉRMICA',
            desc: '+3% de ignorar escudo por nivel.',
            icon: '⚡',
            maxLevel: 5,
            effects: { ignore_shield_pct: 0.03 },
          },
          {
            id: 'atk_m1_s2',
            name: 'CADENCIA MILITAR',
            desc: '+2% Cadencia de fuego por nivel.',
            icon: '⚔️',
            maxLevel: 5,
            effects: { fire_rate_pct: 0.02 },
          },
        ],
      },
      {
        id: 'atk_m2',
        name: 'ARSENAL PESADO',
        desc: '+4% Munición extra por nivel. Más proyectiles en combate.',
        icon: '💣',
        maxLevel: 5,
        effects: { ammo_bonus_pct: 0.04 },
        smalls: [
          {
            id: 'atk_m2_s1',
            name: 'IMPULSO LÁSER',
            desc: '+5% Alcance de munición láser por nivel.',
            icon: '🎯',
            maxLevel: 5,
            effects: { 'ammo:laser:range': 0.05 },
          },
          {
            id: 'atk_m2_s2',
            name: 'MILOS MISIL',
            desc: '+5% Velocidad de proyectil de misil por nivel.',
            icon: '🚀',
            maxLevel: 5,
            effects: { 'ammo:missile:bulletSpeed': 0.05 },
          },
        ],
      },
    ],
  },
  {
    id: 'fender',
    angle: 180, // izquierda
    root: {
      id: 'def_root',
      name: 'DEFENSA',
      desc: 'Nodo maestro de supervivencia. +5% Vida y +5% Escudo por nivel.',
      icon: '🛡️',
      maxLevel: 3,
      effects: { hp_pct: 0.05, sh_pct: 0.05 },
    },
    mediums: [
      {
        id: 'def_m1',
        name: 'NÚCLEO DE CASCO',
        desc: '+3% Vida máxima por nivel. Refuerza la estructura interna.',
        icon: '💠',
        maxLevel: 5,
        effects: { hp_pct: 0.03 },
        smalls: [
          {
            id: 'def_m1_s1',
            name: 'REGEN DE COMBATE',
            desc: '+4% Regeneración de vida por nivel.',
            icon: '🔧',
            maxLevel: 5,
            effects: { hp_regen: 0.04 },
          },
          {
            id: 'def_m1_s2',
            name: 'PLACAS NANOBOT',
            desc: '+2% Armadura total por nivel.',
            icon: '⚙️',
            maxLevel: 5,
            effects: { armor_pct: 0.02 },
          },
        ],
      },
      {
        id: 'def_m2',
        name: 'BARRERA DE PLASMA',
        desc: '+4% Escudo máximo por nivel. Campo de contención mejorado.',
        icon: '🔵',
        maxLevel: 5,
        effects: { sh_pct: 0.04 },
        smalls: [
          {
            id: 'def_m2_s1',
            name: 'CAPACITOR DINÁMICO',
            desc: '+5% Regeneración de escudo por nivel.',
            icon: '🔋',
            maxLevel: 5,
            effects: { shield_regen: 0.05 },
          },
          {
            id: 'def_m2_s2',
            name: 'BARRERA REFORZADA',
            desc: '-5% Enfriamiento de Barrera de Viento por nivel.',
            icon: '🌪️',
            maxLevel: 5,
            effects: { 'skill:SK-DEF-05:cd': -0.05 },
          },
        ],
      },
    ],
  },
  {
    id: 'healing',
    angle: 270, // arriba
    root: {
      id: 'heal_root',
      name: 'CURACIÓN',
      desc: 'Nodo maestro de restauración. +6% Curación por nivel.',
      icon: '🔮',
      maxLevel: 3,
      effects: { heal_pct: 0.06 },
    },
    mediums: [
      {
        id: 'heal_m1',
        name: 'CANALIZADORES',
        desc: '+3% Curación por nivel. Optimiza los pulsos de reparación.',
        icon: '💚',
        maxLevel: 5,
        effects: { heal_pct: 0.03 },
        smalls: [
          {
            id: 'heal_m1_s1',
            name: 'DRONES MÉDICOS',
            desc: '+5% Poder de Auto-Reparación por nivel.',
            icon: '🤖',
            maxLevel: 5,
            effects: { 'skill:SK-HEAL-01:amount': 0.05 },
          },
          {
            id: 'heal_m1_s2',
            name: 'BALIZA MEJORADA',
            desc: '+5% Sanación de Baliza de Curación por nivel.',
            icon: '🏮',
            maxLevel: 5,
            effects: { 'skill:SK-HEAL-02:heal_amount': 0.05 },
          },
        ],
      },
      {
        id: 'heal_m2',
        name: 'REGENERACIÓN ALFA',
        desc: '+3% Regeneración de vida por nivel. Metabolismo de combate.',
        icon: '🌿',
        maxLevel: 5,
        effects: { hp_regen: 0.03 },
        smalls: [
          {
            id: 'heal_m2_s1',
            name: 'NANO-REGENERACIÓN',
            desc: '-5% Enfriamiento de NANO-REGENERACIÓN por nivel.',
            icon: '🦠',
            maxLevel: 5,
            effects: { 'skill:SK-HEAL-02:cd': -0.05 },
          },
          {
            id: 'heal_m2_s2',
            name: 'VÍNCULO VITAL',
            desc: '+5% Poder de Vínculo Vital por nivel.',
            icon: '❤️‍🔥',
            maxLevel: 5,
            effects: { 'skill:SK-HEAL-04:amount': 0.05 },
          },
        ],
      },
    ],
  },
  {
    id: 'utility',
    angle: 0, // derecha
    root: {
      id: 'uti_root',
      name: 'UTILIDAD',
      desc: 'Nodo maestro de eficiencia. -4% Enfriamiento global por nivel.',
      icon: '🔬',
      maxLevel: 3,
      effects: { cooldown_reduction: 0.04 },
    },
    mediums: [
      {
        id: 'uti_m1',
        name: 'PROPULSIÓN AVANZADA',
        desc: '+2% Velocidad base por nivel. Motores de fusión calibrados.',
        icon: '🚀',
        maxLevel: 5,
        effects: { speed_pct: 0.02 },
        smalls: [
          {
            id: 'uti_m1_s1',
            name: 'SALTO HIPERESPACIAL',
            desc: '+10% Distancia de Dash por nivel.',
            icon: '🌀',
            maxLevel: 5,
            effects: { dash_distance: 0.1 },
          },
          {
            id: 'uti_m1_s2',
            name: 'TURBO-IMPULSO',
            desc: '-5% Enfriamiento de Turbo-Impulso por nivel.',
            icon: '💨',
            maxLevel: 5,
            effects: { 'skill:SK-UTIL-01:cd': -0.05 },
          },
        ],
      },
      {
        id: 'uti_m2',
        name: 'SISTEMAS TÁCTICOS',
        desc: '+8% Rango de radar por nivel. Sensores de largo alcance.',
        icon: '📡',
        maxLevel: 5,
        effects: { minimap_range: 0.08 },
        smalls: [
          {
            id: 'uti_m2_s1',
            name: 'ESCÁNER ORBITAL',
            desc: '+3% Eficiencia de energía por nivel.',
            icon: '⚛️',
            maxLevel: 5,
            effects: { energy_efficiency: 0.03 },
          },
          {
            id: 'uti_m2_s2',
            name: 'MERCADO GALÁCTICO',
            desc: '-2% Descuento en tiendas por nivel (mejores precios).',
            icon: '🏪',
            maxLevel: 5,
            effects: { shop_discount: 0.02 },
          },
        ],
      },
    ],
  },
];

// ── Construir talentos, nodos, conexiones con posiciones ──
const talents = [];
const nodes = {};
const connections = [];

for (const br of BRANCHES) {
  const base = br.angle;
  const category = br.id;

  // Keystone en el eje de la rama
  const kPos = pol(0, 0, D_KESTONE_FROM_CENTER, base);
  talents.push({ ...br.root, category });
  nodes[br.root.id] = { nodeType: 'keystone', x: kPos.x, y: kPos.y };

  br.mediums.forEach((med, mi) => {
    // Ángulo del notable: base ± spread (primer notable a la izquierda del eje)
    const sign = mi === 0 ? -1 : 1;
    const medAngle = base + sign * SPREAD_MED_DEG;
    const mPos = pol(kPos.x, kPos.y, D_MED_FROM_KESTONE, medAngle);

    talents.push({ ...med, effects: med.effects, category });
    // limpiar smalls del objeto notable para no meterlos en talents
    const medTalent = talents[talents.length - 1];
    delete medTalent.smalls;
    nodes[med.id] = { nodeType: 'notable', x: mPos.x, y: mPos.y };
    connections.push({ from: br.root.id, to: med.id });

    // Eje del notable para colgar smalls: desde keystone pasando por notable
    const medDirAngle = medAngle; // dirección radial aproximada

    med.smalls.forEach((sm, si) => {
      const sSign = si === 0 ? -1 : 1;
      const smallAngle = medDirAngle + sSign * SPREAD_SMALL_DEG;
      const sPos = pol(mPos.x, mPos.y, D_SMALL_FROM_MED, smallAngle);

      talents.push({ ...sm, category });
      nodes[sm.id] = { nodeType: 'small', x: sPos.x, y: sPos.y };
      connections.push({ from: med.id, to: sm.id });
    });
  });
}

// ── Validación de distancias ──
const ids = Object.keys(nodes);
const problems = [];
for (let i = 0; i < ids.length; i++) {
  for (let j = i + 1; j < ids.length; j++) {
    const a = ids[i], b = ids[j];
    const ta = nodes[a].nodeType, tb = nodes[b].nodeType;
    const d = dist(nodes[a], nodes[b]);
    // Solo exigir gap mínimo entre nodos que NO están en padre-hijo directo
    const isEdge = connections.some(
      (c) => (c.from === a && c.to === b) || (c.from === b && c.to === a)
    );
    if (isEdge) continue;
    const need = minGap(ta, tb);
    if (d < need) {
      problems.push(`${a}(${ta}) ↔ ${b}(${tb}): ${d}px < ${need}px`);
    }
  }
}

// Distancia mínima en ejes de conexión (no solapar radios en la línea)
for (const c of connections) {
  const a = nodes[c.from], b = nodes[c.to];
  const d = dist(a, b);
  const minLine = RADII[a.nodeType] + RADII[b.nodeType] + 40;
  if (d < minLine) {
    problems.push(`edge ${c.from}→${c.to}: ${d}px < radios+40=${minLine}px`);
  }
}

// Bounds
let minX = 0, maxX = 0, minY = 0, maxY = 0;
for (const id of ids) {
  minX = Math.min(minX, nodes[id].x);
  maxX = Math.max(maxX, nodes[id].x);
  minY = Math.min(minY, nodes[id].y);
  maxY = Math.max(maxY, nodes[id].y);
}

console.log('=== VALIDACIÓN ===');
console.log(`Nodos: ${ids.length} (esperado 28)`);
console.log(`Talentos: ${talents.length}`);
console.log(`Conexiones: ${connections.length} (esperado 24, intra-rama)`);
console.log(`Bounds: X[${minX}..${maxX}] Y[${minY}..${maxY}]`);

// Verificar que ninguna conexión cruza ramas
const catOf = {};
talents.forEach((t) => (catOf[t.id] = t.category));
const cross = connections.filter((c) => catOf[c.from] !== catOf[c.to]);
if (cross.length) problems.push(`CONEXIONES CRUZADAS: ${JSON.stringify(cross)}`);

// Conteo por categoría
for (const br of BRANCHES) {
  const n = talents.filter((t) => t.category === br.id).length;
  console.log(`  ${br.id}: ${n} talentos`);
}

if (problems.length) {
  console.error('\nPROBLEMAS:');
  problems.forEach((p) => console.error(' -', p));
  process.exit(1);
}
console.log('\n✔ Validación OK — sin solapamientos ni cruces.');

// ── Inyectar en config.json ──
const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
const config = JSON.parse(raw);

// Detectar indent
const indentMatch = raw.match(/\n([\t ]+)"/);
const indent = indentMatch ? indentMatch[1].length : 4;

const prevTalents = (config.talentsConfig && config.talentsConfig.talents) || [];
console.log(`\nTalentos previos: ${prevTalents.length} → nuevos: ${talents.length}`);

config.talentsConfig = config.talentsConfig || {};
config.talentsConfig.talents = talents;
config.talentsConfig.nodes = nodes;
config.talentsConfig.connections = connections;
// categories se conserva tal cual (fender/attack/utility/healing)
if (!Array.isArray(config.talentsConfig.categories) || config.talentsConfig.categories.length === 0) {
  config.talentsConfig.categories = BRANCHES.map((b) => {
    const meta = {
      attack: { name: 'Ataque', color: '#ff3131', emoji: '⚔️' },
      fender: { name: 'Defensa', color: '#0011ff', emoji: '🛠️' },
      healing: { name: 'Curacion', color: '#29bd00', emoji: '🔮' },
      utility: { name: 'Utilidad', color: '#ffea00', emoji: '🔬' },
    }[b.id];
    return { id: b.id, ...meta };
  });
}
// Sellados: limpiar índices fuera de rango (cada rama ahora tiene 7)
config.talentsLockedConfig = (config.talentsLockedConfig || []).filter((l) => {
  const count = talents.filter((t) => t.category === l.category).length;
  return Number(l.index) >= 0 && Number(l.index) < count;
});

fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, indent) + '\n', 'utf8');
console.log(`\n✔ config.json actualizado (indent=${indent}).`);
console.log('\nMapa de posiciones:');
for (const br of BRANCHES) {
  console.log(`\n[${br.id}]`);
  talents.filter((t) => t.category === br.id).forEach((t) => {
    const n = nodes[t.id];
    console.log(`  ${n.nodeType.padEnd(9)} ${t.id.padEnd(12)} (${n.x},${n.y})  ${t.name}`);
  });
}
