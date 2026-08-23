extends Node2D

const SkillWindBarrierClass = preload("res://scripts/resources/skills/Skill_WindBarrier.gd")
const SkillHealBeaconClass = preload("res://scripts/resources/skills/Skill_HealBeacon.gd")
const SkillProvocacionClass = preload("res://scripts/resources/skills/Skill_Provocacion.gd")
const SkillResurreccionClass = preload("res://scripts/resources/skills/Skill_Resurreccion.gd")


var player = null
signal spheres_updated
var angle = 0.0
var radius = 80.0
var rotation_speed = 1.0

var spheres = []
var spheres_data = [
	{"name": "Slot 1", "type": "any", "color": Color.WHITE, "sphere": null, "equipped": null},
	{"name": "Slot 2", "type": "any", "color": Color.WHITE, "sphere": null, "equipped": null},
	{"name": "Slot 3", "type": "any", "color": Color.WHITE, "sphere": null, "equipped": null},
	{"name": "Slot 4", "type": "any", "color": Color.WHITE, "sphere": null, "equipped": null}
]


func _ready():
	add_to_group("spheres_system")
	player = get_parent()
	_create_spheres()
	
	# v6.2: Retraso de cortesía para asegurar que el HUD esté listo al loguear
	# No se emite spheres_updated aquí porque _update_3d_spheres ya se llama
	# al conectar la señal desde Entity.gd _ready(), evitando el re-flash de esferas.

func _create_spheres():
	# Inicialización de nodos base para 4 esferas dinámicas
	for i in range(4):
		var s = Sprite2D.new()
		s.visible = false
		
		var icon_sprite = Sprite2D.new()
		icon_sprite.name = "Icon"
		icon_sprite.scale = Vector2(0.5, 0.5)
		s.add_child(icon_sprite)
		
		add_child(s)
		spheres.append(s)


func _process(delta):
	if not player: return
	angle += rotation_speed * delta
	
	var is_3d_mode = player.world_root_3d != null
	
	for i in range(spheres.size()):
		if i >= spheres_data.size(): break
		
		var slot_data = spheres_data[i]
		var is_equipped = slot_data["equipped"] != null
		# v760.1: La esfera instalada se ve aunque el slot no tenga skill equipada
		var has_sphere = slot_data.get("sphere") != null
		var sphere_angle = angle + (i * TAU / float(spheres.size()))
		
		# Sincronización 2D (Sólo se ve si no hay 3D)
		spheres[i].visible = (is_equipped or has_sphere) and not is_3d_mode
		if is_equipped or has_sphere:
			spheres[i].position = Vector2(cos(sphere_angle), sin(sphere_angle)) * radius

func use_skill(id: int):
	if id < 0 or id >= spheres_data.size(): return
	var skill = spheres_data[id]["equipped"]
	if skill and (skill is SphereSkill or skill is Resource):
		if skill.has_method("activate"):
			skill.activate(player)
			return true
	return false

# v760.0: Nombre de color capitalizado de la esfera INSTALADA en un slot ("" si no hay)
func installed_color_name(slot_data) -> String:
	if typeof(slot_data) != TYPE_DICTIONARY: return ""
	var sp = slot_data.get("sphere")
	if sp == null or typeof(sp) != TYPE_DICTIONARY: return ""
	var c: String = str(sp.get("type", sp.get("sphereColor", ""))).to_lower()
	match c:
		"roja", "red": return "Roja"
		"azul", "blue": return "Azul"
		"verde", "green": return "Verde"
		"amarilla", "amarillo", "yellow": return "Amarilla"
	return ""

# v760.0: ¿El slot tiene una esfera física instalada?
func has_installed_sphere(slot_id: int) -> bool:
	if slot_id < 0 or slot_id >= spheres_data.size(): return false
	var sp = spheres_data[slot_id].get("sphere")
	return sp != null and typeof(sp) == TYPE_DICTIONARY and not sp.is_empty()

# v760.0: Actualización local optimista al instalar (el servidor es autoritativo)
func install_sphere(sphere_id: int, sphere_item):
	if sphere_id < 0 or sphere_id >= spheres_data.size(): return
	if typeof(sphere_item) != TYPE_DICTIONARY or sphere_item.is_empty(): return
	spheres_data[sphere_id]["sphere"] = sphere_item
	if sphere_item.has("type"):
		spheres_data[sphere_id]["type"] = sphere_item["type"]
	if sphere_item.has("color"):
		var c = sphere_item["color"]
		if typeof(c) == TYPE_STRING:
			c = c.replace("(", "").replace(")", "").replace(" ", "")
			if "," in c:
				var parts = c.split(",")
				if parts.size() >= 3:
					c = Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() > 3 else 1.0)
			else:
				c = Color(c)
		spheres_data[sphere_id]["color"] = c
	_update_visuals()
	spheres_updated.emit()

