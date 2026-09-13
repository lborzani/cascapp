class_name BomberBot
extends RefCounted

## O adversário de Bomberman: sem busca, só medo e oportunismo.
##
## O `Bot` minimax dos outros jogos não serve aqui, e não é questão de ajuste. Ele
## precisa de "quais lances existem" e "de quem é a vez"; nesta partida os quatro
## agem no mesmo instante, e o espaço de decisão de um segundo de jogo tem trinta
## tiques por jogador — a árvore de um segundo já tem cinco elevado a cento e
## vinte folhas.
##
## O que funciona num jogo assim é uma máquina de prioridades, e ela cabe em três
## perguntas feitas nesta ordem:
##
## 1. **estou no caminho de um fogo?** Então a única coisa que importa é sair.
## 2. **dá para abrir caminho ou acertar alguém daqui?** Então põe a bomba — mas
##    só se houver para onde correr depois.
## 3. **senão**, anda na direção do que interessa: caixa para quebrar, jogador
##    para caçar.
##
## A ordem é a regra. Um bot que decidisse "atacar" antes de "fugir" morreria da
## própria bomba, e é exatamente assim que um bot de Bomberman mal escrito se
## denuncia nos primeiros dez segundos.
##
## ## Determinismo
##
## O bot roda dentro da simulação, então ele **não pode** sortear nada de fora
## nem olhar o relógio: dois aparelhos rodando o mesmo bot no mesmo tique têm de
## pedir o mesmo comando. Toda a decisão sai do estado, e o desempate é por ordem
## fixa de direção.

## Tiques de folga que o bot exige entre a bomba e o fogo antes de se arriscar.
## Sem margem ele calcula a fuga exata e morre no arredondamento; com margem
## demais ele nunca põe bomba nenhuma.
const ESCAPE_MARGIN := 12

## Até onde ele procura alvo. O mapa inteiro cabe, e limitar existe para o bot
## não atravessar o mapa ignorando a caixa ao lado.
const HUNT_RANGE := 10

## Distância a partir da qual ele prefere caçar jogador a quebrar caixa. Perto, o
## jogador é o alvo; longe, quebrar caixa é o que abre o caminho até ele.
const CHASE_RANGE := 4

## Por quantos tiques o bot fica com o alvo escolhido. Meio segundo é mais que o
## tempo de andar uma casa (oito tiques), então ele chega antes de reconsiderar —
## e é curto o bastante para reagir a uma bomba que fechou o caminho.
const COMMIT_TICKS := 15

## Folga, em unidades, dentro da qual o bot se considera alinhado ao corredor.
## Menor que um passo (32) faria ele corrigir para sempre sem nunca acertar.
const ALIGN_TOLERANCE := 34

## Alvo de caminhada por assento, `{seat: {"cell": Vector2i, "ttl": int}}`.
var _targets := {}


## O comando deste tique para este assento.
func decide(state: BomberState, seat: int) -> int:
	_current_seat = seat
	var player := state.players[seat]
	if not player.alive:
		return 0
	var col := player.x / BomberState.CELL
	var row := player.y / BomberState.CELL
	var danger := _danger_map(state)

	if danger[BomberState.index_of(col, row)] > 0:
		return _step_toward(state, col, row, _nearest_safe(state, col, row, danger))

	# A capacidade é conferida **antes** de querer atacar, e não depois.
	#
	# Sem esta linha o bot pedia bomba enquanto a anterior dele ainda queimava, o
	# pedido era recusado lá dentro, e ele devolvia um comando sem direção: ficava
	# parado ao lado da caixa até o próprio pavio acabar. Medido, dava 128 pedidos
	# para 5 bombas postas, e um mapa que quase não abria em cem segundos.
	#
	# Ele não pode "descobrir" a recusa depois porque o comando é o que ele
	# entrega ao tique — não há resposta a receber.
	var attack := _can_place(state, seat) and _worth_bombing(state, seat, col, row)
	if attack and _has_escape(state, col, row, player.flame):
		return BomberRules.IN_BOMB

	# Duas coisas diferentes, e confundi-las foi o bug: `target` é **para onde ele
	# está indo** — uma casa qualquer do mapa —, e `next` é a casa vizinha em que
	# ele pisa neste tique. A memória guarda o destino; o caminho é refeito todo
	# tique, porque uma bomba pode ter fechado o corredor desde ontem.
	var here := Vector2i(col, row)
	var target := _committed_target(state, seat, col, row, danger)
	var next := _step_target(state, here, target, danger)
	# Alvo sem caminho é alvo vencido, e esperar os quinze tiques do compromisso
	# olhando para uma parede é tempo que o bot passa imóvel. Esquecer aqui faz o
	# tique seguinte escolher outro — quase sempre a caixa que fecha o corredor.
	if next == here and target != here:
		_targets.erase(seat)
	return _step_toward(state, col, row, next)


