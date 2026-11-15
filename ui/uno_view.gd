class_name UnoView
extends Control

## A mesa vista de cima: os jogadores em volta, o monte e o descarte no meio.
##
## ## Por que uma mesa, e não uma fileira de cartões
##
## A fileira era o desenho de retrato, e ela quebra em três lugares:
##
## - **seis jogadores numa faixa de 432 px** dão 72 px cada, e 72 px é um nome
##   cortado ao lado de um número;
## - **o tamanho da mão alheia vira leitura.** Um "7" escrito obriga a ler; sete
##   versos empilhados dizem "muita carta" antes de qualquer número ser lido;
## - **o sentido do jogo não tinha em volta de quê girar.** A seta apontava para
##   um lado da tela, e o inverte — a única carta cujo efeito não se vê — não
##   tinha como se ver. Com os assentos dispostos na ordem de jogo, a seta gira
##   em torno da mesa e aponta para uma pessoa.
##
## ## O local fica sempre embaixo
##
## E os outros são distribuídos a partir dele, na ordem em que jogam. **Não** na
## ordem de assento: em rede o `local_seat` de cada aparelho é diferente, e uma
## mesa desenhada por índice de assento mostraria a mesma partida girada de um
## jeito para cada jogador — a seta do sentido deixaria de significar a mesma
## coisa nas quatro telas.
##
## O lugar de baixo fica vazio de propósito: quem está ali é o dono do aparelho, e
## a mão dele é o leque inteiro logo abaixo desta vista.
##
## ## O leque de costas tem teto
##
## No máximo [constant MAX_BACKS] versos por jogador, e o número conta o resto.
## Dois motivos, e os dois são medidos: vinte versos sobrepostos viram uma mancha
## sem tamanho legível, e seis jogadores com vinte cartas seriam 120 cartas
## desenhadas por quadro — cada uma com polígonos e texto, num celular.
##
## O número **não** sai por causa do leque. O leque é aproximação; "uma carta na
## mão" precisa ser inequívoco, e é o aviso mais importante da mesa.

## O monte foi tocado. Só sai quando comprar é lance legal: a vista não decide o
## que é legal, mas também não oferece um toque que não leva a nada.
signal deck_tapped

## Versos desenhados por jogador, no máximo.
##
## Seis e não sete: com o leque em pé nos assentos laterais, cada verso a mais é
## altura, e altura é o que falta numa tela deitada. Acima disto quem conta é o
## número — que é o que ele existe para fazer.
const MAX_BACKS := 5
## Sobreposição entre os versos, em larguras de carta.
const BACK_STEP := 0.32

## Centro da mesa, em fração do tamanho. Abaixo do meio porque o lugar de baixo
## não é usado — puxar tudo para cima deixaria uma faixa morta sob o descarte.
const TABLE_AT := Vector2(0.5, 0.50)
## Meia-largura e meia-altura da **borda** onde os assentos ficam.
##
## Borda de retângulo e não de elipse, e a diferença decide se a mesa de seis
## funciona. Numa elipse os dois assentos de um mesmo lado ficam a um raio
## vertical de distância — com a altura que uma tela deitada tem, isso dava 90 px
## entre dois leques em pé de 120. Na borda do retângulo eles vão para os cantos,
## e a distância entre eles passa a ser a altura útil inteira.
const RADIUS := Vector2(0.42, 0.28)
## De pé, o centro desce: as etiquetas dos assentos de cima sobem acima do leque,
## e numa mesa de seis são três delas disputando a faixa de cima. Embaixo sobra —
## o lugar do local fica vazio.
const TABLE_AT_PORTRAIT := Vector2(0.5, 0.56)
## A mesma borda de pé, alta o bastante para separar na vertical a etiqueta do
## assento de cima das dos cantos, que na horizontal se cruzam.
const RADIUS_PORTRAIT := Vector2(0.36, 0.36)

## Quanto o realce sobra para fora da carta central.
const MAT_GROW := 0.09

