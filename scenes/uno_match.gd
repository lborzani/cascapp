extends Control

## Uma partida de Uno contra três bots, neste aparelho.
##
## O ciclo é curto e a tela não deixa sair dele: **jogue uma carta acesa, ou
## compre**. Não há outro toque possível — a mão apaga o que não serve e o monte
## só acende quando comprar é lance legal, então errar o toque não é um caminho
## que a tela ofereça.
##
## Duas escolhas a mais existem, e as duas só aparecem quando existem de verdade:
##
## - **o curinga** pergunta a cor. Quatro botões, uma vez, e a partida segue;
## - **o 7 com a regra da casa** pergunta com quem trocar. Um botão por adversário
##   — e numa mesa de dois a pergunta não é feita, porque ela tem uma resposta só.
##
## ## Comprar não encerra a vez
##
## Se a carta comprada serve, ela fica acesa sozinha na mão e um botão de passar
## aparece ao lado do monte. É a regra de caixa, e é o único momento da partida em
## que a mão mostra uma carta acesa e todas as outras apagadas mesmo havendo
## outras jogáveis — `UnoRules` restringe a lista de propósito, para a compra não
## virar uma segunda chance de jogar o que já se podia.
##
## ## Rede
##
## Cada aparelho é um assento (`Game.local_seat`), e só o dono da vez joga; os
## outros veem a mesa andar. O lance viaja inteiro (`Net.send_move`) e é conferido
## do outro lado por `UnoRules.validate` contra a lista legal daqui — mão oculta é
## desenho, não segredo do modelo, então todos derivam todas as mãos da semente
## (que chega no `welcome`, em `Net.option`) e podem validar o lance de qualquer um.
## A reconexão repete o histórico sobre a mesma semente, como nos outros jogos.
##
## Cadeira vazia vira bot, e **um aparelho só** os dirige (`Net.bot_driver`): dois
## escolhendo o lance do mesmo bot dariam dois lances para a mesma vez.

const MENU_SCENE := "res://scenes/game_menu.tscn"

## Espera antes de o bot jogar. Ele não pensa, mas precisa parecer que decidiu:
## sem a pausa a vez dele acontece entre dois quadros, e o jogador vê a mão do
## vizinho encolher sem ter visto nada acontecer.
##
## Maior que a do Ludo (1.1s) porque aqui a vez de um bot pode ser **duas coisas**
## — comprar e depois jogar a comprada —, e as duas coladas passam como uma só.
const BOT_THINK := 0.9
## Respiro depois de um lance, antes de a vez seguinte começar.
const AFTER_MOVE := 0.35
## Quanto tempo o aviso de efeito fica na tela. Um +4 aplicado sem aviso é uma mão
## que cresce quatro cartas sem motivo visível.
const READ_EFFECT := 0.9
## O que a máquina leva para gritar UNO ou para pegar quem esqueceu.
##
## Curto de propósito. As duas são ações **livres** — não gastam a vez —, então
## elas acontecem *antes* da jogada de verdade, e com o tempo de reflexão normal a
## vez de um bot passaria a durar dois segundos e meio: um para gritar, outro para
## jogar. O grito é um reflexo, e é assim que ele lê.
const BOT_QUICK := 0.25

## O peso de cada botão de ação, e nenhum é decorativo.
##
## "Duvidar" é vermelho porque é a única jogada da mesa que pode custar mais do
## que evita; "UNO!" é o latão da ação da vez; "Comprar N" e "Pegar" são neutros —
## o primeiro é desistir, o segundo é rotina.
const _ACTION_STYLE := {
	UnoRules.CHALLENGE: &"DangerButton",
	UnoRules.TAKE: &"Button",
	UnoRules.CALL: &"PrimaryButton",
	UnoRules.CATCH: &"AccentButton",
}

var _rules := UnoRules.new()
var _state: MatchState
var _busy := false
## Alguém saiu para valer, ou o link caiu. Nos dois casos a mesa para de aceitar
## toque — a diferença é que o segundo pode voltar.
var _abandoned := false
var _link_down := false
## Lances que chegaram da rede e ainda não foram aplicados. Ver `_drain_incoming`:
## a vez de um bot ou um efeito com aviso dura quase um segundo, e nesse tempo o
## aparelho de quem joga em seguida já pode ter mandado o dele.
var _incoming: Array[Dictionary] = []
var _draining := false
## Cadeiras jogadas por máquina. No solo são as três que sobram.
var _bot_seats := PackedInt32Array()
## Uma vez de bot já foi agendada. Sem isto, cada `_refresh` durante a vez dele
## marcaria outra jogada, e o bot jogaria várias vezes de uma vez.
var _bot_pending := false
## A faixa de cada jogador na coluna da esquerda, na ordem dos assentos.
var _chips: Array[PanelContainer] = []
## Os botões de lance que não é carta, por espécie. Ver [method _build_actions].
var _actions := {}

