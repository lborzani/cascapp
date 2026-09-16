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

## Uma tacada foi pedida: com qual bola, em que direção e com que força (0 a 1).
signal shot_aimed(ball: int, direction: Vector2, power: float)
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

## O taco. Madeira clara, cabo escuro, virola branca e a sola de couro azul — as
## quatro faixas que fazem um bastão marrom ler como taco de sinuca.
const CUE_WOOD := Color("c8a06a")
const CUE_GRIP := Color("3a2a1c")
const CUE_FERRULE := Color("efe6d8")
const CUE_LEATHER := Color("4b7fb5")

## Largura da tabela em volta do pano, em unidades de mesa.
const RAIL_WIDTH := 0.055
## Quanto do arrasto vale força cheia, em fração da largura da mesa desenhada.
const PULL_FULL := 0.30
## Abaixo disto o arrasto não é tacada: é um toque que escorregou.
const PULL_DEAD := 0.02

## Comprimento do taco, em unidades de mesa. Um taco de verdade mede quase o
## comprimento da mesa; este mede pouco mais da metade, porque o que sobra sai
## pela borda da tela e o que importa é a metade que encosta na bola.
const CUE_LENGTH := 1.15
## Raio do taco na ponta e no cabo. A diferença é o que dá o afunilamento — um
## retângulo de largura constante lê como régua.
const CUE_TIP := 0.011
const CUE_BUTT := 0.024
## Quanto o taco recua com a força, em unidades de mesa. O recuo **é** a barra de
## força: um taco puxado para trás diz quanta pancada vem sem nenhum número na
## tela, que é como se lê força numa mesa de verdade.
const CUE_PULL_MIN := 0.03
const CUE_PULL_MAX := 0.22

## Comprimento da linha que sai da bola atingida, em unidades de mesa.
##
## Curta de propósito. Ela é uma **direção**, não uma trajetória: a bola objeto
## sai pela linha dos centros no instante do contato, e isso é exato; para onde
## ela vai depois de bater numa tabela ou noutra bola já não é, e prometer isso
## seria prometer o que a régua não mede.
const OBJECT_HINT := 0.20

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
## A bola escolhida para tacar, ou -1 para "a primeira que servir". Ver [method
## _shooter_ball].
var _shooter := -1
var _scale := 1.0
var _origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# O taco é mais comprido que a folga entre a mesa e a borda da tela, e sem
	# recorte ele atravessaria a coluna dos jogadores. Recortado, ele some pela
	# borda — que é o que um taco faz quando o jogador se afasta da mesa.
	clip_contents = true
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


## O toque começa uma de duas coisas: **escolher a bola** ou puxar o taco.
##
## Qual das duas sai do lugar em que o dedo encostou. Em cima de uma bola que
## pode tacar, é escolha; em qualquer outro lugar, é mira da que já está
## escolhida. Um botão separado para trocar de bola seria um toque a mais para
## uma decisão que o dedo já sabe apontar.
##
## No mata-mata a escolha é o primeiro lance de cada vez, e é ela que o jogo tem
## de novo: sem tacadeira, com **qual** das próprias bolas se taca é metade da
## jogada. Na brasileira só a branca é tacável, e a escolha se resolve sozinha.
func _begin(at: Vector2) -> void:
	if Rules.ball_in_hand(state):
		var spot := _to_table(at)
		if Rules._placeable(state, spot, Rules.cue_ball(state)):
			ball_placed.emit(spot)
		return

	var picked := _ball_under(at)
	if picked >= 0:
		_shooter = picked
		_aiming = false
		_pull = Vector2.ZERO
		queue_redraw()
		return

	if _shooter_ball() < 0:
		return
	_aiming = true
	_pull = at - _cue_screen()
	queue_redraw()


