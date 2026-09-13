extends Node

## Autoload `BomberNet`: o fio entre os aparelhos e o servidor autoritativo de
## Bomberman.
##
## O mesmo arquivo roda dos dois lados, como o `net.gd` do streetVolley — não é
## economia de linhas, é o que garante que as duas pontas concordam sobre o
## protocolo, porque **é** o mesmo protocolo.
##
## ## Só o Bomberman fala por aqui
##
## Os outros cinco jogos do app são por turno e falam pelo relay ([NetLink],
## WebSocket). O Bomberman é o único em tempo real, e o lockstep P2P que ele usava
## pagava um atraso de entrada fixo e travava quando qualquer aparelho engasgava.
## Este autoload é a metade de rede da troca por um servidor autoritativo com
## predição no cliente.
##
## ## O QR/NFC continua igual
##
## O emparelhamento não muda: o QR/NFC carrega `XDM3|bomberman|código` ([Pairing]),
## e sempre carregou só isso — o endereço do servidor é fixo ([constant
## BomberProtocol.SERVER_HOST]). O anfitrião cria a sala aqui, recebe o código, e o
## mostra pelo mesmo QR/NFC de antes; o convidado lê o código e entra na sala do
## servidor. O código, que antes apontava pra uma sala no relay, agora aponta pra
## uma sala no servidor — e é a única coisa que mudou no caminho de entrada.
##
## ## UDP e três canais
##
## - **canal 0, confiável**: entrar na sala, sentar, começar, sair;
## - **canal 1, comandos e linhas usadas**: não confiável, mas cada mensagem
##   repete as anteriores ([constant BomberProtocol.HISTORY]);
## - **canal 2, snapshots**: não confiável e sem ordem — um snapshot atrasado não
##   vale nada quando um mais novo já chegou.

signal joined(seat: int, is_host: bool)
signal denied(reason: int)
signal seats_changed(names: PackedStringArray)
signal started()
signal snapshot_arrived(raw: PackedByteArray)
signal frame_arrived(raw: PackedByteArray)
signal dropped()

var is_server := false
var code := ""
var seat := -1
var is_host := false
## Os nomes dos assentos como a sala os anunciou por último. Guardado porque a
## partida os pede **ao montar** a cena, e nesse instante o sinal já passou — quem
## chega depois de um evento precisa do valor, não do aviso.
var names := PackedStringArray()

## O código que o lobby vai pedir ao montar. Vazio = criar sala (anfitrião); com
## código = entrar (convidado). É como o menu e o painel de entrada dizem ao lobby
## o que fazer, já que `change_scene_to_file` não passa argumentos.
var pending_code := ""

var _peer: ENetMultiplayerPeer = null
var _rooms := {}
var _peer_room := {}
## Código da sala → peer do anfitrião. Só ele pode começar a partida.
var _room_host := {}
var _salt := 0
var _sim_time := 0.0
var _snap_time := 0.0


# --- servidor ----------------------------------------------------------------


## Endereço em que o servidor escuta, pela variável `BOMBER_BIND`. Existe pelo
## Fly, que entrega UDP no `fly-global-services` e não no coringa — escutando em
## `0.0.0.0` o socket abre, o servidor sobe, e nenhum pacote chega. Mesma pegadinha
## do streetVolley.
const BIND_ENV := "BOMBER_BIND"


func start_server(port := BomberProtocol.PORT) -> Error:
	_peer = ENetMultiplayerPeer.new()

	var wanted := OS.get_environment(BIND_ENV)
	if wanted != "":
		var address := wanted if wanted.is_valid_ip_address() else IP.resolve_hostname(wanted)
		if address == "":
			printerr("não consegui resolver %s=%s" % [BIND_ENV, wanted])
			return ERR_CANT_RESOLVE
		_peer.set_bind_ip(address)
		print("escutando em %s (%s)" % [address, wanted])

	var problem := _peer.create_server(port, 64, 3)
	if problem != OK:
		return problem
	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	is_server = true
	return OK


