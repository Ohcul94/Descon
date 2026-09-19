extends PanelContainer

# PartyMemberRow.gd (Aliados v1.54)
# Muestra HP/SH, Datos numéricos y ROL de aliados en el HUD.

@onready var name_label = $VBox/Header/Name
@onready var role_icon = $VBox/Header/RoleIcon
@onready var hp_bar = $VBox/HPBar
@onready var sh_bar = $VBox/SHBar
@onready var stats_label = $VBox/StatsText

var member_id = ""
var member_name = ""
var kick_btn: Button = null
var role_menu: PopupPanel = null
var _role_icon_connected = false

var ROLE_COLORS = {
	"tank": Color(0.3, 0.6, 1.0),
	"healer": Color(0.2, 0.9, 0.3),
	"buffer": Color(1.0, 0.85, 0.2),
	"dps": Color(0.9, 0.2, 0.2)
}

func setup(id: String, p_name: String):
	member_id = id
	member_name = p_name
	if name_label: name_label.text = p_name
	
	var vbox = get_node_or_null("VBox")
	if vbox:
		vbox.move_child(sh_bar, 1)
		vbox.move_child(hp_bar, 2)
	
	if not _role_icon_connected and role_icon:
		role_icon.gui_input.connect(_on_role_icon_input)
		role_icon.mouse_filter = Control.MOUSE_FILTER_STOP
		_role_icon_connected = true
	
	_setup_kick_button()
	_update_role_icon()
	update_bars()

func _setup_kick_button():
	var header = get_node_or_null("VBox/Header")
	if not header: return
	
	if not kick_btn:
		kick_btn = Button.new()
		kick_btn.text = "X"
		kick_btn.flat = true
		kick_btn.add_theme_color_override("font_color", Color.RED)
		kick_btn.add_theme_font_size_override("font_size", 10)
		kick_btn.custom_minimum_size = Vector2(20, 20)
		kick_btn.tooltip_text = "Expulsar del grupo"
		kick_btn.pressed.connect(_on_kick_pressed)
		header.add_child(kick_btn)
	
	var lp = get_tree().get_first_node_in_group("player")
	if is_instance_valid(lp) and PartyManager.current_party:
		var is_leader = (lp.db_id == PartyManager.current_party.id)
		var is_not_me = (lp.db_id != member_id)
		kick_btn.visible = is_leader and is_not_me
	else:
		kick_btn.visible = false

func _update_role_icon():
	if not role_icon: return
	
	var role = PartyManager.get_member_role(member_id)
	var is_leader = PartyManager.is_leader()
	
	# Tooltip según el rol
	match role:
		"tank": role_icon.tooltip_text = "Tanque" + (" (click para cambiar)" if is_leader else "")
		"healer": role_icon.tooltip_text = "Sanador" + (" (click para cambiar)" if is_leader else "")
		"buffer": role_icon.tooltip_text = "Buffer" + (" (click para cambiar)" if is_leader else "")
		"dps": role_icon.tooltip_text = "Daño" + (" (click para cambiar)" if is_leader else "")
		_:
			if is_leader:
				role_icon.tooltip_text = "Asignar rol (click)"
			else:
				role_icon.tooltip_text = ""
	
	# Generar textura del rol
	var icon_gen = load("res://scripts/ui/RoleIconGenerator.gd")
	if role != "":
		role_icon.texture = icon_gen.get_role_icon(role)
		role_icon.modulate = Color.WHITE
		role_icon.custom_minimum_size = Vector2(14, 14)
	elif is_leader:
		# Sin rol pero soy líder: ícono clickable con borde cyan
		role_icon.texture = _create_assignable_role_icon()
		role_icon.modulate = Color.CYAN.lightened(0.3)
		role_icon.custom_minimum_size = Vector2(14, 14)
	else:
		# Sin rol: ícono gris sutil
		role_icon.texture = _create_empty_role_icon()
		role_icon.modulate = Color(0.4, 0.4, 0.4, 0.3)
		role_icon.custom_minimum_size = Vector2(14, 14)

func _create_empty_role_icon() -> ImageTexture:
	var img = Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in range(4, 20):
		img.set_pixel(x, 4, Color(0.5, 0.5, 0.5, 0.35))
		img.set_pixel(x, 19, Color(0.5, 0.5, 0.5, 0.35))
	for y in range(4, 20):
		img.set_pixel(4, y, Color(0.5, 0.5, 0.5, 0.35))
		img.set_pixel(19, y, Color(0.5, 0.5, 0.5, 0.35))
	return ImageTexture.create_from_image(img)

