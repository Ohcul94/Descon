extends Area2D
class_name Projectile

# Projectile.gd (v141.71 - VECTOR RENDERING & RECOVERY)
# Clase base para todos los proyectiles. 

@export var speed: float = 800.0
@export var damage: float = 10.0
@export var owner_id: String = ""
@export var type: String = "laser" # laser, missile, mine

var owner_type: String = "player"
var enemy_type: int = 1 # v226.40: Atributo crítico para sincronía de daño
var velocity: Vector2 = Vector2.ZERO
var sprite: Sprite2D = null
var _has_hit: bool = false
var max_range: float = 0.0
var _start_pos: Vector2 = Vector2.ZERO
var target_id: String = "" # v266.450: Soporte para Homing (Rastreo)
var _target_node: Node2D = null
var _owner_node: Node2D = null
var _chain_visual: Line2D = null
var lifetime: float = 6.0 # v266.460: Tiempo de vida máximo del misil
var _current_lifetime: float = 0.0
var turn_speed: float = 2.5 # v266.505: Velocidad de rotación angular (Agilidad)
var is_homing: bool = false # v266.800: Switch de rastreo dinámico
var orbit_target: Node2D = null # v266.992: Objetivo al que orbitamos
var orbit_radius: float = 150.0
var orbit_speed: float = 2.0
var orbit_angle_offset: float = 0.0
var orbit_start_time: float = 0.0
var strike_id: String = "" # v266.995: ID único de ráfaga para evitar colisiones lógicas
var _start_time_stamp: float = 0.0
var _find_target_timer: float = 0.0


func _ready():
	add_to_group("projectiles")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	queue_redraw()

func setup(p_pos: Vector2, p_angle: float, p_data: Dictionary):
	global_position = p_pos
	rotation = p_angle
	type = p_data.get("bulletType", p_data.get("type", "laser"))
	owner_id = str(p_data.get("enemyId", p_data.get("id", p_data.get("senderId", p_data.get("entityId", "")))))
	owner_type = p_data.get("owner_type", "player")
	enemy_type = int(p_data.get("enemyType", 1))
	
	speed = float(p_data.get("bulletSpeed", p_data.get("speed", 800.0)))
	if speed <= 0 and (type == "missile" or type == "ice_missile"):
		speed = 450.0 # v266.520: Velocidad de crucero segura si no hay config
		
	max_range = float(p_data.get("range", 600.0))
	target_id = str(p_data.get("targetId", ""))
	
	# v266.510: Localizar nodo objetivo (Reforzado v3)
	_find_target()
	
	# v266.500: Configuración Dinámica (Combustible y Agilidad)
	lifetime = float(p_data.get("lifetimeMs", 0.0)) / 1000.0
	turn_speed = float(p_data.get("turnSpeed", 2.5))
	is_homing = bool(p_data.get("isHoming", false))
	
	var world = get_tree().get_first_node_in_group("world_node")
	
	# v266.992: Soporte para Órbita inicial
	if p_data.get("isOrbiting", false):
		if is_instance_valid(world):
			var ent_node = world.get("entities_node")
			if ent_node:
				for e in ent_node.get_children():
					if str(e.get("entity_id")) == owner_id:
						orbit_target = e
						break
		orbit_radius = float(p_data.get("orbitRadius", 150.0))
		orbit_speed = float(p_data.get("orbitSpeed", 2.0))
		orbit_angle_offset = float(p_data.get("orbitAngleOffset", 0.0))
		orbit_start_time = Time.get_ticks_msec() / 1000.0
	
	strike_id = str(p_data.get("strikeId", ""))
	if p_data.has("stunDuration"): set_meta("stunDuration", p_data.stunDuration)
	
	damage = p_data.get("damageBoost", p_data.get("damage", 10.0))
	_start_pos = p_pos
	_start_time_stamp = Time.get_ticks_msec() / 1000.0
	if type == "melee":
		lifetime = 0.35
	
	if type == "mega_laser":
		velocity = Vector2.ZERO
		speed = 0.0
	else:
		velocity = Vector2.RIGHT.rotated(p_angle) * speed

	
	# v266.610: Configuración de Colisión Dinámica en setup()
	var shape = CollisionShape2D.new()
	if type == "mega_laser":
		var rect = RectangleShape2D.new()
		# El tamaño se ajustará en _setup_visual_sprite
		shape.shape = rect
	else:
		var circle = CircleShape2D.new()
		circle.radius = 20.0 
		shape.shape = circle
	add_child(shape)
	
	collision_layer = 0
	
	# v269.30: Búsqueda de Dueño para efectos visuales (Cadena de Gancho)
	if is_instance_valid(world):
		var ent_node = world.get("entities_node")
		if ent_node:
			for e in ent_node.get_children():
				if str(e.get("entity_id")) == owner_id:
					_owner_node = e
					break
	
	if type == "hook":
		_chain_visual = Line2D.new()
		_chain_visual.width = 2.0
		_chain_visual.default_color = Color(0.6, 0.6, 0.6, 0.6)
		_chain_visual.z_index = -1
		_chain_visual.top_level = true
		add_child(_chain_visual)
	if owner_type == "player" or owner_type == "remote":
		# v220.82: Ahora los jugadores pueden impactar NPCs (2) y otros Players (1) para PvP
		collision_mask = 1 | 2 
	else:
		collision_mask = 1 # Los enemigos solo pegan a Players
	_setup_visual_sprite()
	queue_redraw()

