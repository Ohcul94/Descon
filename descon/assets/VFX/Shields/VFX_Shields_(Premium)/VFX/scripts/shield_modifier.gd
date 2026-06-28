#####  THIS IS A AUTO-SCRIPT  TO SYNCHRONYZING DISTORTION SPHERE AND COLORS SPHERE #######
###########    ITS MOSTLY USEFULL FOR TESTING, BUT DELETE THIS IF YOU WANT     ###########

@tool

extends Node3D


@export var dissapear_line:float = 0.84:
	set(new_dissapear_line):
		dissapear_line = new_dissapear_line
		self._on_dissapear_line_has_changed()

@export var sphere_size:float = 0.00:
	set(new_sphere_size):
		sphere_size = new_sphere_size
		self._on_size_has_changed()

func _on_dissapear_line_has_changed()->void:
		for child in self.get_children():
			if child is MeshInstance3D:
				child.material_override.set("shader_parameter/Gradient_Line",dissapear_line);

func _on_size_has_changed()->void:
		for child in self.get_children():
			if child is MeshInstance3D:
				child.material_override.set("shader_parameter/Size_Sphere",sphere_size);

