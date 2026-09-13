class_name MonopolyRules
extends Ruleset

## Metrópole: 2 a 6 jogadores, 40 casas, hipoteca, construção e troca.
##
## O tabuleiro em si — nomes, preços, tabelas de aluguel, cartas — está em
## [monopoly_board.gd] e não muda nunca. Aqui mora só o que a partida faz com
## ele.
##
## ## Um turno é vários lances
##
## Esta é a decisão que faz o jogo caber no app, e ela merece o parágrafo.
##
## No xadrez, turno é lance: um `Move`, um `apply_move`, pronto. No Ludo já são
## duas coisas — rolar e escolher o peão — mas elas cabem juntas num `Move` só
## porque a segunda depende inteiramente da primeira. Aqui não cabe de jeito
## nenhum: rola, anda, cai, resolve o que a casa manda, constrói, hipoteca,
## talvez role de novo. São decisões independentes, tomadas com informação que só
## existe depois da anterior.
##
## Empacotar tudo isso num `Move` obrigaria o jogador a declarar o turno inteiro
## antes de rolar o dado, o que é absurdo. Então **o turno é uma sequência de
## lances pequenos**, e o estado guarda em que ponto da sequência está:
## `meta["ph"]`, a fase. `generate_moves` responde sempre a mesma pergunta —
## "o que é legal **agora**" — e a resposta depende da fase.
##
## O que isso preserva, e é o motivo de ter sido feito assim: **nada mais muda.**
## `history` continua sendo a lista de lances, replay continua reconstruindo a
## partida, a reconexão continua sendo repetir o histórico, o validador do outro
## aparelho continua conferindo contra a própria lista de legais. Um turno vira
## 3 a 8 linhas no histórico em vez de 1. É o único custo.
##
## ## Os dois acasos viajam dentro do lance
##
## O Ludo já guarda o dado dentro do `Move` ([ludo_rules.gd]). Aqui são dois
## acasos, não um: os dados **e a carta**. Os dois viajam do mesmo jeito —
## `[ROLL, d1, d2]` e `[DRAW, baralho, índice]`.
##
## A alternativa era embaralhar com semente combinada no handshake. Ela quebra na
## reconexão: o sync manda `history` e mais nada, então a semente teria de virar
## um segundo canal, e um segundo canal é uma segunda coisa que pode chegar
## errada. Com o índice dentro do lance, repetir a lista devolve exatamente a
## mesma partida — sem semente, sem baralho guardado, sem estado nenhum.
##
## Consequência assumida: **o baralho não tem memória.** Cada carta é sorteada do
## baralho inteiro, então a mesma pode sair duas vezes seguidas. Guardar a ordem
## do baralho custaria 32 inteiros em `meta` e uma pilha de descarte a sincronizar;
## o que se ganha é uma distribuição levemente mais justa numa partida de duas
## horas. Não vale.
##
## A única exceção é a carta de saída livre: enquanto ela está na mão de alguém
## não pode ser sorteada de novo, e `meta["jc"]` guarda isso em dois bits.
##
## ## A troca é o único lance que não se enumera
##
## Todo o resto do jogo cabe em `generate_moves`, e é assim que a tela sabe o que
## oferecer, o bot o que escolher e a rede o que aceitar de fora: pertencer à
## lista **é** ser legal.
##
## Uma proposta de troca não cabe. São até 2²⁰ subconjuntos de escrituras de cada
## lado, vezes todo valor em dinheiro possível — a lista não existe. Então ela é
## conferida por predicado, e `validate()` é a porta por onde tudo passa: lance
## comum, confere pertencendo à lista; proposta, confere pelo predicado. Quem
## aplica um `Move` sem passar por ali está pulando as regras.
##
## É também o único momento em que **quem joga não é o jogador da vez** — quem
## responde é o destinatário. `actor_of()` responde isso, e ela existe para a
## tela, o bot e a rede não terem cada um a sua ideia sobre de quem é a decisão.
##
## ## Tudo em `meta` é inteiro ou `PackedInt32Array`
##
## Obrigatório, não estilístico. `MatchState.clone()` copia `meta` de forma rasa
## ([match_state.gd:24]) — um `Array` de arrays ou um `Dictionary` aninhado seria
## **compartilhado** entre a posição e a cópia, e o bot corromperia a partida em
## silêncio ao explorar uma variante. `PackedInt32Array` é cópia-na-escrita e
## sobrevive; por isso são sete vetores planos e nenhuma estrutura.
##
## ## Quem venceu
##
## `Outcome` tem dois lados e aqui existem até seis. Mesmo caminho do Ludo:
## `winner()` devolve o índice do jogador, e `outcome()` só responde se acabou.

const MIN_SEATS := 2
const MAX_SEATS := 6

## Duplas seguidas antes de a cadeia cobrar a insistência.
const DOUBLES_LIMIT := 3
## Tentativas de tirar dupla na cadeia antes de a fiança virar obrigatória.
const JAIL_TRIES := 3

const NO_OWNER := -1
## Credor "banco". Falência para o banco devolve as escrituras ao mercado; para
## um jogador, transfere.
const BANK := -1
const FREE := -1

## Em que ponto do turno o jogo está. É o que `generate_moves` consulta, e a
## única coisa que distingue "pode rolar" de "tem de decidir se compra".
enum Phase {
	## Início do turno: rolar, ou mexer no patrimônio antes de rolar.
	ROLL,
	## Preso. Rolar tentando dupla, pagar fiança, ou usar a carta.
	JAILED,
	## Parou numa casa sem dono e tem como pagar.
	BUY,
	## Parou em Sorte ou Cofre e a carta ainda não saiu.
	DRAW,
	## Casa resolvida. Construir, hipotecar, trocar, ou encerrar.
	MANAGE,
	## Deve mais do que tem no bolso. Só levanta dinheiro ou quebra.
	RAISE,
	## Uma proposta de troca está na mesa. **Quem decide não é o jogador da vez**
	## — é o destinatário, e é o único momento do jogo assim. Ver `actor_of`.
	TRADE,
}

## O que um lance é. `Move.path[0]` sempre carrega isto.
enum Act {
	## `[ROLL, d1, d2]`. Os dois dados separados porque dupla é regra e a soma
	## esconderia qual 8 foi 4+4.
	ROLL,
	BUY,
	DECLINE,
	## `[DRAW, baralho, índice]`.
	DRAW,
	## `[BUILD, casa]` e companhia — a casa do tabuleiro, não a construção.
	BUILD,
	SELL,
	MORTGAGE,
	UNMORTGAGE,
	END,
	BAIL,
	USE_CARD,
	BANKRUPT,
	## `[OFFER, para, dinheiro, quantas_saem, casas_que_saem…, casas_que_entram…]`,
	## do ponto de vista de quem propõe. `dinheiro` é com sinal: positivo é ele
	## pagando, negativo é ele cobrando.
	##
	## É o único lance de tamanho variável do jogo, e o único que
	## `generate_moves` **não** enumera — ver `validate`.
	OFFER,
	ACCEPT,
	REJECT,
}

