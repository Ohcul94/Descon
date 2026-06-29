extends Node

# VFXSystem.gd (Architecture v164.12 - RE-SAVED)
# Manager central de efectos visuales (Explosiones, Nova, Rifts)

var _warmup_cache: Dictionary = {}

func _ready():
	add_to_group("vfx_system")
	print("[VFX] Sistema restaurado para compatibilidad de escenas.")
	
	# Iniciar el proceso de Warm-up de Shaders y Caché de Texturas en segundo plano
	_run_shader_warmup()

func _run_shader_warmup():
	# Retrasar un frame inicial para asegurar que el motor arrancó por completo
	await get_tree().process_frame
	print("[VFX-WarmUp] Iniciando precalentamiento de Shaders y Caché de Texturas (Warm-up)...")
	
	# 1. Caché de Texturas (Iconos de UI, Talentos, Skills, Esferas)
	var texture_dirs = [
		"res://assets/Esferas",
		"res://assets/Skills",
		"res://assets/Talentos",
		"res://assets/UI"
	]
	
	for dir_path in texture_dirs:
		_cache_textures_in_dir(dir_path)
		
	# 2. Precalentamiento de Shaders 3D (VFX, Escudos, Cofres y Modelos)
	var scenes_to_compile = [
		# Escudos
		"res://VFX/scenes/VFX_Shield_green.tscn",
		"res://VFX/scenes/VFX_Shield_green_plane.tscn",
		
		# Proyectiles 3D (Hadouken, Cube, Anticipaciones, Hits)
		"res://VFX/scenes/VFX_Cube_projectile.tscn",
		"res://VFX/scenes/VFX_Hadouken.tscn",
		"res://VFX/scenes/VFX_Anticipation_wave_digital.tscn",
		"res://VFX/scenes/VFX_Anticipation_hadouken.tscn",
		"res://VFX/scenes/VFX_Hit_cyber.tscn",
		"res://VFX/scenes/VFX_Hit_hadouken.tscn",
		
		# Modelos y naves
		"res://scenes/entities/Enemy.tscn",
		"res://scenes/entities/Ship.tscn",
		"res://assets/Contenedores/Baules/3D/Baul1/Baul1.glb"
	]
	
	# Crear un Viewport oculto para renderizar los shaders por un frame
	var wp_vp = SubViewport.new()
	wp_vp.size = Vector2i(128, 128)
	wp_vp.transparent_bg = true
	wp_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(wp_vp)
	
	var wp_node3d = Node3D.new()
	wp_vp.add_child(wp_node3d)
	
	var wp_cam = Camera3D.new()
	wp_cam.position = Vector3(0, 0, 5)
	wp_node3d.add_child(wp_cam)
	wp_cam.look_at(Vector3.ZERO) # Ya está dentro del tree, así que no falla
	
	# Procesar cada escena secuencialmente
	for scene_path in scenes_to_compile:
		if ResourceLoader.exists(scene_path):
			var scene = load(scene_path)
			if scene:
				var instance = scene.instantiate()
				if instance is Node3D:
					wp_node3d.add_child(instance)
					instance.position = Vector3.ZERO
				elif instance is Node2D:
					wp_vp.add_child(instance)
					instance.position = Vector2.ZERO
				else:
					wp_vp.add_child(instance)
				
				# Esperar un frame de físicas y renderizado para forzar la compilación del shader en la GPU
				await get_tree().physics_frame
				await get_tree().process_frame
				
				instance.queue_free()
				
	# Eliminar el viewport de calentamiento
	wp_vp.queue_free()
	print("[VFX-WarmUp] Precalentamiento de Shaders y Caché finalizado con éxito. Juego optimizado para gameplay AAA.")

func _cache_textures_in_dir(path: String):
	if not DirAccess.dir_exists_absolute(path): return
	
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var lower_name = file_name.to_lower()
				if lower_name.ends_with(".png") or lower_name.ends_with(".jpg") or lower_name.ends_with(".jpeg") or lower_name.ends_with(".bmp"):
					# Ignorar los archivos .import y cargar la textura real
					var full_path = path + "/" + file_name
					if ResourceLoader.exists(full_path):
						var tex = load(full_path)
						_warmup_cache[full_path] = tex
			file_name = dir.get_next()
		dir.list_dir_end()

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
