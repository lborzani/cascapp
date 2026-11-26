class_name FriendChat
extends Control

## A conversa direta com um amigo: balões (os meus à direita), a fileira de
## emojis e o campo de texto. Os convites para partida ficam no mesmo fio; o
## recebido tem "Entrar" enquanto quem chamou está na sala esperando, e "A sala
## já fechou" depois (ver `_invite_state`).
##
## As mensagens moram no PocketBase (`Account.chat`, `pocketbase/pb_hooks/
## conversa.pb.js`), então o amigo offline lê depois. Aberta, a tela pergunta a
## cada [constant POLL_SECONDS]; ler marca as recebidas como lidas.
##
## O topo é o banner do amigo (capa, moldura, nome e status): tocar nele abre o
## perfil por cima.
##
## Por cima da gaveta: fechar devolve a gaveta.

signal closed
## Tocaram no banner: abrir o perfil deste amigo.
signal profile_requested(friend_id: String)

const POLL_SECONDS := 3.0

var friend_id := ""

var _bubbles: VBoxContainer = null
var _scroll: ScrollContainer = null
var _input: LineEdit = null
var _note: Label = null
## O que está desenhado. Começa diferente de qualquer fio, até o vazio, para a
## primeira resposta sempre desenhar.
var _shown: Array = [null]
## As mensagens da última consulta, para redesenhar quando um convite cai.
var _items: Array = []
var _sending := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)

	var safe := SafeAreaMargin.new()
	safe.follow_keyboard = true
	for side in ["left", "top", "right", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 16)
	safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	safe.add_child(column)

	var profile := Friends.profile_of(friend_id)
	var look := Cosmetics.clean(profile.get("look", {}))
	var banner := PanelContainer.new()
	banner.name = "Banner"
	banner.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SURFACE_HIGH, AppTheme.RADIUS))
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	ProfileCover.dress_card(banner, header, look, AppTheme.RADIUS)
	var coaster := Coaster.new()
	coaster.custom_minimum_size = Vector2(44, 44)
	coaster.size_flags_vertical = SIZE_SHRINK_CENTER
	coaster.mouse_filter = MOUSE_FILTER_IGNORE
	coaster.player_name = str(profile.get("name", ""))
	coaster.photo = Account.avatar_of(friend_id, str(profile.get("avatar", "")))
	coaster.frame = Cosmetics.frame_of(look)
	header.add_child(coaster)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 0)
	var title := _text(str(profile.get("name", "Conversa")), &"")
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_override("font", AppTheme.font(800))
	title.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	ProfileStyle.paint_name(title, look)
	words.add_child(title)
	var status: Variant = Friends.status_of(friend_id)
	var status_label := _text(Friends.status_text(status), &"Caption")
	if status != null:
		status_label.add_theme_color_override("font_color", AppTheme.SUCCESS)
	words.add_child(status_label)
	header.add_child(words)
	var close_button := IconButton.new()
	close_button.kind = IconButton.Kind.CLOSE
	close_button.size_flags_vertical = SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	header.add_child(close_button)
	# Tocar no banner (fora do fechar) abre o perfil. Ao soltar, como na gaveta.
	var press := Tap.Press.new()
	banner.gui_input.connect(func(event: InputEvent) -> void:
		if press.feed(event):
			profile_requested.emit(friend_id)
	)
	column.add_child(banner)

	_note = _text("", &"Caption")
	_note.visible = false
	column.add_child(_note)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_bubbles = VBoxContainer.new()
	_bubbles.size_flags_horizontal = SIZE_EXPAND_FILL
	_bubbles.add_theme_constant_override("separation", 8)
	_scroll.add_child(_bubbles)

	# Como no chat da partida (`ChatPanel._emotes`): quadrados sem folga numa
	# grade. Com a folga do botão comum, as oito não cabiam na largura do
	# celular, e a fileira esticava a tela inteira para os lados.
	var emotes := GridContainer.new()
	emotes.columns = ChatLog.EMOTES.size()
	emotes.add_theme_constant_override("h_separation", AppTheme.SPACE_XS)
	for index in ChatLog.EMOTES.size():
		var emote := Button.new()
		emote.text = ChatLog.EMOTES[index]
		MatchBar.frame_button(emote)
		emote.focus_mode = FOCUS_NONE
		emote.custom_minimum_size = Vector2(ChatPanel.EMOTE_SIZE, ChatPanel.EMOTE_SIZE)
		emote.size_flags_horizontal = SIZE_EXPAND_FILL
		emote.add_theme_font_size_override("font_size", ChatPanel.EMOTE_FONT)
		emote.set_meta(&"emote", index)
		emote.pressed.connect(func() -> void: send({"kind": "emote", "emote": index}))
		emotes.add_child(emote)
	column.add_child(emotes)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	_input = LineEdit.new()
	_input.placeholder_text = "Mensagem"
	_input.max_length = ChatLog.TEXT_LIMIT
	_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 48)
	_input.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	_input.text_submitted.connect(func(_text: String) -> void: _send_text())
	line.add_child(_input)
	var send_button := Button.new()
	send_button.text = "Enviar"
	send_button.theme_type_variation = &"PrimaryButton"
	# Sem foco: tocar em Enviar não tira o teclado do campo.
	send_button.focus_mode = FOCUS_NONE
	send_button.custom_minimum_size = Vector2(0, 48)
	send_button.pressed.connect(_send_text)
	line.add_child(send_button)
	column.add_child(line)

	if not Account.signed_in():
		_say("Sem conexão com a sua conta agora. A conversa aparece quando ela voltar.")
		return
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.timeout.connect(_load)
	add_child(timer)
	timer.start()
	# O `who` da gaveta diz quem está em qual sala: um convite pode cair entre
	# duas consultas da conversa.
	Friends.changed.connect(func() -> void: show_items(_items))
	_load()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


