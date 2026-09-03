extends Area2D
class_name Projectile

# Pre-cargado estático de escenas VFX para optimizar FPS en ráfagas de red (v313.1)
const VFX_Anticipation_wave_digital_scene = "res://VFX/scenes/VFX_Anticipation_wave_digital.tscn"
const VFX_Anticipation_hadouken_scene = "res://VFX/scenes/VFX_Anticipation_hadouken.tscn"
const VFX_Hadouken_scene = "res://VFX/scenes/VFX_Hadouken.tscn"
const VFX_Cube_projectile_scene = "res://VFX/scenes/VFX_Cube_projectile.tscn"
const VFX_Hit_cyber_scene = "res://VFX/scenes/VFX_Hit_cyber.tscn"
const VFX_Hit_hadouken_scene = "res://VFX/scenes/VFX_Hit_hadouken.tscn"
const VFX_Laser_projectile_scene = "res://VFX/scenes/VFX_Laser_projectile.tscn"
const VFX_Laser_Hit_scene = "res://VFX/scenes/VFX_Laser_Hit.tscn"
const VFX_Siphon_projectile_scene = "res://VFX/scenes/VFX_Siphon_projectile.tscn"
const VFX_Siphon_Hit_scene = "res://VFX/scenes/VFX_Siphon_Hit.tscn"
const VFX_Fire_ball_type_B_scene = "res://VFX/scenes/VFX_Fire_ball_type_B.tscn"
const VFX_Fire_strike_scene = "res://VFX/scenes/VFX_Fire_strike.tscn"

# Pre-cargado estático de texturas para evitar I/O bloqueante
const TEXTURE_MISSILE = preload("res://assets/Municiones/Misiles/Misil1/Misil1.png")
const TEXTURE_MINE = preload("res://assets/Municiones/Minas/Mina1/Mina1.png")
const TEXTURE_MINE_3 = preload("res://assets/Municiones/Minas/Mina3/Mina3.png")
const TEXTURE_MINE_2 = preload("res://assets/Municiones/Minas/Mina2/Mina2.png")
const TEXTURE_SIPHON = preload("res://assets/Municiones/Siphon/Siphon1/Siphon1.png")
const TEXTURE_LASER = preload("res://assets/Municiones/Lasers/Laser1/Laser1.png")

const TEXTURE_CACHE = {
	"missile": TEXTURE_MISSILE,
	"ice_missile": TEXTURE_MISSILE,
	"mine": TEXTURE_MINE,
	"orbital_mine": TEXTURE_MINE_3,
	"hook": TEXTURE_MINE_2,
	"siphon": TEXTURE_SIPHON,
	"laser": TEXTURE_LASER
}

# Projectile.gd (v141.72 - CONE EMP & VECTOR RENDERING)
# Clase base para todos los proyectiles con soporte de colisión y efectos cónicos para EMP. 

@export var speed: float = 800.0
@export var damage: float = 10.0
@export var owner_id: String = ""
@export var type: String = "laser" # laser, missile, mine

var owner_type: String = "player"
var enemy_type: String = "1" 
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

# Referencias para animación y efectos de Mega Láser (v315)
var _laser_hit_3d: Node3D = null
var _laser_glow_mat: StandardMaterial3D = null
var _laser_beam_mat: StandardMaterial3D = null
var _laser_core_mat: StandardMaterial3D = null
var _laser_glow_mesh: MeshInstance3D = null
var _laser_beam_mesh: MeshInstance3D = null
var _laser_core_mesh: MeshInstance3D = null
var _hook_chain_3d: MeshInstance3D = null
var _bomb_ground_marker: Node3D = null
var _bomb_radius: float = 150.0

# v410: Variables de polimorfia
var poly_duration: float = 4.0
var poly_can_move: bool = false
var poly_can_use_skills: bool = false

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
		# El tipo "electron" maneja su propia posición 3D en _physics_process (parábola)
		if type != "electron":
			world_root_3d.position.x = global_position.x * s_factor
			world_root_3d.position.z = global_position.y * s_factor * correction_z
			
			if type == "mine" or type == "orbital_mine":
				world_root_3d.position.y = 0.1
			else:
				# Vuela a una altura de soporte constante
				world_root_3d.position.y = 0.8
		if type == "mega_laser":
			var dir_2d = Vector2.RIGHT.rotated(rotation)
			var diff_3d = Vector3(dir_2d.x * s_factor, 0.0, dir_2d.y * s_factor * correction_z)
			world_root_3d.rotation.y = atan2(-diff_3d.x, -diff_3d.z)
			
			# 1. Fluctuación y vibración dinámica del rayo láser
			var time = Time.get_ticks_msec() / 1000.0
			var scale_pulse = 1.0 + sin(time * 45.0) * 0.15
			var scale_pulse_core = 1.0 + cos(time * 60.0) * 0.2
			
			if is_instance_valid(_laser_beam_mesh):
				_laser_beam_mesh.scale.x = scale_pulse
				_laser_beam_mesh.scale.y = scale_pulse
			if is_instance_valid(_laser_core_mesh):
				_laser_core_mesh.scale.x = scale_pulse_core
				_laser_core_mesh.scale.y = scale_pulse_core
			if is_instance_valid(_laser_glow_mesh):
				_laser_glow_mesh.scale.x = 1.0 + sin(time * 30.0) * 0.1
				_laser_glow_mesh.scale.y = 1.0 + sin(time * 30.0) * 0.1
				
			if is_instance_valid(_laser_glow_mat):
				_laser_glow_mat.emission_energy_multiplier = 2.0 + sin(time * 35.0) * 0.4
			if is_instance_valid(_laser_beam_mat):
				_laser_beam_mat.emission_energy_multiplier = 5.0 + cos(time * 50.0) * 1.5
			if is_instance_valid(_laser_core_mat):
				_laser_core_mat.emission_energy_multiplier = 8.0 + sin(time * 70.0) * 2.0
				
			# 2. Posicionamiento del Hit VFX en la punta del láser
			if is_instance_valid(_laser_hit_3d):
				var length = max_range if max_range > 0.0 else 1000.0
				var beam_len_3d = length * s_factor
				var forward = -world_root_3d.global_transform.basis.z.normalized()
				_laser_hit_3d.global_position = world_root_3d.global_position + forward * beam_len_3d
				_laser_hit_3d.global_position.y = world_root_3d.position.y + 0.1
		else:
			world_root_3d.rotation.y = -rotation - PI/2.0

		if type == "hook" and is_instance_valid(_hook_chain_3d) and is_instance_valid(_owner_node):
			var map_n = get_tree().get_first_node_in_group("map")
			var sf = map_n.scale_factor if is_instance_valid(map_n) and "scale_factor" in map_n else 0.02
			var cz = map_n.correction_z if is_instance_valid(map_n) and "correction_z" in map_n else 1.41421356

			var owner_3d = Vector3(
				_owner_node.global_position.x * sf,
				_owner_node.world_root_3d.position.y if is_instance_valid(_owner_node.get("world_root_3d")) else 1.0,
				_owner_node.global_position.y * sf * cz
			)
			var hook_3d = world_root_3d.global_position
			var mid = (owner_3d + hook_3d) / 2.0
			var dist = owner_3d.distance_to(hook_3d)

			_hook_chain_3d.global_position = mid
			_hook_chain_3d.scale.y = max(dist, 0.01)
			if not mid.is_equal_approx(hook_3d):
				var dir = (hook_3d - mid).normalized()
				var up_vec = Vector3.UP
				if abs(dir.dot(Vector3.UP)) > 0.99:
					up_vec = Vector3.FORWARD
				_hook_chain_3d.look_at(hook_3d, up_vec)
			_hook_chain_3d.rotate_object_local(Vector3.RIGHT, PI / 2)


