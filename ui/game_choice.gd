class_name GameChoice
extends Control

## Cartão de jogo: uma peça e o nome.
##
## A peça responde antes da palavra, e usa exatamente o mesmo desenho que aparece
## no tabuleiro depois — a escolha do jogo é uma prévia dele, não um formulário.
##
## Era um pedaço de tabuleiro 4x4 com quatro peças em cima. Bonito e caro: cada
## cartão carregava uma lista de posições no catálogo, e desenhava 16 casas, uma
## moldura e quatro peças para dizer "isto é xadrez". Um cavalo diz o mesmo. O
## catálogo emagreceu junto — cada jogo passou de uma lista de quatro triplas
## para um inteiro.
##
## Dois arranjos, o mesmo nó. **Empilhado** onde o cartão é um alvo grande e a
## peça é o que se enxerga de longe. **Em linha** na lista de jogos da tela
## inicial e no cabeçalho da tela seguinte, onde a altura toda seria desperdício.
##
## Em linha ele ainda tem duas larguras: encolhido até o texto (cabeçalho, que é
## um rótulo) ou esticado na tela (lista, onde a linha inteira é o alvo do toque
## e ganha a seta que diz "isto leva a algum lugar").

signal chosen
## A estrela foi tocada. Quem escuta grava e devolve o estado por `favorite` — o
## cartão não fala com o disco, do mesmo jeito que não fala com a navegação.
signal favorite_toggled

## Altura do cartão empilhado, e do cabeçalho em linha.
const HEIGHT := 168.0
const ROW_HEIGHT := 76.0
## Faixa reservada ao nome no arranjo empilhado. Em constante porque o desenho do
## nome e o tamanho da peça têm de concordar sobre ela — dois números soltos
## viram um nome em cima da peça na primeira mudança de altura.
const TEXT_BAND := 46.0
const PAD := 16.0
const GAP := 12.0
const ROW_ICON := 44.0
const TITLE_SIZE := 20
## A estrela desenhada, e a faixa que responde ao toque em volta dela.
##
## Os dois números porque não são a mesma coisa: 20 px é o tamanho em que uma
## estrela ainda se lê como estrela ao lado de um nome, e 46 é o dedo. Desenhar
## no tamanho do alvo daria um enfeite maior que a peça do jogo; ouvir só no
## tamanho do desenho daria um alvo que erra uma vez em cada três.
const STAR_SIZE := 20.0
const STAR_ZONE := 46.0
## Quanto a seta ocupa na direita. O nome do jogo para antes dela e antes da
## estrela — um título longo sobrepondo os dois é o defeito que só aparece no
## aparelho de alguém.
const ARROW_BAND := 30.0
## Onde `tests/card_art.gd` grava o fundo de cada jogo, e o quanto dele aparece.
##
## Baixo de propósito: o fundo é para dar textura à linha, não para ser olhado.
## Acima de ~0.2 as casas claras do tabuleiro começam a competir com o nome, e o
## cartão passa a parecer uma imagem com um texto por cima em vez de uma linha
## de lista.
const ART_DIR := "res://assets/cards"
## Baixo de propósito, e mais alto no ladrilho: ali o degradê some antes de
## chegar ao nome, então a arte pode aparecer mais sem disputar com o texto — e
## precisa, porque num cartão pequeno ela some.
const ART_ALPHA := 0.13
const TILE_ALPHA := 0.20

var title := "":
	set(value):
		title = value
		_fit_row()
		queue_redraw()

## Inteiro de `Board.piece`. Zero desenha só o nome.
var piece := 0:
	set(value):
		piece = value
		queue_redraw()

## Peça e nome lado a lado, em vez de um sobre o outro.
var row := false:
	set(value):
		row = value
		_fit_row()
		queue_redraw()

## Em linha, ocupando a largura toda. É a linha de lista: o alvo do toque é a
## faixa inteira, e não o pedaço que o nome do jogo por acaso ocupa.
var stretch := false:
	set(value):
		stretch = value
		_fit_row()
		queue_redraw()

## Jogo cujo tabuleiro desfocado entra atrás da linha. Vazio, ou sem imagem
## gerada, desenha a linha lisa — a arte é enfeite, e um enfeite que falta não
## pode levar a tela junto.
##
## O recorte, o desfoque, os cantos e o degradê já vêm assados no PNG: aqui é um
## `draw_texture_rect` e mais nada. Ver `tests/card_art.gd`.
var art_id := &"":
	set(value):
		art_id = value
		_art = _load_art("%s/%s.png" % [ART_DIR, art_id])
		_tile = _load_art("%s/%s_tile.png" % [ART_DIR, art_id])
		queue_redraw()

## Aceso. Na tela de escolha é o retorno visual do toque, no instante entre tocar
## e a tela trocar. Antes isto queria dizer "jogo escolhido", e não quer mais: a
## escolha agora é a navegação.
var highlighted := false:
	set(value):
		highlighted = value
		queue_redraw()

