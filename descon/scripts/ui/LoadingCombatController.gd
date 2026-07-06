extends Node3D

# LoadingCombatController.gd
# Maneja la simulación cinemática 3D de combate espacial durante la carga y el login.
# Utiliza los efectos visuales 3D (VFX) oficiales del juego para coherencia estética.

var ship1: Node3D
var ship2: Node3D
var camera: Camera3D

# Planetas 3D de fondo para dar profundidad
var planet1: Node3D
var planet2: Node3D
var planet3: Node3D

var time_passed: float = 0.0
var shoot_cooldown1: float = 0.5
var shoot_cooldown2: float = 1.1

class ActiveProjectile extends RefCounted:
	var node: Node3D
	var start_pos: Vector3
	var target_ship: Node3D
	var progress: float = 0.0
	var duration: float = 1.2
	var is_emp: bool = false
	var color: Color
	var light: OmniLight3D

var active_projectiles: Array[ActiveProjectile] = []

func _ready():
	# Inicializar tiempos de disparo de manera semi-aleatoria para que no salgan al unísono
	shoot_cooldown1 = randf_range(0.2, 0.8)
	shoot_cooldown2 = randf_range(0.6, 1.2)
	print("[LoadingCombat] Controlador de Combate 3D con planetas de fondo inicializado.")

func _process(delta: float):
	time_passed += delta
	
	# 1. Movimiento de las naves en órbita elíptica enfrentada
	_animate_ships(delta)
	
	# 2. Control orbital suave de la cámara
	_animate_camera(delta)
	
	# 3. Rotación lenta de los planetas de fondo
	_animate_planets(delta)
	
	# 4. Temporizadores de disparo
	_handle_shooting(delta)
	
	# 5. Actualizar proyectiles activos
	_update_projectiles(delta)

func _animate_ships(delta: float):
	if not is_instance_valid(ship1) or not is_instance_valid(ship2):
		return
		
	var speed_multiplier = 0.35
	
	# Nave 11 (ship1)
	var x1 = sin(time_passed * speed_multiplier) * 4.2
	var z1 = cos(time_passed * speed_multiplier) * 2.2
	var y1 = sin(time_passed * 1.5) * 0.15 - 0.2
	ship1.position = Vector3(x1, y1, z1)
	
	# Nave 12 (ship2) - Desfasada por PI
	var x2 = sin(time_passed * speed_multiplier + PI) * 4.2
	var z2 = cos(time_passed * speed_multiplier + PI) * 2.2
	var y2 = sin(time_passed * 1.5 + PI) * 0.15 + 0.2
	ship2.position = Vector3(x2, y2, z2)
	
	# Rotación suavizada combinando el look_at, desfase del modelo (+X de frente) y ladeo (Roll)
	var t1 = ship1.transform.looking_at(ship2.position, Vector3.UP)
	t1 = t1.rotated_local(Vector3.UP, deg_to_rad(90)) # Alinear frente visual de la Nave 11 (+X)
	var roll_angle1 = -cos(time_passed * speed_multiplier) * 0.25
	t1 = t1.rotated_local(Vector3.RIGHT, roll_angle1) # Roll longitudinal sobre el nuevo eje visual
	ship1.transform = ship1.transform.interpolate_with(t1, delta * 3.5)
	
	var t2 = ship2.transform.looking_at(ship1.position, Vector3.UP)
	t2 = t2.rotated_local(Vector3.UP, deg_to_rad(90)) # Alinear frente visual de la Nave 12 (+X)
	var roll_angle2 = -cos(time_passed * speed_multiplier + PI) * 0.25
	t2 = t2.rotated_local(Vector3.RIGHT, roll_angle2) # Roll longitudinal sobre el nuevo eje visual
	ship2.transform = ship2.transform.interpolate_with(t2, delta * 3.5)

func _animate_camera(delta: float):
	if not is_instance_valid(camera):
		return
		
	# Órbita circular lenta de la cámara
	var cam_speed = 0.08
	var cam_x = sin(time_passed * cam_speed) * 8.5
	var cam_z = cos(time_passed * cam_speed) * 8.5
	var cam_y = 1.2 + sin(time_passed * 0.12) * 0.6
	
	camera.position = Vector3(cam_x, cam_y, cam_z)
	
	# La cámara apunta al punto medio entre las dos naves con un ligero retraso suave
	var target_look = Vector3.ZERO
	if is_instance_valid(ship1) and is_instance_valid(ship2):
		target_look = (ship1.position + ship2.position) * 0.5
		
	# Mirar al objetivo suavemente
	var current_trans = camera.global_transform
	var target_trans = camera.global_transform.looking_at(target_look, Vector3.UP)
	camera.global_transform = current_trans.interpolate_with(target_trans, delta * 2.0)