func _setup_visual_sprite():
	if is_instance_valid(sprite): sprite.queue_free()
	
	var path = ""
	match type:
		"laser": path = "res://assets/Municiones/Lasers/Laser1/Laser1.png"
		"missile": path = "res://assets/Municiones/Misiles/Misil1/Misil1.png"
		"ice_missile": path = "res://assets/Municiones/Misiles/Misil1/Misil1.png"
		"mine": path = "res://assets/Municiones/Minas/Mina1/Mina1.png"
		"orbital_mine": path = "res://assets/Municiones/Minas/Mina3/Mina3.png"
		"melee": path = "res://assets/Municiones/Lasers/Laser2/Laser2.png"
		"heal": path = "res://assets/Municiones/Minas/Mina2/Mina2.png"
		"siphon": path = "res://assets/Municiones/Misiles/Misil2/Misil2.png"
		"emp": path = "res://assets/Municiones/Misiles/Misil3/Misil3.png"
		"hook": 
			path = "res://assets/Municiones/Minas/Mina2/Mina2.png"
			modulate = Color(0, 1, 1) # v269.40: Cian Neón para diferenciar del láser rojo
		"mega_laser":
			var beam = Line2D.new()
			beam.width = 40.0
			beam.default_color = Color(1, 0.2, 0.2, 0.8) # Rojo Lux
			var length = max_range if max_range > 0.0 else 1000.0
			beam.points = PackedVector2Array([Vector2.ZERO, Vector2(length, 0)])
			
			# Efecto de brillo (Glow)
			var glow = Line2D.new()
			glow.width = 15.0
			glow.default_color = Color(1, 1, 1, 0.9) # Centro blanco
			glow.points = beam.points
			beam.add_child(glow)
			
			add_child(beam)
			
			# Ajustar colisión al tamaño del rayo
			for child in get_children():
				if child is CollisionShape2D and child.shape is RectangleShape2D:
					child.shape.size = Vector2(length, 40.0)
					child.position.x = child.shape.size.x / 2.0
			return
	
	if path != "" and ResourceLoader.exists(path):
		sprite = Sprite2D.new()
		var tex = load(path)
		sprite.texture = tex
		
		# Tamaños ajustados para que las proporciones no sobrepasen las naves (160px)
		var target_size = 48.0
		if type == "mine" or type == "orbital_mine": target_size = 64.0
		elif type == "missile": target_size = 56.0
		
		var s = target_size / max(tex.get_width(), tex.get_height())
		if type == "orbital_mine": s = 0.08 # Mantener escala de captura aprobada
		sprite.scale = Vector2(s, s)
		
		# Ajuste de orientación. Los renders "desde arriba" del usuario están a -90 grados respecto del este
		sprite.rotation_degrees = 90
		
		if type == "ice_missile":
			sprite.modulate = Color(0.4, 0.7, 1.0) # Celeste Hielo
		elif type == "melee":
			sprite.modulate = Color(1.0, 0.65, 0.1) # Naranja/Amarillo Fuego
		elif type == "heal":
			sprite.modulate = Color(0.2, 0.9, 0.3) # Verde Esmeralda Curación
		elif type == "siphon":
			sprite.modulate = Color(0.8, 0.15, 0.9) # Magenta/Púrpura Vampírico
		elif type == "emp":
			sprite.modulate = Color(0.1, 0.5, 1.0) # Azul Eléctrico EMP
		elif owner_type == "enemy":
			if type == "orbital_mine": sprite.modulate = Color(1.2, 1.2, 1.2) # Blanco brillante neón
			else: sprite.modulate = Color(1.0, 0.3, 0.3) # Rojo para enemigos
		else:
			sprite.modulate = Color(0.3, 1.0, 1.0) # Cyan para jugadores
		
		add_child(sprite)
 
