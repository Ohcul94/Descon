extends Node

# AudioManager.gd (Sound Control v1.02)
# Gestiona música y efectos de sonido.

var _sfx_players = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Pre-pools de reproductores de audio
	for i in range(16):
		var p = AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)

func play_sfx(p_stream: Variant, p_vol: float = 0.0):
	# Si p_stream es un String (como "laser"), ignoramos por ahora (v1.51)
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
