extends SphereSkill
class_name Skill_DimensionExtrana

# Skill_DimensionExtrana.gd
# Mecánica de Defensa: Dimensión Extraña
# Teletransporta al jugador a una dimensión paralela sombría y tenebrosa,
# cambiando la estética a tonos violetas/oscuridad, eliminando entidades
# aliadas y del entorno. Permite crear enemigos dentro de la dimensión.

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
	
	# Establecer el flag CC para activación automática en _physics_process
	if player.has_method("strange_dimension_cc"):
		player.strange_dimension_cc = true
		player.strange_dimension_timer = power_value
		player.strange_dimension_config = {
			"duration": power_value,
			"targets": { "enemies": true, "bosses": true, "players": false, "allies": false },
			"summonConfig": { "canSummon": true, "enemyTypes": [], "maxEnemies": 5 }
		}
	
	# Disparar el VFX del portal
	if player.has_method("play_skill_vfx"):
		player.play_skill_vfx("STRANGE_DIMENSION_PORTAL", 0.0)
	
	super.activate(player)