## Uma cor por assento, e **nenhuma delas é cor de carta**.
##
## É a única regra que essa paleta tem de obedecer, e ela não é estética: o jogo
## inteiro fala em vermelho, amarelo, verde e azul o tempo todo — a cor ativa, a
## cor que um curinga declara, a cor que casa com o descarte. Um "jogador azul"
## no meio disso lê como "as cartas azuis", e a mesa passa a ter duas linguagens
## de cor dizendo coisas diferentes com as mesmas palavras.
##
## Então os seis assentos ficam nos hues que o baralho não usa: violeta,
## turquesa, laranja queimado, rosa, oliva e ardósia. Nenhum deles pode ser
## confundido com uma carta, e os seis se separam entre si num fundo escuro.
const SEAT_COLORS := [
	Color("9b6bd6"),  # violeta
	Color("38a89d"),  # turquesa
	Color("d9763c"),  # laranja queimado
	Color("d4699e"),  # rosa
	Color("8fa03f"),  # oliva
	Color("7d8ea8"),  # ardósia
]


static func color_of_seat(seat: int) -> Color:
	return SEAT_COLORS[seat % SEAT_COLORS.size()]

var state: MatchState = null:
	set(value):
		state = value
		queue_redraw()

## Nosso lugar na mesa. É ele que vai para baixo, e é a partir dele que os outros
## são espalhados.
var local_seat := 0:
	set(value):
		local_seat = value
		queue_redraw()

## Como cada assento se chama, na ordem dos assentos. Vazio cai em "Jogador N".
var names := PackedStringArray():
	set(value):
		names = value
		queue_redraw()

## Comprar é lance legal agora. Acende o monte e libera o toque.
var can_draw := false:
	set(value):
		if can_draw == value:
			return
		can_draw = value
		queue_redraw()

## O descarte mostra esta carta e esta cor em vez das de verdade, enquanto a carta
## nova ainda voa até ele. Negativo é o descarte de verdade.
##
## Sem isto a carta jogada aparecia duas vezes — já pousada no descarte e ainda a
## caminho dele —, e o voo deixava de ser o que conta o lance.
var held_top := -1
var _held_color := 0

## A pílula embaixo das duas cartas do meio: o que fazer agora ("Jogue um verde
## ou um 7") ou de quem é a vez. Limão quando a vez é de quem segura o aparelho.
var hint := "":
	set(value):
		hint = value
		queue_redraw()
var hint_lit := false:
	set(value):
		hint_lit = value
		queue_redraw()

## Uma volta do anel do sentido, em segundos. Devagar: é fundo, não alarme.
const RING_TURN := 14.0
## O feltro oval e o anel tracejado moram em dois filhos desenhados **por trás**
## da mesa. O anel gira pela `rotation` do nó, sem redesenhar a mesa a cada
## quadro.
var _felt: Control = null
var _ring: Control = null
var _turn := 0.0


## Quanto a seta do sentido está girada. O inverte a faz dar meia volta até
## assentar no sentido novo — é o único efeito dele que se vê, já que nenhuma mão
## muda.
var spin := 0.0:
	set(value):
		spin = value
		queue_redraw()
var _spin_tween: Tween


func spin_direction() -> void:
	if _spin_tween != null:
		_spin_tween.kill()
	_spin_tween = create_tween()
	_spin_tween.tween_property(self, "spin", 0.0, 0.6).from(PI) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hold_pile(card: int, color: int) -> void:
	held_top = card
	_held_color = color
	queue_redraw()


func release_pile() -> void:
	held_top = -1
	queue_redraw()

## Medidas calculadas no desenho e reusadas pelo toque. Guardadas em vez de
## recalculadas no `_gui_input` porque as duas contas precisam concordar: um monte
## que acende num lugar e aceita toque em outro é pior que um monte que não acende.
var _card_height := 0.0
var _deck_center := Vector2.ZERO
var _pile_center := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_felt = _backdrop(_draw_felt)
	_ring = _backdrop(_draw_ring)
	set_process(true)


func _backdrop(painter: Callable) -> Control:
	var layer := Control.new()
	layer.show_behind_parent = true
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Âncoras antes do `add_child`.
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	layer.draw.connect(painter)
	return layer


