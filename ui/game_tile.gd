class_name GameTile
extends Button

## O bloco de um jogo na tela inicial: a cor do jogo, a peça, o nome e a lotação.
##
## A tela inicial era um cardápio em linhas, com pontilhado até a lotação. Lia
## bem e não convidava: sete linhas iguais são sete linhas a comparar. Um bloco
## na cor do jogo se acha pelo canto do olho, e o polegar tem o bloco inteiro
## como alvo.
##
## É um `Button` de verdade, e não um `Control` com `_gui_input`: assim herda o
## que todo botão do app já tem — o aperto com escala e o arrasto que passa para
## a lista (`Nav`) —, e o `pressed` é o "escolhi este jogo".
##
## A estrela é um segundo botão por cima do canto: guarda o jogo sem abri-lo.

## A estrela foi tocada. Quem escuta grava e devolve o estado por `favorite` — o
## bloco não fala com o disco.
signal favorite_toggled

const HEIGHT := 112.0
const PAD := 14.0
const ICON := 40.0
const TITLE_SIZE := 22
const COUNT_SIZE := 13
const STAR_SIZE := 20.0
const STAR_ZONE := 46.0

var game_id: StringName = &"":
	set(value):
		game_id = value
		_refresh()
var favorite := false:
	set(value):
		favorite = value
		_star.queue_redraw()
## Nenhum modo deste jogo funciona neste build. O bloco continua na grade,
## apagado: um jogo que some parece um jogo que foi removido.
var unavailable := false:
	set(value):
		unavailable = value
		modulate.a = 0.4 if value else 1.0

var _coaster: Coaster = null
var _star: Button = null


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Sem caixa do tema: o bloco desenha a própria placa.
	theme_type_variation = &"IconButton"
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

	_coaster = Coaster.new()
	_coaster.fill = Color(AppTheme.ACCENT_INK, 0.2)
	_coaster.ring = Color(0, 0, 0, 0)
	_coaster.position = Vector2(PAD, PAD)
	_coaster.size = Vector2(ICON, ICON)
	add_child(_coaster)

	_star = Button.new()
	_star.theme_type_variation = &"IconButton"
	_star.pressed.connect(func() -> void: favorite_toggled.emit())
	_star.draw.connect(_draw_star)
	add_child(_star)


func _refresh() -> void:
	_coaster.piece = Game.piece_of(game_id)
	_star.tooltip_text = "Favoritar %s" % Game.game_title(game_id)
	queue_redraw()


func _draw() -> void:
	var color: Color = AppTheme.GAME_COLORS.get(String(game_id), AppTheme.SURFACE_HIGH)
	var edge := float(AppTheme.PLATE_EDGE)
	# A placa: a borda de baixo é a mesma caixa, mais escura, um pouco abaixo.
	# Apertado, o rosto desce até cobri-la — o bloco afunda.
	var sunk := edge if is_pressed() else 0.0
	var face := Rect2(0.0, sunk, size.x, size.y - edge)
	draw_style_box(AppTheme.box(color.darkened(0.3), AppTheme.RADIUS_LARGE), Rect2(0.0, edge, size.x, size.y - edge))
	draw_style_box(AppTheme.box(color, AppTheme.RADIUS_LARGE), face)
	_coaster.position.y = PAD + sunk
	# À mão e não por âncora: o bloco não é contêiner, e a estrela afunda junto.
	_star.position = Vector2(size.x - STAR_ZONE, sunk)
	_star.size = Vector2(STAR_ZONE, STAR_ZONE)

	var ink := AppTheme.ACCENT_INK
	# A peça do jogo, grande e apagada, inclinada no lado direito: é o que faz o
	# bloco ler como "este jogo" antes de se ler o nome. Tingida de tinta escura,
	# vira silhueta sobre a cor.
	PieceRenderer.draw_piece(
		self, Game.piece_of(game_id), Vector2(size.x - face.size.y * 0.4, face.get_center().y + 6.0),
		face.size.y * 0.82, 0.14, 1.0, false, ink, -0.18
	)
	var bottom := face.end.y - PAD
	draw_string(
		AppTheme.font(700), Vector2(PAD, bottom), _players_text(),
		HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2.0, COUNT_SIZE, ink
	)
	draw_string(
		AppTheme.display(700), Vector2(PAD, bottom - COUNT_SIZE - 5.0), Game.game_title(game_id),
		HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2.0, TITLE_SIZE, ink
	)


## Quantos jogam: uma faixa ("2 a 6") onde a mesa varia, um número onde é fixa.
func _players_text() -> String:
	var span := Game.players_range(game_id)
	if span.is_empty():
		return "%d jogadores" % Game.players_of(game_id)
	return "%d a %d jogadores" % [int(span[0]), int(span[1])]


## Cheia quando é favorito, vazada quando não é. Vazada e não ausente: uma estrela
## que só aparece depois de marcada é uma função que ninguém descobre.
func _draw_star() -> void:
	var center := _star.size * 0.5
	var points := PackedVector2Array()
	var radius := STAR_SIZE * 0.5
	for step in 10:
		var angle := -PI * 0.5 + PI * float(step) / 5.0
		var reach := radius if step % 2 == 0 else radius * 0.44
		points.append(center + Vector2(cos(angle), sin(angle)) * reach)
	if favorite:
		_star.draw_colored_polygon(points, AppTheme.ACCENT_INK)
		return
	points.append(points[0])
	_star.draw_polyline(points, Color(AppTheme.ACCENT_INK, 0.55), 2.0, true)
