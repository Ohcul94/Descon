extends Node

# VFXSystem.gd (Architecture v164.12 - RE-SAVED)
# Manager central de efectos visuales (Explosiones, Nova, Rifts)

var _warmup_cache: Dictionary = {}
var _vfx_pools: Dictionary = {} # { scene_path: Array[Node] } (v313.6)
var _warmed_materials: Array[Material] = [] # Caché de retención fuerte de materiales (v313.8)
var _loading_refs: Dictionary = {}

var static_textures_to_cache = [
  "res://assets/Esferas/EsferaAmarilla1.png",
  "res://assets/Esferas/EsferaAzul1.png",
  "res://assets/Esferas/EsferaRoja1.png",
  "res://assets/Esferas/EsferaVerde1.png",
  "res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla_EsferaAmarilla_basecolor.jpg",
  "res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla_EsferaAmarilla_normal.jpg",
  "res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla_EsferaAmarilla_rm.jpg",
  "res://assets/Esferas/3D/EsferaAzul/EsferaAzul_EsferaAzul_basecolor.jpg",
  "res://assets/Esferas/3D/EsferaRoja/EsferaRoja_EsferaRoja_basecolor.jpg",
  "res://assets/Esferas/3D/EsferaVerde/EsferaVerde_EsferaVerde_basecolor.jpg",
  "res://assets/Skills/Marco Contenedor.png",
  "res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png",
  "res://assets/Skills/Iconos/Ataque/Provocacion/Provocacion.png",
  "res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png",
  "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
  "res://assets/Skills/Iconos/Cura/Baliza Curativa/Baliza Curativa.png",
  "res://assets/Skills/Iconos/Cura/Regeneracion Alfa/Regeneracion Alfa.png",
  "res://assets/Skills/Iconos/Cura/Vinculo Vital/Vinculo Vital.png",
  "res://assets/Skills/Iconos/Defensa/Barrera de Viento/Barrera de Viento.png",
  "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
  "res://assets/Skills/Iconos/Defensa/Camino de Hielo/Camino de Hielo.png",
  "res://assets/Skills/Iconos/Defensa/Escudo Celular/Escudo Celular.png",
  "res://assets/Skills/Iconos/Utilidad/Destello/Destello.png",
  "res://assets/Skills/Iconos/Utilidad/Invisibilidad/Invisibilidad.png",
  "res://assets/Skills/Iconos/Utilidad/Invulnerabilidad/Invulnerabilidad.png",
  "res://assets/Skills/Iconos/Utilidad/Resurrecion/Resurrecion.png",
  "res://assets/Skills/Iconos/Utilidad/SuperVelocidad/SuperVelocidad.png",
  "res://assets/Talentos/ContenedorGrande.png",
  "res://assets/UI/hand_interact.jpg",
  "res://assets/UI/Chat/Chat(Transp).png",
  "res://assets/UI/Chat/Chat.png",
  "res://assets/UI/Equipo/Equipo(Transp).png",
  "res://assets/UI/Equipo/Equipo.png",
  "res://assets/UI/Habilidades/Habilidades(Transp).png",
  "res://assets/UI/Habilidades/Habilidades.png",
  "res://assets/UI/Minimapa/Minimapa(Transp).png",
  "res://assets/UI/Minimapa/Minimapa.png",
  "res://assets/UI/Perfil/Perfil(Transp).png",
  "res://assets/UI/Perfil/Perfil.png",
  "res://assets/Armas/Arma1/Arma1.png",
  "res://assets/Armas/Arma2/Arma2.png",
  "res://assets/Armas/Arma3/Arma3.png",
  "res://assets/Armas/Arma4/Arma4.png",
  "res://assets/Armas/Arma5/Arma5.png",
  "res://assets/Armas/Arma6/Arma6.png",
  "res://assets/Escudos/Escudo1/Escudo1.png",
  "res://assets/Escudos/Escudo2/Escudo2.png",
  "res://assets/Escudos/Escudo3/Escudo3.png",
  "res://assets/Escudos/Escudo4/Escudo4.png",
  "res://assets/Escudos/Escudo5/Escudo5.png",
  "res://assets/Escudos/Escudo6/Escudo6.png",
  "res://assets/Motores/Motor1/Motor1.png",
  "res://assets/Motores/Motor2/Motor2.png",
  "res://assets/Motores/Motor3/Motor3.png",
  "res://assets/Municiones/Lasers/Laser1/Laser1.png",
  "res://assets/Municiones/Lasers/Laser2/Laser2-1.png",
  "res://assets/Municiones/Lasers/Laser2/Laser2.png",
  "res://assets/Municiones/Minas/Mina1/Mina1.png",
  "res://assets/Municiones/Minas/Mina2/Mina2-1.png",
  "res://assets/Municiones/Minas/Mina2/Mina2.png",
  "res://assets/Municiones/Minas/Mina3/Mina3-1.png",
  "res://assets/Municiones/Minas/Mina3/Mina3.png",
  "res://assets/Municiones/Misiles/Misil1/Misil1.png",
  "res://assets/Municiones/Misiles/Misil2/Misil2-1.png",
  "res://assets/Municiones/Misiles/Misil2/Misil2.png",
  "res://assets/Municiones/Misiles/Misil3/Misil3-1.png",
  "res://assets/Municiones/Misiles/Misil3/Misil3.png",
  "res://assets/Personajes/3D/Nave11/Nave11.glb",
  "res://assets/Personajes/3D/Nave12/Nave12.glb",
  "res://assets/Esferas/3D/EsferaAzul/EsferaAzul.glb",
  "res://assets/Esferas/3D/EsferaRoja/EsferaRoja.glb",
  "res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla.glb",
  "res://VFX/scenes/VFX_Cube_projectile.tscn",
  "res://VFX/scenes/VFX_Hadouken.tscn",
  "res://VFX/scenes/VFX_Hit_hadouken.tscn",
  "res://VFX/scenes/VFX_Hit_cyber.tscn",
  "res://VFX/scenes/VFX_Anticipation_hadouken.tscn",
  "res://VFX/scenes/VFX_Anticipation_wave_digital.tscn",
  "res://VFX/scenes/VFX_Laser_projectile.tscn",
  "res://VFX/scenes/VFX_Laser_Hit.tscn",
  "res://VFX/scenes/VFX_Fire_ball_type_B.tscn",
  "res://VFX/scenes/VFX_Fire_strike.tscn",
  "res://VFX/scenes/VFX_Shield_hex.tscn",
  "res://VFX/scenes/VFX_Shield_demon.tscn",
  "res://VFX/scenes/VFX_Shield_yellow.tscn",
  "res://VFX/scenes/VFX_Hit_Hex_Sphere.tscn",
  "res://VFX/scenes/VFX_Hit_sphere_demon.tscn",
  "res://VFX/scenes/VFX_Hit_sphere_green.tscn",
  "res://VFX/scenes/VFX_Hit_sphere_bbasic.tscn",
  "res://VFX/scenes/VFX_Anticipation_fire_1.tscn",
  "res://VFX/scenes/VFX_Anticipation_fire_3.tscn",
  "res://VFX/scenes/VFX_Anticipation_wave_1.tscn",
  "res://VFX/scenes/VFX_Darkness_projectile.tscn",
  "res://VFX/scenes/VFX_Electric_strike.tscn",
  "res://VFX/scenes/VFX_Fire_ball_standar.tscn",
  "res://VFX/scenes/VFX_Hit_blue_wild.tscn",
  "res://VFX/scenes/VFX_Hit_dark.tscn",
  "res://VFX/scenes/VFX_Hit_electric.tscn",
  "res://VFX/scenes/VFX_Hit_fire_1.tscn",
  "res://VFX/scenes/VFX_Hit_fire_2.tscn",
  "res://VFX/scenes/VFX_Hit_fire_3.tscn",
  "res://VFX/scenes/VFX_Laser_Anticipation.tscn",
  "res://VFX/scenes/VFX_Shield_blue_basic.tscn",
  "res://VFX/scenes/VFX_Shield_blue_w_pyramid.tscn",
  "res://VFX/scenes/VFX_Shield_blue_wild.tscn",
  "res://VFX/scenes/vfx_std_fire_ball.tscn"
]

