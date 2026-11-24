extends Node

## Bloquear, desbloquear e silenciar amigos contra um PocketBase de verdade
## (`pocketbase/pb_hooks/amigos.pb.js`, `pb_migrations/1764300000_bloqueios.js`):
##
##   CASCAPP_PB_URL=http://127.0.0.1:18091 godot --headless --path . res://tests/blocks_probe.tscn
##
## A e B são amigos; A bloqueia B. Contas trocadas como em `gifts_probe.gd`.

var _failures := 0
var _seed := ""
var _ids := {}
var _tokens := {}
var _codes := {}


func _ready() -> void:
	if Account.base_url().is_empty():
		printerr("defina CASCAPP_PB_URL apontando para um PocketBase de teste")
		get_tree().quit(1)
		return
	while Account._busy:
		await get_tree().process_frame
	_seed = "bloqueios-%d" % Time.get_ticks_usec()
	for who in ["a", "b"]:
		await _as(who)
	await _befriend("a", "b")
	var a := str(_ids["a"])
	var b := str(_ids["b"])

	print("silenciar")
	await _as("a")
	# Com aparelho, a mensagem de B vira push. O PocketBase do teste aponta o
	# push para lugar nenhum: cada aviso tentado deixa "push falhou" no log dele,
	# e só a mensagem de depois de reativar deve deixar.
	await Account.push_token("token-de-teste-" + a)
	_equals(_friend(await _friends(), b).get("muted"), false, "amigo novo não vem silenciado")
	Friends.list = await _friends()
	Friends.requests = {"incoming": [], "outgoing": []}
	Friends.unread = {b: 3}
	_equals(Friends.alerts(), 3, "não lidas de B acendem a bolinha")
	var profile := FriendProfile.new()
	profile.friend_id = b
	add_child(profile)
	await get_tree().process_frame
	var mute: Button = profile.find_child("Mute", true, false)
	_equals(mute.text if mute else null, "Silenciar", "o perfil oferece Silenciar")
	await profile._toggle_mute(mute)
	_check(Friends.is_muted(b), "Silenciar no perfil silencia")
	_equals(mute.text, "Reativar avisos", "e o botão vira Reativar")
	_equals(Friends.alerts(), 0, "silenciado não acende a bolinha")
	_equals(Friends.unread_of(b), 3, "mas o contador dele continua")
	profile.close()
	_check(await Account.mute_friend(b, true), "Account.mute_friend")
	_equals(_friend(await _friends(), b).get("muted"), true, "a lista diz silenciado")
	await _as("b")
	_equals(_friend(await _friends(), a).get("muted"), false, "do lado de B nada muda")
	_equals((await _send(a))["code"], 200, "B manda mensagem para quem o silenciou")
	await _as("a")
	_equals((await _mute(b, false))["code"], 204, "reativa B")
	_equals(_friend(await _friends(), b).get("muted"), false, "a lista diz reativado")
	await _as("b")
	_equals((await _send(a))["code"], 200, "B manda de novo, agora com aviso")
	await _as("a")
	_equals((await _mute(b, "sim"))["code"], 400, "muted que não é booleano: 400")
	_equals((await _mute("naoexiste12345", true))["code"], 404, "quem não é amigo: 404")

	print("bloquear")
	_equals((await _call(HTTPClient.METHOD_POST, "/api/cascapp/blocks/" + a))["code"], 400, "a si mesmo: 400")
	_equals((await _call(HTTPClient.METHOD_POST, "/api/cascapp/blocks/naoexiste12345"))["code"], 404, "conta que não existe: 404")
	_check(await Account.block(b), "A bloqueia B")
	_equals((await _call(HTTPClient.METHOD_POST, "/api/cascapp/blocks/" + b))["code"], 204, "de novo: 204")
	_check(_friend(await _friends(), b).is_empty(), "B saiu da lista de A")
	var blocks: Array = await Account.blocks()
	_equals(blocks.size(), 1, "um bloqueado")
	_equals(blocks[0].get("id") if not blocks.is_empty() else null, b, "e é B")
	await _as("b")
	_check(_friend(await _friends(), a).is_empty(), "A saiu da lista de B")
	_equals((await _send(a))["code"], 404, "B não conversa mais com A")
	var asked := await Account.add_friend(str(_codes["a"]))
	_equals(asked["code"], 200, "B pede A pelo código: 200")
	_equals(asked["data"].get("status") if asked["data"] is Dictionary else null, "requested", "e parece que foi")
	await _as("a")
	var pending: Dictionary = await Account.friend_requests()
	_equals(pending["incoming"].size(), 0, "mas nada chega para A")
	_equals((await Account.add_friend(str(_codes["b"])))["code"], 409, "A pede B enquanto bloqueia: 409")

	print("desbloquear")
	var panel := FriendsPanel.new()
	add_child(panel)
	while panel._blocked.get_child_count() == 0:
		await get_tree().process_frame
	_equals(panel._blocked.get_child_count(), 2, "o painel mostra a seção Bloqueados com B")
	var unblock: Button = panel._blocked.find_children("", "Button", true, false).back()
	await panel._unblock(b, unblock)
	_check(true, "A desbloqueia B pelo painel")
	await get_tree().process_frame
	panel.close()
	_equals((await _call(HTTPClient.METHOD_DELETE, "/api/cascapp/blocks/" + b))["code"], 204, "de novo: 204")
	_equals((await _blocks()).size(), 0, "lista de bloqueados vazia")
	_check(_friend(await _friends(), b).is_empty(), "a amizade não volta sozinha")
	await _befriend("a", "b")
	await _as("a")
	_check(not _friend(await _friends(), b).is_empty(), "pedido novo refaz a amizade")

	print("bloquear com pedido pendente")
	await _as("b")
	var page := FriendProfile.new()
	page.friend_id = a
	add_child(page)
	await get_tree().process_frame
	var remove: Button = page.find_child("Remove", true, false)
	await page._confirm(remove, "Remover", Account.remove_friend)
	_equals(remove.text, "Confirmar?", "Remover no perfil pede confirmação")
	await page._confirm(remove, "Remover", Account.remove_friend)
	_check(page.is_queued_for_deletion(), "o segundo toque remove e fecha o perfil")
	_check(_friend(await _friends(), a).is_empty(), "A saiu da lista de B")
	await Account.add_friend(str(_codes["a"]))
	await _as("a")
	await _call(HTTPClient.METHOD_POST, "/api/cascapp/blocks/" + b)
	pending = await Account.friend_requests()
	_equals(pending["incoming"].size(), 0, "bloquear apaga o pedido de B")

	print("%d falha(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _friend(list: Array, id: String) -> Dictionary:
	for friend: Dictionary in list:
		if str(friend.get("id", "")) == id:
			return friend
	return {}


func _friends() -> Array:
	var list: Variant = await Account.friends()
	return list if list is Array else []


func _blocks() -> Array:
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/blocks")
	return reply["data"].get("items", []) if reply["data"] is Dictionary else []


func _mute(id: String, muted: Variant) -> Dictionary:
	return await Account._call(HTTPClient.METHOD_PUT, "/api/cascapp/friends/%s/mute" % id, {"muted": muted})


func _send(to: String) -> Dictionary:
	return await Account.send_chat(to, {"kind": "text", "text": "oi"})


func _call(method: int, path: String) -> Dictionary:
	return await Account._call(method, path, {})


## Igual a `gifts_probe.gd`.
func _as(who: String) -> void:
	if _tokens.has(who):
		Account._set_token(_tokens[who], _ids[who])
		Account.friend_code = _codes[who]
		return
	Account.device_seed = "%s-%s" % [_seed, who]
	Account.sign_out()
	for attempt in 8:
		if await Account.sign_in():
			break
		await get_tree().create_timer(10.0).timeout
	_ids[who] = Account.user_id
	_tokens[who] = Account.token
	_codes[who] = Account.friend_code


## `x` pede e `y` aceita.
func _befriend(x: String, y: String) -> void:
	await _as(y)
	await _as(x)
	await Account.add_friend(str(_codes[y]))
	await _as(y)
	var requests: Variant = await Account.friend_requests()
	for request: Dictionary in (requests["incoming"] if requests is Dictionary else []):
		await Account.accept_request(str(request["id"]))


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FALHOU", label])
	if not condition:
		_failures += 1


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
