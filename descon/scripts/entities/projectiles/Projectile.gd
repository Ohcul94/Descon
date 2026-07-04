extends Area2D
class_name Projectile

# Pre-cargado estático de escenas VFX para optimizar FPS en ráfagas de red (v313.1)
const VFX_Anticipation_wave_digital_scene = preload("res://VFX/scenes/VFX_Anticipation_wave_digital.tscn")
const VFX_Anticipation_hadouken_scene = preload("res://VFX/scenes/VFX_Anticipation_hadouken.tscn")
const VFX_Hadouken_scene = preload("res://VFX/scenes/VFX_Hadouken.tscn")
const VFX_Cube_projectile_scene = preload("res://VFX/scenes/VFX_Cube_projectile.tscn")
const VFX_Hit_cyber_scene = preload("res://VFX/scenes/VFX_Hit_cyber.tscn")
const VFX_Hit_hadouken_scene = preload("res://VFX/scenes/VFX_Hit_hadouken.tscn")
const VFX_Laser_projectile_scene = preload("res://VFX/scenes/VFX_Laser_projectile.tscn")
const VFX_Laser_Hit_scene = preload("res://VFX/scenes/VFX_Laser_Hit.tscn")
const VFX_Fire_ball_type_B_scene = preload("res://VFX/scenes/VFX_Fire_ball_type_B.tscn")
const VFX_Fire_strike_scene = preload("res://VFX/scenes/VFX_Fire_strike.tscn")

# Pre-cargado estático de texturas para evitar I/O bloqueante
const TEXTURE_MISSILE = preload("res://assets/Municiones/Misiles/Misil1/Misil1.png")
const TEXTURE_MINE = preload("res://assets/Municiones/Minas/Mina1/Mina1.png")
const TEXTURE_MINE_3 = preload("res://assets/Municiones/Minas/Mina3/Mina3.png")
const TEXTURE_MINE_2 = preload("res://assets/Municiones/Minas/Mina2/Mina2.png")

const TEXTURE_CACHE = {
	"missile": TEXTURE_MISSILE,
	"ice_missile": TEXTURE_MISSILE,
	"mine": TEXTURE_MINE,
	"orbital_mine": TEXTURE_MINE_3,
	"hook": TEXTURE_MINE_2
}

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
var _melee_fireballs_3d: Array = []
var _melee_blade_positions_3d: Array = []

func _ready():
	add_to_group("projectiles")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if not body_shape_entered.is_connected(_on_body_shape_entered):
		body_shape_entered.connect(_on_body_shape_entered)
	queue_redraw()

