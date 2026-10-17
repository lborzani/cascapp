class_name Changelog
extends RefCounted

## O `CHANGELOG.md` da raiz, lido pelo app: uma seção `## 1.31` por versão, uma
## linha `- ` por novidade. Vai dentro do APK (`include_filter` do preset), então
## "Novidades" e o histórico funcionam sem rede.
##
## A mesma forma serve às notas da release do GitHub, que a esteira tira deste
## arquivo: a tela de atualizar lê as versões que ainda não estão no aparelho por
## lá, com o mesmo [method items].

const PATH := "res://CHANGELOG.md"


## `[{"version", "items"}]` de todas as seções, na ordem do arquivo (a mais nova
## em cima).
static func parse(text: String) -> Array:
	var sections := []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("## "):
			sections.append({"version": trimmed.trim_prefix("## ").strip_edges(), "items": PackedStringArray()})
		elif not sections.is_empty() and trimmed.begins_with("- "):
			sections[-1]["items"].append(trimmed.trim_prefix("- ").strip_edges())
	return sections


## As novidades de `version`, ou vazio quando o arquivo não tem a seção.
static func items_of(text: String, version: String) -> PackedStringArray:
	for section: Dictionary in parse(text):
		if AppVersion.compare(section["version"], version) == 0:
			return section["items"]
	return PackedStringArray()


## As linhas `- ` de um texto solto (as notas de uma release), até o `---` que
## separa a origem do build.
static func items(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed == "---":
			break
		if trimmed.begins_with("- "):
			found.append(trimmed.trim_prefix("- ").strip_edges())
	return found


## O arquivo que veio no APK; vazio fora dele (o filtro do preset esqueceu).
static func bundled() -> String:
	return FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else ""
