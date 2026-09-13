class_name MonopolyResult
extends Control

## A tela de fim de partida: quem venceu, por quê, e como ficou a mesa.
##
## Ela mostra o **patrimônio final de todo mundo**, e não só o nome do vencedor.
## Metrópole é longa e termina de dois jeitos diferentes — sobrando um, ou no
## fim das rodadas — e no segundo o vencedor é o maior patrimônio, um número que
## ninguém acompanhou durante a partida porque a coluna da esquerda mostra o
## caixa, que é outra coisa. Anunciar o campeão sem a tabela seria anunciar o
## resultado de uma conta que o jogador não viu ser feita.
##
## Cobre a tela inteira e escurece o que está atrás em vez de flutuar sobre o
## tabuleiro. A partida acabou: nada atrás disto aceita toque, e um painel
## flutuante convidaria a tentar.

signal again_pressed
signal leave_pressed

## Fundo escuro sobre o tabuleiro.
const SHADE := 0.72

var _panel: PanelContainer = null
var _title: Label = null
var _subtitle: Label = null
var _table: VBoxContainer = null
var _again: Button = null


## O `PRESET_FULL_RECT` desta camada é escrito por quem a monta, **antes** de
## `add_child`. Escrito aqui dentro, o nó já estava na árvore e escondido, e o
## layout não voltava para recalcular: a camada ficava com tamanho zero, o fundo
## escuro não cobria nada e o painel aparecia encostado no canto de cima à
## esquerda em vez de centrado.
func _ready() -> void:
	visible = false

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, SHADE)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Pára o toque: o tabuleiro atrás continua vivo, e um toque que atravessasse
	# daqui moveria a câmera de uma partida encerrada.
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(340, 0)
	_panel.add_theme_stylebox_override("panel", AppTheme.box(
		AppTheme.SURFACE, AppTheme.RADIUS_LARGE, AppTheme.BORDER, 1
	))
	center.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 11)
	_subtitle.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_subtitle)

	_table = VBoxContainer.new()
	_table.add_theme_constant_override("separation", 3)
	column.add_child(_table)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	var leave := Button.new()
	leave.text = "Sair"
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.custom_minimum_size.y = 38
	leave.add_theme_font_size_override("font_size", 13)
	leave.pressed.connect(func() -> void: leave_pressed.emit())
	buttons.add_child(leave)

	_again = Button.new()
	_again.text = "Jogar de novo"
	_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_again.custom_minimum_size.y = 38
	_again.add_theme_font_size_override("font_size", 13)
	_again.theme_type_variation = &"PrimaryButton"
	_again.pressed.connect(func() -> void: again_pressed.emit())
	buttons.add_child(_again)


## O fim normal: alguém venceu.
##
## `labeler` é a mesma função que nomeia a coluna da esquerda. Recebida de fora
## para "Bot 2" ser "Bot 2" nos dois lugares — quem sabe quais cadeiras são
## máquina e qual nome está guardado no aparelho é a cena da partida.
func show_winner(
	state: MatchState, champion: int, labeler: Callable, allow_again: bool
) -> void:
	var by_rounds := MonopolyRules.limit_of(state) > 0
	_title.text = "%s venceu" % labeler.call(champion)
	_subtitle.text = (
		"Fim das %d rodadas — venceu o maior patrimônio." % MonopolyRules.limit_of(state)
		if by_rounds
		else "Todos os outros quebraram."
	)
	_fill_table(state, labeler, champion)
	_again.visible = allow_again
	visible = true


## O fim que ninguém escolheu: a mesa se desfez em rede.
##
## Sem tabela de patrimônio. Ela responderia "quem estava ganhando", que é uma
## pergunta que uma partida interrompida não tem o direito de responder.
func show_abandoned(message: String) -> void:
	_title.text = "A partida acabou"
	_subtitle.text = message
	for child in _table.get_children():
		child.queue_free()
	_again.visible = false
	visible = true


## Uma linha por jogador, do maior patrimônio para o menor. Quem quebrou aparece
## também, no fim e apagado: sumir da lista faria a mesa de seis parecer ter tido
## quatro.
func _fill_table(state: MatchState, labeler: Callable, champion: int) -> void:
	for child in _table.get_children():
		child.queue_free()

	var order: Array[int] = []
	for player in MonopolyRules.seats_of(state):
		order.append(player)
	order.sort_custom(func(a: int, b: int) -> bool:
		var a_out := MonopolyRules.is_out(state, a)
		var b_out := MonopolyRules.is_out(state, b)
		if a_out != b_out:
			return b_out
		return MonopolyRules.net_worth(state, a) > MonopolyRules.net_worth(state, b)
	)

	for player in order:
		var out := MonopolyRules.is_out(state, player)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var stripe := ColorRect.new()
		stripe.custom_minimum_size = Vector2(4, 0)
		stripe.color = Color(
			MonopolyFace.PLAYER_COLORS[player % MonopolyFace.PLAYER_COLORS.size()],
			0.35 if out else 1.0
		)
		row.add_child(stripe)

		var tint := AppTheme.TEXT_DIM if out or player != champion else AppTheme.TEXT
		var name_label := Label.new()
		name_label.text = labeler.call(player)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", tint)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_label)

		var worth := Label.new()
		worth.text = "quebrou" if out else "M %d" % MonopolyRules.net_worth(state, player)
		worth.add_theme_font_size_override("font_size", 12)
		worth.add_theme_color_override("font_color", tint)
		row.add_child(worth)

		_table.add_child(row)
