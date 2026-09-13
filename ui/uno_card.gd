class_name UnoCardArt
extends RefCounted

## Desenha uma carta de Uno por código, num `CanvasItem` qualquer.
##
## Ponto único de desenho de carta: o leque da mão, o descarte, o monte, a
## contagem dos adversários e a folha de contato passam todos por aqui. É a mesma
## forma do `PieceRenderer` — funções estáticas que recebem o canvas — e pelo
## mesmo motivo: uma mão de vinte cartas em leque seriam vinte `Control` com
## layout próprio, quando o que se quer é vinte desenhos.
##
## ## Por código, e não em arquivo
##
## São 108 cartas e 15 desenhos diferentes: dez algarismos, quatro ações e o
## verso. Em SVG seriam 15 arquivos por cor mais os curingas, e trocar a paleta
## seria reexportar tudo. Aqui a cor é um parâmetro e o desenho é um só.
##
## Diferente dos ícones de peça, que **são** arquivo (`assets/pieces/`): aqueles
## precisam ser irmãos entre si num tamanho só, e um algarismo desenhado à mão em
## polígono nunca ficaria tão legível quanto o mesmo algarismo tipografado.
## Aqui o miolo é tipografia de verdade — `draw_string` com a fonte do tema.
##
## ## A silhueta é a leitura
##
## Uma carta se reconhece de longe por três coisas, nesta ordem: a **cor**, a
## **moldura clara** e o **símbolo grande no meio**. As três estão aqui, e o
## resto — os cantos pequenos — só serve para quando as cartas estão sobrepostas
## no leque e só a faixa da esquerda aparece.
##
## A oval inclinada no meio é o que faz a carta ler como carta de Uno e não como
## um retângulo colorido com um número. Ela é o desenho da marca, e é de graça:
## um polígono de elipse girado.

## As quatro cores, na ordem de `UnoRules.CardColor`.
##
## Parentes das do Ludo (`LudoView.COLORS`) sem serem as mesmas, e não é
## descuido: lá elas pintam casas de tabuleiro sob peças claras e precisam ser
## discretas; aqui elas **são** a carta, ocupam a mão inteira da tela e precisam
## aguentar uma moldura clara em volta sem sumir. Copiar as do Ludo deixava o
## leque parecendo desbotado ao lado do descarte.
##
## Duplicar a lista é o preço de as duas telas poderem ser afinadas em separado.
## Uma constante compartilhada faria um ajuste no Ludo repintar o Uno.
const COLORS := [
	Color("cf4b45"),  # vermelho
	Color("dfa62c"),  # amarelo
	Color("4e9e5c"),  # verde
	Color("4176ad"),  # azul
]

## O corpo do curinga. Quase preto e não preto: preto puro sobre o fundo do app
## — que também é quase preto — faz a carta perder a borda e virar um buraco.
const WILD_BODY := Color("2b2521")

## A moldura e a oval. É o `TEXT` do tema, e não branco puro: o app inteiro é
## quente, e um branco frio no meio de uma mão de cartas denuncia que o desenho
## veio de outro lugar.
const PAPER := Color("f2eae0")

## O verso. Vermelho como o baralho de verdade, escurecido para não competir com
## uma carta vermelha jogada ao lado dele.
const BACK_BODY := Color("8f3833")

const SHADOW := Color(0, 0, 0, 0.34)

## Quanto do fundo entra na carta que não pode ser jogada.
##
## Um **véu da cor do fundo por cima**, e não transparência. A transparência era a
## primeira versão e estava errada por um motivo que só a tela mostrou: a moldura
## da carta é clara, e clara a 58% sobre o fundo quase preto do app vira **cinza**.
## Quatro cartas apagadas lado a lado no leque viravam uma mancha cinza única, com
## as cores mal visíveis dentro dela — o oposto de "estas continuam legíveis, só
## não servem agora".
##
## Com o véu, cada forma continua opaca e nítida; o que muda é a distância delas
## em relação ao fundo. A carta apagada fica escura e quente como o resto do app,
## e o leque volta a ter cartas em vez de uma faixa.
const DIM_VEIL := 0.52

