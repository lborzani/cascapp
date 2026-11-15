class_name AppTheme
extends RefCounted

## Tema construído em código e aplicado na raiz de cada cena. Em código e não num
## `.tres` porque uma paleta é um conjunto de decisões relacionadas: aqui elas
## ficam nomeadas, com o porquê ao lado.
##
## ## A direção: Mesa Viva
##
## Noite de jogo. Fundo violeta bem escuro, superfícies em degraus do mesmo
## violeta, e cor de verdade só em três lugares:
##
## - **Limão** (`ACCENT`): a ação da tela e "é sua vez". Uma cor de ação só
##   significa que ela sempre quer dizer a mesma coisa.
## - **Coral** (`DANGER`): xeque, acerto, o que custa caro.
## - **A cor do jogo** (`GAME_COLORS`): cada jogo tem a sua, no bloco do menu e
##   no topo das telas que são dele.
##
## Nada é tracejado e nada é papel: o que separa uma coisa da outra é o degrau
## de superfície. O botão principal tem uma borda de baixo mais escura e afunda
## no toque (`plate`); o movimento mora em `Motion`.
##
## O que é **do jogo** não lê daqui: peças, cartas e o tabuleiro de Metrópole têm
## cores e fonte próprias, fixas. As cores dos tabuleiros (`BOARD_*`, `WATER*`)
## moram aqui, mas não mudam com a paleta.
##
## ## Destaque de botão: peso e cor são eixos separados
##
## **Peso** — quanta atenção o botão pede: placa (preenchido, borda de baixo; um
## por tela), contorno (borda e texto na cor; poucos) e neutro (um degrau de
## superfície acima; à vontade).
##
## **Cor** — o que o botão faz: limão age, verde confirma, coral desfaz ou sai.
## `PrimaryButton` é placa limão, `AccentButton` é limão em contorno,
## `DangerButton` é coral em contorno, `GhostButton` é o neutro.

## Noite: o fundo de toda tela.
const BACKGROUND := Color("15122b")
## Mesa: painéis e folhas sobre a noite.
const SURFACE := Color("211c40")
## Campos, segmentos inativos, o que está sobre um painel.
const SURFACE_HIGH := Color("2d2757")
## O que está por cima de tudo.
const SURFACE_TOP := Color("3d3670")
## Fundo das bolachas de jogador e do placar do relógio.
const COASTER := Color("0b0918")
const TEXT := Color("f7f5ff")
## Texto secundário. 8,5:1 sobre a noite — secundário não é ilegível.
const TEXT_DIM := Color("b4aedb")
## Contorno de coisa tocável: 3:1 sobre a noite, o mínimo para um contorno contar
## como fronteira de controle.
const LINE := Color("f7f5ff", 0.45)
## Separadores e contorno de painel.
const LINE_SOFT := Color("f7f5ff", 0.14)
## Nome antigo do contorno decorativo, mantido para as telas que ainda o usam.
const BORDER := LINE_SOFT
## Limão: a ação da tela e a vez.
const ACCENT := Color("c8f53c")
const ACCENT_SOFT := Color("c8f53c", 0.12)
## Tinta sobre o limão (14:1).
const ACCENT_INK := Color("15122b")
## A borda de baixo da placa limão.
const ACCENT_EDGE := Color("8db322")
## O anel das bolachas de quem não está na vez. O nome é do tema antigo (era o
## dourado do chopp) e fica para não renomear em vinte arquivos.
const GOLD := Color("3d3670")
## O único claro da tela: escritura da Metrópole, dado, cartão de destaque.
const PAPER := Color("f7f5ff")
const PAPER_INK := Color("15122b")
const DANGER := Color("ff5c7a")
const DANGER_SOFT := Color("ff5c7a", 0.18)
## Coral claro, para texto de ação que custa caro sobre a mesa ("Desistir"): o
## coral cheio é alerta, e um botão que só pode ser apertado não é alerta.
const DANGER_LIGHT := Color("ff8fa3")
const SUCCESS := Color("59d36b")
const SUCCESS_SOFT := Color("59d36b", 0.16)

## A cor de cada jogo, pela id do catálogo (`Game.CHESS` etc.). Em texto e não
## pelas constantes de `Game` porque o tema não conhece autoload nenhum.
const GAME_COLORS := {
	"chess": Color("9b7bff"),
	"checkers": Color("ff8a3d"),
	"battleship": Color("39c6ff"),
	"ludo": Color("ffc229"),
	"uno": Color("ff4d7d"),
	"monopoly": Color("2ed3b7"),
	"pool": Color("59d36b"),
}

