class_name AppTheme
extends RefCounted

## Tema construído em código e aplicado na raiz da janela, de onde desce para
## todas as cenas. Em código e não num `.tres` porque uma paleta é um conjunto de
## decisões relacionadas: aqui elas ficam nomeadas, com o porquê ao lado, em vez
## de espalhadas por centenas de linhas de propriedades serializadas.
##
## A direção é tátil, de tabuleiro de madeira: fundo quase preto e quente, e um
## latão como única cor de destaque. Uma cor de destaque só significa que ela
## sempre quer dizer a mesma coisa — "é aqui que você age, é sua vez".
##
## ## Destaque de botão: peso e cor são eixos separados
##
## O jeito errado de ganhar mais formas de destacar um botão é acrescentar cores;
## uma paleta com seis destaques não destaca nada. O que existe aqui são dois
## eixos que se combinam, e cada um responde uma pergunta diferente.
##
## **Peso** — quanta atenção o botão pede:
##
## | Peso     | Como é                          | Quantos por tela |
## |----------|---------------------------------|------------------|
## | Cheio    | preenchido, texto no fundo      | um, no máximo    |
## | Contorno | fundo vazado, borda e texto na cor | poucos        |
## | Neutro   | superfície cinza, texto claro   | à vontade        |
## | Fantasma | vazado, texto apagado           | à vontade        |
##
## **Cor** — o que o botão faz. Só três, e nenhuma é decorativa:
##
## - **Latão** (`ACCENT`): a ação da tela. É a mesma cor de "é sua vez" no
##   tabuleiro, e continua querendo dizer "aja aqui".
## - **Verde** (`SUCCESS`): confirmar, aceitar, começar. É a cor que o tabuleiro
##   já usa para o que aconteceu.
## - **Vermelho** (`DANGER`): desfazer, desistir, sair — o que custa caro.
##
## Combinar os dois dá as variações: `PrimaryButton` é latão cheio,
## `AccentButton` é latão em contorno, `DangerButton` é vermelho em contorno, e
## assim por diante. Um destaque novo é uma combinação, não uma cor nova.

const BACKGROUND := Color("13100e")
const SURFACE := Color("1e1a17")
const SURFACE_HIGH := Color("2a2421")
const BORDER := Color("3a322c")
const ACCENT := Color("d9a441")
const ACCENT_SOFT := Color("d9a441", 0.16)
const TEXT := Color("f2eae0")
const TEXT_DIM := Color("a2968a")
const DANGER := Color("e05a4d")
const DANGER_SOFT := Color("e05a4d", 0.18)
const SUCCESS := Color("7ec27f")
const SUCCESS_SOFT := Color("7ec27f", 0.16)

## Casas do último lance. Verde e não o latão: o latão quer dizer "é aqui que
## você age", e um lance que já aconteceu é exatamente o que não se pode mais
## mudar. Também precisa se separar da madeira clara do tabuleiro, que é onde o
## latão desaparecia.
const LAST_MOVE := Color("6fbf73")

## Lance planejado para a vez seguinte. Azul frio, e deliberadamente não o
## latão: o latão quer dizer "é sua vez, aja aqui", e um plano é o contrário
## disso — é o que ainda não aconteceu e pode não acontecer.
const PREMOVE := Color("6f9fd8")

const BOARD_LIGHT := Color("e9d8b8")
const BOARD_DARK := Color("8a5b3c")
const BOARD_FRAME := Color("241d18")

## Mar da batalha naval. A madeira do xadrez não serve aqui: as casas de um mar
## são todas iguais em função — não existe casa clara e casa escura com regra
## diferente — e o xadrezado sugeriria uma que não há. O contraste entre as duas
## é mínimo de propósito, só o bastante para a grade se contar com o olho.
##
## Azul frio também porque o que vai por cima é quente: o acerto é vermelho e a
## mira é latão. Sobre madeira os dois brigavam com o fundo.
const WATER := Color("223a4d")
const WATER_ALT := Color("27414f")
## Casco visível — o próprio, ou o inimigo depois de afundado.
const HULL := Color("8fa3b0")
## Tiro n'água: a casa está gasta, não vale mais nada.
const SPLASH := Color("6f8899")

