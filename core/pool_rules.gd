class_name PoolRules
extends Ruleset

## Sinuca de mesa de bar, em dois formatos, com a física dentro das regras.
##
## É o jogo mais diferente do catálogo, e a diferença tem um nome: aqui o lance
## não **é** o resultado, ele é a **causa** dele. No xadrez "e2-e4" já descreve a
## posição seguinte; aqui uma tacada é uma bola, uma direção e uma força, e o que
## acontece com as outras depois disso sai de uma simulação.
##
## ## Os dois formatos, e eles discordam no que é uma tacadeira
##
## - **Mata-mata**, o jogo de bar de São Paulo: cinco bolas de cada cor e
##   **nenhuma branca**. Quem joga escolhe uma das **próprias** bolas e taca com
##   ela; ganha quem primeiro deixar o adversário sem bola na mesa. Encaçapar uma
##   sua é um tiro no pé literal — ela sai do jogo e aproxima o outro da vitória;
## - **Brasileira**, a regra nacional: a branca e sete coloridas de 1 a 7. Taca-se
##   sempre com a branca, e a **bola da vez** é a de menor número ainda na mesa.
##
## A diferença atravessa o arquivo inteiro, e é por isso que ela tem um nome:
## [method has_cue_ball]. Com tacadeira, a bola que taca é sempre a mesma, nunca
## sai do jogo e volta para a marca quando cai; sem ela, a bola que taca é uma
## escolha do jogador, é do grupo dele, e cair é perdê-la.
##
## ## Por que a simulação mora em `core/`
##
## Porque ela é a regra. Se ela morasse na tela, o aparelho do adversário
## receberia "taquei para lá com essa força" e teria de acreditar no resultado que
## viesse junto — e um resultado que viaja é um resultado que pode ser inventado.
## Com a física aqui, os dois aparelhos rodam a **mesma** tacada e chegam à mesma
## mesa, e repetir o histórico reconstrói a partida como em todos os outros jogos.
##
## ## O que torna isso possível: a tacada é um par de inteiros
##
## Um lance carrega a bola e a velocidade inicial dela em **milésimos de unidade
## por segundo**, dois inteiros. Não carrega ângulo.
##
## A diferença não é de gosto. Ângulo obrigaria os dois lados a chamar `cos` e
## `sin`, e essas duas — ao contrário de `+`, `-`, `*`, `/` e `sqrt`, que a
## IEEE-754 obriga a arredondar corretamente — **não** têm resultado garantido
## bit a bit entre plataformas: a libm de um ARM pode devolver um último bit
## diferente da de um x86. Um bit de diferença na direção vira um centímetro
## depois da terceira tabela, e um centímetro é a bola entrando ou não entrando.
##
## Então quem mira converte ângulo em vetor **uma vez**, no aparelho de quem está
## jogando, e o que viaja é o vetor já quantizado. Daí para frente a simulação usa
## só as cinco operações exatas, e as duas mesas são a mesma mesa.
##
## Pelo mesmo motivo não há efeito (nem "inglês"): ele pediria rotação, atrito
## lateral e uma integração bem mais sensível a erro — e a primeira coisa a
## quebrar seria justamente a igualdade entre os dois aparelhos.
##
## ## E não há acaso nenhum
##
## É o único jogo do app sem sorteio: o tabuleiro inicial é fixo, a física é
## determinística, e a única entrada é a tacada. Não há semente para combinar nem
## carta para sortear — o `welcome` leva o formato e mais nada.

# --- a mesa -------------------------------------------------------------------

## Pano em unidades de mundo, com a origem no canto de cima à esquerda. Duas por
## uma é a proporção da mesa de bar, e é o que sobra da tela deitada depois da
## coluna de jogadores.
const TABLE_WIDTH := 2.0
const TABLE_HEIGHT := 1.0
const BALL_RADIUS := 0.027
## Raio de captura da caçapa, medido do centro dela ao centro da bola. Pouco mais
## que duas bolas, como na mesa de verdade: menos que isso e a bola bate na quina
## em vez de cair, e a partida vira uma discussão sobre o que era gol.
const POCKET_RADIUS := 0.058

## As seis bocas: quatro cantos e duas no meio dos lados compridos.
const POCKETS := [
	Vector2(0.0, 0.0),
	Vector2(TABLE_WIDTH * 0.5, -0.012),
	Vector2(TABLE_WIDTH, 0.0),
	Vector2(0.0, TABLE_HEIGHT),
	Vector2(TABLE_WIDTH * 0.5, TABLE_HEIGHT + 0.012),
	Vector2(TABLE_WIDTH, TABLE_HEIGHT),
]

# --- a física -----------------------------------------------------------------

