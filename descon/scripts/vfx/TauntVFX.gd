extends Node2D

var caster_id: String = ""
var affected_enemy_ids: Array = []
var radius: float = 220.0
var duration_ms: float = 4000.0

var wave_radius: float = 0.0
var wave_alpha: float = 1.0
var elapsed_time: float = 0.0
var max_life: float = 0.8 # duración total del efecto visual en segundos

var caster_node: Node2D = null
var enemy_nodes: Array = []

func _ready():
	# Intentar buscar el caster
	var world = get_tree().current_scene
	if is_instance_valid(world):
		var em = world.get("entity_manager")
		if is_instance_valid(em):
			# Buscar caster
			if is_instance_valid(world.get("local_player")) and world.local_player.entity_id == caster_id:
				caster_node = world.local_player
			elif em.get("remote_players") and em.remote_players.has(caster_id):
				caster_node = em.remote_players[caster_id]
			
			# Buscar enemigos y mostrar burbuja de enojo
			for eid in affected_enemy_ids:
				if em.get("enemies") and em.enemies.has(eid):
					var enemy = em.enemies[eid]
					if is_instance_valid(enemy):
						enemy_nodes.append(enemy)
						if enemy.has_method("show_bubble"):
							enemy.show_bubble("😡") # Emoticón de enojo

	# Tweens para la onda expansiva
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "wave_radius", radius, 0.45).set_trans(Tween.TRANS_OUT).set_ease(Tween.EASE_CUBIC)
	tween.tween_property(self, "wave_alpha", 0.0, 0.65).set_trans(Tween.TRANS_IN).set_ease(Tween.EASE_QUAD)
	
	# Auto destrucción tras completarse el ciclo visual
	get_tree().create_timer(max_life).timeout.connect(queue_free)

func _process(delta: float):
	elapsed_time += delta
	queue_redraw()

func _draw():
	# 1. Dibujar onda expansiva de taunt (rojo brillante con núcleo)
	if wave_alpha > 0.01:
		# Anillo exterior
		draw_arc(Vector2.ZERO, wave_radius, 0.0, TAU, 64, Color(1.0, 0.15, 0.1, wave_alpha * 0.8), 6.0 - 4.0 * (wave_radius / radius))
		# Relleno desvanecido
		draw_circle(Vector2.ZERO, wave_radius, Color(1.0, 0.1, 0.1, wave_alpha * 0.15))
		
		# Ondas de pulso secundarias concéntricas
		var ring2 = wave_radius * 0.6
		if ring2 < radius:
			draw_arc(Vector2.ZERO, ring2, 0.0, TAU, 48, Color(1.0, 0.3, 0.1, wave_alpha * 0.4), 2.0)
	
	# 2. Dibujar hilos / cadenas de energía entre el epicentro y los enemigos
	var fade_factor = clamp(1.0 - (elapsed_time / max_life), 0.0, 1.0)
	if fade_factor > 0.0:
		for enemy in enemy_nodes:
			if is_instance_valid(enemy):
				# Posición del enemigo relativa a este VFX
				var p0 = Vector2.ZERO # Centro del taunt
				var p1 = to_local(enemy.global_position)
				
				# Dibujar filamentos vibrantes de plasma rojo
				_draw_electric_line(p0, p1, Color(1.0, 0.2, 0.1, fade_factor * 0.9), 3.0)
				_draw_electric_line(p0, p1, Color(1.0, 0.7, 0.2, fade_factor * 1.0), 1.0) # Centro incandescente amarillo
				
				# Efecto de pulso fluyendo hacia el centro
				var segments = 12
				var time_offset = elapsed_time * 6.0
				var flow_pos = fmod(time_offset, 1.0)
				var pulse_pt = p0.lerp(p1, 1.0 - flow_pos)
				draw_circle(pulse_pt, 5.0, Color(1.0, 0.9, 0.5, fade_factor))

func _draw_electric_line(from: Vector2, to: Vector2, color: Color, width: float):
	var points = PackedVector2Array()
	var steps = 10
	var diff = to - from
	var dir = diff.normalized()
	var normal = Vector2(-dir.y, dir.x)
	
	points.append(from)
	
	for i in range(1, steps):
		var t = float(i) / steps
		var pt = from.lerp(to, t)
		
		# Modulador de ruido eléctrico usando senos y la hora del juego
		var noise = sin(t * PI * 3.0 + elapsed_time * 30.0) * 12.0 * (1.0 - t) * t
		pt += normal * noise
		points.append(pt)
		
	points.append(to)
	
	for i in range(points.size() - 1):
		draw_line(points[i], points[i+1], color, width)
