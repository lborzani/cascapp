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
## Quatro se mexem: as estrelas da noite piscam, as ondas andam, a aurora ondula e
## o céu dos pioneiros tem nebulosas, constelações com pulsos e estrelas cadentes.

const ANIMATED := ["stars", "waves", "aurora", "pioneer"]
## Quantos segundos cada constelação fica na capa deitada do céu dos pioneiros.
const CYCLE := 6.0

## As constelações da capa dos testadores, com as posições reais do céu (ascensão
## reta e declinação projetadas em volta do centro de cada uma, vista de baixo:
## leste à esquerda, sul embaixo). Cada estrela é `[x, y, magnitude, vermelha]`,
## com x e y de -0,5 a 0,5 na maior medida da constelação; `lines` liga estrelas
## pelo índice; `place` é onde ela fica na capa em pé (centro em fração do
## retângulo, tamanho em fração da meia largura). Deitada, uma por vez no meio.
const CONSTELLATIONS := [
	{
		# Cruzeiro do Sul: Acrux, Mimosa, Gacrux, Imai, Ginan.
		"stars": [[0.101, 0.500, 0.8, false], [-0.342, -0.069, 1.2, false], [0.006, -0.500, 1.6, true], [0.342, -0.226, 2.8, false], [0.211, 0.049, 3.6, false]],
		"lines": [Vector2i(0, 2), Vector2i(1, 3)],
		"place": Vector3(0.83, 0.14, 0.5),
	},
	{
		# Sagitário (o bule): Kaus Australis, Kaus Media, Kaus Borealis, φ, Nunki, τ, Ascella, Alnasl.
		"stars": [[0.200, 0.335, 1.8, false], [0.252, -0.005, 2.7, false], [0.138, -0.335, 2.8, false], [-0.152, -0.217, 3.2, false], [-0.309, -0.269, 2.0, false], [-0.500, -0.167, 3.3, false], [-0.429, -0.001, 2.6, false], [0.500, 0.039, 3.0, false]],
		"lines": [Vector2i(7, 1), Vector2i(7, 0), Vector2i(1, 0), Vector2i(1, 2), Vector2i(2, 3), Vector2i(1, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 3), Vector2i(6, 0)],
		"place": Vector3(0.26, 0.84, 0.75),
	},
	{
		# Aquário: Sadalmelik, Sadalsuud, Albali, Sadachbia, ζ, η, π, λ, Skat, θ, ι.
		"stars": [[-0.115, -0.218, 3.0, false], [0.155, -0.052, 2.9, false], [0.500, 0.072, 3.8, false], [-0.240, -0.185, 3.8, false], [-0.297, -0.228, 3.6, false], [-0.348, -0.225, 4.0, false], [-0.268, -0.272, 4.6, false], [-0.484, 0.011, 3.7, false], [-0.500, 0.272, 3.3, false], [-0.202, 0.018, 4.2, false], [-0.120, 0.210, 4.3, false]],
		"lines": [Vector2i(2, 1), Vector2i(1, 0), Vector2i(0, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(0, 9), Vector2i(9, 7), Vector2i(7, 8), Vector2i(1, 10)],
		"place": Vector3(0.74, 0.52, 0.8),
	},
	{
		# Leão: Regulus, η, Algieba, Adhafera, μ, ε, Zosma, Chertan, Denebola.
		"stars": [[0.317, 0.241, 1.4, false], [0.326, 0.077, 3.5, false], [0.223, -0.029, 2.0, true], [0.250, -0.152, 3.4, false], [0.444, -0.241, 3.9, false], [0.500, -0.164, 3.0, false], [-0.216, -0.053, 2.6, false], [-0.217, 0.122, 3.3, false], [-0.500, 0.152, 2.1, false]],
		"lines": [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(2, 6), Vector2i(6, 8), Vector2i(8, 7), Vector2i(7, 0)],
		"place": Vector3(0.27, 0.55, 0.8),
	},
	{
		# Gêmeos: Castor, Pollux, Alhena, Tejat, Propus, Mebsuta, Wasat, ξ, τ, θ, κ, υ, λ, Mekbuda.
		"stars": [[-0.375, -0.402, 1.6, false], [-0.491, -0.218, 1.1, true], [0.243, 0.334, 1.9, false], [0.403, 0.044, 2.9, true], [0.491, 0.044, 3.3, true], [0.176, -0.081, 3.0, false], [-0.217, 0.069, 3.5, false], [0.161, 0.500, 3.4, false], [-0.120, -0.324, 4.4, false], [0.079, -0.500, 3.6, false], [-0.482, -0.046, 3.6, false], [-0.389, -0.165, 4.1, false], [-0.195, 0.327, 3.6, false], [-0.044, 0.136, 3.9, false]],
		"lines": [Vector2i(0, 8), Vector2i(8, 9), Vector2i(8, 5), Vector2i(5, 3), Vector2i(3, 4), Vector2i(1, 11), Vector2i(11, 6), Vector2i(6, 13), Vector2i(13, 2), Vector2i(6, 12), Vector2i(12, 7), Vector2i(1, 10), Vector2i(8, 11)],
		"place": Vector3(0.2, 0.14, 0.55),
	},
	{
		# Órion: Betelgeuse, Bellatrix, Mintaka, Alnilam, Alnitak, Saiph, Rigel, Meissa.
		"stars": [[-0.259, -0.371, 0.5, true], [0.124, -0.317, 1.6, false], [0.036, 0.022, 2.2, false], [-0.018, 0.068, 1.7, false], [-0.075, 0.106, 1.8, false], [-0.165, 0.500, 2.1, false], [0.259, 0.425, 0.1, false], [-0.003, -0.500, 3.4, false]],
		"lines": [Vector2i(7, 0), Vector2i(7, 1), Vector2i(0, 1), Vector2i(0, 4), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(2, 6)],
		"place": Vector3(0.75, 0.84, 0.7),
	},
]

var look := {}:
	set(value):
		look = value
		set_process(animated(Cosmetics.item_of(value, Cosmetics.BANNER)))
		queue_redraw()
## O relógio da capa animada, em segundos.
var time := 0.0
var _since := 0.0
## Escurece a parte de baixo, para o texto em cima dela continuar legível quando
## a capa é o fundo da tela inteira (o perfil do amigo).
var fade := false:
	set(value):
		fade = value
		queue_redraw()
## Escurece a capa inteira por igual (0 a 1): atrás de um cartão pequeno, com
## nome e botões por cima, a capa é fundo e não pode brigar com eles.
var shade := 0.0:
	set(value):
		shade = value
		queue_redraw()
## O quanto a capa escurece atrás dos cartões (lista de amigos, etiqueta da
## partida, aba Você).
const CARD_SHADE := 0.38


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_process(animated(Cosmetics.item_of(look, Cosmetics.BANNER)))


func _process(delta: float) -> void:
	time += delta
	_since += delta
	# Redesenhar custa o desenho inteiro de novo; 30 vezes por segundo basta para
	# o movimento, e o celular de 90 ou 120 Hz não paga três ou quatro por quadro.
	if _since >= Coaster.REDRAW_STEP:
		_since = 0.0
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	paint(self, rect, Cosmetics.item_of(look, Cosmetics.BANNER), time)
	if shade > 0.0:
		draw_rect(rect, Color(AppTheme.BACKGROUND, shade))
	if fade:
		var clear := Color(AppTheme.BACKGROUND, 0.0)
		var dim := Color(AppTheme.BACKGROUND, 0.62)
		_vertical(self, Rect2(rect.position + Vector2(0, rect.size.y * 0.18), rect.size * Vector2(1, 0.82)), clear, dim)


static func animated(banner: Dictionary) -> bool:
	return str(banner.get("pattern", "")) in ANIMATED


## A capa do visual dentro de um painel de cantos arredondados que a recorta.
static func rounded(look_value: Dictionary, radius: int, shade_value := 0.0) -> Panel:
	var panel := Panel.new()
	panel.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	panel.add_theme_stylebox_override("panel", AppTheme.box(Color.WHITE, radius))
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	var cover := ProfileCover.new()
	cover.look = look_value
	cover.shade = shade_value
	cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	panel.add_child(cover)
	return panel


## Põe a capa do visual atrás do conteúdo de um cartão (`PanelContainer`): o
## cartão perde o próprio fundo, a capa recortada vem primeiro e o conteúdo vai
## por cima, com as mesmas margens do `AppTheme.box`. Sem capa no visual, o
## conteúdo entra direto, e o cartão fica como era.
static func dress_card(card: PanelContainer, content: Control, look_value: Dictionary, radius: int) -> void:
	if Cosmetics.item_of(look_value, Cosmetics.BANNER).is_empty():
		card.add_child(content)
		return
	var empty := StyleBoxEmpty.new()
	card.add_theme_stylebox_override("panel", empty)
	var cover := rounded(look_value, radius, CARD_SHADE)
	cover.name = "Cover"
	card.add_child(cover)
	var pad := MarginContainer.new()
	pad.mouse_filter = MOUSE_FILTER_PASS
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 18)
	for side: String in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	pad.add_child(content)
	card.add_child(pad)


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
		"pioneer":
			_pioneer(canvas, rect, rng, time)


