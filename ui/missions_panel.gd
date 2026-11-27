class_name MissionsPanel
extends Control

## As missões: as do dia, as conquistas e as de cada evento no ar, com o
## progresso e o botão de resgatar.
##
## Por cima da tela "Você", como a loja. Tudo vem do servidor
## (`Account.fetch_missions`), que é quem conta o progresso pelo prêmio de cada
## partida; aqui só se mostra e se resgata. O texto de cada missão sai do
## `title` que o admin escreveu ou, vazio, de [method describe].

signal closed

## Como folha (a tela inicial): uma `BottomSheet`, que sobe de baixo e fecha ao
## tocar fora. Falso, a tela inteira (a aba Você).
var sheet := false
var _sheet: BottomSheet = null

const DAILY := "daily"
const PERM := "perm"
const EVENT := "event"

var _note: Label = null
var _rows: VBoxContainer = null
var _tabs: SegmentedControl = null
var _toast: Banner = null
## As abas como estão na tela: `[track, chave do evento, rótulo]`.
var _shown_tabs: Array = []
var _tab := 0
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	if sheet:
		_build_sheet(column)
	else:
		var background := ColorRect.new()
		background.color = AppTheme.BACKGROUND
		background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(background)
		var safe := SafeAreaMargin.new()
		for side in ["left", "top", "right", "bottom"]:
			safe.add_theme_constant_override("margin_" + side, 16)
		safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(safe)
		safe.add_child(column)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Missões"
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

	_tabs = SegmentedControl.new()
	_tabs.selected.connect(func(index: int) -> void:
		Sound.play(Sound.Cue.TAP)
		_tab = index
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
	if sheet:
		# Na folha, o aviso vai na raiz: dentro do corpo ele viraria uma linha da
		# lista. A raiz não é contêiner, então a margem segura dá a largura e o
		# topo; sem ela o aviso nascia com largura zero, torto na borda esquerda.
		var safe := SafeAreaMargin.new()
		safe.mouse_filter = MOUSE_FILTER_IGNORE
		for side in ["left", "top", "right"]:
			safe.add_theme_constant_override("margin_" + side, 16)
		safe.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
		add_child(safe)
		safe.add_child(_toast)
	else:
		column.get_parent().add_child(_toast)

	Account.missions_changed.connect(_fill)
	_fill()
	Account.fetch_missions()
	if Account.paid.is_empty():
		# O nome do item do prêmio e a loja trancada precisam do catálogo.
		Account.fetch_prices()


## O que o voltar do sistema chama.
func close() -> void:
	if is_queued_for_deletion():
		return
	if _sheet != null:
		_sheet.close()  # avisa `closed` e sai depois da descida
		return
	closed.emit()
	queue_free()


## A folha: o conteúdo numa `BottomSheet`. Fechar por ela (toque fora) fecha
## o painel junto, depois da descida.
func _build_sheet(column: VBoxContainer) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_sheet = BottomSheet.new()
	column.size_flags_vertical = SIZE_EXPAND_FILL
	_sheet.body.add_child(column)
	_sheet.closed.connect(func() -> void: closed.emit())
	_sheet.tree_exited.connect(queue_free)
	add_child(_sheet)


## As abas que existem agora: Hoje e Conquistas sempre, e uma por evento no ar.
static func tabs_for(events: Array) -> Array:
	var tabs := [[DAILY, "", "Hoje"], [PERM, "", "Conquistas"]]
	for event: Dictionary in events:
		tabs.append([EVENT, str(event.get("key", "")), str(event.get("name", "Evento"))])
	return tabs


## O texto de uma missão sem `title`: "Vença 3 partidas de Uno".
static func describe(mission: Dictionary) -> String:
	var target := int(mission.get("target", 1))
	var game := StringName(str(mission.get("game", "")))
	var where := ""
	if game != &"":
		where = " de %s" % str(Game.entry_of(game).get("title", game))
	match str(mission.get("kind", "")):
		"win":
			return ("Vença 1 partida%s" % where) if target == 1 else ("Vença %d partidas%s" % [target, where])
		"variety":
			return "Jogue %d jogos diferentes" % target
		_:
			return ("Termine 1 partida%s" % where) if target == 1 else ("Termine %d partidas%s" % [target, where])


## O prêmio em palavras: "+30 moedas", "Título Veterano" ou os dois.
static func prize_text(mission: Dictionary) -> String:
	var parts := PackedStringArray()
	var item := str(mission.get("reward_item", ""))
	if not item.is_empty():
		var kind := "Título" if Cosmetics.ITEMS.get(item, {}).get("slot", "") == Cosmetics.TITLE else "Item"
		parts.append("%s %s" % [kind, Cosmetics.name_of(item)])
	var coins := int(mission.get("reward_coins", 0))
	if coins > 0:
		parts.append("+%d moedas" % coins)
	return " · ".join(parts)


func _fill() -> void:
	var tabs := tabs_for(Account.events)
	if tabs != _shown_tabs:
		_shown_tabs = tabs
		_tab = mini(_tab, tabs.size() - 1)
		var labels := PackedStringArray()
		for tab: Array in tabs:
			labels.append(tab[2])
		_tabs.setup(labels, _tab)
		# O nome do evento é do admin e pode ser longo: cada aba ganha largura
		# pelo rótulo, como na loja, e o que ainda não couber corta.
		for button in _tabs._buttons:
			button.size_flags_stretch_ratio = maxf(1.0, button.text.length() / 4.5)
			button.add_theme_font_size_override("font_size", 14)
	var tab: Array = _shown_tabs[_tab]
	if not Account.signed_in():
		_note.text = "As missões precisam da conta, e ela ainda não entrou. Confira a internet."
	elif tab[0] == DAILY:
		_note.text = "Três novas todo dia. Contam as partidas terminadas contra o bot ou online."
	elif tab[0] == PERM:
		_note.text = "Não zeram nunca, e pagam itens que não se compram na loja."
	else:
		_note.text = "Só até %s." % _ends_text(tab[1])
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var shown := Account.missions.filter(func(m: Dictionary) -> bool:
		return m.get("track") == tab[0] and (tab[0] != EVENT or m.get("event") == tab[1])
	)
	for mission: Dictionary in shown:
		_rows.add_child(_card(mission))


func _ends_text(event_key: String) -> String:
	for event: Dictionary in Account.events:
		if event.get("key") == event_key:
			var ends := Time.get_datetime_dict_from_unix_time(int(event.get("ends", 0)) - 3 * 3600)
			return "%02d/%02d, %02d:%02d" % [ends["day"], ends["month"], ends["hour"], ends["minute"]]
	return "o fim do evento"


## Uma missão: o texto, a barra, o prêmio e o botão.
func _card(mission: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	# Na folha o fundo já é `SURFACE`: o cartão sobe um tom para aparecer.
	var box := AppTheme.box(AppTheme.SURFACE_HIGH if sheet else AppTheme.SURFACE, AppTheme.RADIUS_LARGE)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, 14)
	card.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)

	var title := str(mission.get("title", ""))
	var name := Label.new()
	name.text = title if not title.is_empty() else describe(mission)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_font_override("font", AppTheme.display(600))
	name.add_theme_font_size_override("font_size", AppTheme.SIZE_DISPLAY_M)
	column.add_child(name)

	var target := maxi(1, int(mission.get("target", 1)))
	var progress := mini(target, int(mission.get("progress", 0)))
	var claimed: bool = mission.get("claimed", false)
	var complete := progress >= target
	column.add_child(_bar(float(progress) / target, complete))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	column.add_child(bottom)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	bottom.add_child(words)
	var count := Label.new()
	count.text = "%d de %d" % [progress, target]
	count.theme_type_variation = &"Hint"
	words.add_child(count)
	var prize := Label.new()
	prize.text = prize_text(mission)
	prize.add_theme_color_override("font_color", AppTheme.ACCENT)
	prize.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	words.add_child(prize)

	var action := Button.new()
	action.custom_minimum_size = Vector2(120, 44)
	action.focus_mode = FOCUS_NONE
	action.size_flags_vertical = SIZE_SHRINK_CENTER
	if claimed:
		action.text = "Resgatada"
		action.disabled = true
		action.theme_type_variation = &"GhostButton"
	elif complete:
		action.text = "Resgatar"
		action.theme_type_variation = &"PrimaryButton"
	else:
		action.text = "Em andamento"
		action.disabled = true
		action.theme_type_variation = &"GhostButton"
	action.disabled = action.disabled or _busy
	action.pressed.connect(_claim.bind(mission))
	bottom.add_child(action)
	return card


## A barra de progresso: o trilho e o preenchido, na fração `ratio`.
func _bar(ratio: float, complete: bool) -> Control:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, 10)
	track.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SURFACE_TOP if sheet else AppTheme.SURFACE_HIGH, 5))
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.SUCCESS if complete else AppTheme.ACCENT, 5))
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.visible = ratio > 0.0
	track.add_child(fill)
	return track


func _claim(mission: Dictionary) -> void:
	Sound.play(Sound.Cue.TAP)
	_busy = true
	_fill()
	var code := await Account.claim_mission(str(mission.get("key", "")))
	_busy = false
	if not is_inside_tree():
		return
	match code:
		200:
			_toast.show_message("Resgatada: %s." % prize_text(mission), Banner.Kind.INFO)
		404:
			_toast.show_message("Essa missão saiu do ar.", Banner.Kind.ALERT)
		409:
			_toast.show_message("Essa missão não está pronta para resgatar.", Banner.Kind.ALERT)
		_:
			_toast.show_message("Não deu para resgatar agora. Tente de novo.", Banner.Kind.DANGER)
	_fill()