func _end(at: Vector2) -> void:
	if not _aiming:
		return
	_aiming = false
	var ball := _shooter_ball()
	_pull = at - _cue_screen()
	var pull := _pull.length()
	var full := size.x * PULL_FULL
	if pull < size.x * PULL_DEAD or ball < 0:
		_pull = Vector2.ZERO
		queue_redraw()
		return
	# A direção é **do dedo para a bola**: puxa-se o taco para trás. Ver o
	# cabeçalho.
	var direction := -_pull.normalized()
	shot_aimed.emit(ball, direction, clampf(pull / full, 0.0, 1.0))
	_pull = Vector2.ZERO
	queue_redraw()


## A bola tacável sob o dedo, ou -1.
##
## O alvo é maior que a bola — um dedo tem uns oito milímetros e uma bola
## desenhada tem menos que isso num celular. Sem a folga, escolher com qual bola
## tacar viraria um teste de pontaria antes do teste de pontaria.
func _ball_under(at: Vector2) -> int:
	var spot := _to_table(at)
	var reach := Rules.BALL_RADIUS * 2.2
	var best := -1
	var closest := reach
	var seat := Rules.turn_of(state)
	for ball in Rules.ball_count(state):
		if not Rules.can_shoot_with(state, seat, ball):
			continue
		var apart := spot.distance_to(_ball_spot(ball))
		if apart <= closest:
			closest = apart
			best = ball
	return best


## Com qual bola se taca agora.
##
## A escolhida, quando ela ainda está na mesa e ainda é de quem joga; senão a
## primeira tacável. O segundo caso não é conveniência: a bola escolhida pode ter
## **caído na tacada anterior**, e uma tela que guardasse o índice dela apontaria
## o taco para um buraco.
func _shooter_ball() -> int:
	if state == null:
		return -1
	var seat := Rules.turn_of(state)
	if _shooter >= 0 and Rules.can_shoot_with(state, seat, _shooter):
		return _shooter
	var mine := Rules.shootable(state)
	return mine[0] if not mine.is_empty() else -1


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


## Onde a bola que taca está na tela. Não é "a bola 0": no mata-mata ela é a
## escolhida, e muda a cada vez.
func _cue_screen() -> Vector2:
	return _to_screen(_ball_spot(_shooter_ball()))


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
	# As linhas correm **por baixo** das bolas e o taco **por cima** delas, que é a
	# ordem física: a régua está no pano, o taco está na mão.
	_draw_aim()
	_draw_balls()
	_draw_cue()


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
	var direction := -_pull.normalized()
	var cue_spot := _ball_spot(_shooter_ball())

	# Até a tabela, e nunca além dela: uma linha que sai do pano promete uma
	# trajetória fora da mesa, e o pior tipo de ajuda é a que mente.
	var impact := _impact(direction)
	var reach: float = _cushion_reach(direction)
	var hit: int = impact["ball"]
	if hit >= 0:
		reach = minf(reach, float(impact["stop"]))

	var ghost_spot := cue_spot + direction * reach
	draw_line(
		_to_screen(cue_spot), _to_screen(ghost_spot),
		Color(AppTheme.ACCENT, 0.55), maxf(2.0, _scale * 0.006)
	)
	if hit < 0:
		# Sem bola no caminho, a linha morre na tabela e mais nada. Um círculo
		# vazado ali marcaria um ponto de contato que não existe.
		return

	# A bola fantasma: onde a branca **para**, e não onde a linha acaba. É a partir
	# do centro dela que a linha dos centros sai, então desenhá-la é mostrar de
	# onde veio a resposta do traço seguinte.
	draw_arc(
		_to_screen(ghost_spot), Rules.BALL_RADIUS * _scale, 0.0, TAU, 24,
		Color(AppTheme.ACCENT, 0.75), maxf(1.5, _scale * 0.004), true
	)
	_draw_object_line(hit, ghost_spot)


