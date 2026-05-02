extends Node

# SettingsManager.gd (v1.2 - Defaults & Reset)
# Maneja persistencia de teclas y configuración de casteo

const SETTINGS_PATH = "user://settings.cfg"

var config_file = ConfigFile.new()

# v264.10: Mapeo por defecto (Q-W-E-R-A-S-D)
var default_keys = {
	"slot_1": KEY_Q,
	"slot_2": KEY_W,
	"slot_3": KEY_E,
	"slot_4": KEY_R,
	"slot_5": KEY_A,
	"slot_6": KEY_S,
	"slot_7": KEY_D
}
var cast_mode_cache: int = 1 # v267.10: Cache local del modo de casteo

func _ready():
	load_settings()

func reset_to_factory():
	print("[SETTINGS] Reseteando a configuración de fábrica...")
	for action in default_keys:
		_apply_key_to_inputmap(action, default_keys[action])
	
	# Reset Cast Mode
	var player = get_tree().get_first_node_in_group("player")
	if player and player.get("_skill_controller"):
		player._skill_controller.config.cast_mode = 1 # ON_RELEASE
	
	save_settings()
	# Forzar actualización de HUD
	var hud = get_tree().get_first_node_in_group("main_hud")
	if hud and hud.has_method("_sync_hud_keys"): hud._sync_hud_keys()

func save_settings():
	var player = get_tree().get_first_node_in_group("player")
	if player and player.get("_skill_controller"):
		cast_mode_cache = player._skill_controller.config.cast_mode
		
	config_file.set_value("combat", "cast_mode", cast_mode_cache)
	
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
	
	# Aplicar cada slot, usando el default si no existe en el archivo
	for i in range(1, 8):
		var action = "slot_" + str(i)
		var default_val = default_keys.get(action, KEY_0)
		var val = config_file.get_value("keys", action, default_val)
		
		_apply_key_to_inputmap(action, val)
	
	if err == OK:
		cast_mode_cache = config_file.get_value("combat", "cast_mode", 1)
		print("[SETTINGS] Configuración cargada. Modo Cast: ", cast_mode_cache)
	else:
		cast_mode_cache = 1
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
