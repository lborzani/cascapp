class_name RulesPage
extends Control

## "Como jogar": a página inteira das regras de um jogo.
##
## Abre por cima de qualquer tela — da folha do jogo, pelo link, e da partida, pela
## gaveta de regras da mesa — e lê tudo de um [GameRulesDoc]. Objetivo em cima,
## porque é a primeira pergunta de quem nunca jogou; passos numerados, porque são
## uma sequência de verdade; e os avisos por último, porque só fazem sentido para
## quem já entendeu os passos.
##
## Um jogo com mais de um formato (a sinuca) ganha abas no topo, e cada aba é uma
## página inteira: os dois formatos discordam até no que é a bola que taca.
##
## Sem autoload: tudo o que a página precisa vem do recurso, e é o que deixa ela
## ser provada sem cena.

signal closed

## Largura máxima do texto. Deitada, a tela tem o dobro disso, e uma linha de
## regra da largura da tela é uma linha que ninguém acompanha até o fim.
const MAX_WIDTH := 620.0

var doc: GameRulesDoc = null
var format := 0

var _scrim: ColorRect = null
var _panel: PanelContainer = null
var _title: Label = null
var _segments: SegmentedControl = null
var _content: VBoxContainer = null


## Abre as regras de `id` por cima de `host`. `chosen_format` é o formato que
## abre selecionado — o da mesa, quando quem abre é uma partida.
static func open(host: Node, id: StringName, chosen_format := 0) -> RulesPage:
	var page := RulesPage.new()
	host.add_child(page)
	page.show_rules(GameRulesDoc.load_for(id), chosen_format)
	return page


## O `Control` mais alto acima de `node`. Subir a árvore em vez de usar a cena
## corrente: a mesma página roda dentro de uma partida no app e dentro de um nó de
## teste no probe.
static func host_of(node: Node) -> Node:
	var best: Node = node
	var cursor: Node = node
	while cursor != null:
		if cursor is Control:
			best = cursor
		cursor = cursor.get_parent()
	return best


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Acima do painel de fim de partida e da escolha de cor do curinga: a página é
	# uma consulta, e uma consulta que aparece atrás do que se queria consultar
	# não foi aberta.
	z_index = 90
	# O gesto de voltar fecha a página antes de chegar à tela de baixo. Ver
	# `nav.gd`.
	add_to_group(&"back_layer")

	_scrim = ColorRect.new()
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.color = AppTheme.SCRIM
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	_panel = PanelContainer.new()
	var style := AppTheme.box(AppTheme.SURFACE, 0)
	style.corner_radius_top_left = AppTheme.RADIUS_LARGE
	style.corner_radius_top_right = AppTheme.RADIUS_LARGE
	style.border_width_top = 2
	style.border_color = AppTheme.LINE_SOFT
	style.content_margin_left = AppTheme.SCREEN_PAD
	style.content_margin_right = AppTheme.SCREEN_PAD
	style.content_margin_top = AppTheme.SPACE_M
	style.content_margin_bottom = AppTheme.SPACE_L
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_M)
	_panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", AppTheme.SPACE_M)
	column.add_child(header)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	header.add_child(words)
	var caption := Label.new()
	caption.theme_type_variation = &"Caption"
	caption.text = "COMO JOGAR"
	words.add_child(caption)
	_title = Label.new()
	_title.theme_type_variation = &"Title"
	words.add_child(_title)
	var close_button := IconButton.new()
	close_button.kind = IconButton.Kind.CLOSE
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(dismiss)
	header.add_child(close_button)

	_segments = SegmentedControl.new()
	_segments.selected.connect(_on_format)
	column.add_child(_segments)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", AppTheme.SPACE_S)
	scroll.add_child(_content)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_panel()


## A folha sobe até perto do topo e fica centrada, com a largura de leitura.
func _place_panel() -> void:
	if _panel == null:
		return
	var width := minf(size.x, MAX_WIDTH)
	_panel.position = Vector2((size.x - width) * 0.5, size.y * 0.08)
	_panel.size = Vector2(width, size.y * 0.92)


func show_rules(rules: GameRulesDoc, chosen_format := 0) -> void:
	doc = rules
	if doc == null:
		_title.text = "Sem regras"
		_segments.visible = false
		_fill("", PackedStringArray(), PackedStringArray())
		return
	_title.text = doc.title.to_upper()
	var labels := PackedStringArray()
	for block in doc.formats:
		labels.append(block.title)
	format = clampi(chosen_format, 0, maxi(0, labels.size() - 1))
	_segments.visible = labels.size() > 1
	if _segments.visible:
		_segments.setup(labels, format)
	_refresh()
	_place_panel()


func _on_format(index: int) -> void:
	format = index
	_refresh()


func _refresh() -> void:
	if doc.formats.is_empty():
		_fill(doc.objective, doc.steps, doc.notes)
		return
	var block: GameRulesFormat = doc.formats[format]
	_fill(block.objective, block.steps, block.notes)


func _fill(objective: String, steps: PackedStringArray, notes: PackedStringArray) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	if not objective.is_empty():
		var goal := _paragraph(objective, &"Subtitle")
		goal.add_theme_color_override("font_color", AppTheme.TEXT)
		_content.add_child(goal)

	if not steps.is_empty():
		_content.add_child(_heading("Como se joga"))
		for index in steps.size():
			_content.add_child(_numbered(index + 1, steps[index]))

	if not notes.is_empty():
		_content.add_child(_heading("Vale saber"))
		for note in notes:
			_content.add_child(_numbered(0, note))


func _heading(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"SectionHeader"
	label.text = text
	return label


func _paragraph(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = text
	return label


## Uma linha com marca à esquerda: o número do passo, em mono amarelo, ou um traço
## de giz nos avisos — que não têm ordem, e numerá-los inventaria uma.
func _numbered(number: int, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", AppTheme.SPACE_S)
	var mark := Label.new()
	mark.custom_minimum_size.x = 22
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if number > 0:
		mark.text = str(number)
		mark.add_theme_font_override("font", AppTheme.mono(600))
		mark.add_theme_color_override("font_color", AppTheme.ACCENT)
	else:
		mark.text = "—"
		mark.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	mark.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	row.add_child(mark)
	var body := _paragraph(text, &"")
	body.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	row.add_child(body)
	return row


## Fecha a página. Público porque o gesto de voltar chega aqui por `nav.gd`.
func dismiss() -> void:
	if is_queued_for_deletion():
		return
	remove_from_group(&"back_layer")
	closed.emit()
	queue_free()


func _on_scrim_input(event: InputEvent) -> void:
	# Tocar fora fecha, como a folha do jogo. Por [Tap]: um clique chega duas vezes.
	if Tap.began(event):
		dismiss()
