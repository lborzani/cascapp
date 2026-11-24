class_name ProfileCover
extends Control

## A capa do perfil da loja (`Cosmetics`, encaixe `banner`): um degradê com um
## desenho por cima, atrás da foto e do nome. Por código, sem arquivo: as capas
## são poucas e simples, e assim escalam para qualquer tamanho.
##
## Como controle, desenha a capa do próprio `look`. Atrás de um contêiner (que
## não pode ter filho solto por cima dos outros), `behind` desenha no `draw` dele.
##
## Três se mexem: as estrelas da noite piscam, as ondas andam e a aurora ondula.

const ANIMATED := ["stars", "waves", "aurora"]

var look := {}:
	set(value):
		look = value
		set_process(animated(Cosmetics.item_of(value, Cosmetics.BANNER)))
		queue_redraw()
## O relógio da capa animada, em segundos.
var time := 0.0


func _ready() -> void:
	set_process(animated(Cosmetics.item_of(look, Cosmetics.BANNER)))


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	paint(self, Rect2(Vector2.ZERO, size), Cosmetics.item_of(look, Cosmetics.BANNER), time)


static func animated(banner: Dictionary) -> bool:
	return str(banner.get("pattern", "")) in ANIMATED


## Desenha a capa `banner` atrás de um contêiner, no `draw` dele; animada, um
## relógio filho redesenha o contêiner a cada quadro.
static func behind(container: Control, banner: Dictionary) -> void:
	var clock := Clock.new()
	clock.target = container
	container.add_child(clock)
	clock.set_process(animated(banner))
	container.draw.connect(func() -> void:
		paint(container, Rect2(Vector2.ZERO, container.size), banner, clock.time)
	)


class Clock:
	extends Node

	var target: CanvasItem = null
	var time := 0.0

	func _process(delta: float) -> void:
		time += delta
		target.queue_redraw()


## Desenha a capa `banner` (um item do catálogo, ou vazio para a superfície de
## sempre) no retângulo, com os cantos arredondados do tema.
static func paint(canvas: CanvasItem, rect: Rect2, banner: Dictionary, time := 0.0) -> void:
	var radius := AppTheme.RADIUS_LARGE
	if banner.is_empty():
		canvas.draw_style_box(AppTheme.box(AppTheme.SURFACE, radius), rect)
		return
	var colors: Array = banner["colors"]
	# O degradê em faixas horizontais finas, dentro do contorno arredondado.
	var outline := _rounded(rect, radius)
	var bands := 24
	for i in bands:
		var t0 := float(i) / bands
		var t1 := float(i + 1) / bands
		var strip := Rect2(rect.position.x, rect.position.y + rect.size.y * t0, rect.size.x, rect.size.y * (t1 - t0) + 1.0)
		var clipped := Geometry2D.intersect_polygons(outline, _box(strip))
		for piece in clipped:
			canvas.draw_colored_polygon(piece, _ramp(colors, (t0 + t1) * 0.5))
	_pattern(canvas, rect, outline, str(banner.get("pattern", "")), time)


static func _pattern(canvas: CanvasItem, rect: Rect2, outline: PackedVector2Array, pattern: String, time: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	match pattern:
		"stars":
			for i in 40:
				var spot := rect.position + Vector2(rng.randf(), rng.randf()) * rect.size
				var radius := rng.randf_range(0.6, 1.8)
				var brightness := rng.randf_range(0.4, 0.95)
				# Cada estrela pisca no próprio ritmo.
				var twinkle := 0.55 + 0.45 * sin(time * rng.randf_range(1.5, 3.5) + i * 1.3)
				if Geometry2D.is_point_in_polygon(spot, outline):
					canvas.draw_circle(spot, radius, Color(1, 1, 1, brightness * twinkle))
		"sun":
			var sun := rect.position + Vector2(rect.size.x * 0.8, rect.size.y * 0.72)
			canvas.draw_circle(sun, rect.size.y * 0.22, Color(1.0, 0.86, 0.45, 0.85))
		"felt":
			# As marcas da tabela da sinuca, em losango, na borda de cima e de baixo.
			for i in range(1, 8):
				var x := rect.position.x + rect.size.x * i / 8.0
				for y in [rect.position.y + 6.0, rect.end.y - 6.0]:
					var s := 3.0
					canvas.draw_colored_polygon(PackedVector2Array([
						Vector2(x, y - s), Vector2(x + s, y), Vector2(x, y + s), Vector2(x - s, y),
					]), Color(1, 1, 1, 0.45))
		"checker":
			var cell := maxf(10.0, rect.size.y / 4.0)
			var columns := int(ceil(rect.size.x / cell))
			var rows := int(ceil(rect.size.y / cell))
			for row in rows:
				for column in columns:
					if (row + column) % 2 == 0:
						continue
					var square := Rect2(rect.position + Vector2(column, row) * cell, Vector2.ONE * cell)
					for piece in Geometry2D.intersect_polygons(outline, _box(square)):
						canvas.draw_colored_polygon(piece, Color(1, 1, 1, 0.07))
		"waves":
			for line in 4:
				var points := PackedVector2Array()
				var base := rect.position.y + rect.size.y * (0.3 + line * 0.18)
				for step in 33:
					var x := rect.position.x + rect.size.x * step / 32.0
					points.append(Vector2(x, base + sin(step * 0.6 + line - time * 2.0) * 4.0))
				canvas.draw_polyline(points, Color(1, 1, 1, 0.18), 2.0, true)


		"aurora":
			# Três cortinas de luz ondulando devagar, cada uma de uma cor.
			for band in 3:
				var colour: Color = [Color("3dffa8"), Color("38c9ff"), Color("b56bff")][band]
				var points := PackedVector2Array()
				for step in 41:
					var x := rect.position.x + rect.size.x * step / 40.0
					var y := rect.position.y + rect.size.y * (0.32 + band * 0.16)
					y += sin(step * 0.25 + band * 1.7 + time * (0.8 + band * 0.3)) * rect.size.y * 0.1
					points.append(Vector2(x, y))
				# Faixas como polígonos recortados pelo contorno, senão a ponta delas
				# vaza pelos cantos arredondados.
				for layer: Array in [[0.11, 0.16], [0.025, 0.45]]:
					var ribbon := _ribbon(points, rect.size.y * float(layer[0]))
					for piece in Geometry2D.intersect_polygons(outline, ribbon):
						canvas.draw_colored_polygon(piece, Color(colour, layer[1]))


## Uma faixa de altura `2 * half` em volta de uma linha que anda da esquerda para a
## direita.
static func _ribbon(line: PackedVector2Array, half: float) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point in line:
		polygon.append(point - Vector2(0, half))
	for i in range(line.size() - 1, -1, -1):
		polygon.append(line[i] + Vector2(0, half))
	return polygon


static func _ramp(colors: Array, t: float) -> Color:
	var scaled := clampf(t, 0.0, 1.0) * (colors.size() - 1)
	var index := mini(int(scaled), colors.size() - 2)
	return (colors[index] as Color).lerp(colors[index + 1], scaled - index)


static func _box(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func _rounded(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var corners := [
		[rect.position + Vector2(r, r), PI], [Vector2(rect.end.x - r, rect.position.y + r), PI * 1.5],
		[rect.end - Vector2(r, r), 0.0], [Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
	]
	for corner: Array in corners:
		for step in 7:
			points.append(corner[0] + Vector2.from_angle(corner[1] + PI * 0.5 * step / 6.0) * r)
	return points