## Casas do último lance, sólidas e em dois tons como no protótipo: um limão
## claro na casa clara e um oliva vivo na escura. Vizinhos do limão sem ser ele —
## o limão cheio quer dizer "é aqui que você age", e um lance que já aconteceu é
## o que não se pode mais mudar. Translúcido sobre o violeta, virava cinza.
const LAST_MOVE := Color("ddf08a")
const LAST_MOVE_DARK := Color("a9c94a")

## Lance planejado para a vez seguinte. Ciano, e deliberadamente não o limão: um
## plano é o contrário de "aja aqui" — é o que ainda não aconteceu. Ciano e não
## o azul de antes, que sumia na casa violeta.
const PREMOVE := Color("39c6ff")

## Tabuleiros de xadrez, damas e Ludo: violeta, da mesma família do fundo. As
## peças continuam as de sempre — o contorno escuro delas segura a leitura nas
## duas casas.
const BOARD_LIGHT := Color("e9e4ff")
const BOARD_DARK := Color("8672e0")
const BOARD_FRAME := Color("2d2757")

## Mar da batalha naval. As casas de um mar são todas iguais em função, e o
## contraste entre as duas é mínimo de propósito, só o bastante para a grade se
## contar com o olho. Fica como estava antes do tema.
const WATER := Color("1b6393")
const WATER_ALT := Color("17557f")
## Casco visível — o próprio, ou o inimigo depois de afundado.
const HULL := Color("f7f5ff")
## Tiro n'água: a casa está gasta, não vale mais nada.
const SPLASH := Color("f7f5ff")

const RADIUS := 14
## Folhas e cartões grandes.
const RADIUS_LARGE := 20
## A placa do botão principal.
const RADIUS_PLATE := 16
## Cartão claro.
const RADIUS_PAPER := 16
## Altura da borda de baixo da placa — e o quanto ela afunda ao ser tocada.
const PLATE_EDGE := 4
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
const SIZE_DISPLAY_XL := 30
const SIZE_DISPLAY_L := 24
const SIZE_DISPLAY_M := 18
const SIZE_BUTTON := 17
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

const FONT_BODY := "res://assets/fonts/Nunito-Variable.ttf"
const FONT_DISPLAY := "res://assets/fonts/Fredoka-Variable.ttf"
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
## Embarcadas, e não `SystemFont`: o tema tem três vozes — o letreiro redondo
## (Fredoka), o corpo (Nunito) e os números que precisam alinhar (IBM Plex Mono)
## —, e nenhuma delas existe garantida num aparelho. Letreiro e corpo são
## arquivos variáveis, com o peso escolhido no eixo `wght` dentro do que cada
## família tem; a mono é um arquivo por peso.
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
		# A Fredoka vai de 300 a 700: quem pede 900 (o peso do letreiro antigo)
		# recebe o mais pesado que existe.
		Role.DISPLAY:
			result = _variable(FONT_DISPLAY, clampi(weight, 300, 700))
		Role.MONO:
			result = load(FONT_MONO_BOLD if weight >= 600 else FONT_MONO)
		# Corpo nunca abaixo de 600: a Nunito fina some sobre fundo escuro.
		_:
			result = _variable(FONT_BODY, clampi(weight + 200, 600, 900))
	_fonts[key] = result
	return result


