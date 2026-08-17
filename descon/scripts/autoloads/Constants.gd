extends Node

# Constants.gd (v255.20 - REESTRUCTURACIÓN TOTAL DE ENTIDADES Y IDS)
# Mapa de IDs normalizado: 1-99 Enemigos Regulares, 100+ Bosses.

func _ready():
	if NetworkManager:
		if not NetworkManager.admin_config_updated.is_connected(_on_config_updated):
			NetworkManager.admin_config_updated.connect(_on_config_updated)
		if not NetworkManager.config_updated.is_connected(_on_config_updated):
			NetworkManager.config_updated.connect(_on_config_updated)

var FULL_CONFIG = {}
var MARKET_CONFIG = {} # v500.0: Casa de Subastas (recibe config.marketConfig del servidor)

func _on_config_updated(config):
	if typeof(config) != TYPE_DICTIONARY: return
	FULL_CONFIG = config
	
	if config.has("shipModels"): SHIP_MODELS = config.shipModels
	if config.has("enemyModels"): ENEMY_MODELS = config.enemyModels
	if config.has("shopItems"): SHOP_ITEMS = config.shopItems
	if config.has("ammoMultipliers"): AMMO_MULTIPLIERS = config.ammoMultipliers
	if config.has("hordeConfig"): HORDES_CONFIG = config.hordeConfig
	if config.has("skillsData"): SKILLS_DATA = config.skillsData
	if config.has("mapsConfig"): MAPS_CONFIG = config.mapsConfig
	if config.has("marketConfig"): MARKET_CONFIG = config.marketConfig # v500.0: Casa de Subastas
	
	print("[CONSTANTS] Configuración sincronizada con el servidor.")

var GAME_CONFIG = {
	"worldSize": 10000.0,
	"version": "2.5.5-Elite"
}

var MAPS_CONFIG = {
	"1": { "name": "Loby", "desc": "Zona segura de reunión y comercio.", "color": "#ffffff", "warpCost": 0, "minLevel": 1, "music": { "enabled": true, "path": "res://assets/Musica/Descon.wav", "volumePercent": 60 } },
	"2": { "name": "Mapa 2", "desc": "Zona de entrenamiento básico y recolección.", "color": "#00ff00", "warpCost": 0, "minLevel": 1 },
	"3": { "name": "Mapa 3", "desc": "Sector hostil con recursos de nivel medio.", "color": "#ffff00", "warpCost": 10, "minLevel": 5 },
	"4": { "name": "Mapa 4", "desc": "Nebulosa densa con piratas espaciales.", "color": "#ffaa00", "warpCost": 25, "minLevel": 10 },
	"5": { "name": "Mapa 5", "desc": "Zona de asteroides inestables.", "color": "#ff5500", "warpCost": 50, "minLevel": 15 },
	"6": { "name": "Mapa 6", "desc": "Borde exterior: Peligro extremo.", "color": "#ff0000", "warpCost": 100, "minLevel": 20 },
	"7": { "name": "Mapa 7", "desc": "Sector de invasión: Hordas detectadas.", "color": "#aa0000", "warpCost": 200, "minLevel": 25 },
	"8": { "name": "Mapa 8", "desc": "Guarida de Jefes: Requiere escolta.", "color": "#550000", "warpCost": 500, "minLevel": 30 },
	"9": { "name": "Arena PVP", "desc": "Zona de combate táctico y enfrentamiento por equipos. Destruye el nexo enemigo.", "color": "#aa00ff", "warpCost": 0, "minLevel": 1 },
	"10": { "name": "Zona de Extracción", "desc": "Sector Prohibido: Alta radiación y presencia de la flota oscura. Solo para misiones de extracción.", "color": "#ff0055", "warpCost": 50, "minLevel": 10 },
	"11": { "name": "Defensa del Altar", "desc": "Protege el Altar Sagrado del ataque de las oleadas de naves enemigas.", "color": "#ff00aa", "warpCost": 100, "minLevel": 10 },
}

