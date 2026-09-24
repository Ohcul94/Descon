/**
 * Genera el mapa de talentos (profundidad 4):
 * Raíz (keystone)
 *  ├─ m1 Stats de nave (notable) → 2 smalls de stats
 *  └─ m2 Habilidades (notable) → 1 nodo por skill (notable) → 2 smalls por skill
 * Sin conexiones entre ramas. Sin munición ni armadura.
 */
const fs = require('fs');
const path = require('path');

const CONFIG_PATH = path.join(__dirname, '..', 'Server', 'config.json');

const D_KESTONE = 190;
const D_MED = 165;
const D_STAT_SMALL = 125;
const D_SKILL_SMALL = 125;
const SPREAD_MED_DEG = 42;
const SPREAD_STAT_DEG = 26;
const SPREAD_SKILL_SMALL_DEG = 16;
const SPREAD_GEAR_SMALL_DEG = 19;
const D_GEAR_SMALL = 110;
const GAP_BUFFER = 1.08;

const RADII = { keystone: 40, notable: 30, small: 22 };
const MIN_GAP = {
  'keystone-keystone': 130,
  'keystone-notable': 105,
  'keystone-small': 95,
  'notable-notable': 92,
  'notable-small': 78,
  'small-small': 68,
};

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function minGap(t1, t2) {
  const k = [t1, t2].sort().join('-');
  return MIN_GAP[k] || 68;
}

function pol(cx, cy, r, deg) {
  const rad = (deg * Math.PI) / 180;
  return {
    x: Math.round(cx + r * Math.cos(rad)),
    y: Math.round(cy + r * Math.sin(rad)),
  };
}

function angLerpSpread(base, i, n, totalDeg) {
  if (n <= 1) return base;
  const t = i / (n - 1) - 0.5;
  return base + t * totalDeg;
}

