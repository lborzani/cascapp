extends SceneTree

## Uma partida de Uno em rede, quatro `net_link.gd` no mesmo processo.
##
##   cd relay && npm start
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/uno_net_smoke.gd
##
## `ludo_net_smoke.gd` já cobre o aperto de mão de quatro assentos. O que este
## cobre é o que o Uno trouxe de novo em cima dele:
##
## - **a semente e a regra da casa viajam.** Elas vão empacotadas em `Net.option`
##   e chegam pelo `welcome`. É a garantia mais grave do jogo: as mãos inteiras
##   saem da semente, e duas mesas com sementes diferentes divergiriam em silêncio
##   já na distribuição — antes de qualquer lance;
## - **as mãos ocultas são iguais nos quatro aparelhos.** Mão oculta é desenho, não
##   segredo do modelo: todos derivam todas as mãos da semente, e é isso que faz o
##   lance de qualquer um ser validável em qualquer aparelho;
## - **o lance de um chega aos outros três** e as quatro cópias derivam a mesma
##   posição a partir dele — o caminho de 4 casas (`[kind, card, color, target]`)
##   é lido igual em todo lado.

const NetLink := preload("res://autoload/net_link.gd")
const CODE := "UNONET"
const SEATS := 4
const TIMEOUT_SECONDS := 30.0

## Empacotamento de `Game.host_option()` para o Uno, replicado aqui porque o teste
## roda sem o autoload `Game`. Semente fixa para a partida ser reproduzível.
const UNO_SEVENS_BIT := 1 << 30
const SEED := 0x0BADC0DE

var _links: Array[Node] = []
var _url := ""
var _failures := 0
var _elapsed := 0.0
var _phase := 0

var _rules := UnoRules.new()
## Assento → estado local, para provar que os quatro derivam a mesma partida.
var _states := {}
## Assentos que já anunciaram mesa pronta.
var _ready_seats := {}
## O option que cada assento enxergou quando a mesa ficou pronta.
var _options := {}
## Assento carimbado pelo servidor em cada lance recebido, por quem recebeu.
var _senders: Array = []


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste do Uno em rede.")
		print("  cd relay && npm start")
		print("  CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/uno_net_smoke.gd")
		quit(0)
	_rules.seats = SEATS


static func _seed_of(option: int) -> int:
	return (option & 0x3FFFFFFF) | 1


static func _sevens_of(option: int) -> bool:
	return (option & UNO_SEVENS_BIT) != 0


func _host_option() -> int:
	return (SEED & 0x3FFFFFFF) | 1 | UNO_SEVENS_BIT


func _spawn(index: int) -> Node:
	var branch := Node.new()
	branch.name = "Seat%d" % index
	root.add_child(branch)
	# Cada lado com a própria MultiplayerAPI: sem isso os quatro `net_link.gd`
	# disputariam a mesma.
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/Seat%d" % index))
	var link := NetLink.new()
	link.name = "Net"
	var bridge := RelayBridge.new()
	bridge.name = "RelayBridge"
	bridge.url = _url
	link.add_child(bridge)
	branch.add_child(link)

	link.table_ready.connect(func(_seats: int):
		_ready_seats[index] = true
		# Lido no instante em que a mesa fica pronta, que é quando a cena da partida
		# lê a semente para montar o estado.
		_options[index] = link.option
	)
	link.move_received.connect(func(data: Dictionary): _apply(index, data))
	_links.append(link)
	return link


## Monta o estado inicial de um assento a partir da semente que ele recebeu. É o
## que `uno_match.gd` faz em `_adopt_rules` no ramo online.
func _build_state(index: int) -> void:
	var option: int = _options[index]
	_rules.match_seed = _seed_of(option)
	_rules.sevens = _sevens_of(option)
	_states[index] = _rules.initial_state()


