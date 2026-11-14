class_name Motion
extends RefCounted

## O movimento do app, num lugar só.
##
## Duração e curva são decisões de tema, como cor: escritas em cada tela, viram
## vinte números mágicos que ninguém consegue afinar juntos. Quem anima chama
## daqui, e mudar o ritmo do app é mudar este arquivo.
##
## Tudo aqui é desenho. Nenhuma função espera, bloqueia toque ou muda estado de
## jogo — quem precisa esperar o fim usa o `Tween` devolvido.

## Toque: o botão afunda.
const PRESS_TIME := 0.12
const PRESS_SCALE := 0.96
## Folha, gaveta e diálogo entrando.
const ENTER_TIME := 0.28
## Troca de aba, véu, o que só aparece.
const FADE_TIME := 0.18


## O botão encolhe ao ser apertado e volta ao soltar.
##
## Escala e não cor: a cor já muda pelo tema, e num celular o dedo cobre o botão
## — o que se vê é a borda dele recuando.
static func press(control: Control, down: bool) -> void:
	if not control.is_inside_tree():
		return
	control.pivot_offset = control.size * 0.5
	var target := Vector2.ONE * (PRESS_SCALE if down else 1.0)
	control.create_tween().tween_property(control, "scale", target, PRESS_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Surge crescendo um pouco além do tamanho e assenta: diálogo, selo, resultado.
static func pop(control: Control) -> Tween:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * 0.8
	control.modulate.a = 0.0
	var tween := control.create_tween().set_parallel()
	tween.tween_property(control, "scale", Vector2.ONE, ENTER_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, FADE_TIME)
	return tween


static func fade_in(item: CanvasItem) -> Tween:
	item.modulate.a = 0.0
	var tween := item.create_tween()
	tween.tween_property(item, "modulate:a", 1.0, FADE_TIME)
	return tween
