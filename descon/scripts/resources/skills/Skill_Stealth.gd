extends SphereSkill
class_name Skill_Stealth

func _init():
	skill_name = "STEALTH"
	description = "Te vuelve invisible para enemigos y jugadores fuera de tu grupo."
	type = "Utilidad"
	cooldown = 25.0

func activate(player: CharacterBody2D):
	# Efecto local inmediato para feedback del jugador
	if player.has_method("play_skill_vfx"):
		player.play_skill_vfx("STEALTH_ACTIVATE", 0.0)
	
	# Llamar a super para enviar el evento al servidor
	super.activate(player)
