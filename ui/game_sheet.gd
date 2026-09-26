class_name GameSheet
extends Control

## A folha do jogo: como jogar este jogo, numa camada só.
##
## Eram duas telas — a dos modos e o diálogo de ajustes por cima dela —, e três
## toques entre escolher o jogo e começar. Aqui o modo são abas no topo da folha,
## os ajustes **daquele modo** ficam logo abaixo, e um botão termina.
##
## Cada seção aparece só onde significa alguma coisa: damas não pergunta ritmo,
## uma partida contra o bot não pergunta quem pode entrar, e o Ludo não pergunta
## quantos são. Uma escolha oferecida onde ela não vale é pior que escolha
## nenhuma — o jogador mexe nela, nada acontece, e passa a desconfiar do resto.
##
## **A folha não navega.** Ela avisa `confirmed(mode)` e quem a abriu decide; o
## caminho de verdade está em [method launch], que é o mesmo para as duas telas
## que a mostram — o cardápio de Jogos e a fileira de Online.

signal confirmed(mode: int)
signal closed

const SLIDE := 0.22
const PAIRING_SCENE := "res://scenes/pairing.tscn"
const BOMBER_LOBBY_SCENE := "res://scenes/bomber_lobby.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var mode := Game.Mode.HOTSEAT
var game_id: StringName = &""

var _panel: PanelContainer = null
## O suporte que desliza. Ver [method _init].
var _slider: Control = null
var _scrim: ColorRect = null
var _title: Label = null
var _meta: Label = null
var _icon: Coaster = null
var _segments: SegmentedControl = null
var _modes: Array[int] = []
var _sections := {}
var _players: HBoxContainer = null
var _clock: GridContainer = null
var _formats: GridContainer = null
var _levels: HBoxContainer = null
var _sides: HBoxContainer = null
var _visibility: HBoxContainer = null
var _start: Button = null
var _unavailable: Label = null
var _rules_link: Button = null


## Os modos que este jogo oferece **neste build**, na ordem da folha. Duas
## perguntas separadas: o catálogo aceita o modo, e o aparelho consegue executá-lo
## (uma sala precisa de servidor).
static func modes_for(id: StringName) -> Array[int]:
	# A sala primeiro, porque é a que precisa de decisão (código, quem entra); o
	# resto começa na hora. Lista aqui dentro e não em constante: `Game` é autoload,
	# e autoload não entra em constante.
	var order: Array[int] = [Game.Mode.ONLINE, Game.Mode.HOTSEAT, Game.Mode.SOLO]
	var available: Array[int] = []
	for candidate in order:
		if Game.mode_available(candidate, id):
			available.append(candidate)
	return available


## O caminho depois do "Começar", igual para toda tela que mostra a folha.
static func launch(tree: SceneTree, chosen_mode: int) -> void:
	if chosen_mode == Game.Mode.ONLINE:
		Game.mode = Game.Mode.ONLINE
		Game.role = Game.Role.HOST
		# O Bomberman fala com o servidor autoritativo, e não com o relay: vai para
		# o lobby próprio dele. Código vazio quer dizer criar sala.
		if Game.game_id == Game.BOMBERMAN:
			BomberNet.pending_code = ""
			tree.change_scene_to_file(BOMBER_LOBBY_SCENE)
			return
		tree.change_scene_to_file(PAIRING_SCENE)
		return
	if chosen_mode == Game.Mode.SOLO:
		Game.start_solo(Game.game_id)
	else:
		Game.start_hotseat(Game.game_id)
	tree.change_scene_to_file(Game.match_scene())


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_scrim = ColorRect.new()
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.color = AppTheme.SCRIM
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	# A folha sobe animada, e quem se move é este suporte de tela cheia, não o
	# painel. O painel é ancorado embaixo e cresce para cima; escrever `position`
	# num `Control` ancorado reescreve os offsets dele, e a animação terminava
	# em `position.y = 0` — a folha ficava presa no topo da tela, com a lista
	# aparecendo embaixo dela. O suporte descansa em zero, que é o lugar certo
	# dele, e o painel nunca tem a posição escrita.
	_slider = Control.new()
	_slider.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slider)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := AppTheme.box(AppTheme.SURFACE, 0)
	style.corner_radius_top_left = AppTheme.RADIUS_LARGE
	style.corner_radius_top_right = AppTheme.RADIUS_LARGE
	style.border_width_top = 2
	style.border_color = AppTheme.LINE_SOFT
	style.content_margin_left = AppTheme.SCREEN_PAD
	style.content_margin_right = AppTheme.SCREEN_PAD
	style.content_margin_top = AppTheme.SPACE_M
	style.content_margin_bottom = AppTheme.SPACE_XL
	_panel.add_theme_stylebox_override("panel", style)
	_slider.add_child(_panel)
	_panel.add_child(_build_body())


