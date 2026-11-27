class_name ShopPanel
extends Control

## A loja: o saldo, os itens à venda e os já comprados para usar.
##
## Mora na aba Loja (`scenes/shop.tscn`), que dá o fundo e a área segura; sai-se
## pelas abas, e por isso não há "Fechar".
## Tudo passa pela conta (`Account.buy`, `Account.equip`): o preço e o saldo são
## do servidor, e sem conta a loja só mostra. Tocar num item abre a folha dele,
## com a amostra grande e o que dá para fazer: comprar (já entra em uso), usar ou
## presentear.

const SWATCH := 72.0
## As abas: `[encaixes, rótulo]`, na ordem da tela. Aba de mais de um encaixe
## mostra uma seção por encaixe, com o título de `SECTIONS`.
const TABS := [
	[[Cosmetics.BALL], "Bola"],
	[[Cosmetics.CUE], "Taco"],
	[[Cosmetics.BOARD], "Tabuleiro"],
	[[Cosmetics.PIECES, Cosmetics.FINISH, Cosmetics.TOKEN], "Peças"],
	[[Cosmetics.DECK], "Cartas"],
	[[Cosmetics.FRAME, Cosmetics.BANNER, Cosmetics.TITLE, Cosmetics.NAME_COLOR], "Perfil"],
]
## As categorias de uma aba de mais de um encaixe: `[rótulo do chip, o que muda]`.
## Uma por vez na tela: com todas empilhadas e só um título entre elas, Formato e
## Acabamento pareciam a mesma lista.
const SECTIONS := {
	Cosmetics.PIECES: ["Formato", "O desenho das peças no xadrez e nas damas."],
	Cosmetics.FINISH: ["Acabamento", "A cor e o brilho das peças, com qualquer formato."],
	Cosmetics.TOKEN: ["Metrópole", "A sua peça no tabuleiro do Metrópole."],
	Cosmetics.FRAME: ["Moldura", "O aro em volta da sua foto."],
	Cosmetics.BANNER: ["Capa", "O fundo do seu cartão de perfil."],
	Cosmetics.TITLE: ["Título", "A frase que aparece embaixo do seu nome."],
	Cosmetics.NAME_COLOR: ["Cor do nome", "Como o seu nome aparece para os outros."],
}
## Os encaixes do perfil: a aba deles abre com o meu cartão como os amigos o veem.
const PROFILE_SLOTS := [Cosmetics.FRAME, Cosmetics.BANNER, Cosmetics.TITLE, Cosmetics.NAME_COLOR]

var _balance: Label = null
var _note: Label = null
var _rows: VBoxContainer = null
var _tabs: SegmentedControl = null
## A segunda fileira, das categorias da aba; escondida em aba de um encaixe só.
var _kinds: SegmentedControl = null
## O que a categoria aberta muda.
var _about: Label = null
## Os encaixes da aba aberta.
var _slots: Array = TABS[0][0]
## O encaixe à mostra: um dos `_slots`.
var _slot: String = TABS[0][0][0]
var _toast: Banner = null
## O amigo à espera do segundo toque para presentear; vazio sem nenhum.
var _confirming := ""
var _busy := false
## A escolha do amigo para presentear, por cima da loja; `null` fechada.
var _picker: Control = null
## A folha do item tocado; `null` fechada.
var _item: BottomSheet = null


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var safe := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 16)
	safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	safe.add_child(column)

	# Título e saldo numa linha só: o saldo grande e a frase fixa embaixo comiam um
	# quarto da tela, e só cabiam dois itens.
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Loja"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_coin_pill())
	column.add_child(header)

	_note = Label.new()
	_note.theme_type_variation = &"Hint"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)

	_tabs = SegmentedControl.new()
	var labels := PackedStringArray()
	for tab: Array in TABS:
		labels.append(tab[1])
	_tabs.setup(labels)
	# Seis abas num celular em pé: com larguras iguais, "Tabuleiro" cortava e
	# "Bola" sobrava. Cada aba ganha largura pelo rótulo mais a folga do botão, que
	# é a mesma em todas (por isso o "+ 3": sem ela, as curtas ficavam sem a folga
	# e cortavam, "Bol" e "Tac").
	for button in _tabs._buttons:
		button.size_flags_stretch_ratio = button.text.length() + 3.0
		button.add_theme_font_size_override("font_size", AppTheme.SIZE_CAPTION)
	_tabs.selected.connect(func(index: int) -> void:
		Sound.play(Sound.Cue.TAP)
		_open_tab(index)
	)
	column.add_child(_tabs)

	_kinds = SegmentedControl.new()
	_kinds.selected.connect(func(index: int) -> void:
		Sound.play(Sound.Cue.TAP)
		_slot = _slots[index]
		_confirming = ""
		_fill()
	)
	column.add_child(_kinds)
	_about = Label.new()
	_about.theme_type_variation = &"Hint"
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_about)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_rows)

	_toast = Banner.new()
	safe.add_child(_toast)

	Account.wallet_changed.connect(_fill)
	_open_tab(0)
	if Account.prices.is_empty():
		Account.fetch_prices()