# Chaves de `meta`. Curtas porque são muitas e são lidas o tempo todo.
const POS := "pos"
const CASH := "cash"
## -1 solto; 0..2 tentativas já gastas na cadeia.
const JAIL := "jail"
const CARDS := "cards"
const OUT := "out"
const OWNER := "own"
## 0..4 casas, 5 é hotel. Um número só para os dois porque hotel é o sexto
## degrau da mesma escada.
const HOUSES := "hs"
const MORT := "mg"
const TURN := "turn"
const PHASE := "ph"
const DOUBLES := "db"
const DEBT := "debt"
const CREDITOR := "cr"
## Soma da última rolagem. Existe por causa do aluguel de companhia, que é o
## único do jogo que depende do dado.
const ROLL_SUM := "roll"
const ROUND := "rd"
const SEATS := "seats"
## Rodadas até o fim, ou 0 para jogar até sobrar um.
const LIMIT := "limit"
## Bits das cartas de saída livre que estão em mãos, uma por baralho.
const JAIL_OUT := "jc"
## A proposta de troca na mesa, quando há uma. Quatro chaves porque tudo em `meta`
## é inteiro ou vetor empacotado, e um dicionário aninhado seria compartilhado
## entre a posição e a cópia do bot.
const OFFER_TO := "oto"
## Com sinal: positivo é quem propõe pagando, negativo é cobrando.
const OFFER_CASH := "ocash"
const OFFER_GIVE := "ogive"
const OFFER_GET := "oget"
## Fase para onde voltar quando a proposta for respondida. Propor não gasta o
## turno: recusada, o jogo volta exatamente para onde estava.
const OFFER_BACK := "oback"

## Onde a lista de casas começa em `[OFFER, para, dinheiro, quantas_saem, …]`.
const OFFER_HEAD := 4

## Configuração da mesa, lida uma vez em `initial_state()`. Fica no objeto e não
## em parâmetro porque `Ruleset` é construído por `Game.make_ruleset()`, que não
## conhece nem o tamanho da sala nem o formato escolhido.
var seats := 4
## 0 joga até a falência; N encerra depois de N rodadas e vence o patrimônio.
var round_limit := 0


func id() -> StringName:
	return &"monopoly"


func players() -> int:
	return clampi(seats, MIN_SEATS, MAX_SEATS)


## O único jogo do app que já contava rodadas antes de alguém querer mostrá-las:
## é por elas que a partida pode acabar, e o contador vive em `meta[ROUND]`.
##
## A conta padrão não serviria: uma dupla nos dados devolve a vez ao mesmo
## jogador, então lances por cadeira não são voltas na mesa.
func rounds_played(state: MatchState) -> int:
	return round_of(state)


func display_name() -> String:
	return "Metrópole"


func initial_state() -> MatchState:
	var state := MatchState.new()
	var count := clampi(seats, MIN_SEATS, MAX_SEATS)
	state.meta[SEATS] = count
	state.meta[LIMIT] = maxi(0, round_limit)
	state.meta[POS] = _filled(count, MonopolyBoard.GO_TILE)
	state.meta[CASH] = _filled(count, MonopolyBoard.START_CASH)
	state.meta[JAIL] = _filled(count, FREE)
	state.meta[CARDS] = _filled(count, 0)
	state.meta[OUT] = _filled(count, 0)
	state.meta[OWNER] = _filled(MonopolyBoard.SIZE, NO_OWNER)
	state.meta[HOUSES] = _filled(MonopolyBoard.SIZE, 0)
	state.meta[MORT] = _filled(MonopolyBoard.SIZE, 0)
	state.meta[TURN] = 0
	state.meta[PHASE] = Phase.ROLL
	state.meta[DOUBLES] = 0
	state.meta[DEBT] = 0
	state.meta[CREDITOR] = BANK
	state.meta[ROLL_SUM] = 0
	state.meta[ROUND] = 0
	state.meta[JAIL_OUT] = 0
	state.meta[OFFER_TO] = FREE
	state.meta[OFFER_CASH] = 0
	state.meta[OFFER_GIVE] = PackedInt32Array()
	state.meta[OFFER_GET] = PackedInt32Array()
	state.meta[OFFER_BACK] = Phase.MANAGE
	state.side_to_move = Board.Side.WHITE
	return state


static func _filled(size: int, value: int) -> PackedInt32Array:
	var array := PackedInt32Array()
	array.resize(size)
	array.fill(value)
	return array


# --- leitura do estado --------------------------------------------------------


static func seats_of(state: MatchState) -> int:
	return int(state.meta.get(SEATS, 4))


static func turn_of(state: MatchState) -> int:
	return int(state.meta.get(TURN, 0))


static func phase_of(state: MatchState) -> int:
	return int(state.meta.get(PHASE, Phase.ROLL))


## Quem decide o lance seguinte.
##
## É o jogador da vez em tudo, **menos** com uma proposta de troca na mesa: lá
## quem responde é o destinatário. Existe para a tela, o bot e a rede fazerem
## uma pergunta só — quem tentasse `turn_of` durante uma proposta ofereceria os
## botões ao jogador errado, e em rede o aparelho errado mandaria o lance.
static func actor_of(state: MatchState) -> int:
	if phase_of(state) == Phase.TRADE:
		return offer_to(state)
	return turn_of(state)


## Para quem a proposta na mesa foi feita, ou -1 sem proposta.
static func offer_to(state: MatchState) -> int:
	return int(state.meta.get(OFFER_TO, FREE))


static func offer_cash(state: MatchState) -> int:
	return int(state.meta.get(OFFER_CASH, 0))


## Escrituras que saem de quem propôs.
static func offer_give(state: MatchState) -> PackedInt32Array:
	return state.meta.get(OFFER_GIVE, PackedInt32Array())


## Escrituras que entram para quem propôs.
static func offer_get(state: MatchState) -> PackedInt32Array:
	return state.meta.get(OFFER_GET, PackedInt32Array())


static func round_of(state: MatchState) -> int:
	return int(state.meta.get(ROUND, 0))


static func limit_of(state: MatchState) -> int:
	return int(state.meta.get(LIMIT, 0))


static func cash_of(state: MatchState, player: int) -> int:
	return state.meta[CASH][player]


static func position_of(state: MatchState, player: int) -> int:
	return state.meta[POS][player]


## -1 solto, senão quantas tentativas de dupla já foram gastas.
static func jail_of(state: MatchState, player: int) -> int:
	return state.meta[JAIL][player]


static func in_jail(state: MatchState, player: int) -> bool:
	return jail_of(state, player) >= 0


static func jail_cards_of(state: MatchState, player: int) -> int:
	return state.meta[CARDS][player]


static func is_out(state: MatchState, player: int) -> bool:
	return state.meta[OUT][player] != 0


static func owner_of(state: MatchState, tile: int) -> int:
	return state.meta[OWNER][tile]


static func houses_on(state: MatchState, tile: int) -> int:
	return state.meta[HOUSES][tile]


static func is_mortgaged(state: MatchState, tile: int) -> bool:
	return state.meta[MORT][tile] != 0


static func debt_of(state: MatchState) -> int:
	return int(state.meta.get(DEBT, 0))


static func creditor_of(state: MatchState) -> int:
	return int(state.meta.get(CREDITOR, BANK))


static func last_roll(state: MatchState) -> int:
	return int(state.meta.get(ROLL_SUM, 0))


## Casas do jogador, na ordem do tabuleiro. A tela lista, o bot conta, a troca
## oferece — três lugares perguntando a mesma coisa.
static func deeds_of(state: MatchState, player: int) -> PackedInt32Array:
	var owned := PackedInt32Array()
	for tile in MonopolyBoard.SIZE:
		if owner_of(state, tile) == player:
			owned.append(tile)
	return owned


## Escrituras que podem entrar numa troca agora: as do jogador cujo grupo está
## sem obra.
##
## A tela monta a proposta a partir desta lista em vez de refazer a regra. Uma
## segunda cópia dela é a que um dia discorda de `validate` e oferece ao jogador
## uma casa que as regras vão recusar depois de ele ter montado a proposta
## inteira.
static func tradable_deeds(state: MatchState, player: int) -> PackedInt32Array:
	var free_deeds := PackedInt32Array()
	for tile in deeds_of(state, player):
		if group_is_clear(state, tile):
			free_deeds.append(tile)
	return free_deeds


## Nenhuma casa do grupo desta tem construção.
static func group_is_clear(state: MatchState, tile: int) -> bool:
	for other in MonopolyBoard.group_tiles(MonopolyBoard.group_of(tile)):
		if houses_on(state, other) > 0:
			return false
	return true


