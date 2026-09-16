class_name DieView
extends Control

## O dado: a face, a rolagem e o convite a tocar.
##
## É o único lugar da partida onde o jogador **age sem escolher** — ele não
## decide o resultado, só pede um. Por isso o nó inteiro é o alvo do toque, e não
## um botão ao lado de um desenho: o dado é o botão.
##
## A rolagem passa por vários números antes de parar. Sem isso o resultado
## simplesmente aparece, e um número que aparece parece decidido pelo app; um que
## para de rolar parece sorteado — que é o que de fato aconteceu.
##
## ## Os pontos não trocam: eles nascem e somem
##
## Um dado de verdade tem **sete lugares** possíveis para um ponto, e cada face é
## um subconjunto deles. A transição entre dois números é, então, os pontos que
## saem encolhendo e os que entram crescendo, cada um no seu lugar fixo.
##
## Trocar a face inteira de uma vez dava um piscar que lia como falha de
## desenho; interpolar posição faria os pontos deslizarem pela face, que não é
## coisa que dado faça. Nascer e sumir no lugar é o que acontece de verdade
## quando um dado tomba de uma face para a outra.
##
## A rolagem também **desacelera**: os primeiros números passam depressa e os
## últimos demoram, como um dado perdendo energia. É o que faz o resultado
## parecer o fim de um movimento, e não o instante em que a animação foi
## desligada.

signal rolled(value: int)

## Quanto tempo o dado rola antes de parar. Longo o bastante para a rolagem ser
## um acontecimento — ela é o único gesto da vez de cada jogador — e curto o
## bastante para não virar espera com quatro pessoas na mesa.
const SPIN := 0.95
## Intervalo entre dois números, no começo e no fim da rolagem. A diferença
## entre os dois é a desaceleração.
const FLIP_FIRST := 0.07
const FLIP_LAST := 0.24
## Transição de um número para o outro. Fração do intervalo, e não tempo fixo:
## no começo os números passam rápido e o morph acompanha; no fim ele se estica
## junto e o último ponto se acomoda com calma.
const MORPH_SHARE := 0.75
## Quanto o dado balança enquanto rola, em fração do próprio lado. Pouco: é para
## dar peso, não para o número ficar difícil de ler.
const SHAKE := 0.06
## Velocidade do balanço, em radianos por segundo, com o dado cheio de energia e
## já quase parado. Ele desacelera junto com a rolagem — um dado que perde
## velocidade de tombo e continua vibrando na mesma frequência parece um objeto
## preso numa máquina, não um dado rolando.
## Perto de 2,5 Hz no auge. Já esteve em 26 rad/s, que é o dobro disso, e ali o
## movimento contínuo ainda **lia** como tremor: a diferença entre balançar e
## vibrar é de frequência, não de suavidade.
const WOBBLE_FAST := 16.0
const WOBBLE_SLOW := 5.0
## Relação entre as frequências dos dois eixos. Irracional de propósito: em 1:1 o
## dado percorre uma diagonal para lá e para cá, que lê como trilho. Fora de fase,
## o caminho é uma curva que nunca se repete.
const WOBBLE_RATIO := 1.37
## O quique de quando ele para. Cresce e volta — é o que faz o número final
## parecer ter caído, e não ter sido escrito.
const SETTLE := 0.28
const SETTLE_SCALE := 0.14

## Os sete lugares de ponto de um dado, em fração da face. Toda face é um
## subconjunto disto, e é o que torna a transição uma questão de quem aparece.
const SLOTS := [
	Vector2(0.28, 0.28), Vector2(0.72, 0.28),   # 0, 1: topo
	Vector2(0.28, 0.50), Vector2(0.72, 0.50),   # 2, 3: meio das laterais
	Vector2(0.28, 0.72), Vector2(0.72, 0.72),   # 4, 5: base
	Vector2(0.50, 0.50),                        # 6: centro
]
## Que lugares cada número ocupa. Escritas como as faces de um dado de verdade:
## os pares nas diagonais, o ímpar acrescentando o centro.
const FACES := {
	1: [6],
	2: [0, 5],
	3: [0, 6, 5],
	4: [0, 1, 4, 5],
	5: [0, 1, 6, 4, 5],
	6: [0, 1, 2, 3, 4, 5],
}

