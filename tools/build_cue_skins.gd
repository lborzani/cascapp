extends SceneTree

## Gera as texturas dos tacos da loja (`Cosmetics`, encaixe `cue`) em
## `assets/pool/cues/`. Rodar de novo depois de mexer aqui:
##
##   godot --headless --path . --script res://tools/build_cue_skins.gd
##
## Uma textura é o taco inteiro desenrolado: x vai da ponta (0) ao fim do cabo
## (1), ao longo dos 1,15 m do `cue.glb`, e y dá a volta no taco. O shader
## `ui/cue_skin.gdshader` a projeta pela posição local, então o modelo não
## precisa de UV. A ponta azul e a virola continuam as do modelo.
##
## O alfa marca o metal: 1 é madeira, couro ou tinta; `METAL` é metal (o shader
## usa `1 - alfa` como `METALLIC`). Os `.import` delas desligam o
## `fix_alpha_border`, que trocaria a cor do pixel quase transparente, e ligam
## os mipmaps, senão a trama fina pisca no taco que tem 3 px de altura.

const WIDTH := 1024
const HEIGHT := 128
const OUT := "res://assets/pool/cues"
## Onde cada trecho do `cue.glb` começa, em fração do comprimento (ver
## `build_cue` em `art/pool/build_pool.py`: 0,032, 0,700, 0,712, 0,860, 1,080 m).
const SHAFT := 0.0278
const JOINT := 0.6087
const FOREARM := 0.6191
const GRIP := 0.7478
const BUTT := 0.9391
const METAL := 0.15


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for name: String in ["default", "ebony", "carbon", "flames", "neon", "gold"]:
		var image := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
		var paint: Callable = Callable(self, "_" + name)
		for y in HEIGHT:
			for x in WIDTH:
				image.set_pixel(x, y, paint.call((x + 0.5) / WIDTH, (y + 0.5) / HEIGHT))
		image.save_png("%s/cue_%s.png" % [OUT, name])
		print("ok ", name)
	quit()


