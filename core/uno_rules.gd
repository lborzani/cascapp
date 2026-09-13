class_name UnoRules
extends Ruleset

## Uno de 2 a 6 jogadores: 108 cartas, mão oculta, e o acaso acontecendo o tempo
## todo em vez de uma vez por lance.
##
## **Nada disso cabe em `squares`.** Não há tabuleiro: o que existe é um monte de
## compra, um descarte, e uma mão por assento. Tudo mora em `meta`, e a divisão
## das chaves é ditada por uma restrição do `MatchState.clone()` — ele copia
## `meta` de forma rasa e só isola os `Packed*Array`, então `Array` de arrays está
## proibido. Uma mão por chave (`h0`..`h5`) resolve sem inventar um vetor plano
## com separadores dentro.
##
## ## De onde vem o acaso
##
## De uma semente, e não de `randi()`. Este é o segundo jogo do app com sorteio
## dentro do estado, e ele segue o Bomberman em vez do Ludo — pelos dois motivos:
##
## - o **embaralhamento inicial** precisa ser igual nos N aparelhos antes do
##   primeiro lance, e não há lance nenhum onde ele pudesse viajar;
## - a **compra** acontece várias vezes por turno, e mandar cada carta comprada
##   dentro do `Move` publicaria a mão de quem comprou a cada compra.
##
## Então o gerador é um xorshift de 32 bits guardado em `meta[RNG]`, semeado por
## `match_seed` — que em rede chega no `welcome` (`Net.option`). Duas partidas com
## a mesma semente são o mesmo baralho, e o histórico de lances reconstrói tudo:
## a reconexão continua sendo repetir a lista, como nos outros jogos.
##
## Isso vale para o **rembaralho** também, e ali é onde este arquivo erra mais
## caro: o monte que acaba no meio da partida é refeito a partir do descarte pelo
## mesmo `meta[RNG]`. Um `randi()` solto ali faria os N aparelhos divergirem em
## silêncio, no meio de uma partida longa, sem nada falhar.
##
## ## A mão não é segredo do modelo
##
## Todos os aparelhos derivam **todas** as mãos da semente. É o mesmo trato da
## batalha naval (ver `net_link.send_fleet`): é o desenho que esconde, não o
## modelo. Guardar o segredo de verdade obrigaria a confiar na resposta do outro
## lado ("comprei uma carta, confie em mim"), que é porta maior para trapaça que
## um cliente modificado que espia — e mataria o replay, que é o que segura a
## reconexão do app inteiro.
##
## Consequência direta: **não há modo mesa**. Quatro mãos ocultas num aparelho só
## exigiriam uma cortina de "passe o celular" a cada turno, que é o modo que a
## batalha naval também não oferece.
##
## ## A regra da casa do 0 e do 7
##
## Opcional, e escolhida por quem abre a sala. Com ela ligada, um 7 **troca a mão**
## com um jogador escolhido e um 0 **roda todas as mãos** no sentido do jogo.
##
## Ela mora no **estado** (`meta[SEVENS]`), e não só no objeto de regra. O replay
## reconstrói o estado chamando `initial_state()`, então tecnicamente o campo
## bastaria — mas `generate_moves` consulta a regra a cada lance, e um ruleset
## remontado sem ela geraria uma lista de lances legais diferente da que o
## histórico contém. No estado, o replay não tem como discordar.
##
## ## Quatro jogadores num app de dois
##
## Como no Ludo: `MatchState.side_to_move` é binário e não carrega seis assentos.
## Quem joga mora em `meta[TURN]`, e quem venceu é `winner()` — `outcome()`
## continua respondendo só se acabou.

# --- a carta ------------------------------------------------------------------

## Cor e valor empacotados num inteiro só: `cor * 16 + valor`.
##
## Dezesseis e não dez porque o valor vai até 14, e uma potência de dois deixa a
## decodificação em duas operações de bit. É o mesmo espírito do `Board.piece()`,
## com um nibble maior porque aqui há mais espécies que lá.
const COLOR_STEP := 16
const VALUE_MASK := 0xF

enum CardColor { RED = 0, YELLOW = 1, GREEN = 2, BLUE = 3, WILD = 4 }

## Os valores acima de 9 são as cartas de ação. O curinga guarda `CardColor.WILD` na
## metade da cor: a cor que ele **declara** não fica na carta, fica em
## `meta[COLOR]` — senão a mesma carta voltaria do descarte com a cor da última
## vez que alguém a jogou.
const SKIP := 10
const REVERSE := 11
const DRAW_TWO := 12
const WILD := 13
const WILD_FOUR := 14

