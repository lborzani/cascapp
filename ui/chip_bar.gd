class_name ChipBar
extends ScrollContainer

## Uma fileira de filtros que rola de lado. Duas telas a usam com listas
## diferentes: as categorias do catálogo na tela inicial, os jogos do catálogo no
## multiplayer.
##
## Uma fileira, e não uma grade de botões nem um menu suspenso. A grade come a
## altura que é do conteúdo, e o menu suspenso esconde as opções atrás de um
## toque, o que transforma "ver o que tem" em "lembrar de procurar". A fileira
## mostra as três ou quatro primeiras e diz, pela que fica cortada na borda, que
## há mais para o lado.
##
## O nó não filtra nada. Ele diz o que foi escolhido e quem escuta decide o que
## isso significa; é o que permite a tela inicial pôr os favoritos acima da lista
## sem que esta fileira saiba que favoritos existem.
##
## As listas saem de `Game`, e não da cena: acrescentar uma categoria ou um jogo
## é acrescentar uma entrada no catálogo, como em todo o resto do app.

signal selected(id: StringName)

## "Todos" é a ausência de filtro, e por isso é o vazio: quem pergunta
## `games_in` com ele recebe o catálogo, sem um caso especial para tratar.
const ALL := &""
## Os favoritos não são uma categoria do catálogo — são uma escolha do jogador —,
## mas na fileira ocupam o mesmo lugar, porque para quem toca são a mesma
## pergunta: "me mostre só estes".
const FAVORITES := &"fav"

const HEIGHT := 44.0

var current: StringName = ALL:
	set(value):
		current = value
		_restyle()

var _chips: Dictionary = {}
var _row: HBoxContainer = null


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# A barra de rolagem fica escondida: a fileira rola pelo arrasto, e um risco
	# cinza de 8 px sob seis chips é uma coisa que parece controle e não é.
	get_h_scroll_bar().modulate.a = 0.0

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", AppTheme.SPACE_S)
	add_child(_row)


## Monta os chips. Chamado pela tela e não no `_ready` porque o filho fica pronto
## antes do pai: uma fileira que se montasse sozinha teria de adivinhar qual das
## duas listas é a dela.
func setup(entries: Array, start: StringName = ALL) -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_chips.clear()
	for entry in entries:
		_add(entry["id"], str(entry["label"]))
	current = start


## Categorias do catálogo, com "Todos" e os favoritos na frente. É a lista da
## tela inicial.
static func category_items() -> Array:
	var items: Array = [
		{"id": ALL, "label": "Todos"},
		# A estrela sozinha, sem a palavra: ela é a mesma que está em cada cartão
		# de jogo, e um chip inteiro de "Favoritos" custaria a largura de uma
		# categoria.
		{"id": FAVORITES, "label": "★"},
	]
	for entry in Game.CATEGORIES:
		items.append({"id": entry["id"], "label": str(entry["label"])})
	return items


## Um chip por jogo jogável em rede, com "Todos" na frente. É a lista do
## multiplayer, onde o filtro é por **jogo** e não por família: quem procura sala
## procura a partida de um jogo, não uma categoria inteira.
##
## Só os que têm modo de rede: filtrar a lista de salas por um jogo que nunca
## abre sala é oferecer um filtro cujo resultado é sempre vazio.
static func online_game_items() -> Array:
	var items: Array = [{"id": ALL, "label": "Todos"}]
	for id in Game.games_in():
		if Game.entry_of(id).get("modes", []).has(Game.Mode.ONLINE):
			items.append({"id": id, "label": Game.game_title(id)})
	return items


func _add(id: StringName, label: String) -> void:
	var chip := Button.new()
	chip.text = label
	chip.custom_minimum_size = Vector2(0, HEIGHT - 4.0)
	chip.focus_mode = Control.FOCUS_NONE
	chip.pressed.connect(select.bind(id))
	_row.add_child(chip)
	_chips[id] = chip


## Escolhe um filtro como se o chip tivesse sido tocado. Público porque é por
## onde o teste entra — e porque uma tela que queira abrir já filtrada tem por
## onde pedir.
func select(id: StringName) -> void:
	# Tocar no filtro já escolhido não é um erro a corrigir, mas também não é uma
	# mudança: refiltrar a lista para ela ficar igual é um piscar sem motivo.
	if id == current:
		return
	Sound.play(Sound.Cue.TAP)
	current = id
	selected.emit(id)


func _restyle() -> void:
	for id in _chips:
		var chip: Button = _chips[id]
		chip.theme_type_variation = &"ChipSelected" if id == current else &"ChipButton"
