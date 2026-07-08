extends SphereSkill
class_name Skill_Resurreccion

func _init():
	skill_name = "RESURRECCIÓN"
	description = "Canaliza un haz de energía en el área seleccionada para resucitar a los aliados caídos."
	type = "Utilidad"
	cooldown = 45.0

func activate(player: CharacterBody2D):
	# El VFX se maneja desde el servidor vía spawnArea con tipo RESURRECCIÓN
	super.activate(player)
