class_name UnoHand
extends Control

## A mão do jogador, aberta em leque.
##
## É a única parte da tela em que se toca durante a maior parte da partida, e por
## isso é a que decide se o jogo é jogável num celular.
##
## ## O leque, e por que ele não é uma fila
##
## Uma mão de Uno passa de vinte cartas com facilidade. Em fila, vinte cartas numa
## tela de 432 px dão 21 px cada — menos que a largura de um dedo, e sem nenhuma
## das duas leituras que a carta oferece (a cor e o canto). Em leque elas se
## cobrem, e o que sobra visível de cada uma é justamente a faixa da esquerda,
## que é onde o canto pequeno mora.
##
## O passo encolhe conforme a mão cresce, então uma mão de sete abre folgada e uma
## de vinte fica apertada — mas **a última carta nunca sai da tela**, que é o que
## uma fila rolável não garante sem um gesto a mais.
##
## ## O que pode ser jogado se vê antes de se tocar
##
## As jogáveis sobem alguns pixels e ficam opacas; as outras ficam apagadas e no
## lugar. Duas pistas para a mesma informação, e as duas contínuas: nada pisca,
## nada aparece só depois do toque.
##
## Apagadas e **não** escondidas: a mão inteira é o que o jogador usa para decidir
## se vale comprar, e sumir com as injogáveis esconde metade da conta.
##
## ## O toque vai para a carta de cima
##
## Elas se cobrem, então o mesmo ponto pertence a várias. A busca vai do topo para
## baixo — a mesma ordem em que foram desenhadas, invertida —, que é a única que
## concorda com o que o olho vê.

## Uma carta jogável foi tocada. As injogáveis não emitem nada: recusar em
## silêncio um toque que a tela já mostrou como impossível é melhor que uma
## mensagem dizendo o que a carta apagada já dizia.
signal card_tapped(card: int)

## Quanto a carta jogável sobe.
const LIFT := 0.09
## Passo máximo entre cartas, em larguras de carta. Menos que 1 sempre: elas
## **precisam** se cobrir, senão o leque vira fila e a mão grande estoura a tela.
const MAX_STEP := 0.72
## Inclinação total do leque, em radianos, distribuída entre as cartas.
##
## Pequena de propósito. Começou em 0.30 e a mão ficava com as pontas deitadas o
## bastante para o canto pequeno delas apontar para fora da tela — e o canto é a
## única coisa que se lê de uma carta coberta.
const SPREAD := 0.14

var cards := PackedInt32Array():
	set(value):
		cards = value
		queue_redraw()

## Cartas que a regra aceita agora, por código. Uma carta repetida na mão aparece
## uma vez aqui e as duas cópias acendem, que é o certo — elas são a mesma carta.
var playable := PackedInt32Array():
	set(value):
		playable = value
		queue_redraw()

## A mão aceita toque. Falso na vez dos outros e enquanto uma animação corre.
var enabled := false:
	set(value):
		if enabled == value:
			return
		enabled = value
		queue_redraw()

## Centro e ângulo de cada carta, preenchidos no desenho e lidos pelo toque.
##
## Guardados porque as duas contas têm de ser a mesma. Recalcular no `_gui_input`
## é como o toque acaba caindo na carta ao lado numa mão grande, onde o passo
## depende da contagem.
var _spots: Array[Transform2D] = []
var _card_height := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	_layout()
	for index in cards.size():
		var card := cards[index]
		var spot := _spots[index]
		UnoCardArt.draw_card(
			self, card, spot.origin, _card_height, spot.get_rotation(),
			not _is_playable(card) or not enabled
		)


func _layout() -> void:
	_spots.clear()
	_card_height = minf(size.y * 0.90, size.x * 0.20 / UnoCardArt.ASPECT)
	var count := cards.size()
	if count == 0:
		return

	var width := UnoCardArt.width_for(_card_height)
	var step := width * MAX_STEP
	if count > 1:
		# O leque inteiro tem de caber na largura, com meia carta de folga de cada
		# lado para a rotação das pontas não sair pela borda.
		var room := size.x - width * 1.2
		step = minf(step, room / float(count - 1))
	var spread := SPREAD if count > 1 else 0.0

	# A linha de base fica embaixo, e a jogável sobe a partir dela. Assim a mão tem
	# **uma** altura de referência e um degrau, em vez de cada carta numa altura
	# diferente.
	#
	# Houve um arco aqui — as pontas descendo, como um leque segurado pelo meio — e
	# ele saiu. Somado à elevação das jogáveis, o resultado era uma serra: cada
	# carta numa altura própria, e nenhuma pista de qual diferença significava o
	# quê. O arco é enfeite; a elevação é informação, e informação ganha.
	var base := size.y * 0.5 + _card_height * LIFT * 0.5
	for index in count:
		var offset := index - (count - 1) * 0.5
		var angle := (offset / maxf(count - 1, 1.0)) * spread
		var lift := -_card_height * LIFT if (enabled and _is_playable(cards[index])) else 0.0
		_spots.append(Transform2D(angle, Vector2(size.x * 0.5 + offset * step, base + lift)))


func _is_playable(card: int) -> bool:
	return playable.has(card)


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return

	var half := Vector2(UnoCardArt.width_for(_card_height), _card_height) * 0.5
	# De cima para baixo: a última desenhada é a que está por cima, e é ela que o
	# dedo acha que tocou.
	for index in range(_spots.size() - 1, -1, -1):
		var local: Vector2 = _spots[index].affine_inverse() * press.position
		if not Rect2(-half, half * 2.0).has_point(local):
			continue
		var card := cards[index]
		if _is_playable(card):
			card_tapped.emit(card)
			accept_event()
		# Para no primeiro acerto mesmo quando a carta não serve. Continuar a busca
		# entregaria o toque a uma carta **de baixo** que por acaso é jogável, e o
		# jogador veria sair da mão uma carta que não é a que ele tocou.
		return
