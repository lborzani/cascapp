class_name UpdateCheck
extends RefCounted

## Existe versão nova do app para baixar?
##
## O app sai como APK na release do GitHub, instalado à mão — não há loja para
## avisar. Sem isto, quem instalou uma vez fica na mesma versão para sempre, e
## descobre que existe outra quando um amigo não consegue entrar na sala dele.
##
## A pergunta vai para a API pública de releases, sem servidor próprio: a release
## é feita por tag (`tools/release.sh`), e é ela mesma que responde. Sem conta e
## sem token, a API aceita 60 consultas por hora por IP — por isso no máximo uma
## por hora, e não uma por abertura do menu.
##
## Era uma por dia, e isso escondia a release do mesmo dia: quem abriu o app
## logo depois de instalar a 1.23 ficou 24 horas sem ver a 1.24. Para quem não
## quer esperar nem a hora, a tela "Você" tem o botão de procurar na hora.

const URL := "https://api.github.com/repos/lborzani/cascapp/releases/latest"
## Só se abre link daqui. A resposta chega por HTTPS da API do GitHub, mas é
## dado de fora: o que vai para o `OS.shell_open` é conferido mesmo assim.
const DOWNLOADS := "https://github.com/lborzani/cascapp/releases/download/"
const INTERVAL := 60 * 60


## Já se passou uma hora desde a última resposta que chegou.
static func due(now: int) -> bool:
	return now - Prefs.update_checked_at() >= INTERVAL


## A versão a oferecer, `{version, url}`, ou vazio.
##
## Pura, e separada da requisição, para o teste não precisar de rede: recebe o
## JSON da release já lido. Vazio quando a release não é mais nova que a
## instalada, quando o jogador já disse "agora não" a ela (ou a uma mais nova),
## ou quando ela não tem APK anexado — um aviso cujo "Baixar" abre outra coisa é
## pior que nenhum.
static func offer(release: Dictionary, installed: String, skipped: String) -> Dictionary:
	var version := str(release.get("tag_name", "")).trim_prefix("v")
	if version.is_empty() or AppVersion.compare(version, installed) <= 0:
		return {}
	if not skipped.is_empty() and AppVersion.compare(version, skipped) <= 0:
		return {}
	var assets = release.get("assets", [])
	if not assets is Array:
		return {}
	for asset in assets:
		if not asset is Dictionary or not str(asset.get("name", "")).ends_with(".apk"):
			continue
		var url := str(asset.get("browser_download_url", ""))
		if url.begins_with(DOWNLOADS):
			return {"version": version, "url": url}
	return {}


## Busca a release mais recente e chama `done` com o JSON dela, ou com `{}`
## quando a rede, a API ou a resposta falharem. O `HTTPRequest` vive em
## `parent` e sai junto com a resposta.
static func fetch(parent: Node, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	parent.add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			var release = null
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				release = JSON.parse_string(body.get_string_from_utf8())
			done.call(release if release is Dictionary else {})
	)
	if http.request(URL) != OK:
		http.queue_free()
		done.call({})
