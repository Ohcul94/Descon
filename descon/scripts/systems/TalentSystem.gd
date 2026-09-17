extends Node

# TalentSystem.gd (v2.0 - Visual Tree Support)
# Gestiona la lógica de talentos y la sincronización con el servidor.
# Soporta árbol visual con nodes, connections, nodeType, etc.

signal talents_updated

var skill_tree: Dictionary = {
	"engineering": [0,0,0,0,0,0,0,0],
	"combat": [0,0,0,0,0,0,0,0],
	"science": [0,0,0,0,0,0,0,0]
}
var skill_points: int = 0
var unlocks: Array = []

# Config del árbol visual (nodes, connections, talents, etc.)
var talents_visual_config: Dictionary = {}

func _ready():
	add_to_group("talent_system")
	if NetworkManager:
		if not NetworkManager.inventory_data.is_connected(_on_inventory_data):
			NetworkManager.inventory_data.connect(_on_inventory_data)
		if not NetworkManager.login_success.is_connected(_on_inventory_data):
			NetworkManager.login_success.connect(_on_inventory_data)
		# Cargar config visual del servidor
		if NetworkManager.server_config:
			talents_visual_config = NetworkManager.server_config.get("talentsConfig", {})
	
	print("[TALENT-SYS] Sistema v2.0 listo.")

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
	
	# Actualizar config visual si viene en los datos
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
	var bonuses = { "hp_pct": 0.0, "sh_pct": 0.0, "dmg_pct": 0.0, "speed_pct": 0.0 }
	if typeof(skill_tree) != TYPE_DICTIONARY: return bonuses
	
	# Intentar usar la config visual para calcular bonos dinámicamente
	var tc = talents_visual_config
	var talents_list = tc.get("talents", [])
	
	if talents_list.size() > 0:
		# Calcular bonos desde la config visual
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
				elif key == "hp_pct":
					bonuses["hp_pct"] += val
				elif key == "sh_pct":
					bonuses["sh_pct"] += val
				elif key == "laser_dmg_pct" or key == "dmg_pct":
					bonuses["dmg_pct"] += val
				elif key == "speed_pct":
					bonuses["speed_pct"] += val
		return bonuses
	
	# Fallback: cálculo hardcoded (compatibilidad con configs viejas)
	if skill_tree.has("engineering") and typeof(skill_tree["engineering"]) == TYPE_ARRAY and skill_tree["engineering"].size() > 0:
		bonuses["hp_pct"] = (skill_tree["engineering"][0] * 0.02)
		if skill_tree["engineering"].size() > 1:
			bonuses["sh_pct"] = (skill_tree["engineering"][1] * 0.02)
	
	if skill_tree.has("combat") and typeof(skill_tree["combat"]) == TYPE_ARRAY and skill_tree["combat"].size() > 0:
		bonuses["dmg_pct"] = (skill_tree["combat"][0] * 0.03)
	
	if skill_tree.has("science") and typeof(skill_tree["science"]) == TYPE_ARRAY and skill_tree["science"].size() > 0:
		bonuses["speed_pct"] = (skill_tree["science"][0] * 0.015)
	
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
