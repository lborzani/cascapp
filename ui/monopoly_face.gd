class_name MonopolyFace
extends Control

## O **tampo** do tabuleiro de Metrópole: o anel de 40 casas pintado, sem nada de
## pé em cima dele.
##
## Este nó não é uma tela. Ele é desenhado dentro de um `SubViewport` e vira a
## textura do tampo em [monopoly_board_3d.gd] — o jogador nunca vê este `Control`,
## vê o quadrado de 2048 pixels que ele produz, colado num plano.
##
## ## Por que o tampo é 2D dentro de um jogo 3D
##
## Porque o que o tampo tem é **texto**, e texto em 3D é caro de todo jeito que
## não seja este. `Label3D` por casa são 80 nós (nome e preço) que precisam ser
## reorientados quando a câmera gira; texto pré-renderizado num PNG obriga a
## reexportar a arte a cada nome que mudar; e nenhum dos dois desenha a barra do
## dono, que muda durante a partida.
##
## `draw_string` num `SubViewport` resolve os três: o texto é vetorial e nítido, a
## barra do dono é repintada quando alguém compra, e o arquivo continua sendo
## código em vez de arte.
##
## ## O que fica aqui e o que virou volume
##
## Aqui: as casas, a faixa de cor do grupo, a barra do dono, a hipoteca, os nomes,
## os preços, os **ícones** e o **miolo**. Tudo o que é plano e não muda de forma.
##
## Fora daqui: as peças dos jogadores, as construções, as pilhas de carta e o
## realce da casa em foco. Eles têm altura, sombra e movimento — pintá-los na
## textura seria desenhar a sombra à mão e depois brigar com a sombra de verdade
## que a luz projeta.
##
## ## O anel se reconhece, não se lê
##
## Uma rua diz o grupo dela pela faixa de cor, e é a única coisa que se precisa
## saber olhando o tabuleiro. As outras nove espécies de casa não tinham nada além
## do nome escrito num retângulo de 127 pixels — e nome escrito obriga a **ler**
## quarenta casas para achar a que interessa.
##
## Cada uma ganhou um símbolo na borda de dentro, onde a faixa de cor fica nas
## ruas: "?" na Sorte, baú no Cofre, avião no aeroporto, lâmpada e gota nas
## companhias, moeda no imposto, grades na cadeia, pausa no Descanso, seta na
## Partida. Nenhuma casa tem faixa **e** ícone, então os dois nunca disputam o
## mesmo lugar.
##
## ## O miolo
##
## Era nove unidades de bege — um quinto da área do tabuleiro sem nada, o que num
## tabuleiro de papelão nunca acontece. Agora tem o nome do jogo numa diagonal e
## as molduras dos dois baralhos na outra.
##
## As molduras não são enfeite: elas são **de onde a carta vem**. Até aqui uma
## casa de Sorte fazia um texto aparecer no aviso sem nenhuma origem visível na
## mesa, e é sobre elas que o lado 3D empilha as cartas de verdade.
##
## Repintado só quando muda: comprar, hipotecar, quebrar. Não a cada quadro — são
## 2048² pixels, e o tampo fica idêntico por dezenas de segundos seguidos.

## O anel em unidades: canto quadrado, casa de borda estreita, nove por lado.
## Os números saem da proporção do tabuleiro de caixa — o canto tem cerca de uma
## vez e meia a largura de uma casa comum.
const CORNER := 1.55
const EDGE := 1.0
const PER_SIDE := 9
const SPAN := CORNER * 2.0 + EDGE * PER_SIDE

## Índice do canto de cada lado. Partida embaixo à direita, e daí no sentido
## anti-horário, que é como o tabuleiro original anda.
const GO_CORNER := 0
const JAIL_CORNER := 10
const PARKING_CORNER := 20
const ARREST_CORNER := 30

## De que lado do tabuleiro a casa está. Decide para onde o texto gira e de que
## lado ficam a faixa de cor e a barra do dono.
enum Side { BOTTOM, LEFT, TOP, RIGHT }

## Seis cores de jogador, distinguíveis entre si e sobre o tampo claro. As quatro
## primeiras são as mesmas do Ludo de propósito: quem já jogou lá reconhece "eu
## sou o vermelho" sem reaprender.
##
## Mora aqui e não no nó 3D porque as duas metades precisam delas — o tampo pinta
## a barra do dono, e o volume tinge o peão — e duas listas de seis cores é uma
## lista a mais do que pode existir sem divergir.
const PLAYER_COLORS := [
	Color("c9524d"), Color("5f9e63"), Color("d9a441"), Color("4b7fb5"),
	Color("a071c4"), Color("58b3ae"),
]

