extends Node3D

# LoadingCombatController.gd
# Maneja la simulación cinemática 3D de combate espacial hiperdinámico para la pantalla de carga y login.
# Implementa maniobras de dogfight acrobático en 3D (alabeo/banking real, toneles evasivos 360°,
# retroceso de disparo, sacudidas de impacto y cámara cinematográfica multi-plano adaptativa).

var ship1: Node3D
var ship2: Node3D
var camera: Camera3D

var time_passed: float = 0.0

# Sistema de Cámara Cinemática Dinámica
var camera_mode: int = 0
var camera_mode_timer: float = 0.0
var cam_shake_trauma: float = 0.0
var cam_banking: float = 0.0

# Temporizadores de disparo y ráfagas
var shoot_cooldown1: float = 0.6
var shoot_cooldown2: float = 1.0
var burst_queue1: int = 0
var burst_queue2: int = 0
var burst_timer1: float = 0.0
var burst_timer2: float = 0.0

# Maniobras acrobáticas evasivas (Toneles de 360 grados sobre el eje longitudinal)
var roll_spin1: float = 0.0
var roll_target1: float = 0.0
var roll_spin2: float = 0.0
var roll_target2: float = 0.0
var evasive_timer1: float = 3.5
var evasive_timer2: float = 6.2

# Disparo frontal: solo se dispara con el morro alineado al enemigo (~32° de cono)
const FACING_MIN_DOT := 0.85
const FACING_RETRY := 0.35

# Secuencia FPV (primera persona): esquiva -> ataca -> vuelve al plano general
const ORBIT_FOV := 75.0
var fpv_active := false
var fpv_phase := 0
var fpv_timer := 0.0
var fpv_ship: Node3D
var fpv_foe: Node3D
var fpv_pick := 1
var fpv_next_in := 10.0
var fpv_rolled := false
var fpv_fov := 75.0

# Flinch (sacudida por impacto) y Recoil (retroceso por disparo)
var flinch1: Vector3 = Vector3.ZERO
var flinch2: Vector3 = Vector3.ZERO
var recoil1: float = 0.0
var recoil2: float = 0.0

# Memoria de posición para cálculo de vectores de vuelo y aceleración
var prev_pos1: Vector3 = Vector3.ZERO
var prev_pos2: Vector3 = Vector3.ZERO
var vel1: Vector3 = Vector3.ZERO
var vel2: Vector3 = Vector3.ZERO
var last_turn_rate1: float = 0.0
var last_turn_rate2: float = 0.0

# Luces de tobera/motores para propulsión visual
var thruster1: OmniLight3D
var thruster2: OmniLight3D

class ActiveProjectile extends RefCounted:
	var node: Node3D
	var start_pos: Vector3
	var target_ship: Node3D
	var progress: float = 0.0
	var duration: float = 1.0
	var is_emp: bool = false
	var color: Color
	var light: OmniLight3D
	var miss: bool = false # Si es true, roza al objetivo sin impactar (esquiva FPV)
	var miss_offset: Vector3 = Vector3.ZERO

var active_projectiles: Array[ActiveProjectile] = []

func _ready():
	shoot_cooldown1 = randf_range(0.4, 0.9)
	shoot_cooldown2 = randf_range(0.7, 1.3)
	camera_mode_timer = randf_range(6.0, 9.0)
	fpv_next_in = randf_range(8.0, 12.0)
	
	# Inicializar posiciones base
	if is_instance_valid(ship1):
		prev_pos1 = _calc_ship_pos(1, 0.0)
		ship1.position = prev_pos1
		_setup_thruster_light(ship1, Color(0.2, 0.95, 0.6), true)
	if is_instance_valid(ship2):
		prev_pos2 = _calc_ship_pos(2, 0.0)
		ship2.position = prev_pos2
		_setup_thruster_light(ship2, Color(0.15, 0.7, 1.0), false)
		
	print("[LoadingCombat] Controlador cinemático 3D de combate espacial inicializado.")

