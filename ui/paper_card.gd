class_name PaperCard
extends PanelContainer

## Papel sobre a mesa: a comanda com o código da sala, a escritura de Metrópole.
##
## Três objetos do app são papel, e só eles. O que eles dividem não é só o fundo
## claro: é a tinta. Tudo o que o tema pinta de giz sobre a lousa — rótulo,
## legenda, título — precisa virar tinta escura aqui dentro, e isso vem de um tema
## próprio, que desce para os filhos antes do tema do app.

@export var tilt_degrees := 0.0:
	set(value):
		tilt_degrees = value
		_apply_tilt()

## O papel um pouco mais escuro dos carimbos (botões e campos dentro do cartão).
const PAPER_SOFT := Color("e2d7bd")

static var _paper_theme: Theme = null


func _init() -> void:
	add_theme_stylebox_override("panel", paper_box())
	theme = paper_theme()
	resized.connect(_apply_tilt)


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

	_paper_theme.set_color("font_color", "LineEdit", AppTheme.PAPER_INK)
	_paper_theme.set_color("font_placeholder_color", "LineEdit", Color(AppTheme.PAPER_INK, 0.45))
	_paper_theme.set_color("caret_color", "LineEdit", AppTheme.PAPER_INK)
	_paper_theme.set_stylebox("normal", "LineEdit", _stamp(Color(1, 1, 1, 0.55)))
	_paper_theme.set_stylebox("focus", "LineEdit", _stamp(Color(1, 1, 1, 0.75)))
	return _paper_theme


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
