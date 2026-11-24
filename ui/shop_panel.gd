class_name ShopPanel
extends Control

## A loja: o saldo, os itens à venda e os já comprados para usar.
##
## Por cima da tela "Você", como o histórico: fechar devolve a tela como estava.
## Tudo passa pela conta (`Account.buy`, `Account.equip`): o preço e o saldo são
## do servidor, e sem conta a loja só mostra. Comprar pede dois toques — o
## primeiro troca o preço por "Confirmar" — e o item comprado já entra em uso.

signal closed

const SWATCH := 92.0
## As abas: `[encaixes, rótulo]`, na ordem da tela. Aba de mais de um encaixe
## mostra uma seção por encaixe, com o título de `SECTIONS`.
const TABS := [
	[[Cosmetics.BALL], "Bola"],
	[[Cosmetics.CUE], "Taco"],
	[[Cosmetics.PIECES, Cosmetics.FINISH], "Peças"],
	[[Cosmetics.FRAME, Cosmetics.BANNER, Cosmetics.TITLE, Cosmetics.NAME_COLOR], "Perfil"],
]
const SECTIONS := {
	Cosmetics.PIECES: "Formato", Cosmetics.FINISH: "Acabamento",
	Cosmetics.FRAME: "Moldura", Cosmetics.BANNER: "Capa", Cosmetics.TITLE: "Título", Cosmetics.NAME_COLOR: "Cor do nome",
}
## Os encaixes do perfil: a aba deles abre com o meu cartão como os amigos o veem.
const PROFILE_SLOTS := [Cosmetics.FRAME, Cosmetics.BANNER, Cosmetics.TITLE, Cosmetics.NAME_COLOR]

var _balance: Label = null
var _note: Label = null
var _rows: VBoxContainer = null
var _tabs: SegmentedControl = null
## Os encaixes da aba aberta.
var _slots: Array = TABS[0][0]
var _toast: Banner = null
## O item à espera do segundo toque para comprar; vazio sem nenhum.
var _confirming := ""
var _busy := false


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
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	safe.add_child(column)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Loja"
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

	_balance = Label.new()
	_balance.add_theme_font_override("font", AppTheme.display(700))
	_balance.add_theme_font_size_override("font_size", 28)
	_balance.add_theme_color_override("font_color", AppTheme.ACCENT)
	column.add_child(_balance)
	_note = Label.new()
	_note.theme_type_variation = &"Hint"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)

	_tabs = SegmentedControl.new()
	var labels := PackedStringArray()
	for tab: Array in TABS:
		labels.append(tab[1])
	_tabs.setup(labels)
	# Cinco abas num celular em pé: com larguras iguais, "Tabuleiro" cortava e
	# "Bola" sobrava. Cada aba ganha largura pelo tamanho do rótulo.
	for button in _tabs._buttons:
		button.size_flags_stretch_ratio = maxf(1.0, button.text.length() / 4.5)
		button.add_theme_font_size_override("font_size", 14)
	_tabs.selected.connect(func(index: int) -> void:
		Sound.play(Sound.Cue.TAP)
		_slots = TABS[index][0]
		_confirming = ""
		_fill()
	)
	column.add_child(_tabs)

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
	_fill()
	if Account.prices.is_empty():
		Account.fetch_prices()


## O que o voltar do sistema chama.
func close() -> void:
	closed.emit()
	queue_free()


func _fill() -> void:
	_balance.text = "%s moedas" % (str(Account.coins) if Account.coins >= 0 else "—")
	if not Account.signed_in():
		_note.text = "A loja precisa da conta, e ela ainda não entrou. Confira a internet."
	elif Account.prices.is_empty():
		_note.text = "Carregando os preços…"
	else:
		_note.text = "Ganhe moedas terminando partidas contra o bot ou online, e com o bônus do dia."
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _slots.has(Cosmetics.FRAME):
		_rows.add_child(_profile_card(Account.look))
	for slot: String in _slots:
		if _slots.size() > 1:
			var heading := Label.new()
			heading.text = SECTIONS[slot]
			heading.theme_type_variation = &"SectionHeader"
			_rows.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		_rows.add_child(grid)
		grid.add_child(_card(slot, ""))
		for id in Cosmetics.of_slot(slot):
			if Account.prices.has(id) or id in Account.owned:
				grid.add_child(_card(slot, id))


