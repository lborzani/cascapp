extends Node

## Ferramenta de rascunho do redesenho: exporta o que é **protegido** (cartas do
## Uno, tabuleiros) sem o fundo atual, para os conceitos novos poderem pôr as
## mesmas cartas sobre outro chão.
##
##   godot --path . --resolution 1536x864 res://tests/redesign_assets.tscn
##
## Salva em user://redesign/.

const OUT := "user://redesign"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if "metropole" in OS.get_cmdline_user_args():
		await _metropole()
		get_tree().quit()
		return
	_bounds("user://shots/06_capturas.png", Rect2i(0, 120, 432, 440), "xadrez")
	_bounds("user://shots/17_ludo.png", Rect2i(400, 0, 760, 720), "ludo")
	_bounds("user://shots/16_naval.png", Rect2i(60, 90, 310, 300), "naval_alvo")
	_bounds("user://shots/16_naval.png", Rect2i(130, 415, 170, 160), "naval_seu")
	_bounds("user://shots/22_sinuca.png", Rect2i(275, 5, 1285, 710), "sinuca")
	_bounds("user://shots/21_bomberman.png", Rect2i(340, 5, 880, 710), "bomberman")
	await _uno_table()
	get_tree().quit()


## O tabuleiro 3D de Metrópole sem nenhum painel por cima, na proporção de um
## celular deitado. A posição é a vitrine da folha de Metrópole.
func _metropole() -> void:
	Game.start_hotseat(Game.MONOPOLY)
	Game.table_size = 4
	var root: Control = load("res://scenes/monopoly_match.tscn").instantiate()
	add_child(root)
	var sheet: Node = load("res://tests/monopoly_sheet.gd").new()
	var state: MatchState = sheet._showcase(4)
	sheet.free()
	state.meta[MonopolyRules.TURN] = 0
	state.meta[MonopolyRules.POS][0] = 19
	root._state = state
	root._refresh()
	var node: Node = root._board
	while node != root:
		var parent := node.get_parent()
		for sibling in parent.get_children():
			if sibling != node and sibling is CanvasItem:
				(sibling as CanvasItem).visible = false
		node = parent
	await get_tree().create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/metropole.png")
	print("metropole ok")


## O menor retângulo que contém tudo o que não é o fundo, dentro de `area`.
func _bounds(path: String, area: Rect2i, label: String) -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		printerr("sem ", path)
		return
	var ground := image.get_pixel(area.position.x + 2, area.position.y + 2)
	var low := Vector2i(area.end)
	var high := Vector2i(area.position)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var pixel := image.get_pixel(x, y)
			if absf(pixel.r - ground.r) + absf(pixel.g - ground.g) + absf(pixel.b - ground.b) > 0.06:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	print("%s bbox x=%d y=%d w=%d h=%d (imagem %dx%d)" % [
		label, low.x, low.y, high.x - low.x + 1, high.y - low.y + 1,
		image.get_width(), image.get_height()
	])


## A mesa do Uno sem a coluna de jogadores, sem o botão de passar e sem o fundo.
func _uno_table() -> void:
	get_viewport().transparent_bg = true
	Game.start_solo(Game.UNO)
	Game.table_size = 4
	Game.uno_sevens = true
	var scene := preload("res://scenes/uno_match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	var state: MatchState = scene._state
	state.meta[UnoRules.hand_key(0)] = PackedInt32Array([
		UnoRules.card(UnoRules.CardColor.RED, 7),
		UnoRules.card(UnoRules.CardColor.RED, UnoRules.DRAW_TWO),
		UnoRules.card(UnoRules.CardColor.YELLOW, 0),
		UnoRules.card(UnoRules.CardColor.GREEN, UnoRules.SKIP),
		UnoRules.card(UnoRules.CardColor.BLUE, 9),
		UnoRules.card(UnoRules.CardColor.BLUE, UnoRules.REVERSE),
		UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR),
	])
	state.meta[UnoRules.hand_key(2)] = PackedInt32Array([
		UnoRules.card(UnoRules.CardColor.GREEN, 4)
	])
	state.meta[UnoRules.PILE] = PackedInt32Array([UnoRules.card(UnoRules.CardColor.RED, 5)])
	state.meta[UnoRules.COLOR] = UnoRules.CardColor.RED
	state.meta[UnoRules.TURN] = 0
	scene.get_node("Background").visible = false
	scene.get_node("Margin/Row/Left").visible = false
	scene.get_node("Margin/Row/Right").visible = false
	scene._refresh()

	for _frame in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(OUT + "/uno_mesa.png")
	print("uno_mesa %dx%d, alfa no canto: %.2f" % [
		shot.get_width(), shot.get_height(), shot.get_pixel(2, 2).a
	])
