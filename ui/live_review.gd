class_name LiveReview
extends Node

## Avaliação ao vivo para quem assiste xadrez: a cada lance que chega, o
## veredito dele e a nota da posição, pelo mesmo Stockfish da revisão.
##
## Só o último lance é julgado. É o único que a tela mostra, e é o que deixa
## quem entra no meio da partida ver a nota em menos de um segundo, em vez de
## esperar o motor passar pelo histórico inteiro. Uma busca por vez, numa
## thread: a partida não espera o motor.

## Entrada da revisão (formato de `GameReview.analyse`) do último lance; vazia
## sem lance, sem motor ou até a busca dele terminar.
var entry := {}

## Onde o veredito vai: o selo na casa de destino do último lance.
var board: BoardView = null
## Quem está na frente, acima do tabuleiro; a cena a põe na coluna. Escondida
## até a primeira nota — e para sempre, sem motor.
var bar := EvalGraph.Bar.new()

var _thread: Thread = null
var _engine: Stockfish = null
## O motor não subiu ou morreu: não tenta de novo a cada lance.
var _no_engine := false
## Histórico mais novo que a partida mostrou.
var _history: Array = []
## O que a busca em andamento julga, e o histórico a que `entry` pertence. Um
## resultado de histórico que mudou no meio da busca é jogado fora.
var _asked: Array = []
var _judged: Array = []
## Nota da última posição vista, e o FEN dela. Lance a lance, a posição de
## antes do lance novo é a de depois do anterior, e a busca dela é poupada.
## Só a thread mexe nestes três.
var _seen := {}
var _seen_fen := ""


func _init() -> void:
	bar.visible = false


func follow(history: Array) -> void:
	if history == _history:
		return
	_history = history.duplicate()
	entry = {}
	_paint()
	_kick()


## O selo sai assim que chega lance novo — ele falaria do lance anterior, numa
## casa que pode nem ser mais a dele —, e a barra fica com a nota anterior até a
## nova chegar, para não piscar a cada lance.
func _paint() -> void:
	if _history.is_empty():
		bar.visible = false
	if not entry.is_empty():
		bar.white = GameReview.white_curve([entry])[1]
		bar.visible = true
	if board == null:
		return
	board.badge_square = Board.NO_SQUARE
	if not entry.is_empty():
		# Mate perdido é sempre erro grave, como na revisão.
		var verdict: int = entry["verdict"]
		if entry["missed_mate"]:
			verdict = maxi(verdict, GameReview.Verdict.BLUNDER)
		var path := PackedInt32Array(_judged[_judged.size() - 1]["p"])
		board.badge_square = path[path.size() - 1]
		board.badge_color = ReviewPanel.VERDICT_COLOR[verdict]
		board.badge_text = GameReview.SYMBOL[verdict]
	board.queue_redraw()


func _kick() -> void:
	if _thread != null or _no_engine or _history.is_empty() or _history == _judged:
		return
	_asked = _history
	_thread = Thread.new()
	_thread.start(_work.bind(_asked))


func _process(_delta: float) -> void:
	if _thread == null or _thread.is_alive():
		return
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	if result.is_empty() and (_engine == null or not _engine.running()):
		_no_engine = true
		return
	if _asked == _history:
		entry = result
		_judged = _asked
		_paint()
	_kick()


## Na thread. O motor sobe na primeira busca e fica para as seguintes.
func _work(history: Array) -> Dictionary:
	if _engine == null:
		_engine = Stockfish.new()
		if not _engine.start():
			_engine = null
			return {}
		_engine.set_strength(0)
	var rules := ChessRules.new()
	var state := rules.initial_state()
	for i in history.size() - 1:
		rules.apply_move(state, rules.move_from_uci(state, rules.uci(Move.from_dict(history[i]))))
	var last := rules.move_from_uci(state, rules.uci(Move.from_dict(history[history.size() - 1])))
	if last == null:
		return {}
	var fen := rules.fen(state)
	if fen != _seen_fen:
		_seen = GameReview.look(_engine, rules, state)
		_seen_fen = fen
	if _seen.is_empty():
		return {}
	var judged := GameReview.judge(_engine, rules, state, _seen, last)
	if judged.is_empty():
		_seen = {}
		_seen_fen = ""
		return {}
	_seen = judged[1]
	_seen_fen = rules.fen(state)
	return judged[0]


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if _engine != null:
		_engine.quit()
		_engine = null