## Um item: a amostra, o nome e o botão. `id` vazio é o padrão do encaixe.
func _card(slot: String, id: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var box := AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_LARGE)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, 12)
	card.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)

	column.add_child(_swatch(slot, id))

	var name := Label.new()
	name.text = Cosmetics.name_of(id) if not id.is_empty() else "Padrão"
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_override("font", AppTheme.display(600))
	name.add_theme_font_size_override("font_size", 18)
	column.add_child(name)

	var action := Button.new()
	action.custom_minimum_size = Vector2(0, 44)
	action.focus_mode = FOCUS_NONE
	var using := str(Account.look.get(slot, "")) == id
	var owned := id.is_empty() or Account.owns(id)
	if using:
		action.text = "Em uso"
		action.disabled = true
	elif owned:
		action.text = "Usar"
	elif _confirming == id:
		action.text = "Confirmar"
	else:
		action.text = "%d moedas" % int(Account.prices.get(id, 0))
		action.theme_type_variation = &"GhostButton"
	action.disabled = action.disabled or _busy or not Account.signed_in()
	action.pressed.connect(_on_action.bind(slot, id, owned))
	column.add_child(action)
	return card


## A amostra do item. `id` vazio é o padrão do encaixe.
func _swatch(slot: String, id: String) -> Control:
	var look := {slot: id}
	if slot in PROFILE_SLOTS:
		return _profile_swatch(slot, Account.look.merged(look, true))
	if slot == Cosmetics.CUE:
		var cue := CueSample.new()
		cue.clip_contents = true
		var skin := Cosmetics.cue_skin(look)
		# O alfa da textura é a máscara do metal (`cue_skin.gdshader`), e aqui
		# deixaria o ouro transparente: a amostra usa só a cor.
		var image := (skin["art"] if not skin.is_empty() else load(Cosmetics.DEFAULT_CUE) as Texture2D).get_image()
		image.convert(Image.FORMAT_RGB8)
		cue.texture = ImageTexture.create_from_image(image)
		cue.custom_minimum_size = Vector2(SWATCH, SWATCH)
		cue.size_flags_horizontal = SIZE_SHRINK_CENTER
		return cue
	if slot != Cosmetics.BALL:
		var sample := BoardSample.new()
		# As peças com o resto do visual de quem compra: a amostra mostra o item
		# como ele vai aparecer na partida.
		sample.look = Account.look.merged(look, true)
		sample.custom_minimum_size = Vector2(SWATCH, SWATCH)
		sample.size_flags_horizontal = SIZE_SHRINK_CENTER
		return sample
	# A textura é o mapa da bola inteira; a amostra mostra o meio dele num círculo.
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
	swatch.size_flags_horizontal = SIZE_SHRINK_CENTER
	swatch.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	swatch.add_theme_stylebox_override("panel", AppTheme.box(Color.WHITE, int(SWATCH / 2)))
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
	var framed := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		framed.add_theme_constant_override("margin_" + side, 14)
	var cover := Cosmetics.item_of(look, Cosmetics.BANNER)
	ProfileCover.behind(framed, cover)
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
	return framed


## A amostra de um item de perfil, já com o resto do meu visual em volta.
func _profile_swatch(slot: String, look: Dictionary) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(SWATCH, SWATCH)
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
			var cover := ProfileCover.new()
			cover.look = look
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
			else:
				text.text = Prefs.player_name() if Prefs.has_name() else "Você"
				ProfileStyle.paint_name(text, look)
			box.add_child(text)
	return box


func _on_action(slot: String, id: String, owned: bool) -> void:
	Sound.play(Sound.Cue.TAP)
	if owned:
		await _equip(slot, id)
		return
	if _confirming != id:
		_confirming = id
		_fill()
		return
	_confirming = ""
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


## A amostra das peças: o miolo do tabuleiro (d4, e4, d5, e5) na moldura, com a
## casa do último lance acesa e um cavalo de cada cor, no conjunto e no
## acabamento do visual.
class BoardSample:
	extends Control

	## O visual que a amostra mostra: o conjunto e o acabamento das peças.
	var look := {}

	func _draw() -> void:
		var side := minf(size.x, size.y)
		var outer := Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)
		draw_style_box(AppTheme.box(AppTheme.BOARD_FRAME, int(side * 0.12)), outer)
		var inner := outer.grow(-side * 0.09)
		var cell := inner.size.x / 2.0
		for row in 2:
			for col in 2:
				var square := Board.square(3 + col, 4 - row)
				var dark := (Board.file_of(square) + Board.rank_of(square)) % 2 == 0
				var color := AppTheme.BOARD_DARK if dark else AppTheme.BOARD_LIGHT
				if row == 1 and col == 1:
					color = AppTheme.LAST_MOVE_DARK if dark else AppTheme.LAST_MOVE
				draw_rect(Rect2(inner.position + Vector2(col, row) * cell, Vector2.ONE * cell), color)
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
