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
## A foto deste aparelho mudou: escolhida agora ou baixada da conta.
signal avatar_changed
## Chegou a foto de outra conta pedida em [method avatar_of].
signal remote_avatar_loaded

const DEFAULT_URL := "https://mammus.tailb8b7e1.ts.net:8443"
const EMAIL_DOMAIN := "anon.cascapp.invalid"
const RETRY_SECONDS := 60.0
## Um pedido a mais que isto é servidor fora do ar, e não lentidão.
const TIMEOUT_SECONDS := 8.0
## A foto deste aparelho, já comprimida. Vale antes de a conta ter recebido.
const AVATAR_CACHE := "user://avatar.webp"

var token := ""
## Só para os testes: troca o id do aparelho, para cada execução ter a própria
## conta num PocketBase que guarda as anteriores.
var device_seed := ""
var user_id := ""
## O nome do arquivo da foto na conta (`avatar` do registro); vazio sem foto.
var avatar_file := ""
## O Elo do xadrez desta conta, como a última entrada disse. 0 sem Elo.
var elo := 0
## O nome que a conta tem no servidor, como a última resposta disse.
var _name := ""
var _busy := false
var _local_texture: Texture2D = null
## Nome do arquivo → foto de outra conta (`null` enquanto baixa).
var _remote := {}
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
	var has_local := FileAccess.file_exists(AVATAR_CACHE)
	if ok and (Prefs.avatar_pending() or (has_local and avatar_file.is_empty())):
		# Idem para a foto escolhida com o servidor fora — ou para a conta que
		# renasceu sem a foto que o aparelho tem.
		await push_avatar()
	elif ok and not avatar_file.is_empty() and not has_local:
		# A conta tem foto e o aparelho não: reinstalação. Baixa a de lá.
		await _fetch_own_avatar()
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


# --- avatar ---------------------------------------------------------------------
#
# A foto já sai comprimida de `Avatar.compress`. Ela vale primeiro no aparelho
# (`AVATAR_CACHE`) e sobe para a conta quando der, como o nome: servidor fora
# deixa a troca pendente no `Prefs`, e a próxima entrada a completa.


## A foto nova do jogador, já no formato do avatar.
func set_avatar(webp: PackedByteArray) -> void:
	var file := FileAccess.open(AVATAR_CACHE, FileAccess.WRITE)
	file.store_buffer(webp)
	file.close()
	_local_texture = null
	Prefs.set_avatar_pending(true)
	avatar_changed.emit()
	push_avatar()


## A foto deste aparelho, ou `null` sem foto. Decodificada uma vez: a etiqueta
## da partida pergunta a cada lance.
func local_avatar() -> Texture2D:
	if _local_texture == null and FileAccess.file_exists(AVATAR_CACHE):
		_local_texture = Avatar.texture(FileAccess.get_file_as_bytes(AVATAR_CACHE))
	return _local_texture


## A foto de outra conta, pela miniatura. `null` enquanto ela não chegou: o
## primeiro pedido dispara o download, e [signal remote_avatar_loaded] avisa
## quando ela estiver aqui. Uma vez por arquivo enquanto o app está aberto — a
## foto trocada nasce com outro nome, e o pedido seguinte já é o dela.
func avatar_of(id: String, file: String) -> Texture2D:
	if id.is_empty() or file.is_empty():
		return null
	if not _remote.has(file):
		_remote[file] = null
		_load_remote(id, file)
	return _remote[file]


func _load_remote(id: String, file: String) -> void:
	var path := avatar_url(id, file, "128x128").trim_prefix(base_url())
	var reply := await _raw(HTTPClient.METHOD_GET, path, "", PackedByteArray())
	var picture := Avatar.texture(reply["body"]) if reply["code"] == 200 else null
	if picture == null:
		# Falhou: esquece, para a próxima pergunta tentar de novo.
		_remote.erase(file)
		return
	_remote[file] = picture
	remote_avatar_loaded.emit()


func push_avatar() -> bool:
	if not signed_in() or not FileAccess.file_exists(AVATAR_CACHE):
		return false
	var boundary := "cascapp" + _random_hex(12)
	var body := ("--%s\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"avatar.webp\"\r\nContent-Type: image/webp\r\n\r\n" % boundary).to_utf8_buffer()
	body.append_array(FileAccess.get_file_as_bytes(AVATAR_CACHE))
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var reply := await _raw(
		HTTPClient.METHOD_PATCH, "/api/collections/users/records/" + user_id,
		"multipart/form-data; boundary=" + boundary, body
	)
	if reply["code"] != 200:
		return false
	var data: Variant = JSON.parse_string((reply["body"] as PackedByteArray).get_string_from_utf8())
	if data is Dictionary:
		avatar_file = str(data.get("avatar", ""))
	Prefs.set_avatar_pending(false)
	return true


## O endereço público da foto de uma conta. `thumb` é uma das miniaturas da
## coleção (`128x128`); vazio, a foto inteira.
static func avatar_url(id: String, file: String, thumb := "") -> String:
	var url := "%s/api/files/users/%s/%s" % [base_url(), id, file]
	return url + ("?thumb=" + thumb if not thumb.is_empty() else "")


func _fetch_own_avatar() -> void:
	var reply := await _raw(HTTPClient.METHOD_GET, avatar_url(user_id, avatar_file).trim_prefix(base_url()), "", PackedByteArray())
	if reply["code"] != 200 or Avatar.decode(reply["body"]) == null:
		return
	var file := FileAccess.open(AVATAR_CACHE, FileAccess.WRITE)
	file.store_buffer(reply["body"])
	file.close()
	_local_texture = null
	avatar_changed.emit()


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
	avatar_file = str(data["record"].get("avatar", ""))
	elo = int(data["record"].get("elo_chess", 0))
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
	var reply := await _raw(method, path, "application/json", JSON.stringify(body).to_utf8_buffer())
	var text := (reply["body"] as PackedByteArray).get_string_from_utf8()
	# 204 (apagar) vem sem corpo, e o parser reclamaria do vazio.
	return {"code": reply["code"], "data": JSON.parse_string(text) if not text.is_empty() else null}


## `{"code": int, "body": PackedByteArray}`, para corpo que não é JSON (a foto).
func _raw(method: int, path: String, content_type: String, body: PackedByteArray) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var headers := PackedStringArray()
	if not content_type.is_empty():
		headers.append("Content-Type: " + content_type)
	if signed_in():
		headers.append("Authorization: " + token)
	var started := http.request_raw(base_url() + path, headers, method, body)
	var reply := {"code": 0, "body": PackedByteArray()}
	if started == OK:
		var result: Array = await http.request_completed
		if result[0] == HTTPRequest.RESULT_SUCCESS:
			reply["code"] = result[1]
			reply["body"] = result[3]
	http.queue_free()
	return reply


static func _random_hex(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()
