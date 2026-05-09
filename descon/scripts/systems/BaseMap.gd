extends Node2D
class_name BaseMap

# Script Base para Mapas Instanciados
# Permite definir propiedades específicas por cada nivel

@export var world_size: float = 4000.0
@export var zone_name: String = "SECTOR DESCONOCIDO"

# Referencia a la textura de fondo principal
@onready var map_background: TextureRect = $ParallaxBackground/MapWorldLayer/MapBackground

func _ready():
	# Ajustar automáticamente el fondo al tamaño del mundo si es necesario
	if is_instance_valid(map_background):
		# Efecto de fade-in para transición suave
		map_background.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(map_background, "modulate:a", 0.7, 1.5).set_trans(Tween.TRANS_SINE)

func setup_map():
	# Método para ejecutar lógica específica al cargar el mapa
	pass
