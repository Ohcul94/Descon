extends Control

# StatsHUD.gd (v1.0 - Componente de Estadísticas del Jugador)

var hubs_label = null
var ohcu_label = null
var lvl_label = null
var speed_label = null

func _ready():
	print("[StatsHUD] Inicializando estadísticas centrales.")
	hubs_label = get_node_or_null("VBox/Currency/HUBS")
	ohcu_label = get_node_or_null("VBox/Currency/OHCU")
	lvl_label = get_node_or_null("VBox/LevelInfo/LVL")
	var vbox = get_node_or_null("VBox")
	if vbox:
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		vbox.add_theme_constant_override("separation", 10)
		
		speed_label = vbox.get_node_or_null("SpeedLabel")
		if not is_instance_valid(speed_label):
			speed_label = Label.new()
			speed_label.name = "SpeedLabel"
			speed_label.add_theme_font_size_override("font_size", 10)
			speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			speed_label.modulate = Color.YELLOW
			vbox.add_child(speed_label)
			
	set_process(true)

func _process(_delta):
	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or p_node.get("is_dead") or p_node.get("entity_id") == "":
		return
		
	if is_instance_valid(lvl_label):
		var p_exp = p_node.get("current_exp")
		if p_exp == null: p_exp = 0.0
		var lvl = p_node.get("level")
		if lvl == null: lvl = 1
		
		# v193.15: Meta Exponencial Sincronizada (Lvl^1.5 * 1000)
		var next_exp = floor(1000.0 * pow(lvl, 1.5))
		var pct = clamp((p_exp / next_exp) * 100, 0, 100)
		lvl_label.text = "LEVEL " + str(lvl) + " | EXP " + str(int(pct)) + "%"
		
	if is_instance_valid(hubs_label): 
		var val = p_node.get("hubs")
		hubs_label.text = "HUBS: " + _format_val(val if val != null else 0)
		
	if is_instance_valid(ohcu_label): 
		var val = p_node.get("ohculianos")
		ohcu_label.text = "OHCU: " + _format_val(val if val != null else 0)

	if is_instance_valid(speed_label):
		var val = p_node.get("speed")
		var s_pts = p_node.get("slow_points")
		if s_pts == null: s_pts = 0.0
		var f_slow = p_node.get("_freeze_slow_val")
		if f_slow == null: f_slow = 0.0
		
		var final_speed = max(0.0, (val if val != null else 0.0) - s_pts - f_slow)
		speed_label.text = "Vel.: " + str(int(final_speed))
		
		# v9.0: Feedback de color si hay slow (común o ambiental)
		if s_pts > 1.0 or f_slow > 1.0: speed_label.modulate = Color.CYAN
		else: speed_label.modulate = Color.YELLOW

func _format_val(v):
	var s = str(int(v))
	var r = ""
	var c = 0
	for i in range(s.length()-1,-1,-1):
		r = s[i] + r
		c += 1
		if c == 3 and i != 0:
			r = "." + r
			c = 0
	return r
