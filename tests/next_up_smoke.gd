extends SceneTree

## Fila de quem joga a próxima, ponta a ponta, contra um relay de verdade.
##
## Três links no mesmo processo: anfitrião, convidado e um espectador. O
## espectador pede a vez, o convidado cede, e os dois trocam de papel sem sair da
## sala: o espectador vira o assento 1 e joga, o convidado passa a assistir. Por
## fim quem sentou cai e volta, e a chave nova o devolve ao assento 1.
##
##   cd relay && npm start
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/next_up_smoke.gd

const NetLink := preload("res://autoload/net_link.gd")
const CODE := "NEXT99"
const TIMEOUT_SECONDS := 20.0

var _url := ""
var _failures := 0
var _elapsed := 0.0
var _phase := 0
var _wait := 0.0

var _host: Node
var _guest: Node
var _viewer: Node

var _history := []
var _joined := {}
var _started := false
var _queued := {}
var _swapped := {}
var _host_moves := []
var _guest_moves := []
var _viewer_moves := []
var _rejected := ""
## Fotografado na hora da troca, antes da reconexão mexer em qualquer coisa.
var _after_swap := {}


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste da fila.")
		quit(0)


func _setup() -> void:
	_host = _spawn_side("HostSide")
	_guest = _spawn_side("GuestSide")
	_viewer = _spawn_side("ViewerSide")

	_host.opponent_joined.connect(func(_side: int): _joined["host"] = true)
	_guest.opponent_joined.connect(func(_side: int): _joined["guest"] = true)
	_host.watcher_joined.connect(func(): _host.send_watch_state(_history, [], 0))
	_viewer.watch_started.connect(func(): _started = true)
	_viewer.join_failed.connect(func(reason: String): _rejected = reason)
	_host.move_received.connect(func(data: Dictionary): _host_moves.append(data))
	_guest.move_received.connect(func(data: Dictionary): _guest_moves.append(data))
	_viewer.move_received.connect(func(data: Dictionary): _viewer_moves.append(data))
	for entry in [["host", _host], ["guest", _guest], ["viewer", _viewer]]:
		var label: String = entry[0]
		var link: Node = entry[1]
		link.queue_changed.connect(func(): _queued[label] = link.queue_names.size())
		link.seat_swapped.connect(func(seat: int): _on_swapped(label, link, seat))


func _on_swapped(label: String, link: Node, seat: int) -> void:
	_swapped[label] = seat
	_after_swap[label] = {
		"spectator": link.is_spectator,
		"seat": link.local_seat,
		"side": link.local_side,
		"white": link.white_seat,
		"name1": link.name_of(1),
		"watchers": link.watcher_count,
	}


func _spawn_side(side_name: String) -> Node:
	var branch := Node.new()
	branch.name = side_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/%s" % side_name))
	var link := NetLink.new()
	link.name = "Net"
	link.player_name = side_name
	var bridge := RelayBridge.new()
	bridge.name = "RelayBridge"
	bridge.url = _url
	link.add_child(bridge)
	branch.add_child(link)
	return link


func _bridge(link: Node) -> RelayBridge:
	return link.get_node("RelayBridge") as RelayBridge


func _play(link: Node, path: Array) -> void:
	var index := _history.size()
	_history.append({"p": path, "pr": 0})
	link.send_move({"p": PackedInt32Array(path), "pr": 0}, index)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		printerr("Tempo esgotado na fase %d (recusa: '%s')." % [_phase, _rejected])
		quit(1)
		return true
	if _wait > 0.0:
		_wait -= delta
		return false

	match _phase:
		0:
			_setup()
			_host.host_relay(&"chess", CODE)
			_phase = 1
		1:
			if _bridge(_host).state() == RelayBridge.State.WAITING:
				_guest.join_relay(CODE, &"chess")
				_phase = 2
		2:
			if _joined.has("host") and _joined.has("guest"):
				_play(_host, [12, 28])
				_viewer.watch_relay(CODE)
				_phase = 3
		3:
			if _started and _guest_moves.size() == 1:
				# Jogador não entra na fila; o pedido dele morre na ponte.
				_host.request_next(true)
				_viewer.request_next(true)
				_phase = 4
		4:
			if _queued.get("host", 0) == 1 and _queued.get("guest", 0) == 1 and _queued.get("viewer", 0) == 1:
				_guest.yield_seat()
				_phase = 5
		5:
			if _swapped.size() == 3:
				# Quem cedeu tenta jogar: não chega a ninguém.
				_guest.send_move({"p": PackedInt32Array([52, 36]), "pr": 0}, 1)
				_wait = 0.4
				_phase = 6
		6:
			_play(_viewer, [52, 36])
			_phase = 7
		7:
			if _host_moves.size() == 1 and _guest_moves.size() == 2:
				_bridge(_viewer)._drop("teste: a rede caiu")
				_phase = 8
		8:
			if _bridge(_viewer).state() == RelayBridge.State.LINKED and _bridge(_viewer).seat() == 1:
				_wait = 0.3
				_phase = 9
		9:
			_play(_host, [6, 21])
			_phase = 10
		10:
			if _viewer_moves.size() >= 1 and _guest_moves.size() == 3:
				_report()
				return true
	return false


func _report() -> void:
	print("fila de quem joga a próxima (%s)" % _url)
	_equals(_viewer.queue_position, -1, "quem sentou saiu da fila")
	_equals(_host.queue_names.size(), 0, "a fila esvaziou para todos")
	_equals(_swapped, {"host": 1, "guest": 1, "viewer": 1}, "os três viram a troca do assento 1")

	var viewer: Dictionary = _after_swap.get("viewer", {})
	_equals(viewer.get("spectator"), false, "quem pediu virou jogador")
	_equals(viewer.get("seat"), 1, "no assento de quem cedeu")
	_equals(viewer.get("side"), Board.Side.BLACK, "com a cor de quem cedeu na partida que acabou")
	_equals(viewer.get("watchers"), 1, "e já sabe quantos assistem")
	_equals(viewer.get("name1"), "ViewerSide", "e se vê no cartão do assento 1")

	var guest: Dictionary = _after_swap.get("guest", {})
	_equals(guest.get("spectator"), true, "quem cedeu virou espectador")
	_equals(guest.get("seat"), -1, "sem assento")
	_equals(guest.get("white"), 0, "e sabe quem joga de brancas")
	_equals(guest.get("name1"), "ViewerSide", "e vê quem sentou no lugar dele")
	_equals(_bridge(_guest).seat_key(), "", "a chave do assento morreu com a troca")

	var host: Dictionary = _after_swap.get("host", {})
	_equals(host.get("spectator"), false, "quem venceu continua jogador")
	_equals(host.get("name1"), "ViewerSide", "e vê o nome do novo oponente")

	_equals(_host_moves.size(), 1, "o anfitrião recebeu só o lance de quem sentou")
	_equals(int(_host_moves[0]["seat"]), 1, "carimbado com o assento 1")
	_equals(int(_host_moves[0]["n"]), 1, "e o lance de quem cedeu não chegou")
	_equals(_guest_moves.size(), 3, "quem cedeu assiste aos lances seguintes")
	_equals(_bridge(_viewer).seat(), 1, "a reconexão de quem sentou volta ao assento 1")
	_check(not _bridge(_viewer).seat_key().is_empty(), "com a chave nova")

	if _failures == 0:
		print("OK — fila funcionando.")
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
