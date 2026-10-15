class_name EvalGraph
extends Control

## A partida inteira num gráfico: a vitória esperada das brancas em cada
## posição, de 0 (pretas ganham) a 100 (brancas ganham). A área clara é a parte
## das brancas, a escura a das pretas — a mesma leitura do tabuleiro.
##
## Tocar ou arrastar leva ao lance: o gráfico é o jeito mais rápido de achar
## onde a partida virou, e só ver a queda sem poder ir até ela seria metade.

signal seek(ply: int)

## Folga nas pontas, para o ponto do primeiro e do último lance não sair cortado.
const PAD := 6.0
const DOT := 4.5

var curve: Array = []:
	set(value):
		curve = value
		queue_redraw()
## Posição mostrada no tabuleiro.
var cursor := 0:
	set(value):
		cursor = value
		queue_redraw()
## Lance → cor do ponto. Só os que merecem atenção: imprecisão para cima.
var dots := {}:
	set(value):
		dots = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(0, 72)
	mouse_filter = MOUSE_FILTER_STOP


func ply_at(x: float) -> int:
	if curve.size() < 2:
		return 0
	return clampi(roundi((x - PAD) / (size.x - PAD * 2.0) * (curve.size() - 1)), 0, curve.size() - 1)


func point(ply: int) -> Vector2:
	var step := (size.x - PAD * 2.0) / maxf(1.0, curve.size() - 1)
	return Vector2(PAD + step * ply, size.y * (1.0 - float(curve[ply]) / 100.0))


func _gui_input(event: InputEvent) -> void:
	# O arrasto vem como `ScreenDrag` nos dois mundos: o projeto emula toque a
	# partir do mouse, e no Android o dedo já é toque. O movimento de mouse
	# emulado a partir do dedo é ignorado para o mesmo gesto não contar duas vezes.
	if Tap.began(event):
		accept_event()
		seek.emit(ply_at(Tap.at(event).x))
	elif event is InputEventScreenDrag:
		accept_event()
		seek.emit(ply_at(event.position.x))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), AppTheme.COASTER)
	if curve.size() < 2:
		return
	var area := PackedVector2Array([Vector2(PAD, size.y)])
	for ply in curve.size():
		area.append(point(ply))
	area.append(Vector2(size.x - PAD, size.y))
	draw_colored_polygon(area, Color(AppTheme.PAPER, 0.85))
	draw_dashed_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), AppTheme.LINE_SOFT, 1.0, 4.0)

	var at := point(clampi(cursor, 0, curve.size() - 1))
	draw_line(Vector2(at.x, 0), Vector2(at.x, size.y), AppTheme.ACCENT, 2.0)
	for ply in dots:
		if ply < curve.size():
			draw_circle(point(ply), DOT, dots[ply])


## Quem está na frente na posição do tabuleiro, numa linha só acima dele.
class Bar extends Control:
	var white := 50.0:
		set(value):
			white = clampf(value, 0.0, 100.0)
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(0, 24)

	func _draw() -> void:
		var split := size.x * white / 100.0
		draw_rect(Rect2(Vector2.ZERO, size), AppTheme.COASTER)
		draw_rect(Rect2(0, 0, split, size.y), AppTheme.PAPER)
		var face := AppTheme.font(700)
		var font_size := AppTheme.SIZE_BODY_S
		var baseline := (size.y + face.get_ascent(font_size) - face.get_descent(font_size)) * 0.5
		# O texto vai do lado de quem lidera, que é o lado com mais espaço.
		if white >= 50.0:
			draw_string(face, Vector2(8, baseline), "Brancas %d%%" % roundi(white),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AppTheme.PAPER_INK)
		else:
			draw_string(face, Vector2(0, baseline), "Pretas %d%%" % roundi(100.0 - white),
				HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, font_size, AppTheme.TEXT)