## Quantas casas de um grupo o jogador tem. Aeroporto e companhia cobram por
## isto; propriedade de cor dobra o aluguel quando é o grupo inteiro.
static func owned_in_group(state: MatchState, player: int, group: int) -> int:
	var total := 0
	for tile in MonopolyBoard.group_tiles(group):
		if owner_of(state, tile) == player:
			total += 1
	return total


## O jogador fechou a cor. Hipoteca não desfaz: quem hipotecou continua dono, e
## o que ele perde é o aluguel daquela casa, não o grupo.
static func owns_group(state: MatchState, player: int, group: int) -> bool:
	var tiles := MonopolyBoard.group_tiles(group)
	if tiles.is_empty():
		return false
	return owned_in_group(state, player, group) == tiles.size()


static func alive_players(state: MatchState) -> PackedInt32Array:
	var alive := PackedInt32Array()
	for player in seats_of(state):
		if not is_out(state, player):
			alive.append(player)
	return alive


## Quanto o jogador vale se liquidar tudo agora: dinheiro, escrituras e metade do
## que gastou construindo. É o critério do modo curto e a bússola do bot.
static func net_worth(state: MatchState, player: int) -> int:
	var total := cash_of(state, player)
	for tile in deeds_of(state, player):
		total += (
			MonopolyBoard.mortgage_value(tile)
			if is_mortgaged(state, tile)
			else MonopolyBoard.price_of(tile)
		)
		total += houses_on(state, tile) * MonopolyBoard.house_cost(tile) / 2
	return total


# --- aluguel ------------------------------------------------------------------


## O que se paga por parar aqui. Zero quando não tem dono, está hipotecada, ou é
## do próprio.
##
## `roll` entra porque companhia cobra a rolagem vezes 4 ou 10 — passar o valor
## em vez de ler `meta` deixa a função utilizável para simular ("quanto eu
## cobraria se ele tirasse 7?"), que é o que o bot faz.
static func rent_for(state: MatchState, tile: int, roll: int) -> int:
	var landlord := owner_of(state, tile)
	if landlord == NO_OWNER or is_mortgaged(state, tile):
		return 0
	var group := MonopolyBoard.group_of(tile)
	match MonopolyBoard.kind_of(tile):
		MonopolyBoard.Tile.PROPERTY:
			var built := houses_on(state, tile)
			var table: Array = MonopolyBoard.tile(tile)["rent"]
			if built > 0:
				return int(table[built])
			# Terreno vazio de cor fechada cobra o dobro. É a regra que torna
			# fechar um grupo valioso antes de haver dinheiro para construir.
			var base := int(table[0])
			return base * 2 if owns_group(state, landlord, group) else base
		MonopolyBoard.Tile.AIRPORT:
			var count := owned_in_group(state, landlord, group)
			return int(MonopolyBoard.AIRPORT_RENT[clampi(count - 1, 0, 3)])
		MonopolyBoard.Tile.UTILITY:
			var count := owned_in_group(state, landlord, group)
			return roll * int(MonopolyBoard.UTILITY_MULTIPLIER[clampi(count - 1, 0, 1)])
	return 0


# --- geração de lances --------------------------------------------------------


func generate_moves(state: MatchState) -> Array[Move]:
	var moves: Array[Move] = []
	if winner(state) >= 0:
		return moves
	var player := turn_of(state)
	if is_out(state, player):
		return moves

	match phase_of(state):
		Phase.ROLL:
			_append_dice(moves)
			_append_management(state, player, moves)
		Phase.JAILED:
			_append_dice(moves)
			if jail_cards_of(state, player) > 0:
				moves.append(_act([Act.USE_CARD]))
			if cash_of(state, player) >= MonopolyBoard.BAIL:
				moves.append(_act([Act.BAIL]))
			_append_management(state, player, moves)
		Phase.BUY:
			var tile := position_of(state, player)
			if cash_of(state, player) >= MonopolyBoard.price_of(tile):
				moves.append(_act([Act.BUY]))
			moves.append(_act([Act.DECLINE]))
			_append_management(state, player, moves)
		Phase.DRAW:
			_append_cards(state, moves)
		Phase.MANAGE:
			_append_management(state, player, moves)
			moves.append(_act([Act.END]))
		Phase.RAISE:
			# Só o que **gera** dinheiro. Construir e desipotecar gastam, e
			# oferecê-los a quem está devendo é oferecer o caminho para afundar.
			_append_selling(state, player, moves)
			moves.append(_act([Act.BANKRUPT]))
		Phase.TRADE:
			# Os dois únicos lances de toda a partida que não são de quem está
			# jogando. Enquanto a proposta está na mesa, quem propôs não faz mais
			# nada — uma pergunta modal, e é o que impede o patrimônio de mudar
			# entre a oferta e a resposta.
			moves.append(_act([Act.ACCEPT]))
			moves.append(_act([Act.REJECT]))
	return moves


## O lance que quem chamou montou, conferido contra as regras — ou `null`.
##
## Porta única: a tela, o bot e a rede passam por aqui, e nenhum deles aplica um
## `Move` que não tenha saído daqui. Sem isso, um `Move` montado à mão atravessa
## `apply_move` sem passar por regra nenhuma.
##
## Quase tudo é conferido por pertencer a `generate_moves`, que é o mais honesto
## possível — a lista de legais é a mesma que a tela desenha. A **proposta de
## troca** não cabe nesse molde: são até 2²⁰ combinações de escrituras de cada
## lado vezes todo valor em dinheiro, e enumerar isso para conferir uma é absurdo.
## Ela é conferida por predicado, e é o único lance assim.
func validate(state: MatchState, path: PackedInt32Array) -> Move:
	if path.is_empty():
		return null
	if path[0] == Act.OFFER:
		return _act(Array(path)) if _offer_is_legal(state, path) else null
	for move in generate_moves(state):
		if move.path == path:
			return move
	return null


## Monta o caminho de uma proposta. Existe para a codificação de `Act.OFFER`
## morar num lugar só: quem escreve é esta função, quem lê são as duas abaixo.
static func offer_path(
	partner: int, cash: int, give: PackedInt32Array, receive: PackedInt32Array
) -> PackedInt32Array:
	var path := PackedInt32Array([Act.OFFER, partner, cash, give.size()])
	path.append_array(give)
	path.append_array(receive)
	return path


static func offered_give(path: PackedInt32Array) -> PackedInt32Array:
	return path.slice(OFFER_HEAD, OFFER_HEAD + _offered_count(path))


static func offered_get(path: PackedInt32Array) -> PackedInt32Array:
	return path.slice(OFFER_HEAD + _offered_count(path))


static func _offered_count(path: PackedInt32Array) -> int:
	return clampi(path[3], 0, path.size() - OFFER_HEAD)


## Este jogador pode abrir uma proposta agora.
##
## Mora aqui e não na tela para o botão de trocar e o `validate` concordarem sobre
## quando a troca existe. Duas listas de fases seria uma tela que oferece o botão
## num momento em que as regras recusam a proposta depois de ela ter sido montada
## inteira.
##
## Fora da lista ficam DRAW e TRADE, e pelo mesmo motivo: nos dois a partida já
## está esperando uma resposta, e uma segunda pergunta por cima da primeira é uma
## fila que ninguém pediu.
static func can_offer(state: MatchState, player: int) -> bool:
	if player != turn_of(state) or is_out(state, player):
		return false
	match phase_of(state):
		Phase.ROLL, Phase.JAILED, Phase.MANAGE, Phase.RAISE:
			pass
		_:
			return false
	return alive_players(state).size() > 1


