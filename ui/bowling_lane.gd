class_name BowlingLane
extends Node3D

## A pista com física de verdade: recebe um arremesso, deixa a Jolt rolar a bola e
## derrubar os pinos, e diz quais caíram.
##
## É a única física do app que não mora em `core/`. A da sinuca é feita à mão para
## dar a mesma mesa bit a bit nos dois aparelhos; pinos batendo uns nos outros em
## três dimensões não cabem nisso, e por isso o lance do boliche carrega o
## resultado (ver o cabeçalho de `BowlingRules`). Esta cena só **produz** a
## máscara, no aparelho de quem arremessa, e ela vira o lance.
##
## Os outros aparelhos não rodam física: seguem os quadros que quem arremessa
## manda (`snapshot` de lá, `follow` daqui), com os corpos parados e postos onde
## o quadro diz. A Jolt daria outra jogada em cada aparelho.
##
## Eixos: a pista corre para -Z a partir da linha de falta (z = 0), x é o lado
## (positivo à direita de quem joga) e o tampo é y = 0. As medidas são as de
## `art/bowling/build_bowling.py`, que gera os modelos.

## A jogada parou: `mask` são os pinos que estavam armados e caíram.
signal settled(mask: int)

const LANE_SCENE := preload("res://assets/bowling/lane.glb")
const PIN_SCENE := preload("res://assets/bowling/pin.glb")
const BALL_SCENE := preload("res://assets/bowling/ball.glb")

# --- medidas oficiais (iguais às de build_bowling.py) -------------------------

const LANE_W := 1.0541
const HEAD_PIN := 18.288
const PIN_SPACING := 0.3048
const DECK_END := 19.16
const GUTTER_W := 0.235
const CAP_W := 0.08
const APPROACH := 3.0
const BALL_R := 0.109
const PIN_H := 0.381
## Óleo nos primeiros 40 pés: ali a bola desliza, e o gancho só aparece no seco.
const OIL_LEN := 12.19

# --- física: botões de ajuste ---------------------------------------------------

const BALL_MASS := 6.5
const PIN_MASS := 1.5
## Centro de massa do pino, a 5,7 pol da base.
const PIN_COM := 0.145
const OIL_FRICTION := 0.02
const DRY_FRICTION := 0.2
const PIN_FRICTION := 0.35
const PIN_BOUNCE := 0.3
const PIN_ROLL_DAMP := 1.0

# --- o arremesso: o que cada parâmetro vale -----------------------------------

## Velocidade com a força cheia solta no ponto certo, em m/s (uns 29 km/h), e com
## a força mínima (uns 14 km/h).
const FULL_SPEED := 8.0
const MIN_SPEED := 4.0
## Direção cheia (parâmetro ±1), em graus para a direita ou a esquerda.
const MAX_ANGLE := 3.5
## Erro de direção de um timing no limite (±1): cedo puxa para a esquerda, tarde
## empurra para a direita.
const TIMING_ANGLE := 1.5
## Quanto da velocidade um timing no limite tira. Menor que antes de existir a
## força: agora é ela quem decide a velocidade.
const TIMING_SLOW := 0.15
## Giro de lado com o efeito cheio, em rad/s. É ele que vira gancho no seco.
const MAX_SPIN := 15.0
## Quanto da rolagem para frente a bola já leva ao sair da mão (o resto ela pega
## no atrito, derrapando).
const INITIAL_ROLL := 0.3
## A bola sai logo depois da linha de falta.
const START_Z := -0.05

# --- quando a jogada acaba ----------------------------------------------------

## Pino com o eixo mais deitado que isso caiu.
const FALL_TILT := 45.0
const REST_SPEED := 0.05
const REST_SPIN := 0.5
## Depois que a bola chega aos pinos: espera mínima e teto.
const AFTER_MIN := 1.0
const AFTER_MAX := 4.0
## Teto da jogada inteira, para uma bola fraca que para no meio da pista.
const MAX_TIME := 12.0

# --- em rede: a jogada em quadros ---------------------------------------------

## Corpos num quadro (`snapshot`): a bola e os dez pinos, nesta ordem.
const BODIES := 1 + BowlingRules.PINS
## Inteiros por corpo: a posição em milímetros e o quatérnio × 10000.
const POSE_INTS := 7
const POSE_MM := 1000.0
const POSE_QUAT := 10000.0
## Atraso de propósito ao seguir os quadros: folga para os que a rede entrega
## fora do ritmo, sem a bola parar no meio.
const FOLLOW_DELAY := 0.2

