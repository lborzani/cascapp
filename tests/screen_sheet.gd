extends Node

## Renderiza as telas do jogo fora do editor, para julgar mudanças visuais sem
## depender do aparelho.
##
##   godot --path . --resolution 720x1280 res://tests/screen_sheet.tscn
##
## Salva em user://shots/.

const SHOTS := [
	["res://scenes/main_menu.tscn", "00_boas_vindas"],
	["res://scenes/main_menu.tscn", "01_jogos"],
	["res://scenes/game_menu.tscn", "01b_como_jogar"],
	["res://scenes/match.tscn", "02_xadrez"],
	["res://scenes/match.tscn", "03_damas"],
	["res://scenes/pairing.tscn", "04_criar"],
	["res://scenes/join.tscn", "05_entrar"],
	["res://scenes/match.tscn", "06_capturas"],
	["res://scenes/match.tscn", "07_material"],
	["res://scenes/game_menu.tscn", "08_ajustes"],
	["res://scenes/match.tscn", "09_revanche"],
	["res://scenes/match.tscn", "10_planejado"],
	["res://scenes/match.tscn", "11_arrasto"],
	["res://scenes/match.tscn", "12_salto"],
	["res://scenes/game_menu.tscn", "13_bot_ajustes"],
	["res://scenes/match.tscn", "14_bot"],
	["res://scenes/battleship_match.tscn", "15_frota"],
	["res://scenes/battleship_match.tscn", "16_naval"],
	["res://scenes/ludo_match.tscn", "17_ludo"],
	["res://scenes/ludo_match.tscn", "17b_ludo_bots"],
	["res://scenes/ludo_match.tscn", "17c_ludo_andando"],
	["res://scenes/ludo_match.tscn", "17d_ludo_pilha"],
	["res://scenes/settings.tscn", "18_ajustes"],
	["res://scenes/game_menu.tscn", "19_metropole_ajustes"],
	["res://scenes/bomber_match.tscn", "21_bomberman"],
]

## Espanhola até a troca em c6: material trocado dos dois lados, então as duas
## faixas de captura aparecem e dá para julgar quanta altura elas custam ao
## tabuleiro — que é a decisão de layout em jogo aqui.
const OPENING := [
	["e2", "e4"], ["e7", "e5"], ["g1", "f3"], ["b8", "c6"],
	["f1", "b5"], ["a7", "a6"], ["b5", "c6"], ["d7", "c6"],
	["e1", "g1"], ["c8", "g4"],
]

var _index := -1
var _frames := 0
var _scene: Node = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	# A folha roda no aparelho de quem a chama, e a tela de boas-vindas depende de
	# uma marca gravada lá. Sem fixá-la, a mesma folha sai diferente na máquina de
	# quem nunca abriu o app — com um painel cobrindo metade dos prints de menu.
	# O print das boas-vindas desfaz a marca sozinho, e só ele.
	Prefs.set_welcomed()
	_next()

## Prints que rodam com o aparelho deitado.
##
## O Ludo passou a girar, como Metrópole. A folha desenha tudo numa janela só, e
## uma cena deitada dentro de uma janela em pé sai espremida — a base é 768x432
## e a janela oferecia 432x768. Girar a janela antes de montar a cena é o que o
## aparelho faz de verdade.
##
## Lista explícita, e não `Game.landscape()`: metade dos prints não é de partida
## nenhuma, e ali `game_id` é o resto do print anterior.
const LANDSCAPE_SHOTS := [
	"17_ludo", "17b_ludo_bots", "17c_ludo_andando", "17d_ludo_pilha",
	"21_bomberman",
]
const PORTRAIT_WINDOW := Vector2i(432, 768)
## Deitado num formato de celular de verdade, e **não** em 16:9.
##
## Era 1280x720, que é exatamente a proporção da base do projeto — e por isso a
## folha era cega justamente para o defeito que a base deitada causa. O tabuleiro
## do Ludo exigia altura igual à própria largura; em 16:9 isso estourava doze
## pixels e não aparecia em print nenhum, e num celular 2.17:1 estourava cento e
## oitenta e cortava metade da tela.
##
## 1560x720 é a proporção de um celular moderno deitado. Um print que só sai certo
## na proporção da base não está conferindo o layout: está conferindo o caso fácil.
const LANDSCAPE_WINDOW := Vector2i(1560, 720)


