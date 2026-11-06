class_name PoolView
extends Control

## A mesa de sinuca: a mesa 3D, as bolas, a mira e a tacada acontecendo.
##
## ## A animação é a própria simulação
##
## Ela não recalcula nada: [PoolRules] guarda retratos da mesa a cada punhado de
## passos e esta tela os reproduz em ordem. Uma segunda física aqui seria a forma
## clássica de a partida animada divergir da partida jogada — a bola entrando na
## tela e não entrando na regra, ou o contrário. O 3D é só desenho: a mesa 2D
## `(x, y)` vira `(x, raio, y)` na cena, e o giro das bolas sai do caminho que elas
## fizeram entre dois retratos.
##
## ## Duas camadas: a mesa em 3D, a mira em 2D por cima
##
## A mesa, as bolas e o taco são renderizados numa [SubViewport] com mundo próprio,
## e a textura dela é o fundo deste controle. A mira (linha, bola fantasma, saída
## da bola atingida) continua desenhada em 2D por cima, porque é informação e não
## objeto: ela tem de ficar nítida e da cor do tema, e não sombreada pela luz da
## mesa.
##
## A câmera olha **reto para baixo**, e é isso que mantém as duas camadas juntas.
## Vista de cima, a altura do centro das bolas é um plano paralelo à tela, e a
## perspectiva leva esse plano para a tela com uma escala e um deslocamento — a
## mesma conta linear da mesa 2D. A perspectiva ainda aparece onde importa para o
## olho (as tabelas e as bocas têm altura), sem entortar a mira.
##
## ## Mira e força são dois gestos separados, como no 8 Ball Pool
##
## Na vez de quem joga, o taco já está na mesa, atrás da bola, apontado para um
## alvo razoável, e a linha de mira mostra **onde a bola vai bater**: o traçado
## para na primeira bola do caminho, e ali aparecem a bola fantasma e a saída da
## bola atingida.
##
## - **Mira:** tocar ou arrastar na mesa aponta o taco para o dedo. Tocar numa
##   bola que pode tacar a escolhe (no mata-mata, com qual das próprias bolas se
##   taca é metade da jogada);
## - **Força:** a barra ao lado da mesa. Puxar para baixo recua o taco, soltar
##   taca. Voltar a barra até o topo antes de soltar desiste.
##
## Separar os dois é o que deixa mirar com calma: no arrasto único, a direção e a
## força saíam do mesmo dedo, e corrigir uma estragava a outra.

## Uma tacada foi pedida: com qual bola, em que direção, com que força (0 a 1) e
## onde o taco bate na bola (`x` lado, `y` altura, dentro do círculo de raio 1).
signal shot_aimed(ball: int, direction: Vector2, power: float, spin: Vector2)
## A branca foi posta, em coordenadas de mesa.
signal ball_placed(spot: Vector2)

const Rules := preload("res://core/pool_rules.gd")
const TABLE_SCENE := preload("res://assets/pool/table.glb")
const BALL_SCENE := preload("res://assets/pool/ball.glb")
const CUE_SCENE := preload("res://assets/pool/cue.glb")

## Quanto da mesa a câmera enquadra além do pano, em unidades de mesa: a borracha
## e a madeira de `art/pool/build_pool.py`, mais uma folga.
const FRAME_MARGIN := 0.15
## Ângulo de visão vertical. Estreito: perspectiva o bastante para as tabelas
## terem altura, pouco o bastante para as bolas da borda não parecerem maiores.
const FOV := 28.0

## As bocas desenhadas ficam recuadas para dentro da madeira (ver
## `art/pool/build_pool.py`). A física captura a bola no ponto de
## [constant PoolRules.POCKETS]; daqui a bola é levada até o buraco e cai.
const CORNER_RECESS := 0.045
const SIDE_RECESS := 0.03
## Duração da queda na caçapa, em segundos.
const SINK_TIME := 0.22
const SINK_DEPTH := 0.09

