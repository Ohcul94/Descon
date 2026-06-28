extends Node3D

var VFX_pos:Vector3 

@onready var projectiler:Resource = preload("res://Misc/projectile.tscn")
var projectiler_inst:Node3D 

var projectile:Node3D
var muzzle:Node3D

var effect:Node3D

var track:Array[PathFollow3D]
var tween:Tween


func _ready() -> void:
	VFX_pos = $VFX_spammer.global_position
	for nodes:Node in get_tree().get_nodes_in_group("trajectory"):
		track.push_back(nodes)

#Debug on key
func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_up"):
		play_vfx_animation()



func Attack(_type:int)->void:
	print(" ")
	print(" ------- ATTACK -------")
			
	#Spawn muzzle
	muzzle = GameManager.muzzle[_type].instantiate()
	get_parent().add_child(muzzle)
	muzzle.global_position = VFX_pos
	print("created muzzle VFX")
	

	#Spawn projectile
	projectile = GameManager.vfx[_type].instantiate()
	print("created fire ball VFX ")
	
	#Spawn Projectiler
	projectiler_inst = projectiler.instantiate()
	
	#Set Projectiler Trajectory
	if  GameManager.get_single_projectile():
		get_parent().add_child(projectiler_inst)
		projectiler_inst.global_position = VFX_pos
	else:
		#check if it has trails and tweak
		if projectile.find_child("Trail1_static") != null:
			projectile.find_child("Trail1_static").visible = false
			projectile.find_child("Trail2_dynamic").visible = true
			if projectile.find_child("Trail1_static2") != null:
				projectile.find_child("Trail1_static2").visible = false
		#trace trajectory over curve
		track[0].add_child(projectiler_inst)
		tween = get_tree().create_tween().bind_node(projectiler_inst).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(track[0], "progress_ratio", 1, 0.7)
		track[0].progress_ratio = 0

	print("created Projectiler")


	#Attach Effect to projectiler
	projectiler_inst.add_child(projectile)
	projectiler_inst.projectile = projectile
	
	await muzzle.find_child("AnimationPlayer").animation_finished
	muzzle.queue_free()
	print("Destroyed muzzle VFX ")
	
#When animation calls
func on_animation_triggered()->void:
	Attack(GameManager.get_vfx_number())

#Play animation
func play_vfx_animation()->void:
	$AnimationPlayer.stop()
	$AnimationPlayer.play("Armature|mixamo_com|Layer0_remap")
	GameManager.set_is_attacking(true)
	if $AnimationPlayer.get_current_animation() == "Armature|mixamo_com|Layer0_remap":
		await $AnimationPlayer.animation_finished
		$AnimationPlayer.play("Idle")
		GameManager.set_is_attacking(false)
