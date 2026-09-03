extends Entity

# Precargas estáticas para optimización de rendimiento (v313.3)
const SKILL_CONTROLLER_SCRIPT = preload("res://scripts/systems/SkillController.gd")
const SLEEP_AURA_SCRIPT = preload("res://scripts/systems/SleepAuraVisual.gd")
const SLEEP_ZZ_SCRIPT = preload("res://scripts/systems/SleepZZVisual.gd")

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
# v300.80: skill_tree delegado totalmente al TalentSystem.gd

var ammo: Dictionary = {
	"laser": [1000, 0, 0, 0, 0, 0],
	"missile": [100, 0, 0],
	"mine": [10, 0, 0],
	"melee": [0, 0, 0, 0, 0, 0],
	"heal": [0, 0, 0, 0, 0, 0],
	"siphon": [0, 0, 0, 0, 0, 0],
	"emp": [0, 0, 0, 0, 0, 0]
}
var selected_ammo: Dictionary = {
	"laser": 0,
	"missile": 0,
	"mine": 0,
	"melee": 0,
	"heal": 0,
	"siphon": 0,
	"emp": 0
}
var ammo_slots: Array = ["laser", "missile", "mine"]

func save_ammo_slots_local():
	var f = ConfigFile.new()
	f.set_value("hud", "ammo_slots", ammo_slots)
	var filename = "user://ammo_slots.cfg"
	if username != "" and username != "Piloto":
		filename = "user://ammo_slots_" + username + ".cfg"
	f.save(filename)

func load_ammo_slots_local():
	var f = ConfigFile.new()
	var filename = "user://ammo_slots.cfg"
	if username != "" and username != "Piloto":
		filename = "user://ammo_slots_" + username + ".cfg"
	if f.load(filename) == OK:
		ammo_slots = f.get_value("hud", "ammo_slots", ["laser", "missile", "mine"])

func set_ammo_slot(slot_idx: int, ammo_type: String):
	print("[PLAYER] set_ammo_slot convocado. SlotIdx: ", slot_idx, " AmmoType: ", ammo_type, " slots_actuales: ", ammo_slots)
	if slot_idx >= 0 and slot_idx < ammo_slots.size():
		# v690.1: Cada munición solo puede estar en UN slot. Si ya está en otro, se quita de ahí.
		for i in range(ammo_slots.size()):
			if i != slot_idx and ammo_slots[i] == ammo_type:
				ammo_slots[i] = "laser"
				print("[PLAYER] Munición ", ammo_type, " ya estaba en slot ", i, ". Se movió al slot ", slot_idx, ".")
				break
		ammo_slots[slot_idx] = ammo_type
		print("[PLAYER] Guardando slots localmente.")
		save_ammo_slots_local()
	else:
		print("[PLAYER] Error: slot_idx fuera de rango.")

var _is_initializing: bool = false # v269.170: Bloqueo de guardado durante login
var current_zone: int = 1
var vision_range: float = 1300.0
var _skill_controller: Node2D = null

# ==== SISTEMA DE CASTEO (Congela nave, apunta al tiro) ====
var is_casting: bool = false
var cast_duration: float = 0.0
var cast_elapsed: float = 0.0
var cast_type: String = "" # "ammo" o "skill"
var cast_payload: Dictionary = {}
var cast_angle: float = 0.0
var cast_start_pos: Vector2 = Vector2.ZERO
var _cast_visual_2d: Control = null
var _current_cast_color: Color = Color.WHITE
var _buffered_cast_action: Dictionary = {}
var _buffered_cast_time: float = 0.0
const CAST_BUFFER_WINDOW_MS: float = 500.0
var _remote_cast_active: bool = false
var _remote_cast_duration: float = 0.0
var _remote_cast_elapsed: float = 0.0
var _remote_cast_angle: float = 0.0

var _shake_amount: float = 0.0
var _shake_decay: float = 0.93
var _cam_node: Camera2D = null
var slow_points: float = 0.0
var slow_is_percentage: bool = false
var is_stunned: bool = false
var stun_timer: float = 0.0
var is_feared: bool = false
var fear_timer: float = 0.0
var fear_vector: Vector2 = Vector2.ZERO
var joystick_direction: Vector2 = Vector2.ZERO # v266.400

# v266.360: Temporizadores de efectos de estado para el HUD de Estados
var slow_timer: float = 0.0
var heal_timer: float = 0.0
var heal_stacks: int = 0
var bleed_timer: float = 0.0
var poison_timer: float = 0.0

# Buff de velocidad de la munición Electron
var electron_speed_buff_timer: float = 0.0
var electron_speed_buff_pct: float = 0.0
var electron_speed_buff_stacks: int = 0

# v410: Polimorfia (Cubito)
var is_polymorphed: bool = false
var poly_timer: float = 0.0
var poly_can_move: bool = false
var poly_can_use_skills: bool = true

func _ready():
	load_ammo_slots_local()
	super._ready() 
	add_to_group("player")
	target_position = global_position
	# Forzar ocultamiento en el inicio hasta que el login sea exitoso
	visible = false
	
	collision_layer = 1
	collision_mask = 2
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	
	_cam_node = get_node_or_null("Camera2D")
	if not _cam_node:
		_cam_node = get_viewport().get_camera_2d()
	
	if NetworkManager:
		NetworkManager.login_success.connect(_on_login_success)
		if NetworkManager.has_signal("cast_started"):
			NetworkManager.cast_started.connect(_on_remote_cast_started)
		if NetworkManager.has_signal("cast_cancelled"):
			NetworkManager.cast_cancelled.connect(_on_remote_cast_cancelled)
		NetworkManager.inventory_data.connect(_on_inventory_received)
		NetworkManager.slow_state.connect(_on_slow_state)
		NetworkManager.stun_state.connect(_on_stun_state)
		NetworkManager.environment_damaged.connect(_on_environment_damaged)
		NetworkManager.status_effects_sync.connect(_on_status_effects_sync)
		if not NetworkManager.config_updated.is_connected(_on_config_updated_recalc):
			NetworkManager.config_updated.connect(_on_config_updated_recalc)
		if not NetworkManager.connection_lost.is_connected(_on_connection_lost_player):
			NetworkManager.connection_lost.connect(_on_connection_lost_player)
	
	# v690.2: Si cambia una esfera, validar que las municiones equipadas sigan cumpliendo requisitos
	var sm_node = get_node_or_null("SpheresManager")
	if sm_node and not sm_node.spheres_updated.is_connected(_validate_ammo_slot_requirements):
		sm_node.spheres_updated.connect(_validate_ammo_slot_requirements)
	
	_setup_skill_controller()

# v690.2: Quitar automáticamente municiones equipadas que dejaron de cumplir requisitos
# (ej: se cambió la esfera de un color y la munición exigía esferas de ese color).
# Avisa en el log del HUD qué se removió y por qué.
func _validate_ammo_slot_requirements():
	if not NetworkManager or not NetworkManager.has_method("check_equip_requirements"):
		return
	if ammo_slots.is_empty():
		return
	var removed := false
	for i in range(ammo_slots.size()):
		var a_type: String = str(ammo_slots[i])
		if a_type == "" or a_type == "laser":
			continue
		var tier = int(selected_ammo.get(a_type, 0))
		var req_check = NetworkManager.check_equip_requirements("", "", a_type, tier)
		if not req_check.get("ok", true):
			ammo_slots[i] = ""
			removed = true
			var a_name: String = _ammo_display_name(a_type)
			var reason: String = str(req_check.get("msg", "requisitos no cumplidos"))
			print("[PLAYER] Munición removida del slot ", i + 1, " (", a_name, "): ", reason)
			NetworkManager.game_notification.emit({
				"msg": "⚠️ MUNICIÓN REMOVIDA DEL SLOT " + str(i + 1) + ": " + a_name + " (" + reason + ")",
				"type": "error"
			})
	if removed:
		save_ammo_slots_local()
		var hud = get_tree().get_first_node_in_group("hud")
		if is_instance_valid(hud) and hud.has_method("update_skill_slots"):
			hud.update_skill_slots()

func _on_config_updated_recalc(_cfg):
	_recalculate_stats()

func _on_environment_damaged(data: Dictionary):
	var dmg = float(data.get("damage", 0.0))
	if dmg > 0:
		# Detenemos la falsa regeneración local avisando a Godot que estamos en combate
		last_combat_time = Time.get_ticks_msec() 
		
		var isLifeSteal = data.get("isLifeSteal", false)
		if isLifeSteal:
			# Robo de vida: bypass del escudo, daño directo a HP
			current_hp -= dmg
			if current_hp < 0: current_hp = 0
		else:
			# Aplicamos el daño visualmente para que las barras bajen al instante 
			# (Evita el salto brusco cuando llega el vSync del servidor)
			if current_shield >= dmg:
				current_shield -= dmg
			else:
				current_hp -= (dmg - current_shield)
				current_shield = 0
			
			if current_hp < 0: current_hp = 0
		
		var isShieldDrain = data.get("isShield", false)
		if isLifeSteal:
			# Robo de vida (life_steal): numero verde con signo negativo
			_spawn_damage_text("-" + str(int(dmg)), Color(0.2, 1.0, 0.35))
			apply_shake(1.0)
		elif isShieldDrain:
			# Robo de escudo (shield_steal): numero celeste con signo negativo
			_spawn_damage_text("-" + str(int(dmg)), Color(0.0, 0.9, 0.95))
			apply_shake(1.0)
		else:
			# Daño normal
			_spawn_damage_text(str(int(dmg)), Color.RED)
			apply_shake(2.0)
		
		if current_hp <= 0:
			die()

