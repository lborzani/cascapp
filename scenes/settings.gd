extends Control

## Ajustes: o que vale para o app inteiro, e não para uma partida.
##
## A aba Você: a foto (que se troca tocando nela), o nome, três números, os
## atalhos para o histórico e o treino, e os interruptores.
##
## O **nome** salva sozinho, ao sair do campo ou ao confirmar no teclado, e não a
## cada tecla: gravar em disco a cada letra digitada é dez escritas para uma
## decisão. Não há botão "Salvar" — ele valia só para o nome, ao lado de
## interruptores que já gravavam sozinhos, e ninguém sabia o que ele salvava. Os
## **interruptores** salvam na hora, porque um interruptor não tem momento de
## confirmar — ele já é a decisão, e quem desligou o som e saiu pelo "Voltar"
## esperaria encontrá-lo desligado.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const JOIN_SCENE := "res://scenes/join.tscn"

var _sound_switch: SwitchRow = null
var _haptics_switch: SwitchRow = null
var _history: HistoryPanel = null
var _news: ChangelogPanel = null
var _training: TrainingPanel = null
var _openings: OpeningsPanel = null
var _shop: ShopPanel = null
## A capa da loja atrás da foto e do nome (`_wrap_profile`), e a margem em volta
## deles, que só existe com capa.
var _profile_cover: Panel = null
var _profile_pad: MarginContainer = null
var _shop_button: Button = null
## O APK da versão nova que a busca manual achou; vazio enquanto não achou.


## O lápis no canto da foto, como no protótipo: diz que tocar ali troca a foto.
func _add_edit_badge() -> void:
	var badge := Control.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(28, 28)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -26
	badge.offset_top = -26
	badge.offset_right = 2
	badge.offset_bottom = 2
	badge.draw.connect(func() -> void:
		var center := badge.size * 0.5
		badge.draw_circle(center, 14.0, AppTheme.PAPER)
		# Um lápis em diagonal: corpo e ponta.
		var a := center + Vector2(-5.0, 5.0)
		var b := center + Vector2(5.0, -5.0)
		badge.draw_line(a, b, AppTheme.PAPER_INK, 3.0, true)
		badge.draw_line(a, a + Vector2(-2.0, 2.0), AppTheme.PAPER_INK, 2.0, true)
	)
	%Avatar.add_child(badge)


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()

	%NameEdit.max_length = Prefs.NAME_LIMIT
	# Campo vazio quando ainda não há escolha, com o padrão só no placeholder: um
	# "Você" dentro do campo parece nome digitado, e ninguém troca o que já
	# parece escolhido.
	%NameEdit.text = Prefs.player_name() if Prefs.has_name() else ""
	%NameEdit.placeholder_text = Prefs.DEFAULT_NAME
	%NameEdit.text_submitted.connect(func(_text: String): _save())
	%NameEdit.focus_exited.connect(_save)

	%Tabs.current = AppTabs.YOU
	if not Net.relay_available():
		%Tabs.disabled = [AppTabs.ONLINE] as Array[StringName]
	%Tabs.picked.connect(_go_tab)

	_sound_switch = _switch("Som", "Peça, dado, carta e vitória", Prefs.sound_on(), _toggle_sound)
	_haptics_switch = _switch("Vibração", "Um toque curto na sua vez", Prefs.haptics_on(), _toggle_haptics)
	_switch(
		"Mostrar lances possíveis", "Bolinhas nas casas de destino",
		Prefs.show_targets(), Prefs.set_show_targets
	)
	_switch("Planejar lance (premove)", "Só no xadrez online", Prefs.premove_on(), Prefs.set_premove)

	%Avatar.ring = AppTheme.ACCENT
	_add_edit_badge()
	%Version.text = "Versão %s" % AppVersion.text()
	for state: String in ["font_color", "font_hover_color"]:
		%NewsButton.add_theme_color_override(state, AppTheme.ACCENT)
	%NewsButton.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	# A loja é um atalho numa linha inteira, embaixo dos outros.
	_shop_button = Button.new()
	_shop_button.custom_minimum_size = Vector2(0, 76)
	_shop_button.focus_mode = Control.FOCUS_NONE
	_shop_button.theme_type_variation = &"IconButton"
	_shop_button.pressed.connect(_open_shop)
	%HistoryButton.get_parent().add_sibling(_shop_button)
	for shortcut: Button in [%HistoryButton, %TrainingButton, _shop_button]:
		shortcut.draw.connect(_draw_shortcut.bind(shortcut))
	%StatusLabel.text = _status_text()
	var openings := Button.new()
	openings.custom_minimum_size = Vector2(0, 76)
	openings.focus_mode = Control.FOCUS_NONE
	openings.theme_type_variation = &"IconButton"
	openings.set_meta(&"title", "Aberturas")
	openings.set_meta(&"detail", "%d linhas para treinar, de ataque e de defesa" % Openings.LINES.size())
	openings.draw.connect(_draw_shortcut.bind(openings))
	openings.pressed.connect(_open_openings)
	%HistoryButton.get_parent().add_sibling(openings)
	_refresh_games()
	%HistoryButton.pressed.connect(_open_history)
	%TrainingButton.pressed.connect(_open_training)
	%UpdateButton.pressed.connect(_check_updates)
	%NewsButton.pressed.connect(_open_news)
	# Sonda do Bluetooth sem internet: ferramenta de teste, nunca no build de release.
	if OS.is_debug_build() and Pairing.ble.is_available():
		var probe := Button.new()
		probe.text = "Teste de Bluetooth (depuração)"
		probe.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ble_probe.tscn"))
		%NewsButton.add_sibling(probe)
	# A própria bolacha é o botão de trocar a foto; sem seletor de arquivo no
	# aparelho, ela só mostra.
	%PhotoButton.disabled = not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	%PhotoButton.pressed.connect(_pick_photo)
	Account.avatar_changed.connect(_update_preview)
	_wrap_profile()
	Account.wallet_changed.connect(_refresh_games)
	# A moldura comprada ou trocada na loja já aparece na foto daqui.
	Account.wallet_changed.connect(_update_preview)
	_update_preview()


