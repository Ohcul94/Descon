extends Control

# Bootloader.gd (v1.0 - PRODUCCIÓN)
# Pantalla de carga inicial que descarga y monta parches PCK dinámicos con firma RSA.

const LOCAL_MANIFEST_PATH = "user://manifest_local.json"
const PCK_SAVE_PATH = "user://updates.pck"
const PCK_TEMP_PATH = "user://updates_temp.pck"
const SERVER_PORT = 3333

@onready var status_lbl = $BootloaderUI/MarginContainer/VBoxContainer/StatusLabel
@onready var progress_bar = $BootloaderUI/MarginContainer/VBoxContainer/DownloadProgressBar
@onready var http_request = $HTTPRequest

var target_ip: String = "138.2.241.76" # IP de Oracle Cloud
var remote_manifest: Dictionary = {}
var platform_key: String = "windows"
var is_downloading: bool = false
var bytes_received: int = 0
var total_bytes: int = 0

func _ready():
	# Forzar pantalla completa inmersiva incondicionalmente en dispositivos móviles (Android/iOS)
	var os_name = OS.get_name()
	if os_name == "Android" or os_name == "iOS":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	# 1. Si ya se montó el PCK y reiniciamos de forma nativa para recargar autoloads,
	# simplemente iniciamos el juego directamente.
	if get_tree().has_meta("pck_loaded_and_reloaded"):
		print("[Bootloader] Iniciando juego con parches aplicados y singletons recargados.")
		status_lbl.text = "Iniciando juego..."
		await get_tree().process_frame
		_setup_background_cinematic()
		await get_tree().create_timer(0.2).timeout
		_finish_bootloader_and_start()
		return

	# 2. Si estamos en el EDITOR de Godot, BYPASSEAR el sistema de actualizaciones
	# Esto evita que se sobrescriban los scripts que el desarrollador está editando en tiempo real.
	if OS.has_feature("editor"):
		print("[Bootloader] Ejecutando en Editor. Omitiendo actualizaciones para desarrollo local.")
		status_lbl.text = "Iniciando modo desarrollo..."
		await get_tree().process_frame
		_setup_background_cinematic()
		await get_tree().create_timer(0.5).timeout
		_finish_bootloader_and_start()
		return

	# 3. Configurar plataforma y servidor para builds compilados
	if os_name == "Android":
		platform_key = "android"
		target_ip = "138.2.241.76" # Celular siempre apunta a Oracle Cloud
	else:
		platform_key = "windows"
		# PC standalone: debug build apunta a local, release build apunta a producción
		if OS.is_debug_build():
			target_ip = "127.0.0.1"
		else:
			target_ip = "138.2.241.76"
			
	status_lbl.text = "Conectando con el servidor..."
	
	# Configurar estilo visual premium (verde neón) de la barra
	var pb_bg = StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.04, 0.05, 0.09, 0.85)
	pb_bg.border_width_left = 1
	pb_bg.border_width_top = 1
	pb_bg.border_width_right = 1
	pb_bg.border_width_bottom = 1
	pb_bg.border_color = Color(0.2, 0.95, 0.4, 0.2)
	pb_bg.corner_radius_top_left = 5
	pb_bg.corner_radius_top_right = 5
	pb_bg.corner_radius_bottom_left = 5
	pb_bg.corner_radius_bottom_right = 5
	
	var pb_fg = StyleBoxFlat.new()
	pb_fg.bg_color = Color(0.2, 0.95, 0.4, 0.9)
	pb_fg.corner_radius_top_left = 5
	pb_fg.corner_radius_top_right = 5
	pb_fg.corner_radius_bottom_left = 5
	pb_fg.corner_radius_bottom_right = 5
	pb_fg.shadow_color = Color(0.2, 0.95, 0.4, 0.45)
	pb_fg.shadow_size = 4
	
	progress_bar.add_theme_stylebox_override("background", pb_bg)
	progress_bar.add_theme_stylebox_override("fill", pb_fg)
	
	progress_bar.value = 0
	progress_bar.visible = false
	
	# Iniciar cinemática de naves en segundo plano mediante VFXSystem tras esperar a que el árbol esté listo
	await get_tree().process_frame
	_setup_background_cinematic()
	
	# Esperar un momento antes de empezar la verificación
	await get_tree().create_timer(0.5).timeout
	_check_for_updates()

