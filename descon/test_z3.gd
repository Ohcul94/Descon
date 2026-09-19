extends Node
func _ready():
	var wm = load("res://scripts/ui/WorldMapDialog.gd")
	var r = wm.get_zone_rect(3, get_tree())
	print("ZONA 3 RECT: ", r)
	get_tree().quit(0)
