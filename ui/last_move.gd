class_name LastMoveLine
extends Control

## Uma linha sobre o tabuleiro: quem jogou por último e o quê.
##
## Substitui o painel de histórico completo. Num celular em retrato a lista
## inteira ou rouba altura do tabuleiro ou vira um painel que cobre a partida —
## e a pergunta que o jogador faz de verdade, quando volta a olhar a tela, é
## "o que o outro acabou de jogar?". Essa cabe numa linha.
##
## A peça desenhada é a que se moveu, na cor de quem jogou, então o "quem" é
## respondido por imagem antes da leitura; o nome do lado fica ao lado só para
## quem quiser confirmar.

const HEIGHT := 24.0
const PIECE_SIZE := 22.0
const GAP := 7.0

const SIDE_NAMES := ["Brancas", "Pretas"]

## Peça que se moveu, como inteiro de `Board.piece`. Zero apaga a linha.
##
## Quem esconde a linha é o Control que a contém, não ela: um filho invisível de
## `VBoxContainer` some da conta de altura, e é o espaço que precisa sumir junto.
var piece := 0:
	set(value):
		piece = value
		queue_redraw()

var notation := "":
	set(value):
		notation = value
		queue_redraw()


func has_move() -> bool:
	return piece != 0 and not notation.is_empty()

## Modo mesa: a linha do jogador do outro lado é lida de lá. Mesma razão do
## cartão para girar pelo nó e não dentro de `_draw` — ver `ui/player_card.gd`.
var upside_down := false:
	set(value):
		upside_down = value
		_apply_rotation()


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_rotation()


func _apply_rotation() -> void:
	pivot_offset = size * 0.5
	rotation = PI if upside_down else 0.0


func _draw() -> void:
	if piece == 0 or notation.is_empty():
		return

	var name_font := AppTheme.font(400)
	var move_font := AppTheme.font(600)
	var side_name: String = SIDE_NAMES[Board.side_of(piece)]
	var name_width := name_font.get_string_size(side_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var move_width := move_font.get_string_size(notation, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x

	# Centralizado como bloco, para a linha não dançar de um lado para o outro a
	# cada lance — o olho volta sempre ao mesmo ponto da tela.
	var total := PIECE_SIZE + GAP + name_width + GAP + move_width
	var x := (size.x - total) * 0.5
	var middle := size.y * 0.5

	PieceRenderer.draw_piece(self, piece, Vector2(x + PIECE_SIZE * 0.5, middle), PIECE_SIZE)
	x += PIECE_SIZE + GAP
	draw_string(
		name_font, Vector2(x, middle + 5.0), side_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, AppTheme.TEXT_DIM
	)
	x += name_width + GAP
	draw_string(
		move_font, Vector2(x, middle + 6.0), notation,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, AppTheme.ACCENT
	)
