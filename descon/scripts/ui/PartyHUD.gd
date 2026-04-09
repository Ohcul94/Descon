extends "res://scripts/systems/HUDWindow.gd"

# PartyHUD.gd (HUD Draggable v1.50)
# Administra la lista de aliados y el arrastre de la ventana.

var MEMBER_ROW_SCENE = preload("res://scenes/ui/PartyMemberRow.tscn")

@onready var members_list = get_node_or_null("VBoxContainer/MembersList")

func _ready():
	window_id = "PartyHUD"
	header_height = 30 # Definir zona de arrastre superior
	z_index = 50
	
	# v167.30: Exorcismo de Títulos Superpuestos (Limpiar el .tscn)
	for child in get_children():
		if child is Label:
			if "ESCUADRON" in child.text.to_upper() or "SQUAD" in child.text.to_upper():
				child.visible = false
				child.queue_free()
		elif child is Control and child.name != "VBoxContainer":
			# Buscar recursivamente si no es el contenedor de miembros
			for gc in child.get_children():
				if gc is Label and "ESCUADRON" in gc.text.to_upper():
					gc.visible = false; gc.queue_free()
	
	super._ready() # Iniciar HUDWindow (Draggable)
	
	# v167.30: Inyección de Cabecera Profesional (Estilo Sistema Recon)
	_create_drag_handler()
	
	if PartyManager:
		PartyManager.party_updated.connect(_on_party_updated)
		visible = PartyManager.current_party != null
	_refresh_list()

func _create_drag_handler():
	# v167.30: Panel con Estilo Neón Cyan (Idéntico a Minimapa/Chat)
	var handle = Panel.new()
	handle.name = "Header"
	handle.custom_minimum_size = Vector2(170, 25)
	handle.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6) # Translucidez táctica
	sb.border_width_bottom = 1
	sb.border_color = Color.CYAN
	handle.add_theme_stylebox_override("panel", sb)
	
	var label = Label.new()
	label.text = "ESCUADRÓN"
	label.add_theme_font_size_override("font_size", 9)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate = Color.CYAN
	handle.add_child(label)
	
	add_child(handle)
	move_child(handle, 0)
	
	# Ajustar margen de la lista de miembros
	var box = get_node_or_null("VBoxContainer")
	if box: box.offset_top = 30

func _process(_delta):
	# Actualización rápida para fluidez de barras
	if visible and is_instance_valid(members_list):
		for row in members_list.get_children():
			if row.has_method("update_visuals"):
				row.update_visuals()

func _on_party_updated(_data):
	visible = PartyManager.current_party != null
	_refresh_list()

func _refresh_list():
	if not is_instance_valid(members_list): return
	
	for child in members_list.get_children():
		child.queue_free()
		
	var party = PartyManager.current_party
	if not party: return
	
	var members = party.get("members", [])
	var names = party.get("names", [])
	
	for i in range(members.size()):
		var id = str(members[i])
		var p_name = names[i] if names.size() > i else "Piloto"
		
		var row = MEMBER_ROW_SCENE.instantiate()
		members_list.add_child(row)
		if row.has_method("setup"):
			row.setup(id, p_name)