func _on_slow_state(data: Dictionary):
	if data.has("active"):
		if data.active:
			slow_points = data.get("amount", slow_points)
			slow_is_percentage = data.get("isPercentage", slow_is_percentage)
			slow_timer = float(data.get("duration", 3000.0)) / 1000.0
			if data.get("isSleep", false):
				_sleep_grace = 10.0
				_start_sleep_aura()
		else:
			slow_points = 0.0
			slow_is_percentage = false
			slow_timer = 0.0
			if data.get("isSleep", false):
				_stop_sleep_aura()

var _sleep_aura: Node2D = null
var _sleep_grace: float = 0.0

func _start_sleep_aura() -> void:
	if is_instance_valid(_sleep_aura):
		if _sleep_aura.has_method("start_aura"):
			_sleep_aura.start_aura()
		return
	if not SLEEP_AURA_SCRIPT:
		return
	var aura := Node2D.new()
	aura.set_script(SLEEP_AURA_SCRIPT)
	aura.name = "SleepAura"
	aura.z_index = 15
	aura.z_as_relative = false
	add_child(aura)
	if aura.has_method("start_aura"):
		aura.start_aura()
	_sleep_aura = aura

func _stop_sleep_aura() -> void:
	if is_instance_valid(_sleep_aura) and _sleep_aura.has_method("stop_aura"):
		_sleep_aura.stop_aura()

func _on_status_effects_sync(data: Dictionary):
	if is_casting and (data.has("stun") or data.has("slow") or data.has("poly")):
		# if any CC arrives during cast, cancel
		if float(data.get("stun", 0)) > 0 or float(data.get("poly", 0)) > 0:
			_cancel_cast("cc")
	if data.has("stun"):
		stun_timer = float(data.stun) / 1000.0
		set_debuff_timer("stun", stun_timer)
		# v413: Fallback visual - si el stun persiste dentro del contexto de sueño
		# (por si el evento stunState directo se perdió), activar/desactivar las Z.
		if _sleep_grace > 0.0:
			if stun_timer > 0.0:
				_start_sleep_zzz()
			else:
				_stop_sleep_zzz()
	if data.has("slow"):
		slow_timer = float(data.slow) / 1000.0
		set_debuff_timer("slow", slow_timer)
	if data.has("stun"):
		stun_timer = float(data.stun) / 1000.0
		set_debuff_timer("stun", stun_timer)
	if data.has("heal"):
		heal_timer = float(data.heal) / 1000.0
		heal_stacks = int(data.get("healStacks", 1))
		set_debuff_timer("heal", heal_timer, heal_stacks)
	if data.has("bleed"):
		bleed_timer = float(data.bleed) / 1000.0
		set_debuff_timer("bleed", bleed_timer)
	if data.has("poison"):
		poison_timer = float(data.poison) / 1000.0
		set_debuff_timer("poison", poison_timer)
	if data.has("poly"):
		poly_timer = float(data.poly) / 1000.0
		is_polymorphed = poly_timer > 0.0
		if not is_polymorphed:
			poly_timer = 0.0
			poly_can_move = true
			poly_can_use_skills = true
			modulate = Color.WHITE
		else:
			modulate = Color(0.7, 0.95, 1.0, 1.0)
			# v410.1: Restaurar flags de poly desde la sincronización periódica de estado
			if data.has("polyCanUseSkills"):
				poly_can_use_skills = str(data.polyCanUseSkills) == "true" or data.polyCanUseSkills == true
			if data.has("polyCanMove"):
				poly_can_move = str(data.polyCanMove) == "true" or data.polyCanMove == true
		set_debuff_timer("poly", poly_timer)
	if data.has("electronSpeedBuff"):
		var eb = data.electronSpeedBuff
		electron_speed_buff_timer = float(eb.get("duration", 3000.0)) / 1000.0
		electron_speed_buff_pct = float(eb.get("pct", 15.0))
		electron_speed_buff_stacks = int(eb.get("stacks", 1))
		set_debuff_timer("electron_speed", electron_speed_buff_timer, electron_speed_buff_stacks)
		_recalculate_stats()

func _on_stun_state(data: Dictionary):
	if data.has("active") and data.active:
		if is_casting:
			_cancel_cast("cc")
		if data.get("isFear", false):
			is_feared = true
			fear_timer = float(data.get("duration", 3000.0)) / 1000.0
			is_stunned = false
			is_moving = false
			autopilot_enabled = false
			joystick_direction = Vector2.ZERO
			
			set_debuff_timer("fear", fear_timer, 1)
			
			if velocity.length() > 10.0:
				fear_vector = -velocity.normalized()
			else:
				fear_vector = Vector2.RIGHT.rotated(rotation + PI)
				
			var tw = create_tween()
			tw.tween_property(self, "modulate", Color(0.9, 0.2, 0.2, 1.0), 0.2)
		else:
			is_stunned = true
			stun_timer = float(data.get("duration", 2000.0)) / 1000.0
			is_moving = false
			target_position = global_position
			velocity = Vector2.ZERO
			apply_shake(5.0)
			# Feedback visual: Azulado/Gris o violeta para Sueño (Sleep)
			var target_color = Color(0.8, 0.4, 1.0, 1.0) if data.get("isSleep", false) else Color(0.7, 0.7, 1.0, 1.0)
			var tw = create_tween()
			tw.tween_property(self, "modulate", target_color, 0.2)
			if data.get("isSleep", false):
				_sleep_grace = 10.0
				_start_sleep_zzz()
	else:
		is_stunned = false
		is_feared = false
		stun_timer = 0.0
		fear_timer = 0.0
		modulate = Color.WHITE
		set_debuff_timer("fear", 0)
		set_debuff_timer("stun", 0)
		_stop_sleep_zzz()

var _sleep_zzz: Node2D = null

func _start_sleep_zzz() -> void:
	if is_instance_valid(_sleep_zzz):
		if _sleep_zzz.has_method("start_zzz"):
			_sleep_zzz.start_zzz()
		return
	if not SLEEP_ZZ_SCRIPT:
		return
	var zzz := Node2D.new()
	zzz.set_script(SLEEP_ZZ_SCRIPT)
	zzz.name = "SleepZZZ"
	zzz.z_index = 60
	zzz.z_as_relative = false
	# Adjuntar al wrapper de UI (misma capa que los números de daño) para
	# garantizar el render por encima de la nave.
	var target_parent = _ui_wrapper if is_instance_valid(_ui_wrapper) else self
	target_parent.add_child(zzz)
	if zzz.has_method("start_zzz"):
		zzz.start_zzz()
	_sleep_zzz = zzz

func _stop_sleep_zzz() -> void:
	if is_instance_valid(_sleep_zzz) and _sleep_zzz.has_method("stop_zzz"):
		_sleep_zzz.stop_zzz()

var _freeze_slow_val: float = 0.0 # v268.40: Ralentización ambiental independiente

func apply_freeze_slow(data: Dictionary):
	var duration = data.get("duration", 6000.0) / 1000.0
	var pct = float(data.get("slowPercentage", 0.0)) / 100.0
	var fixed = float(data.get("slowFixed", 0.0))
	
	# v268.45: Debug para verificar que los datos llegan bien
	
	# Calcular cuánto restamos (Basado en la velocidad actual para que el % sea real)
	var total_to_reduce = (speed * pct) + fixed
	_freeze_slow_val = total_to_reduce
	
	await get_tree().create_timer(duration).timeout
	
	# Recuperar velocidad suavemente
	var tw = create_tween()
	tw.tween_property(self, "_freeze_slow_val", 0.0, 1.5).set_trans(Tween.TRANS_SINE)

func _setup_skill_controller():
	if SKILL_CONTROLLER_SCRIPT:
		_skill_controller = SKILL_CONTROLLER_SCRIPT.new()
		_skill_controller.name = "SkillController"
		add_child(_skill_controller)

func _unhandled_input(event):
	if is_casting and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_cast("manual")
		get_viewport().set_input_as_handled()
		return
	if is_casting and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_cast("manual")
		get_viewport().set_input_as_handled()
		return
	if current_zone == 100:
		return
		
	# v226.50: Bloquear zoom si el mouse está sobre la UI (Evitar zoom al scrollear menús)
	if event is InputEventMouseButton:
		# v2.6: Bloqueo de SEGURIDAD para evitar click-through a cualquier menú abierto
		var ui_blocking = false
		for group in ["inventory_ui", "admin_panel_ui", "battlepass_ui"]:
			for node in get_tree().get_nodes_in_group(group):
				if node.visible:
					# v2.7: Si el menú está visible y bloquea mouse, impedimos movimiento
					if node.mouse_filter == Control.MOUSE_FILTER_STOP:
						ui_blocking = true; break
		
		if ui_blocking: return

		if get_viewport().gui_get_hovered_control() != null:
			return
			
		# Procesar Movimiento (Click) - Con botón configurable según settings
		if event.pressed:
			var is_mobile = SettingsManager and SettingsManager.mobile_mode
			if not is_mobile:
				var move_btn = MOUSE_BUTTON_RIGHT
				if SettingsManager and SettingsManager.get("control_move_btn") == "LMB":
					move_btn = MOUSE_BUTTON_LEFT
				
				if event.button_index == move_btn:
					if is_casting:
						_cancel_cast("manual")
						return
					var map_node = get_tree().get_first_node_in_group("map")
					if is_instance_valid(map_node):
						if "mouse_world_pos_2d" in map_node:
							target_position = map_node.mouse_world_pos_2d
					is_moving = true; autopilot_enabled = false




