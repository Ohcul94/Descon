extends Node3D

# ==============================================================================
# VFX_Water_Laguna.gd
# Controla la vida de la laguna: saltos esporádicos, bajos y sutiles de pirañas
# con apariencia anatómica real, aleteo vivo de pez y orientación perfecta hacia adelante.
# ==============================================================================

@export var min_jump_interval: float = 12.0
@export var max_jump_interval: float = 24.0
@export var jump_radius: float = 9.0

var _jump_timer: float = 0.0

# 6 Paletas de colores variadas (desde vientre rojo clásico hasta mutantes)
const PALETTES = [
	# 1. Piraña Vientre Rojo Clásica (Lomo gris pizarra/carbón, vientre carmesí fuego)
	{ "back": Color(0.18, 0.22, 0.25), "belly": Color(0.85, 0.20, 0.10), "fin": Color(0.45, 0.12, 0.10), "eye": Color(0.95, 0.60, 0.15) },
	# 2. Piraña Dorada del Pantano (Lomo oliva oscuro, vientre dorado miel)
	{ "back": Color(0.25, 0.24, 0.16), "belly": Color(0.90, 0.72, 0.18), "fin": Color(0.60, 0.42, 0.12), "eye": Color(1.0, 0.90, 0.25) },
	# 3. Piraña Esmeralda Tóxica (Lomo verde musgo oscuro, vientre jade fosforescente)
	{ "back": Color(0.10, 0.30, 0.20), "belly": Color(0.22, 0.85, 0.42), "fin": Color(0.10, 0.45, 0.22), "eye": Color(0.25, 1.0, 0.45) },
	# 4. Piraña Violeta Mutante (Lomo amatista profundo, vientre magenta neón)
	{ "back": Color(0.28, 0.12, 0.38), "belly": Color(0.82, 0.20, 0.88), "fin": Color(0.45, 0.10, 0.55), "eye": Color(1.0, 0.20, 0.80) },
	# 5. Piraña Cyan Bioluminiscente (Lomo azul marino abisal, vientre turquesa eléctrico)
	{ "back": Color(0.08, 0.18, 0.35), "belly": Color(0.16, 0.76, 0.94), "fin": Color(0.08, 0.38, 0.60), "eye": Color(0.20, 0.88, 1.0) },
	# 6. Piraña Negra Obsidiana (Cuerpo negro azabache, vientre ahumado, ojos rubí)
	{ "back": Color(0.07, 0.07, 0.09), "belly": Color(0.22, 0.08, 0.12), "fin": Color(0.10, 0.05, 0.07), "eye": Color(1.0, 0.15, 0.10) }
]

func _ready() -> void:
	# Inicio desfasado aleatorio para que lagunas vecinas no salten a la vez
	_jump_timer = randf_range(5.0, 12.0)

func _process(delta: float) -> void:
	_jump_timer -= delta
	if _jump_timer <= 0.0:
		_jump_timer = randf_range(min_jump_interval, max_jump_interval)
		_trigger_fish_jump()

