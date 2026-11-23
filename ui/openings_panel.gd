class_name OpeningsPanel
extends Control

## O guia de aberturas (`Openings`): o nome, de quem ela é, os lances e a ideia.
## Cada uma abre o treino de dois jeitos — jogando a abertura, ou se defendendo
## dela —, sempre contra o bot, que segue a linha enquanto a partida estiver nela.
##
## Por cima da tela "Você", como o histórico: fechar devolve a tela como estava.

signal closed


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)

	var safe := SafeAreaMargin.new()
	for side in ["left", "top", "right", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 16)
	safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	safe.add_child(column)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Aberturas"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Fechar"
	close_button.theme_type_variation = &"GhostButton"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(rows)
	column.add_child(scroll)
	for line: Dictionary in Openings.LINES:
		rows.add_child(_row(line))


## É o que o voltar do sistema chama.
func close() -> void:
	closed.emit()
	queue_free()


func _row(line: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS, AppTheme.LINE_SOFT, 1))
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 4)
	card.add_child(texts)

	var white := int(line["side"]) == Board.Side.WHITE
	for pair in [
		[str(line["name"]), &"", AppTheme.TEXT],
		["Das brancas" if white else "Das pretas", &"Caption", AppTheme.TEXT_DIM],
		[Openings.san(Openings.moves_of(line)), &"Hint", AppTheme.TEXT],
		[str(line["idea"]), &"Hint", AppTheme.TEXT_DIM],
	]:
		var label := Label.new()
		label.text = pair[0]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if pair[1] != &"":
			label.theme_type_variation = pair[1]
		else:
			label.add_theme_font_override("font", AppTheme.font(800))
			label.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
		label.add_theme_color_override("font_color", pair[2])
		texts.add_child(label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	texts.add_child(buttons)
	var side := int(line["side"])
	for spec in [["Treinar a abertura", &"PrimaryButton", side], ["Treinar a defesa", &"GhostButton", Board.opponent(side)]]:
		var button := Button.new()
		button.text = spec[0]
		button.theme_type_variation = spec[1]
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(start.bind(line, spec[2]))
		buttons.add_child(button)
	return card


## O treino contra o bot com `line` a seguir, eu de `side`.
func start(line: Dictionary, side: int) -> void:
	Sound.play(Sound.Cue.TAP)
	Game.training_bot = true
	Game.bot_side = Board.opponent(side)
	Game.start_training(Game.CHESS)
	Game.training_line = Openings.moves_of(line)
	get_tree().change_scene_to_file(Game.match_scene())
