extends SceneTree

## Cair e voltar no meio da partida, no relay de verdade.
##
##   cd relay && npm start
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/rejoin_smoke.gd
##
## Os testes de mesa provam o aperto de mão de quem **chega**. Este prova o de
## quem **volta**, que é outro: a partida já existe, e quem volta não pode nem
## começar uma nova nem ficar parado esperando um convite que ninguém manda.
##
## - **queda numa mesa de quatro vira bot na hora.** Congelar a mesa inteira por
##   noventa segundos à espera de uma pessoa é o 4G de um acabando o jogo dos
##   outros três;
## - **a chave devolve o mesmo assento**, mesmo com outro livre antes dele — o
##   aparelho guarda a chave em disco, e é ela que diz qual cadeira era a sua;
## - **quem volta recebe a mesa de quem ficou**: a mesma semente, e a cadeira sai
##   da lista de máquinas em todos os aparelhos;
## - **o anfitrião também volta.** Ele era o único que sabia receber quem volta, e
##   quando o ausente era ele mesmo, voltava sentando no assento 0 e abrindo uma
##   partida nova com outra semente enquanto os outros seguiam na antiga;
## - **numa mesa de dois o anfitrião volta pelo outro**, que é o único que ficou.

const NetLink := preload("res://autoload/net_link.gd")
const CODE := "VOLTA4"
const PAIR_CODE := "VOLTA2"
const SEATS := 4
const OPTION := 0x2ACE0001
const TIMEOUT_SECONDS := 60.0
## Quanto a mesa pode levar para perceber uma queda. O relay avisa em
## milissegundos; o teto existe para uma máquina de CI lenta, e é muito menor que
## os noventa segundos da carência antiga — que é o que se quer provar.
const DROP_NOTICE := 5.0

var _url := ""
var _failures := 0
var _elapsed := 0.0
var _phase := 0
var _phase_started := 0.0
var _spawned := 0

## Assento → link vivo daquele assento.
var _links := {}
## Link → quantas vezes ele anunciou mesa pronta ou oponente.
var _ready_count := {}
## Chaves de assento guardadas antes da queda, como o app guarda em disco.
var _keys := {}


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste de reconexão.")
		print("  cd relay && npm start")
		print("  CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/rejoin_smoke.gd")
		quit(0)
	print("Reconexão (%s)" % _url)


func _spawn(player: String) -> Node:
	_spawned += 1
	var branch_name := "Link%d" % _spawned
	var branch := Node.new()
	branch.name = branch_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/%s" % branch_name))
	var link := NetLink.new()
	link.name = "Net"
	link.player_name = player
	var bridge := RelayBridge.new()
	bridge.name = "RelayBridge"
	bridge.url = _url
	link.add_child(bridge)
	branch.add_child(link)
	_ready_count[link] = 0
	link.table_ready.connect(func(_seats: int): _ready_count[link] += 1)
	link.opponent_joined.connect(func(_side: int): _ready_count[link] += 1)
	return link


static func _bridge(link: Node) -> RelayBridge:
	return link.get_node("RelayBridge") as RelayBridge


## O processo morre: nem `bye` para a partida nem `leave` para o servidor. O
## socket fecha e o relay avisa os outros com `peer_left`, que é tudo o que um
## aparelho sem bateria consegue dizer.
func _kill(seat: int) -> void:
	var link: Node = _links[seat]
	var bridge := _bridge(link)
	_keys[seat] = bridge.seat_key()
	bridge._want_link = false
	bridge._close_socket()
	link.get_parent().queue_free()
	_links.erase(seat)


func _next(phase: int) -> void:
	_phase = phase
	_phase_started = _elapsed


