extends SceneTree

## A partida sem internet nos pontos em que o Bluetooth difere do relay.
##
##   godot --headless --path . --script res://tests/ble_smoke.gd
##
## `relay_smoke.gd` e `ludo_net_smoke.gd` rodam inteiros pelo Bluetooth falso
## (`tests/fake_ble.gd`) com `CHESS_RELAY_URL=ble://`. Este cobre o que só
## acontece aqui, onde o anfitrião é o próprio servidor (`net/ble_room.gd`):
##
## - o rádio do convidado cai no meio da partida, e ele volta **sozinho** para o
##   mesmo assento, com a chave, e o histórico chega a quem ficou;
## - um terceiro aparelho com o mesmo código ouve que a partida está cheia;
## - quem abriu sai, e o convidado fica sabendo na hora.

const NetLink := preload("res://autoload/net_link.gd")
const FakeBle := preload("res://tests/fake_ble.gd")
const CODE := "BLUE22"
const TIMEOUT_SECONDS := 20.0

var _air := {}
var _host: Node
var _guest: Node
var _guest_radio: RefCounted
var _failures := 0
var _elapsed := 0.0
var _phase := 0
var _spawned := 0
var _joined := {}
var _received := {}
var _lost := {}
var _restored := {}
var _synced := []
var _seat_before := -1
var _key_before := ""
var _cut_at := 0.0
var _back_seconds := 0.0
var _full := ""
var _left := false
var _left_at := 0.0
var _left_seconds := 0.0


func _spawn(player: String) -> Array:
	_spawned += 1
	var branch_name := "Ble%d" % _spawned
	var branch := Node.new()
	branch.name = branch_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/%s" % branch_name))
	var link := NetLink.new()
	link.name = "Net"
	link.player_name = player
	var bridge := RelayBridge.new()
	bridge.name = "RelayBridge"
	var radio := FakeBle.wire(bridge, FakeBle.URL, _air)
	link.add_child(bridge)
	branch.add_child(link)
	return [link, radio]


static func _bridge(link: Node) -> RelayBridge:
	return link.get_node("RelayBridge") as RelayBridge


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		printerr("  FAIL tempo esgotado na fase %d" % _phase)
		quit(1)
		return true

	match _phase:
		0:
			_host = _spawn("Ana")[0]
			var guest := _spawn("Bia")
			_guest = guest[0]
			_guest_radio = guest[1]
			for pair in [["host", _host], ["guest", _guest]]:
				var side: String = pair[0]
				var link: Node = pair[1]
				link.opponent_joined.connect(func(_s: int): _joined[side] = true)
				link.link_lost.connect(func(): _lost[side] = true)
				link.link_restored.connect(func(): _restored[side] = _elapsed)
			_guest.move_received.connect(func(data: Dictionary): _received = data)
			# O que a tela de partida faz quando o link volta: manda o que tem.
			_guest.link_restored.connect(func(): _guest.send_sync([{"p": [12, 28], "pr": 0}], []))
			_host.sync_received.connect(func(moves: Array, _c: Array): _synced = moves)
			_guest.opponent_left.connect(func(): _left = true)
			_host.host_relay(&"chess", CODE, false, 2, 0)
			_phase = 1
		1:
			if _bridge(_host).state() == RelayBridge.State.WAITING:
				_guest.join_relay(CODE, &"chess")
				_phase = 2
		2:
			if _joined.has("host") and _joined.has("guest"):
				_host.send_move({"p": PackedInt32Array([12, 28]), "pr": 0}, 0, [])
				_phase = 3
		3:
			if not _received.is_empty():
				_seat_before = _bridge(_guest).seat()
				_key_before = _bridge(_guest).seat_key()
				# O rádio cai: nem `bye`, nem `leave`. Os dois lados só veem o link sumir.
				_guest_radio.cut(_guest_radio.first_link())
				_cut_at = _elapsed
				_phase = 4
		4:
			if _restored.has("host") and _restored.has("guest") and not _synced.is_empty():
				_back_seconds = _elapsed - _cut_at
				var intruder: Node = _spawn("Caio")[0]
				intruder.join_failed.connect(func(reason: String): _full = reason)
				intruder.join_relay(CODE, &"chess")
				_phase = 5
		5:
			if not _full.is_empty():
				_host.leave()
				_left_at = _elapsed
				_phase = 6
		6:
			if _left:
				_left_seconds = _elapsed - _left_at
				_report()
				return true
	return false


func _report() -> void:
	print("partida sem internet (Bluetooth falso)")
	_equals(PackedInt32Array(_received.get("p", [])), PackedInt32Array([12, 28]), "o lance atravessa o mini relay")
	_check(_lost.has("host") and _lost.has("guest"), "a queda do rádio congela os dois lados")
	_check(
		_back_seconds < 5.0,
		"o convidado volta sozinho, sem ninguém tocar em nada (%.1fs)" % _back_seconds
	)
	_equals(_bridge(_guest).seat(), _seat_before, "no mesmo assento")
	_equals(_bridge(_guest).seat_key(), _key_before, "com a mesma chave")
	_equals(_synced.size(), 1, "e o histórico chega a quem ficou")
	_equals(_full, "Essa partida já está cheia.", "um terceiro aparelho ouve que a mesa está cheia")
	_check(_left, "quem abriu sai e o convidado fica sabendo")
	_check(_left_seconds < 5.0, "na hora (%.1fs)" % _left_seconds)

	if _failures == 0:
		print("OK — partida por Bluetooth funcionando.")
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
