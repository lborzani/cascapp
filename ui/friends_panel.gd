class_name FriendsPanel
extends Control

## Amigos da conta: o próprio código (e o QR dele) para mostrar, o código de um
## amigo para adicionar — digitado ou lido pela câmera —, e a lista com foto,
## nome e Elo de cada um.
##
## Adicionar manda um pedido (`pocketbase/pb_hooks/amigos.pb.js`): a amizade
## nasce quando o outro aceita, ou na hora se ele já tinha pedido. Os pedidos
## recebidos (Aceitar, Recusar) e os enviados (Cancelar) ficam acima da lista.
##
## Por cima da tela "Você", como o histórico: fechar devolve a tela como estava.

signal closed

## O QR de amigo. Prefixo diferente do da sala (`Pairing.PAYLOAD_PREFIX`): o
## leitor da tela de entrar recusa este, e este painel recusa o da sala.
const QR_PREFIX := "XDMF|"

var _code_input: CodeInput = null
var _status: Label = null
var _rows: VBoxContainer = null
var _requests: VBoxContainer = null
## Id do amigo cujo "Remover" já foi tocado uma vez e espera a confirmação.
var _confirming := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)

	var safe := SafeAreaMargin.new()
	for side in ["left", "top", "right", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 16)
	safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(safe)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	safe.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(column)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Amigos"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Fechar"
	close_button.theme_type_variation = &"GhostButton"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	if not Account.signed_in():
		column.add_child(_text("Sem conexão com a sua conta agora. Os amigos aparecem quando ela voltar.", &"Subtitle"))
		return

	column.add_child(_own_code())
	column.add_child(_add_row())
	_status = _text("", &"Caption")
	_status.visible = false
	column.add_child(_status)

	_requests = VBoxContainer.new()
	_requests.add_theme_constant_override("separation", 10)
	column.add_child(_requests)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	column.add_child(_rows)

	Pairing.qr_scanner.scanned.connect(_on_scanned)
	Pairing.qr_scanner.failed.connect(_say)
	# A foto de um amigo chega depois da lista: é um download à parte.
	Account.remote_avatar_loaded.connect(_refresh_photos)
	_load()


func close() -> void:
	closed.emit()
	queue_free()


## O conteúdo de um QR de amigo, ou vazio para qualquer outra coisa.
static func code_from_qr(payload: String) -> String:
	var text := payload.strip_edges()
	if not text.begins_with(QR_PREFIX):
		return ""
	var code := CodeInput.clean(text.trim_prefix(QR_PREFIX))
	return code if code.length() == CodeInput.LENGTH else ""


func _own_code() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS, AppTheme.LINE_SOFT, 1))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.add_child(_text("Seu código de amigo", &"Hint"))
	var code := _text(Account.friend_code, &"Greeting")
	words.add_child(code)
	words.add_child(_text("Mostre o QR para um amigo ler, ou dite o código.", &"Caption"))
	line.add_child(words)
	if not Account.friend_code.is_empty():
		var qr := QrCodeView.new()
		qr.payload = QR_PREFIX + Account.friend_code
		qr.custom_minimum_size = Vector2(112, 112)
		line.add_child(qr)
	return card


func _add_row() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_text("Adicionar pelo código do amigo", &"Hint"))
	_code_input = CodeInput.new()
	_code_input.completed.connect(func(_code: String) -> void: _add(_code_input.code))
	box.add_child(_code_input)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var add := Button.new()
	add.text = "Adicionar"
	add.theme_type_variation = &"PrimaryButton"
	add.custom_minimum_size = Vector2(0, 44)
	add.size_flags_horizontal = SIZE_EXPAND_FILL
	add.pressed.connect(func() -> void: _add(_code_input.code))
	buttons.add_child(add)
	if Pairing.qr_scanner.is_available():
		var scan := Button.new()
		scan.text = "Ler QR"
		scan.theme_type_variation = &"GhostButton"
		scan.custom_minimum_size = Vector2(0, 44)
		scan.pressed.connect(_scan)
		buttons.add_child(scan)
	box.add_child(buttons)
	return box


func _scan() -> void:
	Sound.play(Sound.Cue.TAP)
	_say("Abrindo a câmera…")
	Pairing.qr_scanner.start()


func _on_scanned(payload: String) -> void:
	var code := code_from_qr(payload)
	if code.is_empty():
		_say("Esse QR não é de amigo. Peça para abrir Você › Amigos e mostrar o dele.")
		return
	_code_input.set_code(code)


func _add(code: String) -> void:
	if code.length() != CodeInput.LENGTH:
		_say("O código tem 6 caracteres.")
		return
	_say("Adicionando…")
	var reply := await Account.add_friend(code)
	if not is_inside_tree():
		return
	match int(reply["code"]):
		200:
			var friend: Dictionary = reply["data"] if reply["data"] is Dictionary else {}
			Sound.play(Sound.Cue.CASH)
			_say(added_text(friend))
			_code_input.clear()
			_load()
		404:
			_say("Nenhuma conta com esse código. Confira as letras.")
		400:
			_say("Esse é o seu próprio código.")
		429:
			_say("Você tem pedidos demais esperando resposta. Cancele alguns antes.")
		_:
			_say("Não deu para adicionar agora. Confira a internet e tente de novo.")


