extends Control

## Como jogar o jogo já escolhido.
##
## O cabeçalho é o mesmo `GameChoice` da tela anterior, aceso e sem receber
## toque: o cartão que você tocou vira o título daqui. A resposta da primeira
## pergunta continua na tela enquanto a segunda é feita, e não custa um desenho
## novo — é o mesmo nó.
##
## Os modos vêm agrupados por **onde está o outro jogador**, porque é a única
## diferença que muda a decisão: uma sala precisa de internet e de espera, o
## mesmo aparelho e o bot começam na hora.
##
## Só **abrir** partida mora aqui. Entrar numa que já existe saiu para a tela
## inicial, e a assimetria é de propósito: quem abre decide o jogo e o ritmo, e
## quem entra recebe os dois do anfitrião — perguntar o jogo a quem só quer
## entrar era perguntar algo que a resposta dele nunca decidiu.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const PAIRING_SCENE := "res://scenes/pairing.tscn"
const BOMBER_LOBBY_SCENE := "res://scenes/bomber_lobby.tscn"

## O que "Começar" vai fazer quando o painel de ajustes for confirmado.
var _pending_mode := Game.Mode.HOTSEAT


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)

	_fill_bar()
	%HostButton.pressed.connect(_open_setup.bind(Game.Mode.ONLINE))
	%HotseatButton.pressed.connect(_open_setup.bind(Game.Mode.HOTSEAT))
	%SoloButton.pressed.connect(_open_setup.bind(Game.Mode.SOLO))
	%StartButton.pressed.connect(_confirm_setup)
	%SetupCancelButton.pressed.connect(_close_setup)
	%PrivateButton.pressed.connect(_select_visibility.bind(false))
	%PublicButton.pressed.connect(_select_visibility.bind(true))
	%WhiteButton.pressed.connect(_select_side.bind(Board.Side.WHITE))
	%BlackButton.pressed.connect(_select_side.bind(Board.Side.BLACK))
	%SetupLayer.visible = false

	_build_clock_grid()
	_build_players_row()
	_build_rounds_grid()
	_build_level_row()
	_apply_modes()


## O nome do jogo é o **título da tela**, e não um cartão dentro dela.
##
## Era um `GameChoice` em linha logo abaixo do topo: a peça e o nome, repetidos da
## tela anterior. Dizia a coisa certa no lugar errado — a pergunta "que jogo é
## este?" é a mesma que toda tela responde no título, e respondê-la duas vezes
## custava 76 px acima da ação principal.
##
## A volta é a seta da barra, e não um "Escolher outro jogo" no rodapé. O rodapé
## era um botão da largura da tela para a saída menos provável, num lugar onde o
## polegar encosta sem querer.
func _fill_bar() -> void:
	%AppBar.title = Game.game_title()
	%AppBar.leading = IconButton.Kind.BACK
	%AppBar.leading_pressed.connect(_back)


## Cada modo aparece só onde ele existe e funciona. Duas perguntas separadas: o
## jogo aceita esse modo (catálogo), e este aparelho consegue executá-lo (sala
## precisa de servidor). Oferecer o que não pode funcionar é pior que oferecer
## menos — o jogador toca, nada acontece, e passa a desconfiar da tela inteira.
##
## O destaque não é fixo no botão de sala: ele vai para a primeira ação que
## sobrou. Um "Criar partida" preenchido ao lado de uma seção vazia diria que a
## tela tem uma ação principal que ela não tem.
func _apply_modes() -> void:
	var online := Game.mode_available(Game.Mode.ONLINE)
	%OnlineCaption.visible = online
	%HostButton.visible = online

	var hotseat := Game.mode_available(Game.Mode.HOTSEAT)
	var solo := Game.mode_available(Game.Mode.SOLO)
	%LocalCaption.visible = hotseat or solo
	%HotseatButton.visible = hotseat
	# O número de jogadores sai do catálogo: o Ludo são quatro, e um botão que
	# promete dois manda três pessoas embora da mesa.
	%HotseatButton.text = "%d jogadores, um aparelho" % Game.players_of()
	%SoloButton.visible = solo
	# O espaço entre os dois grupos só existe quando há dois grupos.
	%GroupSpacer.visible = online and (hotseat or solo)

	# Vazio, e não `&"Button"`: variação vazia é o botão padrão do tema. Nomear o
	# tipo base cria uma variação que o tema não registra, e o botão perde o estilo.
	%HotseatButton.theme_type_variation = &"PrimaryButton" if not online else &""
	%UnavailableLabel.visible = not Game.playable()


func _back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## O painel de ajustes é uma tela por cima desta, e o gesto de voltar fecha ele
## primeiro. É a única tela do menu com duas camadas, e ignorar a de cima faria o
## gesto pular uma etapa que o jogador enxerga — ele veria a tela de trás sumir
## com o painel ainda aberto na cabeça dele.
func go_back() -> void:
	if %SetupLayer.visible:
		_close_setup()
		return
	_back()


