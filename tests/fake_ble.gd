extends RefCounted

## O singleton `GodotBle` sem rádio, para as suítes de rede rodarem a partida sem
## internet no mesmo processo.
##
## Mesmos métodos e sinais do plugin (`android_plugin/.../ble/GodotBlePlugin.kt`).
## Os aparelhos de um teste compartilham o "ar": um dicionário de código para
## anfitrião. Tudo o que cruza o ar chega um quadro depois, como chegaria pelo
## rádio — nunca dentro da chamada que mandou.
##
## Com `CHESS_RELAY_URL=ble://`, as suítes do relay ligam cada ponte a um destes
## por [method wire] e jogam pelo Bluetooth falso.

signal link_opened(id: int)
signal line(id: int, text: String)
signal link_closed(id: int)
signal ble_error(code: String)
signal hosting
signal permissions_result(granted: bool)
signal enable_result(enabled: bool)

const URL := "ble://"

var _air: Dictionary
var _next := 1
## Meu id de link -> [o outro FakeBle, o id dele].
var _peers := {}


func _init(air: Dictionary) -> void:
	_air = air


## Liga a ponte ao Bluetooth falso quando `url` pede. Devolve o falso, para o
## teste poder derrubar um link com [method cut]; `null` fora do modo Bluetooth.
static func wire(bridge: RelayBridge, url: String, air: Dictionary) -> RefCounted:
	if url != URL:
		return null
	var fake: RefCounted = load("res://tests/fake_ble.gd").new(air)
	var link := BleLink.new()
	link.name = "BleLink"
	bridge.add_child(link)
	link.use_plugin(fake)
	bridge.ble = link
	bridge.via_bluetooth = true
	return fake


func isAvailable() -> bool:
	return true


func isEnabled() -> bool:
	return true


func hasPermissions() -> bool:
	return true


func locationNeededAndOff() -> bool:
	return false


func requestPermissions() -> void:
	call_deferred("emit_signal", "permissions_result", true)


func requestEnable() -> void:
	call_deferred("emit_signal", "enable_result", true)


func host(code: String) -> void:
	stop()
	_air[code] = self
	call_deferred("emit_signal", "hosting")


func join(code: String, _timeout_ms: int) -> void:
	stop()
	call_deferred("_join", code)


func _join(code: String) -> void:
	var host: Variant = _air.get(code)
	if host == null:
		ble_error.emit("not_found")
		return
	var mine := _open()
	var theirs: int = host._open()
	_peers[mine] = [host, theirs]
	host._peers[theirs] = [self, mine]
	host.link_opened.emit(theirs)
	link_opened.emit(mine)


func _open() -> int:
	_next += 1
	return _next - 1


func send(id: int, text: String) -> void:
	var peer: Variant = _peers.get(id)
	if peer != null:
		peer[0].call_deferred("_deliver", peer[1], text)


func _deliver(id: int, text: String) -> void:
	if _peers.has(id):
		line.emit(id, text)


## Fechar do lado de cá não avisa o lado de cá, como no plugin.
func close(id: int) -> void:
	var peer: Variant = _peers.get(id)
	if peer == null:
		return
	_peers.erase(id)
	peer[0].call_deferred("_remote_closed", peer[1])


func _remote_closed(id: int) -> void:
	if _peers.erase(id):
		link_closed.emit(id)


## Queda de rádio: os dois lados perdem o link e os dois são avisados.
func cut(id: int) -> void:
	if not _peers.has(id):
		return
	close(id)
	call_deferred("emit_signal", "link_closed", id)


func stop() -> void:
	for code in _air.keys():
		if _air[code] == self:
			_air.erase(code)
	for id in _peers.keys():
		close(id)


## O link deste aparelho, para o teste derrubar.
func first_link() -> int:
	return _peers.keys()[0] if not _peers.is_empty() else -1
