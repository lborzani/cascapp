class_name PieceRenderer
extends RefCounted

## Desenha as peças de xadrez a partir de `assets/pieces/`, e as de damas por
## código.
##
## Ponto único de desenho de peça em todo o jogo — tabuleiro, cartão de jogador,
## fileira de capturas, linha de último lance e miniatura do menu passam por
## aqui. Por isso a troca de polígonos por textura não tocou em nenhum deles: a
## assinatura de `draw_piece` é a mesma.
##
## Todas as espécies dos dois jogos têm arquivo hoje. O caminho do polígono
## continua vivo como rede de segurança: espécie sem textura cai nele em vez de
## desaparecer do tabuleiro, e é o que vai segurar a primeira peça de um jogo
## novo enquanto o desenho dela não chega.
##
## **Sobre o desenho por código, que continua vivo abaixo:** cada peça é um
## perfil torneado — só a metade direita da silhueta, de baixo para cima,
## espelhada. É como uma peça de xadrez é feita de verdade, num torno, e resolve
## dois problemas de uma vez: garante simetria perfeita e reduz o desenho à
## metade dos pontos. Os perfis passam por Catmull-Rom, então poucos pontos de
## controle viram curva contínua, e pontos repetidos criam quina proposital (a
## borda da base não pode arredondar). Tudo em espaço normalizado (a casa é 1x1,
## centro em 0,0) e cacheado.

const WHITE_FILL := Color("f6efe1")
const BLACK_FILL := Color("26231f")
const WHITE_LINE := Color("5d4630")
const BLACK_LINE := Color("d6cab6")
const SHADOW := Color(0, 0, 0, 0.30)
const SHADOW_OFFSET := Vector2(0.035, 0.055)
## Sombreado lateral e realce: dão volume sem shader, recortando a própria
## silhueta com `Geometry2D`.
const SHADE := Color(0, 0, 0, 0.13)
const HIGHLIGHT := Color(1, 1, 1, 0.10)

const OUTLINE_WIDTH := 0.022
const SAMPLES := 7
## Folga entre a peça e a borda da casa.
const SCALE := 0.94

## Nome do arquivo por tipo de peça. O que não está aqui — as pedras de damas —
## cai no desenho por código.
const TEXTURE_NAMES := {
	Board.Kind.PAWN: "pawn",
	Board.Kind.KNIGHT: "knight",
	Board.Kind.BISHOP: "bishop",
	Board.Kind.ROOK: "rook",
	Board.Kind.QUEEN: "queen",
	Board.Kind.KING: "king",
	Board.Kind.MAN: "man",
	Board.Kind.DAME: "dame",
	# Batalha naval desenha os cascos na própria grade, não por aqui. O navio só
	# existe como textura para ser o ícone do jogo — na grade de escolha e no
	# cabeçalho da tela seguinte, onde é a peça que diz que jogo é aquele.
	Board.Kind.BATTLESHIP: "battleship",
	# O dado, pelo mesmo motivo do navio: ele é o ícone do Ludo, não uma peça do
	# tabuleiro. Em arquivo e não em polígono porque o ícone precisa ser irmão
	# dos outros — o desenho por código saía com a paleta do tabuleiro (creme e
	# marrom) enquanto os quatro vizinhos da lista são brancos de contorno
	# escuro, e o Ludo aparecia como um cartão de outro app.
	Board.Kind.DIE: "die",
	# A casinha de Metrópole, pelo mesmo motivo do navio e do dado: ela é o ícone
	# do jogo, não uma peça do tabuleiro. As construções da partida são volumes
	# 3D e nunca passam por aqui.
	Board.Kind.HOUSE: "house",
	Board.Kind.BOMB: "bomb",
	# As duas cartas em leque do Uno. Como o navio, o dado, a casinha e a bomba:
	# ícone do jogo, não peça de tabuleiro. As 108 cartas da partida são desenhadas
	# por código (`ui/uno_card.gd`) e nunca passam por aqui — em arquivo elas seriam
	# quinze desenhos vezes quatro cores, e uma paleta impossível de afinar.
	#
	# Duas cartas e não uma: uma carta sozinha, de frente, é um retângulo com uma
	# oval no meio — indistinguível de um ícone genérico de documento no tamanho da
	# grade do menu. O leque é o que diz "baralho".
	Board.Kind.CARD: "card",
}
const TEXTURE_DIR := "res://assets/pieces"

