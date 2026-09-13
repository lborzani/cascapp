class_name BomberView
extends Control

## O mapa de Bomberman desenhado, e nada além disso.
##
## Não decide nada: recebe um [BomberState] e o desenha. Quem anda com a partida é
## a cena, e quem sabe as regras é [BomberRules] — esta separação é a mesma dos
## outros quatro tabuleiros do app, e aqui ela pesa mais: a simulação tem de rodar
## igual em quatro aparelhos, e uma decisão tomada no meio de um `_draw` seria uma
## decisão que só existe em quem está olhando.
##
## ## O desenho anda mais liso que a simulação
##
## A simulação dá trinta passos por segundo; a tela desenha nos quadros que o
## aparelho conseguir, que costumam ser sessenta. Desenhar a posição crua faria o
## boneco andar aos saltos de 32 unidades. Por isso a cena entrega também a
## posição do tique **anterior** ([member previous]) e o quanto do próximo já
## passou ([member blend]), e os bonecos são desenhados entre as duas.
##
## Só os bonecos são interpolados. Bomba, fogo e caixa nascem e somem em casas
## inteiras — interpolar aquilo seria inventar meio-fogo, que não existe na regra
## e enganaria sobre onde é seguro pisar.

## Cores dos quatro jogadores, na ordem dos assentos. Vermelho, azul, verde e
## amarelo — as mesmas famílias do Ludo, porque num app com dois jogos de quatro
## cores o jogador aprende a cor uma vez só.
const COLORS := [
	Color("d2564b"), Color("4b7fd2"), Color("5aa860"), Color("d9a441"),
]

const FLOOR_A := Color("2c2723")
const FLOOR_B := Color("332d28")
const SOLID_TOP := Color("6f665d")
const SOLID_SIDE := Color("4a433c")
const BRICK_TOP := Color("9a6a44")
const BRICK_SIDE := Color("6d4a2f")
const FLAME_CORE := Color("ffe7a8")
const FLAME_EDGE := Color("e8763a")

## O estado a desenhar. A cena troca a referência a cada tique.
var state: BomberState = null

## Posições do tique anterior, dois inteiros por assento (`x`, `y`). Vazio no
## primeiro quadro, e aí o desenho usa a posição atual.
var previous := PackedInt32Array()

## Quanto do tique seguinte já passou, de 0 a 1.
var blend := 0.0

var _cell := 0.0
var _origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Chamado pela cena a cada quadro. Recalcula o enquadramento e redesenha.
func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if state == null:
		return
	_layout()
	_draw_floor()
	_draw_prizes()
	_draw_blocks()
	_draw_bombs()
	_draw_flames()
	_draw_players()


## A casa é quadrada e o mapa é centrado no que sobrar. Quadrada e não esticada:
## o alcance da bomba é contado em casas, e uma casa retangular faria o fogo
## parecer alcançar mais para um lado do que para o outro.
func _layout() -> void:
	_cell = floorf(minf(size.x / BomberState.COLS, size.y / BomberState.ROWS))
	var board := Vector2(_cell * BomberState.COLS, _cell * BomberState.ROWS)
	_origin = ((size - board) * 0.5).floor()


func _rect_of(col: int, row: int) -> Rect2:
	return Rect2(_origin + Vector2(col, row) * _cell, Vector2(_cell, _cell))


func _draw_floor() -> void:
	for row in BomberState.ROWS:
		for col in BomberState.COLS:
			var shade := FLOOR_A if (col + row) % 2 == 0 else FLOOR_B
			draw_rect(_rect_of(col, row), shade)


## Os prêmios ficam **embaixo** dos blocos de propósito: assim a caixa que cai
## revela o que guardava sem nada precisar aparecer no mesmo quadro.
func _draw_prizes() -> void:
	for row in BomberState.ROWS:
		for col in BomberState.COLS:
			var index := BomberState.index_of(col, row)
			if state.tiles[index] != BomberState.Tile.FLOOR:
				continue
			var prize: int = state.prizes[index]
			if prize == BomberState.Prize.NONE:
				continue
			var rect := _rect_of(col, row).grow(-_cell * 0.26)
			var tint := _prize_color(prize)
			draw_rect(rect, Color(tint, 0.22), true)
			draw_rect(rect, tint, false, maxf(1.0, _cell * 0.05))
			# Uma marca por tipo, e não três cores parecidas: no meio de uma
			# partida ninguém compara tons, mas todo mundo reconhece forma.
			_draw_prize_mark(prize, rect, tint)


static func _prize_color(prize: int) -> Color:
	match prize:
		BomberState.Prize.BOMB:
			return Color("cfd6dd")
		BomberState.Prize.FLAME:
			return FLAME_EDGE
		_:
			return Color("7ec27f")


