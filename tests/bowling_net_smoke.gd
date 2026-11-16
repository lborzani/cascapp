extends SceneTree

## Uma partida de boliche em rede, três `net_link.gd` no mesmo processo.
##
##   cd relay && npm start
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/bowling_net_smoke.gd
##
## A física fica de fora: o que se persegue aqui é o caminho do lance. O boliche
## é o único jogo do app em que o lance **é** o resultado (a máscara dos pinos
## caídos) e carrega os parâmetros do arremesso junto, sete casas ao todo. O teste
## prova que essas sete casas saem de quem arremessou, chegam carimbadas com o
## assento dele aos outros dois, passam pelo `validate` de cada um e deixam as
## três cartelas iguais — incluindo a vez, que no boliche passa por frame e não
## por lance.
##
## Antes de cada lance, quem arremessa manda a jogada em quadros (`send_frame`),
## como a partida faz enquanto a bola rola. O teste prova que os quadros chegam
## aos outros dois antes do lance, com o assento de quem jogou e as poses
## intactas: é com eles que a pista dos outros mostra a mesma jogada.

const NetLink := preload("res://autoload/net_link.gd")
const FakeBle := preload("res://tests/fake_ble.gd")
const CODE := "BOWLNT"
const SEATS := 3
const TIMEOUT_SECONDS := 30.0
## Quadros por arremesso. Poucos, porque aqui saem de uma vez: o relay aceita 40
## mensagens por segundo de cada aparelho, e a partida manda 15.
const FRAMES_PER_THROW := 8

## Os arremessos, na ordem: strike do 0; 7 e spare do 1; 9 e canaleta do 2; e o
## segundo frame do 0 começando. Parâmetros diferentes em cada um, para provar que
## eles viajam inteiros.
const THROWS := [
	[0, 0b1111111111, [0.2, -0.1, 0.5, 0.0, 1.0]],
	[1, 0b0001111111, [-0.4, 0.3, -0.2, 0.25, 0.6]],
	[1, 0b1110000000, [0.0, 0.0, 0.0, -0.5, 0.3]],
	[2, 0b0111111111, [0.9, -0.9, 1.0, 1.0, 0.0]],
	[2, 0, [-1.0, 1.0, -1.0, -1.0, 0.5]],
	[0, 0b0000000011, [0.1, 0.1, 0.1, 0.1, 0.1]],
]

var _links: Array[Node] = []
var _url := ""
var _air := {}
var _failures := 0
var _elapsed := 0.0
var _phase := 0
var _next := 0

var _rules := BowlingRules.new()
var _states := {}
var _ready_seats := {}
## [quem recebeu, assento carimbado pelo servidor, caminho].
var _received: Array = []
## Quadros que chegaram: [quem recebeu, lance, assento carimbado, poses].
var _frames_in: Array = []
## Os quadros mandados em cada lance, na ordem.
var _frames_out := {}
## Quantos quadros do lance cada um tinha quando o lance chegou: [quem, lance, quantos].
var _frames_before: Array = []


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste do boliche em rede.")
		print("  cd relay && npm start")
		print("  CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/bowling_net_smoke.gd")
		quit(0)
	_rules.seats = SEATS


func _spawn(index: int) -> Node:
	var branch := Node.new()
	branch.name = "Seat%d" % index
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/Seat%d" % index))
	var link := NetLink.new()
	link.name = "Net"
	var bridge := RelayBridge.new()
	bridge.name = "RelayBridge"
	bridge.url = _url
	FakeBle.wire(bridge, _url, _air)
	link.add_child(bridge)
	branch.add_child(link)
	link.table_ready.connect(func(_seats: int): _ready_seats[index] = true)
	link.move_received.connect(func(data: Dictionary): _apply(index, data))
	link.frame_received.connect(func(data: Dictionary):
		_frames_in.append([index, int(data["n"]), int(data["seat"]), data["x"]]))
	_links.append(link)
	return link