func _physics_process(p_delta):
	if current_hp <= 0 and not is_dead:
		die()
		return

	# Evaluar visibilidad antes del retorno de red para mantener la nave oculta sin conexión inicial
	if NetworkManager and not NetworkManager.is_logged_in:
		if visible:
			visible = false
		if is_instance_valid(world_root_3d):
			world_root_3d.visible = false
		if is_instance_valid(_ui_wrapper):
			_ui_wrapper.visible = false
	else:
		if current_zone != 100 and not visible and not is_dead:
			visible = true
			
	if not is_instance_valid(NetworkManager) or not NetworkManager.network_connected: 
		velocity = Vector2.ZERO
		return
	
	if current_zone == 100:
		if visible:
			visible = false
		velocity = Vector2.ZERO
		return
	else:
		pass

	_handle_cooldowns(p_delta)
	# Remote cast tick
	if _remote_cast_active:
		_remote_cast_elapsed += p_delta
		var progR = clamp(_remote_cast_elapsed / max(0.01, _remote_cast_duration), 0.0, 1.0)
		_update_cast_visual(progR)
		rotation = lerp_angle(rotation, _remote_cast_angle, 0.25)
		if _remote_cast_elapsed >= _remote_cast_duration:
			_clear_remote_cast_visual()
	# Decrementar temporizadores de efectos de estado activos
	if slow_timer > 0.0:
		slow_timer = max(0.0, slow_timer - p_delta)
	if heal_timer > 0.0:
		heal_timer = max(0.0, heal_timer - p_delta)
		if heal_timer <= 0.0:
			heal_stacks = 0
	if bleed_timer > 0.0:
		bleed_timer = max(0.0, bleed_timer - p_delta)
	if poison_timer > 0.0:
		poison_timer = max(0.0, poison_timer - p_delta)
	if electron_speed_buff_timer > 0.0:
		electron_speed_buff_timer = max(0.0, electron_speed_buff_timer - p_delta)
		if electron_speed_buff_timer <= 0.0:
			electron_speed_buff_stacks = 0
			_recalculate_stats()
	if _sleep_grace > 0.0:
		_sleep_grace = max(0.0, _sleep_grace - p_delta)
	
	# ==== CASTEO LOCAL: congelar y bloquear input/movimiento ====
	if is_casting:
		var chat_c = get_tree().get_first_node_in_group("chat_ui")
		var focus_node_c = get_viewport().gui_get_focus_owner()
		var is_typing_c = (chat_c and chat_c.has_method("is_typing") and chat_c.is_typing()) or (focus_node_c is LineEdit or focus_node_c is TextEdit)
		if not is_typing_c:
			_handle_input()
		if _update_cast(p_delta):
			_update_shake(p_delta)
			_sync_with_server(p_delta)
			return
	
	if is_feared:
		fear_timer -= p_delta
		if fear_timer <= 0:
			is_feared = false
			modulate = Color.WHITE

	if is_stunned:
		stun_timer -= p_delta
		if stun_timer <= 0:
			is_stunned = false
			modulate = Color.WHITE
		return # Bloquear TODO el proceso si está stuneado

	# v410: Polimorfia - Bloquear movimiento/habilidades según checks configurables
	if is_polymorphed:
		poly_timer -= p_delta
		if poly_timer <= 0:
			is_polymorphed = false
			_poly_authoritative = false
			poly_can_move = true
			poly_can_use_skills = true
			modulate = Color.WHITE
			status_effects["polymorphed"] = false
			_force_clear_poly_visual()
		else:
			_poly_authoritative = true
			status_effects["polymorphed"] = true
			# Si no puede moverse, bloquear el proceso (como stun),
			# pero si puede usar habilidades, procesarlas igual antes de salir
			if not poly_can_move:
				if poly_can_use_skills:
					var chat_node = get_tree().get_first_node_in_group("chat_ui")
					var focus_node_p = get_viewport().gui_get_focus_owner()
					var is_typing_p = (chat_node and chat_node.has_method("is_typing") and chat_node.is_typing()) or (focus_node_p is LineEdit or focus_node_p is TextEdit)
					if not is_typing_p:
						_handle_input()
				return
	
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
	_handle_slot_input("slot_1", ammo_slots[0], -1)
	_handle_slot_input("slot_2", ammo_slots[1], -1)
	_handle_slot_input("slot_3", ammo_slots[2], -1)
	
	# Esferas (Slots 4 al 7) - v266.65: Auto-detección centralizada
	for i in range(4):
		var slot_name = "slot_" + str(i + 4)
		var s_id = "sphere_" + str(i)
		_handle_slot_input(slot_name, s_id, -1)
	
	# Quedarse quieto: cancela la navegación por click/autopilot
	if Input.is_action_just_pressed("stay_still"):
		stay_still()

# v420: Detener el movimiento actual (click, autopilot) y quedarse quieto
func stay_still():
	if is_casting:
		_cancel_cast("manual")
		return
	is_moving = false
	autopilot_enabled = false
	target_position = global_position
	velocity = Vector2.ZERO

func _handle_slot_input(action: String, skill_id: String, type: int):
	# Auto-crear acción si no existe para evitar errores
	if not InputMap.has_action(action): 
		InputMap.add_action(action)
		return

	if Input.is_action_just_pressed(action):
		trigger_skill_by_id(skill_id, type)
	
	if Input.is_action_just_released(action):
		if _skill_controller.is_aiming and _skill_controller.current_skill.id == skill_id:
			if _skill_controller.config.get("cast_mode") == 1: # ON_RELEASE
				_skill_controller.execute_skill()

# v266.30: Método público para disparar desde el HUD (Celulares/Mouse)
func trigger_skill_by_id(skill_id: String, type: int = -1):
	if skill_id == "":
		return
	# v410: Bloqueo de habilidades por Polimorfia
	if is_polymorphed and not poly_can_use_skills:
		return
	
	# v268.30: Bloqueo por Interferencia Ambiental
	if get_meta("skills_blocked", false):
		return
	
	# Zona segura (Lobby): bloquear disparos de municiones y uso de habilidades
	if _is_safe_zone():
		_notify_safe_zone_block()
		return
	
	# Bloquear skills solo en modo paneo (cámara libre sin seguir al jugador)
	if get_node_or_null("/root/SettingsManager") and SettingsManager.cam_free_active and not SettingsManager.cam_free_orbit:
		return
		
	# v420: Slots bloqueados o vacíos NO generan apuntado ni círculo de rango
	if skill_id.begins_with("sphere_"):
		var eq_idx = int(skill_id.replace("sphere_", ""))
		var eq_sm = get_node_or_null("SpheresManager")
		var eq_sph = eq_sm.get_equipped_skill(eq_idx) if eq_sm else null
		if eq_sph == null:
			_notify_skill_block("SIN HABILIDAD EQUIPADA EN SLOT " + str(eq_idx + 4))
			return
		if NetworkManager and NetworkManager.has_method("check_sphere_slot_requirements"):
			var slot_check = NetworkManager.check_sphere_slot_requirements(eq_idx)
			if not slot_check.get("ok", true):
				_notify_skill_block("SLOT BLOQUEADO: " + str(slot_check.get("msg", "REQUISITOS NO CUMPLIDOS")))
				return
	elif skill_id in ["laser", "missile", "mine", "melee", "heal", "siphon", "emp", "electron"]:
		# v690.1: Validación de requisitos para TODOS los tipos de munición (antes solo laser/missile/mine)
		var eq_tier = selected_ammo.get(skill_id, 0)
		var eq_ammo_list = GameConstants.SHOP_ITEMS.ammo.get(skill_id, [])
		if eq_tier < 0 or eq_tier >= eq_ammo_list.size():
			_notify_skill_block("SIN MUNICIÓN EQUIPADA (" + _ammo_display_name(skill_id) + ")")
			return
		if NetworkManager and NetworkManager.has_method("check_equip_requirements"):
			var req_check = NetworkManager.check_equip_requirements("", "", skill_id, eq_tier)
			if not req_check.get("ok", true):
				_notify_skill_block("MUNICIÓN BLOQUEADA: " + str(req_check.get("msg", "REQUISITOS NO CUMPLIDOS")))
				return
		var own_ammo: Array = ammo.get(skill_id, [])
		if eq_tier >= own_ammo.size() or int(own_ammo[eq_tier]) <= 0:
			_notify_skill_block("SIN MUNICIÓN (" + _ammo_display_name(skill_id) + ") EN INVENTARIO")
			return
		
	var cd = cooldowns.get(skill_id, 0.0)
	if cd <= 0:
		var r_val = 600.0 # Default
		var filters = {}
		var s_name = skill_id # Fallback para armas base (laser, missile, mine)
		var s_type = type
		
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
						
						# v266.60: Auto-detección de tipo si no se especificó (o es -1)
						if s_type == -1:
							s_type = 3 # Instant por defecto
							if s_name == "ESFERA DE TERROR": s_type = 0 # Siempre apuntable (Directional)
							elif s_data.get("canTargetOthers", false) and s_name != "FROST-TRAIL": s_type = 1 # PointClick
							elif s_name == "RESURRECCIÓN" or s_name == "BALIZA DE CURACION" or s_name == "REGENERACIÓN ALFA": s_type = 2 # Area
							elif s_name == "PROVOCACION": s_type = 3 # Instant (self-cast charge)
							elif s_data.get("range", 0) > 0 and s_name != "FROST-TRAIL": s_type = 0 # Directional
		elif s_type == -1:
			s_type = 0 # Laser/Missile/Mine son Directional
			var t_idx = selected_ammo.get(skill_id, 0)
			var ammo_list = GameConstants.SHOP_ITEMS.ammo.get(skill_id, [])
			if t_idx < ammo_list.size():
				r_val = ammo_list[t_idx].get("range", 600.0)
		
		# Auto-target self logic
		if Input.is_action_pressed("auto_target_self") and skill_id.begins_with("sphere_"):
			_on_skill_executed({
				"skill_id": skill_id,
				"angle": 0.0,
				"target": self,
				"pos": global_position
			})
			return
		
		_skill_controller.start_aiming({"id": skill_id, "type": s_type, "range": r_val, "filters": filters, "skill_name": s_name})

