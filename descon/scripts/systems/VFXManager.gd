extends Node

# VFXSystem.gd (Architecture v164.12 - RE-SAVED)
# Manager central de efectos visuales (Explosiones, Nova, Rifts)

var _warmup_cache: Dictionary = {}

var static_textures_to_cache = [
  "res://assets/Esferas/EsferaAmarilla1.png",
  "res://assets/Esferas/EsferaAzul1.png",
  "res://assets/Esferas/EsferaRoja1.png",
  "res://assets/Esferas/EsferaVerde1.png",
  "res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla_EsferaAmarilla_basecolor.jpg",
  "res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla_EsferaAmarilla_normal.jpg",
  "res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla_EsferaAmarilla_rm.jpg",
  "res://assets/Esferas/3D/EsferaAzul/EsferaAzul_EsferaAzul_basecolor.jpg",
  "res://assets/Esferas/3D/EsferaRoja/EsferaRoja_EsferaRoja_basecolor.jpg",
  "res://assets/Esferas/3D/EsferaVerde/EsferaVerde_EsferaVerde_basecolor.jpg",
  "res://assets/Skills/Marco Contenedor.png",
  "res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png",
  "res://assets/Skills/Iconos/Ataque/Provocacion/Provocacion.png",
  "res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png",
  "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
  "res://assets/Skills/Iconos/Cura/Baliza Curativa/Baliza Curativa.png",
  "res://assets/Skills/Iconos/Cura/Regeneracion Alfa/Regeneracion Alfa.png",
  "res://assets/Skills/Iconos/Cura/Vinculo Vital/Vinculo Vital.png",
  "res://assets/Skills/Iconos/Defensa/Barrera de Viento/Barrera de Viento.png",
  "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
  "res://assets/Skills/Iconos/Defensa/Camino de Hielo/Camino de Hielo.png",
  "res://assets/Skills/Iconos/Defensa/Escudo Celular/Escudo Celular.png",
  "res://assets/Skills/Iconos/Utilidad/Destello/Destello.png",
  "res://assets/Skills/Iconos/Utilidad/Invisibilidad/Invisibilidad.png",
  "res://assets/Skills/Iconos/Utilidad/Invulnerabilidad/Invulnerabilidad.png",
  "res://assets/Skills/Iconos/Utilidad/Resurrecion/Resurrecion.png",
  "res://assets/Skills/Iconos/Utilidad/SuperVelocidad/SuperVelocidad.png",
  "res://assets/Talentos/ContenedorGrande.png",
  "res://assets/UI/hand_interact.jpg",
  "res://assets/UI/Chat/Chat(Transp).png",
  "res://assets/UI/Chat/Chat.png",
  "res://assets/UI/Equipo/Equipo(Transp).png",
  "res://assets/UI/Equipo/Equipo.png",
  "res://assets/UI/Habilidades/Habilidades(Transp).png",
  "res://assets/UI/Habilidades/Habilidades.png",
  "res://assets/UI/Minimapa/Minimapa(Transp).png",
  "res://assets/UI/Minimapa/Minimapa.png",
  "res://assets/UI/Perfil/Perfil(Transp).png",
  "res://assets/UI/Perfil/Perfil.png",
  "res://assets/Armas/Arma1/Arma1.png",
  "res://assets/Armas/Arma2/Arma2.png",
  "res://assets/Armas/Arma3/Arma3.png",
  "res://assets/Armas/Arma4/Arma4.png",
  "res://assets/Armas/Arma5/Arma5.png",
  "res://assets/Armas/Arma6/Arma6.png",
  "res://assets/Escudos/Escudo1/Escudo1.png",
  "res://assets/Escudos/Escudo2/Escudo2.png",
  "res://assets/Escudos/Escudo3/Escudo3.png",
  "res://assets/Escudos/Escudo4/Escudo4.png",
  "res://assets/Escudos/Escudo5/Escudo5.png",
  "res://assets/Escudos/Escudo6/Escudo6.png",
  "res://assets/Motores/Motor1/Motor1.png",
  "res://assets/Motores/Motor2/Motor2.png",
  "res://assets/Motores/Motor3/Motor3.png",
  "res://assets/Municiones/Lasers/Laser1/Laser1.png",
  "res://assets/Municiones/Lasers/Laser2/Laser2-1.png",
  "res://assets/Municiones/Lasers/Laser2/Laser2.png",
  "res://assets/Municiones/Minas/Mina1/Mina1.png",
  "res://assets/Municiones/Minas/Mina2/Mina2-1.png",
  "res://assets/Municiones/Minas/Mina2/Mina2.png",
  "res://assets/Municiones/Minas/Mina3/Mina3-1.png",
  "res://assets/Municiones/Minas/Mina3/Mina3.png",
  "res://assets/Municiones/Misiles/Misil1/Misil1.png",
  "res://assets/Municiones/Misiles/Misil2/Misil2-1.png",
  "res://assets/Municiones/Misiles/Misil2/Misil2.png",
  "res://assets/Municiones/Misiles/Misil3/Misil3-1.png",
  "res://assets/Municiones/Misiles/Misil3/Misil3.png"
]

