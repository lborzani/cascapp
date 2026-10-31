extends Node

## Carrega a versão baixada por OTA (`user://ota/<versão>.pck`) por cima do que
## veio no APK, antes de qualquer outro script do jogo.
##
## Precisa ser o **primeiro** autoload, e por isso não pode citar nenhum outro
## script: o Godot carrega os autoloads em ordem, e um script carregado antes do
## pacote fica em cache na versão do APK — o pacote o substituiria no disco e o
## jogo continuaria rodando o velho. Pelo mesmo motivo este arquivo nunca se
## atualiza por OTA: quando o pacote chega, ele já está rodando.
##
## Rollback: antes de carregar, grava em `BOOTING` qual versão está tentando. O
## menu apaga a marca ao abrir (`confirm`). Se a marca ainda estiver lá na
## abertura seguinte, aquele pacote não chegou ao menu; ele é apagado e o app abre
## a versão do APK, que vai oferecer a atualização pelo APK.

const DIR := "user://ota/"
const BOOTING := "user://ota/booting"
## A última versão cujo pacote não abriu. Sem isto, a tela de atualizar baixaria
## o mesmo pacote de novo, e o app cairia no mesmo rollback a cada abertura.
const FAILED := "user://ota/failed"
## O mesmo carimbo que `AppVersion` lê. Lido aqui antes do pacote, é a versão do
## APK; depois, é a do pacote.
const STAMP := "res://version.gen.txt"

## A versão do APK instalado, lida antes de o pacote entrar.
var apk_version := ""
## A versão do pacote carregado, ou vazio quando o app roda só com o APK.
var loaded := ""
## A versão do último pacote que não abriu, ou vazio (`FAILED`).
var failed := ""


func _init() -> void:
	apk_version = _stamped()
	if not DirAccess.dir_exists_absolute(DIR):
		return
	if FileAccess.file_exists(FAILED):
		failed = FileAccess.get_file_as_string(FAILED)
	var booting := FileAccess.get_file_as_string(BOOTING) if FileAccess.file_exists(BOOTING) else ""
	var best := ""
	for file in DirAccess.get_files_at(DIR):
		if file.get_extension() != "pck":
			continue
		var version := file.get_basename()
		if best.is_empty() or _compare(version, best) > 0:
			best = version
	# Só o mais novo serve. Os outros são versões já superadas, ou o pacote que
	# falhou, ou um pacote que o APK instalado por cima já alcançou.
	for file in DirAccess.get_files_at(DIR):
		var version := file.get_basename()
		if file.get_extension() == "pck" and version != best:
			DirAccess.remove_absolute(DIR + file)
	if best.is_empty():
		return
	if _compare(best, apk_version) <= 0:
		_drop(best)
		return
	if best == booting:
		_fail(best)
		return

	_write(BOOTING, best)
	if ProjectSettings.load_resource_pack(DIR + best + ".pck"):
		loaded = best
	else:
		_fail(best)


## O app chegou ao menu com o pacote: ele não precisa mais de rollback.
func confirm() -> void:
	if FileAccess.file_exists(BOOTING):
		DirAccess.remove_absolute(BOOTING)


func _drop(version: String) -> void:
	DirAccess.remove_absolute(DIR + version + ".pck")
	confirm()


func _fail(version: String) -> void:
	_drop(version)
	failed = version
	_write(FAILED, version)


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _stamped() -> String:
	if FileAccess.file_exists(STAMP):
		var stamped := FileAccess.get_file_as_string(STAMP).strip_edges()
		if not stamped.is_empty():
			return stamped
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Cópia de `AppVersion.compare`, de propósito: citar `AppVersion` daqui o
## carregaria antes do pacote (ver o topo).
static func _compare(a: String, b: String) -> int:
	var left := a.split(".")
	var right := b.split(".")
	for index in maxi(left.size(), right.size()):
		var x := left[index].to_int() if index < left.size() else 0
		var y := right[index].to_int() if index < right.size() else 0
		if x != y:
			return x - y
	return 0
