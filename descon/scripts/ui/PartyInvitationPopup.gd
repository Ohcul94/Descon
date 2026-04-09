extends PanelContainer

# PartyInvitationPopup.gd (Notificación v1.50)
# Muestra invitación entrante y permite aceptar/rechazar.

@onready var text_label = $VBox/Text
@onready var accept_btn = $VBox/HBox/Accept
@onready var reject_btn = $VBox/HBox/Reject

var current_inviter_id = ""

func _ready():
	visible = false
	if PartyManager:
		PartyManager.invitation_received.connect(_on_invitation)
	
	if accept_btn: accept_btn.pressed.connect(_on_accept)
	if reject_btn: reject_btn.pressed.connect(_on_reject)

func _on_invitation(from_name: String, from_id: String):
	current_inviter_id = from_id
	if text_label:
		text_label.text = from_name + " te ha inviado a su escuadrón."
	visible = true

func _on_accept():
	PartyManager.accept_invitation(current_inviter_id)
	visible = false

func _on_reject():
	visible = false
