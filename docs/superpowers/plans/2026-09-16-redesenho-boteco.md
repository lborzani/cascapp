# Redesenho Boteco — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refazer a interface do Cascapp na direção Boteco sem alterar um pixel do que é protegido (logo, peças, barcos, tabuleiro de Metrópole, cartas de Uno).

**Architecture:** O tema continua construído em código em `ui/app_theme.gd` e aplicado na raiz de cada cena; a etapa 1 troca a paleta, embarca as fontes e cria os componentes base (`StyleBoxDashed`, `Coaster`, `PaperCard`, `SegmentedControl`). As etapas 2–6 reconstroem telas sobre esses componentes. Os desenhos protegidos são congelados **antes** da troca de paleta e conferidos por comparação de imagem.

**Tech Stack:** Godot 4.7.1 / GDScript tipado; testes headless (`--script` e cenas `.tscn`); folhas de print renderizadas com GPU.

**Spec:** `docs/superpowers/specs/2026-09-16-redesenho-boteco-design.md`

## Global Constraints

- Branch `feature/redesign-ui`; commits `tipo: descrição` com corpo explicando o porquê, terminando com `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Protegidos, nenhum pixel: `assets/icon/*`, `assets/pieces/*`, `scenes/piece_renderer.gd`, `ui/uno_card.gd`, `ui/monopoly_board_3d.gd` (tabuleiro, casas, hotéis, peões, destaque), `ui/monopoly_face.gd`, `ui/monopoly_token.gd`.
- Tabuleiros que ficam como estão: constantes `BOARD_LIGHT`, `BOARD_DARK`, `BOARD_FRAME`, `WATER`, `WATER_ALT`, `HULL`, `SPLASH`, `LAST_MOVE`, `PREMOVE` não mudam de valor.
- Tipagem estática em todo código novo; `signal.connect(callable)`; componentes sem dependência de autoload (rodam em `--script`).
- Toda cor de interface vem de `AppTheme`; nada de `Color("...")` solto em componente novo.
- Godot: `/c/Users/lucas/Desktop/godot/Godot_v4.7.1-stable_win64_console.exe` (abaixo, `$GODOT`).
- Antes de qualquer teste: `$GODOT --headless --path . --import` sem `SCRIPT ERROR`/`Parse Error` no log.

## Etapas

| Etapa | Entrega | Estado deste plano |
| --- | --- | --- |
| 1 | Fundação: referência dos protegidos, fontes, paleta, componentes base | **detalhada abaixo** |
| 2 | Navegação e menus (TabBar, Início, GameSheet, Online, sala de espera, Você, boas-vindas) | tarefas detalhadas ao iniciar a etapa |
| 3 | Partidas em pé (MatchBar, PlayerTag, xadrez/damas com modo mesa, naval, fim de partida) | idem |
| 4 | Partidas deitadas (Uno, Ludo, Sinuca, Metrópole, Bomberman) | idem |
| 5 | Como jogar (GameRulesDoc, 8 `.tres`, RulesPage, TableRulesDrawer) | idem |
| 6 | Limpeza, README, prints finais | idem |

As etapas 2–6 são detalhadas no começo de cada uma porque dependem da API
entregue pela anterior e de ler as cenas que vão reconstruir; detalhar agora
seria escrever código contra componentes que ainda não existem.

---

## Etapa 1 — Fundação

### Task 1: Referência dos desenhos protegidos

Congela, **antes de qualquer mudança**, uma imagem de referência de cada desenho
protegido, e cria a ferramenta que compara imagens. É o que prova, no fim da
etapa, que a troca de paleta e de fonte não tocou em nada protegido.

**Files:**
- Create: `tests/image_diff.gd`
- Modify: `tests/uno_sheet.gd:48`, `tests/piece_sheet.gd:32` (fundo fixo)

**Interfaces:**
- Produces: `$GODOT --headless --path . --script res://tests/image_diff.gd -- <a.png> <b.png> [x y w h]` → imprime `iguais` ou `diferentes: N pixels`, sai 0/1.

- [ ] **Step 1: Fundo fixo nas folhas de referência**

As duas folhas pintam o fundo com `AppTheme.BACKGROUND`, que vai mudar. Trocar
pela cor literal de hoje em `tests/uno_sheet.gd:48` e `tests/piece_sheet.gd:32`:

```gdscript
	# Fundo fixo, e não `AppTheme.BACKGROUND`: esta folha é a referência que prova
	# que as cartas não mudaram quando o tema muda. Com o fundo do tema, toda troca
	# de paleta sairia como "diferente" — inclusive as que não tocaram carta nenhuma.
	draw_rect(Rect2(Vector2.ZERO, size), REFERENCE_GROUND)
```

e, no topo de cada arquivo:

```gdscript
const REFERENCE_GROUND := Color("13100e")
```

- [ ] **Step 2: Escrever `tests/image_diff.gd`**

```gdscript
extends SceneTree

## Compara duas imagens pixel a pixel.
##
##   godot --headless --path . --script res://tests/image_diff.gd -- a.png b.png [x y w h]
##
## Existe para o redesenho: tudo o que é protegido (peças, cartas, tabuleiro de
## Metrópole) é renderizado antes e depois de cada etapa, e a resposta aceitável
## é uma só — zero pixels diferentes. Com a região opcional, compara só aquele
## retângulo, que é o que permite conferir o tabuleiro 3D sem os painéis em volta.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 and args.size() != 6:
		printerr("uso: -- a.png b.png [x y w h]")
		quit(2)
		return
	var first := Image.load_from_file(_path(args[0]))
	var second := Image.load_from_file(_path(args[1]))
	if first == null or second == null:
		printerr("não consegui abrir as duas imagens")
		quit(2)
		return
	if first.get_size() != second.get_size():
		printerr("tamanhos diferentes: %s e %s" % [first.get_size(), second.get_size()])
		quit(1)
		return
	var area := Rect2i(Vector2i.ZERO, first.get_size())
	if args.size() == 6:
		area = Rect2i(int(args[2]), int(args[3]), int(args[4]), int(args[5]))
	var differing := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				differing += 1
	if differing == 0:
		print("iguais (%dx%d em %s)" % [area.size.x, area.size.y, area.position])
		quit(0)
	else:
		printerr("diferentes: %d pixels" % differing)
		quit(1)


static func _path(raw: String) -> String:
	return ProjectSettings.globalize_path(raw) if raw.begins_with("user://") or raw.begins_with("res://") else raw
```

- [ ] **Step 3: Conferir a ferramenta**

```bash
$GODOT --headless --path . --script res://tests/image_diff.gd -- user://shots/01_jogos.png user://shots/01_jogos.png
```
Esperado: `iguais`, saída 0.

```bash
$GODOT --headless --path . --script res://tests/image_diff.gd -- user://shots/01_jogos.png user://shots/02_xadrez.png
```
Esperado: `diferentes: N pixels`, saída 1.

- [ ] **Step 4: Renderizar a referência (tema de hoje)**

```bash
$GODOT --path . --resolution 1100x1500 res://tests/uno_sheet.tscn
$GODOT --path . --resolution 720x1280 res://tests/piece_sheet.tscn
$GODOT --path . --resolution 1280x720 res://tests/monopoly_sheet.tscn
mkdir -p "$APPDATA/Godot/app_userdata/cascapp/baseline"
cp "$APPDATA/Godot/app_userdata/cascapp/"{uno_cards,pieces}.png "$APPDATA/Godot/app_userdata/cascapp/baseline/"
cp "$APPDATA/Godot/app_userdata/cascapp/shots/20h_metropole_tampo.png" "$APPDATA/Godot/app_userdata/cascapp/baseline/"
```

- [ ] **Step 5: Commit**

```bash
git add tests/image_diff.gd tests/uno_sheet.gd tests/piece_sheet.gd
git commit -m "test: referência por imagem dos desenhos protegidos"
```

### Task 2: Congelar os desenhos protegidos

Os desenhos protegidos leem três coisas do tema que vão mudar: a fonte
(`AppTheme.font`), o fundo (`AppTheme.BACKGROUND`) e cores de estado
(`DANGER`, `SUCCESS`, `ACCENT`). Cada leitura vira um valor fixo igual ao de
hoje, para a saída continuar idêntica.

**Files:**
- Modify: `ui/app_theme.gd` (adiciona `legacy_font`)
- Modify: `ui/uno_card.gd:140,384`
- Modify: `ui/monopoly_face.gd:203,244,307,474`
- Modify: `ui/monopoly_board_3d.gd:589,924,930,991`

**Interfaces:**
- Produces: `AppTheme.legacy_font(weight: int) -> Font` — a `SystemFont` de hoje, com cache próprio.

- [ ] **Step 1: `legacy_font` em `ui/app_theme.gd`**

```gdscript
static var _legacy_fonts := {}


## A fonte do sistema que o app usava antes do tema Boteco.
##
## Só para desenho **protegido**: os números das cartas de Uno e os nomes das casas
## de Metrópole foram desenhados com ela, e trocar a família mudaria o desenho.
## Interface nova usa `font()`, `display()` e `mono()`.
static func legacy_font(weight: int) -> Font:
	if _legacy_fonts.has(weight):
		return _legacy_fonts[weight]
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Roboto", "Segoe UI", "Noto Sans", "DejaVu Sans", "Arial"])
	system.font_weight = weight
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	system.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_legacy_fonts[weight] = system
	return system
```

- [ ] **Step 2: Cartas de Uno**

`ui/uno_card.gd:384`: `AppTheme.font(700)` → `AppTheme.legacy_font(700)`.
`ui/uno_card.gd:140`: `AppTheme.BACKGROUND` → `VEIL_COLOR`, com a constante:

```gdscript
## O véu da carta apagada. Fixo, e não o fundo do tema: a carta é desenho
## protegido, e o tom do véu faz parte de como ela aparece apagada.
const VEIL_COLOR := Color("13100e")
```

- [ ] **Step 3: Faces de Metrópole**

`ui/monopoly_face.gd:203,244,474`: `AppTheme.font(700)` → `AppTheme.legacy_font(700)`.
`ui/monopoly_face.gd:307`: `AppTheme.font(600)` → `AppTheme.legacy_font(600)`.

- [ ] **Step 4: Tabuleiro 3D de Metrópole**

Constantes novas perto do topo de `ui/monopoly_board_3d.gd`:

```gdscript
## Cores das peças do tabuleiro, fixas. Vinham do tema (`SUCCESS`, `DANGER`,
## `ACCENT`), e o tabuleiro é desenho protegido: a troca de paleta do app não pode
## pintar as casas de outro verde. O fundo da sala continua seguindo o tema — ele
## é o ambiente em volta da mesa, não a mesa.
const HOUSE_COLOR := Color("7ec27f")
const HOTEL_COLOR := Color("e05a4d")
const MARK_COLOR := Color("e05a4d")
const HIGHLIGHT_COLOR := Color("d9a441")
```

`:589` `Color(AppTheme.ACCENT, 0.30)` → `Color(HIGHLIGHT_COLOR, 0.30)`;
`:924` `AppTheme.DANGER` → `HOTEL_COLOR`; `:930` `AppTheme.SUCCESS` → `HOUSE_COLOR`;
`:991` `AppTheme.DANGER` → `MARK_COLOR`.

- [ ] **Step 5: Conferir que nada mudou ainda**

Renderizar de novo as três folhas (comandos do Task 1, Step 4) e comparar:

```bash
U="$APPDATA/Godot/app_userdata/cascapp"
$GODOT --headless --path . --script res://tests/image_diff.gd -- "$U/baseline/uno_cards.png" "$U/uno_cards.png"
$GODOT --headless --path . --script res://tests/image_diff.gd -- "$U/baseline/pieces.png" "$U/pieces.png"
$GODOT --headless --path . --script res://tests/image_diff.gd -- "$U/baseline/20h_metropole_tampo.png" "$U/shots/20h_metropole_tampo.png" 520 180 380 390
```
Esperado: `iguais` nas três.

- [ ] **Step 6: Suítes e commit**

Rodar `test_runner`, `monopoly_probe`, `uno_probe.tscn`, `uno_scene_probe.tscn`. Esperado: verdes.

```bash
git add ui/app_theme.gd ui/uno_card.gd ui/monopoly_face.gd ui/monopoly_board_3d.gd
git commit -m "refactor: desenhos protegidos deixam de ler o tema"
```

### Task 3: Fontes embarcadas

**Files:**
- Create: `assets/fonts/BigShouldersDisplay-Variable.ttf`, `assets/fonts/AtkinsonHyperlegible-Regular.ttf`, `assets/fonts/AtkinsonHyperlegible-Bold.ttf`, `assets/fonts/IBMPlexMono-Medium.ttf`, `assets/fonts/IBMPlexMono-SemiBold.ttf`, `assets/fonts/OFL-BigShouldersDisplay.txt`, `assets/fonts/OFL-AtkinsonHyperlegible.txt`, `assets/fonts/OFL-IBMPlexMono.txt`
- Modify: `ui/app_theme.gd` (`font`, `display`, `mono`, `Role`)
- Create: `tests/ui_kit_probe.gd`

**Interfaces:**
- Produces: `enum AppTheme.Role { BODY, DISPLAY, MONO }`; `AppTheme.font(weight: int, role := Role.BODY) -> Font`; `AppTheme.display(weight := 900) -> Font` (um `FontVariation` com eixo `wght`); `AppTheme.mono(weight := 600) -> Font`.

- [ ] **Step 1: Baixar (com autorização) de `github.com/google/fonts`, ramo `main`**

| Origem (`ofl/…`) | Destino | Bytes |
| --- | --- | --- |
| `bigshouldersdisplay/BigShouldersDisplay[wght].ttf` | `BigShouldersDisplay-Variable.ttf` | 219 532 |
| `bigshouldersdisplay/OFL.txt` | `OFL-BigShouldersDisplay.txt` | 4 396 |
| `atkinsonhyperlegible/AtkinsonHyperlegible-Regular.ttf` | igual | 54 348 |
| `atkinsonhyperlegible/AtkinsonHyperlegible-Bold.ttf` | igual | 55 256 |
| `atkinsonhyperlegible/OFL.txt` | `OFL-AtkinsonHyperlegible.txt` | 4 352 |
| `ibmplexmono/IBMPlexMono-Medium.ttf` | igual | 136 704 |
| `ibmplexmono/IBMPlexMono-SemiBold.ttf` | igual | 140 216 |
| `ibmplexmono/OFL.txt` | `OFL-IBMPlexMono.txt` | 4 456 |

Conferir o tamanho de cada arquivo baixado contra a tabela.

- [ ] **Step 2: Teste que falha — `tests/ui_kit_probe.gd`**

```gdscript
extends SceneTree

## Os componentes base do tema Boteco, sem autoload e sem GPU.
##
##   godot --headless --path . --script res://tests/ui_kit_probe.gd

var _failures := 0


func _initialize() -> void:
	_probe_fonts()
	if _failures == 0:
		print("OK — kit de interface consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


func _probe_fonts() -> void:
	print("fontes")
	var body := AppTheme.font(400)
	var bold := AppTheme.font(700)
	var display := AppTheme.display()
	var mono := AppTheme.mono()
	_check(body is FontFile and body.resource_path.ends_with("AtkinsonHyperlegible-Regular.ttf"), "corpo é a Atkinson Hyperlegible")
	_check(bold is FontFile and bold.resource_path.ends_with("AtkinsonHyperlegible-Bold.ttf"), "e o negrito é o arquivo negrito")
	_check(display is FontVariation, "display é uma variação da Big Shoulders")
	if display is FontVariation:
		var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
		_equals(int((display as FontVariation).variation_opentype.get(tag, 0)), 900, "no peso 900")
	_check(mono is FontFile and mono.resource_path.ends_with("IBMPlexMono-SemiBold.ttf"), "mono é a IBM Plex Mono")
	_check(AppTheme.legacy_font(700) is SystemFont, "a fonte antiga continua disponível para o que é protegido")
	_check(AppTheme.font(700) == AppTheme.font(700), "fontes em cache: a mesma instância a cada chamada")
	for letter in ["ç", "ã", "é", "ô", "Ú"]:
		var code := letter.unicode_at(0)
		_check(body.has_char(code) and display.has_char(code) and mono.has_char(code), "as três famílias têm '%s'" % letter)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
```

Run: `$GODOT --headless --path . --import` e depois `$GODOT --headless --path . --script res://tests/ui_kit_probe.gd`
Esperado: FAIL (`display` e `mono` não existem — erro de compilação conta como falha).

- [ ] **Step 3: Implementar em `ui/app_theme.gd`**

Substituir `font()` por:

```gdscript
enum Role { BODY, DISPLAY, MONO }

const FONT_BODY := "res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"
const FONT_BODY_BOLD := "res://assets/fonts/AtkinsonHyperlegible-Bold.ttf"
const FONT_DISPLAY := "res://assets/fonts/BigShouldersDisplay-Variable.ttf"
const FONT_MONO := "res://assets/fonts/IBMPlexMono-Medium.ttf"
const FONT_MONO_BOLD := "res://assets/fonts/IBMPlexMono-SemiBold.ttf"


## A fonte de um papel num peso.
##
## Embarcadas, e não mais `SystemFont`: o tema tem três vozes — o letreiro
## (Big Shoulders), o texto que precisa ser lido longe do rosto (Atkinson
## Hyperlegible) e os números que precisam alinhar (IBM Plex Mono) —, e nenhuma
## delas existe garantida num aparelho. Os pesos de corpo e mono são arquivos
## separados; o display é um arquivo variável com eixo de peso.
##
## Cacheado por papel e peso porque `draw_string` recebe a fonte a cada quadro:
## uma instância nova por chamada nunca chega a carregar os glifos e desenha
## blocos em vez de texto.
static func font(weight: int, role := Role.BODY) -> Font:
	var key := int(role) * 1000 + weight
	if _fonts.has(key):
		return _fonts[key]
	var result: Font
	match role:
		Role.DISPLAY:
			var variation := FontVariation.new()
			variation.base_font = load(FONT_DISPLAY)
			var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
			variation.variation_opentype = {tag: clampi(weight, 100, 900)}
			result = variation
		Role.MONO:
			result = load(FONT_MONO_BOLD if weight >= 600 else FONT_MONO)
		_:
			result = load(FONT_BODY_BOLD if weight >= 600 else FONT_BODY)
	_fonts[key] = result
	return result


static func display(weight := 900) -> Font:
	return font(weight, Role.DISPLAY)


static func mono(weight := 600) -> Font:
	return font(weight, Role.MONO)
```

- [ ] **Step 4: Rodar**

Run: `$GODOT --headless --path . --import` e `$GODOT --headless --path . --script res://tests/ui_kit_probe.gd`
Esperado: `OK — kit de interface consistente.`

- [ ] **Step 5: Commit**

```bash
git add assets/fonts ui/app_theme.gd tests/ui_kit_probe.gd
git commit -m "feat(tema): fontes do Boteco embarcadas"
```

### Task 4: `StyleBoxDashed`

**Files:**
- Create: `ui/style_box_dashed.gd`
- Modify: `tests/ui_kit_probe.gd`

**Interfaces:**
- Produces: `class_name StyleBoxDashed extends StyleBox` com `bg_color: Color`, `border_color: Color`, `border_width: float`, `corner_radius: float`, `dash: float`, `gap: float`; `static func outline_points(rect: Rect2, radius: float) -> PackedVector2Array`; `static func dash_segments(points: PackedVector2Array, dash: float, gap: float) -> PackedVector2Array` (pares início/fim).

- [ ] **Step 1: Teste que falha**

Acrescentar em `_initialize()` a chamada `_probe_dashed()` e:

```gdscript
func _probe_dashed() -> void:
	print("tracejado")
	var rounded := StyleBoxDashed.outline_points(Rect2(0, 0, 100, 40), 10.0)
	_equals(rounded.size(), 4 * (StyleBoxDashed.CORNER_STEPS + 1), "um arco de pontos por canto")
	_check(rounded[0].is_equal_approx(Vector2(90, 0)), "o contorno começa no fim da aresta de cima")
	var inside := true
	for point in rounded:
		inside = inside and Rect2(0, 0, 100, 40).grow(0.001).has_point(point)
	_check(inside, "e nenhum ponto sai do retângulo")
	var clamped := StyleBoxDashed.outline_points(Rect2(0, 0, 100, 40), 50.0)
	_check(clamped[0].is_equal_approx(Vector2(80, 0)), "raio maior que meia altura é limitado a ela")
	var square := StyleBoxDashed.outline_points(Rect2(0, 0, 100, 100), 0.0)
	_equals(square.size(), 4, "sem raio, um ponto por canto")
	var dashes := StyleBoxDashed.dash_segments(square, 10.0, 10.0)
	_equals(dashes.size() % 2, 0, "os traços vêm em pares")
	_check(absf(_drawn(dashes) - 200.0) < 0.01, "metade do perímetro desenhado com traço e vão iguais (obtido %.2f)" % _drawn(dashes))
	var longest := 0.0
	for i in range(0, dashes.size(), 2):
		longest = maxf(longest, dashes[i].distance_to(dashes[i + 1]))
	_check(longest <= 10.0001, "nenhum traço maior que o pedido")
	_check(absf(_drawn(StyleBoxDashed.dash_segments(square, 10.0, 0.0)) - 400.0) < 0.01, "sem vão, o contorno inteiro")


static func _drawn(segments: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(0, segments.size(), 2):
		total += segments[i].distance_to(segments[i + 1])
	return total
```

Run: `$GODOT --headless --path . --script res://tests/ui_kit_probe.gd` → FAIL (`StyleBoxDashed` não existe).

- [ ] **Step 2: Implementar `ui/style_box_dashed.gd`**

```gdscript
class_name StyleBoxDashed
extends StyleBox

## Contorno tracejado com cantos arredondados — a linha de giz do tema Boteco.
##
## `StyleBoxFlat` não tem traço: a borda dele é sempre contínua. O tracejado é a
## assinatura do tema em três lugares (painel secundário, separador, borda de
## folha), e desenhá-lo em cada `_draw` de cada tela seria repetir a mesma conta
## em vinte arquivos. Como `StyleBox`, ele entra no tema e em qualquer `Control`.
##
## A geometria mora em duas funções estáticas puras — o contorno e o corte em
## traços — porque é o que dá para testar sem GPU.

## Pontos por quarto de círculo. Oito já não mostram quina no tamanho de um botão.
const CORNER_STEPS := 8

@export var bg_color := Color(0, 0, 0, 0)
@export var border_color := Color(1, 1, 1, 0.45)
@export var border_width := 1.5
@export var corner_radius := 10.0
@export var dash := 6.0
@export var gap := 4.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if bg_color.a > 0.0:
		RenderingServer.canvas_item_add_polygon(
			to_canvas_item, outline_points(rect, corner_radius), PackedColorArray([bg_color])
		)
	if border_width <= 0.0 or border_color.a <= 0.0:
		return
	# O traço anda por dentro da borda, como o do `StyleBoxFlat`: centrado nela,
	# metade sairia do retângulo e seria cortada por quem recorta o conteúdo.
	var half := border_width * 0.5
	var path := outline_points(rect.grow(-half), maxf(corner_radius - half, 0.0))
	var segments := dash_segments(path, dash, gap)
	for i in range(0, segments.size(), 2):
		RenderingServer.canvas_item_add_line(
			to_canvas_item, segments[i], segments[i + 1], border_color, border_width, true
		)


## O contorno fechado de um retângulo arredondado, no sentido horário da tela,
## começando no fim da aresta de cima. Sem raio, um ponto por canto — pontos
## repetidos quebrariam a triangulação do preenchimento.
static func outline_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var steps := CORNER_STEPS if r > 0.0 else 0
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	var points := PackedVector2Array()
	for corner in corners:
		var center: Vector2 = corner[0]
		var start: float = corner[1]
		for step in steps + 1:
			var angle := start + (PI * 0.5) * (float(step) / maxf(steps, 1))
			points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points


## Corta um contorno fechado em traços: pares de pontos, início e fim de cada
## pedaço desenhado. Um traço que dobra um canto sai em mais de um pedaço, e
## visualmente continua sendo um traço só.
static func dash_segments(points: PackedVector2Array, dash: float, gap: float) -> PackedVector2Array:
	var segments := PackedVector2Array()
	if points.size() < 2 or dash <= 0.0:
		return segments
	var count := points.size()
	if gap <= 0.0:
		for i in count:
			segments.append(points[i])
			segments.append(points[(i + 1) % count])
		return segments
	var drawing := true
	var left := dash
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		var length := a.distance_to(b)
		var walked := 0.0
		while length - walked > 0.0001:
			var take := minf(left, length - walked)
			if drawing:
				segments.append(a.lerp(b, walked / length))
				segments.append(a.lerp(b, (walked + take) / length))
			walked += take
			left -= take
			if left <= 0.0001:
				drawing = not drawing
				left = dash if drawing else gap
	return segments
```

- [ ] **Step 3: Rodar** — `$GODOT --headless --path . --import` e o probe. Esperado: OK.

- [ ] **Step 4: Commit**

```bash
git add ui/style_box_dashed.gd tests/ui_kit_probe.gd
git commit -m "feat(tema): contorno tracejado como StyleBox"
```

### Task 5: Paleta e variações do Boteco

**Files:**
- Modify: `ui/app_theme.gd` (tokens, `contrast`, `dashed`, `plate`, `_style_*`)
- Modify: `tests/ui_kit_probe.gd`

**Interfaces:**
- Consumes: `StyleBoxDashed` (Task 4), `display()`/`mono()` (Task 3).
- Produces: tokens `BACKGROUND, SURFACE, SURFACE_HIGH, SURFACE_TOP, COASTER, TEXT, TEXT_DIM, LINE, LINE_SOFT, BORDER, ACCENT, ACCENT_SOFT, ACCENT_INK, ACCENT_EDGE, GOLD, PAPER, PAPER_INK, DANGER, DANGER_SOFT, SUCCESS, SUCCESS_SOFT`; raios `RADIUS := 10`, `RADIUS_LARGE := 16`, `RADIUS_PLATE := 6`, `RADIUS_PAPER := 3`; tamanhos `SIZE_DISPLAY_XL := 34`, `SIZE_DISPLAY_L := 26`, `SIZE_DISPLAY_M := 20`, `SIZE_BUTTON := 19`, `SIZE_BODY := 16`, `SIZE_BODY_S := 14`, `SIZE_CAPTION := 12`, `SIZE_MONO_L := 34`, `SIZE_MONO_M := 22`, `SIZE_MONO_S := 13`; `static func contrast(a: Color, b: Color) -> float`; `static func dashed(fill: Color, border: Color, radius := RADIUS, width := 1.5) -> StyleBoxDashed`; `static func plate(fill: Color, edge: Color, pressed := false) -> StyleBoxFlat`; variações novas `Segment`, `SegmentSelected`, `Mono`, e todas as existentes mantidas (`PrimaryButton`, `ChipButton`, `ChipSelected`, `AccentButton`, `SuccessButton`, `SuccessSolidButton`, `DangerButton`, `NavItem`, `NavItemSelected`, `IconButton`, `GhostButton`, `Display`, `Title`, `Subtitle`, `Greeting`, `SectionHeader`, `Caption`, `PairingCode`, `Card`, `QuietCard`).

- [ ] **Step 1: Teste que falha**

Acrescentar `_probe_palette()`:

```gdscript
func _probe_palette() -> void:
	print("paleta")
	_equals(AppTheme.BACKGROUND, Color("17211c"), "fundo é a lousa")
	_equals(AppTheme.ACCENT, Color("f2c029"), "destaque é o amarelo de cadeira")
	_equals(AppTheme.BOARD_LIGHT, Color("e9d8b8"), "casa clara do tabuleiro não mudou")
	_equals(AppTheme.BOARD_DARK, Color("8a5b3c"), "casa escura não mudou")
	_equals(AppTheme.WATER, Color("223a4d"), "o mar não mudou")
	var text_pairs := [
		["TEXT", AppTheme.TEXT, "BACKGROUND", AppTheme.BACKGROUND],
		["TEXT_DIM", AppTheme.TEXT_DIM, "BACKGROUND", AppTheme.BACKGROUND],
		["TEXT_DIM", AppTheme.TEXT_DIM, "SURFACE", AppTheme.SURFACE],
		["ACCENT_INK", AppTheme.ACCENT_INK, "ACCENT", AppTheme.ACCENT],
		["ACCENT", AppTheme.ACCENT, "BACKGROUND", AppTheme.BACKGROUND],
		["DANGER", AppTheme.DANGER, "BACKGROUND", AppTheme.BACKGROUND],
		["PAPER_INK", AppTheme.PAPER_INK, "PAPER", AppTheme.PAPER],
	]
	for pair in text_pairs:
		var ratio := AppTheme.contrast(pair[1], pair[3])
		_check(ratio >= 4.5, "%s sobre %s legível como texto (%.1f:1)" % [pair[0], pair[2], ratio])
	var line := AppTheme.contrast(AppTheme.BACKGROUND.blend(AppTheme.LINE), AppTheme.BACKGROUND)
	_check(line >= 3.0, "LINE contorna coisa tocável (%.1f:1)" % line)


func _probe_theme() -> void:
	print("tema")
	var theme := AppTheme.shared()
	for variation in ["PrimaryButton", "ChipButton", "ChipSelected", "AccentButton", "SuccessButton",
			"SuccessSolidButton", "DangerButton", "NavItem", "NavItemSelected", "IconButton",
			"GhostButton", "Segment", "SegmentSelected"]:
		_equals(String(theme.get_type_variation_base(variation)), "Button", "%s é variação de botão" % variation)
	for variation in ["Display", "Title", "Subtitle", "Greeting", "SectionHeader", "Caption", "PairingCode", "Mono"]:
		_equals(String(theme.get_type_variation_base(variation)), "Label", "%s é variação de rótulo" % variation)
	_check(theme.get_font("font", "Button") == AppTheme.display(900), "botão fala com a voz do letreiro")
	_equals(theme.get_color("font_color", "PrimaryButton"), AppTheme.ACCENT_INK, "placa amarela com tinta escura")
	_check(theme.get_stylebox("normal", "GhostButton") is StyleBoxDashed, "botão secundário é tracejado")
	_check(theme.get_font("font", "PairingCode") == AppTheme.mono(600), "código da sala em mono")
	_equals(theme.default_font_size, AppTheme.SIZE_BODY, "corpo em 16")
```

com `_probe_palette()` e `_probe_theme()` chamados em `_initialize()`.
Run → FAIL (tokens com valores antigos, `contrast` inexistente).

- [ ] **Step 2: Implementar — reescrever os blocos de constantes e `_style_*` de `ui/app_theme.gd`**

Constantes (substituem as de hoje; `LAST_MOVE`, `PREMOVE`, `BOARD_*`, `WATER*`, `HULL`, `SPLASH`, `RADIUS_ICON`, `RADIUS_PILL`, `SCREEN_PAD`, `SPACE_*`, `SCRIM`, `BAR_HEIGHT`, `NAV_HEIGHT` continuam iguais):

```gdscript
const BACKGROUND := Color("17211c")
const SURFACE := Color("1f2b25")
const SURFACE_HIGH := Color("2a3931")
const SURFACE_TOP := Color("33443a")
const COASTER := Color("0e1511")
const TEXT := Color("f1ede3")
const TEXT_DIM := Color("a4b0a7")
const LINE := Color("f1ede3", 0.45)
const LINE_SOFT := Color("f1ede3", 0.22)
const BORDER := LINE_SOFT
const ACCENT := Color("f2c029")
const ACCENT_SOFT := Color("f2c029", 0.12)
const ACCENT_INK := Color("1c1a10")
const ACCENT_EDGE := Color("b38c14")
const GOLD := Color("d9a441")
const PAPER := Color("efe7d4")
const PAPER_INK := Color("221c13")
const DANGER := Color("e8694c")
const DANGER_SOFT := Color("e8694c", 0.18)
const SUCCESS := Color("7ec27f")
const SUCCESS_SOFT := Color("7ec27f", 0.16)

const RADIUS := 10
const RADIUS_LARGE := 16
const RADIUS_PLATE := 6
const RADIUS_PAPER := 3
const PLATE_EDGE := 3

const SIZE_DISPLAY_XL := 34
const SIZE_DISPLAY_L := 26
const SIZE_DISPLAY_M := 20
const SIZE_BUTTON := 19
const SIZE_BODY := 16
const SIZE_BODY_S := 14
const SIZE_CAPTION := 12
const SIZE_MONO_L := 34
const SIZE_MONO_M := 22
const SIZE_MONO_S := 13
```

Funções novas:

```gdscript
## Razão de contraste WCAG entre duas cores opacas.
static func contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func dashed(fill: Color, border: Color, radius := RADIUS, width := 1.5) -> StyleBoxDashed:
	var style := StyleBoxDashed.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width = width
	style.corner_radius = radius
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


## A placa de plástico: preenchida, com a borda de baixo mais escura. Pressionada,
## a borda some e o texto desce a mesma altura — a placa afunda.
static func plate(fill: Color, edge: Color, pressed := false) -> StyleBoxFlat:
	var style := box(fill, RADIUS_PLATE)
	if pressed:
		style.content_margin_top += PLATE_EDGE
	else:
		style.border_width_bottom = PLATE_EDGE
		style.border_color = edge
	return style
```

`build()`:

```gdscript
static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = font(400)
	theme.default_font_size = SIZE_BODY
	_style_buttons(theme)
	_style_labels(theme)
	_style_inputs(theme)
	_style_panels(theme)
	return theme
```

`_style_buttons`:

```gdscript
static func _style_buttons(theme: Theme) -> void:
	theme.set_font("font", "Button", display(900))
	theme.set_font_size("font_size", "Button", SIZE_BUTTON)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.45))
	theme.set_stylebox("normal", "Button", box(SURFACE_HIGH, RADIUS))
	theme.set_stylebox("hover", "Button", box(SURFACE_HIGH.lightened(0.06), RADIUS))
	theme.set_stylebox("pressed", "Button", box(ACCENT_SOFT, RADIUS, ACCENT, 2))
	theme.set_stylebox("disabled", "Button", box(SURFACE, RADIUS))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), RADIUS, ACCENT, 2))

	# A placa amarela: a ação da tela. Uma por tela, no máximo.
	theme.set_type_variation("PrimaryButton", "Button")
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "PrimaryButton", ACCENT_INK)
	theme.set_color("font_disabled_color", "PrimaryButton", Color(ACCENT_INK, 0.6))
	theme.set_stylebox("normal", "PrimaryButton", plate(ACCENT, ACCENT_EDGE))
	theme.set_stylebox("hover", "PrimaryButton", plate(ACCENT.lightened(0.08), ACCENT_EDGE))
	theme.set_stylebox("pressed", "PrimaryButton", plate(ACCENT.darkened(0.08), ACCENT_EDGE, true))
	theme.set_stylebox("disabled", "PrimaryButton", plate(Color(ACCENT, 0.35), Color(ACCENT_EDGE, 0.35)))

	# Escolha dentro de um grupo: tracejado solto; marcada, contorno amarelo.
	theme.set_type_variation("ChipButton", "Button")
	theme.set_color("font_color", "ChipButton", TEXT_DIM)
	theme.set_color("font_hover_color", "ChipButton", TEXT)
	theme.set_color("font_pressed_color", "ChipButton", ACCENT)
	theme.set_stylebox("normal", "ChipButton", dashed(Color(0, 0, 0, 0), LINE))
	theme.set_stylebox("hover", "ChipButton", dashed(SURFACE, LINE))
	theme.set_stylebox("pressed", "ChipButton", box(ACCENT_SOFT, RADIUS, ACCENT, 2))

	theme.set_type_variation("ChipSelected", "Button")
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "ChipSelected", ACCENT)
	for state in ["normal", "hover", "pressed"]:
		theme.set_stylebox(state, "ChipSelected", box(ACCENT_SOFT, RADIUS, ACCENT, 2))

	_outlined(theme, "AccentButton", ACCENT, ACCENT_SOFT)
	_outlined(theme, "SuccessButton", SUCCESS, SUCCESS_SOFT)
	_outlined(theme, "DangerButton", DANGER, DANGER_SOFT)

	theme.set_type_variation("SuccessSolidButton", "Button")
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "SuccessSolidButton", ACCENT_INK)
	theme.set_stylebox("normal", "SuccessSolidButton", plate(SUCCESS, SUCCESS.darkened(0.35)))
	theme.set_stylebox("hover", "SuccessSolidButton", plate(SUCCESS.lightened(0.08), SUCCESS.darkened(0.35)))
	theme.set_stylebox("pressed", "SuccessSolidButton", plate(SUCCESS.darkened(0.08), SUCCESS.darkened(0.35), true))

	theme.set_type_variation("NavItem", "Button")
	theme.set_color("font_color", "NavItem", TEXT_DIM)
	theme.set_color("font_hover_color", "NavItem", TEXT)
	theme.set_stylebox("normal", "NavItem", box(Color(0, 0, 0, 0), RADIUS_PILL))
	theme.set_stylebox("hover", "NavItem", box(SURFACE_HIGH, RADIUS_PILL))
	theme.set_stylebox("pressed", "NavItem", box(ACCENT_SOFT, RADIUS_PILL))
	theme.set_type_variation("NavItemSelected", "Button")
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "NavItemSelected", ACCENT)
	for state in ["normal", "hover", "pressed"]:
		theme.set_stylebox(state, "NavItemSelected", box(ACCENT_SOFT, RADIUS_PILL))

	theme.set_type_variation("IconButton", "Button")
	theme.set_color("font_color", "IconButton", TEXT_DIM)
	theme.set_color("font_hover_color", "IconButton", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "IconButton", StyleBoxEmpty.new())

	# Ação secundária: tracejado de giz, sem preenchimento.
	theme.set_type_variation("GhostButton", "Button")
	theme.set_color("font_color", "GhostButton", TEXT)
	theme.set_color("font_hover_color", "GhostButton", TEXT)
	theme.set_color("font_pressed_color", "GhostButton", ACCENT)
	theme.set_stylebox("normal", "GhostButton", dashed(Color(0, 0, 0, 0), LINE))
	theme.set_stylebox("hover", "GhostButton", dashed(Color(TEXT, 0.05), LINE))
	theme.set_stylebox("pressed", "GhostButton", dashed(ACCENT_SOFT, ACCENT))

	# Segmentos do `SegmentedControl`: o marcado é o único preenchido.
	theme.set_type_variation("Segment", "Button")
	theme.set_font_size("font_size", "Segment", SIZE_DISPLAY_M - 2)
	theme.set_color("font_color", "Segment", TEXT_DIM)
	theme.set_color("font_hover_color", "Segment", TEXT)
	theme.set_color("font_pressed_color", "Segment", TEXT)
	for state in ["normal", "hover", "pressed", "focus"]:
		theme.set_stylebox(state, "Segment", _segment(Color(0, 0, 0, 0)))
	theme.set_type_variation("SegmentSelected", "Button")
	theme.set_font_size("font_size", "SegmentSelected", SIZE_DISPLAY_M - 2)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, "SegmentSelected", ACCENT_INK)
	for state in ["normal", "hover", "pressed", "focus"]:
		theme.set_stylebox(state, "SegmentSelected", _segment(ACCENT))


static func _segment(fill: Color) -> StyleBoxFlat:
	var style := box(fill, RADIUS - 3)
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style


static func _outlined(theme: Theme, name: String, tint: Color, soft: Color) -> void:
	theme.set_type_variation(name, "Button")
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(state, name, tint)
	theme.set_stylebox("normal", name, box(Color(0, 0, 0, 0), RADIUS, tint, 2))
	theme.set_stylebox("hover", name, box(soft, RADIUS, tint, 2))
	theme.set_stylebox("pressed", name, box(soft, RADIUS, tint, 3))
```

`_style_labels`, `_style_inputs`, `_style_panels`:

```gdscript
static func _style_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT)
	_label(theme, "Display", display(900), SIZE_DISPLAY_XL, TEXT)
	_label(theme, "Title", display(900), SIZE_DISPLAY_L, TEXT)
	_label(theme, "Greeting", display(900), SIZE_DISPLAY_L - 2, TEXT)
	_label(theme, "SectionHeader", display(900), SIZE_DISPLAY_M, TEXT)
	_label(theme, "Subtitle", font(400), SIZE_BODY, TEXT_DIM)
	_label(theme, "Caption", font(700), SIZE_CAPTION, TEXT_DIM)
	_label(theme, "PairingCode", mono(600), SIZE_MONO_L, ACCENT)
	_label(theme, "Mono", mono(600), SIZE_MONO_M, TEXT)


static func _label(theme: Theme, name: String, face: Font, font_size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, face)
	theme.set_font_size("font_size", name, font_size)
	theme.set_color("font_color", name, color)


static func _style_inputs(theme: Theme) -> void:
	theme.set_font("font", "LineEdit", font(700))
	theme.set_font_size("font_size", "LineEdit", SIZE_DISPLAY_M)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.7))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_stylebox("normal", "LineEdit", box(SURFACE, RADIUS, LINE, 1))
	theme.set_stylebox("focus", "LineEdit", box(SURFACE, RADIUS, ACCENT, 2))

	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_font_size("font_size", "ItemList", SIZE_BODY)
	theme.set_stylebox("panel", "ItemList", box(SURFACE, RADIUS, LINE_SOFT, 1))
	theme.set_stylebox("selected", "ItemList", box(ACCENT_SOFT, RADIUS))
	theme.set_stylebox("selected_focus", "ItemList", box(ACCENT_SOFT, RADIUS))
	theme.set_stylebox("hovered", "ItemList", box(Color(TEXT, 0.05), RADIUS))
	theme.set_constant("v_separation", "ItemList", 6)


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", box(SURFACE, RADIUS_LARGE))
	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", box(SURFACE, RADIUS_LARGE))
	theme.set_type_variation("QuietCard", "PanelContainer")
	theme.set_stylebox("panel", "QuietCard", dashed(Color(0, 0, 0, 0), LINE_SOFT, RADIUS_LARGE))
```

O comentário de cabeçalho do arquivo (a direção "tabuleiro de madeira, latão") é
reescrito para a direção Boteco, mantendo a explicação de peso × cor dos botões.

- [ ] **Step 3: Rodar** — import, `ui_kit_probe`. Esperado: OK.

- [ ] **Step 4: Protegidos continuam idênticos**

Renderizar as três folhas e comparar com a referência (comandos do Task 2,
Step 5). Esperado: `iguais` nas três.

- [ ] **Step 5: Suítes completas** (lista da seção Verificação da etapa). Esperado: verdes.

- [ ] **Step 6: Commit**

```bash
git add ui/app_theme.gd tests/ui_kit_probe.gd
git commit -m "feat(tema): paleta e variações do Boteco"
```

### Task 6: `Coaster`

**Files:**
- Create: `ui/coaster.gd`
- Modify: `tests/ui_kit_probe.gd`

**Interfaces:**
- Produces: `class_name Coaster extends Control` com `player_name: String`, `fill: Color` (padrão `COASTER`), `ring: Color` (padrão `GOLD`), `turn: bool`; `static func initial_of(name: String) -> String`; `static func ink_for(background: Color) -> Color`.

- [ ] **Step 1: Teste que falha**

```gdscript
func _probe_coaster() -> void:
	print("bolacha")
	_equals(Coaster.initial_of("Casqueta"), "C", "inicial do nome")
	_equals(Coaster.initial_of("k'rec@"), "K", "maiúscula, mesmo com símbolo no nome")
	_equals(Coaster.initial_of("  bia"), "B", "espaço antes não conta")
	_equals(Coaster.initial_of("érica"), "É", "acento vira maiúsculo")
	_equals(Coaster.initial_of("@@"), "?", "sem letra, interrogação")
	_equals(Coaster.initial_of("7 Belo"), "7", "número vale")
	_equals(Coaster.ink_for(AppTheme.COASTER), AppTheme.TEXT, "tinta clara sobre a bolacha escura")
	_equals(Coaster.ink_for(AppTheme.PAPER), AppTheme.PAPER_INK, "tinta escura sobre papel")
	_equals(Coaster.ink_for(AppTheme.ACCENT), AppTheme.PAPER_INK, "e sobre o amarelo")
	var coaster := Coaster.new()
	_equals(coaster.fill, AppTheme.COASTER, "bolacha escura por padrão")
	_equals(coaster.ring, AppTheme.GOLD, "com anel de chopp")
	_check(coaster.custom_minimum_size.x >= 40.0, "e no mínimo 40 de largura")
	_equals(coaster.mouse_filter, Control.MOUSE_FILTER_IGNORE, "não rouba o toque de quem a contém")
	coaster.free()
```

Run → FAIL.

- [ ] **Step 2: Implementar `ui/coaster.gd`**

```gdscript
class_name Coaster
extends Control

## A bolacha de chopp: o avatar de um jogador no tema Boteco.
##
## Um círculo escuro com a inicial, um anel dourado — ou na cor do assento, dentro
## da partida — e um segundo anel amarelo, por fora, quando é a vez dele. É o mesmo
## objeto na sala de espera, na coluna de jogadores e em volta da mesa: quem
## aprendeu a achar a própria bolacha numa tela acha nas outras.

const RING_RATIO := 0.08
const TURN_GAP_RATIO := 0.06

@export var player_name := "":
	set(value):
		player_name = value
		queue_redraw()
@export var fill := AppTheme.COASTER:
	set(value):
		fill = value
		queue_redraw()
@export var ring := AppTheme.GOLD:
	set(value):
		ring = value
		queue_redraw()
@export var turn := false:
	set(value):
		turn = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var diameter := minf(size.x, size.y)
	var center := size * 0.5
	var radius := diameter * 0.5
	var ring_width := maxf(2.0, diameter * RING_RATIO)
	if turn:
		draw_arc(center, radius - ring_width * 0.5, 0.0, TAU, 48, AppTheme.ACCENT, ring_width, true)
		radius -= ring_width + diameter * TURN_GAP_RATIO
	draw_circle(center, radius, fill)
	draw_arc(center, radius - ring_width * 0.5, 0.0, TAU, 48, ring, ring_width, true)
	var face := AppTheme.display(900)
	var font_size := maxi(8, int(radius * 1.05))
	var baseline := center.y + (face.get_ascent(font_size) - face.get_descent(font_size)) * 0.5
	draw_string(
		face, Vector2(center.x - radius, baseline), initial_of(player_name),
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, ink_for(fill)
	)


## A primeira letra ou número do nome, em maiúscula. Apelido é escolhido por gente
## ("k'rec@"), e a bolacha não pode mostrar um apóstrofo.
static func initial_of(name: String) -> String:
	for character in name:
		if character.is_valid_int() or character.to_upper() != character.to_lower():
			return character.to_upper()
	return "?"


## Tinta legível sobre um fundo: escura sobre claro, giz sobre escuro.
static func ink_for(background: Color) -> Color:
	return AppTheme.PAPER_INK if background.srgb_to_linear().get_luminance() > 0.5 else AppTheme.TEXT
```

Nota: `ACCENT` tem luminância relativa 0,567, e o limite 0,5 põe tinta escura
sobre ele; `COASTER`, 0,009.

- [ ] **Step 3: Rodar** — Esperado: OK.
- [ ] **Step 4: Commit** — `git add ui/coaster.gd tests/ui_kit_probe.gd` · `feat(tema): bolacha de jogador`

### Task 7: `PaperCard`

**Files:**
- Create: `ui/paper_card.gd`
- Modify: `tests/ui_kit_probe.gd`

**Interfaces:**
- Produces: `class_name PaperCard extends PanelContainer` com `tilt_degrees: float`; `static func paper_box() -> StyleBoxFlat`; `static func paper_theme() -> Theme` (tinta `PAPER_INK` para `Label` e para toda variação de rótulo do `AppTheme`).

- [ ] **Step 1: Teste que falha**

```gdscript
func _probe_paper() -> void:
	print("papel")
	var host := Control.new()
	host.theme = AppTheme.shared()
	root.add_child(host)
	var paper := PaperCard.new()
	host.add_child(paper)
	var plain := Label.new()
	var caption := Label.new()
	caption.theme_type_variation = &"Caption"
	paper.add_child(plain)
	paper.add_child(caption)
	var box := paper.get_theme_stylebox("panel") as StyleBoxFlat
	_check(box != null and box.bg_color == AppTheme.PAPER, "fundo de papel")
	_equals(plain.get_theme_color("font_color"), AppTheme.PAPER_INK, "texto sobre papel em tinta escura")
	_check(caption.get_theme_color("font_color") != AppTheme.TEXT_DIM, "e a legenda não herda o cinza da lousa")
	paper.size = Vector2(200, 100)
	paper.tilt_degrees = -1.2
	_check(paper.pivot_offset.is_equal_approx(Vector2(100, 50)), "gira em torno do próprio centro")
	_check(is_equal_approx(paper.rotation, deg_to_rad(-1.2)), "no ângulo pedido")
	host.free()
```

Run → FAIL.

- [ ] **Step 2: Implementar `ui/paper_card.gd`**

```gdscript
class_name PaperCard
extends PanelContainer

## Papel sobre a mesa: a comanda com o código da sala, a escritura de Metrópole.
##
## Três objetos do app são papel, e só eles. O que eles dividem não é só o fundo
## claro: é a tinta. Tudo o que o tema pinta de giz sobre a lousa — rótulo,
## legenda, título — precisa virar tinta escura aqui dentro, e isso vem de um tema
## próprio, que desce para os filhos antes do tema do app.

@export var tilt_degrees := 0.0:
	set(value):
		tilt_degrees = value
		_apply_tilt()

static var _paper_theme: Theme = null

## As variações de rótulo do `AppTheme`. A busca de cor de tema anda **por tipo**
## antes de andar por dono: uma legenda (`Caption`) dentro do papel acharia a cor
## `Caption` do tema do app antes da `Label` deste, e sairia cinza sobre creme.
const LABEL_TYPES := ["Label", "Display", "Title", "Greeting", "SectionHeader", "Subtitle", "Caption", "PairingCode", "Mono"]


func _init() -> void:
	add_theme_stylebox_override("panel", paper_box())
	theme = paper_theme()
	resized.connect(_apply_tilt)


func _apply_tilt() -> void:
	pivot_offset = size * 0.5
	rotation = deg_to_rad(tilt_degrees)


static func paper_box() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.PAPER
	style.set_corner_radius_all(AppTheme.RADIUS_PAPER)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


static func paper_theme() -> Theme:
	if _paper_theme != null:
		return _paper_theme
	_paper_theme = Theme.new()
	for type in LABEL_TYPES:
		var ink := AppTheme.PAPER_INK
		if type == "Caption" or type == "Subtitle":
			ink = Color(AppTheme.PAPER_INK, 0.72)
		_paper_theme.set_color("font_color", type, ink)
	return _paper_theme
```

- [ ] **Step 3: Rodar** — Esperado: OK.

> **Na execução:** a lista `LABEL_TYPES` se mostrou desnecessária. A busca de tema
> vai ao dono mais perto primeiro e sobe da variação para `Label` dentro dele;
> reduzir a lista à `Label` manteve a legenda escura. O código final define só
> `Label` e a tinta leve de `Caption`/`Subtitle`. O teste também passou a esperar um
> quadro antes de montar nós: em `_initialize` a árvore ainda não resolve tema.
- [ ] **Step 4: Commit** — `git add ui/paper_card.gd tests/ui_kit_probe.gd` · `feat(tema): cartão de papel`

### Task 8: `SegmentedControl`

**Files:**
- Create: `ui/segmented_control.gd`
- Modify: `tests/ui_kit_probe.gd`

**Interfaces:**
- Consumes: variações `Segment`/`SegmentSelected` (Task 5).
- Produces: `class_name SegmentedControl extends PanelContainer`; `signal selected(index: int)`; `var current: int`; `func setup(labels: PackedStringArray, index := 0) -> void`; `func set_current(index: int) -> void` (sem sinal); `func segment_count() -> int`.

- [ ] **Step 1: Teste que falha**

```gdscript
func _probe_segments() -> void:
	print("segmentos")
	var control := SegmentedControl.new()
	root.add_child(control)
	var heard: Array[int] = []
	control.selected.connect(func(index: int) -> void: heard.append(index))
	control.setup(PackedStringArray(["Online", "Neste aparelho", "Contra bot"]), 0)
	_equals(control.segment_count(), 3, "um segmento por opção")
	_equals(control.current, 0, "começa no pedido")
	_equals(control._buttons[0].text, "ONLINE", "rótulo em maiúsculas, voz de letreiro")
	_equals(control._buttons[0].theme_type_variation, &"SegmentSelected", "o marcado é o preenchido")
	_equals(control._buttons[1].theme_type_variation, &"Segment", "e os outros não")
	control._buttons[2].pressed.emit()
	_equals(control.current, 2, "tocar troca")
	_equals(heard, [2] as Array[int], "e avisa uma vez")
	control._buttons[2].pressed.emit()
	_equals(heard.size(), 1, "tocar no marcado não avisa de novo")
	control.set_current(1)
	_equals(control.current, 1, "trocar por código funciona")
	_equals(heard.size(), 1, "sem avisar — quem trocou já sabe")
	control.setup(PackedStringArray(["Mata-mata", "Brasileira"]), 1)
	_equals(control.segment_count(), 2, "refazer troca os segmentos")
	_equals(control._row.get_child_count(), 2, "sem deixar os velhos na fileira")
	control.free()
```

Run → FAIL.

- [ ] **Step 2: Implementar `ui/segmented_control.gd`**

```gdscript
class_name SegmentedControl
extends PanelContainer

## Abas curtas de uma escolha só: o modo de jogo na folha do jogo, o formato na
## página de regras.
##
## Uma fileira de botões dentro de um contorno, e só o marcado preenchido de
## amarelo. `selected` avisa apenas o toque de quem joga; `set_current` troca em
## silêncio, para a tela poder restaurar uma escolha sem se ouvir de volta.

signal selected(index: int)

var current := -1
var _row: HBoxContainer = null
var _buttons: Array[Button] = []


func _init() -> void:
	var frame := AppTheme.box(Color(0, 0, 0, 0), AppTheme.RADIUS, AppTheme.LINE, 1)
	frame.content_margin_left = 4
	frame.content_margin_right = 4
	frame.content_margin_top = 4
	frame.content_margin_bottom = 4
	add_theme_stylebox_override("panel", frame)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	add_child(_row)


func setup(labels: PackedStringArray, index := 0) -> void:
	for button in _buttons:
		_row.remove_child(button)
		button.queue_free()
	_buttons.clear()
	for i in labels.size():
		var button := Button.new()
		button.text = labels[i].to_upper()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.pressed.connect(_on_pressed.bind(i))
		_row.add_child(button)
		_buttons.append(button)
	current = -1
	set_current(index)


func set_current(index: int) -> void:
	current = -1 if _buttons.is_empty() else clampi(index, 0, _buttons.size() - 1)
	for i in _buttons.size():
		_buttons[i].theme_type_variation = &"SegmentSelected" if i == current else &"Segment"


func segment_count() -> int:
	return _buttons.size()


func _on_pressed(index: int) -> void:
	if index == current:
		return
	set_current(index)
	selected.emit(index)
```

- [ ] **Step 3: Rodar** — Esperado: OK.
- [ ] **Step 4: Commit** — `git add ui/segmented_control.gd tests/ui_kit_probe.gd` · `feat(tema): controle segmentado`

### Task 9: Fechamento da etapa 1

**Files:**
- Modify: `.github/workflows/ci.yml` (roda `ui_kit_probe`)
- Modify: `docs/superpowers/specs/2026-09-16-redesenho-boteco-design.md` (acertos abaixo)

- [ ] **Step 1: CI** — no passo de testes do job `jogo`, depois do `test_runner`:

```yaml
      - name: Kit de interface
        run: godot --headless --path . --script res://tests/ui_kit_probe.gd
```

- [ ] **Step 2: Acertos na spec**
  - §2: `ui/monopoly_card.gd` é o **painel** da carta de Sorte/Cofre (interface), não o baralho 3D — sai da tabela de intocáveis e entra no redesenho da etapa 4.
  - §2: o fundo da sala em volta da mesa 3D segue o tema; tabuleiro, casas, hotéis, peões e destaque ficam com cor fixa.
  - §3 Tipografia: a assinatura é `AppTheme.font(weight, role)`, com `display()` e `mono()` de atalho, e `legacy_font()` para o protegido.

- [ ] **Step 3: Verificação completa**

```bash
$GODOT --headless --path . --import   # sem SCRIPT ERROR
for t in test_runner monopoly_probe bomber_probe bomber_room_probe bomber_snapshot_probe bomber_predict_probe pool_probe ui_kit_probe; do $GODOT --headless --path . --script res://tests/$t.gd; done
for t in scene_probe pairing_probe ludo_probe uno_probe uno_scene_probe pool_scene_probe bomber_match_offline_probe; do $GODOT --headless --path . res://tests/$t.tscn; done
npm --prefix relay test
```
e, com o relay local, os sete smokes de rede. Esperado: tudo verde.

- [ ] **Step 4: Protegidos** — as três comparações de imagem: `iguais`.

- [ ] **Step 5: Folha de prints** — `$GODOT --path . --resolution 720x1280 res://tests/screen_sheet.tscn`; olhar as telas: o app de hoje com paleta e fontes novas (a estrutura ainda é a antiga). Anotar o que estourar de tamanho para a etapa 2.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci.yml docs/superpowers/specs/2026-09-16-redesenho-boteco-design.md
git commit -m "chore: fecha a fundação do redesenho"
```

## Verificação da etapa (lista completa)

- `--import` sem erro de script.
- `--script`: `test_runner`, `monopoly_probe`, `bomber_probe`, `bomber_room_probe`, `bomber_snapshot_probe`, `bomber_predict_probe`, `pool_probe`, `ui_kit_probe`.
- `.tscn`: `scene_probe`, `pairing_probe`, `ludo_probe`, `uno_probe`, `uno_scene_probe`, `pool_scene_probe`, `bomber_match_offline_probe`.
- Relay: `npm --prefix relay test`; smokes de rede com `CHESS_RELAY_URL`.
- Imagem: `uno_cards.png`, `pieces.png`, `20h_metropole_tampo.png` (região 520,180,380,390) iguais à referência.

---

## Etapa 2 — Navegação e menus

Detalhada ao iniciar a etapa, depois de ler `main_menu`, `game_menu`, `join`,
`join_panel`, `pairing`, `settings`, `nav_drawer`, `app_bar`, `game_choice`,
`welcome_panel`, `waiting_panel`, `tests/pairing_probe.gd` e `tests/scene_probe.gd`.

### Decisões de arquitetura

- **As abas são três cenas**, e não uma cena com páginas: `main_menu.tscn` (Jogos),
  `join.tscn` (Online) e `settings.tscn` (Você), cada uma com o componente
  `AppTabs` embaixo. Mantém o contrato do `Nav` (um `go_back()` por cena, varrido
  por `scene_probe`) e os testes que abrem cada tela. Trocar de aba é trocar de
  cena, com o mesmo fade de 0,16 s de hoje.
- **A folha do jogo é um componente** (`ui/game_sheet.gd`), aberto por cima da tela
  que o chama — o cardápio em Jogos, a fileira de jogos em Online. A cena
  `game_menu.tscn` sai. A folha não navega: emite `confirmed(mode)` e a tela chama
  `GameSheet.launch(tree, mode)`, que é o `_confirm_setup` e o `_open_pairing` de hoje.
- **Voltar de uma partida ou da sala** vai para a tela inicial com a folha daquele
  jogo reaberta: `Game.pending_sheet` guarda o jogo, e o `_ready` da tela inicial
  consome. Todo `MENU_SCENE` que apontava para `game_menu.tscn` passa a apontar
  para `main_menu.tscn`.
- **A gaveta sai.** `NavDrawer` é apagado quando nenhuma tela o usar mais.
- **"Como jogar"** não aparece na folha nesta etapa: link que não leva a lugar
  nenhum é pior que link nenhum. Entra na etapa 5.

### Task 10: Barra, abas e dica

**Files:** Modify `ui/app_theme.gd` (variação `Hint`), `ui/app_bar.gd`; Create `ui/app_tabs.gd`; Modify `tests/ui_kit_probe.gd`.

**Interfaces:**
- `Hint` (rótulo): corpo 400, `SIZE_BODY_S`, `TEXT_DIM` — as frases de ajuda que hoje usam `Caption` e ficaram em 12.
- `AppBar`: `leading` aceita `-1` (sem botão, para as abas); `func greet(player_name: String) -> void` monta o cabeçalho da tela inicial (logo, "Olá," pequeno, nome em letreiro, `Coaster` à direita que emite `action_pressed`).
- `class_name AppTabs extends Control`; `const GAMES := &"games"`, `ONLINE := &"online"`, `YOU := &"you"`; `signal picked(route: StringName)`; `var current: StringName`; `var disabled: Array[StringName]`; `func route_at(point: Vector2) -> StringName`; `func pick(route: StringName) -> void` (emite só se diferente de `current` e não desabilitada).

**Teste (ui_kit_probe):**

```gdscript
func _probe_tabs() -> void:
	print("abas")
	var tabs := AppTabs.new()
	tabs.size = Vector2(432, 64)
	tabs.current = AppTabs.GAMES
	root.add_child(tabs)
	var heard: Array[StringName] = []
	tabs.picked.connect(func(route: StringName) -> void: heard.append(route))
	_equals(tabs.route_at(Vector2(30, 30)), AppTabs.GAMES, "a esquerda é Jogos")
	_equals(tabs.route_at(Vector2(216, 30)), AppTabs.ONLINE, "o meio é Online")
	_equals(tabs.route_at(Vector2(400, 30)), AppTabs.YOU, "a direita é Você")
	tabs.pick(AppTabs.GAMES)
	_equals(heard.size(), 0, "tocar na aba em que se está não navega")
	tabs.disabled = [AppTabs.ONLINE] as Array[StringName]
	tabs.pick(AppTabs.ONLINE)
	_equals(heard.size(), 0, "nem na desabilitada")
	tabs.pick(AppTabs.YOU)
	_equals(heard, [AppTabs.YOU] as Array[StringName], "a outra avisa")
	tabs.free()
	var bar := AppBar.new()
	root.add_child(bar)
	bar.greet("Casqueta")
	_check(bar.find_children("*", "Coaster", true, false).size() == 1, "o cabeçalho de casa tem a bolacha do jogador")
	bar.leading = -1
	_check(not bar._leading_button.visible, "e as abas não têm botão de voltar")
	bar.free()
```

### Task 11: Folha do jogo

**Files:** Create `ui/game_sheet.gd`; Modify `autoload/game_state.gd` (`pending_sheet`); Modify `tests/pairing_probe.gd` (`_probe_setup_panel` vira `_probe_game_sheet`).

**Interfaces:**
- `class_name GameSheet extends Control`; `signal confirmed(mode: int)`; `signal closed`.
- `func open(id: StringName, preferred_mode := -1) -> void` (grava `Game.game_id`); `func close() -> void`; `func select_mode(mode: int) -> void`; `var mode: int`; `func is_open() -> bool`.
- `static func modes_for(id: StringName) -> Array[int]` — na ordem Online, Neste aparelho, Contra bot, só os que `Game.mode_available` aceita.
- `static func launch(tree: SceneTree, mode: int) -> void`.
- Nós internos para o teste: `_segments: SegmentedControl`, `_clock: GridContainer`, `_players: HBoxContainer`, `_formats: GridContainer`, `_levels: HBoxContainer`, `_sides: HBoxContainer`, `_visibility: HBoxContainer`, `_start: Button`, e `_section(name) -> Control` (legenda mais grupo).
- `Game.pending_sheet: StringName` — vazio por padrão.

**Teste (pairing_probe, substitui `_probe_setup_panel`):** abrir xadrez dá os segmentos na ordem dos modos disponíveis; um botão por ritmo; escolher o ritmo 1 grava `time_control` e marca `ChipSelected`; damas esconde a seção de ritmo; em "Contra bot" aparecem nível e cor e some "quem pode entrar"; escolher pretas deixa brancas com o bot; o botão diz "CRIAR SALA" online e "COMEÇAR" fora; `close()` fecha; sem relay o segmento Online não existe.

### Task 12: Início

**Files:** Create `ui/catalog_row.gd`; Modify `ui/game_choice.gd` (cartão de favorito em bolacha), `ui/resume_card.gd` (placa amarela), `scenes/main_menu.gd` e `.tscn`; Delete `scenes/game_menu.gd` e `.tscn`; Modify `MENU_SCENE` em `scenes/{match,battleship_match,bomber_match,ludo_match,monopoly_match,pool_match,uno_match,pairing,bomber_lobby}.gd`; Modify `tests/pairing_probe.gd` (`_probe_game_picker`), `tests/screen_sheet.gd` (prints da folha).

**Interfaces:**
- `class_name CatalogRow extends Control`; `signal chosen`; `signal favorite_toggled`; `var game_id: StringName`; `var favorite: bool`; `var unavailable: bool`; `func _star_zone() -> Rect2`.
- Árvore de `main_menu.tscn`: `Background`, `Safe/VBox/{AppBar, Scroll/Pad/Content/{Favorites, CatalogHeader/{CatalogTitle, Categories}, GameList}, Tabs}`. `%GameList` guarda só `CatalogRow`; `%Favorites` guarda os `GameChoice` e some sem favorito.
- `main_menu.gd`: `_sheet() -> GameSheet`; `go_back()` fecha a folha, depois as boas-vindas, depois sai.

**Teste (pairing_probe, reescreve `_probe_game_picker`):** uma linha por jogo visível; a primeira é Xadrez; a estrela da linha grava favorito sem navegar e sem refazer a lista; o favorito aparece em `%Favorites` ao remontar; filtro Favoritos, categoria e Todos; tocar na linha abre a folha com o jogo; `go_back()` com a folha aberta fecha a folha; `Game.pending_sheet` reabre a folha ao montar e é consumido.

### Task 13: Mesa de espera

**Files:** Create `ui/seat_table.gd`; Modify `tests/ui_kit_probe.gd`.

**Interfaces:** `class_name SeatTable extends Control`; `var capacity: int`; `var local_seat: int`; `var present: PackedInt32Array`; `func refresh() -> void`; `static func seat_angle(seat: int, capacity: int, local_seat: int) -> float` (radianos, local embaixo, sentido horário na tela); `func label_of(seat: int) -> String` ("Você", "Chegou", "Esperando").

**Teste:** o ângulo do local é `PI/2`; com 4 cadeiras e local 2, a 3 fica em `PI`, a 0 em `3PI/2` e a 1 em `0`; os rótulos; uma bolacha por cadeira; `refresh()` com outra capacidade refaz as bolachas.

### Task 14: Online

**Files:** Create `ui/code_input.gd`; Modify `ui/room_card.gd`, `ui/join_panel.gd` e `.tscn`, `ui/waiting_panel.gd`, `scenes/join.gd` e `.tscn`; Modify `tests/ui_kit_probe.gd`, `tests/pairing_probe.gd` (`_probe_guest`), `tests/screen_sheet.gd` (`05_entrar`).

**Interfaces:**
- `class_name CodeInput extends Control`; `signal completed(code: String)`; `const LENGTH := 6`; `var code: String` (maiúsculo, só letras e números); `func set_code(raw: String) -> void`; `func clear() -> void`. Por dentro, um `LineEdit` transparente cobrindo as casas — é o que abre o teclado do Android e aceita colar.
- `JoinPanel`: `%CodeInput`, `%JoinButton`, `%ScanButton`, `%NfcHint`, `%CreateRow` (bolachas dos jogos que têm Online), `%GameFilter`, `%RefreshButton`, `%RoomRows`, `%Status`; `signal create_requested(game_id: StringName)`.
- `WaitingPanel.show_room(game_id, code, present: PackedInt32Array, capacity, local_seat)`.
- `join.gd` abre a `GameSheet` em Online no `create_requested`.

**Teste (ui_kit_probe):** colar "ab-12cd9" dá "AB12CD" e avisa `completed` uma vez; menos de 6 não avisa; `clear()` esvazia. **(pairing_probe):** código curto no "Entrar" vai para o toast; completar as 6 casas procura a sala sozinho; sala da lista leva o jogo dela; tocar numa bolacha de "Criar sala" abre a folha em Online.

### Task 15: Sala de espera do anfitrião

**Files:** Modify `scenes/pairing.gd` e `.tscn`; Modify `tests/pairing_probe.gd` (`_probe_host`), `tests/screen_sheet.gd` (`04_criar`).

**Árvore:** `Safe/Shell/{AppBar, Scroll/Pad/VBox/{HostPanel/{CodeCard(PaperCard)/CodeBox/{CodeCaption, CodeLabel, CodeActions/{CopyButton, QrButton}}, QrCard/QrCode}, SeatsHeader/{SeatsTitle, SeatsCount}, Seats(SeatTable), HostHint, StatusLabel, BotsButton}}`. O QR começa escondido.

**Teste:** código com 6 caracteres e no link; o QR começa escondido e "Mostrar QR" mostra; payload do QR válido; "Copiar" põe o código na área de transferência; a mesa tem a capacidade do jogo e o anfitrião sentado.

### Task 16: Você e boas-vindas

**Files:** Modify `scenes/settings.gd` e `.tscn`, `ui/welcome_panel.gd`.

**Árvore de `settings.tscn`:** `Safe/VBox/{AppBar, Scroll/Pad/Content/{Profile/{Avatar(Coaster), NameColumn/{NameSection, NameEdit}}, Preview, FeedbackSection, Switches, SaveButton, AboutSection, StatusLabel}, Tabs}`.

**Teste:** `scene_probe._test_welcome` continua verde; a bolacha do perfil acompanha o nome digitado.

### Task 17: Fechamento da etapa 2

Apagar `ui/nav_drawer.gd` se órfão; `NavDrawer` e `game_menu` sem nenhuma referência fora do histórico; verificação completa (lista da etapa 1); folha de prints inteira e comparação com o canvas aprovado; commit.
