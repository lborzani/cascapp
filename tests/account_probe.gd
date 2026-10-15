extends Node

## A conta anônima contra um PocketBase de verdade, com as migrations do repo:
##
##   pocketbase serve --http 127.0.0.1:18091 --dir /tmp/pb --migrationsDir pocketbase/pb_migrations
##   CASCAPP_PB_URL=http://127.0.0.1:18091 godot --headless --path . res://tests/account_probe.tscn
##
## Reescreve o `prefs.cfg` do usuário de teste (o "reinstalar" apaga o arquivo);
## o nome salvo antes volta no fim, o resto das preferências não.
##
## Cena, e não `--script`: `Account` é autoload, e autoload só existe numa cena.

var _failures := 0


func _ready() -> void:
	if Account.base_url().is_empty():
		printerr("defina CASCAPP_PB_URL apontando para um PocketBase de teste")
		get_tree().quit(1)
		return
	var name_before := Prefs.player_name() if Prefs.has_name() else ""
	# O autoload já tentou entrar sozinho; espera ele terminar antes de mexer.
	while Account._busy:
		await get_tree().process_frame

	print("conta do aparelho")
	# Um aparelho novo por execução: o PocketBase local guarda as anteriores.
	Account.device_seed = "probe-%d" % Time.get_ticks_usec()
	Account.sign_out()
	Prefs.set_player_name("Probe")
	_check(await Account.sign_in(), "primeira abertura cria a conta e entra")
	_check(Account._name == "Probe", "a conta nasce com o nome da tela Você")
	var first := Account.user_id

	Account.sign_out()
	_check(await Account.sign_in(), "a segunda abertura só entra")
	_equals(Account.user_id, first, "na mesma conta, sem criar outra")

	print("reinstalar o app")
	# Desinstalar apaga o `user://`; o id do aparelho fica.
	var reinstall := ConfigFile.new()
	reinstall.save(Prefs.PATH)
	Prefs.forget()
	Account.sign_out()
	_check(await Account.sign_in(), "depois de reinstalar entra")
	_equals(Account.user_id, first, "e é a mesma conta de antes")

	print("outro aparelho")
	var device := Account.device_seed
	Account.device_seed = device + "-outro"
	Account.sign_out()
	_check(await Account.sign_in(), "outro aparelho entra")
	_check(Account.user_id != first, "numa conta própria")
	Account.device_seed = device

	Prefs.set_player_name("Probe")
	Account.sign_out()
	_check(await Account.sign_in(), "de volta ao primeiro aparelho")
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
	OS.set_environment("CASCAPP_PB_URL", url)
	Account._retry.stop()

	print("conta apagada no painel")
	_check(await Account.sign_in(), "entra de novo")
	await Account._call(HTTPClient.METHOD_DELETE, "/api/collections/users/records/" + first, {})
	Account.sign_out()
	_check(await Account.sign_in(), "a próxima entrada recria a conta do aparelho")
	_check(Account.user_id != first, "com outro id")
	Account._retry.stop()

	Prefs.set_player_name(name_before)
	print("OK — conta." if _failures == 0 else "%d falha(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FALHOU", label])
	if not condition:
		_failures += 1


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