## Face mostrada. Zero é o dado ainda não rolado nesta vez — a face fica em
## branco e o convite ("toque para rolar") é o que aparece.
##
## Escrever aqui **transiciona**: o número anterior sai e o novo entra. É o mesmo
## caminho que a rolagem usa, então um valor posto de fora (uma partida
## reconstruída, um print) chega com a mesma animação.
var value := 0:
	set(new_value):
		if new_value == value:
			return
		_previous = value
		value = new_value
		_morph = 0.0
		_morph_time = maxf(0.06, FLIP_FIRST * MORPH_SHARE)
		_wake()

## Cor de quem está jogando. O dado é o mesmo objeto para os quatro, e a borda é
## o que diz de quem é a vez sem uma segunda etiqueta na tela.
var tint := AppTheme.ACCENT:
	set(new_tint):
		tint = new_tint
		queue_redraw()

## Ninguém rola enquanto o tabuleiro espera um peão: o dado já foi lançado e o
## que falta é usá-lo.
var enabled := true:
	set(new_enabled):
		enabled = new_enabled
		queue_redraw()

var _spinning := false
var _spin_left := 0.0
var _flip_left := 0.0
var _result := 0
## Número que está saindo, e quanto da saída já passou.
var _previous := 0
var _morph := 1.0
var _morph_time := 0.12
## Tempo desde que o dado parou, enquanto o quique dura.
var _settle := -1.0
## Deslocamento do balanço. Guardado em vez de sorteado no `_draw` porque um
## desenho tem de sair igual quantas vezes for chamado — sorteando ali, o dado
## tremeria a cada redesenho da tela, inclusive parado.
var _offset := Vector2.ZERO
## Fase do balanço, acumulada. É o que permite a frequência cair sem o movimento
## dar um salto: mudando a velocidade de um seno lido de `t * f`, o argumento pula
## junto; acumulando a fase, ele só passa a crescer mais devagar.
var _wobble := 0.0


## O `mouse_filter` **não** é escrito aqui, e a ausência é a correção.
##
## Ele era posto em `MOUSE_FILTER_STOP`, que já é o padrão de `Control` — então a
## linha não fazia nada, exceto apagar a escolha de quem tivesse decidido o
## contrário. E alguém tinha: em Metrópole os dados não aceitam toque, porque são
## **dois** e cada um sorteando por conta produziria um lance que não existe.
## Aquela tela escrevia `IGNORE` antes do `add_child`, e este `_ready` desfazia.
##
## O sintoma era um dado que girava ao ser tocado e parava num número que a
## partida ignorava — e que ainda gastava um dos dois avisos de "dado parou",
## atrapalhando a rolagem seguinte.
##
## `custom_minimum_size` continua sendo escrito, e por isso quem quiser outro
## tamanho tem de escrevê-lo **depois** de entrar na árvore. Fica porque 76 é o
## tamanho do único alvo de toque da tela do Ludo, e ali ele é a regra.
func _ready() -> void:
	custom_minimum_size = Vector2(76, 76)
	set_process(false)


func _gui_input(event: InputEvent) -> void:
	# Por [Tap]: um clique chega duas vezes, e o segundo pedido cairia no dado que
	# já está rolando. Contar uma vez é a diferença entre ignorar um evento e nunca
	# tê-lo recebido.
	if Tap.began(event):
		accept_event()
		roll()


## O resultado é sorteado **agora**, e não quando a animação termina: assim o
## que a partida registra não depende de quantos quadros a tela conseguiu
## desenhar. A animação só atrasa a notícia.
func roll() -> void:
	roll_to(randi_range(1, 6))


## Gira até parar num valor **já decidido**.
##
## Existe porque nem todo dado é sorteado aqui. Numa mesa de mais de um aparelho
## o valor chega pronto de quem rolou, e num jogo de dois dados os dois têm de
## ser decididos juntos antes de virarem lance — em Metrópole, `[ROLL, d1, d2]`
## é uma coisa só, e dois dados sorteando cada um por conta produziriam um lance
## que não existe até os dois pararem.
##
## `roll()` continua sendo o caminho de quem sorteia na hora, e agora é uma linha
## dele: o sorteio é a única diferença entre os dois.
func roll_to(result: int) -> void:
	if _spinning or not enabled:
		return
	_result = clampi(result, 1, 6)
	_spinning = true
	_spin_left = SPIN
	_flip_left = 0.0
	_settle = -1.0
	_wobble = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_morph = minf(1.0, _morph + delta / maxf(0.001, _morph_time))

	if _spinning:
		_spin_left -= delta
		_flip_left -= delta
		_shake(delta)
		if _spin_left <= 0.0:
			_land()
		elif _flip_left <= 0.0:
			_tumble()
		queue_redraw()
		return

	if _settle >= 0.0:
		_settle += delta
		if _settle >= SETTLE and _morph >= 1.0:
			_settle = -1.0
			set_process(false)
	elif _morph >= 1.0:
		set_process(false)
	queue_redraw()


