extends Control

# EstadisticasTab.gd - Panel completo de estadísticas del jugador
# Muestra base de nave, modificadores de equipamiento, esferas, talentos y stats finales.

var inv_main = null

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	# Limpiar
	for n in get_children():
		remove_child(n)
		n.queue_free()

	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		var err = Label.new()
		err.text = "ESPERANDO CONEXIÓN CON EL PILOTO..."
		err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err.modulate = Color.CYAN
		err.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		add_child(err)
		return

	_build_ui(player)

func _build_ui(player):
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	var master_v = VBoxContainer.new()
	master_v.name = "StatsMasterVBox"
	master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	master_v.add_theme_constant_override("separation", 6)
	master_v.mouse_filter = Control.MOUSE_FILTER_PASS
	master_v.clip_contents = true
	add_child(master_v)

	# Header
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	master_v.add_child(header)

	var title_lbl = Label.new()
	title_lbl.text = "📊 CENTRO DE ESTADÍSTICAS DEL PILOTO"
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.modulate = Color(0, 0.82, 1)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var refresh_btn = Button.new()
	refresh_btn.text = "🔄 REFRESCAR"
	refresh_btn.custom_minimum_size = Vector2(100, 28)
	refresh_btn.pressed.connect(func(): update_ui())
	header.add_child(refresh_btn)

	# Scroll principal
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	master_v.add_child(scroll)

	var content_v = VBoxContainer.new()
	content_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_v.add_theme_constant_override("separation", 8)
	content_v.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content_v)

	# Recopilar datos
	var ship_base = _get_ship_base(player)
	var equip_mods = _get_equipment_modifiers(player)
	var sphere_mods = _get_sphere_modifiers(player)
	var talent_bonuses = _get_talent_bonuses(player)
	var final_stats = _calculate_final(player, ship_base, equip_mods, sphere_mods, talent_bonuses)

	# ═══ SECCIÓN 1: STATS FINALES (PRIMERO - Lo más importante) ═══
	_add_section_header(content_v, "📈 STATS FINALES CALCULADOS", Color(0.0, 1.0, 0.5))

	_add_final_stat_row(content_v, "❤️ Vida Máxima", final_stats.hp, player.current_hp, Color(0.2, 1.0, 0.3))
	_add_final_stat_row(content_v, "🛡️ Escudo Máximo", final_stats.shield, player.current_shield, Color(0.3, 0.7, 1.0))
	_add_final_stat_row(content_v, "🚀 Velocidad Final", final_stats.speed, 0.0, Color(1.0, 0.9, 0.2))
	_add_final_stat_row(content_v, "💥 Daño", final_stats.damage, 0.0, Color(1.0, 0.3, 0.2))
	_add_stat_row(content_v, "👁️ Rango de Visión", final_stats.vision, Color(0.6, 0.6, 0.8))

	_add_separator(content_v)
	_add_sub_header(content_v, "🔧 Regeneración", Color(0.4, 0.8, 0.6))
	_add_stat_row(content_v, "Regen. de Vida", player.hp_regen, Color(0.2, 1.0, 0.3))
	_add_stat_row(content_v, "Regen. de Escudo", player.sh_regen, Color(0.3, 0.7, 1.0))

	# ═══ SECCIÓN 2: NAVE ACTUAL ═══
	_add_section_header(content_v, "🚀 NAVE ACTUAL", Color(0, 0.82, 1))
	var ship_name = _get_ship_name(player.current_ship_id)
	_add_info_row(content_v, "Modelo", ship_name, Color.WHITE)
	_add_info_row(content_v, "ID", str(player.current_ship_id), Color.GRAY)
	_add_info_row(content_v, "Nivel", str(player.level), Color(0.3, 1.0, 0.5))
	_add_exp_bar(content_v, player)

	# ═══ SECCIÓN 3: STATS BASE DE NAVE ═══
	_add_section_header(content_v, "📐 STATS BASE (Nave)", Color(0.0, 0.9, 0.7))
	_add_stat_row(content_v, "HP Base", ship_base.hp, Color(0.2, 1.0, 0.3))
	_add_stat_row(content_v, "Escudo Base", ship_base.shield, Color(0.3, 0.7, 1.0))
	_add_stat_row(content_v, "Velocidad Base", ship_base.speed, Color(1.0, 0.9, 0.2))
	_add_stat_row(content_v, "Daño Base", ship_base.base_dmg, Color(1.0, 0.3, 0.2))
	_add_stat_row(content_v, "Visión", ship_base.vision, Color(0.6, 0.6, 0.8))

	# ═══ SECCIÓN 4: MODIFICADORES DE EQUIPAMIENTO ═══
	_add_section_header(content_v, "⚙️ MODIFICADORES DE EQUIPAMIENTO", Color(1.0, 0.6, 0.0))

	# Weapons
	if equip_mods.weapons.size() > 0:
		_add_sub_header(content_v, "🔫 Armas Equipadas", Color(1.0, 0.4, 0.3))
		for w in equip_mods.weapons:
			_add_item_mod_row(content_v, w.name, "Daño", w.base_dmg, "+")
			if w.hp_mod != 0.0:
				_add_item_mod_row(content_v, "", "HP Mod", w.hp_mod, "+" if w.hp_mod > 0 else "", w.hp_mod_flat)
			if w.speed_mod != 0.0:
				_add_item_mod_row(content_v, "", "Vel. Mod", w.speed_mod, "+" if w.speed_mod > 0 else "", w.speed_mod_flat)

	# Shields
	if equip_mods.shields.size() > 0:
		_add_sub_header(content_v, "🛡️ Escudos Equipados", Color(0.3, 0.7, 1.0))
		for s in equip_mods.shields:
			_add_item_mod_row(content_v, s.name, "Escudo", s.base_val, "+")
			if s.hp_mod != 0.0:
				_add_item_mod_row(content_v, "", "HP Mod", s.hp_mod, "+" if s.hp_mod > 0 else "", s.hp_mod_flat)
			if s.speed_mod != 0.0:
				_add_item_mod_row(content_v, "", "Vel. Mod", s.speed_mod, "+" if s.speed_mod > 0 else "", s.speed_mod_flat)

	# Engines
	if equip_mods.engines.size() > 0:
		_add_sub_header(content_v, "🚀 Motores Equipados", Color(1.0, 0.8, 0.0))
		for e in equip_mods.engines:
			_add_item_mod_row(content_v, e.name, "Velocidad", e.base_val, "+")
			if e.shield_mod != 0.0:
				_add_item_mod_row(content_v, "", "Escudo Mod", e.shield_mod, "+" if e.shield_mod > 0 else "", e.shield_mod_flat)
			if e.hp_mod != 0.0:
				_add_item_mod_row(content_v, "", "HP Mod", e.hp_mod, "+" if e.hp_mod > 0 else "", e.hp_mod_flat)

	# Extras
	if equip_mods.extras.size() > 0:
		_add_sub_header(content_v, "🔧 Extras Equipados", Color(0.8, 0.5, 1.0))
		for x in equip_mods.extras:
			_add_item_mod_row(content_v, x.name, "HP Base", x.base_val, "+")

	# Totales de equipamiento
	if equip_mods.total_hp != 0.0 or equip_mods.total_shield != 0.0 or equip_mods.total_speed != 0.0 or equip_mods.total_dmg != 0.0:
		_add_separator(content_v)
		_add_sub_header(content_v, "📊 TOTAL Equipamiento", Color(1.0, 0.85, 0.3))
		if equip_mods.total_hp != 0.0:
			_add_mod_summary(content_v, "HP Equip", equip_mods.total_hp, equip_mods.hp_mod_pct)
		if equip_mods.total_shield != 0.0:
			_add_mod_summary(content_v, "Escudo Equip", equip_mods.total_shield, equip_mods.shield_mod_pct)
		if equip_mods.total_speed != 0.0:
			_add_mod_summary(content_v, "Vel. Equip", equip_mods.total_speed, equip_mods.speed_mod_pct)
		if equip_mods.total_dmg != 0.0:
			_add_mod_summary(content_v, "Daño Equip", equip_mods.total_dmg, 0.0)

	# ═══ SECCIÓN 5: MODIFICADORES DE ESFERAS ═══
	_add_section_header(content_v, "🔮 MODIFICADORES DE ESFERAS", Color(0.8, 0.3, 1.0))
	var sm = player.get_node_or_null("SpheresManager")
	var config_spheres_display = []
	if NetworkManager and NetworkManager.server_config:
		config_spheres_display = NetworkManager.server_config.get("shopItems", {}).get("spheres", [])
	if is_instance_valid(sm):
		var has_any_sphere = false
		for i in range(min(sm.spheres_data.size(), 4)):
			var sd = sm.spheres_data[i]
			var sphere = sd.get("sphere")
			if sphere != null and typeof(sphere) == TYPE_DICTIONARY:
				has_any_sphere = true
				var s_name = str(sphere.get("name", sphere.get("id", "Esfera " + str(i + 1))))
				var s_color = str(sphere.get("type", sphere.get("sphereColor", "Desconocido")))
				_add_info_row(content_v, "Slot " + str(i + 1), s_name + " (" + s_color + ")", Color(0.8, 0.5, 1.0))
				# Buscar stats en la config maestra (mismo lookup que _get_sphere_modifiers)
				var sphere_id = str(sphere.get("id", ""))
				var master_stats_display = {}
				for ms in config_spheres_display:
					if str(ms.get("id", "")) == sphere_id:
						master_stats_display = ms.get("stats", {})
						break
				if master_stats_display.is_empty():
					master_stats_display = sphere.get("stats", {})
				# Mostrar cada stat de la esfera
				if typeof(master_stats_display) == TYPE_DICTIONARY:
					for key in master_stats_display:
						_add_stat_mod_row(content_v, "  " + _get_stat_key_display(key), float(master_stats_display[key]))
				elif typeof(master_stats_display) == TYPE_ARRAY:
					for entry in master_stats_display:
						if typeof(entry) == TYPE_DICTIONARY:
							_add_stat_mod_row(content_v, "  " + _get_stat_key_display(str(entry.get("key", ""))), float(entry.get("val", 0)))
		if not has_any_sphere:
			_add_info_row(content_v, "", "Sin esferas instaladas", Color.GRAY)
	else:
		_add_info_row(content_v, "", "Sistema de esferas no disponible", Color.GRAY)

	if sphere_mods.total_hp != 0.0 or sphere_mods.total_shield != 0.0 or sphere_mods.total_speed != 0.0 or sphere_mods.total_heal_pct != 0.0:
		_add_separator(content_v)
		_add_sub_header(content_v, "📊 TOTAL Esferas", Color(0.8, 0.5, 1.0))
		if sphere_mods.total_hp != 0.0:
			_add_stat_row(content_v, "HP Esferas", sphere_mods.total_hp, Color(0.8, 0.5, 1.0))
		if sphere_mods.total_shield != 0.0:
			_add_stat_row(content_v, "Escudo Esferas", sphere_mods.total_shield, Color(0.8, 0.5, 1.0))
		if sphere_mods.total_speed != 0.0:
			_add_stat_row(content_v, "Vel. Esferas", sphere_mods.total_speed, Color(0.8, 0.5, 1.0))
		if sphere_mods.total_heal_pct != 0.0:
			_add_stat_row(content_v, "Curación Esferas", sphere_mods.total_heal_pct, Color(0.8, 0.5, 1.0))

	# ═══ SECCIÓN 6: BONIFICACIONES DE TALENTOS ═══
	_add_section_header(content_v, "🌟 BONIFICACIONES DE TALENTOS", Color(0.75, 0.2, 1.0))
	var ts = get_tree().get_first_node_in_group("talent_system")
	if is_instance_valid(ts):
		var bonuses = ts.get_bonuses()
		var has_any_bonus = false
		for key in bonuses:
			var val = float(bonuses[key])
			if abs(val) > 0.0001:
				has_any_bonus = true
				var is_flat = key.ends_with("_flat")
				var display_name = _get_effect_display_name(key)
				_add_talent_bonus_row(content_v, display_name, val, is_flat)
		if not has_any_bonus:
			_add_info_row(content_v, "", "Sin talentos asignados", Color.GRAY)

		# Desbloqueos
		var unlocks = ts.get_talent_unlocks()
		if unlocks.size() > 0:
			_add_separator(content_v)
			_add_sub_header(content_v, "🔓 Desbloqueos Activos", Color(0.65, 0.4, 0.9))
			for uid in unlocks:
				_add_info_row(content_v, "", uid, Color(0.75, 0.5, 1.0))

		# Bonuses dinámicos
		var dynamic = ts.get_dynamic_bonuses()
		if dynamic.size() > 0:
			_add_separator(content_v)
			_add_sub_header(content_v, "⚡ Bonuses Dinámicos (Skills/Armas)", Color(1.0, 0.7, 0.2))
			for key in dynamic:
				var d = dynamic[key]
				var val = float(d.get("val", 0.0))
				var is_flat = bool(d.get("flat", false))
				_add_talent_bonus_row(content_v, key, val, is_flat)
	else:
		_add_info_row(content_v, "", "Sistema de talentos no disponible", Color.GRAY)

	# ═══ SECCIÓN 7: MUNICIÓN ═══
	_add_section_header(content_v, "💣 MUNICIÓN ACTUAL", Color(1.0, 0.6, 0.2))
	_add_ammo_section(content_v, player)

	# ═══ SECCIÓN 8: ESTADOS ACTIVOS ═══
	_add_section_header(content_v, "🔮 ESTADOS ACTIVOS", Color(0.8, 0.3, 0.5))
	_add_status_effects(content_v, player)


