class_name CodeInput
extends Control

## O código da sala em seis casas de papel.
##
## Era um campo de texto com "Código da partida" escrito dentro. Um campo aceita
## qualquer coisa e não diz **quanto** falta: quem digitava cinco letras só
## descobria o erro tocando em "Entrar". Seis casas dizem o tamanho antes de
## começar, mostram onde o dedo parou, e entram sozinhas quando a última é
## preenchida.
##
## Por dentro ainda é um `LineEdit`, invisível, cobrindo as casas: é ele que abre
## o teclado do Android, aceita colar e recebe o texto do sistema. As casas são
## desenhadas por baixo, e o que aparece nelas é o que ele guarda — um só dono do
## texto, em vez de seis campos que precisam concordar entre si.
##
## O que entra é limpo na porta: maiúsculas, só letras e números. Um código colado
## de uma mensagem vem com espaço, hífen e aspas em volta, e recusar isso seria
## culpar o jogador pela formatação de quem mandou.

signal completed(code: String)

const LENGTH := 6
const HEIGHT := 58.0
const GAP := 6.0
const CHAR_SIZE := 26

var code := ""

var _edit: LineEdit = null
## Já avisamos por este código? Sem isto, cada tecla depois da sexta avisaria de
## novo, e a tela tentaria entrar na sala uma vez por toque.
var _announced := false


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	_edit = LineEdit.new()
	_edit.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edit.max_length = LENGTH
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.context_menu_enabled = true
	_edit.caret_blink = true
	# Invisível, e não escondido: escondido ele não recebe toque nem abre teclado.
	_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_edit.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_edit.add_theme_color_override("font_placeholder_color", Color(0, 0, 0, 0))
	_edit.add_theme_color_override("caret_color", Color(0, 0, 0, 0))
	_edit.add_theme_color_override("selection_color", Color(0, 0, 0, 0))
	_edit.text_changed.connect(_on_typed)
	_edit.text_submitted.connect(func(_text: String) -> void: _announce())
	add_child(_edit)


func set_code(raw: String) -> void:
	_edit.text = clean(raw)
	_edit.caret_column = _edit.text.length()
	_apply(_edit.text)


func clear() -> void:
	_announced = false
	set_code("")


func grab() -> void:
	_edit.grab_focus()


## Maiúsculas e só letras e números, no tamanho do código. É a porta: o resto do
## app pode contar com o que sai daqui.
static func clean(raw: String) -> String:
	var kept := ""
	for character in raw.to_upper():
		if character.is_valid_int() or character.to_upper() != character.to_lower():
			kept += character
		if kept.length() == LENGTH:
			break
	return kept


func _on_typed(text: String) -> void:
	var cleaned := clean(text)
	if cleaned != text:
		# Escrever de volta não reemite `text_changed`, então não há laço aqui.
		_edit.text = cleaned
		_edit.caret_column = cleaned.length()
	_apply(cleaned)


func _apply(cleaned: String) -> void:
	code = cleaned
	queue_redraw()
	if cleaned.length() < LENGTH:
		_announced = false
		return
	_announce()


func _announce() -> void:
	if _announced or code.length() < LENGTH:
		return
	_announced = true
	completed.emit(code)


func _draw() -> void:
	var box := Vector2((size.x - GAP * (LENGTH - 1)) / LENGTH, size.y)
	var face := AppTheme.mono(600)
	for index in LENGTH:
		var origin := Vector2((box.x + GAP) * index, 0.0)
		var rect := Rect2(origin, box)
		draw_rect(rect, AppTheme.PAPER)
		# A casa em que o dedo está ganha o contorno amarelo: é onde a próxima
		# letra cai, e é a única coisa desta tela que responde ao teclado.
		if index == mini(code.length(), LENGTH - 1) and _edit.has_focus():
			draw_rect(rect, AppTheme.ACCENT, false, 2.0)
		if index >= code.length():
			continue
		var glyph := code[index]
		var width := face.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CHAR_SIZE).x
		draw_string(
			face, origin + Vector2((box.x - width) * 0.5, box.y * 0.5 + CHAR_SIZE * 0.36),
			glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CHAR_SIZE, AppTheme.PAPER_INK
		)
