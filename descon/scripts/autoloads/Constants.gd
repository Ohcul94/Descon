extends Node

# Constants.gd (v252.18 - RESTAURACIÓN TOTAL DE MUNICIÓN Y ESCALAS)

var GAME_CONFIG = {
	"worldSize": 10000.0,
	"version": "2.5.2-Elite"
}

var HORDES_CONFIG = {
	"active": true,
	"currentWaveIndex": 0,
	"map": 6,
	"timeBetweenWaves": 5,
	"waves": [
		{ "enemies": [ { "count": 3, "type": "1" } ], "name": "Fase 1: Reconocimiento", "rewardMultiplier": 1 },
		{ "enemies": [ { "count": 5, "type": "1" }, { "count": 3, "type": "2" }, { "count": 5, "type": "5" } ], "name": "Fase 2: Asalto", "rewardMultiplier": 1.5 },
		{ "enemies": [ { "count": 8, "type": "3" }, { "count": 4, "type": "7" }, { "count": 2, "type": "8" } ], "name": "Fase 3: Incursión Pesada", "rewardMultiplier": 2 },
		{ "enemies": [ { "count": 10, "type": "9" }, { "count": 5, "type": "6" }, { "count": 1, "type": "4" } ], "name": "Fase 4: El Gran Juicio", "rewardMultiplier": 3 }
	]
}

var SHIP_MODELS = [
	{ "id": 1, "name": "Phoenix-L1", "hp": 3000, "shield": 1000, "speed": 500, "slots": { "e": 1, "s": 2, "w": 3, "x": 1 }, "prices": { "hubs": 0, "ohcu": 0 } },
	{ "id": 2, "name": "Vulture-G2", "hp": 4500, "shield": 2500, "speed": 330, "slots": { "e": 2, "s": 2, "w": 2, "x": 2 }, "prices": { "hubs": 1000000, "ohcu": 1000 } },
	{ "id": 3, "name": "Falcon-A3", "hp": 10000, "shield": 6000, "speed": 360, "slots": { "e": 4, "s": 4, "w": 4, "x": 3 }, "prices": { "hubs": 5000000, "ohcu": 5000 } },
	{ "id": 4, "name": "Titan-S4", "hp": 25000, "shield": 15000, "speed": 390, "slots": { "e": 8, "s": 8, "w": 8, "x": 4 }, "prices": { "hubs": 20000000, "ohcu": 15000 } },
	{ "id": 5, "name": "Wraith-X5", "hp": 70000, "shield": 45000, "speed": 420, "slots": { "e": 12, "s": 12, "w": 12, "x": 5 }, "prices": { "hubs": 0, "ohcu": 50000 } },
	{ "id": 6, "name": "Galactus-Z6", "hp": 200000, "shield": 130000, "speed": 460, "slots": { "e": 16, "s": 16, "w": 16, "x": 6 }, "prices": { "hubs": 0, "ohcu": 200000 } }
]