const RADIUS := 14
const RADIUS_LARGE := 22
## Pílula: a linha da gaveta e o botão redondo da barra.
##
## Dois números exatos, e **não** um 999 de "arredonde tudo". O `StyleBoxFlat`
## aceita o exagero e degenera ao desenhar: o botão pressionado ganhava uma
## emenda atravessada no meio, porque as quatro curvas se encontram no centro
## quando o raio passa de metade da altura.
##
## Cada um é metade exata da altura do seu alvo — 44 do botão de ícone, 52 da
## linha da gaveta. Metade exata é o maior valor que ainda descreve um arco, e é
## o que dá a pílula sem artefato.
const RADIUS_ICON := 22
const RADIUS_PILL := 26

## Recuo do conteúdo até a borda da tela. Em constante porque a barra superior e
## o corpo rolável **têm** de concordar: com números independentes, o botão da
## direita sobrava 12 px para fora da coluna dos cartões, e a tela ficava com
## duas margens diferentes uma em cima da outra.
const SCREEN_PAD := 20

## ## Espaçamento em grade de 4
##
## Todo respiro do app fora do tabuleiro é um múltiplo de 4, e vem daqui. Antes
## eram números soltos nas cenas — 20 aqui, 18 ali, 12 no vizinho —, e o efeito
## de somar uma tela por vez é uma pilha de margens que ninguém escolheu junto.
##
## Quatro degraus bastam: entre um rótulo e o campo dele (`SPACE_S`), entre dois
## itens de uma lista (`SPACE_M`), entre blocos de assunto diferente (`SPACE_L`),
## e entre o conteúdo e a borda da tela (`SPACE_XL`).
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 12
const SPACE_L := 16
const SPACE_XL := 24

## ## Superfícies por nível
##
## Quanto mais perto do jogador, mais clara a superfície — é como a profundidade
## aparece num tema escuro, onde sombra não se enxerga. `BACKGROUND` é a tela,
## `SURFACE` é um cartão nela, `SURFACE_HIGH` é o que está por cima de um cartão
## (um painel modal, uma gaveta), e `SURFACE_TOP` é o que está por cima de tudo.
##
## O passo é pequeno de propósito: três níveis separados por muito claro viram um
## degrau visível a cada elemento, e a tela passa a parecer remendada.
const SURFACE_TOP := Color("332c28")

## Véu por trás de uma camada modal. Escuro e não desfoque: desfocar custa uma
## passada de tela inteira num aparelho que ainda vai desenhar o tabuleiro.
const SCRIM := Color(0.0, 0.0, 0.0, 0.55)

## Altura da barra superior e da linha de navegação da gaveta. Os dois são alvo
## de toque, e 56 é o mínimo confortável com a densidade de um celular.
const BAR_HEIGHT := 64.0
const NAV_HEIGHT := 52.0


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
	theme.default_font_size = 17

	_style_buttons(theme)
	_style_labels(theme)
	_style_inputs(theme)
	_style_panels(theme)
	return theme


enum Role { BODY, DISPLAY, MONO }

const FONT_BODY := "res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"
const FONT_BODY_BOLD := "res://assets/fonts/AtkinsonHyperlegible-Bold.ttf"
const FONT_DISPLAY := "res://assets/fonts/BigShouldersDisplay-Variable.ttf"
const FONT_MONO := "res://assets/fonts/IBMPlexMono-Medium.ttf"
const FONT_MONO_BOLD := "res://assets/fonts/IBMPlexMono-SemiBold.ttf"


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


