extends Node

var admin_main = null

func setup(main):
	admin_main = main

func render(container):
	var entity_tabs = TabContainer.new()
	entity_tabs.custom_minimum_size.y = 500
	container.add_child(entity_tabs)
	
	# Sub-pestaña 1: ENEMIGOS REGULARES
	var enemies_scroll = ScrollContainer.new(); enemies_scroll.name = "ENEMIGOS"; entity_tabs.add_child(enemies_scroll)
	var enemies_v = VBoxContainer.new(); enemies_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; enemies_scroll.add_child(enemies_v)
	
	# Sub-pestaña 2: BOSSES
	var bosses_scroll = ScrollContainer.new(); bosses_scroll.name = "BOSSES"; entity_tabs.add_child(bosses_scroll)
	var bosses_v = VBoxContainer.new(); bosses_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bosses_scroll.add_child(bosses_v)

	# Obtener IDs ordenados numéricamente
	var sorted_ids = GameConstants.ENEMY_MODELS.keys()
	sorted_ids.sort_custom(func(a, b): return int(a) < int(b))

	for id in sorted_ids:
		var enemy = GameConstants.ENEMY_MODELS[id]
		var target_v = bosses_v if enemy.get("isBoss", false) else enemies_v
		
		var card = admin_main._create_card(target_v, "ENTIDAD [" + str(id) + "] - " + enemy.name.to_upper())
		var grid = admin_main._create_grid(card, 4)
		
		admin_main._add_input(grid, "NOMBRE", enemy.name, func(v): GameConstants.ENEMY_MODELS[id].name = v, true)
		admin_main._add_input(grid, "HP", str(enemy.hp), func(v): GameConstants.ENEMY_MODELS[id].hp = int(v))
		admin_main._add_input(grid, "SH", str(enemy.shield), func(v): GameConstants.ENEMY_MODELS[id].shield = int(v))
		admin_main._add_input(grid, "DMG", str(enemy.bulletDamage), func(v): GameConstants.ENEMY_MODELS[id].bulletDamage = int(v))
		admin_main._add_input(grid, "RATE", str(enemy.fireRate), func(v): GameConstants.ENEMY_MODELS[id].fireRate = int(v))
		admin_main._add_input(grid, "R_HUBS", str(enemy.rewardHubs), func(v): GameConstants.ENEMY_MODELS[id].rewardHubs = int(v))
		admin_main._add_input(grid, "R_OHCU", str(enemy.get("rewardOhcu", 0)), func(v): GameConstants.ENEMY_MODELS[id].rewardOhcu = int(v))
		admin_main._add_input(grid, "R_EXP", str(enemy.get("rewardExp", 100)), func(v): GameConstants.ENEMY_MODELS[id].rewardExp = int(v))
		admin_main._add_input(grid, "SPD", str(enemy.get("speed", 3.0)), func(v): GameConstants.ENEMY_MODELS[id].speed = float(v))
		admin_main._add_input(grid, "B_SPD", str(enemy.get("bulletSpeed", 800)), func(v): GameConstants.ENEMY_MODELS[id].bulletSpeed = int(v))
		admin_main._add_input(grid, "RANGE", str(enemy.get("fireRange", 600)), func(v): GameConstants.ENEMY_MODELS[id].fireRange = int(v))
		admin_main._add_input(grid, "RAGETIME", str(enemy.get("rageTimer", 20)), func(v): GameConstants.ENEMY_MODELS[id].rageTimer = int(v))
