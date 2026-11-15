class_name PlayerTag
extends Control

## Quem é, de que lado está e se é a vez dele. A etiqueta de um jogador.
##
## É a evolução do cartão de jogador do xadrez, agora com dois formatos e
## servindo a todos os jogos:
##
## - **faixa** (`Shape.STRIP`), nas telas em pé: a largura toda, com o que o lado
##   já capturou e o relógio num placar à direita;
## - **etiqueta** (`Shape.TAG`), nas telas deitadas: um retângulo curto que se
##   ancora ao lugar do jogador — a pilha dele no Uno, o canto do tabuleiro no
##   Ludo. Ali o nome precisa estar **junto do que é dele**, e uma coluna de
##   cartões num canto obriga a procurar duas vezes.
##
## O avatar é a bolacha do tema: a peça do jogo dentro dela nas partidas de
## tabuleiro, a inicial do nome nas outras. A vez acende o anel da bolacha e a
## borda da etiqueta — dois sinais, porque um cartão aceso é lido de relance e
## uma borda sozinha se perde num fundo escuro.

enum Shape { STRIP, TAG }

const HEIGHT := 64.0
const HEIGHT_TAG := 42.0

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

## Passo entre duas bolinhas de peão em casa.
const PIP_STEP := 14.0

## Grande o suficiente para a peça ser reconhecida pela silhueta. Abaixo disso um
## bispo e um peão viram a mesma mancha.
const CAPTURED_SIZE := 24.0
const CAPTURED_GAP := 1.0
## Centro da fileira, medido do meio da faixa.
const CAPTURED_Y := 13.0

@export var shape := Shape.STRIP:
	set(value):
		shape = value
		_apply_shape()

## A peça que representa o jogador na bolacha, de `Board.piece`. Zero deixa a
## bolacha com a inicial do nome.
@export var piece := 0:
	set(value):
		piece = value
		if _coaster != null:
			_coaster.piece = value if photo == null else 0

## A foto da conta do jogador. Com ela a bolacha mostra a foto no lugar da peça
## e da inicial — o lado continua escrito no subtítulo.
var photo: Texture2D = null:
	set(value):
		photo = value
		if _coaster != null:
			_coaster.photo = value
			_coaster.piece = piece if value == null else 0

## A cor do assento — a do jogador no Uno, a do canto no Ludo. Fora desses jogos
## a bolacha é escura como as outras.
@export var seat_color := AppTheme.COASTER:
	set(value):
		seat_color = value
		if _coaster != null:
			_coaster.fill = value

@export var title := "":
	set(value):
		title = value
		if _coaster != null:
			_coaster.player_name = value
		queue_redraw()

@export var subtitle := "":
	set(value):
		subtitle = value
		queue_redraw()

@export var active := false:
	set(value):
		var gained := value and not active
		active = value
		if _coaster != null:
			_coaster.turn = value
		if gained:
			Motion.nudge(self)
		queue_redraw()

## O estado vermelho da etiqueta: xeque no xadrez, uma carta na mão no Uno. O
## texto é de quem usa, porque o que é urgente muda de jogo para jogo — e é ele
## que aparece no lugar do detalhe enquanto o alarme durar.
@export var alert := false:
	set(value):
		alert = value
		queue_redraw()

@export var alert_text := "":
	set(value):
		alert_text = value
		queue_redraw()

## Um selo curto à direita — as cartas na mão no Uno. Com selo a etiqueta vira
## pílula, como os adversários do protótipo. `badge_hot` pinta de coral (uma
## carta só: "UNO!").
@export var badge := "":
	set(value):
		badge = value
		queue_redraw()
@export var badge_hot := false:
	set(value):
		badge_hot = value
		queue_redraw()

## Peças que este lado capturou, como inteiros de `Board.piece`. Só na faixa.
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

## Bolinhas à direita: quantos peões deste jogador já chegaram em casa, de quantos.
## Cheias as que chegaram, vazias as que faltam — a mesma leitura de "3 de 4" sem
## o jogador ter de ler dois números e subtrair.
@export var pips := 0:
	set(value):
		pips = value
		queue_redraw()