// ── Skills por tipo (skillsData.type en config.json) ──
// icon = asset real (misma ruta que SkillsHUD.gd _skill_icon_paths)
const SKILLS_BY_TYPE = {
  Ataque: [
    { key: 'REFLECT-OMEGA', id: 'SK-ATK-01', icon: 'res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png', powerAttr: 'amount', powerLabel: 'Potencia de Reflejo' },
    { key: 'ESFERA DE TERROR', id: 'SK-ATK-02', icon: 'res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png', powerAttr: 'amount', powerLabel: 'Potencia' },
    { key: 'PROVOCACION', id: 'SK-DEF-06', icon: 'res://assets/Skills/Iconos/Ataque/Provocacion/Provocacion.png', powerAttr: 'taunt_duration', powerLabel: 'Duración Provocación' },
  ],
  Defensa: [
    { key: 'BARRERA DE VIENTO', id: 'SK-DEF-05', icon: 'res://assets/Skills/Iconos/Defensa/Barrera de Viento/Barrera de Viento.png', powerAttr: 'duration', powerLabel: 'Duración' },
    { key: 'ESCUDO CELULAR', id: 'SK-DEF-01', icon: 'res://assets/Skills/Iconos/Defensa/Escudo Celular/Escudo Celular.png', powerAttr: 'amount', powerLabel: 'Potencia' },
    { key: 'FROST-TRAIL', id: 'SK-DEF-04', icon: 'res://assets/Skills/Iconos/Defensa/Camino de Hielo/Camino de Hielo.png', powerAttr: 'duration', powerLabel: 'Duración' },
    { key: 'SMOKE-BOMB', id: 'SK-DEF-03', icon: 'res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png', powerAttr: 'duration', powerLabel: 'Duración' },
  ],
  Curación: [
    { key: 'AUTO-REPARACIÓN', id: 'SK-HEAL-01', icon: 'res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png', powerAttr: 'amount', powerLabel: 'Potencia' },
    { key: 'BALIZA DE CURACION', id: 'SK-HEAL-05', icon: 'res://assets/Skills/Iconos/Cura/Baliza Curativa/Baliza Curativa.png', powerAttr: 'heal_amount', powerLabel: 'Sanación' },
    { key: 'NANO-REGENERACIÓN', id: 'SK-HEAL-02', icon: 'res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png', powerAttr: 'amount', powerLabel: 'Potencia' },
    { key: 'REGENERACIÓN ALFA', id: 'SK-HEAL-03', icon: 'res://assets/Skills/Iconos/Cura/Regeneracion Alfa/Regeneracion Alfa.png', powerAttr: 'amount', powerLabel: 'Potencia' },
    { key: 'VÍNCULO VITAL', id: 'SK-HEAL-04', icon: 'res://assets/Skills/Iconos/Cura/Vinculo Vital/Vinculo Vital.png', powerAttr: 'amount', powerLabel: 'Potencia' },
  ],
  Utilidad: [
    { key: 'TURBO-IMPULSO', id: 'SK-UTIL-01', icon: 'res://assets/Skills/Iconos/Utilidad/Turbo Impulso/Turbo Impulso.png', powerAttr: null, powerLabel: null },
    { key: 'HYPER-DASH', id: 'SK-UTIL-02', icon: 'res://assets/Skills/Iconos/Utilidad/HyperDash/HyperDash.png', powerAttr: 'range', powerLabel: 'Rango' },
    { key: 'INVULNERABILIDAD', id: 'SK-UTIL-03', icon: 'res://assets/Skills/Iconos/Utilidad/Invulnerabilidad/Invulnerabilidad.png', powerAttr: 'duration', powerLabel: 'Duración' },
    { key: 'BLINK', id: 'SK-UTIL-04', icon: 'res://assets/Skills/Iconos/Utilidad/Destello/Destello.png', powerAttr: 'range', powerLabel: 'Rango' },
    { key: 'STEALTH', id: 'SK-UTIL-05', icon: 'res://assets/Skills/Iconos/Utilidad/Invisibilidad/Invisibilidad.png', powerAttr: 'duration', powerLabel: 'Duración' },
    { key: 'RESURRECCIÓN', id: 'SK-UTIL-06', icon: 'res://assets/Skills/Iconos/Utilidad/Resurrecion/Resurrecion.png', powerAttr: 'radius', powerLabel: 'Radio' },
  ],
};

// ── Armas y municiones (desde shopItems en config.json) ──
function loadShopGear() {
  const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  const shop = config.shopItems || {};
  const weapons = (shop.weapons || [])
    .filter((w) => w && w.id && !w.hidden)
    .map((w) => ({
      id: w.id,
      name: w.name || w.id,
      icon: w.icon || '',
      dmgPct: 0.01,
    }));
  const ammoNames = {
    laser: 'Láser',
    missile: 'Misil',
    mine: 'Mina',
    emp: 'EMP',
    electron: 'Electrón',
    heal: 'Drones',
    melee: 'Plasma',
    siphon: 'Sifón',
  };
  const ammoIcons = {
    laser: 'res://assets/Municiones/Iconos/laser/Laser.png',
    missile: 'res://assets/Municiones/Iconos/missile/Missile.png',
    mine: 'res://assets/Municiones/Iconos/mine/Mine.png',
    emp: 'res://assets/Municiones/Iconos/emp/Emp.png',
    electron: 'res://assets/Municiones/Iconos/electron/Electron.png',
    heal: 'res://assets/Municiones/Iconos/heal/Heal.png',
    melee: 'res://assets/Municiones/Iconos/melee/Melee.png',
    siphon: 'res://assets/Municiones/Iconos/siphon/Siphon.png',
  };
  const ammo = Object.keys(shop.ammo || {}).map((type) => ({
    type,
    name: ammoNames[type] || type,
    icon: ammoIcons[type] || '',
    castPct: -0.05,
    cdPct: -0.05,
  }));
  return { weapons, ammo };
}

const SHOP_GEAR = loadShopGear();