## Para onde a **bola atingida** sai, e por que a linha é exatamente essa.
##
## Numa batida entre duas esferas de mesma massa, a bola parada sai pela **linha
## dos centros** no instante do contato — não pela direção da tacada. É a regra
## de bolso que todo jogador usa e a única coisa da mesa que dá para prometer sem
## mentir: a partir dali, a primeira tabela já depende de quanto sobrou de
## velocidade.
##
## Por isso a linha é curta e é da **cor da bola**. Curta porque é uma direção e
## não uma trajetória; da cor da bola porque no mata-mata a pergunta não é só
## "para onde", é "qual" — e uma segunda linha em latão diria que ela é a mesma
## coisa que a mira, que é justamente o que ela não é.
func _draw_object_line(ball: int, contact: Vector2) -> void:
	var target := _ball_spot(ball)
	var away := target - contact
	if away.length() < 0.0001:
		return
	away = away.normalized()
	var span := minf(OBJECT_HINT, _cushion_reach_from(target, away))
	# A cor da bola, clareada quando ela é escura demais para riscar o pano.
	#
	# A preta do 7 é quase a cor do fundo do app, e uma seta preta sobre verde
	# escuro é uma seta que não existe. Clarear em vez de trocar por uma cor fixa
	# mantém a resposta que a linha dá — **qual** bola vai —, que é metade do que
	# ela serve para dizer.
	var tint := Rules.color_of_ball(state, ball)
	if tint.get_luminance() < 0.32:
		tint = tint.lerp(AppTheme.TEXT, 0.6)
	var head := target + away * Rules.BALL_RADIUS
	var tail := target + away * (Rules.BALL_RADIUS + span)
	draw_line(_to_screen(head), _to_screen(tail), Color(tint, 0.85), maxf(2.0, _scale * 0.007))

	# A seta é o que separa "esta bola" de "para lá": sem ponta, a linha lida de
	# relance é o traço da mira continuando por trás da bola.
	var wing := Vector2(away.y, -away.x) * 0.015
	var base := tail - away * 0.028
	draw_colored_polygon(
		PackedVector2Array([
			_to_screen(tail), _to_screen(base + wing), _to_screen(base - wing)
		]),
		Color(tint, 0.9)
	)


## O taco, atrás da branca e recuado pela força.
##
## Ele não é enfeite: é a **barra de força** do jogo. Um taco puxado para trás diz
## quanta pancada vem sem nenhum número na tela, que é como se lê força numa mesa
## de verdade — e o arco que fazia esse papel antes dizia a mesma coisa numa
## língua que não é a da sinuca.
##
## Só enquanto o dedo está na tela. Um taco parado atrás da bola pediria uma
## direção que ninguém escolheu ainda, e apontá-lo para um lado qualquer seria a
## tela inventando a mira.
func _draw_cue() -> void:
	if not _aiming or _pull.length() < size.x * PULL_DEAD:
		return
	var cue_spot := _ball_spot(_shooter_ball())
	var away := _pull.normalized()
	var power := clampf(_pull.length() / (size.x * PULL_FULL), 0.0, 1.0)
	var gap := Rules.BALL_RADIUS + lerpf(CUE_PULL_MIN, CUE_PULL_MAX, power)
	var tip := cue_spot + away * gap
	var side := Vector2(away.y, -away.x)

	# Quatro trechos ao longo do mesmo eixo, cada um um pouco mais grosso que o
	# anterior: couro, virola, madeira, cabo. O afunilamento é o que faz um bastão
	# marrom ler como taco em vez de régua.
	var marks := [0.0, 0.022, 0.055, 0.52, 1.0]
	var tints := [CUE_LEATHER, CUE_FERRULE, CUE_WOOD, CUE_GRIP]
	for part in tints.size():
		var near: float = marks[part]
		var far: float = marks[part + 1]
		_draw_taper(tip, away, side, near, far, tints[part])

	# Um fio escuro por baixo dá volume sem uma segunda passada de desenho: o taco
	# deixa de ser uma forma chapada e passa a ter um lado iluminado.
	var butt := tip + away * CUE_LENGTH
	draw_line(
		_to_screen(tip + side * CUE_TIP * 0.6), _to_screen(butt + side * CUE_BUTT * 0.6),
		Color(0, 0, 0, 0.30), maxf(1.0, _scale * 0.004)
	)


