class_name BleRoom
extends RefCounted

## O relay em miniatura que roda no celular de quem abre a partida sem internet.
##
## Fala o pedaço do protocolo de `relay/src/server.ts` que o cliente
## (`net/relay_bridge.gd`) usa: `host`, `join` com chave, `msg` repassado com o
## `from` carimbado, `peer`, `peer_left`, `ping`/`pong` e `error`. Com isso a
## ponte, o `Net` e as telas jogam por Bluetooth sem saber disso — reconexão com
## a chave do assento, recusa de sala cheia e mesa de N assentos vêm de graça.
##
## O que só o servidor de verdade tem fica de fora: Elo (`result`), fila da
## próxima (`queue`, `yield`), espectador e lista pública.
##
## Quem abriu fala com a sala por um laço interno ([constant LOCAL]); os outros,
## pelos links do [BleLink]. A sala vive enquanto o socket do anfitrião vive
## (`net/ble_socket.gd`): aqui o anfitrião **é** o servidor, e se o app dele
## fecha, a sala acaba junto.

## O link do próprio anfitrião. Os ids do plugin começam em 1.
const LOCAL := 0
const FREE := -1

var _ble: BleLink
var _code := ""
var _game := ""
var _capacity := 0
## Link de cada assento, ou [constant FREE].
var _seats: Array[int] = []
var _keys: Array[String] = []
var _deliver_local: Callable


func _init(ble: BleLink, code: String, deliver_local: Callable) -> void:
	_ble = ble
	_code = code.to_upper()
	_deliver_local = deliver_local
	_ble.line_received.connect(_receive)
	_ble.link_closed.connect(_on_link_closed)
	_ble.failed.connect(_on_failed)
	_ble.host(_code)


func close() -> void:
	if _ble == null:
		return
	_ble.line_received.disconnect(_receive)
	_ble.link_closed.disconnect(_on_link_closed)
	_ble.failed.disconnect(_on_failed)
	_ble.stop()
	_ble = null


func receive_local(text: String) -> void:
	_receive(LOCAL, text)


func _receive(link: int, text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if not message is Dictionary:
		return
	var seat := _seats.find(link)
	if seat < 0:
		_hello(link, message)
		return
	match str(message.get("t", "")):
		"msg":
			_to_others(seat, {"t": "msg", "d": message.get("d"), "from": seat})
		"ping":
			_send(link, {"t": "pong"})
		"leave":
			if link == LOCAL:
				# Quem abriu saiu: não sobra servidor. Os outros ouvem o link cair, e
				# o `bye` do jogo já foi antes deste `leave`.
				close()
				return
			_release(seat)
			_ble.close(link)
		_:
			pass  # `result`, `queue`, `yield`: só o relay de verdade.


func _hello(link: int, message: Dictionary) -> void:
	match str(message.get("t", "")):
		"host":
			if link != LOCAL:
				_fail(link, "room_taken")
				return
			if _seats.is_empty():
				_game = str(message.get("game", ""))
				_capacity = clampi(int(message.get("seats", 2)), RelayBridge.MIN_SEATS, RelayBridge.MAX_SEATS)
				_seats.resize(_capacity)
				_seats.fill(FREE)
				_keys.resize(_capacity)
				_keys.fill("")
				_keys[0] = _new_key()
			_take(0, link)
		"join":
			if _seats.is_empty() or str(message.get("room", "")).to_upper() != _code:
				_fail(link, "room_not_found")
				return
			# Com a chave, o assento que ela abriu — mesmo que pareça ocupado, porque o
			# que está lá é o link morto da conexão anterior. Sem ela, o primeiro
			# livre, com chave nova (ver `joinRoom` em `relay/src/rooms.ts`).
			var key := str(message.get("key", ""))
			var seat := _keys.find(key) if not key.is_empty() else -1
			if seat < 0:
				seat = _seats.find(FREE)
				if seat < 0:
					_fail(link, "room_full")
					return
				_keys[seat] = _new_key()
			_take(seat, link)
		_:
			# Assistir não existe sem internet.
			_fail(link, "room_not_found")


func _take(seat: int, link: int) -> void:
	var evicted := _seats[seat]
	_seats[seat] = link
	if evicted != FREE and evicted != link and evicted != LOCAL:
		_ble.close(evicted)
	_send(link, {
		"t": "joined",
		"seat": seat,
		"game": _game,
		"seats": _capacity,
		"present": _present(),
		"key": _keys[seat],
		"watchers": 0,
	})
	_to_others(seat, {"t": "peer", "seat": seat})


func _on_link_closed(link: int) -> void:
	var seat := _seats.find(link)
	if seat >= 0:
		_release(seat)


## Rádio do anfitrião falhou (anúncio recusado, Bluetooth desligado): a sala não
## existe para ninguém, e quem precisa saber é a ponte do próprio anfitrião.
func _on_failed(code: String, _message: String) -> void:
	_send(LOCAL, {"t": "error", "reason": code})


func _release(seat: int) -> void:
	_seats[seat] = FREE
	_to_others(seat, {"t": "peer_left", "seat": seat})


func _fail(link: int, reason: String) -> void:
	_send(link, {"t": "error", "reason": reason})
	if link != LOCAL:
		_ble.close(link)


func _present() -> Array:
	var present := []
	for seat in _seats.size():
		if _seats[seat] != FREE:
			present.append(seat)
	return present


func _to_others(seat: int, payload: Dictionary) -> void:
	for other in _seats.size():
		if other != seat and _seats[other] != FREE:
			_send(_seats[other], payload)


func _send(link: int, payload: Dictionary) -> void:
	# Precisão cheia: o `d` de um `msg` é desfeito e refeito aqui, e uma semente
	# grande não pode perder dígitos no caminho.
	var text := JSON.stringify(payload, "", false, true)
	if link == LOCAL:
		_deliver_local.call(text)
	elif _ble != null:
		_ble.send(link, text)


static func _new_key() -> String:
	return "%08x" % randi()
