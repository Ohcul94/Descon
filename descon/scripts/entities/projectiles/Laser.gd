extends Projectile
class_name Laser

# Laser.gd (v141.60 Original - Path: scripts/entities/projectiles/Laser.gd)

func _ready():
	super._ready()
	speed = 1200 # El láser es el proyectil más rápido
	damage = 8

func _on_body_entered(body):
	# Lógica específica de impacto láser (partículas rápidas)
	super._on_body_entered(body)
