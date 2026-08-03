extends Node2D
# v410.2: Vinculo de Robador de Escudo (SHIELD_STEAL)
# Gestor de duración del vínculo. El VFX por tick se genera directamente
# en el SubViewport 3D desde EntityManager._handle_shield_steal_action.

var enemy_node: Node2D = null
var target_node_id: String = ""
var duration_ms: float = 5000.0
var steal_amount: float = 100.0
var steal_mode: String = "flat"
var _life: float = 0.0

var _server_enemy_pos: Vector2 = Vector2.ZERO
var _has_server_enemy_pos: bool = false

func _ready() -> void:
	z_index = 100
	z_as_relative = false
	visible = true
	show()

func setup(data: Dictionary, p_enemy_node: Node2D = null) -> void:
	enemy_node = p_enemy_node
	duration_ms = float(data.get("duration", 5000.0))
	steal_mode = str(data.get("stealMode", "percent"))
	steal_amount = float(data.get("stealAmount", 25.0))
	target_node_id = str(data.get("targetId", get_meta("targetId", "")))
	if data.has("ex") and data.has("ey"):
		_server_enemy_pos = Vector2(float(data.get("ex", 0.0)), float(data.get("ey", 0.0)))
		_has_server_enemy_pos = true

func update_enemy_position(p_ex: float, p_ey: float) -> void:
	_server_enemy_pos = Vector2(float(p_ex), float(p_ey))
	_has_server_enemy_pos = true

func get_target_node() -> Node2D:
	var t_id: String = target_node_id
	if t_id == "":
		return null
	var world = get_tree().get_first_node_in_group("world_node")
	if not is_instance_valid(world):
		world = get_tree().get_first_node_in_group("world")
	if is_instance_valid(world):
		if is_instance_valid(world.local_player) and t_id == str(world.local_player.entity_id):
			return world.local_player
		var em = world.get_node_or_null("EntityManager")
		if is_instance_valid(em):
			if "remote_players" in em and em.remote_players.has(t_id):
				return em.remote_players[t_id]
			if "enemies" in em and em.enemies.has(t_id):
				return em.enemies[t_id]
		if "remote_players" in world and world.remote_players.has(t_id):
			return world.remote_players[t_id]
	var nodes = get_tree().get_nodes_in_group("player")
	for nd in nodes:
		if str(nd.get("entity_id")) == t_id:
			return nd
	return null

func get_enemy_pos() -> Vector2:
	if is_instance_valid(enemy_node):
		return enemy_node.global_position
	if _has_server_enemy_pos:
		return _server_enemy_pos
	return global_position

func _process(delta: float) -> void:
	_life += delta
	if _life > (duration_ms / 1000.0) + 1.5:
		queue_free()

func update_tick_flash() -> void:
	# Destello rápido al recibir un tick de robo (llamado desde EntityManager)
	var tw = create_tween()
	tw.tween_property(self, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.07)
	tw.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.14)
