extends SceneTree

## Espectador ponta a ponta, contra um relay de verdade.
##
## Quatro links no mesmo processo: anfitrião, convidado e dois espectadores — um
## que chega antes do primeiro lance (recebe o `welcome`) e outro que chega no
## meio (recebe a foto da partida, `watch_state`). O teste faz o papel da cena:
## guarda o histórico do anfitrião e responde ao `watcher_joined` com ele.
##
##   cd relay && npm start
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/spectate_smoke.gd

const NetLink := preload("res://autoload/net_link.gd")
const CODE := "WATCH9"
const TIMEOUT_SECONDS := 20.0

var _url := ""
var _failures := 0
var _elapsed := 0.0
var _phase := 0
var _wait := 0.0

var _host: Node
var _guest: Node
var _early: Node
var _late: Node

## Histórico do anfitrião, como a cena o teria.
var _history := []
var _joined := {}
## Por espectador: começou? qual histórico chegou? quais lances (n) chegaram?
var _started := {}
var _synced := {}
var _moves := {"early": [], "late": []}
var _guest_moves := []
var _host_moves := []
var _left := {}
var _rejected := ""
## Fotografado antes de o convidado sair de verdade: depois dele o anfitrião
## é avisado, e deve ser.
var _host_left_early := false


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste do espectador.")
		quit(0)


func _setup() -> void:
	_host = _spawn_side("HostSide")
	_guest = _spawn_side("GuestSide")
	_early = _spawn_side("EarlySide")
	_late = _spawn_side("LateSide")

	_host.opponent_joined.connect(func(_side: int): _joined["host"] = true)
	_guest.opponent_joined.connect(func(_side: int): _joined["guest"] = true)
	_guest.move_received.connect(func(data: Dictionary): _guest_moves.append(data))
	_host.move_received.connect(func(data: Dictionary): _host_moves.append(data))
	_host.watcher_joined.connect(func(): _host.send_watch_state(_history, [], 0))
	_guest.watcher_joined.connect(func(): _guest.send_watch_state(_history, [], 0))
	for entry in [["early", _early], ["late", _late]]:
		var label: String = entry[0]
		var link: Node = entry[1]
		link.watch_started.connect(func(): _started[label] = true)
		link.sync_received.connect(func(moves: Array, _clocks: Array): _synced[label] = moves)
		link.move_received.connect(func(data: Dictionary): _moves[label].append(int(data["n"])))
		link.opponent_left.connect(func(): _left[label] = true)
		link.join_failed.connect(func(reason: String): _rejected = reason)
	_host.opponent_left.connect(func(): _left["host"] = true)
	_guest.opponent_left.connect(func(): _left["guest"] = true)


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
				_early.watch_relay(CODE)
				_phase = 2
		2:
			# Espectador confirmado antes de a mesa encher: ele vai ver o `welcome`.
			if _bridge(_early).state() == RelayBridge.State.WAITING:
				_guest.join_relay(CODE, &"chess")
				_phase = 3
		3:
			if _joined.has("host") and _joined.has("guest"):
				_play(_host, [12, 28])
				_phase = 4
		4:
			if _guest_moves.size() == 1:
				_play(_guest, [52, 36])
				_phase = 5
		5:
			if _host_moves.size() == 1:
				_late.watch_relay(CODE)
				_phase = 6
		6:
			if _started.has("late") and _synced.has("late"):
				_play(_host, [6, 21])
				_phase = 7
		7:
			if _moves["late"].has(2) and _moves["early"].has(2):
				# Espectador tentando falar pelos caminhos que a cena tem.
				_late.send_move({"p": PackedInt32Array([57, 42]), "pr": 0}, 3)
				_late._send_direct({"t": "bye"})
				_late.send_sync([], [])
				_wait = 0.6
				_phase = 8
		8:
			_play(_guest, [57, 42])
			_phase = 9
		9:
			if _host_moves.size() == 2:
				_host_left_early = _left.has("host")
				_guest.leave()
				_phase = 10
		10:
			if _left.has("early") and _left.has("late"):
				_report()
				return true
	return false


func _report() -> void:
	print("espectador pelo relay (%s)" % _url)
	_check(_started.has("early"), "quem chega antes do primeiro lance recebe a mesa")
	_equals(_moves["early"], [0, 1, 2, 3], "e vê todos os lances ao vivo")
	_check(_started.has("late"), "quem chega no meio recebe a mesa")
	_equals(Array(_synced.get("late", [])).size(), 2, "com o histórico inteiro até ali")
	_equals(_late.white_seat, 0, "e sabe quem joga de brancas")
	_equals(_moves["late"], [2, 3], "e os lances seguintes chegam")
	_equals(_late.game_id, &"chess", "o jogo vem do relay")
	_equals(_host_moves.size(), 2, "o que o espectador mandou não chegou ao anfitrião")
	_equals(int(_host_moves[1]["n"]), 3, "o lance seguinte do anfitrião é o do convidado")
	_check(not _host_left_early, "o bye do espectador não encerrou nada")
	_equals(_guest_moves.size(), 2, "nem ao convidado")
	_check(_host.watcher_count >= 1, "o anfitrião sabe que é assistido (%d)" % _host.watcher_count)
	_equals(_late.name_of(1), "GuestSide", "o espectador conhece o nome do convidado")
	_check(_left.has("early") and _left.has("late"), "a saída de um jogador chega a quem assiste")

	if _failures == 0:
		print("OK — espectador funcionando.")
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
