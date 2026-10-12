extends Node3D
class_name AmbientBirdsFlock

## VFX de Palomas y Aves Pequeñas 3D Ambientales
## Vuelan en bandada cruzando el entorno con volumen 3D,
## alternando aleteo alegre y planeo suave con sombras proyectadas en el suelo.

const SHADER_BIRD = preload("res://resources/shaders/ambient_bird.gdshader")
const SHADER_SHADOW = preload("res://resources/shaders/ambient_bird_shadow.gdshader")

@export_group("Configuración de Bandada")
@export var bird_count: int = 5                  # Cantidad de palomas por bandada (pequeña y armónica)
@export var fly_height: float = 8.5              # Altura de vuelo en Y sobre el mapa
@export var fly_speed: float = 11.0              # Velocidad de crucero 3D
@export var flock_spread: float = 2.8            # Dispersión espacial entre palomas
@export var height_variation: float = 0.8        # Ondulación vertical suave al volar
@export var turn_smoothness: float = 0.35        # Curvatura y giros en el aire

@export_group("Intervalos y Pasadas Esporádicas")
@export var min_pass_interval: float = 12.0      # Tiempo mínimo de espera entre pasadas (segundos)
@export var max_pass_interval: float = 22.0      # Tiempo máximo de espera entre pasadas (segundos)
@export var pass_duration: float = 4.5           # Duración en vuelo de cada pasada cruzando el entorno
@export var spawn_distance_3d: float = 24.0      # Distancia de inicio y fin respecto al jugador

enum State {
	WAITING,
	FADING_IN,
	FLYING,
	FADING_OUT
}

class BirdInstance:
	var mesh_inst: MeshInstance3D
	var shadow_inst: MeshInstance3D
	var mat_bird: ShaderMaterial
	var mat_shadow: ShaderMaterial
	var local_pos: Vector3
	var offset_flock: Vector3
	var flap_timer: float
	var glide_timer: float
	var is_gliding: bool
	var personal_phase: float
	var bank_angle: float

var birds: Array[BirdInstance] = []
var _shared_pigeon_mesh: ArrayMesh = null
var _shared_shadow_mesh: PlaneMesh = null

var flock_center_3d: Vector3 = Vector3.ZERO
var flight_direction: Vector3 = Vector3.FORWARD
var target_direction: Vector3 = Vector3.FORWARD
var turn_timer: float = 0.0
var time_alive: float = 0.0

var current_state: State = State.WAITING
var state_timer: float = 0.0
var current_fade: float = 0.0

var _scale_factor_cached: float = 0.02
var _correction_z_cached: float = 1.4142

func _ready() -> void:
	_read_map_scale_factors()
	flock_center_3d = global_position
	if flock_center_3d.y < fly_height:
		flock_center_3d.y = fly_height
	
	_shared_pigeon_mesh = _build_3d_pigeon_mesh()
	_shared_shadow_mesh = PlaneMesh.new()
	_shared_shadow_mesh.size = Vector2(1.2, 1.2) # Sombra chiquita proporcional a paloma
	
	_create_birds()
	
	# Iniciar en espera breve para arrancar de inmediato tras entrar al mapa
	_set_birds_visible(false)
	_set_fade_alpha(0.0)
	current_state = State.WAITING
	state_timer = 1.5 # Primera pasada a los 1.5s de entrar al mapa