## Passo fixo da simulação. Pequeno o bastante para uma bola rápida não atravessar
## outra entre dois passos: no teto de velocidade ela anda 0,025 por passo, menos
## que um raio.
const STEP := 1.0 / 240.0
## Quanto da velocidade sobra a cada passo. Atrito de pano, e o número saiu de
## quanto tempo uma tacada forte leva para parar: com isto, uns quatro segundos.
const ROLL_KEEP := 0.994
## Abaixo disto a bola parou. Sem um piso, o atrito multiplicativo nunca chega a
## zero e a mesa fica "andando" para sempre em velocidades invisíveis.
const STOP_SPEED := 0.02
## Quanto sobra numa batida. A tabela come mais que a bola — é pano e borracha
## contra marfim.
const CUSHION_KEEP := 0.86
const BALL_KEEP := 0.96
## Teto de passos por tacada. Não é otimização: é a garantia de que `apply_move`
## termina. Uma bola presa numa quina por um erro de arredondamento não pode
## travar a partida dos dois lados para sempre.
const MAX_STEPS := 3600

## Velocidade máxima da tacada, em unidades por segundo. Uma tacada cheia
## atravessa a mesa umas três vezes antes de parar.
const MAX_SPEED := 6.0
## O que a força mínima ainda faz. Abaixo disto a bola não chega na outra ponta, e
## uma tacada que não chega a lugar nenhum é um turno perdido sem decisão.
const MIN_SPEED := 0.6

## A velocidade viaja em milésimos de unidade por segundo. Ver o cabeçalho.
const SPEED_SCALE := 1000.0

## De quantos em quantos passos a simulação guarda um retrato da mesa, ou 0 para
## não guardar nenhum.
##
## A tela precisa ver a tacada acontecendo, e a alternativa seria ela ter a
## própria cópia da física — duas implementações do mesmo laço, que é o jeito
## clássico de a partida animada divergir da partida jogada. Aqui a animação é
## **a mesma simulação**, amostrada: quem desenha só reproduz retratos.
##
## Zero nos testes e no bot, porque ali ninguém olha e a fita custa memória.
##
## A cena de partida usa [constant TRACE_EVERY], e o número não é livre: a fita é
## reproduzida no mesmo ritmo em que foi gravada, então ele decide a **duração**
## da tacada na tela. Quatro passos dão 60 retratos por segundo, que é tempo real.
const TRACE_EVERY := 4

# --- espécies de lance --------------------------------------------------------

## `path = [KIND, bola, a, b]`, sempre com quatro casas.
##
## Em `SHOOT`, `a` e `b` são a velocidade inicial em milésimos; em `PLACE`, a
## posição, na mesma escala. O campo da bola é o que o mata-mata trouxe: lá a
## tacadeira **é uma escolha**, e um lance que não a carregasse seria um lance que
## o outro aparelho não sabe reproduzir.
const SHOOT := 0
## A branca na mão, depois de uma falta. Só existe na brasileira: sem tacadeira
## não há o que pôr de volta.
const PLACE := 1

const KIND_AT := 0
const BALL_AT := 1
const PATH_SIZE := 4

# --- formatos -----------------------------------------------------------------

enum Format { KNOCKOUT, BRAZILIAN }

## Bolas de cada cor no mata-mata.
const KNOCKOUT_PER_GROUP := 5

## Onde elas começam: encostadas nas tabelas, cada cor de um lado, e duas de cada
## flanqueando as caçapas do meio.
##
## Não é um triângulo, e é o que mais distingue este jogo de uma mesa de pool: sem
## tacadeira não existe saída — não há uma bola de fora para abrir o agrupamento,
## e um triângulo fechado seria dez bolas que ninguém consegue separar. Coladas
## nas tabelas, toda bola tem linha para alguma caçapa desde a primeira tacada.
##
## As cinco primeiras são do grupo 0 e as cinco últimas do grupo 1, e a ordem é a
## do desenho da mesa: três na lateral e duas nos meios.
const KNOCKOUT_SPOTS := [
	Vector2(0.07, 0.25), Vector2(0.07, 0.50), Vector2(0.07, 0.75),
	Vector2(0.89, 0.07), Vector2(0.89, 0.93),
	Vector2(1.93, 0.25), Vector2(1.93, 0.50), Vector2(1.93, 0.75),
	Vector2(1.11, 0.07), Vector2(1.11, 0.93),
]

## Valor das sete coloridas da brasileira, na ordem em que entram em jogo.
const BRAZILIAN_VALUES := [1, 2, 3, 4, 5, 6, 7]
## O que uma falta entrega ao adversário, na brasileira. Sete, como na mesa.
const FOUL_POINTS := 7

# --- chaves de `meta` ---------------------------------------------------------

const SEATS := "st"
const TURN := "tn"
const FORMAT := "fm"
## Posições, `x` e `y` intercalados, uma bola por par.
const POS := "ps"
## Bola ainda na mesa, um byte por bola.
const LIVE := "lv"
## O que cada bola é: grupo (0 ou 1) no mata-mata, valor (1 a 7) na brasileira. A
## branca da brasileira, no índice 0, guarda 0.
const KIND := "kd"
const SCORE := "sc"
## A branca está na mão: o próximo lance é pôr, não tacar. Só na brasileira.
const HAND := "hd"
## Quem venceu, -2 para empate, ou -1. Guardado em vez de derivado porque a
## vitória acontece **dentro** de uma tacada, e a mesa depois dela não distingue
## "limpei o dele" de "ele limpou o meu" quando as duas coisas cabem no mesmo
## lance.
const WINNER := "wn"