## Nenhum modo deste jogo funciona neste build. O cartão continua na grade,
## apagado: um jogo que desaparece parece um jogo que foi removido, e o jogador
## vai procurar o que ele fez de errado. Apagado, ele diz "existe, mas não agora",
## e a tela seguinte explica por quê.
##
## Já existiu um `dim` aqui que queria dizer "cartão não selecionado". Aquele saiu
## porque com a escolha virando navegação nada fica selecionado, e a grade inteira
## parecia desabilitada. Este é o oposto: apaga o que realmente não dá para tocar.
var unavailable := false:
	set(value):
		unavailable = value
		queue_redraw()

## Este cartão aceita ser favoritado. Falso no cabeçalho da tela seguinte, que é
## um rótulo: uma estrela ali marcaria o jogo que o jogador já está abrindo.
var favoritable := false:
	set(value):
		favoritable = value
		queue_redraw()

var favorite := false:
	set(value):
		favorite = value
		queue_redraw()

var _hovered := false
var _art: Texture2D = null
## O recorte da grade. Ver o desenho em [method _draw].
var _tile: Texture2D = null


func _ready() -> void:
	# Só quando a cena não pediu outra altura: como cabeçalho ele é mais baixo
	# que como alvo de toque, e um valor cravado aqui apagaria a escolha da cena.
	if custom_minimum_size.y <= 0.0:
		custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; queue_redraw())