## O lance que chegou, conferido contra as regras locais antes de entrar. É o mesmo
## `validate` que `uno_match.gd` usa, e a mesma porta por onde passam os lances
## locais.
func _apply(index: int, data: Dictionary) -> void:
	_senders.append([index, int(data.get("seat", -1))])
	var path := PackedInt32Array(data.get("p", []))
	var state: MatchState = _states[index]
	var move := _rules.validate(state, path)
	if move == null:
		_failures += 1
		printerr("  FAIL o assento %d recusou um lance legal: %s" % [index, path])
		return
	_rules.apply_move(state, move)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		printerr("Tempo esgotado na fase %d — o relay está rodando em %s?" % [_phase, _url])
		quit(1)
		return true

	match _phase:
		0:
			var host := _spawn(0)
			host.option = _host_option()
			host.host_relay(&"uno", CODE, false, SEATS)
			_phase = 1
		1:
			if _bridge(0).state() == RelayBridge.State.WAITING:
				_spawn(1).join_relay(CODE, &"uno")
				_phase = 2
		2:
			if _bridge(1).seat() == 1:
				_spawn(2).join_relay(CODE, &"uno")
				_phase = 3
		3:
			if _bridge(2).seat() == 2:
				_spawn(3).join_relay(CODE, &"uno")
				_phase = 4
		4:
			if _ready_seats.size() == SEATS:
				for index in SEATS:
					_build_state(index)
				# O assento 0 joga o primeiro lance legal. Com a semente fixa ele é
				# determinístico, e é o que os outros três vão repetir.
				var state: MatchState = _states[0]
				var move := _rules.generate_moves(state)[0]
				var ply := state.ply
				_rules.apply_move(state, move)
				_links[0].send_move({"p": move.path, "pr": 0}, ply)
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


## As mãos dos quatro assentos, achatadas, para comparar duas cópias do estado.
func _hands(state: MatchState) -> Array:
	var all := []
	for seat in SEATS:
		all.append(UnoRules.hand_of(state, seat))
	return all


func _report() -> void:
	print("Uno em rede (%s)" % _url)
	_equals(_ready_seats.size(), SEATS, "a mesa cheia avisa os quatro")

	var seats := []
	for index in SEATS:
		seats.append(_links[index].local_seat)
		_equals(_links[index].seats, SEATS, "o assento %d sabe o tamanho da mesa" % index)
	_equals(seats, [0, 1, 2, 3], "cada aparelho é um assento diferente")
	_equals(_links[0].is_host, true, "quem abriu é o assento 0")

	# A semente e a regra da casa chegaram aos três que entraram.
	for index in range(1, SEATS):
		_equals(
			_options.get(index, -1), _host_option(),
			"o assento %d recebeu a semente e a regra da casa do anfitrião" % index
		)
	_check(_sevens_of(_host_option()), "a regra da casa está ligada nesta partida")

	# A garantia mais grave: os quatro derivaram as **mesmas** mãos da semente,
	# antes de qualquer lance. Reconstruo o estado inicial de cada um e comparo.
	var deal := []
	for index in SEATS:
		_rules.match_seed = _seed_of(_options[index])
		_rules.sevens = _sevens_of(_options[index])
		deal.append(_hands(_rules.initial_state()))
	for index in range(1, SEATS):
		_equals(deal[index], deal[0], "o assento %d recebeu a mesma distribuição" % index)

	# E depois do lance, as quatro cópias continuam iguais.
	var first := _hands(_states[0])
	for index in range(1, SEATS):
		_equals(
			_hands(_states[index]), first,
			"o assento %d derivou as mesmas mãos do lance recebido" % index
		)
		_equals(
			UnoRules.turn_of(_states[index]), UnoRules.turn_of(_states[0]),
			"e a mesma vez"
		)
		_equals(
			UnoRules.top_card(_states[index]), UnoRules.top_card(_states[0]),
			"e a mesma carta no topo"
		)
	_equals(_states[0].ply, 1, "o lance entrou no histórico")

	# O carimbo do remetente: o lance saiu do assento 0. Sem ele, qualquer assento
	# joga a vez de qualquer outro.
	var stamped := true
	for entry in _senders:
		if int(entry[1]) != 0:
			stamped = false
	_check(stamped, "todo lance recebido chega carimbado com o assento 0")
	_equals(_senders.size(), SEATS - 1, "e o lance chegou aos outros três")

	for link in _links:
		link.leave()

	if _failures == 0:
		print("OK — Uno em rede funcionando.")
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
