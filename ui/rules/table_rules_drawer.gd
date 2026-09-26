class_name TableRulesDrawer
extends Control

## "Regras desta mesa": a gaveta do `?` da barra de partida.
##
## Não é a página de regras encolhida. Quem toca no `?` no meio de uma partida já
## sabe jogar e quer uma resposta curta — "o 0 e o 7 estão valendo aqui?", "quanto
## custa esquecer o UNO?" —, e a resposta está numa lista de linhas com o estado
## de cada uma. A página inteira fica a um toque, no rodapé, para quem precisar.
##
## Entra pela direita e cobre só uma faixa: a mesa continua à vista atrás dela,
## que é o que se está consultando.

signal closed

const WIDTH := 340.0

var game_id: StringName = &""
var format := 0

var _scrim: ColorRect = null
var _panel: PanelContainer = null
var _list: VBoxContainer = null


## Abre a gaveta com as regras já montadas — quem abre sabe as opções da partida,
## a gaveta não. `chosen_format` segue para a página completa, se ela for aberta.
static func open(
	host: Node, id: StringName, rules: Array[Dictionary], chosen_format := 0
) -> TableRulesDrawer:
	var drawer := TableRulesDrawer.new()
	drawer.game_id = id
	drawer.format = chosen_format
	host.add_child(drawer)
	drawer.show_rules(rules)
	return drawer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90
	add_to_group(&"back_layer")

	_scrim = ColorRect.new()
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(AppTheme.SCRIM, 0.35)
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	_panel = PanelContainer.new()
	var style := AppTheme.box(AppTheme.SURFACE, 0)
	style.border_width_left = 2
	style.border_color = AppTheme.LINE_SOFT
	style.content_margin_left = AppTheme.SPACE_L
	style.content_margin_right = AppTheme.SPACE_L
	style.content_margin_top = AppTheme.SPACE_M
	style.content_margin_bottom = AppTheme.SPACE_M
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_S)
	_panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", AppTheme.SPACE_S)
	column.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"SectionHeader"
	title.text = "Regras desta mesa"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := IconButton.new()
	close_button.kind = IconButton.Kind.CLOSE
	close_button.pressed.connect(dismiss)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_list)

	var full := Button.new()
	full.theme_type_variation = &"GhostButton"
	full.text = "Ver regras completas"
	full.pressed.connect(open_full)
	column.add_child(full)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null:
		var width := minf(size.x, WIDTH)
		_panel.position = Vector2(size.x - width, 0.0)
		_panel.size = Vector2(width, size.y)


func show_rules(rules: Array[Dictionary]) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for rule in rules:
		_list.add_child(_row(str(rule["label"]), str(rule["state"])))


## Uma regra por linha: o que ela é à esquerda e como está aqui à direita, em
## amarelo — é a parte que muda de mesa para mesa, e a que se procura.
func _row(label: String, state: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 40
	row.add_theme_constant_override("separation", AppTheme.SPACE_S)
	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	row.add_child(name_label)
	var state_label := Label.new()
	state_label.text = state
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state_label.add_theme_font_override("font", AppTheme.font(700))
	state_label.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	state_label.add_theme_color_override("font_color", AppTheme.ACCENT)
	row.add_child(state_label)

	# Um fio de giz entre as linhas, e não uma caixa por regra: são quatro
	# linhas curtas, e quatro caixas seriam quatro coisas para tocar sem ter o que
	# tocar.
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 0)
	block.add_child(row)
	var rule := Panel.new()
	rule.custom_minimum_size.y = 1
	rule.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.LINE_SOFT, 0))
	block.add_child(rule)
	return block


## Troca a gaveta pela página inteira, no formato da mesa.
func open_full() -> RulesPage:
	var host := get_parent()
	dismiss()
	return RulesPage.open(host, game_id, format)


func dismiss() -> void:
	if is_queued_for_deletion():
		return
	remove_from_group(&"back_layer")
	closed.emit()
	queue_free()


func _on_scrim_input(event: InputEvent) -> void:
	if Tap.began(event):
		dismiss()
