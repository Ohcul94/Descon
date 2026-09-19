extends Resource
class_name SphereSkill

@export var skill_id: String = "" # Identificador único para evitar crisis de identidad
@export var skill_name: String = "Habilidad"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var type: String = "Utilidad" # Utilidad, Defensa, Curación
# v2.9: Propiedades dinámicas que priorizan el catálogo de Constants.gd (Admin Sync)
var cooldown: float:
	get:
		if GameConstants and "SKILLS_DATA" in GameConstants and GameConstants.SKILLS_DATA.has(skill_name):
			var cd_val = GameConstants.SKILLS_DATA[skill_name].get("cd", _cooldown)
			if cd_val != null:
				return float(cd_val)
		return float(_cooldown)
	set(v):
		_cooldown = float(v) if v != null else 5.0

var power_value: float:
	get:
		if GameConstants and "SKILLS_DATA" in GameConstants and GameConstants.SKILLS_DATA.has(skill_name):
			var data = GameConstants.SKILLS_DATA[skill_name]
			if typeof(data) == TYPE_DICTIONARY:
				for k in ["amount", "heal_amount", "speed", "range", "duration", "slow_amount", "reflect_mult", "revive_hp_pct", "taunt_duration"]:
					if data.has(k) and data[k] != null:
						return float(data[k])
		return float(_power_value)
	set(v):
		_power_value = float(v) if v != null else 10.0

var _cooldown: float = 5.0
var _power_value: float = 10.0

# v200.7: Esta función será llamada por el SpheresManager
func activate(player: CharacterBody2D):
	print("[SKILL] Activando: ", skill_name)
	# La lógica específica se implementará en las subclases o se manejará por tipo
	match type:
		"Utilidad":
			_apply_utility(player)
		"Defensa":
			_apply_defense(player)
		"Curación":
			_apply_healing(player)

func _apply_utility(player):
	if skill_name == "TURBO-IMPULSO" or skill_name == "HYPER-DASH":
		if player.has_method("_apply_dash") and skill_name == "HYPER-DASH":
			player._apply_dash(power_value)
		elif player.has_method("play_skill_vfx"):
			player.play_skill_vfx(skill_name, power_value)
	elif skill_name == "INVULNERABILIDAD":
		if player.has_method("play_skill_vfx"):
			player.play_skill_vfx("INVULNERABILIDAD", 2.0)

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
			player.play_skill_vfx(skill_name, actual_heal)

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
			player.play_skill_vfx(skill_name, actual_heal)
