extends Node

# AudioManager.gd (Sound Control v1.10 - SFX 2D con atenuación)
# Gestiona música y efectos de sonido.
# v1.10: + SFX por path (assets/Sonidos/Habilidades/, assets/Sonidos/Mecanicas/) con volumen + maxDist + soporte bus SFX
#        Hybrid: sonido por librería (mechanicsLib) y override por instancia. Skills: skillsData.sound
#        2D posicional: atenuación lineal según distancia al jugador (maxDist).
# v1.05: Música por zona (bucle MP3/OGG/WAV) configurable desde AdminDash > Cartografía

var _sfx_players = []
var _music_player: AudioStreamPlayer = null
var _current_music_path: String = ""
var _current_music_zone: String = ""
var _current_music_volume_percent: float = 100.0

# cache de streams por path {path: AudioStream}
var _sfx_cache: Dictionary = {}
var _sfx_cooldown: Dictionary = {} # anti-spam {path: next_allowed_msec}

const SFX_SPAM_MS: int = 80

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_count() == 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(0, "Master")
	# Crear buses SFX/UI si no existen (default_bus_layout ya los trae, pero por seguridad)
	_ensure_bus("SFX")
	_ensure_bus("UI")

	# Pre-pools de reproductores de audio (SFX en bus SFX)
	for i in range(24):
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Music"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)

func _ensure_bus(bus_name: String):
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus_name), "Master")

# Compat: firma antigua play_sfx(stream, vol) sigue funcionando
func play_sfx(p_stream: Variant, p_vol: float = 0.0):
	if typeof(p_stream) == TYPE_STRING:
		# Nuevo: play_sfx("res://assets/Sonidos/xxx.ogg")
		play_sfx_path(String(p_stream), Vector2.INF, p_vol)
		return
	if not p_stream or not (p_stream is AudioStream): return
	for p in _sfx_players:
		if not p.playing:
			p.stream = p_stream
			p.volume_db = p_vol + _get_sfx_volume_offset()
			p.bus = "SFX"
			p.play()
			return

func play_sfx_path(path: String, pos: Variant = Vector2.INF, extra_vol_db: float = 0.0, max_dist: float = 1200.0, bus: String = "SFX") -> bool:
	if path.is_empty(): return false
	# anti-spam
	var now = Time.get_ticks_msec()
	if _sfx_cooldown.has(path) and now < _sfx_cooldown[path]:
		return false
	_sfx_cooldown[path] = now + SFX_SPAM_MS
	# mute/volumen
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and sm.get("sfx_muted") and sm.sfx_muted:
		return false
	var sfx_user_vol: float = 100.0
	if sm and "sfx_volume" in sm:
		sfx_user_vol = float(sm.sfx_volume)
	if sfx_user_vol <= 0.0:
		return false

	var stream: AudioStream = _load_sfx(path)
	if stream == null:
		return false
	# atenuación por distancia si hay posición
	var atten_db: float = 0.0
	if pos is Vector2 and pos != Vector2.INF:
		var listener = _get_listener_pos()
		if listener != Vector2.INF:
			var dist = listener.distance_to(pos)
			if dist > max_dist:
				return false
			# caida lineal: 0db a 0 distancia, -18db a maxDist
			atten_db = -18.0 * (dist / max_dist)
	# volumen combinado: usuario + extra + atenuación
	var user_db = linear_to_db(clamp(sfx_user_vol / 100.0, 0.001, 1.0)) if sfx_user_vol < 100.0 else 0.0
	var final_db = user_db + extra_vol_db + atten_db
	# clamp para no silenciar totalmente por error de conversión
	final_db = clamp(final_db, -40.0, 6.0)

	for p in _sfx_players:
		if not p.playing:
			# reasignar stream para forzar recarga si cambia
			p.stream = stream
			p.volume_db = final_db
			p.bus = bus
			p.play()
			return true
	# si todos ocupados, robar el primero (menos notorio que perder el sonido)
	var p0 = _sfx_players[0]
	p0.stream = stream
	p0.volume_db = final_db
	p0.bus = bus
	p0.play()
	return true

func _load_sfx(path: String) -> AudioStream:
	if _sfx_cache.has(path):
		return _sfx_cache[path]
	if not ResourceLoader.exists(path):
		push_warning("[AUDIO] SFX no existe: " + path)
		return null
	var s = load(path)
	if s == null:
		push_warning("[AUDIO] No se pudo cargar SFX: " + path)
		return null
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif s is AudioStreamOggVorbis:
		s.loop = false
	elif s is AudioStreamMP3:
		s.loop = false
	_sfx_cache[path] = s
	return s

func _get_listener_pos() -> Vector2:
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		return player.global_position
	var cam = get_tree().get_first_node_in_group("map")
	if is_instance_valid(cam) and "player" in cam and is_instance_valid(cam.player):
		return cam.player.global_position
	return Vector2.INF