func _ready():
	add_to_group("vfx_system")
	print("[VFX] Sistema restaurado para compatibilidad de escenas.")
	
	# Iniciar el precalentamiento y caché al arrancar
	_run_shader_warmup()

func _run_shader_warmup():
	# Esperamos un frame para asegurar que el root se cargó
	await get_tree().process_frame
	
	# 1. CREACIÓN DE PANTALLA DE CARGA AAA
	var canvas = CanvasLayer.new()
	canvas.layer = 9999 # Encima de todo
	get_tree().root.add_child(canvas)
	
	var bg = ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05, 1.0) # Fondo oscuro premium
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "DESCON"
	title.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.2, 0.95, 0.4, 1.0)) # Verde HUD
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	
	var spacing = Control.new()
	spacing.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacing)
	
	var status = Label.new()
	status.text = "Optimizando texturas de interfaz..."
	status.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9, 0.75))
	status.add_theme_font_size_override("font_size", 16)
	vbox.add_child(status)
	
	var spacing2 = Control.new()
	spacing2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacing2)
	
	var progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(320, 18)
	progress.max_value = 100.0
	progress.value = 0.0
	vbox.add_child(progress)
	
	await get_tree().process_frame
	
	# 2. CARGAR TEXTURAS DE LA LISTA ESTÁTICA (Resuelve el lag de Android/Exportados)
	var total_textures = static_textures_to_cache.size()
	for i in range(total_textures):
		var tex_path = static_textures_to_cache[i]
		if ResourceLoader.exists(tex_path):
			var tex = load(tex_path)
			_warmup_cache[tex_path] = tex
		
		# Actualizar barra de progreso para texturas (0% a 50%)
		progress.value = (float(i) / total_textures) * 50.0
		if i % 8 == 0:
			await get_tree().process_frame
			
	status.text = "Compilando shaders gráficos (GPU)..."
	await get_tree().process_frame

	# 3. PRECALENTAMIENTO DE SHADERS EN VIEWPORT PRINCIPAL (Forzar compilación Vulkan/GLES en móvil)
	var scenes_to_compile = [
		"res://VFX/scenes/VFX_Shield_green.tscn",
		"res://VFX/scenes/VFX_Shield_green_plane.tscn",
		"res://VFX/scenes/VFX_Cube_projectile.tscn",
		"res://VFX/scenes/VFX_Hadouken.tscn",
		"res://VFX/scenes/VFX_Anticipation_wave_digital.tscn",
		"res://VFX/scenes/VFX_Anticipation_hadouken.tscn",
		"res://VFX/scenes/VFX_Hit_cyber.tscn",
		"res://VFX/scenes/VFX_Hit_hadouken.tscn",
		"res://scenes/entities/Enemy.tscn",
		"res://scenes/entities/Ship.tscn",
		"res://assets/Contenedores/Baules/3D/Baul1/Baul1.glb"
	]
	
	# Creamos un nodo 3D y cámara temporal en la escena principal para forzar render
	var temp_node3d = Node3D.new()
	get_tree().root.add_child(temp_node3d)
	
	var temp_cam = Camera3D.new()
	temp_cam.position = Vector3(999.0, 999.0, 1004.0) # Fuera del mapa jugable
	temp_node3d.add_child(temp_cam)
	temp_cam.look_at(Vector3(999.0, 999.0, 999.0))
	
	var total_scenes = scenes_to_compile.size()
	for i in range(total_scenes):
		var scene_path = scenes_to_compile[i]
		status.text = "Preparando efectos: " + scene_path.get_file()
		
		if ResourceLoader.exists(scene_path):
			var scene = load(scene_path)
			if scene:
				var instance = scene.instantiate()
				if instance is Node3D:
					temp_node3d.add_child(instance)
					instance.position = Vector3(999.0, 999.0, 999.0) # Justo frente a la cámara temp
				elif instance is Node2D:
					# Para escenas 2D, las añadimos directo a la raíz
					get_tree().root.add_child(instance)
					instance.position = Vector2(-9999.0, -9999.0) # Off-screen
				else:
					get_tree().root.add_child(instance)
				
				# Esperar 2 frames de renderizado (Requerido por compiladores de GPU móviles)
				await get_tree().physics_frame
				await get_tree().process_frame
				
				instance.queue_free()
				
		# Actualizar barra de progreso para shaders (50% a 100%)
		progress.value = 50.0 + ((float(i) / total_scenes) * 50.0)
		await get_tree().process_frame

	# 4. LIMPIEZA DE ELEMENTOS TEMPORALES Y TRANSICIÓN SUAVE
	temp_node3d.queue_free()
	
	status.text = "¡Listo!"
	progress.value = 100.0
	
	# Animación de salida (Fade out)
	var tween = create_tween()
	tween.tween_property(bg, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(center, "modulate:a", 0.0, 0.3)
	await tween.finished
	
	canvas.queue_free()
	print("[VFX-WarmUp] Precalentamiento de Shaders y Caché finalizado con éxito. Carga completada.")

func spawn_explosion(pos: Vector2, p_scale: float = 1.0): # Renombrado scale a p_scale
	# Efecto visual de explosión por defecto
	print("[VFX] Generando Explosión en ", pos, " (Escala: ", p_scale, ")")
	_create_nova_effect(pos.x, pos.y, p_scale * 100.0)

# v3.1: Generador de efectos rápidos (Teletransporte, impactos, etc)
func create_simple_vfx(pos: Vector2, type: String = "warp_exit", radius: float = 50.0):
	match type:
		"warp_exit", "warp_entry":
			_create_nova_effect(pos.x, pos.y, radius)
		_:
			_create_nova_effect(pos.x, pos.y, radius)

func handle_boss_effect(data: Dictionary):
	var type = data.get("type", "")
	var p_x = data.get("x", 0.0)
	var p_y = data.get("y", 0.0)
	
	match type:
		"vacuum":
			_create_nova_effect(p_x, p_y, data.get("radius", 1200))
		"rift":
			_create_void_rift_effect(p_x, p_y, data.get("duration", 4000) / 1000.0)
		"leech":
			var from_pos = Vector2(p_x, p_y)
			var to_id = str(data.get("to", ""))
			var to_node = null
			
			var entities = get_tree().get_nodes_in_group("entities")
			for entity in entities:
				if is_instance_valid(entity) and entity.get("entity_id") == to_id:
					to_node = entity
					break
			if not to_node:
				var pl = get_tree().get_first_node_in_group("player")
				if is_instance_valid(pl) and pl.get("entity_id") == to_id:
					to_node = pl
			
			var to_pos = to_node.global_position if is_instance_valid(to_node) else from_pos
			_create_leech_ray_vfx(from_pos, to_pos, to_node)

func _create_leech_ray_vfx(from_pos: Vector2, to_pos: Vector2, target_node: Node2D):
	# Rayo curativo verde de pilares (39ff14 -> Verde Eléctrico)
	var rayo = Line2D.new()
	rayo.width = 4.0
	rayo.default_color = Color("#39ff14")
	rayo.points = PackedVector2Array([from_pos, to_pos])
	
	var world = get_tree().get_first_node_in_group("world")
	if world: world.add_child(rayo)
	else: get_tree().root.add_child(rayo)
	
	var duration = 0.8
	var tween = create_tween().set_parallel(true)
	
	# Desvanecer ancho y color
	tween.tween_property(rayo, "width", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(rayo, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	if is_instance_valid(target_node):
		var steps = 15
		for i in range(steps):
			var t = (i / float(steps)) * duration
			tween.tween_callback(func():
				if is_instance_valid(rayo) and is_instance_valid(target_node):
					rayo.points = PackedVector2Array([from_pos, target_node.global_position])
			).set_delay(t)
			
	tween.chain().tween_callback(rayo.queue_free)

func _create_nova_effect(p_x: float, p_y: float, radius: float):
	# Anillo de energía expansiva (bc13fe -> Violeta Neón)
	var ring = Line2D.new()
	ring.width = 6.0
	ring.default_color = Color("#bc13fe")
	ring.closed = true
	
	var pts = PackedVector2Array()
	var segments = 32
	for i in range(segments + 1):
		var phi = (i * 2.0 * PI) / segments
		pts.append(Vector2(cos(phi), sin(phi)) * 10.0)
	ring.points = pts
	
	ring.global_position = Vector2(p_x, p_y)
	
	# v240.71: Buscar el nodo World para que el efecto no se desplace con la camara
	var world = get_tree().get_first_node_in_group("world")
	if world: world.add_child(ring)
	else: get_tree().root.add_child(ring)
	
	var tween = create_tween().set_parallel(true)
	var duration = 1.5
	var final_scale = radius / 10.0
	
	tween.tween_property(ring, "scale", Vector2(final_scale, final_scale), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)
	
	_apply_nova_push(Vector2(p_x, p_y), radius)

func _create_void_rift_effect(p_x: float, p_y: float, duration: float):
	var rift = Polygon2D.new()
	var pts = PackedVector2Array()
	var segments = 16
	for i in range(segments):
		var phi = (i * 2.0 * PI) / segments
		pts.append(Vector2(cos(phi), sin(phi)) * 80.0)
	rift.polygon = pts
	rift.color = Color("#bc13fe")
	rift.modulate.a = 0.2
	
	rift.global_position = Vector2(p_x, p_y)
	var world = get_tree().get_first_node_in_group("world")
	if world: world.add_child(rift)
	else: get_tree().root.add_child(rift)
	
	var tween = create_tween().set_loops()
	tween.bind_node(rift)
	tween.tween_property(rift, "scale", Vector2(1.2, 1.2), 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(rift, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE)
	
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(rift):
		rift.queue_free()

func _apply_nova_push(pos: Vector2, radius: float):
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p):
		var dist = p.global_position.distance_to(pos)
		if dist < radius:
			var direction = (p.global_position - pos).normalized()
			if "velocity" in p:
				p.velocity += direction * 800.0
