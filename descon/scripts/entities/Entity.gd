extends CharacterBody2D
class_name Entity

# Entity.gd (v150.20 - Non-Triangular Xeno Engine)
# Eliminación Absoluta de Triángulos en Enemigos. Siluetas Geométricas Puras.

var entity_id: String = ""
var db_id: String = "" # v243.80: Identidad persistente (MongoDB ID)
var username: String = "Unknown"
var entity_type: int = 1
var clan_tag: String = "" # v244.110: Siglas de Flota

var max_hp: float = 3000; var is_rage: bool = false # v238.70: Modo Furia (ex-Ryze)

var current_hp: float = 3000
var max_shield: float = 1000; var current_shield: float = 1000
var _display_hp: float = 3000 # v190.85: Interpolación visual de vida
var _display_shield: float = 1000 # v190.85: Interpolación visual de escudo
var hp_regen: float = 5.0; var sh_regen: float = 15.0
var current_ship_id: int = 1
var target_position: Vector2 = Vector2.ZERO
var target_rotation: float = 0.0

var is_dead: bool = false
var is_god: bool = false
var last_combat_time: float = 0

@onready var name_tag = get_node_or_null("NameTag")
var _ui_wrapper: Node2D = null
var sprite: Sprite2D = null
var anim_player: AnimationPlayer = null

# v219.95: SISTEMA DE FÍSICAS 3D DINÁMICAS
var _3d_model: Node3D = null
var world_root_3d: Node3D = null
var accessory_pivot_3d: Node3D = null
var _3d_spheres: Array = [null, null, null, null]
var _spheres_angle: float = 0.0
var _last_rot2d: float = 0.0
var _bank_target: float = 0.0
var _bank_current: float = 0.0
var _ship_rot_mem: Dictionary = {}
var pvp_status: bool = false
var reflect_timer: float = 0.0
var shield_visual_timer: float = 0.0
var heal_visual_timer: float = 0.0
var invulnerable_timer: float = 0.0
var is_invulnerable: bool = false # v2.7: Sincronía autoritativa
 # v2.5: Visual de Invulnerabilidad (Amarillo)
var _reflect_aura: Sprite2D = null
var _3d_shield_mesh: MeshInstance3D = null
var _collision_shape: CollisionShape2D = null
var _hit_flash_material: ShaderMaterial = null
var _hit_flash_material_3d: StandardMaterial3D = null
var _cached_viewport: SubViewport = null # Cache para frustum culling

func _ready():
	add_to_group("entities")
	motion_mode = MOTION_MODE_FLOATING 
	safe_margin = 0.5 # v235.99: Margen de seguridad aumentado para evitar 'pegamento'


	
	# v235.56: Inicialización Universal de Esferas
	var sm_script = load("res://scripts/systems/SpheresManager.gd")
	if sm_script:
		var sm = sm_script.new()
		sm.name = "SpheresManager"
		add_child(sm)
		sm.spheres_updated.connect(_update_3d_spheres)

	z_index = 1 # v166.60: Por encima de las estrellas
	visible = true; show()
	target_position = global_position
	target_rotation = rotation
	
	_collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 25.0 
	_collision_shape.shape = circle
	add_child(_collision_shape)
	
	print("[BATTLE] Colisión normalizada: ", name)

	var junk = ["HealthBar", "ShieldBar", "HP", "SH", "Health", "Shield"]
	for j in junk:
		var n = get_node_or_null(j)
		if n: n.visible = false; n.queue_free()
	
	if not _ui_wrapper:
		# v300.30: El HUD ahora es un componente independiente (EntityHUD.gd)
		var hud_script = load("res://scripts/entities/EntityHUD.gd")
		if hud_script:
			_ui_wrapper = hud_script.new()
			_ui_wrapper.setup(self)
			_ui_wrapper.top_level = true
			_ui_wrapper.name = "HUD_Layer_Final"
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
	
	# v235.36: Sincronía Visual de Habilidades
	if NetworkManager.has_signal("remote_skill_used"):
		NetworkManager.remote_skill_used.connect(_on_remote_skill_used)


var last_draw_hp: float = -1.0
var last_draw_sh: float = -1.0
var sync_lock_timer: float = 0.0
var is_teleporting: bool = false # v3.1: Bloquear interpolación en saltos instantáneos

func activate_sync_lock(duration: float = 2.5):
	sync_lock_timer = duration
	print("[NET] Bloqueo de Sincronía activado por ", duration, "s")

# v3.2: Teletransporte Autoritativo Instantáneo (Anti-Lerp)
func teleport_to(new_pos: Vector2):
	is_teleporting = true
	# 1. Ocultar ANTES de mover para que no se vea ningún frame de tránsito
	modulate.a = 0.0
	if is_instance_valid(_3d_model): _3d_model.visible = false
	if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = false
	# 2. Teletransporte instantáneo (ambos valores)
	global_position = new_pos
	target_position = new_pos
	# 3. Re-aparecer después de 2 frames (tiempo suficiente para que el render procese)
	get_tree().create_timer(0.05).timeout.connect(func():
		if not is_instance_valid(self): return
		modulate.a = 1.0
		if is_instance_valid(_3d_model): _3d_model.visible = true
		if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = true
		get_tree().create_timer(0.45).timeout.connect(func(): 
			if is_instance_valid(self): is_teleporting = false
		)
	)

