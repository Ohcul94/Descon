extends Marker2D

# DamageText.gd (Flying Combat Text v1.02)
# Muestra números de daño o burbujas de texto flotantes.

@onready var label = Label.new()
var velocity = Vector2(0, -350) # Salto rápido v1.10
var duration = 1.6 # Un poco más de tiempo de vida

func _ready():
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(label)
	
	# v1.11: Pop-out effect + Fade
	scale = Vector2(0.5, 0.5)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.2, 1.2), 0.15).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate:a", 0.0, 0.6).set_delay(duration - 0.6)
	
	create_tween().tween_callback(queue_free).set_delay(duration)

func setup(p_text: String, p_color: Color = Color.WHITE):
	label.text = p_text
	label.modulate = p_color

func _process(p_delta):
	position += velocity * p_delta
	velocity.y *= 0.92 # Frenado más pronunciado para efecto flotante
