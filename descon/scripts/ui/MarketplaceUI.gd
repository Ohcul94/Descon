extends CanvasLayer

# MarketplaceUI.gd (v1.0 - Interfaz AAA de la Casa de Subastas Galáctica)
# Mercado centralizado del Lobby: Comprar / Vender / Mis Publicaciones / Buzón.

var is_open: bool = false
var market_config: Dictionary = {}
var listings: Array = []
var my_listings: Array = []
var mailbox: Array = []
var inventory_items: Array = []
var hubs: int = 0
var ohcu: int = 0
var active_tab: int = 0

# Filtros de compra
var category_filter: String = ""
var search_text: String = ""

# Auto-refresh pasivo de listings
var _auto_refresh_timer: Timer = null
const AUTO_REFRESH_INTERVAL: float = 30.0  # segundos

# Referencias UI
var control_root: Control = null
var overlay: ColorRect = null
var tab_bar: TabBar = null
var content_stack: VBoxContainer = null
var buy_grid: GridContainer = null
var sell_grid: GridContainer = null
var my_list_container: VBoxContainer = null
var mailbox_container: VBoxContainer = null
var lbl_hubs: Label = null
var lbl_ohcu: Label = null
var lbl_footer: Label = null
var search_edit: LineEdit = null
var modal_root: Control = null

const PANEL_BG = Color(0.02, 0.02, 0.05, 0.98)
const BORDER_GOLD = Color(1.0, 0.84, 0.0, 0.9)
const BORDER_CYAN = Color(0.0, 0.85, 1.0, 0.9)
const RARITY_COLORS = {
	0: Color(0.8, 0.8, 0.8),
	1: Color(0.2, 1.0, 0.4),
	2: Color(0.2, 0.6, 1.0),
	3: Color(0.9, 0.3, 1.0),
	4: Color(1.0, 0.6, 0.1),
	5: Color(1.0, 0.2, 0.2)
}

func _ready():
	add_to_group("market_ui")
	layer = 102
	
	overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	control_root = Control.new()
	control_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(control_root)
	
	overlay.visible = false
	overlay.modulate.a = 0.0
	control_root.visible = false
	
	_build_ui()
	
	NetworkManager.market_data.connect(_on_market_data)
	NetworkManager.market_update.connect(_on_market_update)
	NetworkManager.market_purchase_result.connect(_on_market_purchase_result)
	NetworkManager.market_mailbox_updated.connect(_on_market_mailbox_updated)
	NetworkManager.inventory_data.connect(_on_inventory_received)

	# Auto-refresh pasivo: refresca listings cada 30 seg mientras el mercado está abierto
	_auto_refresh_timer = Timer.new()
	_auto_refresh_timer.wait_time = AUTO_REFRESH_INTERVAL
	_auto_refresh_timer.autostart = false
	_auto_refresh_timer.timeout.connect(_on_auto_refresh_tick)
	add_child(_auto_refresh_timer)