func _on_skill_executed(p_data: Dictionary):
	var id = p_data.skill_id
	if id in ["laser", "missile", "mine", "melee", "heal", "siphon", "emp", "electron"]:
		_shoot_skill(id, p_data.angle, p_data.get("pos", Vector2.ZERO))
	elif id.begins_with("sphere_"):
		var s_idx = int(id.replace("sphere_", ""))
		_use_sphere_skill(s_idx, p_data) # v260.91: Integración con lógica de esferas y targeting

func is_in_combat() -> bool:
	return (Time.get_ticks_msec() - last_combat_time) < 5000

func _use_heal_skill(p_target):
	if p_target:
		# Enviar al servidor...
		NetworkManager.send_event("playerHeal", {"targetId": p_target.entity_id, "amount": 500})


var cooldowns = {
	"laser": 0.0, "missile": 0.0, "mine": 0.0,
	"melee": 0.0, "heal": 0.0, "siphon": 0.0, "emp": 0.0, "electron": 0.0,
	"sphere_0": 0.0, "sphere_1": 0.0, "sphere_2": 0.0, "sphere_3": 0.0
}
func _handle_cooldowns(p_delta):
	for s in cooldowns:
		if cooldowns[s] > 0: cooldowns[s] -= p_delta

# ==== CASTEO HELPERS ====
func _get_ammo_cast_ms(p_type: String, p_tier: int) -> float:
	if GameConstants.SHOP_ITEMS and GameConstants.SHOP_ITEMS.has("ammo"):
		var ammo_cfg = GameConstants.SHOP_ITEMS["ammo"].get(p_type, [])
		if p_tier >= 0 and p_tier < ammo_cfg.size():
			return float(ammo_cfg[p_tier].get("castTimeMs", ammo_cfg[p_tier].get("castTime", 0)))
	return 0.0

func _get_skill_cast_ms(skill_name: String) -> float:
	if skill_name == "":
		return 0.0
	var key = skill_name.to_upper().strip_edges().replace("Ó","O").replace("É","E").replace("Í","I").replace("Á","A").replace("Ú","U")
	if GameConstants.SKILLS_DATA.has(skill_name):
		return float(GameConstants.SKILLS_DATA[skill_name].get("castTimeMs", 0))
	if GameConstants.SKILLS_DATA.has(key):
		return float(GameConstants.SKILLS_DATA[key].get("castTimeMs", 0))
	return 0.0

func _get_cast_color(p_type: String, p_detail: String) -> Color:
	if p_type == "ammo":
		var ammo_type = p_detail.to_lower()
		match ammo_type:
			"laser": return Color(0.95, 0.15, 0.15)      # Rojo fuerte
			"missile": return Color(1.0, 0.45, 0.0)      # Naranja brillante
			"mine": return Color(0.95, 0.75, 0.0)       # Amarillo/Naranja
			"melee": return Color(0.85, 0.25, 0.0)      # Rojo oscuro / Fuego
			"heal": return Color(0.15, 0.95, 0.15)       # Verde curación
			"siphon": return Color(0.85, 0.0, 0.85)      # Fucsia/Vampírico
			"emp": return Color(0.0, 0.75, 1.0)         # Celeste/Azul eléctrico
			"electron": return Color(1.0, 0.9, 0.0)     # Amarillo eléctrico
			_: return Color.WHITE
	elif p_type == "skill":
		var skill_name = p_detail.to_upper().strip_edges().replace("Ó","O").replace("É","E").replace("Í","I").replace("Á","A").replace("Ú","U")
		if GameConstants.SKILLS_DATA.has(skill_name):
			var s_data = GameConstants.SKILLS_DATA[skill_name]
			var raw_type = str(s_data.get("type", "ataque")).to_lower()
			if "ataque" in raw_type:
				return Color(0.9, 0.35, 0.3)
			elif "defensa" in raw_type:
				return Color(0.3, 0.65, 0.9)
			elif "curacion" in raw_type or "curación" in raw_type:
				return Color(0.35, 0.85, 0.4)
			elif "utilidad" in raw_type or "movimiento" in raw_type:
				return Color(0.95, 0.9, 0.35)
		if GameConstants.SKILLS_DATA.has(p_detail):
			var s_data = GameConstants.SKILLS_DATA[p_detail]
			var raw_type = str(s_data.get("type", "ataque")).to_lower()
			if "ataque" in raw_type:
				return Color(0.9, 0.35, 0.3)
			elif "defensa" in raw_type:
				return Color(0.3, 0.65, 0.9)
			elif "curacion" in raw_type or "curación" in raw_type:
				return Color(0.35, 0.85, 0.4)
			elif "utilidad" in raw_type or "movimiento" in raw_type:
				return Color(0.95, 0.9, 0.35)
	return Color.WHITE

func _start_cast(p_duration_ms: float, p_type: String, p_angle: float, p_payload: Dictionary) -> bool:
	if is_casting:
		return false
	if p_duration_ms <= 0:
		return false
	is_casting = true
	cast_duration = float(p_duration_ms) / 1000.0
	cast_elapsed = 0.0
	cast_type = p_type
	cast_payload = p_payload.duplicate(true)
	cast_angle = p_angle
	cast_start_pos = global_position
	# Congelar nave completamente
	is_moving = false
	autopilot_enabled = false
	target_position = global_position
	velocity = Vector2.ZERO
	joystick_direction = Vector2.ZERO
	rotation = p_angle
	if NetworkManager and NetworkManager.has_method("send_event"):
		var pos_v = p_payload.get("pos", Vector2.ZERO)
		if typeof(pos_v) != TYPE_VECTOR2:
			pos_v = Vector2.ZERO
		if p_type == "ammo":
			var tier = int(selected_ammo.get(p_payload.get("type","laser"), 0))
			NetworkManager.send_event("playerCastStart", {"ammoType": p_payload.get("type","laser"), "ammoTier": tier, "angle": p_angle, "x": global_position.x, "y": global_position.y, "targetId": p_payload.get("targetId", null), "posX": pos_v.x, "posY": pos_v.y})
		else:
			NetworkManager.send_event("playerCastStart", {"skillName": p_payload.get("skillName",""), "sphereIdx": p_payload.get("sphereIdx", -1), "angle": p_angle, "x": global_position.x, "y": global_position.y, "targetId": p_payload.get("targetId", null), "posX": pos_v.x, "posY": pos_v.y})
	_force_move_sync()
	
	var detail = ""
	if p_type == "ammo":
		detail = p_payload.get("type", "laser")
	else:
		detail = p_payload.get("skillName", "")
		
	_ensure_cast_visual(p_type, detail)
	_update_cast_visual(0.0)
	return true

func _update_cast(p_delta: float) -> bool:
	if not is_casting:
		return false
	# Cancelar si entra stun/fear/poly/dead
	if is_stunned or is_feared or (is_polymorphed and not poly_can_move) or is_dead:
		_cancel_cast("cc")
		return true
	cast_elapsed += p_delta
	# Mantener congelada y apuntando
	rotation = lerp_angle(rotation, cast_angle, 0.35)
	is_moving = false
	autopilot_enabled = false
	velocity = Vector2.ZERO
	target_position = cast_start_pos
	global_position = cast_start_pos
	var prog = clamp(cast_elapsed / max(0.01, cast_duration), 0.0, 1.0)
	_update_cast_visual(prog)
	if cast_elapsed >= cast_duration:
		_execute_cast()
		return true
	return true

