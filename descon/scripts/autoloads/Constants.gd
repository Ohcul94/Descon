extends Node
# Constants.gd (v142.0 - FULL DATABASE RESTORE)
# Recuperación de ítems, naves y multiplicadores desde JS original.

const GAME_CONFIG = {
	"worldSize": 4000.0,
	"vignette_intensity": 0.5,
	"camera_shake": true,
	"regenDelay": 5000,
	"regenRate": 0.1
}

const SHIP_MODELS = [
	{ "id": 1, "name": "Phoenix-L1", "hp": 2000, "shield": 1000, "speed": 300, "slots": { "w": 1, "s": 1, "e": 1, "x": 1 }, "prices": { "hubs": 0, "ohcu": 0 } },
	{ "id": 2, "name": "Vulture-G2", "hp": 4500, "shield": 2500, "speed": 330, "slots": { "w": 2, "s": 2, "e": 2, "x": 2 }, "prices": { "hubs": 1000000, "ohcu": 1000 } },
	{ "id": 3, "name": "Falcon-A3", "hp": 10000, "shield": 6000, "speed": 360, "slots": { "w": 4, "s": 4, "e": 4, "x": 3 }, "prices": { "hubs": 5000000, "ohcu": 5000 } },
	{ "id": 4, "name": "Titan-S4", "hp": 25000, "shield": 15000, "speed": 390, "slots": { "w": 8, "s": 8, "e": 8, "x": 4 }, "prices": { "hubs": 20000000, "ohcu": 15000 } },
	{ "id": 5, "name": "Wraith-X5", "hp": 70000, "shield": 45000, "speed": 420, "slots": { "w": 12, "s": 12, "e": 12, "x": 5 }, "prices": { "hubs": 0, "ohcu": 50000 }, "premium": true },
	{ "id": 6, "name": "Galactus-Z6", "hp": 200000, "shield": 130000, "speed": 460, "slots": { "w": 16, "s": 16, "e": 16, "x": 6 }, "prices": { "hubs": 0, "ohcu": 200000 }, "premium": true }
]

const AMMO_MULTIPLIERS = {
	"laser": [1.0, 1.5, 2.5, 4, 8, 15],
	"missile": [1, 2, 4, 8, 16, 30],
	"mine": [1, 3, 7, 15, 40, 100]
}