func _go_tab(route: StringName) -> void:
	_save()
	Sound.play(Sound.Cue.TAP)
	match route:
		AppTabs.GAMES:
			get_tree().change_scene_to_file(MENU_SCENE)
		AppTabs.ONLINE:
			get_tree().change_scene_to_file(JOIN_SCENE)


## Os dois interruptores gravam **na hora**, e não no "Salvar".
##
## O botão de salvar é do nome, que é um campo de texto e precisa de um momento
## de confirmar. Um interruptor não tem esse momento: ele já é a decisão, e quem
## desligou o som e saiu pelo "Voltar" esperaria encontrá-lo desligado.
##
## O de som toca ao ser **ligado**. É a única forma de responder "ligado como?"
## sem mandar o jogador abrir uma partida para descobrir.
func _toggle_sound(value: bool) -> void:
	Prefs.set_sound(value)
	if value:
		Sound.play(Sound.Cue.CASH)


func _toggle_haptics(value: bool) -> void:
	Prefs.set_haptics(value)
	# A vibração só se prova vibrando, e ela não sai do `Sound` sem um sinal que a
	# tenha. O toque é o mais curto dos quatro que vibram.
	if value:
		Sound.play(Sound.Cue.TAP)


## Que build é este e o que ele consegue fazer.
##
## Estava no rodapé da tela inicial, sob a lista de jogos. Saiu de lá porque é
## diagnóstico: responde "por que não tem sala nenhuma?" e "por que o botão de
## câmera não aparece?", que são perguntas que se fazem **depois** de estranhar
## alguma coisa — e o rodapé da primeira tela é o lugar mais caro do app para uma
## resposta que quase ninguém procura.
func _status_text() -> String:
	var parts := PackedStringArray()
	parts.append("On-line: %s" % ("sim" if Net.relay_available() else "não"))
	parts.append("NFC: %s" % ("sim" if Pairing.nfc.is_available() else "não"))
	parts.append("Câmera: %s" % ("sim" if Pairing.qr_scanner.is_available() else "não"))
	return "   •   ".join(parts)


func _save() -> void:
	Prefs.set_player_name(%NameEdit.text)
	_update_preview()
	# Sem esperar: o nome já valeu no aparelho, e a conta acompanha quando der.
	Account.push_name(Prefs.player_name())


## Põe a fileira da foto e do nome dentro de um cartão que pode ter a capa da
## loja atrás (`ProfileCover`). A fileira vem da cena; o cartão nasce aqui.
func _wrap_profile() -> void:
	var row: Control = %PhotoButton.get_parent()
	var content := row.get_parent()
	var index := row.get_index()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_profile_cover = ProfileCover.rounded({}, AppTheme.RADIUS_LARGE, ProfileCover.CARD_SHADE)
	card.add_child(_profile_cover)
	_profile_pad = MarginContainer.new()
	card.add_child(_profile_pad)
	# Tirar da árvore apaga o dono dos nós, e com ele os `%nomes` (`%Preview`,
	# `%NameEdit`): o dono volta depois da mudança.
	var owned: Array[Node] = [row]
	owned.append_array(row.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node.owner == self))
	content.remove_child(row)
	_profile_pad.add_child(row)
	content.add_child(card)
	content.move_child(card, index)
	for node in owned:
		node.owner = self