var static_models_to_cache = [
	"res://assets/Personajes/3D/Nave1/futuristic+jet+3d+model_Clone1.glb",
	"res://assets/Personajes/3D/Nave2/Nave2.glb",
	"res://assets/Personajes/3D/Nave3/Nave3.glb",
	"res://assets/Personajes/3D/Nave4/Nave4.glb",
	"res://assets/Personajes/3D/Nave5/Nave5.glb",
	"res://assets/Personajes/3D/Nave6/Nave6.glb",
	"res://assets/Personajes/3D/Nave7/Nave7.glb",
	"res://assets/Personajes/3D/Nave8/Nave8.glb",
	"res://assets/Personajes/3D/Nave9/Nave9.glb",
	"res://assets/Personajes/3D/Nave10/Nave10.glb",
	"res://assets/Personajes/3D/Nave11/Nave11.glb",
	"res://assets/Personajes/3D/Nave12/Nave12.glb",
	
	"res://assets/Enemigos/3D/Enemigo1/Enemigo1.glb",
	"res://assets/Enemigos/3D/Enemigo2/Enemigo2.glb",
	"res://assets/Enemigos/3D/Enemigo3/Enemigo3.glb",
	"res://assets/Enemigos/3D/Enemigo4/Enemigo4.glb",
	"res://assets/Enemigos/3D/Enemigo5/Enemigo5.glb",
	"res://assets/Enemigos/3D/Enemigo6/Enemigo6.glb",
	"res://assets/Enemigos/3D/Enemigo7/Enemigo7.glb",
	"res://assets/Enemigos/3D/Enemigo8/Enemigo8.glb",
	"res://assets/Enemigos/3D/Enemigo9/Enemigo9.glb",
	"res://assets/Enemigos/3D/Enemigo10/Enemigo10.glb",
	"res://assets/Enemigos/3D/Enemigo11/Enemigo11.glb",
	"res://assets/Enemigos/3D/Enemigo12/Enemigo12.glb",
	"res://assets/Enemigos/3D/Enemigo13/Enemigo13.glb",
	
	"res://assets/Enemigos/3D/Bosses/Boss1/Boss1.glb",
	"res://assets/Enemigos/3D/Bosses/Boss2/Boss2.glb",
	"res://assets/Enemigos/3D/Bosses/Boss3/Boss3.glb",
	"res://assets/Enemigos/3D/Bosses/Boss4/Boss4.glb",
	
	"res://assets/Pilares/3D/Pilar1/Pilar1.glb",
	
	"res://assets/Esferas/3D/EsferaRoja/EsferaRoja.glb",
	"res://assets/Esferas/3D/EsferaAzul/EsferaAzul.glb",
	"res://assets/Esferas/3D/EsferaVerde/EsferaVerde.glb",
	"res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla.glb",
	
	"res://assets/Puertas/3D/Puerta2/Puerta2.glb",
	"res://assets/Contenedores/Baules/3D/Baul1/Baul1.glb",
	"res://assets/Contenedores/Cofres/3D/Cofre1/Cofre1.glb",
	"res://assets/Altares/3D/Altar1/Altar1.glb",
	"res://assets/Paredes/Pared1/Pared1.glb",
	"res://assets/Arenas PVP/3D/Torres/Torre1/Torre1.glb",
	"res://assets/Mapas/Mapa1/Estructuras/3D/Decorativo1/Decorativo1.glb",
	"res://assets/Mapas/Mapa1/Estructuras/3D/Decorativo2/Decorativo2.glb",
	"res://assets/Mapas/Mapa1/Estructuras/3D/Decorativo3/Decorativo3.glb"
]