const TILE_FILL := Color("e4d5bb")
## O canto é mais escuro porque ele é um evento e não uma propriedade — a
## diferença de tom diz isso antes de o nome ser lido.
const CORNER_FILL := Color("d3c2a5")
const TILE_LINE := Color("241d18")
const MIDDLE_FILL := Color("cdbb9d")
## Texto sobre o tampo claro. O `AppTheme.TEXT` é claro, feito para o fundo
## escuro do app, e aqui sumiria.
const TILE_TEXT := Color("2a2320")
const TILE_TEXT_DIM := Color("6b5c4e")

## Espessura das duas tiras da casa, em unidades. A do grupo é larga porque é
## sobre ela que as construções se apoiam; a do dono é fina porque ela só precisa
## ser **achada**, e uma barra grossa de seis cores em volta do anel competiria
## com o próprio tabuleiro.
const BAND_DEPTH := 0.30
const OWNER_DEPTH := 0.16

## Onde, na profundidade da casa, cada coisa fica. Fração contada da borda de
## **dentro**: 0 é a faixa de cor, 1 é a borda de fora.
##
## Público porque o lado 3D consulta os mesmos números para pousar as construções
## sobre a faixa e os peões entre a faixa e o nome. Dois conjuntos de frações
## seriam duas ideias do que é "sobre a faixa", e elas divergiriam no dia em que a
## faixa mudasse de espessura.
const BAND_AT := BAND_DEPTH * 0.5 / CORNER
const PAWN_AT := 0.30
const NAME_AT := 0.60
const PRICE_AT := 0.88
## O ícone fica na borda de **dentro**, onde a faixa de cor fica nas propriedades
## — e é justamente nas casas sem faixa que ele existe. As duas nunca disputam o
## mesmo lugar porque nenhuma casa tem as duas.
const ICON_AT := 0.13
const CORNER_ICON_AT := 0.22
## Nome e peões do canto, empurrados para fora para o ícone caber. O canto tem
## profundidade de sobra — 1,55 contra a mesma 1,55 de uma casa de borda, mas sem
## faixa de cor nem preço para acomodar.
const CORNER_NAME_AT := 0.52
const CORNER_PAWN_AT := 0.80

## Tinta dos dois baralhos. Cores próprias, e não o cinza do resto: Sorte e Cofre
## são as duas casas que aparecem seis vezes no anel, e distingui-las de longe é
## o que evita o toque para descobrir em qual se caiu.
const CHANCE_INK := Color("d98b3a")
const CHEST_INK := Color("4b7fb5")
## Tintas dos outros ícones. Escuras o bastante para o tampo claro — as do
## `AppTheme` foram feitas para o fundo escuro do app e aqui ficariam lavadas.
const SUCCESS_INK := Color("3f8a52")
const DANGER_INK := Color("c04a3e")
const ACCENT_INK := Color("c08a24")

## Miolo: onde os dois baralhos ficam, medido do centro do tabuleiro em unidades,
## e o tamanho da carta de cima da pilha.
##
## Público porque o lado 3D empilha cartas de verdade em cima da moldura pintada
## aqui. Dois números seriam duas ideias de onde é o baralho, e a pilha pousaria
## ao lado do próprio contorno.
const DECK_OFFSET := 2.7
const DECK_SIZE := Vector2(1.45, 0.98)
## Os dois baralhos ficam numa diagonal e o nome do jogo atravessa a **outra**.
##
## Os sinais parecem trocados e não são: em espaço de desenho `+y` aponta para
## baixo, então um giro positivo leva o texto para a mesma diagonal em que os
## baralhos estão. Foi exatamente assim que a primeira versão saiu — o nome do
## jogo passando por dentro das duas pilhas.
const DECK_ANGLE := -PI * 0.25
const TITLE_ANGLE := -PI * 0.25

## Cor do que é ilustração e não informação: o nome do jogo no miolo, o contorno
## dos baralhos. Baixa de propósito — o miolo tem de dar textura ao vazio sem
## disputar com as casas, que são onde a partida acontece.
const MIDDLE_INK := Color("a1866a")