func _create_assignable_role_icon() -> ImageTexture:
	var img = Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c = Color(0, 0.8, 0.9, 0.7)
	# Cuadro borde
	for x in range(3, 21):
		img.set_pixel(x, 3, c); img.set_pixel(x, 20, c)
	for y in range(3, 21):
		img.set_pixel(3, y, c); img.set_pixel(20, y, c)
	# Cruz "+"
	for x in range(9, 15):
		img.set_pixel(x, 11, c); img.set_pixel(x, 12, c)
	for y in range(8, 16):
		img.set_pixel(11, y, c); img.set_pixel(12, y, c)
	return ImageTexture.create_from_image(img)

func _on_role_icon_input(event: InputEvent):
	if not event is InputEventMouseButton: return
	if not event.pressed: return
	if event.button_index != MOUSE_BUTTON_LEFT: return
	if not PartyManager.is_leader(): return
	_show_role_menu()

func _show_role_menu():
	if role_menu and is_instance_valid(role_menu):
		role_menu.queue_free()
		role_menu = null
	
	role_menu = PopupPanel.new()
	role_menu.name = "RoleMenu"
	role_menu.size = Vector2(190, 140)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 2)
	
	var lp = get_tree().get_first_node_in_group("player")
	var is_me = (is_instance_valid(lp) and lp.db_id == member_id)
	var target_display = "TI MISMO" if is_me else member_name
	
	var title = Label.new()
	title.text = "  ASIGNAR ROL A " + target_display
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color.CYAN)
	vbox.add_child(title)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var roles = [
		{"id": "tank", "label": "Tanque", "desc": "Absorbe daño"},
		{"id": "healer", "label": "Sanador", "desc": "Cura aliados"},
		{"id": "buffer", "label": "Buffer", "desc": "Mejora stats"},
		{"id": "dps", "label": "Daño", "desc": "Ataque principal"}
	]
	
	var icon_gen = load("res://scripts/ui/RoleIconGenerator.gd")
	for r in roles:
		var btn = Button.new()
		btn.text = "  " + r.label + "  -  " + r.desc
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(180, 22)
		btn.add_theme_font_size_override("font_size", 9)
		var icon = icon_gen.get_role_icon(r.id)
		if icon:
			btn.icon = icon
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var role_id = r.id
		btn.pressed.connect(func(): _on_role_selected(role_id))
		vbox.add_child(btn)
	
	# Botón para quitar rol
	var current_role = PartyManager.get_member_role(member_id)
	if current_role != "":
		var sep2 = HSeparator.new()
		vbox.add_child(sep2)
		var clear_btn = Button.new()
		clear_btn.text = "  Quitar Rol"
		clear_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		clear_btn.custom_minimum_size = Vector2(180, 22)
		clear_btn.add_theme_font_size_override("font_size", 9)
		clear_btn.add_theme_color_override("font_color", Color.GRAY)
		clear_btn.pressed.connect(func(): _on_role_selected(""))
		vbox.add_child(clear_btn)
	
	role_menu.add_child(vbox)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.08, 0.96)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color.CYAN.darkened(0.2)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 4
	sb.content_margin_top = 4
	sb.content_margin_right = 4
	sb.content_margin_bottom = 4
	role_menu.add_theme_stylebox_override("panel", sb)
	
	add_child(role_menu)
	var icon_rect = role_icon.get_global_rect()
	role_menu.position = Vector2i(int(icon_rect.position.x), int(icon_rect.position.y + 20))
	role_menu.popup()

func _on_role_selected(role: String):
	PartyManager.set_role(member_id, role)
	if role_menu and is_instance_valid(role_menu):
		role_menu.hide()

func _on_kick_pressed():
	if member_id != "":
		PartyManager.kick_player(member_id)

func update_bars():
	var info = PartyManager.get_member_stats(member_id, member_name)
	if is_instance_valid(hp_bar):
		hp_bar.max_value = info["max_hp"]
		hp_bar.value = info["hp"]
	if is_instance_valid(sh_bar):
		sh_bar.max_value = info["max_shield"]
		sh_bar.value = info["shield"]
	if is_instance_valid(stats_label):
		var hp_str = str(int(info["hp"])) + "/" + str(int(info["max_hp"]))
		var sh_str = str(int(info["shield"])) + "/" + str(int(info["max_shield"]))
		stats_label.text = "HP: " + hp_str + " | SH: " + sh_str
