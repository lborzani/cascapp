class_name AppBar
extends MarginContainer

## A barra superior das telas fora da partida: um botão à esquerda, o título, e
## um botão opcional à direita.
##
## Um nó só para as cinco telas, e não um cabeçalho desenhado em cada `.tscn`.
## Desenhados um a um eles já discordavam: o menu tinha logo, nome e engrenagem
## em 56 px de altura; entrar e criar tinham um título centralizado sem botão
## nenhum e a volta no rodapé; os ajustes tinham as duas coisas. Três cabeçalhos
## diferentes em três telas seguidas é o jogador reaprendendo onde ficam as
## coisas a cada passo.
##
## A regra que a barra impõe é a do Material, e é a que o Android inteiro usa: à
## esquerda é **de onde se sai** — a gaveta na primeira tela, a volta em todas as
## outras —, no meio é **onde se está**, e à direita é a ação da tela, se houver.
##
## O que ela **não** faz: navegar. Ela emite, e a tela decide — é o que permite a
## mesma barra ser a gaveta no menu e o `go_back()` numa tela de partida sendo
## criada, sem saber a diferença.

signal leading_pressed
signal action_pressed
## O botão de amigos da saudação do menu.
signal friends_pressed


var title := "":
	set(value):
		title = value
		if _label != null:
			_label.text = value

## Ícone do botão da esquerda: `BACK` nas telas que voltam, ou `-1` para nenhum —
## as abas são lugares, e não há de onde voltar num lugar.
var leading := IconButton.Kind.BACK:
	set(value):
		leading = value
		if _leading_button != null:
			_leading_button.visible = value >= 0
			if value >= 0:
				_leading_button.kind = value

## Ícone do botão da direita, ou nada. A tela inicial tem os ajustes ali; as
## telas que não têm ação própria deixam o lugar vazio em vez de inventarem uma.
var action := -1:
	set(value):
		action = value
		if _action_button != null:
			_action_button.visible = value >= 0
			if value >= 0:
				_action_button.kind = value

var _label: Label = null
var _leading_button: IconButton = null
var _friends: Button = null
var _online := 0
var _action_button: IconButton = null
var _greeting: HBoxContainer = null
var _greeting_name: Label = null
var _avatar: Coaster = null

const AVATAR := 48.0


func _init() -> void:
	custom_minimum_size.y = AppTheme.BAR_HEIGHT
	# A mesma margem do corpo da tela, e não a do Material (16 com alvos de 48).
	# O que importa é que as duas bordas da barra caiam na mesma coluna dos
	# cartões de baixo: com 8, o botão da direita sobrava 12 px para fora da
	# grade, e a tela tinha duas margens empilhadas discordando.
	add_theme_constant_override("margin_left", AppTheme.SCREEN_PAD)
	add_theme_constant_override("margin_right", AppTheme.SCREEN_PAD)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", AppTheme.SPACE_S)
	add_child(row)

	_leading_button = IconButton.new()
	_leading_button.kind = leading
	_leading_button.pressed.connect(func(): leading_pressed.emit())
	row.add_child(_leading_button)

	_label = Label.new()
	_label.text = title
	_label.theme_type_variation = &"Greeting"
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# O nome do jogador entra aqui, e nome de jogador não tem limite de bom senso.
	# Cortado com reticências, e não quebrado em duas linhas: a barra tem uma
	# altura só, e um título de duas linhas empurraria o conteúdo da tela.
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_label)

	_action_button = IconButton.new()
	_action_button.visible = false
	_action_button.pressed.connect(func(): action_pressed.emit())
	row.add_child(_action_button)


## O cabeçalho da tela inicial: a bolacha do jogador à esquerda (leva à aba Você,
## onde o nome se troca), "Bora jogar," e o nome em letreiro, e à direita a pílula
## dos amigos, que diz quantos estão online quando alguém está.
##
## Chamar de novo só troca o nome: é o que a tela faz quando as boas-vindas
## terminam, para a saudação mostrar o nome recém escolhido sem reabrir o app.
## `photo` é a foto da conta; sem ela a bolacha fica com a inicial. Vem de quem
## chama, e não do `Account`: a barra é do kit de UI e roda sem os autoloads.
func greet(player_name: String, photo: Texture2D = null) -> void:
	if _greeting == null:
		_build_greeting()
	_greeting_name.text = player_name
	_avatar.player_name = player_name
	_avatar.photo = photo


func _build_greeting() -> void:
	var row: HBoxContainer = _label.get_parent()
	_leading_button.visible = false
	_label.visible = false
	_action_button.visible = false

	_greeting = HBoxContainer.new()
	_greeting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_greeting.add_theme_constant_override("separation", AppTheme.SPACE_M)
	row.add_child(_greeting)
	row.move_child(_greeting, 0)

	# Um botão sem pele segurando a bolacha: a bolacha não recebe toque (ela é o
	# mesmo desenho dentro da partida, onde o toque é do que está em volta).
	var holder := Button.new()
	holder.theme_type_variation = &"IconButton"
	holder.focus_mode = Control.FOCUS_NONE
	holder.custom_minimum_size = Vector2(AVATAR, AVATAR)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.pressed.connect(func() -> void: action_pressed.emit())
	_greeting.add_child(holder)
	_avatar = Coaster.new()
	# O anel limão é do dono do aparelho: é a única bolacha desta tela.
	_avatar.ring = AppTheme.ACCENT
	_avatar.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_avatar)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", -4)
	_greeting.add_child(words)
	var hello := Label.new()
	hello.text = "Bora jogar,"
	hello.theme_type_variation = &"Hint"
	words.add_child(hello)
	_greeting_name = Label.new()
	_greeting_name.theme_type_variation = &"Greeting"
	_greeting_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(_greeting_name)

	_friends = Button.new()
	_friends.name = "FriendsButton"
	_friends.theme_type_variation = &"GhostButton"
	_friends.focus_mode = Control.FOCUS_NONE
	_friends.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_friends.add_theme_font_override("font", AppTheme.font(800))
	_friends.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	_friends.pressed.connect(func() -> void: friends_pressed.emit())
	_friends.draw.connect(_draw_online_dot)
	_greeting.add_child(_friends)
	set_online(0)


## Quantos amigos estão online agora. Zero mostra só "Amigos": um "0 online" é uma
## notícia que não é notícia.
func set_online(count: int) -> void:
	if _friends == null:
		return
	_online = count
	_friends.text = "%d online" % count if count > 0 else "Amigos"
	var pill := AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_ICON)
	pill.content_margin_top = 10
	pill.content_margin_bottom = 10
	pill.content_margin_left = 30 if count > 0 else 16
	pill.content_margin_right = 16
	for state: String in ["normal", "hover", "pressed"]:
		_friends.add_theme_stylebox_override(state, pill)
	_friends.queue_redraw()


func _draw_online_dot() -> void:
	if _online > 0:
		_friends.draw_circle(Vector2(17.0, _friends.size.y * 0.5), 5.0, AppTheme.ACCENT)


## Título de aba, grande como no protótipo ("Online"): sem voltar à esquerda, ele
## é a única coisa da barra.
func headline() -> void:
	_label.add_theme_font_override("font", AppTheme.display(700))
	_label.add_theme_font_size_override("font_size", 30)
