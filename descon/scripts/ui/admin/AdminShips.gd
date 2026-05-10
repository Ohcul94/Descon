extends Node

var admin_main = null

func setup(main):
	admin_main = main

func render(container):
	for i in range(GameConstants.SHIP_MODELS.size()):
		var ship = GameConstants.SHIP_MODELS[i]
		var card = admin_main._create_card(container, "REF_ID [" + str(ship.id) + "] - " + ship.name.to_upper())
		var grid = admin_main._create_grid(card, 5) # Subir a 5 columnas para el nombre
		
		# Propiedades Básicas (v226.15: RENOMBRAR SOPORTE)
		admin_main._add_input(grid, "NOMBRE", ship.name, func(v): GameConstants.SHIP_MODELS[i].name = v, true)
		admin_main._add_input(grid, "HP", str(int(ship.hp)), func(v): GameConstants.SHIP_MODELS[i].hp = int(float(v)))
		admin_main._add_input(grid, "SH", str(int(ship.shield)), func(v): GameConstants.SHIP_MODELS[i].shield = int(float(v)))
		admin_main._add_input(grid, "SPD", str(int(ship.speed)), func(v): GameConstants.SHIP_MODELS[i].speed = int(float(v)))
		
		# Slots
		admin_main._add_input(grid, "W_SLOT", str(ship.slots.w), func(v): GameConstants.SHIP_MODELS[i].slots.w = int(v))
		admin_main._add_input(grid, "S_SLOT", str(ship.slots.s), func(v): GameConstants.SHIP_MODELS[i].slots.s = int(v))
		admin_main._add_input(grid, "E_SLOT", str(ship.slots.e), func(v): GameConstants.SHIP_MODELS[i].slots.e = int(v))
		admin_main._add_input(grid, "X_SLOT", str(ship.slots.x), func(v): GameConstants.SHIP_MODELS[i].slots.x = int(v))
		
		# Economía
		admin_main._add_input(grid, "HUBS", str(int(ship.prices.hubs)), func(v): GameConstants.SHIP_MODELS[i].prices.hubs = int(float(v)))
		admin_main._add_input(grid, "OHCU", str(int(ship.prices.ohcu)), func(v): GameConstants.SHIP_MODELS[i].prices.ohcu = int(float(v)))
