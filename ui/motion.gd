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
## Quanto o botão afunda ao ser apertado, em pixels.
const PRESS_SINK := 4.0
## Folha, gaveta e diálogo entrando.
const ENTER_TIME := 0.28
## Troca de aba, véu, o que só aparece.
const FADE_TIME := 0.18
## Quanto a tela nova sobe ao entrar, em pixels da base.
const ENTER_RISE := 14.0
## O empurrão de quem acabou de ganhar a vez.
const NUDGE_TIME := 0.3
const NUDGE_SCALE := 1.05


## O botão afunda 4 px e encolhe ao ser apertado, e volta ao soltar.
##
## O afundar sai da própria escala, com o pivô abaixo do botão: encolher em
## direção a um ponto 100 px abaixo desce o centro 4 px. Mexer na posição
## brigaria com o container que posiciona o botão.
##
## Escala e não cor: a cor já muda pelo tema, e num celular o dedo cobre o botão
## — o que se vê é a borda dele recuando.
static func press(control: Control, down: bool) -> void:
	if not control.is_inside_tree():
		return
	if down:
		if not control.has_meta(&"press_pivot"):
			control.set_meta(&"press_pivot", control.pivot_offset)
		control.pivot_offset = Vector2(
			control.size.x * 0.5, control.size.y * 0.5 + PRESS_SINK / (1.0 - PRESS_SCALE)
		)
	var target := Vector2.ONE * (PRESS_SCALE if down else 1.0)
	var tween := control.create_tween()
	tween.tween_property(control, "scale", target, PRESS_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not down:
		# Devolve o pivô de quem tinha um (o "UNO!" balança em torno do centro).
		tween.tween_callback(func() -> void:
			if is_instance_valid(control) and control.has_meta(&"press_pivot"):
				control.pivot_offset = control.get_meta(&"press_pivot")
				control.remove_meta(&"press_pivot")
		)


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


## Cresce um pouco e volta: "agora é você". A troca de vez era só uma borda
## mudando de um cartão para o outro, e passava sem ninguém ver.
static func nudge(control: Control) -> void:
	if not control.is_inside_tree():
		return
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * NUDGE_SCALE, NUDGE_TIME * 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, NUDGE_TIME * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func fade_in(item: CanvasItem) -> Tween:
	item.modulate.a = 0.0
	var tween := item.create_tween()
	tween.tween_property(item, "modulate:a", 1.0, FADE_TIME)
	return tween
