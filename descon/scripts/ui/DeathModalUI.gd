extends CanvasLayer

# DeathModalUI.gd (v1.0 - Modal de Muerte y Resurrección AAA)
# Interfaz espacial pulida con cuenta regresiva de 120s y opciones tácticas.

var countdown_ms: float = 120000.0
var timer_active: bool = false
var is_open: bool = false

var control_root: Control = null
var overlay: ColorRect = null
var panel_container: PanelContainer = null
var label_title: Label = null
var label_timer: Label = null
var label_status: Label = null
var btn_lobby: Button = null
var btn_wait: Button = null

var local_player: Node = null

func _ready():
	name = "DeathModalUI"
	layer = 110 # Por encima del HUD normal de juego (Layer 100)
	
	# 1. Fondo difuminado/oscurecido con un tinte violeta/rojizo de peligro
	overlay = ColorRect.new()
	overlay.color = Color(0.04, 0.01, 0.05, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# 2. Contenedor raíz centrado
	control_root = Control.new()
	control_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(control_root)
	
	overlay.visible = false
	overlay.modulate.a = 0.0
	control_root.visible = false
	
	# 3. Modal Container (PanelContainer)
	panel_container = PanelContainer.new()
	panel_container.custom_minimum_size = Vector2(460, 260)
	# Centrar el panel respecto al control raíz
	panel_container.position = Vector2(-230, -130)
	
	# Estética Sci-Fi Neon (Borde magenta neón, fondo glassmorphism oscuro)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.01, 0.07, 0.98)
	sb.border_width_top = 4
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(1.0, 0.1, 0.45, 0.95) # Magenta neón vibrante
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(1.0, 0.0, 0.4, 0.12)
	sb.shadow_size = 25
	panel_container.add_theme_stylebox_override("panel", sb)
	control_root.add_child(panel_container)
	
	# 4. Estructura interna
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_top", 20)
	margin_container.add_theme_constant_override("margin_bottom", 20)
	margin_container.add_theme_constant_override("margin_left", 25)
	margin_container.add_theme_constant_override("margin_right", 25)
	panel_container.add_child(margin_container)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin_container.add_child(vbox)
	
	# A) Título de Alerta (Rojo/Magenta neón parpadeante sutil)
	label_title = Label.new()
	label_title.text = "¡SISTEMAS CRÍTICOS: NAVE DESTRUIDA!"
	label_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_title.add_theme_color_override("font_color", Color(1.0, 0.2, 0.3))
	label_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(label_title)
	
	# B) Cuenta regresiva
	label_timer = Label.new()
	label_timer.text = "02:00"
	label_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_timer.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	label_timer.add_theme_font_size_override("font_size", 32)
	vbox.add_child(label_timer)
	
	# C) Mensaje de estado descriptivo
	label_status = Label.new()
	label_status.text = "Selecciona una opción antes del auto-retorno al Lobby."
	label_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_status.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	label_status.add_theme_font_size_override("font_size", 11)
	vbox.add_child(label_status)
	
	# D) Fila de Botones
	var hbox_btns = HBoxContainer.new()
	hbox_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_btns.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox_btns)
	
	# Botón Revivir en Lobby
	btn_lobby = Button.new()
	btn_lobby.text = "REVIVIR EN LOBBY"
	btn_lobby.custom_minimum_size = Vector2(175, 40)
	btn_lobby.pressed.connect(_on_revive_lobby_pressed)
	
	var sb_lobby = StyleBoxFlat.new()
	sb_lobby.bg_color = Color(0.0, 0.4, 0.5, 0.35)
	sb_lobby.border_width_left = 1
	sb_lobby.border_width_right = 1
	sb_lobby.border_width_top = 1
	sb_lobby.border_width_bottom = 1
	sb_lobby.border_color = Color(0.0, 0.8, 1.0)
	sb_lobby.corner_radius_top_left = 4
	sb_lobby.corner_radius_top_right = 4
	sb_lobby.corner_radius_bottom_left = 4
	sb_lobby.corner_radius_bottom_right = 4
	btn_lobby.add_theme_stylebox_override("normal", sb_lobby)
	
	var sb_lobby_h = sb_lobby.duplicate()
	sb_lobby_h.bg_color = Color(0.0, 0.5, 0.6, 0.6)
	btn_lobby.add_theme_stylebox_override("hover", sb_lobby_h)
	
	hbox_btns.add_child(btn_lobby)
	
	# Botón Esperar Resurrección
	btn_wait = Button.new()
	btn_wait.text = "ESPERAR ALIADO"
	btn_wait.custom_minimum_size = Vector2(175, 40)
	btn_wait.pressed.connect(_on_wait_pressed)
	
	var sb_wait = StyleBoxFlat.new()
	sb_wait.bg_color = Color(0.4, 0.0, 0.4, 0.35)
	sb_wait.border_width_left = 1
	sb_wait.border_width_right = 1
	sb_wait.border_width_top = 1
	sb_wait.border_width_bottom = 1
	sb_wait.border_color = Color(0.9, 0.1, 0.9)
	sb_wait.corner_radius_top_left = 4
	sb_wait.corner_radius_top_right = 4
	sb_wait.corner_radius_bottom_left = 4
	sb_wait.corner_radius_bottom_right = 4
	btn_wait.add_theme_stylebox_override("normal", sb_wait)
	
	var sb_wait_h = sb_wait.duplicate()
	sb_wait_h.bg_color = Color(0.5, 0.0, 0.5, 0.6)
	btn_wait.add_theme_stylebox_override("hover", sb_wait_h)
	
	hbox_btns.add_child(btn_wait)

