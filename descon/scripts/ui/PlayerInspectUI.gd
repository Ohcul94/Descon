extends Control

# ==============================================================================
# PlayerInspectUI.gd - Módulo de Inspección de Objetivo (Atajo: 'Y')
# ==============================================================================
# - Permite inspeccionar a cualquier objetivo seleccionado (Pilotos, Jefes y Enemigos).
# - Modo PILOTO: Equipamiento y habilidades equipadas de cualquier jugador objetivo
#   (aliado o enemigo). No permite auto-inspección.
# - Modo JEFE / ENEMIGO: Estadísticas completas de combate (HP, Escudo, Daño, Rango,
#   Velocidad, Recompensas) y desglose dinámico de todas sus mecánicas (ofensivas,
#   defensivas y movimiento) sincronizadas en tiempo real con el Admin Dashboard.
# - Estética Sci-Fi unificada con el resto de módulos del juego.
# ==============================================================================

const ItemInfoHelper = preload("res://scripts/ui/inventory/ItemInfoHelper.gd")

enum Mode { NONE, HINT, PLAYER, ENEMY }

var current_mode: int = Mode.NONE
var is_open: bool = false
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

var window_panel: PanelContainer = null
var header_bar: Control = null
var icon_title: Label = null
var pilot_title_label: Label = null

var target_node: Node = null
var target_player_node: Node = null
var inspected_data: Dictionary = {}

# Contenedores UI por Modo
var player_view: VBoxContainer = null
var enemy_view: VBoxContainer = null
var hint_panel: PanelContainer = null
var hint_label: Label = null

# Componentes Modo Piloto
var ship_info_label: Label = null
var clan_info_label: Label = null
var hp_bar: ProgressBar = null
var hp_label: Label = null
var shield_bar: ProgressBar = null
var shield_label: Label = null
var skills_container: HBoxContainer = null
var equip_container: HBoxContainer = null

# Componentes Modo Jefe / Enemigo
var enemy_avatar_rect: TextureRect = null
var _enemy_viewport_container: SubViewportContainer = null
var _enemy_viewport: SubViewport = null
var _enemy_preview_root: Node3D = null
var _enemy_preview_cam: Camera3D = null
var _enemy_model_holder: Node3D = null
var _last_previewed_glb: String = ""

var enemy_name_label: Label = null
var enemy_badge_category: Label = null
var enemy_badge_category_panel: PanelContainer = null
var enemy_badge_id: Label = null
var enemy_badge_id_panel: PanelContainer = null
var enemy_badge_rage: Label = null
var enemy_badge_rage_panel: PanelContainer = null
var enemy_hp_bar: ProgressBar = null
var enemy_hp_label: Label = null
var enemy_shield_bar: ProgressBar = null
var enemy_shield_label: Label = null
var enemy_behavior_panel: PanelContainer = null
var enemy_behavior_flow_tactics: HFlowContainer = null
var enemy_behavior_flow_regen: HFlowContainer = null
var enemy_rewards_panel: PanelContainer = null
var enemy_rewards_flow: HFlowContainer = null
var enemy_mechanics_count_label: Label = null
var mechanics_cards_container: VBoxContainer = null

# Rutas de iconos de habilidades de jugador
var _skill_icons: Dictionary = {
	"BLINK": "res://assets/Skills/Iconos/Utilidad/Destello/Destello.png",
	"DESTELLO": "res://assets/Skills/Iconos/Utilidad/Destello/Destello.png",
	"TURBO-IMPULSO": "res://assets/Skills/Iconos/Utilidad/Turbo Impulso/Turbo Impulso.png",
	"TURBO IMPULSO": "res://assets/Skills/Iconos/Utilidad/Turbo Impulso/Turbo Impulso.png",
	"HYPER-DASH": "res://assets/Skills/Iconos/Utilidad/HyperDash/HyperDash.png",
	"HYPERDASH": "res://assets/Skills/Iconos/Utilidad/HyperDash/HyperDash.png",
	"INVULNERABILIDAD": "res://assets/Skills/Iconos/Utilidad/Invulnerabilidad/Invulnerabilidad.png",
	"STEALTH": "res://assets/Skills/Iconos/Utilidad/Invisibilidad/Invisibilidad.png",
	"INVISIBILIDAD": "res://assets/Skills/Iconos/Utilidad/Invisibilidad/Invisibilidad.png",
	"RESURRECCION": "res://assets/Skills/Iconos/Utilidad/Resurrecion/Resurrecion.png",
	"RESURRECCIÓN": "res://assets/Skills/Iconos/Utilidad/Resurrecion/Resurrecion.png",
	"REFLECT-OMEGA": "res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png",
	"REFLECT": "res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png",
	"ESFERA DE TERROR": "res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png",
	"MIEDO": "res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png",
	"PROVOCACION": "res://assets/Skills/Iconos/Ataque/Provocacion/Provocacion.png",
	"PROVOCACIÓN": "res://assets/Skills/Iconos/Ataque/Provocacion/Provocacion.png",
	"HOOKSHOT": "res://assets/Skills/Iconos/Ataque/Hookshot/Hookshot.png",
	"VINCULO VITAL": "res://assets/Skills/Iconos/Cura/Vinculo Vital/Vinculo Vital.png",
	"VÍNCULO VITAL": "res://assets/Skills/Iconos/Cura/Vinculo Vital/Vinculo Vital.png",
	"REGENERACION ALFA": "res://assets/Skills/Iconos/Cura/Regeneracion Alfa/Regeneracion Alfa.png",
	"REGENERACIÓN ALFA": "res://assets/Skills/Iconos/Cura/Regeneracion Alfa/Regeneracion Alfa.png",
	"BALIZA DE CURACION": "res://assets/Skills/Iconos/Cura/Baliza Curativa/Baliza Curativa.png",
	"BALIZA DE CURACIÓN": "res://assets/Skills/Iconos/Cura/Baliza Curativa/Baliza Curativa.png",
	"AUTO-REPARACION": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"AUTO-REPARACIÓN": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"NANO-REGENERACION": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"NANO-REGENERACIÓN": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"ESCUDO CELULAR": "res://assets/Skills/Iconos/Defensa/Escudo Celular/Escudo Celular.png",
	"SMOKE-BOMB": "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
	"BOMBA DE HUMO": "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
	"FROST-TRAIL": "res://assets/Skills/Iconos/Defensa/Camino de Hielo/Camino de Hielo.png",
	"CAMINO DE HIELO": "res://assets/Skills/Iconos/Defensa/Camino de Hielo/Camino de Hielo.png",
	"BARRERA DE VIENTO": "res://assets/Skills/Iconos/Defensa/Barrera de Viento/Barrera de Viento.png",
	"DIMENSION EXTRAÑA": "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
	"DIMENSIÓN EXTRAÑA": "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png"
}

# Librerías de fallback para mecánicas de enemigos (siempre disponible aunque haya lag de red)
var _default_mechanics_lib: Dictionary = {
	"laser": { "label": "Láser Estándar", "icon": "🔫", "desc": "Ataque lineal básico de proyectiles de energía." },
	"missile": { "label": "Misil Rastreador", "icon": "🚀", "desc": "Proyectil autoguiado que persigue al objetivo." },
	"ice_missile": { "label": "Misil de Hielo", "icon": "❄️", "desc": "Proyectil gélido que impacta y ralentiza drásticamente al objetivo." },
	"mine": { "label": "Mina de Proximidad", "icon": "💣", "desc": "Explosivo estático que detona al acercarse una nave enemiga." },
	"orbital_strike": { "label": "Ataque Orbital", "icon": "🌀", "desc": "Círculos giratorios concentrados que luego se disparan en ráfaga." },
	"aura_damage": { "label": "Aura de Vacío", "icon": "🔥", "desc": "Genera un área hostil persistente que inflige daño continuo a objetivos cercanos." },
	"hook": { "label": "Gancho Abisal", "icon": "⚓", "desc": "Dispara un anclaje que engancha al objetivo, lo atrae hacia el enemigo y lo inmoviliza." },
	"cone_cast": { "label": "Ataque en Cono Casteable", "icon": "📐", "desc": "Carga un ataque devastador en forma de cono y, al completarse, daña y aturde a todos los objetivos en el área." },
	"bomb": { "label": "Lanzador de Bombas", "icon": "💣", "desc": "Lanza bombas en círculo que detonan tras un retardo con daño expansivo." },
	"circle_cast": { "label": "Explosión Circular", "icon": "⭕", "desc": "Carga un área circular centrada en el enemigo y detona infligiendo daño masivo." },
	"sleep": { "label": "Sueño Inducido", "icon": "💤", "desc": "Aplica somnolencia progresiva hasta dormir a los pilotos. Despertar prematuramente provoca pesadilla con daño crítico." },
	"reflect": { "label": "Escudo Reflectante", "icon": "🛡️", "desc": "Crea una barrera refractaria que devuelve el daño directo recibido hacia el agresor." },
	"spin_ring": { "label": "Giro de Lillia", "icon": "🌀", "desc": "Un orbe gira a gran velocidad alrededor del enemigo. Inflige daño, ralentiza y aumenta la velocidad del lanzador." },
	"summoning": { "label": "Invocación de Esbirros", "icon": "🧟", "desc": "Invoca refuerzos alienígenas para abrumar a los invasores durante el combate." },
	"survival_dome": { "label": "Domo de Supervivencia", "icon": "🔮", "desc": "Carga un cataclismo masivo creando un domo seguro aleatorio. Permanecer fuera del domo inflige daño aniquilador." },
	"ice_storm": { "label": "Tormenta de Hielo", "icon": "❄️", "desc": "Invoca una tormenta de hielo persistente que congela, ralentiza y daña continuamente." },
	"worm_boomerang": { "label": "Gusanos Bumerán", "icon": "🪱", "desc": "Lanza un abanico de parásitos bumerán que avanzan dañando y regresan al origen duplicando el castigo." },
	"wind_wall": { "label": "Aluvión de Viento", "icon": "🌪️", "desc": "Carga y expulsa un vendaval violento que empuja a las naves fuera de curso con daño de impacto." },
	"burrow": { "label": "Zambullida Telúrica", "icon": "🕳️", "desc": "El enemigo se sumerge bajo tierra volviéndose inalcanzable, viaja velozmente hacia su objetivo y emerge rompiendo el terreno con daño en área." },
	"polymorph": { "label": "Polimorfia", "icon": "🗺️", "desc": "Dispara proyectiles cúbicos transmutadores que transforman la nave del jugador, limitando su movilidad y uso de armas." },
	"meteor": { "label": "Lluvia de Meteoritos", "icon": "☄️", "desc": "Convoca una lluvia de meteoritos incendiarios desde el firmamento con avisos en el suelo y zonas persistentes de fuego." },
	"execution": { "label": "Ejecución Directa", "icon": "💀", "desc": "Canaliza una calavera cósmica letal inquebrantable. Al alcanzar su objetivo, inflige muerte instantánea ignorando escudos." },
	"ascension": { "label": "Ascensión Telúrica", "icon": "🎈", "desc": "El enemigo se eleva por los cielos canalizando y desciende violentamente sobre su presa con daño de impacto telúrico." },
	"melee_slash": { "label": "Hachazo Melee", "icon": "🪓", "desc": "Corte cuerpo a cuerpo instantáneo de gran calibre con anticipación de impacto frontal o circular." },
	"mega_laser": { "label": "Mega Láser", "icon": "🔥", "desc": "Canaliza un rayo de energía concentrada de gran espesor y alcance que perfora cualquier defensa." },
	"choque_devastador": { "label": "Choque Devastador", "icon": "💥", "desc": "El enemigo carga en línea recta a máxima velocidad embistiendo y dañando a todo lo que cruza su trayectoria." },
	"fireball": { "label": "Bola de Fuego Dinámica", "icon": "☀️", "desc": "Invoca una esfera solar ardiente que deambula por el sector, dañando por ticks y atrayendo naves mediante fuerza gravitatoria." },
	"whip_summon": { "label": "Látigo Dominante", "icon": "🪢", "desc": "Canaliza un látigo místico que azota consecutivamente a su víctima a un ritmo implacable." },
	"strange_dimension": { "label": "Dimensión Extraña", "icon": "🌌", "desc": "Abre una brecha dimensional que arrastra a los objetivos a una dimensión paralela aislada durante unos segundos." },
	"enraizada": { "label": "Enraizada", "icon": "🌱", "desc": "Brotan raíces vivientes del subsuelo que apresan a la nave, inmovilizándola e infligiendo daño constante por constricción." }
}

var _default_defense_lib: Dictionary = {
	"aura_heal": { "label": "Aura Curativa", "icon": "✨", "desc": "Restaura salud progresivamente al enemigo y a todas las unidades aliadas dentro de su radio." },
	"invulnerability": { "label": "Invulnerabilidad Temporal", "icon": "💎", "desc": "Activa un escudo inexpugnable que neutraliza completamente todo daño entrante durante su duración." },
	"invisibility": { "label": "Invisibilidad / Camuflaje", "icon": "👤", "desc": "Activa sigilo óptico haciéndose indetectable a los radares y sensores visuales." },
	"boss_pillars": { "label": "Pilares del Boss", "icon": "🗼", "desc": "Genera pilares de energía protectores que desvían daño y curan al jefe mientras continúen en pie." },
	"boss_colors": { "label": "Mecánica de Colores", "icon": "🎨", "desc": "Sincroniza frecuencias cromáticas: solo los pilotos que coincidan con la tonalidad activa del jefe pueden dañarlo." },
	"boss_water_orbs": { "label": "Orbes de Agua", "icon": "💧", "desc": "Invoca esferas hidrodinámicas que viajan hacia el jefe para regenerar su vitalidad a menos que sean interceptadas." },
	"duplicado": { "label": "Duplicación Defensiva", "icon": "👥", "desc": "Se divide en réplicas ilusorias que persiguen a los atacantes y detonan al expirar restaurando vida al líder." },
	"wall_dome": { "label": "Muro de Energía", "icon": "🌐", "desc": "Despliega una cúpula electromagnética impermeable que bloquea todos los proyectiles externos." },
	"reflect": { "label": "Escudo Reflectante", "icon": "🛡️", "desc": "Genera un campo reflectante que redirige el daño absorbido contra los tiradores." },
	"shield_steal": { "label": "Robador de Escudo", "icon": "💠", "desc": "Dispara un zarcillo electromagnético que drena el escudo del piloto y lo transfiere directamente a la nave enemiga." },
	"life_steal": { "label": "Robador de Vida", "icon": "💚", "desc": "Vínculo vampírico que absorbe la integridad del casco de la nave impactada para curar al agresor." },
	"strange_dimension": { "label": "Escape a Dimensión Extraña", "icon": "🌌", "desc": "Se transporta de emergencia a un plano paralelo para evitar ser aniquilado." },
	"sobrecarga": { "label": "Sobrecarga Curativa", "icon": "⚡", "desc": "Acumula energía reactor y detona una onda expansiva verde que repara a sus aliados y opcionalmente daña a los enemigos." }
}

