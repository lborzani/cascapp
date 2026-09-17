extends Control

## Uma partida de Ludo, quatro jogadores no mesmo aparelho.
##
## O ciclo é sempre o mesmo e a tela não deixa sair dele: **role**, depois
## **escolha o peão**. O dado só aceita toque quando não há dado na mesa, e os
## peões só acendem quando há — em vez de recusar o toque errado com uma
## mensagem, a tela não oferece o toque errado.
##
## Duas conveniências, e as duas evitam toque que não decide nada:
##
## - rolagem sem lance possível passa a vez sozinha, depois de uma pausa para o
##   número ser lido. Obrigar a confirmar "não deu" é pedir um toque cuja única
##   resposta possível é "ok";
## - dado com um único peão possível joga esse peão sozinho. A escolha não
##   existe, e apresentá-la como escolha ensina o jogador a tocar sem olhar.
##
## Cena separada da `match.tscn` pelo mesmo motivo da batalha naval: aquela tela
## é inteira sobre selecionar casa, arrastar peça, relógio e lance planejado, e
## nada disso existe aqui.
##
## ## Em rede
##
## Cada aparelho é uma cor, e a cor é o **assento** na sala (`Game.local_seat`):
## quem abriu é o vermelho, e assim por diante. Só o dono da vez rola o dado; os
## outros três veem o tabuleiro andar.
##
## O dado sorteado num aparelho vira lance no mesmo instante, e é o lance que
## viaja — `LudoRules` guarda o dado dentro do `Move`, então a lista de lances
## reconstrói a partida inteira em qualquer aparelho. É isso que faz a reconexão
## do Ludo ser a mesma dos outros jogos: repetir o histórico.
##
## O que **não** dá para validar é o valor do dado, que é aleatório por
## definição. Confia-se no aparelho de quem rolou, e em nada além disso: o peão
## que ele move é conferido contra a lista de lances legais daqui, como em todos
## os outros jogos.

## ## Os bots
##
## Cadeira vazia vira máquina, e o jogo é o mesmo: o bot rola o dado e escolhe o
## peão pelas quatro regras de bolso de `LudoRules.best_move()`.
##
## **Quem executa um bot é um aparelho só.** No solo é este; em rede é sempre o
## assento 0, e os lances dele saem pela mesma mensagem de um lance humano. Dois
## aparelhos rolando o dado do mesmo bot dariam dois valores para a mesma vez, e
## as quatro partidas divergiriam no primeiro deles — o oposto do que a lista de
## lances promete.

const MENU_SCENE := "res://scenes/main_menu.tscn"
## Pausa entre o dado parar e o que ele causa — o lance automático, ou a vez
## passando.
##
## É tempo de **ler**, e ler um número que acabou de assentar leva mais do que
## parece: a primeira versão passava em meio segundo e a partida inteira dava a
## impressão de estar sendo jogada por outra pessoa. Numa mesa de quatro, três
## em cada quatro vezes são de outro jogador — se elas passam voando, ninguém
## acompanha a partida em que está.
const READ_DIE := 0.95
## Espera antes de o bot rolar. Ele não pensa, mas precisa parecer que decidiu:
## sem a pausa a vez dele acontece entre dois quadros, e o jogador vê o
## tabuleiro diferente sem ter visto nada acontecer.
const BOT_THINK := 1.1
## Respiro depois do lance, antes de a vez seguinte começar. Sem ele o dado da
## próxima vez sai enquanto o peão da anterior ainda está pousando.
const AFTER_MOVE := 0.35

var _rules := LudoRules.new()
var _state: MatchState
## Lances possíveis com o dado que está na mesa. Vazio quando não há dado.
var _pending: Array[Move] = []
var _die := 0
var _busy := false
## Alguém saiu para valer, ou o link caiu. Nos dois casos o tabuleiro para de
## aceitar toque — a diferença é que o segundo pode voltar.
var _abandoned := false
var _link_down := false
## Cores jogadas por máquina. Vem do modo: no solo são as três que sobram, em
## rede é o que quem abriu decidiu ao começar sem a mesa cheia.
var _bot_seats := PackedInt32Array()
## Uma vez de bot já foi agendada. Sem isto, cada `_refresh` durante a vez dele
## marcaria outra rolagem, e o bot jogaria várias vezes de uma vez.
var _bot_pending := false