static func _noise(seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 1.0
	return noise


static var _grain := _noise(3)


## Veio de madeira ao longo do taco.
static func _wood(base: Color, u: float, v: float, strength := 0.08) -> Color:
	var streak := _grain.get_noise_2d(u * 6.0, v * 40.0)
	return base.darkened(strength * (0.5 + 0.5 * streak))


## Anéis finos no começo e no fim de um trecho.
static func _rings(u: float, from: float, to: float, width := 0.004) -> bool:
	return u - from < width or to - u < width


## O taco de sempre, com as cores dos materiais do `cue.glb`: só para a amostra
## da loja, o jogo sem item usa o modelo como ele é.
func _default(u: float, v: float) -> Color:
	if u < JOINT:
		return _wood(Color("d9b27c"), u, v)
	if u < FOREARM:
		return Color("e8e4dc")
	if u < GRIP or u >= BUTT:
		return _wood(Color("3a2416"), u, v, 0.15)
	return Color("1c1714")


## Ébano e marfim: haste clara, ébano com losangos de marfim, cabo de linho.
func _ebony(u: float, v: float) -> Color:
	var ivory := Color("efe6d2")
	var ebony := Color("1b1412")
	if u < JOINT:
		return _wood(ivory, u, v, 0.05)
	if u < FOREARM:
		return Color(Color("d9dde2"), METAL)
	if u < GRIP:
		if _rings(u, FOREARM, GRIP):
			return ivory
		# Quatro losangos de marfim em volta, apontando para a ponta.
		var along := absf((u - (FOREARM + GRIP) * 0.5) / ((GRIP - FOREARM) * 0.32))
		var around := absf(fposmod(v * 4.0, 1.0) - 0.5) / 0.32
		return ivory if along + around < 1.0 else _wood(ebony, u, v, 0.3)
	if u < BUTT:
		var wrap := fposmod((u * 260.0) + v * 3.0, 1.0)
		return Color("2a2320") if wrap < 0.5 else Color("191513")
	return ivory if _rings(u, BUTT, 1.0, 0.006) or absf(u - 0.967) < 0.003 else _wood(ebony, u, v, 0.3)


## Fibra de carbono: trama em sarja, anéis vermelhos e cabo emborrachado.
func _carbon(u: float, v: float) -> Color:
	var red := Color("e0302f")
	var weave := fposmod(floorf(u * 220.0) + floorf(v * 24.0), 4.0)
	var carbon := Color("2c2e33") if weave < 2.0 else Color("17181b")
	if u < JOINT:
		return carbon
	if u < FOREARM:
		return Color(red, METAL)
	if u < GRIP:
		return red if _rings(u, FOREARM, GRIP, 0.006) or absf(u - (FOREARM + GRIP) * 0.5) < 0.003 else carbon
	if u < BUTT:
		var dots := Vector2(fposmod(u * 160.0, 1.0) - 0.5, fposmod(v * 16.0, 1.0) - 0.5).length()
		return Color("26272a") if dots < 0.3 else Color("111214")
	return red if _rings(u, BUTT, 1.0, 0.006) else carbon


## Chamas: haste natural e chamas subindo do cabo para a ponta.
func _flames(u: float, v: float) -> Color:
	var black := Color("141110")
	if u < JOINT:
		return _wood(Color("e2c08a"), u, v)
	if u < FOREARM:
		return black
	if u >= GRIP and u < BUTT:
		return Color("1c1714")
	var start := FOREARM if u < GRIP else BUTT
	var end := GRIP if u < GRIP else 1.0
	# Seis línguas em volta. `reach` é até onde a língua chega (0 no começo do
	# trecho, do lado da ponta, 1 no fim); a chama nasce do lado do cabo.
	var f := (u - start) / (end - start)
	var lane := absf(fposmod(v * 6.0 + f * 0.6, 1.0) - 0.5) * 2.0
	var reach := 0.25 + 0.55 * pow(lane, 1.6)
	if f < reach:
		return black
	var heat := clampf((f - reach) / 0.35, 0.0, 1.0)
	return Color("ffe066").lerp(Color("ff7a1a"), heat).lerp(Color("c81d11"), maxf(heat - 0.6, 0.0) * 2.0)


## Neon: escuro com tubos ciano e magenta, que brilham (o item tem `glow`).
func _neon(u: float, v: float) -> Color:
	var dark := Color("120e22")
	var cyan := Color("39e6ff")
	var magenta := Color("ff4fd8")
	if u < JOINT:
		return cyan if absf(fposmod(v * 2.0, 1.0) - 0.5) < 0.04 else dark
	if u < FOREARM:
		return magenta
	if u < GRIP:
		var chevron := fposmod((u - FOREARM) * 90.0 + absf(fposmod(v * 3.0, 1.0) - 0.5) * 2.0, 1.0)
		if chevron < 0.18:
			return magenta
		if chevron > 0.5 and chevron < 0.6:
			return cyan
		return dark
	if u < BUTT:
		return cyan if fposmod(u * 80.0, 1.0) < 0.12 else Color("0b0916")
	return magenta if _rings(u, BUTT, 1.0, 0.008) else dark


## Ouro: haste creme, ouro gravado e cabo preto.
func _gold(u: float, v: float) -> Color:
	var gold := Color("e2b54d")
	if u < JOINT:
		return _wood(Color("f1e7d2"), u, v, 0.05)
	if u < FOREARM:
		return Color(gold, METAL)
	if u < GRIP:
		# Volutas gravadas: uma onda que se repete em volta, em traço escuro.
		var wave := sin((u - FOREARM) * 150.0 + sin(v * TAU * 3.0) * 2.2)
		if absf(wave) < 0.12:
			return Color("5a3d0c")
		return Color(gold.lightened(0.15 * (0.5 + 0.5 * sin(v * TAU))), METAL)
	if u < BUTT:
		return Color("17120c")
	return Color("17120c") if absf(u - 0.967) < 0.004 else Color(gold, METAL)
