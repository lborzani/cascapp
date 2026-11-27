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
## Toda folha do app passa por aqui: as missões e o convite de proteger a conta
## usam direto; a `GameSheet` e a `RulesPage` herdam. A folha do jogo é reaberta
## várias vezes em vez de criada a cada uso: com [member keep], fechar só esconde,
## e [method present] mostra de novo.

signal closed

## Canto de cima da folha: bem redondo, para ela ler como camada e não como tela.
const RADIUS := 32
const SLIDE := 0.26
## Quanto a folha anda na subida e na descida.
const TRAVEL := 40.0

## Quanto da altura da tela fica à vista em cima, de 0 a 1. Negativo: a folha
## tem a altura do conteúdo, ancorada embaixo.
var top := 0.16
## Largura máxima, centrada; zero é a largura da tela. Para texto corrido, que
## deitado viraria uma linha que ninguém acompanha até o fim.
var max_width := 0.0
## Fechar esconde em vez de liberar; [method present] reabre. Começa escondida.
var keep := false:
	set(value):
		keep = value
		if keep:
			visible = false
## Onde vai o conteúdo.
var body := VBoxContainer.new()

var _slider: Control = null
var _panel: PanelContainer = null
var _scrim_press := Tap.Press.new()
var _closing := false
var _motion: Tween = null


## Montada no `_init`, e não no `_ready`: quem herda preenche [member body] no
## próprio `_init`, e quem testa mexe na folha antes de ela entrar na árvore.
func _init() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	body.add_theme_constant_override("separation", AppTheme.SPACE_M)

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(PRESET_FULL_RECT)
	scrim.color = AppTheme.SCRIM
	scrim.gui_input.connect(func(event: InputEvent) -> void:
		if _scrim_press.feed(event):
			close()
	)
	add_child(scrim)

	# Quem se move é este suporte de tela cheia, e não o painel: escrever
	# `position` num `Control` ancorado reescreve os offsets dele, e a folha
	# ficava presa no topo da tela.
	_slider = Control.new()
	_slider.set_anchors_preset(PRESET_FULL_RECT)
	_slider.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_slider)

	_panel = PanelContainer.new()
	var style := AppTheme.box(AppTheme.SURFACE, 0)
	style.corner_radius_top_left = RADIUS
	style.corner_radius_top_right = RADIUS
	style.content_margin_left = AppTheme.SCREEN_PAD
	style.content_margin_right = AppTheme.SCREEN_PAD
	style.content_margin_top = AppTheme.SPACE_M
	style.content_margin_bottom = AppTheme.SPACE_XL
	_panel.add_theme_stylebox_override("panel", style)
	_slider.add_child(_panel)
	_panel.add_child(body)


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_place()
	if not keep:
		_rise()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


## Aberta (e não descendo).
func is_open() -> bool:
	return visible and not _closing


## Mostra de novo a folha [member keep] fechada. Aberta, não faz nada.
func present() -> void:
	if is_open():
		return
	_closing = false
	visible = true
	_rise()


## Desce, avisa [signal closed] e sai da árvore — ou só some, com [member keep].
## Chamar de novo não faz nada.
func close() -> void:
	if not is_open():
		return
	_closing = true
	closed.emit()
	if not is_inside_tree():
		_finish()
		return
	_stop()
	_motion = create_tween().set_parallel()
	_motion.tween_property(self, "modulate:a", 0.0, SLIDE * 0.6)
	_motion.tween_property(_slider, "position:y", TRAVEL, SLIDE * 0.6)
	_motion.chain().tween_callback(_finish)


func _finish() -> void:
	if keep:
		visible = false
		_closing = false
	else:
		queue_free()


func _rise() -> void:
	if not is_inside_tree():
		return
	_stop()
	# Pelo caminho e não pelo nome: as sondas de `--script` não têm autoload.
	var sound := get_node_or_null(^"/root/Sound")
	if sound != null:
		sound.play(sound.Cue.SHEET)
	modulate.a = 0.0
	_slider.position.y = TRAVEL
	_motion = create_tween().set_parallel()
	_motion.tween_property(self, "modulate:a", 1.0, SLIDE * 0.6)
	_motion.tween_property(_slider, "position:y", 0.0, SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _stop() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()


## A largura (cheia, ou [member max_width] no centro) e a altura de [member top].
func _place() -> void:
	if _panel == null:
		return
	if max_width <= 0.0:
		_panel.anchor_left = 0.0
		_panel.anchor_right = 1.0
		_panel.offset_left = 0.0
		_panel.offset_right = 0.0
	else:
		var width := minf(size.x, max_width)
		_panel.anchor_left = 0.5
		_panel.anchor_right = 0.5
		_panel.offset_left = -width * 0.5
		_panel.offset_right = width * 0.5
	_panel.anchor_bottom = 1.0
	_panel.offset_bottom = 0.0
	if top >= 0.0:
		_panel.anchor_top = top
	else:
		_panel.anchor_top = 1.0
		_panel.grow_vertical = GROW_DIRECTION_BEGIN
	_panel.offset_top = 0.0
