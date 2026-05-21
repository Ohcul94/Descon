extends SphereSkill
class_name Skill_Provocacion

func _init():
	skill_name = "PROVOCACION"
	description = "Provoca a todos los enemigos en el área elegida, forzándolos a atacarte."
	type = "Ataque"
	cooldown = 15.0

func activate(player: CharacterBody2D):
	# Feedback local al activar la habilidad (opcional)
	if player.has_method("play_skill_vfx"):
		player.play_skill_vfx("TAUNT_ACTIVATE", 0.0)
	
	# Enviar el evento de activación al servidor
	super.activate(player)
