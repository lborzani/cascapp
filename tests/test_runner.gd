extends SceneTree

## Headless self-test for the parts that are easy to get subtly wrong: chess
## move generation (perft), the checkers capture rules, and the QR matrix.
##
##   godot --headless --path . --import        # uma vez, gera o cache de classes
##   godot --headless --path . --script res://tests/test_runner.gd

## Autoloads are not instantiated for a `--script` run, so the pairing helpers
## are reached through the script itself (they are static on purpose).
const PairingLib := preload("res://autoload/pairing.gd")

var _failures := 0


func _initialize() -> void:
	_test_chess_perft()
	_test_chess_special_moves()
	_test_chess_notation()
	_test_checkers_notation()
	_test_checkers_opening()
	_test_checkers_capture_routes()
	_test_checkers_optional_capture()
	_test_checkers_promotion()
	_test_battleship_placement()
	_test_battleship_shots()
	_test_bot_chess()
	_test_bot_starved()
	_test_bot_checkers()
	_test_qr_structure()
	_test_pairing_payload()
	_test_app_version()
	_test_prefs()
	_test_rounds_played()
	_test_match_clock()

	if _failures == 0:
		print("OK — todos os testes passaram.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


## Rodadas completas, que a faixa de contexto mostra nas cinco telas.
##
## O que se testa aqui é que cada jogo responde na **sua** unidade. A conta
## padrão é lances dividido por jogadores, e ela erraria feio nos dois jogos que
## não alternam estritamente: em Metrópole uma dupla nos dados devolve a vez a
## quem jogou, e no Ludo um 6 faz o mesmo. Metrópole tem contador próprio; o Ludo
## aceita o erro para baixo, e este teste registra que ele é conhecido.
func _test_rounds_played() -> void:
	print("rodadas completas")

	var chess := ChessRules.new()
	var state := chess.initial_state()
	_equals(chess.players(), 2, "xadrez se reveza entre dois")
	_equals(chess.rounds_played(state), 0, "partida nova não teve rodada nenhuma")
	state.ply = 1
	_equals(chess.rounds_played(state), 0, "um lance não fecha a volta")
	state.ply = 2
	_equals(chess.rounds_played(state), 1, "os dois lances fecham a primeira")
	state.ply = 21
	_equals(chess.rounds_played(state), 10, "e a rodada em curso não conta")

	var ludo := LudoRules.new()
	_equals(ludo.players(), LudoRules.PLAYERS, "o Ludo são quatro cantos")
	var ludo_state := ludo.initial_state()
	ludo_state.ply = 8
	_equals(ludo.rounds_played(ludo_state), 2, "quatro lances por volta")

	# Metrópole não deriva de `ply`: ela lê o contador que já usa para acabar a
	# partida por número de rodadas. É o mesmo número que o limite do menu compara,
	# e mostrar um diferente na faixa seria a tela discordando da regra que encerra
	# a partida na frente do jogador.
	var monopoly := MonopolyRules.new()
	monopoly.seats = 5
	var table := monopoly.initial_state()
	_equals(monopoly.players(), 5, "Metrópole se reveza entre quantos sentaram")
	_equals(monopoly.rounds_played(table), 0, "mesa nova, nenhuma rodada")
	table.ply = 40
	_equals(
		monopoly.rounds_played(table), 0,
		"e lances não viram rodadas: a dupla devolve a vez a quem jogou"
	)
	table.meta[MonopolyRules.ROUND] = 7
	_equals(monopoly.rounds_played(table), 7, "quem responde é o contador do jogo")


## Onde começou a partida que está em curso — a memória que faz o relógio da
## faixa sobreviver a uma queda.
##
## É o que separa "quanto tempo este nó existe" de "quanto tempo esta partida
## dura", e a diferença só aparece no caso que ninguém testa à mão: o aparelho que
## fechou o app no meio da partida e voltou pela mesma sala.
##
## Aqui e não junto do resto da faixa porque `Prefs` é estático e não depende de
## autoload nenhum. O `MatchStatus` depende, e por isso é testado no
## `scene_probe`.
func _test_match_clock() -> void:
	print("começo de partida guardado")

	var code := "PROBE1"
	var start := 1_700_000_000
	_equals(Prefs.match_start(code, start), start, "a primeira pergunta grava o começo")
	# O caso da reconexão: outro instante, a mesma sala. Quem volta tem de
	# reencontrar o relógio onde ele estava, e não em zero.
	_equals(
		Prefs.match_start(code, start + 600), start,
		"voltar para a mesma sala reencontra o começo original"
	)
	# Sala diferente é partida diferente, mesmo sem ninguém ter avisado nada.
	_equals(
		Prefs.match_start("PROBE2", start + 900), start + 900,
		"outra sala começa a contar agora"
	)
	# E a revanche: mesma sala, partida nova. Sem isto o relógio da segunda partida
	# abriria com o tempo da primeira.
	_equals(
		Prefs.restart_match("PROBE2", start + 1200), start + 1200,
		"a revanche zera o relógio sem trocar de sala"
	)
	_equals(
		Prefs.match_start("PROBE2", start + 9999), start + 1200,
		"e o novo começo é o que fica gravado"
	)

	# O arquivo é o de verdade, do aparelho de quem roda a suíte. Sala vazia é a
	# que `Game.begin_match()` nunca consulta — sem isto, uma partida real numa
	# sala chamada PROBE2 herdaria um relógio de 2023.
	Prefs.restart_match("", 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])


# --- chess -------------------------------------------------------------------


