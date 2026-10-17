extends Node

## A presença dos amigos ponta a ponta, contra um relay de verdade: dois
## `friends.gd` que se listam se veem online, e um deles aparece "na sala" quando
## senta numa — o caminho que a gaveta de amigos desenha.
##
## O relay precisa conferir contas, e o PocketBase não entra aqui: ele sobe com
## um verificador falso em que o token é o nome da conta.
##
##   cd relay && npm run build
##   node -e "import('./dist/server.js').then(m=>{const a={ana:'anaanaanaana123',bia:'biabiabiabia123'};m.createRelay({verifyToken:async t=>a[t]?{id:a[t],name:t,avatar:'',elo:1200}:null}).listen(8090,'127.0.0.1')})"
##   CHESS_RELAY_URL=ws://127.0.0.1:8090/ws godot --headless --path . res://tests/friends_smoke.tscn
##
## Sem `CHESS_RELAY_URL` o teste não roda, pelo mesmo motivo de `relay_smoke.gd`.

const FriendsScript := preload("res://autoload/friends.gd")
const ANA := "anaanaanaana123"
const BIA := "biabiabiabia123"
const CODE := "AMG234"
const TIMEOUT_SECONDS := 10.0

var _failures := 0


func _ready() -> void:
	var url := OS.get_environment("CHESS_RELAY_URL")
	if url.is_empty():
		print("CHESS_RELAY_URL não definida — pulando o teste de presença.")
		get_tree().quit(0)
		return
	_run(url)


func _run(url: String) -> void:
	await get_tree().process_frame
	var ana: Node = FriendsScript.new()
	var bia: Node = FriendsScript.new()
	add_child(ana)
	add_child(bia)
	ana.list = [{"id": BIA, "name": "Bia"}]
	bia.list = [{"id": ANA, "name": "Ana"}]
	ana.connect_presence(url, "ana")
	await _until(func() -> bool: return ana.is_open())
	bia.connect_presence(url, "bia")
	_check(await _until(func() -> bool: return bia.online.has(ANA)), "a Bia chega e já vê a Ana online")

	ana.watching = true
	_check(await _until(func() -> bool: return ana.online.has(BIA)), "a Ana, com a gaveta aberta, vê a Bia online")
	_check(Dictionary(ana.online.get(BIA, {})).get("room", "x") == "", "a Bia está fora de sala")

	# A Bia abre uma sala com a conta: o relay confere e conta para a Ana onde ela está.
	var table := WebSocketPeer.new()
	table.connect_to_url(url)
	await _until(func() -> bool:
		table.poll()
		return table.get_ready_state() == WebSocketPeer.STATE_OPEN
	)
	table.send_text(JSON.stringify({
		"t": "host", "room": CODE, "game": "chess", "listed": false, "tc": 0, "seats": 2, "name": "", "token": "bia",
	}))
	var seated := func() -> bool:
		table.poll()
		while table.get_available_packet_count() > 0:
			table.get_packet()
		ana._poll = minf(ana._poll, 0.3)
		return str(Dictionary(ana.online.get(BIA, {})).get("room", "")) == CODE
	_check(await _until(seated), "a Ana vê a Bia na sala %s" % CODE)
	_check(not bool(Dictionary(ana.online.get(BIA, {})).get("playing", true)), "mesa sem o segundo jogador: não está jogando ainda")
	table.close()

	# A Ana chama a Bia: o convite chega com o jogo e o código.
	var invites := []
	bia.invited.connect(func(from: String, game: StringName, code: String) -> void: invites.append([from, game, code]))
	ana.invite(BIA, &"chess", CODE)
	_check(await _until(func() -> bool: return not invites.is_empty()), "o convite da Ana chega na Bia")
	_check(invites.size() > 0 and invites[0] == [ANA, &"chess", CODE], "com quem chamou, o jogo e a sala")

	# A Bia fecha o app: some do online da Ana.
	bia.queue_free()
	var gone := func() -> bool:
		ana._poll = minf(ana._poll, 0.3)
		return not ana.online.has(BIA)
	_check(await _until(gone), "a Bia fechou o app e saiu do online")

	if _failures == 0:
		print("OK — presença dos amigos ponta a ponta.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	ana.queue_free()
	get_tree().quit(1 if _failures > 0 else 0)


func _until(condition: Callable) -> bool:
	var waited := 0.0
	while not condition.call():
		if waited > TIMEOUT_SECONDS:
			return false
		await get_tree().process_frame
		waited += 1.0 / 60.0
		await get_tree().create_timer(1.0 / 60.0).timeout
	return true


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
