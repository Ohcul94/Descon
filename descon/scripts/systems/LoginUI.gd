extends Control

# LoginUI.gd (v141.70 - RECONSTRUCTED)
# Pantalla de inicio con persistencia de usuario y corrección de señales.

@onready var user_input = get_node_or_null("Panel/VBoxContainer/UserLine")
@onready var pass_input = get_node_or_null("Panel/VBoxContainer/PassLine")
@onready var remember_check = get_node_or_null("Panel/VBoxContainer/RememberCheck")
@onready var status_lbl = get_node_or_null("Panel/VBoxContainer/ErrorLabel")
@onready var login_btn = get_node_or_null("Panel/VBoxContainer/HBoxContainer/LoginBtn")
@onready var register_btn = get_node_or_null("Panel/VBoxContainer/HBoxContainer/RegisterBtn")

const CONFIG_PATH = "user://descon_config.cfg"

func _ready():
	visible = true
	_load_saved_user()
	
	# Conexión manual de señales de botones (blindaje contra escenas rotas)
	if login_btn: login_btn.pressed.connect(_on_login_btn_pressed)
	if register_btn: register_btn.pressed.connect(_on_register_btn_pressed)
	
	if NetworkManager:
		NetworkManager.auth_success.connect(_on_auth_success)
		NetworkManager.auth_error.connect(_on_auth_fail)
		NetworkManager.login_success.connect(_on_auth_success)

func _on_login_btn_pressed():
	if not user_input or not pass_input: return
	
	var u = user_input.text.strip_edges()
	var p = pass_input.text.strip_edges()
	
	if u == "" or p == "":
		_show_status("Ingresa usuario y contraseña", Color.YELLOW)
		return
		
	_show_status("Conectando...", Color.CYAN)
	_save_user_state()
	
	# Intentar conexión (v141.70 usa 127.0.0.1 por defecto para desarrollo local)
	NetworkManager.connect_to_server("127.0.0.1", 3333, u, p)

func _on_register_btn_pressed():
	_show_status("Registro no implementado en esta versión local", Color.YELLOW)

func _on_auth_success(_data):
	_show_status("Bienvenido!", Color.GREEN)
	create_tween().tween_property(self, "modulate:a", 0.0, 0.5)
	await get_tree().create_timer(0.6).timeout
	visible = false

func _on_auth_fail(msg):
	_show_status("ERROR: " + str(msg), Color.RED)

func _show_status(txt, col):
	if status_lbl:
		status_lbl.text = txt
		status_lbl.modulate = col

func _save_user_state():
	var config = ConfigFile.new()
	if remember_check and remember_check.button_pressed:
		config.set_value("auth", "user", user_input.text)
		config.set_value("auth", "remember", true)
	else:
		config.set_value("auth", "remember", false)
	config.save(CONFIG_PATH)

func _load_saved_user():
	var config = ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		if config.get_value("auth", "remember", false):
			if user_input: user_input.text = config.get_value("auth", "user", "")
			if remember_check: remember_check.button_pressed = true