func _draw_prize_mark(prize: int, rect: Rect2, tint: Color) -> void:
	var center := rect.get_center()
	var radius := rect.size.x * 0.26
	match prize:
		BomberState.Prize.BOMB:
			draw_circle(center, radius, tint)
		BomberState.Prize.FLAME:
			# Uma cruz: é o desenho do que a bomba faz.
			var arm := rect.size.x * 0.34
			draw_line(center - Vector2(arm, 0), center + Vector2(arm, 0), tint, 3.0)
			draw_line(center - Vector2(0, arm), center + Vector2(0, arm), tint, 3.0)
		_:
			# Duas setas: velocidade.
			var span := rect.size.x * 0.3
			for offset in [-span * 0.5, span * 0.5]:
				draw_polyline(
					PackedVector2Array([
						center + Vector2(offset - span * 0.35, -span * 0.5),
						center + Vector2(offset + span * 0.15, 0.0),
						center + Vector2(offset - span * 0.35, span * 0.5),
					]),
					tint, 3.0, true
				)


## Concreto e caixa com uma faixa mais escura embaixo: é o mínimo que dá volume
## sem virar desenho. Sem ela o mapa fica um mosaico chapado e a diferença entre
## "passa" e "não passa" some no meio da partida.
func _draw_blocks() -> void:
	for row in BomberState.ROWS:
		for col in BomberState.COLS:
			var tile: int = state.tiles[BomberState.index_of(col, row)]
			if tile == BomberState.Tile.FLOOR:
				continue
			var rect := _rect_of(col, row)
			var top := SOLID_TOP if tile == BomberState.Tile.SOLID else BRICK_TOP
			var side := SOLID_SIDE if tile == BomberState.Tile.SOLID else BRICK_SIDE
			draw_rect(rect, side)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.78)), top)
			if tile == BomberState.Tile.BRICK:
				# Duas juntas de tijolo. Só o suficiente para a caixa não se
				# confundir com o pilar de relance.
				var line := Color(0, 0, 0, 0.22)
				draw_line(
					rect.position + Vector2(0, rect.size.y * 0.39),
					rect.position + Vector2(rect.size.x, rect.size.y * 0.39), line, 2.0
				)
				draw_line(
					rect.position + Vector2(rect.size.x * 0.5, 0),
					rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.39), line, 2.0
				)


## A bomba pulsa, e o pulso acelera junto com o pavio. É a única leitura de tempo
## que o jogador tem no meio da correria — um número de segundos ali seria algo a
## ler, e ninguém lê nada com fogo chegando.
func _draw_bombs() -> void:
	for bomb in state.bombs:
		var center := _rect_of(bomb.col, bomb.row).get_center()
		var spent := 1.0 - float(bomb.fuse) / float(BomberRules.FUSE)
		var beat := sin(spent * spent * 42.0) * 0.5 + 0.5
		var radius := _cell * (0.30 + 0.05 * beat)
		draw_circle(center, radius, Color("1b1a1e"))
		draw_circle(center, radius * 0.72, Color("35333a"))
		# O pavio acende com o tempo: de brasa a branco quando está por estourar.
		var fuse_tint := Color(FLAME_EDGE).lerp(FLAME_CORE, spent)
		draw_circle(center - Vector2(radius * 0.45, radius * 0.85), _cell * 0.07, fuse_tint)


func _draw_flames() -> void:
	for row in BomberState.ROWS:
		for col in BomberState.COLS:
			var left: int = state.flames[BomberState.index_of(col, row)]
			if left <= 0:
				continue
			# O fogo encolhe enquanto apaga, para o fim dele ser visível: uma casa
			# que apaga de repente não avisa que já dá para passar.
			var life := float(left) / float(BomberRules.FLAME_TICKS)
			var rect := _rect_of(col, row).grow(-_cell * 0.5 * (1.0 - life) * 0.6)
			draw_rect(rect, Color(FLAME_EDGE, 0.85))
			draw_rect(rect.grow(-rect.size.x * 0.22), Color(FLAME_CORE, 0.9))


func _draw_players() -> void:
	for seat in state.players.size():
		var player := state.players[seat]
		if not player.alive:
			continue
		var center := _origin + _blended(seat, player) * _cell / float(BomberState.CELL)
		var radius := _cell * 0.34
		draw_circle(center + Vector2(0, radius * 0.55), radius * 0.9, Color(0, 0, 0, 0.28))
		draw_circle(center, radius, COLORS[seat % COLORS.size()])
		draw_circle(center, radius * 0.66, Color(1, 1, 1, 0.12))
		# Um ponto na direção em que ele olha. Serve para saber de que lado a
		# bomba vai cair antes de ela cair.
		var look: Vector2i = BomberRules.DIRS[player.facing % BomberRules.DIRS.size()]
		draw_circle(center + Vector2(look) * radius * 0.62, radius * 0.22, Color("13100e"))


## A posição desenhada: entre a do tique anterior e a de agora.
func _blended(seat: int, player: BomberState.Bomber) -> Vector2:
	var now := Vector2(player.x, player.y)
	if previous.size() < (seat + 1) * 2:
		return now
	var before := Vector2(previous[seat * 2], previous[seat * 2 + 1])
	# Salto grande é renascimento ou teleporte de resync, e não caminhada: aí
	# interpolar desenharia o boneco atravessando o mapa em linha reta.
	if before.distance_squared_to(now) > float(BomberState.CELL * BomberState.CELL):
		return now
	return before.lerp(now, clampf(blend, 0.0, 1.0))
