class_name BottomSheet
extends Control

## Uma folha que sobe de baixo por cima da tela, o padrão de camada do app.
##
## O fundo escurece (`AppTheme.SCRIM`), o painel tem os cantos de cima bem
## redondos e sobe animado, e tocar fora fecha, como toda folha do Android. Quem
## usa põe o conteúdo em [member body] antes de pôr a folha na árvore:
##
##   var sheet := BottomSheet.new()
##   sheet.body.add_child(meu_conteudo)
##   sheet.closed.connect(...)
##   add_child(sheet)
##
## [method close] anima a descida e libera a folha. O voltar do sistema é de
## quem abriu: ele chama [method close].
##
## A `GameSheet` é a folha original e segue com o próprio código (é reaberta
## várias vezes, em vez de criada a cada uso); os números saem daqui.

signal closed

## Canto de cima da folha: bem redondo, para ela ler como camada e não como tela.
const RADIUS := 32
const SLIDE := 0.26

## Quanto da altura da tela fica à vista em cima, de 0 a 1. Negativo: a folha
## tem a altura do conteúdo, ancorada embaixo.
var top := 0.16
## Onde vai o conteúdo.
var body := VBoxContainer.new()

var _slider: Control = null
var _scrim_press := Tap.Press.new()
var _closing := false


func _init() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	body.add_theme_constant_override("separation", AppTheme.SPACE_M)


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.color = AppTheme.SCRIM
	scrim.gui_input.connect(func(event: InputEvent) -> void:
		if _scrim_press.feed(event):
			close()
	)
	add_child(scrim)

	# Quem se move é este suporte de tela cheia, e não o painel: escrever
	# `position` num `Control` ancorado reescreve os offsets dele (ver o
	# `_init` da `GameSheet`, que já caiu nisso).
	_slider = Control.new()
	_slider.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_slider.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_slider)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	if top >= 0.0:
		panel.anchor_top = top
	else:
		panel.anchor_top = 1.0
		panel.grow_vertical = GROW_DIRECTION_BEGIN
	var style := AppTheme.box(AppTheme.SURFACE, 0)
	style.corner_radius_top_left = RADIUS
	style.corner_radius_top_right = RADIUS
	style.content_margin_left = AppTheme.SCREEN_PAD
	style.content_margin_right = AppTheme.SCREEN_PAD
	style.content_margin_top = AppTheme.SPACE_M
	style.content_margin_bottom = AppTheme.SPACE_XL
	panel.add_theme_stylebox_override("panel", style)
	_slider.add_child(panel)
	panel.add_child(body)

	modulate.a = 0.0
	_slider.position.y = 40.0
	var rise := create_tween().set_parallel()
	rise.tween_property(self, "modulate:a", 1.0, SLIDE * 0.6)
	rise.tween_property(_slider, "position:y", 0.0, SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Desce, avisa [signal closed] e sai da árvore. Chamar de novo não faz nada.
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	if not is_inside_tree():
		queue_free()
		return
	var fall := create_tween().set_parallel()
	fall.tween_property(self, "modulate:a", 0.0, SLIDE * 0.6)
	fall.tween_property(_slider, "position:y", 40.0, SLIDE * 0.6)
	fall.chain().tween_callback(queue_free)
