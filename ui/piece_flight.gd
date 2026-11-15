class_name PieceFlight
extends Control

## Uma peça tomada voando do tabuleiro até a fileira de quem a capturou.
##
## Sem isto a peça some da casa e aparece na etiqueta no mesmo quadro, em dois
## cantos diferentes da tela — e ninguém liga uma coisa à outra. O voo é o que
## diz "foi para lá". Desenho puro: o estado já mudou, e a fileira já mostra a
## peça; o voo só leva o olho até ela.

const TIME := 0.45
## Quanto o arco sobe, em fração da distância.
const ARC := 0.25

var piece := 0
var from := Vector2.ZERO
var to := Vector2.ZERO
var from_size := 40.0
var to_size := 24.0
var _t := 0.0:
	set(value):
		_t = value
		queue_redraw()


## Solta uma peça de `from` a `to` (coordenadas globais) depois de `delay`
## segundos — o tempo de a peça que captura chegar na casa.
static func launch(
	host: Node, piece_code: int, start: Vector2, end: Vector2,
	start_size: float, end_size: float, delay := 0.0
) -> PieceFlight:
	var flight := PieceFlight.new()
	flight.piece = piece_code
	flight.from = start
	flight.to = end
	flight.from_size = start_size
	flight.to_size = end_size
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fora do layout de quem a hospeda, e por cima de tudo: ela atravessa o
	# tabuleiro e a etiqueta, que moram em containers diferentes.
	flight.top_level = true
	flight.z_index = 100
	flight.visible = false
	host.add_child(flight)
	var tween := flight.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void: flight.visible = true)
	tween.tween_property(flight, "_t", 1.0, TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(flight.queue_free)
	return flight


func _draw() -> void:
	var at := from.lerp(to, _t)
	at.y -= sin(_t * PI) * from.distance_to(to) * ARC
	var side := lerpf(from_size, to_size, _t)
	PieceRenderer.draw_piece(self, piece, at - global_position, side, 1.0 - _t * 0.25)
