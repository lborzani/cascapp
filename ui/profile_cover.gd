class_name ProfileCover
extends Control

## A capa do perfil da loja (`Cosmetics`, encaixe `banner`): um degradê com um
## desenho por cima, atrás da foto e do nome. Por código, sem arquivo: as capas
## são poucas e simples, e assim escalam para qualquer tamanho.
##
## Como controle, desenha a capa do próprio `look`. Atrás de um contêiner (que
## não pode ter filho solto por cima dos outros), `paint` desenha no `draw` dele.

var look := {}:
	set(value):
		look = value
		queue_redraw()


func _draw() -> void:
	paint(self, Rect2(Vector2.ZERO, size), Cosmetics.item_of(look, Cosmetics.BANNER))


## Desenha a capa `banner` (um item do catálogo, ou vazio para a superfície de
## sempre) no retângulo, com os cantos arredondados do tema.
static func paint(canvas: CanvasItem, rect: Rect2, banner: Dictionary) -> void:
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
	_pattern(canvas, rect, outline, str(banner.get("pattern", "")))


static func _pattern(canvas: CanvasItem, rect: Rect2, outline: PackedVector2Array, pattern: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	match pattern:
		"stars":
			for i in 40:
				var spot := rect.position + Vector2(rng.randf(), rng.randf()) * rect.size
				if Geometry2D.is_point_in_polygon(spot, outline):
					canvas.draw_circle(spot, rng.randf_range(0.6, 1.8), Color(1, 1, 1, rng.randf_range(0.4, 0.95)))
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
					points.append(Vector2(x, base + sin(step * 0.6 + line) * 4.0))
				canvas.draw_polyline(points, Color(1, 1, 1, 0.18), 2.0, true)


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