## O alvo de caminhada, **guardado** entre tiques.
##
## Sem memória o bot andava em círculo, e o rastro era literal: `1,2 1,3 1,2 1,3`
## até o fim da partida. A causa não é o caminho estar errado — é o alvo ser
## recalculado do zero a cada tique. De (1,2) a caixa mais perto fica de um lado;
## assim que ele dá um passo e vira (1,3), fica do outro. Cada busca acerta, e as
## duas juntas produzem um bot que nunca chega.
##
## Ele então escolhe um alvo e **fica com ele** até chegar, até o alvo deixar de
## fazer sentido, ou até o prazo acabar. O prazo existe para o bot não teimar num
## alvo que ficou inalcançável — uma bomba pode fechar o corredor no meio do
## caminho.
##
## Isto torna o bot **com estado**, e isso tem consequência na rede: dois
## aparelhos só chegam ao mesmo comando se rodarem o bot desde o mesmo começo,
## tique a tique. É uma restrição a respeitar quando a partida em rede entrar, e
## a alternativa — um aparelho decidir pelas máquinas e mandar os comandos — já é
## o desenho que os outros jogos usam.
func _committed_target(
	state: BomberState, seat: int, col: int, row: int, danger: PackedInt32Array
) -> Vector2i:
	var here := Vector2i(col, row)
	var memory: Dictionary = _targets.get(seat, {})
	var goal: Vector2i = memory.get("cell", here)
	var left := int(memory.get("ttl", 0))
	# Um alvo que virou zona de fogo deixa de ser alvo na hora: o compromisso de
	# quinze tiques existe para o bot não redecidir a cada passo, e não para ele
	# insistir em andar para dentro de uma explosão.
	var goal_safe := danger[BomberState.index_of(goal.x, goal.y)] == 0
	if left > 0 and goal != here and goal_safe and _still_useful(state, goal):
		_targets[seat] = {"cell": goal, "ttl": left - 1}
		return goal
	goal = _hunt(state, seat, col, row, danger)
	_targets[seat] = {"cell": goal, "ttl": COMMIT_TICKS}
	return goal


## O alvo continua valendo? Vale enquanto der para pisar nele e ainda houver o que
## fazer lá — a caixa que ele ia quebrar pode ter sido quebrada por outro.
func _still_useful(state: BomberState, goal: Vector2i) -> bool:
	if not _walkable(state, goal.x, goal.y):
		return false
	for step: Vector2i in BomberRules.DIRS:
		if state.tile_at(goal.x + step.x, goal.y + step.y) == BomberState.Tile.BRICK:
			return true
	# Sem caixa em volta, o alvo só serve se for a caçada de alguém.
	for player in state.players:
		if not player.alive:
			continue
		var cell := Vector2i(player.x / BomberState.CELL, player.y / BomberState.CELL)
		if absi(cell.x - goal.x) + absi(cell.y - goal.y) <= CHASE_RANGE:
			return true
	return false