func _ready():
	add_to_group("vfx_system")
	print("[VFX] Sistema restaurado para compatibilidad de escenas.")
	
	# Iniciar el precalentamiento y caché al arrancar de forma diferida si no está el Bootloader
	var main_scene = ProjectSettings.get_setting("application/run/main_scene")
	if main_scene != "res://scenes/Bootloader.tscn":
		call_deferred("_run_shader_warmup")

func _add_loading_ship(parent: Node3D, path: String, pos: Vector3, s: float):
	if not ResourceLoader.exists(path):
		return
	var glb = load(path)
	if not glb:
		return
	var ship = glb.instantiate()
	if not ship is Node3D:
		ship.queue_free()
		return
	ship.position = pos
	ship.scale = Vector3(s, s, s)
	parent.add_child(ship)
	return ship

func _create_starfield_3d(parent: Node3D):
	var sm = SphereMesh.new()
	sm.radius = 0.015
	sm.height = 0.03
	for i in range(320): # Campo estelar en 360 grados
		var star = MeshInstance3D.new()
		star.mesh = sm
		
		# Dirección esférica aleatoria
		var dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		# Radio exterior aleatorio (entre 12 y 26 unidades)
		var dist = randf_range(12.0, 26.0)
		star.position = dir * dist
		
		var b = randf_range(0.6, 1.0)
		var tint = randf()
		var col: Color
		if tint < 0.15: col = Color(b * 0.8, b * 0.85, b)
		elif tint < 0.3: col = Color(b, b * 0.85, b * 0.7)
		elif tint < 0.45: col = Color(b * 0.7, b * 0.8, b)
		else: col = Color(b, b, b * (0.9 + randf() * 0.1))
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = randf_range(0.8, 3.5)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		star.material_override = mat
		parent.add_child(star)

func _create_nebula_clouds(parent: Node3D):
	var cols = [
		Color(0.4, 0.2, 0.6, 0.08), # Violeta
		Color(0.2, 0.5, 0.8, 0.06), # Azul
		Color(0.6, 0.15, 0.3, 0.05), # Magenta
		Color(0.1, 0.6, 0.4, 0.05)  # Verde esmeralda
	]
	for i in range(4):
		var cloud = MeshInstance3D.new()
		cloud.mesh = SphereMesh.new()
		var r = randf_range(6.0, 9.0)
		cloud.mesh.radius = r
		cloud.mesh.height = r * 2
		
		# Distribuir nebulosas en 360 grados
		var dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.5, 0.5), # Concentradas en el plano de combate
			randf_range(-1.0, 1.0)
		).normalized()
		
		cloud.position = dir * randf_range(8.0, 14.0)
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = cols[i]
		mat.emission_enabled = true
		mat.emission = cols[i]
		mat.emission_energy_multiplier = 0.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cloud.material_override = mat
		parent.add_child(cloud)

func _create_projectile(parent: Node3D, from_pos: Vector3, to_pos: Vector3, color: Color, texture_path: String, is_emp: bool):
	var core_mat = StandardMaterial3D.new()
	core_mat.albedo_color = color
	core_mat.emission_enabled = true
	core_mat.emission = color
	core_mat.emission_energy_multiplier = 5.0

	var aura_mat = StandardMaterial3D.new()
	aura_mat.albedo_color = Color(color.r, color.g, color.b, 0.35)
	aura_mat.emission_enabled = true
	aura_mat.emission = color
	aura_mat.emission_energy_multiplier = 2.5
	aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var trail_mats = []
	for i in range(4):
		var a = 0.5 - i * 0.1
		if a < 0.05: a = 0.05
		var tc = Color(color.r, color.g, color.b, a)
		var tm = StandardMaterial3D.new()
		tm.albedo_color = tc
		tm.emission_enabled = true
		tm.emission = tc
		tm.emission_energy_multiplier = 2.0
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail_mats.append(tm)

	var all_nodes = []
	for i in range(5):
		var m = MeshInstance3D.new()
		if i == 0:
			m.mesh = SphereMesh.new()
			m.mesh.radius = 0.14
			m.mesh.height = 0.28
			m.mesh.surface_set_material(0, core_mat)
		elif i == 1:
			m.mesh = SphereMesh.new()
			m.mesh.radius = 0.35
			m.mesh.height = 0.7
			m.mesh.surface_set_material(0, aura_mat)
		else:
			var ri = i - 2
			var r = 0.08 - ri * 0.015
			if r < 0.02: r = 0.02
			m.mesh = SphereMesh.new()
			m.mesh.radius = r
			m.mesh.height = r * 2
			m.mesh.surface_set_material(0, trail_mats[ri])
		m.position = from_pos
		parent.add_child(m)
		all_nodes.append(m)

	if ResourceLoader.exists(texture_path):
		var spr = Sprite3D.new()
		spr.texture = load(texture_path)
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.scale = Vector3(0.45, 0.45, 0.45)
		spr.position = from_pos
		parent.add_child(spr)
		all_nodes.append(spr)

	var light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 3.0
	light.position = from_pos
	parent.add_child(light)
	all_nodes.append(light)

	if is_emp:
		var fm = StandardMaterial3D.new()
		fm.albedo_color = Color.WHITE
		fm.emission_enabled = true
		fm.emission = Color.WHITE
		fm.emission_energy_multiplier = 6.0
		var flash = MeshInstance3D.new()
		flash.mesh = SphereMesh.new()
		flash.mesh.radius = 0.06
		flash.mesh.height = 0.12
		flash.mesh.surface_set_material(0, fm)
		flash.position = from_pos
		parent.add_child(flash)
		all_nodes.append(flash)
		var fl = create_tween().set_loops()
		fl.tween_property(flash, "scale", Vector3(2.0, 2.0, 2.0), 0.3).set_trans(Tween.TRANS_SINE)
		fl.tween_property(flash, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_SINE)

	var travel = create_tween().set_loops()
	travel.tween_method(func(t):
		var p = from_pos.lerp(to_pos, t)
		for n in all_nodes:
			n.position = p
	, 0.0, 1.0, 1.8).set_trans(Tween.TRANS_LINEAR)
	travel.tween_method(func(_unused):
		var p = from_pos
		for n in all_nodes:
			n.position = p
	, 0.0, 1.0, 0.0)