func _get_sfx_volume_offset() -> float:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null or not ("sfx_volume" in sm): return 0.0
	if sm.sfx_muted: return -80.0
	var v = clamp(float(sm.sfx_volume), 0.0, 100.0)
	if v <= 0.0: return -80.0
	if v >= 100.0: return 0.0
	return linear_to_db(v / 100.0)

func stop_all_sfx():
	for p in _sfx_players:
		p.stop()

# ─── Helpers de alto nivel ────────────────────────────────────────────────
func play_skill_sound(skill_name: String, pos: Variant = Vector2.INF):
	if skill_name.is_empty(): return
	var data = null
	if GameConstants and "SKILLS_DATA" in GameConstants:
		data = GameConstants.SKILLS_DATA.get(skill_name, null)
	if data == null: return
	var path = String(data.get("sound", ""))
	if path.is_empty(): return
	var vol = float(data.get("soundVolumeDb", data.get("soundVolume", 0.0)))
	var maxd = float(data.get("soundMaxDist", 1400.0))
	play_sfx_path(path, pos, vol, maxd, "SFX")

func play_mechanic_sound(mech_type: String, mech_instance: Variant = null, pos: Variant = Vector2.INF):
	# Hybrid: si la instancia trae soundOverride/sound no vacío, usa eso; si no, usa lib
	var path: String = ""
	var vol: float = 0.0
	var maxd: float = 1200.0
	var lib_sound: String = ""
	var lib_vol: float = 0.0
	var lib_maxd: float = 1200.0
	# buscar en libs
	var mech_lib = null
	if GameConstants:
		if "MECHANICS_LIB" in GameConstants and mech_type in GameConstants.MECHANICS_LIB:
			mech_lib = GameConstants.MECHANICS_LIB[mech_type]
		elif "DEFENSE_LIB" in GameConstants and mech_type in GameConstants.DEFENSE_LIB:
			mech_lib = GameConstants.DEFENSE_LIB[mech_type]
		elif "MOVEMENT_LIB" in GameConstants and mech_type in GameConstants.MOVEMENT_LIB:
			mech_lib = GameConstants.MOVEMENT_LIB[mech_type]
	if mech_lib:
		lib_sound = String(mech_lib.get("sound", ""))
		lib_vol = float(mech_lib.get("soundVolumeDb", mech_lib.get("soundVolume", 0.0)))
		lib_maxd = float(mech_lib.get("soundMaxDist", 1200.0))
	# override por instancia (hybrid)
	if mech_instance is Dictionary:
		var inst_sound = String(mech_instance.get("sound", mech_instance.get("soundOverride", "")))
		if not inst_sound.is_empty():
			path = inst_sound
			vol = float(mech_instance.get("soundVolumeDb", mech_instance.get("soundVolume", lib_vol)))
			maxd = float(mech_instance.get("soundMaxDist", lib_maxd))
		else:
			path = lib_sound
			vol = lib_vol
			maxd = lib_maxd
	else:
		path = lib_sound
		vol = lib_vol
		maxd = lib_maxd
	if path.is_empty(): return
	play_sfx_path(path, pos, vol, maxd, "SFX")

# ─── MÚSICA DE LA ZONA ────────────────────────────────────────────────────
func play_zone_music(zone_id):
	var z_str = str(zone_id)
	var map_cfg = {}
	var maps_cfg = GameConstants.get("MAPS_CONFIG")
	if maps_cfg and maps_cfg.has(z_str):
		map_cfg = maps_cfg[z_str]
	var music_cfg = map_cfg.get("music", {})
	var path = music_cfg.get("path", "")
	var enabled = music_cfg.get("enabled", true)
	var volume_percent = clamp(float(music_cfg.get("volumePercent", 60)), 0.0, 100.0)
	if not enabled or path.is_empty():
		stop_zone_music()
		return
	if path == _current_music_path and _music_player.playing:
		apply_settings()
		return
	var stream = load(path)
	if stream == null:
		push_warning("[AUDIO] No se pudo cargar la música: " + path)
		stop_zone_music()
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamMP3:
		stream.loop = true
	_music_player.stream = stream
	_current_music_path = path
	_current_music_zone = z_str
	_current_music_volume_percent = volume_percent
	_music_player.play()
	apply_settings()
	print("[AUDIO] Música de zona '", z_str, "' → ", path, " (vol mapa ", volume_percent, "%)")

func stop_zone_music():
	if _music_player and _music_player.playing:
		_music_player.stop()
	_current_music_path = ""
	_current_music_zone = ""

func apply_settings():
	if not is_instance_valid(_music_player): return
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null: return
	var user_volume = sm.music_volume if not sm.music_muted else 0.0
	var combined = (user_volume * _current_music_volume_percent) / 100.0
	combined = clamp(float(combined), 0.0, 100.0)
	if combined <= 0.0:
		_music_player.volume_db = -80.0
	else:
		_music_player.volume_db = linear_to_db(combined / 100.0)

func apply_sfx_settings():
	# El volumen SFX se aplica en cada play_sfx_path; nada que hacer en reproductores activos
	pass