## A folha do item ou a lista de amigos está aberta por cima da loja.
func picking() -> bool:
	return is_instance_valid(_picker) or (is_instance_valid(_item) and _item.is_open())


## O que o voltar do sistema chama com algo por cima: fecha só isso.
func close() -> void:
	if is_instance_valid(_item) and _item.is_open():
		_item.close()
		return
	_close_picker()


## A folha de um item: a amostra grande, o nome, a categoria e o que dá para
## fazer com ele. `id` vazio é o padrão do encaixe.
func _open_item(slot: String, id: String) -> void:
	Sound.play(Sound.Cue.TAP)
	_item = BottomSheet.new()
	_item.top = -1.0
	var sheet := _item
	var preview := _swatch(slot, id, SWATCH * 2.0)
	preview.size_flags_horizontal = SIZE_SHRINK_CENTER
	sheet.body.add_child(preview)
	var name := Label.new()
	name.text = Cosmetics.name_of(id) if not id.is_empty() else "Padrão"
	name.theme_type_variation = &"Title"
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.body.add_child(name)
	var kind := Label.new()
	for tab: Array in TABS:
		if slot in tab[0]:
			kind.text = SECTIONS[slot][0] if SECTIONS.has(slot) else tab[1]
	kind.theme_type_variation = &"Hint"
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.body.add_child(kind)

	var using := str(Account.look.get(slot, "")) == id
	var owned := id.is_empty() or Account.owns(id)
	var price := int(Account.prices.get(id, 0))
	var main := Button.new()
	main.custom_minimum_size.y = 52
	main.focus_mode = FOCUS_NONE
	main.theme_type_variation = &"PrimaryButton"
	if using:
		main.text = "Em uso"
		main.disabled = true
	elif owned:
		main.text = "Usar"
		main.pressed.connect(func() -> void:
			Sound.play(Sound.Cue.TAP)
			sheet.close()
			_equip(slot, id)
		)
	elif id in Account.exclusive or not Account.prices.has(id):
		main.text = "Só sai como prêmio de missão"
		main.disabled = true
	elif Account.coins >= 0 and Account.coins < price:
		main.text = "Faltam %d moedas" % (price - Account.coins)
		main.disabled = true
	else:
		main.text = "Comprar por %d moedas" % price
		main.pressed.connect(func() -> void:
			Sound.play(Sound.Cue.TAP)
			sheet.close()
			_buy(slot, id)
		)
	main.disabled = main.disabled or _busy or not Account.signed_in()
	sheet.body.add_child(main)
	# Presentear só o que está à venda, e só quem tem amigo.
	if Account.prices.has(id) and not Friends.list.is_empty():
		var gift := Button.new()
		gift.text = "Presentear um amigo"
		gift.theme_type_variation = &"GhostButton"
		gift.custom_minimum_size.y = 48
		gift.focus_mode = FOCUS_NONE
		gift.disabled = _busy or not Account.signed_in()
		gift.pressed.connect(func() -> void:
			sheet.close()
			_pick_friend(id)
		)
		sheet.body.add_child(gift)
	add_child(sheet)


