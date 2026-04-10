extends CharacterBody2D
class_name Entity

# Entity.gd (v150.20 - Non-Triangular Xeno Engine)
# Eliminación Absoluta de Triángulos en Enemigos. Siluetas Geométricas Puras.

var entity_id: String = ""
var username: String = "Unknown"
var entity_type: int = 1

var max_hp: float = 2000; var current_hp: float = 2000
var max_shield: float = 1000; var current_shield: float = 1000
var hp_regen: float = 5.0; var sh_regen: float = 15.0

var is_dead: bool = false
var is_god: bool = false
var last_combat_time: float = 0

@onready var name_tag = get_node_or_null("NameTag")
var _ui_wrapper: Node2D = null
var sprite: Sprite2D = null
var anim_player: AnimationPlayer = null

func _ready():
	add_to_group("entities")
	z_index = 1 # v166.60: Por encima de las estrellas
	visible = true; show()
	
	# Limpieza de UI basura v186
	var junk = ["HealthBar", "ShieldBar", "HP", "SH", "Health", "Shield"]
	for j in junk:
		var n = get_node_or_null(j)
		if n: n.visible = false; n.queue_free()
	
	if not _ui_wrapper:
		_ui_wrapper = Node2D.new(); _ui_wrapper.top_level = true
		_ui_wrapper.name = "HUD_Layer_Final"; _ui_wrapper.draw.connect(_draw_hud)
		add_child(_ui_wrapper)
	
	# v190.90: SISTEMA DE RECORTE Y ANIMACIÓN NAVE-1 (Phoenix)
	# Si somos una nave (no enemigo), configuramos el sprite.
	if !is_in_group("enemies"):
		_setup_ship_visuals()
	else:
		_setup_enemy_visuals()
	
	if name_tag:
		if name_tag.get_parent() != _ui_wrapper: name_tag.reparent(_ui_wrapper)
		name_tag.visible = true; name_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		name_tag.grow_horizontal = Control.GROW_DIRECTION_BOTH; name_tag.grow_vertical = Control.GROW_DIRECTION_BOTH
		name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	_update_tags()

var sync_lock_timer: float = 0.0

func activate_sync_lock(duration: float = 2.5):
	sync_lock_timer = duration
	print("[NET] Bloqueo de Sincronía activado por ", duration, "s")

func _process(delta):
	if sync_lock_timer > 0:
		sync_lock_timer -= delta
	
	if is_dead:
		if _ui_wrapper: _ui_wrapper.visible = false
		visible = false; return
	
	visible = true; show(); modulate.a = 1.0; queue_redraw()
	if _ui_wrapper: _ui_wrapper.visible = true
	
	_update_animations()
	
	# v167.70: REGENERACIÓN POST-COMBATE (SÓLO PARA EL JUGADOR LOCAL)
	if is_in_group("player") and not is_dead:
		var now = Time.get_ticks_msec()
		if now - last_combat_time > 5000:
			var regen_hp = (max_hp * 0.01) * delta
			var regen_sh = (max_shield * 0.02) * delta
			if current_hp < max_hp: current_hp = min(max_hp, current_hp + regen_hp)
			if current_shield < max_shield: current_shield = min(max_shield, current_shield + regen_sh)
			_update_tags()
	
	if is_instance_valid(_ui_wrapper):
		_ui_wrapper.global_position = global_position
		_ui_wrapper.queue_redraw()
		if name_tag: 
			name_tag.position = Vector2(-100, -90) 
			if name_tag.size.x > 0:
				name_tag.position.x = -(name_tag.size.x / 2.0)
		
		# v165.75: Seguir a la entidad con la burbuja de chat
		var bubble = get_node_or_null("ChatBubbleNode")
		if is_instance_valid(bubble):
			bubble.global_position.x = global_position.x - (bubble.size.x / 2.0)
			# Nota: Dejamos el eje Y libre para que la animación de flote funcione.

