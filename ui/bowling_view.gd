class_name BowlingView
extends Control

## A pista na tela: a câmera, a mira, o efeito e o balanço com a barra de timing.
##
## A pista com física ([BowlingLane]) roda numa [SubViewport] com mundo próprio, e
## a textura dela é o fundo deste controle. A mira, o seletor de efeito e a barra
## de timing são desenhados em 2D por cima, como na sinuca: são informação, não
## objeto, e têm de ficar nítidos e da cor do tema.
##
## ## O arremesso
##
## - **Posição:** arrastar a bola para os lados, na linha de falta;
## - **Direção:** arrastar na pista, acima da bola, gira a mira (a linha mostra
##   o caminho, já com a curva do efeito);
## - **Efeito:** o trilho embaixo, de gancho à esquerda a gancho à direita;
## - **Timing:** o botão começa o balanço — a bola recua e volta como um pêndulo —
##   e o segundo toque solta. O ponto verde da barra é o fundo do balanço: soltar
##   ali sai como mirado, cedo puxa para a esquerda, tarde empurra para a direita.
##
## ## A câmera faz o caminho de quem assiste ao boliche
##
## Atrás da bola na mira, seguindo a bola pela pista depois de solta, e parada
## perto dos pinos quando ela chega lá.

## Quem joga soltou a bola; a física já começou com estes parâmetros.
signal released(params: PackedFloat32Array)
## A jogada parou: `mask` são os pinos armados que caíram.
signal settled(mask: int)

const Lane := preload("res://ui/bowling_lane.gd")

## Campo de visão vertical. Em retrato, uns 54° de altura dão uns 32° de largura:
## a pista cabe inteira com os pinos visíveis no fundo.
const FOV := 33.0
const AIM_CAMERA := Vector3(0.0, 1.5, 3.4)
const AIM_LOOK := Vector3(0.0, 0.0, -2.36)
## Perto dos pinos: a câmera para aqui e olha o deck.
const PIN_CAMERA := Vector3(0.0, 0.75, -(Lane.HEAD_PIN - 3.4))
const PIN_LOOK := Vector3(0.0, 0.15, -(Lane.HEAD_PIN + 0.5))
## Atrás da bola enquanto ela rola.
const FOLLOW_BACK := 2.4
const FOLLOW_AHEAD := 6.0
## Quão rápido a câmera alcança o alvo (por segundo).
const CAMERA_EASE := 6.0

## O balanço: braço do pêndulo, quanto a bola recua e até onde ela vai.
const ARM := 0.75
const BACKSWING := 70.0
const FOLLOW_THROUGH := -40.0
const BACK_TIME := 0.55
const FORWARD_TIME := 0.6
## Graus do fundo do balanço até o timing valer ±1.
const WINDOW := 20.0
## Faixa do ponto certo, em fração da janela, pintada de verde na barra.
const SWEET := 0.25

## Curva da linha de mira com o efeito cheio, medida na física (`bowling_physics_probe`).
const HOOK_PREVIEW := 0.32

const BUTTON_SIZE := Vector2(180.0, 52.0)
const BOTTOM_PAD := 16.0
const TRACK_WIDTH := 220.0
const KNOB := 12.0

enum Phase { IDLE, AIM, BACK, FORWARD, ROLLING }

## Aceita mira e o botão. Falso na vez do outro e com a bola rolando.
var enabled := false:
	set(value):
		enabled = value
		_drag = Drag.NONE
		if value and _phase == Phase.IDLE:
			_phase = Phase.AIM
		elif not value and _phase == Phase.AIM:
			_phase = Phase.IDLE
		_sync()

## Cor da bola de quem joga.
var ball_color := Color.WHITE:
	set(value):
		ball_color = value
		if lane != null:
			lane.ball_color = value
		if _preview != null:
			Lane.tint_ball(_preview, value)
		_render()

var lane: BowlingLane = null

## Os três parâmetros da mira, de -1 a 1 (o quarto, o timing, sai do balanço).
var aim_position := 0.0
var aim_direction := 0.0
var aim_spin := 0.0

enum Drag { NONE, BALL, AIM, SPIN }

var _phase := Phase.IDLE
var _drag := Drag.NONE
var _swing := 0.0
var _angle := 0.0
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _preview: Node3D = null
var _button: Button = null
var _look := AIM_LOOK
var _camera_moving := false
var _density := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_world()
	_button = Button.new()
	_button.theme_type_variation = &"PrimaryButton"
	_button.custom_minimum_size = BUTTON_SIZE
	# No toque, e não na soltura: é um botão de timing.
	_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_on_button)
	add_child(_button)
	resized.connect(_on_resized)
	_on_resized()
	_sync()


