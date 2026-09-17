class_name AppTheme
extends RefCounted

## Tema construído em código e aplicado na raiz da janela, de onde desce para
## todas as cenas. Em código e não num `.tres` porque uma paleta é um conjunto de
## decisões relacionadas: aqui elas ficam nomeadas, com o porquê ao lado, em vez
## de espalhadas por centenas de linhas de propriedades serializadas.
##
## ## A direção: Boteco
##
## A mesa do bar onde o rolê acontece, puxada do próprio logo — a caneca de
## chopp. Fundo de lousa verde-escura, texto de giz, e o amarelo da cadeira de
## plástico como única cor de ação. O dourado do chopp fica nos anéis das
## bolachas; o papel (comanda, escritura, dado) é o único claro da tela.
##
## Uma cor de ação só significa que ela sempre quer dizer a mesma coisa — "é aqui
## que você age, é sua vez".
##
## O que é **do jogo** não lê daqui: peças, cartas e o tabuleiro de Metrópole têm
## cores e fonte próprias, fixas, para que uma troca de tema nunca os redesenhe.
## As cores dos tabuleiros que ficaram como estavam (`BOARD_*`, `WATER*`) moram
## aqui, mas não mudam com a paleta.
##
## ## Destaque de botão: peso e cor são eixos separados
##
## O jeito errado de ganhar mais formas de destacar um botão é acrescentar cores;
## uma paleta com seis destaques não destaca nada. O que existe aqui são dois
## eixos que se combinam, e cada um responde uma pergunta diferente.
##
## **Peso** — quanta atenção o botão pede:
##
## | Peso      | Como é                                   | Quantos por tela |
## |-----------|------------------------------------------|------------------|
## | Placa     | preenchido, borda de baixo mais escura   | um, no máximo    |
## | Contorno  | vazado, borda e texto na cor             | poucos           |
## | Neutro    | tampo, texto de giz                      | à vontade        |
## | Tracejado | vazado, contorno de giz                  | à vontade        |
##
## **Cor** — o que o botão faz. Só três, e nenhuma é decorativa:
##
## - **Amarelo** (`ACCENT`): a ação da tela, e "é sua vez" no tabuleiro.
## - **Verde** (`SUCCESS`): confirmar, aceitar, começar.
## - **Vermelho** (`DANGER`): desfazer, desistir, sair — o que custa caro.
##
## Combinar os dois dá as variações: `PrimaryButton` é placa amarela,
## `AccentButton` é amarelo em contorno, `DangerButton` é vermelho em contorno,
## `GhostButton` é o tracejado. Um destaque novo é uma combinação, não uma cor nova.

## Lousa: o fundo de toda tela.
const BACKGROUND := Color("17211c")
## Tampo: painéis e folhas sobre a lousa.
const SURFACE := Color("1f2b25")
## Campos, segmentos inativos, o que está sobre um painel.
const SURFACE_HIGH := Color("2a3931")
## O que está por cima de tudo.
const SURFACE_TOP := Color("33443a")
## Fundo das bolachas de jogador e do placar do relógio.
const COASTER := Color("0e1511")
## Giz: texto principal.
const TEXT := Color("f1ede3")
## Texto secundário. 7,3:1 sobre a lousa — secundário não é ilegível.
const TEXT_DIM := Color("a4b0a7")
## Contorno de coisa tocável: 3:1 sobre a lousa, o mínimo para um contorno contar
## como fronteira de controle.
const LINE := Color("f1ede3", 0.45)
## Tracejado decorativo, separadores, contorno de painel.
const LINE_SOFT := Color("f1ede3", 0.22)
## Nome antigo do contorno decorativo, mantido para as telas que ainda o usam.
const BORDER := LINE_SOFT
## Amarelo de cadeira de plástico: a ação da tela e a vez.
const ACCENT := Color("f2c029")
const ACCENT_SOFT := Color("f2c029", 0.12)
## Tinta sobre o amarelo (10:1).
const ACCENT_INK := Color("1c1a10")
## A borda de baixo da placa amarela.
const ACCENT_EDGE := Color("b38c14")
## Dourado do chopp: o anel das bolachas.
const GOLD := Color("d9a441")
## Papel: comanda, escritura, dado.
const PAPER := Color("efe7d4")
const PAPER_INK := Color("221c13")
const DANGER := Color("e8694c")
const DANGER_SOFT := Color("e8694c", 0.18)
const SUCCESS := Color("7ec27f")
const SUCCESS_SOFT := Color("7ec27f", 0.16)

