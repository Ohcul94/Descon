extends Node2D

# EntityHUD.gd (v1.0 - Modular Component)
# Se encarga exclusivamente del renderizado visual de barras y tags de la entidad.

var entity = null

func setup(parent_entity):
	entity = parent_entity
	name = "EntityHUD_Component"

func _draw():
	if not is_instance_valid(entity) or entity.is_dead: return
	if not visible or not entity.visible: return
	if entity.get_meta("is_pooled", false): return
	if "current_hp" in entity and entity.current_hp <= 0.0: return
	if not entity.is_inside_tree() or not is_inside_tree(): return
	
	# Si la entidad usa el Lienzo 3D Único pero su modelo no está instanciado o no está visible, no dibujar
	var is_single = entity.get_meta("is_single_world", false)
	if is_single and (not is_instance_valid(entity.world_root_3d) or not entity.world_root_3d.visible):
		return
	
	# Ocultar barras de vida y escudo en la zona de housing (100)
	var current_map = get_tree().get_first_node_in_group("map")
	if current_map and str(current_map.get("zone_id")) == "100":
		return
	
	# Ocultar barras según configuración del jugador
	var is_entity_player = entity.is_in_group("player") or entity.is_in_group("remote_players")
	
	# Reglas estrictas para enemigos: si no tiene nombre válido o está en mecánicas ocultas, jamás dibujar barras
	if not is_entity_player:
		var u_name = entity.username.strip_edges()
		if u_name == "" or u_name == "Unknown":
			return
		if entity.get("is_burrowed") and not entity.get("_burrow_emerging"):
			return
		if entity.get("_is_currently_invisible"):
			return
	
	var show_bars = SettingsManager.show_player_bars if is_entity_player else SettingsManager.show_enemy_bars
	if not show_bars:
		return
	
	var is_boss = entity.entity_type >= 101 if "entity_type" in entity else false
	var bar_w = 90.0 if is_boss else 60.0
	var segments = 6 if is_boss else 4
	var gap = 2.0
	var seg_w = (bar_w - (gap * (segments - 1.0))) / float(segments)
	var bar_h = 4.5
	
	var has_shield = entity.max_shield > 0
	var sh_pct = clamp(entity._display_shield / entity.max_shield if has_shield else 0.0, 0.0, 1.0)
	var hp_pct = clamp(entity._display_hp / entity.max_hp if entity.max_hp > 0 else 0.0, 0.0, 1.0)
	
	var is_projected = entity.get_meta("is_single_world", false) and is_instance_valid(entity.world_root_3d)
	var base_y = 0.0
	if not is_projected:
		if is_entity_player: base_y = -105.0
		elif is_boss: base_y = -220.0
		else: base_y = -70.0
	
	var sh_y = base_y - (bar_h * 2.0 + 2.0) # base_y - 11.0
	var hp_y = base_y - bar_h              # base_y - 4.5
	
	for i in range(segments):
		var x = -(bar_w / 2.0) + (i * (seg_w + gap))
		
		# Fondo y Barra de Escudo (solo si la entidad tiene escudo máximo > 0)
		if has_shield:
			draw_rect(Rect2(x - 0.5, sh_y - 0.5, seg_w + 1.0, bar_h + 1.0), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x, sh_y, seg_w, bar_h), Color(0, 1, 1, 0.25))
			var f_sh = clamp((sh_pct * segments) - i, 0.0, 1.0)
			if f_sh > 0.0:
				draw_rect(Rect2(x, sh_y, seg_w * f_sh, bar_h), Color(0, 1, 1))
		
		# Fondo y Barra de HP
		draw_rect(Rect2(x - 0.5, hp_y - 0.5, seg_w + 1.0, bar_h + 1.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(x, hp_y, seg_w, bar_h), Color(0, 0.8, 0, 0.25))
		var f_hp = clamp((hp_pct * segments) - i, 0.0, 1.0)
		if f_hp > 0.0:
			var c = Color(0, 0.85, 0.1) if hp_pct > 0.3 else Color(1, 0.15, 0.15)
			draw_rect(Rect2(x, hp_y, seg_w * f_hp, bar_h), c)
