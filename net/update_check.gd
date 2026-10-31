class_name UpdateCheck
extends RefCounted

## Existe versão nova do app para baixar? Existindo, ela é obrigatória.
##
## O app sai como APK na release do GitHub, instalado à mão — não há loja para
## avisar. Sem isto, quem instalou uma vez fica na mesma versão para sempre, e
## descobre que existe outra quando um amigo não consegue entrar na sala dele.
## Por isso a versão nova não é oferta: o menu a mostra em tela cheia
## (`UpdateGate`) até ela ser instalada.
##
## A pergunta vai para a API pública de releases, sem servidor próprio: a release
## é feita por tag (`tools/release.sh`), e é ela mesma que responde, com o
## changelog nas notas (`release.yml`). Sem conta e sem token a API aceita 60
## consultas por hora por IP — por isso no máximo uma a cada dez minutos.
##
## A lista, e não só a mais recente: quem pulou duas versões precisa ler o que as
## duas trazem, e uma chamada só responde as duas coisas.

const URL := "https://api.github.com/repos/lborzani/cascapp/releases?per_page=20"
## Só se abre link daqui. A resposta chega por HTTPS da API do GitHub, mas é
## dado de fora: o que vai para o `OS.shell_open` é conferido mesmo assim.
const DOWNLOADS := "https://github.com/lborzani/cascapp/releases/download/"
const INTERVAL := 10 * 60


## Já se passaram dez minutos desde a última resposta que chegou.
static func due(now: int) -> bool:
	return now - Prefs.update_checked_at() >= INTERVAL


## A versão a instalar, `{version, url, changes}` e às vezes `pck`, ou vazio.
##
## `changes` é `[{version, items}]` de cada release entre a instalada (fora) e a
## oferecida (dentro), a mais nova em cima, só as que têm novidades nas notas.
##
## `pck` é `{url, size, sha256}` do pacote OTA da versão, quando ele roda sobre o
## APK instalado (`apk`, de `Patcher.apk_version`): o nome do arquivo diz a base,
## o APK mais velho que sabe rodá-lo (`tools/ota_base.sh`). Sem `pck`, o caminho
## é o APK.
##
## Pura, e separada da requisição, para o teste não precisar de rede: recebe a
## lista da API já lida. A oferecida é a mais nova **com APK anexado**: a release
## nasce antes de a esteira subir o arquivo, e uma tela que obriga a baixar algo
## que ainda não existe trancaria o app à toa. Rascunho e pré-release não contam.
static func offer(releases: Array, installed: String, apk := installed) -> Dictionary:
	var best := {}
	var pck := {}
	for release in releases:
		if not release is Dictionary or release.get("draft", false) or release.get("prerelease", false):
			continue
		var version := str(release.get("tag_name", "")).trim_prefix("v")
		if version.is_empty() or AppVersion.compare(version, installed) <= 0:
			continue
		var url := _apk_url(release)
		if url.is_empty():
			continue
		if best.is_empty() or AppVersion.compare(version, best["version"]) > 0:
			best = {"version": version, "url": url}
			pck = _pck(release, version, apk)
	if best.is_empty():
		return {}
	if not pck.is_empty():
		best["pck"] = pck

	var changes := []
	for release in releases:
		if not release is Dictionary:
			continue
		var version := str(release.get("tag_name", "")).trim_prefix("v")
		if AppVersion.compare(version, installed) <= 0 or AppVersion.compare(version, best["version"]) > 0:
			continue
		var items := Changelog.items(str(release.get("body", "")))
		if not items.is_empty():
			changes.append({"version": version, "items": items})
	changes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return AppVersion.compare(a["version"], b["version"]) > 0
	)
	best["changes"] = changes
	return best


static func _apk_url(release: Dictionary) -> String:
	var assets = release.get("assets", [])
	if not assets is Array:
		return ""
	for asset in assets:
		if not asset is Dictionary or not str(asset.get("name", "")).ends_with(".apk"):
			continue
		var url := str(asset.get("browser_download_url", ""))
		if url.begins_with(DOWNLOADS):
			return url
	return ""


## `cascapp-<versão>-base<base>.pck`, quando a base não passa do APK instalado. O
## sha256 vem da própria API (`digest`); sem ele não há como conferir o que
## chegou, e o pacote não é oferecido.
static func _pck(release: Dictionary, version: String, apk: String) -> Dictionary:
	var assets = release.get("assets", [])
	if not assets is Array:
		return {}
	var prefix := "cascapp-%s-base" % version
	for asset in assets:
		if not asset is Dictionary:
			continue
		var name := str(asset.get("name", ""))
		if not name.begins_with(prefix) or not name.ends_with(".pck"):
			continue
		var base := name.trim_prefix(prefix).trim_suffix(".pck")
		var url := str(asset.get("browser_download_url", ""))
		var digest := str(asset.get("digest", ""))
		if base.is_empty() or AppVersion.compare(base, apk) > 0 or not url.begins_with(DOWNLOADS) \
				or not digest.begins_with("sha256:"):
			return {}
		return {"url": url, "size": int(asset.get("size", 0)), "sha256": digest.trim_prefix("sha256:")}
	return {}


## O pacote baixado em `path` é o que a release anunciou.
static func verify(path: String, pck: Dictionary) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var size := file.get_length() if file != null else -1
	if file != null:
		file.close()
	return size == int(pck.get("size", -2)) and FileAccess.get_sha256(path) == str(pck.get("sha256", ""))


## Busca as releases e chama `done` com a lista, ou com `null` quando a rede, a
## API ou a resposta falharem — diferente de lista vazia, que é "nenhuma". O
## `HTTPRequest` vive em `parent` e sai junto com a resposta.
static func fetch(parent: Node, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	parent.add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			var releases = null
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				releases = JSON.parse_string(body.get_string_from_utf8())
			done.call(releases if releases is Array else null)
	)
	if http.request(URL) != OK:
		http.queue_free()
		done.call(null)