## Abre a aba `index` na primeira categoria dela.
func _open_tab(index: int) -> void:
	_slots = TABS[index][0]
	_slot = _slots[0]
	_confirming = ""
	var labels := PackedStringArray()
	for slot: String in _slots:
		labels.append(SECTIONS[slot][0] if SECTIONS.has(slot) else "")
	_kinds.setup(labels)
	# Como nas abas: "Cor do nome" cortava ao lado de "Capa" com larguras iguais.
	for button in _kinds._buttons:
		button.size_flags_stretch_ratio = button.text.length() + 3.0
		button.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	_kinds.visible = _slots.size() > 1
	_fill()


## O saldo numa pílula com a moeda desenhada, como a do menu.
func _coin_pill() -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_vertical = SIZE_SHRINK_CENTER
	var box := AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_ICON)
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.content_margin_left = 34
	box.content_margin_right = 14
	pill.add_theme_stylebox_override("panel", box)
	pill.draw.connect(func() -> void:
		var center := Vector2(19.0, pill.size.y * 0.5)
		pill.draw_circle(center, 9.0, AppTheme.ACCENT_EDGE)
		pill.draw_circle(center, 7.0, AppTheme.ACCENT)
	)
	_balance = Label.new()
	_balance.add_theme_font_override("font", AppTheme.display(700))
	_balance.add_theme_font_size_override("font_size", AppTheme.SIZE_DISPLAY_M)
	pill.add_child(_balance)
	return pill


func _fill() -> void:
	_balance.text = str(Account.coins) if Account.coins >= 0 else "—"
	# A dica só quando algo impede comprar; o resto do tempo ela só ocupava a tela.
	if not Account.signed_in():
		_note.text = "A loja precisa da conta, e ela ainda não entrou. Confira a internet."
	elif Account.prices.is_empty():
		_note.text = "Carregando os preços…"
	else:
		_note.text = ""
	_note.visible = not _note.text.is_empty()
	_kinds.set_current(_slots.find(_slot))
	_about.text = SECTIONS[_slot][1] if SECTIONS.has(_slot) else ""
	_about.visible = not _about.text.is_empty()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _slot in PROFILE_SLOTS:
		_rows.add_child(_profile_card(Account.look))
	# Três por linha: com o estado num selo, o card não precisa mais de botão.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_rows.add_child(grid)
	grid.add_child(_card(_slot, ""))
	# Os exclusivos aparecem trancados: a vitrine do que as missões dão. Os de
	# testador (`testers`) não: só quem ganhou vê.
	for id in Cosmetics.of_slot(_slot):
		var showcase: bool = not Cosmetics.ITEMS[id].get("testers", false) and (Account.prices.has(id) or id in Account.exclusive)
		if showcase or id in Account.owned:
			grid.add_child(_card(_slot, id))


