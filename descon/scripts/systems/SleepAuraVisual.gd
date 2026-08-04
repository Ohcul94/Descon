extends Node2D
# v413: Aura de somnolencia (Sueño Inducido) - pulso violeta alrededor del jugador
# mientras está ralentizado por la fase previa al sueño. Solo feedback visual;
# el slow real lo gestiona el servidor.

var _active: bool = false
var _t: float = 0.0

func start_aura() -> void:
	_active = true
	visible = true

func stop_aura() -> void:
	_active = false
	visible = false

func _process(delta: float) -> void:
	if _active:
		_t += delta
		queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var base_r = 42.0
	var pulse = base_r + sin(_t * 3.0) * 6.0
	draw_circle(Vector2.ZERO, pulse, Color(0.7, 0.35, 0.95, 0.14))
	draw_circle(Vector2.ZERO, pulse * 0.7, Color(0.8, 0.45, 1.0, 0.10))
	draw_arc(Vector2.ZERO, pulse, _t * 1.5, _t * 1.5 + 2.2, 24, Color(0.85, 0.55, 1.0, 0.5), 2.0)
	draw_arc(Vector2.ZERO, pulse, _t * 1.5 + PI, _t * 1.5 + PI + 2.2, 24, Color(0.85, 0.55, 1.0, 0.5), 2.0)
