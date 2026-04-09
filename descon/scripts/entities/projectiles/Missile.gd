extends Projectile
class_name Missile

# Missile.gd (v141.70 - STABLE RECOVERY)

func _ready():
	super._ready()
	speed = 500
	damage = 25
	type = "missile"

func _physics_process(delta):
	super._physics_process(delta)
	# v141.70: Motor simple para mantener compatibilidad con Godot 4
