extends Control
class_name HUDFrame

# HUDFrame.gd - Sistema de Contenedores Visuales AAA (Aerospace Tactical Glass)
# Diseñado para MMO Espacial 2.5D: Mantiene nitidez procedural sub-pixel en cualquier
# resolución, escala o tamaño dinámico, y responde 100% al Configurador de Layout.

enum Variant { PANEL, RADAR, SLOT, MODAL }

@export var variant: String = "panel" # "panel", "radar", "slot", "modal"
@export var title: String = "" # Título táctico opcional en cabecera
@export var accent_color: Color = Color(0.0, 0.82, 0.96, 0.85) # Cian Ionizado por defecto
@export var bg_color: Color = Color(0.012, 0.024, 0.038, 1.0) # Cristal de Obsidiana Sólido (100% por defecto)
@export var frame_base_color: Color = Color(0.09, 0.16, 0.24, 0.95) # Titanio/Grafito
@export var chamfer_size: float = 12.0
@export var show_glow: bool = true
@export var show_brackets: bool = true
@export var show_header_plate: bool = true
@export var show_telemetry: bool = true
@export var show_rivets: bool = true

func _ready():
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	
	if get_parent() is Control:
		get_parent().resized.connect(queue_redraw)

func _draw():
	if size.x <= 4 or size.y <= 4:
		return
		
	var r = Rect2(Vector2.ZERO, size)
	
	match variant:
		"slot":
			_draw_slot(r)
		"radar":
			_draw_radar(r)
		"modal":
			_draw_modal_frame(r)
		_:
			_draw_panel(r)

# ==============================================================================
# 1. VARIANTE PANEL: Contenedores HUD (Chat, Métricas, Información, Equipo)
# ==============================================================================
func _draw_panel(r: Rect2):
	var c = min(chamfer_size, min(r.size.x, r.size.y) * 0.25)
	var pts = _get_chamfered_points(r, c)
	
	# 1. Fondo de Cristal de Obsidiana (100% sólido por defecto)
	draw_colored_polygon(pts, bg_color)
	
	# 2. Placa de Cabecera Aeroespacial Integrada (Polígono estrictamente convexo de 6 vértices)
	if show_header_plate and r.size.y > 45:
		var header_h = min(22.0, r.size.y * 0.2)
		var h_pts = PackedVector2Array([
			Vector2(r.position.x + c, r.position.y),
			Vector2(r.end.x - c, r.position.y),
			Vector2(r.end.x, r.position.y + c),
			Vector2(r.end.x, r.position.y + header_h),
			Vector2(r.position.x, r.position.y + header_h),
			Vector2(r.position.x, r.position.y + c)
		])
		draw_colored_polygon(h_pts, Color(frame_base_color.r * 0.7, frame_base_color.g * 0.9, frame_base_color.b * 1.2, 0.9))
		
		# Línea separadora de cabecera con sutil brillo
		var sep_y = r.position.y + header_h
		draw_line(Vector2(r.position.x + 4, sep_y), Vector2(r.end.x - 4, sep_y), Color(accent_color.r, accent_color.g, accent_color.b, 0.5), 1.0)
		
		# Título táctico en la cabecera si está presente
		if title != "":
			var f = get_theme_font("font") if has_method("get_theme_font") else null
			if f:
				draw_rect(Rect2(r.position.x + c + 4, r.position.y + 8, 4, 4), accent_color)
				draw_string(f, Vector2(r.position.x + c + 14, r.position.y + 15), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(accent_color.r, accent_color.g, accent_color.b, 0.95))
	
	# 3. Estructura Exterior de Titanio
	draw_polyline(pts, frame_base_color, 1.2, true)
	
	# 4. Brillo Holográfico / Borde de Energía
	if show_glow:
		draw_polyline(pts, Color(accent_color.r, accent_color.g, accent_color.b, 0.15), 3.0, true)
		draw_polyline(pts, Color(accent_color.r, accent_color.g, accent_color.b, 0.45), 1.0, true)
	
	# 5. Brackets Tácticos en las Esquinas (Targeting Reticle aesthetic)
	if show_brackets:
		var b_len = min(14.0, c * 1.4)
		_draw_corner_brackets(r, c, b_len, accent_color)
		
	# 6. Micro-Telemetría / Marcas de Graduación
	if show_telemetry and r.size.x > 80:
		_draw_telemetry_ticks(r, c)
		
	# 7. Remaches Mecanizados con Bisel 3D
	if show_rivets and r.size.x > 60 and r.size.y > 60:
		_draw_machined_rivets(r, c)

