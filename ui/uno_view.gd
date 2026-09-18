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

## Medidas calculadas no desenho e reusadas pelo toque. Guardadas em vez de
## recalculadas no `_gui_input` porque as duas contas precisam concordar: um monte
## que acende num lugar e aceita toque em outro é pior que um monte que não acende.
var _card_height := 0.0
var _deck_center := Vector2.ZERO
var _pile_center := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	_layout()
	if state == null:
		return
	_draw_direction()
	_draw_seats()
	_draw_deck()
	_draw_pile()


func _layout() -> void:
	var center := Vector2(size.x * TABLE_AT.x, size.y * TABLE_AT.y)
	# As duas cartas do meio dividem a largura livre entre os assentos laterais.
	#
	# Menores do que caberiam, de propósito. O monte e o descarte são as duas
	# coisas da mesa que **não** competem por atenção — o descarte diz a cor e o
	# valor de uma carta só, e o monte é um alvo de toque. Grandes, eles empurram o
	# nome de cada assento para fora do vão em que ele cabe, e o rótulo acaba tendo
	# de escolher um lado conforme onde o assento está. Menores, o vão entre o
	# assento e o meio abre, e o nome pode ir sempre para o mesmo lugar.
	_card_height = minf(size.y * 0.30, (size.x * 0.12) / UnoCardArt.ASPECT)
	var gap := UnoCardArt.width_for(_card_height) * 0.72
	_deck_center = center - Vector2(gap, 0.0)
	_pile_center = center + Vector2(gap, 0.0)


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
	return Vector2(size.x * TABLE_AT.x, size.y * TABLE_AT.y)


## O ponto onde o raio do assento encontra a **borda do retângulo**.
##
## O fator é o menor dos dois que levam à borda: quem estourar primeiro manda. É
## isso que empurra os assentos de ângulo quase horizontal para os cantos em vez
## de deixá-los amontoados no meio da lateral.
func _seat_center(seat: int) -> Vector2:
	var angle := _angle_of(seat)
	var ray := Vector2(cos(angle), sin(angle))
	var half := Vector2(size.x * RADIUS.x, size.y * RADIUS.y)
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
	var center := _seat_center(seat)
	var away := (center - _table_center()).normalized()
	var back_height := minf(size.y * 0.19, _card_height * 0.52)

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
	var spot := center + away * (mat + reach + 8.0) - tag * 0.5
	return Vector2(
		clampf(spot.x, 0.0, maxf(0.0, size.x - tag.x)),
		clampf(spot.y, 0.0, maxf(0.0, size.y - tag.y))
	)


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
func _draw_seat(seat: int, center: Vector2, is_turn: bool) -> void:
	var held := UnoRules.hand_size(state, seat)
	var back_height := minf(size.y * 0.19, _card_height * 0.52)
	var shown := mini(held, MAX_BACKS)
	var step := UnoCardArt.width_for(back_height) * BACK_STEP

	# Uma carta na mão é o aviso mais forte da mesa, e é o que o Uno grita em voz
	# alta na vida real. Vermelho — a cor que o app já usa para o que custa caro.
	var alarm := held == 1
	var tint := color_of_seat(seat)
	var ink := AppTheme.DANGER if alarm else (AppTheme.TEXT if is_turn else AppTheme.TEXT_DIM)

	# O leque abre ao longo do eixo x **do assento**, que é o raio girado de um
	# quarto de volta. No lugar de baixo isso dá o leque normal, deitado; nos lados
	# dá um leque em pé; em cima, um leque de cabeça para baixo — que é como as
	# cartas de quem está do outro lado da mesa apontam.
	var facing := _angle_of(seat) - PI * 0.5
	var along := Vector2(cos(facing), sin(facing))
	var half := Vector2(UnoCardArt.width_for(back_height), back_height) * 0.5
	var spread := step * maxf(shown - 1, 0) * 0.5

	# A moldura da cor do dono, girada junto com o leque. É o que amarra a mão na
	# mesa ao nome na coluna da esquerda — sem ela, seis leques idênticos de costas
	# só se distinguem por posição, e a posição muda de aparelho para aparelho.
	_draw_seat_mat(center, half + Vector2(spread, 0.0), back_height, facing, tint, is_turn)

	for index in shown:
		var offset := index - (shown - 1) * 0.5
		UnoCardArt.draw_back(
			self, center + along * (offset * step), back_height, facing + offset * 0.06
		)

	# O número em cima do leque, e **sem o nome ao lado**.
	#
	# O nome saiu da mesa e foi para a coluna da esquerda, junto do da cor. Ele
	# passou por três lugares aqui antes disso — acima do leque, para dentro pelo
	# raio, e de novo acima — e nenhum resolvia os seis assentos ao mesmo tempo:
	# um rótulo é uma linha larga e baixa, e numa mesa de seis não há vão largo o
	# bastante em todas as direções. O que resolve não é achar o vão certo, é o
	# nome não precisar estar aqui: a cor da moldura já diz de quem é a mão.
	var disc := back_height * 0.32
	draw_circle(center, disc, Color(AppTheme.BACKGROUND, 0.88))
	_text(str(held), center, disc * 1.25, ink)


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