func _process(delta):
	if reflect_timer > 0:
		reflect_timer -= delta
	
	if sync_lock_timer > 0:
		sync_lock_timer -= delta
	
	_update_reflect_aura(delta)
	_update_3d_shield(delta)
	_update_hit_flash(delta)
	
	if is_dead:
		if _ui_wrapper: _ui_wrapper.visible = false
		if _reflect_aura: _reflect_aura.visible = false
		visible = false; return
	
	visible = true; show()
	if _ui_wrapper: _ui_wrapper.visible = true
	
	# v219.65: Redibujado Inteligente (Interpolación v190.85)
	_display_hp = lerp(_display_hp, current_hp, 0.1)
	_display_shield = lerp(_display_shield, current_shield, 0.1)
	
	if abs(_display_hp - last_draw_hp) > 0.05 or abs(_display_shield - last_draw_sh) > 0.05:
		queue_redraw()
		if _ui_wrapper: _ui_wrapper.queue_redraw()
		last_draw_hp = _display_hp
		last_draw_sh = _display_shield
	
	# v220.30: INTERPOLACIÓN DE MOVIMIENTO (Para fluidez en naves remotas/enemigos)
	if not is_in_group("player") and not is_teleporting:
		# Deslizamiento suave de posición (Lerp 20% por frame)
		global_position = global_position.lerp(target_position, 0.2)
		# Suavizado de rotación (Lerp_angle evita saltos de 0 a 360)
		rotation = lerp_angle(rotation, target_rotation, 0.2)
	
	_update_animations()

	# OPTIMIZACIÓN: Pausar SubViewport de entidades fuera de pantalla
	if _cached_viewport:
		var cam = get_viewport().get_camera_2d()
		var screen_visible = true
		if cam:
			var screen_size = get_viewport_rect().size
			var cam_pos = cam.global_position
			var margin = 600.0
			var diff = global_position - cam_pos
			if abs(diff.x) > (screen_size.x / 2.0 + margin) or abs(diff.y) > (screen_size.y / 2.0 + margin):
				screen_visible = false
		if screen_visible:
			_cached_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		else:
			_cached_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	# v219.98: FÍSICAS 3D DINÁMICAS (BANKING + BOBBING + ÓRBITA)
	if is_instance_valid(_3d_model):
		# 1. BALANCEO (BOBBING)
		_3d_model.position.y = sin(Time.get_ticks_msec() * 0.002) * 0.12
		
		# 2. CÁLCULO DE INCLINACIÓN (BANKING)
		var rot_diff = angle_difference(_last_rot2d, rotation)
		_bank_target = clamp(rot_diff * 25.0, -0.7, 0.7)
		_bank_current = lerp(_bank_current, _bank_target, 0.1)
		
		# 3. ROTACIÓN DE LA NAVE (v254.60: Revertido a original por pedido del usuario)
		var target_yaw = -rotation
		_3d_model.rotation.y = lerp_angle(_3d_model.rotation.y, target_yaw, 0.2)
		_3d_model.rotation.x = abs(_bank_current) * 0.12
		_3d_model.rotation.z = -_bank_current * 0.4
		
		# 4. ACTUALIZAR ÓRBITA DE ESFERAS (Sincronización suave + Inventario)
		_spheres_angle += delta * 0.3 
		var is_auth = username == "Unknown" or username == ""
		
		# Buscamos el manager de esferas para saber qué está equipado
		var manager = get_node_or_null("SpheresManager")
		
		for i in range(4):
			var s_node = _3d_spheres[i]
			if is_instance_valid(s_node):
				# Radio 2.3 local (Phoenix)
				var r = 2.3
				var s_angle = _spheres_angle + (i * TAU / 4.0)
				
				# POSICIONAMIENTO 3D DINÁMICO
				var target_x = cos(s_angle) * r
				var target_z = sin(s_angle) * r
				# Efecto "Subibaja" (Levitación independiente y desfasada)
				var bobbing = sin(Time.get_ticks_msec() * 0.002 + i * 2.0) * 0.4
				
				s_node.position = Vector3(target_x, bobbing, target_z)
				
				var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.005 + i) * 0.1
				s_node.scale = Vector3(0.6, 0.6, 0.6) * pulse
				
				# LÓGICA DE EQUIPAMIENTO:
				var is_equipped = true # Por defecto visible (enemigos/NPCs)
				if manager and "spheres_data" in manager:
					if i < manager.spheres_data.size():
						is_equipped = manager.spheres_data[i]["equipped"] != null
					else:
						is_equipped = false # Si no existe la configuración para esta esfera, no se muestra
				
				s_node.visible = visible and not is_auth and is_equipped
		
		# --- MODO INSPECCIÓN (Rotación manual con Numpad) ---
		# v220.71: Solo permitir rotación en jugador local y persistir en memoria RAM
		var actual_model = _3d_model.get_child(0) if _3d_model.get_child_count() > 0 else null
		if is_instance_valid(actual_model) and is_in_group("player"):
			# Si no hay memoria para esta nave, tomar el valor actual como punto de partida
			if not _ship_rot_mem.has(current_ship_id):
				_ship_rot_mem[current_ship_id] = actual_model.rotation_degrees
			
			var m_rot = _ship_rot_mem[current_ship_id]
			if Input.is_key_pressed(KEY_KP_1): m_rot.x += 1
			if Input.is_key_pressed(KEY_KP_2): m_rot.x -= 1
			if Input.is_key_pressed(KEY_KP_4): m_rot.y += 1
			if Input.is_key_pressed(KEY_KP_5): m_rot.y -= 1
			if Input.is_key_pressed(KEY_KP_7): m_rot.z += 1
			if Input.is_key_pressed(KEY_KP_8): m_rot.z -= 1
			
			_ship_rot_mem[current_ship_id] = m_rot
			actual_model.rotation_degrees = m_rot
			
		# v235.69: Rotación de accesorios (Esferas)
		if is_instance_valid(accessory_pivot_3d):
			accessory_pivot_3d.rotate_y(delta * 2.0)
		
		# Sincronización de visibilidad y anti-rotación del Sprite2D
		if is_instance_valid(sprite):
			sprite.rotation = -rotation
			sprite.visible = visible
			
		_last_rot2d = rotation
	
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
		if name_tag: 
			var y_offset = -145.0
			if is_in_group("player"): y_offset = -180.0
			elif entity_type >= 4: y_offset = -300.0 # Bosses (v238.80: Espacio para 3 líneas de texto)

			name_tag.position.y = y_offset
			if name_tag.size.x > 0:
				name_tag.position.x = -(name_tag.size.x / 2.0)
		
		# v165.75: Las burbujas ahora son hijos de _ui_wrapper, por lo que siguen 
		# la posición global automáticamente sin heredar rotación.

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
		1: # Enemigo 1
			poly_color = Color(1, 0.45, 0) 
			pts = PackedVector2Array([Vector2(12, 12), Vector2(-12, 12), Vector2(-12, -12), Vector2(12, -12)])
		6: # Enemigo 6 (Vértice)
			poly_color = Color(0, 0.5, 1)
			pts = PackedVector2Array([Vector2(20, 0), Vector2(14, -14), Vector2(0, -20), Vector2(-14, -14), Vector2(-20, 0), Vector2(-14, 14), Vector2(0, 20), Vector2(14, 14)])
		8: # Enemigo 8 (Charger)
			poly_color = Color(1, 0.8, 0)
			pts = PackedVector2Array([Vector2(15, -8), Vector2(15, 8), Vector2(0, 18), Vector2(-15, 8), Vector2(-15, -8), Vector2(0, -18)])
		4: # Lord Titán
			poly_color = Color(1, 0, 0.5)
			pts = PackedVector2Array([Vector2(25, -12), Vector2(25, 12), Vector2(12, 25), Vector2(-12, 25), Vector2(-25, 12), Vector2(-25, -12), Vector2(-12, -25), Vector2(12, -25)])
		10: # Ancient Boss
			poly_color = Color(1, 0, 0)
			pts = PackedVector2Array([Vector2(35, 0), Vector2(8, -8), Vector2(0, -35), Vector2(-8, -8), Vector2(-35, 0), Vector2(-8, 8), Vector2(0, 35), Vector2(8, 8)])
		11: # Mechanic Boss
			poly_color = Color(0.7, 0, 1)
			pts = PackedVector2Array([Vector2(60, 0), Vector2(20, -50), Vector2(-40, -40), Vector2(-60, 0), Vector2(-40, 40), Vector2(20, 50)])
		5: # Enemigo 5
			poly_color = Color(0.5, 1, 0)
			pts = PackedVector2Array([Vector2(18, 0), Vector2(0, -18), Vector2(-18, 0), Vector2(0, 18)])
		_: # Otros / Genéricos (Pentágono Cyan)
			poly_color = Color(0, 1, 1)
			pts = PackedVector2Array([Vector2(15, 0), Vector2(5, -15), Vector2(-15, -10), Vector2(-15, 10), Vector2(5, 15)])
	
	draw_colored_polygon(pts, poly_color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.8)

# v300.30: HUD delegado a EntityHUD.gd


	

func reset_combat_timer():
	last_combat_time = Time.get_ticks_msec()

