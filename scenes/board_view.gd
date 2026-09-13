class_name BoardView
extends GridView

## Renders a position and turns taps into square indices. It knows nothing about
## the rules; the match scene feeds it the squares to highlight.
##
## A grade em si — moldura, coordenadas, geometria da casa e o gesto de toque e
## arrasto — mora no `GridView`, junto com a batalha naval. Aqui fica só o que
## sabe que existem peças: o desenho delas, os destaques do lance e a animação.

const CHECK_PERIOD := 1.1
## Duração por trecho do lance. Numa sequência de capturas nas damas o tempo
## soma, então um salto triplo demora o triplo — que é o certo: cada salto
## precisa ser visto.
const MOVE_STEP := 0.17
## Altura do pulo em capturas, em frações de casa.
const HOP := 0.22
const TARGET_GROW := 0.16

var ruleset: Ruleset = null
var state: MatchState = null

var selection := PackedInt32Array()
var targets := PackedInt32Array()
var capture_targets := PackedInt32Array()
var last_move := PackedInt32Array()
var doomed := PackedInt32Array()
var preview_from := Board.NO_SQUARE
var preview_to := Board.NO_SQUARE

## Lance planejado para a vez seguinte (`[origem, destino]`), e a peça erguida
## enquanto ele é montado. Só marcação: a peça continua onde está, porque o
## tabuleiro ainda é do oponente.
var premove := PackedInt32Array()
var premove_pick := Board.NO_SQUARE

var check_square := Board.NO_SQUARE:
	set(value):
		check_square = value
		_update_processing()
		queue_redraw()

var _pulse := 0.0

var _move_path := PackedInt32Array()
var _move_taken: Array = []
var _move_time := 0.0
var _move_duration := 0.0
var _target_time := 1.0
var _drawn_targets := PackedInt32Array()
var _drawn_captures := PackedInt32Array()


func _ready() -> void:
	set_process(false)


## Anima o lance recém-aplicado. O estado já mudou quando isto é chamado, então
## a peça é desenhada fora do lugar de propósito até a animação alcançá-la, e as
## capturadas — que já não existem no estado — vêm no `taken` para poderem sumir
## em vez de desaparecer de um quadro para o outro.
##
## Vale principalmente pelo lance do oponente: sem isto, ele chega teleportado e
## o jogador não vê o que foi jogado.
func play_move(path: PackedInt32Array, taken: Array) -> void:
	if path.size() < 2:
		return
	_move_path = path.duplicate()
	_move_taken = taken
	_move_duration = MOVE_STEP * (path.size() - 1)
	_move_time = 0.0
	_update_processing()
	queue_redraw()


func remaining_animation() -> float:
	return maxf(0.0, _move_duration - _move_time)


func cancel_animation() -> void:
	_move_path = PackedInt32Array()
	_move_taken = []
	_move_time = 0.0
	_move_duration = 0.0
	_update_processing()


func _process(delta: float) -> void:
	if check_square != Board.NO_SQUARE:
		_pulse = fmod(_pulse + delta, CHECK_PERIOD)
	if _move_duration > 0.0:
		_move_time += delta
		if _move_time >= _move_duration:
			cancel_animation()
	if _target_time < TARGET_GROW:
		_target_time += delta
	_update_processing()
	queue_redraw()


func _update_processing() -> void:
	set_process(
		check_square != Board.NO_SQUARE or _move_duration > 0.0 or _target_time < TARGET_GROW
	)


func refresh() -> void:
	if targets != _drawn_targets or capture_targets != _drawn_captures:
		_drawn_targets = targets.duplicate()
		_drawn_captures = capture_targets.duplicate()
		_target_time = 0.0
	_update_processing()
	queue_redraw()


## Vira arrasto só o toque que pegou uma peça. Quem decide isso é a cena, e a
## decisão já chegou quando esta pergunta é feita: `square_tapped` é síncrono, e
## o que a cena marcou está em `selection` — ou em `premove_pick`, quando o plano
## é para a vez seguinte.
func _can_drag(square: int) -> bool:
	var picked := not selection.is_empty() and selection[selection.size() - 1] == square
	return picked or square == premove_pick


