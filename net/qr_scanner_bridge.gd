class_name QrScannerBridge
extends Node

## Camera-based QR *reading* needs a decoder Godot does not ship, so it lives in
## an optional Android plugin singleton (`GodotQrScanner`) that opens the system
## camera and returns the decoded string.
##
## Generating a QR code is fully implemented in GDScript (`QrEncoder`); only
## scanning is native. Without the plugin the guest types the 6 character code
## shown under the host's QR, which works on every platform.

signal scanned(payload: String)
signal cancelled
signal failed(message: String)

const SINGLETON_NAME := "GodotQrScanner"
const CAMERA_PERMISSION := "android.permission.CAMERA"

var _plugin: Object = null


func _ready() -> void:
	if not Engine.has_singleton(SINGLETON_NAME):
		return
	_plugin = Engine.get_singleton(SINGLETON_NAME)
	_plugin.connect("scan_result", _on_scan_result)
	_plugin.connect("scan_cancelled", func(): cancelled.emit())
	_plugin.connect("scan_error", _on_scan_error)


func is_available() -> bool:
	return _plugin != null


## A câmera abre dentro da própria activity do jogo, então precisa da permissão
## de CAMERA — o leitor externo do Play Services dispensava, ao custo de mandar
## o jogo para segundo plano e ser recolhido no meio da leitura.
func start() -> void:
	if not is_available():
		failed.emit("Leitor de QR nativo indisponível neste build.")
		return
	if OS.get_granted_permissions().has(CAMERA_PERMISSION):
		_plugin.call("startScan")
		return
	if not get_tree().on_request_permissions_result.is_connected(_on_permission_result):
		get_tree().on_request_permissions_result.connect(_on_permission_result)
	OS.request_permission(CAMERA_PERMISSION)


func stop() -> void:
	if is_available():
		_plugin.call("stopScan")


func _on_permission_result(permission: String, granted: bool) -> void:
	if permission != CAMERA_PERMISSION:
		return
	get_tree().on_request_permissions_result.disconnect(_on_permission_result)
	if granted:
		_plugin.call("startScan")
	else:
		failed.emit("Sem permissão de câmera não dá para ler o QR. Use o código de 6 caracteres.")


## Payload lido numa execução anterior do processo. O leitor abre uma activity
## do Play Services, o jogo vai para segundo plano e o Android pode recolher o
## processo enquanto a câmera está aberta; quando isso acontece o app volta do
## zero e o sinal de resultado não chega a ninguém. O plugin grava o resultado
## antes de emitir, e isto recupera na inicialização seguinte.
##
## Devolve string vazia quando não há nada pendente, que é o caso normal.
func take_pending() -> String:
	if not is_available():
		return ""
	return str(_plugin.call("takePendingScan"))


func _on_scan_result(payload: String) -> void:
	# O processo sobreviveu, então o sinal basta e o guardado vira lixo — se
	# ficasse, dispararia um pareamento fantasma na próxima abertura do app.
	if is_available():
		_plugin.call("clearPendingScan")
	scanned.emit(payload)


func _on_scan_error(message: String) -> void:
	failed.emit(message)
