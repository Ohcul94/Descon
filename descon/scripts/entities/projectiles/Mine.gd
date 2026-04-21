extends Projectile
class_name Mine

# Mine.gd (v141.60 Original - Path: scripts/entities/projectiles/Mine.gd)

func _ready():
	# Las minas no se mueven (speed = 0)
	super._ready()
	speed = 0
	damage = 50 # Mucho daño por impacto

func _on_body_entered(body):
	# Explosión de mina (vfx)
	if VFXSystem:
		VFXSystem.spawn_explosion(global_position, 1.5)
	super._on_body_entered(body)
