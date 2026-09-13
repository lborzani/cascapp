extends SceneTree

## Bancada do bot de xadrez: quanto custa cada profundidade, e o que ele escolhe.
##
##   godot --headless --path . --script res://tests/bot_bench.gd
##
## Não é teste — não afirma nada e não falha. É a régua: imprime a pontuação de
## cada lance da raiz em várias profundidades **sem limite de tempo**, o custo por
## profundidade, o preço de uma chamada a `generate_moves`, e o que cada nível
## joga com o relógio dele ligado.
##
## Existe porque a otimização da busca precisou separar três perguntas que o
## sintoma misturava: "a busca prefere este lance", "a busca não teve tempo de
## olhar" e "onde o tempo está indo". Sem os números lado a lado, a resposta óbvia
## — mexer na avaliação — teria sido a errada: o bot que passeava com a torre não
## preferia a torre, ele nunca chegou a pontuar lance nenhum.
##
## Medidas para comparar depois (desktop, Godot 4.7.1):
##
##                        antes      depois
##   generate_moves       0,650 ms   0,195 ms
##   abertura, prof. 1    2263 ms      65 ms
##   abertura, prof. 2    3749 ms     387 ms
##   meio-jogo, prof. 1   7875 ms    2550 ms
##   meio-jogo, prof. 2  11906 ms    2884 ms
##
## O meio-jogo é a coluna que importa: era lá que o bot fraco não completava
## rodada nenhuma e acabava jogando a torre. As notas de cada profundidade saem
## idênticas antes e depois — as podas cortam trabalho, não resposta.

const OPENING := [
	["e2", "e4"], ["e7", "e5"], ["g1", "f3"], ["b8", "c6"],
	["f1", "c4"], ["f8", "c5"], ["e1", "g1"], ["g8", "f6"],
	["b1", "c3"], ["c5", "d6"],
]
const SHOWN := 6


func _initialize() -> void:
	var rules := ChessRules.new()
	var state := rules.initial_state()
	for step in OPENING:
		var move := _find(rules, state, step[0], step[1])
		if move == null:
			printerr("lance %s-%s indisponível" % step)
			quit(1)
			return
		rules.apply_move(state, move)

	_report(rules, state, "abertura")
	# A posição do relato é de meio-jogo, com o tabuleiro cheio: mais lances na
	# raiz e cada `generate_moves` mais caro. Uma abertura mansa não mede o caso
	# em que o bot fraco vive.
	_report(rules, _midgame(rules), "meio-jogo (Kiwipete)")
	quit(0)


func _report(rules: ChessRules, state: MatchState, label: String) -> void:
	print("--- %s: avaliação parada = %.1f" % [label, rules.evaluate(state)])
	var moves := rules.generate_moves(state)
	print("primeiro lance gerado: %s (de %d)" % [rules.notation(state, moves[0]), moves.size()])
	for depth in [1, 2]:
		_dump(rules, state, depth)

	_bench(rules, state)

	# O que o bot **de verdade** joga, com o relógio do nível ligado.
	for level in Bot.LEVELS.size():
		var bot := Bot.new()
		var started := Time.get_ticks_msec()
		bot.think(&"chess", state, level)
		var chosen: Move = null
		while chosen == null:
			chosen = bot.take_move()
		print("nível %s: %s em %d ms" % [
			Bot.level_label(level), rules.notation(state, chosen), Time.get_ticks_msec() - started
		])