func _process(_delta):
	# Sincronización visual 3D en cada frame para evitar desfase con las naves (Entity.gd)
	if is_instance_valid(world_root_3d):
		var active_map = get_tree().get_first_node_in_group("map")
		var s_factor = active_map.scale_factor if is_instance_valid(active_map) and "scale_factor" in active_map else 0.02
		var correction_z = active_map.correction_z if is_instance_valid(active_map) and "correction_z" in active_map else 1.41421356
		world_root_3d.position.x = global_position.x * s_factor
		world_root_3d.position.z = global_position.y * s_factor * correction_z
		world_root_3d.position.y = 0.0
		world_root_3d.rotation.y = -rotation - PI/2.0


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
	# Calcular lifetime desde range/speed si el servidor no lo envió
	if lifetime <= 0 and speed > 0 and max_range > 0:
		lifetime = max_range / speed + 1.0
	elif lifetime <= 0:
		lifetime = 3.0
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
	if p_data.has("duration"): set_meta("duration", p_data.duration)
	
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
		
	# Spawn 3D anticipation aura for heal projectiles
	if type == "heal":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Anticipation_wave_digital_scene:
				var antic = VFX_Anticipation_wave_digital_scene.instantiate()
				antic.name = "HealAntic3D_" + str(get_instance_id())
				target_vp.add_child(antic)
				
				# Calcular posición desplazada hacia atrás de la nave (según la rotación de disparo)
				var offset_dist = 50.0 # Desplazar 50px hacia atrás
				var offset_pos = p_pos - Vector2.RIGHT.rotated(p_angle) * offset_dist
				
				# Posicionarlo a la altura correcta
				var s_factor = 0.02
				var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
				antic.position.x = offset_pos.x * s_factor
				antic.position.z = offset_pos.y * s_factor * correction_z
				# Elevarlo un poco en Y para que se alinee con el chasis de la nave y no quede en el suelo
				antic.position.y = 0.4
				antic.scale = Vector3(1.2, 1.2, 1.2)
				
				# Sincronizar la rotación del aura 3D con la dirección del disparo
				antic.rotation.y = -p_angle - PI/2.0
				
				# Auto-liberar al terminar la animación
				var anim = antic.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(antic.queue_free.unbind(1))
				else:
					var tw = antic.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(antic.queue_free)

	# Spawn 3D anticipation aura for emp (hadouken) projectiles
	if type == "emp":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Anticipation_hadouken_scene:
				var antic = VFX_Anticipation_hadouken_scene.instantiate()
				antic.name = "HadoukenAntic3D_" + str(get_instance_id())
				target_vp.add_child(antic)
				
				# Calcular posición desplazada hacia atrás de la nave (según la rotación de disparo)
				var offset_dist = 50.0
				var offset_pos = p_pos - Vector2.RIGHT.rotated(p_angle) * offset_dist
				
				# Posicionarlo a la altura correcta
				var s_factor = 0.02
				var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
				antic.position.x = offset_pos.x * s_factor
				antic.position.z = offset_pos.y * s_factor * correction_z
				# Elevarlo un poco en Y para que se alinee con el chasis de la nave y no quede en el suelo
				antic.position.y = 0.4
				antic.scale = Vector3(1.2, 1.2, 1.2)
				
				# Sincronizar la rotación del aura 3D con la dirección del disparo
				antic.rotation.y = -p_angle - PI/2.0
				
				# Auto-liberar al terminar la animación
				var anim = antic.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(antic.queue_free.unbind(1))
				else:
					var tw = antic.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(antic.queue_free)

	_setup_visual_sprite()
	_is_setup = true
	queue_redraw()