## Um item: a amostra, o nome e o botão. `id` vazio é o padrão do encaixe.
func _card(slot: String, id: String) -> Control:
	var using := str(Account.look.get(slot, "")) == id
	var owned := id.is_empty() or Account.owns(id)
	var card := PanelContainer.new()
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	# O que está em uso ganha a borda de destaque: dá para achar sem ler nada.
	var box := AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS, AppTheme.ACCENT if using else AppTheme.SURFACE, 2)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, 8)
	card.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(column)

	column.add_child(_swatch(slot, id))

	var name := Label.new()
	name.text = Cosmetics.name_of(id) if not id.is_empty() else "Padrão"
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_font_override("font", AppTheme.display(600))
	name.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	column.add_child(name)

	# O estado num selo, cada um com a sua cor: antes era sempre o mesmo botão
	# escuro, e "Usar", "Em uso" e "300 moedas" pareciam a mesma coisa.
	if using:
		column.add_child(_badge("Em uso", AppTheme.ACCENT, AppTheme.ACCENT_INK))
	elif id.is_empty():
		column.add_child(_badge("Grátis", AppTheme.SURFACE_HIGH, AppTheme.TEXT))
	elif owned:
		column.add_child(_badge("Seu", AppTheme.SUCCESS_SOFT, AppTheme.SUCCESS))
	elif id in Account.exclusive:
		column.add_child(_badge("Só por missão", AppTheme.SURFACE_HIGH, AppTheme.TEXT_DIM))
	else:
		column.add_child(_badge(str(int(Account.prices.get(id, 0))), AppTheme.ACCENT_SOFT, AppTheme.ACCENT, true))

	# O card inteiro é o botão, por cima do conteúdo.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	hit.disabled = _busy
	hit.pressed.connect(_open_item.bind(slot, id))
	card.add_child(hit)
	return card


## Um selo de estado, centrado. `coin` põe a moeda antes do texto.
func _badge(text: String, fill: Color, ink: Color, coin := false) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = SIZE_SHRINK_CENTER
	pill.mouse_filter = MOUSE_FILTER_IGNORE
	var box := AppTheme.box(fill, AppTheme.RADIUS_PILL)
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	box.content_margin_left = 24 if coin else 10
	box.content_margin_right = 10
	pill.add_theme_stylebox_override("panel", box)
	if coin:
		pill.draw.connect(func() -> void:
			var center := Vector2(14.0, pill.size.y * 0.5)
			pill.draw_circle(center, 6.0, AppTheme.ACCENT_EDGE)
			pill.draw_circle(center, 4.5, AppTheme.ACCENT)
		)
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", AppTheme.display(700))
	label.add_theme_font_size_override("font_size", AppTheme.SIZE_CAPTION)
	label.add_theme_color_override("font_color", ink)
	pill.add_child(label)
	return pill


## A lista de amigos para mandar `id`. Como a compra, dois toques: o primeiro
## troca o nome do amigo por "Confirmar", o segundo manda.
func _pick_friend(id: String) -> void:
	Sound.play(Sound.Cue.TAP)
	_confirming = ""
	_picker = Control.new()
	_picker.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_picker.mouse_filter = MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = AppTheme.BACKGROUND
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_picker.add_child(shade)
	var safe := SafeAreaMargin.new()
	for side in ["left", "top", "right", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 16)
	safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_picker.add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	safe.add_child(column)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Presentear"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.theme_type_variation = &"GhostButton"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.pressed.connect(_close_picker)
	header.add_child(cancel)
	column.add_child(header)
	var hint := Label.new()
	hint.text = "%s por %d moedas. Seu amigo ganha na hora e abre na caixa de presentes." % [GiftsPanel.contents_text({"item": id}), int(Account.prices.get(id, 0))]
	hint.theme_type_variation = &"Hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for friend: Dictionary in Friends.sorted():
		var who := Button.new()
		var name := str(friend.get("name", ""))
		who.text = name if not name.is_empty() else "Amigo"
		who.custom_minimum_size = Vector2(0, 52)
		who.focus_mode = FOCUS_NONE
		who.theme_type_variation = &"GhostButton"
		who.pressed.connect(_on_friend.bind(who, str(friend.get("id", "")), id))
		list.add_child(who)
	add_child(_picker)


func _close_picker() -> void:
	if is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null
	_confirming = ""