## O anel gira no sentido em que a vez anda: horário quando ela vai para a
## esquerda de quem está embaixo, anti-horário depois de um inverte.
func _process(delta: float) -> void:
	if state == null or _ring == null:
		return
	var way := 1.0 if UnoRules.direction_of(state) > 0 else -1.0
	_turn = fmod(_turn + delta * TAU / RING_TURN * way, TAU)
	_ring.pivot_offset = _table_center()
	_ring.rotation = _turn + spin * way


func _draw() -> void:
	_layout()
	if state == null:
		return
	_felt.queue_redraw()
	_ring.queue_redraw()
	_draw_seats()
	_draw_deck()
	_draw_pile()
	_draw_hint()


func _portrait() -> bool:
	return size.y > size.x


## Altura dos versos nos assentos. Um lugar só para a conta, porque o desenho e a
## etiqueta precisam concordar sobre o tamanho do leque.
func _back_height() -> float:
	return minf(size.y * 0.19, _card_height * 0.52)


func _layout() -> void:
	var center := _table_center()
	# As duas cartas do meio dividem a largura livre entre os assentos laterais.
	#
	# Menores do que caberiam, de propósito. O monte e o descarte são as duas
	# coisas da mesa que **não** competem por atenção — o descarte diz a cor e o
	# valor de uma carta só, e o monte é um alvo de toque. Grandes, eles empurram o
	# nome de cada assento para fora do vão em que ele cabe, e o rótulo acaba tendo
	# de escolher um lado conforme onde o assento está. Menores, o vão entre o
	# assento e o meio abre, e o nome pode ir sempre para o mesmo lugar.
	if _portrait():
		_card_height = minf(size.y * 0.22, (size.x * 0.20) / UnoCardArt.ASPECT)
	else:
		_card_height = minf(size.y * 0.30, (size.x * 0.12) / UnoCardArt.ASPECT)
	var gap := UnoCardArt.width_for(_card_height) * 0.72
	_deck_center = center - Vector2(gap, 0.0)
	_pile_center = center + Vector2(gap, 0.0)


# --- pontos para os voos ------------------------------------------------------
#
# Em coordenadas globais: quem lança a carta é a camada de cima, que atravessa a
# mesa e a mão, e só ela sabe onde está. `_layout()` antes de cada um pelo mesmo
# motivo de `seat_tag_spot`: a medida das cartas nasce no desenho.


func deck_point() -> Vector2:
	_layout()
	return get_global_transform() * _deck_center


func pile_point() -> Vector2:
	_layout()
	return get_global_transform() * _pile_center


## O meio do leque de um assento, girado como ele. A carta de um adversário sai
## dali deitada do jeito que ele a segura, e endireita no caminho.
func seat_spot(seat: int) -> Transform2D:
	_layout()
	var facing := _angle_of(seat) - PI * 0.5
	return Transform2D(facing, get_global_transform() * _seat_center(seat))


func card_height() -> float:
	_layout()
	return _card_height


func back_height() -> float:
	_layout()
	return _back_height()


# --- os assentos --------------------------------------------------------------


## Onde cada assento fica na tela, em ângulo.
##
## O local é o de baixo (meia volta em coordenadas de tela, onde o y cresce para
## baixo), e os outros seguem dele **na ordem de jogo**. O passo é sempre o mesmo,
## então uma mesa de seis é a de quatro com dois lugares a mais, e não outro
## desenho.
func _angle_of(seat: int) -> float:
	var count := UnoRules.seats_of(state)
	var steps := posmod(seat - local_seat, count)
	return PI * 0.5 + TAU * float(steps) / float(count)


func _table_center() -> Vector2:
	var at := TABLE_AT_PORTRAIT if _portrait() else TABLE_AT
	return Vector2(size.x * at.x, size.y * at.y)


