class_name AppTabs
extends Control

## As abas da base da tela: Jogos · Online · Loja · Você.
##
## Substituem a gaveta e a engrenagem do topo. Os dois ficavam no canto de cima —
## o lugar mais longe do polegar num celular — e "Multiplayer" só existia dentro da
## gaveta, que é onde uma função se esconde de quem não sabe que ela existe. Na
## base, os lugares do app estão sempre à vista e ao alcance.
##
## Uma pílula solta do chão, com a aba aberta preenchida de limão. Desenhada
## inteira aqui, com as áreas de toque calculadas da largura, em vez de três
## botões: a pílula é um desenho só, e o toque vale na faixa toda, margem incluída.
##
## Quem navega é a tela. A barra só diz qual aba foi tocada — é o que permite a
## mesma barra servir às cenas todas sem saber para onde cada uma leva. O som do
## toque também é da tela: o componente não conhece autoload, e é isso que deixa
## testá-lo sem eles.

signal picked(route: StringName)

const GAMES := &"games"
const ONLINE := &"online"
const SHOP := &"shop"
const YOU := &"you"
const ROUTES: Array[StringName] = [GAMES, ONLINE, SHOP, YOU]
const LABELS := {GAMES: "Jogos", ONLINE: "Online", SHOP: "Loja", YOU: "Você"}
const ICONS := {GAMES: LineIcon.DICE, ONLINE: LineIcon.GLOBE, SHOP: LineIcon.BAG, YOU: LineIcon.PERSON}

const HEIGHT := 80.0
## A pílula dentro da faixa: recuada dos lados e do chão.
const PILL_HEIGHT := 60.0
const PILL_SIDE := 20.0
const PILL_BOTTOM := 12.0
## Folga entre a pílula e o preenchimento da aba aberta.
const INSET := 6.0
const LABEL_SIZE := 15
## O ícone à esquerda do rótulo (`LineIcon`): lado do quadrado e folga até o texto.
const ICON := 16.0
const ICON_GAP := 5.0
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


var _press := Tap.Press.new()


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
	# deixa a segunda mandando numa tela que a primeira já descartou. Ao soltar,
	# para o gesto do Android de subir pela base da tela não trocar de aba.
	if not _press.feed(event):
		return
	accept_event()
	pick(route_at(_press.origin))


func _draw() -> void:
	var pill := Rect2(
		PILL_SIDE, size.y - PILL_BOTTOM - PILL_HEIGHT, size.x - PILL_SIDE * 2.0, PILL_HEIGHT
	)
	draw_style_box(AppTheme.box(AppTheme.SURFACE_HIGH, int(PILL_HEIGHT * 0.5)), pill)
	var width := pill.size.x / ROUTES.size()
	var face := AppTheme.display(600)
	for index in ROUTES.size():
		var route := ROUTES[index]
		var slot := Rect2(pill.position.x + width * index, pill.position.y, width, pill.size.y)
		var ink := AppTheme.TEXT_DIM
		if route == current:
			ink = AppTheme.ACCENT_INK
			var chosen := slot.grow(-INSET)
			draw_style_box(AppTheme.box(AppTheme.ACCENT, int(chosen.size.y * 0.5)), chosen)
		if route in disabled:
			ink = Color(ink, DISABLED_ALPHA)
		var label := String(LABELS[route])
		var text_width := face.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		var left := slot.get_center().x - (ICON + ICON_GAP + text_width) * 0.5
		LineIcon.draw(self, ICONS[route], Vector2(left + ICON * 0.5, slot.get_center().y), ICON, ink)
		draw_string(
			face, Vector2(left + ICON + ICON_GAP, slot.get_center().y + LABEL_SIZE * 0.36),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, ink
		)
