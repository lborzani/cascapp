extends SceneTree

## Uma partida de Metrópole em rede, quatro `net_link.gd` no mesmo processo.
##
##   cd relay && npm start
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/monopoly_net_smoke.gd
##
## `ludo_net_smoke.gd` já cobre o aperto de mão de quatro assentos. O que este
## cobre é o que Metrópole trouxe de novo em cima dele, e são três coisas:
##
## - **o formato viaja.** O limite de rodadas é escolhido por quem abre e chega
##   pelo `welcome` (`Net.option`). Duas mesas com limites diferentes não seriam
##   a mesma partida, e o erro só apareceria na rodada em que uma delas acabasse;
## - **a troca atravessa a rede.** É o único lance de tamanho variável do jogo, e
##   o único que o outro lado **não** confere pertencendo a `generate_moves` —
##   quem confere é o predicado do `validate`. Se os dois lados lessem o caminho
##   `[OFFER, para, dinheiro, quantas, …]` de formas diferentes, as escrituras
##   mudariam de mão de forma diferente em cada aparelho;
## - **quem responde não é quem joga.** Com uma proposta na mesa, `actor_of` é o
##   destinatário nos quatro aparelhos. É a única fase do jogo assim, e é ela que
##   decide qual aparelho tem direito de mandar o lance seguinte.

const NetLink := preload("res://autoload/net_link.gd")
const CODE := "METRONET"
const SEATS := 4
const TIMEOUT_SECONDS := 30.0
## O que o anfitrião escolheu no menu, e que os outros três têm de receber.
const ROUND_LIMIT := 20

## As duas escrituras da troca: uma de cada lado.
const MINE := 1
const YOURS := 6

var _links: Array[Node] = []
var _url := ""
var _failures := 0
var _elapsed := 0.0
var _phase := 0

var _rules := MonopolyRules.new()
## Assento → estado local, para provar que os quatro derivam a mesma partida.
var _states := {}
var _ready_seats := {}
## O limite que cada assento enxergou quando a mesa ficou pronta.
var _limits := {}
## `[quem viu, assento que saiu]`, para provar que a mesa continua sem ele.
var _departures: Array = []
## Assento carimbado pelo servidor em cada lance recebido, por quem recebeu.
var _senders: Array = []
## O aparelho que entra depois, na partida já em curso.
var _rejoin: Node = null
var _rejoined := false
## Quem via a cadeira 2 como máquina **no instante da saída**. Fotografado ali
## porque o teste seguinte devolve a cadeira a um humano.
var _bots_after_leave: Array = []


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste de Metrópole em rede.")
		print("  cd relay && npm start")
		print("  CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/monopoly_net_smoke.gd")
		quit(0)
	_rules.seats = SEATS


## Nome que cada assento anuncia. Um deles é comprido e sujo de propósito: o que
## chega pela rede é texto escolhido por outra pessoa e desenhado na nossa tela,
## e sem limpeza ele estoura a coluna ou empurra a faixa para fora com uma quebra
## de linha.
const NAMES := [
	"Lucas", "Ana", "Beto\nfalso", "Um nome absurdamente comprido que não cabe",
]


func _spawn(index: int) -> Node:
	var branch := Node.new()
	branch.name = "Seat%d" % index
	root.add_child(branch)
	# Cada lado com a própria MultiplayerAPI: sem isso os quatro `net_link.gd`
	# disputariam a mesma.
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/Seat%d" % index))
	var link := NetLink.new()
	link.name = "Net"
	# Cada link se apresenta com o seu nome. Escrito no **campo** e não no `Prefs`:
	# aquele é estático e o processo é um só, então os quatro links leriam o
	# último nome gravado — foi exatamente assim que a primeira versão deste teste
	# saiu, com os quatro nomes trocados entre si.
	link.player_name = NAMES[index % NAMES.size()]
	var bridge := RelayBridge.new()
	bridge.name = "RelayBridge"
	bridge.url = _url
	link.add_child(bridge)
	branch.add_child(link)

	link.table_ready.connect(func(_seats: int):
		if index >= SEATS:
			_rejoined = true
			return
		_ready_seats[index] = true
		# Lido no instante em que a mesa fica pronta, que é quando a cena da
		# partida lê: um valor que chegasse depois já não seria usado.
		_limits[index] = link.option
	)
	link.move_received.connect(func(data: Dictionary): _apply(index, data))
	link.seat_left.connect(func(seat: int): _departures.append([index, seat]))
	_links.append(link)
	return link


## Todo mundo parte da mesma posição armada à mão. Ela não vem de lances porque o
## que se quer testar é a troca, e chegar a uma posição com escrituras de dois
## donos rolando dados levaria dezenas de turnos e um resultado diferente a cada
## execução.
func _arm() -> void:
	for index in SEATS:
		var state := _rules.initial_state()
		state.meta[MonopolyRules.OWNER][MINE] = 0
		state.meta[MonopolyRules.OWNER][YOURS] = 1
		state.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.MANAGE
		_states[index] = state