## O degradê redondo das nebulosas: branco no meio, transparente na borda.
static var _glow_texture: GradientTexture2D = null


static func _glow() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color.WHITE)
		gradient.set_color(1, Color(1, 1, 1, 0))
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(0.5, 0.0)
		_glow_texture.width = 128
		_glow_texture.height = 128
	return _glow_texture


## A capa dos testadores: três nebulosas que respiram e derivam nas cores do
## conjunto (`ProfileStyle.PIONEER`), poeira de estrelas, seis constelações de
## verdade (`CONSTELLATIONS`) cujas linhas levam pulsos de luz de estrela em
## estrela e, de tempos em tempos, duas estrelas cadentes.
static func _pioneer(canvas: CanvasItem, rect: Rect2, rng: RandomNumberGenerator, time: float) -> void:
	var sky := minf(rect.size.y, rect.size.x * 1.2)
	for cloud in 3:
		var drift := Vector2(sin(time * 0.21 + cloud * 2.0), cos(time * 0.17 + cloud * 1.3)) * sky * 0.08
		var spot := rect.position + Vector2(rect.size.x * (0.18 + cloud * 0.32), sky * (0.3 + 0.25 * (cloud % 2))) + drift
		var tint := ProfileStyle.pioneer_color(cloud / 3.0)
		var breath := 0.5 + 0.5 * sin(time * 0.6 + cloud * 2.4)
		# Uma mancha de bordas macias: um quadrado com o degradê redondo. Eram doze
		# discos empilhados, e na tela inteira do celular isso derrubava os quadros.
		var reach := sky * 0.5
		canvas.draw_texture_rect(_glow(), Rect2(spot - Vector2.ONE * reach, Vector2.ONE * reach * 2.0), false, Color(tint, 0.22 + 0.14 * breath))

	var dust := clampi(int(rect.get_area() / 1100.0), 20, 200)
	for i in dust:
		var at := rect.position + Vector2(rng.randf(), rng.randf()) * rect.size
		var twinkle := 0.45 + 0.55 * sin(time * rng.randf_range(1.2, 3.2) + i * 0.9)
		# Sem antialias: num ponto de um pixel ele só custa vértices.
		canvas.draw_circle(at, rng.randf_range(0.5, 1.3), Color(1, 1, 1, 0.55 * twinkle))

	# Em pé (tela cheia), as seis no céu, em duas colunas. Deitada (cartão, loja),
	# seis juntas viram borrão: uma por vez, no meio, trocando a cada `CYCLE`
	# segundos. Ela acende com as linhas se traçando de estrela em estrela e
	# apaga antes da próxima.
	if rect.size.y > rect.size.x * 1.1:
		for constellation: Dictionary in CONSTELLATIONS:
			var place: Vector3 = constellation["place"]
			_constellation(canvas, constellation, rect.position + Vector2(place.x, place.y) * rect.size, rect.size.x * 0.5 * place.z, time, 1.0, 1.0)
	else:
		var turn := fposmod(time, CYCLE) / CYCLE
		var shown: Dictionary = CONSTELLATIONS[int(time / CYCLE) % CONSTELLATIONS.size()]
		var alpha := smoothstep(0.0, 0.12, turn) * (1.0 - smoothstep(0.85, 1.0, turn))
		_constellation(canvas, shown, rect.get_center(), minf(rect.size.y, rect.size.x * 0.6) * 0.82, time, alpha, smoothstep(0.0, 0.35, turn))

	# As cadentes: cada uma cruza o céu em 0,9 s, num ciclo de 3,5 s, partindo de
	# um ponto diferente a cada volta.
	var heading := Vector2(-1.0, 0.45).normalized()
	for shot in 2:
		var clock := time + shot * 1.75
		var local := fposmod(clock, 3.5) / 0.9
		if local >= 1.0:
			continue
		var lap := floorf(clock / 3.5)
		var start := rect.position + Vector2(
			rect.size.x * (0.35 + 0.65 * fposmod(lap * 0.618 + shot * 0.3, 1.0)),
			sky * 0.5 * fposmod(lap * 0.414 + shot * 0.5, 1.0)
		)
		var head := start + heading * local * sky * 0.9
		var alpha := sin(local * PI)
		canvas.draw_polyline_colors(
			PackedVector2Array([head - heading * sky * 0.3, head]),
			PackedColorArray([Color(1, 1, 1, 0.0), Color(1.0, 0.95, 0.8, alpha)]), 2.0, true
		)
		canvas.draw_circle(head, 2.2, Color(1, 1, 1, alpha), true, -1.0, true)