# --- desenho: o verniz ----------------------------------------------------------

## O reflexo no verniz é um truque barato (a Compatibility do celular não tem
## SSR): cada desenho ganha um gêmeo espelhado embaixo do tampo, e a madeira fica
## um pouco transparente por cima dele. Quanto da madeira cobre o gêmeo.
const VARNISH_ALPHA := 0.6
const VARNISH_ROUGHNESS := 0.12
## O fundo embaixo do reflexo: madeira escura, para a pista transparente não
## escurecer com o fundo da cena.
const UNDERCOAT := Color(0.42, 0.32, 0.2)
const UNDERCOAT_DEPTH := 0.5
const UNDERCOAT_PAST := 6.0
## As placas com o número de cada pista, na fachada da máquina: a do meio é a de
## quem joga, e as vizinhas do salão (`build_bowling.py`) seguem a conta.
const LANE_NUMBER := 7
const NEIGHBOURS := [-2, -1, 1, 2]
const PITCH := LANE_W + 2.0 * (GUTTER_W + CAP_W)
const PLATE_AT := Vector3(0.0, 0.935, -(HEAD_PIN - 0.5) + 0.02)
## A camada do cenário (pista, salão, máquina). A luz do deck fica fora dela: na
## Compatibility cada luz é mais uma passada por objeto, e somada sobre a madeira
## transparente lavava o deck e riscava uma faixa cinza na pista.
const SCENERY_LAYER := 2
## Espelha em y = 0, o tampo.
const MIRROR := Transform3D(Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.BACK), Vector3.ZERO)

## A jogada em curso. Falso antes do primeiro arremesso e depois de `settled`.
var rolling := false
## Mostrando a jogada de outro aparelho pelos quadros (`follow`), sem física.
var following := false
## Cor da bola do próximo arremesso (a de quem joga).
var ball_color := Color.WHITE
## A textura da loja da bola de quem joga, ou `null` para o mármore na cor.
var ball_skin: Texture2D = null
var ball: RigidBody3D = null
## Um por pino (índice 0 = pino 1); `null` nos que não estão armados.
var pins: Array[RigidBody3D] = []

var _time := 0.0
var _after := -1.0
var _on_oil := false
var _pin_shape: Shape3D = null
## Desenho suave. A física anda a 60 quadros por segundo e a tela do celular a 90
## ou 120: desenhada no corpo, a bola só andava nos quadros de física e "travava"
## nos outros (o stuttering da 1.48). O desenho de cada corpo é um filho
## `top_level`, posto entre os dois últimos quadros de física na fração em que o
## quadro da tela cai. Corpo -> [desenho, transformada anterior, atual, reflexo].
var _smooth := {}
## Os quadros seguidos, `[segundos, poses]` em ordem, e o ponto da jogada que a
## tela mostra agora.
var _frames: Array = []
var _clock := 0.0


func _init() -> void:
	pins.resize(BowlingRules.PINS)


func _ready() -> void:
	var scenery := LANE_SCENE.instantiate()
	add_child(scenery)
	for node in scenery.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.layers = SCENERY_LAYER
		# O salão é enfeite de longe: sem sombra, que dobrava o passe de sombra.
		if geometry.name.begins_with("hall_"):
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_varnish()
	_number_plates()
	_build_colliders()


## Onde fica cada pino, na ordem oficial: 1 na frente, 7 a 10 da esquerda para a
## direita de quem joga.
static func pin_spot(pin: int) -> Vector3:
	var row := 0
	while (row + 1) * (row + 2) / 2 <= pin:
		row += 1
	var slot := pin - row * (row + 1) / 2
	var depth := float(row) * PIN_SPACING * sin(deg_to_rad(60.0))
	return Vector3((float(slot) - float(row) * 0.5) * PIN_SPACING, 0.0, -(HEAD_PIN + depth))


## O arremesso a partir dos parâmetros: posição na linha, direção, efeito
## (positivo curva para a direita) e timing (0 é o ponto certo, negativo é cedo),
## de -1 a 1; e a força, de 0 a 1 (sem ela, cheia).
static func launch(params: PackedFloat32Array) -> Dictionary:
	var spot := params[0] * (LANE_W * 0.5 - BALL_R)
	var angle := deg_to_rad(params[1] * MAX_ANGLE + params[3] * TIMING_ANGLE)
	var power := params[4] if params.size() > 4 else 1.0
	var speed := lerpf(MIN_SPEED, FULL_SPEED, power) * (1.0 - absf(params[3]) * TIMING_SLOW)
	var forward := Vector3(sin(angle), 0.0, -cos(angle))
	# Giro em volta da direção de viagem: o atrito no seco empurra a bola para o
	# lado contrário ao deslize do ponto de contato, e é esse o gancho.
	var side := forward * params[2] * MAX_SPIN
	var roll := Vector3.UP.cross(forward) * (speed / BALL_R) * INITIAL_ROLL
	return {
		"position": Vector3(spot, BALL_R + 0.001, START_Z),
		"velocity": forward * speed,
		"spin": side + roll,
	}


