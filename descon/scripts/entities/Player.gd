extends Entity

# Player.gd (Controlador Maestro v69.45 - FULL STABILITY RECOVERY)
# Saneado y corregido para evitar errores de parseo y autodaño.

@export var speed: float = 300.0
@export var acceleration: float = 1200.0
@export var friction: float = 800.0

var last_sent_pos = Vector2.ZERO
var sync_timer = 0.0
const SYNC_INTERVAL = 0.05 
var save_timer = 0.0
const SAVE_INTERVAL = 10.0

signal stats_changed(p_data)
signal shoot_fired(p_data)

var target_position = Vector2.ZERO
var is_moving = false
var autopilot_enabled: bool = false
var is_autopilot_active: bool: 
	get: return autopilot_enabled
	set(v): autopilot_enabled = v

var hubs: int = 0
var ohculianos: int = 0
var inventory: Array = []
var equipped: Dictionary = {"w": [], "s": [], "e": [], "x": []}
var owned_ships: Array = [1]
var base_laser_damage: float = 100.0
var level: int = 1
var current_exp: float = 0.0
var next_level_exp: float = 1000.0
var skill_tree: Dictionary = {"combat": [], "engineering": []}
var ammo: Dictionary = {"laser": [1000, 0, 0, 0, 0, 0], "missile": [100, 0, 0], "mine": [10, 0, 0]}
var selected_ammo: Dictionary = {"laser": 0, "missile": 0, "mine": 0}
var current_zone: int = 1

func _ready():
	super._ready() 
	add_to_group("player")
	target_position = global_position
	
	collision_layer = 1
	collision_mask = 2
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	
	var cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 5.0
	add_child(cam)
	cam.make_current()
	
	var sm_script = load("res://scripts/systems/SpheresManager.gd")
	if sm_script:
		var sm = sm_script.new()
		sm.name = "SpheresManager"
		add_child(sm)
	
	if NetworkManager:
		NetworkManager.login_success.connect(_on_login_success)
		NetworkManager.inventory_data.connect(_on_inventory_received)
		NetworkManager.enemy_dead.connect(_on_enemy_dead)
		NetworkManager.reward_received.connect(_on_reward_received)
		NetworkManager.level_up.connect(_on_level_up)

func _physics_process(p_delta):
	if not NetworkManager.network_connected: return
	_handle_cooldowns(p_delta)
	
	var chat = get_tree().get_first_node_in_group("chat_ui")
	if not (chat and chat.has_method("is_typing") and chat.is_typing()):
		_handle_input()
		
	_apply_movement()
	_sync_with_server(p_delta)

func _handle_input():
	var mouse_angle = (get_global_mouse_position() - global_position).angle()

	if Input.is_action_just_pressed("fire_laser") and cooldowns["laser"] <= 0:
		_shoot_skill("laser", mouse_angle)
	elif Input.is_action_pressed("fire_laser") and cooldowns["laser"] <= 0:
		_shoot_skill("laser", mouse_angle)
		
	if Input.is_action_just_pressed("fire_missile") and cooldowns["missile"] <= 0:
		_shoot_skill("missile", mouse_angle)
	if Input.is_action_just_pressed("fire_mine") and cooldowns["mine"] <= 0:
		_shoot_skill("mine", mouse_angle)
	
	if Input.is_physical_key_pressed(KEY_A): _use_sphere_skill(0)
	if Input.is_physical_key_pressed(KEY_S): _use_sphere_skill(1)
	if Input.is_physical_key_pressed(KEY_D): _use_sphere_skill(2)
	
func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			target_position = get_global_mouse_position()
			is_moving = true
			autopilot_enabled = false

var cooldowns = {"laser": 0.0, "missile": 0.0, "mine": 0.0, "sphere_0": 0.0, "sphere_1": 0.0, "sphere_2": 0.0}
func _handle_cooldowns(p_delta):
	for s in cooldowns:
		if cooldowns[s] > 0: cooldowns[s] -= p_delta