var state: MatchState = null:
	set(value):
		state = value
		queue_redraw()


func _draw() -> void:
	var unit := minf(size.x, size.y) / SPAN
	var origin := ((size - Vector2.ONE * unit * SPAN) * 0.5).floor()
	if state == null or unit <= 0.0:
		return

	var board := Rect2(origin, Vector2.ONE * unit * SPAN)
	draw_rect(board, TILE_LINE)
	# O miolo é do mesmo tom do tampo, e não escuro: no 3D ele recebe luz e
	# sombra como o resto da peça, e um buraco preto no meio pareceria um furo.
	draw_rect(board.grow(-unit * CORNER), MIDDLE_FILL)
	_draw_middle(unit, origin)

	for tile in MonopolyBoard.SIZE:
		_draw_tile(tile, unit, origin)


## O miolo: o nome do jogo numa diagonal e os dois baralhos na outra.
##
## Ele era um retângulo bege vazio de nove unidades de lado — um quinto da área do
## tabuleiro sem nada, o que num tabuleiro de papelão nunca acontece. E não é só
## enfeite: o contorno dos baralhos é o que **explica de onde a carta vem** quando
## uma sai, que até aqui era um texto que aparecia no aviso sem origem visível.
##
## Tudo em diagonal, como no tabuleiro de mesa, e pelo mesmo motivo dos cantos:
## com a câmera girando não existe orientação certa para os quatro lados, e a
## diagonal fica igualmente torta para dois em vez de de cabeça para baixo para
## um.
func _draw_middle(unit: float, origin: Vector2) -> void:
	var center := origin + Vector2.ONE * unit * SPAN * 0.5
	for which in [MonopolyBoard.CHANCE, MonopolyBoard.CHEST]:
		_draw_deck_slot(which, center, unit)

	var font := AppTheme.font(700)
	var title := "METRÓPOLE"
	var room := unit * (SPAN - CORNER * 2.0)
	var size_pt := _fitting_size(font, title, room * 0.86, int(unit * 0.52))
	if size_pt <= 0:
		return

	draw_set_transform(center, TITLE_ANGLE, Vector2.ONE)
	# Uma faixa sob o nome, e não o nome solto.
	#
	# Solto no meio de nove unidades de bege, ele lia como um carimbo esquecido: a
	# palavra é pequena perto do vazio que ela precisa ocupar, e aumentá-la até
	# preencher deixaria o miolo mais chamativo que o anel, que é onde a partida
	# acontece. A faixa preenche a diagonal com quase nada de tinta.
	var band := Rect2(
		Vector2(-room * 0.47, -size_pt * 0.95), Vector2(room * 0.94, size_pt * 1.9)
	)
	draw_rect(band, Color(MIDDLE_INK, 0.12))
	draw_rect(band, Color(MIDDLE_INK, 0.38), false, maxf(1.0, unit * 0.03))
	var wide := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt).x
	draw_string(
		font, Vector2(-wide * 0.5, size_pt * 0.34), title,
		HORIZONTAL_ALIGNMENT_CENTER, wide, size_pt, Color(MIDDLE_INK, 0.72)
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A moldura de um baralho: onde a pilha de cartas do lado 3D pousa.
##
## Só o contorno, e um pouco maior que a carta: a pilha de verdade fica em cima, e
## um retângulo preenchido embaixo dela não seria visto — o que se vê é a borda
## sobrando em volta, que é o que diz "isto é o lugar do baralho" mesmo com as
## cartas ali.
func _draw_deck_slot(which: int, center: Vector2, unit: float) -> void:
	var spot := center + deck_spot(which) * unit
	var half := DECK_SIZE * unit * 0.5 + Vector2.ONE * unit * 0.13
	draw_set_transform(spot, DECK_ANGLE, Vector2.ONE)
	var frame := Rect2(-half, half * 2.0)
	draw_rect(frame, Color(MIDDLE_INK, 0.16))
	draw_rect(frame, Color(MIDDLE_INK, 0.75), false, maxf(1.0, unit * 0.035))
	var label := "SORTE" if which == MonopolyBoard.CHANCE else "COFRE"
	var font := AppTheme.font(700)
	var size_pt := _fitting_size(font, label, half.x * 1.7, int(unit * 0.22))
	if size_pt > 0:
		draw_string(
			font, Vector2(-half.x, -half.y - size_pt * 0.35), label,
			HORIZONTAL_ALIGNMENT_CENTER, half.x * 2.0, size_pt, Color(MIDDLE_INK, 0.9)
		)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Centro de um baralho, em unidades a partir do centro do tabuleiro.
##
## Estático porque o lado 3D empilha as cartas aqui. Os dois na mesma diagonal e
## em lados opostos, apontando para o centro, como no tabuleiro de mesa.
static func deck_spot(which: int) -> Vector2:
	var side := -1.0 if which == MonopolyBoard.CHANCE else 1.0
	return Vector2(side, side) * DECK_OFFSET


func _draw_tile(tile: int, unit: float, origin: Vector2) -> void:
	var rect := tile_rect(tile, unit, origin)
	draw_rect(rect, CORNER_FILL if is_corner(tile) else TILE_FILL)
	draw_rect(rect, TILE_LINE, false, maxf(1.0, unit * 0.03))

	if MonopolyBoard.can_build_on(tile):
		var band := _edge_strip(rect, inward(tile), unit * BAND_DEPTH)
		draw_rect(band, MonopolyBoard.GROUP_COLORS[MonopolyBoard.group_of(tile)])
		draw_rect(band, TILE_LINE, false, maxf(1.0, unit * 0.02))
	if MonopolyBoard.is_deed(tile):
		_draw_ownership(tile, rect, unit)
	_draw_label(tile, rect, unit)


## A barra do dono, na borda de **fora**. Fora e não dentro porque a de dentro já
## é do grupo, e porque a moldura externa do anel é o que se percorre com o olho
## para responder "o que é meu".
##
## Hipoteca não some com a barra — ela a apaga pela metade e escurece a casa. Uma
## propriedade hipotecada continua sendo do dono, e some da conta só na hora de
## cobrar; escondê-la faria o jogador achar que a perdeu.
func _draw_ownership(tile: int, rect: Rect2, unit: float) -> void:
	var landlord := MonopolyRules.owner_of(state, tile)
	if landlord == MonopolyRules.NO_OWNER:
		return
	var mortgaged := MonopolyRules.is_mortgaged(state, tile)
	var color: Color = PLAYER_COLORS[landlord % PLAYER_COLORS.size()]
	draw_rect(
		_edge_strip(rect, -inward(tile), unit * OWNER_DEPTH),
		Color(color, 0.45 if mortgaged else 1.0)
	)
	if mortgaged:
		# Uma faixa acinzentada por cima, e não um risco na diagonal: o risco
		# atravessa a casa de canto a canto e, num anel de 40 retângulos
		# encostados, lê como um arranhão no desenho.
		draw_rect(rect.grow(-unit * 0.06), Color(TILE_LINE, 0.20))


## Nome curto e preço, girados para o lado do tabuleiro.
##
## O texto acompanha o lado como no tabuleiro de papelão. Com a câmera girando
## para o jogador da vez, isso deixa de ser convenção e vira função: o lado de
## quem joga fica sempre de pé.
func _draw_label(tile: int, rect: Rect2, unit: float) -> void:
	var font := AppTheme.font(600)
	var angle := text_angle(tile)
	# `along` é o comprimento útil do texto e `across` a profundidade da casa. Nos
	# lados esquerdo e direito o retângulo está deitado mas de pé para quem lê,
	# então os dois trocam de lugar.
	var upright := absf(cos(angle)) > 0.5
	var along := rect.size.x if upright else rect.size.y
	var across := rect.size.y if upright else rect.size.x

	# Para onde é "fora do tabuleiro" **no quadro girado**.
	#
	# Com os quatro lados a 0/90/180/270 a resposta é sempre +1, e a conta parece
	# sobra. Ela fica porque é ela que **prova** isso: se um dia um lado voltar a
	# ser orientado para a tela em vez de para a mesa, o texto continua caindo do
	# lado certo em vez de aterrissar em cima da faixa de cor, que foi como este
	# erro apareceu da primeira vez.
	var outer := signf((-inward(tile)).rotated(-angle).y)
	if is_zero_approx(outer):
		outer = 1.0
	var name_at := CORNER_NAME_AT if is_corner(tile) else NAME_AT

	var text := MonopolyBoard.short_name(tile)
	# O teto sai do tamanho da casa, não do tamanho da palavra. Sem ele "Sorte"
	# aparecia no dobro do corpo de "R. Vermelho" na casa ao lado, e o anel virava
	# uma colcha de tipografias.
	var ceiling := int(unit * (0.34 if is_corner(tile) else 0.24))
	var size_pt := _fitting_size(font, text, along * 0.94, ceiling)
	if size_pt <= 0:
		return

	draw_set_transform(rect.get_center(), angle, Vector2.ONE)
	_draw_icon(tile, across, outer, unit)
	draw_string(
		font, Vector2(-along * 0.5, _depth(across, outer, name_at) + size_pt * 0.36), text,
		HORIZONTAL_ALIGNMENT_CENTER, along, size_pt, TILE_TEXT
	)
	var price := MonopolyBoard.price_of(tile)
	if price > 0 and MonopolyRules.owner_of(state, tile) == MonopolyRules.NO_OWNER:
		var small := maxi(7, size_pt - 2)
		draw_string(
			font, Vector2(-along * 0.5, _depth(across, outer, PRICE_AT) + small * 0.36),
			str(price), HORIZONTAL_ALIGNMENT_CENTER, along, small, TILE_TEXT_DIM
		)
	# Desfeita já: a transformação vale para todo o resto do `_draw`, e esquecê-la
	# desenha o tabuleiro inteiro torto a partir da primeira casa da esquerda.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- ícones -------------------------------------------------------------------


## O símbolo da casa, na borda de dentro.
##
## Só as casas **sem faixa de cor** têm um, e não por economia de espaço: a faixa
## é o símbolo da propriedade — ela diz o grupo, que é a única coisa que se
## precisa saber de uma rua olhando o tabuleiro. As outras nove espécies de casa
## não tinham nada além do nome escrito, e nome escrito num retângulo de 127
## pixels é o que obriga a **ler** o anel em vez de reconhecê-lo.
##
## Aeroporto e companhia são propriedades e mesmo assim ganham ícone: elas não
## têm grupo de cor para exibir, e sem símbolo a única diferença entre "Congonh."
## e uma rua qualquer é o nome abreviado.
##
## Desenhado dentro do quadro já girado pelo `_draw_label`, então ele nasce
## alinhado com o nome — e gira junto quando a câmera gira.
func _draw_icon(tile: int, across: float, outer: float, unit: float) -> void:
	var kind := MonopolyBoard.kind_of(tile)
	if kind == MonopolyBoard.Tile.PROPERTY:
		return
	var corner := is_corner(tile)
	var spot := Vector2(0.0, _depth(across, outer, CORNER_ICON_AT if corner else ICON_AT))
	var radius := unit * (0.20 if corner else 0.155)

	match kind:
		MonopolyBoard.Tile.GO:
			_glyph_go(spot, radius)
		MonopolyBoard.Tile.JAIL:
			_glyph_bars(spot, radius, TILE_TEXT_DIM)
		MonopolyBoard.Tile.PARKING:
			_glyph_rest(spot, radius)
		MonopolyBoard.Tile.GOTO_JAIL:
			_glyph_arrest(spot, radius)
		MonopolyBoard.Tile.CHANCE:
			_glyph_letter(spot, radius, "?", CHANCE_INK)
		MonopolyBoard.Tile.CHEST:
			_glyph_chest(spot, radius)
		MonopolyBoard.Tile.TAX:
			_glyph_letter(spot, radius, "M", TILE_TEXT_DIM, true)
		MonopolyBoard.Tile.AIRPORT:
			_glyph_plane(spot, radius)
		MonopolyBoard.Tile.UTILITY:
			_glyph_utility(tile, spot, radius)


## Seta grossa apontando para dentro do tabuleiro. A Partida é a única casa que
## paga por ser **atravessada**, e a seta é o que diz "o caminho continua" — o
## nome sozinho diz só onde ela é.
func _glyph_go(spot: Vector2, radius: float) -> void:
	var stem := radius * 0.30
	draw_colored_polygon(PackedVector2Array([
		spot + Vector2(0.0, -radius),
		spot + Vector2(radius * 0.85, radius * 0.05),
		spot + Vector2(stem, radius * 0.05),
		spot + Vector2(stem, radius),
		spot + Vector2(-stem, radius),
		spot + Vector2(-stem, radius * 0.05),
		spot + Vector2(-radius * 0.85, radius * 0.05),
	]), SUCCESS_INK)


## Grades. Serve à cadeia e ao "vá para a cadeia", que são a mesma ideia em dois
## papéis — visitar e ser mandado.
func _glyph_bars(spot: Vector2, radius: float, tint: Color) -> void:
	var frame := Rect2(spot - Vector2(radius, radius * 0.82), Vector2(radius * 2.0, radius * 1.64))
	draw_rect(frame, tint, false, maxf(1.0, radius * 0.18))
	for index in 3:
		var x := frame.position.x + frame.size.x * (index + 1) / 4.0
		draw_line(
			Vector2(x, frame.position.y + radius * 0.20),
			Vector2(x, frame.end.y - radius * 0.20),
			tint, maxf(1.0, radius * 0.16)
		)


## Pausa: duas barras dentro de um círculo. O Descanso é a única casa do
## tabuleiro em que **nada acontece**, e o símbolo universal de pausa diz isso
## sem precisar de uma ilustração de cadeira de praia num quadrado de 127 pixels.
func _glyph_rest(spot: Vector2, radius: float) -> void:
	draw_arc(spot, radius * 0.92, 0.0, TAU, 22, TILE_TEXT_DIM, maxf(1.0, radius * 0.16), true)
	for side in [-1.0, 1.0]:
		draw_rect(Rect2(
			spot + Vector2(side * radius * 0.34 - radius * 0.11, -radius * 0.42),
			Vector2(radius * 0.22, radius * 0.84)
		), TILE_TEXT_DIM)


## Grades com uma seta entrando nelas. É a diferença entre a casa 10 e a 30, e
## sem ela as duas casas de cadeia do tabuleiro ficariam idênticas de longe.
func _glyph_arrest(spot: Vector2, radius: float) -> void:
	_glyph_bars(spot + Vector2(radius * 0.35, 0.0), radius * 0.80, DANGER_INK)
	var tip := spot + Vector2(-radius * 0.42, 0.0)
	draw_colored_polygon(PackedVector2Array([
		tip + Vector2(radius * 0.42, 0.0),
		tip + Vector2(-radius * 0.10, -radius * 0.46),
		tip + Vector2(-radius * 0.10, radius * 0.46),
	]), DANGER_INK)


## Baú: caixa, tampa e fechadura.
func _glyph_chest(spot: Vector2, radius: float) -> void:
	var body := Rect2(spot - Vector2(radius * 0.92, radius * 0.30), Vector2(radius * 1.84, radius * 1.0))
	draw_rect(body, CHEST_INK)
	var lid := Rect2(
		spot - Vector2(radius * 1.0, radius * 0.80), Vector2(radius * 2.0, radius * 0.52)
	)
	draw_rect(lid, CHEST_INK.darkened(0.22))
	draw_rect(Rect2(
		spot - Vector2(radius * 0.16, radius * 0.16), Vector2(radius * 0.32, radius * 0.46)
	), Color(TILE_FILL, 0.95))


## Uma letra grande num círculo. Serve ao "?" da Sorte e ao "M" do imposto — os
## dois casos em que o símbolo **é** um caractere, e desenhá-lo em polígonos
## seria refazer à mão o que a fonte já resolve.
func _glyph_letter(spot: Vector2, radius: float, text: String, tint: Color, ring := false) -> void:
	if ring:
		draw_arc(spot, radius * 0.95, 0.0, TAU, 22, tint, maxf(1.0, radius * 0.14), true)
	var font := AppTheme.font(700)
	var size_pt := maxi(8, int(radius * (1.5 if ring else 2.1)))
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt).x
	draw_string(
		font, spot + Vector2(-wide * 0.5, size_pt * 0.35), text,
		HORIZONTAL_ALIGNMENT_CENTER, wide, size_pt, tint
	)