func _execute_cast():
	_clear_cast_visual()
	var payload = cast_payload.duplicate(true)
	var was_type = cast_type
	var was_angle = cast_angle
	is_casting = false
	cast_duration = 0.0
	cast_elapsed = 0.0
	cast_type = ""
	cast_payload = {}
	cast_angle = 0.0
	if was_type == "ammo":
		_do_shoot_immediate(payload.get("type","laser"), was_angle, payload.get("pos", Vector2.ZERO), payload.get("targetId", null))
	elif was_type == "skill":
		var sid = int(payload.get("sphereIdx", -1))
		var pdata = {"angle": was_angle, "pos": payload.get("pos", global_position), "target": payload.get("target", null)}
		_do_sphere_skill_immediate(sid, pdata)
	
	# Procesar el buffer de casteo de forma diferida para evitar conflictos del frame actual
	call_deferred("_check_and_process_cast_buffer")

func _cancel_cast(reason: String = "manual"):
	if not is_casting:
		return
	_clear_cast_visual()
	_buffered_cast_action = {} # Limpiar el buffer ante interrupciones
	is_casting = false
	cast_duration = 0.0
	cast_elapsed = 0.0
	cast_type = ""
	cast_payload = {}
	cast_angle = 0.0
	if NetworkManager and NetworkManager.has_method("send_event"):
		NetworkManager.send_event("playerCastCancel", {"reason": reason})
	# feedback leve
	if reason == "manual":
		pass

func _check_and_process_cast_buffer():
	if _buffered_cast_action.is_empty():
		return
		
	var now = Time.get_ticks_msec()
	var elapsed = now - _buffered_cast_time
	if elapsed > CAST_BUFFER_WINDOW_MS:
		print("[BUFFER] Acción encolada expiró: ", elapsed, "ms")
		_buffered_cast_action = {}
		return
		
	var action = _buffered_cast_action.duplicate(true)
	_buffered_cast_action = {} # Limpiar para evitar recursiones
	
	print("[BUFFER] Procesando acción encolada del buffer...")
	if action.action_type == "ammo":
		_shoot_skill(action.ammo_type, action.angle, action.pos)
	elif action.action_type == "skill":
		_use_sphere_skill(action.sphere_id, action.payload)

func is_currently_casting() -> bool:
	return is_casting

func _get_hud_base_y() -> float:
	var base_y = -70.0
	if is_in_group("player"):
		base_y = -105.0
	elif entity_type >= 101:
		base_y = -220.0
		
	var is_projected = get_meta("is_single_world", false) and is_instance_valid(world_root_3d)
	if is_projected:
		base_y = 0.0
	return base_y

func _ensure_cast_visual(p_type: String, p_detail: String):
	_current_cast_color = _get_cast_color(p_type, p_detail)
	_ensure_cast_visual_2d(p_type, p_detail)

