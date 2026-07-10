extends SphereSkill
class_name Skill_Provocacion

func _init():
	skill_name = "PROVOCACION"
	description = "Carga y libera una onda que provoca a los enemigos cercanos."
	type = "Defensa"
	cooldown = 15.0

func activate(player: CharacterBody2D):
	if player.has_method("play_skill_vfx"):
		player.play_skill_vfx("TAUNT_ACTIVATE", 0.0)