## Sobrou bomba na mão deste assento? Mesma conta de [method BomberRules._drop_bomb],
## feita de fora: o bot precisa saber a resposta antes de pedir.
func _can_place(state: BomberState, seat: int) -> bool:
	var live := 0
	for bomb in state.bombs:
		if bomb.owner == seat:
			live += 1
	return live < state.players[seat].bombs


## Casas que o fogo vai alcançar, com quantos tiques faltam para isso.
##
## Zero é casa segura. Um número é "aqui vai queimar em tantos tiques", e é o que
## permite ao bot passar por uma casa que só queima daqui a dois segundos em vez
## de tratar o mapa inteiro como proibido assim que alguém solta uma bomba.
func _danger_map(state: BomberState) -> PackedInt32Array:
	var danger := PackedInt32Array()
	danger.resize(BomberState.COLS * BomberState.ROWS)
	for bomb in state.bombs:
		_mark(danger, state, bomb.col, bomb.row, bomb.fuse)
		for step: Vector2i in BomberRules.DIRS:
			for distance in range(1, bomb.flame + 1):
				var col := bomb.col + step.x * distance
				var row := bomb.row + step.y * distance
				var tile := state.tile_at(col, row)
				if tile == BomberState.Tile.SOLID:
					break
				_mark(danger, state, col, row, bomb.fuse)
				if tile == BomberState.Tile.BRICK:
					break
	# O fogo aceso agora é o perigo mais urgente que existe.
	for index in state.flames.size():
		if state.flames[index] > 0:
			danger[index] = 1
	return danger


static func _mark(danger: PackedInt32Array, state: BomberState, col: int, row: int, fuse: int) -> void:
	var index := BomberState.index_of(col, row)
	if index < 0 or index >= danger.size():
		return
	# O menor tempo manda: duas bombas mirando a mesma casa, vale a que chega antes.
	if danger[index] == 0 or fuse + 1 < danger[index]:
		danger[index] = fuse + 1


func _walkable(state: BomberState, col: int, row: int) -> bool:
	if state.tile_at(col, row) != BomberState.Tile.FLOOR:
		return false
	return state.bomb_at(col, row) == null


## Busca em largura até a casa segura mais próxima, e devolve a **primeira** casa
## do caminho — é para lá que o bot anda neste tique.
##
## Em largura e não em profundidade: o que se quer é o abrigo mais perto, e uma
## busca em profundidade acharia um abrigo qualquer do outro lado do mapa
## enquanto o fogo sobe.
func _nearest_safe(
	state: BomberState, col: int, row: int, danger: PackedInt32Array
) -> Vector2i:
	var start := Vector2i(col, row)
	var came := {start: start}
	var queue: Array[Vector2i] = [start]
	var steps := {start: 0}
	while not queue.is_empty():
		var here: Vector2i = queue.pop_front()
		var index := BomberState.index_of(here.x, here.y)
		var distance: int = steps[here]
		# Segura, e dá tempo de chegar: um abrigo que estoura antes de o bot pisar
		# nele não é abrigo. Cada casa custa uns oito tiques de caminhada.
		if danger[index] == 0 and here != start:
			return _first_step(came, start, here)
		for step: Vector2i in BomberRules.DIRS:
			var next := here + step
			if came.has(next) or not _walkable(state, next.x, next.y):
				continue
			var next_index := BomberState.index_of(next.x, next.y)
			var arrival := (distance + 1) * 8
			if danger[next_index] > 0 and danger[next_index] < arrival + ESCAPE_MARGIN:
				continue
			came[next] = here
			steps[next] = distance + 1
			queue.append(next)
	# Encurralado: fica onde está em vez de andar para dentro do fogo.
	return start


static func _first_step(came: Dictionary, start: Vector2i, goal: Vector2i) -> Vector2i:
	var here := goal
	while came.has(here) and came[here] != start:
		here = came[here]
	return here


