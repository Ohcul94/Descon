extends Entity

# Enemy.gd (Controlador de Enemigos Remotos v2.3 - Organic Orientation)
# Sincronización de Identidad y Orientación Táctica Dinámica.

var _last_sync_pos: Vector2 = Vector2.ZERO
var _move_dir: Vector2 = Vector2.RIGHT

func _ready():
	super._ready()
	if not is_in_group("enemies"): add_to_group("enemies")
	collision_layer = 2; collision_mask = 1
	_ensure_correct_name(); set_z_index(10)
	_last_sync_pos = global_position

func _process(delta):
	super._process(delta)
	
	var movement = global_position - _last_sync_pos
	
	# Filtro draconiano (25.0 px) para matar hasta el más mínimo eco de lag del server y asegurar giro limpio
	if movement.length() > 25.0:
		_move_dir = movement.normalized()
		_last_sync_pos = global_position
	
	# Restauramos la simulación súper lenta "tipo crucero" que mitiga los temblequeos visuales (0.015)
	rotation = lerp_angle(rotation, _move_dir.angle(), 0.015)
	
	# Redibujar para asegurar que el cuerpo siga la rotación (v187)
	queue_redraw()

func update_stats(data: Dictionary):
	super.update_stats(data)
	_ensure_correct_name()

func _ensure_correct_name():
	match entity_type:
		6: username = "GUARDIÁN CIBERNÉTICO"
		4: username = "LORD TITÁN"
		5: username = "ANCIENT BOSS"
		2: username = "Nave Renegada T2"
		3: username = "Nave Renegada T3"
		_: username = "Nave Renegada T1"
	_update_tags()