var HORDES_CONFIG = {
	"active": true,
	"currentWaveIndex": 0,
	"map": 7,
	"timeBetweenWaves": 5,
	"waves": [
		{ "enemies": [ { "count": 3, "type": "1" } ], "name": "Fase 1: Reconocimiento", "rewardMultiplier": 1 },
		{ "enemies": [ { "count": 5, "type": "1" }, { "count": 3, "type": "2" }, { "count": 5, "type": "5" } ], "name": "Fase 2: Asalto", "rewardMultiplier": 1.5 },
		{ "enemies": [ { "count": 8, "type": "3" }, { "count": 4, "type": "7" }, { "count": 2, "type": "8" } ], "name": "Fase 3: Incursión Pesada", "rewardMultiplier": 2 },
		{ "enemies": [ { "count": 10, "type": "4" }, { "count": 5, "type": "6" }, { "count": 1, "type": "101" } ], "name": "Fase 4: El Gran Juicio", "rewardMultiplier": 3 }
	]
}

var SHIP_MODELS = [
	{ "id": 1, "name": "Phoenix-L1", "hp": 3000, "shield": 1000, "speed": 500, "baseDmg": 5, "slots": { "e": 1, "s": 2, "w": 3, "x": 1 }, "prices": { "hubs": 0, "ohcu": 0 }, "vision": 1300 },
	{ "id": 2, "name": "Vulture-G2", "hp": 4500, "shield": 2500, "speed": 330, "baseDmg": 10, "slots": { "e": 2, "s": 2, "w": 2, "x": 2 }, "prices": { "hubs": 1000000, "ohcu": 1000 }, "vision": 1300 },
	{ "id": 3, "name": "Falcon-A3", "hp": 10000, "shield": 6000, "speed": 360, "baseDmg": 10, "slots": { "e": 4, "s": 4, "w": 4, "x": 3 }, "prices": { "hubs": 5000000, "ohcu": 5000 }, "vision": 1300 },
	{ "id": 4, "name": "Titan-S4", "hp": 25000, "shield": 15000, "speed": 390, "baseDmg": 10, "slots": { "e": 8, "s": 8, "w": 8, "x": 4 }, "prices": { "hubs": 20000000, "ohcu": 15000 }, "vision": 1300 },
	{ "id": 5, "name": "Wraith-X5", "hp": 70000, "shield": 45000, "speed": 420, "baseDmg": 10, "slots": { "e": 12, "s": 12, "w": 12, "x": 5 }, "prices": { "hubs": 0, "ohcu": 50000 }, "vision": 1300 },
	{ "id": 6, "name": "Galactus-Z6", "hp": 200000, "shield": 130000, "speed": 460, "baseDmg": 10, "slots": { "e": 16, "s": 16, "w": 16, "x": 6 }, "prices": { "hubs": 0, "ohcu": 200000 }, "vision": 1300 }
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
		],
		"electron": [
			{ "id": "am_el1", "name": "Electrón T1", "prices": { "hubs": 4000, "ohcu": 5 }, "range": 500 },
			{ "id": "am_el2", "name": "Electrón T2", "prices": { "hubs": 8000, "ohcu": 10 }, "range": 520 },
			{ "id": "am_el3", "name": "Electrón T3", "prices": { "hubs": 16000, "ohcu": 20 }, "range": 540 },
			{ "id": "am_el4", "name": "Electrón T4", "prices": { "hubs": 32000, "ohcu": 40 }, "range": 560 },
			{ "id": "am_el5", "name": "Electrón T5", "prices": { "hubs": 0, "ohcu": 100 }, "range": 580 },
			{ "id": "am_el6", "name": "Electrón T6", "prices": { "hubs": 0, "ohcu": 200 }, "range": 600 }
		],
		"siphon": [
			{ "id": "am_s1", "name": "Vampire Beam T1", "prices": { "hubs": 3000, "ohcu": 3 }, "range": 600, "bulletSpeed": 1200 },
			{ "id": "am_s2", "name": "Vampire Beam T2", "prices": { "hubs": 6000, "ohcu": 6 }, "range": 620, "bulletSpeed": 1200 },
			{ "id": "am_s3", "name": "Vampire Beam T3", "prices": { "hubs": 12000, "ohcu": 12 }, "range": 640, "bulletSpeed": 1200 },
			{ "id": "am_s4", "name": "Vampire Beam T4", "prices": { "hubs": 24000, "ohcu": 24 }, "range": 660, "bulletSpeed": 1200 },
			{ "id": "am_s5", "name": "Vampire Beam T5", "prices": { "hubs": 0, "ohcu": 60 }, "range": 680, "bulletSpeed": 1300 },
			{ "id": "am_s6", "name": "Vampire Beam T6", "prices": { "hubs": 0, "ohcu": 120 }, "range": 700, "bulletSpeed": 1400 }
		],
		"emp": [
			{ "id": "am_e1", "name": "EMP Pulse T1", "prices": { "hubs": 4000, "ohcu": 4 }, "range": 500, "bulletSpeed": 800 },
			{ "id": "am_e2", "name": "EMP Pulse T2", "prices": { "hubs": 8000, "ohcu": 8 }, "range": 550, "bulletSpeed": 850 },
			{ "id": "am_e3", "name": "EMP Pulse T3", "prices": { "hubs": 16000, "ohcu": 16 }, "range": 600, "bulletSpeed": 900 },
			{ "id": "am_e4", "name": "EMP Pulse T4", "prices": { "hubs": 32000, "ohcu": 32 }, "range": 650, "bulletSpeed": 950 },
			{ "id": "am_e5", "name": "EMP Pulse T5", "prices": { "hubs": 0, "ohcu": 80 }, "range": 700, "bulletSpeed": 1000 },
			{ "id": "am_e6", "name": "EMP Pulse T6", "prices": { "hubs": 0, "ohcu": 160 }, "range": 750, "bulletSpeed": 1100 }
		]
	},
	"weapons": [
		{ "id": "las1", "name": "Láser LF-1", "desc": "Láser básico.", "base": 100, "icon": "res://assets/Armas/Arma1/Arma1.png", "prices": { "hubs": 10000, "ohcu": 10 } },
		{ "id": "las2", "name": "Láser LF-2", "desc": "Mejora en potencia.", "base": 250, "icon": "res://assets/Armas/Arma2/Arma2.png", "prices": { "hubs": 50000, "ohcu": 50 } },
		{ "id": "las3", "name": "Láser LF-3", "desc": "Estándar militar.", "base": 600, "icon": "res://assets/Armas/Arma3/Arma3.png", "prices": { "hubs": 200000, "ohcu": 200 } },
		{ "id": "las4", "name": "Láser LF-4", "desc": "Vanguardia tecnológica.", "base": 1500, "icon": "res://assets/Armas/Arma4/Arma4.png", "prices": { "hubs": 1000000, "ohcu": 1000 } },
		{ "id": "las5", "name": "Láser Prometheus", "desc": "Poder solar concentrado.", "base": 5000, "icon": "res://assets/Armas/Arma5/Arma5.png", "prices": { "hubs": 0, "ohcu": 5000 }, "premium": true },
		{ "id": "las6", "name": "Cañón Hyper", "desc": "Disruptor de materia.", "base": 15000, "icon": "res://assets/Armas/Arma6/Arma6.png", "prices": { "hubs": 0, "ohcu": 15000 }, "premium": true }
	],
	"shields": [
		{ "id": "sh1", "name": "Escudo S1", "desc": "Protección básica.", "base": 1000, "icon": "res://assets/Escudos/Escudo1/Escudo1.png", "prices": { "hubs": 10000, "ohcu": 10 } },
		{ "id": "sh2", "name": "Escudo S2", "desc": "Reforzado con titanio.", "base": 5000, "icon": "res://assets/Escudos/Escudo2/Escudo2.png", "prices": { "hubs": 100000, "ohcu": 100 } },
		{ "id": "sh3", "name": "Escudo SG3", "desc": "Campo gravitacional.", "base": 15000, "icon": "res://assets/Escudos/Escudo3/Escudo3.png", "prices": { "hubs": 500000, "ohcu": 500 } },
		{ "id": "sh4", "name": "Escudo NX", "desc": "Reparación por nanobots.", "base": 40000, "icon": "res://assets/Escudos/Escudo4/Escudo4.png", "prices": { "hubs": 2000000, "ohcu": 2000 } },
		{ "id": "sh5", "name": "Escudo Fusion", "desc": "Tecnología alienígena.", "base": 100000, "icon": "res://assets/Escudos/Escudo5/Escudo5.png", "prices": { "hubs": 0, "ohcu": 10000 }, "premium": true },
		{ "id": "sh6", "name": "Generador Z+", "desc": "Casi invulnerable.", "base": 250000, "icon": "res://assets/Escudos/Escudo6/Escudo6.png", "prices": { "hubs": 0, "ohcu": 25000 }, "premium": true }
	],
	"engines": [
		{ "id": "en1", "name": "Motor M1", "desc": "Propulsión química.", "base": 20, "icon": "res://assets/Motores/Motor1/Motor1.png", "prices": { "hubs": 5000, "ohcu": 5 } },
		{ "id": "en2", "name": "Motor M2", "desc": "Estándar iónico.", "base": 50, "icon": "res://assets/Motores/Motor2/Motor2.png", "prices": { "hubs": 50000, "ohcu": 50 } },
		{ "id": "en3", "name": "Motor M3", "desc": "Núcleo de plasma.", "base": 100, "icon": "res://assets/Motores/Motor3/Motor3.png", "prices": { "hubs": 300000, "ohcu": 300 } }
	],
	"extras": [
		{ "id": "ext1", "name": "CPU de Salto", "desc": "Optimiza el salto hiperespacial.", "prices": { "hubs": 50000, "ohcu": 50 } },
		{ "id": "ext2", "name": "Radar Táctico", "desc": "Mayor alcance de escaneo.", "prices": { "hubs": 100000, "ohcu": 100 } }
	]
}

