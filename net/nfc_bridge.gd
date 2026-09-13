class_name NfcBridge
extends Node

## Thin wrapper over the optional Android plugin singleton `GodotNfc`.
##
## Godot has no built-in NFC API, so this is the seam between GDScript and a
## native plugin (see `android_plugin/`). When the plugin is missing — desktop,
## iOS, or an Android build without it — `is_available()` returns false and the
## pairing screen falls back to QR + manual code, which always works.
##
## Note: Android Beam (peer-to-peer NDEF push) was removed from Android; the
## plugin implements the modern approach instead — the host runs Host Card
## Emulation and the guest runs NFC reader mode.

signal payload_received(payload: String)
signal failed(message: String)

const SINGLETON_NAME := "GodotNfc"

var _plugin: Object = null


func _ready() -> void:
	if not Engine.has_singleton(SINGLETON_NAME):
		return
	_plugin = Engine.get_singleton(SINGLETON_NAME)
	_plugin.connect("payload_received", _on_payload_received)
	_plugin.connect("nfc_error", _on_nfc_error)


func is_available() -> bool:
	return _plugin != null and bool(_plugin.call("isAvailable"))


func is_enabled() -> bool:
	return is_available() and bool(_plugin.call("isEnabled"))


## Host side: keep emulating a tag carrying `payload` until `stop()`.
func broadcast(payload: String) -> void:
	if is_available():
		_plugin.call("startBroadcast", payload)


## Guest side: listen for a tag and emit `payload_received`.
func listen() -> void:
	if is_available():
		_plugin.call("startReader")


func stop() -> void:
	if is_available():
		_plugin.call("stop")


func _on_payload_received(payload: String) -> void:
	payload_received.emit(payload)


func _on_nfc_error(message: String) -> void:
	failed.emit(message)
