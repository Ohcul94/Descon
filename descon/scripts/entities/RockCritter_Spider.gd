extends "res://scripts/entities/RockCritter_Base.gd"

const TRIPOD_A := [0, 2, 5, 7]

var hips: Array[Node3D] = []
var leg_sides: Array[float] = []
var body_node: Node3D
var abdomen: MeshInstance3D


func _size_range() -> Array:
	return [0.045, 0.06]


func _size_clamp() -> Array:
	return [0.12, 0.22]


func _build() -> void:
	var L := size
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.32, 0.10, 0.07)
	body_mat.roughness = 0.5
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.24, 0.09, 0.06)
	leg_mat.roughness = 0.6

	body_node = Node3D.new()
	add_child(body_node)

	abdomen = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = L * 0.30
	sm.height = L * 0.55
	sm.radial_segments = 12
	sm.rings = 8
	sm.material = body_mat
	abdomen.mesh = sm
	abdomen.position = Vector3(0.0, L * 0.16, -L * 0.26)
	abdomen.scale = Vector3(1.0, 0.75, 1.2)
	body_node.add_child(abdomen)

	var cep := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = L * 0.20
	sm2.height = L * 0.36
	sm2.radial_segments = 10
	sm2.rings = 6
	sm2.material = body_mat
	cep.mesh = sm2
	cep.position = Vector3(0.0, L * 0.15, L * 0.12)
	cep.scale = Vector3(1.0, 0.8, 1.05)
	body_node.add_child(cep)

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.92, 0.88, 0.75)
	eye_mat.roughness = 0.3
	for e_off in [Vector3(-0.06, 0.21, 0.26), Vector3(0.06, 0.21, 0.26), Vector3(-0.12, 0.18, 0.22), Vector3(0.12, 0.18, 0.22)]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = L * 0.032
		es.height = L * 0.064
		es.radial_segments = 6
		es.rings = 4
		es.material = eye_mat
		eye.mesh = es
		eye.position = Vector3(e_off.x * L, e_off.y * L, e_off.z * L)
		body_node.add_child(eye)

	for side in [-1.0, 1.0]:
		for i in 4:
			var hip := Node3D.new()
			var z := L * (0.18 - i * 0.11)
			hip.position = Vector3(side * L * 0.13, L * 0.15, z)
			add_child(hip)
			hips.append(hip)
			leg_sides.append(side)

			var femur := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = L * 0.032
			cyl.bottom_radius = L * 0.026
			cyl.height = L * 0.32
			cyl.radial_segments = 6
			cyl.material = leg_mat
			femur.mesh = cyl
			femur.position = Vector3(side * L * 0.11, L * 0.11, 0.0)
			femur.rotation.z = -side * 0.80
			hip.add_child(femur)

			var tibia := MeshInstance3D.new()
			var cyl2 := CylinderMesh.new()
			cyl2.top_radius = L * 0.024
			cyl2.bottom_radius = L * 0.014
			cyl2.height = L * 0.36
			cyl2.radial_segments = 6
			cyl2.material = leg_mat
			tibia.mesh = cyl2
			tibia.position = Vector3(side * L * 0.40, L * 0.16, 0.0)
			tibia.rotation.z = PI + side * 0.30
			hip.add_child(tibia)


func _animate(delta: float) -> void:
	var want := 0.70 if walking else 0.0
	_amp = lerpf(_amp, want, minf(1.0, delta * 8.0))
	for i in hips.size():
		var off: float = PI if TRIPOD_A.has(i) else 0.0
		var s := sin(phase + off)
		hips[i].rotation.y = s * _amp
		hips[i].rotation.z = leg_sides[i] * maxf(0.0, s) * _amp * 0.85
	var bob := 0.0
	if walking:
		bob = absf(sin(phase * 2.0)) * size * 0.06
	body_node.position.y = lerpf(body_node.position.y, bob, minf(1.0, delta * 10.0))
	if not walking:
		var br := 1.0 + sin(phase * 0.45) * 0.025
		abdomen.scale = Vector3(1.0, 0.75, 1.2) * br