func _on_friend(button: Button, friend: String, id: String) -> void:
	Sound.play(Sound.Cue.TAP)
	if _confirming != friend:
		# O toque anterior em outro amigo volta ao nome dele.
		for other: Button in button.get_parent().get_children():
			if other.has_meta(&"name"):
				other.text = other.get_meta(&"name")
				other.theme_type_variation = &"GhostButton"
		_confirming = friend
		button.set_meta(&"name", button.text)
		button.text = "Confirmar para %s" % button.text
		button.theme_type_variation = &"PrimaryButton"
		return
	button.disabled = true
	var name: String = button.get_meta(&"name", "")
	var code := await Account.send_gift(friend, id)
	if not is_inside_tree():
		return
	_close_picker()
	match code:
		200:
			_toast.show_message("Presente mandado para %s." % name, Banner.Kind.INFO)
		402:
			var missing := int(Account.prices.get(id, 0)) - maxi(Account.coins, 0)
			_toast.show_message("Faltam %d moedas." % missing, Banner.Kind.ALERT)
		409:
			_toast.show_message("%s já tem esse item." % name, Banner.Kind.ALERT)
		_:
			_toast.show_message("Não deu para presentear agora. Tente de novo.", Banner.Kind.DANGER)
	_fill()


## A amostra do item. `id` vazio é o padrão do encaixe.
func _swatch(slot: String, id: String, side := SWATCH) -> Control:
	var look := {slot: id}
	if slot in PROFILE_SLOTS:
		return _profile_swatch(slot, Account.look.merged(look, true), side)
	if slot == Cosmetics.CUE:
		var cue := CueSample.new()
		cue.clip_contents = true
		var skin := Cosmetics.cue_skin(look)
		# O alfa da textura é a máscara do metal (`cue_skin.gdshader`), e aqui
		# deixaria o ouro transparente: a amostra usa só a cor.
		var image := (skin["art"] if not skin.is_empty() else load(Cosmetics.DEFAULT_CUE) as Texture2D).get_image()
		image.convert(Image.FORMAT_RGB8)
		cue.texture = ImageTexture.create_from_image(image)
		cue.custom_minimum_size = Vector2(side, side)
		cue.size_flags_horizontal = SIZE_SHRINK_CENTER
		return cue
	if slot == Cosmetics.DECK:
		var cards := CardSample.new()
		cards.skin = Cosmetics.deck_of(look)
		cards.custom_minimum_size = Vector2(side * 1.3, side)
		cards.size_flags_horizontal = SIZE_SHRINK_CENTER
		return cards
	if slot == Cosmetics.TOKEN:
		var token := TokenSample.new(Cosmetics.token_of(look))
		token.custom_minimum_size = Vector2(side, side)
		token.size_flags_horizontal = SIZE_SHRINK_CENTER
		return token
	if slot != Cosmetics.BALL:
		var sample := BoardSample.new()
		# As peças aparecem no tabuleiro de quem compra, e o tabuleiro com as peças
		# de quem compra: a amostra mostra o item como ele vai aparecer na partida.
		sample.look = Account.look.merged(look, true)
		sample.custom_minimum_size = Vector2(side, side)
		sample.size_flags_horizontal = SIZE_SHRINK_CENTER
		return sample
	# A textura é o mapa da bola inteira; a amostra mostra o meio dele num círculo.
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(side, side)
	swatch.size_flags_horizontal = SIZE_SHRINK_CENTER
	swatch.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	swatch.add_theme_stylebox_override("panel", AppTheme.box(Color.WHITE, int(side / 2)))
	var art := TextureRect.new()
	art.texture = Cosmetics.ball_texture(look) if not id.is_empty() else load(Cosmetics.MARBLE)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	swatch.add_child(art)
	return swatch


