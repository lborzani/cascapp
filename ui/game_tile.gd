class_name GameTile
extends Button

## O bloco de um jogo na tela inicial: a cor do jogo, o ícone, o nome e a lotação.
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
##
## O ícone é desenhado aqui, em formas simples e numa tinta só (`draw_art`): a
## dama empilhada, as ondas, o dado, as cartas, os prédios, a bola 8. Não é a
## peça do tabuleiro em miniatura — é um sinal que se lê de longe, e por isso
## cabe grande e apagado atrás do nome sem brigar com ele.

## A estrela foi tocada. Quem escuta grava e devolve o estado por `favorite` — o
## bloco não fala com o disco.
signal favorite_toggled

const HEIGHT := 112.0
const PAD := 14.0
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
## Selo escuro ao lado da estrela ("Seu favorito · Elo 1204"). Vazio, não aparece.
var tag := "":
	set(value):
		tag = value
		queue_redraw()
## Nenhum modo deste jogo funciona neste build. O bloco continua na grade,
## apagado: um jogo que some parece um jogo que foi removido.
var unavailable := false:
	set(value):
		unavailable = value
		modulate.a = 0.4 if value else 1.0

var _star: Button = null


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Sem caixa do tema: o bloco desenha a própria placa.
	theme_type_variation = &"IconButton"
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

	_star = Button.new()
	_star.theme_type_variation = &"IconButton"
	_star.pressed.connect(func() -> void: favorite_toggled.emit())
	_star.draw.connect(_draw_star)
	add_child(_star)


