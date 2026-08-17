extends Node

# AudioManager.gd (Sound Control v1.05)
# Gestiona música y efectos de sonido.
# v1.05: Música por zona (bucle MP3/OGG/WAV) configurable desde AdminDash > Cartografía
#        + volumen combinado del jugador (Settings > Sonido) y del mapa.

var _sfx_players = []
var _music_player: AudioStreamPlayer = null
var _current_music_path: String = ""
var _current_music_zone: String = ""
var _current_music_volume_percent: float = 100.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Asegurar que el bus Master exista (por si no hay default_bus_layout.tres cargado)
	if AudioServer.get_bus_count() == 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(0, "Master")
	
	# Pre-pools de reproductores de audio
	for i in range(16):
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)
	
	# Reproductor dedicado para la música de la zona
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Master"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)

func play_sfx(p_stream: Variant, p_vol: float = 0.0):
	# Si p_stream es un String (como "laser"), ignoramos por ahora
	if typeof(p_stream) == TYPE_STRING: return
	
	if not p_stream or not (p_stream is AudioStream): return
	
	for p in _sfx_players:
		if not p.playing:
			p.stream = p_stream
			p.volume_db = p_vol
			p.play()
			return

func stop_all_sfx():
	for p in _sfx_players:
		p.stop()

# ─── MÚSICA DE LA ZONA ─────────────────────────────────────────────────────────
# Reproduce en bucle la música asignada al mapa en AdminDash (mapsConfig[zone].music).
# Si el mapa no tiene música (o está desactivada), detiene la música anterior.
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
	
	# Si ya estamos sonando la misma pista de la misma zona, solo reajustar volumen
	if path == _current_music_path and _music_player.playing:
		apply_settings()
		return
	
	var stream = load(path)
	if stream == null:
		push_warning("[AUDIO] No se pudo cargar la música: " + path)
		stop_zone_music()
		return
	
	# Forzar bucle según el tipo de stream (Godot 4)
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

# Ajustes del jugador (Settings > Sonido): mute y volumen de la música.
# El volumen final combina el del mapa (AdminDash) y el del jugador.
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
