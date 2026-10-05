extends Node2D

# ResourceBeamVFX.gd
# Rayo continuo celeste/azul entre un nodo de recurso y el jugador
# mientras dura el canal de recolección (VFX estilo Vital Link).

const JITTER_INTERVAL: float = 0.05
const SEGMENTS: int = 9
const DROPLET_COUNT: int = 5

var from_node: Node2D = null
var to_node: Node2D = null
var active: bool = false

var elapsed: float = 0.0
var progress: float = 0.0
var _jitter_timer: float = 0.0
var _seed: int = 0
var _a: Vector2 = Vector2.ZERO
var _b: Vector2 = Vector2.ZERO
var _droplets: Array = []

var glow_line: Line2D = null
var main_line: Line2D = null
var core_line: Line2D = null

func _ready():
	set_as_top_level(true)
	z_index = 6

	glow_line = Line2D.new()
	glow_line.name = "Glow"
	glow_line.width = 16.0
	glow_line.default_color = Color(0.22, 0.74, 0.97, 0.15)
	glow_line.joint_mode = Line2D.LINE_JOINT_ROUND
	glow_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(glow_line)

	main_line = Line2D.new()
	main_line.name = "Main"
	main_line.width = 5.0
	var grad = Gradient.new()
	grad.colors = PackedColorArray([Color(0.22, 0.74, 0.97), Color(0.05, 0.65, 0.92)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	main_line.gradient = grad
	main_line.default_color = Color(0.22, 0.74, 0.97, 0.75)
	main_line.joint_mode = Line2D.LINE_JOINT_ROUND
	main_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	main_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(main_line)

	core_line = Line2D.new()
	core_line.name = "Core"
	core_line.width = 1.8
	core_line.default_color = Color(0.88, 0.97, 1.0, 0.95)
	core_line.joint_mode = Line2D.LINE_JOINT_ROUND
	core_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(core_line)

	_seed = randi()
	_droplets.clear()
	for i in range(DROPLET_COUNT):
		_droplets.append({
			"t": float(i) / float(DROPLET_COUNT),
			"speed": randf_range(0.9, 1.5),
			"size": randf_range(2.0, 3.6)
		})

func setup(p_from: Node2D, p_to: Node2D) -> void:
	from_node = p_from
	to_node = p_to
	active = is_instance_valid(from_node) and is_instance_valid(to_node)
	visible = active
	set_process(active)

func set_progress(p: float) -> void:
	progress = clamp(p, 0.0, 1.0)

func stop() -> void:
	active = false
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(from_node) or not is_instance_valid(to_node):
		stop()
		return

	elapsed += delta
	_jitter_timer -= delta
	if _jitter_timer <= 0.0:
		_jitter_timer = JITTER_INTERVAL
		_seed = randi()

	_a = from_node.global_position + Vector2(0.0, -24.0)
	_b = to_node.global_position + Vector2(0.0, -12.0)
	_update_beam_points()
	_update_droplets(delta)
	queue_redraw()

func _update_beam_points() -> void:
	var pts = PackedVector2Array()
	var delta_v = _b - _a
	var perp = Vector2.ZERO
	if delta_v.length() > 0.001:
		perp = Vector2(-delta_v.y, delta_v.x).normalized()

	for i in range(SEGMENTS + 1):
		var t = float(i) / float(SEGMENTS)
		var base = _a.lerp(_b, t)
		var amp = 7.0 * sin(PI * t)
		var n = sin(_seed * 0.37 + t * 9.0) + cos(_seed * 0.11 + t * 15.0)
		pts.append(base + perp * amp * n * 0.5)

	glow_line.points = pts
	main_line.points = pts
	core_line.points = pts

	# Brillo proporcional al avance del canal
	var boost = 1.0 + progress * 0.6
	glow_line.width = 16.0 * boost
	main_line.width = 5.0 * boost

func _update_droplets(delta: float) -> void:
	for d in _droplets:
		d["t"] += delta * d["speed"] * 0.55
		if d["t"] > 1.0:
			d["t"] -= 1.0

func _draw() -> void:
	if not active:
		return
	for d in _droplets:
		var p = _a.lerp(_b, float(d["t"]))
		var fade = sin(float(d["t"]) * PI)
		draw_circle(p, float(d["size"]), Color(0.88, 0.97, 1.0, 0.85 * fade))

func fade_out_and_free() -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)
