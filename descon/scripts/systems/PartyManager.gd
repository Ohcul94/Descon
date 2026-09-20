extends Node

# PartyManager.gd (Escuadron v141.66)
# Sincronización de HP/SH, gestión de invitaciones y roles de party.

signal party_updated(data)
signal invitation_received(from_name, from_id)

const ROLE_ICONS = {
	"tank": "res://assets/ui/icons/role_tank.png",
	"healer": "res://assets/ui/icons/role_healer.png",
	"buffer": "res://assets/ui/icons/role_buffer.png",
	"dps": "res://assets/ui/icons/role_dps.png"
}

var current_party = null

func _ready():
	if NetworkManager:
		if not NetworkManager.party_invitation.is_connected(_on_invitation_received):
			NetworkManager.party_invitation.connect(_on_invitation_received)
		if not NetworkManager.party_update.is_connected(_on_party_updated):
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

func kick_player(target_id: String):
	if NetworkManager and target_id != "":
		NetworkManager.send_event("kickFromParty", target_id)
		print("[PARTY] EXPULSANDO MIEMBRO ID: " + target_id)

func _on_invitation_received(data):
	var f_name = data.get("from", "Piloto")
	var f_id = data.get("fromId", "")
	invitation_received.emit(f_name, f_id)

func _on_party_updated(data):
	if data == null:
		current_party = null
	elif typeof(data) == TYPE_DICTIONARY:
		var lp = get_tree().get_first_node_in_group("player")
		var is_member = false
		if is_instance_valid(lp):
			var my_id = str(lp.db_id)
			var my_name = str(lp.username).to_lower()
			var members = data.get("members", [])
			var names = data.get("names", [])
			for m in members:
				if str(m) == my_id and my_id != "":
					is_member = true
					break
			if not is_member and my_name != "":
				for n in names:
					if str(n).to_lower() == my_name:
						is_member = true
						break
		else:
			is_member = true
		
		if is_member:
			current_party = data
		else:
			if current_party != null:
				current_party = null
	else:
		current_party = null

	party_updated.emit(current_party)
	var count = 0
	if current_party and current_party.has("members"):
		count = current_party["members"].size()
	print("[PARTY] ACTUALIZADO - MIEMBROS: " + str(count))
	
	# Forzar actualización inmediata de las etiquetas de todos los jugadores en pantalla
	for ent in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(ent) and ent.has_method("_force_update_tags"):
			ent._force_update_tags()
	var lp_ref = get_tree().get_first_node_in_group("player")
	if is_instance_valid(lp_ref) and lp_ref.has_method("_force_update_tags"):
		lp_ref._force_update_tags()

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

# ── Sistema de Roles de Party (Estilo WOW) ──

func set_role(member_id: String, role: String):
	if not NetworkManager or not current_party:
		return
	NetworkManager.send_event("setPartyRole", {"targetId": member_id, "role": role})
	print("[PARTY] SET ROLE: " + member_id + " → " + role)

func is_leader() -> bool:
	if not current_party:
		return false
	var lp = get_tree().get_first_node_in_group("player")
	if is_instance_valid(lp):
		return lp.db_id == current_party.id
	return false

func get_member_role(member_id_or_name: String) -> String:
	if not current_party or not current_party.has("roles"):
		return ""
	var roles = current_party.get("roles", {})
	if typeof(roles) != TYPE_DICTIONARY:
		return ""
	if roles.has(member_id_or_name):
		return str(roles[member_id_or_name])
	
	# Buscar por nombre si nos pasaron username:
	if current_party.has("members") and current_party.has("names"):
		var members = current_party["members"]
		var names = current_party["names"]
		for i in range(min(members.size(), names.size())):
			if str(names[i]).to_lower() == member_id_or_name.to_lower():
				var uid = str(members[i])
				return str(roles.get(uid, ""))
			if str(members[i]) == member_id_or_name:
				return str(roles.get(members[i], ""))
	return ""

func get_role_icon_path(role: String) -> String:
	return ROLE_ICONS.get(role, "")
