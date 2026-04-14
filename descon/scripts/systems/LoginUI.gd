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
	
	# Conexión manual de señales de botones (blindaje contra escenas rotas)
	if login_btn: login_btn.pressed.connect(_on_login_btn_pressed)
	if register_btn: register_btn.pressed.connect(_on_register_btn_pressed)
	
	if NetworkManager:
		NetworkManager.auth_success.connect(_on_auth_success)
		NetworkManager.auth_error.connect(_on_auth_fail)
		NetworkManager.login_success.connect(_on_auth_success)
		if not NetworkManager.connection_lost.is_connected(_on_connection_lost):
			NetworkManager.connection_lost.connect(_on_connection_lost)
			
	# v214.200: FIX TÁCTIL PARA TABLETS (Forzar foco al tocar inputs)
	if user_input: user_input.gui_input.connect(_on_input_gui_input.bind(user_input))
	if pass_input: pass_input.gui_input.connect(_on_input_gui_input.bind(pass_input))

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
		if arg == "--user" and i + 1 < args.size():
			d_user = args[i+1]
		elif arg == "--pass" and i + 1 < args.size():
			d_pass = args[i+1]
		elif arg == "--win_pos" and i + 1 < args.size():
			var pos_str = args[i+1].split(",")
			if pos_str.size() == 2:
				DisplayServer.window_set_position(Vector2i(int(pos_str[0]), int(pos_str[1])))
		elif arg == "--win_size" and i + 1 < args.size():
			var size_str = args[i+1].split(",")
			if size_str.size() == 2:
				DisplayServer.window_set_size(Vector2i(int(size_str[0]), int(size_str[1])))

	if d_user != "" and d_pass != "":
		print("[DEBUG] Auto-login detectado para: ", d_user)
		if user_input: user_input.text = d_user
		if pass_input: pass_input.text = d_pass
		# Esperar un frame a que todo cargue antes de conectar
		get_tree().process_frame.connect(_on_login_btn_pressed, CONNECT_ONE_SHOT)

func _on_login_btn_pressed():
	if not user_input or not pass_input: return
	
	var u = user_input.text.strip_edges()
	var p = pass_input.text.strip_edges()
	
	if u == "" or p == "":
		_show_status("Ingresa usuario y contraseña", Color.YELLOW)
		return
		
	_show_status("Conectando...", Color.CYAN)
	_save_user_state()
	
# Intentar conexión dinámica (v141.72: Fix Auto-Cloudflare para APK)
	var target_ip = "mileage-cakes-teaches-personal.trycloudflare.com" # Cambiado de 127.0.0.1
	var target_port = 443 # El puerto de los túneles HTTPS siempre es 443
	
	# Usar 127.0.0.1 solo si estamos en el editor de Godot testeando local
	if OS.has_feature("editor"):
		target_ip = "127.0.0.1"
		target_port = 3333
	
	# 1. Prioridad: Argumentos de consola
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--ip" and i + 1 < args.size():
			target_ip = args[i+1]
		elif args[i] == "--port" and i + 1 < args.size():
			target_port = int(args[i+1])
			
	# 2. Prioridad: Archivo de configuración manual (al lado del .exe)
	var exe_path = OS.get_executable_path().get_base_dir()
	var config_file = exe_path + "/server_config.ini"
	if FileAccess.file_exists(config_file):
		var file = FileAccess.open(config_file, FileAccess.READ)
		var content = file.get_as_text().strip_edges()
		if content != "":
			var lines = content.split("\n")
			for line in lines:
				if line.begins_with("ip="): target_ip = line.split("=")[1].strip_edges()
				elif line.begins_with("port="): target_port = int(line.split("=")[1].strip_edges())
		print("[NET] Configuración cargada desde archivo externo: ", target_ip)

	NetworkManager.connect_to_server(target_ip, target_port, u, p)

func _on_register_btn_pressed():
	_show_status("Registro no implementado en esta versión local", Color.YELLOW)

func _on_auth_success(_data):
	_show_status("Bienvenido!", Color.GREEN)
	# Quitar cortina negra
	var bg = get_node_or_null("FondoNegro")
	if bg: bg.visible = false
	
	create_tween().tween_property(self, "modulate:a", 0.0, 0.5)
	await get_tree().create_timer(0.6).timeout
	visible = false

func _on_auth_fail(msg):
	# v189.50: LA CORTINA NEGRA (Simple y 100% Efectivo)
	visible = true
	modulate.a = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Asegurarnos de que el panel de login esté por encima de todo
	show()
	
	# Crear u Ocultar con fondo negro total
	var bg = get_node_or_null("FondoNegro")
	if not bg:
		bg = ColorRect.new()
		bg.name = "FondoNegro"
		bg.color = Color.BLACK
		# Forzar que cubra toda la pantalla
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		move_child(bg, 0) # Ponerlo al fondo del Panel de Login
	
	bg.visible = true

	_show_status("SESIÓN CERRADA: " + str(msg), Color.RED)
	print("[NET] Desconexión: ", msg)

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
