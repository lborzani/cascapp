extends Control

## Drives one game. Both devices run the identical ruleset, so a move that
## arrives over the network is only accepted if it is also legal locally.

const MENU_SCENE := "res://scenes/game_menu.tscn"
## Piso de espera antes de o bot jogar, mesmo que ele já tenha decidido. Sem ele
## o nível fácil responde antes de o próprio lance do jogador terminar de andar,
## e a partida vira um pingue-pongue em que ninguém vê o que aconteceu.
const BOT_MIN_THINK := 0.45
const PROMOTION_NAMES := {
	Board.Kind.QUEEN: "Dama",
	Board.Kind.ROOK: "Torre",
	Board.Kind.BISHOP: "Bispo",
	Board.Kind.KNIGHT: "Cavalo",
}

var _ruleset: Ruleset
var _state: MatchState
var _legal: Array[Move] = []
var _selection := PackedInt32Array()
var _pending_promotions: Array[Move] = []
var _outcome := Ruleset.Outcome.ONGOING
## Transient explanation for the last tap, shown instead of the usual status.
var _hint := ""
## Lado para o qual o xeque já foi anunciado, para o aviso não repetir a cada toque.
var _announced_check := -1
## Verdadeiro quando o oponente abandonou: o tabuleiro para de aceitar toques
## mesmo com a partida sem desfecho pelas regras.
var _abandoned := false
## Lances em notação, na ordem jogada. Derivado, não autoritativo: `_state.history`
## continua sendo a verdade, e isto é a leitura dela — por isso é reconstruído
## inteiro quando o resync reconstrói a partida.
var _notation := PackedStringArray()
## Lado → peças que ele capturou (inteiros de `Board.piece`).
var _captured := {}
## Lado → segundos restantes. Vazio quando a partida não tem relógio.
var _clock := {}
## Lado que perdeu no tempo, ou -1. Como o abandono, é um fim que as regras do
## tabuleiro não conhecem: `Ruleset.outcome` continua dizendo ONGOING.
var _flagged := -1
## Último segundo desenhado, para o cartão não ser redesenhado 60 vezes por
## segundo mostrando o mesmo texto.
var _clock_shown := -1
## Aparelho deitado na mesa entre os dois jogadores, cada peça apontando para o
## dono. Só no jogo no mesmo aparelho.
var _table_mode := false

## Corrente de lances planejados, achatada em pares `[origem, destino, …]`, e a
## casa erguida enquanto o elo seguinte é montado.
##
## Guardada em casas e não como `Move`: o lance ainda não existe na posição atual,
## e só vai existir — ou não — depois que o oponente jogar. Um elo sai por vez, e
## o que falhar leva o resto junto. Ver [method _run_premove].
var _premove := PackedInt32Array()
var _premove_pick := Board.NO_SQUARE

## Teto de elos na corrente.
##
## Não é limite de memória — são oito inteiros. É limite de duas outras coisas: do
## que cabe legível no tabuleiro (quatro elos já são oito casas marcadas, com o
## número da ordem em cada destino) e do que vale a pena planejar sobre uma
## hipótese que ignora o oponente. O quinto elo pressupõe quatro lances seguidos
## do adversário sem consequência nenhuma, e a chance de ele ainda ser jogável
## quando chegar a vez dele é baixa o bastante para o plano atrapalhar mais que
## ajudar.
const PREMOVE_MAX_LINKS := 4

## O adversário local. Existe sempre; só é acionado no modo solo.
var _bot := Bot.new()
## Um lance do bot foi pedido e ainda não foi jogado.
var _bot_pending := false
var _bot_wait := 0.0

## Estado do convite de revanche. `ASKED` = pedimos e esperamos; `INVITED` = o
## oponente pediu e a resposta é nossa.
enum Rematch { IDLE, ASKED, INVITED }
var _rematch := Rematch.IDLE

@onready var _board: BoardView = %Board
var _match_status: MatchStatus = null
@onready var _banner: Banner = %Banner
@onready var _top_last_move: LastMoveLine = %TopLastMove
@onready var _bottom_last_move: LastMoveLine = %BottomLastMove


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	# Entrada curta: troca de tela sem corte seco.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)
	_ruleset = Game.make_ruleset()
	if Game.mode == Game.Mode.ONLINE:
		Game.local_side = Net.local_side
		Net.move_received.connect(_on_remote_move)
		Net.opponent_left.connect(_on_opponent_left)
		Net.rematch_requested.connect(_on_rematch_requested)
		Net.rematch_accepted.connect(_on_rematch_accepted)
		Net.rematch_declined.connect(_on_rematch_declined)
		Net.link_lost.connect(_on_link_lost)
		Net.link_restored.connect(_on_link_restored)
		Net.sync_received.connect(_apply_sync)
		# Os nomes chegam **depois** da tela: quem entra se apresenta no `ready` e
		# quem volta no `resumed`, e os dois caem no meio de uma partida já
		# desenhada. Sem isto o cartão só se corrigia no lance seguinte.
		Net.names_changed.connect(_refresh)
		# Orientação decidida pelo lado que se joga, e não por botão: em rede as
		# pretas veem o tabuleiro do lado delas, e é o único arranjo certo.
		_board.flipped = Game.local_side == Board.Side.BLACK
	elif Game.mode == Game.Mode.SOLO:
		# Contra o bot vale a mesma regra: quem escolheu jogar de pretas vê o
		# tabuleiro do lado das pretas.
		_board.flipped = Game.local_side == Board.Side.BLACK

	# Modo mesa é o jogo no mesmo aparelho: cada peça e o cartão de cima apontam
	# para o dono, e o aparelho fica parado sobre a mesa. Em rede cada um vê a
	# própria tela e nada disso faz sentido.
	_table_mode = Game.mode == Game.Mode.HOTSEAT
	_board.table_mode = _table_mode
	%TopCard.upside_down = _table_mode
	_top_last_move.upside_down = _table_mode

	_board.ruleset = _ruleset
	_board.square_tapped.connect(_on_square_tapped)
	%ExitButton.confirmed.connect(_exit)
	%RematchButton.pressed.connect(_request_rematch)
	%RematchDeclineButton.pressed.connect(_decline_rematch)
	%ResultExitButton.pressed.connect(_exit)
	%PromotionLayer.visible = false
	%ResultLayer.visible = false

	# A faixa entra por código, e não pelo `.tscn`, pelo mesmo motivo nas cinco
	# telas: é o mesmo nó em cinco cenas que não se parecem, e cinco cópias no
	# editor são cinco lugares para editar no dia em que ela mudar.
	#
	# No lugar do `%StatusLabel`, que ficou sem quem o preenchesse. Ele responde a
	# mesma pergunta — o que está acontecendo fora do tabuleiro — e a faixa
	# responde melhor.
	Game.begin_match()
	_match_status = MatchStatus.create()
	var column := %StatusLabel.get_parent()
	column.add_child(_match_status)
	column.move_child(_match_status, %StatusLabel.get_index())
	%StatusLabel.visible = false

	_new_game()
	# Depois de montar a partida: quem entrou numa que já estava em curso recebeu o
	# histórico antes desta cena existir, e ele ficou guardado esperando.
	Net.claim_sync()