## O ponto onde o raio do assento encontra a **borda do retângulo**.
##
## O fator é o menor dos dois que levam à borda: quem estourar primeiro manda. É
## isso que empurra os assentos de ângulo quase horizontal para os cantos em vez
## de deixá-los amontoados no meio da lateral.
func _seat_center(seat: int) -> Vector2:
	var angle := _angle_of(seat)
	var ray := Vector2(cos(angle), sin(angle))
	var radius := RADIUS_PORTRAIT if _portrait() else RADIUS
	var half := Vector2(size.x * radius.x, size.y * radius.y)
	var reach := INF
	if not is_zero_approx(ray.x):
		reach = minf(reach, half.x / absf(ray.x))
	if not is_zero_approx(ray.y):
		reach = minf(reach, half.y / absf(ray.y))
	return _table_center() + ray * reach


## Onde a etiqueta de um assento cabe: encostada no leque dele, do lado de fora da
## mesa, e sempre dentro da vista.
##
## A conta mora aqui, e não na cena, porque é a mesma geometria que põe o leque no
## lugar — quem sabe onde está a mão de um assento sabe onde o nome dele cabe. E
## `_layout()` de novo porque a medida das cartas nasce no primeiro desenho: a
## cena pode perguntar antes disso.
func seat_tag_spot(seat: int, tag: Vector2) -> Vector2:
	# Sem partida ainda não há assentos: a cena monta as etiquetas antes do primeiro
	# desenho, e perguntar a geometria de uma mesa vazia é perguntar por nada.
	if state == null:
		return Vector2.ZERO
	_layout()
	var away := (_seat_center(seat) - _table_center()).normalized()
	var spot := _tag_spot_along(seat, away, tag)
	# Para fora pelo raio, quando cabe. Quando não cabe — sempre de pé, e deitado
	# nos assentos do meio da lateral numa mesa de quatro —, o nome empurrado para
	# fora voltava preso na borda, em cima do leque. Aí ele sobe ou desce.
	if _portrait() or spot.x < 0.0 or spot.x > size.x - tag.x:
		var vertical := Vector2(0.0, -1.0 if away.y < -0.01 else 1.0)
		spot = _tag_spot_along(seat, vertical, tag)
	return Vector2(
		clampf(spot.x, 0.0, maxf(0.0, size.x - tag.x)),
		clampf(spot.y, 0.0, maxf(0.0, size.y - tag.y))
	)


## A etiqueta encostada no leque do assento, do lado `away`, sem prender na vista.
func _tag_spot_along(seat: int, away: Vector2, tag: Vector2) -> Vector2:
	var center := _seat_center(seat)
	var back_height := _back_height()

	# Quanto o leque ocupa **na direção em que a etiqueta vai**: um leque deitado
	# ocupa pouco para cima e muito para o lado, e é a mesma conta que decide onde
	# o nome cabe. Um empurrão de valor fixo acertava os assentos de cima e punha o
	# nome em cima das cartas nos das pontas.
	var shown := mini(UnoRules.hand_size(state, seat), MAX_BACKS)
	var step := UnoCardArt.width_for(back_height) * BACK_STEP
	var half := Vector2(UnoCardArt.width_for(back_height), back_height) * 0.5
	var pad := Vector2.ONE * back_height * 0.16
	var facing := _angle_of(seat) - PI * 0.5
	var mat := _extent(away, step * maxf(shown - 1, 0) * 0.5, half + pad, facing)
	var reach := absf(away.x) * tag.x * 0.5 + absf(away.y) * tag.y * 0.5
	return center + away * (mat + reach + 8.0) - tag * 0.5


func _draw_seats() -> void:
	var count := UnoRules.seats_of(state)
	var turn := UnoRules.turn_of(state)
	for seat in count:
		if seat == local_seat:
			continue
		_draw_seat(seat, _seat_center(seat), seat == turn)