## Vale a pena soltar uma bomba daqui? Vale se ela derruba caixa ou pega jogador.
func _worth_bombing(state: BomberState, seat: int, col: int, row: int) -> bool:
	var player := state.players[seat]
	# A casa da própria bomba também queima, e dois bonecos dividem casa o tempo
	# todo — o corpo tem 81% da casa. Sem esta conferência o bot encostava no
	# adversário e não via alvo nenhum: os braços do fogo começam na casa **ao
	# lado**, e o inimigo estava debaixo do pé dele.
	for other in state.players.size():
		if other == seat or not state.players[other].alive:
			continue
		var enemy := state.players[other]
		if enemy.x / BomberState.CELL == col and enemy.y / BomberState.CELL == row:
			return true
	for step: Vector2i in BomberRules.DIRS:
		for distance in range(1, player.flame + 1):
			var target_col := col + step.x * distance
			var target_row := row + step.y * distance
			var tile := state.tile_at(target_col, target_row)
			if tile == BomberState.Tile.SOLID:
				break
			if tile == BomberState.Tile.BRICK:
				return true
			for other in state.players.size():
				if other == seat or not state.players[other].alive:
					continue
				var enemy := state.players[other]
				if enemy.x / BomberState.CELL == target_col and enemy.y / BomberState.CELL == target_row:
					return true
	return false


## Existe abrigo depois desta bomba? A pergunta é feita **antes** de pôr, com a
## bomba imaginada no lugar — é a diferença entre um bot que abre caminho e um
## que se explode abrindo caminho.
func _has_escape(state: BomberState, col: int, row: int, flame: int) -> bool:
	var imagined := state.clone()
	var bomb := BomberState.Bomb.new()
	bomb.col = col
	bomb.row = row
	bomb.fuse = BomberRules.FUSE
	bomb.flame = flame
	# Quem pôs pode atravessar a própria bomba enquanto sai; sem isto o bot se
	# considera preso pela bomba que ele mesmo ia pôr, e nunca põe nenhuma.
	bomb.pass_seats = 0xF
	imagined.bombs.append(bomb)
	var danger := _danger_map(imagined)
	return _nearest_safe(imagined, col, row, danger) != Vector2i(col, row)


## Para **onde ir**: jogador perto, senão a casa colada na caixa mais próxima.
##
## Devolve o destino, e não o próximo passo. A diferença parece de nomenclatura e
## é a que fazia o bot andar em círculo: guardando o vizinho como alvo, ele
## chegava no alvo em oito tiques, redecidia, e a decisão nova apontava para trás.
func _hunt(
	state: BomberState, seat: int, col: int, row: int, danger: PackedInt32Array
) -> Vector2i:
	var start := Vector2i(col, row)
	var best_enemy := Vector2i(-1, -1)
	var best_distance := HUNT_RANGE + 1
	for other in state.players.size():
		if other == seat or not state.players[other].alive:
			continue
		var enemy := state.players[other]
		var cell := Vector2i(enemy.x / BomberState.CELL, enemy.y / BomberState.CELL)
		var distance := absi(cell.x - col) + absi(cell.y - row)
		if distance < best_distance:
			best_distance = distance
			best_enemy = cell
	# Caçar quem já está na casa em que o bot está é pedir para ficar parado: o
	# alvo é a casa dele mesmo, o caminho tem tamanho zero, e o comando sai vazio.
	# Dois bots assim se encaravam até o fim da partida. Quem divide casa com o
	# adversário não caça — bombardeia, e é o ramo acima que resolve.
	# A caçada só vale se houver caminho. Quatro casas de distância em linha reta
	# no mapa não são quatro casas de caminho: com uma caixa no meio do corredor, o
	# adversário está a uma parede de distância, e o bot que o escolhe como alvo
	# fica parado apontando para ele até o fim da partida — medido, 1660 tiques de
	# 1800. Sem caminho, o que aproxima os dois é justamente quebrar a caixa, e é o
	# que a busca abaixo vai achar.
	if (
		best_enemy.x >= 0 and best_distance <= CHASE_RANGE and best_enemy != start
		and _step_target(state, start, best_enemy, danger) != start
	):
		return best_enemy

	# Caixa mais próxima. Ela não é andável, então o destino é a casa colada nela.
	#
	# Com a mão vazia, a casa em que ele **já está** não conta como destino: sem
	# esta ressalva o bot plantava-se ao lado de uma caixa que não podia quebrar e
	# esperava o próprio pavio — 1944 tiques parado em 3600, medidos. Sem bomba na
	# mão, o que resta a fazer é procurar a próxima caixa.
	var idle_here := not _can_place(state, seat)
	var queue: Array[Vector2i] = [start]
	var came := {start: start}
	var steps := {start: 0}
	while not queue.is_empty():
		var here: Vector2i = queue.pop_front()
		var distance: int = steps[here]
		for step: Vector2i in BomberRules.DIRS:
			var next := here + step
			if state.tile_at(next.x, next.y) == BomberState.Tile.BRICK:
				if here != start or not idle_here:
					return here
				continue
			if came.has(next) or not _walkable(state, next.x, next.y):
				continue
			if not _crossable(danger, next, distance + 1):
				continue
			came[next] = here
			steps[next] = distance + 1
			queue.append(next)
	return best_enemy if best_enemy.x >= 0 and best_enemy != start else start


