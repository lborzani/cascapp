class_name Coaster
extends Control

## A bolacha de chopp: o avatar de um jogador no tema Boteco.
##
## Um círculo escuro com a inicial, um anel dourado — ou na cor do assento, dentro
## da partida — e um segundo anel amarelo, por fora, quando é a vez dele. É o mesmo
## objeto na sala de espera, na coluna de jogadores e em volta da mesa: quem
## aprendeu a achar a própria bolacha numa tela acha nas outras.

## Espessura do anel em relação ao diâmetro. Fina demais some numa bolacha de 30
## px; grossa demais vira um alvo.
const RING_RATIO := 0.08
## O vão entre o anel de vez e a bolacha, também em relação ao diâmetro.
const TURN_GAP_RATIO := 0.06

@export var player_name := "":
	set(value):
		player_name = value
		queue_redraw()
## A peça de um jogo, de `Board.piece`, no lugar da inicial. É a bolacha servindo
## de ícone de jogo no cardápio, na folha e na lista de salas — a mesma moldura
## redonda para "quem é" e para "qual jogo".
@export var piece := 0:
	set(value):
		piece = value
		queue_redraw()
## A foto do jogador, por cima da inicial. A peça, quando há, vence: no
## cardápio a bolacha é o ícone do jogo, e não de alguém.
@export var photo: Texture2D = null:
	set(value):
		photo = value
		queue_redraw()
@export var fill := AppTheme.COASTER:
	set(value):
		fill = value
		queue_redraw()
@export var ring := AppTheme.GOLD:
	set(value):
		ring = value
		queue_redraw()
## A moldura da loja (`Cosmetics.frame_of`): "gold", "silver", "neon", "flames" ou
## "laurel"; vazio é sem moldura. Ela fica por fora de tudo, e a bolacha encolhe
## para caber no mesmo quadrado.
var frame := "":
	set(value):
		frame = value
		set_process(is_inside_tree() and animated(value))
		queue_redraw()
## As molduras que se mexem: o neon pulsa, as chamas tremulam e o arco-íris gira.
const ANIMATED_FRAMES := ["neon", "flames", "rainbow"]
## O relógio da moldura animada, em segundos. Anda no `_process`, que só roda
## com uma delas na tela; a folha de conferência o escreve à mão.
var frame_time := 0.0
## Largura da moldura em relação ao diâmetro.
const FRAME_RATIO := 0.11
## O halo da vez, de 0 a 1: um anel que cresce para fora e some, em laço.
var _halo := 0.0:
	set(value):
		_halo = value
		queue_redraw()
var _pulse: Tween = null