## O lance que chegou, conferido contra as regras locais antes de entrar. É o
## mesmo `validate` que `monopoly_match.gd` usa, e a mesma porta por onde passam
## os lances daqui.
func _apply(index: int, data: Dictionary) -> void:
	# O assento de quem mandou, carimbado pelo servidor. É a única coisa da
	# mensagem que um cliente adulterado não consegue forjar, e é o que separa
	# "este lance é legal" de "este lance é seu".
	_senders.append([index, int(data.get("seat", -1))])
	var path := PackedInt32Array(data.get("p", []))
	var state: MatchState = _states[index]
	var move := _rules.validate(state, path)
	if move == null:
		_failures += 1
		printerr("  FAIL o assento %d recusou um lance legal: %s" % [index, path])
		return
	_rules.apply_move(state, move)


## Joga por um assento: aplica aqui e manda para os outros, como a cena faz.
func _send(seat: int, path: PackedInt32Array) -> void:
	var state: MatchState = _states[seat]
	var move := _rules.validate(state, path)
	if move == null:
		_failures += 1
		printerr("  FAIL o assento %d não conseguiu montar %s" % [seat, path])
		return
	var index := state.ply
	_rules.apply_move(state, move)
	_links[seat].send_move({"p": move.path, "pr": 0}, index)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		printerr("Tempo esgotado na fase %d — o relay está rodando em %s?" % [_phase, _url])
		quit(1)
		return true

	match _phase:
		0:
			var host := _spawn(0)
			host.option = ROUND_LIMIT
			host.host_relay(&"monopoly", CODE, false, SEATS)
			_phase = 1
		1:
			if _bridge(0).state() == RelayBridge.State.WAITING:
				_spawn(1).join_relay(CODE, &"monopoly")
				_phase = 2
		2:
			if _bridge(1).seat() == 1:
				_spawn(2).join_relay(CODE, &"monopoly")
				_phase = 3
		3:
			if _bridge(2).seat() == 2:
				_spawn(3).join_relay(CODE, &"monopoly")
				_phase = 4
		4:
			if _ready_seats.size() == SEATS:
				_arm()
				# O assento 0 oferece a sua rua e mais 150 pela do assento 1.
				_send(0, MonopolyRules.offer_path(
					1, 150, PackedInt32Array([MINE]), PackedInt32Array([YOURS])
				))
				_phase = 5
		5:
			if _everyone_at(MonopolyRules.Phase.TRADE):
				# E agora quem manda o lance é o **outro** aparelho.
				_send(1, PackedInt32Array([MonopolyRules.Act.ACCEPT]))
				_phase = 6
		6:
			if _everyone_at(MonopolyRules.Phase.MANAGE):
				# O assento 2 fecha o app. Numa mesa de quatro isso **não** pode
				# acabar a partida dos outros três — a cadeira vira máquina.
				_links[2].leave()
				_phase = 7
		7:
			if _departures.size() >= SEATS - 1:
				# Alguém entra na partida **em curso**, na cadeira que virou
				# máquina. É o caso que o `welcome` nunca vê: a mesa já se
				# apresentou, então quem chega recebe `resume` — e até aqui o
				# `resume` só levava a lista de nomes. Sem jogo, sem número de
				# assentos e sem a lista de máquinas, a tela de entrar não tinha o
				# que abrir, e o jogador ficava parado nela.
				for index in [0, 1, 3]:
					_bots_after_leave.append(_links[index].bot_seats.has(2))
				_rejoin = _spawn(SEATS)
				_rejoin.join_relay(CODE, &"monopoly")
				_phase = 8
		8:
			if _rejoined:
				_report()
				return true
	return false


func _bridge(index: int) -> RelayBridge:
	return _links[index].get_node("RelayBridge") as RelayBridge


func _everyone_at(phase: int) -> bool:
	for index in SEATS:
		if MonopolyRules.phase_of(_states[index]) != phase:
			return false
	return true