## Kiwipete: 48 lances na raiz, tabuleiro cheio. O meio-jogo que o print do
## relato mostrava.
func _midgame(rules: ChessRules) -> MatchState:
	var state := rules.initial_state()
	state.squares = Board.empty_squares()
	var pieces := {
		"a1": [Board.Side.WHITE, Board.Kind.ROOK], "e1": [Board.Side.WHITE, Board.Kind.KING],
		"h1": [Board.Side.WHITE, Board.Kind.ROOK], "a2": [Board.Side.WHITE, Board.Kind.PAWN],
		"b2": [Board.Side.WHITE, Board.Kind.PAWN], "c2": [Board.Side.WHITE, Board.Kind.PAWN],
		"d2": [Board.Side.WHITE, Board.Kind.BISHOP], "e2": [Board.Side.WHITE, Board.Kind.BISHOP],
		"f2": [Board.Side.WHITE, Board.Kind.PAWN], "g2": [Board.Side.WHITE, Board.Kind.PAWN],
		"h2": [Board.Side.WHITE, Board.Kind.PAWN], "c3": [Board.Side.WHITE, Board.Kind.KNIGHT],
		"f3": [Board.Side.WHITE, Board.Kind.QUEEN], "e4": [Board.Side.WHITE, Board.Kind.PAWN],
		"d5": [Board.Side.WHITE, Board.Kind.PAWN], "e5": [Board.Side.WHITE, Board.Kind.KNIGHT],
		"h3": [Board.Side.BLACK, Board.Kind.PAWN], "b4": [Board.Side.BLACK, Board.Kind.PAWN],
		"a6": [Board.Side.BLACK, Board.Kind.BISHOP], "b6": [Board.Side.BLACK, Board.Kind.KNIGHT],
		"e6": [Board.Side.BLACK, Board.Kind.PAWN], "f6": [Board.Side.BLACK, Board.Kind.KNIGHT],
		"g6": [Board.Side.BLACK, Board.Kind.PAWN], "a7": [Board.Side.BLACK, Board.Kind.PAWN],
		"c7": [Board.Side.BLACK, Board.Kind.PAWN], "d7": [Board.Side.BLACK, Board.Kind.PAWN],
		"e7": [Board.Side.BLACK, Board.Kind.QUEEN], "f7": [Board.Side.BLACK, Board.Kind.PAWN],
		"g7": [Board.Side.BLACK, Board.Kind.BISHOP], "a8": [Board.Side.BLACK, Board.Kind.ROOK],
		"e8": [Board.Side.BLACK, Board.Kind.KING], "h8": [Board.Side.BLACK, Board.Kind.ROOK],
	}
	for name in pieces:
		var entry: Array = pieces[name]
		state.set_piece(_square(name), Board.piece(entry[0], entry[1]))
	state.side_to_move = Board.Side.WHITE
	state.meta = {"castle": ChessRules.CASTLE_ALL, "ep": Board.NO_SQUARE, "halfmove": 0}
	return state


## Pontua todo lance da raiz com a mesma busca do bot, mas com o relógio
## desligado: `_deadline` no futuro distante, para nenhuma poda por tempo se
## confundir com preferência.
func _dump(rules: ChessRules, state: MatchState, depth: int) -> void:
	var bot := Bot.new()
	bot._ruleset = rules
	bot._deadline = Time.get_ticks_msec() + 600_000
	bot._expired = false
	bot._abandoned = false
	bot._ticks = 0

	var started := Time.get_ticks_msec()
	var scored := []
	for move in rules.generate_moves(state):
		var next := state.clone()
		rules.apply_move(next, move)
		var score := -bot._search(next, depth - 1, -Bot.MATE * 2.0, Bot.MATE * 2.0)
		scored.append({"note": rules.notation(state, move), "score": score})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])

	var line := PackedStringArray()
	for index in mini(SHOWN, scored.size()):
		line.append("%s %.1f" % [scored[index]["note"], scored[index]["score"]])
	print("profundidade %d (%d ms): %s" % [
		depth, Time.get_ticks_msec() - started, "   ".join(line)
	])


## Onde o tempo vai. Um nó de busca é: clonar, aplicar, gerar, avaliar — e a
## conta só fecha se soubermos quanto custa cada um deles separado.
func _bench(rules: ChessRules, state: MatchState) -> void:
	const ROUNDS := 200
	var started := Time.get_ticks_msec()
	for i in ROUNDS:
		var copy := state.clone()
	var clone_ms := Time.get_ticks_msec() - started

	started = Time.get_ticks_msec()
	for i in ROUNDS:
		var generated := rules.generate_moves(state)
	var gen_ms := Time.get_ticks_msec() - started

	started = Time.get_ticks_msec()
	for i in ROUNDS:
		var value := rules.evaluate(state)
	var eval_ms := Time.get_ticks_msec() - started

	print("por chamada em %d rodadas: clone %.3f ms | generate_moves %.3f ms | evaluate %.3f ms" % [
		ROUNDS, float(clone_ms) / ROUNDS, float(gen_ms) / ROUNDS, float(eval_ms) / ROUNDS
	])


func _find(rules: ChessRules, state: MatchState, from: String, to: String) -> Move:
	for move in rules.generate_moves(state):
		if move.from_square() == _square(from) and move.to_square() == _square(to):
			return move
	return null


static func _square(name: String) -> int:
	return Board.square(name.unicode_at(0) - "a".unicode_at(0), int(name.substr(1)) - 1)
