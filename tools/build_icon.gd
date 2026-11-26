extends SceneTree

## Gera o ícone do app e a imagem da splash em `assets/icon/`: a galera em roda.
## Oito pessoas vistas de cima, ombro com ombro, nas cores dos jogos
## (`AppTheme.GAME_COLORS`), formam o C de Cascão; a bola de vôlei limão fecha a
## roda. O fundo é o violeta do tema (`AppTheme.BACKGROUND`).
## Rodar de novo depois de mexer aqui:
##
##   godot --headless --path . --script res://tools/build_icon.gd
##
## O ícone adaptativo do Android tem três camadas de 432 px; o launcher corta
## até 1/3 das bordas, então a roda fica dentro do círculo central de 288 px.
## O vão em volta das cabeças e as costuras da bola são recortes (máscara), não
## tinta: funcionam em qualquer fundo e na camada monocromática que o Android
## tinge.

const OUT := "res://assets/icon"
const INK := "#15122b"
const LIME := "#c8f53c"
## A roda é desenhada num quadro de 512 com centro em (236, 256). Com a bola, o
## desenho todo se centra em (243, 256) e cabe num raio de 195.
const CENTER := Vector2(236, 256)
const ART_CENTER := Vector2(243, 256)
const ART_RADIUS := 195.0
const BALL := Vector2(382, 256)
## Uma das três costuras da bola, num círculo de raio 100.
const SEAM := "M0 0 C 40 0 70 -30 75 -66 M-18.5 -21.6 C 14 -26 42 -52 46 -89"


func _init() -> void:
	_save("role.png", 512, _icon(512))
	_save("role_background.png", 432, _svg(432, '<rect width="432" height="432" fill="%s"/>' % INK))
	_save("role_foreground.png", 432, _svg(432, _roda(432, 144, "")))
	_save("role_monochrome.png", 432, _svg(432, _roda(432, 144, "#ffffff")))
	_save("splash.png", 512, _svg(512, _roda(512, 200, "")))
	quit()


func _icon(size: int) -> String:
	var r := size * 0.23
	return _svg(size, '<rect width="%d" height="%d" rx="%f" fill="%s"/>' % [size, size, r, INK] + _roda(size, size * 0.38, ""))


## A roda centrada no quadro `size`, cabendo no raio `radius`. Com `tint`, tudo
## sai nessa cor (camada monocromática); sem, cada pessoa tem a cor de um jogo.
func _roda(size: float, radius: float, tint: String) -> String:
	var colors := AppTheme.GAME_COLORS.values()
	var people := ""
	var cuts := ""
	for i in colors.size():
		var angle := deg_to_rad(lerpf(55.0, 305.0, i / 7.0))
		var body := CENTER + Vector2.from_angle(angle) * 148.0
		var head := CENTER + Vector2.from_angle(angle) * 114.0
		var color: String = tint if not tint.is_empty() else "#" + colors[i].to_html(false)
		people += '<ellipse cx="%f" cy="%f" rx="47" ry="24" transform="rotate(%f %f %f)" fill="%s"/>' % [body.x, body.y, rad_to_deg(angle) + 90.0, body.x, body.y, color]
		people += '<circle cx="%f" cy="%f" r="26" fill="%s"/>' % [head.x, head.y, color]
		cuts += '<circle cx="%f" cy="%f" r="26" fill="none" stroke="black" stroke-width="9"/>' % [head.x, head.y]
	people += '<circle cx="%f" cy="%f" r="56" fill="%s"/>' % [BALL.x, BALL.y, tint if not tint.is_empty() else LIME]
	for turn in [0, 120, 240]:
		cuts += '<path fill="none" stroke="black" stroke-width="13" stroke-linecap="round" transform="translate(%f %f) scale(0.56) rotate(%d)" d="%s"/>' % [BALL.x, BALL.y, turn, SEAM]
	var fit := "translate(%f %f) scale(%f) translate(%f %f)" % [size / 2.0, size / 2.0, radius / ART_RADIUS, -ART_CENTER.x, -ART_CENTER.y]
	var mask := '<mask id="cut" maskUnits="userSpaceOnUse" x="0" y="0" width="512" height="512"><rect width="512" height="512" fill="white"/>%s</mask>' % cuts
	return '<defs>%s</defs><g transform="%s"><g mask="url(#cut)">%s</g></g>' % [mask, fit, people]


func _svg(size: int, body: String) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [size, size, size, size, body]


func _save(file: String, size: int, svg: String) -> void:
	var image := Image.new()
	var err := image.load_svg_from_string(svg)
	assert(err == OK and image.get_width() == size, file)
	image.save_png("%s/%s" % [OUT, file])
	print("icone: ", file)
