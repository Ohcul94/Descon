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
	
	# v2.3: Orientación Orgánica (Mover la punta hacia el destino)
	# Calculamos el vector de movimiento real entre paquetes de red
	var movement = global_position - _last_sync_pos
	if movement.length() > 0.5:
		_move_dir = movement.normalized()
		_last_sync_pos = global_position
	
	# Lerp suave de rotación hacia la dirección de avance (igual que el player)
	rotation = lerp_angle(rotation, _move_dir.angle(), 0.15)
	
	# Redibujar para asegurar que el cuerpo siga la rotación (v187)
	queue_redraw()

func update_stats(data: Dictionary):
	super.update_stats(data)
	_ensure_correct_name()

func _ensure_correct_name():
	if username == "Unknown" or username == "Piloto" or username == "Enemigo":
		match entity_type:
			4: username = "LORD TITÁN"
			5: username = "ANCIENT BOSS"
			2: username = "Nave Renegada T2"
			3: username = "Nave Renegada T3"
			_: username = "Nave Renegada T1"
	_update_tags()

func _adjust_visuals(_type):
	pass
