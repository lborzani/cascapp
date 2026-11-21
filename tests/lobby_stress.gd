extends SceneTree

## Estresse do aperto de mão: a mesma dupla de links abre e entra em salas
## seguidas, como dois celulares jogando várias partidas na mesma execução do app.
##
## Cada rodada: o anfitrião abre uma sala nova, às vezes perde a rede (ver
## [method _shake_host]), o convidado entra depois de um atraso aleatório, e os
## dois têm de ouvir `opponent_joined`. Depois a partida acaba
## por um caminho sorteado (quem sai primeiro, com ou sem lance) e a próxima
## rodada começa. Uma rodada em que alguém fica sem `opponent_joined` é o
## convidado preso em "Esperando quem abriu a sala".
##
##   CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/lobby_stress.gd -- --rounds=40

const NetLink := preload("res://autoload/net_link.gd")
const FakeBle := preload("res://tests/fake_ble.gd")
var _limit := 8.0

var _url := ""
var _air := {}
var _host: Node
var _guest: Node
var _rounds := 40
var _round := 0
var _phase := 0
var _clock := 0.0
var _delay := 0.0
var _code := ""
var _joined := {}
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _zombies := []


func _initialize() -> void:
	_url = OS.get_environment("CHESS_RELAY_URL")
	if _url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando.")
		quit(0)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rounds="):
			_rounds = int(arg.get_slice("=", 1))
		# Contra o relay antigo o zumbi só cai pelo ping do servidor, em até 50 s.
		if arg.begins_with("--limit="):
			_limit = float(arg.get_slice("=", 1))
	_rng.seed = 7
	_host = _spawn("HostSide")
	_guest = _spawn("GuestSide")
	_host.player_name = "Ana"
	_guest.player_name = "Bia"
	_host.opponent_joined.connect(func(_side: int): _joined["host"] = _clock)
	_guest.opponent_joined.connect(func(_side: int): _joined["guest"] = _clock)
	_host.relay_unavailable.connect(func(reason: String): _joined["host_fail"] = reason)
	_guest.join_failed.connect(func(reason: String): _joined["guest_fail"] = reason)


func _spawn(side_name: String) -> Node:
	var branch := Node.new()
	branch.name = side_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/%s" % side_name))
	var link := NetLink.new()
	link.name = "Net"
	var bridge := RelayBridge.new()
	bridge.name = "RelayBridge"
	bridge.url = _url
	FakeBle.wire(bridge, _url, _air)
	link.add_child(bridge)
	branch.add_child(link)
	return link


func _bridge(link: Node) -> RelayBridge:
	return link.get_node("RelayBridge") as RelayBridge


func _process(delta: float) -> bool:
	_clock += delta
	match _phase:
		0:
			if _round >= _rounds:
				print("%d rodada(s), %d travada(s)." % [_rounds, _failures])
				quit(1 if _failures > 0 else 0)
				return true
			_joined = {}
			_code = "S%05d" % _rng.randi_range(0, 99999)
			_host.host_relay(&"chess", _code, false, 2, _rng.randi() % 2)
			_delay = _rng.randf_range(0.0, 0.6)
			_clock = 0.0
			_phase = 1
		1:
			# Depois do `joined`: a sala é nossa, e a chave já chegou.
			if not _bridge(_host).seat_key().is_empty() and _clock >= _delay:
				_shake_host()
				_guest.join_relay(_code, &"chess")
				_clock = 0.0
				_phase = 2
		2:
			if _joined.has("host") and _joined.has("guest"):
				if _clock > 3.0:
					print("rodada %d: os dois entraram em %.1f s" % [_round, _clock])
				_finish_round()
			elif _clock > _limit:
				_failures += 1
				printerr("rodada %d travou: %s | host conn=%s started=%s present=%s | guest conn=%s seat=%d present=%s" % [
					_round, _joined, _host.connected, _host._session_started, _bridge(_host).present_seats(),
					_guest.connected, _guest.local_seat, _bridge(_guest).present_seats(),
				])
				_host.leave()
				_guest.leave()
				_clock = 0.0
				_phase = 3
		3:
			# Um respiro entre as rodadas, como o tempo de voltar ao menu.
			if _clock > _rng.randf_range(0.0, 0.3):
				_round += 1
				_phase = 0
	return false


## A rede de quem abriu, logo antes de o convidado entrar, por um caminho sorteado:
##
## - nada;
## - **troca de rede**: o socket antigo fica aberto no servidor (o zumbi que o
##   Wi-Fi deixa ao passar para o 4G) e a ponte abre outro. Era `room_taken`, e a
##   sala morria com o convidado esperando;
## - **queda limpa**: o servidor vê o assento 0 livre, e o convidado que chega na
##   janela da volta sentava nele.
func _shake_host() -> void:
	var bridge := _bridge(_host)
	match _rng.randi() % 3:
		1:
			# Guardado e nunca mais lido: sem `poll` ele não responde ao ping, como um
			# socket cuja rede sumiu.
			_zombies.append(bridge._socket)
			bridge._socket = null
			bridge._drop("troca de rede (teste)")
		2:
			bridge._drop("queda (teste)")


## A partida acaba por um caminho sorteado, que é o estado que a próxima sala herda.
func _finish_round() -> void:
	match _rng.randi() % 3:
		0:
			_host.leave()
			_guest.leave()
		1:
			_guest.leave()
			_host.leave()
		2:
			_host.send_move({"p": [12, 28], "pr": 0}, 0, [])
			_guest.leave()
			_host.leave()
	_clock = 0.0
	_phase = 3
