class_name MoveStrip
extends Control

## A faixa de lances embaixo do tabuleiro: "1. e4 e5  2. f3 Dh4+", do mais novo à
## direita para trás, até onde couber.
##
## Era uma linha sobre o tabuleiro com a peça e o último lance. A faixa responde
## a mesma pergunta ("o que acabou de acontecer?") e mais uma — "como chegamos
## aqui?" —, no espaço de uma linha. O último lance ganha um fundo: coral quando
## deu xeque, que vem escrito à direita; neutro nos outros.

const HEIGHT := 44.0
const PAD := 14.0
const GAP := 12.0
const FONT_SIZE := 14

## Um lance por meio-lance, na notação do jogo (`Ruleset.notation`).
var moves := PackedStringArray():
	set(value):
		moves = value
		queue_redraw()
## O último lance deu xeque.
var check := false:
	set(value):
		check = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Os pedaços da faixa, do primeiro ao último: o número da volta antes do lance
## das brancas, e cada lance como um pedaço próprio — só o último é destacado.
static func tokens(list: PackedStringArray) -> Array:
	var result := []
	for index in list.size():
		var text := list[index]
		if index % 2 == 0:
			text = "%d. %s" % [index / 2 + 1, text]
		result.append(text)
	return result


func _draw() -> void:
	draw_style_box(AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS), Rect2(Vector2.ZERO, size))
	var face := AppTheme.font(800)
	var right := size.x - PAD
	if check:
		var warning := "Rei em xeque"
		var width := face.get_string_size(warning, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(
			face, Vector2(right - width, size.y * 0.5 + 5.0), warning,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, AppTheme.DANGER
		)
		right -= width + GAP * 2.0
	var parts := tokens(moves)
	if parts.is_empty():
		draw_string(
			face, Vector2(PAD, size.y * 0.5 + 5.0), "Nenhum lance ainda",
			HORIZONTAL_ALIGNMENT_LEFT, right - PAD, FONT_SIZE, AppTheme.TEXT_DIM
		)
		return
	# Do último para trás: o que não cabe à esquerda é o começo da partida, que é o
	# que menos importa agora.
	var x := right
	var placed := []
	for index in range(parts.size() - 1, -1, -1):
		var text: String = parts[index]
		var width := face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var pill := 16.0 if index == parts.size() - 1 else 0.0
		if x - width - pill < PAD:
			break
		x -= width + pill
		placed.push_front([x, text, index == parts.size() - 1, width])
		x -= GAP
	for entry in placed:
		var at: float = entry[0]
		var last: bool = entry[2]
		var ink := AppTheme.TEXT_DIM
		if last:
			var fill := AppTheme.DANGER if check else AppTheme.SURFACE_TOP
			draw_style_box(
				AppTheme.box(fill, 8), Rect2(at, size.y * 0.5 - 13.0, float(entry[3]) + 16.0, 26.0)
			)
			at += 8.0
			ink = AppTheme.ACCENT_INK if check else AppTheme.TEXT
		draw_string(
			face, Vector2(at, size.y * 0.5 + 5.0), entry[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, ink
		)
