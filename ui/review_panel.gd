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
## O registro do histórico (`Prefs.record_game`) de onde a partida veio; vazio
## quando ela não foi para o histórico, e aí nada vai para o treino.
var _game: Dictionary = {}
## Posição depois de cada meio-lance; `[0]` é a inicial.
var _states: Array[MatchState] = []
var _entries: Array = []
var _ply := 0

var _board := BoardView.new()
var _message := MessageCard.new()
var _status: Label = _message.status
var _detail: Label = _message.detail
var _moves := HFlowContainer.new()
var _next_mistake: Button = null
var _retry: Button = null
var _nav := HBoxContainer.new()
var _scroll := ScrollContainer.new()
var _graph := EvalGraph.new()
var _bar := EvalGraph.Bar.new()
## Vitória esperada das brancas por posição; vazia até a análise chegar.
var _curve: Array = []

## Desafio: índice da entrada em jogo, -1 fora dele. O desafio tem o próprio
## tabuleiro; enquanto ele está na tela, o replay some.
var _puzzle := -1
## Cor de quem jogou a partida; -1 no mesmo aparelho, onde os dois lados são
## de quem revisa. Os desafios saem só dos erros dessa cor: o do oponente
## abriria com a vez dele, e o jogador moveria as peças que não eram suas.
var _side := -1
var _challenge := ChallengeView.new()


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

	_bar.visible = false
	column.add_child(_bar)

	_board.ruleset = ChessRules.new()
	_board.size_flags_vertical = SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(0, 300)
	column.add_child(_board)
	column.add_child(_message)

	_challenge.visible = false
	_challenge.size_flags_vertical = SIZE_EXPAND_FILL
	_challenge.continue_label = "Voltar à revisão"
	_challenge.done.connect(func(_solved: bool, _clean: bool): _end_puzzle())
	column.add_child(_challenge)

	_retry = _button("Tentar de novo", &"PrimaryButton", func(): _start_puzzle(_ply - 1))
	_retry.visible = false
	column.add_child(_retry)

	_graph.visible = false
	_graph.seek.connect(_show)
	column.add_child(_graph)

	_nav.add_theme_constant_override("separation", 8)
	_nav.add_child(_button("Anterior", &"GhostButton", func(): _show(_ply - 1)))
	_nav.add_child(_button("Próximo", &"GhostButton", func(): _show(_ply + 1)))
	_next_mistake = _button("Próximo erro", &"PrimaryButton", _jump_to_mistake)
	_next_mistake.disabled = true
	_nav.add_child(_next_mistake)
	column.add_child(_nav)

	_scroll.custom_minimum_size = Vector2(0, 110)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_moves.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(_moves)
	column.add_child(_scroll)


## Chamado depois de entrar na árvore. `history` é o da partida, no formato do
## fio (`Move.to_dict`); `side` é a cor de quem jogou, ou -1 no mesmo aparelho;
## `game` é o registro dela no histórico, se houver.
func open(history: Array, side: int, game := {}) -> void:
	_history = history.duplicate()
	_side = side
	_game = game
	_board.flipped = side == Board.Side.BLACK
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
		_status.text = "Analisando a partida… %d/%d" % [_review.progress, _history.size()]
		return
	var entries: Array = _thread.wait_to_finish()
	_thread = null
	_analysed(entries)


