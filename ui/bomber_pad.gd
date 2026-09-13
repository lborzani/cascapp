class_name BomberPad
extends Control

## O direcional de toque, e o botão de bomba ao lado dele.
##
## ## Por que não são quatro botões
##
## Quatro `Button` num losango funcionam no mouse e falham no polegar: o dedo
## cobre o alvo, escorrega entre dois, e trocar de direção exige soltar e tocar de
## novo. Aqui o toque **fica preso** ao direcional até ser solto, e a direção sai
## de onde o dedo está em relação ao centro. Arrastar o polegar troca de direção
## sem levantar, que é como se joga um jogo de correr.
##
## ## A direção é lida, não avisada
##
## O direcional não emite sinal a cada mudança: ele guarda o que está sendo
## pedido e a partida **pergunta** uma vez por tique, em [method direction]. É a
## forma certa para uma simulação de passo fixo — um sinal por evento de toque
## entregaria três mudanças dentro de um tique e nenhuma no seguinte, e o que a
## simulação precisa saber é o que o dedo estava fazendo naquele instante.
##
## A bomba é o contrário: ela é **travada** no toque e consumida pelo tique
## seguinte ([method take_bomb]). Um toque rápido que começasse e terminasse entre
## dois tiques seria um toque perdido, e perder um pedido de bomba é perder a
## jogada inteira.

## Fração do raio abaixo da qual o dedo conta como "no meio", sem direção. Sem
## essa zona morta, encostar no centro escolhe uma direção ao acaso.
const DEAD_ZONE := 0.28
## Quanto do lado menor do painel o direcional ocupa.
const PAD_SHARE := 0.86

const RING := Color("3a322c")
const RING_LIVE := Color("d9a441")
const ARROW := Color("a2968a")
const ARROW_LIVE := Color("f2eae0")

var _pointer := -1
var _offset := Vector2.ZERO
var _direction := 0
var _bomb_latched := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## Os bits de direção deste instante, no vocabulário de [BomberRules].
func direction() -> int:
	return _direction


## Verdadeiro uma vez por pedido de bomba. Consumir aqui é o que garante que um
## toque curto entre dois tiques não se perde nem vale por dois.
func take_bomb() -> bool:
	var wanted := _bomb_latched
	_bomb_latched = false
	return wanted


## Chamado pela cena quando a partida acaba ou o boneco morre: o dedo pode
## continuar na tela, e sem isto a última direção ficaria pedida para sempre.
func release() -> void:
	_pointer = -1
	_direction = 0
	_offset = Vector2.ZERO
	_bomb_latched = false
	queue_redraw()


func press_bomb() -> void:
	_bomb_latched = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _pointer < 0:
			_pointer = touch.index
			_aim(touch.position)
		elif not touch.pressed and touch.index == _pointer:
			release()
		accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _pointer:
			_aim(drag.position)
			accept_event()
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		if click.pressed:
			_pointer = 0
			_aim(click.position)
		else:
			release()
		accept_event()
	elif event is InputEventMouseMotion and _pointer >= 0:
		_aim((event as InputEventMouseMotion).position)
		accept_event()


## Um eixo por vez, o dominante.
##
## A simulação só anda num eixo por tique — na diagonal o boneco passaria pela
## quina de dois pilares —, então oferecer diagonal no direcional seria prometer
## um movimento que a regra não faz. O eixo dominante é o que o dedo quis.
func _aim(local: Vector2) -> void:
	var center := _pad_center()
	var radius := _pad_radius()
	_offset = (local - center) / maxf(1.0, radius)
	if _offset.length() < DEAD_ZONE:
		_direction = 0
		queue_redraw()
		return
	if absf(_offset.x) >= absf(_offset.y):
		_direction = BomberRules.IN_RIGHT if _offset.x > 0.0 else BomberRules.IN_LEFT
	else:
		_direction = BomberRules.IN_DOWN if _offset.y > 0.0 else BomberRules.IN_UP
	queue_redraw()


func _pad_radius() -> float:
	return minf(size.x, size.y) * PAD_SHARE * 0.5


func _pad_center() -> Vector2:
	return size * 0.5


func _draw() -> void:
	var center := _pad_center()
	var radius := _pad_radius()
	draw_circle(center, radius, Color(RING, 0.35))
	draw_arc(center, radius, 0.0, TAU, 48, RING, 3.0, true)

	for bit: int in [BomberRules.IN_UP, BomberRules.IN_DOWN, BomberRules.IN_LEFT, BomberRules.IN_RIGHT]:
		var step := _step_of(bit)
		var live := (_direction & bit) != 0
		var tip := center + step * radius * 0.78
		var wing := Vector2(step.y, step.x) * radius * 0.22
		draw_colored_polygon(
			PackedVector2Array([tip, tip - step * radius * 0.3 + wing, tip - step * radius * 0.3 - wing]),
			ARROW_LIVE if live else ARROW
		)

	if _direction != 0:
		draw_circle(center + _offset.limit_length(1.0) * radius * 0.5, radius * 0.22, Color(RING_LIVE, 0.5))


static func _step_of(bit: int) -> Vector2:
	match bit:
		BomberRules.IN_UP:
			return Vector2(0, -1)
		BomberRules.IN_DOWN:
			return Vector2(0, 1)
		BomberRules.IN_LEFT:
			return Vector2(-1, 0)
		_:
			return Vector2(1, 0)
