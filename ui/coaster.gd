class_name Coaster
extends Control

## A bolacha de chopp: o avatar de um jogador no tema Boteco.
##
## Um círculo escuro com a inicial, um anel dourado — ou na cor do assento, dentro
## da partida — e um segundo anel amarelo, por fora, quando é a vez dele. É o mesmo
## objeto na sala de espera, na coluna de jogadores e em volta da mesa: quem
## aprendeu a achar a própria bolacha numa tela acha nas outras.

## Espessura do anel em relação ao diâmetro. Fina demais some numa bolacha de 30
## px; grossa demais vira um alvo.
const RING_RATIO := 0.08
## O vão entre o anel de vez e a bolacha, também em relação ao diâmetro.
const TURN_GAP_RATIO := 0.06

@export var player_name := "":
	set(value):
		player_name = value
		queue_redraw()
@export var fill := AppTheme.COASTER:
	set(value):
		fill = value
		queue_redraw()
@export var ring := AppTheme.GOLD:
	set(value):
		ring = value
		queue_redraw()
@export var turn := false:
	set(value):
		turn = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var diameter := minf(size.x, size.y)
	var center := size * 0.5
	var radius := diameter * 0.5
	var ring_width := maxf(2.0, diameter * RING_RATIO)
	# O anel de vez fica por fora, e a bolacha encolhe para caber dentro do mesmo
	# quadrado: acender a vez não pode empurrar o que está em volta.
	if turn:
		draw_arc(center, radius - ring_width * 0.5, 0.0, TAU, 48, AppTheme.ACCENT, ring_width, true)
		radius -= ring_width + diameter * TURN_GAP_RATIO
	draw_circle(center, radius, fill)
	draw_arc(center, radius - ring_width * 0.5, 0.0, TAU, 48, ring, ring_width, true)
	var face := AppTheme.display(900)
	var font_size := maxi(8, int(radius * 1.05))
	var baseline := center.y + (face.get_ascent(font_size) - face.get_descent(font_size)) * 0.5
	draw_string(
		face, Vector2(center.x - radius, baseline), initial_of(player_name),
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, ink_for(fill)
	)


## A primeira letra ou número do nome, em maiúscula. Apelido é escolhido por gente
## ("k'rec@"), e a bolacha não pode mostrar um apóstrofo.
static func initial_of(name: String) -> String:
	for character in name:
		if character.is_valid_int() or character.to_upper() != character.to_lower():
			return character.to_upper()
	return "?"


## Tinta legível sobre um fundo: escura sobre claro, giz sobre escuro. O limite é
## a luminância relativa 0,5 — o amarelo (0,57) fica com tinta escura, e a cor de
## qualquer assento, com giz.
static func ink_for(background: Color) -> Color:
	return AppTheme.PAPER_INK if background.srgb_to_linear().get_luminance() > 0.5 else AppTheme.TEXT