func _build_world() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = AppTheme.COASTER
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.70, 0.68, 0.80)
	environment.ambient_light_energy = 0.45
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)

	# A luz do salão, quase a pino e vinda de trás de quem joga; e a do deck,
	# embaixo da máquina, que é o que faz os pinos brilharem no fundo escuro.
	var hall := DirectionalLight3D.new()
	hall.rotation_degrees = Vector3(-60.0, 10.0, 0.0)
	hall.light_energy = 0.9
	hall.light_color = Color(1.0, 0.96, 0.9)
	hall.shadow_enabled = true
	hall.directional_shadow_max_distance = 30.0
	_viewport.add_child(hall)
	var deck := OmniLight3D.new()
	deck.position = Vector3(0.0, 0.55, -(Lane.HEAD_PIN + 0.2))
	deck.omni_range = 3.0
	deck.light_energy = 2.2
	_viewport.add_child(deck)

	lane = BowlingLane.new()
	lane.ball_color = ball_color
	lane.settled.connect(_on_settled)
	_viewport.add_child(lane)

	_preview = Lane.BALL_SCENE.instantiate()
	_viewport.add_child(_preview)
	Lane.tint_ball(_preview, ball_color)

	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.far = 60.0
	_viewport.add_child(_camera)
	_camera.position = AIM_CAMERA
	_camera.look_at(AIM_LOOK)


func _on_resized() -> void:
	if _viewport == null or size.x < 1.0 or size.y < 1.0:
		return
	_density = get_viewport().get_final_transform().get_scale().x if is_inside_tree() else 1.0
	_viewport.size = Vector2i((size * _density).round())
	_button.position = Vector2((size.x - BUTTON_SIZE.x) * 0.5, size.y - BUTTON_SIZE.y - BOTTOM_PAD)
	_button.size = BUTTON_SIZE
	_render()
	queue_redraw()


# --- o que a cena pede --------------------------------------------------------


## Arma os pinos de `mask`, devolve a bola à linha de falta e a câmera à mira.
func rack(mask: int) -> void:
	lane.rack(mask)
	_phase = Phase.AIM if enabled else Phase.IDLE
	_angle = 0.0
	_camera.position = _aim_camera()
	_look = AIM_LOOK
	_camera.look_at(_look)
	_sync()


## Um arremesso que não veio deste dedo: o bot, ou quem joga do outro lado.
func throw(params: PackedFloat32Array) -> void:
	aim_position = params[0]
	aim_direction = params[1]
	aim_spin = params[2]
	_start_rolling(params)


func params(timing: float) -> PackedFloat32Array:
	return PackedFloat32Array([aim_position, aim_direction, aim_spin, clampf(timing, -1.0, 1.0)])


## A bola está rolando ou o balanço está no meio.
func busy() -> bool:
	return _phase in [Phase.BACK, Phase.FORWARD, Phase.ROLLING]


# --- o balanço ----------------------------------------------------------------


func _on_button() -> void:
	match _phase:
		Phase.AIM:
			_phase = Phase.BACK
			_swing = 0.0
			_drag = Drag.NONE
		Phase.BACK:
			# Soltou antes de a bola voltar: o mais cedo que dá.
			_release(-1.0)
		Phase.FORWARD:
			_release(_timing())
	_sync()


## O timing do ângulo em que a bola está: 0 no fundo do balanço.
func _timing() -> float:
	return clampf(-_angle / WINDOW, -1.0, 1.0)


func _release(timing: float) -> void:
	var chosen := params(timing)
	_start_rolling(chosen)
	released.emit(chosen)


func _start_rolling(chosen: PackedFloat32Array) -> void:
	_phase = Phase.ROLLING
	_angle = 0.0
	lane.ball_color = ball_color
	lane.throw(chosen)
	_sync()


func _on_settled(mask: int) -> void:
	_phase = Phase.IDLE
	_sync()
	settled.emit(mask)


func _process(delta: float) -> void:
	match _phase:
		Phase.BACK:
			_swing += delta
			var u := clampf(_swing / BACK_TIME, 0.0, 1.0)
			_angle = BACKSWING * sin(u * PI * 0.5)
			if u >= 1.0:
				_phase = Phase.FORWARD
				_swing = 0.0
		Phase.FORWARD:
			_swing += delta
			var u := clampf(_swing / FORWARD_TIME, 0.0, 1.0)
			_angle = lerpf(BACKSWING, FOLLOW_THROUGH, u)
			if u >= 1.0:
				# Passou do ponto e ninguém soltou: a bola sai sozinha, tarde.
				_release(1.0)
	_place_preview()
	_follow(delta)
	queue_redraw()
	if _live():
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		# Tudo parado: um último quadro e a pista para de gastar bateria.
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		set_process(false)