var SHOP_ITEMS = {
	"ammo": {
		"laser": [
			{ "id": "am_l1", "name": "Láser T1", "prices": { "hubs": 1000, "ohcu": 10 }, "range": 600 },
			{ "id": "am_l2", "name": "Láser T2", "prices": { "hubs": 2000, "ohcu": 2 }, "range": 650 },
			{ "id": "am_l3", "name": "Láser T3", "prices": { "hubs": 3000, "ohcu": 4 }, "range": 700 },
			{ "id": "am_l4", "name": "Láser T4", "prices": { "hubs": 4000, "ohcu": 6 }, "range": 750 },
			{ "id": "am_l5", "name": "Láser T5", "prices": { "hubs": 0, "ohcu": 10 }, "range": 800 },
			{ "id": "am_l6", "name": "Láser T6", "prices": { "hubs": 0, "ohcu": 20 }, "range": 1000 }
		],
		"mine": [
			{ "id": "am_n1", "name": "Mina T1", "prices": { "hubs": 10000, "ohcu": 1 }, "range": 300 },
			{ "id": "am_n2", "name": "Mina T2", "prices": { "hubs": 20000, "ohcu": 20 }, "range": 350 },
			{ "id": "am_n3", "name": "Mina T3", "prices": { "hubs": 30000, "ohcu": 30 }, "range": 400 },
			{ "id": "am_n4", "name": "Mina T4", "prices": { "hubs": 40000, "ohcu": 40 }, "range": 450 },
			{ "id": "am_n5", "name": "Mina T5", "prices": { "hubs": 0, "ohcu": 100 }, "range": 500 },
			{ "id": "am_n6", "name": "Mina T6", "prices": { "hubs": 0, "ohcu": 200 }, "range": 600 }
		],
		"missile": [
			{ "id": "am_m1", "name": "Misil T1", "prices": { "hubs": 5000, "ohcu": 1 }, "range": 800 },
			{ "id": "am_m2", "name": "Misil T2", "prices": { "hubs": 10000, "ohcu": 10 }, "range": 900 },
			{ "id": "am_m3", "name": "Misil T3", "prices": { "hubs": 15000, "ohcu": 15 }, "range": 1000 },
			{ "id": "am_m4", "name": "Misil T4", "prices": { "hubs": 20000, "ohcu": 20 }, "range": 1100 },
			{ "id": "am_m5", "name": "Misil T5", "prices": { "hubs": 0, "ohcu": 50 }, "range": 1200 },
			{ "id": "am_m6", "name": "Misil T6", "prices": { "hubs": 0, "ohcu": 100 }, "range": 1500 }
		]
	},
	"engines": [
		{ "id": "en1", "name": "Motor M1", "prices": { "hubs": 5000, "ohcu": 5 }, "base": 20 },
		{ "id": "en2", "name": "Motor M2", "prices": { "hubs": 50000, "ohcu": 50 }, "base": 50 },
		{ "id": "en3", "name": "Motor M3", "prices": { "hubs": 300000, "ohcu": 300 }, "base": 100 }
	],
	"shields": [
		{ "id": "sh1", "name": "Escudo S1", "prices": { "hubs": 10000, "ohcu": 10 }, "base": 1000 },
		{ "id": "sh2", "name": "Escudo S2", "prices": { "hubs": 100000, "ohcu": 100 }, "base": 5000 },
		{ "id": "sh3", "name": "Escudo SG3", "prices": { "hubs": 500000, "ohcu": 500 }, "base": 15000 }
	],
	"weapons": [
		{ "id": "las1", "name": "Láser LF-1", "prices": { "hubs": 10000, "ohcu": 10 }, "base": 100 },
		{ "id": "las2", "name": "Láser LF-2", "prices": { "hubs": 50000, "ohcu": 50 }, "base": 250 },
		{ "id": "las3", "name": "Láser LF-3", "prices": { "hubs": 200000, "ohcu": 200 }, "base": 600 }
	]
}

