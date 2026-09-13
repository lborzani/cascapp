extends Node

## Um cliente de mentira, pra provar que a rede do Bomberman fecha sem dois
## celulares.
##
##   godot --headless --path . res://server/main.tscn -- --port 27200 &
##   godot --headless --path . res://tests/bomber_net_smoke.tscn -- --port 27200 --create
##
## Cena e não `--script`: os autoloads ([BomberNet]) não existem no modo `--script`,
## e sem eles não há RPC nenhum. É a mesma razão do `net_smoke` do streetVolley.
##
## O que ele afirma: que dá pra conectar, criar sala, virar anfitrião, começar a
## partida, mandar comando, receber snapshot que **decodifica**, e que o tique do
## servidor **anda**. Um servidor que aceita conexão e não simula passa em qualquer
## teste mais fraco que este.

const SECONDS := 5.0

var _failures := 0
var _snapshots := 0
var _frames := 0
var _first_tick := -1
var _last_tick := -1
var _elapsed := 0.0
var _sent := 0
var _seat := -1
var _host := false
var _names := PackedStringArray()


func _ready() -> void:
	var port := _arg_int("--port", BomberProtocol.PORT)

	BomberNet.joined.connect(_on_joined)
	BomberNet.denied.connect(_on_denied)
	BomberNet.seats_changed.connect(func(names: PackedStringArray) -> void: _names = names)
	BomberNet.started.connect(func() -> void: pass)
	BomberNet.snapshot_arrived.connect(_on_snapshot)
	BomberNet.frame_arrived.connect(func(_raw: PackedByteArray) -> void: _frames += 1)

	var problem := BomberNet.connect_to(_arg_text("--host", "127.0.0.1"), port)
	if problem != OK:
		_fail("não consegui abrir o cliente: %s" % error_string(problem))
		return _finish()

	if not await _wait_for_connection():
		_fail("o servidor não respondeu em %s:%d" % [_arg_text("--host", "127.0.0.1"), port])
		return _finish()

	BomberNet.ask_room("", 4, "Smoke")
	if not await _wait_for_seat():
		_fail("não fui sentado em nenhuma sala")
		return _finish()

	print("assento %d na sala %s (anfitrião: %s)" % [_seat, BomberNet.code, _host])
	_expect(_host, "quem cria a sala é o anfitrião")

	# O anfitrião começa a partida; sem isso o servidor não simula.
	BomberNet.start_match()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	# Um comando por quadro com o tique que o servidor está vendo. O cliente de
	# verdade manda de dois em dois com histórico; aqui se testa o cano, não o ritmo.
	BomberNet.send_inputs(maxi(_last_tick, 0) + 1, PackedByteArray([BomberRules.IN_RIGHT]))
	_sent += 1

	if _elapsed < SECONDS:
		return
	set_process(false)
	_check()
	_finish()


func _check() -> void:
	_expect(_snapshots > 0, "chegou algum snapshot (vieram %d)" % _snapshots)
	_expect(
		_snapshots >= BomberProtocol.SNAPSHOT_HZ * SECONDS * 0.5,
		"snapshots no ritmo esperado (%d em %.0f s)" % [_snapshots, SECONDS]
	)
	# A prova de que o servidor **simula**, e não só repete um estado parado.
	var advanced := _last_tick - _first_tick
	_expect(
		advanced > BomberRules.TICK_HZ * SECONDS * 0.5,
		"o tique do servidor andou (%d tiques em %.0f s)" % [advanced, SECONDS]
	)
	_expect(_seat >= 0 and _seat < 4, "o assento é válido")
	_expect(_frames > 0, "chegaram linhas de comando usadas (%d)" % _frames)


func _on_joined(seat: int, host: bool) -> void:
	_seat = seat
	_host = host


func _on_denied(reason: int) -> void:
	_fail("a sala recusou: %d" % reason)


func _on_snapshot(raw: PackedByteArray) -> void:
	var state := BomberState.new()
	if not state.from_bytes(raw):
		_fail("snapshot de %d bytes não decodifica" % raw.size())
		return
	_snapshots += 1
	if _first_tick < 0:
		_first_tick = state.tick
	_last_tick = state.tick


# --- espera ------------------------------------------------------------------


func _wait_for_connection() -> bool:
	for frame in 600:
		if multiplayer.multiplayer_peer != null:
			var status := multiplayer.multiplayer_peer.get_connection_status()
			if status == MultiplayerPeer.CONNECTION_CONNECTED:
				return true
			if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
				return false
		await get_tree().process_frame
	return false


func _wait_for_seat() -> bool:
	for frame in 600:
		if _seat >= 0 or _failures > 0:
			return _seat >= 0
		await get_tree().process_frame
	return false


# --- utilidades --------------------------------------------------------------


func _arg_text(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	return fallback if at < 0 or at + 1 >= args.size() else args[at + 1]


func _arg_int(name: String, fallback: int) -> int:
	var text := _arg_text(name, "")
	return fallback if text == "" else int(text)


func _expect(condition: bool, what: String) -> void:
	if condition:
		print("   ok — %s" % what)
		return
	_fail(what)


func _fail(what: String) -> void:
	_failures += 1
	printerr("   FALHOU: %s" % what)


func _finish() -> void:
	if _failures == 0:
		print("OK — rede do Bomberman consistente.")
	else:
		printerr("%d verificação(ões) falharam." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