func open_modal():
	local_player = get_tree().get_first_node_in_group("player")
	countdown_ms = 120000.0
	timer_active = true
	is_open = true
	
	overlay.visible = true
	control_root.visible = true
	btn_lobby.visible = true
	btn_wait.visible = true
	label_timer.visible = true
	label_status.text = "Selecciona una opción antes del auto-retorno al Lobby."
	
	# Efecto de pulsación/entrada suave
	control_root.scale = Vector2(0.85, 0.85)
	overlay.modulate.a = 0.0
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(control_root, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close_modal():
	if is_open:
		is_open = false
		timer_active = false
		
		var tw = create_tween().set_parallel(true)
		tw.tween_property(overlay, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(control_root, "scale", Vector2(0.85, 0.85), 0.2).set_trans(Tween.TRANS_SINE)
		
		await tw.finished
		if not is_open:
			overlay.visible = false
			control_root.visible = false

func _process(delta):
	if is_open and timer_active:
		countdown_ms -= delta * 1000.0
		if countdown_ms <= 0:
			countdown_ms = 0
			timer_active = false
			_revive_at_lobby()
		else:
			_update_timer_display()
			
		# Añadir parpadeo sutil neón rojo al título
		var pulse = 0.8 + sin(Time.get_ticks_msec() * 0.006) * 0.2
		label_title.modulate.a = pulse

func _update_timer_display():
	var total_secs = int(ceil(countdown_ms / 1000.0))
	var mins = int(float(total_secs) / 60.0)
	var secs = total_secs % 60
	label_timer.text = "%02d:%02d" % [mins, secs]

func _on_revive_lobby_pressed():
	_revive_at_lobby()

func _revive_at_lobby():
	if is_instance_valid(local_player):
		local_player.current_zone = 1
		local_player.respawn()
	close_modal()

func _on_wait_pressed():
	# Detener el cronómetro de retorno y esperar por la resurrección de un aliado, pero mantener el botón del lobby disponible
	timer_active = false
	label_timer.visible = false
	btn_wait.visible = false
	label_status.text = "Transmisor de baliza activo. Esperando resurrección de aliado..."
	label_status.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4))
