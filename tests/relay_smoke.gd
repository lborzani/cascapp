extends SceneTree

## Teste ponta a ponta do transporte pela internet, contra um relay de verdade.
##
## Sobe dois `net_link.gd` no mesmo processo, cada um com seu próprio
## `RelayBridge`, e faz os dois se acharem pelo código da sala — exatamente o
## caminho que dois celulares em redes diferentes percorrem. O que está sendo
## verificado é o aperto de mão, o transporte de lances com índice, e o resync
## que a reconexão dispara.
##
##   cd relay && npm start
##   set CHESS_RELAY_URL=ws://127.0.0.1:8080/ws
##   godot --headless --path . --script res://tests/relay_smoke.gd
##
## Sem `CHESS_RELAY_URL` o teste não roda: apontar para o relay de produção a
## partir de um teste automatizado abriria salas de verdade num servidor de
## verdade toda vez que a suíte rodasse.

const NetLink := preload("res://autoload/net_link.gd")
const CODE := "TST123"
const TIMEOUT_SECONDS := 20.0

var _host: Node
var _guest: Node
var _url := ""
var _failures := 0
var _elapsed := 0.0
var _phase := 0
var _joined := {}
var _received := {}
var _synced := []
var _clocks := []
var _rejected := ""
## Recusa da sala inexistente, e em quanto tempo ela chegou.
var _refusal := ""
var _refusal_seconds := 0.0
## Estado do link no auge da partida, antes de alguém sair.
var _linked := {}
## Saída do oponente: se o anfitrião foi avisado, e quanto tempo levou.
var _abandoned := false
var _left_at := 0.0
var _abandon_seconds := 0.0


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste do relay.")
		print("  cd relay && npm start")
		print("  CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/relay_smoke.gd")
		quit(0)


func _setup() -> void:
	_host = _spawn_side("HostSide")
	_guest = _spawn_side("GuestSide")

	_host.opponent_joined.connect(func(side: int): _joined["host"] = side)
	_guest.opponent_joined.connect(func(side: int): _joined["guest"] = side)
	_guest.move_received.connect(func(data: Dictionary): _received = data)
	_host.sync_received.connect(func(moves: Array, clocks: Array): _synced = moves; _clocks = clocks)
	_host.join_failed.connect(func(reason: String): _rejected = reason)
	_guest.join_failed.connect(func(reason: String): _rejected = reason)
	_host.opponent_left.connect(func(): _abandoned = true)


func _spawn_side(side_name: String) -> Node:
	var branch := Node.new()
	branch.name = side_name
	root.add_child(branch)
	# Cada lado ganha sua própria MultiplayerAPI: sem isso os dois `net_link.gd`
	# disputariam a mesma, e o caminho ENet interferiria no do relay.
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/%s" % side_name))
	var link := NetLink.new()
	link.name = "Net"
	var bridge := RelayBridge.new()
	bridge.name = "RelayBridge"
	bridge.url = _url
	link.add_child(bridge)
	branch.add_child(link)
	return link


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		printerr("Tempo esgotado na fase %d." % _phase)
		if not _rejected.is_empty():
			printerr("  recusado: %s" % _rejected)
		printerr("  o relay está rodando em %s?" % _url)
		quit(1)
		return true

	match _phase:
		0:
			_setup()
			# Sala que ninguém abriu. O servidor recusa e fecha no mesmo fôlego,
			# e o cliente tem de **desistir com o motivo** em vez de entrar em
			# reconexão — era isso que produzia "conexão instável" para sempre
			# quando o código estava errado ou o anfitrião não tinha sala.
			_guest.join_relay("ZZZ999", &"chess")
			_phase = 1
		1:
			if not _rejected.is_empty():
				_refusal = _rejected
				_refusal_seconds = _elapsed
				_rejected = ""
				_host.host_relay(&"chess", CODE)
				_phase = 2
		2:
			# O convidado só procura a sala depois que o anfitrião abriu: um
			# `join` antes disso volta como `room_not_found`, que é o
			# comportamento correto do servidor e não o que este teste mede.
			var bridge := _host.get_node("RelayBridge") as RelayBridge
			if bridge.state() == RelayBridge.State.WAITING:
				_guest.join_relay(CODE, &"chess")
				_phase = 3
		3:
			if _joined.has("host") and _joined.has("guest"):
				_host.send_move({"p": PackedInt32Array([12, 28]), "pr": 0}, 0, [178.0, 180.0])
				_phase = 4
		4:
			if not _received.is_empty():
				# O resync que toda reconexão dispara: o convidado manda o que
				# tem, o anfitrião recebe a lista inteira e os dois relógios.
				_guest.send_sync([{"p": [12, 28], "pr": 0}], [178.0, 176.5])
				_phase = 5
		5:
			if not _synced.is_empty():
				# Fotografado antes da saída: depois dela os dois lados estão
				# desconectados de propósito, e o relatório roda no fim.
				_linked = {"host": _host.connected, "guest": _guest.connected}
				# O convidado sai da partida. O anfitrião tem de saber **agora**,
				# e não depois de 90s em "conexão instável": era esse o sintoma
				# quando a saída era indistinguível de uma queda de rede.
				_guest.leave()
				_left_at = _elapsed
				_phase = 6
		6:
			if _abandoned:
				_abandon_seconds = _elapsed - _left_at
				_report()
				return true
	return false


func _report() -> void:
	print("link pelo relay (%s)" % _url)
	_check(
		_refusal.contains("Nenhuma partida"),
		"sala inexistente é recusada com o motivo (obtido: '%s')" % _refusal
	)
	# O limite é generoso: o que importa é que a recusa não fique presa no laço
	# de reconexão, que só desiste depois de 90 segundos.
	_check(
		_refusal_seconds < 10.0,
		"e a recusa chega rápido (%.1fs, não os 90s da reconexão)" % _refusal_seconds
	)
	_equals(_linked.get("host"), true, "anfitrião conectado")
	_equals(_linked.get("guest"), true, "convidado conectado")
	_equals(_host.is_host, true, "um abriu a sala")
	_equals(_guest.is_host, false, "e o outro entrou nela")
	_equals(_host.local_side, Board.Side.WHITE, "anfitrião joga de brancas")
	_equals(_guest.local_side, Board.Side.BLACK, "convidado joga de pretas")
	_equals(_joined.get("host"), Board.Side.BLACK, "anfitrião vê o oponente de pretas")
	_equals(_joined.get("guest"), Board.Side.WHITE, "convidado vê o oponente de brancas")
	_equals(PackedInt32Array(_received.get("p", [])), PackedInt32Array([12, 28]), "lance intacto")
	_equals(int(_received.get("n", -1)), 0, "índice do lance preservado")
	_equals(Array(_received.get("c", [])), [178.0, 180.0], "relógios viajam com o lance")
	_equals(_synced.size(), 1, "histórico recebido no resync")
	_equals(_clocks, [178.0, 176.5], "e os relógios junto")
	_equals(_rejected, "", "nenhuma recusa")

	_check(_abandoned, "a saída do oponente é anunciada")
	# O `bye` chega no mesmo fôlego da saída. Sem ele, só a carência de 95s
	# encerraria a partida, e até lá a tela diria "conexão instável".
	_check(
		_abandon_seconds < 5.0,
		"e chega na hora (%.1fs, não os %ds da carência)" % [
			_abandon_seconds, int(NetLink.ABSENCE_LIMIT)
		]
	)

	if _failures == 0:
		print("OK — partida pela internet funcionando.")
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