func _on_login_done(_data = null):
	# Si ya se limpió, salimos
	if _loading_refs.get("viewport_canvas") == null and _loading_refs.get("viewport_display") == null:
		return

	# Desconectar por seguridad si estaban conectadas
	if NetworkManager:
		if NetworkManager.auth_success.is_connected(_on_login_done):
			NetworkManager.auth_success.disconnect(_on_login_done)
		if NetworkManager.has_signal("login_success") and NetworkManager.login_success.is_connected(_on_login_done):
			NetworkManager.login_success.disconnect(_on_login_done)

	var canvas = _loading_refs.get("viewport_canvas")
	var cont = _loading_refs.get("viewport_display")
	var vp = _loading_refs.get("sub_viewport")
	
	if cont and is_instance_valid(cont):
		var fade_tween = cont.create_tween()
		fade_tween.tween_property(cont, "modulate:a", 0.0, 0.4)
		await fade_tween.finished
		
	if canvas and is_instance_valid(canvas):
		canvas.queue_free()
	else:
		if cont and is_instance_valid(cont):
			cont.queue_free()
		if vp and is_instance_valid(vp):
			vp.queue_free()
			
	# Restaurar el Player, HUD, mapa y entidades del juego real
	_set_world_environment_visible(true)
	_loading_refs.clear()

func start_login_cinematic():
	# Ocultar el entorno del juego real (Player, HUD, mapa, enemigos)
	_set_world_environment_visible(false)
	
	# Configurar/reutilizar la cinemática 3D de combate
	_setup_cinematic_3d()
	
	# Asegurarnos de que el viewport 3D sea visible
	var cont = _loading_refs.get("viewport_display")
	if cont and is_instance_valid(cont):
		cont.visible = true
		cont.modulate.a = 1.0
	var canvas = _loading_refs.get("viewport_canvas")
	if canvas and is_instance_valid(canvas):
		canvas.visible = true

	# Mostrar el LoginUI con fade-in
	var login_ui = get_tree().root.find_child("LoginUI", true, false)
	if login_ui:
		# Limpiar texto de estado anterior (ej. "Bienvenido!")
		var status = login_ui.get_node_or_null("Panel/VBoxContainer/ErrorLabel")
		if status:
			status.text = " "
		login_ui.visible = true
		login_ui.modulate.a = 0.0
		var fade = create_tween()
		fade.tween_property(login_ui, "modulate:a", 1.0, 0.4)

	# Conectar señal para cuando el login sea exitoso
	if NetworkManager:
		if not NetworkManager.auth_success.is_connected(_on_login_done):
			NetworkManager.auth_success.connect(_on_login_done, CONNECT_ONE_SHOT)
		if NetworkManager.has_signal("login_success") and not NetworkManager.login_success.is_connected(_on_login_done):
			NetworkManager.login_success.connect(_on_login_done, CONNECT_ONE_SHOT)

func _set_world_environment_visible(value: bool):
	# 1. Jugador Local
	var player = get_tree().root.find_child("Player", true, false)
	if player:
		# Modificar su visibilidad base
		player.visible = value
		
		# Ocultar/mostrar su modelo 3D y UI flotante
		var wr3d = player.get("world_root_3d")
		if wr3d and is_instance_valid(wr3d):
			wr3d.visible = value
		var uiw = player.get("_ui_wrapper")
		if uiw and is_instance_valid(uiw):
			uiw.visible = value
		var spr = player.get("sprite")
		if spr and is_instance_valid(spr):
			spr.visible = value

	# 2. Mapas activos y sus CanvasLayers de renderizado 3D
	for map in get_tree().get_nodes_in_group("map"):
		if is_instance_valid(map):
			map.visible = value
			for child in map.find_children("*", "CanvasLayer", true, false):
				child.visible = value
	var world = get_tree().root.find_child("MainGame", true, false)
	if world and "current_map_node" in world:
		var map = world.current_map_node
		if is_instance_valid(map):
			map.visible = value
			for child in map.find_children("*", "CanvasLayer", true, false):
				child.visible = value

	# 3. MainHUD (HUD de juego real)
	var main_hud = get_tree().root.find_child("MainHUD", true, false)
	if main_hud and is_instance_valid(main_hud):
		main_hud.visible = value

	# 4. Jugadores remotos y enemigos
	for entity in get_tree().get_nodes_in_group("remote_players") + get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(entity):
			entity.visible = value
			var e_wr3d = entity.get("world_root_3d")
			if e_wr3d and is_instance_valid(e_wr3d):
				e_wr3d.visible = value
			var e_uiw = entity.get("_ui_wrapper")
			if e_uiw and is_instance_valid(e_uiw):
				e_uiw.visible = value

