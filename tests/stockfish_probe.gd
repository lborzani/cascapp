extends SceneTree

## Conversa de verdade com o Stockfish: precisa do binário no PATH ou em
## `$STOCKFISH`. Fora do test_runner porque o resto da suíte não depende dele.
##
##   godot --headless --path . --script res://tests/stockfish_probe.gd

var _failures := 0


func _initialize() -> void:
	var missing := Stockfish.new()
	_check(not missing.start("/nao/existe/stockfish"), "binário inexistente: start() falso, sem travar")

	var engine := Stockfish.new()
	_check(engine.start(), "motor sobe (%s)" % Stockfish.binary())
	if engine.running():
		var rules := ChessRules.new()
		var state := rules.initial_state()
		state.squares = Board.empty_squares()
		state.set_piece(Board.square(6, 7), Board.piece(Board.Side.BLACK, Board.Kind.KING))
		for file in [5, 6, 7]:
			state.set_piece(Board.square(file, 6), Board.piece(Board.Side.BLACK, Board.Kind.PAWN))
		state.set_piece(Board.square(0, 0), Board.piece(Board.Side.WHITE, Board.Kind.ROOK))
		state.set_piece(Board.square(6, 0), Board.piece(Board.Side.WHITE, Board.Kind.KING))
		state.meta = {"castle": 0, "ep": Board.NO_SQUARE, "halfmove": 0}

		var seen := engine.search(rules.fen(state), 200)
		_check(seen.get("best") == "a1a8", "mate do corredor: a1a8 (veio %s)" % seen.get("best"))
		_check(seen.get("mate") == 1, "nota é mate em 1 (veio %s)" % seen.get("mate"))
		_check(rules.move_from_uci(state, str(seen.get("best"))) != null, "lance do motor é legal para ChessRules")

		engine.set_strength(1320)
		_check(engine.ready(), "aceita UCI_Elo")
		var opening := engine.search(rules.fen(rules.initial_state()), 100)
		_check(rules.move_from_uci(rules.initial_state(), str(opening.get("best"))) != null, "joga lance legal limitado")
		engine.quit()
		_check(not engine.running(), "quit encerra")

	_bot_game()
	_review()

	print("OK — stockfish." if _failures == 0 else "%d falha(s)." % _failures)
	quit(1 if _failures > 0 else 0)


## Fácil contra Difícil, 30 lances, pelo mesmo caminho da cena: `think` e
## `take_move` com o relógio do bot. O que se prova é o encanamento — lance legal
## sempre, motor de pé durante a partida e derrubado no `abandon`.
func _bot_game() -> void:
	var rules := ChessRules.new()
	var state := rules.initial_state()
	var bots := [Bot.new(), Bot.new()]
	var legal := true
	for ply in 30:
		if rules.outcome(state) != Ruleset.Outcome.ONGOING:
			break
		var bot: Bot = bots[ply % 2]
		bot.think(&"chess", state, 0 if ply % 2 == 0 else 2, 200)
		var move: Move = null
		while move == null:
			OS.delay_msec(10)
			move = bot.take_move()
		legal = legal and rules.move_from_uci(state, rules.uci(move)) != null
		rules.apply_move(state, move)
	_check(legal, "bot×bot via Stockfish: só lances legais (%d meios-lances)" % state.ply)
	_check(bots[0]._engine != null and bots[0]._engine.running(), "bot usou o Stockfish")
	for bot in bots:
		bot.abandon()
	_check(bots[0]._engine == null, "abandon derruba o motor")


## O mate do pastor que não aconteceu: 3...Cf6?? deixa Dxf7# na mesa, e 4.d3
## deixa passar. A outra linha dá o mate, que não pode virar "mate perdido".
func _review() -> void:
	var missed := _history(["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "d2d3"])
	var entries := GameReview.new().analyse(missed)
	_check(entries.size() == 7, "uma entrada por lance (%d)" % entries.size())
	if entries.size() == 7:
		_check(entries[5]["verdict"] == GameReview.Verdict.BLUNDER, "3...Cf6 é erro grave (%s)" % GameReview.LABEL[entries[5]["verdict"]])
		_check(entries[6]["missed_mate"], "4.d3 deixa o mate passar")
		_check(entries[6]["best_san"] == "Dxf7#", "o melhor era Dxf7# (veio %s)" % entries[6]["best_san"])
		_check(not entries[4]["missed_mate"], "lance sem mate na mesa não é mate perdido")

	var mated := GameReview.new().analyse(_history(["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"]))
	_check(mated.size() == 7 and not mated[6]["missed_mate"], "dar o mate não é mate perdido")
	_check(mated.size() == 7 and mated[6]["verdict"] == GameReview.Verdict.BEST, "Dxf7# é o melhor lance")


func _history(moves: Array) -> Array:
	var rules := ChessRules.new()
	var state := rules.initial_state()
	for text in moves:
		rules.apply_move(state, rules.move_from_uci(state, text))
	return state.history


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FALHOU", label])
	if not condition:
		_failures += 1