var _default_movement_lib: Dictionary = {
	"sniper": { "label": "Francotirador", "icon": "🎯", "desc": "Mantiene distancia segura alejándose metódicamente del agresor para disparar con ventaja de alcance." },
	"chase": { "label": "Persecución Directa", "icon": "🏃", "desc": "Acelera en persecución frontal constante hasta alcanzar la distancia óptima de combate." },
	"orbit": { "label": "Órbita Circular", "icon": "🔄", "desc": "Realiza maniobras evasivas orbitales girando constantemente alrededor del blanco." },
	"charger": { "label": "Embestida Táctica", "icon": "⚡", "desc": "Reduce la distancia y ejecuta embestidas de alta aceleración." },
	"zigzag": { "label": "Movimiento ZigZag", "icon": "↩️", "desc": "Avanza en patrones ondulantes para dificultar la puntería de los cañones del jugador." },
	"kamikaze": { "label": "Kamikaze Desesperado", "icon": "💣", "desc": "Al verse acorralado con baja vida, se lanza a máxima propulsión en trayectoria suicida para detonar." },
	"prowler": { "label": "Merodeador", "icon": "🐾", "desc": "Patrulla autónoma e impredecible por el sector hasta detectar un objetivo viable." },
	"aura_speed": { "label": "Aura de Impulso", "icon": "🌬️", "desc": "Aumenta la velocidad de desplazamiento propia y de su escuadrón." },
	"boss": { "label": "Cerebro de Jefe", "icon": "💀", "desc": "Maneja múltiples fases tácticas de combate coordinando ataques, defensas y posicionamiento." },
	"altar_rush": { "label": "Asalto al Altar", "icon": "⛩️", "desc": "Avanza inexorablemente hacia el objetivo prioritario o altar sin desviarse." },
	"nearest_target": { "label": "Radar de Proximidad", "icon": "👁️", "desc": "Escanea el sector y focaliza su hostilidad en la presa más cercana disponible." }
}


func _ready():
	add_to_group("player_inspect_ui")
	add_to_group("inspect_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_build_ui_structure()
	_connect_signals()


func _connect_signals():
	if NetworkManager:
		if NetworkManager.has_signal("player_inspect_data"):
			if not NetworkManager.player_inspect_data.is_connected(_on_server_inspect_data):
				NetworkManager.player_inspect_data.connect(_on_server_inspect_data)
		if NetworkManager.has_signal("config_updated"):
			if not NetworkManager.config_updated.is_connected(_on_server_config_updated):
				NetworkManager.config_updated.connect(_on_server_config_updated)
		if NetworkManager.has_signal("admin_config_updated"):
			if not NetworkManager.admin_config_updated.is_connected(_on_server_config_updated):
				NetworkManager.admin_config_updated.connect(_on_server_config_updated)


func _on_server_config_updated(_cfg: Dictionary = {}):
	if not is_open: return
	if is_instance_valid(target_node) and current_mode == Mode.ENEMY:
		# Recarga dinámica inmediata de mecánicas modificadas en Admin Dashboard
		_open_with_enemy_target(target_node)


func _build_ui_structure():
	var blocker = Control.new()
	blocker.name = "ClickBlocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blocker)

	# Ventana flotante principal con estilo unificado cian espacial
	window_panel = PanelContainer.new()
	window_panel.name = "InspectWindow"
	window_panel.custom_minimum_size = Vector2(660, 580)
	window_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	window_panel.gui_input.connect(_on_header_gui_input)

	var sb_win = StyleBoxFlat.new()
	sb_win.bg_color = Color(0.012, 0.022, 0.038, 0.98)
	sb_win.border_width_left = 2; sb_win.border_width_top = 2
	sb_win.border_width_right = 2; sb_win.border_width_bottom = 2
	sb_win.border_color = Color(0.0, 0.85, 1.0, 0.8) # Borde cian espacial
	sb_win.set_corner_radius_all(8)
	sb_win.corner_detail = 12
	sb_win.anti_aliasing = true
	sb_win.shadow_color = Color(0, 0, 0, 0.45)
	sb_win.shadow_size = 12
	window_panel.add_theme_stylebox_override("panel", sb_win)
	add_child(window_panel)

	_reposition_window()

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	window_panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)

	# 1. Overlay superior para botón de Cierre integrado en la esquina del modal
	var top_overlay = Control.new()
	top_overlay.name = "TopOverlay"
	top_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window_panel.add_child(top_overlay)

	var btn_close = Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(28, 24)
	btn_close.add_theme_font_size_override("font_size", 12)
	btn_close.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	var sb_close = StyleBoxFlat.new()
	sb_close.bg_color = Color(0.22, 0.05, 0.08, 0.85)
	sb_close.border_width_left = 1; sb_close.border_width_top = 1
	sb_close.border_width_right = 1; sb_close.border_width_bottom = 1
	sb_close.border_color = Color(0.9, 0.25, 0.25, 0.6)
	sb_close.set_corner_radius_all(4)
	btn_close.add_theme_stylebox_override("normal", sb_close)
	var sb_close_h = sb_close.duplicate()
	sb_close_h.bg_color = Color(0.38, 0.08, 0.12, 0.95)
	sb_close_h.border_color = Color(1.0, 0.4, 0.4, 0.9)
	btn_close.add_theme_stylebox_override("hover", sb_close_h)
	btn_close.anchor_left = 1.0; btn_close.anchor_right = 1.0
	btn_close.anchor_top = 0.0; btn_close.anchor_bottom = 0.0
	btn_close.offset_left = -38; btn_close.offset_right = -10
	btn_close.offset_top = 10; btn_close.offset_bottom = 34
	btn_close.z_index = 20
	btn_close.pressed.connect(close)
	top_overlay.add_child(btn_close)

	# 2. Vistas Especializadas (Contenedores)
	_build_player_view(main_vbox)
	_build_enemy_view(main_vbox)
	_build_hint_panel(main_vbox)


# ==============================================================================
# CONSTRUCCIÓN DE LA VISTA: MODO PILOTO (JUGADOR)
# ==============================================================================
func _build_player_view(parent: Control):
	player_view = VBoxContainer.new()
	player_view.name = "PlayerView"
	player_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_view.add_theme_constant_override("separation", 10)
	parent.add_child(player_view)

	# Panel superior: Datos del Piloto y Barras de Estado
	var info_panel = PanelContainer.new()
	var sb_info = StyleBoxFlat.new()
	sb_info.bg_color = Color(0.015, 0.04, 0.07, 0.85)
	sb_info.border_width_left = 1; sb_info.border_width_top = 1
	sb_info.border_width_right = 1; sb_info.border_width_bottom = 1
	sb_info.border_color = Color(0.0, 0.7, 0.9, 0.35)
	sb_info.set_corner_radius_all(6)
	info_panel.add_theme_stylebox_override("panel", sb_info)
	info_panel.gui_input.connect(_on_header_gui_input)
	player_view.add_child(info_panel)

	var info_margin = MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 12)
	info_margin.add_theme_constant_override("margin_right", 12)
	info_margin.add_theme_constant_override("margin_top", 8)
	info_margin.add_theme_constant_override("margin_bottom", 8)
	info_panel.add_child(info_margin)

	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 6)
	info_margin.add_child(info_vbox)

	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 20)
	info_vbox.add_child(top_row)

	ship_info_label = Label.new()
	ship_info_label.text = "NAVE: Identificando..."
	ship_info_label.add_theme_font_size_override("font_size", 11)
	ship_info_label.modulate = Color(0.2, 0.85, 1.0)
	top_row.add_child(ship_info_label)

	clan_info_label = Label.new()
	clan_info_label.text = "FLOTA: Sin Clan"
	clan_info_label.add_theme_font_size_override("font_size", 11)
	clan_info_label.modulate = Color(0.4, 1.0, 0.7)
	top_row.add_child(clan_info_label)

	var spacer_p_close = Control.new()
	spacer_p_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer_p_close)

	var room_p_close = Control.new()
	room_p_close.custom_minimum_size = Vector2(32, 0)
	top_row.add_child(room_p_close)

	# Barras de Salud y Escudo proporcionales
	var bars_vbox = VBoxContainer.new()
	bars_vbox.add_theme_constant_override("separation", 5)
	info_vbox.add_child(bars_vbox)

	# Escudo
	var sh_box = HBoxContainer.new()
	sh_box.add_theme_constant_override("separation", 8)
	bars_vbox.add_child(sh_box)

	var lbl_sh_title = Label.new()
	lbl_sh_title.text = "ESCUDO:"
	lbl_sh_title.custom_minimum_size.x = 65
	lbl_sh_title.add_theme_font_size_override("font_size", 10)
	lbl_sh_title.modulate = Color(0.0, 0.85, 1.0)
	sh_box.add_child(lbl_sh_title)

	shield_bar = ProgressBar.new()
	shield_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shield_bar.custom_minimum_size.y = 16
	shield_bar.show_percentage = false
	var sb_sh = StyleBoxFlat.new()
	sb_sh.bg_color = Color(0.0, 0.75, 0.9, 0.9)
	sb_sh.set_corner_radius_all(3)
	shield_bar.add_theme_stylebox_override("fill", sb_sh)
	var sb_sh_bg = StyleBoxFlat.new()
	sb_sh_bg.bg_color = Color(0.03, 0.1, 0.15, 0.8)
	sb_sh_bg.set_corner_radius_all(3)
	shield_bar.add_theme_stylebox_override("background", sb_sh_bg)
	sh_box.add_child(shield_bar)

	shield_label = Label.new()
	shield_label.text = "0 / 0"
	shield_label.custom_minimum_size.x = 100
	shield_label.add_theme_font_size_override("font_size", 10)
	shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sh_box.add_child(shield_label)

	# Casco / HP
	var hp_box = HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 8)
	bars_vbox.add_child(hp_box)

	var lbl_hp_title = Label.new()
	lbl_hp_title.text = "CASCO:"
	lbl_hp_title.custom_minimum_size.x = 65
	lbl_hp_title.add_theme_font_size_override("font_size", 10)
	lbl_hp_title.modulate = Color(0.2, 0.9, 0.35)
	hp_box.add_child(lbl_hp_title)

	hp_bar = ProgressBar.new()
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.custom_minimum_size.y = 16
	hp_bar.show_percentage = false
	var sb_hp = StyleBoxFlat.new()
	sb_hp.bg_color = Color(0.12, 0.8, 0.28, 0.9)
	sb_hp.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("fill", sb_hp)
	var sb_hp_bg = StyleBoxFlat.new()
	sb_hp_bg.bg_color = Color(0.05, 0.14, 0.08, 0.8)
	sb_hp_bg.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("background", sb_hp_bg)
	hp_box.add_child(hp_bar)

	hp_label = Label.new()
	hp_label.text = "0 / 0"
	hp_label.custom_minimum_size.x = 100
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_box.add_child(hp_label)

	# SECCIÓN: HABILIDADES EQUIPADAS
	var skills_sec_panel = PanelContainer.new()
	var sb_sec1 = StyleBoxFlat.new()
	sb_sec1.bg_color = Color(0.015, 0.035, 0.06, 0.8)
	sb_sec1.border_width_left = 1; sb_sec1.border_width_top = 1
	sb_sec1.border_width_right = 1; sb_sec1.border_width_bottom = 1
	sb_sec1.border_color = Color(0.0, 0.75, 0.9, 0.3)
	sb_sec1.set_corner_radius_all(6)
	skills_sec_panel.add_theme_stylebox_override("panel", sb_sec1)
	player_view.add_child(skills_sec_panel)

	var skills_m = MarginContainer.new()
	skills_m.add_theme_constant_override("margin_left", 12)
	skills_m.add_theme_constant_override("margin_right", 12)
	skills_m.add_theme_constant_override("margin_top", 8)
	skills_m.add_theme_constant_override("margin_bottom", 10)
	skills_sec_panel.add_child(skills_m)

	var skills_vb = VBoxContainer.new()
	skills_vb.add_theme_constant_override("separation", 8)
	skills_m.add_child(skills_vb)

	var skills_header = Label.new()
	skills_header.text = "⚡ HABILIDADES EQUIPADAS DEL PILOTO"
	skills_header.add_theme_font_size_override("font_size", 11)
	skills_header.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	skills_vb.add_child(skills_header)

	skills_container = HBoxContainer.new()
	skills_container.add_theme_constant_override("separation", 14)
	skills_vb.add_child(skills_container)

	# SECCIÓN: EQUIPAMIENTO Y MÓDULOS DE LA NAVE
	var equip_sec_panel = PanelContainer.new()
	equip_sec_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb_sec2 = StyleBoxFlat.new()
	sb_sec2.bg_color = Color(0.015, 0.035, 0.06, 0.8)
	sb_sec2.border_width_left = 1; sb_sec2.border_width_top = 1
	sb_sec2.border_width_right = 1; sb_sec2.border_width_bottom = 1
	sb_sec2.border_color = Color(0.0, 0.75, 0.9, 0.3)
	sb_sec2.set_corner_radius_all(6)
	equip_sec_panel.add_theme_stylebox_override("panel", sb_sec2)
	player_view.add_child(equip_sec_panel)

	var equip_m = MarginContainer.new()
	equip_m.add_theme_constant_override("margin_left", 12)
	equip_m.add_theme_constant_override("margin_right", 12)
	equip_m.add_theme_constant_override("margin_top", 8)
	equip_m.add_theme_constant_override("margin_bottom", 10)
	equip_sec_panel.add_child(equip_m)

	var equip_vb = VBoxContainer.new()
	equip_vb.add_theme_constant_override("separation", 8)
	equip_m.add_child(equip_vb)

	var equip_header = Label.new()
	equip_header.text = "🛡️ MÓDULOS Y EQUIPAMIENTO DE LA NAVE"
	equip_header.add_theme_font_size_override("font_size", 11)
	equip_header.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	equip_vb.add_child(equip_header)

	var scroll_equip = ScrollContainer.new()
	scroll_equip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_equip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	equip_vb.add_child(scroll_equip)

	equip_container = HBoxContainer.new()
	equip_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_container.add_theme_constant_override("separation", 12)
	scroll_equip.add_child(equip_container)


