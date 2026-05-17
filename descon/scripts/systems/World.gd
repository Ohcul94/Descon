extends Node2D

# World.gd (Controlador Global v200.0 - Phoenix Universal Render Modular)
# Optimización de Instanciación de Entidades y Parallax Stellar.

@onready var player_spawn = $PlayerSpawn
@onready var entities_node = $Entities
@onready var ui_hud = get_node_or_null("HUD/MainHUD")
@onready var ui_chat = get_node_or_null("HUD/ChatUI")
@onready var ui_inventory = get_node_or_null("HUD/Inventory")
@onready var ui_admin = get_node_or_null("HUD/MainHUD/AdminPanel")
@onready var local_player = $Player 
@onready var combat_system = $CombatSystem
var talent_system = null
var current_map_node = null # Referencia al mapa cargado actualmente

var entity_manager: Node = null

# Propiedades Dinámicas de Godot 4 (Backwards-compatibility de clase)
var remote_players: Dictionary:
	get: return entity_manager.remote_players if is_instance_valid(entity_manager) else {}

var enemies: Dictionary:
	get: return entity_manager.enemies if is_instance_valid(entity_manager) else {}

var save_timer = 0.0
const SAVE_INTERVAL = 10.0
var respawn_timer = 0.0

# v268.30: Variables para Interferencia
var _shake_strength = 0.0
var _is_interference_active = false

# 650 Estrellas Procesales (v73.31) - PRE-BAKED para rendimiento
var _star_sprites: Array = [] # [far, mid, near] Sprite2Ds
const WORLD_DRAW_SIZE = 4000.0

func _ready():
	add_to_group("world_node") # v164.37: Para que el ChatUI nos encuentre fácil
	
	# COMPONENTIZACIÓN: Inyección dinámica del Gestor de Entidades
	_inject_entity_manager()
	
	NetworkManager.login_success.connect(_on_login_success)
	NetworkManager.config_updated.connect(_on_admin_config_received)
	
	# Sincronización HUD
	NetworkManager.clear_zone_entities.connect(_update_hud_map_name) # v243.63
	
	talent_system = get_node_or_null("TalentSystem")
	
	if ui_hud: ui_hud.visible = false
	if ui_inventory: ui_inventory.visible = false
	if ui_admin: ui_admin.visible = false
	if ui_chat: ui_chat.visible = false
	
	_generate_stellar_data()
	
	# v267.900: Inicializar Overlays de Ambiente
	_setup_blindness_overlay()
	_setup_interference_overlay() 
	_setup_freeze_overlay() # v268.40
	NetworkManager.blindness_event.connect(_on_blindness_event)
	NetworkManager.interference_event.connect(_on_interference_event)
	NetworkManager.freeze_event.connect(_on_freeze_event) # v268.40

func _inject_entity_manager():
	entity_manager = Node.new()
	entity_manager.name = "EntityManager"
	entity_manager.set_script(load("res://scripts/systems/EntityManager.gd"))
	add_child(entity_manager)
	entity_manager.setup(self)

func _setup_freeze_overlay():
	var canvas = CanvasLayer.new()
	canvas.name = "FreezeLayer"
	canvas.layer = 89 # Por debajo de la ceguera
	add_child(canvas)
	
	var overlay = ColorRect.new()
	overlay.name = "Frost"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.8, 0.9, 1.0, 0.2) # Blanco/Celeste Hielo
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)

func _on_freeze_event(data):
	var duration = data.get("duration", 6000.0) / 1000.0
	var overlay = get_node_or_null("FreezeLayer/Frost")
	if overlay:
		overlay.visible = true
		var tw = create_tween()
		overlay.modulate.a = 0.0
		tw.tween_property(overlay, "modulate:a", 1.0, 0.5)
		
		# Aplicar Slow al jugador
		if is_instance_valid(local_player) and local_player.has_method("apply_freeze_slow"):
			local_player.apply_freeze_slow(data)
			
		await get_tree().create_timer(duration).timeout
		
		var tw_out = create_tween()
		tw_out.tween_property(overlay, "modulate:a", 0.0, 1.0)
		await tw_out.finished
		overlay.visible = false

