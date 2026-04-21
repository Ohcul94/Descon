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
var _has_hit: bool = false # v222.60: Evitar procesos duplicados

func _ready():
	add_to_group("projectiles")
	
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 20.0 # v235.16: Radio aumentado masivamente para facilidad de impacto
	shape.shape = circle
	add_child(shape)
	
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	queue_redraw()

func setup(p_pos: Vector2, p_angle: float, p_data: Dictionary):
	global_position = p_pos
	rotation = p_angle
	type = p_data.get("type", "laser")
	owner_id = str(p_data.get("enemyId", p_data.get("id", p_data.get("senderId", p_data.get("entityId", "")))))
	owner_type = p_data.get("owner_type", "player")
	enemy_type = int(p_data.get("enemyType", 1))
	
	speed = p_data.get("speed", 1500.0)
	if type == "missile":
		speed = 450.0  # Mucho más lento siempre (Velocidad impuesta)
	elif type == "mine":
		speed = 400.0  # Impulso de eyección (Frenará por fricción)
	damage = p_data.get("damageBoost", p_data.get("damage", 10.0))
	
	velocity = Vector2.RIGHT.rotated(p_angle) * speed
	
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
					"enemyType": enemy_type # v226.41: Informar qué bicho pegó para validar daño
				})
		
		_explode()
	elif body.is_in_group("obstacles"):
		_explode()

func _explode():
	queue_free()
