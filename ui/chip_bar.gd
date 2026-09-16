class_name ChipBar
extends Button

## O filtro da lista, num menu suspenso. Duas telas o usam com listas diferentes:
## as categorias do catálogo na tela inicial, os jogos do catálogo no
## multiplayer.
##
## ## Era uma fileira que rolava de lado, e ela não se deixava arrastar
##
## O argumento da fileira era bom: ela mostra as três ou quatro primeiras opções
## e diz, pela que fica cortada na borda, que há mais para o lado — enquanto um
## menu suspenso esconde tudo atrás de um toque e transforma "ver o que tem" em
## "lembrar de procurar".
##
## O que ele não previu é que **ela não rolava**. Cada opção é um `Button`, e um
## botão engole o arrasto antes de o `ScrollContainer` em volta dele ver que o
## dedo andou: no celular, arrastar a fileira era uma sequência de toques
## acidentais nos filtros por onde o dedo passava. Uma fileira que só rola se o
## dedo começar no vão entre dois chips não é uma fileira que rola.
##
## O menu suspenso troca uma opção visível por um toque — e é uma troca que vale
## quando a alternativa é um controle que responde errado. Todas as opções ficam
## visíveis de uma vez quando ele abre, que é mais do que a fileira mostrava.
##
## O nó continua não filtrando nada. Ele diz o que foi escolhido e quem escuta
## decide o que isso significa; é o que permite a tela inicial pôr os favoritos
## acima da lista sem que este controle saiba que favoritos existem.
##
## As listas saem de `Game`, e não da cena: acrescentar uma categoria ou um jogo é
## acrescentar uma entrada no catálogo, como em todo o resto do app.

signal selected(id: StringName)

## "Todos" é a ausência de filtro, e por isso é o vazio: quem pergunta `games_in`
## com ele recebe o catálogo, sem um caso especial para tratar.
const ALL := &""
## Os favoritos não são uma categoria do catálogo — são uma escolha do jogador —,
## mas no menu ocupam o mesmo lugar, porque para quem toca são a mesma pergunta:
## "me mostre só estes".
const FAVORITES := &"fav"

const HEIGHT := 44.0
## Recuo do texto até a borda, e a faixa reservada à seta.
const PAD := 16.0
const ARROW_BAND := 34.0

var current: StringName = ALL:
	set(value):
		current = value
		_refresh()

var _ids: Array[StringName] = []
var _labels: Array[String] = []
var _menu: PopupMenu = null
var _arrow: Control = null


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	focus_mode = Control.FOCUS_NONE
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	clip_text = true
	pressed.connect(_open)


func _ready() -> void:
	add_theme_constant_override("outline_size", 0)
	_menu = PopupMenu.new()
	_dress(_menu)
	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)

	# A seta é desenhada, e não um caractere de texto.
	#
	# "▾" dependeria da fonte do sistema ter o glifo, que é a mesma aposta que o
	# emoji da bomba do Bomberman perdeu — lá ele saía roxo num aparelho e como um
	# quadrado vazio noutro. Dois traços custam menos que essa dúvida, e são o
	# mesmo traço da seta do cartão de jogo.
	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_arrow.custom_minimum_size.x = ARROW_BAND
	_arrow.offset_left = -ARROW_BAND
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	_refresh()


## Monta as opções. Chamado pela tela e não no `_ready` porque o filho fica
## pronto antes do pai: um filtro que se montasse sozinho teria de adivinhar qual
## das duas listas é a dele.
func setup(entries: Array, start: StringName = ALL) -> void:
	_ids.clear()
	_labels.clear()
	for entry in entries:
		_ids.append(entry["id"])
		_labels.append(str(entry["label"]))
	current = start


## Categorias do catálogo, com "Todos" e os favoritos na frente. É a lista da
## tela inicial.
##
## "Favoritos" por extenso, e não a estrela sozinha: ela cabia num chip de
## fileira, onde a largura era o que faltava. Aqui o rótulo também é o que fica
## escrito no botão fechado, e um botão marcado só com "★" não diz o que está
## sendo mostrado.
static func category_items() -> Array:
	var items: Array = [
		{"id": ALL, "label": "Todos os jogos"},
		{"id": FAVORITES, "label": "Favoritos"},
	]
	for entry in Game.CATEGORIES:
		items.append({"id": entry["id"], "label": str(entry["label"])})
	return items


