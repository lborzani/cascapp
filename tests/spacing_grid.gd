extends SceneTree

## Régua do espaçamento: todo respiro entre blocos é múltiplo de 4.
##
##   godot --headless --path . --script res://tests/spacing_grid.gd
##
## A grade de 4 (`AppTheme.SPACE_*`) existia, mas nada a cobrava, e os números
## soltos foram se acumulando — 6 aqui, 10 ali, 14 acolá. Cada um parece certo
## sozinho; juntos são as telas em que dois blocos vizinhos têm vãos diferentes
## sem motivo. A régua lê o código e as cenas e aponta arquivo e linha de cada
## número fora da grade.
##
## Cobre `separation` e `margin_*` de containers — o vão **entre** coisas — no
## `add_theme_constant_override`, no `theme_override_constants/` das cenas e no
## `set_constant` do tema. Não cobre o recheio dos botões (`content_margin_*`,
## que mede o botão, não o vão) nem o que é desenhado em `_draw`.
##
## ponytail: lê só número literal. Um vão vindo de constante própria
## (`const GUTTER := 10`) passa sem ser visto; cobrar isso pede avaliar o script.

const ROOTS := ["res://ui", "res://scenes"]
const GRID := 4
const NAMES := "separation|h_separation|v_separation|margin_left|margin_top|margin_right|margin_bottom"
const PATTERNS := [
	'add_theme_constant_override\\("(' + NAMES + ')",\\s*(-?\\d+)\\)',
	'theme_override_constants/(' + NAMES + ') = (-?\\d+)',
	'set_constant\\("(' + NAMES + ')",\\s*"\\w+",\\s*(-?\\d+)\\)',
]


func _initialize() -> void:
	var regexes: Array[RegEx] = []
	for pattern: String in PATTERNS:
		regexes.append(RegEx.create_from_string(pattern))
	var off := 0
	for root: String in ROOTS:
		for path in _files(root):
			off += _scan(path, regexes)
	if off == 0:
		print("OK — todo espaçamento na grade de %d." % GRID)
	else:
		printerr("%d espaçamento(s) fora da grade de %d." % [off, GRID])
	quit(1 if off > 0 else 0)


func _scan(path: String, regexes: Array[RegEx]) -> int:
	var off := 0
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		for regex in regexes:
			for found in regex.search_all(lines[i]):
				var value := int(found.get_string(2))
				if value % GRID != 0:
					print("  %s:%d  %s = %d" % [path.trim_prefix("res://"), i + 1, found.get_string(1), value])
					off += 1
	return off


func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(dir.path_join(file))
	return out
