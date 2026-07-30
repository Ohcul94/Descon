extends Node

# SettingsManager.gd (v1.2 - Defaults & Reset)
# Maneja persistencia de teclas y configuración de casteo

const SETTINGS_PATH = "user://settings.cfg"

var config_file = ConfigFile.new()

# v264.10: Mapeo por defecto (Q-W-E-R-A-S-D)
var default_keys = {
	"slot_1": KEY_Q, "slot_2": KEY_W, "slot_3": KEY_E, "slot_4": KEY_R,
	"slot_5": KEY_A, "slot_6": KEY_S, "slot_7": KEY_D,
	"ui_inventory": KEY_F1, "ui_menu": KEY_ESCAPE, "ui_events": KEY_F2, "ui_housing": KEY_F3, "ui_battlepass": KEY_F4,
	"ui_map": KEY_M, "ui_party": KEY_P, "ui_pvp_toggle": KEY_C,
	"auto_target_self": KEY_ALT, # v4.9: Atajo para auto-casteo
	"portal_jump": KEY_SPACE, # Atajo para portal de salto
	"toggle_free_camera": KEY_O, # Atajo para cámara libre 3D
	"toggle_orbit_mode": KEY_SEMICOLON, # Ñ en teclado español (física); orbit/free mode
	"chat_toggle": KEY_ENTER, # Atajo para chat
	"loot_claim": KEY_Y # Atajo para abrir cofres de botín
}
var cast_mode_cache: int = 1 # v267.10: Cache local del modo de casteo
var graphics_quality: int = 1 # 0: Baja, 1: Media, 2: Alta
var hit_flash_enabled: bool = true
var camera_shake_enabled: bool = true
var camera_shake_intensity: float = 1.0
var click_sensitivity: float = 1.0 
var skill_magnetism: float = 1.0   
var mouse_sensitivity: float = 1.0 # Velocidad del cursor virtual
var skill_aim_speed: float = 1.0   # Suavizado de apuntado de habilidades
var mobile_mode: bool = false           # v266.670: Modo Celular MOBA

# Estado de cámara que persiste entre mapas (NO se guarda en disco, se reinicia al cerrar el juego)
var cam_fixed_zoom: float = 0.88
var cam_free_active: bool = false
var cam_free_h: float = 0.0
var cam_free_v: float = 40.0
var cam_free_zoom: float = 28.0
var cam_free_orbit: bool = true
var cam_use_orthogonal: bool = false
var camera_use_orthogonal: bool = false
var mobile_aim_sensitivity: float = 1.0 # v266.700: Sensibilidad de apuntado MOBA (profundidad)
var mobile_invert_y: bool = true        # v266.760: Invertir eje Y en apuntado movil
var mobile_camera_edit_enabled: int = 0  # v420.600: 0=Fija, 1=Libre Editable, 2=Libre Bloqueada
var mobile_camera_sensitivity: float = 1.0  # v420.600: Sensibilidad de órbita táctil
var fps_limit: int = 60                 # Límite de FPS (30, 60, 90, 120)
var show_stars: bool = false            # Activar estrellas en el cielo (desactivado por defecto)
var minimap_rotate: bool = false        # Minimapa rotatorio (gira con la nave)

# Configuraciones de tamaño de letra de forma independiente
var font_size_player_name: int = 13
var font_size_player_stats: int = 10
var font_size_enemy_name: int = 13
var font_size_enemy_stats: int = 10
var font_size_chat_bubble: int = 10
var font_size_menus: int = 12

# Configuraciones de negrita de forma independiente (Por defecto desactivadas)
var bold_player_name: bool = false
var bold_player_stats: bool = false
var bold_enemy_name: bool = false
var bold_enemy_stats: bool = false
var bold_chat_bubble: bool = false
var bold_menus: bool = false

# Visibilidad de elementos de UI de entidades
var show_player_tags: bool = true
var show_enemy_tags: bool = true
var show_player_bars: bool = true
var show_enemy_bars: bool = true
var show_player_stats: bool = true
var show_enemy_stats: bool = true

var bold_font: SystemFont = null

