extends SceneTree

## As regras e o placar do boliche, sem física nem tela.
##
##   godot --headless --path . --script res://tests/bowling_probe.gd
##
## A física decide quais pinos caem; daqui para frente é só contagem, e é a
## contagem que tem de estar certa nos dois aparelhos e no histórico.

var _failures := 0


func _initialize() -> void:
	_test_classic_games()
	_test_known_card()
	_test_tenth_frame()
	_test_rack()
	_test_turns_and_winner()
	_test_validate()
	_test_replay()

	if _failures == 0:
		print("OK — boliche consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


func _test_classic_games() -> void:
	print("jogos clássicos")
	var perfect := _game([10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10])
	_equals(BowlingRules.score_of(perfect, 0), 300, "jogo perfeito é 300")
	_check(BowlingRules.game_over(perfect), "e acaba na 12ª bola")

	var spares := _game([9, 1, 9, 1, 9, 1, 9, 1, 9, 1, 9, 1, 9, 1, 9, 1, 9, 1, 9, 1, 9])
	_equals(BowlingRules.score_of(spares, 0), 190, "tudo 9 e spare, bônus 9, é 190")

	var gutters := _game([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	_equals(BowlingRules.score_of(gutters, 0), 0, "tudo canaleta é 0")
	_check(BowlingRules.game_over(gutters), "e acaba na 20ª bola")

	var nines := _game([9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0])
	_equals(BowlingRules.score_of(nines, 0), 90, "tudo 9 e erro é 90")


func _test_known_card() -> void:
	print("cartela conhecida")
	# X | 7/ | 9- | X | -8 | 8/ | -6 | X | X | X81
	var state := _game([10, 7, 3, 9, 0, 10, 0, 8, 8, 2, 0, 6, 10, 10, 10, 8, 1])
	var rolls := BowlingRules.rolls_of(state, 0)
	_equals(
		BowlingRules.totals(rolls),
		PackedInt32Array([20, 39, 48, 66, 74, 84, 90, 120, 148, 167]),
		"acumulado frame a frame"
	)
	var marks := BowlingRules.marks(rolls)
	var flat := PackedStringArray()
	for cells in marks:
		flat.append(" ".join(cells))
	_equals(
		" | ".join(flat), "X | 7 / | 9 - | X | - 8 | 8 / | - 6 | X | X | X 8 1",
		"marcas da cartela"
	)

	# Strike esperando as duas seguintes: o frame fica em aberto, e os de depois também.
	var pending := _game([10, 7])
	_equals(
		BowlingRules.totals(BowlingRules.rolls_of(pending, 0)).slice(0, 3),
		PackedInt32Array([-1, -1, -1]), "strike espera duas bolas"
	)
	_equals(BowlingRules.score_of(pending, 0), 0, "e o placar só conta o resolvido")
	var spare := _game([7, 3])
	_equals(BowlingRules.totals(BowlingRules.rolls_of(spare, 0))[0], -1, "spare espera uma bola")
	_equals(_rules(1).status_hint(_new(1)), "Frame 1, 1ª bola.", "dica do primeiro frame")


func _test_tenth_frame() -> void:
	print("décimo frame")
	var nine := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

	var three := _game(nine + [10, 10, 10])
	_equals(BowlingRules.score_of(three, 0), 30, "X X X no décimo é 30")
	_check(BowlingRules.game_over(three), "e acaba")
	_equals(" ".join(BowlingRules.marks(BowlingRules.rolls_of(three, 0))[9]), "X X X", "marcado X X X")

	var spare := _game(nine + [6, 4, 7])
	_equals(BowlingRules.score_of(spare, 0), 17, "spare no décimo ganha a bola extra")
	_equals(" ".join(BowlingRules.marks(BowlingRules.rolls_of(spare, 0))[9]), "6 / 7", "marcado 6 / 7")

	var open := _game(nine + [6, 3])
	_check(BowlingRules.game_over(open), "aberto no décimo acaba em duas bolas")
	_equals(BowlingRules.score_of(open, 0), 9, "sem bônus")

	var strike_then := _game(nine + [10, 7, 3])
	_equals(" ".join(BowlingRules.marks(BowlingRules.rolls_of(strike_then, 0))[9]), "X 7 /", "X 7 / no décimo")
	_equals(BowlingRules.score_of(strike_then, 0), 20, "vale 20")


func _test_rack() -> void:
	print("máquina de pinos")
	var rules := _rules(1)
	var state := rules.initial_state()
	_equals(BowlingRules.standing(state), BowlingRules.ALL_PINS, "dez em pé no começo")
	_apply(rules, state, 0b0001111111)  # pinos 1 a 7
	_equals(BowlingRules.standing(state), 0b1110000000, "sobram 8, 9 e 10")
	_apply(rules, state, 0b0100000000)  # derruba o 9
	_equals(BowlingRules.standing(state), BowlingRules.ALL_PINS, "frame fechado arma os dez")
	_equals(BowlingRules.rolls_of(state, 0), PackedInt32Array([7, 1]), "e conta 7 e 1")

	# Décimo: strike arma de novo; depois de 7, a terceira é contra os 3 que sobraram.
	var tenth := _game([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	_apply(rules, tenth, BowlingRules.ALL_PINS)
	_equals(BowlingRules.standing(tenth), BowlingRules.ALL_PINS, "strike no décimo arma os dez")
	_apply(rules, tenth, 0b0001111111)
	_equals(BowlingRules.standing(tenth), 0b1110000000, "a terceira é contra o que sobrou")
	_check(not BowlingRules.game_over(tenth), "e ainda falta ela")


func _test_turns_and_winner() -> void:
	print("vez e vencedor")
	var rules := _rules(2)
	var state := rules.initial_state()
	_apply(rules, state, BowlingRules.ALL_PINS)
	_equals(BowlingRules.turn_of(state), 1, "strike passa a vez")
	_apply(rules, state, 0b0000000111)
	_equals(BowlingRules.turn_of(state), 1, "a segunda bola ainda é dele")
	_apply(rules, state, 0)
	_equals(BowlingRules.turn_of(state), 0, "frame fechado devolve a vez")
	_equals(rules.rounds_played(state), 1, "uma volta completa")

	# Nove frames de canaleta para os dois, e o décimo decide.
	var duel := _rules(2).initial_state()
	for frame in 9:
		for seat in 2:
			_play(rules, duel, 0)
			_play(rules, duel, 0)
	_play(rules, duel, 5)
	_play(rules, duel, 0)
	_check(BowlingRules.winner_of(duel) == -1, "ninguém vence antes do fim")
	_play(rules, duel, 3)
	_play(rules, duel, 1)
	_check(BowlingRules.game_over(duel), "acaba quando o último fecha o décimo")
	_equals(BowlingRules.winner_of(duel), 0, "vence o maior placar")
	_equals(rules.outcome(duel), Ruleset.Outcome.WHITE_WINS, "e o assento 0 é o das brancas")

	var tie := _rules(2).initial_state()
	for i in 40:
		_play(rules, tie, 0)
	_equals(BowlingRules.winner_of(tie), -2, "placar igual é empate")
	_equals(rules.outcome(tie), Ruleset.Outcome.DRAW, "e o resultado diz isso")


func _test_validate() -> void:
	print("validação")
	var rules := _rules(1)
	var state := rules.initial_state()
	_check(rules.validate(state, BowlingRules.roll(0b11).path) != null, "lance comum passa")
	_check(rules.validate(state, PackedInt32Array([0, 1, 0, 0])) == null, "tamanho errado é recusado")
	_check(rules.validate(state, PackedInt32Array([0, 1, 0, 0, 0, 0])) == null, "lance de 6 casas, sem a força, é recusado")
	_check(rules.validate(state, PackedInt32Array([0, 1, 0, 0, 0, 1001, 500])) == null, "parâmetro fora da faixa é recusado")
	_check(rules.validate(state, PackedInt32Array([0, 1 << 10, 0, 0, 0, 0, 500])) == null, "pino que não existe é recusado")
	_apply(rules, state, 0b1)
	_check(rules.validate(state, BowlingRules.roll(0b1).path) == null, "pino já caído é recusado")
	_check(rules.validate(state, BowlingRules.roll(0b10).path) != null, "pino em pé passa")
	var over := _game([10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10])
	_check(rules.validate(over, BowlingRules.roll(0).path) == null, "depois do fim nada passa")

	var params := PackedFloat32Array([0.25, -0.5, 1.0, -0.125, 0.75])
	var move := BowlingRules.roll(0b101, params)
	_equals(BowlingRules.params_of(move), params, "parâmetros vão e voltam em milésimos")
	_equals(BowlingRules.mask_of(move), 0b101, "e a máscara junto")


func _test_replay() -> void:
	print("histórico")
	var rules := _rules(3)
	var state := rules.initial_state()
	var counts := [10, 7, 2, 9, 1, 0, 0, 10, 3, 6, 8, 2, 10, 5, 4, 0, 10, 10, 9, 0]
	for pins in counts:
		_play(rules, state, pins)
	var again := rules.initial_state()
	var replayed := 0
	for entry in state.history:
		var move := rules.validate(again, Move.from_dict(entry).path)
		if move == null:
			break
		rules.apply_move(again, move)
		replayed += 1
	_equals(replayed, counts.size(), "todo lance do histórico passa de novo")
	for seat in 3:
		_equals(BowlingRules.rolls_of(again, seat), BowlingRules.rolls_of(state, seat), "assento %d igual" % seat)
	_equals(BowlingRules.standing(again), BowlingRules.standing(state), "pinos em pé iguais")
	_equals(BowlingRules.turn_of(again), BowlingRules.turn_of(state), "vez igual")


# --- apoio --------------------------------------------------------------------


func _rules(seats: int) -> BowlingRules:
	var rules := BowlingRules.new()
	rules.seats = seats
	return rules


func _new(seats: int) -> MatchState:
	return _rules(seats).initial_state()


## Uma partida de um jogador só, pelas contagens de cada bola.
func _game(counts: Array) -> MatchState:
	var rules := _rules(1)
	var state := rules.initial_state()
	for pins in counts:
		_play(rules, state, pins)
	return state


## Derruba os `pins` primeiros pinos em pé.
func _play(rules: BowlingRules, state: MatchState, pins: int) -> void:
	var mask := 0
	var left := BowlingRules.standing(state)
	for pin in BowlingRules.PINS:
		if pins == 0:
			break
		if left & (1 << pin):
			mask |= 1 << pin
			pins -= 1
	_apply(rules, state, mask)


func _apply(rules: BowlingRules, state: MatchState, mask: int) -> void:
	var move := rules.validate(state, BowlingRules.roll(mask).path)
	if move == null:
		_failures += 1
		printerr("  FAIL lance de %s recusado" % String.num_int64(mask, 2))
		return
	rules.apply_move(state, move)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