func update_stats(data):
	if data.has("id"): entity_id = str(data.id)
	var raw = data.get("username", data.get("user", data.get("name", null)))
	if raw != null and str(raw) != "" and str(raw) != "Unknown": 
		username = str(raw)
	
	if data.has("clanTag"):
		clan_tag = str(data.clanTag)
	if data.has("clanId"):
		set("clanId", data.clanId) # v245.92: Mantener ID para filtros de Minimap

	
	if data.has("pvpEnabled") and name_tag:
		pvp_status = !!data.pvpEnabled

	
	# v164.94: Sincronía de Popups de Daño (Antes de pisar los valores)
	var old_total = current_hp + current_shield
	
	# v191.70: PREDICCIÓN DE CLIENTE ANTI-PARPADEO (Shield/HP Stability)
	# Si somos el jugador local, ignoramos cambios minúsculos del server (Regen vs Latencia)
	# Si somos el jugador local, ignoramos cambios minúsculos del server (Regen vs Latencia)
	var is_local = is_in_group("player")
	var threshold = max(25.0, max_hp * 0.02) # v240.69: Umbral dinámico para naves de alto HP
	var lock_active = (is_local and sync_lock_timer > 0)
	
	if data.has("isInvulnerable"):
		is_invulnerable = bool(data.isInvulnerable)
		if is_invulnerable: invulnerable_timer = 2.0
	
	if data.has("hp") and not lock_active:
		var server_hp = float(data.get("hp", current_hp))
		if not is_local or abs(current_hp - server_hp) > threshold:
			current_hp = server_hp
			
	if (data.has("shield") or data.has("sh")) and not lock_active:
		var server_sh = float(data.get("shield", data.get("sh", current_shield)))
		if not is_local or abs(current_shield - server_sh) > threshold:
			current_shield = server_sh
			
	if data.has("maxHp"): 
		max_hp = float(data.get("maxHp", max_hp))
	if (data.has("maxShield") or data.has("maxSh")):
		max_shield = float(data.get("maxShield", data.get("maxSh", max_shield)))
	
	if data.has("currentShipId") and not is_in_group("enemies"):
		var sid = int(data.currentShipId)
		if sid != current_ship_id:
			current_ship_id = sid
			# v210.160: Limpieza RADICAL de equipo al cambiar de nave para evitar polución visual
			_clear_all_equipment_visuals()
			_setup_ship_visuals()
		
	# v210.131: Sincronía de Equipamiento Visual (Reflejar en el sprite/HUD)
	if data.has("equipped"):
		var new_eq = data.equipped
		if typeof(new_eq) == TYPE_DICTIONARY:
			# Si somos el jugador local, ya tenemos 'equipped' vinculado, solo recalculamos
			# Si somos remoto, actualizamos el diccionario local
			if !is_in_group("player"):
				if self.has_method("set"): self.set("equipped", new_eq)
			
			if self.has_method("_recalculate_stats"):
				self.call("_recalculate_stats")

	# v3.5: Sincronía de Invisibilidad (STEALTH)
	if data.has("isInvisible"):
		_update_invisibility_visuals(bool(data.isInvisible))

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
	
	# v240.69: Solo emitir daño visual en el sync si es un daño no predicho GRANDE (Evitar falsos sangrados por regen)
	if damage_taken >= max(10.0, max_hp * 0.05) and old_total > 0: 
		# No reseteamos el combat_timer aquí porque el ataque real ya lo reseteó en take_damage
		_spawn_damage_text(str(int(damage_taken)), Color.RED)
	
	if data.has("spheres"):
		var sm = get_node_or_null("SpheresManager")
		if is_instance_valid(sm):
			var sps = data.spheres
			if typeof(sps) == TYPE_ARRAY:
				for i in range(min(sps.size(), 4)):
					var s_data = sps[i]
					var new_skill = s_data.get("equipped") if s_data else null
					# Evitar spam de recarga si el slot no cambió
					var current = sm.spheres_data[i]["equipped"]
					var needs_update = false
					
					if new_skill == null and current != null: needs_update = true
					elif new_skill != null and current == null: needs_update = true
					elif new_skill != null and current != null:
						var n_name = new_skill.get("skill_name", "") if typeof(new_skill) == TYPE_DICTIONARY else new_skill.get("skill_name")
						var c_name = current.skill_name
						if n_name != c_name: needs_update = true
						
					if needs_update:
						sm.equip_item(i, new_skill)
		
	if data.has("isRage") or data.has("isRyze"):
		is_rage = bool(data.get("isRage", data.get("isRyze", false)))
		
	if data.has("type"):
		var t = int(data.type)
		# v224.30: Forzar recarga si el tipo cambió O si el 3D falló (polígono rosa visible)
		if t != entity_type or not is_instance_valid(_3d_model): 
			entity_type = t
			_adjust_visuals(t)
			
	# Forzar regenerar el tag para enemigos si estamos en local y somos T1/T4 etc
	_update_tags()

func _update_tags():
	if name_tag and not name_tag is RichTextLabel:
		var rtl = RichTextLabel.new()
		rtl.name = name_tag.name
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rtl.bbcode_enabled = true
		rtl.scroll_active = false
		rtl.clip_contents = false
		rtl.fit_content = true
		rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		
		var parent = name_tag.get_parent()
		if parent:
			parent.add_child(rtl)
			rtl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			rtl.grow_horizontal = Control.GROW_DIRECTION_BOTH
			rtl.grow_vertical = Control.GROW_DIRECTION_BOTH
			name_tag.queue_free()
			name_tag = rtl
			
	if name_tag:
		name_tag.add_theme_font_size_override("normal_font_size", 13)
		name_tag.add_theme_font_size_override("bold_font_size", 13)
		name_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		name_tag.add_theme_constant_override("outline_size", 4)
		if name_tag is RichTextLabel:
			name_tag.bbcode_enabled = true
			var n_color = "#bf00ff" if is_rage else ("#ff3333" if pvp_status else "#ffffff")
			var txt = "[center]"
			
			# v244.110: Mostrar TAG de Flota con color según relación
			var name_str = username
			if clan_tag != "":
				var local_player = get_tree().get_first_node_in_group("player")
				var my_tag = ""
				if is_instance_valid(local_player) and "clan_tag" in local_player:
					my_tag = local_player.clan_tag.strip_edges()
				
				var tag_color = "#ffff00" # Amarillo = neutral/desconocido
				if my_tag != "" and my_tag.to_lower() == clan_tag.strip_edges().to_lower():
					tag_color = "#00ff44" # Verde = aliado (mismo clan)
				# Futuro: elif is_enemy_clan(clan_tag): tag_color = "#ff3333"
				
				name_str = "[b][color=" + tag_color + "][" + clan_tag + "][/color][/b] " + username
			
			if is_rage: txt += "[b][wave amp=50 freq=2][color=" + n_color + "]" + name_str + "[/color][/wave][/b]\n"
			else: txt += "[b][color=" + n_color + "]" + name_str + "[/color][/b]\n"
			
			txt += "[color=#00ffff][font_size=10]SH: " + str(int(current_shield)) + " / " + str(int(max_shield)) + "[/font_size][/color]\n"
			txt += "[color=#00ff00][font_size=10]HP: " + str(int(current_hp)) + " / " + str(int(max_hp)) + "[/font_size][/color][/center]"
			name_tag.text = txt
		else: 
			# Caso Label normal: sin BBCode, color plano
			var name_str = username
			if clan_tag != "": name_str = "[" + clan_tag + "] " + username
			name_tag.text = name_str + "\nSH: " + str(int(current_shield)) + " / " + str(int(max_shield)) + "\nHP: " + str(int(current_hp)) + " / " + str(int(max_hp))
			if is_rage:
				name_tag.add_theme_color_override("font_outline_color", Color(0.75, 0, 1)) # Borde Violeta
				name_tag.add_theme_constant_override("outline_size", 10) # Borde grueso para que se vea
			else:
				name_tag.add_theme_color_override("font_outline_color", Color.BLACK)
				name_tag.add_theme_constant_override("outline_size", 4)


	if _ui_wrapper: _ui_wrapper.queue_redraw()