# ═══════════════════════════════════════════════════════
# RECOLECCIÓN DE DATOS
# ═══════════════════════════════════════════════════════

func _get_ship_base(player) -> Dictionary:
	var result = {"hp": 3000.0, "shield": 1000.0, "speed": 300.0, "base_dmg": 100.0, "vision": 1300.0}
	for ship in GameConstants.SHIP_MODELS:
		if ship.id == player.current_ship_id:
			result.hp = float(ship.get("hp", 3000))
			result.shield = float(ship.get("shield", 1000))
			result.speed = float(ship.get("speed", 300))
			result.vision = float(ship.get("vision", 1300))
			if ship.has("baseDmg"):
				result.base_dmg = float(ship.baseDmg)
			elif ship.has("base_damage"):
				result.base_dmg = float(ship.base_damage)
			break
	return result

func _get_equipment_modifiers(player) -> Dictionary:
	var result = {
		"weapons": [], "shields": [], "engines": [], "extras": [],
		"total_hp": 0.0, "total_shield": 0.0, "total_speed": 0.0, "total_dmg": 0.0,
		"hp_mod_pct": 0.0, "shield_mod_pct": 0.0, "speed_mod_pct": 0.0
	}
	var equipped = player.equipped
	if typeof(equipped) != TYPE_DICTIONARY:
		return result

	# Weapons (w)
	if equipped.has("w") and typeof(equipped["w"]) == TYPE_ARRAY:
		for item in equipped["w"]:
			if typeof(item) != TYPE_DICTIONARY: continue
			var w = {
				"name": str(item.get("name", item.get("id", "Arma"))),
				"base_dmg": float(item.get("base", 0)),
				"hp_mod": 0.0, "hp_mod_flat": false,
				"speed_mod": 0.0, "speed_mod_flat": false
			}
			var hv = float(item.get("hpMod", 0))
			if item.get("hpModType", "percent") == "flat":
				w.hp_mod = hv; w.hp_mod_flat = true
				result.total_hp += hv
			else:
				w.hp_mod = hv; w.hp_mod_flat = false
				result.hp_mod_pct += hv
			var sv = float(item.get("speedMod", 0))
			if item.get("speedModType", "percent") == "flat":
				w.speed_mod = sv; w.speed_mod_flat = true
				result.total_speed += sv
			else:
				w.speed_mod = sv; w.speed_mod_flat = false
				result.speed_mod_pct += sv
			result.weapons.append(w)
			result.total_dmg += w.base_dmg

	# Shields (s)
	if equipped.has("s") and typeof(equipped["s"]) == TYPE_ARRAY:
		for item in equipped["s"]:
			if typeof(item) != TYPE_DICTIONARY: continue
			var s = {
				"name": str(item.get("name", item.get("id", "Escudo"))),
				"base_val": float(item.get("base", 0)),
				"hp_mod": 0.0, "hp_mod_flat": false,
				"speed_mod": 0.0, "speed_mod_flat": false
			}
			var hv = float(item.get("hpMod", 0))
			if item.get("hpModType", "percent") == "flat":
				s.hp_mod = hv; s.hp_mod_flat = true
				result.total_hp += hv
			else:
				s.hp_mod = hv; s.hp_mod_flat = false
				result.hp_mod_pct += hv
			var sv = float(item.get("speedMod", 0))
			if item.get("speedModType", "percent") == "flat":
				s.speed_mod = sv; s.speed_mod_flat = true
				result.total_speed += sv
			else:
				s.speed_mod = sv; s.speed_mod_flat = false
				result.speed_mod_pct += sv
			result.shields.append(s)
			result.total_shield += s.base_val

	# Engines (e)
	if equipped.has("e") and typeof(equipped["e"]) == TYPE_ARRAY:
		for item in equipped["e"]:
			if typeof(item) != TYPE_DICTIONARY: continue
			var e = {
				"name": str(item.get("name", item.get("id", "Motor"))),
				"base_val": float(item.get("base", 0)),
				"shield_mod": 0.0, "shield_mod_flat": false,
				"hp_mod": 0.0, "hp_mod_flat": false
			}
			var shv = float(item.get("shieldMod", 0))
			if item.get("shieldModType", "percent") == "flat":
				e.shield_mod = shv; e.shield_mod_flat = true
				result.total_shield += shv
			else:
				e.shield_mod = shv; e.shield_mod_flat = false
				result.shield_mod_pct += shv
			var hv = float(item.get("hpMod", 0))
			if item.get("hpModType", "percent") == "flat":
				e.hp_mod = hv; e.hp_mod_flat = true
				result.total_hp += hv
			else:
				e.hp_mod = hv; e.hp_mod_flat = false
				result.hp_mod_pct += hv
			result.engines.append(e)
			result.total_speed += e.base_val

	# Extras (x)
	if equipped.has("x") and typeof(equipped["x"]) == TYPE_ARRAY:
		for item in equipped["x"]:
			if typeof(item) != TYPE_DICTIONARY: continue
			var x = {
				"name": str(item.get("name", item.get("id", "Extra"))),
				"base_val": float(item.get("base", 0))
			}
			result.extras.append(x)
			result.total_hp += x.base_val

	return result

