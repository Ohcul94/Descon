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
	else:
		# Fallback: Aumento temporal de velocidad
		var original_speed = player.get("speed")
		if original_speed == null: original_speed = 300.0
		player.set("speed", original_speed + power_value)
		
		# --- VFX DE VELOCIDAD ---
		var vfx = null
		var path = "res://assets/Efectos de Skills/Velocidad(Transp).png"
		if ResourceLoader.exists(path):
			vfx = Sprite2D.new()
			var t = load(path)
			vfx.texture = t
			# Escalar y colocar en la retaguardia de la nave
			var s = 120.0 / max(t.get_width(), t.get_height())
			vfx.scale = Vector2(s, s)
			
			# El eje axial del ShipSprite estándar en Godot tiene su "culo" en X negativo.
			# Volvemos a colocar en el eje correcto (-45x) y giramos 180° para anular el render invertido
			vfx.rotation_degrees = 180
			vfx.position = Vector2(-45, 0)
			vfx.z_index = -1
			
			var sp_node = player.get_node_or_null("ShipSprite")
			if sp_node: sp_node.add_child(vfx)
			else: player.add_child(vfx)
			
			# Animación: Propulsor inestable/vibrante
			var tw = player.create_tween().set_loops()
			tw.tween_property(vfx, "scale", Vector2(s*1.3, s*0.8), 0.1)
			tw.tween_property(vfx, "scale", Vector2(s*0.8, s*1.3), 0.1)
		
		await player.get_tree().create_timer(2.0).timeout
		
		if is_instance_valid(vfx): vfx.queue_free()
		if is_instance_valid(player): player.set("speed", original_speed)

func _apply_defense(player):
	if "current_shield" in player:
		var ms = player.get("max_shield")
		if ms == null: ms = 1000.0
		var actual_heal = min(power_value, ms - player.current_shield)
		if actual_heal >= 0:
			if actual_heal > 0: player.current_shield += actual_heal
			if player.has_method("_spawn_damage_text"):
				player._spawn_damage_text("+" + str(int(actual_heal)), Color.AQUA)
			if player.has_method("_update_tags"): player._update_tags()
			if player.has_method("_emit_stats"): player._emit_stats()
			
			# --- VFX DE DEFENSA ---
			var path = "res://assets/Efectos de Skills/Escudo(Transp).png"
			if ResourceLoader.exists(path):
				var vfx = Sprite2D.new()
				var t = load(path)
				vfx.texture = t
				var s = 240.0 / max(t.get_width(), t.get_height())
				vfx.scale = Vector2(s*1.5, s*1.5) # Inicia explotado grande
				vfx.modulate.a = 0.0
				vfx.z_index = 2 # Por encima de la nave
				player.add_child(vfx)
				
				# Animación (Cúpula defensiva que se contrae)
				var tw = player.create_tween().set_parallel(true)
				tw.tween_property(vfx, "modulate:a", 0.8, 0.2)
				tw.tween_property(vfx, "scale", Vector2(s, s), 0.4).set_trans(Tween.TRANS_BACK)
				tw.chain().tween_property(vfx, "modulate:a", 0.0, 0.4).set_delay(0.2)
				tw.chain().tween_callback(vfx.queue_free)

func _apply_healing(player):
	if "current_hp" in player:
		var mh = player.get("max_hp")
		if mh == null: mh = 3000.0
		var actual_heal = min(power_value, mh - player.current_hp)
		if actual_heal >= 0:
			if actual_heal > 0: player.current_hp += actual_heal
			if player.has_method("_spawn_damage_text"):
				player._spawn_damage_text("+" + str(int(actual_heal)), Color.GREEN)
			if player.has_method("_update_tags"): player._update_tags()
			if player.has_method("_emit_stats"): player._emit_stats()
			
			# --- VFX DE CURACIÓN ---
			var path = "res://assets/Efectos de Skills/Curacion(Transp).png"
			if ResourceLoader.exists(path):
				var vfx = Sprite2D.new()
				var t = load(path)
				vfx.texture = t
				var s = 180.0 / max(t.get_width(), t.get_height())
				vfx.scale = Vector2(0.1, 0.1) # Inicia microscópico
				vfx.modulate.a = 0.9
				player.add_child(vfx)
				
				# Animación (Giro Mágico de Reparación)
				var tw = player.create_tween().set_parallel(true)
				tw.tween_property(vfx, "scale", Vector2(s, s), 0.5).set_trans(Tween.TRANS_ELASTIC)
				tw.tween_property(vfx, "rotation", TAU, 0.6)
				tw.tween_property(vfx, "modulate:a", 0.0, 0.4).set_delay(0.2)
				tw.chain().tween_callback(vfx.queue_free)
