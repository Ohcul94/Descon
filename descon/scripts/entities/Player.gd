extends Entity

# Player.gd (Controlador Maestro v69.40 - STABLE RECOVERY)
# Saneado y corregido para evitar errores de sintaxis en línea 181.

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
var is_autopilot_active: bool: # Alias para compatibilidad con el minimapa
	get: return autopilot_enabled
	set(v): autopilot_enabled = v

var hubs: int = 0
var ohculianos: int = 0
var inventory: Array = []
var equipped: Dictionary = {"l": [], "s": [], "e": []}
var owned_ships: Array = [1]
var current_ship_id: int = 1
var base_laser_damage: float = 100.0
var level: int = 1
var current_exp: float = 0.0
var next_level_exp: float = 1000.0
var skill_tree: Dictionary = {"combat": [], "engineering": []}
var ammo: Dictionary = {"laser": [1000, 0, 0, 0, 0, 0], "missile": [100, 0, 0], "mine": [10, 0, 0]}
var selected_ammo: Dictionary = {"laser": 0, "missile": 0, "mine": 0}
var current_zone: int = 1 # v168.08: Tracking de zona para visibilidad de red

func _ready():
	super._ready() # v150: Ejecutar exorcismo de barras redundantes
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
	
	if NetworkManager:
		NetworkManager.login_success.connect(_on_login_success)
		# NetworkManager.player_stat_sync.connect(update_stats) # ELIMINADO v168.12: Evita el ping-pong de stats (World.gd ya lo rutea)
		NetworkManager.inventory_data.connect(_on_inventory_received)
		NetworkManager.enemy_dead.connect(_on_enemy_dead)
		NetworkManager.reward_received.connect(_on_reward_received)

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

	# Disparo: Apuntar al mouse al disparar. Bloqueo por Cooldown activado.
	if Input.is_action_just_pressed("fire_laser") and cooldowns["laser"] <= 0:
		_shoot_skill("laser", mouse_angle)
	elif Input.is_action_pressed("fire_laser") and cooldowns["laser"] <= 0:
		_shoot_skill("laser", mouse_angle)
		
	if Input.is_action_just_pressed("fire_missile") and cooldowns["missile"] <= 0:
		_shoot_skill("missile", mouse_angle)
	if Input.is_action_just_pressed("fire_mine") and cooldowns["mine"] <= 0:
		_shoot_skill("mine", mouse_angle)
	
func _unhandled_input(event):
	# v165.25: Movimiento solo si el clic NO fue capturado por el HUD
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			target_position = get_global_mouse_position()
			is_moving = true
			autopilot_enabled = false

var cooldowns = {"laser": 0.0, "missile": 0.0, "mine": 0.0}
func _handle_cooldowns(p_delta):
	for s in cooldowns:
		if cooldowns[s] > 0: cooldowns[s] -= p_delta

func _on_inventory_received(p_data):
	if typeof(p_data) == TYPE_ARRAY:
		inventory = p_data
	elif typeof(p_data) == TYPE_DICTIONARY and p_data.has("items"):
		inventory = p_data["items"]
	_recalculate_stats()

func _recalculate_stats():
	# Reset stats a base
	base_laser_damage = 100.0
	var total_sh_bonus = 0.0
	var total_hp_bonus = 0.0
	var speed_bonus = 0.0
	
	# v167.05: Sincronía con Estructura del Servidor (Iterar sobre Equipped dict)
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
	
	# v190.80: SINCRONÍA ABSOLUTA CON ADMIN CONSTANTS
	# Ya no usamos 2000, 1000 o 300 fijos. Buscamos el modelo de nuestra nave actual.
	var ship_base = { "hp": 2000, "shield": 1000, "speed": 300 }
	for ship in GameConstants.SHIP_MODELS:
		if ship.id == current_ship_id:
			ship_base = ship
			break
			
	max_hp = float(ship_base.get("hp", 2000)) + total_hp_bonus
	max_shield = float(ship_base.get("shield", 1000)) + total_sh_bonus
	speed = float(ship_base.get("speed", 300)) + speed_bonus
	
	# Notificar al servidor nuestros nuevos límites reales (Sincronía Crítica)
	save_progress()
	
	_update_tags()
	_emit_stats()

