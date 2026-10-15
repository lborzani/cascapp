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
## O par de rótulos vai num cartão tingido pela nota do lance: a mensagem é o
## que a revisão tem a dizer, e em cinza pequeno ela sumia embaixo do tabuleiro.
var _message := PanelContainer.new()
var _moves := HFlowContainer.new()
var _next_mistake := Button.new()
var _retry := Button.new()
var _nav := HBoxContainer.new()
var _scroll := ScrollContainer.new()
var _graph := EvalGraph.new()
var _bar := EvalGraph.Bar.new()
## Vitória esperada das brancas por posição; vazia até a análise chegar.
var _curve: Array = []

## Desafio "encontre o mate": índice da entrada em jogo, -1 fora dele.
const HINT_AFTER := 3
var _puzzle := -1
var _puzzle_state: MatchState = null
var _pick := Board.NO_SQUARE
var _misses := 0
var _solved := false
## Mate perdido pede o mate de volta; erro grave pede só um lance que segure.
var _mate_puzzle := false
var _tried: Move = null
var _view_flipped := false
## A conferência do lance roda numa thread, com um Stockfish só do desafio — o
## da análise já foi encerrado quando ela terminou.
var _checker: Thread = null
var _puzzle_engine: Stockfish = null


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
	_board.square_tapped.connect(_on_tap)
	column.add_child(_board)

	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 4)
	for label in [_status, _detail]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(label)
	_status.add_theme_font_override("font", AppTheme.font(800))
	_status.add_theme_font_size_override("font_size", AppTheme.SIZE_DISPLAY_M)
	_detail.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	_detail.add_theme_color_override("font_color", AppTheme.TEXT)
	_message.add_child(texts)
	column.add_child(_message)
	_tone(AppTheme.TEXT_DIM)

	_retry = _button("Tentar de novo", &"PrimaryButton", _toggle_puzzle)
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
	if _checker != null and not _checker.is_alive():
		var solved: bool = _checker.wait_to_finish()
		_checker = null
		_judged(solved)
	if _thread == null:
		return
	if _thread.is_alive():
		_status.text = "Analisando com o Stockfish… %d/%d" % [_review.progress, _history.size()]
		return
	var entries: Array = _thread.wait_to_finish()
	_thread = null
	_analysed(entries)


## A análise chegou: marcas nos chips, gráfico e barra.
func _analysed(entries: Array) -> void:
	_entries = entries
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
	if _checker != null:
		_checker.wait_to_finish()
		_checker = null
	if _puzzle_engine != null:
		_puzzle_engine.quit()
		_puzzle_engine = null


func _show(ply: int) -> void:
	_ply = clampi(ply, 0, _history.size())
	_board.state = _states[_ply]
	_board.last_move = PackedInt32Array(_history[_ply - 1]["p"]) if _ply > 0 else PackedInt32Array()
	_board.refresh()
	_tone(AppTheme.TEXT_DIM)
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
		_status.text = "Não foi possível analisar — Stockfish indisponível."
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
	_tone(AppTheme.DANGER if entry["missed_mate"] else VERDICT_COLOR[verdict])
	if entry["missed_mate"]:
		_detail.text = "Havia %s." % entry["best_san"]
	elif verdict >= GameReview.Verdict.INACCURACY and entry["best_san"] != "":
		_detail.text = "O melhor era %s." % entry["best_san"]
	else:
		_detail.text = ""
	_retry.visible = entry["missed_mate"] or verdict == GameReview.Verdict.BLUNDER


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


# --- desafio: encontre o mate ---------------------------------------------------


func _toggle_puzzle() -> void:
	if _puzzle >= 0:
		_end_puzzle()
	else:
		_start_puzzle(_ply - 1)


## A posição de antes do lance que deixou o mate passar, com o tabuleiro virado
## para quem joga — no mesmo aparelho, o mate perdido pode ser das pretas.
func _start_puzzle(index: int) -> void:
	_puzzle = index
	_misses = 0
	_solved = false
	_pick = Board.NO_SQUARE
	_puzzle_state = _states[index].clone()
	_mate_puzzle = _entries[index]["missed_mate"]
	_view_flipped = _board.flipped
	_board.flipped = _puzzle_state.side_to_move == Board.Side.BLACK
	_nav.visible = false
	_scroll.visible = false
	# A barra e o gráfico entregariam a resposta: a curva cai logo depois do lance.
	_graph.visible = false
	_bar.visible = false
	_retry.text = "Desistir"
	_tone(AppTheme.TEXT_DIM)
	_status.text = "%s Jogam as %s." % [
		"Encontre o mate!" if _mate_puzzle else "Ache um lance melhor!",
		"brancas" if _puzzle_state.side_to_move == Board.Side.WHITE else "pretas",
	]
	_detail.text = "Toque na peça e depois na casa."
	_tone(AppTheme.ACCENT)
	_draw_puzzle(PackedInt32Array())