## Um assento: o leque de costas, o nome e a contagem.
##
## ## O leque encara a mesa
##
## Cada jogador segura as cartas viradas para o centro, como numa mesa de
## verdade: o leque é perpendicular ao raio que vai do meio da mesa até ele. Quem
## está à esquerda tem um leque **em pé**, e é aí que está o ganho — um leque
## deitado de sete cartas gasta uns 180 px de largura de cada lado, e essa largura
## é justamente a que falta numa tela deitada de celular.
##
## O nome e o número **não** giram. Eles são texto, e texto de lado obriga a
## inclinar o aparelho para ler o que a mesa deveria dizer de relance.
func _draw_seat(seat: int, center: Vector2, _is_turn: bool) -> void:
	var held := UnoRules.hand_size(state, seat)
	var back_height := _back_height()
	var shown := mini(held, MAX_BACKS)
	var step := UnoCardArt.width_for(back_height) * BACK_STEP

	# O leque abre ao longo do eixo x **do assento**, que é o raio girado de um
	# quarto de volta. No lugar de baixo isso dá o leque normal, deitado; nos lados
	# dá um leque em pé; em cima, um leque de cabeça para baixo.
	#
	# Só os versos: o nome e a contagem moram na pílula do assento, como no
	# protótipo, e o destaque da vez também.
	var facing := _angle_of(seat) - PI * 0.5
	var along := Vector2(cos(facing), sin(facing))
	for index in shown:
		var offset := index - (shown - 1) * 0.5
		UnoCardArt.draw_back(
			self, center + along * (offset * step), back_height, facing + offset * 0.06
		)


## Meia extensão do grupo de cartas na direção `axis`.
##
## Sai do retângulo girado, e não de uma constante: o mesmo assento ocupa medidas
## diferentes conforme onde ele está na mesa — deitado em cima, em pé nos lados —
## e é essa medida que decide onde o nome cabe sem bater no vizinho.
static func _extent(axis: Vector2, spread: float, half: Vector2, facing: float) -> float:
	var along := Vector2(cos(facing), sin(facing))
	var across := Vector2(-along.y, along.x)
	return (
		absf(along.dot(axis)) * (spread + half.x)
		+ absf(across.dot(axis)) * half.y
	)


func _name_of(seat: int) -> String:
	if seat < names.size() and not names[seat].is_empty():
		return names[seat]
	return "Jogador %d" % (seat + 1)


# --- o meio da mesa -----------------------------------------------------------


func _draw_deck() -> void:
	if UnoRules.deck_of(state).is_empty() and UnoRules.pile_of(state).size() <= 1:
		# Baralho e descarte esgotados. O lugar continua marcado — sumir com ele
		# faria a mesa parecer quebrada em vez de vazia.
		_draw_slot(_deck_center)
		return
	# Duas lâminas atrás, subindo para a direita: é um **monte**, e não uma carta
	# virada. O verso de cima ganha a moldura limão quando comprar vale.
	var half := Vector2(UnoCardArt.width_for(_card_height), _card_height) * 0.5
	var slide := Vector2(1.0, -1.0) * _card_height * 0.045
	for depth in [2, 1]:
		draw_colored_polygon(
			_shift(UnoCardArt.rounded_rect(half, _card_height * UnoCardArt.CORNER), _deck_center + slide * depth),
			AppTheme.SURFACE_HIGH if depth == 2 else AppTheme.SURFACE_TOP
		)
	UnoCardArt.draw_back(
		self, _deck_center, _card_height, 0.0, 1.0,
		AppTheme.ACCENT if can_draw else Color(0, 0, 0, 0)
	)


func _draw_pile() -> void:
	if held_top >= 0:
		if UnoRules.is_wild(held_top):
			_draw_mat(_pile_center, UnoCardArt.COLORS[_held_color])
		UnoCardArt.draw_card(self, held_top, _pile_center, _card_height)
		return
	var top := UnoRules.top_card(state)
	if top < 0:
		_draw_slot(_pile_center)
		return
	# A cor ativa só difere da carta do topo depois de um curinga, e é só ali que o
	# tapete aparece. Nas outras a carta já diz a cor, e a pílula embaixo repete.
	if UnoRules.is_wild(top):
		_draw_mat(_pile_center, UnoCardArt.COLORS[UnoRules.active_color(state)])
	UnoCardArt.draw_card(self, top, _pile_center, _card_height)