func _on_inventory_received(p_data):
	var gd = p_data
	if typeof(p_data) == TYPE_DICTIONARY and p_data.has("player"):
		gd = p_data["player"]
		
	if typeof(gd) == TYPE_DICTIONARY:
		if gd.has("items"): inventory = gd["items"]
		elif gd.has("inventory"): inventory = gd["inventory"]
		if gd.has("equipped"): equipped = gd["equipped"]
		if gd.has("hubs"): hubs = int(gd["hubs"])
		if gd.has("ohcu"): ohculianos = int(gd["ohcu"])
		if gd.has("skillTree"):
			skill_tree = gd["skillTree"].duplicate()
			if gd.has("skillPoints"):
				skill_tree["skillPoints"] = int(gd["skillPoints"])
	
	_recalculate_stats()

func _recalculate_stats():
	base_laser_damage = 100.0
	var total_sh_bonus = 0.0
	var total_hp_bonus = 0.0
	var speed_bonus = 0.0
	
	for cat in equipped:
		var slot_list = equipped[cat]
		if typeof(slot_list) != TYPE_ARRAY: continue
		for item in slot_list:
			if typeof(item) != TYPE_DICTIONARY: continue
			var type = str(item.get("type", cat)).to_lower()
			var bonus = float(item.get("base", 0))
			if type == "w" or type == "laser" or cat == "w": base_laser_damage += bonus
			elif type == "s" or type == "shield" or cat == "s": total_sh_bonus += bonus
			elif type == "e" or type == "engine" or cat == "e": speed_bonus += bonus
			elif type == "h" or type == "hp" or cat == "h": total_hp_bonus += bonus
	
	var ship_base = { "hp": 2000, "shield": 1000, "speed": 300 }
	for ship in GameConstants.SHIP_MODELS:
		if ship.id == current_ship_id:
			ship_base = ship
			break
			
	var base_hp_val = float(ship_base.get("hp", 2000)) + total_hp_bonus
	var base_sh_val = float(ship_base.get("shield", 1000)) + total_sh_bonus
	var base_speed_val = float(ship_base.get("speed", 300)) + speed_bonus
	
	var talent_system = get_tree().get_first_node_in_group("talent_system")
	if is_instance_valid(talent_system):
		var bonuses = talent_system.get_bonuses()
		max_hp = base_hp_val * (1.0 + bonuses["hp_pct"])
		max_shield = base_sh_val * (1.0 + bonuses["sh_pct"])
		speed = base_speed_val * (1.0 + bonuses["speed_pct"])
		base_laser_damage *= (1.0 + bonuses["dmg_pct"])
	else:
		max_hp = base_hp_val
		max_shield = base_sh_val
		speed = base_speed_val
	
	save_progress()
	_update_tags()
	_emit_stats()

func take_damage(amt: float):
	super.take_damage(amt)
	if NetworkManager:
		NetworkManager.send_event("playerHitByEnemy", { "damage": amt, "id": entity_id })

func _shoot_skill(p_type: String, p_angle: float):
	last_combat_time = Time.get_ticks_msec()
	if NetworkManager:
		NetworkManager.send_event("playerHitByEnemy", { "damage": 0, "id": entity_id, "attackerType": "combat_ping" })
	
	var t_idx = selected_ammo.get(p_type, 0)
	var current_ammo = 0
	if ammo.has(p_type) and t_idx < ammo[p_type].size():
		current_ammo = ammo[p_type][t_idx]
	
	if current_ammo <= 0: return
		
	ammo[p_type][t_idx] -= 1
	AudioManager.play_sfx(p_type)
	cooldowns[p_type] = 1.0 
	
	is_moving = false
	autopilot_enabled = false
	target_position = global_position
	rotation = p_angle 

	var ammo_mult = 1.0
	var mult_list = GameConstants.AMMO_MULTIPLIERS.get(p_type, [1.0])
	if t_idx < mult_list.size(): ammo_mult = mult_list[t_idx]
	
	var final_damage = base_laser_damage * ammo_mult
	var final_payload = {
		"id": entity_id, "x": global_position.x, "y": global_position.y,
		"angle": p_angle, "rotation": rotation, "type": p_type, "ammoType": t_idx, 
		"senderId": entity_id, "damageBoost": final_damage
	}
	
	shoot_fired.emit(final_payload)
	NetworkManager.send_event("playerFire", final_payload)
	_force_move_sync()

