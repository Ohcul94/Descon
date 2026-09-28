extends SphereSkill
class_name Skill_DimensionExtrana

# Skill_DimensionExtrana.gd
# Mecánica de Defensa: Dimensión Extraña
# Teletransporta al jugador a una dimensión paralela sombría y tenebrosa,
# cambiando la estética a tonos violetas/oscuridad, eliminando entidades
# aliadas y del entorno.

func _init():
	skill_id = "SK-DEF-07"
	skill_name = "DIMENSIÓN EXTRAÑA"
	description = "Te transporta a una dimensión paralela tenebrosa con estética violeta. Oculta aliados y entorno, permitiendo convocar enemigos desde esa realidad."
	type = "Defensa"
	power_value = 5.0
	cooldown = 30.0

func activate(player: CharacterBody2D):
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(2.0)
	
	if player.has_method("activate_strange_dimension"):
		player.activate_strange_dimension(power_value)
	
	super.activate(player)
