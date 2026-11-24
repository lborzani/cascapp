class_name ProfileStyle
extends RefCounted

## Onde o visual de perfil da loja (`Cosmetics`) encontra a interface: a cor do
## nome num `Label` ou desenhada à mão (a etiqueta da partida), e o título.

const RAINBOW := preload("res://ui/rainbow_text.gdshader")
static var _rainbow_material: ShaderMaterial = null


## Pinta o nome de um `Label` com a cor do visual; sem item, não mexe.
static func paint_name(label: Label, look: Dictionary) -> void:
	var item := Cosmetics.item_of(look, Cosmetics.NAME_COLOR)
	if item.is_empty():
		return
	if item.get("rainbow", false):
		label.material = rainbow_material()
	else:
		label.add_theme_color_override("font_color", item["color"])


static func rainbow_material() -> ShaderMaterial:
	if _rainbow_material == null:
		_rainbow_material = ShaderMaterial.new()
		_rainbow_material.shader = RAINBOW
	return _rainbow_material


## Desenha um nome com a cor do visual, ou `fallback` sem item. O arco-íris sai
## letra por letra, como no `Label`.
static func draw_name(
	canvas: CanvasItem, font: Font, at: Vector2, text: String, width: float, font_size: int,
	fallback: Color, look: Dictionary
) -> void:
	var item := Cosmetics.item_of(look, Cosmetics.NAME_COLOR)
	if not item.get("rainbow", false):
		canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, item.get("color", fallback))
		return
	var x := 0.0
	for character in text:
		var advance := font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if width >= 0.0 and x + advance > width:
			break
		var hue := fmod(x / 150.0, 1.0)
		canvas.draw_string(font, at + Vector2(x, 0), character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.from_hsv(hue, 0.75, 1.0))
		x += advance


## O título do visual num `Label` pronto para pôr abaixo do nome, ou `null`.
static func title_label(look: Dictionary) -> Label:
	var text := Cosmetics.title_of(look)
	if text.is_empty():
		return null
	var label := Label.new()
	label.name = "Title"
	label.text = text
	label.theme_type_variation = &"Caption"
	label.add_theme_color_override("font_color", AppTheme.ACCENT)
	return label