func take_damage(amt: float, attacker_pos: Vector2 = Vector2.ZERO, attacker_id: String = ""):
	# v235.23: DEBUG LOGS (Para diagnosticar daño 0)
	if is_in_group("player"):
		print("[BATTLE-IN] Recibiendo: ", amt, " de ", attacker_id if attacker_id != "" else "Desconocido")
	
	if invulnerable_timer > 0:
		amt = 0 # v2.6: Feedback visual de daño bloqueado (0 en rojo)
	
	# v235.20: REFLEJO TOTAL (Prioridad absoluta sobre invulnerabildiad)
	if reflect_timer > 0:
		var r_amt = int(amt * 0.8)
		if r_amt < 1: r_amt = 1
		
		# 1. VISUAL: Garantizar efecto
		var target_node = null
		if attacker_id != "":
			for ent in get_tree().get_nodes_in_group("entities"):
				if str(ent.get("entity_id")) == attacker_id:
					target_node = ent; break
		
		var visual_target = attacker_pos
		if visual_target == Vector2.ZERO and target_node: visual_target = target_node.global_position
		_trigger_reflect_visual(visual_target if visual_target != Vector2.ZERO else global_position + Vector2.UP)

		# 2. DAÑO: Notificación Red (Obligatorio) + Aplicación Local (Si existe el nodo)
		if is_in_group("player") and attacker_id != "" and attacker_id != entity_id:
			# Siempre notificar al servidor
			if NetworkManager:
				if target_node and is_instance_valid(target_node) and target_node.is_in_group("remote_players"):
					NetworkManager.send_event("playerHitByPlayer", {"victimId": attacker_id, "damage": r_amt})
				else:
					# Por defecto PvE si no es un jugador remoto conocido
					NetworkManager.send_event("enemyHit", {"enemyId": attacker_id, "damage": r_amt})
				print("[REFLECT-OUT] Devolviendo: ", r_amt, " a ", attacker_id)
			
			# Aplicar localmente solo para feedback visual inmediato
			if target_node and is_instance_valid(target_node) and target_node.has_method("take_damage"):
				target_node.take_damage(r_amt, global_position, entity_id)


	if is_god or is_dead: return
	reset_combat_timer() # Bloqueo local de regen
	
	# v235.31: Daño Local (Visual) para TODOS (incluyendo player)
	if current_shield >= amt: current_shield -= amt
	else:
		var d = amt - current_shield
		current_hp -= d; current_shield = 0

	_spawn_damage_text(str(int(amt)), Color.RED)
	_trigger_hit_flash()

	_update_tags()
	if is_in_group("player") and has_method("_emit_stats"):
		call("_emit_stats") # v164.72: Actualizar HUD local instantáneamente
	if current_hp <= 0: die()

func _trigger_reflect_visual(p_dest: Vector2):

	var spr = Sprite2D.new()
	var path = "res://assets/Efectos de Skills/Reflect (Rojo)/Reflect (Transp).png"
	if ResourceLoader.exists(path):
		spr.texture = load(path)
		spr.top_level = true
		spr.z_index = 101
		
		# v235.11: Dirección del rebote
		var dir_to_target = (p_dest - global_position).normalized()
		if dir_to_target.length() < 0.1: dir_to_target = Vector2.UP
		
		spr.global_position = global_position + dir_to_target * 35.0
		# v235.12: Quitamos el offset para que no salga de costado
		spr.rotation = dir_to_target.angle()
		
		spr.scale = Vector2(0.01, 0.01)
		spr.modulate = Color(4.0, 0.4, 0.4, 1.0)
		
		get_tree().root.add_child(spr)
		
		var tw = create_tween().set_parallel(true)
		var travel_dist = dir_to_target * 140.0
		tw.tween_property(spr, "global_position", spr.global_position + travel_dist, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "scale", Vector2(0.12, 0.12), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "modulate:a", 0.0, 0.2).set_delay(0.12)
		
		tw.finished.connect(spr.queue_free)

func _spawn_damage_text(txt: String, clr: Color):
	var dt_script = load("res://scripts/ui/DamageText.gd")
	if dt_script:
		var dt = Marker2D.new()
		dt.z_index = 100
		dt.set_script(dt_script)
		
		# v222.95: Añadir al wrapper de UI de la nave para que la SIGA
		var target_parent = _ui_wrapper if is_instance_valid(_ui_wrapper) else self
		target_parent.add_child(dt)
		
		# v222.96: Si es hijo del wrapper, la posición es relativa
		dt.position = Vector2(0, -60)
		
		if dt.has_method("setup"): dt.setup(txt, clr)

func die():
	is_dead = true
	set_physics_process(false)
	_spawn_death_vfx()
	
	# v210.180: Animación de Muerte Real
	if is_instance_valid(anim_player) and anim_player.has_animation("death"):
		anim_player.play("death")
		await anim_player.animation_finished
	
	visible = false; queue_redraw()
	if _ui_wrapper: _ui_wrapper.visible = false
	set_process(false)
	
	if not is_in_group("player") and not is_in_group("remote_players"): 
		set_meta("is_pooled", true)
		if _collision_shape: _collision_shape.set_deferred("disabled", true)

func _adjust_visuals(_type): 
	if is_in_group("enemies"):
		_setup_enemy_visuals()
		queue_redraw()

# v165.80: Sistema de Burbujas Apiladas (Frame Stacking)
func show_bubble(p_text: String):
	# Subir los mensajes anteriores para dejar espacio al nuevo
	var bubble_container = _ui_wrapper if is_instance_valid(_ui_wrapper) else self
	for child in bubble_container.get_children():
		if child.has_meta("is_chat_bubble"):
			var shift_tw = create_tween().set_parallel(true)
			shift_tw.tween_property(child, "position:y", child.position.y - 35, 0.25)
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
	
	if is_instance_valid(_ui_wrapper):
		_ui_wrapper.add_child(bubble)
	else:
		add_child(bubble)
		
	bubble.z_index = 10
	# Posición base de inicio (Relativa al wrapper que ya está en global_pos)
	bubble.position = Vector2(-bubble.size.x / 2.0, -110)
	
	# Animación y Autodestrucción Segura
	var tw = create_tween()
	tw.tween_property(bubble, "position:y", bubble.position.y - 20, 0.5) 
	tw.tween_interval(3.5)
	tw.tween_property(bubble, "modulate:a", 0.0, 1.0)
	tw.finished.connect(bubble.queue_free)

