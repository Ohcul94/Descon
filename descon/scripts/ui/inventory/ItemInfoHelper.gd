extends RefCounted

# ItemInfoHelper.gd — Estadísticas compartidas de ítems y resumen de efectos de esferas.
# Usado por HangarTab / Inventory (tooltips click-simple) y VaultUI (Baúl + sección de esferas).

static func rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.7, 0.7, 0.7) # Común
		1: return Color(0.13, 0.77, 0.36) # Raro
		2: return Color(0.23, 0.51, 0.96) # Épico
		3: return Color(0.66, 0.33, 0.97) # Reliquia
		4: return Color(0.98, 0.45, 0.09) # Legendario
		_: return Color.WHITE

static func rarity_label(rarity: int) -> String:
	match rarity:
		0: return "COMÚN"
		1: return "RARO"
		2: return "ÉPICO"
		3: return "RELIQUIA"
		4: return "LEGENDARIO"
		_: return "MÓDULO"

static func item_slot(item_id: String, type_str: String = "") -> String:
	var id = item_id.to_lower()
	var t = type_str.to_lower()
	if id.begins_with("esfera_") or t == "sphere": return "sphere"
	if id.begins_with("las") or t == "laser" or t == "weapon": return "w"
	if id.begins_with("sh") or t == "shield": return "s"
	if id.begins_with("en") or t == "engine": return "e"
	if id.begins_with("mat_") or t == "resource": return "mat"
	if id.begins_with("recipe_") or t == "recipe": return "recipe"
	return "x"

# Texto completo de stats para el tooltip (click simple) — idéntico en Hangar y Baúl.
static func format_stats(item: Dictionary) -> String:
	if item.is_empty(): return ""
	var search_id = str(item.get("id", "")).to_lower()
	var type_str = str(item.get("type", "")).to_lower()
	var slot = item_slot(search_id, type_str)
	var base_val = int(round(float(item.get("base", 0))))

	if slot == "sphere":
		var eff = sphere_item_effect_texts(item)
		if eff.size() > 0:
			return "OFRECE: " + " | ".join(eff)
		return "ESFERA DE PODER — HABILITA HABILIDADES DE SU COLOR"

	if int(item.get("grantShip", 0)) > 0 or search_id.begins_with("ship_"):
		return "NAVE DESBLOQUEABLE — USÁLA EN TU BODEGA"
	if type_str == "consumible":
		return "USABLE: Objeto comerciable (Mercado)"
	if slot == "mat":
		return "MATERIAL DE CRAFTEO"
	if slot == "recipe":
		return "RECETA DE CRAFTEO"

	var parts: Array = []
	match slot:
		"w": parts.append("DAÑO: +" + str(base_val))
		"s": parts.append("ESCUDO: +" + str(base_val))
		"e": parts.append("VELOCIDAD: +" + str(base_val))
		_:
			if base_val != 0:
				parts.append("VIDA: +" + str(base_val))

	_append_mod(parts, "HP", item.get("hpMod", 0), item.get("hpModType", "percent"))
	_append_mod(parts, "VEL", item.get("speedMod", 0), item.get("speedModType", "percent"))
	_append_mod(parts, "ESCUDO", item.get("shieldMod", 0), item.get("shieldModType", "percent"))

	if parts.is_empty():
		if base_val != 0:
			return "ESTADÍSTICA BASE: +" + str(base_val)
		return "SIN ESTADÍSTICAS DE MÓDULO"
	return " | ".join(parts)

static func _append_mod(parts: Array, label: String, raw, mod_type) -> void:
	var v = float(raw)
	if absf(v) < 0.0001: return
	var t = str(mod_type)
	if t == "flat":
		var sign_ch = "+" if v > 0 else "-"
		parts.append(label + ": " + sign_ch + str(int(round(absf(v)))) + " (fijo)")
	else:
		var sign_ch = "+" if v > 0 else "-"
		var pts = v * 100.0 if absf(v) < 1.0 else v
		parts.append(label + ": " + sign_ch + str(int(round(absf(pts)))) + "%")

# ── Esferas ──────────────────────────────────────────────────────────────────

static func _scene_tree():
	var ml = Engine.get_main_loop()
	if ml is SceneTree:
		return ml
	return null

static func _get_sm():
	var tree = _scene_tree()
	if tree == null: return null
	var p = tree.get_first_node_in_group("player")
	if p == null: return null
	return p.get_node_or_null("SpheresManager")