## Um passo em direção a um alvo, por busca em largura pelo caminho andável.
##
## O caminho desvia do fogo, e isto **não** é redundante com o ramo da fuga.
## Aquele responde "estou queimando, para onde corro"; este responde "estou a
## salvo, por onde vou". Sem o desvio aqui, o bot a salvo na divisa da casa
## seguinte voltava para dentro da bomba de onde tinha acabado de sair — a casa
## dele vira a de trás, o ramo da fuga liga, ele volta meio passo, a casa vira a
## da frente, e o rastro era `FOGE@1,3 anda@1,2 FOGE@1,3` até o fogo subir. Não é
## o alvo que oscila: é a resposta à pergunta "estou em perigo".
##
## Alvo inalcançável não devolve "fique parado", devolve **o passo que mais
## aproxima**. A diferença apareceu numa partida de mapa limpo: o adversário
## estava ao lado da própria bomba, a casa dele ficou marcada, a busca nunca
## chegava, e o bot do outro canto ficou 862 tiques imóvel esperando um caminho
## que o fogo abriria em três segundos. Aproximar-se do que não dá para alcançar
## agora é o que o põe em posição de alcançar depois.
func _step_target(
	state: BomberState, start: Vector2i, goal: Vector2i, danger: PackedInt32Array
) -> Vector2i:
	if goal == start:
		return start
	var queue: Array[Vector2i] = [start]
	var came := {start: start}
	var steps := {start: 0}
	# O melhor consolo visto até agora. Empate fica com quem a busca em largura
	# viu primeiro, e a ordem dela é fixa — o desempate não pode ser sorteado.
	var closest := start
	var closest_gap := absi(start.x - goal.x) + absi(start.y - goal.y)
	while not queue.is_empty():
		var here: Vector2i = queue.pop_front()
		if here == goal:
			return _first_step(came, start, here)
		var gap := absi(here.x - goal.x) + absi(here.y - goal.y)
		if gap < closest_gap:
			closest_gap = gap
			closest = here
		var distance: int = steps[here]
		for step: Vector2i in BomberRules.DIRS:
			var next := here + step
			if came.has(next) or not _walkable(state, next.x, next.y):
				continue
			if not _crossable(danger, next, distance + 1):
				continue
			came[next] = here
			steps[next] = distance + 1
			queue.append(next)
	return start if closest == start else _first_step(came, start, closest)