## Cores das bolas, para a tela e para o nome. Moram aqui e não no desenho porque
## no mata-mata a cor **é** a regra: ela é o que diz de quem é a bola, e de quem é
## a bola é o que diz se o lance é legal.
const GROUP_COLORS := [Color("4b7fb5"), Color("d98b3a")]
const GROUP_NAMES := ["azuis", "laranjas"]
const BRAZILIAN_COLORS := [
	Color("c9524d"), Color("d9c341"), Color("5f9e63"), Color("8a5b3c"),
	Color("4b7fb5"), Color("d98cb0"), Color("2a2421"),
]
const BRAZILIAN_NAMES := [
	"vermelha", "amarela", "verde", "marrom", "azul", "rosa", "preta",
]

## Formato da mesa, lido uma vez em `initial_state()`. Campo no objeto e não
## parâmetro porque quem constrói é `Game.make_ruleset()`, como em Uno e
## Metrópole.
var format := Format.KNOCKOUT

## Ver [constant TRACE_EVERY].
var trace_every := 0
## Os retratos da última tacada: posições por quadro e quem ainda estava na mesa.
## Válidos até a tacada seguinte.
var trace_spots: Array[PackedFloat64Array] = []
var trace_live: Array[PackedByteArray] = []


func id() -> StringName:
	return &"pool"


func display_name() -> String:
	return "Sinuca"


func players() -> int:
	return 2


# --- leitura do estado --------------------------------------------------------


static func format_of(state: MatchState) -> int:
	return int(state.meta.get(FORMAT, Format.KNOCKOUT))


## A mesa tem tacadeira. É a diferença que atravessa o arquivo — ver o cabeçalho.
static func has_cue_ball(state: MatchState) -> bool:
	return format_of(state) == Format.BRAZILIAN


## O índice da branca, ou -1 quando não há uma.
static func cue_ball(state: MatchState) -> int:
	return 0 if has_cue_ball(state) else -1


static func turn_of(state: MatchState) -> int:
	return int(state.meta.get(TURN, 0))


static func ball_count(state: MatchState) -> int:
	return PackedByteArray(state.meta.get(LIVE, PackedByteArray())).size()


static func is_live(state: MatchState, ball: int) -> bool:
	var live := PackedByteArray(state.meta.get(LIVE, PackedByteArray()))
	return ball >= 0 and ball < live.size() and live[ball] != 0


static func position_of(state: MatchState, ball: int) -> Vector2:
	var spots := PackedFloat64Array(state.meta.get(POS, PackedFloat64Array()))
	if ball < 0 or ball * 2 + 1 >= spots.size():
		return Vector2.ZERO
	return Vector2(spots[ball * 2], spots[ball * 2 + 1])


static func kind_of_ball(state: MatchState, ball: int) -> int:
	var kinds := PackedInt32Array(state.meta.get(KIND, PackedInt32Array()))
	return kinds[ball] if ball >= 0 and ball < kinds.size() else 0


## O grupo de cada assento no mata-mata: o próprio número dele.
##
## Fixo desde a primeira tacada, e não decidido pela primeira bola que cai. Aqui
## a cor não é um prêmio de saída — ela **é** de quem joga desde antes de a
## partida começar, porque é com as bolas dela que ele taca.
static func group_of(seat: int) -> int:
	return seat


static func score_of(state: MatchState, seat: int) -> int:
	var scores := PackedInt32Array(state.meta.get(SCORE, PackedInt32Array()))
	return scores[seat] if seat >= 0 and seat < scores.size() else 0


static func ball_in_hand(state: MatchState) -> bool:
	return has_cue_ball(state) and int(state.meta.get(HAND, 0)) != 0


static func color_of_ball(state: MatchState, ball: int) -> Color:
	if has_cue_ball(state):
		if ball == 0:
			return Color("f2eae0")
		return BRAZILIAN_COLORS[(kind_of_ball(state, ball) - 1) % BRAZILIAN_COLORS.size()]
	return GROUP_COLORS[kind_of_ball(state, ball) % GROUP_COLORS.size()]


## Quantas bolas deste grupo ainda estão na mesa. Só faz sentido no mata-mata.
static func balls_left(state: MatchState, group: int) -> int:
	var count := 0
	for ball in ball_count(state):
		if is_live(state, ball) and kind_of_ball(state, ball) == group:
			count += 1
	return count


## `seat` pode tacar com esta bola agora.
##
## Com tacadeira, só com ela. Sem, só com uma do próprio grupo — e é esta linha
## que faz a escolha da bola ser uma decisão de jogo em vez de um detalhe de tela.
static func can_shoot_with(state: MatchState, seat: int, ball: int) -> bool:
	if not is_live(state, ball):
		return false
	if has_cue_ball(state):
		return ball == cue_ball(state)
	return kind_of_ball(state, ball) == group_of(seat)