static var _cache := {}
## Peça (inteiro de `Board.piece`) → textura, ou `null` quando não há arquivo.
## O `null` também é cacheado: sem isso, cada pedra de damas tentaria um `load`
## por quadro, e um `load` que falha não é barato.
static var _textures := {}


## `opacity` e `size` existem para as animações: peça capturada some, peça em
## movimento cresce um pouco enquanto viaja.
##
## `upside_down` gira a peça meia volta, para o modo mesa: com o aparelho
## deitado entre os dois jogadores, as peças de quem está do outro lado precisam
## apontar para lá. A sombra continua caindo para o mesmo lado na tela — quem
## vira é a peça, não a luz.
## `tint` multiplica a peça. Existe pelo Ludo, que tem **quatro** cores e este
## encoding tem um bit de lado: em vez de quatro jogos de arquivos, o peão branco
## é tingido de vermelho, verde, amarelo e azul. O contorno escuro do desenho
## sobrevive à multiplicação — escuro vezes cor continua escuro —, então a peça
## tingida mantém a silhueta que a peça original tem no tabuleiro.
##
## Branco é o neutro da multiplicação, então os outros três jogos não notam.
## `spin` gira a peça em torno do próprio centro, e se soma à meia volta do modo
## mesa. Existe pelo peão derrubado do Ludo: uma peça que atravessa o tabuleiro
## em pé lê como "mudou de lugar", e girando lê como "foi comida".
static func draw_piece(
	canvas: CanvasItem, piece: int, center: Vector2, cell: float,
	opacity := 1.0, size := 1.0, upside_down := false, tint := Color.WHITE, spin := 0.0
) -> void:
	if piece == 0 or opacity <= 0.0:
		return
	var texture := _texture(piece)
	if texture != null:
		_draw_texture(canvas, texture, center, cell, opacity, size, upside_down, tint, spin)
		return
	_draw_polygons(canvas, piece, center, cell, opacity, size, upside_down, tint, spin)


static func _texture(piece: int) -> Texture2D:
	if _textures.has(piece):
		return _textures[piece]
	var kind := Board.kind_of(piece)
	var texture: Texture2D = null
	if TEXTURE_NAMES.has(kind):
		var side := "white" if Board.side_of(piece) == Board.Side.WHITE else "black"
		texture = load("%s/%s_%s.svg" % [TEXTURE_DIR, TEXTURE_NAMES[kind], side]) as Texture2D
	_textures[piece] = texture
	return texture


## A sombra é a própria peça desenhada de novo, deslocada e multiplicada por
## preto. Sai de graça — mesma textura, mesmo desenho — e mantém o volume que o
## desenho por código dava, que era o que descolava a peça da casa.
static func _draw_texture(
	canvas: CanvasItem, texture: Texture2D, center: Vector2, cell: float,
	opacity: float, size: float, upside_down: bool, tint := Color.WHITE, spin := 0.0
) -> void:
	var side := cell * SCALE * size
	# Desenhada em torno da origem, para a meia volta sair da própria transformada
	# em vez de contas de canto. O deslocamento da sombra fica de fora dela e por
	# isso continua em coordenadas de tela.
	var rect := Rect2(Vector2(side, side) * -0.5, Vector2(side, side))
	var angle := (PI if upside_down else 0.0) + spin

	canvas.draw_set_transform(center + SHADOW_OFFSET * cell, angle, Vector2.ONE)
	canvas.draw_texture_rect(texture, rect, false, Color(0.0, 0.0, 0.0, SHADOW.a * opacity))
	canvas.draw_set_transform(center, angle, Vector2.ONE)
	canvas.draw_texture_rect(texture, rect, false, Color(tint.r, tint.g, tint.b, opacity))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_polygons(
	canvas: CanvasItem, piece: int, center: Vector2, cell: float,
	opacity: float, size: float, upside_down: bool, tint := Color.WHITE, spin := 0.0
) -> void:
	var kind := Board.kind_of(piece)
	var shape := _shape(kind)
	var white := Board.side_of(piece) == Board.Side.WHITE
	var scale := Vector2.ONE * cell * SCALE * size
	var angle := (PI if upside_down else 0.0) + spin

	canvas.draw_set_transform(center + SHADOW_OFFSET * cell, angle, scale)
	for polygon in shape["solids"]:
		canvas.draw_colored_polygon(polygon, _fade(SHADOW, opacity))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	canvas.draw_set_transform(center, angle, scale)
	# Mesma multiplicação do caminho por textura, para os dois desenhos
	# responderem igual a uma peça tingida.
	var fill := _fade((WHITE_FILL if white else BLACK_FILL) * tint, opacity)
	var line := _fade((WHITE_LINE if white else BLACK_LINE) * tint, opacity)
	for polygon in shape["solids"]:
		canvas.draw_colored_polygon(polygon, fill)
	for polygon in shape["shade"]:
		canvas.draw_colored_polygon(polygon, _fade(SHADE, opacity))
	for polygon in shape["highlight"]:
		canvas.draw_colored_polygon(polygon, _fade(HIGHLIGHT, opacity))
	for polygon in shape["solids"]:
		var outline: PackedVector2Array = polygon.duplicate()
		outline.append(polygon[0])
		canvas.draw_polyline(outline, line, OUTLINE_WIDTH)
	for accent in shape["accents"]:
		canvas.draw_colored_polygon(accent, line)
	for detail in shape["details"]:
		canvas.draw_polyline(detail, line, OUTLINE_WIDTH * 0.85)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _fade(color: Color, opacity: float) -> Color:
	return Color(color, color.a * opacity)


