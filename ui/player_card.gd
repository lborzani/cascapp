class_name PlayerCard
extends Control

## Faixa que identifica um dos lados: peça, nome, estado e o que já capturou.
##
## Substitui o rótulo único "Vez das brancas". Um rótulo obriga o jogador a ler
## e traduzir; dois cartões, um aceso e outro apagado, respondem "é minha vez?"
## por posição e brilho, antes da leitura. Em partida em rede o cartão de baixo é
## sempre o do jogador local, para a pergunta ser respondida sem interpretação.
##
## As peças capturadas moram aqui e não numa faixa própria por dois motivos. O
## espaço já existia — entre o nome e a etiqueta "SUA VEZ" o cartão era quase
## todo vazio — e uma faixa separada custava ~70px de altura, que num celular em
## retrato saem direto do tabuleiro. Além disso, uma fileira de peças flutuando
## fora do cartão não diz de quem ela é; dentro, não há como confundir.

const HEIGHT := 68.0

## Peão 1, cavalo e bispo 3, torre 5, dama 9 — a tabela que todo mundo usa. Nas
## damas a pedra vale 1 e a dama 3, que é a proporção com que se troca material.
const MATERIAL := {
	Board.Kind.PAWN: 1,
	Board.Kind.KNIGHT: 3,
	Board.Kind.BISHOP: 3,
	Board.Kind.ROOK: 5,
	Board.Kind.QUEEN: 9,
	Board.Kind.MAN: 1,
	Board.Kind.DAME: 3,
}

## Grande o suficiente para a peça ser reconhecida pela silhueta. Abaixo disso
## um bispo e um peão viram a mesma mancha — e sobre um cartão quase preto, uma
## peça preta pequena simplesmente some.
const CAPTURED_SIZE := 26.0
const CAPTURED_GAP := 1.0
## Centro da fileira, medido do meio do cartão. A peça ocupa metade disso para
## cada lado, então o valor é o que a mantém dentro dos 68px sem encostar na
## borda de baixo.
const CAPTURED_Y := 14.0

var side := Board.Side.WHITE:
	set(value):
		side = value
		queue_redraw()

var title := "":
	set(value):
		title = value
		queue_redraw()

var subtitle := "":
	set(value):
		subtitle = value
		queue_redraw()

var active := false:
	set(value):
		active = value
		queue_redraw()

var in_check := false:
	set(value):
		in_check = value
		queue_redraw()

## Peças que este lado capturou, como inteiros de `Board.piece`.
var captured: Array = []:
	set(value):
		captured = value
		queue_redraw()

## Saldo de material a favor deste lado. Zero ou negativo não desenha nada: a
## vantagem aparece de um lado só, senão o jogador tem de comparar dois números
## para descobrir quem está ganhando, que é a pergunta inteira.
var advantage := 0:
	set(value):
		advantage = value
		queue_redraw()

## Tempo restante formatado. Vazio quando a partida não tem relógio — aí a
## etiqueta "SUA VEZ" volta a ocupar o canto direito.
var clock_text := "":
	set(value):
		clock_text = value
		queue_redraw()

## Menos de 20s no relógio de quem está jogando. Muda a cor da etiqueta, porque
## nesse ponto o número deixa de ser informação e passa a ser urgência.
var clock_urgent := false:
	set(value):
		clock_urgent = value
		queue_redraw()

## Modo mesa: o cartão de quem está do outro lado do aparelho é lido de lá.
##
## A meia volta é feita por `rotation` do Control, e não por transformada dentro
## de `_draw`: o desenho da peça usa `draw_set_transform` por conta própria, e
## `draw_set_transform` **substitui** a transformada em vez de compor com ela —
## a peça sairia direita num cartão de ponta-cabeça. A rotação do nó entra antes
## disso, então as duas convivem.
var upside_down := false:
	set(value):
		upside_down = value
		_apply_rotation()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_rotation()


func _apply_rotation() -> void:
	pivot_offset = size * 0.5
	rotation = PI if upside_down else 0.0


