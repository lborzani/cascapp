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
## - **Força:** enquanto o botão está seguro, a força vai e volta de 0 a 100% (e a
##   bola recua e desce junto). Soltar o dedo escolhe a força daquele momento;
## - **Timing:** depois de soltar o dedo, a bola balança como um pêndulo, indo e
##   voltando até o toque (no botão ou em qualquer lugar da pista). O ponto verde
##   da barra é o fundo do balanço: soltar ali sai como mirado, antes dele puxa
##   para a esquerda, depois empurra para a direita.
##
## As duas barras vão e voltam sem parar, a pedido do Borzani: a força não trava
## em 100% e o balanço não desiste nem solta a bola sozinho.
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
## O rastro da bola: quanto tempo um ponto dele vive, a distância mínima entre
## pontos e a largura no ponto mais novo.
const TRAIL_LIFE := 0.5
const TRAIL_STEP := 0.08
const TRAIL_WIDTH := 0.16
## A tremida quando a bola chega aos pinos, em metros de deslocamento da imagem
## com a bola na força cheia, e quão rápido ela some.
const SHAKE := 0.035
const SHAKE_DECAY := 9.0
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

## O balanço: braço do pêndulo e quanto a bola recua, de força nenhuma a força
## cheia. O balanço vai até o mesmo tanto para a frente.
const ARM := 0.75
const MIN_BACKSWING := 20.0
const BACKSWING := 75.0
## Uma ida e volta da força (0 → 100% → 0).
const POWER_PERIOD := 1.6
## Uma ida e volta do balanço (atrás → frente → atrás), igual com qualquer força,
## como num pêndulo: com mais força a bola passa mais rápido pelo verde, e o
## timing fica mais difícil.
const SWING_PERIOD := 1.6
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

enum Phase { IDLE, AIM, HOLD, SWING, ROLLING }

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
			Lane.tint_ball(_preview, value, ball_skin)
		_render()

## A textura da loja (`Cosmetics`) da bola de quem joga; `null` é o mármore na
## cor do assento.
var ball_skin: Texture2D = null:
	set(value):
		ball_skin = value
		if lane != null:
			lane.ball_skin = value
		if _preview != null:
			Lane.tint_ball(_preview, ball_color, value)
		_render()

var lane: BowlingLane = null

## Os três parâmetros da mira, de -1 a 1 (força e timing saem do balanço).
var aim_position := 0.0
var aim_direction := 0.0
var aim_spin := 0.0

enum Drag { NONE, BALL, AIM, SPIN }

var _phase := Phase.IDLE
var _drag := Drag.NONE
var _swing := 0.0
var _angle := 0.0
## Força do balanço em curso, de 0 a 1: o tempo que o botão ficou seguro.
var _power := 0.0
## De onde a volta começou (o recuo da força escolhida).
var _top := 0.0
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _preview: Node3D = null
## O reflexo da bola da mira no verniz (ver `BowlingLane.reflection`). Filho da
## bola, para a pintura e o `visible` dela valerem para ele também.
var _preview_echo: Node3D = null
var _button: Button = null
var _look := AIM_LOOK
var _camera_moving := false
var _density := 1.0
var _trail: MeshInstance3D = null
## Os pontos do rastro, `[posição, idade]`, do mais velho ao mais novo.
var _trail_points: Array = []
var _shake := 0.0
## A bola já chegou aos pinos nesta jogada (a tremida é uma vez só).
var _impacted := false
var _last_point := Vector3.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_world()
	_button = Button.new()
	_button.theme_type_variation = &"PrimaryButton"
	_button.custom_minimum_size = BUTTON_SIZE
	_button.focus_mode = Control.FOCUS_NONE
	# Segurar e soltar, e não um clique: o tempo segurando é a força, e o dedo que
	# escorrega para fora do botão ainda conta como soltar.
	_button.keep_pressed_outside = true
	_button.button_down.connect(_on_press)
	_button.button_up.connect(_on_lift)
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
	deck.light_energy = 3.0
	deck.light_color = Color(1.0, 0.95, 0.85)
	deck.light_cull_mask = ~Lane.SCENERY_LAYER
	_viewport.add_child(deck)

	lane = BowlingLane.new()
	lane.ball_color = ball_color
	lane.ball_skin = ball_skin
	lane.settled.connect(_on_settled)
	_viewport.add_child(lane)

	_preview = Lane.BALL_SCENE.instantiate()
	_viewport.add_child(_preview)
	_preview_echo = Lane.reflection(_preview)
	_preview.add_child(_preview_echo)
	Lane.tint_ball(_preview, ball_color, ball_skin)

	_trail = MeshInstance3D.new()
	_trail.mesh = ImmediateMesh.new()
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = glow
	_viewport.add_child(_trail)

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
	_trail_points.clear()
	_draw_trail()
	_impacted = false
	_phase = Phase.AIM if enabled else Phase.IDLE
	_angle = 0.0
	_power = 0.0
	_camera.position = _aim_camera()
	_look = AIM_LOOK
	_camera.look_at(_look)
	_sync()


