class_name Confetti
extends Control

## Uma chuva curta de confete por cima do fim de partida, nas cores dos jogos.
##
## Desenhada à mão, e não com partículas: são trinta retângulos por pouco mais de
## um segundo, e um `_process` que se desliga sozinho no fim custa menos que um
## sistema de partículas montado para isso. Não pega toque.

const COUNT := 30
const LIFE := 1.6
const GRAVITY := 900.0

var _pieces: Array[Dictionary] = []
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Solta o confete a partir do topo da área deste nó.
func burst() -> void:
	var colors: Array = AppTheme.GAME_COLORS.values()
	colors.append(AppTheme.ACCENT)
	_pieces.clear()
	for index in COUNT:
		_pieces.append({
			"at": Vector2(randf() * size.x, -20.0 - randf() * size.y * 0.15),
			"speed": Vector2(randf_range(-80.0, 80.0), randf_range(80.0, 260.0)),
			"spin": randf_range(-6.0, 6.0),
			"angle": randf() * TAU,
			"size": Vector2(randf_range(8.0, 12.0), randf_range(12.0, 18.0)),
			"color": colors[index % colors.size()],
		})
	_time = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	for piece in _pieces:
		piece["speed"].y += GRAVITY * delta * 0.35
		piece["at"] += piece["speed"] * delta
		piece["angle"] += piece["spin"] * delta
	if _time >= LIFE:
		_pieces.clear()
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var fade := clampf((LIFE - _time) / 0.4, 0.0, 1.0)
	for piece in _pieces:
		draw_set_transform(piece["at"], piece["angle"], Vector2.ONE)
		var half: Vector2 = piece["size"] * 0.5
		draw_rect(Rect2(-half, piece["size"]), Color(piece["color"], fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
