class_name ChatPanel
extends Control

## A conversa da partida: a gaveta do balão da barra.
##
## Entra pela direita, como a gaveta de regras, e deixa a mesa à vista atrás dela.
## Em cima ficam as reações e as frases prontas, que são o que se usa no meio de
## uma jogada; embaixo delas, o campo de texto; e por último o histórico, da mais
## nova para a mais antiga.
##
## O campo mora **em cima**, e não no rodapé como nos aplicativos de mensagem: o
## teclado do celular sobe de baixo e cobriria um campo no rodapé. Em cima ele não
## cobre nada, e a gaveta não precisa medir o teclado de cada aparelho.
##
## Mandar fecha a gaveta. Isto é uma reação no meio de uma partida, não uma
## conversa: quem reagiu quer voltar à mesa, e a própria mensagem aparece no aviso
## embaixo da barra (ver `ChatButton`).
##
## Quem assiste fala também, como plateia: o nome dele sai com "(plateia)", para
## ninguém confundir quem torce com quem joga.

signal closed

const SLIDE := 0.22
const MAX_WIDTH := 340.0
## Deitada a tela é baixa e larga: mais largura põe as reações numa fileira só, e
## a altura que sobra vai para o histórico.
const MAX_WIDTH_LANDSCAPE := 460.0
const WIDTH_RATIO := 0.86
const EMOTE_SIZE := 40.0
const EMOTE_FONT := 24

var _slider: Control = null
var _rows: VBoxContainer = null
var _input: LineEdit = null
## O que fica desligado durante a espera entre duas mensagens.
var _senders: Array[BaseButton] = []
var _ready_to_send := true


static func open(host: Node) -> ChatPanel:
	var panel := ChatPanel.new()
	host.add_child(panel)
	return panel