## A arte é enfeite, e um enfeite que falta não pode levar a tela junto: um jogo
## novo entra no catálogo antes de a ferramenta rodar, e o cartão dele desenha o
## fundo liso.
static func _load_art(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Em linha o cartão encolhe até o conteúdo, em vez de atravessar a tela: ele é
## um rótulo, e um rótulo do lado esquerdo de uma faixa vazia parece um botão
## quebrado. A largura sai do texto porque é o que muda entre um jogo e outro.
func _fit_row() -> void:
	if not row:
		return
	if stretch:
		custom_minimum_size = Vector2(0, ROW_HEIGHT)
		return
	var width := AppTheme.font(600).get_string_size(
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE
	).x
	custom_minimum_size = Vector2(PAD * 2.0 + ROW_ICON + GAP + width, ROW_HEIGHT)


func _gui_input(event: InputEvent) -> void:
	# Por [Tap] e não pelas duas espécies de evento: um clique chega duas vezes, e
	# contá-lo duas vezes marcava e desmarcava o favorito no mesmo toque — a
	# estrela simplesmente não funcionava.
	if not Tap.began(event):
		return
	var at := Tap.at(event)
	accept_event()
	# A estrela é um segundo alvo dentro do primeiro, e por isso responde antes:
	# a linha inteira leva ao jogo, menos o pedaço que guarda o jogo.
	if _star_zone().has_point(at):
		favorite_toggled.emit()
		return
	chosen.emit()


## A faixa da estrela, ou um retângulo vazio onde ela não existe — um retângulo
## vazio não contém ponto nenhum, e o toque cai direto no cartão.
##
## Em linha ela fica antes da seta, no meio da altura. Empilhada, no canto
## superior direito — que é onde a estrela mora em qualquer grade de cartões, e é
## o canto que a peça e o nome não usam.
func _star_zone() -> Rect2:
	if not favoritable:
		return Rect2()
	if not row:
		return Rect2(size.x - STAR_ZONE, 0.0, STAR_ZONE, STAR_ZONE)
	if not stretch:
		return Rect2()
	return Rect2(size.x - ARROW_BAND - STAR_ZONE, 0.0, STAR_ZONE, size.y)


func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	# Entre o fundo e o conteúdo: a arte cobre o preenchimento do cartão e é
	# coberta pela peça e pelo nome, que é a ordem que mantém o texto legível.
	#
	# **Dois recortes, e não um esticado.** A faixa da lista é larga e baixa;
	# esticá-la num cartão de grade quase quadrado deformava o tabuleiro, e um
	# tabuleiro de casas retangulares atrás do nome do jogo chama mais atenção do
	# que o nome. Era por isso que a grade ficou sem arte nenhuma quando a tela
	# inicial deixou de ser uma lista. `tests/card_art.gd` assa os dois.
	var art := _art if stretch else _tile
	if art != null and (stretch or not row):
		var alpha := ART_ALPHA if stretch else TILE_ALPHA
		draw_texture_rect(
			art, Rect2(Vector2.ZERO, size), false, Color(1.0, 1.0, 1.0, alpha * _fade())
		)
	if row:
		_draw_row()
	else:
		_draw_stacked()


## Peça e nome recuam juntos quando o jogo não pode ser jogado. Apagar só um dos
## dois deixaria o cartão parecendo meio carregado, e não indisponível.
func _fade() -> float:
	return 0.4 if unavailable else 1.0


func _draw_row() -> void:
	var font := AppTheme.display(900)
	PieceRenderer.draw_piece(
		self, piece, Vector2(PAD + ROW_ICON * 0.5, size.y * 0.5), ROW_ICON, _fade()
	)
	var text_x := PAD + ROW_ICON + GAP
	# Largura disponível, e não `-1`: esticado, o que sobra à direita é da seta e
	# da estrela, e o nome que passasse por cima delas só seria visto num jogo de
	# nome comprido — que é o jogo que ainda não existe.
	var text_width := -1.0
	if stretch:
		var reserved := ARROW_BAND + (STAR_ZONE if favoritable else 0.0)
		text_width = maxf(size.x - text_x - reserved, 0.0)
	draw_string(
		font, Vector2(text_x, size.y * 0.5 + TITLE_SIZE * 0.36), title,
		HORIZONTAL_ALIGNMENT_LEFT, text_width, TITLE_SIZE, Color(AppTheme.TEXT, _fade())
	)
	if not stretch:
		return
	if favoritable:
		_draw_star(_star_zone().get_center())
	# Mesma seta da lista de salas: um jogo aqui abre outra tela, e a linha
	# precisa dizer isso sem gastar uma palavra.
	var arrow := Vector2(size.x - 22.0, size.y * 0.5)
	draw_polyline(
		PackedVector2Array([
			arrow + Vector2(-4.0, -7.0), arrow + Vector2(4.0, 0.0), arrow + Vector2(-4.0, 7.0)
		]),
		Color(AppTheme.TEXT_DIM, _fade()), 2.0, true
	)


## Cheia quando é favorito, vazada quando não é.
##
## Vazada e não ausente: uma estrela que só aparece depois de marcada é uma
## função que ninguém descobre. Vazada em `TEXT_DIM` ela convida sem competir com
## o nome do jogo, que continua sendo o que a linha diz.
func _draw_star(center: Vector2) -> void:
	var points := PackedVector2Array()
	var radius := STAR_SIZE * 0.5
	for step in 10:
		# Dez vértices alternando ponta e vale; a ponta de cima é o -90° inicial,
		# que é como uma estrela é lida.
		var angle := -PI * 0.5 + PI * float(step) / 5.0
		var reach := radius if step % 2 == 0 else radius * 0.44
		points.append(center + Vector2(cos(angle), sin(angle)) * reach)
	if favorite:
		draw_colored_polygon(points, Color(AppTheme.ACCENT, _fade()))
		return
	points.append(points[0])
	draw_polyline(points, Color(AppTheme.TEXT_DIM, _fade() * 0.8), 1.6, true)


## O cartão da grade: peça grande em cima, nome embaixo, estrela no canto.
##
## As medidas saem do tamanho do cartão e não de constantes, porque este mesmo
## desenho serve a um cartão de 168 px de altura e a um de 118 numa grade de três
## colunas. Com número fixo, o nome de 20 px cabia no primeiro e transbordava no
## segundo — e transbordar era o caso que a tela inicial nova produz.
func _draw_stacked() -> void:
	var font := AppTheme.display(900)
	var text_size := int(clampf(size.x / 6.0, 14.0, float(TITLE_SIZE) + 2.0))
	# Duas linhas de nome cabem: "Batalha Naval" numa coluna de 120 px não cabe em
	# uma, e abreviar o nome do jogo na tela que serve para escolher o jogo seria
	# economizar no lugar errado.
	var band := float(text_size) * 2.6 + PAD
	var icon := minf(size.x - PAD * 2.0, size.y - band)
	var center := Vector2(size.x * 0.5, (size.y - band) * 0.5 + PAD * 0.4)
	# A bolacha atrás da peça: é a mesma moldura redonda da sala de espera e da
	# coluna de jogadores, e é ela que separa a peça da arte de fundo.
	draw_circle(center, icon * 0.46, Color(AppTheme.COASTER, _fade() * 0.92))
	draw_arc(center, icon * 0.46, 0.0, TAU, 40, Color(AppTheme.GOLD, _fade() * 0.7), 2.0, true)
	PieceRenderer.draw_piece(self, piece, center, icon * 0.72, _fade())

	draw_multiline_string(
		font, Vector2(PAD * 0.5, size.y - band + float(text_size)), title.to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, size.x - PAD, text_size, 2,
		Color(AppTheme.TEXT, _fade()), TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND
	)
	if favoritable:
		_draw_star(_star_zone().get_center())


## Tracejado de giz quando em repouso, contorno amarelo quando aceso: o cartão
## segue o mesmo vocabulário dos painéis secundários do tema.
func _background() -> StyleBox:
	if highlighted:
		return AppTheme.box(AppTheme.SURFACE_HIGH, AppTheme.RADIUS_LARGE, AppTheme.ACCENT, 2)
	var fill := AppTheme.SURFACE if _hovered else Color(AppTheme.SURFACE, 0.55)
	return AppTheme.dashed(fill, AppTheme.LINE_SOFT, AppTheme.RADIUS_LARGE)
