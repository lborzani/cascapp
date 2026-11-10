class_name MessageCard
extends PanelContainer

## Título e detalhe num cartão tingido pela cor da mensagem. É o que a revisão
## e o desafio têm a dizer, e em cinza pequeno embaixo do tabuleiro sumia.

var status := Label.new()
var detail := Label.new()


func _init() -> void:
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 4)
	for label in [status, detail]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(label)
	status.add_theme_font_override("font", AppTheme.font(800))
	status.add_theme_font_size_override("font_size", AppTheme.SIZE_DISPLAY_M)
	detail.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	detail.add_theme_color_override("font_color", AppTheme.TEXT)
	add_child(texts)
	tone(AppTheme.TEXT_DIM)


## O neutro (`TEXT_DIM`) mantém o título em texto claro sobre um cartão discreto.
func tone(color: Color) -> void:
	var neutral := color == AppTheme.TEXT_DIM
	add_theme_stylebox_override("panel", AppTheme.box(
		AppTheme.SURFACE if neutral else Color(color, 0.16), AppTheme.RADIUS,
		AppTheme.LINE_SOFT if neutral else color, 2
	))
	status.add_theme_color_override("font_color", AppTheme.TEXT if neutral else color)
