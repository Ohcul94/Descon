extends CharacterBody2D
class_name Entity

# precargas estáticas de optimización de rendimiento (v313.0)
const SpheresManagerScript = preload("res://scripts/systems/SpheresManager.gd")
const EntityHUDScript = preload("res://scripts/entities/EntityHUD.gd")
const DamageTextScript = preload("res://scripts/ui/DamageText.gd")
const EnergyShieldShader = preload("res://resources/shaders/energy_shield.gdshader")
const HitFlashShader = preload("res://resources/shaders/hit_flash.gdshader")
const SpaceExplosionScript = preload("res://scripts/vfx/SpaceExplosion.gd")
const WreckageDrawingScript = preload("res://scripts/ui/WreckageDrawing.gd")

# Caché estática de recursos para propulsión 3D optimizada
static var _prop_proc_material: ParticleProcessMaterial = null
static var _prop_material: StandardMaterial3D = null
static var _prop_mesh: QuadMesh = null

# Entity.gd (v150.20 - Non-Triangular Xeno Engine)
# Eliminación Absoluta de Triángulos en Enemigos. Siluetas Geométricas Puras.

var entity_id: String = ""
var _3d_propulsion: GPUParticles3D = null
var db_id: String = "" # v243.80: Identidad persistente (MongoDB ID)
var username: String = "Unknown"
var entity_type: int = 1
var clan_tag: String = "" # v244.110: Siglas de Flota

var max_hp: float = 3000; var is_rage: bool = false # v238.70: Modo Furia (ex-Ryze)

var current_hp: float = 3000
var max_shield: float = 1000; var current_shield: float = 1000
var _display_hp: float = 3000 # v190.85: Interpolación visual de vida
var _display_shield: float = 1000 # v190.85: Interpolación visual de escudo
var status_effects: Dictionary = {} # v268.68: Almacén de estados (Stun, Frozen, etc.)
var hp_regen: float = 5.0; var sh_regen: float = 15.0
var current_ship_id: int = 1
var target_position: Vector2 = Vector2.ZERO
var target_rotation: float = 0.0

var is_dead: bool = false
var is_god: bool = false
var last_combat_time: float = 0

@onready var name_tag = get_node_or_null("NameTag")
var _ui_wrapper: Node2D = null
var sprite: Sprite2D = null
var anim_player: AnimationPlayer = null

# v219.95: SISTEMA DE FÍSICAS 3D DINÁMICAS
var _3d_model: Node3D = null
var world_root_3d: Node3D = null
var accessory_pivot_3d: Node3D = null
var _3d_spheres: Array = [null, null, null, null]
var _spheres_angle: float = 0.0
var _last_rot2d: float = 0.0
var _bank_target: float = 0.0
var _bank_current: float = 0.0
var _ship_rot_mem: Dictionary = {}
var pvp_status: bool = false
var reflect_timer: float = 0.0
var shield_visual_timer: float = 0.0
var heal_visual_timer: float = 0.0
var invulnerable_timer: float = 0.0
var is_invulnerable: bool = false # v2.7: Sincronía autoritativa
var is_hovered: bool = false # v302.1: Feedback de apuntado
var _reflect_aura: Sprite2D = null
var _3d_shield_mesh: MeshInstance3D = null
var _collision_shape: CollisionShape2D = null
var _hit_flash_material: ShaderMaterial = null
var _hit_flash_material_3d: StandardMaterial3D = null
var _hover_outline_material: StandardMaterial3D = null # v302.5: Outline estilo LoL
var _stealth_material: StandardMaterial3D = null
var _status_material: StandardMaterial3D = null
var _vfx_container_2d: Node2D = null
var _is_currently_invisible: bool = false
var _is_currently_camouflaged: bool = false
var _is_ally: bool = false
var _cached_viewport: SubViewport = null # Cache para frustum culling

# Cache para optimización de rendimiento
var _cached_map: Node = null
var _cached_camera_3d: Camera3D = null
var _cached_sub_viewport: SubViewport = null
var _cached_camera_2d: Camera2D = null
var _cached_player: Node = null
var _cached_spheres_manager: Node = null

# Estado para evitar recálculo redundante de tags UI
var _last_rendered_hp: float = -1.0
var _last_rendered_shield: float = -1.0
var _last_rendered_max_hp: float = -1.0
var _last_rendered_max_shield: float = -1.0
var _last_rendered_username: String = ""
var _last_rendered_clan_tag: String = ""
var _last_rendered_is_rage: bool = false
var _last_rendered_pvp_status: bool = false

func _get_map_node() -> Node:
	if not is_instance_valid(_cached_map):
		_cached_map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(_cached_map):
			_cached_camera_3d = _cached_map.get("camera_3d")
			_cached_sub_viewport = _cached_map.get("sub_viewport")
	return _cached_map

func _get_camera_2d() -> Camera2D:
	if not is_instance_valid(_cached_camera_2d):
		_cached_camera_2d = get_viewport().get_camera_2d()
	return _cached_camera_2d

func _get_player_node() -> Node:
	if not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group("player")
	return _cached_player

func _get_spheres_manager() -> Node:
	if not is_instance_valid(_cached_spheres_manager):
		_cached_spheres_manager = get_node_or_null("SpheresManager")
	return _cached_spheres_manager

func _ready():
	add_to_group("entities")
	_vfx_container_2d = Node2D.new()
	_vfx_container_2d.name = "VFXContainer2D"
	add_child(_vfx_container_2d)
	motion_mode = MOTION_MODE_FLOATING 
	safe_margin = 0.5 # v235.99: Margen de seguridad aumentado para evitar 'pegamento'


	
	# v235.56: Inicialización Universal de Esferas
	var sm_script = SpheresManagerScript
	if sm_script:
		var sm = sm_script.new()
		sm.name = "SpheresManager"
		add_child(sm)
		sm.spheres_updated.connect(_update_3d_spheres)

	z_index = 1 # v166.60: Por encima de las estrellas
	visible = true; show()
	target_position = global_position
	target_rotation = rotation
	
	_collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 25.0 
	_collision_shape.shape = circle
	add_child(_collision_shape)
	
	# print("[BATTLE] Colisión normalizada: ", name)

	var junk = ["HealthBar", "ShieldBar", "HP", "SH", "Health", "Shield"]
	for j in junk:
		var n = get_node_or_null(j)
		if n: n.visible = false; n.queue_free()
	
	if not _ui_wrapper:
		# v300.30: El HUD ahora es un componente independiente (EntityHUD.gd)
		var hud_script = EntityHUDScript
		if hud_script:
			_ui_wrapper = hud_script.new()
			_ui_wrapper.setup(self)
			_ui_wrapper.top_level = false
			_ui_wrapper.name = "HUD_Layer_Final"
			add_child(_ui_wrapper)
	
	# v190.90: SISTEMA DE RECORTE Y ANIMACIÓN NAVE-1 (Phoenix)
	# Si somos una nave (no enemigo), configuramos el sprite.
	if !is_in_group("enemies"):
		_setup_ship_visuals()
	else:
		_setup_enemy_visuals()
	
	if name_tag:
		if name_tag.get_parent() != _ui_wrapper: name_tag.reparent(_ui_wrapper)
		name_tag.visible = true; name_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		name_tag.grow_horizontal = Control.GROW_DIRECTION_BOTH; name_tag.grow_vertical = Control.GROW_DIRECTION_BOTH
		name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	_update_tags()
	
	# v235.36: Sincronía Visual de Habilidades
	if NetworkManager.has_signal("remote_skill_used"):
		NetworkManager.remote_skill_used.connect(_on_remote_skill_used)
	
	# v266.985: Suscripción a acciones especiales de enemigos
	if NetworkManager.has_signal("enemy_action"):
		NetworkManager.enemy_action.connect(_on_enemy_action)
	
	# v268.800: Sincronía visual de AURAS
	if NetworkManager.has_signal("enemy_aura"):
		NetworkManager.enemy_aura.connect(_on_enemy_aura)

var active_auras: Dictionary = {} # v268.800: { mId: Sprite2D }


var last_draw_hp: float = -1.0
var last_draw_sh: float = -1.0
var sync_lock_timer: float = 0.0
var is_teleporting: bool = false # v3.1: Bloquear interpolación en saltos instantáneos

func activate_sync_lock(duration: float = 2.5):
	sync_lock_timer = duration
	print("[NET] Bloqueo de Sincronía activado por ", duration, "s")

# v3.2: Teletransporte Autoritativo Instantáneo (Anti-Lerp)
func teleport_to(new_pos: Vector2):
	is_teleporting = true
	# 1. Ocultar ANTES de mover para que no se vea ningún frame de tránsito
	modulate.a = 0.0
	if is_instance_valid(_3d_model): _3d_model.visible = false
	if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = false
	# 2. Teletransporte instantáneo (ambos valores)
	global_position = new_pos
	target_position = new_pos
	# 3. Re-aparecer después de 2 frames (tiempo suficiente para que el render procese)
	get_tree().create_timer(0.05).timeout.connect(func():
		if not is_instance_valid(self): return
		modulate.a = 1.0
		if is_instance_valid(_3d_model): _3d_model.visible = true
		if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = true
		get_tree().create_timer(0.45).timeout.connect(func(): 
			if is_instance_valid(self): is_teleporting = false
		)
	)