static func _style_buttons(theme: Theme) -> void:
	theme.set_font("font", "Button", font(600))
	theme.set_font_size("font_size", "Button", 19)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", BACKGROUND)
	theme.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.45))
	theme.set_stylebox("normal", "Button", box(SURFACE_HIGH, RADIUS, BORDER, 1))
	theme.set_stylebox("hover", "Button", box(SURFACE_HIGH.lightened(0.06), RADIUS, ACCENT_SOFT, 1))
	theme.set_stylebox("pressed", "Button", box(ACCENT, RADIUS))
	theme.set_stylebox("disabled", "Button", box(SURFACE, RADIUS, BORDER, 1))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), RADIUS, ACCENT_SOFT, 1))

	# Ação principal da tela. Existe uma por tela, no máximo.
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_color("font_color", "PrimaryButton", BACKGROUND)
	theme.set_color("font_hover_color", "PrimaryButton", BACKGROUND)
	theme.set_color("font_pressed_color", "PrimaryButton", BACKGROUND)
	theme.set_stylebox("normal", "PrimaryButton", box(ACCENT, RADIUS))
	theme.set_stylebox("hover", "PrimaryButton", box(ACCENT.lightened(0.12), RADIUS))
	theme.set_stylebox("pressed", "PrimaryButton", box(ACCENT.darkened(0.15), RADIUS))

	# Escolha dentro de um grupo (o ritmo do relógio). A opção marcada se
	# distingue por contorno e cor de texto, nunca por preenchimento: o latão
	# sólido é a ação principal da tela, e existe uma só — duas competiriam, e o
	# olho iria para a errada.
	theme.set_type_variation("ChipButton", "Button")
	theme.set_color("font_color", "ChipButton", TEXT_DIM)
	theme.set_color("font_hover_color", "ChipButton", TEXT)
	theme.set_stylebox("normal", "ChipButton", box(Color(0, 0, 0, 0), RADIUS, BORDER, 1))
	theme.set_stylebox("hover", "ChipButton", box(SURFACE, RADIUS, BORDER, 1))

	# O estado pressionado dos dois é escrito, e não herdado do `Button` comum: lá
	# ele é latão **cheio**, que é o peso da ação principal da tela. Um chip que
	# pisca sólido ao ser tocado promete, por um instante, ser o botão mais
	# importante da tela — e o olho vai atrás.
	theme.set_stylebox("pressed", "ChipButton", box(ACCENT_SOFT, RADIUS, ACCENT, 1))
	theme.set_color("font_pressed_color", "ChipButton", ACCENT)

	theme.set_type_variation("ChipSelected", "Button")
	theme.set_color("font_color", "ChipSelected", ACCENT)
	theme.set_color("font_hover_color", "ChipSelected", ACCENT)
	theme.set_color("font_pressed_color", "ChipSelected", ACCENT)
	theme.set_stylebox("normal", "ChipSelected", box(ACCENT_SOFT, RADIUS, ACCENT, 1))
	theme.set_stylebox("hover", "ChipSelected", box(ACCENT_SOFT, RADIUS, ACCENT, 1))
	theme.set_stylebox("pressed", "ChipSelected", box(ACCENT_SOFT, RADIUS, ACCENT, 1))

	# Segundo lugar do latão: mesma cor da ação principal, um peso abaixo. É o que
	# faltava quando uma tela tem duas saídas boas e uma delas é a mais provável —
	# antes as duas ficavam neutras e a hierarquia sumia.
	_outlined(theme, "AccentButton", ACCENT, ACCENT_SOFT)
	# Confirmar e começar. Verde cheio existe porque num painel de confirmação a
	# ação de sair é latão e a de confirmar precisa de outra cor, senão as duas
	# disputam.
	_outlined(theme, "SuccessButton", SUCCESS, SUCCESS_SOFT)
	theme.set_type_variation("SuccessSolidButton", "Button")
	theme.set_color("font_color", "SuccessSolidButton", BACKGROUND)
	theme.set_color("font_hover_color", "SuccessSolidButton", BACKGROUND)
	theme.set_color("font_pressed_color", "SuccessSolidButton", BACKGROUND)
	theme.set_stylebox("normal", "SuccessSolidButton", box(SUCCESS, RADIUS))
	theme.set_stylebox("hover", "SuccessSolidButton", box(SUCCESS.lightened(0.12), RADIUS))
	theme.set_stylebox("pressed", "SuccessSolidButton", box(SUCCESS.darkened(0.15), RADIUS))
	# O que custa caro: desistir, sair no meio, apagar. Em contorno e não cheio —
	# vermelho preenchido num menu grita antes de o jogador ter feito nada errado.
	_outlined(theme, "DangerButton", DANGER, DANGER_SOFT)

	# Linha da gaveta de navegação: pílula da largura toda, texto à esquerda. O
	# selecionado é o mesmo par latão-suave da escolha marcada em qualquer outro
	# lugar do app — a gaveta não inventa um vocabulário só dela.
	theme.set_type_variation("NavItem", "Button")
	theme.set_color("font_color", "NavItem", TEXT_DIM)
	theme.set_color("font_hover_color", "NavItem", TEXT)
	theme.set_stylebox("normal", "NavItem", box(Color(0, 0, 0, 0), RADIUS_PILL))
	theme.set_stylebox("hover", "NavItem", box(SURFACE_HIGH, RADIUS_PILL))
	theme.set_stylebox("pressed", "NavItem", box(ACCENT_SOFT, RADIUS_PILL))

	theme.set_type_variation("NavItemSelected", "Button")
	theme.set_color("font_color", "NavItemSelected", ACCENT)
	theme.set_color("font_hover_color", "NavItemSelected", ACCENT)
	theme.set_color("font_pressed_color", "NavItemSelected", ACCENT)
	theme.set_stylebox("normal", "NavItemSelected", box(ACCENT_SOFT, RADIUS_PILL))
	theme.set_stylebox("hover", "NavItemSelected", box(ACCENT_SOFT, RADIUS_PILL))
	theme.set_stylebox("pressed", "NavItemSelected", box(ACCENT_SOFT, RADIUS_PILL))

	# Botão redondo de ícone da barra superior. Sem preenchimento: a barra já é
	# uma superfície, e um círculo cheio nela seria a ação principal da tela —
	# que nunca é "abrir ajustes".
	# Sem fundo nenhum: `IconButton` desenha o próprio círculo, porque um
	# retângulo arredondado de raio igual à metade da largura deixa uma costura no
	# meio. Os quatro estados são vazios de propósito — o que existisse aqui
	# apareceria **atrás** do círculo desenhado, com os cantos de fora.
	theme.set_type_variation("IconButton", "Button")
	theme.set_color("font_color", "IconButton", TEXT_DIM)
	theme.set_color("font_hover_color", "IconButton", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "IconButton", StyleBoxEmpty.new())

	# Ação secundária: sem preenchimento, para não competir com a principal.
	theme.set_type_variation("GhostButton", "Button")
	theme.set_color("font_color", "GhostButton", TEXT_DIM)
	theme.set_color("font_hover_color", "GhostButton", TEXT)
	theme.set_stylebox("normal", "GhostButton", box(Color(0, 0, 0, 0), RADIUS, BORDER, 1))
	theme.set_stylebox("hover", "GhostButton", box(SURFACE, RADIUS, BORDER, 1))
	theme.set_stylebox("pressed", "GhostButton", box(SURFACE_HIGH, RADIUS, ACCENT_SOFT, 1))


