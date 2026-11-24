class_name GiftsPanel
extends Control

## A caixa de presentes: o que os amigos mandaram e ainda está fechado.
##
## Por cima da tela "Você", como a loja e as missões. Abrir é um toque: a caixa
## balança, o confete cai e o cartão mostra o que veio. Item já é da conta desde o
## envio (`pocketbase/pb_hooks/presentes.pb.js`); abrir só marca aberto e, no
## presentinho, paga as moedas. O kit do admin (`items`, com um bilhete) entrega
## os itens ao abrir, e o cartão aberto lista todos com um "Usar tudo".

signal closed

const BOX := 64.0

var _rows: VBoxContainer = null
var _note: Label = null
var _confetti: Confetti = null
var _toast: Banner = null
## Os presentes abertos nesta visita: id → o que veio. Ficam na tela, revelados,
## até ela fechar.
var _revealed := {}
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
	title.text = "Presentes"
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

	_note = Label.new()
	_note.theme_type_variation = &"Hint"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_rows)

	_confetti = Confetti.new()
	_confetti.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_confetti)
	_toast = Banner.new()
	safe.add_child(_toast)

	Account.gifts_changed.connect(_fill)
	_fill()
	Account.fetch_gifts()


## O que o voltar do sistema chama.
func close() -> void:
	closed.emit()
	queue_free()


## O que veio, em palavras: "Bola Madeira", "10 moedas" ou "Kit com 7 itens".
static func contents_text(gift: Dictionary) -> String:
	var kit: Array = gift.get("items", [])
	if not kit.is_empty():
		return "Kit com %d itens" % kit.size() if kit.size() > 1 else item_text(str(kit[0]))
	var item := str(gift.get("item", ""))
	if item.is_empty():
		return "%d moedas" % int(gift.get("coins", 0))
	return item_text(item)


## Um item em palavras, com o tipo na frente: "Moldura Pioneiro".
static func item_text(item: String) -> String:
	var slot := str(Cosmetics.ITEMS.get(item, {}).get("slot", ""))
	var kinds := {
		Cosmetics.BALL: "Bola", Cosmetics.CUE: "Taco", Cosmetics.PIECES: "Peças", Cosmetics.FINISH: "Acabamento",
		Cosmetics.FRAME: "Moldura", Cosmetics.BANNER: "Capa", Cosmetics.TITLE: "Título", Cosmetics.NAME_COLOR: "Cor do nome",
	}
	return ("%s %s" % [kinds[slot], Cosmetics.name_of(item)]) if kinds.has(slot) else Cosmetics.name_of(item)


## O que um presente aberto dá para usar e ainda não está em uso: `{encaixe: item}`.
## Item que este app não conhece fica de fora; de dois no mesmo encaixe, vale o último.
static func wearable(gift: Dictionary) -> Dictionary:
	var items: Array = gift.get("items", [])
	if items.is_empty():
		items = [gift.get("item", "")]
	var changes := {}
	for item: Variant in items:
		var slot := str(Cosmetics.ITEMS.get(str(item), {}).get("slot", ""))
		if not slot.is_empty() and str(Account.look.get(slot, "")) != str(item):
			changes[slot] = str(item)
	return changes


## Quem mandou: "De Ana", ou "Do cascapp" no kit de testador, que sai sem
## remetente (`from.id` vazio).
static func sender_text(gift: Dictionary) -> String:
	var from: Variant = gift.get("from")
	if not from is Dictionary or str(from.get("id", "")).is_empty():
		return "Do cascapp"
	var name := str(from.get("name", ""))
	return "De %s" % (name if not name.is_empty() else "um amigo")


## Presente que é de item (um só ou kit), e não de moedas.
static func has_items(gift: Dictionary) -> bool:
	return not str(gift.get("item", "")).is_empty() or not (gift.get("items", []) as Array).is_empty()


func _fill() -> void:
	if not Account.signed_in():
		_note.text = "Os presentes precisam da conta, e ela ainda não entrou. Confira a internet."
	elif Account.gifts.is_empty() and _revealed.is_empty():
		_note.text = "Nenhum presente fechado. Mande um presentinho pelo perfil de um amigo, ou um item pela loja."
	else:
		_note.text = "Toque para abrir."
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for id: String in _revealed:
		_rows.add_child(_card(_revealed[id], true))
	for gift: Dictionary in Account.gifts:
		if not _revealed.has(str(gift.get("id", ""))):
			_rows.add_child(_card(gift, false))