func _process(delta):
	if reflect_timer > 0:
		reflect_timer -= delta
	
	if sync_lock_timer > 0:
		sync_lock_timer -= delta
	
	# v311.2: Calcular visibilidad en pantalla antes de procesar visuales costosos
	var screen_visible = true
	if not is_in_group("player"): # El jugador local siempre se considera visible
		var local_player = _get_player_node()
		if is_instance_valid(local_player):
			var vision_r = 1300.0
			if "vision_range" in local_player:
				vision_r = local_player.vision_range
			else:
				# Fallback
				if "current_ship_id" in local_player and GameConstants.SHIP_MODELS:
					for ship in GameConstants.SHIP_MODELS:
						if ship.id == local_player.current_ship_id:
							vision_r = float(ship.get("vision", 1300.0))
							break
			var dist = target_position.distance_to(local_player.global_position)
			if dist > vision_r:
				screen_visible = false
		
		if screen_visible:
			var cam = _get_camera_2d()
			if cam:
				var screen_size = get_viewport_rect().size
				var cam_pos = cam.global_position
				var margin = 600.0
				var diff = target_position - cam_pos # v311.4: Usar target_position para evitar desincronización por cortocircuito
				if abs(diff.x) > (screen_size.x / 2.0 + margin) or abs(diff.y) > (screen_size.y / 2.0 + margin):
					screen_visible = false

	# v311.3: Culling masivo de procesamiento para naves lejanas fuera de pantalla
	if not is_in_group("player"):
		if not screen_visible:
			# Actualizar posición física 2D de inmediato (evita que queden clavadas en 0,0) (v311.6)
			global_position = target_position
			rotation = target_rotation
			
			if get_meta("_was_screen_visible", true) == true:
				set_meta("_was_screen_visible", false)
				if is_instance_valid(world_root_3d):
					world_root_3d.visible = false
				if is_instance_valid(_ui_wrapper):
					_ui_wrapper.visible = false
				if is_instance_valid(_vfx_container_2d):
					_vfx_container_2d.visible = false
				if is_instance_valid(sprite):
					sprite.visible = false
				if is_instance_valid(_3d_propulsion):
					_3d_propulsion.emitting = false
			return # CORTOCIRCUITO COMPLETO: Salva 100% de cálculos en cada frame
		else:
			if get_meta("_was_screen_visible", true) == false:
				set_meta("_was_screen_visible", true)
				# Posicionar inmediatamente para evitar teleportación tardía visual
				global_position = target_position
				rotation = target_rotation
			
			# v311.5: Forzar visibilidad correcta al estar en pantalla
			if is_instance_valid(world_root_3d):
				if (_is_currently_invisible or _is_currently_camouflaged) and not _is_ally:
					world_root_3d.visible = _is_currently_camouflaged
				else:
					world_root_3d.visible = not is_dead
			if is_instance_valid(_ui_wrapper):
				if (_is_currently_invisible or _is_currently_camouflaged) and not _is_ally:
					_ui_wrapper.visible = false
				else:
					_ui_wrapper.visible = visible and not is_dead
			if is_instance_valid(_vfx_container_2d):
				if (_is_currently_invisible or _is_currently_camouflaged) and not _is_ally:
					_vfx_container_2d.visible = _is_currently_camouflaged
				else:
					_vfx_container_2d.visible = true

	# v310.1: SINCRONIZACIÓN ATÓMICA TOTAL (Elimina efecto acordeón y restaura HUD)
	# 1. Interpolación de posición de red
	if not is_in_group("player") and not is_teleporting:
		var weight = 1.0 - pow(0.01, delta) # v310.2: Suavizado balanceado
		global_position = global_position.lerp(target_position, weight)
		
		# Suavizado de rotación respetando bloqueos tácticos
		var can_rotate = true
		if get_meta("is_locked", false) or get_meta("is_firing", false):
			can_rotate = false
			
		if can_rotate:
			var rot_factor = 0.2
			if is_in_group("enemies"):
				rot_factor = 0.1 # Suavizado orgánico original de enemigos
			var rot_weight = 1.0 - pow(1.0 - rot_factor, delta * 60.0)
			rotation = lerp_angle(rotation, target_rotation, rot_weight)
		
	# 2. Sincronía de UI y VFX (Solo si está en pantalla)
	if screen_visible:
		# Primero actualizamos la posición 3D para tener el world_root_3d en su lugar correcto
		_update_3d_root_sync()
		
		var is_single = get_meta("is_single_world", false)
		var projected_pos_hud = global_position
		var projected_pos_vfx = Vector2.ZERO
		var has_projected = false
		
		if is_single and is_instance_valid(world_root_3d):
			var current_map = _get_map_node()
			if is_instance_valid(current_map) and is_instance_valid(_cached_camera_3d):
				var cam3d = _cached_camera_3d
				var sub_vp = _cached_sub_viewport
				if not cam3d.is_position_behind(world_root_3d.global_position):
					# unproject_position devuelve la posición en píxeles del SubViewport
					var sv_pixel = cam3d.unproject_position(world_root_3d.global_position)
					# Escalar de SubViewport a la pantalla principal si difieren en tamaño
					if is_instance_valid(sub_vp) and sub_vp.size.x > 0 and sub_vp.size.y > 0:
						var main_size = Vector2(get_viewport().get_visible_rect().size)
						sv_pixel *= main_size / Vector2(sub_vp.size)
					# Convertir de píxeles de pantalla a coordenadas del mundo 2D
					var world_2d = get_viewport().get_canvas_transform().affine_inverse() * sv_pixel
					projected_pos_hud = world_2d
					projected_pos_vfx = world_2d
					has_projected = true
		
		if is_instance_valid(_ui_wrapper):
			_ui_wrapper.visible = visible and not is_dead
			_ui_wrapper.global_position = projected_pos_hud
			if name_tag: _update_hud_offsets()
		
		# 3. Resto de efectos (ya se llamó _update_3d_root_sync arriba)
		_update_3d_shield(delta) # Aquí se procesa la invulnerabilidad
		_update_reflect_aura(delta)
		_update_hit_flash(delta)
		
		if is_instance_valid(_vfx_container_2d):
			if is_single and has_projected:
				_vfx_container_2d.global_position = projected_pos_vfx
			else:
				_vfx_container_2d.position = Vector2.ZERO
	else:
		# v311.2: Culling proactivo cuando está fuera de pantalla
		if is_instance_valid(world_root_3d):
			world_root_3d.visible = false
		if is_instance_valid(_ui_wrapper):
			_ui_wrapper.visible = false
		if is_instance_valid(_vfx_container_2d):
			_vfx_container_2d.visible = false

	# v268.70: Feedback visual de estados alterados (Soporte 2.5D)
	if not is_dead:
		var is_affected = status_effects.get("stunned", false) or status_effects.get("frozen", false)
		var state_color = Color(1.5, 1.5, 3.5, 1.0) if is_affected else Color(1, 1, 1, 1) # v268.76: Más azul y brillante
		
		if is_instance_valid(sprite):
			if _is_currently_invisible or _is_currently_camouflaged:
				var alpha_val = 0.5 if _is_ally else (0.3 if _is_currently_camouflaged else 0.0)
				sprite.modulate = Color(state_color.r, state_color.g, state_color.b, alpha_val)
			else:
				sprite.modulate = state_color
		
		# v268.77: Tinte para modelos 3D (Corregido para Viewports locales y compartidos)
		if is_instance_valid(_3d_model):
			if is_affected:
				if not _status_material:
					_status_material = StandardMaterial3D.new()
					_status_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_status_material.albedo_color = Color(0.1, 0.5, 1.0, 0.6) # v268.76: Tinte más opaco para que se note
				_apply_material_recursive(_3d_model, _status_material, false)
			elif _is_currently_invisible or _is_currently_camouflaged:
				# Restaurar o mantener el material de sigilo si estamos en sigilo o camuflaje
				if not _stealth_material:
					_stealth_material = StandardMaterial3D.new()
					_stealth_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
					_stealth_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					_stealth_material.albedo_color = Color(0.15, 0.65, 0.95, 0.28) # Holograma de sigilo translúcido cian/azul
				_apply_material_recursive(_3d_model, _stealth_material, false)
			else:
				# Restaurar material original si no hay ni sigilo ni estado alterado
				_apply_material_recursive(_3d_model, null, false)
	
	if is_dead:
		if _ui_wrapper: _ui_wrapper.visible = false
		if _reflect_aura: _reflect_aura.visible = false
		if is_instance_valid(world_root_3d): world_root_3d.visible = false
		visible = false; return

	visible = true; show()
	if _ui_wrapper: _ui_wrapper.visible = true

	# v219.65: Redibujado Inteligente (Interpolación v190.85)
	_display_hp = lerp(_display_hp, current_hp, 0.1)
	_display_shield = lerp(_display_shield, current_shield, 0.1)
	
	if abs(_display_hp - last_draw_hp) > 0.05 or abs(_display_shield - last_draw_sh) > 0.05:
		queue_redraw()
		if _ui_wrapper: _ui_wrapper.queue_redraw()
		last_draw_hp = _display_hp
		last_draw_sh = _display_shield
	
	_update_animations()
	_update_auras(delta)

	# OPTIMIZACIÓN MASIVA: Pausar/Intercalar SubViewport de entidades según visibilidad, rol y distancia
	if _cached_viewport:
		if screen_visible:
			if is_in_group("player") or entity_type >= 100: # Jugador local y Bosses actualizan en cada frame
				_cached_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			else:
				# LOD temporal adaptativo según distancia al jugador local para reducir updates transparentes
				var player = _get_player_node()
				var modulo = 2
				if is_instance_valid(player):
					var dist = global_position.distance_to(player.global_position)
					if dist > 600.0:
						modulo = 6 # ~10 FPS si está muy lejos
					elif dist > 300.0:
						modulo = 4 # ~15 FPS a distancia media
					else:
						modulo = 2 # ~30 FPS de cerca
						
				var frame = Engine.get_frames_drawn()
				if (frame + name.hash()) % modulo == 0:
					_cached_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				else:
					_cached_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		else:
			_cached_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	# v302.2: Actualización visual de Outline y reset para el siguiente frame
	_update_hover_visuals(is_hovered)
	is_hovered = false 

	# v219.98: FÍSICAS 3D DINÁMICAS (BANKING + BOBBING + ÓRBITA)
	if is_instance_valid(_3d_model) and screen_visible:
		# 1. BALANCEO (BOBBING)
		_3d_model.position.y = sin(Time.get_ticks_msec() * 0.002) * 0.12
		
		# 2. CÁLCULO DE INCLINACIÓN (BANKING)
		var rot_diff = angle_difference(_last_rot2d, rotation)
		_bank_target = clamp(rot_diff * 25.0, -0.7, 0.7)
		_bank_current = lerp(_bank_current, _bank_target, 0.1)
		
		# 3. ROTACIÓN DE LA NAVE (v254.60: Revertido a original por pedido del usuario)
		var target_yaw = -rotation
		_3d_model.rotation.y = lerp_angle(_3d_model.rotation.y, target_yaw, 0.2)
		_3d_model.rotation.x = abs(_bank_current) * 0.12
		_3d_model.rotation.z = -_bank_current * 0.4
		
		# Control de emisión de propulsión 3D basada en velocidad
		if is_instance_valid(_3d_propulsion):
			var is_moving = velocity.length() > 15.0 and not is_dead
			if _3d_propulsion.emitting != is_moving:
				_3d_propulsion.emitting = is_moving
		
		# 4. ACTUALIZAR ÓRBITA DE ESFERAS (Sincronización suave + Inventario)
		_spheres_angle += delta * 0.3 
		var is_auth = username == "Unknown" or username == ""
		
		# Buscamos el manager de esferas para saber qué está equipado
		var manager = _get_spheres_manager()
		
		for i in range(4):
			var s_node = _3d_spheres[i]
			if is_instance_valid(s_node):
				# Radio 2.3 local (Phoenix)
				var r = 2.3
				var s_angle = _spheres_angle + (i * TAU / 4.0)
				
				# POSICIONAMIENTO 3D DINÁMICO
				var target_x = cos(s_angle) * r
				var target_z = sin(s_angle) * r
				# Efecto "Subibaja" (Levitación independiente y desfasada)
				var bobbing = sin(Time.get_ticks_msec() * 0.002 + i * 2.0) * 0.4
				
				s_node.position = Vector3(target_x, bobbing, target_z)
				
				var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.005 + i) * 0.1
				s_node.scale = Vector3(0.6, 0.6, 0.6) * pulse
				
				# LÓGICA DE EQUIPAMIENTO:
				var is_equipped = true # Por defecto visible (enemigos/NPCs)
				if manager and "spheres_data" in manager:
					if i < manager.spheres_data.size():
						is_equipped = manager.spheres_data[i]["equipped"] != null
					else:
						is_equipped = false # Si no existe la configuración para esta esfera, no se muestra
				
				s_node.visible = visible and not is_auth and is_equipped
		
		# --- MODO INSPECCIÓN (Rotación manual con Numpad) ---
		# v220.71: Solo permitir rotación en jugador local y persistir en memoria RAM
		var actual_model = _3d_model.get_child(0) if _3d_model.get_child_count() > 0 else null
		if is_instance_valid(actual_model) and is_in_group("player"):
			# Si no hay memoria para esta nave, tomar el valor actual como punto de partida
			if not _ship_rot_mem.has(current_ship_id):
				_ship_rot_mem[current_ship_id] = actual_model.rotation_degrees
			
			var m_rot = _ship_rot_mem[current_ship_id]
			if Input.is_key_pressed(KEY_KP_1): m_rot.x += 1
			if Input.is_key_pressed(KEY_KP_2): m_rot.x -= 1
			if Input.is_key_pressed(KEY_KP_4): m_rot.y += 1
			if Input.is_key_pressed(KEY_KP_5): m_rot.y -= 1
			if Input.is_key_pressed(KEY_KP_7): m_rot.z += 1
			if Input.is_key_pressed(KEY_KP_8): m_rot.z -= 1
			
			_ship_rot_mem[current_ship_id] = m_rot
			actual_model.rotation_degrees = m_rot
			
		# v235.69: Rotación de accesorios (Esferas)
		if is_instance_valid(accessory_pivot_3d):
			accessory_pivot_3d.rotate_y(delta * 2.0)
		
		# Sincronización de visibilidad y anti-rotación del Sprite2D (Ocultar si es Lienzo Único)
		if is_instance_valid(sprite):
			sprite.rotation = -rotation
			sprite.visible = visible if not get_meta("is_single_world", false) else false
			
		_last_rot2d = rotation
	
	# v167.70: REGENERACIÓN POST-COMBATE (SÓLO PARA EL JUGADOR LOCAL)
	if is_in_group("player") and not is_dead:
		var now = Time.get_ticks_msec()
		if now - last_combat_time > 5000:
			var regen_hp = (max_hp * 0.01) * delta
			var regen_sh = (max_shield * 0.02) * delta
			if current_hp < max_hp: current_hp = min(max_hp, current_hp + regen_hp)
			if current_shield < max_shield: current_shield = min(max_shield, current_shield + regen_sh)
			_update_tags()
	
func _update_hud_offsets():
	if is_instance_valid(_ui_wrapper):
		_ui_wrapper.global_rotation = 0.0
	var y_offset = -145.0
	if is_in_group("player"): y_offset = -180.0
	elif entity_type >= 4: y_offset = -300.0
	name_tag.position.y = y_offset
	if name_tag.size.x > 0:
		name_tag.position.x = -(name_tag.size.x / 2.0)

func _draw():
	# v268.810: Dibujo de soporte para cúpulas de energía (Wall Dome)
	for mId in active_auras:
		var a_data = active_auras[mId]
		if a_data.get("type") == "wall_dome":
			var radius = a_data.get("radius", 300.0)
			var pulse_val = sin(Time.get_ticks_msec() * 0.006)
			var pulse_radius = radius + pulse_val * 4.0
			
			# 1. Relleno semitransparente del escudo
			draw_circle(Vector2.ZERO, radius, Color(0.0, 0.4, 0.9, 0.06))
			
			# 2. Pared de energía (anillo principal de neón celeste)
			draw_arc(Vector2.ZERO, radius, 0, TAU, 90, Color(0.0, 0.7, 1.0, 0.7), 5.0, true)
			
			# 3. Efecto de onda/brillo exterior
			draw_arc(Vector2.ZERO, pulse_radius, 0, TAU, 90, Color(0.0, 0.9, 1.0, 0.25), 1.5, true)
			
			# 4. Líneas radiales de energía/campo de fuerza
			for i in range(8):
				var angle = (i * PI / 4.0) + (Time.get_ticks_msec() * 0.0002)
				var dir = Vector2.from_angle(angle)
				draw_line(dir * (radius - 12.0), dir * radius, Color(0.0, 0.8, 1.0, 0.6), 2.5, true)

	# v166.61: RENDERIZADO TACTICO (Glow & Visibility Fix)
	# v190.91: Si hay sprite cargado, ya no dibujamos el polígono base
	if is_instance_valid(sprite): return

	var poly_color = Color(1, 0.4, 0)
	var pts = PackedVector2Array()
	
	if is_in_group("player") or is_in_group("remote_players"):
		poly_color = Color(0, 0.8, 1) # Cyan Neón
		pts = PackedVector2Array([Vector2(22, 0), Vector2(-15, -15), Vector2(-10, 0), Vector2(-15, 15)])
		
		# Efecto de brillo exterior
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 1, 1, 0.4), 4.0)
		draw_colored_polygon(pts, poly_color)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.5)
		return

	# ENEMIGOS: Siluetas Geométricas Distintas (No-Triángulos)
	match entity_type:
		1: # Enemigo 1
			poly_color = Color(1, 0.45, 0) 
			pts = PackedVector2Array([Vector2(12, 12), Vector2(-12, 12), Vector2(-12, -12), Vector2(12, -12)])
		6: # Enemigo 6 (Vértice)
			poly_color = Color(0, 0.5, 1)
			pts = PackedVector2Array([Vector2(20, 0), Vector2(14, -14), Vector2(0, -20), Vector2(-14, -14), Vector2(-20, 0), Vector2(-14, 14), Vector2(0, 20), Vector2(14, 14)])
		8: # Enemigo 8 (Charger)
			poly_color = Color(1, 0.8, 0)
			pts = PackedVector2Array([Vector2(15, -8), Vector2(15, 8), Vector2(0, 18), Vector2(-15, 8), Vector2(-15, -8), Vector2(0, -18)])
		4: # Lord Titán
			poly_color = Color(1, 0, 0.5)
			pts = PackedVector2Array([Vector2(25, -12), Vector2(25, 12), Vector2(12, 25), Vector2(-12, 25), Vector2(-25, 12), Vector2(-25, -12), Vector2(-12, -25), Vector2(12, -25)])
		10: # Ancient Boss
			poly_color = Color(1, 0, 0)
			pts = PackedVector2Array([Vector2(35, 0), Vector2(8, -8), Vector2(0, -35), Vector2(-8, -8), Vector2(-35, 0), Vector2(-8, 8), Vector2(0, 35), Vector2(8, 8)])
		11: # Mechanic Boss
			poly_color = Color(0.7, 0, 1)
			pts = PackedVector2Array([Vector2(60, 0), Vector2(20, -50), Vector2(-40, -40), Vector2(-60, 0), Vector2(-40, 40), Vector2(20, 50)])
		5: # Enemigo 5
			poly_color = Color(0.5, 1, 0)
			pts = PackedVector2Array([Vector2(18, 0), Vector2(0, -18), Vector2(-18, 0), Vector2(0, 18)])
		_: # Otros / Genéricos (Pentágono Cyan)
			poly_color = Color(0, 1, 1)
			pts = PackedVector2Array([Vector2(15, 0), Vector2(5, -15), Vector2(-15, -10), Vector2(-15, 10), Vector2(5, 15)])
	
	draw_colored_polygon(pts, poly_color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.8)