## Arma os pinos de `mask` no lugar exato e tira a bola. Os pinos são refeitos do
## zero, e não só reposicionados: a mesma armação dá a mesma jogada.
func rack(mask: int) -> void:
	rolling = false
	following = false
	_frames.clear()
	for pin in BowlingRules.PINS:
		if pins[pin] != null:
			_drop(pins[pin])
			pins[pin] = null
	if ball != null:
		_drop(ball)
		ball = null
	for pin in BowlingRules.PINS:
		if mask & (1 << pin):
			pins[pin] = _make_pin(pin)


func throw(params: PackedFloat32Array) -> void:
	var start := launch(params)
	_spawn_ball(start["position"])
	# No óleo, o atrito da bola é o do óleo: a Godot usa o menor dos dois atritos
	# no contato, então a pista (seco) desliza como óleo até a bola passar dele.
	ball.physics_material_override = _material(OIL_FRICTION, 0.1)
	_on_oil = true
	ball.linear_velocity = start["velocity"]
	ball.angular_velocity = start["spin"]
	_time = 0.0
	_after = -1.0
	rolling = true


## Um quadro da jogada de outro aparelho, no passo de física `step` dela. No
## primeiro, os corpos param de simular; daí em diante a tela os põe entre os
## dois quadros em volta do ponto que ela mostra (`_follow_frames`).
func follow(step: int, poses: PackedInt32Array) -> void:
	var at := float(step) / Engine.physics_ticks_per_second
	if not following:
		following = true
		rolling = false
		_frames.clear()
		_clock = at - FOLLOW_DELAY
		var start: Variant = pose_of(poses, 0)
		_spawn_ball(start.origin if start != null else Vector3(0.0, BALL_R, START_Z))
		for body in _bodies():
			body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			body.freeze = true
	if _frames.is_empty() or at > _frames[-1][0]:
		_frames.append([at, poses])
	elif is_equal_approx(at, _frames[-1][0]):
		_frames[-1][1] = poses


## A tela já mostrou o último quadro recebido.
func caught_up() -> bool:
	return following and not _frames.is_empty() and _clock >= _frames[-1][0]


func _bodies() -> Array[RigidBody3D]:
	var bodies: Array[RigidBody3D] = [ball]
	for body in pins:
		if body != null:
			bodies.append(body)
	return bodies


func _spawn_ball(at: Vector3) -> void:
	if ball != null:
		_drop(ball)
	ball = RigidBody3D.new()
	ball.name = "Ball"
	ball.mass = BALL_MASS
	ball.continuous_cd = true
	_no_damping(ball)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BALL_R
	shape.shape = sphere
	ball.add_child(shape)
	var visual := BALL_SCENE.instantiate()
	tint_ball(visual, ball_color, ball_skin)
	ball.add_child(visual)
	ball.position = at
	add_child(ball)
	_track(ball, visual)


## Pinta a bola (o material `ball`; os furos ficam como estão): a textura da
## loja (`Cosmetics`) quando há, senão o mármore cinza na cor do assento.
static func tint_ball(node: Node, color: Color, skin: Texture2D = null) -> void:
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (found as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var source := mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or source.resource_name != "ball":
				continue
			if color == Color.WHITE and skin == null:
				# O mármore como veio; e sem material novo, que o modo sem tela reclama.
				(found as MeshInstance3D).set_surface_override_material(surface, null)
				continue
			var painted := source.duplicate() as StandardMaterial3D
			if skin != null:
				painted.albedo_texture = skin
				_finish_ball(painted, Cosmetics.ball_params(skin))
			else:
				painted.albedo_color = color
			(found as MeshInstance3D).set_surface_override_material(surface, painted)


## O material das bolas especiais da loja (`Cosmetics.ball_params`). A física
## não vê nada disto.
static func _finish_ball(material: StandardMaterial3D, params: Dictionary) -> void:
	if params.has("metallic"):
		material.metallic = params["metallic"]
	if params.has("roughness"):
		material.roughness = params["roughness"]
	if params.has("glow"):
		# A própria textura acende: o escuro dela quase não brilha.
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_texture = material.albedo_texture
		# Multiplica, e não soma: somada ao branco, a bola inteira virava luz.
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = params["glow"]
	if params.has("alpha"):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, 1, 1, params["alpha"])
		material.clearcoat_enabled = true


