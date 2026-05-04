extends Resource
class_name SphereSkill

@export var skill_name: String = "Habilidad"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var type: String = "Movimiento" # Movimiento, Defensa, Curación
@export var cooldown: float = 5.0
@export var power_value: float = 10.0 # Cantidad de curación, velocidad, etc.

# v200.7: Esta función será llamada por el SpheresManager
func activate(player: CharacterBody2D):
	print("[SKILL] Activando: ", skill_name)
	# La lógica específica se implementará en las subclases o se manejará por tipo
	match type:
		"Movimiento":
			_apply_movement(player)
		"Defensa":
			_apply_defense(player)
		"Curación":
			_apply_healing(player)

func _apply_movement(player):
	if player.has_method("_apply_dash"):
		player._apply_dash(power_value)
	elif player.has_method("play_skill_vfx"):
		# v4.6: Delegar incremento de velocidad a play_skill_vfx para evitar duplicados
		player.play_skill_vfx("TURBO-IMPULSO", power_value)

func _apply_defense(player):
	if "current_shield" in player:
		var ms = player.get("max_shield")
		if ms == null: ms = 1000.0
		var available = max(0.0, ms - player.current_shield)
		var actual_heal = min(power_value, available)
		
		if actual_heal > 0: 
			player.current_shield += actual_heal
			if player.has_method("_update_tags"): player._update_tags()
			if player.has_method("_emit_stats"): player._emit_stats()
		
		if player.has_method("play_skill_vfx"): 
			player.play_skill_vfx("ESCUDO CELULAR", actual_heal)

func _apply_healing(player):
	if "current_hp" in player:
		var mh = player.get("max_hp")
		if mh == null: mh = 3000.0
		var available = max(0.0, mh - player.current_hp)
		var actual_heal = min(power_value, available)
		
		if actual_heal > 0: 
			player.current_hp += actual_heal
			if player.has_method("_update_tags"): player._update_tags()
			if player.has_method("_emit_stats"): player._emit_stats()
			
		if player.has_method("play_skill_vfx"): 
			player.play_skill_vfx("AUTO-REPARACIÓN", actual_heal)