# v300.30: HUD delegado a EntityHUD.gd


	

func get_visual_position() -> Vector2:
	if get_meta("is_single_world", false) and is_instance_valid(world_root_3d):
		var current_map = _get_map_node()
		if is_instance_valid(current_map) and is_instance_valid(_cached_camera_3d):
			var cam3d: Camera3D = _cached_camera_3d
			var sub_vp: SubViewport = _cached_sub_viewport
			if not cam3d.is_position_behind(world_root_3d.global_position):
				var sv_pixel = cam3d.unproject_position(world_root_3d.global_position)
				if is_instance_valid(sub_vp) and sub_vp.size.x > 0 and sub_vp.size.y > 0:
					var main_size = Vector2(get_viewport().get_visible_rect().size)
					sv_pixel *= main_size / Vector2(sub_vp.size)
				return get_viewport().get_canvas_transform().affine_inverse() * sv_pixel
	return global_position

func _update_3d_root_sync():
	if is_instance_valid(world_root_3d) and get_meta("is_single_world", false):
		var pl = get_tree().get_first_node_in_group("player")
		if pl and pl.get("current_zone") == 100:
			world_root_3d.visible = false
			return
			
		var s_factor = get_meta("map_scale", 0.02)
		var correction_z = 1.41421356 # 1.0 / sin(45 grados) para compensar perspectiva ortogonal inclinada
		world_root_3d.position.x = global_position.x * s_factor
		world_root_3d.position.z = global_position.y * s_factor * correction_z
		world_root_3d.position.y = 0.0
		
		# v311.5: Sincronización directa y robusta de visibilidad (evita discrepancias por márgenes fijos)
		if is_dead:
			world_root_3d.visible = false
		elif is_teleporting:
			world_root_3d.visible = true
		elif _is_currently_invisible and not _is_ally:
			# Si somos invisibles y no somos aliados, ocultar completamente el canvas 3D
			world_root_3d.visible = false
		elif _is_currently_camouflaged and not _is_ally:
			world_root_3d.visible = true
		else:
			world_root_3d.visible = true

func reset_combat_timer():
	last_combat_time = Time.get_ticks_msec()

func update_stats(data):
	if data.has("id"): entity_id = str(data.id)
	var raw = data.get("username", data.get("user", data.get("name", null)))
	if raw != null and str(raw) != "" and str(raw) != "Unknown": 
		username = str(raw)
	
	if data.has("status_effects"):
		status_effects = data.status_effects
	
	# v268.87: Capturar posición desde el paquete de stats para evitar rubber-banding
	if data.has("x"): target_position.x = _safe_float(data.x, target_position.x)
	if data.has("y"): target_position.y = _safe_float(data.y, target_position.y)
	if data.has("rot"): target_rotation = _safe_float(data.rot, target_rotation)
	
	if data.has("clanTag"):
		clan_tag = str(data.clanTag)
	if data.has("clanId"):
		set("clanId", data.clanId) # v245.92: Mantener ID para filtros de Minimap

	
	if data.has("pvpEnabled") and name_tag:
		pvp_status = !!data.pvpEnabled

	
	# v164.94: Sincronía de Popups de Daño (Antes de pisar los valores)
	var old_total = current_hp + current_shield
	
	# v191.70: PREDICCIÓN DE CLIENTE ANTI-PARPADEO (Shield/HP Stability)
	# Si somos el jugador local, ignoramos cambios minúsculos del server (Regen vs Latencia)
	# Si somos el jugador local, ignoramos cambios minúsculos del server (Regen vs Latencia)
	var is_local = is_in_group("player")
	var threshold = max(25.0, max_hp * 0.02) # v240.69: Umbral dinámico para naves de alto HP
	var lock_active = (is_local and sync_lock_timer > 0)
	
	if data.has("isInvulnerable"):
		is_invulnerable = bool(data.isInvulnerable)
		# v269.182: Eliminado timer de 2s para sincronizar con la duración real del skill
	
	if data.has("hp") and not lock_active:
		var server_hp = _safe_float(data.get("hp"), current_hp)
		if not is_local or abs(current_hp - server_hp) > threshold:
			current_hp = server_hp
			
	if (data.has("shield") or data.has("sh")) and not lock_active:
		var server_sh = _safe_float(data.get("shield", data.get("sh")), current_shield)
		if not is_local or abs(current_shield - server_sh) > threshold:
			current_shield = server_sh
			
	if data.has("maxHp"): 
		max_hp = _safe_float(data.get("maxHp"), max_hp)
	if (data.has("maxShield") or data.has("maxSh")):
		max_shield = _safe_float(data.get("maxShield", data.get("maxSh")), max_shield)
	
	if data.has("currentShipId") and not is_in_group("enemies"):
		var sid = int(data.currentShipId)
		if sid != current_ship_id:
			current_ship_id = sid
			# v210.160: Limpieza RADICAL de equipo al cambiar de nave para evitar polución visual
			_clear_all_equipment_visuals()
			_setup_ship_visuals()
		
	# v210.131: Sincronía de Equipamiento Visual (Reflejar en el sprite/HUD)
	if data.has("equipped"):
		var new_eq = data.equipped
		if typeof(new_eq) == TYPE_DICTIONARY:
			# Si somos el jugador local, ya tenemos 'equipped' vinculado, solo recalculamos
			# Si somos remoto, actualizamos el diccionario local
			if !is_in_group("player"):
				if self.has_method("set"): self.set("equipped", new_eq)
			
			if self.has_method("_recalculate_stats"):
				self.call("_recalculate_stats")

	# v3.5: Sincronía de Invisibilidad (STEALTH)
	if data.has("isInvisible") or data.has("isCamouflaged"):
		var inv = bool(data.get("isInvisible", false))
		var camo = bool(data.get("isCamouflaged", false))
		_update_invisibility_visuals(inv, camo)

	if not is_local:
		if current_shield > max_shield: max_shield = current_shield
		if current_hp > max_hp: max_hp = current_hp
	
	# v186.16: Sincronía de Resurrección Crítica
	if data.has("isDead"):
		var dead_on_server = bool(data.isDead)
		if is_dead and not dead_on_server:
			_resurrect(data)
		elif not is_dead and dead_on_server:
			die()
	elif current_hp > 0 and is_dead:
		_resurrect(data)
	elif current_hp <= 0 and not is_dead:
		# v307.1: Si la vida llega a 0 en la sincronía pero no estamos marcados como muertos, forzar die()
		die()
	
	
	# v166.75: Capado de Seguridad (No exceder máximos sincronizados)
	current_hp = min(current_hp, max_hp)
	current_shield = min(current_shield, max_shield)
	
	var new_total = current_hp + current_shield
	var damage_taken = old_total - new_total
	
	# v240.69: Solo emitir daño visual en el sync si es un daño no predicho GRANDE (Evitar falsos sangrados por regen)
	if damage_taken >= max(10.0, max_hp * 0.05) and old_total > 0: 
		# No reseteamos el combat_timer aquí porque el ataque real ya lo reseteó en take_damage
		_spawn_damage_text(str(int(damage_taken)), Color.RED)
	
	if data.has("healPopup"):
		var h_val = int(data.healPopup)
		_spawn_damage_text("+" + str(h_val), Color.GREEN)
		
	if data.has("spheres"):
		var sm = get_node_or_null("SpheresManager")
		if is_instance_valid(sm):
			var sps = data.spheres
			if typeof(sps) == TYPE_ARRAY:
				for i in range(min(sps.size(), 4)):
					var s_data = sps[i]
					var new_skill = s_data.get("equipped") if s_data else null
					# Evitar spam de recarga si el slot no cambió
					var current = sm.spheres_data[i]["equipped"]
					var needs_update = false
					
					if new_skill == null and current != null: needs_update = true
					elif new_skill != null and current == null: needs_update = true
					elif new_skill != null and current != null:
						var n_name = new_skill.get("skill_name", "") if typeof(new_skill) == TYPE_DICTIONARY else new_skill.get("skill_name")
						var c_name = current.skill_name
						if n_name != c_name: needs_update = true
						
					if needs_update:
						sm.equip_item(i, new_skill)
		
	if data.has("isRage") or data.has("isRyze"):
		is_rage = bool(data.get("isRage", data.get("isRyze", false)))
		
	if data.has("type"):
		var t = str(data.type).to_int()
		# v224.30: Forzar recarga si el tipo cambió O si el 3D falló (polígono rosa visible)
		if t != entity_type or not is_instance_valid(_3d_model): 
			entity_type = t
			_adjust_visuals(t)
			
	# Forzar regenerar el tag para enemigos si estamos en local y somos T1/T4 etc
	_update_tags()

func _update_tags():
	if not name_tag: return
	
	# Verificar si los valores realmente cambiaron para evitar reconstruir el RichTextLabel innecesariamente
	if (
		abs(current_hp - _last_rendered_hp) < 1.0 and
		abs(current_shield - _last_rendered_shield) < 1.0 and
		abs(max_hp - _last_rendered_max_hp) < 1.0 and
		abs(max_shield - _last_rendered_max_shield) < 1.0 and
		username == _last_rendered_username and
		clan_tag == _last_rendered_clan_tag and
		is_rage == _last_rendered_is_rage and
		pvp_status == _last_rendered_pvp_status
	):
		return # No cambió nada visual, evitar recálculo

	# Guardar valores actuales
	_last_rendered_hp = current_hp
	_last_rendered_shield = current_shield
	_last_rendered_max_hp = max_hp
	_last_rendered_max_shield = max_shield
	_last_rendered_username = username
	_last_rendered_clan_tag = clan_tag
	_last_rendered_is_rage = is_rage
	_last_rendered_pvp_status = pvp_status

	if not name_tag is RichTextLabel:
		var rtl = RichTextLabel.new()
		rtl.name = name_tag.name
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rtl.bbcode_enabled = true
		rtl.scroll_active = false
		rtl.clip_contents = false
		rtl.fit_content = true
		rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		
		var parent = name_tag.get_parent()
		if parent:
			parent.add_child(rtl)
			rtl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			rtl.grow_horizontal = Control.GROW_DIRECTION_BOTH
			rtl.grow_vertical = Control.GROW_DIRECTION_BOTH
			name_tag.queue_free()
			name_tag = rtl
			
	if name_tag:
		var is_enemy = is_in_group("enemies")
		var name_sz = SettingsManager.font_size_enemy_name if is_enemy else SettingsManager.font_size_player_name
		var stats_sz = SettingsManager.font_size_enemy_stats if is_enemy else SettingsManager.font_size_player_stats
		var name_bold = SettingsManager.bold_enemy_name if is_enemy else SettingsManager.bold_player_name
		var stats_bold = SettingsManager.bold_enemy_stats if is_enemy else SettingsManager.bold_player_stats
		
		name_tag.add_theme_font_size_override("normal_font_size", name_sz)
		name_tag.add_theme_font_size_override("bold_font_size", name_sz)
		name_tag.add_theme_font_size_override("font_size", name_sz)
		name_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		name_tag.add_theme_constant_override("outline_size", 4)
		if name_tag is RichTextLabel:
			name_tag.bbcode_enabled = true
			var n_color = "#bf00ff" if is_rage else ("#ff3333" if pvp_status else "#ffffff")
			var txt = "[center]"
			
			# v244.110: Mostrar TAG de Flota con color según relación
			var name_str = username
			if clan_tag != "":
				var local_player = _get_player_node()
				var my_tag = ""
				if is_instance_valid(local_player) and "clan_tag" in local_player:
					my_tag = local_player.clan_tag.strip_edges()
				
				var tag_color = "#ffff00" # Amarillo = neutral/desconocido
				if my_tag != "" and my_tag.to_lower() == clan_tag.strip_edges().to_lower():
					tag_color = "#00ff44" # Verde = aliado (mismo clan)
				
				var wrap_b_start = "[b]" if name_bold else ""
				var wrap_b_end = "[/b]" if name_bold else ""
				name_str = wrap_b_start + "[color=" + tag_color + "][" + clan_tag + "][/color]" + wrap_b_end + " " + username
			
			var wrap_name_start = "[b]" if name_bold else ""
			var wrap_name_end = "[/b]" if name_bold else ""
			if is_rage: txt += wrap_name_start + "[wave amp=50 freq=2][color=" + n_color + "]" + name_str + "[/color][/wave]" + wrap_name_end + "\n"
			else: txt += wrap_name_start + "[color=" + n_color + "]" + name_str + "[/color]" + wrap_name_end + "\n"
			
			var wrap_stats_start = "[b]" if stats_bold else ""
			var wrap_stats_end = "[/b]" if stats_bold else ""
			txt += wrap_stats_start + "[color=#00ffff][font_size=" + str(stats_sz) + "]SH: " + str(int(current_shield)) + " / " + str(int(max_shield)) + "[/font_size][/color]" + wrap_stats_end + "\n"
			txt += wrap_stats_start + "[color=#00ff00][font_size=" + str(stats_sz) + "]HP: " + str(int(current_hp)) + " / " + str(int(max_hp)) + "[/font_size][/color]" + wrap_stats_end + "[/center]"
			name_tag.text = txt
		else: 
			# Caso Label normal: sin BBCode, color plano
			var name_str = username
			if clan_tag != "": name_str = "[" + clan_tag + "] " + username
			name_tag.text = name_str + "\nSH: " + str(int(current_shield)) + " / " + str(int(max_shield)) + "\nHP: " + str(int(current_hp)) + " / " + str(int(max_hp))
			if name_bold or stats_bold:
				name_tag.add_theme_font_override("font", SettingsManager.get_bold_font())
			else:
				name_tag.remove_theme_font_override("font")
				
			if is_rage:
				name_tag.add_theme_color_override("font_outline_color", Color(0.75, 0, 1)) # Borde Violeta
				name_tag.add_theme_constant_override("outline_size", 10) # Borde grueso para que se vea
			else:
				name_tag.add_theme_color_override("font_outline_color", Color.BLACK)
				name_tag.add_theme_constant_override("outline_size", 4)

