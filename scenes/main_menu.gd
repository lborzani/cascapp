extends Control

## A tela inicial: a coleção de jogos, com os favoritos na frente.
##
## ## O que a tela é
##
## Uma barra superior, uma fileira de filtros e uma grade de cartões. É o arranjo
## que o Android inteiro usa, e usá-lo aqui não é seguir moda: é aproveitar o que
## o jogador já sabe fazer antes de abrir o app. A gaveta está onde ele procura
## gaveta, os ajustes estão onde ele procura ajustes, e o conteúdo rola por baixo
## de uma barra que não sai do lugar.
##
## O cabeçalho é a saudação com o nome do jogador, e não o nome do app. O nome do
## app está na gaveta, junto do ícone — ele responde "que app é este", que é uma
## pergunta que se faz uma vez. "Olá, Fulano" responde "este app sabe quem eu
## sou", que é a pergunta que se refaz a cada abertura, e é o que justifica ter
## pedido o nome nas boas-vindas.
##
## ## Grade, e não lista
##
## Foi lista enquanto foram dois jogos: uma linha por jogo, o nome inteiro, sobra
## de tela embaixo. Com sete, a lista passou a rolar — e o sétimo jogo virou um
## jogo que ninguém vê. A grade de três colunas mostra nove cartões na mesma
## altura em que a lista mostrava quatro, e o que se perde é o espaço para uma
## legenda que ninguém lia.
##
## ## Favoritos na frente
##
## Quem volta ao app volta para o mesmo jogo. Os favoritos ficam acima do
## catálogo, separados por um rótulo de seção, e o resto continua ali embaixo na
## ordem do catálogo — a estrela adianta o caminho sem esconder nada.
##
## ## Para onde esta tela leva
##
## Tocar num jogo é escolher **criar** uma partida dele (`game_menu`). Entrar
## numa partida que já existe é outro destino, e está na gaveta: quem entra joga
## o que o anfitrião abriu, então escolher o jogo antes seria escolher uma coisa
## que a resposta dele não decide.
##
## Acrescentar um jogo continua sendo acrescentar uma entrada em `Game.GAMES`.

const GAME_MENU_SCENE := "res://scenes/game_menu.tscn"
const JOIN_SCENE := "res://scenes/join.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
## Espera entre o toque e a troca de tela. Curta o bastante para não ser
## percebida como demora, longa o bastante para o cartão aceso ser visto: sem
## ela, o toque não tem resposta nenhuma antes da tela seguinte aparecer.
const TAP_FEEDBACK := 0.13

## Três colunas numa tela de 432 px dão cartões de ~120, que é onde a peça ainda
## se reconhece e o nome ainda cabe em duas linhas. Com quatro, "Batalha Naval"
## vira duas linhas de quatro letras.
const COLUMNS := 3
const TILE_HEIGHT := 118.0

var _leaving := false


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)
	Game.reset_to_menu()
	if _resume_pending_scan():
		return

	%AppBar.title = "Olá, %s!" % Prefs.player_name()
	%AppBar.leading = IconButton.Kind.MENU
	%AppBar.action = IconButton.Kind.GEAR
	%AppBar.leading_pressed.connect(_open_drawer)
	%AppBar.action_pressed.connect(_open_settings)

	%Categories.setup(ChipBar.category_items())
	%Categories.selected.connect(_filter)
	_fill_games()
	_offer_rejoin()
	_greet()


## A partida de onde este aparelho caiu, no topo, acima do filtro.
##
## Acima de tudo porque é a única coisa na tela com gente esperando: os outros
## jogadores estão numa mesa com uma máquina no lugar de quem caiu. A grade de jogos
## continua lá embaixo para quem prefere começar outra.
func _offer_rejoin() -> void:
	if not Net.relay_available():
		return
	var pending := Prefs.pending_rejoin(int(Time.get_unix_time_from_system()))
	if pending.is_empty():
		return
	var card := ResumeCard.new()
	card.game_id = pending["game"]
	card.code = pending["code"]
	card.saved_at = pending["at"]
	card.resume_pressed.connect(_rejoin)
	card.dismissed.connect(func() -> void:
		Prefs.forget_rejoin()
		card.queue_free()
	)
	# Irmão do filtro, e não da grade: a grade é refeita a cada troca de filtro, e o
	# cartão sumiria no primeiro toque nela.
	var content := %Categories.get_parent()
	content.add_child(card)
	content.move_child(card, 0)


