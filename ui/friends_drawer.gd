class_name FriendsDrawer
extends Control

## A barra lateral de amigos: desliza da direita, por cima da tela, com cada amigo
## — foto, nome, se está online e o que está fazendo.
##
## Os dados são do `Friends` (lista do PocketBase, online pelo relay); esta camada
## só desenha e redesenha quando eles mudam. Enquanto ela está aberta o `Friends`
## pergunta ao relay a cada poucos segundos — fechada, ninguém está olhando.
##
## Gerenciar amigos (código, QR, remover) continua no painel da aba Você: o
## "Adicionar amigo" daqui abre aquele painel por cima, e a lista volta
## atualizada quando ele fecha.

signal closed

const SLIDE := 0.22
const MAX_WIDTH := 340.0
const WIDTH_RATIO := 0.86
const PHOTO := 44.0
const DOT := 12.0

var _slider: Control = null
var _rows: VBoxContainer = null
var _note: Label = null
var _width := MAX_WIDTH


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_width = minf(MAX_WIDTH, get_viewport_rect().size.x * WIDTH_RATIO)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.color = AppTheme.SCRIM
	scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close()
	)
	add_child(scrim)

	# Quem anda é o suporte de tela cheia, e não o painel ancorado (ver
	# `GameSheet`: escrever `position` num `Control` ancorado reescreve os offsets).
	_slider = Control.new()
	_slider.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_slider.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_slider)

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -_width
	var style := AppTheme.box(AppTheme.SURFACE, 0)
	style.border_width_left = 2
	style.border_color = AppTheme.LINE_SOFT
	panel.add_theme_stylebox_override("panel", style)
	_slider.add_child(panel)

	var safe := SafeAreaMargin.new()
	panel.add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_M)
	safe.add_child(column)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Amigos"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := IconButton.new()
	close_button.kind = IconButton.Kind.CLOSE
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(_padded(header))

	_note = _text("", &"Subtitle")
	_note.visible = false
	column.add_child(_padded(_note))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", AppTheme.SPACE_S)
	scroll.add_child(_padded(_rows))

	var add := Button.new()
	add.text = "Adicionar amigo"
	add.theme_type_variation = &"GhostButton"
	add.custom_minimum_size = Vector2(0, 44)
	add.pressed.connect(_open_panel)
	column.add_child(_padded(add))

	Friends.changed.connect(_fill)
	Account.remote_avatar_loaded.connect(_fill)
	Friends.watching = true
	_fill()
	Friends.refresh()

	_slider.position.x = _width
	modulate.a = 0.0
	var slide := create_tween().set_parallel()
	slide.tween_property(self, "modulate:a", 1.0, SLIDE * 0.6)
	slide.tween_property(_slider, "position:x", 0.0, SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _exit_tree() -> void:
	Friends.watching = false


## Fecha o painel de amigos, se aberto por cima, e depois a gaveta: é o que o
## gesto de voltar faz, uma camada por vez.
func close() -> void:
	for child in get_children():
		if child is FriendsPanel:
			child.close()
			return
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _fill() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	var note := ""
	if not Account.signed_in():
		note = "Sem conexão com a sua conta agora. Os amigos aparecem quando ela voltar."
	elif not Net.relay_available():
		note = "Sem servidor de partidas: não dá para ver quem está online."
	elif Friends.list.is_empty():
		note = "Nenhum amigo ainda. Troque códigos com quem joga com você."
	_note.text = note
	_note.visible = not note.is_empty()

	for friend: Dictionary in Friends.sorted():
		_rows.add_child(_row(friend))


func _row(friend: Dictionary) -> Control:
	var id := str(friend.get("id", ""))
	var status: Variant = Friends.status_of(id)
	var card := PanelContainer.new()
	card.set_meta(&"friend_id", id)
	card.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SURFACE_HIGH, AppTheme.RADIUS))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", AppTheme.SPACE_M)
	card.add_child(line)

	# A bolinha verde por cima do canto da foto, como nos mensageiros.
	var photo_box := Control.new()
	photo_box.custom_minimum_size = Vector2(PHOTO, PHOTO)
	photo_box.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(photo_box)
	var coaster := Coaster.new()
	coaster.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	coaster.player_name = str(friend.get("name", ""))
	coaster.photo = Account.avatar_of(id, str(friend.get("avatar", "")))
	photo_box.add_child(coaster)
	if status != null:
		var dot := Panel.new()
		dot.name = "OnlineDot"
		dot.mouse_filter = MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SUCCESS, int(DOT * 0.5), AppTheme.SURFACE_HIGH, 2))
		dot.position = Vector2(PHOTO - DOT, PHOTO - DOT)
		dot.size = Vector2(DOT, DOT)
		photo_box.add_child(dot)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 0)
	var name_label := _text(str(friend.get("name", "")), &"")
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_override("font", AppTheme.font(800))
	name_label.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	words.add_child(name_label)
	var status_label := _text(Friends.status_text(status), &"Caption")
	status_label.name = "Status"
	if status != null:
		status_label.add_theme_color_override("font_color", AppTheme.SUCCESS)
	words.add_child(status_label)
	line.add_child(words)
	return card


func _open_panel() -> void:
	Sound.play(Sound.Cue.TAP)
	var panel := FriendsPanel.new()
	panel.closed.connect(Friends.refresh)
	add_child(panel)


func _padded(content: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, AppTheme.SPACE_L)
	margin.add_child(content)
	return margin


func _text(value: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		label.theme_type_variation = variation
	return label