var ENEMY_MODELS = {
	"1": { "name": "Enemigo 1", "hp": 500, "shield": 100, "bulletDamage": 40, "fireRate": 1000, "rewardHubs": 100, "rewardOhcu": 1, "rewardExp": 150, "speed": 450, "bulletSpeed": 800, "fireRange": 600 },
	"2": { "name": "Enemigo 2", "hp": 800, "shield": 300, "bulletDamage": 60, "fireRate": 1200, "rewardHubs": 200, "rewardOhcu": 2, "rewardExp": 200, "speed": 420, "bulletSpeed": 800, "fireRange": 650 },
	"3": { "name": "Enemigo 3", "hp": 1200, "shield": 600, "bulletDamage": 80, "fireRate": 1100, "rewardHubs": 350, "rewardOhcu": 3, "rewardExp": 300, "speed": 400, "bulletSpeed": 850, "fireRange": 700 },
	"4": { "name": "Enemigo 4", "hp": 8000, "shield": 4500, "bulletDamage": 250, "fireRate": 1000, "rewardHubs": 3500, "rewardOhcu": 35, "rewardExp": 1500, "speed": 280, "bulletSpeed": 850, "fireRange": 1000 },
	"5": { "name": "Enemigo 5", "hp": 1500, "shield": 800, "bulletDamage": 120, "fireRate": 1500, "rewardHubs": 500, "rewardOhcu": 5, "rewardExp": 400, "speed": 350, "bulletSpeed": 800, "fireRange": 750 },
	"6": { "name": "Enemigo 6", "hp": 15000, "shield": 5000, "bulletDamage": 200, "fireRate": 2500, "rewardHubs": 5000, "rewardOhcu": 50, "rewardExp": 250, "speed": 250, "bulletSpeed": 600, "fireRange": 800 },
	"7": { "name": "Enemigo 7", "hp": 3000, "shield": 1500, "bulletDamage": 160, "fireRate": 1300, "rewardHubs": 1000, "rewardOhcu": 10, "rewardExp": 600, "speed": 320, "bulletSpeed": 800, "fireRange": 700 },
	"8": { "name": "Enemigo 8", "hp": 5000, "shield": 3000, "bulletDamage": 350, "fireRate": 1200, "rewardHubs": 2500, "rewardOhcu": 25, "rewardExp": 1200, "speed": 300, "bulletSpeed": 800, "fireRange": 900 },
	"9": { "name": "Enemigo 9", "hp": 9000, "shield": 4000, "bulletDamage": 280, "fireRate": 950, "rewardHubs": 3800, "rewardOhcu": 38, "rewardExp": 1800, "speed": 310, "bulletSpeed": 880, "fireRange": 1050 },
	"10": { "name": "Enemigo 10", "hp": 11000, "shield": 5500, "bulletDamage": 320, "fireRate": 880, "rewardHubs": 4200, "rewardOhcu": 42, "rewardExp": 2200, "speed": 305, "bulletSpeed": 920, "fireRange": 1150 },
	"11": { "name": "Enemigo 11", "hp": 13000, "shield": 6500, "bulletDamage": 380, "fireRate": 820, "rewardHubs": 4800, "rewardOhcu": 48, "rewardExp": 2800, "speed": 285, "bulletSpeed": 980, "fireRange": 1250 },
	"14": { "name": "Enemigo 14", "hp": 16000, "shield": 8000, "bulletDamage": 400, "fireRate": 800, "rewardHubs": 5500, "rewardOhcu": 55, "rewardExp": 3000, "speed": 280, "bulletSpeed": 1000, "fireRange": 1300, "assetPath": "res://assets/Enemigos/3D/Enemigo14/Enemigo14.glb", "icon": "", "rotX": 0, "rotY": 90, "rotZ": 0, "scale": 2.0 },
	"15": { "name": "Enemigo 15", "hp": 20000, "shield": 10000, "bulletDamage": 500, "fireRate": 750, "rewardHubs": 6500, "rewardOhcu": 65, "rewardExp": 3500, "speed": 270, "bulletSpeed": 1050, "fireRange": 1350, "assetPath": "res://assets/Enemigos/3D/Enemigo15/Enemigo15.glb", "icon": "", "rotX": 0, "rotY": 90, "rotZ": 0, "scale": 2.0 },
	
	"101": { "name": "Lord Titán", "hp": 100000, "shield": 50000, "bulletDamage": 2000, "fireRate": 800, "rewardHubs": 50000, "rewardOhcu": 500, "rewardExp": 10000, "rageTimer": 20, "speed": 250, "bulletSpeed": 900, "fireRange": 1200, "isBoss": true },
	"102": { "name": "Ancient Titán", "hp": 200000, "shield": 100000, "bulletDamage": 5000, "fireRate": 1000, "rewardHubs": 0, "rewardOhcu": 1000, "rewardExp": 25000, "rageTimer": 20, "speed": 220, "bulletSpeed": 1000, "fireRange": 1500, "isBoss": true },
	"103": { "name": "Mechanic Boss", "hp": 150000, "shield": 75000, "bulletDamage": 3000, "fireRate": 600, "rewardHubs": 200000, "rewardOhcu": 2000, "rewardExp": 50000, "rageTimer": 20, "speed": 280, "bulletSpeed": 1100, "fireRange": 1300, "isBoss": true },
	"104": { "name": "Stellar Guardian", "hp": 300000, "shield": 150000, "bulletDamage": 8000, "fireRate": 1200, "rewardHubs": 500000, "rewardOhcu": 5000, "rewardExp": 100000, "rageTimer": 20, "speed": 260, "bulletSpeed": 1200, "fireRange": 1400, "isBoss": true },
	"105": { "name": "Titán Carmesí", "hp": 400000, "shield": 200000, "bulletDamage": 10000, "fireRate": 900, "rewardHubs": 750000, "rewardOhcu": 7500, "rewardExp": 150000, "rageTimer": 20, "speed": 240, "bulletSpeed": 1100, "fireRange": 1500, "isBoss": true, "assetPath": "res://assets/Enemigos/3D/Bosses/Boss5/Animaciones/AnimacionesBoss5.glb", "icon": "res://assets/Enemigos/2D/Bosses/Boss5/Boss5.png", "rotX": 0, "rotY": 90, "rotZ": 0, "scale": 6.0 },
	"106": { "name": "Dragón Demoníaco", "hp": 500000, "shield": 250000, "bulletDamage": 12000, "fireRate": 1000, "rewardHubs": 1000000, "rewardOhcu": 10000, "rewardExp": 200000, "rageTimer": 20, "speed": 230, "bulletSpeed": 1200, "fireRange": 1600, "isBoss": true, "assetPath": "res://assets/Enemigos/3D/Bosses/Boss6/Boss6.glb", "icon": "res://assets/Enemigos/2D/Bosses/Boss6/Boss6.png", "rotX": 0, "rotY": 90, "rotZ": 0, "scale": 6.0 },
	"107": { "name": "Dragón Cromático", "hp": 600000, "shield": 300000, "bulletDamage": 15000, "fireRate": 850, "rewardHubs": 1250000, "rewardOhcu": 12500, "rewardExp": 250000, "rageTimer": 20, "speed": 220, "bulletSpeed": 1300, "fireRange": 1700, "isBoss": true, "assetPath": "res://assets/Enemigos/3D/Bosses/Boss7/Animaciones/AnimacionesBoss7.glb", "icon": "res://assets/Enemigos/2D/Bosses/Boss7/Boss7.png", "rotX": 0, "rotY": 90, "rotZ": 0, "scale": 6.0 }
}

