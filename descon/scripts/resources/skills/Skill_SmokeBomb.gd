extends SphereSkill
class_name Skill_SmokeBomb

func _init():
	skill_name = "SMOKE-BOMB"
	description = "Lanza una bomba de humo que silencia y ciega a los enemigos en el área."
	type = "Defensa"
	power_value = 1.0

func activate(player: CharacterBody2D):
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(2.0)
	
	# v2.2: Restaurar llamada a super para que Player.gd envíe el evento al servidor
	super.activate(player)
	
	# v2.0: No llamábamos a super.activate() para evitar que la lógica base 
	# de "Defensa" (SphereSkill.gd) active visuales de escudo por error.
	# v2.2 Fix: Ya comprobamos que play_skill_vfx("SMOKE-BOMB") es un 'pass' en Entity.gd, 
	# así que llamar a super es seguro y necesario para la sincronía.



