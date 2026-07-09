extends Node3D

var _ambient_particles: GPUParticles3D
var _hover_time: float = 0.0
var _scale_factor: float = 0.02
var _heal_radius_2d: float = 200.0
var _floating: Node3D
var _ring_h: MeshInstance3D
var _ring_v: MeshInstance3D
var _ring_t: MeshInstance3D
var _motes: Array[MeshInstance3D]
var _circle_tex: ImageTexture

func _ready():
	_circle_tex = _generate_circle_texture()
	_build_beacon()
	_setup_ambient_particles()
	_add_range_indicator()

func _generate_circle_texture(size := 64) -> ImageTexture:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half = size * 0.5
	var rad = size * 0.45
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(Vector2(half, half))
			var a = 0.0
			if dist < rad:
				a = 1.0 - (dist / rad)
				a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _process(delta):
	_hover_time += delta

	_floating.position.y = 0.8 + sin(_hover_time * 1.2) * 0.12

	_ring_h.rotation.y += delta * 0.6
	_ring_v.rotation.x += delta * 0.4
	_ring_t.rotation.z += delta * 0.35

	for i in _motes.size():
		var angle = _hover_time * 0.7 + i * TAU / _motes.size()
		var r = 0.55 + sin(_hover_time * 0.5 + i) * 0.1
		_motes[i].position = Vector3(cos(angle) * r, sin(_hover_time * 0.8 + i) * 0.15, sin(angle) * r)

	for child in get_children():
		if child is GPUParticles3D and child.name.begins_with("Wave_"):
			child.position.y = sin(_hover_time * 2.0) * 0.04

func _build_beacon():
	_floating = Node3D.new()
	_floating.name = "Floating"
	add_child(_floating)

	var mat_core = StandardMaterial3D.new()
	mat_core.albedo_color = Color(0.1, 1.0, 0.3)
	mat_core.emission_enabled = true
	mat_core.emission = Color(0.1, 1.0, 0.3)
	mat_core.emission_energy_multiplier = 4.0
	mat_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mat_glow = StandardMaterial3D.new()
	mat_glow.albedo_color = Color(0.1, 1.0, 0.3, 0.12)
	mat_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mat_ring = StandardMaterial3D.new()
	mat_ring.albedo_color = Color(0.1, 1.0, 0.3, 0.15)
	mat_ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mat_mote = StandardMaterial3D.new()
	mat_mote.albedo_color = Color(0.3, 1.0, 0.5)
	mat_mote.emission_enabled = true
	mat_mote.emission = Color(0.3, 1.0, 0.5)
	mat_mote.emission_energy_multiplier = 2.0
	mat_mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var core = MeshInstance3D.new()
	core.name = "Core"
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	sphere.radial_segments = 24
	sphere.rings = 12
	core.mesh = sphere
	core.material_override = mat_core
	_floating.add_child(core)

	for g in range(3):
		var glow = MeshInstance3D.new()
		glow.name = "Glow%d" % g
		var gs = SphereMesh.new()
		gs.radius = 0.18 + g * 0.12
		gs.height = (0.18 + g * 0.12) * 2.0
		gs.radial_segments = 24
		gs.rings = 12
		glow.mesh = gs
		var gm = StandardMaterial3D.new()
		gm.albedo_color = Color(0.1, 1.0, 0.3, 0.12 - g * 0.03)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.material_override = gm
		_floating.add_child(glow)

	_ring_h = MeshInstance3D.new()
	_ring_h.name = "RingH"
	var torus_h = TorusMesh.new()
	torus_h.inner_radius = 0.25
	torus_h.outer_radius = 0.35
	_ring_h.mesh = torus_h
	_ring_h.material_override = mat_ring
	_floating.add_child(_ring_h)

	_ring_v = MeshInstance3D.new()
	_ring_v.name = "RingV"
	var torus_v = TorusMesh.new()
	torus_v.inner_radius = 0.25
	torus_v.outer_radius = 0.35
	_ring_v.mesh = torus_v
	_ring_v.material_override = mat_ring
	_ring_v.rotation_degrees.x = 60
	_floating.add_child(_ring_v)

	_ring_t = MeshInstance3D.new()
	_ring_t.name = "RingT"
	var torus_t = TorusMesh.new()
	torus_t.inner_radius = 0.28
	torus_t.outer_radius = 0.36
	_ring_t.mesh = torus_t
	var mat_ring2 = StandardMaterial3D.new()
	mat_ring2.albedo_color = Color(0.2, 1.0, 0.4, 0.1)
	mat_ring2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_ring2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_t.material_override = mat_ring2
	_ring_t.rotation_degrees.z = 45
	_floating.add_child(_ring_t)

	for i in 5:
		var mote = MeshInstance3D.new()
		mote.name = "Mote%d" % i
		var ms = SphereMesh.new()
		ms.radius = 0.025
		ms.height = 0.05
		ms.radial_segments = 12
		ms.rings = 6
		mote.mesh = ms
		mote.material_override = mat_mote
		_floating.add_child(mote)
		_motes.append(mote)

	var light = OmniLight3D.new()
	light.light_color = Color(0.1, 1.0, 0.3)
	light.light_energy = 1.0
	light.omni_range = 7.0
	_floating.add_child(light)

