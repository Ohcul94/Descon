extends Area2D
class_name Projectile

# Projectile.gd (v141.71 - VECTOR RENDERING & RECOVERY)
# Clase base para todos los proyectiles. 

@export var speed: float = 800.0
@export var damage: float = 10.0
@export var owner_id: String = ""
@export var type: String = "laser" # laser, missile, mine

var owner_type: String = "player"
var velocity: Vector2 = Vector2.ZERO
var sprite: Sprite2D = null

func _ready():
	add_to_group("projectiles")
	
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	add_child(shape)
	
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	queue_redraw()

func setup(p_pos: Vector2, p_angle: float, p_data: Dictionary):
	global_position = p_pos
	rotation = p_angle
	type = p_data.get("type", "laser")
	owner_id = str(p_data.get("id", p_data.get("senderId", p_data.get("entityId", ""))))
	owner_type = p_data.get("owner_type", "player")
	
	speed = p_data.get("speed", 1500.0)
	if type == "missile":
		speed = 450.0  # Mucho más lento siempre (Velocidad impuesta)
	elif type == "mine":
		speed = 400.0  # Impulso de eyección (Frenará por fricción)
	damage = p_data.get("damageBoost", p_data.get("damage", 10.0))
	
	velocity = Vector2.RIGHT.rotated(p_angle) * speed
	
	collision_layer = 0
	if owner_type == "player" or owner_type == "remote":
		collision_mask = 2 # Impactar NPCs
	else:
		collision_mask = 1 # Impactar Jugadores
	
	_setup_visual_sprite()
	queue_redraw()

func _setup_visual_sprite():
	if is_instance_valid(sprite): sprite.queue_free()
	
	var path = ""
	match type:
		"laser": path = "res://assets/Municiones/Laser1.png"
		"missile": path = "res://assets/Municiones/Misil1.png"
		"mine": path = "res://assets/Municiones/Mina1.png"
	
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
		
		add_child(sprite)

func _draw():
	if is_instance_valid(sprite): return
	match type:
		"laser":
			draw_rect(Rect2(Vector2(-10, -2.5), Vector2(20, 5)), Color.WHITE)
		"missile":
			draw_line(Vector2(-10, 0), Vector2(10, 0), Color.WHITE, 6.0)
			draw_circle(Vector2(10, 0), 4, Color.WHITE)
		"mine":
			draw_circle(Vector2.ZERO, 10, Color.WHITE)
			draw_circle(Vector2.ZERO, 12, Color(1, 1, 1, 0.3), false, 3.0)

func _physics_process(delta):
	# Efecto de Fricción Fuerte para desplegar minas estáticas a corta distancia (recorren poco antes de anclarse)
	if type == "mine":
		velocity = velocity.lerp(Vector2.ZERO, 3.5 * delta)
		
	global_position += velocity * delta
	if global_position.length() > 15000: 
		queue_free()

func _on_body_entered(body):
	if body.has_method("take_damage"):
		var body_eid = ""
		if "entity_id" in body: body_eid = str(body.entity_id)
		if body_eid != owner_id:
			# Aplicar daño local para feedback inmediato
			body.take_damage(damage)
			
			# v167.80: NOTIFICAR AL SERVIDOR (Crucial para detener Regen)
			if NetworkManager:
				if owner_type == "player" and body.is_in_group("enemies"):
					# Yo le pego a un enemigo
					NetworkManager.send_event("enemyHit", {"enemyId": body.entity_id, "damage": damage})
				elif (owner_type == "enemy" or owner_type == "remote") and body.is_in_group("player"):
					# Un enemigo o bala remota me pega a MI
					NetworkManager.send_event("playerHitByEnemy", {"damage": damage, "attackerType": owner_type})
			
			_explode()
	elif body.is_in_group("obstacles"):
		_explode()

func _explode():
	queue_free()
