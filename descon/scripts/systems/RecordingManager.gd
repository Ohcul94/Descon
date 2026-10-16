extends Node

# Gestor de grabación y exportación de video

signal recording_started(platform: int, resolution: Vector2i, fps: int)
signal recording_stopped(file_path: String)
signal recording_error(error_message: String)
signal frame_recorded(frame_number: int, total_frames: int)

enum VideoCodec {
	H264 = 0,
	H265 = 1,
	VP8 = 2,
	VP9 = 3
}

var _is_recording: bool = false
var _recording_thread: Thread = null
var _frame_queue: Array[Image] = []
var _max_queue_size: int = 120
var _target_fps: int = 60
var _current_platform: int = 0
var _current_resolution: Vector2i = Vector2i(1920, 1080)
var _current_quality: int = 90
var _output_path: String = "user://social_media_recordings/"
var _frame_count: int = 0
var _start_time: float = 0.0
var _viewport: Viewport = null
var _camera_3d: Camera3D = null
var _render_target: SubViewport = null
var _render_texture: ViewportTexture = null
var _async_save: bool = true

func _ready():
	_ensure_output_dir()
	_viewport = get_viewport()

func _ensure_output_dir():
	var dir = DirAccess.open(_output_path)
	if not dir:
		DirAccess.make_dir_recursive_absolute(_output_path)

func start_recording(platform: int, resolution: Vector2i, fps: int = 60, quality: int = 90, output_path: String = "") -> bool:
	if _is_recording:
		push_warning("Already recording!")
		return false
	
	_current_platform = platform
	_current_resolution = resolution
	_target_fps = fps
	_current_quality = quality
	
	if output_path != "":
		_output_path = output_path
		_ensure_output_dir()
	
	_setup_render_target()
	
	_is_recording = true
	_frame_count = 0
	_start_time = Time.get_ticks_msec() / 1000.0
	_frame_queue.clear()
	
	_recording_thread = Thread.new()
	var err = _recording_thread.start(_recording_thread_func.bind())
	if err != OK:
		_is_recording = false
		recording_error.emit("Failed to start recording thread: " + str(err))
		return false
	
	recording_started.emit(platform, resolution, fps)
	print("[RecordingManager] Started recording: ", _get_platform_name(platform), " ", resolution.x, "x", resolution.y, "@", fps, "fps")
	return true

func stop_recording() -> String:
	if not _is_recording:
		return ""
	
	_is_recording = false
	
	if _recording_thread and _recording_thread.is_started():
		_recording_thread.wait_to_finish()
	
	var file_path = _finalize_recording()
	
	_cleanup_render_target()
	
	recording_stopped.emit(file_path)
	print("[RecordingManager] Stopped recording: ", file_path)
	return file_path

func _setup_render_target():
	_render_target = SubViewport.new()
	_render_target.name = "SocialMediaRecordViewport"
	_render_target.size = _current_resolution
	_render_target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_render_target.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_render_target.msaa_3d = Viewport.MSAA_4X
	_render_target.own_world_3d = false
	_render_target.canvas_cull_mask = 0
	_render_target.global_canvas_transform = Transform2D.IDENTITY
	
	# Get the main camera
	var base_map = get_tree().get_first_node_in_group("map")
	if base_map:
		_camera_3d = base_map.get("camera_3d")
	
	if _camera_3d:
		_render_target.world_3d = _camera_3d.get_world_3d()
	
	get_tree().root.add_child(_render_target)
	_render_texture = _render_target.get_texture()

func _cleanup_render_target():
	if _render_target and is_instance_valid(_render_target):
		_render_target.queue_free()
		_render_target = null
	_render_texture = null

