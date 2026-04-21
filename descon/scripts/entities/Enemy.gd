extends Entity

# Enemy.gd (Controlador de Enemigos Remotos v2.3 - Organic Orientation)
# Sincronización de Identidad y Orientación Táctica Dinámica.

var _last_sync_pos: Vector2 = Vector2.ZERO
var _move_dir: Vector2 = Vector2.RIGHT

func _ready():
	super._ready()
	if not is_in_group("enemies"): add_to_group("enemies")
	collision_layer = 2; collision_mask = 1
	set_z_index(10)
	_last_sync_pos = global_position

func _process(delta):
	super._process(delta)
	
	var movement = global_position - _last_sync_pos
	
	if movement.length() > 25.0:
		_move_dir = movement.normalized()
		_last_sync_pos = global_position
	
	rotation = lerp_angle(rotation, _move_dir.angle(), 0.015)
	queue_redraw()

func update_stats(data: Dictionary):
	super.update_stats(data)
