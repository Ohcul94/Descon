extends Node

# TalentSystem.gd (v2.1 - Full Effect Support)
# Gestiona la lógica de talentos y la sincronización con el servidor.
# Soporta árbol visual con nodes, connections, nodeType, etc.

signal talents_updated

var skill_tree: Dictionary = {}
var skill_points: int = 0
var unlocks: Array = []

# Config del árbol visual (nodes, connections, talents, etc.)
var talents_visual_config: Dictionary = {}

func _ready():
	add_to_group("talent_system")
	if NetworkManager:
		# Conectar eventos de datos
		if not NetworkManager.inventory_data.is_connected(_on_inventory_data):
			NetworkManager.inventory_data.connect(_on_inventory_data)
		if not NetworkManager.login_success.is_connected(_on_inventory_data):
			NetworkManager.login_success.connect(_on_inventory_data)
		# CRÍTICO: Conectar config_updated para recibir talentsConfig
		if not NetworkManager.config_updated.is_connected(_on_config_updated):
			NetworkManager.config_updated.connect(_on_config_updated)
		if not NetworkManager.admin_config_updated.is_connected(_on_config_updated):
			NetworkManager.admin_config_updated.connect(_on_config_updated)
		# Intentar cargar config visual si ya está disponible
		if NetworkManager.server_config and NetworkManager.server_config.size() > 0:
			talents_visual_config = NetworkManager.server_config.get("talentsConfig", {})
			print("[TALENT-SYS] Config visual cargada al inicio: ", talents_visual_config.size() > 0)
	
	print("[TALENT-SYS] Sistema v2.1 listo.")

func _on_config_updated(config: Dictionary):
	if config.has("talentsConfig"):
		talents_visual_config = config["talentsConfig"]
		print("[TALENT-SYS] Config visual actualizada via config_updated: ", talents_visual_config.size(), " keys")
		talents_updated.emit()
		# Recalcular stats del jugador
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p) and p.has_method("_recalculate_stats"):
			p._recalculate_stats()

func _on_inventory_data(data: Dictionary):
	var source = "InventoryData"
	if data.has("player"): 
		data = data.player
		source = "PlayerData"
	elif data.has("gameData"): 
		data = data.gameData
		source = "GameData"
	
	if data.has("skillTree"):
		skill_tree = data["skillTree"]
		print("[TALENT-SYS] Árbol actualizado desde ", source)
	
	if data.has("skillPoints"):
		skill_points = int(data["skillPoints"])
		print("[TALENT-SYS] Puntos actualizados: ", skill_points)
	
	if data.has("unlocks"):
		unlocks = data["unlocks"]
		print("[TALENT-SYS] Desbloqueos actualizados: ", unlocks.size())
	
	# Intentar cargar config visual si viene en los datos
	if data.has("talentsVisualConfig"):
		talents_visual_config = data["talentsVisualConfig"]
	
	talents_updated.emit()
	
	# Recalcular en el jugador
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p.has_method("_recalculate_stats"):
		p.skill_points = skill_points
		p._recalculate_stats()

# ═══════════════════════════════════════════════════════
# GETTERS PÚBLICOS
# ═══════════════════════════════════════════════════════

func get_unlocks() -> Array:
	return unlocks

func get_talent_level(talent_id: String) -> int:
	var tc = talents_visual_config
	var talents_list = tc.get("talents", [])
	for t in talents_list:
		if t.get("id", "") == talent_id:
			var cat = t.get("category", "")
			var branch = skill_tree.get(cat, [])
			# Encontrar el índice de este talento en su categoría
			var idx = 0
			for t2 in talents_list:
				if t2.get("category") == cat:
					if t2.get("id") == talent_id:
						break
					idx += 1
			return branch[idx] if idx < branch.size() else 0
	return 0

func get_talent_config() -> Dictionary:
	return talents_visual_config

# ═══════════════════════════════════════════════════════
# BONIFICADORES (para el cálculo de stats)
# ═══════════════════════════════════════════════════════

func get_bonuses() -> Dictionary:
	var bonuses = {
		"hp_pct": 0.0, "sh_pct": 0.0, "dmg_pct": 0.0, "speed_pct": 0.0,
		"hp_regen": 0.0, "shield_regen": 0.0, "armor_pct": 0.0,
		"energy_efficiency": 0.0, "stability": 0.0,
		"crit_chance": 0.0, "crit_dmg": 0.0,
		"fire_rate_pct": 0.0, "evasion_pct": 0.0,
		"cooldown_reduction": 0.0, "cooldown_reduction_flat": 0.0,
		"cast_time_reduction": 0.0, "cast_time_reduction_flat": 0.0,
		"ignore_shield_pct": 0.0, "accuracy_pct": 0.0,
		"ammo_bonus_pct": 0.0, "laser_dmg_pct": 0.0,
		"repair_cost_reduction": 0.0, "minimap_range": 0.0,
		"ohcu_kill_bonus": 0.0, "shop_discount": 0.0,
		"group_bonus": 0.0, "boss_loot_bonus": 0.0,
		"dash_distance": 0.0
	}
	if typeof(skill_tree) != TYPE_DICTIONARY:
		return bonuses
	
	var tc = talents_visual_config
	var talents_list = tc.get("talents", [])
	
	if talents_list.size() > 0:
		for t in talents_list:
			var cat = t.get("category", "")
			var branch = skill_tree.get(cat, [])
			var talents_in_cat = talents_list.filter(func(x): return x.get("category") == cat)
			var idx = talents_in_cat.find(t)
			if idx == -1 or idx >= branch.size():
				continue
			var lvl = branch[idx]
			if lvl <= 0:
				continue
			var effects = t.get("effects", {})
			for key in effects:
				var val = effects[key] * lvl
				if bonuses.has(key):
					bonuses[key] += val
		return bonuses
	
	# Fallback: si no hay config visual, calcular desde skill_tree directamente
	# Solo funciona si la config tiene categorías conocidas
	for cat in skill_tree:
		var branch = skill_tree[cat]
		if typeof(branch) != TYPE_ARRAY or branch.size() == 0:
			continue
		var cat_talents = talents_list.filter(func(t): return t.get("category") == cat)
		for i in range(min(branch.size(), cat_talents.size())):
			var lvl = branch[i]
			if lvl <= 0:
				continue
			var effects = cat_talents[i].get("effects", {})
			for key in effects:
				if bonuses.has(key):
					bonuses[key] += effects[key] * lvl
	
	return bonuses

# ═══════════════════════════════════════════════════════
# ACCIONES
# ═══════════════════════════════════════════════════════

func invest_point(category: String, index: int):
	if skill_points <= 0:
		print("[TALENT-SYS] ERROR: Intentaste invertir pero tienes 0 puntos.")
		return
		
	var branch = skill_tree.get(category, [])
	var current_lvl = branch[index] if index < branch.size() else 0
	
	# Obtener maxLevel desde la config visual
	var max_lvl = 5
	var tc = talents_visual_config
	var talents_list = tc.get("talents", [])
	var idx_count = 0
	for t in talents_list:
		if t.get("category") == category:
			if idx_count == index:
				max_lvl = t.get("maxLevel", 5)
				break
			idx_count += 1
	
	if current_lvl < max_lvl:
		print("[TALENT-SYS] Enviando investSkill: ", category, "[", index, "]")
		NetworkManager.send_event("investSkill", {"category": category, "index": index})
	else:
		print("[TALENT-SYS] Nivel máximo alcanzado: ", category, "[", index, "] lvl ", current_lvl)

func reset_talents():
	print("[TALENT-SYS] Enviando resetSkills...")
	NetworkManager.send_event("resetSkills", {})