## O meu cartão de perfil com o visual `look`: a capa, a foto com a moldura, o
## nome na cor e o título. É como os amigos o veem no perfil e na gaveta.
func _profile_card(look: Dictionary) -> Control:
	# A capa recortada pelos cantos do cartão, e o conteúdo por cima dela.
	var card := Control.new()
	card.custom_minimum_size = Vector2(0, 92)
	var cover := ProfileCover.rounded(look, AppTheme.RADIUS_LARGE)
	cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	card.add_child(cover)
	var framed := MarginContainer.new()
	framed.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		framed.add_theme_constant_override("margin_" + side, 14)
	card.add_child(framed)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	framed.add_child(line)
	var coaster := Coaster.new()
	coaster.custom_minimum_size = Vector2(64, 64)
	coaster.player_name = Prefs.player_name()
	coaster.photo = Account.local_avatar()
	coaster.frame = Cosmetics.frame_of(look)
	line.add_child(coaster)
	var words := VBoxContainer.new()
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	var name := Label.new()
	name.text = Prefs.player_name() if Prefs.has_name() else "Você"
	name.add_theme_font_override("font", AppTheme.display(700))
	name.add_theme_font_size_override("font_size", 22)
	ProfileStyle.paint_name(name, look)
	words.add_child(name)
	var title := ProfileStyle.title_label(look)
	if title != null:
		words.add_child(title)
	line.add_child(words)
	return card


## A amostra de um item de perfil, já com o resto do meu visual em volta.
func _profile_swatch(slot: String, look: Dictionary, side := SWATCH) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(side, side)
	box.size_flags_horizontal = SIZE_SHRINK_CENTER
	match slot:
		Cosmetics.FRAME:
			var coaster := Coaster.new()
			coaster.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			coaster.player_name = Prefs.player_name()
			coaster.photo = Account.local_avatar()
			coaster.frame = Cosmetics.frame_of(look)
			box.add_child(coaster)
		Cosmetics.BANNER:
			var cover := ProfileCover.rounded(look, AppTheme.RADIUS)
			cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			box.add_child(cover)
		_:
			# O título e a cor: o nome, ou o título, escrito como vai aparecer.
			box.draw.connect(func() -> void:
				box.draw_style_box(AppTheme.box(AppTheme.SURFACE_HIGH, AppTheme.RADIUS), Rect2(Vector2.ZERO, box.size))
			)
			var text := Label.new()
			text.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.add_theme_font_override("font", AppTheme.display(700))
			text.add_theme_font_size_override("font_size", 16)
			if slot == Cosmetics.TITLE:
				var title := Cosmetics.title_of(look)
				text.text = title if not title.is_empty() else "Sem título"
				text.add_theme_color_override("font_color", AppTheme.ACCENT if not title.is_empty() else AppTheme.TEXT_DIM)
				ProfileStyle.dress_title(text, look)
			else:
				text.text = Prefs.player_name() if Prefs.has_name() else "Você"
				ProfileStyle.paint_name(text, look)
			box.add_child(text)
	return box


## Compra `id` e já o põe em uso. A folha do item é a confirmação: um toque só.
func _buy(slot: String, id: String) -> void:
	_busy = true
	_fill()
	var code := await Account.buy(id)
	_busy = false
	if not is_inside_tree():
		return
	match code:
		200:
			_toast.show_message("%s é sua." % Cosmetics.name_of(id), Banner.Kind.INFO)
			await _equip(slot, id)
		402:
			var missing := int(Account.prices.get(id, 0)) - maxi(Account.coins, 0)
			_toast.show_message("Faltam %d moedas." % missing, Banner.Kind.ALERT)
		_:
			_toast.show_message("Não deu para comprar agora. Tente de novo.", Banner.Kind.DANGER)
	_fill()


func _equip(slot: String, id: String) -> void:
	_busy = true
	_fill()
	var ok := await Account.equip(slot, id)
	_busy = false
	if not is_inside_tree():
		return
	if not ok:
		_toast.show_message("Não deu para trocar agora. Tente de novo.", Banner.Kind.DANGER)
	_fill()


## A amostra de um tabuleiro: o miolo dele (d4, e4, d5, e5) na moldura, com a casa
## do último lance acesa e um cavalo de cada cor, para ver o contraste das peças.
## A amostra de um baralho do Uno: o verso e um 7 vermelho, um sobre o outro.
class CardSample:
	extends Control

	var skin := {}

	func _draw() -> void:
		var height := size.y * 0.86
		var width := UnoCardArt.width_for(height)
		var middle := size * 0.5
		UnoCardArt.draw_back(self, middle - Vector2(width * 0.32, 0.0), height, -0.12, 1.0, Color(0, 0, 0, 0), skin)
		UnoCardArt.draw_card(self, UnoRules.card(UnoRules.CardColor.RED, 7), middle + Vector2(width * 0.32, 0.0), height, 0.12, false, 1.0, Color(0, 0, 0, 0), skin)