func _new_game() -> void:
	# Uma busca em andamento pertence à partida que acabou. Abandonar antes de
	# trocar o estado é o que impede o lance dela de cair no tabuleiro novo.
	_bot.abandon()
	_bot_pending = false
	_state = _ruleset.initial_state()
	_selection.clear()
	_hint = ""
	_announced_check = -1
	_abandoned = false
	_board.cancel_animation()
	_pending_promotions.clear()
	_outcome = Ruleset.Outcome.ONGOING
	_board.last_move = PackedInt32Array()
	_notation = PackedStringArray()
	_captured = _empty_captured()
	_clock = _fresh_clock()
	_flagged = -1
	_clock_shown = -1
	_clear_premove()
	_rematch = Rematch.IDLE
	_refresh_rematch()
	set_process(Game.has_clock() or Game.mode == Game.Mode.SOLO)
	%PromotionLayer.visible = false
	%ResultLayer.visible = false
	_banner.hide_message()
	_recompute()


func _empty_captured() -> Dictionary:
	return {Board.Side.WHITE: [], Board.Side.BLACK: []}


func _fresh_clock() -> Dictionary:
	var initial := Game.clock_initial()
	return {Board.Side.WHITE: initial, Board.Side.BLACK: initial}


## Anota o lance e recolhe o que ele capturou. Tem de rodar **antes** de aplicar:
## depois, a peça capturada já saiu do tabuleiro, a de origem já se moveu, e a
## desambiguação da notação (quais outras peças alcançavam a mesma casa) deixa de
## ser respondível.
##
## `into` é mutado; a notação volta pelo retorno, porque `PackedStringArray` é
## valor em GDScript e um `append` dentro daqui não sairia daqui.
func _record(state: MatchState, move: Move, into: Dictionary) -> String:
	var mover := state.side_to_move
	for square in move.captured:
		into[mover].append(state.squares[square])
	return _ruleset.notation(state, move)


# --- relógio -----------------------------------------------------------------


## Só o lado da vez consome tempo, e só enquanto a partida está de fato correndo.
##
## A pausa durante uma reconexão não é detalhe: sem ela, quem trocasse de Wi-Fi
## para 4G no meio da partida voltaria já derrotado no relógio — e o relay foi
## construído justamente para essa troca não custar a partida.
func _process(delta: float) -> void:
	_tick_bot(delta)
	if not _clock_running():
		return

	var side: int = _state.side_to_move
	_clock[side] = maxf(0.0, float(_clock[side]) - delta)
	if _clock[side] <= 0.0:
		_flag(side)
		return

	var whole := int(ceilf(float(_clock[side])))
	if whole != _clock_shown:
		_clock_shown = whole
		_refresh_cards()


func _clock_running() -> bool:
	if not Game.has_clock() or _flagged >= 0 or _abandoned:
		return false
	if _outcome != Ruleset.Outcome.ONGOING or %PromotionLayer.visible:
		return false
	return Game.mode != Game.Mode.ONLINE or Net.connected


## Cair no tempo é derrota, mesmo com a posição ganha — mas não quando o outro
## lado não tem com que dar mate. Aí é empate, e ignorar isso transformaria um
## empate teórico numa derrota inventada pelo cronômetro.
func _flag(side: int) -> void:
	_flagged = side
	_clock[side] = 0.0
	_board.cancel_animation()
	set_process(false)

	var winner := Board.opponent(side)
	var title := "Tempo esgotado"
	var detail := "%s ficaram sem tempo." % ("Brancas" if side == Board.Side.WHITE else "Pretas")
	if Game.mode != Game.Mode.HOTSEAT:
		detail = "Você perdeu no tempo." if side == Game.local_side else "O oponente perdeu no tempo."
	if _ruleset is ChessRules and not (_ruleset as ChessRules).has_mating_material(_state, winner):
		title = "Empate"
		detail = "Tempo esgotado, mas o outro lado não tem material para dar mate."
	_show_overlay(title, detail, true)
	_refresh()


func _clock_text(side: int) -> String:
	if not Game.has_clock():
		return ""
	var remaining := float(_clock.get(side, 0.0))
	# Abaixo de 20s os décimos aparecem: é quando a diferença entre "dá tempo" e
	# "não dá" deixa de ser medida em minutos.
	if remaining < 20.0:
		return "%0.1f" % remaining
	return "%d:%02d" % [int(remaining) / 60, int(remaining) % 60]


# --- input -------------------------------------------------------------------


