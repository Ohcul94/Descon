extends Node2D

# Configuración y Estado del VFX de la Baliza
var radius: float = 200.0
var hover_time: float = 0.0
var pulses: Array = []
var sparks: Array = []
var max_sparks: int = 15

# Variables de Estructura de la Boya
var base_color := Color(0.2, 0.9, 0.4, 0.95)   # Verde cian tecnológico
var shield_color := Color(0.1, 0.7, 0.9, 0.4)  # Contorno azul/cian
var glow_intensity: float = 1.0

class HealingPulse:
	var radius: float = 0.0
	var max_radius: float = 200.0
	var alpha: float = 1.0

class Spark:
	var pos: Vector2
	var vel: Vector2
	var lifetime: float = 0.0
	var max_lifetime: float = 1.2
	var size: float = 2.0
	var alpha: float = 1.0

func _ready():
	# Activar dibujo constante y generación de partículas
	set_process(true)
	
	# Efecto de spawn
	scale = Vector2.ZERO
	var spawn_tw = create_tween().set_parallel(true)
	spawn_tw.tween_property(self, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	spawn_tw.tween_property(self, "modulate:a", 1.0, 0.4)

func _process(delta: float):
	hover_time += delta
	glow_intensity = 0.8 + 0.25 * sin(hover_time * 5.0)
	
	# 1. Actualizar Partículas (Sparks) de Sanación
	_update_sparks(delta)
	
	# 2. Actualizar las ondas expansivas de curación (pulses)
	var active_pulses = []
	for p in pulses:
		if p.alpha > 0.005:
			active_pulses.append(p)
	pulses = active_pulses
	
	queue_redraw()

func pulse(max_r: float):
	radius = max_r
	var p = HealingPulse.new()
	p.max_radius = max_r
	p.radius = 0.0
	p.alpha = 1.0
	pulses.append(p)
	
	# Animar la onda de curación de forma ultra fluida
	var tw = create_tween().set_parallel(true)
	tw.tween_property(p, "radius", max_r, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "alpha", 0.0, 0.80).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

func _update_sparks(delta: float):
	# Limpieza y actualización de físicas
	var active_sparks = []
	for s in sparks:
		s.lifetime += delta
		if s.lifetime < s.max_lifetime:
			s.pos += s.vel * delta
			s.vel.x += sin(hover_time * 10.0 + s.pos.y) * 20.0 * delta # Movimiento sinusoidal ondulante
			s.alpha = 1.0 - (s.lifetime / s.max_lifetime)
			active_sparks.append(s)
	sparks = active_sparks
	
	# Spawnear chispas si hay cupo
	if sparks.size() < max_sparks and randf() < 0.25:
		var s = Spark.new()
		s.pos = Vector2(randf_range(-15, 15), randf_range(-5, -30))
		s.vel = Vector2(randf_range(-25, 25), randf_range(-60, -90)) # Fluyen hacia arriba
		s.max_lifetime = randf_range(0.8, 1.4)
		s.size = randf_range(2.0, 4.0)
		s.alpha = 1.0
		sparks.append(s)

func _draw():
	var hover_offset = sin(hover_time * 3.5) * 8.0  # Animación de flotar (2.5D) Y-offset
	
	# 1. Dibujar Sombras en el Suelo (Sin offset de flotación)
	var shadow_alpha = 0.22 - (hover_offset * 0.01)
	draw_ellipse_glow(Vector2.ZERO, Vector2(24, 8), Color(0, 0, 0, shadow_alpha), true)
	draw_ellipse_glow(Vector2.ZERO, Vector2(40, 14), Color(0, 0.2, 0, 0.1), false)
	
	# 2. Anillo de Proyección Tecnológica en el Suelo
	draw_arc(Vector2.ZERO, 30.0, 0, TAU, 32, Color(base_color.r, base_color.g, base_color.b, 0.2 * glow_intensity), 1.5)
	
	# 3. Dibujar Sparks (Chispas flotantes) con el offset respectivo
	for s in sparks:
		var p_color = Color(0.3, 1.0, 0.5, s.alpha * 0.8)
		draw_circle(s.pos + Vector2(0, hover_offset), s.size, p_color)
		# Glow sutil alrededor de la chispa
		draw_circle(s.pos + Vector2(0, hover_offset), s.size * 2.0, Color(0.3, 1.0, 0.5, s.alpha * 0.25))

	# 4. Dibujar Ondas Circulares Expansivas (Pulses)
	for p in pulses:
		# Onda principal
		draw_arc(Vector2.ZERO, p.radius, 0, TAU, 72, Color(base_color.r, base_color.g, base_color.b, p.alpha * 0.65), 3.0)
		# Halo interior difuso de la onda
		draw_arc(Vector2.ZERO, p.radius - 8.0, 0, TAU, 72, Color(base_color.r, base_color.g, base_color.b, p.alpha * 0.22), 6.0)
		# Relleno del pulso expansivo
		draw_circle(Vector2.ZERO, p.radius, Color(base_color.r, base_color.g, base_color.b, p.alpha * 0.05))

	# 5. Estructura de la Boya/Baliza (Con offset de flotación)
	var beacon_center = Vector2(0, -32 + hover_offset)
	
	# Conexión/haz de energía interno vertical
	draw_line(Vector2(0, 0), beacon_center, Color(base_color.r, base_color.g, base_color.b, 0.35 * glow_intensity), 2.5)
	draw_line(Vector2(0, 0), beacon_center, Color(1, 1, 1, 0.15), 1.0)
	
	# Patas de Soporte Mecánicas (Forma piramidal)
	var left_foot = Vector2(-16, 0)
	var right_foot = Vector2(16, 0)
	draw_line(left_foot, beacon_center + Vector2(-6, 8), Color(0.18, 0.22, 0.25, 0.95), 4.5)
	draw_line(right_foot, beacon_center + Vector2(6, 8), Color(0.18, 0.22, 0.25, 0.95), 4.5)
	
	# Cuerpo Central de la Boya
	# Corona/Anillo holográfico flotante horizontal
	draw_ellipse_glow(beacon_center, Vector2(14, 5), Color(base_color.r, base_color.g, base_color.b, 0.45 * glow_intensity), false)
	
	# Núcleo Metálico del Dispositivo
	draw_circle(beacon_center, 9.0, Color(0.12, 0.15, 0.18, 1.0))
	draw_circle(beacon_center, 7.0, Color(0.22, 0.26, 0.30, 1.0))
	
	# Orbe/Núcleo de Energía Curativa (Brillante y Pulsante)
	var core_color = Color(0.3, 1.0, 0.4, 0.9)
	draw_circle(beacon_center, 4.5 * glow_intensity, core_color)
	draw_circle(beacon_center, 8.0 * glow_intensity, Color(0.3, 1.0, 0.4, 0.3))
	draw_circle(beacon_center, 14.0 * glow_intensity, Color(0.3, 1.0, 0.4, 0.08))

# Función helper para dibujar elipses difuminadas (Glow)
func draw_ellipse_glow(center: Vector2, axes: Vector2, color: Color, filled: bool):
	var points = PackedVector2Array()
	var num_pts = 32
	for i in range(num_pts + 1):
		var angle = (float(i) / num_pts) * TAU
		points.append(center + Vector2(cos(angle) * axes.x, sin(angle) * axes.y))
	
	if filled:
		draw_colored_polygon(points, color)
	else:
		draw_polyline(points, color, 2.5)
