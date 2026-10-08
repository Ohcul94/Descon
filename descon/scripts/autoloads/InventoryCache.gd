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

# Íconos 2D de armas, escudos, motores, esferas, municiones y habilidades
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
	"res://assets/Esferas/EsferaAmarilla1.png",

	# Íconos de Municiones
	"res://assets/Municiones/Iconos/laser/Laser.png",
	"res://assets/Municiones/Iconos/missile/Missile.png",
	"res://assets/Municiones/Iconos/mine/Mine.png",
	"res://assets/Municiones/Iconos/melee/Melee.png",
	"res://assets/Municiones/Iconos/heal/Heal.png",
	"res://assets/Municiones/Iconos/siphon/Siphon.png",
	"res://assets/Municiones/Iconos/emp/Emp.png",
	"res://assets/Municiones/Iconos/electron/Electron.png",
	"res://assets/Municiones/Lasers/Laser1/Laser1.png",
	"res://assets/Municiones/Lasers/Laser2/Laser2.png",
	"res://assets/Municiones/Lasers/Laser2/Laser2-1.png",
	"res://assets/Municiones/Misiles/Misil1/Misil1.png",
	"res://assets/Municiones/Misiles/Misil2/Misil2.png",
	"res://assets/Municiones/Misiles/Misil2/Misil2-1.png",
	"res://assets/Municiones/Misiles/Misil3/Misil3.png",
	"res://assets/Municiones/Misiles/Misil3/Misil3-1.png",
	"res://assets/Municiones/Minas/Mina1/Mina1.png",
	"res://assets/Municiones/Minas/Mina2/Mina2.png",
	"res://assets/Municiones/Minas/Mina2/Mina2-1.png",
	"res://assets/Municiones/Minas/Mina3/Mina3.png",
	"res://assets/Municiones/Minas/Mina3/Mina3-1.png",
	"res://assets/Municiones/Siphon/Siphon1/Siphon1.png",

	# Íconos de Habilidades
	"res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png",
	"res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png",
	"res://assets/Skills/Iconos/Ataque/Provocacion/Provocacion.png",
	"res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"res://assets/Skills/Iconos/Cura/Baliza Curativa/Baliza Curativa.png",
	"res://assets/Skills/Iconos/Cura/Regeneracion Alfa/Regeneracion Alfa.png",
	"res://assets/Skills/Iconos/Cura/Vinculo Vital/Vinculo Vital.png",
	"res://assets/Skills/Iconos/Defensa/Barrera de Viento/Barrera de Viento.png",
	"res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
	"res://assets/Skills/Iconos/Defensa/Camino de Hielo/Camino de Hielo.png",
	"res://assets/Skills/Iconos/Defensa/Escudo Celular/Escudo Celular.png",
	"res://assets/Skills/Iconos/Utilidad/Destello/Destello.png",
	"res://assets/Skills/Iconos/Utilidad/Invisibilidad/Invisibilidad.png",
	"res://assets/Skills/Iconos/Utilidad/Invulnerabilidad/Invulnerabilidad.png",
	"res://assets/Skills/Iconos/Utilidad/Resurrecion/Resurrecion.png",
	"res://assets/Skills/Iconos/Utilidad/HyperDash/HyperDash.png",
	"res://assets/Skills/Iconos/Utilidad/Turbo Impulso/Turbo Impulso.png",

	# Texturas de Efectos Visuales de Skills
	"res://assets/Efectos de Skills/Reflect (Rojo)/Reflect Aura (Transp).png",
	"res://assets/Efectos de Skills/Reflect (Rojo)/Reflect (Transp).png",
	"res://assets/Efectos de Skills/Reflect (Rojo)/Reflect Aura.png",
	"res://assets/Efectos de Skills/Curacion(Transp).png",
	"res://assets/Efectos de Skills/Curacion.png",
	"res://assets/Efectos de Skills/Escudo(Transp).png",
	"res://assets/Efectos de Skills/Escudo.png",
	"res://assets/Efectos de Skills/Velocidad(Transp).png",
	"res://assets/Efectos de Skills/Velocidad.png",
	"res://assets/Skills/Marco Contenedor.png"
]

