class_name ServerSearch
extends Stockfish

## O Stockfish do servidor (`/search`, SF 19) com a cara do motor local: quem
## julga uma posição (`GameReview.look`, o desafio, a avaliação ao vivo) não
## sabe de onde a nota veio. Sem conta, sem rede, ou com o servidor recusando
## (fila cheia, limite), a busca cai no Stockfish do aparelho, que só sobe na
## primeira vez que for preciso.
##
## Bloqueante, como o pai: roda na thread de quem chama. O bot não usa isto —
## ele joga com a força limitada, e aí o servidor só somaria espera.

## Conexão e resposta, somadas. Passou disso, a busca é local.
const TIMEOUT_MS := 4000
## Depois de uma falha de rede, quanto tempo seguir só no aparelho antes de
## tentar o servidor de novo. Sem isso, cada lance no modo avião esperaria a
## conexão falhar.
const RETRY_MS := 30000

var _local: Stockfish = null
var _elo := 0
var _client: HTTPClient = null
var _down_until := 0


## Sempre sobe: o servidor é tentado a cada busca, e o motor local só quando ele
## falhar. Falso só se nem o servidor estiver disponível nem o motor local subir.
func start(_path := "") -> bool:
	return _server_ready() or _local_engine() != null


func running() -> bool:
	return _server_ready() or (_local != null and _local.running())


## A força vale só para o motor local; o servidor busca sempre em força total.
func set_strength(elo: int) -> void:
	_elo = elo
	if _local != null:
		_local.set_strength(elo)


func ready() -> bool:
	return true


func search(fen: String, movetime_ms: int, moves := PackedStringArray(), nodes := 0) -> Dictionary:
	if _server_ready():
		var seen := _ask({"fen": fen} if moves.is_empty() else {"moves": " ".join(moves)})
		if not seen.is_empty():
			return seen
	var engine := _local_engine()
	return {} if engine == null else engine.search(fen, movetime_ms, moves, nodes)


func quit() -> void:
	if _local != null:
		_local.quit()
		_local = null
	if _client != null:
		_client.close()
		_client = null


func _server_ready() -> bool:
	return Account.signed_in() and not Account.base_url().is_empty() and Time.get_ticks_msec() >= _down_until


func _local_engine() -> Stockfish:
	if _local == null:
		var engine := Stockfish.new()
		if not engine.start():
			return null
		engine.set_strength(_elo)
		_local = engine
	return _local if _local.running() else null


## `{"best", "mate", "wdl", "cp"}`, como `Stockfish.search`, ou vazio. Erro de
## rede deixa o servidor de lado por `RETRY_MS`; resposta recusada (429, 503)
## não, porque é passageira.
func _ask(body: Dictionary) -> Dictionary:
	var url := parse_url(Account.base_url() + "/search")
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	if _client == null or _client.get_status() != HTTPClient.STATUS_CONNECTED:
		_client = HTTPClient.new()
		var tls: TLSOptions = TLSOptions.client() if url["tls"] else null
		if _client.connect_to_host(url["host"], url["port"], tls) != OK or not _wait(deadline, [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING], HTTPClient.STATUS_CONNECTED):
			return _offline()
	var headers := ["Content-Type: application/json", "Authorization: " + Account.token]
	if _client.request(HTTPClient.METHOD_POST, url["path"], headers, JSON.stringify(body)) != OK:
		return _offline()
	# Com corpo a resposta chega em BODY; sem corpo, a conexão volta a CONNECTED.
	_wait(deadline, [HTTPClient.STATUS_REQUESTING], HTTPClient.STATUS_BODY)
	if not _client.get_status() in [HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED]:
		return _offline()
	var code := _client.get_response_code()
	var text := PackedByteArray()
	while _client.get_status() == HTTPClient.STATUS_BODY:
		if Time.get_ticks_msec() > deadline:
			return _offline()
		_client.poll()
		var chunk := _client.read_response_body_chunk()
		if chunk.is_empty():
			OS.delay_msec(5)
		else:
			text.append_array(chunk)
	if code != 200:
		return {}
	var reply: Variant = JSON.parse_string(text.get_string_from_utf8())
	if not reply is Dictionary or not reply.get("wdl") is Array or reply["wdl"].size() != 3:
		return {}
	return {
		"best": str(reply.get("best", "(none)")),
		"mate": int(reply.get("mate", 0)),
		"wdl": [int(reply["wdl"][0]), int(reply["wdl"][1]), int(reply["wdl"][2])],
		"cp": 0,
	}


func _wait(deadline: int, passing: Array, target: int) -> bool:
	while _client.get_status() in passing:
		if Time.get_ticks_msec() > deadline:
			return false
		_client.poll()
		OS.delay_msec(5)
	return _client.get_status() == target


func _offline() -> Dictionary:
	_down_until = Time.get_ticks_msec() + RETRY_MS
	_client = null
	return {}


## `{"tls", "host", "port", "path"}` de um endereço `http(s)://host[:porta]/caminho`.
static func parse_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var authority := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var host := authority
	var port := 443 if tls else 80
	var colon := authority.rfind(":")
	if colon >= 0:
		host = authority.substr(0, colon)
		port = int(authority.substr(colon + 1))
	return {"tls": tls, "host": host, "port": port, "path": path}