## Os pinos armados que caíram até agora.
func knocked() -> int:
	var mask := 0
	for pin in BowlingRules.PINS:
		if pins[pin] != null and is_down(pins[pin].global_transform):
			mask |= 1 << pin
	return mask


## Onde está cada corpo agora (ver `BODIES`), em inteiros. É o quadro que o
## aparelho que roda a física manda aos outros enquanto a bola rola: eles mostram
## a jogada daqui, e não a física deles, que daria outra. Corpo que não existe
## (pino não armado, bola antes do arremesso) vai zerado.
func snapshot() -> PackedInt32Array:
	var poses := PackedInt32Array()
	poses.resize(BODIES * POSE_INTS)
	for index in BODIES:
		var body := ball if index == 0 else pins[index - 1]
		if body == null:
			continue
		var at := body.global_position * POSE_MM
		var turn := body.global_basis.get_rotation_quaternion() * POSE_QUAT
		var values := [at.x, at.y, at.z, turn.x, turn.y, turn.z, turn.w]
		for slot in POSE_INTS:
			poses[index * POSE_INTS + slot] = roundi(values[slot])
	return poses


## A pose do corpo `index` num quadro, ou `null` se ele não existia ali.
static func pose_of(poses: PackedInt32Array, index: int) -> Variant:
	var base := index * POSE_INTS
	if poses.size() < base + POSE_INTS:
		return null
	var turn := Quaternion(poses[base + 3], poses[base + 4], poses[base + 5], poses[base + 6])
	if turn.length_squared() < 1.0:
		return null
	var at := Vector3(poses[base], poses[base + 1], poses[base + 2]) / POSE_MM
	return Transform3D(Basis(turn.normalized()), at)


func _physics_process(delta: float) -> void:
	# O passo de física de agora ainda não andou: o que o corpo tem é o resultado
	# do anterior. O desenho fica um quadro de física atrás, e liso.
	for body: RigidBody3D in _smooth:
		var entry: Array = _smooth[body]
		entry[1] = entry[2]
		entry[2] = body.global_transform
	if not rolling:
		return
	_time += delta
	var at := ball.global_position
	if _on_oil and (at.z < -OIL_LEN or absf(at.x) > LANE_W * 0.5):
		# Acabou o óleo (ou a bola caiu na canaleta, que não tem óleo): ela volta ao
		# atrito cheio, e o contato passa a valer o da pista seca, da canaleta e dos
		# pinos.
		_on_oil = false
		ball.physics_material_override = _material(1.0, 0.1)
	if _after < 0.0 and (at.z < -(HEAD_PIN - 0.5) or at.y < -0.1):
		_after = 0.0
	elif _after >= 0.0:
		_after += delta
	var done := _time >= MAX_TIME
	if _after >= AFTER_MIN and _pins_resting():
		done = true
	if _after >= AFTER_MAX:
		done = true
	# Bola fraca que parou antes dos pinos.
	if _after < 0.0 and _time > 1.0 and ball.linear_velocity.length() < REST_SPEED:
		done = true
	if done:
		rolling = false
		settled.emit(knocked())


func _pins_resting() -> bool:
	for body in pins:
		if body == null or body.sleeping or off_deck(body.global_position):
			continue
		if body.linear_velocity.length() > REST_SPEED or body.angular_velocity.length() > REST_SPIN:
			return false
	return true


## Um pino nesta pose caiu: deitado demais, ou fora do deck.
static func is_down(pose: Transform3D) -> bool:
	return off_deck(pose.origin) or pose.basis.y.normalized().dot(Vector3.UP) < cos(deg_to_rad(FALL_TILT))


## Embaixo do tampo da pista ou do deck (no vão do poço), onde nada deve ser visto.
static func under_deck(at: Vector3) -> bool:
	return at.y < -0.1 and at.z > -DECK_END and absf(at.x) < LANE_W * 0.5


## Caiu na canaleta ou no poço: já conta, e o que ele faz lá não importa mais.
static func off_deck(at: Vector3) -> bool:
	return at.y < -0.02 or absf(at.x) > LANE_W * 0.5 + 0.02 or at.z < -DECK_END