## As duas cartas da regra da casa. Números comuns quando ela está desligada.
const ZERO := 0
const SEVEN := 7

const COLOR_COUNT := 4
const DECK_SIZE := 108
const HAND_SIZE := 7
const MIN_SEATS := 2
const MAX_SEATS := 6

## Quantas cartas o +2 e o +4 obrigam a comprar.
const DRAW_TWO_CARDS := 2
const WILD_FOUR_CARDS := 4

# --- espécies de lance --------------------------------------------------------

## `path = [kind, card, color, target]`, sempre com quatro casas.
##
## `card` é a **carta codificada**, e não o índice dela na mão. O índice é frágil
## frente à ordenação da tela e não é conferível; a carta é conferida contra a mão
## de quem joga, que é o que faz um lance de rede ser validável aqui.
##
## `color` só significa alguma coisa num curinga (a cor declarada); `target` só
## num 7 com a regra da casa ligada (com quem trocar). Os dois são -1 no resto,
## e é assim que um lance forjado com campo sobrando é recusado.
const PLAY := 0
const DRAW := 1
## Comprou uma carta que não quis jogar. Existe porque comprar **não** encerra a
## vez quando a carta comprada serve — ver [method _apply_draw].
const PASS := 2

const KIND_AT := 0
const CARD_AT := 1
const COLOR_AT := 2
const TARGET_AT := 3
const PATH_SIZE := 4

# --- chaves de `meta` ---------------------------------------------------------

## Nomes curtos porque `history` viaja pela rede a cada lance.
const SEATS := "st"
const TURN := "tn"
## Sentido do jogo: +1 ou -1.
const DIR := "dir"
## Cor ativa. Diferente da cor da carta do topo só depois de um curinga.
const COLOR := "cl"
const DECK := "dk"
## O descarte inteiro, e não só o topo: é dele que sai o monte quando ele acaba.
const PILE := "pl"
## Comprou nesta vez e a carta comprada serve. Restringe a lista de lances da vez
## seguinte a essa carta e a passar.
const DREW := "dw"
const RNG := "rng"
const SEVENS := "s7"

## Mão de um assento. A chave é formatada, e não uma lista de constantes: são seis
## e a diferença entre elas é um número.
const HAND := "h%d"


## Configuração da mesa, lida uma vez em `initial_state()`. Campos no objeto e
## não parâmetros porque quem constrói é `Game.make_ruleset()`, que não conhece o
## tamanho da sala nem a semente — é a cena da partida que preenche, como
## `MonopolyRules.seats` já faz.
var seats := 4
## A regra da casa do 0 e do 7.
var sevens := true
## Semente do baralho. Nunca zero: o xorshift tem o zero como ponto fixo e
## devolveria um baralho que nunca embaralha — 108 cartas na ordem em que foram
## fabricadas, sem nenhum erro à vista.
var match_seed := 1


func id() -> StringName:
	return &"uno"


func display_name() -> String:
	return "Uno"


func players() -> int:
	return clampi(seats, MIN_SEATS, MAX_SEATS)


# --- leitura da carta ---------------------------------------------------------


static func card(color: int, value: int) -> int:
	return color * COLOR_STEP + value


static func color_of_card(card_code: int) -> int:
	return card_code / COLOR_STEP


static func value_of_card(card_code: int) -> int:
	return card_code & VALUE_MASK


static func is_wild(card_code: int) -> bool:
	return color_of_card(card_code) == CardColor.WILD


## Carta de ação: muda a vez de alguém em vez de só ocupar o topo. O 0 e o 7 não
## entram, mesmo com a regra da casa ligada — eles trocam mãos, não a ordem.
static func is_action(card_code: int) -> bool:
	return value_of_card(card_code) >= SKIP


# --- leitura do estado --------------------------------------------------------


static func seats_of(state: MatchState) -> int:
	return int(state.meta.get(SEATS, MIN_SEATS))


static func turn_of(state: MatchState) -> int:
	return int(state.meta.get(TURN, 0))


static func direction_of(state: MatchState) -> int:
	return int(state.meta.get(DIR, 1))


static func active_color(state: MatchState) -> int:
	return int(state.meta.get(COLOR, CardColor.RED))