func _setup_thruster_light(ship: Node3D, col: Color, is_ship1: bool):
	var l = OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.2
	l.omni_range = 3.2
	# Posicionar en la parte trasera del modelo (propulsores en -X)
	l.position = Vector3(-0.6, 0.08, 0.0)
	ship.add_child(l)
	if is_ship1:
		thruster1 = l
	else:
		thruster2 = l

func _process(delta: float):
	time_passed += delta
	
	# 1. Movimiento acrobático 3D de las naves y rotaciones dinámicas
	_animate_ships(delta)
	
	# 2. Secuencia FPV (si está activa pisa a la cámara orbital)
	_update_fpv(delta)
	
	# 2b. Control cinemático multi-plano de cámara con encuadre derecho y sacudida
	if fpv_active:
		_animate_fpv_camera(delta)
	else:
		_animate_camera(delta)
	
	# 3. Temporizadores de disparo y ráfagas
	_handle_shooting(delta)
	
	# 4. Actualización física de proyectiles en vuelo
	_update_projectiles(delta)

# Cálculo suave de la trayectoria de dogfight en el espacio tridimensional
func _calc_ship_pos(ship_id: int, t: float) -> Vector3:
	if ship_id == 1:
		# Nave 1: Trayectoria de intercepción agresiva con virajes y picados tridimensionales
		var w = t * 0.50
		var x = sin(w) * 4.6 + cos(w * 1.9) * 0.85
		var z = cos(w * 0.92) * 2.7 + sin(w * 1.8) * 0.6
		var y = sin(w * 1.35) * 1.15 + cos(w * 0.65) * 0.45
		return Vector3(x, y, z)
	else:
		# Nave 2: Trayectoria de contraataque y evasión con tijeras tácticas
		var w = t * 0.50 + 2.85
		var x = sin(w + 0.35) * 4.8 - cos(w * 1.65) * 0.9
		var z = cos(w * 0.92 + 0.25) * 2.85 - sin(w * 2.05) * 0.55
		var y = -sin(w * 1.35) * 1.05 - cos(w * 0.65) * 0.4
		return Vector3(x, y, z)

