extends Area2D
class_name Projectile

# Projectile.gd (v141.72 - CONE EMP & VECTOR RENDERING)
# Clase base para todos los proyectiles con soporte de colisión y efectos cónicos para EMP. 

@export var speed: float = 800.0
@export var damage: float = 10.0
@export var owner_id: String = ""
@export var type: String = "laser" # laser, missile, mine

var owner_type: String = "player"
var enemy_type: int = 1 
var velocity: Vector2 = Vector2.ZERO
var sprite: Sprite2D = null
var _has_hit: bool = false
var max_range: float = 0.0
var _start_pos: Vector2 = Vector2.ZERO
var target_id: String = "" 
var _target_node: Node2D = null
var _owner_node: Node2D = null
var _chain_visual: Line2D = null
var lifetime: float = 6.0 
var _current_lifetime: float = 0.0
var turn_speed: float = 2.5 
var is_homing: bool = false 
var orbit_target: Node2D = null 
var orbit_radius: float = 150.0
var orbit_speed: float = 2.0
var orbit_angle_offset: float = 0.0
var orbit_start_time: float = 0.0
var strike_id: String = "" 
var _start_time_stamp: float = 0.0
var _find_target_timer: float = 0.0
var world_root_3d: Node3D = null
var _orb_mesh: MeshInstance3D = null
var _is_setup: bool = false

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
	
	var raw_speed = p_data.get("bulletSpeed")
	if raw_speed == null: raw_speed = p_data.get("speed")
	speed = _safe_float(raw_speed, speed)
	if speed <= 0 and (type == "missile" or type == "ice_missile"):
		speed = 450.0 
		
	max_range = _safe_float(p_data.get("range"), 600.0)
	target_id = str(p_data.get("targetId", ""))
	
	_find_target()
	
	lifetime = _safe_float(p_data.get("lifetimeMs"), 0.0) / 1000.0
	turn_speed = _safe_float(p_data.get("turnSpeed"), 2.5)
	is_homing = bool(p_data.get("isHoming", false))
	
	var world = get_tree().get_first_node_in_group("world_node")
	
	if p_data.get("isOrbiting", false):
		if is_instance_valid(world):
			var ent_node = world.get("entities_node")
			if ent_node:
				for e in ent_node.get_children():
					if str(e.get("entity_id")) == owner_id:
						orbit_target = e
						break
		orbit_radius = _safe_float(p_data.get("orbitRadius"), 150.0)
		orbit_speed = _safe_float(p_data.get("orbitSpeed"), 2.0)
		orbit_angle_offset = _safe_float(p_data.get("orbitAngleOffset"), 0.0)
		orbit_start_time = Time.get_ticks_msec() / 1000.0
	
	strike_id = str(p_data.get("strikeId", ""))
	if p_data.has("stunDuration"): set_meta("stunDuration", p_data.stunDuration)
	
	var raw_dmg = p_data.get("damageBoost")
	if raw_dmg == null: raw_dmg = p_data.get("damage")
	damage = _safe_float(raw_dmg, damage)
	_start_pos = p_pos
	_start_time_stamp = Time.get_ticks_msec() / 1000.0
	if type == "melee":
		lifetime = 0.85 # 0.35s de convergencia circular + 0.5s de permanencia/desvanecimiento
	
	if type == "mega_laser":
		velocity = Vector2.ZERO
		speed = 0.0
	else:
		velocity = Vector2.RIGHT.rotated(p_angle) * speed

	if type == "melee":
		var shape_izq = CollisionShape2D.new()
		var circle_izq = CircleShape2D.new()
		circle_izq.radius = 18.0
		shape_izq.shape = circle_izq
		shape_izq.name = "ColSierIzqu"
		add_child(shape_izq)
		
		var shape_der = CollisionShape2D.new()
		var circle_der = CircleShape2D.new()
		circle_der.radius = 18.0
		shape_der.shape = circle_der
		shape_der.name = "ColSierDere"
		add_child(shape_der)
		
		var shape_tras_izq = CollisionShape2D.new()
		var circle_tras_izq = CircleShape2D.new()
		circle_tras_izq.radius = 18.0
		shape_tras_izq.shape = circle_tras_izq
		shape_tras_izq.name = "ColSierTrasIzqu"
		add_child(shape_tras_izq)
		
		var shape_tras_der = CollisionShape2D.new()
		var circle_tras_der = CircleShape2D.new()
		circle_tras_der.radius = 18.0
		shape_tras_der.shape = circle_tras_der
		shape_tras_der.name = "ColSierTrasDere"
		add_child(shape_tras_der)
	else:
		var shape = CollisionShape2D.new()
		if type == "mega_laser":
			var rect = RectangleShape2D.new()
			shape.shape = rect
		else:
			var circle = CircleShape2D.new()
			if type == "spin_ring":
				circle.radius = 35.0 
			elif type == "emp":
				circle.radius = 30.0 # Ancho de 60px
			else:
				circle.radius = 20.0 
			shape.shape = circle
		add_child(shape)
	
	collision_layer = 0
	
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
		collision_mask = 1 | 2 
	else:
		collision_mask = 1 
		
	if type == "spin_ring":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			world_root_3d = Node3D.new()
			world_root_3d.name = "Orb3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)
			
			_orb_mesh = MeshInstance3D.new()
			var sphere_mesh = SphereMesh.new()
			sphere_mesh.radius = 0.45
			sphere_mesh.height = 0.9
			_orb_mesh.mesh = sphere_mesh
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.9, 0.2, 1.0) 
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.2, 1.0)
			mat.emission_energy_multiplier = 3.0
			_orb_mesh.material_override = mat
			world_root_3d.add_child(_orb_mesh)
			
			world_root_3d.scale = Vector3.ZERO
			create_tween().tween_property(world_root_3d, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			
		tree_exiting.connect(func():
			if is_instance_valid(world_root_3d):
				world_root_3d.queue_free()
		)
		
	_setup_visual_sprite()
	_is_setup = true
	queue_redraw()

func _setup_visual_sprite():
	if type == "spin_ring": return
	if is_instance_valid(sprite): sprite.queue_free()
	
	# Efecto de partículas de tormenta de viento eléctrica lineal para EMP
	if type == "emp":
		sprite = null
		var parts = CPUParticles2D.new()
		parts.name = "EMPViento"
		parts.amount = 60
		parts.lifetime = 0.4
		parts.speed_scale = 1.3
		parts.explosiveness = 0.05
		parts.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		parts.emission_rect_extents = Vector2(5.0, 30.0) # Cubre ancho de 60px
		parts.direction = Vector2.RIGHT
		parts.spread = 0.0 # Haz lineal recto sin esparcimiento cónico
		parts.gravity = Vector2.ZERO
		parts.initial_velocity_min = 250.0
		parts.initial_velocity_max = 500.0
		parts.scale_amount_min = 2.0
		parts.scale_amount_max = 7.0
		parts.z_index = 6
		
		var gradient = Gradient.new()
		gradient.set_color(0, Color(0.15, 0.55, 1.0, 0.85)) 
		gradient.add_point(0.4, Color(0.4, 0.8, 1.0, 0.65)) 
		gradient.add_point(0.8, Color(0.05, 0.3, 0.9, 0.3)) 
		gradient.set_color(1, Color(0.0, 0.1, 0.5, 0.0))
		parts.color_ramp = gradient
		
		add_child(parts)
		parts.emitting = true
		
		var sparks = CPUParticles2D.new()
		sparks.amount = 25
		sparks.lifetime = 0.5
		sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		sparks.emission_rect_extents = Vector2(5.0, 30.0)
		sparks.direction = Vector2.RIGHT
		sparks.spread = 10.0
		sparks.gravity = Vector2.ZERO
		sparks.initial_velocity_min = 100.0
		sparks.initial_velocity_max = 300.0
		sparks.scale_amount_min = 1.0
		sparks.scale_amount_max = 3.0
		sparks.color = Color(0.7, 0.9, 1.0, 0.9)
		add_child(sparks)
		sparks.emitting = true
		return
		
	# Efecto de partículas de chispas radiales de sierras giratorias para Melee
	if type == "melee":
		sprite = null
		var parts_izq = CPUParticles2D.new()
		parts_izq.name = "CuchillaIzq"
		parts_izq.amount = 40
		parts_izq.lifetime = 0.2
		parts_izq.speed_scale = 1.3
		parts_izq.explosiveness = 0.0
		parts_izq.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		parts_izq.emission_sphere_radius = 12.0 # Emite desde el contorno de la sierra
		parts_izq.spread = 180.0 # Radial en todas direcciones (efecto chispas)
		parts_izq.gravity = Vector2.ZERO
		parts_izq.initial_velocity_min = 50.0
		parts_izq.initial_velocity_max = 130.0
		parts_izq.scale_amount_min = 1.5
		parts_izq.scale_amount_max = 4.0
		parts_izq.z_index = 6
		
		var grad = Gradient.new()
		grad.set_color(0, Color(1.0, 0.6, 0.0, 0.95)) # Chispas naranja brillante
		grad.add_point(0.4, Color(1.0, 0.95, 0.3, 0.85)) # Amarillo núcleo
		grad.add_point(0.7, Color(0.95, 0.2, 0.0, 0.4)) # Rojo difuminado
		grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		parts_izq.color_ramp = grad
		
		add_child(parts_izq)
		parts_izq.emitting = true
		
		var parts_der = parts_izq.duplicate()
		parts_der.name = "CuchillaDer"
		add_child(parts_der)
		parts_der.emitting = true
		
		var parts_tras_izq = parts_izq.duplicate()
		parts_tras_izq.name = "CuchillaTrasIzq"
		add_child(parts_tras_izq)
		parts_tras_izq.emitting = true
		
		var parts_tras_der = parts_izq.duplicate()
		parts_tras_der.name = "CuchillaTrasDer"
		add_child(parts_tras_der)
		parts_tras_der.emitting = true
		return
		
	# Efecto de partículas de estela verde brillante para Heal Drones
	if type == "heal":
		sprite = null
		var parts = CPUParticles2D.new()
		parts.name = "HealTrail"
		parts.amount = 35
		parts.lifetime = 0.5
		parts.speed_scale = 1.0
		parts.explosiveness = 0.0
		parts.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		parts.emission_sphere_radius = 5.0
		parts.direction = Vector2.LEFT # Estela hacia atrás
		parts.spread = 20.0
		parts.gravity = Vector2.ZERO
		parts.initial_velocity_min = 40.0
		parts.initial_velocity_max = 90.0
		parts.scale_amount_min = 2.0
		parts.scale_amount_max = 5.0
		parts.z_index = 5
		
		var grad = Gradient.new()
		grad.set_color(0, Color(0.2, 0.95, 0.4, 0.9)) # Verde brillante
		grad.add_point(0.5, Color(0.5, 1.0, 0.6, 0.7)) # Verde claro brillante
		grad.set_color(1, Color(0.1, 0.6, 0.2, 0.0)) # Desvanecimiento
		parts.color_ramp = grad
		
		add_child(parts)
		parts.emitting = true
		return

	var path = ""
	match type:
		"laser": path = "res://assets/Municiones/Lasers/Laser1/Laser1.png"
		"missile": path = "res://assets/Municiones/Misiles/Misil1/Misil1.png"
		"ice_missile": path = "res://assets/Municiones/Misiles/Misil1/Misil1.png"
		"mine": path = "res://assets/Municiones/Minas/Mina1/Mina1.png"
		"orbital_mine": path = "res://assets/Municiones/Minas/Mina3/Mina3.png"
		"siphon": path = "res://assets/Municiones/Misiles/Misil2/Misil2.png"
		"hook": 
			path = "res://assets/Municiones/Minas/Mina2/Mina2.png"
			modulate = Color(0, 1, 1) 
		"mega_laser":
			var beam = Line2D.new()
			beam.width = 40.0
			beam.default_color = Color(1, 0.2, 0.2, 0.8) 
			var length = max_range if max_range > 0.0 else 1000.0
			beam.points = PackedVector2Array([Vector2.ZERO, Vector2(length, 0)])
			
			var glow = Line2D.new()
			glow.width = 15.0
			glow.default_color = Color(1, 1, 1, 0.9) 
			glow.points = beam.points
			beam.add_child(glow)
			
			add_child(beam)
			
			for child in get_children():
				if child is CollisionShape2D and child.shape is RectangleShape2D:
					child.shape.size = Vector2(length, 40.0)
					child.position.x = child.shape.size.x / 2.0
			return
	
	if path != "" and ResourceLoader.exists(path):
		sprite = Sprite2D.new()
		var tex = load(path)
		sprite.texture = tex
		
		var target_size = 48.0
		if type == "mine" or type == "orbital_mine": target_size = 64.0
		elif type == "missile": target_size = 56.0
		
		var s = target_size / max(tex.get_width(), tex.get_height())
		if type == "orbital_mine": s = 0.08 
		sprite.scale = Vector2(s, s)
		sprite.rotation_degrees = 90
		
		if type == "ice_missile":
			sprite.modulate = Color(0.4, 0.7, 1.0) 
		elif type == "melee":
			sprite.modulate = Color(1.0, 0.65, 0.1) 
		elif type == "heal":
			sprite.modulate = Color(0.2, 0.9, 0.3) 
		elif type == "siphon":
			sprite.modulate = Color(0.8, 0.15, 0.9) 
		elif owner_type == "enemy":
			if type == "orbital_mine": sprite.modulate = Color(1.2, 1.2, 1.2) 
			else: sprite.modulate = Color(1.0, 0.3, 0.3) 
		else:
			sprite.modulate = Color(0.3, 1.0, 1.0) 
		
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
			draw_line(Vector2(0, 0), Vector2(-20, 0), Color.GRAY, 2.0)
			draw_arc(Vector2(5, 0), 10, -PI/2, PI/2, 8, Color.GRAY, 3.0)
		"melee":
			var t = _current_lifetime / 0.35
			t = clamp(t, 0.0, 1.0)
			var rango_local = max_range if max_range > 0.0 else 150.0
			
			var alpha = 1.0
			if _current_lifetime > 0.35:
				var extra_t = (_current_lifetime - 0.35) / 0.5
				alpha = clamp(1.0 - extra_t, 0.0, 1.0)
			
			var color_sierra = Color(1.0, 0.4, 0.0, 0.8 * alpha) # Naranja ígneo
			var color_relleno = Color(1.0, 0.55, 0.1, 0.3 * alpha) # Relleno translúcido
			var color_nucleo = Color(1.0, 0.95, 0.4, 0.9 * alpha) # Amarillo brillante
			
			var r_sierra = 18.0
			var spin_angle = (Time.get_ticks_msec() / 1000.0) * 16.0 # Velocidad de giro rápida
			var num_dientes = 10
			
			# Delanteras
			var theta_izq = -PI/2.0 + t * (PI/2.0)
			var pos_izq = Vector2(cos(theta_izq) * rango_local, sin(theta_izq) * rango_local)
			
			var theta_der = PI/2.0 - t * (PI/2.0)
			var pos_der = Vector2(cos(theta_der) * rango_local, sin(theta_der) * rango_local)
			
			# Traseras (Trayectoria inversa)
			var theta_tras_izq = -PI/2.0 - t * (PI/2.0)
			var pos_tras_izq = Vector2(cos(theta_tras_izq) * rango_local, sin(theta_tras_izq) * rango_local)
			
			var theta_tras_der = PI/2.0 + t * (PI/2.0)
			var pos_tras_der = Vector2(cos(theta_tras_der) * rango_local, sin(theta_tras_der) * rango_local)
			
			var list_pos = [pos_izq, pos_der, pos_tras_izq, pos_tras_der]
			
			# Dibujar las 4 sierras
			for idx in range(4):
				var pos = list_pos[idx]
				draw_circle(pos, r_sierra, color_relleno)
				draw_circle(pos, r_sierra - 3.0, Color(color_sierra.r, color_sierra.g, color_sierra.b, 0.6 * alpha))
				draw_circle(pos, 4.0, color_nucleo)
				
				# Alternar sentido de giro entre sierras consecutivas
				var angle_dir = spin_angle if idx % 2 == 0 else -spin_angle
				
				for i in range(num_dientes):
					var ang = angle_dir + (float(i) / num_dientes) * TAU
					var p1 = pos + Vector2(cos(ang), sin(ang)) * (r_sierra - 3.0)
					var p2 = pos + Vector2(cos(ang + 0.25), sin(ang + 0.25)) * (r_sierra + 6.0)
					draw_line(p1, p2, color_sierra, 3.0)
					draw_line(p1, p2, color_nucleo, 1.2)
		"heal":
			# Dibujamos un mini-dron de soporte curativo (Heal Drones)
			var pulse = sin(Time.get_ticks_msec() * 0.01) * 2.0
			var base_r = 8.0 + pulse
			
			draw_circle(Vector2.ZERO, base_r, Color(0.15, 0.75, 0.25, 0.45)) # Brillo exterior verde
			draw_circle(Vector2.ZERO, 6.0, Color(0.2, 0.95, 0.35, 0.9)) # Cuerpo del dron
			draw_circle(Vector2.ZERO, 3.0, Color.WHITE) # Lente/núcleo luminoso
			
			# Brazos y mini-propulsores laterales del dron
			draw_circle(Vector2(-10, 0), 2.5, Color(0.4, 0.4, 0.4, 0.8))
			draw_circle(Vector2(10, 0), 2.5, Color(0.4, 0.4, 0.4, 0.8))
			draw_line(Vector2(-10, 0), Vector2(-12, -3), Color(0.25, 0.95, 0.35, 0.6), 1.5)
			draw_line(Vector2(10, 0), Vector2(12, -3), Color(0.25, 0.95, 0.35, 0.6), 1.5)
			
			# Cruz de curación blanca translúcida en el centro
			draw_line(Vector2(-3.5, 0), Vector2(3.5, 0), Color.WHITE, 1.5)
			draw_line(Vector2(0, -3.5), Vector2(0, 3.5), Color.WHITE, 1.5)
		"siphon":
			draw_circle(Vector2.ZERO, 6.0, color)
			draw_rect(Rect2(Vector2(-6, -6), Vector2(12, 12)), Color(color.r, color.g, color.b, 0.4), false, 2.0)
			draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.1, 0.3, 0.4), false, 1.5)
		"emp":
			# Dibujar líneas verticales sutiles que representan el frente del haz de viento (de Y=-30 a Y=30)
			draw_line(Vector2(0, -30), Vector2(0, 30), Color(0.1, 0.5, 1.0, 0.45), 4.0)
			draw_line(Vector2(-8, -20), Vector2(-8, 20), Color(0.3, 0.7, 1.0, 0.25), 2.0)
			draw_line(Vector2(8, -20), Vector2(8, 20), Color(0.3, 0.7, 1.0, 0.25), 2.0)

