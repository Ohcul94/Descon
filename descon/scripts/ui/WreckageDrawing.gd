extends Node2D

# WreckageDrawing.gd (v1.0)
# Dibuja un marcador visual estático de restos espaciales extremadamente liviano.

func _draw():
	# Círculo discontinuo de restos metálicos (Gris translúcido)
	var color = Color(0.5, 0.5, 0.5, 0.45)
	
	# Cruz interna que indica naufragio / destrucción
	draw_line(Vector2(-12, -12), Vector2(12, 12), color, 2.5)
	draw_line(Vector2(12, -12), Vector2(-12, 12), color, 2.5)
	
	# Líneas decorativas circulares simulando escombros
	draw_arc(Vector2.ZERO, 20.0, 0, TAU, 16, color, 1.5)
	draw_arc(Vector2.ZERO, 30.0, 0, PI/2, 8, color, 1.0)
	draw_arc(Vector2.ZERO, 30.0, PI, 3*PI/2, 8, color, 1.0)
