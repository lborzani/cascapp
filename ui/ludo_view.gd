class_name LudoView
extends Control

## O tabuleiro do Ludo: a cruz de 15x15, os quatro currais e os dezesseis peões.
##
## Não herda de `GridView`. Aquele nó é uma grade 8x8 quadrada com moldura e
## coordenadas — tudo o que ele oferece (casa por índice, arrasto, letras na
## borda) fala de um tabuleiro que este não é. O que sobraria em comum é
## `min(largura, altura) / n`, que é uma linha.
##
## **A geometria toda sai de `LudoRules`.** Esta classe traduz progresso em
## coordenada e mais nada: quem decide que a saída da segunda cor fica 13 casas
## adiante é a regra, não o desenho. Uma tabela de casas pintada à mão aqui seria
## uma segunda fonte de verdade sobre o percurso, e as duas divergiriam no dia em
## que a trilha mudasse de tamanho.
##
## Cada casa é desenhada uma vez, no seu lugar. Não há nó por casa nem por peão:
## são 225 células e 16 discos por quadro, todos em `_draw`, que é o mesmo
## arranjo do tabuleiro de xadrez e pela mesma razão — nó de Godot custa caro em
## quantidade, desenho não.

## Peão tocado. A cena decide o que fazer: só ela sabe se o dado já foi rolado.
signal token_tapped(token: int)
## A caminhada acabou e o desenho voltou a ser o estado puro.
signal travel_finished

## Tempo por **casa** andada, e não por lance: um 6 tem de parecer seis passos.
## É o que deixa acompanhar de quem foi a vez sem ler o placar — e o que faz uma
## captura ser vista acontecendo, em vez de já ter acontecido.
##
## A primeira versão usava 0.085s e o peão atravessava seis casas em meio
## segundo: dava para ver que algo tinha andado, não **o quê**. O passo tem de
## ser contável com o olho, porque é assim que se confere um lance de dado.
const STEP_SECONDS := 0.15
## Altura do pulinho entre casas, em fração de casa. Sem ele o peão desliza, e
## deslizar lê como arraste do dedo, não como andar.
const HOP_HEIGHT := 0.33
## Quanto o peão capturado leva para voltar à base. Mais que um passo: a captura
## é a coisa mais importante que acontece no Ludo, e ela tem de ser vista pelo
## dono do peão — que provavelmente está olhando para outro canto do tabuleiro.
const KNOCK_SECONDS := 0.55

## Passo do leque de peões que dividem uma casa, em frações de célula.
##
## Pequeno de propósito: quatro peões abrem 0,54 de célula na diagonal, então a
## pilha continua **dentro** da casa e ainda se lê como uma casa só. Maior que
## isto e um peão empilhado parece estar na casa vizinha, que é uma mentira pior
## que a de não se ver quantos são.
const STACK_STEP := 0.20
## Corpo do número que conta a pilha, em frações de célula.
const STACK_COUNT_SIZE := 0.42

## Tamanho do peão, em frações de célula.
##
## Acima de 1 de propósito: o peão **transborda** a casa, e pode. Ele é mais alto
## que largo, a casa é quadrada, e o que se lê num tabuleiro de 15 casas por lado
## é a silhueta — não a moldura em volta dela. Cabendo certinho na casa ele mede
## 0,88 de célula depois da folga que o `PieceRenderer` já tira, que é o tamanho
## que fazia o Ludo ser difícil de ler.
##
## É este número que responde ao pedido de "peões maiores". Encolher os currais
## **não** responde: o tabuleiro tem 15 casas de lado porque o braço mede 6 (é o
## que dá as 13 casas de trilha por quadrante, 52 no total) mais as 3 do centro,
## e o curral só ocupa a sobra do canto. A célula é `lado / 15` e nada no desenho
## muda isso.
const TOKEN_SIZE := 1.16
## Quem já chegou fica menor: ele não joga mais, e no tamanho cheio quatro deles
## tapam o centro do tabuleiro, que é onde o placar se lê.
const TOKEN_HOME_SIZE := 0.78