func _ready():
	# v303.01: Soporte para argumentos de lanzamiento (--mobile)
	for arg in OS.get_cmdline_user_args():
		if arg == "--mobile":
			mobile_mode = true
			print("[SETTINGS] Forzando Modo Celular vía comando.")
	
	load_settings()
	apply_fps_limit(fps_limit)
	cam_use_orthogonal = camera_use_orthogonal
	
	# v303.02: Si iniciamos en modo celular, ajustar ventana inmediatamente
	if mobile_mode:
		call_deferred("_apply_mobile_window_size")
		
	# Conectar hook de escalado de interfaz dinámico
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)

func _apply_mobile_window_size():
	# Solo aplicar tamaño de ventana simulada en PC (si no es un dispositivo movil real)
	var os = OS.get_name()
	if os == "Android" or os == "iOS":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		return
		
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(450, 800))
	# Centrar ventana
	var screen_res = DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i(Vector2(screen_res) / 2.0) - Vector2i(225, 400))

func reset_to_factory():
	print("[SETTINGS] Reseteando a configuración de fábrica...")
	for action in default_keys:
		_apply_key_to_inputmap(action, default_keys[action])
	
	# Reset Cast Mode
	var player = get_tree().get_first_node_in_group("player")
	if player and player.get("_skill_controller"):
		player._skill_controller.config.cast_mode = 1 # ON_RELEASE
	
	graphics_quality = 1 # Restaurar a Media
	hit_flash_enabled = true
	camera_shake_enabled = true
	camera_shake_intensity = 1.0
	click_sensitivity = 1.0
	skill_magnetism = 1.0
	mouse_sensitivity = 1.0
	skill_aim_speed = 1.0
	mobile_mode = false
	mobile_aim_sensitivity = 1.0
	mobile_invert_y = true
	mobile_camera_edit_enabled = 0
	mobile_camera_sensitivity = 1.0
	fps_limit = 60
	camera_use_orthogonal = false
	cam_use_orthogonal = false
	show_stars = false
	minimap_rotate = false
	show_player_tags = true
	show_enemy_tags = true
	show_player_bars = true
	show_enemy_bars = true
	show_player_stats = true
	show_enemy_stats = true
	apply_fps_limit(60)
	
	font_size_player_name = 13
	font_size_player_stats = 10
	font_size_enemy_name = 13
	font_size_enemy_stats = 10
	font_size_chat_bubble = 10
	font_size_menus = 12
	
	bold_player_name = false
	bold_player_stats = false
	bold_enemy_name = false
	bold_enemy_stats = false
	bold_chat_bubble = false
	bold_menus = false
	
	apply_menu_fonts_live()
	update_entity_tags_live()
	
	save_settings()
	# Forzar actualización de HUD
	var hud = get_tree().get_first_node_in_group("main_hud")
	if hud and hud.has_method("_sync_hud_keys"): hud._sync_hud_keys()

