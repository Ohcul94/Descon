@tool
extends Node

# Trigger boolean in the Inspector
@export var capture_sky: bool = false

# Expose the viewport and camera to the editor
@export var viewport: Viewport
@export var camera: Camera3D

func _process(_delta):
	# Only run in the editor when the boolean is true
	if Engine.is_editor_hint() and capture_sky:
		capture_sky_image()
		capture_sky = false  # Reset the trigger

func capture_sky_image():
	if not viewport or not camera:
		push_error("Viewport or Camera not assigned!")
		return

	# Rotate camera if you want to look straight up
	camera.rotation_degrees = Vector3(90, 0, 0)

	# Wait until the viewport is fully rendered
	await RenderingServer.frame_post_draw

	# Grab the viewport image
	var image: Image = viewport.get_texture().get_image()
	image.flip_y()  # Correct orientation

	# Ensure the folder exists
	var dir = DirAccess.open("res://sky/capture")

	# Save the image
	var save_path = "res://sky/capture/sky_capture.png"
	var err = image.save_png(save_path)
	if err == OK:
		print("Sky captured and saved to ", save_path)
	else:
		push_error("Failed to save image: %s" % err)