func _setup_ship_visuals():
	# Limpieza de sprite anterior si existe para evitar duplicados
	if is_instance_valid(sprite): sprite.queue_free()
	if is_instance_valid(anim_player): anim_player.queue_free()
	
	var poly = get_node_or_null("Polygon2D")
	if poly: poly.visible = false
	
	sprite = Sprite2D.new(); sprite.name = "ShipSprite"
	
	# v210.50: SELECTOR DE ASSETS DINÁMICO
	var path = ""
	var h_f = 1; var v_f = 1
	var rot_offset = 0.0 # Compensación de rotación si el asset no apunta a la derecha
	
	# v222.0: ACTIVACIÓN DE FLOTA 3D (Mapeo 1 a 6)
	var glb_path = ""
	
	match current_ship_id:
		1: glb_path = "res://assets/Personajes/3D/Nave1/futuristic+jet+3d+model_Clone1.glb"
		2: glb_path = "res://assets/Personajes/3D/Nave2/Nave2.glb"
		3: glb_path = "res://assets/Personajes/3D/Nave3/Nave3.glb"
		4: glb_path = "res://assets/Personajes/3D/Nave4/Nave4.glb"
		5: glb_path = "res://assets/Personajes/3D/Nave5/Nave5.glb"
		6: glb_path = "res://assets/Personajes/3D/Nave6/Nave6.glb"

	if glb_path != "" and ResourceLoader.exists(glb_path):
		_setup_3d_visuals(glb_path)
		
		# --- PARCHES DE ORIENTACIÓN SEGÚN EL ASSET ---
		# Buscamos el modelo real (hijo del _3d_model que es el nodo control)
		var actual_model = _3d_model.get_child(0) if _3d_model and _3d_model.get_child_count() > 0 else null
		if actual_model:
			match current_ship_id:
				3: # NAVE 3: Calibrada manualmente para estar plana y al frente
					actual_model.rotation_degrees.x = 0
					actual_model.rotation_degrees.y = 1
					actual_model.rotation_degrees.z = 98
				4: # NAVE 4: Posición perfecta lograda por calibración manual
					actual_model.rotation_degrees.x = 0
					actual_model.rotation_degrees.y = -180
					actual_model.rotation_degrees.z = 52
				6: # NAVE 6: Viene en reversa
					actual_model.rotation_degrees.y = 180
			
			# v220.72: APLICAR MEMORIA DE USUARIO (Si el piloto calibró esta nave en esta sesión)
			if _ship_rot_mem.has(current_ship_id):
				actual_model.rotation_degrees = _ship_rot_mem[current_ship_id]
		return # Salto al modo 3D pro
	
	# Mapeo 2D original (Backup)
	match current_ship_id:
		1: path = "res://assets/Personajes/2D/Nave1/Nave1 (Lista).png"
		2: 
			path = "res://assets/Personajes/2D/Nave2/Nave2 (Lista).png"
			rot_offset = 90.0
		3: 
			path = "res://assets/Personajes/2D/Nave3/Nave3.png"
			rot_offset = 90.0
		4: 
			path = "res://assets/Personajes/2D/Nave4/Nave4.png"
			rot_offset = 90.0
		5: 
			path = "res://assets/Personajes/2D/Nave5/Nave5.png"
			rot_offset = 90.0
		6: 
			path = "res://assets/Personajes/2D/Nave6/Nave6.png"
			rot_offset = 90.0
		_:
			path = "res://assets/Personajes/2D/Nave1/Nave1 (Lista).png"
	
	if path == "": return
	
	var tex = load(path)
	if tex:
		sprite.texture = tex
		sprite.hframes = h_f
		sprite.vframes = v_f
		
		# v218.10: UNIFICACIÓN DE TAMAÑOS (Target 160x160 para todas las naves)
		var frame_w = tex.get_width() / float(h_f)
		var frame_h = tex.get_height() / float(v_f)
		var target_size = 160.0
		var s = target_size / max(frame_w, frame_h)
		sprite.scale = Vector2(s, s)
		
		# v210.55: COMPENSACIÓN DE ORIENTACIÓN (Si el asset no apunta a la derecha)
		if rot_offset != 0.0:
			sprite.rotation_degrees = rot_offset
		
		# Escalar Hitbox proporcionalmente
		var col = get_node_or_null("CollisionPolygon2D")
		if is_instance_valid(col): col.scale = Vector2((target_size * 0.85)/35.0, (target_size * 0.85)/35.0)
	
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	
	# v210.40: Configuración de AnimPlayer
	anim_player = AnimationPlayer.new()
	sprite.add_child(anim_player) 
	anim_player.root_node = NodePath(".")
	
	var lib = AnimationLibrary.new()
	anim_player.add_animation_library("", lib)
	
	# Mapeo de animaciones (Si son imágenes simples de 1 frame, h_f será 1)
	if h_f == 1:
		_create_anim(lib, "idle", 0, 1, 0.15, true)
		_create_anim(lib, "start_move", 0, 1, 0.08, false) 
		_create_anim(lib, "run", 0, 1, 0.1, true)      
		_create_anim(lib, "death", 0, 1, 0.08, false) 
	elif h_f == 4: # Caso especial Vulture
		_create_anim(lib, "idle", 0, 4, 0.15, true)
		_create_anim(lib, "start_move", 4, 4, 0.08, false) 
		_create_anim(lib, "run", 8, 4, 0.1, true)      
		_create_anim(lib, "death", 12, 4, 0.08, false) 
	
	anim_player.play("idle")

func _create_anim(lib: AnimationLibrary, a_name: String, start: int, count: int, step: float, loop: bool):
	var anim = Animation.new()
	var track = anim.add_track(Animation.TYPE_VALUE)
	# v210.41: Ruta absoluta al frame del nodo raíz del AnimationPlayer
	anim.track_set_path(track, NodePath(".:frame"))
	for i in range(count): anim.track_insert_key(track, i * step, start + i)
	if loop: anim.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation(a_name, anim)

