class_name SegmentedControl
extends PanelContainer

## Abas curtas de uma escolha só: o modo de jogo na folha do jogo, o formato na
## página de regras.
##
## Uma fileira de botões dentro de um contorno, e só o marcado preenchido de
## amarelo. `selected` avisa apenas o toque de quem joga; `set_current` troca em
## silêncio, para a tela poder restaurar uma escolha sem se ouvir de volta.

signal selected(index: int)

var current := -1
var _row: HBoxContainer = null
var _buttons: Array[Button] = []


func _init() -> void:
	var frame := AppTheme.box(Color(0, 0, 0, 0), AppTheme.RADIUS, AppTheme.LINE, 1)
	frame.content_margin_left = 4
	frame.content_margin_right = 4
	frame.content_margin_top = 4
	frame.content_margin_bottom = 4
	add_theme_stylebox_override("panel", frame)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	add_child(_row)


func setup(labels: PackedStringArray, index := 0) -> void:
	# `remove_child` antes do `queue_free`: o segundo só apaga no fim do quadro, e
	# até lá a fileira teria os segmentos velhos ao lado dos novos.
	for button in _buttons:
		_row.remove_child(button)
		button.queue_free()
	_buttons.clear()
	for i in labels.size():
		var button := Button.new()
		button.text = labels[i].to_upper()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.pressed.connect(_on_pressed.bind(i))
		_row.add_child(button)
		_buttons.append(button)
	current = -1
	set_current(index)


func set_current(index: int) -> void:
	current = -1 if _buttons.is_empty() else clampi(index, 0, _buttons.size() - 1)
	for i in _buttons.size():
		_buttons[i].theme_type_variation = &"SegmentSelected" if i == current else &"Segment"


func segment_count() -> int:
	return _buttons.size()


func _on_pressed(index: int) -> void:
	if index == current:
		return
	set_current(index)
	selected.emit(index)