func _draw():
	# v166.61: RENDERIZADO TACTICO (Glow & Visibility Fix)
	# v190.91: Si hay sprite cargado, ya no dibujamos el polígono base
	if is_instance_valid(sprite): return

	var poly_color = Color(1, 0.4, 0)
	var pts = PackedVector2Array()
	
	if is_in_group("player") or is_in_group("remote_players"):
		poly_color = Color(0, 0.8, 1) # Cyan Neón
		pts = PackedVector2Array([Vector2(22, 0), Vector2(-15, -15), Vector2(-10, 0), Vector2(-15, 15)])
		
		# Efecto de brillo exterior
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 1, 1, 0.4), 4.0)
		draw_colored_polygon(pts, poly_color)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.5)
		return

	# ENEMIGOS: Siluetas Geométricas Distintas (No-Triángulos)
	match entity_type:
		1: # T1 - Estructura Cuadrada Táctica (Naranja)
			poly_color = Color(1, 0.45, 0) 
			pts = PackedVector2Array([Vector2(12, 12), Vector2(-12, 12), Vector2(-12, -12), Vector2(12, -12)])
		2: # T2 - Rombo de Combate Ligero (Verde Lima)
			poly_color = Color(0.5, 1, 0)
			pts = PackedVector2Array([Vector2(18, 0), Vector2(0, -18), Vector2(-18, 0), Vector2(0, 18)])
		3: # T3 - Hexágono Blindado (Dorado)
			poly_color = Color(1, 0.8, 0)
			pts = PackedVector2Array([Vector2(15, -8), Vector2(15, 8), Vector2(0, 18), Vector2(-15, 8), Vector2(-15, -8), Vector2(0, -18)])
		4: # T4 - LORD TITÁN (Octógono Fortificado - Magenta)
			poly_color = Color(1, 0, 0.5)
			pts = PackedVector2Array([Vector2(25, -12), Vector2(25, 12), Vector2(12, 25), Vector2(-12, 25), Vector2(-25, 12), Vector2(-25, -12), Vector2(-12, -25), Vector2(12, -25)])
		5: # T5 - ANCIENT BOSS (Cruz de Vindicación - Rojo Sangre)
			poly_color = Color(1, 0, 0)
			pts = PackedVector2Array([Vector2(35, 0), Vector2(8, -8), Vector2(0, -35), Vector2(-8, -8), Vector2(-35, 0), Vector2(-8, 8), Vector2(0, 35), Vector2(8, 8)])
		_: # Otros / Genéricos (Pentágono Cyan)
			poly_color = Color(0, 1, 1)
			pts = PackedVector2Array([Vector2(15, 0), Vector2(5, -15), Vector2(-15, -10), Vector2(-15, 10), Vector2(5, 15)])
	
	draw_colored_polygon(pts, poly_color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.8)

func _draw_hud():
	if is_dead: return
	var bar_w = 44.0; var gap = 2.0; var segments = 4
	var seg_w = (bar_w - (gap * (segments - 1.0))) / float(segments)
	var sh_pct = clamp(current_shield / max_shield if max_shield > 0 else 0.0, 0, 1)
	var hp_pct = clamp(current_hp / max_hp if max_hp > 0 else 0.0, 0, 1)
	for i in range(segments):
		var x = -(bar_w / 2.0) + (i * (seg_w + gap))
		_ui_wrapper.draw_rect(Rect2(x, -25, seg_w, 4), Color(0, 1, 1, 0.25))
		var f_sh = clamp((sh_pct * segments) - i, 0.0, 1.0)
		if f_sh > 0: _ui_wrapper.draw_rect(Rect2(x, -25, seg_w * f_sh, 4), Color(0, 1, 1))
		_ui_wrapper.draw_rect(Rect2(x, -18, seg_w, 4), Color(0, 1, 0, 0.25))
		var f_hp = clamp((hp_pct * segments) - i, 0.0, 1.0)
		if f_hp > 0: 
			var c = Color(0, 1, 0) if hp_pct > 0.3 else Color(1, 0, 0)
			_ui_wrapper.draw_rect(Rect2(x, -18, seg_w * f_hp, 4), c)

func reset_combat_timer():
	last_combat_time = Time.get_ticks_msec()