func _build_ui():
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(940, 580)
	panel.position = Vector2(-470, -290)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_width_top = 3
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = BORDER_GOLD
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 30
	panel.add_theme_stylebox_override("panel", sb)
	control_root.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	# HEADER
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)
	
	var lbl_title = Label.new()
	lbl_title.text = "CASA DE SUBASTAS GALÁCTICA"
	lbl_title.add_theme_font_size_override("font_size", 18)
	lbl_title.add_theme_color_override("font_color", BORDER_GOLD)
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(lbl_title)
	
	lbl_hubs = Label.new()
	lbl_hubs.add_theme_font_size_override("font_size", 13)
	lbl_hubs.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	header.add_child(lbl_hubs)
	
	lbl_ohcu = Label.new()
	lbl_ohcu.add_theme_font_size_override("font_size", 13)
	lbl_ohcu.add_theme_color_override("font_color", Color(1.0, 0.4, 0.9))
	header.add_child(lbl_ohcu)
	
	var btn_close = Button.new()
	btn_close.text = "X"
	btn_close.add_theme_font_size_override("font_size", 14)
	btn_close.custom_minimum_size = Vector2(34, 30)
	btn_close.pressed.connect(close_market)
	header.add_child(btn_close)
	
	# TABS
	tab_bar = TabBar.new()
	tab_bar.add_tab("COMPRAR")
	tab_bar.add_tab("VENDER")
	tab_bar.add_tab("MIS PUBLICACIONES")
	tab_bar.add_tab("BUZÓN")
	tab_bar.tab_changed.connect(_on_tab_changed)
	vbox.add_child(tab_bar)
	
	# BARRA DE FILTROS (Compra)
	var filter_bar = HBoxContainer.new()
	filter_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(filter_bar)
	
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Buscar ítem..."
	search_edit.custom_minimum_size = Vector2(170, 30)
	search_edit.text_changed.connect(_on_search_changed)
	filter_bar.add_child(search_edit)
	
	btn_refresh = Button.new()
	btn_refresh.text = "🔄 ACTUALIZAR"
	btn_refresh.pressed.connect(_refresh_all)
	filter_bar.add_child(btn_refresh)
	filter_bar.add_child(Control.new()) # spacer
	
	var cat_bar = HBoxContainer.new()
	cat_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(cat_bar)
	for cat_name in ["TODAS", "ARMAS", "ESCUDOS", "MOTORES", "RECURSOS", "EXTRAS", "MUNICIÓN"]:
		var b = Button.new()
		b.text = cat_name
		b.toggle_mode = true
		b.button_pressed = (cat_name == "TODAS")
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_category_pressed.bind(cat_name, b))
		cat_bar.add_child(b)
		if cat_name == "TODAS":
			active_cat_button = b
	
	# CONTENIDO SCROLLABLE
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 370)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	content_stack = VBoxContainer.new()
	content_stack.add_theme_constant_override("separation", 8)
	content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content_stack)
	
	buy_grid = GridContainer.new()
	buy_grid.columns = 2
	buy_grid.add_theme_constant_override("h_separation", 10)
	buy_grid.add_theme_constant_override("v_separation", 10)
	content_stack.add_child(buy_grid)
	
	sell_grid = GridContainer.new()
	sell_grid.columns = 4
	sell_grid.add_theme_constant_override("h_separation", 10)
	sell_grid.add_theme_constant_override("v_separation", 10)
	sell_grid.visible = false
	content_stack.add_child(sell_grid)
	
	my_list_container = VBoxContainer.new()
	my_list_container.add_theme_constant_override("separation", 6)
	my_list_container.visible = false
	content_stack.add_child(my_list_container)
	
	mailbox_container = VBoxContainer.new()
	mailbox_container.add_theme_constant_override("separation", 6)
	mailbox_container.visible = false
	content_stack.add_child(mailbox_container)
	
	# FOOTER
	lbl_footer = Label.new()
	lbl_footer.text = "Impuesto de venta aplicado al vendedor."
	lbl_footer.add_theme_font_size_override("font_size", 11)
	lbl_footer.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vbox.add_child(lbl_footer)
	
	_update_balances()

var btn_refresh: Button = null
var active_cat_button: Button = null

# ---------------------------------------------------------------------------
# RED
# ---------------------------------------------------------------------------
func _on_market_data(data: Dictionary):
	market_config = data.get("config", {})
	listings = data.get("listings", [])
	my_listings = data.get("myListings", [])
	mailbox = data.get("mailbox", [])
	_open()
	_render_active_tab()

func _on_market_update(data: Dictionary):
	var lid = str(data.get("_id", ""))
	var status = str(data.get("status", ""))
	if status == "active":
		# Nueva publicación: agregar si no existe
		var exists = listings.any(func(l): return str(l.get("_id", "")) == lid)
		if not exists:
			listings.insert(0, data)
	else:
		listings = listings.filter(func(l): return str(l.get("_id", "")) != lid)
		my_listings = my_listings.filter(func(l): return str(l.get("_id", "")) != lid)
	if is_open:
		_render_active_tab()

func _on_market_purchase_result(data: Dictionary):
	var ok = data.get("ok", false)
	var msg = str(data.get("msg", ""))
	_notify(msg, "success" if ok else "error")
	if ok:
		_refresh_all()