const BRANCHES = [
  {
    id: 'attack',
    angle: 90,
    typeKey: 'Ataque',
    root: {
      id: 'atk_root',
      name: 'ATAQUE',
      desc: 'Nodo maestro de combate. +4% Daño Total por nivel.',
      icon: '⚔️',
      effects: { dmg_pct: 0.04 },
    },
    stats: {
      id: 'atk_stats',
      name: 'DAÑO',
      desc: 'Mejora el daño de cada arma y las municiones por separado.',
      icon: '💥',
      effects: {},
      // Rellenado dinámicamente: armas (daño) + municiones (casteo/CD)
      smalls: [],
      gear: true,
    },
    skillsTitle: { name: 'RUTAS DE HABILIDAD', desc: 'Mejoras de habilidades de Ataque.', icon: '🌀' },
  },
  {
    id: 'fender',
    angle: 180,
    typeKey: 'Defensa',
    root: {
      id: 'def_root',
      name: 'DEFENSA',
      desc: 'Nodo maestro de supervivencia. +5% Vida y +5% Escudo por nivel.',
      icon: '🛡️',
      maxLevel: 3,
      effects: { hp_pct: 0.05, sh_pct: 0.05 },
    },
    stats: {
      id: 'def_stats',
      name: 'CASCO REFORZADO',
      desc: 'Stats de nave de resistencia. +3% Vida y +3% Escudo por nivel.',
      icon: '💠',
      maxLevel: 5,
      effects: { hp_pct: 0.03, sh_pct: 0.03 },
      smalls: [
        {
          id: 'def_stats_s1',
          name: 'REGEN DE COMBATE',
          desc: '+4% Regeneración de vida por nivel.',
          icon: '🔧',
          maxLevel: 5,
          effects: { hp_regen: 0.04 },
        },
        {
          id: 'def_stats_s2',
          name: 'CAPACITOR DINÁMICO',
          desc: '+5% Regeneración de escudo por nivel.',
          icon: '🔋',
          maxLevel: 5,
          effects: { shield_regen: 0.05 },
        },
      ],
    },
    skillsTitle: { name: 'PROTOCOLOS DEFENSIVOS', desc: 'Mejoras de habilidades de Defensa.', icon: '🌀' },
  },
  {
    id: 'healing',
    angle: 270,
    typeKey: 'Curación',
    root: {
      id: 'heal_root',
      name: 'CURACIÓN',
      desc: 'Nodo maestro de restauración. +6% Curación por nivel.',
      icon: '🔮',
      maxLevel: 3,
      effects: { heal_pct: 0.06 },
    },
    stats: {
      id: 'heal_stats',
      name: 'PULSO VITAL',
      desc: 'Stats de nave curativos. +3% Curación por nivel.',
      icon: '💚',
      maxLevel: 5,
      effects: { heal_pct: 0.03 },
      smalls: [
        {
          id: 'heal_stats_s1',
          name: 'METABOLISMO COMBATIVO',
          desc: '+3% Regeneración de vida por nivel.',
          icon: '🌿',
          maxLevel: 5,
          effects: { hp_regen: 0.03 },
        },
        {
          id: 'heal_stats_s2',
          name: 'NÚCLEO VITAL',
          desc: '+2% Vida máxima por nivel.',
          icon: '❤️',
          maxLevel: 5,
          effects: { hp_pct: 0.02 },
        },
      ],
    },
    skillsTitle: { name: 'PROTOCOLOS MÉDICOS', desc: 'Mejoras de habilidades de Curación.', icon: '🌀' },
  },
  {
    id: 'utility',
    angle: 0,
    typeKey: 'Utilidad',
    root: {
      id: 'uti_root',
      name: 'UTILIDAD',
      desc: 'Nodo maestro de eficiencia. -4% Enfriamiento global por nivel.',
      icon: '🔬',
      maxLevel: 3,
      effects: { cooldown_reduction: 0.04 },
    },
    stats: {
      id: 'uti_stats',
      name: 'EFICIENCIA GLOBAL',
      desc: 'Stats de nave de utilidad. -3% Enfriamiento global por nivel.',
      icon: '❄️',
      maxLevel: 5,
      effects: { cooldown_reduction: 0.03 },
      smalls: [
        {
          id: 'uti_stats_s1',
          name: 'REDUCCIÓN DE CASTEO',
          desc: '-3% Tiempo de casteo global por nivel.',
          icon: '⏱️',
          maxLevel: 5,
          effects: { cast_time_reduction: 0.03 },
        },
        {
          id: 'uti_stats_s2',
          name: 'CADENCIA OPTIMIZADA',
          desc: '+2% Cadencia de fuego por nivel.',
          icon: '🎯',
          maxLevel: 5,
          effects: { fire_rate_pct: 0.02 },
        },
      ],
    },
    skillsTitle: { name: 'PROTOCOLOS TÁCTICOS', desc: 'Mejoras de habilidades de Utilidad.', icon: '🌀' },
  },
];

