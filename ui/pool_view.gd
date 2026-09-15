class_name PoolView
extends Control

## A mesa de sinuca: o pano, as bolas, a mira e a tacada acontecendo.
##
## ## A animação é a própria simulação
##
## Ela não recalcula nada: [PoolRules] guarda retratos da mesa a cada punhado de
## passos e esta tela os reproduz em ordem. Uma segunda física aqui seria a forma
## clássica de a partida animada divergir da partida jogada — a bola entrando na
## tela e não entrando na regra, ou o contrário.
##
## ## A mira é um arrasto, e ele é ao contrário
##
## O dedo puxa **para trás** da branca, como se puxa um taco: a direção é do dedo
## para a bola, e a distância é a força. Puxar para frente pareceria empurrar a
## bola com o dedo, e num celular o dedo estaria justamente em cima do que ele
## precisa ver.
##
## Enquanto o dedo está na tela, a linha de mira mostra **onde a branca vai
## bater** — o traçado para até a primeira bola no caminho, e ali aparece o ponto
## de contato. Sem isso, mirar num celular é chutar: o dedo cobre a bola e não há
## taco para alinhar com o olho.

## Uma tacada foi pedida: direção e força de 0 a 1.
signal shot_aimed(direction: Vector2, power: float)
## A branca foi posta, em coordenadas de mesa.
signal ball_placed(spot: Vector2)

const Rules := preload("res://core/pool_rules.gd")

## Cores da mesa. Pano verde-escuro e não a madeira do xadrez: uma mesa de sinuca
## é reconhecida pelo pano antes de qualquer outra coisa, e o latão do tema
## continua sendo só o que diz "aja aqui".
const CLOTH := Color("1f3b2e")
const CLOTH_EDGE := Color("183025")
const RAIL := Color("4a2f1f")
const RAIL_EDGE := Color("302014")
const POCKET_INK := Color("0d0b0a")
const LINE := Color("2b4d3c")

## Largura da tabela em volta do pano, em unidades de mesa.
const RAIL_WIDTH := 0.055
## Quanto do arrasto vale força cheia, em fração da largura da mesa desenhada.
const PULL_FULL := 0.30
## Abaixo disto o arrasto não é tacada: é um toque que escorregou.
const PULL_DEAD := 0.02

var state: MatchState = null:
	set(value):
		state = value
		queue_redraw()

## A mesa aceita mira. Falso na vez do outro e enquanto a tacada corre.
var enabled := false:
	set(value):
		enabled = value
		if not value:
			_pull = Vector2.ZERO
			_aiming = false
		queue_redraw()

## Os retratos em reprodução, e onde ela está.
var _frames: Array[PackedFloat64Array] = []
var _frame_live: Array[PackedByteArray] = []
var _frame := 0.0
var _playing := false

var _aiming := false
var _pull := Vector2.ZERO
var _scale := 1.0
var _origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


## Reproduz a tacada que a regra acabou de simular.
func play(spots: Array[PackedFloat64Array], live: Array[PackedByteArray]) -> void:
	_frames = spots
	_frame_live = live
	_frame = 0.0
	_playing = not spots.is_empty()
	set_process(_playing)
	queue_redraw()


## Segundos que faltam da tacada em curso. A cena espera por isto antes de
## resolver o que a tacada causou — ver o mesmo padrão no tabuleiro de xadrez.
func remaining_animation() -> float:
	if not _playing:
		return 0.0
	return maxf(0.0, (float(_frames.size()) - _frame) / _playback_fps())


func _playback_fps() -> float:
	# A fita foi amostrada a cada N passos de [constant PoolRules.STEP], então
	# reproduzi-la nesse mesmo ritmo devolve o tempo real da tacada. Reproduzir por
	# quadro da tela faria a mesma tacada durar diferente em cada aparelho.
	return 1.0 / (Rules.STEP * float(maxi(1, Rules.TRACE_EVERY)))


func _process(delta: float) -> void:
	_frame += delta * _playback_fps()
	if _frame >= float(_frames.size()) - 1.0:
		_frame = float(_frames.size()) - 1.0
		_playing = false
		set_process(false)
	queue_redraw()


# --- gesto --------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not enabled or state == null or _playing:
		return
	var press := event as InputEventMouseButton
	if press != null and press.button_index == MOUSE_BUTTON_LEFT:
		if press.pressed:
			_begin(press.position)
		else:
			_end(press.position)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _aiming:
		_pull = motion.position - _cue_screen()
		queue_redraw()
		accept_event()


