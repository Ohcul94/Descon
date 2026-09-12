extends Node2D

# WreckageLabelTracker.gd
# Proyecta la posición 3D de los restos al espacio de pantalla 2D usando la cámara real del mapa.
# Precompilado para evitar congelamiento de fotogramas (frame-hitch) al compilar GDScript en caliente.

func _ready():
	_update_position()

func _process(_delta):
	_update_position()

func _update_position():
	var t = get_meta("t", null)
	var cam = get_meta("cam", null)
	var sub_vp = get_meta("sub_vp", null)
	var map = get_meta("map", null)
	if not is_instance_valid(t) or not is_instance_valid(cam) or not is_instance_valid(sub_vp):
		return
	if cam.is_position_behind(t.global_position):
		visible = false
		return
	visible = true
	var sv_pixel = cam.unproject_position(t.global_position)
	if is_instance_valid(map):
		var container = map.viewport_container
		if is_instance_valid(container) and sub_vp.size.x > 0:
			sv_pixel *= Vector2(container.size) / Vector2(sub_vp.size)
			sv_pixel += container.global_position
		else:
			if sub_vp.size.x > 0 and sub_vp.size.y > 0:
				var main_size = Vector2(get_viewport().get_visible_rect().size)
				sv_pixel *= main_size / Vector2(sub_vp.size)
	else:
		if sub_vp.size.x > 0 and sub_vp.size.y > 0:
			var main_size = Vector2(get_viewport().get_visible_rect().size)
			sv_pixel *= main_size / Vector2(sub_vp.size)
	global_position = get_viewport().get_canvas_transform().affine_inverse() * sv_pixel
