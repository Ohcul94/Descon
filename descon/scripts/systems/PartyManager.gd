extends Node

# PartyManager.gd (Escuadron v141.65)
# Sincronización de HP/SH y gestión de invitaciones.

signal party_updated(data)
signal invitation_received(from_name, from_id)

var current_party = null

func _ready():
	if NetworkManager:
		NetworkManager.party_invitation.connect(_on_invitation_received)
		NetworkManager.party_update.connect(_on_party_updated)

func invite_player(player_name: String):
	if player_name != "" and NetworkManager:
		NetworkManager.send_event("inviteToParty", player_name)
		print("[PARTY] INVITANDO A: " + player_name)

func accept_invitation(from_id: String):
	if NetworkManager:
		NetworkManager.send_event("acceptParty", from_id)
		print("[PARTY] ACEPTANDO INVITACION DE " + from_id)

func leave_party():
	if NetworkManager:
		NetworkManager.send_event("leaveParty", {})
		current_party = null
		party_updated.emit(null)
		print("[PARTY] ABANDONASTE EL GRUPO")

func _on_invitation_received(data):
	var f_name = data.get("from", "Piloto")
	var f_id = data.get("fromId", "")
	invitation_received.emit(f_name, f_id)

func _on_party_updated(data):
	current_party = data
	party_updated.emit(data)
	var count = 0
	if data and data.has("members"):
		count = data["members"].size()
	print("[PARTY] ACTUALIZADO - MIEMBROS: " + str(count))

func get_member_stats(id: String, p_name: String):
	# Objeto de respuesta seguro (Fallback)
	var res = {"hp": 0, "max_hp": 1, "shield": 0, "max_shield": 1}
	
	# Caso 1: Piloto Local
	var lp = get_tree().get_first_node_in_group("player")
	if is_instance_valid(lp):
		var mid = (lp.entity_id == id and id != "")
		var mnm = (lp.username.to_lower() == p_name.to_lower())
		if mid or mnm:
			res["hp"] = lp.current_hp; res["max_hp"] = lp.max_hp
			res["shield"] = lp.current_shield; res["max_shield"] = lp.max_shield
			return res
			
	# Caso 2: Pilotos en la zona (Remotos)
	var world = get_tree().get_first_node_in_group("world_node")
	if is_instance_valid(world):
		var rp = world.remote_players.get(id)
		if not is_instance_valid(rp):
			for p in world.remote_players.values():
				if is_instance_valid(p) and p.username.to_lower() == p_name.to_lower():
					rp = p; break
		
		if is_instance_valid(rp):
			res["hp"] = rp.current_hp; res["max_hp"] = rp.max_hp
			res["shield"] = rp.current_shield; res["max_shield"] = rp.max_shield
			
	return res