const CELLS := 15
## Lado do bloco de cor do curral e do quadrado claro de dentro, em células,
## centrados no canto de 6x6.
##
## Menores que o canto inteiro. Não sobra espaço para a trilha com isso — a
## trilha não passa por aqui —, mas sobra **ar**: o curral deixa de ser um bloco
## maciço de um quarto do tabuleiro e a cruz vira a forma dominante, que é o que
## se percorre com o olho durante a partida.
const YARD_BLOCK := 5.0
const YARD_INNER := 3.6
## A trilha em coordenadas de célula, na ordem em que se anda. Gerada uma vez —
## é a mesma para as quatro cores, que só entram nela em pontos diferentes.
const RING_PATH := [
	# braço da esquerda, indo para o centro pela linha de cima
	Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6),
	# sobe a coluna 6
	Vector2i(6, 5), Vector2i(6, 4), Vector2i(6, 3), Vector2i(6, 2), Vector2i(6, 1),
	Vector2i(6, 0),
	# a entrada de cima e a descida pela coluna 8
	Vector2i(7, 0), Vector2i(8, 0),
	Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5),
	# braço da direita
	Vector2i(9, 6), Vector2i(10, 6), Vector2i(11, 6), Vector2i(12, 6), Vector2i(13, 6),
	Vector2i(14, 6), Vector2i(14, 7), Vector2i(14, 8),
	# volta pela linha 8
	Vector2i(13, 8), Vector2i(12, 8), Vector2i(11, 8), Vector2i(10, 8), Vector2i(9, 8),
	# desce a coluna 8
	Vector2i(8, 9), Vector2i(8, 10), Vector2i(8, 11), Vector2i(8, 12), Vector2i(8, 13),
	Vector2i(8, 14), Vector2i(7, 14), Vector2i(6, 14),
	# sobe a coluna 6
	Vector2i(6, 13), Vector2i(6, 12), Vector2i(6, 11), Vector2i(6, 10), Vector2i(6, 9),
	# braço da esquerda, linha de baixo
	Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8), Vector2i(2, 8), Vector2i(1, 8),
	Vector2i(0, 8), Vector2i(0, 7), Vector2i(0, 6),
]

## Reta final de cada cor, da primeira casa até a última antes da chegada. A
## chegada é o centro, e é comum às quatro.
const HOME_PATH := [
	[Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)],
	[Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5)],
	[Vector2i(13, 7), Vector2i(12, 7), Vector2i(11, 7), Vector2i(10, 7), Vector2i(9, 7)],
	[Vector2i(7, 13), Vector2i(7, 12), Vector2i(7, 11), Vector2i(7, 10), Vector2i(7, 9)],
]

## Canto de cada curral, em célula. Os quatro peões ficam num quadrado interno,
## folgado o bastante para o dedo separar um do outro.
const YARD := [Vector2i(0, 0), Vector2i(9, 0), Vector2i(9, 9), Vector2i(0, 9)]
## As quatro vagas, em torno do centro do canto de 6x6.
##
## A média das duas coordenadas **tem** de ser 2,5, que é onde [method _draw_yard]
## centra o bloco. Elas estavam em 2,1 e 3,9 — média 3,0 —, e os quatro peões
## saíam meia célula para baixo e para a direita: os de cima sobravam ar dentro do
## quadrado claro e os de baixo vazavam para fora dele.
##
## O erro veio de confundir dois espaços. `_center()` já soma meia célula, então
## o centro do bloco vale **2,5 em coordenada de vaga** e 3,0 em célula crua — e a
## correção anterior mirou o número certo do espaço errado. As vagas originais,
## em 1,5 e 3,5, estavam certas; o que se queria de verdade era afastá-las mais
## uma da outra, e isso é o 1,8 de distância abaixo, sem mexer no centro.
const YARD_SPOTS := [
	Vector2(1.6, 1.6), Vector2(3.4, 1.6), Vector2(1.6, 3.4), Vector2(3.4, 3.4),
]