func update_stats(data):
	if data.has("id"): entity_id = str(data.id)
	var raw = data.get("username", data.get("user", data.get("name", "Unknown")))
	if raw != "Unknown" and raw != "Piloto" and raw != "Enemigo": username = raw
	
	# v164.94: Sincronía de Popups de Daño (Antes de pisar los valores)
	var old_total = current_hp + current_shield
	
	# v191.70: PREDICCIÓN DE CLIENTE ANTI-PARPADEO (Shield/HP Stability)
	# Si somos el jugador local, ignoramos cambios minúsculos del server (Regen vs Latencia)
	var is_local = is_in_group("player")
	var threshold = 25.0
	var lock_active = (is_local and sync_lock_timer > 0)
	
	if data.has("hp") and not lock_active:
		var server_hp = float(data.hp)
		if not is_local or abs(current_hp - server_hp) > threshold:
			current_hp = server_hp
			
	if (data.has("shield") or data.has("sh")) and not lock_active:
		var server_sh = float(data.get("shield", data.get("sh", 0)))
		if not is_local or abs(current_shield - server_sh) > threshold:
			current_shield = server_sh
			
	if data.has("maxHp") and not is_local: 
		max_hp = float(data.maxHp)
	if (data.has("maxShield") or data.has("maxSh")) and not is_local:
		max_shield = float(data.get("maxShield", data.get("maxSh", 2000)))
		
	# v192.35: Corrección de Emergencia para Aliados (Si el actual es mayor al máximo)
	if not is_local:
		if current_shield > max_shield: max_shield = current_shield
		if current_hp > max_hp: max_hp = current_hp
	
	# v186.16: Sincronía de Resurrección Crítica
	if data.has("isDead"):
		var dead_on_server = bool(data.isDead)
		if is_dead and not dead_on_server:
			is_dead = false
			visible = true; show(); modulate.a = 1.0
			set_physics_process(true); set_process(true)
		elif not is_dead and dead_on_server:
			die()
	elif current_hp > 0 and is_dead:
		is_dead = false; visible = true; show()
		set_physics_process(true); set_process(true)
	
	# v166.75: Capado de Seguridad (No exceder máximos sincronizados)
	current_hp = min(current_hp, max_hp)
	current_shield = min(current_shield, max_shield)
	
	var new_total = current_hp + current_shield
	var damage_taken = old_total - new_total
	
	if damage_taken >= 1.0 and old_total > 0: 
		reset_combat_timer() # v191.80: Restaurado nombre correcto
		if not is_in_group("player"):
			_spawn_damage_text(str(int(damage_taken)), Color.RED)
	
	var t = int(data.get("type", entity_type))
	if t != entity_type: entity_type = t; _adjust_visuals(t)
	_update_tags()

func _update_tags():
	if name_tag:
		name_tag.add_theme_font_size_override("font_size", 13)
		name_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		name_tag.add_theme_constant_override("outline_size", 4)
		if name_tag is RichTextLabel:
			var txt = "[center][b]" + username + "[/b]\n"
			txt += "[color=#00ffff][font_size=10]SH: " + str(int(current_shield)) + " / " + str(int(max_shield)) + "[/font_size][/color]\n"
			txt += "[color=#00ff00][font_size=10]HP: " + str(int(current_hp)) + " / " + str(int(max_hp)) + "[/font_size][/color][/center]"
			name_tag.text = txt
		else: name_tag.text = username + "\nSH: " + str(int(current_shield)) + " / " + str(int(max_shield)) + "\nHP: " + str(int(current_hp)) + " / " + str(int(max_hp))
	if _ui_wrapper: _ui_wrapper.queue_redraw()

func take_damage(amt: float):
	if is_god or is_dead: return
	reset_combat_timer() # Bloqueo local de regen
	if current_shield >= amt: current_shield -= amt
	else:
		var d = amt - current_shield
		current_hp -= d; current_shield = 0
	_spawn_damage_text(str(int(amt)), Color.RED)
	_update_tags()
	if is_in_group("player") and has_method("_emit_stats"):
		call("_emit_stats") # v164.72: Actualizar HUD local instantáneamente
	if current_hp <= 0: die()

func _spawn_damage_text(txt: String, clr: Color):
	var dt_script = load("res://scripts/ui/DamageText.gd")
	if dt_script:
		var dt = Marker2D.new(); dt.set_script(dt_script); dt.global_position = global_position + Vector2(0, -60)
		get_tree().root.add_child(dt); if dt.has_method("setup"): dt.setup(txt, clr)

func die():
	is_dead = true; visible = false; queue_redraw()
	if _ui_wrapper: _ui_wrapper.visible = false
	set_physics_process(false); set_process(false)
	# v186.26: No borrar naves de jugadores remotos al morir, solo ocultar (Sincronía Crítica)
	if not is_in_group("player") and not is_in_group("remote_players"): 
		queue_free()

func _adjust_visuals(_type): pass

