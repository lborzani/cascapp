class_name AppVersion
extends RefCounted

## Que versão é este build.
##
## Num APK a resposta vem de `version.gen.txt`, carimbado durante a exportação
## pelo addon `version_stamp` a partir do `version/name` do preset — o mesmo
## número que o Android instala. Rodando pelo editor esse arquivo não existe, e
## aí vale `application/config/version` do `project.godot`.
##
## Ter os dois é o ponto: o rodapé nunca mente sobre um build, e continua dizendo
## alguma coisa útil durante o desenvolvimento.

const STAMP := "res://version.gen.txt"


static func text() -> String:
	return read(STAMP)


## Separado de `text()` só para o teste poder apontar para um arquivo próprio —
## escrever o carimbo de verdade dentro do projeto para testá-lo deixaria um
## arquivo que sobrevive ao teste e passa a mentir em toda execução no editor.
static func read(path: String) -> String:
	if FileAccess.file_exists(path):
		var stamped := FileAccess.get_file_as_string(path).strip_edges()
		if not stamped.is_empty():
			return stamped
	return str(ProjectSettings.get_setting("application/config/version", "?"))


## Ordena duas versões: negativo se `a` é mais velha, zero se iguais, positivo
## se mais nova.
##
## Por número, segmento a segmento, e não como texto: "1.10" vem depois de
## "1.9", e a comparação de string diria o contrário — o aviso de atualização
## mandaria quem está na 1.10 "atualizar" para a 1.9. O "v" da tag é aceito
## porque é assim que a release chega da API do GitHub. Segmento que falta vale
## zero: "1.2" e "1.2.0" são o mesmo build.
static func compare(a: String, b: String) -> int:
	var left := a.strip_edges().trim_prefix("v").split(".")
	var right := b.strip_edges().trim_prefix("v").split(".")
	for index in maxi(left.size(), right.size()):
		var x := left[index].to_int() if index < left.size() else 0
		var y := right[index].to_int() if index < right.size() else 0
		if x != y:
			return x - y
	return 0
