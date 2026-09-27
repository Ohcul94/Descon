extends SphereSkill
class_name Skill_Hookshot

func _init():
	skill_id = "SK-ATK-03"
	skill_name = "HOOKSHOT"
	description = "Dispara un gancho que viaja hacia el enemigo, dañándolo y arrastrándote hasta él."
	type = "Ataque"
	power_value = 300.0
	cooldown = 12.0

func activate(player: CharacterBody2D):
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(0.5)
	super.activate(player)