func _ensure_cast_visual_2d(_p_type: String, _p_detail: String):
	if is_instance_valid(_cast_visual_2d):
		return
	var ui = get("_ui_wrapper")
	if not is_instance_valid(ui):
		ui = get_node_or_null("HUD_Layer_Final")
	if not is_instance_valid(ui):
		return
		
	var base_y = _get_hud_base_y()
	
	var container = Control.new()
	container.name = "CastBar2D"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ancho 44 (mismo de la barra de vida), alto 2 (mitad de 4)
	container.custom_minimum_size = Vector2(44, 2)
	container.size = Vector2(44, 2)
	# Centrado en X (-22) y posicionado debajo de la barra de vida (base_y + 2.0)
	container.position = Vector2(-22, base_y + 2.0)
	container.z_index = 10
	
	var bg = ColorRect.new()
	bg.name = "BG"
	bg.color = Color(0.08, 0.08, 0.1, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(bg)
	
	var fg = ColorRect.new()
	fg.name = "FG"
	fg.color = _current_cast_color
	fg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fg.anchor_right = 0
	fg.offset_left = 0
	fg.offset_right = 0
	fg.offset_top = 0
	fg.offset_bottom = 0
	container.add_child(fg)
	
	ui.add_child(container)
	_cast_visual_2d = container

func _update_cast_visual(progress: float):
	progress = clamp(progress, 0.0, 1.0)
	if is_instance_valid(_cast_visual_2d):
		var fg = _cast_visual_2d.get_node_or_null("FG")
		if is_instance_valid(fg):
			fg.anchor_right = progress
			fg.color = _current_cast_color

func _clear_cast_visual():
	if is_instance_valid(_cast_visual_2d):
		_cast_visual_2d.queue_free()
		_cast_visual_2d = null

func _start_remote_cast_visual(duration_ms: float, angle: float, p_type: String, p_detail: String):
	_remote_cast_active = true
	_remote_cast_duration = max(0.01, float(duration_ms)/1000.0)
	_remote_cast_elapsed = 0.0
	_remote_cast_angle = angle
	rotation = angle
	_ensure_cast_visual(p_type, p_detail)
	_update_cast_visual(0.0)

func _clear_remote_cast_visual():
	_remote_cast_active = false
	_remote_cast_duration = 0.0
	_remote_cast_elapsed = 0.0
	_clear_cast_visual()

func _on_remote_cast_started(data: Dictionary):
	var sid = str(data.get("id",""))
	if sid != str(entity_id):
		return
	var dur = float(data.get("duration", 0))
	var ang = float(data.get("angle", rotation))
	var c_type = str(data.get("type", "ammo"))
	var detail = ""
	if c_type == "ammo":
		detail = str(data.get("ammoType", "laser"))
	else:
		detail = str(data.get("skillName", ""))
	_start_remote_cast_visual(dur, ang, c_type, detail)

func _on_remote_cast_cancelled(data: Dictionary):
	var sid = str(data.get("id",""))
	if sid != str(entity_id):
		return
	_clear_remote_cast_visual()



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
		if gd.has("level"): level = int(gd["level"])
		if gd.has("exp"): current_exp = float(gd["exp"])

		
		# v300.81: Los talentos ahora se sincronizan SOLO a través del TalentSystem.gd
		# Evitamos duplicidad de datos en Player.gd
		
		# v240.95: Sincronía de Munición en Tiempo Real (Fix Shop Update)
		if gd.has("ammo") and typeof(gd["ammo"]) == TYPE_DICTIONARY:
			ammo = gd["ammo"].duplicate()
		if gd.has("selectedAmmo") and typeof(gd["selectedAmmo"]) == TYPE_DICTIONARY:
			selected_ammo = gd["selectedAmmo"].duplicate()
		
		# v235.95: Persistencia de Esferas Orbitales
		if gd.has("spheres"):
			var sm = get_node_or_null("SpheresManager")
			if sm:
				var sph_data = gd["spheres"]
				for i in range(min(sph_data.size(), 4)):
					# v760.0: Sincronizar slot completo (esfera instalada + skill equipada)
					sm.equip_item(i, sph_data[i])

	
	_recalculate_stats()

func _recalculate_stats():
	var total_sh_bonus = 0.0
	var total_hp_bonus = 0.0
	var speed_bonus = 0.0
	var hp_mod_flat = 0.0
	var hp_mod_pct = 0.0
	var speed_mod_flat = 0.0
	var speed_mod_pct = 0.0
	var shield_mod_flat = 0.0
	var shield_mod_pct = 0.0
	var dmg_mod_flat = 0.0
	var dmg_mod_pct = 0.0
	
	var ship_base = { "hp": 3000, "shield": 1000, "speed": 300, "vision": 1300.0, "baseDmg": 100.0 }
	for ship in GameConstants.SHIP_MODELS:
		if ship.id == current_ship_id:
			ship_base = ship
			break
			
	var base_dmg_val = 100.0
	if ship_base.has("baseDmg"):
		base_dmg_val = float(ship_base.baseDmg)
	elif ship_base.has("base_damage"):
		base_dmg_val = float(ship_base.base_damage)
		
	base_laser_damage = base_dmg_val
	
	for cat in equipped:
		var slot_list = equipped[cat]
		if typeof(slot_list) != TYPE_ARRAY: continue
		for item in slot_list:
			if typeof(item) != TYPE_DICTIONARY: continue
			var type = str(item.get("type", cat)).to_lower()
			var bonus = float(item.get("base", 0))
			if type == "w" or type == "laser" or cat == "w":
				base_laser_damage += bonus
				var sv = float(item.get("speedMod", 0))
				if item.get("speedModType", "percent") == "flat": speed_mod_flat += sv
				else: speed_mod_pct += sv
				var hv = float(item.get("hpMod", 0))
				if item.get("hpModType", "percent") == "flat": hp_mod_flat += hv
				else: hp_mod_pct += hv
			elif type == "s" or type == "shield" or cat == "s":
				total_sh_bonus += bonus
				var hv = float(item.get("hpMod", 0))
				if item.get("hpModType", "percent") == "flat": hp_mod_flat += hv
				else: hp_mod_pct += hv
				var sv = float(item.get("speedMod", 0))
				if item.get("speedModType", "percent") == "flat": speed_mod_flat += sv
				else: speed_mod_pct += sv
			elif type == "e" or type == "engine" or cat == "e":
				speed_bonus += bonus
				var shv = float(item.get("shieldMod", 0))
				if item.get("shieldModType", "percent") == "flat": shield_mod_flat += shv
				else: shield_mod_pct += shv
				var hv = float(item.get("hpMod", 0))
				if item.get("hpModType", "percent") == "flat": hp_mod_flat += hv
				else: hp_mod_pct += hv
			elif type == "h" or type == "hp" or type == "x" or cat == "h" or cat == "x":
				total_hp_bonus += bonus
	
	vision_range = float(ship_base.get("vision", 1300.0))
			
	var base_hp_val = float(ship_base.get("hp", 3000)) + total_hp_bonus + hp_mod_flat
	var base_sh_val = float(ship_base.get("shield", 1000)) + total_sh_bonus + shield_mod_flat
	var base_speed_val = float(ship_base.get("speed", 300)) + speed_bonus + speed_mod_flat
	
	var hp_mod_mult = 1.0 + hp_mod_pct / 100.0
	var speed_mod_mult = 1.0 + speed_mod_pct / 100.0
	var shield_mod_mult = 1.0 + shield_mod_pct / 100.0
	var dmg_mod_mult = 1.0 + dmg_mod_pct / 100.0
	
	var talent_system = get_tree().get_first_node_in_group("talent_system")
	if is_instance_valid(talent_system):
		var bonuses = talent_system.get_bonuses()
		max_hp = base_hp_val * (1.0 + bonuses["hp_pct"]) * hp_mod_mult
		max_shield = base_sh_val * (1.0 + bonuses["sh_pct"]) * shield_mod_mult
		speed = base_speed_val * (1.0 + bonuses["speed_pct"]) * speed_mod_mult
		base_laser_damage = (base_laser_damage * (1.0 + bonuses["dmg_pct"]) * dmg_mod_mult) + dmg_mod_flat
	else:
		max_hp = base_hp_val * hp_mod_mult
		max_shield = base_sh_val * shield_mod_mult
		speed = base_speed_val * speed_mod_mult
		base_laser_damage = (base_laser_damage * dmg_mod_mult) + dmg_mod_flat
	
	if electron_speed_buff_timer > 0.0:
		speed = speed * (1.0 + (electron_speed_buff_pct * electron_speed_buff_stacks) / 100.0)
	
	save_progress()
	_update_tags()
	_emit_stats()

func take_damage(amt: float, attacker_pos: Vector2 = Vector2.ZERO, attacker_id: String = ""):
	if amt <= 0.0:
		return
	super.take_damage(amt, attacker_pos, attacker_id)
	apply_shake(amt * 0.15) # v260: Shake leve
	# v240.69: Eliminado envío duplicado al servidor. Projectile.gd ya se encarga de notificar 
	# el daño exacto con el enemyType correcto. Hacerlo aquí duplicaba el daño (1 hit = 2 hits) 
	# y enviaba eventos "fantasma" que reiniciaban contadores de combate.

func _is_safe_zone() -> bool:
	var safe_z = 1
	if NetworkManager and NetworkManager.server_config and NetworkManager.server_config.has("pilotConfig"):
		var pc = NetworkManager.server_config.pilotConfig
		if pc.has("startingMapId"):
			safe_z = int(pc.startingMapId)
	return current_zone == safe_z

func _notify_safe_zone_block():
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("notify"):
		hud.notify("ZONA SEGURA: El combate esta deshabilitado en el Lobby", "warn")

# v420: Cartel + log cuando un slot bloqueado/vacío intenta usarse
func _notify_skill_block(msg: String):
	print("[PLAYER] ", msg)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("notify"):
		hud.notify(msg, "warn")

func _ammo_display_name(ammo_type: String) -> String:
	match ammo_type:
		"laser": return "LÁSER"
		"missile": return "MISIL"
		"mine": return "MINA"
	return ammo_type.to_upper()

func _shoot_skill(p_type: String, p_angle: float, p_target_pos: Vector2 = Vector2.ZERO):
	if cooldowns.get(p_type, 0.0) > 0.0:
		return
	if is_casting:
		_buffered_cast_action = {
			"action_type": "ammo",
			"ammo_type": p_type,
			"angle": p_angle,
			"pos": p_target_pos
		}
		_buffered_cast_time = Time.get_ticks_msec()
		print("[BUFFER] Munición encolada en el buffer: ", p_type)
		return
	# Zona segura (Lobby): defensa en profundidad, nunca disparar
	if _is_safe_zone():
		return
	var t_idx_cast = selected_ammo.get(p_type, 0)
	var cast_ms_ammo = _get_ammo_cast_ms(p_type, t_idx_cast)
	if cast_ms_ammo > 0:
		var payload = {"type": p_type, "angle": p_angle, "pos": p_target_pos, "targetId": null}
		if _start_cast(cast_ms_ammo, "ammo", p_angle, payload):
			return
	_do_shoot_immediate(p_type, p_angle, p_target_pos, null)

func _do_shoot_immediate(p_type: String, p_angle: float, p_target_pos: Vector2 = Vector2.ZERO, _p_target_id = null):
	if cooldowns.get(p_type, 0.0) > 0.0:
		return
	if _is_safe_zone():
		return
	last_combat_time = Time.get_ticks_msec()
	if NetworkManager:
		NetworkManager.send_event("playerHitByEnemy", { "damage": 0, "id": entity_id, "attackerType": "combat_ping" })
	
	var t_idx = selected_ammo.get(p_type, 0)
	var current_ammo = 0
	if ammo.has(p_type) and t_idx < ammo[p_type].size():
		current_ammo = ammo[p_type][t_idx]
	
	if current_ammo <= 0: return
		
	ammo[p_type][t_idx] -= 1
	# v900.0: sonido de munición (ammo sound + fallback)
	if AudioManager and AudioManager.has_method("play_sfx_path"):
		var ammo_sfx_path = ""
		var ammo_vol = 0.0
		var ammo_maxd = 1000.0
		if GameConstants.SHOP_ITEMS and GameConstants.SHOP_ITEMS.has("ammo"):
			var ammo_cfg = GameConstants.SHOP_ITEMS["ammo"].get(p_type, [])
			if t_idx < ammo_cfg.size():
				ammo_sfx_path = String(ammo_cfg[t_idx].get("sound", ""))
				var ammo_pct = float(ammo_cfg[t_idx].get("soundVolumePercent", ammo_cfg[t_idx].get("soundVolume", 100.0)))
				ammo_vol = linear_to_db(clamp(ammo_pct / 100.0, 0.0001, 1.0))
				ammo_maxd = float(ammo_cfg[t_idx].get("soundMaxDist", 1000.0))
		if not ammo_sfx_path.is_empty():
			AudioManager.play_sfx_path(ammo_sfx_path, global_position, ammo_vol, ammo_maxd)
		# Si no hay sonido configurado (AdminDash -> sound vacío) silencio intencional, sin fallback ni warning
	
	is_moving = false
	autopilot_enabled = false
	target_position = global_position
	rotation = p_angle 

	var ammo_mult = 1.0
	var mult_list = GameConstants.AMMO_MULTIPLIERS.get(p_type, [1.0])
	if t_idx < mult_list.size(): ammo_mult = mult_list[t_idx]
	
	var r_val = 600.0
	var ammo_list = GameConstants.SHOP_ITEMS.ammo.get(p_type, [])
	var item_data = {}
	if t_idx < ammo_list.size():
		r_val = ammo_list[t_idx].get("range", 600.0)
		item_data = ammo_list[t_idx]
	
	# v400.70: Obtener el cooldown del Admin Dash (en ms) con fallback a 1.0s
	var cd_ms = item_data.get("cooldown", 1000.0)
	cooldowns[p_type] = float(cd_ms) / 1000.0
	
	# v260.95: Lógica de Minas y Bombas Electron de Precisión (Despliegue en cursor si está en rango)
	if (p_type == "mine" or p_type == "electron") and p_target_pos != Vector2.ZERO:
		var dist = global_position.distance_to(p_target_pos)
		r_val = min(r_val, dist)

	var final_damage = base_laser_damage * ammo_mult
	var final_payload = {
		"id": entity_id, "x": global_position.x, "y": global_position.y,
		"angle": p_angle, "rotation": rotation, "type": p_type, "ammoType": t_idx, 
		"senderId": entity_id, "damageBoost": final_damage, "range": r_val
	}
	
	# Copiar propiedades adicionales del tier (ej. explosionRadius) al payload
	for key in item_data:
		if not final_payload.has(key):
			final_payload[key] = item_data[key]
			
	shoot_fired.emit(final_payload)
	NetworkManager.send_event("playerFire", final_payload)
	# apply_shake(1.2) # v260: Shake muy leve al disparar (removido por pedido del usuario)
	_force_move_sync()

func _use_sphere_skill(id: int, p_data: Dictionary):
	if is_casting:
		_buffered_cast_action = {
			"action_type": "skill",
			"sphere_id": id,
			"payload": p_data.duplicate(true)
		}
		_buffered_cast_time = Time.get_ticks_msec()
		print("[BUFFER] Habilidad encolada en el buffer: sphere_", id)
		return
	var key = "sphere_" + str(id)
	if cooldowns[key] > 0: return
	# CASTEO HABILIDAD
	var skill_for_cast = null
	var sm_for_cast = get_node_or_null("SpheresManager")
	if is_instance_valid(sm_for_cast):
		skill_for_cast = sm_for_cast.get_equipped_skill(id)
	if skill_for_cast:
		var s_name_cast = skill_for_cast.skill_name if "skill_name" in skill_for_cast else str(skill_for_cast.get("skill_name",""))
		var cast_ms_skill = _get_skill_cast_ms(s_name_cast)
		if cast_ms_skill > 0:
			var payload_s = {"skillName": s_name_cast, "sphereIdx": id, "angle": p_data.get("angle", rotation), "pos": p_data.get("pos", global_position), "target": p_data.get("target", null), "targetId": null}
			if is_instance_valid(p_data.get("target")):
				var tg = p_data.get("target")
				if "entity_id" in tg: payload_s["targetId"] = tg.entity_id
				elif tg.has_method("get_id"): payload_s["targetId"] = tg.get_id()
			if _start_cast(cast_ms_skill, "skill", p_data.get("angle", rotation), payload_s):
				return
	_do_sphere_skill_immediate(id, p_data)

func _do_sphere_skill_immediate(id: int, p_data: Dictionary):
	var key = "sphere_" + str(id)
	if cooldowns[key] > 0: return
	var sm = get_node_or_null("SpheresManager")
	if not is_instance_valid(sm): return

	# Zona segura (Lobby): defensa en profundidad, nunca usar habilidades
	if _is_safe_zone():
		return
	
	var skill = sm.get_equipped_skill(id)
	if not skill: return
	
	if skill.skill_name == "BLINK" and p_data.has("pos"):
		set_meta("_last_blink_target", p_data.pos)
	
	# v5.1: Objetivo explícito (Fix Auto-Self en modo PC)
	var final_target = p_data.get("target")
	
	var target_id = null
	if is_instance_valid(final_target):
		if "entity_id" in final_target: target_id = final_target.entity_id
		elif final_target.has_method("get_id"): target_id = final_target.get_id()
		else: target_id = str(final_target.name)
		
	var is_targeted = false
	var skill_range = 0.0
	var s_data = {}
	
	if GameConstants.SKILLS_DATA.has(skill.skill_name):
		s_data = GameConstants.SKILLS_DATA[skill.skill_name]
		is_targeted = s_data.get("canTargetOthers", false)
		skill_range = s_data.get("range", 0.0)
		
	if is_targeted and target_id == null:
		# v301.7: Bloquear lanzamiento al vacío para habilidades dirigidas (Cura, Escudo, etc)
		# s_data.get("range") > 0 suele indicar que no es instantánea sobre el player
		if s_data.get("range", 0) > 0 or s_data.get("canTargetOthers", false):
			# print("[SKILL] Cancelado: Se requiere un objetivo válido.")
			return
		
	# v4.8: Validación de rango en cliente
	if is_targeted and target_id != entity_id and skill_range > 0:
		var target_node = final_target
		if is_instance_valid(target_node):
			var dist = global_position.distance_to(target_node.global_position)
			if dist > skill_range + 5.0:
				if has_method("_spawn_damage_text"):
					_spawn_damage_text("¡Objetivo fuera de rango!", Color.RED)
				print("[SKILL] Cancelado: Objetivo fuera de rango.")
				return
		
	# v4.2: Evitar autodaño/autocura si el objetivo es otro
	var is_self = (target_id == null or target_id == entity_id)

	# BLOQUEO PREVENTIVO LOCAL: VÍNCULO VITAL no permite auto-casteo
	if skill.skill_name == "VÍNCULO VITAL" and is_self:
		if has_method("_spawn_damage_text"):
			_spawn_damage_text("¡No puedes enlazarte a ti mismo!", Color.RED)
		print("[SKILL] Cancelado localmente: Vínculo Vital no permite auto-casteo.")
		return
	
	if is_self and skill.skill_name != "REGENERACIÓN ALFA":
		# Auto-lanzamiento: Activar efectos locales inmediatos
		if not sm.use_skill(id): return
	else:
		# Lanzamiento a otros o habilidades de area física: NO activar localmente
		pass
		
	# Enviar al servidor para que procese y broadcastee a todos
	NetworkManager.send_event("playerSphereSkill", {
		"id": id, "skillName": skill.skill_name, "powerValue": skill.power_value,
		"targetId": target_id, "posX": p_data.pos.x, "posY": p_data.pos.y,
		"angle": p_data.get("angle", rotation)
	})
	# v900.0: sonido de habilidad local (2D con maxDist)
	if AudioManager and AudioManager.has_method("play_skill_sound"):
		AudioManager.play_skill_sound(skill.skill_name, global_position)
	
	# Cooldown persistente basado en la configuración en milisegundos (ms)
	var cd_val = 5.0
	if GameConstants.SKILLS_DATA.has(skill.skill_name):
		var cd_ms = GameConstants.SKILLS_DATA[skill.skill_name].get("cd", 5000.0)
		cd_val = float(cd_ms) / 1000.0
	elif "cooldown" in skill:
		cd_val = skill.cooldown
	cooldowns[key] = cd_val

func set_joystick_direction(dir: Vector2):
	if is_casting and dir != Vector2.ZERO:
		_cancel_cast("manual")
		return
	joystick_direction = dir
	if dir != Vector2.ZERO:
		is_moving = false
		autopilot_enabled = false

func _apply_movement():
	if is_casting:
		velocity = Vector2.ZERO
		return
	var slow_val = (speed * (slow_points / 100.0)) if slow_is_percentage else slow_points
	var final_speed = max(10.0, speed - slow_val - _freeze_slow_val) # v268.40

	if is_feared:
		rotation = lerp_angle(rotation, fear_vector.angle(), 0.25)
		velocity = fear_vector * final_speed
	elif joystick_direction != Vector2.ZERO:
		var target_angle = joystick_direction.angle()
		var map_node = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map_node) and map_node.get("free_cam_active") == true:
			var cam_h_val = map_node.get("free_cam_h")
			target_angle += deg_to_rad(180.0 - (180.0 if cam_h_val == null else float(cam_h_val)))
		rotation = lerp_angle(rotation, target_angle, 0.25)
		var dir = Vector2.RIGHT.rotated(rotation)
		velocity = dir * final_speed
	elif is_moving:
		var dist = global_position.distance_to(target_position)
		var threshold = 15.0
		if get_node_or_null("/root/SettingsManager"):
			threshold = 15.0 / max(0.1, SettingsManager.click_sensitivity)
			
		if dist > threshold:
			var target_angle = (target_position - global_position).angle()
			rotation = lerp_angle(rotation, target_angle, 0.25)
			var dir = Vector2.RIGHT.rotated(rotation)
			velocity = dir * final_speed
		else:
			is_moving = false
			autopilot_enabled = false
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO

	# Feedback Visual
	if is_polymorphed:
		modulate = Color(0.7, 0.95, 1.0, 1.0)
	elif velocity != Vector2.ZERO or slow_points > 1.0:
		var target_color = Color.WHITE
		if slow_points > 1.0:
			target_color = Color(0.4, 0.7, 1.0, 1.0)
		target_color.a = modulate.a 
		modulate = modulate.lerp(target_color, 0.1)
	elif not _is_currently_invisible and not _is_currently_camouflaged:
		modulate = modulate.lerp(Color.WHITE, 0.1)

	if velocity != Vector2.ZERO:
		if move_and_slide():
			for i in get_slide_collision_count():
				var col = get_slide_collision(i)
				var obj = col.get_collider()
				if obj and (obj.is_in_group("enemies") or obj.is_in_group("remote_players")):
					global_position += col.get_normal() * 2.0
					velocity = velocity.bounce(col.get_normal()) * 0.5

		# v531.0: Nebulosa FANTASMA — clamp DESACTIVADO. Solo visual para referencia de pixeles del AdminDash.
		# El jugador puede atravesar libremente la nebulosa sin choque. Si quieres reactivar el choque duro, descomenta:
		# var w_size = GameConstants.GAME_CONFIG.get("worldSize", 4000)
		# var h_size = w_size
		# var p_node = get_parent()
		# if is_instance_valid(p_node) and "current_map_node" in p_node and is_instance_valid(p_node.current_map_node):
		# 	var mn = p_node.current_map_node
		# 	w_size = mn.world_size
		# 	if "map_height" in mn and mn.map_height > 0.0:
		# 		h_size = mn.map_height
		# global_position.x = clamp(global_position.x, 10, w_size - 10)
		# global_position.y = clamp(global_position.y, 10, h_size - 10)
		pass