func _add_range_indicator():
	var radius_3d = _heal_radius_2d * _scale_factor
	var ring = MeshInstance3D.new()
	ring.name = "RangeRing"
	var torus = TorusMesh.new()
	var ring_width = max(radius_3d * 0.06, 0.15)
	var half_thick = ring_width * 0.5
	torus.inner_radius = max(radius_3d - half_thick, 0.01)
	torus.outer_radius = radius_3d + half_thick
	var ring_mat = StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.1, 1.0, 0.3, 0.2)
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	ring.material_override = ring_mat
	ring.mesh = torus
	ring.position.y = 0.02
	add_child(ring)

func _update_range_ring():
	var ring = get_node_or_null("RangeRing")
	if not ring: return
	var radius_3d = _heal_radius_2d * _scale_factor
	var torus = TorusMesh.new()
	var ring_width = max(radius_3d * 0.06, 0.15)
	var half_thick = ring_width * 0.5
	torus.inner_radius = max(radius_3d - half_thick, 0.01)
	torus.outer_radius = radius_3d + half_thick
	ring.mesh = torus

func _setup_ambient_particles():
	var parts = GPUParticles3D.new()
	parts.name = "Ambient"
	parts.amount = 30
	parts.lifetime = 2.0
	parts.one_shot = false
	parts.explosiveness = 0.0

	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.12, 0.12)
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _circle_tex
	mesh.material = mat
	parts.draw_pass_1 = mesh

	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 40.0
	pm.gravity = Vector3(0, 0.1, 0)
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.5
	pm.orbit_velocity_min = 0.05
	pm.orbit_velocity_max = 0.15
	var grad = Gradient.new()
	grad.set_color(0, Color(0.1, 1.0, 0.3, 0.9))
	grad.add_point(0.4, Color(0.2, 1.0, 0.4, 0.5))
	grad.set_color(1, Color(0.4, 1.0, 0.5, 0.0))
	pm.color_ramp = GradientTexture1D.new()
	pm.color_ramp.gradient = grad
	parts.process_material = pm
	_floating.add_child(parts)
	parts.emitting = true
	_ambient_particles = parts

func pulse(radius_2d: float = 200.0):
	_heal_radius_2d = radius_2d
	_update_range_ring()
	var radius_3d = radius_2d * _scale_factor
	var lifetime = 0.8
	var burst_speed = radius_3d / lifetime

	var wave = GPUParticles3D.new()
	wave.name = "Wave_%d" % [_hover_time * 1000]
	wave.one_shot = true
	wave.emitting = true
	wave.amount = 100
	wave.lifetime = lifetime
	wave.explosiveness = 0.3
	wave.position.y = 0.05

	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.25, 0.25)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 1.0, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _circle_tex
	mesh.material = mat
	wave.draw_pass_1 = mesh

	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3.FORWARD
	pm.spread = 180.0
	pm.flatness = 0.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = burst_speed * 0.7
	pm.initial_velocity_max = burst_speed
	pm.scale_min = 2.5
	pm.scale_max = 4.5
	var grad = Gradient.new()
	grad.set_color(0, Color(0.1, 1.0, 0.3, 0.9))
	grad.set_color(1, Color(0.1, 1.0, 0.3, 0.0))
	pm.color_ramp = GradientTexture1D.new()
	pm.color_ramp.gradient = grad
	wave.process_material = pm
	add_child(wave)

	var tw = create_tween()
	tw.tween_interval(lifetime + 0.4)
	tw.tween_callback(wave.queue_free)

	var ring_width = max(radius_3d * 0.06, 0.15)
	var half_thick = ring_width * 0.5
	var ring_flash = MeshInstance3D.new()
	var ring_torus = TorusMesh.new()
	ring_torus.inner_radius = max(radius_3d - half_thick, 0.01)
	ring_torus.outer_radius = radius_3d + half_thick
	var ring_mat = StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.1, 1.0, 0.3, 0.5)
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	ring_flash.material_override = ring_mat
	ring_flash.mesh = ring_torus
	ring_flash.position.y = 0.04
	ring_flash.name = "FlashRing"
	add_child(ring_flash)

	var ftw = create_tween()
	ftw.set_parallel(true)
	ftw.tween_property(ring_mat, "albedo_color", Color(0.1, 1.0, 0.3, 0.0), lifetime)
	ftw.tween_property(ring_flash, "scale", Vector3(1.12, 1.0, 1.12), lifetime)
	ftw.chain().tween_callback(ring_flash.queue_free)