func release_orbit():
	orbit_target = null

func _physics_process(delta):
	if is_instance_valid(world_root_3d):
		var s_factor = 0.02
		var correction_z = 1.41421356
		world_root_3d.position.x = global_position.x * s_factor
		world_root_3d.position.z = global_position.y * s_factor * correction_z
		world_root_3d.position.y = 0.0

	if lifetime > 0:
		_current_lifetime += delta
		if _current_lifetime >= lifetime:
			queue_free()
			return

	if is_instance_valid(orbit_target):
		var time = (Time.get_ticks_msec() / 1000.0) - orbit_start_time
		var angle = time * orbit_speed + orbit_angle_offset
		global_position = orbit_target.global_position + Vector2(cos(angle), sin(angle)) * orbit_radius
		rotation = angle
		velocity = Vector2.RIGHT.rotated(rotation) * speed 
		return

	if is_instance_valid(_chain_visual) and is_instance_valid(_owner_node):
		_chain_visual.points = PackedVector2Array([_owner_node.global_position, global_position])

	if target_id != "" and not is_instance_valid(_target_node):
		_find_target_timer += delta
		if _find_target_timer >= 0.25:
			_find_target_timer = 0.0
			_find_target()

	if is_homing and is_instance_valid(_target_node):
		var target_pos = _target_node.global_position
		if _target_node.get_meta("is_single_world", false) and is_instance_valid(_target_node.get("world_root_3d")):
			target_pos = _get_visual_position_of(_target_node)
		
		var target_angle = (target_pos - global_position).angle()
		rotation = rotate_toward(rotation, target_angle, turn_speed * delta)
		velocity = Vector2.RIGHT.rotated(rotation) * speed
	
	elif type == "mine":
		velocity = velocity.lerp(Vector2.ZERO, 3.5 * delta)
	elif type == "melee":
		velocity = velocity.lerp(Vector2.ZERO, 6.0 * delta)
		if is_instance_valid(_owner_node):
			global_position = _owner_node.global_position
			rotation = _owner_node.rotation
			
		var t = _current_lifetime / 0.35
		t = clamp(t, 0.0, 1.0)
		var rango_local = max_range if max_range > 0.0 else 150.0
		
		# Delanteras
		var theta_izq = -PI/2.0 + t * (PI/2.0)
		var pos_izq = Vector2(cos(theta_izq) * rango_local, sin(theta_izq) * rango_local)
		
		var theta_der = PI/2.0 - t * (PI/2.0)
		var pos_der = Vector2(cos(theta_der) * rango_local, sin(theta_der) * rango_local)
		
		# Traseras (Trayectoria inversa)
		var theta_tras_izq = -PI/2.0 - t * (PI/2.0)
		var pos_tras_izq = Vector2(cos(theta_tras_izq) * rango_local, sin(theta_tras_izq) * rango_local)
		
		var theta_tras_der = PI/2.0 + t * (PI/2.0)
		var pos_tras_der = Vector2(cos(theta_tras_der) * rango_local, sin(theta_tras_der) * rango_local)
		
		# Sincronización de visuales (partículas)
		var node_izq = get_node_or_null("CuchillaIzq")
		var node_der = get_node_or_null("CuchillaDer")
		var node_tras_izq = get_node_or_null("CuchillaTrasIzq")
		var node_tras_der = get_node_or_null("CuchillaTrasDer")
		
		if is_instance_valid(node_izq) and is_instance_valid(node_der) and is_instance_valid(node_tras_izq) and is_instance_valid(node_tras_der):
			node_izq.position = pos_izq
			node_der.position = pos_der
			node_tras_izq.position = pos_tras_izq
			node_tras_der.position = pos_tras_der
			
			if _current_lifetime > 0.35:
				node_izq.emitting = false
				node_der.emitting = false
				node_tras_izq.emitting = false
				node_tras_der.emitting = false
				
		# Sincronización de colisiones físicas locales
		var col_izq = get_node_or_null("ColSierIzqu")
		var col_der = get_node_or_null("ColSierDere")
		var col_tras_izq = get_node_or_null("ColSierTrasIzqu")
		var col_tras_der = get_node_or_null("ColSierTrasDere")
		
		if is_instance_valid(col_izq) and is_instance_valid(col_der) and is_instance_valid(col_tras_izq) and is_instance_valid(col_tras_der):
			col_izq.position = pos_izq
			col_der.position = pos_der
			col_tras_izq.position = pos_tras_izq
			col_tras_der.position = pos_tras_der
			
		queue_redraw()
		
	var move_step = velocity * delta
	if type == "melee":
		move_step = Vector2.ZERO
	if type == "siphon":
		var time = (Time.get_ticks_msec() / 1000.0) - _start_time_stamp
		var wave_offset = cos(time * 20.0) * 6.0
		var perp = Vector2(-velocity.y, velocity.x).normalized()
		global_position += move_step + perp * (wave_offset * delta * 60.0)
	else:
		global_position += move_step

	if max_range > 0:
		var dist = global_position.distance_to(_start_pos)
		if dist >= max_range:
			if type == "mine":
				global_position = _start_pos + (_start_pos.direction_to(global_position) * max_range)
				velocity = Vector2.ZERO
			else:
				queue_free()
	
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
		
		if type == "orbital_mine":
			var age = (Time.get_ticks_msec() / 1000.0) - orbit_start_time
			if age < 0.3: return 
		
		if body_eid == owner_id: return
		
		var is_pvp_target = body.is_in_group("remote_players") or body.is_in_group("player")
		
		if is_pvp_target:
			if owner_type == "player" or owner_type == "remote":
				var attacker_has_pvp = false
				var target_has_pvp = false
				
				if "pvp_status" in body: target_has_pvp = body.pvp_status
				
				for entity in get_tree().get_nodes_in_group("entities"):
					if str(entity.entity_id) == owner_id:
						if "pvp_status" in entity: attacker_has_pvp = entity.pvp_status
						break
				
				if not (attacker_has_pvp and target_has_pvp):
					return
		
		_has_hit = true
		body.take_damage(damage, global_position, owner_id)
		
		if NetworkManager:
			if owner_type == "player" and body.is_in_group("enemies"):
				NetworkManager.send_event("enemyHit", {"enemyId": body.entity_id, "damage": damage})
			elif owner_type == "player" and is_pvp_target:
				NetworkManager.send_event("playerHitByPlayer", {"victimId": body.entity_id, "damage": damage})
			elif owner_type == "enemy" and body.is_in_group("player"):
				NetworkManager.send_event("playerHitByEnemy", {
					"damage": damage, 
					"attackerType": owner_type,
					"enemyType": enemy_type, 
					"bulletType": type, 
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
	
	if NetworkManager and target_id == str(NetworkManager.my_socket_id):
		_target_node = get_tree().get_first_node_in_group("player")
		if is_instance_valid(_target_node): return

	var entities = get_tree().get_nodes_in_group("entities")
	for e in entities:
		if e.has_method("get") and str(e.get("entity_id")) == target_id:
			_target_node = e
			return
			
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

func _safe_float(val, default: float = 0.0) -> float:
	if val == null:
		return default
	var val_type = typeof(val)
	if val_type == TYPE_INT or val_type == TYPE_FLOAT:
		return float(val)
	elif val_type == TYPE_STRING:
		return val.to_float()
	elif val_type == TYPE_BOOL:
		return 1.0 if val else 0.0
	return default
