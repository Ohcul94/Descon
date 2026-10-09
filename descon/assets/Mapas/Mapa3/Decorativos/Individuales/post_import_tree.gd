@tool
extends EditorScenePostImport

## Configura automáticamente la animación de viento del árbol en bucle (Loop) y Autoplay al importar
func _post_import(scene: Node) -> Object:
	var anim_player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
	if anim_player:
		var anim_list = anim_player.get_animation_list()
		for a in anim_list:
			var anim_name = str(a)
			if "RESET" not in anim_name:
				var anim = anim_player.get_animation(anim_name)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
				anim_player.autoplay = anim_name
				break
	return scene
