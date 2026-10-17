class_name ChangelogPanel
extends Control

## As novidades do app, por cima da tela: "Novidades da 1.31" na primeira
## abertura de uma versão nova (menu), ou todas as versões do `CHANGELOG.md` que
## veio no APK (aba Você). Fechar devolve a tela como estava.

signal closed

var title := "Novidades"
## `[{version, items}]`, a mais nova em cima (ver `Changelog.parse`).
var sections := []


## A lista "Novidades da X" + uma linha por novidade. A tela de atualizar mostra
## as versões puladas com a mesma cara.
static func notes(of: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Notes"
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", AppTheme.SPACE_S)
	if of.is_empty():
		box.add_child(_line("Melhorias e correções.", &""))
	for section: Dictionary in of:
		box.add_child(_line("Novidades da %s" % section["version"], &"SectionHeader"))
		for item in section["items"]:
			box.add_child(_line("•  %s" % item, &""))
	return box


static func _line(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		label.theme_type_variation = variation
	return label


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = AppTheme.shared()
	mouse_filter = MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)

	var safe := SafeAreaMargin.new()
	for side in ["left", "top", "right", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 16)
	safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	safe.add_child(column)

	var header := HBoxContainer.new()
	var heading := _line(title, &"Title")
	heading.name = "Title"
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(heading)
	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = "Fechar"
	close_button.theme_type_variation = &"GhostButton"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(notes(sections))
	column.add_child(scroll)


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