func _animate_ships(delta: float):
	if not is_instance_valid(ship1) or not is_instance_valid(ship2):
		return
		
	# Amortiguar flinch (impactos) y recoil (disparos)
	flinch1 = flinch1.lerp(Vector3.ZERO, delta * 9.0)
	flinch2 = flinch2.lerp(Vector3.ZERO, delta * 9.0)
	recoil1 = lerpf(recoil1, 0.0, delta * 8.0)
	recoil2 = lerpf(recoil2, 0.0, delta * 8.0)
	
	# Toneles evasivos (Barrel rolls 360°) con interpolación suave
	roll_spin1 = lerp_angle(roll_spin1, roll_target1, delta * 6.5)
	roll_spin2 = lerp_angle(roll_spin2, roll_target2, delta * 6.5)
	
	# Manejar temporizadores de maniobras evasivas espontáneas
	evasive_timer1 -= delta
	if evasive_timer1 <= 0.0:
		evasive_timer1 = randf_range(5.5, 9.0)
		_trigger_barrel_roll(1)
		
	evasive_timer2 -= delta
	if evasive_timer2 <= 0.0:
		evasive_timer2 = randf_range(5.0, 8.5)
		_trigger_barrel_roll(2)
		
	# --------------------------------------------------------------------------
	# NAVE 1: Actualizar Posición y Transform
	# --------------------------------------------------------------------------
	var target_pos1 = _calc_ship_pos(1, time_passed)
	vel1 = (target_pos1 - prev_pos1) / max(delta, 0.0001)
	prev_pos1 = target_pos1
	
	# Aplicar retroceso local y flinch
	var forward_approx1 = (target_pos1 - _calc_ship_pos(1, time_passed - 0.05)).normalized()
	ship1.position = target_pos1 + flinch1 - (forward_approx1 * recoil1)
	
	# Vector hacia el enemigo y vector de velocidad
	var aim_dir1 = (ship2.position - ship1.position).normalized()
	var flight_dir1 = vel1.normalized() if vel1.length_squared() > 0.01 else aim_dir1
	
	# Mezcla dinámica: El morro apunta combinando la trayectoria de vuelo y la mira hacia el enemigo
	var combat_heading1 = flight_dir1.lerp(aim_dir1, 0.48).normalized()
	
	# Tasa de viraje para Ladeo Dinámico (Banking)
	var future_vel1 = (_calc_ship_pos(1, time_passed + 0.12) - target_pos1) / 0.12
	var turn_rate1 = flight_dir1.cross(future_vel1.normalized()).y
	last_turn_rate1 = turn_rate1
	var bank_angle1 = clamp(turn_rate1 * 4.2, -1.25, 1.25)
	var pitch_angle1 = clamp(vel1.y * 0.18, -0.45, 0.45)
	
	var t1 = ship1.transform.looking_at(ship1.position + combat_heading1, Vector3.UP)
	t1 = t1.rotated_local(Vector3.UP, PI * 0.5) # Morro (+X) al frente de vuelo, propulsores (-X) atrás
	t1 = t1.rotated_local(Vector3.RIGHT, -bank_angle1 + roll_spin1) # Alabeo longitudinal (roll sobre el eje morro-cola +X)
	t1 = t1.rotated_local(Vector3.BACK, pitch_angle1) # Cabeceo transversal (pitch sobre el eje alar Z)
	
	ship1.transform = ship1.transform.interpolate_with(t1, delta * 6.5)
	
	# --------------------------------------------------------------------------
	# NAVE 2: Actualizar Posición y Transform
	# --------------------------------------------------------------------------
	var target_pos2 = _calc_ship_pos(2, time_passed)
	vel2 = (target_pos2 - prev_pos2) / max(delta, 0.0001)
	prev_pos2 = target_pos2
	
	var forward_approx2 = (target_pos2 - _calc_ship_pos(2, time_passed - 0.05)).normalized()
	ship2.position = target_pos2 + flinch2 - (forward_approx2 * recoil2)
	
	var aim_dir2 = (ship1.position - ship2.position).normalized()
	var flight_dir2 = vel2.normalized() if vel2.length_squared() > 0.01 else aim_dir2
	var combat_heading2 = flight_dir2.lerp(aim_dir2, 0.48).normalized()
	
	var future_vel2 = (_calc_ship_pos(2, time_passed + 0.12) - target_pos2) / 0.12
	var turn_rate2 = flight_dir2.cross(future_vel2.normalized()).y
	last_turn_rate2 = turn_rate2
	var bank_angle2 = clamp(turn_rate2 * 4.2, -1.25, 1.25)
	var pitch_angle2 = clamp(vel2.y * 0.18, -0.45, 0.45)
	
	var t2 = ship2.transform.looking_at(ship2.position + combat_heading2, Vector3.UP)
	t2 = t2.rotated_local(Vector3.UP, PI * 0.5) # Morro (+X) al frente de vuelo, propulsores (-X) atrás
	t2 = t2.rotated_local(Vector3.RIGHT, -bank_angle2 + roll_spin2) # Alabeo longitudinal (roll sobre el eje morro-cola +X)
	t2 = t2.rotated_local(Vector3.BACK, pitch_angle2) # Cabeceo transversal (pitch sobre el eje alar Z)
	
	ship2.transform = ship2.transform.interpolate_with(t2, delta * 6.5)
	
	# Modular potencia de luces de motor con aceleración
	if is_instance_valid(thruster1):
		thruster1.light_energy = 1.8 + abs(bank_angle1) * 1.5 + abs(pitch_angle1) * 1.2
	if is_instance_valid(thruster2):
		thruster2.light_energy = 1.8 + abs(bank_angle2) * 1.5 + abs(pitch_angle2) * 1.2

