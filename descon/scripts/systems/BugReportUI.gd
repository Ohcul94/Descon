extends Control
# BugReportUI.gd (v1.0) - Modal de Reporte de Bugs
# Accesible desde el menú ESC. Todos los campos se tratan como texto plano:
# se eliminan caracteres de control y nunca se interpretan como código.

signal closed

const MAX_DESC_CHARS: int = 1000
const MAX_IMAGES: int = 2
const MAX_IMAGE_BYTES: int = 3 * 1024 * 1024

var _overlay: Control
var _panel: PanelContainer
var _nick_label: Label
var _email_input: LineEdit
var _phone_input: LineEdit
var _desc_input: TextEdit
var _char_counter: Label
var _images_box: HBoxContainer
var _attach_btn: Button
var _error_label: Label
var _attached_images: Array = []
var _file_dialog: FileDialog
var _email_regex := RegEx.new()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)
	visible = false
	_email_regex.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")
	_build_ui()
	get_viewport().size_changed.connect(_recenter)

func open():
	_reset_form()
	visible = true
	_recenter()
	_email_input.grab_focus()

func close():
	visible = false
	closed.emit()

func _input(event: InputEvent):
	if not visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _recenter():
	if not visible or not is_instance_valid(_panel): return
	_reset_size()
	var vp = get_viewport_rect().size
	_panel.global_position = (vp - _panel.size) / 2.0

func _reset_size():
	_panel.reset_size()
	_panel.custom_minimum_size = Vector2(480, 560)
	_panel.size = Vector2(480, 560)

func _prefill_nick():
	var nick := ""
	if NetworkManager and NetworkManager.current_user_data.has("user"):
		nick = str(NetworkManager.current_user_data.user)
	if _nick_label:
		_nick_label.text = nick if nick != "" else "DESCONOCIDO"

func _reset_form():
	_email_input.text = ""
	_phone_input.text = ""
	_desc_input.text = ""
	_char_counter.text = "0/" + str(MAX_DESC_CHARS)
	_attached_images.clear()
	_error_label.text = ""
	_refresh_images_ui()
	_prefill_nick()

