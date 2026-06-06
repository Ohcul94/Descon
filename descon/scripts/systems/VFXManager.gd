extends Node

# VFXSystem.gd (Architecture v164.12 - RE-SAVED)
# Manager central de efectos visuales (Explosiones, Nova, Rifts)

func _ready():
	add_to_group("vfx_system")
	print("[VFX] Sistema restaurado para compatibilidad de escenas.")

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