## A barra de força: largura, e quanto de cada lado da mesa fica reservado para
## ela e para o seletor de efeito. Pixels da base.
const BAR_WIDTH := 34.0
const BAR_ROOM := 64.0
## Abaixo disto soltar a barra não taca: é desistir.
const POWER_DEAD := 0.04
## O seletor de efeito: o raio da bolinha ao lado da mesa e o da bola grande
## que abre por cima dela, em pixels da base.
const SPIN_ICON := 22.0
const SPIN_BIG := 110.0
## Até onde o ponto de batida chega na bola, como no [method PoolRules.shot].
const SPIN_EDGE := 0.998

## Quanto o taco recua com a força, em unidades de mesa. O recuo **é** a barra de
## força: um taco puxado para trás diz quanta pancada vem sem nenhum número na
## tela, que é como se lê força numa mesa de verdade.
const CUE_PULL_MIN := 0.03
const CUE_PULL_MAX := 0.22
## O cabo sobe um pouco, como na mão de quem joga, e passa por cima da madeira.
const CUE_TILT := 5.0

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
		# Fora de uma reprodução a mesa é o estado, e uma fita velha não pode mais
		# responder por ela — numa partida nova ela seria a mesa da anterior.
		if not _playing:
			_frames = []
			_frame_live = []
		_sync_balls(false)
		_sync_cue()
		_render()
		queue_redraw()

## A mesa aceita mira. Falso na vez do outro e enquanto a tacada corre.
var enabled := false:
	set(value):
		var starting := value and not enabled
		enabled = value
		if not value:
			_steering = false
			_pulling = false
			_power = 0.0
			_spin = Vector2.ZERO
			_spin_open = false
			_spinning = false
			_aim = Vector2.ZERO
		elif starting or _aim == Vector2.ZERO:
			# A vez começa com o taco já mirando num alvo que faz sentido: o jogador
			# corrige a partir dali em vez de começar do nada. Um `enabled = true`
			# repetido no meio da vez (a cena atualiza nomes, por exemplo) não mexe
			# na mira que ele já ajustou.
			_aim = _default_aim()
		_sync_cue()
		_render()
		queue_redraw()

## Os retratos em reprodução, e onde ela está.
var _frames: Array[PackedFloat64Array] = []
var _frame_live: Array[PackedByteArray] = []
var _frame := 0.0
var _playing := false

## Para onde o taco aponta, unitário, em coordenadas de mesa. Zero fora da vez.
var _aim := Vector2.ZERO
## Quanto a barra está puxada, de 0 a 1.
var _power := 0.0
## O dedo está mirando na mesa, ou puxando a barra.
var _steering := false
var _pulling := false
## Onde o taco bate na bola: `x` lado (direita positiva), `y` altura (em cima
## positiva), dentro do círculo de raio 1. Volta a zero depois de cada tacada.
var _spin := Vector2.ZERO
## A bola grande do seletor está aberta, e o dedo está arrastando o ponto nela.
var _spin_open := false
var _spinning := false
## A bola escolhida para tacar, ou -1 para "a primeira que servir". Ver [method
## _shooter_ball].
var _shooter := -1
var _scale := 1.0
var _origin := Vector2.ZERO

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _cue: Node3D = null
var _ball_mesh: Mesh = null
var _balls: Array[MeshInstance3D] = []
## Onde cada bola estava no último quadro desenhado, para o giro.
var _last_spots: Array[Vector2] = []
## Quedas em curso: bola -> {from: Vector3, to: Vector3, t: float}.
var _sinks := {}
var _materials := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# O taco sai pela borda da mesa, e sem recorte ele atravessaria a coluna dos
	# jogadores. Recortado, ele some pela borda — que é o que um taco faz quando o
	# jogador se afasta da mesa.
	clip_contents = true
	_build_world()
	resized.connect(_on_resized)
	_on_resized()
	set_process(false)


# --- a cena 3D ----------------------------------------------------------------


func _build_world() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.64, 0.70)
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)

	# A luminária de bar: uma luz quase a pino, para as sombras das bolas caírem
	# rentes a elas e não atravessarem a mesa.
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-72.0, 18.0, 0.0)
	lamp.light_energy = 1.15
	lamp.light_color = Color(1.0, 0.96, 0.90)
	lamp.shadow_enabled = true
	lamp.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	lamp.directional_shadow_max_distance = 8.0
	_viewport.add_child(lamp)

	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_viewport.add_child(_camera)

	_viewport.add_child(TABLE_SCENE.instantiate())

	var ball_source := BALL_SCENE.instantiate()
	var found := ball_source.find_children("*", "MeshInstance3D", true, false)
	_ball_mesh = (found[0] as MeshInstance3D).mesh
	ball_source.free()

	_cue = CUE_SCENE.instantiate()
	_cue.visible = false
	_viewport.add_child(_cue)


