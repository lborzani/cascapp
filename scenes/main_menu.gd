extends Control

## A aba Jogos: a coleção, com os favoritos na frente.
##
## ## O que a tela é
##
## O cabeçalho com o logo e o nome de quem está jogando, os favoritos em cartão
## grande, o catálogo inteiro em cardápio de lousa, e as abas na base. Escolher um
## jogo não troca de tela: sobe a **folha do jogo** por cima desta, com o modo e os
## ajustes. A tela de modos que existia entre as duas saiu.
##
## ## Cardápio, e não grade
##
## Foi lista, depois grade de três colunas. A grade mostra mais jogos na mesma
## altura e cobra por isso onde dói: num cartão de 118 px "Batalha Naval" quebra em
## duas linhas de quatro letras e a peça vira mancha. O cardápio devolve o nome
## inteiro, alinha a lotação à direita como um preço e dá a faixa toda ao dedo — e
## é o que a tela faz de verdade: listar o que tem.
##
## Os favoritos continuam acima, em cartão: lá o cartão é atalho, e a estrela
## adianta o caminho sem esconder nada.
##
## ## Para onde esta tela leva
##
## Para a folha do jogo, para as outras duas abas, e para a partida guardada. Ela
## é a raiz: o gesto de voltar fecha as camadas que estiverem abertas e, sem
## nenhuma, sai do app — é o que o Android promete quando não sobrou tela.
##
## Acrescentar um jogo continua sendo acrescentar uma entrada em `Game.GAMES`.

const JOIN_SCENE := "res://scenes/join.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"

## Duas colunas de favorito: o cartão precisa de largura para a peça aparecer, e
## três deles num celular de 432 px voltariam ao problema da grade.
const FAV_COLUMNS := 2
const FAV_HEIGHT := 132.0

var _leaving := false
var _sheet: GameSheet = null


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)
	Game.reset_to_menu()
	if _resume_pending_scan():
		return

	%AppBar.greet(Prefs.player_name())
	%AppBar.action_pressed.connect(_open_settings)

	%Tabs.current = AppTabs.GAMES
	# Sem servidor de partidas não há sala para procurar. A aba continua lá,
	# apagada: uma aba que some parece uma aba que foi removida.
	if not Net.relay_available():
		%Tabs.disabled = [AppTabs.ONLINE] as Array[StringName]
	%Tabs.picked.connect(_go_tab)

	%Categories.setup(ChipBar.category_items())
	%Categories.selected.connect(_filter)

	_sheet = GameSheet.new()
	add_child(_sheet)
	_sheet.confirmed.connect(_launch)

	_fill_games()
	_offer_rejoin()
	_greet()

	# A folha volta aberta para quem chegou aqui saindo de uma partida ou da sala:
	# quem voltou está escolhendo como jogar de novo, e não navegando do zero.
	var pending: StringName = Game.pending_sheet
	Game.pending_sheet = &""
	if not pending.is_empty():
		_sheet.open(pending)


# --- catálogo -----------------------------------------------------------------


## A coleção inteira vem de `Game.GAMES`, e não de cartões desenhados na cena.
func _fill_games() -> void:
	# `remove_child` antes do `queue_free`: o segundo só apaga no fim do quadro, e
	# entre trocar de filtro e o quadro acabar a tela teria as seções velhas por
	# baixo das novas.
	for parent: Node in [%Favorites, %GameList]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()

	var filter: StringName = %Categories.current
	%Favorites.visible = filter == ChipBar.ALL and not Game.favorite_games().is_empty()
	if %Favorites.visible:
		_fill_favorites()

	if filter == ChipBar.FAVORITES:
		var starred := Game.favorite_games()
		if starred.is_empty():
			_add_hint("Nenhum favorito ainda.\nToque na estrela de um jogo para guardá-lo aqui.")
			return
		_add_rows(starred)
		return
	if filter != ChipBar.ALL:
		_add_rows(Game.games_in(filter))
		return

	# Em "Todos", o cardápio vem **por categoria**: sete linhas seguidas são sete
	# linhas a comparar, e em blocos a comparação é dentro do bloco — que é a
	# pergunta que o jogador faz ("qual jogo de tabuleiro eu quero?").
	#
	# Os favoritos continuam aqui embaixo também, porque o cardápio é o catálogo:
	# uma lista que esconde o que está favoritado é uma lista incompleta. Em cima
	# eles são atalho, e a forma diferente evita a leitura de "dois jogos iguais".
	for entry: Dictionary in Game.CATEGORIES:
		var ids: Array[StringName] = []
		for id in Game.games_in():
			if Game.category_of(id) == entry["id"]:
				ids.append(id)
		if ids.is_empty():
			continue
		_add_caption(str(entry["label"]))
		_add_rows(ids)