func _setup_cinematic_3d():
	# Si ya existe, no creamos de nuevo
	if _loading_refs.has("viewport_canvas") and is_instance_valid(_loading_refs["viewport_canvas"]):
		return
		
	var bg_canvas = CanvasLayer.new()
	bg_canvas.layer = 1
	get_tree().root.add_child(bg_canvas)
	_loading_refs["viewport_canvas"] = bg_canvas

	var vp_container = SubViewportContainer.new()
	vp_container.name = "LoadingViewportContainer"
	vp_container.stretch = true
	vp_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_canvas.add_child(vp_container)
	_loading_refs["viewport_display"] = vp_container

	var sub_vp = SubViewport.new()
	sub_vp.name = "LoadingSubViewport"
	sub_vp.transparent_bg = false
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp_container.add_child(sub_vp)
	_loading_refs["sub_viewport"] = sub_vp

	var scene_3d = Node3D.new()
	scene_3d.name = "LoadingScene3D"
	sub_vp.add_child(scene_3d)
	_loading_refs["scene_3d"] = scene_3d

	var cam = Camera3D.new()
	cam.position = Vector3(0, 0.6, 6.5)
	scene_3d.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, -0.1, 0))

	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 40, 0)
	key.light_energy = 2.5
	key.light_color = Color(0.9, 0.95, 1.0)
	scene_3d.add_child(key)

	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, -160, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.5, 0.6, 1.0)
	scene_3d.add_child(fill)

	# Generar el campo estelar y nebulosas en 360 grados
	_create_starfield_3d(scene_3d)
	_create_nebula_clouds(scene_3d)

	# Instanciar las naves de combate
	var ship1 = _add_loading_ship(scene_3d, "res://assets/Personajes/3D/Nave11/Nave11.glb", Vector3(-2.8, -0.3, -0.5), 0.6)
	var ship2 = _add_loading_ship(scene_3d, "res://assets/Personajes/3D/Nave12/Nave12.glb", Vector3(2.8, 0.3, 0.5), 0.6)
	if ship1: ship1.rotation.y = deg_to_rad(15)
	if ship2: ship2.rotation.y = deg_to_rad(165)

	# Instanciar planetas 3D de fondo giratorios a lo lejos
	var planet1 = _add_loading_ship(scene_3d, "res://assets/Esferas/3D/EsferaAzul/EsferaAzul.glb", Vector3(-6.5, -2.0, -11.0), 1.6)
	var planet2 = _add_loading_ship(scene_3d, "res://assets/Esferas/3D/EsferaRoja/EsferaRoja.glb", Vector3(7.5, 3.0, -13.0), 1.3)
	var planet3 = _add_loading_ship(scene_3d, "res://assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla.glb", Vector3(-4.0, 4.5, -16.0), 0.9)

	# Instanciar el controlador de combate espacial y asignarle los nodos correspondientes
	var combat_script = load("res://scripts/ui/LoadingCombatController.gd")
	var combat_controller = combat_script.new()
	scene_3d.add_child(combat_controller)
	combat_controller.ship1 = ship1
	combat_controller.ship2 = ship2
	combat_controller.camera = cam
	combat_controller.planet1 = planet1
	combat_controller.planet2 = planet2
	combat_controller.planet3 = planet3

func cleanup_cinematic():
	for key in _loading_refs.keys():
		var node = _loading_refs[key]
		if node and is_instance_valid(node):
			node.queue_free()
	_loading_refs.clear()

func reset_for_new_session():
	for key in _loading_refs.keys():
		var node = _loading_refs[key]
		if node and is_instance_valid(node):
			node.queue_free()
	_loading_refs.clear()
	call_deferred("_run_shader_warmup")