## Quem disse: "Você", o nome que o assento deu, "Jogador N" ou alguém da plateia.
static func speaker(entry: Dictionary) -> String:
	if entry.get("mine", false):
		return "Você"
	var seat := int(entry["seat"])
	if seat == ChatLog.AUDIENCE:
		var watcher := str(entry.get("name", ""))
		return "Plateia" if watcher.is_empty() else "%s (plateia)" % watcher
	var known := Net.name_of(seat)
	return known if not known.is_empty() else "Jogador %d" % (seat + 1)


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	z_index = 90
	add_to_group(&"back_layer")
	var screen := get_viewport_rect().size
	var width := minf(MAX_WIDTH_LANDSCAPE if screen.x > screen.y else MAX_WIDTH, screen.x * WIDTH_RATIO)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.color = Color(AppTheme.SCRIM, 0.35)
	# Tocar fora fecha ao soltar: arrastar pelo fundo não fecha a conversa.
	var scrim_press := Tap.Press.new()
	scrim.gui_input.connect(func(event: InputEvent) -> void:
		if scrim_press.feed(event):
			dismiss()
	)
	add_child(scrim)

	# Quem anda é o suporte de tela cheia, e não o painel ancorado: escrever
	# `position` num `Control` ancorado reescreve os offsets (ver `FriendsDrawer`).
	_slider = Control.new()
	_slider.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_slider.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_slider)

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -width
	var style := AppTheme.box(AppTheme.SURFACE, 0)
	style.border_width_left = 2
	style.border_color = AppTheme.LINE_SOFT
	style.content_margin_left = AppTheme.SPACE_L
	style.content_margin_right = AppTheme.SPACE_L
	style.content_margin_top = AppTheme.SPACE_M
	style.content_margin_bottom = AppTheme.SPACE_M
	panel.add_theme_stylebox_override("panel", style)
	_slider.add_child(panel)

	var safe := SafeAreaMargin.new()
	panel.add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_M)
	safe.add_child(column)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"SectionHeader"
	title.text = "Conversa"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := IconButton.new()
	close_button.kind = IconButton.Kind.CLOSE
	close_button.pressed.connect(dismiss)
	header.add_child(close_button)
	column.add_child(header)

	column.add_child(_emotes(8 if screen.x > screen.y else 4))
	column.add_child(_phrases())
	column.add_child(_text_row())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", AppTheme.SPACE_S)
	scroll.add_child(_rows)
	for entry: Dictionary in Net.chat.entries:
		_add_row(entry)
	Net.chat_received.connect(_add_row)

	_refresh_senders()
	_slider.position.x = width
	modulate.a = 0.0
	var slide := create_tween().set_parallel()
	slide.tween_property(self, "modulate:a", 1.0, SLIDE * 0.6)
	slide.tween_property(_slider, "position:x", 0.0, SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A espera acaba sozinha, e a conexão cai e volta sem avisar a gaveta: olhar a
## cada quadro é mais curto que ligar dois sinais e um temporizador.
func _process(_delta: float) -> void:
	_refresh_senders()


func _refresh_senders() -> void:
	var can := Net.connected and Net.chat.can_send(Time.get_ticks_msec())
	if can == _ready_to_send:
		return
	_ready_to_send = can
	for button in _senders:
		button.disabled = not can


## Grade e não fluxo: o fluxo deixava sete numa linha e uma sozinha na outra.
func _emotes(columns: int) -> Control:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", AppTheme.SPACE_XS)
	grid.add_theme_constant_override("v_separation", AppTheme.SPACE_XS)
	for index in ChatLog.EMOTES.size():
		var button := Button.new()
		button.text = ChatLog.EMOTES[index]
		# O quadrado sem folga dos botões da barra: com a folga do botão comum,
		# as oito não cabem numa fileira nem na gaveta deitada.
		MatchBar.frame_button(button)
		button.focus_mode = FOCUS_NONE
		button.custom_minimum_size = Vector2(EMOTE_SIZE, EMOTE_SIZE)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", EMOTE_FONT)
		button.pressed.connect(_send.bind(Net.send_emote.bind(index)))
		_senders.append(button)
		grid.add_child(button)
	return grid


func _phrases() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", AppTheme.SPACE_XS)
	flow.add_theme_constant_override("v_separation", AppTheme.SPACE_XS)
	for index in ChatLog.PHRASES.size():
		var button := Button.new()
		button.text = ChatLog.PHRASES[index]
		button.theme_type_variation = &"GhostButton"
		button.focus_mode = FOCUS_NONE
		button.custom_minimum_size.y = 36
		button.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
		button.pressed.connect(_send.bind(Net.send_phrase.bind(index)))
		_senders.append(button)
		flow.add_child(button)
	return flow


func _text_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", AppTheme.SPACE_S)
	_input = LineEdit.new()
	_input.max_length = ChatLog.TEXT_LIMIT
	_input.placeholder_text = "Mensagem"
	_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	_input.text_submitted.connect(func(_text: String) -> void: _send_text())
	row.add_child(_input)
	var send := Button.new()
	send.text = "Enviar"
	send.theme_type_variation = &"PrimaryButton"
	send.focus_mode = FOCUS_NONE
	send.custom_minimum_size = Vector2(0, 44)
	send.pressed.connect(_send_text)
	_senders.append(send)
	row.add_child(send)
	return row


func _send_text() -> void:
	_send(Net.send_text.bind(_input.text))


## Fecha só quando a mensagem saiu: na espera ou com o campo vazio, a gaveta fica
## onde está e o texto digitado não se perde.
func _send(say: Callable) -> void:
	if say.call():
		dismiss()


## Uma linha por mensagem: quem disse, e o que disse. `Label` puro, e nunca
## `RichTextLabel`: o texto vem de outro aparelho, e um `[url]` ou um `[img]`
## dentro dele não pode virar marcação.
func _add_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", AppTheme.SPACE_S)
	var who := Label.new()
	who.text = speaker(entry)
	who.add_theme_font_override("font", AppTheme.font(700))
	who.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	who.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	row.add_child(who)
	var said := Label.new()
	said.text = str(entry["text"])
	said.size_flags_horizontal = SIZE_EXPAND_FILL
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if int(entry["kind"]) == ChatLog.Kind.EMOTE:
		said.add_theme_font_size_override("font_size", EMOTE_FONT)
	row.add_child(said)
	_rows.add_child(row)
	# A mais nova em cima, colada no campo de onde as mensagens saem.
	_rows.move_child(row, 0)


func dismiss() -> void:
	if is_queued_for_deletion():
		return
	remove_from_group(&"back_layer")
	closed.emit()
	queue_free()
