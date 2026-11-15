class_name BowlingLane
extends Node3D

## A pista com física de verdade: recebe um arremesso, deixa a Jolt rolar a bola e
## derrubar os pinos, e diz quais caíram.
##
## É a única física do app que não mora em `core/`. A da sinuca é feita à mão para
## dar a mesma mesa bit a bit nos dois aparelhos; pinos batendo uns nos outros em
## três dimensões não cabem nisso, e por isso o lance do boliche carrega o
## resultado (ver o cabeçalho de `BowlingRules`). Esta cena só **produz** a
## máscara: no aparelho de quem arremessa ela vira o lance, e no dos outros ela
## só mostra a jogada.
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

## A jogada em curso. Falso antes do primeiro arremesso e depois de `settled`.
var rolling := false
## Cor da bola do próximo arremesso (a de quem joga).
var ball_color := Color.WHITE
var ball: RigidBody3D = null
## Um por pino (índice 0 = pino 1); `null` nos que não estão armados.
var pins: Array[RigidBody3D] = []

var _time := 0.0
var _after := -1.0
var _on_oil := false
var _pin_shape: Shape3D = null


func _init() -> void:
	pins.resize(BowlingRules.PINS)


func _ready() -> void:
	add_child(LANE_SCENE.instantiate())
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
	for pin in BowlingRules.PINS:
		if pins[pin] != null:
			pins[pin].free()
			pins[pin] = null
	if ball != null:
		ball.free()
		ball = null
	for pin in BowlingRules.PINS:
		if mask & (1 << pin):
			pins[pin] = _make_pin(pin)


func throw(params: PackedFloat32Array) -> void:
	if ball != null:
		ball.free()
	var start := launch(params)
	ball = RigidBody3D.new()
	ball.name = "Ball"
	ball.mass = BALL_MASS
	ball.continuous_cd = true
	# No óleo, o atrito da bola é o do óleo: a Godot usa o menor dos dois atritos
	# no contato, então a pista (seco) desliza como óleo até a bola passar dele.
	ball.physics_material_override = _material(OIL_FRICTION, 0.1)
	_on_oil = true
	_no_damping(ball)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BALL_R
	shape.shape = sphere
	ball.add_child(shape)
	var visual := BALL_SCENE.instantiate()
	tint_ball(visual, ball_color)
	ball.add_child(visual)
	ball.position = start["position"]
	add_child(ball)
	ball.linear_velocity = start["velocity"]
	ball.angular_velocity = start["spin"]
	_time = 0.0
	_after = -1.0
	rolling = true


## Pinta o mármore cinza da bola (o material `ball`; os furos ficam como estão).
static func tint_ball(node: Node, color: Color) -> void:
	if color == Color.WHITE:
		return  # o mármore como veio; e sem material novo, que o modo sem tela reclama
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (found as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var source := mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or source.resource_name != "ball":
				continue
			var painted := source.duplicate() as StandardMaterial3D
			painted.albedo_color = color
			(found as MeshInstance3D).set_surface_override_material(surface, painted)


## Os pinos armados que caíram até agora.
func knocked() -> int:
	var mask := 0
	for pin in BowlingRules.PINS:
		if pins[pin] != null and _is_down(pins[pin]):
			mask |= 1 << pin
	return mask


func _physics_process(delta: float) -> void:
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
		if body == null or body.sleeping or _off_deck(body):
			continue
		if body.linear_velocity.length() > REST_SPEED or body.angular_velocity.length() > REST_SPIN:
			return false
	return true


func _is_down(body: RigidBody3D) -> bool:
	return _off_deck(body) or body.global_basis.y.dot(Vector3.UP) < cos(deg_to_rad(FALL_TILT))


## Caiu na canaleta ou no poço: já conta, e o que ele faz lá não importa mais.
func _off_deck(body: RigidBody3D) -> bool:
	var at := body.global_position
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
	return body


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
