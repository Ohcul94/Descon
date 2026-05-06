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

var is_moving = false
var autopilot_enabled: bool = false
var is_autopilot_active: bool:
	get:
		return autopilot_enabled
	set(v):
		autopilot_enabled = v

var hubs: int = 0
var ohculianos: int = 0
var inventory: Array = []
var equipped: Dictionary = {"w": [], "s": [], "e": [], "x": []}
var owned_ships: Array = [1]
var base_laser_damage: float = 100.0
var level: int = 1
var current_exp: float = 0.0
var next_level_exp: float = 1000.0
var skill_points: int = 0
var skill_tree: Dictionary = {"combat": [], "engineering": [], "science": []}

var ammo: Dictionary = {"laser": [1000, 0, 0, 0, 0, 0], "missile": [100, 0, 0], "mine": [10, 0, 0]}
var selected_ammo: Dictionary = {"laser": 0, "missile": 0, "mine": 0}
var current_zone: int = 1
var _skill_controller: Node2D = null

var _shake_amount: float = 0.0
var _shake_decay: float = 0.9
var _cam_node: Camera2D = null
var slow_points: float = 0.0

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
	cam.zoom = Vector2(0.8, 0.8) # v217.10: Mayor visibilidad táctica
	add_child(cam)
	cam.make_current()
	_cam_node = cam
	
	if NetworkManager:
		NetworkManager.login_success.connect(_on_login_success)
		NetworkManager.inventory_data.connect(_on_inventory_received)
		NetworkManager.slow_state.connect(_on_slow_state)
	
	_setup_skill_controller()

func _on_slow_state(data: Dictionary):
	if data.has("active"):
		if data.active:
			slow_points = data.get("amount", 50.0)
		else:
			slow_points = 0.0

func _setup_skill_controller():
	var sc_script = load("res://scripts/systems/SkillController.gd")
	if sc_script:
		_skill_controller = sc_script.new()
		add_child(_skill_controller)

func _unhandled_input(event):
	# v226.50: Bloquear zoom si el mouse está sobre la UI (Evitar zoom al scrollear menús)
	if event is InputEventMouseButton:
		# v2.6: Bloqueo de SEGURIDAD para evitar click-through a cualquier menú abierto
		var ui_blocking = false
		for group in ["inventory_ui", "admin_panel_ui"]:
			for node in get_tree().get_nodes_in_group(group):
				if node.visible:
					# v2.7: Si el menú está visible y bloquea mouse, impedimos movimiento
					if node.mouse_filter == Control.MOUSE_FILTER_STOP:
						ui_blocking = true; break
		
		if ui_blocking: return

		if get_viewport().gui_get_hovered_control() != null:
			return
			
		var cam = get_viewport().get_camera_2d()
		
		# Procesar Movimiento (Click)
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				target_position = get_global_mouse_position()
				is_moving = true; autopilot_enabled = false
			
			# Procesar Zoom (Rueda)
			if is_instance_valid(cam):
				var zoom_step = 0.1
				var min_zoom = 0.3; var max_zoom = 2.0
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					var target_z = clamp(cam.zoom.x + zoom_step, min_zoom, max_zoom)
					create_tween().set_trans(Tween.TRANS_SINE).tween_property(cam, "zoom", Vector2(target_z, target_z), 0.2)
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					var target_z = clamp(cam.zoom.x - zoom_step, min_zoom, max_zoom)
					create_tween().set_trans(Tween.TRANS_SINE).tween_property(cam, "zoom", Vector2(target_z, target_z), 0.2)

func _physics_process(p_delta):
	if not NetworkManager.network_connected: return
	_handle_cooldowns(p_delta)
	
	var chat = get_tree().get_first_node_in_group("chat_ui")
	var focus_node = get_viewport().gui_get_focus_owner()
	var is_typing = (chat and chat.has_method("is_typing") and chat.is_typing()) or (focus_node is LineEdit or focus_node is TextEdit)
	if not is_typing:
		_handle_input()
		
	_apply_movement()
	_update_shake(p_delta)
	_sync_with_server(p_delta)

enum Skill_Type { DIRECTIONAL, POINT_CLICK, AREA, INSTANT }

