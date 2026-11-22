extends SceneTree

## Gera os conjuntos de peças de xadrez da loja (`Cosmetics`, encaixe `pieces`)
## em `assets/pieces/sets/<conjunto>/`, e uma folha de conferência em
## `user://piece_sets.png`. Rodar de novo depois de mexer aqui:
##
##   godot --headless --path . --script res://tools/build_piece_sets.gd
##
## As peças usam só as duas tintas dos SVGs de sempre (`PieceRenderer.SVG_LIGHT`
## e `SVG_DARK`): corpo numa, contorno e detalhes na outra, trocadas na peça
## preta. É o que deixa qualquer conjunto combinar com qualquer acabamento.
## Os `.import` saem como `keep`, porque o `PieceRenderer` lê o SVG cru.
##
## Tudo num quadro de 72×72, com o centro em x = 36 e a base em y = 66. Um
## perfil torneado (`_lathe`) é a metade direita da silhueta, de baixo para cima,
## em pares (meia largura, y), espelhada; ponto repetido vira quina, o resto é
## curva (Catmull-Rom).

const OUT := "res://assets/pieces/sets"
const KINDS := ["pawn", "knight", "bishop", "rook", "queen", "king"]
const STROKE := 3.5
## Quanto o conjunto em construção é alargado em torno do centro. As peças são
## desenhadas magras, como de verdade, mas no celular a casa tem uns 45 px, e as
## de sempre ocupam a casa quase toda: sem alargar, as novas sumiam ao lado delas.
static var _widen := 1.0


func _init() -> void:
	var sets := {}
	for entry in [["staunton", 1.25, _staunton], ["minimal", 1.1, _minimal], ["medieval", 1.15, _medieval]]:
		_widen = entry[1]
		sets[entry[0]] = (entry[2] as Callable).call()
	for name: String in sets:
		var dir := "%s/%s" % [OUT, name]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for kind: String in KINDS:
			for white in [true, false]:
				var path := "%s/%s_%s.svg" % [dir, kind, "white" if white else "black"]
				_write(path, _svg(sets[name][kind], white))
				_write(path + ".import", '[remap]\n\nimporter="keep"\n')
		print("ok ", dir)
	_sheet(sets)
	quit()


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


static func _svg(parts: Array, white: bool) -> String:
	var body := PieceRenderer.SVG_LIGHT if white else PieceRenderer.SVG_DARK
	var line := PieceRenderer.SVG_DARK if white else PieceRenderer.SVG_LIGHT
	var text := '<svg width="72" height="72" viewBox="0 0 72 72" fill="none" xmlns="http://www.w3.org/2000/svg">\n'
	for part: String in parts:
		text += part.replace("{B}", body).replace("{L}", line) + "\n"
	return text + "</svg>\n"


## A folha de conferência: cada conjunto em duas fileiras (brancas na casa clara,
## pretas na escura), e depois o cavalo e a dama de cada conjunto em cada
## acabamento.
func _sheet(sets: Dictionary) -> void:
	const CELL := 96
	var finishes: Array[String] = [""]
	finishes.append_array(Cosmetics.of_slot(Cosmetics.FINISH))
	var columns := KINDS.size()
	var rows := sets.size() * 2 + sets.size()
	var sheet := Image.create_empty(CELL * columns * 2, CELL * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(AppTheme.BACKGROUND)
	var row := 0
	for name: String in sets:
		for white in [true, false]:
			for i in columns:
				var square := AppTheme.BOARD_LIGHT if white else AppTheme.BOARD_DARK
				sheet.fill_rect(Rect2i(i * CELL * 2, row * CELL, CELL * 2, CELL), square)
				_stamp(sheet, _svg(sets[name][KINDS[i]], white), Vector2i(i * CELL * 2 + CELL / 2, row * CELL), CELL)
			row += 1
		var spot := 0
		for finish in finishes:
			for kind: String in ["knight", "queen"]:
				for white in [true, false]:
					var svg := _svg(sets[name][kind], white)
					if not finish.is_empty():
						svg = PieceRenderer.recolor(svg, white, Cosmetics.finish_paint(finish, Board.Side.WHITE if white else Board.Side.BLACK))
					_stamp(sheet, svg, Vector2i(spot * CELL / 2, row * CELL + CELL / 4), CELL / 2)
					spot += 1
		row += 1
	sheet.save_png("user://piece_sets.png")
	print("folha ", ProjectSettings.globalize_path("user://piece_sets.png"))


static func _stamp(sheet: Image, svg: String, at: Vector2i, size: int) -> void:
	var image := Image.new()
	image.load_svg_from_string(svg, size / 72.0)
	image.convert(Image.FORMAT_RGBA8)
	sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)


