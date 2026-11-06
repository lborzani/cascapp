class_name CatalogRow
extends Control

## Uma linha do cardápio de jogos: a peça, o nome, os pontinhos e a lotação.
##
## A grade de cartões pequenos virou cardápio de lousa porque é o que a tela
## inicial faz: **listar o que tem**. Num cartão de 118 px o nome "Batalha Naval"
## quebrava em duas linhas de quatro letras e a peça virava mancha; numa linha, o
## nome cabe inteiro, a lotação fica alinhada à direita como um preço, e o dedo
## tem a faixa toda como alvo.
##
## Os favoritos continuam em cartão grande, acima — lá o cartão é atalho, e aqui a
## linha é catálogo.

signal chosen
## A estrela foi tocada. Quem escuta grava e devolve o estado por `favorite` — a
## linha não fala com o disco, do mesmo jeito que não fala com a navegação.
signal favorite_toggled

const HEIGHT := 54.0
const PAD := 4.0
const ICON := 38.0
const GAP := 12.0
const TITLE_SIZE := 21
const COUNT_SIZE := 14
## A estrela desenhada, e a faixa que responde ao toque em volta dela: 20 px é o
## tamanho em que ela ainda se lê, 46 é o dedo.
const STAR_SIZE := 20.0
const STAR_ZONE := 46.0

var game_id: StringName = &"":
	set(value):
		game_id = value
		queue_redraw()
var favorite := false:
	set(value):
		favorite = value
		queue_redraw()
## Nenhum modo deste jogo funciona neste build. A linha continua no cardápio,
## apagada: um jogo que some parece um jogo que foi removido.
var unavailable := false:
	set(value):
		unavailable = value
		queue_redraw()

var _coaster: Coaster = null


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP
	_coaster = Coaster.new()
	_coaster.ring = Color(AppTheme.GOLD, 0.7)
	add_child(_coaster)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_coaster.position = Vector2(PAD, (size.y - ICON) * 0.5)
		_coaster.size = Vector2(ICON, ICON)
		_coaster.piece = Game.piece_of(game_id)
		_coaster.modulate.a = _fade()


func _gui_input(event: InputEvent) -> void:
	# Por [Tap]: um clique chega duas vezes, e num alvo que **alterna** contar os
	# dois é marcar e desmarcar a estrela no mesmo toque.
	if not Tap.began(event):
		return
	accept_event()
	# A estrela é um segundo alvo dentro do primeiro, e por isso responde antes: a
	# linha inteira leva ao jogo, menos o pedaço que guarda o jogo.
	if _star_zone().has_point(Tap.at(event)):
		favorite_toggled.emit()
		return
	chosen.emit()


func _star_zone() -> Rect2:
	return Rect2(size.x - STAR_ZONE, 0.0, STAR_ZONE, size.y)


func _fade() -> float:
	return 0.4 if unavailable else 1.0


func _draw() -> void:
	_coaster.piece = Game.piece_of(game_id)
	_coaster.modulate.a = _fade()
	var fade := _fade()
	var face := AppTheme.display(900)
	var mono := AppTheme.mono(600)
	var title := Game.game_title(game_id).to_upper()
	var text_x := PAD + ICON + GAP
	var baseline := size.y * 0.5 + TITLE_SIZE * 0.34
	var width := face.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TITLE_SIZE).x
	draw_string(
		face, Vector2(text_x, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		TITLE_SIZE, Color(AppTheme.TEXT, fade)
	)

	var players := _players_text()
	var players_width := mono.get_string_size(players, HORIZONTAL_ALIGNMENT_LEFT, -1.0, COUNT_SIZE).x
	var count_x := size.x - STAR_ZONE - players_width - GAP * 0.5
	# Os pontinhos do cardápio: ligam o nome ao número sem gastar uma palavra, e é
	# o que faz a lista ler como cardápio e não como formulário.
	var dots_from := text_x + width + GAP * 0.5
	if count_x - dots_from > GAP:
		draw_dashed_line(
			Vector2(dots_from, baseline - 4.0), Vector2(count_x - GAP * 0.5, baseline - 4.0),
			Color(AppTheme.LINE_SOFT, fade), 1.5, 5.0
		)
	draw_string(
		mono, Vector2(count_x, baseline - 1.0), players, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		COUNT_SIZE, Color(AppTheme.ACCENT, fade * 0.9)
	)
	_draw_star(_star_zone().get_center(), fade)


## Quantos jogam: uma faixa ("2–6") onde a mesa varia, um número onde ela é fixa.
func _players_text() -> String:
	var span := Game.players_range(game_id)
	if span.is_empty():
		return str(Game.players_of(game_id))
	return "%d–%d" % [int(span[0]), int(span[1])]


## Cheia quando é favorito, vazada quando não é. Vazada e não ausente: uma estrela
## que só aparece depois de marcada é uma função que ninguém descobre.
func _draw_star(center: Vector2, fade: float) -> void:
	var points := PackedVector2Array()
	var radius := STAR_SIZE * 0.5
	for step in 10:
		var angle := -PI * 0.5 + PI * float(step) / 5.0
		var reach := radius if step % 2 == 0 else radius * 0.44
		points.append(center + Vector2(cos(angle), sin(angle)) * reach)
	if favorite:
		draw_colored_polygon(points, Color(AppTheme.ACCENT, fade))
		return
	points.append(points[0])
	draw_polyline(points, Color(AppTheme.TEXT_DIM, fade * 0.8), 1.6, true)
