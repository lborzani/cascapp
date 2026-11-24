extends RefCounted

## O superusuário do PocketBase de teste, para os probes editarem as coleções
## como o painel admin (`/_/`). Lê `CASCAPP_PB_SUPERUSER=email:senha`; sem ele,
## `sign_in` devolve falso e o probe pula a parte do admin.

var token := ""
var _host: Node = null


func _init(host: Node) -> void:
	_host = host


func sign_in() -> bool:
	var login := OS.get_environment("CASCAPP_PB_SUPERUSER").split(":", true, 1)
	if login.size() < 2:
		return false
	var auth := await call_api(HTTPClient.METHOD_POST, "/api/collections/_superusers/auth-with-password", {"identity": login[0], "password": login[1]})
	token = str(auth["data"].get("token", "")) if auth["data"] is Dictionary else ""
	return not token.is_empty()


## Como `Account._call`, mas com o token do superusuário.
func call_api(method: int, path: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	_host.add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: " + token)
	http.request(Account.base_url() + path, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	var result: Array = await http.request_completed
	http.queue_free()
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	return {"code": result[1], "data": JSON.parse_string(text) if not text.is_empty() else null}


## O primeiro registro de `collection` com `field = value`, ou `{}`.
func find(collection: String, field: String, value: String) -> Dictionary:
	var filter := ("(%s='%s')" % [field, value]).uri_encode()
	var found := await call_api(HTTPClient.METHOD_GET, "/api/collections/%s/records?filter=%s" % [collection, filter], {})
	var items: Array = found["data"].get("items", []) if found["data"] is Dictionary else []
	return items[0] if not items.is_empty() else {}
