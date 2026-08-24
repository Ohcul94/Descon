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
	
	if player.has_meta("_last_blink_target"):
		target_pos = player.get_meta("_last_blink_target")
		player.remove_meta("_last_blink_target")
	else:
		var sc = player.get("_skill_controller")
		if not sc:
			sc = player.get_node_or_null("SkillController")
		
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
	
	# v530.0: Clamp al borde de la nebulosa (choque duro) — Blink no puede atravesar el muro perimetral
	var map_node = player.get_tree().get_first_node_in_group("map") if player.get_tree() else null
	if is_instance_valid(map_node):
		var w = 4000.0
		var h = 4000.0
		if "world_size" in map_node and float(map_node.world_size) > 0:
			w = float(map_node.world_size)
		if "map_height" in map_node and float(map_node.map_height) > 0:
			h = float(map_node.map_height)
		target_pos.x = clamp(target_pos.x, 25.0, w - 25.0)
		target_pos.y = clamp(target_pos.y, 25.0, h - 25.0)
	
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
	if "is_moving" in player:
		player.is_moving = false
	if "autopilot_enabled" in player:
		player.autopilot_enabled = false
	if "velocity" in player:
		player.velocity = Vector2.ZERO
	
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
