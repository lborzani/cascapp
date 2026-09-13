class_name BattleshipRules
extends Ruleset

## Batalha naval em 8x8, quatro navios por lado.
##
## O tabuleiro de 10x10 é o mais conhecido, mas 8x8 é o que deixa o `Board`
## inteiro servir sem uma linha nova: mesmo índice `rank * 8 + file`, mesma
## coordenada "e4" na moldura, mesmas 64 casas. Um segundo sistema de coordenadas
## no projeto custaria bem mais que a fileira e a coluna que faltam — e com quatro
## navios (12 casas de 64, 19%) a densidade fica na mesma do 10x10 com cinco.
##
## **Informação escondida mora no desenho, não no estado.** As duas frotas ficam
## no `MatchState`, e é a tela que decide o que mostrar. Parece o contrário do
## certo, mas é o que mantém o resto do app de pé: `_apply_sync` reconstrói a
## partida repetindo a lista de lances, e para isso os dois aparelhos precisam
## derivar a mesma posição. Esconder no modelo quebraria a reconexão; esconder no
## desenho não quebra nada. O preço é confiar no cliente do outro — aceitável num
## app onde as partidas nascem de um código de 6 caracteres passado a um amigo.
##
## As frotas não vêm de `initial_state()`: elas são posicionadas antes do primeiro
## tiro, por cada jogador ou pelo bot. Até isso acontecer a posição existe e é
## válida, só não é jogável — `ready()` responde por essa diferença.

## Resultado de um tiro numa casa. `NONE` é casa nunca visitada, e é o que
## `generate_moves` procura.
enum Shot { NONE = 0, MISS = 1, HIT = 2 }

## Um navio por espécie, então a casa atingida já diz **qual** navio afundou sem
## precisar de um identificador por casco. Dois navios de três casas com nomes
## diferentes é o padrão do jogo de caixa, não economia nossa.
const SHIPS := [
	{"kind": Board.Kind.BATTLESHIP, "size": 4, "name": "Encouraçado"},
	{"kind": Board.Kind.CRUISER, "size": 3, "name": "Cruzador"},
	{"kind": Board.Kind.SUBMARINE, "size": 3, "name": "Submarino"},
	{"kind": Board.Kind.DESTROYER, "size": 2, "name": "Destroier"},
]

## Casas ocupadas por uma frota inteira. Serve de alvo para o posicionamento e de
## divisor no cálculo de quanto já foi afundado.
const FLEET_CELLS := 12

## Chaves de `meta`. Frota é o que o lado **tem**; tiros são os que ele **deu**,
## então `SHOTS[WHITE]` marca o tabuleiro das pretas.
##
## Quatro `PackedInt32Array` planos, e não um dicionário aninhado por lado, porque
## `MatchState.clone()` copia `meta` de forma rasa. Packed array é tipo de valor
## com cópia-na-escrita, então a cópia rasa já entrega arrays independentes; um
## `Dictionary` aninhado ali dentro seria compartilhado e é exatamente o caso que
## `match_state.gd` avisa que quebra.
const FLEET := {Board.Side.WHITE: "fleet_w", Board.Side.BLACK: "fleet_b"}
const SHOTS := {Board.Side.WHITE: "shots_w", Board.Side.BLACK: "shots_b"}


func id() -> StringName:
	return &"battleship"


func display_name() -> String:
	return "Batalha Naval"


## `squares` fica vazio a partida inteira. Batalha naval não tem peça que ande
## por um tabuleiro comum aos dois: são dois mares, e os dois moram em `meta`.
## Guardar um deles em `squares` e o outro em `meta` deixaria os lados assimétricos
## e é assim que nasce o bug de ler o mar errado.
func initial_state() -> MatchState:
	var state := MatchState.new()
	for side in [Board.Side.WHITE, Board.Side.BLACK]:
		state.meta[FLEET[side]] = empty_grid()
		state.meta[SHOTS[side]] = empty_grid()
	state.side_to_move = Board.Side.WHITE
	return state


