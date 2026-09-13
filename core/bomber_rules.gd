class_name BomberRules
extends RefCounted

## A simulação de Bomberman: um tique de trinta, e o que ele faz.
##
## ## Por que ela não é um `Ruleset`
##
## Os cinco jogos anteriores respondem "quais lances são legais agora" e "aplique
## este". Aqui não há lance nem vez: há quatro bonecos andando ao mesmo tempo,
## pavios queimando e fogo que aparece sozinho. `generate_moves` não tem o que
## devolver, e `apply_move` não tem quando acontecer.
##
## O que existe no lugar é [method step]: recebe o que **cada** jogador está
## segurando neste instante e avança a partida um tique. Uma partida é a lista de
## comandos de cada tique, e nada mais — é dela que sai tanto a rede quanto a
## volta de quem caiu.
##
## ## Determinismo é o requisito, não um detalhe
##
## Os aparelhos não trocam posições: cada um roda esta mesma função com os mesmos
## comandos e chega ao mesmo lugar. Isso só funciona se o resultado for
## **exatamente** o mesmo em todo processador, então:
##
## - nenhuma conta em `float`, em lugar nenhum;
## - nenhum `randi()`; o sorteio sai de [method next_random], que é estado da
##   partida e viaja com ela;
## - ordem de iteração fixa: jogadores por assento, bombas por ordem de posta.
##
## Uma diferença de uma unidade no décimo segundo vira, no vigésimo, um jogador
## vivo num aparelho e morto no outro — e o sintoma aparece longe da causa.

## Tiques por segundo. Trinta, e não sessenta: a conta é a mesma, a rede carrega
## metade dos comandos, e um boneco de grade não fica mais fluido a sessenta —
## quem suaviza o desenho é a interpolação da tela, não a simulação.
const TICK_HZ := 30

## Pavio, fogo e agonia, em tiques. Três segundos de pavio é o do jogo original, e
## é o que torna a bomba uma **ameaça posicional** em vez de um tiro: dá tempo de
## sair, e dá tempo de o outro entrar.
const FUSE := 90
const FLAME_TICKS := 15

## O que cada comando liga. Um byte por jogador por tique — é o que viaja na rede.
const IN_UP := 1
const IN_DOWN := 2
const IN_LEFT := 4
const IN_RIGHT := 8
const IN_BOMB := 16

## Direções na ordem dos bits acima, para o código não repetir a tabela.
const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

## Meia casa: o boneco está centrado quando as coordenadas caem aqui.
const HALF := BomberState.CELL >> 1
## Folga da colisão. O boneco não é um ponto nem uma casa inteira: com um corpo do
## tamanho da casa ele não passaria por corredor nenhum, e com um ponto ele
## entraria pela quina das paredes.
## Medido e não chutado: com um corpo pequeno o boneco vagueia dentro da casa e
## deixa de parecer preso ao corredor — a 96 dava para subir 64 unidades contra a
## borda antes de encostar nela. 208 é 81% da casa: sobra folga para o empurrão de
## quina trabalhar, e não sobra para passear.
const BODY := 208

## Quanto o boneco é empurrado para o meio do corredor quando esbarra numa quina.
##
## Sem isto, andar para a direita num corredor exige estar alinhado ao pixel com a
## linha — e num celular, com o polegar, isso é impossível. O empurrão é o que
## faz o jogo parecer que "entende" para onde se quer ir; ele existe no original
## pelo mesmo motivo.
const NUDGE := 12
## Até que distância do centro do corredor o empurrão age. Mais que isso e o
## boneco começa a virar esquinas que ninguém pediu.
const NUDGE_RANGE := 96

## Um em cada tantas caixas guarda um prêmio, por tipo. Somados dão menos de
## metade: caixa que quase sempre dá prêmio transforma a partida em coleta.
const PRIZE_ODDS := [
	[BomberState.Prize.BOMB, 5],
	[BomberState.Prize.FLAME, 5],
	[BomberState.Prize.SPEED, 12],
]

## Densidade de caixas nas casas livres, em porcentagem. Alta o bastante para o
## mapa ser um labirinto no começo, baixa o bastante para haver por onde fugir.
const BRICK_CHANCE := 72

## Tetos dos prêmios. Sem eles, uma partida longa vira um jogador com fogo de
## ponta a ponta do mapa, e aí não existe mais posição — só sorte.
const MAX_BOMBS := 6
const MAX_FLAME := 6
const MAX_SPEED := 56
const SPEED_STEP := 6


