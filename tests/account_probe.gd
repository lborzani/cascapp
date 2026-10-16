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
	# A foto de outra execução entraria na primeira conta nova.
	DirAccess.remove_absolute(Account.AVATAR_CACHE)
	Prefs.set_avatar_pending(false)

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

	print("perfil público")
	var own: Dictionary = (await Account._call(HTTPClient.METHOD_GET, "/api/collections/users/records/" + first, {}))["data"]
	var code := str(own.get("friend_code", ""))
	_equals(code.length(), 6, "a conta nasce com código de amigo")
	_equals(own.get("elo_chess"), 1200.0, "e Elo 1200")
	_equals(own.get("games_chess"), 0.0, "e nenhuma partida")
	for field: String in ["elo_chess", "games_chess", "friend_code"]:
		var forged := await Account._call(HTTPClient.METHOD_PATCH, "/api/collections/users/records/" + first, {field: 3000 if field != "friend_code" else "AAAAAA"})
		_check(forged["code"] != 200, "o app não escreve %s (HTTP %d)" % [field, forged["code"]])
	own = (await Account._call(HTTPClient.METHOD_GET, "/api/collections/users/records/" + first, {}))["data"]
	_equals(own.get("elo_chess"), 1200.0, "o Elo segue o do servidor")
	_equals(own.get("friend_code"), code, "e o código também")

	var forged_email := "forjada-%d@%s" % [Time.get_ticks_usec(), Account.EMAIL_DOMAIN]
	await Account._call(HTTPClient.METHOD_POST, "/api/collections/users/records", {
		"email": forged_email, "password": "senha-forjada-123", "passwordConfirm": "senha-forjada-123",
		"elo_chess": 9999, "games_chess": 50, "friend_code": "AAAAAA",
	})
	var forged_auth: Variant = (await Account._call(HTTPClient.METHOD_POST, "/api/collections/users/auth-with-password", {"identity": forged_email, "password": "senha-forjada-123"}))["data"]
	var forged_record: Dictionary = forged_auth["record"] if forged_auth is Dictionary and forged_auth.has("record") else {}
	_equals(forged_record.get("elo_chess"), 1200.0, "criar mandando Elo não muda o Elo inicial")
	_check(str(forged_record.get("friend_code", "")) not in ["", "AAAAAA"], "nem escolhe o código")

	Account.device_seed = device + "-outro"
	Account.sign_out()
	_check(await Account.sign_in(), "outra conta entra")
	var seen := await Account._call(HTTPClient.METHOD_GET, "/api/collections/users/records/" + first, {})
	_equals(seen["code"], 200, "e vê o perfil da primeira")
	var seen_data: Dictionary = seen["data"] if seen["data"] is Dictionary else {}
	_equals(seen_data.get("friend_code"), code, "com o código")
	_check(str(seen_data.get("email", "")).is_empty(), "sem o e-mail")
	var found := await Account._call(HTTPClient.METHOD_GET, "/api/cascapp/by-code/" + code.to_lower(), {})
	_equals(found["code"], 200, "acha a primeira pelo código, em minúsculas")
	var found_data: Dictionary = found["data"] if found["data"] is Dictionary else {}
	_equals(found_data.get("id"), first, "e é ela")
	_check(not found_data.has("email"), "sem e-mail na busca")
	_equals((await Account._call(HTTPClient.METHOD_GET, "/api/cascapp/by-code/ZZZZZ1", {}))["code"], 404, "código que não existe: 404")
	var listing: Variant = (await Account._call(HTTPClient.METHOD_GET, "/api/collections/users/records?perPage=50", {}))["data"]
	var items: Array = listing.get("items", []) if listing is Dictionary else []
	_check(items.size() == 1 and items[0]["id"] == Account.user_id, "listar contas só devolve a própria")
	Account.device_seed = device
	Account.sign_out()
	_equals((await Account._call(HTTPClient.METHOD_GET, "/api/cascapp/by-code/" + code, {}))["code"], 401, "sem conta não busca")
	_check(await Account.sign_in(), "volta ao primeiro aparelho")

	print("avatar")
	var photo := Image.create(640, 480, false, Image.FORMAT_RGB8)
	photo.fill(Color.ORANGE)
	Account.set_avatar(Avatar.compress(photo.save_jpg_to_buffer()))
	_check(Account.local_avatar() != null, "a foto vale no aparelho na hora")
	_check(await _settled(), "e sobe para a conta")
	var first_file := Account.avatar_file
	_check(not first_file.is_empty(), "que guarda o arquivo (%s)" % first_file)
	var full := await Account._raw(HTTPClient.METHOD_GET, Account.avatar_url(first, first_file).trim_prefix(Account.base_url()), "", PackedByteArray())
	var full_image := Avatar.decode(full["body"])
	_check(full_image != null and full_image.get_size() == Vector2i(Avatar.SIZE, Avatar.SIZE), "a foto volta pelo endereço público")
	var thumb := await Account._raw(HTTPClient.METHOD_GET, Account.avatar_url(first, first_file, "128x128").trim_prefix(Account.base_url()), "", PackedByteArray())
	var thumb_image := Avatar.decode(thumb["body"])
	_check(thumb_image != null and thumb_image.get_width() == 128, "e a miniatura de 128")

	DirAccess.remove_absolute(Account.AVATAR_CACHE)
	Account.sign_out()
	_check(await Account.sign_in(), "reinstalado, entra")
	_check(Account.local_avatar() != null, "e baixa a foto da conta")

	var url_before := Account.base_url()
	OS.set_environment("CASCAPP_PB_URL", "http://127.0.0.1:1")
	photo.fill(Color.TEAL)
	Account.set_avatar(Avatar.compress(photo.save_png_to_buffer()))
	_check(not await _settled(), "foto trocada com o servidor fora fica pendente")
	OS.set_environment("CASCAPP_PB_URL", url_before)
	Account.sign_out()
	_check(await Account.sign_in(), "volta a entrar")
	_check(not Prefs.avatar_pending() and Account.avatar_file != first_file, "e a conta alcança a foto nova")
	DirAccess.remove_absolute(Account.AVATAR_CACHE)

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


## Espera a foto pendente subir; falso se ela não subiu em `Account.TIMEOUT_SECONDS`.
func _settled() -> bool:
	var deadline := Time.get_ticks_msec() + int(Account.TIMEOUT_SECONDS * 1000) + 500
	while Prefs.avatar_pending() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return not Prefs.avatar_pending()


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FALHOU", label])
	if not condition:
		_failures += 1


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