# --- construção das formas ---------------------------------------------------


static func _shape(kind: int) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]

	var solids: Array[PackedVector2Array] = []
	var details: Array[PackedVector2Array] = []
	var accents: Array[PackedVector2Array] = []
	match kind:
		Board.Kind.MAN, Board.Kind.DAME:
			solids.append(_disc(0.36))
			details.append(_ring(0.27))
			if kind == Board.Kind.DAME:
				details.append(_ring(0.17))
				details.append(_ring(0.08))
		Board.Kind.PAWN:
			solids.append(_lathe(_PAWN))
			solids.append(_disc(0.145, Vector2(0, -0.20)))
		Board.Kind.ROOK:
			solids.append(_lathe(_ROOK))
			solids.append(_rook_top())
		Board.Kind.KNIGHT:
			solids.append(_lathe(_KNIGHT_BASE))
			solids.append(_drop_collinear(_smooth(_KNIGHT_HEAD, true)))
			accents.append(_disc(0.027, Vector2(-0.16, -0.30)))
			# Linha da boca: separa mandíbula de focinho, que é o que faz o
			# perfil longo parecer focinho de cavalo e não um bico.
			details.append(PackedVector2Array([
				Vector2(-0.43, -0.145), Vector2(-0.36, -0.12), Vector2(-0.29, -0.115)
			]))
			# Traço da crina, para o pescoço não ler como bloco liso.
			details.append(PackedVector2Array([
				Vector2(0.03, -0.30), Vector2(0.10, -0.17), Vector2(0.14, -0.01)
			]))
		Board.Kind.BISHOP:
			solids.append(_lathe(_BISHOP))
			solids.append(_disc(0.052, Vector2(0, -0.415)))
			details.append(PackedVector2Array([
				Vector2(0.02, -0.34), Vector2(0.08, -0.26), Vector2(0.10, -0.17)
			]))
		Board.Kind.QUEEN:
			solids.append(_lathe(_QUEEN))
			solids.append(_coronet(0.285, 0.245, -0.19, -0.32))
			for point in _crown_beads(5, 0.245, -0.35, 0.035):
				solids.append(_disc(0.052, point))
		Board.Kind.KING:
			solids.append(_lathe(_KING))
			solids.append(_coronet(0.265, 0.215, -0.19, -0.30))
			solids.append(_cross())
		Board.Kind.DIE:
			# Cinco pontos, e não uma face qualquer: o 5 é simétrico nos dois
			# eixos, então o dado lê como dado em qualquer tamanho e não parece
			# um dado tombado.
			solids.append(_rounded_square(0.38, 0.09))
			for point in [
				Vector2(-0.19, -0.19), Vector2(0.19, -0.19), Vector2.ZERO,
				Vector2(-0.19, 0.19), Vector2(0.19, 0.19),
			]:
				accents.append(_disc(0.062, point))

	for i in solids.size():
		solids[i] = _sanitize(solids[i])

	var shape := {
		"solids": solids,
		"details": details,
		"accents": accents,
		# Duas faixas de sombra em vez de uma: a borda vira degrau em vez de
		# costura reta no meio da peça, que é o que denuncia o truque.
		"shade": _clip_all(solids, _band(0.05, 0.60)) + _clip_all(solids, _band(0.17, 0.60)),
		"highlight": _clip_all(solids, _band(-0.44, -0.14)),
	}
	_cache[kind] = shape
	return shape