func _get_sphere_modifiers(player) -> Dictionary:
	var result = {"total_hp": 0.0, "total_shield": 0.0, "total_speed": 0.0, "total_heal_pct": 0.0}
	var sm = player.get_node_or_null("SpheresManager")
	if not is_instance_valid(sm):
		return result

	var config_spheres = []
	if NetworkManager and NetworkManager.server_config:
		config_spheres = NetworkManager.server_config.get("shopItems", {}).get("spheres", [])

	for i in range(min(sm.spheres_data.size(), 4)):
		var sd = sm.spheres_data[i]
		var sphere = sd.get("sphere")
		if sphere == null or typeof(sphere) != TYPE_DICTIONARY:
			continue
		var sphere_id = str(sphere.get("id", ""))
		var master_stats = {}
		for ms in config_spheres:
			if str(ms.get("id", "")) == sphere_id:
				master_stats = ms.get("stats", {})
				break
		if master_stats.is_empty():
			master_stats = sphere.get("stats", {})

		if typeof(master_stats) == TYPE_DICTIONARY:
			for key in master_stats:
				var val = float(master_stats[key])
				if key == "hpMod": result.total_hp += val
				elif key == "shieldMod": result.total_shield += val
				elif key == "speedMod": result.total_speed += val
				elif key == "hpPct": result.total_hp += val * 100.0
				elif key == "shieldPct": result.total_shield += val * 100.0
				elif key == "speedPct": result.total_speed += val * 100.0
				elif key == "healPct": result.total_heal_pct += val * 100.0
		elif typeof(master_stats) == TYPE_ARRAY:
			for entry in master_stats:
				if typeof(entry) == TYPE_DICTIONARY:
					var key = str(entry.get("key", ""))
					var val = float(entry.get("val", 0))
					if key == "hpMod": result.total_hp += val
					elif key == "shieldMod": result.total_shield += val
					elif key == "speedMod": result.total_speed += val
					elif key == "hpPct": result.total_hp += val * 100.0
					elif key == "shieldPct": result.total_shield += val * 100.0
					elif key == "speedPct": result.total_speed += val * 100.0
					elif key == "healPct": result.total_heal_pct += val * 100.0
	return result

