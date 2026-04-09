extends Marker2D

# DamageText.gd (Flying Combat Text v1.02)
# Muestra números de daño o burbujas de texto flotantes.

@onready var label = Label.new()
var velocity = Vector2(0, -60)
var duration = 1.0

func _ready():
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(label)
	
	create_tween().tween_property(self, "modulate:a", 0.0, duration).set_delay(duration * 0.5)
	create_tween().tween_callback(queue_free).set_delay(duration)

func setup(p_text: String, p_color: Color = Color.WHITE):
	label.text = p_text
	label.modulate = p_color

func _process(p_delta):
	position += velocity * p_delta
	velocity.y *= 0.95 # Frenado vertical suave