func _on_market_mailbox_updated(data: Dictionary):
	mailbox = data.get("mailbox", [])
	if is_open:
		_render_active_tab()

func _on_inventory_received(data):
	if typeof(data) == TYPE_DICTIONARY:
		inventory_items = []  # Limpiar antes de repoblar
		if data.has("inventory"): inventory_items = data["inventory"]
		if data.has("hubs"): hubs = int(data["hubs"])
		if data.has("ohcu"): ohcu = int(data["ohcu"])
		if data.has("equippedByShip") and data.has("currentShipId"):
			var ebs = data["equippedByShip"]
			var cid = str(data["currentShipId"])
			if typeof(ebs) == TYPE_DICTIONARY and ebs.has(cid):
				var eq = ebs[cid]
				for slot in ["w", "s", "e", "x"]:
					if eq.has(slot) and eq[slot] is Array:
						inventory_items.append_array(eq[slot])
	_update_balances()
	if is_open:
		# Re-renderizar siempre que el mercado esté abierto y lleguen datos de inventario
		# (sin importar qué pestaña esté activa, para que VENDER tenga datos al clickear)
		_render_active_tab()

# ---------------------------------------------------------------------------
# APERTURA / CIERRE
# ---------------------------------------------------------------------------
func open_market():
	_refresh_all()

func _open():
	is_open = true
	overlay.visible = true
	control_root.visible = true
	overlay.modulate.a = 0.0
	control_root.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(control_root, "modulate:a", 1.0, 0.15)
	# Arrancar auto-refresh cada 30 seg (listings en vivo)
	if is_instance_valid(_auto_refresh_timer) and _auto_refresh_timer.is_stopped():
		_auto_refresh_timer.start()

func close_market():
	if not is_open: return
	is_open = false
	_hide_modal()
	# Detener auto-refresh al cerrar
	if is_instance_valid(_auto_refresh_timer):
		_auto_refresh_timer.stop()
	var tw = create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, 0.12)
	tw.parallel().tween_property(control_root, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func():
		overlay.visible = false
		control_root.visible = false
	)

func _refresh_all():
	if NetworkManager:
		NetworkManager.send_event("getMarketData", {})
		NetworkManager.send_event("getInventory", {})

func _on_auto_refresh_tick():
	# Refrescar listings pasivamente (no re-abre, solo actualiza datos en background)
	if is_open and NetworkManager:
		NetworkManager.send_event("getMarketData", {})

func _input(event):
	if not is_open: return
	if event is InputEventKey and event.pressed and not event.is_echo():
		var focus = get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		if event.keycode == KEY_ESCAPE or event.is_action_pressed("loot_claim"):
			close_market()
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# RENDER
# ---------------------------------------------------------------------------
func _on_tab_changed(tab: int):
	active_tab = tab
	if tab == 1 and inventory_items.is_empty() and NetworkManager:
		# El inventario todavía no llegó (o llegó vacío): pedirlo ahora
		NetworkManager.send_event("getInventory", {})
	_render_active_tab()

func _on_search_changed(text: String):
	search_text = text.strip_edges().to_lower()
	_render_buy_tab()

func _on_category_pressed(cat: String, btn: Button):
	if active_cat_button and is_instance_valid(active_cat_button):
		active_cat_button.button_pressed = false
	active_cat_button = btn
	category_filter = "" if cat == "TODAS" else cat
	_render_buy_tab()

func _render_active_tab():
	match active_tab:
		0: _render_buy_tab()
		1: _render_sell_tab()
		2: _render_my_listings()
		3: _render_mailbox()

func _clear_children(node: Node):
	for child in node.get_children():
		child.queue_free()

func _item_matches_filter(item: Dictionary) -> bool:
	var item_name = str(item.get("name", "")).to_lower()
	if search_text != "" and search_text not in item_name:
		return false
	if category_filter == "": return true
	var type = str(item.get("type", "")).to_lower()
	match category_filter:
		"ARMAS": return type == "weapon"
		"ESCUDOS": return type == "shield"
		"MOTORES": return type == "engine"
		"RECURSOS": return type == "resource"
		"EXTRAS": return type == "utility" or type == "extra"
		"MUNICIÓN": return type == "ammo"
	return true

