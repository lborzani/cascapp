extends SceneTree

## A simulação de Bomberman, sem tela e sem rede.
##
##   godot --headless --path . --script res://tests/bomber_probe.gd
##
## O teste que sustenta os outros é o de **determinismo**. Este é o primeiro jogo
## do app em que os aparelhos não trocam posições: cada um roda a mesma simulação
## com os mesmos comandos e confia que chegou ao mesmo lugar. Se essa promessa
## falhar, o sintoma não é um erro — é um jogador vivo numa tela e morto na outra,
## vinte segundos depois da divergência, sem nada apontando para a causa.
##
## Por isso a suíte confere o estado **inteiro** depois de centenas de tiques, e
## não só o que cada regra faz isoladamente.

var _failures := 0
var _rules := BomberRules.new()


func _initialize() -> void:
	_test_map()
	_test_determinism()
	_test_walls()
	_test_bomb_and_flame()
	_test_chain()
	_test_bomb_limit()
	_test_standing_on_own_bomb()
	_test_bomb_under_a_neighbour()
	_test_prizes()
	_test_winner()
	_test_bots()
	_test_lockstep()
	_test_lockstep_drop()
	_test_two_devices()

	if _failures == 0:
		print("OK — simulação de Bomberman consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


## O mapa nasce jogável: bordas fechadas, pilares no xadrez, e os quatro cantos
## livres. A última é a que importa — um jogador que nasce emparedado perde a
## partida sem tocar na tela.
func _test_map() -> void:
	print("mapa inicial")
	var state := _rules.initial_state(4, 12345)

	var border_ok := true
	for col in BomberState.COLS:
		border_ok = border_ok and state.tile_at(col, 0) == BomberState.Tile.SOLID
		border_ok = border_ok and state.tile_at(col, BomberState.ROWS - 1) == BomberState.Tile.SOLID
	_check(border_ok, "a borda é toda de concreto")

	_equals(state.tile_at(2, 2), BomberState.Tile.SOLID, "pilar na casa par/par")
	_equals(state.tile_at(1, 1), BomberState.Tile.FLOOR, "e o canto de nascimento é chão")

	var clear := true
	for seat in 4:
		var home := BomberRules.spawn_cell(seat)
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var col := home.x + step.x
			var row := home.y + step.y
			var tile := state.tile_at(col, row)
			clear = clear and tile != BomberState.Tile.BRICK
	_check(clear, "nenhum canto nasce fechado por caixa")

	_equals(state.players.size(), 4, "quatro bonecos na mesa")
	_equals(
		state.players[0].x, BomberRules.spawn_cell(0).x * BomberState.CELL + BomberRules.HALF,
		"e centrados na casa deles"
	)


## Mesma semente e mesmos comandos dão a mesma partida; sementes diferentes dão
## partidas diferentes. As duas metades importam: sem a segunda, um gerador
## quebrado que devolvesse sempre zero passaria na primeira.
func _test_determinism() -> void:
	print("determinismo")
	var left := _rules.initial_state(4, 987)
	var right := _rules.initial_state(4, 987)
	var other := _rules.initial_state(4, 988)
	_check(_same_map(left, right), "a mesma semente monta o mesmo mapa")
	_check(not _same_map(left, other), "e outra semente monta outro")

	# Trezentos tiques — dez segundos — com comandos que variam por assento e por
	# tique, incluindo bombas. É tempo de sobra para uma divergência de uma unidade
	# virar posições diferentes.
	for tick in 300:
		var inputs := _scripted_inputs(tick)
		_rules.step(left, inputs)
		_rules.step(right, inputs)
	_check(_same_map(left, right), "e depois de 300 tiques o mapa continua igual")
	_check(_same_players(left, right), "com os bonecos no mesmo lugar")
	_equals(left.seed_state, right.seed_state, "e o gerador no mesmo ponto")

	# A cópia também é a partida: é dela que a tela desenha e o bot pensa.
	var copy := left.clone()
	for tick in 60:
		var inputs := _scripted_inputs(tick)
		_rules.step(left, inputs)
		_rules.step(copy, inputs)
	_check(_same_map(left, copy), "e um clone segue a mesma partida")
	_check(_same_players(left, copy), "com os mesmos bonecos")


## Comandos que dão movimento de verdade em vez de todo mundo andando igual: cada
## assento vira em tempos diferentes, e solta bomba em tempos diferentes.
static func _scripted_inputs(tick: int) -> PackedByteArray:
	var inputs := PackedByteArray()
	inputs.resize(4)
	for seat in 4:
		var phase := (tick + seat * 17) % 40
		var command := 0
		if phase < 10:
			command = BomberRules.IN_RIGHT
		elif phase < 20:
			command = BomberRules.IN_DOWN
		elif phase < 30:
			command = BomberRules.IN_LEFT
		else:
			command = BomberRules.IN_UP
		if (tick + seat * 7) % 37 == 0:
			command |= BomberRules.IN_BOMB
		inputs[seat] = command
	return inputs


func _same_map(a: BomberState, b: BomberState) -> bool:
	return a.tiles == b.tiles and a.prizes == b.prizes and a.flames == b.flames


func _same_players(a: BomberState, b: BomberState) -> bool:
	if a.players.size() != b.players.size() or a.bombs.size() != b.bombs.size():
		return false
	for seat in a.players.size():
		var one := a.players[seat]
		var two := b.players[seat]
		if one.x != two.x or one.y != two.y or one.alive != two.alive:
			return false
		if one.bombs != two.bombs or one.flame != two.flame or one.speed != two.speed:
			return false
	return true


## Parede para de verdade, e corredor deixa passar.
func _test_walls() -> void:
	print("colisão")
	var state := _rules.initial_state(4, 555)
	# Mapa limpo em volta, para o teste medir a parede e não uma caixa sorteada.
	_clear_around(state, 1, 1, 3)
	var player := state.players[0]
	var start_y := player.y

	# Para cima do canto de nascimento só há a borda.
	for tick in 20:
		_rules.step(state, _one(0, BomberRules.IN_UP))
	_equals(player.y, start_y, "a borda não deixa sair do mapa")

	# Para a direita há corredor.
	for tick in 20:
		_rules.step(state, _one(0, BomberRules.IN_RIGHT))
	_check(player.x > BomberState.CELL + BomberRules.HALF, "o corredor deixa andar")
	_equals(player.y, start_y, "sem desviar de linha")


## A bomba explode na hora certa, o fogo alcança o que deve e a caixa cai.
func _test_bomb_and_flame() -> void:
	print("bomba e fogo")
	var state := _rules.initial_state(4, 777)
	_clear_around(state, 1, 1, 4)
	# Uma caixa plantada a duas casas: o fogo de alcance 1 não chega, o de 2 sim.
	state.tiles[BomberState.index_of(3, 1)] = BomberState.Tile.BRICK
	state.prizes[BomberState.index_of(3, 1)] = BomberState.Prize.NONE

	_rules.step(state, _one(0, BomberRules.IN_BOMB))
	_equals(state.bombs.size(), 1, "a bomba foi posta")
	_equals(state.bombs[0].fuse, BomberRules.FUSE - 1, "com o pavio contando")

	# Sai de cima dela antes de estourar.
	for tick in 20:
		_rules.step(state, _one(0, BomberRules.IN_DOWN))

	for tick in BomberRules.FUSE:
		if state.bombs.is_empty():
			break
		_rules.step(state, PackedByteArray([0, 0, 0, 0]))
	_equals(state.bombs.size(), 0, "e estourou no fim do pavio")
	_check(
		state.flames[BomberState.index_of(1, 1)] > 0,
		"com fogo na casa dela"
	)
	_check(
		state.flames[BomberState.index_of(2, 1)] > 0,
		"e na casa ao lado"
	)
	_equals(
		state.tiles[BomberState.index_of(3, 1)], BomberState.Tile.BRICK,
		"e a caixa a duas casas fica de pé: alcance 1 não chega lá"
	)
	# O pilar par/par corta o braço: o fogo não vira esquina nem atravessa.
	_equals(
		state.flames[BomberState.index_of(2, 2)], 0,
		"e o fogo não vaza para fora dos braços"
	)


## Uma bomba acende a outra, e a corrente resolve no mesmo tique.
func _test_chain() -> void:
	print("reação em cadeia")
	var state := _rules.initial_state(2, 31337)
	_clear_around(state, 1, 1, 6)
	var player := state.players[0]
	player.bombs = 3
	player.flame = 3

	_rules.step(state, _one(0, BomberRules.IN_BOMB))
	# Anda duas casas e põe a segunda, dentro do alcance da primeira.
	for tick in 16:
		_rules.step(state, _one(0, BomberRules.IN_RIGHT))
	_rules.step(state, _one(0, BomberRules.IN_BOMB))
	_equals(state.bombs.size(), 2, "duas bombas na mesa")
	var second_fuse := state.bombs[1].fuse
	_check(second_fuse > BomberRules.FUSE - 30, "a segunda mal começou o pavio")

	for tick in BomberRules.FUSE:
		if state.bombs.is_empty():
			break
		_rules.step(state, PackedByteArray([0, 0]))
	_equals(state.bombs.size(), 0, "a primeira levou a segunda junto")


## O teto de bombas simultâneas é o do jogador, e ele não solta duas na mesma casa.
func _test_bomb_limit() -> void:
	print("limite de bombas")
	var state := _rules.initial_state(2, 4242)
	_clear_around(state, 1, 1, 5)

	_rules.step(state, _one(0, BomberRules.IN_BOMB))
	_rules.step(state, _one(0, BomberRules.IN_BOMB))
	_equals(state.bombs.size(), 1, "com uma bomba de capacidade, sai uma só")

	state.players[0].bombs = 2
	for tick in 16:
		_rules.step(state, _one(0, BomberRules.IN_RIGHT))
	_rules.step(state, _one(0, BomberRules.IN_BOMB))
	_equals(state.bombs.size(), 2, "com duas, sai a segunda em outra casa")


## Quem põe a bomba sai de cima dela; depois de sair, ela vira parede para ele
## também. Sem a segunda metade, dá para se esconder dentro da própria bomba.
func _test_standing_on_own_bomb() -> void:
	print("bomba embaixo do pé")
	var state := _rules.initial_state(2, 909)
	_clear_around(state, 1, 1, 5)
	var player := state.players[0]

	_rules.step(state, _one(0, BomberRules.IN_BOMB))
	var start_x := player.x
	for tick in 16:
		_rules.step(state, _one(0, BomberRules.IN_RIGHT))
	_check(player.x > start_x, "saiu de cima da própria bomba")

	var left_x := player.x
	for tick in 16:
		_rules.step(state, _one(0, BomberRules.IN_LEFT))
	_check(player.x < left_x, "andou de volta")
	_check(
		player.x / BomberState.CELL > 1,
		"mas não voltou para dentro dela (parou na casa %d)" % (player.x / BomberState.CELL)
	)


## A bomba nasce debaixo do pé de quem estava junto, e quem estava junto tem de
## conseguir sair.
##
## O corpo tem 81% da casa, então dois bonecos dividem casa o tempo todo. Com a
## permissão de travessia guardada para um assento só, o outro ficava **imóvel**:
## as quatro posições candidatas dele encostavam na casa da bomba, o empurrão de
## quina também, e ele esperava o pavio sem poder andar. Era assim que o bot
## morria preso entre casas.
func _test_bomb_under_a_neighbour() -> void:
	print("bomba embaixo do pé do outro")
	var state := _rules.initial_state(2, 909)
	_clear_around(state, 1, 1, 5)
	var victim := state.players[0]
	# O dono da bomba encostado no vizinho, na mesma casa.
	state.players[1].x = victim.x
	state.players[1].y = victim.y

	_rules.step(state, _one(1, BomberRules.IN_BOMB))
	_equals(state.bombs.size(), 1, "a bomba do assento 1 saiu")

	var start_x := victim.x
	for tick in 16:
		_rules.step(state, _one(0, BomberRules.IN_RIGHT))
	_check(victim.x > start_x, "e o assento 0 conseguiu sair de cima dela")

	var left_x := victim.x
	for tick in 16:
		_rules.step(state, _one(0, BomberRules.IN_LEFT))
	_check(
		victim.x / BomberState.CELL > 1,
		"depois de sair, ela é parede para ele também (parou na casa %d)"
		% (victim.x / BomberState.CELL)
	)
	_check(victim.x < left_x, "mas ele andou de volta até encostar")


func _test_prizes() -> void:
	print("prêmios")
	var state := _rules.initial_state(2, 2024)
	_clear_around(state, 1, 1, 5)
	var player := state.players[0]
	var before := player.flame
	state.prizes[BomberState.index_of(2, 1)] = BomberState.Prize.FLAME

	for tick in 16:
		_rules.step(state, _one(0, BomberRules.IN_RIGHT))
	_equals(player.flame, before + 1, "andar por cima do prêmio recolhe")
	_equals(
		state.prizes[BomberState.index_of(2, 1)], BomberState.Prize.NONE,
		"e ele sai do mapa"
	)

	# Os tetos existem para a partida longa não virar sorte.
	player.flame = BomberRules.MAX_FLAME
	state.prizes[BomberState.index_of(3, 1)] = BomberState.Prize.FLAME
	for tick in 16:
		_rules.step(state, _one(0, BomberRules.IN_RIGHT))
	_equals(player.flame, BomberRules.MAX_FLAME, "o alcance para no teto")


func _test_winner() -> void:
	print("fim de partida")
	var state := _rules.initial_state(2, 606)
	_equals(_rules.winner(state), -1, "com dois de pé, ninguém venceu")
	state.players[1].alive = false
	_equals(_rules.winner(state), 0, "sobrando um, ele vence")
	state.players[0].alive = false
	_equals(_rules.winner(state), -2, "morrendo os dois no mesmo fogo, é empate")


## Quatro máquinas numa mesa, em três mapas diferentes.
##
## **Este teste guarda o mecanismo, não a qualidade do bot.** A distinção é
## deliberada e o estado dele está registrado no README: hoje ele sobrevive, põe
## bomba, quebra caixa e às vezes se mata sozinho. Não é um bom adversário, e
## fingir que é — escrevendo uma asserção fraca com nome de asserção forte — seria
## pior que não ter teste.
##
## O que **é** invariante e vale travar:
##
## - a decisão sempre sai, para qualquer estado, sem travar em busca infinita;
## - o comando cabe num byte, que é o que a rede vai carregar;
## - o bot mexe no mapa: um que nunca põe bomba passaria por "funcionando" numa
##   partida inteira sem nada acusar, e essa é a falha silenciosa que já apareceu
##   aqui uma vez;
## - a simulação sobrevive a mil tiques de máquina sem cair.
func _test_bots() -> void:
	print("bots")
	var bot := BomberBot.new()
	for match_seed in [11, 4242, 90210]:
		var state := _rules.initial_state(4, match_seed)
		var bricks_before := _count_bricks(state)
		var ticks := 0
		var clean := true
		while ticks < 1000 and _rules.winner(state) == -1:
			var inputs := PackedByteArray()
			inputs.resize(4)
			for seat in 4:
				var command := bot.decide(state, seat)
				clean = clean and command >= 0 and command <= 31
				inputs[seat] = command
			_rules.step(state, inputs)
			ticks += 1

		_check(clean, "semente %d: todo comando coube num byte de cinco bits" % match_seed)
		var bricks_after := _count_bricks(state)
		_check(
			bricks_after < bricks_before,
			"semente %d: as máquinas mexeram no mapa (%d caixas de %d)"
				% [match_seed, bricks_after, bricks_before]
		)


## O acerto de passo: atraso, agrupamento, retransmissão e espera.
##
## O que se testa aqui é o **contrato**, não o transporte: dado um conjunto de
## bytes recebidos, a classe diz "dá para rodar o tique n" ou não diz. Se ela
## disser que dá quando falta alguém, dois aparelhos rodam o mesmo tique com
## comandos diferentes — e o sintoma aparece vinte segundos depois, longe daqui.
func _test_lockstep() -> void:
	print("acerto de passo")
	var link := BomberLockstep.new()
	link.remote_seats = PackedInt32Array([1])

	_check(link.ready_for(0), "os primeiros tiques não esperam ninguém: ninguém pediu nada ainda")
	_check(
		not link.ready_for(BomberLockstep.DELAY),
		"passado o atraso, o tique espera o comando do outro"
	)

	# O comando dado no tique 0 vale no tique DELAY, e não agora. É o atraso de
	# entrada inteiro, e ele vale para o assento local como para qualquer outro.
	link.record_local(0, 0, BomberRules.IN_RIGHT)
	_equals(link.command_of(0, 0), 0, "o comando local não vale no tique em que foi dado")
	_equals(
		link.command_of(0, BomberLockstep.DELAY), BomberRules.IN_RIGHT,
		"ele vale %d tiques depois" % BomberLockstep.DELAY
	)

	# Um quadro sai a cada FRAME comandos, e carrega a janela de retransmissão.
	_check(link.take_frame().is_empty(), "com um comando só ainda não há mensagem")
	link.record_local(0, 1, BomberRules.IN_LEFT)
	link.record_local(0, 2, BomberRules.IN_UP)
	var frame := link.take_frame()
	_check(not frame.is_empty(), "juntados %d, a mensagem sai" % BomberLockstep.FRAME)
	_equals(frame[0], BomberLockstep.Op.INPUT, "e ela é uma mensagem de comando")
	_equals(frame[1], BomberLockstep.DELAY, "que começa no tique em que o primeiro vale")
	_check(link.take_frame().is_empty(), "e não sai de novo sem comando novo")

	# O que chega destrava exatamente os tiques que chegaram, e nem um a mais.
	link.receive_inputs(1, BomberLockstep.DELAY, PackedInt32Array([BomberRules.IN_DOWN, 0]))
	_check(link.ready_for(BomberLockstep.DELAY), "o tique com o byte do outro roda")
	_check(link.ready_for(BomberLockstep.DELAY + 1), "e o seguinte também")
	_check(not link.ready_for(BomberLockstep.DELAY + 2), "o terceiro ainda espera")
	_equals(
		link.command_of(1, BomberLockstep.DELAY), BomberRules.IN_DOWN,
		"e o comando recebido é o que ele mandou"
	)
	_equals(
		link.waiting_seats(BomberLockstep.DELAY + 2), PackedInt32Array([1]),
		"a tela consegue dizer por quem está esperando"
	)

	# Retransmissão: a mesma mensagem chegando duas vezes não muda nada, e uma que
	# se sobrepõe a comandos já conhecidos não os reescreve.
	link.receive_inputs(1, BomberLockstep.DELAY, PackedInt32Array([BomberRules.IN_UP, 0, 0]))
	_equals(
		link.command_of(1, BomberLockstep.DELAY), BomberRules.IN_DOWN,
		"o repetido não sobrescreve o que já estava"
	)
	_check(link.ready_for(BomberLockstep.DELAY + 2), "e o que ele traz de novo destrava o resto")


## A cadeira que cai sai num tique combinado, e o histórico dela vem junto.
##
## É o teste do impasse: sem o repasse, quem ficou sem os últimos bytes do que
## caiu espera por eles para sempre — e quem os mandaria já não está na sala.
func _test_lockstep_drop() -> void:
	print("saída de cadeira")
	var link := BomberLockstep.new()
	link.remote_seats = PackedInt32Array([1])
	link.receive_inputs(1, BomberLockstep.DELAY, PackedInt32Array([BomberRules.IN_RIGHT]))

	var missing := link.first_missing(1)
	_equals(missing, BomberLockstep.DELAY + 1, "o tique da saída é o primeiro que falta dela")
	_check(not link.ready_for(missing), "e é exatamente onde a partida travou")

	link.drop_seat(1, missing)
	_check(link.ready_for(missing), "anunciada a saída, o tique destrava")
	_check(link.ready_for(missing + 500), "e os seguintes também, sem esperar mais nada")
	_equals(link.command_of(1, missing), 0, "a cadeira vazia não pede mais nada")
	_equals(
		link.command_of(1, BomberLockstep.DELAY), BomberRules.IN_RIGHT,
		"mas o que ela pediu antes de sair continua valendo"
	)
	_equals(link.dropped_at(1), missing, "e o tique da saída fica registrado")

	# O repasse é o que o anunciante manda junto: os comandos da cadeira que caiu,
	# em nome dela.
	var relayed := link.relayed_history(1)
	_equals(relayed[0], BomberLockstep.Op.RELAY, "o repasse se identifica como repasse")
	_equals(relayed[1], 1, "e diz de qual assento ele é")


## Dois aparelhos, cada um com o seu acerto de passo, trocando bytes — e as duas
## simulações rodando em paralelo.
##
## É o teste que fecha o assunto: não adianta a classe responder certo se, ligada
## à simulação de verdade, os dois lados chegam a estados diferentes. Aqui um lado
## recebe as mensagens com atraso e fora de ordem, que é o que uma rede móvel faz.
func _test_two_devices() -> void:
	print("dois aparelhos")
	var seed_used := 777
	var left_state := _rules.initial_state(2, seed_used)
	var right_state := _rules.initial_state(2, seed_used)

	var left := BomberLockstep.new()
	left.remote_seats = PackedInt32Array([1])
	var right := BomberLockstep.new()
	right.remote_seats = PackedInt32Array([0])

	# Mensagens em trânsito: cada uma entregue alguns tiques depois de mandada, e
	# a de número sete perdida de vez — a retransmissão tem de cobri-la.
	var mail: Array = []
	var lost := 0
	var stalls := 0

	for tick in 240:
		left.record_local(0, tick, _scripted_command(tick, 0))
		right.record_local(1, tick, _scripted_command(tick, 1))

		for pair: Array in [[left, 0], [right, 1]]:
			var frame: PackedInt32Array = pair[0].take_frame()
			if frame.is_empty():
				continue
			if lost == 7:
				# Perdida. Nada é reenviado de propósito: quem cobre o buraco é a
				# janela de retransmissão da mensagem seguinte.
				lost += 1
				continue
			lost += 1
			mail.append({"at": tick + 4, "from": int(pair[1]), "p": frame})

		var still: Array = []
		for letter: Dictionary in mail:
			if int(letter["at"]) > tick:
				still.append(letter)
				continue
			var path: PackedInt32Array = letter["p"]
			var target: BomberLockstep = right if int(letter["from"]) == 0 else left
			target.receive_inputs(int(letter["from"]), path[1], path.slice(2))
		mail = still

		# Cada lado anda o que puder. Eles param em tiques diferentes — é o ponto —,
		# mas nunca rodam o mesmo tique com comandos diferentes.
		for pair: Array in [[left, left_state], [right, right_state]]:
			var link: BomberLockstep = pair[0]
			var state: BomberState = pair[1]
			while state.tick <= tick and link.ready_for(state.tick):
				var inputs := PackedByteArray()
				inputs.resize(2)
				inputs[0] = link.command_of(0, state.tick)
				inputs[1] = link.command_of(1, state.tick)
				_rules.step(state, inputs)
		if left_state.tick != right_state.tick:
			stalls += 1

	_check(stalls > 0, "a entrega atrasada fez os dois lados pararem em tiques diferentes")

	# Alcança o atrasado: com o correio entregue, os dois têm de chegar ao mesmo
	# tique e ao mesmo estado.
	for letter: Dictionary in mail:
		var path: PackedInt32Array = letter["p"]
		var target: BomberLockstep = right if int(letter["from"]) == 0 else left
		target.receive_inputs(int(letter["from"]), path[1], path.slice(2))
	for pair: Array in [[left, left_state], [right, right_state]]:
		var link: BomberLockstep = pair[0]
		var state: BomberState = pair[1]
		while state.tick < 240 and link.ready_for(state.tick):
			var inputs := PackedByteArray()
			inputs.resize(2)
			inputs[0] = link.command_of(0, state.tick)
			inputs[1] = link.command_of(1, state.tick)
			_rules.step(state, inputs)

	_equals(left_state.tick, right_state.tick, "no fim os dois estão no mesmo tique")
	_check(left_state.tick >= 200, "e a partida andou de verdade (%d tiques)" % left_state.tick)
	_check(_same_map(left_state, right_state), "com o mesmo mapa")
	_check(_same_players(left_state, right_state), "e os bonecos no mesmo lugar")


## Um comando por tique e por assento, variado o bastante para os dois bonecos
## andarem por caminhos diferentes e soltarem bomba em tempos diferentes.
static func _scripted_command(tick: int, seat: int) -> int:
	var phase := (tick + seat * 23) % 44
	var command := BomberRules.IN_RIGHT
	if phase >= 33:
		command = BomberRules.IN_UP
	elif phase >= 22:
		command = BomberRules.IN_LEFT
	elif phase >= 11:
		command = BomberRules.IN_DOWN
	if (tick + seat * 13) % 41 == 0:
		command |= BomberRules.IN_BOMB
	return command


static func _count_bricks(state: BomberState) -> int:
	var total := 0
	for index in state.tiles.size():
		if state.tiles[index] == BomberState.Tile.BRICK:
			total += 1
	return total


## Abre um quadrado de chão em volta de uma casa, tirando as caixas sorteadas. Os
## testes de regra precisam de um mapa conhecido; o sorteio é assunto do teste de
## determinismo.
static func _clear_around(state: BomberState, col: int, row: int, radius: int) -> void:
	for r in range(row - radius, row + radius + 1):
		for c in range(col - radius, col + radius + 1):
			if c <= 0 or r <= 0 or c >= BomberState.COLS - 1 or r >= BomberState.ROWS - 1:
				continue
			if c % 2 == 0 and r % 2 == 0:
				continue
			var index := BomberState.index_of(c, r)
			state.tiles[index] = BomberState.Tile.FLOOR
			state.prizes[index] = BomberState.Prize.NONE


## Comando para um assento só; os outros ficam parados.
static func _one(seat: int, command: int) -> PackedByteArray:
	var inputs := PackedByteArray()
	inputs.resize(4)
	inputs[seat] = command
	return inputs


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
