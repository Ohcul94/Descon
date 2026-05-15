// v266.220: Definición de Mecánicas de Ataque
const DEFAULT_MECHANICS_LIB = {
    "laser": { label: "Láser Estándar", icon: "🔫", desc: "Ataque lineal básico.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "startDelay"] },
    "missile": { label: "Misil Rastreador", icon: "🚀", desc: "Proyectil autoguiado.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "startDelay"] },
    "ice_missile": { label: "Misil de Hielo", icon: "❄️", desc: "Ralentiza al objetivo.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "slowAmount", "slowDuration", "startDelay"] },
    "mine": { label: "Mina de Proximidad", icon: "💣", desc: "Explosivo estático.", fields: ["bulletDamage", "fireRange", "fireRate", "startDelay"] },
    "orbital_strike": { label: "Ataque Orbital", icon: "🌀", desc: "Círculos que giran y luego se disparan.", fields: ["bulletDamage", "orbitSpeed", "circleCount", "orbitRadius", "orbitDuration", "staticTime", "fireRate", "fireRange", "startDelay"] },
    "aura_damage": { label: "Aura de Vacío (Daño)", icon: "🔥", desc: "Daña a los jugadores cercanos continuamente.", fields: ["activationHP", "radius", "damage", "intervalMs", "duration", "cooldown", "startDelay"] },
    "hook": { label: "Gancho Abisal", icon: "⚓", desc: "Atrae al objetivo, lo daña y lo paraliza.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "stunDuration", "pullSpeed", "postHookWaitMs", "hookMissWaitMs", "isHoming", "turnSpeed", "startDelay"] }
};

// v266.230: Definición de Mecánicas de Movimiento (Cerebros)
const DEFAULT_MOVEMENT_LIB = {
    "chase": { label: "Persecución Directa", icon: "🏃", desc: "Persigue al jugador hasta una distancia fija.", fields: ["speed", "stopDist"] },
    "sniper": { label: "Francotirador (Kiting)", icon: "🎯", desc: "Mantiene una distancia segura alejándose si te acercas.", fields: ["speed", "idealDist"] },
    "orbit": { label: "Órbita Circular", icon: "🔄", desc: "Gira alrededor del jugador constantemente.", fields: ["speed", "orbitRadius"] },
    "charger": { label: "Embestida (Dash)", icon: "⚡", desc: "Se acerca y lanza ataques de alta velocidad.", fields: ["speed", "chargeCooldown"] },
    "kamikaze": { label: "Kamikaze", icon: "💣", desc: "Se lanza hacia vos al bajar de HP y explota.", fields: ["activationHP", "speed", "explosionDamage", "duration", "explodeOnDeath"] },
    "aura_speed": { label: "Aura de Impulso", icon: "🌬️", desc: "Aumenta la velocidad en un área circular.", fields: ["activationHP", "radius", "speedBonus", "duration", "cooldown", "startDelay", "affectsEnemies", "affectsBosses"] }
};

// v266.300: Definición de Mecánicas de Defensa
const DEFAULT_DEFENSE_LIB = {
    "basic_defense": { label: "Defensa Estándar", icon: "🛡️", desc: "Mecánica de mitigación de daño y regeneración.", fields: ["reductionPercentage", "shieldRegen", "duration", "cooldown", "startDelay"] },
    "aura_heal": { label: "Aura Curativa", icon: "✨", desc: "Cura a los aliados cercanos continuamente.", fields: ["activationHP", "radius", "healAmount", "intervalMs", "duration", "cooldown", "startDelay", "affectsEnemies", "affectsBosses"] },
    "invulnerability": { label: "Invulnerabilidad Temporal", icon: "💎", desc: "Se vuelve inmune a todo daño por un tiempo.", fields: ["activationHP", "duration", "cooldown", "startDelay"] }
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