# v165.80: Sistema de Burbujas Apiladas (Frame Stacking)
func show_bubble(p_text: String):
	# Subir los mensajes anteriores para dejar espacio al nuevo
	for child in get_children():
		if child.has_meta("is_chat_bubble"):
			var shift_tw = create_tween().set_parallel(true)
			shift_tw.tween_property(child, "global_position:y", child.global_position.y - 35, 0.25)
			# Los mensajes viejos duran menos conforme suben
			shift_tw.tween_property(child, "modulate:a", child.modulate.a * 0.7, 0.25)

	var bubble = Label.new()
	bubble.text = p_text
	bubble.set_meta("is_chat_bubble", true)
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.custom_minimum_size = Vector2(80, 20)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.border_width_left = 1; style.border_width_top = 1
	style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = Color(0, 1, 1, 0.8) 
	style.set_corner_radius_all(4)
	style.content_margin_left = 8; style.content_margin_right = 8
	style.content_margin_top = 4; style.content_margin_bottom = 4
	
	bubble.add_theme_stylebox_override("normal", style)
	bubble.add_theme_font_size_override("font_size", 10) # v165.81: Fuente levemente más chica para apilado pro
	bubble.add_theme_color_override("font_shadow_color", Color.BLACK)
	
	add_child(bubble)
	bubble.z_index = 10
	bubble.top_level = true
	# Posición base de inicio
	bubble.global_position = global_position + Vector2(-bubble.size.x / 2.0, -110)
	
	# Animación y Autodestrucción Segura (Fix Lambda Error v165.85)
	var tw = create_tween()
	tw.tween_property(bubble, "global_position:y", bubble.global_position.y - 20, 0.5) # Subida inicial suave
	tw.tween_interval(3.5)
	tw.tween_property(bubble, "modulate:a", 0.0, 1.0)
	tw.finished.connect(bubble.queue_free) # Conexión directa y segura

func _setup_ship_visuals():
	# v191.60: CARGA SEGURA CON FALLBACK (PNG -> JPEG)
	var poly = get_node_or_null("Polygon2D")
	if poly: poly.visible = false
	
	sprite = Sprite2D.new()
	sprite.name = "ShipSprite"
	
	var path_png = "res://assets/player/Nave1.png"
	var path_jpg = "res://assets/player/Nave1.jpeg"
	
	if ResourceLoader.exists(path_png):
		sprite.texture = load(path_png)
		sprite.hframes = 8
		sprite.vframes = 4
	elif ResourceLoader.exists(path_jpg):
		# v191.61: Fallback a JPEG si el PNG no se importó aún
		sprite.texture = load(path_jpg)
		sprite.hframes = 8
		sprite.vframes = 4
	
	sprite.scale = Vector2(0.5, 0.5)
	sprite.rotation_degrees = 0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	
	anim_player = AnimationPlayer.new()
	add_child(anim_player)
	var lib = AnimationLibrary.new()
	anim_player.add_animation_library("", lib)
	
	# 1. IDLE (Bucle suave en fila 1)
	var anim_idle = Animation.new()
	var track_idx = anim_idle.add_track(Animation.TYPE_VALUE)
	anim_idle.track_set_path(track_idx, "ShipSprite:frame")
	for i in range(6): anim_idle.track_insert_key(track_idx, i * 0.15, i)
	anim_idle.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("idle", anim_idle)
	
	# 2. START_MOVE (Aceleración - Fila 2, frames 8-10)
	var anim_start = Animation.new()
	track_idx = anim_start.add_track(Animation.TYPE_VALUE)
	anim_start.track_set_path(track_idx, "ShipSprite:frame")
	for i in range(3): anim_start.track_insert_key(track_idx, i * 0.08, 8 + i)
	lib.add_animation("start_move", anim_start)
	
	# 3. RUN (Vuelo - Fila 2, frames 11-13)
	var anim_run = Animation.new()
	track_idx = anim_run.add_track(Animation.TYPE_VALUE)
	anim_run.track_set_path(track_idx, "ShipSprite:frame")
	for i in range(3): anim_run.track_insert_key(track_idx, i * 0.1, 11 + i)
	anim_run.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("run", anim_run)

	# 4. DEATH (Explosión - Fila 3 y 4)
	var anim_death = Animation.new()
	track_idx = anim_death.add_track(Animation.TYPE_VALUE)
	anim_death.track_set_path(track_idx, "ShipSprite:frame")
	for i in range(16): anim_death.track_insert_key(track_idx, i * 0.08, 16 + i)
	lib.add_animation("death", anim_death)

	anim_player.play("idle")

func _setup_enemy_visuals(): pass

func _update_animations():
	if not anim_player or not is_instance_valid(sprite): return
	if is_dead: return
		
	var vel_len = velocity.length()
	
	# v191.55: REPOSO ABSOLUTO (Frame 0 fijo)
	if vel_len < 5.0:
		if anim_player.is_playing(): anim_player.stop()
		sprite.frame = 0
		return

	if vel_len > 40.0:
		if not anim_player.is_playing() or anim_player.current_animation == "idle":
			anim_player.play("start_move")
			if anim_player.is_playing() and anim_player.current_animation == "start_move":
				await anim_player.animation_finished
			if velocity.length() > 40.0: anim_player.play("run")
	else:
		if anim_player.current_animation != "idle": anim_player.play("idle")