@onready var _table: UnoView = %Table
@onready var _hand: UnoHand = %Hand
@onready var _banner: Banner = %Toast


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	# Deitado, como Ludo e Metrópole — e aqui por um motivo próprio: a mesa é um
	# anel de até seis jogadores em volta do monte, e em retrato ele fica com
	# metade da largura enquanto o leque da mão, que é onde se toca, fica com uma
	# faixa. Quem desgira é `Game.reset_to_menu()`, por onde toda saída passa.
	Orientation.to_landscape(get_tree())
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)

	_adopt_rules()
	_state = _rules.initial_state()

	_table.deck_tapped.connect(_on_deck_tapped)
	_hand.card_tapped.connect(_on_card_tapped)
	%PassButton.pressed.connect(_on_pass)
	_build_actions()
	%BackButton.confirmed.connect(_leave)
	%AgainButton.pressed.connect(_restart)
	%OverlayLeaveButton.pressed.connect(_leave)
	%Overlay.visible = false
	%ChoiceLayer.visible = false

	Game.begin_match()
	if Game.mode == Game.Mode.SOLO:
		# Solo é a mesa cheia com um humano só: você é o assento 0, o resto é
		# máquina. É o mesmo caminho de uma sala que não encheu, sem a sala.
		Game.local_seat = 0
		for seat in range(1, _rules.players()):
			_bot_seats.append(seat)
	if Game.mode == Game.Mode.ONLINE:
		Game.local_seat = Net.local_seat
		_bot_seats = Net.bot_seats
		Net.move_received.connect(_on_remote_move)
		Net.opponent_left.connect(_on_opponent_left)
		Net.seat_left.connect(_on_seat_left)
		Net.link_lost.connect(_on_link_lost)
		Net.link_restored.connect(_on_link_restored)
		Net.sync_received.connect(_apply_sync)
		# Os nomes chegam **depois** da tela: quem entra se apresenta no `ready` e
		# quem volta no `resumed`, e os dois caem no meio de uma partida já
		# desenhada. Sem isto o cartão só se corrigia no lance seguinte.
		Net.names_changed.connect(_on_names_changed)
		# A cópia local da lista de máquinas envelhece: ela é lida a cada decisão de
		# vez, e uma cadeira pode deixar de ser de máquina no meio da partida quando
		# alguém senta nela.
		Net.bots_changed.connect(_adopt_bot_seats)
		# Revanche é de dois; numa mesa de até seis, quem quer jogar de novo abre
		# outra sala. O botão sai em vez de mentir — mesma decisão de Ludo e
		# Metrópole.
		%AgainButton.visible = false

	_table.local_seat = Game.local_seat
	_table.names = _seat_names()
	_build_roster()
	_refresh()
	# Depois de montar a partida: quem entrou numa que já estava em curso recebeu o
	# histórico antes desta cena existir, e ele ficou guardado esperando.
	Net.claim_sync()


## Desgira ao sair, como Ludo e Metrópole. `Game.reset_to_menu()` já faz isso e é
## por onde toda saída passa — este é a rede de segurança de quem for liberado por
## outro caminho, que é o que a folha de prints faz a cada foto.
func _exit_tree() -> void:
	Orientation.reset(get_tree())


## Semente e regra da casa. No solo as duas saem do menu e do sorteio local; em
## rede virão juntas dentro de `Net.option`, como em `bomber_match.gd`.
func _adopt_rules() -> void:
	if Game.mode == Game.Mode.ONLINE:
		# A mesa, a semente e a regra da casa vêm de quem abriu a sala, não das
		# escolhas deste aparelho: duas mesas que discordassem de qualquer um dos
		# três não seriam a mesma partida — e a semente é a mais grave, porque as
		# mãos inteiras saem dela. As duas metades viajam juntas em `Net.option`.
		_rules.seats = maxi(UnoRules.MIN_SEATS, Net.seats)
		_rules.match_seed = Game.uno_seed_of(Net.option)
		_rules.sevens = Game.uno_sevens_of(Net.option)
		return
	_rules.seats = Game.players_of(Game.UNO)
	_rules.sevens = Game.uno_sevens
	# Nunca zero: o xorshift trata o zero como ponto fixo e devolveria as 108
	# cartas na ordem de fábrica.
	_rules.match_seed = randi() | 1


# --- ciclo da vez -------------------------------------------------------------