func _get_talent_bonuses(player) -> Dictionary:
	var ts = get_tree().get_first_node_in_group("talent_system")
	if is_instance_valid(ts):
		return ts.get_bonuses()
	return {}

func _calculate_final(player, ship_base: Dictionary, equip_mods: Dictionary, sphere_mods: Dictionary, talent_bonuses: Dictionary) -> Dictionary:
	var result = {"hp": 0.0, "shield": 0.0, "speed": 0.0, "damage": 0.0, "vision": 0.0}

	var base_hp = ship_base.hp + equip_mods.total_hp + sphere_mods.total_hp
	var base_sh = ship_base.shield + equip_mods.total_shield + sphere_mods.total_shield
	var base_spd = ship_base.speed + equip_mods.total_speed + sphere_mods.total_speed
	var base_dmg = ship_base.base_dmg + equip_mods.total_dmg

	var hp_mod_mult = 1.0 + equip_mods.hp_mod_pct / 100.0
	var sh_mod_mult = 1.0 + equip_mods.shield_mod_pct / 100.0
	var spd_mod_mult = 1.0 + equip_mods.speed_mod_pct / 100.0

	var t_hp_pct = float(talent_bonuses.get("hp_pct", 0.0))
	var t_sh_pct = float(talent_bonuses.get("sh_pct", 0.0))
	var t_spd_pct = float(talent_bonuses.get("speed_pct", 0.0))
	var t_dmg_pct = float(talent_bonuses.get("dmg_pct", 0.0))

	result.hp = round((base_hp) * (1.0 + t_hp_pct) * hp_mod_mult)
	result.shield = round((base_sh) * (1.0 + t_sh_pct) * sh_mod_mult)
	result.speed = round((base_spd) * (1.0 + t_spd_pct) * spd_mod_mult)
	result.damage = round((base_dmg) * (1.0 + t_dmg_pct))
	result.vision = ship_base.vision

	# Buff de velocidad Electron
	if player.electron_speed_buff_timer > 0.0:
		var bonus_pct = (player.electron_speed_buff_pct * player.electron_speed_buff_stacks) / 100.0
		result.speed = round(result.speed * (1.0 + bonus_pct))

	return result