func _perft(rules: ChessRules, state: MatchState, depth: int) -> int:
	var moves := rules.generate_moves(state)
	if depth <= 1:
		return moves.size()
	var total := 0
	for move in moves:
		var next := state.clone()
		rules.apply_move(next, move)
		total += _perft(rules, next, depth - 1)
	return total


func _test_chess_perft() -> void:
	print("chess perft")
	var rules := ChessRules.new()
	var state := rules.initial_state()
	_equals(_perft(rules, state, 1), 20, "perft(1)")
	_equals(_perft(rules, state, 2), 400, "perft(2)")
	_equals(_perft(rules, state, 3), 8902, "perft(3)")
	_equals(_perft(rules, state, 4), 197281, "perft(4)")

	# As duas posições de tortura clássicas. A inicial é mansa: nela quase nenhum
	# lance é ilegal, e um gerador que **nunca** conferisse a legalidade passaria
	# perft(4) com folga. Estas duas existem para isso não ser possível.
	#
	# Kiwipete — roque dos dois lados, peças pregadas, xeque, e um bocado de
	# lance pseudo-legal que deixa o rei em xeque.
	var kiwipete := _position(rules, {
		"a1": [Board.Side.WHITE, Board.Kind.ROOK],
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"h1": [Board.Side.WHITE, Board.Kind.ROOK],
		"a2": [Board.Side.WHITE, Board.Kind.PAWN],
		"b2": [Board.Side.WHITE, Board.Kind.PAWN],
		"c2": [Board.Side.WHITE, Board.Kind.PAWN],
		"d2": [Board.Side.WHITE, Board.Kind.BISHOP],
		"e2": [Board.Side.WHITE, Board.Kind.BISHOP],
		"f2": [Board.Side.WHITE, Board.Kind.PAWN],
		"g2": [Board.Side.WHITE, Board.Kind.PAWN],
		"h2": [Board.Side.WHITE, Board.Kind.PAWN],
		"c3": [Board.Side.WHITE, Board.Kind.KNIGHT],
		"f3": [Board.Side.WHITE, Board.Kind.QUEEN],
		"e4": [Board.Side.WHITE, Board.Kind.PAWN],
		"d5": [Board.Side.WHITE, Board.Kind.PAWN],
		"e5": [Board.Side.WHITE, Board.Kind.KNIGHT],
		"h3": [Board.Side.BLACK, Board.Kind.PAWN],
		"b4": [Board.Side.BLACK, Board.Kind.PAWN],
		"a6": [Board.Side.BLACK, Board.Kind.BISHOP],
		"b6": [Board.Side.BLACK, Board.Kind.KNIGHT],
		"e6": [Board.Side.BLACK, Board.Kind.PAWN],
		"f6": [Board.Side.BLACK, Board.Kind.KNIGHT],
		"g6": [Board.Side.BLACK, Board.Kind.PAWN],
		"a7": [Board.Side.BLACK, Board.Kind.PAWN],
		"c7": [Board.Side.BLACK, Board.Kind.PAWN],
		"d7": [Board.Side.BLACK, Board.Kind.PAWN],
		"e7": [Board.Side.BLACK, Board.Kind.QUEEN],
		"f7": [Board.Side.BLACK, Board.Kind.PAWN],
		"g7": [Board.Side.BLACK, Board.Kind.BISHOP],
		"a8": [Board.Side.BLACK, Board.Kind.ROOK],
		"e8": [Board.Side.BLACK, Board.Kind.KING],
		"h8": [Board.Side.BLACK, Board.Kind.ROOK],
	}, ChessRules.CASTLE_ALL)
	_equals(_perft(rules, kiwipete, 1), 48, "kiwipete(1)")
	_equals(_perft(rules, kiwipete, 2), 2039, "kiwipete(2)")
	_equals(_perft(rules, kiwipete, 3), 97862, "kiwipete(3)")

	# A terceira posição da lista clássica: poucas peças e fundo. É a que pega o
	# en passant que **descobre** xeque na quinta linha — o caso que todo atalho de
	# legalidade erra, porque a captura tira uma peça de uma casa em que o lance
	# não pousa.
	var endgame := _position(rules, {
		"a5": [Board.Side.WHITE, Board.Kind.KING],
		"b5": [Board.Side.WHITE, Board.Kind.PAWN],
		"b4": [Board.Side.WHITE, Board.Kind.ROOK],
		"e2": [Board.Side.WHITE, Board.Kind.PAWN],
		"g2": [Board.Side.WHITE, Board.Kind.PAWN],
		"c7": [Board.Side.BLACK, Board.Kind.PAWN],
		"d6": [Board.Side.BLACK, Board.Kind.PAWN],
		"h5": [Board.Side.BLACK, Board.Kind.ROOK],
		"f4": [Board.Side.BLACK, Board.Kind.PAWN],
		"h4": [Board.Side.BLACK, Board.Kind.KING],
	})
	_equals(_perft(rules, endgame, 1), 14, "final(1)")
	_equals(_perft(rules, endgame, 2), 191, "final(2)")
	_equals(_perft(rules, endgame, 3), 2812, "final(3)")
	_equals(_perft(rules, endgame, 4), 43238, "final(4)")


