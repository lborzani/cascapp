extends Node

## As bolas de boliche da loja de perto, lado a lado, com o material de verdade
## (`BowlingLane.tint_ball`) e a luz da pista: a padrão, as seis texturas e as
## quatro especiais (cromada, neon, cristal e lava).
##
##   godot --path . res://tests/ball_sheet.tscn
##
## Não roda com `--headless` (o 3D volta preto). Salva em user://balls.png.


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1500, 640)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	# O mesmo ambiente do `BowlingView`, que é o que o metal e o vidro têm em volta.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = AppTheme.COASTER
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.70, 0.68, 0.80)
	environment.ambient_light_energy = 0.45
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var hall := DirectionalLight3D.new()
	hall.rotation_degrees = Vector3(-60.0, 10.0, 0.0)
	hall.light_energy = 0.9
	hall.light_color = Color(1.0, 0.96, 0.9)
	viewport.add_child(hall)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.62
	camera.position = Vector3(0.0, 0.0, 1.0)
	viewport.add_child(camera)

	var ids: Array = [""]
	ids.append_array(Cosmetics.of_slot(Cosmetics.BALL))
	var columns := 6
	for i in ids.size():
		var ball: Node3D = BowlingLane.BALL_SCENE.instantiate()
		var row := i / columns
		ball.position = Vector3((i % columns - (columns - 1) * 0.5) * 0.25, 0.13 - row * 0.26, 0.0)
		ball.rotation_degrees = Vector3(25, -30 + i * 17, 0)
		viewport.add_child(ball)
		var skin: Texture2D = null if ids[i] == "" else Cosmetics.ball_texture({"ball": ids[i]})
		BowlingLane.tint_ball(ball, Color("e05555") if skin == null else Color.WHITE, skin)
	for frame in 8:
		await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("user://balls.png")
	print("PRONTO ", ProjectSettings.globalize_path("user://balls.png"))
	get_tree().quit()