func _draw() -> void:
	layout()
	draw_frame()

	for square in Board.SQUARE_COUNT:
		var rect := rect_of(square)
		var dark := (Board.file_of(square) + Board.rank_of(square)) % 2 == 0
		var color := AppTheme.BOARD_DARK if dark else AppTheme.BOARD_LIGHT
		# Nas damas metade do tabuleiro nunca é usada. Puxar essas casas para a
		# cor da moldura, em vez de só escurecê-las, faz elas lerem como "fora do
		# jogo"; escurecer a madeira apenas cria uma terceira cor competindo.
		if ruleset != null and not ruleset.square_is_playable(square):
			color = color.lerp(AppTheme.BOARD_FRAME, 0.62)
		draw_rect(rect, color)

	_draw_last_move()
	_draw_premove()
	_draw_check()
	_draw_selection()
	draw_coordinates()

	if state == null:
		return
	var travelling := _move_duration > 0.0
	var arriving := _move_path[_move_path.size() - 1] if travelling else Board.NO_SQUARE
	# A peça no dedo é desenhada por último, sobre tudo. Aqui ela só sai da casa
	# em que estava, senão apareceria duas vezes.
	var dragged := _drag_square if dragging else Board.NO_SQUARE
	for square in Board.SQUARE_COUNT:
		if square == preview_from or square == arriving or square == dragged:
			continue
		var rect := rect_of(square)
		var piece := state.squares[square]
		PieceRenderer.draw_piece(self, piece, rect.get_center(), _cell, 1.0, 1.0, _turned(piece))
		if doomed.has(square):
			_draw_cross(rect)
	if preview_from != Board.NO_SQUARE and preview_to != Board.NO_SQUARE and preview_to != dragged:
		var previewed := state.squares[preview_from]
		PieceRenderer.draw_piece(
			self, previewed, rect_of(preview_to).get_center(), _cell, 1.0, 1.0, _turned(previewed)
		)

	_draw_targets()
	if travelling:
		_draw_travelling(arriving)
	_draw_drag()


## Verdadeiro para a peça que pertence a quem está do outro lado do aparelho.
## Fora do modo mesa nunca gira nada, e a de baixo do tabuleiro é sempre a que
## fica em pé. `flipped` acompanha o lado que se joga (em rede as pretas veem o
## tabuleiro do lado delas), e a regra segue a orientação, não a cor.
func _turned(piece: int) -> bool:
	if not table_mode or piece == 0:
		return false
	var upright := Board.Side.BLACK if flipped else Board.Side.WHITE
	return Board.side_of(piece) != upright


func _draw_travelling(arriving: int) -> void:
	var progress := clampf(_move_time / _move_duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 3.0)

	# As capturadas somem antes do fim, para a peça chegar num tabuleiro limpo.
	var fade := clampf(1.0 - progress * 1.7, 0.0, 1.0)
	for entry in _move_taken:
		PieceRenderer.draw_piece(
			self, entry[1], rect_of(entry[0]).get_center(), _cell, fade, 0.7 + 0.3 * fade,
			_turned(entry[1])
		)

	var segments := _move_path.size() - 1
	var travelled := eased * segments
	var index := mini(int(travelled), segments - 1)
	var local := travelled - index
	var from := rect_of(_move_path[index]).get_center()
	var to := rect_of(_move_path[index + 1]).get_center()
	var position := from.lerp(to, local)
	if not _move_taken.is_empty():
		position.y -= sin(PI * local) * _cell * HOP
	# Um leve aumento enquanto viaja sugere a peça erguida do tabuleiro.
	var moving := state.squares[arriving]
	PieceRenderer.draw_piece(
		self, moving, position, _cell, 1.0, 1.0 + 0.08 * sin(PI * progress), _turned(moving)
	)


## O último lance: de onde a peça saiu e onde ela está, nas duas casas, na mesma
## cor. Nas damas todas as casas do salto entram, que é o lance de verdade.
##
## Verde, e antes era o latão da própria interface. Duas razões para trocar. A
## primeira é que o latão quer dizer "é aqui que você age": no destaque de um
## lance que já aconteceu ele convidava a agir sobre o passado. A segunda é que
## ele ficava a um passo da madeira clara do tabuleiro, e um destaque que só
## aparece quando você procura não está destacando nada.
##
## A mesma cor nas duas casas de propósito. Diferenciá-las seria responder uma
## pergunta que o tabuleiro já responde melhor: a casa com a peça é onde ela
## está, a vazia é de onde ela veio.
func _draw_last_move() -> void:
	for square in last_move:
		draw_rect(rect_of(square), Color(AppTheme.LAST_MOVE, 0.38))


