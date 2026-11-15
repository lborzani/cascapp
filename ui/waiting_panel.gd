class_name WaitingPanel
extends Control

## O que está acontecendo enquanto a sala não abre, do lado de quem entrou.
##
## Antes isto era uma linha de texto embaixo da lista: "Na sala: 4 de 4
## jogadores." Ela diz o número e não diz **em que partida** você entrou — e é
## justamente essa a dúvida de quem digitou um código de seis letras que alguém
## mandou por mensagem. Xadrez ou Ludo? Já começou?
##
## É a mesma tela de quem abriu a sala (`scenes/pairing.tscn`), vista do outro
## lado: a faixa na cor do jogo com o código, um lugar por linha, e no rodapé o
## botão — que aqui fica apagado, porque quem começa é quem abriu.
##
## ## Ele sai por um botão, e o botão desiste de verdade
##
## Sair daqui não é voltar de tela: é largar a cadeira que o servidor já reservou.
## Sem isso a cadeira fica ocupada até a carência do relay expirar, e quem tentar
## entrar no lugar recebe "sala cheia" de uma sala que tem gente de menos.

## Desistiu de entrar. Quem escuta larga a sala.
signal cancelled

var _band: PanelContainer = null
var _title: Label = null
var _count: Label = null
var _code: Label = null
var _seats: SeatList = null
var _hint: Label = null
var _start: Button = null


## As âncoras são escritas por quem monta, antes do `add_child` — mesma armadilha
## do painel de fim de Metrópole e do de boas-vindas.
func _ready() -> void:
	visible = false

	var shade := ColorRect.new()
	shade.color = AppTheme.BACKGROUND
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var shell := VBoxContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 0)
	add_child(shell)

	_band = PanelContainer.new()
	shell.add_child(_band)
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", AppTheme.SPACE_M)
	_band.add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	_title = _ink_label(AppTheme.display(700), 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title)
	_count = _ink_label(AppTheme.font(800), AppTheme.SIZE_CAPTION + 1)
	row.add_child(_count)
	var caption := _ink_label(AppTheme.font(800), AppTheme.SIZE_CAPTION + 1)
	caption.text = "VOCÊ ENTROU NA SALA"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(caption)
	_code = _ink_label(AppTheme.display(700), 56)
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_code)

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top"]:
		body.add_theme_constant_override("margin_" + side, AppTheme.SCREEN_PAD)
	shell.add_child(body)
	# Um lugar por linha, no lugar do número: "2 de 4" responde "falta muito?" e
	# não responde "quem já está aqui?".
	_seats = SeatList.new()
	body.add_child(_seats)

	var footer := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		footer.add_theme_constant_override("margin_" + side, AppTheme.SCREEN_PAD)
	shell.add_child(footer)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	footer.add_child(column)
	_hint = Label.new()
	_hint.theme_type_variation = &"Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)
	_start = Button.new()
	_start.theme_type_variation = &"PrimaryButton"
	_start.custom_minimum_size.y = 60
	_start.disabled = true
	column.add_child(_start)
	var cancel := Button.new()
	cancel.text = "Desistir"
	cancel.theme_type_variation = &"GhostButton"
	cancel.custom_minimum_size.y = 48
	cancel.pressed.connect(func() -> void: cancelled.emit())
	column.add_child(cancel)


func _ink_label(face: Font, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", face)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", AppTheme.ACCENT_INK)
	return label


## Mostra a espera. `taken` e `capacity` vêm do relay, que os conhece assim que a
## cadeira é dada — antes de o anfitrião ter dito qualquer coisa.
##
## `capacity` zero é a sala de dois, onde o relay não conta: ali a pergunta não é
## "quantos faltam" e sim "o anfitrião ainda está aí".
func show_room(
	game_id: StringName, code: String, present: PackedInt32Array, capacity: int, local_seat: int
) -> void:
	var color: Color = AppTheme.GAME_COLORS.get(String(game_id), AppTheme.SURFACE_HIGH)
	var band := AppTheme.box(color, 0)
	band.corner_radius_bottom_left = 32
	band.corner_radius_bottom_right = 32
	band.border_width_bottom = 6
	band.border_color = color.darkened(0.3)
	band.content_margin_left = AppTheme.SCREEN_PAD
	band.content_margin_right = AppTheme.SCREEN_PAD
	band.content_margin_top = AppTheme.SPACE_XL
	band.content_margin_bottom = AppTheme.SPACE_XL
	_band.add_theme_stylebox_override("panel", band)

	var title := Game.game_title(game_id)
	_title.text = "Sala de %s" % title if not title.is_empty() else "Sala"
	_code.text = code
	var seats := maxi(capacity, 2)
	_count.text = "%d de %d" % [mini(maxi(present.size(), 1), seats), seats]
	_seats.capacity = seats
	_seats.game_id = Game.game_id
	_seats.local_seat = maxi(local_seat, 0)
	_seats.present = present
	_seats.refresh()
	if capacity > 2:
		var full := present.size() >= capacity
		_hint.text = "Mesa cheia." if full else "Quem abriu a sala começa quando quiser."
		_start.text = "Entrando na partida…" if full else "Esperando a mesa encher"
	else:
		_hint.text = "A partida começa assim que quem abriu a sala estiver pronto."
		_start.text = "Esperando quem abriu a sala"
	visible = true


func hide_room() -> void:
	visible = false