## Construye un modelo 3D con volumen de paloma usando SurfaceTool para normales e iluminación suaves
static func _build_3d_pigeon_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Coordenadas anatómicas de la paloma pequeña en 3D (en metros)
	var BEAK       = Vector3(0.0, 0.03, -0.34)       # Punta del pico
	var HEAD_TOP   = Vector3(0.0, 0.08, -0.25)       # Cabeza arriba
	var HEAD_BOT   = Vector3(0.0, 0.00, -0.25)       # Garganta
	var HEAD_L     = Vector3(-0.035, 0.045, -0.25)   # Sien izquierda
	var HEAD_R     = Vector3(0.035, 0.045, -0.25)    # Sien derecha

	var BREAST     = Vector3(0.0, -0.045, -0.11)     # Pecho inflado de paloma
	var BACK       = Vector3(0.0, 0.075, -0.06)      # Lomo
	var BODY_L     = Vector3(-0.065, 0.02, -0.06)    # Costado izq
	var BODY_R     = Vector3(0.065, 0.02, -0.06)     # Costado der
	var BELLY      = Vector3(0.0, -0.03, 0.08)       # Vientre
	var RUMP       = Vector3(0.0, 0.04, 0.16)        # Base de cola
	
	var TAIL_TIP   = Vector3(0.0, 0.025, 0.30)       # Cola centro
	var TAIL_L     = Vector3(-0.055, 0.025, 0.28)    # Cola izquierda
	var TAIL_R     = Vector3(0.055, 0.025, 0.28)     # Cola derecha

	# Alas articuladas con volumen
	var SH_L       = Vector3(-0.06, 0.05, -0.07)     # Hombro izq
	var SH_R       = Vector3(0.06, 0.05, -0.07)      # Hombro der
	var MID_FL     = Vector3(-0.21, 0.055, -0.05)    # Codo frontal izq
	var MID_FR     = Vector3(0.21, 0.055, -0.05)     # Codo frontal der
	var MID_BL     = Vector3(-0.18, 0.045, 0.06)     # Codo trasero izq
	var MID_BR     = Vector3(0.18, 0.045, 0.06)      # Codo trasero der
	var TIP_L      = Vector3(-0.46, 0.055, 0.01)     # Punta ala izq
	var TIP_R      = Vector3(0.46, 0.055, 0.01)      # Punta ala der
	var TIP_BL     = Vector3(-0.36, 0.045, 0.10)     # Borde plumas izq
	var TIP_BR     = Vector3(0.36, 0.045, 0.10)      # Borde plumas der

	# Helper para agregar triángulos
	var add_tri = func(a: Vector3, b: Vector3, c: Vector3):
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)

	# 1. Pico (pirámide 3D hacia adelante)
	add_tri.call(BEAK, HEAD_TOP, HEAD_L)
	add_tri.call(BEAK, HEAD_R, HEAD_TOP)
	add_tri.call(BEAK, HEAD_BOT, HEAD_R)
	add_tri.call(BEAK, HEAD_L, HEAD_BOT)

	# 2. Cabeza conectando al pecho y lomo
	add_tri.call(HEAD_TOP, BACK, BODY_L)
	add_tri.call(HEAD_TOP, BODY_R, BACK)
	add_tri.call(HEAD_TOP, BODY_L, HEAD_L)
	add_tri.call(HEAD_TOP, HEAD_R, BODY_R)
	add_tri.call(HEAD_BOT, BODY_L, BREAST)
	add_tri.call(HEAD_BOT, BREAST, BODY_R)
	add_tri.call(HEAD_BOT, HEAD_L, BODY_L)
	add_tri.call(HEAD_BOT, BODY_R, HEAD_R)

	# 3. Tronco tridimensional de la paloma (pecho, vientre y lomo)
	add_tri.call(BREAST, BODY_L, BELLY)
	add_tri.call(BREAST, BELLY, BODY_R)
	add_tri.call(BACK, RUMP, BODY_L)
	add_tri.call(BACK, BODY_R, RUMP)
	add_tri.call(BODY_L, RUMP, BELLY)
	add_tri.call(BODY_R, BELLY, RUMP)

	# 4. Cola en abanico (plana y abierta)
	add_tri.call(RUMP, TAIL_L, TAIL_TIP)
	add_tri.call(RUMP, TAIL_TIP, TAIL_R)
	add_tri.call(BELLY, TAIL_TIP, TAIL_L)
	add_tri.call(BELLY, TAIL_R, TAIL_TIP)

	# 5. Ala Izquierda (sección media + sección exterior curvada)
	add_tri.call(SH_L, MID_FL, MID_BL)
	add_tri.call(BODY_L, SH_L, MID_BL)
	add_tri.call(MID_FL, TIP_L, MID_BL)
	add_tri.call(MID_BL, TIP_L, TIP_BL)

	# 6. Ala Derecha
	add_tri.call(SH_R, MID_BR, MID_FR)
	add_tri.call(BODY_R, MID_BR, SH_R)
	add_tri.call(MID_FR, MID_BR, TIP_R)
	add_tri.call(MID_BR, TIP_BR, TIP_R)

	st.generate_normals()
	return st.commit()