func _setup_visual_sprite():
	if type == "spin_ring": return
	if is_instance_valid(sprite): sprite.queue_free()
	
	# Efecto 3D de proyectil EMP (Hadouken)
	if type == "emp":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Hadouken_scene:
				world_root_3d = VFX_Hadouken_scene.instantiate()
				world_root_3d.name = "HadoukenProj3D_" + str(get_instance_id())
				target_vp.add_child(world_root_3d)
				
				# Escala 3D óptima
				world_root_3d.scale = Vector3(1.5, 1.5, 1.5)
				
				# Conectar la limpieza al salir del árbol
				tree_exiting.connect(func():
					if is_instance_valid(world_root_3d):
						world_root_3d.queue_free()
				)
				
				sprite = null
				return
		
	# Efecto 3D de bola de fuego giratoria para Melee (Fire Ball Type B en cada cuchilla)
	if type == "melee":
		sprite = null
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Fire_ball_type_B_scene:
				_melee_fireballs_3d = []
				_melee_blade_positions_3d = []
				for i in 4:
					var fb = VFX_Fire_ball_type_B_scene.instantiate()
					fb.name = "MeleeFB3D_" + str(get_instance_id()) + "_" + str(i)
					fb.scale = Vector3(0.8, 0.8, 0.8)
					# Rotar la estela estática 180° en Y para que quede detrás de la esfera
					var trail1 = fb.get_node_or_null("Trail1_static")
					if trail1:
						var t = trail1.transform
						trail1.transform = Transform3D(t.basis * Basis.from_euler(Vector3(0, PI, 0)), t.origin)
					# Activar la estela dinámica (viene invisible en la escena)
					var trail2 = fb.get_node_or_null("Trail2_dynamic")
					if trail2:
						trail2.visible = true
					target_vp.add_child(fb)
					_melee_fireballs_3d.append(fb)
					_melee_blade_positions_3d.append(Vector3.ZERO)
				tree_exiting.connect(func():
					for fb in _melee_fireballs_3d:
						if is_instance_valid(fb):
							fb.queue_free()
				)
		return
		
	# Efecto 3D de proyectil curativo (glowing green cube)
	if type == "heal":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Cube_projectile_scene:
				world_root_3d = VFX_Cube_projectile_scene.instantiate()
				world_root_3d.name = "HealProj3D_" + str(get_instance_id())
				target_vp.add_child(world_root_3d)
				
				# Escala 3D óptima
				world_root_3d.scale = Vector3(1.5, 1.5, 1.5)
				
				# Conectar la limpieza al salir del árbol
				tree_exiting.connect(func():
					if is_instance_valid(world_root_3d):
						world_root_3d.queue_free()
				)
				
				sprite = null
				return
		
	# Efecto de partículas de humo oscuro y aura carmesí para Siphon
	if type == "siphon":
		sprite = null
		var parts = CPUParticles2D.new()
		parts.name = "SiphonTrail"
		parts.amount = 55
		parts.lifetime = 0.5
		parts.speed_scale = 1.0
		parts.explosiveness = 0.0
		parts.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		parts.emission_sphere_radius = 8.0
		parts.direction = Vector2.LEFT
		parts.spread = 20.0
		parts.gravity = Vector2.ZERO
		parts.initial_velocity_min = 20.0
		parts.initial_velocity_max = 60.0
		parts.scale_amount_min = 2.5
		parts.scale_amount_max = 8.0 # Partículas más grandes y difusas para simular humo
		parts.z_index = 5
		
		var grad = Gradient.new()
		grad.set_color(0, Color(0.95, 0.05, 0.1, 0.85)) # Rojo carmesí brillante
		grad.add_point(0.35, Color(0.6, 0.05, 0.65, 0.6)) # Púrpura místico
		grad.add_point(0.7, Color(0.15, 0.02, 0.2, 0.35)) # Humo oscuro (púrpura/negro muy translúcido)
		grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		parts.color_ramp = grad
		
		add_child(parts)
		parts.emitting = true
		return

	# Efecto 3D de proyectil Láser (cubo rojo con estela)
	if type == "laser":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Laser_projectile_scene:
				world_root_3d = VFX_Laser_projectile_scene.instantiate()
				world_root_3d.name = "LaserProj3D_" + str(get_instance_id())
				target_vp.add_child(world_root_3d)
				
				world_root_3d.scale = Vector3(0.75, 0.75, 0.75)
				
				tree_exiting.connect(func():
					if is_instance_valid(world_root_3d):
						world_root_3d.queue_free()
				)
				
				sprite = null
				return

	# Efecto 3D de proyectil de fuego (Fire Strike) para misiles
	if type == "missile" or type == "ice_missile":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Fire_strike_scene:
				world_root_3d = VFX_Fire_strike_scene.instantiate()
				world_root_3d.name = "MissileProj3D_" + str(get_instance_id())
				target_vp.add_child(world_root_3d)
				
				world_root_3d.scale = Vector3(0.75, 0.75, 0.75)
				
				# Activar la estela dinámica (viene invisible en la escena)
				var trail2 = world_root_3d.get_node_or_null("Trail2_dynamic")
				if trail2:
					trail2.visible = true
				
			# Auto-limpiar el nodo 3D cuando el proyectil 2D se destruye
			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
			)
			
			# Tinte azul para misiles de hielo
			if type == "ice_missile":
				var mesh = world_root_3d.get_node_or_null("MeshInstance3D")
				if mesh and mesh.material_override:
					var mat = mesh.material_override.duplicate()
					mat.albedo_color = Color(0.4, 0.7, 2.0)
					mesh.material_override = mat
				
				tree_exiting.connect(func():
					if is_instance_valid(world_root_3d):
						world_root_3d.queue_free()
				)
				
				sprite = null
				return

	var path = ""
	match type:
		"mine": path = "res://assets/Municiones/Minas/Mina1/Mina1.png"
		"orbital_mine": path = "res://assets/Municiones/Minas/Mina3/Mina3.png"
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
	
	if path != "":
		var tex = null
		if TEXTURE_CACHE.has(type):
			tex = TEXTURE_CACHE[type]
		elif ResourceLoader.exists(path):
			tex = load(path)
			
		if tex:
			sprite = Sprite2D.new()
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

	match type:
		"spin_ring":
			var pulse = sin(Time.get_ticks_msec() * 0.02) * 3.0
			draw_circle(Vector2.ZERO, 15.0 + pulse, Color(0.85, 0.1, 0.95, 0.4))
			draw_circle(Vector2.ZERO, 10.0, Color(0.9, 0.2, 1.0, 0.85))
			draw_circle(Vector2.ZERO, 4.0, Color.WHITE)
		"fear":
			var pulse = sin(Time.get_ticks_msec() * 0.015) * 2.0
			var base_r = 14.0 + pulse
			draw_circle(Vector2.ZERO, base_r, Color(0.6, 0.05, 0.65, 0.4))
			draw_circle(Vector2.ZERO, 9.0, Color(0.12, 0.0, 0.18, 0.9))
			draw_circle(Vector2.ZERO, 4.0, Color(0.9, 0.1, 0.1, 0.8))
		"electron":
			var total_flight_time = max_range / max(1.0, speed)
			var t = clamp(_current_lifetime / total_flight_time, 0.0, 1.0)
			var max_height = 180.0
			var height = 4.0 * max_height * t * (1.0 - t)
			
			# Sombra en el suelo (plana en 2D, se encoge un poco al subir y se agranda al bajar)
			var shadow_radius = 16.0 * (1.0 - t * 0.3)
			var shadow_alpha = 0.35 * (1.0 - t * 0.5)
			draw_circle(Vector2.ZERO, shadow_radius, Color(0, 0, 0, shadow_alpha))
			
			# Orbe de energía celeste/azul que se desplaza hacia arriba (-height)
			var bomb_pos = Vector2(0, -height)
			var pulse = sin(Time.get_ticks_msec() * 0.015) * 2.0
			var bomb_radius = 12.0 + pulse
			
			# Aura externa
			draw_circle(bomb_pos, bomb_radius + 6.0, Color(0.2, 0.6, 1.0, 0.35))
			draw_circle(bomb_pos, bomb_radius, Color(0.4, 0.8, 1.0, 0.85))
			# Núcleo brillante
			draw_circle(bomb_pos, 5.0, Color.WHITE)
			
			# Rayos giratorios
			var spin_angle = (Time.get_ticks_msec() / 1000.0) * 12.0
			for i in range(3):
				var ang = spin_angle + (float(i) / 3.0) * TAU
				var spark_pos = bomb_pos + Vector2(cos(ang), sin(ang)) * (bomb_radius + 3.0)
				draw_circle(spark_pos, 2.0, Color(0.8, 0.95, 1.0, 0.95))
				draw_line(bomb_pos, spark_pos, Color(0.5, 0.9, 1.0, 0.6), 1.5)
		"mine":
			draw_circle(Vector2.ZERO, 10, Color.WHITE)
			draw_circle(Vector2.ZERO, 12, Color(1, 1, 1, 0.3), false, 3.0)
		"hook":
			draw_line(Vector2(0, 0), Vector2(-20, 0), Color.GRAY, 2.0)
			draw_arc(Vector2(5, 0), 10, -PI/2, PI/2, 8, Color.GRAY, 3.0)
		"melee":
			# Reemplazado por fireballs 3D en _setup_visual_sprite()
			pass
		"heal":
			if is_instance_valid(world_root_3d):
				return
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
			# Aguja/Cristal Rúnico Plateado con Canal de Sangre (Sifón)
			var length = 18.0
			var half_w = 4.0
			
			# Cuerpo plateado/cristal (rombo alargado)
			var pts = PackedVector2Array([
				Vector2(-length, 0),
				Vector2(0, -half_w),
				Vector2(length, 0),
				Vector2(0, half_w)
			])
			draw_polygon(pts, [Color(0.85, 0.85, 0.9, 0.85)]) # Plateado/Cristal
			draw_polyline(pts, Color(0.65, 0.05, 0.75, 0.9), 1.5) # Bordes mágicos púrpuras
			
			# Canal de sangre central (haz rojo carmesí brillante de punta a punta)
			draw_line(Vector2(-length + 2.0, 0), Vector2(length - 2.0, 0), Color(0.95, 0.05, 0.1, 0.95), 2.5)
			
			# Cámara central / Gema brillante en el centro
			var time_f = Time.get_ticks_msec() / 1000.0
			var pulse = sin(time_f * 15.0) * 1.0
			draw_circle(Vector2.ZERO, 3.5 + pulse, Color(0.95, 0.05, 0.15, 0.8)) # Brillo rojo carmesí
			draw_circle(Vector2.ZERO, 2.0, Color.WHITE) # Lente central
			
			# Runas místicas grabadas a los lados (líneas púrpuras sutiles)
			draw_line(Vector2(-6, -2), Vector2(-4, -2), Color(0.8, 0.1, 0.95, 0.75), 1.0)
			draw_line(Vector2(4, 2), Vector2(6, 2), Color(0.8, 0.1, 0.95, 0.75), 1.0)
		"emp":
			if is_instance_valid(world_root_3d):
				return
			# Dibujar líneas verticales sutiles que representan el frente del haz de viento (de Y=-30 a Y=30)
			draw_line(Vector2(0, -30), Vector2(0, 30), Color(0.1, 0.5, 1.0, 0.45), 4.0)
			draw_line(Vector2(-8, -20), Vector2(-8, 20), Color(0.3, 0.7, 1.0, 0.25), 2.0)
			draw_line(Vector2(8, -20), Vector2(8, 20), Color(0.3, 0.7, 1.0, 0.25), 2.0)