## Avião visto de cima: fuselagem, asa em flecha e cauda. As quatro ferrovias do
## jogo de mesa viraram quatro aeroportos aqui, e a peça de avião do jogador usa
## a mesma silhueta.
func _glyph_plane(spot: Vector2, radius: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		spot + Vector2(0.0, -radius),
		spot + Vector2(radius * 0.18, -radius * 0.30),
		spot + Vector2(radius, radius * 0.18),
		spot + Vector2(radius, radius * 0.42),
		spot + Vector2(radius * 0.16, radius * 0.22),
		spot + Vector2(radius * 0.16, radius * 0.66),
		spot + Vector2(radius * 0.46, radius * 0.92),
		spot + Vector2(radius * 0.46, radius),
		spot + Vector2(0.0, radius * 0.84),
		spot + Vector2(-radius * 0.46, radius),
		spot + Vector2(-radius * 0.46, radius * 0.92),
		spot + Vector2(-radius * 0.16, radius * 0.66),
		spot + Vector2(-radius * 0.16, radius * 0.22),
		spot + Vector2(-radius, radius * 0.42),
		spot + Vector2(-radius, radius * 0.18),
		spot + Vector2(-radius * 0.18, -radius * 0.30),
	]), TILE_TEXT_DIM)


## Lâmpada na companhia de energia, gota na de águas.
##
## Qual é qual sai da **ordem no tabuleiro** e não do nome escrito: a primeira
## companhia do anel é a de energia. Comparar strings aqui seria pendurar o
## desenho no texto de `monopoly_board.gd`, e renomear uma casa apagaria o ícone
## dela sem nenhum aviso.
func _glyph_utility(tile: int, spot: Vector2, radius: float) -> void:
	var siblings := MonopolyBoard.group_tiles(MonopolyBoard.Group.UTILITIES)
	if siblings.find(tile) == 0:
		# Bulbo e rosca.
		draw_circle(spot + Vector2(0.0, -radius * 0.18), radius * 0.62, ACCENT_INK)
		draw_rect(Rect2(
			spot + Vector2(-radius * 0.26, radius * 0.40), Vector2(radius * 0.52, radius * 0.46)
		), ACCENT_INK.darkened(0.30))
		return
	# Gota: ponta em cima, barriga redonda embaixo.
	draw_colored_polygon(PackedVector2Array([
		spot + Vector2(0.0, -radius),
		spot + Vector2(radius * 0.66, radius * 0.24),
		spot + Vector2(radius * 0.42, radius * 0.86),
		spot + Vector2(-radius * 0.42, radius * 0.86),
		spot + Vector2(-radius * 0.66, radius * 0.24),
	]), CHEST_INK)