func _on_square_tapped(square: int) -> void:
	if _abandoned or _flagged >= 0 or _outcome != Ruleset.Outcome.ONGOING:
		return
	if %PromotionLayer.visible:
		return
	# Fora da nossa vez o toque ainda serve para alguma coisa: planejar o lance
	# seguinte. Onde o pré-movimento não vale, `_on_premove_tapped` não faz nada,
	# e o tabuleiro segue mudo como antes.
	if not _is_local_turn():
		_on_premove_tapped(square)
		return

	if _selection.is_empty():
		_try_select(square)
		_refresh()
		return

	var alias := _castling_alias(square)
	if alias != Board.NO_SQUARE:
		square = alias

	var extended := _selection.duplicate()
	extended.append(square)
	var matches := _moves_with_prefix(extended)
	if matches.is_empty():
		# Tapping elsewhere either picks another piece or clears the selection.
		_selection.clear()
		_try_select(square)
		_refresh()
		return

	_selection = extended
	var complete: Array[Move] = []
	var has_continuation := false
	for move in matches:
		if move.path.size() == extended.size():
			complete.append(move)
		else:
			has_continuation = true

	# Um único lance ainda casando com o prefixo significa que **não sobrou
	# escolha**: os saltos que faltam são forçados. Pedir mais toques aí não é
	# oferecer uma decisão, é esconder o lance atrás de uma pergunta sem
	# alternativa — e era o que fazia uma captura dupla parecer recusada, porque
	# tocar na casa de destino não movia nada e a tela não dizia por quê.
	if matches.size() == 1 and has_continuation:
		_play(matches[0], true)
		_refresh()
		return

	if not has_continuation and not complete.is_empty():
		# More than one "complete" move means identical paths differing only by
		# the promotion piece — a chess pawn reaching the last rank. Anything
		# else is a single move to play.
		var promotions := {}
		for move in complete:
			promotions[move.promotion] = move
		if promotions.size() > 1:
			_ask_promotion(complete)
		else:
			_play(complete[0], true)
	elif has_continuation:
		# Sobrou rota a escolher. Sem uma palavra aqui, o jogador fica olhando
		# uma peça que não andou, sem saber que o lance ainda não terminou.
		_hint = "A captura continua: toque na próxima casa."
		_banner.show_message(_hint, Banner.Kind.INFO)
	_refresh()


## With the king selected, tapping your own rook means "castle" — that is how
## most people do it, and how the big chess sites accept it. Without this the
## tap lands on a square with no move attached, the selection is dropped, and
## castling looks broken even though the move was generated.
func _castling_alias(square: int) -> int:
	if _selection.size() != 1:
		return Board.NO_SQUARE
	var piece := _state.squares[square]
	if piece == 0 or Board.side_of(piece) != _state.side_to_move:
		return Board.NO_SQUARE
	if Board.kind_of(piece) != Board.Kind.ROOK:
		return Board.NO_SQUARE

	var home := 0 if _state.side_to_move == Board.Side.WHITE else 56
	for move in _moves_with_prefix(_selection):
		if not move.tags.has("castle"):
			continue
		var rook_square: int = home + 7 if move.tags["castle"] == "king" else home
		if rook_square == square:
			return move.to_square()
	return Board.NO_SQUARE


## A tap that selects nothing used to be indistinguishable from a frozen board.
## In check that is most of the army — you are down to the handful of pieces that
## can answer it — so the board has to say why instead of going quiet.
func _try_select(square: int) -> void:
	var start := PackedInt32Array([square])
	if not _moves_with_prefix(start).is_empty():
		_selection = start
		_hint = ""
		Sound.play(Sound.Cue.TAP)
		return
	var piece := _state.squares[square]
	if piece == 0 or Board.side_of(piece) != _state.side_to_move:
		# Toque no vazio não faz som: quem errou o alvo por um dedo não precisa de
		# uma notificação disso, e num tabuleiro de 64 casas isso acontece o tempo
		# todo.
		_hint = ""
		return
	_hint = "Essa peça não tem lance legal agora."
	if _check_square() != Board.NO_SQUARE:
		_hint = "Você está em xeque: só valem lances que respondam ao xeque."
	Sound.play(Sound.Cue.ALERT)
	_banner.show_message(_hint, Banner.Kind.ALERT)


func _moves_with_prefix(prefix: PackedInt32Array) -> Array[Move]:
	var found: Array[Move] = []
	for move in _legal:
		if move.starts_with(prefix):
			found.append(move)
	return found


func _ask_promotion(options: Array[Move]) -> void:
	_pending_promotions = options
	for child in %PromotionRow.get_children():
		child.queue_free()
	for move in options:
		var button := Button.new()
		button.text = PROMOTION_NAMES.get(move.promotion, "Promover")
		button.custom_minimum_size = Vector2(0, 56)
		button.pressed.connect(_choose_promotion.bind(move))
		%PromotionRow.add_child(button)
	%PromotionLayer.visible = true


func _choose_promotion(move: Move) -> void:
	%PromotionLayer.visible = false
	_pending_promotions.clear()
	_play(move, true)
	_refresh()


# --- bot ---------------------------------------------------------------------


## Põe o bot a pensar quando a vez virar dele. Chamado no fim de `_recompute()`,
## que é o único lugar por onde toda mudança de posição passa — o lance do
## jogador, a partida nova e a revanche entram todos por ali.
func _maybe_think() -> void:
	if _bot_pending or not Game.bot_turn(_state.side_to_move):
		return
	if _outcome != Ruleset.Outcome.ONGOING or _flagged >= 0:
		return
	_bot_pending = true
	_bot_wait = BOT_MIN_THINK
	# Começa junto com a animação do lance do jogador, e não depois dela: o tempo
	# que a peça leva para andar é tempo de busca de graça.
	_bot.think(Game.game_id, _state, Game.bot_level, _bot_budget())


## Teto de reflexão vindo do relógio do próprio bot. Um vigésimo do que resta dá
## cerca de vinte lances de folga a qualquer altura da partida, e é o que impede
## que ele perca no tempo num ritmo curto — a busca não olha o cronômetro, então
## quem olha por ela é a partida.
##
## Zero quer dizer "sem teto": é o caso sem relógio, e aí o nível manda sozinho.
func _bot_budget() -> int:
	if not Game.has_clock():
		return 0
	return maxi(80, int(float(_clock[Game.bot_side]) * 1000.0 / 20.0))


## O lance do bot entra quando três coisas coincidem: ele decidiu, o piso de
## espera passou, e o lance anterior terminou de andar. As duas últimas não são
## enfeite — um lance que aparece antes de o anterior pousar apaga o anterior da
## tela, e o jogador nunca vê o que ele mesmo jogou.
func _tick_bot(delta: float) -> void:
	if not _bot_pending:
		return
	_bot_wait -= delta
	if _bot_wait > 0.0 or _board.remaining_animation() > 0.0:
		return
	var chosen := _bot.take_move()
	if chosen == null:
		return
	_bot_pending = false

	# Revalidado contra a própria lista legal, como um lance que chega pela rede.
	# A busca trabalhou sobre um clone, e um clone é uma posição paralela: ela
	# *deveria* ser a mesma, e "deveria" não é o que se aplica no tabuleiro.
	for candidate in _legal:
		if candidate.same_as(chosen):
			_play(candidate, false)
			_refresh()
			return
	push_error("Lance do bot recusado: %s" % chosen)