func _process(delta: float) -> void:
	if not is_server:
		return

	# Passo fixo, igual ao do cliente e pelo mesmo motivo: simular por `delta` daria
	# uma partida que depende da carga da máquina.
	_sim_time += delta
	var step := 1.0 / BomberRules.TICK_HZ
	var steps := 0
	while _sim_time >= step and steps < 8:
		for room in _rooms.values():
			room.step()
		_sim_time -= step
		steps += 1
	if _sim_time >= step * 8:
		_sim_time = 0.0

	_snap_time += delta
	var gap := 1.0 / BomberProtocol.SNAPSHOT_HZ
	if _snap_time < gap:
		return
	_snap_time = 0.0
	for room in _rooms.values():
		# Manda enquanto corre e também depois de acabar: o snapshot final leva o
		# resultado a quem precisa ver quem venceu.
		if not room.running and not room.finished:
			continue
		var raw: PackedByteArray = room.state.to_bytes()
		var recent: Dictionary = room.recent_commands()
		var frame := PackedByteArray()
		if not recent.is_empty():
			frame = BomberProtocol.write_frame(recent["tick"], room.seat_count(), recent["rows"])
		for peer in room.seats:
			if peer == 0:
				continue
			_snap.rpc_id(peer, raw)
			if not frame.is_empty():
				_frame.rpc_id(peer, frame)


func _on_peer_gone(peer: int) -> void:
	if not _peer_room.has(peer):
		return
	var room: BomberRoom = _rooms.get(_peer_room[peer])
	_peer_room.erase(peer)
	if room == null:
		return
	room.release(peer)
	if room.occupied() == 0:
		# Sala vazia some. Sem isto, um servidor de dias acumula salas mortas
		# rodando simulação pra ninguém.
		_rooms.erase(room.code)
		_room_host.erase(room.code)
		return
	# O anfitrião caiu antes de começar: passa a faca pra quem sobrou, senão a sala
	# fica sem quem possa dar o start.
	if _room_host.get(room.code) == peer:
		for other in room.seats:
			if other != 0:
				_room_host[room.code] = other
				_host_now.rpc_id(other)
				break
	_announce(room)


func _announce(room: BomberRoom) -> void:
	for peer in room.seats:
		if peer != 0:
			_seats.rpc_id(peer, room.names)


# --- cliente -----------------------------------------------------------------


## Conecta ao servidor, por endereço ou nome. Resolve nome em IPv4 explícito: o Fly
## (e boa parte de quem faz proxy de UDP) não entrega UDP por IPv6, e resolvendo em
## qualquer família o cliente às vezes pega o v6 e nenhum pacote chega — falha
## silenciosa idêntica à do streetVolley.
func connect_to(host := BomberProtocol.SERVER_HOST, port := BomberProtocol.PORT) -> Error:
	var address := host.strip_edges()
	if not address.is_valid_ip_address():
		address = IP.resolve_hostname(address, IP.TYPE_IPV4)
		if address == "":
			printerr("não consegui resolver %s em IPv4" % host)
			return ERR_CANT_RESOLVE

	_peer = ENetMultiplayerPeer.new()
	var problem := _peer.create_client(address, port, 3)
	if problem != OK:
		return problem
	multiplayer.multiplayer_peer = _peer
	multiplayer.server_disconnected.connect(func() -> void: dropped.emit())
	return OK


## Pede uma sala. Código vazio cria uma nova, e quem cria é o anfitrião.
func ask_room(wanted: String, format: int, who: String) -> void:
	_ask.rpc_id(1, wanted, format, who)


## O anfitrião começa a partida. Só ele pode, e por isso a checagem é no servidor.
func start_match() -> void:
	if not is_host:
		return
	_begin.rpc_id(1)


func send_inputs(first_tick: int, commands: PackedByteArray) -> void:
	if seat < 0:
		return
	_inputs.rpc_id(1, BomberProtocol.write_inputs(first_tick, commands))


func leave() -> void:
	seat = -1
	code = ""
	is_host = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null


# --- protocolo ---------------------------------------------------------------