## A câmera enquadra a mesa inteira no tamanho que o controle tiver, e a
## [SubViewport] renderiza na densidade de pixels da tela: no tamanho lógico, o
## 3D sairia borrado num celular de tela densa.
func _on_resized() -> void:
	if _viewport == null or size.x < 1.0 or size.y < 1.0:
		return
	var density := get_viewport().get_final_transform().get_scale().x if is_inside_tree() else 1.0
	_viewport.size = Vector2i((size * density).round())

	var half_w := Rules.TABLE_WIDTH * 0.5 + FRAME_MARGIN
	var half_h := Rules.TABLE_HEIGHT * 0.5 + FRAME_MARGIN
	var reach := tan(deg_to_rad(FOV * 0.5))
	# Dos lados fica o lugar da barra de força e do seletor de efeito.
	var room := maxf(1.0, size.x - BAR_ROOM * 2.0)
	var distance := maxf(half_h, half_w / (room / size.y)) / reach
	_camera.position = Vector3(
		Rules.TABLE_WIDTH * 0.5, Rules.BALL_RADIUS + distance, Rules.TABLE_HEIGHT * 0.5
	)
	_layout()
	_sync_balls(false)
	_sync_cue()
	_render()
	queue_redraw()


## Pede um quadro novo da mesa. Parada, ela não é redesenhada a cada quadro: a
## mesa de quem espera a vez do outro não gasta bateria.
func _render() -> void:
	if _viewport == null:
		return
	var live := _playing or not _sinks.is_empty() or _steering or _pulling
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_ONCE
	)


func _material_for(ball: int) -> StandardMaterial3D:
	var key := "cue"
	if not Rules.has_cue_ball(state):
		key = "g%d" % Rules.kind_of_ball(state, ball)
	elif ball != Rules.cue_ball(state):
		key = "n%d" % Rules.kind_of_ball(state, ball)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_texture = load("res://assets/pool/balls/ball_%s.png" % key)
		material.roughness = 0.12
		material.clearcoat_enabled = true
		material.clearcoat = 1.0
		_materials[key] = material
	return _materials[key]


## Põe cada bola onde a fita ou o estado mandam, e gira a bola pelo caminho que
## ela fez desde o quadro anterior.
##
## `roll` falso é um salto (estado novo, resincronização): a bola vai para o
## lugar sem girar, porque um salto não é um caminho rolado.
func _sync_balls(roll: bool) -> void:
	if state == null or _viewport == null:
		return
	var count := Rules.ball_count(state)
	while _balls.size() < count:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _ball_mesh
		# Cada bola começa num giro diferente: alinhadas, as sete mostrariam o
		# número do mesmo jeito, e o triângulo pareceria um carimbo.
		mesh.basis = Basis.from_euler(Vector3(1.3, 0.7 * _balls.size(), 0.4 * _balls.size()))
		_viewport.add_child(mesh)
		_balls.append(mesh)
		_last_spots.append(Vector2.INF)
	while _balls.size() > count:
		_balls.pop_back().queue_free()
		_last_spots.pop_back()

	for ball in count:
		var node := _balls[ball]
		node.material_override = _material_for(ball)
		if _sinks.has(ball):
			continue
		var spot := _ball_spot(ball)
		var live := _ball_live(ball)
		if not live and roll and node.visible and _last_spots[ball] != Vector2.INF:
			_start_sink(ball, _last_spots[ball])
			continue
		node.visible = live
		if not live:
			_last_spots[ball] = Vector2.INF
			continue
		var moved := spot - _last_spots[ball]
		if roll and _last_spots[ball] != Vector2.INF and moved.length() > 0.00001:
			# Rolar sem escorregar: o eixo é o pano cruzado com o caminho, e o ângulo é
			# o caminho dividido pelo raio.
			var axis := Vector3(moved.y, 0.0, -moved.x).normalized()
			node.basis = (Basis(axis, moved.length() / Rules.BALL_RADIUS) * node.basis).orthonormalized()
		node.position = Vector3(spot.x, Rules.BALL_RADIUS, spot.y)
		_last_spots[ball] = spot


