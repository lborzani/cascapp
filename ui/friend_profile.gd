class_name FriendProfile
extends Control

## O perfil de um amigo, aberto pelo toque no card dele na gaveta: foto, nome,
## o que está fazendo agora, o Elo do xadrez e uma linha por jogo (partidas,
## vitórias, derrotas). As partidas uma a uma ficam só no histórico de cada um.
##
## O topo sai na hora, do que a gaveta já sabe (`Friends.profile_of`); os
## números chegam depois, da rota do perfil (`Account.friend_profile`), que só
## responde a amigo. As partidas são as que o amigo subiu do aparelho dele
## (`Account.push_matches`): contra o bot e online, de todos os jogos.
##
## Embaixo dos botões de conversar, convidar e presentear: Silenciar (sem
## notificação das mensagens dele), Remover e Bloquear (`Account.block`).
##
## Por cima da gaveta, como o painel de amigos: fechar devolve a gaveta.

signal closed
## Convidar este amigo: a gaveta pergunta o jogo.
signal invite_requested(friend_id: String)
## Abrir a conversa com este amigo.
signal chat_requested(friend_id: String)

const PHOTO := 72.0

var friend_id := ""

var _rows: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	# A capa da loja do amigo é o fundo da tela inteira, escurecida embaixo para o
	# texto continuar legível.
	var profile := Friends.profile_of(friend_id)
	var look := Cosmetics.clean(profile.get("look", {}))
	if not Cosmetics.item_of(look, Cosmetics.BANNER).is_empty():
		var cover := ProfileCover.new()
		cover.look = look
		cover.fade = true
		cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(cover)

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
	var title := _text("Perfil", &"Title")
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Fechar"
	close_button.theme_type_variation = &"GhostButton"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var coaster := Coaster.new()
	coaster.custom_minimum_size = Vector2(PHOTO, PHOTO)
	coaster.player_name = str(profile.get("name", ""))
	coaster.photo = Account.avatar_of(friend_id, str(profile.get("avatar", "")))
	coaster.frame = Cosmetics.frame_of(look)
	top.add_child(coaster)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	var name_label := _text(str(profile.get("name", "")), &"Greeting")
	ProfileStyle.paint_name(name_label, look)
	words.add_child(name_label)
	var title_label := ProfileStyle.title_label(look)
	if title_label != null:
		words.add_child(title_label)
	var status: Variant = Friends.status_of(friend_id)
	_status = _text(Friends.status_text(status), &"Caption")
	if status != null:
		_status.add_theme_color_override("font_color", AppTheme.SUCCESS)
	words.add_child(_status)
	var elo := int(profile.get("elo_chess", 0))
	if elo > 0:
		words.add_child(_text("Elo %d no xadrez" % elo, &"Hint"))
	top.add_child(words)
	column.add_child(top)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	var unread := Friends.unread_of(friend_id)
	var chat := Button.new()
	chat.name = "Chat"
	chat.text = "Conversar (%d nova%s)" % [unread, "" if unread == 1 else "s"] if unread > 0 else "Conversar"
	chat.theme_type_variation = &"GhostButton"
	chat.custom_minimum_size = Vector2(0, 48)
	chat.size_flags_horizontal = SIZE_EXPAND_FILL
	chat.pressed.connect(func() -> void:
		Sound.play(Sound.Cue.TAP)
		chat_requested.emit(friend_id)
	)
	actions.add_child(chat)
	# Convidar só quem está online e fora de sala, como na gaveta.
	if status is Dictionary and str(status.get("room", "")).is_empty() and Net.relay_available():
		var invite := Button.new()
		invite.name = "Invite"
		invite.text = "Convidar"
		invite.theme_type_variation = &"PrimaryButton"
		invite.custom_minimum_size = Vector2(0, 48)
		invite.size_flags_horizontal = SIZE_EXPAND_FILL
		invite.pressed.connect(func() -> void:
			Sound.play(Sound.Cue.TAP)
			invite_requested.emit(friend_id)
		)
		actions.add_child(invite)

	# O presentinho do dia: de graça, um por amigo por dia. Linha própria: com
	# Conversar e Convidar, três botões não cabem num celular em pé.
	if Account.signed_in():
		var gift := Button.new()
		gift.name = "Gift"
		gift.theme_type_variation = &"GhostButton"
		gift.custom_minimum_size = Vector2(0, 48)
		gift.size_flags_horizontal = SIZE_EXPAND_FILL
		_paint_gift(gift)
		gift.pressed.connect(_send_gift.bind(gift))
		column.add_child(gift)
		column.add_child(_manage_row())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	column.add_child(_rows)

	if not Account.signed_in():
		_rows.add_child(_text("Sem conexão com a sua conta agora. As partidas aparecem quando ela voltar.", &"Subtitle"))
		return
	_rows.add_child(_text("Carregando as partidas…", &"Subtitle"))
	var data: Variant = await Account.friend_profile(friend_id)
	if is_inside_tree():
		show_data(data)


