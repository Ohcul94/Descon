extends Control
class_name HUDFrame

# HUDFrame.gd - Sistema de Marcos Sci-Fi Dinámicos (v1.1)
# Recrea fielmente el diseño: Marco exterior redondeado + Brillo rojo biselado.

@export var frame_color: Color = Color(0.08, 0.08, 0.1, 0.95)
@export var glow_color: Color = Color(1.0, 0.2, 0.2, 0.8)
@export var bg_color: Color = Color(0, 0, 0, 0.45)
@export var border_thickness: float = 10.0
@export var corner_radius: float = 18.0
@export var chamfer_size: float = 16.0 

func _ready():
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	
	# Asegurar que el padre no nos tape
	if get_parent() is Control:
		get_parent().resized.connect(queue_redraw)

func _draw():
	var r = Rect2(Vector2.ZERO, size)
	
	# 1. Fondo principal
	draw_rect(r, bg_color, true)
	
	# 2. Marco Exterior Oscuro (Redondeado)
	_draw_rounded_frame(r, frame_color, border_thickness)
	
	# 3. Línea de Brillo Roja (Biselada / Chamfered)
	_draw_chamfered_glow(r, glow_color)
	
	# 4. Remaches Estéticos
	_draw_rivets(r, frame_color.lightened(0.15))

func _draw_rounded_frame(rect: Rect2, color: Color, thickness: float):
	var points = _get_rounded_points(rect, corner_radius)
	# Dibujar el contorno grueso
	draw_polyline(points, color, thickness, true)
	# Dibujar un pequeño bisel de luz en el borde superior para efecto 3D metálico
	var top_line = PackedVector2Array([points[0], points[1], points[2]])
	draw_polyline(top_line, color.lightened(0.1), 1.0, true)

func _draw_chamfered_glow(rect: Rect2, color: Color):
	var inset = border_thickness + 2.0
	var inner_rect = rect.grow(-inset)
	var c = chamfer_size
	
	var p = PackedVector2Array([
		Vector2(inner_rect.position.x + c, inner_rect.position.y),
		Vector2(inner_rect.end.x - c, inner_rect.position.y),
		Vector2(inner_rect.end.x, inner_rect.position.y + c),
		Vector2(inner_rect.end.x, inner_rect.end.y - c),
		Vector2(inner_rect.end.x - c, inner_rect.end.y),
		Vector2(inner_rect.position.x + c, inner_rect.end.y),
		Vector2(inner_rect.position.x, inner_rect.end.y - c),
		Vector2(inner_rect.position.x, inner_rect.position.y + c),
		Vector2(inner_rect.position.x + c, inner_rect.position.y)
	])
	
	# Efecto de resplandor (Glow) usando múltiples líneas con alpha decreciente
	draw_polyline(p, Color(color.r, color.g, color.b, 0.15), 4.0, true)
	draw_polyline(p, Color(color.r, color.g, color.b, 0.3), 2.5, true)
	draw_polyline(p, color, 1.2, true)

func _draw_rivets(rect: Rect2, color: Color):
	var offset = corner_radius * 0.6
	var rivet_pos = [
		Vector2(offset, offset),
		Vector2(rect.size.x - offset, offset),
		Vector2(rect.size.x - offset, rect.size.y - offset),
		Vector2(offset, rect.size.y - offset)
	]
	for pos in rivet_pos:
		# Remache con sombreado simple
		draw_circle(pos, 2.5, color.darkened(0.5))
		draw_circle(pos, 1.8, color)

func _get_rounded_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var steps = 8
	# TL, TR, BR, BL
	var centers = [
		rect.position + Vector2(radius, radius),
		Vector2(rect.end.x - radius, rect.position.y + radius),
		rect.end - Vector2(radius, radius),
		Vector2(rect.position.x + radius, rect.end.y - radius)
	]
	var angles = [PI, PI*1.5, 0.0, PI/2.0]
	
	for j in range(4):
		for i in range(steps + 1):
			var a = angles[j] + (PI/2.0) * (float(i)/steps)
			points.append(centers[j] + Vector2(cos(a), sin(a)) * radius)
	
	points.append(points[0])
	return points