static func _server_spheres() -> Array:
	var tree = _scene_tree()
	if tree == null or tree.root == null: return []
	var nm = tree.root.get_node_or_null("NetworkManager")
	if nm == null: return []
	var cfg = nm.get("server_config")
	if typeof(cfg) != TYPE_DICTIONARY: return []
	var shop = cfg.get("shopItems", {})
	if typeof(shop) != TYPE_DICTIONARY: return []
	var sph = shop.get("spheres", [])
	if typeof(sph) != TYPE_ARRAY: return []
	return sph

static func _lookup_sphere_stats(sphere_id: String) -> Dictionary:
	for ms in _server_spheres():
		if typeof(ms) == TYPE_DICTIONARY and str(ms.get("id", "")) == sphere_id:
			var st = ms.get("stats", {})
			if typeof(st) == TYPE_DICTIONARY:
				return st
			if typeof(st) == TYPE_ARRAY:
				var out := {}
				for e in st:
					if typeof(e) == TYPE_DICTIONARY:
						out[str(e.get("key", ""))] = float(e.get("val", 0))
				return out
	return {}

static func _sphere_color_key_from(sp) -> String:
	if typeof(sp) != TYPE_DICTIONARY: return ""
	var c: String = str(sp.get("type", sp.get("sphereColor", ""))).to_lower()
	if c != "":
		match c:
			"roja", "red": return "roja"
			"azul", "blue": return "azul"
			"verde", "green": return "verde"
			"amarilla", "amarillo", "yellow": return "amarilla"
	var iid: String = str(sp.get("id", "")).to_lower()
	if iid == "esfera_roja": return "roja"
	if iid == "esfera_azul": return "azul"
	if iid == "esfera_verde": return "verde"
	if iid == "esfera_amarilla": return "amarilla"
	return ""

static func sphere_color_label(sp) -> String:
	match _sphere_color_key_from(sp):
		"roja": return "Roja"
		"azul": return "Azul"
		"verde": return "Verde"
		"amarilla": return "Amarilla"
	return "?"

static func _pct_points(val: float) -> float:
	return val * 100.0 if absf(val) < 1.0 else val

# Convierte una key/val de stats en línea legible; acumula en totals (si no es null).
static func _stat_line(key: String, val: float, totals) -> String:
	if absf(val) < 0.0001: return ""
	var k = key
	var lbl := ""
	var bucket := ""
	match k:
		"dmg_pct", "dmgPct":
			lbl = "DAÑO"; bucket = "dmg_pct"
		"shieldPct", "shield_pct":
			lbl = "ESCUDO"; bucket = "shield_pct"
		"hpPct", "hp_pct":
			lbl = "VIDA"; bucket = "hp_pct"
		"speedPct", "speed_pct":
			lbl = "VELOCIDAD"; bucket = "speed_pct"
		"healPct", "heal_pct":
			lbl = "CURACIÓN"; bucket = "heal_pct"
		"hpMod":
			if totals != null: totals["hp_flat"] = float(totals.get("hp_flat", 0.0)) + val
			return "+" + str(int(round(val))) + " VIDA"
		"shieldMod":
			if totals != null: totals["shield_flat"] = float(totals.get("shield_flat", 0.0)) + val
			return "+" + str(int(round(val))) + " ESCUDO"
		"speedMod":
			if totals != null: totals["speed_flat"] = float(totals.get("speed_flat", 0.0)) + val
			return "+" + str(int(round(val))) + " VELOCIDAD"

	if lbl != "":
		var p = _pct_points(val)
		if totals != null:
			totals[bucket] = float(totals.get(bucket, 0.0)) + p
		return "+" + str(int(round(p))) + "% " + lbl

	var lower = k.to_lower()
	if lower.ends_with("pct") or lower.ends_with("_pct"):
		return "+" + str(int(round(_pct_points(val)))) + "% " + k.to_upper()
	return k + ": " + str(val)

static func _parse_stats(stats, totals) -> Array:
	var lines: Array = []
	if typeof(stats) == TYPE_DICTIONARY:
		for key in stats:
			var line = _stat_line(str(key), float(stats[key]), totals)
			if line != "": lines.append(line)
	elif typeof(stats) == TYPE_ARRAY:
		for e in stats:
			if typeof(e) == TYPE_DICTIONARY:
				var line2 = _stat_line(str(e.get("key", "")), float(e.get("val", 0)), totals)
				if line2 != "": lines.append(line2)
	return lines

