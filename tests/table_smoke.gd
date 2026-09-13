extends SceneTree

## Uma mesa de quatro no relay de verdade, pelo `RelayBridge`.
##
##   cd relay && npm start
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/table_smoke.gd
##
## `relay_smoke.gd` cobre a partida de dois pelo `net_link.gd`, que é um
## protocolo de dois lados. Este cobre o que veio abaixo dele: a sala de N
## assentos. São quatro pontes no mesmo processo, e o que se verifica é o que
## uma sala de dois nunca exercitou —
##
## - cada um senta num assento diferente, na ordem de chegada;
## - a mesa só fica **ligada** quando o quarto chega, e não quando o segundo;
## - um lance sai para os outros três, assinado por quem jogou;
## - quem cai volta para o **mesmo** assento, mesmo havendo outro livre antes
##   dele — que é o caso em que a chave do assento é a única resposta certa.
##
## Sem `CHESS_RELAY_URL` o teste não roda: apontar para o relay de produção a
## partir de um teste automatizado abriria salas de verdade toda vez.

const CODE := "TBL404"
const SEATS := 4
const TIMEOUT_SECONDS := 30.0

var _bridges: Array[RelayBridge] = []
var _url := ""
var _failures := 0
var _elapsed := 0.0
var _phase := 0

## Assento → mensagens recebidas, como `[remetente, conteúdo]`.
var _inbox := {}
## Estado da mesa fotografado no momento em que o terceiro entrou, para provar
## que "quase cheia" ainda não é "ligada".
var _state_with_three := RelayBridge.State.OFFLINE
var _seat_after_return := -1
var _dropped_at := 0.0
var _return_seconds := 0.0


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste da mesa.")
		print("  cd relay && npm start")
		print("  CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/table_smoke.gd")
		quit(0)


func _spawn(index: int) -> RelayBridge:
	var bridge := RelayBridge.new()
	bridge.name = "Bridge%d" % index
	bridge.url = _url
	root.add_child(bridge)
	bridge.message_received.connect(
		func(message: Dictionary, from_seat: int):
			_inbox.get_or_add(index, []).append([from_seat, message])
	)
	_bridges.append(bridge)
	return bridge


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		printerr("Tempo esgotado na fase %d — o relay está rodando em %s?" % [_phase, _url])
		quit(1)
		return true

	match _phase:
		0:
			_spawn(0).host_room(CODE, &"ludo", false, 0, SEATS)
			_phase = 1
		1:
			if _bridges[0].seat() == 0:
				_spawn(1).join_room(CODE)
				_phase = 2
		2:
			if _bridges[1].seat() >= 0:
				_spawn(2).join_room(CODE)
				_phase = 3
		3:
			if _bridges[2].seat() >= 0:
				# Três numa mesa de quatro: ainda falta um, e o estado tem de
				# dizer isso. Numa sala de dois, o segundo já era o último.
				_state_with_three = _bridges[0].state()
				_spawn(3).join_room(CODE)
				_phase = 4
		4:
			if _bridges[0].state() == RelayBridge.State.LINKED:
				_bridges[2].send({"t": "move", "die": 6, "token": 1})
				_phase = 5
		5:
			if _delivered() == 3:
				# Queda de verdade do assento 1, com o 2 e o 3 ocupados: o
				# primeiro assento livre passa a ser o dele, e é isso que torna
				# o teste honesto — sem a chave, qualquer um voltaria "certo".
				_bridges[1]._drop("teste: queda simulada")
				_dropped_at = _elapsed
				_phase = 6
		6:
			if _bridges[1].state() == RelayBridge.State.LINKED:
				_seat_after_return = _bridges[1].seat()
				_return_seconds = _elapsed - _dropped_at
				_report()
				return true
	return false


## Quantos dos outros já receberam o lance do assento 2.
func _delivered() -> int:
	var total := 0
	for index in [0, 1, 3]:
		if not Array(_inbox.get(index, [])).is_empty():
			total += 1
	return total


func _report() -> void:
	print("mesa de quatro pelo relay (%s)" % _url)
	for index in SEATS:
		_equals(_bridges[index].seat(), index, "o %dº a entrar senta no assento %d" % [index + 1, index])
	_equals(_bridges[0].capacity(), SEATS, "a capacidade da mesa vem do servidor")
	_equals(
		_state_with_three, RelayBridge.State.WAITING,
		"com três, a mesa ainda espera — cheia é cheia"
	)
	_equals(_bridges[3].state(), RelayBridge.State.LINKED, "o quarto fecha a mesa")
	_equals(_bridges[0].seats_taken(), SEATS, "e todos aparecem na lista de presentes")

	for index in [0, 1, 3]:
		var messages: Array = _inbox.get(index, [])
		_equals(messages.size(), 1, "o assento %d recebeu o lance" % index)
		if messages.is_empty():
			continue
		_equals(messages[0][0], 2, "e sabe que veio do assento 2")
		_equals(int(messages[0][1].get("die", 0)), 6, "com o conteúdo intacto")
	_equals(Array(_inbox.get(2, [])).size(), 0, "quem jogou não recebe o próprio lance")

	_equals(_seat_after_return, 1, "quem caiu volta para o mesmo assento, e não para o primeiro livre")
	_check(
		_return_seconds < 15.0,
		"e volta sem esperar a carência inteira (%.1fs)" % _return_seconds
	)

	for bridge in _bridges:
		bridge.leave()

	if _failures == 0:
		print("OK — mesa de quatro pelo relay funcionando.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