## A bola em que a tacadeira **tem** de bater primeiro, ou -1 quando o que importa
## não é uma bola e sim um grupo.
##
## Na brasileira é a de menor número na mesa. No mata-mata não existe uma: o que
## a regra exige é bater primeiro numa bola **do adversário**, e quem confere isso
## é [method _legal_first_hit].
static func target_ball(state: MatchState) -> int:
	if not has_cue_ball(state):
		return -1
	var best := -1
	var best_value := 99
	for ball in range(1, ball_count(state)):
		if not is_live(state, ball):
			continue
		var value := kind_of_ball(state, ball)
		if value < best_value:
			best_value = value
			best = ball
	return best


## As bolas com que quem está na vez pode tacar.
static func shootable(state: MatchState) -> PackedInt32Array:
	var mine := PackedInt32Array()
	var seat := turn_of(state)
	for ball in ball_count(state):
		if can_shoot_with(state, seat, ball):
			mine.append(ball)
	return mine


# --- posição inicial ----------------------------------------------------------


func initial_state() -> MatchState:
	var state := MatchState.new()
	state.meta[SEATS] = 2
	state.meta[TURN] = 0
	state.meta[FORMAT] = format
	state.meta[SCORE] = PackedInt32Array([0, 0])
	state.meta[HAND] = 0
	state.meta[WINNER] = -1

	var spots := PackedFloat64Array()
	var kinds := PackedInt32Array()
	var live := PackedByteArray()

	if format == Format.BRAZILIAN:
		# A branca na cabeceira, e o triângulo com a ponta virada para ela. Aqui a
		# saída existe: há uma bola de fora para abrir o agrupamento.
		_append_ball(spots, kinds, live, _break_spot(), 0)
		var apex := Vector2(TABLE_WIDTH * 0.72, TABLE_HEIGHT * 0.5)
		var gap := BALL_RADIUS * 2.02
		var at := 0
		for row in 4:
			if at >= BRAZILIAN_VALUES.size():
				break
			for slot in row + 1:
				if at >= BRAZILIAN_VALUES.size():
					break
				var spot := apex + Vector2(
					float(row) * gap * 0.866,
					(float(slot) - float(row) * 0.5) * gap
				)
				_append_ball(spots, kinds, live, spot, BRAZILIAN_VALUES[at])
				at += 1
	else:
		for index in KNOCKOUT_SPOTS.size():
			_append_ball(
				spots, kinds, live, KNOCKOUT_SPOTS[index],
				0 if index < KNOCKOUT_PER_GROUP else 1
			)

	state.meta[POS] = spots
	state.meta[KIND] = kinds
	state.meta[LIVE] = live
	state.side_to_move = Board.Side.WHITE
	return state


static func _append_ball(
	spots: PackedFloat64Array, kinds: PackedInt32Array, live: PackedByteArray,
	spot: Vector2, kind: int
) -> void:
	spots.append(spot.x)
	spots.append(spot.y)
	kinds.append(kind)
	live.append(1)


static func _break_spot() -> Vector2:
	return Vector2(TABLE_WIDTH * 0.25, TABLE_HEIGHT * 0.5)


# --- lances -------------------------------------------------------------------


static func kind_of(move: Move) -> int:
	return move.path[KIND_AT]


static func ball_of(move: Move) -> int:
	return move.path[BALL_AT]


static func velocity_of(move: Move) -> Vector2:
	return Vector2(float(move.path[2]), float(move.path[3])) / SPEED_SCALE


static func spot_of(move: Move) -> Vector2:
	return Vector2(float(move.path[2]), float(move.path[3])) / SPEED_SCALE


## Monta a tacada a partir da bola, de uma direção e de uma fração de força.
##
## **Aqui é o único lugar em que trigonometria toca esta partida**, e ele roda só
## no aparelho de quem está mirando: o resultado sai quantizado em inteiros e é
## isso que viaja e que a simulação consome. Ver o cabeçalho.
static func shot(ball: int, direction: Vector2, power: float) -> Move:
	var speed := lerpf(MIN_SPEED, MAX_SPEED, clampf(power, 0.0, 1.0))
	var velocity := direction.normalized() * speed
	var move := Move.new()
	move.path = PackedInt32Array([
		SHOOT, ball,
		int(roundf(velocity.x * SPEED_SCALE)),
		int(roundf(velocity.y * SPEED_SCALE)),
	])
	return move


static func placement(spot: Vector2) -> Move:
	var move := Move.new()
	move.path = PackedInt32Array([
		PLACE, 0, int(roundf(spot.x * SPEED_SCALE)), int(roundf(spot.y * SPEED_SCALE))
	])
	return move