## A mesa aceita toque: é a nossa vez, nada está em curso e o link está de pé.
## Um ponto só para os três guardas — os handlers e o `_refresh` liam versões
## ligeiramente diferentes disto, e uma que esquecesse `_link_down` aceitaria um
## lance no meio de uma reconexão.
func _can_act() -> bool:
	return _my_turn() and not _busy and not _link_down and not _abandoned


func _on_card_tapped(card: int) -> void:
	if not _can_act():
		return
	var options := _moves_for_card(card)
	if options.is_empty():
		return
	if options.size() == 1:
		Sound.play(Sound.Cue.TAP)
		_play(options[0])
		return
	# Mais de um lance para a mesma carta é uma segunda pergunta: qual cor (curinga)
	# ou com quem trocar (o 7 da regra da casa). Nunca as duas — curinga não tem
	# número, então nenhum curinga é um 7.
	Sound.play(Sound.Cue.TAP)
	if UnoRules.is_wild(card):
		_ask(options, "Escolha a cor", true)
	else:
		_ask(options, "Trocar a mão com quem?", false)


func _on_deck_tapped() -> void:
	if not _can_act():
		return
	var move := _move_of_kind(UnoRules.DRAW)
	if move != null:
		_play(move)


func _on_pass() -> void:
	if not _can_act():
		return
	var move := _move_of_kind(UnoRules.PASS)
	if move != null:
		Sound.play(Sound.Cue.TAP)
		_play(move)


## Aplica o lance e conta o que ele causou.
##
## As contagens são lidas **antes** de aplicar: depois do `apply_move` a mão do
## vizinho já cresceu e as mãos já trocaram de dono, e não há como saber o que
## aconteceu — nem a quem.
func _play(move: Move, from_network := false) -> void:
	_busy = true
	_hand.enabled = false
	_table.can_draw = false

	var seat := UnoRules.turn_of(_state)
	var before := _hand_sizes()
	var kind := UnoRules.kind_of(move)

	# O lance sai antes de ser aplicado: `_state.ply` é o índice dele, e depois de
	# aplicar já é o do próximo. É o mesmo `n` que o torna idempotente do outro
	# lado, impedindo uma reconexão de reaplicar o que já chegou.
	if not from_network and Game.mode == Game.Mode.ONLINE:
		Net.send_move({"p": move.path, "pr": 0}, _state.ply)

	_rules.apply_move(_state, move)
	Sound.play(Sound.Cue.CARD if kind == UnoRules.PLAY else Sound.Cue.TAP)
	_refresh_table()

	# A pausa de leitura não vale para as ações livres.
	#
	# Elas têm aviso — o grito e a denúncia são justamente o que os outros
	# precisam ver —, mas o aviso é um toast, que some sozinho no tempo dele. O que
	# está em jogo aqui é outra coisa: quanto a **mesa** fica parada. Gritar UNO e
	# continuar segurando a carta por quase um segundo lê como travamento, e é o
	# próprio jogador que está esperando por si mesmo.
	var told := _announce(seat, move, before)
	var pause := AFTER_MOVE
	if told:
		pause = BOT_QUICK if _is_free_action(kind) else READ_EFFECT
	await _wait(pause)
	if not _alive():
		return

	_busy = false
	var champion := _rules.winner(_state)
	if champion >= 0:
		_finish(champion)
		return
	_refresh()


## O aviso do que o lance causou, ou falso quando não houve o que contar.
##
## Só os efeitos que mexem em mão alheia. Um 5 azul jogado sobre um 5 vermelho não
## precisa de aviso: a carta está no descarte, à vista. Um +4 precisa, porque
## quatro cartas entram numa mão que não é a de quem jogou.
func _announce(seat: int, move: Move, before: Array) -> bool:
	var kind := UnoRules.kind_of(move)
	var who := _seat_name(seat)

	# Os lances que não são carta, e os três novos são justamente os que mexem em
	# mão alheia sem nada mudar no descarte — sem aviso, uma mão cresce seis cartas
	# e a mesa não diz por quê.
	match kind:
		UnoRules.CALL:
			_banner.show_message("%s gritou UNO!" % who, Banner.Kind.ALERT)
			return true
		UnoRules.CATCH:
			_banner.show_message(
				"%s pegou %s sem gritar: +%d." % [
					who, _seat_name(UnoRules.target_of(move)), UnoRules.CATCH_PENALTY
				],
				Banner.Kind.ALERT
			)
			return true
		UnoRules.TAKE:
			var ate: int = UnoRules.hand_size(_state, seat) - int(before[seat])
			_banner.show_message("%s comprou %d." % [who, ate], Banner.Kind.ALERT)
			return true
		UnoRules.CHALLENGE:
			return _announce_challenge(seat, before)
	if kind != UnoRules.PLAY:
		return false

	var value := UnoRules.value_of_card(UnoRules.card_of(move))

	if value == UnoRules.DRAW_TWO or value == UnoRules.WILD_FOUR:
		# A carta **acumula** em vez de entregar: o aviso conta quanto está de pé
		# na mesa e de quem é a resposta, que é a pergunta do momento seguinte.
		var stack := UnoRules.pending(_state)
		_banner.show_message(
			"%s jogou. São %d cartas para %s responder ou engolir."
			% [who, stack, _seat_name(UnoRules.turn_of(_state))],
			Banner.Kind.ALERT
		)
		return true

	if not UnoRules.sevens_on(_state):
		return false

	if value == UnoRules.SEVEN:
		_banner.show_message(
			"%s trocou de mão com %s." % [who, _seat_name(UnoRules.target_of(move))],
			Banner.Kind.ALERT
		)
		return true

	if value == UnoRules.ZERO:
		var mine: int = before[Game.local_seat]
		var now := UnoRules.hand_size(_state, Game.local_seat)
		_banner.show_message(
			"As mãos rodaram. Você tinha %d, agora tem %d." % [mine, now], Banner.Kind.ALERT
		)
		return true
	return false