func _refresh() -> void:
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
	# À mão e não por âncora: o bloco não é contêiner, e a estrela afunda junto.
	_star.position = Vector2(0.0, sunk)
	_star.size = Vector2(STAR_ZONE, STAR_ZONE)

	var ink := AppTheme.ACCENT_INK
	var unit := face.size.y * 0.3
	draw_art(
		self, game_id, Vector2(size.x - unit - PAD * 1.6, face.position.y + unit + PAD),
		unit, Color(ink, 0.24), color
	)
	if not tag.is_empty():
		var tag_font := AppTheme.font(700)
		var tag_width := tag_font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x + 20.0
		var pill := Rect2(STAR_ZONE, face.position.y + 11.0, tag_width, 24.0)
		draw_style_box(AppTheme.box(ink, 12), pill)
		draw_string(
			tag_font, Vector2(pill.position.x, pill.get_center().y + 4.5), tag,
			HORIZONTAL_ALIGNMENT_CENTER, tag_width, 12, AppTheme.TEXT
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


## Quantos jogam, curto como no protótipo: "2 a 6" onde a mesa varia, "até 4"
## onde as cadeiras vazias viram bot (Ludo), "2 jogadores" onde é fixa.
func _players_text() -> String:
	var span := Game.players_range(game_id)
	if not span.is_empty():
		return "%d a %d" % [int(span[0]), int(span[1])]
	var seats := Game.players_of(game_id)
	if game_id == Game.LUDO:
		return "até %d" % seats
	return "%d jogadores" % seats


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


## O ícone de um jogo em torno de `center`, cabendo num raio `unit`.
##
## `ink` é a tinta do desenho e `hole` a cor do que é vazado nele (as pintas do
## dado, o 8 da bola): quem chama passa a cor do fundo. Estático para o cartão de
## voltar e a folha do jogo usarem o mesmo desenho.
static func draw_art(
	canvas: CanvasItem, id: StringName, center: Vector2, unit: float, ink: Color, hole: Color
) -> void:
	match String(id):
		"checkers":
			# Duas pedras empilhadas.
			canvas.draw_circle(center + Vector2(0.0, unit * 0.22), unit * 0.92, ink)
			canvas.draw_circle(center - Vector2(0.0, unit * 0.12), unit * 0.92, Color(ink, ink.a * 0.9))
			# Um fio na cor do fundo separa as duas: sem ele, em tinta cheia viram uma mancha só.
			canvas.draw_arc(center - Vector2(0.0, unit * 0.12), unit * 0.92, 0.12, PI - 0.12, 24, Color(hole, ink.a), unit * 0.12, true)
		"battleship":
			for row in 2:
				var wave := PackedVector2Array()
				for step in 25:
					var t := step / 24.0
					wave.append(center + Vector2(
						(t - 0.5) * unit * 2.4,
						(row - 0.5) * unit * 0.9 + sin(t * TAU * 1.5) * unit * 0.24
					))
				canvas.draw_polyline(wave, ink, unit * 0.2, true)
		"ludo":
			canvas.draw_set_transform(center, 0.2, Vector2.ONE)
			canvas.draw_style_box(
				AppTheme.box(ink, int(unit * 0.3)), Rect2(Vector2.ONE * -unit * 0.9, Vector2.ONE * unit * 1.8)
			)
			for spot: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)]:
				canvas.draw_circle(spot * unit * 0.46, unit * 0.16, hole)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"uno":
			# Duas cartas, a de trás mais apagada.
			for index in 2:
				canvas.draw_set_transform(center + Vector2((index - 0.5) * unit * 0.7, 0.0), -0.12 + index * 0.4, Vector2.ONE)
				canvas.draw_style_box(
					AppTheme.box(Color(ink, ink.a * (0.6 + 0.4 * index)), int(unit * 0.22)),
					Rect2(-unit * 0.6, -unit * 0.9, unit * 1.2, unit * 1.8)
				)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"monopoly":
			# Três prédios de alturas diferentes, no mesmo chão.
			var ground := center.y + unit * 0.9
			var heights := [1.1, 1.8, 1.4]
			for index in 3:
				var tall := unit * float(heights[index])
				canvas.draw_style_box(
					AppTheme.box(ink, int(unit * 0.12)),
					Rect2(center.x + (index - 1.5) * unit * 0.66, ground - tall, unit * 0.58, tall)
				)
		"pool":
			canvas.draw_circle(center, unit * 0.95, ink)
			var face := AppTheme.display(700)
			var font_size := int(unit * 1.2)
			canvas.draw_string(
				face, Vector2(center.x - unit, center.y + font_size * 0.36), "8",
				HORIZONTAL_ALIGNMENT_CENTER, unit * 2.0, font_size, hole
			)
		"bowling":
			# Um pino e, na frente dele, a bola com os três furos.
			var pin := center + Vector2(unit * 0.38, -unit * 0.05)
			var body := PackedVector2Array()
			for side: float in [1.0, -1.0]:
				var outline := [Vector2(0.13, -0.45), Vector2(0.30, -0.1), Vector2(0.42, 0.25), Vector2(0.38, 0.6), Vector2(0.24, 0.95)]
				if side < 0.0:
					outline.reverse()
				for point: Vector2 in outline:
					body.append(pin + Vector2(point.x * side, point.y) * unit)
			canvas.draw_colored_polygon(body, ink)
			canvas.draw_circle(pin + Vector2(0.0, -0.72) * unit, unit * 0.27, ink)
			var ball := center + Vector2(-unit * 0.45, unit * 0.42)
			canvas.draw_circle(ball, unit * 0.62, hole)
			canvas.draw_circle(ball, unit * 0.52, ink)
			for spot: Vector2 in [Vector2(-0.2, -0.22), Vector2(0.06, -0.3), Vector2(-0.08, 0.04)]:
				canvas.draw_circle(ball + spot * unit, unit * 0.08, hole)
		_:
			# Xadrez, e qualquer jogo que ainda não tenha desenho: a peça dele em
			# silhueta, inclinada.
			PieceRenderer.draw_piece(
				canvas, Game.piece_of(id), center, unit * 2.6, ink.a, 1.0, false,
				Color(ink.r, ink.g, ink.b), -0.18
			)


## O ladrilho de um jogo: a cor dele, a borda de baixo e o ícone. É o "qual jogo"
## de toda lista do app — cartão de voltar, folha, salas abertas, criar sala.
static func draw_badge(canvas: CanvasItem, id: StringName, rect: Rect2) -> void:
	var color: Color = AppTheme.GAME_COLORS.get(String(id), AppTheme.SURFACE_HIGH)
	var radius := int(rect.size.y * 0.24)
	canvas.draw_style_box(
		AppTheme.box(color.darkened(0.3), radius),
		Rect2(rect.position + Vector2(0.0, AppTheme.PLATE_EDGE), rect.size)
	)
	canvas.draw_style_box(AppTheme.box(color, radius), rect)
	draw_art(canvas, id, rect.get_center(), rect.size.y * 0.3, AppTheme.ACCENT_INK, color)
