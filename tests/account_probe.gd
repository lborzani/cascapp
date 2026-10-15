extends Node

## A conta anônima contra um PocketBase de verdade, com as migrations do repo:
##
##   pocketbase serve --http 127.0.0.1:18091 --dir /tmp/pb --migrationsDir pocketbase/pb_migrations
##   CASCAPP_PB_URL=http://127.0.0.1:18091 godot --headless --path . res://tests/account_probe.tscn
##
## Cena, e não `--script`: `Account` é autoload, e autoload só existe numa cena.

var _failures := 0


func _ready() -> void:
	if Account.base_url().is_empty():
		printerr("defina CASCAPP_PB_URL apontando para um PocketBase de teste")
		get_tree().quit(1)
		return
	var name_before := Prefs.player_name() if Prefs.has_name() else ""
	var account_before := Prefs.account()
	# O autoload já tentou entrar sozinho; espera ele terminar antes de mexer.
	while Account._busy:
		await get_tree().process_frame

	print("conta anônima")
	Prefs.forget_account()
	Account.sign_out()
	Prefs.set_player_name("Probe")
	_check(await Account.sign_in(), "primeira abertura cria a conta e entra")
	_check(Prefs.account()["email"].ends_with("@" + Account.EMAIL_DOMAIN), "a credencial fica no aparelho")
	_check(Account._name == "Probe", "a conta nasce com o nome da tela Você")
	var first := Account.user_id

	Account.sign_out()
	_check(await Account.sign_in(), "a segunda abertura só entra")
	_equals(Account.user_id, first, "na mesma conta, sem criar outra")

	_check(await Account.push_name("Novo nome"), "salvar o nome sobe para a conta")
	var record: Dictionary = (await Account._call(HTTPClient.METHOD_GET, "/api/collections/users/records/" + first, {}))["data"]
	_equals(record.get("name"), "Novo nome", "e o servidor guarda")

	print("nome mudado com o servidor fora")
	Account.sign_out()
	Prefs.set_player_name("Renomeado")
	_check(await Account.sign_in(), "volta a entrar")
	record = (await Account._call(HTTPClient.METHOD_GET, "/api/collections/users/records/" + first, {}))["data"]
	_equals(record.get("name"), "Renomeado", "e a conta alcança o nome do aparelho")

	print("servidor fora do ar")
	var url := Account.base_url()
	Account.sign_out()
	OS.set_environment("CASCAPP_PB_URL", "http://127.0.0.1:1")
	_check(not await Account.sign_in(), "não entra, sem travar")
	_equals(Prefs.account()["email"].is_empty(), false, "e não esquece a credencial")
	OS.set_environment("CASCAPP_PB_URL", url)
	Account._retry.stop()

	print("conta apagada no servidor")
	_check(await Account.sign_in(), "entra de novo")
	await Account._call(HTTPClient.METHOD_DELETE, "/api/collections/users/records/" + first, {})
	Account.sign_out()
	_check(not await Account.sign_in(), "a credencial antiga é recusada")
	_check(Prefs.account()["email"].is_empty(), "e esquecida")
	_check(await Account.sign_in(), "a próxima tentativa cria outra conta")
	_check(Account.user_id != first, "com outro id")
	Account._retry.stop()

	Prefs.set_player_name(name_before)
	if account_before["email"].is_empty():
		Prefs.forget_account()
	else:
		Prefs.set_account(account_before["email"], account_before["password"])
	print("OK — conta." if _failures == 0 else "%d falha(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FALHOU", label])
	if not condition:
		_failures += 1


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