func _start_sink(ball: int, from: Vector2) -> void:
	_sinks[ball] = {
		"from": Vector3(from.x, Rules.BALL_RADIUS, from.y),
		"to": _hole_of(from),
		"t": 0.0,
	}
	_last_spots[ball] = Vector2.INF
	set_process(true)
	_render()


## O buraco desenhado mais perto de onde a bola foi capturada.
static func _hole_of(spot: Vector2) -> Vector3:
	var best := Vector2.ZERO
	for pocket: Vector2 in Rules.POCKETS:
		var outward := Vector2(
			-1.0 if pocket.x <= 0.0 else (1.0 if pocket.x >= Rules.TABLE_WIDTH else 0.0),
			-1.0 if pocket.y <= 0.0 else (1.0 if pocket.y >= Rules.TABLE_HEIGHT else 0.0),
		)
		var hole := pocket + outward.normalized() * CORNER_RECESS
		if outward.x == 0.0:
			hole = Vector2(pocket.x, (Rules.TABLE_HEIGHT if outward.y > 0.0 else 0.0) + outward.y * SIDE_RECESS)
		if best == Vector2.ZERO or spot.distance_to(hole) < spot.distance_to(best):
			best = hole
	return Vector3(best.x, Rules.BALL_RADIUS, best.y)


func _advance_sinks(delta: float) -> void:
	for ball: int in _sinks.keys():
		var sink: Dictionary = _sinks[ball]
		sink["t"] = minf(1.0, float(sink["t"]) + delta / SINK_TIME)
		var t: float = sink["t"]
		var node := _balls[ball]
		# Desliza até a boca na primeira metade, cai na segunda.
		var slide := minf(1.0, t * 2.0)
		var at: Vector3 = (sink["from"] as Vector3).lerp(sink["to"], slide)
		at.y -= maxf(0.0, t * 2.0 - 1.0) * SINK_DEPTH
		node.position = at
		if t >= 1.0:
			node.visible = false
			_sinks.erase(ball)


## O taco 3D atrás da bola, durante a vez inteira de quem joga, recuado pela
## barra de força.
func _sync_cue() -> void:
	if _cue == null:
		return
	_cue.visible = _cue_showing()
	if not _cue.visible:
		return
	var cue_spot := _ball_spot(_shooter_ball())
	var away := -_aim
	var gap := Rules.BALL_RADIUS + lerpf(CUE_PULL_MIN, CUE_PULL_MAX, _power)
	# O efeito leva a ponta para o ponto escolhido na bola: para o lado (à
	# direita de quem taca, com o y da mesa crescendo para baixo) e para cima.
	var right := Vector2(-_aim.y, _aim.x)
	var tip := cue_spot + away * gap + right * _spin.x * Rules.BALL_RADIUS * 0.7
	var lift := _spin.y * Rules.BALL_RADIUS * 0.7
	# O modelo deita em +X com a ponta na origem: gira em Y até +X apontar para
	# trás da bola, e em Z para o cabo subir.
	_cue.basis = Basis(Vector3.UP, atan2(-away.y, away.x)) * Basis(Vector3.BACK, deg_to_rad(CUE_TILT))
	_cue.position = Vector3(tip.x, Rules.BALL_RADIUS + lift, tip.y)


# --- reprodução ---------------------------------------------------------------


## Reproduz a tacada que a regra acabou de simular.
func play(spots: Array[PackedFloat64Array], live: Array[PackedByteArray]) -> void:
	_frames = spots
	_frame_live = live
	_frame = 0.0
	_playing = not spots.is_empty()
	set_process(_playing)
	_render()
	queue_redraw()


