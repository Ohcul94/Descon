extends SphereSkill
class_name Skill_RepairKit

func _init():
	skill_name = "AUTO-REPARACIÓN"
	description = "Drones de reparación restauran la integridad del casco."
	type = "Curación"
	power_value = 400.0

func activate(player: CharacterBody2D):
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(6.0) # Bloqueo de 6s para curación
	super.activate(player)