# ==============================================================================
# CONSTRUCCIÓN DE LA VISTA: MODO JEFE / ENEMIGO (ESTADÍSTICAS Y MECÁNICAS)
# ==============================================================================
func _build_enemy_view(parent: Control):
	enemy_view = VBoxContainer.new()
	enemy_view.name = "EnemyView"
	enemy_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_view.add_theme_constant_override("separation", 10)
	parent.add_child(enemy_view)

	# 1. Panel de Identidad y Barras de Combate
	var id_panel = PanelContainer.new()
	var sb_id = StyleBoxFlat.new()
	sb_id.bg_color = Color(0.015, 0.04, 0.07, 0.88)
	sb_id.border_width_left = 1; sb_id.border_width_top = 1
	sb_id.border_width_right = 1; sb_id.border_width_bottom = 1
	sb_id.border_color = Color(0.9, 0.45, 0.1, 0.4)
	sb_id.set_corner_radius_all(6)
	id_panel.add_theme_stylebox_override("panel", sb_id)
	id_panel.gui_input.connect(_on_header_gui_input)
	enemy_view.add_child(id_panel)

	var id_margin = MarginContainer.new()
	id_margin.add_theme_constant_override("margin_left", 10)
	id_margin.add_theme_constant_override("margin_right", 10)
	id_margin.add_theme_constant_override("margin_top", 8)
	id_margin.add_theme_constant_override("margin_bottom", 8)
	id_panel.add_child(id_margin)

	var id_hbox = HBoxContainer.new()
	id_hbox.add_theme_constant_override("separation", 12)
	id_margin.add_child(id_hbox)

	# Avatar / Modelo 3D de la nave enemiga en un marco elegante
	var avatar_frame = PanelContainer.new()
	avatar_frame.custom_minimum_size = Vector2(68, 68)
	var sb_avatar = StyleBoxFlat.new()
	sb_avatar.bg_color = Color(0.02, 0.05, 0.09, 0.95)
	sb_avatar.border_width_left = 2; sb_avatar.border_width_top = 2
	sb_avatar.border_width_right = 2; sb_avatar.border_width_bottom = 2
	sb_avatar.border_color = Color(0.98, 0.65, 0.15, 0.8)
	sb_avatar.set_corner_radius_all(6)
	avatar_frame.add_theme_stylebox_override("panel", sb_avatar)
	id_hbox.add_child(avatar_frame)

	# 1. Contenedor SubViewport 3D para renderizar el modelo GLB
	_enemy_viewport_container = SubViewportContainer.new()
	_enemy_viewport_container.name = "EnemyViewportContainer"
	_enemy_viewport_container.custom_minimum_size = Vector2(64, 64)
	_enemy_viewport_container.size = Vector2(64, 64)
	_enemy_viewport_container.stretch = true
	_enemy_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_frame.add_child(_enemy_viewport_container)

	_enemy_viewport = SubViewport.new()
	_enemy_viewport.name = "EnemyViewport"
	_enemy_viewport.size = Vector2i(64, 64)
	_enemy_viewport.transparent_bg = true
	_enemy_viewport.own_world_3d = true
	_enemy_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_enemy_viewport_container.add_child(_enemy_viewport)

	_enemy_preview_root = Node3D.new()
	_enemy_preview_root.name = "EnemyPreviewRoot"
	_enemy_viewport.add_child(_enemy_preview_root)

	_enemy_preview_cam = Camera3D.new()
	_enemy_preview_cam.name = "Camera3D"
	_enemy_preview_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_enemy_preview_cam.fov = 40.0
	_enemy_preview_cam.look_at_from_position(Vector3(0, 0.45, 1.8), Vector3(0, 0.1, 0))
	_enemy_preview_root.add_child(_enemy_preview_cam)

	var target_light = DirectionalLight3D.new()
	target_light.name = "Light3D"
	target_light.rotation_degrees = Vector3(-45, 35, 0)
	target_light.light_energy = 2.0
	_enemy_preview_root.add_child(target_light)

	_enemy_model_holder = Node3D.new()
	_enemy_model_holder.name = "ModelHolder"
	_enemy_preview_root.add_child(_enemy_model_holder)

	# 2. Textura 2D de respaldo (por si no hay modelo 3D GLB disponible)
	enemy_avatar_rect = TextureRect.new()
	enemy_avatar_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enemy_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	enemy_avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_frame.add_child(enemy_avatar_rect)

	# Columna central: Nombre, Badges y Barras de Salud / Escudo
	var details_vbox = VBoxContainer.new()
	details_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_vbox.add_theme_constant_override("separation", 5)
	id_hbox.add_child(details_vbox)

	var name_badges_row = HBoxContainer.new()
	name_badges_row.add_theme_constant_override("separation", 8)
	details_vbox.add_child(name_badges_row)

	enemy_name_label = Label.new()
	enemy_name_label.text = "JEFE SUPREMO"
	enemy_name_label.add_theme_font_size_override("font_size", 13)
	enemy_name_label.add_theme_color_override("font_color", Color(0.98, 0.78, 0.2))
	enemy_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_badges_row.add_child(enemy_name_label)

	var spacer_nb = Control.new()
	spacer_nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_badges_row.add_child(spacer_nb)

	# Badges (Categoría, ID, Rage)
	enemy_badge_category_panel = _create_badge_panel(Color(0.98, 0.75, 0.15), Color(0.2, 0.1, 0.02, 0.9))
	enemy_badge_category = enemy_badge_category_panel.get_node("Margin/Label")
	enemy_badge_category.text = "👑 JEFE DE ÉLITE"
	name_badges_row.add_child(enemy_badge_category_panel)

	enemy_badge_id_panel = _create_badge_panel(Color(0.4, 0.85, 1.0), Color(0.02, 0.1, 0.15, 0.9))
	enemy_badge_id = enemy_badge_id_panel.get_node("Margin/Label")
	enemy_badge_id.text = "TIPO: 101"
	name_badges_row.add_child(enemy_badge_id_panel)

	enemy_badge_rage_panel = _create_badge_panel(Color(1.0, 0.35, 0.35), Color(0.25, 0.04, 0.04, 0.9))
	enemy_badge_rage = enemy_badge_rage_panel.get_node("Margin/Label")
	enemy_badge_rage.text = "⚠️ ENFURECE: 20s"
	name_badges_row.add_child(enemy_badge_rage_panel)

	var spacer_close_room = Control.new()
	spacer_close_room.custom_minimum_size = Vector2(32, 0)
	name_badges_row.add_child(spacer_close_room)

	# Barras de Salud y Escudo en tiempo real
	var enemy_bars_vbox = VBoxContainer.new()
	enemy_bars_vbox.add_theme_constant_override("separation", 4)
	details_vbox.add_child(enemy_bars_vbox)

	# Escudo
	var sh_r = HBoxContainer.new()
	sh_r.add_theme_constant_override("separation", 8)
	enemy_bars_vbox.add_child(sh_r)

	var lbl_esh_title = Label.new()
	lbl_esh_title.text = "ESCUDO:"
	lbl_esh_title.custom_minimum_size.x = 55
	lbl_esh_title.add_theme_font_size_override("font_size", 9)
	lbl_esh_title.modulate = Color(0.0, 0.85, 1.0)
	sh_r.add_child(lbl_esh_title)

	enemy_shield_bar = ProgressBar.new()
	enemy_shield_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_shield_bar.custom_minimum_size.y = 14
	enemy_shield_bar.show_percentage = false
	var sb_esh = StyleBoxFlat.new()
	sb_esh.bg_color = Color(0.0, 0.75, 0.95, 0.9)
	sb_esh.set_corner_radius_all(3)
	enemy_shield_bar.add_theme_stylebox_override("fill", sb_esh)
	var sb_esh_bg = StyleBoxFlat.new()
	sb_esh_bg.bg_color = Color(0.02, 0.08, 0.12, 0.8)
	sb_esh_bg.set_corner_radius_all(3)
	enemy_shield_bar.add_theme_stylebox_override("background", sb_esh_bg)
	sh_r.add_child(enemy_shield_bar)

	enemy_shield_label = Label.new()
	enemy_shield_label.text = "0 / 0"
	enemy_shield_label.custom_minimum_size.x = 110
	enemy_shield_label.add_theme_font_size_override("font_size", 9)
	enemy_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sh_r.add_child(enemy_shield_label)

	# Casco
	var hp_r = HBoxContainer.new()
	hp_r.add_theme_constant_override("separation", 8)
	enemy_bars_vbox.add_child(hp_r)

	var lbl_ehp_title = Label.new()
	lbl_ehp_title.text = "CASCO:"
	lbl_ehp_title.custom_minimum_size.x = 55
	lbl_ehp_title.add_theme_font_size_override("font_size", 9)
	lbl_ehp_title.modulate = Color(0.2, 0.9, 0.35)
	hp_r.add_child(lbl_ehp_title)

	enemy_hp_bar = ProgressBar.new()
	enemy_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_hp_bar.custom_minimum_size.y = 14
	enemy_hp_bar.show_percentage = false
	var sb_ehp = StyleBoxFlat.new()
	sb_ehp.bg_color = Color(0.12, 0.82, 0.28, 0.9)
	sb_ehp.set_corner_radius_all(3)
	enemy_hp_bar.add_theme_stylebox_override("fill", sb_ehp)
	var sb_ehp_bg = StyleBoxFlat.new()
	sb_ehp_bg.bg_color = Color(0.05, 0.12, 0.07, 0.8)
	sb_ehp_bg.set_corner_radius_all(3)
	enemy_hp_bar.add_theme_stylebox_override("background", sb_ehp_bg)
	hp_r.add_child(enemy_hp_bar)

	enemy_hp_label = Label.new()
	enemy_hp_label.text = "0 / 0"
	enemy_hp_label.custom_minimum_size.x = 110
	enemy_hp_label.add_theme_font_size_override("font_size", 9)
	enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_r.add_child(enemy_hp_label)

	# 2. Panel de Recompensas de Eliminación (solo visible si otorga recompensas)
	enemy_rewards_panel = PanelContainer.new()
	var sb_rew = StyleBoxFlat.new()
	sb_rew.bg_color = Color(0.012, 0.03, 0.055, 0.85)
	sb_rew.border_width_left = 1; sb_rew.border_width_top = 1
	sb_rew.border_width_right = 1; sb_rew.border_width_bottom = 1
	sb_rew.border_color = Color(0.2, 0.7, 0.9, 0.3)
	sb_rew.set_corner_radius_all(6)
	enemy_rewards_panel.add_theme_stylebox_override("panel", sb_rew)
	enemy_view.add_child(enemy_rewards_panel)

	var rew_margin = MarginContainer.new()
	rew_margin.add_theme_constant_override("margin_left", 10)
	rew_margin.add_theme_constant_override("margin_right", 10)
	rew_margin.add_theme_constant_override("margin_top", 6)
	rew_margin.add_theme_constant_override("margin_bottom", 6)
	enemy_rewards_panel.add_child(rew_margin)

	var rew_vbox = VBoxContainer.new()
	rew_vbox.add_theme_constant_override("separation", 4)
	rew_margin.add_child(rew_vbox)

	var rew_title = Label.new()
	rew_title.text = "🎁 RECOMPENSAS POR DERROTA"
	rew_title.add_theme_font_size_override("font_size", 10)
	rew_title.modulate = Color(0.4, 0.85, 1.0)
	rew_vbox.add_child(rew_title)

	enemy_rewards_flow = HFlowContainer.new()
	enemy_rewards_flow.add_theme_constant_override("h_separation", 8)
	enemy_rewards_flow.add_theme_constant_override("v_separation", 4)
	rew_vbox.add_child(enemy_rewards_flow)

	# 3. Panel de Comportamiento Global (Tácticas y Reglas de Supervivencia)
	enemy_behavior_panel = PanelContainer.new()
	var sb_beh = StyleBoxFlat.new()
	sb_beh.bg_color = Color(0.012, 0.03, 0.055, 0.88)
	sb_beh.border_width_left = 1; sb_beh.border_width_top = 1
	sb_beh.border_width_right = 1; sb_beh.border_width_bottom = 1
	sb_beh.border_color = Color(0.0, 0.8, 0.9, 0.35)
	sb_beh.set_corner_radius_all(6)
	enemy_behavior_panel.add_theme_stylebox_override("panel", sb_beh)
	enemy_view.add_child(enemy_behavior_panel)

	var beh_margin = MarginContainer.new()
	beh_margin.add_theme_constant_override("margin_left", 10)
	beh_margin.add_theme_constant_override("margin_right", 10)
	beh_margin.add_theme_constant_override("margin_top", 6)
	beh_margin.add_theme_constant_override("margin_bottom", 6)
	enemy_behavior_panel.add_child(beh_margin)

	var beh_vbox = VBoxContainer.new()
	beh_vbox.add_theme_constant_override("separation", 5)
	beh_margin.add_child(beh_vbox)

	var beh_title = Label.new()
	beh_title.text = "🧠 COMPORTAMIENTO GLOBAL"
	beh_title.add_theme_font_size_override("font_size", 10)
	beh_title.modulate = Color(0.3, 0.85, 1.0)
	beh_vbox.add_child(beh_title)

	enemy_behavior_flow_tactics = HFlowContainer.new()
	enemy_behavior_flow_tactics.add_theme_constant_override("h_separation", 6)
	enemy_behavior_flow_tactics.add_theme_constant_override("v_separation", 4)
	beh_vbox.add_child(enemy_behavior_flow_tactics)

	enemy_behavior_flow_regen = HFlowContainer.new()
	enemy_behavior_flow_regen.add_theme_constant_override("h_separation", 6)
	enemy_behavior_flow_regen.add_theme_constant_override("v_separation", 4)
	beh_vbox.add_child(enemy_behavior_flow_regen)

	# 4. Panel de Mecánicas y Habilidades Dinámicas (con Scroll)
	var mechs_sec_panel = PanelContainer.new()
	mechs_sec_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb_mechs = StyleBoxFlat.new()
	sb_mechs.bg_color = Color(0.015, 0.035, 0.06, 0.85)
	sb_mechs.border_width_left = 1; sb_mechs.border_width_top = 1
	sb_mechs.border_width_right = 1; sb_mechs.border_width_bottom = 1
	sb_mechs.border_color = Color(0.95, 0.55, 0.15, 0.4)
	sb_mechs.set_corner_radius_all(6)
	mechs_sec_panel.add_theme_stylebox_override("panel", sb_mechs)
	enemy_view.add_child(mechs_sec_panel)

	var mechs_margin = MarginContainer.new()
	mechs_margin.add_theme_constant_override("margin_left", 10)
	mechs_margin.add_theme_constant_override("margin_right", 10)
	mechs_margin.add_theme_constant_override("margin_top", 8)
	mechs_margin.add_theme_constant_override("margin_bottom", 8)
	mechs_sec_panel.add_child(mechs_margin)

	var mechs_vbox = VBoxContainer.new()
	mechs_vbox.add_theme_constant_override("separation", 8)
	mechs_margin.add_child(mechs_vbox)

	var mechs_header_row = HBoxContainer.new()
	mechs_header_row.add_theme_constant_override("separation", 8)
	mechs_vbox.add_child(mechs_header_row)

	enemy_mechanics_count_label = Label.new()
	enemy_mechanics_count_label.text = "⚙️ MECÁNICAS Y HABILIDADES DE COMBATE (0)"
	enemy_mechanics_count_label.add_theme_font_size_override("font_size", 11)
	enemy_mechanics_count_label.add_theme_color_override("font_color", Color(0.98, 0.7, 0.2))
	mechs_header_row.add_child(enemy_mechanics_count_label)

	var scroll_mechs = ScrollContainer.new()
	scroll_mechs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_mechs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_mechs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_mechs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	mechs_vbox.add_child(scroll_mechs)

	mechanics_cards_container = VBoxContainer.new()
	mechanics_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mechanics_cards_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mechanics_cards_container.add_theme_constant_override("separation", 8)
	scroll_mechs.add_child(mechanics_cards_container)