func _render_buy_tab():
	buy_grid.visible = true
	sell_grid.visible = false
	my_list_container.visible = false
	mailbox_container.visible = false
	_clear_children(buy_grid)
	
	var shown = 0
	for l in listings:
		if not _item_matches_filter(l.get("item", {})):
			continue
		buy_grid.add_child(_create_listing_card(l))
		shown += 1
	if shown == 0:
		var lbl = Label.new()
		lbl.text = "No hay publicaciones activas que coincidan con tu búsqueda."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buy_grid.add_child(lbl)

func _render_sell_tab():
	buy_grid.visible = false
	sell_grid.visible = true
	my_list_container.visible = false
	mailbox_container.visible = false
	_clear_children(sell_grid)
	
	var sellable = inventory_items.filter(func(it): return not it.get("soulbound", false))
	if sellable.size() == 0:
		var lbl = Label.new()
		lbl.text = "No tienes ítems comerciables. Los ítems de misión o bloqueados no se pueden vender."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sell_grid.add_child(lbl)
		return
	for it in sellable:
		sell_grid.add_child(_create_sell_card(it))

func _render_my_listings():
	buy_grid.visible = false
	sell_grid.visible = false
	my_list_container.visible = true
	mailbox_container.visible = false
	_clear_children(my_list_container)
	
	if my_listings.size() == 0:
		var lbl = Label.new()
		lbl.text = "Aún no has publicado nada en el Mercado."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		my_list_container.add_child(lbl)
		return
	for l in my_listings:
		my_list_container.add_child(_create_my_listing_row(l))

func _render_mailbox():
	buy_grid.visible = false
	sell_grid.visible = false
	my_list_container.visible = false
	mailbox_container.visible = true
	_clear_children(mailbox_container)
	
	if mailbox.size() == 0:
		var lbl = Label.new()
		lbl.text = "Buzón vacío. Los ítems no vendidos y las notificaciones de venta llegan aquí."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		mailbox_container.add_child(lbl)
		return
	for entry in mailbox:
		mailbox_container.add_child(_create_mailbox_row(entry))

func _update_balances():
	if lbl_hubs: lbl_hubs.text = "HUBS: " + _format_number(hubs)
	if lbl_ohcu: lbl_ohcu.text = "OHCU: " + _format_number(ohcu)
	if lbl_footer:
		var tax = int(market_config.get("sellTaxPercent", 0))
		var fee_h = int(market_config.get("listingFeeHubs", 0))
		var fee_o = int(market_config.get("listingFeeOhcu", 0))
		var dur = int(market_config.get("listingDurationHours", 48))
		lbl_footer.text = "Impuesto de venta: %d%% | Tasa de publicación: %d HUBS / %d OHCU | Duración: %d h" % [tax, fee_h, fee_o, dur]

