extends Node

# SettingsManager.gd (v1.2 - Defaults & Reset)
# Maneja persistencia de teclas y configuración de casteo

const SETTINGS_PATH = "user://settings.cfg"

var config_file = ConfigFile.new()

# v264.10: Mapeo por defecto (Q-W-E-R-A-S-D)
var default_keys = {
	"slot_1": KEY_Q, "slot_2": KEY_W, "slot_3": KEY_E, "slot_4": KEY_R,
	"slot_5": KEY_A, "slot_6": KEY_S, "slot_7": KEY_D,
	"ui_inventory": KEY_F1, "ui_menu": KEY_ESCAPE,
	"ui_map": KEY_M, "ui_party": KEY_P, "ui_pvp_toggle": KEY_C,
	"auto_target_self": KEY_ALT # v4.9: Atajo para auto-casteo
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
var mobile_aim_sensitivity: float = 1.0 # v266.700: Sensibilidad de apuntado MOBA (profundidad)
var mobile_invert_y: bool = true        # v266.760: Invertir eje Y en apuntado movil
func _ready():
	# v303.01: Soporte para argumentos de lanzamiento (--mobile)
	for arg in OS.get_cmdline_user_args():
		if arg == "--mobile":
			mobile_mode = true
			print("[SETTINGS] Forzando Modo Celular vía comando.")
	
	load_settings()
	
	# v303.02: Si iniciamos en modo celular, ajustar ventana inmediatamente
	if mobile_mode:
		call_deferred("_apply_mobile_window_size")

func _apply_mobile_window_size():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(450, 800))
	# Centrar ventana
	var screen_res = DisplayServer.screen_get_size()
	DisplayServer.window_set_position(screen_res / 2 - Vector2i(225, 400))

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
	
	for i in range(1, 8):
		var action = "slot_" + str(i)
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
		print("[SETTINGS] Configuración cargada.")
	else:
		cast_mode_cache = 1
		graphics_quality = 1
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
		print("[SETTINGS] Usando configuración por defecto.")

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