var _match_status: MatchStatus = null
## Uma faixa de cor por jogador, na ordem das cores.
var _chips: Array[PanelContainer] = []

@onready var _board: LudoView = %Board
@onready var _dice: DieView = %Die
@onready var _banner: Banner = %Toast


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	# Deitado, como Metrópole. Quem desgira é `Game.reset_to_menu()`, por onde
	# toda saída passa.
	Orientation.to_landscape(get_tree())
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)

	_state = _rules.initial_state()
	_board.state = _state
	_board.token_tapped.connect(_on_token_tapped)
	_dice.rolled.connect(_on_die_rolled)
	%BackButton.confirmed.connect(_leave)
	%AgainButton.pressed.connect(_restart)
	%OverlayLeaveButton.pressed.connect(_leave)
	%Overlay.visible = false

	# No topo do placar, e não na coluna do dado: a coluna do dado é onde se **age**
	# nesta tela, e a faixa não é para agir. O placar já é a coluna do "como está a
	# partida", e a faixa é mais uma linha dessa resposta.
	#
	# A coluna tem 150 px, então a faixa quebra em duas ou três linhas — é para isso
	# que ela é um `HFlowContainer`, e é a mesma faixa das telas de retrato onde
	# sobra largura.
	Game.begin_match()
	_match_status = MatchStatus.create()
	%Scoreboard.add_child(_match_status)
	%Scoreboard.move_child(_match_status, 0)

	if Game.mode == Game.Mode.SOLO:
		# Solo é a mesa cheia com um humano só: você é o vermelho, as outras três
		# cores são máquina. É o mesmo caminho de uma sala on-line que não
		# encheu, sem a sala.
		Game.local_seat = 0
		for seat_index in range(1, LudoRules.PLAYERS):
			_bot_seats.append(seat_index)
	if Game.mode == Game.Mode.ONLINE:
		Game.local_seat = Net.local_seat
		_bot_seats = Net.bot_seats
		Net.move_received.connect(_on_remote_move)
		Net.opponent_left.connect(_on_opponent_left)
		Net.seat_left.connect(_on_seat_left)
		Net.seat_returned.connect(_on_seat_returned)
		Net.link_lost.connect(_on_link_lost)
		Net.link_restored.connect(_on_link_restored)
		Net.sync_received.connect(_apply_sync)
		# Os nomes chegam **depois** da tela: quem entra se apresenta no `ready` e
		# quem volta no `resumed`, e os dois caem no meio de uma partida já
		# desenhada. Sem isto o cartão só se corrigia no lance seguinte — e numa
		# mesa parada esperando alguém, nunca.
		Net.names_changed.connect(_refresh)
		# A cópia local da lista de máquinas envelhece: ela é lida a cada decisão
		# de vez, e uma cadeira pode deixar de ser de máquina no meio da partida
		# quando alguém senta nela.
		Net.bots_changed.connect(_adopt_bot_seats)
		# Revanche é de dois; numa mesa de quatro, quem quer jogar de novo abre
		# outra sala. O botão sai em vez de mentir.
		%AgainButton.visible = false

	_build_scoreboard()
	# Para o fim da coluna, depois das faixas de cor.
	#
	# Na cena ele é o primeiro filho — é lá que um nó escrito à mão cabe —, mas as
	# faixas nascem em laço e entram depois dele, e a de contexto é movida para o
	# topo. Sem esta linha o botão de sair fica encravado entre o placar e a
	# primeira cor, que é o meio da coluna.
	%Scoreboard.move_child(%BackButton, -1)
	_refresh()
	# Depois de montar a partida: quem entrou numa que já estava em curso recebeu o
	# histórico antes desta cena existir, e ele ficou guardado esperando.
	Net.claim_sync()


