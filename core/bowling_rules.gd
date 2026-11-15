class_name BowlingRules
extends Ruleset

## Boliche de dez pinos: dez frames, strike, spare e o décimo frame com as bolas
## extras, de um a quatro jogadores.
##
## ## O lance é o resultado, e a física fica de fora
##
## Na sinuca a física mora em `core/` porque ela é determinística e os dois
## aparelhos chegam à mesma mesa. Aqui os pinos caem pela física 3D da Godot
## (Jolt), que **não** dá o mesmo resultado bit a bit em dois aparelhos. Então o
## lance carrega o que aconteceu — a máscara dos pinos derrubados — e as regras só
## contam. Quem arremessou é quem diz quais pinos caíram; o outro aparelho repete
## a física para ver a jogada, mas vale a máscara. É a única porta do app que
## confia no resultado de quem jogou, e ela é aberta só aqui.
##
## Os parâmetros do arremesso viajam junto (posição, direção, efeito e timing),
## para quem assiste ver a mesma bola. As regras só conferem que estão na faixa.
##
## ## A vez é de frame, não de bola
##
## Cada jogador joga o frame inteiro (uma, duas ou três bolas) e passa a vez. A
## partida acaba quando o último assento fecha o décimo frame.

const MIN_SEATS := 1
const MAX_SEATS := 4
const FRAMES := 10
const PINS := 10
const ALL_PINS := (1 << PINS) - 1

## `path = [ROLL, máscara, posição, direção, efeito, timing, força]`. A máscara tem
## um bit por pino (bit 0 = pino 1). Os cinco parâmetros vão em milésimos, de -1000
## a 1000 (a força de 0 a 1000); o que cada um significa é da física
## (`ui/bowling_lane.gd`). A força entrou na 1.48; o boliche ainda não joga em
## rede, então não há lance de 6 casas guardado em lugar nenhum para aceitar.
const ROLL := 0
const KIND_AT := 0
const MASK_AT := 1
const PARAMS_AT := 2
const PARAM_COUNT := 5
const PATH_SIZE := PARAMS_AT + PARAM_COUNT
const PARAM_SCALE := 1000

# --- chaves de `meta` ---------------------------------------------------------

const SEATS := "st"
const TURN := "tn"
## Pinos em pé agora, um bit por pino.
const STANDING := "sd"
## Bolas de cada assento, em pinos derrubados: `"r0"`, `"r1"`... Uma chave por
## assento porque `meta` não aceita vetor dentro de vetor (ver `MatchState.clone`).
const ROLLS := "r"

## Lido uma vez em `initial_state()`, como em Uno e Metrópole.
var seats := 2


func id() -> StringName:
	return &"bowling"


func display_name() -> String:
	return "Boliche"


func players() -> int:
	return clampi(seats, MIN_SEATS, MAX_SEATS)


func initial_state() -> MatchState:
	var state := MatchState.new()
	var count := players()
	state.meta[SEATS] = count
	state.meta[TURN] = 0
	state.meta[STANDING] = ALL_PINS
	for seat in count:
		state.meta[ROLLS + str(seat)] = PackedInt32Array()
	return state


# --- leitura do estado --------------------------------------------------------


static func seats_of(state: MatchState) -> int:
	return int(state.meta.get(SEATS, 1))


static func turn_of(state: MatchState) -> int:
	return int(state.meta.get(TURN, 0))


static func standing(state: MatchState) -> int:
	return int(state.meta.get(STANDING, ALL_PINS))


static func rolls_of(state: MatchState, seat: int) -> PackedInt32Array:
	return state.meta.get(ROLLS + str(seat), PackedInt32Array())


static func pin_count(mask: int) -> int:
	var count := 0
	for pin in PINS:
		count += (mask >> pin) & 1
	return count


## Onde as bolas de um jogador estão: `{"frame": 0..10, "ball": 0..2}`. Frame 10
## é "acabou".
static func position(rolls: PackedInt32Array) -> Dictionary:
	var at := 0
	for frame in FRAMES - 1:
		if at >= rolls.size():
			return {"frame": frame, "ball": 0}
		if rolls[at] == PINS:
			at += 1
		elif at + 1 >= rolls.size():
			return {"frame": frame, "ball": 1}
		else:
			at += 2
	var last := rolls.slice(at)
	if last.size() < 2:
		return {"frame": FRAMES - 1, "ball": last.size()}
	var bonus := last[0] == PINS or last[0] + last[1] == PINS
	if last.size() == 2 and bonus:
		return {"frame": FRAMES - 1, "ball": 2}
	return {"frame": FRAMES, "ball": 0}


static func finished(rolls: PackedInt32Array) -> bool:
	return int(position(rolls)["frame"]) >= FRAMES


static func game_over(state: MatchState) -> bool:
	for seat in seats_of(state):
		if not finished(rolls_of(state, seat)):
			return false
	return true