func _build_ui():
	_overlay = Control.new()
	_overlay.name = "BugReportOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.name = "BugReportPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.03, 0.06, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.6, 0.1)
	style.set_corner_radius_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(480, 560)
	_panel.size = Vector2(480, 560)
	_overlay.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "🐛 REPORTAR BUGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color(1.0, 0.6, 0.1)
	vbox.add_child(title)

	var nick_row := HBoxContainer.new()
	nick_row.add_theme_constant_override("separation", 8)
	var nick_tag := Label.new()
	nick_tag.text = "NICK:"
	nick_tag.add_theme_font_size_override("font_size", 13)
	nick_tag.custom_minimum_size.x = 60
	nick_row.add_child(nick_tag)
	_nick_label = Label.new()
	_nick_label.name = "NickLabel"
	_nick_label.text = "DESCONOCIDO"
	_nick_label.add_theme_font_size_override("font_size", 15)
	_nick_label.modulate = Color.CYAN
	_nick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nick_row.add_child(_nick_label)
	vbox.add_child(nick_row)

	_email_input = LineEdit.new()
	_email_input.name = "EmailInput"
	_email_input.placeholder_text = "TU EMAIL (OBLIGATORIO)"
	_email_input.custom_minimum_size = Vector2(0, 40)
	_email_input.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_email_input)

	_phone_input = LineEdit.new()
	_phone_input.name = "PhoneInput"
	_phone_input.placeholder_text = "CELULAR (OPCIONAL) - Incluí código de país y área. Ej: +54 11 5555-1234"
	_phone_input.custom_minimum_size = Vector2(0, 40)
	_phone_input.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_phone_input)

	var desc_label := Label.new()
	desc_label.text = "DESCRIPCIÓN DEL BUG (MÁX 1000 CARACTERES):"
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.modulate = Color(0.7, 0.75, 0.8)
	vbox.add_child(desc_label)

	_desc_input = TextEdit.new()
	_desc_input.name = "DescInput"
	_desc_input.custom_minimum_size = Vector2(0, 150)
	_desc_input.placeholder_text = "Describí qué pasó, qué estabas haciendo, y qué esperabas que ocurriera..."
	_desc_input.add_theme_font_size_override("font_size", 14)
	_desc_input.text_changed.connect(_on_desc_changed)
	vbox.add_child(_desc_input)

	_char_counter = Label.new()
	_char_counter.name = "CharCounter"
	_char_counter.text = "0/" + str(MAX_DESC_CHARS)
	_char_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_char_counter.add_theme_font_size_override("font_size", 11)
	_char_counter.modulate = Color(0.6, 0.65, 0.7)
	vbox.add_child(_char_counter)

	var attach_row := HBoxContainer.new()
	attach_row.add_theme_constant_override("separation", 10)
	_attach_btn = Button.new()
	_attach_btn.name = "AttachButton"
	_attach_btn.text = "ADJUNTAR IMAGEN (0/" + str(MAX_IMAGES) + ")"
	_attach_btn.custom_minimum_size = Vector2(200, 40)
	_attach_btn.pressed.connect(_on_attach_pressed)
	attach_row.add_child(_attach_btn)
	_images_box = HBoxContainer.new()
	_images_box.name = "ImagesBox"
	_images_box.add_theme_constant_override("separation", 8)
	_images_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attach_row.add_child(_images_box)
	vbox.add_child(attach_row)

	_error_label = Label.new()
	_error_label.name = "ErrorLabel"
	_error_label.text = ""
	_error_label.modulate = Color(1.0, 0.3, 0.3)
	_error_label.add_theme_font_size_override("font_size", 12)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_error_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	var send_btn := Button.new()
	send_btn.text = "ENVIAR REPORTE"
	send_btn.custom_minimum_size = Vector2(180, 44)
	send_btn.modulate = Color(0.3, 1.0, 0.4)
	send_btn.pressed.connect(_on_send_pressed)
	btn_row.add_child(send_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "CANCELAR"
	cancel_btn.custom_minimum_size = Vector2(180, 44)
	cancel_btn.modulate = Color(1.0, 0.4, 0.4)
	cancel_btn.pressed.connect(close)
	btn_row.add_child(cancel_btn)
	vbox.add_child(btn_row)

	_file_dialog = FileDialog.new()
	_file_dialog.name = "BugImageFileDialog"
	_file_dialog.title = "SELECCIONAR IMÁGENES (MÁX " + str(MAX_IMAGES) + ")"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray([
		"*.png ; Imagen PNG",
		"*.jpg ; Imagen JPG",
		"*.jpeg ; Imagen JPEG",
		"*.webp ; Imagen WEBP"
	])
	_file_dialog.files_selected.connect(_on_files_selected)
	add_child(_file_dialog)

func _on_desc_changed():
	var t := _desc_input.text
	if t.length() > MAX_DESC_CHARS:
		_desc_input.text = t.substr(0, MAX_DESC_CHARS)
		_desc_input.caret_column = MAX_DESC_CHARS
	_char_counter.text = str(_desc_input.text.length()) + "/" + str(MAX_DESC_CHARS)

func _on_attach_pressed():
	_file_dialog.popup_centered_ratio(0.6)

func _on_files_selected(paths: PackedStringArray):
	for p in paths:
		if _attached_images.size() >= MAX_IMAGES:
			break
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var file_len := f.get_length()
		if file_len <= 0 or file_len > MAX_IMAGE_BYTES:
			f.close()
			continue
		var bytes := f.get_buffer(file_len)
		f.close()
		var comp := _compress_image(bytes)
		if comp.is_empty():
			continue
		_attached_images.append({
			"name": p.get_file(),
			"mime": comp.mime,
			"path": p,
			"data": Marshalls.raw_to_base64(comp.bytes)
		})
	_refresh_images_ui()

# v1.3: Comprime y redimensiona la imagen antes de enviarla. Un payload gigante
# (imágenes de 3 MB en base64) excede el buffer del WebSocket y el servidor corta
# la conexión. Tope duro de ~256 KB por imagen => 2 imágenes ≈ 700 KB base64,
# cabe incluso en servidores con buffer de 1 MB.
func _compress_image(p_bytes: PackedByteArray) -> Dictionary:
	var img := Image.new()
	if img.load_png_from_buffer(p_bytes) != OK:
		img = Image.new()
		if img.load_jpg_from_buffer(p_bytes) != OK:
			img = Image.new()
			if img.load_webp_from_buffer(p_bytes) != OK:
				return {}
	const MAX_DIM := 1280
	const TARGET_MAX_BYTES := 256 * 1024
	if img.get_width() > MAX_DIM or img.get_height() > MAX_DIM:
		var scale_factor := float(MAX_DIM) / float(maxi(img.get_width(), img.get_height()))
		img.resize(maxi(1, int(round(img.get_width() * scale_factor))), maxi(1, int(round(img.get_height() * scale_factor))), Image.INTERPOLATE_LANCZOS)
	var out := img.save_jpg_to_buffer(0.85)
	if out.size() > TARGET_MAX_BYTES:
		out = img.save_jpg_to_buffer(0.6)
	if out.size() > TARGET_MAX_BYTES:
		var s2 := float(1024) / float(maxi(img.get_width(), img.get_height()))
		img.resize(maxi(1, int(round(img.get_width() * s2))), maxi(1, int(round(img.get_height() * s2))), Image.INTERPOLATE_LANCZOS)
		out = img.save_jpg_to_buffer(0.6)
	return {"bytes": out, "mime": "image/jpeg"}

func _refresh_images_ui():
	for child in _images_box.get_children():
		child.queue_free()
	_attach_btn.text = "ADJUNTAR IMAGEN (" + str(_attached_images.size()) + "/" + str(MAX_IMAGES) + ")"
	for i in range(_attached_images.size()):
		var entry: Dictionary = _attached_images[i]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(64, 64)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var img := Image.load_from_file(str(entry.path))
		if img:
			preview.texture = ImageTexture.create_from_image(img)
		cell.add_child(preview)
		var remove_btn := Button.new()
		remove_btn.text = "✕ QUITAR"
		remove_btn.add_theme_font_size_override("font_size", 9)
		remove_btn.modulate = Color(1.0, 0.4, 0.4)
		var idx := i
		remove_btn.pressed.connect(func():
			_attached_images.remove_at(idx)
			_refresh_images_ui()
		)
		cell.add_child(remove_btn)
		_images_box.add_child(cell)

func _sanitize_text(p_raw: String) -> String:
	var out := ""
	for ch in p_raw:
		var code := ch.unicode_at(0)
		if code < 32 and code != 10:
			continue
		out += ch
	return out.strip_edges()

func _on_send_pressed():
	var email := _sanitize_text(_email_input.text)
	var phone := _sanitize_text(_phone_input.text)
	var desc := _sanitize_text(_desc_input.text)

	if email.is_empty():
		_show_error("⚠ EL EMAIL ES OBLIGATORIO")
		return
	if not _email_regex.search(email):
		_show_error("⚠ INGRESÁ UN EMAIL VÁLIDO (ej: piloto@galaxia.com)")
		return
	if desc.is_empty():
		_show_error("⚠ LA DESCRIPCIÓN ES OBLIGATORIA")
		return
	_show_error("")

	var images: Array = []
	for entry in _attached_images:
		images.append({
			"name": str(entry.name),
			"mime": str(entry.mime),
			"data": str(entry.data)
		})

	if NetworkManager:
		NetworkManager.send_event("reportBug", {
			"email": email,
			"phone": phone,
			"description": desc,
			"images": images
		})
	close()

func _show_error(msg: String):
	_error_label.text = msg