func _create_birds() -> void:
	for i in range(bird_count):
		var b = BirdInstance.new()
		
		# Material individual con ligeras variaciones de tono blanco/gris
		b.mat_bird = ShaderMaterial.new()
		b.mat_bird.shader = SHADER_BIRD
		var tint_var = randf_range(-0.03, 0.03)
		var body_col = Color(0.92 + tint_var, 0.94 + tint_var, 0.96 + tint_var)
		b.mat_bird.set_shader_parameter("body_color", body_col)
		b.mat_bird.set_shader_parameter("wing_tip_color", Color(0.42, 0.46, 0.54))
		b.mat_bird.set_shader_parameter("flap_speed", 18.0 + randf_range(-1.5, 2.5))
		b.mat_bird.set_shader_parameter("flap_amplitude", 0.55)
		b.mat_bird.set_shader_parameter("flap_strength", 1.0)
		b.mat_bird.set_shader_parameter("fade_alpha", 1.0)

		b.mesh_inst = MeshInstance3D.new()
		b.mesh_inst.mesh = _shared_pigeon_mesh
		b.mesh_inst.material_override = b.mat_bird
		b.mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b.mesh_inst)

		# Material de sombra
		b.mat_shadow = ShaderMaterial.new()
		b.mat_shadow.shader = SHADER_SHADOW
		b.mat_shadow.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, 0.28))
		b.mat_shadow.set_shader_parameter("fade_alpha", 1.0)

		b.shadow_inst = MeshInstance3D.new()
		b.shadow_inst.mesh = _shared_shadow_mesh
		b.shadow_inst.material_override = b.mat_shadow
		b.shadow_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b.shadow_inst)

		# Formación orgánica de palomas
		var row: float = float(i) / 2.0
		var side: float = -1.0 if (i % 2 == 1) else 1.0
		if i == 0:
			b.offset_flock = Vector3.ZERO
		else:
			b.offset_flock = Vector3(
				side * (row * 0.9 + randf_range(-0.25, 0.25)),
				randf_range(-0.35, 0.35),
				row * 1.1 + randf_range(-0.2, 0.3)
			)

		b.local_pos = b.offset_flock
		b.personal_phase = randf_range(0.0, TAU)
		b.flap_timer = randf_range(1.2, 2.8)   # Aletean 1.5 a 2.5 seg
		b.glide_timer = randf_range(1.0, 2.2)  # Planean 1 a 2 seg
		b.is_gliding = false
		b.bank_angle = 0.0
		birds.append(b)

func _process(delta: float) -> void:
	match current_state:
		State.WAITING:
			state_timer -= delta
			if state_timer <= 0.0:
				var p_node = get_tree().get_first_node_in_group("player") if get_tree() else null
				if is_instance_valid(p_node):
					_start_flight_pass()
				else:
					state_timer = 2.0

		State.FADING_IN:
			time_alive += delta
			state_timer -= delta
			current_fade = clamp(1.0 - (state_timer / 0.8), 0.0, 1.0)
			_set_fade_alpha(current_fade)
			_update_flock_navigation(delta)
			_update_individual_birds(delta)
			if state_timer <= 0.0:
				current_state = State.FLYING
				state_timer = pass_duration
				current_fade = 1.0
				_set_fade_alpha(1.0)

		State.FLYING:
			time_alive += delta
			state_timer -= delta
			_update_flock_navigation(delta)
			_update_individual_birds(delta)
			if state_timer <= 0.0:
				current_state = State.FADING_OUT
				state_timer = 1.0

		State.FADING_OUT:
			time_alive += delta
			state_timer -= delta
			current_fade = clamp(state_timer / 1.0, 0.0, 1.0)
			_set_fade_alpha(current_fade)
			_update_flock_navigation(delta)
			_update_individual_birds(delta)
			if state_timer <= 0.0:
				_set_birds_visible(false)
				_set_fade_alpha(0.0)
				current_state = State.WAITING
				state_timer = randf_range(min_pass_interval, max_pass_interval)

