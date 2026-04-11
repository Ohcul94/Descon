extends Node2D

# SpheresManager.gd - Sistema de Esferas Orbitales
# Maneja 3 esferas alrededor del personaje con habilidades y estadísticas.

var player = null
signal spheres_updated
var angle = 0.0
var radius = 80.0
var rotation_speed = 1.0

var spheres = []
var spheres_data = [
	{"name": "ESFERA ALFA", "type": "Movimiento", "color": Color(1, 0.8, 0), "equipped": null},
	{"name": "ESFERA BETA", "type": "Defensa", "color": Color.AQUA, "equipped": null},
	{"name": "ESFERA GAMMA", "type": "Curación", "color": Color.GREEN, "equipped": null}
]

func _ready():
	add_to_group("spheres_system")
	player = get_parent()
	_create_spheres()
	# v206.20: Desactivado para evitar sobrescribir los datos del servidor al entrar
	# _initialize_mock_skills()

func _initialize_mock_skills():
	# v201.0: Cargamos las clases externas de forma limpia y profesional
	spheres_data[0]["equipped"] = Skill_TurboImpulse.new()
	spheres_data[1]["equipped"] = Skill_ShieldCell.new()
	spheres_data[2]["equipped"] = Skill_RepairKit.new()
	
	_update_visuals()

func _create_spheres():
	for i in range(3):
		var s = Sprite2D.new()
		s.texture = load("res://icon.svg")
		s.scale = Vector2(0.2, 0.2)
		s.modulate = spheres_data[i]["color"]
		
		# Contenedor para el icono de la habilidad
		var icon_sprite = Sprite2D.new()
		icon_sprite.name = "Icon"
		icon_sprite.scale = Vector2(0.5, 0.5)
		icon_sprite.modulate = Color(1, 1, 1, 0.8) # Un poco transparente
		s.add_child(icon_sprite)
		
		add_child(s)
		spheres.append(s)

func _process(delta):
	if not player: return
	angle += rotation_speed * delta
	for i in range(3):
		var sphere_angle = angle + (i * TAU / 3.0)
		var target_pos = Vector2(cos(sphere_angle), sin(sphere_angle)) * radius
		spheres[i].position = target_pos
		var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.005 + i) * 0.1
		spheres[i].scale = Vector2(0.2, 0.2) * pulse

func use_skill(id: int):
	if id < 0 or id >= spheres_data.size(): return
	var skill = spheres_data[id]["equipped"]
	if skill and skill is SphereSkill:
		skill.activate(player)
		# Notificar al HUD si es necesario (se maneja vía Player.gd cooldowns)
		return true
	return false

func _update_visuals():
	for i in range(spheres.size()):
		var skill = spheres_data[i]["equipped"]
		var icon_node = spheres[i].get_node("Icon")
		if skill and skill is SphereSkill:
			if skill.icon:
				icon_node.texture = skill.icon
			else:
				# Placeholder visual si no hay icono (un puntito blanco)
				icon_node.texture = load("res://icon.svg")
			icon_node.visible = true
		else:
			icon_node.visible = false

func equip_item(sphere_id, item_data):
	if sphere_id >= 0 and sphere_id < 3:
		# Convertir dict a Resource si es necesario
		if item_data is Dictionary:
			var res = SphereSkill.new()
			res.skill_name = item_data.get("name", "Skill")
			res.type = spheres_data[sphere_id]["type"]
			# ... mapear resto de campos si vienen del servidor
			spheres_data[sphere_id]["equipped"] = res
		else:
			spheres_data[sphere_id]["equipped"] = item_data
		
		_update_visuals()
		if player and player.has_method("_recalculate_stats"):
			player._recalculate_stats()
		spheres_updated.emit() # v203.0: Uso explícito para silenciar el warning
