extends SceneTree

## Uma partida de Ludo em rede, quatro `net_link.gd` no mesmo processo.
##
##   cd relay && npm start
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/ludo_net_smoke.gd
##
## `table_smoke.gd` cobre o transporte de quatro assentos; este cobre o que veio
## em cima dele — o aperto de mão de N jogadores:
##
## - a partida **não** começa quando o segundo entra, e sim quando a mesa enche;
## - cada assento vira uma cor, e as quatro são diferentes;
## - o lance de um chega aos outros três com o dado dentro, e as quatro cópias
##   do tabuleiro derivam a mesma posição a partir dele.
##
## O último item é a razão de o dado morar no `Move`: sem isso, quatro aparelhos
## sorteando números diferentes teriam quatro partidas diferentes.

const NetLink := preload("res://autoload/net_link.gd")
const CODE := "LUDONET"
const SEATS := 4
const TIMEOUT_SECONDS := 30.0

var _links: Array[Node] = []
var _url := ""
var _failures := 0
var _elapsed := 0.0
var _phase := 0

## Assento → estado local da partida, para provar que os quatro derivam a mesma.
var _states := {}
var _rules := LudoRules.new()
## Assentos que já anunciaram mesa pronta, e quando o primeiro anunciou.
var _ready_seats := {}
var _ready_at := 0.0
## Quantos estavam na sala quando o terceiro entrou — a prova de que ninguém
## começou a jogar antes da hora.
var _ready_with_three := 0


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste do Ludo em rede.")
		print("  cd relay && npm start")
		print("  CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/ludo_net_smoke.gd")
		quit(0)


func _spawn(index: int) -> Node:
	var branch := Node.new()
	branch.name = "Seat%d" % index
	root.add_child(branch)
	# Cada lado com sua própria MultiplayerAPI, como no `relay_smoke`: sem isso
	# os quatro `net_link.gd` disputariam a mesma.
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/Seat%d" % index))
	var link := NetLink.new()
	link.name = "Net"
	var bridge := RelayBridge.new()
	bridge.name = "RelayBridge"
	bridge.url = _url
	link.add_child(bridge)
	branch.add_child(link)

	_states[index] = _rules.initial_state()
	link.table_ready.connect(func(_seats: int):
		_ready_seats[index] = true
		if _ready_at == 0.0:
			_ready_at = _elapsed
	)
	link.move_received.connect(func(data: Dictionary): _apply(index, data))
	_links.append(link)
	return link


## O lance que chegou, conferido contra as regras locais antes de entrar. É o
## mesmo caminho de `ludo_match.gd`: o dado é aceito, o peão é validado.
func _apply(index: int, data: Dictionary) -> void:
	var path := PackedInt32Array(data.get("p", []))
	if path.size() != 2:
		return
	var state: MatchState = _states[index]
	for move in _rules.moves_for(state, path[0]):
		if LudoRules.token_of(move) == path[1]:
			_rules.apply_move(state, move)
			return
	_failures += 1
	printerr("  FAIL o assento %d recusou um lance legal: %s" % [index, path])


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		printerr("Tempo esgotado na fase %d — o relay está rodando em %s?" % [_phase, _url])
		quit(1)
		return true

	match _phase:
		0:
			_spawn(0).host_relay(&"ludo", CODE, false, SEATS)
			_phase = 1
		1:
			if _bridge(0).state() == RelayBridge.State.WAITING:
				_spawn(1).join_relay(CODE, &"ludo")
				_phase = 2
		2:
			if _bridge(1).seat() == 1:
				_spawn(2).join_relay(CODE, &"ludo")
				_phase = 3
		3:
			if _bridge(2).seat() == 2:
				# Três na sala: ninguém pode ter começado a partida ainda.
				_ready_with_three = _ready_seats.size()
				_spawn(3).join_relay(CODE, &"ludo")
				_phase = 4
		4:
			if _ready_seats.size() == SEATS:
				# O assento 0 joga: tira 6 e tira um peão da base. O lance sai
				# com o dado dentro, e é o que os outros três vão repetir.
				var state: MatchState = _states[0]
				var move := _rules.moves_for(state, 6)[0]
				_rules.apply_move(state, move)
				_links[0].send_move({"p": move.path, "pr": 0}, 0)
				_phase = 5
		5:
			if _all_advanced():
				_report()
				return true
	return false


func _bridge(index: int) -> RelayBridge:
	return _links[index].get_node("RelayBridge") as RelayBridge


func _all_advanced() -> bool:
	for index in SEATS:
		if _states[index].ply == 0:
			return false
	return true


func _report() -> void:
	print("Ludo em rede (%s)" % _url)
	_equals(_ready_with_three, 0, "com três na sala ninguém começou a jogar")
	_equals(_ready_seats.size(), SEATS, "a mesa cheia avisa os quatro")
	_check(_ready_at > 0.0, "e avisa quando enche (%.1fs)" % _ready_at)

	var seats := []
	for index in SEATS:
		seats.append(_links[index].local_seat)
		_equals(_links[index].seats, SEATS, "o assento %d sabe o tamanho da mesa" % index)
	_equals(seats, [0, 1, 2, 3], "cada aparelho é uma cor diferente")
	_equals(_links[0].is_host, true, "quem abriu é o assento 0")

	var first: PackedInt32Array = LudoRules.progress(_states[0])
	for index in range(1, SEATS):
		_equals(
			LudoRules.progress(_states[index]), first,
			"o assento %d derivou a mesma posição do lance recebido" % index
		)
		_equals(
			LudoRules.turn_of(_states[index]), LudoRules.turn_of(_states[0]),
			"e a mesma vez"
		)
	_equals(first[LudoRules.slot(0, 0)], 1, "o peão saiu da base com o 6")
	_equals(LudoRules.turn_of(_states[0]), 0, "e o 6 devolveu a vez a quem tirou")

	for link in _links:
		link.leave()

	if _failures == 0:
		print("OK — Ludo em rede funcionando.")
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