## Quem pagou a dúvida, lido pelas mãos: o veredito mora no estado e some junto
## com a pilha, então perguntá-lo depois do lance não dá resposta. A diferença de
## tamanho dá, e ela diz a mesma coisa em linguagem de mesa — quem comprou perdeu.
func _announce_challenge(seat: int, before: Array) -> bool:
	var mine: int = UnoRules.hand_size(_state, seat) - int(before[seat])
	if mine > 0:
		_banner.show_message(
			"%s duvidou e errou: +%d." % [_seat_name(seat), mine], Banner.Kind.DANGER
		)
		return true
	for other in UnoRules.seats_of(_state):
		var grew: int = UnoRules.hand_size(_state, other) - int(before[other])
		if grew > 0:
			_banner.show_message(
				"%s duvidou e acertou: %s comprou %d."
				% [_seat_name(seat), _seat_name(other), grew],
				Banner.Kind.ALERT
			)
			return true
	return false


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## A cena ainda está viva. Chamado depois de toda espera: entre o começo e o fim
## de uma delas o jogador pode ter saído, e mexer no tabuleiro de uma cena
## liberada é mexer em nós que já não existem.
func _alive() -> bool:
	return is_inside_tree() and not _abandoned


# --- a segunda pergunta -------------------------------------------------------


## O painel de escolha, usado pelas duas perguntas que uma carta pode fazer.
##
## Um painel e não dois: as duas são a mesma forma — um título e uma fileira de
## botões, um por lance possível — e a diferença é só o rótulo de cada botão. Duas
## telas para isso seriam duas telas para manter alinhadas com o tema.
func _ask(options: Array[Move], title: String, by_color: bool) -> void:
	%ChoiceTitle.text = title
	for child in %ChoiceRow.get_children():
		child.queue_free()

	for move in options:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if by_color:
			var color := UnoRules.declared_color(move)
			button.text = UnoRules.color_name(color)
			# O botão **é** a cor que ele escolhe. Um rótulo escrito "Verde" num
			# botão cinza obriga a ler quatro palavras para escolher uma cor.
			button.add_theme_stylebox_override(
				"normal", AppTheme.box(UnoCardArt.COLORS[color])
			)
			button.add_theme_stylebox_override(
				"pressed", AppTheme.box(UnoCardArt.COLORS[color].darkened(0.2))
			)
			button.add_theme_stylebox_override(
				"hover", AppTheme.box(UnoCardArt.COLORS[color].lightened(0.1))
			)
			button.add_theme_color_override("font_color", AppTheme.TEXT)
		else:
			var target := UnoRules.target_of(move)
			# Quantas cartas ele tem vai junto: é a informação inteira da escolha.
			# Sem ela o jogador escolhe um nome, e o que ele quer escolher é a mão
			# menor da mesa.
			button.text = "%s (%d)" % [
				_seat_name(target), UnoRules.hand_size(_state, target)
			]
			button.theme_type_variation = &"ChipButton"
		button.pressed.connect(_on_choice.bind(move))
		%ChoiceRow.add_child(button)

	%ChoiceLayer.visible = true


func _on_choice(move: Move) -> void:
	%ChoiceLayer.visible = false
	Sound.play(Sound.Cue.TAP)
	_play(move)


# --- bots ---------------------------------------------------------------------


func _my_turn() -> bool:
	var seat := UnoRules.turn_of(_state)
	if _is_bot(seat):
		return false
	return seat == Game.local_seat


func _is_bot(seat: int) -> bool:
	return _bot_seats.has(seat)


