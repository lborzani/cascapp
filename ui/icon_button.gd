class_name IconButton
extends Button

## Botão redondo com o ícone desenhado em traço, e não escrito em texto.
##
## Era `text = "⚙"`. Funciona no Windows, onde o Segoe tem o glifo, e é uma aposta
## no Android, onde a fonte do sistema decide se aquele ponto de código existe —
## e quando não existe, o botão da tela inicial vira um retângulo vazio sem que
## nada tenha falhado. Um traço desenhado sai igual em todo aparelho.
##
## Três formas, que é o que o app fora da partida precisa: a gaveta, os ajustes e
## a volta. Acrescentar uma quarta é acrescentar um `match` aqui.
##
## Herda `Button` e não `Control`: o estado de toque, o foco e o `pressed` já são
## dele, e o desenho por cima é só `_draw`.

enum Kind { MENU, GEAR, BACK, CLOSE }

const SIZE := 44.0
## Metade do traço some quando a linha é fina demais num aparelho denso; 2 px é o
## mínimo que continua sendo um traço depois da escala.
const STROKE := 2.0

var kind := Kind.BACK:
	set(value):
		kind = value
		queue_redraw()

## Cor do traço. Segue a cor de texto da variação, e não uma cor própria: um
## ícone que não acompanha o botão em que mora é um ícone que destoa no dia em
## que a variação mudar.
var tint := AppTheme.TEXT_DIM:
	set(value):
		tint = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	theme_type_variation = &"IconButton"
	focus_mode = Control.FOCUS_NONE
	# Quadrado, e não esticado pela caixa que o hospeda. Numa `HBoxContainer` o
	# padrão é preencher a altura toda: dentro da barra de 64 px ele virava uma
	# cápsula de 44x64 com um ícone no meio, que é um botão redondo que deixou de
	# ser redondo por causa de onde foi posto.
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


## O fundo é desenhado aqui, e não por um `StyleBoxFlat` do tema.
##
## Um retângulo arredondado com raio igual à metade da largura tem as duas curvas
## se encontrando no meio, e o `StyleBoxFlat` deixa uma costura visível na
## emenda — uma linha vertical atravessando o botão, que só aparecia no estado
## pressionado, que é o estado que ninguém fotografa.
##
## `draw_circle` não tem emenda porque não tem quatro cantos: é um círculo, que é
## o que este botão sempre quis ser.
func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	match get_draw_mode():
		DRAW_PRESSED:
			draw_circle(center, radius, AppTheme.ACCENT_SOFT)
			draw_arc(center, radius - 0.5, 0.0, TAU, 48, AppTheme.ACCENT, 1.0, true)
		DRAW_HOVER:
			draw_circle(center, radius, AppTheme.SURFACE_HIGH)
			draw_arc(center, radius - 0.5, 0.0, TAU, 48, AppTheme.BORDER, 1.0, true)
		_:
			draw_arc(center, radius - 0.5, 0.0, TAU, 48, AppTheme.BORDER, 1.0, true)
	match kind:
		Kind.MENU:
			_draw_menu(center)
		Kind.GEAR:
			_draw_gear(center)
		Kind.BACK:
			_draw_chevron(center, -1.0)
		Kind.CLOSE:
			_draw_close(center)


## Três traços, com o do meio do mesmo tamanho: a gaveta tem três itens iguais, e
## um hambúrguer com a linha do meio curta é um enfeite que promete uma hierarquia
## que não existe.
func _draw_menu(center: Vector2) -> void:
	var half := 9.0
	for step in 3:
		var y := center.y + (float(step) - 1.0) * 6.0
		draw_line(Vector2(center.x - half, y), Vector2(center.x + half, y), tint, STROKE, true)


## Uma roda: círculo vazado e oito dentes curtos em volta. Oito porque com menos
## ela lê como sol e com mais vira um borrão nos 44 px em que é desenhada.
func _draw_gear(center: Vector2) -> void:
	draw_arc(center, 5.0, 0.0, TAU, 24, tint, STROKE, true)
	for step in 8:
		var angle := TAU * float(step) / 8.0
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(center + dir * 7.0, center + dir * 10.0, tint, STROKE, true)


func _draw_chevron(center: Vector2, direction: float) -> void:
	var reach := 5.0
	draw_polyline(
		PackedVector2Array([
			center + Vector2(-direction * reach, -reach * 1.4),
			center + Vector2(direction * reach, 0.0),
			center + Vector2(-direction * reach, reach * 1.4),
		]),
		tint, STROKE, true
	)


func _draw_close(center: Vector2) -> void:
	var reach := 7.0
	draw_line(center - Vector2(reach, reach), center + Vector2(reach, reach), tint, STROKE, true)
	draw_line(center + Vector2(reach, -reach), center + Vector2(-reach, reach), tint, STROKE, true)
