class_name BombButton
extends Control

## O botão de largar bomba, desenhado — e não um emoji num `Button`.
##
## O emoji era o caminho barato e cobrava duas coisas. A primeira é que ele é a
## fonte do **sistema**: o mesmo botão sai roxo num aparelho, azul noutro e como
## um quadrado vazio num terceiro, e nenhum deles parece a bomba que está no mapa
## dois centímetros ao lado. A segunda é a moldura retangular de `Button` no canto
## de uma tela onde o outro controle — o direcional — é um círculo desenhado: dois
## vocabulários no mesmo par de polegares.
##
## Aqui a bomba é **a mesma** de [bomber_view.gd]: esfera escura, calota mais
## clara, pavio aceso. O botão passa a mostrar o objeto que ele produz.
##
## ## `button_down`, e não `pressed`
##
## Ele dispara no instante em que o dedo encosta. Num jogo de reação, esperar o
## dedo **sair** para largar a bomba é meio segundo entre querer e acontecer — e
## meio segundo é a diferença entre a bomba pegar alguém e a bomba pegar você.
## Quem consome o pedido é [BomberPad.take_bomb], no tique seguinte.

## O dedo encostou. Ver o cabeçalho.
signal pressed_down

const BODY := Color("1b1a1e")
const BODY_LIGHT := Color("35333a")
const FLAME_CORE := Color("ffe7a8")
const FLAME_EDGE := Color("e8763a")
## Quanto tempo o botão fica aceso depois do toque. Curto: é um recibo do toque,
## não um estado.
const FLASH_SECONDS := 0.18

var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


func _gui_input(event: InputEvent) -> void:
	if not Tap.began(event):
		# O soltar também é aceito, senão o `Control` deixa o evento seguir e o nó de
		# baixo recebe metade de um gesto.
		if Tap.ended(event):
			accept_event()
		return
	accept_event()
	pressed_down.emit()
	_flash = FLASH_SECONDS
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if _flash <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	var lit := _flash / FLASH_SECONDS

	# O prato amarelo: é a ação da tela, e a ação da tela no tema é a placa
	# amarela. O aro mais escuro é a borda da placa; no toque, o fogo acende o
	# aro inteiro.
	draw_circle(center, radius, AppTheme.ACCENT)
	draw_circle(center - Vector2(0.0, radius * 0.06), radius * 0.92, AppTheme.ACCENT.lightened(0.06))
	draw_arc(
		center, radius - 1.5, 0.0, TAU, 64,
		AppTheme.ACCENT_EDGE.lerp(FLAME_EDGE, lit), 3.0, true
	)

	# A bomba, encolhendo um fio no toque: é o afundar do botão sem mover o alvo
	# de lugar, que é o que um botão que cresce e encolhe faz com o dedo.
	var bomb := radius * (0.56 - 0.04 * lit)
	var seat := center + Vector2(0.0, radius * 0.06)
	# Escura de novo sobre o amarelo: sobre o prato escuro de antes, a esfera
	# escura sumia e precisava ser clara; sobre a placa, é a escura que se lê.
	draw_circle(seat, bomb, BODY)
	draw_circle(seat - Vector2(bomb * 0.20, bomb * 0.18), bomb * 0.55, BODY_LIGHT)
	draw_arc(seat, bomb, 0.0, TAU, 48, AppTheme.ACCENT_INK, maxf(1.5, radius * 0.035), true)

	# O pavio: um toco de corda e a fagulha. A fagulha é o único ponto quente do
	# canto inteiro da tela, e é o que faz o botão ser encontrado sem ser lido.
	var wick := seat + Vector2(-bomb * 0.42, -bomb * 0.88)
	draw_line(wick, wick + Vector2(bomb * 0.10, -bomb * 0.34), BODY_LIGHT.lightened(0.15), maxf(2.0, radius * 0.06))
	var spark := wick + Vector2(bomb * 0.12, -bomb * 0.40)
	draw_circle(spark, radius * (0.10 + 0.05 * lit), FLAME_EDGE)
	draw_circle(spark, radius * (0.05 + 0.03 * lit), FLAME_CORE)