## Retângulo alto usado para recortar a faixa iluminada ou sombreada da peça.
static func _band(x_from: float, x_to: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x_from, -0.6), Vector2(x_to, -0.6), Vector2(x_to, 0.6), Vector2(x_from, 0.6)
	])


static func _clip_all(solids: Array[PackedVector2Array], mask: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for polygon in solids:
		for piece in Geometry2D.intersect_polygons(polygon, mask):
			out.append(piece)
	return out


## Espelha o meio-perfil: sobe pela direita e desce pela esquerda.
static func _lathe(profile: Array) -> PackedVector2Array:
	var right := _smooth(profile, false)
	# Catmull-Rom ultrapassa nos extremos e joga x para o lado negativo; espelhar
	# isso cria um polígono auto-intersectante que a triangulação recusa inteiro,
	# e a peça simplesmente não aparece.
	for i in right.size():
		right[i] = Vector2(maxf(right[i].x, 0.0), right[i].y)
	var points := PackedVector2Array()
	points.append_array(right)
	for i in range(right.size() - 1, -1, -1):
		var p := right[i]
		if absf(p.x) < 0.001:
			continue
		points.append(Vector2(-p.x, p.y))
	return _sanitize(points)


## Pontos de controle repetidos (o truque que cria quina) geram segmentos de
## comprimento zero depois da suavização, e trechos retos geram dezenas de
## pontos colineares. A triangulação por ear-clipping da Godot rejeita o polígono
## inteiro nos dois casos — sem erro visível além da peça não aparecer.
static func _dedupe(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 1e-8:
			out.append(p)
	if out.size() > 2 and out[0].distance_squared_to(out[out.size() - 1]) < 1e-8:
		out.remove_at(out.size() - 1)
	return out


## Une o polígono com ele mesmo. Parece inútil, mas `merge_polygons` usa Clipper,
## que resolve auto-interseções e devolve um contorno simples — ao contrário do
## ear-clipping do `draw_colored_polygon`, que só desiste. É o que torna seguro
## descrever as peças com curvas suavizadas, onde qualquer ultrapassagem da
## Catmull-Rom cruzaria a silhueta consigo mesma.
static func _sanitize(points: PackedVector2Array) -> PackedVector2Array:
	var merged := Geometry2D.merge_polygons(points, points)
	var best := points
	var best_area := -1.0
	for candidate in merged:
		var area := absf(_area(candidate))
		if area > best_area:
			best_area = area
			best = candidate
	return _drop_collinear(_dedupe(best))


static func _area(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		total += a.cross(b)
	return total * 0.5


static func _drop_collinear(points: PackedVector2Array) -> PackedVector2Array:
	var count := points.size()
	if count < 4:
		return points
	var out := PackedVector2Array()
	for i in count:
		var previous := points[(i - 1 + count) % count]
		var current := points[i]
		var following := points[(i + 1) % count]
		if absf((current - previous).cross(following - previous)) > 1e-6:
			out.append(current)
	return out if out.size() >= 3 else points


## Catmull-Rom sobre os pontos de controle. Pontos repetidos na entrada viram
## quina, que é como a base ganha aresta viva sem virar caso especial.
static func _smooth(points: Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := points.size()
	var last := count - 1 if not closed else count
	for i in last:
		var p0: Vector2 = points[(i - 1 + count) % count] if closed else points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i % count]
		var p2: Vector2 = points[(i + 1) % count]
		var p3: Vector2 = points[(i + 2) % count] if closed else points[mini(i + 2, count - 1)]
		for s in SAMPLES:
			out.append(_catmull(p0, p1, p2, p3, float(s) / SAMPLES))
	if not closed:
		out.append(points[count - 1])
	return _dedupe(out)


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


static func _disc(radius: float, center := Vector2.ZERO, segments := 40) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Quadrado de cantos arredondados, em espaço normalizado. `half` é o meio-lado
## e `radius` o canto; o arco de cada canto sai de um laço curto porque quatro
## cantos escritos à mão é onde um deles acaba com um sinal trocado.
static func _rounded_square(half: float, radius: float, steps := 6) -> PackedVector2Array:
	var points := PackedVector2Array()
	var inner := half - radius
	var corners := [
		Vector2(inner, inner), Vector2(-inner, inner),
		Vector2(-inner, -inner), Vector2(inner, -inner),
	]
	for index in corners.size():
		var pivot: Vector2 = corners[index]
		var start := index * PI * 0.5
		for step in steps + 1:
			var angle := start + (PI * 0.5) * (float(step) / steps)
			points.append(pivot + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _ring(radius: float) -> PackedVector2Array:
	var points := _disc(radius)
	points.append(points[0])
	return points


## Ameias explícitas e simétricas. Gerar por laço deixava a torre fora de eixo,
## e numa peça que é literalmente um retângulo isso salta aos olhos.
static func _rook_top() -> PackedVector2Array:
	var top := -0.44
	var notch := -0.33
	var bottom := -0.12
	return PackedVector2Array([
		Vector2(-0.32, bottom), Vector2(-0.32, top), Vector2(-0.17, top),
		Vector2(-0.17, notch), Vector2(-0.075, notch), Vector2(-0.075, top),
		Vector2(0.075, top), Vector2(0.075, notch), Vector2(0.17, notch),
		Vector2(0.17, top), Vector2(0.32, top), Vector2(0.32, bottom),
	])


## Coroa do rei e da dama: uma faixa troncocônica, não pontas de serra. O
## coronet do Staunton é isso — o que dá identidade são as contas em cima, não
## bicos afiados.
static func _coronet(half_bottom: float, half_top: float, y_bottom: float, y_top: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half_bottom, y_bottom), Vector2(-half_top, y_top),
		Vector2(half_top, y_top), Vector2(half_bottom, y_bottom),
	])


## Contas sobre um arco suave, como as pontas do coronet da dama.
static func _crown_beads(count: int, half: float, y: float, rise: float) -> Array:
	var beads := []
	for i in count:
		var t := (float(i) / (count - 1)) * 2.0 - 1.0
		beads.append(Vector2(t * half, y + absf(t) * rise))
	return beads


static func _cross() -> PackedVector2Array:
	var arm := 0.058
	var wide := 0.17
	var top := -0.50
	var bottom := -0.30
	var arm_top := -0.42
	var arm_bottom := -0.355
	return PackedVector2Array([
		Vector2(-arm, top), Vector2(arm, top), Vector2(arm, arm_top),
		Vector2(wide, arm_top), Vector2(wide, arm_bottom), Vector2(arm, arm_bottom),
		Vector2(arm, bottom), Vector2(-arm, bottom), Vector2(-arm, arm_bottom),
		Vector2(-wide, arm_bottom), Vector2(-wide, arm_top), Vector2(-arm, arm_top),
	])


# --- perfis (metade direita, de baixo para cima) -----------------------------

const _BASE := [
	Vector2(0.00, 0.46), Vector2(0.00, 0.46),
	Vector2(0.30, 0.46), Vector2(0.30, 0.46),
	Vector2(0.32, 0.42), Vector2(0.24, 0.38),
	Vector2(0.20, 0.33),
]

const _PAWN := [
	Vector2(0.00, 0.46), Vector2(0.00, 0.46),
	Vector2(0.28, 0.46), Vector2(0.28, 0.46),
	Vector2(0.29, 0.41), Vector2(0.21, 0.37),
	Vector2(0.16, 0.30), Vector2(0.13, 0.21),
	Vector2(0.16, 0.15), Vector2(0.17, 0.12),
	Vector2(0.10, 0.09), Vector2(0.10, 0.02),
	Vector2(0.00, -0.02),
]

const _ROOK := [
	Vector2(0.00, 0.46), Vector2(0.00, 0.46),
	Vector2(0.32, 0.46), Vector2(0.32, 0.46),
	Vector2(0.33, 0.40), Vector2(0.25, 0.36),
	Vector2(0.22, 0.26), Vector2(0.20, 0.08),
	Vector2(0.24, 0.00), Vector2(0.30, -0.06),
	Vector2(0.30, -0.12), Vector2(0.30, -0.12),
	Vector2(0.00, -0.12), Vector2(0.00, -0.12),
]

const _KNIGHT_BASE := [
	Vector2(0.00, 0.46), Vector2(0.00, 0.46),
	Vector2(0.31, 0.46), Vector2(0.31, 0.46),
	Vector2(0.32, 0.40), Vector2(0.24, 0.36),
	Vector2(0.21, 0.30), Vector2(0.21, 0.26),
	Vector2(0.00, 0.24),
]

## Cabeça de cavalo, virada para a esquerda. Única forma fechada e assimétrica —
## e a única peça em que a leitura depende do desenho, não da silhueta torneada.
## O que separa cavalo de cachorro na silhueta: **cana nasal longa e reta**,
## mandíbula funda atrás dela, e crista no pescoço. Focinho curto e rombudo lê
## como cachorro por mais orelhas de cavalo que se ponha em cima.
##
## Sem pontos repetidos: numa spline fechada eles viram laço, o polígono se
## auto-intersecta e a peça some. As quinas vêm de pontos próximos, não de
## duplicatas.
const _KNIGHT_HEAD := [
	Vector2(-0.14, 0.31),                     # base do pescoço, frente
	Vector2(-0.18, 0.19),                     # pescoço
	Vector2(-0.23, 0.08),                     # garganta
	Vector2(-0.31, 0.00),                     # ganacha funda
	Vector2(-0.39, -0.04),                    # sob o focinho
	Vector2(-0.44, -0.10),                    # queixo
	Vector2(-0.43, -0.17),                    # ponta do focinho, apontando baixo
	Vector2(-0.34, -0.21),                    # narina
	Vector2(-0.22, -0.27),                    # cana nasal, longa e reta
	Vector2(-0.12, -0.35),                    # fronte
	Vector2(-0.08, -0.48),                    # orelha da frente
	Vector2(-0.02, -0.38),                    # vão entre as orelhas
	Vector2(0.04, -0.46),                     # orelha de trás
	Vector2(0.09, -0.33),                     # nuca
	Vector2(0.15, -0.24),                     # crista do pescoço
	Vector2(0.22, -0.06),                     # crina
	Vector2(0.26, 0.12),
	Vector2(0.23, 0.31),                      # base do pescoço, trás
]

const _BISHOP := [
	Vector2(0.00, 0.46), Vector2(0.00, 0.46),
	Vector2(0.29, 0.46), Vector2(0.29, 0.46),
	Vector2(0.30, 0.41), Vector2(0.22, 0.37),
	Vector2(0.17, 0.29), Vector2(0.15, 0.20),
	Vector2(0.19, 0.15), Vector2(0.19, 0.13),
	Vector2(0.11, 0.10), Vector2(0.13, 0.04),
	Vector2(0.19, -0.04), Vector2(0.20, -0.16),
	Vector2(0.14, -0.28), Vector2(0.06, -0.35),
	Vector2(0.00, -0.37),
]

const _QUEEN := [
	Vector2(0.00, 0.46), Vector2(0.00, 0.46),
	Vector2(0.32, 0.46), Vector2(0.32, 0.46),
	Vector2(0.33, 0.40), Vector2(0.25, 0.36),
	Vector2(0.19, 0.27), Vector2(0.16, 0.15),
	Vector2(0.21, 0.10), Vector2(0.21, 0.08),
	Vector2(0.12, 0.04), Vector2(0.16, -0.04),
	Vector2(0.25, -0.13), Vector2(0.285, -0.20),
	Vector2(0.00, -0.20),
]

const _KING := [
	Vector2(0.00, 0.46), Vector2(0.00, 0.46),
	Vector2(0.32, 0.46), Vector2(0.32, 0.46),
	Vector2(0.33, 0.40), Vector2(0.25, 0.36),
	Vector2(0.19, 0.27), Vector2(0.16, 0.15),
	Vector2(0.21, 0.10), Vector2(0.21, 0.08),
	Vector2(0.12, 0.04), Vector2(0.16, -0.04),
	Vector2(0.23, -0.13), Vector2(0.265, -0.20),
	Vector2(0.00, -0.20),
]