func _begin(at: Vector2) -> void:
	if Rules.ball_in_hand(state):
		var spot := _to_table(at)
		if Rules._placeable(state, spot):
			ball_placed.emit(spot)
		return
	_aiming = true
	_pull = at - _cue_screen()
	queue_redraw()


func _end(at: Vector2) -> void:
	if not _aiming:
		return
	_aiming = false
	_pull = at - _cue_screen()
	var pull := _pull.length()
	var full := size.x * PULL_FULL
	if pull < size.x * PULL_DEAD:
		_pull = Vector2.ZERO
		queue_redraw()
		return
	# A direção é **do dedo para a bola**: puxa-se o taco para trás. Ver o
	# cabeçalho.
	var direction := -_pull.normalized()
	shot_aimed.emit(direction, clampf(pull / full, 0.0, 1.0))
	_pull = Vector2.ZERO
	queue_redraw()


# --- geometria ----------------------------------------------------------------


func _layout() -> void:
	var span := Vector2(
		Rules.TABLE_WIDTH + RAIL_WIDTH * 2.0, Rules.TABLE_HEIGHT + RAIL_WIDTH * 2.0
	)
	_scale = minf(size.x / span.x, size.y / span.y)
	_origin = (size - span * _scale) * 0.5 + Vector2.ONE * RAIL_WIDTH * _scale


func _to_screen(spot: Vector2) -> Vector2:
	return _origin + spot * _scale


func _to_table(at: Vector2) -> Vector2:
	return (at - _origin) / _scale


func _cue_screen() -> Vector2:
	return _to_screen(_ball_spot(0))


## Onde a bola está **agora na tela**: o retrato em reprodução quando há um, o
## estado quando não há.
func _ball_spot(ball: int) -> Vector2:
	if _frames.is_empty():
		return Rules.position_of(state, ball)
	var frame: PackedFloat64Array = _frames[mini(int(_frame), _frames.size() - 1)]
	return Vector2(frame[ball * 2], frame[ball * 2 + 1])


func _ball_live(ball: int) -> bool:
	if _frame_live.is_empty():
		return Rules.is_live(state, ball)
	var frame: PackedByteArray = _frame_live[mini(int(_frame), _frame_live.size() - 1)]
	return frame[ball] != 0


# --- desenho ------------------------------------------------------------------


func _draw() -> void:
	if state == null:
		return
	_layout()
	_draw_table()
	_draw_aim()
	_draw_balls()


func _draw_table() -> void:
	var cloth := Rect2(_to_screen(Vector2.ZERO), Vector2(Rules.TABLE_WIDTH, Rules.TABLE_HEIGHT) * _scale)
	var rail := cloth.grow(RAIL_WIDTH * _scale)
	draw_rect(rail, RAIL)
	draw_rect(rail, RAIL_EDGE, false, maxf(2.0, _scale * 0.006))
	draw_rect(cloth, CLOTH)
	draw_rect(cloth, CLOTH_EDGE, false, maxf(2.0, _scale * 0.004))

	# A linha da cabeceira. Ela não é regra neste app — a branca na mão pode ir a
	# qualquer lugar —, mas é o que faz a superfície ler como mesa de sinuca e não
	# como um retângulo verde.
	var head := _to_screen(Vector2(Rules.TABLE_WIDTH * 0.25, 0.0))
	draw_line(head, head + Vector2(0.0, Rules.TABLE_HEIGHT * _scale), LINE, maxf(1.0, _scale * 0.004))
	var mark := _to_screen(Rules._break_spot())
	draw_arc(mark, _scale * 0.012, 0.0, TAU, 16, LINE, maxf(1.0, _scale * 0.004), true)

	for pocket: Vector2 in Rules.POCKETS:
		draw_circle(_to_screen(pocket), Rules.POCKET_RADIUS * _scale, POCKET_INK)