## As quatro cores. Escolhidas para o fundo escuro do app: a vermelha e a
## amarela do tabuleiro de caixa clareiam demais e brigam com o latão da ação,
## então são as mesmas famílias puxadas para o tom que o tema já usa.
const COLORS := [
	Color("c9524d"), Color("5f9e63"), Color("d9a441"), Color("4b7fb5"),
]
## Uma silhueta por assento, e não quatro vezes o mesmo peão tingido.
##
## A cor **continua** sendo a identidade do Ludo — o curral, a trilha e a reta
## final são pintados dela, e nada disso muda. O que a forma acrescenta é a
## segunda leitura: quem não separa o vermelho do verde via quatro peças idênticas
## em quatro tons que, para ele, eram dois. Era o único jogo do app onde a cor
## carregava a identidade sozinha — Metrópole já dá uma peça por assento.
##
## São as peças de xadrez que o app **já desenha**, e é o ponto: o traço é o
## mesmo, o arquivo é o mesmo, e o dia em que o desenho da peça mudar ele muda
## aqui junto. Uma coleção de fichas próprias custaria quatro SVGs novos para
## dizer o que estes quatro já dizem.
##
## As quatro escolhidas são as que menos se confundem no tamanho de uma casa:
## cabeça redonda (peão), perfil de cavalo (assimétrico), mitra com fenda (bispo)
## e ameia quadrada (torre). Dama e rei saíram — a coroa dos dois é a mesma mancha
## a esta escala.
##
## Não há hierarquia nenhuma nisto: os quatro peões do Ludo continuam sendo a
## mesma peça, com as mesmas regras. A forma aqui é crachá, e não patente.
const TOKEN_KINDS := [Board.Kind.PAWN, Board.Kind.KNIGHT, Board.Kind.BISHOP, Board.Kind.ROOK]
const CENTER := Vector2(7.0, 7.0)
## Para onde fica o quarto do centro de cada cor — o mesmo lado por onde a reta
## final dela chega.
const GOAL_SIDE := [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN]


var state: MatchState = null:
	set(value):
		state = value
		queue_redraw()

## Peões que podem se mover agora, em índice de peão da cor da vez. Vazio
## enquanto o dado não foi rolado — e é o que faz o tabuleiro parecer parado
## antes da rolagem, que é exatamente o que ele está.
var movable := PackedInt32Array():
	set(value):
		movable = value
		queue_redraw()

## Peão sob o dedo, para o toque ter resposta antes da tela mudar.
var picked := -1:
	set(value):
		picked = value
		queue_redraw()

var _cell := 0.0
var _origin := Vector2.ZERO
## Pulso do realce dos peões jogáveis. Um contorno parado some no meio de um
## tabuleiro colorido; um que respira é achado sem ser procurado.
var _pulse := 0.0

## O peão que está andando agora, com o progresso de onde ele saiu.
##
## **O estado já é o final**: quem anda é o desenho. Guardar uma posição
## intermediária no `MatchState` significaria um segundo tabuleiro, que discorda
## do verdadeiro no primeiro bug — e é o verdadeiro que viaja pela rede. Aqui só
## existe "de onde", "para onde" e quanto tempo já passou.
var _walk := {}
## Peões mandados para a base neste lance, voltando do lugar em que estavam.
var _knocked: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


## Anima o lance recém-aplicado: o peão anda casa a casa, e quem ele capturou
## volta para a base.
##
## `from` é o progresso de **antes** do lance, que o estado já não tem — quem
## chama leu antes de aplicar. Sem ele o peão só teleporta, que era o que
## acontecia: o tabuleiro mudava e ninguém via o quê.
func travel(player: int, token: int, from: int, to: int, knocked: Array) -> void:
	var steps := maxi(1, to - from)
	var duration := steps * STEP_SECONDS
	_knocked = []
	for entry in knocked:
		_knocked.append({
			"player": int(entry["player"]),
			"token": int(entry["token"]),
			"from": int(entry["from"]),
			# Começa **negativo**: a captura acontece quando o peão chega, não
			# quando ele sai. Enquanto o relógio é negativo o capturado fica
			# parado na casa dele, esperando a batida — que é o que se vê num
			# tabuleiro de verdade.
			"elapsed": -duration,
		})
	_walk = {
		"player": player,
		"token": token,
		"from": from,
		"to": to,
		"elapsed": 0.0,
		"duration": duration,
	}
	queue_redraw()


## Verdadeiro enquanto **qualquer** coisa está andando, inclusive um capturado
## voltando para a base. A cena espera por isto antes de devolver a vez: sem o
## capturado na conta, o dado da vez seguinte rolava com um peão ainda no ar.
func is_travelling() -> bool:
	return not _walk.is_empty() or not _knocked.is_empty()


