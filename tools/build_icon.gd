extends SceneTree

## Gera o ícone do app e a imagem da splash em `assets/icon/`: um dado limão
## inclinado, com três pontos, sobre o violeta do tema (`AppTheme.BACKGROUND`).
## Rodar de novo depois de mexer aqui:
##
##   godot --headless --path . --script res://tools/build_icon.gd
##
## O ícone adaptativo do Android tem três camadas de 432 px; o launcher corta
## até 1/3 das bordas, então o dado fica dentro do círculo central de 288 px.

const OUT := "res://assets/icon"
const INK := "#15122b"
const LIME := "#c8f53c"


func _init() -> void:
	_save("role.png", 512, _icon(512))
	_save("role_background.png", 432, _svg(432, '<rect width="432" height="432" fill="%s"/>' % INK))
	_save("role_foreground.png", 432, _svg(432, _die(432, 190, LIME, INK)))
	_save("role_monochrome.png", 432, _svg(432, _die(432, 190, "#ffffff", "")))
	_save("splash.png", 512, _svg(512, _die(512, 220, LIME, INK)))
	quit()


func _icon(size: int) -> String:
	var r := size * 0.23
	return _svg(size, '<rect width="%d" height="%d" rx="%f" fill="%s"/>' % [size, size, r, INK] + _die(size, size * 0.55, LIME, INK))


## O dado de lado `side` no centro do quadro, girado 12°. Sem `pip_color`, os
## pontos são furos (evenodd), para a camada monocromática que o Android tinge.
func _die(size: float, side: float, body: String, pip_color: String) -> String:
	var c := size / 2.0
	var x := c - side / 2.0
	var corner := side * 0.25
	var radius := side * 0.1
	var pips := [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]
	var spread := side * 0.22
	var body_path := _rounded(x, x, side, corner)
	var holes := ""
	var dots := ""
	for p: Vector2 in pips:
		var at := Vector2(c, c) + p * spread
		if pip_color.is_empty():
			holes += " M %f %f a %f %f 0 1 0 %f 0 a %f %f 0 1 0 %f 0 Z" % [at.x - radius, at.y, radius, radius, radius * 2, radius, radius, -radius * 2]
		else:
			dots += '<circle cx="%f" cy="%f" r="%f" fill="%s"/>' % [at.x, at.y, radius, pip_color]
	return '<g transform="rotate(-12 %f %f)"><path fill-rule="evenodd" fill="%s" d="%s%s"/>%s</g>' % [c, c, body, body_path, holes, dots]


func _rounded(x: float, y: float, s: float, r: float) -> String:
	return "M %f %f H %f A %f %f 0 0 1 %f %f V %f A %f %f 0 0 1 %f %f H %f A %f %f 0 0 1 %f %f V %f A %f %f 0 0 1 %f %f Z" % [
		x + r, y, x + s - r, r, r, x + s, y + r,
		y + s - r, r, r, x + s - r, y + s,
		x + r, r, r, x, y + s - r,
		y + r, r, r, x + r, y,
	]


func _svg(size: int, body: String) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [size, size, size, size, body]


func _save(file: String, size: int, svg: String) -> void:
	var image := Image.new()
	var err := image.load_svg_from_string(svg)
	assert(err == OK and image.get_width() == size, file)
	image.save_png("%s/%s" % [OUT, file])
	print("icone: ", file)
