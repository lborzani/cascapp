extends Node

## A conta do jogador no PocketBase do servidor de casa (`pocketbase/`).
##
## Anônima e sem tela: o e-mail sintético e a senha são **derivados do
## aparelho** (`OS.get_unique_id()`, o `ANDROID_ID` no Android) por hash. No
## primeiro uso o app cria a conta com eles; daí em diante só entra.
##
## Derivados, e não sorteados e guardados: desinstalar apaga o `user://`, e com
## a credencial guardada lá cada reinstalação nascia uma conta nova. O
## `ANDROID_ID` sobrevive à reinstalação (muda com reset de fábrica e com outra
## chave de assinatura), então reinstalar volta para a mesma conta. O id em si
## nunca sai do aparelho — só o hash.
## O nome é o da tela "Você" — salvar lá sobe para a conta.
##
## Nada aqui é obrigatório para jogar. Servidor fora do ar, sem rede, resposta
## estranha: `signed_in()` fica falso, o app segue igual, e uma nova tentativa
## acontece a cada `RETRY_SECONDS` e quando o app volta ao primeiro plano.

signal signed_in_changed(now: bool)

const DEFAULT_URL := "https://mammus.tailb8b7e1.ts.net:8443"
const EMAIL_DOMAIN := "anon.cascapp.invalid"
const RETRY_SECONDS := 60.0
## Um pedido a mais que isto é servidor fora do ar, e não lentidão.
const TIMEOUT_SECONDS := 8.0

var token := ""
## Só para os testes: troca o id do aparelho, para cada execução ter a própria
## conta num PocketBase que guarda as anteriores.
var device_seed := ""
var user_id := ""
## O nome que a conta tem no servidor, como a última resposta disse.
var _name := ""
var _busy := false
var _retry: Timer = null


## Fora do APK (editor, suítes headless) a conta só liga com `CASCAPP_PB_URL`
## apontando para um PocketBase de teste: rodar a CI não pode criar conta no
## servidor de verdade.
static func base_url() -> String:
	if OS.has_environment("CASCAPP_PB_URL"):
		return OS.get_environment("CASCAPP_PB_URL")
	return "" if OS.has_feature("editor") else DEFAULT_URL


func _ready() -> void:
	_retry = Timer.new()
	_retry.wait_time = RETRY_SECONDS
	_retry.one_shot = true
	_retry.timeout.connect(sign_in)
	add_child(_retry)
	if not base_url().is_empty():
		sign_in()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and not signed_in() and not base_url().is_empty():
		sign_in()


func signed_in() -> bool:
	return not token.is_empty()


## Cria a conta se ainda não existe e entra. Devolve se entrou.
func sign_in() -> bool:
	if _busy or base_url().is_empty():
		return signed_in()
	_busy = true
	var credentials := _credentials()
	var code := await _authenticate(credentials)
	if code == 400:
		# Recusada: a conta deste aparelho ainda não existe — primeiro uso, ou
		# apagada no painel. Nasce agora, com a mesma credencial.
		if await _create(credentials):
			code = await _authenticate(credentials)
	var ok := code == 200
	_busy = false
	if ok and Prefs.has_name() and _name != Prefs.player_name():
		# O nome mudou enquanto o servidor estava fora: a conta alcança agora.
		await push_name(Prefs.player_name())
	if not ok:
		_retry.start()
	return ok


## Sobe o nome da tela "Você". Sem conta ainda, não há o que fazer: o nome vai
## junto quando ela for criada, e a próxima entrada não sobrescreve nada.
func push_name(name: String) -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_PATCH, "/api/collections/users/records/" + user_id, {"name": name})
	if reply["code"] == 200:
		_name = name
	return reply["code"] == 200


## Esquece a sessão (não a conta). Para os testes.
func sign_out() -> void:
	_set_token("", "")


## `{"email", "password"}` deste aparelho, sempre os mesmos.
##
## Sem id de aparelho (plataforma que não informa), um sorteado uma vez e
## guardado no `Prefs` faz o papel — e aí a reinstalação volta a criar outra.
func _credentials() -> Dictionary:
	var seed := device_seed if not device_seed.is_empty() else OS.get_unique_id()
	if seed.is_empty():
		seed = Prefs.account_seed()
		if seed.is_empty():
			seed = _random_hex(16)
			Prefs.set_account_seed(seed)
	return {
		"email": "%s@%s" % [("cascapp:email:" + seed).sha256_text().left(32), EMAIL_DOMAIN],
		"password": ("cascapp:password:" + seed).sha256_text(),
	}


func _create(credentials: Dictionary) -> bool:
	var body := {
		"email": credentials["email"],
		"password": credentials["password"],
		"passwordConfirm": credentials["password"],
	}
	if Prefs.has_name():
		body["name"] = Prefs.player_name()
	var reply := await _call(HTTPClient.METHOD_POST, "/api/collections/users/records", body)
	return reply["code"] == 200


## O código HTTP da tentativa: 200 entrou, 400 credencial recusada, 0 sem
## resposta (rede, servidor fora do ar).
func _authenticate(credentials: Dictionary) -> int:
	var reply := await _call(
		HTTPClient.METHOD_POST, "/api/collections/users/auth-with-password",
		{"identity": credentials["email"], "password": credentials["password"]}
	)
	var data: Variant = reply["data"]
	if reply["code"] != 200:
		return reply["code"]
	if not data is Dictionary or not data.has("token"):
		return 0
	_name = str(data["record"].get("name", ""))
	_set_token(str(data["token"]), str(data["record"]["id"]))
	return 200


func _set_token(value: String, id: String) -> void:
	var before := signed_in()
	token = value
	user_id = id
	if signed_in() != before:
		signed_in_changed.emit(signed_in())


## `{"code": int, "data": Variant}`; `code` 0 quando nem resposta houve.
func _call(method: int, path: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if signed_in():
		headers.append("Authorization: " + token)
	var started := http.request(base_url() + path, headers, method, JSON.stringify(body))
	var reply := {"code": 0, "data": null}
	if started == OK:
		var result: Array = await http.request_completed
		if result[0] == HTTPRequest.RESULT_SUCCESS:
			reply["code"] = result[1]
			var text := (result[3] as PackedByteArray).get_string_from_utf8()
			# 204 (apagar) vem sem corpo, e o parser reclamaria do vazio.
			reply["data"] = JSON.parse_string(text) if not text.is_empty() else null
	http.queue_free()
	return reply


static func _random_hex(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()
