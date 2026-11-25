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
	Color("ff4d5e"),  # vermelho
	Color("e0a800"),  # amarelo
	Color("3dbe5c"),  # verde
	Color("3b8bff"),  # azul
]

## O corpo do curinga. Quase preto e não preto: preto puro sobre o fundo do app
## — que também é quase preto — faz a carta perder a borda e virar um buraco.
const WILD_BODY := AppTheme.COASTER

## A moldura e a oval. É o `TEXT` do tema, e não branco puro: o app inteiro é
## quente, e um branco frio no meio de uma mão de cartas denuncia que o desenho
## veio de outro lugar.
const PAPER := AppTheme.PAPER
## O véu da carta apagada. Fixo, e não o fundo do tema: a carta é desenho
## protegido, e o tom do véu faz parte de como ela aparece apagada.
const VEIL_COLOR := AppTheme.COASTER

## O verso. Vermelho como o baralho de verdade, escurecido para não competir com
## uma carta vermelha jogada ao lado dele.
const BACK_BODY := AppTheme.BACKGROUND
## A mancha coral no meio do verso, como no protótipo. Sem palavra nenhuma.
const BACK_SPOT := AppTheme.DANGER

const SHADOW := Color(0, 0, 0, 0.45)

## O baralho da loja de quem olha (`Cosmetics.deck_of`): a sua mão, o descarte e o
## monte saem nele. Vazio é o de sempre. As quatro cores de jogo nunca mudam: o
## baralho troca a moldura (`paper`), o verso (`back`, `spot`, `back_pattern`) e
## um desenho discreto na face (`face`), nada que pese na leitura da carta. Com
## `accent`, os desenhos saem nessa cor (o ouro dos testadores).
static var deck := {}
## O baralho de sempre, dito às claras: `skin` vazio cai no `deck` de quem olha,
## e a mão de quem não tem baralho da loja tem de sair no padrão, não no meu.
const STANDARD := {"paper": PAPER}

## As formas cheias da carta são **textura**, e não polígono.
##
## Polígono na Godot não tem antialiasing, e o MSAA 2D do projeto não chega a
## esse desenho: a carta girada no leque saía com a borda em degrau. Um traço
## suavizado por cima do contorno ajudava pouco. As formas viraram SVG em
## `assets/uno/`, rasterizadas grandes na importação e com mipmaps; desenhadas
## pequenas e giradas, a filtragem da textura suaviza a borda. A cor continua
## sendo parâmetro: as texturas são brancas e o desenho as tinge.
##
## Cada SVG tem uma folga transparente em volta da forma, para a borda do quad
## cair no transparente e não na forma.
const CARD_TEX := preload("res://assets/uno/card.svg")
const OVAL_TEX := preload("res://assets/uno/oval.svg")
const WILD_TEX := preload("res://assets/uno/wild.svg")
## Folga do `card.svg` em volta do retângulo, em fração da altura dele.
const CARD_PAD := 0.04
## O disco dos SVGs redondos tem raio 100 numa caixa de 216.
const DISC_PAD := 1.08

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
const DIM_VEIL := 0.55

## Proporção da carta de verdade (88 × 58 mm). Tudo aqui é medido em **altura**:
## é ela que a linha do leque decide, e a largura sai daqui.
const ASPECT := 0.66

## Frações da altura. Todas relativas, então a mesma função desenha a carta de
## 30 px do adversário e a de 300 px da folha de contato.
const CORNER := 0.085
const FRAME := 0.045
const SHADOW_OFFSET := Vector2(0.0, 0.04)
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

