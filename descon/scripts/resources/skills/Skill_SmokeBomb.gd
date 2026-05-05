extends SphereSkill
class_name Skill_SmokeBomb

func _init():
	skill_name = "SMOKE-BOMB"
	description = "Lanza una bomba de humo que silencia y ciega a los enemigos en el área."
	type = "Defensa"
	power_value = 1.0

func activate(player: CharacterBody2D):
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(2.0)
	# v2.0: No llamamos a super.activate() para evitar que la lógica base 
	# de "Defensa" (SphereSkill.gd) active visuales de escudo por error.
	# La lógica de esta habilidad es 100% autoritativa en el servidor.
