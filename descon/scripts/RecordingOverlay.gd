extends CanvasLayer

const DEV_TOGGLE_KEY = KEY_F5
const VIS_TOGGLE_KEY = KEY_F12
const SAVE_PATH = "user://recording_frame.json"

@export var dev_mode: bool = true

var frame_visible: bool = false
var frame: FrameVisual
var drag_active := false
var drag_offset := Vector2.ZERO
var last_viewport_size := Vector2.ZERO

class FrameVisual extends Control:
	const BORDER_COLOR := Color(0.2, 1.0, 0.4, 0.9)
	const BORDER_WIDTH := 4.0
	const BORDER_GAP := 6.0

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw():
		var m := BORDER_GAP + BORDER_WIDTH * 0.5
		draw_rect(Rect2(Vector2.ZERO, size).grow(m), BORDER_COLOR, false, BORDER_WIDTH)

	func hit_rect() -> Rect2:
		return get_global_rect().grow(BORDER_GAP + BORDER_WIDTH)

func _ready():
	frame = FrameVisual.new()
	frame.name = "RecordingFrame"
	add_child(frame)

	last_viewport_size = get_viewport().get_visible_rect().size
	update_rect_size()
	frame.position = last_viewport_size / 2.0 - frame.size / 2.0

	var saved = load_saved_position()
	if saved != null:
		frame.position = saved
	else:
		save_position()

	frame.visible = frame_visible

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == DEV_TOGGLE_KEY:
			dev_mode = !dev_mode
		elif event.physical_keycode == VIS_TOGGLE_KEY:
			frame_visible = !frame_visible
			frame.visible = frame_visible
		return

	if not dev_mode or not frame_visible:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not drag_active and frame.hit_rect().has_point(event.position):
				drag_active = true
				drag_offset = frame.position - event.position
				get_viewport().set_input_as_handled()
		elif drag_active:
			drag_active = false
			save_position()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and drag_active:
		var new_pos = event.position + drag_offset
		var vp = get_viewport().get_visible_rect().size
		new_pos.x = clampf(new_pos.x, 0.0, maxf(0.0, vp.x - frame.size.x))
		new_pos.y = clampf(new_pos.y, 0.0, maxf(0.0, vp.y - frame.size.y))
		frame.position = new_pos
		get_viewport().set_input_as_handled()

func _process(_delta: float):
	var vp_size = get_viewport().get_visible_rect().size
	if vp_size != last_viewport_size:
		last_viewport_size = vp_size
		var old_center = frame.position + frame.size / 2.0
		update_rect_size()
		frame.position = old_center - frame.size / 2.0
		clamp_to_viewport()

func update_rect_size():
	var vp_size = get_viewport().get_visible_rect().size
	var rw: float
	var rh: float
	if vp_size.x / 9.0 > vp_size.y / 16.0:
		rh = vp_size.y * 0.9
		rw = rh * 9.0 / 16.0
	else:
		rw = vp_size.x * 0.9
		rh = rw * 16.0 / 9.0
	frame.size = Vector2(rw, rh)
	frame.queue_redraw()

func clamp_to_viewport():
	var vp = get_viewport().get_visible_rect().size
	frame.position = Vector2(
		clampf(frame.position.x, 0.0, maxf(0.0, vp.x - frame.size.x)),
		clampf(frame.position.y, 0.0, maxf(0.0, vp.y - frame.size.y))
	)

func save_position():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify([frame.position.x, frame.position.y]))
		file.close()

func load_saved_position() -> Variant:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array and parsed.size() == 2:
		return Vector2(float(parsed[0]), float(parsed[1]))
	return null