func _make_pin(pin: int) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Pin%d" % (pin + 1)
	body.mass = PIN_MASS
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(0.0, PIN_COM, 0.0)
	body.physics_material_override = _material(PIN_FRICTION, PIN_BOUNCE)
	_no_damping(body)
	# Pino deitado rola sem fim sem resistência ao rolamento, que a Jolt não tem.
	body.angular_damp = PIN_ROLL_DAMP
	var visual := PIN_SCENE.instantiate()
	body.add_child(visual)
	if _pin_shape == null:
		var mesh := (visual.find_children("*", "MeshInstance3D")[0] as MeshInstance3D).mesh
		_pin_shape = mesh.create_convex_shape(true, false)
	var shape := CollisionShape3D.new()
	shape.shape = _pin_shape
	body.add_child(shape)
	body.position = pin_spot(pin)
	body.sleeping = true
	add_child(body)
	_track(body, visual)
	return body


func _track(body: RigidBody3D, visual: Node3D) -> void:
	visual.top_level = true
	var echo := reflection(visual)
	body.add_child(echo)
	_smooth[body] = [visual, body.global_transform, body.global_transform, echo]
	_place(_smooth[body], body.global_transform)


## O gêmeo espelhado de um desenho, para o reflexo no verniz (ver `MIRROR`). Quem
## chama põe na árvore e o move com `MIRROR * pose`.
static func reflection(visual: Node3D) -> Node3D:
	var echo := visual.duplicate() as Node3D
	echo.top_level = true
	for found in echo.find_children("*", "GeometryInstance3D", true, false):
		(found as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return echo


func _place(entry: Array, pose: Transform3D) -> void:
	(entry[0] as Node3D).global_transform = pose
	# O poço fica embaixo do deck, aberto para a frente: pino que cai lá rola para
	# baixo da madeira. Com o verniz transparente ele aparecia através dela.
	(entry[0] as Node3D).visible = not under_deck(pose.origin)
	var echo := entry[3] as Node3D
	# Fora do tampo (canaleta, poço) o espelho poria o gêmeo flutuando acima da
	# pista: bola e pinos que caíram no poço apareciam no ar depois do impacto.
	echo.visible = not off_deck(pose.origin)
	echo.global_transform = MIRROR * pose


func _number_plates() -> void:
	for offset in [0] + NEIGHBOURS:
		var plate := Label3D.new()
		plate.text = str(LANE_NUMBER + offset)
		plate.font = AppTheme.font(700, AppTheme.Role.DISPLAY)
		plate.font_size = 96
		plate.pixel_size = 0.0032
		plate.outline_size = 0
		plate.shaded = false
		plate.modulate = Color.WHITE if offset == 0 else Color(1, 1, 1, 0.75)
		plate.position = PLATE_AT + Vector3(offset * PITCH, 0.0, 0.0)
		add_child(plate)


## A madeira deixa ver o reflexo por baixo e brilha mais. Fica por cima do
## material do modelo, para o verniz se ajustar aqui sem regerar o glb.
func _varnish() -> void:
	for node in find_children("lane_wood", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var material := mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = VARNISH_ALPHA
		material.roughness = VARNISH_ROUGHNESS
		# O glb vem com as duas faces: o fundo da caixa cobria o reflexo outra vez.
		material.cull_mode = BaseMaterial3D.CULL_BACK
		mi.set_surface_override_material(0, material)
	var under := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# Vai bem além do deck: olhando rasante da câmera dos pinos, o raio que
	# atravessa o fim da pista só chega a 0,5 m de fundo metros depois.
	var length := APPROACH + DECK_END + UNDERCOAT_PAST
	plane.size = Vector2(LANE_W + 2.0 * (GUTTER_W + CAP_W), length)
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = UNDERCOAT
	plane.material = paint
	under.mesh = plane
	under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	under.position = Vector3(0.0, -UNDERCOAT_DEPTH, APPROACH - length * 0.5)
	add_child(under)


func _drop(body: RigidBody3D) -> void:
	_smooth.erase(body)
	body.free()


## Onde a bola está desenhada agora (entre os dois últimos quadros de física). É
## o que a câmera segue: seguir o corpo dava o mesmo tranco da bola.
func ball_point() -> Vector3:
	if ball == null:
		return Vector3.ZERO
	var entry: Array = _smooth.get(ball, [])
	if entry.is_empty():
		return ball.global_position
	var before: Transform3D = entry[1]
	var now: Transform3D = entry[2]
	return before.origin.lerp(now.origin, Engine.get_physics_interpolation_fraction())


func _process(delta: float) -> void:
	if following:
		_follow_frames(delta)
		return
	var fraction := Engine.get_physics_interpolation_fraction()
	for body: RigidBody3D in _smooth:
		var entry: Array = _smooth[body]
		var before: Transform3D = entry[1]
		_place(entry, before.interpolate_with(entry[2], fraction))


## Anda o ponto mostrado e põe cada corpo entre os dois quadros em volta dele.
##
## Sem quadro novo, a pista segura no último (a bola espera, não inventa
## caminho). Atrás da folga, por um quadro que atrasou ou por ter começado
## tarde, ela anda até duas vezes mais rápido até alcançar, sem pular.
func _follow_frames(delta: float) -> void:
	if _frames.is_empty():
		return
	var last: float = _frames[-1][0]
	var lag := last - _clock
	_clock = minf(_clock + delta * (1.0 + clampf(lag / FOLLOW_DELAY - 1.0, 0.0, 1.0)), last)
	var next := 0
	while next < _frames.size() - 1 and _frames[next][0] < _clock:
		next += 1
	var after: Array = _frames[next]
	var before: Array = _frames[maxi(next - 1, 0)]
	var span: float = after[0] - before[0]
	var weight := clampf((_clock - before[0]) / span, 0.0, 1.0) if span > 0.0 else 1.0
	for index in BODIES:
		var body := ball if index == 0 else pins[index - 1]
		var to: Variant = pose_of(after[1], index)
		if body == null or to == null:
			continue
		var from: Variant = pose_of(before[1], index)
		var pose: Transform3D = to if from == null else (from as Transform3D).interpolate_with(to, weight)
		body.global_transform = pose
		var entry: Array = _smooth[body]
		entry[1] = pose
		entry[2] = pose
		_place(entry, pose)


func _build_colliders() -> void:
	var cap_out := LANE_W * 0.5 + GUTTER_W + CAP_W
	# A pista é **uma** caixa, da aproximação ao fim do deck. Na 1.47 eram duas
	# (óleo e seco, cada uma com o seu atrito), e a quina entre elas, a 12,19 m,
	# jogava a bola para cima — até 45 cm, conforme a força. O óleo agora é o
	# atrito da bola (ver `_physics_process`), e a pista tem o atrito do seco.
	var lane_body := _static_body(DRY_FRICTION)
	var length := APPROACH + DECK_END
	_box(lane_body, Vector3(LANE_W, 0.06, length), Vector3(0.0, -0.03, APPROACH - length * 0.5))
	# A aproximação é mais larga que a pista; as sobras dos lados nunca ficam no
	# caminho da bola.
	var side_w := cap_out - LANE_W * 0.5
	for side: float in [-1.0, 1.0]:
		_box(lane_body, Vector3(side_w, 0.06, APPROACH), Vector3(side * (LANE_W * 0.5 + side_w * 0.5), -0.03, APPROACH * 0.5))
	# Canaletas, divisórias, paredes do fundo, poço e máquina: a malha do próprio
	# modelo, para a bola cair na canaleta de verdade.
	var walls := _static_body(0.3)
	# Parede invisível na borda de fora de cada canaleta: uma bola com gancho forte
	# subia a meia-cana e pulava a divisória de 3 cm para fora do mundo.
	var outer := LANE_W * 0.5 + GUTTER_W
	var reach := APPROACH + DECK_END + 1.0
	for side: float in [-1.0, 1.0]:
		_box(walls, Vector3(0.1, 1.0, reach), Vector3(side * (outer + 0.05), 0.5, APPROACH - reach * 0.5))
	for node in find_children("*", "MeshInstance3D", true, false):
		if node.name in ["gutters", "walls", "pit", "masking"]:
			var mi := node as MeshInstance3D
			var shape := CollisionShape3D.new()
			shape.shape = mi.mesh.create_trimesh_shape()
			shape.transform = global_transform.affine_inverse() * mi.global_transform
			walls.add_child(shape)


func _static_body(friction: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.physics_material_override = _material(friction, 0.1)
	add_child(body)
	return body


func _box(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)


static func _material(friction: float, bounce: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = bounce
	return material


## Sem o amortecimento padrão do projeto: quem freia a bola é o atrito da pista.
static func _no_damping(body: RigidBody3D) -> void:
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