var ENEMY_MODELS = {
	"1": { "name": "Enemigo 1", "hp": 500, "shield": 100, "bulletDamage": 40, "fireRate": 1000, "rewardHubs": 100, "rewardOhcu": 1, "rewardExp": 150, "speed": 450, "bulletSpeed": 800, "fireRange": 600 },
	"2": { "name": "Enemigo 2", "hp": 800, "shield": 300, "bulletDamage": 60, "fireRate": 1200, "rewardHubs": 200, "rewardOhcu": 2, "rewardExp": 200, "speed": 420, "bulletSpeed": 800, "fireRange": 650 },
	"3": { "name": "Enemigo 3", "hp": 1200, "shield": 600, "bulletDamage": 80, "fireRate": 1100, "rewardHubs": 350, "rewardOhcu": 3, "rewardExp": 300, "speed": 400, "bulletSpeed": 850, "fireRange": 700 },
	"5": { "name": "Enemigo 5", "hp": 1500, "shield": 800, "bulletDamage": 120, "fireRate": 1500, "rewardHubs": 500, "rewardOhcu": 5, "rewardExp": 400, "speed": 350, "bulletSpeed": 800, "fireRange": 750 },
	"6": { "name": "Enemigo 6", "hp": 15000, "shield": 5000, "bulletDamage": 200, "fireRate": 2500, "rewardHubs": 5000, "rewardOhcu": 50, "rewardExp": 250, "speed": 250, "bulletSpeed": 600, "fireRange": 800 },
	"7": { "name": "Enemigo 7", "hp": 3000, "shield": 1500, "bulletDamage": 160, "fireRate": 1300, "rewardHubs": 1000, "rewardOhcu": 10, "rewardExp": 600, "speed": 320, "bulletSpeed": 800, "fireRange": 700 },
	"8": { "name": "Enemigo 8", "hp": 5000, "shield": 3000, "bulletDamage": 350, "fireRate": 1200, "rewardHubs": 2500, "rewardOhcu": 25, "rewardExp": 1200, "speed": 300, "bulletSpeed": 800, "fireRange": 900 },
	"9": { "name": "Enemigo 4", "hp": 8000, "shield": 4500, "bulletDamage": 250, "fireRate": 1000, "rewardHubs": 3500, "rewardOhcu": 35, "rewardExp": 1500, "speed": 280, "bulletSpeed": 850, "fireRange": 1000 },
	"4": { "name": "Lord Titán", "hp": 100000, "shield": 50000, "bulletDamage": 2000, "fireRate": 800, "rewardHubs": 50000, "rewardOhcu": 500, "rewardExp": 10000, "rageTimer": 20, "speed": 250, "bulletSpeed": 900, "fireRange": 1200 },
	"10": { "name": "Ancient Titán", "hp": 200000, "shield": 100000, "bulletDamage": 5000, "fireRate": 1000, "rewardHubs": 0, "rewardOhcu": 1000, "rewardExp": 25000, "rageTimer": 20, "speed": 220, "bulletSpeed": 1000, "fireRange": 1500 },
	"11": { "name": "Mechanic Boss", "hp": 150000, "shield": 75000, "bulletDamage": 3000, "fireRate": 600, "rewardHubs": 200000, "rewardOhcu": 2000, "rewardExp": 50000, "rageTimer": 20, "speed": 280, "bulletSpeed": 1100, "fireRange": 1300 },
	"12": { "name": "Enemigo 12", "hp": 10000, "shield": 5000, "bulletDamage": 300, "fireRate": 900, "rewardHubs": 4000, "rewardOhcu": 40, "rewardExp": 2000, "speed": 300, "bulletSpeed": 900, "fireRange": 1100 },
	"13": { "name": "Enemigo 13", "hp": 12000, "shield": 6000, "bulletDamage": 350, "fireRate": 850, "rewardHubs": 4500, "rewardOhcu": 45, "rewardExp": 2500, "speed": 290, "bulletSpeed": 950, "fireRange": 1200 },
	"14": { "name": "Enemigo 9", "hp": 9000, "shield": 4000, "bulletDamage": 280, "fireRate": 950, "rewardHubs": 3800, "rewardOhcu": 38, "rewardExp": 1800, "speed": 310, "bulletSpeed": 880, "fireRange": 1050 },
	"15": { "name": "Enemigo 10", "hp": 11000, "shield": 5500, "bulletDamage": 320, "fireRate": 880, "rewardHubs": 4200, "rewardOhcu": 42, "rewardExp": 2200, "speed": 305, "bulletSpeed": 920, "fireRange": 1150 },
	"16": { "name": "Enemigo 11", "hp": 13000, "shield": 6500, "bulletDamage": 380, "fireRate": 820, "rewardHubs": 4800, "rewardOhcu": 48, "rewardExp": 2800, "speed": 285, "bulletSpeed": 980, "fireRange": 1250 }
}

var AMMO_MULTIPLIERS = {
	"laser": [1, 2, 3, 4, 5, 15],
	"missile": [1, 2, 4, 8, 16, 30],
	"mine": [1, 3, 7, 15, 40, 100]
}