const GLYPH_SIZE := 0.42
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
##
## `rim` troca a moldura clara por outra cor — o limão da carta que pode ser
## jogada. Transparente é a moldura de sempre.
static func draw_card(
	canvas: CanvasItem, card_code: int, center: Vector2, height: float,
	rotation := 0.0, dim := false, opacity := 1.0, rim := Color(0, 0, 0, 0), skin := {}
) -> void:
	if height <= 0.0 or opacity <= 0.0:
		return
	var alpha := opacity
	var color := _body_color(card_code)
	var chosen := skin if not skin.is_empty() else deck
	var paper: Color = chosen.get("paper", PAPER)

	canvas.draw_set_transform(center + SHADOW_OFFSET * height, rotation, Vector2.ONE)
	_rounded(canvas, height, 1.0, _fade(SHADOW, alpha))
	canvas.draw_set_transform(center, rotation, Vector2.ONE)

	# Moldura clara por fora, corpo colorido por dentro. Dois retângulos e não um
	# contorno traçado: o traço da Godot não acompanha canto arredondado, e a
	# emenda aparece justamente nos quatro cantos.
	_rounded(canvas, height, 1.0, _fade(paper if rim.a <= 0.0 else rim, alpha))
	_rounded(canvas, height, 1.0 - FRAME * 2.0, _fade(color, alpha))
	var accent: Color = chosen.get("accent", PAPER)
	_pattern(canvas, str(chosen.get("face", "")), height, _fade(Color(accent, 0.3 if chosen.has("accent") else 0.22), alpha), card_code)
	# Corpo chapado e o símbolo claro com sombra de tinta, como no protótipo. A
	# oval só no curinga: ali ela é o desenho que diz "qualquer cor".
	if UnoRules.is_wild(card_code):
		_oval(canvas, height, alpha, Transform2D(rotation, center))
		if UnoRules.value_of_card(card_code) == UnoRules.WILD_FOUR:
			# Miolo escuro atrás do "+4": claro direto sobre o amarelo some.
			canvas.draw_circle(Vector2.ZERO, height * GLYPH_SIZE * 0.44, _fade(WILD_BODY, alpha), true, -1.0, true)
	_center_glyph(canvas, card_code, height, _fade(AppTheme.BACKGROUND, alpha), Vector2(0.0, height * 0.03))
	_center_glyph(canvas, card_code, height, _fade(PAPER, alpha), Vector2.ZERO)
	_corner_glyphs(canvas, card_code, height, alpha)
	# O véu por último: ele afasta a carta inteira do primeiro plano de uma vez, em
	# vez de cada forma dela ter de saber que está apagada.
	if dim:
		_rounded(canvas, height, 1.0, Color(VEIL_COLOR, DIM_VEIL * opacity))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## O verso, para a mão dos outros e para o monte.
##
## Um desenho e não a carta virada com o miolo apagado: o verso precisa ser
## **inconfundível** de frente nenhuma, senão uma mão de adversário lida de
## relance parece uma mão de cartas vermelhas.
static func draw_back(
	canvas: CanvasItem, center: Vector2, height: float, rotation := 0.0, opacity := 1.0,
	rim := Color(0, 0, 0, 0), skin := {}
) -> void:
	if height <= 0.0 or opacity <= 0.0:
		return
	var chosen := skin if not skin.is_empty() else deck
	canvas.draw_set_transform(center + SHADOW_OFFSET * height, rotation, Vector2.ONE)
	_rounded(canvas, height, 1.0, _fade(SHADOW, opacity))
	canvas.draw_set_transform(center, rotation, Vector2.ONE)

	_rounded(canvas, height, 1.0, _fade(chosen.get("paper", PAPER) if rim.a <= 0.0 else rim, opacity))
	_rounded(canvas, height, 1.0 - FRAME * 2.0, _fade(chosen.get("back", BACK_BODY), opacity))
	var spot: Color = chosen.get("spot", BACK_SPOT)
	var accent: Color = chosen.get("accent", Color(spot, 0.55))
	_pattern(canvas, str(chosen.get("back_pattern", "")), height, _fade(accent, opacity), 0)
	# Escuro com a mancha coral no meio: nenhuma carta de frente é assim, então
	# a mão de um adversário não parece uma mão de cartas vermelhas.
	_disc(canvas, OVAL_TEX, Vector2(height * ASPECT * 0.30, height * 0.27), _fade(spot, opacity))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Polígono cheio com a borda suavizada.
##
## O preenchimento de polígono da Godot não tem antialiasing, e o MSAA 2D do
## projeto não chega a ele nas capturas nem no aparelho: carta girada no leque
## saía com a borda em degrau. Um traço de 1 px suavizado, na mesma cor, por cima
## do contorno faz a transição que faltava. Ficou para as formas pequenas que
## não são textura: as setas do inverte e as do anel da mesa.
static func fill(canvas: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	canvas.draw_colored_polygon(points, color)
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline, color, 1.0, true)


static func width_for(height: float) -> float:
	return height * ASPECT


static func color_of(card_code: int) -> Color:
	return _body_color(card_code)


# --- partes -------------------------------------------------------------------