static func material(pieces: Array) -> int:
	var total := 0
	for piece in pieces:
		total += int(MATERIAL.get(Board.kind_of(piece), 0))
	return total


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_background(), rect)

	# Quem não está jogando recua também no conteúdo, e não só no fundo: um
	# cartão inteiro mais apagado lê mais rápido que uma borda a menos.
	var awake := active or in_check
	var pad := 14.0
	var piece_size := size.y * 0.78
	var piece_center := Vector2(pad + piece_size * 0.5, size.y * 0.5)
	# A própria peça como avatar: o mesmo desenho do tabuleiro, então não há
	# vocabulário novo para aprender. E a peça do jogo em curso — um rei de xadrez
	# num cartão de damas era um resto do tempo em que só o xadrez tinha desenho.
	PieceRenderer.draw_piece(
		self, Board.piece(side, Board.kind_of(Game.piece_of(Game.game_id))), piece_center,
		piece_size, 1.0 if awake else 0.45
	)

	var text_x := pad + piece_size + 14.0
	var title_font := AppTheme.font(600)
	var body_font := AppTheme.font(400)
	draw_string(
		title_font, Vector2(text_x, size.y * 0.5 - 3.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19,
		AppTheme.TEXT if awake else Color(AppTheme.TEXT, 0.5)
	)
	var detail := subtitle
	var detail_color := AppTheme.TEXT_DIM if awake else Color(AppTheme.TEXT_DIM, 0.6)
	if in_check:
		detail = "Em xeque"
		detail_color = AppTheme.DANGER
	var detail_width := 0.0
	if not detail.is_empty():
		draw_string(
			body_font, Vector2(text_x, size.y * 0.5 + 18.0), detail,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, detail_color
		)
		detail_width = body_font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0

	_draw_captured(text_x + detail_width)

	# O relógio toma o lugar de "SUA VEZ" quando existe: os dois diriam a mesma
	# coisa (o cartão aceso já indica a vez), e o número diz mais.
	if not clock_text.is_empty():
		_draw_chip(clock_text, 18, _clock_chip_colors())
	elif active:
		_draw_chip("SUA VEZ", 13, [AppTheme.ACCENT, AppTheme.BACKGROUND])


## Devolve `[fundo, texto]`. O relógio do lado parado recua para não competir
## com o de quem está gastando tempo.
func _clock_chip_colors() -> Array:
	if not active:
		return [Color(AppTheme.SURFACE_HIGH, 0.9), AppTheme.TEXT_DIM]
	if clock_urgent:
		return [AppTheme.DANGER, AppTheme.TEXT]
	return [AppTheme.ACCENT, AppTheme.BACKGROUND]


## Segunda linha do cartão, começando depois do subtítulo quando ele existe. Vai
## até onde a etiqueta "SUA VEZ" começa: passar por baixo dela deixaria as
## últimas peças ilegíveis justamente quando é a vez do jogador.
func _draw_captured(start_x: float) -> void:
	if captured.is_empty():
		return

	# Do menos valioso para o mais valioso: a leitura fica igual em toda partida,
	# e peças iguais acabam juntas sem precisar agrupar de propósito.
	var ordered := captured.duplicate()
	ordered.sort_custom(
		func(a, b): return int(MATERIAL.get(Board.kind_of(a), 0)) < int(MATERIAL.get(Board.kind_of(b), 0))
	)

	var advantage_room := 34.0 if advantage > 0 else 0.0
	# O relógio ocupa o canto direito o tempo todo, não só na vez do jogador —
	# então o espaço dele sai da fileira sempre que houver relógio.
	var showing_chip := active or not clock_text.is_empty()
	var limit := size.x - (_chip_width() if showing_chip else 14.0) - advantage_room
	var step := CAPTURED_SIZE + CAPTURED_GAP
	if ordered.size() > 1:
		# Sobrepõe em vez de encolher: peça menor fica ilegível, enquanto uma
		# fileira sobreposta ainda deixa contar e reconhecer.
		step = minf(step, (limit - start_x - CAPTURED_SIZE) / float(ordered.size() - 1))
	step = maxf(step, CAPTURED_SIZE * 0.34)

	var y := size.y * 0.5 + CAPTURED_Y
	for index in ordered.size():
		var center := Vector2(start_x + CAPTURED_SIZE * 0.5 + step * index, y)
		PieceRenderer.draw_piece(self, ordered[index], center, CAPTURED_SIZE)

	if advantage > 0:
		var font := AppTheme.font(700)
		var label := "+%d" % advantage
		var x := start_x + CAPTURED_SIZE + step * (ordered.size() - 1) + 6.0
		draw_string(
			font, Vector2(x, y + 5.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, AppTheme.ACCENT
		)


## Espaço reservado para a etiqueta, seja qual for. Mede o texto mais largo que
## o relógio pode assumir ("10:00") e não o que ele mostra agora: um espaço que
## encolhe faria a fileira de peças capturadas dançar a cada segundo.
func _chip_width() -> float:
	var font := AppTheme.font(700)
	if not clock_text.is_empty():
		return font.get_string_size("10:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 44.0
	return font.get_string_size("SUA VEZ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 44.0


func _draw_chip(label: String, font_size: int, colors: Array) -> void:
	var font := AppTheme.font(700)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var chip := Rect2(
		Vector2(size.x - _chip_width() + 10.0, size.y * 0.5 - 15.0),
		Vector2(text_size.x + 20.0, 30.0)
	)
	var style := StyleBoxFlat.new()
	style.bg_color = colors[0]
	style.set_corner_radius_all(15)
	draw_style_box(style, chip)
	draw_string(
		font, chip.position + Vector2(10.0, 21.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colors[1]
	)


## De quem é a vez é a pergunta que o cartão existe para responder, e ela precisa
## ser respondida **de relance**, sem comparar os dois. Por isso a diferença está
## em quatro sinais somados, e não num só:
##
## - borda de 2px em latão cheio (era 1px a 55%, que sumia no fundo escuro);
## - um brilho da mesma cor em volta, que descola o cartão do fundo — é o sinal
##   mais forte, porque é o único que não depende de comparar bordas;
## - fundo levemente aquecido pela cor de destaque;
## - o cartão parado recua mais fundo (fundo e texto), largando o contraste.
##
## Aumentar só o lado aceso não resolveria: a leitura é relativa, e afastar os
## dois extremos dobra a diferença pelo mesmo custo visual.
func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(AppTheme.RADIUS)
	if in_check:
		style.bg_color = AppTheme.DANGER_SOFT
		style.border_color = AppTheme.DANGER
		style.set_border_width_all(2)
		style.shadow_color = Color(AppTheme.DANGER, 0.28)
		style.shadow_size = 7
	elif active:
		style.bg_color = AppTheme.SURFACE_HIGH.lerp(AppTheme.ACCENT, 0.10)
		style.border_color = AppTheme.ACCENT
		style.set_border_width_all(2)
		style.shadow_color = Color(AppTheme.ACCENT, 0.22)
		style.shadow_size = 7
	else:
		style.bg_color = Color(AppTheme.SURFACE, 0.4)
	return style
