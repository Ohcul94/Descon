extends SphereSkill
class_name Skill_Blink

func _init():
	skill_id = "SK-UTIL-04"
	skill_name = "BLINK"
	description = "Teletransportación instantánea al punto seleccionado."
	type = "Utilidad"
	power_value = 450.0 # Rango máximo
	cooldown = 15.0

func activate(player: CharacterBody2D):
	# Intentar obtener la posición del mouse del controlador de habilidades
	var target_pos = player.get_global_mouse_position()
	
	var dist = player.global_position.distance_to(target_pos)
	
	# Clampear al rango máximo (Seguridad cliente)
	if dist > power_value:
		var dir = (target_pos - player.global_position).normalized()
		target_pos = player.global_position + dir * power_value
	
	# 1. VFX Desaparecer
	if player.has_method("play_skill_vfx"):
		player.play_skill_vfx("BLINK_OUT", 0.0)
	
	# 2. Teletransporte Real y Orientación
	var dir_leap = (target_pos - player.global_position).normalized()
	if dir_leap.length() > 0.1:
		player.rotation = dir_leap.angle()
	
	player.global_position = target_pos
	
	# v2.9: Cancelar el autopilot o destino de navegación anterior
	if "target_position" in player:
		player.target_position = target_pos
	
	# 3. VFX Reaparecer
	if player.has_method("play_skill_vfx"):
		# Breve delay para que se note la desaparición antes de la reaparición
		player.get_tree().create_timer(0.05).timeout.connect(func():
			if is_instance_valid(player):
				player.play_skill_vfx("BLINK_IN", 0.0)
		)
	
	# 4. Sincronía con servidor
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(0.5)
	
	super.activate(player)