func _resurrect(data: Dictionary):
	# v306.5: Lógica de Resurrección Centralizada (Soluciona Invisibilidad por Culling)
	is_dead = false
	is_teleporting = true 
	_clear_wreckage_marker()

	# 1. Salto instantáneo a la posición de respawn
	if data.has("x") and data.has("y"):
		global_position = Vector2(_safe_float(data.x, global_position.x), _safe_float(data.y, global_position.y))
		target_position = global_position
		if data.has("rot"):
			rotation = _safe_float(data.rot, rotation)
			target_rotation = rotation

	# 2. Reset visual completo (Igual que el Player al spawnear)
	_update_flash_visuals(0.0)
	rebuild_3d_layout()
	
	# Limpiar auras activas viejas del pooling
	for mId in active_auras:
		var aura_data = active_auras[mId]
		if is_instance_valid(aura_data.node):
			aura_data.node.queue_free()
	active_auras.clear()

	# 3. Restaurar visibilidad y estado de todos los componentes
	modulate = Color(1, 1, 1, 1)
	visible = true; show()
	if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = true
	if is_instance_valid(world_root_3d): 
		world_root_3d.visible = true
		world_root_3d.scale = Vector3(1,1,1) # Reset de escala por si el pooling la rompió
	if _collision_shape: _collision_shape.set_deferred("disabled", false)
	set_meta("is_pooled", false)

	# 4. Reactivar procesos
	set_physics_process(true); set_process(true)

	# 5. Desbloquear culling y lerp de inmediato para evitar efecto acordeón
	is_teleporting = false
	
	if _ui_wrapper: _ui_wrapper.queue_redraw()

func take_damage(amt: float, attacker_pos: Vector2 = Vector2.ZERO, attacker_id: String = ""):
	var original_amt = amt
	# Mecánica de colores cooperativa (boss_colors)
	if has_meta("boss_color"):
		var req_color = get_meta("boss_color")
		var my_color = ""
		var pl = get_tree().get_first_node_in_group("player")
		if is_instance_valid(pl) and pl.has_meta("my_color"):
			my_color = pl.get_meta("my_color")
		if my_color != req_color:
			amt = 0.0

	if invulnerable_timer > 0 or is_invulnerable:
		amt = 0 # v269.185: Bloqueo visual total de daño (0 en rojo para feedback)
	
	# v268.820: Soporte visual AAA para Muro de Energía (Wall Dome)
	for mId in active_auras:
		var a_data = active_auras[mId]
		if a_data.get("type") == "wall_dome":
			var radius = a_data.get("radius", 300.0)
			var pl = get_tree().get_first_node_in_group("player")
			if is_instance_valid(pl):
				var dist = pl.global_position.distance_to(global_position)
				if dist > radius:
					amt = 0.0
	
	# v235.20: REFLEJO TOTAL (Prioridad absoluta sobre invulnerabildiad)
	if reflect_timer > 0:
		var r_amt = int(amt * 0.8)
		if r_amt < 1: r_amt = 1
		
		# 1. VISUAL: Garantizar efecto
		var target_node = null
		if attacker_id != "":
			for ent in get_tree().get_nodes_in_group("entities"):
				if str(ent.get("entity_id")) == attacker_id:
					target_node = ent; break
		
		var visual_target = attacker_pos
		if visual_target == Vector2.ZERO and target_node: visual_target = target_node.global_position
		_trigger_reflect_visual(visual_target if visual_target != Vector2.ZERO else global_position + Vector2.UP)

		# 2. DAÑO: Notificación Red (Obligatorio) + Aplicación Local (Si existe el nodo)
		if is_in_group("player") and attacker_id != "" and attacker_id != entity_id:
			# Siempre notificar al servidor
			if NetworkManager:
				if target_node and is_instance_valid(target_node) and target_node.is_in_group("remote_players"):
					NetworkManager.send_event("playerHitByPlayer", {"victimId": attacker_id, "damage": r_amt})
				else:
					# Por defecto PvE si no es un jugador remoto conocido
					NetworkManager.send_event("enemyHit", {"enemyId": attacker_id, "damage": r_amt})
				print("[REFLECT-OUT] Devolviendo: ", r_amt, " a ", attacker_id)
			
			# Aplicar localmente solo para feedback visual inmediato
			if target_node and is_instance_valid(target_node) and target_node.has_method("take_damage"):
				target_node.take_damage(r_amt, global_position, entity_id)


	if is_god or is_dead: return
	
	if original_amt <= 0.0:
		_spawn_damage_text("0", Color.RED)
		return
		
	reset_combat_timer() # Bloqueo local de regen
	
	# v235.31: Daño Local (Visual) para TODOS (incluyendo player)
	if current_shield >= amt: current_shield -= amt
	else:
		var d = amt - current_shield
		current_hp -= d; current_shield = 0

	_spawn_damage_text(str(int(amt)), Color.RED)
	_trigger_hit_flash()

	_update_tags()
	if is_in_group("player") and has_method("_emit_stats"):
		call("_emit_stats") # v164.72: Actualizar HUD local instantáneamente
	if current_hp <= 0: die()

func _trigger_reflect_visual(p_dest: Vector2):

	var spr = Sprite2D.new()
	var path = "res://assets/Efectos de Skills/Reflect (Rojo)/Reflect (Transp).png"
	if ResourceLoader.exists(path):
		spr.texture = load(path)
		spr.top_level = true
		spr.z_index = 101
		
		# v235.11: Dirección del rebote
		var dir_to_target = (p_dest - global_position).normalized()
		if dir_to_target.length() < 0.1: dir_to_target = Vector2.UP
		
		var spawn_origin = global_position
		if get_meta("is_single_world", false) and is_instance_valid(world_root_3d):
			var current_map = get_tree().get_first_node_in_group("map")
			if is_instance_valid(current_map) and is_instance_valid(current_map.camera_3d):
				var cam3d = current_map.camera_3d
				var sub_vp = current_map.sub_viewport
				if not cam3d.is_position_behind(world_root_3d.global_position):
					var sv_pixel = cam3d.unproject_position(world_root_3d.global_position)
					if is_instance_valid(sub_vp) and sub_vp.size.x > 0 and sub_vp.size.y > 0:
						var main_size = Vector2(get_viewport().get_visible_rect().size)
						sv_pixel *= main_size / Vector2(sub_vp.size)
					spawn_origin = get_viewport().get_canvas_transform().affine_inverse() * sv_pixel
		
		spr.global_position = spawn_origin + dir_to_target * 35.0
		# v235.12: Quitamos el offset para que no salga de costado
		spr.rotation = dir_to_target.angle()
		
		spr.scale = Vector2(0.01, 0.01)
		spr.modulate = Color(4.0, 0.4, 0.4, 1.0)
		
		get_tree().root.add_child(spr)
		
		var tw = create_tween().set_parallel(true)
		var travel_dist = dir_to_target * 140.0
		tw.tween_property(spr, "global_position", spr.global_position + travel_dist, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "scale", Vector2(0.12, 0.12), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "modulate:a", 0.0, 0.2).set_delay(0.12)
		
		tw.finished.connect(spr.queue_free)

func _spawn_damage_text(txt: String, clr: Color):
	var dt_script = DamageTextScript
	if dt_script:
		var dt = Marker2D.new()
		dt.z_index = 100
		dt.set_script(dt_script)
		
		# v222.95: Añadir al wrapper de UI de la nave para que la SIGA
		var target_parent = _ui_wrapper if is_instance_valid(_ui_wrapper) else self
		target_parent.add_child(dt)
		
		# v222.96: Si es hijo del wrapper, la posición es relativa
		dt.position = Vector2(0, -60)
		
		if dt.has_method("setup"): dt.setup(txt, clr)

func die():
	if is_dead: return
	is_dead = true
	
	# 1. Detener toda la lógica del objeto inmediatamente
	set_physics_process(false)
	set_process(false)
	
	# 2. Desaparecer el asset al instante (Evita quedar congelado o en blanco)
	visible = false
	if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = false
	if is_instance_valid(world_root_3d): world_root_3d.visible = false
	
	if is_instance_valid(_3d_propulsion):
		_3d_propulsion.emitting = false
	
	# Limpieza explícita de esferas 3D en muerte para evitar que queden flotando y agrandadas
	for s in _3d_spheres:
		if is_instance_valid(s):
			s.queue_free()
	_3d_spheres = [null, null, null, null]
	
	# 3. Limpieza de efectos visuales residuales para el pooling/respawn
	_update_flash_visuals(0.0)
	if is_instance_valid(sprite):
		sprite.modulate = Color(1, 1, 1, 1)
		
	# Limpiar auras visuales activas en muerte
	for mId in active_auras:
		var aura_data = active_auras[mId]
		if is_instance_valid(aura_data.node):
			aura_data.node.queue_free()
	active_auras.clear()
		
	# 4. Spawnear la explosión (VFX) justo donde estaba la nave
	_spawn_death_vfx()
	
	# Spawnear el marcador de restos (evitar para pilares y orbes de agua)
	var is_special_defense = entity_type == 200 or entity_type == 201 or "pillar" in entity_id or "orb" in entity_id
	if not is_special_defense:
		_spawn_wreckage_marker()
	
	# 5. Lógica de pooling/limpieza para enemigos
	if not is_in_group("player") and not is_in_group("remote_players"): 
		if is_special_defense:
			if is_instance_valid(world_root_3d):
				world_root_3d.queue_free()
			queue_free()
		else:
			set_meta("is_pooled", true)
			if _collision_shape: _collision_shape.set_deferred("disabled", true)

# ---------------------------------------------------------
# v266.985: Mecánicas de Ataque Orbital (Pedido del Usuario)
# Ahora gestionadas por Projectile.gd directamente para consistencia de asset
var _is_orbital_active: bool = false