## Desgira ao sair, como Metrópole. `Game.reset_to_menu()` já faz isso e é por
## onde toda saída passa — este é a rede de segurança de quem for liberado por
## outro caminho, que é o que a folha de prints faz a cada foto.
func _exit_tree() -> void:
	Orientation.reset(get_tree())


# --- ciclo da vez -------------------------------------------------------------


## Sorteado, mostrado, e só então usado. O `DieView` decide o número no instante
## do toque e avisa quando termina de girar, então o que chega aqui já é o
## resultado — a animação não tem voto.
func _on_die_rolled(value: int) -> void:
	Sound.play(Sound.Cue.DICE)
	_die = value
	_pending = _rules.moves_for(_state, value)
	if _pending.is_empty():
		# Não deveria acontecer: o gerador devolve um lance de passar quando não
		# há peão que ande. Se acontecer, passar a vez é a recuperação honesta.
		_advance_turn()
		return

	# As duas esperas abaixo duram quase um segundo, e nesse tempo cabe um toque
	# em "Sair". Sem a guarda, `_play` continua e mexe no tabuleiro de uma cena que
	# já saiu da árvore — as outras três telas do app guardam depois de cada
	# espera, e esta guardava só lá dentro, tarde demais.
	if _pending.size() == 1 and LudoRules.token_of(_pending[0]) == LudoRules.PASS:
		_status("%s tirou %d e não tem lance." % [_color_name(), value])
		await _wait(READ_DIE)
		if _alive():
			_play(_pending[0])
		return

	if _pending.size() == 1:
		_status("%s tirou %d." % [_color_name(), value])
		await _wait(READ_DIE)
		if _alive():
			_play(_pending[0])
		return

	_status("%s tirou %d. Escolha o peão." % [_color_name(), value])
	_refresh()


func _on_token_tapped(token: int) -> void:
	if _busy or _pending.is_empty() or not _my_turn():
		return
	for move in _pending:
		if LudoRules.token_of(move) == token:
			_board.picked = token
			Sound.play(Sound.Cue.TAP)
			_play(move)
			return


## Aplica o lance e conta o que ele causou. A leitura acontece **antes** de
## aplicar — depois do `apply_move` o peão capturado já está na base, e não há
## como saber que ele estava na trilha.
func _play(move: Move, from_network := false) -> void:
	_busy = true
	_board.movable = PackedInt32Array()
	var player := LudoRules.turn_of(_state)
	var token := LudoRules.token_of(move)
	# Lido **antes** de aplicar: depois do `apply_move` o peão já está no destino
	# e quem ele derrubou já está na base, e não há como saber de onde nenhum dos
	# dois saiu — nem que houve captura.
	var origin := _origins(move)
	var captured := _captured_names(origin)

	# O lance sai antes de ser aplicado aqui: `_state.ply` é o índice dele, e
	# depois de aplicar já é o do próximo. É o mesmo `n` que torna o lance
	# idempotente do outro lado.
	if not from_network and Game.mode == Game.Mode.ONLINE:
		Net.send_move({"p": move.path, "pr": 0}, _state.ply)

	_rules.apply_move(_state, move)
	if token != LudoRules.PASS:
		# Captura em vez de passo quando o lance derruba alguém: os dois soam ao
		# mesmo tempo e o mais grave é o que conta a notícia.
		Sound.play(Sound.Cue.CAPTURE if not captured.is_empty() else Sound.Cue.MOVE)
		await _animate_move(player, token, origin)
	# Respiro depois de o peão pousar. Sem ele o dado da vez seguinte já está
	# rolando enquanto o olho ainda está no peão que acabou de andar.
	await _wait(AFTER_MOVE)
	if not _alive():
		return

	_board.picked = -1
	_die = 0
	_pending = []
	_busy = false

	if not captured.is_empty():
		_banner.show_message(
			"%s capturou %s." % [LudoRules.color_name(player), " e ".join(captured)],
			Banner.Kind.ALERT
		)

	var champion := _rules.winner(_state)
	if champion >= 0:
		_finish(champion)
		return
	_refresh()