## O realce: uma carta um pouco maior, da cor, atrás da carta de verdade.
##
## Era um anel (`draw_arc` de raio proporcional à altura), e o anel estava errado
## por construção: a carta é alta e estreita, então um círculo que cobre a altura
## sobra muito para os lados — os dois anéis se cruzavam no meio da mesa. O tapete
## tem a forma da carta, então sobra igual dos quatro lados.
func _draw_mat(center: Vector2, color: Color) -> void:
	var half := Vector2(_card_height * UnoCardArt.ASPECT, _card_height) * 0.5
	var grow := Vector2.ONE * _card_height * MAT_GROW
	draw_colored_polygon(
		_shift(
			UnoCardArt.rounded_rect(half + grow, _card_height * (UnoCardArt.CORNER + MAT_GROW)),
			center
		),
		color
	)


func _draw_slot(center: Vector2) -> void:
	var half := Vector2(_card_height * UnoCardArt.ASPECT, _card_height) * 0.5
	draw_rect(Rect2(center - half, half * 2.0), AppTheme.BORDER, false, maxf(_card_height * 0.02, 1.0))


## O feltro: uma oval clara sob a mesa inteira, como no protótipo.
func _draw_felt() -> void:
	var half := Vector2(size.x * 0.47, size.y * 0.36) if _portrait() else Vector2(size.x * 0.40, size.y * 0.47)
	_felt.draw_set_transform(_table_center(), 0.0, Vector2(half.x / half.y, 1.0))
	_felt.draw_circle(Vector2.ZERO, half.y, AppTheme.SURFACE)
	_felt.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## O sentido do jogo: quatro traços num anel em volta do meio, cada um com a ponta
## para onde a vez anda, girando para o mesmo lado. É o único efeito do inverte
## que se vê, já que nenhuma mão muda.
func _draw_ring() -> void:
	if state == null:
		return
	var forward := UnoRules.direction_of(state) > 0
	var center := _table_center()
	var radius := minf(size.x, size.y) * 0.36 if _portrait() else size.y * 0.40
	var thick := maxf(radius * 0.04, 3.0)
	var dash := TAU * 0.17
	for index in 4:
		var start := TAU * 0.25 * index
		_ring.draw_arc(center, radius, start, start + dash, 24, AppTheme.SURFACE_TOP, thick, true)
		var tip_angle := start + dash if forward else start
		var heading := Vector2(-sin(tip_angle), cos(tip_angle)) * (1.0 if forward else -1.0)
		var tip := center + Vector2(cos(tip_angle), sin(tip_angle)) * radius
		var side := Vector2(-heading.y, heading.x) * thick * 1.5
		_ring.draw_colored_polygon(
			PackedVector2Array([tip + heading * thick * 1.6, tip + side, tip - side]),
			AppTheme.SURFACE_TOP
		)


## A pílula embaixo do monte e do descarte.
func _draw_hint() -> void:
	if hint.is_empty():
		return
	var font := AppTheme.font(800)
	var font_size := 13
	var width := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 28.0
	# Deitada, embaixo das cartas, como no protótipo. De pé, em cima: embaixo
	# ficam as pílulas dos dois assentos laterais, na mesma altura.
	var below := _card_height * 0.64 + 13.0
	var middle := Vector2(_table_center().x, _deck_center.y + (-below if _portrait() else below))
	var rect := Rect2(middle - Vector2(width * 0.5, 13.0), Vector2(width, 26.0))
	draw_style_box(AppTheme.box(AppTheme.ACCENT if hint_lit else AppTheme.SURFACE_HIGH, 13), rect)
	draw_string(
		font, Vector2(rect.position.x + 14.0, middle.y + 5.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		AppTheme.ACCENT_INK if hint_lit else AppTheme.TEXT_DIM
	)


# --- utilidades ---------------------------------------------------------------


static func _shift(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point + by)
	return out


func _gui_input(event: InputEvent) -> void:
	if not can_draw:
		return
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	var half := Vector2(_card_height * UnoCardArt.ASPECT, _card_height) * 0.5
	# Alvo maior que o desenho: o monte é o toque mais frequente da partida depois
	# das cartas da mão, e um polegar não acerta 60 px de largura com precisão.
	if Rect2(_deck_center - half * 1.35, half * 2.7).has_point(press.position):
		deck_tapped.emit()
		accept_event()
