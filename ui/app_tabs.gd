class_name AppTabs
extends Control

## As abas da base da tela: Jogos · Online · Você.
##
## Substituem a gaveta e a engrenagem do topo. Os dois ficavam no canto de cima —
## o lugar mais longe do polegar num celular — e "Multiplayer" só existia dentro da
## gaveta, que é onde uma função se esconde de quem não sabe que ela existe. Na
## base, os três lugares do app estão sempre à vista e ao alcance.
##
## Desenhada inteira aqui, com as três áreas de toque calculadas da largura, em vez
## de três botões: o que cada aba mostra é um ícone de traço e uma palavra, e um
## `Button` com filho desenhado por cima seria dois nós brigando pelo mesmo toque.
##
## Quem navega é a tela. A barra só diz qual aba foi tocada — é o que permite a
## mesma barra servir às três cenas sem saber para onde cada uma leva. O som do
## toque também é da tela: o componente não conhece autoload, e é isso que deixa
## testá-lo sem eles.

signal picked(route: StringName)

const GAMES := &"games"
const ONLINE := &"online"
const YOU := &"you"
const ROUTES: Array[StringName] = [GAMES, ONLINE, YOU]
const LABELS := {GAMES: "Jogos", ONLINE: "Online", YOU: "Você"}

const HEIGHT := 64.0
const ICON := 22.0
const LABEL_SIZE := 14
## Opacidade de uma aba que não pode ser aberta neste build — Online sem servidor.
## Apagada e não escondida: uma aba que some parece uma aba que foi removida.
const DISABLED_ALPHA := 0.35

var current: StringName = GAMES:
	set(value):
		current = value
		queue_redraw()

var disabled: Array[StringName] = []:
	set(value):
		disabled = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP


func route_at(point: Vector2) -> StringName:
	if size.x <= 0.0:
		return &""
	var index := clampi(int(point.x / (size.x / ROUTES.size())), 0, ROUTES.size() - 1)
	return ROUTES[index]


## A aba em que se está não navega — tocar nela de novo recarregaria a própria tela
## para chegar exatamente onde se estava —, e a desabilitada não responde.
func pick(route: StringName) -> void:
	if route == current or route in disabled or not ROUTES.has(route):
		return
	picked.emit(route)


func _gui_input(event: InputEvent) -> void:
	# Por [Tap]: um clique chega duas vezes, e trocar de cena duas vezes seguidas
	# deixa a segunda mandando numa tela que a primeira já descartou.
	if not Tap.began(event):
		return
	accept_event()
	pick(route_at(Tap.at(event)))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), AppTheme.COASTER)
	# O fio de cima é tracejado, como a linha de giz do resto do tema.
	draw_dashed_line(Vector2(0, 0.75), Vector2(size.x, 0.75), AppTheme.LINE_SOFT, 1.5, 6.0)
	var width := size.x / ROUTES.size()
	var face := AppTheme.display(900)
	for index in ROUTES.size():
		var route := ROUTES[index]
		var ink := AppTheme.ACCENT if route == current else AppTheme.TEXT_DIM
		if route in disabled:
			ink = Color(ink, DISABLED_ALPHA)
		var center_x := width * (index + 0.5)
		_draw_icon(route, Vector2(center_x, size.y * 0.38), ink)
		draw_string(
			face, Vector2(width * index, size.y * 0.84), String(LABELS[route]).to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, width, LABEL_SIZE, ink
		)


func _draw_icon(route: StringName, center: Vector2, ink: Color) -> void:
	var half := ICON * 0.5
	match route:
		GAMES:
			# Quatro ladrilhos: a coleção.
			var cell := ICON * 0.42
			for dx: float in [-1.0, 1.0]:
				for dy: float in [-1.0, 1.0]:
					var origin := center + Vector2(dx, dy) * (ICON * 0.25) - Vector2(cell, cell) * 0.5
					draw_rect(Rect2(origin, Vector2(cell, cell)), ink, false, 2.0)
		ONLINE:
			# Três arcos de sinal e o ponto de onde saem.
			var base := center + Vector2(0, half * 0.85)
			for step in 3:
				var radius := half * (0.45 + 0.4 * step)
				draw_arc(base, radius, -PI * 0.78, -PI * 0.22, 16, ink, 2.0, true)
			draw_circle(base, 2.0, ink)
		YOU:
			# Cabeça e ombros.
			draw_arc(center + Vector2(0, -half * 0.35), half * 0.42, 0.0, TAU, 20, ink, 2.0, true)
			draw_arc(center + Vector2(0, half * 0.95), half * 0.8, PI * 1.12, PI * 1.88, 16, ink, 2.0, true)
