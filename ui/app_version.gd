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
