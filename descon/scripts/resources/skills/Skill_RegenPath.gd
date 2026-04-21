extends SphereSkill
class_name Skill_RegenPath

func _init():
	skill_name = "NANO-REGENERACIÓN"
	description = "Inyecta nanobots que reparan el casco de forma continua."
	type = "Curación"
	power_value = 300.0
	cooldown = 12.0

func activate(player: CharacterBody2D):
	if "hp_regen" in player:
		# Temporal HP regen buff
		print("[SKILL] Nano-Regeneración activada")
	super.activate(player)
