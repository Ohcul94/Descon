extends SphereSkill
class_name Skill_ShieldCell

func _init():
	skill_name = "ESCUDO CELULAR"
	description = "Inyecta plasma en los generadores para restaurar el escudo."
	type = "Defensa"
	power_value = 600.0

func activate(player: CharacterBody2D):
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(6.0)
	super.activate(player)