## A porta única por onde todo lance passa — local, de bot ou de rede.
##
## É o desenho de Metrópole, e pelo mesmo motivo: a lista de tacadas legais não
## existe. São todas as bolas vezes todas as direções vezes todas as forças, e
## enumerá-las seria discretizar o jogo. Então a conferência é por **predicado**,
## e quem aplica um `Move` sem passar por aqui está pulando as regras.
func validate(state: MatchState, path: PackedInt32Array) -> Move:
	if path.size() != PATH_SIZE or winner_of(state) >= 0:
		return null
	var move := Move.new()
	move.path = path.duplicate()

	if path[KIND_AT] == PLACE:
		if not ball_in_hand(state):
			return null
		return move if _placeable(state, spot_of(move), cue_ball(state)) else null

	if path[KIND_AT] != SHOOT or ball_in_hand(state):
		return null
	if not can_shoot_with(state, turn_of(state), ball_of(move)):
		return null
	var speed := velocity_of(move).length()
	# A folga de meio milésimo é o arredondamento da quantização: uma tacada de
	# força cheia sai com a velocidade máxima mais ou menos meio milésimo.
	return move if speed >= MIN_SPEED - 0.001 and speed <= MAX_SPEED + 0.001 else null


## Uma bola cabe aqui: dentro do pano, sem encostar em nenhuma outra e longe das
## bocas. `ignore` é a própria bola, que não colide consigo mesma.
static func _placeable(state: MatchState, spot: Vector2, ignore: int) -> bool:
	if (
		spot.x < BALL_RADIUS or spot.x > TABLE_WIDTH - BALL_RADIUS
		or spot.y < BALL_RADIUS or spot.y > TABLE_HEIGHT - BALL_RADIUS
	):
		return false
	for pocket: Vector2 in POCKETS:
		if spot.distance_to(pocket) < POCKET_RADIUS + BALL_RADIUS:
			return false
	for ball in ball_count(state):
		if ball == ignore or not is_live(state, ball):
			continue
		if spot.distance_to(position_of(state, ball)) < BALL_RADIUS * 2.1:
			return false
	return true


## Tacadas candidatas, para o bot e para quem precisa saber que ainda há o que
## fazer. **Não** é a lista do que é legal — ver [method validate].
func generate_moves(state: MatchState) -> Array[Move]:
	var moves: Array[Move] = []
	if winner_of(state) >= 0:
		return moves
	if ball_in_hand(state):
		for spot in _hand_candidates(state):
			moves.append(placement(spot))
		return moves

	var seat := turn_of(state)
	for from in shootable(state):
		var origin := position_of(state, from)
		for ball in ball_count(state):
			if ball == from or not is_live(state, ball) or not _worth_aiming(state, seat, ball):
				continue
			var aim := position_of(state, ball) - origin
			if aim.length() < 0.0001:
				continue
			for power: float in [0.45, 0.75, 1.0]:
				moves.append(shot(from, aim, power))
	if moves.is_empty():
		var mine := shootable(state)
		if not mine.is_empty():
			moves.append(shot(mine[0], Vector2.RIGHT, 0.6))
	return moves


## Vale a pena mirar nesta bola? É o corte que impede o bot de gerar tacadas que a
## regra vai recusar antes mesmo de simular.
static func _worth_aiming(state: MatchState, seat: int, ball: int) -> bool:
	if has_cue_ball(state):
		return true
	return kind_of_ball(state, ball) != group_of(seat)


static func _hand_candidates(state: MatchState) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var wanted := _break_spot()
	var cue := cue_ball(state)
	if _placeable(state, wanted, cue):
		spots.append(wanted)
	# Uma varredura grossa do pano para o caso de a marca estar ocupada. Grossa de
	# propósito: escolher **onde** pôr a branca é a decisão do jogador, e o bot só
	# precisa de um lugar legal.
	for column in 9:
		for row in 5:
			var spot := Vector2(
				TABLE_WIDTH * (0.1 + 0.1 * float(column)),
				TABLE_HEIGHT * (0.15 + 0.175 * float(row))
			)
			if _placeable(state, spot, cue):
				spots.append(spot)
	if spots.is_empty():
		spots.append(wanted)
	return spots


# --- aplicar ------------------------------------------------------------------


func apply_move(state: MatchState, move: Move) -> void:
	if kind_of(move) == PLACE:
		_set_position(state, cue_ball(state), spot_of(move))
		state.meta[HAND] = 0
	else:
		_resolve(state, ball_of(move), velocity_of(move))
	state.ply += 1
	state.history.append(move.to_dict())


## A tacada inteira: simula, lê o que aconteceu, e aplica a regra do formato.
func _resolve(state: MatchState, from: int, velocity: Vector2) -> void:
	var seat := turn_of(state)
	# O alvo é o de **antes** da tacada, e é por isso que ele viaja como parâmetro.
	# Perguntar de novo depois seria perguntar a uma mesa em que a bola da vez pode
	# ter acabado de cair — e aí acertá-la em cheio contaria como falta.
	var target := target_ball(state)
	trace_spots = []
	trace_live = []
	var report := simulate(state, from, velocity, trace_every, trace_spots, trace_live)

	var potted: PackedInt32Array = report["potted"]
	var first: int = report["first"]
	var cue_potted: bool = report["cue"]

	var foul := cue_potted or not _legal_first_hit(state, seat, target, first)
	if has_cue_ball(state):
		_score_brazilian(state, seat, potted, target, foul)
	else:
		_score_knockout(state, seat, from, potted, foul)


