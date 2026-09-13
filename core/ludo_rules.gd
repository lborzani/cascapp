class_name LudoRules
extends Ruleset

## Ludo de quatro jogadores: 52 casas de trilha, 4 peões por cor, dado de 6.
##
## **Nada disso cabe em `squares`.** O tabuleiro do Ludo não é uma grade de casas
## ocupadas: é um percurso, e o que importa de cada peão é *quanto ele já andou*.
## Guardar 15x15 casas para descrever 16 peões seria carregar 209 zeros por
## posição, e ainda assim não diria de quem é a reta final em que um peão está.
## Então o estado é `meta["prog"]`: 16 inteiros, um por peão.
##
## O **progresso** de um peão vale mais que a casa dele, e é a única coisa
## guardada:
##
##     0        na base, ainda não entrou
##     1..51    na trilha comum, contando da própria saída
##     52..56   na reta final, que é só dele
##     57       chegou
##
## Contar da *própria* saída é o que faz as quatro cores compartilharem uma
## trilha só sem nenhum caso especial: a casa de trilha de um peão é
## `(saída_da_cor + progresso - 1) % 52`, e duas cores em progressos diferentes
## caem na mesma casa exatamente quando deveriam — que é quando uma captura a
## outra.
##
## ## O dado viaja dentro do lance
##
## `generate_moves` devolve todos os pares **(dado, peão)** legais, para os seis
## valores de dado. Parece estranho — o jogador não escolhe o dado — e é o que
## mantém o resto do app funcionando sem exceção nenhuma:
##
## - o lance continua sendo uma coisa só, então `history` reproduz a partida
##   inteira e a reconexão continua sendo repetir a lista de lances;
## - quem recebe valida o lance contra a própria lista de legais, como nos outros
##   jogos — o que ele **não** pode validar é o dado, que é aleatório por
##   definição. Confia-se no cliente do outro para o valor do dado, e em nada
##   além disso. É a mesma confiança que a batalha naval já pede ao guardar as
##   duas frotas no estado.
##
## Rolagem sem lance possível também é lance (peão `PASS`): sem ela, um dado 3
## com os quatro peões na base sumiria do histórico, e os dois aparelhos
## discordariam de quem é a vez.
##
## ## Quatro jogadores num app de dois
##
## `MatchState.side_to_move` é binário e não tem como carregar quatro cores.
## Quem está jogando mora em `meta["turn"]` (0..3), e `side_to_move` fica onde
## está — quem precisa saber pergunta a `turn_of()`. Pelo mesmo motivo `outcome()`
## responde só se acabou: quem venceu é `winner()`, que devolve o índice da cor.

## Quatro cores, na ordem em que jogam. O índice é a identidade do jogador em
## todo lugar: em `prog`, em `meta["turn"]`, no que a tela desenha.
const PLAYERS := 4
const TOKENS := 4
## Casas da trilha comum, e o quanto uma cor anda até a saída da seguinte. As
## quatro saídas ficam a 13 casas uma da outra, e é isso que divide a trilha em
## quatro braços iguais.
const RING := 52
const START_STEP := 13
## Casas da reta final, mais a chegada.
const HOME := 5
## Progresso de quem chegou. Entrar exige número exato: com 3 casas para o fim,
## um 5 não anda — é a regra que faz o fim de partida ter tensão em vez de ser
## uma formalidade.
const GOAL := RING - 1 + HOME + 1
const BASE := 0

## Peão que não existe: a rolagem que não tem lance nenhum. Vale como lance
## porque o dado precisa aparecer no histórico de qualquer jeito.
const PASS := -1

## Sai da base só com 6, e 6 dá direito a jogar de novo. As duas regras são a
## mesma decisão: o 6 é o que destrava a partida, então ele também é o que
## recompensa.
const EXIT_ROLL := 6

## Casas seguras da trilha, em índice absoluto. As quatro saídas e as quatro
## casas oito passos adiante delas — as "estrelas" do tabuleiro de caixa. Peão
## em casa segura não é capturado, e é o que impede que sair da base seja um
## convite a ser mandado de volta na jogada seguinte.
const SAFE_OFFSET := 8

## Chaves de `meta`. Nomes curtos porque `history` viaja pela rede a cada lance.
const PROG := "prog"
const TURN := "turn"


func id() -> StringName:
	return &"ludo"


func players() -> int:
	return PLAYERS


## A contagem padrão (`ply / 4`) **arredonda para baixo** aqui, e de propósito.
##
## Um 6 devolve a vez a quem jogou, então quatro lances nem sempre são uma volta
## completa na mesa — numa partida com muitos 6 a faixa mostra menos rodadas do
## que se jogou. Contar certo exigiria um contador em `meta` andando junto com a
## vez, e a faixa é contexto: errar para menos numa partida cheia de 6 custa
## menos que um campo novo no estado, que todo lance, todo resync e todo teste
## passariam a carregar.
func rounds_played(state: MatchState) -> int:
	return state.ply / PLAYERS


func display_name() -> String:
	return "Ludo"