## Botão de contorno numa cor: fundo vazado, borda e texto na cor, e o suave
## como preenchimento só no toque. É o peso do meio — visível sem gritar — e
## sai daqui em vez de repetido três vezes, porque o que distingue um do outro
## é a cor e mais nada.
static func _outlined(theme: Theme, name: String, tint: Color, soft: Color) -> void:
	theme.set_type_variation(name, "Button")
	theme.set_color("font_color", name, tint)
	theme.set_color("font_hover_color", name, tint)
	theme.set_color("font_pressed_color", name, tint)
	theme.set_stylebox("normal", name, box(Color(0, 0, 0, 0), RADIUS, tint, 1))
	theme.set_stylebox("hover", name, box(soft, RADIUS, tint, 1))
	theme.set_stylebox("pressed", name, box(soft, RADIUS, tint, 2))


static func _style_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT)

	theme.set_type_variation("Display", "Label")
	theme.set_font("font", "Display", font(700))
	theme.set_font_size("font_size", "Display", 44)

	theme.set_type_variation("Title", "Label")
	theme.set_font("font", "Title", font(600))
	theme.set_font_size("font_size", "Title", 24)

	theme.set_type_variation("Subtitle", "Label")
	theme.set_font_size("font_size", "Subtitle", 16)
	theme.set_color("font_color", "Subtitle", TEXT_DIM)

	# Saudação da barra superior. Peso 600 e não 700: ela é o endereço da tela,
	# não o nome do app — o `Display` continua sendo do logo.
	theme.set_type_variation("Greeting", "Label")
	theme.set_font("font", "Greeting", font(600))
	theme.set_font_size("font_size", "Greeting", 21)

	# Título de seção dentro de uma tela rolável ("Favoritos", "Tabuleiro").
	#
	# Em caixa normal e na cor do texto, ao contrário do `Caption`, que é caixa
	# alta e apagado. A diferença é de função: `Caption` rotula um controle ("SEU
	# NOME"), e isto **divide** o conteúdo. Um divisor apagado é um divisor que
	# não divide.
	theme.set_type_variation("SectionHeader", "Label")
	theme.set_font("font", "SectionHeader", font(600))
	theme.set_font_size("font_size", "SectionHeader", 16)
	theme.set_color("font_color", "SectionHeader", TEXT)

	theme.set_type_variation("Caption", "Label")
	theme.set_font_size("font_size", "Caption", 14)
	theme.set_color("font_color", "Caption", Color(TEXT_DIM, 0.8))

	# Código de pareamento: números grandes, espaçados, feitos para serem lidos
	# de uma tela e digitados noutra.
	theme.set_type_variation("PairingCode", "Label")
	theme.set_font("font", "PairingCode", font(700))
	theme.set_font_size("font_size", "PairingCode", 40)
	theme.set_color("font_color", "PairingCode", ACCENT)