var AMMO_MULTIPLIERS = {
	"laser": [1, 2, 3, 4, 5, 15],
	"missile": [1, 2, 4, 8, 16, 30],
	"mine": [1, 3, 7, 15, 40, 100],
	"melee": [1.5, 3, 5, 10, 22, 50],
	"heal": [1, 1.8, 3, 5.5, 12, 25],
	"siphon": [0.8, 1.5, 2.5, 5, 10, 20],
	"emp": [0.5, 1, 1.5, 3, 6, 12],
	"electron": [1.0, 2.0, 3.5, 6.0, 12.0, 25.0]
}

var SKILLS_DATA = {
	"ESCUDO CELULAR": { "id": "SK-DEF-01", "type": "Defensa", "desc": "Inyecta plasma en los generadores para restaurar el escudo.", "amount": 600, "cd": 5000.0, "range": 0, "canTargetOthers": true, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"AUTO-REPARACIÓN": { "id": "SK-HEAL-01", "type": "Curación", "desc": "Drones de reparación restauran la integridad del casco.", "amount": 400, "cd": 5000.0, "range": 500, "canTargetOthers": true, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"NANO-REGENERACIÓN": { "id": "SK-HEAL-02", "type": "Curación", "desc": "Inyecta nanobots que reparan el casco de forma continua.", "amount": 300, "cd": 12000.0, "range": 0, "canTargetOthers": true, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"REGENERACIÓN ALFA": { "id": "SK-HEAL-03", "type": "Curación", "desc": "Un pulso de alta energía que deposita un núcleo en el suelo para restaurar 1500 HP de casco al recogerlo.", "amount": 1500, "cd": 20000.0, "range": 600, "duration": 60000.0, "radius": 100.0, "canTargetOthers": false, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"VÍNCULO VITAL": { "id": "SK-HEAL-04", "type": "Curación", "desc": "Enlaza un rayo curativo continuo a un aliado que restaura HP periódicamente. El lazo se corta si se alejan demasiado.", "amount": 250, "cd": 15000.0, "range": 350, "duration": 10000.0, "breakRange": 500.0, "tickInterval": 1000.0, "canTargetOthers": true, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"TURBO-IMPULSO": { "id": "SK-UTIL-01", "type": "Utilidad", "desc": "Aumenta la velocidad de los motores temporalmente.", "speed": 150, "cd": 5000.0, "range": 0, "canTargetOthers": true, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"HYPER-DASH": { "id": "SK-UTIL-02", "type": "Utilidad", "desc": "Propulsión instantánea hacia adelante para evasión rápida.", "speed": 1000, "duration": 500, "cd": 5000.0, "range": 0, "canTargetOthers": false },
	"INVULNERABILIDAD": { "id": "SK-UTIL-03", "type": "Utilidad", "desc": "Te vuelve inmune a todo daño durante 2 segundos.", "duration": 2.0, "cd": 30000.0, "range": 0, "canTargetOthers": false },
	"BLINK": { "id": "SK-UTIL-04", "type": "Utilidad", "desc": "Teletransportación instantánea al punto seleccionado.", "range": 450, "cd": 15000.0, "canTargetOthers": false },
	"REFLECT-OMEGA": { "id": "SK-ATK-01", "type": "Ataque", "desc": "Crea un campo de resonancia que refleja daño hostil.", "reflect_mult": 1.5, "amount": 500, "cd": 5000.0, "range": 0, "canTargetOthers": false },
	"SMOKE-BOMB": { "id": "SK-DEF-03", "type": "Defensa", "desc": "Lanza una bomba de humo que silencia y ciega a los enemigos en el área.", "duration": 6, "radius": 180, "cd": 12000.0, "range": 0, "amount": 1, "canTargetOthers": false },
	"STEALTH": { "id": "SK-UTIL-05", "type": "Utilidad", "desc": "Te vuelve invisible para enemigos y jugadores fuera de tu grupo.", "duration": 8, "cd": 25000.0, "range": 0, "canTargetOthers": false },
	"FROST-TRAIL": { "id": "SK-DEF-04", "type": "Defensa", "desc": "Deja un rastro de escarcha que ralentiza a los enemigos.", "duration": 6, "slow_amount": 0.5, "radius": 120, "cd": 18000.0, "range": 0, "canTargetOthers": false },
	"BARRERA DE VIENTO": { "id": "SK-DEF-05", "type": "Defensa", "desc": "Crea una barrera de viento que repele a los objetivos seleccionados.", "duration": 6, "width": 150, "cd": 20000.0, "range": 400, "canTargetOthers": false, "targetFilters": { "allies": false, "enemies": true, "bosses": false, "players": false } },
	"BALIZA DE CURACION": { "id": "SK-HEAL-05", "type": "Curación", "desc": "Despliega una baliza que emite ondas de curación periódicas a los aliados cercanos.", "duration": 8000.0, "pulse_interval": 1500.0, "heal_amount": 250, "cd": 18000.0, "range": 500, "radius": 200.0, "canTargetOthers": false, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true } },
	"PROVOCACION": { "id": "SK-DEF-06", "type": "Defensa", "desc": "Provoca a todos los enemigos en el área elegida, forzándolos a atacarte.", "taunt_duration": 4000.0, "cd": 15000.0, "range": 450, "radius": 220.0, "canTargetOthers": false, "targetFilters": { "allies": false, "enemies": true, "bosses": true, "players": false } },
	"RESURRECCIÓN": { "id": "SK-UTIL-06", "type": "Utilidad", "desc": "Canaliza un haz de energía en el área seleccionada para resucitar a los aliados caídos.", "cd": 45000.0, "range": 500, "radius": 200.0, "revive_hp_pct": 50, "revive_shield_pct": 20, "canTargetOthers": false, "targetFilters": { "allies": true, "enemies": false, "bosses": false, "players": true, "clan": true } }
}