func save_settings():
	var player = get_tree().get_first_node_in_group("player")
	if player and player.get("_skill_controller"):
		cast_mode_cache = player._skill_controller.config.cast_mode
		
	config_file.set_value("combat", "cast_mode", cast_mode_cache)
	config_file.set_value("graphics", "quality", graphics_quality)
	config_file.set_value("graphics", "fps_limit", fps_limit)
	config_file.set_value("graphics", "camera_use_orthogonal", camera_use_orthogonal)
	config_file.set_value("graphics", "show_stars", show_stars)
	config_file.set_value("graphics", "minimap_rotate", minimap_rotate)
	config_file.set_value("accessibility", "hit_flash", hit_flash_enabled)
	config_file.set_value("accessibility", "camera_shake", camera_shake_enabled)
	config_file.set_value("accessibility", "camera_shake_intensity", camera_shake_intensity)
	config_file.set_value("accessibility", "click_sensitivity", click_sensitivity)
	config_file.set_value("accessibility", "skill_magnetism", skill_magnetism)
	config_file.set_value("accessibility", "mouse_sensitivity", mouse_sensitivity)
	config_file.set_value("accessibility", "skill_aim_speed", skill_aim_speed)
	config_file.set_value("accessibility", "mobile_mode", mobile_mode)
	config_file.set_value("accessibility", "mobile_aim_sensitivity", mobile_aim_sensitivity)
	config_file.set_value("accessibility", "mobile_invert_y", mobile_invert_y)
	config_file.set_value("accessibility", "mobile_camera_edit_enabled", mobile_camera_edit_enabled)
	config_file.set_value("accessibility", "mobile_camera_sensitivity", mobile_camera_sensitivity)
	config_file.set_value("accessibility", "font_size_player_name", font_size_player_name)
	config_file.set_value("accessibility", "font_size_player_stats", font_size_player_stats)
	config_file.set_value("accessibility", "font_size_enemy_name", font_size_enemy_name)
	config_file.set_value("accessibility", "font_size_enemy_stats", font_size_enemy_stats)
	config_file.set_value("accessibility", "font_size_chat_bubble", font_size_chat_bubble)
	config_file.set_value("accessibility", "font_size_menus", font_size_menus)
	config_file.set_value("accessibility", "bold_player_name", bold_player_name)
	config_file.set_value("accessibility", "bold_player_stats", bold_player_stats)
	config_file.set_value("accessibility", "bold_enemy_name", bold_enemy_name)
	config_file.set_value("accessibility", "bold_enemy_stats", bold_enemy_stats)
	config_file.set_value("accessibility", "bold_chat_bubble", bold_chat_bubble)
	config_file.set_value("accessibility", "bold_menus", bold_menus)
	config_file.set_value("interface", "show_player_tags", show_player_tags)
	config_file.set_value("interface", "show_enemy_tags", show_enemy_tags)
	config_file.set_value("interface", "show_player_bars", show_player_bars)
	config_file.set_value("interface", "show_enemy_bars", show_enemy_bars)
	config_file.set_value("interface", "show_player_stats", show_player_stats)
	config_file.set_value("interface", "show_enemy_stats", show_enemy_stats)
	
	for action in default_keys:
		var events = InputMap.action_get_events(action)
		if events.size() > 0:
			var event = events[0]
			if event is InputEventKey:
				config_file.set_value("keys", action, event.physical_keycode)
			elif event is InputEventMouseButton:
				config_file.set_value("keys", action, "MOUSE_" + str(event.button_index))
	
	config_file.save(SETTINGS_PATH)

