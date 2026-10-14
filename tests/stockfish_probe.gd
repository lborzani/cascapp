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

	print("OK — stockfish." if _failures == 0 else "%d falha(s)." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FALHOU", label])
	if not condition:
		_failures += 1
