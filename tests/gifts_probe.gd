extends Node

## Os presentes contra um PocketBase de verdade (`pocketbase/pb_hooks/presentes.pb.js`):
##
##   CASCAPP_PB_URL=http://127.0.0.1:18091 godot --headless --path . res://tests/gifts_probe.tscn
##
## Várias contas, trocadas pelo `Account` como em `account_probe.gd`: A manda a B,
## C é estranha, e S1..S5 são amigas de B para o teto do presentinho. As regras
## puras estão em `pocketbase/presentes.test.js`.

const USERS := "/api/collections/users/records/"

var _failures := 0
var _seed := ""
## semente → id da conta, e o token e o código de amigo dela.
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
	_seed = "presentes-%d" % Time.get_ticks_usec()
	for who in ["a", "b", "c"]:
		await _as(who)
	_check(_ids.size() == 3, "três contas novas entram")
	await _befriend("a", "b")
	var a := str(_ids["a"])
	var b := str(_ids["b"])
	var c := str(_ids["c"])

	print("presente de item")
	await _as("a")
	_equals((await _gift(b, "ball_wood"))["code"], 402, "sem saldo (50 < 150): 402")
	for i in 4:
		await _post("/api/cascapp/reward", {"game": "uno", "result": "win"})
	_equals((await _gift(c, "ball_wood"))["code"], 404, "para quem não é amigo: 404")
	_equals((await _gift(a, "ball_wood"))["code"], 404, "para si mesmo: 404")
	_equals((await _gift(b, "title_veteran"))["code"], 404, "exclusivo não se presenteia: 404")
	_equals((await _gift(b, "ball_nada"))["code"], 404, "item que não existe: 404")
	var sent := await _gift(b, "ball_wood")
	_equals(sent["code"], 200, "manda a bola de madeira")
	_equals(sent["data"].get("coins") if sent["data"] is Dictionary else null, 0.0, "e paga os 150")
	_equals((await _gift(b, "ball_wood"))["code"], 409, "o amigo já tem: 409")

	print("caixa de quem recebe")
	await _as("b")
	_check("ball_wood" in (await _record(b)).get("owned", []), "o item já entrou na conta do amigo")
	var inbox := await _inbox()
	_equals(inbox["gifts"].size(), 1, "um presente fechado na caixa")
	var gift: Dictionary = inbox["gifts"][0] if not inbox["gifts"].is_empty() else {}
	_equals(gift.get("item"), "ball_wood", "com o item")
	_equals(gift.get("from", {}).get("id"), a, "e quem mandou")
	await _as("c")
	_equals((await _open(str(gift.get("id", ""))))["code"], 404, "outra conta não abre")
	await _as("b")
	var opened := await _open(str(gift.get("id", "")))
	_equals(opened["code"], 200, "quem recebeu abre")
	_equals(opened["data"].get("item") if opened["data"] is Dictionary else null, "ball_wood", "e vê o que era")
	_equals((await _open(str(gift.get("id", ""))))["code"], 404, "abrir de novo: 404")
	_equals((await _inbox())["gifts"].size(), 0, "e a caixa esvazia")
	_equals((await Account._call(HTTPClient.METHOD_PATCH, USERS + b, {"look": {"ball": "ball_wood"}}))["code"], 200, "e dá para usar")

	print("presentinho do dia")
	await _as("a")
	_equals((await _daily(c))["code"], 404, "para quem não é amigo: 404")
	_equals((await _daily(b))["code"], 200, "manda o presentinho")
	_equals((await _daily(b))["code"], 409, "o segundo do dia para o mesmo amigo: 409")
	_check(b in (await _inbox())["sent_today"], "a caixa de quem mandou diz que já foi hoje")
	await _as("b")
	var before := int((await _record(b)).get("coins", 0))
	var daily: Dictionary = (await _inbox())["gifts"][0]
	_equals(daily.get("coins"), 10.0, "chega fechado, de 10 moedas")
	_equals(int((await _record(b)).get("coins", 0)), before, "e não paga antes de abrir")
	var got := await _open(str(daily.get("id", "")))
	_equals(int(got["data"].get("coins", 0)) if got["data"] is Dictionary else -1, 10, "abrir mostra as 10")
	_equals(int((await _record(b)).get("coins", 0)), before + 10, "e elas entram")

	print("teto de recebidos")
	for i in 4:
		await _befriend("s%d" % i, "b")
		await _as("s%d" % i)
		_equals((await _daily(b))["code"], 200, "presentinho %d de 5 que B recebe hoje" % (i + 2))
	await _befriend("s4", "b")
	await _as("s4")
	_equals((await _daily(b))["code"], 429, "o sexto do dia: 429")

	print("o app não mexe nos presentes")
	_check((await Account._call(HTTPClient.METHOD_GET, "/api/collections/gifts/records", {}))["code"] != 200, "nem lê a coleção")
	_check((await _post("/api/collections/gifts/records", {"from": b, "to": _ids["s4"], "coins": 999, "day": "2026-01-01"}))["code"] != 200, "nem cria presente")

	await _app_side(a, b)
	print("%s — %d falha(s)" % ["OK" if _failures == 0 else "FALHOU", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## O lado do app: `Account` e o `GiftsPanel`. A já mandou o presentinho de hoje
## para B; aqui A manda um item pela conta do app e B abre pelo painel.
func _app_side(a: String, b: String) -> void:
	print("presentes no app")
	await _as("a")
	_check(await Account.fetch_gifts(), "a caixa chega")
	_check(b in Account.gifts_sent_today, "e sabe que o presentinho de hoje já foi")
	_equals(Account.gift_daily_coins, 10, "e quanto ele vale")
	_equals(await Account.send_daily_gift(b), 409, "mandar de novo pelo app: 409")
	for i in 6:
		await _post("/api/cascapp/reward", {"game": "pool", "result": "win"})
	await Account.fetch_prices()
	# 6 vitórias de 25 = 150, a capa Feltro.
	_equals(await Account.send_gift(b, "banner_felt"), 200, "manda a capa pelo app")
	_equals(Account.coins, int((await _record(a)).get("coins", -1)), "e o saldo do app segue o do servidor")

	await _as("b")
	_check(await Account.fetch_gifts(), "B busca a caixa")
	# Os presentinhos do teto, acima, ainda estão fechados.
	_equals(Account.gifts.size(), 5, "com a capa e os quatro presentinhos fechados")
	var items := Account.gifts.filter(func(g: Dictionary) -> bool: return g.get("item") != "")
	var gift: Dictionary = items[0] if not items.is_empty() else {}
	_equals(GiftsPanel.contents_text(gift), "Capa Feltro", "o texto do que veio")
	_equals(GiftsPanel.contents_text({"item": "", "coins": 10}), "10 moedas", "e do presentinho")

	print("painel")
	var panel := GiftsPanel.new()
	add_child(panel)
	await get_tree().process_frame
	_equals(panel._rows.get_child_count(), 5, "um cartão por presente fechado")
	await panel._open(gift, GiftsPanel.GiftBox.new())
	_equals(Account.gifts.size(), 4, "abrir tira da caixa")
	_check(panel._revealed.has(str(gift.get("id", ""))), "e o cartão fica revelado na tela")
	_equals(panel._rows.get_child_count(), 5, "aberto continua na tela, revelado")
	_check(Account.owns("banner_felt"), "a capa é de B")
	var coins := Account.coins
	await panel._open(Account.gifts[0], GiftsPanel.GiftBox.new())
	_equals(Account.coins, coins + 10, "abrir um presentinho soma as moedas no app")
	panel.close()


## Entra como a conta `who`: cria e entra na primeira vez; depois só troca o
## token, porque o servidor limita as entradas por minuto (`1760600000_limites.js`).
func _as(who: String) -> void:
	if _tokens.has(who):
		Account._set_token(_tokens[who], _ids[who])
		Account.friend_code = _codes[who]
		return
	Account.device_seed = "%s-%s" % [_seed, who]
	Account.sign_out()
	# Na CI os probes anteriores já gastaram parte do limite do minuto: espera a
	# janela andar em vez de falhar.
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
	var code := Account.friend_code
	await _as(x)
	await Account.add_friend(code)
	await _as(y)
	var requests: Variant = await Account.friend_requests()
	for request: Dictionary in (requests["incoming"] if requests is Dictionary else []):
		await Account.accept_request(str(request["id"]))


func _gift(to: String, item: String) -> Dictionary:
	return await _post("/api/cascapp/gifts", {"to": to, "item": item})


func _daily(to: String) -> Dictionary:
	return await _post("/api/cascapp/gifts/daily", {"to": to})


func _open(id: String) -> Dictionary:
	return await _post("/api/cascapp/gifts/%s/open" % id, {})


func _inbox() -> Dictionary:
	var reply := await Account._call(HTTPClient.METHOD_GET, "/api/cascapp/gifts", {})
	return reply["data"] if reply["data"] is Dictionary else {"gifts": [], "sent_today": []}


func _record(id: String) -> Dictionary:
	var reply := await Account._call(HTTPClient.METHOD_GET, USERS + id, {})
	return reply["data"] if reply["data"] is Dictionary else {}


func _post(path: String, body: Dictionary) -> Dictionary:
	return await Account._call(HTTPClient.METHOD_POST, path, body)


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FALHOU", label])
	if not condition:
		_failures += 1


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
