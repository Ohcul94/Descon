extends Node

# TalentSystem.gd (v1.1 - Professional Debug)
# Gestiona la lógica de talentos y la sincronización con el servidor.

signal talents_updated

var skill_tree: Dictionary = {
	"engineering": [0,0,0,0,0,0,0,0],
	"combat": [0,0,0,0,0,0,0,0],
	"science": [0,0,0,0,0,0,0,0]
}
var skill_points: int = 0

func _ready():
	add_to_group("talent_system")
	if NetworkManager:
		# Conectamos a los eventos de datos del servidor
		if not NetworkManager.inventory_data.is_connected(_on_inventory_data):
			NetworkManager.inventory_data.connect(_on_inventory_data)
		if not NetworkManager.login_success.is_connected(_on_inventory_data):
			NetworkManager.login_success.connect(_on_inventory_data)
	
	print("[TALENT-SYS] Sistema listo y escuchando red.")

func _on_inventory_data(data: Dictionary):
	# v1.1.1: Debug de entrada de datos
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
	
	talents_updated.emit()
	
	# Recalcular en el jugador
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p.has_method("_recalculate_stats"):
		p.skill_points = skill_points
		p._recalculate_stats()

# v1.1.3: Helper para obtener bonificadores reales para el Player.gd
func get_bonuses() -> Dictionary:
	var bonuses = { "hp_pct": 0.0, "sh_pct": 0.0, "dmg_pct": 0.0, "speed_pct": 0.0 }
	if typeof(skill_tree) != TYPE_DICTIONARY: return bonuses
	
	# INGENIERÍA
	if skill_tree.has("engineering") and typeof(skill_tree["engineering"]) == TYPE_ARRAY and skill_tree["engineering"].size() > 0:
		bonuses["hp_pct"] = (skill_tree["engineering"][0] * 0.02) # REFUERZO DE CASCO
		if skill_tree["engineering"].size() > 1:
			bonuses["sh_pct"] = (skill_tree["engineering"][1] * 0.02) # ESCUDO DINÁMICO
	
	# COMBATE
	if skill_tree.has("combat") and typeof(skill_tree["combat"]) == TYPE_ARRAY and skill_tree["combat"].size() > 0:
		bonuses["dmg_pct"] = (skill_tree["combat"][0] * 0.03) # LÁSER SOBRECARGA
	
	# CIENCIA
	if skill_tree.has("science") and typeof(skill_tree["science"]) == TYPE_ARRAY and skill_tree["science"].size() > 0:
		bonuses["speed_pct"] = (skill_tree["science"][0] * 0.015) # MOTORES FUSIÓN
	
	return bonuses

func invest_point(category: String, index: int):
	if skill_points <= 0:
		print("[TALENT-SYS] ERROR: Intentaste invertir pero tienes 0 puntos.")
		return
		
	var branch = skill_tree.get(category, [])
	
	# v1.1.4: Permitir envío si el array está vacío o es corto (el servidor lo autocompleta)
	var current_lvl = branch[index] if index < branch.size() else 0
	
	if current_lvl < 5:
		print("[TALENT-SYS] Enviando orden 'investSkill' al servidor...")
		NetworkManager.send_event("investSkill", {"category": category, "index": index})
	else:
		print("[TALENT-SYS] Nivel máximo alcanzado en ", category, " (Nivel: ", current_lvl, ")")

func reset_talents():
	print("[TALENT-SYS] Enviando orden 'resetSkills' al servidor...")
	NetworkManager.send_event("resetSkills", {})
