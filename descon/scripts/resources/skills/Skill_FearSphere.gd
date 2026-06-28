extends SphereSkill
class_name Skill_FearSphere

func _init():
	skill_name = "ESFERA DE TERROR"
	type = "Ataque"

func activate(player: CharacterBody2D):
	super.activate(player)