## Passar a vez sem lance nenhum. Só existe para o caso degenerado do gerador
## vazio — o caminho normal é o lance de passar, que entra no histórico.
func _advance_turn() -> void:
	_state.meta[LudoRules.TURN] = (LudoRules.turn_of(_state) + 1) % LudoRules.PLAYERS
	_die = 0
	_pending = []
	_refresh()


## De onde saem os peões que este lance mexe: o que anda e os que ele derruba.
##
## Colhido antes de aplicar, porque depois não existe mais: o estado guarda onde
## cada peão **está**, e a animação precisa de onde ele **estava**.
func _origins(move: Move) -> Dictionary:
	var player := LudoRules.turn_of(_state)
	var token := LudoRules.token_of(move)
	var before := LudoRules.progress(_state)
	var result := {"from": before[LudoRules.slot(player, token)], "knocked": []}

	var probe := _state.clone()
	_rules.apply_move(probe, move)
	var after := LudoRules.progress(probe)
	for other in LudoRules.PLAYERS:
		if other == player:
			continue
		for index in LudoRules.TOKENS:
			var slot := LudoRules.slot(other, index)
			if after[slot] == LudoRules.BASE and before[slot] != LudoRules.BASE:
				result["knocked"].append(
					{"player": other, "token": index, "from": before[slot]}
				)
	return result


## O peão anda casa a casa até a posição nova, e os capturados voltam para a
## base. O estado já é o final e não se mexe: quem anda é o desenho.
##
## Um segundo tabuleiro só para a viagem discordaria do verdadeiro no primeiro
## bug — e é o verdadeiro que viaja pela rede. A vista recebe "de onde", "para
## onde" e o tempo, e devolve um sinal quando terminou.
func _animate_move(player: int, token: int, origin: Dictionary) -> void:
	_board.state = _state
	var landing := LudoRules.progress(_state)[LudoRules.slot(player, token)]
	_board.travel(player, token, int(origin["from"]), landing, origin["knocked"])
	await _board.travel_finished


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## A cena ainda está viva e a partida ainda aceita lance. Chamado depois de toda
## espera: entre o começo e o fim de uma delas o jogador pode ter saído, e um
## `_play` numa cena liberada mexe em nós que já não existem.
func _alive() -> bool:
	return is_inside_tree() and not _abandoned


# --- rede ---------------------------------------------------------------------


## Vez em que **este humano** decide. No mesmo aparelho é toda vez que não seja
## de bot — quem segura o celular joga as quatro cores. Em rede, só a do próprio
## assento.
func _my_turn() -> bool:
	var player := LudoRules.turn_of(_state)
	if _is_bot(player):
		return false
	if Game.mode != Game.Mode.ONLINE:
		return true
	return player == Game.local_seat


func _is_bot(player: int) -> bool:
	return _bot_seats.has(player)


## Uma cadeira mudou de dono entre máquina e gente. Relê a lista e redesenha.
##
## Redesenhar junto não é enfeite: o cartão diz "(bot)" e a barra diz de quem é a
## vez, e as duas leem esta lista. Deixar a atualização para o lance seguinte
## mostraria uma pessoa jogando com "(bot)" escrito ao lado do nome dela.
func _adopt_bot_seats() -> void:
	_bot_seats = Net.bot_seats
	_refresh()


## Este aparelho é o que joga pelos bots. No solo não há outro; em rede é o
## assento 0, e os demais só veem os lances dele chegarem.
func _drives_bots() -> bool:
	if Game.mode != Game.Mode.ONLINE:
		return true
	return Net.drives_bots()


## Quem tem o direito de mandar o lance desta cor: ela mesma, se for humana; o
## aparelho que joga pelas máquinas, se não for.
func _sender_for(player: int) -> int:
	return Net.bot_driver() if _is_bot(player) else player