func _setup_enemy_visuals():
	var glb_path = ""
	var enemy_rot_offset = 0.0
	var enemy_scale = 3.0 
	var path = "" # v252.16: Declaración restaurada para fallback 2D
	
	# v255.15: CONFIGURACIÓN NORMALIZADA (Manual de Activos)
	match entity_type:
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13:
			glb_path = "res://assets/Enemigos/3D/Enemigo" + str(entity_type) + "/Enemigo" + str(entity_type) + ".glb"
			enemy_rot_offset = 90.0
			# Excepciones de rotación específicas detectadas en pruebas
			if entity_type == 7 or entity_type == 4: enemy_rot_offset = 180.0
			if entity_type == 6 or entity_type == 8: enemy_rot_offset = 0.0
			
		101: # Lord Titán (Boss1)
			glb_path = "res://assets/Enemigos/3D/Bosses/Boss1/Boss1.glb"
			enemy_rot_offset = 90.0
			enemy_scale = 6.0
		102: # Ancient Titán (Boss2)
			glb_path = "res://assets/Enemigos/3D/Bosses/Boss2/Boss2.glb"
			enemy_rot_offset = 90.0
			enemy_scale = 6.0
		103: # Mechanic Boss (Boss3)
			glb_path = "res://assets/Enemigos/3D/Bosses/Boss3/Boss3.glb"
			enemy_rot_offset = 180.0
			enemy_scale = 6.0

	if glb_path != "":
		print("[CORE] Cargando Enemigo 3D: ", glb_path, " Tipo: ", entity_type)
	
	# v225.40: SALTO INTELIGENTE
	if glb_path != "" and is_instance_valid(_3d_model) and is_instance_valid(sprite):
		if sprite.texture != null and get_meta("current_glb", "") == glb_path: 
			# Asegurar escala correcta incluso si el modelo se recicla
			_3d_model.scale = Vector3(enemy_scale, enemy_scale, enemy_scale)
			return

	set_meta("current_glb", glb_path)

	# Limpieza
	if is_instance_valid(sprite): sprite.queue_free(); sprite = null
	if is_instance_valid(anim_player): anim_player.queue_free()
	var poly_node = get_node_or_null("Polygon2D")
	if poly_node: poly_node.visible = false

	# Carga de Visual 3D
	if glb_path != "":
		for c in get_children():
			if "Viewport" in c.name or c is Sprite2D or c is Polygon2D or c.name == "Ship3DRender":
				c.queue_free()
		
		_setup_3d_visuals(glb_path, enemy_rot_offset)
		if is_instance_valid(_3d_model):
			_3d_model.scale = Vector3(enemy_scale, enemy_scale, enemy_scale)
			return
		else:
			print("[VISUAL-WARN] Falló carga 3D para ", username, ". Usando fallback 2D.")


	# Fallback a 2D (v223.1: Rutas Corregidas 2D)
	match entity_type:
		1: path = "res://assets/Enemigos/2D/Enemigo1/Enemy1Map1.png"
		2: path = "res://assets/Enemigos/2D/Enemigo1/Enemy1Map1.png" # Fallback a E1
		3: path = "res://assets/Enemigos/2D/Enemigo2/Enemy2Map1.png" # Fallback a E2
		5: path = "res://assets/Enemigos/2D/Enemigo2/Enemy2Map1.png"
		8: path = "res://assets/Enemigos/2D/Enemigo3/Enemy3Map1.png"
		7: path = "res://assets/Enemigos/2D/Enemigo3/Enemy3Map1.png" # Fallback a E3
		9: path = "res://assets/Enemigos/2D/Enemigo1/Enemy1Map1.png" # Fallback a E1
		4: path = "res://assets/Enemigos/2D/Bosses/Boss1/Boss1.png"
		10: path = "res://assets/Enemigos/2D/Bosses/Boss2/Boss2.png"
		11: path = "res://assets/Enemigos/2D/Bosses/Boss3/Boss3.png"
		6: path = "res://assets/Enemigos/2D/Enemigo6/Enemigo6.png"
	
	if path == "": path = "res://assets/Enemigos/2D/Enemigo1/Enemy1Map1.png"
	
	if ResourceLoader.exists(path):
		sprite = Sprite2D.new(); sprite.name = "EnemySprite"
		var tex = load(path)
		sprite.texture = tex
		
		# Bosses tienen escala monumental (320px), minions normales (160px)
		var target_size = 320.0 if entity_type >= 4 else 160.0
		
		var s = target_size / max(tex.get_width(), tex.get_height())
		sprite.scale = Vector2(s, s)
		
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(sprite)
		
		# Ajustar el Hitbox base del objeto (que mide aprox 25px de largo originalmente)
		var col = get_node_or_null("CollisionPolygon2D")
		if is_instance_valid(col):
			var factor = (target_size * 0.85) / 25.0
			col.scale = Vector2(factor, factor)
	
	# Asegurarnos de borrar toda geometria fea que este de fondo o recargar
	_update_collision_size()
	queue_redraw()

func _update_animations():
	if not anim_player or not is_instance_valid(sprite): return
	if is_dead: return
		
	var vel_len = velocity.length()
	
	# v191.55: REPOSO (Idle en bucle)
	if vel_len < 10.0:
		if anim_player.current_animation != "idle":
			anim_player.play("idle")
		return

	# v210.181: Transición Inteligente Aceleración -> Máxima
	if vel_len > 10.0:
		if anim_player.current_animation == "idle":
			anim_player.play("start_move")
		
		# Si ya terminó de arrancar, pasamos a modo Crucero (Run)
		if anim_player.current_animation == "start_move" and not anim_player.is_playing():
			anim_player.play("run")
		
		# Si nos movemos y no hay nada sonando, forzamos Run
		if anim_player.current_animation == "" or (not anim_player.is_playing() and vel_len > 100.0):
			anim_player.play("run")

# v210.161: Helper para limpiar visuales de equipo (evita duplicidad)
func _clear_all_equipment_visuals():
	# Buscar nodos de equipo bajo esta entidad y eliminarlos
	if is_instance_valid(sprite):
		for child in sprite.get_children():
			if child is Sprite2D or child is Node2D:
				# Si el nodo es de equipamiento, lo volamos
				if child.name.begins_with("Equip_") or child.is_in_group("ship_equipment"):
					child.queue_free()
	
	if is_instance_valid(_ui_wrapper):
		_ui_wrapper.queue_redraw()

func play_skill_vfx(skill_name: String, amount: float = 0.0):
	# Mostrar siempre los números de retroalimentación
	if has_method("_spawn_damage_text"):
		if skill_name == "ESCUDO CELULAR": _spawn_damage_text("+" + str(int(amount)), Color.AQUA)
		elif skill_name == "AUTO-REPARACIÓN": _spawn_damage_text("+" + str(int(amount)), Color.GREEN)
		elif skill_name == "TURBO-IMPULSO": _spawn_damage_text("+" + str(int(amount)), Color.YELLOW)
	match skill_name:
		"TURBO-IMPULSO":
			# v4.1: Aplicar velocidad real si es un jugador (Aliado o Local)
			if "speed" in self:
				var bonus = amount
				self.speed += bonus
				get_tree().create_timer(2.0).timeout.connect(func(): 
					if is_instance_valid(self): self.speed -= bonus
				)
				
			var path = "res://assets/Efectos de Skills/Velocidad(Transp).png"
			if ResourceLoader.exists(path):
				var vfx = Sprite2D.new(); var t = load(path); vfx.texture = t
				var s = 145.0 / max(t.get_width(), t.get_height())
				vfx.scale = Vector2(s, s); vfx.rotation_degrees = 180
				vfx.position = Vector2(-65, 0)
				vfx.z_index = -1
				add_child(vfx)
				var tw = create_tween().set_loops()
				tw.bind_node(vfx)
				tw.tween_property(vfx, "scale", Vector2(s*1.3, s*0.8), 0.1)
				tw.tween_property(vfx, "scale", Vector2(s*0.8, s*1.3), 0.1)
				get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(vfx): vfx.queue_free())
		"ESCUDO CELULAR":
			shield_visual_timer = 2.0 # Activar visual 3D pro
			# v260.20: Se eliminó el Sprite2D viejo para limpiar la visual 3D

		"AUTO-REPARACIÓN":
			heal_visual_timer = 2.0 # Activar visual 3D pro de curación
			# v260.30: Se eliminó el Sprite2D de curación en favor del efecto 3D
		
		"SMOKE-BOMB":
			pass # La visual es gestionada por World.gd de forma global

		
		"INVULNERABILIDAD":
			invulnerable_timer = 2.0 # Activar visual 3D amarilla
			print("[SKILL] Activando visual de INVULNERABILIDAD para: ", username)
		"BLINK_OUT":
			# v3.2: Desaparición TOTAL e INSTANTÁNEA (sin VFX expansivo)
			modulate.a = 0.0
			if is_instance_valid(_3d_model): _3d_model.visible = false
			if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = false
		"BLINK_IN":
			# v3.2: Reaparición con destello puntual (sin nova expansiva)
			modulate.a = 1.0
			if is_instance_valid(_3d_model): _3d_model.visible = true
			if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = true
			# Destello blanco puntual en el destino (no expansivo)
			var tw = create_tween()
			tw.tween_property(self, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.0)
			tw.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)