# --- geometria, compartilhada com o lado 3D -----------------------------------


## De que lado a casa fica. Os cantos respondem o lado que **termina** neles, que
## é o lado de onde se chega.
static func side_of(tile: int) -> int:
	if tile < JAIL_CORNER:
		return Side.BOTTOM
	if tile < PARKING_CORNER:
		return Side.LEFT
	if tile < ARREST_CORNER:
		return Side.TOP
	return Side.RIGHT


static func is_corner(tile: int) -> bool:
	return tile % 10 == 0


## Retângulo da casa, na escala pedida.
##
## Estático e com `unit`/`origin` por parâmetro porque quem pergunta são dois: o
## `_draw` daqui, em pixels do `SubViewport`, e o nó 3D, que converte o mesmo
## retângulo em posição no mundo. Uma segunda tabela de coordenadas lá seria uma
## segunda verdade sobre onde fica a casa 19.
##
## As quatro contas são a mesma escrita quatro vezes, e a repetição é proposital:
## unificá-las com rotação de coordenadas produz seis linhas que ninguém confere
## olhando.
static func tile_rect(tile: int, unit: float, origin: Vector2) -> Rect2:
	var corner := unit * CORNER
	var edge := unit * EDGE
	var span := unit * SPAN

	match tile:
		GO_CORNER:
			return _at(origin, span - corner, span - corner, corner, corner)
		JAIL_CORNER:
			return _at(origin, 0.0, span - corner, corner, corner)
		PARKING_CORNER:
			return _at(origin, 0.0, 0.0, corner, corner)
		ARREST_CORNER:
			return _at(origin, span - corner, 0.0, corner, corner)

	match side_of(tile):
		Side.BOTTOM:
			# Da Partida para a esquerda.
			return _at(origin, span - corner - tile * edge, span - corner, edge, corner)
		Side.LEFT:
			# Da cadeia para cima.
			return _at(origin, 0.0, span - corner - (tile - JAIL_CORNER) * edge, corner, edge)
		Side.TOP:
			# Do Descanso para a direita.
			return _at(origin, corner + (tile - PARKING_CORNER - 1) * edge, 0.0, edge, corner)
		_:
			# Do "vá para a cadeia" para baixo.
			return _at(origin, span - corner, corner + (tile - ARREST_CORNER - 1) * edge, corner, edge)