## A análise chegou: marcas nos chips, gráfico e barra.
func _analysed(entries: Array) -> void:
	_entries = entries
	Training.collect(_game, _entries)
	_next_mistake.disabled = _entries.is_empty()
	_curve = GameReview.white_curve(_entries)
	var dots := {}
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		if entry["missed_mate"]:
			dots[i + 1] = AppTheme.DANGER
		elif entry["verdict"] >= GameReview.Verdict.INACCURACY:
			dots[i + 1] = VERDICT_COLOR[entry["verdict"]]
	_graph.curve = _curve
	_graph.dots = dots
	_graph.visible = not _curve.is_empty() and _puzzle < 0
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
	_message.tone(AppTheme.TEXT_DIM)
	_retry.visible = false
	for i in _moves.get_child_count():
		(_moves.get_child(i) as Button).button_pressed = i == _ply - 1
	_graph.cursor = _ply
	_bar.visible = _ply < _curve.size() and _puzzle < 0
	if _bar.visible:
		_bar.white = _curve[_ply]

	if _thread != null:
		_detail.text = ""
		return
	if _entries.is_empty() and not _history.is_empty():
		_status.text = "Não foi possível analisar a partida agora."
		_detail.text = ""
		return
	if _ply == 0 or _ply > _entries.size():
		_status.text = _accuracy_text() if _ply == 0 else ""
		_detail.text = "%d lances analisados. Toque num lance ou no gráfico." % _entries.size() if _ply == 0 else ""
		return

	var entry: Dictionary = _entries[_ply - 1]
	var verdict: int = entry["verdict"]
	var label: String = "Mate perdido" if entry["missed_mate"] else GameReview.LABEL[verdict]
	_status.text = "%s — %s" % [_move_text(_ply - 1, entry), label]
	_message.tone(AppTheme.DANGER if entry["missed_mate"] else VERDICT_COLOR[verdict])
	# O lance certo não é dito: quem errou descobre no desafio, que é o que
	# ensina. A revisão só aponta que havia coisa melhor.
	var slipped: bool = (
		(entry["missed_mate"] or verdict >= GameReview.Verdict.INACCURACY) and entry["best"] != ""
	)
	_retry.visible = slipped and (_side < 0 or entry["side"] == _side)
	var invite := " Toque em Tentar de novo para achar." if _retry.visible else ""
	if entry["missed_mate"]:
		_detail.text = "Havia um mate." + invite
	elif slipped:
		_detail.text = "Havia um lance melhor." + invite
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


# --- desafio ------------------------------------------------------------------


## A posição de antes do erro, no tabuleiro do desafio. O gráfico e a barra
## somem com o replay: a curva cai logo depois do lance e entregaria a resposta.
func _start_puzzle(index: int) -> void:
	_puzzle = index
	var entry: Dictionary = _entries[index]
	for part in [_board, _message, _retry, _nav, _scroll, _graph, _bar]:
		part.visible = false
	_challenge.visible = true
	_challenge.start(_states[index], str(entry["best"]), str(entry["best_san"]), float(entry["score"]), entry["missed_mate"])


func _end_puzzle() -> void:
	_puzzle = -1
	_challenge.visible = false
	for part in [_board, _message, _nav, _scroll]:
		part.visible = true
	_graph.visible = not _curve.is_empty()
	_show(_ply)


func _jump_to_mistake() -> void:
	for step in range(1, _entries.size() + 1):
		var index := (_ply - 1 + step) % _entries.size()
		var entry: Dictionary = _entries[index]
		if entry["missed_mate"] or entry["verdict"] >= GameReview.Verdict.MISTAKE:
			_show(index + 1)
			return
	_detail.text = "Nenhum erro nesta partida."


## "Precisão: brancas 87% · pretas 64%" — o resumo que abre a revisão.
func _accuracy_text() -> String:
	var parts := PackedStringArray()
	for pair in [[Board.Side.WHITE, "brancas"], [Board.Side.BLACK, "pretas"]]:
		var value := GameReview.accuracy(_entries, pair[0])
		if value >= 0.0:
			parts.append("%s %d%%" % [pair[1], roundi(value)])
	return "Precisão: " + " · ".join(parts)


static func _move_number(index: int) -> String:
	return "%d.%s" % [index / 2 + 1, "" if index % 2 == 0 else ".."]


static func _move_text(index: int, entry: Dictionary) -> String:
	# Mate perdido é sempre um erro, mesmo quando a partida continuava ganha.
	var verdict: int = entry["verdict"]
	if entry["missed_mate"]:
		verdict = maxi(verdict, GameReview.Verdict.BLUNDER)
	var mark: String = GameReview.SYMBOL[verdict]
	return "%s%s%s" % [_move_number(index), entry["san"], mark]


func _button(text: String, variation: StringName, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = SIZE_EXPAND_FILL if variation != &"ChipButton" else SIZE_SHRINK_BEGIN
	button.pressed.connect(action)
	return button