# v760.0: Actualización local optimista al retirar (el servidor es autoritativo)
func remove_sphere(sphere_id: int):
	if sphere_id < 0 or sphere_id >= spheres_data.size(): return
	spheres_data[sphere_id]["sphere"] = null
	spheres_data[sphere_id]["equipped"] = null
	spheres_data[sphere_id]["type"] = "any"
	spheres_data[sphere_id]["color"] = Color.WHITE
	_update_visuals()
	spheres_updated.emit()

# v760.0: Sincronización completa de un slot desde datos del servidor (esfera instalada + skill)
func apply_server_slot(sphere_id: int, slot_data):
	if sphere_id < 0 or sphere_id >= spheres_data.size(): return
	if typeof(slot_data) != TYPE_DICTIONARY: return
	
	var needs_update = false
	var cur_sphere = spheres_data[sphere_id].get("sphere")
	var new_sphere = slot_data.get("sphere")
	
	if new_sphere == null or (typeof(new_sphere) == TYPE_DICTIONARY and new_sphere.is_empty()):
		if cur_sphere != null:
			spheres_data[sphere_id]["sphere"] = null
			spheres_data[sphere_id]["type"] = slot_data.get("type", "any")
			needs_update = true
	elif typeof(new_sphere) == TYPE_DICTIONARY:
		var same_id = cur_sphere != null and str(cur_sphere.get("instanceId", cur_sphere.get("id", ""))) == str(new_sphere.get("instanceId", new_sphere.get("id", "")))
		if not same_id:
			spheres_data[sphere_id]["sphere"] = new_sphere
			spheres_data[sphere_id]["type"] = slot_data.get("type", new_sphere.get("type", "any"))
			needs_update = true
	
	# v235.60: Saneamiento de Sincronía de la skill equipada (Evitar recarga si es lo mismo)
	var real_equipped = slot_data.get("equipped")
	var current = spheres_data[sphere_id]["equipped"]
	var skill_needs_update = false
	
	if real_equipped == null or (typeof(real_equipped) == TYPE_DICTIONARY and real_equipped.is_empty()):
		if current != null:
			spheres_data[sphere_id]["equipped"] = null
			skill_needs_update = true
	else:
		var is_matching = false
		if typeof(real_equipped) == TYPE_DICTIONARY and current != null:
			if real_equipped.get("skill_name") == current.get("skill_name"):
				is_matching = true
		if not is_matching:
			spheres_data[sphere_id]["equipped"] = _build_skill_from_data(real_equipped)
			skill_needs_update = true
	
	if needs_update or skill_needs_update:
		_update_visuals()
		if player and player.has_method("_recalculate_stats"):
			player._recalculate_stats()
		spheres_updated.emit()
		
		# v6.1: Forzar actualización del HUD global si existe
		var hud = get_tree().get_first_node_in_group("hud")
		if is_instance_valid(hud) and hud.has_method("update_skill_slots"):
			hud.update_skill_slots()

# v760.0: Reconstruye la clase de skill a partir de un dict del servidor
func _build_skill_from_data(real_equipped) -> Resource:
	if typeof(real_equipped) != TYPE_DICTIONARY:
		return real_equipped
	var s_name = real_equipped.get("skill_name", "")
	
	# v3.9: Mapeo manual para asegurar persistencia al reloguear
	var skill_paths = {
		"TURBO-IMPULSO": "res://scripts/resources/skills/Skill_TurboImpulse.gd",
		"ESCUDO CELULAR": "res://scripts/resources/skills/Skill_ShieldCell.gd",
		"AUTO-REPARACIÓN": "res://scripts/resources/skills/Skill_RepairKit.gd",
		"REFLECT-OMEGA": "res://scripts/resources/skills/Skill_Reflect.gd",
		"NANO-REGENERACIÓN": "res://scripts/resources/skills/Skill_RegenPath.gd",
		"HYPER-DASH": "res://scripts/resources/skills/Skill_HyperDash.gd",
		"INVULNERABILIDAD": "res://scripts/resources/skills/Skill_Invulnerability.gd",
		"BLINK": "res://scripts/resources/skills/Skill_Blink.gd",
		"SMOKE-BOMB": "res://scripts/resources/skills/Skill_SmokeBomb.gd",
		"STEALTH": "res://scripts/resources/skills/Skill_Stealth.gd",
		"REGENERACIÓN ALFA": "res://scripts/resources/skills/Skill_AlphaRegen.gd",
		"BARRERA DE VIENTO": "res://scripts/resources/skills/Skill_WindBarrier.gd",
		"VÍNCULO VITAL": "res://scripts/resources/skills/Skill_VitalLink.gd",
		"BALIZA DE CURACION": "res://scripts/resources/skills/Skill_HealBeacon.gd",
		"PROVOCACION": "res://scripts/resources/skills/Skill_Provocacion.gd",
		"RESURRECCIÓN": "res://scripts/resources/skills/Skill_Resurreccion.gd",
		"ESFERA DE TERROR": "res://scripts/resources/skills/Skill_FearSphere.gd"
	}
	
	var s_class = null
	if skill_paths.has(s_name):
		var script = load(skill_paths[s_name])
		if script:
			s_class = script
	
	var res
	if s_class:
		res = s_class.new()
	else:
		res = SphereSkill.new()
		res.skill_name = s_name
		res.type = real_equipped.get("type", "Ataque")
	
	res.power_value = real_equipped.get("power_value", 0)
	return res