static func sevens_on(state: MatchState) -> bool:
	return int(state.meta.get(SEVENS, 0)) != 0


static func drew(state: MatchState) -> bool:
	return int(state.meta.get(DREW, 0)) != 0


static func hand_key(seat: int) -> String:
	return HAND % seat


static func hand_of(state: MatchState, seat: int) -> PackedInt32Array:
	return state.meta.get(hand_key(seat), PackedInt32Array())


static func hand_size(state: MatchState, seat: int) -> int:
	return hand_of(state, seat).size()


static func deck_of(state: MatchState) -> PackedInt32Array:
	return state.meta.get(DECK, PackedInt32Array())


static func pile_of(state: MatchState) -> PackedInt32Array:
	return state.meta.get(PILE, PackedInt32Array())


## A carta virada, ou -1 antes de haver uma.
static func top_card(state: MatchState) -> int:
	var pile := pile_of(state)
	return -1 if pile.is_empty() else pile[pile.size() - 1]


## Assento a `steps` posições daqui, no sentido do jogo.
static func seat_ahead(state: MatchState, steps := 1) -> int:
	var count := seats_of(state)
	return posmod(turn_of(state) + direction_of(state) * steps, count)


# --- sorteio ------------------------------------------------------------------


## Xorshift de 32 bits, com o estado dentro de `meta`.
##
## Escrito à mão pelo mesmo motivo do Bomberman: `RandomNumberGenerator` é um
## objeto com estado interno que não sobrevive ao `clone()`, e `randi()` é global.
## Os dois dariam baralhos diferentes em aparelhos diferentes, que é a única coisa
## que este jogo não pode permitir.
##
## A máscara de 32 bits é obrigatória — o inteiro do GDScript é de 64, e sem ela o
## deslocamento acumula bits que a referência do algoritmo não tem.
static func next_random(state: MatchState) -> int:
	var value := int(state.meta.get(RNG, 1)) & 0xFFFFFFFF
	value ^= (value << 13) & 0xFFFFFFFF
	value ^= value >> 17
	value ^= (value << 5) & 0xFFFFFFFF
	state.meta[RNG] = value
	return value


static func _random_below(state: MatchState, bound: int) -> int:
	return next_random(state) % maxi(1, bound)


## As 108 cartas na ordem de fábrica: por cor, um 0, dois de cada 1 a 9, dois de
## cada carta de ação, e os oito curingas no fim.
static func full_deck() -> PackedInt32Array:
	var cards := PackedInt32Array()
	for color in COLOR_COUNT:
		cards.append(card(color, 0))
		for value in range(1, 10):
			cards.append(card(color, value))
			cards.append(card(color, value))
		for value in [SKIP, REVERSE, DRAW_TWO]:
			cards.append(card(color, value))
			cards.append(card(color, value))
	for _copy in COLOR_COUNT:
		cards.append(card(CardColor.WILD, WILD))
		cards.append(card(CardColor.WILD, WILD_FOUR))
	return cards


## Fisher-Yates com o gerador do estado. Devolve o mesmo vetor, embaralhado.
static func _shuffle(state: MatchState, cards: PackedInt32Array) -> PackedInt32Array:
	for index in range(cards.size() - 1, 0, -1):
		var other := _random_below(state, index + 1)
		var held := cards[index]
		cards[index] = cards[other]
		cards[other] = held
	return cards


## A carta do topo do monte, ou -1 quando não há como comprar.
##
## O monte vazio é refeito a partir do descarte, **menos a carta virada** — e pelo
## mesmo gerador de sempre, que é o que mantém os N aparelhos com o mesmo monte
## depois do rembaralho.
##
## O -1 é o caso degenerado das duas pilhas esgotadas, que uma mesa de seis com
## muito +4 alcança. Quem chama trata; o que não pode acontecer é a vez ficar
## presa num jogador sem lance nenhum.
static func _draw_card(state: MatchState) -> int:
	var deck := deck_of(state)
	if deck.is_empty():
		if not _reshuffle(state):
			return -1
		deck = deck_of(state)
	var drawn := deck[deck.size() - 1]
	deck.resize(deck.size() - 1)
	state.meta[DECK] = deck
	return drawn


static func _reshuffle(state: MatchState) -> bool:
	var pile := pile_of(state)
	if pile.size() <= 1:
		return false
	var top := pile[pile.size() - 1]
	state.meta[DECK] = _shuffle(state, pile.slice(0, pile.size() - 1))
	state.meta[PILE] = PackedInt32Array([top])
	return true


