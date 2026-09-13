extends Node

## Renderiza o tabuleiro 3D de Metrópole fora do editor, para julgar o desenho
## sem depender do aparelho.
##
##   godot --path . --resolution 1280x720 res://tests/monopoly_sheet.tscn
##
## Salva em user://shots/. Existe separado do `screen_sheet.gd` porque este jogo
## ainda não tem cena de partida — o que há para olhar é o tabuleiro, e ele
## precisa de uma posição armada à mão para mostrar o que sabe desenhar.
##
## A posição não é uma partida de verdade: é uma **vitrine**. Ela tem de propósito
## um exemplar de cada coisa que a casa pode dizer — grupo fechado com casas,
## grupo com hotel, propriedade hipotecada, aeroporto e companhia com dono, peões
## dividindo a mesma casa, e alguém preso. Uma posição sorteada mostraria o caso
## comum, que é o tabuleiro quase vazio, e é justamente onde não há nada para
## julgar.
##
## Os quatro prints são os quatro lados: é o giro de câmera visto parado. Se um
## deles sair com o texto de cabeça para baixo, o giro está errado — e essa é a
## coisa que o 3D existe para resolver.

const RulesLib := preload("res://core/monopoly_rules.gd")
const MATCH_SCENE := "res://scenes/monopoly_match.tscn"

## Nome do print, assento da vez, a casa que o painel mostra, e quantos
## **segundos** esperar antes da foto.
##
## Segundos e não quadros: o ciclo de turno é temporizado — 0,95s de dado, 0,5s
## de leitura, 0,085s por casa andada — e contar quadros amarra a foto à taxa de
## atualização da máquina. Numa placa rápida, 160 quadros passavam antes de o
## peão sair do lugar; numa lenta, passariam depois de ele chegar.
##
## A casa muda de propósito: uma propriedade construída, uma companhia, um grupo
## com hotel. O último print **joga um turno de verdade** — ele aperta "Rolar" e
## espera o bastante para os dados pararem (0,95s), a pausa de leitura passar
## (0,5s) e o peão estar no meio do caminho. É o único que prova que o ciclo anda;
## os outros três provam só que a tela desenha.
const SHOTS := [
	["20_metropole", 0, 19, 0.9],
	["20b_metropole_lado1", 1, 12, 0.9],
	["20c_metropole_lado2", 2, 34, 0.9],
	["20d_metropole_andando", 3, 0, 1.85],
	["20e_metropole_bot", 1, 12, 2.4],
	["20f_metropole_troca", 0, 19, 0.6],
	["20g_metropole_fim", 0, 19, 0.6],
	["20h_metropole_tampo", 0, 19, 0.9],
	["20i_metropole_seis", 0, 24, 0.9],
	["20j_metropole_cadeia", 2, 10, 0.9],
	["20k_metropole_camera", 0, 19, 0.9],
]

var _index := -1
## Segundos decorridos desde que a cena foi montada.
var _elapsed := 0.0
var _root: Control = null
var _board: MonopolyBoard3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	_next()


func _next() -> void:
	if _root != null:
		# `free()` e não `queue_free()`: a cena de partida desgira o aparelho no
		# `_exit_tree`, e o adiado roda **depois** do `_ready` da cena seguinte —
		# a saída da anterior desfazia a orientação da nova, e todos os prints a
		# partir do segundo saíam na base de retrato, com a UI encolhida.
		_root.free()
		_root = null
	_index += 1
	if _index >= SHOTS.size():
		print("PRONTO ", ProjectSettings.globalize_path("user://shots"))
		get_tree().quit()
		return

	# A cena de partida de verdade, e não o tabuleiro solto. O enquadramento da
	# câmera depende do formato da janela 3D, e a janela só tem o formato certo
	# depois que a coluna da esquerda tirou a largura dela — julgar a câmera num
	# retângulo 16:9 cheio seria julgar um enquadramento que ninguém vai ver.
	# O último print é solo: as três cadeiras que não são a sua viram máquina, e a
	# cena começa a vez do bot sozinha. Definido antes de instanciar porque quem
	# monta a lista de bots é o `_ready` da cena.
	if SHOTS[_index][0] == "20e_metropole_bot":
		Game.start_solo(Game.MONOPOLY)
	else:
		Game.start_hotseat(Game.MONOPOLY)

	# O tamanho da mesa é lido pelo `_ready` da cena, então ele tem de estar
	# escolhido **antes** de instanciar. Seis é a mesa cheia, que é onde a coluna
	# da esquerda aperta os cartões para caber.
	var seats := 6 if SHOTS[_index][0] == "20i_metropole_seis" else 4
	Game.table_size = seats

	_root = load(MATCH_SCENE).instantiate()
	add_child(_root)
	_board = _root._board

	var state := _showcase(seats)
	state.meta[MonopolyRules.TURN] = int(SHOTS[_index][1])
	# O peão da vez espalhado pelo tabuleiro: com a câmera seguindo, cada print
	# passa a mostrar um trecho diferente do anel em vez de quatro vistas do mesmo
	# canto.
	state.meta[MonopolyRules.POS][int(SHOTS[_index][1])] = int(SHOTS[_index][2])
	_root._state = state
	# Antes da contagem de quadros, e não na hora da foto: o tabuleiro monta as
	# peças em `_process`, e mandar o estado depois de congelá-lo deixava os
	# quatro peões na casa em que a partida nasce.
	_root._refresh()
	_root._on_tile_tapped(SHOTS[_index][2])
	match str(SHOTS[_index][0]):
		"20d_metropole_andando":
			# Um turno inteiro pelo caminho de verdade: o botão da barra, os dados, o
			# lance e a caminhada. Se a máquina de fases travar, este print sai com o
			# peão parado.
			_root._roll()
		"20f_metropole_troca":
			# A mesa de troca aberta com duas colunas cheias: é a única tela do jogo
			# que ocupa tudo, e a que mais depende de caber.
			state.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.MANAGE
			_root._refresh()
			_root._open_trade()
		"20j_metropole_cadeia":
			# A fase da cadeia é a barra mais alta que existe: status, dois dados e
			# **três** botões. É o caso que descobria a barra crescendo para cima e
			# entrando por dentro do painel de escritura.
			state.meta[MonopolyRules.JAIL][2] = 0
			state.meta[MonopolyRules.CARDS][2] = 1
			state.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.JAILED
			_root._refresh()
		"20k_metropole_camera":
			# A câmera na mão do jogador: girada, inclinada e afastada, com o botão
			# de recentrar aceso. É o único print em que a mesa não está no
			# enquadramento que o jogo escolhe sozinho.
			_board._orbit(Vector2(-150.0, 40.0))
			_board._zoom(6.0)
			_root._update_recenter()
		"20h_metropole_tampo":
			# O tabuleiro inteiro, que a partida nunca mostra: a câmera segue o peão
			# da vez de perto, e o miolo — nome do jogo e os dois baralhos — só
			# aparece de raspão. É o print que julga o **desenho do tampo**, que é
			# outra coisa do que julgar o enquadramento.
			_board.follow = -1
		"20g_metropole_fim":
			# O fim por rodadas, que é o que exige a tabela de patrimônio: o vencedor
			# é o maior número dela, e ele não aparece em lugar nenhum durante a
			# partida.
			state.meta[MonopolyRules.LIMIT] = 20
			state.meta[MonopolyRules.ROUND] = 20
			state.meta[MonopolyRules.OUT][3] = 1
			_root._refresh()

	_elapsed = 0.0
	set_process(true)


