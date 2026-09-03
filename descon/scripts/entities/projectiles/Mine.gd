extends Projectile
class_name Mine

# Mine.gd (v141.60 Original - Path: scripts/entities/projectiles/Mine.gd)

func _ready():
	# Las minas no se mueven (speed = 0)
	super._ready()
	if not _is_setup:
		speed = 0
		damage = 50 # Mucho daño por impacto

func _on_body_entered(body):
	# Explosión de mina (vfx) - usar radio configurable de explosionRadius
	if VFXSystem:
		var explosion_scale = _bomb_radius / 100.0 if _bomb_radius > 0 else 1.5
		VFXSystem.spawn_explosion(global_position, explosion_scale)
	super._on_body_entered(body)