## Este aparelho é o que joga pelos bots. No solo não há outro; em rede é o menor
## assento humano (`Net.bot_driver`), e os demais só veem os lances dele chegarem.
## Dois aparelhos escolhendo o lance do mesmo bot dariam dois lances para a mesma
## vez, e as partidas divergiriam no primeiro deles.
func _drives_bots() -> bool:
	if Game.mode != Game.Mode.ONLINE:
		return true
	return Net.drives_bots()


## Quem tem o direito de mandar o lance deste assento: ele mesmo, se for humano; o
## aparelho que joga pelas máquinas, se não for. A legalidade do lance não responde
## isso — um lance legal para o jogador da vez é legal olhando só a mesa, venha ele
## de quem vier —, e sem esta conferência qualquer assento joga a vez de qualquer
## outro.
func _sender_for(seat: int) -> int:
	return Net.bot_driver() if _is_bot(seat) else seat


## A vez de uma máquina, jogada como a de um humano: escolhe e joga. O resultado
## sai pelo mesmo `_play`, então em rede ele viaja como qualquer lance — e o
## histórico não distingue quem o produziu, que é o que mantém a reconexão igual.
func _run_bot() -> void:
	_bot_pending = true
	# O tempo de reflexão é escolhido **antes** da espera, olhando o que a máquina
	# vai fazer: gritar UNO e pegar quem esqueceu são reflexos, não decisões, e com
	# o tempo cheio a vez de um bot passaria a durar dois segundos e meio.
	#
	# A escolha é refeita depois da espera porque a mesa pode ter mudado no meio —
	# um lance de rede que estava na fila, alguém que saiu. O primeiro cálculo
	# serve só para cronometrar.
	var peek := _rules.best_move(_state, _rules.generate_moves(_state))
	var quick := peek != null and _is_free_action(UnoRules.kind_of(peek))
	await _wait(BOT_QUICK if quick else BOT_THINK)
	if not _alive() or _busy:
		_bot_pending = false
		return
	var seat := UnoRules.turn_of(_state)
	if not _is_bot(seat) or not _drives_bots():
		_bot_pending = false
		return

	var moves := _rules.generate_moves(_state)
	var choice := _rules.best_move(_state, moves)
	_bot_pending = false
	if choice == null:
		return
	_play(choice)


## Lance que **não** gasta a vez: depois dele, quem jogou continua jogando.
static func _is_free_action(kind: int) -> bool:
	return kind == UnoRules.CALL or kind == UnoRules.CATCH


# --- rede ---------------------------------------------------------------------


## Lance de outro aparelho, enfileirado antes de ser aplicado.
##
## A fila existe porque uma vez pode durar quase um segundo aqui — um bot pensando,
## um +4 com aviso na tela —, e nesse tempo o aparelho de quem joga em seguida já
## pode ter mandado o dele. Aplicar direto o descartaria, e um lance descartado é
## uma partida que diverge em silêncio.
func _on_remote_move(data: Dictionary) -> void:
	if _abandoned:
		return
	_incoming.append({
		"n": int(data.get("n", -1)),
		"p": PackedInt32Array(data.get("p", [])),
		"seat": int(data.get("seat", -1)),
	})
	_drain_incoming()


## Esvazia a fila, um lance por vez, esperando cada aviso/efeito terminar.
func _drain_incoming() -> void:
	if _draining or _busy or _abandoned or _incoming.is_empty():
		return
	_draining = true
	while not _incoming.is_empty() and not _abandoned and is_inside_tree():
		var entry: Dictionary = _incoming.pop_front()
		# Conferido na hora de aplicar, e não na de receber: uma reconexão reenvia o
		# que o outro lado não sabe que chegou, e a fila pode ter andado desde então.
		var index := int(entry["n"])
		if index >= 0 and index < _state.ply:
			continue
		if index > _state.ply:
			# Falta lance no meio. Pedir o histórico é mais barato que adivinhar — e
			# aplicar por cima do buraco é como as mãos deixam de ser as mesmas, em
			# silêncio. O `_apply_sync` reconstrói e limpa a fila.
			Net.send_sync(_state.history, [])
			break
		# O remetente é conferido aqui, e não ao receber: a fila pode ter andado, e
		# quem tinha o direito de jogar mudou junto com a vez.
		var sender := int(entry["seat"])
		var allowed := _sender_for(UnoRules.turn_of(_state))
		if sender != allowed:
			push_warning(
				"Lance do assento %d recusado: a vez é de quem o assento %d joga."
				% [sender, allowed]
			)
			continue
		# A carta é conferida contra a lista legal daqui — mão oculta é desenho, não
		# segredo do modelo, então todos derivam todas as mãos da semente e podem
		# validar o lance de qualquer um.
		var move := _rules.validate(_state, entry["p"])
		if move == null:
			push_warning("Lance de rede recusado pelas regras locais: %s" % [entry["p"]])
			continue
		await _play(move, true)
	_draining = false