## Casas do último lance. Verde e não o amarelo: o amarelo quer dizer "é aqui que
## você age", e um lance que já aconteceu é exatamente o que não se pode mais
## mudar. Desenhado sobre o tabuleiro, que não muda com o tema — e por isso ele
## também não muda.
const LAST_MOVE := Color("6fbf73")

## Lance planejado para a vez seguinte. Azul frio, e deliberadamente não o
## amarelo: um plano é o contrário de "aja aqui" — é o que ainda não aconteceu.
const PREMOVE := Color("6f9fd8")

## Tabuleiros de xadrez, damas e Ludo. Ficam como estavam antes do Boteco.
const BOARD_LIGHT := Color("e9d8b8")
const BOARD_DARK := Color("8a5b3c")
const BOARD_FRAME := Color("241d18")

## Mar da batalha naval. As casas de um mar são todas iguais em função, e o
## contraste entre as duas é mínimo de propósito, só o bastante para a grade se
## contar com o olho. Fica como estava antes do Boteco.
const WATER := Color("223a4d")
const WATER_ALT := Color("27414f")
## Casco visível — o próprio, ou o inimigo depois de afundado.
const HULL := Color("8fa3b0")
## Tiro n'água: a casa está gasta, não vale mais nada.
const SPLASH := Color("6f8899")

const RADIUS := 10
## Folhas e cartões grandes.
const RADIUS_LARGE := 16
## A placa amarela.
const RADIUS_PLATE := 6
## Papel é quase quina viva.
const RADIUS_PAPER := 3
## Altura da borda de baixo da placa — e o quanto ela afunda ao ser tocada.
const PLATE_EDGE := 3
## Pílula: a linha da gaveta e o botão redondo da barra.
##
## Dois números exatos, e **não** um 999 de "arredonde tudo". O `StyleBoxFlat`
## aceita o exagero e degenera ao desenhar: o botão pressionado ganhava uma
## emenda atravessada no meio, porque as quatro curvas se encontram no centro
## quando o raio passa de metade da altura. Cada um é metade exata da altura do
## seu alvo — 44 do botão de ícone, 52 da linha da gaveta.
const RADIUS_ICON := 22
const RADIUS_PILL := 26

## Escala tipográfica, em pixels da base de 432 de largura.
const SIZE_DISPLAY_XL := 34
const SIZE_DISPLAY_L := 26
const SIZE_DISPLAY_M := 20
const SIZE_BUTTON := 19
const SIZE_BODY := 16
const SIZE_BODY_S := 14
const SIZE_CAPTION := 12
const SIZE_MONO_L := 34
const SIZE_MONO_M := 22
const SIZE_MONO_S := 13

## Recuo do conteúdo até a borda da tela. Em constante porque a barra superior e
## o corpo rolável **têm** de concordar: com números independentes, o botão da
## direita sobrava 12 px para fora da coluna dos cartões, e a tela ficava com
## duas margens diferentes uma em cima da outra.
const SCREEN_PAD := 20

## ## Espaçamento em grade de 4
##
## Todo respiro do app fora do tabuleiro é um múltiplo de 4, e vem daqui. Quatro
## degraus bastam: entre um rótulo e o campo dele (`SPACE_S`), entre dois itens
## de uma lista (`SPACE_M`), entre blocos de assunto diferente (`SPACE_L`), e
## entre o conteúdo e a borda da tela (`SPACE_XL`).
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 12
const SPACE_L := 16
const SPACE_XL := 24

## Véu por trás de uma camada modal. Escuro e não desfoque: desfocar custa uma
## passada de tela inteira num aparelho que ainda vai desenhar o tabuleiro.
const SCRIM := Color(0.0, 0.0, 0.0, 0.55)

## Altura da barra superior e da linha de navegação da gaveta. Os dois são alvo
## de toque, e 56 é o mínimo confortável com a densidade de um celular.
const BAR_HEIGHT := 64.0
const NAV_HEIGHT := 52.0

enum Role { BODY, DISPLAY, MONO }

const FONT_BODY := "res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"
const FONT_BODY_BOLD := "res://assets/fonts/AtkinsonHyperlegible-Bold.ttf"
const FONT_DISPLAY := "res://assets/fonts/BigShouldersDisplay-Variable.ttf"
const FONT_MONO := "res://assets/fonts/IBMPlexMono-Medium.ttf"
const FONT_MONO_BOLD := "res://assets/fonts/IBMPlexMono-SemiBold.ttf"


static var _theme: Theme = null
static var _fonts := {}
static var _legacy_fonts := {}