# v219.70: SISTEMA DE RENDERIZADO 3D SOBRE 2D (EXPERIMENTAL)
func _setup_3d_visuals(glb_path: String, rot_offset: float = 0.0):
	print("[3D] Inicializando renderizado para: ", glb_path)
	
	# 1. Crear el contenedor del Viewport con su propio mundo 3D
	# Resolucion dinamica segun calidad grafica (SettingsManager)
	var quality = 1
	if get_node_or_null("/root/SettingsManager"):
		quality = SettingsManager.get_graphics_quality()
		
	var res = 256 # Calidad media por defecto
	if is_in_group("player") or (is_in_group("enemies") and entity_type >= 4):
		res = 512
		
	match quality:
		0: # Baja (Celulares)
			res = 128 if not is_in_group("player") else 256
		1: # Media (Recomendado)
			res = 256 if not is_in_group("player") else 512
		2: # Alta (Gama Alta - Calidad Original Máxima)
			res = 1024
			
	var viewport = SubViewport.new()
	viewport.size = Vector2i(res, res)
	viewport.transparent_bg = true
	viewport.own_world_3d = true 
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	# OPTIMIZACION MASIVA: Apagar cálculos innecesarios del motor 3D
	viewport.positional_shadow_atlas_size = 0
	if "use_hdr_3d" in viewport: viewport.use_hdr_3d = false
	if "msaa_3d" in viewport: viewport.msaa_3d = Viewport.MSAA_DISABLED
	if "screen_space_aa" in viewport: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	
	add_child(viewport)
	_cached_viewport = viewport # Cache para frustum culling
	
	# Asegurar que el sprite principal esté en la escena y configurado
	if is_instance_valid(sprite):
		if not sprite.get_parent():
			add_child(sprite)
		sprite.z_index = 10 # BIEN ARRIBA
		sprite.name = "Ship3DRender"
	else:
		sprite = Sprite2D.new()
		sprite.name = "Ship3DRender"
		sprite.z_index = 10
		add_child(sprite)
	
	# 2. Crear la escena 3D interna
	var node3d = Node3D.new()
	viewport.add_child(node3d)
	world_root_3d = node3d
	
	# PIVOTE INDEPENDIENTE (Igual que en 2D)
	accessory_pivot_3d = Node3D.new()
	accessory_pivot_3d.name = "AccessoryPivot"
	node3d.add_child(accessory_pivot_3d)
	
	# Entorno con luz AMBIENTE BLANCA (Garantía de visibilidad)
	var env = WorldEnvironment.new()
	var world_env = Environment.new()
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color.WHITE
	world_env.ambient_light_energy = 1.0 
	env.environment = world_env
	node3d.add_child(env)
	
	# Instanciar el modelo GLB
	var model_scene = load(glb_path)
	if model_scene:
		var model = model_scene.instantiate()
		
		# CREAMOS UN NODO DE CONTROL (Padre) 
		var control_node = Node3D.new()
		control_node.name = "ShipControl"
		node3d.add_child(control_node)
		control_node.add_child(model)
		
		# v252.23: INSPECTOR Y ACTIVADOR DE ANIMACIONES
		var anim_player_3d = null
		if model.has_node("AnimationPlayer"):
			anim_player_3d = model.get_node("AnimationPlayer")
		else:
			# Búsqueda recursiva simple si no está en la raíz
			for child in model.get_children():
				if child is AnimationPlayer:
					anim_player_3d = child; break
		
		if anim_player_3d:
			var anim_list = anim_player_3d.get_animation_list()
			print("[3D-ANIM] ", entity_type, " tiene ", anim_list.size(), " animaciones: ", anim_list)
			if anim_list.size() > 0:
				var target_anim = anim_list[0]
				# Priorizar nombres comunes
				for a in anim_list:
					var low = a.to_lower()
					if "idle" in low or "fly" in low or "walk" in low or "move" in low:
						target_anim = a; break
				
				anim_player_3d.play(target_anim)
				print("[3D-ANIM] Reproduciendo: ", target_anim, " en ", entity_type)
		
		_3d_model = control_node 
		control_node.scale = Vector3(3.0, 3.0, 3.0) 
		model.rotation_degrees.y = rot_offset 

		# v260.10: Inyectar Escudo de Energía 3D (Procedural)
		_3d_shield_mesh = MeshInstance3D.new()
		_3d_shield_mesh.name = "EnergyShield"
		var sphere = SphereMesh.new()
		sphere.radius = 0.55 # Ajustado para ser apenas mayor que la nave (escala 1.0 relativa al control_node)
		sphere.height = 1.1
		_3d_shield_mesh.mesh = sphere
		
		var mat = ShaderMaterial.new()
		mat.shader = load("res://resources/shaders/energy_shield.gdshader")
		_3d_shield_mesh.material_override = mat
		_3d_shield_mesh.visible = false 
		control_node.add_child(_3d_shield_mesh) # Ahora rota y escala CON la nave
	
	# 4. Cámara de Perspectiva con ZOOM 50% (Punto 0)
	var cam_pivot = Node3D.new()
	node3d.add_child(cam_pivot)
	var cam = Camera3D.new()
	cam_pivot.add_child(cam)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 60.0
	cam.position = Vector3(0, 10, 10) # v238.20: RESTORED FROM 1f65223
	cam.look_at(Vector3.ZERO)
	
	# LUZ FRONTAL (Headlight)
	var sun = DirectionalLight3D.new()
	cam.add_child(sun)
	sun.rotation = Vector3.ZERO 
	sun.light_energy = 2.0 # Volver al original suave
	sun.light_specular = 0.0 # Reducido a 0 para no calcular brillos especulares
	sun.shadow_enabled = false # Desactivar sombras direccionales obligatoriamente
	# 5. Conectar al Sprite2D existente (Transparencia Pro)
	if is_instance_valid(sprite):
		sprite.texture = viewport.get_texture()
		# Compensacion: si la resolucion bajó, agrandamos el sprite para mantener el tamaño real
		var scale_factor = 1024.0 / float(res)
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.rotation_degrees = 0
		sprite.flip_v = false 
		
		if is_in_group("player") or is_in_group("remote_players"):
			var sm = get_node_or_null("SpheresManager")
			if sm and not sm.spheres_updated.is_connected(_update_3d_spheres):
				sm.spheres_updated.connect(_update_3d_spheres)
			_update_3d_spheres()
	
	print("[3D] Visualizacion configurada correctamente.")

func _update_reflect_aura(_delta: float):
	# v260.20: Aura 2D desactivada en favor del sistema de Escudo de Energía 3D
	if _reflect_aura:
		_reflect_aura.visible = false
	return
	
func _on_remote_skill_used(data: Dictionary):
	# v235.37: Registro de uso de habilidad remota para sincronía visual
	if str(data.get("id")) == entity_id:
		var s_name = str(data.get("skillName", ""))
		if s_name == "REFLECT-Ω" or s_name == "REFLECT":
			reflect_timer = 3.0
			print("[SKILL-SYNC] Activando visual de REFLECT para aliado: ", username)
		elif s_name == "ESCUDO CELULAR" or s_name == "FORTALEZA-X":
			shield_visual_timer = 2.0
			print("[SKILL-SYNC] Activando visual de ESCUDO para aliado: ", username)
		elif s_name == "AUTO-REPARACIÓN" or s_name == "NANO-REGENERACIÓN":
			heal_visual_timer = 2.0
			print("[SKILL-SYNC] Activando visual de CURACION para aliado: ", username)
		elif "SMOKE" in s_name or "BOMBA" in s_name:
			pass # Ignorar visuales locales para bomba de humo
		elif s_name == "INVULNERABILIDAD":
			invulnerable_timer = 2.0
			print("[SKILL-SYNC] Activando visual de INVULNERABILIDAD para aliado: ", username)