## Proporção da carta de verdade (88 × 58 mm). Tudo aqui é medido em **altura**:
## é ela que a linha do leque decide, e a largura sai daqui.
const ASPECT := 0.66

## Frações da altura. Todas relativas, então a mesma função desenha a carta de
## 30 px do adversário e a de 300 px da folha de contato.
const CORNER := 0.085
const FRAME := 0.055
const SHADOW_OFFSET := Vector2(0.03, 0.045)
## Meias-medidas da oval, e o quanto ela deita. Vinte graus é o bastante para
## ler como inclinada e pouco o bastante para o algarismo dentro dela continuar
## de pé — a oval gira, o número não.
##
## Ela é **menor que a carta com folga**, e isso foi medido na folha de contato:
## com a oval ocupando quase a largura toda, a cor virava um filete entre ela e a
## moldura, e a primeira coisa que se lê numa carta de Uno — a cor — passava a ser
## a última. Sobrar cor em volta é o desenho, não desperdício.
const OVAL_HALF := Vector2(0.25, 0.34)
const OVAL_TILT := -0.35

const GLYPH_SIZE := 0.44
const CORNER_GLYPH_SIZE := 0.15
## Para dentro o bastante para o canto cair **sobre a cor**, e não sobre a moldura
## clara. Papel sobre papel é um canto que não existe, e era assim que a folha de
## contato mostrava a primeira versão: sete cartas no leque e nenhum canto legível.
const CORNER_INSET := Vector2(0.20, 0.125)


## `height` é a altura da carta em pixels; `center` é o meio dela.
##
## `rotation` existe pelo leque: as cartas da mão abrem em arco, e girar aqui
## dentro é uma transformada só em vez de o chamador recalcular quatro cantos.
##
## `dim` apaga a carta que não pode ser jogada. Apagar e não esconder: a mão é a
## informação do jogador, e sumir com metade dela para dizer "estas não servem"
## esconde justamente o que ele precisa para decidir se compra.
static func draw_card(
	canvas: CanvasItem, card_code: int, center: Vector2, height: float,
	rotation := 0.0, dim := false, opacity := 1.0
) -> void:
	if height <= 0.0 or opacity <= 0.0:
		return
	var alpha := opacity
	var color := _body_color(card_code)

	canvas.draw_set_transform(center + SHADOW_OFFSET * height, rotation, Vector2.ONE)
	_rounded(canvas, height, 1.0, _fade(SHADOW, alpha))
	canvas.draw_set_transform(center, rotation, Vector2.ONE)

	# Moldura clara por fora, corpo colorido por dentro. Dois retângulos e não um
	# contorno traçado: o traço da Godot não acompanha canto arredondado, e a
	# emenda aparece justamente nos quatro cantos.
	_rounded(canvas, height, 1.0, _fade(PAPER, alpha))
	_rounded(canvas, height, 1.0 - FRAME * 2.0, _fade(color, alpha))
	_oval(canvas, height, alpha, card_code)
	_center_glyph(canvas, card_code, height, alpha)
	_corner_glyphs(canvas, card_code, height, alpha)
	# O véu por último: ele afasta a carta inteira do primeiro plano de uma vez, em
	# vez de cada forma dela ter de saber que está apagada.
	if dim:
		_rounded(canvas, height, 1.0, Color(AppTheme.BACKGROUND, DIM_VEIL * opacity))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## O verso, para a mão dos outros e para o monte.
