class_name HistoryPanel
extends Control

## As partidas de xadrez que terminaram neste aparelho, mais recente primeiro.
## Cada uma abre a mesma revisão do fim de partida — análise, gráfico e
## desafios —, que é a razão de o histórico existir.
##
## Por cima da tela "Você", como a revisão fica por cima da partida: fechar
## devolve a tela como estava.

signal closed

var _review: ReviewPanel = null


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
	title.text = "Histórico de partidas"
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

	var games := Prefs.history()
	if games.is_empty():
		var empty := Label.new()
		empty.text = "Nenhuma partida de xadrez ainda. As que terminarem aparecem aqui, prontas para revisar."
		empty.theme_type_variation = &"Subtitle"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(empty)
	for game in games:
		rows.add_child(_row(game))


## Fecha a revisão aberta, ou o histórico. É o que o voltar do sistema chama.
func close() -> void:
	if is_instance_valid(_review):
		_review.close()
		return
	closed.emit()
	queue_free()


func _row(game: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS, AppTheme.LINE_SOFT, 1))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = SIZE_EXPAND_FILL
	var moves: Array = game.get("moves", [])
	var side := "brancas" if int(game.get("side", Board.Side.WHITE)) == Board.Side.WHITE else "pretas"
	for pair in [
		[str(game.get("title", "")), &"", AppTheme.TEXT],
		[str(game.get("against", "")), &"Hint", AppTheme.TEXT],
		["%s · de %s · %d lances" % [when(int(game.get("at", 0))), side, (moves.size() + 1) / 2], &"Caption", AppTheme.TEXT_DIM],
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
	line.add_child(texts)

	var open := Button.new()
	open.text = "Revisar"
	open.theme_type_variation = &"PrimaryButton"
	open.custom_minimum_size = Vector2(110, 44)
	open.size_flags_vertical = SIZE_SHRINK_CENTER
	# Partida gravada antes do campo `hotseat` abre com a cor gravada: brancas.
	var played := -1 if game.get("hotseat", false) else int(game.get("side", Board.Side.WHITE))
	open.pressed.connect(_open.bind(moves, played))
	line.add_child(open)
	return card


func _open(moves: Array, side: int) -> void:
	_review = ReviewPanel.new()
	add_child(_review)
	_review.open(moves, side)


## "14/10 às 17:32", na hora local do aparelho.
static func when(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var at := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%02d/%02d às %02d:%02d" % [at["day"], at["month"], at["hour"], at["minute"]]