func _process(_delta: float) -> void:
	_elapsed += _delta
	if _elapsed < float(SHOTS[_index][3]):
		return
	set_process(false)
	# Congela: o passo é de 0,085s e a foto sai quadros depois de armada, então
	# sem isto o peão já teria chegado. Mesmo motivo do print da captura do Ludo.
	_board.set_process(false)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://shots/%s.png" % SHOTS[_index][0])
	print("  ", SHOTS[_index][0])
	_next()


## Uma posição com um exemplar de cada coisa que o tabuleiro sabe desenhar.
func _showcase(seats := 4) -> MatchState:
	var rules := RulesLib.new()
	rules.seats = seats
	var state := rules.initial_state()

	# Recife inteira do assento 0, com construção crescente — mostra as casinhas
	# de pé sobre a faixa de cor e a regra de construção uniforme desenhada.
	for tile in [16, 18, 19]:
		state.meta[MonopolyRules.OWNER][tile] = 0
	state.meta[MonopolyRules.HOUSES][16] = 3
	state.meta[MonopolyRules.HOUSES][18] = 2
	state.meta[MonopolyRules.HOUSES][19] = 2

	# Belo Horizonte do assento 1, com um hotel.
	for tile in [31, 32, 34]:
		state.meta[MonopolyRules.OWNER][tile] = 1
	state.meta[MonopolyRules.HOUSES][34] = MonopolyBoard.HOTEL

	# Manaus do assento 2, com uma hipotecada.
	for tile in [6, 8, 9]:
		state.meta[MonopolyRules.OWNER][tile] = 2
	state.meta[MonopolyRules.MORT][8] = 1

	# Aeroportos e companhias espalhados: nenhum tem faixa de cor, e é a barra do
	# dono que responde de quem são.
	state.meta[MonopolyRules.OWNER][5] = 3
	state.meta[MonopolyRules.OWNER][15] = 3
	state.meta[MonopolyRules.OWNER][25] = 0
	state.meta[MonopolyRules.OWNER][12] = 1
	state.meta[MonopolyRules.OWNER][28] = 3
	state.meta[MonopolyRules.OWNER][37] = 3
	state.meta[MonopolyRules.OWNER][39] = 0

	# Dois peões na mesma casa, um preso, um num canto.
	state.meta[MonopolyRules.POS][0] = 24
	state.meta[MonopolyRules.POS][1] = 24
	state.meta[MonopolyRules.POS][2] = MonopolyBoard.JAIL_TILE
	state.meta[MonopolyRules.JAIL][2] = 0
	state.meta[MonopolyRules.POS][3] = MonopolyBoard.GO_TILE

	# As cadeiras que só existem numa mesa cheia, espalhadas para as seis peças
	# aparecerem no mesmo print.
	if seats > 4:
		state.meta[MonopolyRules.POS][4] = 21
		state.meta[MonopolyRules.OWNER][21] = 4
	if seats > 5:
		state.meta[MonopolyRules.POS][5] = 26
		state.meta[MonopolyRules.OWNER][26] = 5
	return state
