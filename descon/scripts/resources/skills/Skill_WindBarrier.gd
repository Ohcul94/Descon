extends SphereSkill
class_name Skill_WindBarrier

func _init():
	skill_name = "BARRERA DE VIENTO"
	description = "Crea una barrera de viento que repele a los objetivos seleccionados."
	type = "Defensa"
	cooldown = 20.0

func activate(player: CharacterBody2D):
	# Efecto visual/feedback local al activar la habilidad
	if player.has_method("play_skill_vfx"):
		player.play_skill_vfx("WIND_BARRIER_ACTIVATE", 0.0)
