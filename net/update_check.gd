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
## por dia, e não uma por abertura do menu.

const URL := "https://api.github.com/repos/lborzani/cascapp/releases/latest"
## Só se abre link daqui. A resposta chega por HTTPS da API do GitHub, mas é
## dado de fora: o que vai para o `OS.shell_open` é conferido mesmo assim.
const DOWNLOADS := "https://github.com/lborzani/cascapp/releases/download/"
const INTERVAL := 24 * 60 * 60


## Já se passou um dia desde a última resposta que chegou.
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