static func _at(origin: Vector2, x: float, y: float, width: float, height: float) -> Rect2:
	return Rect2(origin + Vector2(x, y), Vector2(width, height))


## Para onde é "dentro do tabuleiro", visto desta casa. Posiciona a faixa de cor,
## empurra a barra do dono para o lado oposto e orienta o texto.
static func inward(tile: int) -> Vector2:
	match side_of(tile):
		Side.BOTTOM:
			return Vector2.UP
		Side.LEFT:
			return Vector2.RIGHT
		Side.TOP:
			return Vector2.DOWN
		_:
			return Vector2.LEFT


## Rotação do texto da casa, em radianos: uma volta inteira dividida pelos quatro
## lados, cada um lido de fora para dentro.
##
## **É a orientação do tabuleiro de mesa, e não a de uma tela.** A diferença é
## toda a razão de o texto do lado oposto ficar de cabeça para baixo, e ela é
## deliberada.
##
## A primeira versão desta função servia a um desenho 2D, onde quem lê está
## sempre embaixo: os dois lados horizontais ficavam a zero e os dois verticais a
## ±90°, tudo o mais legível possível de uma posição só. Com a câmera girando
## para o jogador da vez, isso passa a estar errado — a conta na tela é
## `ângulo_no_tampo + giro_da_câmera`, e com os quatro lados quase iguais o lado
## que fica **de frente** para o jogador é justamente o que aparece invertido.
##
## Com os quatro a 0, 90, 180 e 270, o lado de quem joga sai sempre de pé, e é
## para isso que a câmera gira. Os outros três ficam tortos, como num tabuleiro
## de papelão — e é aceitável porque, ao contrário do papelão, este gira.
##
## O canto vai na **diagonal**, no meio do caminho entre os dois lados a que ele
## pertence. É o que o tabuleiro de papelão faz, e pelo mesmo motivo: "Partida" e
## "Cadeia" são as casas mais lidas do tabuleiro, e alinhá-las a um dos dois lados
## as deixa de cabeça para baixo para metade das cadeiras. Na diagonal ficam
## igualmente tortas para as duas — o que, em quatro cadeiras, é o melhor
## resultado possível.
static func text_angle(tile: int) -> float:
	if is_corner(tile):
		return -PI * 0.25 + (tile / 10) * PI * 0.5
	return side_angle(tile)