func _setup_background_cinematic():
	# VFXSystem ya tiene cargada la función de configurar la cinemática
	var vfx = get_node_or_null("/root/VFXSystem")
	if vfx and vfx.has_method("_setup_cinematic_3d"):
		vfx._setup_cinematic_3d()
		print("[Bootloader] Cinemática de fondo iniciada desde VFXSystem.")
	else:
		print("[Bootloader-WARN] VFXSystem no está disponible o no tiene _setup_cinematic_3d")

func _check_for_updates():
	status_lbl.text = "Buscando actualizaciones..."
	var url = "http://" + target_ip + ":" + str(SERVER_PORT) + "/cdn/manifest.json"
	
	# Conectar señal de respuesta de HTTPRequest
	if http_request.request_completed.is_connected(_on_manifest_download_completed):
		http_request.request_completed.disconnect(_on_manifest_download_completed)
	http_request.request_completed.connect(_on_manifest_download_completed)
	
	var err = http_request.request(url)
	if err != OK:
		print("[Bootloader-ERR] Error al iniciar petición de manifiesto: ", err)
		_fail_and_load_game("Error de conexión al buscar actualizaciones.")

func _on_manifest_download_completed(_result, response_code, _headers, body):
	http_request.request_completed.disconnect(_on_manifest_download_completed)
	
	if response_code != 200:
		print("[Bootloader-ERR] Servidor no respondió con 200 OK. Código: ", response_code)
		_fail_and_load_game("Servidor de actualizaciones no disponible.")
		return
		
	var json = JSON.new()
	var err = json.parse(body.get_string_from_utf8())
	if err != OK:
		print("[Bootloader-ERR] Error al parsear JSON del manifiesto.")
		_fail_and_load_game("Manifiesto corrupto en el servidor.")
		return
		
	remote_manifest = json.data
	print("[Bootloader] Manifiesto remoto obtenido. Versión: ", remote_manifest.get("version"))
	
	_compare_versions()

