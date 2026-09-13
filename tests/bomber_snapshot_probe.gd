extends SceneTree

## A serialização de um estado de Bomberman e as mensagens do protocolo, sem tela
## e sem rede.
##
##   godot --headless --path . --script res://tests/bomber_snapshot_probe.gd
##
## É a base da rede nova: o servidor manda o estado em bytes e o cliente o
## reconstrói pra prever em cima dele. Se um campo se perder no caminho — a
## semente, um pavio, o mapa depois de uma caixa queimar — a partida do cliente
## diverge da do servidor sem nada apontando pra causa. Por isso o teste central é
## de **ida e volta**: `from_bytes(to_bytes(s))` tem de reproduzir o estado campo
## a campo, e não só num instante limpo, mas numa partida cheia de bombas acesas,
## fogo no ar e jogador morto.

var _failures := 0
var _rules := BomberRules.new()


func _initialize() -> void:
	_test_roundtrip_fresh()
	_test_roundtrip_played()
	_test_roundtrip_synthetic()
	_test_size_budget()
	_test_short_packet()
	_test_inputs_message()
	_test_frame_message()

	if _failures == 0:
		print("OK — serialização de Bomberman consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


## O estado inicial vai e volta inteiro. Mapa, prêmios escondidos e semente
## inclusos — a semente é o que o replay do cliente vai consumir.
func _test_roundtrip_fresh() -> void:
	print("ida e volta do estado inicial")
	var state := _rules.initial_state(4, 987654)
	_compare(state, _revive(state), "estado inicial de quatro")

	var duo := _rules.initial_state(2, 111)
	_compare(duo, _revive(duo), "estado inicial de dois")


## Uma partida de verdade, jogada até haver bombas acesas, fogo no ar e um morto —
## os estados que um snapshot limpo não exercita.
func _test_roundtrip_played() -> void:
	print("ida e volta de uma partida em andamento")
	var state := _rules.initial_state(4, 424242)

	# Cada assento solta bomba e anda, pra encher o mapa de pavios e mudar terreno
	# quando as caixas queimarem.
	for tick in 200:
		var inputs := PackedByteArray()
		inputs.resize(4)
		for seat in 4:
			var command := 0
			if tick % 20 == seat:
				command |= BomberRules.IN_BOMB
			command |= [BomberRules.IN_UP, BomberRules.IN_DOWN, BomberRules.IN_LEFT, BomberRules.IN_RIGHT][(tick + seat) % 4]
			inputs[seat] = command
		_rules.step(state, inputs)

	_compare(state, _revive(state), "partida no tique %d" % state.tick)


## Um estado montado à mão com bombas acesas, fogo no ar e um jogador morto — os
## campos que o gameplay emergente pode não deixar vivos no instante da captura,
## mas que o servidor manda o tempo todo. Testa a serialização deles direto.
func _test_roundtrip_synthetic() -> void:
	print("ida e volta de estado com bombas, fogo e morto")
	var state := _rules.initial_state(4, 999)
	state.tick = 777
	state.seed_state = 0xDEADBEEF

	var bomb := BomberState.Bomb.new()
	bomb.col = 3
	bomb.row = 5
	bomb.owner = 2
	bomb.fuse = BomberRules.FUSE
	bomb.flame = 4
	bomb.pass_seats = 0b0110
	state.bombs.append(bomb)

	var other := BomberState.Bomb.new()
	other.col = 7
	other.row = 1
	other.owner = 0
	other.fuse = 3
	other.flame = BomberRules.MAX_FLAME
	state.bombs.append(other)

	state.flames[BomberState.index_of(5, 5)] = BomberRules.FLAME_TICKS
	state.flames[BomberState.index_of(6, 5)] = 1

	state.players[1].alive = false
	state.players[1].died_at = 750
	state.players[3].speed = BomberRules.MAX_SPEED
	state.players[3].bombs = BomberRules.MAX_BOMBS
	state.players[3].flame = BomberRules.MAX_FLAME

	_check(state.bombs.size() == 2, "o estado sintético tem duas bombas")
	_check(_flames_present(state), "o estado sintético tem fogo")
	_compare(state, _revive(state), "estado sintético")


## O snapshot cabe no orçamento. Um estado cheio de quatro jogadores e bombas fica
## bem abaixo de um pacote ENet — se passar disso, a rede fragmenta e o custo do
## snapshot deixa de ser o que o plano previu.
func _test_size_budget() -> void:
	print("tamanho do snapshot")
	var state := _rules.initial_state(4, 7)
	# Enche de bombas até o limite dos quatro donos.
	for seat in 4:
		state.players[seat].bombs = BomberRules.MAX_BOMBS
	for tick in 60:
		var inputs := PackedByteArray()
		inputs.resize(4)
		for seat in 4:
			inputs[seat] = BomberRules.IN_BOMB if tick % 3 == 0 else 0
		_rules.step(state, inputs)
	var size := state.to_bytes().size()
	print("  snapshot de %d bytes com %d bombas" % [size, state.bombs.size()])
	_check(size < 1000, "o snapshot cabe abaixo de 1000 bytes")


## Um pacote curto é lixo e tem de ser recusado, não decodificado pela metade.
func _test_short_packet() -> void:
	print("pacote curto")
	var state := BomberState.new()
	_check(not state.from_bytes(PackedByteArray()), "vazio é recusado")
	_check(not state.from_bytes(PackedByteArray([1, 2, 3])), "curto demais é recusado")
	var good := _rules.initial_state(4, 5).to_bytes()
	_check(not state.from_bytes(good.slice(0, good.size() - 10)), "truncado é recusado")


func _test_inputs_message() -> void:
	print("mensagem de entrada")
	var commands := PackedByteArray([BomberRules.IN_UP, BomberRules.IN_UP | BomberRules.IN_BOMB])
	var raw := BomberProtocol.write_inputs(340, commands)
	var back := BomberProtocol.read_inputs(raw)
	_check(not back.is_empty(), "decodifica")
	_equals(back.get("tick"), 340, "o tique volta")
	_equals(back.get("commands"), commands, "os comandos voltam")

	_check(BomberProtocol.read_inputs(PackedByteArray([1, 2])).is_empty(), "curto é recusado")
	var lying := PackedByteArray()
	lying.resize(5)
	lying.encode_u8(4, 99)  # conta maior que o corpo
	_check(BomberProtocol.read_inputs(lying).is_empty(), "conta impossível é recusada")


func _test_frame_message() -> void:
	print("mensagem de linhas usadas")
	var rows: Array = [
		PackedByteArray([1, 2, 4, 8]),
		PackedByteArray([16, 0, 1, 2]),
	]
	var raw := BomberProtocol.write_frame(500, 4, rows)
	var back := BomberProtocol.read_frame(raw)
	_check(not back.is_empty(), "decodifica")
	_equals(back.get("tick"), 500, "o tique volta")
	_equals(back.get("seats"), 4, "os assentos voltam")
	_equals(back.get("rows"), rows, "as linhas voltam")

	# Mesa de dois: cada linha tem dois bytes.
	var duo: Array = [PackedByteArray([1, 2]), PackedByteArray([4, 8])]
	var duo_back := BomberProtocol.read_frame(BomberProtocol.write_frame(10, 2, duo))
	_equals(duo_back.get("rows"), duo, "linhas de mesa de dois voltam")


# --- utilidades --------------------------------------------------------------


## Round-trip: os bytes de um estado, reconstruídos num estado novo.
func _revive(state: BomberState) -> BomberState:
	var fresh := BomberState.new()
	_check(fresh.from_bytes(state.to_bytes()), "%d bytes decodificam" % state.to_bytes().size())
	return fresh


func _flames_present(state: BomberState) -> bool:
	for cell in state.flames:
		if cell > 0:
			return true
	return false


## Compara dois estados campo a campo. É o coração do teste: um snapshot que perde
## um pavio ou um bit de semente passa em qualquer verificação mais frouxa.
func _compare(a: BomberState, b: BomberState, label: String) -> void:
	_equals(b.tick, a.tick, "%s: tique" % label)
	_equals(b.seats, a.seats, "%s: assentos" % label)
	_equals(b.seed_state, a.seed_state, "%s: semente" % label)
	_equals(b.tiles, a.tiles, "%s: mapa" % label)
	_equals(b.prizes, a.prizes, "%s: prêmios" % label)
	_equals(b.flames, a.flames, "%s: fogo" % label)
	_equals(b.players.size(), a.players.size(), "%s: número de jogadores" % label)
	_equals(b.bombs.size(), a.bombs.size(), "%s: número de bombas" % label)

	for seat in mini(a.players.size(), b.players.size()):
		var one := a.players[seat]
		var two := b.players[seat]
		var same := (
			one.x == two.x and one.y == two.y and one.facing == two.facing
			and one.alive == two.alive and one.died_at == two.died_at
			and one.bombs == two.bombs and one.flame == two.flame and one.speed == two.speed
		)
		_check(same, "%s: jogador %d idêntico" % [label, seat])

	for index in mini(a.bombs.size(), b.bombs.size()):
		var one := a.bombs[index]
		var two := b.bombs[index]
		var same := (
			one.col == two.col and one.row == two.row and one.owner == two.owner
			and one.fuse == two.fuse and one.flame == two.flame and one.pass_seats == two.pass_seats
		)
		_check(same, "%s: bomba %d idêntica" % [label, index])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
