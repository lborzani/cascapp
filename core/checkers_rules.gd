class_name CheckersRules
extends Ruleset

## Damas brasileiras (8x8): men capture forwards and backwards, dames fly.
## Captured pieces stay on the board until the sequence ends, so the same piece
## can never be jumped twice ("regra turca").
##
## Capturing is **optional** here, unlike tournament rules. The obligation (and
## the "lei da maioria" that forces the longest sequence) made the board feel
## broken in practice: tapping a piece that could move but was not the one
## holding the required capture simply did nothing, with no way for the UI to
## explain why. A started sequence still has to be finished — you pick a jump
## route, not a jump count.

const DIAGONALS := [[1, 1], [1, -1], [-1, 1], [-1, -1]]
## Plies of dame-only, capture-free shuffling before the game is called a draw.
const IDLE_DRAW_LIMIT := 40


func id() -> StringName:
	return &"checkers"


func display_name() -> String:
	return "Damas"


func square_is_playable(sq: int) -> bool:
	return (Board.file_of(sq) + Board.rank_of(sq)) % 2 == 0


func initial_state() -> MatchState:
	var state := MatchState.new()
	for sq in Board.SQUARE_COUNT:
		if not square_is_playable(sq):
			continue
		var rank := Board.rank_of(sq)
		if rank <= 2:
			state.set_piece(sq, Board.piece(Board.Side.WHITE, Board.Kind.MAN))
		elif rank >= 5:
			state.set_piece(sq, Board.piece(Board.Side.BLACK, Board.Kind.MAN))
	state.side_to_move = Board.Side.WHITE
	state.meta = {"idle": 0}
	return state


func generate_moves(state: MatchState) -> Array[Move]:
	var moves := _quiet_moves(state)
	moves.append_array(_capture_moves(state))
	return moves


func apply_move(state: MatchState, move: Move) -> void:
	var from := move.from_square()
	var to := move.to_square()
	var moved := state.squares[from]
	var side := Board.side_of(moved)

	state.squares[from] = 0
	for sq in move.captured:
		state.squares[sq] = 0
	state.squares[to] = moved
	if move.promotion != Board.Kind.EMPTY:
		state.squares[to] = Board.piece(side, move.promotion)

	var quiet_dame_move := move.captured.is_empty() and Board.kind_of(moved) == Board.Kind.DAME
	state.meta["idle"] = int(state.meta.get("idle", 0)) + 1 if quiet_dame_move else 0
	state.side_to_move = Board.opponent(side)
	state.ply += 1
	state.history.append(move.to_dict())


func outcome(state: MatchState) -> Outcome:
	if state.count_pieces(state.side_to_move) == 0 or generate_moves(state).is_empty():
		return Outcome.BLACK_WINS if state.side_to_move == Board.Side.WHITE else Outcome.WHITE_WINS
	if int(state.meta.get("idle", 0)) >= IDLE_DRAW_LIMIT:
		return Outcome.DRAW
	return Outcome.ONGOING


# --- avaliação ---------------------------------------------------------------

const MAN_VALUE := 100.0
## A dama voa: ela alcança a diagonal inteira e come de longe. Três pedras é a
## conta usual nas damas brasileiras, e é bem mais que a dama de outras
## variantes, onde ela anda uma casa só.
const DAME_VALUE := 320.0
## Pedra na borda não pode ser capturada — não existe casa do outro lado para o
## saltador cair. É vantagem posicional de graça, e barata de contar.
const EDGE_BONUS := 8.0


## Material, avanço e borda.
##
## O avanço vale bastante porque em damas virar dama é a partida inteira: uma
## pedra na sexta linha não é uma pedra, é uma dama atrasada dois lances. Sem
## esse termo o bot empurra pedras ao acaso até tropeçar numa promoção.
func evaluate(state: MatchState) -> float:
	var score := 0.0
	for sq in Board.SQUARE_COUNT:
		var piece := state.squares[sq]
		if piece == 0:
			continue
		var side := Board.side_of(piece)
		var value := DAME_VALUE
		if Board.kind_of(piece) == Board.Kind.MAN:
			var advance := Board.rank_of(sq) if side == Board.Side.WHITE else 7 - Board.rank_of(sq)
			value = MAN_VALUE + advance * advance * 3.0
		var file := Board.file_of(sq)
		if file == 0 or file == Board.SIZE - 1:
			value += EDGE_BONUS
		score += value if side == Board.Side.WHITE else -value
	return score


