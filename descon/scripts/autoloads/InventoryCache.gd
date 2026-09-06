class_name InventoryCache
extends Object

# ==============================================================================
# InventoryCache.gd - CACHÉ Y PRECARGA CENTRALIZADA PARA EL INVENTARIO (v1.0)
# Elimina los tirones y congelamientos al abrir pestañas o equipar ítems
# manteniendo en memoria todos los modelos 3D, texturas y scripts requeridos.
# ==============================================================================

static var _models: Dictionary = {}
static var _textures: Dictionary = {}
static var _scripts: Dictionary = {}
static var _is_preloaded: bool = false

# Modelos 3D de naves a precargar
static var SHIP_MODEL_PATHS = [
	"res://assets/Personajes/3D/Nave1/futuristic+jet+3d+model_Clone1.glb",
	"res://assets/Personajes/3D/Nave2/Nave2.glb",
	"res://assets/Personajes/3D/Nave3/Nave3.glb",
	"res://assets/Personajes/3D/Nave4/Nave4.glb",
	"res://assets/Personajes/3D/Nave5/Nave5.glb",
	"res://assets/Personajes/3D/Nave6/Nave6.glb",
	"res://assets/Personajes/3D/Nave7/Nave7.glb",
	"res://assets/Personajes/3D/Nave8/Nave8.glb",
	"res://assets/Personajes/3D/Nave9/Nave9.glb",
	"res://assets/Personajes/3D/Nave10/Nave10.glb",
	"res://assets/Personajes/3D/Nave11/Nave11.glb",
	"res://assets/Personajes/3D/Nave12/Nave12.glb"
]

# Modelos 3D de esferas orbitales
static var SPHERE_MODEL_PATHS = [
	"res://assets/Esferas/3D/EsferaAzul/EsferaAzul.glb",
	"res://assets/Esferas/3D/EsferaRoja/EsferaRoja.glb",
	"res://assets/Esferas/3D/EsferaVerde/EsferaVerde.glb",
	"res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla.glb"
]

# Íconos 2D de armas, escudos y motores
static var EQUIPMENT_ICON_PATHS = [
	"res://assets/Armas/Arma1/Arma1.png",
	"res://assets/Armas/Arma2/Arma2.png",
	"res://assets/Armas/Arma3/Arma3.png",
	"res://assets/Armas/Arma4/Arma4.png",
	"res://assets/Armas/Arma5/Arma5.png",
	"res://assets/Armas/Arma6/Arma6.png",
	"res://assets/Escudos/Escudo1/Escudo1.png",
	"res://assets/Escudos/Escudo2/Escudo2.png",
	"res://assets/Escudos/Escudo3/Escudo3.png",
	"res://assets/Escudos/Escudo4/Escudo4.png",
	"res://assets/Escudos/Escudo5/Escudo5.png",
	"res://assets/Escudos/Escudo6/Escudo6.png",
	"res://assets/Motores/Motor1/Motor1.png",
	"res://assets/Motores/Motor2/Motor2.png",
	"res://assets/Motores/Motor3/Motor3.png",
	"res://assets/Esferas/EsferaAzul1.png",
	"res://assets/Esferas/EsferaRoja1.png",
	"res://assets/Esferas/EsferaVerde1.png",
	"res://assets/Esferas/EsferaAmarilla1.png"
]

# Scripts de esferas y habilidades
static var SPHERE_SCRIPT_PATHS = [
	"res://scripts/resources/skills/Skill_HealBeacon.gd",
	"res://scripts/resources/skills/Skill_Reflect.gd",
	"res://scripts/resources/skills/Skill_FearSphere.gd"
]

# Precargar todos los recursos en memoria
static func preload_all() -> void:
	if _is_preloaded:
		return
	_is_preloaded = true

	# 1. Precargar modelos 3D de naves
	for path in SHIP_MODEL_PATHS:
		if ResourceLoader.exists(path) and not _models.has(path):
			var res = load(path)
			if res: _models[path] = res

	# 2. Precargar modelos 3D de esferas
	for path in SPHERE_MODEL_PATHS:
		if ResourceLoader.exists(path) and not _models.has(path):
			var res = load(path)
			if res: _models[path] = res

	# 3. Precargar íconos de equipamiento 2D
	for path in EQUIPMENT_ICON_PATHS:
		if ResourceLoader.exists(path) and not _textures.has(path):
			var res = load(path)
			if res: _textures[path] = res

	# 4. Precargar scripts de esferas
	for path in SPHERE_SCRIPT_PATHS:
		if ResourceLoader.exists(path) and not _scripts.has(path):
			var res = load(path)
			if res: _scripts[path] = res

	print("[InventoryCache] Precarga completa: %d modelos, %d texturas, %d scripts en memoria." % [
		_models.size(), _textures.size(), _scripts.size()
	])

# Obtener modelo 3D precalentado
static func get_model(path: String) -> PackedScene:
	if path == "": return null
	if _models.has(path):
		return _models[path]
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is PackedScene:
			_models[path] = res
			return res
	return null

# Obtener textura 2D precalentada
static func get_texture(path: String) -> Texture2D:
	if path == "": return null
	if _textures.has(path):
		return _textures[path]
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			_textures[path] = res
			return res
	return null

# Obtener script precalentado
static func get_cached_script(path: String) -> Script:
	if path == "": return null
	if _scripts.has(path):
		return _scripts[path]
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Script:
			_scripts[path] = res
			return res
	return null