## A proposta é apresentável.
##
## O que ela **não** confere é se é um bom negócio: dar três ruas por nada é
## legal, e é assim no jogo de mesa. Quem julga é quem responde.
func _offer_is_legal(state: MatchState, path: PackedInt32Array) -> bool:
	if path.size() < OFFER_HEAD or path[3] < 0 or path[3] > path.size() - OFFER_HEAD:
		return false
	var proposer := turn_of(state)
	if not can_offer(state, proposer):
		return false
	var partner := path[1]
	if partner < 0 or partner >= seats_of(state) or partner == proposer:
		return false
	if is_out(state, partner):
		return false

	var give := offered_give(path)
	var receive := offered_get(path)
	var cash := path[2]
	# Proposta vazia não é proposta. Ela viraria uma pergunta cuja resposta não
	# muda nada, e em rede um jeito de travar a vez do outro.
	if give.is_empty() and receive.is_empty() and cash == 0:
		return false

	var seen := {}
	for tile in give:
		if not _tradable(state, proposer, tile, seen):
			return false
	for tile in receive:
		if not _tradable(state, partner, tile, seen):
			return false

	if cash > 0 and cash_of(state, proposer) < cash:
		return false
	if cash < 0 and cash_of(state, partner) < -cash:
		return false
	return true


## A escritura pode entrar numa troca: é de quem a oferece, ainda não apareceu
## nesta proposta, e o grupo dela está sem obra.
##
## O **grupo** inteiro, e não só a casa. Passar adiante a rua vazia de um grupo
## que tem hotel na vizinha deixaria construção de pé num grupo de dois donos —
## uma posição que a regra de uniformidade não sabe desfazer, porque ela pergunta
## "a irmã tem menos casas que esta?" sem nunca perguntar de quem é a irmã.
func _tradable(state: MatchState, owner: int, tile: int, seen: Dictionary) -> bool:
	if tile < 0 or tile >= MonopolyBoard.SIZE or seen.has(tile):
		return false
	seen[tile] = true
	return owner_of(state, tile) == owner and group_is_clear(state, tile)


## As 36 combinações, e não as 21 distintas: dupla é regra, e `3+5` precisa ser
## um lance diferente de `4+4` mesmo somando o mesmo. Quem rola escolhe uma; o
## outro aparelho confere que a escolhida está nesta lista, como em todos os
## outros jogos — o que ele não confere é **qual**, porque isso é o acaso.
func _append_dice(moves: Array[Move]) -> void:
	for first in range(1, 7):
		for second in range(1, 7):
			moves.append(_act([Act.ROLL, first, second]))


## Toda carta que pode sair agora. A de saída livre some da lista enquanto está
## na mão de alguém — é a única com memória, e são dois bits.
func _append_cards(state: MatchState, moves: Array[Move]) -> void:
	var which := _deck_at(position_of(state, turn_of(state)))
	var cards := MonopolyBoard.deck(which)
	var held := int(state.meta.get(JAIL_OUT, 0))
	for index in cards.size():
		var effect := int(cards[index]["effect"])
		if effect == MonopolyBoard.Effect.JAIL_CARD and (held & (1 << which)) != 0:
			continue
		moves.append(_act([Act.DRAW, which, index]))


## Construir, vender, hipotecar, desipotecar. Disponíveis em qualquer fase em que
## o jogador da vez decide algo — mexer no patrimônio nunca depende de onde o
## peão está, e travar isso só na fase MANAGE obrigaria a rolar antes de poder
## pagar uma dívida que já se sabe que vem.
func _append_management(state: MatchState, player: int, moves: Array[Move]) -> void:
	_append_selling(state, player, moves)
	var cash := cash_of(state, player)
	for tile in deeds_of(state, player):
		if is_mortgaged(state, tile):
			if cash >= MonopolyBoard.unmortgage_cost(tile):
				moves.append(_act([Act.UNMORTGAGE, tile]))
			continue
		if _can_build(state, player, tile) and cash >= MonopolyBoard.house_cost(tile):
			moves.append(_act([Act.BUILD, tile]))


func _append_selling(state: MatchState, player: int, moves: Array[Move]) -> void:
	for tile in deeds_of(state, player):
		if _can_sell(state, tile):
			moves.append(_act([Act.SELL, tile]))
		if _can_mortgage(state, player, tile):
			moves.append(_act([Act.MORTGAGE, tile]))


## Construção é uniforme: não dá para pôr a segunda casa numa rua antes de a
## irmã ter a primeira. Sem isso, hotelar a casa mais cara do grupo e deixar as
## outras vazias seria a jogada ótima sempre, e o grupo deixaria de ser um grupo.
func _can_build(state: MatchState, player: int, tile: int) -> bool:
	if not MonopolyBoard.can_build_on(tile):
		return false
	var group := MonopolyBoard.group_of(tile)
	if not owns_group(state, player, group):
		return false
	if houses_on(state, tile) >= MonopolyBoard.HOTEL:
		return false
	var lowest := MonopolyBoard.HOTEL
	for other in MonopolyBoard.group_tiles(group):
		# Grupo com qualquer casa hipotecada não constrói: o banco já é dono de
		# metade dele.
		if is_mortgaged(state, other):
			return false
		lowest = mini(lowest, houses_on(state, other))
	return houses_on(state, tile) == lowest


## Vender é o espelho: sai a construção mais alta do grupo primeiro, senão a
## uniformidade poderia ser desfeita pela porta dos fundos.
func _can_sell(state: MatchState, tile: int) -> bool:
	if houses_on(state, tile) <= 0:
		return false
	var highest := 0
	for other in MonopolyBoard.group_tiles(MonopolyBoard.group_of(tile)):
		highest = maxi(highest, houses_on(state, other))
	return houses_on(state, tile) == highest


## Hipoteca exige o grupo inteiro sem construção. O banco não empresta sobre um
## terreno cujas casas ainda estão de pé, e nem sobre um grupo em que só a
## vizinha construiu.
func _can_mortgage(state: MatchState, player: int, tile: int) -> bool:
	if is_mortgaged(state, tile):
		return false
	if owner_of(state, tile) != player:
		return false
	for other in MonopolyBoard.group_tiles(MonopolyBoard.group_of(tile)):
		if houses_on(state, other) > 0:
			return false
	return true


static func _act(path: Array) -> Move:
	var move := Move.new()
	move.path = PackedInt32Array(path)
	return move


static func act_of(move: Move) -> int:
	return move.path[0]


static func _deck_at(tile: int) -> int:
	return (
		MonopolyBoard.CHEST
		if MonopolyBoard.kind_of(tile) == MonopolyBoard.Tile.CHEST
		else MonopolyBoard.CHANCE
	)


# --- aplicação ----------------------------------------------------------------


func apply_move(state: MatchState, move: Move) -> void:
	var player := turn_of(state)
	match act_of(move):
		Act.ROLL:
			_do_roll(state, player, move.path[1], move.path[2])
		Act.BUY:
			_do_buy(state, player)
		Act.DECLINE:
			# Sem leilão: a casa recusada simplesmente continua do banco. O leilão
			# é a regra mais esquecida do jogo de mesa e a que mais trava uma
			# partida on-line, porque para o turno de todo mundo.
			_set_phase(state, Phase.MANAGE)
		Act.DRAW:
			_do_card(state, player, move.path[1], move.path[2])
		Act.BUILD:
			_do_build(state, player, move.path[1])
		Act.SELL:
			_do_sell(state, player, move.path[1])
		Act.MORTGAGE:
			_do_mortgage(state, player, move.path[1])
		Act.UNMORTGAGE:
			_do_unmortgage(state, player, move.path[1])
		Act.BAIL:
			_pay(state, player, MonopolyBoard.BAIL)
			_leave_jail(state, player)
			_set_phase(state, Phase.MANAGE)
		Act.USE_CARD:
			_spend_jail_card(state, player)
			_leave_jail(state, player)
			_set_phase(state, Phase.MANAGE)
		Act.BANKRUPT:
			_do_bankrupt(state, player)
		Act.OFFER:
			_do_offer(state, move.path)
		Act.ACCEPT:
			_do_accept(state)
		Act.REJECT:
			_close_offer(state)
		Act.END:
			_end_turn(state)
	state.ply += 1
	state.history.append(move.to_dict())