## A vez de uma máquina, jogada como a de um humano: rola, escolhe, joga. O
## resultado sai pelo mesmo `_play`, então em rede ele viaja como qualquer
## lance — e o histórico não distingue quem o produziu, que é o que mantém a
## reconexão funcionando igual.
func _run_bot() -> void:
	_bot_pending = true
	await _wait(BOT_THINK)
	if not _alive() or _busy:
		_bot_pending = false
		return
	var player := LudoRules.turn_of(_state)
	if not _is_bot(player) or not _drives_bots():
		_bot_pending = false
		return

	var die := randi_range(1, 6)
	_die = die
	_dice.value = die
	_pending = _rules.moves_for(_state, die)
	var choice := _rules.best_move(_state, _pending)
	if choice == null:
		_bot_pending = false
		_advance_turn()
		return
	_status("%s tirou %d." % [_color_name(), die])
	await _wait(READ_DIE)
	_bot_pending = false
	if _alive():
		_play(choice)


## Lance de outro aparelho. O dado vem dentro dele e é aceito — é aleatório, não
## há como conferir. O **peão** é conferido: só entra o que a lista de lances
## legais daqui também produziria.
func _on_remote_move(data: Dictionary) -> void:
	if _abandoned:
		return
	var index := int(data.get("n", -1))
	# Lance que já temos: uma reconexão reenvia o que o outro lado não sabe que
	# chegou, e reaplicá-lo faria a partida andar duas vezes.
	if index >= 0 and index < _state.ply:
		return
	if index > _state.ply:
		# Falta lance no meio. Pedir o histórico é mais barato que adivinhar — e
		# aplicar o que chegou por cima do buraco é como as quatro cópias deste
		# tabuleiro deixam de ser a mesma partida, em silêncio.
		Net.send_sync(_state.history, [])
		return
	# Quem mandou tem de ser quem tinha o direito de jogar. A legalidade do lance
	# não responde isso: um lance legal para o jogador da vez é legal olhando só o
	# tabuleiro, venha ele de quem vier.
	var sender := int(data.get("seat", -1))
	var allowed := _sender_for(LudoRules.turn_of(_state))
	if sender != allowed:
		push_warning(
			"Lance do assento %d recusado: a vez é de quem o assento %d joga."
			% [sender, allowed]
		)
		return
	var path := PackedInt32Array(data.get("p", []))
	if path.size() != 2:
		return
	for move in _rules.moves_for(_state, path[0]):
		if LudoRules.token_of(move) == path[1]:
			_die = path[0]
			_dice.value = _die
			_pending = []
			_play(move, true)
			return
	push_warning("Lance de rede recusado pelas regras locais: %s" % [path])


## Reconexão: os dois lados trocam o histórico e quem estiver atrás repete a
## diferença. Como o dado viaja dentro do lance, repetir a lista devolve
## exatamente a mesma posição — sem isso, nenhuma partida de dado sobreviveria a
## uma queda.
func _apply_sync(moves: Array, _clocks: Array) -> void:
	if moves.size() <= _state.ply:
		return
	var rebuilt := _rules.initial_state()
	for data in moves:
		var move := Move.from_dict(data)
		if move.path.size() != 2:
			return
		var legal := false
		for candidate in _rules.moves_for(rebuilt, move.path[0]):
			if LudoRules.token_of(candidate) == move.path[1]:
				_rules.apply_move(rebuilt, candidate)
				legal = true
				break
		if not legal:
			push_warning("Histórico recebido não bate com as regras; ignorado.")
			return
	_state = rebuilt
	_die = 0
	_pending = []
	_busy = false
	_refresh()


func _on_link_lost() -> void:
	_link_down = true
	_status("Conexão instável; tentando voltar…")
	_refresh()


func _on_link_restored() -> void:
	_link_down = false
	Net.send_sync(_state.history, [])
	_refresh()


func _on_opponent_left() -> void:
	_abandoned = true
	_board.movable = PackedInt32Array()
	_dice.enabled = false
	%OverlayTitle.text = "A partida acabou"
	%OverlaySubtitle.text = "Um dos jogadores saiu."
	%Overlay.visible = true