func setup(p_pos: Vector2, p_angle: float, p_data: Dictionary):
	global_position = p_pos
	rotation = p_angle
	type = p_data.get("bulletType", p_data.get("type", "laser"))
	print("[PROJECTILE SETUP] type = ", type, " | p_data = ", p_data)
	owner_id = str(p_data.get("enemyId", p_data.get("id", p_data.get("senderId", p_data.get("entityId", "")))))
	owner_type = p_data.get("owner_type", "player")
	enemy_type = str(p_data.get("enemyType", "1"))
	
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
	if lifetime <= 0:
		if p_data.get("isOrbiting", false):
			lifetime = 10.0 # Darle tiempo suficiente para la fase de órbita y disparo
		elif speed > 0 and max_range > 0:
			lifetime = max_range / speed + 1.0
		else:
			lifetime = 3.0
	turn_speed = _safe_float(p_data.get("turnSpeed"), 2.5)
	is_homing = bool(p_data.get("isHoming", false))
	_bomb_radius = _safe_float(p_data.get("radius", p_data.get("explosionRadius", 150.0)), 150.0)
	if _bomb_radius <= 1.0:
		_bomb_radius = 150.0
	
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
	
	if type == "polymorph":
		poly_duration = _safe_float(p_data.get("polyDuration", 4000), 4000) / 1000.0
		poly_can_move = bool(p_data.get("canMove", false))
		poly_can_use_skills = bool(p_data.get("canUseSkills", false))
	
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
				var antic = VFXSystem.get_vfx_from_pool(VFX_Anticipation_wave_digital_scene)
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
				antic.position.y = (_owner_node.world_root_3d.position.y + 0.2) if is_instance_valid(_owner_node) and is_instance_valid(_owner_node.get("world_root_3d")) else 1.2
				antic.scale = Vector3(1.2, 1.2, 1.2)
				
				# Sincronizar la rotación del aura 3D con la dirección del disparo
				antic.rotation.y = -p_angle - PI/2.0
				
				# Auto-liberar al terminar la animación
				var anim = antic.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(func(_a): VFXSystem.recycle_vfx_to_pool(antic), CONNECT_ONE_SHOT)
				else:
					var tw = antic.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(func(): VFXSystem.recycle_vfx_to_pool(antic))

	# Spawn 3D anticipation aura for emp (hadouken) projectiles
	if type == "emp":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Anticipation_hadouken_scene:
				var antic = VFXSystem.get_vfx_from_pool(VFX_Anticipation_hadouken_scene)
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
				antic.position.y = (_owner_node.world_root_3d.position.y + 0.2) if is_instance_valid(_owner_node) and is_instance_valid(_owner_node.get("world_root_3d")) else 1.2
				antic.scale = Vector3(1.2, 1.2, 1.2)
				
				# Sincronizar la rotación del aura 3D con la dirección del disparo
				antic.rotation.y = -p_angle - PI/2.0
				
				# Auto-liberar al terminar la animación
				var anim = antic.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(func(_a): VFXSystem.recycle_vfx_to_pool(antic), CONNECT_ONE_SHOT)
				else:
					var tw = antic.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(func(): VFXSystem.recycle_vfx_to_pool(antic))

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
				world_root_3d = VFXSystem.get_vfx_from_pool(VFX_Hadouken_scene)
				world_root_3d.name = "HadoukenProj3D_" + str(get_instance_id())
				target_vp.add_child(world_root_3d)
				
				# Escala 3D óptima
				world_root_3d.scale = Vector3(1.5, 1.5, 1.5)
				
				# Conectar la limpieza al salir del árbol
				tree_exiting.connect(func():
					if is_instance_valid(world_root_3d):
						VFXSystem.recycle_vfx_to_pool(world_root_3d)
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
					var fb = VFXSystem.get_vfx_from_pool(VFX_Fire_ball_type_B_scene)
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
							VFXSystem.recycle_vfx_to_pool(fb)
				)
		return
		
	# Efecto 3D de proyectil curativo (glowing green cube)
	if type == "heal":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Cube_projectile_scene:
				world_root_3d = VFXSystem.get_vfx_from_pool(VFX_Cube_projectile_scene)
				world_root_3d.name = "HealProj3D_" + str(get_instance_id())
				target_vp.add_child(world_root_3d)
				
				# Escala 3D óptima
				world_root_3d.scale = Vector3(1.5, 1.5, 1.5)
				
				# Conectar la limpieza al salir del árbol
				tree_exiting.connect(func():
					if is_instance_valid(world_root_3d):
						VFXSystem.recycle_vfx_to_pool(world_root_3d)
				)
				
				sprite = null
				return
		
	# Modelo 3D para Siphon usando escena VFX pool
	if type == "siphon":
		print("[SIPHON DEBUG] type = ", type, " - spawning 3D")
		sprite = null
		var map_node = get_tree().get_first_node_in_group("map")
		print("[SIPHON DEBUG] map_node = ", map_node)
		if is_instance_valid(map_node):
			print("[SIPHON DEBUG] map_node.sub_viewport = ", map_node.get("sub_viewport"))
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			print("[SIPHON DEBUG] VFX_Siphon_projectile_scene = ", VFX_Siphon_projectile_scene)
			if VFX_Siphon_projectile_scene:
				world_root_3d = VFXSystem.get_vfx_from_pool(VFX_Siphon_projectile_scene)
				print("[SIPHON DEBUG] world_root_3d = ", world_root_3d)
				if is_instance_valid(world_root_3d):
					world_root_3d.name = "SiphonProj3D_" + str(get_instance_id())
					target_vp.add_child(world_root_3d)
					
					world_root_3d.scale = Vector3(0.6, 0.6, 0.6)
					
					tree_exiting.connect(func():
						if is_instance_valid(world_root_3d):
							VFXSystem.recycle_vfx_to_pool(world_root_3d)
					)
					
					return
				else:
					print("[SIPHON ERROR] Failed to get VFX from pool!")
			else:
				print("[SIPHON ERROR] VFX_Siphon_projectile_scene is empty!")
		else:
			print("[SIPHON DEBUG] No map node or sub_viewport, falling back to 2D")
		# NO return here - allow fallback to 2D if 3D fails

	# Efecto 3D de proyectil Láser (cubo rojo con estela) - v530.5 fix visibilidad (horizontal + fallback)
	if type == "laser":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Laser_projectile_scene:
				world_root_3d = VFXSystem.get_vfx_from_pool(VFX_Laser_projectile_scene)
				if is_instance_valid(world_root_3d):
					world_root_3d.name = "LaserProj3D_" + str(get_instance_id())
					target_vp.add_child(world_root_3d)
					
					world_root_3d.scale = Vector3(0.85, 0.85, 0.85)
					
					tree_exiting.connect(func():
						if is_instance_valid(world_root_3d):
							VFXSystem.recycle_vfx_to_pool(world_root_3d)
					)
					
					sprite = null
					return
				else:
					print("[LASER FIX] Pool devolvio null, usando fallback 2D")
		else:
			print("[LASER FIX] map_node o sub_viewport nulo, usando fallback 2D. map_node=", map_node)
		# No return -> cae al fallback 2D de sprite/_draw para garantizar visibilidad

	# Efecto 3D de proyectil de fuego (Fire Strike) para misiles
	if type == "missile" or type == "ice_missile":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Fire_strike_scene:
				world_root_3d = VFXSystem.get_vfx_from_pool(VFX_Fire_strike_scene)
				world_root_3d.name = "MissileProj3D_" + str(get_instance_id())
				target_vp.add_child(world_root_3d)
				
				world_root_3d.scale = Vector3(0.75, 0.75, 0.75)
				
			# Auto-limpiar el nodo 3D cuando el proyectil 2D se destruye
			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					VFXSystem.recycle_vfx_to_pool(world_root_3d)
			)
			
			# Tinte azul para misiles de hielo
			if type == "ice_missile":
				var mesh = world_root_3d.get_node_or_null("MeshInstance3D")
				if mesh and mesh.material_override:
					var mat = mesh.material_override.duplicate()
					mat.albedo_color = Color(0.4, 0.7, 2.0)
					mesh.material_override = mat
				
				sprite = null
				return

	if type == "mine":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			world_root_3d = Node3D.new()
			world_root_3d.name = "Mine3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)

			var core = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			core.mesh = sphere
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.15, 0.05)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.15, 0.05)
			mat.emission_energy_multiplier = 5.0
			core.material_override = mat
			world_root_3d.add_child(core)

			var ring = MeshInstance3D.new()
			var ring_mesh = CylinderMesh.new()
			ring_mesh.top_radius = 0.7
			ring_mesh.bottom_radius = 0.7
			ring_mesh.height = 0.05
			ring.mesh = ring_mesh
			var ring_mat = StandardMaterial3D.new()
			ring_mat.albedo_color = Color(1.0, 0.3, 0.1)
			ring_mat.emission_enabled = true
			ring_mat.emission = Color(1.0, 0.3, 0.1)
			ring_mat.emission_energy_multiplier = 3.0
			ring.material_override = ring_mat
			world_root_3d.add_child(ring)

			var light = OmniLight3D.new()
			light.light_color = Color(1.0, 0.15, 0.05)
			light.light_energy = 3.0
			light.omni_range = 6.0
			world_root_3d.add_child(light)

			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
			)

			sprite = null
			return

	if type == "orbital_mine":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			world_root_3d = Node3D.new()
			world_root_3d.name = "OrbMine3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)

			var core = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.35
			sphere.height = 0.7
			core.mesh = sphere
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.15, 0.6, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.15, 0.6, 1.0)
			mat.emission_energy_multiplier = 4.0
			core.material_override = mat
			world_root_3d.add_child(core)

			var ring = MeshInstance3D.new()
			var ring_mesh = TorusMesh.new()
			ring_mesh.inner_radius = 0.5
			ring_mesh.outer_radius = 0.65
			ring.mesh = ring_mesh
			var ring_mat = StandardMaterial3D.new()
			ring_mat.albedo_color = Color(0.3, 0.8, 1.0)
			ring_mat.emission_enabled = true
			ring_mat.emission = Color(0.3, 0.8, 1.0)
			ring_mat.emission_energy_multiplier = 2.0
			ring.material_override = ring_mat
			ring.rotation.x = PI / 2
			world_root_3d.add_child(ring)

			var light = OmniLight3D.new()
			light.light_color = Color(0.15, 0.6, 1.0)
			light.light_energy = 2.5
			light.omni_range = 5.0
			world_root_3d.add_child(light)

			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
			)

			sprite = null
			return

	if type == "hook":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			var _s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
			world_root_3d = Node3D.new()
			world_root_3d.name = "Hook3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)

			var harpoon_len = 1.0
			var half_len = harpoon_len / 2.0

			var shaft = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.03
			cyl.bottom_radius = 0.03
			cyl.height = harpoon_len
			shaft.mesh = cyl
			shaft.rotation.x = PI / 2
			shaft.position.z = -half_len
			var shaft_mat = StandardMaterial3D.new()
			shaft_mat.albedo_color = Color(0.0, 0.7, 0.7)
			shaft_mat.metallic = 0.9
			shaft_mat.roughness = 0.15
			shaft.material_override = shaft_mat
			world_root_3d.add_child(shaft)

			var tip = MeshInstance3D.new()
			var tip_cyl = CylinderMesh.new()
			tip_cyl.top_radius = 0.0
			tip_cyl.bottom_radius = 0.03
			tip_cyl.height = 0.2
			tip.mesh = tip_cyl
			tip.rotation.x = PI / 2
			tip.position.z = -harpoon_len
			var tip_mat = StandardMaterial3D.new()
			tip_mat.albedo_color = Color(0.0, 0.9, 0.9)
			tip_mat.emission_enabled = true
			tip_mat.emission = Color(0.0, 0.9, 0.9)
			tip_mat.emission_energy_multiplier = 3.0
			tip.material_override = tip_mat
			world_root_3d.add_child(tip)

			for i in 3:
				var ring = MeshInstance3D.new()
				var ring_mesh = CylinderMesh.new()
				ring_mesh.top_radius = 0.06
				ring_mesh.bottom_radius = 0.02
				ring_mesh.height = 0.03
				ring.mesh = ring_mesh
				ring.position.z = -0.65 + i * 0.25
				var ring_mat = StandardMaterial3D.new()
				ring_mat.albedo_color = Color(0.0, 0.6, 0.6)
				ring_mat.metallic = 1.0
				ring_mat.roughness = 0.1
				ring.material_override = ring_mat
				world_root_3d.add_child(ring)

			var orb = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.07
			sphere.height = 0.14
			orb.mesh = sphere
			orb.position.z = 0.05
			var orb_mat = StandardMaterial3D.new()
			orb_mat.albedo_color = Color(0.2, 1.0, 1.0)
			orb_mat.emission_enabled = true
			orb_mat.emission = Color(0.2, 1.0, 1.0)
			orb_mat.emission_energy_multiplier = 6.0
			orb.material_override = orb_mat
			world_root_3d.add_child(orb)

			var light = OmniLight3D.new()
			light.light_color = Color(0.0, 0.8, 1.0)
			light.light_energy = 5.0
			light.omni_range = 4.0
			world_root_3d.add_child(light)

			_hook_chain_3d = MeshInstance3D.new()
			var chain_cyl = CylinderMesh.new()
			chain_cyl.top_radius = 0.008
			chain_cyl.bottom_radius = 0.008
			chain_cyl.height = 1.0
			_hook_chain_3d.mesh = chain_cyl
			var chain_mat = StandardMaterial3D.new()
			chain_mat.albedo_color = Color(0.0, 0.9, 0.9, 0.4)
			chain_mat.emission_enabled = true
			chain_mat.emission = Color(0.0, 0.9, 0.9)
			chain_mat.emission_energy_multiplier = 2.0
			chain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_hook_chain_3d.material_override = chain_mat
			target_vp.add_child(_hook_chain_3d)

			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
				if is_instance_valid(_hook_chain_3d):
					_hook_chain_3d.queue_free()
			)

			sprite = null
			return

	# v325.2: Efecto 3D de proyectil de Miedo (Esfera de Terror)
	if type == "fear":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			world_root_3d = Node3D.new()
			world_root_3d.name = "FearProj3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)

			# Esfera interna oscura
			var core = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.35
			sphere.height = 0.7
			core.mesh = sphere
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.12, 0.0, 0.18)
			mat.metallic = 0.8
			mat.roughness = 0.2
			core.material_override = mat
			world_root_3d.add_child(core)

			# Esfera de brillo púrpura mágica externa
			var glow = MeshInstance3D.new()
			var glow_sphere = SphereMesh.new()
			glow_sphere.radius = 0.45
			glow_sphere.height = 0.9
			glow.mesh = glow_sphere
			var glow_mat = StandardMaterial3D.new()
			glow_mat.albedo_color = Color(0.8, 0.1, 0.9, 0.35)
			glow_mat.emission_enabled = true
			glow_mat.emission = Color(0.8, 0.1, 0.9)
			glow_mat.emission_energy_multiplier = 3.0
			glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glow.material_override = glow_mat
			world_root_3d.add_child(glow)

			# Luz omni de ambiente púrpura
			var light = OmniLight3D.new()
			light.light_color = Color(0.8, 0.1, 0.9)
			light.light_energy = 3.5
			light.omni_range = 5.0
			world_root_3d.add_child(light)

			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
			)

			sprite = null
			return

	if type == "electron":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
			var correction_z = map_node.correction_z if "correction_z" in map_node else 1.41421356

			world_root_3d = Node3D.new()
			world_root_3d.name = "Bomb3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)

			var body = MeshInstance3D.new()
			var body_sphere = SphereMesh.new()
			body_sphere.radius = 0.4
			body_sphere.height = 0.8
			body.mesh = body_sphere
			var body_mat = StandardMaterial3D.new()
			body_mat.albedo_color = Color(0.25, 0.25, 0.25)
			body_mat.metallic = 0.8
			body_mat.roughness = 0.3
			body.material_override = body_mat
			world_root_3d.add_child(body)

			var glow = MeshInstance3D.new()
			var glow_sphere = SphereMesh.new()
			glow_sphere.radius = 0.5
			glow_sphere.height = 1.0
			glow.mesh = glow_sphere
			var glow_mat = StandardMaterial3D.new()
			glow_mat.albedo_color = Color(1.0, 0.4, 0.0, 0.2)
			glow_mat.emission_enabled = true
			glow_mat.emission = Color(1.0, 0.4, 0.0)
			glow_mat.emission_energy_multiplier = 1.0
			glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glow.material_override = glow_mat
			world_root_3d.add_child(glow)

			var fuse = MeshInstance3D.new()
			var fuse_cyl = CylinderMesh.new()
			fuse_cyl.top_radius = 0.03
			fuse_cyl.bottom_radius = 0.05
			fuse_cyl.height = 0.25
			fuse.mesh = fuse_cyl
			var fuse_mat = StandardMaterial3D.new()
			fuse_mat.albedo_color = Color(0.4, 0.3, 0.2)
			fuse.position.y = 1.0
			fuse.material_override = fuse_mat
			world_root_3d.add_child(fuse)

			var spark = MeshInstance3D.new()
			var spark_sphere = SphereMesh.new()
			spark_sphere.radius = 0.06
			spark_sphere.height = 0.12
			spark.mesh = spark_sphere
			var spark_mat = StandardMaterial3D.new()
			spark_mat.albedo_color = Color(1.0, 0.7, 0.0)
			spark_mat.emission_enabled = true
			spark_mat.emission = Color(1.0, 0.7, 0.0)
			spark_mat.emission_energy_multiplier = 8.0
			spark.material_override = spark_mat
			spark.position.y = 0.65
			world_root_3d.add_child(spark)

			var sparks_node = Node3D.new()
			sparks_node.name = "Sparks3D"
			world_root_3d.add_child(sparks_node)
			for i in 3:
				var s = MeshInstance3D.new()
				var ss = SphereMesh.new()
				ss.radius = 0.03
				ss.height = 0.06
				s.mesh = ss
				var sm = StandardMaterial3D.new()
				sm.albedo_color = Color(1.0, 0.8, 0.2)
				sm.emission_enabled = true
				sm.emission = Color(1.0, 0.8, 0.2)
				sm.emission_energy_multiplier = 6.0
				s.material_override = sm
				sparks_node.add_child(s)

			var light = OmniLight3D.new()
			light.light_color = Color(1.0, 0.4, 0.0)
			light.light_energy = 4.0
			light.omni_range = 6.0
			world_root_3d.add_child(light)

			var target_2d = _start_pos + Vector2(cos(rotation), sin(rotation)) * max_range
			# Radio real del AdminDash (guardado en setup como _bomb_radius) -> escalar aro como IceStorm
			var exp_radius = _bomb_radius
			var r3d_bomb = exp_radius * s_factor
			var marker_h = 0.05
			# muestrear altura del terreno como hace Meteor/TormentaHielo
			var _map_b = map_node
			if is_instance_valid(_map_b) and is_instance_valid(_map_b.get("terrain_node")):
				# intentar helper de EntityManager si existe, sino fallback a map_node
				var em_node = get_tree().get_first_node_in_group("world_node")
				if em_node and em_node.has_node("EntityManager"):
					var mgr = em_node.get_node("EntityManager")
					if mgr and mgr.has_method("_sample_terrain_height"):
						marker_h = mgr._sample_terrain_height(target_2d, _map_b) + 0.06
					elif _map_b.has_method("get_terrain_height_at_pos"):
						marker_h = _map_b.get_terrain_height_at_pos(target_2d) + 0.06
				elif _map_b.has_method("get_terrain_height_at_pos"):
					marker_h = _map_b.get_terrain_height_at_pos(target_2d) + 0.06
			var marker_pos = Vector3(target_2d.x * s_factor, marker_h, target_2d.y * s_factor * correction_z)
			_bomb_ground_marker = Node3D.new()
			_bomb_ground_marker.name = "BombMarker_" + str(get_instance_id())
			_bomb_ground_marker.position = marker_pos
			_bomb_ground_marker.scale = Vector3(1.0, 1.0, correction_z)
			target_vp.add_child(_bomb_ground_marker)

			var marker_ring = MeshInstance3D.new()
			var m_ring = TorusMesh.new()
			m_ring.inner_radius = r3d_bomb * 0.92
			m_ring.outer_radius = r3d_bomb
			marker_ring.mesh = m_ring
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = Color(1.0, 0.15, 0.05, 0.7)
			m_mat.emission_enabled = true
			m_mat.emission = Color(1.0, 0.15, 0.05)
			m_mat.emission_energy_multiplier = 2.0
			m_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m_mat.no_depth_test = true
			m_mat.render_priority = 2
			marker_ring.material_override = m_mat
			# Torus default ya es plano XZ como Cylinder, NO rotar PI/2 (eso lo pone vertical)
			marker_ring.position.y = 0.02
			_bomb_ground_marker.add_child(marker_ring)

			var marker_fill = MeshInstance3D.new()
			var m_fill: Mesh = CylinderMesh.new()
			m_fill.top_radius = r3d_bomb * 0.88
			m_fill.bottom_radius = r3d_bomb * 0.88
			m_fill.height = 0.01
			# si hay terreno, usar disco conformante igual que Meteor
			if is_instance_valid(_map_b) and is_instance_valid(_map_b.get("terrain_node")):
				var em_node2 = get_tree().get_first_node_in_group("world_node")
				if em_node2 and em_node2.has_node("EntityManager"):
					var mgr2 = em_node2.get_node("EntityManager")
					if mgr2 and mgr2.has_method("_make_circle_disc_conforming"):
						m_fill = mgr2._make_circle_disc_conforming(target_2d, exp_radius * 0.88, _map_b)
			marker_fill.mesh = m_fill
			var mf_mat = StandardMaterial3D.new()
			mf_mat.albedo_color = Color(1.0, 0.15, 0.05, 0.12)
			mf_mat.emission_enabled = true
			mf_mat.emission = Color(1.0, 0.15, 0.05)
			mf_mat.emission_energy_multiplier = 0.5
			mf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mf_mat.no_depth_test = true
			mf_mat.render_priority = 2
			marker_fill.material_override = mf_mat
			_bomb_ground_marker.add_child(marker_fill)

			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
				if is_instance_valid(_bomb_ground_marker):
					_bomb_ground_marker.queue_free()
			)

			sprite = null
			return

	if type == "shield_steal":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			world_root_3d = Node3D.new()
			world_root_3d.name = "ShieldSteal3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)

			# Orbe celeste (núcleo de energía)
			var core = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.4
			sphere.height = 0.8
			core.mesh = sphere
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.35, 0.85, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.8, 1.0)
			mat.emission_energy_multiplier = 4.0
			core.material_override = mat
			world_root_3d.add_child(core)

			# Anillo de escudo giratorio
			var ring = MeshInstance3D.new()
			var ring_mesh = TorusMesh.new()
			ring_mesh.inner_radius = 0.55
			ring_mesh.outer_radius = 0.7
			ring.mesh = ring_mesh
			var ring_mat = StandardMaterial3D.new()
			ring_mat.albedo_color = Color(0.2, 0.9, 1.0)
			ring_mat.emission_enabled = true
			ring_mat.emission = Color(0.2, 0.9, 1.0)
			ring_mat.emission_energy_multiplier = 2.5
			ring.material_override = ring_mat
			ring.rotation.x = PI / 2
			world_root_3d.add_child(ring)

			var light = OmniLight3D.new()
			light.light_color = Color(0.3, 0.8, 1.0)
			light.light_energy = 2.5
			light.omni_range = 5.0
			world_root_3d.add_child(light)

			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
			)

			sprite = null
			return

	if type == "life_steal":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			world_root_3d = Node3D.new()
			world_root_3d.name = "LifeSteal3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)

			# Orbe verde (núcleo de energía vital)
			var core = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.4
			sphere.height = 0.8
			core.mesh = sphere
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 1.0, 0.4)
			mat.emission_enabled = true
			mat.emission = Color(0.2, 1.0, 0.3)
			mat.emission_energy_multiplier = 4.0
			core.material_override = mat
			world_root_3d.add_child(core)

			# Anillo de vida giratorio
			var ring = MeshInstance3D.new()
			var ring_mesh = TorusMesh.new()
			ring_mesh.inner_radius = 0.55
			ring_mesh.outer_radius = 0.7
			ring.mesh = ring_mesh
			var ring_mat = StandardMaterial3D.new()
			ring_mat.albedo_color = Color(0.2, 0.95, 0.3)
			ring_mat.emission_enabled = true
			ring_mat.emission = Color(0.2, 0.95, 0.3)
			ring_mat.emission_energy_multiplier = 2.5
			ring.material_override = ring_mat
			ring.rotation.x = PI / 2
			world_root_3d.add_child(ring)

			var light = OmniLight3D.new()
			light.light_color = Color(0.3, 1.0, 0.4)
			light.light_energy = 2.5
			light.omni_range = 5.0
			world_root_3d.add_child(light)

			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
			)

			sprite = null
			return

	if type == "polymorph":
		# Cubito 3D como proyectil polimórfico
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			world_root_3d = Node3D.new()
			world_root_3d.name = "PolymorphCube3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)
			
			# Crear el cubo (BoxMesh)
			_orb_mesh = MeshInstance3D.new()
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3(0.35, 0.35, 0.35)
			_orb_mesh.mesh = box_mesh
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.2, 0.8, 1.0, 0.9)
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.8, 1.0)
			mat.emission_energy_multiplier = 3.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_orb_mesh.material_override = mat
			world_root_3d.add_child(_orb_mesh)
			
			# Luz puntual
			var light = OmniLight3D.new()
			light.light_color = Color(0.2, 0.8, 1.0)
			light.light_energy = 2.0
			light.omni_range = 5.0
			world_root_3d.add_child(light)
			
			# Rotación continua del cubo
			var tw = create_tween().set_loops()
			tw.tween_property(world_root_3d, "rotation_degrees", Vector3(0, 360, 0), 1.5).set_trans(Tween.TRANS_LINEAR)
			
			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
			)
		
		sprite = null
		return

	# v413: Calavera Ejecutora (Execution / Instant Kill)
	# Skull 3D con estela estilo proyectil curativo + luz + homing (point & click).
	if type == "execution":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport

			world_root_3d = Node3D.new()
			world_root_3d.name = "ExecutionSkull3D_" + str(get_instance_id())
			target_vp.add_child(world_root_3d)

			world_root_3d.scale = Vector3(0.55, 0.55, 0.55)

			tree_exiting.connect(func():
				if is_instance_valid(world_root_3d):
					world_root_3d.queue_free()
			)

			# --- Cráneo (esfera hueso) ---
			var cranium = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.34
			sphere.height = 0.7
			cranium.mesh = sphere
			var bone_mat = StandardMaterial3D.new()
			bone_mat.albedo_color = Color(0.72, 0.68, 0.62, 0.95)
			bone_mat.emission_enabled = true
			bone_mat.emission = Color(0.75, 0.55, 0.9, 0.35)
			bone_mat.emission_energy_multiplier = 2.0
			bone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cranium.material_override = bone_mat
			world_root_3d.add_child(cranium)

			# --- Ojos vacíos (dos esferas negras hundidas) ---
			for side in [-1, 1]:
				var eye = MeshInstance3D.new()
				var eye_mesh = SphereMesh.new()
				eye_mesh.radius = 0.1
				eye_mesh.height = 0.2
				eye.mesh = eye_mesh
				var eye_mat = StandardMaterial3D.new()
				eye_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.95)
				eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				eye.material_override = eye_mat
				eye.position = Vector3(0.11 * side, 0.03, 0.22)
				cranium.add_child(eye)

			# --- Mandíbula inferior ---
			var jaw = MeshInstance3D.new()
			var jaw_mesh = BoxMesh.new()
			jaw_mesh.size = Vector3(0.55, 0.14, 0.30)
			jaw.mesh = jaw_mesh
			var jaw_mat = StandardMaterial3D.new()
			jaw_mat.albedo_color = Color(0.6, 0.55, 0.5, 0.9)
			jaw_mat.emission_enabled = true
			jaw_mat.emission = Color(0.75, 0.55, 0.9, 0.3)
			jaw_mat.emission_energy_multiplier = 1.5
			jaw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			jaw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			jaw.material_override = jaw_mat
			jaw.position = Vector3(0.0, -0.3, 0.0)
			world_root_3d.add_child(jaw)

			# --- Luz puntual violeta ---
			var light = OmniLight3D.new()
			light.light_color = Color(0.65, 0.45, 0.95)
			light.light_energy = 2.0
			light.omni_range = 4.0
			world_root_3d.add_child(light)

			# --- Estela de partículas (estilo proyectil curativo) ---
			var trail = CPUParticles3D.new()
			trail.one_shot = false
			trail.lifetime = 0.45
			trail.preprocess = 0.2
			trail.amount = 5
			trail.speed_scale = 1.0
			trail.explosiveness = 0.0
			trail.lifetime_randomness = 0.3
			trail.direction = Vector3.BACK
			trail.spread = 25.0
			trail.gravity = Vector3.ZERO
			trail.initial_velocity_min = 0.4
			trail.initial_velocity_max = 1.8
			trail.scale_amount_min = 0.18
			trail.scale_amount_max = 0.32
			trail.color = Color(0.6, 0.35, 0.95, 0.55)
			var grad = Gradient.new()
			grad.set_color(0, Color(0.7, 0.4, 0.95, 0.6))
			grad.add_point(0.5, Color(0.45, 0.25, 0.75, 0.35))
			grad.set_color(1, Color(0.2, 0.1, 0.4, 0.0))
			trail.color_ramp = grad
			var skull_draw_mesh = SphereMesh.new()
			skull_draw_mesh.radius = 0.08
			trail.mesh = skull_draw_mesh
			world_root_3d.add_child(trail)

			sprite = null
			return
	var path = ""
	match type:
		"laser": path = "res://assets/Municiones/Lasers/Laser1/Laser1.png"
		"mine": path = "res://assets/Municiones/Minas/Mina1/Mina1.png"
		"orbital_mine": path = "res://assets/Municiones/Minas/Mina3/Mina3.png"
		"hook": 
			path = "res://assets/Municiones/Minas/Mina2/Mina2.png"
			modulate = Color(0, 1, 1) 
		"siphon": path = "res://assets/Municiones/Siphon/Siphon1/Siphon1.png"
		"shield_steal": 
			path = "res://assets/Municiones/Siphon/Siphon1/Siphon1.png"
			modulate = Color(0.3, 0.85, 1.0)
		"life_steal": 
			path = "res://assets/Municiones/Siphon/Siphon1/Siphon1.png"
			modulate = Color(0.3, 1.0, 0.4)
		"mega_laser":
			var length = max_range if max_range > 0.0 else 1000.0

			for child in get_children():
				if child is CollisionShape2D and child.shape is RectangleShape2D:
					child.shape.size = Vector2(length, 40.0)
					child.position.x = child.shape.size.x / 2.0

			var map_node = get_tree().get_first_node_in_group("map")
			if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
				var target_vp = map_node.sub_viewport
				var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02

				world_root_3d = Node3D.new()
				world_root_3d.name = "MegaLaser3D_" + str(get_instance_id())
				target_vp.add_child(world_root_3d)

				var beam_len_3d = length * s_factor
				var half_len = beam_len_3d / 2.0

				var glow = MeshInstance3D.new()
				var glow_box = BoxMesh.new()
				glow_box.size = Vector3(0.5, 0.5, beam_len_3d)
				glow.mesh = glow_box
				var glow_mat = StandardMaterial3D.new()
				glow_mat.albedo_color = Color(1.0, 0.2, 0.05, 0.3)
				glow_mat.emission_enabled = true
				glow_mat.emission = Color(1.0, 0.15, 0.05)
				glow_mat.emission_energy_multiplier = 2.0
				glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				glow.material_override = glow_mat
				glow.position = Vector3(0, 0.2, -half_len)
				world_root_3d.add_child(glow)
				
				_laser_glow_mesh = glow
				_laser_glow_mat = glow_mat

				var beam_mesh = MeshInstance3D.new()
				var box = BoxMesh.new()
				box.size = Vector3(0.18, 0.18, beam_len_3d)
				beam_mesh.mesh = box
				var mat = StandardMaterial3D.new()
				mat.albedo_color = Color(1.0, 0.25, 0.1)
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.25, 0.1)
				mat.emission_energy_multiplier = 5.0
				beam_mesh.material_override = mat
				beam_mesh.position = Vector3(0, 0.2, -half_len)
				world_root_3d.add_child(beam_mesh)
				
				_laser_beam_mesh = beam_mesh
				_laser_beam_mat = mat

				var core = MeshInstance3D.new()
				var core_box = BoxMesh.new()
				core_box.size = Vector3(0.05, 0.05, beam_len_3d * 0.97)
				core.mesh = core_box
				var core_mat = StandardMaterial3D.new()
				core_mat.albedo_color = Color(1.0, 1.0, 1.0)
				core_mat.emission_enabled = true
				core_mat.emission = Color(1.0, 1.0, 0.95)
				core_mat.emission_energy_multiplier = 8.0
				core.material_override = core_mat
				core.position = Vector3(0, 0.2, -half_len)
				world_root_3d.add_child(core)
				
				_laser_core_mesh = core
				_laser_core_mat = core_mat

				var light = OmniLight3D.new()
				light.light_color = Color(1.0, 0.2, 0.05)
				light.light_energy = 5.0
				light.omni_range = beam_len_3d * 0.6
				light.position = Vector3(0, 0.2, -half_len)
				world_root_3d.add_child(light)

				# Instanciar efecto oficial de impacto de partículas en la punta del láser
				if VFX_Laser_Hit_scene:
					_laser_hit_3d = VFXSystem.get_vfx_from_pool(VFX_Laser_Hit_scene)
					_laser_hit_3d.name = "LaserHit3D_" + str(get_instance_id())
					target_vp.add_child(_laser_hit_3d)

				tree_exiting.connect(func():
					if is_instance_valid(world_root_3d):
						VFXSystem.recycle_vfx_to_pool(world_root_3d)
					if is_instance_valid(_laser_hit_3d):
						VFXSystem.recycle_vfx_to_pool(_laser_hit_3d)
				)

				sprite = null
				return

			var beam_2d = Line2D.new()
			beam_2d.width = 40.0
			beam_2d.default_color = Color(1, 0.2, 0.2, 0.8) 
			beam_2d.points = PackedVector2Array([Vector2.ZERO, Vector2(length, 0)])

			var glow_2d = Line2D.new()
			glow_2d.width = 15.0
			glow_2d.default_color = Color(1, 1, 1, 0.9) 
			glow_2d.points = beam_2d.points
			beam_2d.add_child(glow_2d)

			add_child(beam_2d)
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
			elif type == "shield_steal":
				sprite.modulate = Color(0.3, 0.85, 1.0) 
			elif type == "laser":
				# v530.5 fallback 2D para laser: rojo-naranja brillante
				sprite.modulate = Color(1.2, 0.35, 0.15)
				sprite.scale *= 1.1
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
			if is_instance_valid(world_root_3d):
				return
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
			if is_instance_valid(world_root_3d):
				return
			draw_circle(Vector2.ZERO, 10, Color.WHITE)
			draw_circle(Vector2.ZERO, 12, Color(1, 1, 1, 0.3), false, 3.0)
		"hook":
			if is_instance_valid(world_root_3d):
				return
			draw_line(Vector2(0, 0), Vector2(-20, 0), Color.GRAY, 2.0)
			draw_arc(Vector2(5, 0), 10, -PI/2, PI/2, 8, Color.GRAY, 3.0)
		"shield_steal":
			if is_instance_valid(world_root_3d):
				return
			var pulse = sin(Time.get_ticks_msec() * 0.015) * 2.0
			draw_circle(Vector2.ZERO, 14.0 + pulse, Color(0.2, 0.75, 1.0, 0.4))
			draw_circle(Vector2.ZERO, 9.0, Color(0.3, 0.85, 1.0, 0.9))
			draw_circle(Vector2.ZERO, 4.0, Color.WHITE)
			draw_arc(Vector2.ZERO, 16.0, 0, TAU, 24, Color(0.4, 0.9, 1.0, 0.6), 2.0)
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
			if is_instance_valid(world_root_3d):
				return
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
		"laser":
			if is_instance_valid(world_root_3d):
				return
			# v530.5 fallback 2D para laser: capsula rojo-naranja brillante con estela
			var t_laser = Time.get_ticks_msec() / 1000.0
			var pulse_laser = sin(t_laser * 18.0) * 1.2
			draw_circle(Vector2.ZERO, 10.0 + pulse_laser, Color(1.0, 0.25, 0.08, 0.38))
			draw_circle(Vector2.ZERO, 6.5, Color(1.0, 0.35, 0.12, 0.95))
			draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
			draw_line(Vector2(-14, 0), Vector2(8, 0), Color(1.0, 0.4, 0.15, 0.85), 3.5)
			draw_line(Vector2(-20, 0), Vector2(-14, 0), Color(1.0, 0.2, 0.05, 0.32), 6.0)
		"emp":
			if is_instance_valid(world_root_3d):
				return
			# Dibujar líneas verticales sutiles que representan el frente del haz de viento (de Y=-30 a Y=30)
			draw_line(Vector2(0, -30), Vector2(0, 30), Color(0.1, 0.5, 1.0, 0.45), 4.0)
			draw_line(Vector2(-8, -20), Vector2(-8, 20), Color(0.3, 0.7, 1.0, 0.25), 2.0)
			draw_line(Vector2(8, -20), Vector2(8, 20), Color(0.3, 0.7, 1.0, 0.25), 2.0)