func release_orbit():
	orbit_target = null

func _physics_process(delta):
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
		
		# Sincronización de visuales 3D (Fire Balls)
		if _melee_fireballs_3d.size() == 4:
			var map_for_fb = get_tree().get_first_node_in_group("map")
			var s_factor = 0.02
			var correction_z = 1.41421356
			if is_instance_valid(map_for_fb):
				if "scale_factor" in map_for_fb: s_factor = map_for_fb.scale_factor
				if "correction_z" in map_for_fb: correction_z = map_for_fb.correction_z
			
			var blade_positions_2d = [pos_izq, pos_der, pos_tras_izq, pos_tras_der]
			for i in 4:
				var blade_global_2d = global_position + blade_positions_2d[i]
				var pos_3d = Vector3(
					blade_global_2d.x * s_factor,
					0.0,
					blade_global_2d.y * s_factor * correction_z
				)
				if is_instance_valid(_melee_fireballs_3d[i]):
					_melee_fireballs_3d[i].position = pos_3d
				_melee_blade_positions_3d[i] = pos_3d
				
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
		queue_redraw()
	else:
		global_position += move_step
	
	if type == "electron":
		queue_redraw()
	
	if max_range > 0:
		var dist = global_position.distance_to(_start_pos)
		if dist >= max_range:
			if type == "mine":
				global_position = _start_pos + (_start_pos.direction_to(global_position) * max_range)
				velocity = Vector2.ZERO
			elif type == "electron":
				global_position = _start_pos + (_start_pos.direction_to(global_position) * max_range)
				_explode()
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
	if type == "electron": return
	
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
		var dmg_to_deal = damage
		if type == "heal":
			dmg_to_deal = 0.0
			var is_target_ally = false
			if body.has_method("get") and body.get("_is_ally") == true:
				is_target_ally = true
			elif body.is_in_group("player"):
				is_target_ally = true
				
			if is_target_ally:
				# Si es del clan o equipo, curar al objetivo
				_predict_local_heal(body, damage)
			else:
				# Si es enemigo en combate, redirigir la curación al emisor del proyectil
				if is_instance_valid(_owner_node):
					_predict_local_heal(_owner_node, damage)
					
		body.take_damage(dmg_to_deal, global_position, owner_id)
		
		if NetworkManager:
			if owner_type == "player" and body.is_in_group("enemies"):
				if type == "fear":
					NetworkManager.send_event("fearSphereHit", {"enemyId": body.entity_id, "damage": damage, "duration": float(get_meta("duration")) if has_meta("duration") else 3000.0})
				else:
					NetworkManager.send_event("enemyHit", {"enemyId": body.entity_id, "damage": damage})
			elif owner_type == "player" and is_pvp_target:
				if type == "fear":
					NetworkManager.send_event("fearSphereHit", {"victimId": body.entity_id, "damage": damage, "duration": float(get_meta("duration")) if has_meta("duration") else 3000.0})
				else:
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