## Compra `count` cartas para um assento. Para de comprar se o baralho acabar.
static func _give(state: MatchState, seat: int, count: int) -> void:
	var hand := hand_of(state, seat)
	for _each in count:
		var drawn := _draw_card(state)
		if drawn < 0:
			break
		hand.append(drawn)
	state.meta[hand_key(seat)] = hand


# --- posição inicial ----------------------------------------------------------


func initial_state() -> MatchState:
	var state := MatchState.new()
	var count := clampi(seats, MIN_SEATS, MAX_SEATS)
	state.meta[SEATS] = count
	state.meta[SEVENS] = 1 if sevens else 0
	state.meta[RNG] = match_seed if match_seed != 0 else 1
	state.meta[DECK] = _shuffle(state, full_deck())
	state.meta[PILE] = PackedInt32Array()
	for seat in count:
		state.meta[hand_key(seat)] = PackedInt32Array()

	# Carta a carta e dando a volta na mesa, como se distribui de verdade. Não faz
	# diferença para o jogo — faz para quem for conferir um baralho contra o outro.
	for _round in HAND_SIZE:
		for seat in count:
			_give(state, seat, 1)

	# A primeira virada nunca é curinga: ele vai para o **fundo** do monte e vira
	# outra. Um curinga aqui não teria quem declarasse a cor — o jogo ainda não
	# começou, e não há jogador anterior a quem perguntar.
	var top := _draw_card(state)
	while top >= 0 and is_wild(top):
		var deck := deck_of(state)
		deck.insert(0, top)
		state.meta[DECK] = deck
		top = _draw_card(state)

	state.meta[PILE] = PackedInt32Array([top])
	# A cor ativa sai da carta virada. O **efeito** dela não: um pular ou um +2 na
	# primeira virada valeria contra alguém que ainda não jogou nada, e a regra
	# oficial disso muda de caixa para caixa. Aqui a primeira carta só dá a cor.
	state.meta[COLOR] = color_of_card(top)
	state.meta[TURN] = 0
	state.meta[DIR] = 1
	state.meta[DREW] = 0
	state.side_to_move = Board.Side.WHITE
	return state


# --- lances -------------------------------------------------------------------


static func kind_of(move: Move) -> int:
	return move.path[KIND_AT]


static func card_of(move: Move) -> int:
	return move.path[CARD_AT]


static func declared_color(move: Move) -> int:
	return move.path[COLOR_AT]


static func target_of(move: Move) -> int:
	return move.path[TARGET_AT]


static func _move(kind: int, card_code: int, color: int, target: int) -> Move:
	var move := Move.new()
	move.path = PackedInt32Array([kind, card_code, color, target])
	return move


## A carta pode ser jogada sobre o topo. Curinga sempre pode; o resto casa por
## cor ativa ou por valor.
##
## A comparação de valor ignora um topo curinga: depois de um curinga o que vale é
## a cor declarada, e "o valor do curinga" não é nada que uma carta comum possa
## igualar.
static func is_playable(state: MatchState, card_code: int) -> bool:
	if is_wild(card_code):
		return true
	if color_of_card(card_code) == active_color(state):
		return true
	var top := top_card(state)
	return top >= 0 and not is_wild(top) and value_of_card(card_code) == value_of_card(top)


## Nunca devolve lista vazia enquanto houver partida: comprar é sempre possível,
## e sem isso a vez ficaria presa num jogador sem carta jogável — no replay isso
## não é uma tela travada, é o histórico deixando de ser reproduzível.
func generate_moves(state: MatchState) -> Array[Move]:
	var moves: Array[Move] = []
	if winner(state) >= 0:
		return moves

	var seat := turn_of(state)
	var hand := hand_of(state, seat)

	if drew(state):
		# Já comprou nesta vez. Só a carta comprada — a última da mão — pode ser
		# jogada, e passar é sempre possível. Deixar a mão inteira aberta aqui
		# daria uma segunda chance de jogar o que já se podia ter jogado antes de
		# comprar.
		if not hand.is_empty():
			var drawn := hand[hand.size() - 1]
			if is_playable(state, drawn):
				_append_plays(state, moves, drawn)
		moves.append(_move(PASS, -1, -1, -1))
		return moves

	# Cartas repetidas dão lances idênticos, e dois lances iguais na lista fazem a
	# tela oferecer a mesma escolha duas vezes.
	var seen := {}
	for card_code in hand:
		if seen.has(card_code) or not is_playable(state, card_code):
			continue
		seen[card_code] = true
		_append_plays(state, moves, card_code)
	moves.append(_move(DRAW, -1, -1, -1))
	return moves