# --- lance planejado ---------------------------------------------------------


## Pré-movimento: escolher o lance enquanto o oponente pensa, para ele sair no
## instante em que a vez chega. Num ritmo curto é o que separa um final jogável
## de uma corrida de toque.
##
## Só em rede e só no xadrez. No mesmo aparelho não existe espera — a vez do
## outro é o outro jogador ali do lado, com o mesmo tabuleiro na frente. E nas
## damas a captura é obrigatória: o lance do oponente decide qual pedra *tem* de
## mover, então quase todo plano nasceria ilegal, e um recurso que falha na
## maioria das vezes atrapalha mais do que ajuda.
func _premove_allowed() -> bool:
	return (
		Game.mode == Game.Mode.ONLINE
		and Net.connected
		and _ruleset is ChessRules
		and _state.side_to_move != Game.local_side
	)


func _on_premove_tapped(square: int) -> void:
	if not _premove_allowed():
		return
	var planned := _premove_state()
	if _premove_pick == Board.NO_SQUARE:
		if _premove_owns(planned, square):
			# Corrente cheia: o toque na própria peça não pode virar um elo, e
			# também não pode apagar um — apagar aqui faria o jogador perder o
			# quarto lance por tentar montar o quinto. Ele é recusado em voz alta.
			if _premove_links() >= PREMOVE_MAX_LINKS:
				_banner.show_message(
					"A sequência planejada já tem %d lances." % PREMOVE_MAX_LINKS,
					Banner.Kind.ALERT
				)
				return
			_premove_pick = square
		elif not _premove.is_empty():
			# O toque que não continua a corrente **apaga o último elo**, e não a
			# corrente inteira.
			#
			# Com um lance só, os dois são a mesma coisa — e era o gesto documentado:
			# qualquer toque fora cancela, sem gastar um botão numa tela que não tem
			# espaço para ele. Encadeando, apagar tudo passa a ser caro demais para um
			# toque errado: quatro decisões perdidas de uma vez. Voltando um elo por
			# toque, cancelar tudo continua possível (são N toques) e desfazer um
			# engano custa um só.
			_premove = _premove.slice(0, _premove.size() - 2)
		_refresh()
		return
	if square == _premove_pick:
		_premove_pick = Board.NO_SQUARE
	elif _premove_owns(planned, square):
		_premove_pick = square
	elif _premove_find(planned, _premove_pick, square) != null:
		_premove.append(_premove_pick)
		_premove.append(square)
		_premove_pick = Board.NO_SQUARE
	else:
		# Destino que a hipótese não oferece: o elo não nasce. Sem isto, o toque
		# armava um lance que a revalidação recusaria depois — e o jogador só
		# descobriria na vez seguinte, quando o plano inteiro fosse descartado.
		_premove_pick = Board.NO_SQUARE
	_refresh()


## A peça é nossa **na hipótese**, que não é a posição de verdade: com elos já
## planejados, a peça de d2 está em d4, e é d4 que o dedo precisa achar.
func _premove_owns(state: MatchState, square: int) -> bool:
	var piece := state.squares[square]
	return piece != 0 and Board.side_of(piece) == Game.local_side


func _clear_premove() -> void:
	_premove = PackedInt32Array()
	_premove_pick = Board.NO_SQUARE


## Quantos elos a corrente tem.
func _premove_links() -> int:
	return _premove.size() / 2


## A posição hipotética sobre a qual o **próximo** elo é escolhido: a de agora com
## a vez trocada, e com todos os elos já planejados aplicados por cima.
##
## É hipótese em dois níveis, e os dois são assumidos:
##
## - a vez é nossa, quando na verdade é do oponente;
## - o oponente **não joga** entre um elo e o seguinte.
##
## A segunda é grosseira e é justamente o que torna a corrente barata: simular o
## que o oponente faria exigiria uma busca por elo, e a resposta dela seria um
## chute de qualquer forma. O preço é pago na hora certa — cada elo é revalidado
## contra a lista legal de verdade no instante em que sai, e o primeiro que não
## existir mais leva a corrente inteira junto.
##
## O `ep` é zerado a cada elo pelo mesmo motivo que no primeiro: o direito de
## *en passant* pertence a quem joga na posição real, e aqui ninguém jogou.
func _premove_state() -> MatchState:
	var hypothetical := _state.clone()
	_premove_take_turn(hypothetical)
	for index in range(0, _premove.size(), 2):
		var link := _premove_find(hypothetical, _premove[index], _premove[index + 1])
		if link == null:
			break
		_ruleset.apply_move(hypothetical, link)
		_premove_take_turn(hypothetical)
	return hypothetical


## Devolve a vez a nós e apaga o *en passant*. Ver [method _premove_state].
func _premove_take_turn(state: MatchState) -> void:
	state.side_to_move = Game.local_side
	state.meta["ep"] = Board.NO_SQUARE


## O lance desta posição que vai de `from` a `to`, ou nulo se ele não existe.
##
## Promoção planejada vira dama: é a escolha em quase toda partida, e a única que
## dá para assumir sem perguntar. Perguntar aqui pararia o lance justamente para
## gastar o tempo que o plano existia para economizar.
func _premove_find(state: MatchState, from: int, to: int) -> Move:
	var fallback: Move = null
	for move in _ruleset.generate_moves(state):
		if move.from_square() != from or move.to_square() != to:
			continue
		if move.promotion == Board.Kind.QUEEN:
			return move
		if fallback == null:
			fallback = move
	return fallback


## Os lances que a peça teria se a vez já fosse nossa, na posição em que os elos
## anteriores já aconteceram. Serve para o jogador ver para onde a peça pode ir;
## sem isso, planejar seria adivinhar.
func _premove_moves(from: int) -> Array[Move]:
	var found: Array[Move] = []
	for move in _ruleset.generate_moves(_premove_state()):
		if move.from_square() == from:
			found.append(move)
	return found


