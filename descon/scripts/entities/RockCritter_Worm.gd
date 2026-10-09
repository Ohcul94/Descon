extends "res://scripts/entities/RockCritter_Base.gd"

var segs: Array[Node3D] = []
var radii: Array[float] = []
var spacing := 0.02
var _contract := 0.0


func _size_range() -> Array:
	return [0.085, 0.11]


func _size_clamp() -> Array:
	return [0.16, 0.26]


func _walk_speed_scale() -> float:
	return maxf(0.15, 1.0 + sin(phase) * 0.85)


func _build() -> void:
	var L := size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.68, 0.35)
	mat.roughness = 0.5
	var mat_head := StandardMaterial3D.new()
	mat_head.albedo_color = Color(0.50, 0.55, 0.26)
	mat_head.roughness = 0.45
	spacing = L * 0.17
	var n := 7
	for i in n:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var t := float(i) / float(n - 1)
		var r: float = L * lerpf(0.165, 0.10, t)
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 10
		sm.rings = 6
		sm.material = mat_head if i == 0 else mat
		m.mesh = sm
		add_child(m)
		segs.append(m)
		radii.append(r)
		m.position = Vector3(0.0, r, -spacing * i)


func _animate(delta: float) -> void:
	var want := 1.0 if walking else 0.0
	_contract = lerpf(_contract, want, minf(1.0, delta * 5.0))
	var pulse := (0.5 + 0.5 * sin(phase)) * _contract
	var n := segs.size()
	for i in n:
		var s := segs[i]
		var f := float(i) / float(n - 1)
		var arch_y := sin(PI * f) * size * 0.30 * pulse
		var sp := spacing * (1.0 - 0.42 * pulse)
		var ty: float = radii[i] + arch_y
		var tz: float = -sp * i
		s.position.y = lerpf(s.position.y, ty, minf(1.0, delta * 12.0))
		s.position.z = lerpf(s.position.z, tz, minf(1.0, delta * 12.0))
		if walking:
			var stretch := 1.0 + sin(phase - f * 2.2) * 0.10 * _contract
			s.scale = Vector3(1.0, 1.0, stretch)
		else:
			var br := 1.0 + sin(phase * 0.5 + f * 0.35) * 0.02
			s.scale = Vector3(br, br, br)