## Pela tela de entrar, e não direto daqui: é ela que sabe esperar a mesa
## responder, mostrar a espera e dizer por que não deu. O `join_info` é o mesmo
## caminho de um QR lido antes de o Android recolher o app.
func _rejoin(game_id: StringName, code: String) -> void:
	if _leaving:
		return
	_leaving = true
	Game.join_info = {"game": game_id, "code": code}
	get_tree().change_scene_to_file(JOIN_SCENE)


## A tela de boas-vindas da primeira abertura.
##
## Aqui e não numa cena própria antes do menu: ela é uma pergunta sobre o
## aparelho, não uma etapa do caminho. Como camada, o jogador já vê a grade de
## jogos atrás dela — o app se apresenta enquanto pergunta, em vez de pedir uma
## resposta antes de mostrar o que é.
##
## Depois do `_resume_pending_scan()`, que sai da função antes: quem abriu o app
## por um QR está no meio de entrar numa partida, e uma pergunta atravessada aí é
## uma pergunta na hora errada. Ele recebe as boas-vindas na próxima vez que
## abrir o app pelo ícone.
func _greet() -> void:
	if not WelcomePanel.pending():
		return
	var welcome := WelcomePanel.new()
	welcome.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(welcome)
	welcome.open()
	# O nome sai daqui, e a barra já foi escrita com o padrão: quem acabou de se
	# apresentar deve ver a saudação com o nome que escolheu, sem reabrir o app.
	welcome.tree_exited.connect(func() -> void:
		if is_inside_tree():
			%AppBar.title = "Olá, %s!" % Prefs.player_name()
	)


## A grade inteira vem de `Game.GAMES`, e não de cartões desenhados na cena.
##
## `continue`, e **não** `return`, para o jogo escondido: com `return`, esconder o
## terceiro jogo truncava a lista nele e o quarto e o quinto sumiam junto, sem
## erro nenhum.
func _fill_games() -> void:
	# `remove_child` antes do `queue_free`: o segundo só apaga no fim do quadro, e
	# entre trocar de filtro e o quadro acabar a tela teria as seções velhas por
	# baixo das novas.
	for child in %GameList.get_children():
		%GameList.remove_child(child)
		child.queue_free()

	var filter: StringName = %Categories.current
	if filter == ChipBar.FAVORITES:
		var starred := Game.favorite_games()
		if starred.is_empty():
			_add_hint("Nenhum favorito ainda.\nToque na estrela de um jogo para guardá-lo aqui.")
			return
		_add_grid(starred)
		return

	if filter != ChipBar.ALL:
		_add_grid(Game.games_in(filter))
		return

	# Em "Todos", os favoritos sobem — e saem de baixo. Repetidos nos dois lugares
	# eles pareceriam dois jogos de mesmo nome, que é o tipo de grade que faz o
	# jogador tocar no de cima para conferir se é o mesmo.
	var favorites := Game.favorite_games()
	var rest := Game.games_in()
	for id in favorites:
		rest.erase(id)
	if not favorites.is_empty():
		_add_caption("Favoritos")
		_add_grid(favorites)
	# O resto vem **por categoria**, e não numa grade só. Sete cartões seguidos
	# são sete cartões a comparar; em blocos de dois e três, a comparação é dentro
	# do bloco — que é a pergunta que o jogador realmente faz ("qual jogo de
	# tabuleiro eu quero?").
	for entry in Game.CATEGORIES:
		var ids: Array[StringName] = []
		for id in rest:
			if Game.category_of(id) == entry["id"]:
				ids.append(id)
		if ids.is_empty():
			continue
		_add_caption(str(entry["label"]))
		_add_grid(ids)


func _add_grid(ids: Array[StringName]) -> void:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", AppTheme.SPACE_M)
	grid.add_theme_constant_override("v_separation", AppTheme.SPACE_M)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%GameList.add_child(grid)
	for id in ids:
		grid.add_child(_tile(id))