# ==============================================================================
# 2. VARIANTE RADAR: Contenedor de Minimapa
# ==============================================================================
func _draw_radar(r: Rect2):
	var c = min(16.0, min(r.size.x, r.size.y) * 0.2)
	var pts = _get_chamfered_points(r, c)
	
	# Fondo oscuro de alta visibilidad para radar (100% sólido por defecto)
	draw_colored_polygon(pts, Color(0.01, 0.02, 0.035, 1.0))
	
	# Marco base exterior
	draw_polyline(pts, frame_base_color, 1.5, true)
	
	# Borde de radar con pulso sutil de energía
	if show_glow:
		draw_polyline(pts, Color(accent_color.r, accent_color.g, accent_color.b, 0.18), 3.5, true)
		draw_polyline(pts, Color(accent_color.r, accent_color.g, accent_color.b, 0.55), 1.2, true)
		
	# Miras ópticas en los puntos cardinales (N, S, E, O)
	var mid_x = r.position.x + r.size.x * 0.5
	var mid_y = r.position.y + r.size.y * 0.5
	var tick_len = 6.0
	
	# Norte
	draw_line(Vector2(mid_x, r.position.y + 1), Vector2(mid_x, r.position.y + 1 + tick_len), accent_color, 1.5)
	# Sur
	draw_line(Vector2(mid_x, r.end.y - 1), Vector2(mid_x, r.end.y - 1 - tick_len), accent_color, 1.5)
	# Oeste
	draw_line(Vector2(r.position.x + 1, mid_y), Vector2(r.position.x + 1 + tick_len, mid_y), accent_color, 1.5)
	# Este
	draw_line(Vector2(r.end.x - 1, mid_y), Vector2(r.end.x - 1 - tick_len, mid_y), accent_color, 1.5)
	
	# Brackets angulares en esquinas
	_draw_corner_brackets(r, c, 12.0, accent_color)

# ==============================================================================
# 3. VARIANTE SLOT: Slots de Habilidades y Armas (65x65)
# ==============================================================================
func _draw_slot(r: Rect2):
	var c = 6.0 # Chaflán compacto para slots de 65x65
	var pts = _get_chamfered_points(r, c)
	
	# 1. Pozo interior oscuro para albergar el icono (100% sólido por defecto)
	draw_colored_polygon(pts, Color(0.008, 0.016, 0.025, 1.0))
	
	# 2. Marco estructural exterior fino
	draw_polyline(pts, frame_base_color, 1.0, true)
	
	# 3. Bisel interno de profundidad
	var inner_r = r.grow(-2.5)
	var inner_pts = _get_chamfered_points(inner_r, c * 0.6)
	draw_polyline(inner_pts, Color(frame_base_color.r * 1.5, frame_base_color.g * 1.8, frame_base_color.b * 2.2, 0.25), 1.0, true)
	
	# 4. Micro-brackets de sujeción táctica en las 4 esquinas
	var b_len = 7.0
	_draw_corner_brackets(r, c, b_len, accent_color)
	
	# 5. Línea sutil de anclaje para la tecla de atajo en la esquina inferior izquierda
	draw_line(Vector2(r.position.x, r.end.y - 14.0), Vector2(r.position.x + 14.0, r.end.y), Color(accent_color.r, accent_color.g, accent_color.b, 0.45), 1.0)

# ==============================================================================
# 4. VARIANTE MODAL: Marcos Grandes de Menús (F1 y F2)
# ==============================================================================
func _draw_modal_frame(r: Rect2):
	var c = 16.0
	var pts = _get_chamfered_points(r, c)
	
	# Fondo
	draw_colored_polygon(pts, bg_color)
	
	# Cabecera prominente
	var h_h = 36.0
	var h_pts = PackedVector2Array([
		Vector2(r.position.x + c, r.position.y),
		Vector2(r.end.x - c, r.position.y),
		Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.position.y + h_h),
		Vector2(r.position.x, r.position.y + h_h),
		Vector2(r.position.x, r.position.y + c)
	])
	draw_colored_polygon(h_pts, Color(0.018, 0.05, 0.08, 0.95))
	
	# Línea de energía bajo cabecera
	draw_line(Vector2(r.position.x, r.position.y + h_h), Vector2(r.end.x, r.position.y + h_h), accent_color, 1.5)
	
	# Estructura exterior
	draw_polyline(pts, frame_base_color, 1.5, true)
	
	if show_glow:
		draw_polyline(pts, Color(accent_color.r, accent_color.g, accent_color.b, 0.15), 4.0, true)
		draw_polyline(pts, Color(accent_color.r, accent_color.g, accent_color.b, 0.4), 1.2, true)
		
	_draw_corner_brackets(r, c, 22.0, accent_color)
	_draw_telemetry_ticks(r, c)