func _compare_versions():
	# Leer hash local del paquete para esta plataforma
	var local_hash = ""
	if FileAccess.file_exists(LOCAL_MANIFEST_PATH):
		var file = FileAccess.open(LOCAL_MANIFEST_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var local_packages = json.data.get("packages", {})
				if local_packages.has(platform_key):
					local_hash = local_packages[platform_key].get("hash", "")
			file.close()
				
	var packages = remote_manifest.get("packages", {})
	if not packages.has(platform_key):
		print("[Bootloader] No hay paquete para la plataforma actual: ", platform_key)
		_load_existing_pck_if_any_and_start()
		return

	var package_info = packages[platform_key]
	var remote_hash = package_info.get("hash", "")
	var pck_exists = FileAccess.file_exists(PCK_SAVE_PATH)
	
	print("[Bootloader] Comparando hashes - Local: '", local_hash.left(10), "' | Remoto: '", remote_hash.left(10), "' | PCK Existe: ", pck_exists)
	
	# Si el hash remoto es diferente, o el archivo PCK local no existe fisicamente
	if local_hash != remote_hash or not pck_exists:
		print("[Bootloader] Actualizacion disponible. Local hash: ", local_hash.left(10), " | Remoto: ", remote_hash.left(10))
		_download_pck(package_info)
	else:
		print("[Bootloader] El juego ya esta actualizado (hashes coinciden).")
		_load_existing_pck_if_any_and_start()

func _download_pck(package_info: Dictionary):
	var file_name = package_info.get("file")
	total_bytes = package_info.get("size", 0)
	var url = "http://" + target_ip + ":" + str(SERVER_PORT) + "/cdn/" + file_name.uri_encode()
	
	status_lbl.text = "Descargando recursos (0%)..."
	progress_bar.value = 0
	progress_bar.visible = true
	is_downloading = true
	
	# Usar HTTPRequest configurado para descargar directamente a disco temporal
	http_request.download_file = PCK_TEMP_PATH
	
	http_request.request_completed.connect(_on_pck_download_completed.bind(package_info))
	
	var err = http_request.request(url)
	if err != OK:
		print("[Bootloader-ERR] Error al iniciar descarga de PCK: ", err)
		_fail_and_load_game("Error al iniciar descarga del juego.")

# Hacemos poll en _process para mostrar la barra de progreso de descarga real
func _process(_delta):
	if is_downloading and http_request.get_http_client_status() == HTTPClient.STATUS_BODY:
		var current_downloaded = http_request.get_downloaded_bytes()
		if total_bytes > 0:
			var pct = float(current_downloaded) / float(total_bytes) * 100.0
			progress_bar.value = pct
			status_lbl.text = "Descargando recursos (%.1f%%)..." % pct

func _on_pck_download_completed(_result, response_code, _headers, _body, package_info: Dictionary):
	is_downloading = false
	http_request.request_completed.disconnect(_on_pck_download_completed)
	
	if response_code != 200:
		print("[Bootloader-ERR] Error en descarga de PCK. Respuesta: ", response_code)
		_fail_and_load_game("Fallo al descargar actualizaciones.")
		return
		
	status_lbl.text = "Verificando integridad..."
	await get_tree().create_timer(0.2).timeout
	
	# 1. Verificar Hash SHA-256 del archivo temporal
	var local_hash = _calculate_file_sha256(PCK_TEMP_PATH)
	var remote_hash = package_info.get("hash", "")
	
	if local_hash != remote_hash:
		print("[Bootloader-ERR] El hash del archivo no coincide. Local: ", local_hash, " | Remoto: ", remote_hash)
		_fail_and_load_game("El archivo descargado está corrupto.")
		return
		
	# 2. Verificar Firma RSA del archivo temporal
	var signature_b64 = package_info.get("signature", "")
	var is_valid = _verify_signature(PCK_TEMP_PATH, signature_b64)
	
	if not is_valid:
		print("[Bootloader-ERR] Firma digital no válida. El archivo podría haber sido modificado.")
		_fail_and_load_game("Fallo de verificación de seguridad.")
		return
		
	print("[Bootloader] Verificación exitosa. Guardando actualización...")
	
	# Reemplazar el archivo temporal por el definitivo de forma segura
	if FileAccess.file_exists(PCK_SAVE_PATH):
		DirAccess.remove_absolute(PCK_SAVE_PATH)
		
	var err_rename = DirAccess.rename_absolute(PCK_TEMP_PATH, PCK_SAVE_PATH)
	if err_rename != OK:
		print("[Bootloader-ERR] Error al renombrar archivo temporal a definitivo: ", err_rename)
		_fail_and_load_game("Error al guardar la actualización.")
		return
		
	# Guardar manifiesto local
	var file = FileAccess.open(LOCAL_MANIFEST_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(remote_manifest))
		file.close()
	
	_mount_pck_and_start()

func _calculate_file_sha256(file_path: String) -> String:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ""
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		var chunk = file.get_buffer(65536)
		ctx.update(chunk)
	var file_hash = ctx.finish()
	file.close()
	
	# Convertir a hexadecimal string
	var hash_str = ""
	for b in file_hash:
		hash_str += "%02x" % b
	return hash_str

func _verify_signature(file_path: String, signature_b64: String) -> bool:
	# Cargar clase PublicKey (creada por package_updates.js)
	var pub_key_script = load("res://scripts/autoloads/PublicKey.gd")
	if not pub_key_script:
		print("[Bootloader-ERR] No se encontró el autoload de la clave pública.")
		return false
		
	var pub_key_pem = pub_key_script.PUBLIC_KEY_PEM
	var key = CryptoKey.new()
	var err = key.load_from_string(pub_key_pem, true) # true = public_key_only
	if err != OK:
		print("[Bootloader-ERR] Error al cargar clave pública PEM: ", err)
		return false
		
	# Obtener hash del archivo
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		var chunk = file.get_buffer(65536)
		ctx.update(chunk)
	var file_hash = ctx.finish()
	file.close()
	
	# Decodificar firma Base64
	var signature_bytes = Marshalls.base64_to_raw(signature_b64)
	
	var crypto = Crypto.new()
	var verified = crypto.verify(HashingContext.HASH_SHA256, file_hash, signature_bytes, key)
	return verified

func _load_existing_pck_if_any_and_start():
	if FileAccess.file_exists(PCK_SAVE_PATH):
		_mount_pck_and_start()
	else:
		# No hay parches locales, iniciar directamente con los assets del juego base
		_finish_bootloader_and_start()

func _mount_pck_and_start():
	var success = ProjectSettings.load_resource_pack(PCK_SAVE_PATH)
	if success:
		print("[Bootloader] PCK montado con éxito.")
		_reload_autoloads()
		return # Detener ejecución aquí, ya que _reload_autoloads reiniciará la escena de forma nativa
	else:
		print("[Bootloader-ERR] Fallo al montar el PCK local.")
		
	_finish_bootloader_and_start()

func _reload_autoloads():
	# Si ya venimos de recargar el árbol con el PCK montado, no lo volvemos a hacer
	if get_tree().has_meta("pck_loaded_and_reloaded"):
		print("[Bootloader] Iniciando con singletons recargados por el motor.")
		return

	print("[Bootloader] PCK montado. Recargando scripts de Autoloads desde el PCK...")
	
	var autoloads = {
		"NetworkManager": "res://scripts/autoloads/NetworkManager.gd",
		"AudioManager": "res://scripts/autoloads/AudioManager.gd",
		"GameConstants": "res://scripts/autoloads/Constants.gd",
		"PartyManager": "res://scripts/systems/PartyManager.gd",
		"VFXSystem": "res://scripts/systems/VFXManager.gd",
		"SettingsManager": "res://scripts/autoloads/SettingsManager.gd"
	}
	
	for autoload_name in autoloads:
		var path = autoloads[autoload_name]
		var node = get_node_or_null("/root/" + autoload_name)
		if node and ResourceLoader.exists(path):
			var new_script = load(path)
			if new_script:
				node.set_script(new_script)
				if node.has_method("_ready"):
					node._ready()
				print("[Bootloader] Autoload recargado en memoria: ", autoload_name)

	print("[Bootloader] PCK montado. Reiniciando árbol de forma nativa para recargar Autoloads...")
	get_tree().set_meta("pck_loaded_and_reloaded", true)
	
	# Cambiar a la misma escena del bootloader. Al recargarse la escena,
	# Godot recargará todos los Singletons usando los scripts del PCK montado.
	var err = get_tree().change_scene_to_file("res://scenes/Bootloader.tscn")
	if err != OK:
		print("[Bootloader-ERR] No se pudo recargar la escena del Bootloader de forma nativa.")

func _finish_bootloader_and_start():
	status_lbl.text = "Iniciando precalentamiento..."
	progress_bar.visible = false
	await get_tree().create_timer(0.2).timeout
	
	# 1. Instanciar la escena real de MainGame y añadirla a la raíz del árbol
	print("[Bootloader] Instanciando MainGame...")
	var main_game_scene = load("res://scenes/MainGame.tscn").instantiate()
	get_tree().root.add_child(main_game_scene)
	get_tree().current_scene = main_game_scene
	
	# 2. Lanzar el shader warmup manualmente en el VFXSystem cargado
	var vfx = get_node_or_null("/root/VFXSystem")
	if vfx and vfx.has_method("_run_shader_warmup"):
		# Destruir UI del Bootloader para que no tape la barra de compilación del shader warmup
		$BootloaderUI.queue_free()
		vfx._run_shader_warmup()
		print("[Bootloader] Traspasado control a VFXSystem para Shader Warmup.")
		
		# Liberar el Bootloader en sí
		queue_free()
	else:
		# Fallback
		print("[Bootloader-WARN] VFXSystem no disponible para shader warmup.")
		queue_free()

func _fail_and_load_game(msg: String):
	print("[Bootloader-WARN] Error: ", msg)
	status_lbl.text = msg + " Iniciando juego..."
	progress_bar.visible = false
	await get_tree().create_timer(2.0).timeout
	_load_existing_pck_if_any_and_start()