func _draw():
	if is_instance_valid(sprite): return
	var color = Color.WHITE
	if type == "ice_missile": color = Color(0.4, 0.7, 1.0)
	elif type == "melee": color = Color(1.0, 0.65, 0.1)
	elif type == "heal": color = Color(0.2, 0.9, 0.3)
	elif type == "siphon": color = Color(0.8, 0.15, 0.9)
	elif type == "emp": color = Color(0.1, 0.5, 1.0)
	elif owner_type == "enemy": color = Color(1.0, 0.3, 0.3)
	else: color = Color(0.3, 1.0, 1.0)
 
	match type:
		"laser":
			draw_rect(Rect2(Vector2(-10, -2.5), Vector2(20, 5)), color)
		"missile", "ice_missile":
			draw_line(Vector2(-10, 0), Vector2(10, 0), color, 6.0)
		"mine":
			draw_circle(Vector2.ZERO, 10, Color.WHITE)
			draw_circle(Vector2.ZERO, 12, Color(1, 1, 1, 0.3), false, 3.0)
		"hook":
			# Dibujar un gancho procedural si no hay asset
			draw_line(Vector2(0, 0), Vector2(-20, 0), Color.GRAY, 2.0)
			draw_arc(Vector2(5, 0), 10, -PI/2, PI/2, 8, Color.GRAY, 3.0)
		"melee":
			# Dibujar un arco de plasma semicircular (cuchilla de energía)
			draw_arc(Vector2.ZERO, 15.0, -PI/3, PI/3, 8, color, 4.0)
			draw_line(Vector2(0, -10), Vector2(7, 0), color, 3.0)
			draw_line(Vector2(0, 10), Vector2(7, 0), color, 3.0)
		"heal":
			# Círculo verde brillante con una cruz médica en el centro
			draw_circle(Vector2.ZERO, 8.0, color)
			draw_circle(Vector2.ZERO, 12.0, Color(color.r, color.g, color.b, 0.3), false, 2.0)
			draw_line(Vector2(-4, 0), Vector2(4, 0), Color.WHITE, 2.0)
			draw_line(Vector2(0, -4), Vector2(0, 4), Color.WHITE, 2.0)
		"siphon":
			# Núcleo oscuro y rombo/espiral magenta
			draw_circle(Vector2.ZERO, 6.0, color)
			draw_rect(Rect2(Vector2(-6, -6), Vector2(12, 12)), Color(color.r, color.g, color.b, 0.4), false, 2.0)
			draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.1, 0.3, 0.4), false, 1.5)
		"emp":
			# Esfera eléctrica con un anillo disruptor y rayos hacia afuera
			draw_circle(Vector2.ZERO, 8.0, Color.WHITE)
			draw_circle(Vector2.ZERO, 13.0, color, false, 2.0)
			# Pequeños pulsos
			draw_line(Vector2(-10, -3), Vector2(-4, 3), color, 1.5)
			draw_line(Vector2(4, -3), Vector2(10, 3), color, 1.5)
			draw_line(Vector2(-3, -10), Vector2(3, -4), color, 1.5)
			draw_line(Vector2(-3, 4), Vector2(3, 10), color, 1.5)

func release_orbit():
	orbit_target = null
	# v266.992: Al poner orbit_target en null, empezará a moverse linealmente

