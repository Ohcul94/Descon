extends SphereSkill
class_name Skill_Resurreccion

func _init():
	skill_name = "RESURRECCIÓN"
	description = "Canaliza un haz de energía en el área seleccionada para resucitar a los aliados caídos."
	type = "Utilidad"
	cooldown = 45.0

func activate(player: CharacterBody2D):
	# Feedback local al activar la habilidad (opcional)
	if player.has_method("play_skill_vfx"):
		player.play_skill_vfx("HEAL_ZONE", 0.0) # Usamos el efecto visual existente