func _animate_planets(delta: float):
	# Rotación lenta sobre el eje Y local de los planetas 3D de fondo
	if is_instance_valid(planet1):
		planet1.rotate_y(delta * 0.04)
	if is_instance_valid(planet2):
		planet2.rotate_y(delta * -0.035)
	if is_instance_valid(planet3):
		planet3.rotate_y(delta * 0.02)

func _handle_shooting(delta: float):
	if not is_instance_valid(ship1) or not is_instance_valid(ship2):
		return
		
	shoot_cooldown1 -= delta
	if shoot_cooldown1 <= 0.0:
		shoot_cooldown1 = randf_range(1.2, 1.8)
		_spawn_laser_projectile(ship1, ship2, Color(0.2, 1.0, 0.4), false)
		
	shoot_cooldown2 -= delta
	if shoot_cooldown2 <= 0.0:
		shoot_cooldown2 = randf_range(1.4, 2.0)
		_spawn_laser_projectile(ship2, ship1, Color(0.1, 0.6, 1.0), true)

func _spawn_laser_projectile(from_ship: Node3D, to_ship: Node3D, col: Color, is_emp: bool):
	# Calcular la posición de salida de frente en la dirección hacia la nave enemiga
	var forward_dir = (to_ship.global_position - from_ship.global_position).normalized()
	var start_pos = from_ship.global_position + forward_dir * 1.3
	
	# 1. FASE DE COMENZAR: Fogonazo de anticipación usando la escena oficial
	var antic_path = "res://VFX/scenes/VFX_Anticipation_hadouken.tscn" if is_emp else "res://VFX/scenes/VFX_Anticipation_wave_digital.tscn"
	if ResourceLoader.exists(antic_path):
		var antic_scene = load(antic_path)
		if antic_scene:
			var antic_inst = antic_scene.instantiate()
			if antic_inst is Node3D:
				add_child(antic_inst)
				antic_inst.position = start_pos
				antic_inst.scale = Vector3(0.8, 0.8, 0.8)
				antic_inst.look_at(to_ship.position, Vector3.UP)
				
				# Reproducir animación inicial si posee AnimationPlayer
				var anim = antic_inst.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
				
				# Auto-liberar tras un tiempo prudencial
				var tw_antic = create_tween()
				tw_antic.tween_interval(1.2)
				tw_antic.tween_callback(antic_inst.queue_free)
				
	# 2. Instanciar escena de proyectil oficial (Hadouken para EMP, Cube para Curación)
	var proj_path = "res://VFX/scenes/VFX_Hadouken.tscn" if is_emp else "res://VFX/scenes/VFX_Cube_projectile.tscn"
	var proj_node: Node3D = null
	if ResourceLoader.exists(proj_path):
		var proj_scene = load(proj_path)
		if proj_scene:
			proj_node = proj_scene.instantiate()
			
	# Failsafe en caso de que no exista el archivo
	if not proj_node:
		proj_node = Node3D.new()
		var m = MeshInstance3D.new()
		m.mesh = SphereMesh.new()
		m.mesh.radius = 0.15; m.mesh.height = 0.3
		proj_node.add_child(m)
		
	proj_node.position = start_pos
	add_child(proj_node)
	
	# Rotar el proyectil 3D para que mire hacia su objetivo en viaje
	proj_node.look_at(to_ship.position, Vector3.UP)
	proj_node.scale = Vector3(1.2, 1.2, 1.2) if is_emp else Vector3(1.0, 1.0, 1.0)
	
	# Luz integrada adicional para iluminar naves al pasar
	var light = OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.6
	light.omni_range = 4.5
	proj_node.add_child(light)
	
	# Guardar en estructura de proyectiles activos
	var ap = ActiveProjectile.new()
	ap.node = proj_node
	ap.start_pos = start_pos
	ap.target_ship = to_ship
	ap.is_emp = is_emp
	ap.color = col
	ap.light = light
	ap.duration = randf_range(0.9, 1.2)
	
	active_projectiles.append(ap)