## Toda casa em que este lado ainda não atirou. Repetir um tiro não é lance: não
## muda nada e só devolveria a vez ao adversário de graça.
func generate_moves(state: MatchState) -> Array[Move]:
	var moves: Array[Move] = []
	if not ready(state):
		return moves
	var shots := shots_of(state, state.side_to_move)
	for sq in Board.SQUARE_COUNT:
		if shots[sq] == Shot.NONE:
			var move := Move.new()
			# Um tiro é uma casa só. `from_square()` e `to_square()` devolvem a
			# mesma, que é a verdade — não existe origem separada do destino.
			move.path = PackedInt32Array([sq])
			moves.append(move)
	return moves


## Acertar **não** dá direito a atirar de novo. É a regra da caixa, e é a que
## mantém a partida com ritmo previsível: com tiro extra por acerto, uma sequência
## de sorte encerra o jogo sem o outro jogar.
func apply_move(state: MatchState, move: Move) -> void:
	var side := state.side_to_move
	var target := move.to_square()
	var enemy := fleet_of(state, Board.opponent(side))

	# Packed array é cópia-na-escrita: `shots_of` devolve uma cópia independente
	# assim que esta linha escreve nela, e o dicionário continua com a antiga até
	# a devolução logo abaixo. Esquecer de devolver é um tiro que some.
	var shots := shots_of(state, side)
	shots[target] = Shot.HIT if enemy[target] != 0 else Shot.MISS
	state.meta[SHOTS[side]] = shots

	state.side_to_move = Board.opponent(side)
	state.ply += 1
	state.history.append(move.to_dict())


func outcome(state: MatchState) -> Outcome:
	if not ready(state):
		return Outcome.ONGOING
	if _fleet_sunk(state, Board.Side.BLACK):
		return Outcome.WHITE_WINS
	if _fleet_sunk(state, Board.Side.WHITE):
		return Outcome.BLACK_WINS
	return Outcome.ONGOING


## Não existe empate: os tiros nunca acabam antes dos navios, porque cada tiro ou
## acerta ou marca uma casa a menos onde procurar.
func outcome_text(result: Outcome) -> String:
	match result:
		Outcome.WHITE_WINS:
			return "Frota preta afundada"
		Outcome.BLACK_WINS:
			return "Frota branca afundada"
		_:
			return ""


## Quantos navios inteiros ainda faltam para o lado da vez. É o que o jogador
## quer saber antes de escolher a próxima casa, e o único número que resume a
## partida sem revelar nada do que está escondido.
func status_hint(state: MatchState) -> String:
	if not ready(state):
		return "Posicione a frota"
	var left := ships_afloat(state, Board.opponent(state.side_to_move))
	if left == 1:
		return "Falta 1 navio inimigo"
	return "Faltam %d navios inimigos" % left


## Zero, sempre. Avaliar posição pressupõe enxergar a posição, e aqui metade dela
## é segredo — uma nota calculada sobre a frota inimiga seria o bot lendo o que o
## jogador não pode ler. O adversário de batalha naval não é busca em árvore, é
## caça e perseguição, e mora em `BattleshipBot`.
func evaluate(_state: MatchState) -> float:
	return 0.0


## "e4" no tiro n'água, "e4 ×" no acerto, e o nome do navio quando ele foi o
## último a cair. O nome só aparece no afundamento porque é a única hora em que
## ele é informação pública pelas regras do jogo.
func notation(state: MatchState, move: Move) -> String:
	var target := move.to_square()
	var name := Board.square_name(target)
	var enemy := fleet_of(state, Board.opponent(state.side_to_move))
	var kind := enemy[target]
	if kind == 0:
		return name
	# `state` é a posição **antes** do lance, então este tiro ainda não está
	# marcado. Soma-se ele às marcas anteriores para saber se completou o navio.
	var shots := shots_of(state, state.side_to_move)
	shots[target] = Shot.HIT
	if is_sunk(enemy, shots, kind):
		return "%s afundou %s" % [name, ship_name(kind)]
	return "%s ×" % name


# --- acesso ao estado --------------------------------------------------------


static func empty_grid() -> PackedInt32Array:
	var grid := PackedInt32Array()
	grid.resize(Board.SQUARE_COUNT)
	grid.fill(0)
	return grid


static func fleet_of(state: MatchState, side: int) -> PackedInt32Array:
	return state.meta.get(FLEET[side], empty_grid())


static func shots_of(state: MatchState, side: int) -> PackedInt32Array:
	return state.meta.get(SHOTS[side], empty_grid())


