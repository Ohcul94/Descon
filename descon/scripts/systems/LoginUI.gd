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
	
	# v187.01: Lógica de Auto-Login y Posicionamiento para Debugging
	_handle_debug_args()
	
	# Conexión manual de señales de botones
	if login_btn and not login_btn.pressed.is_connected(_on_login_btn_pressed):
		login_btn.pressed.connect(_on_login_btn_pressed)
	if register_btn and not register_btn.pressed.is_connected(_on_register_btn_pressed):
		register_btn.pressed.connect(_on_register_btn_pressed)
	
	if NetworkManager:
		if not NetworkManager.auth_success.is_connected(_on_auth_success):
			NetworkManager.auth_success.connect(_on_auth_success)
		if not NetworkManager.auth_error.is_connected(_on_auth_fail):
			NetworkManager.auth_error.connect(_on_auth_fail)
		if not NetworkManager.login_success.is_connected(_on_auth_success):
			NetworkManager.login_success.connect(_on_auth_success)
		if not NetworkManager.connection_lost.is_connected(_on_connection_lost):
			NetworkManager.connection_lost.connect(_on_connection_lost)

	# v214.200: FIX TÁCTIL PARA TABLETS + ENTER
	if user_input: 
		user_input.gui_input.connect(_on_input_gui_input.bind(user_input))
		if not user_input.text_submitted.is_connected(_on_submit_login):
			user_input.text_submitted.connect(_on_submit_login)
		
	if pass_input: 
		pass_input.gui_input.connect(_on_input_gui_input.bind(pass_input))
		if not pass_input.text_submitted.is_connected(_on_submit_login):
			pass_input.text_submitted.connect(_on_submit_login)

func _input(event):
	# Soporte universal para Enter (Failsafe)
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		if (user_input and user_input.has_focus()) or (pass_input and pass_input.has_focus()):
			_on_login_btn_pressed()
			get_viewport().set_input_as_handled()

func _on_submit_login(_text):
	_on_login_btn_pressed()

func _on_input_gui_input(event: InputEvent, node: LineEdit):
	if event is InputEventMouseButton and event.pressed:
		node.grab_focus()
		if OS.has_feature("mobile"): 
			DisplayServer.virtual_keyboard_show(node.text)

func _on_connection_lost():
	_on_auth_fail("CONEXIÓN TERMINADA.")

func _handle_debug_args():
	var args = OS.get_cmdline_args()
	var d_user = ""
	var d_pass = ""
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--user" and i + 1 < args.size(): d_user = args[i+1]
		elif arg == "--pass" and i + 1 < args.size(): d_pass = args[i+1]

	if d_user != "" and d_pass != "":
		if not NetworkManager.was_manual_logout:
			if user_input: user_input.text = d_user
			if pass_input: pass_input.text = d_pass
			get_tree().process_frame.connect(_on_login_btn_pressed, CONNECT_ONE_SHOT)
		else:
			NetworkManager.was_manual_logout = false

func _on_login_btn_pressed():
	if not user_input or not pass_input: return
	var u = user_input.text.strip_edges()
	var p = pass_input.text.strip_edges()
	if u == "" or p == "":
		_show_status("Ingresa usuario y contraseña", Color.YELLOW)
		return
	_show_status("Conectando...", Color.CYAN)
	_save_user_state()

	var target_ip = "mileage-cakes-teaches-personal.trycloudflare.com"
	var target_port = 443
	if OS.has_feature("editor"):
		target_ip = "127.0.0.1"
		target_port = 3333
	
	NetworkManager.connect_to_server(target_ip, target_port, u, p)

func _on_register_btn_pressed():
	_show_status("Registro no implementado", Color.YELLOW)

func _on_auth_success(_data):
	_show_status("Bienvenido!", Color.GREEN)
	var bg = get_node_or_null("FondoNegro")
	if bg: bg.visible = false
	create_tween().tween_property(self, "modulate:a", 0.0, 0.5)
	await get_tree().create_timer(0.6).timeout
	visible = false

func _on_auth_fail(msg):
	visible = true
	modulate.a = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	show()
	var bg = get_node_or_null("FondoNegro")
	if not bg:
		bg = ColorRect.new(); bg.name = "FondoNegro"; bg.color = Color.BLACK
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg); move_child(bg, 0)
	bg.visible = true
	_show_status("SESIÓN CERRADA: " + str(msg), Color.RED)

func _show_status(txt, col):
	if status_lbl:
		status_lbl.text = txt; status_lbl.modulate = col

func _save_user_state():
	var config = ConfigFile.new()
	if remember_check and remember_check.button_pressed:
		config.set_value("auth", "user", user_input.text)
		config.set_value("auth", "pass", pass_input.text)
		config.set_value("auth", "remember", true)
	else:
		config.set_value("auth", "remember", false)
	config.save(CONFIG_PATH)

func _load_saved_user():
	var config = ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		if config.get_value("auth", "remember", false):
			if user_input: user_input.text = config.get_value("auth", "user", "")
			if pass_input: pass_input.text = config.get_value("auth", "pass", "")
			if remember_check: remember_check.button_pressed = true
