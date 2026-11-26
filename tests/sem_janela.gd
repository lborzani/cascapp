extends SceneTree

## Roda uma cena de teste (folhas de print, probes com janela) sem roubar o foco
## da área de trabalho, no Linux e no Windows.
##
##   godot --headless --path . --script res://tests/sem_janela.gd -- res://tests/screen_sheet.tscn
##   SHOT=34c godot --headless --path . --script res://tests/sem_janela.gd -- res://tests/screen_sheet.tscn
##
## O Godot 4.7 não desenha sem janela (`--headless` só tem o desenho `dummy`, e o
## print sai preto). O que dá é a janela nascer sem foco: `no_focus` precisa
## valer **na criação** dela, então entra por um `override.cfg` que só existe
## enquanto a cena roda. No niri a janela nem aparece, e o print sai igual.
##
## Tudo depois do `--` vai para o Godot filho, e as variáveis de ambiente (SHOT)
## também. A saída do filho sai aqui no fim, e o código de saída é o dele.

const OVERRIDE := "res://override.cfg"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Uso: godot --headless --path . --script res://tests/sem_janela.gd -- <cena ou argumentos>")
		quit(2)
		return
	var path := ProjectSettings.globalize_path(OVERRIDE)
	# Um override.cfg que não é nosso fica: apagar seria mexer no projeto de alguém.
	if FileAccess.file_exists(path):
		printerr("Já existe um %s; apague antes (sobra de uma rodada que caiu?)." % path)
		quit(1)
		return
	var config := ConfigFile.new()
	config.set_value("display", "window/size/no_focus", true)
	config.save(path)
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]) + PackedStringArray(args), output, true)
	DirAccess.remove_absolute(path)
	printraw("".join(output))
	quit(code)