## O lance que chegou, pela mesma porta da cena: o remetente tem de ser quem tem
## a vez, e o caminho tem de passar no `validate`.
func _apply(index: int, data: Dictionary) -> void:
	var path := PackedInt32Array(data.get("p", []))
	var sender := int(data.get("seat", -1))
	_received.append([index, sender, path])
	var ply := int(data.get("n", -1))
	_frames_before.append([index, ply, _frames_in.filter(func(frame: Array) -> bool:
		return frame[0] == index and frame[1] == ply).size()])
	var state: MatchState = _states[index]
	if sender != BowlingRules.turn_of(state):
		_failures += 1
		printerr("  FAIL o assento %d recebeu um arremesso de %d fora da vez" % [index, sender])
		return
	var move := _rules.validate(state, path)
	if move == null:
		_failures += 1
		printerr("  FAIL o assento %d recusou um arremesso legal: %s" % [index, path])
		return
	_rules.apply_move(state, move)


## Quem tem a vez arremessa: aplica e manda, como `bowling_match.gd` faz.
func _throw(step: Array) -> void:
	var seat: int = step[0]
	var move := BowlingRules.roll(step[1], PackedFloat32Array(step[2]))
	var state: MatchState = _states[seat]
	var ply := state.ply
	var checked := _rules.validate(state, move.path)
	if checked == null:
		_failures += 1
		printerr("  FAIL o próprio assento %d recusou o arremesso %s" % [seat, move.path])
		return
	# A jogada em quadros, como a partida manda enquanto a bola rola; o último com
	# os pinos da máscara deitados.
	var racked := BowlingRules.standing(state)
	var sent: Array = []
	for frame in FRAMES_PER_THROW:
		var fallen: int = step[1] if frame == FRAMES_PER_THROW - 1 else 0
		var poses := _poses(-2.0 * frame, fallen, racked)
		sent.append(poses)
		_links[seat].send_frame(ply, frame * 4, poses)
	_frames_out[ply] = sent
	_rules.apply_move(state, checked)
	_links[seat].send_move({"p": move.path, "pr": 0}, ply)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		printerr("Tempo esgotado na fase %d — o relay está rodando em %s?" % [_phase, _url])
		quit(1)
		return true
	match _phase:
		0:
			_spawn(0).host_relay(&"bowling", CODE, false, SEATS)
			_phase = 1
		1:
			if _bridge(0).state() == RelayBridge.State.WAITING:
				_spawn(1).join_relay(CODE, &"bowling")
				_phase = 2
		2:
			if _bridge(1).seat() == 1:
				_spawn(2).join_relay(CODE, &"bowling")
				_phase = 3
		3:
			if _ready_seats.size() == SEATS:
				for index in SEATS:
					_states[index] = _rules.initial_state()
				_phase = 4
		4:
			# Um arremesso por vez, e o próximo só quando os três já têm o anterior:
			# é o ritmo da partida de verdade, em que cada um assiste à jogada antes.
			if _all_at(_next):
				if _next == THROWS.size():
					_report()
					return true
				_throw(THROWS[_next])
				_next += 1
	return false


func _bridge(index: int) -> RelayBridge:
	return _links[index].get_node("RelayBridge") as RelayBridge


func _all_at(ply: int) -> bool:
	for index in SEATS:
		if (_states[index] as MatchState).ply != ply:
			return false
	return true


