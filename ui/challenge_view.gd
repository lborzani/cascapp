class_name ChallengeView
extends VBoxContainer

## O desafio "encontre o mate" / "ache um lance melhor": a posição de antes de
## um erro, o jogador tenta, o Stockfish confere. É da revisão e do treino.
##
## Vale qualquer lance que segure — ou, no mate, qualquer caminho que mantenha o
## mate —, não só o do motor. Três erros e a peça do melhor lance vira dica.
##
## O botão é "Desistir" até resolver, e `continue_label` depois. Tocar nele é
## o fim do desafio para quem abriu: `done` diz se resolveu e se foi limpo, de
## primeira — a régua do treino.

signal done(solved: bool, clean: bool)

const HINT_AFTER := 3

## O botão depois de resolver: "Voltar à revisão", "Próximo".
var continue_label := "Continuar"

var _board := BoardView.new()
var _message := MessageCard.new()
var _status: Label = _message.status
var _detail: Label = _message.detail
var _action: Button = null

var _state: MatchState = null
var _best := ""
var _best_san := ""
## Vitória esperada de quem joga na posição; a régua do "ache um lance melhor".
var _before := 50.0
## Mate perdido pede o mate de volta; erro pede só um lance que segure.
var _mate := false
var _pick := Board.NO_SQUARE
var _misses := 0
var _solved := false
var _tried: Move = null
## A conferência roda numa thread, com um Stockfish que vive enquanto o desafio
## estiver na tela — o treino passa de um cartão a outro sem subir outro motor.
var _checker: Thread = null
var _engine: Stockfish = null


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_board.ruleset = ChessRules.new()
	_board.size_flags_vertical = SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(0, 300)
	_board.square_tapped.connect(_on_tap)
	add_child(_board)
	add_child(_message)
	_action = Button.new()
	_action.theme_type_variation = &"PrimaryButton"
	_action.custom_minimum_size = Vector2(0, 44)
	_action.pressed.connect(_leave)
	add_child(_action)


func _process(_delta: float) -> void:
	if _checker != null and not _checker.is_alive():
		var solved: bool = _checker.wait_to_finish()
		_checker = null
		_judged(solved)


func _exit_tree() -> void:
	_wait()
	if _engine != null:
		_engine.quit()
		_engine = null


## `state` é a posição do desafio; o tabuleiro vira para quem joga — no mesmo
## aparelho, o erro pode ser das pretas.
func start(state: MatchState, best: String, best_san: String, before: float, mate: bool) -> void:
	_wait()
	_state = state.clone()
	_best = best
	_best_san = best_san
	_before = before
	_mate = mate
	_misses = 0
	_solved = false
	_pick = Board.NO_SQUARE
	_board.flipped = _state.side_to_move == Board.Side.BLACK
	_action.text = "Desistir"
	_status.text = "%s Jogam as %s." % [
		"Encontre o mate!" if _mate else "Ache um lance melhor!",
		"brancas" if _state.side_to_move == Board.Side.WHITE else "pretas",
	]
	_detail.text = "Toque na peça e depois na casa."
	_message.tone(AppTheme.ACCENT)
	_draw()


func _leave() -> void:
	_wait()
	done.emit(_solved, _solved and _misses == 0)


func _wait() -> void:
	if _checker != null:
		_checker.wait_to_finish()
		_checker = null


func _on_tap(square: int) -> void:
	if _state == null or _solved or _checker != null:
		return
	if _pick != Board.NO_SQUARE:
		var chosen := _move_to(square)
		if chosen != null:
			_try(chosen)
			return
	_pick = square if not _moves_from(square).is_empty() else Board.NO_SQUARE
	_draw()


func _moves_from(square: int) -> Array[Move]:
	var out: Array[Move] = []
	for move in ChessRules.new().generate_moves(_state):
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


func _draw() -> void:
	_board.state = _state
	_board.last_move = PackedInt32Array()
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
	var after := _state.clone()
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
	_checker.start(_judge.bind(after, ChessRules.new().uci(move)))


## Na thread. Sem motor, só o lance que ele tinha apontado vale.
func _judge(after: MatchState, played: String) -> bool:
	if _engine == null:
		_engine = Stockfish.new()
		if not _engine.start():
			_engine = null
	if _engine == null:
		return played == _best
	var seen := GameReview.look(_engine, ChessRules.new(), after)
	if seen.is_empty():
		return played == _best
	if _mate:
		return GameReview.keeps_mate(seen["mate"], seen["mated"])
	return GameReview.holds(_before, 100.0 - float(seen["score"]))


func _judged(solved: bool) -> void:
	var san := ChessRules.new().notation(_state, _tried)
	if solved:
		_solved = true
		var praise := "segura a posição."
		if san.ends_with("#"):
			praise = "é xeque-mate."
		elif _mate:
			praise = "mantém o mate."
		elif san == _best_san:
			praise = "era o melhor lance."
		_status.text = "Isso! %s %s" % [san, praise]
		_message.tone(AppTheme.SUCCESS)
		_detail.text = ""
		_action.text = continue_label
		return
	_misses += 1
	_pick = Board.NO_SQUARE
	_status.text = "%s %s Tente de novo." % [san, "deixa o mate escapar." if _mate else "ainda perde muito."]
	_message.tone(AppTheme.DANGER)
	_detail.text = ""
	if _misses >= HINT_AFTER:
		var best := ChessRules.new().move_from_uci(_state, _best)
		if best != null:
			_pick = best.from_square()
			_detail.text = "Dica: a peça destacada %s." % ("dá o mate" if _mate else "faz o melhor lance")
	_draw()