## Redesenha o fio, só quando ele mudou: a consulta de 3 em 3 segundos não pode
## piscar a tela nem tirar a rolagem de quem está lendo lá em cima. "Mudou"
## inclui um convite que deixou de valer (a sala fechou).
func show_items(items: Array) -> void:
	_items = items
	var ids := items.map(func(item: Dictionary) -> String: return "%s:%s" % [item.get("id", ""), _invite_state(item)])
	if ids == _shown:
		return
	_shown = ids
	for child in _bubbles.get_children():
		_bubbles.remove_child(child)
		child.queue_free()
	if items.is_empty():
		_bubbles.add_child(_text("Nenhuma mensagem ainda. Mande um oi ou um emoji.", &"Subtitle"))
	for item: Dictionary in items:
		_bubbles.add_child(_bubble(item))
	# Depois do layout: antes dele o fim da rolagem ainda é o do fio antigo.
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Manda e recarrega. Uma por vez: o botão apertado duas vezes não duplica.
func send(body: Dictionary) -> void:
	if _sending or not Account.signed_in():
		return
	_sending = true
	Sound.play(Sound.Cue.TAP)
	var reply := await Account.send_chat(friend_id, body)
	_sending = false
	if not is_inside_tree():
		return
	match int(reply["code"]):
		200:
			_say("")
			if body.get("kind") == "text":
				_input.clear()
			_load()
		429:
			_say("Calma: muitas mensagens seguidas. Espera um pouco.")
		404:
			_say("Vocês não são mais amigos.")
		_:
			_say("Não deu para mandar agora. Confira a internet.")


## "Bia: oi", "Bia: 😂", "Bia te chamou para Xadrez" — a mensagem numa linha,
## para o aviso e a notificação.
static func preview(item: Dictionary, sender: String) -> String:
	match str(item.get("kind", "")):
		"emote":
			var index := int(item.get("emote", -1))
			return "%s: %s" % [sender, ChatLog.EMOTES[index] if index >= 0 and index < ChatLog.EMOTES.size() else "?"]
		"invite":
			return "%s te chamou para %s" % [sender, Game.game_title(StringName(str(item.get("game", ""))))]
	return "%s: %s" % [sender, str(item.get("text", ""))]


