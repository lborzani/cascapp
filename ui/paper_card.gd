class_name PaperCard
extends PanelContainer

## O cartão de diálogo do app: fim de partida, revanche, placar final.
##
## Nasceu como papel creme (a comanda do tema antigo), e o nome ficou. Hoje a
## **instância** é um cartão escuro da família do resto da tela, com o canto bem
## redondo, e entra crescendo (`Motion.pop`) toda vez que aparece: os seis jogos
## terminam neste mesmo cartão, então é aqui que o fim de partida ganha a mesma
## cara em todos.
##
## O papel claro continua existindo para o que é papel **dentro de um jogo** — a
## escritura da Metrópole —, pelas funções estáticas `paper_box()` e
## `paper_theme()`. Quem instancia a classe não recebe mais nenhum dos dois.

## Canto do cartão de diálogo.
const DIALOG_RADIUS := 28

@export var tilt_degrees := 0.0:
	set(value):
		tilt_degrees = value
		_apply_tilt()

## O papel um pouco mais escuro dos carimbos (botões e campos dentro do cartão).
const PAPER_SOFT := Color("e2d7bd")

static var _paper_theme: Theme = null


func _init() -> void:
	add_theme_stylebox_override("panel", dialog_box())
	resized.connect(_apply_tilt)
	visibility_changed.connect(_on_visibility_changed)


## Entra com o salto do tema sempre que aparece na tela. Em `visibility_changed`
## e não em quem mostra: são seis telas mostrando este cartão de seis jeitos, e a
## entrada tem de ser a mesma em todas.
func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		Motion.pop(self)


static func dialog_box() -> StyleBoxFlat:
	var style := AppTheme.box(AppTheme.SURFACE, DIALOG_RADIUS)
	# A borda de baixo dos blocos e botões: o cartão é da mesma família.
	style.border_width_bottom = 6
	style.border_color = AppTheme.COASTER
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 24
	style.content_margin_bottom = 20
	return style


func _apply_tilt() -> void:
	pivot_offset = size * 0.5
	rotation = deg_to_rad(tilt_degrees)


static func paper_box() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.PAPER
	style.set_corner_radius_all(AppTheme.RADIUS_PAPER)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


## Só cores: fonte e tamanho continuam vindo do tema do app, e um título no papel
## continua sendo letreiro.
##
## Basta a `Label`: a busca de tema vai primeiro ao dono mais perto — este papel —
## e, dentro dele, sobe da variação para o tipo base. Uma legenda (`Caption`) acha a
## `Label` daqui antes de chegar ao cinza do tema do app. Legenda e subtítulo são
## escritos à parte só para ganharem a tinta mais leve.
static func paper_theme() -> Theme:
	if _paper_theme != null:
		return _paper_theme
	_paper_theme = Theme.new()
	_paper_theme.set_color("font_color", "Label", AppTheme.PAPER_INK)
	for type: String in ["Caption", "Subtitle"]:
		_paper_theme.set_color("font_color", type, Color(AppTheme.PAPER_INK, 0.72))

	# Botão e campo também: um botão com a pele escura do tema dentro do papel é um
	# buraco no papel, e o texto claro dele some no creme. O tom é o mesmo papel um
	# pouco mais escuro — a comanda tem o carimbo, não um painel colado nela.
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_paper_theme.set_color(state, "Button", AppTheme.PAPER_INK)
	_paper_theme.set_stylebox("normal", "Button", _stamp(PAPER_SOFT))
	_paper_theme.set_stylebox("hover", "Button", _stamp(PAPER_SOFT.darkened(0.06)))
	_paper_theme.set_stylebox("pressed", "Button", _stamp(PAPER_SOFT.darkened(0.12)))
	_paper_theme.set_stylebox("focus", "Button", _stamp(PAPER_SOFT))

	_paper_buttons(_paper_theme)

	_paper_theme.set_color("font_color", "LineEdit", AppTheme.PAPER_INK)
	_paper_theme.set_color("font_placeholder_color", "LineEdit", Color(AppTheme.PAPER_INK, 0.45))
	_paper_theme.set_color("caret_color", "LineEdit", AppTheme.PAPER_INK)
	_paper_theme.set_stylebox("normal", "LineEdit", _stamp(Color(1, 1, 1, 0.55)))
	_paper_theme.set_stylebox("focus", "LineEdit", _stamp(Color(1, 1, 1, 0.75)))
	return _paper_theme