# --- ajustes da partida ------------------------------------------------------


## Painel entre "quero jogar" e o tabuleiro. Existe para o ritmo, mas a forma é
## a que aguenta o resto: cada regra vira uma legenda e um grupo de opções dentro
## do mesmo `VBox`, sem inventar tela nova a cada uma.
##
## Fica atrás da ação, e não solto na tela: no corpo da tela ele disputava
## atenção com "Criar partida" mesmo quando ninguém ia mexer nele, que é a
## maioria das vezes.
func _open_setup(mode: int) -> void:
	_pending_mode = mode
	var title := Game.game_title()
	match mode:
		Game.Mode.ONLINE:
			%SetupTitle.text = "Criar partida"
			# "Ritmo" é palavra de relógio, e nem todo jogo tem um. Em Metrópole o
			# que quem entra herda é o **formato** — até a falência ou N rodadas —,
			# e prometer ritmo num jogo sem cronômetro seria prometer um controle
			# que a tela seguinte não tem.
			var inherited := "no ritmo escolhido aqui" if Game.supports_clock() else (
				"no formato escolhido aqui" if Game.supports_rounds()
				else "com as regras escolhidas aqui"
			)
			%SetupSubtitle.text = "%s • quem entrar joga %s." % [title, inherited]
		Game.Mode.SOLO:
			%SetupTitle.text = "Contra o bot"
			%SetupSubtitle.text = "%s • o bot joga sozinho, neste aparelho." % title
		_:
			%SetupTitle.text = "No mesmo aparelho"
			%SetupSubtitle.text = "%s • os dois jogam neste aparelho." % title

	# Cada seção aparece só onde significa alguma coisa. Uma escolha oferecida
	# onde ela não vale é pior que escolha nenhuma: o jogador mexe nela, nada
	# acontece, e ele passa a desconfiar do resto do painel.
	var solo := mode == Game.Mode.SOLO
	var online := mode == Game.Mode.ONLINE
	%VisibilityCaption.visible = online
	%VisibilityRow.visible = online
	# Nível e cor só existem onde há escolha: o bot do Ludo é uma heurística
	# fixa, e lá as cores são quatro e vêm do assento, não de um par de botões.
	var tunable := solo and Game.bot_levels()
	%LevelCaption.visible = tunable
	%LevelRow.visible = tunable
	%SideCaption.visible = tunable
	%SideRow.visible = tunable
	_select_visibility(Game.listed_room)
	_select_side(Board.opponent(Game.bot_side))

	# Damas não tem relógio, então a seção inteira sai.
	%ClockCaption.visible = Game.supports_clock()
	%ClockGrid.visible = Game.supports_clock()

	# E só Metrópole acaba por número de rodadas.
	%RoundsCaption.visible = Game.supports_rounds()
	%RoundsGrid.visible = Game.supports_rounds()

	# Tamanho da mesa só onde há mais de um. O Ludo são quatro cantos e os outros
	# são dois lados — perguntar ali seria uma escolha com uma resposta.
	var pick_size := not Game.players_range().is_empty()
	%PlayersCaption.visible = pick_size
	%PlayersRow.visible = pick_size

	%SetupLayer.visible = true


## Privada é o padrão, e continua sendo depois de cada partida: o código é um
## segredo, e quem abre para um amigo não deve receber um estranho por não ter
## reparado numa opção.
func _select_visibility(listed: bool) -> void:
	Game.listed_room = listed
	%PrivateButton.theme_type_variation = &"ChipButton" if listed else &"ChipSelected"
	%PublicButton.theme_type_variation = &"ChipSelected" if listed else &"ChipButton"


## A cor escolhida é a do **jogador**; o que fica guardado é a do bot. Guardar a
## do bot e não a do humano é o que faz `Game.bot_turn()` responder sem precisar
## saber quem é quem.
func _select_side(side: int) -> void:
	Game.bot_side = Board.opponent(side)
	var white := side == Board.Side.WHITE
	%WhiteButton.theme_type_variation = &"ChipSelected" if white else &"ChipButton"
	%BlackButton.theme_type_variation = &"ChipButton" if white else &"ChipSelected"


func _close_setup() -> void:
	%SetupLayer.visible = false


func _confirm_setup() -> void:
	%SetupLayer.visible = false
	if _pending_mode == Game.Mode.ONLINE:
		_open_pairing()
		return
	if _pending_mode == Game.Mode.SOLO:
		Game.start_solo(Game.game_id)
	else:
		Game.start_hotseat(Game.game_id)
	get_tree().change_scene_to_file(Game.match_scene())


## Botões gerados a partir de `Game.TIME_CONTROLS`, e não desenhados na cena:
## acrescentar um ritmo passa a ser uma linha na lista, sem mexer em layout.
func _build_clock_grid() -> void:
	for child in %ClockGrid.get_children():
		child.queue_free()
	for index in Game.TIME_CONTROLS.size():
		var button := Button.new()
		button.text = str(Game.TIME_CONTROLS[index]["label"])
		button.custom_minimum_size = Vector2(96, 46)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_select_clock.bind(index))
		%ClockGrid.add_child(button)
	_select_clock(Game.time_control)