## Dá para passar por esta casa a caminho de outra coisa?
##
## Mesma conta da fuga: casa sem perigo passa; casa marcada só passa se o fogo
## chegar bem depois do bot. Cada casa custa uns oito tiques de caminhada.
static func _crossable(danger: PackedInt32Array, cell: Vector2i, distance: int) -> bool:
	var index := BomberState.index_of(cell.x, cell.y)
	if index < 0 or index >= danger.size():
		return false
	if danger[index] == 0:
		return true
	return danger[index] >= distance * 8 + ESCAPE_MARGIN


## O comando que leva da casa atual à vizinha escolhida.
##
## Mira o **centro** da casa vizinha, em unidades, e não a casa. A versão que
## comparava só coordenadas de casa fazia o bot tremer em cima da divisa: ele
## andava 32 unidades, o centro cruzava a fronteira, a casa dele mudava, a busca
## era refeita da casa nova e apontava para trás. O rastro era literal —
## `1,2 1,3 1,2 1,3` até morrer —, e nenhuma memória de alvo conserta isso, porque
## o que oscila não é o alvo: é a resposta à pergunta "em que casa eu estou".
##
## Alinhar o eixo perpendicular **antes** de avançar é a outra metade. O boneco
## fora do meio do corredor encosta na quina do pilar e para; o empurrão de quina
## de [BomberRules] existe para o polegar humano, que não sabe mirar, e o bot não
## deve depender dele.
## Sem para onde ir — abrigo bloqueado, caminho fechado pelo fogo alheio — ele
## não fica onde parou: ele acaba de entrar na casa. Parar em cima da divisa é o
## que faz o bot **parecer** preso, e não é só aparência: o corpo tem 81% da
## casa, então quem para na borda deixa o ombro dentro da casa vizinha, que é
## justamente a que está para queimar. Quem mata é a casa do centro, e por isso o
## bot sobrevivia ali — mas na tela ele estava metido no fogo, imóvel.
func _step_toward(state: BomberState, col: int, row: int, goal: Vector2i) -> int:
	if state == null or goal.x < 0:
		return 0
	# `goal` igual à casa atual não é caso à parte: mirar o centro dela é
	# exatamente o comando de se recolher para o meio do corredor.
	return _aim_at(state.players[_current_seat], goal, col)


## Guardado entre as duas chamadas porque `_step_toward` só recebe a casa, e o
## comando depende da posição exata de **quem** está andando.
var _current_seat := 0


func _aim_at(player: BomberState.Bomber, goal: Vector2i, col: int) -> int:
	var goal_x := goal.x * BomberState.CELL + (BomberState.CELL >> 1)
	var goal_y := goal.y * BomberState.CELL + (BomberState.CELL >> 1)
	var dx := goal_x - player.x
	var dy := goal_y - player.y
	if goal.x != col:
		# Andando na horizontal: primeiro centraliza na linha, depois avança.
		if absi(dy) > ALIGN_TOLERANCE:
			return BomberRules.IN_DOWN if dy > 0 else BomberRules.IN_UP
		return BomberRules.IN_RIGHT if dx > 0 else BomberRules.IN_LEFT
	if absi(dx) > ALIGN_TOLERANCE:
		return BomberRules.IN_RIGHT if dx > 0 else BomberRules.IN_LEFT
	# Chegou é "chegou perto o bastante", e a tolerância é a mesma dos dois eixos.
	# Exigir `dy == 0` só funciona a 32 unidades por tique, que é a velocidade de
	# fábrica: com um prêmio de velocidade o passo vira 38, o centro cai entre dois
	# passos, e o bot pedia baixo-cima-baixo para sempre a doze unidades do meio da
	# casa. A tolerância é menor que meia casa, então parar dentro dela não muda em
	# que casa ele está.
	if absi(dy) <= ALIGN_TOLERANCE:
		return 0
	return BomberRules.IN_DOWN if dy > 0 else BomberRules.IN_UP