func _end_puzzle() -> void:
	if _checker != null:
		_checker.wait_to_finish()
		_checker = null
	_puzzle = -1
	_pick = Board.NO_SQUARE
	_board.flipped = _view_flipped
	_board.selection = PackedInt32Array()
	_board.targets = PackedInt32Array()
	_board.capture_targets = PackedInt32Array()
	_nav.visible = true
	_scroll.visible = true
	_graph.visible = not _curve.is_empty()
	_retry.text = "Tentar de novo"
	_show(_ply)


func _on_tap(square: int) -> void:
	if _puzzle < 0 or _solved or _checker != null:
		return
	if _pick != Board.NO_SQUARE:
		var chosen := _move_to(square)
		if chosen != null:
			_try(chosen)
			return
	_pick = square if not _moves_from(square).is_empty() else Board.NO_SQUARE
	_draw_puzzle(PackedInt32Array())


func _moves_from(square: int) -> Array[Move]:
	var out: Array[Move] = []
	for move in ChessRules.new().generate_moves(_puzzle_state):
		if move.from_square() == square:
			out.append(move)
	return out


func _move_to(square: int) -> Move:
	var found: Move = null
	for move in _moves_from(_pick):
		if move.to_square() != square:
			continue
		# ponytail: promoção vira dama; sub-promoção que dá mate fica de fora.
		if found == null or move.promotion == Board.Kind.QUEEN:
			found = move
	return found


func _draw_puzzle(last: PackedInt32Array) -> void:
	_board.state = _puzzle_state
	_board.last_move = last
	_board.selection = PackedInt32Array([_pick]) if _pick != Board.NO_SQUARE else PackedInt32Array()
	var targets := PackedInt32Array()
	var captures := PackedInt32Array()
	for move in _moves_from(_pick):
		if move.is_capture():
			captures.append(move.to_square())
		else:
			targets.append(move.to_square())
	_board.targets = targets
	_board.capture_targets = captures
	_board.refresh()


## Mostra o lance na hora e confere em segundo plano: subir o motor e olhar a
## posição leva até meio segundo, e o tabuleiro parado nesse tempo pareceria
## que o toque não pegou.
func _try(move: Move) -> void:
	_tried = move
	var after := _puzzle_state.clone()
	ChessRules.new().apply_move(after, move)
	_board.state = after
	_board.last_move = move.path
	_board.selection = PackedInt32Array()
	_board.targets = PackedInt32Array()
	_board.capture_targets = PackedInt32Array()
	_board.refresh()
	_status.text = "Conferindo…"
	_detail.text = ""
	_checker = Thread.new()
	var entry: Dictionary = _entries[_puzzle]
	_checker.start(_judge.bind(after, ChessRules.new().uci(move), str(entry["best"]), float(entry["score"])))


## Na thread. Sem motor, só o lance que ele tinha apontado vale. `before` é a
## vitória esperada de quem joga na posição do desafio.
func _judge(after: MatchState, played: String, best: String, before: float) -> bool:
	var rules := ChessRules.new()
	if _puzzle_engine == null:
		_puzzle_engine = Stockfish.new()
		if not _puzzle_engine.start():
			_puzzle_engine = null
	if _puzzle_engine == null:
		return played == best
	var seen := GameReview.look(_puzzle_engine, rules, after)
	if seen.is_empty():
		return played == best
	if _mate_puzzle:
		return GameReview.keeps_mate(seen["mate"], seen["mated"])
	return GameReview.holds(before, 100.0 - float(seen["score"]))


func _judged(solved: bool) -> void:
	var san := ChessRules.new().notation(_puzzle_state, _tried)
	if solved:
		_solved = true
		var praise := "segura a posição."
		if san.ends_with("#"):
			praise = "é xeque-mate."
		elif _mate_puzzle:
			praise = "mantém o mate."
		elif san == _entries[_puzzle]["best_san"]:
			praise = "era o melhor lance."
		_status.text = "Isso! %s %s" % [san, praise]
		_tone(AppTheme.SUCCESS)
		_detail.text = ""
		_retry.text = "Voltar à revisão"
		return
	_misses += 1
	_pick = Board.NO_SQUARE
	_status.text = "%s %s Tente de novo." % [
		san, "deixa o mate escapar." if _mate_puzzle else "ainda perde muito."
	]
	_tone(AppTheme.DANGER)
	_detail.text = ""
	if _misses >= HINT_AFTER:
		var best := ChessRules.new().move_from_uci(_puzzle_state, str(_entries[_puzzle]["best"]))
		if best != null:
			_pick = best.from_square()
			_detail.text = "Dica: a peça destacada %s." % ("dá o mate" if _mate_puzzle else "faz o melhor lance")
	_draw_puzzle(PackedInt32Array())


## Cartão e título na cor da mensagem; o neutro (`TEXT_DIM`) mantém o título
## em texto claro sobre um cartão discreto.
func _tone(color: Color) -> void:
	var neutral := color == AppTheme.TEXT_DIM
	_message.add_theme_stylebox_override("panel", AppTheme.box(
		AppTheme.SURFACE if neutral else Color(color, 0.16), AppTheme.RADIUS,
		AppTheme.LINE_SOFT if neutral else color, 2
	))
	_status.add_theme_color_override("font_color", AppTheme.TEXT if neutral else color)


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