## O ritmo escolhido ganha contorno e texto em latão; os outros ficam apagados.
## Preenchido, ele competiria com "Começar", que é a ação do painel — e o olho
## iria para a escolha em vez de para o que fazer com ela.
func _select_clock(index: int) -> void:
	Game.time_control = index
	var buttons := %ClockGrid.get_children()
	for position in buttons.size():
		var button: Button = buttons[position]
		button.theme_type_variation = &"ChipSelected" if position == index else &"ChipButton"


## Tamanho da mesa: um número por cadeira possível, do mínimo ao máximo do
## catálogo.
##
## Números soltos e não "2 jogadores / 3 jogadores": cinco botões com a mesma
## palavra repetida obrigam a ler a diferença em vez de vê-la, e a legenda em
## cima já disse que são jogadores.
func _build_players_row() -> void:
	for child in %PlayersRow.get_children():
		child.queue_free()
	var span := Game.players_range()
	if span.is_empty():
		return
	for count in range(int(span[0]), int(span[1]) + 1):
		var button := Button.new()
		button.text = str(count)
		button.custom_minimum_size = Vector2(0, 46)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_select_players.bind(count))
		%PlayersRow.add_child(button)
	_select_players(Game.players_of())


func _select_players(count: int) -> void:
	Game.table_size = count
	var span := Game.players_range()
	if span.is_empty():
		return
	var buttons := %PlayersRow.get_children()
	for position in buttons.size():
		var button: Button = buttons[position]
		var picked := int(span[0]) + position == count
		button.theme_type_variation = &"ChipSelected" if picked else &"ChipButton"
	# O botão de mesa local repete o número, e ele muda junto — um "4 jogadores,
	# um aparelho" atrás de um painel que diz 6 é a tela discordando de si mesma.
	%HotseatButton.text = "%d jogadores, um aparelho" % Game.players_of()


## Mesma construção do relógio: os formatos saem de `Game.ROUND_LIMITS`.
##
## Em duas colunas e não em linha: "Até a falência" é um rótulo longo, e quatro
## deles lado a lado ficariam cortados no meio num celular estreito.
func _build_rounds_grid() -> void:
	for child in %RoundsGrid.get_children():
		child.queue_free()
	for index in Game.ROUND_LIMITS.size():
		var button := Button.new()
		button.text = str(Game.ROUND_LIMITS[index]["label"])
		button.custom_minimum_size = Vector2(96, 46)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_select_rounds.bind(index))
		%RoundsGrid.add_child(button)
	_select_rounds(_rounds_index())


func _select_rounds(index: int) -> void:
	Game.round_limit = int(Game.ROUND_LIMITS[clampi(index, 0, Game.ROUND_LIMITS.size() - 1)]["rounds"])
	var buttons := %RoundsGrid.get_children()
	for position in buttons.size():
		var button: Button = buttons[position]
		button.theme_type_variation = &"ChipSelected" if position == index else &"ChipButton"


## Onde o formato guardado cai na lista. O que fica guardado é o **número de
## rodadas**, e não o índice: é ele que as regras leem e que viaja pela rede, e
## guardar o índice obrigaria os dois lados a concordar sobre a ordem da lista.
func _rounds_index() -> int:
	for index in Game.ROUND_LIMITS.size():
		if int(Game.ROUND_LIMITS[index]["rounds"]) == Game.round_limit:
			return index
	return 0


## Mesma construção do relógio, e pelo mesmo motivo: um nível a mais é uma
## entrada em `Bot.LEVELS`, não um botão desenhado na cena.
func _build_level_row() -> void:
	for child in %LevelRow.get_children():
		child.queue_free()
	for index in Bot.LEVELS.size():
		var button := Button.new()
		button.text = Bot.level_label(index)
		button.custom_minimum_size = Vector2(0, 46)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_select_level.bind(index))
		%LevelRow.add_child(button)
	_select_level(Game.bot_level)


func _select_level(index: int) -> void:
	Game.bot_level = index
	var buttons := %LevelRow.get_children()
	for position in buttons.size():
		var button: Button = buttons[position]
		button.theme_type_variation = &"ChipSelected" if position == index else &"ChipButton"


## Sempre como anfitrião: esta tela só abre partida. Entrar numa que já existe é
## a tela inicial, e nem passa por aqui.
func _open_pairing() -> void:
	Game.mode = Game.Mode.ONLINE
	Game.role = Game.Role.HOST
	# O Bomberman fala com o servidor autoritativo, e não com o relay: vai pro lobby
	# próprio dele. Código vazio = criar sala.
	if Game.game_id == Game.BOMBERMAN:
		BomberNet.pending_code = ""
		get_tree().change_scene_to_file(BOMBER_LOBBY_SCENE)
		return
	get_tree().change_scene_to_file(PAIRING_SCENE)
