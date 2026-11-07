extends RefCounted

## Palco de tamanho fixo para as folhas de print.
##
## As folhas fotografavam a janela raiz, e o tamanho da janela é do gerenciador
## de janelas, não do Godot: num gerenciador lado a lado (niri, Hyprland, i3) o
## `--resolution` e o `window_set_size` são ignorados, e os prints saíam
## cortados, espremidos ou pretos — sem erro nenhum. Um `SubViewport` tem o
## tamanho que se pede em qualquer máquina.
##
## O `size_2d_override` faz o papel do `canvas_items` + `expand` do projeto: a
## base (432x768 em pé, 768x432 deitado) é esticada até caber e o lado que sobra
## cresce, como num celular de proporção diferente da base.

const PORTRAIT_BASE := Vector2i(432, 768)
const LANDSCAPE_BASE := Vector2i(768, 432)


static func make(parent: Node, physical: Vector2i) -> SubViewport:
	# Com vsync, uma janela coberta ou noutra área de trabalho recebe um quadro a
	# cada vez que o compositor lembra dela — no Wayland, ~1 por segundo, e a folha
	# inteira levava quinze minutos e parecia travada.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# E sem vsync nenhum, o oposto: centenas de quadros por segundo, e as folhas
	# contam quadros para esperar o fade de entrada — a foto sairia no meio dele.
	Engine.max_fps = 60
	var stage := SubViewport.new()
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.size_2d_override_stretch = true
	fit(stage, physical)
	parent.add_child(stage)
	return stage


## Muda o tamanho do palco. Deitado ou em pé sai da proporção pedida.
static func fit(stage: SubViewport, physical: Vector2i) -> void:
	var base := LANDSCAPE_BASE if physical.x > physical.y else PORTRAIT_BASE
	var scale := minf(float(physical.x) / base.x, float(physical.y) / base.y)
	stage.size = physical
	stage.size_2d_override = Vector2i((Vector2(physical) / scale).round())


static func save(stage: SubViewport, path: String) -> void:
	stage.get_texture().get_image().save_png(path)