func load_settings():
	var err = config_file.load(SETTINGS_PATH)
	
	# Aplicar todas las teclas del mapeo, usando el default si no existe en el archivo
	for action in default_keys:
		var default_val = default_keys[action]
		var val = config_file.get_value("keys", action, default_val)
		_apply_key_to_inputmap(action, val)
	
	if err == OK:
		cast_mode_cache = config_file.get_value("combat", "cast_mode", 1)
		graphics_quality = config_file.get_value("graphics", "quality", 1)
		fps_limit = config_file.get_value("graphics", "fps_limit", 60)
		camera_use_orthogonal = config_file.get_value("graphics", "camera_use_orthogonal", true)
		show_stars = config_file.get_value("graphics", "show_stars", false)
		minimap_rotate = config_file.get_value("graphics", "minimap_rotate", false)
		hit_flash_enabled = config_file.get_value("accessibility", "hit_flash", true)
		camera_shake_enabled = config_file.get_value("accessibility", "camera_shake", true)
		camera_shake_intensity = config_file.get_value("accessibility", "camera_shake_intensity", 1.0)
		click_sensitivity = config_file.get_value("accessibility", "click_sensitivity", 1.0)
		skill_magnetism = config_file.get_value("accessibility", "skill_magnetism", 1.0)
		mouse_sensitivity = config_file.get_value("accessibility", "mouse_sensitivity", 1.0)
		skill_aim_speed = config_file.get_value("accessibility", "skill_aim_speed", 1.0)
		mobile_mode = config_file.get_value("accessibility", "mobile_mode", false)
		mobile_aim_sensitivity = config_file.get_value("accessibility", "mobile_aim_sensitivity", 1.0)
		mobile_invert_y = config_file.get_value("accessibility", "mobile_invert_y", true)
		var raw_val = config_file.get_value("accessibility", "mobile_camera_edit_enabled", 0)
		mobile_camera_edit_enabled = 1 if typeof(raw_val) == TYPE_BOOL and raw_val else (0 if typeof(raw_val) == TYPE_BOOL else int(raw_val))
		mobile_camera_sensitivity = config_file.get_value("accessibility", "mobile_camera_sensitivity", 1.0)
		font_size_player_name = config_file.get_value("accessibility", "font_size_player_name", 13)
		font_size_player_stats = config_file.get_value("accessibility", "font_size_player_stats", 10)
		font_size_enemy_name = config_file.get_value("accessibility", "font_size_enemy_name", 13)
		font_size_enemy_stats = config_file.get_value("accessibility", "font_size_enemy_stats", 10)
		font_size_chat_bubble = config_file.get_value("accessibility", "font_size_chat_bubble", 10)
		font_size_menus = config_file.get_value("accessibility", "font_size_menus", 12)
		bold_player_name = config_file.get_value("accessibility", "bold_player_name", false)
		bold_player_stats = config_file.get_value("accessibility", "bold_player_stats", false)
		bold_enemy_name = config_file.get_value("accessibility", "bold_enemy_name", false)
		bold_enemy_stats = config_file.get_value("accessibility", "bold_enemy_stats", false)
		bold_chat_bubble = config_file.get_value("accessibility", "bold_chat_bubble", false)
		bold_menus = config_file.get_value("accessibility", "bold_menus", false)
		show_player_tags = config_file.get_value("interface", "show_player_tags", true)
		show_enemy_tags = config_file.get_value("interface", "show_enemy_tags", true)
		show_player_bars = config_file.get_value("interface", "show_player_bars", true)
		show_enemy_bars = config_file.get_value("interface", "show_enemy_bars", true)
		show_player_stats = config_file.get_value("interface", "show_player_stats", true)
		show_enemy_stats = config_file.get_value("interface", "show_enemy_stats", true)
		print("[SETTINGS] Configuración cargada.")
	else:
		cast_mode_cache = 1
		graphics_quality = 1
		fps_limit = 60
		camera_use_orthogonal = false
		show_stars = false
		minimap_rotate = false
		hit_flash_enabled = true
		camera_shake_enabled = true
		camera_shake_intensity = 1.0
		click_sensitivity = 1.0
		skill_magnetism = 1.0
		mouse_sensitivity = 1.0
		skill_aim_speed = 1.0
		mobile_mode = false
		mobile_aim_sensitivity = 1.0
		mobile_invert_y = true
		mobile_camera_edit_enabled = 0
		mobile_camera_sensitivity = 1.0
		font_size_player_name = 13
		font_size_player_stats = 10
		font_size_enemy_name = 13
		font_size_enemy_stats = 10
		font_size_chat_bubble = 10
		font_size_menus = 12
		bold_player_name = false
		bold_player_stats = false
		bold_enemy_name = false
		bold_enemy_stats = false
		bold_chat_bubble = false
		bold_menus = false
		show_player_tags = true
		show_enemy_tags = true
		show_player_bars = true
		show_enemy_bars = true
		show_player_stats = true
		show_enemy_stats = true
		print("[SETTINGS] Usando configuración por defecto.")

func apply_fps_limit(limit: int):
	fps_limit = limit
	Engine.max_fps = limit
	# Si es de 90 o 120 FPS y estamos en PC, desactivar vsync para poder superar los 60 hz si es que la pantalla no da más
	if limit > 60:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	print("[SETTINGS] Límite de FPS aplicado: ", limit, " (VSync: ", "OFF" if limit > 60 else "ON", ")")

func _apply_key_to_inputmap(action: String, val):
	if not InputMap.has_action(action): InputMap.add_action(action)
	InputMap.action_erase_events(action)
	
	var new_event = null
	if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
		new_event = InputEventKey.new()
		new_event.physical_keycode = int(val)
	elif typeof(val) == TYPE_STRING and val.begins_with("MOUSE_"):
		new_event = InputEventMouseButton.new()
		new_event.button_index = int(val.replace("MOUSE_", ""))
	
	if new_event:
		InputMap.action_add_event(action, new_event)

func get_cast_mode() -> int:
	return cast_mode_cache

func get_graphics_quality() -> int:
	return graphics_quality

# --- FUNCIONES DE ESCALADO DINÁMICO DE FUENTES ---

func update_entity_tags_live():
	for ent in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(ent) and ent.has_method("_force_update_tags"):
			ent._force_update_tags()

func update_entity_hud_live():
	for ent in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(ent) and is_instance_valid(ent._ui_wrapper):
			ent._ui_wrapper.queue_redraw()

