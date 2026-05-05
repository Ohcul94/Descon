extends SphereSkill
class_name Skill_TurboImpulse

func _init():
	skill_id = "SK-UTIL-01"
	skill_name = "TURBO-IMPULSO"
	description = "Aumenta la velocidad de los motores temporalmente."
	type = "Utilidad"
	power_value = 150.0

func activate(player: CharacterBody2D):
	super.activate(player)
	# Lógica extra si fuera necesaria (ej: partículas)
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(2.0)