## O balanço, quadro a quadro.
##
## Ele morava em [method _tumble], sorteado de uma vez a cada troca de número, e
## era esse o tranco: entre dois sorteios o dado ficava **parado** numa posição
## qualquer e depois saltava para outra, de 0,07 a 0,24 segundos por salto. Isso
## não é balanço, é teletransporte — e é exatamente o que se via.
##
## Aqui ele é contínuo: dois senos fora de fase traçam uma curva que não se repete,
## a fase acumula (então a frequência pode cair sem o movimento pular), e a
## amplitude cai com a energia que sobra. O dado chega em zero **por conta
## própria** no instante em que para, e por isso a pousada não tem corte.
func _shake(delta: float) -> void:
	var energy := clampf(_spin_left / SPIN, 0.0, 1.0)
	_wobble += delta * lerpf(WOBBLE_SLOW, WOBBLE_FAST, energy)
	var side := minf(size.x, size.y)
	_offset = Vector2(
		sin(_wobble), sin(_wobble * WOBBLE_RATIO + 1.1)
	) * side * SHAKE * energy


## Mais um número no caminho, com o intervalo crescendo: quanto menos falta
## girar, mais devagar ele passa.
func _tumble() -> void:
	var spent := 1.0 - clampf(_spin_left / SPIN, 0.0, 1.0)
	var interval := lerpf(FLIP_FIRST, FLIP_LAST, spent * spent)
	_flip_left = interval
	var face := randi_range(1, 6)
	# Sem repetir o anterior: um número que aparece duas vezes seguidas lê como
	# animação travada, e travada durante a rolagem parece bug.
	value = face if face != value else (face % 6) + 1
	_morph_time = interval * MORPH_SHARE


## O dado para no resultado. O aviso sai aqui, e não no fim do quique: o quique
## é enfeite, e prender a partida a ele atrasaria a jogada por uma animação.
func _land() -> void:
	_spinning = false
	_offset = Vector2.ZERO
	_settle = 0.0
	value = _result
	_morph_time = FLIP_LAST * MORPH_SHARE
	rolled.emit(_result)


func _wake() -> void:
	set_process(true)
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	# O quique é uma escala que sobe e volta, aplicada ao lado do dado. Meio seno
	# porque ele tem de sair de 1 e voltar a 1 — uma curva que não fecha deixa o
	# dado ligeiramente maior para sempre, e ninguém descobre por quê.
	if _settle >= 0.0:
		side *= 1.0 + SETTLE_SCALE * sin(clampf(_settle / SETTLE, 0.0, 1.0) * PI)
	var rect := Rect2((size - Vector2.ONE * side) * 0.5 + _offset, Vector2.ONE * side)
	rect = rect.grow(-side * 0.06)

	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(int(side * 0.22))
	box.bg_color = AppTheme.SURFACE_HIGH if enabled else AppTheme.SURFACE
	box.border_color = Color(tint, 1.0 if enabled else 0.35)
	box.set_border_width_all(2)
	if enabled and value == 0 and _morph >= 1.0:
		box.shadow_color = Color(tint, 0.22)
		box.shadow_size = int(side * 0.12)
	draw_style_box(box, rect)

	if value == 0 and _previous == 0:
		# Sem face: o ponto único no meio é o alvo, e some assim que houver
		# número para mostrar.
		draw_circle(rect.get_center(), side * 0.07, Color(tint, 0.5 if enabled else 0.2))
		return

	# Suavizado nas duas pontas: um ponto que cresce em linha reta parece
	# aparecer de repente, e o que se quer é vê-lo nascer.
	var eased := smoothstep(0.0, 1.0, _morph)
	var leaving: Array = FACES.get(_previous, [])
	var arriving: Array = FACES.get(value, [])
	var pip := side * 0.075
	var color := Color(AppTheme.TEXT, 1.0 if enabled else 0.35)

	for slot in SLOTS.size():
		var was := 1.0 if leaving.has(slot) else 0.0
		var becomes := 1.0 if arriving.has(slot) else 0.0
		var presence := lerpf(was, becomes, eased)
		if presence <= 0.01:
			continue
		# O ponto encolhe e desaparece ao mesmo tempo: só o tamanho deixaria um
		# ponto minúsculo cravado na face, e só o alfa daria um fantasma.
		draw_circle(
			rect.position + SLOTS[slot] * rect.size,
			pip * presence,
			Color(color, color.a * presence)
		)
