extends SceneTree

## Quadros por segundo com a capa e a moldura dos pioneiros na tela: a capa em
## tela cheia (o perfil do amigo) e oito bolachas (uma mesa cheia). Sem vsync e
## sem teto, para o número medir o custo e não o monitor.
##
##   godot --path . --script res://tests/pioneer_bench.gd

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var stage := SubViewport.new()
	stage.size = Vector2i(1080, 1920)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var look := {"banner": "banner_pioneer", "frame": "frame_pioneer"}
	var only := OS.get_environment("BENCH")
	var cover := ProfileCover.new()
	cover.look = look
	cover.fade = true
	cover.size = Vector2(stage.size)
	if only != "frame" and only != "none":
		stage.add_child(cover)
	for i in (0 if only in ["cover", "none"] else 8):
		var coaster := Coaster.new()
		coaster.frame = Cosmetics.frame_of(look)
		coaster.position = Vector2(40 + (i % 4) * 250, 200 + (i / 4) * 250)
		coaster.size = Vector2(180, 180)
		stage.add_child(coaster)
	RenderingServer.viewport_set_measure_render_time(stage.get_viewport_rid(), true)
	await create_timer(1.0).timeout
	var cpu := 0.0
	var gpu := 0.0
	var script := 0.0
	var frames := 0
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 4000:
		await process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(stage.get_viewport_rid())
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(stage.get_viewport_rid())
		script += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		frames += 1
	print("FPS %.0f · script %.2f ms · render cpu %.2f ms · gpu %.2f ms" % [frames / 4.0, script / frames, cpu / frames, gpu / frames])
	quit()
