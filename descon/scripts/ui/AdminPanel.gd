extends "res://scripts/systems/HUDWindow.gd"

# AdminPanel.gd (F2 Admin v2.0 - Neon Styling)
# Panel de administración para configurar stats en tiempo real.

@onready var ship_name_lbl = get_node_or_null("VBox/ShipInfo/Name")
@onready var hp_input = get_node_or_null("VBox/Stats/HPInput")
@onready var shield_input = get_node_or_null("VBox/Stats/ShieldInput")

func _ready():
	super._ready() # Iniciar arrastre
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func toggle():
	visible = !visible
	if visible:
		_refresh_inputs()

func _refresh_inputs():
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p):
		if hp_input: hp_input.text = str(int(p.max_hp))
		if shield_input: shield_input.text = str(int(p.max_shield))

func _on_apply_btn_pressed():
	if not hp_input or not shield_input: return
	var data = {
		"hp": float(hp_input.text),
		"shield": float(shield_input.text)
	}
	NetworkManager.send_event("adminUpdateStats", data)
	print("[ADMIN] Solicitud de cambio de stats enviada.")