// ── Construcción ──
const talents = [];
const nodes = {};
const connections = [];

const MAX_LEVEL_BY_TYPE = { keystone: 4, notable: 3, small: 2 };

function addTalent(data, category, nodeType, pos) {
  talents.push({ ...data, maxLevel: MAX_LEVEL_BY_TYPE[nodeType] || data.maxLevel || 5, category });
  nodes[data.id] = { nodeType, x: pos.x, y: pos.y };
}

function chordDeg(gap, radius) {
  const g = gap * GAP_BUFFER;
  return 2 * Math.asin(Math.min(1, g / (2 * radius))) * (180 / Math.PI);
}

function requiredSkillRadius(n, notableGap) {
  // d = gap / (2*sin(step/2)); elige step razonable y asegura chord >= gap
  const step = 20;
  const need = (notableGap * GAP_BUFFER) / (2 * Math.sin((step * Math.PI) / 360));
  const byCount = Math.max(n, 2);
  return Math.max(210, need, byCount * 14);
}

for (const br of BRANCHES) {
  const base = br.angle;
  const category = br.id;
  const skills = SKILLS_BY_TYPE[br.typeKey] || [];

  const kPos = pol(0, 0, D_KESTONE, base);
  addTalent(br.root, category, 'keystone', kPos);

  // Stats a la izquierda del eje; hub de skills en el eje de la rama
  const statsAngle = base - SPREAD_MED_DEG;
  const skillsAngle = base;
  const statsPos = pol(kPos.x, kPos.y, D_MED, statsAngle);
  const skillsPos = pol(kPos.x, kPos.y, D_MED, skillsAngle);

  addTalent(br.stats, category, 'notable', statsPos);
  connections.push({ from: br.root.id, to: br.stats.id });

  if (br.stats.gear) {
    // DAÑO: 1 nodo ARMAS (si el shop tiene armas) + 1 hub por munición con 2 smalls.
    // Sin "LÁSER 1/2" separados: solo existe MUNICIÓN LÁSER (1 tipo de munición).
    const gearMid = [];
    const weapons = SHOP_GEAR.weapons || [];
    if (weapons.length) {
      const wFx = {};
      for (const w of weapons) wFx[`weapon:${w.id}:base`] = w.dmgPct;
      gearMid.push({
        nodeType: 'notable',
        data: {
          id: 'atk_weapons',
          name: 'ARMAS',
          desc: weapons.length === 1
            ? `+1% Daño de ${weapons[0].name} por nivel.`
            : '+1% Daño de cada arma por nivel.',
          icon: weapons[0] && weapons[0].icon ? weapons[0].icon : '🔫',
          effects: wFx,
        },
        smalls: [],
      });
    }
    for (const am of SHOP_GEAR.ammo) {
      gearMid.push({
        nodeType: 'notable',
        data: {
          id: `atk_am_${am.type}`,
          name: `MUNICIÓN ${am.name.toUpperCase()}`,
          desc: `Mejoras de ${am.name}: casteo y enfriamiento.`,
          icon: am.icon,
          effects: {},
        },
        // Dos smalls hermanos colgados del hub de munición (±ángulo), como skills/stats
        smalls: [
          {
            id: `atk_am_${am.type}_cast`,
            name: 'CASTEO',
            desc: `-5% Velocidad de casteo de ${am.name} por nivel.`,
            icon: '⏳',
            effects: { [`ammo:${am.type}:castTimeMs`]: am.castPct },
          },
          {
            id: `atk_am_${am.type}_cd`,
            name: 'ENFRIAMIENTO',
            desc: `-5% CD de ${am.name} por nivel.`,
            icon: '⏱️',
            effects: { [`ammo:${am.type}:cooldown`]: am.cdPct },
          },
        ],
      });
    }

    const midN = gearMid.length;
    // Abanico abajo-derecha de DAÑO (lejos de skills ~90° y Utilidad ~0°).
    // edgeGap cubre el ancho de los 2 smalls hermanos (CASTEO/CD) entre hubs vecinos;
    // dMid grande → paso angular chico → el abanico no invade skills ni utilidad.
    const fanCenter = statsAngle + 2;
    const dMid = 1200;
    const gearSmallSpan = 2 * D_GEAR_SMALL * Math.sin((SPREAD_GEAR_SMALL_DEG * Math.PI) / 180);
    const edgeGap = Math.max(
      MIN_GAP['notable-notable'],
      RADII.notable * 2 + 40,
      MIN_GAP['small-small'] + gearSmallSpan
    );
    const stepGear = Math.max(chordDeg(edgeGap, dMid), 7);
    const fanTotal = stepGear * Math.max(midN - 1, 1);

    gearMid.forEach((mid, i) => {
      const a = angLerpSpread(fanCenter, i, midN, fanTotal);
      const p = pol(statsPos.x, statsPos.y, dMid, a);
      addTalent(mid.data, category, mid.nodeType, p);
      connections.push({ from: br.stats.id, to: mid.data.id });

      if (mid.smalls) {
        // Smalls hermanos al mismo radio del padre, abiertos en ±ángulo
        // (CASTEO y ENFRIAMIENTO cuelgan de MUNICIÓN, no en cadena)
        mid.smalls.forEach((sm, j) => {
          const sa = a + (j === 0 ? -SPREAD_GEAR_SMALL_DEG : SPREAD_GEAR_SMALL_DEG);
          const sp = pol(p.x, p.y, D_GEAR_SMALL, sa);
          addTalent(sm, category, 'small', sp);
          connections.push({ from: mid.data.id, to: sm.id });
        });
      }
    });
  } else {
    br.stats.smalls.forEach((sm, i) => {
      const a = angLerpSpread(statsAngle, i, br.stats.smalls.length, SPREAD_STAT_DEG * 2);
      const p = pol(statsPos.x, statsPos.y, D_STAT_SMALL, a);
      addTalent(sm, category, 'small', p);
      connections.push({ from: br.stats.id, to: sm.id });
    });
  }

  addTalent(
    { id: `${br.id}_skills`, ...br.skillsTitle, maxLevel: 1, effects: {} },
    category,
    'notable',
    skillsPos
  );
  connections.push({ from: br.root.id, to: `${br.id}_skills` });

  const hubId = `${br.id}_skills`;
  const n = skills.length;
  const dSkill = requiredSkillRadius(n, MIN_GAP['notable-notable']);
  const stepSkill = Math.max(
    chordDeg(MIN_GAP['notable-notable'], dSkill),
    chordDeg(MIN_GAP['small-small'], dSkill + D_SKILL_SMALL * Math.cos((SPREAD_SKILL_SMALL_DEG * Math.PI) / 180))
  );
  const fanTotal = stepSkill * Math.max(n - 1, 1);

  skills.forEach((sk, i) => {
    const skillAngle = angLerpSpread(skillsAngle, i, n, fanTotal);
    const skillId = `${br.id}_sk${i + 1}`;
    const skillPos = pol(skillsPos.x, skillsPos.y, dSkill, skillAngle);

    const cdKey = `skill:${sk.id}:cd`;
    const powerKey = sk.powerAttr ? `skill:${sk.id}:${sk.powerAttr}` : null;

    addTalent(
      {
        id: skillId,
        name: sk.key,
        desc: `Maestría de ${sk.key}. -3% Enfriamiento por nivel.`,
        icon: sk.icon,
        maxLevel: 3,
        effects: { [cdKey]: -0.03 },
      },
      category,
      'notable',
      skillPos
    );
    connections.push({ from: hubId, to: skillId });

    const smallDefs = [
      {
        id: `${skillId}_s1`,
        name: 'AFINADO',
        desc: `-4% Enfriamiento de ${sk.key} por nivel.`,
        icon: '⏱️',
        maxLevel: 5,
        effects: { [cdKey]: -0.04 },
      },
      powerKey
        ? {
            id: `${skillId}_s2`,
            name: 'POTENCIADOR',
            desc: `+5% ${sk.powerLabel} de ${sk.key} por nivel.`,
            icon: '⚡',
            maxLevel: 5,
            effects: { [powerKey]: 0.05 },
          }
        : {
            id: `${skillId}_s2`,
            name: 'SOBRECARGA',
            desc: `-5% Enfriamiento de ${sk.key} por nivel.`,
            icon: '🔥',
            maxLevel: 5,
            effects: { [cdKey]: -0.05 },
          },
    ];

    smallDefs.forEach((sm, j) => {
      // Smalls más afuera y casi radiales al skill (menos solape entre skills vecinos)
      const a = skillAngle + (j === 0 ? -SPREAD_SKILL_SMALL_DEG : SPREAD_SKILL_SMALL_DEG);
      const p = pol(skillPos.x, skillPos.y, D_SKILL_SMALL, a);
      addTalent(sm, category, 'small', p);
      connections.push({ from: skillId, to: sm.id });
    });
  });
}