## Inicia una nueva pasada de la bandada cruzando el cielo sobre la nave del jugador
func _start_flight_pass() -> void:
	var focal = _get_focal_point_3d()

	# Ángulo aleatorio de entrada
	var in_angle = randf_range(0.0, TAU)
	var start_pos = focal + Vector3(cos(in_angle), 0.0, sin(in_angle)) * spawn_distance_3d
	start_pos.y = focal.y + fly_height + randf_range(-0.3, 0.3)

	# Ángulo opuesto para atravesar directo sobre la nave del jugador
	var out_angle = in_angle + PI + randf_range(-0.25, 0.25)
	var exit_pos = focal + Vector3(cos(out_angle), 0.0, sin(out_angle)) * spawn_distance_3d
	exit_pos.y = start_pos.y

	flight_direction = (exit_pos - start_pos).normalized()
	target_direction = flight_direction
	flock_center_3d = start_pos
	turn_timer = randf_range(3.0, 5.0)

	var flock_yaw = atan2(flight_direction.x, flight_direction.z) + PI

	for b in birds:
		b.local_pos = flock_center_3d + b.offset_flock.rotated(Vector3.UP, flock_yaw - PI)
		b.mesh_inst.global_position = b.local_pos
		b.mesh_inst.rotation.y = flock_yaw
		b.mesh_inst.rotation.z = 0.0
		b.bank_angle = 0.0
		b.is_gliding = false
		b.flap_timer = randf_range(1.4, 2.5)
		b.glide_timer = randf_range(1.0, 2.0)
		b.shadow_inst.global_position = Vector3(b.local_pos.x, focal.y + 0.03, b.local_pos.z)

	_set_birds_visible(true)
	_set_fade_alpha(0.0)
	current_fade = 0.0
	current_state = State.FADING_IN
	state_timer = 0.8

## Navegación del centro de la bandada por el cielo
func _update_flock_navigation(delta: float) -> void:
	turn_timer -= delta
	if turn_timer <= 0.0:
		turn_timer = randf_range(3.0, 6.0)
		# Variación sutil del rumbo durante la pasada
		var angle_offset = randf_range(-0.20, 0.20)
		var current_yaw = atan2(flight_direction.x, flight_direction.z)
		var new_yaw = current_yaw + angle_offset
		target_direction = Vector3(sin(new_yaw), 0.0, cos(new_yaw)).normalized()

	# Interpolar dirección suavemente
	flight_direction = flight_direction.slerp(target_direction, delta * turn_smoothness).normalized()

	# Ondulación vertical suave (suben y bajan sutilmente)
	var focal = _get_focal_point_3d()
	var target_y = focal.y + fly_height + sin(time_alive * 0.5) * height_variation
	flock_center_3d.y = lerp(flock_center_3d.y, target_y, delta * 1.5)

	# Desplazamiento en el espacio 3D
	flock_center_3d += flight_direction * fly_speed * delta

