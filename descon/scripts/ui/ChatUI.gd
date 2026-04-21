extends HUDWindow

# ChatUI.gd (Controlador de Comunicación Táctica v69.46)
# Ahora hereda de HUDWindow para tener Drag and Drop nativo.

@onready var chat_input = $Window/VBox/HBox/Input
@onready var chat_messages = $Window/VBox/Scroll/Messages
@onready var chat_scroll = $Window/VBox/Scroll
@onready var chat_window = $Window
@onready var chat_title = $Window/Title
@onready var channel_selector = null # Se inyecta dinámicamente v164.22

var active_channel = "region" # v164.21: Regional (Local) por defecto
var is_minimized = false
var original_height = 0.0

func _ready():
	super._ready() # Iniciar lógica de ventana (cargar posición)
	add_to_group("chat_ui")
	# v164.46: Señal para que el resto de la HUD sepa que cambiamos visibilidad
	visibility_changed.connect(_on_visibility_changed)
	# Conexión Segura
	if NetworkManager:
		if not NetworkManager.chat_received.is_connected(_on_chat_received):
			NetworkManager.chat_received.connect(_on_chat_received)
	
	if chat_input:
		if not chat_input.text_submitted.is_connected(_send_msg):
			chat_input.text_submitted.connect(_send_msg)
		chat_input.max_length = 50 # v164.31: Límite estricto de 50 caracteres
	
	if chat_title:
		chat_title.text = "" # Titulo Eliminado v164.51
		# v164.49: Botón de Minimizar ELIMINADO para paridad minimalista.
		# Se gestiona todo desde los iconos del Footer.
		
	# v164.22: Inyección Táctica del Selector (si no existe en el .tscn)
	if not channel_selector and $Window/VBox/HBox:
		channel_selector = OptionButton.new()
		channel_selector.name = "ChannelSelect"
		channel_selector.flat = true
		channel_selector.add_theme_font_size_override("font_size", 9)
		$Window/VBox/HBox.add_child(channel_selector)
		$Window/VBox/HBox.move_child(channel_selector, 0) # Poner antes del input
		
	if channel_selector:
		channel_selector.clear()
		channel_selector.add_item("LOCAL", 0); channel_selector.set_item_metadata(0, "region")
		channel_selector.add_item("GLOBAL", 1); channel_selector.set_item_metadata(1, "global")
		channel_selector.add_item("EQUIPO", 2); channel_selector.set_item_metadata(2, "team")
		channel_selector.selected = 0 # Local por defecto
		if not channel_selector.item_selected.is_connected(_on_channel_selected):
			channel_selector.item_selected.connect(_on_channel_selected)

func toggle_minimize():
	# v164.48: PARIDAD TOTAL HUD (Ocultar y avisar al MainHUD)
	visible = false
	is_minimized = true
	minimized.emit("Chat") # "Chat" es el ID que usa MainHUD.gd

func _on_visibility_changed():
	# Esta señal es capturada por los botones de la HUD de abajo
	# para prender/apagar su color automáticamente.
	pass

func _input(ev):
	super._input(ev) # v165.41: Mantener Drag and Drop funcionando
	if ev.is_action_pressed("ui_accept"):
		if chat_input:
			if not chat_input.has_focus():
				chat_input.grab_focus()
				get_viewport().set_input_as_handled()
			else:
				if chat_input.text.strip_edges() == "":
					chat_input.release_focus()
					get_viewport().set_input_as_handled()

func _send_msg(msg_text: String):
	if msg_text.strip_edges() != "":
		var filtered_text = msg_text
		
		if filtered_text.begins_with("/t "):
			active_channel = "team"
			filtered_text = filtered_text.substr(3)
		elif filtered_text.begins_with("/r "):
			active_channel = "region"
			filtered_text = filtered_text.substr(3)
		elif filtered_text.begins_with("/g "):
			active_channel = "global"
			filtered_text = filtered_text.substr(3)
			
		if NetworkManager:
			NetworkManager.send_event("chatMessage", {
				"msg": filtered_text.substr(0, 50),
				"channel": active_channel
			})
			chat_input.text = ""
	
	if chat_input:
		chat_input.release_focus()

func _on_chat_received(msg_data: Dictionary):
	var sender = str(msg_data.get("sender", msg_data.get("user", "System")))
	var content = str(msg_data.get("msg", msg_data.get("text", "")))
	var channel_type = str(msg_data.get("channel", "global"))
	
	var label_msg = RichTextLabel.new()
	label_msg.bbcode_enabled = true
	label_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_msg.fit_content = true
	label_msg.add_theme_font_size_override("normal_font_size", 11)
	
	var tag_color = "#ffffff"
	var tag_text = "[GLOBAL]"
	
	match channel_type:
		"global": 
			tag_color = "#00ffff"; tag_text = "[GLOBAL]"
		"region": 
			tag_color = "#ffff00"; tag_text = "[LOCAL]"
		"team": 
			tag_color = "#00ff00"; tag_text = "[EQUIPO]"
		"admin": 
			tag_color = "#bc13fe"; tag_text = "[ADMIN]"
	
	var final_content = content.replace("(Sin compañeros activos)", "[color=#888888](Sin compañeros activos)[/color]")
	label_msg.text = "[outline_size=1][outline_color=black][color=" + tag_color + "]" + tag_text + " " + sender + ":[/color] " + final_content + "[/outline_color][/outline_size]"
	
	var sid = str(msg_data.get("senderId", "")); 
	_render_message(label_msg, sid, content, sender)

func _render_message(msg_node, sid: String = "", content: String = "", sender: String = ""):
	if chat_messages:
		chat_messages.add_child(msg_node)
		if chat_messages.get_child_count() > 30:
			chat_messages.get_child(0).queue_free()
		
		msg_node.modulate.a = 0
		var tw = create_tween()
		tw.tween_property(msg_node, "modulate:a", 1.0, 0.2)
		
		if sid != "" and content != "":
			var clean_txt = content.replace("(Sin compañeros activos)", "").strip_edges()
			if clean_txt != "":
				_route_bubble(sid, clean_txt, sender)
		
		await get_tree().process_frame
		if chat_scroll:
			var max_v = chat_scroll.get_v_scroll_bar().max_value
			chat_scroll.set_deferred("scroll_vertical", int(max_v))

func _route_bubble(sid: String, txt: String, sender: String):
	var world = get_tree().get_first_node_in_group("world_node")
	if world and world.has_method("route_chat_bubble"):
		world.route_chat_bubble({
			"senderId": sid,
			"msg": txt,
			"sender": sender
		})

func _on_channel_selected(index: int):
	if channel_selector:
		active_channel = channel_selector.get_item_metadata(index)

func is_typing() -> bool:
	return chat_input and chat_input.has_focus()

func release_chat_focus():
	if chat_input: chat_input.release_focus()