func _use_sphere_skill(id: int):
	var key = "sphere_" + str(id)
	if cooldowns[key] > 0: return
	var sm = get_node_or_null("SpheresManager")
	if not is_instance_valid(sm): return
	if sm.use_skill(id):
		var skill = sm.spheres_data[id]["equipped"]
		if skill:
			NetworkManager.send_event("playerSphereSkill", {
				"id": id, "skillName": skill.skill_name, "powerValue": skill.power_value
			})
		cooldowns[key] = 10.0

func _apply_movement():
	if is_moving:
		var dist = global_position.distance_to(target_position)
		if dist > 15.0:
			var target_angle = (target_position - global_position).angle()
			rotation = lerp_angle(rotation, target_angle, 0.25)
			var dir = Vector2.RIGHT.rotated(rotation)
			velocity = dir * speed
			move_and_slide()
			var w_size = GameConstants.GAME_CONFIG.get("worldSize", 4000)
			global_position.x = clamp(global_position.x, 10, w_size - 10)
			global_position.y = clamp(global_position.y, 10, w_size - 10)
		else:
			is_moving = false
			autopilot_enabled = false
			velocity = Vector2.ZERO

func set_autopilot(p_dest: Vector2):
	target_position = p_dest
	is_moving = true
	autopilot_enabled = true

func _sync_with_server(p_delta):
	sync_timer += p_delta
	if sync_timer >= SYNC_INTERVAL:
		sync_timer = 0.0
		if global_position.distance_to(last_sent_pos) > 1.0:
			_force_move_sync()

var last_sent_rotation = 0.0
func change_ammo(p_type: String, p_tier: int):
	if selected_ammo.has(p_type):
		selected_ammo[p_type] = p_tier
		_emit_stats()

func _force_move_sync():
	last_sent_pos = global_position
	last_sent_rotation = rotation
	NetworkManager.send_event("playerMovement", {
		"id": entity_id, "x": global_position.x, "y": global_position.y,
		"rotation": rotation, "hp": current_hp, "sh": current_shield,
		"maxHp": max_hp, "maxSh": max_shield, "maxShield": max_shield,
		"zone": current_zone 
	})

func respawn():
	is_dead = false
	current_hp = max_hp
	current_shield = max_shield
	global_position = Vector2(randf_range(1500, 2500), randf_range(1500, 2500))
	target_position = global_position
	visible = true; modulate.a = 1.0; show()
	set_physics_process(true); set_process(true)
	_update_tags()
	NetworkManager.send_event("playerRespawn", {
		"id": entity_id, "hp": max_hp, "sh": max_shield,
		"x": global_position.x, "y": global_position.y, "zone": current_zone
	})

