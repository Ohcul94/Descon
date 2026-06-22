// v266.220: Definición de Mecánicas de Ataque
const DEFAULT_MECHANICS_LIB = {
    "laser": { label: "Láser Estándar", icon: "🔫", desc: "Ataque lineal básico.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "startDelay"] },
    "missile": { label: "Misil Rastreador", icon: "🚀", desc: "Proyectil autoguiado.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "startDelay"] },
    "ice_missile": { label: "Misil de Hielo", icon: "❄️", desc: "Ralentiza al objetivo.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "slowAmount", "slowDuration", "startDelay"] },
    "mine": { label: "Mina de Proximidad", icon: "💣", desc: "Explosivo estático.", fields: ["bulletDamage", "fireRange", "fireRate", "startDelay"] },
    "orbital_strike": { label: "Ataque Orbital", icon: "🌀", desc: "Círculos que giran y luego se disparan.", fields: ["bulletDamage", "orbitSpeed", "circleCount", "orbitRadius", "orbitDuration", "staticTime", "fireRate", "fireRange", "startDelay"] },
    "aura_damage": { label: "Aura de Vacío (Daño)", icon: "🔥", desc: "Daña a los jugadores cercanos continuamente.", fields: ["activationHP", "radius", "damage", "intervalMs", "duration", "cooldown", "startDelay"] },
    "hook": { label: "Gancho Abisal", icon: "⚓", desc: "Atrae al objetivo, lo daña y lo paraliza.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "stunDuration", "pullSpeed", "postHookWaitMs", "hookMissWaitMs", "isHoming", "turnSpeed", "startDelay"] },
    "cone_cast": { label: "Ataque en Cono Casteable", icon: "📐", desc: "Ataque en cono que se carga y al completarse daña/stunea.", fields: ["cooldown", "castTimeMs", "damage", "stunDuration", "castSpeed", "coneAngle", "fireRange", "coneFollow", "lockTimeMs", "aimDelayMs", "startDelay"] },
    "bomb": { label: "Lanzador de Bombas", icon: "💣", desc: "Lanza bombas en círculo que explotan tras un retardo.", fields: ["bulletDamage", "radius", "fireRange", "bulletSpeed", "bombCount", "bombDelayMs", "fuseTimeMs", "cooldown", "startDelay"] },
    "circle_cast": { label: "Explosión Circular", icon: "⭕", desc: "Ataque circular que se carga siguiendo al enemigo y explota dañando a todos.", fields: ["cooldown", "castTimeMs", "damage", "fireRange", "lockTimeMs", "startDelay"] },
    "sleep": { label: "Sueño Inducido (Sleep)", icon: "💤", desc: "Duerme a los pilotos con somnolencia progresiva y un efecto de pesadilla al despertar.", fields: ["fireRange", "targetCount", "targetMode", "duration", "slowPercentage", "slowDuration", "damagePerSecond", "nightmareMultiplier", "wakeOnDamage", "cooldown", "startDelay"] },
    "reflect": { label: "Escudo Reflectante (Reflect)", icon: "🛡️", desc: "Devuelve daño recibido al atacante.", fields: ["duration", "reflect_mult", "cooldown", "fireRange", "startDelay"] },
    "spin_ring": { label: "Giro de Lillia (spin_ring)", icon: "🌀", desc: "Un orbe gira alrededor del enemigo. Si golpea a un jugador, le inflige daño, le da velocidad al dueño y puede aplicar slow.", fields: ["cooldown", "radius", "damage", "spinSpeed", "speedBuffAmount", "speedBuffDuration", "applySlow", "slowIsPercentage", "slowPercentage", "slowDuration", "duration", "startDelay"] }
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
    "aura_speed": { label: "Aura de Impulso", icon: "🌬️", desc: "Aumenta la velocidad en un área circular.", fields: ["activationHP", "radius", "speedBonus", "duration", "cooldown", "startDelay", "affectsEnemies", "affectsBosses"] }
};

// v266.300: Definición de Mecánicas de Defensa
const DEFAULT_DEFENSE_LIB = {
    "basic_defense": { label: "Defensa Estándar", icon: "🛡️", desc: "Mecánica de mitigación de daño y regeneración.", fields: ["reductionPercentage", "shieldRegen", "duration", "cooldown", "startDelay"] },
    "aura_heal": { label: "Aura Curativa", icon: "✨", desc: "Cura a los aliados cercanos continuamente.", fields: ["activationHP", "radius", "healAmount", "intervalMs", "duration", "cooldown", "startDelay", "affectsEnemies", "affectsBosses"] },
    "invulnerability": { label: "Invulnerabilidad Temporal", icon: "💎", desc: "Se vuelve inmune a todo daño por un tiempo.", fields: ["activationHP", "duration", "cooldown", "startDelay"] },
    "invisibility": { label: "Invisibilidad / Camuflaje", icon: "👤", desc: "El enemigo se vuelve invisible o camuflado.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "duration", "cooldown", "invisType", "keepAttacking", "changeSpeed", "invisSpeedMultiplier", "startDelay"] },
    "boss_pillars": { label: "Pilares del Boss", icon: "🗼", desc: "Invoca pilares que lo protegen y curan hasta ser destruidos.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "pillarCount", "pillarType", "pillarHp", "pillarShield", "pillarName", "spawnRadius", "duration", "healIntervalMs", "healPercentPerTick", "healPercentPerPillarOnExpiry", "cooldown"] },
    "boss_colors": { label: "Mecánica de Colores", icon: "🎨", desc: "El Boss y los jugadores cercanos reciben colores. Solo los del color del Boss pueden dañarlo.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "duration", "cooldown", "radius"] },
    "boss_water_orbs": { label: "Orbes de Agua", icon: "💧", desc: "Invoca orbes que viajan al boss. Interceptarlas hace daño pero evita que el boss se cure.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "orbCount", "spawnRadius", "orbSpeed", "playerDamage", "bossHealPercent", "duration", "cooldown"] },
    "duplicado": { label: "Duplicación Defensiva", icon: "👥", desc: "El enemigo se divide en clones que persiguen al jugador y explotan curando al original.", fields: ["activationMode", "activationHPs", "activationIntervalMs", "cloneCount", "cloneSpeed", "cloneDuration", "cloneExplodeOnExpiry", "spawnRadius", "cooldown"] }
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
            items: []
        }
    }
];

const DEFAULT_QUESTS_GLOBAL_CONFIG = {
    maxActiveQuests: 3
};