## A linha sob o nome diz que ele salva sozinho e, com conta, o código de amigo —
## que é o que se dita para alguém adicionar você.
func _update_preview() -> void:
	%Preview.text = "Salva sozinho"
	if not Account.friend_code.is_empty():
		%Preview.text += " · código de amigo %s" % Account.friend_code
	# A bolacha é a mesma que os outros vão ver na mesa.
	%Avatar.player_name = Prefs.player_name()
	%Avatar.photo = Account.local_avatar()
	%Avatar.frame = Cosmetics.frame_of(Account.look)
	if _profile_cover != null:
		var has_cover := not Cosmetics.item_of(Account.look, Cosmetics.BANNER).is_empty()
		_profile_cover.visible = has_cover
		(_profile_cover.get_child(0) as ProfileCover).look = Account.look
		for side: String in ["left", "top", "right", "bottom"]:
			_profile_pad.add_theme_constant_override("margin_" + side, 14 if has_cover else 0)


## Uma linha do cartão de interruptores. `save` grava a escolha; quem precisa de
## mais (o som toca ao ligar) passa a própria função.
func _switch(label: String, about: String, start: bool, save: Callable) -> SwitchRow:
	var row := SwitchRow.new()
	row.setup(label, start, about)
	row.switched.connect(save)
	%Switches.add_child(row)
	return row


## Os três números do topo. O Elo só existe com conta; sem ela o bloco diz isso
## em vez de mostrar um zero que parece nota.
func _fill_stats(games: int, due: int) -> void:
	for child in %Stats.get_children():
		%Stats.remove_child(child)
		child.queue_free()
	var chess: Color = AppTheme.GAME_COLORS["chess"]
	_stat(str(Account.elo) if Account.elo > 0 else "—", "Elo no xadrez", chess, AppTheme.ACCENT_INK)
	_stat(str(games), "partidas" if games != 1 else "partida", AppTheme.SURFACE, AppTheme.TEXT)
	_stat(str(due), "para treinar hoje", AppTheme.SURFACE, AppTheme.TEXT)
	_stat(str(Account.coins) if Account.coins >= 0 else "—", "moedas", AppTheme.SURFACE, AppTheme.TEXT)


func _stat(value: String, caption: String, fill: Color, ink: Color) -> void:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size.y = 80.0
	var box := AppTheme.box(fill, AppTheme.RADIUS_LARGE)
	box.content_margin_left = 6
	box.content_margin_right = 6
	tile.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", -2)
	tile.add_child(column)
	var number := Label.new()
	number.text = value
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_override("font", AppTheme.display(700))
	number.add_theme_font_size_override("font_size", 28)
	number.add_theme_color_override("font_color", ink)
	column.add_child(number)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", AppTheme.font(700))
	label.add_theme_font_size_override("font_size", AppTheme.SIZE_CAPTION)
	label.add_theme_color_override("font_color", ink if fill != AppTheme.SURFACE else AppTheme.TEXT_DIM)
	column.add_child(label)
	%Stats.add_child(tile)


## Histórico e Treino: um cartão com o nome e uma linha que conta. O texto mora
## em `meta` e não no `text` do botão, que não sabe ter duas linhas de pesos
## diferentes.
func _draw_shortcut(button: Button) -> void:
	button.draw_style_box(
		AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_LARGE), Rect2(Vector2.ZERO, button.size)
	)
	var lit: bool = button.get_meta(&"lit", false)
	button.draw_string(
		AppTheme.display(600), Vector2(14.0, button.size.y * 0.5 - 2.0), str(button.get_meta(&"title", "")),
		HORIZONTAL_ALIGNMENT_LEFT, button.size.x - 28.0, 18, AppTheme.TEXT
	)
	button.draw_string(
		AppTheme.font(700), Vector2(14.0, button.size.y * 0.5 + 17.0), str(button.get_meta(&"detail", "")),
		HORIZONTAL_ALIGNMENT_LEFT, button.size.x - 28.0, 13, AppTheme.ACCENT if lit else AppTheme.TEXT_DIM
	)


# --- foto -----------------------------------------------------------------------


## O seletor do sistema (no Android, o da galeria). A foto é recortada e
## comprimida aqui mesmo, e sobe para a conta quando der — ver `Account`.
func _pick_photo() -> void:
	Sound.play(Sound.Cue.TAP)
	DisplayServer.file_dialog_show(
		"Escolher foto", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.jpg,*.jpeg,*.png,*.webp;Fotos;image/jpeg,image/png,image/webp"]),
		_on_photo_picked
	)