## O primeiro elo sai assim que a vez chega — mas depois de o lance do oponente
## terminar de andar. É o lance dele que o jogador está esperando ver, e cortá-lo
## pela metade esconderia justamente a informação que motivou o plano.
##
## Sai **um** elo por vez, e o resto da corrente fica esperando a vez seguinte. O
## que não pode acontecer é a corrente sobreviver ao elo que falhou: os elos
## seguintes foram escolhidos numa posição que pressupunha o anterior, e jogar o
## segundo sem o primeiro é jogar um lance que ninguém planejou.
func _run_premove() -> void:
	if _premove.size() < 2:
		return
	var wait := _board.remaining_animation()
	if wait > 0.0:
		var expected := _state.ply
		await get_tree().create_timer(wait).timeout
		if _state.ply != expected or _premove.size() < 2:
			return
	if not _is_local_turn() or _outcome != Ruleset.Outcome.ONGOING or _abandoned or _flagged >= 0:
		_clear_premove()
		_refresh()
		return

	var head := _premove_find(_state, _premove[0], _premove[1])
	if head == null:
		# Acontece o tempo todo e não é erro: o lance do oponente tornou o plano
		# impossível. O aviso existe para o jogador não concluir que o toque dele
		# se perdeu no caminho.
		var lost := _premove_links()
		_clear_premove()
		_banner.show_message(
			"O lance planejado deixou de ser possível."
			if lost == 1
			else "O lance planejado deixou de ser possível — a sequência inteira saiu.",
			Banner.Kind.ALERT
		)
		_refresh()
		return
	_premove = _premove.slice(2)
	_premove_pick = Board.NO_SQUARE
	_play(head, true)
	_refresh()


# --- game flow ---------------------------------------------------------------


func _play(move: Move, broadcast: bool) -> void:
	# As peças capturadas somem do estado ao aplicar o lance; a animação precisa
	# saber o que havia ali para poder mostrá-las desaparecendo.
	var taken := []
	for square in move.captured:
		taken.append([square, _state.squares[square]])

	# Índice do lance na partida, capturado antes de aplicá-lo. Vai junto na
	# mensagem para que um lance que chegue duas vezes — o que uma reconexão
	# torna comum — seja reconhecido como repetido em vez de recusado.
	var index := _state.history.size()
	var mover := _state.side_to_move
	_notation.append(_record(_state, move, _captured))
	# Antes de aplicar: `is_capture()` lê o lance, não o tabuleiro, mas o som tem
	# de sair junto com a animação, e ela começa duas linhas abaixo.
	Sound.play(Sound.Cue.CAPTURE if move.is_capture() else Sound.Cue.MOVE)
	_ruleset.apply_move(_state, move)
	_board.last_move = move.path.duplicate()
	_board.play_move(move.path, taken)
	_selection.clear()
	_hint = ""
	# O incremento entra depois do lance, para quem jogou. É o que torna partida
	# curta jogável num celular: sem ele os últimos lances viram corrida de toque.
	if Game.has_clock():
		_clock[mover] = float(_clock[mover]) + Game.clock_increment()
		_clock_shown = -1
	if broadcast and Game.mode == Game.Mode.ONLINE:
		Net.send_move(move.to_dict(), index, _clock_pair())
	_recompute()


## `[brancas, pretas]` em segundos, ou vazio sem relógio.
func _clock_pair() -> Array:
	if not Game.has_clock():
		return []
	return [float(_clock[Board.Side.WHITE]), float(_clock[Board.Side.BLACK])]


## O outro aparelho é a autoridade sobre o próprio relógio, então o que chega
## substitui o que temos em vez de ser mediado — a deriva entre dois cronômetros
## livres cresce a partida inteira, e um lance é a oportunidade natural de zerá-la.
func _adopt_clocks(clocks: Array) -> void:
	if not Game.has_clock() or clocks.size() != 2:
		return
	_clock[Board.Side.WHITE] = float(clocks[0])
	_clock[Board.Side.BLACK] = float(clocks[1])
	_clock_shown = -1


func _recompute() -> void:
	_legal = _ruleset.generate_moves(_state)
	_outcome = _ruleset.outcome(_state)
	if _outcome != Ruleset.Outcome.ONGOING:
		_show_result()
	_refresh()
	_maybe_think()


## Espera o lance terminar de andar antes de cobrir o tabuleiro. O lance que
## decide a partida é o que o jogador mais quer ver, e é justamente o que um
## painel imediato esconderia.
func _show_result() -> void:
	var wait := _board.remaining_animation()
	if wait > 0.0:
		var expected := _state.ply
		await get_tree().create_timer(wait).timeout
		if _abandoned or _outcome == Ruleset.Outcome.ONGOING or _state.ply != expected:
			return
	_show_overlay(_ruleset.outcome_text(_outcome), _result_detail(), true)


## Um único painel para todo fim de partida — vitória, empate ou abandono. Sair
## no meio é um desfecho como qualquer outro, e merece o mesmo tratamento: quem
## ficou precisa saber por que o tabuleiro parou de responder.
func _show_overlay(title: String, detail: String, allow_rematch: bool) -> void:
	%ResultTitle.text = title
	%ResultDetail.text = detail
	%RematchButton.visible = allow_rematch
	# Só quando o painel **abre**. Ele é reaberto por convite de revanche e por
	# oponente que saiu, e tocar a fanfarra de novo em cada um faria a partida
	# parecer que acabou três vezes.
	if not %ResultLayer.visible:
		Sound.play(Sound.Cue.WIN)
	%ResultLayer.visible = true
	_banner.hide_message()
	# Depois do texto: um convite que chegou enquanto a animação do último lance
	# rodava já mudou o estado, e é ele que manda no rótulo do botão.
	if allow_rematch:
		_refresh_rematch()

	var panel: Control = %ResultLayer.get_node("Center/Panel")
	%ResultLayer.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(%ResultLayer, "modulate:a", 1.0, 0.16)
	if panel.size != Vector2.ZERO:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(0.93, 0.93)
		tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _result_detail() -> String:
	if _outcome == Ruleset.Outcome.DRAW:
		return "Empate em %d lances." % _state.ply
	if Game.mode != Game.Mode.HOTSEAT:
		var won := (_outcome == Ruleset.Outcome.WHITE_WINS) == (Game.local_side == Board.Side.WHITE)
		return "Você venceu em %d lances." % _state.ply if won else "Você perdeu em %d lances." % _state.ply
	# Em 'xadrez' a única forma de terminar com o lado a jogar em xeque é o mate.
	if _ruleset is ChessRules and (_ruleset as ChessRules).is_in_check(_state, _state.side_to_move):
		return "Xeque-mate em %d lances." % _state.ply
	return "Partida encerrada em %d lances." % _state.ply


