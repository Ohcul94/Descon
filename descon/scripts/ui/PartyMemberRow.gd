extends PanelContainer

# PartyMemberRow.gd (Aliados v1.52)
# Muestra HP/SH y Datos numéricos de aliados en el HUD.

@onready var name_label = $VBox/Header/Name
@onready var hp_bar = $VBox/HPBar
@onready var sh_bar = $VBox/SHBar
@onready var stats_label = $VBox/StatsText

var member_id = ""
var member_name = ""
var kick_btn: Button = null

func setup(id: String, p_name: String):
	member_id = id
	member_name = p_name
	if name_label: name_label.text = p_name
	
	# v167.60: Invertir Barras para paridad con el Player (Shield arriba, HP abajo)
	var vbox = get_node_or_null("VBox")
	if vbox:
		vbox.move_child(sh_bar, 1) # Poner escudo debajo del header
		vbox.move_child(hp_bar, 2) # Poner vida debajo del escudo
	
	_setup_kick_button()
	update_visuals()

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
	
	# Solo visible para el líder y si NO soy yo mismo
	var lp = get_tree().get_first_node_in_group("player")
	if is_instance_valid(lp) and PartyManager.current_party:
		var is_leader = (lp.db_id == PartyManager.current_party.id)
		var is_not_me = (lp.db_id != member_id)
		kick_btn.visible = is_leader and is_not_me
	else:
		kick_btn.visible = false

func _on_kick_pressed():
	if member_id != "":
		PartyManager.kick_player(member_id)

func update_visuals():
	_setup_kick_button()
	# Obtención segura de datos a través del singleton PartyManager
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