## Reconexão: os dois lados trocam o histórico e quem estiver atrás repete a
## diferença. Como o acaso mora na semente (que veio no `welcome`) e no histórico,
## repetir a lista devolve exatamente as mesmas mãos — sem isso, nenhuma partida de
## baralho sobreviveria a uma queda.
func _apply_sync(moves: Array, _clocks: Array) -> void:
	if moves.size() <= _state.ply:
		return
	var rebuilt := _rules.initial_state()
	for data in moves:
		var move := Move.from_dict(data)
		var checked := _rules.validate(rebuilt, move.path)
		if checked == null:
			push_warning("Histórico recebido não bate com as regras; ignorado.")
			return
		_rules.apply_move(rebuilt, checked)

	_state = rebuilt
	_busy = false
	_incoming.clear()
	# A pergunta aberta era de uma partida que avançou vários lances desde então.
	%ChoiceLayer.visible = false
	_refresh()


func _on_link_lost() -> void:
	_link_down = true
	_refresh()


func _on_link_restored() -> void:
	_link_down = false
	Net.send_sync(_state.history, [])
	_refresh()


func _on_opponent_left() -> void:
	_abandoned = true
	_hand.enabled = false
	_table.can_draw = false
	%PassButton.visible = false
	%OverlayTitle.text = "A partida acabou"
	%OverlaySubtitle.text = "Um dos jogadores saiu."
	%Overlay.visible = true


## Um jogador saiu de uma mesa de mais de dois: a mão dele passa a ser jogada por
## uma máquina e a partida continua. Encerrar seria o que `_on_opponent_left` faz,
## e numa mesa de seis isso é o 4G de uma pessoa acabando o jogo das outras cinco.
func _on_seat_left(seat: int) -> void:
	if _abandoned:
		return
	# O nome sai **antes** de `_bot_seats` ser atualizada: depois dela o assento já
	# é máquina, e o aviso diria "Bot 3 saiu".
	var who := _seat_name(seat)
	_bot_seats = Net.bot_seats
	_link_down = false
	_banner.show_message("%s saiu. Um bot assumiu a mão." % who, Banner.Kind.ALERT)
	_refresh()


## A lista de máquinas mudou no meio da partida: uma cadeira virou bot (alguém
## sumiu) ou deixou de ser (alguém sentou). Relê e redesenha — o cartão e o
## direito de dirigir os bots leem esta lista.
func _adopt_bot_seats() -> void:
	_bot_seats = Net.bot_seats
	_refresh()


func _on_names_changed() -> void:
	_table.names = _seat_names()
	_refresh()


# --- tela ---------------------------------------------------------------------


func _refresh() -> void:
	_refresh_table()
	_refresh_hand()
	_refresh_roster()
	_refresh_status()

	# Lances de rede que chegaram durante uma animação ou uma vez de bot esperam na
	# fila; agora que a mesa está parada, são aplicados.
	_drain_incoming()

	# A vez da máquina começa sozinha, e só depois de a tela já mostrar de quem
	# ela é — e só no aparelho que dirige os bots.
	if (
		_is_bot(UnoRules.turn_of(_state)) and _drives_bots() and not _bot_pending
		and not _busy and not _link_down and not _abandoned
		and _rules.winner(_state) < 0
	):
		_run_bot()


func _refresh_table() -> void:
	_table.state = _state
	_table.can_draw = _can_act() and _move_of_kind(UnoRules.DRAW) != null


func _refresh_hand() -> void:
	_hand.cards = UnoRules.hand_of(_state, Game.local_seat)
	_hand.playable = _playable_now()
	_hand.enabled = _can_act()
	%PassButton.visible = _can_act() and _move_of_kind(UnoRules.PASS) != null
	_refresh_actions()


## Os botões da coluna da direita: um por lance que não é uma carta.
##
## Eles são construídos em código e não na cena pelo mesmo motivo que o resto
## deste app: cada um existe só quando o lance dele existe, e a regra de quando é
## `generate_moves` — pôr cinco botões na cena e escondê-los deixaria a lista de
## quem aparece em dois lugares, um deles desatualizado.
##
## Um botão que existe e não funciona é pior que a ausência dele; aqui a ausência
## é a regra, e é por isso que nenhum deles fica cinza.
func _build_actions() -> void:
	var column: VBoxContainer = %PassButton.get_parent()
	for kind: int in [UnoRules.CHALLENGE, UnoRules.TAKE, UnoRules.CALL, UnoRules.CATCH]:
		var button := Button.new()
		button.custom_minimum_size.y = 46
		button.visible = false
		button.clip_text = true
		button.theme_type_variation = _ACTION_STYLE[kind]
		button.pressed.connect(_on_action.bind(kind))
		# Acima do "Passar", que é o mais comum e por isso o mais perto do polegar
		# na base da coluna.
		column.add_child(button)
		column.move_child(button, %PassButton.get_index())
		_actions[kind] = button


