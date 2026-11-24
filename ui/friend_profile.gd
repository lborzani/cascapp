class_name FriendProfile
extends Control

## O perfil de um amigo, aberto pelo toque no card dele na gaveta: foto, nome,
## o que está fazendo agora, o Elo do xadrez, uma linha por jogo (partidas,
## vitórias, derrotas) e as partidas mais recentes.
##
## O topo sai na hora, do que a gaveta já sabe (`Friends.profile_of`); os
## números chegam depois, da rota do perfil (`Account.friend_profile`), que só
## responde a amigo. As partidas são as que o amigo subiu do aparelho dele
## (`Account.push_matches`): contra o bot e online, de todos os jogos.
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
	var recent: Array = data.get("recent", [])
	if stats.is_empty() and recent.is_empty():
		_rows.add_child(_text("Nenhuma partida ainda. As contra o bot e online aparecem aqui.", &"Subtitle"))
		return

	if not stats.is_empty():
		_rows.add_child(_text("Por jogo", &"Hint"))
	# Na ordem do catálogo, e não na que o servidor mandou.
	for game_id: StringName in Game.games_in():
		if stats.has(String(game_id)):
			_rows.add_child(_stat_row(game_id, stats[String(game_id)]))
	if not recent.is_empty():
		_rows.add_child(_text("Partidas recentes", &"Hint"))
	for game: Dictionary in recent:
		_rows.add_child(_recent_row(game))


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


func _recent_row(game: Dictionary) -> Control:
	var card := _card()
	var words := VBoxContainer.new()
	var name := _text(HistoryPanel.headline(game), &"")
	name.add_theme_font_override("font", AppTheme.font(800))
	name.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	words.add_child(name)
	words.add_child(_text(str(game.get("against", "")), &"Hint"))
	var foot := _text(HistoryPanel.footnote(game), &"Caption")
	foot.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	words.add_child(foot)
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
