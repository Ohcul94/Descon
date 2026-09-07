class_name EntityMechanicsVFX
extends Node

# EntityMechanicsVFX.gd - Submódulo desacoplado de Entity.gd para:
# - Acciones y mecánicas visuales de combate de jefes (Survival Dome, Wall Dome, Bomb, Reflect, Orbital Strike)
# - Auras 3D (Daño, Curación, Velocidad)
# - Auras de Color y Pilares (Puzzle de Colores)
# - Setup visual de Orbe de Agua 3D

var entity: CharacterBody2D = null

const ColorBeamShader = preload("res://resources/shaders/color_beam.gdshader")
const ColorAuraShader = preload("res://resources/shaders/color_aura.gdshader")
const VFX_HexTexture = preload("res://VFX/textures/T_Hex1_inv.jpg")
const VFX_SmokeTexture = preload("res://VFX/textures/T_VFX_Smoke_4_alpha.PNG")
const VFX_FlareTexture = preload("res://VFX/textures/T_VFX_Flare_15.PNG")
const VFX_WaterNormalTexture = preload("res://VFX/textures/T_GW_WaterNormal_01_b.PNG")
const TEX_REFLECT_AURA = preload("res://assets/Efectos de Skills/Reflect (Rojo)/Reflect Aura (Transp).png")
const TEX_REFLECT_IMPACT = preload("res://assets/Efectos de Skills/Reflect (Rojo)/Reflect (Transp).png")

var _color_aura_3d_root: Node3D = null

func setup(entity_ref: CharacterBody2D) -> void:
	entity = entity_ref