## Gerador determinístico — xorshift de 32 bits.
##
## Escrito à mão e guardado no estado porque `RandomNumberGenerator` é um objeto
## com estado interno que não viaja no `clone()`, e `randi()` é global. Os dois
## dariam mapas diferentes em aparelhos diferentes, que é a única coisa que esta
## simulação não pode permitir.
##
## A máscara de 32 bits é obrigatória: o inteiro do GDScript é de 64, e sem ela o
## deslocamento acumularia bits que a referência do algoritmo não tem.
static func next_random(state: BomberState) -> int:
	var value := state.seed_state & 0xFFFFFFFF
	value ^= (value << 13) & 0xFFFFFFFF
	value ^= value >> 17
	value ^= (value << 5) & 0xFFFFFFFF
	state.seed_state = value
	return value


static func _random_below(state: BomberState, bound: int) -> int:
	return next_random(state) % maxi(1, bound)


## Os quatro cantos, na ordem dos assentos.
static func spawn_cell(seat: int) -> Vector2i:
	match seat % 4:
		0:
			return Vector2i(1, 1)
		1:
			return Vector2i(BomberState.COLS - 2, BomberState.ROWS - 2)
		2:
			return Vector2i(BomberState.COLS - 2, 1)
		_:
			return Vector2i(1, BomberState.ROWS - 2)


## As casas que ficam livres em volta de cada canto. Sem elas, um jogador pode
## nascer emparedado — e perder a partida antes de tocar na tela.
static func _spawn_is_clear(col: int, row: int, seats: int) -> bool:
	for seat in seats:
		var home := spawn_cell(seat)
		if absi(home.x - col) + absi(home.y - row) <= 2:
			return true
	return false


func initial_state(seats := 4, match_seed := 1) -> BomberState:
	var state := BomberState.new()
	state.seats = clampi(seats, 2, 4)
	# Semente nunca zero: o xorshift tem o zero como ponto fixo e devolveria zero
	# para sempre — um mapa vazio, sempre o mesmo, sem nenhum erro à vista.
	state.seed_state = match_seed if match_seed != 0 else 1
	state.tiles = PackedByteArray()
	state.tiles.resize(BomberState.COLS * BomberState.ROWS)
	state.prizes = PackedByteArray()
	state.prizes.resize(state.tiles.size())
	state.flames = PackedByteArray()
	state.flames.resize(state.tiles.size())

	for row in BomberState.ROWS:
		for col in BomberState.COLS:
			var index := BomberState.index_of(col, row)
			state.tiles[index] = _initial_tile(state, col, row)
			state.prizes[index] = (
				_roll_prize(state) if state.tiles[index] == BomberState.Tile.BRICK
				else BomberState.Prize.NONE
			)

	for seat in state.seats:
		var home := spawn_cell(seat)
		var player := BomberState.Bomber.new()
		player.x = home.x * BomberState.CELL + HALF
		player.y = home.y * BomberState.CELL + HALF
		state.players.append(player)
	return state


static func _initial_tile(state: BomberState, col: int, row: int) -> int:
	if col == 0 or row == 0 or col == BomberState.COLS - 1 or row == BomberState.ROWS - 1:
		return BomberState.Tile.SOLID
	# O xadrez de pilares: casa de coluna e linha pares (contando a borda) é
	# concreto. É o que dá ao mapa os corredores de largura um.
	if col % 2 == 0 and row % 2 == 0:
		return BomberState.Tile.SOLID
	if _spawn_is_clear(col, row, state.seats):
		return BomberState.Tile.FLOOR
	return (
		BomberState.Tile.BRICK if _random_below(state, 100) < BRICK_CHANCE
		else BomberState.Tile.FLOOR
	)


static func _roll_prize(state: BomberState) -> int:
	for entry in PRIZE_ODDS:
		if _random_below(state, 100) < int(entry[1]):
			return int(entry[0])
	return BomberState.Prize.NONE


## Um tique. `inputs` traz um byte por assento, na ordem dos assentos.
##
## A ordem das etapas é regra de jogo, e não arrumação: o fogo do tique anterior
## mata **antes** de os bonecos andarem, senão dava para atravessar a chama de
## raspão entre dois tiques; e as bombas contam o pavio depois de todo mundo se
## mexer, para quem soltou ainda conseguir sair de cima dela.
func step(state: BomberState, inputs: PackedByteArray) -> void:
	_expire_flames(state)
	_kill_in_flames(state)
	for seat in state.players.size():
		var command := inputs[seat] if seat < inputs.size() else 0
		_move_player(state, seat, command)
	_release_bombs(state)
	for seat in state.players.size():
		var command := inputs[seat] if seat < inputs.size() else 0
		if command & IN_BOMB:
			_drop_bomb(state, seat)
	_burn_fuses(state)
	_kill_in_flames(state)
	state.tick += 1


func _expire_flames(state: BomberState) -> void:
	for index in state.flames.size():
		if state.flames[index] > 0:
			state.flames[index] -= 1