func _trigger_barrel_roll(ship_id: int):
	# Ejecutar un giro de 360 grados sobre el eje longitudinal de la nave
	if ship_id == 1:
		roll_target1 += TAU * (1.0 if randf() > 0.5 else -1.0)
	else:
		roll_target2 += TAU * (1.0 if randf() > 0.5 else -1.0)

func _animate_camera(delta: float):
	if not is_instance_valid(camera):
		return
		
	# Ciclo de modos cinemáticos de cámara (Director de Combate)
	camera_mode_timer -= delta
	if camera_mode_timer <= 0.0:
		camera_mode_timer = randf_range(7.0, 10.0)
		camera_mode = (camera_mode + 1) % 3
		
	# Amortiguar sacudida de cámara por impactos
	cam_shake_trauma = max(0.0, cam_shake_trauma - delta * 2.5)
	var shake_offset = Vector3(
		randf_range(-1.0, 1.0) * cam_shake_trauma * 0.22,
		randf_range(-1.0, 1.0) * cam_shake_trauma * 0.22,
		randf_range(-1.0, 1.0) * cam_shake_trauma * 0.22
	)
	
	# Medir distancia entre naves para zoom dinámico en cruces cercanos
	var dist_between_ships = 6.0
	var combat_center = Vector3.ZERO
	if is_instance_valid(ship1) and is_instance_valid(ship2):
		dist_between_ships = ship1.position.distance_to(ship2.position)
		combat_center = (ship1.position + ship2.position) * 0.5
		
	# Zoom reactivo: La cámara se acerca en cruces a alta velocidad (< 4.2 unidades)
	var proximity_zoom = clamp((4.5 - dist_between_ships) * 0.65, 0.0, 1.8)
	
	# Calcular posición y alabeo deseado según el plano cinemático activo
	var target_cam_pos = Vector3.ZERO
	var target_cam_bank = 0.0
	
	match camera_mode:
		0:
			# PLANO 1: Persecución Aérea Dinámica con Inclinación Cinemática (Dutch Angle)
			var angle = time_passed * 0.14
			var dist = 8.5 - proximity_zoom
			target_cam_pos = Vector3(
				sin(angle) * dist,
				1.3 + sin(time_passed * 0.25) * 0.7,
				cos(angle) * dist
			)
			target_cam_bank = clamp(last_turn_rate1 * -0.18, -0.12, 0.12)
			
		1:
			# PLANO 2: Contrapicado Heroico (Low-Angle Hero Shot) viendo naves contra el firmamento
			var angle = time_passed * 0.11 + 1.4
			var dist = 7.6 - proximity_zoom
			target_cam_pos = Vector3(
				sin(angle) * dist,
				-0.9 + sin(time_passed * 0.2) * 0.4,
				cos(angle) * dist
			)
			target_cam_bank = clamp(last_turn_rate2 * 0.16, -0.10, 0.10)
			
		2:
			# PLANO 3: Barrido Táctico Elevado (High-Orbit Tactical Sweep)
			var angle = time_passed * 0.16 + 2.8
			var dist = 9.0 - proximity_zoom
			target_cam_pos = Vector3(
				sin(angle) * dist,
				2.7 + cos(time_passed * 0.22) * 0.6,
				cos(angle) * dist
			)
			target_cam_bank = sin(time_passed * 0.35) * 0.07
			
	# Punto de enfoque: Centrado en el combate con desplazamiento hacia la derecha (+1.35 en X)
	# para que el combate ocurra despejado a la derecha del panel de login
	var target_look = combat_center + Vector3(1.35, 0.0, 0.0)
	
	# Interpolación de posición con sacudida
	camera.position = camera.position.lerp(target_cam_pos + shake_offset, delta * 2.6)
	
	# Construir la orientación suave de la cámara con alabeo cinemático (Camera Bank)
	var current_trans = camera.global_transform
	var target_trans = camera.global_transform.looking_at(target_look, Vector3.UP)
	target_trans = target_trans.rotated_local(Vector3.FORWARD, target_cam_bank)
	
	camera.global_transform = current_trans.interpolate_with(target_trans, delta * 3.2)
	camera.fov = lerpf(camera.fov, ORBIT_FOV, min(1.0, delta * 3.0))