## Um arremesso que não veio deste dedo: o bot, ou quem joga do outro lado.
func throw(chosen: PackedFloat32Array) -> void:
	aim_position = chosen[0]
	aim_direction = chosen[1]
	aim_spin = chosen[2]
	_start_rolling(chosen)


## Um quadro da jogada de outro aparelho: a pista segue o que ele manda em vez
## de rodar a própria física (ver `BowlingLane.follow`).
func follow(step: int, poses: PackedInt32Array) -> void:
	if not lane.following:
		_phase = Phase.ROLLING
		_angle = 0.0
		lane.ball_color = ball_color
		lane.ball_skin = ball_skin
	lane.follow(step, poses)
	_sync()


func params(timing: float, power := _power) -> PackedFloat32Array:
	return PackedFloat32Array([
		aim_position, aim_direction, aim_spin, clampf(timing, -1.0, 1.0), clampf(power, 0.0, 1.0),
	])


## A bola está rolando ou o balanço está no meio.
func busy() -> bool:
	return _phase in [Phase.HOLD, Phase.SWING, Phase.ROLLING]


# --- o balanço ----------------------------------------------------------------


## O dedo encostou: na mira começa a juntar força; na volta, solta a bola.
func _on_press() -> void:
	match _phase:
		Phase.AIM:
			_phase = Phase.HOLD
			_swing = 0.0
			_power = 0.0
			_drag = Drag.NONE
		Phase.SWING:
			_release(_timing())
	_sync()


## O dedo saiu: a força fica escolhida e a bola começa a voltar.
func _on_lift() -> void:
	if _phase != Phase.HOLD:
		return
	_phase = Phase.SWING
	_top = _angle
	_swing = 0.0
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
	lane.ball_skin = ball_skin
	lane.throw(chosen)
	_sync()


func _on_settled(mask: int) -> void:
	_phase = Phase.IDLE
	_sync()
	settled.emit(mask)


func _process(delta: float) -> void:
	match _phase:
		Phase.HOLD:
			_swing += delta
			# Vai e volta: 0 → 100% → 0, até o dedo sair.
			_power = 1.0 - absf(fposmod(_swing / POWER_PERIOD, 1.0) * 2.0 - 1.0)
			# A bola acompanha o recuo da força, sem saltar para ele.
			var top := lerpf(MIN_BACKSWING, BACKSWING, _power)
			_angle = lerpf(_angle, top, 1.0 - exp(-12.0 * delta))
		Phase.SWING:
			_swing += delta
			# Onda triangular: começa atrás (+1), passa pelo fundo, vai à frente (-1)
			# e volta — sem parar, até o toque. Triangular e não seno: a bola passa
			# pelo verde sempre na mesma velocidade, e o toque é questão de olho.
			_angle = _top * (4.0 * absf(fposmod(_swing / SWING_PERIOD, 1.0) - 0.5) - 1.0)
	_place_preview()
	_follow(delta)
	_juice(delta)
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
	_preview_echo.global_transform = Lane.MIRROR * _preview.global_transform


func _aim_camera() -> Vector3:
	return AIM_CAMERA + Vector3(aim_position * Lane.LANE_W * 0.18, 0.0, 0.0)


func _follow(delta: float) -> void:
	var target := _aim_camera()
	var look := AIM_LOOK
	if lane.ball != null:
		var at := lane.ball_point()
		var z := maxf(at.z + FOLLOW_BACK, PIN_CAMERA.z)
		var k := inverse_lerp(AIM_CAMERA.z, PIN_CAMERA.z, z)
		target = Vector3(lerpf(at.x * 0.4, 0.0, k), lerpf(AIM_CAMERA.y, PIN_CAMERA.y, k), z)
		# Sempre o mesmo tanto à frente da câmera, sem trava própria. Na 1.47 o ponto
		# olhado parava antes da câmera: ela inclinava para baixo, a bola descia na
		# tela e depois subia de repente — o "pulinho" no fim da pista.
		look = Vector3(target.x * 0.5, lerpf(AIM_LOOK.y, PIN_LOOK.y, k), z - FOLLOW_AHEAD)
	var weight := 1.0 - exp(-CAMERA_EASE * delta)
	_camera.position = _camera.position.lerp(target, weight)
	_look = _look.lerp(look, weight)
	_camera.look_at(_look)
	_camera_moving = _camera.position.distance_to(target) > 0.005 or _look.distance_to(look) > 0.005