## O tabuleiro **não** declara altura mínima, e a ausência é a correção.
##
## Ele declarava `custom_minimum_size.y = size.x`, e aquilo estava certo enquanto
## a tela era uma coluna: ali a largura era o que sobrava, e reservar a mesma
## altura evitava uma faixa morta entre o tabuleiro e o dado.
##
## Deitado, a conta se inverte e vira uma exigência impossível. Numa fileira
## `[placar 150][tabuleiro][dado 150]` a largura do tabuleiro é a **sobra**, e ele
## passou a exigir essa sobra de volta em altura. Num aparelho 16:9 a base é
## 768x432, a sobra dá 444, e ele pedia 444 de altura para uma faixa de 432 — doze
## pixels, quase invisíveis. Num 2.17:1 a base deitada vira ~938 de largura, a
## sobra vai a ~614, e ele pede 614: a fileira inteira estoura para fora da tela e
## leva junto o quarto cartão do placar, que é o do próprio jogador.
##
## Sem a linha, o nó recebe a altura da faixa e [method _layout] desenha um
## quadrado do menor lado, centrado no que receber. A sobra de largura vira
## margem, que é o que ela é.
##
## A lição de forma: uma dimensão mínima derivada da outra é um acordo com o
## sentido do layout, e ele foi trocado de coluna para fileira sem que este
## arquivo soubesse.


func _process(delta: float) -> void:
	var busy := is_travelling()

	if not _walk.is_empty():
		_walk["elapsed"] = float(_walk["elapsed"]) + delta
		if float(_walk["elapsed"]) >= float(_walk["duration"]):
			_walk = {}

	if not _knocked.is_empty():
		var still: Array[Dictionary] = []
		for entry in _knocked:
			entry["elapsed"] = float(entry["elapsed"]) + delta
			if float(entry["elapsed"]) < KNOCK_SECONDS:
				still.append(entry)
		_knocked = still

	if busy and not is_travelling():
		# O sinal sai depois de o desenho já ter voltado ao estado puro: quem
		# espera por ele pode mexer no tabuleiro sem disputar com a animação.
		queue_redraw()
		travel_finished.emit()

	if not movable.is_empty():
		_pulse = fmod(_pulse + delta, 1.2)
		busy = true

	if busy:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var position := Vector2.ZERO
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			return
		position = touch.position
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
			return
		position = click.position
	else:
		return
	accept_event()
	var token := _token_at(position)
	if token >= 0:
		token_tapped.emit(token)


## Peão da cor da vez mais próximo do toque, dentro do raio de um peão. Só os
## jogáveis respondem: tocar num peão preso não é um erro que mereça mensagem,
## é um toque em cima de uma peça que não é alvo.
func _token_at(position: Vector2) -> int:
	if state == null or movable.is_empty():
		return -1
	var player := LudoRules.turn_of(state)
	var best := -1
	var best_distance := _cell * 0.75
	for token in movable:
		var distance := _token_center(player, token).distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best = token
	return best


# --- geometria ----------------------------------------------------------------


func _layout() -> void:
	_cell = minf(size.x, size.y) / float(CELLS)
	_origin = ((size - Vector2.ONE * _cell * CELLS) * 0.5).floor()


func _rect(cell: Vector2i) -> Rect2:
	return Rect2(_origin + Vector2(cell) * _cell, Vector2.ONE * _cell)


func _center(cell: Vector2) -> Vector2:
	return _origin + (cell + Vector2(0.5, 0.5)) * _cell


## Onde este peão está desenhado, seja qual for a parte do percurso.
##
## Ponto único de tradução progresso → tela. O desenho e o toque usam o mesmo,
## que é o que garante que o alvo do dedo é o disco que se vê — e, durante uma
## animação, que ele não responde de onde não está.
func _token_center(player: int, token: int) -> Vector2:
	if not _walk.is_empty() and _walk["player"] == player and _walk["token"] == token:
		return _walking_center()
	for entry in _knocked:
		if entry["player"] == player and entry["token"] == token:
			return _knocked_center(entry)
	var prog := LudoRules.progress(state)[LudoRules.slot(player, token)]
	return _center_at(player, prog, token) + _stack_offset(player, token, prog)


