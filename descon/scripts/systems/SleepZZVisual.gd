extends Node2D
# v413: ZZZ de Sueño Inducido - letras "Z" que flotan sobre el jugador
# mientras está dormido (stun isSleep). Solo feedback visual.
# Se adjunta al _ui_wrapper del jugador (misma capa que los números de daño).

var _active: bool = false
var _elapsed: float = 0.0
var _next_z: float = 0.0

func start_zzz() -> void:
	var was_active := _active
	_active = true
	_elapsed = 0.0
	_next_z = 0.0
	visible = true
	if not was_active:
		_spawn_z()

func stop_zzz() -> void:
	_active = false
	for child in get_children():
		if child.has_meta("sleep_z"):
			child.queue_free()

func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	if _elapsed >= _next_z:
		_next_z = _elapsed + 0.45
		_spawn_z()

func _spawn_z() -> void:
	var z_label = Label.new()
	z_label.text = "Z"
	z_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	z_label.add_theme_font_size_override("font_size", 30)
	z_label.add_theme_constant_override("outline_size", 8)
	z_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	z_label.add_theme_color_override("font_color", Color(1.0, 0.65, 1.0))
	z_label.set_meta("sleep_z", true)
	z_label.z_index = 110
	z_label.position = Vector2(randf_range(-18.0, 18.0), -randf_range(50.0, 80.0))
	add_child(z_label)
	var tw = z_label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(z_label, "position:y", z_label.position.y - randf_range(50.0, 80.0), 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(z_label, "position:x", z_label.position.x + randf_range(-20.0, 20.0), 1.3)
	tw.tween_property(z_label, "rotation", randf_range(-0.35, 0.35), 1.3)
	tw.tween_property(z_label, "scale", Vector2(1.15, 1.15), 1.3)
	tw.tween_property(z_label, "modulate:a", 0.0, 0.5).set_delay(0.75)
	tw.chain().tween_callback(z_label.queue_free)