func _kill_in_flames(state: BomberState) -> void:
	for seat in state.players.size():
		var player := state.players[seat]
		if not player.alive:
			continue
		var index := BomberState.index_of(player.x / BomberState.CELL, player.y / BomberState.CELL)
		if index >= 0 and index < state.flames.size() and state.flames[index] > 0:
			player.alive = false
			player.died_at = state.tick


## Anda um eixo por vez, na ordem em que os bits foram pedidos.
##
## Um eixo por tique e não os dois: na diagonal o boneco andaria 1,41 casa por
## tique e passaria pela quina de dois pilares — e "passar pela quina" é a
## diferença entre um labirinto e um campo aberto.
func _move_player(state: BomberState, seat: int, command: int) -> void:
	var player := state.players[seat]
	if not player.alive:
		return
	var direction := -1
	if command & IN_UP:
		direction = 0
	elif command & IN_DOWN:
		direction = 1
	elif command & IN_LEFT:
		direction = 2
	elif command & IN_RIGHT:
		direction = 3
	if direction < 0:
		return

	player.facing = direction
	var step_vector: Vector2i = DIRS[direction]
	var wanted_x := player.x + step_vector.x * player.speed
	var wanted_y := player.y + step_vector.y * player.speed
	if _can_stand(state, seat, wanted_x, wanted_y):
		player.x = wanted_x
		player.y = wanted_y
		_collect(state, seat)
		return

	# Bateu. Antes de desistir, tenta o empurrão para o meio do corredor: quem
	# pediu "direita" quase alinhado com o corredor quis dizer direita.
	# Tipo escrito: o `:=` num ternário faz o GDScript inferir `Variant`, e o
	# `signi()` abaixo recusa Variant. É o mesmo tropeço que a mesa de troca de
	# Metrópole já registrou.
	var offset: int = (
		(player.y % BomberState.CELL) - HALF if step_vector.x != 0
		else (player.x % BomberState.CELL) - HALF
	)
	if absi(offset) > NUDGE_RANGE or offset == 0:
		return
	var nudge := -signi(offset) * mini(NUDGE, absi(offset))
	var slid_x := player.x + (nudge if step_vector.x == 0 else 0)
	var slid_y := player.y + (nudge if step_vector.x != 0 else 0)
	if _can_stand(state, seat, slid_x, slid_y):
		player.x = slid_x
		player.y = slid_y
		_collect(state, seat)


## O corpo do boneco cabe nesta posição?
##
## Confere os quatro cantos do corpo, e não o centro: com o centro, metade do
## boneco entraria na parede antes de alguém reclamar.
func _can_stand(state: BomberState, seat: int, x: int, y: int) -> bool:
	var half_body := BODY >> 1
	for corner in [
		Vector2i(x - half_body, y - half_body), Vector2i(x + half_body, y - half_body),
		Vector2i(x - half_body, y + half_body), Vector2i(x + half_body, y + half_body),
	]:
		var col: int = corner.x / BomberState.CELL
		var row: int = corner.y / BomberState.CELL
		if corner.x < 0 or corner.y < 0:
			return false
		if state.tile_at(col, row) != BomberState.Tile.FLOOR:
			return false
		if not _bomb_passable(state, seat, col, row):
			return false
	return true


## A bomba recém-posta não empurra ninguém que já estava em cima dela: a
## permissão está guardada na própria bomba, e [method _release_bombs] a retira
## de cada assento assim que ele sai.
##
## A permissão é do **assento** e não da posição, e essa foi a correção: com a
## posição, quem estava saindo travava no meio. O corpo tem 81% da casa, então
## durante a travessia ele ocupa duas — o centro já estava na casa seguinte
## enquanto o ombro ainda estava na bomba, e a conferência de canto reprovava o
## lance. O boneco ficava preso ao lado da própria bomba até ela estourar.
func _bomb_passable(state: BomberState, seat: int, col: int, row: int) -> bool:
	var bomb := state.bomb_at(col, row)
	return bomb == null or (bomb.pass_seats & (1 << seat)) != 0


## Tira a permissão de quem já saiu. Cada assento perde a dele sozinho; quando
## não sobra nenhum, a bomba é parede para todos.
func _release_bombs(state: BomberState) -> void:
	for bomb in state.bombs:
		if bomb.pass_seats == 0:
			continue
		for seat in state.players.size():
			var bit := 1 << seat
			if bomb.pass_seats & bit == 0:
				continue
			if not _body_overlaps(state.players[seat], bomb.col, bomb.row):
				bomb.pass_seats &= ~bit


## O corpo do boneco encosta nesta casa?
static func _body_overlaps(player: BomberState.Bomber, col: int, row: int) -> bool:
	var half_body := BODY >> 1
	var cell_left := col * BomberState.CELL
	var cell_top := row * BomberState.CELL
	return (
		player.x - half_body < cell_left + BomberState.CELL
		and player.x + half_body > cell_left
		and player.y - half_body < cell_top + BomberState.CELL
		and player.y + half_body > cell_top
	)