func _report() -> void:
	print("Boliche em rede (%s)" % _url)
	var seats := []
	for index in SEATS:
		seats.append(_links[index].local_seat)
	_equals(seats, [0, 1, 2], "cada aparelho é um assento diferente")

	var first: MatchState = _states[0]
	for index in range(1, SEATS):
		var state: MatchState = _states[index]
		for seat in SEATS:
			_equals(
				BowlingRules.rolls_of(state, seat), BowlingRules.rolls_of(first, seat),
				"o aparelho %d tem a cartela do assento %d igual" % [index, seat]
			)
		_equals(BowlingRules.turn_of(state), BowlingRules.turn_of(first), "e a mesma vez")
		_equals(BowlingRules.standing(state), BowlingRules.standing(first), "e os mesmos pinos em pé")
	_equals(BowlingRules.rolls_of(first, 1), PackedInt32Array([7, 3]), "o assento 1 fez 7 e spare")
	_equals(BowlingRules.turn_of(first), 0, "a vez voltou ao 0 no segundo frame")
	_equals(BowlingRules.standing(first), 0b1111111100, "com o 1 e o 2 já caídos")

	# Cada arremesso chegou aos dois outros, com o assento de quem o mandou e as
	# sete casas intactas (os parâmetros em milésimos, a força incluída).
	_equals(_received.size(), THROWS.size() * (SEATS - 1), "cada arremesso chegou aos outros dois")
	var intact := true
	for entry in _received:
		var path: PackedInt32Array = entry[2]
		var step: Array = []
		for throw in THROWS:
			if BowlingRules.roll(throw[1], PackedFloat32Array(throw[2])).path == path:
				step = throw
		intact = intact and not step.is_empty() and int(entry[1]) == int(step[0]) and path.size() == BowlingRules.PATH_SIZE
	_check(intact, "com o remetente certo e as sete casas intactas")

	# A jogada em quadros chegou inteira aos outros dois, antes do lance.
	_equals(_frames_in.size(), THROWS.size() * (SEATS - 1) * FRAMES_PER_THROW, "os quadros de cada arremesso chegaram aos outros dois")
	_check(_frames_before.all(func(entry: Array) -> bool: return entry[2] == FRAMES_PER_THROW), "todos antes do lance")
	var frames_ok := true
	var order := {}
	for entry: Array in _frames_in:
		var ply: int = entry[1]
		var key := "%d:%d" % [entry[0], ply]
		var at: int = order.get(key, 0)
		order[key] = at + 1
		var sent: Array = _frames_out.get(ply, [])
		frames_ok = frames_ok and at < sent.size() and entry[3] == sent[at] and entry[2] == int(THROWS[ply][0])
	_check(frames_ok, "na ordem, com o assento de quem jogou e as poses intactas")
	var last: PackedInt32Array = _frames_out[0][-1]
	var down := 0
	for pin in BowlingRules.PINS:
		var pose: Variant = BowlingLane.pose_of(last, pin + 1)
		if pose != null and BowlingLane.is_down(pose):
			down |= 1 << pin
	_equals(down, int(THROWS[0][1]), "e o último quadro do strike tem os dez no chão")

	for link in _links:
		link.leave()
	if _failures == 0:
		print("OK — boliche em rede funcionando.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


## Um quadro como o da partida (`BowlingLane.snapshot`): a bola em `ball_z`, os
## pinos de `racked` no lugar e os de `fallen` deitados.
func _poses(ball_z: float, fallen: int, racked: int) -> PackedInt32Array:
	var poses := PackedInt32Array()
	poses.resize(BowlingLane.BODIES * BowlingLane.POSE_INTS)
	_put(poses, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, BowlingLane.BALL_R, ball_z)))
	for pin in BowlingRules.PINS:
		if racked & (1 << pin):
			var lying := Basis(Vector3.RIGHT, PI / 2.0) if fallen & (1 << pin) else Basis.IDENTITY
			_put(poses, pin + 1, Transform3D(lying, BowlingLane.pin_spot(pin)))
	return poses


func _put(poses: PackedInt32Array, index: int, pose: Transform3D) -> void:
	var at := pose.origin * BowlingLane.POSE_MM
	var turn := pose.basis.get_rotation_quaternion() * BowlingLane.POSE_QUAT
	var values := [at.x, at.y, at.z, turn.x, turn.y, turn.z, turn.w]
	for slot in BowlingLane.POSE_INTS:
		poses[index * BowlingLane.POSE_INTS + slot] = roundi(values[slot])


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
