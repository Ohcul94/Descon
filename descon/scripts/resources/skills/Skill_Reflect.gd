extends SphereSkill
class_name Skill_Reflect

func _init():
	skill_name = "REFLECT-Ω"
	description = "Crea un campo de resonancia que refleja daño hostil."
	type = "Ataque"
	power_value = 500.0

func activate(player: CharacterBody2D):
	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(5.0)
	
	if "reflect_timer" in player:
		player.reflect_timer = 3.0
		print("[SKILL] Reflect activado por 3s para ", player.name)
		
	super.activate(player)