## A linha de mira, e ela para onde a bola vai parar.
##
## O traçado segue reto até a primeira bola no caminho e marca o ponto de contato.
## Sem essa parada, a linha atravessaria a mesa inteira e prometeria uma trajetória
## que não existe — o pior tipo de ajuda, a que mente.
func _draw_aim() -> void:
	if not _aiming or _pull.length() < size.x * PULL_DEAD:
		return
	var cue := _cue_screen()
	var direction := -_pull.normalized()
	# Até a tabela, e nunca além dela: uma linha que sai do pano promete uma
	# trajetória fora da mesa, e o pior tipo de ajuda é a que mente.
	var reach := _cushion_reach(direction)
	var blocked := _first_in_path(direction)
	if blocked > 0.0:
		reach = minf(reach, blocked)

	var tip := cue + direction * reach
	draw_line(cue, tip, Color(AppTheme.ACCENT, 0.55), maxf(2.0, _scale * 0.006))
	draw_arc(tip, Rules.BALL_RADIUS * _scale, 0.0, TAU, 24, Color(AppTheme.ACCENT, 0.75), 2.0, true)

	# A força, num arco atrás da bola: ele cresce com o arrasto e fica no lado de
	# onde o dedo puxou, que é onde o olho já está.
	var power := clampf(_pull.length() / (size.x * PULL_FULL), 0.0, 1.0)
	var back := cue - direction * Rules.BALL_RADIUS * _scale * 2.4
	draw_arc(
		back, Rules.BALL_RADIUS * _scale * (1.1 + power * 1.6), 0.0, TAU, 28,
		Color(AppTheme.ACCENT, 0.25 + 0.5 * power), maxf(2.0, _scale * 0.008), true
	)


## Distância até a tabela, na direção mirada. Em pixels de tela.
func _cushion_reach(direction: Vector2) -> float:
	var cue := _ball_spot(0)
	var aim := direction.normalized()
	var reach := Rules.TABLE_WIDTH + Rules.TABLE_HEIGHT
	var edge := Rules.BALL_RADIUS
	if aim.x > 0.0001:
		reach = minf(reach, (Rules.TABLE_WIDTH - edge - cue.x) / aim.x)
	elif aim.x < -0.0001:
		reach = minf(reach, (edge - cue.x) / aim.x)
	if aim.y > 0.0001:
		reach = minf(reach, (Rules.TABLE_HEIGHT - edge - cue.y) / aim.y)
	elif aim.y < -0.0001:
		reach = minf(reach, (edge - cue.y) / aim.y)
	return maxf(0.0, reach) * _scale


## Distância até a primeira bola no caminho da branca, ou -1.
func _first_in_path(direction: Vector2) -> float:
	var cue := _ball_spot(0)
	var aim := direction / _scale
	var best := -1.0
	for ball in range(1, Rules.ball_count(state)):
		if not _ball_live(ball):
			continue
		var to_ball := _ball_spot(ball) - cue
		var along := to_ball.dot(aim.normalized())
		if along <= 0.0:
			continue
		var side := (to_ball - aim.normalized() * along).length()
		if side > Rules.BALL_RADIUS * 2.0:
			continue
		var stop := along - Rules.BALL_RADIUS * 2.0
		if best < 0.0 or stop < best:
			best = stop
	return best * _scale if best >= 0.0 else -1.0


func _draw_balls() -> void:
	var radius := Rules.BALL_RADIUS * _scale
	for ball in Rules.ball_count(state):
		if not _ball_live(ball):
			continue
		var at := _to_screen(_ball_spot(ball))
		var tint := Rules.color_of_ball(state, ball)
		# Sombra rente, e uma calota clara em cima: são as duas coisas que separam
		# uma bola de um disco, e as duas custam um `draw_circle`.
		draw_circle(at + Vector2(radius * 0.18, radius * 0.22), radius, Color(0, 0, 0, 0.35))
		draw_circle(at, radius, tint)
		draw_circle(at - Vector2(radius * 0.28, radius * 0.30), radius * 0.38, Color(1, 1, 1, 0.30))
		draw_arc(at, radius, 0.0, TAU, 24, Color(0, 0, 0, 0.45), maxf(1.0, radius * 0.10), true)

		# O número, só na brasileira: lá a bola **vale** o número, e a cor sozinha
		# obrigaria a decorar uma tabela de sete.
		if ball > 0 and Rules.format_of(state) == Rules.Format.BRAZILIAN:
			_draw_value(at, radius, Rules.kind_of_ball(state, ball), tint)


func _draw_value(at: Vector2, radius: float, value: int, tint: Color) -> void:
	var font := AppTheme.font(700)
	var body := maxi(8, int(radius * 1.1))
	var text := str(value)
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, body).x
	draw_circle(at, radius * 0.60, Color(AppTheme.TEXT, 0.92))
	draw_string(
		font, at + Vector2(-wide * 0.5, body * 0.36), text,
		HORIZONTAL_ALIGNMENT_CENTER, wide, body, tint.darkened(0.45)
	)
