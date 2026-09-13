class_name SwitchRow
extends Button

## Uma linha de ajuste com nome à esquerda e um interruptor à direita.
##
## Existe porque os dois ajustes de som eram chips lado a lado, e um chip não tem
## como dizer que está **desligado**: o app inteiro usa contorno latão para "esta
## é a opção marcada", então o som desligado e o som ligado só se distinguiam
## comparando um com o outro. Quem abrisse os ajustes com os dois no mesmo estado
## não tinha do que comparar.
##
## O interruptor resolve porque ele não é uma escolha entre irmãos — é uma coisa
## que está de um jeito ou do outro, e a posição do botão diz qual sem cor
## nenhuma. Quem não distingue o latão do cinza ainda vê a bolinha à direita.
##
## Continua sendo um `Button` inteiro: o alvo do toque é a linha, e não a bolinha
## de 20 px no canto.

signal switched(value: bool)

const HEIGHT := 56.0
const TRACK := Vector2(46.0, 26.0)
const KNOB := 9.0
const PAD := 16.0
## Quanto o botão leva para atravessar o trilho. Curto: é a confirmação do toque,
## e uma animação de ajuste que se faz esperar é um ajuste que parece travado.
const SLIDE := 0.12

var value := false:
	set(new_value):
		if value == new_value:
			return
		value = new_value
		_animate()

## Posição desenhada do botão, de 0 (desligado) a 1. Separada de `value` porque é
## ela que a animação move — o valor pula, o desenho desliza.
var _knob := 0.0:
	set(position_value):
		_knob = position_value
		queue_redraw()


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = &"NavItem"
	add_theme_color_override("font_color", AppTheme.TEXT)
	add_theme_color_override("font_hover_color", AppTheme.TEXT)
	pressed.connect(func() -> void:
		value = not value
		switched.emit(value)
	)


## Estado inicial sem animação: a tela abre com o interruptor já onde ele está, e
## não com os dois deslizando na primeira aparição.
func setup(label: String, start: bool) -> void:
	text = label
	value = start
	_knob = 1.0 if start else 0.0


func _animate() -> void:
	create_tween().tween_property(self, "_knob", 1.0 if value else 0.0, SLIDE)


func _draw() -> void:
	var track_position := Vector2(size.x - PAD - TRACK.x, (size.y - TRACK.y) * 0.5)
	var rect := Rect2(track_position, TRACK)
	var off := AppTheme.SURFACE_HIGH
	var on := AppTheme.ACCENT_SOFT
	draw_rect_rounded(rect, off.lerp(on, _knob))
	draw_rect_rounded_outline(rect, AppTheme.BORDER.lerp(AppTheme.ACCENT, _knob))

	var travel := TRACK.x - TRACK.y
	var center := rect.position + Vector2(TRACK.y * 0.5 + travel * _knob, TRACK.y * 0.5)
	draw_circle(center, KNOB, AppTheme.TEXT_DIM.lerp(AppTheme.ACCENT, _knob))


func draw_rect_rounded(rect: Rect2, fill: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(rect.size.y * 0.5))
	draw_style_box(style, rect)


func draw_rect_rounded_outline(rect: Rect2, tint: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(int(rect.size.y * 0.5))
	style.set_border_width_all(1)
	style.border_color = tint
	draw_style_box(style, rect)