static func _style_inputs(theme: Theme) -> void:
	theme.set_font("font", "LineEdit", font(600))
	theme.set_font_size("font_size", "LineEdit", 24)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_stylebox("normal", "LineEdit", box(SURFACE, RADIUS, BORDER, 1))
	theme.set_stylebox("focus", "LineEdit", box(SURFACE, RADIUS, ACCENT, 1))

	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_font_size("font_size", "ItemList", 17)
	theme.set_stylebox("panel", "ItemList", box(SURFACE, RADIUS, BORDER, 1))
	theme.set_stylebox("selected", "ItemList", box(ACCENT_SOFT, 10))
	theme.set_stylebox("selected_focus", "ItemList", box(ACCENT_SOFT, 10))
	theme.set_stylebox("hovered", "ItemList", box(Color(TEXT, 0.05), 10))
	theme.set_constant("v_separation", "ItemList", 6)


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", box(SURFACE, RADIUS_LARGE, BORDER, 1))

	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", box(SURFACE, RADIUS_LARGE, BORDER, 1))

	theme.set_type_variation("QuietCard", "PanelContainer")
	var quiet := box(Color(TEXT, 0.03), RADIUS_LARGE, Color(BORDER, 0.6), 1)
	theme.set_stylebox("panel", "QuietCard", quiet)
