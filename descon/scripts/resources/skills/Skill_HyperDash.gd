extends SphereSkill
class_name Skill_HyperDash

func _init():
	skill_name = "HYPER-DASH"
	description = "Propulsión instantánea hacia adelante para evasión rápida."
	type = "Movimiento"
	power_value = 1000.0
	cooldown = 5.0

func activate(player: CharacterBody2D):
	if player.has_method("apply_impulse"):
		# Lógica de impulso (dash)
		print("[SKILL] Hyper-Dash activado")
	super.activate(player)