## O bot sem tempo nenhum: ele ainda tem de devolver um lance que **olhou**.
##
## Era o bug do passeio da torre. Quando nenhuma rodada de aprofundamento cabia no
## orçamento, a busca desistia e devolvia `moves[0]` — o primeiro lance que o
## gerador produz, que ninguém pontuou. O gerador varre o tabuleiro de a1 para
## h8, então esse lance é o da peça na casa mais baixa: depois do roque, a torre.
## O bot jogava `Tf1`, na vez seguinte `Te1`, e assim até uma captura mudar a
## lista — que é exatamente o sintoma relatado.
##
## A posição é a do relato: brancas rocaram, nada pendurado, e o primeiro lance
## gerado é o da torre. Um milissegundo de orçamento garante que nenhuma rodada
## termine, então o que sai aqui é só o caminho de emergência.
func _test_bot_starved() -> void:
	print("bot sem tempo")
	var rules := ChessRules.new()
	var state := rules.initial_state()
	for step in [
		["e2", "e4"], ["e7", "e5"], ["g1", "f3"], ["b8", "c6"],
		["f1", "c4"], ["f8", "c5"], ["e1", "g1"], ["g8", "f6"],
		["b1", "c3"], ["c5", "d6"],
	]:
		var move := _find(rules, state, step[0], step[1])
		if move == null:
			_check(false, "abertura %s-%s indisponível" % step)
			return
		rules.apply_move(state, move)

	var first := rules.generate_moves(state)[0]
	_equals(
		rules.notation(state, first), "Tb1",
		"o primeiro lance do gerador continua sendo o da torre"
	)

	var bot := Bot.new()
	bot.think(&"chess", state, 0, 1)
	var chosen: Move = null
	while chosen == null:
		chosen = bot.take_move()
	_check(
		not chosen.same_as(first),
		"com um milissegundo, o bot não devolve o lance que ninguém olhou (devolveu %s)"
			% rules.notation(state, chosen)
	)


func _test_chess_special_moves() -> void:
	print("chess lances especiais")
	var rules := ChessRules.new()

	# Empty board except the white king, both rooks and the black king.
	var state := MatchState.new()
	state.set_piece(4, Board.piece(Board.Side.WHITE, Board.Kind.KING))
	state.set_piece(0, Board.piece(Board.Side.WHITE, Board.Kind.ROOK))
	state.set_piece(7, Board.piece(Board.Side.WHITE, Board.Kind.ROOK))
	state.set_piece(60, Board.piece(Board.Side.BLACK, Board.Kind.KING))
	state.meta = {"castle": ChessRules.CASTLE_ALL, "ep": Board.NO_SQUARE, "halfmove": 0}
	var castles := 0
	for move in rules.generate_moves(state):
		if move.tags.has("castle"):
			castles += 1
	_equals(castles, 2, "roque dos dois lados disponível")

	# Fool's mate: 1. f3 e5 2. g4 Qh4#
	var game := rules.initial_state()
	for path in [[13, 21], [52, 36], [14, 30], [59, 31]]:
		var chosen: Move = null
		for move in rules.generate_moves(game):
			if move.from_square() == path[0] and move.to_square() == path[1]:
				chosen = move
				break
		if chosen == null:
			_check(false, "lance %s-%s disponível" % [Board.square_name(path[0]), Board.square_name(path[1])])
			return
		rules.apply_move(game, chosen)
	_equals(rules.outcome(game), Ruleset.Outcome.BLACK_WINS, "mate do pastor invertido (fool's mate)")

	# White pawn on the 7th rank offers four promotions.
	var promo := MatchState.new()
	promo.set_piece(Board.square(0, 6), Board.piece(Board.Side.WHITE, Board.Kind.PAWN))
	promo.set_piece(Board.square(4, 0), Board.piece(Board.Side.WHITE, Board.Kind.KING))
	promo.set_piece(Board.square(4, 7), Board.piece(Board.Side.BLACK, Board.Kind.KING))
	promo.meta = {"castle": 0, "ep": Board.NO_SQUARE, "halfmove": 0}
	var promotions := 0
	for move in rules.generate_moves(promo):
		if move.promotion != Board.Kind.EMPTY:
			promotions += 1
	_equals(promotions, 4, "quatro opções de promoção")


