class_name BleLink
extends Node

## Envoltório do singleton `GodotBle` (`android_plugin/.../ble/GodotBlePlugin.kt`):
## linhas de texto entre celulares por Bluetooth LE, sem internet.
##
## O anfitrião anuncia o código da sala e aceita conexões; o convidado procura o
## anúncio com aquele código e conecta. Cada conexão tem um `id`, e o que passa
## por ela são linhas — uma mensagem JSON por linha.
##
## Sem o plugin (desktop, iOS, headless) `is_available()` é falso e nada aqui faz
## coisa alguma. Os testes trocam o plugin por um falso com [method use_plugin].
##
## Nada liga rádio por conta própria: [method prepare] pede a permissão e, com o
## Bluetooth desligado, mostra o diálogo do sistema para o jogador ligar.

signal link_opened(id: int)
signal line_received(id: int, text: String)
signal link_closed(id: int)
## O anúncio do anfitrião está no ar.
signal hosting
## `code` é o motivo curto do plugin (`not_found`, `disabled`…); `message` é para
## gente ler.
signal failed(code: String, message: String)
signal permissions_result(granted: bool)
signal enable_result(enabled: bool)

const SINGLETON_NAME := "GodotBle"

const ERROR_TEXT := {
	"unsupported": "Este aparelho não joga por Bluetooth (precisa de Android 10 ou mais novo, com Bluetooth LE).",
	"no_permission": "Sem a permissão de dispositivos próximos não dá para jogar por Bluetooth.",
	"disabled": "O Bluetooth está desligado.",
	"location_off": "Neste Android a busca por Bluetooth só funciona com a localização ligada.",
	"not_found": "Nenhuma partida com esse código por perto. Os dois celulares estão com o Bluetooth ligado e próximos?",
	"connect_failed": "Achei a partida, mas a conexão não fechou. Tente de novo.",
	"listen_failed": "Não consegui abrir a partida pelo Bluetooth.",
	"advertise_unsupported": "Este aparelho não consegue anunciar uma partida por Bluetooth. Abra a partida no outro celular.",
	"advertise_failed": "O Bluetooth deste aparelho recusou anunciar a partida. Desligue e ligue o Bluetooth, ou abra a partida no outro celular.",
}

var _plugin: Object = null


func _ready() -> void:
	if Engine.has_singleton(SINGLETON_NAME):
		use_plugin(Engine.get_singleton(SINGLETON_NAME))


## Liga a um plugin, de verdade ou falso. Os testes passam um objeto com a mesma
## API do `GodotBle`.
func use_plugin(plugin: Object) -> void:
	_plugin = plugin
	_plugin.connect("link_opened", func(id: int): link_opened.emit(id))
	_plugin.connect("line", func(id: int, text: String): line_received.emit(id, text))
	_plugin.connect("link_closed", func(id: int): link_closed.emit(id))
	_plugin.connect("hosting", func(): hosting.emit())
	_plugin.connect("ble_error", _on_error)
	_plugin.connect("permissions_result", func(ok: bool): permissions_result.emit(ok))
	_plugin.connect("enable_result", func(ok: bool): enable_result.emit(ok))


func is_available() -> bool:
	return _plugin != null and bool(_plugin.call("isAvailable"))


## Permissão concedida e Bluetooth ligado, pedindo ao jogador o que faltar.
## Devolve vazio quando está tudo pronto, ou o texto do que faltou — para a tela
## mostrar onde ela mostra erros, e não por um sinal que outra tela também ouve.
func prepare() -> String:
	if not is_available():
		return ERROR_TEXT["unsupported"]
	if not bool(_plugin.call("hasPermissions")):
		_plugin.call("requestPermissions")
		if not await permissions_result:
			return ERROR_TEXT["no_permission"]
	if not bool(_plugin.call("isEnabled")):
		_plugin.call("requestEnable")
		if not await enable_result:
			return ERROR_TEXT["disabled"]
	return ""


## Anuncia `code` e aceita conexões até [method stop].
func host(code: String) -> void:
	if is_available():
		_plugin.call("host", code)


## Procura o anúncio de `code` por até `timeout` segundos e conecta.
func join(code: String, timeout := 15.0) -> void:
	if is_available():
		_plugin.call("join", code, int(timeout * 1000.0))


func send(id: int, text: String) -> void:
	if is_available():
		_plugin.call("send", id, text)


func close(id: int) -> void:
	if is_available():
		_plugin.call("close", id)


func stop() -> void:
	if is_available():
		_plugin.call("stop")


func _on_error(code: String) -> void:
	var key := code.get_slice(":", 0)
	var message: String = ERROR_TEXT.get(key, "Erro no Bluetooth (%s)." % code)
	failed.emit(code, message)