##
## Um desenho e não a carta virada com o miolo apagado: o verso precisa ser
## **inconfundível** de frente nenhuma, senão uma mão de adversário lida de
## relance parece uma mão de cartas vermelhas.
static func draw_back(
	canvas: CanvasItem, center: Vector2, height: float, rotation := 0.0, opacity := 1.0
) -> void:
	if height <= 0.0 or opacity <= 0.0:
		return
	canvas.draw_set_transform(center + SHADOW_OFFSET * height, rotation, Vector2.ONE)
	_rounded(canvas, height, 1.0, _fade(SHADOW, opacity))
	canvas.draw_set_transform(center, rotation, Vector2.ONE)

	_rounded(canvas, height, 1.0, _fade(PAPER, opacity))
	_rounded(canvas, height, 1.0 - FRAME * 2.0, _fade(BACK_BODY, opacity))
	# A oval do verso é vazia e deitada mais, com a palavra dentro. É o que o
	# baralho de verdade tem, e é o que separa o verso de uma carta vermelha.
	canvas.draw_colored_polygon(
		_ellipse(height * OVAL_HALF.x * 1.05, height * OVAL_HALF.y * 0.92, OVAL_TILT),
		_fade(PAPER, opacity)
	)
	_text(canvas, "UNO", height * 0.20, _fade(BACK_BODY, opacity), Vector2.ZERO)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func width_for(height: float) -> float:
	return height * ASPECT


static func color_of(card_code: int) -> Color:
	return _body_color(card_code)


# --- partes -------------------------------------------------------------------


static func _body_color(card_code: int) -> Color:
	var color := UnoRules.color_of_card(card_code)
	return WILD_BODY if color >= COLORS.size() else COLORS[color]


static func _fade(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)


## Retângulo de cantos arredondados centrado na origem. `scale` encolhe os dois
## lados juntos, que é o que mantém a moldura com a mesma espessura em cima e nos
## lados — encolher só a largura deixaria a moldura fina em cima e grossa ao lado.
static func _rounded(canvas: CanvasItem, height: float, scale: float, color: Color) -> void:
	var half := Vector2(height * ASPECT, height) * 0.5 * scale
	canvas.draw_colored_polygon(rounded_rect(half, height * CORNER * scale), color)


