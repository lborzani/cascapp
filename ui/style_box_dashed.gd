class_name StyleBoxDashed
extends StyleBox

## Contorno tracejado com cantos arredondados — a linha de giz do tema Boteco.
##
## `StyleBoxFlat` não tem traço: a borda dele é sempre contínua. O tracejado é a
## assinatura do tema em três lugares (painel secundário, separador, borda de
## folha), e desenhá-lo no `_draw` de cada tela seria repetir a mesma conta em
## vinte arquivos. Como `StyleBox`, ele entra no tema e em qualquer `Control`.
##
## A geometria mora em duas funções estáticas puras — o contorno e o corte em
## traços — porque é a parte que dá para testar sem GPU.

## Pontos por quarto de círculo. Oito já não mostram quina no tamanho de um botão.
const CORNER_STEPS := 8

@export var bg_color := Color(0, 0, 0, 0)
@export var border_color := Color(1, 1, 1, 0.45)
@export var border_width := 1.5
@export var corner_radius := 10.0
@export var dash := 6.0
@export var gap := 4.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if bg_color.a > 0.0:
		RenderingServer.canvas_item_add_polygon(
			to_canvas_item, outline_points(rect, corner_radius), PackedColorArray([bg_color])
		)
	if border_width <= 0.0 or border_color.a <= 0.0:
		return
	# O traço anda por dentro da borda, como o do `StyleBoxFlat`: centrado nela,
	# metade sairia do retângulo e seria cortada por quem recorta o conteúdo.
	var half := border_width * 0.5
	var path := outline_points(rect.grow(-half), maxf(corner_radius - half, 0.0))
	var segments := dash_segments(path, dash, gap)
	for i in range(0, segments.size(), 2):
		RenderingServer.canvas_item_add_line(
			to_canvas_item, segments[i], segments[i + 1], border_color, border_width, true
		)


## O contorno fechado de um retângulo arredondado, no sentido horário da tela,
## começando no fim da aresta de cima. Sem raio, um ponto por canto: pontos
## repetidos quebrariam a triangulação do preenchimento.
static func outline_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var steps := CORNER_STEPS if r > 0.0 else 0
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	var points := PackedVector2Array()
	for corner: Array in corners:
		var center: Vector2 = corner[0]
		var start: float = corner[1]
		for step in steps + 1:
			var angle := start + (PI * 0.5) * (float(step) / maxf(steps, 1))
			points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points


## Corta um contorno fechado em traços: pares de pontos, início e fim de cada
## pedaço desenhado. Um traço que dobra um canto sai em mais de um pedaço, e
## visualmente continua sendo um traço só.
##
## Sem vão, devolve as arestas inteiras — e não por economia: com vão zero, o
## laço de alternância trocaria de estado sem andar nada e nunca terminaria.
static func dash_segments(points: PackedVector2Array, dash: float, gap: float) -> PackedVector2Array:
	var segments := PackedVector2Array()
	if points.size() < 2 or dash <= 0.0:
		return segments
	var count := points.size()
	if gap <= 0.0:
		for i in count:
			segments.append(points[i])
			segments.append(points[(i + 1) % count])
		return segments
	var drawing := true
	var left := dash
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		var length := a.distance_to(b)
		var walked := 0.0
		while length - walked > 0.0001:
			var take := minf(left, length - walked)
			if drawing:
				segments.append(a.lerp(b, walked / length))
				segments.append(a.lerp(b, (walked + take) / length))
			walked += take
			left -= take
			if left <= 0.0001:
				drawing = not drawing
				left = dash if drawing else gap
	return segments