# Scripts de esferas y habilidades precargadas
static var SPHERE_SCRIPT_PATHS = [
	"res://scripts/resources/skills/Skill_AlphaRegen.gd",
	"res://scripts/resources/skills/Skill_Blink.gd",
	"res://scripts/resources/skills/Skill_FearSphere.gd",
	"res://scripts/resources/skills/Skill_FrostTrail.gd",
	"res://scripts/resources/skills/Skill_HealBeacon.gd",
	"res://scripts/resources/skills/Skill_HyperDash.gd",
	"res://scripts/resources/skills/Skill_Invulnerability.gd",
	"res://scripts/resources/skills/Skill_PlasmaBlast.gd",
	"res://scripts/resources/skills/Skill_Provocacion.gd",
	"res://scripts/resources/skills/Skill_Reflect.gd",
	"res://scripts/resources/skills/Skill_RegenPath.gd",
	"res://scripts/resources/skills/Skill_RepairKit.gd",
	"res://scripts/resources/skills/Skill_Resurreccion.gd",
	"res://scripts/resources/skills/Skill_ShieldCell.gd",
	"res://scripts/resources/skills/Skill_SmokeBomb.gd",
	"res://scripts/resources/skills/Skill_Stealth.gd",
	"res://scripts/resources/skills/Skill_TurboImpulse.gd",
	"res://scripts/resources/skills/Skill_VitalLink.gd",
	"res://scripts/resources/skills/Skill_WindBarrier.gd",
	"res://scripts/resources/skills/Skill_Hookshot.gd"
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

	# 3. Precargar íconos de equipamiento, habilidades, municiones y VFX 2D
	for path in EQUIPMENT_ICON_PATHS:
		if ResourceLoader.exists(path) and not _textures.has(path):
			var res = load(path)
			if res: _textures[path] = res

	# 4. Precargar scripts de esferas y habilidades
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

# Obtener ícono de ítem (Texture2D)
static func get_item_icon(item: Dictionary) -> Texture2D:
	if item.is_empty():
		return null

	var icon_path = str(item.get("icon", ""))
	if icon_path != "" and icon_path != "null":
		var tex = get_texture(icon_path)
		if tex != null:
			return tex

	var item_id = str(item.get("id", "")).to_lower()
	var emergency_map = {
		"las1": "res://assets/Armas/Arma1/Arma1.png", "las2": "res://assets/Armas/Arma2/Arma2.png", "las3": "res://assets/Armas/Arma3/Arma3.png",
		"las4": "res://assets/Armas/Arma4/Arma4.png", "las5": "res://assets/Armas/Arma5/Arma5.png", "las6": "res://assets/Armas/Arma6/Arma6.png",
		"sh1": "res://assets/Escudos/Escudo1/Escudo1.png", "sh2": "res://assets/Escudos/Escudo2/Escudo2.png", "sh3": "res://assets/Escudos/Escudo3/Escudo3.png",
		"sh4": "res://assets/Escudos/Escudo4/Escudo4.png", "sh5": "res://assets/Escudos/Escudo5/Escudo5.png", "sh6": "res://assets/Escudos/Escudo6/Escudo6.png",
		"en1": "res://assets/Motores/Motor1/Motor1.png", "en2": "res://assets/Motores/Motor2/Motor2.png", "en3": "res://assets/Motores/Motor3/Motor3.png",
		"esf_az": "res://assets/Esferas/EsferaAzul1.png", "esf_ro": "res://assets/Esferas/EsferaRoja1.png",
		"esf_ve": "res://assets/Esferas/EsferaVerde1.png", "esf_am": "res://assets/Esferas/EsferaAmarilla1.png"
	}
	if emergency_map.has(item_id):
		return get_texture(emergency_map[item_id])

	if item_id.begins_with("las"):
		var num = item_id.replace("las", "")
		return get_texture("res://assets/Armas/Arma" + num + "/Arma" + num + ".png")
	elif item_id.begins_with("sh"):
		var num = item_id.replace("sh", "")
		return get_texture("res://assets/Escudos/Escudo" + num + "/Escudo" + num + ".png")
	elif item_id.begins_with("en"):
		var num = item_id.replace("en", "")
		return get_texture("res://assets/Motores/Motor" + num + "/Motor" + num + ".png")

	# Búsqueda en GameConstants.SHOP_ITEMS si está disponible
	if typeof(GameConstants) != TYPE_NIL and "SHOP_ITEMS" in GameConstants:
		var shop = GameConstants.SHOP_ITEMS
		for cat_key in shop:
			var category = shop[cat_key]
			if category is Dictionary:
				for sub_key in category:
					var sub_list = category[sub_key]
					if sub_list is Array:
						for shop_item in sub_list:
							if str(shop_item.get("id", "")).to_lower() == item_id:
								var ic = str(shop_item.get("icon", ""))
								if ic != "":
									var t = get_texture(ic)
									if t: return t
			elif category is Array:
				for shop_item in category:
					if str(shop_item.get("id", "")).to_lower() == item_id:
						var ic = str(shop_item.get("icon", ""))
						if ic != "":
							var t = get_texture(ic)
							if t: return t

	return null
