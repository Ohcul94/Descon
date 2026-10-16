extends CanvasLayer

const DEV_TOGGLE_KEY = KEY_F5
const VIS_TOGGLE_KEY = KEY_F12

@export var dev_mode: bool = true

# Platform aspect ratios (as int constants)
const ASPECT_YOUTUBE = 0        # 16:9
const ASPECT_INSTAGRAM_FEED = 1 # 1:1
const ASPECT_INSTAGRAM_STORY = 2 # 9:16
const ASPECT_TIKTOK = 3         # 9:16
const ASPECT_CUSTOM = 4

var frame_visible: bool = false
var frame: FrameVisual
var last_viewport_size := Vector2.ZERO
var current_aspect: int = ASPECT_YOUTUBE
var custom_aspect: Vector2 = Vector2(16.0, 9.0)

class FrameVisual extends Control:
	const BORDER_COLOR := Color(0.0, 0.85, 1.0, 0.95) # Cyan brillante estilo Sci-Fi
	const BORDER_WIDTH := 3.0
	const BORDER_GAP := 4.0

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw():
		var vp_size = get_viewport().get_visible_rect().size
		var g_pos = global_position
		var shadow_col = Color(0.0, 0.0, 0.0, 0.55) # Sombreado elegante para áreas fuera del encuadre
		
		# Letterboxing / Pillarboxing: bandas sombreadas exteriores
		if g_pos.y > 0.5:
			draw_rect(Rect2(-g_pos.x, -g_pos.y, vp_size.x, g_pos.y), shadow_col) # Banda superior
		
		var bottom_y = g_pos.y + size.y
		if bottom_y < vp_size.y - 0.5:
			draw_rect(Rect2(-g_pos.x, size.y, vp_size.x, vp_size.y - bottom_y), shadow_col) # Banda inferior
		
		if g_pos.x > 0.5:
			draw_rect(Rect2(-g_pos.x, 0, g_pos.x, size.y), shadow_col) # Banda izquierda
		
		var right_x = g_pos.x + size.x
		if right_x < vp_size.x - 0.5:
			draw_rect(Rect2(size.x, 0, vp_size.x - right_x, size.y), shadow_col) # Banda derecha

		# Borde del encuadre
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

	frame.visible = frame_visible
	
	# Connect to SocialCamera if available
	var smc = get_node_or_null("/root/SocialCamera")
	if smc:
		smc.platform_changed.connect(_on_platform_changed)
		smc.camera_activated.connect(_on_camera_activated)
		smc.camera_deactivated.connect(_on_camera_deactivated)
		current_aspect = int(smc.current_platform)
		update_rect_size()

func _on_platform_changed(platform: int):
	current_aspect = platform
	update_rect_size()

func _on_camera_activated():
	frame_visible = true
	frame.visible = true
	update_rect_size()

func _on_camera_deactivated():
	if not dev_mode:
		frame_visible = false
		frame.visible = false

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == DEV_TOGGLE_KEY:
			dev_mode = !dev_mode
		elif event.physical_keycode == VIS_TOGGLE_KEY:
			frame_visible = !frame_visible
			frame.visible = frame_visible
		elif event.physical_keycode == KEY_F6:
			_cycle_aspect_ratio()
		return

func _notify(message: String, type: String = "info"):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("notify"):
		hud.notify(message, type)

func _process(_delta: float):
	var vp_size = get_viewport().get_visible_rect().size
	if vp_size != last_viewport_size:
		last_viewport_size = vp_size
		update_rect_size()

func update_rect_size():
	var vp_size = get_viewport().get_visible_rect().size
	var rw: float
	var rh: float
	
	var aspect_w: float = 16.0
	var aspect_h: float = 9.0
	var is_fullscreen = false
	
	match current_aspect:
		0:  # YOUTUBE 16:9 (Pantalla completa si la pantalla es 16:9)
			aspect_w = 16.0
			aspect_h = 9.0
			is_fullscreen = true
		1:  # INSTAGRAM_FEED 1:1
			aspect_w = 1.0
			aspect_h = 1.0
		2:  # INSTAGRAM_STORY / REELS 9:16
			aspect_w = 9.0
			aspect_h = 16.0
		3:  # TIKTOK 9:16
			aspect_w = 9.0
			aspect_h = 16.0
		4:  # CUSTOM
			aspect_w = custom_aspect.x
			aspect_h = custom_aspect.y
	
	if is_fullscreen and abs((vp_size.x / vp_size.y) - (aspect_w / aspect_h)) < 0.05:
		frame.size = vp_size
		frame.position = Vector2.ZERO
	else:
		# Centrado absoluto en ancho y alto
		var padding = 0.94
		if (vp_size.x / aspect_w) > (vp_size.y / aspect_h):
			rh = vp_size.y * padding
			rw = rh * aspect_w / aspect_h
		else:
			rw = vp_size.x * padding
			rh = rw * aspect_h / aspect_w
		
		frame.size = Vector2(rw, rh)
		# Centrado al medio exacto de la pantalla (alto y ancho)
		frame.position = Vector2(
			roundf((vp_size.x - rw) / 2.0),
			roundf((vp_size.y - rh) / 2.0)
		)
	
	frame.queue_redraw()

func set_custom_aspect(width: float, height: float):
	custom_aspect = Vector2(width, height)
	current_aspect = 4  # CUSTOM
	update_rect_size()

func get_current_aspect_ratio() -> Vector2:
	match current_aspect:
		0: return Vector2(16.0, 9.0)
		1: return Vector2(1.0, 1.0)
		2: return Vector2(9.0, 16.0)
		3: return Vector2(9.0, 16.0)
		4: return custom_aspect
	return Vector2(16.0, 9.0)

func _cycle_aspect_ratio():
	var aspects = [0, 1, 2, 3]
	var idx = aspects.find(current_aspect)
	idx = (idx + 1) % aspects.size()
	current_aspect = aspects[idx]
	update_rect_size()
	
	var smc = get_node_or_null("/root/SocialCamera")
	if smc and smc.is_active:
		smc.set_platform(current_aspect)
	
	_notify("Formato: " + _get_aspect_name(current_aspect))

func _get_aspect_name(aspect: int) -> String:
	match aspect:
		0: return "YouTube (16:9)"
		1: return "Instagram Feed (1:1)"
		2: return "Instagram Story (9:16)"
		3: return "TikTok (9:16)"
		4: return "Personalizado"
	return "Desconocido"