## Os lances que esta carta produz. Uma carta comum dá um; as que pedem uma
## segunda decisão dão um por resposta possível.
##
## Curinga: quatro, um por cor. Sete com a regra da casa: um por adversário — e
## numa mesa de dois, **um só**, porque não há com quem escolher trocar.
func _append_plays(state: MatchState, moves: Array[Move], card_code: int) -> void:
	if is_wild(card_code):
		for color in COLOR_COUNT:
			moves.append(_move(PLAY, card_code, color, -1))
		return

	if sevens_on(state) and value_of_card(card_code) == SEVEN:
		var count := seats_of(state)
		var seat := turn_of(state)
		for other in count:
			if other != seat:
				moves.append(_move(PLAY, card_code, -1, other))
		return

	moves.append(_move(PLAY, card_code, -1, -1))


## O lance de rede, conferido contra a lista legal daqui antes de virar `Move`.
##
## Casa o **caminho inteiro** (`move.path == path`), e não só a carta: um curinga
## gera quatro lances — um por cor — e um 7 da regra da casa gera um por
## adversário, todos com a mesma carta. Conferir só a carta deixaria o remetente
## escolher a cor declarada ou o alvo da troca, que [method _apply_play] aplica
## sem reconferir (só confere que a carta está na mão). O caminho inteiro fecha
## isso, e é a mesma porta por onde passam os lances locais.
func validate(state: MatchState, path: PackedInt32Array) -> Move:
	if path.size() != PATH_SIZE:
		return null
	for move in generate_moves(state):
		if move.path == path:
			return move
	return null


func apply_move(state: MatchState, move: Move) -> void:
	var seat := turn_of(state)
	match kind_of(move):
		DRAW:
			_apply_draw(state, seat)
		PASS:
			state.meta[DREW] = 0
			_advance(state)
		_:
			_apply_play(state, seat, move)
	state.ply += 1
	state.history.append(move.to_dict())


## Comprar **não** encerra a vez quando a carta comprada serve.
##
## É a regra de caixa, e ela custa um campo no estado (`DREW`): sem ele a lista de
## lances da vez seguinte não teria como saber que só a carta recém-comprada pode
## ser jogada, e o jogador ganharia uma segunda chance de jogar o que já tinha.
##
## A alternativa — comprar e passar sempre — não custa campo nenhum e joga pior:
## quem compra exatamente a carta que precisava fica olhando ela ir para a mão e a
## vez passar.
func _apply_draw(state: MatchState, seat: int) -> void:
	var drawn := _draw_card(state)
	state.meta[DREW] = 0
	if drawn < 0:
		# Monte e descarte esgotados. Não há o que comprar, e a vez passa — senão
		# ela fica presa num jogador cujo único lance possível não faz nada.
		_advance(state)
		return

	var hand := hand_of(state, seat)
	hand.append(drawn)
	state.meta[hand_key(seat)] = hand

	if is_playable(state, drawn):
		state.meta[DREW] = 1
		return
	_advance(state)


func _apply_play(state: MatchState, seat: int, move: Move) -> void:
	var card_code := card_of(move)
	var hand := hand_of(state, seat)
	var at := hand.find(card_code)
	if at < 0:
		# Não deveria acontecer: só entram lances de `generate_moves`. Recusar em
		# silêncio é melhor que aplicar meio lance.
		return

	hand.remove_at(at)
	state.meta[hand_key(seat)] = hand

	var pile := pile_of(state)
	pile.append(card_code)
	state.meta[PILE] = pile
	# O curinga entra no descarte com a cor dele — `CardColor.WILD` —, e a cor
	# declarada fica só em `meta[COLOR]`. Guardá-la dentro da carta faria o
	# rembaralho devolver ao monte um curinga já pintado.
	state.meta[COLOR] = declared_color(move) if is_wild(card_code) else color_of_card(card_code)
	state.meta[DREW] = 0

	# **Vitória antes do efeito.** A última carta ganha a partida, e um 7 jogado
	# como última carta trocaria a mão vazia do vencedor por uma cheia — desfazendo
	# a vitória que acabou de acontecer. Um 0 faria o mesmo com a mesa inteira.
	if hand.is_empty():
		return

	_apply_effect(state, seat, card_code, target_of(move))


