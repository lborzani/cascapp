class_name BleSocket
extends RefCounted

## A superfície de `WebSocketPeer` que a `RelayBridge` usa, por cima do Bluetooth.
##
## Trocar só o socket, e não a ponte, é o que deixa a partida sem internet
## idêntica à do relay: o aperto de mão, a chave do assento, a carência de
## reconexão, o ping e a recusa com motivo são o código da ponte de sempre.
##
## - **Anfitrião:** o socket é um laço interno até o [BleRoom], o relay em
##   miniatura que roda neste aparelho. Abre na hora e não cai sozinho.
## - **Convidado:** procura o anúncio com o código e fala por um link do
##   [BleLink]. Quando o link cai, o socket fecha como um WebSocket que caiu, e a
##   ponte reconecta como sempre.

## O mesmo código de recusa do relay: a ponte para de insistir quando o vê.
const CLOSE_POLICY := RelayBridge.CLOSE_POLICY
const CLOSE_LOST := 1006
## Abaixo do `CONNECT_TIMEOUT` da ponte (12s), para o "não achei" chegar antes de
## ela desistir por conta própria.
const JOIN_TIMEOUT := 10.0
## Recusas que tentar de novo não resolvem.
const FINAL := ["unsupported", "no_permission", "disabled", "location_off"]

var _ble: BleLink
var _code := ""
var _hosting := false
## Primeira tentativa de entrar: só nela "não achei" quer dizer "não existe".
## Depois de sentar é o anfitrião fora de alcance por um instante, e vale
## insistir como em qualquer queda.
var _first := true
var _room: BleRoom = null
var _link := -1
var _state := WebSocketPeer.STATE_CLOSED
var _inbox: Array[String] = []
var _close_code := -1
var _close_reason := ""


func _init(ble: BleLink, code: String, hosting: bool, first: bool) -> void:
	_ble = ble
	_code = code
	_hosting = hosting
	_first = first


func connect_to_url(_url: String) -> Error:
	if _ble == null:
		return ERR_UNCONFIGURED
	if _hosting:
		_room = BleRoom.new(_ble, _code, _deliver)
		_state = WebSocketPeer.STATE_OPEN
		return OK
	_ble.link_opened.connect(_on_opened)
	_ble.line_received.connect(_on_line)
	_ble.link_closed.connect(_on_closed)
	_ble.failed.connect(_on_failed)
	_ble.join(_code, JOIN_TIMEOUT)
	_state = WebSocketPeer.STATE_CONNECTING
	return OK


## Nada a empurrar: o que chega vem por sinal do [BleLink].
func poll() -> void:
	pass


func get_ready_state() -> int:
	return _state


func send_text(text: String) -> Error:
	if _state != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	if _hosting:
		_room.receive_local(text)
	else:
		_ble.send(_link, text)
	return OK


func get_available_packet_count() -> int:
	return _inbox.size()


func get_packet() -> PackedByteArray:
	return _inbox.pop_front().to_utf8_buffer() if not _inbox.is_empty() else PackedByteArray()


func get_close_code() -> int:
	return _close_code


func get_close_reason() -> String:
	return _close_reason


func close(code := 1000, reason := "") -> void:
	if _state == WebSocketPeer.STATE_CLOSED and _room == null and _link < 0:
		return
	if _room != null:
		_room.close()
		_room = null
	elif _ble != null:
		_unwire()
		if _link >= 0:
			_ble.close(_link)
		else:
			_ble.stop()  # Ainda procurando: para o scan.
	_link = -1
	_finish(code, reason)


func _deliver(text: String) -> void:
	_inbox.append(text)


func _on_opened(id: int) -> void:
	if _state == WebSocketPeer.STATE_CONNECTING and _link < 0:
		_link = id
		_state = WebSocketPeer.STATE_OPEN


func _on_line(id: int, text: String) -> void:
	if id == _link:
		_inbox.append(text)


func _on_closed(id: int) -> void:
	if id != _link:
		return
	_unwire()
	_link = -1
	_finish(CLOSE_LOST, "")


func _on_failed(code: String, _message: String) -> void:
	if _state != WebSocketPeer.STATE_CONNECTING:
		return
	_unwire()
	var reason := code.get_slice(":", 0)
	if reason in FINAL:
		_finish(CLOSE_POLICY, reason)
	elif reason == "not_found" and _first:
		# Com o texto do Bluetooth ("…por perto"), e não o do relay ("…on-line"):
		# aqui o que falta costuma ser distância ou rádio desligado, não o código.
		_finish(CLOSE_POLICY, "not_found")
	else:
		_finish(CLOSE_LOST, reason)


func _finish(code: int, reason: String) -> void:
	_state = WebSocketPeer.STATE_CLOSED
	_close_code = code
	_close_reason = reason


func _unwire() -> void:
	if _ble.link_opened.is_connected(_on_opened):
		_ble.link_opened.disconnect(_on_opened)
		_ble.line_received.disconnect(_on_line)
		_ble.link_closed.disconnect(_on_closed)
		_ble.failed.disconnect(_on_failed)
