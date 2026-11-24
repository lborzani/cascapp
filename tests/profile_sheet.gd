extends Control

## As molduras e as capas do perfil da loja, para conferir. As animadas saem em
## três instantes lado a lado (0, 0,4 e 0,8 s), que é o que um print consegue
## mostrar de um movimento.
##
##   godot --path . res://tests/profile_sheet.tscn
##
## Não roda com `--headless`. Salva em user://profile_sheet.png.

const TIMES := [0.0, 0.4, 0.8]
const CELL := Vector2(150, 110)


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CELL.x * 3 + 160, CELL.y * 13)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var canvas := Control.new()
	canvas.size = viewport.size
	viewport.add_child(canvas)
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.size = viewport.size
	canvas.add_child(background)

	var row := 0
	for id in Cosmetics.of_slot(Cosmetics.FRAME):
		var style := Cosmetics.frame_of({"frame": id})
		_caption(canvas, Cosmetics.name_of(id), row)
		for column in (TIMES.size() if Coaster.animated(style) else 1):
			var coaster := Coaster.new()
			coaster.position = Vector2(160 + column * CELL.x + 25, row * CELL.y + 5)
			coaster.size = Vector2(100, 100)
			coaster.player_name = "Eva"
			coaster.frame = style
			coaster.frame_time = TIMES[column]
			canvas.add_child(coaster)
			coaster.set_process(false)
		row += 1
	for id in Cosmetics.of_slot(Cosmetics.BANNER):
		var look := {"banner": id}
		_caption(canvas, Cosmetics.name_of(id), row)
		for column in (TIMES.size() if ProfileCover.animated(Cosmetics.item_of(look, Cosmetics.BANNER)) else 1):
			var cover := ProfileCover.new()
			cover.position = Vector2(160 + column * CELL.x + 5, row * CELL.y + 15)
			cover.size = Vector2(CELL.x - 10, CELL.y - 30)
			cover.look = look
			cover.time = TIMES[column] * 2.0
			canvas.add_child(cover)
			cover.set_process(false)
		row += 1
	for frame in 6:
		await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("user://profile_sheet.png")
	print("PRONTO ", ProjectSettings.globalize_path("user://profile_sheet.png"))
	get_tree().quit()


func _caption(canvas: Control, text: String, row: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(12, row * CELL.y + CELL.y * 0.4)
	label.add_theme_color_override("font_color", AppTheme.TEXT)
	canvas.add_child(label)
