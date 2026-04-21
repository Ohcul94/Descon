extends SphereSkill
class_name Skill_Fortress

func _init():
	skill_name = "FORTALEZA-X"
	description = "Sobrecarga los escudos incrementando la resistencia momentáneamente."
	type = "Defensa"
	power_value = 1200.0
	cooldown = 15.0

func activate(player: CharacterBody2D):
	if "current_shield" in player:
		player.current_shield += 500
		print("[SKILL] Fortaleza-X activada: +500 SH")
	super.activate(player)
