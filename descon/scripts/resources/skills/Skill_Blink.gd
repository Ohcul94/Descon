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
	# v266.850: Leer el vector de apuntado del SkillController (Modo Celu)
	# En lugar de hardcodear el mouse, respetamos el apuntado por arrastre.
	var target_pos: Vector2
	var sc = player.get_node_or_null("SkillController")
	var is_mobile = player.get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
	
	if is_mobile and sc and sc.external_aim_vector != Vector2.ZERO:
		# Modo Celular con arrastre: usar el vector de apuntado
		target_pos = player.global_position + sc.external_aim_vector
	elif is_mobile and sc:
		# Modo Celular sin arrastre: ir hacia adelante de la nave
		target_pos = player.global_position + Vector2.RIGHT.rotated(player.rotation) * min(power_value, 200.0)
	else:
		# Modo PC: comportamiento clásico con mouse
		target_pos = player.get_global_mouse_position()
	
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
	
	# 3. VFX Reaparecer (Con un pequeño delay de 2 frames para asegurar que el motor lo oculte en el origen)
	if player.has_method("play_skill_vfx"):
		player.get_tree().create_timer(0.03).timeout.connect(func():
			if is_instance_valid(player):
				player.play_skill_vfx("BLINK_IN", 0.0)
		)
	
	# 4. Sincronía con servidor
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(0.5)
	
	super.activate(player)