## Ângulo do **lado**, sem a diagonal do canto.
##
## Separado de `text_angle` porque a câmera consulta este: seguindo um peão, ela
## vira para o lado em que ele está, e um canto não merece uma parada de 45° no
## meio do caminho entre dois lados. O texto do canto continua na diagonal; a
## câmera passa reto.
static func side_angle(tile: int) -> float:
	match side_of(tile):
		Side.BOTTOM:
			return 0.0
		Side.LEFT:
			return PI * 0.5
		Side.TOP:
			return PI
		_:
			return -PI * 0.5


## Uma tira colada numa das quatro bordas do retângulo.
##
## Uma função para as duas tiras que a casa tem — a do grupo, encostada por
## dentro, e a do dono, por fora — porque elas são a mesma conta com o vetor
## invertido. Escrever as duas separadas foi como a primeira versão pôs as duas
## do lado errado sem que nenhuma parecesse errada sozinha.
##
## O sinal é o de tela: `+y` é para **baixo**, então `Vector2.UP` é `-y` e a tira
## de quem aponta para cima fica no começo do retângulo, não no fim.
static func _edge_strip(rect: Rect2, toward: Vector2, thickness: float) -> Rect2:
	var strip := rect
	if absf(toward.x) > 0.0:
		strip.size.x = thickness
		if toward.x > 0.0:
			strip.position.x = rect.end.x - thickness
	else:
		strip.size.y = thickness
		if toward.y > 0.0:
			strip.position.y = rect.end.y - thickness
	return strip


## Converte "fração da profundidade, medida da borda de dentro" em coordenada do
## quadro girado.
static func _depth(across: float, outer: float, fraction: float) -> float:
	return outer * across * (fraction - 0.5)


## O maior corpo que faz o texto caber na largura, ou 0 se nem o menor cabe.
##
## Encolher em vez de cortar: um nome cortado ("Espinhei") parece um bug do
## desenho, e um nome dois pontos menor parece um nome comprido.
static func _fitting_size(font: Font, text: String, room: float, ceiling: int) -> int:
	var wanted := maxi(8, ceiling)
	while wanted >= 8:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted).x <= room:
			return wanted
		wanted -= 1
	return 0