func _do_roll(state: MatchState, player: int, first: int, second: int) -> void:
	var total := first + second
	var doubled := first == second
	state.meta[ROLL_SUM] = total

	if phase_of(state) == Phase.JAILED:
		_roll_in_jail(state, player, total, doubled)
		return

	if doubled:
		var streak := int(state.meta[DOUBLES]) + 1
		state.meta[DOUBLES] = streak
		# Três duplas seguidas é a regra que impede o turno infinito. O peão vai
		# para a cadeia sem andar e sem passar pela Partida.
		if streak >= DOUBLES_LIMIT:
			_send_to_jail(state, player)
			return
	else:
		state.meta[DOUBLES] = 0
	_advance(state, player, total)


## Rolar preso não anda o peão a menos que dê dupla. A terceira tentativa
## fracassada cobra a fiança e solta — a cadeia é cara, nunca é permanente.
##
## Sair com dupla **não** dá turno extra: `DOUBLES` fica em zero. Quem sai da
## cadeia já ganhou o suficiente com aquela dupla.
func _roll_in_jail(state: MatchState, player: int, total: int, doubled: bool) -> void:
	state.meta[DOUBLES] = 0
	if doubled:
		_leave_jail(state, player)
		_advance(state, player, total)
		return

	var tries := jail_of(state, player) + 1
	if tries < JAIL_TRIES:
		var jail := PackedInt32Array(state.meta[JAIL])
		jail[player] = tries
		state.meta[JAIL] = jail
		_set_phase(state, Phase.MANAGE)
		return

	_leave_jail(state, player)
	_charge(state, player, MonopolyBoard.BAIL, BANK)
	# Só anda se a fiança coube no bolso. Quem saiu devendo resolve a dívida
	# primeiro e perde a movimentação desta vez — a alternativa seria andar
	# devendo e acumular uma segunda dívida sobre a primeira, que é como um
	# turno vira uma cascata que ninguém acompanha.
	if phase_of(state) != Phase.RAISE:
		_advance(state, player, total)


## Anda N casas pela frente, pagando o salário se cruzar a Partida.
func _advance(state: MatchState, player: int, steps: int) -> void:
	var position := PackedInt32Array(state.meta[POS])
	var target := position[player] + steps
	if target >= MonopolyBoard.SIZE:
		target -= MonopolyBoard.SIZE
		_earn(state, player, MonopolyBoard.GO_SALARY)
	position[player] = target
	state.meta[POS] = position
	_land(state, player)


## Vai direto para uma casa. Cruzar a Partida no caminho paga; recuar não.
func _jump_to(state: MatchState, player: int, tile: int) -> void:
	var position := PackedInt32Array(state.meta[POS])
	if tile < position[player]:
		_earn(state, player, MonopolyBoard.GO_SALARY)
	position[player] = tile
	state.meta[POS] = position
	_land(state, player)


## Anda para trás, sem salário. Só cartas fazem isso, e nunca o bastante para
## dar a volta.
func _step_back(state: MatchState, player: int, steps: int) -> void:
	var position := PackedInt32Array(state.meta[POS])
	position[player] = posmod(position[player] + steps, MonopolyBoard.SIZE)
	state.meta[POS] = position
	_land(state, player)


## O que a casa faz com quem parou nela. É aqui que a fase seguinte é decidida, e
## é a única função que decide isso — cada casa responde uma vez.
func _land(state: MatchState, player: int) -> void:
	var tile := position_of(state, player)
	match MonopolyBoard.kind_of(tile):
		MonopolyBoard.Tile.GOTO_JAIL:
			_send_to_jail(state, player)
		MonopolyBoard.Tile.TAX:
			_charge(state, player, int(MonopolyBoard.tile(tile)["amount"]), BANK)
		MonopolyBoard.Tile.CHANCE, MonopolyBoard.Tile.CHEST:
			_set_phase(state, Phase.DRAW)
		MonopolyBoard.Tile.PROPERTY, MonopolyBoard.Tile.AIRPORT, MonopolyBoard.Tile.UTILITY:
			_land_on_deed(state, player, tile)
		_:
			# Partida, Descanso e a visita à cadeia não fazem nada. O "prêmio do
			# Descanso" é regra caseira: ele injeta dinheiro do nada e é o
			# principal motivo de partidas que não terminam.
			_set_phase(state, Phase.MANAGE)


func _land_on_deed(state: MatchState, player: int, tile: int) -> void:
	var landlord := owner_of(state, tile)
	if landlord == NO_OWNER:
		# Sem dinheiro para comprar não é uma escolha: a casa fica do banco e o
		# turno segue. Sem leilão, não há nada a decidir.
		if cash_of(state, player) >= MonopolyBoard.price_of(tile):
			_set_phase(state, Phase.BUY)
		else:
			_set_phase(state, Phase.MANAGE)
		return
	if landlord == player:
		_set_phase(state, Phase.MANAGE)
		return
	var rent := rent_for(state, tile, last_roll(state))
	if rent <= 0:
		_set_phase(state, Phase.MANAGE)
		return
	_charge(state, player, rent, landlord)


func _do_buy(state: MatchState, player: int) -> void:
	var tile := position_of(state, player)
	_pay(state, player, MonopolyBoard.price_of(tile))
	var owners := PackedInt32Array(state.meta[OWNER])
	owners[tile] = player
	state.meta[OWNER] = owners
	_set_phase(state, Phase.MANAGE)


func _do_build(state: MatchState, player: int, tile: int) -> void:
	_pay(state, player, MonopolyBoard.house_cost(tile))
	_set_houses(state, tile, houses_on(state, tile) + 1)


func _do_sell(state: MatchState, player: int, tile: int) -> void:
	_earn(state, player, MonopolyBoard.house_cost(tile) / 2)
	_set_houses(state, tile, houses_on(state, tile) - 1)
	_settle(state, player)


func _do_mortgage(state: MatchState, player: int, tile: int) -> void:
	_earn(state, player, MonopolyBoard.mortgage_value(tile))
	_set_mortgage(state, tile, true)
	_settle(state, player)


func _do_unmortgage(state: MatchState, player: int, tile: int) -> void:
	_pay(state, player, MonopolyBoard.unmortgage_cost(tile))
	_set_mortgage(state, tile, false)


## A carta sai, faz o que faz, e some. Quem move manda de volta para `_land`,
## então uma carta pode levar a outra — "volte três casas" a partir da última
## Sorte cai num Cofre, e a fase volta a ser DRAW sem nenhum caso especial.
func _do_card(state: MatchState, player: int, which: int, index: int) -> void:
	var card := MonopolyBoard.card(which, index)
	var value := int(card.get("value", 0))
	_set_phase(state, Phase.MANAGE)

	match int(card["effect"]):
		MonopolyBoard.Effect.MONEY:
			if value >= 0:
				_earn(state, player, value)
			else:
				_charge(state, player, -value, BANK)
		MonopolyBoard.Effect.MOVE_TO:
			_jump_to(state, player, value)
		MonopolyBoard.Effect.MOVE_BY:
			_step_back(state, player, value)
		MonopolyBoard.Effect.GOTO_JAIL:
			_send_to_jail(state, player)
		MonopolyBoard.Effect.JAIL_CARD:
			var cards := PackedInt32Array(state.meta[CARDS])
			cards[player] += 1
			state.meta[CARDS] = cards
			state.meta[JAIL_OUT] = int(state.meta.get(JAIL_OUT, 0)) | (1 << which)
		MonopolyBoard.Effect.PER_BUILDING:
			_charge(state, player, _building_bill(state, player, card), BANK)
		MonopolyBoard.Effect.EACH_PLAYER:
			_settle_with_table(state, player, value)