static func _variable(path: String, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = load(path)
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	variation.variation_opentype = {tag: weight}
	return variation


static func display(weight := 900) -> Font:
	return font(weight, Role.DISPLAY)


static func mono(weight := 600) -> Font:
	return font(weight, Role.MONO)


## A fonte do sistema que o app usava antes de ter fontes embarcadas.
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


## Caixa com contorno fino, para o que é secundário sobre a noite. Mesmas margens
## de conteúdo de `box()` — trocar um pelo outro num botão não mexe no tamanho.
static func framed(fill: Color, border: Color, radius := RADIUS) -> StyleBoxFlat:
	return box(fill, radius, border, 2)


## A placa: preenchida, com a borda de baixo mais escura. Pressionada,
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

	# A placa limão: a ação da tela. Existe uma por tela, no máximo.
	theme.set_type_variation("PrimaryButton", "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "PrimaryButton", ACCENT_INK)
	theme.set_color("font_disabled_color", "PrimaryButton", TEXT_DIM)
	theme.set_stylebox("normal", "PrimaryButton", plate(ACCENT, ACCENT_EDGE))
	theme.set_stylebox("hover", "PrimaryButton", plate(ACCENT.lightened(0.08), ACCENT_EDGE))
	theme.set_stylebox("pressed", "PrimaryButton", plate(ACCENT.darkened(0.08), ACCENT_EDGE, true))
	# Desligado vira placa lilás, como no protótipo: limão apagado ainda lia como
	# convite.
	theme.set_stylebox("disabled", "PrimaryButton", plate(SURFACE_TOP, SURFACE_TOP))

	# Escolha dentro de um grupo (o ritmo do relógio). A marcada é clara com tinta
	# escura, e não limão: o limão cheio é a ação principal da tela, e existe uma só.
	theme.set_type_variation("ChipButton", "Button")
	theme.set_color("font_color", "ChipButton", TEXT_DIM)
	theme.set_color("font_hover_color", "ChipButton", TEXT)
	theme.set_color("font_pressed_color", "ChipButton", TEXT)
	theme.set_stylebox("normal", "ChipButton", box(SURFACE_HIGH, RADIUS))
	theme.set_stylebox("hover", "ChipButton", box(SURFACE_TOP, RADIUS))
	theme.set_stylebox("pressed", "ChipButton", box(SURFACE_TOP, RADIUS))

	theme.set_type_variation("ChipSelected", "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "ChipSelected", PAPER_INK)
	for state: String in ["normal", "hover", "pressed"]:
		theme.set_stylebox(state, "ChipSelected", box(PAPER, RADIUS))

	_outlined(theme, "AccentButton", ACCENT, ACCENT_SOFT)
	# O que custa caro: desistir, sair no meio, apagar. Em contorno e não cheio —
	# vermelho preenchido num menu grita antes de o jogador ter feito nada errado.
	_outlined(theme, "DangerButton", DANGER, DANGER_SOFT)

	# Confirmar e começar, quando a saída da mesma tela já é limão.
	theme.set_type_variation("SuccessSolidButton", "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "SuccessSolidButton", ACCENT_INK)
	var success_edge := SUCCESS.darkened(0.35)
	theme.set_stylebox("normal", "SuccessSolidButton", plate(SUCCESS, success_edge))
	theme.set_stylebox("hover", "SuccessSolidButton", plate(SUCCESS.lightened(0.08), success_edge))
	theme.set_stylebox("pressed", "SuccessSolidButton", plate(SUCCESS.darkened(0.08), success_edge, true))

	# Linha de ajuste (os interruptores da aba Você): pílula da largura toda, texto à
	# esquerda.
	theme.set_type_variation("NavItem", "Button")
	theme.set_color("font_color", "NavItem", TEXT_DIM)
	theme.set_color("font_hover_color", "NavItem", TEXT)
	theme.set_stylebox("normal", "NavItem", box(Color(0, 0, 0, 0), RADIUS_PILL))
	theme.set_stylebox("hover", "NavItem", box(SURFACE_HIGH, RADIUS_PILL))
	theme.set_stylebox("pressed", "NavItem", box(ACCENT_SOFT, RADIUS_PILL))

	# Sem fundo nenhum: `IconButton` desenha o próprio círculo, porque um
	# retângulo arredondado de raio igual à metade da largura deixa uma costura no
	# meio. O que existisse aqui apareceria **atrás** do círculo desenhado.
	theme.set_type_variation("IconButton", "Button")
	theme.set_color("font_color", "IconButton", TEXT_DIM)
	theme.set_color("font_hover_color", "IconButton", TEXT)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "IconButton", StyleBoxEmpty.new())

	# Ação secundária: um degrau de superfície, sem cor, para não competir com a
	# placa.
	theme.set_type_variation("GhostButton", "Button")
	theme.set_color("font_color", "GhostButton", TEXT)
	theme.set_color("font_hover_color", "GhostButton", TEXT)
	theme.set_color("font_pressed_color", "GhostButton", TEXT)
	theme.set_stylebox("normal", "GhostButton", box(SURFACE_HIGH, RADIUS))
	theme.set_stylebox("hover", "GhostButton", box(SURFACE_TOP, RADIUS))
	theme.set_stylebox("pressed", "GhostButton", box(SURFACE_TOP, RADIUS))

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
	# Frase de ajuda embaixo de um controle ("Nas partidas você aparece como…").
	# Era `Caption`, e `Caption` é rótulo curto em 12 — uma frase inteira nesse
	# tamanho é a frase que ninguém lê.
	_label(theme, "Hint", font(400), SIZE_BODY_S, TEXT_DIM)
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
	theme.set_constant("v_separation", "ItemList", SPACE_S)


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", box(SURFACE, RADIUS_LARGE))
	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", box(SURFACE, RADIUS_LARGE))
	theme.set_type_variation("QuietCard", "PanelContainer")
	theme.set_stylebox("panel", "QuietCard", framed(Color(0, 0, 0, 0), LINE_SOFT, RADIUS_LARGE))