var SKILLS_DATA = {
	"ESCUDO CELULAR": { "id": "SK-DEF-01", "type": "Defensa", "desc": "Inyecta plasma en los generadores para restaurar el escudo.", "amount": 600, "cd": 5.0, "range": 0, "canTargetOthers": true, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"FORTALEZA-X": { "id": "SK-DEF-02", "type": "Defensa", "desc": "Sobrecarga los escudos incrementando la resistencia momentáneamente.", "amount": 1200, "cd": 15.0, "range": 0, "canTargetOthers": false },
	"AUTO-REPARACIÓN": { "id": "SK-HEAL-01", "type": "Curación", "desc": "Drones de reparación restauran la integridad del casco.", "amount": 400, "cd": 5.0, "range": 500, "canTargetOthers": true, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"NANO-REGENERACIÓN": { "id": "SK-HEAL-02", "type": "Curación", "desc": "Inyecta nanobots que reparan el casco de forma continua.", "amount": 300, "cd": 12.0, "range": 0, "canTargetOthers": true, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"TURBO-IMPULSO": { "id": "SK-UTIL-01", "type": "Utilidad", "desc": "Aumenta la velocidad de los motores temporalmente.", "speed": 150, "cd": 5.0, "range": 0, "canTargetOthers": true, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"HYPER-DASH": { "id": "SK-UTIL-02", "type": "Utilidad", "desc": "Propulsión instantánea hacia adelante para evasión rápida.", "speed": 1000, "cd": 5.0, "range": 0, "canTargetOthers": false },
	"INVULNERABILIDAD": { "id": "SK-UTIL-03", "type": "Utilidad", "desc": "Te vuelve inmune a todo daño durante 2 segundos.", "duration": 2.0, "cd": 30.0, "range": 0, "canTargetOthers": false },
	"BLINK": { "id": "SK-UTIL-04", "type": "Utilidad", "desc": "Teletransportación instantánea al punto seleccionado.", "range": 450, "cd": 15.0, "canTargetOthers": false },
	"REFLECT-Ω": { "id": "SK-ATK-01", "type": "Ataque", "desc": "Crea un campo de resonancia que refleja daño hostil.", "reflect_mult": 1.5, "amount": 500, "cd": 5.0, "range": 0, "canTargetOthers": false },
	"PLASMA BLAST": { "id": "SK-ATK-02", "type": "Ataque", "desc": "Disparo concentrado de plasma con alta potencia destructiva.", "amount": 850, "cd": 8.0, "range": 600, "canTargetOthers": true, "targetFilters": { "allies": false, "enemies": true, "bosses": true, "players": true } },
	"SMOKE-BOMB": { "id": "SK-DEF-03", "type": "Defensa", "desc": "Lanza una bomba de humo que silencia y ciega a los enemigos en el área.", "duration": 6, "radius": 180, "cd": 12.0, "range": 0, "amount": 1, "canTargetOthers": false },
	"STEALTH": { "id": "SK-UTIL-05", "type": "Utilidad", "desc": "Te vuelve invisible para enemigos y jugadores fuera de tu grupo.", "duration": 8, "cd": 25.0, "range": 0, "canTargetOthers": false },
	"FROST-TRAIL": { "id": "SK-DEF-04", "type": "Defensa", "desc": "Deja un rastro de escarcha que ralentiza a los enemigos.", "duration": 6, "slow_amount": 0.5, "radius": 120, "cd": 18.0, "range": 0, "canTargetOthers": false }
}

var MAPS_CONFIG = {
	"1": { "name": "LOBY", "desc": "Puerto seguro central de comercio.", "color": "#ffffff", "warpCost": 0, "minLevel": 1 },
	"2": { "name": "MAPA 1", "desc": "Sector de inicio y entrenamiento.", "color": "#00ffff", "warpCost": 0, "minLevel": 1 },
	"3": { "name": "MAPA 2", "desc": "Zona de exploración profunda.", "color": "#ffd700", "warpCost": 10, "minLevel": 2 },
	"4": { "name": "MAPA 3", "desc": "Sector de anomalías espaciales.", "color": "#ffa500", "warpCost": 10, "minLevel": 3 },
	"5": { "name": "MAPA 4", "desc": "Antigua base de suministros.", "color": "#00ffff", "warpCost": 10, "minLevel": 4 },
	"6": { "name": "MAPA 5", "desc": "Cinturón de radiación estelar.", "color": "#ff0000", "warpCost": 10, "minLevel": 5 },
	"7": { "name": "MAPA 6", "desc": "Sistemas de defensa remotos.", "color": "#87ceeb", "warpCost": 10, "minLevel": 6 },
	"8": { "name": "MAPA 7", "desc": "Vacío intergaláctico.", "color": "#ff00ff", "warpCost": 10, "minLevel": 7 },
	"9": { "name": "MAPA 8", "desc": "Confines del universo conocido.", "color": "#c0c0c0", "warpCost": 10, "minLevel": 8 }
}

func _ready():
	if NetworkManager:
		NetworkManager.config_updated.connect(update_from_server)

func update_from_server(data: Dictionary):
	if data.has("gameConfig"): GAME_CONFIG = data.gameConfig
	if data.has("hordeConfig"): HORDES_CONFIG = data.hordeConfig
	if data.has("shipModels"): SHIP_MODELS = data.shipModels
	if data.has("shopItems"): SHOP_ITEMS = data.shopItems
	if data.has("enemyModels"): ENEMY_MODELS = data.enemyModels
	if data.has("ammoMultipliers"): AMMO_MULTIPLIERS = data.ammoMultipliers
	if data.has("skillsData"): SKILLS_DATA = data.skillsData
	if data.has("mapsConfig"): MAPS_CONFIG = data.mapsConfig
	print("[CONSTANTS] Configuración sincronizada con el servidor.")