func _handle_input():
	# v260.90: Sistema de 7 Slots Unificados (Láser, Misil, Mina + 4 Esferas)
	_handle_slot_input("slot_1", "laser", Skill_Type.DIRECTIONAL)
	_handle_slot_input("slot_2", "missile", Skill_Type.DIRECTIONAL)
	_handle_slot_input("slot_3", "mine", Skill_Type.DIRECTIONAL)
	
	# Esferas (Slots 4 al 7) - v3.9: Tipo Dinámico (Directional vs PointClick vs Instant)
	for i in range(4):
		var slot_name = "slot_" + str(i + 4)
		var s_id = "sphere_" + str(i)
		var s_type = Skill_Type.INSTANT # v4.5: Default ahora es INSTANT para esferas
		
		var sm = get_node_or_null("SpheresManager")
		if sm:
			var sph = sm.get_equipped_skill(i)
			if sph:
				var s_name = sph.get("skill_name")
				if s_name and GameConstants.SKILLS_DATA.has(s_name):
					var s_data = GameConstants.SKILLS_DATA[s_name]
					if s_data.get("canTargetOthers", false) and s_name != "FROST-TRAIL":
						s_type = Skill_Type.POINT_CLICK
					elif s_data.get("range", 0) > 0 and s_name != "FROST-TRAIL":
						s_type = Skill_Type.DIRECTIONAL
		
		_handle_slot_input(slot_name, s_id, s_type)

func _handle_slot_input(action: String, skill_id: String, type: int):
	# Auto-crear acción si no existe para evitar errores
	if not InputMap.has_action(action): 
		InputMap.add_action(action)
		return

	if Input.is_action_just_pressed(action):
		var cd = cooldowns.get(skill_id, 0.0)
		if cd <= 0:
			var r_val = 600.0 # Default
			var filters = {}
			var s_name = skill_id # Fallback para armas base (laser, missile, mine)
			
			if skill_id.begins_with("sphere_"):
				var s_idx = int(skill_id.replace("sphere_", ""))
				var sm = get_node_or_null("SpheresManager")
				if sm:
					var sph = sm.get_equipped_skill(s_idx)
					if sph:
						s_name = sph.get("skill_name")
						if s_name == null: s_name = ""
						if s_name != "" and GameConstants.SKILLS_DATA.has(s_name):
							var s_data = GameConstants.SKILLS_DATA[s_name]
							r_val = s_data.get("range", 0)
							filters = s_data.get("targetFilters", {})
			elif skill_id == "laser" or skill_id == "missile" or skill_id == "mine":
				var t_idx = selected_ammo.get(skill_id, 0)
				var ammo_list = GameConstants.SHOP_ITEMS.ammo.get(skill_id, [])
				if t_idx < ammo_list.size():
					r_val = ammo_list[t_idx].get("range", 600.0)
			
			# v4.9: Auto-target self si se mantiene presionada la tecla (Alt por defecto)
			if not InputMap.has_action("auto_target_self"):
				InputMap.add_action("auto_target_self")
				var ev = InputEventKey.new()
				ev.keycode = KEY_ALT
				InputMap.action_add_event("auto_target_self", ev)
				
			if Input.is_action_pressed("auto_target_self") and skill_id.begins_with("sphere_"):
				_on_skill_executed({
					"skill_id": skill_id,
					"angle": 0.0,
					"target": self,
					"pos": global_position
				})
				return
			
			# v3.9.8: Inyección de Filtros Dinámicos y Nombre para Visuales
			_skill_controller.start_aiming({"id": skill_id, "type": type, "range": r_val, "filters": filters, "skill_name": s_name})
	
	if Input.is_action_just_released(action):
		if _skill_controller.is_aiming and _skill_controller.current_skill.id == skill_id:
			if _skill_controller.config.cast_mode == 1: # ON_RELEASE
				_skill_controller.execute_skill()

func _on_skill_executed(p_data: Dictionary):
	var id = p_data.skill_id
	if id == "laser" or id == "missile" or id == "mine":
		_shoot_skill(id, p_data.angle, p_data.get("pos", Vector2.ZERO))
	elif id.begins_with("sphere_"):
		var s_idx = int(id.replace("sphere_", ""))
		_use_sphere_skill(s_idx, p_data) # v260.91: Integración con lógica de esferas y targeting