func _on_remote_move(data: Dictionary) -> void:
	var index := int(data.get("n", -1))
	if index >= 0 and index < _state.history.size():
		# Já temos esse lance. Uma reconexão reenvia o que estava em voo, e sem
		# esta guarda ele seria julgado ilegal — que é o mesmo sintoma de um
		# pacote adulterado, com um alarme que assusta à toa.
		return
	if index > _state.history.size():
		# Falta lance no meio. Pedir o histórico é mais barato que adivinhar.
		Net.send_sync(_state.history, _clock_pair())
		return
	# Quem mandou tem de ser quem tinha a vez.
	#
	# Numa mesa de dois só existe um remetente possível, então isto parece sobra —
	# e não é: sem ele o oponente pode mandar um lance **das nossas peças**, que é
	# legal olhando só o tabuleiro e passaria pela conferência abaixo. A
	# legalidade responde "este lance existe", não "este lance é seu".
	var sender := int(data.get("seat", -1))
	if sender != _seat_of(_state.side_to_move):
		push_warning("Lance do assento %d recusado: não é a vez dele." % sender)
		return

	var incoming := Move.from_dict(data)
	for move in _legal:
		if move.same_as(incoming):
			_play(move, false)
			# Depois de aplicar: `_play` soma o incremento local ao lado que
			# jogou, e o valor que veio do dono do relógio é que vale.
			_adopt_clocks(Array(data.get("c", [])))
			_refresh()
			# A vez é nossa de novo: se havia plano, é agora.
			_run_premove()
			return
	# Desync or a tampered packet: refuse it rather than corrupting the board.
	_banner.show_message("Lance inválido recebido do oponente", Banner.Kind.DANGER)
	push_error("Rejected illegal remote move: %s" % incoming)


## Assento de uma cor, numa sala de dois. O assento 0 é de quem abriu, e quem
## abre joga de `Net.HOST_SIDE` — a conta mora aqui e não em `net_link.gd`
## porque cor é conceito de jogo de dois, e aquele arquivo serve mesas de seis.
static func _seat_of(side: int) -> int:
	return 0 if side == Net.HOST_SIDE else 1


## O transporte caiu mas a sessão ainda pode voltar. `Net.connected` já é falso,
## então o tabuleiro para de aceitar toques sozinho; o que falta é dizer por quê,
## porque um tabuleiro mudo é indistinguível de um jogo travado.
func _on_link_lost() -> void:
	if _outcome != Ruleset.Outcome.ONGOING or _abandoned or _flagged >= 0:
		return
	_board.cancel_animation()
	_selection.clear()
	# Persistente: a condição continua verdadeira enquanto durar, e um aviso que
	# some sozinho deixaria o tabuleiro travado sem explicação na tela.
	_banner.show_message("Conexão instável. Tentando reconectar…", Banner.Kind.ALERT, true)
	_refresh()


## Voltamos. Nenhum dos dois lados sabe quantos lances o outro jogou enquanto o
## link estava fora, então os dois mandam o histórico inteiro e quem estiver
## atrás reconstrói a posição — os dois rodam o mesmo ruleset determinístico, e
## a lista de lances é a única coisa que precisa atravessar.
func _on_link_restored() -> void:
	_banner.show_message("Reconectado.", Banner.Kind.INFO)
	Net.send_sync(_state.history, _clock_pair())
	_refresh()


## Reconstrói do zero em vez de aplicar a diferença: replay é a mesma operação
## que o jogo já faz a cada lance, e recomeçar do estado inicial não depende de
## a posição local estar correta — que é justamente o que está em dúvida aqui.
func _apply_sync(moves: Array, clocks: Array = []) -> void:
	if moves.size() < _state.history.size():
		# O outro lado está atrás. Um histórico mais curto é o pedido.
		Net.send_sync(_state.history, _clock_pair())
		return
	if moves.size() == _state.history.size():
		return

	# Tudo em variáveis locais até o replay terminar: um histórico inválido tem
	# de deixar a partida atual intacta, não meio reconstruída.
	var rebuilt := _ruleset.initial_state()
	var notation := PackedStringArray()
	var captured := _empty_captured()
	for entry in moves:
		if entry is not Dictionary:
			_show_desync(rebuilt.history.size())
			return
		var wanted := Move.from_dict(entry)
		var applied := false
		for candidate in _ruleset.generate_moves(rebuilt):
			if candidate.same_as(wanted):
				notation.append(_record(rebuilt, candidate, captured))
				_ruleset.apply_move(rebuilt, candidate)
				applied = true
				break
		if not applied:
			_show_desync(rebuilt.history.size())
			return

	_state = rebuilt
	_notation = notation
	_captured = captured
	_adopt_clocks(clocks)
	_selection.clear()
	# A posição foi reconstruída de outro histórico: um plano montado sobre a
	# anterior não descreve mais nada que se possa jogar.
	_clear_premove()
	_hint = ""
	_announced_check = -1
	_board.cancel_animation()
	_board.last_move = PackedInt32Array()
	if not _state.history.is_empty():
		var last: Dictionary = _state.history[_state.history.size() - 1]
		_board.last_move = PackedInt32Array(last.get("p", []))
	_recompute()


func _show_desync(at_ply: int) -> void:
	_banner.show_message("Não foi possível sincronizar a partida", Banner.Kind.DANGER)
	push_error("Sync rejeitado: lance %d não é legal na posição reconstruída." % at_ply)