## A amostra de uma peça do Metrópole: a peça em 3D, na cor do primeiro assento,
## vista de cima e de lado como na partida. Desenha uma vez só: a peça é parada.
class TokenSample:
	extends SubViewportContainer

	func _init(shape: String) -> void:
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(viewport)
		var token := MonopolyToken.build(0, MonopolyFace.PLAYER_COLORS[0], shape)
		# Meio de lado: de frente o pescoço esconde o corpo do dinossauro, e de lado o
		# violão e a estrela, que são planos, viram uma linha.
		token.rotation_degrees.y = 215.0
		viewport.add_child(token)
		var camera := Camera3D.new()
		camera.fov = 30.0
		# Fora da árvore ainda: o `look_at` precisaria da transformação global.
		var eye := Vector3(0.0, 0.62, 0.95)
		camera.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.2, 0.0) - eye), eye)
		viewport.add_child(camera)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
		viewport.add_child(sun)
		var fill := WorldEnvironment.new()
		fill.environment = Environment.new()
		fill.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		fill.environment.ambient_light_color = Color(0.75, 0.72, 0.9)
		fill.environment.ambient_light_energy = 0.7
		viewport.add_child(fill)


class BoardSample:
	extends Control

	## O visual que a amostra mostra: o tabuleiro e as peças dele.
	var look := {}

	func _draw() -> void:
		var skin := Cosmetics.board_skin(look)
		var side := minf(size.x, size.y)
		var outer := Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)
		draw_style_box(AppTheme.box(skin["frame"], int(side * 0.12)), outer)
		var inner := outer.grow(-side * 0.09)
		var cell := inner.size.x / 2.0
		for row in 2:
			for col in 2:
				var square := Board.square(3 + col, 4 - row)
				var dark := (Board.file_of(square) + Board.rank_of(square)) % 2 == 0
				var color: Color = skin["dark"] if dark else skin["light"]
				if row == 1 and col == 1:
					color = skin["last_dark"] if dark else skin["last"]
				BoardView.paint_square(self, skin, Rect2(inner.position + Vector2(col, row) * cell, Vector2.ONE * cell), square, color)
		PieceRenderer.draw_piece(
			self, Board.piece(Board.Side.BLACK, Board.Kind.KNIGHT), inner.position + Vector2(0.5, 0.5) * cell, cell,
			1.0, 1.0, false, Color.WHITE, 0.0, look
		)
		PieceRenderer.draw_piece(
			self, Board.piece(Board.Side.WHITE, Board.Kind.KNIGHT), inner.position + Vector2(1.5, 1.5) * cell, cell,
			1.0, 1.0, false, Color.WHITE, 0.0, look
		)


## A amostra de um taco: a metade de trás dele (antebraço e cabo, onde fica o
## desenho), na diagonal, num quadrado da cor do pano.
class CueSample:
	extends Control

	var texture: Texture2D = null

	func _draw() -> void:
		var side := minf(size.x, size.y)
		var outer := Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)
		draw_style_box(AppTheme.box(Color("1f6b4a"), int(side * 0.12)), outer)
		if texture == null:
			return
		var length := side * 1.25
		var thickness := side * 0.16
		var source_width := texture.get_width() * 0.48
		var source := Rect2(texture.get_width() - source_width, texture.get_height() * 0.25, source_width, texture.get_height() * 0.5)
		draw_set_transform(outer.get_center(), -PI / 4.0, Vector2.ONE)
		draw_texture_rect_region(texture, Rect2(-length * 0.5, -thickness * 0.5, length, thickness), source)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
