class_name ChessRules
extends Ruleset

## Standard chess: castling, en passant, promotion, check/checkmate/stalemate,
## the 50 move rule and the common insufficient-material draws.
## Threefold repetition is not tracked (see README).

const KNIGHT_DIRS := [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
const KING_DIRS := [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
const ROOK_DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const BISHOP_DIRS := [[1, 1], [1, -1], [-1, 1], [-1, -1]]
## A dama anda nos dois. Escrito como constante e não como `BISHOP_DIRS +
## ROOK_DIRS` na hora de gerar: aquela soma construía um `Array` novo por dama e
## por chamada, dentro do laço mais quente do app.
const QUEEN_DIRS := [
	[1, 1], [1, -1], [-1, 1], [-1, -1], [1, 0], [-1, 0], [0, 1], [0, -1],
]

const CASTLE_WK := 1
const CASTLE_WQ := 2
const CASTLE_BK := 4
const CASTLE_BQ := 8
const CASTLE_ALL := 15

const PROMOTION_KINDS := [Board.Kind.QUEEN, Board.Kind.ROOK, Board.Kind.BISHOP, Board.Kind.KNIGHT]

const BACK_RANK := [
	Board.Kind.ROOK,
	Board.Kind.KNIGHT,
	Board.Kind.BISHOP,
	Board.Kind.QUEEN,
	Board.Kind.KING,
	Board.Kind.BISHOP,
	Board.Kind.KNIGHT,
	Board.Kind.ROOK,
]


func id() -> StringName:
	return &"chess"


func display_name() -> String:
	return "Xadrez"


func initial_state() -> MatchState:
	var state := MatchState.new()
	for file in Board.SIZE:
		state.set_piece(Board.square(file, 0), Board.piece(Board.Side.WHITE, BACK_RANK[file]))
		state.set_piece(Board.square(file, 1), Board.piece(Board.Side.WHITE, Board.Kind.PAWN))
		state.set_piece(Board.square(file, 6), Board.piece(Board.Side.BLACK, Board.Kind.PAWN))
		state.set_piece(Board.square(file, 7), Board.piece(Board.Side.BLACK, BACK_RANK[file]))
	state.side_to_move = Board.Side.WHITE
	state.meta = {"castle": CASTLE_ALL, "ep": Board.NO_SQUARE, "halfmove": 0}
	return state


## Um lance é legal quando não deixa o próprio rei em xeque, e descobrir isso
## exige jogá-lo. O caminho curto importa: esta função roda dezenas de milhares
## de vezes por lance do bot, e era ela que fazia a busca demorar.
##
## Duas economias, as duas por não fazer trabalho que ninguém lê. O tabuleiro de
## teste copia **só as casas** — `_is_attacked` não olha nada além delas, então
## clonar `meta` e o resto era copiar para descartar. E a casa do rei é
## localizada uma vez, e não uma varredura de 64 casas por lance candidato: o rei
## só muda de casa no lance que o move, e essa é a única exceção a tratar.
## Legalidade conferida só onde ela pode falhar.
##
## Um lance pseudo-legal só é ilegal se deixar o próprio rei atacado, e isso tem
## quatro causas possíveis: o rei é quem se move, o rei já está em xeque, a peça
## que se move está **pregada** contra ele, ou é uma captura en passant. Fora
## esses casos a linha entre o rei e qualquer atacante não muda, e o lance é legal
## sem ninguém conferir.
##
## Antes, cada lance pseudo-legal custava uma cópia do tabuleiro e um
## `_is_attacked` inteiro — umas 35 varreduras de raio por posição, para
## tipicamente não descartar nada. `generate_moves` é o nó da busca do bot, roda
## uma vez por posição visitada, e custava 0,65 ms: o nível Fácil não tinha tempo
## de pontuar **um** lance dentro do orçamento dele.
##
## O en passant fica na lista dos caros porque é o único lance que remove uma peça
## de uma casa em que ele não pousa — ele abre uma linha que nem o pino nem o
## destino denunciam. É exatamente o que a posição `final(4)` do perft cobre.
func generate_moves(state: MatchState) -> Array[Move]:
	var side := state.side_to_move
	var enemy := Board.opponent(side)
	var king_home := state.find_piece(side, Board.Kind.KING)
	var pseudo := _pseudo_moves(state)
	# Sem rei no tabuleiro nada pode ficar em xeque. São as posições armadas à mão
	# dos testes, e não uma partida.
	if king_home == Board.NO_SQUARE:
		return pseudo

	var legal: Array[Move] = []
	var in_check := _is_attacked(state, king_home, enemy)
	var pinned := _pinned_squares(state, king_home, side)
	var probe := MatchState.new()
	for move in pseudo:
		var from := move.from_square()
		if (
			not in_check and from != king_home
			and not pinned.has(from) and not _captures_off_square(move)
		):
			legal.append(move)
			continue
		probe.squares = state.squares.duplicate()
		_move_pieces(probe, move)
		var king := move.to_square() if from == king_home else king_home
		if not _is_attacked(probe, king, enemy):
			legal.append(move)
	return legal


## Verdadeiro no en passant, e só nele: a peça capturada não está na casa onde o
## lance pousa.
static func _captures_off_square(move: Move) -> bool:
	return not move.captured.is_empty() and move.captured[0] != move.to_square()


## Casas de peças próprias que estão entre o rei e um atacante de longo alcance.
##
## Uma varredura de oito raios a partir do rei, **uma vez por posição**, no lugar
## de uma varredura completa por lance. Mover uma dessas peças pode abrir a linha,
## então elas continuam passando pela conferência inteira — a lista é de
## suspeitas, não de culpadas.
func _pinned_squares(state: MatchState, king: int, side: int) -> PackedInt32Array:
	var pinned := PackedInt32Array()
	for dir in ROOK_DIRS:
		_scan_pin(state, king, side, dir, Board.Kind.ROOK, pinned)
	for dir in BISHOP_DIRS:
		_scan_pin(state, king, side, dir, Board.Kind.BISHOP, pinned)
	return pinned


## Anda um raio a partir do rei. A primeira peça própria vira candidata; se logo
## atrás dela vier um atacante do tipo que anda nesse raio — ou uma dama, que anda
## em todos —, ela está pregada. Duas peças próprias na mesma linha não pregam
## nada: tirar uma ainda deixa a outra tapando.
func _scan_pin(
	state: MatchState, king: int, side: int, dir: Array, kind: int, out: PackedInt32Array
) -> void:
	var f: int = Board.file_of(king) + dir[0]
	var r: int = Board.rank_of(king) + dir[1]
	var candidate := Board.NO_SQUARE
	while Board.in_bounds(f, r):
		var sq := Board.square(f, r)
		var piece := state.squares[sq]
		if piece != 0:
			if Board.side_of(piece) == side:
				if candidate != Board.NO_SQUARE:
					return
				candidate = sq
			else:
				var found := Board.kind_of(piece)
				if candidate != Board.NO_SQUARE and (found == kind or found == Board.Kind.QUEEN):
					out.append(candidate)
				return
		f += dir[0]
		r += dir[1]


func apply_move(state: MatchState, move: Move) -> void:
	_apply(state, move)
	state.history.append(move.to_dict())


func outcome(state: MatchState) -> Outcome:
	if generate_moves(state).is_empty():
		if is_in_check(state, state.side_to_move):
			return Outcome.BLACK_WINS if state.side_to_move == Board.Side.WHITE else Outcome.WHITE_WINS
		return Outcome.DRAW
	if int(state.meta.get("halfmove", 0)) >= 100:
		return Outcome.DRAW
	if _is_insufficient_material(state):
		return Outcome.DRAW
	return Outcome.ONGOING


func status_hint(state: MatchState) -> String:
	return "Xeque!" if is_in_check(state, state.side_to_move) else ""


# --- avaliação ---------------------------------------------------------------

## Valores clássicos, em centésimos de peão. O bispo vale um pouco mais que o
## cavalo porque num tabuleiro que abre ele alcança mais casas; a diferença é
## pequena de propósito, porque com o tabuleiro fechado ela se inverte.
##
## O rei vale zero: ele nunca sai do tabuleiro, então somá-lo dos dois lados só
## acrescentaria uma constante. O mate é decidido pela busca, não pelo material.
const PIECE_VALUE := {
	Board.Kind.PAWN: 100.0,
	Board.Kind.KNIGHT: 320.0,
	Board.Kind.BISHOP: 330.0,
	Board.Kind.ROOK: 500.0,
	Board.Kind.QUEEN: 900.0,
	Board.Kind.KING: 0.0,
}


## Quanto cada casa vale para cada peça, na visão das **brancas** e da primeira
## linha para a última. Para as pretas o índice é espelhado (`sq ^ 56` troca a
## linha e mantém a coluna), então uma tabela só serve aos dois lados.
##
## São as tabelas clássicas, e não são enfeite: sem elas todo avanço de peão vale
## exatamente o mesmo — o peão da torre e o do rei saem da segunda para a quarta
## linha ganhando a mesma coisa — e a busca desempata pela ordem da lista. O
## resultado era um bot que abria com h4 e mantinha os cavalos em casa. O termo
## posicional é de onde sai o desenvolvimento, sem nenhuma regra de abertura
## escrita em lugar nenhum.
const PAWN_SQUARES := [
	  0,   0,   0,   0,   0,   0,   0,   0,
	  5,  10,  10, -20, -20,  10,  10,   5,
	  5,  -5, -10,   0,   0, -10,  -5,   5,
	  0,   0,   0,  20,  20,   0,   0,   0,
	  5,   5,  10,  25,  25,  10,   5,   5,
	 10,  10,  20,  30,  30,  20,  10,  10,
	 50,  50,  50,  50,  50,  50,  50,  50,
	  0,   0,   0,   0,   0,   0,   0,   0,
]
const KNIGHT_SQUARES := [
	-50, -40, -30, -30, -30, -30, -40, -50,
	-40, -20,   0,   5,   5,   0, -20, -40,
	-30,   5,  10,  15,  15,  10,   5, -30,
	-30,   0,  15,  20,  20,  15,   0, -30,
	-30,   5,  15,  20,  20,  15,   5, -30,
	-30,   0,  10,  15,  15,  10,   0, -30,
	-40, -20,   0,   0,   0,   0, -20, -40,
	-50, -40, -30, -30, -30, -30, -40, -50,
]
const BISHOP_SQUARES := [
	-20, -10, -10, -10, -10, -10, -10, -20,
	-10,   5,   0,   0,   0,   0,   5, -10,
	-10,  10,  10,  10,  10,  10,  10, -10,
	-10,   0,  10,  10,  10,  10,   0, -10,
	-10,   5,   5,  10,  10,   5,   5, -10,
	-10,   0,   5,  10,  10,   5,   0, -10,
	-10,   0,   0,   0,   0,   0,   0, -10,
	-20, -10, -10, -10, -10, -10, -10, -20,
]
## Torre: colunas centrais valem um pouco mais, a sétima linha vale bastante, e
## a1 e h1 valem o mesmo que b1 e g1 — de propósito. Com um empurrão genérico
## para o centro, a torre ganhava meio ponto indo de a1 para b1 e voltava no
## lance seguinte; a partida de teste era `Tb1 … Ta1 … Tb1`, três lances jogados
## fora para o bot passear com a torre no lugar de desenvolver.
const ROOK_SQUARES := [
	  0,   0,   5,  10,  10,   5,   0,   0,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	  5,  10,  10,  10,  10,  10,  10,   5,
	  0,   0,   0,   0,   0,   0,   0,   0,
]
const QUEEN_SQUARES := [
	-20, -10, -10,  -5,  -5, -10, -10, -20,
	-10,   0,   5,   0,   0,   0,   0, -10,
	-10,   5,   5,   5,   5,   5,   0, -10,
	  0,   0,   5,   5,   5,   5,   0,  -5,
	 -5,   0,   5,   5,   5,   5,   0,  -5,
	-10,   0,   5,   5,   5,   5,   0, -10,
	-10,   0,   0,   0,   0,   0,   0, -10,
	-20, -10, -10,  -5,  -5, -10, -10, -20,
]
## O rei quer o canto enquanto há peças no tabuleiro, e g1/b1 valem mais que e1:
## é assim que o roque vira o lance certo sem ninguém ter escrito "roque".
const KING_SQUARES := [
	 20,  30,  10,   0,   0,  10,  30,  20,
	 20,  20,   0,   0,   0,   0,  20,  20,
	-10, -20, -20, -20, -20, -20, -20, -10,
	-20, -30, -30, -40, -40, -30, -30, -20,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
]


## Material mais a qualidade das casas ocupadas.
func evaluate(state: MatchState) -> float:
	var score := 0.0
	for sq in Board.SQUARE_COUNT:
		var piece := state.squares[sq]
		if piece == 0:
			continue
		var side := Board.side_of(piece)
		var kind := Board.kind_of(piece)
		# Espelhamento pelas pretas: mesma tabela, linha invertida.
		var seat := sq if side == Board.Side.WHITE else sq ^ 56
		var value: float = PIECE_VALUE[kind] + _placement(kind, seat)
		score += value if side == Board.Side.WHITE else -value
	return score


## O material que o lance tira do tabuleiro, mais o que a promoção acrescenta.
##
## Só o ganho **bruto**: a recaptura não entra, e é justamente por isso que serve
## de teto. Se nem ganhando isto de graça a posição alcança o que já se tem, não
## há por que buscar a sequência inteira.
func capture_gain(state: MatchState, move: Move) -> float:
	var gain := 0.0
	for square in move.captured:
		gain += float(PIECE_VALUE.get(Board.kind_of(state.squares[square]), 0.0))
	if move.promotion != Board.Kind.EMPTY:
		gain += float(PIECE_VALUE.get(move.promotion, 0.0)) - float(PIECE_VALUE[Board.Kind.PAWN])
	return gain


static func _placement(kind: int, sq: int) -> float:
	match kind:
		Board.Kind.PAWN:
			return PAWN_SQUARES[sq]
		Board.Kind.KNIGHT:
			return KNIGHT_SQUARES[sq]
		Board.Kind.BISHOP:
			return BISHOP_SQUARES[sq]
		Board.Kind.ROOK:
			return ROOK_SQUARES[sq]
		Board.Kind.QUEEN:
			return QUEEN_SQUARES[sq]
		Board.Kind.KING:
			return KING_SQUARES[sq]
	return 0.0


func promotion_options(state: MatchState, move_path: PackedInt32Array) -> Array[int]:
	var kinds: Array[int] = []
	for move in generate_moves(state):
		if move.path == move_path and move.promotion != Board.Kind.EMPTY:
			kinds.append(move.promotion)
	return kinds


func is_in_check(state: MatchState, side: int) -> bool:
	var king := state.find_piece(side, Board.Kind.KING)
	return king != Board.NO_SQUARE and _is_attacked(state, king, Board.opponent(side))


## `side` ainda consegue dar mate por alguma sequência legal?
##
## Existe para o relógio: pela norma, quem fica sem tempo só perde se o
## adversário tiver com que dar mate — rei sozinho, ou rei com um bispo ou um
## cavalo, não têm. Sem esta verificação um empate teórico viraria derrota
## inventada pelo cronômetro.
##
## Rei com dois cavalos é a exceção conhecida: o mate existe mas não pode ser
## forçado, e a norma o conta como material suficiente. Fica de fora daqui de
## propósito.
func has_mating_material(state: MatchState, side: int) -> bool:
	var minors := 0
	for sq in Board.SQUARE_COUNT:
		var piece := state.squares[sq]
		if piece == 0 or Board.side_of(piece) != side:
			continue
		match Board.kind_of(piece):
			Board.Kind.KING:
				continue
			Board.Kind.BISHOP, Board.Kind.KNIGHT:
				minors += 1
			_:
				return true
	return minors >= 2


# --- notação -----------------------------------------------------------------


## Letras em português, como o resto da interface: Rei, Dama, Torre, Bispo,
## Cavalo. Peão não tem letra em notação algébrica.
const NOTATION_LETTER := {
	Board.Kind.KING: "R",
	Board.Kind.QUEEN: "D",
	Board.Kind.ROOK: "T",
	Board.Kind.BISHOP: "B",
	Board.Kind.KNIGHT: "C",
}


## Notação algébrica abreviada (SAN) do lance na posição `state`.
##
## Custa duas gerações de lances — uma para desambiguar, outra para saber se o
## lance dá xeque ou mate. É uma vez por lance jogado, não por quadro; o preço é
## invisível e paga uma linha que o jogador consegue conferir.
func notation(state: MatchState, move: Move) -> String:
	if move.tags.has("castle"):
		var castle := "O-O" if move.tags["castle"] == "king" else "O-O-O"
		return castle + _check_suffix(state, move)

	var from := move.from_square()
	var to := move.to_square()
	var kind := Board.kind_of(state.squares[from])
	var text := ""

	if kind == Board.Kind.PAWN:
		# Peão só se identifica quando captura, e aí pela coluna de origem
		# ("exd5") — é o que distingue duas capturas para a mesma casa.
		if move.is_capture():
			text = "%sx" % _file_letter(from)
	else:
		text = NOTATION_LETTER[kind] + _disambiguation(state, move)
		if move.is_capture():
			text += "x"

	text += Board.square_name(to)
	if move.promotion != Board.Kind.EMPTY:
		text += "=" + NOTATION_LETTER[move.promotion]
	return text + _check_suffix(state, move)


## Só o suficiente para desfazer a ambiguidade, na ordem da norma: coluna,
## depois linha, depois a casa inteira. Escrever sempre a casa completa seria
## correto e ilegível.
func _disambiguation(state: MatchState, move: Move) -> String:
	var from := move.from_square()
	var to := move.to_square()
	var kind := Board.kind_of(state.squares[from])

	var same_file := false
	var same_rank := false
	var rivals := 0
	for other in generate_moves(state):
		var other_from := other.from_square()
		if other_from == from or other.to_square() != to:
			continue
		if Board.kind_of(state.squares[other_from]) != kind:
			continue
		rivals += 1
		if Board.file_of(other_from) == Board.file_of(from):
			same_file = true
		if Board.rank_of(other_from) == Board.rank_of(from):
			same_rank = true

	if rivals == 0:
		return ""
	if not same_file:
		return _file_letter(from)
	if not same_rank:
		return str(Board.rank_of(from) + 1)
	return Board.square_name(from)


func _check_suffix(state: MatchState, move: Move) -> String:
	var probe := state.clone()
	_apply(probe, move)
	if not is_in_check(probe, probe.side_to_move):
		return ""
	return "#" if generate_moves(probe).is_empty() else "+"


func _file_letter(sq: int) -> String:
	return char("a".unicode_at(0) + Board.file_of(sq))


# --- move generation ---------------------------------------------------------


func _pseudo_moves(state: MatchState) -> Array[Move]:
	var moves: Array[Move] = []
	var side := state.side_to_move
	for sq in Board.SQUARE_COUNT:
		var p := state.squares[sq]
		if p == 0 or Board.side_of(p) != side:
			continue
		match Board.kind_of(p):
			Board.Kind.PAWN:
				_add_pawn_moves(state, sq, side, moves)
			Board.Kind.KNIGHT:
				_add_step_moves(state, sq, side, KNIGHT_DIRS, moves)
			Board.Kind.KING:
				_add_step_moves(state, sq, side, KING_DIRS, moves)
			Board.Kind.BISHOP:
				_add_slide_moves(state, sq, side, BISHOP_DIRS, moves)
			Board.Kind.ROOK:
				_add_slide_moves(state, sq, side, ROOK_DIRS, moves)
			Board.Kind.QUEEN:
				_add_slide_moves(state, sq, side, QUEEN_DIRS, moves)
	_add_castling(state, side, moves)
	return moves


## Os dois laços abaixo leem `state.squares` direto e fazem a conta da casa à mão.
##
## É a única parte do arquivo escrita assim, e é de propósito: aqui rodam as
## dezenas de milhares de iterações por lance do bot, e cada `Board.in_bounds`,
## `Board.square`, `has_friend` e `is_occupied` é uma chamada de função do
## GDScript — que custa mais que a conta que ela faz. Eram seis chamadas por casa
## visitada; sobrou uma, e só quando a casa está ocupada.
##
## O resto do arquivo continua usando os auxiliares do `Board`. A troca só vale
## onde ela foi medida.
func _add_step_moves(state: MatchState, from: int, side: int, dirs: Array, out: Array[Move]) -> void:
	var size := Board.SIZE
	var squares := state.squares
	var file := from % size
	var rank := from / size
	for d in dirs:
		var f: int = file + d[0]
		var r: int = rank + d[1]
		if f < 0 or f >= size or r < 0 or r >= size:
			continue
		var to: int = r * size + f
		var piece: int = squares[to]
		if piece == 0:
			out.append(Move.simple(from, to))
		elif Board.side_of(piece) != side:
			out.append(_capture_move(from, to))


func _add_slide_moves(state: MatchState, from: int, side: int, dirs: Array, out: Array[Move]) -> void:
	var size := Board.SIZE
	var squares := state.squares
	var file := from % size
	var rank := from / size
	for d in dirs:
		var f: int = file + d[0]
		var r: int = rank + d[1]
		while f >= 0 and f < size and r >= 0 and r < size:
			var to: int = r * size + f
			var piece: int = squares[to]
			if piece != 0:
				# Peça própria fecha a linha sem lance; peça inimiga fecha com captura.
				if Board.side_of(piece) != side:
					out.append(_capture_move(from, to))
				break
			out.append(Move.simple(from, to))
			f += d[0]
			r += d[1]


static func _capture_move(from: int, to: int) -> Move:
	var move := Move.simple(from, to)
	move.captured = PackedInt32Array([to])
	return move


func _add_pawn_moves(state: MatchState, from: int, side: int, out: Array[Move]) -> void:
	var forward := 1 if side == Board.Side.WHITE else -1
	var start_rank := 1 if side == Board.Side.WHITE else 6
	var last_rank := 7 if side == Board.Side.WHITE else 0
	var file := Board.file_of(from)
	var rank := Board.rank_of(from)
	var ep_square := int(state.meta.get("ep", Board.NO_SQUARE))

	var one := Board.square(file, rank + forward)
	if Board.in_bounds(file, rank + forward) and not state.is_occupied(one):
		_push_pawn_move(Move.simple(from, one), last_rank, out)
		if rank == start_rank:
			var two := Board.square(file, rank + 2 * forward)
			if not state.is_occupied(two):
				var move := Move.simple(from, two)
				move.tags["double_push"] = true
				out.append(move)

	for df: int in [-1, 1]:
		var f := file + df
		var r := rank + forward
		if not Board.in_bounds(f, r):
			continue
		var to := Board.square(f, r)
		if state.has_enemy(to, side):
			var move := Move.simple(from, to)
			move.captured = PackedInt32Array([to])
			_push_pawn_move(move, last_rank, out)
		elif to == ep_square:
			var move := Move.simple(from, to)
			move.captured = PackedInt32Array([Board.square(f, rank)])
			move.tags["en_passant"] = true
			out.append(move)


func _push_pawn_move(move: Move, last_rank: int, out: Array[Move]) -> void:
	if Board.rank_of(move.to_square()) != last_rank:
		out.append(move)
		return
	for kind in PROMOTION_KINDS:
		var promo := Move.new()
		promo.path = move.path.duplicate()
		promo.captured = move.captured.duplicate()
		promo.promotion = kind
		out.append(promo)


func _add_castling(state: MatchState, side: int, out: Array[Move]) -> void:
	var rights := int(state.meta.get("castle", 0))
	var enemy := Board.opponent(side)
	var home := 0 if side == Board.Side.WHITE else 56
	var king_sq := home + 4
	if state.squares[king_sq] != Board.piece(side, Board.Kind.KING):
		return
	if _is_attacked(state, king_sq, enemy):
		return

	var king_side := CASTLE_WK if side == Board.Side.WHITE else CASTLE_BK
	if rights & king_side and state.squares[home + 7] == Board.piece(side, Board.Kind.ROOK):
		if not state.is_occupied(home + 5) and not state.is_occupied(home + 6):
			if not _is_attacked(state, home + 5, enemy) and not _is_attacked(state, home + 6, enemy):
				var move := Move.simple(king_sq, home + 6)
				move.tags["castle"] = "king"
				out.append(move)

	var queen_side := CASTLE_WQ if side == Board.Side.WHITE else CASTLE_BQ
	if rights & queen_side and state.squares[home] == Board.piece(side, Board.Kind.ROOK):
		var empty := not state.is_occupied(home + 1) and not state.is_occupied(home + 2) and not state.is_occupied(home + 3)
		if empty and not _is_attacked(state, home + 3, enemy) and not _is_attacked(state, home + 2, enemy):
			var move := Move.simple(king_sq, home + 2)
			move.tags["castle"] = "queen"
			out.append(move)


func _is_attacked(state: MatchState, sq: int, by_side: int) -> bool:
	var file := Board.file_of(sq)
	var rank := Board.rank_of(sq)

	# Pawns attack "forward" from their own point of view, so we look backward.
	var pawn_rank := rank - (1 if by_side == Board.Side.WHITE else -1)
	var enemy_pawn := Board.piece(by_side, Board.Kind.PAWN)
	for df in [-1, 1]:
		if Board.in_bounds(file + df, pawn_rank) and state.squares[Board.square(file + df, pawn_rank)] == enemy_pawn:
			return true

	if _has_stepper(state, file, rank, KNIGHT_DIRS, Board.piece(by_side, Board.Kind.KNIGHT)):
		return true
	if _has_stepper(state, file, rank, KING_DIRS, Board.piece(by_side, Board.Kind.KING)):
		return true
	if _has_slider(state, file, rank, ROOK_DIRS, by_side, Board.Kind.ROOK):
		return true
	if _has_slider(state, file, rank, BISHOP_DIRS, by_side, Board.Kind.BISHOP):
		return true
	return false


func _has_stepper(state: MatchState, file: int, rank: int, dirs: Array, wanted: int) -> bool:
	for d in dirs:
		var f: int = file + d[0]
		var r: int = rank + d[1]
		if Board.in_bounds(f, r) and state.squares[Board.square(f, r)] == wanted:
			return true
	return false


func _has_slider(state: MatchState, file: int, rank: int, dirs: Array, by_side: int, kind: int) -> bool:
	for d in dirs:
		var f: int = file + d[0]
		var r: int = rank + d[1]
		while Board.in_bounds(f, r):
			var p := state.squares[Board.square(f, r)]
			if p != 0:
				if Board.side_of(p) == by_side:
					var k := Board.kind_of(p)
					if k == kind or k == Board.Kind.QUEEN:
						return true
				break
			f += d[0]
			r += d[1]
	return false


# --- application -------------------------------------------------------------


## Só o tabuleiro: peças que saem, peça que chega, promoção e a torre do roque.
## Separado de `_apply` porque o teste de legalidade precisa exatamente disto e
## de mais nada — os direitos de roque e o contador dos 50 lances não mudam quem
## ataca o quê.
func _move_pieces(state: MatchState, move: Move) -> void:
	var from := move.from_square()
	var to := move.to_square()
	var moved := state.squares[from]

	for sq in move.captured:
		state.squares[sq] = 0
	state.squares[from] = 0
	state.squares[to] = moved
	if move.promotion != Board.Kind.EMPTY:
		state.squares[to] = Board.piece(Board.side_of(moved), move.promotion)

	if move.tags.has("castle"):
		var home := 0 if Board.side_of(moved) == Board.Side.WHITE else 56
		if move.tags["castle"] == "king":
			state.squares[home + 7] = 0
			state.squares[home + 5] = Board.piece(Board.side_of(moved), Board.Kind.ROOK)
		else:
			state.squares[home] = 0
			state.squares[home + 3] = Board.piece(Board.side_of(moved), Board.Kind.ROOK)


func _apply(state: MatchState, move: Move) -> void:
	var from := move.from_square()
	var to := move.to_square()
	var moved := state.squares[from]
	var side := Board.side_of(moved)
	var kind := Board.kind_of(moved)
	var halfmove := int(state.meta.get("halfmove", 0)) + 1
	if kind == Board.Kind.PAWN or move.is_capture():
		halfmove = 0

	_move_pieces(state, move)

	state.meta["castle"] = _rights_after(int(state.meta.get("castle", 0)), from, to)
	state.meta["ep"] = Board.square(Board.file_of(from), (Board.rank_of(from) + Board.rank_of(to)) / 2) if move.tags.has("double_push") else Board.NO_SQUARE
	state.meta["halfmove"] = halfmove
	state.side_to_move = Board.opponent(side)
	state.ply += 1


## Any king or rook leaving its home square — or any rook home square being
## captured on — kills the matching right.
func _rights_after(rights: int, from: int, to: int) -> int:
	for sq in [from, to]:
		match sq:
			4:
				rights &= ~(CASTLE_WK | CASTLE_WQ)
			60:
				rights &= ~(CASTLE_BK | CASTLE_BQ)
			0:
				rights &= ~CASTLE_WQ
			7:
				rights &= ~CASTLE_WK
			56:
				rights &= ~CASTLE_BQ
			63:
				rights &= ~CASTLE_BK
	return rights


func _is_insufficient_material(state: MatchState) -> bool:
	var minors := 0
	for sq in Board.SQUARE_COUNT:
		var p := state.squares[sq]
		if p == 0:
			continue
		match Board.kind_of(p):
			Board.Kind.KING:
				continue
			Board.Kind.BISHOP, Board.Kind.KNIGHT:
				minors += 1
			_:
				return false
	return minors <= 1
