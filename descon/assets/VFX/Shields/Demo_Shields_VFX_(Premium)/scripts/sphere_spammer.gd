extends Marker3D

var shield1_inst:Node3D;

# Preload all shields
@onready var shield:Array[PackedScene] = [
	preload("res://VFX/scenes/VFX_Shield_green.tscn"),
	preload("res://VFX/scenes/VFX_Shield_blue_basic.tscn"),
	preload("res://VFX/scenes/VFX_Shield_blue_wild.tscn"),
	preload("res://VFX/scenes/VFX_Shield_demon.tscn"),
	preload("res://VFX/scenes/VFX_Shield_hex.tscn")
	]


# Create the first Shield
func _ready() -> void:
	create_shield(SceneManager.number);


# If Press Arrow keys change to the next shield
func _unhandled_input(_event: InputEvent) -> void:
	
	if Input.is_action_just_pressed("left_key"):
		if SceneManager.number>0:
			SceneManager.number -= 1;
		else:
			SceneManager.number = 4;
		clear_shield();
		create_shield(SceneManager.number);
	
	if Input.is_action_just_pressed("right_key"):
		
		if SceneManager.number<4:
			SceneManager.number += 1;
		else:
			SceneManager.number = 0;
		clear_shield();
		create_shield(SceneManager.number);

# Functions to Create and Clear Shields
func create_shield(number:int)->void:
	shield1_inst  = shield[number].instantiate();
	shield1_inst.sphere_size = 0.25;
	add_child(shield1_inst);
	shield1_inst.get_node("AnimationPlayer").play("start_animation");

func clear_shield()->void:
	if shield1_inst != null:
		shield1_inst.queue_free();