func set_autopilot(p_dest: Vector2):
	if get_meta("spawn_locked", false):
		return # Bloquear piloto automático si la barrera de spawn está activa
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
	_recalculate_stats()
	current_hp = max_hp
	current_shield = max_shield
	if current_zone == 1:
		global_position = Vector2(1000, 1000)
	else:
		global_position = Vector2(randf_range(1500, 2500), randf_range(1500, 2500))
	target_position = global_position
	visible = true; modulate.a = 1.0; show()
	set_physics_process(true); set_process(true)

	# v421.1: Reactivar formas de colisión 2D al revivir
	for child in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", false)

	_update_tags()
	NetworkManager.send_event("playerRespawn", {
		"id": entity_id, "hp": max_hp, "sh": max_shield,
		"x": global_position.x, "y": global_position.y, "zone": current_zone
	})

func _on_connection_lost_player():
	entity_id = ""
	is_dead = false
	velocity = Vector2.ZERO

func _on_login_success(p_in):
	_is_initializing = true # v269.170: Silenciar save_progress redundante
	self.entity_id = str(p_in.get("socketId", ""))
	self.db_id = str(p_in.get("id", ""))
	self.username = p_in.get("username", p_in.get("user", "Piloto"))
	self.clan_tag = str(p_in.get("clanTag", "")) # v244.110
	
	# Cargar slots específicos del usuario ahora que sabemos su nombre
	load_ammo_slots_local()
	
	# v263.030: Refrescar tags de todas las entidades al conocer nuestro propio clan
	if clan_tag != "":
		call_deferred("_refresh_all_entity_tags")
	
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
		# Sincronía de puntos para UI base
		skill_points = int(gd.get("skillPoints", 0))
		
		# v221.26: Cargar estado PvP persistente de la cuenta
		if gd.has("pvpEnabled"):
			self.pvp_status = !!gd["pvpEnabled"]

		# v210.191: FORZAR REDRAW VISUAL (Fix: Asset Inconsistency)
		_setup_ship_visuals() 
		print("[CLIENT] Nave configurada ID: ", current_ship_id, " para ", username)
		
		# v690.2: Al entrar, quitar municiones equipadas que ya no cumplan requisitos
		call_deferred("_validate_ammo_slot_requirements")
		
		var sm = get_node_or_null("SpheresManager")
		if sm and gd.has("spheres"):
			var raw_spheres = gd["spheres"].duplicate()
			# v246.2: Delegar la hidratación al SpheresManager para evitar desincronizaciones de clases
			for i in range(min(raw_spheres.size(), 4)):
				sm.equip_item(i, raw_spheres[i])
			
			if sm.has_method("_update_visuals"):
				sm._update_visuals()

		current_hp = float(gd.get("hp", max_hp)) 
		current_shield = float(gd.get("shield", max_shield))
		# v_fix_dead: Guardia de seguridad — si venimos con hp=0 de la DB (legacy o bug), restaurar al loguear
		if current_hp <= 0:
			current_hp = max_hp
			current_shield = max_shield
			print("[PLAYER] AVISO: HP restaurado al loguear (estaba en 0 en DB)")
		_recalculate_stats()
		
		# v221.35: Sincronía inicial con el HUD
		if is_instance_valid(get_parent()) and get_parent().has_node("HUD/MainHUD"):
			get_parent().get_node("HUD/MainHUD").set_pvp_status(pvp_status)
		
		update_stats({"pvpEnabled": pvp_status, "isInvulnerable": p_in.get("isInvulnerable", false)})
	_update_tags(); _emit_stats(); queue_redraw()
	_is_initializing = false # v269.170: Restaurar guardado normal

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
	# v410: La velocidad del jugador local la calcula _recalculate_stats(), no el servidor
	if data.has("speed") and not is_in_group("player"):
		speed = float(data.speed)
	if data.has("electronSpeedBuff"):
		var eb = data.electronSpeedBuff
		electron_speed_buff_timer = float(eb.get("duration", 3000.0)) / 1000.0
		electron_speed_buff_pct = float(eb.get("pct", 15.0))
		electron_speed_buff_stacks = int(eb.get("stacks", 1))
		set_debuff_timer("electron_speed", electron_speed_buff_timer, electron_speed_buff_stacks)
		_recalculate_stats()
	
	# v410: Polimorfia - Recibir flags de movimiento/habilidades del servidor
	var poly_active = false
	if data.has("isPolymorphed"):
		poly_active = bool(data.isPolymorphed)
	elif data.has("polymorphed"):
		poly_active = bool(data.polymorphed)
		
	if data.has("isPolymorphed") or data.has("polymorphed"):
		is_polymorphed = poly_active
		_poly_authoritative = poly_active  # v410.3: Sincronizar flag autoritativo base
		status_effects["polymorphed"] = poly_active
		
		if not poly_active:
			poly_timer = 0.0
			poly_can_move = true
			poly_can_use_skills = true
			modulate = Color.WHITE
			_force_clear_poly_visual()  # Limpiar inmediatamente
		else:
			# Saneamiento de tipo de datos (soportar bool nativo y string de red)
			if data.has("polyCanMove"): 
				poly_can_move = str(data.polyCanMove) == "true" or data.polyCanMove == true
			if data.has("polyCanUseSkills"): 
				poly_can_use_skills = str(data.polyCanUseSkills) == "true" or data.polyCanUseSkills == true
			
			if data.has("polyDuration"):
				poly_timer = float(data.polyDuration) / 1000.0
			elif data.has("polyEndTime"):
				var now_unix_ms = Time.get_unix_time_from_system() * 1000.0
				poly_timer = max(0.0, (float(data.polyEndTime) - now_unix_ms) / 1000.0)
			elif poly_timer <= 0.0:
				poly_timer = 0.0  # v410.2: No reiniciar timer a 4.0; esperar a statusEffectsSync
	
	# v311.0: Conservar el target_position de click si el jugador se está moviendo y llega una actualización de posición del server.
	var old_target_pos = target_position
	
	# Guardar valores de HP y escudo antes de la actualización del servidor
	var old_hp = current_hp
	var old_shield = current_shield
	
	super.update_stats(data)
	
	# Calcular daño real recibido tras la sincronización del servidor
	var dmg_hp = old_hp - current_hp
	var dmg_sh = old_shield - current_shield
	var total_dmg = dmg_hp + dmg_sh
	
	# v380.0: Si el jugador recibe daño real de red, hacer temblar la cámara
	if total_dmg > 1.0:
		apply_shake(total_dmg * 0.15)
	
	if data.has("x") and data.has("y"):
		# Forzar el posicionamiento directo para que el rubber-banding del server sea efectivo.
		global_position = Vector2(float(data.x), float(data.y))
		if is_moving:
			target_position = old_target_pos
		else:
			target_position = global_position
			
	_emit_stats()

