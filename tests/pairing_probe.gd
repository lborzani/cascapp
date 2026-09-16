extends Node

## Teste do menu e da tela de pareamento, com os autoloads de verdade.
##
##   godot --headless --path . res://tests/pairing_probe.tscn
##
## Existe por causa do que as rodadas de teste em aparelho encontraram: a tela
## abria, o QR aparecia, e nenhum caminho conectava. As causas eram invisíveis
## por inspeção — uma chamada de limpeza derrubando o que a própria tela tinha
## acabado de ligar, um sinal recebido com os argumentos fora de ordem. Nenhuma
## produzia erro; todas produziam silêncio.
##
## O que dá para verificar sem dois aparelhos é que o convite é *oferecido*: a
## sala é aberta, o código chega ao link, o payload do QR é válido e nomeia a
## mesma sala. Se o outro lado entra ou não depende do outro lado.

const PAIRING_SCENE := preload("res://scenes/pairing.tscn")
const JOIN_SCENE := preload("res://scenes/join.tscn")
const MENU_SCENE := preload("res://scenes/main_menu.tscn")
const GAME_MENU_SCENE := preload("res://scenes/game_menu.tscn")

var _failures := 0


func _ready() -> void:
	await _probe_game_picker()
	await _probe_favorite()
	await _probe_setup_panel()
	await _probe_room_list()
	await _probe_host()
	await _probe_guest()

	if _failures == 0:
		print("OK — menu e pareamento consistentes.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## A estrela guarda o jogo, e guarda **uma vez**.
##
## Um clique chega duas vezes: o projeto liga `emulate_touch_from_mouse`, então
## todo botão do mouse também vira toque, e no Android o dedo também vira mouse.
## Num alvo que **alterna**, contar os dois é marcar e desmarcar no mesmo clique —
## e o sintoma não é um estado errado, é a estrela simplesmente não funcionar.
##
## O teste manda os dois eventos porque é o que o aparelho manda. Sem isso, um
## teste que mandasse só um passaria com o defeito inteiro de pé.
func _probe_favorite() -> void:
	print("favorito")
	Prefs.forget_favorites()
	var card := GameChoice.new()
	card.favoritable = true
	card.size = Vector2(140.0, 96.0)
	add_child(card)
	await get_tree().process_frame

	var count := [0]
	card.favorite_toggled.connect(func() -> void: count[0] += 1)
	var at := card._star_zone().get_center()
	_check(card._star_zone().has_point(at), "a estrela tem um alvo de toque")

	card._gui_input(_touch(at))
	card._gui_input(_click(at))
	_equals(count[0], 1, "um clique conta uma vez, e não duas")

	# E o toque fora dela continua abrindo o jogo, também uma vez só.
	var picks := [0]
	card.chosen.connect(func() -> void: picks[0] += 1)
	var middle := Vector2(card.size.x * 0.3, card.size.y * 0.7)
	card._gui_input(_touch(middle))
	card._gui_input(_click(middle))
	_equals(picks[0], 1, "e o toque no cartão também")

	# De ponta a ponta: a tela grava no disco e a estrela volta preenchida.
	_check(not Prefs.is_favorite(Game.CHESS), "o xadrez começa sem estrela")
	Prefs.toggle_favorite(Game.CHESS)
	_check(Prefs.is_favorite(Game.CHESS), "e favoritar sobrevive à leitura seguinte")
	Prefs.forget_favorites()

	card.queue_free()
	await get_tree().process_frame


func _touch(at: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.pressed = true
	event.position = at
	return event


func _click(at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	return event


## A primeira tela responde uma pergunta só: qual jogo. Tocar num cartão grava o
## jogo e leva à tela seguinte — antes o cartão só marcava, e os botões de ação
## moravam embaixo, mudando de significado conforme um cartão acima deles.
func _probe_game_picker() -> void:
	print("escolha do jogo")
	Game.reset_to_menu()
	Game.game_id = Game.CHESS
	# Sem favoritos a grade é o catálogo na ordem do catálogo. Com um favorito
	# gravado numa execução anterior — o aparelho de quem roda o teste é o mesmo
	# que joga —, ela começaria por ele, e a asserção seguinte falharia por um
	# motivo que não é defeito nenhum.
	Prefs.forget_favorites()
	var menu := MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame

	var list: Control = menu.get_node("%GameList")
	# Um cartão por jogo **visível**, e não por entrada do catálogo. Os dois foram
	# a mesma conta enquanto todo jogo do catálogo tinha tela; um jogo em
	# construção entra no catálogo com `visible` falso — ele já responde por
	# `make_ruleset` e `host_option`, que é o que os testes de regra usam, e ainda
	# não tem cena para o cartão abrir.
	var shown := 0
	for entry in Game.GAMES:
		if entry.get("visible", true):
			shown += 1
	var cards := _tiles(list)
	_equals(cards.size(), shown, "um cartão por jogo visível do catálogo")

	var first: GameChoice = cards[0]
	_equals(first.title, "Xadrez", "o primeiro cartão é o xadrez")
	_check(first.piece != 0, "com a peça que representa o jogo")
	_check(not first.row, "empilhado: peça em cima, nome embaixo")
	_check(not first.highlighted, "nenhum começa aceso: escolher agora é navegar")

	# A grade vem em seções por categoria, e um rótulo separa cada uma. São irmãos
	# dos cartões na mesma coluna, e é por isso que contar jogo é contar `GameChoice`
	# e não filhos.
	_check(list.get_child_count() > Game.CATEGORIES.size(), "com um rótulo por seção")

	# A estrela é um segundo alvo dentro do cartão: ela guarda o jogo sem abrir a
	# tela seguinte, e sem reordenar a grade debaixo do dedo que acabou de tocar.
	first.favorite_toggled.emit()
	_check(first.favorite, "tocar na estrela acende o favorito")
	_check(Prefs.is_favorite(Game.CHESS), "e grava no disco, não na sessão")
	_equals(Game.game_id, Game.CHESS, "sem escolher o jogo: a estrela não navega")
	_equals(_tiles(list).size(), shown, "e sem refazer a grade no mesmo toque")

	var bar: ChipBar = menu.get_node("%Categories")
	bar.select(ChipBar.FAVORITES)
	await get_tree().process_frame
	_equals(_tiles(list).size(), 1, "o filtro de favoritos mostra só o que foi guardado")
	bar.select(Game.CAT_BOARD)
	await get_tree().process_frame
	_equals(
		_tiles(list).size(), Game.games_in(Game.CAT_BOARD).size(),
		"e cada categoria mostra os jogos dela"
	)
	bar.select(ChipBar.ALL)
	await get_tree().process_frame
	cards = _tiles(list)
	_equals(cards.size(), shown, "de volta em todos, o catálogo inteiro")
	_equals(cards[0].title, "Xadrez", "com o favorito no topo, acima das categorias")
	Prefs.forget_favorites()

	# Entrar numa partida saiu da tela inicial e virou um destino da gaveta: quem
	# entra joga o que o anfitrião abriu, então escolher o jogo antes é escolher
	# uma coisa que a resposta dele não decide.
	menu._open_drawer()
	var drawer: NavDrawer = menu._drawer()
	_check(drawer != null, "o botão da esquerda abre a gaveta")
	menu.go_back()
	_check(menu._drawer() != null, "e o gesto de voltar fecha a gaveta, não o app")

	# A troca de tela só acontece depois do retorno visual, então o que se verifica
	# aqui é a parte síncrona: o jogo gravado e o cartão aceso. A cena é liberada
	# antes de o temporizador vencer, e a navegação desiste sozinha por não estar
	# mais na árvore.
	#
	# De novo da árvore: os cartões foram trocados a cada filtro, e o que sobrou
	# nas variáveis é um nó já liberado.
	var second: GameChoice = _tiles(list)[1]
	second.chosen.emit()
	_equals(Game.game_id, Game.CHECKERS, "tocar no cartão grava o jogo")
	_check(second.highlighted, "e acende o cartão tocado, para o toque ter resposta")

	# `free()` e não `queue_free()`: o segundo só apaga no fim do quadro, e o
	# primeiro quadro de uma cena com fontes do sistema demora mais que o retorno
	# visual — a troca de tela vencia a corrida e levava o próprio teste junto.
	menu.free()
	await get_tree().process_frame
	Game.game_id = Game.CHESS


## Só os cartões de jogo, onde quer que estejam. A coluna guarda rótulos de seção
## e uma grade por categoria, então os cartões são netos e não filhos — e contar
## filhos seria contar rótulos como se fossem jogos.
func _tiles(list: Control) -> Array[GameChoice]:
	var cards: Array[GameChoice] = []
	for child in list.get_children():
		if child is GameChoice:
			cards.append(child as GameChoice)
			continue
		for grandchild in child.get_children():
			if grandchild is GameChoice:
				cards.append(grandchild as GameChoice)
	return cards


## O painel de ajustes fica entre "quero jogar" e o tabuleiro, e só para quem
## abre a partida: quem entra recebe o ritmo do anfitrião no handshake, então
## oferecer a escolha ali seria oferecer uma decisão que não é dele.
func _probe_setup_panel() -> void:
	print("ajustes da partida")
	Game.reset_to_menu()
	Game.time_control = 0
	Game.game_id = Game.CHESS
	var menu := GAME_MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame

	# O jogo escolhido é o título da tela, e não um cartão repetido dentro dela.
	var bar: AppBar = menu.get_node("%AppBar")
	_equals(bar.title, "Xadrez", "a barra diz o jogo escolhido")
	_equals(bar.leading, IconButton.Kind.BACK, "e a volta é a seta da barra")

	var layer: Control = menu.get_node("%SetupLayer")
	var grid: Control = menu.get_node("%ClockGrid")
	_equals(layer.visible, false, "painel começa fechado")
	_equals(grid.get_child_count(), Game.TIME_CONTROLS.size(), "um botão por ritmo")

	menu.get_node("%HostButton").pressed.emit()
	await get_tree().process_frame
	_equals(layer.visible, true, "criar partida abre o painel")
	_check(menu.get_node("%SetupTitle").text.contains("Criar"), "título diz o que vai acontecer")

	# 1:30 é o índice 1 da lista; escolher tem de mudar o estado de verdade, não
	# só a aparência do botão.
	grid.get_child(1).pressed.emit()
	_equals(Game.time_control, 1, "escolher o ritmo grava a escolha")
	_equals(Game.clock_initial(), 90.0, "1:30 são 90 segundos")
	_equals(grid.get_child(1).theme_type_variation, &"ChipSelected", "o escolhido fica marcado")
	_equals(grid.get_child(0).theme_type_variation, &"ChipButton", "e os outros não")

	# Damas não tem relógio: a seção some do painel, e a regra vale mesmo com um
	# ritmo escolhido antes — ela mora em `Game`, não na tela.
	Game.game_id = Game.CHECKERS
	menu._open_setup(Game.Mode.ONLINE)
	await get_tree().process_frame
	_equals(grid.visible, false, "damas esconde a escolha de ritmo")
	_equals(menu.get_node("%ClockCaption").visible, false, "e a legenda dela")
	_equals(Game.has_clock(), false, "e damas nunca tem relógio")
	Game.game_id = Game.CHESS
	_equals(Game.has_clock(), true, "xadrez mantém o ritmo escolhido")
	menu._open_setup(Game.Mode.ONLINE)
	await get_tree().process_frame
	_equals(grid.visible, true, "e a escolha volta no xadrez")

	# Contra o bot o painel troca de seções: nível e cor entram, "quem pode
	# entrar" sai. Uma escolha oferecida onde não vale é pior que escolha
	# nenhuma — o jogador mexe nela, nada acontece, e passa a desconfiar do resto.
	var levels: Control = menu.get_node("%LevelRow")
	_equals(levels.get_child_count(), Bot.LEVELS.size(), "um botão por nível do bot")
	menu.get_node("%SoloButton").pressed.emit()
	await get_tree().process_frame
	_equals(levels.visible, true, "contra o bot o nível aparece")
	_equals(menu.get_node("%SideRow").visible, true, "e a escolha de cor")
	_equals(menu.get_node("%VisibilityRow").visible, false, "sem sala, sem quem pode entrar")

	levels.get_child(2).pressed.emit()
	_equals(Game.bot_level, 2, "escolher o nível grava a escolha")
	_equals(levels.get_child(2).theme_type_variation, &"ChipSelected", "o escolhido fica marcado")

	# A cor escolhida é a do jogador; o que fica guardado é a do bot.
	menu.get_node("%BlackButton").pressed.emit()
	_equals(Game.bot_side, Board.Side.WHITE, "escolher pretas deixa as brancas com o bot")
	menu.get_node("%WhiteButton").pressed.emit()
	_equals(Game.bot_side, Board.Side.BLACK, "e vice-versa")

	menu.get_node("%HostButton").pressed.emit()
	await get_tree().process_frame
	_equals(levels.visible, false, "numa sala o nível some")
	_equals(menu.get_node("%VisibilityRow").visible, true, "e quem pode entrar volta")

	menu.get_node("%SetupCancelButton").pressed.emit()
	await get_tree().process_frame
	_equals(layer.visible, false, "cancelar fecha o painel")

	menu.get_node("%HotseatButton").pressed.emit()
	await get_tree().process_frame
	_equals(layer.visible, true, "jogar no mesmo aparelho também abre")
	_check(
		not menu.get_node("%SetupTitle").text.contains("Criar"),
		"com um título diferente do de rede"
	)
	menu.get_node("%SetupCancelButton").pressed.emit()

	# Sem servidor a seção de sala inteira sai, e a ação principal passa a ser
	# jogar no mesmo aparelho. Oferecer o que não pode funcionar é pior que
	# oferecer menos.
	_equals(
		menu.get_node("%OnlineCaption").visible, Net.relay_available(),
		"a seção de sala acompanha o relay estar configurado"
	)
	_equals(
		menu.get_node("%HotseatButton").theme_type_variation,
		&"PrimaryButton" if not Net.relay_available() else &"",
		"e a ação principal muda junto"
	)

	menu.queue_free()
	await get_tree().process_frame
	Game.time_control = 0


## A lista pública é opt-in e o padrão é privado. Verificado contra o relay de
## verdade porque o que está em jogo é o acordo entre o campo `listed` do
## cliente e o filtro do servidor — os dois lados podem estar certos sozinhos e
## errados juntos.
func _probe_room_list() -> void:
	print("lista de salas")
	if not Net.relay_available():
		print("  (sem relay configurado — pulando)")
		return

	var address := Net.rooms_url()
	_check(address.ends_with("/rooms"), "endereço da lista sai do endereço do relay")

	var private_code := Pairing.generate_code()
	Game.game_id = Game.CHESS
	Net.time_control = 0
	Net.host_relay(Game.CHESS, private_code, false)
	await _wait_for_room()
	var listing := await _fetch_rooms(address)
	_check(
		not _codes(listing).has(private_code),
		"sala privada não aparece na lista"
	)
	Net.leave()

	var public_code := Pairing.generate_code()
	Net.time_control = 2
	Net.host_relay(Game.CHESS, public_code, true)
	await _wait_for_room()
	listing = await _fetch_rooms(address)
	_check(_codes(listing).has(public_code), "sala pública aparece")
	for entry in listing:
		if str(entry.get("code", "")) == public_code:
			_equals(str(entry.get("game", "")), "chess", "com o jogo")
			_equals(int(entry.get("tc", -1)), 2, "e com o ritmo")
	Net.leave()
	await get_tree().process_frame


func _wait_for_room() -> void:
	for _i in 200:
		if Pairing.relay.state() == RelayBridge.State.WAITING:
			return
		await get_tree().process_frame
	_failures += 1
	printerr("  FAIL a sala não abriu a tempo")


func _fetch_rooms(address: String) -> Array:
	var request := HTTPRequest.new()
	add_child(request)
	request.request(address)
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[1]) != 200:
		_failures += 1
		printerr("  FAIL a lista respondeu %d" % int(result[1]))
		return []
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return Array(parsed.get("rooms", [])) if parsed is Dictionary else []


func _codes(rooms: Array) -> PackedStringArray:
	var codes := PackedStringArray()
	for entry in rooms:
		codes.append(str(entry.get("code", "")))
	return codes


func _probe_host() -> void:
	print("anfitrião")
	Game.mode = Game.Mode.ONLINE
	Game.role = Game.Role.HOST
	Game.game_id = Game.CHESS
	var screen := PAIRING_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame

	var code: String = screen.get_node("%CodeLabel").text
	_equals(code.length(), Pairing.CODE_LENGTH, "código de %d caracteres" % Pairing.CODE_LENGTH)
	_equals(screen.get_node("%HostPanel").visible, true, "painel do anfitrião visível")
	_equals(Net.is_host, true, "papel de anfitrião")

	# A tela não pode ficar parada esperando rádio antes de mostrar o código: o
	# fluxo antigo bloqueava até 8s no hotspot, e o jogador via uma tela morta.
	_check(not code.is_empty(), "código pronto no primeiro quadro")

	# O QR carrega o nome da sala, e só. Endereço, porta e credenciais de Wi-Fi
	# saíram junto com a partida por ligação direta.
	var info := Pairing.parse_payload(screen.get_node("%QrCode").payload)
	_check(not info.is_empty(), "payload do QR é válido")
	if not info.is_empty():
		_equals(info["code"], code, "payload carrega o mesmo código")
		_equals(info["game"], Game.CHESS, "payload carrega o jogo")
		_equals(info.size(), 2, "e nada além disso")

	_equals(Net._expected_code, code, "o código chegou ao link")

	screen.queue_free()
	await get_tree().process_frame
	Game.reset_to_menu()


## Entrar numa partida é uma tela própria, alcançada pelo botão da tela inicial e
## sem passar pela escolha do jogo: o painel é o mesmo nó nas quatro portas de
## entrada (sala da lista, código, QR, NFC), e todas terminam na mesma chamada ao
## link.
func _probe_guest() -> void:
	print("convidado")
	Game.reset_to_menu()
	Game.game_id = Game.CHESS
	var screen := JOIN_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame
	if not Net.relay_available():
		print("  (sem relay configurado — pulando)")
		screen.free()
		return

	var panel: JoinPanel = screen.get_node("%JoinPanel")

	# Código com o tamanho errado nunca chega ao transporte. Os campos vêm do
	# painel, e não da tela: `%` só enxerga dentro da cena que declarou o nome, e
	# o painel é uma cena própria — é o que o torna reusável sem que a tela
	# precise conhecer as peças dele.
	panel.get_node("%CodeEdit").text = "ABC"
	panel.get_node("%JoinButton").pressed.emit()
	await get_tree().process_frame
	# A recusa vai para o toast do topo, não para a linha de status: é ali que o
	# rodapé enterrava os erros, entre uma mensagem de progresso e outra.
	var toast: Banner = screen.get_node("%Toast")
	_check(
		toast._message.contains(str(Pairing.CODE_LENGTH)),
		"código curto é recusado no toast (obtido: '%s')" % toast._message
	)

	# Código completo: vai direto para a sala, sem tentar endereço nenhum antes.
	# O estado do relay sobrescreve o texto assim que a ponte responde, então o
	# que se verifica é o efeito — a tentativa foi entregue ao link.
	# O campo é sempre maiúsculo, e na tela: converter só no envio deixaria o
	# jogador lendo um código diferente do que mandou.
	var field: LineEdit = panel.get_node("%CodeEdit")
	field.text = "ab12cd"
	panel._on_code_typed(field.text)
	_equals(field.text, "AB12CD", "o que é digitado em minúsculas vira maiúscula no campo")

	field.text = "ZZZ999"
	panel.get_node("%JoinButton").pressed.emit()
	await get_tree().process_frame
	_equals(Net._expected_code, "ZZZ999", "o código digitado vira o nome da sala procurada")
	_equals(Net.is_host, false, "e o papel é de convidado")
	_equals(Game.role, Game.Role.GUEST, "com o papel gravado antes de sair da tela")

	# Uma sala da lista carrega o jogo junto com o código, então tocar nela
	# responde as duas perguntas de uma vez — inclusive quando o jogo é outro.
	Net.leave()
	panel._joining = false
	panel.show_rooms([{"code": "AB12CD", "game": "checkers", "tc": 0, "age": 30}])
	var rooms := panel.get_node("%RoomRows").get_children()
	var card: RoomCard = rooms[rooms.size() - 1]
	_equals(card.code, "AB12CD", "a sala vira um cartão na lista")
	card.pressed.emit()
	await get_tree().process_frame
	_equals(Net._expected_code, "AB12CD", "tocar na sala procura o código dela")
	_equals(Game.game_id, Game.CHECKERS, "e leva o jogo da sala, não o que estava escolhido")

	screen.free()
	await get_tree().process_frame
	Game.reset_to_menu()
	Game.game_id = Game.CHESS


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s (esperado %s, obtido %s)" % [label, expected, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