func take_damage(amt: float):
	super.take_damage(amt)
	# v166.98: Notificar al servidor para que detenga SU regeneración (5-sec rule sync)
	if NetworkManager:
		NetworkManager.send_event("playerHitByEnemy", { "damage": amt, "id": entity_id })

func _shoot_skill(p_type: String, p_angle: float):
	last_combat_time = Time.get_ticks_msec() # v166.92: Disparar también cuenta como combate
	# v166.98: Notificar al servidor que estamos en combate
	if NetworkManager:
		NetworkManager.send_event("playerHitByEnemy", { "damage": 0, "id": entity_id })
	
	var t_idx = selected_ammo.get(p_type, 0)
	var current_ammo = 0
	if ammo.has(p_type) and t_idx < ammo[p_type].size():
		current_ammo = ammo[p_type][t_idx]
	
	# Parche: Siempre permitir disparar Tier 1 (Infinity Ammo para pruebas)
	if current_ammo > 0:
		ammo[p_type][t_idx] -= 1
		
	cooldowns[p_type] = 0.5 if p_type == "laser" else 2.0
	AudioManager.play_sfx(p_type)
	
	# v164.91: Al disparar cualquier arma detiene el movimiento automático 
	# para evitar el conflicto de rotación.
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
		print("[COMBAT] Munición de ", p_type, " cambiada a Tier ", p_tier + 1)

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
	# v168.15: Posición de seguridad dinámica (evitar spawn kill)
	global_position = Vector2(randf_range(1500, 2500), randf_range(1500, 2500))
	target_position = global_position
	
	visible = true; modulate.a = 1.0; show()
	set_physics_process(true); set_process(true)
	_update_tags()
	
	# Sincronía Crítica con el Servidor
	NetworkManager.send_event("playerRespawn", {
		"id": entity_id, "hp": max_hp, "sh": max_shield,
		"x": global_position.x, "y": global_position.y,
		"zone": current_zone
	})
	print("[SYSTEM] Reaparecido en Zona ", current_zone)

func save_progress():
	NetworkManager.send_event("saveProgress", {
		"hubs": hubs, "ohcu": ohculianos, "exp": current_exp,
		"inventory": inventory, "equipped": equipped,
		"lastPos": {"x": global_position.x, "y": global_position.y}
	})

func _on_login_success(p_in):
	# v167.97: Normalización Crítica - Usar socketId para red (dbId interno)
	self.entity_id = str(p_in.get("socketId", p_in.get("id", "")))
	self.username = p_in.get("username", p_in.get("user", "Piloto"))
	if p_in.has("gameData"):
		var gd = p_in.gameData
		hubs = int(gd.get("hubs", 0))
		ohculianos = int(gd.get("ohcu", 0))
		inventory = gd.get("inventory", [])
		equipped = gd.get("equipped", equipped)
		if gd.has("lastPos"):
			var lp = gd["lastPos"]
			global_position = Vector2(lp.get("x", 2000), lp.get("y", 2000))
			target_position = global_position
		current_ship_id = int(gd.get("currentShipId", 1)) # v190.81: Recordar qué nave tenemos
		current_zone = int(gd.get("zone", 1)) # Sincronizar zona inicial
		_recalculate_stats()
	_update_tags()
	queue_redraw()

func _on_enemy_dead(_data): pass
func _on_reward_received(p_data):
	hubs += int(p_data.get("hubs", 0))
	ohculianos += int(p_data.get("ohcu", 0))
	_update_tags()
	_emit_stats()

func _emit_stats():
	stats_changed.emit({
		"hp": current_hp, "maxHp": max_hp,
		"sh": current_shield, "maxSh": max_shield,
		"hubs": hubs, "ohcu": ohculianos
	})

func update_stats(data: Dictionary):
	# v167.92: Heredar Detección de Daño de Entity (Reset Combat Timer)
	super.update_stats(data)
	
	# Sincronía adicional específica del Jugador (Stats locales y HUD)
	_emit_stats()