# Efectos que ofrece un ítem-esfera en inventario/bodega.
static func sphere_item_effect_texts(item: Dictionary) -> Array:
	if typeof(item) != TYPE_DICTIONARY: return []
	var sid = str(item.get("id", ""))
	var stats = _lookup_sphere_stats(sid)
	if stats.is_empty():
		stats = item.get("stats", {})
	return _parse_stats(stats, null)

# Totales de las esferas INSTALADAS en el Sistema Orbital.
static func sphere_totals() -> Dictionary:
	var totals := {
		"dmg_pct": 0.0, "shield_pct": 0.0, "hp_pct": 0.0, "speed_pct": 0.0,
		"heal_pct": 0.0, "hp_flat": 0.0, "shield_flat": 0.0, "speed_flat": 0.0,
		"count": 0
	}
	var sm = _get_sm()
	if sm == null: return totals
	for i in range(min(sm.spheres_data.size(), 4)):
		var sd = sm.spheres_data[i]
		if typeof(sd) != TYPE_DICTIONARY: continue
		var sp = sd.get("sphere")
		if sp == null or typeof(sp) != TYPE_DICTIONARY or sp.is_empty(): continue
		totals["count"] = int(totals["count"]) + 1
		var sid = str(sp.get("id", ""))
		var stats = _lookup_sphere_stats(sid)
		if stats.is_empty():
			stats = sp.get("stats", {})
		_parse_stats(stats, totals)
	return totals

# Líneas detalladas: "Slot 1 · Azul: +5% ESCUDO"
static func sphere_effect_lines() -> Array:
	var out: Array = []
	var sm = _get_sm()
	if sm == null: return out
	for i in range(min(sm.spheres_data.size(), 4)):
		var sd = sm.spheres_data[i]
		if typeof(sd) != TYPE_DICTIONARY: continue
		var sp = sd.get("sphere")
		if sp == null or typeof(sp) != TYPE_DICTIONARY or sp.is_empty(): continue
		var sid = str(sp.get("id", ""))
		var stats = _lookup_sphere_stats(sid)
		if stats.is_empty():
			stats = sp.get("stats", {})
		var lines = _parse_stats(stats, null)
		var body = " | ".join(lines) if lines.size() > 0 else "SIN STATS"
		out.append("Slot " + str(i + 1) + " · " + sphere_color_label(sp) + ": " + body)
	return out

static func sphere_total_line(totals: Dictionary = {}) -> String:
	if totals.is_empty():
		totals = sphere_totals()
	var parts: Array = []
	if float(totals.get("hp_pct", 0.0)) != 0.0:
		parts.append("+" + str(int(round(float(totals["hp_pct"])))) + "% VIDA")
	if float(totals.get("shield_pct", 0.0)) != 0.0:
		parts.append("+" + str(int(round(float(totals["shield_pct"])))) + "% ESCUDO")
	if float(totals.get("dmg_pct", 0.0)) != 0.0:
		parts.append("+" + str(int(round(float(totals["dmg_pct"])))) + "% DAÑO")
	if float(totals.get("speed_pct", 0.0)) != 0.0:
		parts.append("+" + str(int(round(float(totals["speed_pct"])))) + "% VEL")
	if float(totals.get("heal_pct", 0.0)) != 0.0:
		parts.append("+" + str(int(round(float(totals["heal_pct"])))) + "% CURACIÓN")
	if float(totals.get("hp_flat", 0.0)) != 0.0:
		parts.append("+" + str(int(round(float(totals["hp_flat"])))) + " VIDA")
	if float(totals.get("shield_flat", 0.0)) != 0.0:
		parts.append("+" + str(int(round(float(totals["shield_flat"])))) + " ESCUDO")
	if float(totals.get("speed_flat", 0.0)) != 0.0:
		parts.append("+" + str(int(round(float(totals["speed_flat"])))) + " VEL")
	if parts.is_empty():
		return "SIN EFECTOS"
	return " | ".join(parts)

# Texto compacto multi-línea para el panel de efectos de esferas.
static func sphere_summary_text() -> String:
	var totals = sphere_totals()
	var count = int(totals.get("count", 0))
	if count == 0:
		return "SIN ESFERAS INSTALADAS — Crafeelás en CRAFTEO e instalalas en SISTEMA ORBITAL."
	var lines = sphere_effect_lines()
	var out: Array = []
	out.append("INSTALADAS: " + str(count) + "/4")
	for l in lines:
		out.append("• " + l)
	out.append("TOTAL: " + sphere_total_line(totals))
	return "\n".join(out)