## "open" (recebido, a sala ainda espera), "closed" (recebido, a sala fechou ou
## encheu) ou "" (não é convite recebido). Quem diz é `Friends.invite_live`, pelo
## que o relay conta de onde quem chamou está sentado: fechar a sala revoga o
## convite sem ninguém mexer na mensagem.
func _invite_state(item: Dictionary) -> String:
	if str(item.get("kind", "")) != "invite" or str(item.get("from", "")) == Account.user_id:
		return ""
	return "open" if Friends.invite_live(str(item.get("from", "")), str(item.get("room", ""))) else "closed"


func _load() -> void:
	var items: Variant = await Account.chat(friend_id)
	if not is_inside_tree():
		return
	if items is Array:
		Friends.mark_read(friend_id)
		show_items(items)
	elif _shown.is_empty():
		_say("Não deu para carregar a conversa agora.")


func _send_text() -> void:
	var text := ChatLog.clean(_input.text)
	if not text.is_empty():
		send({"kind": "text", "text": text})


func _bubble(item: Dictionary) -> Control:
	var mine := str(item.get("from", "")) == Account.user_id
	var row := HBoxContainer.new()
	row.set_meta(&"message", item)
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	var bubble := PanelContainer.new()
	var box := AppTheme.box(AppTheme.SURFACE_TOP if mine else AppTheme.SURFACE_HIGH, AppTheme.RADIUS_LARGE)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", box)
	bubble.size_flags_horizontal = SIZE_SHRINK_END if mine else SIZE_SHRINK_BEGIN
	row.add_child(bubble)
	var words := VBoxContainer.new()
	bubble.add_child(words)

	match str(item.get("kind", "")):
		"emote":
			var index := int(item.get("emote", -1))
			var emote := _text(ChatLog.EMOTES[index] if index >= 0 and index < ChatLog.EMOTES.size() else "?", &"")
			emote.add_theme_font_size_override("font_size", 34)
			words.add_child(emote)
		"invite":
			var game := StringName(str(item.get("game", "")))
			var what := "Você chamou para %s" % Game.game_title(game) if mine else "Te chamou para %s" % Game.game_title(game)
			var invite_text := _text(what, &"Hint")
			# Curto sempre ("Te chamou para Batalha naval"): uma linha só.
			invite_text.autowrap_mode = TextServer.AUTOWRAP_OFF
			words.add_child(invite_text)
			var state := _invite_state(item)
			if state == "closed":
				var gone := _text("A sala já fechou", &"Caption")
				gone.name = "Closed"
				gone.autowrap_mode = TextServer.AUTOWRAP_OFF
				gone.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
				words.add_child(gone)
			elif state == "open":
				var join := Button.new()
				join.name = "Join"
				join.text = "Entrar"
				join.theme_type_variation = &"PrimaryButton"
				join.custom_minimum_size = Vector2(0, 40)
				join.pressed.connect(func() -> void:
					Sound.play(Sound.Cue.TAP)
					Game.join_info = {"game": game, "code": str(item.get("room", ""))}
					get_tree().change_scene_to_file(Friends.JOIN_SCENE)
				)
				words.add_child(join)
		_:
			words.add_child(_fit(_text(str(item.get("text", "")), &""), AppTheme.SIZE_BODY))
	var when := _text(HistoryPanel.when(int(item.get("at", 0))), &"Caption")
	when.autowrap_mode = TextServer.AUTOWRAP_OFF
	when.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	words.add_child(when)
	return row


## Um rótulo que quebra linha dentro de um balão que encolhe não tem largura
## nenhuma: cada letra vira uma linha. A largura sai do próprio texto, com teto
## em 72% da tela, e o resto quebra.
func _fit(label: Label, font_size: int) -> Label:
	var width := AppTheme.font(500).get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 4.0
	label.custom_minimum_size.x = minf(width, get_viewport_rect().size.x * 0.72)
	return label


func _say(message: String) -> void:
	_note.text = message
	_note.visible = not message.is_empty()


func _text(value: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		label.theme_type_variation = variation
	return label