# ==============================================================================
# CONSTRUCCIÓN DEL PANEL DE ESTADO/AVISO (HINT)
# ==============================================================================
func _build_hint_panel(parent: Control):
	hint_panel = PanelContainer.new()
	hint_panel.name = "HintPanel"
	hint_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb_hint = StyleBoxFlat.new()
	sb_hint.bg_color = Color(0.015, 0.035, 0.06, 0.85)
	sb_hint.border_width_left = 1; sb_hint.border_width_top = 1
	sb_hint.border_width_right = 1; sb_hint.border_width_bottom = 1
	sb_hint.border_color = Color(0.0, 0.75, 0.9, 0.3)
	sb_hint.set_corner_radius_all(6)
	hint_panel.add_theme_stylebox_override("panel", sb_hint)
	parent.add_child(hint_panel)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_panel.add_child(center)

	hint_label = Label.new()
	hint_label.text = "Selecciona un objetivo para inspeccionar."
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.modulate = Color(0.4, 0.85, 1.0, 0.85)
	center.add_child(hint_label)


func _create_badge_panel(border_color: Color, bg_color: Color) -> PanelContainer:
	var p = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = border_color
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)

	var m = MarginContainer.new()
	m.name = "Margin"
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	m.add_theme_constant_override("margin_top", 2)
	m.add_theme_constant_override("margin_bottom", 2)
	p.add_child(m)

	var lbl = Label.new()
	lbl.name = "Label"
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", border_color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	m.add_child(lbl)
	return p


# ==============================================================================
# LÓGICA DE APERTURA, TRACKING Y SELECCIÓN DE OBJETIVOS
# ==============================================================================
func _process(_delta: float):
	if not is_open: return

	# 0. Rotación continua y fluida del modelo 3D del enemigo en el marco del avatar
	if current_mode == Mode.ENEMY and is_instance_valid(_enemy_model_holder) and _enemy_model_holder.get_child_count() > 0:
		_enemy_model_holder.rotate_y(_delta * 0.4)

	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_tree().get_first_node_in_group("main_hud")

	# 1. Detectar si el jugador cambió de objetivo en el mundo mientras la ventana está abierta
	if is_instance_valid(main_hud) and "_target_entity" in main_hud:
		var cur_tgt = main_hud._target_entity
		if is_instance_valid(cur_tgt) and cur_tgt != target_node:
			var local_player = get_tree().get_first_node_in_group("player")
			if cur_tgt != local_player:
				if _is_player_target(cur_tgt):
					target_node = cur_tgt
					target_player_node = cur_tgt
					_open_with_player_target(cur_tgt)
				elif _is_enemy_target(cur_tgt):
					target_node = cur_tgt
					_open_with_enemy_target(cur_tgt)

	# 2. Actualización continua de barras vitales (Salud / Escudo)
	if is_instance_valid(target_node):
		if current_mode == Mode.ENEMY:
			_update_live_enemy_bars()
		elif current_mode == Mode.PLAYER:
			_update_live_player_bars()
	else:
		if is_open and current_mode != Mode.HINT and current_mode != Mode.NONE:
			_show_hint_state("El objetivo seleccionado ha desaparecido o ha sido destruido.")


func inspect_current_target():
	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_tree().get_first_node_in_group("main_hud")

	var target = null
	if is_instance_valid(main_hud) and "_target_entity" in main_hud:
		target = main_hud._target_entity

	is_open = true
	visible = true
	_reposition_window()
	if get_parent():
		get_parent().move_child(self, get_parent().get_child_count() - 1)
		z_index = 110

	# 1. Fallback si no hay objetivo actual pero teníamos uno previamente válido
	if not is_instance_valid(target) and is_instance_valid(target_node):
		target = target_node

	# 2. Sin objetivo
	if not is_instance_valid(target):
		_show_hint_state("Selecciona a otro piloto o a un enemigo para inspeccionar sus características y mecánicas.")
		return

	# 3. Bloqueo de auto-inspección
	var stats_key = _get_action_key_display("ui_stats", "C")
	var equip_key = _get_action_key_display("ui_inventory", "V")
	var self_inspect_msg = "No puedes inspeccionarte a ti mismo. Usa tus menús de Estadísticas (%s) o Equipamiento (%s)." % [stats_key, equip_key]

	var local_player = get_tree().get_first_node_in_group("player")
	if target == local_player:
		_show_hint_state(self_inspect_msg)
		return

	if NetworkManager and NetworkManager.is_logged_in:
		var target_uname = str(target.get("username")) if "username" in target else ""
		if target_uname != "" and target_uname.to_lower() == NetworkManager.login_name.to_lower():
			_show_hint_state(self_inspect_msg)
			return

	# 4. Caso nodo de recursos
	if target.get("is_resource_node") == true:
		_show_hint_state("El objetivo seleccionado es un nodo de recursos, no una unidad de combate.")
		return

	# 5. CASO PILOTO (JUGADOR)
	if _is_player_target(target):
		target_node = target
		target_player_node = target
		_open_with_player_target(target)
		return

	# 6. CASO ENEMIGO O BOSS
	if _is_enemy_target(target):
		target_node = target
		_open_with_enemy_target(target)
		return

	_show_hint_state("El objetivo seleccionado no se puede inspeccionar.")


func _is_player_target(target: Node) -> bool:
	if not is_instance_valid(target): return false
	var local_player = get_tree().get_first_node_in_group("player")
	if target == local_player: return false
	if target.is_in_group("remote_players"): return true
	if target.is_in_group("player"): return true
	return false


func _is_enemy_target(target: Node) -> bool:
	if not is_instance_valid(target): return false
	if _is_player_target(target): return false
	if target.get("is_resource_node") == true: return false
	if target.is_in_group("enemies"): return true
	if target.get("is_boss") == true or target.has_meta("is_boss"): return true
	if "entity_type" in target and int(target.get("entity_type")) > 0: return true
	if "raw_entity_type" in target and str(target.get("raw_entity_type")) != "": return true
	return false


func _show_hint_state(msg: String):
	current_mode = Mode.HINT
	player_view.visible = false
	enemy_view.visible = false
	hint_panel.visible = true
	hint_label.text = msg
	if is_instance_valid(pilot_title_label):
		pilot_title_label.text = "INSPECCIÓN DE OBJETIVO"
		pilot_title_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	if is_instance_valid(icon_title):
		icon_title.text = " 🔍 "


# ==============================================================================
# CARGA Y DESPLIEGUE: MODO PILOTO (JUGADOR)
# ==============================================================================
func _open_with_player_target(target: Node):
	current_mode = Mode.PLAYER
	player_view.visible = true
	enemy_view.visible = false
	hint_panel.visible = false
	if is_instance_valid(icon_title): icon_title.text = " 🔍 "

	# 1. Carga inmediata de datos locales
	_load_data_from_target_node(target)

	# 2. Consulta al servidor para datos autoritativos y módulos de nave
	if NetworkManager and NetworkManager.network_connected:
		var uname = str(target.get("username")) if "username" in target else str(target.name)
		NetworkManager.send_event("inspectPlayer", { "username": uname, "id": target.get("entity_id") })


func _load_data_from_target_node(target: Node):
	var uname = str(target.get("username")) if "username" in target and str(target.get("username")) != "" else str(target.name)
	var tag = str(target.get("clan_tag")) if "clan_tag" in target and str(target.get("clan_tag")) != "" else ""
	var ship_id = int(target.get("current_ship_id")) if "current_ship_id" in target else 1
	var hp = float(target.get("current_hp")) if "current_hp" in target else 0.0
	var max_h = float(target.get("max_hp")) if "max_hp" in target else 0.0
	var sh = float(target.get("current_shield")) if "current_shield" in target else 0.0
	var max_s = float(target.get("max_shield")) if "max_shield" in target else 0.0

	var ship_name = "Nave #" + str(ship_id)
	var slots_def = { "w": 1, "s": 1, "e": 1, "x": 1 }
	if GameConstants.SHIP_MODELS:
		for sm in GameConstants.SHIP_MODELS:
			if int(sm.get("id")) == ship_id:
				ship_name = str(sm.get("name", ship_name))
				slots_def = sm.get("slots", slots_def)
				if max_h <= 0.0:
					max_h = float(sm.get("hp", 1000.0))
					hp = max_h
				if max_s <= 0.0:
					max_s = float(sm.get("shield", 500.0))
					sh = max_s
				break

	if max_h <= 0.0: max_h = 1000.0; hp = 1000.0
	if max_s <= 0.0: max_s = 500.0; sh = 500.0

	if is_instance_valid(pilot_title_label):
		pilot_title_label.text = "INSPECCIÓN DE PILOTO: " + (("[" + tag + "] ") if tag != "" else "") + uname
		pilot_title_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))

	ship_info_label.text = "NAVE: " + ship_name + " (#" + str(ship_id) + ")"
	clan_info_label.text = "FLOTA: " + (("[" + tag + "]") if tag != "" else "Piloto Libre")

	hp_bar.max_value = max(1.0, max_h)
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [int(hp), int(max_h)]

	shield_bar.max_value = max(1.0, max_s)
	shield_bar.value = sh
	shield_label.text = "%d / %d" % [int(sh), int(max_s)]

	var eq = target.get("equipped") if "equipped" in target else {}
	_render_equipment(eq if typeof(eq) == TYPE_DICTIONARY else {}, slots_def)

	var sm = target.get_node_or_null("SpheresManager")
	var skills_arr = []
	if is_instance_valid(sm) and "spheres_data" in sm:
		for s_data in sm.spheres_data:
			var eq_skill = s_data.get("equipped")
			if eq_skill != null:
				skills_arr.append(eq_skill)
	_render_skills(skills_arr)


func _update_live_player_bars():
	if not is_instance_valid(target_node): return
	var cur_hp = float(target_node.get("current_hp")) if "current_hp" in target_node else 0.0
	var max_h = float(target_node.get("max_hp")) if "max_hp" in target_node else 1.0
	var cur_sh = float(target_node.get("current_shield")) if "current_shield" in target_node else 0.0
	var max_s = float(target_node.get("max_shield")) if "max_shield" in target_node else 0.0

	if is_instance_valid(hp_bar) and max_h > 0:
		hp_bar.max_value = max(1.0, max_h)
		hp_bar.value = cur_hp
	if is_instance_valid(hp_label):
		hp_label.text = "%d / %d" % [int(cur_hp), int(max_h)]

	if is_instance_valid(shield_bar) and max_s > 0:
		shield_bar.max_value = max(1.0, max_s)
		shield_bar.value = cur_sh
	if is_instance_valid(shield_label):
		shield_label.text = "%d / %d" % [int(cur_sh), int(max_s)]


