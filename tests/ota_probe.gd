extends Node

## Teste do `Patcher`, com um pacote de verdade carregado no boot.
##
##   godot --headless --path . res://tests/ota_probe.tscn
##
## O `Patcher` só age na abertura do app, então o teste abre o projeto mais de
## uma vez: esta execução monta os pacotes em `user://ota/` e chama a si mesma
## em processos novos, cada um conferindo uma abertura.
##
## O pacote de teste tem o que um `.pck` exportado tem de delicado: o carimbo de
## versão e um `class_name` que só existe nele, com o cache de classes globais
## atualizado. Uma classe nova que não resolve é exatamente o tipo de patch que
## passa no CI e quebra no celular.

const DIR := "user://ota/"
const SRC := "user://ota_probe_src/"
const NEW_CLASS := "OtaProbeAddition"
const NEW_SCRIPT := "res://tests/ota_probe_addition.gd"

var _failures := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	match args[0] if not args.is_empty() else "":
		"patched":
			_check_patched()
		"rolled_back":
			_check_rolled_back()
		_:
			_run()
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	DirAccess.make_dir_recursive_absolute(SRC)
	_pack("9.99")
	_pack("0.1")
	# Primeira abertura: carrega o 9.99, apaga o 0.1, e o menu não abriu.
	_check(_open("patched") == 0, "abertura com o pacote")
	# Segunda: o 9.99 não confirmou, então sai e o app volta ao APK.
	_check(_open("rolled_back") == 0, "abertura depois do boot que falhou")
	_clean()
	print("ota_probe: %s" % ("FALHOU" if _failures > 0 else "ok"))


func _check_patched() -> void:
	_check(Patcher.loaded == "9.99", "carregou o 9.99 (veio %s)" % Patcher.loaded)
	_check(AppVersion.text() == "9.99", "carimbo do pacote (veio %s)" % AppVersion.text())
	_check(Patcher.apk_version == str(ProjectSettings.get_setting("application/config/version")),
		"versão do APK lida antes do pacote")
	_check(not FileAccess.file_exists(DIR + "0.1.pck"), "pacote velho apagado")
	_check(FileAccess.get_file_as_string(DIR + "booting") == "9.99", "marca de boot")
	# Compilado agora, depois do pacote: é o caminho de qualquer script novo dele.
	var script := GDScript.new()
	script.source_code = "static func value() -> int:\n\treturn %s.value()\n" % NEW_CLASS
	var compiled := script.reload() == OK
	_check(compiled, "class_name novo resolve")
	if compiled:
		_check(script.call("value") == 42, "class_name novo responde")


func _check_rolled_back() -> void:
	_check(Patcher.loaded.is_empty(), "nada carregado (veio %s)" % Patcher.loaded)
	_check(not FileAccess.file_exists(DIR + "9.99.pck"), "pacote que falhou apagado")
	_check(not FileAccess.file_exists(DIR + "booting"), "marca de boot limpa")
	_check(Patcher.failed == "9.99", "e lembra qual versão falhou")
	_check(AppVersion.text() != "9.99", "versão do APK de volta")


## Monta `user://ota/<version>.pck` com o carimbo, a classe nova e o cache de
## classes que a inclui — o mesmo trio de um export.
func _pack(version: String) -> void:
	_write(SRC + "version.gen.txt", version)
	_write(SRC + "addition.gd",
		"class_name %s\nextends RefCounted\n\nstatic func value() -> int:\n\treturn 42\n" % NEW_CLASS)
	var cache := ConfigFile.new()
	cache.load("res://.godot/global_script_class_cache.cfg")
	var list: Array = cache.get_value("", "list", [])
	list.append({
		"base": &"RefCounted", "class": StringName(NEW_CLASS), "icon": "", "is_abstract": false,
		"is_tool": false, "language": &"GDScript", "path": NEW_SCRIPT,
	})
	cache.set_value("", "list", list)
	cache.save(SRC + "classes.cfg")

	var packer := PCKPacker.new()
	packer.pck_start(DIR + version + ".pck")
	packer.add_file("res://version.gen.txt", SRC + "version.gen.txt")
	packer.add_file(NEW_SCRIPT, SRC + "addition.gd")
	packer.add_file("res://.godot/global_script_class_cache.cfg", SRC + "classes.cfg")
	packer.flush()


func _open(mode: String) -> int:
	var output := []
	var code := OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/ota_probe.tscn", "--", mode,
	], output, true)
	for line in output:
		print(line)
	return code


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	for dir in [DIR, SRC]:
		if DirAccess.dir_exists_absolute(dir):
			for file in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir + file)
			DirAccess.remove_absolute(dir)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FALHOU: %s" % what)