# ═══════════════════════════════════════════════════════
# COMPONENTES DE UI
# ═══════════════════════════════════════════════════════

func _add_section_header(parent, text: String, color: Color):
	var sep = HSeparator.new()
	sep.modulate = Color(color.r, color.g, color.b, 0.3)
	parent.add_child(sep)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate = color
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(lbl)

func _add_sub_header(parent, text: String, color: Color):
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(color.r, color.g, color.b, 0.85)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.offset_left = 12.0
	parent.add_child(lbl)

func _add_info_row(parent, label: String, value: String, color: Color):
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.offset_left = 8.0
	parent.add_child(h)

	if label != "":
		var l = Label.new()
		l.text = label
		l.add_theme_font_size_override("font_size", 10)
		l.modulate = Color(0.6, 0.65, 0.75)
		l.custom_minimum_size.x = 110.0
		h.add_child(l)

	var v = Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 10)
	v.modulate = color
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)

func _add_stat_row(parent, label: String, value: float, color: Color):
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.offset_left = 8.0
	parent.add_child(h)

	var l = Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 10)
	l.modulate = Color(0.6, 0.65, 0.75)
	l.custom_minimum_size.x = 130.0
	h.add_child(l)

	var v = Label.new()
	v.text = _format_number(value)
	v.add_theme_font_size_override("font_size", 10)
	v.modulate = color
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)