# ==============================================================================
# 1. ENEMY ACTION (Acciones de Combate de Enemigos / Jefes)
# ==============================================================================
func handle_enemy_action(data: Dictionary) -> void:
	if not is_instance_valid(entity): return
	if str(data.get("id", "")) != entity.entity_id: return
	var action = str(data.get("action", ""))

	match action:
		"orbital_strike_start": 
			entity.set("_is_orbital_active", true)
		"orbital_strike_static":
			stop_orbital_orbit()
		"orbital_strike_fire": 
			entity.set("_is_orbital_active", false)
			fire_orbital_strike()
		"survival_dome_charging":
			entity._active_survival_dome = {
				"safe_pos": Vector2(float(data.get("safeX", 0.0)), float(data.get("safeY", 0.0))),
				"safe_radius": float(data.get("safeRadius", 150.0)),
				"fire_range": float(data.get("fireRange", 800.0)),
				"duration": float(data.get("duration", 3000.0)) / 1000.0,
				"time_elapsed": 0.0
			}
			entity.queue_redraw()
			if is_instance_valid(entity.world_root_3d):
				var map_node = get_tree().get_first_node_in_group("map")
				if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
					var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
					var correction_z = map_node.correction_z if "correction_z" in map_node else 1.41421356
					var dome_3d = Node3D.new()
					dome_3d.name = "Dome3D_" + entity.entity_id
					entity.world_root_3d.add_child(dome_3d)
					var fire_r3d = entity._active_survival_dome.fire_range * s_factor
					var danger_disc = MeshInstance3D.new()
					var disc_mesh = CylinderMesh.new()
					disc_mesh.top_radius = 0.01
					disc_mesh.bottom_radius = 0.01
					disc_mesh.height = 0.02
					danger_disc.mesh = disc_mesh
					var d_mat = StandardMaterial3D.new()
					d_mat.albedo_color = Color(1.0, 0.1, 0.0, 0.25)
					d_mat.emission_enabled = true
					d_mat.emission = Color(1.0, 0.15, 0.0)
					d_mat.emission_energy_multiplier = 1.5
					d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					d_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					danger_disc.material_override = d_mat
					danger_disc.position.y = 0.01
					dome_3d.add_child(danger_disc)
					dome_3d.set_meta("danger_disc", danger_disc)
					dome_3d.set_meta("fire_r3d", fire_r3d)
					var outer_ring = MeshInstance3D.new()
					var ring_mesh = TorusMesh.new()
					ring_mesh.inner_radius = fire_r3d - 0.02
					ring_mesh.outer_radius = fire_r3d + 0.02
					outer_ring.mesh = ring_mesh
					var ring_mat = StandardMaterial3D.new()
					ring_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.5)
					ring_mat.emission_enabled = true
					ring_mat.emission = Color(1.0, 0.1, 0.1)
					ring_mat.emission_energy_multiplier = 2.0
					ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					outer_ring.material_override = ring_mat
					outer_ring.rotation.x = PI / 2
					dome_3d.add_child(outer_ring)
					var safe_pos = entity._active_survival_dome.safe_pos
					var safe_r3d = entity._active_survival_dome.safe_radius * s_factor
					var boss_2d = entity.global_position
					var offset_x = (safe_pos.x - boss_2d.x) * s_factor
					var offset_z = (safe_pos.y - boss_2d.y) * s_factor * correction_z
					var safe_node = Node3D.new()
					safe_node.name = "SafeDome3D"
					safe_node.position = Vector3(offset_x, 0.0, offset_z)
					dome_3d.add_child(safe_node)
					var dome_hemi = MeshInstance3D.new()
					var hemi_mesh = SphereMesh.new()
					hemi_mesh.radius = safe_r3d
					hemi_mesh.height = safe_r3d * 1.8
					hemi_mesh.is_hemisphere = true
					dome_hemi.mesh = hemi_mesh
					var h_mat = StandardMaterial3D.new()
					h_mat.albedo_color = Color(0.0, 1.0, 0.5, 0.15)
					h_mat.emission_enabled = true
					h_mat.emission = Color(0.0, 1.0, 0.5)
					h_mat.emission_energy_multiplier = 2.0
					h_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					h_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					dome_hemi.material_override = h_mat
					dome_hemi.position.y = 0.0
					safe_node.add_child(dome_hemi)
					var dome_light = OmniLight3D.new()
					dome_light.light_color = Color(0.0, 1.0, 0.5)
					dome_light.light_energy = 4.0
					dome_light.omni_range = safe_r3d * 2.5
					dome_light.position.y = safe_r3d * 0.5
					safe_node.add_child(dome_light)
					var safe_disc = MeshInstance3D.new()
					var sd_mesh = CylinderMesh.new()
					sd_mesh.top_radius = safe_r3d
					sd_mesh.bottom_radius = safe_r3d
					sd_mesh.height = 0.015
					safe_disc.mesh = sd_mesh
					var sd_mat = StandardMaterial3D.new()
					sd_mat.albedo_color = Color(0.0, 0.8, 1.0, 0.25)
					sd_mat.emission_enabled = true
					sd_mat.emission = Color(0.0, 0.8, 1.0)
					sd_mat.emission_energy_multiplier = 2.0
					sd_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					sd_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					safe_disc.material_override = sd_mat
					safe_disc.position.y = 0.016
					safe_node.add_child(safe_disc)
					safe_node.set_meta("safe_disc", safe_disc)
					entity._active_survival_dome["dome_3d"] = dome_3d
					entity._active_survival_dome["s_factor"] = s_factor
					entity._active_survival_dome["correction_z"] = correction_z
					entity._active_survival_dome["fire_r3d"] = fire_r3d
					entity.tree_exiting.connect(func():
						if is_instance_valid(dome_3d):
							dome_3d.queue_free()
					)
		"survival_dome_fire":
			var dome_3d_ref = entity._active_survival_dome.get("dome_3d")
			if is_instance_valid(dome_3d_ref):
				var map_node = get_tree().get_first_node_in_group("map")
				if is_instance_valid(map_node) and map_node.get("sub_viewport") != null:
					var vp = map_node.sub_viewport
					var fire_r3d = entity._active_survival_dome.get("fire_r3d", entity._active_survival_dome.fire_range * 0.02)
					var boss_3d = entity.world_root_3d.position if is_instance_valid(entity.world_root_3d) else Vector3.ZERO
					var flash = MeshInstance3D.new()
					var flash_s = SphereMesh.new()
					flash_s.radius = fire_r3d * 0.3
					flash_s.height = fire_r3d * 0.6
					flash.mesh = flash_s
					var flash_mat = StandardMaterial3D.new()
					flash_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
					flash_mat.emission_enabled = true
					flash_mat.emission = Color(1.0, 0.5, 0.1)
					flash_mat.emission_energy_multiplier = 10.0
					flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					flash.material_override = flash_mat
					flash.position = boss_3d
					flash.position.y = 0.1
					vp.add_child(flash)
					var tw_f = flash.create_tween()
					tw_f.tween_property(flash, "scale", Vector3(4.0, 4.0, 4.0), 0.35)
					tw_f.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 0.35)
					tw_f.parallel().tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.35)
					tw_f.finished.connect(flash.queue_free)
					var damage_area = MeshInstance3D.new()
					var area_mesh = CylinderMesh.new()
					area_mesh.top_radius = fire_r3d
					area_mesh.bottom_radius = fire_r3d
					area_mesh.height = 0.01
					damage_area.mesh = area_mesh
					var area_mat = StandardMaterial3D.new()
					area_mat.albedo_color = Color(1.0, 0.15, 0.0, 0.5)
					area_mat.emission_enabled = true
					area_mat.emission = Color(1.0, 0.2, 0.0)
					area_mat.emission_energy_multiplier = 3.0
					area_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					area_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					damage_area.material_override = area_mat
					damage_area.position = boss_3d
					damage_area.position.y = 0.01
					vp.add_child(damage_area)
					var tw_a = damage_area.create_tween().set_parallel(true)
					tw_a.tween_property(area_mat, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
					tw_a.tween_property(area_mat, "emission_energy_multiplier", 0.0, 0.5).set_ease(Tween.EASE_IN)
					tw_a.finished.connect(damage_area.queue_free)
					var shockwave = MeshInstance3D.new()
					var sw_mesh = TorusMesh.new()
					sw_mesh.inner_radius = fire_r3d * 0.95
					sw_mesh.outer_radius = fire_r3d * 1.05
					shockwave.mesh = sw_mesh
					var sw_mat = StandardMaterial3D.new()
					sw_mat.albedo_color = Color(1.0, 0.4, 0.05, 0.9)
					sw_mat.emission_enabled = true
					sw_mat.emission = Color(1.0, 0.4, 0.05)
					sw_mat.emission_energy_multiplier = 5.0
					sw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					sw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					shockwave.material_override = sw_mat
					shockwave.position = boss_3d
					shockwave.position.y = 0.02
					shockwave.rotation.x = PI / 2
					vp.add_child(shockwave)
					var tw_sw = shockwave.create_tween().set_parallel(true)
					tw_sw.tween_property(shockwave, "scale", Vector3(1.5, 1.5, 1.5), 0.4)
					tw_sw.tween_property(sw_mat, "albedo_color:a", 0.0, 0.4)
					tw_sw.tween_property(sw_mat, "emission_energy_multiplier", 0.0, 0.4)
					tw_sw.finished.connect(shockwave.queue_free)
					var exp_light = OmniLight3D.new()
					exp_light.light_color = Color(1.0, 0.4, 0.05)
					exp_light.light_energy = 15.0
					exp_light.omni_range = fire_r3d * 2.0
					exp_light.position = boss_3d
					exp_light.position.y = 0.5
					vp.add_child(exp_light)
					var tw_l = exp_light.create_tween()
					tw_l.tween_property(exp_light, "light_energy", 0.0, 0.4)
					tw_l.finished.connect(exp_light.queue_free)
				dome_3d_ref.queue_free()
			entity._active_survival_dome.clear()
			entity.queue_redraw()
			if entity.has_method("_trigger_hit_flash"):
				entity._trigger_hit_flash()
		"wall_dome_start":
			var mId = data.get("mId", "wall_dome")
			if not entity.active_auras.has(mId):
				var spr = Sprite2D.new()
				if TEX_REFLECT_AURA:
					spr.texture = TEX_REFLECT_AURA
				spr.modulate = Color(0.0, 0.6, 1.0, 0.45)
				var radius = float(data.get("radius", 300.0))
				var target_scale = (radius * 2.0) / 512.0
				spr.scale = Vector2.ZERO
				entity._vfx_container_2d.add_child(spr)
				entity.active_auras[mId] = {"node": spr, "target_scale": target_scale, "type": "wall_dome", "radius": radius}
				var tw = create_tween()
				tw.tween_property(spr, "scale", Vector2(target_scale, target_scale), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				entity.queue_redraw()
		"wall_dome_end":
			var mId = data.get("mId", "wall_dome")
			if entity.active_auras.has(mId):
				var a_data = entity.active_auras[mId]
				var spr = a_data.node
				entity.active_auras.erase(mId)
				var tw = create_tween()
				tw.tween_property(spr, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
				tw.finished.connect(spr.queue_free)
				entity.queue_redraw()
		"throw_bomb":
			var world = get_tree().get_first_node_in_group("world_node")
			if world and world.has_method("get_node"):
				var cs = world.get_node_or_null("CombatSystem")
				if is_instance_valid(cs):
					var s_x = float(data.get("startX", entity.global_position.x))
					var s_y = float(data.get("startY", entity.global_position.y))
					var t_x = float(data.get("targetX", 0.0))
					var t_y = float(data.get("targetY", 0.0))
					var start_pos = Vector2(s_x, s_y)
					var target_pos = Vector2(t_x, t_y)
					var dist = start_pos.distance_to(target_pos)
					var travel_time = float(data.get("travelTimeMs", 1000.0)) / 1000.0
					var speed_val = dist / max(0.01, travel_time)
					var angle_val = start_pos.angle_to_point(target_pos)
					
					var proj_data = {
						"bulletType": "electron",
						"type": "electron",
						"x": s_x,
						"y": s_y,
						"range": dist,
						"bulletSpeed": speed_val,
						"angle": angle_val,
						"enemyId": entity.entity_id,
						"id": entity.entity_id,
						"lifetimeMs": float(data.get("travelTimeMs", 1000.0)),
						"radius": float(data.get("radius", 150.0)),
						"explosionRadius": float(data.get("radius", 150.0))
					}
					cs._spawn_projectile(proj_data, "enemy")
		"bomb_explode":
			var bx = float(data.get("x", 0.0))
			var by = float(data.get("y", 0.0))
			var radius = float(data.get("radius", 150.0))
			var scale_factor = radius / 100.0
			if is_instance_valid(VFXSystem):
				VFXSystem.spawn_explosion(Vector2(bx, by), scale_factor)
			var map_node = get_tree().get_first_node_in_group("map")
			if is_instance_valid(map_node) and map_node.get("sub_viewport") != null and is_instance_valid(entity.world_root_3d):
				var s_factor = map_node.scale_factor if "scale_factor" in map_node else 0.02
				var correction_z = map_node.correction_z if "correction_z" in map_node else 1.41421356
				var vp = map_node.sub_viewport
				var h_bomb = 0.08
				if is_instance_valid(map_node.get("terrain_node")):
					var em_n = get_tree().get_first_node_in_group("world_node")
					if em_n and em_n.has_node("EntityManager"):
						var mgr_b = em_n.get_node("EntityManager")
						if mgr_b and mgr_b.has_method("_sample_terrain_height"):
							h_bomb = mgr_b._sample_terrain_height(Vector2(bx,by), map_node) + 0.06
						elif map_node.has_method("get_terrain_height_at_pos"):
							h_bomb = map_node.get_terrain_height_at_pos(Vector2(bx,by)) + 0.06
					elif map_node.has_method("get_terrain_height_at_pos"):
						h_bomb = map_node.get_terrain_height_at_pos(Vector2(bx,by)) + 0.06
				var pos_3d = Vector3(bx * s_factor, h_bomb, by * s_factor * correction_z)

				var flash = MeshInstance3D.new()
				var flash_s = SphereMesh.new()
				var r3d = radius * 0.02
				flash_s.radius = r3d * 0.3
				flash_s.height = r3d * 0.6
				flash.mesh = flash_s
				var flash_mat = StandardMaterial3D.new()
				flash_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
				flash_mat.emission_enabled = true
				flash_mat.emission = Color(1.0, 0.5, 0.1)
				flash_mat.emission_energy_multiplier = 8.0
				flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				flash.material_override = flash_mat
				flash.position = pos_3d
				vp.add_child(flash)
				var tw_f = flash.create_tween()
				tw_f.tween_property(flash, "scale", Vector3(2.5, 2.5, 2.5), 0.3)
				tw_f.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 0.3)
				tw_f.parallel().tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.3)
				tw_f.finished.connect(flash.queue_free)

				var shockwave = MeshInstance3D.new()
				var ring_mesh = TorusMesh.new()
				ring_mesh.inner_radius = r3d * 0.5
				ring_mesh.outer_radius = r3d * 0.55
				shockwave.mesh = ring_mesh
				var sw_mat = StandardMaterial3D.new()
				sw_mat.albedo_color = Color(1.0, 0.4, 0.05, 0.8)
				sw_mat.emission_enabled = true
				sw_mat.emission = Color(1.0, 0.4, 0.05)
				sw_mat.emission_energy_multiplier = 3.0
				sw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				shockwave.material_override = sw_mat
				shockwave.position = pos_3d + Vector3(0,0.02,0)
				vp.add_child(shockwave)
				var tw_sw = shockwave.create_tween()
				tw_sw.tween_property(shockwave, "scale", Vector3(2.5, 2.5, 2.5), 0.35)
				tw_sw.parallel().tween_property(sw_mat, "albedo_color:a", 0.0, 0.35)
				tw_sw.parallel().tween_property(sw_mat, "emission_energy_multiplier", 0.0, 0.35)
				tw_sw.finished.connect(shockwave.queue_free)
		"reflect_start":
			entity.reflect_timer = float(data.get("duration", 3000.0)) / 1000.0
			print("[REFLECT-IN] Enemigo activó reflect por ", entity.reflect_timer, "s")
		"reflect_end":
			entity.reflect_timer = 0.0
			print("[REFLECT-IN] Enemigo desactivó reflect")
		"reflect_trigger":
			var target_id = str(data.get("targetId", ""))
			var target_node = null
			if target_id != "":
				for ent in get_tree().get_nodes_in_group("entities"):
					if str(ent.get("entity_id")) == target_id:
						target_node = ent; break
				if not target_node:
					var local_player = get_tree().get_first_node_in_group("player")
					if local_player and str(local_player.get("entity_id")) == target_id:
						target_node = local_player
			
			var visual_target = Vector2.ZERO
			if target_node: visual_target = target_node.global_position
			if entity.has_method("_trigger_reflect_visual"):
				entity._trigger_reflect_visual(visual_target if visual_target != Vector2.ZERO else entity.global_position + Vector2.UP)

func stop_orbital_orbit() -> void:
	if not is_instance_valid(entity): return
	var projs = get_tree().get_nodes_in_group("projectiles")
	for p in projs:
		if is_instance_valid(p) and str(p.get("owner_id")) == entity.entity_id:
			if p.has_method("stop_orbit"):
				p.stop_orbit()

func fire_orbital_strike() -> void:
	if not is_instance_valid(entity): return
	var projs = get_tree().get_nodes_in_group("projectiles")
	for p in projs:
		if is_instance_valid(p) and str(p.get("owner_id")) == entity.entity_id:
			if p.has_method("release_orbit"):
				p.release_orbit()

# ==============================================================================
# 2. ENEMY AURA (Auras 3D de Estado / Buffs)
# ==============================================================================
func handle_enemy_aura(data: Dictionary) -> void:
	if not is_instance_valid(entity) or entity.is_queued_for_deletion(): return
	if str(data.get("id", "")) != entity.entity_id: return

	var mId = data.get("mId", "")
	if data.get("active", false):
		if entity.active_auras.has(mId): return
		
		var radius = data.get("radius", 200)
		entity.active_auras[mId] = {"type": data.get("type", ""), "radius": radius, "start_time_3d": Time.get_ticks_msec() / 1000.0}
		
		var current_map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(current_map) and is_instance_valid(current_map.get("sub_viewport")):
			var s_factor = current_map.scale_factor if "scale_factor" in current_map else 0.02
			var correction_z = current_map.correction_z if "correction_z" in current_map else 1.41421356
			var radius_3d = radius * s_factor
			
			var tex_hex = VFX_HexTexture
			var tex_smoke = VFX_SmokeTexture
			var tex_flare = VFX_FlareTexture
			
			var shader = Shader.new()
			shader.code = """shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 scroll_speed = vec2(0.0, -0.5);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float fade_exponent = 2.0;

void fragment() {
	vec2 uv = UV * uv_scale + scroll_speed * TIME;
	vec4 tex = texture(albedo_texture, uv);
	float vertical_fade = sin(UV.y * 3.14159265);
	vertical_fade = pow(vertical_fade, fade_exponent);
	ALBEDO = albedo_color.rgb * tex.rgb;
	ALPHA = albedo_color.a * tex.a * vertical_fade;
}"""
			
			var aura_3d = Node3D.new()
			aura_3d.name = "Aura3D_" + mId
			current_map.sub_viewport.add_child(aura_3d)
			
			aura_3d.position.x = entity.global_position.x * s_factor
			aura_3d.position.z = entity.global_position.y * s_factor * correction_z
			aura_3d.position.y = 0.01
			aura_3d.scale = Vector3(0.01, 0.01, 0.01)
			
			var aura_color = Color(1.0, 0.05, 0.1, 0.75)
			if data.get("type") == "aura_heal": aura_color = Color(0.05, 1.0, 0.35, 0.75)
			elif data.get("type") == "aura_speed": aura_color = Color(1.0, 0.75, 0.0, 0.75)
			
			var cyl_outer = MeshInstance3D.new()
			var mesh_outer = CylinderMesh.new()
			mesh_outer.top_radius = radius_3d * 0.75
			mesh_outer.bottom_radius = radius_3d * 1.15
			mesh_outer.height = radius_3d * 2.6
			mesh_outer.cap_top = false
			mesh_outer.cap_bottom = false
			cyl_outer.mesh = mesh_outer
			
			var mat_outer = ShaderMaterial.new()
			mat_outer.shader = shader
			mat_outer.set_shader_parameter("albedo_texture", tex_hex)
			mat_outer.set_shader_parameter("scroll_speed", Vector2(0.0, -0.2))
			mat_outer.set_shader_parameter("uv_scale", Vector2(4.0, 2.0))
			mat_outer.set_shader_parameter("fade_exponent", 1.8)
			cyl_outer.material_override = mat_outer
			cyl_outer.position.y = mesh_outer.height / 2.0
			aura_3d.add_child(cyl_outer)
			
			var cyl_inner = MeshInstance3D.new()
			var mesh_inner = CylinderMesh.new()
			mesh_inner.top_radius = radius_3d * 0.65
			mesh_inner.bottom_radius = radius_3d * 1.0
			mesh_inner.height = radius_3d * 2.6
			mesh_inner.cap_top = false
			mesh_inner.cap_bottom = false
			cyl_inner.mesh = mesh_inner
			
			var mat_inner = ShaderMaterial.new()
			mat_inner.shader = shader
			mat_inner.set_shader_parameter("albedo_texture", tex_smoke)
			mat_inner.set_shader_parameter("scroll_speed", Vector2(0.0, -0.45))
			mat_inner.set_shader_parameter("uv_scale", Vector2(2.5, 1.5))
			mat_inner.set_shader_parameter("fade_exponent", 2.2)
			cyl_inner.material_override = mat_inner
			cyl_inner.position.y = mesh_inner.height / 2.0
			aura_3d.add_child(cyl_inner)
			
			var particles = CPUParticles3D.new()
			particles.name = "AuraParticles_" + mId
			current_map.sub_viewport.add_child(particles)
			
			particles.position.x = entity.global_position.x * s_factor
			particles.position.z = entity.global_position.y * s_factor * correction_z
			particles.position.y = 0.05
			particles.scale = Vector3(0.01, 0.01, 0.01)
			
			particles.amount = 70
			particles.lifetime = 1.6
			particles.preprocess = 0.8
			particles.randomness = 0.4
			particles.direction = Vector3.UP
			particles.gravity = Vector3.ZERO
			particles.initial_velocity_min = 1.0
			particles.initial_velocity_max = 2.2
			particles.spread = 10.0
			
			particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			particles.emission_ring_axis = Vector3.UP
			particles.emission_ring_radius = radius_3d * 0.9
			particles.emission_ring_inner_radius = radius_3d * 0.4
			particles.emission_ring_height = 0.1
			particles.scale_amount_min = 0.08
			particles.scale_amount_max = 0.22
			
			var s_curve = Curve.new()
			s_curve.add_point(Vector2(0, 0.1))
			s_curve.add_point(Vector2(0.2, 1.0))
			s_curve.add_point(Vector2(0.8, 0.6))
			s_curve.add_point(Vector2(1.0, 0.0))
			particles.scale_amount_curve = s_curve
			
			var grad = Gradient.new()
			var part_c = aura_color
			part_c.a = 0.8
			var trans_c = aura_color
			trans_c.a = 0.0
			grad.set_color(0, Color(part_c.r, part_c.g, part_c.b, 0.0))
			grad.add_point(0.2, part_c)
			grad.add_point(0.8, Color(part_c.r * 1.5, part_c.g * 1.2, part_c.b, 0.6))
			grad.set_color(1, trans_c)
			particles.color_ramp = grad
			
			var p_mesh = QuadMesh.new()
			p_mesh.size = Vector2(0.4, 0.4)
			particles.mesh = p_mesh
			
			var p_mat = StandardMaterial3D.new()
			p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			p_mat.vertex_color_use_as_albedo = true
			p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			if tex_flare:
				p_mat.albedo_texture = tex_flare
			particles.material_override = p_mat
			
			var target_color_outer = aura_color
			target_color_outer.a = 0.5
			var target_color_inner = Color(aura_color.r * 0.8, aura_color.g * 0.8, aura_color.b, 0.45)
			
			var start_color_outer = target_color_outer
			start_color_outer.a = 0.0
			var start_color_inner = target_color_inner
			start_color_inner.a = 0.0
			
			mat_outer.set_shader_parameter("albedo_color", start_color_outer)
			mat_inner.set_shader_parameter("albedo_color", start_color_inner)
			
			var tw_in = create_tween().set_parallel(true)
			tw_in.tween_property(aura_3d, "scale", Vector3(1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw_in.tween_property(particles, "scale", Vector3(1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw_in.tween_method(func(c): mat_outer.set_shader_parameter("albedo_color", c), start_color_outer, target_color_outer, 0.4)
			tw_in.tween_method(func(c): mat_inner.set_shader_parameter("albedo_color", c), start_color_inner, target_color_inner, 0.4)
			
			entity.active_auras[mId]["node_3d"] = aura_3d
			entity.active_auras[mId]["particles_3d"] = particles
			entity.active_auras[mId]["mat_outer"] = mat_outer
			entity.active_auras[mId]["mat_inner"] = mat_inner
			entity.active_auras[mId]["s_factor"] = s_factor
			entity.active_auras[mId]["correction_z"] = correction_z
			entity.active_auras[mId]["radius_3d"] = radius_3d
	
	else:
		if entity.active_auras.has(mId):
			var a_data = entity.active_auras[mId]
			entity.active_auras.erase(mId)
			
			if a_data.has("node_3d") and is_instance_valid(a_data.node_3d):
				var m_outer = a_data.get("mat_outer")
				var m_inner = a_data.get("mat_inner")
				
				var tw_out = create_tween().set_parallel(true)
				if is_instance_valid(m_outer):
					var current_c_outer = m_outer.get_shader_parameter("albedo_color")
					var target_c_outer = current_c_outer
					target_c_outer.a = 0.0
					tw_out.tween_method(func(c): m_outer.set_shader_parameter("albedo_color", c), current_c_outer, target_c_outer, 0.4)
				if is_instance_valid(m_inner):
					var current_c_inner = m_inner.get_shader_parameter("albedo_color")
					var target_c_inner = current_c_inner
					target_c_inner.a = 0.0
					tw_out.tween_method(func(c): m_inner.set_shader_parameter("albedo_color", c), current_c_inner, target_c_inner, 0.4)
				
				if a_data.has("particles_3d") and is_instance_valid(a_data.particles_3d):
					tw_out.tween_property(a_data.particles_3d, "scale", Vector3.ZERO, 0.4)
				
				var tw_cleanup = create_tween()
				tw_cleanup.tween_interval(0.45)
				tw_cleanup.tween_callback(a_data.node_3d.queue_free)
				if a_data.has("particles_3d") and is_instance_valid(a_data.particles_3d):
					tw_cleanup.tween_callback(a_data.particles_3d.queue_free)
			else:
				if a_data.has("particles_3d") and is_instance_valid(a_data.particles_3d):
					a_data.particles_3d.queue_free()

func update_auras(delta: float) -> void:
	if not is_instance_valid(entity): return
	var now = Time.get_ticks_msec() / 1000.0
	for mId in entity.active_auras:
		var a_data = entity.active_auras[mId]
		
		if a_data.has("node") and is_instance_valid(a_data.node):
			var pulse = 1.0 + sin(now * 4.0) * 0.05
			var s = a_data.get("target_scale", 1.0) * pulse
			a_data.node.scale = Vector2(s, s)
			a_data.node.rotate(delta * 0.5)
			if a_data.get("type") == "wall_dome":
				entity.queue_redraw()
		
		if a_data.has("node_3d") and is_instance_valid(a_data.node_3d):
			var s_factor = a_data.get("s_factor", 0.02)
			var correction_z = a_data.get("correction_z", 1.41421356)
			a_data.node_3d.position.x = entity.global_position.x * s_factor
			a_data.node_3d.position.z = entity.global_position.y * s_factor * correction_z
		
		if a_data.has("particles_3d") and is_instance_valid(a_data.particles_3d):
			var s_factor = a_data.get("s_factor", 0.02)
			var correction_z = a_data.get("correction_z", 1.41421356)
			a_data.particles_3d.position.x = entity.global_position.x * s_factor
			a_data.particles_3d.position.z = entity.global_position.y * s_factor * correction_z

# ==============================================================================
# 3. COLOR AURA (Pilares y Puzzle de Colores)
# ==============================================================================
func apply_color_aura(color_name: String) -> void:
	if not is_instance_valid(entity): return
	remove_color_aura()
	
	var clr = Color.WHITE
	match color_name.to_lower():
		"roja": clr = Color("#ff003c")
		"azul": clr = Color("#00aaff")
		"verde": clr = Color("#00ff66")
		"amarilla": clr = Color("#ffdd00")
		"violeta": clr = Color("#d400ff")
		
	var pivot = entity.accessory_pivot_3d if is_instance_valid(entity.accessory_pivot_3d) else entity.world_root_3d
	if not is_instance_valid(pivot):
		return
	
	var s_factor = entity.get_meta("map_scale", 0.02)
	var base_r: float
	if entity.entity_type >= 101:
		base_r = 180.0
	elif entity.entity_type == 200 or "pillar" in entity.entity_id:
		base_r = 100.0
	else:
		base_r = 70.0
	var r = base_r * s_factor
	
	var aura_root = Node3D.new()
	aura_root.name = "ColorAuraVFX"
	pivot.add_child(aura_root)
	_color_aura_3d_root = aura_root
	
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = r * 0.85
	ring_mesh.outer_radius = r * 1.2
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 32
	
	var ring = MeshInstance3D.new()
	ring.mesh = ring_mesh
	
	var ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.albedo_color = Color(clr.r, clr.g, clr.b, 0.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = clr
	ring_mat.emission_energy_multiplier = 4.0
	ring.material_override = ring_mat
	ring.position = Vector3(0, -0.02, 0)
	aura_root.add_child(ring)
	
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = r * 0.95
	cylinder_mesh.bottom_radius = r * 1.15
	cylinder_mesh.height = r * 4.0
	cylinder_mesh.radial_segments = 32
	cylinder_mesh.rings = 4
	cylinder_mesh.cap_top = false
	cylinder_mesh.cap_bottom = false
	
	var cylinder = MeshInstance3D.new()
	cylinder.mesh = cylinder_mesh
	
	var beam_mat = ShaderMaterial.new()
	beam_mat.shader = ColorBeamShader
	beam_mat.set_shader_parameter("beam_color", Color(clr.r, clr.g, clr.b, 0.0))
	beam_mat.set_shader_parameter("speed", 1.6)
	beam_mat.set_shader_parameter("scale_y", 6.0)
	beam_mat.set_shader_parameter("scale_x", 20.0)
	beam_mat.set_shader_parameter("fresnel_power", 2.2)
	cylinder.material_override = beam_mat
	cylinder.position = Vector3(0, r * 2.0, 0)
	aura_root.add_child(cylinder)
	
	var tex_flare = VFX_FlareTexture
	var particles = CPUParticles3D.new()
	particles.amount = 35
	particles.lifetime = 1.8
	particles.preprocess = 0.5
	particles.randomness = 0.4
	particles.direction = Vector3.UP
	particles.gravity = Vector3(0, 0.2, 0)
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 2.0
	particles.spread = 15.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_radius = r * 0.9
	particles.emission_ring_inner_radius = r * 0.3
	particles.emission_ring_height = 0.1
	particles.scale_amount_min = 0.08
	particles.scale_amount_max = 0.2
	
	var s_curve = Curve.new()
	s_curve.add_point(Vector2(0, 0.1))
	s_curve.add_point(Vector2(0.2, 1.0))
	s_curve.add_point(Vector2(0.8, 0.6))
	s_curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = s_curve
	
	var grad = Gradient.new()
	grad.set_color(0, Color(clr.r, clr.g, clr.b, 0.0))
	grad.add_point(0.2, Color(clr.r, clr.g, clr.b, 0.8))
	grad.add_point(0.8, Color(clr.r * 1.3, clr.g * 1.3, clr.b * 1.3, 0.6))
	grad.set_color(1, Color(clr.r, clr.g, clr.b, 0.0))
	particles.color_ramp = grad
	
	var p_mesh = QuadMesh.new()
	p_mesh.size = Vector2(0.35, 0.35)
	particles.mesh = p_mesh
	
	var p_mat = StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p_mat.vertex_color_use_as_albedo = true
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if tex_flare:
		p_mat.albedo_texture = tex_flare
	particles.material_override = p_mat
	aura_root.add_child(particles)
	
	var light = OmniLight3D.new()
	light.light_color = clr
	light.light_energy = 0.0
	light.omni_range = r * 5.0
	light.position = Vector3(0, r * 1.5, 0)
	aura_root.add_child(light)
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(ring_mat, "albedo_color:a", 0.7, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(c): beam_mat.set_shader_parameter("beam_color", c), Color(clr.r, clr.g, clr.b, 0.0), Color(clr.r, clr.g, clr.b, 0.6), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "light_energy", 3.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func remove_color_aura() -> void:
	if is_instance_valid(_color_aura_3d_root):
		_color_aura_3d_root.queue_free()
		_color_aura_3d_root = null

# ==============================================================================
# 4. WATER ORB 3D (Boss Marino / Orbe Acuático)
# ==============================================================================
func setup_water_orb_3d() -> void:
	if not is_instance_valid(entity): return
	var current_map = get_tree().get_first_node_in_group("map")
	var is_single_world = false
	var target_viewport = null
	var map_scale_val = 0.02

	if is_instance_valid(current_map):
		if "sub_viewport" in current_map and is_instance_valid(current_map.sub_viewport):
			is_single_world = true
			target_viewport = current_map.sub_viewport
			if "scale_factor" in current_map:
				map_scale_val = current_map.scale_factor

	entity.set_meta("is_single_world", is_single_world)
	entity.set_meta("map_scale", map_scale_val)

	var viewport = null
	var res = 256
	if not is_single_world:
		var quality = 1
		if get_node_or_null("/root/SettingsManager"):
			quality = SettingsManager.get_graphics_quality()
		match quality:
			0: res = 128
			2: res = 1024
		viewport = SubViewport.new()
		viewport.size = Vector2i(res, res)
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.positional_shadow_atlas_size = 0
		entity.add_child(viewport)
		entity.set("_cached_viewport", viewport)

	if is_instance_valid(entity.sprite):
		entity.sprite.visible = not is_single_world
	else:
		entity.sprite = Sprite2D.new()
		entity.sprite.name = "Ship3DRender"
		entity.sprite.z_index = 10
		entity.add_child(entity.sprite)
		entity.sprite.visible = not is_single_world

	var node3d = Node3D.new()
	if is_single_world:
		target_viewport.add_child(node3d)
	else:
		viewport.add_child(node3d)
	entity.world_root_3d = node3d

	entity.accessory_pivot_3d = Node3D.new()
	entity.accessory_pivot_3d.name = "AccessoryPivot"
	node3d.add_child(entity.accessory_pivot_3d)

	if not is_single_world:
		var env = WorldEnvironment.new()
		var world_env = Environment.new()
		world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_env.ambient_light_color = Color(0.2, 0.2, 0.35)
		world_env.ambient_light_energy = 0.6
		world_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.environment = world_env
		node3d.add_child(env)

		var cam_pivot = Node3D.new()
		node3d.add_child(cam_pivot)
		var cam = Camera3D.new()
		cam_pivot.add_child(cam)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 45.0
		cam.position = Vector3(0, 1.3, 3.3)
		cam.look_at(Vector3(0, 0.1, 0))

		var key = DirectionalLight3D.new()
		node3d.add_child(key)
		key.rotation_degrees = Vector3(-65, 35, 0)
		key.light_energy = 1.5
		key.light_color = Color(1.0, 0.92, 0.85)
		key.light_specular = 0.5
		key.shadow_enabled = false

		var fill = DirectionalLight3D.new()
		node3d.add_child(fill)
		fill.rotation_degrees = Vector3(25, -135, 0)
		fill.light_energy = 0.6
		fill.light_color = Color(0.7, 0.8, 1.0)
		fill.light_specular = 0.3
		fill.shadow_enabled = false

		if is_instance_valid(entity.sprite):
			entity.sprite.texture = viewport.get_texture()
			entity.sprite.scale = Vector2(1024.0 / float(res), 1024.0 / float(res))

	var orb_size = map_scale_val * 100.0
	var water_normal = VFX_WaterNormalTexture

	var water_shader = Shader.new()
	water_shader.code = """shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D normal_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(0.0, 0.6, 1.0, 0.45);
uniform vec4 emission_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float emission_energy = 4.0;
uniform float wave_speed = 0.5;
uniform float wave_strength = 0.3;

void vertex() {
	vec3 pos = VERTEX;
	float w = sin(pos.x * 2.5 + TIME * wave_speed) * wave_strength * 0.08;
	w += sin(pos.y * 3.2 + TIME * wave_speed * 1.2) * wave_strength * 0.06;
	w += sin(pos.z * 2.0 + TIME * wave_speed * 0.8) * wave_strength * 0.07;
	VERTEX = pos + NORMAL * w;
}

void fragment() {
	vec2 uv1 = UV * 2.0 + vec2(TIME * 0.04, TIME * 0.02);
	vec2 uv2 = UV * 3.0 + vec2(TIME * -0.03, TIME * 0.05);
	vec3 n1 = texture(normal_map, uv1).rgb - 0.5;
	vec3 n2 = texture(normal_map, uv2).rgb - 0.5;
	vec3 n = normalize(n1 + n2);
	vec3 view_dir = normalize(VIEW);
	float fresnel = pow(1.0 - abs(dot(view_dir, n)), 2.5);
	float ripple = sin(UV.x * 25.0 + UV.y * 18.0 + TIME * 2.5) * 0.5 + 0.5;
	ALBEDO = albedo_color.rgb;
	ALPHA = albedo_color.a * (0.5 + fresnel * 0.5);
	EMISSION = emission_color.rgb * emission_energy * (0.6 + fresnel * 1.2 + ripple * 0.3);
}"""

	var orb_mat = ShaderMaterial.new()
	orb_mat.shader = water_shader
	orb_mat.set_shader_parameter("normal_map", water_normal)
	orb_mat.set_shader_parameter("albedo_color", Color(0.0, 0.6, 1.0, 0.45))
	orb_mat.set_shader_parameter("emission_color", Color(0.0, 0.8, 1.0))
	orb_mat.set_shader_parameter("emission_energy", 4.0)
	orb_mat.set_shader_parameter("wave_speed", 0.5)
	orb_mat.set_shader_parameter("wave_strength", 0.3)

	var orb = MeshInstance3D.new()
	var orb_mesh = SphereMesh.new()
	orb_mesh.radius = orb_size
	orb_mesh.height = orb_size * 2.0
	orb.mesh = orb_mesh
	orb.material_override = orb_mat
	entity.accessory_pivot_3d.add_child(orb)

	var core_mat = StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_mat.albedo_color = Color(0.3, 0.85, 1.0, 0.2)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.2, 0.8, 1.0)
	core_mat.emission_energy_multiplier = 5.0
	core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var core = MeshInstance3D.new()
	var core_mesh = SphereMesh.new()
	core_mesh.radius = orb_size * 0.45
	core_mesh.height = orb_size * 0.9
	core.mesh = core_mesh
	core.material_override = core_mat
	entity.accessory_pivot_3d.add_child(core)

	var tex_flare = VFX_FlareTexture
	var bubbles = CPUParticles3D.new()
	bubbles.amount = 15
	bubbles.lifetime = 2.5
	bubbles.randomness = 0.6
	bubbles.direction = Vector3.UP
	bubbles.gravity = Vector3(0, 0.15, 0)
	bubbles.initial_velocity_min = 0.1
	bubbles.initial_velocity_max = 0.4
	bubbles.spread = 60.0
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bubbles.emission_sphere_radius = orb_size * 1.1
	bubbles.scale_amount_min = 0.015
	bubbles.scale_amount_max = 0.04
	entity.accessory_pivot_3d.add_child(bubbles)

	var b_curve = Curve.new()
	b_curve.add_point(Vector2(0, 0.0))
	b_curve.add_point(Vector2(0.15, 1.0))
	b_curve.add_point(Vector2(0.7, 0.6))
	b_curve.add_point(Vector2(1.0, 0.0))
	bubbles.scale_amount_curve = b_curve

	var b_grad = Gradient.new()
	b_grad.set_color(0, Color(0.8, 1.0, 1.0, 0.0))
	b_grad.add_point(0.15, Color(0.8, 1.0, 1.0, 0.9))
	b_grad.add_point(0.6, Color(0.5, 0.9, 1.0, 0.3))
	b_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	bubbles.color_ramp = b_grad

	var b_mesh = QuadMesh.new()
	b_mesh.size = Vector2(0.12, 0.12)
	bubbles.mesh = b_mesh

	var b_mat = StandardMaterial3D.new()
	b_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	b_mat.vertex_color_use_as_albedo = true
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if tex_flare:
		b_mat.albedo_texture = tex_flare
	bubbles.material_override = b_mat

	var light = OmniLight3D.new()
	light.light_color = Color(0.0, 0.7, 1.0)
	light.light_energy = 1.0
	light.omni_range = orb_size * 4.0
	entity.accessory_pivot_3d.add_child(light)

	var tw = create_tween().set_parallel(true)
	tw.tween_property(orb, "scale", Vector3(1.0, 1.0, 1.0), 0.3).from(Vector3(0.01, 0.01, 0.01)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(core, "scale", Vector3(1.0, 1.0, 1.0), 0.35).from(Vector3(0.01, 0.01, 0.01)).set_delay(0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "light_energy", 1.0, 0.3).from(0.0)
