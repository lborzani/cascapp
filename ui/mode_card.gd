class_name ModeCard
extends Button

## Um modo de jogo na folha: o selo, o nome, uma linha que explica e a bolinha de
## escolha.
##
## Eram três segmentos numa faixa — "Online · Aqui · Contra bot" —, e "Aqui" não
## dizia "no mesmo aparelho" a ninguém. Um cartão por modo tem espaço para dizer
## o que o modo é, e o alvo do toque passa de um terço da largura para a tela
## inteira.
##
## O cartão não sabe que modos existem: quem monta a folha diz o selo, a cor e os
## textos. Marcado, ganha o contorno limão e a bolinha cheia — o limão aqui é
## "é este que vai valer quando você apertar o botão lá embaixo".

const HEIGHT := 60.0
const PAD := 12.0
const BADGE := 40.0
const DOT := 20.0

var badge := "":
	set(value):
		badge = value
		queue_redraw()
var badge_color := AppTheme.SURFACE_TOP:
	set(value):
		badge_color = value
		queue_redraw()
var title := "":
	set(value):
		title = value
		queue_redraw()
var detail := "":
	set(value):
		detail = value
		queue_redraw()
var chosen := false:
	set(value):
		chosen = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	focus_mode = Control.FOCUS_NONE
	# Sem caixa do tema: o cartão desenha a própria.
	theme_type_variation = &"IconButton"


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	draw_style_box(AppTheme.box(
		AppTheme.SURFACE.lerp(AppTheme.ACCENT, 0.1) if chosen else AppTheme.SURFACE,
		AppTheme.RADIUS_LARGE, AppTheme.ACCENT if chosen else AppTheme.SURFACE_TOP, 2
	), box)

	var mark := Rect2(PAD, (size.y - BADGE) * 0.5, BADGE, BADGE)
	draw_style_box(AppTheme.box(badge_color, AppTheme.RADIUS), mark)
	draw_string(
		AppTheme.display(700), Vector2(mark.position.x, mark.get_center().y + 5.0), badge,
		HORIZONTAL_ALIGNMENT_CENTER, BADGE, 14, AppTheme.ACCENT_INK
	)

	var text_x := mark.end.x + PAD
	var text_width := size.x - text_x - DOT - PAD * 2.0
	draw_string(
		AppTheme.display(600), Vector2(text_x, size.y * 0.5 - 2.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, text_width, 17, AppTheme.TEXT
	)
	draw_string(
		AppTheme.font(500), Vector2(text_x, size.y * 0.5 + 16.0), detail,
		HORIZONTAL_ALIGNMENT_LEFT, text_width, 13, AppTheme.TEXT_DIM
	)

	var dot := Vector2(size.x - PAD - DOT * 0.5, size.y * 0.5)
	if chosen:
		draw_circle(dot, DOT * 0.5, AppTheme.ACCENT)
	else:
		draw_arc(dot, DOT * 0.5 - 1.0, 0.0, TAU, 32, AppTheme.SURFACE_TOP, 2.0, true)