func _add_stat_mod_row(parent, key: String, val: float):
	if abs(val) < 0.0001: return
	var display = _get_stat_key_display(key)
	var prefix = "+" if val > 0 else ""
	var suffix = ""
	if key.ends_with("Pct"):
		suffix = " (" + prefix + str(int(val * 100)) + "%)"
		val = 0.0
	_add_info_row(parent, "  " + display, prefix + _format_number(val) + suffix if val != 0.0 else suffix, Color(0.7, 0.8, 1.0))

func _add_item_mod_row(parent, item_name: String, stat_name: String, val: float, prefix: String = "+", is_flat: bool = false):
	if abs(val) < 0.0001: return
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.offset_left = 20.0
	parent.add_child(h)

	if item_name != "":
		var n = Label.new()
		n.text = item_name
		n.add_theme_font_size_override("font_size", 9)
		n.modulate = Color(0.5, 0.55, 0.65)
		n.custom_minimum_size.x = 100.0
		h.add_child(n)
	else:
		var spacer = Control.new()
		spacer.custom_minimum_size.x = 100.0
		h.add_child(spacer)

	var s = Label.new()
	s.text = stat_name
	s.add_theme_font_size_override("font_size", 9)
	s.modulate = Color(0.55, 0.6, 0.7)
	s.custom_minimum_size.x = 70.0
	h.add_child(s)

	var flat_tag = " (fijo)" if is_flat else ""
	var v = Label.new()
	v.text = prefix + _format_number(abs(val)) + flat_tag
	v.add_theme_font_size_override("font_size", 9)
	v.modulate = Color(0.2, 1.0, 0.5) if val > 0 else Color(1.0, 0.3, 0.3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)

func _add_mod_summary(parent, label: String, flat_val: float, pct_val: float):
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.offset_left = 12.0
	parent.add_child(h)

	var l = Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 10)
	l.modulate = Color(0.6, 0.65, 0.75)
	l.custom_minimum_size.x = 120.0
	h.add_child(l)

	var parts = []
	if flat_val != 0.0:
		parts.append("+" + _format_number(flat_val) + " fijo")
	if pct_val != 0.0:
		parts.append("+" + str(int(pct_val)) + "%")
	var v = Label.new()
	v.text = " | ".join(parts)
	v.add_theme_font_size_override("font_size", 10)
	v.modulate = Color(0.3, 1.0, 0.6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)

func _add_talent_bonus_row(parent, name: String, val: float, is_flat: bool):
	if abs(val) < 0.0001: return
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.offset_left = 8.0
	parent.add_child(h)

	var l = Label.new()
	l.text = name
	l.add_theme_font_size_override("font_size", 10)
	l.modulate = Color(0.6, 0.65, 0.75)
	l.custom_minimum_size.x = 160.0
	h.add_child(l)

	var display_val = ""
	if is_flat:
		display_val = "+" + _format_number(val) + " (fijo)"
	else:
		display_val = "+" + str(int(val * 100)) + "%"

	var v = Label.new()
	v.text = display_val
	v.add_theme_font_size_override("font_size", 10)
	v.modulate = Color(0.5, 0.85, 1.0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)

