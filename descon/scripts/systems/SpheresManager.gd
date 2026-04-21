extends Node2D

# SpheresManager.gd - Sistema de Esferas Orbitales
# Maneja 4 esferas alrededor del personaje con habilidades y estadísticas.

var player = null
signal spheres_updated
var angle = 0.0
var radius = 80.0
var rotation_speed = 1.0

var spheres = []
var spheres_data = [
	{"name": "Slot 1", "type": "any", "color": Color.WHITE, "equipped": null},
	{"name": "Slot 2", "type": "any", "color": Color.WHITE, "equipped": null},
	{"name": "Slot 3", "type": "any", "color": Color.WHITE, "equipped": null},
	{"name": "Slot 4", "type": "any", "color": Color.WHITE, "equipped": null}
]


func _ready():
	add_to_group("spheres_system")
	player = get_parent()
	_create_spheres()

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
		
		var is_equipped = spheres_data[i]["equipped"] != null
		var sphere_angle = angle + (i * TAU / float(spheres.size()))
		
		# Sincronización 2D (Sólo se ve si no hay 3D)
		spheres[i].visible = is_equipped and not is_3d_mode
		if is_equipped:
			spheres[i].position = Vector2(cos(sphere_angle), sin(sphere_angle)) * radius

func use_skill(id: int):
	if id < 0 or id >= spheres_data.size(): return
	var skill = spheres_data[id]["equipped"]
	if skill and (skill is SphereSkill or skill is Resource):
		if skill.has_method("activate"):
			skill.activate(player)
			return true
	return false

func _update_visuals():
	var is_3d_mode = player.get("world_root_3d") != null
	for i in range(spheres.size()):
		var skill = spheres_data[i]["equipped"]
		var sprite = spheres[i]
		var icon_node = sprite.get_node("Icon")
		
		if skill:
			# v235.40: Mapeo dinámico de textura según el tipo de habilidad
			var s_path = "res://assets/Esferas/EsferaAmarilla.png"
			var s_type = str(skill.type).to_lower()
			
			if s_type == "ataque": s_path = "res://assets/Esferas/EsferaRoja1.png"
			elif s_type == "defensa": s_path = "res://assets/Esferas/EsferaAzul1.png"
			elif s_type == "curación" or s_type == "curacion": s_path = "res://assets/Esferas/EsferaVerde.png"
			
			if ResourceLoader.exists(s_path):
				sprite.texture = load(s_path)
			
			if skill is Resource and skill.get("icon"):
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

				if typeof(real_equipped) == TYPE_DICTIONARY:
					var res = SphereSkill.new()
					res.skill_name = real_equipped.get("skill_name", "Skill")
					res.power_value = real_equipped.get("power_value", 0)
					res.type = real_equipped.get("type", "Ataque")
					spheres_data[sphere_id]["equipped"] = res
				else:
					spheres_data[sphere_id]["equipped"] = real_equipped
				needs_update = true

		if needs_update:
			_update_visuals()
			if player and player.has_method("_recalculate_stats"):
				player._recalculate_stats()
			spheres_updated.emit()