## Instância única. O tema é atribuído na raiz de cada cena e não na janela:
## `Window.theme` não desce para os Controls filhos, então uma variação de tipo
## declarada lá simplesmente não resolve — falha silenciosa, tudo continua com a
## aparência padrão da engine.
static func shared() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = font(400)
	theme.default_font_size = SIZE_BODY
	_style_buttons(theme)
	_style_labels(theme)
	_style_inputs(theme)
	_style_panels(theme)
	return theme


## A fonte de um papel num peso.
##
## Embarcadas, e não mais `SystemFont`: o tema tem três vozes — o letreiro (Big
## Shoulders), o texto que precisa ser lido longe do rosto (Atkinson Hyperlegible)
## e os números que precisam alinhar (IBM Plex Mono) —, e nenhuma delas existe
## garantida num aparelho. Corpo e mono são um arquivo por peso; o letreiro é um
## arquivo variável, com o peso escolhido no eixo `wght`.
##
## Cacheado por papel e peso porque `draw_string` recebe a fonte a cada quadro:
## uma instância nova por chamada nunca chega a carregar os glifos e desenha
## blocos em vez de texto.
static func font(weight: int, role := Role.BODY) -> Font:
	var key := int(role) * 1000 + weight
	if _fonts.has(key):
		return _fonts[key]
	var result: Font
	match role:
		Role.DISPLAY:
			var variation := FontVariation.new()
			variation.base_font = load(FONT_DISPLAY)
			var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
			variation.variation_opentype = {tag: clampi(weight, 100, 900)}
			result = variation
		Role.MONO:
			result = load(FONT_MONO_BOLD if weight >= 600 else FONT_MONO)
		_:
			result = load(FONT_BODY_BOLD if weight >= 600 else FONT_BODY)
	_fonts[key] = result
	return result


static func display(weight := 900) -> Font:
	return font(weight, Role.DISPLAY)


static func mono(weight := 600) -> Font:
	return font(weight, Role.MONO)


## A fonte do sistema que o app usava antes do tema Boteco.
##
## Só para desenho **protegido**: os números das cartas de Uno e os nomes das casas
## de Metrópole foram desenhados com ela, e trocar a família mudaria o desenho.
## Interface nova não usa isto.
static func legacy_font(weight: int) -> Font:
	if _legacy_fonts.has(weight):
		return _legacy_fonts[weight]
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Roboto", "Segoe UI", "Noto Sans", "DejaVu Sans", "Arial"])
	system.font_weight = weight
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	system.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_legacy_fonts[weight] = system
	return system