## Uma constelação de `CONSTELLATIONS` centrada em `middle`, com `extent` de lado
## na maior medida. `alpha` apaga tudo junto; `reveal` (0 a 1) é o quanto das
## linhas já se traçou, de uma estrela à outra.
static func _constellation(
	canvas: CanvasItem, constellation: Dictionary, middle: Vector2, extent: float, time: float, alpha: float, reveal: float
) -> void:
	if alpha <= 0.0:
		return
	var stars := PackedVector2Array()
	for star: Array in constellation["stars"]:
		stars.append(middle + Vector2(star[0], star[1]) * extent)
	var grow := clampf(extent / 120.0, 0.8, 1.6)
	var spark := ProfileStyle.PIONEER[2]
	var index := 0
	for line: Vector2i in constellation["lines"]:
		var a := stars[line.x]
		var b := a.lerp(stars[line.y], reveal)
		canvas.draw_line(a, b, Color(0.82, 0.86, 1.0, 0.22 * alpha), 1.0, true)
		if reveal >= 1.0:
			var phase := fposmod(time * 0.35 + index * 0.37, 1.0)
			canvas.draw_circle(a.lerp(b, phase), 1.4 * grow, Color(spark, sin(phase * PI) * alpha))
		index += 1
	for i in stars.size():
		var star: Array = constellation["stars"][i]
		# Mais brilhante (magnitude menor), maior. As gigantes laranjas e
		# vermelhas (Betelgeuse, Pollux, Gacrux...) saem alaranjadas, como no céu.
		var radius := (1.0 + (4.0 - float(star[2])) * 0.5) * grow
		var core := Color("ffb27a") if star[3] else Color("e6efff")
		var glow := 0.6 + 0.4 * sin(time * 1.7 + (index + i) * 1.1)
		var halo := radius * 2.6 * glow
		canvas.draw_texture_rect(_glow(), Rect2(stars[i] - Vector2.ONE * halo, Vector2.ONE * halo * 2.0), false, Color(ProfileStyle.pioneer_color(float(i) / stars.size()), 0.3 * alpha))
		canvas.draw_circle(stars[i], radius * (0.8 + 0.2 * glow), Color(core, alpha), true, -1.0, true)