func initial_state() -> MatchState:
	var state := MatchState.new()
	var progress := PackedInt32Array()
	progress.resize(PLAYERS * TOKENS)
	progress.fill(BASE)
	state.meta[PROG] = progress
	state.meta[TURN] = 0
	state.side_to_move = Board.Side.WHITE
	return state


# --- leitura do estado --------------------------------------------------------


## De quem é a vez, em índice de cor. `side_to_move` não serve: ele tem dois
## valores e aqui existem quatro.
static func turn_of(state: MatchState) -> int:
	return int(state.meta.get(TURN, 0))


static func progress(state: MatchState) -> PackedInt32Array:
	return state.meta.get(PROG, PackedInt32Array())


## Índice do peão `token` da cor `player` dentro de `prog`. Um vetor plano e não
## quatro vetores porque `MatchState.clone()` copia `meta` de forma rasa: um
## `PackedInt32Array` é cópia-na-escrita e sobrevive a isso; um `Array` de
## arrays seria compartilhado entre a posição e a cópia.
static func slot(player: int, token: int) -> int:
	return player * TOKENS + token


static func player_of(slot_index: int) -> int:
	return slot_index / TOKENS


## Casa da trilha comum onde este progresso cai, ou -1 quando o peão está na
## base ou já entrou na reta final — nos dois casos ele não divide espaço com
## ninguém, e é justamente por isso que não pode ser capturado lá.
static func ring_square(player: int, prog: int) -> int:
	if prog < 1 or prog > RING - 1:
		return -1
	return (player * START_STEP + prog - 1) % RING


## Casa segura: as quatro saídas e as quatro estrelas. Em índice absoluto de
## trilha, então a resposta é a mesma para as quatro cores olhando a mesma casa.
static func is_safe(square: int) -> bool:
	if square < 0:
		return false
	var offset := square % START_STEP
	return offset == 0 or offset == SAFE_OFFSET


# --- lances -------------------------------------------------------------------


## Todos os pares (dado, peão) legais, para os seis dados. Quem rola filtra pelo
## valor que tirou; ver o cabeçalho para o porquê de o dado morar no lance.
func generate_moves(state: MatchState) -> Array[Move]:
	var moves: Array[Move] = []
	if winner(state) >= 0:
		return moves
	for die in range(1, 7):
		var any := false
		for token in TOKENS:
			if _target(state, turn_of(state), token, die) >= 0:
				moves.append(_move(die, token))
				any = true
		# Rolagem sem saída ainda é uma rolagem: ela consome a vez, e o histórico
		# precisa dela para os dois aparelhos concordarem sobre quem joga agora.
		if not any:
			moves.append(_move(die, PASS))
	return moves


## Os lances de um dado só — o que a tela usa depois de rolar.
func moves_for(state: MatchState, die: int) -> Array[Move]:
	var moves: Array[Move] = []
	for move in generate_moves(state):
		if die_of(move) == die:
			moves.append(move)
	return moves


static func die_of(move: Move) -> int:
	return move.path[0]


static func token_of(move: Move) -> int:
	return move.path[1]


static func _move(die: int, token: int) -> Move:
	var move := Move.new()
	move.path = PackedInt32Array([die, token])
	return move


## Progresso a que este peão chegaria, ou -1 quando o lance não existe.
##
## Duas recusas, e cada uma é uma regra: sair da base só com 6, e não passar da
## chegada.
##
## Havia uma terceira — "não pousar em cima de peão da própria cor" — e ela saiu.
## Era uma regra de casa disfarçada de regra do jogo, e travava o Ludo no ponto
## mais visível dele: com um peão já na casa de saída, um 6 **não tirava outro da
## base**, porque o único lugar onde ele pode nascer estava ocupado por um peão
## seu. E o efeito seguinte era pior que a recusa — sobrando um lance só, a tela
## joga sozinha, então o 6 saía andando com o peão que já estava fora sem o
## jogador ter escolhido nada.
##
## No Ludo de tabuleiro dois peões da mesma cor dividem casa; algumas variantes
## ainda fazem disso um bloqueio que os outros não atravessam. O bloqueio ficou de
## fora — ele obrigaria o gerador a olhar o caminho inteiro e não só o destino —,
## mas empilhar passou a valer.
func _target(state: MatchState, player: int, token: int, die: int) -> int:
	var prog := progress(state)
	var current := prog[slot(player, token)]
	if current == GOAL:
		return -1
	if current == BASE:
		if die != EXIT_ROLL:
			return -1
		# Sair põe o peão na própria casa de saída, e não seis casas adiante: o 6
		# é a chave da porta, não um avanço.
		return 1
	var landing := current + die
	if landing > GOAL:
		return -1
	return landing


## Aplica o lance. A vez só passa quando o dado não é 6 — tirar 6 joga de novo,
## e é a mesma regra que destrava a saída da base.
func apply_move(state: MatchState, move: Move) -> void:
	var player := turn_of(state)
	var die := die_of(move)
	var token := token_of(move)

	if token != PASS:
		var prog := progress(state)
		var landing := _target(state, player, token, die)
		prog[slot(player, token)] = landing
		state.meta[PROG] = prog
		_capture(state, player, landing)

	if die != EXIT_ROLL:
		state.meta[TURN] = (player + 1) % PLAYERS
	state.ply += 1
	state.history.append(move.to_dict())


