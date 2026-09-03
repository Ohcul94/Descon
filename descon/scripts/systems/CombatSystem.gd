extends Node2D

# CombatSystem.gd (Sincronía Balística v160.2 - Phoenix Factory)
# Gestión centralizada de daño, colisiones y FACTORÍA DINÁMICA de proyectiles (sin .tscn).

@onready var world = get_parent()

func _process(_delta):
	# v165.95: Procesamiento manual eliminado. 
	# Ahora usamos las señales de área nativas de Godot para máxima precisión.
	pass

func handle_local_shoot(data): _spawn_projectile(data, "player")
func handle_remote_shoot(data): 
	# v164.96: Sincronía de Rotación (Apuntar antes de disparar)
	var sid = str(data.id)
	var world_node = get_parent()
	if is_instance_valid(world_node) and "remote_players" in world_node:
		var rp = world_node.remote_players.get(sid)
		if is_instance_valid(rp):
			rp.rotation = data.get("angle", rp.rotation)
	
	_spawn_projectile(data, "remote")

func handle_enemy_shoot(data): _spawn_projectile(data, "enemy")

func _spawn_projectile(data, o_type):
	var script_path = "res://scripts/entities/projectiles/Projectile.gd"
	var bullet_script = load(script_path)
	
	if not bullet_script:
		print("[COMBAT-ERR] No se pudo cargar el script del proyectil: ", script_path)
		return
	
	var p = Area2D.new() # Creamos el nodo base
	p.set_script(bullet_script) # Le asignamos el cerebro restaurado
	
	# v166.21: Inyectar metadatos cruciales antes del setup
	var spawn_data = data.duplicate()
	spawn_data["owner_type"] = o_type
	
	# v168.13: Asegurar visibilidad (Z-Index alto) y organización
	p.z_index = 5 
	p.top_level = false # Seguir el sistema de coordenadas del padre
	
	if is_instance_valid(world) and world.get("entities_node"):
		world.entities_node.add_child(p)
	else:
		get_parent().add_child(p)

	# v311.10: Posicionar en coordenadas globales de forma segura DESPUÉS de añadir al árbol de escenas
	var px = str(data.get("x", 0.0)).to_float()
	var py = str(data.get("y", 0.0)).to_float()
	
	# v311.20: Sincronización de origen de proyectil con la posición visual actual en el cliente para evitar lag de interpolación (lerp)
	var owner_id = str(data.get("enemyId", data.get("id", data.get("senderId", data.get("entityId", "")))))
	var spawn_pos = Vector2(px, py)
	var found_entity = null
	
	if is_instance_valid(world):
		if o_type == "player" and is_instance_valid(world.local_player):
			found_entity = world.local_player
		elif o_type == "remote" and owner_id != "" and world.get("remote_players") != null:
			found_entity = world.remote_players.get(owner_id)
		elif o_type == "enemy" and owner_id != "" and world.get("enemies") != null:
			found_entity = world.enemies.get(owner_id)
		
	if is_instance_valid(found_entity):
		spawn_pos = found_entity.global_position
	
	# Para minas de JUGADOR, spawnear en posición del target si está dentro del rango
	var mine_type = str(data.get("type", ""))
	if mine_type == "mine" and data.has("target_x") and data.has("target_y"):
		var target_pos = Vector2(str(data.target_x).to_float(), str(data.target_y).to_float())
		var mine_range = str(data.get("range", 600.0)).to_float()
		var dist_to_target = spawn_pos.distance_to(target_pos)
		if dist_to_target <= mine_range:
			spawn_pos = target_pos
	
	# Para minas de ENEMIGO, spawnear en la posición del jugador (target)
	if mine_type == "mine" and o_type == "enemy":
		var player = world.local_player if is_instance_valid(world) and is_instance_valid(world.local_player) else null
		if is_instance_valid(player):
			var mine_range = str(data.get("range", 800.0)).to_float()
			var dist_to_player = spawn_pos.distance_to(player.global_position)
			if dist_to_player <= mine_range:
				spawn_pos = player.global_position
	
	p.global_position = spawn_pos
	
	var fire_angle = str(data.get("angle", 0.0)).to_float()
	p.rotation = fire_angle
	
	# v165.96: Inicialización CENTRALIZADA via setup()
	if p.has_method("setup"):
		p.setup(p.global_position, p.rotation, spawn_data)
	
	# v266.190: Eliminado override de color forzado. 
	# Projectile.gd ahora gestiona sus propios colores según el bulletType.

func _on_enemy_hit(enemy, b):
	var dmg = b.get("damage") if b.get("damage") else 100.0
	enemy.take_damage(dmg)
	if NetworkManager: NetworkManager.send_event("enemyHit", {"enemyId": enemy.entity_id, "damage": dmg})

func _on_local_player_hit(p, b):
	if p.get("is_god") or p.get("is_dead"): return
	var dmg = b.get("damage") if b.get("damage") else 100.0
	p.take_damage(dmg)
	if NetworkManager: 
		NetworkManager.send_event("playerHitByEnemy", {
			"damage": dmg, 
			"attackerType": b.get("owner_type"),
			"attackerId": b.get("owner_id"),
			"bulletType": b.get("type")
		})

func clear_boss_bullets(boss_id: String):
	var bullets = get_tree().get_nodes_in_group("projectiles")
	var count = 0
	for b in bullets:
		if is_instance_valid(b) and str(b.get("owner_id")) == boss_id:
			b.queue_free()
			count += 1
	if count > 0:
		print("[COMBAT] Limpieza selectiva: ", count, " proyectiles de ", boss_id, " eliminados.")

func clear_all_bullets():
	var bullets = get_tree().get_nodes_in_group("projectiles")
	for b in bullets:
		if is_instance_valid(b): b.queue_free()
	print("[COMBAT] Limpieza total de munición del sector completada.")
