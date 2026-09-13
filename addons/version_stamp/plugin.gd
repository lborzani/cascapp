@tool
extends EditorPlugin

## Liga o carimbo de versão. Só isso — a lógica mora em `export_plugin.gd`.

const StampExporter := preload("res://addons/version_stamp/export_plugin.gd")

var _exporter: EditorExportPlugin = null


func _enter_tree() -> void:
	_exporter = StampExporter.new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	if _exporter != null:
		remove_export_plugin(_exporter)
		_exporter = null