func _on_login_success(p_in):
	self.entity_id = str(p_in.get("socketId", p_in.get("id", "")))
	self.username = p_in.get("username", p_in.get("user", "Piloto"))
	if p_in.has("gameData"):
		var gd = p_in.gameData
		hubs = int(gd.get("hubs", 0))
		ohculianos = int(gd.get("ohcu", 0))
		inventory = gd.get("inventory", [])
		equipped = gd.get("equipped", equipped)
		ammo = gd.get("ammo", ammo)
		selected_ammo = gd.get("selected_ammo", selected_ammo)
		if gd.has("lastPos"):
			var lp = gd["lastPos"]
			global_position = Vector2(lp.get("x", 2000), lp.get("y", 2000))
			target_position = global_position
		current_ship_id = int(gd.get("currentShipId", 1))
		_setup_ship_visuals() # v210.20: Fuerza actualización visual tras recibir ID del servidor
		current_zone = int(gd.get("zone", 1))
		level = int(gd.get("level", 1))
		current_exp = float(gd.get("exp", 0))
		skill_tree = gd.get("skillTree", {"engineering":[0,0,0,0,0,0,0,0],"combat":[0,0,0,0,0,0,0,0],"science":[0,0,0,0,0,0,0,0]}).duplicate()
		skill_tree["skillPoints"] = int(gd.get("skillPoints", 0))
		
		var sm = get_node_or_null("SpheresManager")
		if sm and gd.has("spheres"):
			var raw_spheres = gd["spheres"].duplicate()
			# v206.0: Re-hidratación de tipos y HABILIDADES (JSON Safe)
			for i in range(raw_spheres.size()):
				var sph = raw_spheres[i]
				if sph.has("color"):
					var c_str = str(sph["color"]).replace("(","").replace(")","").replace(" ","")
					if "," in c_str:
						var parts = c_str.split(",")
						if parts.size() >= 3:
							var r_v = float(parts[0]); var g_v = float(parts[1]); var b_v = float(parts[2])
							var a_v = float(parts[3]) if parts.size() > 3 else 1.0
							sph["color"] = Color(r_v, g_v, b_v, a_v)
					else: sph["color"] = Color(c_str)
				
				# Re-hidratar Habilidad (Si viene como Diccionario del Servidor)
				if sph.has("equipped") and typeof(sph["equipped"]) == TYPE_DICTIONARY:
					var eq = sph["equipped"]
					if eq.has("skill_name"):
						sph["equipped"] = _find_skill_by_name(eq["skill_name"])
						if sph["equipped"] is Object:
							for key in eq: sph["equipped"].set(key, eq[key])
			sm.spheres_data = raw_spheres
			sm.emit_signal("spheres_updated")

		current_hp = float(gd.get("hp", max_hp)) 
		current_shield = float(gd.get("shield", max_shield))
		_recalculate_stats()
		update_stats({})
	_update_tags(); _emit_stats(); queue_redraw()

func _on_enemy_dead(_data): pass
func _on_reward_received(p_data: Dictionary):
	hubs += int(p_data.get("hubs", 0))
	ohculianos += int(p_data.get("ohcu", 0))
	current_exp += float(p_data.get("exp", 0))
	_update_tags(); _emit_stats()

func _on_level_up(p_data: Dictionary):
	level = int(p_data.get("level", level + 1))
	_emit_stats()

func _emit_stats():
	stats_changed.emit({
		"hp": current_hp, "maxHp": max_hp,
		"sh": current_shield, "maxSh": max_shield,
		"hubs": hubs, "ohcu": ohculianos,
		"level": level, "current_exp": current_exp, "next_level_exp": next_level_exp
	})

func update_stats(data):
	super.update_stats(data)
	_emit_stats()

func save_progress():
	var s_data = []
	var sm = get_node_or_null("SpheresManager")
	if sm: 
		# v206.0: De-serialización de Habilidades para JSON Safe Saving
		var raw = sm.spheres_data.duplicate(true)
		for i in range(raw.size()):
			var sph = raw[i]
			if sph.has("color") and typeof(sph["color"]) == TYPE_COLOR:
				sph["color"] = str(sph["color"])
			
			if sph.has("equipped") and sph["equipped"] is Object:
				var skill = sph["equipped"]
				sph["equipped"] = {
					"skill_name": skill.skill_name if "skill_name" in skill else "SKILL",
					"power_value": skill.power_value if "power_value" in skill else 0,
					"type": skill.type if "type" in skill else "w"
				}
		s_data = raw
		
	NetworkManager.send_event("saveProgress", {
		"hubs": hubs, "ohcu": ohculianos, "exp": current_exp,
		"level": level, "skillPoints": skill_tree.get("skillPoints", 0),
		"skillTree": skill_tree,
		"inventory": inventory, "equipped": equipped,
		"spheres": s_data,
		"hp": current_hp, "shield": current_shield,
		"maxHp": max_hp, "maxShield": max_shield,
		"ownedShips": owned_ships, "currentShipId": current_ship_id,
		"lastPos": {"x": global_position.x, "y": global_position.y}
	})

# Buscar clase de habilidad por nombre (v206.0 Internal Helper)
func _find_skill_by_name(n: String):
	var skills = [Skill_TurboImpulse, Skill_ShieldCell, Skill_RepairKit]
	for s in skills:
		var inst = s.new()
		if inst.skill_name == n: return inst
	return null