@export var pips_filled := 0:
	set(value):
		pips_filled = value
		queue_redraw()

## Tempo restante formatado. Vazio quando a partida não tem relógio — aí a
## etiqueta "SUA VEZ" volta a ocupar o canto direito.
var clock_text := "":
	set(value):
		clock_text = value
		queue_redraw()

## Menos de 20s no relógio de quem está jogando. Muda a cor dos dígitos, porque
## nesse ponto o número deixa de ser informação e passa a ser urgência.
var clock_urgent := false:
	set(value):
		if value == clock_urgent:
			return
		clock_urgent = value
		_sync_beat()
		queue_redraw()

## O pulso do relógio nos últimos segundos, de 0 a 1. Cor parada não chama o
## olho de volta para o relógio; um relógio que bate chama.
var _beat := 0.0:
	set(value):
		_beat = value
		queue_redraw()
var _beat_tween: Tween = null


func _sync_beat() -> void:
	if _beat_tween != null:
		_beat_tween.kill()
		_beat_tween = null
	_beat = 0.0
	if not clock_urgent or not is_inside_tree():
		return
	_beat_tween = create_tween().set_loops()
	_beat_tween.tween_property(self, "_beat", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
	_beat_tween.tween_property(self, "_beat", 0.0, 0.5).set_trans(Tween.TRANS_SINE)

## Modo mesa: a etiqueta de quem está do outro lado do aparelho é lida de lá.
##
## A meia volta é feita por `rotation` do Control, e não por transformada dentro
## de `_draw`: o desenho da peça usa `draw_set_transform` por conta própria, e
## `draw_set_transform` **substitui** a transformada em vez de compor com ela — a
## peça sairia direita numa faixa de ponta-cabeça. A rotação do nó entra antes
## disso, então as duas convivem.
@export var upside_down := false:
	set(value):
		upside_down = value
		_apply_rotation()

var _coaster: Coaster = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coaster = Coaster.new()
	_coaster.custom_minimum_size = Vector2.ZERO
	_coaster.piece = piece
	_coaster.fill = seat_color
	add_child(_coaster)
	_apply_shape()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and clock_urgent:
		_sync_beat.call_deferred()
	# Também ao entrar na árvore: quem recebe o tamanho antes do `add_child` (as
	# pílulas do Uno) não ganha outro RESIZED, e a bolacha ficava sem medida.
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_apply_rotation()
		_layout()


func _apply_shape() -> void:
	custom_minimum_size = Vector2(0, HEIGHT if shape == Shape.STRIP else HEIGHT_TAG)
	_layout()
	queue_redraw()


func _apply_rotation() -> void:
	pivot_offset = size * 0.5
	rotation = PI if upside_down else 0.0


## A bolacha é um nó filho, e um nó filho de um `Control` que não é contêiner não
## se posiciona sozinho.
func _layout() -> void:
	if _coaster == null:
		return
	var diameter := size.y * (0.72 if shape == Shape.STRIP else 0.78)
	_coaster.size = Vector2(diameter, diameter)
	_coaster.position = Vector2(_pad(), (size.y - diameter) * 0.5)


func _pad() -> float:
	return 12.0 if shape == Shape.STRIP else 8.0


func _alerting() -> bool:
	return alert and not alert_text.is_empty()


static func material(pieces: Array) -> int:
	var total := 0
	for value in pieces:
		total += int(MATERIAL.get(Board.kind_of(value), 0))
	return total


func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))

	var awake := active or alert
	var text_x := _pad() + _coaster.size.x + 12.0
	var name_size := 17 if shape == Shape.STRIP else 15
	# Na faixa, quem está na vez lê "Sua vez" em limão na linha de baixo: é a
	# mesma informação do anel, escrita.
	var turn_line := active and shape == Shape.STRIP and not _alerting()
	var has_detail := not subtitle.is_empty() or _alerting() or turn_line
	# Nome sozinho fica no meio da etiqueta; com detalhe, bolinhas ou capturas
	# embaixo, sobe. Sem contar as capturas, o nome ficava no meio e a fileira de
	# peças era desenhada por cima dele.
	var two_lines := has_detail or pips > 0 or (shape == Shape.STRIP and not captured.is_empty())
	var name_y := size.y * 0.5 + (6.0 if not two_lines else -2.0)
	# Com largura, e não `-1`: um apelido longo numa etiqueta ancorada passava por
	# cima do leque do vizinho. Cortar é feio; escrever por cima da mesa é pior.
	var room := maxf(0.0, size.x - text_x - _right_room())
	draw_string(
		AppTheme.display(600), Vector2(text_x, name_y), title,
		HORIZONTAL_ALIGNMENT_LEFT, room, name_size,
		AppTheme.TEXT if awake else AppTheme.TEXT_DIM
	)

	var detail := subtitle
	var detail_color := AppTheme.TEXT_DIM if awake else Color(AppTheme.TEXT_DIM, 0.6)
	if _alerting():
		detail = alert_text
		detail_color = AppTheme.DANGER
	elif turn_line:
		detail = "Sua vez" if subtitle.is_empty() else "Sua vez · %s" % subtitle.to_lower()
		detail_color = AppTheme.ACCENT
	var detail_width := 0.0
	if has_detail:
		var body := AppTheme.font(700 if turn_line else 400)
		var detail_size := AppTheme.SIZE_BODY_S if shape == Shape.STRIP else AppTheme.SIZE_CAPTION
		draw_string(
			body, Vector2(text_x, size.y * 0.5 + 17.0), detail,
			HORIZONTAL_ALIGNMENT_LEFT, _detail_room(room), detail_size, detail_color
		)
		detail_width = body.get_string_size(
			detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size
		).x + 12.0

	if shape == Shape.STRIP:
		_draw_captured(text_x + detail_width)

	# O placar toma o lugar de "SUA VEZ" quando existe: os dois diriam a mesma
	# coisa (o anel da bolacha já indica a vez), e o número diz mais.
	if pips > 0:
		_draw_pips()
	if not clock_text.is_empty():
		_draw_clock()
	if not badge.is_empty():
		_draw_badge()