func save_progress():
	# v269.170: Seguridad absoluta - No guardar si estamos cargando o el socket no está listo
	if _is_initializing or not NetworkManager or not NetworkManager.network_connected: return
	
	NetworkManager.send_event("saveProgress", {
		"hubs": hubs, "ohcu": ohculianos, "exp": current_exp,
		"level": level,
		# v300.82: ELIMINADO skillTree de aquí. El servidor es la única autoridad.
		"hp": current_hp, "shield": current_shield,
		"maxHp": max_hp, "maxShield": max_shield,
		"ownedShips": owned_ships, "currentShipId": current_ship_id,
		"lastPos": {"x": global_position.x, "y": global_position.y}
	})

func _find_skill_by_name(n: String):
	if n == "": return null
	var target_n = n.to_upper().strip_edges()
	
	var skill_paths = {
		"TURBO-IMPULSO": "res://scripts/resources/skills/Skill_TurboImpulse.gd",
		"ESCUDO CELULAR": "res://scripts/resources/skills/Skill_ShieldCell.gd",
		"AUTO-REPARACIÓN": "res://scripts/resources/skills/Skill_RepairKit.gd",
		"REFLECT-OMEGA": "res://scripts/resources/skills/Skill_Reflect.gd",
		"NANO-REGENERACIÓN": "res://scripts/resources/skills/Skill_RegenPath.gd",
		"HYPER-DASH": "res://scripts/resources/skills/Skill_HyperDash.gd",
		"INVULNERABILIDAD": "res://scripts/resources/skills/Skill_Invulnerability.gd",
		"BLINK": "res://scripts/resources/skills/Skill_Blink.gd",
		"SMOKE-BOMB": "res://scripts/resources/skills/Skill_SmokeBomb.gd",
		"STEALTH": "res://scripts/resources/skills/Skill_Stealth.gd",
		"REGENERACIÓN ALFA": "res://scripts/resources/skills/Skill_AlphaRegen.gd",
		"BARRERA DE VIENTO": "res://scripts/resources/skills/Skill_WindBarrier.gd",
		"VÍNCULO VITAL": "res://scripts/resources/skills/Skill_VitalLink.gd",
		"BALIZA DE CURACION": "res://scripts/resources/skills/Skill_HealBeacon.gd",
		"PROVOCACION": "res://scripts/resources/skills/Skill_Provocacion.gd",
		"RESURRECCIÓN": "res://scripts/resources/skills/Skill_Resurreccion.gd",
		"ESFERA DE TERROR": "res://scripts/resources/skills/Skill_FearSphere.gd"
	}
	
	if skill_paths.has(target_n):
		var script = load(skill_paths[target_n])
		if script:
			return script.new()
	return null


func apply_shake(amount: float):
	if get_node_or_null("/root/SettingsManager"):
		if not SettingsManager.camera_shake_enabled: return
		amount *= SettingsManager.camera_shake_intensity
		
	_shake_amount += amount
	_shake_amount = min(_shake_amount, 100.0)

func _update_shake(_delta):
	if _shake_amount > 0.1:
		if is_instance_valid(_cam_node):
			_cam_node.offset = Vector2(randf_range(-_shake_amount, _shake_amount), randf_range(-_shake_amount, _shake_amount))
		_shake_amount *= _shake_decay
	else:
		if is_instance_valid(_cam_node):
			_cam_node.offset = Vector2.ZERO
		_shake_amount = 0.0

# v263.030: Refrescar etiquetas de clan en todas las entidades remotas
func _refresh_all_entity_tags():
	for entity in get_tree().get_nodes_in_group("remote_players"):
		if is_instance_valid(entity) and entity.has_method("_update_tags"):
			entity._update_tags()