## Segundos que faltam da tacada em curso. A cena espera por isto antes de
## resolver o que a tacada causou — ver o mesmo padrão no tabuleiro de xadrez.
func remaining_animation() -> float:
	if not _playing:
		return SINK_TIME if not _sinks.is_empty() else 0.0
	# A última bola a cair começa a queda no último retrato.
	return maxf(0.0, (float(_frames.size()) - _frame) / _playback_fps()) + SINK_TIME


func _playback_fps() -> float:
	# A fita foi amostrada a cada N passos de [constant PoolRules.STEP], então
	# reproduzi-la nesse mesmo ritmo devolve o tempo real da tacada. Reproduzir por
	# quadro da tela faria a mesma tacada durar diferente em cada aparelho.
	return 1.0 / (Rules.STEP * float(maxi(1, Rules.TRACE_EVERY)))


func _process(delta: float) -> void:
	if _playing:
		_frame += delta * _playback_fps()
		if _frame >= float(_frames.size()) - 1.0:
			_frame = float(_frames.size()) - 1.0
			_playing = false
		_sync_balls(true)
	_advance_sinks(delta)
	if not _playing and _sinks.is_empty():
		set_process(false)
	_render()
	queue_redraw()


# --- gesto --------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not enabled or state == null or _playing:
		return
	var press := event as InputEventMouseButton
	if press != null and press.button_index == MOUSE_BUTTON_LEFT:
		if press.pressed:
			_press(press.position)
		else:
			_release(press.position)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and (_steering or _pulling or _spinning):
		_drag(motion.position)
		accept_event()


## O toque começa uma de três coisas: **puxar a barra**, **escolher a bola** ou
## **mirar**.
##
## Qual delas sai do lugar em que o dedo encostou: na barra é força; em cima de
## uma bola que pode tacar é escolha; em qualquer outro lugar da mesa, o taco
## passa a apontar para o dedo. Com a branca na mão, o toque põe a branca.
func _press(at: Vector2) -> void:
	if Rules.ball_in_hand(state):
		var spot := _to_table(at)
		if Rules._placeable(state, spot, Rules.cue_ball(state)):
			ball_placed.emit(spot)
		return
	if _shooter_ball() < 0:
		return

	# Com a bola grande aberta, o toque é dela: dentro escolhe o ponto, fora fecha.
	if _spin_open:
		if at.distance_to(_spin_center()) <= _spin_radius() * 1.15:
			_spinning = true
			_drag(at)
		else:
			_spin_open = false
			queue_redraw()
		return
	if at.distance_to(_spin_icon_center()) <= SPIN_ICON * 1.6:
		_spin_open = true
		queue_redraw()
		return

	if _bar_rect().grow(BAR_WIDTH * 0.5).has_point(at):
		_pulling = true
		_drag(at)
		return

	var picked := _ball_under(at)
	if picked >= 0:
		if picked != _shooter_ball():
			_shooter = picked
			_aim = _default_aim()
			_sync_cue()
			queue_redraw()
		return

	_steering = true
	_drag(at)


func _drag(at: Vector2) -> void:
	if _spinning:
		var local := (at - _spin_center()) / _spin_radius()
		# A tela cresce para baixo e a altura para cima.
		_spin = Vector2(local.x, -local.y).limit_length(SPIN_EDGE)
	elif _pulling:
		var bar := _bar_rect()
		_power = clampf((at.y - bar.position.y) / bar.size.y, 0.0, 1.0)
	elif _steering:
		var toward := _to_table(at) - _ball_spot(_shooter_ball())
		if toward.length() > Rules.BALL_RADIUS:
			_aim = toward.normalized()
	_sync_cue()
	_render()
	queue_redraw()


## Soltar a barra taca com a força em que ela estava; soltar a mira só a fixa.
func _release(at: Vector2) -> void:
	if _spinning:
		_drag(at)
		_spinning = false
		return
	if _steering:
		_drag(at)
		_steering = false
		_render()
		return
	if not _pulling:
		return
	_drag(at)
	_pulling = false
	var power := _power
	_power = 0.0
	_sync_cue()
	_render()
	queue_redraw()
	if power < POWER_DEAD or _aim == Vector2.ZERO:
		return
	# Cópias locais: o primeiro a ouvir o sinal (a cena) fecha a mesa e zera
	# `_aim`, e quem ouvisse depois receberia o membro já zerado.
	var aim := _aim
	var ball := _shooter_ball()
	var spin := _spin
	_spin = Vector2.ZERO
	shot_aimed.emit(ball, aim, power, spin)