func _update_projectiles(delta: float):
	var to_remove: Array[ActiveProjectile] = []
	
	for ap in active_projectiles:
		if not is_instance_valid(ap.node) or not is_instance_valid(ap.target_ship):
			to_remove.append(ap)
			continue
			
		ap.progress += delta * (1.0 / ap.duration)
		var current_target_pos = ap.target_ship.position
		
		# FASE DE VIAJE: Desplazamiento del proyectil oficial
		var new_pos = ap.start_pos.lerp(current_target_pos, ap.progress)
		ap.node.position = new_pos
		
		# Asegurar que siga orientado hacia el objetivo durante el viaje
		if ap.progress < 0.95:
			ap.node.look_at(current_target_pos, Vector3.UP)
				
		if ap.progress >= 1.0:
			# El proyectil ha impactado en el blanco
			_trigger_impact_effect(ap.target_ship, ap.color, ap.is_emp)
			
			# Limpieza de recursos
			ap.node.queue_free()
			to_remove.append(ap)
			
	# Remover proyectiles terminados
	for ap in to_remove:
		active_projectiles.erase(ap)

func _trigger_impact_effect(ship: Node3D, col: Color, is_emp: bool):
	if not is_instance_valid(ship):
		return
		
	var impact_pos = ship.position
	
	# 3. FASE DE IMPACTO:
	# A) Instanciar efecto de Hit oficial (VFX_Hit_hadouken para EMP, VFX_Hit_cyber para Curación)
	var hit_path = "res://VFX/scenes/VFX_Hit_hadouken.tscn" if is_emp else "res://VFX/scenes/VFX_Hit_cyber.tscn"
	if ResourceLoader.exists(hit_path):
		var hit_scene = load(hit_path)
		if hit_scene:
			var hit_inst = hit_scene.instantiate()
			if hit_inst is Node3D:
				add_child(hit_inst)
				hit_inst.position = impact_pos
				hit_inst.scale = Vector3(1.2, 1.2, 1.2)
				
				# Auto-liberar
				var tw_hit = create_tween()
				tw_hit.tween_interval(1.5)
				tw_hit.tween_callback(hit_inst.queue_free)
				
	# B) Crear Escudo Deflector Reactivo
	var shield = MeshInstance3D.new()
	shield.mesh = SphereMesh.new()
	shield.mesh.radius = 1.15
	shield.mesh.height = 2.3
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.0)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield.material_override = mat
	ship.add_child(shield)
	shield.position = Vector3.ZERO
	
	# Tween del Escudo (SINE/EASE_OUT)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.5, 0.05)
	tw.tween_property(shield, "scale", Vector3(1.25, 1.25, 1.25), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	var tw_fade = create_tween()
	tw_fade.tween_interval(0.1)
	tw_fade.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw_fade.tween_callback(shield.queue_free)
	
	# C) Partículas extras de impacto (Chispas)
	_spawn_spark_particles(impact_pos, col, is_emp)

func _spawn_spark_particles(pos: Vector3, col: Color, is_emp: bool):
	var spark_count = 12 if is_emp else 6
	var particle_lifetime = 0.45
	
	for i in range(spark_count):
		var p = MeshInstance3D.new()
		p.mesh = SphereMesh.new()
		var size = randf_range(0.03, 0.06)
		p.mesh.radius = size
		p.mesh.height = size * 2
		
		var p_mat = StandardMaterial3D.new()
		p_mat.albedo_color = Color.WHITE
		p_mat.emission_enabled = true
		p_mat.emission = col
		p_mat.emission_energy_multiplier = 5.0
		p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p.material_override = p_mat
		
		add_child(p)
		p.position = pos
		
		var dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		var speed = randf_range(1.5, 3.2)
		var dest = pos + dir * (speed * particle_lifetime)
		
		var tw_p = create_tween().set_parallel(true)
		tw_p.tween_property(p, "position", dest, particle_lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_p.tween_property(p, "scale", Vector3.ZERO, particle_lifetime).set_trans(Tween.TRANS_LINEAR)
		tw_p.chain().tween_callback(p.queue_free)