func _setup_blindness_overlay():
	var canvas = CanvasLayer.new()
	canvas.name = "BlindnessLayer"
	canvas.layer = 90
	add_child(canvas)
	
	var overlay = ColorRect.new()
	overlay.name = "Darkness"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 1)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)
	
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
		shader_type canvas_item;
		uniform vec2 player_world_pos;
		uniform float world_radius;
		uniform vec2 view_top_left;
		uniform vec2 view_size;
		uniform float softness = 40.0; // Suavidad en unidades de mundo

		void fragment() {
			// v268.25: Calcular la posición de MUNDO de este píxel
			vec2 pixel_world_pos = view_top_left + (UV * view_size);
			
			float dist = distance(pixel_world_pos, player_world_pos);
			
			// Pulsación sutil en unidades de mundo
			float pulse = sin(TIME * 1.5) * 5.0;
			float final_radius = world_radius + pulse;
			
			// Ceguera basada en distancia real en el MAPA
			float alpha = smoothstep(final_radius, final_radius + softness, dist);
			COLOR = vec4(0.0, 0.0, 0.0, alpha);
		}
	"""
	mat.shader = shader
	overlay.material = mat

func _setup_interference_overlay():
	var canvas = CanvasLayer.new()
	canvas.name = "InterferenceLayer"
	canvas.layer = 91 # Un poquito arriba de la ceguera
	add_child(canvas)
	
	var overlay = ColorRect.new()
	overlay.name = "Static"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)
	
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
		shader_type canvas_item;
		uniform float strength = 0.0;
		uniform float time_speed = 10.0;

		float random(vec2 uv) {
			return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
		}

		void fragment() {
			vec2 uv = UV;
			float noise = random(uv + TIME * time_speed);
			float stripes = sin(uv.y * 50.0 + TIME * 20.0);
			float final_noise = mix(0.0, noise * 0.5 + stripes * 0.2, strength);
			COLOR = vec4(0.5, 0.7, 1.0, final_noise * 0.4);
		}
	"""
	mat.shader = shader
	overlay.material = mat

func _on_interference_event(data):
	var duration = data.get("duration", 4000.0) / 1000.0
	_shake_strength = data.get("shakeIntensity", 10.0)
	var static_str = data.get("staticIntensity", 0.4)
	
	var overlay = get_node_or_null("InterferenceLayer/Static")
	if overlay:
		overlay.visible = true
		overlay.material.set_shader_parameter("strength", static_str)
		_is_interference_active = true
		
		# Bloquear habilidades en el jugador local
		if is_instance_valid(local_player):
			local_player.set_meta("skills_blocked", true)
			if local_player.has_method("apply_shake"): local_player.apply_shake(1.0) # Shake inicial fuerte
		
		await get_tree().create_timer(duration).timeout
		
		_is_interference_active = false
		_shake_strength = 0.0
		overlay.visible = false
		if is_instance_valid(local_player):
			local_player.set_meta("skills_blocked", false)

