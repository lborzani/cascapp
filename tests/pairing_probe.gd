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

var _failures := 0


func _ready() -> void:
	await _probe_game_picker()
	await _probe_favorite()
	await _probe_rejoin_offer()
	await _probe_game_sheet()
	await _probe_formats()
	await _probe_room_list()
	await _probe_host()
	await _probe_guest()

	if _failures == 0:
		print("OK — menu e pareamento consistentes.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## A partida de onde se caiu é oferecida de volta — e só enquanto faz sentido.
##
## Sem o cartão, quem tinha o app fechado no meio de uma partida reabria na grade
## de jogos, e o gesto à mão era **criar** partida: sala nova, e a antiga seguindo
## com uma máquina no lugar dele. As três regras que decidem o cartão:
##
## - cair mantém a cadeira: sair sem `bye` é o processo morrendo ou a rede caindo;
## - sair **avisando** a esquece: é desistir, e oferecer a volta seria insistir;
## - o `X` a esquece, para quem não quer voltar não ter de esperar quatro horas.
func _probe_rejoin_offer() -> void:
	print("voltar à partida")
	var now := int(Time.get_unix_time_from_system())
	Prefs.forget_rejoin()
	Game.reset_to_menu()

	var bare := MENU_SCENE.instantiate()
	add_child(bare)
	await get_tree().process_frame
	_equals(_resume_cards(bare).size(), 0, "sem partida guardada não há cartão")
	bare.free()

	Prefs.remember_rejoin("VOLTA7", Game.UNO, "k-assento", now)
	_equals(Prefs.rejoin_key("volta7"), "k-assento", "a chave é achada pelo código, digitado de qualquer jeito")
	_equals(Prefs.rejoin_key("OUTRA1"), "", "e não vai para o código de outra sala")

	var menu := MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame
	var cards := _resume_cards(menu)
	_equals(cards.size(), 1, "com a partida guardada, a tela inicial oferece a volta")
	if cards.size() == 1:
		var card: ResumeCard = cards[0]
		_equals(card.code, "VOLTA7", "para a sala certa")
		_equals(card.game_id, Game.UNO, "e o jogo certo")
		_equals(card.get_index(), 0, "no topo, acima do filtro")
		card.dismissed.emit()
		await get_tree().process_frame
		_check(Prefs.pending_rejoin(now).is_empty(), "o X esquece a partida")
	menu.free()

	# Cair: o link não está de pé, e sair não manda `bye`. A cadeira fica.
	Prefs.remember_rejoin("VOLTA7", Game.UNO, "k-assento", now)
	Net.connected = false
	Game.reset_to_menu()
	_check(not Prefs.pending_rejoin(now).is_empty(), "quem caiu continua podendo voltar")

	# Sair avisando: o link está de pé, e o `leave` manda `bye`. A cadeira vai.
	Net.connected = true
	Game.reset_to_menu()
	_check(Prefs.pending_rejoin(now).is_empty(), "quem saiu pelo botão desistiu da cadeira")

	Prefs.remember_rejoin("VOLTA7", Game.UNO, "k-assento", now - Prefs.REJOIN_WINDOW - 60)
	_check(Prefs.pending_rejoin(now).is_empty(), "e a sala que o relay já fechou não é oferecida")
	Prefs.forget_rejoin()


func _resume_cards(menu: Node) -> Array:
	return menu.find_children("*", "ResumeCard", true, false)


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


## A primeira tela responde uma pergunta só: qual jogo. Tocar numa linha escolhe o
## jogo e sobe a folha dele — antes a linha levava a uma tela de modos, e a folha
## juntou as duas.
func _probe_game_picker() -> void:
	print("escolha do jogo")
	Game.reset_to_menu()
	Game.game_id = Game.CHESS
	# Sem favoritos o cardápio é o catálogo na ordem do catálogo. Com um favorito
	# gravado numa execução anterior — o aparelho de quem roda o teste é o mesmo que
	# joga —, a seção de cima apareceria e as asserções seguintes falhariam por um
	# motivo que não é defeito nenhum.
	Prefs.forget_favorites()
	Prefs.forget_rejoin()
	var menu := MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame

	var list: Control = menu.get_node("%GameList")
	# Uma linha por jogo **visível**, e não por entrada do catálogo: um jogo em
	# construção entra no catálogo com `visible` falso.
	var shown := 0
	for entry in Game.GAMES:
		if entry.get("visible", true):
			shown += 1
	var rows := _rows(list)
	_equals(rows.size(), shown, "uma linha por jogo visível do catálogo")
	_equals(rows[0].game_id, Game.CHESS, "a primeira linha é o xadrez")
	_check(list.get_child_count() > shown, "com um rótulo de categoria entre elas")
	_check(not menu.get_node("%Favorites").visible, "sem favorito, a seção de cima não aparece")

	# A estrela é um segundo alvo dentro da linha: guarda o jogo sem abrir a folha e
	# sem refazer o cardápio debaixo do dedo que acabou de tocar.
	rows[0].favorite_toggled.emit()
	_check(rows[0].favorite, "tocar na estrela acende o favorito")
	_check(Prefs.is_favorite(Game.CHESS), "e grava no disco, não na sessão")
	_equals(_rows(list).size(), shown, "sem refazer o cardápio no mesmo toque")
	_check(not menu._sheet_open(), "e sem abrir a folha")

	var bar: ChipBar = menu.get_node("%Categories")
	bar.select(ChipBar.FAVORITES)
	await get_tree().process_frame
	_equals(_rows(list).size(), 1, "o filtro de favoritos mostra só o que foi guardado")
	bar.select(Game.CAT_BOARD)
	await get_tree().process_frame
	_equals(
		_rows(list).size(), Game.games_in(Game.CAT_BOARD).size(),
		"e cada categoria mostra os jogos dela"
	)
	bar.select(ChipBar.ALL)
	await get_tree().process_frame
	_equals(_rows(list).size(), shown, "de volta em todos, o catálogo inteiro")
	_check(menu.get_node("%Favorites").visible, "e o favorito ganha o cartão de cima")
	_equals(
		menu.get_node("%Favorites").find_children("*", "GameChoice", true, false).size(), 1,
		"um cartão por favorito"
	)
	Prefs.forget_favorites()

	# Tocar na linha abre a folha por cima, em vez de trocar de tela — e o gesto de
	# voltar fecha a folha antes de pensar em sair do app.
	var second: CatalogRow = _rows(list)[1]
	second.chosen.emit()
	await get_tree().process_frame
	_equals(Game.game_id, Game.CHECKERS, "tocar na linha escolhe o jogo")
	_check(menu._sheet_open(), "e abre a folha dele")
	menu.go_back()
	_check(not menu._sheet_open(), "o gesto de voltar fecha a folha, e não o app")

	menu.free()
	await get_tree().process_frame

	# Quem volta de uma partida ou da sala chega com a folha daquele jogo aberta: ele
	# está escolhendo como jogar de novo, e não navegando do zero.
	Game.pending_sheet = Game.LUDO
	var again := MENU_SCENE.instantiate()
	add_child(again)
	await get_tree().process_frame
	_check(again._sheet_open(), "voltar de uma partida reabre a folha")
	_equals(Game.game_id, Game.LUDO, "do jogo de onde se voltou")
	_equals(Game.pending_sheet, &"", "e o pedido é consumido, para não reabrir sozinho depois")
	again.free()
	await get_tree().process_frame
	Game.game_id = Game.CHESS


## Só as linhas do cardápio: a coluna guarda também os rótulos de categoria, e
## contar filhos seria contar rótulo como se fosse jogo.
func _rows(list: Control) -> Array:
	return list.find_children("*", "CatalogRow", true, false)


## O painel de ajustes fica entre "quero jogar" e o tabuleiro, e só para quem
## abre a partida: quem entra recebe o ritmo do anfitrião no handshake, então
## oferecer a escolha ali seria oferecer uma decisão que não é dele.
## A seção de formato serve **três** jogos, e a tela não sabe qual é qual.
##
## Metrópole escolhe rodadas, a sinuca escolhe entre duas regras e o Uno escolhe
## a regra da casa. Antes cada um teria a sua seção com o mesmo código e um `if`
## diferente — e a do Uno simplesmente não existia: a regra do 0 e do 7 nascia do
## disco e ficava lá, sem nenhuma tela que a oferecesse.
func _probe_formats() -> void:
	print("formato por jogo")
	_check(Game.formats_of(Game.CHESS).is_empty(), "xadrez não pergunta formato")
	_equals(Game.formats_of(Game.MONOPOLY).size(), Game.ROUND_LIMITS.size(), "Metrópole pergunta")
	_equals(Game.formats_of(Game.POOL).size(), 2, "a sinuca pergunta")
	_equals(Game.formats_of(Game.UNO).size(), 2, "e o Uno também")

	# Ida e volta pelo valor, que é o que as regras leem e o que viaja pela rede.
	for wanted: int in [1, 0]:
		Game.set_format(wanted, Game.UNO)
		_equals(Game.format_value(Game.UNO), wanted, "o Uno guarda o formato escolhido")
		_equals(Game.uno_sevens, wanted != 0, "e ele é a regra da casa")
		# E ele viaja: a regra vai no bit alto do `option`, junto da semente.
		_equals(
			Game.uno_sevens_of(Game.host_option(Game.UNO)), wanted != 0,
			"que chega inteira do outro lado"
		)
	# Fica como estava para o resto da suíte: é uma preferência de disco.
	Game.set_format(1, Game.UNO)

	Game.set_format(PoolRules.Format.BRAZILIAN, Game.POOL)
	_equals(Game.pool_format, PoolRules.Format.BRAZILIAN, "a sinuca guarda o dela")
	_equals(Game.host_option(Game.POOL), PoolRules.Format.BRAZILIAN, "e ele viaja cru")
	Game.set_format(PoolRules.Format.KNOCKOUT, Game.POOL)


## A folha do jogo: modo, ajustes do modo e um botão, tudo numa camada só.
##
## Eram duas telas — a dos modos e o diálogo de ajustes por cima dela — e três
## toques até começar. A folha responde as duas perguntas juntas, e cada seção
## aparece só onde significa alguma coisa: uma escolha oferecida onde não vale é
## pior que escolha nenhuma, porque o jogador mexe nela, nada acontece, e ele
## passa a desconfiar do resto.
##
## Ela também não navega: avisa quem a abriu, e a tela decide. É o que deixa a
## mesma folha servir ao cardápio de Jogos e à fileira de Online.
func _probe_game_sheet() -> void:
	print("folha do jogo")
	Game.reset_to_menu()
	Game.time_control = 0
	var sheet := GameSheet.new()
	add_child(sheet)
	sheet.open(Game.CHESS)
	await get_tree().process_frame

	# Depois da animação de entrada a folha está encostada embaixo. A animação
	# escrevia `position` no painel ancorado, e ele terminava preso no topo da tela
	# com a lista aparecendo por baixo — nenhum erro, só uma folha no lugar errado.
	await get_tree().create_timer(GameSheet.SLIDE + 0.15).timeout
	var panel_bottom := sheet._panel.get_global_rect().end.y
	_check(
		absf(panel_bottom - sheet.get_global_rect().end.y) < 1.0,
		"a folha termina encostada na base da tela (%.0f de %.0f)" % [panel_bottom, sheet.get_global_rect().end.y]
	)
	_check(sheet._panel.get_global_rect().position.y > 1.0, "e não no topo")

	var modes := GameSheet.modes_for(Game.CHESS)
	_check(not modes.is_empty(), "o xadrez tem modo para oferecer")
	_equals(
		modes[0], Game.Mode.ONLINE if Net.relay_available() else Game.Mode.HOTSEAT,
		"a sala vem primeiro quando existe"
	)
	_equals(sheet._segments.segment_count(), modes.size(), "um segmento por modo disponível")
	_equals(sheet.mode, modes[0], "e a folha abre no primeiro")
	_equals(sheet._clock.get_child_count(), Game.TIME_CONTROLS.size(), "um botão por ritmo")

	sheet._clock.get_child(1).pressed.emit()
	_equals(Game.time_control, 1, "escolher o ritmo grava a escolha")
	_equals(Game.clock_initial(), 90.0, "1:30 são 90 segundos")
	_equals(sheet._clock.get_child(1).theme_type_variation, &"ChipSelected", "o escolhido fica marcado")
	_equals(sheet._clock.get_child(0).theme_type_variation, &"ChipButton", "e os outros não")

	# Damas não tem relógio: a seção inteira sai, e a escolha continua gravada em
	# `Game` — ela mora lá, não na tela.
	sheet.open(Game.CHECKERS)
	await get_tree().process_frame
	_check(not sheet._section("clock").visible, "damas esconde a escolha de ritmo")
	_equals(Game.has_clock(), false, "e damas nunca tem relógio")
	sheet.open(Game.CHESS)
	await get_tree().process_frame
	_check(sheet._section("clock").visible, "e a escolha volta no xadrez")

	# O formato serve três jogos com a mesma seção: rodadas, regra da sinuca e a
	# regra da casa do Uno.
	sheet.open(Game.UNO)
	await get_tree().process_frame
	_check(sheet._section("format").visible, "o Uno pergunta o formato")
	_check(sheet._section("players").visible, "e o tamanho da mesa")
	_equals(sheet._players.get_child_count(), 5, "de 2 a 6 jogadores")

	# Contra o bot o painel troca de seções: nível e cor entram, "quem pode
	# entrar" sai.
	sheet.open(Game.CHESS, Game.Mode.SOLO)
	await get_tree().process_frame
	_equals(sheet.mode, Game.Mode.SOLO, "a folha abre no modo pedido")
	_check(sheet._section("level").visible, "contra o bot o nível aparece")
	_check(sheet._section("side").visible, "e a escolha de cor")
	_check(not sheet._section("visibility").visible, "sem sala, sem quem pode entrar")
	_equals(sheet._levels.get_child_count(), Bot.LEVELS.size(), "um botão por nível do bot")
	sheet._levels.get_child(2).pressed.emit()
	_equals(Game.bot_level, 2, "escolher o nível grava a escolha")
	# A cor escolhida é a do jogador; o que fica guardado é a do bot.
	sheet._sides.get_child(1).pressed.emit()
	_equals(Game.bot_side, Board.Side.WHITE, "escolher pretas deixa as brancas com o bot")
	sheet._sides.get_child(0).pressed.emit()
	_equals(Game.bot_side, Board.Side.BLACK, "e vice-versa")
	_check(sheet._start.text.to_upper().contains("COMEÇAR"), "fora de rede o botão diz começar")

	if Net.relay_available():
		sheet.select_mode(Game.Mode.ONLINE)
		await get_tree().process_frame
		_check(sheet._section("visibility").visible, "numa sala quem pode entrar volta")
		_check(not sheet._section("level").visible, "e o nível some")
		_check(sheet._start.text.to_upper().contains("CRIAR"), "e o botão diz criar sala")

	var heard := [0]
	sheet.confirmed.connect(func(_mode: int) -> void: heard[0] += 1)
	sheet._start.pressed.emit()
	_equals(heard[0], 1, "o botão avisa quem abriu a folha, em vez de navegar sozinho")

	# "Como jogar" abre por cima da folha, e o gesto de voltar fecha só a página:
	# a folha continua aberta, com o que já estava escolhido.
	_check(sheet._rules_link.visible, "a folha tem o link Como jogar")
	var page := sheet.open_rules()
	await get_tree().process_frame
	_equals(page.doc.title, Game.game_title(Game.CHESS), "que abre as regras do jogo da folha")
	Nav.go_back()
	await get_tree().process_frame
	_check(not is_instance_valid(page), "o gesto de voltar fecha a página")
	_check(sheet.is_open(), "e deixa a folha aberta")

	sheet.close()
	await get_tree().process_frame
	_check(not sheet.is_open(), "fechar fecha")
	sheet.free()
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

	# O QR começa escondido: ele ocupa meia tela e serve a um caminho só — o outro
	# aparelho apontando a câmera —, enquanto o código serve a todos.
	_check(not screen.get_node("%QrCard").visible, "o QR começa escondido")
	screen.get_node("%QrButton").pressed.emit()
	_check(screen.get_node("%QrCard").visible, "e Mostrar QR mostra")
	screen.get_node("%CopyButton").pressed.emit()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_equals(DisplayServer.clipboard_get(), code, "Copiar leva o código para a área de transferência")
	_equals(screen.get_node("%Seats").capacity, maxi(Game.players_of(), 2), "a mesa tem a lotação do jogo")
	_check(screen.get_node("%Seats").present.has(0), "com o anfitrião sentado")

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
	var field: CodeInput = panel.get_node("%CodeInput")

	# Código com o tamanho errado nunca chega ao transporte. Os campos vêm do
	# painel, e não da tela: `%` só enxerga dentro da cena que declarou o nome, e
	# o painel é uma cena própria — é o que o torna reusável sem que a tela
	# precise conhecer as peças dele.
	field.set_code("ABC")
	panel.get_node("%JoinButton").pressed.emit()
	await get_tree().process_frame
	# A recusa vai para o toast do topo, não para a linha de status: é ali que o
	# rodapé enterrava os erros, entre uma mensagem de progresso e outra.
	var toast: Banner = screen.get_node("%Toast")
	_check(
		toast._message.contains(str(Pairing.CODE_LENGTH)),
		"código curto é recusado no toast (obtido: '%s')" % toast._message
	)

	# Seis casas cheias entram sozinhas: quem acabou de digitar o código inteiro não
	# deveria ter de procurar um botão. E o que é digitado em minúsculas vira
	# maiúscula na tela — converter só no envio deixaria o jogador lendo um código
	# diferente do que mandou.
	field.set_code("zzz999")
	await get_tree().process_frame
	_equals(field.code, "ZZZ999", "o que é digitado em minúsculas vira maiúscula no campo")
	_equals(Net._expected_code, "ZZZ999", "e a sexta casa procura a sala sem passar pelo botão")
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

	# Ao vivo: só os jogos que já têm tela de espectador, e o toque vai assistir.
	Net.leave()
	panel._joining = false
	panel.show_live([
		{"code": "LIVE01", "game": "chess", "tc": 0, "host": "Ana", "watchers": 2},
		{"code": "LIVE02", "game": "ludo", "tc": 0, "watchers": 0},
	])
	var live := panel.get_node("%LiveRows").get_children()
	_equals(live.size(), 1, "a lista ao vivo mostra só jogo que dá para assistir")
	_check(panel.get_node("%LiveCaption").visible, "com o título da seção")
	(live[0] as RoomCard).pressed.emit()
	await get_tree().process_frame
	_equals(Net._expected_code, "LIVE01", "tocar na partida ao vivo vai assistir")
	_check(Net.is_spectator, "como espectador")
	panel.show_live([])
	_check(not panel.get_node("%LiveCaption").visible, "sem partida ao vivo a seção some")

	# O mesmo código do campo, pelo botão Assistir.
	Net.leave()
	panel._joining = false
	panel.get_node("%WatchButton").pressed.emit()
	await get_tree().process_frame
	_equals(Net._expected_code, "ZZZ999", "Assistir usa o código digitado")
	_check(Net.is_spectator, "e entra como espectador")

	# Jogo sem tela de espectador é recusado assim que o relay diz qual é.
	panel._on_watching("ludo", 4)
	await get_tree().process_frame
	_check(
		toast._message.contains("não está disponível"),
		"assistir Ludo é recusado com o motivo (obtido: '%s')" % toast._message
	)
	_check(not Net.is_spectator, "e a sala é deixada")

	# "Criar sala" mora aqui também: quem abriu o app para jogar com alguém já está
	# nesta aba, e mandá-lo à coleção de jogos só para voltar é um desvio que não
	# decide nada. A fileira abre a mesma folha do cardápio, já em Online.
	Net.leave()
	panel._joining = false
	panel.create_requested.emit(Game.LUDO)
	await get_tree().process_frame
	_check(screen._sheet.is_open(), "tocar num jogo de Criar sala abre a folha")
	_equals(screen._sheet.mode, Game.Mode.ONLINE, "já em Online")
	screen.go_back()
	_check(not screen._sheet.is_open(), "e o gesto de voltar fecha a folha")

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
