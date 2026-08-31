@tool
extends EditorPlugin

var _editor_dock: Control = null
var _map_editor_scene: PackedScene = null
var _map_editor_instance: Node = null

func _enter_tree():
	# Añadir botón en la barra superior del editor
	var btn = Button.new()
	btn.text = "🗺️ MapEditor3D"
	btn.tooltip_text = "Abrir editor 3D de mapas (visuales 3D + física 2D)"
	btn.custom_minimum_size = Vector2(140, 30)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.1, 0.15, 0.25)
	style_normal.border_width_left = 1
	style_normal.border_width_top = 1
	style_normal.border_width_right = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0, 0.7, 1, 0.8)
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.15, 0.25, 0.4)
	style_hover.border_color = Color(0, 1, 1, 1)
	btn.add_theme_stylebox_override("hover", style_hover)
	
	btn.add_theme_color_override("font_color", Color(0.8, 0.95, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	
	btn.pressed.connect(_on_editor_button_pressed)
	
	add_control_to_container(CONTAINER_TOOLBAR, btn)

func _exit_tree():
	if _map_editor_instance:
		_map_editor_instance.queue_free()
		_map_editor_instance = null

func _on_editor_button_pressed():
	if not _map_editor_instance:
		_open_editor()
	else:
		_close_editor()

func _open_editor():
	if not _map_editor_scene:
		_map_editor_scene = load("res://tools/MapEditor3D.tscn")
	if not _map_editor_scene:
		push_warning("[MapEditor3D] No se encontró MapEditor3D.tscn")
		return
	_map_editor_instance = _map_editor_scene.instantiate()
	get_editor_interface().get_editor_viewport().add_child(_map_editor_instance)
	
	# Hacer que la cámara del editor sea la activa temporalmente
	var editor_viewport = get_editor_interface().get_editor_viewport()
	var cam = _map_editor_instance.get_node_or_null("Camera3D")
	if cam:
		cam.make_current()
	
	print("[MapEditor3D] Editor abierto. Controles:")
	print("  Click izq: Seleccionar/Arrastrar")
	print("  Click der: Menú contextual")
	print("  G: Toggle snap grid")
	print("  W/E/R: Mover/Rotar/Escalar (gizmo)")
	print("  Del: Eliminar")
	print("  Ctrl+D: Duplicar")
	print("  Ctrl+C: Copiar JSON al portapapeles")
	print("  Arrastra .glb a ObjectsRoot en el árbol de escena")

func _close_editor():
	if _map_editor_instance:
		_map_editor_instance.queue_free()
		_map_editor_instance = null
		print("[MapEditor3D] Editor cerrado")

func _apply_changes():
	# Buscar si la escena editada actualmente tiene un nodo MapEditor3D
	var scene_root = get_editor_interface().get_edited_scene_root()
	if is_instance_valid(scene_root):
		var map_editor = _find_map_editor_node(scene_root)
		if is_instance_valid(map_editor) and map_editor.has_method("save_to_server"):
			print("[MapEditor3DPlugin] 💾 Guardado automático detectado (Ctrl+S). Exportando config a Server/config.json...")
			map_editor.save_to_server()

func _save_external_data():
	# v700.10: Godot 4 llama a _save_external_data al guardar escena (Ctrl+S), no _apply_changes
	_apply_changes()

func _find_map_editor_node(node: Node) -> Node:
	if not is_instance_valid(node):
		return null
	# Comparar por clase o nombre del script
	if node is MapEditor3D or node.get_class() == "MapEditor3D" or node.name == "MapEditor3D":
		return node
	for child in node.get_children():
		var found = _find_map_editor_node(child)
		if found:
			return found
	return null