func _next() -> void:
	if _scene != null:
		# `free()` e não `queue_free()`: a cena deitada desgira a janela no
		# `_exit_tree`, e o adiado roda **depois** do `_ready` da seguinte — a
		# saída de uma desfazia a orientação da outra. É o mesmo tropeço que a
		# folha de Metrópole já tinha registrado.
		_scene.free()
		_scene = null
	_index += 1
	if _index >= SHOTS.size():
		print("PRONTO ", ProjectSettings.globalize_path("user://shots"))
		get_tree().quit()
		return
	# Pelo nome do print, e não pelo índice: com índices, acrescentar um print no
	# meio da lista deslocava todos os seguintes e cada `elif` passava a preparar
	# a tela errada — em silêncio, porque o print continuava saindo.
	var shot: String = SHOTS[_index][1]
	match shot:
		"00_boas_vindas":
			# A única marca desfeita da folha inteira, e o print seguinte a repõe.
			Prefs.forget_welcome()
		"01_jogos":
			Prefs.set_welcomed()
		"21_bomberman":
			# Solo: um humano e três máquinas, que é o modo em que o jogo existe
			# hoje. O print sai alguns segundos dentro da partida para o mapa já
			# ter buracos — um mapa intocado não mostra o que o jogo faz.
			Game.start_solo(Game.BOMBERMAN)
		"01b_como_jogar", "02_xadrez":
			Game.start_hotseat(Game.CHESS)
		"03_damas":
			Game.start_hotseat(Game.CHECKERS)
		"04_criar":
			Game.mode = Game.Mode.ONLINE
			Game.role = Game.Role.HOST
			Game.game_id = Game.CHESS
		"17_ludo":
			Game.start_hotseat(Game.LUDO)
		"17b_ludo_bots":
			# Solo de Ludo: um humano e três máquinas na mesma mesa.
			Game.start_solo(Game.LUDO)
		"17c_ludo_andando", "17d_ludo_pilha":
			Game.start_hotseat(Game.LUDO)
		"06_capturas", "07_material":
			Game.start_hotseat(Game.CHESS)
			# 3 + 2 nas telas de partida: o relógio no cartão é o elemento novo, e
			# um print sem ele não mostra o layout que precisa ser julgado.
			Game.time_control = 2
		"09_revanche":
			# A revanche negociada só existe em rede; no mesmo aparelho é imediata.
			Game.start_hotseat(Game.CHESS)
			Game.mode = Game.Mode.ONLINE
			Game.local_side = Board.Side.WHITE
		"10_planejado", "11_arrasto":
			# Lance planejado e arrasto são os dois de rede: o primeiro só existe na
			# vez do oponente, e o segundo precisa do tabuleiro do lado das brancas.
			Game.start_hotseat(Game.CHESS)
			Game.mode = Game.Mode.ONLINE
			Game.local_side = Board.Side.WHITE
			Net.local_side = Board.Side.WHITE
			Net.connected = true
		"12_salto":
			Game.start_hotseat(Game.CHECKERS)
		"08_ajustes", "13_bot_ajustes":
			Game.start_hotseat(Game.CHESS)
			Game.time_control = 2
			Game.bot_level = 1
			Game.bot_side = Board.Side.BLACK
		"19_metropole_ajustes":
			# O mesmo painel com as seções trocadas: Metrópole não tem relógio nem
			# nível de bot, e é o único jogo que pergunta o **formato**. O print
			# existe para provar que cada seção aparece só onde significa alguma
			# coisa — um painel com "ritmo" num jogo sem relógio seria uma escolha
			# que não decide nada.
			Game.start_hotseat(Game.MONOPOLY)
			Game.round_limit = 20
		"14_bot":
			Game.bot_level = 1
			Game.bot_side = Board.Side.BLACK
			Game.start_solo(Game.CHESS)
		"15_frota", "16_naval":
			# Batalha naval só existe em rede, então o print precisa do modo e do
			# lado que o aperto de mão daria.
			Game.mode = Game.Mode.ONLINE
			Game.game_id = Game.BATTLESHIP
			Game.local_side = Board.Side.WHITE
			Net.connected = true
	# A janela gira **antes** de a cena existir: é o `_ready` dela que escreve a
	# base de 768x432, e escrevê-la numa janela em pé desenha a tela deitada
	# espremida dentro dela.
	var wanted := LANDSCAPE_WINDOW if LANDSCAPE_SHOTS.has(shot) else PORTRAIT_WINDOW
	if DisplayServer.window_get_size() != wanted:
		DisplayServer.window_set_size(wanted)
		await get_tree().process_frame

	_scene = load(SHOTS[_index][0]).instantiate()
	add_child(_scene)
	if shot == "02_xadrez":
		_setup_check(_scene)
	elif shot == "05_entrar":
		# Salas plantadas: o print precisa responder como a lista fica com
		# conteúdo, e depender de haver partidas abertas de verdade no relay
		# tornaria o resultado diferente a cada execução.
		#
		# A consulta periódica é desligada **e** a que já saiu é cancelada: sem as
		# duas, a resposta real (vazia) chega no meio da contagem até o print e
		# apaga o que foi plantado.
		var panel: JoinPanel = _scene.get_node("%JoinPanel")
		panel.set_process(false)
		panel.get_node("%RoomsRequest").cancel_request()
		panel.show_rooms([
			{"code": "K7QW2M", "game": "chess", "tc": 2, "age": 20, "host": "Lucas"},
			# Mesa de quatro com apelido no limite: é a linha mais comprida que a
			# lista consegue produzir, e é ela que diz se o cartão aguenta.
			{
				"code": "LD44QT", "game": "ludo", "tc": 0, "age": 95,
				"seats": 4, "taken": 2, "host": "Maria Aparecida Jr",
			},
			{"code": "C3376G", "game": "checkers", "tc": 0, "age": 240},
			{"code": "PX9WT4", "game": "chess", "tc": 4, "age": 3900, "host": "Guidon"},
		])
		# QR e NFC forçados a aparecer: rodando no PC os dois são plugins Android
		# ausentes, e o print mostraria uma tela que nenhum aparelho vê. O que
		# precisa ser julgado aqui é o cartão cheio, com os três caminhos.
		panel.get_node("%ScanButton").visible = true
		panel.get_node("%NfcHint").visible = true
		panel.get_node("%Hint").visible = false
	elif shot == "06_capturas" or shot == "07_material":
		_play_opening(_scene)
		if shot == "07_material":
			_stuff_captures(_scene)
	elif shot == "08_ajustes" or shot == "19_metropole_ajustes":
		_scene._open_setup(Game.Mode.ONLINE)
	elif shot == "09_revanche":
		# Painel de fim de partida no estado mais cheio: convite de revanche
		# recebido, com aceitar e recusar. É o caso que responde se três botões
		# ainda cabem no painel.
		_play_opening(_scene)
		_scene._show_overlay("Brancas venceram", "Você venceu em 10 lances.", true)
		_scene._on_rematch_requested()
	elif shot == "10_planejado":
		# Vez do oponente, com os **três** lances seguintes já escolhidos. Duas
		# coisas precisam ser julgadas aqui:
		#
		# - o azul, que não pode ser confundido nem com o latão do último lance nem
		#   com o destaque de "é sua vez";
		# - a ordem da corrente. Ela é a única informação que a marcação sozinha não
		#   carrega, e sai em duas pistas — o elo mais próximo é o mais forte, e o
		#   número no destino diz a posição na fila. Três elos é onde as duas
		#   começam a ser exigidas ao mesmo tempo.
		_play_opening(_scene, 9)
		for link: Array in [["d2", "d4"], ["d4", "d5"], ["d1", "d3"]]:
			_scene._on_square_tapped(_sq(link[0]))
			_scene._on_square_tapped(_sq(link[1]))
	elif shot == "15_frota":
		# Metade da frota pousada: é o estado em que a tela precisa dizer qual
		# navio vem agora e quantos faltam, sem o jogador contar sozinho.
		#
		# Um deitado e um em pé de propósito: é o print que responde se a proa
		# aponta para o lado certo nas duas orientações.
		_scene._on_place_tapped(_sq("b2"))
		_scene._rotate()
		_scene._on_place_tapped(_sq("f4"))
		_scene._refresh()
	elif shot == "16_naval":
		_stage_battleship(_scene)
	elif shot == "17_ludo":
		_stage_ludo(_scene)
	elif shot == "17d_ludo_pilha":
		# Peões empilhados, que passou a ser lance legal: três vermelhos na saída
		# e duas cores dividindo uma casa segura. É o print que responde se dá para
		# ver **quantos** e **de quem** são — antes eles caíam no mesmo pixel e
		# quatro peões apareciam como um.
		_stage_ludo(_scene)
		var stacked: LudoView = _scene._board
		var progress := LudoRules.progress(_scene._state)
		for entry in [[0, 0, 1], [0, 1, 1], [0, 3, 1], [1, 0, 1], [2, 0, 9], [2, 1, 9]]:
			progress[LudoRules.slot(entry[0], entry[1])] = entry[2]
		_scene._state.meta[LudoRules.PROG] = progress
		stacked.state = _scene._state
		_scene._board.movable = PackedInt32Array()
	elif shot == "17c_ludo_andando":
		# Um quadro no meio da caminhada: o peão no ar entre duas casas e um
		# capturado voltando para a base. O print é tirado alguns quadros depois
		# da montagem, então a viagem é alongada para caber nesse intervalo —
		# sem isso ela já teria acabado e a foto seria de um tabuleiro parado.
		_stage_ludo(_scene)
		var board: LudoView = _scene._board
		board.travel(0, 1, 20, 26, [{"player": 2, "token": 0, "from": 17}])
		board._walk["duration"] = 6.0
		# O capturado começa com o relógio negativo, esperando a batida. Aqui ele
		# é adiantado para o instante do golpe, que é o que o print precisa
		# mostrar — o anel abrindo na casa e o peão já girando.
		board._knocked[0]["elapsed"] = LudoView.KNOCK_SECONDS * 0.18
		# E o relógio da vista para: o print sai alguns quadros depois da
		# montagem, e o anel do impacto dura menos que isso — sem congelar, a
		# foto sairia sempre do instante seguinte ao que ela quer mostrar.
		board.set_process(false)
		_scene._status("Vermelho tirou 6.")
	elif shot == "17b_ludo_bots":
		# Solo: você é o vermelho e as outras três cores são máquina. O print
		# responde se dá para saber quem é quem antes da primeira vez chegar.
		_stage_ludo(_scene)
		_scene._status("Vez do Verde (bot).")
		_scene._update_scoreboard()
	elif shot == "11_arrasto":
		_play_opening(_scene)
		_scene._on_square_tapped(_sq("f3"))
	elif shot == "12_salto":
		_stage_double_jump(_scene)
	elif shot == "13_bot_ajustes":
		# O painel no estado mais cheio que ele chega: ritmo, nível e cor de uma
		# vez. É o print que responde se ainda cabe na tela de um celular.
		_scene._open_setup(Game.Mode.SOLO)
	elif shot == "14_bot":
		# Partida contra o bot com dois lances jogados. O que se olha é o cartão
		# de cima, que aqui diz o nível em vez de "Oponente".
		_play_opening(_scene, 2)
	_frames = 0


