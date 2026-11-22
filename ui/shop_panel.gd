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
## As abas, uma por encaixe: `[encaixe, rótulo]`, na ordem da tela.
const TABS := [[Cosmetics.BALL, "Bola"], [Cosmetics.BOARD, "Tabuleiro"], [Cosmetics.FINISH, "Peças"]]

var _balance: Label = null
var _note: Label = null
var _grid: GridContainer = null
var _tabs: SegmentedControl = null
## O encaixe da aba aberta.
var _slot: String = TABS[0][0]
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
	_tabs.selected.connect(func(index: int) -> void:
		Sound.play(Sound.Cue.TAP)
		_slot = TABS[index][0]
		_confirming = ""
		_fill()
	)
	column.add_child(_tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	rows.add_child(_grid)

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
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_grid.add_child(_card(""))
	for id in Cosmetics.of_slot(_slot):
		if Account.prices.has(id) or id in Account.owned:
			_grid.add_child(_card(id))


## Um item: a amostra, o nome e o botão. `id` vazio é o padrão do encaixe.
func _card(id: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var box := AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_LARGE)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, 12)
	card.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)

	column.add_child(_swatch(id))

	var name := Label.new()
	name.text = Cosmetics.name_of(id) if not id.is_empty() else "Padrão"
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_override("font", AppTheme.display(600))
	name.add_theme_font_size_override("font_size", 18)
	column.add_child(name)

	var action := Button.new()
	action.custom_minimum_size = Vector2(0, 44)
	action.focus_mode = FOCUS_NONE
	var using := str(Account.look.get(_slot, "")) == id
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
	action.pressed.connect(_on_action.bind(id, owned))
	column.add_child(action)
	return card


## A amostra do item na aba aberta. `id` vazio é o padrão do encaixe.
func _swatch(id: String) -> Control:
	var look := {_slot: id}
	if _slot == Cosmetics.BOARD or _slot == Cosmetics.FINISH:
		var sample := BoardSample.new()
		# As peças aparecem no tabuleiro de quem compra, e o tabuleiro com as peças
		# de sempre: a amostra mostra o item como ele vai aparecer na partida.
		var mine := Account.look.merged(look, true)
		sample.skin = Cosmetics.board_skin(mine)
		sample.finish = Cosmetics.finish_of(mine)
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


func _on_action(id: String, owned: bool) -> void:
	Sound.play(Sound.Cue.TAP)
	if owned:
		await _equip(id)
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
			await _equip(id)
		402:
			var missing := int(Account.prices.get(id, 0)) - maxi(Account.coins, 0)
			_toast.show_message("Faltam %d moedas." % missing, Banner.Kind.ALERT)
		_:
			_toast.show_message("Não deu para comprar agora. Tente de novo.", Banner.Kind.DANGER)
	_fill()


func _equip(id: String) -> void:
	_busy = true
	_fill()
	var ok := await Account.equip(_slot, id)
	_busy = false
	if not is_inside_tree():
		return
	if not ok:
		_toast.show_message("Não deu para trocar agora. Tente de novo.", Banner.Kind.DANGER)
	_fill()


## A amostra de um tabuleiro: o miolo dele (d4, e4, d5, e5) na moldura, com a casa
## do último lance acesa e um cavalo de cada cor, para ver o contraste das peças.
class BoardSample:
	extends Control

	var skin: Dictionary = Cosmetics.DEFAULT_BOARD
	var finish := ""

	func _draw() -> void:
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
			1.0, 1.0, false, Color.WHITE, 0.0, finish
		)
		PieceRenderer.draw_piece(
			self, Board.piece(Board.Side.WHITE, Board.Kind.KNIGHT), inner.position + Vector2(1.5, 1.5) * cell, cell,
			1.0, 1.0, false, Color.WHITE, 0.0, finish
		)