func _on_opponent_left() -> void:
	_abandoned = true
	_board.cancel_animation()
	_show_overlay(
		"O oponente saiu",
		"A partida foi encerrada no lance %d." % _state.ply,
		false
	)


# --- revanche ----------------------------------------------------------------


## No mesmo aparelho a revanche é imediata: os dois jogadores estão ali, e pedir
## confirmação a quem está do outro lado da mesa seria pedir duas vezes.
##
## Em rede é convite. Quem pede espera; quem recebe decide. E as cores trocam —
## sem isso o mesmo jogador começa de brancas partida após partida, que é meia
## vantagem repetida para sempre.
func _request_rematch() -> void:
	if Game.mode != Game.Mode.ONLINE:
		_start_rematch()
		return
	# Os dois clicaram quase juntos: o convite dele já chegou, então isto é um
	# acordo, não um pedido novo.
	if _rematch == Rematch.INVITED:
		_accept_rematch()
		return
	_rematch = Rematch.ASKED
	Net.send_rematch()
	_refresh_rematch()


func _on_rematch_requested() -> void:
	# Pedidos cruzados: já tínhamos pedido, e agora sabemos que ele também quer.
	if _rematch == Rematch.ASKED:
		_accept_rematch()
		return
	_rematch = Rematch.INVITED
	_refresh_rematch()


func _accept_rematch() -> void:
	Net.send_rematch_accept()
	_start_rematch()


func _decline_rematch() -> void:
	Net.send_rematch_decline()
	_rematch = Rematch.IDLE
	_refresh_rematch()


func _on_rematch_accepted() -> void:
	if _rematch != Rematch.ASKED:
		return
	_start_rematch()


func _on_rematch_declined() -> void:
	_rematch = Rematch.IDLE
	_refresh_rematch()
	_banner.show_message("O oponente não quis revanche.", Banner.Kind.ALERT)


func _start_rematch() -> void:
	if Game.mode == Game.Mode.ONLINE:
		# Quem jogou de brancas joga de pretas. `Net.local_side` acompanha porque
		# é dele que a próxima reconexão lê o lado.
		Game.local_side = Board.opponent(Game.local_side)
		Net.local_side = Game.local_side
		_board.flipped = Game.local_side == Board.Side.BLACK
	elif Game.mode == Game.Mode.SOLO:
		# Mesma troca, e pelo mesmo motivo: começar sempre de brancas contra o bot
		# é jogar sempre a mesma metade do jogo.
		Game.bot_side = Board.opponent(Game.bot_side)
		Game.local_side = Board.opponent(Game.bot_side)
		_board.flipped = Game.local_side == Board.Side.BLACK
	_rematch = Rematch.IDLE
	# A sala é a mesma e a partida é outra: sem isto o relógio da faixa continuaria
	# contando o tempo da anterior.
	Game.restart_match()
	_match_status.started_at = Game.match_started_at
	_new_game()


## O painel de fim de partida muda de papel conforme o estado do convite: pedir,
## esperar, ou responder.
func _refresh_rematch() -> void:
	var online := Game.mode == Game.Mode.ONLINE
	%RematchDeclineButton.visible = online and _rematch == Rematch.INVITED
	match _rematch:
		Rematch.ASKED:
			%RematchButton.text = "Aguardando o oponente…"
			%RematchButton.disabled = true
		Rematch.INVITED:
			%RematchButton.text = "Aceitar revanche"
			%RematchButton.disabled = false
			%ResultDetail.text = "O oponente quer jogar de novo."
		_:
			%RematchButton.text = "Jogar de novo"
			%RematchButton.disabled = false


## O gesto de voltar é o botão "Sair", inclusive com o painel de fim aberto — lá
## ele já é a única saída, e o painel não é uma camada para desfazer: a partida
## acabou atrás dele.
func go_back() -> void:
	_exit()


func _exit() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)


## Sair da cena com a busca viva derruba o processo, e é uma queda que só aparece
## em quem fecha a partida no segundo em que o bot está pensando — ou seja, quase
## nunca em teste e sempre em uso.
func _exit_tree() -> void:
	_bot.abandon()


# --- presentation ------------------------------------------------------------


func _is_local_turn() -> bool:
	if Game.mode == Game.Mode.HOTSEAT:
		return true
	if Game.mode == Game.Mode.SOLO:
		return not Game.bot_turn(_state.side_to_move)
	return Net.connected and _state.side_to_move == Game.local_side


func _refresh() -> void:
	_board.state = _state
	_board.selection = _selection
	_board.check_square = _check_square()
	if _match_status != null:
		_match_status.rounds = _ruleset.rounds_played(_state)

	var targets := PackedInt32Array()
	var captures := PackedInt32Array()
	var candidates := _moves_with_prefix(_selection)
	for move in candidates:
		if _selection.is_empty() or move.path.size() <= _selection.size():
			continue
		var next := move.path[_selection.size()]
		if move.is_capture():
			if not captures.has(next):
				captures.append(next)
		elif not targets.has(next):
			targets.append(next)

	# Os destinos do plano entram na mesma lista: para o jogador é a mesma
	# pergunta ("para onde essa peça vai?"), e a cor da marcação nas casas de
	# origem e destino é que diz que ainda não é lance.
	if _premove_pick != Board.NO_SQUARE:
		for planned in _premove_moves(_premove_pick):
			var landing := planned.to_square()
			if planned.is_capture():
				if not captures.has(landing):
					captures.append(landing)
			elif not targets.has(landing):
				targets.append(landing)

	_board.premove = _premove
	_board.premove_pick = _premove_pick
	_board.targets = targets
	_board.capture_targets = captures
	_update_preview(candidates)
	_board.refresh()

	_refresh_cards()
	_refresh_last_move()
	_refresh_banner()