@export var turn := false:
	set(value):
		if turn == value:
			return
		turn = value
		_sync_pulse()
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A vez pulsa: parado, o anel limão é só uma borda mais clara, e a troca de vez
## passava sem ninguém ver. Liga e desliga com `turn`, e só dentro da árvore —
## bolacha fora de cena não gasta quadro.
func _sync_pulse() -> void:
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	_halo = 0.0
	if not turn or not is_inside_tree():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "_halo", 1.0, 1.4).from(0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_sync_pulse()


## Ter `_process` liga o processamento de toda bolacha; só a da moldura animada
## precisa dele.
func _ready() -> void:
	set_process(animated(frame))


func _draw() -> void:
	var diameter := minf(size.x, size.y)
	var center := size * 0.5
	var radius := diameter * 0.5
	if turn and _halo > 0.0:
		draw_arc(
			center, radius + _halo * maxf(3.0, diameter * 0.12), 0.0, TAU, 48,
			Color(AppTheme.ACCENT, 0.5 * (1.0 - _halo)), 3.0, true
		)
	if not frame.is_empty():
		var band := diameter * FRAME_RATIO
		_draw_frame(center, radius, band)
		radius -= band
		diameter = radius * 2.0
	var ring_width := maxf(2.0, diameter * RING_RATIO)
	# O anel de vez fica por fora, e a bolacha encolhe para caber dentro do mesmo
	# quadrado: acender a vez não pode empurrar o que está em volta.
	if turn:
		draw_arc(center, radius - ring_width * 0.5, 0.0, TAU, 48, AppTheme.ACCENT, ring_width, true)
		radius -= ring_width + diameter * TURN_GAP_RATIO
	draw_circle(center, radius, fill)
	if piece == 0 and photo != null:
		# Um disco com a textura mapeada: o recorte redondo sai do polígono, sem
		# shader nem máscara. O anel vem por cima e esconde o serrilhado da borda.
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		for step in 48:
			var direction := Vector2.from_angle(TAU * step / 48.0)
			points.append(center + direction * radius)
			uvs.append(Vector2(0.5, 0.5) + direction * 0.5)
		draw_colored_polygon(points, Color.WHITE, uvs, photo)
	draw_arc(center, radius - ring_width * 0.5, 0.0, TAU, 48, ring, ring_width, true)
	if piece != 0:
		PieceRenderer.draw_piece(self, piece, center, radius * 1.25)
		return
	if photo != null:
		return
	var face := AppTheme.display(900)
	var font_size := maxi(8, int(radius * 1.05))
	var baseline := center.y + (face.get_ascent(font_size) - face.get_descent(font_size)) * 0.5
	draw_string(
		face, Vector2(center.x - radius, baseline), initial_of(player_name),
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, ink_for(fill)
	)


## A moldura da loja, na faixa entre `radius - band` e `radius`.
func _draw_frame(center: Vector2, radius: float, band: float) -> void:
	var middle := radius - band * 0.5
	match frame:
		"gold", "silver":
			var metal := Color("e2b54d") if frame == "gold" else Color("c9d0d8")
			var shine := Color("fff1b0") if frame == "gold" else Color("ffffff")
			var edge := Color("7a5512") if frame == "gold" else Color("5b6470")
			draw_arc(center, middle, 0.0, TAU, 64, metal, band, true)
			draw_arc(center, middle - band * 0.1, deg_to_rad(200), deg_to_rad(290), 24, shine, band * 0.35, true)
			draw_arc(center, radius - 0.75, 0.0, TAU, 64, edge, 1.5, true)
			draw_arc(center, radius - band + 0.75, 0.0, TAU, 64, edge, 1.5, true)
		"neon":
			# Pulsa: o halo cresce e acende, e o tubo respira junto.
			var beat := 0.5 + 0.5 * sin(frame_time * TAU * 0.8)
			draw_arc(center, middle, 0.0, TAU, 64, Color(1.0, 0.31, 0.85, 0.15 + 0.3 * beat), band * (1.0 + 0.5 * beat), true)
			draw_arc(center, middle, 0.0, TAU, 64, Color("ff4fd8"), band * (0.42 + 0.16 * beat), true)
			draw_arc(center, middle, 0.0, TAU, 64, Color("ffd6f6").lerp(Color.WHITE, beat), maxf(1.0, band * 0.16), true)
		"rainbow":
			# Um anel de todas as cores, girando devagar.
			var segments := 48
			for i in segments:
				var from := TAU * i / segments
				var hue := fposmod(float(i) / segments - frame_time * 0.25, 1.0)
				draw_arc(center, middle, from, from + TAU / segments + 0.02, 4, Color.from_hsv(hue, 0.8, 1.0), band * 0.8, true)
			draw_arc(center, radius - 0.75, 0.0, TAU, 64, Color(1, 1, 1, 0.5), 1.5, true)
		"flames":
			draw_arc(center, radius - band * 0.7, 0.0, TAU, 64, Color("c81d11"), band * 0.6, true)
			var tongues := 16
			for i in tongues:
				var angle := TAU * i / tongues
				var across := Vector2.from_angle(angle + PI * 0.5)
				var out := Vector2.from_angle(angle)
				var base := center + out * (radius - band)
				for layer: Array in [[1.0, Color("ff7a1a")], [0.6, Color("ffe066")]]:
					# Cada língua sobe e desce no próprio ritmo: o fogo tremula.
					var flicker := 0.7 + 0.3 * sin(frame_time * 9.0 + i * 1.7 + float(layer[0]) * 4.0)
					var reach: float = band * layer[0] * flicker
					var half := TAU * radius / tongues * 0.45 * float(layer[0])
					draw_colored_polygon(PackedVector2Array([
						base - across * half, base + across * half, base + out * reach + across * half * 0.6,
					]), layer[1])
		"laurel":
			var green := Color("a8d46f")
			var dark := Color("3d6b25")
			# Duas ramagens, uma de cada lado, abertas em cima.
			for side: float in [-1.0, 1.0]:
				for i in 8:
					var angle := PI * 0.5 + side * (deg_to_rad(16) + i * deg_to_rad(19))
					var tangent := Vector2.from_angle(angle + side * PI * 0.5)
					var spot := center + Vector2.from_angle(angle) * (middle + (band * 0.18 if i % 2 == 0 else -band * 0.18))
					var leaf := _leaf(spot, tangent.rotated(side * 0.5), band * 0.9, band * 0.45)
					draw_colored_polygon(leaf, green)
					draw_polyline(leaf + PackedVector2Array([leaf[0]]), dark, 1.0, true)


static func animated(style: String) -> bool:
	return style in ANIMATED_FRAMES


func _process(delta: float) -> void:
	frame_time += delta
	queue_redraw()


static func _leaf(at: Vector2, along: Vector2, length: float, width: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var across := along.orthogonal()
	for step in 12:
		var t := TAU * step / 12.0
		points.append(at + along * cos(t) * length * 0.5 + across * sin(t) * width * 0.5)
	return points


## A primeira letra ou número do nome, em maiúscula. Apelido é escolhido por gente
## ("k'rec@"), e a bolacha não pode mostrar um apóstrofo.
static func initial_of(name: String) -> String:
	for character in name:
		if character.is_valid_int() or character.to_upper() != character.to_lower():
			return character.to_upper()
	return "?"


## Tinta legível sobre um fundo: escura sobre claro, giz sobre escuro. O limite é
## a luminância relativa 0,5 — o amarelo (0,57) fica com tinta escura, e a cor de
## qualquer assento, com giz.
static func ink_for(background: Color) -> Color:
	return AppTheme.PAPER_INK if background.srgb_to_linear().get_luminance() > 0.5 else AppTheme.TEXT