func _fill_favorites() -> void:
	var caption := Label.new()
	caption.text = "Favoritos"
	caption.theme_type_variation = &"SectionHeader"
	%Favorites.add_child(caption)

	var grid := GridContainer.new()
	grid.columns = FAV_COLUMNS
	grid.add_theme_constant_override("h_separation", AppTheme.SPACE_M)
	grid.add_theme_constant_override("v_separation", AppTheme.SPACE_M)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%Favorites.add_child(grid)
	for id in Game.favorite_games():
		var card := GameChoice.new()
		card.custom_minimum_size = Vector2(0, FAV_HEIGHT)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.title = Game.game_title(id)
		card.piece = Game.piece_of(id)
		card.art_id = id
		card.unavailable = not Game.playable(id)
		card.favoritable = true
		card.favorite = true
		card.chosen.connect(_open_sheet.bind(id))
		card.favorite_toggled.connect(_toggle_favorite.bind(id))
		grid.add_child(card)


func _add_rows(ids: Array[StringName]) -> void:
	for id in ids:
		var row := CatalogRow.new()
		row.game_id = id
		row.favorite = Prefs.is_favorite(id)
		row.unavailable = not Game.playable(id)
		row.chosen.connect(_open_sheet.bind(id))
		row.favorite_toggled.connect(_toggle_favorite.bind(id, row))
		%GameList.add_child(row)


## Rótulo de seção dentro do cardápio. Nasce aqui e não na cena porque as seções
## vêm e vão com o filtro: em "Cartas" não há o que separar.
func _add_caption(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Caption"
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.custom_minimum_size.y = 30.0
	%GameList.add_child(label)


## O que dizer quando o filtro não tem jogo nenhum — hoje, só a lista de favoritos
## vazia. Uma tela em branco parece defeito; uma frase explica o que falta fazer.
func _add_hint(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Hint"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 120.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	%GameList.add_child(label)


func _filter(_id: StringName) -> void:
	_fill_games()


## A estrela acende ou apaga na hora; o cardápio **não** se reordena.
##
## Reordenar aqui tiraria a linha de baixo do dedo que acabou de tocá-la. A ordem
## nova vale a partir da próxima vez que a tela for montada, que é trocar de filtro
## ou voltar para cá — e é aí que o favorito aparece no cartão de cima.
func _toggle_favorite(id: StringName, row: CatalogRow = null) -> void:
	var marked := Prefs.toggle_favorite(id)
	if row != null:
		row.favorite = marked
	else:
		_fill_games()
	Sound.play(Sound.Cue.TAP)


# --- folha do jogo ------------------------------------------------------------


func _open_sheet(id: StringName) -> void:
	if _leaving:
		return
	Sound.play(Sound.Cue.TAP)
	_sheet.open(id)


func _launch(mode: int) -> void:
	if _leaving:
		return
	_leaving = true
	GameSheet.launch(get_tree(), mode)


func _sheet_open() -> bool:
	return _sheet != null and _sheet.is_open()


# --- navegação ----------------------------------------------------------------


func _go_tab(route: StringName) -> void:
	Sound.play(Sound.Cue.TAP)
	match route:
		AppTabs.ONLINE:
			_open_join()
		AppTabs.YOU:
			_open_settings()


## Aqui o gesto de voltar chegou ao fim da pilha: esta é a primeira tela, e não há
## anterior. Fechar é a resposta certa — é o que o Android promete quando não
## sobrou tela — e é a única tela do app onde ela é certa.
##
## Antes disso, as camadas: com a folha do jogo aberta o gesto fecha **ela**, e com
## as boas-vindas abertas, elas.
func go_back() -> void:
	if _sheet_open():
		_sheet.close()
		return
	var welcome := _welcome()
	if welcome != null:
		welcome.finish()
		return
	get_tree().quit()


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


# --- partida guardada e boas-vindas -------------------------------------------


## A partida de onde este aparelho caiu, no topo de tudo.
##
## Acima do resto porque é a única coisa na tela com gente esperando: os outros
## jogadores estão numa mesa com uma máquina no lugar de quem caiu. O catálogo
## continua abaixo para quem prefere começar outra.
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
	# Irmão do cardápio, e não filho dele: a lista é refeita a cada troca de
	# filtro, e o cartão sumiria no primeiro toque nela.
	%Content.add_child(card)
	%Content.move_child(card, 0)


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
## aparelho, não uma etapa do caminho. Como camada, o jogador já vê a coleção
## atrás dela — o app se apresenta enquanto pergunta.
##
## Depois do `_resume_pending_scan()`, que sai da função antes: quem abriu o app
## por um QR está no meio de entrar numa partida, e uma pergunta atravessada aí é
## uma pergunta na hora errada.
func _greet() -> void:
	if not WelcomePanel.pending():
		return
	var welcome := WelcomePanel.new()
	welcome.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(welcome)
	welcome.open()
	# O nome sai daqui, e o cabeçalho já foi escrito com o padrão: quem acabou de
	# se apresentar deve ver a saudação com o nome que escolheu.
	welcome.tree_exited.connect(func() -> void:
		if is_inside_tree():
			%AppBar.greet(Prefs.player_name())
	)


## Um QR lido numa execução anterior do processo. Se o Android recolheu o app
## enquanto a câmera estava aberta, o resultado sobreviveu no plugin e o pareamento
## continua na tela de entrar, em vez de o jogador voltar ao menu sem entender o
## que aconteceu.
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