func _on_body_shape_entered(_body_rid, body, _body_shape_index, local_shape_index):
	if type != "melee": return
	if _has_hit: return
	if not body.has_method("take_damage"): return
	
	if local_shape_index >= 0 and local_shape_index < _melee_blade_positions_3d.size():
		var pos_3d = _melee_blade_positions_3d[local_shape_index]
		if pos_3d.length_squared() > 0.001:
			var map_node = get_tree().get_first_node_in_group("map")
			if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
				var target_vp = map_node.sub_viewport
				if VFX_Fire_ball_type_B_scene:
					var impact = VFX_Fire_ball_type_B_scene.instantiate()
					impact.name = "MeleeImpact3D_" + str(get_instance_id())
					target_vp.add_child(impact)
					impact.position = pos_3d
					impact.scale = Vector3(0.5, 0.5, 0.5)
					var tw = impact.create_tween()
					tw.tween_interval(0.5)
					tw.tween_callback(impact.queue_free)

var _is_exploding: bool = false

func _explode():
	if _is_exploding: return
	_is_exploding = true
	
	if type == "electron":
		_has_hit = true
		var radius = float(get_meta("explosionRadius", 120.0)) if has_meta("explosionRadius") else 120.0
		
		# 1. Efecto visual de explosión eléctrica de área
		var particles = CPUParticles2D.new()
		particles.amount = 75
		particles.lifetime = 0.5
		particles.one_shot = true
		particles.explosiveness = 0.9
		particles.spread = 180.0
		particles.gravity = Vector2.ZERO
		particles.initial_velocity_min = 150.0
		particles.initial_velocity_max = 300.0
		particles.scale_amount_min = 3.0
		particles.scale_amount_max = 8.0
		particles.z_index = 6
		
		var grad = Gradient.new()
		grad.set_color(0, Color(0.2, 0.7, 1.0, 0.95)) # Azul/Celeste eléctrico brillante
		grad.add_point(0.4, Color(0.5, 0.9, 1.0, 0.85)) # Blanco celeste núcleo
		grad.add_point(0.7, Color(0.0, 0.3, 0.8, 0.4)) # Azul profundo desvanecido
		grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		particles.color_ramp = grad
		
		particles.global_position = global_position
		get_parent().add_child(particles)
		particles.emitting = true
		get_tree().create_timer(0.6).timeout.connect(particles.queue_free)
		
		# Anillo de onda de choque eléctrico en área
		var wave = Line2D.new()
		wave.width = 4.0
		wave.default_color = Color(0.3, 0.8, 1.0, 0.8)
		get_parent().add_child(wave)
		var pts = PackedVector2Array()
		var steps = 32
		for i in range(steps + 1):
			var a = (float(i) / steps) * TAU
			pts.append(Vector2(cos(a), sin(a)) * radius)
		wave.points = pts
		wave.global_position = global_position
		
		var tw = wave.create_tween()
		tw.tween_property(wave, "scale", Vector2(1.2, 1.2), 0.3)
		tw.parallel().tween_property(wave, "default_color:a", 0.0, 0.3)
		tw.finished.connect(wave.queue_free)
		
		# 2. Buscar y dañar enemigos/jugadores en el radio de la explosión
		var targets_hit = []
		var entities = get_tree().get_nodes_in_group("entities")
		for ent in entities:
			if not is_instance_valid(ent) or ent.get("is_dead") == true: continue
			
			var ent_eid = ""
			if "entity_id" in ent: ent_eid = str(ent.entity_id)
			if ent_eid == owner_id: continue
			
			var dist = global_position.distance_to(ent.global_position)
			if dist <= radius:
				targets_hit.append(ent)
				
		for ent in targets_hit:
			ent.take_damage(damage, global_position, owner_id)
			if NetworkManager:
				if owner_type == "player" and ent.is_in_group("enemies"):
					NetworkManager.send_event("enemyHit", {"enemyId": ent.entity_id, "damage": damage})
				elif owner_type == "player" and (ent.is_in_group("remote_players") or ent.is_in_group("player")):
					NetworkManager.send_event("playerHitByPlayer", {"victimId": ent.entity_id, "damage": damage})
					
		queue_free()
		return

	if type == "siphon":
		# 1. Efecto de Impacto (Destello de Cristal Rompiéndose)
		var sparks_impact = CPUParticles2D.new()
		sparks_impact.amount = 20
		sparks_impact.lifetime = 0.3
		sparks_impact.one_shot = true
		sparks_impact.explosiveness = 1.0
		sparks_impact.spread = 180.0
		sparks_impact.gravity = Vector2.ZERO
		sparks_impact.initial_velocity_min = 100.0
		sparks_impact.initial_velocity_max = 220.0
		sparks_impact.scale_amount_min = 1.5
		sparks_impact.scale_amount_max = 4.0
		
		var spark_grad = Gradient.new()
		spark_grad.set_color(0, Color(1.0, 0.95, 0.95, 0.95)) # Cristal blanco brillante
		spark_grad.add_point(0.3, Color(0.95, 0.05, 0.15, 0.85)) # Rojo carmesí
		spark_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		sparks_impact.color_ramp = spark_grad
		
		sparks_impact.global_position = global_position
		get_parent().add_child(sparks_impact)
		sparks_impact.emitting = true
		
		get_tree().create_timer(0.4).timeout.connect(sparks_impact.queue_free)
		
		# 2. Retribución "Chupasangre" (Trayectorias de espirales rojas hacia el atacante)
		if is_instance_valid(_owner_node):
			var ret = Node2D.new()
			ret.top_level = true
			ret.global_position = global_position
			get_parent().add_child(ret)
			
			var p_ret = CPUParticles2D.new()
			p_ret.amount = 30
			p_ret.lifetime = 0.3
			p_ret.gravity = Vector2.ZERO
			p_ret.scale_amount_min = 2.0
			p_ret.scale_amount_max = 5.0
			p_ret.color = Color(0.95, 0.05, 0.1, 0.9) # Rojo brillante sangre
			ret.add_child(p_ret)
			p_ret.emitting = true
			
			var line = Line2D.new()
			line.width = 3.5
			line.default_color = Color(0.95, 0.1, 0.15, 0.9) # Rastro rojo
			line.points = PackedVector2Array([Vector2.ZERO, Vector2(-8, 0)])
			ret.add_child(line)
			
			# Script inline para la trayectoria espiral hacia el emisor
			var inline_script = GDScript.new()
			inline_script.source_code = "extends Node2D\n" + \
				"var start_pos: Vector2\n" + \
				"var owner_ref: Node2D\n" + \
				"var duration: float = 0.5\n" + \
				"var elapsed: float = 0.0\n" + \
				"func _process(delta):\n" + \
				"	if not is_instance_valid(owner_ref):\n" + \
				"		queue_free()\n" + \
				"		return\n" + \
				"	elapsed += delta\n" + \
				"	var t = elapsed / duration\n" + \
				"	if t >= 1.0:\n" + \
				"		queue_free()\n" + \
				"		return\n" + \
				"	var target_pos = owner_ref.global_position\n" + \
				"	var base_pos = start_pos.lerp(target_pos, t)\n" + \
				"	var dir = (target_pos - start_pos).normalized()\n" + \
				"	var perp = Vector2(-dir.y, dir.x)\n" + \
				"	var freq = 4.0 * PI\n" + \
				"	var amp = 35.0 * (1.0 - t)\n" + \
				"	var offset = perp * sin(t * freq) * amp\n" + \
				"	global_position = base_pos + offset\n"
			inline_script.reload()
			ret.set_script(inline_script)
			ret.set("start_pos", global_position)
			ret.set("owner_ref", _owner_node)
			ret.set_process(true)

	# Spawn 3D hit impact effect for heal projectiles
	if type == "heal":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Hit_cyber_scene:
				var hit_node = VFX_Hit_cyber_scene.instantiate()
				hit_node.name = "HealHit3D_" + str(get_instance_id())
				target_vp.add_child(hit_node)
				
				# Posicionarlo en el lugar exacto del impacto a altura de la nave (0.0)
				var s_factor = 0.02
				var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
				hit_node.position.x = global_position.x * s_factor
				hit_node.position.z = global_position.y * s_factor * correction_z
				hit_node.position.y = 0.0
				hit_node.scale = Vector3(1.5, 1.5, 1.5)
				
				# Auto-liberar al terminar la animación
				var anim = hit_node.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(hit_node.queue_free.unbind(1))
				else:
					var tw = hit_node.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(hit_node.queue_free)

	# Spawn 3D hit impact effect for emp (hadouken) projectiles
	if type == "emp":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Hit_hadouken_scene:
				var hit_node = VFX_Hit_hadouken_scene.instantiate()
				hit_node.name = "HadoukenHit3D_" + str(get_instance_id())
				target_vp.add_child(hit_node)
				
				# Posicionarlo en el lugar exacto del impacto a altura de la nave (0.0)
				var s_factor = 0.02
				var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
				hit_node.position.x = global_position.x * s_factor
				hit_node.position.z = global_position.y * s_factor * correction_z
				hit_node.position.y = 0.0
				hit_node.scale = Vector3(1.5, 1.5, 1.5)
				
				# Auto-liberar al terminar la animación
				var anim = hit_node.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(hit_node.queue_free.unbind(1))
				else:
					var tw = hit_node.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(hit_node.queue_free)

	# Spawn 3D hit impact effect for laser projectiles
	if type == "laser":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Laser_Hit_scene:
				var hit_node = VFX_Laser_Hit_scene.instantiate()
				hit_node.name = "LaserHit3D_" + str(get_instance_id())
				target_vp.add_child(hit_node)
				
				var s_factor = 0.02
				var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
				hit_node.position.x = global_position.x * s_factor
				hit_node.position.z = global_position.y * s_factor * correction_z
				hit_node.position.y = 0.0
				hit_node.scale = Vector3(1.5, 1.5, 1.5)
				
				var anim = hit_node.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(hit_node.queue_free.unbind(1))
				else:
					var tw = hit_node.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(hit_node.queue_free)

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