## Para onde o taco aponta quando a vez começa: a bola da vez na brasileira, a
## bola do adversário mais perto no mata-mata. Sem alvo nenhum, para a direita.
func _default_aim() -> Vector2:
	if state == null or _shooter_ball() < 0:
		return Vector2.ZERO
	var from := _ball_spot(_shooter_ball())
	var best := Vector2.RIGHT
	var closest := INF
	var seat := Rules.turn_of(state)
	for ball in Rules.ball_count(state):
		if ball == _shooter_ball() or not _ball_live(ball):
			continue
		if Rules.has_cue_ball(state):
			if ball != Rules.target_ball(state):
				continue
		elif Rules.kind_of_ball(state, ball) == Rules.group_of(seat):
			continue
		var toward := _ball_spot(ball) - from
		if toward.length() > 0.0001 and toward.length() < closest:
			closest = toward.length()
			best = toward.normalized()
	return best


## O taco aparece na vez de quem joga, parado atrás da bola, e não durante a
## tacada nem com a branca na mão (aí o que se decide é onde ela fica).
func _cue_showing() -> bool:
	return (
		enabled and not _playing and state != null and _aim != Vector2.ZERO
		and _shooter_ball() >= 0 and not Rules.ball_in_hand(state)
	)


## A bolinha do seletor de efeito: do lado direito da mesa, espelhando a barra,
## na altura do topo do pano.
func _spin_icon_center() -> Vector2:
	var bar := _bar_rect()
	var mirror := size.x - bar.get_center().x
	return Vector2(mirror, bar.position.y + SPIN_ICON + 4.0)


## A bola grande abre no meio da mesa, do maior tamanho que couber nela.
func _spin_center() -> Vector2:
	return _to_screen(Vector2(Rules.TABLE_WIDTH, Rules.TABLE_HEIGHT) * 0.5)


func _spin_radius() -> float:
	return minf(SPIN_BIG, Rules.TABLE_HEIGHT * _scale * 0.42)


## A barra de força: em pé, à esquerda da mesa, da altura do pano.
func _bar_rect() -> Rect2:
	var top := _to_screen(Vector2(0.0, 0.0)).y
	var bottom := _to_screen(Vector2(0.0, Rules.TABLE_HEIGHT)).y
	var x := maxf(4.0, _to_screen(Vector2.ZERO).x - (FRAME_MARGIN * _scale) - BAR_ROOM * 0.5 - BAR_WIDTH * 0.5)
	return Rect2(x, top, BAR_WIDTH, bottom - top)


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


## A conta tela↔mesa, tirada da câmera: onde a origem da mesa e um ponto uma
## unidade à direita caem na tela, na altura do centro das bolas. Com a câmera
## olhando reto para baixo isso é uma escala e um deslocamento (ver o cabeçalho).
func _layout() -> void:
	if _camera == null or not _camera.is_inside_tree() or _viewport.size.x == 0:
		return
	var density := float(_viewport.size.x) / size.x
	var zero := _camera.unproject_position(Vector3(0.0, Rules.BALL_RADIUS, 0.0)) / density
	var one := _camera.unproject_position(Vector3(1.0, Rules.BALL_RADIUS, 0.0)) / density
	_origin = zero
	_scale = one.x - zero.x


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
	if _viewport != null:
		draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, size), false)
	if state == null:
		return
	# A mira corre por cima das bolas: ela é informação, não objeto. O taco é 3D
	# e mora na cena.
	_draw_aim()
	_draw_shooter_ring()
	if _cue_showing():
		_draw_power_bar()
		_draw_spin_icon()
	if _spin_open and _cue_showing():
		_draw_spin_picker()


## A escolhida ganha um anel de latão, e só quando a mesa aceita toque: fora da
## vez o anel diria "aja aqui" numa tela em que não há o que fazer.
func _draw_shooter_ring() -> void:
	if not enabled or _playing:
		return
	var shooter := _shooter_ball()
	if shooter < 0 or not _ball_live(shooter):
		return
	var radius := Rules.BALL_RADIUS * _scale
	draw_arc(
		_to_screen(_ball_spot(shooter)), radius * 1.55, 0.0, TAU, 32,
		Color(AppTheme.ACCENT, 0.9), maxf(2.0, radius * 0.16), true
	)


