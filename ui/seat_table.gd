class_name SeatTable
extends Control

## As cadeiras de uma sala, em volta de uma mesa redonda.
##
## A espera dizia "Aguardando: 2 de 4 jogadores" — um número que responde
## "falta muito?" e não responde "quem já está aqui?". Desenhadas, as cadeiras
## respondem as duas de uma vez, e a mesa fica parecida com a que os jogadores
## vão ver na partida: o seu lugar embaixo, os outros em volta na ordem de jogo.
##
## Quem olha fica **sempre embaixo**. É a mesma regra da mesa do Uno e do Ludo, e
## é o que faz a cadeira de cada um ser achada no mesmo lugar nas duas telas.

const SEAT := 54.0
const LABEL_SIZE := 12
## O raio da órbita das cadeiras, em relação à metade do menor lado.
const ORBIT := 0.72

var capacity := 2
var local_seat := 0
## Assentos ocupados agora, como o relay os conhece.
var present := PackedInt32Array()

var _coasters: Array[Coaster] = []
var _labels: Array[Label] = []


func _init() -> void:
	custom_minimum_size.y = 230.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_place)


## Onde cada cadeira senta: o local embaixo, e o resto no sentido do jogo. Em
## radianos de tela — o eixo y cresce para baixo, então somar ângulo anda no
## sentido horário, que é a ordem em que a vez passa.
static func seat_angle(seat: int, seats: int, local: int) -> float:
	var count := maxi(seats, 1)
	var step := posmod(seat - local, count)
	return fmod(PI * 0.5 + TAU * float(step) / float(count), TAU)


func label_of(seat: int) -> String:
	if seat == local_seat:
		return "Você"
	return "Chegou" if present.has(seat) else "Esperando"


## Refaz as cadeiras. Chamado quando a lotação muda ou quando alguém senta — e não
## a cada quadro: uma bolacha é um nó, e recriar quatro por quadro seria refazer a
## mesa inteira para mudar uma palavra.
func refresh() -> void:
	if _coasters.size() != capacity:
		# `remove_child` antes do `queue_free`: o segundo só apaga no fim do quadro, e
		# até lá a mesa teria as cadeiras velhas em volta das novas.
		for node in _coasters + _labels:
			remove_child(node)
			node.queue_free()
		_coasters.clear()
		_labels.clear()
		for seat in capacity:
			var coaster := Coaster.new()
			coaster.size = Vector2(SEAT, SEAT)
			add_child(coaster)
			_coasters.append(coaster)
			var label := Label.new()
			label.theme_type_variation = &"Caption"
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", LABEL_SIZE)
			add_child(label)
			_labels.append(label)
	for seat in capacity:
		var taken := present.has(seat) or seat == local_seat
		_coasters[seat].player_name = str(seat + 1)
		_coasters[seat].ring = AppTheme.GOLD if taken else Color(AppTheme.LINE_SOFT, 0.8)
		_coasters[seat].turn = seat == local_seat
		_coasters[seat].modulate.a = 1.0 if taken else 0.55
		_labels[seat].text = label_of(seat)
		_labels[seat].modulate.a = 1.0 if taken else 0.6
	_place()
	queue_redraw()


func _place() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 * ORBIT
	for seat in _coasters.size():
		var angle := seat_angle(seat, capacity, local_seat)
		var spot := center + Vector2(cos(angle), sin(angle)) * radius
		_coasters[seat].position = spot - Vector2(SEAT, SEAT) * 0.5
		_labels[seat].size.x = SEAT + 40.0
		_labels[seat].position = Vector2(spot.x - (SEAT + 40.0) * 0.5, spot.y + SEAT * 0.55)


## O tampo: um círculo escuro com o contorno de giz, como a bolacha grande que ele
## é. É o que dá às cadeiras um lugar de onde estar em volta.
func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 * (ORBIT - 0.3)
	if radius <= 0.0:
		return
	draw_circle(center, radius, AppTheme.COASTER)
	draw_arc(center, radius, 0.0, TAU, 48, AppTheme.LINE_SOFT, 1.5, true)