func _building_bill(state: MatchState, player: int, card: Dictionary) -> int:
	var per_house := int(card.get("house", 0))
	var per_hotel := int(card.get("hotel", 0))
	var total := 0
	for tile in deeds_of(state, player):
		var built := houses_on(state, tile)
		if built == MonopolyBoard.HOTEL:
			total += per_hotel
		else:
			total += built * per_house
	return total


## Recebe de cada um, ou paga a cada um. Quem não tem o bastante paga o que tem —
## a alternativa seria abrir uma dívida com cada jogador da mesa ao mesmo tempo,
## e a fase RAISE só sabe cobrar um credor.
func _settle_with_table(state: MatchState, player: int, amount: int) -> void:
	var cash := PackedInt32Array(state.meta[CASH])
	for other in seats_of(state):
		if other == player or is_out(state, other):
			continue
		var moved := amount
		if amount > 0:
			moved = mini(amount, cash[other])
			cash[other] -= moved
			cash[player] += moved
		else:
			moved = mini(-amount, cash[player])
			cash[player] -= moved
			cash[other] += moved
	state.meta[CASH] = cash


# --- troca --------------------------------------------------------------------


## A proposta vai para a mesa e a partida para de andar até ser respondida.
##
## Propor não gasta o turno: `OFFER_BACK` guarda de onde se saiu, e uma recusa
## devolve o jogador exatamente ao ponto em que ele estava. Sem isso, tentar uma
## troca e ouvir "não" custaria a rolagem.
func _do_offer(state: MatchState, path: PackedInt32Array) -> void:
	state.meta[OFFER_BACK] = phase_of(state)
	state.meta[OFFER_TO] = path[1]
	state.meta[OFFER_CASH] = path[2]
	state.meta[OFFER_GIVE] = offered_give(path)
	state.meta[OFFER_GET] = offered_get(path)
	state.meta[PHASE] = Phase.TRADE


## As escrituras mudam de mão e o dinheiro é liquidado.
##
## Quem aceitou **não é o jogador da vez**, então o destinatário sai de `meta` e
## não de `turn_of` — é o único lugar do arquivo em que isso acontece.
##
## A hipoteca viaja junto com a escritura, e sem taxa: quem recebe uma casa
## hipotecada recebe a dívida dela, e resgata quando quiser pelos mesmos 10% de
## sempre. A regra de mesa cobra os juros na hora da transferência; cobrá-los
## aqui abriria uma cobrança que pode não caber no bolso **dentro** de um lance
## que já mudou as escrituras de dono, e desfazer isso pela metade é pior que a
## simplificação.
func _do_accept(state: MatchState) -> void:
	var proposer := turn_of(state)
	var partner := offer_to(state)
	var owners := PackedInt32Array(state.meta[OWNER])
	for tile in offer_give(state):
		owners[tile] = partner
	for tile in offer_get(state):
		owners[tile] = proposer
	state.meta[OWNER] = owners

	var amount := offer_cash(state)
	if amount > 0:
		_pay(state, proposer, amount)
		_earn(state, partner, amount)
	elif amount < 0:
		_pay(state, partner, -amount)
		_earn(state, proposer, -amount)

	_close_offer(state)
	# A troca pode ter coberto a dívida que abriu a fase RAISE. É justamente por
	# isso que propor é legal lá: vender uma cor a quem a quer costuma render
	# mais que hipotecá-la, e é a última saída de quem está quebrando.
	_settle(state, proposer)


func _close_offer(state: MatchState) -> void:
	state.meta[PHASE] = int(state.meta.get(OFFER_BACK, Phase.MANAGE))
	state.meta[OFFER_TO] = FREE
	state.meta[OFFER_CASH] = 0
	state.meta[OFFER_GIVE] = PackedInt32Array()
	state.meta[OFFER_GET] = PackedInt32Array()
	state.meta[OFFER_BACK] = Phase.MANAGE


# --- dinheiro -----------------------------------------------------------------


func _earn(state: MatchState, player: int, amount: int) -> void:
	var cash := PackedInt32Array(state.meta[CASH])
	cash[player] += amount
	state.meta[CASH] = cash


## Débito garantido: só chamado onde a legalidade do lance já garantiu o saldo.
func _pay(state: MatchState, player: int, amount: int) -> void:
	var cash := PackedInt32Array(state.meta[CASH])
	cash[player] -= amount
	state.meta[CASH] = cash


## Cobrança que **pode não caber no bolso**. Cabendo, paga e a vida segue; não
## cabendo, o jogo entra em RAISE e o jogador só sai de lá levantando dinheiro ou
## quebrando.
##
## Toda saída de dinheiro involuntária passa por aqui — aluguel, imposto, carta,
## fiança. As voluntárias (comprar, construir, desipotecar) usam `_pay`, porque
## lá o lance só existe se o dinheiro existe.
func _charge(state: MatchState, player: int, amount: int, creditor: int) -> void:
	if amount <= 0:
		_set_phase(state, Phase.MANAGE)
		return
	if cash_of(state, player) >= amount:
		_pay(state, player, amount)
		if creditor >= 0:
			_earn(state, creditor, amount)
		_set_phase(state, Phase.MANAGE)
		return
	state.meta[DEBT] = amount
	state.meta[CREDITOR] = creditor
	state.meta[PHASE] = Phase.RAISE


## Chamado depois de cada venda ou hipoteca: se o dinheiro chegou, a dívida é
## paga e o turno volta a andar.
func _settle(state: MatchState, player: int) -> void:
	if phase_of(state) != Phase.RAISE:
		return
	var owed := debt_of(state)
	if cash_of(state, player) < owed:
		return
	var creditor := creditor_of(state)
	_pay(state, player, owed)
	if creditor >= 0:
		_earn(state, creditor, owed)
	state.meta[DEBT] = 0
	state.meta[CREDITOR] = BANK
	state.meta[PHASE] = Phase.MANAGE


# --- cadeia -------------------------------------------------------------------


func _send_to_jail(state: MatchState, player: int) -> void:
	var position := PackedInt32Array(state.meta[POS])
	position[player] = MonopolyBoard.JAIL_TILE
	state.meta[POS] = position
	var jail := PackedInt32Array(state.meta[JAIL])
	jail[player] = 0
	state.meta[JAIL] = jail
	# Ir para a cadeia encerra o turno mesmo depois de uma dupla — é o que
	# transforma a terceira dupla em castigo em vez de bônus.
	state.meta[DOUBLES] = 0
	_set_phase(state, Phase.MANAGE)


func _leave_jail(state: MatchState, player: int) -> void:
	var jail := PackedInt32Array(state.meta[JAIL])
	jail[player] = FREE
	state.meta[JAIL] = jail


## Devolve a carta ao baralho. Qual das duas voltou não é distinguível — as duas
## são idênticas no efeito —, então limpa-se o bit mais baixo em uso.
func _spend_jail_card(state: MatchState, player: int) -> void:
	var cards := PackedInt32Array(state.meta[CARDS])
	cards[player] -= 1
	state.meta[CARDS] = cards
	var held := int(state.meta.get(JAIL_OUT, 0))
	if held & 1:
		held &= ~1
	elif held & 2:
		held &= ~2
	state.meta[JAIL_OUT] = held


# --- falência e fim de turno --------------------------------------------------