## Peão inimigo que estava na casa onde este pousou volta para a base.
##
## Só na trilha comum e só fora das casas seguras. A reta final é privada — duas
## cores nunca ocupam a mesma casa lá —, e a casa segura existe para que sair da
## base não seja um convite a voltar para ela na jogada seguinte.
func _capture(state: MatchState, player: int, landing: int) -> void:
	var square := ring_square(player, landing)
	if square < 0 or is_safe(square):
		return
	var prog := progress(state)
	var changed := false
	for other in PLAYERS:
		if other == player:
			continue
		for token in TOKENS:
			var index := slot(other, token)
			if ring_square(other, prog[index]) == square:
				prog[index] = BASE
				changed = true
	if changed:
		state.meta[PROG] = prog


# --- fim de partida -----------------------------------------------------------


## Índice da cor que levou os quatro peões à chegada, ou -1.
##
## Separado de `outcome()` porque o enum de `Ruleset` tem dois lados e uma cor
## vencedora aqui pode ser qualquer um dos quatro. Quem desenha a tela pergunta
## isto; `outcome()` continua servindo a quem só quer saber se acabou.
func winner(state: MatchState) -> int:
	var prog := progress(state)
	for player in PLAYERS:
		var home := 0
		for token in TOKENS:
			if prog[slot(player, token)] == GOAL:
				home += 1
		if home == TOKENS:
			return player
	return -1


func outcome(state: MatchState) -> Outcome:
	var champion := winner(state)
	if champion < 0:
		return Outcome.ONGOING
	# O enum não tem quatro lados, e forçar um aqui seria inventar uma resposta
	# errada em dois dos quatro casos. A tela do Ludo lê `winner()`.
	return Outcome.WHITE_WINS if champion == 0 else Outcome.BLACK_WINS


## Quantos peões desta cor já chegaram. É o placar da partida, e o que a tela
## mostra ao lado de cada cor.
static func finished(state: MatchState, player: int) -> int:
	var prog := progress(state)
	var total := 0
	for token in TOKENS:
		if prog[slot(player, token)] == GOAL:
			total += 1
	return total


# --- bot ----------------------------------------------------------------------


## Escolha heurística entre os lances de um dado já rolado.
##
## O minimax do `Bot` não serve, e não é questão de ajuste: ele trataria o dado
## como uma escolha do jogador e procuraria a linha em que todo mundo tira o que
## precisa. Uma busca honesta aqui precisaria de nós de chance e de esperança
## matemática — muito maquinário para um jogo em que quatro regras de bolso
## jogam bem.
##
## A ordem é a de um jogador razoável: capturar, chegar, sair da base, entrar na
## reta final, e por fim andar com o peão mais adiantado.
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
	var token := token_of(move)
	if token == PASS:
		return 0.0
	var player := turn_of(state)
	var prog := progress(state)
	var current := prog[slot(player, token)]
	var landing := _target(state, player, token, die_of(move))

	if _captures(state, player, landing):
		return 100.0
	if landing == GOAL:
		return 90.0
	if current == BASE:
		return 80.0
	if landing > RING - 1:
		return 70.0
	# Empate entre lances comuns: anda o peão mais adiantado, que é o que encurta
	# a partida sem espalhar alvos pela trilha.
	var advance := float(landing) / float(GOAL)
	return 10.0 + advance * 10.0 + (5.0 if is_safe(ring_square(player, landing)) else 0.0)


func _captures(state: MatchState, player: int, landing: int) -> bool:
	var square := ring_square(player, landing)
	if square < 0 or is_safe(square):
		return false
	var prog := progress(state)
	for other in PLAYERS:
		if other == player:
			continue
		for token in TOKENS:
			if ring_square(other, prog[slot(other, token)]) == square:
				return true
	return false


# --- texto --------------------------------------------------------------------


func status_hint(state: MatchState) -> String:
	var champion := winner(state)
	if champion >= 0:
		return "%s venceu" % color_name(champion)
	return ""


func notation(state: MatchState, move: Move) -> String:
	var player := turn_of(state)
	var die := die_of(move)
	if token_of(move) == PASS:
		return "%s %d—" % [color_short(player), die]
	var landing := _target(state, player, token_of(move), die)
	if landing == GOAL:
		return "%s %d✓" % [color_short(player), die]
	return "%s %d·%d" % [color_short(player), die, token_of(move) + 1]


const COLOR_NAMES := ["Vermelho", "Verde", "Amarelo", "Azul"]
## Abreviações escritas à mão, e não as duas primeiras letras do nome: "Vermelho"
## e "Verde" começam iguais, e o placar mostrava duas faixas "Ve" lado a lado.
const COLOR_SHORT := ["VM", "VD", "AM", "AZ"]


static func color_name(player: int) -> String:
	return COLOR_NAMES[player % PLAYERS]


static func color_short(player: int) -> String:
	return COLOR_SHORT[player % PLAYERS]