## Notação é escrita uma vez e lida a partida inteira: um erro aqui não trava
## nada, só produz um histórico que descreve outra partida. Cada caso abaixo é
## uma regra da norma que só aparece numa posição específica.
func _test_chess_notation() -> void:
	print("xadrez notação")
	var rules := ChessRules.new()

	var opening := rules.initial_state()
	_equals(_notate(rules, opening, "e2", "e4"), "e4", "peão sem letra")
	_equals(_notate(rules, opening, "g1", "f3"), "Cf3", "cavalo em português")

	# Peão de e4 come em d5: a coluna de origem é o que distingue de "cxd5".
	var capture := _position(rules, {
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"e4": [Board.Side.WHITE, Board.Kind.PAWN],
		"c4": [Board.Side.WHITE, Board.Kind.PAWN],
		"d5": [Board.Side.BLACK, Board.Kind.PAWN],
		"e8": [Board.Side.BLACK, Board.Kind.KING],
	})
	_equals(_notate(rules, capture, "e4", "d5"), "exd5", "captura de peão leva a coluna")

	# Dois cavalos alcançam d2: b1 e f3. Colunas diferentes, então basta a coluna.
	var two_knights := _position(rules, {
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"b1": [Board.Side.WHITE, Board.Kind.KNIGHT],
		"f3": [Board.Side.WHITE, Board.Kind.KNIGHT],
		"e8": [Board.Side.BLACK, Board.Kind.KING],
	})
	_equals(_notate(rules, two_knights, "b1", "d2"), "Cbd2", "desambiguação pela coluna")

	# Mesma coluna (d1 e d5 para d3): aí a coluna não resolve e entra a linha.
	var same_file := _position(rules, {
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"d1": [Board.Side.WHITE, Board.Kind.ROOK],
		"d5": [Board.Side.WHITE, Board.Kind.ROOK],
		"e8": [Board.Side.BLACK, Board.Kind.KING],
	})
	_equals(_notate(rules, same_file, "d1", "d3"), "T1d3", "desambiguação pela linha")

	var castle := _position(rules, {
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"a1": [Board.Side.WHITE, Board.Kind.ROOK],
		"h1": [Board.Side.WHITE, Board.Kind.ROOK],
		"e8": [Board.Side.BLACK, Board.Kind.KING],
	}, ChessRules.CASTLE_ALL)
	_equals(_notate(rules, castle, "e1", "g1"), "O-O", "roque pequeno")
	_equals(_notate(rules, castle, "e1", "c1"), "O-O-O", "roque grande")

	# Peão em a7 promove em a8 e a dama nova dá xeque no rei em c8.
	var promotion := _position(rules, {
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"a7": [Board.Side.WHITE, Board.Kind.PAWN],
		"c8": [Board.Side.BLACK, Board.Kind.KING],
	})
	_equals(_notate(rules, promotion, "a7", "a8"), "a8=D+", "promoção com xeque")

	# Mate do corredor: a torre toma a oitava linha inteira e o rei preto está
	# preso atrás dos próprios peões.
	var mate := _position(rules, {
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"a1": [Board.Side.WHITE, Board.Kind.ROOK],
		"g8": [Board.Side.BLACK, Board.Kind.KING],
		"f7": [Board.Side.BLACK, Board.Kind.PAWN],
		"g7": [Board.Side.BLACK, Board.Kind.PAWN],
		"h7": [Board.Side.BLACK, Board.Kind.PAWN],
	})
	_equals(_notate(rules, mate, "a1", "a8"), "Ta8#", "mate marcado com #")