func _update_3d_shield(delta: float):
	if shield_visual_timer > 0: shield_visual_timer -= delta
	if heal_visual_timer > 0: heal_visual_timer -= delta
	if invulnerable_timer > 0: invulnerable_timer -= delta
	
	if not _3d_shield_mesh: return
	
	# v260.15: Lógica de Visibilidad Híbrida (Reflect, Escudo, Cura o Inmunidad)
	var is_active = shield_visual_timer > 0 or reflect_timer > 0 or heal_visual_timer > 0 or invulnerable_timer > 0 or is_invulnerable
	_3d_shield_mesh.visible = is_active
	
	if is_active:
		var mat = _3d_shield_mesh.material_override as ShaderMaterial
		if mat:
			var color = Color(0.1, 0.5, 1.0, 1.0) # Azul (Escudo)
			var is_healing = heal_visual_timer > 0
			
			if reflect_timer > 0:
				color = Color(1.0, 0.2, 0.1, 1.0) # Rojo (Reflect)
			elif invulnerable_timer > 0 or is_invulnerable:
				color = Color(1.0, 0.9, 0.1, 1.0) # Amarillo (Invulnerabilidad)
			elif is_healing:
				color = Color(0.1, 1.0, 0.3, 1.0) # Verde (Cura)
			
			mat.set_shader_parameter("color_escudo", color)
			mat.set_shader_parameter("modo_curacion", is_healing)

func _update_3d_spheres():
	var sm = get_node_or_null("SpheresManager")
	if not sm or not accessory_pivot_3d: return
	
	# v235.90: SISTEMA DE CARGA DIRECTA INFALIBLE (Bypass de todo)
	for s in _3d_spheres:
		if is_instance_valid(s): s.queue_free()
	_3d_spheres = [null, null, null, null]
	
	for i in range(4):
		var data = sm.spheres_data[i] if i < sm.spheres_data.size() else null
		var skill = data.get("equipped") if data else null
		if not skill: continue
			
		var color_name = "Amarilla"
		var s_type = str(skill.type).to_lower()
		if s_type == "ataque": color_name = "Roja"
		elif s_type == "defensa": color_name = "Azul"
		elif s_type == "curación" or s_type == "curacion": color_name = "Verde"
		
		var s_path = "res://assets/Esferas/3D/Esfera" + color_name + "/Esfera" + color_name + ".glb"
		if ResourceLoader.exists(s_path):
			var s_scene = load(s_path).instantiate()
			accessory_pivot_3d.add_child(s_scene)
			_3d_spheres[i] = s_scene
			var a = i * (PI/2.0)
			var r = 7.0 
			s_scene.position = Vector3(cos(a)*r, 0, sin(a)*r)
			s_scene.scale = Vector3(3.0, 3.0, 3.0) 
			
			print("[FIX] Esfera cargada sin luces extra.")

func _ensure_flash_material():
	if not _hit_flash_material:
		_hit_flash_material = ShaderMaterial.new()
		_hit_flash_material.shader = load("res://resources/shaders/hit_flash.gdshader")
	if not _hit_flash_material_3d:
		_hit_flash_material_3d = StandardMaterial3D.new()
		_hit_flash_material_3d.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		_hit_flash_material_3d.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		_hit_flash_material_3d.albedo_color = Color(1, 1, 1, 0.0)
	if is_instance_valid(sprite) and not is_instance_valid(_3d_model):
		sprite.material = _hit_flash_material
	else:
		if is_instance_valid(sprite): sprite.material = null

var _flash_timer: float = 0.0
func _trigger_hit_flash():
	if get_node_or_null("/root/SettingsManager"):
		if not SettingsManager.hit_flash_enabled: return
		_flash_timer = 0.15
	_ensure_flash_material()
	_update_flash_visuals(1.0)

func _update_hit_flash(delta):
	if _flash_timer > 0:
		_flash_timer -= delta
		var intensity = clamp(_flash_timer / 0.15, 0.0, 1.0)
		_update_flash_visuals(intensity)
		if _flash_timer <= 0:
			_update_flash_visuals(0.0)

func _update_flash_visuals(p_intensity: float):
	if _hit_flash_material: _hit_flash_material.set_shader_parameter("hit_opacity", p_intensity)
	if is_instance_valid(_3d_model) and _hit_flash_material_3d:
		_hit_flash_material_3d.albedo_color.a = p_intensity * 0.4
		_apply_flash_recursive(_3d_model, _hit_flash_material_3d)

func _apply_flash_recursive(p_node, p_mat):
	if p_node is MeshInstance3D: p_node.material_overlay = p_mat
	for child in p_node.get_children(): _apply_flash_recursive(child, p_mat)

func _spawn_death_vfx():
	var vfx_script = load("res://scripts/vfx/ImpactVFX.gd")
	if vfx_script:
		var vfx = vfx_script.new()
		get_parent().add_child(vfx)
		vfx.global_position = global_position

func _update_collision_size():
	if not _collision_shape or not _collision_shape.shape is CircleShape2D: return

	var base_size = 160.0
	if is_in_group("enemies"):
		if entity_type >= 4: base_size = 320.0
		else: base_size = 160.0

	_collision_shape.shape.radius = base_size * 0.4

func _update_invisibility_visuals(invisible: bool):
	var is_local = is_in_group("player")
	var in_party = false
	var same_clan = false
	
	# v3.5: Verificar si somos del mismo grupo usando PartyManager
	var pm = get_node_or_null("/root/PartyManager")
	if pm and pm.current_party and pm.current_party.has("members"):
		for m in pm.current_party["members"]:
			if str(m.get("id", "")) == entity_id or str(m.get("socketId", "")) == entity_id:
				in_party = true
				break
				
	# v3.6: Verificar si somos del mismo clan (SOLO si ambos tienen clan válido)
	var local_player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(local_player):
		var my_tag = local_player.clan_tag.strip_edges()
		var target_tag = clan_tag.strip_edges()
		if my_tag != "" and target_tag != "" and my_tag == target_tag:
			same_clan = true

	if invisible:
		var is_ally = (is_local or in_party or same_clan)
		
		# Nave: Para aliados transparente (0.3), para el resto invisible (0.0)
		visible = true
		modulate = Color(0.5, 0.8, 1.0, 0.3) if is_ally else Color(1, 1, 1, 0)
		
		if is_instance_valid(sprite): 
			sprite.visible = true
			sprite.modulate.a = 0.5 if is_ally else 0.0
			
		# HUD y Textos: SOLO para aliados
		if is_instance_valid(name_tag): name_tag.visible = is_ally
		if is_instance_valid(_ui_wrapper): 
			_ui_wrapper.visible = is_ally
			_ui_wrapper.modulate.a = 0.7 if is_ally else 0.0
	else:
		# Estado normal
		visible = true
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		if is_instance_valid(_3d_model): _3d_model.visible = true
		if is_instance_valid(sprite): 
			sprite.visible = true
			sprite.modulate.a = 1.0
		if is_instance_valid(name_tag): name_tag.visible = true
		if is_instance_valid(_ui_wrapper): 
			_ui_wrapper.visible = true
			_ui_wrapper.modulate.a = 1.0