func _physics_process(delta):
	# v266.992: Lógica de Órbita (Seguir al enemigo antes de disparar)
	if is_instance_valid(orbit_target):
		var time = (Time.get_ticks_msec() / 1000.0) - orbit_start_time
		var angle = time * orbit_speed + orbit_angle_offset
		global_position = orbit_target.global_position + Vector2(cos(angle), sin(angle)) * orbit_radius
		rotation = angle
		velocity = Vector2.RIGHT.rotated(rotation) * speed # Preparar velocidad para cuando suelte
		return

	# v269.35: Actualizar visual de la cadena del Gancho
	if is_instance_valid(_chain_visual) and is_instance_valid(_owner_node):
		_chain_visual.points = PackedVector2Array([_owner_node.global_position, global_position])

	if lifetime > 0:
		_current_lifetime += delta
		if _current_lifetime >= lifetime:
			queue_free()
			return

	# v266.510: Re-intentar búsqueda si el objetivo se perdió o no se encontró al nacer
	if target_id != "" and not is_instance_valid(_target_node):
		_find_target_timer += delta
		if _find_target_timer >= 0.25:
			_find_target_timer = 0.0
			_find_target()

	# v266.800: Lógica de RASTREO (Homing) v3 - Ahora depende del switch is_homing
	if is_homing and is_instance_valid(_target_node):
		var target_pos = _target_node.global_position
		if _target_node.get_meta("is_single_world", false) and is_instance_valid(_target_node.get("world_root_3d")):
			target_pos = _get_visual_position_of(_target_node)
		
		var target_angle = (target_pos - global_position).angle()
		
		# rotate_toward garantiza que gire a una velocidad constante (turn_speed en radianes por segundo)
		rotation = rotate_toward(rotation, target_angle, turn_speed * delta)
		velocity = Vector2.RIGHT.rotated(rotation) * speed
	
	# Efecto de Fricción Fuerte para desplegar minas estáticas a corta distancia
	elif type == "mine":
		velocity = velocity.lerp(Vector2.ZERO, 3.5 * delta)
	elif type == "melee":
		velocity = velocity.lerp(Vector2.ZERO, 6.0 * delta)
		
	var move_step = velocity * delta
	if type == "heal":
		var time = (Time.get_ticks_msec() / 1000.0) - _start_time_stamp
		var wave_offset = sin(time * 15.0) * 8.0
		var perp = Vector2(-velocity.y, velocity.x).normalized()
		global_position += move_step + perp * (wave_offset * delta * 60.0)
	elif type == "siphon":
		var time = (Time.get_ticks_msec() / 1000.0) - _start_time_stamp
		var wave_offset = cos(time * 20.0) * 6.0
		var perp = Vector2(-velocity.y, velocity.x).normalized()
		global_position += move_step + perp * (wave_offset * delta * 60.0)
	else:
		global_position += move_step

	
	# v3.5: Límite de Rango (Auto-destrucción) - Ignorar para minas (ellas solo se frenan)
	if max_range > 0:
		var dist = global_position.distance_to(_start_pos)
		if dist >= max_range:
			if type == "mine":
				# v269.10: Posicionamiento de Precisión - Clavar la mina en el punto exacto
				global_position = _start_pos + (_start_pos.direction_to(global_position) * max_range)
				velocity = Vector2.ZERO
			else:
				queue_free()
	
	# v311.1: Evitar autodestrucción prematura en mapas masivos dinámicos de eventos (20k x 20k)
	var max_map_limit = 35000.0
	var active_map = get_tree().get_first_node_in_group("map")
	if is_instance_valid(active_map) and "world_size" in active_map:
		max_map_limit = float(active_map.world_size) * 1.6
		
	if global_position.length() > max_map_limit: 
		queue_free()

func _get_visual_position_of(entity: Node) -> Vector2:
	if is_instance_valid(entity):
		if entity.has_method("get_visual_position"):
			return entity.get_visual_position()
		return entity.global_position
	return Vector2.ZERO