## Razão de contraste WCAG entre duas cores opacas. Uma cor com transparência
## precisa ser composta sobre o fundo antes (`fundo.blend(cor)`).
static func contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func box(fill: Color, radius: int = RADIUS, border_color: Color = Color(0, 0, 0, 0), border: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	if border > 0:
		style.set_border_width_all(border)
		style.border_color = border_color
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


## O contorno de giz, com as mesmas margens de conteúdo de `box()` — trocar um pelo
## outro num botão não pode mexer no tamanho dele.
static func dashed(fill: Color, border: Color, radius := RADIUS, width := 1.5) -> StyleBoxDashed:
	var style := StyleBoxDashed.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width = width
	style.corner_radius = radius
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


## A placa de plástico: preenchida, com a borda de baixo mais escura. Pressionada,
## a borda some e o texto desce a mesma altura — a placa afunda.
static func plate(fill: Color, edge: Color, pressed := false) -> StyleBoxFlat:
	var style := box(fill, RADIUS_PLATE)
	if pressed:
		style.content_margin_top += PLATE_EDGE
	else:
		style.border_width_bottom = PLATE_EDGE
		style.border_color = edge
	return style


static func _style_buttons(theme: Theme) -> void:
	theme.set_font("font", "Button", display(900))
	theme.set_font_size("font_size", "Button", SIZE_BUTTON)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.45))
	theme.set_stylebox("normal", "Button", box(SURFACE_HIGH, RADIUS))
	theme.set_stylebox("hover", "Button", box(SURFACE_HIGH.lightened(0.06), RADIUS))
	theme.set_stylebox("pressed", "Button", box(ACCENT_SOFT, RADIUS, ACCENT, 2))
	theme.set_stylebox("disabled", "Button", box(SURFACE, RADIUS))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), RADIUS, ACCENT, 2))

	# A placa amarela: a ação da tela. Existe uma por tela, no máximo.
	theme.set_type_variation("PrimaryButton", "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "PrimaryButton", ACCENT_INK)
	theme.set_color("font_disabled_color", "PrimaryButton", Color(ACCENT_INK, 0.6))
	theme.set_stylebox("normal", "PrimaryButton", plate(ACCENT, ACCENT_EDGE))
	theme.set_stylebox("hover", "PrimaryButton", plate(ACCENT.lightened(0.08), ACCENT_EDGE))
	theme.set_stylebox("pressed", "PrimaryButton", plate(ACCENT.darkened(0.08), ACCENT_EDGE, true))
	theme.set_stylebox("disabled", "PrimaryButton", plate(Color(ACCENT, 0.35), Color(ACCENT_EDGE, 0.35)))

	# Escolha dentro de um grupo (o ritmo do relógio). Solta, é um tracejado; a
	# marcada se distingue por contorno amarelo, nunca por preenchimento cheio: o
	# amarelo sólido é a ação principal da tela, e existe uma só.
	theme.set_type_variation("ChipButton", "Button")
	theme.set_color("font_color", "ChipButton", TEXT_DIM)
	theme.set_color("font_hover_color", "ChipButton", TEXT)
	theme.set_color("font_pressed_color", "ChipButton", ACCENT)
	theme.set_stylebox("normal", "ChipButton", dashed(Color(0, 0, 0, 0), LINE))
	theme.set_stylebox("hover", "ChipButton", dashed(SURFACE, LINE))
	theme.set_stylebox("pressed", "ChipButton", box(ACCENT_SOFT, RADIUS, ACCENT, 2))

	theme.set_type_variation("ChipSelected", "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "ChipSelected", ACCENT)
	for state: String in ["normal", "hover", "pressed"]:
		theme.set_stylebox(state, "ChipSelected", box(ACCENT_SOFT, RADIUS, ACCENT, 2))

	_outlined(theme, "AccentButton", ACCENT, ACCENT_SOFT)
	_outlined(theme, "SuccessButton", SUCCESS, SUCCESS_SOFT)
	# O que custa caro: desistir, sair no meio, apagar. Em contorno e não cheio —
	# vermelho preenchido num menu grita antes de o jogador ter feito nada errado.
	_outlined(theme, "DangerButton", DANGER, DANGER_SOFT)

	# Confirmar e começar, quando a saída da mesma tela já é amarela.
	theme.set_type_variation("SuccessSolidButton", "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "SuccessSolidButton", ACCENT_INK)
	var success_edge := SUCCESS.darkened(0.35)
	theme.set_stylebox("normal", "SuccessSolidButton", plate(SUCCESS, success_edge))
	theme.set_stylebox("hover", "SuccessSolidButton", plate(SUCCESS.lightened(0.08), success_edge))
	theme.set_stylebox("pressed", "SuccessSolidButton", plate(SUCCESS.darkened(0.08), success_edge, true))

	# Linha da gaveta de navegação: pílula da largura toda, texto à esquerda.
	theme.set_type_variation("NavItem", "Button")
	theme.set_color("font_color", "NavItem", TEXT_DIM)
	theme.set_color("font_hover_color", "NavItem", TEXT)
	theme.set_stylebox("normal", "NavItem", box(Color(0, 0, 0, 0), RADIUS_PILL))
	theme.set_stylebox("hover", "NavItem", box(SURFACE_HIGH, RADIUS_PILL))
	theme.set_stylebox("pressed", "NavItem", box(ACCENT_SOFT, RADIUS_PILL))
	theme.set_type_variation("NavItemSelected", "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "NavItemSelected", ACCENT)
	for state: String in ["normal", "hover", "pressed"]:
		theme.set_stylebox(state, "NavItemSelected", box(ACCENT_SOFT, RADIUS_PILL))

	# Sem fundo nenhum: `IconButton` desenha o próprio círculo, porque um
	# retângulo arredondado de raio igual à metade da largura deixa uma costura no
	# meio. O que existisse aqui apareceria **atrás** do círculo desenhado.
	theme.set_type_variation("IconButton", "Button")
	theme.set_color("font_color", "IconButton", TEXT_DIM)
	theme.set_color("font_hover_color", "IconButton", TEXT)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "IconButton", StyleBoxEmpty.new())

	# Ação secundária: o contorno de giz, sem preenchimento, para não competir com
	# a placa.
	theme.set_type_variation("GhostButton", "Button")
	theme.set_color("font_color", "GhostButton", TEXT)
	theme.set_color("font_hover_color", "GhostButton", TEXT)
	theme.set_color("font_pressed_color", "GhostButton", ACCENT)
	theme.set_stylebox("normal", "GhostButton", dashed(Color(0, 0, 0, 0), LINE))
	theme.set_stylebox("hover", "GhostButton", dashed(Color(TEXT, 0.05), LINE))
	theme.set_stylebox("pressed", "GhostButton", dashed(ACCENT_SOFT, ACCENT))

	# Segmentos do `SegmentedControl`: o marcado é o único preenchido.
	theme.set_type_variation("Segment", "Button")
	theme.set_font_size("font_size", "Segment", SIZE_DISPLAY_M - 2)
	theme.set_color("font_color", "Segment", TEXT_DIM)
	theme.set_color("font_hover_color", "Segment", TEXT)
	theme.set_color("font_pressed_color", "Segment", TEXT)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		theme.set_stylebox(state, "Segment", _segment(Color(0, 0, 0, 0)))
	theme.set_type_variation("SegmentSelected", "Button")
	theme.set_font_size("font_size", "SegmentSelected", SIZE_DISPLAY_M - 2)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "SegmentSelected", ACCENT_INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		theme.set_stylebox(state, "SegmentSelected", _segment(ACCENT))


static func _segment(fill: Color) -> StyleBoxFlat:
	var style := box(fill, RADIUS - 3)
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style


## Botão de contorno numa cor: fundo vazado, borda e texto na cor, e o suave
## como preenchimento só no toque. É o peso do meio — visível sem gritar — e
## sai daqui em vez de repetido três vezes, porque o que distingue um do outro
## é a cor e mais nada.
static func _outlined(theme: Theme, name: String, tint: Color, soft: Color) -> void:
	theme.set_type_variation(name, "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, name, tint)
	theme.set_stylebox("normal", name, box(Color(0, 0, 0, 0), RADIUS, tint, 2))
	theme.set_stylebox("hover", name, box(soft, RADIUS, tint, 2))
	theme.set_stylebox("pressed", name, box(soft, RADIUS, tint, 3))


static func _style_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT)
	_label(theme, "Display", display(900), SIZE_DISPLAY_XL, TEXT)
	_label(theme, "Title", display(900), SIZE_DISPLAY_L, TEXT)
	# Saudação da barra superior: o endereço da tela, em letreiro.
	_label(theme, "Greeting", display(900), SIZE_DISPLAY_L - 2, TEXT)
	# Título de seção ("Favoritos", "Tabuleiro"). Na cor do texto, ao contrário do
	# `Caption`, que é apagado: `Caption` rotula um controle, e isto **divide** o
	# conteúdo. Um divisor apagado é um divisor que não divide.
	_label(theme, "SectionHeader", display(900), SIZE_DISPLAY_M, TEXT)
	_label(theme, "Subtitle", font(400), SIZE_BODY, TEXT_DIM)
	_label(theme, "Caption", font(700), SIZE_CAPTION, TEXT_DIM)
	# Código de pareamento: feito para ser lido de uma tela e digitado noutra, e
	# em mono para o "0" e o "O" não se confundirem.
	_label(theme, "PairingCode", mono(600), SIZE_MONO_L, ACCENT)
	_label(theme, "Mono", mono(600), SIZE_MONO_M, TEXT)


static func _label(theme: Theme, name: String, face: Font, font_size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, face)
	theme.set_font_size("font_size", name, font_size)
	theme.set_color("font_color", name, color)


static func _style_inputs(theme: Theme) -> void:
	theme.set_font("font", "LineEdit", font(700))
	theme.set_font_size("font_size", "LineEdit", SIZE_DISPLAY_M)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.7))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_stylebox("normal", "LineEdit", box(SURFACE, RADIUS, LINE, 1))
	theme.set_stylebox("focus", "LineEdit", box(SURFACE, RADIUS, ACCENT, 2))

	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_font_size("font_size", "ItemList", SIZE_BODY)
	theme.set_stylebox("panel", "ItemList", box(SURFACE, RADIUS, LINE_SOFT, 1))
	theme.set_stylebox("selected", "ItemList", box(ACCENT_SOFT, RADIUS))
	theme.set_stylebox("selected_focus", "ItemList", box(ACCENT_SOFT, RADIUS))
	theme.set_stylebox("hovered", "ItemList", box(Color(TEXT, 0.05), RADIUS))
	theme.set_constant("v_separation", "ItemList", 6)


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", box(SURFACE, RADIUS_LARGE))
	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", box(SURFACE, RADIUS_LARGE))
	theme.set_type_variation("QuietCard", "PanelContainer")
	theme.set_stylebox("panel", "QuietCard", dashed(Color(0, 0, 0, 0), LINE_SOFT, RADIUS_LARGE))
