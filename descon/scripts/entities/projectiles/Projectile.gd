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
var lifetime: float = 6.0 # v266.460: Tiempo de vida máximo del misil
var _current_lifetime: float = 0.0
var turn_speed: float = 2.5 # v266.505: Velocidad de rotación angular (Agilidad)

func _ready():
	add_to_group("projectiles")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
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
		
	max_range = float(p_data.get("range", 0.0))
	target_id = str(p_data.get("targetId", ""))
	
	# v266.510: Localizar nodo objetivo (Reforzado v3)
	_find_target()
	
	# v266.500: Configuración Dinámica (Combustible y Agilidad)
	lifetime = float(p_data.get("lifetimeMs", 0.0)) / 1000.0
	turn_speed = float(p_data.get("turnSpeed", 2.5))
	
	damage = p_data.get("damageBoost", p_data.get("damage", 10.0))
	_start_pos = p_pos
	
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
		if type == "mine": target_size = 64.0
		elif type == "missile": target_size = 56.0
		
		var s = target_size / max(tex.get_width(), tex.get_height())
		sprite.scale = Vector2(s, s)
		
		# Ajuste de orientación. Los renders "desde arriba" del usuario están a -90 grados respecto del este
		sprite.rotation_degrees = 90
		
		if type == "ice_missile":
			sprite.modulate = Color(0.4, 0.7, 1.0) # Celeste Hielo
		elif owner_type == "enemy":
			sprite.modulate = Color(1.0, 0.3, 0.3) # Rojo para enemigos
		else:
			sprite.modulate = Color(0.3, 1.0, 1.0) # Cyan para jugadores
		
		add_child(sprite)

func _draw():
	if is_instance_valid(sprite): return
	var color = Color.WHITE
	if type == "ice_missile": color = Color(0.4, 0.7, 1.0)
	elif owner_type == "enemy": color = Color(1.0, 0.3, 0.3)
	else: color = Color(0.3, 1.0, 1.0)

	match type:
		"laser":
			draw_rect(Rect2(Vector2(-10, -2.5), Vector2(20, 5)), color)
		"missile", "ice_missile":
			draw_line(Vector2(-10, 0), Vector2(10, 0), color, 6.0)
			draw_circle(Vector2(10, 0), 4, color)
		"mine":
			draw_circle(Vector2.ZERO, 10, Color.WHITE)
			draw_circle(Vector2.ZERO, 12, Color(1, 1, 1, 0.3), false, 3.0)

func _physics_process(delta):
	if lifetime > 0:
		_current_lifetime += delta
		if _current_lifetime >= lifetime:
			queue_free()
			return

	# v266.510: Re-intentar búsqueda si el objetivo se perdió o no se encontró al nacer
	if target_id != "" and not is_instance_valid(_target_node):
		_find_target()

	# v266.505: Lógica de RASTREO (Homing) v2 - Basada en Rotación Angular
	if (type == "missile" or type == "ice_missile") and is_instance_valid(_target_node):
		var target_angle = (_target_node.global_position - global_position).angle()
		
		# rotate_toward garantiza que gire a una velocidad constante (turn_speed en radianes por segundo)
		rotation = rotate_toward(rotation, target_angle, turn_speed * delta)
		velocity = Vector2.RIGHT.rotated(rotation) * speed
	
	# Efecto de Fricción Fuerte para desplegar minas estáticas a corta distancia
	elif type == "mine":
		velocity = velocity.lerp(Vector2.ZERO, 3.5 * delta)
		
	global_position += velocity * delta
	
	# v3.5: Límite de Rango (Auto-destrucción)
	if max_range > 0:
		var dist = global_position.distance_to(_start_pos)
		if dist >= max_range:
			queue_free()
	
	if global_position.length() > 15000: 
		queue_free()

func _on_body_entered(body):
	if _has_hit: return
	
	if body.has_method("take_damage"):
		var body_eid = ""
		if "entity_id" in body: body_eid = str(body.entity_id)
		
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
			if (owner_type == "player" or owner_type == "remote") and body.is_in_group("enemies"):
				NetworkManager.send_event("enemyHit", {"enemyId": body.entity_id, "damage": damage})
			elif (owner_type == "player" or owner_type == "remote") and is_pvp_target:
				NetworkManager.send_event("playerHitByPlayer", {"victimId": body.entity_id, "damage": damage})
			elif owner_type == "enemy" and body.is_in_group("player"):
				NetworkManager.send_event("playerHitByEnemy", {
					"damage": damage, 
					"attackerType": owner_type,
					"enemyType": enemy_type, # v226.41: Informar qué bicho pegó para validar daño
					"bulletType": type, # v266.182: Informar si es hielo o especial
					"attackerId": owner_id
				})
		
		_explode()
	elif body.is_in_group("obstacles"):
		_explode()

func _explode():
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
