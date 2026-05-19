extends SphereSkill
class_name Skill_VitalLink

# Skill_VitalLink.gd (v1.0 - Rayo de Curacion Vinculado)

func _init():
	skill_id = "SK-HEAL-04"
	skill_name = "VÍNCULO VITAL"
	description = "Enlaza un rayo curativo continuo a un aliado que restaura HP periódicamente. El lazo se corta si se alejan demasiado."
	type = "Curación"
	power_value = 250.0
	cooldown = 15.0

func activate(player: CharacterBody2D):
	super.activate(player)
