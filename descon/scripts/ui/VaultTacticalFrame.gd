extends Control

# VaultTacticalFrame.gd — Marco exterior del Baúl con la MISMA estética táctica
# que el Inventario F1 (HUDFrame.draw_tactical_modal): obsidiana, cabecera cian,
# brackets y badge de balances HUBS/OHCU.

var title_text: String = "CENTRO DE BAÚL Y LOGÍSTICA"
var hubs_str: String = "0"
var ohcu_str: String = "0"

func _draw():
	if size.x <= 4 or size.y <= 4:
		return
	HUDFrame.draw_tactical_modal(self, Vector2.ZERO, size, title_text, true, hubs_str, ohcu_str)
