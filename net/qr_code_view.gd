@tool
class_name QrCodeView
extends Control

## Draws a QR code for `payload`, scaled to fit and centred, with the 4 module
## quiet zone the spec requires (without it most phone scanners refuse to lock).

const QUIET_ZONE := 4

@export var payload := "":
	set(value):
		payload = value
		_rebuild()

@export var light_color := Color(1, 1, 1)
@export var dark_color := Color(0.05, 0.05, 0.07)

var _size := 0
var _modules := PackedByteArray()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if payload.is_empty():
		_size = 0
		_modules = PackedByteArray()
	else:
		var code := QrEncoder.encode(payload)
		_size = int(code["size"])
		_modules = code["modules"]
	queue_redraw()


func _draw() -> void:
	if _size == 0:
		return
	var total := _size + QUIET_ZONE * 2
	# Integer module size keeps every module crisp; fractional scaling is the
	# usual cause of unreadable on-screen QR codes.
	var module_px := floori(minf(size.x, size.y) / total)
	if module_px < 1:
		module_px = 1
	var side := module_px * total
	var origin := ((size - Vector2(side, side)) * 0.5).floor()

	# Fundo claro com cantos arredondados: o QR mora dentro de um cartão escuro e
	# um retângulo duro brigaria com ele. A zona de silêncio garante que arredondar
	# não encosta em nenhum módulo.
	var background := StyleBoxFlat.new()
	background.bg_color = light_color
	background.set_corner_radius_all(module_px * 2)
	draw_style_box(background, Rect2(origin, Vector2(side, side)))
	for row in _size:
		for col in _size:
			if _modules[row * _size + col] == 0:
				continue
			var pos := origin + Vector2((col + QUIET_ZONE) * module_px, (row + QUIET_ZONE) * module_px)
			draw_rect(Rect2(pos, Vector2(module_px, module_px)), dark_color)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
