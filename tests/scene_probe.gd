extends Node

## Teste da camada de cena, que o `test_runner.gd` não alcança: ele roda com
## `--script`, onde os autoloads não existem e portanto `match.tscn` nem carrega.
##
##   godot --headless --path . res://tests/scene_probe.tscn
##
## Existe por causa de um bug real: duas linhas de `_refresh()` foram parar
## dentro de outra função numa edição, e os rótulos pararam de acompanhar o
## estado. O tabuleiro continuava certo, então nada acusou — o jogador via "Vez
## das brancas" com as pretas em xeque e concluía que o jogo travou.

var _failures := 0


func _ready() -> void:
	Game.start_hotseat(Game.CHESS)
	var match_scene := preload("res://scenes/match.tscn").instantiate()
	add_child(match_scene)
	await get_tree().process_frame

	_test_initial_labels(match_scene)
	_test_check_position(match_scene)
	_test_castling(match_scene)
	await _test_history_and_captures(match_scene)
	_test_opponent_left(match_scene)
	await _test_clock(match_scene)
	_test_table_mode(match_scene)
	_test_drag(match_scene)
	await _test_checkers_capture_taps()
	await _test_rematch()
	await _test_spectator()
	await _test_premove()
	await _test_premove_limit()
	await _test_bot()
	await _test_battleship()
	_test_back_navigation()
	await _test_match_bar()
	await _test_match_status()
	await _test_welcome()

	if _failures == 0:
		print("OK — camada de cena consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## No mesmo aparelho o cartão de baixo é sempre o das brancas, e o aceso é o de
## quem joga. Antes isto conferia um rótulo `%TurnLabel` que não existe mais na
## cena: `get_node` devolvia null, o acesso a `.text` abortava a função inteira
## antes de qualquer asserção rodar, e o arquivo terminava anunciando sucesso
## sem ter testado nada. Daí o `_node()` abaixo.
func _test_initial_labels(match_scene: Node) -> void:
	print("cena inicial")
	var top: PlayerTag = _node(match_scene, "%TopTag")
	var bottom: PlayerTag = _node(match_scene, "%BottomTag")
	_equals(bottom.title, "Brancas", "cartão de baixo é o das brancas")
	_equals(top.title, "Pretas", "cartão de cima é o das pretas")
	_check(bottom.active, "brancas começam com a vez")
	_check(not top.active, "pretas esperam")
	# O botão de revanche mora dentro do painel de fim de partida; o que precisa
	# estar escondido no começo é o painel.
	_equals(_node(match_scene, "%ResultLayer").visible, false, "painel de fim de partida escondido")
	_equals(_node(match_scene, "%TopLastMoveSlot").visible, false, "linha de último lance vazia no início")
	_equals(_node(match_scene, "%BottomLastMoveSlot").visible, false, "as duas")


## Bispo em b5 dando xeque no rei preto em e8, coluna d aberta para a dama
## branca. As pretas têm exatamente 4 respostas; as outras 12 peças não podem
## mover, e é justamente aí que a interface precisa falar.
func _test_check_position(match_scene: Node) -> void:
	print("posição de xeque")
	var state: MatchState = match_scene._state
	state.squares = Board.empty_squares()
	for square in ["a7", "b7", "c7", "e7", "f7", "g7", "h7"]:
		_put(state, square, Board.Side.BLACK, Board.Kind.PAWN)
	_put(state, "a8", Board.Side.BLACK, Board.Kind.ROOK)
	_put(state, "b8", Board.Side.BLACK, Board.Kind.KNIGHT)
	_put(state, "c8", Board.Side.BLACK, Board.Kind.BISHOP)
	_put(state, "e8", Board.Side.BLACK, Board.Kind.KING)
	_put(state, "f8", Board.Side.BLACK, Board.Kind.BISHOP)
	_put(state, "g8", Board.Side.BLACK, Board.Kind.KNIGHT)
	_put(state, "h8", Board.Side.BLACK, Board.Kind.ROOK)
	_put(state, "f4", Board.Side.BLACK, Board.Kind.QUEEN)
	for square in ["a2", "b2", "c2", "h2"]:
		_put(state, square, Board.Side.WHITE, Board.Kind.PAWN)
	_put(state, "a1", Board.Side.WHITE, Board.Kind.ROOK)
	_put(state, "b1", Board.Side.WHITE, Board.Kind.KNIGHT)
	_put(state, "c1", Board.Side.WHITE, Board.Kind.BISHOP)
	_put(state, "d1", Board.Side.WHITE, Board.Kind.QUEEN)
	_put(state, "e1", Board.Side.WHITE, Board.Kind.KING)
	_put(state, "g1", Board.Side.WHITE, Board.Kind.KNIGHT)
	_put(state, "h1", Board.Side.WHITE, Board.Kind.ROOK)
	_put(state, "b5", Board.Side.WHITE, Board.Kind.BISHOP)
	state.side_to_move = Board.Side.BLACK
	match_scene._recompute()

	var top: PlayerTag = _node(match_scene, "%TopTag")
	var bottom: PlayerTag = _node(match_scene, "%BottomTag")
	_check(top.active, "a vez passou para o cartão das pretas")
	_check(not bottom.active, "cartão das brancas apagou")
	_check(top.alert, "cartão das pretas anuncia o xeque")
	_equals(Board.square_name(match_scene._board.check_square), "e8", "rei em xeque destacado")
	_equals(match_scene._legal.size(), 4, "quatro respostas ao xeque")
	_equals(match_scene._outcome, Ruleset.Outcome.ONGOING, "partida em andamento")

	# Uma peça sem lance legal precisa dizer por quê, não ficar muda. A
	# explicação vai para o banner sobre o tabuleiro, e `_hint` é o que o
	# alimenta — a linha de status embaixo ficou só com o contexto da partida.
	match_scene._on_square_tapped(_square("f4"))
	_check(
		match_scene._hint.contains("xeque") or match_scene._hint.contains("lance legal"),
		"peça travada explica o motivo (obtido: '%s')" % match_scene._hint
	)
	_check(match_scene._selection.is_empty(), "peça sem lance não fica selecionada")

	# Uma que pode responder seleciona normalmente e limpa o aviso.
	match_scene._on_square_tapped(_square("c7"))
	_equals(match_scene._selection.size(), 1, "peça com lance é selecionada")
	_check(match_scene._hint.is_empty(), "aviso some ao selecionar uma peça válida")


## Roque pelo toque: o jogador toca no rei e depois na casa de destino. Muita
## gente toca na torre, então esse caminho também é verificado.
func _test_castling(match_scene: Node) -> void:
	print("roque")
	var state: MatchState = match_scene._state
	state.squares = Board.empty_squares()
	_put(state, "e1", Board.Side.WHITE, Board.Kind.KING)
	_put(state, "a1", Board.Side.WHITE, Board.Kind.ROOK)
	_put(state, "h1", Board.Side.WHITE, Board.Kind.ROOK)
	_put(state, "e8", Board.Side.BLACK, Board.Kind.KING)
	_put(state, "a8", Board.Side.BLACK, Board.Kind.ROOK)
	state.side_to_move = Board.Side.WHITE
	state.meta = {"castle": ChessRules.CASTLE_ALL, "ep": Board.NO_SQUARE, "halfmove": 0}
	match_scene._recompute()

	var castles := 0
	for move in match_scene._legal:
		if move.tags.has("castle"):
			castles += 1
	_equals(castles, 2, "dois roques gerados")

	# Toca no rei: g1 e c1 devem aparecer como destinos.
	match_scene._selection = PackedInt32Array()
	match_scene._on_square_tapped(_square("e1"))
	_equals(match_scene._selection.size(), 1, "rei selecionado")
	_check(match_scene._board.targets.has(_square("g1")), "g1 oferecido como destino")
	_check(match_scene._board.targets.has(_square("c1")), "c1 oferecido como destino")

	# Toca na torre em vez da casa de destino.
	match_scene._on_square_tapped(_square("h1"))
	_check(
		Board.kind_of(state.piece_at(_square("g1"))) == Board.Kind.KING,
		"tocar na torre também roca (rei em g1: %s)" % Board.square_name(
			state.find_piece(Board.Side.WHITE, Board.Kind.KING)
		)
	)

	# Mesma coisa do lado da dama, que usa a outra casa de torre.
	state.squares = Board.empty_squares()
	_put(state, "e1", Board.Side.WHITE, Board.Kind.KING)
	_put(state, "a1", Board.Side.WHITE, Board.Kind.ROOK)
	_put(state, "e8", Board.Side.BLACK, Board.Kind.KING)
	state.side_to_move = Board.Side.WHITE
	state.meta = {"castle": ChessRules.CASTLE_ALL, "ep": Board.NO_SQUARE, "halfmove": 0}
	match_scene._selection = PackedInt32Array()
	match_scene._recompute()
	match_scene._on_square_tapped(_square("e1"))
	match_scene._on_square_tapped(_square("a1"))
	_equals(
		Board.square_name(state.find_piece(Board.Side.WHITE, Board.Kind.KING)),
		"c1",
		"roque grande pela torre"
	)

	# E o caminho canônico: rei e depois a casa de destino.
	state.squares = Board.empty_squares()
	_put(state, "e1", Board.Side.WHITE, Board.Kind.KING)
	_put(state, "h1", Board.Side.WHITE, Board.Kind.ROOK)
	_put(state, "e8", Board.Side.BLACK, Board.Kind.KING)
	state.side_to_move = Board.Side.WHITE
	state.meta = {"castle": ChessRules.CASTLE_ALL, "ep": Board.NO_SQUARE, "halfmove": 0}
	match_scene._selection = PackedInt32Array()
	match_scene._recompute()
	match_scene._on_square_tapped(_square("e1"))
	match_scene._on_square_tapped(_square("g1"))
	_equals(Board.square_name(state.find_piece(Board.Side.WHITE, Board.Kind.KING)), "g1", "rei foi para g1")
	_equals(Board.square_name(state.find_piece(Board.Side.WHITE, Board.Kind.ROOK)), "f1", "torre foi para f1")


## O histórico e as peças capturadas são derivados de `_state.history`, não
## guardados em paralelo — então o que precisa ser verificado é que a derivação
## acompanha o jogo, inclusive quando a partida é reconstruída por um resync.
func _test_history_and_captures(match_scene: Node) -> void:
	print("histórico e capturas")
	match_scene._new_game()

	# 1. e4 e5 2. Cf3 Cc6 3. Bb5 a6 — a espanhola até o lance que ganha material.
	for step in [["e2", "e4"], ["e7", "e5"], ["g1", "f3"], ["b8", "c6"], ["f1", "b5"], ["a7", "a6"]]:
		_play(match_scene, step[0], step[1])
	_equals(
		" ".join(match_scene._notation),
		"e4 e5 Cf3 Cc6 Bb5 a6",
		"abertura anotada em português"
	)

	var top: PlayerTag = _node(match_scene, "%TopTag")
	var bottom: PlayerTag = _node(match_scene, "%BottomTag")
	_check(top.captured.is_empty(), "nenhuma peça capturada no cartão de cima")
	_check(bottom.captured.is_empty(), "nem no de baixo")

	# 4. Bxc6: o bispo branco come o cavalo preto. No mesmo aparelho o cartão de
	# baixo é o das brancas, então é ele que ganha a peça.
	_play(match_scene, "b5", "c6")
	_equals(match_scene._notation[6], "Bxc6", "captura anotada com x")
	_equals(bottom.captured.size(), 1, "uma peça no cartão das brancas")
	_equals(Board.kind_of(bottom.captured[0]), Board.Kind.KNIGHT, "a peça capturada é o cavalo")
	_equals(bottom.advantage, 3, "cavalo vale 3 de vantagem")
	_check(top.captured.is_empty(), "as pretas ainda não comeram nada")

	# 4... dxc6 devolve o material: com o bispo valendo o mesmo, a vantagem zera
	# dos dois lados e nenhum "+N" deve sobrar na tela.
	_play(match_scene, "d7", "c6")
	_equals(match_scene._notation[7], "dxc6", "recaptura de peão leva a coluna")
	_equals(top.captured.size(), 1, "uma peça no cartão das pretas")
	_equals(top.advantage, 0, "material igual não mostra vantagem para as pretas")
	_equals(bottom.advantage, 0, "nem para as brancas")

	# A linha mostra o último lance e a peça que o fez — a de destino, não a de
	# origem: depois de uma promoção quem chegou lá é a peça nova, e é dela que a
	# notação fala. No mesmo aparelho ela aparece dos dois lados, com o mesmo
	# conteúdo: quem jogou já sabe o que jogou, quem precisa da informação é o
	# outro, e ele está do outro lado do aparelho.
	var top_line: LastMoveLine = _node(match_scene, "%TopLastMove")
	var bottom_line: LastMoveLine = _node(match_scene, "%BottomLastMove")
	var top_slot: Control = _node(match_scene, "%TopLastMoveSlot")
	var bottom_slot: Control = _node(match_scene, "%BottomLastMoveSlot")
	_check(top_slot.visible and bottom_slot.visible, "a linha aparece dos dois lados")
	_check(is_equal_approx(top_line.rotation, PI), "a de cima virada para o outro jogador")
	_equals(bottom_line.rotation, 0.0, "a de baixo em pé")
	_equals(top_line.notation, "dxc6", "linha mostra o lance mais recente")
	_equals(bottom_line.notation, "dxc6", "as duas com o mesmo lance")
	_equals(Board.side_of(top_line.piece), Board.Side.BLACK, "e a cor de quem jogou")
	_equals(Board.kind_of(top_line.piece), Board.Kind.PAWN, "com a peça que se moveu")

	# Lance das brancas: as duas linhas acompanham, nenhuma se apaga.
	_play(match_scene, "b1", "c3")
	_equals(top_line.notation, "Cc3", "lance das brancas atualiza a de cima")
	_equals(bottom_line.notation, "Cc3", "e a de baixo")
	_play(match_scene, "d8", "d7")
	var line := top_line

	# Resync: a partida é reconstruída do zero a partir da lista de lances, e o
	# histórico e as capturas têm de vir junto. Um `_notation` que só soubesse
	# crescer sobreviveria a isto descrevendo a partida errada.
	var played: Array = match_scene._state.history.duplicate(true)
	match_scene._new_game()
	_equals(match_scene._notation.size(), 0, "partida nova zera o histórico")
	_check(bottom.captured.is_empty(), "e as peças capturadas")
	match_scene._apply_sync(played)
	_equals(
		" ".join(match_scene._notation),
		"e4 e5 Cf3 Cc6 Bb5 a6 Bxc6 dxc6 Cc3 Dd7",
		"resync reconstrói o histórico inteiro"
	)
	_equals(bottom.captured.size(), 1, "resync reconstrói as capturas das brancas")
	_equals(top.captured.size(), 1, "e as das pretas")
	_equals(line.notation, "Dd7", "e a linha de último lance, do lado certo")
	await get_tree().process_frame


## Abandono é um desfecho: o painel tem que aparecer, sem oferecer revanche, e o
## tabuleiro tem que parar de aceitar toques. Antes isso era só um aviso
## flutuante, e o tabuleiro continuava respondendo a toques que não iam a lugar
## nenhum.
func _test_opponent_left(match_scene: Node) -> void:
	print("oponente saiu")
	match_scene._new_game()
	match_scene._on_opponent_left()

	_check(match_scene.get_node("%ResultLayer").visible, "painel de fim de partida aparece")
	_equals(match_scene.get_node("%ResultTitle").text, "O oponente saiu", "título do painel")
	_equals(match_scene.get_node("%RematchButton").visible, false, "sem revanche contra ninguém")

	match_scene._selection = PackedInt32Array()
	match_scene._on_square_tapped(_square("e2"))
	_check(match_scene._selection.is_empty(), "tabuleiro deixa de aceitar toques")

	match_scene._new_game()
	_equals(match_scene.get_node("%ResultLayer").visible, false, "revanche limpa o painel")


## Modo mesa: o aparelho fica deitado entre os dois jogadores, e o que gira é o
## que pertence a quem está do outro lado — as peças dele e o cartão dele. O
## tabuleiro, as coordenadas e os destaques ficam parados: girar tudo seria a
## mesma tela ao contrário, que resolve para um e quebra para o outro.
func _test_table_mode(match_scene: Node) -> void:
	print("modo mesa")
	var board: BoardView = match_scene._board
	_check(board.table_mode, "ligado no jogo no mesmo aparelho")
	var top_card: PlayerTag = _node(match_scene, "%TopTag")
	_check(top_card.upside_down, "o cartão de cima vira")
	_check(is_equal_approx(top_card.rotation, PI), "e a rotação chega ao nó (%f)" % top_card.rotation)
	_check(top_card.pivot_offset.x > 0.0, "com o pivô no centro (%s)" % top_card.pivot_offset)
	_check(not _node(match_scene, "%BottomTag").upside_down, "o de baixo não")

	_check(
		board._turned(Board.piece(Board.Side.BLACK, Board.Kind.PAWN)),
		"peça de quem está do outro lado gira"
	)
	_check(
		not board._turned(Board.piece(Board.Side.WHITE, Board.Kind.PAWN)),
		"peça de quem está deste lado fica em pé"
	)
	_check(not board._turned(0), "casa vazia não gira nada")

	# Em rede as pretas veem o tabuleiro do lado delas (`flipped`), e quem fica em
	# pé acompanha a orientação. Não há mais botão para girar, mas a regra
	# continua ligada à orientação e não à cor.
	board.flipped = true
	_check(
		board._turned(Board.piece(Board.Side.WHITE, Board.Kind.PAWN)),
		"com o tabuleiro girado quem vira é o outro lado"
	)
	board.flipped = false

	# Em rede cada um olha a própria tela: nada vira.
	board.table_mode = false
	_check(
		not board._turned(Board.piece(Board.Side.BLACK, Board.Kind.PAWN)),
		"fora do modo mesa nenhuma peça gira"
	)
	board.table_mode = true


## Arrastar a peça é o mesmo lance do toque duplo, feito num gesto só: a casa de
## origem sai na descida do dedo, a de destino na subida — e são exatamente as
## duas casas que os dois toques emitiriam. É por isso que as regras não sabem
## que o arrasto existe, e é isso que estes testes protegem.
func _test_drag(match_scene: Node) -> void:
	print("arrastar a peça")
	match_scene._new_game()
	var board: BoardView = match_scene._board
	board.layout()
	_check(board._cell > 0.0, "o tabuleiro tem tamanho (casa de %.1f px)" % board._cell)

	var from := board.rect_of(_square("e2")).get_center()
	var to := board.rect_of(_square("e4")).get_center()

	board._gui_input(_press(from))
	_equals(match_scene._selection.size(), 1, "a descida do dedo já seleciona, como o toque")
	_equals(board._drag_square, _square("e2"), "e arma o arrasto na peça pega")

	# Dedo nenhum fica parado. Abaixo do limiar continua sendo toque simples,
	# senão a peça sairia da casa por um tremor de dois pixels.
	board._input(_motion(board, from + Vector2(1.0, 1.0)))
	_check(not board.dragging, "um tremor não vira arrasto")
	board._input(_motion(board, to))
	_check(board.dragging, "andar além do limiar vira arrasto")

	board._input(_release(board, to))
	_equals(match_scene._state.ply, 1, "soltar no destino joga o lance")
	_equals(Board.square_name(match_scene._state.history[0]["p"][1]), "e4", "o peão foi para e4")
	_check(not board.dragging, "e o arrasto termina")
	_equals(board._pointer, "", "com o gesto liberado para o próximo")

	# Soltar de volta na origem não é lance: desistir de um arrasto não pode
	# custar a seleção, senão o jogador teria de recomeçar do zero.
	var origin := board.rect_of(_square("e7")).get_center()
	board._gui_input(_press(origin))
	board._input(_motion(board, origin + Vector2(0.0, board._cell)))
	board._input(_release(board, origin))
	_equals(match_scene._state.ply, 1, "voltar para a origem não joga nada")
	_equals(match_scene._selection.size(), 1, "e a peça continua selecionada")

	# O Android manda o toque e ainda a emulação de mouse do mesmo dedo. Sem a
	# trava de origem, um gesto só soltaria o lance duas vezes — e a segunda
	# cairia na casa de destino selecionando a peça que acabou de chegar.
	var target := board.rect_of(_square("e5")).get_center()
	board._gui_input(_press(origin))
	board._input(_mouse_motion(board, target))
	_check(not board.dragging, "o mouse emulado não entra num gesto de toque")
	board._input(_motion(board, target))
	_check(board.dragging, "mas o toque continua o gesto")
	board._input(_mouse_release(board, target))
	_equals(match_scene._state.ply, 1, "a soltura emulada não joga nada")
	board._input(_release(board, target))
	_equals(match_scene._state.ply, 2, "o lance sai uma vez só, no evento de toque")


## Captura encadeada pelo toque, que é onde a regra certa parecia um jogo
## quebrado: as regras geravam a sequência dupla, mas tocar na casa de destino
## não movia nada — a sequência ainda não tinha terminado — e a tela não dizia
## isso. Da cadeira do jogador, o lance tinha sido recusado.
func _test_checkers_capture_taps() -> void:
	print("damas captura pelo toque")
	Game.start_hotseat(Game.CHECKERS)
	var scene := preload("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	# Rota única: c3 come d4 caindo em e5, e de e5 só resta comer f6 até g7.
	# Sem escolha a fazer, um toque em e5 tem de resolver o lance inteiro.
	_lay_out(scene, ["c3"], ["d4", "f6"])
	scene._on_square_tapped(_square("c3"))
	_equals(scene._selection.size(), 1, "a pedra é selecionada")
	_check(scene._board.capture_targets.has(_square("e5")), "e5 é oferecido como captura")

	scene._on_square_tapped(_square("e5"))
	_equals(scene._state.ply, 1, "um toque no destino resolve a captura forçada")
	_equals(
		Board.kind_of(scene._state.squares[_square("g7")]),
		Board.Kind.MAN,
		"a pedra terminou em g7, no fim da sequência"
	)
	_equals(scene._notation[0], "c3xe5xg7", "e as duas capturas ficam na notação")

	# Rota dupla: de e5 dá para ir por d6 (até c7) ou por f6 (até g7). Aí existe
	# escolha de verdade, e o toque a mais é o jogador escolhendo — mas a tela
	# tem de dizer que a captura continua.
	_lay_out(scene, ["c3"], ["d4", "d6", "f6"])
	scene._on_square_tapped(_square("c3"))
	scene._on_square_tapped(_square("e5"))
	_equals(scene._state.ply, 0, "com duas rotas, o lance espera a escolha")
	_equals(scene._selection.size(), 2, "e a selecção guarda o caminho já andado")
	_check(scene._hint.contains("continua"), "a tela avisa que a captura continua")
	_check(scene._board.capture_targets.has(_square("c7")), "c7 é oferecido")
	_check(scene._board.capture_targets.has(_square("g7")), "g7 também")

	scene._on_square_tapped(_square("g7"))
	_equals(scene._state.ply, 1, "escolhida a rota, o lance acontece")

	scene.queue_free()
	await get_tree().process_frame


## Revanche em rede é convite: quem pede espera, quem recebe decide, e as cores
## trocam. Antes um toque reiniciava os dois lados na hora — o outro jogador era
## arrastado para um tabuleiro novo sem ter sido consultado, e quem começou de
## brancas começava de brancas para sempre.
func _test_rematch() -> void:
	print("revanche")
	Game.mode = Game.Mode.ONLINE
	Game.local_side = Board.Side.WHITE
	Net.local_side = Board.Side.WHITE
	Game.game_id = Game.CHESS
	var scene := preload("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	var button: Button = _node(scene, "%RematchButton")
	var decline: Button = _node(scene, "%RematchDeclineButton")
	scene._on_opponent_left()
	_equals(button.visible, false, "sem revanche contra quem saiu")

	# Nós pedimos: o botão vira espera, e a partida não recomeça sozinha.
	scene._new_game()
	scene._show_overlay("Fim", "", true)
	scene._request_rematch()
	_equals(scene._rematch, scene.Rematch.ASKED, "o pedido fica pendente")
	_check(button.disabled, "o botão espera a resposta")
	_equals(scene._state.ply, 0, "e nada recomeça antes dela")
	_equals(Game.local_side, Board.Side.WHITE, "as cores só trocam quando aceitam")

	# Ele aceita: aí sim recomeça, com as cores trocadas.
	scene._on_rematch_accepted()
	_equals(scene._rematch, scene.Rematch.IDLE, "o convite se resolve")
	_equals(Game.local_side, Board.Side.BLACK, "quem era brancas joga de pretas")
	_equals(scene._board.flipped, true, "e o tabuleiro vira junto")

	# Na revanche quem abriu (assento 0) joga de pretas, e o primeiro lance de
	# brancas vem do assento 1. Com a conta fixa "assento 0 é brancas" ele era
	# recusado como "não é a vez dele", e a revanche travava no primeiro lance.
	Net.local_seat = 0
	Net.player_names = {0: "Ana", 1: "Bia"}
	_equals(scene._opponent_name(), "Bia", "o cartão do oponente segue o assento dele")
	var e4 := {"p": [_square("e2"), _square("e4")], "pr": 0, "n": 0}
	scene._on_remote_move(e4.merged({"seat": 0}))
	_equals(scene._state.ply, 0, "lance de brancas vindo do nosso assento é recusado")
	scene._on_remote_move(e4.merged({"seat": 1}))
	_equals(scene._state.ply, 1, "e o do assento que joga de brancas entra")
	Net.player_names = {}

	# Ele pede: a resposta é nossa, e recusar não recomeça nada.
	scene._show_overlay("Fim", "", true)
	scene._on_rematch_requested()
	_equals(scene._rematch, scene.Rematch.INVITED, "o convite dele fica pendente")
	_check(decline.visible, "e aparece como pergunta, com recusa")
	scene._decline_rematch()
	_equals(scene._rematch, scene.Rematch.IDLE, "recusar encerra o convite")
	_equals(Game.local_side, Board.Side.BLACK, "sem trocar cor nenhuma")

	# Os dois clicam quase juntos: é acordo, não dois pedidos empacados.
	scene._show_overlay("Fim", "", true)
	scene._request_rematch()
	scene._on_rematch_requested()
	_equals(scene._rematch, scene.Rematch.IDLE, "pedidos cruzados viram acordo")
	_equals(Game.local_side, Board.Side.WHITE, "e a cor troca uma vez só")

	scene.queue_free()
	await get_tree().process_frame
	Game.mode = Game.Mode.HOTSEAT


## Quem assiste: o tabuleiro não responde ao toque, os cartões têm o nome de
## quem joga, e a revanche dos jogadores é seguida com as cores trocadas — uma
## vez só, mesmo quando os dois mandam o aceite.
func _test_spectator() -> void:
	print("espectador")
	Game.mode = Game.Mode.ONLINE
	Game.game_id = Game.CHESS
	Net.is_spectator = true
	Net.connected = true
	Net.white_seat = 1
	Net.player_names = {0: "Ana", 1: "Bia"}
	var scene := preload("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	_equals(scene._board.flipped, false, "brancas embaixo")
	scene._on_square_tapped(_square("e2"))
	_check(
		scene._selection.is_empty() and scene._premove_pick == Board.NO_SQUARE,
		"o toque não seleciona nem planeja nada"
	)
	_equals(_node(scene, "%BottomTag").title, "Bia", "o cartão de baixo é de quem joga de brancas")
	_equals(_node(scene, "%TopTag").title, "Ana", "e o de cima, de quem joga de pretas")

	var e4 := {"p": [_square("e2"), _square("e4")], "pr": 0, "n": 0}
	scene._on_remote_move(e4.merged({"seat": 0}))
	_equals(scene._state.ply, 0, "lance de brancas vindo de quem joga de pretas é recusado")
	scene._on_remote_move(e4.merged({"seat": 1}))
	_equals(scene._state.ply, 1, "e o de quem joga de brancas entra")

	scene._on_rematch_accepted()
	_equals(scene._state.ply, 1, "aceite de revanche com a partida em curso é ignorado")

	scene._flag(Board.Side.BLACK)
	_check(not _node(scene, "%RematchButton").visible, "sem botão de revanche para quem assiste")
	_check(
		_node(scene, "%ResultDetail").text.begins_with("Pretas"),
		"o resultado é contado pelas cores, e não por 'você'"
	)
	scene._on_rematch_accepted()
	_equals(Net.white_seat, 0, "a revanche dos jogadores troca as cores de quem assiste")
	_equals(scene._state.ply, 0, "e começa a partida nova")
	_equals(_node(scene, "%BottomTag").title, "Ana", "com os nomes no lado certo")
	scene._on_rematch_accepted()
	_equals(Net.white_seat, 0, "o segundo aceite de um pedido cruzado não troca de novo")

	# A revanche que ele não viu (caiu bem na hora): o histórico mais curto manda.
	scene._apply_sync([{"p": [12, 28], "pr": 0}, {"p": [52, 36], "pr": 0}])
	_equals(scene._state.ply, 2, "o histórico de quem joga é adotado")
	scene._apply_sync([])
	_equals(scene._state.ply, 0, "mesmo quando é mais curto que o de quem assiste")

	# O contador da barra, que é o que os jogadores veem.
	Net.watchers_changed.emit(2)
	var caption: Label = scene._match_status._watchers
	_check(caption.visible and caption.text == "2 assistindo", "a barra conta quem assiste")
	Net.watchers_changed.emit(0)
	_check(not caption.visible, "e some quando ninguém assiste")

	scene.queue_free()
	await get_tree().process_frame
	Net.is_spectator = false
	Net.white_seat = 0
	Net.player_names = {}
	Game.mode = Game.Mode.HOTSEAT


## Pré-movimento: o lance escolhido enquanto o oponente pensa, que sai sozinho no
## instante em que a vez chega. O que importa aqui é que ele seja um *plano* e
## não um lance adiantado — o tabuleiro não pode mexer antes da hora, e o plano
## tem de ser revalidado contra a posição que o oponente deixou, não contra a que
## havia quando foi montado.
func _test_premove() -> void:
	print("lance planejado")
	Game.mode = Game.Mode.ONLINE
	Game.local_side = Board.Side.WHITE
	Net.local_side = Board.Side.WHITE
	Net.connected = true
	Game.game_id = Game.CHESS
	var scene := preload("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	_check(not scene._premove_allowed(), "na própria vez não há o que planejar")
	_play(scene, "e2", "e4")
	_check(scene._premove_allowed(), "na vez do oponente sim")

	scene._on_square_tapped(_square("d7"))
	_equals(scene._premove_pick, Board.NO_SQUARE, "peça do oponente não é nossa para planejar")
	scene._on_square_tapped(_square("d2"))
	_equals(scene._premove_pick, _square("d2"), "peça nossa é erguida")
	_check(scene._board.targets.has(_square("d4")), "com os destinos que ela teria na nossa vez")
	# E **sem** o *en passant* do nosso próprio avanço duplo.
	#
	# O plano é montado numa cópia do estado com a vez trocada, e o `ep` que está
	# escrito ali veio do lance anterior — que é nosso, porque agora é a vez do
	# outro. Com a vez trocada e o campo intacto, o peão de d2 ganhava uma
	# diagonal grátis para e3: um destino que a revalidação depois recusa, e que o
	# jogador não tem como entender ter sido oferecido.
	# As duas listas, e a segunda é a que importa: o lance fantasma carrega uma
	# casa em `captured`, então ele entrava em `capture_targets` e a tela marcava
	# e3 como **captura** — uma peça inimiga que não existe, na casa por onde o
	# nosso próprio peão acabou de passar.
	_check(
		not scene._board.targets.has(_square("e3"))
		and not scene._board.capture_targets.has(_square("e3")),
		"e sem a diagonal fantasma do nosso próprio avanço duplo"
	)

	scene._on_square_tapped(_square("d4"))
	_equals(scene._premove_pick, Board.NO_SQUARE, "escolhido o destino, a peça baixa")
	_equals(scene._premove.size(), 2, "e o plano fica armado")
	_equals(scene._state.ply, 1, "sem mexer no tabuleiro, que ainda é do oponente")
	_check(scene._board.premove.has(_square("d2")), "a casa de origem fica marcada")
	_check(scene._board.premove.has(_square("d4")), "e a de destino")

	# Um toque fora de peça nossa apaga o último elo — com um elo só, é o gesto de
	# sempre: cancelar o plano.
	scene._on_square_tapped(_square("h5"))
	_check(scene._premove.is_empty(), "tocar em outro lugar cancela o plano")
	scene._on_square_tapped(_square("d2"))
	scene._on_square_tapped(_square("d4"))

	# Chega o lance do oponente e a vez volta.
	#
	# `seat` vai junto porque é o que a rede entrega: o servidor carimba o
	# remetente, e a tela recusa um lance que não venha de quem tem a vez. Um
	# lance de teste sem assento é indistinguível de um adulterado — que é
	# exatamente o que a conferência existe para pegar.
	scene._on_remote_move({"p": [_square("e7"), _square("e5")], "pr": 0, "n": 1, "seat": 1})
	await get_tree().create_timer(scene._board.remaining_animation() + 0.2).timeout
	_equals(scene._state.ply, 3, "o plano sai assim que a vez chega")
	_equals(
		Board.square_name(scene._state.history[2]["p"][1]), "d4", "e é o lance que foi planejado"
	)
	_check(scene._premove.is_empty(), "o plano se consome ao sair")

	await _test_premove_chain(scene)

	Game.mode = Game.Mode.HOTSEAT
	_check(not scene._premove_allowed(), "no mesmo aparelho não se planeja: não há espera")
	Game.mode = Game.Mode.ONLINE

	# Plano que o lance do oponente inviabiliza — aqui ele come a própria peça
	# planejada. O aviso existe para o jogador não concluir que o toque dele se
	# perdeu no caminho.
	var state: MatchState = scene._state
	state.squares = Board.empty_squares()
	_put(state, "g1", Board.Side.WHITE, Board.Kind.KING)
	_put(state, "f3", Board.Side.WHITE, Board.Kind.KNIGHT)
	_put(state, "a2", Board.Side.WHITE, Board.Kind.PAWN)
	_put(state, "e8", Board.Side.BLACK, Board.Kind.KING)
	_put(state, "g4", Board.Side.BLACK, Board.Kind.BISHOP)
	state.side_to_move = Board.Side.BLACK
	state.meta = {"castle": 0, "ep": Board.NO_SQUARE, "halfmove": 0}
	state.history.clear()
	state.ply = 0
	scene._clear_premove()
	scene._recompute()

	scene._on_square_tapped(_square("f3"))
	scene._on_square_tapped(_square("e5"))
	_equals(scene._premove.size(), 2, "plano armado para o cavalo")

	scene._on_remote_move({"p": [_square("g4"), _square("f3")], "pr": 0, "n": 0, "seat": 1})
	await get_tree().create_timer(scene._board.remaining_animation() + 0.2).timeout
	_equals(scene._state.ply, 1, "o cavalo foi capturado, então o plano não sai")
	_check(scene._premove.is_empty(), "e é descartado")
	_check(
		scene._banner._message.contains("planejado"),
		"com aviso, para o toque não parecer perdido (obtido: '%s')" % scene._banner._message
	)

	scene.queue_free()
	await get_tree().process_frame

	# Nas damas a captura é obrigatória: o lance do oponente decide qual pedra
	# *tem* de mover, então quase todo plano nasceria ilegal.
	Game.game_id = Game.CHECKERS
	var checkers := preload("res://scenes/match.tscn").instantiate()
	add_child(checkers)
	await get_tree().process_frame
	checkers._state.side_to_move = Board.Side.BLACK
	checkers._recompute()
	_check(not checkers._premove_allowed(), "damas não tem lance planejado")
	checkers.queue_free()
	await get_tree().process_frame

	Net.connected = false
	Game.mode = Game.Mode.HOTSEAT
	Game.game_id = Game.CHESS


## A corrente: mais de um lance planejado, saindo um por vez.
##
## O que ela tem de diferente de um plano só, e é o que este teste persegue: o
## segundo elo é escolhido numa posição **hipotética**, onde o primeiro já
## aconteceu. A peça é pega onde ela vai estar, e não onde ela está — se isso
## estiver errado, o jogador toca na casa de destino do elo anterior e o tabuleiro
## não responde.
##
## Chega com a partida em 1.e4 e5 2.d4, vez das pretas.
func _test_premove_chain(scene: Node) -> void:
	print("corrente de lances planejados")
	_check(scene._premove_allowed(), "ainda é a vez do oponente")

	scene._on_square_tapped(_square("g1"))
	scene._on_square_tapped(_square("f3"))
	_equals(scene._premove.size(), 2, "primeiro elo armado")

	# A peça está em g1 de verdade e em f3 na hipótese. É f3 que o dedo procura.
	scene._on_square_tapped(_square("f3"))
	_equals(scene._premove_pick, _square("f3"), "a peça é pega onde ela **vai** estar")
	_check(
		scene._board.targets.has(_square("g5")),
		"com os destinos da posição em que o elo anterior já aconteceu"
	)
	scene._on_square_tapped(_square("g5"))
	_equals(scene._premove.size(), 4, "a corrente tem dois elos")

	# Um toque fora apaga **um** elo, e não a corrente: quatro decisões perdidas
	# por um toque errado seria caro demais.
	scene._on_square_tapped(_square("h5"))
	_equals(scene._premove.size(), 2, "o toque fora apaga só o último elo")
	scene._on_square_tapped(_square("f3"))
	scene._on_square_tapped(_square("g5"))
	_equals(scene._premove.size(), 4, "e o elo volta com dois toques")

	# Sai um por vez: o primeiro agora, o segundo na vez seguinte.
	#
	# O `n` é o índice do lance no histórico, e ele **tem** de ser o tamanho atual:
	# a tela descarta um `n` que já está no histórico (é o reenvio de uma
	# reconexão) e pede sincronia para um que pule lance. Aqui isso importa porque
	# cada elo que sai empurra o histórico dois de uma vez — o do oponente e o
	# nosso.
	scene._on_remote_move({"p": [_square("b8"), _square("c6")], "pr": 0, "n": 3, "seat": 1})
	await get_tree().create_timer(scene._board.remaining_animation() + 0.2).timeout
	_equals(scene._state.history.size(), 5, "o oponente jogou e o primeiro elo saiu atrás")
	_equals(Board.square_name(scene._state.history[4]["p"][1]), "f3", "e o elo foi o planejado")
	_equals(scene._premove.size(), 2, "com o segundo ainda esperando a vez dele")

	scene._on_remote_move({"p": [_square("d7"), _square("d6")], "pr": 0, "n": 5, "seat": 1})
	await get_tree().create_timer(scene._board.remaining_animation() + 0.2).timeout
	_equals(Board.square_name(scene._state.history[6]["p"][1]), "g5", "o segundo elo saiu depois")
	_check(scene._premove.is_empty(), "e a corrente acabou")


## O teto de elos. Ele é recusado em voz alta: sem o aviso, o toque na quinta peça
## não faz nada e a tela fica muda, que é o que o app evita em todo lugar.
func _test_premove_limit() -> void:
	print("teto da corrente")
	Game.mode = Game.Mode.ONLINE
	Game.local_side = Board.Side.WHITE
	Net.local_side = Board.Side.WHITE
	Net.connected = true
	Game.game_id = Game.CHESS
	var scene := preload("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	# Uma torre num tabuleiro quase vazio: ela anda para frente e para trás, então
	# a corrente cresce sem que a posição hipotética fique impossível.
	var state: MatchState = scene._state
	state.squares = Board.empty_squares()
	_put(state, "a1", Board.Side.WHITE, Board.Kind.KING)
	_put(state, "h1", Board.Side.WHITE, Board.Kind.ROOK)
	_put(state, "a8", Board.Side.BLACK, Board.Kind.KING)
	state.side_to_move = Board.Side.BLACK
	state.meta = {"castle": 0, "ep": Board.NO_SQUARE, "halfmove": 0}
	state.history.clear()
	state.ply = 0
	scene._clear_premove()
	scene._recompute()

	var path := ["h1", "h4", "h1", "h4", "h1"]
	for index in range(path.size() - 1):
		scene._on_square_tapped(_square(path[index]))
		scene._on_square_tapped(_square(path[index + 1]))
	_equals(scene._premove.size() / 2, scene.PREMOVE_MAX_LINKS, "a corrente para no teto")

	# Na hipótese, depois dos quatro elos a torre está de volta em h1 — é lá que o
	# dedo a acha, e é lá que o teto tem de recusar em voz alta.
	scene._on_square_tapped(_square("h1"))
	_equals(scene._premove.size() / 2, scene.PREMOVE_MAX_LINKS, "e o elo a mais não entra")
	_equals(scene._premove_pick, Board.NO_SQUARE, "sem deixar a peça erguida")
	_check(
		scene._banner._message.contains("sequência"),
		"com aviso, para a tela não ficar muda (obtido: '%s')" % scene._banner._message
	)

	scene.queue_free()
	await get_tree().process_frame
	Net.connected = false
	Game.mode = Game.Mode.HOTSEAT


## O bot dentro da partida. A busca em si é testada no `test_runner`; o que se
## verifica aqui é o encaixe, que é onde mora o risco: quem tem a vez, quem pode
## tocar no tabuleiro, e se o lance dele chega ao estado.
##
## O nível fácil de propósito — é o mais rápido, e o teste é sobre a partida
## andar, não sobre o lance ser bom.
func _test_bot() -> void:
	print("bot na partida")
	# O cartão mostra o nome salvo do jogador, que é estado do aparelho: sem
	# limpar, a asserção do título falharia em qualquer máquina onde alguém já
	# escolheu um nome. O nome original volta no fim da seção.
	var saved_name := Prefs.player_name() if Prefs.has_name() else ""
	Prefs.set_player_name("")
	Game.bot_level = 0
	Game.bot_side = Board.Side.BLACK
	Game.start_solo(Game.CHESS)
	var scene := preload("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	_equals(Game.local_side, Board.Side.WHITE, "quem joga sou eu, do lado escolhido")
	_equals(scene._board.flipped, false, "e o tabuleiro fica do meu lado")
	_check(scene._is_local_turn(), "a vez começa comigo")
	_check(not scene._bot_pending, "e o bot não pensa fora da vez dele")
	# `DEFAULT_NAME` e não um literal: sem nome escolhido, o cartão mostra o nome
	# padrão, e ele mora no `Prefs`. Um "Você" escrito aqui à mão foi exatamente o
	# que sobreviveu à troca do padrão e deixou esta suíte vermelha sem que nada
	# estivesse quebrado.
	_equals(
		_node(scene, "%BottomTag").title, Prefs.DEFAULT_NAME,
		"cartão de baixo é o meu"
	)
	_check(_node(scene, "%TopTag").title.begins_with("Bot"), "o de cima é o do bot")

	# Meu lance passa a vez, e a busca começa junto — sem esperar a animação
	# terminar, que é tempo de graça.
	_play(scene, "e2", "e4")
	_check(scene._bot_pending, "meu lance põe o bot a pensar")
	_check(not scene._is_local_turn(), "e o tabuleiro deixa de aceitar toques")
	scene._selection = PackedInt32Array()
	scene._on_square_tapped(_square("d2"))
	_check(scene._selection.is_empty(), "nem para planejar: contra o bot não há espera")

	# O lance sai sozinho, dentro do piso de espera mais uma folga.
	var deadline := Time.get_ticks_msec() + 8000
	while scene._bot_pending and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_equals(scene._state.ply, 2, "o bot responde sozinho")
	_check(scene._is_local_turn(), "e devolve a vez")
	_equals(
		Board.side_of(scene._state.squares[scene._state.history[1]["p"][1]]),
		Board.Side.BLACK,
		"quem se moveu foi uma peça do bot"
	)

	# Revanche troca as cores, como em rede: começar sempre de brancas contra o
	# bot é jogar sempre a mesma metade do jogo.
	scene._show_overlay("Fim", "", true)
	scene._request_rematch()
	_equals(Game.bot_side, Board.Side.WHITE, "revanche passa as brancas para o bot")
	_equals(Game.local_side, Board.Side.BLACK, "e as pretas para mim")
	_equals(scene._board.flipped, true, "com o tabuleiro virado junto")
	_check(scene._bot_pending, "e o bot abre a partida")

	scene.queue_free()
	await get_tree().process_frame

	Prefs.set_player_name(saved_name)
	Game.bot_side = Board.Side.BLACK
	Game.mode = Game.Mode.HOTSEAT
	Game.local_side = Board.Side.WHITE


## Toda tela sabe receber o botão de voltar do sistema.
##
## `Nav` desliga o `quit_on_go_back` e entrega o gesto ao `go_back()` da cena
## aberta. Quem não declarar o método volta à tela inicial em vez de fechar o app
## — a falha barata, de propósito —, mas volta **errado**: uma partida largada sem
## passar pelo `_leave()` dela, ou um painel que devia fechar primeiro e não
## fecha. É uma tela que funciona mal em silêncio, e silêncio é o que este teste
## existe para quebrar.
##
## Varre o diretório em vez de conferir uma lista escrita aqui: uma lista é uma
## segunda coisa a lembrar de atualizar quando uma tela nova nascer, e esquecer
## dela é exatamente o esquecimento que o teste deveria pegar.
func _test_back_navigation() -> void:
	print("botão de voltar do sistema")
	var files := DirAccess.get_files_at("res://scenes")
	var screens := 0
	for file in files:
		if not file.ends_with(".tscn"):
			continue
		screens += 1
		var path := "res://scenes/%s" % file
		# `instantiate()` sem `add_child`: `_ready` não roda, então nenhuma tela
		# abre câmera, link de rede ou viewport 3D só para responder se tem um
		# método. O que se pergunta é do script, não do estado.
		var screen := (load(path) as PackedScene).instantiate()
		_check(screen.has_method(&"go_back"), "%s declara go_back()" % file)
		screen.free()
	_check(screens >= 9, "as nove telas do app foram varridas (achadas: %d)" % screens)

	# A linha que faz o resto valer alguma coisa. Com ela ligada o `SceneTree`
	# fecha o app junto com a notificação, e nenhum `go_back()` chega a ser
	# chamado — as nove telas acima estariam certas e inúteis.
	_check(not get_tree().quit_on_go_back, "o gesto deixou de fechar o app sozinho")

	# E o gesto chega mesmo à tela aberta. Uma dublê no lugar da cena atual, porque
	# o caminho de quem **não** declara o método troca de cena — e a cena que ele
	# descartaria é esta suíte.
	var previous := get_tree().current_scene
	var stub := _BackStub.new()
	# Na **raiz**, e não aqui dentro: `set_current_scene` recusa em silêncio um nó
	# que não seja filho de `root`. Pendurada nesta suíte, a dublê não virava cena
	# atual, `Nav` caía no caminho de quem não tem `go_back()` — e trocava a cena,
	# levando junto o teste que estava rodando.
	get_tree().root.add_child(stub)
	get_tree().current_scene = stub
	Nav.go_back()
	_check(stub.went_back, "Nav entrega o gesto ao go_back() da tela aberta")
	get_tree().current_scene = previous
	stub.queue_free()


## A barra da partida, na cena de verdade.
##
## Ela é a moldura que as cinco telas passam a dividir, e o que se verifica aqui é
## o que uma troca de cena quebra sem dar erro: que a barra entrou na árvore, que
## `bind()` a ligou à partida em curso, e sobretudo que **sair continua
## perguntando** — ligar a saída no toque em vez da confirmação compila, roda, e
## só aparece quando alguém perde uma partida por encostar no canto da tela.
func _test_match_bar() -> void:
	print("barra de partida")

	Game.mode = Game.Mode.HOTSEAT
	Game.start_hotseat(Game.CHECKERS)
	var scene := preload("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	var bar: MatchBar = scene.get_node("%Bar")
	_check(bar.is_visible_in_tree(), "a barra está na tela da partida")
	_equals(bar.title, Game.game_title(), "com o nome do jogo em curso")
	_check(bar.status == _find_status(scene), "e a faixa de contexto mora dentro dela")

	# O gesto de voltar do Android é o mesmo botão, e por isso faz a mesma
	# pergunta. Se um dia ele voltar a chamar `_exit()` direto, a partida acaba com
	# um deslize de dedo na borda da tela — e isso não dá erro nenhum.
	scene.go_back()
	await get_tree().process_frame
	_check(bar.leave._layer != null, "o gesto de voltar abre a pergunta em vez de sair")
	_check(is_instance_valid(scene), "e a partida continua de pé")
	bar.leave._dismiss()

	# O `?` abre as regras desta mesa, e o gesto de voltar fecha a gaveta antes de
	# chegar à partida: voltar é sair do que está na frente.
	var drawer := bar.open_rules()
	await get_tree().process_frame
	_check(drawer._list.get_child_count() > 0, "o ? abre as regras desta mesa")
	Nav.go_back()
	await get_tree().process_frame
	_check(not is_instance_valid(drawer), "o gesto de voltar fecha a gaveta")
	_check(bar.leave._layer == null, "e não chega a perguntar se quer sair")

	# A saída é provada numa barra solta, e não nesta: a da cena está ligada ao
	# `_exit()` da partida, e confirmar aqui trocaria a cena debaixo do teste.
	var loose := MatchBar.create("Xadrez")
	add_child(loose)
	# Lista, e não contador: o lambda do GDScript captura a variável local **por
	# valor**, e um `int` incrementado lá dentro some ao voltar. O array é
	# referência, então o que acontece dentro é visto aqui fora.
	var heard: Array[int] = []
	loose.leave_confirmed.connect(func() -> void: heard.append(1))
	loose.leave.pressed.emit()
	_equals(heard.size(), 0, "tocar em sair não sai da partida")
	loose.leave.confirmed.emit()
	_equals(heard.size(), 1, "quem sai é a confirmação")
	loose.queue_free()

	scene.queue_free()
	await get_tree().process_frame


## A faixa de contexto dentro de uma partida de verdade.
##
## As cinco telas montam a faixa por código, cada uma num contêiner diferente, e
## é aí que mora o risco: um `add_child` no lugar errado não dá erro nenhum — a
## faixa simplesmente não aparece, ou aparece com largura zero num canto. Por isso
## o teste procura o nó **na árvore da cena**, e não no script que o criou.
func _test_match_status() -> void:
	print("faixa de contexto")

	_equals(MatchStatus.clock_text(0), "0:00", "partida recém-começada")
	_equals(MatchStatus.clock_text(9), "0:09", "os segundos vêm com zero à esquerda")
	_equals(MatchStatus.clock_text(754), "12:34", "minutos e segundos")
	# A hora só aparece quando existe: "0:12:34" gasta um campo para dizer zero.
	_equals(MatchStatus.clock_text(3599), "59:59", "o último segundo antes da hora")
	_equals(MatchStatus.clock_text(3600), "1:00:00", "e aí a hora entra")
	_equals(MatchStatus.clock_text(7384), "2:03:04", "com os dois campos preenchidos")

	Game.mode = Game.Mode.HOTSEAT
	Game.start_hotseat(Game.CHESS)
	var scene := preload("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	var strip := _find_status(scene)
	_check(strip != null, "a faixa entrou na árvore da partida")
	if strip == null:
		scene.queue_free()
		return

	_check(strip.is_visible_in_tree(), "e está visível")
	_equals(strip.rounds, 0, "partida nova não teve rodada nenhuma")
	_play(scene, "e2", "e4")
	_equals(strip.rounds, 0, "um lance das brancas não fecha a volta")
	_play(scene, "e7", "e5")
	_equals(strip.rounds, 1, "a resposta das pretas fecha a primeira")

	# No mesmo aparelho não há sala, e um "Sala " vazio na tela seria pior que a
	# ausência: ele promete um código que não existe.
	_equals(strip.code, "", "sem rede não há código a mostrar")
	_check(not strip._code.visible, "e o botão do código sai da faixa")

	strip.code = "ABC123"
	_check(strip._code.visible, "com sala, o botão aparece")
	_equals(strip._code.text, "Sala ABC123", "escrito com o código")

	# O relógio conta do começo gravado, e não de quando o nó nasceu — é o mesmo
	# número em quem abriu a sala e em quem acabou de reconectar nela.
	strip.started_at = int(Time.get_unix_time_from_system()) - 125
	_equals(strip.elapsed(), 125, "o relógio conta desde o começo da partida")
	strip.started_at = 0
	_equals(strip.elapsed(), 0, "e fora de partida não conta desde 1970")

	scene.queue_free()
	await get_tree().process_frame


## As boas-vindas da primeira abertura.
##
## Três coisas, e a terceira é a que um teste pega e um olho não: **ela não
## volta**. Quem abre, lê e decide ficar com o nome padrão sai daqui com o mesmo
## nome de antes — e se a marca fosse `has_name()`, esse jogador receberia a
## mesma tela em toda abertura sem nunca entender o que o app quer dele.
func _test_welcome() -> void:
	print("boas-vindas")
	# O arquivo é o do aparelho de quem roda a suíte. O nome e a marca voltam ao
	# que eram no fim.
	var saved_name := Prefs.player_name() if Prefs.has_name() else ""
	var saved_welcomed := Prefs.welcomed()

	# A marca é **apagada**, e não suposta ausente. Esta seção passou na primeira
	# execução porque a chave ainda não existia neste aparelho, e quebrou na
	# seguinte — a folha de prints tinha rodado no meio e gravado a marca. Um teste
	# que depende do estado da máquina passa exatamente até a hora em que
	# importaria.
	Prefs.forget_welcome()
	Prefs.set_player_name("")
	_check(WelcomePanel.pending(), "sem marca, a tela é devida")

	var menu := preload("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var welcome: WelcomePanel = menu._welcome()
	_check(welcome != null, "e a tela inicial a monta por cima da lista de jogos")
	if welcome == null:
		menu.queue_free()
		return

	welcome._edit.text = "Lucas"
	welcome.finish()
	_equals(Prefs.player_name(), "Lucas", "o nome digitado é gravado")
	_check(Prefs.welcomed(), "e a marca fica")
	_check(not WelcomePanel.pending(), "então a tela não é mais devida")
	menu.queue_free()
	await get_tree().process_frame

	# Quem sai sem escrever nada fica com o padrão — e mesmo assim não vê de novo.
	# É o caso que separa a marca do nome, e o único em que os dois discordam.
	Prefs.set_player_name("")
	Prefs.set_welcomed()
	_equals(Prefs.player_name(), Prefs.DEFAULT_NAME, "campo vazio devolve o padrão")
	_check(not Prefs.has_name(), "sem nome escolhido")
	_check(not WelcomePanel.pending(), "e ainda assim a tela não reaparece")

	Prefs.set_player_name(saved_name)
	if not saved_welcomed:
		Prefs.forget_welcome()


func _find_status(node: Node) -> MatchStatus:
	if node is MatchStatus:
		return node as MatchStatus
	for child in node.get_children():
		var found := _find_status(child)
		if found != null:
			return found
	return null


class _BackStub extends Node:
	var went_back := false

	func go_back() -> void:
		went_back = true


## Eventos de ponteiro como o sistema os entrega. O começo do gesto chega em
## coordenadas locais, pelo `_gui_input`; o resto chega em coordenadas globais,
## pelo `_input` — que é o caminho que faz um arrasto para fora do tabuleiro
## ainda terminar.
static func _press(local: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.pressed = true
	event.position = local
	return event


static func _motion(board: BoardView, local: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.position = _to_global(board, local)
	return event


static func _release(board: BoardView, local: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.pressed = false
	event.position = _to_global(board, local)
	return event


static func _mouse_motion(board: BoardView, local: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = _to_global(board, local)
	return event


static func _mouse_release(board: BoardView, local: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = _to_global(board, local)
	return event


static func _to_global(board: BoardView, local: Vector2) -> Vector2:
	return board.get_global_transform_with_canvas() * local


## Tabuleiro limpo com as pedras informadas, brancas a jogar.
func _lay_out(scene: Node, white: Array, black: Array) -> void:
	scene._new_game()
	var state: MatchState = scene._state
	state.squares = Board.empty_squares()
	for name in white:
		_put(state, name, Board.Side.WHITE, Board.Kind.MAN)
	for name in black:
		_put(state, name, Board.Side.BLACK, Board.Kind.MAN)
	state.side_to_move = Board.Side.WHITE
	state.meta = {"idle": 0}
	scene._selection = PackedInt32Array()
	scene._recompute()


func _time_control_with_increment() -> int:
	for index in Game.TIME_CONTROLS.size():
		if float(Game.TIME_CONTROLS[index]["increment"]) > 0.0:
			return index
	_failures += 1
	printerr("  FAIL nenhum ritmo da lista tem incremento")
	return 0


## Um nó que sumiu da cena tem de virar falha, não um `null` que aborta a função
## e leva junto todas as asserções que viriam depois — foi assim que este arquivo
## passou a reportar sucesso sem testar nada.
func _node(match_scene: Node, path: String) -> Node:
	var found := match_scene.get_node_or_null(path)
	if found == null:
		_failures += 1
		printerr("  FAIL nó %s não existe em match.tscn" % path)
	return found


## Joga o lance `from`-`to` pelas regras da partida, como o toque faria.
func _play(match_scene: Node, from: String, to: String) -> void:
	for move in match_scene._legal:
		if move.from_square() == _square(from) and move.to_square() == _square(to):
			match_scene._play(move, false)
			return
	_failures += 1
	printerr("  FAIL lance %s-%s não estava disponível" % [from, to])


## O relógio só corre para o lado da vez, o incremento entra depois do lance, e
## zerar encerra a partida — exceto quando quem ganharia não tem com que dar
## mate, que pela norma é empate.
func _test_clock(match_scene: Node) -> void:
	print("relógio")
	# O ritmo com incremento é o caso interessante, e é procurado pelo incremento
	# e não por índice: acrescentar um ritmo à lista não pode quebrar este teste.
	Game.time_control = _time_control_with_increment()
	match_scene._new_game()

	var white := Board.Side.WHITE
	var black := Board.Side.BLACK
	var initial := Game.clock_initial()
	var increment := Game.clock_increment()
	var top: PlayerTag = _node(match_scene, "%TopTag")
	var bottom: PlayerTag = _node(match_scene, "%BottomTag")
	_equals(float(match_scene._clock[white]), initial, "os dois começam com o tempo do ritmo")
	_equals(
		bottom.clock_text,
		"%d:%02d" % [int(initial) / 60, int(initial) % 60],
		"o cartão mostra o relógio no lugar de SUA VEZ"
	)

	# Um segundo de vez das brancas sai só do relógio das brancas.
	match_scene._process(1.0)
	_equals(float(match_scene._clock[white]), initial - 1.0, "o lado da vez consome tempo")
	_equals(float(match_scene._clock[black]), initial, "o lado parado não")

	_play(match_scene, "e2", "e4")
	_equals(
		float(match_scene._clock[white]),
		initial - 1.0 + increment,
		"o incremento entra depois do lance"
	)

	# Em rede o relógio para durante a reconexão: quem trocou de Wi-Fi para 4G
	# não pode voltar já derrotado no cronômetro.
	Game.mode = Game.Mode.ONLINE
	_check(not match_scene._clock_running(), "relógio para com o link caído")
	Game.mode = Game.Mode.HOTSEAT
	_check(match_scene._clock_running(), "e volta a correr no mesmo aparelho")

	# Zerar com material suficiente do outro lado é derrota.
	match_scene._clock[black] = 0.4
	match_scene._state.side_to_move = black
	match_scene._process(1.0)
	_equals(match_scene._flagged, black, "quem zera é marcado")
	_check(_node(match_scene, "%ResultLayer").visible, "o painel de fim aparece")
	_equals(_node(match_scene, "%ResultTitle").text, "Tempo esgotado", "com o título do tempo")
	match_scene._selection = PackedInt32Array()
	match_scene._on_square_tapped(_square("e7"))
	_check(match_scene._selection.is_empty(), "e o tabuleiro para de aceitar toques")

	# As brancas zeram estando com a dama, e as pretas — que "venceriam" — só têm
	# o rei. Rei sozinho não dá mate por nenhuma sequência legal, então a norma
	# manda empatar em vez de premiar o cronômetro.
	match_scene._new_game()
	var state: MatchState = match_scene._state
	state.squares = Board.empty_squares()
	_put(state, "e1", Board.Side.WHITE, Board.Kind.KING)
	_put(state, "d7", Board.Side.WHITE, Board.Kind.QUEEN)
	_put(state, "e8", Board.Side.BLACK, Board.Kind.KING)
	state.side_to_move = Board.Side.WHITE
	state.meta = {"castle": 0, "ep": Board.NO_SQUARE, "halfmove": 0}
	match_scene._recompute()
	match_scene._clock[white] = 0.2
	match_scene._process(1.0)
	_equals(_node(match_scene, "%ResultTitle").text, "Empate", "rei sozinho não vence no tempo")

	Game.time_control = 0
	match_scene._new_game()
	_equals(bottom.clock_text, "", "sem relógio o cartão volta a mostrar só a vez")
	await get_tree().process_frame


static func _square(name: String) -> int:
	return Board.square(name.unicode_at(0) - "a".unicode_at(0), int(name.substr(1)) - 1)


static func _put(state: MatchState, name: String, side: int, kind: int) -> void:
	state.set_piece(_square(name), Board.piece(side, kind))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])


# --- batalha naval -----------------------------------------------------------


## A partida inteira pela cena: posicionar, confirmar, receber a frota do outro,
## mirar, atirar e afundar. O que mais importa aqui é a **névoa** — o modelo
## conhece as duas frotas de propósito, e a única coisa que separa isso de
## entregar o jogo é `own` estar falso no mar do adversário.
func _test_battleship() -> void:
	print("batalha naval — cena")
	Game.mode = Game.Mode.ONLINE
	Game.game_id = Game.BATTLESHIP
	Game.local_side = Board.Side.WHITE
	var scene := preload("res://scenes/battleship_match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	var enemy: WatersView = _bs_node(scene, "%EnemyWaters")
	var own: WatersView = _bs_node(scene, "%OwnWaters")
	_check(not enemy.own, "o mar do adversário nunca revela navio inteiro")
	_check(own.own, "o mar do jogador mostra a frota dele")

	_equals(_bs_node(scene, "%PlaceLayer").visible, true, "a partida abre no posicionamento")
	_check(_bs_node(scene, "%ConfirmButton").disabled, "sem frota não dá para confirmar")

	# Quatro navios deitados, um por linha ímpar. Nenhum encosta nos outros.
	for start in ["a1", "a3", "a5", "a7"]:
		scene._on_place_tapped(_square(start))
	_check(scene._fleet_complete(), "os quatro navios pousaram")
	scene._refresh()
	_check(not _bs_node(scene, "%ConfirmButton").disabled, "aí o botão libera")

	# Uma casa já ocupada não aceita navio, e o toque inválido não gasta nada.
	var before: int = scene._next_ship
	scene._on_place_tapped(_square("a1"))
	_equals(scene._next_ship, before, "toque inválido não avança a frota")

	scene._confirm_fleet()
	_equals(scene._phase, 1, "confirmar leva para a espera do oponente")
	_equals(_bs_node(scene, "%PlaceLayer").visible, true, "e a tela de posicionar continua")

	scene._on_enemy_fleet(_bs_fleet())
	_equals(scene._phase, 2, "com as duas frotas a partida começa")
	_equals(_bs_node(scene, "%PlaceLayer").visible, false, "e a tela de posicionar sai")

	# Primeiro toque mira, segundo atira. Um toque perdido não pode custar a vez.
	scene._on_enemy_tapped(_square("h8"))
	_equals(scene._state.ply, 0, "o primeiro toque só mira")
	_equals(enemy.aim, _square("h8"), "e a mira aparece na casa tocada")
	scene._on_enemy_tapped(_square("g8"))
	_equals(scene._state.ply, 0, "mirar outra casa também não atira")
	scene._on_enemy_tapped(_square("g8"))
	_equals(scene._state.ply, 1, "o segundo toque na mesma casa dispara")
	_equals(scene._state.side_to_move, Board.Side.BLACK, "e a vez passa")

	scene._on_enemy_tapped(_square("a1"))
	_equals(scene._state.ply, 1, "fora da vez o mar não aceita toque")

	_check(
		not enemy._sunk_kinds().has(Board.Kind.BATTLESHIP),
		"o encouraçado inimigo não está afundado ainda"
	)
	_check(
		_bs_node(scene, "%TopTag").subtitle == "4 navios",
		"o cartão do oponente conta a frota dele"
	)

	# Afunda as doze casas da frota inimiga.
	for cell in ["a1", "b1", "c1", "d1", "a3", "b3", "c3", "a5", "b5", "c5", "a7", "b7"]:
		_bs_fire(scene, cell)
	_equals(scene._phase, 3, "a frota inteira afundada encerra a partida")
	_equals(_bs_node(scene, "%OverlayLayer").visible, true, "e o painel de fim aparece")
	_equals(_bs_node(scene, "%ResultTitle").text, "Você venceu", "com o resultado do lado certo")
	_check(
		enemy._sunk_kinds().has(Board.Kind.BATTLESHIP),
		"os navios afundados passam a aparecer no mar inimigo"
	)

	# Revanche. O botão troca de significado conforme o convite venha ou vá, e a
	# primeira versão trocava o **tratador** com `disconnect`/`connect` — dois
	# convites seguidos derrubavam o jogo, e depois de uma revanche aceita o botão
	# ficava preso no tratador de "aceitar".
	var button: Button = _bs_node(scene, "%RematchButton")
	scene._on_rematch_requested()
	_equals(button.text, "Aceitar revanche", "o convite recebido muda o botão")
	scene._on_rematch_requested()
	_equals(button.text, "Aceitar revanche", "e um segundo convite não quebra nada")

	scene._on_rematch_button()
	_equals(scene._phase, 0, "aceitar volta para o posicionamento")
	_equals(_bs_node(scene, "%OverlayLayer").visible, false, "e o painel de fim sai")
	_equals(scene._state.ply, 0, "com a partida zerada")
	_check(scene._draft_is_empty(), "e a frota da partida anterior não fica")
	_equals(button.text, "Revanche", "o botão volta ao estado neutro")

	scene.free()


## Devolve a vez ao jogador e resolve o tiro nos dois toques.
func _bs_fire(scene: Node, cell: String) -> void:
	scene._state.side_to_move = Game.local_side
	scene._on_enemy_tapped(_square(cell))
	scene._on_enemy_tapped(_square(cell))


func _bs_fleet() -> PackedInt32Array:
	var fleet := BattleshipRules.empty_grid()
	fleet = BattleshipRules.place(fleet, Board.Kind.BATTLESHIP, _square("a1"), true)
	fleet = BattleshipRules.place(fleet, Board.Kind.CRUISER, _square("a3"), true)
	fleet = BattleshipRules.place(fleet, Board.Kind.SUBMARINE, _square("a5"), true)
	fleet = BattleshipRules.place(fleet, Board.Kind.DESTROYER, _square("a7"), true)
	return fleet


func _bs_node(scene: Node, path: String) -> Node:
	var found := scene.get_node_or_null(path)
	if found == null:
		_failures += 1
		printerr("  FAIL nó %s não existe em battleship_match.tscn" % path)
	return found