func _add_final_stat_row(parent, label: String, final_val: float, current_val: float, color: Color):
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.offset_left = 8.0
	parent.add_child(h)

	var l = Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 11)
	l.modulate = Color(0.7, 0.75, 0.85)
	l.custom_minimum_size.x = 150.0
	h.add_child(l)

	var v = Label.new()
	if current_val > 0.0:
		v.text = _format_number(current_val) + " / " + _format_number(final_val)
	else:
		v.text = _format_number(final_val)
	v.add_theme_font_size_override("font_size", 11)
	v.modulate = color
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)

func _add_exp_bar(parent, player):
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.offset_left = 8.0
	parent.add_child(h)

	var l = Label.new()
	l.text = "Experiencia"
	l.add_theme_font_size_override("font_size", 10)
	l.modulate = Color(0.6, 0.65, 0.75)
	l.custom_minimum_size.x = 110.0
	h.add_child(l)

	var next_exp = floor(1000.0 * pow(max(1, player.level), 1.5))
	var pct = clamp((player.current_exp / next_exp) * 100.0, 0.0, 100.0) if next_exp > 0 else 0.0

	var bar_v = VBoxContainer.new()
	bar_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(bar_v)

	var bar_bg = ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(0, 8)
	bar_bg.color = Color(0.08, 0.1, 0.15)
	bar_v.add_child(bar_bg)

	var bar_fg = ColorRect.new()
	bar_fg.color = Color(0.2, 0.7, 1.0)
	bar_fg.anchor_right = 1.0
	bar_fg.offset_bottom = 8.0
	bar_v.add_child(bar_fg)
	bar_fg.size = Vector2(bar_bg.size.x * pct / 100.0, 8) if bar_bg.size.x > 0 else Vector2(0, 8)

	var pct_lbl = Label.new()
	pct_lbl.text = str(int(pct)) + "% (" + _format_number(player.current_exp) + " / " + _format_number(next_exp) + ")"
	pct_lbl.add_theme_font_size_override("font_size", 9)
	pct_lbl.modulate = Color(0.5, 0.6, 0.7)
	bar_v.add_child(pct_lbl)

func _add_ammo_section(parent, player):
	var ammo = player.ammo
	var selected = player.selected_ammo
	var active_slots = player.ammo_slots
	var ammo_types = ["laser", "missile", "mine", "melee", "heal", "siphon", "emp"]
	var ammo_names = {
		"laser": "Láser", "missile": "Misil", "mine": "Mina",
		"melee": "Melee", "heal": "Curación", "siphon": "Siphon", "emp": "EMP"
	}

	var active_count = 0
	for atype in ammo_types:
		if not ammo.has(atype): continue
		var tiers = ammo[atype]
		if typeof(tiers) != TYPE_ARRAY: continue
		var has_any = false
		for t in tiers:
			if int(t) > 0:
				has_any = true; break
		if not has_any: continue

		var is_active_type = atype in active_slots
		var display = ammo_names.get(atype, atype)
		var tier_str = ""
		for i in range(tiers.size()):
			var count = int(tiers[i])
			if count > 0:
				var marker = ""
				if is_active_type:
					marker = " [ACTIVA]"
					if i == int(selected.get(atype, 0)):
						marker = " [ACTIVA T" + str(i + 1) + "]"
					else:
						marker = " [Slot " + str(active_slots.find(atype) + 1) + "]"
				tier_str += " T" + str(i + 1) + ": " + str(count) + marker
		if is_active_type:
			active_count += 1
		_add_info_row(parent, "💣 " + display, tier_str.strip_edges(), Color(1.0, 0.85, 0.3) if is_active_type else Color(0.6, 0.65, 0.7))

	_add_info_row(parent, "", str(active_count) + " de 3 slots activos", Color(0.4, 0.5, 0.6))

