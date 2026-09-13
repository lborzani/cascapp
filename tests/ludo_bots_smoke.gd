extends SceneTree

## A sala que não enche: dois humanos numa mesa de quatro, e os dois lugares que
## sobraram viram máquina.
##
##   cd relay && npm start
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/ludo_bots_smoke.gd
##
## O que se verifica é o acordo entre os aparelhos sobre **quem é máquina**:
##
## - a partida começa sem a mesa cheia, quando quem abriu decide;
## - os dois lados recebem a mesma lista de assentos de bot;
## - quem abriu é quem os joga, e o lance de um bot chega ao outro humano como
##   qualquer lance — porque é qualquer lance.
##
## Sem esse acordo, o segundo aparelho ficaria esperando para sempre uma vez que
## ninguém ia jogar, ou os dois rolariam o dado do mesmo bot.

const NetLink := preload("res://autoload/net_link.gd")
const CODE := "LUDOBOT"
const SEATS := 4
const TIMEOUT_SECONDS := 30.0

var _links: Array[Node] = []
var _url := ""
var _failures := 0
var _elapsed := 0.0
var _phase := 0

var _rules := LudoRules.new()
var _states := {}
var _ready_seats := {}
## Lance de bot que chegou ao segundo humano, como ele chegou.
var _bot_move := {}


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste dos bots em rede.")
		print("  cd relay && npm start")
		print("  CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/ludo_bots_smoke.gd")
		quit(0)


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
	link.add_child(bridge)
	branch.add_child(link)

	_states[index] = _rules.initial_state()
	link.table_ready.connect(func(_seats: int): _ready_seats[index] = true)
	link.move_received.connect(func(data: Dictionary):
		if index == 1:
			_bot_move = data
	)
	_links.append(link)
	return link


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
				# Ninguém mais vem. Quem abriu fecha a mesa com máquinas.
				_links[0].start_with_bots(PackedInt32Array([2, 3]))
				_phase = 3
		3:
			if _ready_seats.size() == 2:
				# O assento 0 joga pelo bot do assento 2, como a tela faria.
				var state: MatchState = _states[0]
				state.meta[LudoRules.TURN] = 2
				var move := _rules.best_move(state, _rules.moves_for(state, 6))
				_rules.apply_move(state, move)
				_links[0].send_move({"p": move.path, "pr": 0}, 0)
				_phase = 4
		4:
			if not _bot_move.is_empty():
				_report()
				return true
	return false


func _bridge(index: int) -> RelayBridge:
	return _links[index].get_node("RelayBridge") as RelayBridge


func _report() -> void:
	print("Ludo com bots em rede (%s)" % _url)
	_equals(_ready_seats.size(), 2, "a partida começa com dois humanos numa mesa de quatro")
	for index in 2:
		_equals(
			Array(_links[index].bot_seats), [2, 3],
			"o assento %d sabe quais cores são máquina" % index
		)
		_equals(_links[index].seats, SEATS, "e que a mesa continua sendo de quatro")
	_equals(_links[0].is_host, true, "quem abriu é quem joga os bots")

	var path := PackedInt32Array(_bot_move.get("p", []))
	_equals(path.size(), 2, "o lance do bot chega como qualquer lance")
	if path.size() == 2:
		_equals(path[0], 6, "com o dado dentro")
		# O humano do outro lado valida contra as próprias regras, sem saber que
		# quem jogou foi uma máquina — que é exatamente o ponto.
		var mirror: MatchState = _states[1]
		mirror.meta[LudoRules.TURN] = 2
		var legal := false
		for candidate in _rules.moves_for(mirror, path[0]):
			if LudoRules.token_of(candidate) == path[1]:
				legal = true
		_check(legal, "e passa pelas regras do outro aparelho")

	for link in _links:
		link.leave()

	if _failures == 0:
		print("OK — mesa preenchida com bots funcionando.")
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
