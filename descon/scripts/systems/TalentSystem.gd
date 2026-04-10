extends Node

# TalentSystem.gd (v1.0 - Modular Separation)
# Maneja la lógica y el cálculo de bonificadores del árbol de talentos.

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
		NetworkManager.inventory_data.connect(_on_inventory_data)
		NetworkManager.login_success.connect(_on_inventory_data)

func _on_inventory_data(data: Dictionary):
	# v1.0.3: Soporte para múltiples formatos de paquete (Login vs InventoryData)
	if data.has("player"): data = data.player
	elif data.has("gameData"): data = data.gameData
	
	if data.has("skillTree"):
		skill_tree = data["skillTree"]
	if data.has("skillPoints"):
		skill_points = data["skillPoints"]
	
	talents_updated.emit()
	
	# v1.0.1: Forzar recálculo en el jugador al recibir datos frescos
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p.has_method("_recalculate_stats"):
		p.skill_tree = skill_tree
		p.skill_tree["skillPoints"] = skill_points
		p._recalculate_stats()

func invest_point(category: String, index: int):
	if skill_points <= 0:
		print("[TALENTS] No hay puntos disponibles.")
		return
		
	var branch = skill_tree.get(category, [])
	if index < branch.size() and branch[index] < 5:
		# Enviamos al servidor. El servidor es quien tiene la autoridad.
		NetworkManager.send_event("investSkill", {"category": category, "index": index})
		# El servidor responderá con inventoryData, lo cual disparará _on_inventory_data aquí.
	else:
		print("[TALENTS] Nivel máximo alcanzado o índice inválido.")

func reset_talents():
	# El costo es de 5000 OHCU, se valida en el servidor
	NetworkManager.send_event("resetSkills", {})

# v1.0.2: Helper para obtener bonificadores reales para el Player.gd
func get_bonuses() -> Dictionary:
	var bonuses = {
		"hp_pct": 0.0,
		"sh_pct": 0.0,
		"dmg_pct": 0.0,
		"speed_pct": 0.0
	}
	
	# INGENIERÍA
	bonuses["hp_pct"] = (skill_tree["engineering"][0] * 0.02) # REFUERZO DE CASCO
	bonuses["sh_pct"] = (skill_tree["engineering"][1] * 0.02) # ESCUDO DINÁMICO
	
	# COMBATE
	bonuses["dmg_pct"] = (skill_tree["combat"][0] * 0.03) # LÁSER SOBRECARGA
	
	# CIENCIA
	bonuses["speed_pct"] = (skill_tree["science"][0] * 0.015) # MOTORES FUSIÓN
	
	return bonuses
