class_name GridView
extends Control

## Grade 8x8 desenhada e tocada: moldura, coordenadas, geometria da casa e o
## gesto que transforma dedo em índice de casa. Não sabe o que mora nas casas.
##
## Existe porque `BoardView` (xadrez e damas) e `WatersView` (batalha naval)
## precisam exatamente da mesma grade e do mesmo gesto, e **o gesto não é código
## que se copia**. A trava de origem do ponteiro resolve um comportamento
## específico do Android — o sistema entrega o toque e ainda a emulação de mouse
## do mesmo dedo por cima — e uma segunda cópia dela é uma cópia que um dia
## recebe a correção que a outra não recebe.
##
## A subclasse desenha o conteúdo no `_draw` dela e chama `layout()`,
## `draw_frame()` e `draw_coordinates()` na ordem que quiser. O que ela precisa
## responder é `_can_drag()`: quais casas o dedo pode arrastar é a única parte do
## gesto que depende do jogo.

signal square_tapped(square: int)

## Espessura da moldura, em frações de casa.
const FRAME := 0.34
## Distância que o dedo precisa andar para o toque virar arrasto, em frações de
## casa. Existe porque dedo nenhum fica parado: sem limiar, todo toque simples
## viraria um arrasto de dois pixels.
const DRAG_THRESHOLD := 0.22

enum Phase { PRESS, MOVE, RELEASE }

var flipped := false

## Modo mesa: com o aparelho deitado entre os dois jogadores, metade da mesa lê
## tudo invertido. Mora aqui porque quem reage a ele são as coordenadas, que são
## da grade. O que a subclasse faz com a informação — girar peça, por exemplo —
## é decisão dela.
var table_mode := false

## Arrasto em curso: o conteúdo acompanha o dedo em vez de esperar um segundo
## toque.
var dragging := false

var _cell := 0.0
var _origin := Vector2.ZERO
var _frame_cache: StyleBoxFlat = null
var _frame_cell := -1.0

## De onde veio o gesto em curso: "touch" ou "mouse". Sem esta trava o mesmo
## arrasto soltaria o lance duas vezes no Android.
var _pointer := ""
var _press_at := Vector2.ZERO
var _drag_square := Board.NO_SQUARE
var _drag_at := Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## A casa tocada pode ser arrastada? Chamado logo depois de `square_tapped`, com
## a resposta da cena já aplicada — o sinal é síncrono.
func _can_drag(_square: int) -> bool:
	return false


# --- gesto -------------------------------------------------------------------


## Classifica o evento em `[origem, fase, posição]`, ou vazio quando não
## interessa. Toque e mouse chegam por classes diferentes com a mesma intenção, e
## o resto do arrasto não precisa saber qual das duas foi.
func _classify(event: InputEvent) -> Array:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		return ["touch", Phase.PRESS if touch.pressed else Phase.RELEASE, touch.position]
	if event is InputEventScreenDrag:
		return ["touch", Phase.MOVE, (event as InputEventScreenDrag).position]
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index != MOUSE_BUTTON_LEFT:
			return []
		return ["mouse", Phase.PRESS if click.pressed else Phase.RELEASE, click.position]
	if event is InputEventMouseMotion:
		return ["mouse", Phase.MOVE, (event as InputEventMouseMotion).position]
	return []


## Só o começo do gesto entra por aqui.
##
## O toque continua valendo sozinho: a casa é emitida na descida, então tocar e
## soltar sem andar é o fluxo simples, intacto. O arrasto é o mesmo gesto
## continuado — solta no destino e emite a segunda casa, que é exatamente o que
## um segundo toque emitiria. Por isso as regras não sabem que ele existe.
func _gui_input(event: InputEvent) -> void:
	if not _pointer.is_empty():
		return
	var parsed := _classify(event)
	if parsed.is_empty() or parsed[1] != Phase.PRESS:
		return
	var position: Vector2 = parsed[2]
	var square := square_at(position)
	if square == Board.NO_SQUARE:
		return
	accept_event()
	_pointer = parsed[0]
	_press_at = position
	_drag_square = Board.NO_SQUARE
	dragging = false
	square_tapped.emit(square)
	if _can_drag(square):
		_drag_square = square


## O resto do gesto. Não vem pelo `_gui_input` porque um arrasto que sai da grade
## deixa de gerar eventos de GUI para este nó: o conteúdo ficaria colado ao
## último ponto visto e o dedo levantado lá fora nunca chegaria aqui.
func _input(event: InputEvent) -> void:
	if _pointer.is_empty():
		return
	var parsed := _classify(make_input_local(event))
	if parsed.is_empty() or parsed[0] != _pointer or parsed[1] == Phase.PRESS:
		return
	get_viewport().set_input_as_handled()
	if parsed[1] == Phase.MOVE:
		_drag_to(parsed[2])
	else:
		_release_at(parsed[2])


func _drag_to(position: Vector2) -> void:
	if _drag_square == Board.NO_SQUARE:
		return
	if not dragging and _press_at.distance_to(position) < _cell * DRAG_THRESHOLD:
		return
	dragging = true
	_drag_at = position
	queue_redraw()