## A peça mostrada é a que está **agora** na casa de destino, e não a que saiu:
## depois de uma promoção quem chegou lá é a dama nova, que é o que a notação
## também diz.
##
## No modo mesa a linha é desenhada **duas vezes**, uma de cada lado do
## tabuleiro, com o mesmo conteúdo: quem acabou de jogar sabe o que jogou, quem
## precisa da informação é o outro. Mostrar só do lado de quem moveu deixava a
## resposta de cabeça para baixo justamente para quem tinha a pergunta.
##
## Em rede só a de cima existe: lá cada jogador tem a própria tela, e não há um
## segundo par de olhos do outro lado do aparelho para atender.
func _refresh_last_move() -> void:
	var piece := 0
	var notation := ""
	if not _notation.is_empty() and not _state.history.is_empty():
		var last: Dictionary = _state.history[_state.history.size() - 1]
		var path := PackedInt32Array(last.get("p", []))
		if not path.is_empty():
			piece = _state.squares[path[path.size() - 1]]
			notation = _notation[_notation.size() - 1]

	_top_last_move.piece = piece
	_top_last_move.notation = notation
	_bottom_last_move.piece = piece if _table_mode else 0
	_bottom_last_move.notation = notation if _table_mode else ""

	# Quem some é o Control que contém a linha, e não a linha: um filho invisível
	# de `VBoxContainer` deixa de contar altura, e é a altura que precisa sumir.
	%TopLastMoveSlot.visible = _top_last_move.has_move()
	%BottomLastMoveSlot.visible = _bottom_last_move.has_move()


## Onde existe um "eu" — rede ou bot — o cartão de baixo é o meu. No mesmo
## aparelho é sempre o das brancas, para "embaixo sou eu" não mudar de
## significado a cada lance quando os dois "eus" estão na mesma cadeira.
func _bottom_side() -> int:
	return Board.Side.WHITE if Game.mode == Game.Mode.HOTSEAT else Game.local_side


func _refresh_cards() -> void:
	var bottom_side := _bottom_side()
	var top_side := Board.opponent(bottom_side)
	var in_check := _check_square() != Board.NO_SQUARE
	var over := _outcome != Ruleset.Outcome.ONGOING or _flagged >= 0 or _abandoned

	var side_names := ["Brancas", "Pretas"]
	for card in [[%TopCard, top_side], [%BottomCard, bottom_side]]:
		var view: PlayerCard = card[0]
		var card_side: int = card[1]
		view.side = card_side
		view.active = not over and _state.side_to_move == card_side
		view.in_check = not over and in_check and _state.side_to_move == card_side
		view.clock_text = _clock_text(card_side)
		view.clock_urgent = view.active and float(_clock.get(card_side, 0.0)) < 20.0
		_refresh_captured(view, card_side)
		if Game.mode == Game.Mode.HOTSEAT:
			# Repetir "Brancas / Brancas" não informa nada; no mesmo aparelho a
			# cor já é o nome do jogador.
			view.title = side_names[card_side]
			view.subtitle = ""
		else:
			var them := "Bot (%s)" % Bot.level_label(Game.bot_level) \
				if Game.mode == Game.Mode.SOLO else _opponent_name()
			view.title = Prefs.player_name() if card_side == Game.local_side else them
			view.subtitle = side_names[card_side]


## Como o outro se chama, ou "Oponente" enquanto ele não se apresentou.
##
## O nome vem do aperto de mão e é do aparelho dele, então ele pode faltar — uma
## reconexão que caia antes do `resume`, ou uma versão antiga do outro lado. O
## rótulo genérico continua sendo a resposta certa nesse caso: ele diz "não sei
## quem é" sem inventar um nome.
func _opponent_name() -> String:
	var them := Net.name_of(_seat_of(Board.opponent(Game.local_side)))
	return them if not them.is_empty() else "Oponente"


## Cada cartão mostra o que **aquele** lado comeu, e o saldo aparece só do lado
## que está na frente: dois números obrigariam a comparar para descobrir quem
## está ganhando, que é a pergunta inteira.
func _refresh_captured(card: PlayerCard, side: int) -> void:
	var mine: Array = _captured[side]
	var theirs: Array = _captured[Board.opponent(side)]
	card.captured = mine
	card.advantage = PlayerCard.material(mine) - PlayerCard.material(theirs)


## O xeque é anunciado uma vez, quando começa. Um banner permanente cobriria a
## fileira de trás justamente quando ela mais importa; o estado contínuo fica no
## cartão, que já vira vermelho e escreve "Em xeque".
func _refresh_banner() -> void:
	if _outcome != Ruleset.Outcome.ONGOING or _check_square() == Board.NO_SQUARE:
		_announced_check = -1
		return
	if _announced_check == _state.side_to_move:
		return
	_announced_check = _state.side_to_move
	_banner.show_message(_check_message(), Banner.Kind.DANGER)


func _check_message() -> String:
	if Game.mode == Game.Mode.HOTSEAT:
		return "Xeque nas brancas!" if _state.side_to_move == Board.Side.WHITE else "Xeque nas pretas!"
	return "Você está em xeque!" if _is_local_turn() else "Xeque no oponente!"


## Shows the jump already committed in the current sequence: the piece drawn on
## the square it has reached so far, and a cross over each piece it has taken.
## Every candidate shares the selected prefix, so any of them describes it.
func _update_preview(candidates: Array[Move]) -> void:
	_board.preview_from = Board.NO_SQUARE
	_board.preview_to = Board.NO_SQUARE
	_board.doomed = PackedInt32Array()
	if _selection.size() < 2 or candidates.is_empty():
		return
	_board.preview_from = _selection[0]
	_board.preview_to = _selection[_selection.size() - 1]
	var steps_taken := _selection.size() - 1
	var reference := candidates[0]
	if reference.is_capture():
		_board.doomed = reference.captured.slice(0, mini(steps_taken, reference.captured.size()))


func _check_square() -> int:
	if _ruleset is not ChessRules:
		return Board.NO_SQUARE
	var chess := _ruleset as ChessRules
	if not chess.is_in_check(_state, _state.side_to_move):
		return Board.NO_SQUARE
	return _state.find_piece(_state.side_to_move, Board.Kind.KING)

## Sem chamador hoje: o `%StatusLabel` deixou de ser preenchido. Mantida porque
## o texto continua correto e é o que voltaria a ser usado se o indicador de
## transporte voltar para a tela.
func _connection_text() -> String:
	if Game.mode != Game.Mode.ONLINE:
		return ""
	if not Net.connected:
		return " • reconectando"
	if Net.transport == Net.Transport.RELAY:
		return " • pela internet"
	return " • pela rede local"