func _on_photo_picked(picked: bool, paths: PackedStringArray, _filter: int) -> void:
	if not picked or paths.is_empty():
		return
	var webp := Avatar.compress(FileAccess.get_file_as_bytes(paths[0]))
	if webp.is_empty():
		%Preview.text = "Essa imagem não abriu. Tente uma foto JPEG ou PNG."
		return
	Account.set_avatar(webp)


## O gesto de voltar é o botão "Voltar", e não o "Salvar": quem sai pelo gesto
## sai sem confirmar o campo de texto, como sairia pelo botão. Os interruptores
## já gravaram sozinhos, então o que se perde é no máximo um nome digitado pela
## metade e nunca confirmado.
func go_back() -> void:
	if is_instance_valid(_history):
		_history.close()
		return
	if is_instance_valid(_news) and not _news.is_queued_for_deletion():
		_news.close()
		return
	if is_instance_valid(_training):
		_training.close()
		return
	if is_instance_valid(_shop):
		_shop.close()
		return
	if is_instance_valid(_openings):
		_openings.close()
		return
	_leave()


# --- atualização ----------------------------------------------------------------


## Procura versão nova na hora, sem a espera do menu: quem toca aqui quer a
## resposta. Achou, é a mesma tela obrigatória do menu, por cima desta.
func _check_updates() -> void:
	Sound.play(Sound.Cue.TAP)
	%UpdateButton.disabled = true
	%UpdateButton.text = "Procurando…"
	UpdateCheck.fetch(self, _show_update)


func _show_update(releases: Variant) -> void:
	%UpdateButton.disabled = false
	%UpdateButton.text = "Procurar atualização"
	%UpdateResult.visible = true
	if not releases is Array:
		%UpdateResult.text = "Não deu para consultar agora. Confira a internet e tente de novo."
		return
	Prefs.set_update_checked(int(Time.get_unix_time_from_system()))
	var offer := UpdateCheck.offer(releases, AppVersion.text(), Patcher.apk_version)
	Prefs.set_pending_update(offer)
	if offer.is_empty():
		%UpdateResult.text = "Você já está na versão mais recente (%s)." % AppVersion.text()
		return
	%UpdateResult.text = "Versão %s disponível." % offer["version"]
	var gate := UpdateGate.new()
	gate.offer = offer
	add_child(gate)


## Todas as versões do `CHANGELOG.md` que veio no APK, sem rede.
func _open_news() -> void:
	Sound.play(Sound.Cue.TAP)
	_news = ChangelogPanel.new()
	_news.sections = Changelog.parse(Changelog.bundled())
	add_child(_news)


## Por cima desta tela, e não uma cena: fechar volta para cá como estava.
func _open_history() -> void:
	_history = HistoryPanel.new()
	# Uma revisão aberta lá dentro pode ter mandado erros para o treino.
	_history.closed.connect(_refresh_games)
	add_child(_history)


func _open_openings() -> void:
	Sound.play(Sound.Cue.TAP)
	_openings = OpeningsPanel.new()
	add_child(_openings)


func _open_training() -> void:
	Sound.play(Sound.Cue.TAP)
	_training = TrainingPanel.new()
	_training.closed.connect(_refresh_games)
	add_child(_training)


func _open_shop() -> void:
	Sound.play(Sound.Cue.TAP)
	_shop = ShopPanel.new()
	add_child(_shop)


## Os números da tela: os três blocos do topo e a linha de cada atalho. "Treino"
## conta o que vence hoje, e não o baralho inteiro: o número é o convite, e um
## convite para 40 desafios que só voltam no mês que vem é mentira.
func _refresh_games() -> void:
	var games := Prefs.history().size()
	var due := Training.due(Prefs.training(), int(Time.get_unix_time_from_system())).size()
	_fill_stats(games, due)
	%HistoryButton.set_meta(&"title", "Histórico")
	%HistoryButton.set_meta(&"detail", history_detail(games))
	%TrainingButton.set_meta(&"title", "Treino")
	%TrainingButton.set_meta(&"detail", training_detail(due))
	%TrainingButton.set_meta(&"lit", due > 0)
	%HistoryButton.queue_redraw()
	%TrainingButton.queue_redraw()
	_shop_button.set_meta(&"title", "Loja")
	_shop_button.set_meta(&"detail", "Bolas, tacos, peças e perfil · %s moedas" % (str(Account.coins) if Account.coins >= 0 else "—"))
	_shop_button.set_meta(&"lit", true)
	_shop_button.queue_redraw()


static func history_detail(games: int) -> String:
	if games <= 0:
		return "Reveja e revise"
	return "%d partida%s" % [games, "" if games == 1 else "s"]


static func training_detail(due: int) -> String:
	if due <= 0:
		return "Nada para hoje"
	return "%d desafio%s hoje" % [due, "" if due == 1 else "s"]


func _leave() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