## Uma opção por jogo jogável em rede, com "Todos" na frente. É a lista do
## multiplayer, onde o filtro é por **jogo** e não por família: quem procura sala
## procura a partida de um jogo, não uma categoria inteira.
##
## Só os que têm modo de rede: filtrar a lista de salas por um jogo que nunca
## abre sala é oferecer um filtro cujo resultado é sempre vazio.
static func online_game_items() -> Array:
	var items: Array = [{"id": ALL, "label": "Todos os jogos"}]
	for id in Game.games_in():
		if Game.entry_of(id).get("modes", []).has(Game.Mode.ONLINE):
			items.append({"id": id, "label": Game.game_title(id)})
	return items


## Escolhe um filtro como se o menu tivesse sido usado. Público porque é por onde
## o teste entra — e porque uma tela que queira abrir já filtrada tem por onde
## pedir.
func select(id: StringName) -> void:
	# Escolher o filtro já escolhido não é um erro a corrigir, mas também não é
	# uma mudança: refiltrar a lista para ela ficar igual é um piscar sem motivo.
	if id == current:
		return
	Sound.play(Sound.Cue.TAP)
	current = id
	selected.emit(id)


func _open() -> void:
	if _ids.is_empty():
		return
	Sound.play(Sound.Cue.TAP)
	_menu.clear()
	for index in _ids.size():
		_menu.add_radio_check_item(_labels[index], index)
		_menu.set_item_checked(index, _ids[index] == current)
	# Da largura do botão, logo abaixo dele: o menu é a continuação do controle, e
	# um popup mais estreito que o botão que o abriu lê como outra coisa.
	_menu.reset_size()
	var at := get_screen_position() + Vector2(0.0, size.y + 4.0)
	_menu.popup(Rect2i(Vector2i(at), Vector2i(int(size.x), 0)))


func _on_menu_id(index: int) -> void:
	if index >= 0 and index < _ids.size():
		select(_ids[index])


func _refresh() -> void:
	if not is_node_ready():
		return
	var at := _ids.find(current)
	text = _labels[at] if at >= 0 else "Todos os jogos"
	# Latão quando há filtro, superfície quando não há: o botão fechado é a única
	# coisa na tela que diz que a lista está recortada, e sem essa pista uma lista
	# curta parece uma lista vazia.
	theme_type_variation = &"ChipButton" if current == ALL else &"ChipSelected"
	add_theme_constant_override("h_separation", 0)
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var style := get_theme_stylebox(state_name) as StyleBoxFlat
		if style == null:
			continue
		var own := style.duplicate() as StyleBoxFlat
		own.content_margin_left = PAD
		own.content_margin_right = ARROW_BAND
		add_theme_stylebox_override(state_name, own)
	_arrow.queue_redraw()


func _draw_arrow() -> void:
	var middle := _arrow.size * 0.5
	var arm := 5.0
	_arrow.draw_polyline(
		PackedVector2Array([
			middle + Vector2(-arm, -arm * 0.5),
			middle + Vector2(0.0, arm * 0.5),
			middle + Vector2(arm, -arm * 0.5),
		]),
		Color(AppTheme.ACCENT if current != ALL else AppTheme.TEXT_DIM, 0.9), 2.0, true
	)


## O menu no vocabulário do app: superfície alta, borda, latão no item sob o
## dedo. Aplicado aqui e não no tema global porque este é o único menu suspenso do
## app — pôr um capítulo de `PopupMenu` em `app_theme.gd` seria escrever um
## vocabulário inteiro para um usuário só.
func _dress(menu: PopupMenu) -> void:
	menu.add_theme_stylebox_override("panel", AppTheme.box(
		AppTheme.SURFACE_HIGH, AppTheme.RADIUS, AppTheme.BORDER, 1
	))
	menu.add_theme_stylebox_override("hover", AppTheme.box(
		Color(AppTheme.ACCENT, 0.22), AppTheme.RADIUS
	))
	menu.add_theme_color_override("font_color", AppTheme.TEXT)
	menu.add_theme_color_override("font_hover_color", AppTheme.TEXT)
	menu.add_theme_color_override("font_separator_color", AppTheme.TEXT_DIM)
	menu.add_theme_constant_override("v_separation", AppTheme.SPACE_XS)
	menu.add_theme_constant_override("item_start_padding", AppTheme.SPACE_S)
	menu.add_theme_constant_override("item_end_padding", AppTheme.SPACE_S)