## O que dizer depois de ler o código, pelo `status` da resposta.
static func added_text(friend: Dictionary) -> String:
	var name := str(friend.get("name", "")) if not str(friend.get("name", "")).is_empty() else "Essa conta"
	if str(friend.get("status", "")) == "friends":
		return "%s agora é seu amigo." % name
	return "Pedido enviado. %s aparece aqui quando aceitar." % name


func _load() -> void:
	var friends: Variant = await Account.friends()
	var pending: Variant = await Account.friend_requests()
	if not is_inside_tree():
		return
	_fill_requests(pending if pending is Dictionary else {"incoming": [], "outgoing": []})
	for child in _rows.get_children():
		child.queue_free()
	if friends == null:
		_rows.add_child(_text("Não deu para carregar a lista agora.", &"Subtitle"))
		return
	if friends.is_empty():
		_rows.add_child(_text("Nenhum amigo ainda. Troque códigos com quem joga com você.", &"Subtitle"))
	for friend: Dictionary in friends:
		_rows.add_child(_row(friend))


func _fill_requests(pending: Dictionary) -> void:
	for child in _requests.get_children():
		child.queue_free()
	for pair in [["incoming", "Pedidos recebidos"], ["outgoing", "Pedidos enviados"]]:
		var items: Array = pending.get(pair[0], [])
		if items.is_empty():
			continue
		_requests.add_child(_text(pair[1], &"Hint"))
		for request: Dictionary in items:
			_requests.add_child(_request_row(request, pair[0] == "incoming"))


func _row(friend: Dictionary) -> Control:
	var games := int(friend.get("games_chess", 0))
	var detail := "Xadrez: Elo %d · %d %s" % [int(friend.get("elo_chess", 0)), games, "partida" if games == 1 else "partidas"]
	var card := _card(friend, detail)
	var remove := _button("Remover", &"GhostButton")
	remove.pressed.connect(_remove.bind(str(friend.get("id", "")), remove))
	card.get_child(0).add_child(remove)
	return card


## Pedido recebido: Aceitar e Recusar. Enviado: Cancelar.
func _request_row(request: Dictionary, incoming: bool) -> Control:
	var profile: Dictionary = request.get("profile", {})
	var card := _card(profile, "Quer ser seu amigo" if incoming else "Pedido enviado")
	card.set_meta(&"request_id", str(request.get("id", "")))
	var line: Control = card.get_child(0)
	var id := str(request.get("id", ""))
	if incoming:
		var accept := _button("Aceitar", &"PrimaryButton")
		accept.pressed.connect(_answer.bind(id, true, accept))
		line.add_child(accept)
	var drop := _button("Recusar" if incoming else "Cancelar", &"GhostButton")
	drop.pressed.connect(_answer.bind(id, false, drop))
	line.add_child(drop)
	return card


func _answer(id: String, accept: bool, button: Button) -> void:
	Sound.play(Sound.Cue.TAP)
	button.disabled = true
	if not await Friends.answer_request(id, accept) and is_inside_tree():
		_say("Não deu para responder agora. Tente de novo.")
	if is_inside_tree():
		_load()


## Foto, nome e uma linha embaixo. A fileira (`get_child(0)`) recebe os botões.
func _card(profile: Dictionary, detail: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS, AppTheme.LINE_SOFT, 1))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)

	var coaster := Coaster.new()
	coaster.custom_minimum_size = Vector2(48, 48)
	coaster.size_flags_vertical = SIZE_SHRINK_CENTER
	coaster.player_name = str(profile.get("name", ""))
	coaster.photo = Account.avatar_of(str(profile.get("id", "")), str(profile.get("avatar", "")))
	coaster.set_meta(&"friend", profile)
	var look := Cosmetics.clean(profile.get("look", {}))
	coaster.frame = Cosmetics.frame_of(look)
	line.add_child(coaster)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	var name := _text(str(profile.get("name", "")), &"")
	name.add_theme_font_override("font", AppTheme.font(800))
	name.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	ProfileStyle.paint_name(name, look)
	words.add_child(name)
	words.add_child(_text(detail, &"Caption"))
	line.add_child(words)
	return card


func _button(text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_vertical = SIZE_SHRINK_CENTER
	return button


## Dois toques: o primeiro pergunta, o segundo remove. Remover tira dos dois lados.
func _remove(id: String, button: Button) -> void:
	if _confirming != id:
		_confirming = id
		button.text = "Confirmar?"
		return
	_confirming = ""
	button.disabled = true
	if await Account.remove_friend(id):
		_load()
	elif is_inside_tree():
		button.disabled = false
		button.text = "Remover"
		_say("Não deu para remover agora. Tente de novo.")


func _refresh_photos() -> void:
	for card in _rows.get_children() + _requests.get_children():
		for coaster in card.find_children("", "Coaster", true, false):
			var friend: Dictionary = coaster.get_meta(&"friend", {})
			if coaster.photo == null and not friend.is_empty():
				coaster.photo = Account.avatar_of(str(friend.get("id", "")), str(friend.get("avatar", "")))


func _say(message: String) -> void:
	_status.text = message
	_status.visible = not message.is_empty()


func _text(value: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		label.theme_type_variation = variation
	return label