## A moldura da cor do dono, atrás do leque e girada com ele.
##
## Preenchimento fraco mais borda: só a borda some contra um fundo escuro quando
## a moldura é fina, e só o preenchimento vira uma mancha sem limite. Na vez do
## jogador os dois sobem juntos — é o mesmo destaque, mais forte, e não um
## segundo enfeite que o olho tem de aprender.
func _draw_seat_mat(
	center: Vector2, half: Vector2, back_height: float,
	facing: float, tint: Color, is_turn: bool
) -> void:
	var pad := Vector2.ONE * back_height * 0.16
	var shape := UnoCardArt.rounded_rect(half + pad, back_height * 0.26)
	var turn := Transform2D(facing, center)
	var placed := PackedVector2Array()
	for point in shape:
		placed.append(turn * point)

	draw_colored_polygon(placed, Color(tint, 0.30 if is_turn else 0.12))
	var outline := placed.duplicate()
	outline.append(placed[0])
	draw_polyline(
		outline, Color(tint, 1.0 if is_turn else 0.6),
		maxf(back_height * (0.06 if is_turn else 0.035), 1.5), true
	)


func _name_of(seat: int) -> String:
	if seat < names.size() and not names[seat].is_empty():
		return names[seat]
	return "Jogador %d" % (seat + 1)


# --- o meio da mesa -----------------------------------------------------------


func _draw_deck() -> void:
	# O realce vai **por baixo**: por cima ele cobriria a moldura clara da carta,
	# que é a segunda coisa que se lê nela.
	if can_draw:
		_draw_mat(_deck_center, AppTheme.ACCENT)

	if UnoRules.deck_of(state).is_empty() and UnoRules.pile_of(state).size() <= 1:
		# Baralho e descarte esgotados. O lugar continua marcado — sumir com ele
		# faria a mesa parecer quebrada em vez de vazia.
		_draw_slot(_deck_center)
		return
	# Três versos empilhados, e não um: um verso sozinho lê como uma carta virada,
	# e o que está ali é um **monte**.
	for depth in range(2, -1, -1):
		var slide := Vector2(-1.0, -1.0) * depth * _card_height * 0.018
		UnoCardArt.draw_back(self, _deck_center + slide, _card_height)


func _draw_pile() -> void:
	var top := UnoRules.top_card(state)
	if top < 0:
		_draw_slot(_pile_center)
		return
	# A cor ativa não é a cor da carta do topo: elas coincidem quase sempre e
	# discordam justamente depois de um curinga, que é quando a informação importa.
	# Por isso o tapete é desenhado sempre, e não só nesse caso — um realce que
	# aparece e some ensina o jogador a procurá-lo.
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


## O sentido do jogo: um arco em volta do meio da mesa, girando para o lado em
## que a vez anda.
##
## Concêntrico com os assentos de propósito. É o que faz a seta apontar para o
## **próximo jogador** em vez de para um lado da tela — e é o que dá ao inverte um
## efeito visível, já que ele não mexe em nenhuma mão.
func _draw_direction() -> void:
	var forward := UnoRules.direction_of(state) > 0
	var radius := minf(size.y * 0.09, size.x * 0.05)
	# Rente ao rodapé da mesa, logo acima do leque da mão.
	#
	# É o lugar do jogador local no anel, e ele fica vazio — a mão dele é o leque
	# abaixo desta vista. A seta ali não disputa espaço com assento nenhum, e fica
	# no caminho do olho que vai da mesa para a própria mão, que é o percurso que
	# se faz a cada vez.
	#
	# Ela nasceu no alto e depois no raio da mesa; nos dois lugares caiu em cima do
	# contador de um assento. Aqui não há o que atropelar.
	var center := Vector2(size.x * 0.5, size.y - radius * 1.35)
	var thickness := maxf(radius * 0.16, 2.0)
	var ink := Color(AppTheme.TEXT_DIM, 0.75)

	# Quase o anel inteiro: solta no rodapé, a seta é um **ícone**, e um arco curto
	# solto lê como um risco. Fechando três quartos de volta ela lê como giro.
	var span := TAU * 0.72
	var start := -PI * 0.35 if forward else -PI * 0.65
	var sweep := span if forward else -span
	draw_arc(center, radius, start, start + sweep, 28, ink, thickness, true)

	var tip_angle := start + sweep
	var tip := center + Vector2(cos(tip_angle), sin(tip_angle)) * radius
	# Perpendicular ao raio, no sentido da varredura: é o que faz a ponta apontar
	# para onde a vez anda em vez de para fora do círculo.
	var heading := Vector2(-sin(tip_angle), cos(tip_angle)) * (1.0 if forward else -1.0)
	var side := Vector2(-heading.y, heading.x)
	var head := radius * 0.62
	draw_colored_polygon(PackedVector2Array([
		tip + heading * head,
		tip - heading * head * 0.4 + side * head * 0.6,
		tip - heading * head * 0.4 - side * head * 0.6,
	]), ink)


# --- utilidades ---------------------------------------------------------------


static func _shift(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point + by)
	return out


## Texto centrado no ponto. `draw_string` ancora na linha de base e alinha à
## esquerda, então centrar de verdade pede a medida da string.
func _text(label: String, at: Vector2, span: float, ink: Color) -> void:
	var font := AppTheme.font(600)
	var points := int(maxf(span, 8.0))
	var measure := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, points)
	draw_string(
		font, at + Vector2(-measure.x * 0.5, points * 0.36),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, points, ink
	)


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
