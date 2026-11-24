class_name ChatButton
extends Button

## O balão da barra de partida: abre a conversa (`ChatPanel`), conta o que
## chegou com ela fechada e mostra por uns segundos, no aviso da barra, quem disse
## o quê.
##
## Só existe em partida pela rede (`MatchBar.bind`). No mesmo aparelho e contra o
## bot não há com quem falar.
##
## O aviso é o mesmo da partida (`MatchBar.notice`), mas de passagem: um "Boa!"
## no meio de "Sem conexão…" some e deixa o aviso da partida de volta.
##
## A reação (emote) não vai para o aviso: ela sobe da etiqueta de quem a mandou,
## que é onde o olho já procura "quem". A tela diz onde fica cada um pelo
## `chat_spot(seat) -> Rect2` (global; vazio quando não sabe), e sem ele a reação
## cai no aviso como o resto.
##
## A da plateia não tem etiqueta: sai num balão dentro da barra, com o rabicho
## apontando para este botão. A barra fica fora da mesa, então a torcida nunca
## cobre a casa onde se vai jogar.

const POP_FONT := 40
const POP_RISE := 56.0
const POP_TIME := 1.4
const CHEER_TAIL := 7.0
const CHEER_HOLD := 1.8
const CHEER_FADE := 0.3

## O aviso da barra. A barra o entrega ao criar o botão.
var notice: Banner = null

## Mensagens que chegaram com a conversa fechada. Zera ao abrir.
var unread := 0:
	set(value):
		unread = value
		queue_redraw()

var _panel: ChatPanel = null


func _init() -> void:
	tooltip_text = "Conversa"
	focus_mode = FOCUS_NONE
	custom_minimum_size = Vector2(44, 44)
	size_flags_vertical = SIZE_SHRINK_CENTER
	MatchBar.frame_button(self)
	pressed.connect(open)


func _ready() -> void:
	Net.chat_received.connect(_on_chat)


func open() -> ChatPanel:
	if _is_open():
		return _panel
	unread = 0
	_panel = ChatPanel.open(RulesPage.host_of(self))
	return _panel


## A própria mensagem também aparece: quem mandou fechou a gaveta ao mandar, e ver
## a mensagem é a confirmação de que saiu. A dos outros só vai ao aviso com a
## conversa fechada; aberta, ela já está na lista. A reação sobe da etiqueta
## sempre, porque é a mesa que reage, e não a lista.
func _on_chat(entry: Dictionary) -> void:
	var seat := int(entry["seat"])
	var mine: bool = entry.get("mine", false)
	if not mine and not _is_open():
		unread += 1
	if int(entry["kind"]) == ChatLog.Kind.EMOTE:
		if seat == ChatLog.AUDIENCE:
			_cheer(entry)
			return
		if _pop(seat, str(entry["text"])):
			return
	if _is_open() and not mine:
		return
	if notice != null:
		notice.show_message(
			"%s: %s" % [ChatPanel.speaker(entry), entry["text"]], Banner.Kind.INFO, false, true
		)


## O retângulo global de uma etiqueta, ou vazio se ela não está na tela. As telas
## respondem o `chat_spot` com isto.
static func spot_of(control: Control) -> Rect2:
	if control == null or not control.is_visible_in_tree():
		return Rect2()
	return control.get_global_rect()


## A reação cresce sobre a bolacha da etiqueta (o quadrado da esquerda, onde mora
## a foto ou a peça), sobe e some. Falso quando a tela não sabe onde fica o assento.
func _pop(seat: int, emote: String) -> bool:
	var host := RulesPage.host_of(self) as Control
	if host == null or not host.has_method(&"chat_spot"):
		return false
	var spot: Rect2 = host.call(&"chat_spot", seat)
	if not spot.has_area():
		return false
	var label := Label.new()
	label.text = emote
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", POP_FONT)
	# Acima da mesa e dos cartões, abaixo das gavetas (90).
	label.z_index = 85
	host.add_child(label)
	label.reset_size()
	var center := Vector2(spot.position.x + minf(spot.size.x, spot.size.y) * 0.5, spot.get_center().y)
	label.global_position = center - label.size * 0.5
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * 0.4
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2.ONE * 1.15, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.1)
	tween.tween_property(label, "position:y", label.position.y - POP_RISE, POP_TIME).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, POP_TIME * 0.5).set_delay(POP_TIME * 0.5)
	tween.tween_callback(label.queue_free)
	return true


