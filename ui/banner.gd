class_name Banner
extends Control

## Aviso flutuante para o que não pode passar despercebido: xeque, lance
## recusado, oponente saiu, código digitado errado.
##
## Antes essas mensagens iam para uma linha cinza no rodapé, no mesmo lugar e no
## mesmo peso do texto de rotina — e passavam batidas. A linha de rodapé muda o
## tempo todo ("conectando a 192.168.0.4…"), então o olho aprende a ignorá-la, e
## era ali que os erros iam morrer. Aqui elas entram animadas por cima do
## conteúdo, que é o custo certo para uma informação que muda o que o jogador
## deve fazer agora.
##
## Some sozinho. Um modal exigiria confirmar cada aviso, inclusive os que o
## jogador já entendeu antes de terminar de ler.

enum Kind { INFO, ALERT, DANGER }

const AUTO_HIDE := 2.6
## Aviso longo dura mais: o tempo de leitura é o que decide, não um número fixo.
const AUTO_HIDE_PER_CHARACTER := 0.045
const AUTO_HIDE_MAX := 7.0

## Multiplica o tempo em tela desta instância.
##
## Existe porque "quanto tempo ler" não é a mesma pergunta em todas as telas. No
## xadrez o aviso é uma reação a um toque que o jogador acabou de dar — ele já sabe
## o que fez, e o aviso só confirma. Em Metrópole ele é a **notícia**: quem pagou
## quanto a quem e por qual casa, com nomes que quem assiste precisa ligar a
## cadeiras, e muitas vezes durante a vez de outra pessoa, quando o olho está no
## tabuleiro e não no topo da tela.
##
## Um número por tela, e não um por mensagem: seria o mesmo valor repetido em todas
## as chamadas de uma cena, e o dia em que alguém esquecesse uma o aviso mais
## importante seria justamente o que passa voando.
var linger := 1.0

const PADDING := Vector2(44.0, 22.0)
const LINE_HEIGHT := 22.0
const FONT_SIZE := 17

var _message := ""
var _kind := Kind.INFO
var _timer: SceneTreeTimer = null
## Deslocamento do desenho na entrada, e não da posição do nó.
##
## A cena posiciona o aviso por âncora e offset — a Metrópole o desce para baixo
## da barra translúcida —, e animar `position` reescreve os offsets: depois do
## primeiro aviso ele morava em `y = 0`, embaixo da barra. O quique é só desenho.
var _lift := 0.0:
	set(value):
		_lift = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 46)
	modulate.a = 0.0


## `persistent` para condições que continuam verdadeiras (xeque); temporário
## para reações a um toque.
func show_message(text: String, kind: Kind = Kind.INFO, persistent: bool = false) -> void:
	if text == _message and modulate.a > 0.5 and persistent:
		return
	_message = text
	_kind = kind
	queue_redraw()

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.18)
	_lift = -8.0
	tween.parallel().tween_property(self, "_lift", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if _timer != null and _timer.time_left > 0.0:
		_timer.timeout.disconnect(_fade_out)
	if not persistent:
		var visible_for := minf(
			AUTO_HIDE + text.length() * AUTO_HIDE_PER_CHARACTER, AUTO_HIDE_MAX
		) * linger
		_timer = get_tree().create_timer(visible_for)
		_timer.timeout.connect(_fade_out)


func hide_message() -> void:
	_message = ""
	_fade_out()


func _fade_out() -> void:
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)


func _draw() -> void:
	if _message.is_empty():
		return
	draw_set_transform(Vector2(0.0, _lift))
	var font := AppTheme.font(600)
	# A caixa não pode passar da largura do nó: uma mensagem de pareamento tem
	# frase inteira, e sem quebra ela saía pelos dois lados da tela.
	var lines := _wrap(font, size.x - PADDING.x - 16.0)
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)

	# Encostado no topo do nó, e não centralizado nele: assim uma mensagem de três
	# linhas cresce para baixo em vez de subir por cima do que está acima dela.
	var box_size := Vector2(widest + PADDING.x, LINE_HEIGHT * lines.size() + PADDING.y)
	var box := Rect2(Vector2((size.x - box_size.x) * 0.5, 3.0), box_size)
	draw_style_box(_style(), box)

	# O ponto acompanha a primeira linha, não o centro da caixa: com três linhas
	# ele ficaria boiando no meio do texto.
	var text_x := box.position.x + 32.0
	var first_baseline := box.position.y + PADDING.y * 0.5 + LINE_HEIGHT * 0.75
	draw_circle(Vector2(box.position.x + 18.0, first_baseline - 5.0), 5.0, _foreground())
	for index in lines.size():
		draw_string(
			font, Vector2(text_x, first_baseline + LINE_HEIGHT * index), lines[index],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, _foreground()
		)


## Quebra por palavra. Uma palavra maior que a linha fica sozinha e transborda —
## acontece com um endereço IP ou um código, e cortá-los no meio seria pior que
## deixar passar um pouco da borda.
func _wrap(font: Font, available: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := ""
	for word in _message.split(" "):
		var candidate := word if current.is_empty() else "%s %s" % [current, word]
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= available:
			current = candidate
			continue
		if not current.is_empty():
			lines.append(current)
		current = word
	if not current.is_empty():
		lines.append(current)
	return lines


func _foreground() -> Color:
	match _kind:
		Kind.DANGER:
			return AppTheme.DANGER
		Kind.ALERT:
			return AppTheme.ACCENT
		_:
			return AppTheme.TEXT


## Bolacha escura com o contorno de giz na cor do aviso: o mesmo vocabulário do
## resto do tema, e escuro porque o aviso aparece **sobre** o tabuleiro — um fundo
## claro ali seria um buraco na mesa.
func _style() -> StyleBox:
	return AppTheme.dashed(AppTheme.COASTER, Color(_foreground(), 0.85), 20, 1.5)
