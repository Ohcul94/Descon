extends SphereSkill
class_name Skill_Reflect

func _init():
	skill_name = "REFLECT-OMEGA"
	description = "Crea un campo de resonancia que refleja daño hostil."
	type = "Ataque"
	power_value = 500.0

func activate(player: CharacterBody2D):
	var dur = 3.0
	if player.has_method("_get_skill_duration"):
		dur = player._get_skill_duration(skill_name, {}, 3.0)

	if player.has_method("activate_sync_lock"):
		player.activate_sync_lock(dur + 0.5)

	if "reflect_timer" in player:
		player.reflect_timer = dur
		print("[SKILL] Reflect activado por ", dur, "s para ", player.name)

	super.activate(player)
