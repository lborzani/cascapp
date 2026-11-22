extends SceneTree

## Gera as texturas dos tabuleiros da loja (`Cosmetics`, encaixe `board`) em
## `assets/boards/`. Rodar de novo depois de mexer aqui:
##
##   godot --headless --path . --script res://tools/build_board_textures.gd
##
## Cada textura cobre o tabuleiro inteiro (8×8 casas) e é em tons de cinza perto
## do branco: o `BoardView` recorta a região de cada casa e multiplica pela cor
## clara ou escura da skin. Assim uma textura só serve às duas cores, e a casa
## vizinha continua o veio em vez de repetir o mesmo pedaço.

const SIZE := 512
const OUT := "res://assets/boards"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_save("wood", _wood)
	_save("marble", _marble)
	_save("candy", _candy)
	_save("neon", _neon)
	quit()


func _save(name: String, shade: Callable) -> void:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_L8)
	for y in SIZE:
		for x in SIZE:
			var value: float = shade.call(float(x) / SIZE, float(y) / SIZE)
			image.set_pixel(x, y, Color(value, value, value))
	var path := "%s/%s.png" % [OUT, name]
	image.save_png(path)
	print("ok ", path)


static func _noise(seed: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = frequency
	noise.fractal_octaves = 4
	return noise


## Veio de madeira na horizontal: anéis ondulados pelo ruído, mais a fibra fina.
## O `BoardView` deita a textura nas casas escuras, então o veio alterna.
var _rings := _noise(7, 1.0)
var _fiber := _noise(11, 1.0)
func _wood(u: float, v: float) -> float:
	var ring := v * 30.0 + _rings.get_noise_2d(u * 0.9, v * 2.2) * 2.2
	var grain := pow(0.5 + 0.5 * sin(ring * TAU), 3.0)
	var fiber := 0.5 + 0.5 * _fiber.get_noise_2d(u * 2.0, v * 90.0)
	return 0.80 + 0.09 * (1.0 - grain) + 0.11 * fiber


## Mármore: veios finos e escuros numa diagonal torcida pela turbulência.
var _turbulence := _noise(23, 1.0)
var _cloud := _noise(29, 1.0)
func _marble(u: float, v: float) -> float:
	var twist := _turbulence.get_noise_2d(u * 1.6, v * 1.6)
	var band := absf(sin((u * 1.3 + v * 0.8) * TAU + twist * 3.2))
	var thin := absf(sin((u * 0.6 - v * 1.9) * TAU + twist * 4.5))
	var vein := smoothstep(0.0, 0.10, band) * (0.55 + 0.45 * smoothstep(0.0, 0.05, thin))
	return clampf(0.80 + 0.15 * vein + 0.05 * _cloud.get_noise_2d(u * 5.0, v * 5.0), 0.0, 1.0)


## Listras diagonais de bala, duas por casa.
func _candy(u: float, v: float) -> float:
	var stripe := fposmod((u + v) * 16.0, 1.0)
	var edge := 0.04
	var on := smoothstep(0.5 - edge, 0.5 + edge, stripe) * (1.0 - smoothstep(1.0 - edge, 1.0, stripe))
	on = maxf(on, 1.0 - smoothstep(0.0, edge, stripe))
	return 1.0 - 0.13 * on


## Neon: cada casa escura por dentro e acesa na borda. A cor da skin é a do tubo.
func _neon(u: float, v: float) -> float:
	var cell := Vector2(fposmod(u * 8.0, 1.0), fposmod(v * 8.0, 1.0))
	var edge := minf(minf(cell.x, 1.0 - cell.x), minf(cell.y, 1.0 - cell.y))
	return 0.24 + 0.76 * exp(-edge * 22.0)
