extends Control

## Sonda do Bluetooth: prova que dois celulares se acham e trocam linhas pelo
## `GodotBle`, antes de qualquer partida passar por ele.
##
## Um celular toca em "Hospedar" e devolve cada linha que recebe. O outro toca
## em "Entrar", acha o primeiro pelo código fixo e manda [constant PINGS] pings,
## um de cada vez, medindo a ida e volta.
##
## Só aparece nos Ajustes em build de depuração.

const SETTINGS_SCENE := "res://scenes/settings.tscn"
const CODE := "SONDA7"
const PINGS := 100
## Sem eco neste prazo o ping conta como perdido e o próximo sai.
const PING_TIMEOUT := 3.0

var _log: RichTextLabel
var _link := -1
var _hosting := false
var _sent := 0
var _rtts: Array[float] = []
var _lost := 0
var _waiting := -1.0
var _join_started := 0


func _ready() -> void:
	theme = AppTheme.shared()
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(box)
	for spec in [["Hospedar", _host], ["Entrar", _join], ["Voltar", go_back]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(spec[1])
		box.add_child(button)
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	box.add_child(_log)

	var ble := Pairing.ble
	ble.link_opened.connect(_on_opened)
	ble.line_received.connect(_on_line)
	ble.link_closed.connect(func(id: int): _say("link %d fechou" % id))
	ble.hosting.connect(func(): _say("anúncio no ar, código %s" % CODE))
	ble.failed.connect(func(code: String, message: String): _say("[color=red]%s (%s)[/color]" % [message, code]))
	_say("disponível: %s" % ble.is_available())


func _exit_tree() -> void:
	Pairing.ble.stop()


func _host() -> void:
	var problem: String = await Pairing.ble.prepare()
	if not problem.is_empty():
		_say("[color=red]%s[/color]" % problem)
		return
	_reset()
	_hosting = true
	Pairing.ble.host(CODE)
	_say("hospedando…")


func _join() -> void:
	var problem: String = await Pairing.ble.prepare()
	if not problem.is_empty():
		_say("[color=red]%s[/color]" % problem)
		return
	_reset()
	_hosting = false
	_join_started = Time.get_ticks_msec()
	Pairing.ble.join(CODE, 15.0)
	_say("procurando %s…" % CODE)


## Gesto de voltar do Android e botão Voltar.
func go_back() -> void:
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func _reset() -> void:
	Pairing.ble.stop()
	_link = -1
	_sent = 0
	_rtts.clear()
	_lost = 0
	_waiting = -1.0


func _on_opened(id: int) -> void:
	_link = id
	if _hosting:
		_say("convidado conectou (link %d)" % id)
		return
	_say("conectado em %d ms (link %d)" % [Time.get_ticks_msec() - _join_started, id])
	_ping()


## Anfitrião ecoa; convidado mede.
func _on_line(id: int, text: String) -> void:
	if _hosting:
		Pairing.ble.send(id, text)
		return
	var parts := text.split(":")
	if parts.size() != 3 or parts[0] != "ping" or int(parts[1]) != _sent - 1:
		return  # Eco atrasado de um ping já dado como perdido.
	_rtts.append((Time.get_ticks_usec() - int(parts[2])) / 1000.0)
	_ping()


func _process(delta: float) -> void:
	if _waiting < 0.0:
		return
	_waiting += delta
	if _waiting > PING_TIMEOUT:
		_lost += 1
		_ping()


func _ping() -> void:
	if _sent >= PINGS:
		_waiting = -1.0
		_report()
		return
	Pairing.ble.send(_link, "ping:%d:%d" % [_sent, Time.get_ticks_usec()])
	_sent += 1
	_waiting = 0.0


func _report() -> void:
	if _rtts.is_empty():
		_say("[color=red]nenhum ping voltou[/color]")
		return
	var sorted := _rtts.duplicate()
	sorted.sort()
	_say("[b]%d/%d voltaram, %d perdidos. RTT mediano %.1f ms, máx %.1f ms[/b]" % [
		_rtts.size(), PINGS, _lost, sorted[sorted.size() / 2], sorted[-1],
	])


func _say(text: String) -> void:
	_log.append_text(text + "\n")
	print("[ble_probe] ", text)