// ── Validación ──
const ids = Object.keys(nodes);
const problems = [];

for (let i = 0; i < ids.length; i++) {
  for (let j = i + 1; j < ids.length; j++) {
    const a = ids[i], b = ids[j];
    const ta = nodes[a].nodeType, tb = nodes[b].nodeType;
    const d = dist(nodes[a], nodes[b]);
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

for (const c of connections) {
  const a = nodes[c.from], b = nodes[c.to];
  if (!a || !b) {
    problems.push(`edge roto ${c.from}→${c.to}`);
    continue;
  }
  const d = dist(a, b);
  const minLine = RADII[a.nodeType] + RADII[b.nodeType] + 40;
  if (d < minLine) {
    problems.push(`edge ${c.from}→${c.to}: ${d}px < ${minLine}px`);
  }
}

let minX = 0, maxX = 0, minY = 0, maxY = 0;
for (const id of ids) {
  minX = Math.min(minX, nodes[id].x);
  maxX = Math.max(maxX, nodes[id].x);
  minY = Math.min(minY, nodes[id].y);
  maxY = Math.max(maxY, nodes[id].y);
}

const catOf = {};
talents.forEach((t) => (catOf[t.id] = t.category));
const cross = connections.filter((c) => catOf[c.from] !== catOf[c.to]);
if (cross.length) problems.push(`CONEXIONES CRUZADAS: ${JSON.stringify(cross)}`);

// Segmentos de conexión: no deben cruzarse entre sí (ni tocar nodos ajenos al edge)
function orient(ax, ay, bx, by, cx, cy) {
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}
function segmentsCross(a1, a2, b1, b2) {
  const o1 = orient(a1.x, a1.y, a2.x, a2.y, b1.x, b1.y);
  const o2 = orient(a1.x, a1.y, a2.x, a2.y, b2.x, b2.y);
  const o3 = orient(b1.x, b1.y, b2.x, b2.y, a1.x, a1.y);
  const o4 = orient(b1.x, b1.y, b2.x, b2.y, a2.x, a2.y);
  const eps = 1e-6;
  if (Math.abs(o1) < eps || Math.abs(o2) < eps || Math.abs(o3) < eps || Math.abs(o4) < eps) return false;
  return o1 * o2 < 0 && o3 * o4 < 0;
}
function edgeKey(c) {
  return c.from + '→' + c.to;
}
const edgeCrosses = [];
for (let i = 0; i < connections.length; i++) {
  for (let j = i + 1; j < connections.length; j++) {
    const a = connections[i];
    const b = connections[j];
    const na = nodes[a.from], nb = nodes[a.to];
    const nc = nodes[b.from], nd = nodes[b.to];
    if (!na || !nb || !nc || !nd) continue;
    // Comparten nodo → no cuenta como cruce
    if (a.from === b.from || a.from === b.to || a.to === b.from || a.to === b.to) continue;
    if (segmentsCross(na, nb, nc, nd)) {
      edgeCrosses.push(`${edgeKey(a)} ✕ ${edgeKey(b)}`);
    }
  }
}
if (edgeCrosses.length) {
  problems.push(`CRUCES DE LÍNEAS (${edgeCrosses.length}): ${edgeCrosses.slice(0, 12).join(' | ')}`);
}

// Sin armadura / stats globales baneadas. ammo:TYPE:castTimeMs|cooldown permitidos.
const banned = talents.filter((t) => {
  const keys = Object.keys(t.effects || {});
  const name = (t.name + t.desc).toLowerCase();
  return (
    keys.some(
      (k) =>
        k === 'ammo_bonus_pct' ||
        k === 'armor_pct' ||
        (k.startsWith('ammo:') && !k.endsWith(':castTimeMs') && !k.endsWith(':cooldown'))
    ) ||
    name.includes('armadura') ||
    name.includes('nanobot')
  );
});
if (banned.length) problems.push(`BANEADOS: ${banned.map((t) => t.id).join(', ')}`);

// Stats y skills hubs presentes
for (const br of BRANCHES) {
  if (!talents.find((t) => t.id === br.stats.id)) problems.push(`falta stats ${br.stats.id}`);
  if (!talents.find((t) => t.id === `${br.id}_skills`)) problems.push(`falta hub skills ${br.id}_skills`);
}

const skillTalentCount = talents.filter((t) => /_sk\d+_s[12]$/.test(t.id) || /_sk\d+$/.test(t.id)).length;

console.log('=== VALIDACIÓN ===');
console.log(`Nodos: ${ids.length}`);
console.log(`Talentos: ${talents.length}`);
console.log(`Conexiones: ${connections.length}`);
console.log(`Bounds: X[${minX}..${maxX}] Y[${minY}..${maxY}]`);
console.log(`Nodos de skills (incl. smalls): ${skillTalentCount}`);
for (const br of BRANCHES) {
  const n = talents.filter((t) => t.category === br.id).length;
  const sk = talents.filter((t) => t.category === br.id && (/_sk\d+/.test(t.id))).length;
  console.log(`  ${br.id}: ${n} talentos (${sk} de skills)`);
}

if (problems.length) {
  console.error('\nPROBLEMAS:');
  problems.forEach((p) => console.error(' -', p));
  process.exit(1);
}
console.log('\n✔ Validación OK — sin solapamientos, cruces ni stats baneadas.');

// ── Inyectar en config.json ──
const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
const config = JSON.parse(raw);
const indentMatch = raw.match(/\n([\t ]+)"/);
const indent = indentMatch ? indentMatch[1].length : 4;

const prevTalents = (config.talentsConfig && config.talentsConfig.talents) || [];
console.log(`\nTalentos previos: ${prevTalents.length} → nuevos: ${talents.length}`);

config.talentsConfig = config.talentsConfig || {};
config.talentsConfig.talents = talents;
config.talentsConfig.nodes = nodes;
config.talentsConfig.connections = connections;

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
    console.log(`  ${n.nodeType.padEnd(9)} ${t.id.padEnd(16)} (${String(n.x).padStart(5)},${String(n.y).padStart(5)})  ${t.name}`);
  });
}
