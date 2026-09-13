class_name MatchState
extends RefCounted

## Full position of a game in progress. `meta` carries the ruleset specific
## bookkeeping (castling rights and en passant for chess, the draw counter for
## checkers) so both rulesets can share the same state object.

var squares := Board.empty_squares()
var side_to_move := Board.Side.WHITE
var meta := {}
var ply := 0
## Move list in wire format, enough to replay or review the game.
var history: Array[Dictionary] = []


## Cópia independente da posição, sem o histórico — quem clona quer explorar uma
## variante, não reescrever a partida.
##
## `meta` é copiado raso **mais** uma duplicação dos vetores empacotados que
## estiverem dentro dele. Os dois passos são necessários e nenhum é sobra:
##
## - raso porque a cópia profunda genérica percorria a estrutura inteira a cada
##   nó da busca do bot e era, sozinha, uma das partes mais caras dela;
## - os `Packed*Array` porque o raso **não** os isola. Isso contraria a intuição:
##   eles são cópia-na-escrita, e por isso `var v := meta[K]; v[i] = x` de fato
##   copia antes de escrever. Mas `meta[K][i] = x` escreve direto no vetor
##   guardado no dicionário, que a cópia rasa deixou compartilhado — e aí a
##   variante que o bot explorou vaza para a partida de verdade. Silenciosamente:
##   nada falha, só a posição fica errada.
##
## Era convenção ("todo mundo que escreve reatribui") e virou estrutura, porque
## uma convenção que só quebra na busca do bot quebra sem deixar rastro. O custo
## é um `typeof` por chave nos jogos que não usam vetor nenhum em `meta`, que é
## nenhum custo.
##
## O que continua proibido em `meta` é `Array` e `Dictionary` aninhados: isolar
## aqueles é a cópia profunda que foi removida de propósito.
func clone() -> MatchState:
	var copy := MatchState.new()
	copy.squares = squares.duplicate()
	copy.side_to_move = side_to_move
	copy.meta = meta.duplicate()
	for key in copy.meta:
		# Os tipos empacotados são os últimos do enum, então uma comparação só
		# cobre os nove sem listá-los.
		if typeof(copy.meta[key]) >= TYPE_PACKED_BYTE_ARRAY:
			copy.meta[key] = copy.meta[key].duplicate()
	copy.ply = ply
	return copy


func piece_at(sq: int) -> int:
	return squares[sq]


func set_piece(sq: int, p: int) -> void:
	squares[sq] = p


func is_occupied(sq: int) -> bool:
	return squares[sq] != 0


func has_enemy(sq: int, side: int) -> bool:
	var p := squares[sq]
	return p != 0 and Board.side_of(p) != side


func has_friend(sq: int, side: int) -> bool:
	var p := squares[sq]
	return p != 0 and Board.side_of(p) == side


func find_piece(side: int, kind: int) -> int:
	var wanted := Board.piece(side, kind)
	for sq in Board.SQUARE_COUNT:
		if squares[sq] == wanted:
			return sq
	return Board.NO_SQUARE


func count_pieces(side: int) -> int:
	var total := 0
	for sq in Board.SQUARE_COUNT:
		var p := squares[sq]
		if p != 0 and Board.side_of(p) == side:
			total += 1
	return total
