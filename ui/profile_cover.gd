class_name ProfileCover
extends Control

## A capa do perfil da loja (`Cosmetics`, encaixe `banner`): um degradê com um
## desenho por cima. Por código, sem arquivo: as capas são poucas e simples, e
## assim escalam do quadradinho da loja à tela inteira do perfil.
##
## Desenha sempre o retângulo inteiro, sem cantos: onde ela precisa de canto
## arredondado (o cartão e as amostras da loja), quem recorta é o painel em volta
## (`rounded`), e o recorte do `StyleBoxFlat` sai suavizado. O degradê é feito de
## cores por vértice e os desenhos com `antialiased`, para nada sair serrilhado.
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
## Escurece a parte de baixo, para o texto em cima dela continuar legível quando
## a capa é o fundo da tela inteira (o perfil do amigo).
var fade := false:
	set(value):
		fade = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_process(animated(Cosmetics.item_of(look, Cosmetics.BANNER)))


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	paint(self, rect, Cosmetics.item_of(look, Cosmetics.BANNER), time)
	if fade:
		var clear := Color(AppTheme.BACKGROUND, 0.0)
		var dim := Color(AppTheme.BACKGROUND, 0.62)
		_vertical(self, Rect2(rect.position + Vector2(0, rect.size.y * 0.18), rect.size * Vector2(1, 0.82)), clear, dim)


static func animated(banner: Dictionary) -> bool:
	return str(banner.get("pattern", "")) in ANIMATED


## A capa do visual dentro de um painel de cantos arredondados que a recorta.
static func rounded(look_value: Dictionary, radius: int) -> Panel:
	var panel := Panel.new()
	panel.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	panel.add_theme_stylebox_override("panel", AppTheme.box(Color.WHITE, radius))
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	var cover := ProfileCover.new()
	cover.look = look_value
	cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	panel.add_child(cover)
	return panel


## Desenha a capa `banner` (um item do catálogo, ou vazio para a superfície de
## sempre) no retângulo inteiro.
static func paint(canvas: CanvasItem, rect: Rect2, banner: Dictionary, time := 0.0) -> void:
	if banner.is_empty():
		canvas.draw_rect(rect, AppTheme.SURFACE)
		return
	var colors: Array = banner["colors"]
	var steps := colors.size() - 1
	for i in steps:
		var band := Rect2(rect.position + Vector2(0, rect.size.y * i / steps), Vector2(rect.size.x, rect.size.y / steps))
		_vertical(canvas, band, colors[i], colors[i + 1])
	_pattern(canvas, rect, str(banner.get("pattern", "")), time)


## Um retângulo em degradê de cima para baixo, pelas cores dos vértices: liso,
## sem as faixas de um degradê em pedaços.
static func _vertical(canvas: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	canvas.draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)


static func _pattern(canvas: CanvasItem, rect: Rect2, pattern: String, time: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# A "faixa" de um desenho que não deve esticar com a altura da tela: no
	# cartão é a altura dele; na tela inteira, uma faixa do alto.
	var strip := minf(rect.size.y, rect.size.x * 0.6)
	match pattern:
		"stars":
			# Tantas estrelas quanto cabem: o céu da tela inteira não fica vazio.
			var count := clampi(int(rect.get_area() / 700.0), 24, 260)
			for i in count:
				var spot := rect.position + Vector2(rng.randf(), rng.randf()) * rect.size
				var radius := rng.randf_range(0.6, 1.8)
				var brightness := rng.randf_range(0.4, 0.95)
				# Cada estrela pisca no próprio ritmo.
				var twinkle := 0.55 + 0.45 * sin(time * rng.randf_range(1.5, 3.5) + i * 1.3)
				canvas.draw_circle(spot, radius, Color(1, 1, 1, brightness * twinkle), true, -1.0, true)
		"sun":
			var sun := rect.position + Vector2(rect.size.x * 0.8, strip * 0.72)
			canvas.draw_circle(sun, strip * 0.32, Color(1.0, 0.86, 0.45, 0.18), true, -1.0, true)
			canvas.draw_circle(sun, strip * 0.22, Color(1.0, 0.86, 0.45, 0.85), true, -1.0, true)
		"felt":
			# As marcas da tabela da sinuca, em losango, em cima e embaixo.
			for i in range(1, 8):
				var x := rect.position.x + rect.size.x * i / 8.0
				for y in [rect.position.y + 6.0, rect.end.y - 6.0]:
					var s := 3.0
					var diamond := PackedVector2Array([Vector2(x, y - s), Vector2(x + s, y), Vector2(x, y + s), Vector2(x - s, y)])
					canvas.draw_colored_polygon(diamond, Color(1, 1, 1, 0.45))
					canvas.draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(1, 1, 1, 0.45), 1.0, true)
		"checker":
			var cell := maxf(10.0, minf(rect.size.y / 4.0, rect.size.x / 8.0))
			for row in int(ceil(rect.size.y / cell)):
				for column in int(ceil(rect.size.x / cell)):
					if (row + column) % 2 == 1:
						canvas.draw_rect(Rect2(rect.position + Vector2(column, row) * cell, Vector2.ONE * cell), Color(1, 1, 1, 0.07))
		"waves":
			var spacing := clampf(rect.size.y / 5.0, 14.0, 40.0)
			var lines := int(rect.size.y / spacing)
			for line in lines:
				var points := PackedVector2Array()
				var base := rect.position.y + spacing * (line + 1.0)
				for step in 49:
					var x := rect.position.x - 4.0 + (rect.size.x + 8.0) * step / 48.0
					points.append(Vector2(x, base + sin(step * 0.4 + line - time * 2.0) * 4.0))
				canvas.draw_polyline(points, Color(1, 1, 1, 0.18), 2.0, true)
		"aurora":
			# Três cortinas de luz ondulando devagar, cada uma de uma cor.
			# Mais alta que a faixa dos outros desenhos: na tela inteira as cortinas
			# se espalham, em vez de se amontoar atrás do nome.
			var sky := minf(rect.size.y, rect.size.x * 1.2)
			for band in 3:
				var colour: Color = [Color("3dffa8"), Color("38c9ff"), Color("b56bff")][band]
				var points := PackedVector2Array()
				# As pontas ficam fora do retângulo, senão o corte da linha grossa aparece.
				for step in 61:
					var x := rect.position.x - rect.size.x * 0.1 + rect.size.x * 1.2 * step / 60.0
					var y := rect.position.y + sky * (0.3 + band * 0.2)
					y += sin(step * 0.17 + band * 1.7 + time * (0.8 + band * 0.3)) * sky * 0.07
					points.append(Vector2(x, y))
				canvas.draw_polyline(points, Color(colour, 0.13), sky * 0.15, true)
				canvas.draw_polyline(points, Color(colour, 0.35), sky * 0.03, true)