func _place_preview() -> void:
	var start: Vector3 = Lane.launch(params(0.0))["position"]
	var swing := deg_to_rad(_angle)
	# Pêndulo pendurado acima da linha de falta: no fundo, a bola encosta na pista.
	_preview.position = start + Vector3(0.0, ARM * (1.0 - cos(swing)), ARM * sin(swing))
	_preview.visible = _phase != Phase.ROLLING and lane.ball == null


func _aim_camera() -> Vector3:
	return AIM_CAMERA + Vector3(aim_position * Lane.LANE_W * 0.18, 0.0, 0.0)


func _follow(delta: float) -> void:
	var target := _aim_camera()
	var look := AIM_LOOK
	if lane.ball != null:
		var at := lane.ball.global_position
		var z := maxf(at.z + FOLLOW_BACK, PIN_CAMERA.z)
		var k := inverse_lerp(AIM_CAMERA.z, PIN_CAMERA.z, z)
		target = Vector3(lerpf(at.x * 0.4, 0.0, k), lerpf(1.0, PIN_CAMERA.y, k), z)
		look = Vector3(target.x * 0.5, lerpf(0.0, PIN_LOOK.y, k), maxf(z - FOLLOW_AHEAD, PIN_LOOK.z))
	var weight := 1.0 - exp(-CAMERA_EASE * delta)
	_camera.position = _camera.position.lerp(target, weight)
	_look = _look.lerp(look, weight)
	_camera.look_at(_look)
	_camera_moving = _camera.position.distance_to(target) > 0.005 or _look.distance_to(look) > 0.005


# --- gesto --------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not enabled or _phase != Phase.AIM:
		return
	var press := event as InputEventMouseButton
	if press != null and press.button_index == MOUSE_BUTTON_LEFT:
		if press.pressed:
			_drag = _grab(press.position)
			_drag_to(press.position)
		else:
			_drag = Drag.NONE
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _drag != Drag.NONE:
		_drag_to(motion.position)
		accept_event()


func _grab(at: Vector2) -> Drag:
	if _track_rect().grow(18.0).has_point(at):
		return Drag.SPIN
	var ball := _to_screen(_preview.position)
	if at.distance_to(ball) <= maxf(44.0, _ball_radius() * 2.5):
		return Drag.BALL
	if at.y < ball.y:
		return Drag.AIM
	return Drag.NONE


func _drag_to(at: Vector2) -> void:
	match _drag:
		Drag.SPIN:
			var track := _track_rect()
			aim_spin = clampf((at.x - track.position.x) / track.size.x * 2.0 - 1.0, -1.0, 1.0)
		Drag.BALL:
			var hit: Variant = _on_lane(at, Lane.BALL_R)
			if hit != null:
				aim_position = clampf((hit as Vector3).x / (Lane.LANE_W * 0.5 - Lane.BALL_R), -1.0, 1.0)
		Drag.AIM:
			var hit: Variant = _on_lane(at, 0.0)
			var start: Vector3 = Lane.launch(params(0.0))["position"]
			if hit != null and (hit as Vector3).z < start.z - 1.0:
				var toward := (hit as Vector3) - start
				var angle := rad_to_deg(atan2(toward.x, -toward.z))
				aim_direction = clampf(angle / Lane.MAX_ANGLE, -1.0, 1.0)
	_render()
	queue_redraw()


## Onde o dedo cai no plano da pista a esta altura, ou `null`.
func _on_lane(at: Vector2, height: float) -> Variant:
	var from := _camera.project_ray_origin(at * _density)
	var ray := _camera.project_ray_normal(at * _density)
	if absf(ray.y) < 0.0001:
		return null
	var t := (height - from.y) / ray.y
	return from + ray * t if t > 0.0 else null


func _to_screen(point: Vector3) -> Vector2:
	return _camera.unproject_position(point) / _density


func _ball_radius() -> float:
	return _to_screen(_preview.position).distance_to(_to_screen(_preview.position + Vector3(Lane.BALL_R, 0.0, 0.0)))


## O trilho do efeito (e, durante o balanço, a barra de timing), logo acima do botão.
func _track_rect() -> Rect2:
	var y := size.y - BUTTON_SIZE.y - BOTTOM_PAD - 30.0
	return Rect2((size.x - TRACK_WIDTH) * 0.5, y, TRACK_WIDTH, 8.0)


# --- desenho ------------------------------------------------------------------


func _sync() -> void:
	if _button == null:
		return
	_button.visible = enabled and _phase in [Phase.AIM, Phase.BACK, Phase.FORWARD]
	_button.text = "Jogar" if _phase == Phase.AIM else "Soltar!"
	if _preview != null:
		_place_preview()
	_render()
	queue_redraw()