## A tacadeira bateu em quem devia.
##
## Na brasileira, na bola da vez. No mata-mata, numa bola **do adversário** — sem
## isso, empurrar as próprias para perto das caçapas seria uma tacada grátis, e o
## jogo deixaria de ter uma decisão por vez.
static func _legal_first_hit(state: MatchState, seat: int, target: int, first: int) -> bool:
	if first < 0:
		return false
	if has_cue_ball(state):
		return first == target
	return kind_of_ball(state, first) != group_of(seat)


## Mata-mata: ganha quem primeiro deixar o adversário sem bola na mesa.
##
## O objetivo invertido é o que faz o resto fechar sozinho. Encaçapar uma bola
## **sua** não precisa de punição escrita: ela sai do jogo, e sair do jogo é
## exatamente o que aproxima o outro de vencer. Um tiro no pé literal, sem caso
## especial nenhum — e quem ficar sem bolas perdeu, porque não sobrou nada para o
## adversário ter de matar.
static func _score_knockout(
	state: MatchState, seat: int, from: int, potted: PackedInt32Array, foul: bool
) -> void:
	var mine := group_of(seat)
	var champion := _wiped_out(state)
	if champion != -1:
		state.meta[WINNER] = champion
		return

	# Segue tacando quem matou alguma do adversário sem falta. A bola que ele usou
	# pode ter caído junto: isso não é prêmio, é uma bola a menos para a próxima
	# tacada — e a regra não precisa dizer nada sobre isso.
	var killed := false
	if not foul:
		for ball in potted:
			if kind_of_ball(state, ball) != mine:
				killed = true
	if foul or not killed:
		state.meta[TURN] = 1 - seat
	# `from` entra só para a assinatura contar a história inteira: a bola que tacou
	# é escolha do jogador, e é ela que ele arrisca perder.
	assert(from >= 0)


## Um dos grupos ficou sem bola: devolve o assento **vencedor**, -2 no empate, ou
## -1 enquanto os dois ainda têm o que perder.
static func _wiped_out(state: MatchState) -> int:
	var alive := [balls_left(state, 0), balls_left(state, 1)]
	if alive[0] == 0 and alive[1] == 0:
		return -2
	if alive[0] == 0:
		return 1
	if alive[1] == 0:
		return 0
	return -1


## Brasileira: cada bola vale o número dela, a falta entrega sete ao adversário, e
## a partida acaba com a mesa limpa.
static func _score_brazilian(
	state: MatchState, seat: int, potted: PackedInt32Array, target: int, foul: bool
) -> void:
	var scores := PackedInt32Array(state.meta.get(SCORE, PackedInt32Array([0, 0])))
	var opponent := 1 - seat

	if foul:
		scores[opponent] += FOUL_POINTS
	else:
		for ball in potted:
			scores[seat] += kind_of_ball(state, ball)
	state.meta[SCORE] = scores

	# Segue tacando quem encaçapou a bola da vez limpo. Encaçapar uma colorida por
	# tabela conta ponto e **não** dá outra tacada: a mesa premia a mira, não a
	# sorte.
	var kept := not foul and potted.has(target)
	state.meta[HAND] = 1 if foul else 0
	if not kept:
		state.meta[TURN] = opponent

	if target_ball(state) < 0:
		state.meta[WINNER] = 0 if scores[0] > scores[1] else (1 if scores[1] > scores[0] else -2)


# --- a física -----------------------------------------------------------------


## Roda a tacada até a mesa parar, mexendo nas posições do estado.
##
## Devolve o que a regra precisa saber e nada mais: quem caiu, em quem a
## tacadeira bateu primeiro, e se ela própria caiu. Tudo o que é desenho — o
## caminho que cada bola fez — a tela refaz rodando a mesma função, e é por isso
## que ela é pública.
##
## Só `+ - * /` e `sqrt` aqui dentro. Ver o cabeçalho: é essa disciplina que faz
## dois aparelhos chegarem à mesma mesa.
static func simulate(
	state: MatchState, from: int, velocity: Vector2, trace_every := 0,
	trace_spots: Array[PackedFloat64Array] = [], trace_live: Array[PackedByteArray] = []
) -> Dictionary:
	var count := ball_count(state)
	var spots := PackedFloat64Array(state.meta.get(POS, PackedFloat64Array()))
	var live := PackedByteArray(state.meta.get(LIVE, PackedByteArray()))
	var speed := PackedFloat64Array()
	speed.resize(count * 2)
	if from >= 0 and from < count:
		speed[from * 2] = velocity.x
		speed[from * 2 + 1] = velocity.y

	var potted := PackedInt32Array()
	var first := -1

	for step in MAX_STEPS:
		if trace_every > 0 and step % trace_every == 0:
			trace_spots.append(spots.duplicate())
			trace_live.append(live.duplicate())
		var moving := false
		for ball in count:
			if live[ball] == 0:
				continue
			var vx := speed[ball * 2]
			var vy := speed[ball * 2 + 1]
			if vx * vx + vy * vy < STOP_SPEED * STOP_SPEED:
				speed[ball * 2] = 0.0
				speed[ball * 2 + 1] = 0.0
				continue
			moving = true
			spots[ball * 2] += vx * STEP
			spots[ball * 2 + 1] += vy * STEP
			speed[ball * 2] = vx * ROLL_KEEP
			speed[ball * 2 + 1] = vy * ROLL_KEEP
		if not moving:
			break

		_bounce_cushions(spots, speed, live, count)
		var hit := _collide_balls(spots, speed, live, count, from)
		if first < 0 and hit >= 0:
			first = hit
		_sink(spots, speed, live, count, potted)

	var cue_potted := from >= 0 and from < count and live[from] == 0
	if cue_potted and has_cue_ball(state) and from == cue_ball(state):
		# A branca sempre volta à mesa: ela é o taco, não um alvo. Sem tacadeira não
		# há volta — a bola era de alguém, e cair é perdê-la.
		live[from] = 1
		spots[from * 2] = _break_spot().x
		spots[from * 2 + 1] = _break_spot().y
		speed[from * 2] = 0.0
		speed[from * 2 + 1] = 0.0
		potted = _without(potted, from)

	if trace_every > 0:
		# O último retrato é a mesa parada: é nele que a animação termina, e ele tem
		# de ser igual ao estado que a regra gravou.
		trace_spots.append(spots.duplicate())
		trace_live.append(live.duplicate())

	state.meta[POS] = spots
	state.meta[LIVE] = live
	return {"potted": potted, "first": first, "cue": cue_potted}


