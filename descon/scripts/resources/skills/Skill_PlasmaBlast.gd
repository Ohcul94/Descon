extends SphereSkill
class_name Skill_PlasmaBlast

func _init():
	skill_name = "PLASMA BLAST"
	description = "Disparo concentrado de plasma con alta potencia destructiva."
	type = "Ataque"
	power_value = 850.0
	cooldown = 8.0

func activate(player: CharacterBody2D):
	# Lógica visual de disparo (Placeholder por ahora)
	print("[SKILL] Plasma Blast activado por ", player.name)
	super.activate(player)