## Um trecho cônico do taco, entre duas frações do comprimento dele.
func _draw_taper(
	tip: Vector2, away: Vector2, side: Vector2, near: float, far: float, tint: Color
) -> void:
	var near_at := tip + away * CUE_LENGTH * near
	var far_at := tip + away * CUE_LENGTH * far
	var near_wide := side * lerpf(CUE_TIP, CUE_BUTT, near)
	var far_wide := side * lerpf(CUE_TIP, CUE_BUTT, far)
	draw_colored_polygon(
		PackedVector2Array([
			_to_screen(near_at + near_wide),
			_to_screen(far_at + far_wide),
			_to_screen(far_at - far_wide),
			_to_screen(near_at - near_wide),
		]),
		tint
	)


## Distância da branca até a tabela, na direção mirada. Em unidades de mesa.
func _cushion_reach(direction: Vector2) -> float:
	return _cushion_reach_from(_ball_spot(_shooter_ball()), direction)


## O mesmo, a partir de um ponto qualquer. A linha da bola atingida também para na
## tabela: ela é curta, mas com a bola já encostada na borda ela sairia do pano.
func _cushion_reach_from(spot: Vector2, direction: Vector2) -> float:
	var aim := direction.normalized()
	var reach := Rules.TABLE_WIDTH + Rules.TABLE_HEIGHT
	var edge := Rules.BALL_RADIUS
	if aim.x > 0.0001:
		reach = minf(reach, (Rules.TABLE_WIDTH - edge - spot.x) / aim.x)
	elif aim.x < -0.0001:
		reach = minf(reach, (edge - spot.x) / aim.x)
	if aim.y > 0.0001:
		reach = minf(reach, (Rules.TABLE_HEIGHT - edge - spot.y) / aim.y)
	elif aim.y < -0.0001:
		reach = minf(reach, (edge - spot.y) / aim.y)
	return maxf(0.0, reach)


## A primeira bola no caminho da branca e **onde a branca encosta nela**, em
## unidades de mesa. `ball` é -1 com o caminho livre.
##
## O recuo não é "dois raios": é o cateto que falta.
##
## A branca para quando os dois centros ficam a duas bolas de distância, e no
## triângulo formado pela linha de mira, pela perpendicular até o centro da outra
## bola e pela linha dos centros, isso é Pitágoras — `sqrt((2r)² - lateral²)`.
## Subtrair `2r` direto só acerta na batida frontal, e é justamente na batida de
## raspão que o erro fica grande: a bola fantasma aparecia depois do ponto de
## contato, e a linha de saída — que sai da **linha dos centros** — apontava para
## o lado errado.
func _impact(direction: Vector2) -> Dictionary:
	var shooter := _shooter_ball()
	var cue := _ball_spot(shooter)
	var aim := direction.normalized()
	var touch := Rules.BALL_RADIUS * 2.0
	var best := -1.0
	var hit := -1
	for ball in Rules.ball_count(state):
		if ball == shooter or not _ball_live(ball):
			continue
		var to_ball := _ball_spot(ball) - cue
		var along := to_ball.dot(aim)
		if along <= 0.0:
			continue
		var lateral := (to_ball - aim * along).length()
		if lateral > touch:
			continue
		var stop := along - sqrt(maxf(0.0, touch * touch - lateral * lateral))
		if stop < 0.0:
			continue
		if best < 0.0 or stop < best:
			best = stop
			hit = ball
	return {"ball": hit, "stop": best}


func _draw_balls() -> void:
	var radius := Rules.BALL_RADIUS * _scale
	# A escolhida ganha um anel de latão, e só quando a mesa aceita toque: fora da
	# vez o anel diria "aja aqui" numa tela em que não há o que fazer.
	var shooter := _shooter_ball() if enabled and not _playing else -1
	for ball in Rules.ball_count(state):
		if not _ball_live(ball):
			continue
		var at := _to_screen(_ball_spot(ball))
		if ball == shooter:
			draw_arc(
				at, radius * 1.55, 0.0, TAU, 32, Color(AppTheme.ACCENT, 0.9),
				maxf(2.0, radius * 0.16), true
			)
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