func apply_menu_fonts_live():
	var roots = []
	for hud in get_tree().get_nodes_in_group("hud"):
		roots.append(hud)
	for ui in get_tree().get_nodes_in_group("inventory_ui"):
		roots.append(ui)
	for chat in get_tree().get_nodes_in_group("chat_ui"):
		roots.append(chat)
	for settings in get_tree().get_nodes_in_group("settings_ui"):
		roots.append(settings)
	
	for r in roots:
		apply_menu_font_sizes_recursive(r, font_size_menus)

func get_bold_font() -> SystemFont:
	if not bold_font:
		bold_font = SystemFont.new()
		bold_font.font_weight = 700 # Peso de negrita (Bold)
	return bold_font

func apply_menu_font_sizes_recursive(node: Node, base_size: int):
	if not is_instance_valid(node): return
	
	if node is Control:
		node.set_meta("fonts_scaled", true)
		var default_ref = 12
		var ratio = float(base_size) / float(default_ref)
		
		# Aplicar negrita a nivel de nodo
		if bold_menus:
			if not node is RichTextLabel:
				node.add_theme_font_override("font", get_bold_font())
			else:
				node.add_theme_font_override("normal_font", get_bold_font())
		else:
			if not node is RichTextLabel:
				node.remove_theme_font_override("font")
			else:
				node.remove_theme_font_override("normal_font")
		
		if node is Label:
			var orig = node.get_meta("orig_font_size", -1)
			if orig == -1:
				orig = node.get_theme_font_size("font_size")
				if orig <= 0 or orig > 100: orig = 12
				node.set_meta("orig_font_size", orig)
			node.add_theme_font_size_override("font_size", int(round(orig * ratio)))
		elif node is Button:
			var orig = node.get_meta("orig_font_size", -1)
			if orig == -1:
				orig = node.get_theme_font_size("font_size")
				if orig <= 0 or orig > 100: orig = 12
				node.set_meta("orig_font_size", orig)
			node.add_theme_font_size_override("font_size", int(round(orig * ratio)))
		elif node is RichTextLabel:
			var orig = node.get_meta("orig_font_size", -1)
			if orig == -1:
				orig = node.get_theme_font_size("normal_font_size")
				if orig <= 0 or orig > 100: orig = 12
				node.set_meta("orig_font_size", orig)
			node.add_theme_font_size_override("normal_font_size", int(round(orig * ratio)))
			node.add_theme_font_size_override("bold_font_size", int(round(orig * ratio)))
		elif node is LineEdit or node is TextEdit:
			var orig = node.get_meta("orig_font_size", -1)
			if orig == -1:
				orig = node.get_theme_font_size("font_size")
				if orig <= 0 or orig > 100: orig = 12
				node.set_meta("orig_font_size", orig)
			node.add_theme_font_size_override("font_size", int(round(orig * ratio)))
		elif node is TabContainer:
			var orig = node.get_meta("orig_font_size", -1)
			if orig == -1:
				orig = node.get_theme_font_size("font_size")
				if orig <= 0 or orig > 100: orig = 12
				node.set_meta("orig_font_size", orig)
			node.add_theme_font_size_override("font_size", int(round(orig * ratio)))
		elif node is OptionButton:
			var orig = node.get_meta("orig_font_size", -1)
			if orig == -1:
				orig = node.get_theme_font_size("font_size")
				if orig <= 0 or orig > 100: orig = 12
				node.set_meta("orig_font_size", orig)
			node.add_theme_font_size_override("font_size", int(round(orig * ratio)))
			
	for child in node.get_children():
		apply_menu_font_sizes_recursive(child, base_size)

func _on_node_added(node: Node):
	if node is Control:
		if node.name == "NameTag" or node.get_meta("is_chat_bubble", false) or node.name.begins_with("Wreckage_"):
			return
		
		# v312.1: Bypass rápido para evitar lag en etiquetas de combate dinámicas
		var parent = node.get_parent()
		if parent:
			if parent.name.begins_with("Wreckage_"):
				return
			var script = parent.get_script()
			if script and script.get_path().ends_with("DamageText.gd"):
				return

		if node.has_meta("fonts_scaled") and node.get_meta("fonts_scaled"):
			return
		if not node.is_inside_tree(): return
		await node.get_tree().process_frame
		if is_instance_valid(node) and node.is_inside_tree():
			if node.has_meta("fonts_scaled") and node.get_meta("fonts_scaled"):
				return
			# Si pertenece a las interfaces o HUDs principales
			apply_menu_font_sizes_recursive(node, font_size_menus)
