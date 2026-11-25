extends Node2D

# EntityHUD.gd (v2.2 - Modular Component)
# Se encarga exclusivamente del renderizado visual de barras y números de vida/escudo de la entidad.

var entity = null
var _last_is_projected: bool = false
var _last_has_shield: bool = false
var _last_max_hp: float = -1.0
var _last_max_shield: float = -1.0
var _stabilize_frames: int = 25

func setup(parent_entity):
	entity = parent_entity
	name = "EntityHUD_Component"

func get_hud_top_y() -> float:
	if not is_instance_valid(entity): return -29.0
	var is_boss = entity.entity_type >= 101 if "entity_type" in entity else false
	var bar_h = 13.0 if is_boss else 11.0
	var bar_sep = 2.0
	var gap_avatar = 5.0
	var has_shield = entity.max_shield > 0
	if has_shield:
		return -gap_avatar - (bar_h * 2.0) - bar_sep
	else:
		return -gap_avatar - bar_h

func _process(_delta):
	if not is_instance_valid(entity) or not is_inside_tree(): return
	
	var is_single = entity.get_meta("is_single_world", false)
	var is_proj = is_single and is_instance_valid(entity.world_root_3d)
	var has_sh = entity.max_shield > 0
	var cur_mhp = entity.max_hp
	var cur_msh = entity.max_shield
	
	var need_redraw = false
	if is_proj != _last_is_projected:
		_last_is_projected = is_proj
		need_redraw = true
	if has_sh != _last_has_shield:
		_last_has_shield = has_sh
		need_redraw = true
	if cur_mhp != _last_max_hp:
		_last_max_hp = cur_mhp
		need_redraw = true
	if cur_msh != _last_max_shield:
		_last_max_shield = cur_msh
		need_redraw = true
		
	# En los primeros frames tras instanciar/entrar al juego, forzar redibujado continuo hasta estabilizar
	if _stabilize_frames > 0:
		_stabilize_frames -= 1
		need_redraw = true
		
	if need_redraw:
		queue_redraw()
		if entity.has_method("_update_hud_offsets"):
			entity._update_hud_offsets()

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
	var has_shield = entity.max_shield > 0
	
	# Dimensiones ampliadas para alojar números cómodamente y dar presencia visual táctica
	var bar_w = 130.0 if is_boss else 78.0
	var bar_h = 13.0 if is_boss else 11.0
	var bar_sep = 2.0
	var gap_avatar = 5.0
	
	var is_projected = is_single and is_instance_valid(entity.world_root_3d)
	var hp_y: float
	var sh_y: float
	
	if is_projected:
		# Espaciado exacto:
		# - A 5 píxeles arriba del tope del avatar termina la base inferior de las barras
		# - Escudo va abajo (si tiene), Vida va arriba
		if has_shield:
			sh_y = -gap_avatar - bar_h
			hp_y = sh_y - bar_sep - bar_h
		else:
			hp_y = -gap_avatar - bar_h
			sh_y = 0.0
	else:
		var base_y = -35.0 if is_entity_player else (-180.0 if is_boss else -40.0)
		if has_shield:
			sh_y = base_y - gap_avatar - bar_h
			hp_y = sh_y - bar_sep - bar_h
		else:
			hp_y = base_y - gap_avatar - bar_h
			sh_y = 0.0
		
	var x0 = -(bar_w / 2.0)
	
	var cur_hp = entity._display_hp if "_display_hp" in entity else entity.current_hp
	var cur_sh = entity._display_shield if "_display_shield" in entity else entity.current_shield
	var max_hp = entity.max_hp
	var max_sh = entity.max_shield
	
	var hp_pct = clamp(cur_hp / max_hp if max_hp > 0 else 0.0, 0.0, 1.0)
	var sh_pct = clamp(cur_sh / max_sh if max_sh > 0 else 0.0, 0.0, 1.0)
	
	var show_stats = SettingsManager.show_player_stats if is_entity_player else SettingsManager.show_enemy_stats
	var use_bold = SettingsManager.bold_player_stats if is_entity_player else SettingsManager.bold_enemy_stats
	var cfg_font_size = SettingsManager.font_size_player_stats if is_entity_player else SettingsManager.font_size_enemy_stats
	var font_size = clamp(cfg_font_size, 8, 10)
	
	var font = null
	if use_bold and SettingsManager.has_method("get_bold_font"):
		font = SettingsManager.get_bold_font()
	if not font:
		font = ThemeDB.fallback_font
	
	# =========================================================================
	# 1. BARRA DE VIDA (HP) [Arriba] - Barra ENTERA sin micro cortes
	# =========================================================================
	# Fondo oscuro
	draw_rect(Rect2(x0, hp_y, bar_w, bar_h), Color(0.06, 0.08, 0.1, 0.9))
	# Track residual
	var hp_track_color = Color(0.28, 0.06, 0.06, 0.5) if hp_pct <= 0.3 else Color(0.04, 0.22, 0.08, 0.45)
	draw_rect(Rect2(x0, hp_y, bar_w, bar_h), hp_track_color)
	# Relleno de Vida continuo
	var fill_hp_w = bar_w * hp_pct
	if fill_hp_w > 0.0:
		var hp_fill_color = Color(0.1, 0.85, 0.25) if hp_pct > 0.3 else Color(1.0, 0.16, 0.16)
		draw_rect(Rect2(x0, hp_y, fill_hp_w, bar_h), hp_fill_color)
	# Borde exterior limpio
	draw_rect(Rect2(x0 - 1.0, hp_y - 1.0, bar_w + 2.0, bar_h + 2.0), Color(0.0, 0.0, 0.0, 0.95), false, 1.0)
	
	# Texto numérico de Vida centrado con reborde negro nítido de alto contraste
	if show_stats and font:
		var hp_str = str(roundi(cur_hp)) + " / " + str(roundi(max_hp))
		var ascent = font.get_ascent(font_size)
		var descent = font.get_descent(font_size)
		var text_y = hp_y + (bar_h + ascent - descent) / 2.0
		var text_w = font.get_string_size(hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var text_x = x0 + (bar_w - text_w) / 2.0
		var text_pos = Vector2(text_x, text_y)
		draw_string_outline(font, text_pos, hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color.BLACK)
		for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(font, text_pos + off, hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
		draw_string(font, text_pos, hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 1.0))
	
	# =========================================================================
	# 2. BARRA DE ESCUDO (SH) [Abajo] - Barra ENTERA sin micro cortes
	# (Solo si la entidad tiene escudo máximo > 0)
	# =========================================================================
	if has_shield:
		# Fondo oscuro
		draw_rect(Rect2(x0, sh_y, bar_w, bar_h), Color(0.06, 0.08, 0.1, 0.9))
		# Track residual
		draw_rect(Rect2(x0, sh_y, bar_w, bar_h), Color(0.02, 0.2, 0.3, 0.45))
		# Relleno de Escudo continuo
		var fill_sh_w = bar_w * sh_pct
		if fill_sh_w > 0.0:
			draw_rect(Rect2(x0, sh_y, fill_sh_w, bar_h), Color(0.0, 0.82, 1.0))
		# Borde exterior limpio
		draw_rect(Rect2(x0 - 1.0, sh_y - 1.0, bar_w + 2.0, bar_h + 2.0), Color(0.0, 0.0, 0.0, 0.95), false, 1.0)
		
		# Texto numérico de Escudo centrado con reborde negro nítido de alto contraste
		if show_stats and font:
			var sh_str = str(roundi(cur_sh)) + " / " + str(roundi(max_sh))
			var ascent_sh = font.get_ascent(font_size)
			var descent_sh = font.get_descent(font_size)
			var text_y_sh = sh_y + (bar_h + ascent_sh - descent_sh) / 2.0
			var text_w_sh = font.get_string_size(sh_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var text_x_sh = x0 + (bar_w - text_w_sh) / 2.0
			var text_pos_sh = Vector2(text_x_sh, text_y_sh)
			draw_string_outline(font, text_pos_sh, sh_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color.BLACK)
			for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_string(font, text_pos_sh + off, sh_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
			draw_string(font, text_pos_sh, sh_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 1.0))