func _run_shader_warmup():
	# Ocultar el entorno de juego real al inicio
	_set_world_environment_visible(false)

	var login_ui = get_tree().root.find_child("LoginUI", true, false)
	if login_ui:
		login_ui.visible = false

	# Inicializar la cinemática 3D PRIMERO, para que el fondo esté listo
	_setup_cinematic_3d()
	var cont = _loading_refs.get("viewport_display")
	if cont and is_instance_valid(cont):
		cont.visible = true
	var canv = _loading_refs.get("viewport_canvas")
	if canv and is_instance_valid(canv):
		canv.visible = true

	# Esperar un frame para que el 3D se renderice
	await get_tree().process_frame

	# 1. Crear e instanciar la UI de carga minimalista encima de la cinemática
	var canvas = CanvasLayer.new()
	canvas.layer = 9999
	get_tree().root.add_child(canvas)
	_loading_refs["canvas"] = canvas

	# Fondo oscuro sutil para que contraste la UI, permitiendo ver el combate
	var bg = ColorRect.new()
	bg.color = Color(0.01, 0.01, 0.03, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	_loading_refs["bg"] = bg

	# MarginContainer para ubicar la barra de progreso y estado bien abajo de la pantalla
	var bottom_margin = MarginContainer.new()
	bottom_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_margin.add_theme_constant_override("margin_left", 120)
	bottom_margin.add_theme_constant_override("margin_right", 120)
	bottom_margin.add_theme_constant_override("margin_bottom", 45)
	canvas.add_child(bottom_margin)
	_loading_refs["center"] = bottom_margin

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_margin.add_child(vbox)

	# Label de Estado encima de la barra
	var status = Label.new()
	status.text = "Inicializando sistemas..."
	status.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.8, 0.95, 0.85, 0.85))
	status.add_theme_font_size_override("font_size", 14)
	vbox.add_child(status)

	var sp_space = Control.new()
	sp_space.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(sp_space)

	# ProgressBar delgada y de color verde neón brillante
	var progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 10)
	progress.max_value = 100.0
	progress.value = 0.0
	progress.show_percentage = false
	
	var pb_bg = StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.04, 0.05, 0.09, 0.85)
	pb_bg.border_width_left = 1
	pb_bg.border_width_top = 1
	pb_bg.border_width_right = 1
	pb_bg.border_width_bottom = 1
	pb_bg.border_color = Color(0.2, 0.95, 0.4, 0.2)
	pb_bg.corner_radius_top_left = 5
	pb_bg.corner_radius_top_right = 5
	pb_bg.corner_radius_bottom_left = 5
	pb_bg.corner_radius_bottom_right = 5
	
	var pb_fg = StyleBoxFlat.new()
	pb_fg.bg_color = Color(0.2, 0.95, 0.4, 0.9)
	pb_fg.corner_radius_top_left = 5
	pb_fg.corner_radius_top_right = 5
	pb_fg.corner_radius_bottom_left = 5
	pb_fg.corner_radius_bottom_right = 5
	pb_fg.shadow_color = Color(0.2, 0.95, 0.4, 0.45)
	pb_fg.shadow_size = 4
	
	progress.add_theme_stylebox_override("background", pb_bg)
	progress.add_theme_stylebox_override("fill", pb_fg)
	vbox.add_child(progress)

	await get_tree().process_frame

	# 3. Unificar cola de recursos para la carga en segundo plano multihilo (v313.8)
	var queue = []
	for p in static_textures_to_cache:
		if not queue.has(p): queue.append(p)
	for p in static_models_to_cache:
		if not queue.has(p): queue.append(p)
	
	# Compilar shaders gráficos instanciando efectos fuera de cámara
	var scenes = [
		"res://VFX/scenes/VFX_Shield_green.tscn",
		"res://VFX/scenes/VFX_Shield_green_plane.tscn",
		"res://VFX/scenes/VFX_Cube_projectile.tscn",
		"res://VFX/scenes/VFX_Hadouken.tscn",
		"res://VFX/scenes/VFX_Anticipation_wave_digital.tscn",
		"res://VFX/scenes/VFX_Anticipation_hadouken.tscn",
		"res://VFX/scenes/VFX_Hit_cyber.tscn",
		"res://VFX/scenes/VFX_Hit_hadouken.tscn",
		"res://VFX/scenes/VFX_Laser_projectile.tscn",
		"res://VFX/scenes/VFX_Laser_Hit.tscn",
		"res://VFX/scenes/VFX_Fire_ball_type_B.tscn",
		"res://VFX/scenes/VFX_Fire_strike.tscn",
		"res://VFX/scenes/VFX_Shield_hex.tscn",
		"res://VFX/scenes/VFX_Shield_demon.tscn",
		"res://VFX/scenes/VFX_Shield_yellow.tscn",
		"res://VFX/scenes/VFX_Hit_Hex_Sphere.tscn",
		"res://VFX/scenes/VFX_Hit_sphere_demon.tscn",
		"res://VFX/scenes/VFX_Hit_sphere_green.tscn",
		"res://VFX/scenes/VFX_Hit_sphere_bbasic.tscn",
		"res://VFX/scenes/VFX_Anticipation_fire_1.tscn",
		"res://VFX/scenes/VFX_Anticipation_fire_3.tscn",
		"res://VFX/scenes/VFX_Anticipation_wave_1.tscn",
		"res://VFX/scenes/VFX_Darkness_projectile.tscn",
		"res://VFX/scenes/VFX_Electric_strike.tscn",
		"res://VFX/scenes/VFX_Fire_ball_standar.tscn",
		"res://VFX/scenes/VFX_Hit_blue_wild.tscn",
		"res://VFX/scenes/VFX_Hit_dark.tscn",
		"res://VFX/scenes/VFX_Hit_electric.tscn",
		"res://VFX/scenes/VFX_Hit_fire_1.tscn",
		"res://VFX/scenes/VFX_Hit_fire_2.tscn",
		"res://VFX/scenes/VFX_Hit_fire_3.tscn",
		"res://VFX/scenes/VFX_Laser_Anticipation.tscn",
		"res://VFX/scenes/VFX_Shield_blue_basic.tscn",
		"res://VFX/scenes/VFX_Shield_blue_w_pyramid.tscn",
		"res://VFX/scenes/VFX_Shield_blue_wild.tscn",
		"res://VFX/scenes/vfx_std_fire_ball.tscn",
		"res://scenes/entities/Enemy.tscn",
		"res://scenes/entities/Ship.tscn",
		"res://assets/Contenedores/Baules/3D/Baul1/Baul1.glb"
	]
	
	for p in scenes:
		if not queue.has(p): queue.append(p)

	# Iniciar solicitudes de carga multihilo en segundo plano
	var pending = []
	for path in queue:
		if ResourceLoader.exists(path) and not _warmup_cache.has(path):
			ResourceLoader.load_threaded_request(path)
			pending.append(path)

	# Bucle de espera asíncrono para mantener la cinemática de fondo a 60 FPS estables
	var total_pending = pending.size()
	while pending.size() > 0:
		var i_idx = pending.size() - 1
		while i_idx >= 0:
			if i_idx < pending.size():
				var path = pending[i_idx]
				var progress_arr = []
				var load_status = ResourceLoader.load_threaded_get_status(path, progress_arr)
				
				if load_status == ResourceLoader.THREAD_LOAD_LOADED:
					var res = ResourceLoader.load_threaded_get(path)
					_warmup_cache[path] = res
					pending.remove_at(i_idx)
				elif load_status == ResourceLoader.THREAD_LOAD_FAILED or load_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					pending.remove_at(i_idx)
			i_idx -= 1
			
		var pct = 0.0
		if total_pending > 0:
			pct = (float(total_pending - pending.size()) / total_pending) * 85.0
		progress.value = pct
		status.text = "Cargando recursos del mundo: %d%%" % [int(pct)]
		
		# Esperar al siguiente frame (mantiene cinemática de fondo fluida)
		await get_tree().process_frame

	# 4. Fase de precalentamiento de shaders en GPU (85% a 95%)
	status.text = "Compilando shaders gráficos (GPU)..."
	progress.value = 85.0
	await get_tree().process_frame

	var tn = Node3D.new()
	get_tree().root.add_child(tn)
	var tc = Camera3D.new()
	tc.position = Vector3(999.0, 999.0, 1004.0)
	tn.add_child(tc)
	tc.look_at_from_position(tc.position, Vector3(999.0, 999.0, 999.0))

	var ts = scenes.size()
	var instantiated_nodes = []
	for i in range(ts):
		var sp = scenes[i]
		var s = _warmup_cache.get(sp)
		if s:
			var inst = s.instantiate()
			if inst is Node3D:
				tn.add_child(inst)
				inst.position = Vector3(999.0, 999.0, 999.0)
			elif inst is Node2D:
				get_tree().root.add_child(inst)
				inst.position = Vector2(-9999.0, -9999.0)
			else:
				get_tree().root.add_child(inst)
			
			# Extraer y retener materiales en _warmed_materials para siempre
			_cache_materials_recursive(inst)
			instantiated_nodes.append(inst)
		
		progress.value = 85.0 + (float(i) / ts) * 10.0
		# Amortiguar el lag de GPU instanciando un efecto por frame
		await get_tree().process_frame

	status.text = "Compilando graficos (GPU)..."
	progress.value = 95.0
	await get_tree().physics_frame
	await get_tree().process_frame
	
	# Liberar todos los efectos instanciados
	for inst in instantiated_nodes:
		if is_instance_valid(inst):
			inst.queue_free()

	tn.queue_free()

	status.text = "¡Listo!"
	progress.value = 100.0

	# Desvanecer la UI de carga de forma suave
	var extw = create_tween().set_parallel(true)
	if _loading_refs.has("bg"):
		extw.tween_property(_loading_refs["bg"], "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD)
	if _loading_refs.has("center"):
		extw.tween_property(_loading_refs["center"], "modulate:a", 0.0, 0.5)
	await extw.finished

	if _loading_refs.has("canvas"):
		_loading_refs["canvas"].queue_free()
		_loading_refs.erase("canvas")
		_loading_refs.erase("bg")
		_loading_refs.erase("center")

	if login_ui and is_instance_valid(login_ui):
		login_ui.visible = true
		login_ui.modulate.a = 0.0
		var fade = create_tween()
		fade.tween_property(login_ui, "modulate:a", 1.0, 0.5)

	if NetworkManager:
		if not NetworkManager.auth_success.is_connected(_on_login_done):
			NetworkManager.auth_success.connect(_on_login_done, CONNECT_ONE_SHOT)
		if NetworkManager.has_signal("login_success") and not NetworkManager.login_success.is_connected(_on_login_done):
			NetworkManager.login_success.connect(_on_login_done, CONNECT_ONE_SHOT)

	print("[VFX-WarmUp] Cinematic PvP activa. LoginUI visible sobre naves.")

func spawn_explosion(pos: Vector2, p_scale: float = 1.0): # Renombrado scale a p_scale
	# Efecto visual de explosión por defecto
	print("[VFX] Generando Explosión en ", pos, " (Escala: ", p_scale, ")")
	_create_nova_effect(pos.x, pos.y, p_scale * 100.0)

# v3.1: Generador de efectos rápidos (Teletransporte, impactos, etc)
func create_simple_vfx(pos: Vector2, type: String = "warp_exit", radius: float = 50.0):
	match type:
		"warp_exit", "warp_entry":
			_create_nova_effect(pos.x, pos.y, radius)
		_:
			_create_nova_effect(pos.x, pos.y, radius)

func handle_boss_effect(data: Dictionary):
	var type = data.get("type", "")
	var p_x = data.get("x", 0.0)
	var p_y = data.get("y", 0.0)
	
	match type:
		"vacuum":
			_create_nova_effect(p_x, p_y, data.get("radius", 1200))
		"rift":
			_create_void_rift_effect(p_x, p_y, data.get("duration", 4000) / 1000.0)
		"leech":
			var from_pos = Vector2(p_x, p_y)
			var to_id = str(data.get("to", ""))
			var to_node = null
			
			var entities = get_tree().get_nodes_in_group("entities")
			for entity in entities:
				if is_instance_valid(entity) and entity.get("entity_id") == to_id:
					to_node = entity
					break
			if not to_node:
				var pl = get_tree().get_first_node_in_group("player")
				if is_instance_valid(pl) and pl.get("entity_id") == to_id:
					to_node = pl
			
			var to_pos = to_node.global_position if is_instance_valid(to_node) else from_pos
			_create_leech_ray_vfx(from_pos, to_pos, to_node)

func _create_leech_ray_vfx(from_pos: Vector2, to_pos: Vector2, target_node: Node2D):
	# Rayo curativo verde de pilares (39ff14 -> Verde Eléctrico)
	var rayo = Line2D.new()
	rayo.width = 4.0
	rayo.default_color = Color("#39ff14")
	rayo.points = PackedVector2Array([from_pos, to_pos])
	
	var world = get_tree().get_first_node_in_group("world")
	if world: world.add_child(rayo)
	else: get_tree().root.add_child(rayo)
	
	var duration = 0.8
	var tween = create_tween().set_parallel(true)
	
	# Desvanecer ancho y color
	tween.tween_property(rayo, "width", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(rayo, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	if is_instance_valid(target_node):
		var steps = 15
		for i in range(steps):
			var t = (i / float(steps)) * duration
			tween.tween_callback(func():
				if is_instance_valid(rayo) and is_instance_valid(target_node):
					rayo.points = PackedVector2Array([from_pos, target_node.global_position])
			).set_delay(t)
			
	tween.chain().tween_callback(rayo.queue_free)

func _create_nova_effect(p_x: float, p_y: float, radius: float):
	# Anillo de energía expansiva (bc13fe -> Violeta Neón)
	var ring = Line2D.new()
	ring.width = 6.0
	ring.default_color = Color("#bc13fe")
	ring.closed = true
	
	var pts = PackedVector2Array()
	var segments = 32
	for i in range(segments + 1):
		var phi = (i * 2.0 * PI) / segments
		pts.append(Vector2(cos(phi), sin(phi)) * 10.0)
	ring.points = pts
	
	ring.global_position = Vector2(p_x, p_y)
	
	# v240.71: Buscar el nodo World para que el efecto no se desplace con la camara
	var world = get_tree().get_first_node_in_group("world")
	if world: world.add_child(ring)
	else: get_tree().root.add_child(ring)
	
	var tween = create_tween().set_parallel(true)
	var duration = 1.5
	var final_scale = radius / 10.0
	
	tween.tween_property(ring, "scale", Vector2(final_scale, final_scale), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)
	
	_apply_nova_push(Vector2(p_x, p_y), radius)

func _create_void_rift_effect(p_x: float, p_y: float, duration: float):
	var rift = Polygon2D.new()
	var pts = PackedVector2Array()
	var segments = 16
	for i in range(segments):
		var phi = (i * 2.0 * PI) / segments
		pts.append(Vector2(cos(phi), sin(phi)) * 80.0)
	rift.polygon = pts
	rift.color = Color("#bc13fe")
	rift.modulate.a = 0.2
	
	rift.global_position = Vector2(p_x, p_y)
	var world = get_tree().get_first_node_in_group("world")
	if world: world.add_child(rift)
	else: get_tree().root.add_child(rift)
	
	var tween = create_tween().set_loops()
	tween.bind_node(rift)
	tween.tween_property(rift, "scale", Vector2(1.2, 1.2), 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(rift, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE)
	
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(rift):
		rift.queue_free()

func _apply_nova_push(pos: Vector2, radius: float):
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p):
		var dist = p.global_position.distance_to(pos)
		if dist < radius:
			var direction = (p.global_position - pos).normalized()
			if "velocity" in p:
				p.velocity += direction * 800.0


# ==========================================
# SISTEMA DE CACHÉ DE RECURSOS Y OBJECT POOLING (v313.6)
# ==========================================

# Recuperar recursos cargados durante el warmup o cargarlos bajo demanda y guardarlos
func get_cached_resource(path: String) -> Resource:
	if _warmup_cache.has(path):
		return _warmup_cache[path]
	if ResourceLoader.exists(path):
		var res = load(path)
		_warmup_cache[path] = res
		return res
	return null

# Obtener una instancia del pool para evitar instantiate() en combate
func get_vfx_from_pool(scene_source) -> Node:
	var path = ""
	var scene = null
	
	if typeof(scene_source) == TYPE_STRING:
		path = scene_source
	elif scene_source is PackedScene:
		path = scene_source.resource_path
		scene = scene_source
		
	if path == "":
		return null
		
	if not _vfx_pools.has(path):
		_vfx_pools[path] = []
		
	var pool = _vfx_pools[path]
	while pool.size() > 0:
		var inst = pool.pop_back()
		if is_instance_valid(inst):
			_reset_vfx_node(inst)
			return inst
			
	# Si no hay en el pool, instanciar
	if not scene:
		scene = get_cached_resource(path)
	
	if scene:
		var inst = scene.instantiate()
		inst.set_meta("pool_scene_path", path)
		return inst
		
	return null

# Devolver una instancia al pool en lugar de queue_free()
func recycle_vfx_to_pool(vfx_node: Node):
	if not is_instance_valid(vfx_node):
		return
		
	var path = vfx_node.get_meta("pool_scene_path", "")
	if path == "":
		# Fallback si no proviene del pooler
		vfx_node.queue_free()
		return
		
	# Remover del padre para dejarlo inactivo y libre
	if vfx_node.get_parent():
		vfx_node.get_parent().remove_child(vfx_node)
		
	if not _vfx_pools.has(path):
		_vfx_pools[path] = []
		
	# Evitar duplicar referencias del mismo objeto en el pool (v313.9)
	if not _vfx_pools[path].has(vfx_node):
		_vfx_pools[path].append(vfx_node)

# Resetear el estado del nodo del pooler recursivamente (partículas y animaciones)
func _reset_vfx_node(node: Node):
	if node is GPUParticles3D or node is CPUParticles3D or node is GPUParticles2D or node is CPUParticles2D:
		node.emitting = false
		node.restart()
		node.emitting = true
	elif node is AnimationPlayer:
		node.stop()
		node.play()
		
	for child in node.get_children():
		_reset_vfx_node(child)

# Extraer y retener fuerte referencia de materiales para evitar que la GPU descarte shaders compilados (v313.8)
func _cache_materials_recursive(node: Node):
	if not is_instance_valid(node):
		return
		
	if node is MeshInstance3D:
		if node.material_override:
			_warmed_materials.append(node.material_override)
		for idx in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(idx)
			if mat:
				_warmed_materials.append(mat)
		if node.mesh:
			for idx in range(node.mesh.get_surface_count()):
				var mat = node.mesh.surface_get_material(idx)
				if mat:
					_warmed_materials.append(mat)
	elif node is GPUParticles3D or node is CPUParticles3D:
		if node.material_override:
			_warmed_materials.append(node.material_override)
		if "draw_pass_1" in node and node.draw_pass_1 and "material" in node.draw_pass_1 and node.draw_pass_1.material:
			_warmed_materials.append(node.draw_pass_1.material)
		if "process_material" in node and node.process_material and node.process_material is Material:
			_warmed_materials.append(node.process_material)
	elif node is Sprite3D or node is Sprite2D:
		if "material" in node and node.material:
			_warmed_materials.append(node.material)
			
	for child in node.get_children():
		_cache_materials_recursive(child)