## Salto duplo nas damas: o caminho do último lance tem três casas, e o que o
## print responde é se o traço acompanha a sequência inteira. A reta entre a
## primeira e a última casa passaria por cima das pedras comidas sem descrever
## nada do que aconteceu.
func _stage_double_jump(scene: Node) -> void:
	var state: MatchState = scene._state
	state.squares = Board.empty_squares()
	state.set_piece(_sq("c3"), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	state.set_piece(_sq("a3"), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	state.set_piece(_sq("g1"), Board.piece(Board.Side.WHITE, Board.Kind.MAN))
	for name in ["d4", "f6", "b8", "h6"]:
		state.set_piece(_sq(name), Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	state.side_to_move = Board.Side.WHITE
	state.meta = {"idle": 0}
	scene._recompute()
	for move in scene._legal:
		if move.path.size() == 3 and move.from_square() == _sq("c3"):
			scene._play(move, false)
			break
	scene._board.cancel_animation()
	scene._refresh()


## Capturas plantadas à mão, não jogadas: o caso que precisa ser visto é o
## cartão cheio — muitas peças de um lado, "+N" ao lado delas e a etiqueta "SUA
## VEZ" disputando a mesma linha. Chegar nele jogando levaria 40 lances.
func _stuff_captures(scene: Node) -> void:
	var black := Board.Side.BLACK
	var white := Board.Side.WHITE
	scene._captured[white] = [
		Board.piece(black, Board.Kind.PAWN),
		Board.piece(black, Board.Kind.PAWN),
		Board.piece(black, Board.Kind.PAWN),
		Board.piece(black, Board.Kind.PAWN),
		Board.piece(black, Board.Kind.KNIGHT),
		Board.piece(black, Board.Kind.BISHOP),
		Board.piece(black, Board.Kind.ROOK),
		Board.piece(black, Board.Kind.QUEEN),
	]
	scene._captured[black] = [
		Board.piece(white, Board.Kind.PAWN),
		Board.piece(white, Board.Kind.PAWN),
		Board.piece(white, Board.Kind.KNIGHT),
	]
	scene._refresh()


static func _sq(name: String) -> int:
	return Board.square(name.unicode_at(0) - 97, int(name.substr(1)) - 1)


## A peça no ar, a meio caminho do destino. Montada à mão e não por eventos: o
## que o print precisa mostrar é o quadro do meio do arrasto, e um gesto de
## verdade passaria por ele rápido demais para ser capturado.
##
## Só no quadro 30 porque `rect_of` depende do tamanho da casa, e ele só existe
## depois de a cena ter sido dimensionada.
func _stage_drag(scene: Node) -> void:
	var board: BoardView = scene._board
	board.layout()
	board._drag_square = _sq("f3")
	board.dragging = true
	board._drag_at = board.rect_of(_sq("f3")).get_center().lerp(
		board.rect_of(_sq("g5")).get_center(), 0.78
	)
	board.queue_redraw()


func _play_opening(scene: Node, plies: int = OPENING.size()) -> void:
	for step in OPENING.slice(0, plies):
		for move in scene._legal:
			if Board.square_name(move.from_square()) == step[0] \
					and Board.square_name(move.to_square()) == step[1]:
				scene._play(move, false)
				break
	scene._board.cancel_animation()
	scene._refresh()

func _setup_check(scene: Node) -> void:
	var s: MatchState = scene._state
	s.squares = Board.empty_squares()
	var put := func(name: String, side: int, kind: int) -> void:
		s.set_piece(Board.square(name.unicode_at(0) - 97, int(name.substr(1)) - 1), Board.piece(side, kind))
	for sq in ["a7", "b7", "c7", "f7", "g7", "h7"]:
		put.call(sq, Board.Side.BLACK, Board.Kind.PAWN)
	put.call("a8", Board.Side.BLACK, Board.Kind.ROOK)
	put.call("c8", Board.Side.BLACK, Board.Kind.BISHOP)
	put.call("e8", Board.Side.BLACK, Board.Kind.KING)
	put.call("g8", Board.Side.BLACK, Board.Kind.KNIGHT)
	put.call("h8", Board.Side.BLACK, Board.Kind.ROOK)
	put.call("d5", Board.Side.BLACK, Board.Kind.QUEEN)
	for sq in ["a2", "b2", "c2", "f2", "g2", "h2"]:
		put.call(sq, Board.Side.WHITE, Board.Kind.PAWN)
	put.call("a1", Board.Side.WHITE, Board.Kind.ROOK)
	put.call("c1", Board.Side.WHITE, Board.Kind.BISHOP)
	put.call("d1", Board.Side.WHITE, Board.Kind.QUEEN)
	put.call("e1", Board.Side.WHITE, Board.Kind.KING)
	put.call("f3", Board.Side.WHITE, Board.Kind.KNIGHT)
	put.call("h1", Board.Side.WHITE, Board.Kind.ROOK)
	put.call("b5", Board.Side.WHITE, Board.Kind.BISHOP)
	s.side_to_move = Board.Side.BLACK
	s.meta = {"castle": 0, "ep": Board.NO_SQUARE, "halfmove": 0}
	scene._board.last_move = PackedInt32Array([5, 33])
	scene._recompute()
	scene._on_square_tapped(Board.square(2, 7))

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 30 and SHOTS[_index][1] == "11_arrasto":
		_stage_drag(_scene)
	# As cenas entram com um fade de 0,16s, e `modulate` no nó raiz é aplicado a
	# cada filho separadamente — no meio do fade um painel opaco deixa o que está
	# atrás aparecer. Um print tirado cedo demais documenta um bug que não existe.
	if _frames == 40:
		var image := get_viewport().get_texture().get_image()
		image.save_png("user://shots/%s.png" % SHOTS[_index][1])
		print("shot ", SHOTS[_index][1])
		_next()


## Partida em andamento: as duas frotas no lugar, um navio inimigo já afundado,
## acertos e tiros n'água dos dois lados. É o estado que responde se os dois
## mares cabem na tela sem o de baixo virar decoração.
## Partida de Ludo no meio: peões nos quatro estados que o tabuleiro precisa
## saber desenhar — na base, na trilha, na reta final e em casa — e um dado
## rolado com peões acesos, que é o momento em que a tela pede uma decisão.
##
## Posição montada à mão e não jogada: uma partida de dado leva centenas de
## rolagens até ter peão em reta final, e nenhuma delas sai igual duas vezes.
func _stage_ludo(scene: Node) -> void:
	var progress := LudoRules.progress(scene._state)
	var placed := [
		[0, 0, 9], [0, 1, 23], [0, 2, LudoRules.GOAL], [0, 3, LudoRules.BASE],
		[1, 0, 4], [1, 1, LudoRules.RING + 1], [1, 2, LudoRules.BASE], [1, 3, LudoRules.BASE],
		[2, 0, 17], [2, 1, 31], [2, 2, LudoRules.BASE], [2, 3, LudoRules.BASE],
		[3, 0, 6], [3, 1, LudoRules.GOAL], [3, 2, 44], [3, 3, LudoRules.BASE],
	]
	for entry in placed:
		progress[LudoRules.slot(entry[0], entry[1])] = entry[2]
	scene._state.meta[LudoRules.PROG] = progress
	scene._state.meta[LudoRules.TURN] = 0

	# Dado na mesa e peões acesos: é o estado que responde se o realce é achado
	# num tabuleiro de quatro cores.
	scene._die = 3
	scene._pending = scene._rules.moves_for(scene._state, 3)
	scene._board.state = scene._state
	scene._board.movable = scene._movable_tokens()
	scene._dice.value = 3
	scene._dice.enabled = false
	scene._update_scoreboard()
	scene._status("Vermelho tirou 3. Escolha o peão.")


func _stage_battleship(scene: Node) -> void:
	for start in ["a1", "a3", "a5", "a7"]:
		scene._on_place_tapped(_sq(start))
	scene._confirm_fleet()

	var enemy := BattleshipRules.empty_grid()
	enemy = BattleshipRules.place(enemy, Board.Kind.BATTLESHIP, _sq("c2"), true)
	enemy = BattleshipRules.place(enemy, Board.Kind.CRUISER, _sq("f4"), false)
	enemy = BattleshipRules.place(enemy, Board.Kind.SUBMARINE, _sq("b6"), true)
	enemy = BattleshipRules.place(enemy, Board.Kind.DESTROYER, _sq("g7"), true)
	scene._on_enemy_fleet(enemy)

	# Nossos tiros: o destroier inimteiro afundado, dois acertos soltos no
	# encouraçado e alguns tiros n'água.
	for cell in ["g7", "h7", "c2", "d2", "a8", "e6", "h1", "b4"]:
		scene._state.side_to_move = Board.Side.WHITE
		scene._on_enemy_tapped(_sq(cell))
		scene._on_enemy_tapped(_sq(cell))

	# E os do oponente no nosso mar, para a grade de baixo não sair vazia.
	for cell in ["a1", "b1", "e3", "a5", "h8"]:
		scene._state.side_to_move = Board.Side.BLACK
		var shot := Move.new()
		shot.path = PackedInt32Array([_sq(cell)])
		scene._rules.apply_move(scene._state, shot)

	scene._state.side_to_move = Board.Side.WHITE
	scene._aim = _sq("d6")
	scene._refresh()