func _on_server_inspect_data(data: Dictionary):
	if not is_open or current_mode != Mode.PLAYER: return
	if data.get("success", false) == false:
		_notify_user(str(data.get("msg", "No se pudo inspeccionar")), "warn")
		return

	inspected_data = data
	var uname = str(data.get("username", ""))
	var tag = str(data.get("clanTag", ""))
	var ship_id = int(data.get("currentShipId", 1))
	var ship_name = str(data.get("shipName", "Nave #" + str(ship_id)))
	var hp = float(data.get("hp", 1000.0))
	var max_h = float(data.get("maxHp", 1000.0))
	var sh = float(data.get("shield", 500.0))
	var max_s = float(data.get("maxShield", 500.0))

	var slots_def = data.get("shipSlots", {})
	if (slots_def == null or (typeof(slots_def) == TYPE_DICTIONARY and slots_def.is_empty())) and GameConstants.SHIP_MODELS:
		for sm in GameConstants.SHIP_MODELS:
			if int(sm.get("id")) == ship_id:
				slots_def = sm.get("slots", { "w": 1, "s": 1, "e": 1, "x": 1 })
				if ship_name == ("Nave #" + str(ship_id)):
					ship_name = str(sm.get("name", ship_name))
				break

	if slots_def == null or typeof(slots_def) != TYPE_DICTIONARY or slots_def.is_empty():
		slots_def = { "w": 1, "s": 1, "e": 1, "x": 1 }

	if is_instance_valid(pilot_title_label):
		pilot_title_label.text = "INSPECCIÓN DE PILOTO: " + (("[" + tag + "] ") if tag != "" else "") + uname
	ship_info_label.text = "NAVE: " + ship_name + " (#" + str(ship_id) + ")"
	clan_info_label.text = "FLOTA: " + (("[" + tag + "]") if tag != "" else "Piloto Libre")

	hp_bar.max_value = max(1.0, max_h)
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [int(hp), int(max_h)]

	shield_bar.max_value = max(1.0, max_s)
	shield_bar.value = sh
	shield_label.text = "%d / %d" % [int(sh), int(max_s)]

	if data.has("equipped") and typeof(data["equipped"]) == TYPE_DICTIONARY:
		_render_equipment(data["equipped"], slots_def)
	else:
		_render_equipment({}, slots_def)

	if data.has("skills") and typeof(data["skills"]) == TYPE_ARRAY:
		_render_skills(data["skills"])


func _render_skills(skills_list: Array):
	for c in skills_container.get_children():
		c.queue_free()

	if skills_list.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "El piloto no tiene habilidades equipadas en sus esferas."
		empty_lbl.add_theme_font_size_override("font_size", 10)
		empty_lbl.modulate = Color(0.6, 0.75, 0.85, 0.6)
		skills_container.add_child(empty_lbl)
		return

	for sk in skills_list:
		var sk_name = ""
		var sk_texture: Texture2D = null
		var sk_type = "Ataque"

		if sk is Resource:
			sk_name = str(sk.get("skill_name"))
			if sk.get("icon") and sk.get("icon") is Texture2D:
				sk_texture = sk.get("icon")
			if sk.get("type"):
				sk_type = str(sk.get("type"))
		elif typeof(sk) == TYPE_DICTIONARY:
			sk_name = str(sk.get("skill_name", sk.get("name", sk.get("id", ""))))
			sk_type = str(sk.get("type", "Ataque"))
			if sk.has("icon") and sk["icon"] is Texture2D:
				sk_texture = sk["icon"]
			elif sk.has("icon_path") and ResourceLoader.exists(str(sk["icon_path"])):
				sk_texture = load(str(sk["icon_path"]))
		else:
			sk_name = str(sk)

		if sk_name == "": continue

		var clean_name = sk_name.to_upper().strip_edges().replace("Ó", "O").replace("É", "E").replace("Í", "I").replace("Á", "A").replace("Ú", "U").replace("Ü", "U")

		var type_color = Color(0.9, 0.35, 0.35)
		var type_lower = sk_type.to_lower()
		if "defensa" in type_lower:
			type_color = Color(0.2, 0.85, 1.0)
		elif "cura" in type_lower:
			type_color = Color(0.25, 0.95, 0.45)
		elif "utilidad" in type_lower or "movimiento" in type_lower:
			type_color = Color(1.0, 0.85, 0.25)

		if sk_texture == null:
			var icon_p = _skill_icons.get(clean_name, "")
			if icon_p != "" and ResourceLoader.exists(icon_p):
				sk_texture = load(icon_p)
			else:
				var fallback_path = ""
				if "defensa" in type_lower:
					fallback_path = "res://assets/Skills/Iconos/Defensa/Escudo Celular/Escudo Celular.png"
				elif "cura" in type_lower:
					fallback_path = "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png"
				elif "utilidad" in type_lower:
					fallback_path = "res://assets/Skills/Iconos/Utilidad/Turbo Impulso/Turbo Impulso.png"
				else:
					fallback_path = "res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png"

				if ResourceLoader.exists(fallback_path):
					sk_texture = load(fallback_path)

		var p = PanelContainer.new()
		p.custom_minimum_size = Vector2(58, 58)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.015, 0.04, 0.08, 0.95)
		sb.border_width_left = 2; sb.border_width_top = 2
		sb.border_width_right = 2; sb.border_width_bottom = 2
		sb.border_color = type_color
		sb.set_corner_radius_all(6)
		p.add_theme_stylebox_override("panel", sb)

		var v = VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 2)
		p.add_child(v)

		var tex_rect = TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(36, 36)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if sk_texture: tex_rect.texture = sk_texture
		v.add_child(tex_rect)

		var lbl = Label.new()
		lbl.text = sk_name.substr(0, 9)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.modulate = type_color
		v.add_child(lbl)

		p.tooltip_text = "%s\nTipo: %s" % [sk_name, sk_type]
		skills_container.add_child(p)


func _render_equipment(equip_dict: Dictionary, slots_def: Dictionary = {}):
	for c in equip_container.get_children():
		c.queue_free()

	if slots_def == null or slots_def.is_empty():
		slots_def = { "w": 1, "s": 1, "e": 1, "x": 1 }

	var categories = [
		{"key": "w", "label": "ARMAS", "color": Color(0.95, 0.35, 0.35), "limit": int(slots_def.get("w", 1)), "glyph": "⚔"},
		{"key": "s", "label": "ESCUDOS", "color": Color(0.2, 0.85, 1.0), "limit": int(slots_def.get("s", 1)), "glyph": "🛡"},
		{"key": "e", "label": "MOTORES", "color": Color(1.0, 0.85, 0.25), "limit": int(slots_def.get("e", 1)), "glyph": "⚡"},
		{"key": "x", "label": "MÓDULOS", "color": Color(0.8, 0.5, 1.0), "limit": int(slots_def.get("x", 1)), "glyph": "💎"}
	]

	for cat in categories:
		var cat_panel = PanelContainer.new()
		cat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb_cat = StyleBoxFlat.new()
		sb_cat.bg_color = Color(0.01, 0.03, 0.06, 0.6)
		sb_cat.border_width_left = 1; sb_cat.border_width_top = 1
		sb_cat.border_width_right = 1; sb_cat.border_width_bottom = 1
		sb_cat.border_color = Color(cat.color.r, cat.color.g, cat.color.b, 0.3)
		sb_cat.set_corner_radius_all(5)
		cat_panel.add_theme_stylebox_override("panel", sb_cat)
		equip_container.add_child(cat_panel)

		var cat_margin = MarginContainer.new()
		cat_margin.add_theme_constant_override("margin_left", 6)
		cat_margin.add_theme_constant_override("margin_right", 6)
		cat_margin.add_theme_constant_override("margin_top", 6)
		cat_margin.add_theme_constant_override("margin_bottom", 6)
		cat_panel.add_child(cat_margin)

		var cat_vb = VBoxContainer.new()
		cat_vb.add_theme_constant_override("separation", 6)
		cat_margin.add_child(cat_vb)

		var items = equip_dict.get(cat.key, [])
		var items_arr = items if typeof(items) == TYPE_ARRAY else []

		var equipped_count = 0
		for it in items_arr:
			if it != null and typeof(it) == TYPE_DICTIONARY and not it.is_empty():
				equipped_count += 1

		var cat_title = Label.new()
		cat_title.text = "%s (%d/%d)" % [cat.label, equipped_count, cat.limit]
		cat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cat_title.add_theme_font_size_override("font_size", 9)
		cat_title.modulate = cat.color
		cat_vb.add_child(cat_title)

		for slot_idx in range(cat.limit):
			var item = items_arr[slot_idx] if slot_idx < items_arr.size() else null
			_create_equip_slot(cat_vb, item, cat.label, cat.color, cat.glyph)


func _create_equip_slot(parent: Control, item, cat_label: String, border_col: Color, glyph: String = ""):
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(56, 56)

	var sb = StyleBoxFlat.new()
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.set_corner_radius_all(5)

	if item != null and typeof(item) == TYPE_DICTIONARY and not item.is_empty():
		var rarity = int(item.get("rarity", 0))
		var r_color = ItemInfoHelper.rarity_color(rarity)

		sb.bg_color = Color(r_color.r, r_color.g, r_color.b, 0.15)
		sb.border_color = r_color
		sb.border_width_left = 2; sb.border_width_top = 2
		sb.border_width_right = 2; sb.border_width_bottom = 2
		p.add_theme_stylebox_override("panel", sb)

		var center = CenterContainer.new()
		center.custom_minimum_size = Vector2(52, 52)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(center)

		var item_name = str(item.get("name", item.get("id", "Módulo")))
		var item_tier = int(item.get("tier", item.get("level", 1)))
		var icon_path = _resolve_item_icon(item)

		var icon_node = null
		if ModelIconGenerator and ModelIconGenerator.has_method("make_icon_rect"):
			icon_node = ModelIconGenerator.make_icon_rect(item, icon_path, Vector2(36, 36))

		if icon_node:
			center.add_child(icon_node)
		else:
			var icon_rect = TextureRect.new()
			icon_rect.custom_minimum_size = Vector2(36, 36)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var tex = _get_item_icon(item)
			if tex: icon_rect.texture = tex
			center.add_child(icon_rect)

		var tier_badge = Label.new()
		tier_badge.text = "T" + str(item_tier)
		tier_badge.add_theme_font_size_override("font_size", 8)
		tier_badge.modulate = r_color
		p.add_child(tier_badge)

		p.tooltip_text = "%s (%s)\nTier %d" % [item_name, cat_label, item_tier]
	else:
		sb.bg_color = Color(0.015, 0.03, 0.05, 0.45)
		sb.border_color = Color(border_col.r, border_col.g, border_col.b, 0.25)
		p.add_theme_stylebox_override("panel", sb)

		var center = CenterContainer.new()
		center.custom_minimum_size = Vector2(52, 52)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(center)

		var empty_lbl = Label.new()
		empty_lbl.text = glyph if glyph != "" else "-"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.modulate = Color(border_col.r, border_col.g, border_col.b, 0.3)
		center.add_child(empty_lbl)
		p.tooltip_text = "Slot vacío (%s)" % cat_label

	parent.add_child(p)


# ==============================================================================
# CARGA Y DESPLIEGUE: MODO JEFE / ENEMIGO (STATS Y MECÁNICAS DINÁMICAS)
# ==============================================================================
func _open_with_enemy_target(target: Node):
	current_mode = Mode.ENEMY
	player_view.visible = false
	enemy_view.visible = true
	hint_panel.visible = false

	var cfg = _get_enemy_config(target)
	var raw_type = ""
	if "raw_entity_type" in target and target.get("raw_entity_type") != null:
		raw_type = str(target.get("raw_entity_type"))
	elif "entity_type" in target and target.get("entity_type") != null:
		raw_type = str(target.get("entity_type"))
	else:
		raw_type = "1"
	raw_type = _format_id(raw_type)

	var num_type = int(target.get("entity_type")) if ("entity_type" in target and target.get("entity_type") != null) else 0
	var is_boss = bool(cfg.get("isBoss", false)) == true or (target.has_meta("is_boss") and bool(target.get_meta("is_boss"))) or ("is_boss" in target and bool(target.get("is_boss"))) or num_type >= 101

	# Título de Cabecera (solo icono temático; el nombre ya se muestra junto al modelo 3D GLB)
	var target_uname = str(target.get("username")) if ("username" in target and target.get("username") != null and str(target.get("username")) != "") else ""
	var enemy_name = str(cfg.get("name", target_uname if target_uname != "" else "Amenaza Desconocida"))
	if enemy_name == "": enemy_name = "Enemigo " + raw_type

	if is_instance_valid(pilot_title_label): pilot_title_label.text = ""
	if is_instance_valid(icon_title): icon_title.text = " 👑 " if is_boss else " 👾 "

	enemy_name_label.text = enemy_name
	enemy_name_label.add_theme_color_override("font_color", Color(0.98, 0.8, 0.25) if is_boss else Color(0.95, 0.5, 0.4))

	# Badges
	if is_boss:
		enemy_badge_category.text = "👑 JEFE DE ÉLITE"
		_set_badge_style(enemy_badge_category_panel, Color(0.98, 0.75, 0.15), Color(0.25, 0.1, 0.02, 0.9))
	elif raw_type.contains("-"):
		enemy_badge_category.text = "⚡ VARIANTE DE ÉLITE"
		_set_badge_style(enemy_badge_category_panel, Color(0.75, 0.5, 1.0), Color(0.18, 0.05, 0.25, 0.9))
	else:
		enemy_badge_category.text = "👾 AMENAZA HOSTIL"
		_set_badge_style(enemy_badge_category_panel, Color(0.95, 0.4, 0.4), Color(0.2, 0.04, 0.04, 0.9))

	enemy_badge_id.text = "TIPO: " + raw_type
	enemy_badge_id_panel.visible = true

	var enrage_on = bool(cfg.get("enrageEnabled", false))
	var enrage_mode = str(cfg.get("enrageMode", "time")).to_lower()
	var enrage_val = float(cfg.get("enrageValue", 0.0))

	if enrage_on and enrage_val > 0.0:
		if enrage_mode == "hp":
			enemy_badge_rage.text = "⚠️ ENFURECE: %s%% HP" % _format_float_clean(enrage_val)
		else:
			enemy_badge_rage.text = "⚠️ ENFURECE: %s" % _format_seconds(enrage_val)
		enemy_badge_rage_panel.visible = true
	else:
		enemy_badge_rage_panel.visible = false

	# Icono 2D de fallback del enemigo
	var icon_path = str(cfg.get("icon", ""))
	var icon_tex: Texture2D = null
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon_tex = load(icon_path)
	elif ResourceLoader.exists("res://assets/Enemigos/2D/Enemigo" + raw_type.split("-")[0] + "/Enemy" + raw_type.split("-")[0] + "Map1.png"):
		icon_tex = load("res://assets/Enemigos/2D/Enemigo" + raw_type.split("-")[0] + "/Enemy" + raw_type.split("-")[0] + "Map1.png")

	if icon_tex:
		enemy_avatar_rect.texture = icon_tex
	else:
		enemy_avatar_rect.texture = null

	# Previsualización 3D rotatoria en tiempo real (idéntica a Target HUD)
	_update_3d_enemy_preview(target, cfg)

	# Barras Vitales Iniciales
	_update_live_enemy_bars()

	# Comportamiento Global (Tácticas y Supervivencia OOC)
	_render_enemy_behavior(cfg, target)

	# Recompensas de Derrota (si tiene)
	_render_enemy_rewards(cfg)

	# Desglose Dinámico de Mecánicas
	_render_enemy_mechanics(cfg)


