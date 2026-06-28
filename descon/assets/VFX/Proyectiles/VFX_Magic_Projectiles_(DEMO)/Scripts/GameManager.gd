extends Node

var vfx:Array[Resource] 
var hit:Array[Resource] 
var muzzle:Array[Resource]
var character:Node3D

var selector:int
var single_projectile:bool = true
var is_attacking:bool = false

func _ready() -> void:
	
	
	# Preload everything (not recommended for big projects)
	vfx = [ 
		preload("res://VFX/Scenes/VFX_Fire_ball_standar.tscn"),
		preload("res://VFX/Scenes/VFX_Fire_strike.tscn"),
		preload("res://VFX/Scenes/VFX_Electric_strike.tscn"),
		preload("res://VFX/Scenes/VFX_Darkness_projectile.tscn"),
		preload("res://VFX/Scenes/VFX_Cube_projectile.tscn"),
		preload("res://VFX/Scenes/VFX_Fire_ball_type_B.tscn"),
		preload("res://VFX/Scenes/VFX_Hadouken.tscn")
		]
		
	hit = [ 
		preload("res://VFX/Scenes/VFX_Hit_fire_2.tscn"),
		preload("res://VFX/Scenes/VFX_Hit_fire_1.tscn"),
		preload("res://VFX/Scenes/VFX_Hit_electric.tscn"),
		preload("res://VFX/Scenes/VFX_Hit_dark.tscn"),
		preload("res://VFX/Scenes/VFX_Hit_cyber.tscn"),
		preload("res://VFX/Scenes/VFX_Hit_fire_3.tscn"),
		preload("res://VFX/Scenes/VFX_Hit_hadouken.tscn")
		]
		
	muzzle = [ 
		preload("res://VFX/Scenes/VFX_Anticipation_fire_3.tscn"),
		preload("res://VFX/Scenes/VFX_Anticipation_fire_1.tscn"),
		preload("res://VFX/Scenes/VFX_Anticipation_wave_1.tscn"),
		preload("res://VFX/Scenes/VFX_Anticipation_wave_1.tscn"),
		preload("res://VFX/Scenes/VFX_Anticipation_wave_digital.tscn"),
		preload("res://VFX/Scenes/VFX_Anticipation_fire_3.tscn"),
		preload("res://VFX/Scenes/VFX_Anticipation_hadouken.tscn")
		]

	#Get character
	character = get_tree().get_nodes_in_group("Character")[0]

func set_vfx_number(val:int):
	selector = val;
	character.play_vfx_animation()
	
func get_vfx_number():
	return selector;
	
func set_single_projectile(bo:bool):
	single_projectile = bo
	
func get_single_projectile():
	return single_projectile;

func set_is_attacking(boa:bool):
	is_attacking = boa
	
func get_is_attacking():
	return is_attacking;
