class_name MatchStatus
extends HFlowContainer

## A faixa de contexto da partida: há quanto tempo ela dura, quantas rodadas já
## passaram e qual é o código da sala.
##
## As três respondem à mesma pergunta — "onde eu estou nesta partida?" — e
## nenhuma delas cabe no tabuleiro. Ficam juntas porque quem procura uma costuma
## querer as outras: "estamos nisso há quanto tempo" e "quantas voltas já demos"
## são a mesma conversa, e o código é a resposta de quem perguntou primeiro
## "e se o celular cair?".
##
## ## Mora na barra da partida
##
## Os oito jogos têm telas que não se parecem em nada, e a faixa entra em todas
## pelo mesmo lugar: a [MatchBar], que a liga à partida em `bind()`. Oito cópias
## seriam oito formatos de relógio e oito jeitos de escrever "rodada". O que muda
## de jogo para jogo é só de onde saem os números — e se há rodada para contar:
## ver [member counts_rounds].
##
## É um `HFlowContainer` para caber numa barra estreita em pé sem cortar o código
## da sala: quando tempo, rodadas e sala não cabem lado a lado, ela quebra em vez
## de empurrar o título para fora.
##
## ## O código é um botão
##
## Ele existe para o caso de alguém cair, e quem caiu precisa **receber** o
## código de volta — normalmente por mensagem, de outra pessoa da mesa. Ler da
## tela e digitar em outro app é o caminho longo de uma coisa que o aparelho faz
## sozinho, então tocar copia. Sem código — no mesmo aparelho e contra o bot — o
## botão não existe: não há sala para voltar.

## O código foi para a área de transferência. A cena avisa do jeito dela — cada
## uma tem o seu banner, e um aviso desenhado aqui dentro apareceria no lugar
## errado em três das cinco telas.
signal code_copied

## Quanto tempo o botão fica dizendo "Copiado" antes de voltar ao código. Curto:
## ele é a confirmação de um gesto, e o que o jogador quer ver na faixa é o
## código.
const COPIED_NOTICE := 1.6

## De onde o relógio conta, em tempo Unix. Zero é "ainda não começou", e aí a
## faixa mostra zero em vez de contar desde 1970.
var started_at := 0:
	set(value):
		started_at = value
		_shown_seconds = -1

## Rodadas **completas**, não a rodada em curso: a pergunta é quanto de partida
## já passou.
var rounds := 0:
	set(value):
		if rounds == value:
			return
		rounds = value
		_refresh_rounds()

## O jogo conta rodadas. Uno, sinuca e Bomberman não contam — a regra deles não
## tem volta completa —, e um "0 rodadas" parado a partida inteira parece defeito.
var counts_rounds := true:
	set(value):
		counts_rounds = value
		_refresh_rounds()

## Código da sala, ou vazio fora de uma partida em rede.
var code := "":
	set(value):
		if code == value:
			return
		code = value
		_copied_left = 0.0
		_refresh_code()

## Quantos estão assistindo. Zero esconde a legenda: só aparece quando é
## verdade, e é o que garante que ninguém é assistido sem saber.
var watchers := 0:
	set(value):
		if watchers == value:
			return
		watchers = value
		_refresh_watchers()

var _clock: Label = null
var _rounds: Label = null
var _watchers: Label = null
var _code: Button = null
## Segundo já escrito na tela. O relógio só reescreve o texto quando o segundo
## vira — a alternativa é um `Label` remontando o texto sessenta vezes por
## segundo para mostrar a mesma coisa.
var _shown_seconds := -1
var _copied_left := 0.0


func _ready() -> void:
	alignment = FlowContainer.ALIGNMENT_CENTER
	add_theme_constant_override("h_separation", 12)
	add_theme_constant_override("v_separation", 2)

	_clock = _caption()
	_rounds = _caption()
	_watchers = _caption()

	_code = Button.new()
	# Chapado: a faixa é contexto, e um botão com fundo ao lado de duas legendas
	# leria como a ação principal de uma tela que já tem tabuleiro. A cor de
	# destaque é o que diz que dá para tocar.
	_code.flat = true
	_code.focus_mode = Control.FOCUS_NONE
	_code.add_theme_font_size_override("font_size", 14)
	_code.add_theme_color_override("font_color", AppTheme.ACCENT)
	_code.add_theme_color_override("font_hover_color", AppTheme.ACCENT)
	_code.add_theme_color_override("font_pressed_color", AppTheme.TEXT)
	_code.pressed.connect(_copy)
	add_child(_code)

	_refresh_rounds()
	_refresh_watchers()
	_refresh_code()
	set_process(true)


func _caption() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Caption"
	add_child(label)
	return label


func _process(delta: float) -> void:
	if _copied_left > 0.0:
		_copied_left -= delta
		if _copied_left <= 0.0:
			_refresh_code()

	var seconds := elapsed()
	if seconds == _shown_seconds:
		return
	_shown_seconds = seconds
	_clock.text = clock_text(seconds)


## Segundos de partida. Do relógio do sistema e não de um acumulador de `delta`:
## o app perde quadros quando o Android o recolhe para segundo plano, e um
## acumulador voltaria de uma pausa de dez minutos achando que se passaram dois
## segundos.
func elapsed() -> int:
	if started_at <= 0:
		return 0
	return maxi(0, int(Time.get_unix_time_from_system()) - started_at)


## `mm:ss` até uma hora, `h:mm:ss` depois. A hora só aparece quando existe:
## "0:07:12" numa partida de sete minutos gasta um campo para dizer zero.
static func clock_text(seconds: int) -> String:
	if seconds >= 3600:
		return "%d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _refresh_rounds() -> void:
	if _rounds == null:
		return
	_rounds.visible = counts_rounds
	_rounds.text = "1 rodada" if rounds == 1 else "%d rodadas" % rounds


func _refresh_watchers() -> void:
	if _watchers == null:
		return
	_watchers.visible = watchers > 0
	_watchers.text = "%d assistindo" % watchers


func _refresh_code() -> void:
	if _code == null:
		return
	_code.visible = not code.is_empty()
	_code.text = "Sala %s" % code


func _copy() -> void:
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	_code.text = "Copiado"
	_copied_left = COPIED_NOTICE
	Sound.play(Sound.Cue.TAP)
	code_copied.emit()