func _use_heal_skill(p_target):
	if p_target:
		print("[SKILL] Curando a: ", p_target.username)
		# Enviar al servidor...
		NetworkManager.send_event("playerHeal", {"targetId": p_target.entity_id, "amount": 500})


var cooldowns = {"laser": 0.0, "missile": 0.0, "mine": 0.0, "sphere_0": 0.0, "sphere_1": 0.0, "sphere_2": 0.0, "sphere_3": 0.0}
func _handle_cooldowns(p_delta):
	for s in cooldowns:
		if cooldowns[s] > 0: cooldowns[s] -= p_delta

func _on_inventory_received(p_data):
	var gd = p_data
	if typeof(p_data) == TYPE_DICTIONARY and p_data.has("player"):
		gd = p_data["player"]
		
	if typeof(gd) == TYPE_DICTIONARY:
		# v236.15: Extraer gameData si viene anidado (común en login_success)
		if gd.has("gameData"): gd = gd["gameData"]
		
		if gd.has("items"): 
			inventory = gd["items"]
		elif gd.has("inventory"): 
			inventory = gd["inventory"]
		if gd.has("equipped"): equipped = gd["equipped"]
		if gd.has("hubs"): hubs = int(gd["hubs"])
		if gd.has("ohcu"): ohculianos = int(gd["ohcu"])
		if gd.has("skillTree"):
			skill_tree = gd["skillTree"].duplicate()
			if gd.has("skillPoints"):
				skill_tree["skillPoints"] = int(gd["skillPoints"])
		if gd.has("level"): level = int(gd["level"])
		if gd.has("exp"): current_exp = float(gd["exp"])
		
		# v240.95: Sincronía de Munición en Tiempo Real (Fix Shop Update)
		if gd.has("ammo"):
			ammo = gd["ammo"].duplicate()
		if gd.has("selectedAmmo"):
			selected_ammo = gd["selectedAmmo"].duplicate()
		
		# v235.95: Persistencia de Esferas Orbitales
		if gd.has("spheres"):
			var sm = get_node_or_null("SpheresManager")
			if sm:
				var sph_data = gd["spheres"]
				for i in range(min(sph_data.size(), 4)):
					var s_raw = sph_data[i]
					var eq = s_raw.get("equipped")
					if eq:
						var s_name = eq.get("skill_name", "")
						var skill_obj = _find_skill_by_name(s_name)
						if skill_obj:
							sm.equip_item(i, skill_obj)
						else:
							# Fallback si no encontramos la clase pero el dict es válido
							sm.equip_item(i, eq)
					else:
						sm.equip_item(i, null)

	
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
	
	var ship_base = { "hp": 3000, "shield": 1000, "speed": 300 }
	for ship in GameConstants.SHIP_MODELS:
		if ship.id == current_ship_id:
			ship_base = ship
			break
			
	var base_hp_val = float(ship_base.get("hp", 3000)) + total_hp_bonus
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

func take_damage(amt: float, attacker_pos: Vector2 = Vector2.ZERO, attacker_id: String = ""):
	super.take_damage(amt, attacker_pos, attacker_id)
	apply_shake(amt * 0.05) # v260: Shake leve
	# v240.69: Eliminado envío duplicado al servidor. Projectile.gd ya se encarga de notificar 
	# el daño exacto con el enemyType correcto. Hacerlo aquí duplicaba el daño (1 hit = 2 hits) 
	# y enviaba eventos "fantasma" que reiniciaban contadores de combate.

func _shoot_skill(p_type: String, p_angle: float, p_target_pos: Vector2 = Vector2.ZERO):
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
	
	var r_val = 600.0
	var ammo_list = GameConstants.SHOP_ITEMS.ammo.get(p_type, [])
	if t_idx < ammo_list.size():
		r_val = ammo_list[t_idx].get("range", 600.0)
	
	# v260.95: Lógica de Minas de Precisión (Despliegue en cursor si está en rango)
	if p_type == "mine" and p_target_pos != Vector2.ZERO:
		var dist = global_position.distance_to(p_target_pos)
		r_val = min(r_val, dist)

	var final_damage = base_laser_damage * ammo_mult
	var final_payload = {
		"id": entity_id, "x": global_position.x, "y": global_position.y,
		"angle": p_angle, "rotation": rotation, "type": p_type, "ammoType": t_idx, 
		"senderId": entity_id, "damageBoost": final_damage, "range": r_val
	}
	
	shoot_fired.emit(final_payload)
	NetworkManager.send_event("playerFire", final_payload)
	apply_shake(0.8) # v260: Shake muy leve al disparar
	_force_move_sync()

