class_name UnoFx
extends Control

## As cartas em voo: a jogada indo para o descarte, a compra saindo do monte.
##
## ## Desenho, e não estado
##
## O lance já foi aplicado quando o voo começa. A camada só desenha uma carta indo
## de um ponto a outro, e quem decide o que a mesa mostra enquanto isso é a cena —
## o descarte segura o topo antigo, a mão espera a carta comprada chegar. Assim a
## regra, a rede e o histórico não sabem que a animação existe, e uma partida
## reconstruída por sincronia não tem voo nenhum a desfazer.
##
## ## Por cima de tudo, sem toque
##
## Uma camada só por cima da mesa **e** da mão, porque o voo atravessa as duas: a
## carta sai do leque, que é um nó, e pousa no descarte, que é outro. E ela não
## pega toque — um voo de 0,3 s não pode engolir o toque seguinte do jogador.
##
## Os pontos chegam em coordenadas globais, e é aqui que eles viram locais: quem
## chama não precisa saber onde esta camada está.

## Quanto dura um voo.
const FLIGHT := 0.32
## Intervalo entre as cartas de uma compra de várias.
const DRAW_GAP := 0.09
## Teto do escalonamento inteiro. Uma pilha de +4 sobre +4 são oito cartas, e
## oito intervalos cheios fariam a compra durar mais que a leitura do aviso.
const DRAW_SPAN := 0.45
## Quanto o voo sobe acima da reta, em fração da distância. Um arco baixo: é o que
## diferencia uma carta lançada de uma carta arrastada.
const ARC := 0.12
## Quanto dura uma marca: o anel do curinga, o proibido do pula, o grito.
const MARK := 0.75

## Quantas vezes cada espécie de voo ou marca saiu, para a sonda conferir que cada
## lance produz o seu efeito e só o seu.
var played := {}

var _flights: Array[Dictionary] = []
## As marcas: efeitos que nascem e morrem num ponto, sem ir a lugar nenhum.
var _marks: Array[Dictionary] = []
## Relógio próprio, e não o do sistema: ele só anda enquanto há voo, e o momento
## de partida de cada voo é escrito nele.
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Lança uma carta e devolve em quantos segundos ela pousa.
##
## `card` negativo é verso o caminho inteiro (a compra, que ninguém vê). `reveal`
## mostra o verso na primeira metade e a face na segunda: é a carta de adversário,
## que só fica pública quando chega ao descarte.
func fly(
	card: int, from: Vector2, to: Vector2, from_height: float, to_height: float,
	delay := 0.0, from_angle := 0.0, reveal := false, tag := &"play"
) -> float:
	_note(tag)
	var inverse := get_global_transform().affine_inverse()
	_flights.append({
		"card": card,
		"from": inverse * from,
		"to": inverse * to,
		"from_height": from_height,
		"to_height": to_height,
		"from_angle": from_angle,
		"start": _clock + delay,
		"reveal": reveal,
	})
	set_process(true)
	return delay + FLIGHT


## O intervalo entre as cartas de uma compra de `count` cartas.
static func draw_gap(count: int) -> float:
	return minf(DRAW_GAP, DRAW_SPAN / maxf(count, 1.0))


## O curinga: um anel da cor escolhida abrindo a partir do descarte. É a cor que a
## mesa passa a pedir, e ela se espalha em vez de só aparecer no tapete.
func ring(at: Vector2, color: Color, delay := 0.0) -> void:
	_mark(&"ring", at, delay, {"color": color})


## O pula: a placa de proibido sobre quem perdeu a vez. O pula é a carta cujo efeito
## não se vê — ninguém compra nada —, e sem a placa a vez só some de alguém.
func forbid(at: Vector2, radius: float, delay := 0.0) -> void:
	_mark(&"forbid", at, delay, {"radius": radius})


## Um grito saltando de um assento: o "UNO!".
func shout(at: Vector2, text: String, delay := 0.0) -> void:
	_mark(&"shout", at, delay, {"text": text})


func busy() -> bool:
	return not _flights.is_empty()


func _note(kind: StringName) -> void:
	played[kind] = int(played.get(kind, 0)) + 1


func _mark(kind: StringName, at: Vector2, delay: float, extra: Dictionary) -> void:
	_note(kind)
	var mark := {"kind": kind, "at": get_global_transform().affine_inverse() * at,
		"start": _clock + delay}
	mark.merge(extra)
	_marks.append(mark)
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	_flights = _flights.filter(func(flight: Dictionary) -> bool:
		return _clock < float(flight["start"]) + FLIGHT
	)
	_marks = _marks.filter(func(mark: Dictionary) -> bool:
		return _clock < float(mark["start"]) + MARK
	)
	if _flights.is_empty() and _marks.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for mark in _marks:
		var t := (_clock - float(mark["start"])) / MARK
		if t >= 0.0:
			_draw_mark(mark, clampf(t, 0.0, 1.0))
	_draw_flights()


## As marcas crescem rápido, passam um pouco do tamanho e assentam — o "pop" que faz
## o olho achar o ponto —, e somem no último terço.
func _draw_mark(mark: Dictionary, t: float) -> void:
	var at: Vector2 = mark["at"]
	var fade := clampf((1.0 - t) * 3.0, 0.0, 1.0)
	var pop := minf(t / 0.25, 1.0)
	var grow := 1.0 + sin(pop * PI) * 0.18
	match mark["kind"]:
		&"ring":
			var reach := minf(size.x, size.y) * 0.42
			var color: Color = mark["color"]
			for wave in 2:
				var k := clampf(t * 1.3 - wave * 0.18, 0.0, 1.0)
				if k <= 0.0:
					continue
				var radius := lerpf(reach * 0.12, reach, 1.0 - pow(1.0 - k, 2.0))
				draw_arc(at, radius, 0.0, TAU, 72, Color(color, (1.0 - k) * 0.9),
					lerpf(14.0, 2.0, k), true)
		&"forbid":
			var radius: float = mark["radius"] * pop * grow
			draw_circle(at, radius * 1.15, Color(AppTheme.BACKGROUND, 0.85 * fade), true, -1.0, true)
			draw_set_transform(at, 0.0, Vector2.ONE)
			UnoCardArt._skip(self, radius, maxf(radius * 0.2, 2.0), Color(AppTheme.DANGER, fade), Vector2.ZERO)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"shout":
			var text: String = mark["text"]
			var font := AppTheme.display()
			var points := int(30.0 * pop * grow) + 1
			var measure := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, points)
			var spot := at + Vector2.UP * (24.0 + 26.0 * t) + Vector2(-measure.x * 0.5, points * 0.36)
			draw_string_outline(font, spot, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, points, 8,
				Color(AppTheme.BACKGROUND, fade))
			draw_string(font, spot, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, points,
				Color(AppTheme.ACCENT, fade))


func _draw_flights() -> void:
	for flight in _flights:
		var t := (_clock - float(flight["start"])) / FLIGHT
		if t < 0.0:
			continue
		# Sai rápido e freia no fim: é o pouso que o olho precisa ver, e não a saída.
		var k := 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)
		var from: Vector2 = flight["from"]
		var to: Vector2 = flight["to"]
		var at := from.lerp(to, k) + Vector2.UP * sin(k * PI) * from.distance_to(to) * ARC
		var height := lerpf(flight["from_height"], flight["to_height"], k)
		var angle := lerp_angle(flight["from_angle"], 0.0, k)
		var card: int = flight["card"]
		if card < 0 or (flight["reveal"] and k < 0.5):
			UnoCardArt.draw_back(self, at, height, angle)
		else:
			UnoCardArt.draw_card(self, card, at, height, angle)