# ---------------------------------------------------------------------------
# TARJETAS
# ---------------------------------------------------------------------------
func _create_listing_card(l: Dictionary) -> PanelContainer:
	var item = l.get("item", {})
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 96)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.98)
	sb.border_width_left = 3
	sb.border_color = _get_rarity_color(int(item.get("rarity", 0)))
	sb.corner_radius_top_left = 6
	sb.corner_radius_bottom_left = 6
	card.add_theme_stylebox_override("panel", sb)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	var mg = MarginContainer.new()
	mg.add_theme_constant_override("margin_top", 6)
	mg.add_theme_constant_override("margin_bottom", 6)
	mg.add_theme_constant_override("margin_left", 8)
	mg.add_theme_constant_override("margin_right", 8)
	card.add_child(mg)
	mg.add_child(hbox)
	
	var icon = _create_icon(str(item.get("icon", "")), 64)
	hbox.add_child(icon)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = str(item.get("name", "?")).to_upper() + " x" + str(l.get("amount", 1))
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", _get_rarity_color(int(item.get("rarity", 0))))
	vbox.add_child(name_lbl)
	
	var seller_lbl = Label.new()
	seller_lbl.text = "Vendedor: " + str(l.get("sellerName", "?"))
	seller_lbl.add_theme_font_size_override("font_size", 10)
	seller_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vbox.add_child(seller_lbl)
	
	var time_lbl = Label.new()
	time_lbl.text = "Quedan " + _format_duration(int(l.get("expiresAt", 0)) - Time.get_ticks_msec())
	time_lbl.add_theme_font_size_override("font_size", 10)
	time_lbl.add_theme_color_override("font_color", Color(0.85, 0.6, 0.2))
	vbox.add_child(time_lbl)
	
	var price_lbl = Label.new()
	price_lbl.text = _format_number(int(l.get("price", 0))) + " " + str(l.get("currency", "hubs")).to_upper()
	price_lbl.add_theme_font_size_override("font_size", 15)
	price_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0) if str(l.get("currency", "")) == "hubs" else Color(1.0, 0.4, 0.9))
	vbox.add_child(price_lbl)
	
	var btn = Button.new()
	btn.text = "COMPRAR"
	btn.custom_minimum_size = Vector2(110, 36)
	btn.pressed.connect(_on_buy_pressed.bind(l))
	hbox.add_child(btn)
	
	return card

func _create_sell_card(item: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(190, 150)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.98)
	sb.border_width_left = 3
	sb.border_color = _get_rarity_color(int(item.get("rarity", 0)))
	sb.corner_radius_top_left = 6
	sb.corner_radius_bottom_left = 6
	card.add_theme_stylebox_override("panel", sb)
	
	var mg = MarginContainer.new()
	mg.add_theme_constant_override("margin_top", 6)
	mg.add_theme_constant_override("margin_bottom", 6)
	mg.add_theme_constant_override("margin_left", 8)
	mg.add_theme_constant_override("margin_right", 8)
	card.add_child(mg)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	mg.add_child(vbox)
	
	var icon = _create_icon(str(item.get("icon", "")), 48)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon)
	
	var name_lbl = Label.new()
	name_lbl.text = str(item.get("name", "?")).to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", _get_rarity_color(int(item.get("rarity", 0))))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)
	
	var qty_lbl = Label.new()
	qty_lbl.text = "Cantidad: " + str(int(item.get("amount", 1)))
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.add_theme_font_size_override("font_size", 10)
	qty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vbox.add_child(qty_lbl)
	
	var btn = Button.new()
	btn.text = "PUBLICAR"
	btn.pressed.connect(_open_sell_modal.bind(item))
	vbox.add_child(btn)
	
	return card

func _create_my_listing_row(l: Dictionary) -> PanelContainer:
	var row = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.98)
	sb.border_width_left = 3
	sb.border_color = _get_rarity_color(int(l.get("item", {}).get("rarity", 0)))
	row.add_theme_stylebox_override("panel", sb)
	
	var mg = MarginContainer.new()
	mg.add_theme_constant_override("margin_top", 4)
	mg.add_theme_constant_override("margin_bottom", 4)
	mg.add_theme_constant_override("margin_left", 8)
	mg.add_theme_constant_override("margin_right", 8)
	row.add_child(mg)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	mg.add_child(hbox)
	
	var icon = _create_icon(str(l.get("item", {}).get("icon", "")), 40)
	hbox.add_child(icon)
	
	var info = Label.new()
	info.text = str(l.get("item", {}).get("name", "?")).to_upper() + " x" + str(l.get("amount", 1)) + " — " + _format_number(int(l.get("price", 0))) + " " + str(l.get("currency", "hubs")).to_upper()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 12)
	hbox.add_child(info)
	
	var status = str(l.get("status", "active"))
	var status_lbl = Label.new()
	match status:
		"active": status_lbl.text = "ACTIVA"
		"sold": status_lbl.text = "VENDIDA"
		"expired": status_lbl.text = "EXPIRADA"
		_: status_lbl.text = status.to_upper()
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if status == "active" else (Color(0.9, 0.4, 0.4) if status == "sold" else Color(0.6, 0.6, 0.65)))
	hbox.add_child(status_lbl)
	
	if status == "active":
		var btn = Button.new()
		btn.text = "CANCELAR"
		btn.pressed.connect(_on_cancel_listing.bind(l))
		hbox.add_child(btn)
	
	return row