## Casas em coordenada algébrica, ligadas por `-` num lance simples e por `x` em
## cada salto de uma captura: `c3-d4`, `c3xe5xg7`.
##
## A notação tradicional de damas numera as 32 casas escuras de 1 a 32, mas o
## ponto de partida da numeração muda entre federações — e um número lido no
## sentido errado é indistinguível de um certo. A coordenada não tem essa
## ambiguidade, e é a mesma que o xadrez usa na tela ao lado.
func notation(_state: MatchState, move: Move) -> String:
	var squares := PackedStringArray()
	for sq in move.path:
		squares.append(Board.square_name(sq))
	var text := ("x" if move.is_capture() else "-").join(squares)
	if move.promotion != Board.Kind.EMPTY:
		text += "=D"
	return text


# --- move generation ---------------------------------------------------------


func _quiet_moves(state: MatchState) -> Array[Move]:
	var moves: Array[Move] = []
	var side := state.side_to_move
	var forward := 1 if side == Board.Side.WHITE else -1
	for from in Board.SQUARE_COUNT:
		var p := state.squares[from]
		if p == 0 or Board.side_of(p) != side:
			continue
		var file := Board.file_of(from)
		var rank := Board.rank_of(from)
		if Board.kind_of(p) == Board.Kind.MAN:
			for df: int in [-1, 1]:
				var f := file + df
				var r := rank + forward
				if Board.in_bounds(f, r) and not state.is_occupied(Board.square(f, r)):
					moves.append(_finish_move(Move.simple(from, Board.square(f, r)), p, side))
		else:
			for d in DIAGONALS:
				var f: int = file + d[0]
				var r: int = rank + d[1]
				while Board.in_bounds(f, r) and not state.is_occupied(Board.square(f, r)):
					moves.append(Move.simple(from, Board.square(f, r)))
					f += d[0]
					r += d[1]
	return moves


func _capture_moves(state: MatchState) -> Array[Move]:
	var moves: Array[Move] = []
	var side := state.side_to_move
	for from in Board.SQUARE_COUNT:
		var p := state.squares[from]
		if p == 0 or Board.side_of(p) != side:
			continue
		# The moving piece is lifted so it never blocks its own landing squares.
		var working := state.squares.duplicate()
		working[from] = 0
		_extend_capture(working, from, p, PackedInt32Array([from]), PackedInt32Array(), moves)
	return moves


## Depth-first walk over every capture continuation. Emits a Move whenever no
## further jump is available from the current square.
func _extend_capture(
	working: PackedInt32Array,
	current: int,
	p: int,
	path: PackedInt32Array,
	captured: PackedInt32Array,
	out: Array[Move]
) -> void:
	var side := Board.side_of(p)
	var is_dame := Board.kind_of(p) == Board.Kind.DAME
	var extended := false

	for d in DIAGONALS:
		var victim := _find_victim(working, current, d, side, captured, is_dame)
		if victim == Board.NO_SQUARE:
			continue
		var f: int = Board.file_of(victim) + d[0]
		var r: int = Board.rank_of(victim) + d[1]
		while Board.in_bounds(f, r) and working[Board.square(f, r)] == 0:
			var land := Board.square(f, r)
			var next_path := path.duplicate()
			next_path.append(land)
			var next_captured := captured.duplicate()
			next_captured.append(victim)
			extended = true
			_extend_capture(working, land, p, next_path, next_captured, out)
			if not is_dame:
				break
			f += d[0]
			r += d[1]

	if not extended and not captured.is_empty():
		var move := Move.new()
		move.path = path
		move.captured = captured
		out.append(_finish_move(move, p, side))


## First enemy piece along `d` that has not been captured yet. Anything else on
## the way (a friend, or a piece already captured this turn) blocks the ray.
func _find_victim(
	working: PackedInt32Array,
	from: int,
	d: Array,
	side: int,
	captured: PackedInt32Array,
	is_dame: bool
) -> int:
	var f: int = Board.file_of(from) + d[0]
	var r: int = Board.rank_of(from) + d[1]
	while Board.in_bounds(f, r):
		var sq := Board.square(f, r)
		var p := working[sq]
		if p != 0:
			if Board.side_of(p) == side or captured.has(sq):
				return Board.NO_SQUARE
			return sq
		if not is_dame:
			return Board.NO_SQUARE
		f += d[0]
		r += d[1]
	return Board.NO_SQUARE


## A man that *ends* its move on the far rank is promoted; one that merely
## passes through mid-sequence is not.
func _finish_move(move: Move, p: int, side: int) -> Move:
	if Board.kind_of(p) != Board.Kind.MAN:
		return move
	var last_rank := 7 if side == Board.Side.WHITE else 0
	if Board.rank_of(move.to_square()) == last_rank:
		move.promotion = Board.Kind.DAME
	return move
