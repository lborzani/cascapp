class_name ReviewPanel
extends Control

## Revisão da partida que acabou de terminar, por cima da tela da partida.
##
## Por cima, e não uma cena nova: fechar a revisão devolve o painel de resultado
## como estava — com a revanche ainda possível e o convite do oponente ainda de
## pé. Trocar de cena perderia a sala.
##
## O replay anda desde o primeiro quadro; a análise chega aos poucos numa thread
## e as marcas aparecem quando ela termina.

signal closed

const VERDICT_COLOR := {
	GameReview.Verdict.BEST: AppTheme.SUCCESS,
	GameReview.Verdict.GOOD: AppTheme.TEXT,
	GameReview.Verdict.INACCURACY: AppTheme.GOLD,
	GameReview.Verdict.MISTAKE: AppTheme.DANGER,
	GameReview.Verdict.BLUNDER: AppTheme.DANGER,
}

var _review := GameReview.new()
var _thread: Thread = null
var _history: Array = []
## Posição depois de cada meio-lance; `[0]` é a inicial.
var _states: Array[MatchState] = []
var _entries: Array = []
var _ply := 0

var _board := BoardView.new()
var _status := Label.new()
var _detail := Label.new()
var _moves := HFlowContainer.new()
var _next_mistake := Button.new()


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
	column.add_theme_constant_override("separation", 10)
	safe.add_child(column)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Revisão da partida"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Fechar", &"GhostButton", close))
	column.add_child(header)

	_board.ruleset = ChessRules.new()
	_board.size_flags_vertical = SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(0, 300)
	column.add_child(_board)

	for label in [_status, _detail]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	_status.theme_type_variation = &"Subtitle"
	_detail.theme_type_variation = &"Hint"

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	nav.add_child(_button("Anterior", &"GhostButton", func(): _show(_ply - 1)))
	nav.add_child(_button("Próximo", &"GhostButton", func(): _show(_ply + 1)))
	_next_mistake = _button("Próximo erro", &"PrimaryButton", _jump_to_mistake)
	_next_mistake.disabled = true
	nav.add_child(_next_mistake)
	column.add_child(nav)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 110)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_moves.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_moves)
	column.add_child(scroll)


## Chamado depois de entrar na árvore. `history` é o da partida, no formato do
## fio (`Move.to_dict`).
func open(history: Array, flipped: bool) -> void:
	_history = history.duplicate()
	_board.flipped = flipped
	var rules := ChessRules.new()
	var state := rules.initial_state()
	_states = [state.clone()]
	for data in _history:
		rules.apply_move(state, rules.move_from_uci(state, rules.uci(Move.from_dict(data))))
		_states.append(state.clone())
	_thread = Thread.new()
	_thread.start(_review.analyse.bind(_history))
	_fill_moves()
	_show(0)


func close() -> void:
	_stop()
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	_stop()


func _process(_delta: float) -> void:
	if _thread == null:
		return
	if _thread.is_alive():
		_status.text = "Analisando com o Stockfish… %d/%d" % [_review.progress, _history.size()]
		return
	_entries = _thread.wait_to_finish()
	_thread = null
	_next_mistake.disabled = _entries.is_empty()
	_fill_moves()
	_show(_ply)


func _stop() -> void:
	if _thread != null:
		_review.abandon()
		_thread.wait_to_finish()
		_thread = null


func _show(ply: int) -> void:
	_ply = clampi(ply, 0, _history.size())
	_board.state = _states[_ply]
	_board.last_move = PackedInt32Array(_history[_ply - 1]["p"]) if _ply > 0 else PackedInt32Array()
	_board.refresh()
	_status.remove_theme_color_override("font_color")
	for i in _moves.get_child_count():
		(_moves.get_child(i) as Button).button_pressed = i == _ply - 1

	if _thread != null:
		_detail.text = ""
		return
	if _entries.is_empty() and not _history.is_empty():
		_status.text = "Não foi possível analisar — Stockfish indisponível."
		_detail.text = ""
		return
	if _ply == 0 or _ply > _entries.size():
		_status.text = "Posição inicial" if _ply == 0 else ""
		_detail.text = "%d lances analisados." % _entries.size() if _ply == 0 else ""
		return

	var entry: Dictionary = _entries[_ply - 1]
	var verdict: int = entry["verdict"]
	_status.text = "%s — %s" % [_move_text(_ply - 1, entry), GameReview.LABEL[verdict]]
	_status.add_theme_color_override("font_color", VERDICT_COLOR[verdict])
	if entry["missed_mate"]:
		_detail.text = "Mate perdido! Havia %s." % entry["best_san"]
	elif verdict >= GameReview.Verdict.INACCURACY and entry["best_san"] != "":
		_detail.text = "O melhor era %s." % entry["best_san"]
	else:
		_detail.text = ""


## Um botão por meio-lance. Antes da análise eles já existem — o replay não
## espera o motor —, e são refeitos com as marcas quando ela chega.
func _fill_moves() -> void:
	for child in _moves.get_children():
		child.queue_free()
	var rules := ChessRules.new()
	for i in _history.size():
		var entry: Dictionary = _entries[i] if i < _entries.size() else {}
		var text := _move_text(i, entry) if not entry.is_empty() else "%s%s" % [
			_move_number(i), rules.notation(_states[i], rules.move_from_uci(_states[i], rules.uci(Move.from_dict(_history[i]))))
		]
		var chip := _button(text, &"ChipButton", _show.bind(i + 1))
		chip.toggle_mode = true
		if not entry.is_empty():
			var color: Color = AppTheme.DANGER if entry["missed_mate"] else VERDICT_COLOR[entry["verdict"]]
			chip.add_theme_color_override("font_color", color)
			chip.add_theme_color_override("font_pressed_color", color)
		_moves.add_child(chip)


func _jump_to_mistake() -> void:
	for step in range(1, _entries.size() + 1):
		var index := (_ply - 1 + step) % _entries.size()
		var entry: Dictionary = _entries[index]
		if entry["missed_mate"] or entry["verdict"] >= GameReview.Verdict.MISTAKE:
			_show(index + 1)
			return
	_detail.text = "Nenhum erro nesta partida."


static func _move_number(index: int) -> String:
	return "%d.%s" % [index / 2 + 1, "" if index % 2 == 0 else ".."]


static func _move_text(index: int, entry: Dictionary) -> String:
	var mark: String = "#?" if entry["missed_mate"] else GameReview.SYMBOL[entry["verdict"]]
	return "%s%s%s" % [_move_number(index), entry["san"], mark]


func _button(text: String, variation: StringName, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = SIZE_EXPAND_FILL if variation != &"ChipButton" else SIZE_SHRINK_BEGIN
	button.pressed.connect(action)
	return button