# Secuencia FPV: cámara en cabina de una nave, esquiva el disparo rival con un
# tonel, contraataca de frente y devuelve al plano general. Alterna la nave POV.
func _update_fpv(delta: float):
	if not is_instance_valid(ship1) or not is_instance_valid(ship2):
		fpv_active = false
		return
	if not fpv_active:
		fpv_next_in -= delta
		if fpv_next_in <= 0.0:
			_start_fpv()
		return
	fpv_timer += delta
	if fpv_phase == 1:
		# FASE 1 - ESQUIVA: el proyectil rival viene a la cabina, tonel al cruzarse
		if not fpv_rolled and fpv_timer >= 1.05:
			fpv_rolled = true
			if fpv_ship == ship1:
				_trigger_barrel_roll(1)
			else:
				_trigger_barrel_roll(2)
			cam_shake_trauma = min(1.0, cam_shake_trauma + 0.25)
		fpv_fov = 88.0
		if fpv_timer >= 2.1:
			# FASE 2 - ATAQUE: la nave POV responde de frente con doble disparo
			fpv_phase = 2
			fpv_timer = 0.0
			var is_pov_emp = fpv_ship != ship1
			var col = Color(0.1, 0.7, 1.0) if is_pov_emp else Color(0.2, 1.0, 0.45)
			_spawn_laser_projectile(fpv_ship, fpv_foe, col, is_pov_emp)
			_spawn_laser_projectile(fpv_ship, fpv_foe, col, is_pov_emp)
			if fpv_ship == ship1:
				recoil1 = 0.22
			else:
				recoil2 = 0.22
	elif fpv_phase == 2:
		fpv_fov = 80.0
		if fpv_timer >= 1.7:
			# FASE 3 - RETORNO: la órbita general retoma con interpolación suave
			fpv_active = false
			fpv_phase = 0
			fpv_next_in = randf_range(18.0, 26.0)
			fpv_fov = ORBIT_FOV

func _start_fpv():
	fpv_ship = ship1 if fpv_pick == 1 else ship2
	fpv_foe = ship2 if fpv_pick == 1 else ship1
	fpv_pick = 2 if fpv_pick == 1 else 1
	if not is_instance_valid(fpv_ship) or not is_instance_valid(fpv_foe):
		fpv_next_in = 6.0
		return
	fpv_active = true
	fpv_phase = 1
	fpv_timer = 0.0
	fpv_rolled = false
	# El rival abre fuego: disparo largo que va a errar rozando la cabina
	var fwd: Vector3 = (fpv_ship.global_position - fpv_foe.global_position).normalized()
	var side: Vector3 = fwd.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var foe_is_emp = fpv_foe == ship2
	var col = Color(0.1, 0.7, 1.0) if foe_is_emp else Color(0.2, 1.0, 0.45)
	_spawn_laser_projectile(fpv_foe, fpv_ship, col, foe_is_emp, true, side * 1.35, 1.8)
	cam_shake_trauma = min(1.0, cam_shake_trauma + 0.1)