func _release_at(position: Vector2) -> void:
	var was_dragging := dragging
	var origin := _drag_square
	_pointer = ""
	_drag_square = Board.NO_SQUARE
	dragging = false
	queue_redraw()
	if not was_dragging:
		return
	var dropped := square_at(position)
	# Soltar fora da grade, ou de volta na casa de origem, não é lance. A escolha
	# continua de pé e o jogador termina por toque se quiser: desistir de um
	# arrasto não pode custar a seleção.
	if dropped == Board.NO_SQUARE or dropped == origin:
		return
	square_tapped.emit(dropped)


# --- geometria ---------------------------------------------------------------


func layout() -> void:
	# A moldura e as coordenadas moram fora da grade, então o cálculo parte do
	# espaço total menos duas molduras.
	var total_cells := Board.SIZE + FRAME * 2.0
	_cell = minf(size.x, size.y) / total_cells
	var side := _cell * Board.SIZE
	_origin = ((size - Vector2.ONE * side) * 0.5).floor()


func rect_of(square: int) -> Rect2:
	var file := Board.file_of(square)
	var rank := Board.rank_of(square)
	var col := file if not flipped else Board.SIZE - 1 - file
	var row := (Board.SIZE - 1 - rank) if not flipped else rank
	return Rect2(_origin + Vector2(col, row) * _cell, Vector2.ONE * _cell)


func square_at(position: Vector2) -> int:
	layout()
	var local := position - _origin
	var col := floori(local.x / _cell)
	var row := floori(local.y / _cell)
	if col < 0 or col >= Board.SIZE or row < 0 or row >= Board.SIZE:
		return Board.NO_SQUARE
	var file := col if not flipped else Board.SIZE - 1 - col
	var rank := (Board.SIZE - 1 - row) if not flipped else row
	return Board.square(file, rank)


# --- moldura e coordenadas ---------------------------------------------------


func draw_frame() -> void:
	var board := Rect2(_origin, Vector2.ONE * _cell * Board.SIZE)
	draw_style_box(_frame_style(), board.grow(_cell * FRAME))
	# Fio escuro na borda interna: separa a moldura das casas sem pesar.
	draw_rect(board.grow(1.5), Color(0, 0, 0, 0.28), false, 2.0)


## Reconstruído só quando o tamanho da casa muda — o pulso do xeque redesenha a
## cada frame e não vale alocar um StyleBox por frame.
func _frame_style() -> StyleBoxFlat:
	if _frame_cache != null and is_equal_approx(_frame_cell, _cell):
		return _frame_cache
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.BOARD_FRAME
	style.set_corner_radius_all(int(_cell * 0.20))
	style.set_border_width_all(1)
	style.border_color = Color(AppTheme.TEXT, 0.10)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = int(_cell * 0.20)
	style.shadow_offset = Vector2(0, _cell * 0.07)
	_frame_cache = style
	_frame_cell = _cell
	return style


## Coordenadas na moldura. Elas seguem o giro da grade, senão viram uma segunda
## fonte de verdade contradizendo o que está desenhado.
##
## No modo mesa saem **duas vezes**: embaixo e à esquerda para quem está deste
## lado, em cima e à direita — de ponta-cabeça — para quem está do outro. Uma
## coordenada só serve para quem consegue lê-la.
func draw_coordinates() -> void:
	var font := get_theme_default_font()
	var text_size := int(maxf(10.0, _cell * 0.24))
	var inset := _cell * FRAME
	var color := Color(AppTheme.TEXT, 0.55)
	var board_side := Board.SIZE * _cell

	for i in Board.SIZE:
		var file_index := i if not flipped else Board.SIZE - 1 - i
		var rank_index := Board.SIZE - 1 - i if not flipped else i
		var file_name := char("a".unicode_at(0) + file_index)
		var rank_name := str(rank_index + 1)

		var x := _origin.x + (i + 0.5) * _cell
		var y := _origin.y + board_side + inset * 0.5 + text_size * 0.35
		draw_string(
			font, Vector2(x - text_size * 0.3, y), file_name, HORIZONTAL_ALIGNMENT_LEFT, -1,
			text_size, color
		)

		var ry := _origin.y + (i + 0.5) * _cell + text_size * 0.35
		draw_string(
			font, Vector2(_origin.x - inset * 0.5 - text_size * 0.3, ry), rank_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color
		)

		if not table_mode:
			continue

		# Meia volta em torno do centro da grade: a letra fica na borda oposta e
		# legível de lá, e a conta é a mesma para linha e coluna.
		var centre := _origin + Vector2.ONE * board_side * 0.5
		draw_set_transform(centre, PI, Vector2.ONE)
		draw_string(
			font, Vector2(x - text_size * 0.3, y) - centre, file_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color
		)
		draw_string(
			font, Vector2(_origin.x - inset * 0.5 - text_size * 0.3, ry) - centre, rank_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
