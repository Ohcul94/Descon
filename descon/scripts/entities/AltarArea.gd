class_name AltarArea
extends Area2D

# AltarArea.gd
# Maneja la detección de impactos y visualización de textos de daño en el Altar de Defensa

const DamageTextScript = preload("res://scripts/ui/DamageText.gd")

func _ready() -> void:
	add_to_group("altar")

func _spawn_damage_text(txt: String, clr: Color = Color(1.0, 0.3, 0.3)) -> void:
	if DamageTextScript:
		var dt = Marker2D.new()
		dt.z_index = 100
		dt.set_script(DamageTextScript)
		add_child(dt)
		dt.position = Vector2(randf_range(-30.0, 30.0), randf_range(-60.0, -85.0))
		if dt.has_method("setup"):
			dt.setup(txt, clr)