func _create_mailbox_row(entry: Dictionary) -> PanelContainer:
	var row = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.98)
	sb.border_width_left = 3
	sb.border_color = BORDER_GOLD
	row.add_theme_stylebox_override("panel", sb)
	
	var mg = MarginContainer.new()
	mg.add_theme_constant_override("margin_top", 4)
	mg.add_theme_constant_override("margin_bottom", 4)
	mg.add_theme_constant_override("margin_left", 8)
	mg.add_theme_constant_override("margin_right", 8)
	row.add_child(mg)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	mg.add_child(hbox)
	
	var info = Label.new()
	if str(entry.get("type", "")) == "item":
		var it = entry.get("item", {})
		info.text = "📦 " + str(entry.get("reason", "")) + " — " + str(it.get("name", "?")).to_upper() + " x" + str(int(entry.get("amount", 1)))
	else:
		info.text = "💰 " + str(entry.get("reason", "")) + " — +" + _format_number(int(entry.get("amount", 0))) + " " + str(entry.get("currency", "hubs")).to_upper()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	hbox.add_child(info)
	
	var btn = Button.new()
	btn.text = "RECLAMAR"
	btn.pressed.connect(_on_claim_mailbox.bind(entry))
	hbox.add_child(btn)
	
	return row

# ---------------------------------------------------------------------------
# ACCIONES
# ---------------------------------------------------------------------------
func _on_buy_pressed(l: Dictionary):
	var item = l.get("item", {})
	var total = int(l.get("price", 0)) * int(l.get("amount", 1))
	var tax = int(market_config.get("sellTaxPercent", 0))
	var seller_gets = int(total * (100 - tax) / 100.0)
	var cur = str(l.get("currency", "hubs")).to_upper()
	_open_confirm(
		"CONFIRMAR COMPRA",
		"Comprar " + str(l.get("amount", 1)) + "x " + str(item.get("name", "?")) + "\n\nPrecio: " + _format_number(total) + " " + cur +
		"\nEl vendedor recibe " + _format_number(seller_gets) + " " + cur + " (impuesto " + str(tax) + "%)",
		func(): NetworkManager.send_event("buyMarketListing", { "listingId": str(l.get("_id", "")) })
	)

func _on_cancel_listing(l: Dictionary):
	NetworkManager.send_event("cancelMarketListing", { "listingId": str(l.get("_id", "")) })

func _on_claim_mailbox(entry: Dictionary):
	NetworkManager.send_event("claimMarketMailbox", { "entryId": str(entry.get("_id", "")) })

# ---------------------------------------------------------------------------
# MODAL DE VENTA
# ---------------------------------------------------------------------------
var modal_overlay: ColorRect = null
var modal_panel: PanelContainer = null
var modal_item: Dictionary = {}
var spin_qty: SpinBox = null
var spin_price: SpinBox = null
var opt_currency: OptionButton = null
var lbl_fee_preview: Label = null

