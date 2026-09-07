# e:/Descon/descon/scripts/skills/Skill_Provocacion.gd
extends Resource
class_name SkillProvocacion

@export var id: String = "SK-TAUNT-01"
@export var skill_name: String = "PROVOCACION"
@export var type: String = "Defensa"
@export var cd: float = 15.0 # Cooldown en segundos
@export var range: float = 450.0 # Rango en píxeles
@export var radius: float = 220.0 # Radio del área de efecto en píxeles
@export var taunt_duration: float = 4.0 # Duración de la provocación en segundos

# Puedes añadir más propiedades si son necesarias para el cliente,
# como el path al icono, descripción, etc.
@export var icon_path: String = "res://assets/icons/skills/taunt_icon.png" # Placeholder
@export var description: String = "Fuerza a los enemigos cercanos a atacarte durante un tiempo."