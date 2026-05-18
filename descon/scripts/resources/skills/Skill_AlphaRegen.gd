extends SphereSkill
class_name Skill_AlphaRegen

# Skill_AlphaRegen.gd (v1.0 - Habilidad Premium de Curación)

func _init():
	skill_id = "SK-HEAL-03"
	skill_name = "REGENERACIÓN ALFA"
	description = "Un pulso de alta energía que restaura instantáneamente 1500 HP de tu casco."
	type = "Curación"
	power_value = 1500.0
	cooldown = 20.0

func activate(player: CharacterBody2D):
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(6.0) # Bloqueo de 6s para sincronización durante la curación
	super.activate(player)