const SHOP_ITEMS = {
	"weapons": [
		{ "id": "las1", "name": "Láser LF-1", "desc": "Láser básico.", "stats": "Daño: 100", "base": 100, "prices": { "hubs": 10000, "ohcu": 10 }, "type": "w" },
		{ "id": "las2", "name": "Láser LF-2", "desc": "Mejora en potencia.", "stats": "Daño: 250", "base": 250, "prices": { "hubs": 50000, "ohcu": 50 }, "type": "w" },
		{ "id": "las3", "name": "Láser LF-3", "desc": "Estándar militar.", "stats": "Daño: 600", "base": 600, "prices": { "hubs": 200000, "ohcu": 200 }, "type": "w" },
		{ "id": "las4", "name": "Láser LF-4", "desc": "Vanguardia.", "stats": "Daño: 1500", "base": 1500, "prices": { "hubs": 1000000, "ohcu": 1000 }, "type": "w" },
		{ "id": "las5", "name": "Láser Prometheus", "desc": "Solar.", "stats": "Daño: 5000", "base": 5000, "prices": { "hubs": 0, "ohcu": 5000 }, "type": "w", "premium": true },
		{ "id": "las6", "name": "Cañón Hyper", "desc": "Disruptor.", "stats": "Daño: 15000", "base": 15000, "prices": { "hubs": 0, "ohcu": 15000 }, "type": "w", "premium": true }
	],
	"shields": [
		{ "id": "sh1", "name": "Escudo S1", "desc": "Mínima.", "stats": "+1000", "base": 1000, "prices": { "hubs": 10000, "ohcu": 10 }, "type": "s" },
		{ "id": "sh2", "name": "Escudo S2", "desc": "Reforzado.", "stats": "+5000", "base": 5000, "prices": { "hubs": 100000, "ohcu": 100 }, "type": "s" },
		{ "id": "sh3", "name": "Escudo SG3", "desc": "Gravitacional.", "stats": "+15000", "base": 15000, "prices": { "hubs": 500000, "ohcu": 500 }, "type": "s" },
		{ "id": "sh4", "name": "Escudo NX", "desc": "Nanobots.", "stats": "+40000", "base": 40000, "prices": { "hubs": 2000000, "ohcu": 2000 }, "type": "s" },
		{ "id": "sh5", "name": "Escudo Fusion", "desc": "Alienígena.", "stats": "+100000", "base": 100000, "prices": { "hubs": 0, "ohcu": 10000 }, "type": "s", "premium": true },
		{ "id": "sh6", "name": "Generador Z+", "desc": "Invulnerabilidad.", "stats": "+250000", "base": 250000, "prices": { "hubs": 0, "ohcu": 25000 }, "type": "s", "premium": true }
	],
	"engines": [
		{ "id": "en1", "name": "Motor M1", "desc": "Químico.", "stats": "+20", "base": 20, "prices": { "hubs": 5000, "ohcu": 5 }, "type": "e" },
		{ "id": "en2", "name": "Motor M2", "desc": "Estándar.", "stats": "+50", "base": 50, "prices": { "hubs": 50000, "ohcu": 50 }, "type": "e" },
		{ "id": "en3", "name": "Motor M3", "desc": "Iónico.", "stats": "+100", "base": 100, "prices": { "hubs": 300000, "ohcu": 300 }, "type": "e" }
	],
	"ammo": {
		"laser": [
			{"id": "am_l1", "name": "Láser T1", "tier": 0, "prices": {"hubs": 1000, "ohcu": 0}},
			{"id": "am_l2", "name": "Láser T2", "tier": 1, "prices": {"hubs": 2000, "ohcu": 2}},
			{"id": "am_l3", "name": "Láser T3", "tier": 2, "prices": {"hubs": 3000, "ohcu": 4}},
			{"id": "am_l4", "name": "Láser T4", "tier": 3, "prices": {"hubs": 4000, "ohcu": 6}},
			{"id": "am_l5", "name": "Láser T5", "tier": 4, "prices": {"hubs": 0, "ohcu": 10}},
			{"id": "am_l6", "name": "Láser T6", "tier": 5, "prices": {"hubs": 0, "ohcu": 20}}
		],
		"missile": [
			{"id": "am_m1", "name": "Misil T1", "tier": 0, "prices": {"hubs": 5000, "ohcu": 5}},
			{"id": "am_m2", "name": "Misil T2", "tier": 1, "prices": {"hubs": 10000, "ohcu": 10}},
			{"id": "am_m3", "name": "Misil T3", "tier": 2, "prices": {"hubs": 15000, "ohcu": 15}},
			{"id": "am_m4", "name": "Misil T4", "tier": 3, "prices": {"hubs": 20000, "ohcu": 20}},
			{"id": "am_m5", "name": "Misil T5", "tier": 4, "prices": {"hubs": 0, "ohcu": 50}},
			{"id": "am_m6", "name": "Misil T6", "tier": 5, "prices": {"hubs": 0, "ohcu": 100}}
		],
		"mine": [
			{"id": "am_n1", "name": "Mina T1", "tier": 0, "prices": {"hubs": 10000, "ohcu": 10}},
			{"id": "am_n2", "name": "Mina T2", "tier": 1, "prices": {"hubs": 20000, "ohcu": 20}},
			{"id": "am_n3", "name": "Mina T3", "tier": 2, "prices": {"hubs": 30000, "ohcu": 30}},
			{"id": "am_n4", "name": "Mina T4", "tier": 3, "prices": {"hubs": 40000, "ohcu": 40}},
			{"id": "am_n5", "name": "Mina T5", "tier": 4, "prices": {"hubs": 0, "ohcu": 100}},
			{"id": "am_n6", "name": "Mina T6", "tier": 5, "prices": {"hubs": 0, "ohcu": 200}}
		]
	}
}

const FACTION_COLORS = {
	"neutral": Color.WHITE, "allied": Color.CYAN, "enemy": Color.RED, "boss": Color.MAGENTA
}