func release_orbit():
	orbit_target = null
	_start_pos = global_position

func stop_orbit():
	if is_instance_valid(orbit_target):
		var time = (Time.get_ticks_msec() / 1000.0) - orbit_start_time
		orbit_angle_offset = time * orbit_speed + orbit_angle_offset
		orbit_speed = 0.0

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
	
	if is_homing and is_instance_valid(_target_node) and type != "mega_laser":
		var target_pos = _target_node.global_position
		var target_angle = (target_pos - global_position).angle()
		rotation = rotate_toward(rotation, target_angle, turn_speed * delta)
		velocity = Vector2.RIGHT.rotated(rotation) * speed
	
	elif type == "mine":
		velocity = velocity.lerp(Vector2.ZERO, 3.5 * delta)
	elif type == "mega_laser":
		if is_instance_valid(_owner_node):
			global_position = _owner_node.global_position
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
	if type == "melee" or type == "mega_laser":
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
		if is_instance_valid(world_root_3d):
			var map_n = get_tree().get_first_node_in_group("map")
			var s_factor = map_n.scale_factor if is_instance_valid(map_n) and "scale_factor" in map_n else 0.02
			var correction_z = map_n.correction_z if is_instance_valid(map_n) and "correction_z" in map_n else 1.41421356
			var total_flight_time = max_range / max(1.0, speed)
			var t = clamp(_current_lifetime / total_flight_time, 0.0, 1.0)
			var time = Time.get_ticks_msec() / 1000.0
			
			var max_h = 4.5 # Altura máxima del arco de la parábola
			var height_y = sin(t * PI) * max_h
			
			# La posición horizontal (X, Z) sigue a la posición 2D actual del proyectil en vuelo
			world_root_3d.position.x = global_position.x * s_factor
			world_root_3d.position.z = global_position.y * s_factor * correction_z
			var base_h = _owner_node.world_root_3d.position.y if is_instance_valid(_owner_node) and is_instance_valid(_owner_node.get("world_root_3d")) else 1.0
			world_root_3d.position.y = base_h + height_y
			
			# Rotación constante en el aire para efecto de giro dinámico
			world_root_3d.rotate_x(delta * 5.0)
			world_root_3d.rotate_y(delta * 2.5)
			
			# Escala suave para aparecer y desaparecer al impactar
			var scale_val = 1.0
			if t < 0.15:
				scale_val = t / 0.15
			elif t > 0.85:
				scale_val = (1.0 - t) / 0.15
			world_root_3d.scale = Vector3(scale_val, scale_val, scale_val)
			var spark_fuse = world_root_3d.get_node_or_null("Sparks3D")
			if is_instance_valid(spark_fuse):
				for i in spark_fuse.get_child_count():
					var s = spark_fuse.get_child(i)
					if is_instance_valid(s):
						var ang = time * 15.0 + (float(i) / float(max(spark_fuse.get_child_count(), 1))) * TAU
						s.position = Vector3(cos(ang) * 0.55, 0.0, sin(ang) * 0.55)
			if is_instance_valid(_bomb_ground_marker):
				var pulse = 1.0 + sin(time * 6.0) * 0.15
				_bomb_ground_marker.scale = Vector3(pulse, 1.0, pulse)
				var marker_ring = _bomb_ground_marker.get_child(0) if _bomb_ground_marker.get_child_count() > 0 else null
				if is_instance_valid(marker_ring) and marker_ring is MeshInstance3D and marker_ring.material_override is StandardMaterial3D:
					var m = marker_ring.material_override
					m.emission_energy_multiplier = 2.0 + sin(time * 5.0) * 1.0
	
	if max_range > 0 and type != "mega_laser":
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
		if type == "shield_steal":
			dmg_to_deal = 0.0
		if type == "life_steal":
			dmg_to_deal = 0.0
		if type == "execution":
			dmg_to_deal = 0.0
		if type == "polymorph":
			dmg_to_deal = damage
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
					
		if type != "shield_steal" and type != "life_steal" and type != "execution":
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
					"stunDuration": float(get_meta("stunDuration", 0)) if has_meta("stunDuration") else 0.0,
					"polyDuration": int(poly_duration * 1000) if type == "polymorph" else 0,
					"polyCanMove": poly_can_move if type == "polymorph" else true,
					"polyCanUseSkills": poly_can_use_skills if type == "polymorph" else true
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
					var impact = VFXSystem.get_vfx_from_pool(VFX_Fire_ball_type_B_scene)
					impact.name = "MeleeImpact3D_" + str(get_instance_id())
					target_vp.add_child(impact)
					impact.position = pos_3d
					impact.scale = Vector3(0.5, 0.5, 0.5)
					var tw = impact.create_tween()
					tw.tween_interval(0.5)
					tw.tween_callback(func(): VFXSystem.recycle_vfx_to_pool(impact))