## O rei em xeque pulsa em vez de ficar com um fundo vermelho fixo. Movimento é
## o único canal que o olho não ignora quando o tabuleiro já está cheio de cor.
func _draw_check() -> void:
	if check_square == Board.NO_SQUARE:
		return
	var phase := sin(_pulse / CHECK_PERIOD * TAU) * 0.5 + 0.5
	var rect := rect_of(check_square)
	draw_rect(rect, Color(AppTheme.DANGER, 0.28 + 0.22 * phase))
	draw_circle(rect.get_center(), _cell * (0.46 + 0.05 * phase), Color(AppTheme.DANGER, 0.16))


func _draw_selection() -> void:
	for square in selection:
		var rect := rect_of(square)
		draw_rect(rect, Color(AppTheme.ACCENT, 0.30))
		draw_rect(rect.grow(-2.0), Color(AppTheme.ACCENT, 0.85), false, maxf(2.0, _cell * 0.05))


## Destinos vazios ganham um ponto; capturas ganham um anel em volta da peça,
## para a diferença entre "ando aqui" e "como isto" não depender de cor.
func _draw_targets() -> void:
	# Os indicadores crescem ao aparecer: a diferença entre "surgiu" e "sempre
	# esteve" é o que confirma que o toque foi registrado.
	var grow := clampf(_target_time / TARGET_GROW, 0.0, 1.0)
	var scale := 1.0 - pow(1.0 - grow, 2.0)
	if scale <= 0.01:
		return
	for square in targets:
		var center := rect_of(square).get_center()
		draw_circle(center, _cell * 0.17 * scale, Color(AppTheme.ACCENT, 0.30))
		draw_circle(center, _cell * 0.11 * scale, Color(AppTheme.ACCENT, 0.85))
	for square in capture_targets:
		var center := rect_of(square).get_center()
		draw_arc(
			center, _cell * 0.42 * scale, 0.0, TAU, 48, Color(AppTheme.DANGER, 0.9), _cell * 0.08
		)


## O lance planejado, marcado nas duas casas. A peça fica onde está: mostrá-la
## já no destino seria desenhar uma posição que ainda não existe — e que pode
## nunca existir, porque o lance do oponente ainda pode torná-la impossível.
func _draw_premove() -> void:
	for square in premove:
		var rect := rect_of(square)
		draw_rect(rect, Color(AppTheme.PREMOVE, 0.28))
		draw_rect(rect.grow(-2.0), Color(AppTheme.PREMOVE, 0.75), false, maxf(2.0, _cell * 0.045))
	if premove_pick != Board.NO_SQUARE:
		draw_rect(rect_of(premove_pick), Color(AppTheme.PREMOVE, 0.32))


## A peça sob o dedo, um pouco maior, e a casa em que ela vai cair contornada.
## O contorno não é enfeite: no celular o dedo cobre exatamente essa casa, e sem
## ele o jogador solta a peça às cegas.
func _draw_drag() -> void:
	var piece := _dragged_piece()
	if piece == 0:
		return
	var over := square_at(_drag_at)
	if over != Board.NO_SQUARE and over != _drag_square:
		draw_rect(rect_of(over).grow(-2.0), Color(AppTheme.TEXT, 0.75), false, maxf(2.0, _cell * 0.05))
	PieceRenderer.draw_piece(self, piece, _drag_at, _cell, 1.0, 1.16, _turned(piece))


func _dragged_piece() -> int:
	if not dragging or state == null or _drag_square == Board.NO_SQUARE:
		return 0
	# Numa sequência de capturas a peça já não está na casa de origem: ela é
	# desenhada onde a sequência parou, e é de lá que o dedo a pega.
	if _drag_square == preview_to and preview_from != Board.NO_SQUARE:
		return state.squares[preview_from]
	return state.squares[_drag_square]


func _draw_cross(rect: Rect2) -> void:
	var inset := rect.grow(-_cell * 0.28)
	var width := _cell * 0.09
	draw_line(inset.position, inset.position + inset.size, AppTheme.DANGER, width)
	draw_line(
		inset.position + Vector2(inset.size.x, 0),
		inset.position + Vector2(0, inset.size.y),
		AppTheme.DANGER,
		width
	)