func _collect(state: BomberState, seat: int) -> void:
	var player := state.players[seat]
	var col := player.x / BomberState.CELL
	var row := player.y / BomberState.CELL
	var index := BomberState.index_of(col, row)
	if state.tiles[index] != BomberState.Tile.FLOOR:
		return
	match state.prizes[index]:
		BomberState.Prize.BOMB:
			player.bombs = mini(MAX_BOMBS, player.bombs + 1)
		BomberState.Prize.FLAME:
			player.flame = mini(MAX_FLAME, player.flame + 1)
		BomberState.Prize.SPEED:
			player.speed = mini(MAX_SPEED, player.speed + SPEED_STEP)
		_:
			return
	state.prizes[index] = BomberState.Prize.NONE


func _drop_bomb(state: BomberState, seat: int) -> void:
	var player := state.players[seat]
	if not player.alive:
		return
	var live := 0
	for bomb in state.bombs:
		if bomb.owner == seat:
			live += 1
	if live >= player.bombs:
		return
	var col := player.x / BomberState.CELL
	var row := player.y / BomberState.CELL
	if state.bomb_at(col, row) != null:
		return
	var bomb := BomberState.Bomb.new()
	bomb.col = col
	bomb.row = row
	bomb.owner = seat
	bomb.fuse = FUSE
	bomb.flame = player.flame
	# Todo mundo que já está encostando na casa recebe a permissão, e não só quem
	# pôs: a bomba nasce debaixo do pé dos outros também, e um boneco emparedado
	# pela bomba alheia no instante em que ela aparece não tem para onde andar.
	for other in state.players.size():
		if state.players[other].alive and _body_overlaps(state.players[other], col, row):
			bomb.pass_seats |= 1 << other
	state.bombs.append(bomb)


## Conta os pavios e detona os que chegaram a zero, junto com os que a explosão
## alcançar — a reação em cadeia é resolvida numa fila, e não por recursão: uma
## corrente de vinte bombas é comum no fim da partida, e recursão ali é uma pilha
## funda por um laço que cabe em cinco linhas.
func _burn_fuses(state: BomberState) -> void:
	var queue: Array[BomberState.Bomb] = []
	for bomb in state.bombs:
		bomb.fuse -= 1
		if bomb.fuse <= 0:
			queue.append(bomb)

	var exploded := {}
	while not queue.is_empty():
		var bomb: BomberState.Bomb = queue.pop_front()
		if exploded.has(bomb):
			continue
		exploded[bomb] = true
		_blast(state, bomb, queue)

	var survivors: Array[BomberState.Bomb] = []
	for bomb in state.bombs:
		if not exploded.has(bomb):
			survivors.append(bomb)
	state.bombs = survivors


## O fogo de uma bomba: a casa dela e quatro braços.
##
## Cada braço para na primeira parede. Numa caixa ele para **depois** de
## derrubá-la — a caixa queima e o fogo não passa —, e é isso que faz abrir
## caminho custar uma bomba por caixa.
func _blast(state: BomberState, bomb: BomberState.Bomb, queue: Array[BomberState.Bomb]) -> void:
	_ignite(state, bomb.col, bomb.row, queue)
	for step_vector in DIRS:
		for distance in range(1, bomb.flame + 1):
			var col: int = bomb.col + step_vector.x * distance
			var row: int = bomb.row + step_vector.y * distance
			var tile := state.tile_at(col, row)
			if tile == BomberState.Tile.SOLID:
				break
			_ignite(state, col, row, queue)
			if tile == BomberState.Tile.BRICK:
				break


func _ignite(state: BomberState, col: int, row: int, queue: Array[BomberState.Bomb]) -> void:
	var index := BomberState.index_of(col, row)
	if index < 0 or index >= state.flames.size():
		return
	state.flames[index] = FLAME_TICKS
	if state.tiles[index] == BomberState.Tile.BRICK:
		# A caixa vira chão e o prêmio dela fica exposto na mesma casa. Ele
		# sobrevive ao fogo de propósito: um prêmio que some junto com a caixa que
		# o guardava é um prêmio que ninguém nunca vê.
		state.tiles[index] = BomberState.Tile.FLOOR
	var chained := state.bomb_at(col, row)
	if chained != null and chained.fuse > 0:
		chained.fuse = 0
		queue.append(chained)


## Assento vencedor, -1 enquanto houver mais de um de pé, e -2 no empate em que
## todos morreram no mesmo fogo.
func winner(state: BomberState) -> int:
	var alive := -1
	var total := 0
	for seat in state.players.size():
		if state.players[seat].alive:
			alive = seat
			total += 1
	if total > 1:
		return -1
	return alive if total == 1 else -2