func _set_badge_style(panel: PanelContainer, border_col: Color, bg_col: Color):
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = border_col
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var lbl = panel.get_node_or_null("Margin/Label")
	if is_instance_valid(lbl):
		lbl.add_theme_color_override("font_color", border_col)


func _update_live_enemy_bars():
	if not is_instance_valid(target_node): return
	var cur_hp = float(target_node.get("current_hp")) if "current_hp" in target_node else 0.0
	var max_h = float(target_node.get("max_hp")) if "max_hp" in target_node else 1.0
	var cur_sh = float(target_node.get("current_shield")) if "current_shield" in target_node else 0.0
	var max_s = float(target_node.get("max_shield")) if "max_shield" in target_node else 0.0

	if max_h <= 0.0: max_h = 1.0

	if is_instance_valid(enemy_hp_bar):
		enemy_hp_bar.max_value = max(1.0, max_h)
		enemy_hp_bar.value = cur_hp
	if is_instance_valid(enemy_hp_label):
		var pct = int((cur_hp / max(1.0, max_h)) * 100.0)
		enemy_hp_label.text = "%s / %s (%d%%)" % [_format_number(int(cur_hp)), _format_number(int(max_h)), pct]

	if is_instance_valid(enemy_shield_bar):
		enemy_shield_bar.max_value = max(1.0, max_s)
		enemy_shield_bar.value = cur_sh
	if is_instance_valid(enemy_shield_label):
		if max_s > 0:
			var pct_s = int((cur_sh / max_s) * 100.0)
			enemy_shield_label.text = "%s / %s (%d%%)" % [_format_number(int(cur_sh)), _format_number(int(max_s)), pct_s]
		else:
			enemy_shield_label.text = "0 / 0 (Sin Escudo)"


func _render_enemy_behavior(cfg: Dictionary, target: Node = null):
	if not is_instance_valid(enemy_behavior_panel): return
	for c in enemy_behavior_flow_tactics.get_children():
		c.queue_free()
	for c in enemy_behavior_flow_regen.get_children():
		c.queue_free()

	# 1. Tácticas de IA y Hostilidad (Solo mostrar lo que esté realmente configurado y activo)
	if bool(cfg.get("aggressive", false)):
		_create_param_pill(enemy_behavior_flow_tactics, "⚔️", "Agresivo: Ataca al ver", Color(0.98, 0.45, 0.35))

	if bool(cfg.get("chaseUntilDeath", false)):
		_create_param_pill(enemy_behavior_flow_tactics, "💀", "Persistir hasta morir", Color(0.98, 0.65, 0.25))

	if bool(cfg.get("stopOnOutOfSight", false)):
		_create_param_pill(enemy_behavior_flow_tactics, "👁️", "Parar si no hay visión", Color(0.45, 0.85, 0.95))

	if bool(cfg.get("enrageEnabled", false)):
		var e_mode = str(cfg.get("enrageMode", "time")).to_lower()
		var e_val = float(cfg.get("enrageValue", 0.0))
		if e_val > 0.0:
			if e_mode == "hp":
				_create_param_pill(enemy_behavior_flow_tactics, "🔥", "Enfurece al caer a %s%% HP" % _format_float_clean(e_val), Color(1.0, 0.4, 0.4))
			else:
				_create_param_pill(enemy_behavior_flow_tactics, "🔥", "Enfurece tras %s de combate" % _format_seconds(e_val), Color(1.0, 0.4, 0.4))

	var timeout_ms = int(cfg.get("chaseIdleTimeout", 0))
	if timeout_ms > 0:
		_create_param_pill(enemy_behavior_flow_tactics, "⏱️", "Timeout Abandono: %s" % _format_ms_to_sec(float(timeout_ms)), Color(0.85, 0.75, 0.95))

	if cfg.has("visionRange") and int(cfg.visionRange) > 0:
		_create_param_pill(enemy_behavior_flow_tactics, "🎯", "Visión: %s px" % _format_number(int(cfg.visionRange)), Color(0.3, 0.85, 1.0))

	if cfg.has("leashRange") and int(cfg.leashRange) > 0:
		_create_param_pill(enemy_behavior_flow_tactics, "🏠", "Retorno al Spawn: %s px" % _format_number(int(cfg.leashRange)), Color(0.4, 0.92, 0.6))

	# 2. Supervivencia y Regeneración Fuera de Combate (Cero hardcodeo: solo si está configurada en > 0)
	var hp_regen = float(cfg.get("hpRegenPercent", 0.0))
	var sh_regen = float(cfg.get("shieldRegenPercent", 0.0))

	var has_shield = float(cfg.get("shield", 0.0)) > 0.0
	if is_instance_valid(target) and "max_shield" in target:
		has_shield = has_shield or float(target.max_shield) > 0.0
	elif is_instance_valid(target_node) and "max_shield" in target_node:
		has_shield = has_shield or float(target_node.max_shield) > 0.0

	if not has_shield:
		sh_regen = 0.0

	if hp_regen > 0.0 or sh_regen > 0.0:
		var int_ms = float(cfg.get("regenIntervalMs", 1000.0))
		var int_str = _format_ms_to_sec(int_ms)
		if int_ms <= 0.0: int_str = "1s"

		if hp_regen > 0.0:
			_create_param_pill(enemy_behavior_flow_regen, "💚", "Regen Casco (Fuera de Combate): %s%% / %s" % [_format_float_clean(hp_regen), int_str], Color(0.3, 0.95, 0.45))

		if sh_regen > 0.0:
			_create_param_pill(enemy_behavior_flow_regen, "🛡️", "Regen Escudo (Fuera de Combate): %s%% / %s" % [_format_float_clean(sh_regen), int_str], Color(0.2, 0.85, 1.0))

		var delay_ms = 0.0
		if cfg.has("regenDelayMs"):
			delay_ms = float(cfg.regenDelayMs)
		elif cfg.has("regenDelaySec"):
			delay_ms = float(cfg.regenDelaySec) * 1000.0

		if delay_ms > 0.0:
			_create_param_pill(enemy_behavior_flow_regen, "⏳", "Espera sin daño para curar: %s" % _format_ms_to_sec(delay_ms), Color(1.0, 0.8, 0.3))

	var has_tactics = enemy_behavior_flow_tactics.get_child_count() > 0
	var has_regen = enemy_behavior_flow_regen.get_child_count() > 0
	enemy_behavior_flow_tactics.visible = has_tactics
	enemy_behavior_flow_regen.visible = has_regen
	enemy_behavior_panel.visible = has_tactics or has_regen


func _clear_3d_enemy_preview():
	if is_instance_valid(_enemy_model_holder):
		for child in _enemy_model_holder.get_children():
			child.queue_free()


func _update_3d_enemy_preview(target: Node, cfg: Dictionary):
	if not is_instance_valid(_enemy_model_holder):
		return

	var glb_path = ""
	if target.has_meta("current_glb"):
		glb_path = str(target.get_meta("current_glb"))

	if glb_path == "":
		var model_val = cfg.get("assetPath", cfg.get("model", cfg.get("mesh", "")))
		if model_val != "" and ResourceLoader.exists(str(model_val)):
			glb_path = str(model_val)

	if glb_path == "":
		if "glb_path" in target and target.glb_path != "":
			glb_path = str(target.glb_path)
		elif "model_path" in target and target.model_path != "":
			glb_path = str(target.model_path)

	if glb_path == "":
		var raw_val = target.get("raw_entity_type") if "raw_entity_type" in target else (target.get("entity_type") if "entity_type" in target else "1")
		var raw_t = _format_id(str(raw_val if raw_val != null else "1"))
		var possible_path = "res://assets/Enemigos/3D/Enemigo" + raw_t.split("-")[0] + "/Enemigo" + raw_t.split("-")[0] + ".glb"
		if ResourceLoader.exists(possible_path):
			glb_path = possible_path

	if glb_path == "" or not ResourceLoader.exists(glb_path):
		_clear_3d_enemy_preview()
		_last_previewed_glb = ""
		if is_instance_valid(_enemy_viewport_container):
			_enemy_viewport_container.visible = false
		if is_instance_valid(enemy_avatar_rect):
			enemy_avatar_rect.visible = true
		return

	if is_instance_valid(_enemy_viewport_container):
		_enemy_viewport_container.visible = true
	if is_instance_valid(enemy_avatar_rect):
		enemy_avatar_rect.visible = false

	if glb_path == _last_previewed_glb and _enemy_model_holder.get_child_count() > 0:
		return

	_clear_3d_enemy_preview()
	_last_previewed_glb = glb_path
	_enemy_model_holder.rotation_degrees = Vector3.ZERO

	var model_scene = null
	if get_node_or_null("/root/VFXSystem") and VFXSystem.has_method("get_cached_resource"):
		model_scene = VFXSystem.get_cached_resource(glb_path)
	else:
		model_scene = load(glb_path)

	if model_scene:
		var model = model_scene.instantiate()
		for child in model.find_children("*", "Light3D", true):
			child.queue_free()

		_enemy_model_holder.add_child(model)

		var aabb = AABB()
		var first = true
		for mesh in model.find_children("*", "MeshInstance3D", true):
			if first:
				aabb = mesh.get_aabb()
				first = false
			else:
				aabb = aabb.merge(mesh.get_aabb())

		var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		var scale_ui = 1.0
		if max_dim > 0.001:
			scale_ui = 1.25 / max_dim

		model.scale = Vector3.ONE * scale_ui
		model.position = -aabb.get_center() * scale_ui

		var applied_rot = Vector3(0, 180, 0)
		if is_instance_valid(target):
			if "_3d_model" in target and is_instance_valid(target._3d_model) and target._3d_model.get_child_count() > 0:
				var orig_mesh = target._3d_model.get_child(0)
				if is_instance_valid(orig_mesh):
					applied_rot = orig_mesh.rotation_degrees
			elif "model_node" in target and is_instance_valid(target.model_node):
				applied_rot = target.model_node.rotation_degrees
			elif target.has_meta("rot_y_deg") or target.has_meta("rotY"):
				var r_y = float(target.get_meta("rot_y_deg") if target.has_meta("rot_y_deg") else target.get_meta("rotY", 0.0))
				applied_rot = Vector3(0, r_y, 0)
			elif "rot_y" in target:
				applied_rot = Vector3(0, float(target.rot_y), 0)

		model.rotation_degrees = applied_rot
		_make_preview_materials_unshaded(model)


func _make_preview_materials_unshaded(node: Node):
	if not is_instance_valid(node): return
	var stack = [node]
	while stack.size() > 0:
		var curr = stack.pop_back()
		if curr is MeshInstance3D:
			var mat_count = curr.get_surface_override_material_count()
			if mat_count == 0 and curr.mesh:
				mat_count = curr.mesh.get_surface_count()
			for i in range(mat_count):
				var mat = curr.get_active_material(i)
				if mat and mat is BaseMaterial3D:
					var dup_mat = mat.duplicate()
					dup_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					curr.set_surface_override_material(i, dup_mat)
		for child in curr.get_children():
			stack.append(child)


func _render_enemy_rewards(cfg: Dictionary):
	for c in enemy_rewards_flow.get_children():
		c.queue_free()

	var pts = int(cfg.get("rankingPoints", 0))
	var re_exp = int(cfg.get("rewardExp", 0))
	var re_hubs = int(cfg.get("rewardHubs", 0))
	var re_ohcu = int(cfg.get("rewardOhcu", 0))
	var chest_pct = int(float(cfg.get("chestDropChance", 0.0)) * 100.0)

	var has_rewards = pts > 0 or re_exp > 0 or re_hubs > 0 or re_ohcu > 0 or chest_pct > 0
	enemy_rewards_panel.visible = has_rewards
	if not has_rewards: return

	if re_exp > 0:
		_create_param_pill(enemy_rewards_flow, "⭐", "EXP +%s" % _format_number(re_exp), Color(0.5, 0.95, 0.75))
	if re_hubs > 0:
		_create_param_pill(enemy_rewards_flow, "💰", "Hubs +%s" % _format_number(re_hubs), Color(0.98, 0.85, 0.2))
	if re_ohcu > 0:
		_create_param_pill(enemy_rewards_flow, "🔮", "Ohcu +%s" % _format_number(re_ohcu), Color(0.85, 0.55, 1.0))
	if chest_pct > 0:
		_create_param_pill(enemy_rewards_flow, "📦", "Drop Cofre: %d%%" % chest_pct, Color(0.4, 0.85, 1.0))
	if pts > 0:
		_create_param_pill(enemy_rewards_flow, "🏆", "Ranking: +%s pts" % _format_number(pts), Color(1.0, 0.75, 0.25))