const BADGE_SIZE := 14


func _badge_width() -> float:
	var text := AppTheme.display(700).get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_SIZE).x
	return maxf(28.0, text + 12.0)


func _draw_badge() -> void:
	var width := _badge_width()
	var rect := Rect2(size.x - width - 9.0, (size.y - 26.0) * 0.5, width, 26.0)
	draw_style_box(AppTheme.box(AppTheme.DANGER if badge_hot else AppTheme.BACKGROUND, 8), rect)
	var face := AppTheme.display(700)
	var text := face.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_SIZE).x
	draw_string(
		face, Vector2(rect.position.x + (width - text) * 0.5, rect.position.y + 18.0), badge,
		HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_SIZE,
		AppTheme.ACCENT_INK if badge_hot else AppTheme.TEXT
	)


## O relógio numa pílula: limão cheio com tinta escura em quem joga, escura e
## apagada em quem espera, coral quando o tempo aperta. Em mono, que é a fonte em
## que 1 e 7 ocupam a mesma largura — um relógio que muda de largura a cada
## segundo empurra o resto da faixa.
func _draw_clock() -> void:
	var font := AppTheme.mono(600)
	var font_size := AppTheme.SIZE_MONO_M if shape == Shape.STRIP else AppTheme.SIZE_MONO_S
	var height := 40.0 if shape == Shape.STRIP else 24.0
	var box := Rect2(
		Vector2(size.x - _chip_width() + 10.0, size.y * 0.5 - height * 0.5),
		Vector2(_chip_width() - 22.0, height)
	)
	var fill := AppTheme.COASTER
	var ink := AppTheme.TEXT_DIM
	if active:
		fill = AppTheme.DANGER if clock_urgent else AppTheme.ACCENT
		ink = AppTheme.ACCENT_INK
		if clock_urgent:
			fill = fill.lightened(0.25 * _beat)
			box = box.grow(2.0 * _beat)
	draw_style_box(AppTheme.box(fill, AppTheme.RADIUS if shape == Shape.STRIP else 8), box)
	var baseline := box.position.y + box.size.y * 0.5 \
		+ (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(
		font, Vector2(box.position.x, baseline), clock_text,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, ink
	)


## Segunda linha da faixa, começando depois do subtítulo quando ele existe. Vai
## até onde o placar começa: passar por baixo dele deixaria as últimas peças
## ilegíveis justamente quando é a vez do jogador.
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
	# O placar ocupa o canto direito o tempo todo, não só na vez do jogador —
	# então o espaço dele sai da fileira sempre que houver relógio.
	var showing_chip := not clock_text.is_empty()
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
		var label := "+%d" % advantage
		var x := start_x + CAPTURED_SIZE + step * (ordered.size() - 1) + 6.0
		draw_string(
			AppTheme.mono(600), Vector2(x, y + 5.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, AppTheme.SIZE_MONO_S, AppTheme.ACCENT
		)


## Quanto do lado direito está ocupado por placar ou etiqueta de vez. É o que o
## texto **não** pode invadir.
func _right_room() -> float:
	if not badge.is_empty():
		return _badge_width() + 18.0
	if not clock_text.is_empty():
		return _chip_width()
	return 10.0


## A linha de baixo divide a largura com as bolinhas; a de cima fica inteira para
## o nome, que é o que precisa ser lido.
func _detail_room(room: float) -> float:
	if pips <= 0:
		return room
	return maxf(0.0, room - _pips_width() - 8.0)


func _pips_width() -> float:
	return float(pips) * PIP_STEP


## As bolinhas ficam na linha de baixo, encostadas à direita: são o placar deste
## jogo, e na linha de cima tirariam do nome a largura que ele não tem de sobra
## numa etiqueta ancorada. A cheia usa a cor do assento quando ele tem uma; sem cor de assento, o
## amarelo do tema, que é como o app marca o que já é seu.
func _draw_pips() -> void:
	var ink := seat_color if seat_color != AppTheme.COASTER else AppTheme.ACCENT
	var radius := PIP_STEP * 0.30
	var left := size.x - _pips_width() - 10.0
	for index in pips:
		var at := Vector2(left + PIP_STEP * (index + 0.5), size.y * 0.5 + 12.0)
		if index < pips_filled:
			draw_circle(at, radius, ink)
		else:
			draw_arc(at, radius, 0.0, TAU, 20, Color(AppTheme.TEXT, 0.35), 1.5, true)


## Espaço reservado para o canto direito, seja o placar ou a etiqueta de vez.
## Mede o texto mais largo que o relógio pode assumir ("10:00") e não o que ele
## mostra agora: um espaço que encolhe faria a fileira de peças capturadas dançar
## a cada segundo.
func _chip_width() -> float:
	var font := AppTheme.mono(600)
	var font_size := AppTheme.SIZE_MONO_M if shape == Shape.STRIP else AppTheme.SIZE_MONO_S
	return font.get_string_size("10:00", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 44.0


## De quem é a vez é a pergunta que a etiqueta existe para responder, e ela
## precisa ser respondida **de relance**, sem comparar as duas. Quem joga sobe um
## degrau de superfície e ganha a borda limão; quem espera fica na superfície
## base, sem borda nenhuma.
func _background() -> StyleBox:
	var radius := AppTheme.RADIUS_LARGE if shape == Shape.STRIP else AppTheme.RADIUS
	if not badge.is_empty():
		radius = int(size.y * 0.5)
	if alert:
		return AppTheme.box(AppTheme.DANGER_SOFT, radius, AppTheme.DANGER, 2)
	if active:
		return AppTheme.box(AppTheme.SURFACE_HIGH, radius, AppTheme.ACCENT, 2)
	return AppTheme.box(AppTheme.SURFACE, radius)
