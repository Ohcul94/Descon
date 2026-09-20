extends PanelContainer

# PartyMemberRow.gd (Aliados v1.55)
# Muestra HP/SH, Datos numéricos y ROL de aliados en el HUD.
# v1.55: Click para targetear aliado + indicador de rango de visión.

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
var _is_in_vision: bool = true

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
		role_icon.mouse_filter = Control.MOUSE_FILTER_PASS
		_role_icon_connected = true
	
	# Conectar click en la tarjeta para targetear
	# Propagar mouse_filter de hijos para que los clicks lleguen al PanelContainer
	var vbox_node = get_node_or_null("VBox")
	if vbox_node:
		vbox_node.mouse_filter = Control.MOUSE_FILTER_PASS
		for child in vbox_node.get_children():
			child.mouse_filter = Control.MOUSE_FILTER_PASS
			if child is Container:
				for sub in child.get_children():
					sub.mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_card_input)
	
	# Hover effect para feedback visual
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)
	
	_setup_kick_button()
	_update_role_icon()
	_update_vision_state()
	update_bars()

func _on_card_input(event: InputEvent):
	if not event is InputEventMouseButton: return
	if not event.pressed: return
	if event.button_index != MOUSE_BUTTON_LEFT: return
	
	# Ignorar clicks sobre botones hijos (ellos manejan su propio input)
	if kick_btn and kick_btn.visible and kick_btn.get_global_rect().has_point(event.global_position):
		return
	if role_icon and role_icon.get_global_rect().has_point(event.global_position):
		return
	
	_target_member()

func _target_member():
	if member_id == "" and member_name == "" and not _is_in_vision:
		return
	
	# No targetear a ti mismo
	var lp = get_tree().get_first_node_in_group("player")
	if is_instance_valid(lp):
		if member_id != "" and lp.db_id == member_id:
			return
		if member_name != "" and lp.username.to_lower() == member_name.to_lower():
			return
	
	var entity = _find_member_entity()
	if not is_instance_valid(entity):
		return
	
	# Buscar MainHUD y llamar set_target
	var main_hud = get_tree().root.find_child("MainHUD", true, false)
	if is_instance_valid(main_hud) and main_hud.has_method("set_target"):
		main_hud.set_target(entity)

func _find_member_entity() -> Node:
	var lp = get_tree().get_first_node_in_group("player")
	
	# 1. Verificar si es el jugador local
	if is_instance_valid(lp):
		if member_id != "" and "db_id" in lp and lp.db_id == member_id:
			return lp
		if member_name != "" and "username" in lp and lp.username.to_lower() == member_name.to_lower():
			return lp
	
	# 2. Buscar en remote_players
	var world = get_tree().get_first_node_in_group("world_node")
	if is_instance_valid(world) and "remote_players" in world:
		var remote = world.remote_players
		if member_id != "" and remote.has(member_id):
			return remote[member_id]
		# Buscar por db_id o username
		for id in remote:
			var rp = remote[id]
			if is_instance_valid(rp):
				var rp_db = str(rp.get("db_id")) if rp.get("db_id") != null else ""
				if member_id != "" and rp_db == member_id:
					return rp
				var rp_user = str(rp.get("username")) if rp.get("username") != null else ""
				if member_name != "" and rp_user.to_lower() == member_name.to_lower():
					return rp
	
	# 3. Buscar en el grupo entities por si acaso
	for ent in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(ent):
			var ent_db = str(ent.get("db_id")) if ent.get("db_id") != null else ""
			if member_id != "" and ent_db == member_id:
				return ent
			var ent_user = str(ent.get("username")) if ent.get("username") != null else ""
			if member_name != "" and ent_user.to_lower() == member_name.to_lower():
				return ent
	
	return null

func _update_vision_state():
	var entity = _find_member_entity()
	var in_range = true
	
	if is_instance_valid(entity) and not entity.is_in_group("player"):
		var lp = get_tree().get_first_node_in_group("player")
		if is_instance_valid(lp):
			var vision_r = 1300.0
			if "vision_range" in lp:
				vision_r = lp.vision_range
			var dist = lp.global_position.distance_to(entity.global_position)
			in_range = dist <= vision_r
	
	_is_in_vision = in_range
	
	# Aplicar color al nombre: cyan si está en rango, gris si no
	if name_label:
		if in_range:
			name_label.modulate = Color.WHITE
			tooltip_text = "Click para targetear a " + member_name
		else:
			name_label.modulate = Color(0.4, 0.4, 0.4)
			tooltip_text = member_name + " (fuera de rango)"
	
	# Reducir opacidad de la tarjeta completa si fuera de rango
	if in_range:
		modulate.a = 1.0
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		modulate.a = 0.55
		# No desactivar mouse_filter para que el tooltip siga funcionando