# --- formas -------------------------------------------------------------------


static func _points(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(Vector2(flat[i], flat[i + 1]))
	return out


## Perfil torneado: pares (meia largura, y) da metade direita, de baixo para cima.
static func _lathe(flat: Array) -> PackedVector2Array:
	var right := _points(flat)
	var out := PackedVector2Array()
	for point in right:
		out.append(Vector2(36 + point.x, point.y))
	for i in range(right.size() - 1, -1, -1):
		if right[i].x > 0.0:
			out.append(Vector2(36 - right[i].x, right[i].y))
	return out


## Caminho fechado e liso pelos pontos (Catmull-Rom em cúbicas). Ponto repetido
## vira quina.
static func _smooth(points: PackedVector2Array) -> String:
	var n := points.size()
	var d := "M%s" % _xy(points[0])
	for i in n:
		var p0 := points[(i - 1 + n) % n]
		var p1 := points[i]
		var p2 := points[(i + 1) % n]
		var p3 := points[(i + 2) % n]
		if p1.is_equal_approx(p2):
			continue
		var c1 := p1 + (p2 - p0) / 6.0 if not p0.is_equal_approx(p1) else p1 + (p2 - p1) / 3.0
		var c2 := p2 - (p3 - p1) / 6.0 if not p2.is_equal_approx(p3) else p2 - (p2 - p1) / 3.0
		d += "C%s %s %s" % [_xy(c1), _xy(c2), _xy(p2)]
	return d + "Z"


static func _poly(flat: Array) -> String:
	var points := _points(flat)
	var d := "M%s" % _xy(points[0])
	for i in range(1, points.size()):
		d += "L%s" % _xy(points[i])
	return d + "Z"


static func _xy(point: Vector2) -> String:
	return "%s %s" % [snappedf(_x(point.x), 0.01), snappedf(point.y, 0.01)]


## Um x do desenho, alargado (`_widen`) em torno do centro.
static func _x(x: float) -> float:
	return 36.0 + (x - 36.0) * _widen


## Uma área com o corpo numa tinta e o contorno na outra.
static func _body(d: String) -> String:
	return '<path d="%s" fill="{B}" stroke="{L}" stroke-width="%s" stroke-linejoin="round"/>' % [d, STROKE]


static func _disc(x: float, y: float, r: float) -> String:
	return '<circle cx="%s" cy="%s" r="%s" fill="{B}" stroke="{L}" stroke-width="%s"/>' % [snappedf(_x(x), 0.01), y, r * sqrt(_widen), STROKE]


static func _rect(x: float, y: float, w: float, h: float, r: float) -> String:
	return '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="{B}" stroke="{L}" stroke-width="%s" stroke-linejoin="round"/>' % [snappedf(_x(x), 0.01), y, snappedf(w * _widen, 0.01), h, r, STROKE]


## Um traço na tinta do contorno (fenda, cruz, detalhe), em comandos absolutos
## M, L, Q, H e V, com os x alargados como o resto.
static func _line(d: String, width := 3.0) -> String:
	return '<path d="%s" stroke="{L}" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % [_widen_path(d), width]


static func _widen_path(d: String) -> String:
	var regex := RegEx.create_from_string("([MLQHV])([^MLQHVZ]*)")
	var out := ""
	for found in regex.search_all(d):
		var command := found.get_string(1)
		var numbers := found.get_string(2).strip_edges().split(" ", false)
		for i in numbers.size():
			# Os x são as posições pares (M, L, Q) e todos os de H; V só tem y.
			if command == "H" or (command != "V" and i % 2 == 0):
				numbers[i] = str(snappedf(_x(float(numbers[i])), 0.01))
		out += command + " ".join(numbers)
	return out + ("Z" if d.ends_with("Z") else "")


## Um ponto cheio na tinta do contorno (olho).
static func _dot(x: float, y: float, r: float) -> String:
	return '<circle cx="%s" cy="%s" r="%s" fill="{L}"/>' % [snappedf(_x(x), 0.01), y, r]


# --- Staunton clássico ---------------------------------------------------------
#
# O torneado de torneio: base larga com degrau, colarinho e cabeça de cada peça.


static func _staunton() -> Dictionary:
	return {
		"pawn": [
			_body(_smooth(_lathe([17, 66, 17, 66, 17, 61, 17, 61, 13, 59, 10, 58, 10, 58, 10, 55, 10, 55, 7, 52, 5, 45, 5, 40, 5, 40, 9, 38, 9, 38, 9, 35, 9, 35, 0, 35]))),
			_disc(36, 27, 9),
		],
		"rook": [
			_body(_smooth(_lathe([18, 66, 18, 66, 18, 61, 18, 61, 14, 59, 11, 57, 11, 57, 11, 54, 11, 54, 9, 50, 9, 33, 9, 33, 0, 33]))),
			_body(_poly([24, 34, 24, 13, 29.5, 13, 29.5, 18, 33.5, 18, 33.5, 13, 38.5, 13, 38.5, 18, 42.5, 18, 42.5, 13, 48, 13, 48, 34])),
		],
		"bishop": [
			_body(_smooth(_lathe([17, 66, 17, 66, 17, 61, 17, 61, 13, 59, 10, 57, 10, 57, 10, 54, 10, 54, 7, 50, 5, 44, 5, 42, 5, 42, 10, 40, 10, 40, 10, 37, 10, 37, 0, 37]))),
			_body(_smooth(_lathe([6, 38, 6, 38, 9, 34, 11, 28, 9, 21, 5, 16, 0, 13]))),
			_disc(36, 9, 3.5),
			_line("M39 21L33 28"),
		],
		"knight": [
			_body(_smooth(_lathe([18, 66, 18, 66, 18, 61, 18, 61, 14, 59, 11, 57, 11, 57, 0, 57]))),
			_body(_smooth(_points([
				49, 58, 49, 58, 51, 46, 50, 36, 47, 26, 42, 17, 38, 12, 38, 12, 37, 4, 37, 4,
				32, 9, 26, 12, 20, 18, 15, 25, 11, 31, 11, 31, 13, 35, 13, 35, 18, 36, 24, 34,
				29, 33, 29, 33, 30, 38, 26, 44, 22, 51, 21, 58, 21, 58,
			]))),
			_dot(29, 20, 2.2),
			_line("M41 24Q47 34 46 48", 2.5),
		],
		"queen": [
			_body(_smooth(_lathe([19, 66, 19, 66, 19, 61, 19, 61, 15, 59, 12, 57, 12, 57, 12, 54, 12, 54, 8, 49, 6, 40, 7, 32, 7, 32, 12, 30, 12, 30, 12, 27, 12, 27, 0, 27]))),
			_body(_poly([25, 29, 22, 14, 25.5, 22, 29, 11, 32.5, 22, 36, 9, 39.5, 22, 43, 11, 46.5, 22, 50, 14, 47, 29])),
			_disc(22, 13, 2.6), _disc(29, 10, 2.6), _disc(36, 8, 2.6), _disc(43, 10, 2.6), _disc(50, 13, 2.6),
		],
		"king": [
			_body(_smooth(_lathe([19, 66, 19, 66, 19, 61, 19, 61, 15, 59, 12, 57, 12, 57, 12, 54, 12, 54, 8, 49, 6, 40, 7, 31, 7, 31, 12, 29, 12, 29, 12, 26, 12, 26, 0, 26]))),
			_body(_smooth(_points([26, 27, 26, 27, 23, 17, 23, 17, 36, 14, 49, 17, 49, 17, 46, 27, 46, 27]))),
			_body(_poly([34, 15, 34, 10, 30, 10, 30, 6, 34, 6, 34, 2, 38, 2, 38, 6, 42, 6, 42, 10, 38, 10, 38, 15])),
		],
	}


# --- Minimalista --------------------------------------------------------------
#
# Formas puras: retângulo, trapézio, círculo e triângulo, com a mesma base em
# todas. O que diz a peça é só o topo.


static func _minimal() -> Dictionary:
	return {
		"pawn": [
			_body(_poly([28, 58, 32, 38, 40, 38, 44, 58])),
			_disc(36, 29, 8),
			_rect(21, 58, 30, 8, 3),
		],
		"rook": [
			_body(_poly([25, 58, 25, 31, 47, 31, 47, 58])),
			_body(_poly([21, 32, 21, 14, 28, 14, 28, 20, 32.5, 20, 32.5, 14, 39.5, 14, 39.5, 20, 44, 20, 44, 14, 51, 14, 51, 32])),
			_rect(19, 58, 34, 8, 3),
		],
		"bishop": [
			_body(_smooth(_lathe([9, 58, 9, 58, 12, 46, 11, 34, 7, 24, 0, 14, 0, 14]))),
			_disc(36, 9, 3),
			_line("M41 27L32 37", 3.5),
			_rect(21, 58, 30, 8, 3),
		],
		"knight": [
			_body(_poly([22, 58, 24, 45, 31, 37, 19, 35, 15, 29, 27, 15, 33, 11, 36, 5, 41, 12, 49, 22, 53, 36, 52, 58])),
			_dot(31, 21, 2.2),
			_rect(19, 58, 36, 8, 3),
		],
		"queen": [
			_body(_poly([26, 58, 30, 30, 42, 30, 46, 58])),
			_body(_poly([24, 31, 22, 15, 29, 23, 36, 12, 43, 23, 50, 15, 48, 31])),
			_disc(36, 9, 3.5),
			_rect(20, 58, 32, 8, 3),
		],
		"king": [
			_body(_poly([25, 58, 29, 29, 43, 29, 47, 58])),
			_rect(24, 18, 24, 12, 2),
			_line("M36 3V14M31 8.5H41", 4.0),
			_rect(20, 58, 32, 8, 3),
		],
	}


# --- Medieval -----------------------------------------------------------------
#
# Figuras de um exército: soldado de elmo, torre com portão, bispo de mitra,
# cavalo de armadura com penacho, rainha e rei de coroa, sobre o mesmo pedestal.


static func _medieval() -> Dictionary:
	var pedestal := _rect(17, 60, 38, 6, 2)
	return {
		"pawn": [
			_body(_poly([26, 60, 29, 44, 43, 44, 46, 60])),
			_disc(36, 37, 7.5),
			_body(_smooth(_lathe([13, 33, 13, 33, 13, 30, 13, 30, 9, 29, 9, 24, 6, 20, 0, 19]))),
			_line("M36 30V41", 2.5),
			pedestal,
		],
		"rook": [
			_body(_poly([23, 60, 25, 28, 47, 28, 49, 60])),
			_body(_poly([21, 29, 21, 12, 27, 12, 27, 17, 31, 17, 31, 12, 41, 12, 41, 17, 45, 17, 45, 12, 51, 12, 51, 29])),
			'<path d="%s" fill="{L}"/>' % _widen_path("M31 60V51Q31 45 36 45Q41 45 41 51V60Z"),
			_line("M36 34V39", 3.0),
			pedestal,
		],
		"bishop": [
			_body(_poly([24, 60, 28, 38, 44, 38, 48, 60])),
			_body(_smooth(_points([26, 40, 26, 40, 27, 28, 31, 18, 36, 10, 36, 10, 41, 18, 45, 28, 46, 40, 46, 40]))),
			_line("M36 16V38M31.5 25H40.5", 2.8),
			pedestal,
		],
		"knight": [
			_body(_smooth(_points([
				48, 60, 48, 60, 50, 47, 49, 37, 46, 27, 41, 19, 37, 15, 37, 15, 36, 8, 36, 8,
				31, 12, 25, 15, 19, 21, 14, 28, 11, 33, 11, 33, 13, 37, 13, 37, 18, 38, 24, 36,
				29, 35, 29, 35, 30, 40, 26, 46, 23, 53, 22, 60, 22, 60,
			]))),
			_body(_smooth(_points([38, 14, 42, 7, 49, 4, 52, 9, 49, 13, 53, 18, 49, 22, 44, 20]))),
			_line("M17 27L28 17M24 33L33 24", 2.4),
			_dot(30, 22, 2.2),
			pedestal,
		],
		"queen": [
			_body(_poly([23, 60, 29, 32, 43, 32, 49, 60])),
			_disc(36, 27, 7),
			_body(_poly([26, 22, 25, 12, 30.5, 17, 36, 8, 41.5, 17, 47, 12, 46, 22])),
			_dot(36, 8, 2.4), _dot(25, 12, 2.0), _dot(47, 12, 2.0),
			pedestal,
		],
		"king": [
			_body(_poly([22, 60, 28, 31, 44, 31, 50, 60])),
			_disc(36, 26, 7),
			_body(_poly([25, 21, 25, 11, 29, 15, 33, 10, 36, 13, 39, 10, 43, 15, 47, 11, 47, 21])),
			_line("M36 1.5V9M32.5 5H39.5", 3.0),
			_line("M27 45H45", 2.5),
			pedestal,
		],
	}
