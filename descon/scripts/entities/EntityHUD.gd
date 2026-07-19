extends Node2D

# EntityHUD.gd (v1.0 - Modular Component)
# Se encarga exclusivamente del renderizado visual de barras y tags de la entidad.

var entity = null

func setup(parent_entity):
	entity = parent_entity
	name = "EntityHUD_Component"

func _draw():
	if not is_instance_valid(entity) or entity.is_dead: return
	
	# Ocultar barras de vida y escudo en la zona de housing (100)
	var current_map = get_tree().get_first_node_in_group("map")
	if current_map and str(current_map.get("zone_id")) == "100":
		return
	
	var bar_w = 44.0; var gap = 2.0; var segments = 4
	var seg_w = (bar_w - (gap * (segments - 1.0))) / float(segments)
	
	# Usar valores interpolados de la entidad
	var sh_pct = clamp(entity._display_shield / entity.max_shield if entity.max_shield > 0 else 0.0, 0, 1)
	var hp_pct = clamp(entity._display_hp / entity.max_hp if entity.max_hp > 0 else 0.0, 0, 1)
	
	var base_y = -70.0
	if entity.is_in_group("player"): base_y = -105.0
	elif entity.entity_type >= 101: base_y = -220.0 # Boss
	
	# En modo 3D proyectado, el contenedor ya está sobre el modelo.
	# Las barras van justo en el punto de anclaje (base_y=0).
	var is_projected = entity.get_meta("is_single_world", false) and is_instance_valid(entity.world_root_3d)
	if is_projected:
		base_y = 0.0
	
	for i in range(segments):
		var x = -(bar_w / 2.0) + (i * (seg_w + gap))
		
		# Fondo (Escudo) - Cian oscuro semi-transparente
		draw_rect(Rect2(x, base_y - 10, seg_w, 4), Color(0, 1, 1, 0.25))
		var f_sh = clamp((sh_pct * segments) - i, 0.0, 1.0)
		if f_sh > 0: draw_rect(Rect2(x, base_y - 10, seg_w * f_sh, 4), Color(0, 1, 1))
		
		# Fondo (HP) - Verde oscuro semi-transparente
		draw_rect(Rect2(x, base_y - 3, seg_w, 4), Color(0, 0.8, 0, 0.25))
		var f_hp = clamp((hp_pct * segments) - i, 0.0, 1.0)
		if f_hp > 0: 
			var c = Color(0, 0.8, 0) if hp_pct > 0.3 else Color(1, 0, 0)
			draw_rect(Rect2(x, base_y - 3, seg_w * f_hp, 4), c)