func _on_body_entered(body):
	if _has_hit: return
	
	if body.has_method("take_damage"):
		if body.get("is_dead") == true: return
		var body_eid = ""
		if "entity_id" in body: body_eid = str(body.entity_id)
		
		# v266.996: Margen de seguridad para evitar que exploten por sacudidas de otros impactos
		if type == "orbital_mine":
			var age = (Time.get_ticks_msec() / 1000.0) - orbit_start_time
			if age < 0.3: return # No explotar en los primeros 300ms de vida
		
		# No pegarse a sí mismo
		if body_eid == owner_id: return
		
		# v221.45: Determinar si es combate PvP y si ambos consienten
		var is_pvp_target = body.is_in_group("remote_players") or body.is_in_group("player")
		
		if is_pvp_target:
			# v221.80: SÓLO chequear consentimiento si el atacante es OTRO JUGADOR (player o remote)
			if owner_type == "player" or owner_type == "remote":
				var attacker_has_pvp = false
				var target_has_pvp = false
				
				if "pvp_status" in body: target_has_pvp = body.pvp_status
				
				# Buscar al dueño de la bala para verificar SU pvp_status actualizado
				for entity in get_tree().get_nodes_in_group("entities"):
					if str(entity.entity_id) == owner_id:
						if "pvp_status" in entity: attacker_has_pvp = entity.pvp_status
						break
				
				if not (attacker_has_pvp and target_has_pvp):
					# v222.20: EFECTO FANTASMA - Si no hay mutuo acuerdo, solo atravesamos
					return
		
		# SI LLEGAMOS AQUÍ: El impacto es válido (es NPC o es PvP legal)
		_has_hit = true
		if body.is_in_group("player"):
			print("[PROJ-DEBUG] Impactando player con daño: ", damage, " de ", owner_id)
		body.take_damage(damage, global_position, owner_id)

		
		# Notificar al servidor
		if NetworkManager:
			if owner_type == "player" and body.is_in_group("enemies"):
				NetworkManager.send_event("enemyHit", {"enemyId": body.entity_id, "damage": damage})
			elif owner_type == "player" and is_pvp_target:
				NetworkManager.send_event("playerHitByPlayer", {"victimId": body.entity_id, "damage": damage})
			elif owner_type == "enemy" and body.is_in_group("player"):
				NetworkManager.send_event("playerHitByEnemy", {
					"damage": damage, 
					"attackerType": owner_type,
					"enemyType": enemy_type, # v226.41: Informar qué bicho pegó para validar daño
					"bulletType": type, # v266.182: Informar si es hielo o especial
					"attackerId": owner_id,
					"stunDuration": float(get_meta("stunDuration", 0)) if has_meta("stunDuration") else 0.0
				})
		
		_explode()
	elif body.is_in_group("obstacles"):
		_explode()

var _is_exploding: bool = false

func _explode():
	if type == "emp" and not _is_exploding:
		_is_exploding = true
		velocity = Vector2.ZERO
		collision_mask = 0
		collision_layer = 0
		var tw = create_tween().set_parallel(true)
		if is_instance_valid(sprite):
			tw.tween_property(sprite, "scale", sprite.scale * 3.0, 0.25)
			tw.tween_property(sprite, "modulate:a", 0.0, 0.25)
		await tw.finished
	queue_free()


func _find_target():
	if target_id == "": return
	
	# 1. ¿Soy yo?
	if NetworkManager and target_id == str(NetworkManager.my_socket_id):
		_target_node = get_tree().get_first_node_in_group("player")
		if is_instance_valid(_target_node): return

	# 2. Buscar en entidades por ID
	var entities = get_tree().get_nodes_in_group("entities")
	for e in entities:
		if e.has_method("get") and str(e.get("entity_id")) == target_id:
			_target_node = e
			return
			
	# 3. Fallback: Si soy el único jugador en el mapa, yo debo ser el blanco
	if _target_node == null:
		_target_node = get_tree().get_first_node_in_group("player")

func _on_area_entered(area):
	if _has_hit: return
	if area.is_in_group("altar") and owner_type == "enemy":
		_has_hit = true
		if NetworkManager:
			print("[PROJ] Impactando Altar con daño: ", damage)
			NetworkManager.send_event("altarHit", {"damage": damage})
		_explode()
