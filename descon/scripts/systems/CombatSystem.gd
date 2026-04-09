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
	
	p.global_position = Vector2(data.x, data.y)
	p.rotation = data.get("angle", 0.0)
	
	# v168.13: Asegurar visibilidad (Z-Index alto) y organización
	p.z_index = 5 
	p.top_level = false # Seguir el sistema de coordenadas del padre
	
	if is_instance_valid(world) and world.get("entities_node"):
		world.entities_node.add_child(p)
	else:
		get_parent().add_child(p)

	# v165.96: Inicialización CENTRALIZADA via setup()
	if p.has_method("setup"):
		p.setup(p.global_position, p.rotation, spawn_data)
	
	# Ajustes extra de equipo/render
	if o_type == "enemy" or o_type == "server":
		p.modulate = Color(1.0, 0.3, 0.3) # Rojo Vivo
	else:
		p.modulate = Color(0.3, 1.0, 1.0) # Cyan Brillante

func _on_enemy_hit(enemy, b):
	var dmg = b.get("damage") if b.get("damage") else 100.0
	enemy.take_damage(dmg)
	if NetworkManager: NetworkManager.send_event("enemyHit", {"enemyId": enemy.entity_id, "damage": dmg})

func _on_local_player_hit(p, b):
	if p.get("is_god") or p.get("is_dead"): return
	var dmg = b.get("damage") if b.get("damage") else 100.0
	p.take_damage(dmg)
	if NetworkManager: NetworkManager.send_event("playerHitByEnemy", {"damage": dmg, "attackerType": b.get("owner_type")})
