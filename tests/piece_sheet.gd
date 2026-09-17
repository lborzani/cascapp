extends Control

## Folha de contato das peças: todas as espécies, nas duas cores, em tamanho
## grande e no tamanho real de tabuleiro em celular. Serve para julgar desenho
## de peça sem passar pelo jogo inteiro.
##
##   godot --path . --resolution 720x1280 res://tests/piece_sheet.tscn
##
## Salva em user://pieces.png.

## O fundo de antes do tema Boteco, fixo. Ver `_draw`.
const REFERENCE_GROUND := Color("13100e")

const KINDS := [Board.Kind.KING, Board.Kind.QUEEN, Board.Kind.ROOK, Board.Kind.BISHOP,
	Board.Kind.KNIGHT, Board.Kind.PAWN, Board.Kind.MAN, Board.Kind.DAME,
	Board.Kind.BATTLESHIP]

func _ready() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://pieces.png")
	print("ok")
	get_tree().quit()

const COLUMNS := 4


## A grade sai do tamanho da tela, e não de números cravados. Com as posições
## fixas de antes, a nona espécie caía fora da viewport e simplesmente não
## aparecia — a folha dizia que estava tudo certo porque a peça nova nem era
## desenhada. Uma ferramenta que some com o caso novo é pior que ferramenta
## nenhuma.
func _draw() -> void:
	# Fundo fixo, e não `AppTheme.BACKGROUND`: esta folha é a referência que prova
	# que o desenho não mudou quando o tema muda. Com o fundo do tema, toda troca de
	# paleta sairia como "diferente" — inclusive as que não tocaram desenho nenhum.
	draw_rect(Rect2(Vector2.ZERO, size), REFERENCE_GROUND)
	var rows := int(ceil(float(KINDS.size()) / float(COLUMNS)))
	var cell := Vector2(size.x / COLUMNS, size.y / rows)
	var big := minf(cell.x * 0.44, cell.y * 0.27)
	var small := big * 0.39
	for i in KINDS.size():
		var origin := Vector2((i % COLUMNS) * cell.x, (i / COLUMNS) * cell.y)
		var centre := origin.x + cell.x * 0.5
		var top := origin.y + cell.y * 0.07 + big * 0.5
		_pair(KINDS[i], Vector2(centre, top), big)
		# Tamanho real de tabuleiro num celular, logo abaixo do grande: é nele que
		# se decide se a silhueta ainda é reconhecível.
		var below := top + big * 1.56 + cell.y * 0.06 + small * 0.5
		_pair(KINDS[i], Vector2(centre, below), small)


## A espécie nas duas cores, cada uma sobre a casa em que ela desaparece mais
## facilmente: a branca no escuro, a preta no claro.
func _pair(kind: int, centre: Vector2, side: float) -> void:
	var gap := side * 0.06
	var box := Vector2.ONE * side
	draw_rect(Rect2(centre - box * 0.5, box), AppTheme.BOARD_DARK)
	PieceRenderer.draw_piece(self, Board.piece(Board.Side.WHITE, kind), centre, side)
	var below := centre + Vector2(0, side + gap)
	draw_rect(Rect2(below - box * 0.5, box), AppTheme.BOARD_LIGHT)
	PieceRenderer.draw_piece(self, Board.piece(Board.Side.BLACK, kind), below, side)