static func _without(list: PackedInt32Array, value: int) -> PackedInt32Array:
	var kept := PackedInt32Array()
	for entry in list:
		if entry != value:
			kept.append(entry)
	return kept


## A bola está na boca de alguma caçapa. Um pouco mais larga que o raio de
## captura: a borracha tem de sumir **antes** de a bola chegar ao ponto em que ela
## cai, senão a última quicada acontece dentro do buraco.
static func _in_jaws(x: float, y: float) -> bool:
	for pocket: Vector2 in POCKETS:
		var dx := x - pocket.x
		var dy := y - pocket.y
		if dx * dx + dy * dy < (POCKET_RADIUS + BALL_RADIUS) * (POCKET_RADIUS + BALL_RADIUS):
			return true
	return false


static func _bounce_cushions(
	spots: PackedFloat64Array, speed: PackedFloat64Array, live: PackedByteArray, count: int
) -> void:
	for ball in count:
		if live[ball] == 0:
			continue
		# Na boca da caçapa não há tabela.
		#
		# Sem isto a borracha atravessa a entrada e a bola **quica** no lugar em que
		# deveria cair: uma bola mandada no canto volta para o pano, e o jogo fica
		# com seis buracos que só engolem quem chega pelo meio. A boca é justamente
		# o pedaço de tabela que não existe.
		if _in_jaws(spots[ball * 2], spots[ball * 2 + 1]):
			continue
		var x := spots[ball * 2]
		var y := spots[ball * 2 + 1]
		if x < BALL_RADIUS:
			spots[ball * 2] = BALL_RADIUS
			speed[ball * 2] = absf(speed[ball * 2]) * CUSHION_KEEP
		elif x > TABLE_WIDTH - BALL_RADIUS:
			spots[ball * 2] = TABLE_WIDTH - BALL_RADIUS
			speed[ball * 2] = -absf(speed[ball * 2]) * CUSHION_KEEP
		if y < BALL_RADIUS:
			spots[ball * 2 + 1] = BALL_RADIUS
			speed[ball * 2 + 1] = absf(speed[ball * 2 + 1]) * CUSHION_KEEP
		elif y > TABLE_HEIGHT - BALL_RADIUS:
			spots[ball * 2 + 1] = TABLE_HEIGHT - BALL_RADIUS
			speed[ball * 2 + 1] = -absf(speed[ball * 2 + 1]) * CUSHION_KEEP


## Resolve as batidas do passo e devolve a primeira bola em que **a tacadeira**
## bateu neste passo, ou -1.
##
## Elástica e de massas iguais: a componente da velocidade relativa ao longo da
## linha dos centros troca de dono, e o resto passa reto. É a conta de uma linha
## que produz a carambola inteira, e é a mesma que uma mesa de verdade faz.
static func _collide_balls(
	spots: PackedFloat64Array, speed: PackedFloat64Array, live: PackedByteArray,
	count: int, from: int
) -> int:
	var cue_hit := -1
	for a in count:
		if live[a] == 0:
			continue
		for b in range(a + 1, count):
			if live[b] == 0:
				continue
			var dx := spots[b * 2] - spots[a * 2]
			var dy := spots[b * 2 + 1] - spots[a * 2 + 1]
			var square := dx * dx + dy * dy
			var touch := BALL_RADIUS * 2.0
			if square >= touch * touch or square < 0.000000001:
				continue
			var span := sqrt(square)
			var nx := dx / span
			var ny := dy / span

			# Separa antes de trocar a velocidade: com as duas ainda encavaladas, o
			# passo seguinte volta a detectar a mesma batida e as bolas grudam.
			var slack := (touch - span) * 0.5
			spots[a * 2] -= nx * slack
			spots[a * 2 + 1] -= ny * slack
			spots[b * 2] += nx * slack
			spots[b * 2 + 1] += ny * slack

			var rvx := speed[b * 2] - speed[a * 2]
			var rvy := speed[b * 2 + 1] - speed[a * 2 + 1]
			var along := rvx * nx + rvy * ny
			if along > 0.0:
				continue
			var impulse := along * BALL_KEEP
			speed[a * 2] += nx * impulse
			speed[a * 2 + 1] += ny * impulse
			speed[b * 2] -= nx * impulse
			speed[b * 2 + 1] -= ny * impulse

			if cue_hit < 0:
				if a == from:
					cue_hit = b
				elif b == from:
					cue_hit = a
	return cue_hit


