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


## A própria mensagem também vira aviso: quem mandou fechou a gaveta ao mandar, e
## o aviso é a confirmação de que saiu. A dos outros só avisa com a conversa
## fechada; aberta, ela já está na lista.
func _on_chat(entry: Dictionary) -> void:
	var mine := int(entry["seat"]) == Net.local_seat and not Net.is_spectator
	if _is_open() and not mine:
		return
	if not mine:
		unread += 1
	if notice != null:
		notice.show_message(
			"%s: %s" % [ChatPanel.speaker(int(entry["seat"])), entry["text"]],
			Banner.Kind.INFO, false, true
		)


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