## Deslocamento deste peão dentro da casa, quando ele divide a casa com outros.
##
## Empilhar virou lance legal — dois peões da mesma cor podem dividir uma casa, e
## numa casa segura duas cores também. Sem isto os dois eram desenhados no
## **mesmo pixel**: quatro peões numa casa apareciam como um, e não havia como
## saber quantos nem de quem eram.
##
## Em leque na diagonal, e não em fileira: a casa mede uma célula, e quatro peões
## lado a lado sairiam dela pelos dois lados. Na diagonal eles se cobrem
## parcialmente, que é como uma pilha de fichas se lê numa mesa.
func _stack_offset(player: int, token: int, prog: int) -> Vector2:
	var here := _stack_at(player, prog)
	if here.size() < 2:
		return Vector2.ZERO
	var index := 0
	for position in here.size():
		if here[position][0] == player and here[position][1] == token:
			index = position
			break
	var step := _cell * STACK_STEP
	return Vector2(1.0, -1.0) * ((float(index) - (here.size() - 1) * 0.5) * step)


## Quem divide a casa deste peão, em ordem estável de cor e número.
##
## Só na trilha e na reta final: no curral e na chegada cada peão já tem o seu
## canto, e ali empilhar nunca foi possível.
##
## A comparação é por **casa de trilha absoluta**, e não por progresso: duas
## cores no mesmo lugar têm progressos diferentes, porque cada uma conta a partir
## da própria saída. É a mesma conta que a captura usa.
func _stack_at(player: int, prog: int) -> Array:
	var here := []
	if state == null or prog <= LudoRules.BASE or prog >= LudoRules.GOAL:
		return here
	var progress := LudoRules.progress(state)
	var square := LudoRules.ring_square(player, prog)
	for other in LudoRules.PLAYERS:
		for token in LudoRules.TOKENS:
			# Quem está no ar não conta: ele ainda não pousou, e contá-lo
			# empurraria para o lado quem já está parado ali.
			if _is_moving(other, token):
				continue
			var theirs: int = progress[LudoRules.slot(other, token)]
			if theirs <= LudoRules.BASE or theirs >= LudoRules.GOAL:
				continue
			if square >= 0:
				if LudoRules.ring_square(other, theirs) == square:
					here.append([other, token])
			elif other == player and theirs == prog:
				here.append([other, token])
	return here


## O peão entre duas casas: interpola as duas pontas e joga um pulinho por cima.
##
## A conta é feita em **progresso**, não em pixels: um peão que dobra a esquina
## do braço do tabuleiro interpola entre a casa antes e a depois da curva, e sai
## andando a curva em vez de cortá-la em diagonal.
func _walking_center() -> Vector2:
	var player := int(_walk["player"])
	var token := int(_walk["token"])
	var from := int(_walk["from"])
	var to := int(_walk["to"])
	var ratio := clampf(float(_walk["elapsed"]) / maxf(0.001, float(_walk["duration"])), 0.0, 1.0)
	var travelled := from + (to - from) * ratio
	var previous := floori(travelled)
	var following := mini(previous + 1, to)
	var between := travelled - previous
	var spot := (
		_center_at(player, previous, token).lerp(_center_at(player, following, token), between)
	)
	# Um pulo por casa, e não um por lance: `between` volta a zero a cada casa.
	return spot - Vector2(0.0, sin(between * PI) * _cell * HOP_HEIGHT)


## O capturado voltando: sobe do lugar em que estava e cai na base. A curva é a
## mesma do pulo, alta o bastante para a viagem ser vista atravessando o
## tabuleiro em vez de sumir e reaparecer.
func _knocked_center(entry: Dictionary) -> Vector2:
	var player := int(entry["player"])
	var token := int(entry["token"])
	var ratio := clampf(float(entry["elapsed"]) / KNOCK_SECONDS, 0.0, 1.0)
	var origin := _center_at(player, int(entry["from"]), token)
	var home := _center(Vector2(YARD[player]) + YARD_SPOTS[token])
	return origin.lerp(home, ratio) - Vector2(0.0, sin(ratio * PI) * _cell * 1.2)