func _apply_effect(state: MatchState, seat: int, card_code: int, target: int) -> void:
	var value := value_of_card(card_code)

	if value == SKIP:
		_advance(state, 2)
		return

	if value == REVERSE:
		state.meta[DIR] = -direction_of(state)
		# Numa mesa de dois, inverter é pular: com o sentido trocado, andar duas
		# casas devolve a vez a quem acabou de jogar. Andar uma entregaria a vez ao
		# adversário, que é o oposto do que a carta faz numa mesa de dois.
		_advance(state, 2 if seats_of(state) == 2 else 1)
		return

	if value == DRAW_TWO:
		_punish(state, DRAW_TWO_CARDS)
		return

	if value == WILD_FOUR:
		_punish(state, WILD_FOUR_CARDS)
		return

	if sevens_on(state):
		if value == ZERO:
			_rotate_hands(state)
			_advance(state)
			return
		if value == SEVEN:
			_swap_hands(state, seat, target)
			_advance(state)
			return

	_advance(state)


## O próximo compra e perde a vez.
##
## Aplicado na hora em vez de acumulado num contador de pendências, porque o +2 e
## o +4 **não empilham** neste jogo: sem empilhamento, "acumular e obrigar o
## próximo a comprar" e "o próximo compra agora" são o mesmo resultado, e o
## primeiro custa um campo a mais no estado e uma fase a mais na lista de lances.
static func _punish(state: MatchState, count: int) -> void:
	_give(state, seat_ahead(state), count)
	_advance(state, 2)


static func _advance(state: MatchState, steps := 1) -> void:
	state.meta[TURN] = seat_ahead(state, steps)


## Troca as mãos de dois assentos — o efeito do 7.
##
## As duas cópias não são sobra. Mover um `PackedInt32Array` de uma chave de
## `meta` para outra deixa as duas chaves compartilhando o mesmo buffer, e o
## `clone()` do `MatchState` copia `meta` de forma rasa: a duplicação por chave
## que ele faz acontece **antes** da troca, não depois. Sem elas, uma variante que
## o bot explorasse podia vazar para a partida de verdade — silenciosamente, que é
## como este arquivo erra.
static func _swap_hands(state: MatchState, seat: int, other: int) -> void:
	if other < 0 or other >= seats_of(state) or other == seat:
		return
	var mine := hand_of(state, seat).duplicate()
	var theirs := hand_of(state, other).duplicate()
	state.meta[hand_key(seat)] = theirs
	state.meta[hand_key(other)] = mine


## Roda todas as mãos no sentido do jogo — o efeito do 0.
##
## Cada assento recebe a mão de quem joga **antes** dele, que é o mesmo sentido em
## que a vez anda. Com o sentido invertido, as mãos andam para o outro lado junto.
static func _rotate_hands(state: MatchState) -> void:
	var count := seats_of(state)
	var direction := direction_of(state)
	var moved: Array[PackedInt32Array] = []
	for seat in count:
		moved.append(hand_of(state, seat).duplicate())
	for seat in count:
		state.meta[hand_key(seat)] = moved[posmod(seat - direction, count)]


# --- fim de partida -----------------------------------------------------------


## Assento que ficou sem cartas, ou -1.
##
## Separado de `outcome()` pelo mesmo motivo do Ludo: o enum de `Ruleset` tem dois
## lados e o vencedor aqui pode ser qualquer um dos seis.
func winner(state: MatchState) -> int:
	for seat in seats_of(state):
		if hand_of(state, seat).is_empty():
			return seat
	return -1


func outcome(state: MatchState) -> Outcome:
	var champion := winner(state)
	if champion < 0:
		return Outcome.ONGOING
	return Outcome.WHITE_WINS if champion == 0 else Outcome.BLACK_WINS


# --- bot ----------------------------------------------------------------------


## Escolha heurística. O minimax do `Bot` não serve, e não é questão de ajuste:
## a mão dos outros é informação que o jogador não tem, e cada compra é um nó de
## chance. Uma busca honesta precisaria de esperança matemática sobre um baralho
## desconhecido — muito maquinário para um jogo em que meia dúzia de regras de
## bolso joga bem.
##
## O tamanho da mão dos outros **é** consultado, e isso não é trapaça: quantas
## cartas cada um tem é informação pública numa mesa de verdade.
func best_move(state: MatchState, moves: Array[Move]) -> Move:
	var best: Move = null
	var best_score := -1.0
	for move in moves:
		var score := _score_move(state, move)
		if score > best_score:
			best_score = score
			best = move
	return best