## O balão da plateia: "Caio 😂", colado à esquerda deste botão e dentro da altura
## da barra. Passa por cima do título por uns segundos, nunca da mesa; o aviso
## não serve de limite, porque escondido ele não tem largura. Um `Label` com fundo (`normal`), e não
## um painel com um `Label` dentro: uma peça só para criar, animar e soltar.
func _cheer(entry: Dictionary) -> void:
	var host := RulesPage.host_of(self) as Control
	if host == null:
		return
	var who := "Você" if entry.get("mine", false) else str(entry.get("name", ""))
	var bubble := Label.new()
	bubble.text = "%s %s" % [who if not who.is_empty() else "Plateia", entry["text"]]
	bubble.mouse_filter = MOUSE_FILTER_IGNORE
	bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble.add_theme_font_override("font", AppTheme.font(700))
	bubble.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	var tall := size.y - 8.0
	var style := AppTheme.box(AppTheme.SURFACE_TOP, int(tall * 0.5), AppTheme.LINE_SOFT, 1)
	style.content_margin_left = tall * 0.4
	style.content_margin_right = tall * 0.4
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	bubble.add_theme_stylebox_override("normal", style)
	# Acima da mesa e dos cartões, abaixo das gavetas (90).
	bubble.z_index = 85
	host.add_child(bubble)
	bubble.custom_minimum_size.y = tall
	bubble.reset_size()

	var right := global_position.x - CHEER_TAIL
	# O corte só depois de medir, e só quando não cabe: ligado, a largura mínima do
	# `Label` vira zero, e na medida justa ele apara o emoji do fim.
	var room := right - AppTheme.SPACE_L
	if bubble.size.x > room:
		bubble.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bubble.size.x = room
	bubble.global_position = Vector2(right - bubble.size.x, global_position.y + (size.y - bubble.size.y) * 0.5)

	var tail := Polygon2D.new()
	tail.color = AppTheme.SURFACE_TOP
	var mid := bubble.size.y * 0.5
	tail.polygon = PackedVector2Array([
		Vector2(bubble.size.x - 1.0, mid - CHEER_TAIL), Vector2(bubble.size.x + CHEER_TAIL, mid),
		Vector2(bubble.size.x - 1.0, mid + CHEER_TAIL),
	])
	bubble.add_child(tail)

	bubble.pivot_offset = Vector2(bubble.size.x, mid)
	bubble.scale = Vector2.ONE * 0.4
	var tween := bubble.create_tween()
	tween.tween_property(bubble, "scale", Vector2.ONE * 1.08, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(bubble, "scale", Vector2.ONE, 0.1)
	tween.tween_interval(CHEER_HOLD)
	tween.tween_property(bubble, "modulate:a", 0.0, CHEER_FADE)
	tween.tween_callback(bubble.queue_free)


func _draw() -> void:
	var tint := AppTheme.TEXT_DIM
	var center := size * 0.5
	# Balão: o corpo e o rabicho embaixo à esquerda, com três pontos dentro.
	var body := Rect2(center + Vector2(-10.0, -8.0), Vector2(20.0, 14.0))
	draw_rect(body, tint, false, IconButton.STROKE)
	draw_polyline(PackedVector2Array([
		center + Vector2(-6.0, 6.0), center + Vector2(-8.0, 11.0), center + Vector2(-1.0, 6.0),
	]), tint, IconButton.STROKE, true)
	for dot in [-5.0, 0.0, 5.0]:
		draw_circle(center + Vector2(dot, -1.0), 1.5, tint)

	if unread > 0:
		var spot := Vector2(size.x - 7.0, 7.0)
		draw_circle(spot, 8.0, AppTheme.ACCENT)
		var label := str(unread) if unread < 10 else "9+"
		var font := AppTheme.font(800)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, spot + Vector2(-width * 0.5, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AppTheme.ACCENT_INK)


## Aberta e não fechando: a gaveta que acabou de mandar ainda existe até o fim do
## quadro, e nesse meio tempo um novo toque no balão tem de abrir outra.
func _is_open() -> bool:
	return is_instance_valid(_panel) and not _panel.is_queued_for_deletion()