## O jogador sai da partida e o patrimônio dele muda de mãos.
##
## Para um credor humano: as construções viram dinheiro do banco (metade), o
## caixa inteiro vai para o credor, e as escrituras — hipotecadas ou não —
## passam para ele. Para o banco: as escrituras voltam ao mercado limpas, e é
## como se nunca tivessem sido vendidas.
func _do_bankrupt(state: MatchState, player: int) -> void:
	var creditor := creditor_of(state)
	var owners := PackedInt32Array(state.meta[OWNER])
	var houses := PackedInt32Array(state.meta[HOUSES])
	var mortgaged := PackedInt32Array(state.meta[MORT])
	var refund := 0

	for tile in MonopolyBoard.SIZE:
		if owners[tile] != player:
			continue
		refund += houses[tile] * MonopolyBoard.house_cost(tile) / 2
		houses[tile] = 0
		if creditor >= 0:
			owners[tile] = creditor
		else:
			owners[tile] = NO_OWNER
			mortgaged[tile] = 0

	state.meta[OWNER] = owners
	state.meta[HOUSES] = houses
	state.meta[MORT] = mortgaged

	var cash := PackedInt32Array(state.meta[CASH])
	var estate := cash[player] + refund
	cash[player] = 0
	if creditor >= 0:
		cash[creditor] += estate
	state.meta[CASH] = cash

	# A carta de saída livre volta ao baralho junto com o resto. Não passa por
	# `_spend_jail_card` porque aquilo devolve uma por chamada e aqui pode haver
	# duas; e o bit que se limpa é indiferente, as duas cartas são iguais.
	var cards := PackedInt32Array(state.meta[CARDS])
	var returning := cards[player]
	cards[player] = 0
	state.meta[CARDS] = cards
	var held := int(state.meta.get(JAIL_OUT, 0))
	while returning > 0 and held != 0:
		held &= held - 1
		returning -= 1
	state.meta[JAIL_OUT] = held

	var out := PackedInt32Array(state.meta[OUT])
	out[player] = 1
	state.meta[OUT] = out
	state.meta[DEBT] = 0
	state.meta[CREDITOR] = BANK
	_end_turn(state)


## Passa a vez, ou devolve o turno a quem tirou dupla.
##
## A rodada avança quando o índice do próximo é menor ou igual ao do atual, isto
## é, quando a volta na mesa fechou. Com jogadores eliminados a conta não é
## exata — quem quebra no meio da rodada encurta aquela volta —, e não precisa
## ser: o limite de rodadas é um relógio de partida, não um contador de lances.
func _end_turn(state: MatchState) -> void:
	var player := turn_of(state)
	if int(state.meta[DOUBLES]) > 0 and not is_out(state, player) and not in_jail(state, player):
		state.meta[PHASE] = Phase.ROLL
		return

	state.meta[DOUBLES] = 0
	state.meta[DEBT] = 0
	state.meta[CREDITOR] = BANK
	var count := seats_of(state)
	var next := player
	for _step in count:
		next = (next + 1) % count
		if not is_out(state, next):
			break
	if next <= player:
		state.meta[ROUND] = round_of(state) + 1
	state.meta[TURN] = next
	state.meta[PHASE] = Phase.JAILED if in_jail(state, next) else Phase.ROLL


# --- escrita auxiliar ---------------------------------------------------------


func _set_phase(state: MatchState, phase: int) -> void:
	state.meta[PHASE] = phase


func _set_houses(state: MatchState, tile: int, count: int) -> void:
	var houses := PackedInt32Array(state.meta[HOUSES])
	houses[tile] = count
	state.meta[HOUSES] = houses


func _set_mortgage(state: MatchState, tile: int, value: bool) -> void:
	var mortgaged := PackedInt32Array(state.meta[MORT])
	mortgaged[tile] = 1 if value else 0
	state.meta[MORT] = mortgaged


# --- fim de partida -----------------------------------------------------------


## Índice de quem venceu, ou -1.
##
## Dois critérios, escolhidos no menu. Até a falência: vence quem sobrar. Por
## rodadas: fechado o número de voltas, vence o maior patrimônio — e o empate
## fica com quem estiver mais perto do começo da mesa, que é arbitrário mas é
## determinístico, que é o que importa para os dois aparelhos concordarem.
func winner(state: MatchState) -> int:
	var alive := alive_players(state)
	if alive.is_empty():
		return -1
	if alive.size() == 1:
		return alive[0]
	var limit := limit_of(state)
	if limit > 0 and round_of(state) >= limit:
		var best := alive[0]
		for player in alive:
			if net_worth(state, player) > net_worth(state, best):
				best = player
		return best
	return -1


func outcome(state: MatchState) -> Outcome:
	var champion := winner(state)
	if champion < 0:
		return Outcome.ONGOING
	# O enum tem dois lados e a mesa tem até seis. Quem desenha a tela lê
	# `winner()`; isto aqui só responde "acabou".
	return Outcome.WHITE_WINS if champion == 0 else Outcome.BLACK_WINS


# --- bot ----------------------------------------------------------------------


## Quanto o bot procura manter em caixa depois de gastar. Existe porque a
## falência quase nunca vem de uma compra ruim — vem de comprar tudo e cair num
## aluguel duas casas depois.
const BOT_RESERVE := 140
## Acima disto ele paga fiança em vez de tentar a dupla. Preso é bom quando o
## tabuleiro está cheio de hotéis alheios e ruim quando ainda há o que comprar, e
## o caixa é a melhor pista disponível de em que fase da partida se está.
const BOT_BAIL_CASH := 400


## Escolha do bot entre os lances legais de agora.
##
## O `Bot` de busca do app não serve, e não é questão de ajuste: ele trataria os
## dados como escolha do jogador e procuraria a linha em que todo mundo tira o
## que precisa. Uma busca honesta aqui precisaria de nós de chance sobre 36
## rolagens **e** de um modelo de economia — muito maquinário para um jogo em que
## meia dúzia de regras de bolso joga razoavelmente. Mesma decisão do Ludo.
##
## Rolar e tirar carta **não são escolhas**: são acaso, e o bot sorteia. Devolver
## um lance de rolagem aqui é honesto justamente porque os seis valores têm o
## mesmo peso — quem chama pode ignorar os dados que vierem e sortear os seus.
func best_move(state: MatchState, moves: Array[Move]) -> Move:
	if moves.is_empty():
		return null
	# `actor_of` e não `turn_of`: numa proposta na mesa quem responde é o outro, e
	# um bot que lesse a vez julgaria a troca com o bolso de quem a propôs.
	var player := actor_of(state)
	match phase_of(state):
		Phase.ROLL:
			return _any(_with_act(moves, Act.ROLL))
		Phase.DRAW:
			return _any(moves)
		Phase.JAILED:
			return _bot_in_jail(state, player, moves)
		Phase.BUY:
			return _bot_buying(state, player, moves)
		Phase.MANAGE:
			return _bot_managing(state, player, moves)
		Phase.RAISE:
			return _bot_raising(state, player, moves)
		Phase.TRADE:
			return _bot_trading(state, player, moves)
	return moves[0]


## Aceita a proposta que o deixa mais rico, pelo preço de tabela das escrituras.
##
## O bot **responde, e não propõe**, e isso é deliberado. Um bot que propõe
## precisa de um freio contra o laço óbvio — proponho, você recusa, proponho de
## novo — e o freio é uma contagem de propostas por turno em `meta`, sincronizada
## e testada, para um ganho que é conversa entre máquinas. Trocar continua sendo
## uma jogada de quem está segurando o celular.
func _bot_trading(state: MatchState, responder: int, moves: Array[Move]) -> Move:
	var balance := offer_cash(state)
	for tile in offer_give(state):
		balance += _trade_value(state, responder, tile)
	for tile in offer_get(state):
		balance -= _trade_value(state, responder, tile)
	if balance > 0:
		var yes := _first(moves, Act.ACCEPT)
		if yes != null:
			return yes
	return _first(moves, Act.REJECT)


