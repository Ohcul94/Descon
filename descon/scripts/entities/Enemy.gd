extends Entity

# Enemy.gd (Controlador de Enemigos Remotos v2.3 - Organic Orientation)
# Sincronización de Identidad y Orientación Táctica Dinámica.

var _last_sync_pos: Vector2 = Vector2.ZERO
var _move_dir: Vector2 = Vector2.RIGHT

func _ready():
	if not is_in_group("enemies"): add_to_group("enemies")
	super._ready()
	collision_layer = 2; collision_mask = 1
	set_z_index(10)
	_last_sync_pos = global_position

func _process(delta):
	super._process(delta)
	
	var movement = global_position - _last_sync_pos
	
	if movement.length() > 25.0:
		_move_dir = movement.normalized()
		_last_sync_pos = global_position
	
	# v268.88: La rotación ahora la maneja la clase base con interpolación delta-timed
	# Solo forzamos redibujado si no hay sprite (modo polígono)
	if not is_instance_valid(sprite) and not is_dead: 
		queue_redraw() 

func update_stats(data: Dictionary):
	super.update_stats(data)