## Pede quadros novos da pista até tudo parar (ver `_process`). Parada, ela não
## é redesenhada: a pista de quem espera a vez do outro não gasta bateria.
func _render() -> void:
	if _viewport == null:
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)


func _live() -> bool:
	return (
		_phase in [Phase.BACK, Phase.FORWARD, Phase.ROLLING] or _drag != Drag.NONE
		or lane.rolling or _camera_moving
	)


func _draw() -> void:
	draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, size), false)
	if not enabled:
		return
	if _phase == Phase.AIM:
		_draw_path()
		_draw_handles()
		_draw_spin()
	elif _phase in [Phase.BACK, Phase.FORWARD]:
		_draw_timing()


## O caminho previsto da bola, com a curva do efeito no fim (medida na física).
func _draw_path() -> void:
	var start: Vector3 = Lane.launch(params(0.0))["position"]
	var angle := deg_to_rad(aim_direction * Lane.MAX_ANGLE)
	var points := PackedVector2Array()
	var reach := Lane.HEAD_PIN + start.z
	for step in 25:
		var travel := reach * float(step) / 24.0
		var bend := aim_spin * HOOK_PREVIEW * pow(travel / reach, 3.0)
		var x := start.x + tan(angle) * travel + bend
		if absf(x) > Lane.LANE_W * 0.5:
			x = signf(x) * Lane.LANE_W * 0.5
		points.append(_to_screen(Vector3(x, 0.005, start.z - travel)))
	draw_polyline(points, Color(AppTheme.ACCENT, 0.85), 3.0, true)
	draw_circle(points[points.size() - 1], 5.0, AppTheme.ACCENT)


## Setas dos dois lados da bola: ela se arrasta para os lados.
func _draw_handles() -> void:
	var ball := _to_screen(_preview.position)
	var gap := _ball_radius() + 14.0
	for side: float in [-1.0, 1.0]:
		var tip := ball + Vector2(side * (gap + 8.0), 0.0)
		draw_polyline(
			PackedVector2Array([tip + Vector2(-side * 7.0, -7.0), tip, tip + Vector2(-side * 7.0, 7.0)]),
			Color(AppTheme.TEXT, 0.8), 3.0, true
		)


func _draw_spin() -> void:
	var track := _track_rect()
	var font := AppTheme.font(800)
	_draw_bar_back(track)
	var knob := Vector2(track.position.x + (aim_spin + 1.0) * 0.5 * track.size.x, track.get_center().y)
	draw_circle(knob, KNOB, AppTheme.PAPER)
	draw_circle(knob, KNOB * 0.45, AppTheme.DANGER)
	_caption("EFEITO: %s" % spin_name().to_upper(), Vector2(track.get_center().x, track.position.y - 12.0), font)


## A barra de timing: o balanço inteiro de um lado ao outro, o ponto verde no
## fundo do balanço e o marcador onde a bola está agora.
func _draw_timing() -> void:
	var track := _track_rect().grow_individual(0.0, 6.0, 0.0, 6.0)
	var font := AppTheme.font(800)
	_draw_bar_back(track)
	draw_rect(_bar_span(track, WINDOW), Color(AppTheme.ACCENT, 0.35))
	draw_rect(_bar_span(track, WINDOW * SWEET), AppTheme.SUCCESS)
	var x := _bar_x(track, _angle)
	draw_line(Vector2(x, track.position.y - 8.0), Vector2(x, track.end.y + 8.0), AppTheme.PAPER, 4.0, true)
	_caption("SOLTE NO VERDE", Vector2(track.get_center().x, track.position.y - 12.0), font)


## Onde um ângulo do balanço cai na barra: recuado à esquerda, passado à direita.
func _bar_x(track: Rect2, angle: float) -> float:
	return track.position.x + (BACKSWING - angle) / (BACKSWING - FOLLOW_THROUGH) * track.size.x


## A faixa da barra de `-angle` a `+angle` em volta do fundo do balanço.
func _bar_span(track: Rect2, angle: float) -> Rect2:
	var left := _bar_x(track, angle)
	return Rect2(left, track.position.y, _bar_x(track, -angle) - left, track.size.y)


func _draw_bar_back(track: Rect2) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = Color(AppTheme.BACKGROUND, 0.85)
	back.set_corner_radius_all(int(track.size.y * 0.5))
	draw_style_box(back, track.grow(4.0))


func _caption(text: String, at: Vector2, font: Font) -> void:
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, at - Vector2(wide * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, AppTheme.TEXT)


func spin_name() -> String:
	if absf(aim_spin) < 0.1:
		return "reto"
	var amount := "leve" if absf(aim_spin) < 0.6 else "forte"
	return "gancho %s à %s" % [amount, "direita" if aim_spin > 0.0 else "esquerda"]