## Um presente: a caixa, quem mandou e o botão. Aberto, o que veio no lugar.
func _card(gift: Dictionary, open: bool) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var box := AppTheme.box(AppTheme.SURFACE_HIGH if open else AppTheme.SURFACE, AppTheme.RADIUS_LARGE)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, 14)
	card.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	var art := GiftBox.new()
	art.custom_minimum_size = Vector2(BOX, BOX)
	art.open = open
	art.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(art)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)
	var from := Label.new()
	from.text = sender_text(gift)
	from.theme_type_variation = &"Hint"
	words.add_child(from)
	var what := Label.new()
	what.text = contents_text(gift) if open else ("Presente" if has_items(gift) else "Presentinho")
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.add_theme_font_override("font", AppTheme.display(600))
	what.add_theme_font_size_override("font_size", AppTheme.SIZE_DISPLAY_M)
	if open:
		what.add_theme_color_override("font_color", AppTheme.ACCENT)
	words.add_child(what)

	if open:
		var message := str(gift.get("message", ""))
		if not message.is_empty():
			var note := Label.new()
			note.text = "“%s”" % message
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			words.add_child(note)
		var kit: Array = gift.get("items", [])
		if kit.size() > 1:
			for item: Variant in kit:
				var line := Label.new()
				line.text = "· " + item_text(str(item))
				line.theme_type_variation = &"Hint"
				words.add_child(line)
		var changes := wearable(gift)
		if not changes.is_empty():
			var use := Button.new()
			use.text = "Usar tudo" if changes.size() > 1 else "Usar"
			use.theme_type_variation = &"GhostButton"
			use.custom_minimum_size = Vector2(96, 44)
			use.focus_mode = FOCUS_NONE
			use.size_flags_vertical = SIZE_SHRINK_CENTER
			use.disabled = _busy
			use.pressed.connect(_use.bind(changes))
			row.add_child(use)
		return card
	var action := Button.new()
	action.text = "Abrir"
	action.theme_type_variation = &"PrimaryButton"
	action.custom_minimum_size = Vector2(96, 44)
	action.focus_mode = FOCUS_NONE
	action.size_flags_vertical = SIZE_SHRINK_CENTER
	action.disabled = _busy
	action.pressed.connect(_open.bind(gift, art))
	row.add_child(action)
	return card


func _open(gift: Dictionary, art: GiftBox) -> void:
	Sound.play(Sound.Cue.TAP)
	_busy = true
	# A caixa balança enquanto o servidor responde.
	art.pivot_offset = art.size * 0.5
	var shake := create_tween().set_loops(3)
	shake.tween_property(art, "rotation", 0.18, 0.06)
	shake.tween_property(art, "rotation", -0.18, 0.12)
	shake.tween_property(art, "rotation", 0.0, 0.06)
	var got := await Account.open_gift(str(gift.get("id", "")))
	if shake.is_valid():
		shake.kill()
	_busy = false
	if not is_inside_tree():
		return
	if got.is_empty():
		_toast.show_message("Não deu para abrir agora. Tente de novo.", Banner.Kind.DANGER)
		_fill()
		return
	_revealed[str(gift.get("id", ""))] = gift.merged(got, true)
	Sound.play(Sound.Cue.WIN if has_items(got) else Sound.Cue.CASH)
	_confetti.burst()
	_fill()


func _use(changes: Dictionary) -> void:
	Sound.play(Sound.Cue.TAP)
	_busy = true
	_fill()
	var ok := await Account.equip_all(changes)
	_busy = false
	if not is_inside_tree():
		return
	if not ok:
		_toast.show_message("Não deu para trocar agora. Tente de novo.", Banner.Kind.DANGER)
	_fill()


## Uma caixa de presente desenhada: a caixa, a tampa e a fita na cor do app.
## Aberta, a tampa sobe torta.
class GiftBox:
	extends Control

	var open := false

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := Rect2(w * 0.12, h * 0.42, w * 0.76, h * 0.52)
		var lid := Rect2(w * 0.06, h * 0.26, w * 0.88, h * 0.18)
		draw_style_box(AppTheme.box(AppTheme.DANGER, 6), body)
		draw_rect(Rect2(w * 0.44, body.position.y, w * 0.12, body.size.y), AppTheme.ACCENT)
		if open:
			draw_set_transform(Vector2(w * 0.5, h * 0.2), -0.35, Vector2.ONE)
			lid.position = Vector2(-lid.size.x * 0.5, -lid.size.y * 0.5)
		draw_style_box(AppTheme.box(AppTheme.DANGER_LIGHT, 6), lid)
		draw_rect(Rect2(lid.position.x + lid.size.x * 0.43, lid.position.y, lid.size.x * 0.14, lid.size.y), AppTheme.ACCENT)
		# O laço: dois círculos em cima da tampa.
		var knot := Vector2(lid.position.x + lid.size.x * 0.5, lid.position.y)
		draw_circle(knot + Vector2(-w * 0.09, -h * 0.05), w * 0.08, AppTheme.ACCENT)
		draw_circle(knot + Vector2(w * 0.09, -h * 0.05), w * 0.08, AppTheme.ACCENT)
		draw_circle(knot, w * 0.05, AppTheme.ACCENT_EDGE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