func _trigger_fish_jump() -> void:
	# Punto inicial y final del salto dentro del charco
	var start_angle = randf() * TAU
	var start_dist = randf_range(2.0, jump_radius)
	var start_pos = Vector3(cos(start_angle) * start_dist, -0.08, sin(start_angle) * start_dist)

	# Salto ágil y corto: distancia horizontal de 1.0m a 1.5m
	var jump_heading = start_angle + randf_range(-0.7, 0.7)
	var jump_dist = randf_range(1.0, 1.5)
	var end_pos = start_pos + Vector3(cos(jump_heading) * jump_dist, 0.0, sin(jump_heading) * jump_dist)
	end_pos.y = -0.12

	# Salto muy bajito (entre 18cm y 28cm sobre el agua)
	var apex_h = randf_range(0.18, 0.28)
	var duration = randf_range(0.55, 0.65)

	# Vector hacia adelante en el plano horizontal (dirección real del salto)
	var fwd_dir = Vector3(end_pos.x - start_pos.x, 0.0, end_pos.z - start_pos.z).normalized()
	if fwd_dir.length_squared() < 0.001:
		fwd_dir = Vector3.FORWARD

	# Salpicadura sutil al emerger
	_create_splash(start_pos)

	# Construir el pez articulado 3D (tamaño pequeño de ~18-22 cm)
	var fish = _build_realistic_piranha_mesh()
	fish.position = start_pos
	add_child(fish)

	var tween = create_tween()

	# Animación: salta hacia adelante con la cabeza hacia arriba y cae más inclinada hacia abajo
	var jump_anim = func(t: float):
		if not is_instance_valid(fish): return

		# 1. Posición balística baja
		var p = start_pos.lerp(end_pos, t)
		p.y += 4.0 * apex_h * t * (1.0 - t)
		fish.position = p

		# 2. Inclinación de la cabeza (Pitch):
		# Al salir (t < 0.38): Cabeza levantada apuntando hacia arriba (+36° a +4°)
		# En la cúspide (t ≈ 0.40): Nivelada horizontalmente (+4°)
		# En la caída (t >= 0.40): Cae más inclinada de cabeza hacia abajo (-4° a -56°)
		var pitch_deg: float
		if t < 0.38:
			var s = t / 0.38
			pitch_deg = lerpf(36.0, 4.0, s * s)
		else:
			var s = (t - 0.38) / 0.62
			pitch_deg = lerpf(4.0, -56.0, sqrt(s))

		# 3. Vector 3D exacto hacia donde apunta la cabeza:
		# fwd_dir apunta hacia adelante; sumamos la componente vertical por el pitch
		var pitch_rad = deg_to_rad(pitch_deg)
		var head_dir = (fwd_dir * cos(pitch_rad) + Vector3.UP * sin(pitch_rad)).normalized()

		# Orientar el pez hacia adelante (en su local, la cabeza está en -Z)
		fish.look_at(p + head_dir, Vector3.UP)

		# 4. Animación viva de pez: aleteo lateral de cola y cuerpo en el aire
		var tail = fish.get_node_or_null("TailPivot")
		if is_instance_valid(tail):
			tail.rotation.y = sin(t * TAU * 5.0) * deg_to_rad(24.0) * (1.0 - t * 0.25)

	tween.tween_method(jump_anim, 0.0, 1.0, duration)

	# Salpicadura al zambullirse de cabeza
	tween.tween_callback(_create_splash.bind(end_pos))
	tween.tween_callback(fish.queue_free)

func _create_splash(pos: Vector3) -> void:
	var particles = CPUParticles3D.new()
	particles.position = Vector3(pos.x, 0.02, pos.z)
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 6
	particles.lifetime = 0.35
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 30.0
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 1.6
	particles.gravity = Vector3(0, -9.8, 0)
	particles.scale_amount_min = 0.02
	particles.scale_amount_max = 0.05

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.96, 0.92, 0.70)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.metallic_specular = 0.9

	var sphere = SphereMesh.new()
	sphere.radius = 0.02
	sphere.height = 0.04
	sphere.radial_segments = 4
	sphere.rings = 3
	particles.mesh = sphere
	particles.material_override = mat

	add_child(particles)

	particles.finished.connect(particles.queue_free)