func _recording_thread_func():
	var frame_time = 1.0 / _target_fps
	var next_frame_time = Time.get_ticks_msec() / 1000.0
	
	while _is_recording:
		var current_time = Time.get_ticks_msec() / 1000.0
		
		if current_time >= next_frame_time:
			_capture_frame()
			next_frame_time += frame_time
			_frame_count += 1
			
			if _frame_count % 30 == 0:
				call_deferred("_emit_frame_progress", _frame_count)
		else:
			var sleep_time = (next_frame_time - current_time) * 1000
			if sleep_time > 1:
				OS.delay_usec(int(sleep_time * 1000))

func get_output_folder_global() -> String:
	return ProjectSettings.globalize_path(_output_path)

func open_output_folder():
	var global_path = get_output_folder_global()
	DirAccess.make_dir_recursive_absolute(global_path)
	OS.shell_open(global_path)

func _capture_frame():
	var img: Image = null
	if _render_target and is_instance_valid(_render_target) and _render_target.get_texture():
		img = _render_target.get_texture().get_image()
	
	if img == null or img.is_empty():
		if _viewport and _viewport.get_texture():
			img = _viewport.get_texture().get_image()
	
	if img and not img.is_empty():
		var src_w = img.get_width()
		var src_h = img.get_height()
		var target_aspect = float(_current_resolution.x) / float(_current_resolution.y)
		var src_aspect = float(src_w) / float(src_h)
		
		if abs(src_aspect - target_aspect) > 0.05:
			var crop_w = src_w
			var crop_h = src_h
			if src_aspect > target_aspect:
				crop_w = int(src_h * target_aspect)
			else:
				crop_h = int(src_w / target_aspect)
			
			var crop_x = int((src_w - crop_w) / 2.0)
			var crop_y = int((src_h - crop_h) / 2.0)
			img = img.get_region(Rect2i(crop_x, crop_y, crop_w, crop_h))
		
		if img.get_size() != _current_resolution:
			img.resize(_current_resolution.x, _current_resolution.y, Image.INTERPOLATE_CUBIC)
		
		_frame_queue.append(img)
		if _frame_queue.size() > _max_queue_size:
			_frame_queue.pop_front()

func _emit_frame_progress(frame_num: int):
	frame_recorded.emit(frame_num, -1)

func _finalize_recording() -> String:
	var timestamp = Time.get_datetime_dict_from_system()
	var date_str = "%04d-%02d-%02d_%02d-%02d-%02d" % [
		timestamp.year, timestamp.month, timestamp.day,
		timestamp.hour, timestamp.minute, timestamp.second
	]
	
	var platform_name = _get_platform_name(_current_platform).to_lower().replace(" ", "_")
	var file_name = "rec_%s_%s_%dx%d.mp4" % [platform_name, date_str, _current_resolution.x, _current_resolution.y]
	var file_path = _output_path.path_join(file_name)
	
	# Use FFmpeg to encode the video
	var success = _encode_video_ffmpeg(file_path)
	
	if not success:
		# Fallback: save as image sequence
		file_path = _save_image_sequence(date_str, platform_name)
	
	_frame_queue.clear()
	return file_path