## O que uma escritura vale para este jogador nesta troca.
##
## Preço de tabela, **dobrado** quando a casa fecha uma cor para ele ou quando
## sair dali quebra uma cor que ele já tinha. É a única distinção que a heurística
## faz, e é a que importa: sem ela o bot troca a terceira rua de um grupo dele
## pela primeira de um grupo alheio, que é a pior troca do jogo feita ao preço
## nominal certo.
##
## Hipotecada vale menos o custo de resgate, porque é isso que ela custa para
## voltar a cobrar aluguel.
func _trade_value(state: MatchState, player: int, tile: int) -> int:
	var value := MonopolyBoard.price_of(tile)
	if is_mortgaged(state, tile):
		value -= MonopolyBoard.unmortgage_cost(tile)
	var group := MonopolyBoard.group_of(tile)
	if owner_of(state, tile) == player:
		if owns_group(state, player, group):
			value *= 2
	elif _would_complete(state, player, tile):
		value *= 2
	return value


## Carta primeiro, que é de graça. Fiança só com caixa folgado: pagar 50 para sair
## e cair num hotel na jogada seguinte é como se perde uma partida ganha.
func _bot_in_jail(state: MatchState, player: int, moves: Array[Move]) -> Move:
	var card := _first(moves, Act.USE_CARD)
	if card != null:
		return card
	if cash_of(state, player) >= BOT_BAIL_CASH:
		var bail := _first(moves, Act.BAIL)
		if bail != null:
			return bail
	return _any(_with_act(moves, Act.ROLL))


## Compra quando sobra reserva — **ou** quando a compra fecha uma cor, que é a
## única coisa no jogo que multiplica aluguel. Fechar um grupo vale ficar sem
## caixa; comprar a terceira casa avulsa de um grupo alheio não vale.
func _bot_buying(state: MatchState, player: int, moves: Array[Move]) -> Move:
	var buy := _first(moves, Act.BUY)
	if buy == null:
		return _first(moves, Act.DECLINE)
	var tile := position_of(state, player)
	var left := cash_of(state, player) - MonopolyBoard.price_of(tile)
	if _would_complete(state, player, tile) or left >= BOT_RESERVE:
		return buy
	return _first(moves, Act.DECLINE)


## Esta compra fecha o grupo: todas as outras casas da cor já são dele.
func _would_complete(state: MatchState, player: int, tile: int) -> bool:
	var group := MonopolyBoard.group_of(tile)
	if group == MonopolyBoard.Group.NONE:
		return false
	for other in MonopolyBoard.group_tiles(group):
		if other != tile and owner_of(state, other) != player:
			return false
	return true


## Constrói enquanto sobra reserva, resgata hipoteca quando está rico, e encerra.
##
## A ordem importa: construir é o que rende, resgatar é o que devolve renda
## parada, e encerrar é o que não faz nada. O bot faz **uma** coisa por chamada e
## a tela pergunta de novo — assim ele constrói várias casas num turno sem que
## isto precise saber quantas cabem.
func _bot_managing(state: MatchState, player: int, moves: Array[Move]) -> Move:
	var purse := cash_of(state, player)
	var best: Move = null
	var best_score := 0.0
	for move in moves:
		if act_of(move) != Act.BUILD:
			continue
		var tile := move.path[1]
		if purse - MonopolyBoard.house_cost(tile) < BOT_RESERVE:
			continue
		# O salto de aluguel que esta casa compra, por unidade gasta. É o que
		# separa construir no laranja de construir no marrom com o mesmo dinheiro.
		var table: Array = MonopolyBoard.tile(tile)["rent"]
		var built := houses_on(state, tile)
		var gain := float(table[built + 1] - table[built])
		var score := gain / maxf(1.0, float(MonopolyBoard.house_cost(tile)))
		if score > best_score:
			best_score = score
			best = move
	if best != null:
		return best

	for move in moves:
		if act_of(move) != Act.UNMORTGAGE:
			continue
		# Só com folga de sobra: uma escritura hipotecada não cobra aluguel, mas
		# também não cobra nada de quem a segura.
		if purse - MonopolyBoard.unmortgage_cost(move.path[1]) >= BOT_RESERVE * 2:
			return move

	return _first(moves, Act.END)


## Levanta dinheiro pelo caminho menos caro: hipoteca antes de vender casa.
##
## Hipotecar é reversível — paga-se 10% para desfazer. Vender construção devolve
## metade do que custou e não volta atrás. Entre hipotecas, a de maior valor
## primeiro: cada ação dessas é um lance, e cobrir a dívida em dois passos em vez
## de cinco é o que evita quebrar por falta de tempo.
##
## Fora de um grupo fechado antes: hipotecar uma cor completa desliga o aluguel
## dobrado das irmãs também.
func _bot_raising(state: MatchState, player: int, moves: Array[Move]) -> Move:
	var best: Move = null
	var best_score := -1.0
	for move in moves:
		var act := act_of(move)
		if act != Act.MORTGAGE and act != Act.SELL:
			continue
		var tile := move.path[1]
		var raised := (
			MonopolyBoard.mortgage_value(tile)
			if act == Act.MORTGAGE
			else MonopolyBoard.house_cost(tile) / 2
		)
		var score := float(raised)
		if act == Act.SELL:
			score *= 0.35
		if owns_group(state, player, MonopolyBoard.group_of(tile)):
			score *= 0.5
		if score > best_score:
			best_score = score
			best = move
	if best != null:
		return best
	return _first(moves, Act.BANKRUPT)


static func _with_act(moves: Array[Move], act: int) -> Array[Move]:
	var found: Array[Move] = []
	for move in moves:
		if act_of(move) == act:
			found.append(move)
	return found


static func _first(moves: Array[Move], act: int) -> Move:
	for move in moves:
		if act_of(move) == act:
			return move
	return null


static func _any(moves: Array[Move]) -> Move:
	if moves.is_empty():
		return null
	return moves[randi() % moves.size()]


# --- texto --------------------------------------------------------------------


func status_hint(state: MatchState) -> String:
	var champion := winner(state)
	if champion >= 0:
		return "Jogador %d venceu" % (champion + 1)
	match phase_of(state):
		Phase.TRADE:
			return "Proposta de troca para o jogador %d" % (offer_to(state) + 1)
		Phase.RAISE:
			return "Levante %d ou declare falência" % debt_of(state)
		Phase.BUY:
			return "%s está à venda" % MonopolyBoard.display_name(
				position_of(state, turn_of(state))
			)
		Phase.JAILED:
			return "Na cadeia"
	return ""


func notation(state: MatchState, move: Move) -> String:
	var player := turn_of(state) + 1
	match act_of(move):
		Act.ROLL:
			return "%d) %d+%d" % [player, move.path[1], move.path[2]]
		Act.BUY:
			return "%d) compra %s" % [
				player, MonopolyBoard.short_name(position_of(state, turn_of(state)))
			]
		Act.DECLINE:
			return "%d) passa" % player
		Act.DRAW:
			return "%d) %s" % [player, "Cofre" if move.path[1] == MonopolyBoard.CHEST else "Sorte"]
		Act.BUILD:
			return "%d) constrói %s" % [player, MonopolyBoard.short_name(move.path[1])]
		Act.SELL:
			return "%d) vende casa %s" % [player, MonopolyBoard.short_name(move.path[1])]
		Act.MORTGAGE:
			return "%d) hipoteca %s" % [player, MonopolyBoard.short_name(move.path[1])]
		Act.UNMORTGAGE:
			return "%d) resgata %s" % [player, MonopolyBoard.short_name(move.path[1])]
		Act.BAIL:
			return "%d) paga fiança" % player
		Act.USE_CARD:
			return "%d) usa saída livre" % player
		Act.BANKRUPT:
			return "%d) falência" % player
		Act.OFFER:
			return "%d) propõe troca a %d" % [player, move.path[1] + 1]
		Act.ACCEPT:
			return "%d) aceita a troca" % (offer_to(state) + 1)
		Act.REJECT:
			return "%d) recusa a troca" % (offer_to(state) + 1)
		Act.END:
			return "%d) fim" % player
	return ""
