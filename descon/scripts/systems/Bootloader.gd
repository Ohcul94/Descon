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
	# Configurar IP según entorno (Editor corre local, builds compilados corren contra Oracle Cloud)
	if OS.has_feature("editor"):
		target_ip = "127.0.0.1"
	
	# Detectar plataforma
	var os_name = OS.get_name()
	if os_name == "Android":
		platform_key = "android"
	else:
		platform_key = "windows"
		
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
	# Leer versión local
	var local_version = "0"
	if FileAccess.file_exists(LOCAL_MANIFEST_PATH):
		var file = FileAccess.open(LOCAL_MANIFEST_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			local_version = json.data.get("version", "0")
			
	var remote_version = remote_manifest.get("version", "0")
	var packages = remote_manifest.get("packages", {})
	
	if not packages.has(platform_key):
		print("[Bootloader] No hay paquete para la plataforma actual: ", platform_key)
		_load_existing_pck_if_any_and_start()
		return

	var package_info = packages[platform_key]
	var pck_exists = FileAccess.file_exists(PCK_SAVE_PATH)
	
	# Si la versión remota es diferente, o el archivo PCK local no existe físicamente
	if local_version != remote_version or not pck_exists:
		print("[Bootloader] Actualización disponible. Local: ", local_version, " | Remota: ", remote_version)
		_download_pck(package_info)
	else:
		print("[Bootloader] El juego ya está actualizado.")
		_load_existing_pck_if_any_and_start()

func _download_pck(package_info: Dictionary):
	var file_name = package_info.get("file")
	total_bytes = package_info.get("size", 0)
	var url = "http://" + target_ip + ":" + str(SERVER_PORT) + "/cdn/" + file_name
	
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
	file.store_string(JSON.stringify(remote_manifest))
	
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
	else:
		print("[Bootloader-ERR] Fallo al montar el PCK local.")
		
	_finish_bootloader_and_start()

func _reload_autoloads():
	print("[Bootloader] Recargando Singletons...")
	var autoloads = [
		{"name": "NetworkManager", "path": "res://scripts/autoloads/NetworkManager.gd"},
		{"name": "AudioManager", "path": "res://scripts/autoloads/AudioManager.gd"},
		{"name": "GameConstants", "path": "res://scripts/autoloads/Constants.gd"},
		{"name": "PartyManager", "path": "res://scripts/systems/PartyManager.gd"},
		{"name": "VFXSystem", "path": "res://scripts/systems/VFXManager.gd"},
		{"name": "SettingsManager", "path": "res://scripts/autoloads/SettingsManager.gd"}
	]
	
	var root = get_tree().root
	for item in autoloads:
		var singleton_name = item["name"]
		var path = item["path"]
		
		# 1. Si existe la instancia vieja, la removemos y liberamos
		if root.has_node(singleton_name):
			var old_node = root.get_node(singleton_name)
			
			# Si el nodo es VFXSystem, llamamos a la limpieza de la cinemática
			if singleton_name == "VFXSystem" and old_node.has_method("cleanup_cinematic"):
				old_node.cleanup_cinematic()
				
			root.remove_child(old_node)
			old_node.queue_free()
			print("[Bootloader] Eliminado Singleton viejo: ", singleton_name)
			
		# 2. Cargar el script (que ahora se leerá del PCK montado en res://)
		var script = load(path)
		if script:
			var new_node = Node.new()
			new_node.name = singleton_name
			new_node.set_script(script)
			root.add_child(new_node)
			print("[Bootloader] Re-inicializado Singleton: ", singleton_name)
		else:
			print("[Bootloader-ERR] No se pudo cargar script actualizado para: ", path)

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