## Uma cor saiu da mesa: ela vira máquina e a partida continua.
##
## Encerrar seria o que `_on_opponent_left` faz, e numa mesa de quatro isso é o
## 4G de uma pessoa acabando o jogo das outras três. A cor já tem um jogador
## pronto — é o mesmo bot da sala que não enche.
func _on_seat_left(seat: int) -> void:
	if _abandoned:
		return
	var who := LudoRules.color_name(seat)
	_bot_seats = Net.bot_seats
	_link_down = false
	_banner.show_message("%s saiu. Um bot joga até a volta." % who, Banner.Kind.ALERT)
	_refresh()


## A cor deixou de ser máquina: quem tinha caído voltou, ou alguém sentou numa
## cadeira que a mesa começou sem.
func _on_seat_returned(seat: int) -> void:
	if _abandoned:
		return
	_bot_seats = Net.bot_seats
	_banner.show_message(
		"%s assumiu o lugar do bot." % LudoRules.color_name(seat), Banner.Kind.INFO
	)
	_refresh()


# --- tela ---------------------------------------------------------------------


func _refresh() -> void:
	_board.state = _state
	if _match_status != null:
		_match_status.rounds = _rules.rounds_played(_state)
	_board.movable = _movable_tokens() if _my_turn() else PackedInt32Array()
	var player := LudoRules.turn_of(_state)
	_dice.tint = LudoView.COLORS[player]
	_dice.enabled = _pending.is_empty() and not _busy and _my_turn() and not _link_down
	if _pending.is_empty():
		_dice.value = 0
		if _link_down:
			_status("Conexão instável; tentando voltar…")
		elif _is_bot(player):
			_status("Vez do %s (bot)." % _color_name())
		elif _my_turn() and Game.mode == Game.Mode.ONLINE:
			_status("Sua vez (%s). Toque no dado." % _color_name())
		elif _my_turn():
			_status("Vez do %s. Toque no dado." % _color_name())
		else:
			_status("Vez do %s." % _color_name())
	_update_scoreboard()

	# A vez da máquina começa sozinha, e só depois de a tela já estar mostrando
	# de quem ela é.
	if (
		_is_bot(player) and _drives_bots() and not _bot_pending
		and not _busy and not _link_down and not _abandoned
		and _rules.winner(_state) < 0
	):
		_run_bot()


## Peões que o dado da mesa consegue mover. Vazio antes da rolagem, e é o que
## mantém o tabuleiro visivelmente parado até haver o que decidir.
func _movable_tokens() -> PackedInt32Array:
	var tokens := PackedInt32Array()
	for move in _pending:
		var token := LudoRules.token_of(move)
		if token != LudoRules.PASS and not tokens.has(token):
			tokens.append(token)
	return tokens


func _status(text: String) -> void:
	%StatusLabel.text = text


func _color_name() -> String:
	return LudoRules.color_name(LudoRules.turn_of(_state))


## Cores derrubadas por este lance, pelo nome, sem repetir. Sai da mesma leitura
## que alimenta a animação: quem foi capturado é quem volta para a base, e
## descobrir isso duas vezes seria duas chances de discordar.
func _captured_names(origin: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for entry in origin["knocked"]:
		var name := LudoRules.color_name(int(entry["player"]))
		if not names.has(name):
			names.append(name)
	return names


## Uma faixa por cor, com quantos peões já chegaram. Construída em laço porque
## quatro cópias no `.tscn` é onde a terceira fica com o nome da segunda.
##
## Em coluna sob o tabuleiro, ao lado do dado. Em linha no topo ela disputava a
## largura da tela com as próprias cores do tabuleiro logo abaixo, e o dado —
## que é a única coisa aqui em que se toca — ficava jogado num canto do rodapé.
## Agora as duas metades de baixo respondem uma pergunta cada: à esquerda como
## está a partida, à direita o que fazer agora.
## As faixas ficam guardadas numa lista, e não procuradas por posição na coluna.
##
## A coluna deixou de ser só das faixas quando a de contexto entrou no topo dela,
## e os dois lados do acoplamento por índice quebraram na mesma hora: o laço de
## limpeza apagava a faixa de contexto junto, e `get_child(player)` passou a
## devolver o nó errado — um `PanelContainer` esperado, um `HFlowContainer`
## recebido. Com a lista, quem mora na coluna deixa de ser problema de quem
## desenha as cores.
func _build_scoreboard() -> void:
	for chip in _chips:
		chip.queue_free()
	_chips.clear()
	for player in LudoRules.PLAYERS:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Deitado a coluna tem a altura do tabuleiro, e as quatro faixas a dividem
		# entre si. Em retrato elas eram uma fileira baixa embaixo do tampo, e o
		# nome disputava a linha com o placar.
		chip.size_flags_vertical = Control.SIZE_EXPAND_FILL
		chip.add_theme_stylebox_override("panel", _chip_style(player, false))

		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 2)
		chip.add_child(column)

		# Duas linhas, e não uma. "Vermelho 2/4" numa linha só obriga a separar o
		# nome do placar com o olho; separados, o placar vira número grande e o
		# nome vira rótulo — que é a hierarquia certa, porque o que muda durante a
		# partida é o número.
		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(name_label)

		var score := Label.new()
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score.add_theme_font_size_override("font_size", 20)
		column.add_child(score)

		%Scoreboard.add_child(chip)
		_chips.append(chip)