func _use_sphere_skill(id: int, p_data: Dictionary):
	var key = "sphere_" + str(id)
	if cooldowns[key] > 0: return
	var sm = get_node_or_null("SpheresManager")
	if not is_instance_valid(sm): return
	
	var skill = sm.get_equipped_skill(id)
	if not skill: return
	
	# v5.0: Auto-target local si no hay objetivo (Especial para INSTANT skills como FROST-TRAIL)
	var final_target = p_data.target
	if not is_instance_valid(final_target): final_target = self
	
	var target_id = null
	if is_instance_valid(final_target):
		if "entity_id" in final_target: target_id = final_target.entity_id
		elif final_target.has_method("get_id"): target_id = final_target.get_id()
		else: target_id = str(final_target.name)
		
	var is_targeted = false
	var skill_range = 0.0
	if GameConstants.SKILLS_DATA.has(skill.skill_name):
		var s_data = GameConstants.SKILLS_DATA[skill.skill_name]
		is_targeted = s_data.get("canTargetOthers", false)
		skill_range = s_data.get("range", 0.0)
		
	if is_targeted and target_id == null:
		return
		
	# v4.8: Validación de rango en cliente
	if is_targeted and target_id != entity_id and skill_range > 0:
		var target_node = final_target
		if is_instance_valid(target_node):
			var dist = global_position.distance_to(target_node.global_position)
			if dist > skill_range + 50.0:
				print("[SKILL] Cancelado: Objetivo fuera de rango.")
				return
		
	# v4.2: Evitar autodaño/autocura si el objetivo es otro
	var is_self = (target_id == null or target_id == entity_id)
	
	if is_self:
		# Auto-lanzamiento: Activar efectos locales inmediatos
		if not sm.use_skill(id): return
	else:
		# Lanzamiento a otros: NO activar localmente (el servidor lo hará para el target)
		# Solo activamos el cooldown visual en el HUD
		pass
		
	# Enviar al servidor para que procese y broadcastee a todos
	NetworkManager.send_event("playerSphereSkill", {
		"id": id, "skillName": skill.skill_name, "powerValue": skill.power_value,
		"targetId": target_id, "posX": p_data.pos.x, "posY": p_data.pos.y
	})
	
	# Cooldown persistente
	cooldowns[key] = skill.cooldown if "cooldown" in skill else 5.0

func _apply_movement():
	if is_moving:
		var dist = global_position.distance_to(target_position)
		var threshold = 15.0
		if get_node_or_null("/root/SettingsManager"):
			threshold = 15.0 / max(0.1, SettingsManager.click_sensitivity)
			
		if dist > threshold:
			var target_angle = (target_position - global_position).angle()
			rotation = lerp_angle(rotation, target_angle, 0.25)
			var dir = Vector2.RIGHT.rotated(rotation)
			# v10.0: Aplicar resta de puntos planos (Igual que Turbo)
			var final_speed = max(10.0, speed - slow_points)
			velocity = dir * final_speed
			
			# v7.0: Feedback Visual de Congelamiento (Igual que ceguera)
			if slow_points > 1.0:
				modulate = modulate.lerp(Color(0.4, 0.7, 1.0, 1.0), 0.1) # Tinte azulado
			else:
				modulate = modulate.lerp(Color.WHITE, 0.1)
				
			if move_and_slide():
				# v235.97: Resolución Activa de Atascamiento (Antiglue System)
				for i in get_slide_collision_count():
					var col = get_slide_collision(i)
					var obj = col.get_collider()
					if obj and (obj.is_in_group("enemies") or obj.is_in_group("remote_players")):
						# Pequeño rebote de seguridad para separar geometrías
						global_position += col.get_normal() * 2.0
						velocity = velocity.bounce(col.get_normal()) * 0.5

			
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
	self.entity_id = str(p_in.get("socketId", ""))
	self.db_id = str(p_in.get("id", ""))
	self.username = p_in.get("username", p_in.get("user", "Piloto"))
	self.clan_tag = str(p_in.get("clanTag", "")) # v244.110
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
		# v210.190: Sincronización final de Visuales y Stats
		current_ship_id = int(gd.get("currentShipId", 1))
		current_zone = int(gd.get("zone", 1)) # v238.45: Recuperación de sector

		level = int(gd.get("level", 1))

		current_exp = float(gd.get("exp", 0))
		skill_tree = gd.get("skillTree", {"engineering":[0,0,0,0,0,0,0,0],"combat":[0,0,0,0,0,0,0,0],"science":[0,0,0,0,0,0,0,0]}).duplicate()
		skill_tree["skillPoints"] = int(gd.get("skillPoints", 0))
		
		# v221.26: Cargar estado PvP persistente de la cuenta
		if gd.has("pvpEnabled"):
			self.pvp_status = !!gd["pvpEnabled"]

		# v210.191: FORZAR REDRAW VISUAL (Fix: Asset Inconsistency)
		_setup_ship_visuals() 
		print("[CLIENT] Nave configurada ID: ", current_ship_id, " para ", username)
		
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
			if sm.has_method("_update_visuals"):
				sm._update_visuals()

		current_hp = float(gd.get("hp", max_hp)) 
		current_shield = float(gd.get("shield", max_shield))
		_recalculate_stats()
		
		# v221.35: Sincronía inicial con el HUD
		if is_instance_valid(get_parent()) and get_parent().has_node("HUD/MainHUD"):
			get_parent().get_node("HUD/MainHUD").set_pvp_status(pvp_status)
		
		update_stats({"pvpEnabled": pvp_status})
	_update_tags(); _emit_stats(); queue_redraw()

