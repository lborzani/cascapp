extends SceneTree

## Compara duas imagens pixel a pixel.
##
##   godot --headless --path . --script res://tests/image_diff.gd -- a.png b.png [x y w h]
##
## Existe para o redesenho: tudo o que é protegido (peças, cartas, tabuleiro de
## Metrópole) é renderizado antes e depois de cada etapa, e a resposta aceitável
## é uma só — zero pixels diferentes. Com a região opcional, compara só aquele
## retângulo, que é o que permite conferir o tabuleiro 3D sem os painéis em volta.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 and args.size() != 6:
		printerr("uso: -- a.png b.png [x y w h]")
		quit(2)
		return
	var first := Image.load_from_file(_path(args[0]))
	var second := Image.load_from_file(_path(args[1]))
	if first == null or second == null:
		printerr("não consegui abrir as duas imagens")
		quit(2)
		return
	if first.get_size() != second.get_size():
		printerr("tamanhos diferentes: %s e %s" % [first.get_size(), second.get_size()])
		quit(1)
		return
	var area := Rect2i(Vector2i.ZERO, first.get_size())
	if args.size() == 6:
		area = Rect2i(int(args[2]), int(args[3]), int(args[4]), int(args[5]))
	var differing := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				differing += 1
	if differing == 0:
		print("iguais (%dx%d em %s)" % [area.size.x, area.size.y, area.position])
		quit(0)
	else:
		printerr("diferentes: %d pixels" % differing)
		quit(1)


static func _path(raw: String) -> String:
	if raw.begins_with("user://") or raw.begins_with("res://"):
		return ProjectSettings.globalize_path(raw)
	return raw