func _score_move(state: MatchState, move: Move) -> float:
	var kind := kind_of(move)
	if kind == DRAW:
		return 1.0
	if kind == PASS:
		return 0.0

	var seat := turn_of(state)
	var card_code := card_of(move)
	var value := value_of_card(card_code)
	var mine := hand_size(state, seat)
	var next_seat := seat_ahead(state)
	var next_size := hand_size(state, next_seat)
	# O vizinho perto de vencer é o que decide entre castigar e economizar carta.
	var threatened := next_size <= 2

	if value == WILD_FOUR:
		# A mais versátil da mão, e por isso a última a sair — a não ser que o
		# vizinho esteja fechando, que é quando quatro cartas valem mais que a
		# versatilidade guardada para depois.
		return 95.0 if threatened else 12.0
	if value == DRAW_TWO:
		return 90.0 if threatened else 60.0
	if value == SKIP or value == REVERSE:
		return 85.0 if threatened else 55.0

	if sevens_on(state):
		if value == SEVEN:
			var target := target_of(move)
			var theirs := hand_size(state, target)
			# Trocar só compensa recebendo menos do que se dá. O empate não conta:
			# trocar mão igual gasta uma carta e não muda nada.
			return 92.0 + float(mine - theirs) if theirs < mine else 20.0
		if value == ZERO:
			var incoming := hand_size(state, posmod(seat - direction_of(state), seats_of(state)))
			return 88.0 if incoming < mine else 25.0

	if is_wild(card_code):
		# A cor mais frequente na mão: o curinga vale pelo que ele destrava depois,
		# não pelo que ele tira agora.
		var color := declared_color(move)
		return 15.0 + float(_color_count(state, seat, color))

	# Números comuns: o maior primeiro. Não é pontuação — é que a carta alta é a
	# mais difícil de casar depois, e a que sobra na mão no fim da partida.
	return 30.0 + float(value)


static func _color_count(state: MatchState, seat: int, color: int) -> int:
	var total := 0
	for card_code in hand_of(state, seat):
		if color_of_card(card_code) == color:
			total += 1
	return total


# --- texto --------------------------------------------------------------------


const COLOR_NAMES := ["Vermelho", "Amarelo", "Verde", "Azul", "Curinga"]
const COLOR_SHORT := ["V", "A", "D", "Z", "C"]


static func color_name(color: int) -> String:
	return COLOR_NAMES[clampi(color, 0, COLOR_NAMES.size() - 1)]


static func color_short(color: int) -> String:
	return COLOR_SHORT[clampi(color, 0, COLOR_SHORT.size() - 1)]


## O rótulo de uma carta, para a tela e para o histórico.
static func card_label(card_code: int) -> String:
	var value := value_of_card(card_code)
	match value:
		SKIP:
			return "%s pula" % color_name(color_of_card(card_code))
		REVERSE:
			return "%s inverte" % color_name(color_of_card(card_code))
		DRAW_TWO:
			return "%s +2" % color_name(color_of_card(card_code))
		WILD:
			return "Curinga"
		WILD_FOUR:
			return "Curinga +4"
		_:
			return "%s %d" % [color_name(color_of_card(card_code)), value]


func notation(state: MatchState, move: Move) -> String:
	var seat := turn_of(state)
	match kind_of(move):
		DRAW:
			return "%d compra" % (seat + 1)
		PASS:
			return "%d passa" % (seat + 1)
	var card_code := card_of(move)
	var text := "%d %s%s" % [
		seat + 1,
		color_short(color_of_card(card_code)),
		str(value_of_card(card_code)),
	]
	if is_wild(card_code):
		return "%s→%s" % [text, color_short(declared_color(move))]
	if target_of(move) >= 0:
		return "%s↔%d" % [text, target_of(move) + 1]
	return text


func status_hint(state: MatchState) -> String:
	var champion := winner(state)
	if champion >= 0:
		return "Jogador %d venceu" % (champion + 1)
	if drew(state):
		return "Comprou — pode jogar a carta comprada ou passar."
	return ""