func _animate_fpv_camera(delta: float):
	if not is_instance_valid(camera) or not is_instance_valid(fpv_ship) or not is_instance_valid(fpv_foe):
		fpv_active = false
		return
	cam_shake_trauma = max(0.0, cam_shake_trauma - delta * 2.5)
	var shake_offset = Vector3(
		randf_range(-1.0, 1.0) * cam_shake_trauma * 0.18,
		randf_range(-1.0, 1.0) * cam_shake_trauma * 0.18,
		randf_range(-1.0, 1.0) * cam_shake_trauma * 0.18
	)
	# Ojo en cabina: sobre el lomo viendo el morro al frente (+X local)
	var st: Transform3D = fpv_ship.global_transform
	var eye: Vector3 = (st * Vector3(-0.15, 0.55, 0.0)) + shake_offset
	camera.global_position = camera.global_position.lerp(eye, min(1.0, delta * 9.0))
	var to_foe: Vector3 = fpv_foe.global_position - camera.global_position
	if to_foe.length_squared() < 0.001:
		return
	var target_trans := Transform3D(Basis.looking_at(to_foe), camera.global_position)
	# Alabeo parcial con el viraje de la nave POV (sin heredar el tonel completo)
	var rate := last_turn_rate1 if fpv_ship == ship1 else last_turn_rate2
	target_trans = target_trans.rotated_local(Vector3.FORWARD, clamp(rate * -0.2, -0.14, 0.14))
	camera.global_transform = camera.global_transform.interpolate_with(target_trans, min(1.0, delta * 7.0))
	camera.fov = lerpf(camera.fov, fpv_fov, min(1.0, delta * 3.0))

func _handle_shooting(delta: float):
	if not is_instance_valid(ship1) or not is_instance_valid(ship2):
		return
		
	# Procesar ráfagas pendientes de Nave 1 (cada tiro exige morro alineado)
	if burst_queue1 > 0:
		burst_timer1 -= delta
		if burst_timer1 <= 0.0:
			if _facing_factor(ship1, ship2) < FACING_MIN_DOT:
				burst_timer1 = 0.12 # Espera a encarar sin gastar la ráfaga
			else:
				burst_queue1 -= 1
				burst_timer1 = 0.16
				_spawn_laser_projectile(ship1, ship2, Color(0.2, 1.0, 0.45), false)
				recoil1 = 0.18
			
	# Procesar ráfagas pendientes de Nave 2 (cada tiro exige morro alineado)
	if burst_queue2 > 0:
		burst_timer2 -= delta
		if burst_timer2 <= 0.0:
			if _facing_factor(ship2, ship1) < FACING_MIN_DOT:
				burst_timer2 = 0.12 # Espera a encarar sin gastar la ráfaga
			else:
				burst_queue2 -= 1
				burst_timer2 = 0.18
				_spawn_laser_projectile(ship2, ship1, Color(0.1, 0.7, 1.0), true)
				recoil2 = 0.20
			
	# Temporizador general de disparo de Nave 1 (SOLO de frente: morro alineado)
	shoot_cooldown1 -= delta
	if shoot_cooldown1 <= 0.0:
		if _facing_factor(ship1, ship2) < FACING_MIN_DOT:
			shoot_cooldown1 = FACING_RETRY # Reintenta ni bien encara al enemigo
		else:
			shoot_cooldown1 = randf_range(1.4, 2.2)
			if randf() < 0.45:
				burst_queue1 = 2
				burst_timer1 = 0.0
			else:
				_spawn_laser_projectile(ship1, ship2, Color(0.2, 1.0, 0.45), false)
				recoil1 = 0.18
		
	# Temporizador general de disparo de Nave 2 (SOLO de frente: morro alineado)
	shoot_cooldown2 -= delta
	if shoot_cooldown2 <= 0.0:
		if _facing_factor(ship2, ship1) < FACING_MIN_DOT:
			shoot_cooldown2 = FACING_RETRY # Reintenta ni bien encara al enemigo
		else:
			shoot_cooldown2 = randf_range(1.6, 2.5)
			if randf() < 0.40:
				burst_queue2 = 2
				burst_timer2 = 0.0
			else:
				_spawn_laser_projectile(ship2, ship1, Color(0.1, 0.7, 1.0), true)
				recoil2 = 0.20

# Alineación del morro (+X local) con la dirección al enemigo: 1.0 = de frente
func _facing_factor(from_ship: Node3D, to_ship: Node3D) -> float:
	if not is_instance_valid(from_ship) or not is_instance_valid(to_ship):
		return 0.0
	var nose: Vector3 = from_ship.global_transform.basis.x.normalized()
	var to_foe: Vector3 = (to_ship.global_position - from_ship.global_position).normalized()
	return nose.dot(to_foe)

