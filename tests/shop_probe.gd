extends Node

## A loja e as moedas contra um PocketBase de verdade, com as migrations e os
## hooks do repo (`pocketbase/pb_hooks/loja.pb.js`):
##
##   pocketbase serve --http 127.0.0.1:18091 --dir /tmp/pb --migrationsDir pocketbase/pb_migrations --hooksDir pocketbase/pb_hooks
##   CASCAPP_PB_URL=http://127.0.0.1:18091 godot --headless --path . res://tests/shop_probe.tscn
##
## As regras puras (dia de Brasília, teto, visual) estão em
## `pocketbase/loja.test.js`; aqui entram as rotas, a regra de atualização e a
## transação. Cena, e não `--script`: `Account` é autoload.

const USERS := "/api/collections/users/records/"

var _failures := 0


func _ready() -> void:
	if Account.base_url().is_empty():
		printerr("defina CASCAPP_PB_URL apontando para um PocketBase de teste")
		get_tree().quit(1)
		return
	while Account._busy:
		await get_tree().process_frame
	# Uma conta nova por execução: o PocketBase local guarda as anteriores.
	Account.device_seed = "loja-%d" % Time.get_ticks_usec()
	Account.sign_out()
	_check(await Account.sign_in(), "conta nova entra")
	var me := USERS + Account.user_id

	print("preços")
	Account.sign_out()
	var shop := await Account._call(HTTPClient.METHOD_GET, "/api/cascapp/shop", {})
	_equals(shop["code"], 200, "a tabela de preços é aberta")
	var prices: Dictionary = shop["data"].get("items", {}) if shop["data"] is Dictionary else {}
	_equals(prices.get("ball_wood"), 150.0, "com o preço de cada item")
	_equals((await _post("/api/cascapp/daily", {}))["code"], 401, "sem conta não ganha bônus")
	_equals((await _post("/api/cascapp/reward", {"game": "uno", "result": "win"}))["code"], 401, "nem prêmio")
	_equals((await _post("/api/cascapp/buy", {"item": "ball_wood"}))["code"], 401, "nem compra")
	_check(await Account.sign_in(), "volta a entrar")

	print("bônus diário")
	# A conta nasce com 0 (ver a criação forjada, abaixo) e a entrada do app já
	# pede o bônus do dia.
	await _until(func() -> bool: return Account.coins == 50)
	var record: Dictionary = (await Account._call(HTTPClient.METHOD_GET, me, {}))["data"]
	_equals(record.get("coins"), 50.0, "a entrada pagou o bônus de 50")
	var daily := await _post("/api/cascapp/daily", {})
	_equals(daily["code"], 200, "o bônus responde")
	_equals(daily["data"].get("granted"), 0.0, "pedir de novo no mesmo dia não paga")
	_equals(daily["data"].get("coins"), 50.0, "e o saldo fica")

	print("prêmio por partida")
	_equals((await _post("/api/cascapp/reward", {"game": "xadrez", "result": "win"}))["code"], 400, "jogo que não existe: 400")
	_equals((await _post("/api/cascapp/reward", {"game": "uno", "result": "ganhei"}))["code"], 400, "desfecho que não existe: 400")
	var reward := await _post("/api/cascapp/reward", {"game": "bowling", "result": "loss"})
	_equals(reward["data"].get("granted"), 10.0, "perder paga 10")
	reward = await _post("/api/cascapp/reward", {"game": "chess", "result": "draw"})
	_equals(reward["data"].get("granted"), 15.0, "empatar paga 15")
	var paid := 25
	for i in 20:
		reward = await _post("/api/cascapp/reward", {"game": "uno", "result": "win"})
		paid += int(reward["data"].get("granted", 0))
	_equals(paid, 300, "as vitórias param no teto de 300 do dia")
	_equals(reward["data"].get("granted"), 0.0, "acima do teto, nada")
	_equals(reward["data"].get("coins"), 350.0, "saldo = bônus + teto")

	print("compra")
	_equals((await _post("/api/cascapp/buy", {"item": "ball_nada"}))["code"], 404, "item que não existe: 404")
	_equals((await _post("/api/cascapp/buy", {"item": "ball_galaxy"}))["code"], 402, "sem saldo (400 > 350): 402")
	var bought := await _post("/api/cascapp/buy", {"item": "ball_wood"})
	_equals(bought["code"], 200, "compra a bola de madeira")
	_equals(bought["data"].get("coins"), 200.0, "pelo preço do servidor")
	_equals(bought["data"].get("owned"), ["ball_wood"], "e ela entra nos itens")
	_equals((await _post("/api/cascapp/buy", {"item": "ball_wood"}))["code"], 409, "comprar de novo: 409")
	# Saldo 200 e duas bolas de 200 pedidas juntas: cada uma cabe, as duas não.
	var codes := []
	var buy := func(item: String) -> void:
		codes.append((await _post("/api/cascapp/buy", {"item": item}))["code"])
	buy.call("ball_melon")
	buy.call("ball_checker")
	while codes.size() < 2:
		await get_tree().process_frame
	codes.sort()
	_equals(codes, [200, 402], "duas compras ao mesmo tempo: o saldo só paga uma")
	record = (await Account._call(HTTPClient.METHOD_GET, me, {}))["data"]
	_equals(record.get("coins"), 0.0, "e o saldo fica em 0, nunca negativo")
	_equals((record.get("owned") as Array).size(), 2, "com dois itens")

	print("o app não escreve a carteira")
	for field: String in ["coins", "owned", "daily_day", "earned_day", "earned_today"]:
		var value: Variant = 99999 if field in ["coins", "earned_today"] else (["ball_galaxy"] if field == "owned" else "2000-01-01")
		var forged := await Account._call(HTTPClient.METHOD_PATCH, me, {field: value})
		_check(forged["code"] != 200, "%s recusado (HTTP %d)" % [field, forged["code"]])
	var after: Dictionary = (await Account._call(HTTPClient.METHOD_GET, me, {}))["data"]
	_equals(after.get("coins"), record.get("coins"), "o saldo segue o do servidor")

	var email := "loja-forjada-%d@%s" % [Time.get_ticks_usec(), Account.EMAIL_DOMAIN]
	await Account._call(HTTPClient.METHOD_POST, "/api/collections/users/records", {
		"email": email, "password": "senha-forjada-123", "passwordConfirm": "senha-forjada-123",
		"coins": 99999, "owned": ["ball_galaxy"], "look": {"ball": "ball_galaxy"},
	})
	var forged_auth: Variant = (await Account._call(HTTPClient.METHOD_POST, "/api/collections/users/auth-with-password", {"identity": email, "password": "senha-forjada-123"}))["data"]
	var forged: Dictionary = forged_auth["record"] if forged_auth is Dictionary and forged_auth.has("record") else {}
	_equals(forged.get("coins"), 0.0, "criar a conta mandando moedas nasce com 0")
	_equals(forged.get("owned"), [], "e sem itens")
	_equals(forged.get("look"), {}, "e sem visual")

	print("equipar")
	var equip := await Account._call(HTTPClient.METHOD_PATCH, me, {"look": {"ball": "ball_galaxy"}})
	_equals(equip["code"], 403, "item pago não comprado: 403")
	equip = await Account._call(HTTPClient.METHOD_PATCH, me, {"look": {"ball": "ball_wood", "skin": "skin_2"}})
	_equals(equip["code"], 200, "item comprado e cor grátis: 200")
	_equals(equip["data"].get("look") if equip["data"] is Dictionary else null, {"ball": "ball_wood", "skin": "skin_2"}, "e o visual fica salvo")
	_equals((await Account._call(HTTPClient.METHOD_PATCH, me, {"look": ["ball_wood"]}))["code"], 400, "visual fora do formato: 400")
	_equals((await Account._call(HTTPClient.METHOD_PATCH, me, {"name": "Loja"}))["code"], 200, "mudar o nome continua livre")

	await _app_wallet()
	Prefs.forget_rewards()
	print("%s — %d falha(s)" % ["OK" if _failures == 0 else "FALHOU", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## O lado do app: `Account` pede o bônus na entrada, e o cartão de fim
## (`ResultHeader`) paga a partida contra bot, uma vez, e põe na fila sem conta.
func _app_wallet() -> void:
	print("carteira no app")
	Prefs.forget_rewards()
	Account.device_seed = "loja-app-%d" % Time.get_ticks_usec()
	Account.sign_out()
	Account.daily_notice = 0
	_check(await Account.sign_in(), "outra conta nova entra")
	await _until(func() -> bool: return Account.daily_notice > 0)
	_equals(Account.daily_notice, 50, "a entrada pede o bônus do dia")
	_equals(Account.coins, 50, "e o saldo chega à conta do app")
	Account.daily_notice = 0
	await Account.claim_daily()
	_equals(Account.daily_notice, 0, "pedir de novo no mesmo dia não avisa")

	print("prêmio pelo cartão de fim")
	Game.game_id = Game.BOWLING
	Game.mode = Game.Mode.SOLO
	Game.match_started_at = 1000
	var header := ResultHeader.new()
	add_child(header)
	header.show_result(ResultHeader.Mood.WIN, [["1:00", "duração"]])
	await _until(func() -> bool: return header.stats_row().get_child_count() == 2)
	_equals(Account.coins, 75, "a vitória contra o bot paga 25")
	_equals(_tile_text(header, 1), "+25", "e o bloco das moedas entra no fim da fileira")
	header.set_stats([["1:00", "duração"], ["Elo 1210", "xadrez"]])
	_equals(_tile_text(header, 2), "+25", "números novos da cena não apagam o bloco")
	header.show_result(ResultHeader.Mood.WIN, [["1:00", "duração"]])
	await get_tree().create_timer(1.0).timeout
	_equals(Account.coins, 75, "o cartão que reabre não paga de novo")

	Game.match_started_at = 1001
	Game.mode = Game.Mode.HOTSEAT
	header.show_result(ResultHeader.Mood.WIN, [["1:00", "duração"]])
	await get_tree().create_timer(1.0).timeout
	_equals(Account.coins, 75, "mesmo aparelho não paga")
	_equals(header.stats_row().get_child_count(), 1, "e a revanche limpa o bloco da partida de antes")

	Game.match_started_at = 1002
	Game.mode = Game.Mode.ONLINE
	header.show_result(ResultHeader.Mood.LOSS, [])
	await _until(func() -> bool: return Account.coins == 85)
	_equals(Account.coins, 85, "a derrota online paga 10")

	print("prêmio sem conta")
	Account.sign_out()
	Game.match_started_at = 1003
	header.show_result(ResultHeader.Mood.DRAW, [])
	await get_tree().create_timer(0.5).timeout
	_equals(Prefs.pending_rewards().size(), 1, "sem conta o prêmio fica na fila")
	_check(await Account.sign_in(), "a conta volta")
	await _until(func() -> bool: return Prefs.pending_rewards().is_empty())
	_check(Prefs.pending_rewards().is_empty(), "e a fila sobe na entrada")
	_equals(Account.coins, 100, "com os 15 do empate")
	header.queue_free()

	print("comprar e usar pela conta do app")
	_check(await Account.fetch_prices(), "a loja traz os preços")
	_check(not Account.owns("ball_wood"), "a bola de madeira ainda não é dela")
	_equals(await Account.equip(Cosmetics.BALL, "ball_wood"), false, "e não dá para usar sem comprar")
	_equals(await Account.buy("ball_galaxy"), 402, "a galáxia (400) não cabe em 100")
	# 100 + duas vitórias (50) dá a madeira (150).
	for i in 2:
		Game.match_started_at = 2000 + i
		await Account.reward(Game.BOWLING, "win", "%s:%d" % [Game.BOWLING, Game.match_started_at])
	_equals(await Account.buy("ball_wood"), 200, "a madeira (150) com 150")
	_equals(Account.coins, 0, "o saldo do app segue o do servidor")
	_check(Account.owns("ball_wood"), "agora é dela")
	_check(await Account.equip(Cosmetics.BALL, "ball_wood"), "e dá para usar")
	_equals(Account.look, {"ball": "ball_wood"}, "o visual da conta muda")
	_equals(Prefs.look(), {"ball": "ball_wood"}, "a cópia do aparelho também")
	_equals(Net.player_look, {"ball": "ball_wood"}, "e o próximo aperto de mão leva a bola nova")
	_check(Cosmetics.ball_texture(Account.look) != null, "o catálogo acha a textura dela")
	_check(await Account.equip(Cosmetics.BALL, ""), "voltar ao padrão")
	_equals(Account.look, {}, "deixa o visual vazio")

	print("tabuleiro e peças")
	_equals(await Account.equip(Cosmetics.FINISH, "finish_gems"), false, "o acabamento não comprado não entra")
	_equals(await Account.equip(Cosmetics.PIECES, "pieces_medieval"), false, "nem o conjunto de peças")
	_equals(await Account.equip(Cosmetics.BOARD, "board_tournament"), false, "o tabuleiro não comprado não entra")
	# Saldo 0 + seis vitórias (150) dá o torneio (150).
	for i in 6:
		await Account.reward(Game.CHESS, "win", "tabuleiro:%d" % i)
	_equals(await Account.buy("board_tournament"), 200, "o torneio (150) com 150")
	_check(await Account.equip(Cosmetics.BOARD, "board_tournament"), "e entra em uso")
	_equals(Account.look, {"board": "board_tournament"}, "o visual guarda o tabuleiro")
	var board := BoardView.new()
	_equals(board.skins[Board.Side.WHITE]["dark"], Color("769656"), "o tabuleiro aberto depois tem as casas do torneio")
	_equals(board.skins[Board.Side.BLACK]["frame"], Color("2c3a24"), "nas duas metades, com a moldura dele")
	board.free()
	_check(await Account.equip(Cosmetics.BOARD, ""), "o tabuleiro volta ao padrão")
	board = BoardView.new()
	_equals(board.skins, [Cosmetics.DEFAULT_BOARD, Cosmetics.DEFAULT_BOARD], "e o próximo tabuleiro é o do tema")
	board.free()
	Account.sign_out()
	Prefs.set_look({"ball": "ball_wood"})
	Prefs.forget()
	_equals(Prefs.look(), {"ball": "ball_wood"}, "a cópia do aparelho sobrevive a reabrir o app")
	_check(await Account.sign_in(), "e a entrada traz o da conta")
	_equals(Prefs.look(), {}, "que vale por cima da cópia")


func _tile_text(header: ResultHeader, index: int) -> String:
	if header.stats_row().get_child_count() <= index:
		return ""
	return (header.stats_row().get_child(index).find_children("*", "Label", true, false)[0] as Label).text


## Espera a condição valer, até 10 s.
func _until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _post(path: String, body: Dictionary) -> Dictionary:
	return await Account._call(HTTPClient.METHOD_POST, path, body)


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FALHOU", label])
	if not condition:
		_failures += 1


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