## O rastro atrás da bola e a tremida no impacto. Vale também seguindo a jogada
## de outro aparelho: os dois só olham para onde a bola está desenhada.
func _juice(delta: float) -> void:
	for point in _trail_points:
		point[1] += delta
	while not _trail_points.is_empty() and _trail_points[0][1] > TRAIL_LIFE:
		_trail_points.pop_front()
	if lane.ball != null and (lane.rolling or lane.following):
		var at := lane.ball_point()
		var speed := at.distance_to(_last_point) / maxf(delta, 0.001)
		_last_point = at
		# No deck e na canaleta o rastro some: ele é só da corrida na madeira.
		var on_lane := at.y > Lane.BALL_R * 0.5 and at.z > -Lane.HEAD_PIN
		if on_lane and (_trail_points.is_empty() or _trail_points[-1][0].distance_to(at) > TRAIL_STEP):
			_trail_points.append([Vector3(at.x, 0.004, at.z), 0.0])
		if not _impacted and at.z < -(Lane.HEAD_PIN - 0.15):
			_impacted = true
			_shake = SHAKE * clampf(speed / Lane.FULL_SPEED, 0.3, 1.0)
	_draw_trail()
	_shake = 0.0 if _shake < 0.001 else _shake * exp(-SHAKE_DECAY * delta)
	_camera.h_offset = randf_range(-1.0, 1.0) * _shake
	_camera.v_offset = randf_range(-1.0, 1.0) * _shake


func _draw_trail() -> void:
	var mesh := _trail.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _trail_points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count := _trail_points.size()
	for index in count:
		var at: Vector3 = _trail_points[index][0]
		var other: Vector3 = _trail_points[mini(index + 1, count - 1)][0]
		if index == count - 1:
			other = at + (at - _trail_points[index - 1][0])
		var side := (other - at).cross(Vector3.UP).normalized()
		# Fino e apagado na ponta velha, largo e aceso perto da bola.
		var life := 1.0 - float(_trail_points[index][1]) / TRAIL_LIFE
		var fresh := float(index + 1) / count
		var colour := Color(ball_color.lerp(AppTheme.ACCENT, 0.5), 0.55 * life * fresh)
		var half := side * TRAIL_WIDTH * 0.5 * fresh
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(at - half)
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(at + half)
	mesh.surface_end()


## O strike e o spare em letreiro grande, com um clarão rápido na pista.
func celebrate(word: String) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1.0, 1.0, 1.0, 0.45)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(flash)
	var label := Label.new()
	label.text = word
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", AppTheme.font(700, AppTheme.Role.DISPLAY))
	label.add_theme_font_size_override("font_size", 72)
	label.add_theme_color_override("font_color", AppTheme.ACCENT)
	label.add_theme_color_override("font_outline_color", AppTheme.ACCENT_INK)
	label.add_theme_constant_override("outline_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_bottom = -size.y * 0.3
	add_child(label)
	label.pivot_offset = Vector2(size.x * 0.5, size.y * 0.35)
	label.scale = Vector2(0.4, 0.4)
	label.rotation_degrees = -6.0
	var tween := create_tween().set_parallel()
	tween.tween_property(flash, "color:a", 0.0, 0.35)
	tween.tween_property(label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(1.1)
	tween.chain().tween_callback(func() -> void:
		flash.queue_free()
		label.queue_free())


# --- gesto --------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	# Na volta do balanço, tocar em qualquer lugar da pista solta: o alvo é o
	# momento, não o botão.
	if enabled and _phase == Phase.SWING and press != null and press.pressed:
		_on_press()
		accept_event()
		return
	if not enabled or _phase != Phase.AIM:
		return
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
	_button.visible = enabled and _phase in [Phase.AIM, Phase.HOLD, Phase.SWING]
	match _phase:
		Phase.HOLD:
			_button.text = "Solte na força certa"
		Phase.SWING:
			_button.text = "Toque no verde!"
		_:
			_button.text = "Segure para jogar"
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
		_phase in [Phase.HOLD, Phase.SWING, Phase.ROLLING] or _drag != Drag.NONE
		or lane.rolling or lane.following or _camera_moving
		or _shake > 0.0 or not _trail_points.is_empty()
	)


func _draw() -> void:
	draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, size), false)
	if not enabled:
		return
	if _phase == Phase.AIM:
		_draw_path()
		_draw_handles()
		_draw_spin()
	elif _phase == Phase.HOLD:
		_draw_power()
	elif _phase == Phase.SWING:
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
	_caption("TOQUE NO VERDE", Vector2(track.get_center().x, track.position.y - 12.0), font)


## A força enquanto o botão está seguro: a barra enche da esquerda para a direita,
## do limão ao coral perto do máximo.
func _draw_power() -> void:
	var track := _track_rect().grow_individual(0.0, 6.0, 0.0, 6.0)
	var font := AppTheme.font(800)
	_draw_bar_back(track)
	if _power > 0.0:
		var fill := Rect2(track.position, Vector2(track.size.x * _power, track.size.y))
		draw_rect(fill, AppTheme.ACCENT.lerp(AppTheme.DANGER, clampf((_power - 0.75) * 4.0, 0.0, 1.0)))
	_caption("FORÇA %d%%" % roundi(_power * 100.0), Vector2(track.get_center().x, track.position.y - 12.0), font)


## Onde um ângulo do balanço cai na barra: recuado à esquerda, à frente à direita.
## A barra é o balanço inteiro desta força, então o verde estreita com mais força.
func _bar_x(track: Rect2, angle: float) -> float:
	var reach := maxf(_top, 1.0)
	return track.position.x + clampf((reach - angle) / (2.0 * reach), 0.0, 1.0) * track.size.x


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