# ==============================================================================
# MÉTODOS AUXILIARES DE DIBUJO VECTORIAL PROCEDURAL
# ==============================================================================
# Retorna los 8 vértices exactos de un rectángulo achaflanado (sin duplicar el primer vértice)
func _get_chamfered_points(rect: Rect2, c: float) -> PackedVector2Array:
	var p = PackedVector2Array([
		Vector2(rect.position.x + c, rect.position.y),
		Vector2(rect.end.x - c, rect.position.y),
		Vector2(rect.end.x, rect.position.y + c),
		Vector2(rect.end.x, rect.end.y - c),
		Vector2(rect.end.x - c, rect.end.y),
		Vector2(rect.position.x + c, rect.end.y),
		Vector2(rect.position.x, rect.end.y - c),
		Vector2(rect.position.x, rect.position.y + c)
	])
	return p

func _draw_corner_brackets(rect: Rect2, c: float, b_len: float, col: Color):
	var glow_col = Color(col.r, col.g, col.b, 0.25)
	
	# 1. Top-Left
	var tl = PackedVector2Array([
		Vector2(rect.position.x, rect.position.y + c + b_len),
		Vector2(rect.position.x, rect.position.y + c),
		Vector2(rect.position.x + c, rect.position.y),
		Vector2(rect.position.x + c + b_len, rect.position.y)
	])
	draw_polyline(tl, glow_col, 3.0)
	draw_polyline(tl, col, 1.5)
	_draw_bracket_pip(Vector2(rect.position.x + c + b_len, rect.position.y), col)
	_draw_bracket_pip(Vector2(rect.position.x, rect.position.y + c + b_len), col)

	# 2. Top-Right
	var tr_pts = PackedVector2Array([
		Vector2(rect.end.x - c - b_len, rect.position.y),
		Vector2(rect.end.x - c, rect.position.y),
		Vector2(rect.end.x, rect.position.y + c),
		Vector2(rect.end.x, rect.position.y + c + b_len)
	])
	draw_polyline(tr_pts, glow_col, 3.0)
	draw_polyline(tr_pts, col, 1.5)
	_draw_bracket_pip(Vector2(rect.end.x - c - b_len, rect.position.y), col)
	_draw_bracket_pip(Vector2(rect.end.x, rect.position.y + c + b_len), col)

	# 3. Bottom-Right
	var br = PackedVector2Array([
		Vector2(rect.end.x, rect.end.y - c - b_len),
		Vector2(rect.end.x, rect.end.y - c),
		Vector2(rect.end.x - c, rect.end.y),
		Vector2(rect.end.x - c - b_len, rect.end.y)
	])
	draw_polyline(br, glow_col, 3.0)
	draw_polyline(br, col, 1.5)
	_draw_bracket_pip(Vector2(rect.end.x - c - b_len, rect.end.y), col)
	_draw_bracket_pip(Vector2(rect.end.x, rect.end.y - c - b_len), col)

	# 4. Bottom-Left
	var bl = PackedVector2Array([
		Vector2(rect.position.x + c + b_len, rect.end.y),
		Vector2(rect.position.x + c, rect.end.y),
		Vector2(rect.position.x, rect.end.y - c),
		Vector2(rect.position.x, rect.end.y - c - b_len)
	])
	draw_polyline(bl, glow_col, 3.0)
	draw_polyline(bl, col, 1.5)
	_draw_bracket_pip(Vector2(rect.position.x + c + b_len, rect.end.y), col)
	_draw_bracket_pip(Vector2(rect.position.x, rect.end.y - c - b_len), col)

func _draw_bracket_pip(pos: Vector2, col: Color):
	draw_circle(pos, 1.4, col)

func _draw_telemetry_ticks(rect: Rect2, c: float):
	var tick_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.45)
	# Graduaciones en la esquina inferior derecha
	var start_x = rect.end.x - c - 32.0
	var y = rect.end.y - 3.0
	for i in range(4):
		var tx = start_x + (i * 6.0)
		draw_line(Vector2(tx, y), Vector2(tx, y + 2.0), tick_color, 1.0)