func _on_enemy_action(data):
	if str(data.id) != entity_id: return
	
	match data.action:
		"orbital_strike_start": 
			_is_orbital_active = true
		"orbital_strike_fire": 
			_is_orbital_active = false
		"wall_dome_start":
			var mId = data.get("mId", "wall_dome")
			if not active_auras.has(mId):
				var spr = Sprite2D.new()
				var tex_path = "res://assets/Efectos de Skills/Reflect (Rojo)/Reflect Aura (Transp).png"
				if ResourceLoader.exists(tex_path):
					spr.texture = load(tex_path)
				spr.modulate = Color(0.0, 0.6, 1.0, 0.45)
				var radius = float(data.get("radius", 300.0))
				var target_scale = (radius * 2.0) / 512.0
				spr.scale = Vector2.ZERO
				_vfx_container_2d.add_child(spr)
				active_auras[mId] = {"node": spr, "target_scale": target_scale, "type": "wall_dome", "radius": radius}
				var tw = create_tween()
				tw.tween_property(spr, "scale", Vector2(target_scale, target_scale), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				queue_redraw()
		"wall_dome_end":
			var mId = data.get("mId", "wall_dome")
			if active_auras.has(mId):
				var a_data = active_auras[mId]
				var spr = a_data.node
				active_auras.erase(mId)
				var tw = create_tween()
				tw.tween_property(spr, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
				tw.finished.connect(spr.queue_free)
				queue_redraw()
		"reflect_start":
			reflect_timer = float(data.get("duration", 3000.0)) / 1000.0
			print("[REFLECT-IN] Enemigo activó reflect por ", reflect_timer, "s")
		"reflect_end":
			reflect_timer = 0.0
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
			_trigger_reflect_visual(visual_target if visual_target != Vector2.ZERO else global_position + Vector2.UP)


func _fire_orbital_strike():
	# v266.992: Buscar los proyectiles que ya están orbitando y soltarlos
	var projs = get_tree().get_nodes_in_group("projectiles")
	for p in projs:
		if is_instance_valid(p) and str(p.get("owner_id")) == entity_id:
			if p.has_method("release_orbit"):
				p.release_orbit()


func _on_enemy_aura(data):
	if str(data.id) != entity_id: return
	# v268.67: Seguridad contra crash de red en entidades ya eliminadas
	if not is_instance_valid(self) or is_queued_for_deletion():
		return

	var mId = data.mId
	if data.active:
		if active_auras.has(mId): return
		
		var spr = Sprite2D.new()
		var tex_path = "res://assets/Efectos de Skills/Reflect (Rojo)/Reflect Aura (Transp).png"
		if ResourceLoader.exists(tex_path):
			spr.texture = load(tex_path)
		
		spr.modulate = Color(1, 0, 0, 0.4) # Default rojo (daño)
		if data.type == "aura_heal": spr.modulate = Color(0, 1, 0.4, 0.4)
		elif data.type == "aura_speed": spr.modulate = Color(1, 0.8, 0, 0.4)
		
		# v268.800: Escalar según el radio del aura (textura base es ~512px)
		var radius = data.get("radius", 200)
		var target_scale = (float(radius) * 2.0) / 512.0
		spr.scale = Vector2.ZERO
		
		_vfx_container_2d.add_child(spr)
		active_auras[mId] = {"node": spr, "target_scale": target_scale, "type": data.type}
		
		var tw = create_tween()
		tw.tween_property(spr, "scale", Vector2(target_scale, target_scale), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		if active_auras.has(mId):
			var a_data = active_auras[mId]
			var spr = a_data.node
			active_auras.erase(mId)
			
			var tw = create_tween()
			tw.tween_property(spr, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.finished.connect(spr.queue_free)

func _update_auras(delta):
	for mId in active_auras:
		var a_data = active_auras[mId]
		var spr = a_data.node
		if is_instance_valid(spr):
			# Efecto de pulso y rotación suave
			var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.004) * 0.05
			var s = a_data.target_scale * pulse
			spr.scale = Vector2(s, s)
			spr.rotate(delta * 0.5)
			if a_data.get("type") == "wall_dome":
				queue_redraw()

func _adjust_visuals(_type): 
	if is_in_group("enemies"):
		_setup_enemy_visuals()
		queue_redraw()

# v165.80: Sistema de Burbujas Apiladas (Frame Stacking)
func show_bubble(p_text: String):
	# Subir los mensajes anteriores para dejar espacio al nuevo
	var bubble_container = _ui_wrapper if is_instance_valid(_ui_wrapper) else self
	for child in bubble_container.get_children():
		if child.has_meta("is_chat_bubble"):
			var shift_tw = create_tween().set_parallel(true)
			shift_tw.tween_property(child, "position:y", child.position.y - 35, 0.25)
			# Los mensajes viejos duran menos conforme suben
			shift_tw.tween_property(child, "modulate:a", child.modulate.a * 0.7, 0.25)

	var bubble = Label.new()
	bubble.text = p_text
	bubble.set_meta("is_chat_bubble", true)
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.custom_minimum_size = Vector2(280, 20)
	bubble.grow_horizontal = Control.GROW_DIRECTION_BOTH
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.border_width_left = 1; style.border_width_top = 1
	style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = Color(0, 1, 1, 0.8) 
	style.set_corner_radius_all(4)
	style.content_margin_left = 8; style.content_margin_right = 8
	style.content_margin_top = 4; style.content_margin_bottom = 4
	
	bubble.add_theme_stylebox_override("normal", style)
	bubble.add_theme_font_size_override("font_size", SettingsManager.font_size_chat_bubble)
	if SettingsManager.bold_chat_bubble:
		bubble.add_theme_font_override("font", SettingsManager.get_bold_font())
	bubble.add_theme_color_override("font_shadow_color", Color.BLACK)
	
	if is_instance_valid(_ui_wrapper):
		_ui_wrapper.add_child(bubble)
	else:
		add_child(bubble)
		
	bubble.z_index = 10
	# Posición base de inicio centrada usando el ancho de la burbuja
	bubble.position = Vector2(-280.0 / 2.0, -110)
	
	# Animación y Autodestrucción Segura
	var tw = create_tween()
	tw.tween_property(bubble, "position:y", bubble.position.y - 20, 0.5) 
	tw.tween_interval(3.5)
	tw.tween_property(bubble, "modulate:a", 0.0, 1.0)
	tw.finished.connect(bubble.queue_free)

func _setup_ship_visuals():
	# Limpieza de sprite anterior si existe para evitar duplicados
	if is_instance_valid(sprite): sprite.queue_free()
	if is_instance_valid(anim_player): anim_player.queue_free()
	
	var poly = get_node_or_null("Polygon2D")
	if poly: poly.visible = false
	
	sprite = Sprite2D.new(); sprite.name = "ShipSprite"
	
	# v210.50: SELECTOR DE ASSETS DINÁMICO
	var path = ""
	var h_f = 1; var v_f = 1
	var rot_offset = 0.0 # Compensación de rotación si el asset no apunta a la derecha
	
	# v222.0: ACTIVACIÓN DE FLOTA 3D (Mapeo dinámico y hardcoded tradicional)
	var glb_path = ""
	var ship_data = {}
	if GameConstants.SHIP_MODELS:
		for s in GameConstants.SHIP_MODELS:
			if int(s.get("id")) == int(current_ship_id):
				ship_data = s
				break

	if ship_data.has("assetPath") and ship_data.assetPath != "":
		glb_path = ship_data.assetPath
	else:
		match current_ship_id:
			1: glb_path = "res://assets/Personajes/3D/Nave1/futuristic+jet+3d+model_Clone1.glb"
			2: glb_path = "res://assets/Personajes/3D/Nave2/Nave2.glb"
			3: glb_path = "res://assets/Personajes/3D/Nave3/Nave3.glb"
			4: glb_path = "res://assets/Personajes/3D/Nave4/Nave4.glb"
			5: glb_path = "res://assets/Personajes/3D/Nave5/Nave5.glb"
			6: glb_path = "res://assets/Personajes/3D/Nave6/Nave6.glb"

	if glb_path != "" and ResourceLoader.exists(glb_path):
		_setup_3d_visuals(glb_path)
		
		# --- PARCHES DE ORIENTACIÓN SEGÚN EL ASSET ---
		# Buscamos el modelo real (hijo del _3d_model que es el nodo control)
		var actual_model = _3d_model.get_child(0) if _3d_model and _3d_model.get_child_count() > 0 else null
		if actual_model:
			if ship_data.has("rotX") or ship_data.has("rotY") or ship_data.has("rotZ"):
				actual_model.rotation_degrees.x = float(ship_data.get("rotX", 0))
				actual_model.rotation_degrees.y = float(ship_data.get("rotY", 0))
				actual_model.rotation_degrees.z = float(ship_data.get("rotZ", 0))
			else:
				match current_ship_id:
					3: # NAVE 3: Calibrada manualmente para estar plana y al frente
						actual_model.rotation_degrees.x = 0
						actual_model.rotation_degrees.y = 1
						actual_model.rotation_degrees.z = 98
					4: # NAVE 4: Posición perfecta lograda por calibración manual
						actual_model.rotation_degrees.x = 0
						actual_model.rotation_degrees.y = -180
						actual_model.rotation_degrees.z = 52
					6: # NAVE 6: Viene en reversa
						actual_model.rotation_degrees.y = 180
			
			# v220.72: APLICAR MEMORIA DE USUARIO (Si el piloto calibró esta nave en esta sesión)
			if _ship_rot_mem.has(current_ship_id):
				actual_model.rotation_degrees = _ship_rot_mem[current_ship_id]
		return # Salto al modo 3D pro
	
	# Mapeo 2D original (Backup)
	match current_ship_id:
		1: path = "res://assets/Personajes/2D/Nave1/Nave1 (Lista).png"
		2: 
			path = "res://assets/Personajes/2D/Nave2/Nave2 (Lista).png"
			rot_offset = 90.0
		3: 
			path = "res://assets/Personajes/2D/Nave3/Nave3.png"
			rot_offset = 90.0
		4: 
			path = "res://assets/Personajes/2D/Nave4/Nave4.png"
			rot_offset = 90.0
		5: 
			path = "res://assets/Personajes/2D/Nave5/Nave5.png"
			rot_offset = 90.0
		6: 
			path = "res://assets/Personajes/2D/Nave6/Nave6.png"
			rot_offset = 90.0
		_:
			path = "res://assets/Personajes/2D/Nave1/Nave1 (Lista).png"
	
	if path == "": return
	
	var tex = load(path)
	if tex:
		sprite.texture = tex
		sprite.hframes = h_f
		sprite.vframes = v_f
		
		# v218.10: UNIFICACIÓN DE TAMAÑOS (Target 160x160 para todas las naves)
		var frame_w = tex.get_width() / float(h_f)
		var frame_h = tex.get_height() / float(v_f)
		var target_size = 160.0
		var s = target_size / max(frame_w, frame_h)
		sprite.scale = Vector2(s, s)
		
		# v210.55: COMPENSACIÓN DE ORIENTACIÓN (Si el asset no apunta a la derecha)
		if rot_offset != 0.0:
			sprite.rotation_degrees = rot_offset
		
		# Escalar Hitbox proporcionalmente
		var col = get_node_or_null("CollisionPolygon2D")
		if is_instance_valid(col): col.scale = Vector2((target_size * 0.85)/35.0, (target_size * 0.85)/35.0)
	
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	
	# v210.40: Configuración de AnimPlayer
	anim_player = AnimationPlayer.new()
	sprite.add_child(anim_player) 
	anim_player.root_node = NodePath(".")
	
	var lib = AnimationLibrary.new()
	anim_player.add_animation_library("", lib)
	
	# Mapeo de animaciones (Si son imágenes simples de 1 frame, h_f será 1)
	if h_f == 1:
		_create_anim(lib, "idle", 0, 1, 0.15, true)
		_create_anim(lib, "start_move", 0, 1, 0.08, false) 
		_create_anim(lib, "run", 0, 1, 0.1, true)      
		_create_anim(lib, "death", 0, 1, 0.08, false) 
	elif h_f == 4: # Caso especial Vulture
		_create_anim(lib, "idle", 0, 4, 0.15, true)
		_create_anim(lib, "start_move", 4, 4, 0.08, false) 
		_create_anim(lib, "run", 8, 4, 0.1, true)      
		_create_anim(lib, "death", 12, 4, 0.08, false) 
	
	anim_player.play("idle")

func _create_anim(lib: AnimationLibrary, a_name: String, start: int, count: int, step: float, loop: bool):
	var anim = Animation.new()
	var track = anim.add_track(Animation.TYPE_VALUE)
	# v210.41: Ruta absoluta al frame del nodo raíz del AnimationPlayer
	anim.track_set_path(track, NodePath(".:frame"))
	for i in range(count): anim.track_insert_key(track, i * step, start + i)
	if loop: anim.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation(a_name, anim)

func _setup_enemy_visuals():
	if entity_type == 201:
		if is_instance_valid(world_root_3d):
			world_root_3d.queue_free()
			world_root_3d = null
		for c in get_children():
			if "Viewport" in c.name or c is Sprite2D or c is Polygon2D or c is Line2D or c.name == "Ship3DRender":
				c.queue_free()
		
		# Orbe de agua visual procedural (Esfera celeste translúcida)
		var poly = Polygon2D.new()
		poly.name = "WaterOrbVisual"
		var pts = PackedVector2Array()
		for i in range(25):
			var a = (i / 24.0) * PI * 2
			pts.append(Vector2(cos(a), sin(a)) * 25.0)
		poly.polygon = pts
		poly.color = Color(0.0, 0.6, 1.0, 0.65) # Celeste transparente
		add_child(poly)
		
		# Aro exterior brillante
		var line = Line2D.new()
		line.points = pts
		line.width = 3.0
		line.default_color = Color(0.5, 0.9, 1.0, 0.9)
		add_child(line)
		
		# Ocultar name tags y HUD
		if is_instance_valid(name_tag): name_tag.visible = false
		if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = false
		return

	var glb_path = ""
	var enemy_rot_offset = 0.0
	var enemy_scale = 3.0 
	var path = "" 
	
	# v255.15: CONFIGURACIÓN NORMALIZADA (Manual de Activos)
	match entity_type:
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13:
			glb_path = "res://assets/Enemigos/3D/Enemigo" + str(entity_type) + "/Enemigo" + str(entity_type) + ".glb"
			enemy_rot_offset = 90.0
			# Excepciones de rotación específicas detectadas en pruebas
			if entity_type == 7 or entity_type == 4: enemy_rot_offset = 180.0
			if entity_type == 6 or entity_type == 8: enemy_rot_offset = 0.0
			
		101: # Lord Titán (Boss1)
			glb_path = "res://assets/Enemigos/3D/Bosses/Boss1/Boss1.glb"
			enemy_rot_offset = 90.0
			enemy_scale = 6.0
		102: # Ancient Titán (Boss2)
			glb_path = "res://assets/Enemigos/3D/Bosses/Boss2/Boss2.glb"
			enemy_rot_offset = 90.0
			enemy_scale = 6.0
		103: # Mechanic Boss (Boss3)
			glb_path = "res://assets/Enemigos/3D/Bosses/Boss3/Boss3.glb"
			enemy_rot_offset = 180.0
			enemy_scale = 6.0
		104: # Stellar Guardian (Boss4)
			glb_path = "res://assets/Enemigos/3D/Bosses/Boss4/Boss4.glb"
			enemy_rot_offset = 0.0
			enemy_scale = 8.0
		200: # Pilar Protector
			glb_path = "res://assets/Pilares/3D/Pilar1/Pilar1.glb"
			enemy_rot_offset = 0.0
			enemy_scale = 5.0

	# if glb_path != "":
	# 	print("[CORE] Cargando Enemigo 3D: ", glb_path, " Tipo: ", entity_type)
	
	# v306.6: ELIMINACIÓN DE OPTIMIZACIÓN "SMART-JUMP"
	# Se fuerza siempre el setup visual para garantizar que world_root_3d se asocie al Viewport del mapa actual.
	# La optimización anterior fallaba al reciclar enemigos entre diferentes mapas o sesiones de pooling.

	set_meta("current_glb", glb_path)

	# Limpieza
	if is_instance_valid(sprite): sprite.queue_free(); sprite = null
	if is_instance_valid(anim_player): anim_player.queue_free()
	var poly_node = get_node_or_null("Polygon2D")
	if poly_node: poly_node.visible = false

	# Carga de Visual 3D
	if glb_path != "":
		for c in get_children():
			if "Viewport" in c.name or c is Sprite2D or c is Polygon2D or c.name == "Ship3DRender":
				c.queue_free()
		
		_setup_3d_visuals(glb_path, enemy_rot_offset)
		if is_instance_valid(_3d_model):
			_3d_model.scale = Vector3(enemy_scale, enemy_scale, enemy_scale)
			return
		else:
			print("[VISUAL-WARN] Falló carga 3D para ", username, ". Usando fallback 2D.")


	# Fallback a 2D (v223.1: Rutas Corregidas 2D)
	match entity_type:
		1: path = "res://assets/Enemigos/2D/Enemigo1/Enemy1Map1.png"
		2: path = "res://assets/Enemigos/2D/Enemigo1/Enemy1Map1.png" # Fallback a E1
		3: path = "res://assets/Enemigos/2D/Enemigo2/Enemy2Map1.png" # Fallback a E2
		5: path = "res://assets/Enemigos/2D/Enemigo2/Enemy2Map1.png"
		8: path = "res://assets/Enemigos/2D/Enemigo3/Enemy3Map1.png"
		7: path = "res://assets/Enemigos/2D/Enemigo3/Enemy3Map1.png" # Fallback a E3
		9: path = "res://assets/Enemigos/2D/Enemigo1/Enemy1Map1.png" # Fallback a E1
		4: path = "res://assets/Enemigos/2D/Bosses/Boss1/Boss1.png"
		10: path = "res://assets/Enemigos/2D/Bosses/Boss2/Boss2.png"
		11: path = "res://assets/Enemigos/2D/Bosses/Boss3/Boss3.png"
		6: path = "res://assets/Enemigos/2D/Enemigo6/Enemigo6.png"
	
	if path == "": path = "res://assets/Enemigos/2D/Enemigo1/Enemy1Map1.png"
	
	if ResourceLoader.exists(path):
		sprite = Sprite2D.new(); sprite.name = "EnemySprite"
		var tex = load(path)
		sprite.texture = tex
		
		# Bosses tienen escala monumental (320px), minions normales (160px)
		var target_size = 320.0 if entity_type >= 4 else 160.0
		
		var s = target_size / max(tex.get_width(), tex.get_height())
		sprite.scale = Vector2(s, s)
		
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(sprite)
		
		# Ajustar el Hitbox base del objeto (que mide aprox 25px de largo originalmente)
		var col = get_node_or_null("CollisionPolygon2D")
		if is_instance_valid(col):
			var factor = (target_size * 0.85) / 25.0
			col.scale = Vector2(factor, factor)
	
	# Asegurarnos de borrar toda geometria fea que este de fondo o recargar
	_update_collision_size()
	queue_redraw()

func _update_animations():
	if not anim_player or not is_instance_valid(sprite): return
	if is_dead: return
		
	var vel_len = velocity.length()
	
	# v191.55: REPOSO (Idle en bucle)
	if vel_len < 10.0:
		if anim_player.current_animation != "idle":
			anim_player.play("idle")
		return

	# v210.181: Transición Inteligente Aceleración -> Máxima
	if vel_len > 10.0:
		if anim_player.current_animation == "idle":
			anim_player.play("start_move")
		
		# Si ya terminó de arrancar, pasamos a modo Crucero (Run)
		if anim_player.current_animation == "start_move" and not anim_player.is_playing():
			anim_player.play("run")
		
		# Si nos movemos y no hay nada sonando, forzamos Run
		if anim_player.current_animation == "" or (not anim_player.is_playing() and vel_len > 100.0):
			anim_player.play("run")

# v210.161: Helper para limpiar visuales de equipo (evita duplicidad)
func _clear_all_equipment_visuals():
	# Buscar nodos de equipo bajo esta entidad y eliminarlos
	if is_instance_valid(sprite):
		for child in sprite.get_children():
			if child is Sprite2D or child is Node2D:
				# Si el nodo es de equipamiento, lo volamos
				if child.name.begins_with("Equip_") or child.is_in_group("ship_equipment"):
					child.queue_free()
	
	if is_instance_valid(_ui_wrapper):
		_ui_wrapper.queue_redraw()

func play_skill_vfx(skill_name: String, amount: float = 0.0):
	# Mostrar siempre los números de retroalimentación
	if has_method("_spawn_damage_text"):
		if skill_name == "ESCUDO CELULAR" or skill_name == "FORTALEZA-X": _spawn_damage_text("+" + str(int(amount)), Color.AQUA)
		elif skill_name == "AUTO-REPARACIÓN" or skill_name == "NANO-REGENERACIÓN" or skill_name == "REGENERACIÓN ALFA" or skill_name == "VÍNCULO VITAL" or skill_name == "BALIZA DE CURACION": _spawn_damage_text("+" + str(int(amount)), Color.GREEN)
		elif skill_name == "TURBO-IMPULSO": _spawn_damage_text("+" + str(int(amount)), Color.YELLOW)
	match skill_name:
		"TURBO-IMPULSO":
			# v4.1: Aplicar velocidad real si es un jugador (Aliado o Local)
			if "speed" in self:
				var bonus = amount
				self.speed += bonus
				get_tree().create_timer(2.0).timeout.connect(func(): 
					if is_instance_valid(self): self.speed -= bonus
				)
				
			var path = "res://assets/Efectos de Skills/Velocidad(Transp).png"
			if ResourceLoader.exists(path):
				var vfx = Sprite2D.new(); var t = load(path); vfx.texture = t
				var s = 145.0 / max(t.get_width(), t.get_height())
				vfx.scale = Vector2(s, s); vfx.rotation_degrees = 180
				vfx.position = Vector2(-65, 0)
				vfx.z_index = -1
				_vfx_container_2d.add_child(vfx)
				var tw = create_tween().set_loops()
				tw.bind_node(vfx)
				tw.tween_property(vfx, "scale", Vector2(s*1.3, s*0.8), 0.1)
				tw.tween_property(vfx, "scale", Vector2(s*0.8, s*1.3), 0.1)
				get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(vfx): vfx.queue_free())
		"ESCUDO CELULAR", "FORTALEZA-X":
			shield_visual_timer = 2.0 # Activar visual 3D pro
			# v260.20: Se eliminó el Sprite2D viejo para limpiar la visual 3D

		"AUTO-REPARACIÓN", "NANO-REGENERACIÓN":
			heal_visual_timer = 2.0 # Activar visual 3D pro de curación
			# v260.30: Se eliminó el Sprite2D de curación en favor del efecto 3D
		
		"SMOKE-BOMB":
			pass # La visual es gestionada por World.gd de forma global

		
		"INVULNERABILIDAD":
			invulnerable_timer = 2.0 # Activar visual 3D amarilla
			print("[SKILL] Activando visual de INVULNERABILIDAD para: ", username)
		"BLINK_OUT":
			# v3.2: Desaparición TOTAL e INSTANTÁNEA (sin VFX expansivo)
			modulate.a = 0.0
			if is_instance_valid(_3d_model): _3d_model.visible = false
			if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = false
		"BLINK_IN":
			# v3.2: Reaparición con destello puntual (sin nova expansiva)
			modulate.a = 1.0
			if is_instance_valid(_3d_model): _3d_model.visible = true
			if is_instance_valid(_ui_wrapper): _ui_wrapper.visible = true
			# Destello blanco puntual en el destino (no expansivo)
			var tw = create_tween()
			tw.tween_property(self, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.0)
			tw.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)


# v219.70: SISTEMA DE RENDERIZADO 3D SOBRE 2D (EXPERIMENTAL)
func _setup_3d_visuals(glb_path: String, rot_offset: float = 0.0):
	# print("[3D] Inicializando renderizado para: ", glb_path)
	
	# v306.4: Evitar duplicaciones de naves huérfanas al reconstruir el layout 3D en cambios de mapa
	if is_instance_valid(world_root_3d):
		world_root_3d.queue_free()
		world_root_3d = null
	_3d_propulsion = null
	
	# Detectar si hay un lienzo 3D global en el mapa actual
	var current_map = get_tree().get_first_node_in_group("map")
	var is_single_world = false
	var target_viewport = null
	var map_scale = 0.02
	
	if is_instance_valid(current_map):
		if "sub_viewport" in current_map and is_instance_valid(current_map.sub_viewport):
			is_single_world = true
			target_viewport = current_map.sub_viewport
			if "scale_factor" in current_map:
				map_scale = current_map.scale_factor
				
	set_meta("is_single_world", is_single_world)
	set_meta("map_scale", map_scale)
	
	# 1. Crear el contenedor del Viewport con su propio mundo 3D (Sólo si NO usamos el Lienzo 3D Único)
	var viewport = null
	var res = 256
	if not is_single_world:
		# Resolucion dinamica segun calidad grafica (SettingsManager)
		var quality = 1
		if get_node_or_null("/root/SettingsManager"):
			quality = SettingsManager.get_graphics_quality()
			
		res = 256 # Calidad media por defecto
		if is_in_group("player") or (is_in_group("enemies") and entity_type >= 4):
			res = 512
			
		match quality:
			0: # Baja (Celulares)
				res = 128 if not is_in_group("player") else 256
			1: # Media (Recomendado)
				res = 256 if not is_in_group("player") else 512
			2: # Alta (Gama Alta - Calidad Original Máxima)
				res = 1024
				
		viewport = SubViewport.new()
		viewport.size = Vector2i(res, res)
		viewport.transparent_bg = true
		viewport.own_world_3d = true 
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		
		# OPTIMIZACION MASIVA: Apagar cálculos innecesarios del motor 3D
		viewport.positional_shadow_atlas_size = 0
		if "use_hdr_3d" in viewport: viewport.use_hdr_3d = false
		if "msaa_3d" in viewport: viewport.msaa_3d = Viewport.MSAA_DISABLED
		if "screen_space_aa" in viewport: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		
		add_child(viewport)
		_cached_viewport = viewport # Cache para frustum culling
	else:
		_cached_viewport = null

	# Asegurar que el sprite principal esté en la escena y configurado (Sólo visible si no es Lienzo Único)
	if is_instance_valid(sprite):
		if not sprite.get_parent():
			add_child(sprite)
		sprite.z_index = 10 # BIEN ARRIBA
		sprite.name = "Ship3DRender"
		sprite.visible = not is_single_world
	else:
		sprite = Sprite2D.new()
		sprite.name = "Ship3DRender"
		sprite.z_index = 10
		add_child(sprite)
		sprite.visible = not is_single_world
	
	# 2. Crear la escena 3D interna
	var node3d = Node3D.new()
	if is_single_world:
		target_viewport.add_child(node3d)
	else:
		viewport.add_child(node3d)
	world_root_3d = node3d
	
	# PIVOTE INDEPENDIENTE (Igual que en 2D)
	accessory_pivot_3d = Node3D.new()
	accessory_pivot_3d.name = "AccessoryPivot"
	node3d.add_child(accessory_pivot_3d)
	
	# Entorno con luz AMBIENTE BLANCA (Garantía de visibilidad - Sólo si es Viewport local)
	if not is_single_world:
		var env = WorldEnvironment.new()
		var world_env = Environment.new()
		world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_env.ambient_light_color = Color.WHITE
		world_env.ambient_light_energy = 1.0 
		env.environment = world_env
		node3d.add_child(env)
	
	# Instanciar el modelo GLB
	var model_scene = load(glb_path)
	if model_scene:
		var model = model_scene.instantiate()
		_clean_internal_lights(model)
		
		# CREAMOS UN NODO DE CONTROL (Padre) 
		var control_node = Node3D.new()
		control_node.name = "ShipControl"
		node3d.add_child(control_node)
		control_node.add_child(model)
		
		# v252.23: INSPECTOR Y ACTIVADOR DE ANIMACIONES
		var anim_player_3d = null
		if model.has_node("AnimationPlayer"):
			anim_player_3d = model.get_node("AnimationPlayer")
		else:
			# Búsqueda recursiva simple si no está en la raíz
			for child in model.get_children():
				if child is AnimationPlayer:
					anim_player_3d = child; break
		
		if anim_player_3d:
			var anim_list = anim_player_3d.get_animation_list()
			print("[3D-ANIM] ", entity_type, " tiene ", anim_list.size(), " animaciones: ", anim_list)
			if anim_list.size() > 0:
				var target_anim = anim_list[0]
				# Priorizar nombres comunes
				for a in anim_list:
					var low = a.to_lower()
					if "idle" in low or "fly" in low or "walk" in low or "move" in low:
						target_anim = a; break
				
				anim_player_3d.play(target_anim)
				print("[3D-ANIM] Reproduciendo: ", target_anim, " en ", entity_type)
		
		_3d_model = control_node 
		control_node.scale = Vector3(3.0, 3.0, 3.0) 
		model.rotation_degrees.y = rot_offset 

		# v260.10: Inyectar Escudo de Energía 3D (Procedural)
		_3d_shield_mesh = MeshInstance3D.new()
		_3d_shield_mesh.name = "EnergyShield"
		var sphere = SphereMesh.new()
		sphere.radius = 0.70 # v269.182: Aura más grande y épica
		sphere.height = 1.40
		_3d_shield_mesh.mesh = sphere
		
		var mat = ShaderMaterial.new()
		mat.shader = EnergyShieldShader
		_3d_shield_mesh.material_override = mat
		_3d_shield_mesh.visible = false 
		control_node.add_child(_3d_shield_mesh) # Ahora rota y escala CON la nave
		
		# v380.0: Inyectar partículas de propulsión 3D optimizadas
		_setup_propulsion_particles(control_node)
	
	# 4. Cámara de Perspectiva con ZOOM 50% (Punto 0 - Sólo si es Viewport local)
	if not is_single_world:
		var cam_pivot = Node3D.new()
		node3d.add_child(cam_pivot)
		var cam = Camera3D.new()
		cam_pivot.add_child(cam)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 60.0
		cam.position = Vector3(0, 10, 10) # v238.20: RESTORED FROM 1f65223
		cam.look_at(Vector3.ZERO)
		
		# LUZ FRONTAL (Headlight)
		var sun = DirectionalLight3D.new()
		cam.add_child(sun)
		sun.rotation = Vector3.ZERO 
		sun.light_energy = 2.0 # Volver al original suave
		sun.light_specular = 0.0 # Reducido a 0 para no calcular brillos especulares
		sun.shadow_enabled = false # Desactivar sombras direccionales obligatoriamente
		
		# 5. Conectar al Sprite2D existente (Transparencia Pro)
		if is_instance_valid(sprite):
			sprite.texture = viewport.get_texture()
			# Compensacion: si la resolucion bajó, agrandamos el sprite para mantener el tamaño real
			var scale_factor = 1024.0 / float(res)
			sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.rotation_degrees = 0
		sprite.flip_v = false 
	
	if is_in_group("player") or is_in_group("remote_players"):
		var sm = get_node_or_null("SpheresManager")
		if sm and not sm.spheres_updated.is_connected(_update_3d_spheres):
			sm.spheres_updated.connect(_update_3d_spheres)
		_update_3d_spheres()
	
	# print("[3D] Visualizacion configurada correctamente.")

func _setup_propulsion_particles(parent: Node3D):
	_3d_propulsion = null
	
	var proc_path = "res://assets/VFX/Propulsion/propulsion_material.tres"
	var mesh_path = "res://assets/VFX/Propulsion/propulsion_mesh_material.tres"
	
	if not ResourceLoader.exists(proc_path) or not ResourceLoader.exists(mesh_path):
		return
		
	# 1. Cargar materiales y mallas estáticas de forma segura (Lazy Initialization)
	if not _prop_proc_material:
		_prop_proc_material = load(proc_path)

	if not _prop_material:
		_prop_material = load(mesh_path)

	if not _prop_mesh:
		_prop_mesh = QuadMesh.new()
		_prop_mesh.material = _prop_material
		_prop_mesh.size = Vector2(0.35, 0.35) # Tamaño ideal para la llama difusa

	# 2. Determinar la posición según el modelo de nave
	# Colgado de control_node, la nave apunta a +X, por lo que el escape siempre es -X.
	var offset = Vector3(-0.35, 0.0, 0.0) # Acercado significativamente al asset
	
	if not is_in_group("enemies"):
		match current_ship_id:
			3:
				offset = Vector3(-0.32, 0.0, 0.0)
			4:
				offset = Vector3(-0.35, 0.0, 0.0)
			6:
				offset = Vector3(-0.38, 0.0, 0.0)
			_:
				offset = Vector3(-0.35, 0.0, 0.0)

	# 3. Instanciar el emisor local de partículas de propulsión
	var particles = GPUParticles3D.new()
	particles.name = "ThrusterParticles"
	particles.amount = 60 # Mayor densidad para suavizado de llama de plasma continuo
	particles.lifetime = 0.05 # Más corto y compacto para evitar estela larga
	particles.preprocess = 0.05
	particles.local_coords = false # Rastro estático al moverse
	
	particles.process_material = _prop_proc_material
	particles.draw_pass_1 = _prop_mesh
	
	# Añadir al parent
	parent.add_child(particles)
	_3d_propulsion = particles
	
	# Posición del escape detrás del modelo de la nave
	particles.position = offset
	particles.emitting = false # Inicia apagado hasta que se mueva

func _update_reflect_aura(_delta: float):
	# v260.20: Aura 2D desactivada en favor del sistema de Escudo de Energía 3D
	if _reflect_aura:
		_reflect_aura.visible = false
	return
	
func _on_remote_skill_used(data: Dictionary):
	# v235.38: Filtrar visuales por OBJETIVO (targetId) y no por EMISOR (id)
	# 'targetId' es a quién le llega el efecto. 'id' es quién lo tiró.
	var my_id = entity_id
	var target_id = str(data.get("targetId", ""))
	
	# Si no hay targetId en el paquete, el servidor asume que es un skill de área o auto-target
	# En ese caso comparamos con el 'id' (el emisor)
	var final_match = false
	if target_id != "":
		final_match = (target_id == my_id)
	else:
		final_match = (str(data.get("id")) == my_id)

	if final_match:
		var s_name = str(data.get("skillName", ""))
		if s_name == "REFLECT-Ω" or s_name == "REFLECT":
			reflect_timer = 3.0
			print("[SKILL-SYNC] Activando visual de REFLECT para aliado: ", username)
		elif s_name == "ESCUDO CELULAR" or s_name == "FORTALEZA-X":
			shield_visual_timer = 2.0
			print("[SKILL-SYNC] Activando visual de ESCUDO para aliado: ", username)
		elif s_name == "AUTO-REPARACIÓN" or s_name == "NANO-REGENERACIÓN":
			heal_visual_timer = 2.0
			print("[SKILL-SYNC] Activando visual de CURACION para aliado: ", username)
		elif "SMOKE" in s_name or "BOMBA" in s_name or "VIENTO" in s_name or "WIND" in s_name:
			pass # Ignorar visuales locales para bomba de humo y barrera de viento

		elif s_name == "INVULNERABILIDAD":
			invulnerable_timer = 2.0
			print("[SKILL-SYNC] Activando visual de INVULNERABILIDAD para aliado: ", username)

func _update_3d_shield(delta: float):
	if shield_visual_timer > 0: shield_visual_timer -= delta
	if heal_visual_timer > 0: heal_visual_timer -= delta
	if invulnerable_timer > 0: invulnerable_timer -= delta
	
	if not _3d_shield_mesh: return
	
	# v260.15: Lógica de Visibilidad Híbrida (Reflect, Escudo, Cura o Inmunidad)
	# v306.9: Asegurar que el estado autoritativo 'is_invulnerable' active el visual
	var is_active = shield_visual_timer > 0 or reflect_timer > 0 or heal_visual_timer > 0 or invulnerable_timer > 0 or is_invulnerable == true
	_3d_shield_mesh.visible = is_active
	
	if is_active:
		var mat = _3d_shield_mesh.material_override as ShaderMaterial
		if not mat:
			# Auto-recuperación del material si fue anulado por efectos u otras funciones
			mat = ShaderMaterial.new()
			mat.shader = EnergyShieldShader
			_3d_shield_mesh.material_override = mat
			
		if mat:
			var color = Color(0.1, 0.5, 1.0, 1.0) # Azul (Escudo)
			var is_healing = heal_visual_timer > 0
			
			if reflect_timer > 0: 
				color = Color(1.0, 0.2, 0.1, 1.0) # Rojo (Reflect)
			elif is_healing:
				color = Color(0.1, 1.0, 0.3, 1.0) # Verde (Cura)
			elif invulnerable_timer > 0 or is_invulnerable:
				color = Color(1.0, 0.8, 0.0, 1.0) # Amarillo/Oro (Invulnerabilidad)
			
			mat.set_shader_parameter("color_escudo", color)
			mat.set_shader_parameter("modo_curacion", is_healing)

func _update_3d_spheres():
	var sm = get_node_or_null("SpheresManager")
	if not sm or not accessory_pivot_3d: return
	
	# v235.90: SISTEMA DE CARGA DIRECTA INFALIBLE (Bypass de todo)
	for s in _3d_spheres:
		if is_instance_valid(s): s.queue_free()
	_3d_spheres = [null, null, null, null]
	
	if is_dead: return
	
	for i in range(4):
		var data = sm.spheres_data[i] if i < sm.spheres_data.size() else null
		var skill = data.get("equipped") if data else null
		if not skill: continue
			
		var color_name = "Amarilla"
		var s_type = str(skill.type).to_lower()
		if s_type == "ataque": color_name = "Roja"
		elif s_type == "defensa": color_name = "Azul"
		elif s_type == "curación" or s_type == "curacion": color_name = "Verde"
		
		var s_path = "res://assets/Esferas/3D/Esfera" + color_name + "/Esfera" + color_name + ".glb"
		if ResourceLoader.exists(s_path):
			var s_scene = load(s_path).instantiate()
			_clean_internal_lights(s_scene)
			_setup_sphere_materials_recursive(s_scene, color_name)
			accessory_pivot_3d.add_child(s_scene)
			_3d_spheres[i] = s_scene
			var a = i * (PI/2.0)
			var r = 7.0 
			s_scene.position = Vector3(cos(a)*r, 0, sin(a)*r)
			s_scene.scale = Vector3(3.0, 3.0, 3.0) 
			
			# print("[FIX] Esfera cargada sin luces extra.")
			
	# Re-aplicar estado de invisibilidad visual a las nuevas esferas si corresponde
	_update_invisibility_visuals(_is_currently_invisible, _is_currently_camouflaged)

func _ensure_flash_material():
	if not _hit_flash_material:
		_hit_flash_material = ShaderMaterial.new()
		_hit_flash_material.shader = HitFlashShader
	if not _hit_flash_material_3d:
		_hit_flash_material_3d = StandardMaterial3D.new()
		_hit_flash_material_3d.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		_hit_flash_material_3d.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		_hit_flash_material_3d.albedo_color = Color(1, 1, 1, 0.0)
	if is_instance_valid(sprite) and not is_instance_valid(_3d_model):
		sprite.material = _hit_flash_material
	else:
		if is_instance_valid(sprite): sprite.material = null

var _flash_timer: float = 0.0
func _trigger_hit_flash():
	if get_node_or_null("/root/SettingsManager"):
		if not SettingsManager.hit_flash_enabled: return
		_flash_timer = 0.15
	_ensure_flash_material()
	_update_flash_visuals(1.0)

func _update_hit_flash(delta):
	if _flash_timer > 0:
		_flash_timer -= delta
		var intensity = clamp(_flash_timer / 0.15, 0.0, 1.0)
		_update_flash_visuals(intensity)
		if _flash_timer <= 0:
			_update_flash_visuals(0.0)

func _update_flash_visuals(p_intensity: float):
	if _hit_flash_material: _hit_flash_material.set_shader_parameter("hit_opacity", p_intensity)
	if is_instance_valid(_3d_model) and _hit_flash_material_3d:
		if p_intensity > 0.01:
			_hit_flash_material_3d.albedo_color.a = p_intensity * 0.4
			_apply_flash_recursive(_3d_model, _hit_flash_material_3d)
		elif not is_hovered:
			# v310.6: Limpiar flash solo si no hay outline de selección activo
			_apply_flash_recursive(_3d_model, null)

func _apply_flash_recursive(p_node, p_mat):
	if p_node is MeshInstance3D: p_node.material_overlay = p_mat
	for child in p_node.get_children(): _apply_flash_recursive(child, p_mat)

func _spawn_death_vfx():
	var vfx_script = SpaceExplosionScript
	if not vfx_script: return
	
	var explosion_3d = vfx_script.new()
	var is_single = get_meta("is_single_world", false)
	var current_map = get_tree().get_first_node_in_group("map")
	
	# v311.0: OPTIMIZACIÓN AAA - Instanciación directa en el Lienzo 3D Único del mapa para evitar recrear Viewports/Cámaras
	if is_single and is_instance_valid(current_map) and is_instance_valid(current_map.get("sub_viewport")):
		var s_factor = get_meta("map_scale", 0.02)
		var correction_z = 1.41421356 # Compensación para perspectiva ortogonal inclinada
		
		# Posicionamiento 3D exacto alineado con la posición 2D de la entidad
		explosion_3d.position.x = global_position.x * s_factor
		explosion_3d.position.z = global_position.y * s_factor * correction_z
		explosion_3d.position.y = 0.0
		
		current_map.sub_viewport.add_child(explosion_3d)
	else:
		# Fallback: Modo original con SubViewport local dedicado (usado si no hay lienzo global)
		var wrapper = Node2D.new()
		var spawn_pos = global_position
		
		if is_single and is_instance_valid(world_root_3d) and is_instance_valid(current_map) and is_instance_valid(current_map.get("camera_3d")):
			var cam3d = current_map.camera_3d
			var sub_vp = current_map.get("sub_viewport")
			if not cam3d.is_position_behind(world_root_3d.global_position):
				var sv_pixel = cam3d.unproject_position(world_root_3d.global_position)
				if is_instance_valid(sub_vp) and sub_vp.size.x > 0 and sub_vp.size.y > 0:
					var main_size = Vector2(get_viewport().get_visible_rect().size)
					sv_pixel *= main_size / Vector2(sub_vp.size)
				spawn_pos = get_viewport().get_canvas_transform().affine_inverse() * sv_pixel
		
		wrapper.global_position = spawn_pos
		
		var world = get_tree().get_first_node_in_group("world_node")
		if world: world.add_child(wrapper)
		else: get_parent().add_child(wrapper)
		
		var vp = SubViewport.new()
		vp.size = Vector2i(384, 384)
		vp.transparent_bg = true
		
		# Desactivar características costosas que no necesitamos
		vp.positional_shadow_atlas_size = 0
		if "use_hdr_3d" in vp: vp.use_hdr_3d = false
		
		wrapper.add_child(vp)
		
		var view_3d = Node3D.new()
		vp.add_child(view_3d)
		
		var cam = Camera3D.new()
		cam.position = Vector3(0, 0, 10)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 12.0
		view_3d.add_child(cam)
		
		view_3d.add_child(explosion_3d)
		
		var explosion_sprite = Sprite2D.new()
		explosion_sprite.texture = vp.get_texture()
		wrapper.add_child(explosion_sprite)
		
		get_tree().create_timer(2.0).timeout.connect(wrapper.queue_free)

func _update_collision_size():
	if not _collision_shape or not _collision_shape.shape is CircleShape2D: return

	var base_size = 160.0
	if is_in_group("enemies"):
		if entity_type >= 4: base_size = 320.0
		else: base_size = 160.0

	_collision_shape.shape.radius = base_size * 0.4

func _update_invisibility_visuals(invisible: bool, camouflaged: bool = false):
	_is_currently_invisible = invisible
	_is_currently_camouflaged = camouflaged
	var is_local = is_in_group("player")
	var in_party = false
	var same_clan = false
	
	# v3.5: Verificar si somos del mismo grupo usando PartyManager (basado en nombres)
	var pm = get_node_or_null("/root/PartyManager")
	if pm and pm.current_party and pm.current_party.has("names"):
		var ent_name_upper = username.to_upper()
		for n in pm.current_party["names"]:
			if str(n).to_upper() == ent_name_upper:
				in_party = true
				break
				
	# v3.6: Verificar si somos del mismo clan (SOLO si ambos tienen clan válido)
	var local_player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(local_player):
		var my_tag = local_player.clan_tag.strip_edges()
		var target_tag = clan_tag.strip_edges()
		if my_tag != "" and target_tag != "" and my_tag == target_tag:
			same_clan = true

	_is_ally = (is_local or in_party or same_clan)
	var is_ally = _is_ally

	if invisible or camouflaged:
		
		# Nave: Para aliados transparente (0.3), para el resto invisible (0.0) o camuflado (0.3)
		visible = true
		if invisible:
			modulate = Color(0.5, 0.8, 1.0, 0.3) if is_ally else Color(1, 1, 1, 0)
		else: # camouflaged (se ve como holograma para todos)
			modulate = Color(0.5, 0.8, 1.0, 0.3)
		
		if is_instance_valid(sprite): 
			sprite.visible = (is_ally or camouflaged) if not get_meta("is_single_world", false) else false
			sprite.modulate.a = 0.5 if is_ally else (0.3 if camouflaged else 0.0)
			
		if is_instance_valid(world_root_3d):
			world_root_3d.visible = is_ally or camouflaged
			
		if is_instance_valid(_3d_model):
			if is_ally or camouflaged:
				if not _stealth_material:
					_stealth_material = StandardMaterial3D.new()
					_stealth_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
					_stealth_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					_stealth_material.albedo_color = Color(0.15, 0.65, 0.95, 0.28) # Holograma de sigilo translúcido cian/azul
				_apply_material_recursive(_3d_model, _stealth_material, false)
			else:
				_apply_material_recursive(_3d_model, null, false)
				
		# También para las esferas de soporte 3D
		for s in _3d_spheres:
			if is_instance_valid(s):
				if is_ally or camouflaged:
					if not _stealth_material:
						_stealth_material = StandardMaterial3D.new()
						_stealth_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
						_stealth_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						_stealth_material.albedo_color = Color(0.15, 0.65, 0.95, 0.28)
					_apply_material_recursive(s, _stealth_material, false)
				else:
					_apply_material_recursive(s, null, false)
			
		# HUD y Textos: SOLO para aliados
		if is_instance_valid(name_tag): name_tag.visible = is_ally
		if is_instance_valid(_ui_wrapper): 
			_ui_wrapper.visible = is_ally
			_ui_wrapper.modulate.a = 0.7 if is_ally else 0.0
	else:
		# Estado normal
		visible = true
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		
		var is_single = get_meta("is_single_world", false)
		if is_instance_valid(world_root_3d):
			world_root_3d.visible = true
			
		if is_instance_valid(_3d_model):
			_apply_material_recursive(_3d_model, null, false) # Restaurar material original
			
		# Restaurar material original de esferas
		for s in _3d_spheres:
			if is_instance_valid(s):
				_apply_material_recursive(s, null, false)
			
		if is_instance_valid(sprite): 
			sprite.visible = not is_single
			sprite.modulate.a = 1.0
		if is_instance_valid(name_tag): name_tag.visible = true
		if is_instance_valid(_ui_wrapper): 
			_ui_wrapper.visible = true
			_ui_wrapper.modulate.a = 1.0
func _update_hover_visuals(active: bool):
	if not is_instance_valid(_3d_model): return
	
	if active:
		if not _hover_outline_material:
			_hover_outline_material = StandardMaterial3D.new()
			_hover_outline_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
			_hover_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
			# v302.6: Color más suave y armónico (Cian/Blanco con transparencia)
			_hover_outline_material.albedo_color = Color(0, 1, 1, 0.4) 
			_hover_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_hover_outline_material.grow = true
			_hover_outline_material.grow_amount = 0.03 # Un poco más fino
			_hover_outline_material.render_priority = 10
		_apply_material_recursive(_3d_model, _hover_outline_material, true)
	elif _flash_timer <= 0.01:
		# v308.2: Solo borrar el overlay si NO hay un efecto de daño activo
		_apply_material_recursive(_3d_model, null, true)

func _apply_material_recursive(p_node, p_mat, is_overlay: bool):
	if not is_instance_valid(p_node): return
	if p_node is MeshInstance3D:
		# v311: No interferir con el material de los escudos procedimentales (evita la esfera blanca)
		if p_node.name != "EnergyShield":
			if is_overlay: p_node.material_overlay = p_mat
			else: p_node.material_override = p_mat
	for child in p_node.get_children():
		_apply_material_recursive(child, p_mat, is_overlay)

func _clean_internal_lights(node: Node):
	if not is_instance_valid(node):
		return
	if node is Light3D:
		print("[3D-LIGHT-CLEAN] Eliminando luz interna del modelo: ", node.name)
		node.queue_free()
	for child in node.get_children():
		_clean_internal_lights(child)

func _setup_sphere_materials_recursive(node: Node, color_name: String):
	if not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mat = node.material_override
		if not mat:
			mat = node.get_active_material(0)
		if mat and mat is StandardMaterial3D:
			# Duplicar el material para hacerlo único y que no afecte otros elementos
			mat = mat.duplicate()
			node.material_override = mat
			
			# Habilitar emisión para que brille y no se apague al girar
			mat.emission_enabled = true
			mat.emission_energy_multiplier = 1.0 # Brillo equilibrado
			
			var emit_color = Color.WHITE
			match color_name.to_lower():
				"roja": emit_color = Color(1.0, 0.15, 0.15)
				"azul": emit_color = Color(0.15, 0.4, 1.0)
				"verde": emit_color = Color(0.15, 1.0, 0.15)
				"amarilla": emit_color = Color(1.0, 0.85, 0.15)
				
			mat.emission = emit_color
			if mat.albedo_texture:
				mat.emission_operator = StandardMaterial3D.EMISSION_OP_MULTIPLY
				mat.emission_texture = mat.albedo_texture
	for child in node.get_children():
		_setup_sphere_materials_recursive(child, color_name)

func _exit_tree():
	if is_instance_valid(world_root_3d):
		world_root_3d.queue_free()

func deactivate_for_pooling():
	set_meta("is_pooled", true)
	visible = false
	set_process(false)
	set_physics_process(false)
	if _collision_shape:
		_collision_shape.set_deferred("disabled", true)
	if is_instance_valid(_ui_wrapper):
		_ui_wrapper.visible = false
	if is_instance_valid(world_root_3d):
		world_root_3d.visible = false

func activate_from_pool():
	set_meta("is_pooled", false)
	is_dead = false
	visible = true
	set_process(true)
	set_physics_process(true)
	if _collision_shape:
		_collision_shape.set_deferred("disabled", false)
	if is_instance_valid(_ui_wrapper):
		_ui_wrapper.visible = true
	if is_instance_valid(world_root_3d):
		world_root_3d.visible = true
	rebuild_3d_layout()

# v306.4: Reconstruir visuales 3D al cambiar de mapa para re-ubicarse en el nuevo Viewport global
func rebuild_3d_layout():
	if get_meta("is_pooled", false) == true:
		return
	if is_in_group("enemies"):
		_setup_enemy_visuals()
	else:
		_setup_ship_visuals()

func _spawn_wreckage_marker():
	_clear_wreckage_marker()
	var world = get_tree().get_first_node_in_group("world_node")
	if not is_instance_valid(world) or not is_instance_valid(world.entities_node): return
	
	var marker = Node2D.new()
	marker.name = "Wreckage_" + str(entity_id)
	marker.global_position = global_position
	world.entities_node.add_child(marker)
	
	var drawing = Node2D.new()
	drawing.name = "Visual"
	drawing.set_script(WreckageDrawingScript)
	marker.add_child(drawing)
	
	# v301.5: Mostrar etiqueta del piloto naufragado con transparencia suave
	var label = Label.new()
	var text_val = ""
	if clan_tag.strip_edges() != "":
		text_val = "[" + clan_tag.strip_edges() + "] " + username
	else:
		text_val = username
	label.text = text_val
	label.horizontal_alignment = 1 # HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = 1 # VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.modulate = Color(0.7, 0.7, 0.7, 0.45) # 45% opacidad
	label.position = Vector2(-150, 32)
	label.custom_minimum_size = Vector2(300, 20)
	marker.add_child(label)
	
	# Si es un enemigo, el marcador de naufragio dura solo 10000 ms para evitar polución visual
	if is_in_group("enemies"):
		var tw = marker.create_tween()
		tw.tween_property(marker, "modulate:a", 0.0, 0.2).set_delay(9.8)
		tw.finished.connect(marker.queue_free)

func _clear_wreckage_marker():
	var world = get_tree().get_first_node_in_group("world_node")
	if is_instance_valid(world) and is_instance_valid(world.entities_node):
		var marker = world.entities_node.get_node_or_null("Wreckage_" + str(entity_id))
		if is_instance_valid(marker):
			marker.queue_free()

func _safe_float(val, default: float = 0.0) -> float:
	if val == null:
		return default
	var val_type = typeof(val)
	if val_type == TYPE_INT or val_type == TYPE_FLOAT:
		return float(val)
	elif val_type == TYPE_STRING:
		return val.to_float()
	elif val_type == TYPE_BOOL:
		return 1.0 if val else 0.0
	return default

var _color_aura_node: Line2D = null

func apply_color_aura(color_name: String):
	remove_color_aura()
	
	var clr = Color.WHITE
	match color_name.to_lower():
		"roja": clr = Color("#ff003c")
		"azul": clr = Color("#00aaff")
		"verde": clr = Color("#00ff66")
		"amarilla": clr = Color("#ffdd00")
		"violeta": clr = Color("#d400ff")
		
	var ring = Line2D.new()
	ring.width = 4.0
	ring.default_color = clr
	ring.closed = true
	
	var radius = 70.0
	if entity_type >= 101: # Boss
		radius = 180.0
	elif entity_type == 200 or "pillar" in entity_id: # Pilar
		radius = 100.0
		
	var pts = PackedVector2Array()
	var segments = 32
	for i in range(segments + 1):
		var phi = (i * 2.0 * PI) / segments
		pts.append(Vector2(cos(phi), sin(phi)) * radius)
	ring.points = pts
	
	add_child(ring)
	_color_aura_node = ring
	
	var tween = create_tween().bind_node(ring).set_loops(0)
	tween.tween_property(ring, "modulate:a", 0.3, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(ring, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func remove_color_aura():
	if is_instance_valid(_color_aura_node):
		_color_aura_node.queue_free()
	_color_aura_node = null