## Uma bola branca com o ponto vermelho de onde o taco vai bater.
func _draw_cue_face(center: Vector2, radius: float, crosshair: bool) -> void:
	draw_circle(center + Vector2(radius * 0.06, radius * 0.08), radius, Color(0, 0, 0, 0.35))
	draw_circle(center, radius, Color("f2efe8"))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0, 0, 0, 0.35), maxf(1.0, radius * 0.04), true)
	if crosshair:
		var ink := Color(0, 0, 0, 0.18)
		draw_line(center - Vector2(radius, 0.0), center + Vector2(radius, 0.0), ink, 1.5, true)
		draw_line(center - Vector2(0.0, radius), center + Vector2(0.0, radius), ink, 1.5, true)
		draw_arc(center, radius * 0.5, 0.0, TAU, 40, ink, 1.5, true)
	# Altura para cima na bola é para cima na tela.
	var dot := center + Vector2(_spin.x, -_spin.y) * radius
	draw_circle(dot, maxf(3.0, radius * 0.14), Color("c62f2f"))


## A bolinha ao lado da mesa: mostra o efeito escolhido e abre o seletor.
func _draw_spin_icon() -> void:
	_draw_cue_face(_spin_icon_center(), SPIN_ICON, false)


## A bola grande do seletor, por cima da mesa escurecida: tocar ou arrastar
## nela escolhe o ponto, tocar fora fecha.
func _draw_spin_picker() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	var center := _spin_center()
	var radius := _spin_radius()
	_draw_cue_face(center, radius, true)
	var font := AppTheme.font(400)
	var text := "Toque onde o taco bate"
	var body := AppTheme.SIZE_BODY_S
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, body).x
	draw_string(
		font, center + Vector2(-wide * 0.5, radius + body + 10.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, body, AppTheme.TEXT
	)


## A barra de força, como no 8 Ball Pool: um trilho em pé ao lado da mesa, e o
## que já foi puxado aceso de cima para baixo, do verde ao vermelho. Parada, ela
## mostra só o trilho e uma seta para baixo dizendo para onde puxar.
func _draw_power_bar() -> void:
	var bar := _bar_rect()
	var round_box := StyleBoxFlat.new()
	round_box.bg_color = Color(0, 0, 0, 0.45)
	round_box.border_color = Color(AppTheme.TEXT, 0.35)
	round_box.set_border_width_all(2)
	round_box.set_corner_radius_all(int(BAR_WIDTH * 0.5))
	draw_style_box(round_box, bar)
	if _power > 0.0:
		var fill := Rect2(bar.position, Vector2(bar.size.x, bar.size.y * _power)).grow(-4.0)
		var heat := Color("5f9e63").lerp(Color("d9c341"), minf(1.0, _power * 2.0))
		if _power > 0.5:
			heat = Color("d9c341").lerp(Color("c9524d"), (_power - 0.5) * 2.0)
		var lit := StyleBoxFlat.new()
		lit.bg_color = heat
		lit.set_corner_radius_all(int(BAR_WIDTH * 0.5) - 4)
		draw_style_box(lit, fill)
		return
	var mid := bar.get_center()
	var wing := BAR_WIDTH * 0.22
	for offset: float in [-14.0, 6.0]:
		var tip := mid + Vector2(0.0, offset + wing)
		draw_polyline(
			PackedVector2Array([tip + Vector2(-wing, -wing), tip, tip + Vector2(wing, -wing)]),
			Color(AppTheme.TEXT, 0.6), 3.0, true
		)


## A linha de mira, e ela para onde a bola vai parar.
##
## O traçado segue reto até a primeira bola no caminho e marca o ponto de contato.
## Sem essa parada, a linha atravessaria a mesa inteira e prometeria uma trajetória
## que não existe — o pior tipo de ajuda, a que mente.
func _draw_aim() -> void:
	if not _cue_showing():
		return
	var direction := _aim
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
