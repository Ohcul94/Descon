extends SphereSkill
class_name Skill_HealBeacon

func _init():
	skill_name = "BALIZA DE CURACION"
	description = "Despliega una baliza que emite ondas de curación periódicas a los aliados cercanos."
	type = "Curación"
	cooldown = 18.0

func activate(player: CharacterBody2D):
	# Feedback local al activar la habilidad
	if player.has_method("play_skill_vfx"):
		player.play_skill_vfx("HEAL_BEACON_ACTIVATE", 0.0)
	
	# Enviar el evento de activación al servidor
	super.activate(player)