func _draw_machined_rivets(rect: Rect2, c: float):
	var offset = c * 0.85
	var rivet_pos = [
		Vector2(rect.position.x + offset, rect.position.y + offset),
		Vector2(rect.end.x - offset, rect.position.y + offset),
		Vector2(rect.end.x - offset, rect.end.y - offset),
		Vector2(rect.position.x + offset, rect.end.y - offset)
	]
	for pos in rivet_pos:
		# Sombra exterior
		draw_circle(pos, 2.2, Color(0.02, 0.04, 0.07, 0.8))
		# Borde metálico mecanizado
		draw_circle(pos, 1.6, frame_base_color.lightened(0.2))
		# Núcleo sutil
		draw_circle(pos, 0.9, Color(accent_color.r, accent_color.g, accent_color.b, 0.6))

# ==============================================================================
# 5. MÉTODO ESTÁTICO MAESTRO PARA MENÚS MODALES (F1 Inventario y F2 Eventos)
# ==============================================================================
static func draw_tactical_modal(canvas: CanvasItem, r_pos: Vector2, r_size: Vector2, title_text: String, is_f1: bool = false, hubs_str: String = "", ohcu_str: String = ""):
	var r = Rect2(r_pos, r_size)
	var c = 16.0
	
	var p = PackedVector2Array([
		Vector2(r.position.x + c, r.position.y),
		Vector2(r.end.x - c, r.position.y),
		Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c),
		Vector2(r.end.x - c, r.end.y),
		Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c),
		Vector2(r.position.x, r.position.y + c)
	])
	
	# 1. Fondo de Cristal de Obsidiana Profundo
	canvas.draw_colored_polygon(p, Color(0.012, 0.022, 0.035, 0.96))
	
	# 2. Placa de Cabecera Aeroespacial Táctica (36px de alto)
	var h_h = 36.0
	var h_pts = PackedVector2Array([
		Vector2(r.position.x + c, r.position.y),
		Vector2(r.end.x - c, r.position.y),
		Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.position.y + h_h),
		Vector2(r.position.x, r.position.y + h_h),
		Vector2(r.position.x, r.position.y + c)
	])
	canvas.draw_colored_polygon(h_pts, Color(0.018, 0.045, 0.075, 0.98))
	
	# 3. Línea Láser divisoria de cabecera con aura
	var sep_y = r.position.y + h_h
	canvas.draw_line(Vector2(r.position.x, sep_y), Vector2(r.end.x, sep_y), Color(0.0, 0.82, 0.96, 0.2), 3.0)
	canvas.draw_line(Vector2(r.position.x, sep_y), Vector2(r.end.x, sep_y), Color(0.0, 0.82, 0.96, 0.85), 1.2)
	
	# 4. Estructura Exterior de Titanio/Grafito
	canvas.draw_polyline(p, Color(0.09, 0.16, 0.24, 0.85), 1.5, true)
	
	# 5. Brillo Tenue Perimetral
	canvas.draw_polyline(p, Color(0.0, 0.82, 0.96, 0.12), 4.0, true)
	canvas.draw_polyline(p, Color(0.0, 0.82, 0.96, 0.35), 1.0, true)
	
	# 6. Brackets Tácticos en las 4 Esquinas
	var b_len = 22.0
	var col = Color(0.0, 0.85, 1.0, 0.9)
	var glow_col = Color(0.0, 0.85, 1.0, 0.25)
	
	# TL
	var tl = PackedVector2Array([
		Vector2(r.position.x, r.position.y + c + b_len),
		Vector2(r.position.x, r.position.y + c),
		Vector2(r.position.x + c, r.position.y),
		Vector2(r.position.x + c + b_len, r.position.y)
	])
	canvas.draw_polyline(tl, glow_col, 3.0)
	canvas.draw_polyline(tl, col, 1.5)
	canvas.draw_circle(Vector2(r.position.x + c + b_len, r.position.y), 1.5, col)
	canvas.draw_circle(Vector2(r.position.x, r.position.y + c + b_len), 1.5, col)
	
	# TR
	var tr_pts = PackedVector2Array([
		Vector2(r.end.x - c - b_len, r.position.y),
		Vector2(r.end.x - c, r.position.y),
		Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.position.y + c + b_len)
	])
	canvas.draw_polyline(tr_pts, glow_col, 3.0)
	canvas.draw_polyline(tr_pts, col, 1.5)
	canvas.draw_circle(Vector2(r.end.x - c - b_len, r.position.y), 1.5, col)
	canvas.draw_circle(Vector2(r.end.x, r.end.y - c - b_len), 1.5, col)
	
	# BR
	var br = PackedVector2Array([
		Vector2(r.end.x, r.end.y - c - b_len),
		Vector2(r.end.x, r.end.y - c),
		Vector2(r.end.x - c, r.end.y),
		Vector2(r.end.x - c - b_len, r.end.y)
	])
	canvas.draw_polyline(br, glow_col, 3.0)
	canvas.draw_polyline(br, col, 1.5)
	canvas.draw_circle(Vector2(r.end.x - c - b_len, r.end.y), 1.5, col)
	canvas.draw_circle(Vector2(r.end.x, r.end.y - c - b_len), 1.5, col)
	
	# BL
	var bl = PackedVector2Array([
		Vector2(r.position.x + c + b_len, r.end.y),
		Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c),
		Vector2(r.position.x, r.end.y - c - b_len)
	])
	canvas.draw_polyline(bl, glow_col, 3.0)
	canvas.draw_polyline(bl, col, 1.5)
	canvas.draw_circle(Vector2(r.position.x + c + b_len, r.end.y), 1.5, col)
	canvas.draw_circle(Vector2(r.position.x, r.end.y - c - b_len), 1.5, col)
	
	# 7. Tipografía y Badges de Cabecera
	var f = canvas.get_theme_font("font") if canvas.has_method("get_theme_font") else null
	if f:
		# Indicador táctico inicial (pequeño rombo/cuadro antes del texto)
		var icon_x = r.position.x + 18.0
		var icon_y = r.position.y + 18.0
		canvas.draw_rect(Rect2(icon_x, icon_y - 4, 8, 8), Color(0.0, 0.85, 1.0, 0.85))
		
		# Título principal
		canvas.draw_string(f, Vector2(icon_x + 16, r.position.y + 23), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.0, 0.9, 1.0))
		
		# Si es F1, dibujar balances HUBS y OHCU con estilo avionics
		if is_f1:
			var hubs_x = r.position.x + 360.0
			var ohcu_x = r.position.x + 520.0
			if r.size.x < 900: # En pantallas más estrechas, ajustar posición
				hubs_x = r.position.x + 300.0
				ohcu_x = r.position.x + 440.0
				
			# HUBS (Cian)
			canvas.draw_rect(Rect2(hubs_x - 6, r.position.y + 8, 110, 20), Color(0.0, 0.15, 0.22, 0.6))
			canvas.draw_rect(Rect2(hubs_x - 6, r.position.y + 8, 110, 20), Color(0.0, 0.8, 1.0, 0.5), false, 1.0)
			canvas.draw_string(f, Vector2(hubs_x, r.position.y + 22), "HUBS: " + hubs_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 1.0, 0.9))
			
			# OHCU (Púrpura / Magenta)
			canvas.draw_rect(Rect2(ohcu_x - 6, r.position.y + 8, 110, 20), Color(0.2, 0.0, 0.25, 0.6))
			canvas.draw_rect(Rect2(ohcu_x - 6, r.position.y + 8, 110, 20), Color(1.0, 0.2, 0.8, 0.5), false, 1.0)
			canvas.draw_string(f, Vector2(ohcu_x, r.position.y + 22), "OHCU: " + ohcu_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.4, 0.9))
		
		# 8. Botón X de Cerrar de Alta Tecnología
		var btn_w = 44.0
		var btn_h = 24.0
		var btn_r = Rect2(r.position.x + r.size.x - 55, r.position.y + 6, btn_w, btn_h)
		
		# Chaflán en el botón de cerrar (8 vértices estrictamente convexos)
		var btn_pts = PackedVector2Array([
			Vector2(btn_r.position.x + 4, btn_r.position.y),
			Vector2(btn_r.end.x - 4, btn_r.position.y),
			Vector2(btn_r.end.x, btn_r.position.y + 4),
			Vector2(btn_r.end.x, btn_r.end.y - 4),
			Vector2(btn_r.end.x - 4, btn_r.end.y),
			Vector2(btn_r.position.x + 4, btn_r.end.y),
			Vector2(btn_r.position.x, btn_r.end.y - 4),
			Vector2(btn_r.position.x, btn_r.position.y + 4)
		])
		canvas.draw_colored_polygon(btn_pts, Color(0.12, 0.03, 0.05, 0.7))
		canvas.draw_polyline(btn_pts, Color(1.0, 0.25, 0.35, 0.75), 1.2, true)
		canvas.draw_string(f, Vector2(btn_r.position.x + 18, btn_r.position.y + 17), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.35, 0.45))
