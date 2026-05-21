# e:/Descon/descon/scripts/vfx/TauntVFX.gd
extends Node2D
class_name TauntVFX

@export var line_color: Color = Color(1.0, 0.0, 0.0, 1.0) # Rojo
@export var line_width: float = 2.0
@export var line_duration: float = 0.5 # Duración de la contracción de las líneas
@export var wave_duration: float = 0.3 # Duración de la onda expansiva
@export var wave_max_radius_factor: float = 1.5 # Factor para el radio máximo de la onda
@export var chat_bubble_duration: float = 2.0 # Duración de la burbuja de chat
@export var chat_bubble_offset: Vector2 = Vector2(0, -50) # Offset para la burbuja

var _caster_node: Node2D
var _affected_enemy_nodes: Array[Node2D] = []
var _epicenter_pos: Vector2
var _radius: float
var _duration: float

var _line_tween: Tween
var _wave_tween: Tween
var _chat_bubble_timer: Timer

var _current_wave_radius: float = 0.0
var _current_wave_opacity: float = 1.0
var _start_time: float = 0.0

func _ready():
    set_process(false) # Desactivar _process por defecto

func init(caster_node: Node2D, affected_enemy_nodes: Array[Node2D], epicenter_pos: Vector2, radius: float, duration: float):
    _caster_node = caster_node
    _affected_enemy_nodes = affected_enemy_nodes
    _epicenter_pos = epicenter_pos
    _radius = radius
    _duration = duration / 1000.0 # Convertir ms a segundos

    global_position = _epicenter_pos # Posicionar el VFX en el epicentro
    _start_time = Time.get_ticks_msec() / 1000.0
    set_process(true)
    _play_vfx()

func _play_vfx():
    # Epicentro: Destello de descarga y onda expansiva
    _current_wave_radius = 0.0
    _current_wave_opacity = 1.0
    _wave_tween = create_tween()
    _wave_tween.tween_property(self, "_current_wave_radius", _radius * wave_max_radius_factor, wave_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
    _wave_tween.tween_property(self, "_current_wave_opacity", 0.0, wave_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
    _wave_tween.finished.connect(queue_redraw) # Asegurar que se redibuje al finalizar

    # Hilos de Agarre: Líneas rojas zigzagueantes
    _line_tween = create_tween()
    _line_tween.set_parallel(true)
    for enemy_node in _affected_enemy_nodes:
        if is_instance_valid(enemy_node):
            # Simular contracción de las líneas
            # Podrías usar un Line2D real y animar sus puntos, o dibujarlo en _draw
            pass # La lógica de dibujo estará en _draw
    _line_tween.tween_interval(line_duration) # Solo para que el tween tenga una duración
    _line_tween.finished.connect(queue_redraw)

    # Efecto de Provocación: Burbuja de chat "💢"
    for enemy_node in _affected_enemy_nodes:
        if is_instance_valid(enemy_node):
            _show_chat_bubble(enemy_node, "💢")

    # Destruir el VFX después de la duración de la provocación + un pequeño margen
    get_tree().create_timer(_duration + 0.5).timeout.connect(queue_free)

func _draw():
    # Dibujar la onda expansiva
    if _current_wave_opacity > 0.01:
        var wave_color = line_color
        wave_color.a = _current_wave_opacity
        draw_arc(Vector2.ZERO, _current_wave_radius, 0, TAU, 64, wave_color, line_width * 2, true)

    # Dibujar los hilos de agarre
    var current_time = Time.get_ticks_msec() / 1000.0
    var line_progress = 1.0
    
    line_progress = clamp((current_time - _start_time) / line_duration, 0.0, 1.0)

    for enemy_node in _affected_enemy_nodes:
        if is_instance_valid(enemy_node):
            var epicenter_rel = Vector2.ZERO 
            var end_pos = to_local(enemy_node.global_position)

            # Las líneas viajan del enemigo hacia el centro (contracción)
            # Usamos animated_start_pos para que el hilo "tire" del enemigo
            var animated_start_pos = epicenter_rel.lerp(end_pos, 1.0 - line_progress)
            
            # Dibujar líneas zigzagueantes (ejemplo simple, puedes usar Line2D o más puntos)
            var num_segments = 5
            var current_point = animated_start_pos
            for i in range(num_segments):
                var next_point = animated_start_pos.lerp(end_pos, float(i + 1) / num_segments)
                var offset_dir = (next_point - current_point).rotated(PI / 2).normalized()
                var wobble_amount = sin(current_time * 10.0 + i) * 5.0 # Efecto de "wobble"
                var mid_point = current_point.lerp(next_point, 0.5) + offset_dir * wobble_amount
                draw_line(current_point, mid_point, line_color, line_width)
                draw_line(mid_point, next_point, line_color, line_width)
                current_point = next_point

    queue_redraw() # Para animar las líneas y la onda

func _show_chat_bubble(target_node: Node2D, text: String):
    # Instanciar una burbuja de chat (Label o TextureRect con texto)
    var chat_bubble = Label.new()
    chat_bubble.text = text
    chat_bubble.add_theme_font_size_override("font_size", 24)
    chat_bubble.add_theme_color_override("font_color", Color.WHITE)
    chat_bubble.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    chat_bubble.position = chat_bubble_offset
    target_node.add_child(chat_bubble)

    var bubble_tween = create_tween()
    bubble_tween.tween_property(chat_bubble, "modulate:a", 0.0, chat_bubble_duration).set_delay(chat_bubble_duration * 0.5)
    bubble_tween.finished.connect(chat_bubble.queue_free)