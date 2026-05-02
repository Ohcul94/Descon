extends SceneTree

func _init():
	var root = get_root()
	# Intentar encontrar el MainHUD
	var hud = root.find_child("MainHUD", true, false)
	if hud:
		var skills = hud.get_node_or_null("Skills")
		if skills:
			print("[TREE] Children of Skills:")
			for c in skills.get_children():
				print("- ", c.name, " (", c.get_class(), ")")
		else:
			print("[TREE] Skills node not found in MainHUD")
	else:
		print("[TREE] MainHUD not found")
	quit()