var _is_exploding: bool = false

func _explode():
	if _is_exploding: return
	_is_exploding = true
	
	if type == "electron":
		_has_hit = true
		var radius = _bomb_radius if _bomb_radius > 1.0 else (float(get_meta("explosionRadius", 120.0)) if has_meta("explosionRadius") else 120.0)
		
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
		grad.set_color(0, Color(1.0, 0.6, 0.1, 0.95))
		grad.add_point(0.4, Color(1.0, 0.85, 0.2, 0.85))
		grad.add_point(0.7, Color(0.8, 0.2, 0.05, 0.4))
		grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		particles.color_ramp = grad
		
		particles.global_position = global_position
		get_parent().add_child(particles)
		particles.emitting = true
		get_tree().create_timer(0.6).timeout.connect(particles.queue_free)
		
		# Anillo de onda de choque eléctrico en área
		var wave = Line2D.new()
		wave.width = 4.0
		wave.default_color = Color(1.0, 0.5, 0.1, 0.8)
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

		# Clean up ground marker
		if is_instance_valid(_bomb_ground_marker):
			var tw_m = _bomb_ground_marker.create_tween()
			tw_m.tween_property(_bomb_ground_marker, "scale", Vector3.ZERO, 0.2)
			tw_m.finished.connect(_bomb_ground_marker.queue_free)
			_bomb_ground_marker = null

		# 3D explosion VFX
		if is_instance_valid(world_root_3d):
			var vp = world_root_3d.get_parent()
			if is_instance_valid(vp):
				var radius_3d = radius * 0.02

				var flash = MeshInstance3D.new()
				var flash_sphere = SphereMesh.new()
				flash_sphere.radius = radius_3d * 0.3
				flash_sphere.height = radius_3d * 0.6
				flash.mesh = flash_sphere
				var flash_mat = StandardMaterial3D.new()
				flash_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
				flash_mat.emission_enabled = true
				flash_mat.emission = Color(1.0, 0.5, 0.1)
				flash_mat.emission_energy_multiplier = 8.0
				flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				flash.material_override = flash_mat
				flash.position = world_root_3d.position
				vp.add_child(flash)
				var tw_f = flash.create_tween()
				tw_f.tween_property(flash, "scale", Vector3(2.5, 2.5, 2.5), 0.3)
				tw_f.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 0.3)
				tw_f.parallel().tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.3)
				tw_f.finished.connect(flash.queue_free)

				# Shockwave plano en el piso (samañado con terrain) - sin PI/2
				var shockwave = MeshInstance3D.new()
				var ring_mesh = TorusMesh.new()
				ring_mesh.inner_radius = radius_3d * 0.5
				ring_mesh.outer_radius = radius_3d * 0.55
				shockwave.mesh = ring_mesh
				var sw_mat = StandardMaterial3D.new()
				sw_mat.albedo_color = Color(1.0, 0.4, 0.05, 0.8)
				sw_mat.emission_enabled = true
				sw_mat.emission = Color(1.0, 0.4, 0.05)
				sw_mat.emission_energy_multiplier = 3.0
				sw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				shockwave.material_override = sw_mat
				# aterrizar en suelo muestreado, no a media altura de la bomba
				var map_n = get_tree().get_first_node_in_group("map")
				var h_exp = 0.08
				if is_instance_valid(map_n):
					var em_n = get_tree().get_first_node_in_group("world_node")
					if em_n and em_n.has_node("EntityManager"):
						var mgr_e = em_n.get_node("EntityManager")
						if mgr_e and mgr_e.has_method("_sample_terrain_height"):
							h_exp = mgr_e._sample_terrain_height(global_position, map_n) + 0.06
						elif map_n.has_method("get_terrain_height_at_pos"):
							h_exp = map_n.get_terrain_height_at_pos(global_position) + 0.06
					elif map_n.has_method("get_terrain_height_at_pos"):
						h_exp = map_n.get_terrain_height_at_pos(global_position) + 0.06
					var s_f = map_n.scale_factor if "scale_factor" in map_n else 0.02
					var cz = map_n.correction_z if "correction_z" in map_n else 1.41421356
					shockwave.position = Vector3(global_position.x * s_f, h_exp, global_position.y * s_f * cz)
				else:
					shockwave.position = world_root_3d.position
					shockwave.position.y = 0.06
				vp.add_child(shockwave)
				var tw_sw = shockwave.create_tween()
				tw_sw.tween_property(shockwave, "scale", Vector3(2.5, 2.5, 2.5), 0.35)
				tw_sw.parallel().tween_property(sw_mat, "albedo_color:a", 0.0, 0.35)
				tw_sw.parallel().tween_property(sw_mat, "emission_energy_multiplier", 0.0, 0.35)
				tw_sw.finished.connect(shockwave.queue_free)

				var explight = OmniLight3D.new()
				explight.light_color = Color(0.3, 0.8, 1.0)
				explight.light_energy = 8.0
				explight.omni_range = 8.0
				explight.position = world_root_3d.position
				vp.add_child(explight)
				var tw_l = explight.create_tween()
				tw_l.tween_property(explight, "light_energy", 0.0, 0.3)
				tw_l.finished.connect(explight.queue_free)

		queue_free()
		return

	# Espectáculo celeste de impacto para shield_steal (el daño se resuelve en servidor)
	if type == "shield_steal":
		var sparks_impact = CPUParticles2D.new()
		sparks_impact.amount = 30
		sparks_impact.lifetime = 0.4
		sparks_impact.one_shot = true
		sparks_impact.explosiveness = 1.0
		sparks_impact.spread = 180.0
		sparks_impact.gravity = Vector2.ZERO
		sparks_impact.initial_velocity_min = 120.0
		sparks_impact.initial_velocity_max = 260.0
		sparks_impact.scale_amount_min = 2.0
		sparks_impact.scale_amount_max = 5.0

		var spark_grad = Gradient.new()
		spark_grad.set_color(0, Color(0.9, 1.0, 1.0, 0.95))
		spark_grad.add_point(0.3, Color(0.3, 0.85, 1.0, 0.85))
		spark_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		sparks_impact.color_ramp = spark_grad

		sparks_impact.global_position = global_position
		get_parent().add_child(sparks_impact)
		sparks_impact.emitting = true

		get_tree().create_timer(0.45).timeout.connect(sparks_impact.queue_free)

		var wave = Line2D.new()
		wave.width = 3.0
		wave.default_color = Color(0.4, 0.9, 1.0, 0.8)
		get_parent().add_child(wave)
		var pts = PackedVector2Array()
		var steps = 24
		for i in range(steps + 1):
			var a = (float(i) / steps) * TAU
			pts.append(Vector2(cos(a), sin(a)) * 34.0)
		wave.points = pts
		wave.global_position = global_position

		var tw = wave.create_tween()
		tw.tween_property(wave, "scale", Vector2(1.8, 1.8), 0.35)
		tw.parallel().tween_property(wave, "default_color:a", 0.0, 0.35)
		tw.finished.connect(wave.queue_free)

	# v412: Espectáculo verde de impacto para life_steal (el daño se resuelve en servidor)
	if type == "life_steal":
		var sparks_impact = CPUParticles2D.new()
		sparks_impact.amount = 30
		sparks_impact.lifetime = 0.4
		sparks_impact.one_shot = true
		sparks_impact.explosiveness = 1.0
		sparks_impact.spread = 180.0
		sparks_impact.gravity = Vector2.ZERO
		sparks_impact.initial_velocity_min = 120.0
		sparks_impact.initial_velocity_max = 260.0
		sparks_impact.scale_amount_min = 2.0
		sparks_impact.scale_amount_max = 5.0

		var spark_grad = Gradient.new()
		spark_grad.set_color(0, Color(0.8, 1.0, 0.8, 0.95))
		spark_grad.add_point(0.3, Color(0.2, 1.0, 0.35, 0.85))
		spark_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		sparks_impact.color_ramp = spark_grad

		sparks_impact.global_position = global_position
		get_parent().add_child(sparks_impact)
		sparks_impact.emitting = true

		get_tree().create_timer(0.45).timeout.connect(sparks_impact.queue_free)

		var wave = Line2D.new()
		wave.width = 3.0
		wave.default_color = Color(0.3, 1.0, 0.4, 0.8)
		get_parent().add_child(wave)
		var pts = PackedVector2Array()
		var steps = 24
		for i in range(steps + 1):
			var a = (float(i) / steps) * TAU
			pts.append(Vector2(cos(a), sin(a)) * 34.0)
		wave.points = pts
		wave.global_position = global_position

		var tw = wave.create_tween()
		tw.tween_property(wave, "scale", Vector2(1.8, 1.8), 0.35)
		tw.parallel().tween_property(wave, "default_color:a", 0.0, 0.35)
		tw.finished.connect(wave.queue_free)

	# v410: Efecto de impacto para Polimorfia (explosión de cubitos)
	if type == "polymorph":
		var cubits = CPUParticles2D.new()
		cubits.amount = 20
		cubits.lifetime = 0.5
		cubits.one_shot = true
		cubits.explosiveness = 1.0
		cubits.spread = 180.0
		cubits.gravity = Vector2.ZERO
		cubits.initial_velocity_min = 100.0
		cubits.initial_velocity_max = 240.0
		cubits.scale_amount_min = 2.0
		cubits.scale_amount_max = 4.0

		var cube_grad = Gradient.new()
		cube_grad.set_color(0, Color(0.9, 1.0, 1.0, 0.9))
		cube_grad.add_point(0.3, Color(0.2, 0.8, 1.0, 0.8))
		cube_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		cubits.color_ramp = cube_grad

		cubits.global_position = global_position
		get_parent().add_child(cubits)
		cubits.emitting = true
		get_tree().create_timer(0.5).timeout.connect(cubits.queue_free)

		# Anillo de transformación
		var poly_ring = Line2D.new()
		poly_ring.width = 3.0
		poly_ring.default_color = Color(0.2, 0.8, 1.0, 0.9)
		get_parent().add_child(poly_ring)
		var ring_pts = PackedVector2Array()
		var ring_steps = 24
		for i in range(ring_steps + 1):
			var a = (float(i) / ring_steps) * TAU
			ring_pts.append(Vector2(cos(a), sin(a)) * 40.0)
		poly_ring.points = ring_pts
		poly_ring.global_position = global_position

		var tw_ring = poly_ring.create_tween()
		tw_ring.tween_property(poly_ring, "scale", Vector2(2.0, 2.0), 0.4)
		tw_ring.parallel().tween_property(poly_ring, "default_color:a", 0.0, 0.4)
		tw_ring.finished.connect(poly_ring.queue_free)
		
		# 3D impact effect en el viewport
		if is_instance_valid(world_root_3d):
			var vp = get_tree().get_first_node_in_group("map")
			if is_instance_valid(vp) and vp.get("sub_viewport") != null:
				var impact_3d = MeshInstance3D.new()
				var impact_box = BoxMesh.new()
				impact_box.size = Vector3(0.5, 0.5, 0.5)
				impact_3d.mesh = impact_box
				var impact_mat = StandardMaterial3D.new()
				impact_mat.albedo_color = Color(0.3, 0.9, 1.0, 0.8)
				impact_mat.emission_enabled = true
				impact_mat.emission = Color(0.3, 0.9, 1.0)
				impact_mat.emission_energy_multiplier = 4.0
				impact_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				impact_3d.material_override = impact_mat
				impact_3d.position = world_root_3d.position
				vp.sub_viewport.add_child(impact_3d)
				
				var tw_3d = impact_3d.create_tween()
				tw_3d.tween_property(impact_3d, "scale", Vector3(2.0, 2.0, 2.0), 0.4)
				tw_3d.parallel().tween_property(impact_mat, "albedo_color:a", 0.0, 0.4)
				tw_3d.finished.connect(impact_3d.queue_free)

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
				var hit_node = VFXSystem.get_vfx_from_pool(VFX_Hit_cyber_scene)
				hit_node.name = "HealHit3D_" + str(get_instance_id())
				target_vp.add_child(hit_node)
				
				# Posicionarlo en el lugar exacto del impacto a altura de la nave (0.0)
				var s_factor = 0.02
				var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
				hit_node.position.x = global_position.x * s_factor
				hit_node.position.z = global_position.y * s_factor * correction_z
				hit_node.position.y = _aim_height()
				hit_node.scale = Vector3(1.5, 1.5, 1.5)
				
				# Auto-liberar al terminar la animación
				var anim = hit_node.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(func(_a): VFXSystem.recycle_vfx_to_pool(hit_node), CONNECT_ONE_SHOT)
				else:
					var tw = hit_node.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(func(): VFXSystem.recycle_vfx_to_pool(hit_node))

	# Spawn 3D hit impact effect for emp (hadouken) projectiles
	if type == "emp":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Hit_hadouken_scene:
				var hit_node = VFXSystem.get_vfx_from_pool(VFX_Hit_hadouken_scene)
				hit_node.name = "HadoukenHit3D_" + str(get_instance_id())
				target_vp.add_child(hit_node)
				
				# Posicionarlo en el lugar exacto del impacto a altura de la nave (0.0)
				var s_factor = 0.02
				var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
				hit_node.position.x = global_position.x * s_factor
				hit_node.position.z = global_position.y * s_factor * correction_z
				hit_node.position.y = _aim_height()
				hit_node.scale = Vector3(1.5, 1.5, 1.5)
				
				# Auto-liberar al terminar la animación
				var anim = hit_node.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(func(_a): VFXSystem.recycle_vfx_to_pool(hit_node), CONNECT_ONE_SHOT)
				else:
					var tw = hit_node.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(func(): VFXSystem.recycle_vfx_to_pool(hit_node))

	# Spawn 3D hit impact effect for execution skulls (huesos/dust púrpura)
	if type == "execution":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			var s_factor = 0.02
			var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
			var impact_pos3d = Vector3(global_position.x * s_factor, 0.2, global_position.y * s_factor * correction_z)

			var puff = CPUParticles3D.new()
			puff.one_shot = true
			puff.lifetime = 0.7
			puff.preprocess = 0.0
			puff.amount = 26
			puff.speed_scale = 1.2
			puff.explosiveness = 0.9
			puff.lifetime_randomness = 0.4
			puff.direction = Vector3.UP
			puff.spread = 140.0
			puff.gravity = Vector3.DOWN * 9.0
			puff.initial_velocity_min = 4.0
			puff.initial_velocity_max = 11.0
			puff.scale_amount_min = 0.05
			puff.scale_amount_max = 0.13
			var g = Gradient.new()
			g.set_color(0, Color(0.8, 0.7, 0.95, 0.9))
			g.add_point(0.45, Color(0.5, 0.4, 0.75, 0.55))
			g.set_color(1, Color(0.1, 0.05, 0.2, 0.0))
			puff.color_ramp = g
			var dm = SphereMesh.new()
			dm.radius = 0.06
			puff.mesh = dm
			puff.position = impact_pos3d
			target_vp.add_child(puff)
			puff.emitting = true
			target_vp.create_tween().tween_callback(puff.queue_free).set_delay(0.8)

			if VFXSystem and VFXSystem.spawn_explosion:
				VFXSystem.spawn_explosion(Vector2(global_position.x, global_position.y), 0.5)

	# Spawn 3D hit impact effect for laser projectiles
	if type == "laser":
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			if VFX_Laser_Hit_scene:
				var hit_node = VFXSystem.get_vfx_from_pool(VFX_Laser_Hit_scene)
				hit_node.name = "LaserHit3D_" + str(get_instance_id())
				target_vp.add_child(hit_node)
				
				var s_factor = 0.02
				var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
				hit_node.position.x = global_position.x * s_factor
				hit_node.position.z = global_position.y * s_factor * correction_z
				hit_node.position.y = _aim_height()
				hit_node.scale = Vector3(1.5, 1.5, 1.5)
				
				var anim = hit_node.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
					anim.animation_finished.connect(func(_a): VFXSystem.recycle_vfx_to_pool(hit_node), CONNECT_ONE_SHOT)
				else:
					var tw = hit_node.create_tween()
					tw.tween_interval(1.0)
					tw.tween_callback(func(): VFXSystem.recycle_vfx_to_pool(hit_node))

	# Spawn 3D hit impact effect for siphon projectiles
	if type == "siphon":
		print("[SIPHON HIT] Spawning 3D hit effect")
		var map_node = get_tree().get_first_node_in_group("map")
		print("[SIPHON HIT] map_node = ", map_node)
		if is_instance_valid(map_node):
			print("[SIPHON HIT] map_node.sub_viewport = ", map_node.get("sub_viewport"))
		if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
			var target_vp = map_node.sub_viewport
			print("[SIPHON HIT] VFX_Siphon_Hit_scene = ", VFX_Siphon_Hit_scene)
			if VFX_Siphon_Hit_scene:
				var hit_node = VFXSystem.get_vfx_from_pool(VFX_Siphon_Hit_scene)
				print("[SIPHON HIT] hit_node = ", hit_node)
				if is_instance_valid(hit_node):
					hit_node.name = "SiphonHit3D_" + str(get_instance_id())
					target_vp.add_child(hit_node)
					
					var s_factor = 0.02
					var correction_z = map_node.correction_z if is_instance_valid(map_node) and "correction_z" in map_node else 1.41421356
					hit_node.position.x = global_position.x * s_factor
					hit_node.position.z = global_position.y * s_factor * correction_z
					hit_node.position.y = _aim_height()
					hit_node.scale = Vector3(1.5, 1.5, 1.5)
					
					var anim = hit_node.get_node_or_null("AnimationPlayer")
					if anim:
						anim.play("Init")
						anim.animation_finished.connect(func(_a): VFXSystem.recycle_vfx_to_pool(hit_node), CONNECT_ONE_SHOT)
					else:
						var tw = hit_node.create_tween()
						tw.tween_interval(1.0)
						tw.tween_callback(func(): VFXSystem.recycle_vfx_to_pool(hit_node))
				else:
					print("[SIPHON HIT ERROR] Failed to get VFX from pool!")
			else:
				print("[SIPHON HIT ERROR] VFX_Siphon_Hit_scene is empty!")
		else:
			print("[SIPHON HIT DEBUG] No map node or sub_viewport")

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

# v411: Altura 3D a la que debe volar el proyectil.
# Se usa la altura del objetivo (jugador/enemigo común) en lugar de la del dueño,
# para que los bosses (escala mayor) no parezcan disparar al aire.
func _aim_height() -> float:
	if is_instance_valid(_target_node) and is_instance_valid(_target_node.get("world_root_3d")):
		return _target_node.world_root_3d.position.y
	var pl = get_tree().get_first_node_in_group("player")
	if is_instance_valid(pl) and is_instance_valid(pl.get("world_root_3d")):
		return pl.world_root_3d.position.y
	if is_instance_valid(_owner_node) and is_instance_valid(_owner_node.get("world_root_3d")):
		return _owner_node.world_root_3d.position.y
	return 1.0

func _find_target():
	if target_id == "": return
	
	if NetworkManager and target_id == str(NetworkManager.my_socket_id):
		_target_node = get_tree().get_first_node_in_group("player")
		if is_instance_valid(_target_node): return

	var _world_ref = get_tree().get_first_node_in_group("world_node")
	if is_instance_valid(_world_ref):
		if _world_ref.get("remote_players") != null and _world_ref.remote_players.has(target_id):
			_target_node = _world_ref.remote_players.get(target_id)
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