## Centro da casa de um progresso qualquer.
##
## `token` só muda as duas pontas do percurso, que são as únicas em que peões da
## mesma cor não se empilham: no curral e na chegada cada um tem o seu canto.
## Sem peão (`-1`) as duas devolvem o meio, que é o que uma viagem em curso
## precisa quando ainda não se sabe de qual peão ela é.
func _center_at(player: int, prog: int, token := -1) -> Vector2:
	if prog <= LudoRules.BASE:
		var spot: Vector2 = YARD_SPOTS[token] if token >= 0 else Vector2(2.5, 2.5)
		return _center(Vector2(YARD[player]) + spot)
	if prog >= LudoRules.GOAL:
		# Quem chegou fica encostado no próprio triângulo do centro, e não em
		# volta do meio dele: assim os quatro peões de uma cor se acumulam do
		# lado dela, e o centro continua dizendo de quem é cada quarto.
		var toward: Vector2 = GOAL_SIDE[player]
		var across := Vector2(toward.y, -toward.x)
		var offset := (float(token) - (LudoRules.TOKENS - 1) * 0.5) if token >= 0 else 0.0
		return _center(CENTER) + toward * _cell * 0.95 + across * offset * _cell * 0.5
	if prog > LudoRules.RING - 1:
		return _center(Vector2(HOME_PATH[player][prog - LudoRules.RING]))
	return _center(Vector2(RING_PATH[LudoRules.ring_square(player, prog)]))


# --- desenho ------------------------------------------------------------------


func _draw() -> void:
	_layout()
	if state == null:
		return
	_draw_board()
	_draw_tokens()


func _draw_board() -> void:
	var board := Rect2(_origin, Vector2.ONE * _cell * CELLS)
	draw_rect(board, AppTheme.BOARD_FRAME)

	for player in LudoRules.PLAYERS:
		_draw_yard(player)
	for index in RING_PATH.size():
		var cell: Vector2i = RING_PATH[index]
		# Casa de saída pintada da cor de quem sai dela: é a informação que
		# responde "por onde eu entro" sem nenhuma legenda.
		var owner := index / LudoRules.START_STEP
		var is_start := index % LudoRules.START_STEP == 0
		var fill := Color(COLORS[owner], 0.85) if is_start else AppTheme.BOARD_LIGHT
		_draw_cell(cell, fill)
		if not is_start and LudoRules.is_safe(index):
			_draw_star(cell)
	for player in LudoRules.PLAYERS:
		for cell in HOME_PATH[player]:
			_draw_cell(cell, Color(COLORS[player], 0.55))
	_draw_center()


## Uma casa da trilha. O contorno é o que a separa da vizinha — sem ele a trilha
## é uma faixa creme contínua, e contar casas na hora de escolher o peão vira
## adivinhação.
##
## Mais escuro e mais grosso do que era: o peão passou a transbordar a casa, e um
## contorno fraco desaparecia embaixo dele justamente onde a contagem importa.
func _draw_cell(cell: Vector2i, fill: Color) -> void:
	var rect := _rect(cell).grow(-_cell * 0.04)
	draw_rect(rect, fill)
	draw_rect(rect, Color(0, 0, 0, 0.38), false, maxf(1.0, _cell * 0.055))


## Estrela da casa segura. Um losango, e não uma estrela de cinco pontas: em 22
## pixels a de cinco pontas vira um borrão, e o que precisa ser dito é "esta casa
## é diferente".
func _draw_star(cell: Vector2i) -> void:
	var middle := _center(Vector2(cell))
	var radius := _cell * 0.22
	draw_colored_polygon(
		PackedVector2Array([
			middle + Vector2(0, -radius), middle + Vector2(radius, 0),
			middle + Vector2(0, radius), middle + Vector2(-radius, 0),
		]),
		Color(0, 0, 0, 0.22)
	)


## Curral: o bloco da cor, com o quadrado claro onde os peões descansam. O
## contraste entre os dois é o que faz "peão na base" ser lido de longe.
func _draw_yard(player: int) -> void:
	var middle := _center(Vector2(YARD[player]) + Vector2(2.5, 2.5))
	var block := Rect2(
		middle - Vector2.ONE * _cell * YARD_BLOCK * 0.5, Vector2.ONE * _cell * YARD_BLOCK
	)
	draw_rect(block, Color(COLORS[player], 0.85))
	# Contorno escuro: o bloco deixou de encostar nas bordas do canto, e sem a
	# linha ele flutuava sobre o fundo do tabuleiro em vez de ser uma peça dele.
	draw_rect(block, Color(0, 0, 0, 0.35), false, maxf(1.0, _cell * 0.05))
	var inner := Rect2(
		middle - Vector2.ONE * _cell * YARD_INNER * 0.5, Vector2.ONE * _cell * YARD_INNER
	)
	draw_rect(inner, Color(AppTheme.BOARD_LIGHT, 0.92))