func _build_body() -> VBoxContainer:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", AppTheme.SPACE_M)

	var grab := ColorRect.new()
	grab.color = Color(AppTheme.TEXT_DIM, 0.45)
	grab.custom_minimum_size = Vector2(40, 4)
	grab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(grab)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", AppTheme.SPACE_M)
	body.add_child(header)
	_icon = Coaster.new()
	_icon.custom_minimum_size = Vector2(54, 54)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 0)
	header.add_child(words)
	_title = Label.new()
	_title.theme_type_variation = &"Title"
	words.add_child(_title)
	_meta = Label.new()
	_meta.theme_type_variation = &"Hint"
	words.add_child(_meta)

	# "Como jogar" no cabeçalho, ao lado do nome: é a pergunta de quem abriu a
	# folha de um jogo que não conhece, e ela vem antes de escolher o modo.
	_rules_link = Button.new()
	_rules_link.text = "Como jogar"
	_rules_link.flat = true
	_rules_link.focus_mode = Control.FOCUS_NONE
	_rules_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rules_link.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	for state_name: String in ["font_color", "font_hover_color"]:
		_rules_link.add_theme_color_override(state_name, AppTheme.ACCENT)
	_rules_link.add_theme_color_override("font_pressed_color", AppTheme.TEXT)
	_rules_link.pressed.connect(open_rules)
	header.add_child(_rules_link)

	_segments = SegmentedControl.new()
	_segments.selected.connect(_on_segment)
	body.add_child(_segments)

	_players = HBoxContainer.new()
	_players.add_theme_constant_override("separation", AppTheme.SPACE_S)
	body.add_child(_wrap("players", "Jogadores", _players))

	_clock = GridContainer.new()
	_clock.columns = 3
	_clock.add_theme_constant_override("h_separation", AppTheme.SPACE_S)
	_clock.add_theme_constant_override("v_separation", AppTheme.SPACE_S)
	body.add_child(_wrap("clock", "Ritmo", _clock))

	_formats = GridContainer.new()
	_formats.columns = 2
	_formats.add_theme_constant_override("h_separation", AppTheme.SPACE_S)
	_formats.add_theme_constant_override("v_separation", AppTheme.SPACE_S)
	body.add_child(_wrap("format", "Formato", _formats))

	_levels = HBoxContainer.new()
	_levels.add_theme_constant_override("separation", AppTheme.SPACE_S)
	body.add_child(_wrap("level", "Nível do bot", _levels))

	_sides = HBoxContainer.new()
	_sides.add_theme_constant_override("separation", AppTheme.SPACE_S)
	body.add_child(_wrap("side", "Você joga de", _sides))

	_visibility = HBoxContainer.new()
	_visibility.add_theme_constant_override("separation", AppTheme.SPACE_S)
	body.add_child(_wrap("visibility", "Quem pode entrar", _visibility))

	_unavailable = Label.new()
	_unavailable.theme_type_variation = &"Hint"
	_unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unavailable.text = "Este jogo não tem nenhum modo disponível neste build."
	_unavailable.visible = false
	body.add_child(_unavailable)

	_start = Button.new()
	_start.theme_type_variation = &"PrimaryButton"
	_start.custom_minimum_size.y = 52
	_start.pressed.connect(func() -> void: confirmed.emit(mode))
	body.add_child(_start)
	return body


