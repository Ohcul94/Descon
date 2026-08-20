// v266.220: Definición de Mecánicas de Ataque
const DEFAULT_MECHANICS_LIB = {
    "laser": { label: "Láser Estándar", icon: "🔫", desc: "Ataque lineal básico.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "burstShots", "startDelay"] },
    "missile": { label: "Misil Rastreador", icon: "🚀", desc: "Proyectil autoguiado.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "startDelay"] },
    "ice_missile": { label: "Misil de Hielo", icon: "❄️", desc: "Ralentiza al objetivo.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "slowAmount", "slowDuration", "startDelay"] },
    "mine": { label: "Mina de Proximidad", icon: "💣", desc: "Explosivo estático.", fields: ["bulletDamage", "fireRange", "fireRate", "startDelay"] },
    "orbital_strike": { label: "Ataque Orbital", icon: "🌀", desc: "Círculos que giran y luego se disparan.", fields: ["bulletDamage", "bulletSpeed", "orbitSpeed", "circleCount", "orbitRadius", "orbitDuration", "staticTime", "fireRate", "fireRange", "startDelay"] },
    "aura_damage": { label: "Aura de Vacío (Daño)", icon: "🔥", desc: "Daña a los jugadores cercanos continuamente.", fields: ["activationHP", "radius", "damage", "intervalMs", "duration", "cooldown", "startDelay"] },
    "hook": { label: "Gancho Abisal", icon: "⚓", desc: "Atrae al objetivo, lo daña y lo paraliza.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "stunDuration", "pullSpeed", "postHookWaitMs", "hookMissWaitMs", "isHoming", "turnSpeed", "startDelay"] },
    "cone_cast": { label: "Ataque en Cono Casteable", icon: "📐", desc: "Ataque en cono que se carga y al completarse daña/stunea.", fields: ["cooldown", "castTimeMs", "damage", "stunDuration", "castSpeed", "coneAngle", "fireRange", "coneFollow", "lockTimeMs", "aimDelayMs", "startDelay"] },
    "bomb": { label: "Lanzador de Bombas", icon: "💣", desc: "Lanza bombas en círculo que explotan tras un retardo.", fields: ["bulletDamage", "radius", "fireRange", "bulletSpeed", "bombCount", "bombDelayMs", "fuseTimeMs", "cooldown", "startDelay"] },
    "circle_cast": { label: "Explosión Circular", icon: "⭕", desc: "Ataque circular que se carga siguiendo al enemigo y explota dañando a todos.", fields: ["cooldown", "castTimeMs", "damage", "fireRange", "lockTimeMs", "startDelay"] },
    "sleep": { label: "Sueño Inducido (Sleep)", icon: "💤", desc: "Duerme a los pilotos con somnolencia progresiva y un efecto de pesadilla al despertar.", fields: ["fireRange", "targetCount", "targetMode", "targetSphereColor", "duration", "slowPercentage", "slowDuration", "damagePerSecond", "nightmareMultiplier", "wakeOnDamage", "cooldown", "startDelay"] },
    "reflect": { label: "Escudo Reflectante (Reflect)", icon: "🛡️", desc: "Devuelve daño recibido al atacante.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "duration", "reflect_mult", "startDelay"] },
    "spin_ring": { label: "Giro de Lillia (spin_ring)", icon: "🌀", desc: "Un orbe gira alrededor del enemigo. Si golpea a un jugador, le inflige daño, le da velocidad al dueño y puede aplicar slow.", fields: ["cooldown", "radius", "damage", "spinSpeed", "speedBuffAmount", "speedBuffDuration", "applySlow", "slowIsPercentage", "slowPercentage", "slowDuration", "duration", "startDelay"] },
    "summoning": { label: "Invocación (Summoning)", icon: "🧟", desc: "Invoca una cantidad de esbirros de tu elección por vida o por tiempo.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "summonCount", "spawnRadius", "summonDurationMode", "summonDurationMs", "summonsList", "startDelay"] },
    "survival_dome": { label: "Domo de Supervivencia (Survival Dome)", icon: "🔮", desc: "Carga un ataque masivo creando un domo seguro en una ubicacion aleatoria.", fields: ["fireRange", "safeRadius", "maxOffset", "castTimeMs", "cooldown", "damage", "postCastWaitMs", "startDelay", "debuffsList"] },
    "ice_storm": { label: "Tormenta de Hielo", icon: "❄️", desc: "Invoca una tormenta de hielo persistente que daña y ralentiza a los jugadores en el área.", fields: ["cooldown", "castTimeMs", "fireRange", "radius", "lockTimeMs", "duration", "tick_interval", "damage_per_tick", "slow_amount", "startDelay"] },
    "worm_boomerang": { label: "Gusanos Bumerán", icon: "🪱", desc: "Lanza un abanico de gusanos que se alejan, se detienen y regresan al origen dañando.", fields: ["projectileCount", "spreadAngle", "bulletSpeed", "fireRange", "parkTimeMs", "bulletDamage", "returnDamage", "debuffsList", "cooldown", "startDelay"] },
    "wind_wall": { label: "Aluvión de Viento", icon: "🌪️", desc: "El enemigo carga una pared de viento visible y, al completarla, la dispara hacia afuera: expulsa al jugador, le hace daño y puede aplicarle efectos extra configurables.", fields: ["castTimeMs", "wallStartOffset", "wallWidth", "bulletSpeed", "fireRange", "bulletDamage", "pushForce", "debuffsList", "cooldown", "startDelay"] },
    "burrow": { label: "Zambullida Telúrica", icon: "🕳️", desc: "El enemigo se hunde bajo tierra, viaja en línea recta hacia un objetivo seleccionable (por proximidad, aleatorio, menos vida, más vida, mayor daño causado, mayor curación, más esferas o por color de esfera), permanece un tiempo oculto bajo tierra, muestra un círculo de aviso en el piso antes de emerger y sale rompiendo el suelo: círculo de daño único o zona persistente con su propio daño por tick + debuffs configurables.", fields: ["cooldown", "castTimeMs", "burrowSpeed", "fireRange", "radius", "bulletDamage", "undergroundMs", "warnTimeMs", "burstMode", "zoneDuration", "zoneTickMs", "zoneDamage", "targetMode", "targetSphereColor", "debuffsList", "startDelay"] },
    "polymorph": { label: "Polimorfia (Cubito)", icon: "🗺️", desc: "Lanza proyectiles cúbicos que transforman al jugador. Configurable: cantidad, velocidad, homing, daño, duración, si bloquea movimiento/habilidades y selección de objetivo (proximidad, aleatorio, más esferas o por color de esfera).", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "startDelay", "bulletCount", "bulletSpeed", "fireRange", "bulletDamage", "polyDuration", "isPointAndClick", "canMove", "canUseSkills", "targetCount", "targetMode", "targetSphereColor"] },
    "meteor": { label: "Lluvia de Meteoritos", icon: "☄️", desc: "Invocan meteoritos desde el cielo: tras un aviso en el piso, caen sobre los objetivos seleccionados, infligen daño en área y pueden aplicar debuffs configurables.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "startDelay", "meteorCount", "fallHeight", "fallSpeed", "meteorSize", "explosionRadius", "bulletDamage", "warnTimeMs", "targetMode", "targetSphereColor", "debuffsList", "persistentZone", "zoneDamage", "zoneTickMs", "zoneDuration"] },
    "execution": { label: "Ejecución Directa (Execution)", icon: "💀", desc: "Tras un tiempo de casteo, lanza una calavera inquebrantable sobre los objetivos: impacto = muerte instantánea (ignora escudo y vida).", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "startDelay", "castTimeMs", "targetCount", "targetMode", "targetSphereColor", "fireRange", "bulletSpeed", "isPointAndClick", "turnSpeed"] },
    "ascension": { label: "Ascensión Telúrica (Ascension)", icon: "🎈", desc: "Inversa de la Zambullida: el objetivo vuela hacia el cielo tras un casteo, el área de caída se marca en el piso y al aterrizar recibe daño en el área.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "startDelay", "castTimeMs", "targetCount", "targetMode", "targetSphereColor", "fireRange", "radius", "bulletDamage", "airTimeMs", "warnDelayMs", "warnTimeMs"] }
};

// v266.230: Definición de Mecánicas de Movimiento (Cerebros)
const DEFAULT_MOVEMENT_LIB = {
    "chase": { label: "Persecución Directa", icon: "🏃", desc: "Persigue al jugador hasta una distancia fija.", fields: ["speed", "stopDist"] },
    "sniper": { label: "Francotirador (Kiting)", icon: "🎯", desc: "Mantiene una distancia segura alejándose si te acercas.", fields: ["speed", "idealDist"] },
    "orbit": { label: "Órbita Circular", icon: "🔄", desc: "Gira alrededor del jugador constantemente.", fields: ["speed", "orbitRadius"] },
    "charger": { label: "Embestida (Dash)", icon: "⚡", desc: "Se acerca y lanza ataques de alta velocidad.", fields: ["speed", "chargeCooldown"] },
    "zigzag": { label: "Movimiento ZigZag", icon: "↩️", desc: "Persigue al jugador zigzagueando de lado a lado.", fields: ["speed", "stopDist", "amplitude", "frequency"] },
    "kamikaze": { label: "Kamikaze", icon: "💣", desc: "Se lanza hacia vos al bajar de HP y explota.", fields: ["activationHP", "speed", "explosionDamage", "duration", "explodeOnDeath"] },
    "prowler": { label: "Merodeador", icon: "🐾", desc: "Movimiento de patrulla autónoma en un rango circular configurable.", fields: ["speed", "patrolRange", "changeTrigger", "changeInterval", "changeType"] },
    "aura_speed": { label: "Aura de Impulso", icon: "🌬️", desc: "Aumenta la velocidad en un área circular.", fields: ["activationHP", "radius", "speedBonus", "duration", "cooldown", "startDelay", "affectsEnemies", "affectsBosses"] },
    "boss": { label: "Cerebro de Boss (Fases)", icon: "💀", desc: "Cerebro de Boss con fases de combate (láser, embestida y misiles).", fields: ["speed", "stopDist", "startDelay"] }
};

// v500.0: Definición de Campos de Condiciones para Fases Dinámicas
const MOVEMENT_CONDITION_FIELDS = [
    { key: 'engagement', label: '⚡ Estado de Combate', type: 'select',
      options: [
        { value: 'idle', label: '🪫 Reposo (fuera de combate)' },
        { value: 'combat', label: '⚔️ En combate' },
        { value: 'returning', label: '↩️ Regresando al spawn' }
      ]},
    { key: 'hpPercentBelow', label: '❤️ HP por debajo de (%)', type: 'number', min: 0, max: 100 },
    { key: 'shieldPercentBelow', label: '🛡️ Escudo por debajo de (%)', type: 'number', min: 0, max: 100 },
    { key: 'timeInCombatMs', label: '⏱️ Tiempo en combate (ms)', type: 'number', min: 0 },
    { key: 'timeSinceSpawnMs', label: '🕐 Tiempo desde spawn (ms)', type: 'number', min: 0 }
];

// v266.300: Definición de Mecánicas de Defensa
const DEFAULT_DEFENSE_LIB = {
    "basic_defense": { label: "Defensa Estándar", icon: "🛡️", desc: "Mecánica de mitigación de daño y regeneración.", fields: ["reductionPercentage", "shieldRegen", "duration", "cooldown", "startDelay"] },
    "aura_heal": { label: "Aura Curativa", icon: "✨", desc: "Cura a los aliados cercanos continuamente.", fields: ["activationHP", "radius", "healAmount", "intervalMs", "duration", "cooldown", "startDelay", "affectsEnemies", "affectsBosses"] },
    "invulnerability": { label: "Invulnerabilidad Temporal", icon: "💎", desc: "Se vuelve inmune a todo daño por un tiempo.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "duration", "cooldown", "startDelay"] },
    "invisibility": { label: "Invisibilidad / Camuflaje", icon: "👤", desc: "El enemigo se vuelve invisible o camuflado.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "duration", "cooldown", "invisType", "keepAttacking", "changeSpeed", "invisSpeedMultiplier", "startDelay"] },
    "boss_pillars": { label: "Pilares del Boss", icon: "🗼", desc: "Invoca pilares que lo protegen y curan hasta ser destruidos.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "pillarCount", "pillarType", "pillarHp", "pillarShield", "pillarName", "spawnRadius", "duration", "healIntervalMs", "healPercentPerTick", "healPercentPerPillarOnExpiry", "cooldown"] },
    "boss_colors": { label: "Mecánica de Colores", icon: "🎨", desc: "El Boss y los jugadores cercanos reciben colores. Solo los del color del Boss pueden dañarlo.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "duration", "cooldown", "radius"] },
    "boss_water_orbs": { label: "Orbes de Agua", icon: "💧", desc: "Invoca orbes que viajan al boss. Interceptarlas hace daño pero evita que el boss se cure.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "orbCount", "spawnRadius", "orbSpeed", "playerDamage", "bossHealPercent", "duration", "cooldown"] },
    "duplicado": { label: "Duplicación Defensiva", icon: "👥", desc: "El enemigo se divide en clones que persiguen al jugador y explotan curando al original.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cloneCount", "cloneSpeed", "cloneDuration", "cloneExplodeOnExpiry", "spawnRadius", "cooldown"] },
    "wall_dome": { label: "Muro de Energía (Wall Dome)", icon: "🌐", desc: "Crea una cúpula protectora que bloquea proyectiles del exterior.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "duration", "radius", "startDelay"] },
    "reflect": { label: "Escudo Reflectante (Reflect)", icon: "🛡️", desc: "Devuelve daño recibido al atacante.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "duration", "reflect_mult", "startDelay"] },
    "shield_steal": { 
        label: "Robador de Escudo (Shield Steal)", 
        icon: "💠", 
        desc: "Dispara un proyectil celestial que se vincula al jugador impactado, robándole escudo por ticks y transfiriéndose al enemigo.", 
        fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "fireRange", "bulletSpeed", "duration", "startDelay", "stealMode", "stealAmount", "stealIntervalMs", "targetMode", "targetSphereColor", "giveToEnemy", "bulletDamage", "isPointAndClick"]
    },
    "life_steal": { 
        label: "Robador de Vida (Life Steal)", 
        icon: "💚", 
        desc: "Igual que el Robador de Escudo pero roba VIDA al jugador por ticks y se la transfiere al enemigo. Aros y números en verde.", 
        fields: ["activationMode", "activationHPs", "activationIntervalMs", "cooldown", "fireRange", "bulletSpeed", "duration", "startDelay", "stealMode", "stealAmount", "stealIntervalMs", "targetMode", "targetSphereColor", "giveToEnemy", "bulletDamage", "isPointAndClick"]
    }
};

// v266.300: Definición de Mecánicas de Ambiente (Hazards)
let AMMO_MECH_LIB = {
    "bleed": { label: "Sangrado", icon: "🩸", desc: "Daño por segundo durante un tiempo.", fields: ["damagePerSecond", "duration"] },
    "stun": { label: "Parálisis", icon: "⚡", desc: "Inmoviliza al objetivo.", fields: ["duration", "chance"] },
    "area": { label: "Daño de Área", icon: "💥", desc: "Explota al impactar.", fields: ["damagePerSecond", "radius"] },
    "critical": { label: "Golpe Crítico", icon: "💎", desc: "Probabilidad de daño extra.", fields: ["chance"] }
};

let AMBIENCE_LIB = {
    "radiation": { label: "Radiación", icon: "☢️", desc: "Daño constante por intervalos de tiempo.", fields: ["damage", "intervalMs"] },
    "nebula": { label: "Nebulosa", icon: "🌫️", desc: "Efecto de slow ambiental.", fields: ["slowPercentage", "visibility"] },
    "gravity": { label: "Gravedad Alta", icon: "🪐", desc: "Reduce la velocidad de dash.", fields: ["dashPenalty"] },
    "extreme_aggression": { 
        label: "Agresividad Extrema", 
        icon: "👹", 
        desc: "Enemigos acechan a toda distancia y con stats potenciados.", 
        fields: ["damageMult", "speedMult", "healthMult", "respawnSpeedBonus"] 
    },
    "vortex_hazard": {
        label: "Vórtices de Acecho",
        icon: "🌪️",
        desc: "Crea vórtices debajo de los jugadores que los succionan y dañan.",
        fields: ["spawnInterval", "duration", "pullForce", "damage", "damageInterval", "radius"]
    },
    "blindness_hazard": {
        label: "Ceguera de Vacío",
        icon: "👁️‍🗨️",
        desc: "Oscurece la pantalla de todos los jugadores periódicamente.",
        fields: ["spawnInterval", "duration", "radius"]
    },
    "interferencia_hazard": {
        label: "Interferencia de Vacío",
        icon: "📡",
        desc: "Bloquea los slots de combate y genera estática visual.",
        fields: ["spawnInterval", "duration", "shakeIntensity", "staticIntensity"]
    },
    "freeze_hazard": {
        label: "Congelación de Vacío",
        icon: "❄️",
        desc: "Ralentiza a los jugadores y tiñe el mapa de blanco.",
        fields: ["spawnInterval", "duration", "slowPercentage", "slowFixed"]
    },
    "multiplicador": {
        label: "Multiplicador",
        icon: "🧬",
        desc: "Multiplica la vida, escudo, velocidad y daño de los enemigos.",
        fields: ["multiplier"]
    },
    "healing_penalty": {
        label: "Penalizador de Curación",
        icon: "💉",
        desc: "Inhibe o reduce las curaciones de vida recibidas (porcentual o fija).",
        fields: ["penaltyPercentage", "penaltyFixed"]
    }
};

const DEFAULT_HOUSING_CONFIG = {
    levelRequired: 5,
    cost: 10000,
    currency: "hubs",
    gridSize: 10,
    placeableItems: [
        { id: "chair", name: "Silla Metálica", cost: 200, currency: "hubs", model: "res://assets/3d/chair.glb" },
        { id: "table", name: "Mesa de Hangar", cost: 500, currency: "hubs", model: "res://assets/3d/table.glb" },
        { id: "light", name: "Pilar de Luz", cost: 800, currency: "hubs", model: "res://assets/3d/light.glb", isLight: true },
        { id: "plant", name: "Holo-Planta", cost: 300, currency: "hubs", model: "res://assets/3d/plant.glb" },
        { id: "terminal", name: "Terminal de Datos", cost: 1500, currency: "ohcu", model: "res://assets/3d/terminal.glb" }
    ]
};

const DEFAULT_MARKET_CONFIG = {
    enabled: true,
    accessZoneId: 1,
    listingDurationHours: 48,
    expiryCheckIntervalMs: 60000,
    cacheRefreshIntervalMs: 300000,
    maxActiveListingsPerPlayer: 10,
    sellTaxPercent: 5,
    listingFeeHubs: 0,
    listingFeeOhcu: 0,
    minPriceHubs: 10,
    maxPriceHubs: 0,
    minPriceOhcu: 1,
    maxPriceOhcu: 0,
    blockedItemIds: [],
    allowSelfBuy: false
};

const DEFAULT_QUESTS_CONFIG = [
    {
        id: "quest_1",
        name: "El Despertar del Piloto",
        desc: "Derrota a 5 enemigos regulares para demostrar tu valía en órbita.",
        type: "story",
        targetType: "kill",
        targetId: "1",
        targetAmount: 5,
        reward: {
            exp: 500,
            hubs: 1000,
            ohcu: 5,
            items: [],
            unlocks: []
        }
    }
];

const DEFAULT_QUESTS_GLOBAL_CONFIG = {
    maxActiveQuests: 3
};

// v600.0: Tipos de desbloqueos otorgables como recompensa de misión
const UNLOCK_TYPES_LIB = {
    "map": { label: "🗺️ Portal / Sector", desc: "Habilita el acceso a un mapa" },
    "item": { label: "🔫 Ítem / Arma", desc: "Permite equipar y usar un objeto" },
    "skill": { label: "✨ Habilidad", desc: "Permite usar una habilidad" },
    "talent": { label: "⭐ Talento", desc: "Permite invertir puntos en un talento" },
    "generic": { label: "🔧 Genérico", desc: "Clave personalizada para mecánicas futuras" }
};

// v600.0: Talentos que inician bloqueados y solo se desbloquean por misión
const DEFAULT_TALENTS_LOCKED_CONFIG = [];

const DEFAULT_RANKING_CONFIG = {
    categories: [
        {
            id: "monsters_killed",
            name: "Monstruos Matados",
            icon: "👾",
            resetInterval: "weekly",
            rewards: [
                { rank: 1, hubs: 50000, ohcu: 100, exp: 10000, bpExp: 5000, items: [] },
                { rank: 2, hubs: 25000, ohcu: 50, exp: 5000, bpExp: 2500, items: [] },
                { rank: 3, hubs: 10000, ohcu: 25, exp: 2500, bpExp: 1000, items: [] }
            ]
        },
        {
            id: "events_completed",
            name: "Eventos Completados",
            icon: "🎯",
            resetInterval: "monthly",
            rewards: [
                { rank: 1, hubs: 100000, ohcu: 200, exp: 20000, bpExp: 10000, items: [] },
                { rank: 2, hubs: 50000, ohcu: 100, exp: 10000, bpExp: 5000, items: [] },
                { rank: 3, hubs: 25000, ohcu: 50, exp: 5000, bpExp: 2500, items: [] }
            ]
        },
        {
            id: "level",
            name: "Nivel Alcanzado",
            icon: "⭐",
            resetInterval: "never",
            rewards: [
                { rank: 1, hubs: 200000, ohcu: 500, exp: 50000, bpExp: 25000, items: [] },
                { rank: 2, hubs: 100000, ohcu: 250, exp: 25000, bpExp: 10000, items: [] },
                { rank: 3, hubs: 50000, ohcu: 100, exp: 10000, bpExp: 5000, items: [] }
            ]
        }
    ]
};