func _tile(id: StringName) -> GameChoice:
	var card := GameChoice.new()
	card.custom_minimum_size = Vector2(0, TILE_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.title = Game.game_title(id)
	card.piece = Game.piece_of(id)
	card.art_id = id
	card.unavailable = not Game.playable(id)
	card.favoritable = true
	card.favorite = Prefs.is_favorite(id)
	card.chosen.connect(_choose.bind(card, id))
	card.favorite_toggled.connect(_toggle_favorite.bind(card, id))
	return card


## Rótulo de seção dentro da grade. Nasce aqui e não na cena porque as seções vêm
## e vão com o filtro: em "Cartas" não há favoritos para separar de coisa nenhuma.
func _add_caption(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SectionHeader"
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.custom_minimum_size.y = 34.0
	%GameList.add_child(label)


## O que dizer quando o filtro não tem jogo nenhum — hoje, só a lista de
## favoritos vazia. Uma tela em branco parece defeito; uma frase explica o que
## falta fazer, e onde.
func _add_hint(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Subtitle"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 140.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	%GameList.add_child(label)


func _filter(_id: StringName) -> void:
	_fill_games()


## A estrela acende ou apaga na hora; a grade **não** se reordena.
##
## Reordenar aqui tiraria o cartão de baixo do dedo que acabou de tocá-lo — o
## jogador favorita o Ludo e vê o Uno pular para onde o Ludo estava. A ordem nova
## vale a partir da próxima vez que a grade for montada, que é trocar de filtro ou
## voltar para esta tela.
func _toggle_favorite(card: GameChoice, id: StringName) -> void:
	card.favorite = Prefs.toggle_favorite(id)
	Sound.play(Sound.Cue.TAP)


func _choose(card: GameChoice, id: StringName) -> void:
	if _leaving:
		return
	_leaving = true
	card.highlighted = true
	Game.game_id = id
	await get_tree().create_timer(TAP_FEEDBACK).timeout
	# A tela pode ter saído da árvore durante a espera. Curta como é, quase nunca
	# acontece em uso — e acontece toda vez num teste, que é onde uma cena é
	# criada e descartada no mesmo fôlego.
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(GAME_MENU_SCENE)


# --- navegação ----------------------------------------------------------------


## A gaveta é montada a cada abertura e morre ao fechar, em vez de viver escondida
## na cena. Ela não guarda estado nenhum — a rota marcada é sempre esta tela —, e
## um nó permanente que existe para ficar invisível é um nó que alguém vai
## esquecer de esconder.
func _open_drawer() -> void:
	if _leaving or _drawer() != null:
		return
	var drawer := NavDrawer.new()
	drawer.current = NavDrawer.HOME
	drawer.picked.connect(_go)
	add_child(drawer)
	drawer.open()


func _go(route: StringName) -> void:
	match route:
		# Já se está aqui. Recarregar a própria tela por um toque na gaveta seria
		# piscar a tela para chegar exatamente onde se estava.
		NavDrawer.HOME:
			return
		NavDrawer.MULTIPLAYER:
			_open_join()
		NavDrawer.SETTINGS:
			_open_settings()


## Aqui o gesto de voltar chegou ao fim da pilha: esta é a primeira tela, e não há
## anterior. Fechar é a resposta certa — é o que o Android promete quando não
## sobrou tela — e é a única tela do app onde ela é certa.
##
## Antes disso, as camadas: com a gaveta aberta o gesto fecha **ela**, e com as
## boas-vindas abertas, elas. Voltar de uma camada é voltar para o que está atrás,
## e só quando não há camada nenhuma é que voltar é sair.
func go_back() -> void:
	var drawer := _drawer()
	if drawer != null:
		drawer.close()
		return
	var welcome := _welcome()
	if welcome != null:
		welcome.finish()
		return
	get_tree().quit()


func _drawer() -> NavDrawer:
	for child in get_children():
		if child is NavDrawer:
			return child as NavDrawer
	return null


func _welcome() -> WelcomePanel:
	for child in get_children():
		if child is WelcomePanel:
			return child as WelcomePanel
	return null


func _open_join() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(JOIN_SCENE)


func _open_settings() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(SETTINGS_SCENE)


## Um QR lido numa execução anterior do processo. Se o Android recolheu o app
## enquanto a câmera estava aberta, o resultado sobreviveu no plugin e o
## pareamento continua na tela de entrar, em vez de o jogador voltar ao menu sem
## entender o que aconteceu.
##
## O payload traz o jogo e o código, então o estado do pareamento é reconstruído
## inteiro a partir dele — não sobrou nada em memória para perder.
func _resume_pending_scan() -> bool:
	var pending := Pairing.qr_scanner.take_pending()
	if pending.is_empty():
		return false
	var info := Pairing.parse_payload(pending)
	if info.is_empty():
		return false
	Game.join_info = info
	get_tree().change_scene_to_file(JOIN_SCENE)
	return true
