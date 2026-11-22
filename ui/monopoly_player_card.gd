class_name MonopolyPlayerCard
extends PanelContainer

## Uma faixa da coluna da esquerda: um jogador e o dinheiro dele.
##
## A coluna é a resposta para "como está a partida". Ela fica **sempre visível**,
## e é por isso que a informação dela é curta: a bolacha na cor do peão, o nome e
## o caixa. Detalhe de propriedade é pergunta de painel, não de coluna — quem olha
## para cá quer comparar seis jogadores de relance.
##
## A cor da bolacha é a mesma que tinge o peão no tabuleiro ([monopoly_face.gd]),
## e é o único elo entre a coluna e o que se vê em cima do tampo.
##
## ## O dinheiro não muda em silêncio
##
## Quando o caixa muda, um selo "+ M 220" (limão) ou "− M 220" (coral) aparece no
## canto e some. O número novo sozinho obrigava a lembrar o antigo para saber o
## que aconteceu — e aluguel é o acontecimento mais frequente do jogo.

## A faixa foi tocada: quem olha quer ver as propriedades deste jogador.
signal chosen(player: int)

## Corpos nos dois tamanhos: mesa curta e mesa cheia. Seis faixas não cabem nos
## 416 de altura da base deitada no tamanho normal.
const SIZES := {
	false: {"name": 13, "cash": 19, "pad": 6, "coaster": 36},
	true: {"name": 11, "cash": 15, "pad": 2, "coaster": 28},
}
## Quanto o selo de diferença fica na tela.
const DELTA_HOLD := 1.6

var _coaster: Coaster = null
var _name: Label = null
var _cash: Label = null
var _delta: Label = null
var _margin: MarginContainer = null
var _player := -1
## O caixa do último desenho. -1 antes do primeiro: a partida nascendo não é
## dinheiro mudando de mão.
var _last_cash := -1
var _delta_tween: Tween = null
var _press := Tap.Press.new()


func _ready() -> void:
	# O cartão inteiro é o alvo, e por isso os containers de dentro deixam o toque
	# passar.
	mouse_filter = Control.MOUSE_FILTER_STOP

	_margin = MarginContainer.new()
	_margin.add_theme_constant_override("margin_left", AppTheme.SPACE_S + 2)
	_margin.add_theme_constant_override("margin_right", AppTheme.SPACE_S)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", AppTheme.SPACE_S + 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(line)

	_coaster = Coaster.new()
	_coaster.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_coaster)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(column)

	_name = Label.new()
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_name.add_theme_font_override("font", AppTheme.font(800))
	column.add_child(_name)

	_cash = Label.new()
	_cash.add_theme_font_override("font", AppTheme.display(600))
	column.add_child(_cash)

	_delta = Label.new()
	_delta.visible = false
	_delta.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_delta.add_theme_font_override("font", AppTheme.font(800))
	_delta.add_theme_font_size_override("font_size", 11)
	_delta.add_theme_color_override("font_color", AppTheme.ACCENT_INK)
	line.add_child(_delta)

	dense(false)


func _gui_input(event: InputEvent) -> void:
	# Por [Tap]: ver o cabeçalho dele. Um clique chega duas vezes.
	if _press.feed(event) and _player >= 0:
		accept_event()
		chosen.emit(_player)


## Aperta o cartão para caber numa mesa cheia. Escrito depois de `add_child`: os
## rótulos só existem a partir do `_ready`.
func dense(value: bool) -> void:
	var step: Dictionary = SIZES[value]
	_name.add_theme_font_size_override("font_size", int(step["name"]))
	_cash.add_theme_font_size_override("font_size", int(step["cash"]))
	_margin.add_theme_constant_override("margin_top", int(step["pad"]))
	_margin.add_theme_constant_override("margin_bottom", int(step["pad"]))
	_coaster.custom_minimum_size = Vector2.ONE * float(step["coaster"])


## "M 1.340": o milhar com ponto, como o dinheiro se escreve aqui.
static func money(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = "." + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return "%sM %s%s" % ["−" if value < 0 else "", digits, grouped]


## Preenche a faixa a partir do estado. Recebe tudo pronto: o cartão não sabe as
## regras do jogo, só desenha o que lhe dizem.
func show_player(
	state: MatchState, player: int, is_turn: bool, label: String
) -> void:
	_player = player
	var color: Color = MonopolyFace.PLAYER_COLORS[player % MonopolyFace.PLAYER_COLORS.size()]
	var out := MonopolyRules.is_out(state, player)

	# Quem joga sobe um degrau de superfície e ganha a borda limão, como as
	# etiquetas dos outros jogos; quem espera fica na superfície base.
	var style := (
		AppTheme.box(AppTheme.SURFACE_HIGH, AppTheme.RADIUS_LARGE, AppTheme.ACCENT, 2)
		if is_turn else AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_LARGE)
	)
	# As folgas do tema saem: quem dá a folga é o `MarginContainer` de dentro, que
	# é o que o modo apertado ajusta.
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	add_theme_stylebox_override("panel", style)

	_coaster.player_name = label
	_coaster.fill = Color(color, 0.4 if out else 1.0)
	_coaster.ring = Color(color, 0.0)
	_coaster.turn = is_turn and not out

	# O que é especial do jogador vai no nome, como no protótipo ("Ana · na
	# cadeia"). A carta de saída livre também: é a única coisa que se guarda neste
	# jogo, e o botão de usá-la só existe na fase da cadeia.
	var parts := PackedStringArray([label])
	if not out and MonopolyRules.in_jail(state, player):
		parts.append("na cadeia")
	var kept := MonopolyRules.jail_cards_of(state, player)
	if not out and kept > 0:
		parts.append("saída livre" if kept == 1 else "%d saídas livres" % kept)
	_name.text = " · ".join(parts)
	_name.add_theme_color_override(
		"font_color", AppTheme.ACCENT if is_turn and not out else AppTheme.TEXT_DIM
	)

	if out:
		_cash.text = "quebrou"
		_cash.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
		_last_cash = -1
		return

	var cash := MonopolyRules.cash_of(state, player)
	_cash.text = money(cash)
	_cash.add_theme_color_override("font_color", AppTheme.TEXT)
	if _last_cash >= 0 and cash != _last_cash:
		_flash(cash - _last_cash)
	_last_cash = cash


## O selo da diferença: entra, fica o bastante para ser lido e sai.
func _flash(change: int) -> void:
	var gain := change > 0
	_delta.text = "%s M %s" % ["+" if gain else "−", money(absi(change)).trim_prefix("M ")]
	var pill := AppTheme.box(AppTheme.ACCENT if gain else AppTheme.DANGER, 11)
	pill.content_margin_left = 7
	pill.content_margin_right = 7
	pill.content_margin_top = 2
	pill.content_margin_bottom = 2
	_delta.add_theme_stylebox_override("normal", pill)
	if _delta_tween != null:
		_delta_tween.kill()
	_delta.visible = true
	_delta.modulate.a = 0.0
	_delta_tween = create_tween()
	_delta_tween.tween_property(_delta, "modulate:a", 1.0, 0.2)
	_delta_tween.tween_interval(DELTA_HOLD)
	_delta_tween.tween_property(_delta, "modulate:a", 0.0, 0.4)
	_delta_tween.tween_callback(func() -> void: _delta.visible = false)
