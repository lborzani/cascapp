@tool
extends EditorExportPlugin

## Escreve a versão do preset num arquivo dentro do build, para o rodapé do menu
## mostrar exatamente o que foi exportado.
##
## O problema que isso resolve: a versão existia em dois lugares — `version/name`
## no `export_presets.cfg`, que é o que o Android instala, e
## `application/config/version` no `project.godot`, que é o que o rodapé lia. Os
## dois **tinham de ser bumpados juntos**, à mão, e esquecer um deles produzia um
## APK que se instala como 1.6 e se apresenta como 1.5. Um número errado no
## rodapé é pior que nenhum: ele é justamente o que alguém copia para relatar um
## problema.
##
## Agora o preset é a fonte única do que sai num build. `project.godot` continua
## servindo para a execução no editor, onde não existe preset nenhum.
##
## `export_presets.cfg` não vai junto no APK (é arquivo de editor), então ler o
## preset em tempo de execução não é opção — o valor precisa ser carimbado aqui,
## no momento da exportação.

const STAMP := "res://version.gen.txt"
## Chave do nome da versão no preset Android. Outras plataformas não têm essa
## opção, e é por isso que ela é consultada antes de ser lida.
const OPTION := "version/name"


func _get_name() -> String:
	return "VersionStamp"


func _export_begin(
	_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int
) -> void:
	var version := _version()
	add_file(STAMP, version.to_utf8_buffer(), false)
	# Sai no log da exportação de propósito: é a única confirmação de que o número
	# que vai no rodapé é o que se pretendia, e ela chega antes de o build demorar
	# alguns minutos para descobrir que estava errado.
	print("VersionStamp: v%s" % version)


## A versão do preset, ou a do projeto quando o preset não tem essa opção. O
## `has()` vem antes do `get_option()` de propósito: pedir uma opção que a
## plataforma não declara vira erro no console a cada exportação.
func _version() -> String:
	var preset := get_export_preset()
	if preset != null and preset.has(OPTION):
		var declared := str(get_option(OPTION)).strip_edges()
		if not declared.is_empty():
			return declared
	return str(ProjectSettings.get_setting("application/config/version", ""))