func _test_checkers_notation() -> void:
	print("damas notação")
	var rules := CheckersRules.new()

	var quiet := rules.initial_state()
	_equals(_notate(rules, quiet, "c3", "d4"), "c3-d4", "lance simples com hífen")

	# Uma pedra branca em c3 come duas pretas, em d4 e f6.
	var jump := MatchState.new()
	jump.set_piece(_sq("c3"), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	jump.set_piece(_sq("d4"), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	jump.set_piece(_sq("f6"), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	jump.side_to_move = Board.Side.WHITE
	jump.meta = {"idle": 0}
	var sequence := _find(rules, jump, "c3", "g7")
	_check(sequence != null, "sequência de duas capturas existe")
	if sequence != null:
		_equals(rules.notation(jump, sequence), "c3xe5xg7", "cada salto aparece na notação")

	# Pedra a um passo da última linha: a promoção entra no fim da notação.
	var promote := MatchState.new()
	promote.set_piece(_sq("c7"), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	promote.set_piece(_sq("a1"), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	promote.side_to_move = Board.Side.WHITE
	promote.meta = {"idle": 0}
	_equals(_notate(rules, promote, "c7", "d8"), "c7-d8=D", "promoção marcada")


## Notação do lance `from`-`to` na posição dada, ou uma mensagem de falha se o
## lance não existir — assim um teste que erra a posição diz isso, em vez de
## comparar contra uma string vazia e parecer um bug de notação.
func _notate(rules: Ruleset, state: MatchState, from: String, to: String) -> String:
	var move := _find(rules, state, from, to)
	if move == null:
		return "<lance %s-%s indisponível>" % [from, to]
	return rules.notation(state, move)


func _find(rules: Ruleset, state: MatchState, from: String, to: String) -> Move:
	for move in rules.generate_moves(state):
		if move.from_square() == _sq(from) and move.to_square() == _sq(to):
			return move
	return null


func _position(rules: ChessRules, pieces: Dictionary, castle: int = 0) -> MatchState:
	var state := rules.initial_state()
	state.squares = Board.empty_squares()
	for name in pieces:
		var entry: Array = pieces[name]
		state.set_piece(_sq(name), Board.piece(entry[0], entry[1]))
	state.side_to_move = Board.Side.WHITE
	state.meta = {"castle": castle, "ep": Board.NO_SQUARE, "halfmove": 0}
	return state


static func _sq(name: String) -> int:
	return Board.square(name.unicode_at(0) - "a".unicode_at(0), int(name.substr(1)) - 1)


# --- checkers ----------------------------------------------------------------


func _test_checkers_opening() -> void:
	print("damas abertura")
	var rules := CheckersRules.new()
	var state := rules.initial_state()
	_equals(state.count_pieces(Board.Side.WHITE), 12, "12 pedras brancas")
	_equals(state.count_pieces(Board.Side.BLACK), 12, "12 pedras pretas")
	_equals(rules.generate_moves(state).size(), 7, "7 lances iniciais")


func _test_checkers_capture_routes() -> void:
	print("damas rotas de captura")
	var rules := CheckersRules.new()
	var state := MatchState.new()
	state.meta = {"idle": 0}
	state.set_piece(Board.square(2, 2), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	# One route captures two pieces, the other only one. Capturing is optional,
	# so both are offered — but each route must be played to its end.
	state.set_piece(Board.square(3, 3), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	state.set_piece(Board.square(5, 5), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	state.set_piece(Board.square(1, 3), Board.piece(Board.Side.BLACK, Board.Kind.MAN))

	var moves := rules.generate_moves(state)
	var counts := PackedInt32Array()
	for move in moves:
		counts.append(move.captured.size())
	counts.sort()
	_equals(counts, PackedInt32Array([1, 2]), "as duas rotas de captura são legais")

	var longest: Move = null
	for move in moves:
		if move.captured.size() == 2:
			longest = move
	if longest == null:
		_check(false, "sequência de duas capturas existe")
		return
	_equals(longest.to_square(), Board.square(6, 6), "sequência de duas capturas termina em g7")


func _test_checkers_optional_capture() -> void:
	print("damas captura opcional")
	var rules := CheckersRules.new()
	var state := MatchState.new()
	state.meta = {"idle": 0}
	# The man on c3 can capture on d4; the one on g3 has nothing to do with it
	# and must still be free to move.
	state.set_piece(Board.square(2, 2), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	state.set_piece(Board.square(6, 2), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	state.set_piece(Board.square(3, 3), Board.piece(Board.Side.BLACK, Board.Kind.MAN))

	var quiet_from_idle_piece := 0
	var captures := 0
	for move in rules.generate_moves(state):
		if move.is_capture():
			captures += 1
		elif move.from_square() == Board.square(6, 2):
			quiet_from_idle_piece += 1
	_equals(captures, 1, "a captura continua disponível")
	_equals(quiet_from_idle_piece, 2, "a outra pedra pode mover mesmo havendo captura")


func _test_checkers_promotion() -> void:
	print("damas promoção")
	var rules := CheckersRules.new()
	var state := MatchState.new()
	state.meta = {"idle": 0}
	state.set_piece(Board.square(2, 6), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	state.set_piece(Board.square(0, 0), Board.piece(Board.Side.BLACK, Board.Kind.MAN))

	var promoted := false
	for move in rules.generate_moves(state):
		if move.promotion == Board.Kind.DAME:
			rules.apply_move(state, move)
			promoted = Board.kind_of(state.piece_at(move.to_square())) == Board.Kind.DAME
			break
	_check(promoted, "pedra na última linha vira dama")


# --- pairing -----------------------------------------------------------------


## Texto literal, e não o payload de pareamento: o que está sendo verificado é o
## codificador, e as posições conferidas abaixo dependem do tamanho da matriz.
## Amarrar isso ao formato do payload faz um teste de QR quebrar quando o
## pareamento muda de ideia — foi o que aconteceu quando o payload encolheu de
## sete campos para dois.
const QR_SAMPLE := "XDM3|chess|192.168.0.10|8909|ABC123||"


## O bot é testado por resultado, e não por linha: qual lance ele escolhe numa
## posição em que só existe uma resposta certa. É o único teste que sobrevive a
## mexer na avaliação ou na profundidade — e é justamente aí que se mexe.
##
## Roda no nível difícil, sem deslize: os níveis fracos erram de propósito, e um
## teste que os usasse falharia metade das vezes por projeto.
const HARD := 2


func _test_bot_chess() -> void:
	print("bot — xadrez")
	var rules := ChessRules.new()

	# Mate em 1. Rei preto em h8 sufocado pelos próprios peões, torre branca
	# entrando em a8. Se a busca não enxerga o mate, ela não enxerga nada.
	var mate := _position(rules, {
		"a1": [Board.Side.WHITE, Board.Kind.ROOK],
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"b2": [Board.Side.WHITE, Board.Kind.QUEEN],
		"h8": [Board.Side.BLACK, Board.Kind.KING],
		"g7": [Board.Side.BLACK, Board.Kind.PAWN],
		"h7": [Board.Side.BLACK, Board.Kind.PAWN],
	})
	# Conferido pelo resultado, e não pelo lance: a posição tem dois mates (Ta8 e
	# Db8), os dois certos. Um teste que exigisse um deles reprovaria o bot por
	# ter escolhido o outro.
	var mate_move := _bot_choice(&"chess", mate, HARD)
	var mated := mate.clone()
	rules.apply_move(mated, mate_move)
	_equals(
		rules.outcome(mated), Ruleset.Outcome.WHITE_WINS,
		"acha o mate em um (jogou %s)" % _path(mate_move)
	)

	# Peça de graça: dama preta indefesa ao alcance da torre. Um bot que não
	# come isso está com a avaliação ou a busca desligada.
	var hanging := _position(rules, {
		"a1": [Board.Side.WHITE, Board.Kind.ROOK],
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"a5": [Board.Side.BLACK, Board.Kind.QUEEN],
		"h8": [Board.Side.BLACK, Board.Kind.KING],
	})
	_equals(_bot_move(&"chess", rules, hanging, HARD), "a1-a5", "come a peça de graça")

	# A recaptura é o que a busca de sossego existe para ver: a torre pode comer
	# o peão em a5, mas o peão em b6 recaptura e a troca é péssima. Sem
	# quiescência o bot conta o peão ganho e para de olhar.
	var poisoned := _position(rules, {
		"a1": [Board.Side.WHITE, Board.Kind.ROOK],
		"e1": [Board.Side.WHITE, Board.Kind.KING],
		"a5": [Board.Side.BLACK, Board.Kind.PAWN],
		"b6": [Board.Side.BLACK, Board.Kind.PAWN],
		"h8": [Board.Side.BLACK, Board.Kind.KING],
	})
	var careful := _bot_move(&"chess", rules, poisoned, HARD)
	_check(careful != "a1-a5", "não come o peão envenenado (escolheu %s)" % careful)

	# Da posição inicial, qualquer lance serve — mas tem de ser um lance legal, e
	# tem de sair antes de o jogador desistir de esperar.
	var start := rules.initial_state()
	var opening := _bot_move(&"chess", rules, start, 1)
	_check(not opening.is_empty(), "responde na posição inicial (%s)" % opening)


func _test_bot_checkers() -> void:
	print("bot — damas")
	var rules := CheckersRules.new()

	# Captura dupla contra simples: o material decide sozinho, sem nenhuma regra
	# de damas escrita na busca.
	var state := MatchState.new()
	state.set_piece(_sq("c3"), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	state.set_piece(_sq("g1"), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	state.set_piece(_sq("d4"), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	state.set_piece(_sq("f6"), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	state.set_piece(_sq("h4"), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	state.side_to_move = Board.Side.WHITE
	state.meta = {"idle": 0}
	_equals(_bot_move(&"checkers", rules, state, HARD), "c3-e5-g7", "prefere a captura dupla")

	# Promoção: pedra a um passo da última linha, sem captura à vista. Virar dama
	# é o maior ganho do tabuleiro, e a avaliação tem de dizer isso.
	var promoting := MatchState.new()
	promoting.set_piece(_sq("b7"), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	promoting.set_piece(_sq("a1"), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	promoting.set_piece(_sq("h8"), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	promoting.side_to_move = Board.Side.WHITE
	promoting.meta = {"idle": 0}
	var chosen := _bot_move(&"checkers", rules, promoting, HARD)
	_check(chosen.begins_with("b7-"), "empurra a pedra que promove (escolheu %s)" % chosen)


## O lance escolhido, escrito como `origem-casa-casa`. Sem thread: o teste quer o
## resultado, não a concorrência — e um `--script` não tem laço de quadros para
## consultar a busca.
func _bot_move(game_id: StringName, _rules: Ruleset, state: MatchState, level: int) -> String:
	return _path(_bot_choice(game_id, state, level))


func _bot_choice(game_id: StringName, state: MatchState, level: int) -> Move:
	var bot := Bot.new()
	return bot._decide(game_id, state.clone(), Bot.LEVELS[level])


func _path(move: Move) -> String:
	if move == null:
		return ""
	var names := PackedStringArray()
	for sq in move.path:
		names.append(Board.square_name(sq))
	return "-".join(names)


func _test_qr_structure() -> void:
	print("qr code")
	var code := QrEncoder.encode(QR_SAMPLE)
	var size := int(code["size"])
	var modules: PackedByteArray = code["modules"]

	_equals(size, 29, "versão 3 (29x29) para o payload de pareamento")
	_equals(modules.size(), size * size, "matriz completa")
	_equals(modules[0], 1, "canto do padrão localizador é escuro")
	_equals(modules[7 * size + 0], 0, "separador do localizador é claro")
	_equals(modules[6 * size + 8], 1, "módulo de sincronismo preservado na linha 6")
	_equals(modules[8 * size + 6], 1, "módulo de sincronismo preservado na coluna 6")
	_equals(modules[(size - 8) * size + 8], 1, "módulo escuro obrigatório")
	_check_format_bits(modules, size, int(code["mask"]))
	_check_generator_polynomials()
	_check_known_matrices()


## Os polinômios geradores de Reed-Solomon são constantes publicadas na norma, em
## expoentes de alfa. Conferir contra eles é a única verificação aqui que não
## depende do meu próprio código estar certo.
##
## Existe porque um QR com ECC errado é indistinguível de um correto por
## inspeção: padrões de função, informação de formato, máscara e dados ficam
## todos perfeitos, e só um decodificador de verdade rejeita. Esse bug passou por
## testes estruturais e por revisão até ser pego por um leitor externo.
func _check_generator_polynomials() -> void:
	const PUBLISHED := {
		10: [0, 251, 67, 46, 61, 118, 70, 64, 94, 32, 45],
		16: [0, 120, 104, 107, 109, 102, 161, 76, 3, 91, 191, 147, 169, 182, 194, 225, 120],
		26: [
			0, 173, 125, 158, 2, 103, 182, 118, 17, 145, 201, 111, 28, 165, 53, 161, 21, 245,
			142, 13, 102, 48, 227, 153, 145, 218, 70
		],
	}
	for degree in PUBLISHED:
		var poly := QrEncoder._generator_poly(degree)
		var exponents := []
		for coefficient in poly:
			exponents.append(QrEncoder.alpha_exponent(coefficient))
		_equals(exponents, PUBLISHED[degree], "polinômio gerador de grau %d" % degree)


## Impressão digital da matriz inteira para payloads fixos. Serve de trava contra
## regressão em qualquer etapa do pipeline; os dois valores abaixo foram
## conferidos com um decodificador externo (jsQR) no momento em que foram
## gravados.
func _check_known_matrices() -> void:
	const EXPECTED := {
		"ab": "374aeb80abc9520f6cc62b57f2c1920874ebd1ec5ce547602e4f4088fcf256a5",
		"XDM3|chess|192.168.0.10|8909|ABC123||":
			"b79d332abab51f33a2c86d8149d8d4f28eb1cceb358a6d26ac34c11072e5a8dd",
	}
	for text in EXPECTED:
		var modules: PackedByteArray = QrEncoder.encode(text)["modules"]
		var bits := ""
		for i in modules.size():
			bits += "1" if modules[i] == 1 else "0"
		_equals(bits.sha256_text(), EXPECTED[text], "matriz de %s inalterada" % JSON.stringify(text))


## As 15 strings de informação de formato para o nível M são publicadas na norma.
## O codificador as calcula por BCH; aqui elas são conferidas contra a tabela,
## lendo os módulos de volta da matriz — é o pedaço mais fácil de errar em
## silêncio, porque um leitor de QR rejeita o código inteiro sem dizer por quê.
func _check_format_bits(modules: PackedByteArray, size: int, mask: int) -> void:
	const PUBLISHED := [
		"101010000010010", "101000100100101", "101111001111100", "101101101001011",
		"100010111111001", "100000011001110", "100111110010111", "100101010100000",
	]
	var positions := [
		Vector2i(0, 8), Vector2i(1, 8), Vector2i(2, 8), Vector2i(3, 8), Vector2i(4, 8),
		Vector2i(5, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(8, 7), Vector2i(8, 5),
		Vector2i(8, 4), Vector2i(8, 3), Vector2i(8, 2), Vector2i(8, 1), Vector2i(8, 0),
	]
	var read := ""
	for i in range(positions.size() - 1, -1, -1):
		var at: Vector2i = positions[i]
		read += str(modules[at.x * size + at.y])
	_equals(read, PUBLISHED[mask], "informação de formato (máscara %d)" % mask)


## O payload carrega só o nome da sala: jogo e código. A versão anterior levava
## lista de endereços, porta, SSID e senha, porque a partida era uma ligação
## direta e o convidado precisava saber *onde* estava o anfitrião.
func _test_pairing_payload() -> void:
	print("payload de pareamento")
	var payload := PairingLib.build_payload(&"checkers", "K7QW2M")
	var info := PairingLib.parse_payload(payload)
	_equals(info.get("game"), &"checkers", "jogo")
	_equals(info.get("code"), "K7QW2M", "código")
	_equals(info.size(), 2, "e mais nada")

	_check(PairingLib.parse_payload("qualquer outro qr").is_empty(), "payload estranho é ignorado")
	# O formato antigo tem sete campos. Recusar é o comportamento certo: melhor
	# não entrar do que entrar lendo os campos trocados.
	_check(
		PairingLib.parse_payload("XDM3|chess|10.0.0.5|8909|K7QW2M||").is_empty(),
		"payload do formato antigo é ignorado"
	)
	_check(
		PairingLib.parse_payload("XDM3|chess|ABC").is_empty(),
		"código com tamanho errado é ignorado"
	)
	_equals(
		PairingLib.parse_payload("XDM3|chess|k7qw2m").get("code"),
		"K7QW2M",
		"código minúsculo é normalizado"
	)

	# Sem os endereços o QR cai de versão 3 (29x29) para versão 2 (25x25), e o do
	# formato antigo com credenciais de hotspot chegava à versão 5 (37x37). Um QR
	# menos denso é um QR que a câmera trava de longe, com a tela suja e com
	# pouca luz — que é a condição real de quem lê a tela do outro celular.
	var matrix := QrEncoder.encode(payload)
	_check(
		int(matrix["version"]) <= 2,
		"o payload de sala cabe num QR pouco denso (versão %d)" % int(matrix["version"])
	)


# --- batalha naval -----------------------------------------------------------


func _test_battleship_placement() -> void:
	print("batalha naval posicionamento")
	var rules := BattleshipRules.new()

	_check(
		BattleshipRules.footprint(_sq("g1"), 4, true).is_empty(),
		"navio de 4 não cabe deitado a partir de g1"
	)
	_check(
		BattleshipRules.footprint(_sq("a7"), 3, false).is_empty(),
		"navio de 3 não cabe em pé a partir de a7"
	)
	_equals(
		BattleshipRules.footprint(_sq("c4"), 3, true).size(), 3, "rastro deitado tem 3 casas"
	)

	var fleet := BattleshipRules.empty_grid()
	fleet = BattleshipRules.place(fleet, Board.Kind.CRUISER, _sq("c4"), true)
	_check(
		not BattleshipRules.can_place(fleet, _sq("d1"), 4, false),
		"navio novo não pode cruzar um já posicionado"
	)
	_check(
		BattleshipRules.can_place(fleet, _sq("c5"), 3, true),
		"navio pode encostar no vizinho de cima"
	)

	# Sorteio: qualquer semente tem de sair com a frota inteira e completa. Uma
	# colisão mal tratada some com um navio sem erro nenhum aparecer.
	var rng := RandomNumberGenerator.new()
	for seed_value in 40:
		rng.seed = seed_value
		var random := BattleshipRules.random_fleet(rng)
		var total := 0
		for ship in BattleshipRules.SHIPS:
			var cells := 0
			for sq in Board.SQUARE_COUNT:
				if random[sq] == int(ship["kind"]):
					cells += 1
			if cells != int(ship["size"]):
				_check(false, "semente %d: %s com %d casas" % [seed_value, ship["name"], cells])
			total += cells
		if total != BattleshipRules.FLEET_CELLS:
			_check(false, "semente %d: frota com %d casas" % [seed_value, total])

	var state := rules.initial_state()
	_check(not BattleshipRules.ready(state), "mar vazio não está pronto para jogar")
	_equals(rules.outcome(state), Ruleset.Outcome.ONGOING, "mar vazio não tem vencedor")
	_check(rules.generate_moves(state).is_empty(), "não há tiro antes de posicionar")


func _test_battleship_shots() -> void:
	print("batalha naval tiros")
	var rules := BattleshipRules.new()
	var state := _battleship_position()

	_check(BattleshipRules.ready(state), "as duas frotas posicionadas")
	_equals(rules.generate_moves(state).size(), 64, "todas as casas disponíveis no início")

	# a1 está vazio no mar das pretas; b1 é a proa do destroier.
	_equals(rules.notation(state, _shot("a1")), "a1", "tiro n'água é só a coordenada")
	rules.apply_move(state, _shot("a1"))
	_equals(
		BattleshipRules.shots_of(state, Board.Side.WHITE)[_sq("a1")],
		BattleshipRules.Shot.MISS,
		"o tiro n'água ficou gravado"
	)
	_equals(state.side_to_move, Board.Side.BLACK, "acertar ou não, a vez passa")

	state.side_to_move = Board.Side.WHITE
	_equals(rules.generate_moves(state).size(), 63, "a casa já visitada sai da lista")
	_equals(rules.notation(state, _shot("b1")), "b1 ×", "acerto sem afundar não diz o navio")
	rules.apply_move(state, _shot("b1"))

	state.side_to_move = Board.Side.WHITE
	_equals(
		rules.notation(state, _shot("c1")),
		"c1 afundou Destroier",
		"o último acerto do navio revela o nome"
	)
	rules.apply_move(state, _shot("c1"))
	_equals(
		BattleshipRules.ships_afloat(state, Board.Side.BLACK), 3, "restam três navios pretos"
	)
	_equals(rules.outcome(state), Ruleset.Outcome.ONGOING, "afundar um navio não encerra")

	# Varre o mar inteiro: no fim, só a frota preta caiu.
	for sq in Board.SQUARE_COUNT:
		state.side_to_move = Board.Side.WHITE
		if BattleshipRules.shots_of(state, Board.Side.WHITE)[sq] == BattleshipRules.Shot.NONE:
			var move := Move.new()
			move.path = PackedInt32Array([sq])
			rules.apply_move(state, move)
	_equals(rules.outcome(state), Ruleset.Outcome.WHITE_WINS, "frota preta afundada encerra")
	_equals(BattleshipRules.ships_afloat(state, Board.Side.WHITE), 4, "a frota branca ficou intacta")


## Frotas fixas nos dois lados, para os testes não dependerem de sorteio. As
## pretas começam com o destroier em b1-c1, que é o navio afundado no teste.
func _battleship_position() -> MatchState:
	var rules := BattleshipRules.new()
	var state := rules.initial_state()
	for side in [Board.Side.WHITE, Board.Side.BLACK]:
		var fleet := BattleshipRules.empty_grid()
		fleet = BattleshipRules.place(fleet, Board.Kind.DESTROYER, _sq("b1"), true)
		fleet = BattleshipRules.place(fleet, Board.Kind.SUBMARINE, _sq("a3"), true)
		fleet = BattleshipRules.place(fleet, Board.Kind.CRUISER, _sq("f2"), false)
		fleet = BattleshipRules.place(fleet, Board.Kind.BATTLESHIP, _sq("d5"), true)
		BattleshipRules.set_fleet(state, side, fleet)
	return state


func _shot(name: String) -> Move:
	var move := Move.new()
	move.path = PackedInt32Array([_sq(name)])
	return move


# --- versão do build ---------------------------------------------------------


## O rodapé lê o carimbo deixado pela exportação, e cai no `project.godot` quando
## ele não existe. As duas metades importam: sem o carimbo o APK se apresentaria
## com a versão errada, e sem o fallback o rodapé ficaria vazio no editor.
func _test_app_version() -> void:
	print("versão do build")
	var project := str(ProjectSettings.get_setting("application/config/version", "?"))
	var stamp := "user://version_probe.txt"

	_equals(AppVersion.read(stamp), project, "sem carimbo, vale a versão do projeto")

	_write(stamp, "9.9-teste")
	_equals(AppVersion.read(stamp), "9.9-teste", "com carimbo, vale o que foi exportado")

	# Preset sem `version/name` preenchido carimba string vazia; isso não pode
	# virar um rodapé com "v" e mais nada.
	_write(stamp, "   \n")
	_equals(AppVersion.read(stamp), project, "carimbo vazio volta para a versão do projeto")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(stamp))


## O nome do jogador sobrevive ao fechamento do app, e o padrão preenche o lugar
## dele enquanto ninguém escolheu — que é o estado em que a maioria vai jogar.
func _test_prefs() -> void:
	print("preferências")
	var backup := Prefs.player_name() if Prefs.has_name() else ""

	Prefs.set_player_name("")
	_equals(Prefs.player_name(), Prefs.DEFAULT_NAME, "sem escolha, vale o padrão")
	_check(not Prefs.has_name(), "e a tela sabe que ainda não é uma escolha")

	Prefs.set_player_name("  Lucas  ")
	_equals(Prefs.player_name(), "Lucas", "espaços das pontas não entram no nome")
	_check(Prefs.has_name(), "e agora há escolha")

	# Releitura do disco: é o que separa "guardei" de "lembrei enquanto o app
	# estava aberto", e só o primeiro é a promessa da tela de ajustes.
	Prefs.forget()
	_equals(Prefs.player_name(), "Lucas", "o nome sobrevive a uma leitura nova do arquivo")

	Prefs.set_player_name("x".repeat(Prefs.NAME_LIMIT + 9))
	_equals(
		Prefs.player_name().length(), Prefs.NAME_LIMIT,
		"nome comprido é cortado no limite do cartão"
	)

	Prefs.set_player_name("   ")
	_check(not Prefs.has_name(), "só espaços é o mesmo que apagar o nome")

	Prefs.set_player_name(backup)


func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()