func _update_visuals():
	var is_3d_mode = player.get("world_root_3d") != null
	for i in range(spheres.size()):
		var slot_data = spheres_data[i]
		var skill = slot_data["equipped"]
		var sprite = spheres[i]
		var icon_node = sprite.get_node("Icon")
		
		# v760.1: El color de la esfera lo define la esfera FÍSICA instalada
		var color_name = installed_color_name(slot_data)
		var has_sphere = slot_data.get("sphere") != null
		
		# v760.1: Mostrar la esfera instalada aunque no haya skill equipada
		if has_sphere or skill:
			if color_name == "":
				color_name = "Amarilla"
			var s_path = "res://assets/Esferas/Esfera" + color_name + "1.png"
			
			if ResourceLoader.exists(s_path):
				sprite.texture = load(s_path)
			
			if skill and skill is Resource and skill.get("icon"):
				icon_node.texture = skill.icon
				icon_node.visible = not is_3d_mode
			else:
				icon_node.visible = false
			
			sprite.visible = not is_3d_mode
		else:
			icon_node.visible = false
			sprite.visible = false


func equip_item(sphere_id, item_data):
	if sphere_id >= 0 and sphere_id < 4:
		# v760.0: Si llega el slot completo por red, procesar esfera instalada + skill
		if typeof(item_data) == TYPE_DICTIONARY and (item_data.has("sphere") or item_data.has("equipped")):
			apply_server_slot(sphere_id, item_data)
			return
		
		# Extraer 'equipped' si viene toda la estructura de la esfera por red
		var real_equipped = item_data
		if typeof(item_data) == TYPE_DICTIONARY and item_data.has("equipped"):
			real_equipped = item_data.get("equipped")

		# v235.60: Saneamiento de Sincronía (Evitar recarga si es lo mismo)
		var current = spheres_data[sphere_id]["equipped"]
		var needs_update = false
		
		# Si viene null del servidor o diccionario vacío, desequipar visualmente
		if real_equipped == null or (typeof(real_equipped) == TYPE_DICTIONARY and real_equipped.is_empty()):
			if current != null:
				spheres_data[sphere_id]["equipped"] = null
				needs_update = true
		else:
			# Comparación profunda simple para evitar spam
			var is_matching = false
			if typeof(real_equipped) == TYPE_DICTIONARY and current != null:
				if real_equipped.get("skill_name") == current.get("skill_name"):
					is_matching = true
			
			if not is_matching:
				spheres_data[sphere_id]["equipped"] = _build_skill_from_data(real_equipped)
				needs_update = true

		if needs_update:
			_update_visuals()
			if player and player.has_method("_recalculate_stats"):
				player._recalculate_stats()
			spheres_updated.emit()
			
			# v6.1: Forzar actualización del HUD global si existe
			var hud = get_tree().get_first_node_in_group("hud")
			if is_instance_valid(hud) and hud.has_method("update_skill_slots"):
				hud.update_skill_slots()

func get_equipped_skill(id: int):
	if id >= 0 and id < spheres_data.size():
		return spheres_data[id]["equipped"]
	return null

# v760.0: La skill equipable debe coincidir con el color de la esfera instalada
func skill_matches_sphere(slot_id: int, skill_type: String) -> bool:
	if slot_id < 0 or slot_id >= spheres_data.size(): return false
	if not has_installed_sphere(slot_id): return false
	var color_name = installed_color_name(spheres_data[slot_id])
	var t: String = skill_type.to_lower()
	match color_name:
		"Roja": return t == "ataque"
		"Azul": return t == "defensa"
		"Verde": return t == "curación" or t == "curacion"
		"Amarilla": return t != "ataque" and t != "defensa" and t != "curación" and t != "curacion"
	return false
