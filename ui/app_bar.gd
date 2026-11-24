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
## A pílula de moedas da saudação do menu.
signal coins_pressed
## A pílula das missões da saudação do menu.
signal missions_pressed


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
var _coins: Button = null
var _missions: Button = null
## Missões prontas para resgatar: o número vermelho no canto da pílula.
var _missions_ready := 0
var _online := 0
var _alerts := 0
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

	# O saldo à vista leva à loja, que antes só se achava na aba Você.
	_coins = Button.new()
	_coins.name = "CoinsButton"
	_coins.theme_type_variation = &"GhostButton"
	_coins.focus_mode = Control.FOCUS_NONE
	_coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coins.add_theme_font_override("font", AppTheme.font(800))
	_coins.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
	var coin_pill := AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_ICON)
	coin_pill.content_margin_top = 10
	coin_pill.content_margin_bottom = 10
	coin_pill.content_margin_left = 32
	coin_pill.content_margin_right = 14
	for state: String in ["normal", "hover", "pressed"]:
		_coins.add_theme_stylebox_override(state, coin_pill)
	_coins.pressed.connect(func() -> void: coins_pressed.emit())
	_coins.draw.connect(func() -> void:
		var center := Vector2(18.0, _coins.size.y * 0.5)
		_coins.draw_circle(center, 8.0, AppTheme.ACCENT_EDGE)
		_coins.draw_circle(center, 6.0, AppTheme.ACCENT)
	)
	_greeting.add_child(_coins)
	set_coins(-1)

	# As missões: só o ícone, para caber ao lado das moedas e dos amigos num
	# celular em pé. O número de prontas aparece no canto, como os pedidos de
	# amizade na pílula dos amigos.
	_missions = Button.new()
	_missions.name = "MissionsButton"
	_missions.tooltip_text = "Missões"
	_missions.theme_type_variation = &"GhostButton"
	_missions.focus_mode = Control.FOCUS_NONE
	_missions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_missions.custom_minimum_size = Vector2(44, 44)
	var mission_pill := AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_ICON)
	for state: String in ["normal", "hover", "pressed"]:
		_missions.add_theme_stylebox_override(state, mission_pill)
	_missions.pressed.connect(func() -> void: missions_pressed.emit())
	_missions.draw.connect(_draw_missions)
	_greeting.add_child(_missions)

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


## O saldo de moedas; negativo é "ainda não sabemos" (sem conta), e mostra "—".
func set_coins(count: int) -> void:
	if _coins != null:
		_coins.text = str(count) if count >= 0 else "—"


## Quantas coisas esperam o jogador na gaveta (pedidos de amizade recebidos):
## uma bolinha vermelha no canto da pílula. Zero apaga.
func set_alerts(count: int) -> void:
	_alerts = count
	if _friends != null:
		_friends.queue_redraw()


func alerts() -> int:
	return _alerts


## Quantas missões estão prontas para resgatar; zero apaga o número.
func set_missions_ready(count: int) -> void:
	_missions_ready = count
	if _missions != null:
		_missions.queue_redraw()


## Um alvo: três anéis e o centro na cor do app.
func _draw_missions() -> void:
	var center := _missions.size * 0.5
	_missions.draw_arc(center, 11.0, 0.0, TAU, 32, AppTheme.TEXT_DIM, 2.0, true)
	_missions.draw_arc(center, 6.5, 0.0, TAU, 24, AppTheme.TEXT_DIM, 2.0, true)
	_missions.draw_circle(center, 2.5, AppTheme.ACCENT)
	if _missions_ready > 0:
		var badge := Vector2(_missions.size.x - 6.0, 6.0)
		_missions.draw_circle(badge, 9.0, AppTheme.DANGER)
		var font := AppTheme.font(800)
		var text := str(mini(_missions_ready, 9))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_missions.draw_string(font, badge + Vector2(-width * 0.5, 4.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, AppTheme.TEXT)


func _draw_online_dot() -> void:
	if _online > 0:
		_friends.draw_circle(Vector2(17.0, _friends.size.y * 0.5), 5.0, AppTheme.ACCENT)
	if _alerts > 0:
		_friends.draw_circle(Vector2(_friends.size.x - 4.0, 4.0), 6.0, AppTheme.DANGER)


## Título de aba, grande como no protótipo ("Online"): sem voltar à esquerda, ele
## é a única coisa da barra.
func headline() -> void:
	_label.add_theme_font_override("font", AppTheme.display(700))
	_label.add_theme_font_size_override("font_size", 30)