func _report() -> void:
	print("Metrópole em rede (%s)" % _url)
	_equals(_ready_seats.size(), SEATS, "a mesa cheia avisa os quatro")
	for index in range(1, SEATS):
		_equals(
			_limits.get(index, -1), ROUND_LIMIT,
			"o assento %d recebeu o formato do anfitrião" % index
		)

	# O código que a faixa de contexto mostra durante a partida. Ele é a resposta
	# para quem cair: quem fechou o app volta digitando isto, e a tela de
	# pareamento — onde o código aparecia — não existe mais depois que a partida
	# começa. Todos dizem o mesmo, inclusive quem entrou digitando.
	#
	# Menos o assento 2, que saiu da sala mais adiante nesta mesma suíte: sair
	# apaga o código, e é isso que impede a próxima entrada de pedir um assento de
	# uma partida que já acabou.
	for index in [0, 1, 3]:
		_equals(_links[index].room_code(), CODE, "o assento %d sabe o código da sala" % index)

	for index in SEATS:
		var state: MatchState = _states[index]
		_equals(
			MonopolyRules.owner_of(state, MINE), 1,
			"no assento %d a escritura oferecida mudou de dono" % index
		)
		_equals(
			MonopolyRules.owner_of(state, YOURS), 0,
			"e a pedida veio para quem propôs"
		)
		_equals(
			MonopolyRules.cash_of(state, 0), MonopolyBoard.START_CASH - 150,
			"o dinheiro saiu de quem propôs"
		)
		_equals(
			MonopolyRules.cash_of(state, 1), MonopolyBoard.START_CASH + 150,
			"e entrou em quem aceitou"
		)
		_equals(state.ply, 2, "e os dois lances entraram no histórico")

	# O carimbo do remetente: o `OFFER` saiu do assento 0 e o `ACCEPT` do 1. Sem
	# ele, qualquer assento joga a vez de qualquer outro — inclusive o proponente
	# mandando o próprio "aceito".
	var stamped := true
	for entry in _senders:
		if int(entry[1]) < 0:
			stamped = false
	_check(stamped, "todo lance recebido chega com o assento de quem mandou")
	_equals(_senders.size(), (SEATS - 1) * 2, "e os dois lances chegaram aos outros três")

	# E a mesa sobreviveu à saída do assento 2.
	var saw := {}
	for entry in _departures:
		_equals(int(entry[1]), 2, "quem saiu foi o assento 2")
		saw[int(entry[0])] = true
	_equals(saw.size(), SEATS - 1, "os três que ficaram souberam da saída")
	for index in [0, 1, 3]:
		_check(_links[index].connected, "o assento %d continua na partida" % index)
	# Lido no instante da saída, e não aqui: mais adiante um humano senta nessa
	# mesma cadeira e ela **deixa** de ser máquina, que é o teste seguinte. Uma
	# asserção sobre o estado de antes tem de ser feita antes.
	_equals(_bots_after_leave.size(), SEATS - 1, "os três que ficaram viram a cadeira 2 virar máquina")
	for entry in _bots_after_leave:
		_check(bool(entry), "e nenhum deles continuou esperando por ela")
	_equals(_links[0].bot_driver(), 0, "quem joga pelas máquinas é o menor assento humano")

	# --- os nomes atravessam a mesa --------------------------------------------
	#
	# Cada um se apresenta uma vez e **todos** ouvem: quem abre manda a lista no
	# `welcome`, quem entra devolve o nome no `ready`, e o relay entrega o `ready`
	# aos outros convidados também. Sem isso, numa mesa de seis cada jogador via
	# cinco desconhecidos numerados.
	# Os três que ficaram, e não os quatro: quem sai limpa a própria lista, e
	# perguntar a ele o nome dos outros é perguntar a quem já saiu da mesa.
	for index in [0, 1, 3]:
		_equals(_links[index].name_of(0), "Lucas", "o assento %d conhece o anfitrião" % index)
		_equals(_links[index].name_of(1), "Ana", "e o assento 1")
		# Limpo antes de ser exibido: a quebra de linha sai e o comprimento é
		# cortado no mesmo limite do campo local.
		_equals(_links[index].name_of(2), "Betofalso", "com a quebra de linha removida")
		_equals(
			_links[index].name_of(3).length(), Prefs.NAME_LIMIT,
			"e o nome comprido cortado no limite do cartão"
		)

	# --- entrar numa partida em curso -------------------------------------------
	#
	# A cadeira 2 tinha virado máquina quando aquele aparelho saiu. Um humano senta
	# nela de novo, e três coisas têm de acontecer: ele descobre **qual** partida é,
	# a mesa deixa de tratar a cadeira como máquina, e quem dirige os bots para de
	# jogar por ela. Nenhuma das três acontecia — a tela dele ficava na sala de
	# espera, que é o que o relato descrevia.
	_check(_rejoined, "quem entra na partida em curso é levado para a mesa")
	_equals(String(_rejoin.game_id), "monopoly", "e descobre qual jogo é")
	_equals(_rejoin.seats, SEATS, "de quantos é a mesa")
	_equals(_rejoin.option, ROUND_LIMIT, "e em que formato ela está sendo jogada")
	_check(
		not _rejoin.bot_seats.has(_rejoin.local_seat),
		"a cadeira dele deixou de ser de máquina (bots: %s, assento %d)"
			% [_rejoin.bot_seats, _rejoin.local_seat]
	)
	# E os que já estavam na mesa souberam: quem dirige as máquinas não pode
	# continuar rolando o dado por uma cadeira que agora tem gente.
	for index in [0, 1, 3]:
		_check(
			not _links[index].bot_seats.has(_rejoin.local_seat),
			"o assento %d parou de ver a cadeira %d como máquina"
				% [index, _rejoin.local_seat]
		)

	for link in _links:
		link.leave()

	if _failures == 0:
		print("OK — Metrópole em rede funcionando.")
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