## O centro é a chegada das quatro cores, então é dividido em quatro triângulos
## que apontam para os donos.
func _draw_center() -> void:
	var middle := _center(CENTER)
	var half := _cell * 1.5
	var corners := [
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
	]
	# Cada triângulo aponta para a reta final da sua cor: esquerda, topo,
	# direita, base — a mesma ordem em que as cores jogam.
	var edges := [[3, 0], [0, 1], [1, 2], [2, 3]]
	for player in LudoRules.PLAYERS:
		var edge: Array = edges[player]
		draw_colored_polygon(
			PackedVector2Array([middle, middle + corners[edge[0]], middle + corners[edge[1]]]),
			Color(COLORS[player], 0.9)
		)


## Os parados primeiro, os que estão em movimento por cima. Um peão andando
## passa por casas ocupadas, e passar **por baixo** de quem está parado lê como
## se ele tivesse sumido no meio do caminho.
func _draw_tokens() -> void:
	_draw_impacts()
	var turn := LudoRules.turn_of(state)
	var moving := []
	for player in LudoRules.PLAYERS:
		for token in LudoRules.TOKENS:
			if _is_moving(player, token):
				moving.append([player, token])
			else:
				_draw_token(player, token, player == turn)
	for entry in moving:
		_draw_token(entry[0], entry[1], entry[0] == turn)


## A marca da casa onde alguém foi comido: um anel que abre e some, na cor de
## quem perdeu o peão.
##
## O voo até a base sozinho não bastava — ele conta para **onde** o peão foi, e
## não o que aconteceu. A captura acontece numa casa só, num instante só, e o
## dono do peão quase sempre está olhando para outro canto do tabuleiro; o anel
## é o que marca o lugar depois de o peão já ter saído dele.
func _draw_impacts() -> void:
	for entry in _knocked:
		# Relógio negativo é o peão que ainda vai ser atingido: o anel só abre
		# quando quem o derruba chega na casa.
		if float(entry["elapsed"]) < 0.0:
			continue
		var ratio := clampf(float(entry["elapsed"]) / KNOCK_SECONDS, 0.0, 1.0)
		# Só na primeira metade da volta: o anel é o golpe, não a viagem.
		if ratio > 0.5:
			continue
		var burst := ratio / 0.5
		var middle := _center_at(int(entry["player"]), int(entry["from"]), int(entry["token"]))
		var color: Color = COLORS[int(entry["player"])]
		draw_arc(
			middle, _cell * (0.35 + 0.7 * burst), 0.0, TAU, 32,
			Color(color, 0.85 * (1.0 - burst)), maxf(2.0, _cell * 0.09 * (1.0 - burst)), true
		)
		draw_circle(middle, _cell * 0.34 * (1.0 - burst), Color(color, 0.30 * (1.0 - burst)))


## O peão está numa casa da própria cor — a reta final, que é a única parte da
## trilha pintada com a cor do dono.
func _on_home_stretch(player: int, token: int) -> bool:
	var prog: int = LudoRules.progress(state)[LudoRules.slot(player, token)]
	return prog > LudoRules.RING - 1 and prog < LudoRules.GOAL


func _is_moving(player: int, token: int) -> bool:
	if not _walk.is_empty() and _walk["player"] == player and _walk["token"] == token:
		return true
	return _knock_ratio(player, token) >= 0.0


## Quanto da volta para a base este peão já andou, ou -1 se ele não está
## voltando. É o mesmo número que move o desenho e que o infla no meio do
## caminho — um só, para os dois não discordarem.
func _knock_ratio(player: int, token: int) -> float:
	for entry in _knocked:
		if entry["player"] == player and entry["token"] == token:
			return clampf(float(entry["elapsed"]) / KNOCK_SECONDS, 0.0, 1.0)
	return -1.0