func _encode_video_ffmpeg(output_path: String) -> bool:
	if _frame_queue.is_empty():
		return false
	
	# Check if FFmpeg is available
	var ffmpeg_path = _find_ffmpeg()
	if ffmpeg_path == "":
		push_warning("FFmpeg not found, falling back to image sequence")
		return false
	
	# Create a temporary directory for frames
	var temp_dir = _output_path.path_join("temp_frames_%d" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(temp_dir)
	
	# Save frames as PNG
	for i in range(_frame_queue.size()):
		var frame = _frame_queue[i]
		var frame_path = temp_dir.path_join("frame_%06d.png" % i)
		frame.save_png(frame_path)
	
	# Build FFmpeg command
	var fps_str = str(_target_fps)
	var crf = str(51 - int(_current_quality / 2.0))  # Convert quality 1-100 to CRF 51-1
	var args = [
		"-y",  # Overwrite output
		"-framerate", fps_str,
		"-i", temp_dir.path_join("frame_%06d.png"),
		"-c:v", "libx264",
		"-preset", "medium",
		"-crf", crf,
		"-pix_fmt", "yuv420p",
		"-movflags", "+faststart",
		output_path
	]
	
	print("[RecordingManager] Running FFmpeg: ", ffmpeg_path, " ", " ".join(args))
	
	var output = []
	var exit_code = OS.execute(ffmpeg_path, args, output, true)
	_cleanup_temp_dir(temp_dir)
	
	if exit_code == 0:
		print("[RecordingManager] Video encoded successfully: ", output_path)
		return true
	else:
		push_error("FFmpeg encoding failed with exit code: ", exit_code, " output: ", output)
		return false

func _find_ffmpeg() -> String:
	var possible_paths = [
		"ffmpeg",
		"ffmpeg.exe",
		"C:/ffmpeg/bin/ffmpeg.exe",
		"/usr/bin/ffmpeg",
		"/usr/local/bin/ffmpeg",
		"/opt/homebrew/bin/ffmpeg"
	]
	
	for path in possible_paths:
		var output = []
		var err = OS.execute(path, ["-version"], output, false)
		if err == 0:
			return path
	
	return ""

func _save_image_sequence(date_str: String, platform_name: String) -> String:
	var seq_dir = _output_path.path_join("seq_%s_%s" % [platform_name, date_str])
	DirAccess.make_dir_recursive_absolute(seq_dir)
	
	for i in range(_frame_queue.size()):
		var frame = _frame_queue[i]
		var frame_path = seq_dir.path_join("frame_%06d.png" % i)
		frame.save_png(frame_path)
	
	print("[RecordingManager] Saved image sequence to: ", seq_dir)
	return seq_dir

func _cleanup_temp_dir(path: String):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(path)

func get_platform_preset_info(platform: int) -> Dictionary:
	match platform:
		0: # YOUTUBE
			return {
				"name": "YouTube",
				"resolution": Vector2i(1920, 1080),
				"aspect": "16:9",
				"recommended_fps": 60,
				"max_duration": 43200,  # 12 hours
				"description": "Standard YouTube video format"
			}
		1: # INSTAGRAM_FEED
			return {
				"name": "Instagram Feed",
				"resolution": Vector2i(1080, 1080),
				"aspect": "1:1",
				"recommended_fps": 30,
				"max_duration": 60,
				"description": "Instagram square feed posts"
			}
		2: # INSTAGRAM_STORY
			return {
				"name": "Instagram Story/Reels",
				"resolution": Vector2i(1080, 1920),
				"aspect": "9:16",
				"recommended_fps": 30,
				"max_duration": 90,
				"description": "Instagram Stories and Reels (vertical)"
			}
		3: # TIKTOK
			return {
				"name": "TikTok",
				"resolution": Vector2i(1080, 1920),
				"aspect": "9:16",
				"recommended_fps": 30,
				"max_duration": 180,
				"description": "TikTok vertical videos"
			}
		4: # CUSTOM
			return {
				"name": "Custom",
				"resolution": Vector2i(1920, 1080),
				"aspect": "Custom",
				"recommended_fps": 60,
				"max_duration": 0,
				"description": "Custom resolution and settings"
			}
	return {}

func _get_platform_name(platform: int) -> String:
	return get_platform_preset_info(platform).get("name", "Unknown")

func is_recording() -> bool:
	return _is_recording

func get_recording_time() -> float:
	if not _is_recording:
		return 0.0
	return (Time.get_ticks_msec() / 1000.0) - _start_time

func get_frame_count() -> int:
	return _frame_count

func get_queue_size() -> int:
	return _frame_queue.size()

func set_async_save(enabled: bool):
	_async_save = enabled

func get_supported_platforms() -> Array[Dictionary]:
	var platforms = []
	for i in range(5):
		platforms.append(get_platform_preset_info(i))
	return platforms