func _paint_gift(button: Button) -> void:
	var sent := friend_id in Account.gifts_sent_today
	button.text = "Presentinho enviado" if sent else "Presentinho +%d" % Account.gift_daily_coins
	button.disabled = sent


func _send_gift(button: Button) -> void:
	Sound.play(Sound.Cue.TAP)
	button.disabled = true
	var code := await Account.send_daily_gift(friend_id)
	if not is_inside_tree():
		return
	match code:
		200, 409:
			_paint_gift(button)
		429:
			button.text = "Já ganhou muitos hoje"
		_:
			button.text = "Tente de novo"
			button.disabled = false


## Silenciar, Remover e Bloquear. Remover e Bloquear pedem um segundo toque.
func _manage_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var mute := _small_button("Mute", "")
	_paint_mute(mute)
	mute.pressed.connect(_toggle_mute.bind(mute))
	row.add_child(mute)
	var remove := _small_button("Remove", "Remover")
	remove.pressed.connect(_confirm.bind(remove, "Remover", Account.remove_friend))
	row.add_child(remove)
	var block := _small_button("Block", "Bloquear")
	block.pressed.connect(_confirm.bind(block, "Bloquear", Account.block))
	row.add_child(block)
	return row


func _small_button(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.theme_type_variation = &"GhostButton"
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	return button


func _paint_mute(button: Button) -> void:
	button.text = "Reativar avisos" if Friends.is_muted(friend_id) else "Silenciar"


func _toggle_mute(button: Button) -> void:
	Sound.play(Sound.Cue.TAP)
	button.disabled = true
	var ok := await Friends.set_muted(friend_id, not Friends.is_muted(friend_id))
	if not is_inside_tree():
		return
	button.disabled = false
	if ok:
		_paint_mute(button)
	else:
		button.text = "Tente de novo"


## O primeiro toque pergunta; o segundo chama `action(friend_id)`. Dando certo,
## a lista recarrega e o perfil fecha: o amigo não é mais amigo.
func _confirm(button: Button, label: String, action: Callable) -> void:
	Sound.play(Sound.Cue.TAP)
	if button.text == label:
		button.text = "Confirmar?"
		return
	button.disabled = true
	if await action.call(friend_id):
		Friends.refresh()
		close()
	elif is_inside_tree():
		button.disabled = false
		button.text = label


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


## Os números e as partidas. `null` é que não deu para perguntar.
func show_data(data: Variant) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if not data is Dictionary:
		_rows.add_child(_text("Não deu para carregar as partidas agora.", &"Subtitle"))
		return
	var stats: Dictionary = data.get("stats", {})
	if stats.is_empty():
		_rows.add_child(_text("Nenhuma partida ainda. As contra o bot e online aparecem aqui.", &"Subtitle"))
		return

	if not stats.is_empty():
		_rows.add_child(_text("Por jogo", &"Hint"))
	# Na ordem do catálogo, e não na que o servidor mandou.
	for game_id: StringName in Game.games_in():
		if stats.has(String(game_id)):
			_rows.add_child(_stat_row(game_id, stats[String(game_id)]))


## "12 partidas · 7 vitórias · 4 derrotas · 1 empate".
static func stat_line(numbers: Dictionary) -> String:
	var parts := PackedStringArray()
	for pair in [["played", "partida", "partidas"], ["won", "vitória", "vitórias"], ["lost", "derrota", "derrotas"], ["draw", "empate", "empates"]]:
		var count := int(numbers.get(pair[0], 0))
		if count > 0 or pair[0] == "played":
			parts.append("%d %s" % [count, pair[1] if count == 1 else pair[2]])
	return " · ".join(parts)


func _stat_row(game_id: StringName, numbers: Dictionary) -> Control:
	var card := _card()
	card.set_meta(&"game", game_id)
	var words := VBoxContainer.new()
	var name := _text(Game.game_title(game_id), &"")
	name.add_theme_font_override("font", AppTheme.font(800))
	name.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	words.add_child(name)
	words.add_child(_text(stat_line(numbers), &"Caption"))
	card.add_child(words)
	return card


func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS, AppTheme.LINE_SOFT, 1))
	return card


func _text(value: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		label.theme_type_variation = variation
	return label