func _render_enemy_mechanics(cfg: Dictionary):
	for c in mechanics_cards_container.get_children():
		c.queue_free()

	var mechanics_list = cfg.get("mechanics", [])
	var defense_list = cfg.get("defenseMechanics", [])
	var movement_list = cfg.get("movementPhases", [])

	var total_count = 0
	if typeof(mechanics_list) == TYPE_ARRAY: total_count += mechanics_list.size()
	if typeof(defense_list) == TYPE_ARRAY: total_count += defense_list.size()
	if typeof(movement_list) == TYPE_ARRAY: total_count += movement_list.size()

	enemy_mechanics_count_label.text = "⚙️ MECÁNICAS Y HABILIDADES DE COMBATE (%d)" % total_count

	if total_count == 0:
		var empty_p = PanelContainer.new()
		var sb_e = StyleBoxFlat.new()
		sb_e.bg_color = Color(0.015, 0.04, 0.07, 0.7)
		sb_e.border_width_left = 1; sb_e.border_width_top = 1
		sb_e.border_width_right = 1; sb_e.border_width_bottom = 1
		sb_e.border_color = Color(0.2, 0.6, 0.8, 0.35)
		sb_e.set_corner_radius_all(6)
		empty_p.add_theme_stylebox_override("panel", sb_e)

		var m_e = MarginContainer.new()
		m_e.add_theme_constant_override("margin_left", 14)
		m_e.add_theme_constant_override("margin_right", 14)
		m_e.add_theme_constant_override("margin_top", 14)
		m_e.add_theme_constant_override("margin_bottom", 14)
		empty_p.add_child(m_e)

		var lbl_e = Label.new()
		lbl_e.text = "ℹ️ Esta unidad no tiene mecánicas complejas configuradas en el Admin Dashboard.\nUtiliza combate estándar con cañones láser y maniobras básicas de patrulla."
		lbl_e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_e.add_theme_font_size_override("font_size", 10)
		lbl_e.modulate = Color(0.55, 0.8, 0.95, 0.8)
		m_e.add_child(lbl_e)
		mechanics_cards_container.add_child(empty_p)
		return

	# 1. MECÁNICAS OFENSIVAS / ATAQUE
	if typeof(mechanics_list) == TYPE_ARRAY:
		for m_data in mechanics_list:
			if typeof(m_data) == TYPE_DICTIONARY:
				_create_mechanic_card(m_data, "attack")

	# 2. MECÁNICAS DEFENSIVAS
	if typeof(defense_list) == TYPE_ARRAY:
		for d_data in defense_list:
			if typeof(d_data) == TYPE_DICTIONARY:
				_create_mechanic_card(d_data, "defense")

	# 3. FASES DE MOVIMIENTO / CEREBRO TÁCTICO
	if typeof(movement_list) == TYPE_ARRAY:
		for mov_data in movement_list:
			if typeof(mov_data) == TYPE_DICTIONARY:
				_create_mechanic_card(mov_data, "movement")


func _create_mechanic_card(data: Dictionary, category: String):
	var m_type = str(data.get("type", "generica")).strip_edges()
	var lib = _get_mechanics_lib(category)
	var lib_entry = lib.get(m_type, {})

	# Resolver Etiqueta, Icono y Descripción
	var title = str(lib_entry.get("label", m_type.replace("_", " ").capitalize()))
	var desc = str(lib_entry.get("desc", ""))
	var icon = str(lib_entry.get("icon", "⚔️" if category == "attack" else ("🛡️" if category == "defense" else "🏃")))

	if desc == "":
		if category == "attack": desc = "Mecánica ofensiva configurada en el Admin Dashboard."
		elif category == "defense": desc = "Mecánica defensiva configurada en el Admin Dashboard."
		else: desc = "Comportamiento táctico de desplazamiento."

	# Color de categoría
	var cat_color = Color(0.98, 0.58, 0.2) # Ofensiva (ámbar)
	var cat_tag = "OFENSIVA"
	if category == "defense":
		cat_color = Color(0.2, 0.8, 1.0) # Defensiva (cian)
		cat_tag = "DEFENSIVA"
	elif category == "movement":
		cat_color = Color(0.35, 0.92, 0.5) # Movimiento (verde)
		cat_tag = "MOVIMIENTO"

	# Tarjeta Principal
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_card = StyleBoxFlat.new()
	sb_card.bg_color = Color(0.012, 0.032, 0.058, 0.95)
	sb_card.border_width_left = 2; sb_card.border_width_top = 1
	sb_card.border_width_right = 1; sb_card.border_width_bottom = 1
	sb_card.border_color = cat_color
	sb_card.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", sb_card)

	var card_margin = MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 12)
	card_margin.add_theme_constant_override("margin_right", 12)
	card_margin.add_theme_constant_override("margin_top", 8)
	card_margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(card_margin)

	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 6)
	card_margin.add_child(card_vbox)

	# Fila 1: Icono, Nombre de la Habilidad y Badges de Tipo/Disparo
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	card_vbox.add_child(header_row)

	var icon_lbl = Label.new()
	icon_lbl.text = icon
	icon_lbl.add_theme_font_size_override("font_size", 13)
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(icon_lbl)

	var name_lbl = Label.new()
	name_lbl.text = title
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", cat_color)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(name_lbl)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	# Badge de Categoría
	var badge_cat = _create_badge_panel(cat_color, Color(cat_color.r * 0.2, cat_color.g * 0.2, cat_color.b * 0.2, 0.8))
	badge_cat.get_node("Margin/Label").text = "[" + cat_tag + "]"
	header_row.add_child(badge_cat)

	# Badge de Modo de Activación
	var act_mode = str(data.get("activationMode", "")).to_lower().strip_edges()
	var act_hps = data.get("activationHPs", data.get("activationHP"))
	var act_interval = float(data.get("activationIntervalMs", 0.0))

	if act_mode == "hp":
		var hps_str = _format_number_or_float(act_hps) if act_hps != null else "50"
		var badge_act = _create_badge_panel(Color(1.0, 0.4, 0.4), Color(0.25, 0.05, 0.05, 0.9))
		badge_act.get_node("Margin/Label").text = "🩸 " + hps_str + "% HP"
		header_row.add_child(badge_act)
	elif act_mode == "time":
		var badge_act = _create_badge_panel(Color(0.35, 0.85, 1.0), Color(0.04, 0.15, 0.22, 0.9))
		if act_interval > 0:
			badge_act.get_node("Margin/Label").text = "⏳ TRAS " + _format_ms_to_sec(act_interval).to_upper()
		else:
			badge_act.get_node("Margin/Label").text = "⏳ EN COMBATE"
		header_row.add_child(badge_act)
	elif act_mode == "" and act_hps != null and (not (act_hps is Array and act_hps.is_empty())) and str(act_hps) != "":
		var badge_act = _create_badge_panel(Color(1.0, 0.4, 0.4), Color(0.25, 0.05, 0.05, 0.9))
		badge_act.get_node("Margin/Label").text = "🩸 " + _format_number_or_float(act_hps) + "% HP"
		header_row.add_child(badge_act)

	# Fila 2: Descripción Explicativa Detallada
	var desc_lbl = Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.modulate = Color(0.85, 0.92, 0.98, 0.85)
	card_vbox.add_child(desc_lbl)

	# Fila 3: Parámetros Clave (Pills con Daño, Enfriamiento, Tiempos, etc.)
	var params_flow = HFlowContainer.new()
	params_flow.add_theme_constant_override("h_separation", 6)
	params_flow.add_theme_constant_override("v_separation", 4)
	card_vbox.add_child(params_flow)

	# --- Modo y Condiciones de Activación Explicadas ---
	if act_mode == "hp":
		var hps_str = _format_number_or_float(act_hps) if act_hps != null else "50"
		_create_param_pill(params_flow, "🩸", "Activación: Al caer al %s%% de Casco" % hps_str, Color(1.0, 0.45, 0.45))
	elif act_mode == "time":
		if act_interval > 0:
			_create_param_pill(params_flow, "⏳", "Activación: Tras %s en combate" % _format_ms_to_sec(act_interval), Color(0.35, 0.85, 1.0))
		else:
			var s_delay = float(data.get("startDelay", 0.0))
			if s_delay > 0:
				_create_param_pill(params_flow, "⏳", "Activación: Tras %s de iniciar combate" % _format_ms_to_sec(s_delay), Color(0.35, 0.85, 1.0))
			else:
				_create_param_pill(params_flow, "⏳", "Activación: Por tiempo en combate (respeta cadencia)", Color(0.35, 0.85, 1.0))
	elif act_mode == "" and act_hps != null and (not (act_hps is Array and act_hps.is_empty())) and str(act_hps) != "":
		_create_param_pill(params_flow, "🩸", "Activación: Al caer al %s%% de Casco" % _format_number_or_float(act_hps), Color(1.0, 0.45, 0.45))

	# --- Parámetros de Daño ---
	var dmg = data.get("damage", data.get("bulletDamage", data.get("ray_damage", data.get("trapDamage"))))
	if dmg != null and float(dmg) > 0:
		_create_param_pill(params_flow, "💥", "Daño: %s" % _format_number_or_float(dmg), Color(0.98, 0.4, 0.4))

	var dot_dmg = data.get("zoneDamage", data.get("damage_per_tick", data.get("rootDps")))
	if dot_dmg != null and float(dot_dmg) > 0:
		_create_param_pill(params_flow, "🔥", "Daño/Tick: %s" % _format_number_or_float(dot_dmg), Color(0.98, 0.6, 0.2))

	var ret_dmg = data.get("returnDamage")
	if ret_dmg != null and float(ret_dmg) > 0:
		_create_param_pill(params_flow, "↩️", "Daño Retorno: %s" % _format_number_or_float(ret_dmg), Color(0.95, 0.5, 0.3))

	# --- Cooldown / Cadencia ---
	var cd = data.get("cooldown")
	var frate = data.get("fireRate")
	if cd != null and float(cd) > 0:
		_create_param_pill(params_flow, "⏱️", "Cadencia: %s" % _format_ms_to_sec(float(cd)), Color(1.0, 0.8, 0.2))
	elif frate != null and float(frate) > 0:
		_create_param_pill(params_flow, "⏱️", "Cadencia: %s" % _format_ms_to_sec(float(frate)), Color(1.0, 0.8, 0.2))

	# --- Tiempo de Casteo ---
	var cast_ms = float(data.get("castTimeMs", 0.0))
	var cast_interr = bool(data.get("castInterruptible", true))
	if cast_ms > 0:
		var interr_txt = "Interrumpible" if cast_interr else "Ininterrumpible"
		_create_param_pill(params_flow, "⏳", "Casteo: %s (%s)" % [_format_ms_to_sec(cast_ms), interr_txt], Color(0.3, 0.85, 1.0))
	elif category == "attack" and m_type != "laser":
		_create_param_pill(params_flow, "⚡", "Instantáneo", Color(0.4, 0.9, 0.7))

	# --- Rango / Área / Ángulo ---
	var frange = data.get("fireRange", data.get("chargeRange"))
	if frange != null and float(frange) > 0:
		_create_param_pill(params_flow, "🎯", "Alcance: %s px" % _format_number_or_float(frange), Color(0.35, 0.85, 1.0))

	var rad = data.get("radius", data.get("areaRadius", data.get("safeRadius", data.get("trapRadius"))))
	if rad != null and float(rad) > 0:
		_create_param_pill(params_flow, "🔘", "Radio: %s px" % _format_number_or_float(rad), Color(0.4, 0.75, 1.0))

	var cone_a = data.get("coneAngle")
	if cone_a != null and float(cone_a) > 0:
		_create_param_pill(params_flow, "📐", "Cono: %s°" % _format_number_or_float(cone_a), Color(0.9, 0.7, 0.3))

	# --- Control de Masas y Debuffs ---
	var stun_ms = float(data.get("stunDuration", 0.0))
	if stun_ms > 0:
		_create_param_pill(params_flow, "💫", "Aturdimiento: %s" % _format_ms_to_sec(stun_ms), Color(0.95, 0.85, 0.2))

	var slow_amt = data.get("slowAmount", data.get("slow_amount", data.get("slowPercentage")))
	var slow_dur = float(data.get("slowDuration", 0.0))
	if slow_amt != null and float(slow_amt) > 0:
		var dur_txt = " (%s)" % _format_ms_to_sec(slow_dur) if slow_dur > 0 else ""
		_create_param_pill(params_flow, "❄️", "Slow: %s%%%s" % [_format_number_or_float(slow_amt), dur_txt], Color(0.4, 0.85, 1.0))

	var root_dur = float(data.get("rootDuration", 0.0))
	if root_dur > 0:
		_create_param_pill(params_flow, "🌱", "Enraizamiento: %s" % _format_ms_to_sec(root_dur), Color(0.4, 0.9, 0.5))

	var poly_dur = float(data.get("polyDuration", 0.0))
	if poly_dur > 0:
		_create_param_pill(params_flow, "🗺️", "Polimorfia: %s" % _format_ms_to_sec(poly_dur), Color(0.85, 0.5, 1.0))

	var under_ms = float(data.get("undergroundMs", 0.0))
	if under_ms > 0:
		_create_param_pill(params_flow, "🕳️", "Bajo tierra: %s" % _format_ms_to_sec(under_ms), Color(0.7, 0.55, 0.4))

	var push = data.get("pushForce", data.get("pushOnHit"))
	if push != null and float(push) > 0:
		_create_param_pill(params_flow, "💨", "Empuje: Fuerza %s" % _format_number_or_float(push), Color(0.7, 0.9, 1.0))

	if bool(data.get("isHoming", false)) == true:
		_create_param_pill(params_flow, "🎯", "Proyectil Teledirigido", Color(0.95, 0.45, 0.75))

	var bursts = data.get("burstShots", data.get("projectileCount", data.get("bulletCount", data.get("meteorCount", data.get("bombCount")))))
	if bursts != null and float(bursts) > 1:
		_create_param_pill(params_flow, "💥", "Proyectiles: x%s" % _format_number_or_float(bursts), Color(0.98, 0.65, 0.2))

	# --- Mecánicas Defensivas / Curación ---
	var heal_amt = data.get("healAmount", data.get("bossHealPercent"))
	if heal_amt != null and float(heal_amt) > 0:
		_create_param_pill(params_flow, "💚", "Curación: %s" % _format_number_or_float(heal_amt), Color(0.3, 0.95, 0.5))

	var red_pct = data.get("reductionPercentage")
	if red_pct != null and float(red_pct) > 0:
		_create_param_pill(params_flow, "🛡️", "Reducción: %s%%" % _format_number_or_float(red_pct), Color(0.2, 0.85, 1.0))

	var dur_ms = float(data.get("duration", 0.0))
	if dur_ms > 0 and category != "movement":
		_create_param_pill(params_flow, "⏱️", "Duración: %s" % _format_ms_to_sec(dur_ms), Color(0.6, 0.8, 1.0))

	var steal_amt = data.get("stealAmount")
	if steal_amt != null and float(steal_amt) > 0:
		_create_param_pill(params_flow, "💠", "Drenaje/Robo: %s" % _format_number_or_float(steal_amt), Color(0.3, 0.95, 0.8))

	var pillars = data.get("pillarCount")
	if pillars != null and float(pillars) > 0:
		_create_param_pill(params_flow, "🏛️", "Pilares: %s" % _format_number_or_float(pillars), Color(0.85, 0.7, 1.0))

	var clones = data.get("cloneCount")
	if clones != null and float(clones) > 0:
		_create_param_pill(params_flow, "👥", "Clones: %s" % _format_number_or_float(clones), Color(0.7, 0.85, 1.0))

	# --- Fases de Movimiento ---
	if category == "movement":
		var m_spd = data.get("speed")
		if m_spd != null and float(m_spd) > 0:
			_create_param_pill(params_flow, "🏃", "Vel. Fase: %s px/s" % _format_number_or_float(m_spd), Color(0.35, 0.95, 0.5))

		var id_dist = data.get("idealDist", data.get("stopDist"))
		if id_dist != null and float(id_dist) > 0:
			_create_param_pill(params_flow, "📏", "Distancia: %s px" % _format_number_or_float(id_dist), Color(0.6, 0.85, 1.0))

		var o_rad = data.get("orbitRadius")
		if o_rad != null and float(o_rad) > 0:
			_create_param_pill(params_flow, "🔄", "Radio Órbita: %s px" % _format_number_or_float(o_rad), Color(0.4, 0.9, 0.8))

	mechanics_cards_container.add_child(card)