static func rounded_rect(half: Vector2, radius: float, steps := 5) -> PackedVector2Array:
	var points := PackedVector2Array()
	var inner := Vector2(maxf(half.x - radius, 0.0), maxf(half.y - radius, 0.0))
	var corners := [
		Vector2(inner.x, inner.y), Vector2(-inner.x, inner.y),
		Vector2(-inner.x, -inner.y), Vector2(inner.x, -inner.y),
	]
	for index in corners.size():
		var pivot: Vector2 = corners[index]
		var start := index * PI * 0.5
		for step in steps + 1:
			var angle := start + (PI * 0.5) * (float(step) / steps)
			points.append(pivot + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _ellipse(half_x: float, half_y: float, tilt: float, segments := 44) -> PackedVector2Array:
	var points := PackedVector2Array()
	var turn := Transform2D(tilt, Vector2.ZERO)
	for index in segments:
		var angle := TAU * index / segments
		points.append(turn * Vector2(cos(angle) * half_x, sin(angle) * half_y))
	return points


## A oval do meio. No curinga ela é quatro quartos coloridos em vez de papel — é
## o desenho que diz "esta carta é de qualquer cor", e dizer isso com a palavra
## "curinga" escrita obrigaria a ler o que se pode ver.
static func _oval(canvas: CanvasItem, height: float, alpha: float, card_code: int) -> void:
	var half_x := height * OVAL_HALF.x
	var half_y := height * OVAL_HALF.y
	if not UnoRules.is_wild(card_code):
		canvas.draw_colored_polygon(_ellipse(half_x, half_y, OVAL_TILT), _fade(PAPER, alpha))
		return

	canvas.draw_colored_polygon(_ellipse(half_x, half_y, OVAL_TILT), _fade(PAPER, alpha))
	# Os quartos saem do recorte da própria elipse contra quatro quadrantes, e não
	# de arcos calculados à mão: assim eles acompanham a inclinação da oval de
	# graça, e nenhum dos quatro pode ficar com um sinal trocado.
	var oval := _ellipse(half_x * 0.86, half_y * 0.86, OVAL_TILT)
	var reach := maxf(half_x, half_y) * 2.0
	for quadrant in COLORS.size():
		var sign_x := 1.0 if quadrant == 0 or quadrant == 3 else -1.0
		var sign_y := -1.0 if quadrant < 2 else 1.0
		var mask := PackedVector2Array([
			Vector2.ZERO,
			Vector2(sign_x * reach, 0.0),
			Vector2(sign_x * reach, sign_y * reach),
			Vector2(0.0, sign_y * reach),
		])
		for shard in Geometry2D.intersect_polygons(oval, mask):
			canvas.draw_colored_polygon(shard, _fade(COLORS[quadrant], alpha))


## O símbolo grande, no meio da oval.
##
## Cor da carta sobre papel nos números e nas ações; papel sobre os quartos
## coloridos no curinga, porque ali não há uma cor da carta — é essa a graça dela.
static func _center_glyph(canvas: CanvasItem, card_code: int, height: float, alpha: float) -> void:
	var value := UnoRules.value_of_card(card_code)
	var ink := _fade(PAPER if UnoRules.is_wild(card_code) else _body_color(card_code), alpha)
	var span := height * GLYPH_SIZE

	match value:
		UnoRules.SKIP:
			_skip(canvas, span * 0.38, span * 0.12, ink)
		UnoRules.REVERSE:
			_reverse(canvas, span * 0.58, ink)
		UnoRules.DRAW_TWO:
			_text(canvas, "+2", span * 0.62, ink, Vector2.ZERO)
		UnoRules.WILD:
			pass
		UnoRules.WILD_FOUR:
			# Sobre os quatro quartos coloridos, e por isso com o miolo escuro
			# atrás: um "+4" claro direto sobre o amarelo some, e sobre o vermelho
			# vibra. O disco é o que dá a ele um fundo só.
			canvas.draw_circle(Vector2.ZERO, span * 0.44, _fade(WILD_BODY, alpha))
			_text(canvas, "+4", span * 0.62, _fade(PAPER, alpha), Vector2.ZERO)
		_:
			_text(canvas, str(value), span, ink, Vector2.ZERO)


## Os cantos: o mesmo símbolo, pequeno, em cima à esquerda e embaixo à direita.
##
## Existem para o **leque**. Com a mão aberta em arco as cartas se cobrem e só a
## faixa da esquerda de cada uma aparece — sem o canto, uma mão de sete cartas
## mostra sete listras coloridas e um símbolo só, o da última.
##
## Os dois de pé, e não o de baixo de cabeça para baixo como na carta de verdade.
## Lá a meia volta serve para a carta ser lida com ela virada na mão; aqui a
## orientação é de quem desenha, e um "+2" de ponta-cabeça na tela lê como erro de
## desenho em vez de como convenção de baralho.
static func _corner_glyphs(canvas: CanvasItem, card_code: int, height: float, alpha: float) -> void:
	var label := _short_label(card_code)
	if label.is_empty():
		return
	var ink := _fade(PAPER, alpha)
	var span := height * CORNER_GLYPH_SIZE
	var half := Vector2(height * ASPECT, height) * 0.5
	var inset := Vector2(half.x * 2.0 * CORNER_INSET.x, height * CORNER_INSET.y)
	_text(canvas, label, span, ink, -half + inset)
	_text(canvas, label, span, ink, half - inset)


## Como a carta se escreve pequena. Os símbolos desenhados não cabem em 17% da
## altura, então o canto é sempre texto — e um texto curto o bastante para não
## precisar ser lido, só reconhecido.
static func _short_label(card_code: int) -> String:
	var value := UnoRules.value_of_card(card_code)
	match value:
		UnoRules.SKIP:
			return "Ø"
		UnoRules.REVERSE:
			return "⇄"
		UnoRules.DRAW_TWO:
			return "+2"
		UnoRules.WILD:
			return "★"
		UnoRules.WILD_FOUR:
			return "+4"
		_:
			return str(value)


# --- símbolos -----------------------------------------------------------------


## O pula: um anel com uma barra atravessada.
##
## Anel e não disco cheio: cheio ele lê como um ponto grande, e a placa de
## proibido — que é o que a carta quer dizer — é justamente o contorno.
static func _skip(canvas: CanvasItem, radius: float, thickness: float, ink: Color) -> void:
	canvas.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, ink, thickness)
	var reach := Vector2(radius, radius) * 0.78
	canvas.draw_line(-reach, reach, ink, thickness)


