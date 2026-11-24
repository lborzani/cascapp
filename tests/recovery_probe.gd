extends Node

## A conta protegida por e-mail contra um PocketBase de verdade, com as
## migrations e os hooks do repo (`pocketbase/pb_hooks/conta.pb.js`). O
## PocketBase sobe com `CASCAPP_MAIL_CAPTURE=1`: o código não sai por e-mail e
## fica legível pela rota de teste.
##
##   CASCAPP_MAIL_CAPTURE=1 pocketbase serve --http 127.0.0.1:18091 --dir /tmp/pb --migrationsDir pocketbase/pb_migrations --hooksDir pocketbase/pb_hooks
##   CASCAPP_PB_URL=http://127.0.0.1:18091 godot --headless --path . res://tests/recovery_probe.tscn
##
## As regras puras (formato, limites, validade) estão em
## `pocketbase/conta.test.js`. Duas sementes de aparelho fazem o papel do
## celular antigo e do formatado.

const USERS := "/api/collections/users/records/"

var _failures := 0
## A conta protegida pela tela Você, que a recuperação pela tela traz de volta.
var _screen_id := ""


func _ready() -> void:
	if Account.base_url().is_empty():
		printerr("defina CASCAPP_PB_URL apontando para um PocketBase de teste")
		get_tree().quit(1)
		return
	while Account._busy:
		await get_tree().process_frame
	var stamp := Time.get_ticks_usec()
	var email := "conta-%d@example.com" % stamp

	print("celular antigo")
	await _become("conta-a-%d" % stamp)
	_check(Account.signed_in(), "conta antiga entra")
	await _until(func() -> bool: return Account.coins == 50)
	var old_id := Account.user_id
	var old_code := Account.friend_code
	var old_record: Dictionary = (await Account._call(HTTPClient.METHOD_GET, USERS + old_id, {}))["data"]
	_equals(old_record.get("coins"), 50.0, "com o bônus do dia")

	print("proteger")
	_equals((await _start("semarroba", "protect"))["code"], 400, "e-mail sem formato: 400")
	_equals((await _start("x@anon.cascapp.invalid", "protect"))["code"], 400, "e-mail sintético: 400")
	_equals((await _start(email, "outra"))["code"], 400, "finalidade que não existe: 400")
	_equals((await _post("/api/cascapp/email/protect", {"code": "123456"}))["data"].get("reason"), "missing", "sem pedir código antes: recusado")
	_equals((await _start(email, "protect"))["code"], 200, "pedir o código responde 200")
	var code := await _last_code(email)
	_check(code.length() == 6, "o código tem 6 dígitos")
	var wrong := await _post("/api/cascapp/email/protect", {"code": _other(code)})
	_equals(wrong["code"], 400, "código errado: 400")
	_equals(wrong["data"].get("reason"), "wrong", "com o motivo")
	var protect := await _post("/api/cascapp/email/protect", {"code": code})
	_equals(protect["code"], 200, "código certo protege")
	_equals(protect["data"].get("contact_email"), email, "e devolve o e-mail")
	var record: Dictionary = (await Account._call(HTTPClient.METHOD_GET, USERS + old_id, {}))["data"]
	_equals(record.get("contact_email"), email, "a conta guarda o e-mail")
	var forged := await Account._call(HTTPClient.METHOD_PATCH, USERS + old_id, {"contact_email": "outro@example.com"})
	_check(forged["code"] != 200, "o app não escreve o e-mail direto (HTTP %d)" % forged["code"])
	_equals((await _post("/api/cascapp/email/protect", {"code": code}))["code"], 400, "o código usado não vale de novo")

	print("outra conta não toma o e-mail")
	await _become("conta-b-%d" % stamp)
	var new_id := Account.user_id
	_check(not new_id.is_empty() and new_id != old_id, "o celular formatado nasce noutra conta")
	_equals((await _start(email, "protect"))["code"], 200, "pedir o código responde igual")
	_equals((await _post("/api/cascapp/email/protect", {"code": await _last_code(email)}))["code"], 409, "e a confirmação recusa: 409")

	print("recuperar")
	var nobody := "ninguem-%d@example.com" % stamp
	_equals((await _start(nobody, "recover"))["code"], 200, "e-mail sem conta responde 200")
	_equals((await _code_reply(nobody))["code"], 404, "e nenhum código sai")
	_equals((await _start(email, "recover"))["code"], 200, "e-mail da conta antiga: 200")
	code = await _last_code(email)
	var password: String = Account._credentials()["password"]
	_equals((await _recover(email, code, "senha-errada"))["code"], 403, "senha que não é deste aparelho: 403")
	for i in 5:
		_equals((await _recover(email, _other(code), password))["data"].get("reason"), "wrong", "tentativa errada %d" % (i + 1))
	_equals((await _recover(email, code, password))["data"].get("reason"), "locked", "depois de 5, nem o certo vale")
	_equals((await _start(email, "recover"))["code"], 200, "um código novo")
	var recover := await _recover(email, await _last_code(email), password)
	_equals(recover["code"], 200, "o código novo recupera")
	Account.sign_out()
	_check(await Account.sign_in(), "o aparelho novo entra com a credencial de sempre")
	_equals(Account.user_id, old_id, "e cai na conta antiga")
	_equals(Account.friend_code, old_code, "com o código de amigo dela")
	record = (await Account._call(HTTPClient.METHOD_GET, USERS + old_id, {}))["data"]
	_equals(record.get("coins"), old_record.get("coins"), "e as moedas dela")
	_equals(record.get("contact_email"), email, "ainda protegida pelo e-mail")
	# A conta vazia sumiu: o e-mail da conta é único, e a conta antiga só pôde
	# ficar com o sintético deste aparelho porque a vazia saiu antes. Ler pelo
	# id não provaria nada, porque a conta dos outros já responde 404.
	await _become("conta-a-%d" % stamp)
	_check(Account.signed_in() and Account.user_id != old_id, "o celular antigo não entra mais nela")

	print("recuperar a própria conta")
	await _become("conta-b-%d" % stamp)
	_equals((await _start(email, "recover"))["code"], 200, "pedir responde 200")
	_equals((await _recover(email, await _last_code(email), Account._credentials()["password"]))["data"].get("reason"), "same", "a conta já é deste aparelho: recusado")

	print("limite de envios")
	var busy := "limite-%d@example.com" % stamp
	for i in 3:
		_equals((await _start(busy, "protect"))["code"], 200, "envio %d" % (i + 1))
	_equals((await _start(busy, "protect"))["code"], 429, "o quarto em 15 minutos: 429")

	_check(await _test_screen(stamp) == true, "a tela Você terminou")
	_check(await _test_recover_screen(stamp) == true, "a recuperação pela tela terminou")

	print("sem conta")
	Account.sign_out()
	_equals((await _start(email, "recover"))["code"], 401, "pedir código pede conta")

	print("FALHAS: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## A linha da aba Você e o painel de proteger, tocados como o jogador tocaria.
func _test_screen(stamp: int) -> bool:
	print("tela Você")
	await _become("conta-tela-%d" % stamp)
	var settings: Node = load("res://scenes/settings.tscn").instantiate()
	add_child(settings)
	await get_tree().process_frame
	var row: Button = settings.find_child("ProtectButton", true, false)
	_check(row != null, "a linha existe")
	_equals(row.get_meta(&"title"), "Proteja sua conta", "sem proteção, ela convida")
	_equals(row.get_meta(&"lit"), true, "acesa")
	row.pressed.emit()
	var panel: EmailPanel = settings._email
	_check(is_instance_valid(panel), "o toque abre o painel")
	_equals(panel._title.text, "Proteger conta", "para proteger")
	_check(panel._switch.visible, "com o caminho para a conta antiga")
	_screen_id = Account.user_id
	_check(await Account.push_name("Antiga"), "a conta tem nome")
	var email := "tela-%d@example.com" % stamp
	panel._email.text = "sem arroba"
	panel._send.pressed.emit()
	_equals(panel._note.text, "Confira o e-mail.", "e-mail torto nem sai do aparelho")
	panel._email.text = " Tela-%d@Example.com " % stamp
	panel._send.pressed.emit()
	await _until(func() -> bool: return panel._code_step.visible)
	_check(panel._code_step.visible, "mandou: aparece o passo do código")
	_check("t***@example.com" in panel._intro.text, "com o e-mail mascarado")
	var code := await _last_code(email)
	_check(code.length() == 6, "o código saiu para o e-mail em minúsculas")
	panel._code.set_code(_other(code))
	await get_tree().process_frame
	await _until(func() -> bool: return not panel._busy)
	_check(panel._note.text.begins_with("Código errado"), "código errado avisa")
	panel._code.set_code(code)
	await _until(func() -> bool: return not is_instance_valid(panel))
	_check(not is_instance_valid(panel), "o código certo fecha o painel")
	_equals(Account.contact_email, email, "a conta sabe o e-mail")
	_equals(row.get_meta(&"title"), "Conta protegida", "a linha mostra a proteção")
	_equals(row.get_meta(&"detail"), "t***@example.com", "com o e-mail mascarado")
	row.pressed.emit()
	_check(not is_instance_valid(settings._email), "protegida, o toque não abre nada")
	Account.sign_out()
	await get_tree().process_frame
	_equals(row.get_meta(&"detail"), "Precisa de internet", "sem conta, avisa")
	row.pressed.emit()
	_check(not is_instance_valid(settings._email), "e não abre o painel")
	settings.queue_free()
	return true


## O celular formatado volta para a conta da tela Você pela boas-vindas, e fica
## com o nome de lá. O caminho pela aba Você é o mesmo painel; aqui só se
## confere que o link troca o modo, porque ao voltar ela remonta a cena atual,
## que nesta sonda é a própria sonda.
func _test_recover_screen(stamp: int) -> bool:
	print("recuperar pela tela")
	var name_before := Prefs.player_name() if Prefs.has_name() else ""
	Prefs.set_player_name("Novo")
	await _become("conta-tela-nova-%d" % stamp)
	_check(Account.user_id != _screen_id, "o celular formatado nasce noutra conta")

	var settings: Node = load("res://scenes/settings.tscn").instantiate()
	add_child(settings)
	await get_tree().process_frame
	settings.find_child("ProtectButton", true, false).pressed.emit()
	var panel: EmailPanel = settings._email
	panel._switch.pressed.emit()
	_equals(panel._title.text, "Recuperar conta", "o link troca para recuperar")
	_check(not panel._switch.visible, "e some")
	settings.queue_free()

	var welcome := WelcomePanel.new()
	welcome.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(welcome)
	await get_tree().process_frame
	var finished := [false]
	welcome.finished.connect(func() -> void: finished[0] = true)
	(welcome.find_children("*", "Button", true, false).filter(
		func(button: Button) -> bool: return button.text == "Já tenho conta"
	)[0] as Button).pressed.emit()
	panel = welcome._email
	_check(is_instance_valid(panel) and panel.recover, "a boas-vindas abre o painel de recuperar")
	var email := "tela-%d@example.com" % stamp
	panel._email.text = email
	panel._send.pressed.emit()
	await _until(func() -> bool: return panel._code_step.visible)
	_check("Se t***@example.com protege uma conta" in panel._intro.text, "a frase não promete que a conta existe")
	panel._code.set_code(await _last_code(email))
	await _until(func() -> bool: return finished[0])
	_check(finished[0], "voltou: a boas-vindas termina")
	_check(Prefs.welcomed(), "e não volta")
	_equals(Account.user_id, _screen_id, "este celular está na conta antiga")
	_equals(Account.contact_email, email, "protegida pelo mesmo e-mail")
	_equals(Prefs.player_name(), "Antiga", "com o nome de lá, e não o deste celular")
	var record: Dictionary = (await Account._call(HTTPClient.METHOD_GET, USERS + _screen_id, {}))["data"]
	_equals(record.get("name"), "Antiga", "e a conta não levou o nome deste celular")
	await get_tree().process_frame
	_check(not is_instance_valid(welcome), "a boas-vindas sai da tela")
	Prefs.set_player_name(name_before)
	return true


## Entra como o aparelho de semente `seed`.
func _become(seed: String) -> void:
	Account.device_seed = seed
	Account.sign_out()
	await Account.sign_in()


func _start(email: String, purpose: String) -> Dictionary:
	return await _post("/api/cascapp/email/start", {"email": email, "purpose": purpose})


func _recover(email: String, code: String, password: String) -> Dictionary:
	return await _post("/api/cascapp/email/recover", {"email": email, "code": code, "password": password})


func _code_reply(email: String) -> Dictionary:
	return await Account._call(HTTPClient.METHOD_GET, "/api/cascapp/test/last-code/" + email.uri_encode(), {})


func _last_code(email: String) -> String:
	var reply := await _code_reply(email)
	return str(reply["data"].get("code", "")) if reply["data"] is Dictionary else ""


## Um código de 6 dígitos diferente de `code`.
func _other(code: String) -> String:
	return "%06d" % ((code.to_int() + 1) % 1000000)


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
