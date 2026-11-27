class_name BowlingAudio
extends Node

## O som do boliche: o salão ao fundo, a bola rolando, os pinos batendo e a
## canaleta.
##
## Só **ouve** a pista: lê onde a bola e os pinos estão a cada passo de física e
## decide o som daí, sem sinal nenhum da física. Assim vale igual jogando aqui e
## seguindo a jogada de outro aparelho (`BowlingLane.following`), em que não há
## física e os corpos só são postos nos quadros recebidos.

## Um pino "acordou" (estava parado, agora anda) ou levou um tranco: m/s.
const WAKE_SPEED := 0.35
const JOLT := 1.2
## A velocidade de pino que dá a batida mais forte.
const LOUD_PIN := 4.0
## Um pino não soa duas vezes em menos que isto: na pancada a Jolt dá vários
## contatos seguidos, e todos virariam metralhadora.
const PIN_GAP := 0.09
## Volume dos laços, em dB, no máximo.
const HALL_DB := -20.0
const ROLL_DB := -8.0
const GUTTER_DB := -9.0
## Quão depressa o volume do rolar acompanha a bola (por segundo).
const ROLL_EASE := 10.0

var lane: BowlingLane = null

var _hall := AudioStreamPlayer.new()
var _roll := AudioStreamPlayer.new()
var _gutter := AudioStreamPlayer.new()
var _last_ball := Vector3.ZERO
var _had_ball := false
var _knocked := false
## Por pino: posição anterior, velocidade anterior e tempo desde a última batida.
var _pin_body: Array = []
var _pin_at: Array[Vector3] = []
var _pin_speed: Array[float] = []
var _pin_quiet: Array[float] = []
var _roll_level := 0.0
var _gutter_level := 0.0


func _init(watched: BowlingLane = null) -> void:
	lane = watched
	_pin_body.resize(BowlingRules.PINS)
	_pin_at.resize(BowlingRules.PINS)
	_pin_speed.resize(BowlingRules.PINS)
	_pin_quiet.resize(BowlingRules.PINS)
	_pin_speed.fill(0.0)
	_pin_quiet.fill(1.0)


func _ready() -> void:
	for player: AudioStreamPlayer in [_hall, _roll, _gutter]:
		player.bus = Sound.SFX_BUS
		player.volume_db = Sound.SILENT_DB
		add_child(player)
	_hall.volume_db = HALL_DB


func _physics_process(delta: float) -> void:
	_start_loops()
	if lane == null:
		return
	_listen_ball(delta)
	_listen_pins(delta)


## Os laços saem da thread do `Sound`; até ficarem prontos, nada a tocar.
func _start_loops() -> void:
	for pair: Array in [[_hall, Sound.Loop.HALL], [_roll, Sound.Loop.ROLL], [_gutter, Sound.Loop.GUTTER]]:
		var player: AudioStreamPlayer = pair[0]
		if player.stream == null:
			player.stream = Sound.loop(pair[1])
			if player.stream != null:
				player.play()


func _listen_ball(delta: float) -> void:
	var moving := lane.ball != null and (lane.rolling or lane.following)
	var on_wood := 0.0
	var in_gutter := 0.0
	if moving:
		var at := lane.ball.global_position
		var speed := at.distance_to(_last_ball) / maxf(delta, 0.0001) if _had_ball else 0.0
		_last_ball = at
		_had_ball = true
		var loud := clampf(speed / BowlingLane.FULL_SPEED, 0.0, 1.0)
		var before_pins := at.z > -BowlingLane.HEAD_PIN and at.y > -0.5
		if before_pins and absf(at.x) <= BowlingLane.LANE_W * 0.5:
			on_wood = loud
		elif before_pins:
			in_gutter = loud
		_roll.pitch_scale = lerpf(0.7, 1.25, loud)
		_gutter.pitch_scale = lerpf(0.8, 1.15, loud)
		if not _knocked and _touches_pin(at):
			_knocked = true
			Sound.play(Sound.Cue.KNOCK, linear_to_db(maxf(loud, 0.25)))
	else:
		_had_ball = false
		_knocked = false
	var blend := clampf(ROLL_EASE * delta, 0.0, 1.0)
	_roll_level = lerpf(_roll_level, on_wood, blend)
	_gutter_level = lerpf(_gutter_level, in_gutter, blend)
	_roll.volume_db = ROLL_DB + linear_to_db(maxf(_roll_level, 0.001))
	_gutter.volume_db = GUTTER_DB + linear_to_db(maxf(_gutter_level, 0.001))


## O mesmo teste da tremida da câmera (`BowlingView`): a bola encosta num pino.
func _touches_pin(at: Vector3) -> bool:
	for pin in lane.pins:
		if pin != null and Vector2(pin.global_position.x - at.x, pin.global_position.z - at.z).length() < BowlingLane.BALL_R + 0.06:
			return true
	return false


## Cada pino que sai do lugar ou leva um tranco dá uma batida, mais alta quanto
## mais rápido ele foi.
func _listen_pins(delta: float) -> void:
	for index in BowlingRules.PINS:
		var pin: RigidBody3D = lane.pins[index]
		if pin != _pin_body[index]:
			# Pino armado de novo (`rack` refaz os corpos): começa parado, sem batida.
			_pin_body[index] = pin
			_pin_speed[index] = 0.0
			if pin != null:
				_pin_at[index] = pin.global_position
			continue
		if pin == null:
			continue
		var at := pin.global_position
		var speed := at.distance_to(_pin_at[index]) / maxf(delta, 0.0001)
		var before := _pin_speed[index]
		_pin_at[index] = at
		_pin_speed[index] = speed
		_pin_quiet[index] += delta
		var woke := before < WAKE_SPEED * 0.5 and speed >= WAKE_SPEED
		var jolted := speed - before >= JOLT
		if (woke or jolted) and _pin_quiet[index] >= PIN_GAP:
			_pin_quiet[index] = 0.0
			var loud := clampf(speed / LOUD_PIN, 0.12, 1.0)
			Sound.play(Sound.Cue.PIN, linear_to_db(loud), randf_range(0.88, 1.14))
