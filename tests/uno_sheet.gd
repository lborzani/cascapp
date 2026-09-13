extends Control

## Folha de contato do baralho: as 108 cartas, o verso, e uma linha em tamanho de
## mão de celular. Serve para julgar o desenho sem passar pela partida.
##
##   godot --path . --resolution 1100x1500 res://tests/uno_sheet.tscn
##
## Salva em user://uno_cards.png.
##
## Duas leituras, e a segunda é a que decide:
##
## - a **grade** mostra as 15 espécies nas quatro cores, grandes. É onde se julga
##   se o símbolo está bem desenhado;
## - a **fita de baixo** mostra uma mão em leque no tamanho real, sobrepostas como
##   ficam na tela. É onde se descobre que um símbolo bonito grande vira uma
##   mancha em 90 px, e que o canto pequeno é a única coisa que se lê no leque.
##
## A folha desenha o baralho **inteiro** e não uma seleção: uma ferramenta que
## mostra as cartas escolhidas à mão é uma ferramenta que some justamente com a
## carta que ninguém lembrou de acrescentar.

const COLUMNS := 15
## Uma linha por cor, mais a linha dos curingas e do verso.
const CARD_ROWS := 5

## Altura de carta na mão de um celular de 432 px de largura, medida do leque de
## sete cartas: é ela que decide se o desenho serve.
const HAND_HEIGHT := 96.0


func _ready() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://uno_cards.png")
	print("ok — user://uno_cards.png")
	get_tree().quit()


## As 15 espécies de uma cor, na ordem em que a carta aparece na mão: os dez
## algarismos e as três ações. As duas últimas colunas ficam para os curingas, que
## não têm cor.
const VALUES := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
	UnoRules.SKIP, UnoRules.REVERSE, UnoRules.DRAW_TWO]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), AppTheme.BACKGROUND)

	# A grade sai do tamanho da tela, como a folha das peças: com posições
	# cravadas, a carta nova cai fora da viewport e a folha diz que está tudo certo
	# porque a carta nem foi desenhada.
	var cell := Vector2(size.x / COLUMNS, size.y * 0.78 / CARD_ROWS)
	var height := minf(cell.y * 0.86, cell.x / UnoCardArt.ASPECT * 0.92)

	for color in UnoCardArt.COLORS.size():
		for index in VALUES.size():
			_place(UnoRules.card(color, VALUES[index]), index, color, cell, height)

	# Última linha: os dois curingas e o verso, com folga entre eles porque não são
	# uma sequência — são três coisas diferentes.
	var last := UnoCardArt.COLORS.size()
	_place(UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD), 0, last, cell, height)
	_place(UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR), 1, last, cell, height)
	UnoCardArt.draw_back(self, _center_of(2, last, cell), height)

	# Uma carta apagada, ao lado: é como a mão mostra o que não pode ser jogado, e
	# ela precisa continuar legível — apagada demais vira mão pela metade.
	UnoCardArt.draw_card(
		self, UnoRules.card(UnoRules.CardColor.BLUE, 5), _center_of(4, last, cell), height,
		0.0, true
	)

	# O ícone do menu, que **não** sai daqui — é `assets/pieces/card_*.svg`, pelo
	# mesmo caminho dos outros cinco jogos. Ele aparece na folha porque é a arte do
	# Uno também, e porque o erro que ele comete é invisível em qualquer outro
	# lugar: no tamanho da grade do menu, um leque mal desenhado vira uma mancha
	# clara, e a grade inteira passa a ter um cartão que não se sabe o que é.
	# Grande para julgar o desenho, e no tamanho da grade do menu logo ao lado, que
	# é onde ele é decidido — a folha das peças faz o mesmo par pelo mesmo motivo.
	# A branca sobre o fundo do app, a preta sobre madeira clara: cada uma sobre o
	# fundo em que ela some mais fácil.
	for index in 2:
		var white := index == 0
		var icon := Board.piece(
			Board.Side.WHITE if white else Board.Side.BLACK, Board.Kind.CARD
		)
		var spot := _center_of(6 + index * 2, last, cell)
		var box := Vector2.ONE * height
		if not white:
			draw_rect(Rect2(spot - box * 0.5, box), AppTheme.BOARD_LIGHT)
		PieceRenderer.draw_piece(self, icon, spot, height)

		var small := spot + Vector2(height * 0.78, 0.0)
		var small_box := Vector2.ONE * height * 0.42
		if not white:
			draw_rect(Rect2(small - small_box * 0.5, small_box), AppTheme.BOARD_LIGHT)
		PieceRenderer.draw_piece(self, icon, small, height * 0.42)

	_hand(Vector2(size.x * 0.5, size.y * 0.89))


func _place(card_code: int, column: int, row: int, cell: Vector2, height: float) -> void:
	UnoCardArt.draw_card(self, card_code, _center_of(column, row, cell), height)


func _center_of(column: int, row: int, cell: Vector2) -> Vector2:
	return Vector2((column + 0.5) * cell.x, (row + 0.6) * cell.y)


## Sete cartas em leque, no tamanho da mão de verdade e sobrepostas como ficam na
## tela. É a única parte da folha que responde à pergunta que importa.
func _hand(center: Vector2) -> void:
	var hand := [
		UnoRules.card(UnoRules.CardColor.RED, 7),
		UnoRules.card(UnoRules.CardColor.RED, UnoRules.DRAW_TWO),
		UnoRules.card(UnoRules.CardColor.YELLOW, 0),
		UnoRules.card(UnoRules.CardColor.GREEN, UnoRules.SKIP),
		UnoRules.card(UnoRules.CardColor.BLUE, 9),
		UnoRules.card(UnoRules.CardColor.BLUE, UnoRules.REVERSE),
		UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR),
	]
	var step := UnoCardArt.width_for(HAND_HEIGHT) * 0.62
	var spread := 0.10
	for index in hand.size():
		var offset := index - (hand.size() - 1) * 0.5
		var angle := offset * spread
		# O arco: as das pontas descem, como um leque segurado pelo meio.
		var lift := absf(offset) * HAND_HEIGHT * 0.045
		UnoCardArt.draw_card(
			self, hand[index], center + Vector2(offset * step, lift), HAND_HEIGHT, angle
		)