## O desenho discreto de um baralho por cima do corpo, dentro da moldura. O sorteio
## é fixo por carta (`seed`), para a mesma carta não piscar entre um quadro e outro.
static func _pattern(canvas: CanvasItem, kind: String, height: float, ink: Color, seed: int) -> void:
	if kind.is_empty():
		return
	var half := Vector2(height * ASPECT, height) * 0.5 * (1.0 - FRAME * 2.0) - Vector2.ONE * height * 0.04
	match kind:
		"stars", "constellation":
			var rng := RandomNumberGenerator.new()
			rng.seed = 7919 + seed
			var points := PackedVector2Array()
			for i in 9:
				var at := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
				points.append(at)
				canvas.draw_circle(at, height * rng.randf_range(0.008, 0.016), ink, true, -1.0, true)
			if kind == "constellation":
				for i in 5:
					canvas.draw_line(points[i], points[i + 1], Color(ink, ink.a * 0.7), maxf(1.0, height * 0.006), true)
		"dots":
			var step := height * 0.11
			var y := -half.y + step * 0.5
			while y < half.y:
				var x := -half.x + step * 0.5
				while x < half.x:
					canvas.draw_circle(Vector2(x, y), height * 0.012, ink, true, -1.0, true)
					x += step
				y += step
		"stripes":
			var gap := height * 0.09
			var d := -half.x - half.y
			# A reta y = x - d, recortada pelo retângulo de dentro.
			while d < half.x + half.y:
				var from := maxf(-half.x, d - half.y)
				var to := minf(half.x, d + half.y)
				if from < to:
					canvas.draw_line(Vector2(from, from - d), Vector2(to, to - d), ink, maxf(1.0, height * 0.02), true)
				d += gap
		"rays":
			for i in 12:
				var angle := TAU * i / 12.0
				var reach := minf(half.x / maxf(absf(cos(angle)), 0.01), half.y / maxf(absf(sin(angle)), 0.01))
				canvas.draw_line(Vector2.ZERO, Vector2(cos(angle), sin(angle)) * reach, ink, maxf(1.0, height * 0.018), true)


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
	round_rect(canvas, Vector2.ZERO, half, color)


## O retângulo de cantos redondos da carta, da textura, centrado em `center` com
## meias-medidas `half`. Público para a mesa desenhar o monte e o tapete na mesma
## forma.
static func round_rect(canvas: CanvasItem, center: Vector2, half: Vector2, color: Color) -> void:
	var pad := Vector2.ONE * half.y * 2.0 * CARD_PAD
	canvas.draw_texture_rect(CARD_TEX, Rect2(center - half - pad, (half + pad) * 2.0), false, color)


## Um disco da textura esticado nas meias-medidas `half`: vira a elipse.
static func _disc(canvas: CanvasItem, texture: Texture2D, half: Vector2, color: Color) -> void:
	var outer := half * DISC_PAD
	canvas.draw_texture_rect(texture, Rect2(-outer, outer * 2.0), false, color)


static func _oval(canvas: CanvasItem, height: float, alpha: float, base: Transform2D) -> void:
	var half := Vector2(height * OVAL_HALF.x, height * OVAL_HALF.y)
	canvas.draw_set_transform_matrix(base * Transform2D(OVAL_TILT, Vector2.ZERO))
	_disc(canvas, WILD_TEX, half, Color(1, 1, 1, alpha))
	canvas.draw_set_transform_matrix(base)


## O símbolo grande, no meio. Desenhado duas vezes por `draw_card`: em tinta e
## deslocado (a sombra), depois claro no lugar.
static func _center_glyph(
	canvas: CanvasItem, card_code: int, height: float, ink: Color, at: Vector2
) -> void:
	var value := UnoRules.value_of_card(card_code)
	var span := height * GLYPH_SIZE

	match value:
		UnoRules.SKIP:
			_skip(canvas, span * 0.38, span * 0.12, ink, at)
		UnoRules.REVERSE:
			_reverse(canvas, span * 0.58, ink, at)
		UnoRules.DRAW_TWO:
			_text(canvas, "+2", span * 0.62, ink, at)
		UnoRules.WILD:
			pass
		UnoRules.WILD_FOUR:
			_text(canvas, "+4", span * 0.62, ink, at)
		_:
			_text(canvas, str(value), span, ink, at)


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
static func _skip(canvas: CanvasItem, radius: float, thickness: float, ink: Color, at: Vector2) -> void:
	canvas.draw_arc(at, radius, 0.0, TAU, 48, ink, thickness, true)
	var reach := Vector2(radius, radius) * 0.78
	canvas.draw_line(at - reach, at + reach, ink, thickness, true)


## O inverte: duas setas em sentidos opostos, uma acima da outra.
static func _reverse(canvas: CanvasItem, span: float, ink: Color, at: Vector2) -> void:
	var gap := span * 0.30
	_arrow(canvas, at + Vector2(0.0, -gap), span, 1.0, ink)
	_arrow(canvas, at + Vector2(0.0, gap), span, -1.0, ink)


static func _arrow(canvas: CanvasItem, origin: Vector2, span: float, facing: float, ink: Color) -> void:
	var half := span * 0.60
	var thick := span * 0.13
	var head := span * 0.40
	var tip := origin + Vector2(half * facing, 0.0)
	fill(canvas, PackedVector2Array([
		origin + Vector2(-half * facing, -thick), origin + Vector2(half * facing * 0.35, -thick),
		origin + Vector2(half * facing * 0.35, thick), origin + Vector2(-half * facing, thick),
	]), ink)
	fill(canvas, PackedVector2Array([
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
	var font := AppTheme.legacy_font(700)
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