static func _sink(
	spots: PackedFloat64Array, speed: PackedFloat64Array,
	live: PackedByteArray, count: int, potted: PackedInt32Array
) -> void:
	for ball in count:
		if live[ball] == 0:
			continue
		var spot := Vector2(spots[ball * 2], spots[ball * 2 + 1])
		for pocket: Vector2 in POCKETS:
			if spot.distance_to(pocket) > POCKET_RADIUS:
				continue
			live[ball] = 0
			speed[ball * 2] = 0.0
			speed[ball * 2 + 1] = 0.0
			potted.append(ball)
			break


static func _set_position(state: MatchState, ball: int, spot: Vector2) -> void:
	var spots := PackedFloat64Array(state.meta.get(POS, PackedFloat64Array()))
	spots[ball * 2] = spot.x
	spots[ball * 2 + 1] = spot.y
	state.meta[POS] = spots


# --- fim ----------------------------------------------------------------------


## Assento vencedor, -2 para empate, -1 enquanto corre.
static func winner_of(state: MatchState) -> int:
	return int(state.meta.get(WINNER, -1))


func outcome(state: MatchState) -> Outcome:
	var champion := winner_of(state)
	if champion == -2:
		return Outcome.DRAW
	if champion == 0:
		return Outcome.WHITE_WINS
	if champion == 1:
		return Outcome.BLACK_WINS
	return Outcome.ONGOING


func status_hint(state: MatchState) -> String:
	if winner_of(state) >= 0:
		return ""
	if ball_in_hand(state):
		return "Falta. Ponha a branca onde quiser."
	if has_cue_ball(state):
		var target := target_ball(state)
		if target >= 0:
			return "Bola da vez: %s." % BRAZILIAN_NAMES[(kind_of_ball(state, target) - 1) % 7]
		return ""
	return "Escolha uma das suas %s e bata numa do adversário." % GROUP_NAMES[
		group_of(turn_of(state)) % GROUP_NAMES.size()
	]


func notation(state: MatchState, move: Move) -> String:
	var seat := turn_of(state)
	if kind_of(move) == PLACE:
		return "%d põe a branca" % (seat + 1)
	return "%d taca a %d" % [seat + 1, ball_of(move) + 1]


## O melhor entre os candidatos, e o critério é simples porque a busca não é: cada
## tacada é simulada numa cópia da mesa, e vale a que mata o que interessa sem
## fazer falta.
##
## Não há alfa-beta aqui. O `Bot` do app procura em profundidade contando lances
## discretos, e uma tacada não é discreta — o galho seguinte depende de onde dez
## bolas pararam. Um passo só, simulado de verdade, joga melhor que uma árvore
## rasa sobre uma aproximação.
func best_move(state: MatchState, moves: Array[Move]) -> Move:
	var best: Move = null
	var best_score := -1000.0
	for move in moves:
		var score := _score_shot(state, move)
		if score > best_score:
			best_score = score
			best = move
	return best


func _score_shot(state: MatchState, move: Move) -> float:
	if kind_of(move) == PLACE:
		# Pôr a branca perto do meio abre mais ângulos que encostá-la numa tabela.
		var spot := spot_of(move)
		return -spot.distance_to(Vector2(TABLE_WIDTH * 0.5, TABLE_HEIGHT * 0.5))

	var seat := turn_of(state)
	var mine := group_of(seat)
	var trial := state.clone()
	var target := target_ball(trial)
	var report := simulate(trial, ball_of(move), velocity_of(move))
	var potted: PackedInt32Array = report["potted"]
	var first: int = report["first"]

	if report["cue"] and has_cue_ball(state):
		return -100.0
	if not _legal_first_hit(state, seat, target, first):
		return -100.0

	var score := 0.0
	for ball in potted:
		if has_cue_ball(state):
			score += 10.0 if ball == target else 4.0
		elif kind_of_ball(state, ball) == mine:
			# Perder uma bola sua é perder um projétil **e** aproximar o outro do
			# fim. Dois prejuízos numa tacada só, e por isso ela pesa mais que o
			# ganho de matar uma.
			score -= 14.0
		else:
			score += 10.0
	return score