func _create_param_pill(parent: Control, icon_str: String, text_str: String, col: Color):
	var p = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.15, col.g * 0.15, col.b * 0.15, 0.85)
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = Color(col.r, col.g, col.b, 0.55)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	m.add_theme_constant_override("margin_top", 2)
	m.add_theme_constant_override("margin_bottom", 2)
	p.add_child(m)

	var lbl = Label.new()
	lbl.text = icon_str + " " + text_str
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate = Color(0.9, 0.95, 1.0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	m.add_child(lbl)

	parent.add_child(p)


# ==============================================================================
# RESOLUCIÓN AUTORITATIVA DE CONFIGURACIONES Y LIBRERÍAS
# ==============================================================================
func _get_enemy_config(target: Node) -> Dictionary:
	var raw_t = str(target.get("raw_entity_type")) if "raw_entity_type" in target else ""
	var num_t = str(target.get("entity_type")) if "entity_type" in target else ""

	var enemy_models: Dictionary = {}
	if NetworkManager and NetworkManager.server_config and NetworkManager.server_config.has("enemyModels"):
		enemy_models = NetworkManager.server_config["enemyModels"]
	elif GameConstants and "ENEMY_MODELS" in GameConstants:
		enemy_models = GameConstants.ENEMY_MODELS

	var cfg: Dictionary = {}
	if raw_t != "" and enemy_models.has(raw_t):
		cfg = enemy_models[raw_t]
	elif num_t != "" and enemy_models.has(num_t):
		cfg = enemy_models[num_t]
	elif raw_t.contains("-"):
		var base_t = raw_t.split("-")[0]
		if enemy_models.has(base_t):
			cfg = enemy_models[base_t]
	elif "entity_id" in target and enemy_models.has(str(target.get("entity_id"))):
		cfg = enemy_models[str(target.get("entity_id"))]

	return cfg


func _get_mechanics_lib(category: String) -> Dictionary:
	var res: Dictionary = {}
	if category == "attack":
		res = _default_mechanics_lib.duplicate()
		if NetworkManager and NetworkManager.server_config and NetworkManager.server_config.has("mechanicsLib"):
			for k in NetworkManager.server_config.mechanicsLib:
				res[k] = NetworkManager.server_config.mechanicsLib[k]
		elif GameConstants and "MECHANICS_LIB" in GameConstants:
			for k in GameConstants.MECHANICS_LIB:
				res[k] = GameConstants.MECHANICS_LIB[k]
	elif category == "defense":
		res = _default_defense_lib.duplicate()
		if NetworkManager and NetworkManager.server_config and NetworkManager.server_config.has("defenseLib"):
			for k in NetworkManager.server_config.defenseLib:
				res[k] = NetworkManager.server_config.defenseLib[k]
		elif GameConstants and "DEFENSE_LIB" in GameConstants:
			for k in GameConstants.DEFENSE_LIB:
				res[k] = GameConstants.DEFENSE_LIB[k]
	elif category == "movement":
		res = _default_movement_lib.duplicate()
		if NetworkManager and NetworkManager.server_config and NetworkManager.server_config.has("movementLib"):
			for k in NetworkManager.server_config.movementLib:
				res[k] = NetworkManager.server_config.movementLib[k]
		elif GameConstants and "MOVEMENT_LIB" in GameConstants:
			for k in GameConstants.MOVEMENT_LIB:
				res[k] = GameConstants.MOVEMENT_LIB[k]
	return res


# ==============================================================================
# RESOLUCIÓN DE RECURSOS Y TEXTURAS
# ==============================================================================
func _resolve_item_icon(item: Dictionary) -> String:
	var icon_path = str(item.get("icon", ""))
	var search_id = str(item.get("id", "")).to_lower()
	if icon_path != "" and icon_path != "null" and ResourceLoader.exists(icon_path):
		return icon_path

	var emergency_map = {
		"las1": "res://assets/Armas/Arma1/Arma1.png", "las2": "res://assets/Armas/Arma2/Arma2.png", "las3": "res://assets/Armas/Arma3/Arma3.png",
		"las4": "res://assets/Armas/Arma4/Arma4.png", "las5": "res://assets/Armas/Arma5/Arma5.png", "las6": "res://assets/Armas/Arma6/Arma6.png",
		"sh1": "res://assets/Escudos/Escudo1/Escudo1.png", "sh2": "res://assets/Escudos/Escudo2/Escudo2.png", "sh3": "res://assets/Escudos/Escudo3/Escudo3.png",
		"sh4": "res://assets/Escudos/Escudo4/Escudo4.png", "sh5": "res://assets/Escudos/Escudo5/Escudo5.png", "sh6": "res://assets/Escudos/Escudo6/Escudo6.png",
		"en1": "res://assets/Motores/Motor1/Motor1.png", "en2": "res://assets/Motores/Motor2/Motor2.png", "en3": "res://assets/Motores/Motor3/Motor3.png"
	}
	if emergency_map.has(search_id): return emergency_map[search_id]

	if GameConstants and "SHOP_ITEMS" in GameConstants:
		for cat_key in GameConstants.SHOP_ITEMS:
			var category = GameConstants.SHOP_ITEMS[cat_key]
			if category is Dictionary:
				for sub_key in category:
					var sub_list = category[sub_key]
					if sub_list is Array:
						for shop_item in sub_list:
							if str(shop_item.get("id", "")).to_lower() == search_id:
								var ic = str(shop_item.get("icon", ""))
								if ic != "" and ResourceLoader.exists(ic): return ic
			elif category is Array:
				for shop_item in category:
					if str(shop_item.get("id", "")).to_lower() == search_id:
						var ic = str(shop_item.get("icon", ""))
						if ic != "" and ResourceLoader.exists(ic): return ic

	if search_id.begins_with("las"):
		return "res://assets/Armas/Arma" + search_id.replace("las", "") + "/Arma" + search_id.replace("las", "") + ".png"
	elif search_id.begins_with("sh"):
		return "res://assets/Escudos/Escudo" + search_id.replace("sh", "") + "/Escudo" + search_id.replace("sh", "") + ".png"
	elif search_id.begins_with("en"):
		return "res://assets/Motores/Motor" + search_id.replace("en", "") + "/Motor" + search_id.replace("en", "") + ".png"

	return ""


func _get_item_icon(item: Dictionary) -> Texture2D:
	if item.is_empty(): return null
	var icon_path = _resolve_item_icon(item)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var t = InventoryCache.get_texture(icon_path)
		if t: return t
		return load(icon_path)
	return null


# ==============================================================================
# CONTROL DE VENTANA, ATAJOS Y DRAG
# ==============================================================================
func toggle():
	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_tree().get_first_node_in_group("main_hud")
	var cur_tgt = main_hud._target_entity if (is_instance_valid(main_hud) and "_target_entity" in main_hud) else null

	# Si la ventana está abierta pero el jugador seleccionó un nuevo objetivo, re-inspeccionar en vez de cerrarla
	if is_open and is_instance_valid(cur_tgt) and cur_tgt != target_node:
		inspect_current_target()
	elif is_open:
		close()
	else:
		inspect_current_target()


func close():
	is_open = false
	visible = false
	z_index = 0
	target_node = null
	target_player_node = null
	current_mode = Mode.NONE
	_clear_3d_enemy_preview()
	_last_previewed_glb = ""


func _reposition_window():
	var vp_size = get_viewport_rect().size
	var target_w = min(660.0, vp_size.x * 0.94)
	var target_h = min(680.0, vp_size.y * 0.94)
	window_panel.custom_minimum_size = Vector2(target_w, target_h)
	window_panel.size = Vector2(target_w, target_h)
	var pos_x = max(10.0, (vp_size.x - target_w) / 2.0)
	var pos_y = max(10.0, (vp_size.y - target_h) / 2.0)
	window_panel.position = Vector2(pos_x, pos_y)


func _on_header_gui_input(event: InputEvent):
	var handled = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_offset = window_panel.global_position - event.global_position
		else:
			is_dragging = false
		handled = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			is_dragging = true
			drag_offset = window_panel.global_position - event.position
		else:
			is_dragging = false
		handled = true
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and is_dragging:
		var event_pos = event.global_position if "global_position" in event else event.position
		var new_pos = event_pos + drag_offset
		var vp_size = get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, vp_size.x - window_panel.size.x)
		new_pos.y = clampf(new_pos.y, 0, vp_size.y - window_panel.size.y)
		window_panel.global_position = new_pos
		handled = true

	if handled:
		get_viewport().set_input_as_handled()


func _input(event: InputEvent):
	if not is_open: return

	var focus_node = get_viewport().gui_get_focus_owner()
	if focus_node is LineEdit or focus_node is TextEdit: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _notify_user(msg: String, type: String = "info"):
	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_tree().get_first_node_in_group("main_hud")
	if is_instance_valid(main_hud) and main_hud.has_method("notify"):
		main_hud.notify(msg, type)
	else:
		print("[INSPECT] ", msg)


func _format_id(raw_id: String) -> String:
	raw_id = raw_id.strip_edges()
	if raw_id.ends_with(".0"):
		raw_id = raw_id.substr(0, raw_id.length() - 2)
	elif raw_id.contains(".0-"):
		raw_id = raw_id.replace(".0-", "-")
	elif raw_id.is_valid_float():
		var f = raw_id.to_float()
		if is_equal_approx(f, floor(f)):
			raw_id = str(int(f))
	return raw_id


func _format_number(val: int) -> String:
	var s = str(val)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count == 3 and i > 0 and s[i - 1] != "-":
			result = "," + result
			count = 0
	return result


func _format_float_clean(val: float) -> String:
	var rounded = snappedf(val, 0.1)
	if is_equal_approx(rounded, floor(rounded)):
		return str(int(rounded))
	var s = str(rounded)
	if s.ends_with(".0"):
		return s.substr(0, s.length() - 2)
	return s


func _format_seconds(sec: float) -> String:
	if sec <= 0.0: return "0s"
	return _format_float_clean(sec) + "s"


func _format_ms_to_sec(ms: float) -> String:
	if ms <= 0.0: return "0s"
	return _format_seconds(ms / 1000.0)


func _format_number_or_float(val) -> String:
	if val == null: return "0"
	if typeof(val) == TYPE_ARRAY:
		var parts: Array = []
		for item in val:
			parts.append(_format_number_or_float(item))
		return " / ".join(parts)
	if typeof(val) == TYPE_DICTIONARY:
		return str(val)
	if typeof(val) == TYPE_BOOL:
		return "Sí" if val else "No"
	if typeof(val) == TYPE_INT:
		return _format_number(val)
	if typeof(val) == TYPE_FLOAT:
		if is_equal_approx(val, floor(val)):
			return _format_number(int(val))
		return _format_float_clean(val)
	if typeof(val) == TYPE_STRING:
		var s_val = str(val).strip_edges()
		if s_val.is_valid_float():
			var num_f = s_val.to_float()
			if is_equal_approx(num_f, floor(num_f)):
				return _format_number(int(num_f))
			return _format_float_clean(num_f)
		return s_val

	var s_fallback = str(val).strip_edges()
	if s_fallback.is_valid_float():
		var fallback_num = s_fallback.to_float()
		if is_equal_approx(fallback_num, floor(fallback_num)):
			return _format_number(int(fallback_num))
		return _format_float_clean(fallback_num)
	return s_fallback


func _get_action_key_display(action: String, default_fallback: String) -> String:
	if InputMap.has_action(action):
		var events = InputMap.action_get_events(action)
		if events.size() > 0 and events[0] != null:
			var ev = events[0]
			if ev is InputEventKey:
				var kc = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
				if kc != 0:
					var s = OS.get_keycode_string(kc)
					if s != "": return s.to_upper()
				var txt = ev.as_text().replace(" (Physical)", "").strip_edges()
				if txt.contains("Physical"): txt = txt.replace("Physical", "").strip_edges()
				if txt != "": return txt.to_upper()
			elif ev is InputEventMouseButton:
				return ("M" + str(ev.button_index)).to_upper()

	if SettingsManager and "default_keys" in SettingsManager and SettingsManager.default_keys.has(action):
		var def_val = SettingsManager.default_keys[action]
		if typeof(def_val) == TYPE_INT and def_val != 0:
			var s = OS.get_keycode_string(def_val)
			if s != "": return s.to_upper()

	return default_fallback.to_upper()