func _on_enemy_dead(_data): pass
func _on_reward_received(_data): pass

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
	# v221.40: Solo actualizar pvp_status si el servidor lo manda explícitamente
	if data.has("pvpEnabled"): 
		pvp_status = !!data.pvpEnabled
	
	super.update_stats(data)
	_emit_stats()

func save_progress():
	# v242.45: Lógica de esferas desactivada en saveProgress para evitar data-loss
	# El servidor ahora gestiona las esferas de forma independiente.
	
	NetworkManager.send_event("saveProgress", {
		"hubs": hubs, "ohcu": ohculianos, "exp": current_exp,
		"level": level, "skillPoints": skill_tree.get("skillPoints", 0),
		"skillTree": skill_tree,
		# "inventory": inventory, # DESACTIVADO v215.30 FIX DUPEO
		# "equipped": equipped,   # DESACTIVADO v215.30 FIX DUPEO
		# "spheres": s_data,      # DESACTIVADO v241.30 FIX DATA LOSS (El server ya maneja equipSphere/unequipSphere)
		"hp": current_hp, "shield": current_shield,
		"maxHp": max_hp, "maxShield": max_shield,
		"ownedShips": owned_ships, "currentShipId": current_ship_id,
		"lastPos": {"x": global_position.x, "y": global_position.y}
	})

# Buscar clase de habilidad por nombre (v206.0 Internal Helper)
func _find_skill_by_name(n: String):
	if n == "": return null
	var target_n = n.to_upper().strip_edges()
	var skills = [
		Skill_TurboImpulse, Skill_ShieldCell, Skill_RepairKit, Skill_Reflect,
		Skill_PlasmaBlast, Skill_Fortress, Skill_RegenPath, Skill_HyperDash,
		Skill_Invulnerability, Skill_Blink, Skill_SmokeBomb, Skill_Stealth
	]
	for s in skills:
		var inst = s.new()
		if inst.skill_name.to_upper().strip_edges() == target_n: return inst
	return null

func apply_shake(amount: float):
	if get_node_or_null("/root/SettingsManager"):
		if not SettingsManager.camera_shake_enabled: return
		amount *= SettingsManager.camera_shake_intensity
		
	_shake_amount += amount
	_shake_amount = min(_shake_amount, 10.0)

func _update_shake(_delta):
	if _shake_amount > 0.1:
		if is_instance_valid(_cam_node):
			_cam_node.offset = Vector2(randf_range(-_shake_amount, _shake_amount), randf_range(-_shake_amount, _shake_amount))
		_shake_amount *= _shake_decay
	else:
		if is_instance_valid(_cam_node):
			_cam_node.offset = Vector2.ZERO
		_shake_amount = 0.0