func _waited() -> float:
	return _elapsed - _phase_started


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		printerr("  FAIL tempo esgotado na fase %d — o relay está rodando em %s?" % [_phase, _url])
		_failures += 1
		_finish()
		return true

	match _phase:
		0:
			var host := _spawn("Ana")
			host.option = OPTION
			host.host_relay(&"uno", CODE, false, SEATS)
			_links[0] = host
			_next(1)
		1, 2, 3:
			var previous: Node = _links[_phase - 1]
			var bridge := _bridge(previous)
			if bridge.seat() == _phase - 1 and bridge.state() != RelayBridge.State.CONNECTING:
				var guest := _spawn(["Bia", "Caio", "Duda"][_phase - 1])
				guest.join_relay(CODE, &"uno")
				_links[_phase] = guest
				_next(_phase + 1)
		4:
			if _all_ready():
				print("mesa de quatro")
				_check(true, "a mesa de quatro começou")
				_kill(2)
				_kill(3)
				_next(5)
		5:
			if _others_see_bots([0, 1], [2, 3]) or _waited() > DROP_NOTICE:
				_check(_others_see_bots([0, 1], [2, 3]), "quem caiu virou bot para quem ficou, sem esperar a carência")
				_check(_links[0].connected and _links[1].connected, "e a mesa continua ligada para quem ficou")
				print("volta com chave")
				# O 3 volta **antes** do 2. Sem a chave o servidor o sentaria no
				# primeiro assento livre, que é o 2.
				var back := _spawn("Duda")
				back.join_relay(CODE, &"uno", _keys[3])
				_links[3] = back
				_next(6)
		6:
			var back: Node = _links[3]
			if _ready_count[back] > 0 or _waited() > DROP_NOTICE:
				_equals(back.local_seat, 3, "a chave devolveu o assento 3, com o 2 livre antes dele")
				_equals(_ready_count[back], 1, "quem voltou recebeu a mesa")
				_equals(back.option, OPTION, "com a semente da partida em curso")
				_equals(back.seats, SEATS, "e o tamanho da mesa")
				_check(
					back.bot_seats.has(2) and not back.bot_seats.has(3),
					"e sabe quem ainda é bot (obtido %s)" % back.bot_seats
				)
				_equals(back.name_of(0), "Ana", "e aprende o nome de quem já estava")
				var twin := _spawn("Caio")
				twin.join_relay(CODE, &"uno", _keys[2])
				_links[2] = twin
				_next(7)
		7:
			var twin: Node = _links[2]
			if (_ready_count[twin] > 0 and _others_see_bots([0, 1, 3], [])) or _waited() > DROP_NOTICE:
				_equals(twin.local_seat, 2, "o 2 voltou para o 2")
				_check(_others_see_bots([0, 1, 3], []), "e as duas cadeiras saíram da lista de bots em todos os aparelhos")
				_equals(_links[0].name_of(3), "Duda", "o nome de quem voltou chega aos outros")
				print("o anfitrião cai e volta")
				_kill(0)
				_next(8)
		8:
			if _others_see_bots([1, 2, 3], [0]) or _waited() > DROP_NOTICE:
				_check(_others_see_bots([1, 2, 3], [0]), "o anfitrião virou bot")
				_equals(_links[1].bot_driver(), 1, "e o assento 1 passou a jogar pelas máquinas")
				var host_back := _spawn("Ana")
				host_back.join_relay(CODE, &"uno", _keys[0])
				_links[0] = host_back
				_next(9)
		9:
			var host_back: Node = _links[0]
			if _ready_count[host_back] > 0 or _waited() > DROP_NOTICE:
				_equals(host_back.local_seat, 0, "o anfitrião voltou para o assento 0")
				_equals(_ready_count[host_back], 1, "e recebeu a mesa em curso")
				_equals(host_back.option, OPTION, "com a semente dela, e não a de uma partida nova")
				_equals(host_back.is_host, false, "sem se achar dono de uma sala por abrir")
				# Um instante para um `welcome` indevido, se houver, chegar aos outros.
				_next(10)
		10:
			if _waited() > 1.0:
				for seat in [1, 2, 3]:
					_equals(_links[seat].option, OPTION, "o assento %d continua na mesma partida" % seat)
					_equals(_ready_count[_links[seat]], 1, "e não recebeu uma mesa nova")
				_check(_others_see_bots([0, 1, 2, 3], []), "ninguém mais é bot")
				for seat in _links:
					_links[seat].leave()
				_next(11)
		11:
			if _waited() > 0.5:
				print("mesa de dois")
				var pair_host := _spawn("Eva")
				pair_host.time_control = 3
				pair_host.host_relay(&"chess", PAIR_CODE, false, 2)
				_links = {0: pair_host}
				_next(12)
		12:
			var pair_host: Node = _links[0]
			if _bridge(pair_host).state() == RelayBridge.State.WAITING:
				var pair_guest := _spawn("Fabi")
				pair_guest.join_relay(PAIR_CODE, &"chess")
				_links[1] = pair_guest
				_next(13)
		13:
			if _all_ready():
				_kill(0)
				_next(14)
		14:
			if _waited() > 0.5:
				_equals(_links[1].bot_seats, PackedInt32Array(), "numa mesa de dois a queda não vira bot")
				var pair_back := _spawn("Eva")
				pair_back.join_relay(PAIR_CODE, &"chess", _keys[0])
				_links[0] = pair_back
				_next(15)
		15:
			var pair_back: Node = _links[0]
			if (_ready_count[pair_back] > 0 and _links[1].connected) or _waited() > DROP_NOTICE:
				_equals(_ready_count[pair_back], 1, "o anfitrião de uma mesa de dois é recebido pelo outro")
				_equals(pair_back.local_side, Board.Side.WHITE, "e volta com as mesmas peças")
				_equals(pair_back.time_control, 3, "e o mesmo ritmo, que só quem ficou sabia")
				_equals(_ready_count[_links[1]], 1, "sem o outro receber uma partida nova")
				_check(_links[1].connected, "e o outro sai do 'reconectando'")
				_finish()
				return true
	return false


func _all_ready() -> bool:
	for seat in _links:
		if _ready_count[_links[seat]] == 0:
			return false
	return true


## Todos os `watchers` enxergam exatamente `bots` como cadeiras de máquina.
func _others_see_bots(watchers: Array, bots: Array) -> bool:
	for seat in watchers:
		if not _links.has(seat):
			return false
		var seen: PackedInt32Array = _links[seat].bot_seats
		if seen.size() != bots.size():
			return false
		for bot in bots:
			if not seen.has(bot):
				return false
	return true


func _finish() -> void:
	for seat in _links:
		if is_instance_valid(_links[seat]):
			_links[seat].leave()
	if _failures == 0:
		print("OK — reconexão consistente.")
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
