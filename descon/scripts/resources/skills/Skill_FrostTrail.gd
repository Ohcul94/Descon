extends SphereSkill
class_name Skill_FrostTrail

func _init():
	skill_name = "FROST-TRAIL"
	description = "Deja un rastro de escarcha que ralentiza a los enemigos."
	type = "Defensa"
	cooldown = 18.0

func activate(player: CharacterBody2D):
	# Efecto local inmediato para feedback del jugador
	if player.has_method("play_skill_vfx"):
		player.play_skill_vfx("FROST_ACTIVATE", 0.0)
	
	# Llamar a super para enviar el evento al servidor (playerSphereSkill)
	super.activate(player)
