extends Node

## Os tacos da loja de perto, lado a lado: o de sempre e um de cada item
## (`Cosmetics`, encaixe `cue`). Para julgar o desenho, que na mesa quase todo
## fica para fora do pano.
##
##   godot --path . res://tests/cue_sheet.tscn
##
## Não roda com `--headless` (o 3D volta preto). Salva em user://cues.png.

const CUE_SCENE := preload("res://assets/pool/cue.glb")


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1400, 760)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("1f6b4a")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 35, 0)
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.66
	camera.position = Vector3(0.575, 1.0, 0.2)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	viewport.add_child(camera)
	var looks: Array = [{}]
	for id in Cosmetics.of_slot(Cosmetics.CUE):
		looks.append({"cue": id})
	for i in looks.size():
		var cue: Node3D = CUE_SCENE.instantiate()
		cue.position = Vector3(0, 0, i * 0.075)
		# Um pouco girado em volta do comprimento, para a luz mostrar o volume.
		cue.rotation_degrees = Vector3(-20, 0, 0)
		viewport.add_child(cue)
		PoolView.dress_cue(cue, looks[i])
	for frame in 8:
		await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("user://cues.png")
	print("PRONTO ", ProjectSettings.globalize_path("user://cues.png"))
	get_tree().quit()
