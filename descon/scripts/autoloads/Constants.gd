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
			{ "id": "am_l1", "name": "Láser T1", "prices": { "hubs": 1000, "ohcu": 10 } },
			{ "id": "am_l2", "name": "Láser T2", "prices": { "hubs": 2000, "ohcu": 2 } },
			{ "id": "am_l3", "name": "Láser T3", "prices": { "hubs": 3000, "ohcu": 4 } },
			{ "id": "am_l4", "name": "Láser T4", "prices": { "hubs": 4000, "ohcu": 6 } },
			{ "id": "am_l5", "name": "Láser T5", "prices": { "hubs": 0, "ohcu": 10 } },
			{ "id": "am_l6", "name": "Láser T6", "prices": { "hubs": 0, "ohcu": 20 } }
		],
		"mine": [
			{ "id": "am_n1", "name": "Mina T1", "prices": { "hubs": 10000, "ohcu": 1 } },
			{ "id": "am_n2", "name": "Mina T2", "prices": { "hubs": 20000, "ohcu": 20 } },
			{ "id": "am_n3", "name": "Mina T3", "prices": { "hubs": 30000, "ohcu": 30 } },
			{ "id": "am_n4", "name": "Mina T4", "prices": { "hubs": 40000, "ohcu": 40 } },
			{ "id": "am_n5", "name": "Mina T5", "prices": { "hubs": 0, "ohcu": 100 } },
			{ "id": "am_n6", "name": "Mina T6", "prices": { "hubs": 0, "ohcu": 200 } }
		],
		"missile": [
			{ "id": "am_m1", "name": "Misil T1", "prices": { "hubs": 5000, "ohcu": 1 } },
			{ "id": "am_m2", "name": "Misil T2", "prices": { "hubs": 10000, "ohcu": 10 } },
			{ "id": "am_m3", "name": "Misil T3", "prices": { "hubs": 15000, "ohcu": 15 } },
			{ "id": "am_m4", "name": "Misil T4", "prices": { "hubs": 20000, "ohcu": 20 } },
			{ "id": "am_m5", "name": "Misil T5", "prices": { "hubs": 0, "ohcu": 50 } },
			{ "id": "am_m6", "name": "Misil T6", "prices": { "hubs": 0, "ohcu": 100 } }
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
	"1": { "name": "Enemigo 1", "hp": 500, "shield": 100, "bulletDamage": 40, "fireRate": 1000, "rewardHubs": 100, "rewardOhcu": 1, "rewardExp": 150, "speed": 450, "bulletSpeed": 800 },
	"2": { "name": "Enemigo 2", "hp": 800, "shield": 300, "bulletDamage": 60, "fireRate": 1200, "rewardHubs": 200, "rewardOhcu": 2, "rewardExp": 200, "speed": 420, "bulletSpeed": 800 },
	"3": { "name": "Enemigo 3", "hp": 1200, "shield": 600, "bulletDamage": 80, "fireRate": 1100, "rewardHubs": 350, "rewardOhcu": 3, "rewardExp": 300, "speed": 400, "bulletSpeed": 850 },
	"5": { "name": "Enemigo 5", "hp": 1500, "shield": 800, "bulletDamage": 120, "fireRate": 1500, "rewardHubs": 500, "rewardOhcu": 5, "rewardExp": 400, "speed": 350, "bulletSpeed": 800 },
	"6": { "name": "Enemigo 6", "hp": 15000, "shield": 5000, "bulletDamage": 200, "fireRate": 2500, "rewardHubs": 5000, "rewardOhcu": 50, "rewardExp": 250, "speed": 250, "bulletSpeed": 600 },
	"7": { "name": "Enemigo 7", "hp": 3000, "shield": 1500, "bulletDamage": 160, "fireRate": 1300, "rewardHubs": 1000, "rewardOhcu": 10, "rewardExp": 600, "speed": 320, "bulletSpeed": 800 },
	"8": { "name": "Enemigo 8", "hp": 5000, "shield": 3000, "bulletDamage": 350, "fireRate": 1200, "rewardHubs": 2500, "rewardOhcu": 25, "rewardExp": 1200, "speed": 300, "bulletSpeed": 800 },
	"9": { "name": "Enemigo 4", "hp": 8000, "shield": 4500, "bulletDamage": 250, "fireRate": 1000, "rewardHubs": 3500, "rewardOhcu": 35, "rewardExp": 1500, "speed": 280, "bulletSpeed": 850 },
	"4": { "name": "Lord Titán", "hp": 100000, "shield": 50000, "bulletDamage": 2000, "fireRate": 800, "rewardHubs": 50000, "rewardOhcu": 500, "rewardExp": 10000, "rageTimer": 20, "speed": 250, "bulletSpeed": 900 },
	"10": { "name": "Ancient Titán", "hp": 200000, "shield": 100000, "bulletDamage": 5000, "fireRate": 1000, "rewardHubs": 0, "rewardOhcu": 1000, "rewardExp": 25000, "rageTimer": 20, "speed": 220, "bulletSpeed": 1000 },
	"11": { "name": "Mechanic Boss", "hp": 150000, "shield": 75000, "bulletDamage": 3000, "fireRate": 600, "rewardHubs": 200000, "rewardOhcu": 2000, "rewardExp": 50000, "rageTimer": 20, "speed": 280, "bulletSpeed": 1100 }
}

var AMMO_MULTIPLIERS = {
	"laser": [1, 2, 3, 4, 5, 15],
	"missile": [1, 2, 4, 8, 16, 30],
	"mine": [1, 3, 7, 15, 40, 100]
}

var SKILLS_DATA = {
	"ESCUDO CELULAR": { "type": "Defensa", "desc": "Regenera escudo instantáneamente.", "amount": 5000, "cd": 15.0, "range": 0 },
	"AUTO-REPARACIÓN": { "type": "Curación", "desc": "Repara la integridad de la nave.", "amount": 2500, "cd": 20.0, "range": 500 },
	"TURBO-IMPULSO": { "type": "Movimiento", "desc": "Aumenta la velocidad temporalmente.", "speed": 800, "cd": 10.0, "range": 0 },
	"REFLECT-Ω": { "type": "Defensa", "desc": "Devuelve el daño recibido.", "reflect_mult": 1.5, "cd": 30.0, "range": 0 }
}