## Os botões com peso próprio continuam com ele dentro do papel.
##
## Sem isto, um botão `PrimaryButton` numa folha vira carimbo: a busca de tema vai
## ao dono mais perto, não acha a variação nele e desce para o tipo base — que
## aqui é o carimbo. O resultado é a ação principal da tela com a mesma cara do
## botão secundário ao lado, que é a única coisa que a placa existe para não ser.
##
## O vermelho é o de perigo escurecido: `DANGER` sobre creme dá contraste de 2,6,
## e um aviso que não se lê não avisa.
static func _paper_buttons(theme: Theme) -> void:
	for name: String in ["PrimaryButton", "SuccessSolidButton", "GhostButton", "DangerButton"]:
		theme.set_type_variation(name, "Button")
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "PrimaryButton", AppTheme.ACCENT_INK)
		theme.set_color(state, "SuccessSolidButton", AppTheme.ACCENT_INK)
		theme.set_color(state, "GhostButton", AppTheme.PAPER_INK)
		theme.set_color(state, "DangerButton", AppTheme.DANGER.darkened(0.35))
	theme.set_stylebox("normal", "PrimaryButton", AppTheme.plate(AppTheme.ACCENT, AppTheme.ACCENT_EDGE))
	theme.set_stylebox("hover", "PrimaryButton", AppTheme.plate(AppTheme.ACCENT.lightened(0.08), AppTheme.ACCENT_EDGE))
	theme.set_stylebox("pressed", "PrimaryButton", AppTheme.plate(AppTheme.ACCENT.darkened(0.08), AppTheme.ACCENT_EDGE, true))

	var success_edge := AppTheme.SUCCESS.darkened(0.35)
	theme.set_stylebox("normal", "SuccessSolidButton", AppTheme.plate(AppTheme.SUCCESS, success_edge))
	theme.set_stylebox("hover", "SuccessSolidButton", AppTheme.plate(AppTheme.SUCCESS.lightened(0.08), success_edge))
	theme.set_stylebox("pressed", "SuccessSolidButton", AppTheme.plate(AppTheme.SUCCESS.darkened(0.08), success_edge, true))

	var ghost_line := Color(AppTheme.PAPER_INK, 0.55)
	theme.set_stylebox("normal", "GhostButton", AppTheme.framed(Color(0, 0, 0, 0), ghost_line))
	theme.set_stylebox("hover", "GhostButton", AppTheme.framed(Color(AppTheme.PAPER_INK, 0.06), ghost_line))
	theme.set_stylebox("pressed", "GhostButton", AppTheme.framed(Color(AppTheme.PAPER_INK, 0.12), AppTheme.PAPER_INK))

	var danger := AppTheme.DANGER.darkened(0.35)
	theme.set_stylebox("normal", "DangerButton", AppTheme.box(Color(0, 0, 0, 0), AppTheme.RADIUS, danger, 2))
	theme.set_stylebox("hover", "DangerButton", AppTheme.box(Color(danger, 0.10), AppTheme.RADIUS, danger, 2))
	theme.set_stylebox("pressed", "DangerButton", AppTheme.box(Color(danger, 0.16), AppTheme.RADIUS, danger, 3))


## Carimbo: o retângulo levemente mais escuro que marca um campo ou um botão dentro
## do papel, com a mesma folga de conteúdo do resto do tema.
static func _stamp(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(AppTheme.RADIUS_PAPER)
	style.border_color = Color(AppTheme.PAPER_INK, 0.35)
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