@rpc("any_peer", "call_remote", "reliable", 0)
func _ask(wanted: String, format: int, who: String) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()

	# Um peer, um assento. Pedir sala duas vezes sentaria o mesmo jogador em duas
	# salas, e a primeira ficaria com um assento preso esperando comandos que nunca
	# vêm.
	if _peer_room.has(peer):
		_denied.rpc_id(peer, BomberProtocol.Deny.ALREADY_SEATED)
		return

	if wanted == "":
		if _rooms.size() >= BomberProtocol.MAX_ROOMS:
			_denied.rpc_id(peer, BomberProtocol.Deny.TOO_MANY_ROOMS)
			return
		_salt += 1
		var fresh := BomberProtocol.make_code(_salt)
		var room := BomberRoom.new(fresh, format, _fresh_seed())
		_rooms[fresh] = room
		_room_host[fresh] = peer
		_admit(peer, room, who)
		return

	var upper := wanted.to_upper()
	if not BomberProtocol.valid_code(upper):
		_denied.rpc_id(peer, BomberProtocol.Deny.BAD_CODE)
		return
	var found: BomberRoom = _rooms.get(upper)
	if found == null:
		_denied.rpc_id(peer, BomberProtocol.Deny.NO_ROOM)
		return
	if found.full():
		_denied.rpc_id(peer, BomberProtocol.Deny.ROOM_FULL)
		return
	if found.running or found.finished:
		# Entrar no meio de uma partida em grade viraria um boneco novo aparecendo
		# do nada. A sala já começou: recuse como cheia.
		_denied.rpc_id(peer, BomberProtocol.Deny.ROOM_FULL)
		return
	_admit(peer, found, who)


## Uma semente de partida nunca zero (o xorshift tem o zero como ponto fixo).
func _fresh_seed() -> int:
	var value := (Time.get_ticks_usec() + _salt * 2654435761) & 0x7FFFFFFF
	return value if value != 0 else 1


func _admit(peer: int, room: BomberRoom, who: String) -> void:
	var index := room.seat_for(peer, who)
	if index < 0:
		_denied.rpc_id(peer, BomberProtocol.Deny.ROOM_FULL)
		return
	_peer_room[peer] = room.code
	_granted.rpc_id(peer, room.code, index, _room_host.get(room.code) == peer)
	_announce(room)


@rpc("authority", "call_remote", "reliable", 0)
func _granted(room_code: String, my_seat: int, host: bool) -> void:
	code = room_code
	seat = my_seat
	is_host = host
	joined.emit(my_seat, host)


@rpc("authority", "call_remote", "reliable", 0)
func _denied(reason: int) -> void:
	denied.emit(reason)


@rpc("authority", "call_remote", "reliable", 0)
func _seats(current: PackedStringArray) -> void:
	names = current
	seats_changed.emit(current)


@rpc("any_peer", "call_remote", "reliable", 0)
func _begin() -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _peer_room.has(peer):
		return
	var room: BomberRoom = _rooms.get(_peer_room[peer])
	if room == null or _room_host.get(room.code) != peer:
		return
	if room.running or room.finished:
		return
	room.running = true
	for other in room.seats:
		if other != 0:
			_start.rpc_id(other)


@rpc("authority", "call_remote", "reliable", 0)
func _start() -> void:
	started.emit()


@rpc("authority", "call_remote", "reliable", 0)
func _host_now() -> void:
	is_host = true


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _inputs(raw: PackedByteArray) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _peer_room.has(peer):
		return
	var room: BomberRoom = _rooms.get(_peer_room[peer])
	if room == null:
		return
	var parsed := BomberProtocol.read_inputs(raw)
	if parsed.is_empty():
		return
	room.receive(peer, parsed["tick"], parsed["commands"])


@rpc("authority", "call_remote", "unreliable", 2)
func _snap(raw: PackedByteArray) -> void:
	snapshot_arrived.emit(raw)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _frame(raw: PackedByteArray) -> void:
	frame_arrived.emit(raw)