# Punto de salida del disparo: punta frontal del morro de la nave (+X local)
func _muzzle_pos(ship: Node3D) -> Vector3:
	if not is_instance_valid(ship):
		return Vector3.ZERO
	return ship.global_transform * Vector3(0.85, 0.08, 0.0)

func _spawn_laser_projectile(from_ship: Node3D, to_ship: Node3D, col: Color, is_emp: bool, miss := false, miss_offset := Vector3.ZERO, duration_override := 0.0):
	if not is_instance_valid(from_ship) or not is_instance_valid(to_ship):
		return
	# El disparo nace en la punta frontal del morro de la nave
	var start_pos: Vector3 = _muzzle_pos(from_ship)
	
	# 1. FASE DE ANTICIPACIÓN: Fogonazo oficial
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
				
				var anim = antic_inst.get_node_or_null("AnimationPlayer")
				if anim:
					anim.play("Init")
				
				var tw_antic = create_tween()
				tw_antic.tween_interval(1.2)
				tw_antic.tween_callback(antic_inst.queue_free)
				
	# 2. Instanciar escena de proyectil oficial
	var proj_path = "res://VFX/scenes/VFX_Hadouken.tscn" if is_emp else "res://VFX/scenes/VFX_Cube_projectile.tscn"
	var proj_node: Node3D = null
	if ResourceLoader.exists(proj_path):
		var proj_scene = load(proj_path)
		if proj_scene:
			proj_node = proj_scene.instantiate()
			
	if not proj_node:
		proj_node = Node3D.new()
		var m = MeshInstance3D.new()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var sm = SphereMesh.new()
		sm.radius = 0.15; sm.height = 0.3
		var sm_mat = StandardMaterial3D.new()
		sm_mat.albedo_color = col
		sm_mat.emission_enabled = true
		sm_mat.emission = col
		sm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = sm_mat
		m.mesh = sm
		m.material_override = sm_mat
		proj_node.add_child(m)
		
	proj_node.position = start_pos
	add_child(proj_node)
	
	proj_node.look_at(to_ship.position, Vector3.UP)
	proj_node.scale = Vector3(0.65, 0.65, 0.65) if is_emp else Vector3(0.55, 0.55, 0.55)
	
	var light = OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.8
	light.omni_range = 4.8
	proj_node.add_child(light)
	
	var ap = ActiveProjectile.new()
	ap.node = proj_node
	ap.start_pos = start_pos
	ap.target_ship = to_ship
	ap.is_emp = is_emp
	ap.color = col
	ap.light = light
	ap.miss = miss
	ap.miss_offset = miss_offset
	ap.duration = duration_override if duration_override > 0.0 else randf_range(0.85, 1.1)
	
	active_projectiles.append(ap)

func _update_projectiles(delta: float):
	var to_remove: Array[ActiveProjectile] = []
	
	for ap in active_projectiles:
		if not is_instance_valid(ap.node) or not is_instance_valid(ap.target_ship):
			to_remove.append(ap)
			continue
			
		ap.progress += delta * (1.0 / ap.duration)
		var current_target_pos = ap.target_ship.position
		var goal = current_target_pos + (ap.miss_offset if ap.miss else Vector3.ZERO)
		
		# Viaje balístico con ligera curvatura
		var new_pos = ap.start_pos.lerp(goal, ap.progress)
		ap.node.position = new_pos
		
		if ap.progress < 0.95:
			ap.node.look_at(goal, Vector3.UP)
				
		if ap.progress >= 1.0:
			if ap.miss:
				# Roza y se pierde en el fondo (solo un suspiro de cámara)
				cam_shake_trauma = min(1.0, cam_shake_trauma + 0.15)
			else:
				_trigger_impact_effect(ap.target_ship, ap.color, ap.is_emp)
			if is_instance_valid(ap.node):
				ap.node.visible = false
				ap.node.queue_free()
			to_remove.append(ap)
			
	for ap in to_remove:
		active_projectiles.erase(ap)