func _on_blindness_event(data):
	var duration = data.get("duration", 5000.0) / 1000.0
	var radius_px = data.get("radius", 150.0)
	
	var overlay = get_node_or_null("BlindnessLayer/Darkness")
	if overlay:
		overlay.size = get_viewport().get_visible_rect().size
		overlay.set_meta("radius_px", radius_px)
		overlay.visible = true
		
		var tw = create_tween()
		overlay.modulate.a = 0.0
		tw.tween_property(overlay, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		await get_tree().create_timer(duration).timeout
		
		var tw_out = create_tween()
		tw_out.tween_property(overlay, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
		await tw_out.finished
		overlay.visible = false

func _generate_stellar_data():
	var layers = [
		{"count": 400, "radius": 1, "alpha": 0.2, "parallax": 0.1},
		{"count": 200, "radius": 2, "alpha": 0.4, "parallax": 0.3},
		{"count": 50, "radius": 3, "alpha": 0.8, "parallax": 0.6}
	]
	var tex_size = int(WORLD_DRAW_SIZE)
	for layer in layers:
		var img = Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var r = layer.radius
		var c = Color(1, 1, 1, layer.alpha)
		for i in range(layer.count):
			var sx = randi_range(r, tex_size - r - 1)
			var sy = randi_range(r, tex_size - r - 1)
			for dx in range(-r, r + 1):
				for dy in range(-r, r + 1):
					if dx*dx + dy*dy <= r*r:
						img.set_pixel(sx + dx, sy + dy, c)
		var spr = Sprite2D.new()
		spr.texture = ImageTexture.create_from_image(img)
		spr.centered = false
		spr.z_index = -10
		spr.set_meta("parallax_factor", layer.parallax)
		add_child(spr)
		_star_sprites.append(spr)

func _process(delta):
	# Parallax de estrellas
	var cam_pos = Vector2.ZERO
	if is_instance_valid(local_player): cam_pos = local_player.global_position
	for spr in _star_sprites:
		if is_instance_valid(spr):
			spr.position = cam_pos * spr.get_meta("parallax_factor")
	
	# Temblor de Cámara por interferencia
	if _is_interference_active:
		var cam = get_viewport().get_camera_2d()
		if cam:
			cam.offset = Vector2(randf_range(-_shake_strength, _shake_strength), randf_range(-_shake_strength, _shake_strength))
	else:
		var cam = get_viewport().get_camera_2d()
		if cam: cam.offset = Vector2.ZERO
	
	# Agujero de Visión en Ceguera
	var overlay = get_node_or_null("BlindnessLayer/Darkness")
	if overlay and overlay.visible and is_instance_valid(local_player):
		var canvas_transform = get_viewport().get_canvas_transform()
		var view_top_left = -canvas_transform.get_origin() / canvas_transform.get_scale()
		var view_size = get_viewport().get_visible_rect().size / canvas_transform.get_scale()
		
		overlay.material.set_shader_parameter("player_world_pos", local_player.global_position)
		overlay.material.set_shader_parameter("world_radius", overlay.get_meta("radius_px", 150.0))
		overlay.material.set_shader_parameter("view_top_left", view_top_left)
		overlay.material.set_shader_parameter("view_size", view_size)
	
	save_timer += delta; if save_timer >= SAVE_INTERVAL: save_timer = 0.0; _save_game_progress()
	if is_instance_valid(local_player) and local_player.is_dead:
		respawn_timer += delta
		if respawn_timer >= 3.0:
			respawn_timer = 0.0
			_perform_local_respawn()
	else: 
		respawn_timer = 0.0

func _input(event):
	var focusNode = get_viewport().gui_get_focus_owner()
	if focusNode is LineEdit or focusNode is TextEdit: return
	
	if not NetworkManager or not NetworkManager.is_logged_in: return
	
	# Atajo para Dungeon Instanciada
	if event is InputEventKey and event.pressed and event.keycode == KEY_0:
		print("[DUNGEON] Solicitando ingreso a Dungeon Instanciada...")
		NetworkManager.send_event("enterDungeon", {})

func _parse_zone_to_int(zone_var) -> int:
	var val = zone_var
	if typeof(val) == TYPE_DICTIONARY:
		val = val.get("zoneId", 1)
	
	if typeof(val) == TYPE_STRING:
		if val.begins_with("dungeon"):
			return 99
		elif val.begins_with("extract_"):
			var parts = val.split("_")
			if parts.size() > 1:
				return int(parts[1])
			return 10
		else:
			return int(val)
	return int(val)

func _update_hud_map_name(zone_id):
	var z_id = _parse_zone_to_int(zone_id)
	var z_name = "SECTOR DESCONOCIDO"
	var z_id_str = str(z_id)
	
	if z_id_str in GameConstants.MAPS_CONFIG:
		z_name = GameConstants.MAPS_CONFIG[z_id_str].name
	elif z_id >= 500: 
		z_name = "INSTANCIA PRIVADA"
	else: 
		z_name = "SECTOR " + str(z_id).pad_zeros(2)
	
	if is_instance_valid(ui_hud) and ui_hud.has_method("set_map_name"):
		ui_hud.set_map_name(z_name)
	
	if is_instance_valid(local_player):
		local_player.current_zone = z_id

func _perform_local_respawn():
	if is_instance_valid(local_player) and local_player.has_method("respawn"):
		local_player.respawn()
	_save_game_progress()

func _on_login_success(data):
	local_player._on_login_success(data)

	if not local_player.shoot_fired.is_connected(_on_local_shoot): 
		local_player.shoot_fired.connect(_on_local_shoot)
	
	if "current_zone" in local_player:
		_update_background(local_player.current_zone)
		_update_hud_map_name(local_player.current_zone)
		
	if ui_hud: ui_hud.visible = true
	if ui_chat: ui_chat.visible = true

func _unhandled_input(event):
	if not NetworkManager or not NetworkManager.is_logged_in: return
	
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if is_instance_valid(ui_hud) and ui_hud.has_method("toggle_esc_menu"):
			ui_hud.toggle_esc_menu()

func route_chat_bubble(data: Dictionary):
	if is_instance_valid(entity_manager):
		entity_manager.route_chat_bubble(data)

func _on_local_shoot(d): 
	if combat_system: combat_system.handle_local_shoot(d)

func _save_game_progress():
	if not is_instance_valid(local_player): return
	var d = { 
		"hubs": local_player.hubs, 
		"ohcu": local_player.ohculianos, 
		"level": local_player.level, 
		"exp": local_player.current_exp, 
		"hp": local_player.current_hp, 
		"shield": local_player.current_shield,
		"maxHp": local_player.max_hp,
		"maxShield": local_player.max_shield,
	}
	NetworkManager.send_event("saveProgress", d)

func _on_admin_config_received(data: Dictionary):
	if GameConstants.has_method("update_from_server"):
		GameConstants.update_from_server(data)
		if is_instance_valid(ui_admin) and ui_admin.visible: ui_admin._refresh_ui()
		if is_instance_valid(ui_inventory) and ui_inventory.visible: ui_inventory._refresh_data()
		print("[WORLD] Configuración administrativa y constantes actualizadas.")

func _update_background(zone_id):
	var zid = int(zone_id)
	if typeof(zone_id) == TYPE_STRING and zone_id.begins_with("extract_"):
		var parts = zone_id.split("_")
		if parts.size() > 1:
			zid = int(parts[1])
			
	var scene_path = "res://scenes/maps/Map_Default.tscn"
	if zid == 1:
		scene_path = "res://scenes/maps/Map_Loby.tscn"
		
	if is_instance_valid(current_map_node):
		current_map_node.queue_free()
		
	var map_scene = load(scene_path)
	if map_scene:
		current_map_node = map_scene.instantiate()
		add_child(current_map_node)
		move_child(current_map_node, 0) # Asegurar que quede detrás de las entidades
		
		if current_map_node.has_method("setup_map"):
			current_map_node.setup_map()

func clear_remote_players():
	if is_instance_valid(entity_manager):
		entity_manager.clear_remote_players()