## Actualiza cada paloma: aleteo/planeo individual, rotación e inclinación en giros
func _update_individual_birds(delta: float) -> void:
	# Cálculo del ángulo de alabeo (bank) según el giro de la bandada
	var turn_rate = flight_direction.cross(target_direction).y
	var target_flock_bank = clamp(-turn_rate * 4.5, -0.45, 0.45)

	var flock_yaw = atan2(flight_direction.x, flight_direction.z) + PI
	var focal = _get_focal_point_3d()

	# Si la nave se teletransportó lejos (> 60m) durante el vuelo, abortar pasada limpiamente
	if flock_center_3d.distance_to(focal) > 60.0:
		_set_birds_visible(false)
		current_state = State.WAITING
		state_timer = randf_range(min_pass_interval, max_pass_interval)
		return

	for b in birds:
		# Ciclo natural de aleteo y planeo de paloma
		if b.is_gliding:
			b.glide_timer -= delta
			if b.glide_timer <= 0.0:
				b.is_gliding = false
				b.flap_timer = randf_range(1.4, 2.6)
				b.mat_bird.set_shader_parameter("flap_strength", 1.0)
		else:
			b.flap_timer -= delta
			if b.flap_timer <= 0.0:
				b.is_gliding = true
				b.glide_timer = randf_range(1.2, 2.2)
				b.mat_bird.set_shader_parameter("flap_strength", 0.06)

		# Pequeña oscilación local dentro de la bandada
		var bob = sin(time_alive * 2.0 + b.personal_phase) * 0.15
		var desired_pos_3d = flock_center_3d + (b.offset_flock.rotated(Vector3.UP, flock_yaw - PI)) + Vector3(0.0, bob, 0.0)
		b.local_pos = b.local_pos.lerp(desired_pos_3d, delta * 4.0)

		# Posición y rotación de la paloma
		b.mesh_inst.global_position = b.local_pos
		b.mesh_inst.rotation.y = lerp_angle(b.mesh_inst.rotation.y, flock_yaw, delta * 5.0)

		# Alabeo suave en las alas en giros
		b.bank_angle = lerp(b.bank_angle, target_flock_bank, delta * 3.5)
		b.mesh_inst.rotation.z = b.bank_angle

		# Sombra proyectada en el suelo
		var ground_y = focal.y + 0.03
		var shadow_offset_z = (b.local_pos.y - ground_y) * 0.18
		b.shadow_inst.global_position = Vector3(b.local_pos.x, ground_y, b.local_pos.z + shadow_offset_z)
		
		# Ajuste de tamaño y opacidad de la sombra según la altura
		var h_ratio = clamp((b.local_pos.y - ground_y) / 12.0, 0.0, 1.0)
		var shadow_scale = lerp(0.7, 1.25, h_ratio)
		b.shadow_inst.scale = Vector3(shadow_scale, 1.0, shadow_scale * 0.85)
		var shadow_alpha = lerp(0.35, 0.15, h_ratio)
		b.mat_shadow.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, shadow_alpha))

func _read_map_scale_factors() -> void:
	var p = get_parent()
	while p:
		if p.has_meta("correction_z"):
			_correction_z_cached = p.get_meta("correction_z")
		if "scale_factor" in p:
			_scale_factor_cached = p.scale_factor
		p = p.get_parent()

## Encuentra el foco de atención 3D: SIEMPRE la nave del jugador primero (centro visible de pantalla)
func _get_focal_point_3d() -> Vector3:
	var p_node = get_tree().get_first_node_in_group("player") if get_tree() else null
	if is_instance_valid(p_node):
		var wr3d = p_node.get("world_root_3d")
		if is_instance_valid(wr3d):
			return Vector3(wr3d.global_position.x, wr3d.global_position.y, wr3d.global_position.z)
		if p_node is Node2D:
			var p2d: Vector2 = p_node.global_position
			return Vector3(p2d.x * _scale_factor_cached, 0.0, p2d.y * _scale_factor_cached * _correction_z_cached)

	var cam = get_viewport().get_camera_3d() if get_viewport() else null
	if is_instance_valid(cam):
		var ground_plane = Plane(Vector3.UP, 0.0)
		var hit = ground_plane.intersects_ray(cam.global_position, -cam.global_transform.basis.z)
		if hit != null:
			return Vector3(hit.x, 0.0, hit.z)
		return Vector3(cam.global_position.x, 0.0, cam.global_position.z)

	return global_position

func _set_birds_visible(vis: bool) -> void:
	for b in birds:
		if is_instance_valid(b.mesh_inst):
			b.mesh_inst.visible = vis
		if is_instance_valid(b.shadow_inst):
			b.shadow_inst.visible = vis

func _set_fade_alpha(alpha: float) -> void:
	for b in birds:
		if is_instance_valid(b.mat_bird):
			b.mat_bird.set_shader_parameter("fade_alpha", alpha)
		if is_instance_valid(b.mat_shadow):
			b.mat_shadow.set_shader_parameter("fade_alpha", alpha)
