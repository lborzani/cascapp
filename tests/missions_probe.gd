extends Node

## As missões contra um PocketBase de verdade (`pocketbase/pb_hooks/missoes.pb.js`):
##
##   CASCAPP_PB_URL=http://127.0.0.1:18091 CASCAPP_PB_SUPERUSER=email:senha godot --headless --path . res://tests/missions_probe.tscn
##
## As regras puras (sorteio, progresso, janela, poda) estão em
## `pocketbase/missoes.test.js`. Sem `CASCAPP_PB_SUPERUSER`, pula a parte do admin.

const USERS := "/api/collections/users/records/"
const GAMES := ["chess", "checkers", "battleship", "ludo", "monopoly", "uno", "pool", "bowling"]

var _failures := 0
var _admin: RefCounted = null


func _ready() -> void:
	if Account.base_url().is_empty():
		printerr("defina CASCAPP_PB_URL apontando para um PocketBase de teste")
		get_tree().quit(1)
		return
	while Account._busy:
		await get_tree().process_frame
	Account.device_seed = "missoes-%d" % Time.get_ticks_usec()
	Account.sign_out()
	_check(await Account.sign_in(), "conta nova entra")
	# A entrada pede o bônus do dia; espera para o saldo não andar no meio.
	await _until(func() -> bool: return Account.coins == 50)

	print("lista")
	var missions := await _missions()
	_equals(_track(missions, "daily").size(), 3, "três diárias")
	_equals(_track(missions, "perm").size(), 3, "três conquistas")
	_check(missions.all(func(m: Dictionary) -> bool: return m["progress"] == 0.0 and not m["claimed"]), "tudo zerado")
	_equals(_track(missions, "daily").map(func(m: Dictionary) -> String: return m["key"]), _track(await _missions(), "daily").map(func(m: Dictionary) -> String: return m["key"]), "o sorteio do dia não muda entre pedidos")

	print("resgate antes da hora")
	_equals((await _claim(_track(missions, "daily")[0]["key"]))["code"], 409, "incompleta: 409")
	_equals((await _claim("d_nada"))["code"], 404, "fora do ar: 404")

	print("progresso pelo prêmio da partida")
	var done := []
	for game: String in GAMES + ["chess", "pool", "bowling"]:
		var reply := await _post("/api/cascapp/reward", {"game": game, "result": "win"})
		done.append_array(reply["data"].get("missions_done", []) if reply["data"] is Dictionary else [])
	_check("p_explorer" in done, "o oitavo jogo diferente completa o Explorador")
	missions = await _missions()
	_check(_track(missions, "daily").all(func(m: Dictionary) -> bool: return m["progress"] == m["target"]), "as três diárias completas")
	_equals(_find(missions, "p_veteran")["progress"], 11.0, "Veterano conta 11 partidas")
	_equals(_find(missions, "p_champion")["progress"], 11.0, "Campeão conta 11 vitórias")
	_equals(_find(missions, "p_explorer")["progress"], 8.0, "Explorador no alvo, 8")

	print("resgate")
	# O saldo do servidor: os prêmios acima foram por fora da carteira do app.
	var coins := int((await Account._call(HTTPClient.METHOD_GET, USERS + Account.user_id, {}))["data"].get("coins", 0))
	for m: Dictionary in _track(missions, "daily"):
		var claim := await _claim(m["key"])
		_equals(claim["code"], 200, "resgata %s" % m["key"])
		var now := int(claim["data"].get("coins", 0)) if claim["data"] is Dictionary else 0
		_equals(now - coins, int(m["reward_coins"]), "e ganha %d moedas" % int(m["reward_coins"]))
		coins = now
		_equals((await _claim(m["key"]))["code"], 409, "resgatar de novo: 409")
	var explorer := await _claim("p_explorer")
	_equals(explorer["code"], 200, "resgata o Explorador")
	_check("title_explorer" in (explorer["data"].get("owned", []) as Array), "e o título exclusivo entra nos itens")
	var me := USERS + Account.user_id
	_equals((await Account._call(HTTPClient.METHOD_PATCH, me, {"look": {"title": "title_explorer"}}))["code"], 200, "e dá para equipar")
	_equals((await Account._call(HTTPClient.METHOD_PATCH, me, {"look": {"title": "title_veteran"}}))["code"], 403, "o exclusivo não ganho não equipa")
	_check(_find(await _missions(), "p_explorer")["claimed"], "a lista mostra resgatada")

	print("o app não escreve o progresso")
	var forged := await Account._call(HTTPClient.METHOD_PATCH, me, {"missions_state": {"perm": {"p": {"p_veteran": 100}, "c": [], "g": []}}})
	_check(forged["code"] != 200, "missions_state recusado (HTTP %d)" % forged["code"])

	await _admin_events()
	await _app_side()
	Prefs.forget_rewards()
	print("%s — %d falha(s)" % ["OK" if _failures == 0 else "FALHOU", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Evento criado no admin: aparece na janela, paga, e some quando ela fecha.
func _admin_events() -> void:
	print("eventos no admin")
	_check((await Account._call(HTTPClient.METHOD_GET, "/api/collections/missions/records", {}))["code"] != 200, "o app não lê as missões cruas")
	_admin = preload("res://tests/pb_admin.gd").new(self)
	if not await _admin.sign_in():
		print("  (pulado: sem CASCAPP_PB_SUPERUSER)")
		return
	var now := int(Time.get_unix_time_from_system())
	var key := "probe_%d" % Time.get_ticks_usec()
	var event: Dictionary = (await _admin.call_api(HTTPClient.METHOD_POST, "/api/collections/events/records", {
		"key": key, "name": "Evento de teste", "starts": _date(now - 3600), "ends": _date(now + 3600),
	}))["data"]
	_check(event.has("id"), "o admin cria o evento")
	var missions_url := "/api/collections/missions/records"
	var base := {"key": key + "_m", "track": "event", "event": event.get("id", ""), "kind": "play", "target": 1, "reward_coins": 5, "active": true}
	_equals((await _admin.call_api(HTTPClient.METHOD_POST, missions_url, base.merged({"reward_item": "title_nada"}, true)))["code"], 400, "item do prêmio que não existe: 400")
	_equals((await _admin.call_api(HTTPClient.METHOD_POST, missions_url, base.merged({"event": ""}, true)))["code"], 400, "missão de evento sem evento: 400")
	_equals((await _admin.call_api(HTTPClient.METHOD_POST, missions_url, base.merged({"reward_coins": 0}, true)))["code"], 400, "missão que não paga nada: 400")
	_equals((await _admin.call_api(HTTPClient.METHOD_POST, missions_url, base))["code"], 200, "e cria a missão do evento")

	var listed := await Account._call(HTTPClient.METHOD_GET, "/api/cascapp/missions", {})
	var events: Array = listed["data"].get("events", []) if listed["data"] is Dictionary else []
	_check(events.any(func(e: Dictionary) -> bool: return e["key"] == key), "o evento aparece no ar")
	_equals(_find(await _missions(), key + "_m").get("event"), key, "com a missão dele")
	await _post("/api/cascapp/reward", {"game": "uno", "result": "loss"})
	_equals((await _claim(key + "_m"))["code"], 200, "uma partida e resgata")

	await _admin.call_api(HTTPClient.METHOD_PATCH, "/api/collections/events/records/" + str(event.get("id", "")), {"ends": _date(now - 60)})
	_check(_find(await _missions(), key + "_m").is_empty(), "fechada a janela, a missão some")
	_equals((await _claim(key + "_m"))["code"], 404, "e não se resgata")
	await _admin.call_api(HTTPClient.METHOD_DELETE, "/api/collections/events/records/" + str(event.get("id", "")), {})


## O lado do app: `Account` e o `MissionsPanel`, com outra conta nova.
func _app_side() -> void:
	print("missões no app")
	Prefs.forget_rewards()
	Account.device_seed = "missoes-app-%d" % Time.get_ticks_usec()
	Account.sign_out()
	_check(await Account.sign_in(), "outra conta nova entra")
	_check(await Account.fetch_prices(), "a loja traz o catálogo")
	_check("title_veteran" in Account.exclusive, "com os exclusivos à parte")
	_check(not Account.owns("title_veteran"), "exclusivo não ganho não é dela")
	_check(not Account.owns("ball_wood"), "item à venda não comprado também não")
	_check(Account.owns("skin_2"), "e o grátis é de todo mundo")
	_check(await Account.fetch_missions(), "as missões chegam")
	_equals(Account.missions.size(), 6, "três do dia e três conquistas")
	_equals(Account.missions_ready(), 0, "nada pronto ainda")

	for i in GAMES.size():
		await Account.reward(StringName(GAMES[i]), "win", "missoes-app:%d" % i)
	_check("p_explorer" in Account.missions_notice, "o prêmio avisa a missão completa")
	await _until(func() -> bool: return Account.missions_ready() > 0)
	_check(Account.missions_ready() >= 1, "e a lista mostra pronta para resgatar")
	_equals(await Account.claim_mission("p_explorer"), 200, "resgata pelo app")
	_check(Account.owns("title_explorer"), "o título entra na carteira do app")
	_check(_find(Account.missions, "p_explorer").get("claimed", false), "e a lista marca resgatada")
	_equals(await Account.claim_mission("p_explorer"), 409, "de novo: 409")

	print("texto das missões")
	_equals(MissionsPanel.describe({"kind": "win", "target": 3, "game": "uno"}), "Vença 3 partidas de Uno", "vencer num jogo")
	_equals(MissionsPanel.describe({"kind": "play", "target": 1, "game": ""}), "Termine 1 partida", "jogar uma")
	_equals(MissionsPanel.describe({"kind": "variety", "target": 4}), "Jogue 4 jogos diferentes", "variados")
	_equals(MissionsPanel.prize_text({"reward_item": "title_veteran", "reward_coins": 0}), "Título Veterano", "prêmio item")
	_equals(MissionsPanel.prize_text({"reward_item": "", "reward_coins": 30}), "+30 moedas", "prêmio moedas")
	_equals(MissionsPanel.tabs_for([{"key": "natal", "name": "Natal"}]).size(), 3, "uma aba por evento no ar")

	print("painel")
	var panel := MissionsPanel.new()
	add_child(panel)
	await get_tree().process_frame
	_equals(panel._rows.get_child_count(), 3, "Hoje mostra as três do dia")
	panel._tabs.selected.emit(1)
	_equals(panel._rows.get_child_count(), 3, "Conquistas mostra as três")
	panel.close()

	print("folha da tela inicial")
	var sheet := MissionsPanel.new()
	sheet.sheet = true
	var events := {"closed": 0, "gone": false}
	sheet.closed.connect(func() -> void: events["closed"] += 1)
	sheet.tree_exited.connect(func() -> void: events["gone"] = true)
	add_child(sheet)
	await get_tree().process_frame
	_check(sheet._sheet != null and sheet._sheet.is_inside_tree(), "abre numa BottomSheet")
	_equals(sheet._rows.get_child_count(), 3, "com as três do dia")
	_check(sheet._toast.get_parent().get_parent() == sheet, "o aviso fica fora da lista")
	_check(sheet._toast.size.x > 0.0, "e com largura, não torto na borda")
	sheet.close()
	sheet.close()
	await get_tree().create_timer(0.6).timeout
	_check(events["gone"], "fechar desce e sai da árvore")
	_equals(events["closed"], 1, "avisando uma vez só")
	Account.missions_notice.clear()


static func _date(unix: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix, true) + "Z"


func _missions() -> Array:
	var reply := await Account._call(HTTPClient.METHOD_GET, "/api/cascapp/missions", {})
	return reply["data"].get("missions", []) if reply["data"] is Dictionary else []


func _track(missions: Array, track: String) -> Array:
	return missions.filter(func(m: Dictionary) -> bool: return m["track"] == track)


func _find(missions: Array, key: String) -> Dictionary:
	for m: Dictionary in missions:
		if m["key"] == key:
			return m
	return {}


func _claim(key: String) -> Dictionary:
	return await _post("/api/cascapp/missions/claim", {"key": key})


func _post(path: String, body: Dictionary) -> Dictionary:
	return await Account._call(HTTPClient.METHOD_POST, path, body)


func _until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FALHOU", label])
	if not condition:
		_failures += 1


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