func _predict_local_heal(target: Node2D, amount: float):
	if not is_instance_valid(target): return
	
	var heal_shield = 0.0
	var heal_hp = 0.0
	
	# Curar escudo primero
	if "current_shield" in target and "max_shield" in target:
		var sh_needed = target.max_shield - target.current_shield
		if sh_needed > 0.0:
			heal_shield = min(amount, sh_needed)
			target.current_shield += heal_shield
			amount -= heal_shield
			
	# Curar vida con lo restante
	if amount > 0.0 and "current_hp" in target and "max_hp" in target:
		var hp_needed = target.max_hp - target.current_hp
		if hp_needed > 0.0:
			heal_hp = min(amount, hp_needed)
			target.current_hp += heal_hp
			
	# Disparar texto flotante
	if heal_shield > 0.0:
		if target.has_method("_spawn_damage_text"):
			target.call("_spawn_damage_text", "+" + str(int(heal_shield)), Color(0.0, 0.9, 0.9)) # Celeste
	if heal_hp > 0.0:
		if target.has_method("_spawn_damage_text"):
			target.call("_spawn_damage_text", "+" + str(int(heal_hp)), Color.GREEN) # Verde
		
	# Actualizar etiquetas de vida/escudo y stats locales
	if target.has_method("_update_tags"):
		target.call("_update_tags")
	if target.is_in_group("player") and target.has_method("_emit_stats"):
		target.call("_emit_stats")