## O peão **é uma peça de xadrez**, tingida — uma por assento, de [constant
## TOKEN_KINDS]. Um disco colorido diria a mesma coisa e diria em outra língua: o
## app inteiro desenha peça com o mesmo traço, e o Ludo com fichas chapadas
## pareceria emprestado de outro lugar. Como é a mesma textura, o dia em que o
## desenho da peça mudar ele muda aqui junto.
func _draw_token(player: int, token: int, is_turn: bool) -> void:
	var middle := _token_center(player, token)
	var home := LudoRules.progress(state)[LudoRules.slot(player, token)] == LudoRules.GOAL
	# Peão que chegou é menor: ele não joga mais, e no tamanho cheio quatro deles
	# tapam o centro do tabuleiro — que é justamente onde o placar se lê.
	var scale := TOKEN_HOME_SIZE if home else TOKEN_SIZE
	# Quem está no ar cresce um pouco no meio do voo. É o mesmo truque do
	# tabuleiro de xadrez para a peça que viaja: sem a mudança de tamanho, um
	# disco atravessando o tabuleiro parece deslizar por baixo dele.
	var knocked := _knock_ratio(player, token)
	# O eliminado é derrubado: encolhe enquanto voa, gira como peça tombada, e
	# volta ao tamanho ao pousar na base. Antes ele só atravessava o tabuleiro
	# inteiro em pé, o que lia como "mudou de lugar" e não como "foi comido".
	var spin := 0.0
	if knocked >= 0.0:
		scale *= lerpf(1.0, 0.62, sin(knocked * PI))
		spin = knocked * TAU
	elif not _walk.is_empty() and _walk["player"] == player and _walk["token"] == token:
		scale *= 1.06
	var radius := _cell * scale * 0.5
	var playable := is_turn and movable.has(token)

	if playable:
		# Halo que respira. Sai do próprio tamanho do peão, então acompanha
		# qualquer tabuleiro sem número solto nenhum.
		var beat := 0.5 + 0.5 * sin(_pulse / 1.2 * TAU)
		draw_circle(
			middle, radius * (1.25 + 0.16 * beat), Color(AppTheme.ACCENT, 0.22 + 0.16 * beat)
		)
	# `is_turn` junto: `picked` é um índice de peão, e sem a cor ele acendia o
	# peão de mesmo número das **quatro** cores — três anéis amarelos em peças
	# que ninguém tinha tocado.
	if is_turn and token == picked:
		draw_arc(middle, radius * 1.15, 0.0, TAU, 28, AppTheme.ACCENT, maxf(2.0, _cell * 0.07), true)

	# Disco claro por baixo **só na reta final**.
	#
	# Ele existe por um motivo estreito: ali o peão fica sobre uma casa da própria
	# cor, e sem a base clara a silhueta some no fundo dela. Estava sendo desenhado
	# em todo peão, e nas casas creme da trilha e no curral — que já são claros —
	# ele não separava nada: virava um anel claro em volta de cada peça, lido como
	# contorno que ninguém pediu.
	#
	# A regra é a mesma de sempre: um recurso que resolve um caso não deve aparecer
	# nos outros. O que dá contorno ao peão em toda casa é o traço do próprio
	# desenho, e ele já existe.
	if _on_home_stretch(player, token):
		draw_circle(middle, radius * 0.92, Color(AppTheme.BOARD_LIGHT, 0.85))
	PieceRenderer.draw_piece(
		self, Board.piece(Board.Side.WHITE, TOKEN_KINDS[player % TOKEN_KINDS.size()]),
		middle, _cell * scale, 1.0, 1.0, false, COLORS[player], spin
	)
	_draw_stack_count(player, token, middle, radius)


## Quantos peões há nesta casa, num selo sobre o **último** da pilha.
##
## O leque já mostra que são vários e de que cores; o número diz **quantos**, que
## em quatro peões sobrepostos deixa de ser contável de relance. Só no de cima da
## pilha, porque um selo por peão seria quatro números dizendo a mesma coisa.
func _draw_stack_count(player: int, token: int, middle: Vector2, radius: float) -> void:
	if _is_moving(player, token):
		return
	var prog := LudoRules.progress(state)[LudoRules.slot(player, token)]
	var here := _stack_at(player, prog)
	if here.size() < 2:
		return
	var last: Array = here[here.size() - 1]
	if last[0] != player or last[1] != token:
		return

	var font := AppTheme.font(700)
	var body := maxi(8, int(_cell * STACK_COUNT_SIZE))
	var text := str(here.size())
	var badge := middle + Vector2(radius * 0.86, -radius * 0.86)
	draw_circle(badge, body * 0.62, Color(AppTheme.BACKGROUND, 0.92))
	draw_arc(badge, body * 0.62, 0.0, TAU, 20, Color(AppTheme.TEXT, 0.55), maxf(1.0, _cell * 0.03), true)
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, body).x
	draw_string(
		font, badge + Vector2(-wide * 0.5, body * 0.36), text,
		HORIZONTAL_ALIGNMENT_CENTER, wide, body, AppTheme.TEXT
	)