func _build_realistic_piranha_mesh() -> Node3D:
	var fish_root = Node3D.new()
	var palette = PALETTES.pick_random()

	# Material dorsal (lomo oscuro con escamas)
	var mat_back = StandardMaterial3D.new()
	mat_back.albedo_color = palette.back
	mat_back.roughness = 0.30
	mat_back.metallic = 0.20

	# Material ventral (vientre vivo contrastante)
	var mat_belly = StandardMaterial3D.new()
	mat_belly.albedo_color = palette.belly
	mat_belly.roughness = 0.25
	mat_belly.metallic = 0.15

	# Material de aletas (translúcidas con coloración)
	var mat_fin = StandardMaterial3D.new()
	mat_fin.albedo_color = palette.fin
	mat_fin.roughness = 0.35
	mat_fin.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Material de ojos (brillante)
	var mat_eye = StandardMaterial3D.new()
	mat_eye.albedo_color = palette.eye
	mat_eye.emission_enabled = true
	mat_eye.emission = palette.eye
	mat_eye.emission_energy_multiplier = 1.5

	# Material de dientes (blanco nítido)
	var mat_teeth = StandardMaterial3D.new()
	mat_teeth.albedo_color = Color(0.95, 0.95, 0.90)
	mat_teeth.roughness = 0.2

	# --------------------------------------------------------------------------
	# PARTE FRONTAL (Cabeza, Hocico, Mandíbula, Vientre, Aletas Pectorales)
	# En el espacio local: Cabeza = -Z (adelante), Cola = +Z (atrás), Lomo = +Y
	# --------------------------------------------------------------------------

	# 1. Cuerpo / Torso frontal (ovoide acostado a lo largo del eje Z)
	var front_body = MeshInstance3D.new()
	var front_mesh = SphereMesh.new()
	front_mesh.radius = 0.11
	front_mesh.height = 0.26
	front_mesh.radial_segments = 8
	front_mesh.rings = 5
	front_body.mesh = front_mesh
	front_body.material_override = mat_back
	front_body.scale = Vector3(0.55, 1.15, 1.0) # Comprimido a los lados, lomo alto
	front_body.position = Vector3(0.0, 0.02, -0.07)
	front_body.rotation_degrees.x = 90.0 # Acostado con eje longitudinal en Z
	fish_root.add_child(front_body)

	# 2. Vientre prominente colorido
	var belly = MeshInstance3D.new()
	var belly_mesh = SphereMesh.new()
	belly_mesh.radius = 0.09
	belly_mesh.height = 0.20
	belly_mesh.radial_segments = 7
	belly_mesh.rings = 4
	belly.mesh = belly_mesh
	belly.material_override = mat_belly
	belly.scale = Vector3(0.52, 1.0, 1.0)
	belly.position = Vector3(0.0, -0.04, -0.06)
	belly.rotation_degrees.x = 90.0
	fish_root.add_child(belly)

	# 3. Mandíbula inferior distintiva (prognata / mordida bulldog hacia adelante)
	var jaw = MeshInstance3D.new()
	var jaw_mesh = BoxMesh.new()
	jaw_mesh.size = Vector3(0.065, 0.035, 0.07)
	jaw.mesh = jaw_mesh
	jaw.material_override = mat_belly
	jaw.position = Vector3(0.0, -0.05, -0.17)
	jaw.rotation_degrees.x = 18.0
	fish_root.add_child(jaw)

	# 4. Dientes pequeños afilados en la mandíbula
	var teeth = MeshInstance3D.new()
	var teeth_mesh = BoxMesh.new()
	teeth_mesh.size = Vector3(0.045, 0.015, 0.015)
	teeth.mesh = teeth_mesh
	teeth.material_override = mat_teeth
	teeth.position = Vector3(0.0, -0.03, -0.19)
	fish_root.add_child(teeth)

	# 5. Ojos a ambos lados de la cabeza
	for side in [-1.0, 1.0]:
		var eye = MeshInstance3D.new()
		var eye_mesh = SphereMesh.new()
		eye_mesh.radius = 0.022
		eye_mesh.height = 0.035
		eye_mesh.radial_segments = 5
		eye_mesh.rings = 3
		eye.mesh = eye_mesh
		eye.material_override = mat_eye
		eye.position = Vector3(side * 0.06, 0.035, -0.13)
		fish_root.add_child(eye)

	# 6. Aletas pectorales pares (inclinadas hacia atrás)
	for side in [-1.0, 1.0]:
		var pec = MeshInstance3D.new()
		var pec_mesh = PrismMesh.new()
		pec_mesh.size = Vector3(0.01, 0.06, 0.08)
		pec.mesh = pec_mesh
		pec.material_override = mat_fin
		pec.position = Vector3(side * 0.065, -0.025, -0.06)
		pec.rotation_degrees = Vector3(15.0, side * 28.0, side * 38.0)
		fish_root.add_child(pec)

	# --------------------------------------------------------------------------
	# PARTE TRASERA ARTICULADA (Pedúnculo, Aleta Dorsal, Aleta Anal, Cola)
	# Como pivote independiente para ondular y aletear en el aire
	# --------------------------------------------------------------------------
	var tail_pivot = Node3D.new()
	tail_pivot.name = "TailPivot"
	tail_pivot.position = Vector3(0.0, 0.0, 0.0)
	fish_root.add_child(tail_pivot)

	# 7. Pedúnculo trasero (cilindro que se afina hacia la cola)
	var rear = MeshInstance3D.new()
	var rear_mesh = CylinderMesh.new()
	rear_mesh.top_radius = 0.08
	rear_mesh.bottom_radius = 0.025
	rear_mesh.height = 0.15
	rear_mesh.radial_segments = 7
	rear_mesh.rings = 3
	rear.mesh = rear_mesh
	rear.material_override = mat_back
	rear.scale = Vector3(0.45, 1.0, 1.0)
	rear.position = Vector3(0.0, 0.005, 0.075)
	rear.rotation_degrees.x = 90.0 # Top (ancho) en Z=0, Bottom (fino) en Z=0.15
	tail_pivot.add_child(rear)

	# 8. Aleta dorsal atrasada en el lomo
	var dorsal = MeshInstance3D.new()
	var dorsal_mesh = PrismMesh.new()
	dorsal_mesh.size = Vector3(0.015, 0.11, 0.10)
	dorsal.mesh = dorsal_mesh
	dorsal.material_override = mat_fin
	dorsal.position = Vector3(0.0, 0.10, 0.04)
	dorsal.rotation_degrees.x = -18.0
	tail_pivot.add_child(dorsal)

	# 9. Aleta anal inferior
	var anal = MeshInstance3D.new()
	var anal_mesh = PrismMesh.new()
	anal_mesh.size = Vector3(0.015, 0.06, 0.07)
	anal.mesh = anal_mesh
	anal.material_override = mat_fin
	anal.position = Vector3(0.0, -0.07, 0.07)
	anal.rotation_degrees.x = 18.0
	tail_pivot.add_child(anal)

	# 10. Aleta caudal (cola vertical de piraña bifurcada en V hacia atrás)
	# Lóbulo superior
	var tail_top = MeshInstance3D.new()
	var tail_top_mesh = PrismMesh.new()
	tail_top_mesh.size = Vector3(0.012, 0.11, 0.07)
	tail_top.mesh = tail_top_mesh
	tail_top.material_override = mat_fin
	tail_top.position = Vector3(0.0, 0.045, 0.17)
	tail_top.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	tail_pivot.add_child(tail_top)

	# Lóbulo inferior
	var tail_bot = MeshInstance3D.new()
	var tail_bot_mesh = PrismMesh.new()
	tail_bot_mesh.size = Vector3(0.012, 0.11, 0.07)
	tail_bot.mesh = tail_bot_mesh
	tail_bot.material_override = mat_fin
	tail_bot.position = Vector3(0.0, -0.045, 0.17)
	tail_bot.rotation_degrees = Vector3(25.0, 0.0, 180.0)
	tail_pivot.add_child(tail_bot)

	# --------------------------------------------------------------------------
	# TAMAÑO PEQUEÑO ESTÉTICO: ~20 a 22 cm de largo en la escala del juego
	# --------------------------------------------------------------------------
	var scale_factor = 0.40 * randf_range(0.90, 1.10)
	fish_root.scale = Vector3(scale_factor, scale_factor, scale_factor)

	return fish_root