static func set_fleet(state: MatchState, side: int, fleet: PackedInt32Array) -> void:
	state.meta[FLEET[side]] = fleet


## As duas frotas posicionadas. Antes disso não há lance legal e nem vencedor —
## um mar vazio marcaria "afundado" no primeiro teste.
static func ready(state: MatchState) -> bool:
	for side in [Board.Side.WHITE, Board.Side.BLACK]:
		if _occupied(fleet_of(state, side)) != FLEET_CELLS:
			return false
	return true


static func _occupied(fleet: PackedInt32Array) -> int:
	var total := 0
	for sq in Board.SQUARE_COUNT:
		if fleet[sq] != 0:
			total += 1
	return total


## Todas as casas de `kind` já atingidas.
static func is_sunk(fleet: PackedInt32Array, shots: PackedInt32Array, kind: int) -> bool:
	for sq in Board.SQUARE_COUNT:
		if fleet[sq] == kind and shots[sq] != Shot.HIT:
			return false
	return true


## Navios de `side` que ainda têm ao menos uma casa inteira.
static func ships_afloat(state: MatchState, side: int) -> int:
	var fleet := fleet_of(state, side)
	var shots := shots_of(state, Board.opponent(side))
	var total := 0
	for ship in SHIPS:
		if not is_sunk(fleet, shots, int(ship["kind"])):
			total += 1
	return total


static func _fleet_sunk(state: MatchState, side: int) -> bool:
	return ships_afloat(state, side) == 0


static func ship_name(kind: int) -> String:
	for ship in SHIPS:
		if int(ship["kind"]) == kind:
			return str(ship["name"])
	return ""


static func ship_size(kind: int) -> int:
	for ship in SHIPS:
		if int(ship["kind"]) == kind:
			return int(ship["size"])
	return 0


# --- posicionamento ----------------------------------------------------------


## Casas que um navio ocuparia, ou vazio se ele não cabe ali. Devolver o caminho
## em vez de um `bool` é o que deixa a tela pintar a prévia com a mesma conta que
## valida — duas contas separadas divergem, e aí a prévia mente.
static func footprint(from: int, size: int, horizontal: bool) -> PackedInt32Array:
	var file := Board.file_of(from)
	var rank := Board.rank_of(from)
	var cells := PackedInt32Array()
	for step in size:
		var f := file + step if horizontal else file
		var r := rank if horizontal else rank + step
		if not Board.in_bounds(f, r):
			return PackedInt32Array()
		cells.append(Board.square(f, r))
	return cells


## Navios podem **encostar** uns nos outros, como na caixa. Proibir o contato é
## variante comum, e ela facilita demais a caça: cada afundamento entregaria de
## graça um anel inteiro de casas vazias em volta.
static func can_place(fleet: PackedInt32Array, from: int, size: int, horizontal: bool) -> bool:
	var cells := footprint(from, size, horizontal)
	if cells.is_empty():
		return false
	for sq in cells:
		if fleet[sq] != 0:
			return false
	return true


static func place(
	fleet: PackedInt32Array, kind: int, from: int, horizontal: bool
) -> PackedInt32Array:
	var cells := footprint(from, ship_size(kind), horizontal)
	var placed := fleet.duplicate()
	for sq in cells:
		placed[sq] = kind
	return placed


## Frota inteira sorteada. Serve ao bot e ao botão "embaralhar" da tela de
## posicionamento — ninguém quer colocar quatro navios à mão toda partida.
##
## Tentativa e erro em vez de busca ordenada de propósito: com 12 casas em 64 a
## colisão é rara, e um sorteio uniforme entre posições válidas é o que impede a
## frota do bot de ter viés que o jogador aprenda a explorar.
static func random_fleet(rng: RandomNumberGenerator) -> PackedInt32Array:
	var fleet := empty_grid()
	for ship in SHIPS:
		var kind := int(ship["kind"])
		var size := int(ship["size"])
		while true:
			var horizontal := rng.randi_range(0, 1) == 0
			var from := rng.randi_range(0, Board.SQUARE_COUNT - 1)
			if can_place(fleet, from, size, horizontal):
				fleet = place(fleet, kind, from, horizontal)
				break
	return fleet
