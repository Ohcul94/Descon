extends PanelContainer

# PartyMemberRow.gd (Aliados v1.52)
# Muestra HP/SH y Datos numéricos de aliados en el HUD.

@onready var name_label = $VBox/Header/Name
@onready var hp_bar = $VBox/HPBar
@onready var sh_bar = $VBox/SHBar
@onready var stats_label = $VBox/StatsText

var member_id = ""
var member_name = ""

func setup(id: String, p_name: String):
	member_id = id
	member_name = p_name
	if name_label: name_label.text = p_name
	
	# v167.60: Invertir Barras para paridad con el Player (Shield arriba, HP abajo)
	var vbox = get_node_or_null("VBox")
	if vbox:
		vbox.move_child(sh_bar, 1) # Poner escudo debajo del header
		vbox.move_child(hp_bar, 2) # Poner vida debajo del escudo
		
	update_visuals()

func update_visuals():
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