func _refresh_actions() -> void:
	for kind: int in _actions:
		var button: Button = _actions[kind]
		var move := _move_of_kind(kind)
		button.visible = _can_act() and move != null
		if button.visible:
			button.text = _action_label(kind, move)


func _action_label(kind: int, move: Move) -> String:
	match kind:
		UnoRules.TAKE:
			return "Comprar %d" % UnoRules.pending(_state)
		UnoRules.CHALLENGE:
			return "Duvidar"
		UnoRules.CALL:
			return "UNO!"
		_:
			return "Pegar %s" % _seat_name(UnoRules.target_of(move))


func _on_action(kind: int) -> void:
	if not _can_act():
		return
	var move := _move_of_kind(kind)
	if move == null:
		return
	Sound.play(Sound.Cue.TAP)
	_play(move)


## As cartas que a regra aceita **agora**, sem repetição.
##
## Sai de `generate_moves` e não de `is_playable` carta a carta, e a diferença
## aparece exatamente depois de uma compra: ali a lista legal é só a carta
## comprada, e `is_playable` continuaria acendendo a mão inteira — a tela
## ofereceria um toque que a regra recusaria.
func _playable_now() -> PackedInt32Array:
	var codes := PackedInt32Array()
	if not _my_turn():
		return codes
	for move in _rules.generate_moves(_state):
		if UnoRules.kind_of(move) != UnoRules.PLAY:
			continue
		var card := UnoRules.card_of(move)
		if not codes.has(card):
			codes.append(card)
	return codes


func _refresh_status() -> void:
	if _link_down:
		%StatusLabel.text = "Conexão instável; tentando voltar…"
		return
	var seat := UnoRules.turn_of(_state)
	if not _my_turn():
		%StatusLabel.text = "Vez de %s." % _seat_name(seat)
		return
	if UnoRules.drew(_state):
		%StatusLabel.text = "Você comprou. Jogue a carta comprada ou passe."
		return
	if _playable_now().is_empty():
		%StatusLabel.text = "Nada serve. Toque no monte para comprar."
		return
	%StatusLabel.text = "Sua vez. Jogue uma carta ou compre."


## A lista de jogadores na coluna da esquerda: uma faixa por assento, com a cor
## dele, o nome e quantas cartas tem.
##
## Mora aqui e não na mesa porque nome é texto, e texto não cabe em volta de um
## anel de seis lugares — três tentativas de encaixá-lo lá provaram isso. A mesa
## fica com o que é gráfico (a moldura colorida e a contagem), e a coluna com o
## que é escrito. É o mesmo arranjo do Ludo e de Metrópole: painel de texto ao
## lado, tabuleiro no meio.
##
## Construída em laço porque seis cópias no `.tscn` é onde a terceira fica com o
## nome da segunda — e porque a mesa vai de dois a seis, e o `.tscn` teria de
## conter o caso maior e esconder o resto.
func _build_roster() -> void:
	for child in %Roster.get_children():
		child.queue_free()
	_chips.clear()

	for seat in _rules.players():
		var chip := PanelContainer.new()
		chip.size_flags_vertical = Control.SIZE_FILL

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		chip.add_child(row)

		# A tarja da cor à esquerda, e não o cartão inteiro pintado: seis cartões
		# cheios lado a lado competem entre si, e o que a coluna responde é "de quem
		# é a vez", não "quais são as cores".
		var stripe := ColorRect.new()
		stripe.custom_minimum_size = Vector2(5, 0)
		stripe.color = UnoView.color_of_seat(seat)
		row.add_child(stripe)

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.text = _seat_name(seat)
		row.add_child(name_label)

		var count := Label.new()
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		count.add_theme_font_size_override("font_size", 15)
		row.add_child(count)

		%Roster.add_child(chip)
		_chips.append(chip)