## Legenda mais grupo, guardados juntos: esconder a escolha sem esconder o rótulo
## dela deixaria um "Ritmo" flutuando sobre a seção seguinte.
func _wrap(key: String, caption: String, control: Control) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", AppTheme.SPACE_XS)
	var label := Label.new()
	label.text = caption.to_upper()
	label.theme_type_variation = &"Caption"
	section.add_child(label)
	section.add_child(control)
	_sections[key] = section
	return section


func _section(key: String) -> Control:
	return _sections.get(key) as Control


## Abre "Como jogar" por cima da folha — na tela que a mostra, e não dentro dela:
## a página fecha sozinha e a folha continua lá, com o que já estava escolhido.
func open_rules() -> RulesPage:
	var host: Node = get_parent() if get_parent() != null else self
	return RulesPage.open(host, game_id)


func is_open() -> bool:
	return visible


func open(id: StringName, preferred_mode := -1) -> void:
	game_id = id
	Game.game_id = id
	_title.text = Game.game_title(id).to_upper()
	_meta.text = _meta_text(id)
	_icon.piece = Game.piece_of(id)
	_rules_link.visible = GameRulesDoc.load_for(id) != null
	_modes = modes_for(id)

	var labels := PackedStringArray()
	for candidate in _modes:
		labels.append(_mode_label(candidate, id))
	_segments.setup(labels, 0)
	_segments.visible = _modes.size() > 1
	_unavailable.visible = _modes.is_empty()
	_start.disabled = _modes.is_empty()

	_build_players()
	_build_clock()
	_build_formats()
	_build_levels()
	_build_sides()
	_build_visibility()

	var wanted := preferred_mode if preferred_mode in _modes else (
		_modes[0] if not _modes.is_empty() else Game.Mode.HOTSEAT
	)
	select_mode(wanted)

	if visible:
		return
	visible = true
	modulate.a = 0.0
	_slider.position.y = 40.0
	var rise := create_tween().set_parallel()
	rise.tween_property(self, "modulate:a", 1.0, SLIDE * 0.6)
	rise.tween_property(_slider, "position:y", 0.0, SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func select_mode(chosen: int) -> void:
	mode = chosen
	var index := _modes.find(chosen)
	if index >= 0:
		_segments.set_current(index)
	var online := chosen == Game.Mode.ONLINE
	var solo := chosen == Game.Mode.SOLO
	# Nível e cor só existem onde há escolha: o bot do Ludo é uma heurística fixa,
	# e lá as cores são quatro e vêm do assento, não de um par de botões.
	var tunable := solo and Game.bot_levels(game_id)
	_section("players").visible = not Game.players_range(game_id).is_empty()
	_section("clock").visible = Game.supports_clock(game_id)
	_section("format").visible = not Game.formats_of(game_id).is_empty()
	_section("level").visible = tunable
	_section("side").visible = tunable
	_section("visibility").visible = online
	_start.text = ("Criar sala" if online else "Começar").to_upper()


func _on_segment(index: int) -> void:
	if index < 0 or index >= _modes.size():
		return
	select_mode(_modes[index])


func _mode_label(candidate: int, id: StringName) -> String:
	match candidate:
		Game.Mode.ONLINE:
			return "Online"
		Game.Mode.SOLO:
			return "Contra bots" if Game.players_of(id) > 2 else "Contra bot"
		_:
			return "Aqui"


func _meta_text(id: StringName) -> String:
	var span := Game.players_range(id)
	var players := (
		"%d a %d jogadores" % [int(span[0]), int(span[1])] if not span.is_empty()
		else "%d jogadores" % Game.players_of(id)
	)
	var category := ""
	for entry: Dictionary in Game.CATEGORIES:
		if entry["id"] == Game.category_of(id):
			category = String(entry["label"]).to_lower()
	return players if category.is_empty() else "%s · %s" % [players, category]


## Os botões saem das listas do catálogo, e não desenhados um a um: acrescentar um
## ritmo ou um formato passa a ser uma linha de lista, sem mexer em layout.
func _chip(label: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	button.pressed.connect(on_press)
	return button


func _mark(group: Node, index: int) -> void:
	for position in group.get_child_count():
		var button: Button = group.get_child(position)
		button.theme_type_variation = &"ChipSelected" if position == index else &"ChipButton"


func _clear(group: Node) -> void:
	for child in group.get_children():
		group.remove_child(child)
		child.queue_free()


func _build_players() -> void:
	_clear(_players)
	var span := Game.players_range(game_id)
	if span.is_empty():
		return
	for count in range(int(span[0]), int(span[1]) + 1):
		_players.add_child(_chip(str(count), _select_players.bind(count)))
	_select_players(Game.players_of(game_id))


func _select_players(count: int) -> void:
	Game.table_size = count
	var span := Game.players_range(game_id)
	if span.is_empty():
		return
	_mark(_players, count - int(span[0]))


func _build_clock() -> void:
	_clear(_clock)
	if not Game.supports_clock(game_id):
		return
	for index in Game.TIME_CONTROLS.size():
		_clock.add_child(_chip(str(Game.TIME_CONTROLS[index]["label"]), _select_clock.bind(index)))
	_select_clock(Game.time_control)


func _select_clock(index: int) -> void:
	Game.time_control = index
	_mark(_clock, index)


func _build_formats() -> void:
	_clear(_formats)
	var formats := Game.formats_of(game_id)
	for index in formats.size():
		_formats.add_child(_chip(str(formats[index]["label"]), _select_format.bind(index)))
	if not formats.is_empty():
		_select_format(_format_index())


## O que fica guardado é o **valor** — o número de rodadas, a regra da sinuca —, e
## não o índice: é ele que as regras leem e que viaja pela rede, e guardar o índice
## obrigaria os dois lados a concordar sobre a ordem de uma lista de tela.
func _format_index() -> int:
	var formats := Game.formats_of(game_id)
	var wanted := Game.format_value(game_id)
	for index in formats.size():
		if int(formats[index]["value"]) == wanted:
			return index
	return 0


func _select_format(index: int) -> void:
	var formats := Game.formats_of(game_id)
	if formats.is_empty():
		return
	var safe := clampi(index, 0, formats.size() - 1)
	Game.set_format(int(formats[safe]["value"]), game_id)
	_mark(_formats, safe)


func _build_levels() -> void:
	_clear(_levels)
	if not Game.bot_levels(game_id):
		return
	for index in Bot.LEVELS.size():
		_levels.add_child(_chip(Bot.level_label(index), _select_level.bind(index)))
	_select_level(Game.bot_level)


func _select_level(index: int) -> void:
	Game.bot_level = index
	_mark(_levels, index)


func _build_sides() -> void:
	_clear(_sides)
	if not Game.bot_levels(game_id):
		return
	_sides.add_child(_chip("Brancas", _select_side.bind(Board.Side.WHITE)))
	_sides.add_child(_chip("Pretas", _select_side.bind(Board.Side.BLACK)))
	_select_side(Board.opponent(Game.bot_side))


## A cor escolhida é a do **jogador**; o que fica guardado é a do bot. Guardar a do
## bot é o que faz `Game.bot_turn()` responder sem precisar saber quem é quem.
func _select_side(side: int) -> void:
	Game.bot_side = Board.opponent(side)
	_mark(_sides, 0 if side == Board.Side.WHITE else 1)


func _build_visibility() -> void:
	_clear(_visibility)
	_visibility.add_child(_chip("Só com o código", _select_visibility.bind(false)))
	_visibility.add_child(_chip("Qualquer um", _select_visibility.bind(true)))
	_select_visibility(Game.listed_room)


## Privada é o padrão, e continua sendo depois de cada partida: o código é um
## segredo, e quem abre para um amigo não deve receber um estranho por não ter
## reparado numa opção.
func _select_visibility(listed: bool) -> void:
	Game.listed_room = listed
	_mark(_visibility, 1 if listed else 0)


func _on_scrim_input(event: InputEvent) -> void:
	# Tocar fora fecha, como toda folha do Android. Por [Tap]: um clique chega duas
	# vezes, e a mesma porta de toque do resto do app é uma porta só.
	if Tap.began(event):
		close()