func _add_status_effects(parent, player):
	var has_effects = false

	if player.is_stunned:
		_add_info_row(parent, "  ⚡ Stun", str(int(player.stun_timer)) + "s", Color(1.0, 0.8, 0.2))
		has_effects = true
	if player.is_feared:
		_add_info_row(parent, "  💫 Miedo", str(int(player.fear_timer)) + "s", Color(0.8, 0.2, 0.8))
		has_effects = true
	if player.is_polymorphed:
		_add_info_row(parent, "  🟦 Polimorfia", str(int(player.poly_timer)) + "s", Color(0.2, 0.8, 1.0))
		has_effects = true
	if player.slow_points > 0.0:
		var slow_str = str(int(player.slow_points))
		if player.slow_is_percentage:
			slow_str += "%"
		_add_info_row(parent, "  ❄️ Ralentización", slow_str, Color(0.3, 0.7, 1.0))
		has_effects = true
	if player.heal_timer > 0.0:
		_add_info_row(parent, "  💚 Curación Activa", str(int(player.heal_timer)) + "s (x" + str(player.heal_stacks) + ")", Color(0.2, 1.0, 0.3))
		has_effects = true
	if player.electron_speed_buff_timer > 0.0:
		_add_info_row(parent, "  ⚡ Buff Electron", "+" + str(int(player.electron_speed_buff_pct)) + "% (x" + str(player.electron_speed_buff_stacks) + ")", Color(1.0, 0.9, 0.0))
		has_effects = true
	if player.poison_timer > 0.0:
		_add_info_row(parent, "  🧪 Veneno", str(int(player.poison_timer)) + "s", Color(0.7, 0.1, 0.9))
		has_effects = true
	if player.bleed_timer > 0.0:
		_add_info_row(parent, "  🩸 Sangrado", str(int(player.bleed_timer)) + "s", Color(0.9, 0.1, 0.1))
		has_effects = true
	if player.is_invulnerable:
		_add_info_row(parent, "  🛡️ Invulnerable", "ACTIVO", Color(1.0, 0.9, 0.3))
		has_effects = true

	if not has_effects:
		_add_info_row(parent, "", "Sin estados activos", Color(0.4, 0.45, 0.5))


# ═══════════════════════════════════════════════════════
# UTILIDADES
# ═══════════════════════════════════════════════════════

func _get_ship_name(ship_id: int) -> String:
	for ship in GameConstants.SHIP_MODELS:
		if ship.id == ship_id:
			return str(ship.get("name", "Nave " + str(ship_id)))
	return "Nave " + str(ship_id)

func _get_effect_display_name(key: String) -> String:
	var names = {
		"hp_pct": "Vida Máxima",
		"sh_pct": "Escudo Máximo",
		"dmg_pct": "Daño Total",
		"speed_pct": "Velocidad Base",
		"hp_regen": "Regen. Vida",
		"shield_regen": "Regen. Escudo",
		"armor_pct": "Armadura",
		"energy_efficiency": "Eficiencia Energía",
		"stability": "Estabilidad",
		"crit_chance": "Crítico Chance",
		"crit_dmg": "Crítico Daño",
		"fire_rate_pct": "Cadencia de Fuego",
		"evasion_pct": "Evasión",
		"cooldown_reduction": "Reducción CD",
		"cooldown_reduction_flat": "Reducción CD (Fijo)",
		"cast_time_reduction": "Reducción Cast",
		"cast_time_reduction_flat": "Reducción Cast (Fijo)",
		"ignore_shield_pct": "Perforación Escudo",
		"accuracy_pct": "Precisión",
		"ammo_bonus_pct": "Bonus Munición",
		"laser_dmg_pct": "Daño Láser",
		"repair_cost_reduction": "Costo Reparación",
		"minimap_range": "Rango Radar",
		"ohcu_kill_bonus": "Bonus OHCU por Bajas",
		"shop_discount": "Descuento Tienda",
		"group_bonus": "Bonus Escuadrón",
		"boss_loot_bonus": "Botín Jefes",
		"dash_distance": "Distancia Dash"
	}
	return names.get(key, key)

func _get_stat_key_display(key: String) -> String:
	match key:
		"hpMod": return "HP (Fijo)"
		"shieldMod": return "Escudo (Fijo)"
		"speedMod": return "Velocidad (Fijo)"
		"hpPct": return "HP (%)"
		"shieldPct": return "Escudo (%)"
		"speedPct": return "Velocidad (%)"
		"healPct": return "Curación (%)"
		"healMod": return "Curación (Fijo)"
		"dmgMod": return "Daño (Fijo)"
		"dmgPct": return "Daño (%)"
		"critChance": return "Crítico Chance"
		"critDmg": return "Crítico Daño"
		"evasion": return "Evasión"
		"armor": return "Armadura"
		"regen": return "Regeneración"
		"hpRegen": return "Regen. Vida"
		"shieldRegen": return "Regen. Escudo"
		_: return key

func _format_number(val: float) -> String:
	var rounded = round(val)
	if is_equal_approx(rounded, round(rounded)):
		return str(int(round(rounded)))
	var s = "%.1f" % val
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s

func _add_separator(parent):
	var sep = HSeparator.new()
	sep.custom_minimum_size.y = 2
	sep.modulate = Color(0, 0.82, 1, 0.15)
	parent.add_child(sep)