func _refresh_roster() -> void:
	var turn := UnoRules.turn_of(_state)
	for seat in _chips.size():
		var chip: PanelContainer = _chips[seat]
		var held := UnoRules.hand_size(_state, seat)
		var row: HBoxContainer = chip.get_child(0)
		var name_label: Label = row.get_child(1)
		var count: Label = row.get_child(2)
		# Relido a cada redesenho, e não só ao montar a coluna. Os nomes dos outros
		# convidados chegam no `ready` deles, que costuma cair **depois** de a cena
		# existir — escrito uma vez só, o cartão ficava em "Jogador 2" ou mostrava o
		# nome certo conforme quem ganhava a corrida. É o mesmo motivo de a cadeira
		# que vira máquina precisar passar a dizer "(bot)".
		name_label.text = _seat_name(seat)
		count.text = str(held)

		# Uma carta na mão é o aviso mais forte da mesa, e é o que o Uno grita em
		# voz alta na vida real. Ele ganha o vermelho do app — o mesmo do que custa
		# caro — e vence o destaque da vez, que é informação mais barata.
		var alarm := held == 1
		var edge := AppTheme.DANGER if alarm else (
			UnoView.color_of_seat(seat) if seat == turn else AppTheme.BORDER
		)
		var style := AppTheme.box(
			AppTheme.DANGER_SOFT if alarm else (
				Color(UnoView.color_of_seat(seat), 0.16) if seat == turn else AppTheme.SURFACE
			),
			AppTheme.RADIUS, edge, 1
		)
		# As margens do tema são de cartão de tela cheia, e aqui são seis faixas
		# empilhadas numa coluna que também carrega o status. Com elas, a lista de
		# uma mesa de seis passava da altura da linha e empurrava a mão para fora
		# da tela — que é o único lugar em que se toca.
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		style.content_margin_left = 0
		style.content_margin_right = 9
		chip.add_theme_stylebox_override("panel", style)
		var ink := AppTheme.TEXT if seat == turn or alarm else AppTheme.TEXT_DIM
		name_label.add_theme_color_override("font_color", ink)
		count.add_theme_color_override("font_color", AppTheme.DANGER if alarm else ink)


## Os nomes na ordem dos assentos, para a mesa desenhar.
##
## Montados uma vez e não a cada quadro: no solo eles não mudam, e em rede o que
## muda é o conteúdo de `Net.player_names`, que tem um sinal próprio para avisar.
func _seat_names() -> PackedStringArray:
	var list := PackedStringArray()
	for seat in _rules.players():
		list.append(_seat_name(seat))
	return list


## Como cada assento se chama. Numerado, e o local é "Você".
##
## O bot não se anuncia como bot no cartão, diferente do Ludo: lá as quatro cores
## existem sempre e o rótulo diz quem as joga. Aqui, no solo, **todos** os outros
## são máquina — escrever "(bot)" três vezes é escrever três vezes a mesma coisa
## que o modo escolhido no menu já disse.
func _seat_name(seat: int) -> String:
	if seat == Game.local_seat:
		return "Você"
	if Game.mode == Game.Mode.ONLINE:
		if _is_bot(seat):
			return "Jogador %d (bot)" % (seat + 1)
		var theirs := Net.name_of(seat)
		if not theirs.is_empty():
			return theirs
	return "Jogador %d" % (seat + 1)


func _hand_sizes() -> Array:
	var sizes := []
	for seat in _rules.players():
		sizes.append(UnoRules.hand_size(_state, seat))
	return sizes


# --- lances disponíveis -------------------------------------------------------


func _moves_for_card(card: int) -> Array[Move]:
	var found: Array[Move] = []
	for move in _rules.generate_moves(_state):
		if UnoRules.kind_of(move) == UnoRules.PLAY and UnoRules.card_of(move) == card:
			found.append(move)
	return found


func _move_of_kind(kind: int) -> Move:
	for move in _rules.generate_moves(_state):
		if UnoRules.kind_of(move) == kind:
			return move
	return null


# --- fim ----------------------------------------------------------------------


func _finish(champion: int) -> void:
	Sound.play(Sound.Cue.WIN)
	_hand.enabled = false
	_table.can_draw = false
	%PassButton.visible = false
	%OverlayTitle.text = "Você venceu" if champion == Game.local_seat else \
		"%s venceu" % _seat_name(champion)
	%OverlaySubtitle.text = "Ficou sem cartas na mão."
	%Overlay.visible = true


func _restart() -> void:
	Game.restart_match()
	# Semente nova: a revanche é outra partida, e repetir o baralho seria repetir
	# a mesma mão inicial para todo mundo.
	_rules.match_seed = randi() | 1
	_state = _rules.initial_state()
	_busy = false
	_bot_pending = false
	%Overlay.visible = false
	%ChoiceLayer.visible = false
	_refresh()


## O gesto de voltar fecha a escolha aberta antes de sair da partida — ela é uma
## camada por cima, e pular uma etapa que o jogador enxerga é a tela sumindo com
## a pergunta na cabeça dele.
func go_back() -> void:
	if %ChoiceLayer.visible:
		%ChoiceLayer.visible = false
		_refresh()
		return
	# Pelo botão ou pelo gesto, sair é a mesma decisão — e uma delas passar sem
	# pergunta é a pergunta não existir.
	%BackButton.ask()


func _leave() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
