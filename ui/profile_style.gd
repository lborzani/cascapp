class_name ProfileStyle
extends RefCounted

## Onde o visual de perfil da loja (`Cosmetics`) encontra a interface: a cor do
## nome num `Label` ou desenhada à mão (a etiqueta da partida), e o título.

const RAINBOW := preload("res://ui/rainbow_text.gdshader")
const SHINE := preload("res://ui/shine_text.gdshader")
const PIONEER_TEXT := preload("res://ui/pioneer_text.gdshader")
## Um material por shader, criado na primeira vez: todos os nomes dividem o mesmo.
static var _materials := {}
## As cores do conjunto dos testadores (moldura e capa), em ciclo.
const PIONEER: Array[Color] = [Color("3dffd0"), Color("a66bff"), Color("ffd25a")]


## A cor do ciclo dos testadores em `t` (uma volta a cada 1), passando suave de
## uma cor à seguinte.
static func pioneer_color(t: float) -> Color:
	var at := fposmod(t, 1.0) * PIONEER.size()
	var i := int(at)
	return PIONEER[i].lerp(PIONEER[(i + 1) % PIONEER.size()], at - i)


## Pinta o nome de um `Label` com a cor do visual; sem item, não mexe.
static func paint_name(label: Label, look: Dictionary) -> void:
	var item := Cosmetics.item_of(look, Cosmetics.NAME_COLOR)
	if item.is_empty():
		return
	if item.get("rainbow", false):
		label.material = rainbow_material()
	elif item.get("pioneer", false):
		label.material = material_of(PIONEER_TEXT)
	else:
		label.add_theme_color_override("font_color", item["color"])


static func rainbow_material() -> ShaderMaterial:
	return material_of(RAINBOW)


static func material_of(shader: Shader) -> ShaderMaterial:
	if not _materials.has(shader):
		var material := ShaderMaterial.new()
		material.shader = shader
		_materials[shader] = material
	return _materials[shader]


## Desenha um nome com a cor do visual, ou `fallback` sem item. O arco-íris e o
## dos testadores saem letra por letra, como no `Label`. O dos testadores anda
## com `time`, nos mesmos passos do `pioneer_text.gdshader`: quem desenha e quer
## ele mexendo se redesenha (`animated_name`).
static func draw_name(
	canvas: CanvasItem, font: Font, at: Vector2, text: String, width: float, font_size: int,
	fallback: Color, look: Dictionary, time := 0.0
) -> void:
	var item := Cosmetics.item_of(look, Cosmetics.NAME_COLOR)
	var rainbow: bool = item.get("rainbow", false)
	if not rainbow and not item.get("pioneer", false):
		canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, item.get("color", fallback))
		return
	var glint_x := fmod(time, 5.0) * 160.0 - 60.0
	var x := 0.0
	for character in text:
		var advance := font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if width >= 0.0 and x + advance > width:
			break
		var colour := Color.from_hsv(fmod(x / 150.0, 1.0), 0.75, 1.0)
		if not rainbow:
			var middle := x + advance * 0.5
			colour = pioneer_color(middle / 150.0 - time * 0.25).lerp(Color.WHITE, 0.8 * exp(-pow((middle - glint_x) / 14.0, 2.0)))
		canvas.draw_string(font, at + Vector2(x, 0), character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
		x += advance


## O nome do visual se mexe (e quem o desenha à mão precisa se redesenhar).
static func animated_name(look: Dictionary) -> bool:
	return Cosmetics.item_of(look, Cosmetics.NAME_COLOR).get("pioneer", false)


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
	dress_title(label, look)
	return label


## O brilho do título que tem (`shine`); sem ele, não mexe.
static func dress_title(label: Label, look: Dictionary) -> void:
	if not Cosmetics.item_of(look, Cosmetics.TITLE).get("shine", false):
		return
	label.material = material_of(SHINE)