func _update_scoreboard() -> void:
	var turn := LudoRules.turn_of(_state)
	for player in LudoRules.PLAYERS:
		var chip: PanelContainer = _chips[player]
		chip.add_theme_stylebox_override("panel", _chip_style(player, player == turn))
		var column: VBoxContainer = chip.get_child(0)
		var name_label: Label = column.get_child(0)
		var score: Label = column.get_child(1)
		# Nome inteiro, e não a abreviação: em coluna sobra largura, e "Vermelho"
		# não precisa ser decifrado como "VM".
		# A cor é a identidade do jogador aqui, então ela é sempre o rótulo — o
		# nome entra como quem está **sentado** naquela cor, e não no lugar dela.
		# Trocar "Vermelho" pelo nome quebraria a única ligação entre a faixa e o
		# peão no tabuleiro.
		var who := LudoRules.color_name(player)
		if Game.mode != Game.Mode.HOTSEAT and player == Game.local_seat:
			who = "%s (você)" % who
		elif _is_bot(player):
			who = "%s (bot)" % who
		elif Game.mode == Game.Mode.ONLINE:
			var theirs := Net.name_of(player)
			if not theirs.is_empty():
				who = "%s (%s)" % [who, theirs]
		name_label.text = who
		score.text = "%d/%d" % [LudoRules.finished(_state, player), LudoRules.TOKENS]
		var tint := AppTheme.TEXT if player == turn else AppTheme.TEXT_DIM
		name_label.add_theme_color_override("font_color", tint)
		score.add_theme_color_override("font_color", tint)


## A cor preenche a faixa de quem joga e só contorna as outras. Quatro faixas
## cheias competiriam entre si, e a pergunta que a barra responde é "de quem é a
## vez", não "quais são as cores".
func _chip_style(player: int, is_turn: bool) -> StyleBoxFlat:
	var color: Color = LudoView.COLORS[player]
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(AppTheme.RADIUS)
	style.bg_color = Color(color, 0.85 if is_turn else 0.12)
	style.border_color = Color(color, 1.0 if is_turn else 0.45)
	style.set_border_width_all(1)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _finish(champion: int) -> void:
	Sound.play(Sound.Cue.WIN)
	_board.movable = PackedInt32Array()
	_dice.enabled = false
	%OverlayTitle.text = "%s venceu" % LudoRules.color_name(champion)
	%OverlaySubtitle.text = "Quatro peões em casa."
	%Overlay.visible = true


func _restart() -> void:
	Game.restart_match()
	_match_status.started_at = Game.match_started_at
	_state = _rules.initial_state()
	_die = 0
	_pending = []
	_busy = false
	_bot_pending = false
	%Overlay.visible = false
	_refresh()


func go_back() -> void:
	# Pelo botão ou pelo gesto, sair é a mesma decisão.
	%BackButton.ask()


func _leave() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
