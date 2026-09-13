class_name Move
extends RefCounted

## One legal move for either ruleset.
##
## `path` holds every square the piece lands on: `[from, to]` for chess and for
## a simple checkers move, `[from, land1, land2, ...]` for a capture sequence.
## `captured` holds the squares of the pieces removed by the move (chess uses it
## for en passant too, where the captured square is not the destination).

var path := PackedInt32Array()
var captured := PackedInt32Array()
var promotion := Board.Kind.EMPTY
## Ruleset specific extras (castling side, double pawn push, ...).
var tags := {}


static func simple(from: int, to: int) -> Move:
	var move := Move.new()
	move.path = PackedInt32Array([from, to])
	return move


func from_square() -> int:
	return path[0]


func to_square() -> int:
	return path[path.size() - 1]


func is_capture() -> bool:
	return not captured.is_empty()


## True when `prefix` is the beginning of this move's path. Used by the board UI
## to filter candidate moves while the player taps a multi-jump sequence.
func starts_with(prefix: PackedInt32Array) -> bool:
	if prefix.size() > path.size():
		return false
	for i in prefix.size():
		if path[i] != prefix[i]:
			return false
	return true


func same_as(other: Move) -> bool:
	return path == other.path and promotion == other.promotion


## Wire format. Kept minimal because it travels through the local link on every
## move; the receiver validates it against its own move generation anyway.
func to_dict() -> Dictionary:
	return {"p": path, "pr": promotion}


static func from_dict(data: Dictionary) -> Move:
	var move := Move.new()
	move.path = PackedInt32Array(data.get("p", []))
	move.promotion = int(data.get("pr", Board.Kind.EMPTY))
	return move


func _to_string() -> String:
	var parts := PackedStringArray()
	for sq in path:
		parts.append(Board.square_name(sq))
	return "-".join(parts)
