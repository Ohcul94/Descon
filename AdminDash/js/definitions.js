// v266.220: Definición de Mecánicas de Ataque
let MECHANICS_LIB = {
    "laser": { label: "Láser Estándar", icon: "🔫", desc: "Ataque lineal básico.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "startDelay"] },
    "missile": { label: "Misil Rastreador", icon: "🚀", desc: "Proyectil autoguiado.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "startDelay"] },
    "ice_missile": { label: "Misil de Hielo", icon: "❄️", desc: "Ralentiza al objetivo.", fields: ["bulletDamage", "bulletSpeed", "fireRange", "fireRate", "slowAmount", "slowDuration", "startDelay"] },
    "mine": { label: "Mina de Proximidad", icon: "💣", desc: "Explosivo estático.", fields: ["bulletDamage", "fireRange", "fireRate", "startDelay"] },
    "orbital_strike": { label: "Ataque Orbital", icon: "🌀", desc: "Círculos que giran y luego se disparan.", fields: ["bulletDamage", "orbitSpeed", "circleCount", "orbitRadius", "orbitDuration", "staticTime", "fireRate", "fireRange", "startDelay"] }
};

// v266.230: Definición de Mecánicas de Movimiento (Cerebros)
let MOVEMENT_LIB = {
    "chase": { label: "Persecución Directa", icon: "🏃", desc: "Persigue al jugador hasta una distancia fija.", fields: ["speed", "stopDist"] },
    "sniper": { label: "Francotirador (Kiting)", icon: "🎯", desc: "Mantiene una distancia segura alejándose si te acercas.", fields: ["speed", "idealDist"] },
    "orbit": { label: "Órbita Circular", icon: "🔄", desc: "Gira alrededor del jugador constantemente.", fields: ["speed", "orbitRadius"] },
    "charger": { label: "Embestida (Dash)", icon: "⚡", desc: "Se acerca y lanza ataques de alta velocidad.", fields: ["speed", "chargeCooldown"] },
    "kamikaze": { label: "Kamikaze", icon: "💣", desc: "Se lanza hacia vos al bajar de HP y explota.", fields: ["activationHP", "speed", "explosionDamage", "duration", "explodeOnDeath"] }
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
    }
};