## O inverte: duas setas em sentidos opostos, uma acima da outra.
static func _reverse(canvas: CanvasItem, span: float, ink: Color) -> void:
	var gap := span * 0.30
	_arrow(canvas, Vector2(0.0, -gap), span, 1.0, ink)
	_arrow(canvas, Vector2(0.0, gap), span, -1.0, ink)


static func _arrow(canvas: CanvasItem, origin: Vector2, span: float, facing: float, ink: Color) -> void:
	var half := span * 0.60
	var thick := span * 0.13
	var head := span * 0.40
	var tip := origin + Vector2(half * facing, 0.0)
	canvas.draw_colored_polygon(PackedVector2Array([
		origin + Vector2(-half * facing, -thick), origin + Vector2(half * facing * 0.35, -thick),
		origin + Vector2(half * facing * 0.35, thick), origin + Vector2(-half * facing, thick),
	]), ink)
	canvas.draw_colored_polygon(PackedVector2Array([
		tip,
		tip + Vector2(-head * facing, -head * 0.72),
		tip + Vector2(-head * facing, head * 0.72),
	]), ink)


## O desenho de duas cartinhas empilhadas — que é o que o baralho de verdade põe
## no +2 e no +4 — **saiu**, e vale registrar por quê.
##
## Ele existiu e foi julgado na folha de contato: em 96 px de altura, que é o
## tamanho da mão num celular, as duas cartinhas somam uns dez pixels cada e viram
## uma mancha única. Duas manchas parecidas — a do +2 e a do +4 — no lugar onde a
## carta deveria estar dizendo qual das duas ela é.
##
## O "+2" e o "+4" escritos grandes resolvem no tamanho que importa, e a distinção
## entre eles passa a ser o que já era a mais forte: o corpo colorido do +2 contra
## os quatro quartos do +4.


## Texto centrado no ponto, com a fonte do tema.
##
## `draw_string` ancora na **linha de base** e alinha à esquerda, então centrar de
## verdade pede a medida da string. Sem isso todo algarismo fica alto e à direita
## do lugar, e o 1 fica visivelmente mais fora que o 8.
##
## Nunca mexe na transformada. Ela é do `draw_card`, que já pôs a carta no lugar e
## no ângulo dela — e `CanvasItem` **não tem como devolver** a transformada de
## desenho corrente, só escrevê-la. Quem escrever aqui dentro não tem como
## restaurar o que havia, e o resto da carta sai desenhado no canto da tela.
static func _text(
	canvas: CanvasItem, label: String, span: float, ink: Color, at: Vector2
) -> void:
	var font := AppTheme.font(700)
	var size := int(maxf(span, 6.0))
	var measure := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	# A altura visual do algarismo, e não a da linha: a linha reserva espaço para
	# acentos e descidas que um "7" não usa, e centrar por ela deixa o número
	# assentado acima do meio da oval.
	var rise := font.get_ascent(size) - font.get_descent(size)
	canvas.draw_string(
		font, at + Vector2(-measure.x * 0.5, rise * 0.5),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, ink
	)
