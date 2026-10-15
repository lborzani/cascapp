class_name RoomCard
extends Button

## Uma sala pública na lista: o jogo, o ritmo e há quanto tempo está aberta.
##
## É um `Button` e não um painel decorado porque toda a linha é a área de toque.
## Um cartão bonito com um alvo pequeno é pior que um alvo grande sem enfeite —
## e aqui a linha inteira responde.

const HEIGHT := 66.0

var code := ""
var game_id := &"chess"
## Rótulo do ritmo, já formatado pelo lado do jogo ("3 + 2", "Sem relógio").
var clock_label := ""
var age_seconds := 0
## Lotação da sala. O servidor conta os dois desde que as salas passaram a ter
## N assentos: numa mesa de Ludo, "faltam dois" é a informação que decide se
## vale entrar agora.
var seats := 2
var taken := 1
## Apelido de quem abriu, já limpo pelo servidor. Vazio quando o relay é antigo
## ou quando quem abriu nunca escolheu um nome.
var host_name := ""
## Partida em andamento, da lista "Ao vivo": quantos já assistem. -1 é sala
## esperando jogador, que é o cartão de sempre.
var watchers := -1


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	theme_type_variation = &"GhostButton"
	# O desenho é todo próprio; o texto do Button seria uma segunda camada
	# competindo com ele.
	text = ""


func _draw() -> void:
	var pad := 16.0
	var piece := Game.piece_of(game_id)
	var piece_size := size.y * 0.62
	var center := Vector2(pad + piece_size * 0.5, size.y * 0.5)
	# A peça em bolacha, como no cardápio e na folha: a mesma moldura redonda para
	# "qual jogo" em toda a lista do app.
	draw_circle(center, piece_size * 0.5, AppTheme.COASTER)
	draw_arc(center, piece_size * 0.5, 0.0, TAU, 40, Color(AppTheme.GOLD, 0.7), 2.0, true)
	PieceRenderer.draw_piece(self, piece, center, piece_size * 0.74)

	var text_x := pad + piece_size + 14.0
	# Largura escrita, e não `-1`. Com `-1` o texto passa por baixo da seta e sai
	# pela borda do cartão sem que nada acuse — e a linha de baixo ganhou um
	# apelido escolhido por outra pessoa, que é justamente o pedaço cujo tamanho
	# esta tela não controla.
	var text_width := maxf(40.0, size.x - text_x - 34.0)
	draw_string(
		AppTheme.display(900), Vector2(text_x, size.y * 0.5 - 2.0), _title().to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, text_width, 19, AppTheme.TEXT
	)
	draw_string(
		AppTheme.font(400), Vector2(text_x, size.y * 0.5 + 19.0), _detail(),
		HORIZONTAL_ALIGNMENT_LEFT, text_width, 14, AppTheme.TEXT_DIM
	)

	# Seta discreta à direita: diz "isto leva a algum lugar" sem competir com o
	# texto, e é o mesmo vocabulário de lista do resto do app.
	var arrow := Vector2(size.x - 26.0, size.y * 0.5)
	draw_polyline(
		PackedVector2Array([
			arrow + Vector2(-4.0, -7.0), arrow + Vector2(4.0, 0.0), arrow + Vector2(-4.0, 7.0)
		]),
		AppTheme.TEXT_DIM, 2.0, true
	)


## O nome sai do catálogo, e não de uma lista de `if`s aqui: era `chess` ou
## `Damas`, e batalha naval — que só existe em rede, e portanto só aparece nesta
## lista — se anunciava como xadrez.
##
## Jogo sem relógio não mostra ritmo: anunciar "Damas • Sem relógio" seria
## informar uma ausência que vale para todas as partidas de damas, e ocupar
## espaço para não dizer nada.
func _title() -> String:
	var name := str(Game.entry_of(game_id).get("title", "Partida"))
	if not Game.supports_clock(game_id) or clock_label.is_empty():
		return name
	return "%s • %s" % [name, clock_label]


## A lotação só aparece onde ela é uma pergunta. Numa sala de dois, "1/2" diz o
## que a existência da sala na lista já disse — ela está esperando alguém. Numa
## de quatro, é a diferença entre entrar agora e esperar mais dois.
## Quem abriu vem **primeiro**, quando há quem.
##
## É a informação que decide de verdade: numa lista de salas do mesmo jogo, um
## código de seis letras não diferencia nada, e quem procura partida escolhe pela
## pessoa antes de escolher pelo ritmo. O resto da linha continua na ordem de
## antes — o apelido entra na frente porque quem lê a linha para no primeiro
## campo que reconhece.
##
## Com apelido, a linha fica em **dois campos**, e o segundo é o que aquela sala
## tem a dizer: numa mesa grande, quantos lugares ainda faltam; numa de dois, há
## quanto tempo ela espera. Três campos não cabem — um apelido no limite empurra
## o último para fora e ele é cortado no meio de uma palavra, que é pior que
## ausente.
##
## O que sai é o menos útil de cada caso. Na sala de dois é o código: ele está
## ali para ser digitado, e ninguém digita um código que já pode tocar.
func _detail() -> String:
	if watchers >= 0:
		var who := host_name if not host_name.is_empty() else "código %s" % code
		return "%s • %d assistindo" % [who, watchers] if watchers > 0 else "%s • ao vivo" % who
	if seats > 2:
		var table := "%d de %d jogadores" % [taken, seats]
		if host_name.is_empty():
			return "%s • %s" % [table, _age_text()]
		return "%s • %s" % [host_name, table]
	if host_name.is_empty():
		return "código %s • %s" % [code, _age_text()]
	return "%s • %s" % [host_name, _age_text()]


## Minutos bastam. Uma sala aberta há 3 minutos e uma aberta há 3 minutos e meio
## são a mesma coisa para quem está escolhendo com quem jogar.
func _age_text() -> String:
	if age_seconds < 60:
		return "agora mesmo"
	var minutes := age_seconds / 60
	if minutes < 60:
		return "há %d min" % minutes
	return "há %d h" % (minutes / 60)