func _open_sell_modal(item: Dictionary):
	modal_item = item
	_hide_modal()
	
	modal_overlay = ColorRect.new()
	modal_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_overlay.z_index = 50
	add_child(modal_overlay)
	
	modal_panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.015, 0.03, 0.98) # Fondo más profundo y premium
	sb.border_width_top = 4
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = BORDER_CYAN
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.shadow_color = Color(0, 0, 0, 0.85)
	sb.shadow_size = 25
	modal_panel.add_theme_stylebox_override("panel", sb)
	modal_panel.custom_minimum_size = Vector2(400, 360) # Ajustado para centrado perfecto
	modal_panel.z_index = 51
	control_root.add_child(modal_panel) # Agregado a control_root para centrado reactivo
	
	# Centrado dinámico nativo mediante anchors y offsets
	modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	modal_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	modal_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	modal_panel.offset_left = -200
	modal_panel.offset_right = 200
	modal_panel.offset_top = -180
	modal_panel.offset_bottom = 180
	
	var mg = MarginContainer.new()
	mg.add_theme_constant_override("margin_top", 18)
	mg.add_theme_constant_override("margin_bottom", 18)
	mg.add_theme_constant_override("margin_left", 22)
	mg.add_theme_constant_override("margin_right", 22)
	modal_panel.add_child(mg)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	mg.add_child(vbox)
	
	var title = Label.new()
	title.text = "PUBLICAR EN EL MERCADO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", BORDER_CYAN)
	vbox.add_child(title)
	
	var name_lbl = Label.new()
	name_lbl.text = str(item.get("name", "?"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(name_lbl)
	
	var max_amount = int(item.get("amount", 1))
	
	var qty_lbl = Label.new()
	qty_lbl.text = "Cantidad a publicar (máx " + str(max_amount) + ")"
	vbox.add_child(qty_lbl)
	spin_qty = SpinBox.new()
	spin_qty.min_value = 1
	spin_qty.max_value = max_amount
	spin_qty.value = max_amount
	spin_qty.custom_minimum_size = Vector2(0, 32)
	spin_qty.value_changed.connect(func(_v): _update_fee_preview())
	vbox.add_child(spin_qty)
	
	var cur_lbl = Label.new()
	cur_lbl.text = "Moneda"
	vbox.add_child(cur_lbl)
	opt_currency = OptionButton.new()
	opt_currency.add_item("HUBS (moneda común)")
	opt_currency.add_item("OHCU (mineral raro)")
	opt_currency.select(0)
	opt_currency.item_selected.connect(func(_i): _update_fee_preview())
	vbox.add_child(opt_currency)
	
	var price_lbl = Label.new()
	price_lbl.text = "Precio por unidad"
	vbox.add_child(price_lbl)
	spin_price = SpinBox.new()
	spin_price.min_value = 1
	spin_price.max_value = 999999999
	spin_price.value = 100
	spin_price.custom_minimum_size = Vector2(0, 32)
	spin_price.value_changed.connect(func(_v): _update_fee_preview())
	vbox.add_child(spin_price)
	
	lbl_fee_preview = Label.new()
	lbl_fee_preview.add_theme_font_size_override("font_size", 11)
	lbl_fee_preview.add_theme_color_override("font_color", Color(0.85, 0.6, 0.2))
	vbox.add_child(lbl_fee_preview)
	_update_fee_preview()
	
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "CANCELAR"
	btn_cancel.pressed.connect(_hide_modal)
	btn_row.add_child(btn_cancel)
	
	var btn_publish = Button.new()
	btn_publish.text = "PUBLICAR"
	btn_publish.pressed.connect(_confirm_publish)
	btn_row.add_child(btn_publish)

func _update_fee_preview():
	if not is_instance_valid(lbl_fee_preview): return
	var qty = int(spin_qty.value) if is_instance_valid(spin_qty) else 1
	var price = int(spin_price.value) if is_instance_valid(spin_price) else 0
	var is_ohcu = (opt_currency.selected == 1) if is_instance_valid(opt_currency) else false
	var fee = int(market_config.get("listingFeeOhcu", 0)) if is_ohcu else int(market_config.get("listingFeeHubs", 0))
	var total = price * qty
	var tax = int(market_config.get("sellTaxPercent", 0))
	var seller_net = int(total * (100 - tax) / 100.0)
	var dur = int(market_config.get("listingDurationHours", 48))
	lbl_fee_preview.text = "Tasa de publicación: " + _format_number(fee) + " " + ("OHCU" if is_ohcu else "HUBS") + " | Total: " + _format_number(total) + " | Al venderse recibirás " + _format_number(seller_net) + " (" + str(tax) + "% impuesto) | Duración: " + str(dur) + " h"

func _confirm_publish():
	if not is_instance_valid(spin_price) or not is_instance_valid(spin_qty):
		return
	var price = int(spin_price.value)
	var qty = int(spin_qty.value)
	var cur = "ohcu" if opt_currency.selected == 1 else "hubs"
	NetworkManager.send_event("createMarketListing", {
		"instanceId": str(modal_item.get("instanceId", "")),
		"amount": qty,
		"price": price,
		"currency": cur
	})
	_hide_modal()

func _hide_modal():
	if is_instance_valid(modal_overlay):
		modal_overlay.queue_free()
		modal_overlay = null
	if is_instance_valid(modal_panel):
		modal_panel.queue_free()
		modal_panel = null

# ---------------------------------------------------------------------------
# MODAL DE CONFIRMACIÓN
# ---------------------------------------------------------------------------
var confirm_callback: Callable = Callable()

func _open_confirm(title: String, msg: String, on_confirm: Callable):
	_hide_modal()
	confirm_callback = on_confirm
	
	modal_overlay = ColorRect.new()
	modal_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_overlay.z_index = 50
	add_child(modal_overlay)
	
	modal_panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.015, 0.03, 0.98) # Fondo más profundo y premium
	sb.border_width_top = 4
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = BORDER_GOLD
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.shadow_color = Color(0, 0, 0, 0.85)
	sb.shadow_size = 25
	modal_panel.add_theme_stylebox_override("panel", sb)
	modal_panel.custom_minimum_size = Vector2(440, 220)
	modal_panel.z_index = 51
	control_root.add_child(modal_panel) # Agregado a control_root para centrado reactivo
	
	# Centrado dinámico nativo mediante anchors y offsets
	modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	modal_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	modal_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	modal_panel.offset_left = -220
	modal_panel.offset_right = 220
	modal_panel.offset_top = -110
	modal_panel.offset_bottom = 110
	
	var mg = MarginContainer.new()
	mg.add_theme_constant_override("margin_top", 18)
	mg.add_theme_constant_override("margin_bottom", 18)
	mg.add_theme_constant_override("margin_left", 22)
	mg.add_theme_constant_override("margin_right", 22)
	modal_panel.add_child(mg)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	mg.add_child(vbox)
	
	var t = Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", BORDER_GOLD)
	vbox.add_child(t)
	
	var m = Label.new()
	m.text = msg
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.add_theme_font_size_override("font_size", 13)
	vbox.add_child(m)
	
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "CANCELAR"
	btn_cancel.pressed.connect(_hide_modal)
	btn_row.add_child(btn_cancel)
	
	var btn_ok = Button.new()
	btn_ok.text = "CONFIRMAR"
	btn_ok.pressed.connect(func():
		_hide_modal()
		if confirm_callback.is_valid():
			confirm_callback.call()
	)
	btn_row.add_child(btn_ok)

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
func _create_icon(path: String, size: float) -> Control:
	var container = CenterContainer.new()
	container.custom_minimum_size = Vector2(size, size)
	if path != "" and ResourceLoader.exists(path):
		var tex = TextureRect.new()
		tex.texture = load(path)
		tex.custom_minimum_size = Vector2(size, size)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		container.add_child(tex)
	else:
		var fallback = Label.new()
		fallback.text = "?"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 20)
		fallback.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		container.add_child(fallback)
	return container

func _get_rarity_color(rarity: int) -> Color:
	return RARITY_COLORS.get(rarity, Color(0.8, 0.8, 0.8))

func _format_number(value: int) -> String:
	var v = absi(value)
	var prefix = "-" if value < 0 else ""
	if v >= 1000000:
		return prefix + ("%.2fM" % (v / 1000000.0)).replace(".00", "")
	if v >= 10000:
		return prefix + ("%.1fK" % (v / 1000.0)).replace(".0", "") + "K"
	return prefix + str(v)

func _format_duration(ms_left: int) -> String:
	if ms_left <= 0: return "0m"
	var total_min = int(ms_left / 60000.0)
	var days = int(total_min / 1440.0)
	var hours = int((total_min % 1440) / 60.0)
	var mins = total_min % 60
	if days > 0: return str(days) + "d " + str(hours) + "h"
	if hours > 0: return str(hours) + "h " + str(mins) + "m"
	return str(mins) + "m"

func _notify(msg: String, type: String):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("notify"):
		hud.notify(msg, type)
	else:
		print("[MARKET] " + msg)