func _on_hover_enter():
	if not _is_in_vision: return
	# Efecto hover: borde brillante cyan
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0.15, 0.25, 0.5)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color.CYAN.lightened(0.3)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

func _on_hover_exit():
	# Restaurar estilo original
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.4)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0, 1, 1, 0.2)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

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
		kick_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		kick_btn.pressed.connect(_on_kick_pressed)
		header.add_child(kick_btn)
	
	var lp = get_tree().get_first_node_in_group("player")
	if is_instance_valid(lp) and PartyManager.current_party:
		var is_leader = (lp.db_id == PartyManager.current_party.id)
		var is_me = (lp.db_id == member_id or (member_name != "" and lp.username.to_lower() == member_name.to_lower()))
		if is_me:
			kick_btn.visible = true
			kick_btn.tooltip_text = "Abandonar grupo"
		elif is_leader:
			kick_btn.visible = true
			kick_btn.tooltip_text = "Expulsar del grupo"
		else:
			kick_btn.visible = false
	else:
		kick_btn.visible = false

func _update_role_icon():
	if not role_icon: return
	
	var role = PartyManager.get_member_role(member_id)
	if role == "" and member_name != "":
		role = PartyManager.get_member_role(member_name)
	
	var is_leader = PartyManager.is_leader()
	
	# Icono y tooltip idéntico a las etiquetas overhead
	match role:
		"tank":
			role_icon.text = "🛡️"
			role_icon.tooltip_text = "Tanque" + (" (click para cambiar)" if is_leader else "")
			role_icon.modulate = Color.WHITE
		"healer":
			role_icon.text = "💚"
			role_icon.tooltip_text = "Sanador" + (" (click para cambiar)" if is_leader else "")
			role_icon.modulate = Color.WHITE
		"buffer":
			role_icon.text = "⚡"
			role_icon.tooltip_text = "Buffer" + (" (click para cambiar)" if is_leader else "")
			role_icon.modulate = Color.WHITE
		"dps":
			role_icon.text = "⚔️"
			role_icon.tooltip_text = "Daño" + (" (click para cambiar)" if is_leader else "")
			role_icon.modulate = Color.WHITE
		_:
			if is_leader:
				role_icon.text = "➕"
				role_icon.tooltip_text = "Asignar rol (click)"
				role_icon.modulate = Color.CYAN
			else:
				role_icon.text = ""
				role_icon.tooltip_text = ""
				role_icon.modulate = Color.TRANSPARENT

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
	role_menu.size = Vector2(200, 150)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 2)
	
	var lp = get_tree().get_first_node_in_group("player")
	var is_me = (is_instance_valid(lp) and (lp.db_id == member_id or lp.username.to_lower() == member_name.to_lower()))
	var target_display = "TI MISMO" if is_me else member_name
	
	var title = Label.new()
	title.text = "  ASIGNAR ROL A " + target_display
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color.CYAN)
	vbox.add_child(title)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var roles = [
		{"id": "tank", "icon": "🛡️", "label": "Tanque", "desc": "Absorbe daño"},
		{"id": "healer", "icon": "💚", "label": "Sanador", "desc": "Cura aliados"},
		{"id": "buffer", "icon": "⚡", "label": "Buffer", "desc": "Mejora stats"},
		{"id": "dps", "icon": "⚔️", "label": "Daño", "desc": "Ataque principal"}
	]
	
	for r in roles:
		var btn = Button.new()
		btn.text = "  " + r.icon + "  " + r.label + " - " + r.desc
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(190, 24)
		btn.add_theme_font_size_override("font_size", 10)
		var role_id = r.id
		btn.pressed.connect(func(): _on_role_selected(role_id))
		vbox.add_child(btn)
	
	# Botón para quitar rol
	var current_role = PartyManager.get_member_role(member_id)
	if current_role == "" and member_name != "":
		current_role = PartyManager.get_member_role(member_name)
	if current_role != "":
		var sep2 = HSeparator.new()
		vbox.add_child(sep2)
		var clear_btn = Button.new()
		clear_btn.text = "  ❌  Quitar Rol"
		clear_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		clear_btn.custom_minimum_size = Vector2(190, 24)
		clear_btn.add_theme_font_size_override("font_size", 10)
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
	var lp = get_tree().get_first_node_in_group("player")
	var is_me = (is_instance_valid(lp) and (lp.db_id == member_id or (member_name != "" and lp.username.to_lower() == member_name.to_lower())))
	if is_me:
		PartyManager.leave_party()
	elif member_id != "":
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
	
	# Actualizar estado de visión periódicamente
	_update_vision_state()