func _trigger_impact_effect(ship: Node3D, col: Color, is_emp: bool):
	if not is_instance_valid(ship):
		return
		
	var impact_pos = ship.position
	
	# Sacudida física (Flinch) en la nave y sacudida cinemática en la cámara
	var impact_dir = Vector3(randf_range(-0.25, 0.25), randf_range(-0.18, 0.18), randf_range(-0.25, 0.25))
	cam_shake_trauma = min(1.0, cam_shake_trauma + 0.35)
	
	if ship == ship1:
		flinch1 = impact_dir
		if randf() < 0.55: _trigger_barrel_roll(1)
	else:
		flinch2 = impact_dir
		if randf() < 0.55: _trigger_barrel_roll(2)
		
	# 1. Efecto de impacto oficial (VFX)
	var hit_path = "res://VFX/scenes/VFX_Hit_hadouken.tscn" if is_emp else "res://VFX/scenes/VFX_Hit_cyber.tscn"
	if ResourceLoader.exists(hit_path):
		var hit_scene = load(hit_path)
		if hit_scene:
			var hit_inst = hit_scene.instantiate()
			if hit_inst is Node3D:
				add_child(hit_inst)
				hit_inst.position = impact_pos
				hit_inst.scale = Vector3(1.3, 1.3, 1.3)
				
				var tw_hit = create_tween()
				tw_hit.tween_interval(1.5)
				tw_hit.tween_callback(func():
					if is_instance_valid(hit_inst):
						hit_inst.visible = false
						hit_inst.queue_free()
				)
				
	# 2. Escudo Deflector Reactivo
	var shield = MeshInstance3D.new()
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var sm = SphereMesh.new()
	sm.radius = 1.2
	sm.height = 2.4
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.0)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat
	shield.mesh = sm
	shield.material_override = mat
	ship.add_child(shield)
	shield.position = Vector3.ZERO
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.55, 0.04)
	tw.tween_property(shield, "scale", Vector3(1.3, 1.3, 1.3), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	var tw_fade = create_tween()
	tw_fade.tween_interval(0.08)
	tw_fade.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw_fade.tween_callback(func():
		if is_instance_valid(tw): tw.kill()
		if is_instance_valid(shield):
			shield.visible = false
			shield.queue_free()
	)
	
	# 3. Chispas de impacto de plasma
	_spawn_spark_particles(impact_pos, col, is_emp)

func _spawn_spark_particles(pos: Vector3, col: Color, is_emp: bool):
	var spark_count = 12 if is_emp else 6
	var particle_lifetime = 0.42
	
	for i in range(spark_count):
		var p = MeshInstance3D.new()
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var sm = SphereMesh.new()
		var size = randf_range(0.03, 0.06)
		sm.radius = size
		sm.height = size * 2
		
		var p_mat = StandardMaterial3D.new()
		p_mat.albedo_color = Color.WHITE
		p_mat.emission_enabled = true
		p_mat.emission = col
		p_mat.emission_energy_multiplier = 5.0
		p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = p_mat
		p.mesh = sm
		p.material_override = p_mat
		
		add_child(p)
		p.position = pos
		
		var dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		var speed = randf_range(1.8, 3.4)
		var dest = pos + dir * (speed * particle_lifetime)
		
		var tw_p = create_tween().set_parallel(true)
		tw_p.tween_property(p, "position", dest, particle_lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_p.tween_property(p, "scale", Vector3.ZERO, particle_lifetime).set_trans(Tween.TRANS_LINEAR)
		tw_p.chain().tween_callback(func():
			if is_instance_valid(p):
				p.visible = false
				p.queue_free()
		)

func _exit_tree():
	for ap in active_projectiles:
		if is_instance_valid(ap.node):
			ap.node.visible = false
			ap.node.queue_free()
	active_projectiles.clear()