## Pontos por frame, acumulados, com -1 no frame que ainda espera bola (o bônus de
## um strike ou spare, ou o frame não jogado).
static func totals(rolls: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var at := 0
	var sum := 0
	var known := true
	for frame in FRAMES:
		# Strike gasta uma bola e soma as duas seguintes; spare soma a seguinte;
		# aberto soma só as duas dele. No décimo as "seguintes" são as extras.
		var take := 2
		var span := 2
		if at < rolls.size() and rolls[at] == PINS:
			take = 1
			span = 3
		elif at + 1 < rolls.size() and rolls[at] + rolls[at + 1] == PINS:
			span = 3
		known = known and at + span <= rolls.size()
		if known:
			for i in span:
				sum += rolls[at + i]
		out.append(sum if known else -1)
		at += take
	return out


## Placar até onde se sabe: o último frame resolvido.
static func score_of(state: MatchState, seat: int) -> int:
	var best := 0
	for total in totals(rolls_of(state, seat)):
		if total >= 0:
			best = total
	return best


## As marcas de cada frame, como na cartela: `X` strike, `/` spare, `-` zero.
static func marks(rolls: PackedInt32Array) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var at := 0
	for frame in FRAMES:
		var cells := PackedStringArray()
		if frame < FRAMES - 1:
			if at < rolls.size() and rolls[at] == PINS:
				cells.append("X")
				at += 1
			else:
				for ball in 2:
					if at >= rolls.size():
						break
					var spare := ball == 1 and rolls[at - 1] + rolls[at] == PINS
					cells.append("/" if spare else _digit(rolls[at]))
					at += 1
		else:
			# No décimo cada bola é marcada contra os pinos que ela tinha à frente.
			var fresh := true
			var previous := 0
			while at < rolls.size():
				var pins := rolls[at]
				if fresh and pins == PINS:
					cells.append("X")
				elif not fresh and previous + pins == PINS:
					cells.append("/")
				else:
					cells.append(_digit(pins))
				fresh = (fresh and pins == PINS) or (not fresh and previous + pins == PINS)
				previous = 0 if fresh else pins
				at += 1
		out.append(cells)
	return out


static func _digit(pins: int) -> String:
	return "-" if pins == 0 else str(pins)


## Lance a partir da máscara e dos parâmetros (cada um de -1 a 1). Os que faltam
## vão como zero.
static func roll(mask: int, params := PackedFloat32Array()) -> Move:
	var move := Move.new()
	move.path = PackedInt32Array([ROLL, mask])
	for i in PARAM_COUNT:
		var value := params[i] if i < params.size() else 0.0
		move.path.append(int(roundf(clampf(value, -1.0, 1.0) * PARAM_SCALE)))
	return move


static func mask_of(move: Move) -> int:
	return move.path[MASK_AT]


static func params_of(move: Move) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in range(PARAMS_AT, PATH_SIZE):
		out.append(float(move.path[i]) / PARAM_SCALE)
	return out


## A porta de todo lance — local, de bot ou de rede. Como na sinuca, não existe a
## lista de lances legais: confere-se por predicado.
func validate(state: MatchState, path: PackedInt32Array) -> Move:
	if path.size() != PATH_SIZE or path[KIND_AT] != ROLL or game_over(state):
		return null
	var mask := path[MASK_AT]
	if mask < 0 or mask & ~standing(state) != 0:
		return null
	for i in range(PARAMS_AT, PATH_SIZE):
		if absi(path[i]) > PARAM_SCALE:
			return null
	var move := Move.new()
	move.path = path.duplicate()
	return move


func apply_move(state: MatchState, move: Move) -> void:
	var seat := turn_of(state)
	var key := ROLLS + str(seat)
	var rolls: PackedInt32Array = state.meta[key]
	var before := position(rolls)
	var knocked := pin_count(mask_of(move))
	rolls.append(knocked)
	state.meta[key] = rolls

	var after := position(rolls)
	var left := standing(state) & ~mask_of(move)
	if int(after["frame"]) != int(before["frame"]):
		# Frame fechado: a vez passa e a máquina arma os dez.
		left = ALL_PINS
		state.meta[TURN] = (seat + 1) % seats_of(state)
	elif left == 0:
		# Strike ou spare no décimo: a bola extra é contra os dez de novo.
		left = ALL_PINS
	state.meta[STANDING] = left
	state.ply += 1
	state.history.append(move.to_dict())


# --- fim de partida -----------------------------------------------------------


## Quem venceu, -2 para empate no topo, ou -1 com a partida em curso.
static func winner_of(state: MatchState) -> int:
	if not game_over(state):
		return -1
	var best := -1
	var champion := -1
	for seat in seats_of(state):
		var score := score_of(state, seat)
		if score > best:
			best = score
			champion = seat
		elif score == best:
			champion = -2
	return champion


func outcome(state: MatchState) -> Outcome:
	var champion := winner_of(state)
	if champion == -1:
		return Outcome.ONGOING
	if champion == -2:
		return Outcome.DRAW
	return Outcome.WHITE_WINS if champion == 0 else Outcome.BLACK_WINS


## Frames que a mesa inteira já fechou: os do último assento.
func rounds_played(state: MatchState) -> int:
	return mini(FRAMES, int(position(rolls_of(state, seats_of(state) - 1))["frame"]))


func status_hint(state: MatchState) -> String:
	if game_over(state):
		return ""
	var at := position(rolls_of(state, turn_of(state)))
	var frame := int(at["frame"]) + 1
	var ball := int(at["ball"]) + 1
	return "Frame %d, %dª bola." % [frame, ball]


func notation(state: MatchState, move: Move) -> String:
	var knocked := pin_count(mask_of(move))
	var fresh := standing(state) == ALL_PINS
	if knocked == PINS and fresh:
		return "%d: strike" % (turn_of(state) + 1)
	if mask_of(move) == standing(state) and not fresh:
		return "%d: spare" % (turn_of(state) + 1)
	return "%d: %d" % [turn_of(state) + 1, knocked]
