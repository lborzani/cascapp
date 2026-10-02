class_name RelayBridge
extends Node

## Transporte pela internet: os dois aparelhos discam para um relay comum e
## conversam por ele.
##
## É o único caminho que funciona quando os jogadores não estão na mesma rede —
## um no Wi-Fi de casa, o outro no 4G. ENet direto exige rota IP entre os dois, e
## em rede móvel ambos estão atrás de CGNAT: nenhum aceita conexão de entrada.
## Discar para fora é a única direção que sempre passa.
##
## O código de 6 caracteres é o nome da sala. O servidor não conhece xadrez:
## ele emparelha dois sockets e repassa bytes. O par de mensagens do jogo viaja
## dentro de `{"t":"msg","d":…}` e o protocolo em `autoload/net_link.gd` é o
## mesmo dos outros transportes.
##
## Reconexão é requisito, não enfeite: em rede móvel o socket morre a cada
## troca de célula, de Wi-Fi para dados, ou quando a tela apaga. A sala fica de
## pé no servidor por 90s e este nó reconecta sozinho dentro dessa janela.
##
## ## A sala tem N assentos
##
## Eram dois, com nome de papel (`host`/`guest`), e isso bastava enquanto todo
## jogo do catálogo tinha dois jogadores. O Ludo tem quatro. Agora quem abre
## declara a **capacidade** e cada jogador recebe um **índice** de assento; o 0
## é quem abriu, e continua sendo quem manda o `welcome` do lado do jogo.
##
## Os sinais carregam o assento junto, porque "o outro" deixou de existir: com
## quatro na sala, saber que **alguém** chegou não diz o suficiente para
## qualquer decisão que dependa de quem é.
##
## A **chave do assento** vem do servidor no `joined` e volta no `join` da
## reconexão. Ela não protege a sala — o segredo da sala é o código —, ela
## responde "qual assento era o meu", pergunta que com dois lugares tinha
## resposta óbvia e com quatro não tem.

## O assento de quem chegou ou saiu. Com dois jogadores isto era um sinal sem
## argumento, porque só havia um outro possível.
## Sentamos: nosso assento e o tamanho da mesa, confirmados pelo servidor. Vem
## também em cada reconexão, com o mesmo assento — é o que permite à camada de
## cima saber quem ela é sem guardar nada entre quedas.
signal seated(seat: int, capacity: int)
signal peer_present(seat: int)
## Alguém **chegou** agora, com a sala já de pé. Diferente de `peer_present`, que
## também é emitido para quem já estava sentado quando este aparelho entrou.
##
## A diferença importa no meio da partida: receber quem volta é uma resposta a
## uma chegada. Tratado como `peer_present`, um aparelho que só perdeu o Wi-Fi
## por um segundo "receberia" os três que nunca saíram, com a lista de máquinas
## que ele tinha antes de cair — e desfaria os bots que os outros criaram
## enquanto ele estava fora.
signal peer_arrived(seat: int)
signal peer_gone(seat: int)
signal message_received(message: Dictionary, from_seat: int)
## Entramos para **assistir**: a sala existe, mas não temos assento nela. Vem
## também a cada reconexão do espectador.
signal watching(game_id: String, capacity: int)
## Quantos espectadores a sala tem agora. Chega aos **jogadores**: a cada entrada
## ou saída de quem assiste, e no `joined` de quem volta de uma queda.
signal watchers_changed(count: int)
signal failed(reason: String)
signal state_changed(state: State)

enum State {
	OFFLINE,
	## Abrindo o socket pela primeira vez.
	CONNECTING,
	## Na sala, esperando os outros jogadores chegarem.
	WAITING,
	## A sala está cheia: todos os assentos ocupados.
	LINKED,
	## O socket caiu e estamos tentando voltar para a mesma sala.
	RECONNECTING,
}

## Faixa que o servidor aceita (`MIN_SEATS`/`MAX_SEATS` em `relay/src/protocol.ts`).
const MIN_SEATS := 2
const MAX_SEATS := 6

## Trocar aqui depois do deploy (veja `relay/README.md`).
const DEFAULT_URL := "wss://chess-checkers-relay.fly.dev/ws"
## Para desenvolvimento: `CHESS_RELAY_URL=ws://192.168.0.10:8080/ws godot --path .`
## Use o IP da máquina na rede, não `localhost` — o celular precisa alcançá-lo.
const URL_ENV := "CHESS_RELAY_URL"

## Generoso de propósito: em rede móvel ruim o aperto de mão TLS passa dos 5s, e
## uma plataforma que hiberna no free tier cobra o cold start nesta primeira
## conexão.
const CONNECT_TIMEOUT := 12.0
const PING_INTERVAL := 20.0
## Quanto tempo o socket fica aberto depois do `leave`, só para empurrá-lo para a
## rede. Poucos quadros — imperceptível para quem sai, e a diferença entre a
## cadeira ser devolvida agora ou quando o TCP morrer sozinho.
const FLUSH_LIMIT := 0.12
## Silêncio maior que isso é link morto. TCP em rede móvel não avisa que caiu:
## o socket fica aberto para sempre mandando pacotes para o nada, então quem
## percebe a queda é a ausência de `pong`, não o sistema operacional.
const STALE_AFTER := 45.0
## Espera progressiva. A primeira tentativa é quase imediata porque a maioria
## das quedas é uma troca de rede que já terminou.
const RETRY_DELAYS: Array[float] = [0.5, 2.0, 4.0, 8.0, 15.0]
## Mesma carência da sala no servidor: insistir além disso é prometer uma
## reconexão que o outro lado já não pode aceitar.
const GIVE_UP_AFTER := 90.0

## Código de fechamento que o servidor usa para recusar (`fail()` em
## `relay/src/server.ts`). Fechamento com este código não é queda de rede: é
## resposta, e não se insiste numa resposta.
const CLOSE_POLICY := 1008

## O servidor manda um motivo em código; a tradução para o jogador mora aqui,
## do lado que sabe o que o jogador estava tentando fazer.
const ERROR_TEXT := {
	"room_taken": "Já existe uma partida com esse código. Volte e gere outro.",
	"room_not_found": "Nenhuma partida on-line com esse código.",
	"room_full": "Essa partida já está cheia.",
	"too_many_rooms": "O servidor está cheio agora. Tente de novo em alguns minutos.",
	"rate_limited": "Mensagens demais; a conexão foi encerrada.",
	"hello_timeout": "O servidor encerrou a conexão antes do pareamento.",
	"bad_code": "Código de sala inválido.",
	"bad_seats": "Número de jogadores fora do que o servidor aceita.",
	"not_in_room": "Erro de protocolo com o servidor.",
	"watch_full": "Essa partida já tem espectadores demais.",
}

var url := DEFAULT_URL

var _socket: WebSocketPeer = null
var _state := State.OFFLINE
var _room := ""
var _game := ""
## "host", "join" ou "watch": reenviado a cada reconexão para reocupar o mesmo
## lugar — o assento, ou a vaga de espectador.
var _role := ""
var _listed := false
## Apelido de quem abriu, para a lista pública. O servidor limpa o que chega —
## este campo é o que **nós** dizemos, não o que confiamos.
var _host_name := ""
var _time_control := 0
var _want_link := false
## Capacidade pedida ao abrir; o servidor confirma no `joined`.
var _capacity := MIN_SEATS
## Nosso assento, e o segredo que o traz de volta depois de uma queda. A chave
## é guardada entre reconexões de propósito — é para isso que ela existe.
var _seat := -1
var _key := ""
## Assentos ocupados agora, incluindo o nosso.
var _present := PackedInt32Array()

## Contando os quadros da despedida, ou -1 fora dela. Ver [method _flush_despedida].
var _flush_timer := -1.0
var _hello_sent := false
var _retry_index := 0
var _retry_timer := 0.0
var _connect_timer := 0.0
var _ping_timer := 0.0
var _silence_timer := 0.0
var _down_timer := 0.0
## O motivo da última recusa do servidor, como ele mandou (`room_not_found`,
## `room_full`…), ou vazio. O texto do `failed` é para gente ler; quem precisa
## **decidir** algo com a recusa — esquecer uma partida que já acabou — lê isto.
var _refusal := ""


func _ready() -> void:
	var override := OS.get_environment(URL_ENV)
	if not override.is_empty():
		url = override
	set_process(false)


func state() -> State:
	return _state


func is_linked() -> bool:
	return _state == State.LINKED


## Nosso lugar na mesa, ou -1 antes de sentar. O assento 0 é quem abriu a sala.
func seat() -> int:
	return _seat


## A chave do nosso assento, ou vazio antes de sentar. É o que o app guarda para
## voltar à mesma cadeira depois de o processo morrer.
func seat_key() -> String:
	return _key


func refusal() -> String:
	return _refusal


## Código da sala em que este socket está. A tela de espera mostra: quem digitou
## seis letras que chegaram por mensagem quer ver de volta que foi essa a sala.
func room_code() -> String:
	return _room


func capacity() -> int:
	return _capacity


func present_seats() -> PackedInt32Array:
	return _present


func seats_taken() -> int:
	return _present.size()


## Falso quando o build não tem relay configurado, para a UI poder dizer isso em
## vez de mostrar uma tentativa que nunca vai conectar.
func is_configured() -> bool:
	return not url.is_empty()


## `listed` põe a sala na lista pública; `time_control` viaja junto só para a
## lista poder mostrar o ritmo antes de alguém entrar. `seats` é a capacidade da
## mesa, e quem abre é quem decide — ela não muda depois, porque é o que os
## outros estão entrando para jogar.
## `host_name` é o apelido de quem abre, e só serve à lista pública: numa sala
## privada ele viaja e o servidor nunca o publica. Vai no `host` e não numa
## mensagem posterior porque a sala já nasce na lista — anunciar o nome depois
## deixaria a sala aparecendo sem dono pelos primeiros segundos, que são
## justamente os em que alguém a vê no topo.
func host_room(
	code: String,
	game_id: StringName,
	listed := false,
	time_control := 0,
	seats := MIN_SEATS,
	host_name := ""
) -> void:
	_listed = listed
	_time_control = time_control
	_capacity = clampi(seats, MIN_SEATS, MAX_SEATS)
	_host_name = host_name
	_start("host", code, String(game_id))


## `key` é a chave de um assento que este aparelho já ocupou nesta sala — guardada
## em disco quando a partida abriu. Com ela o servidor devolve **aquele** assento;
## sem ela, o primeiro livre. Vai depois do `_start`, que zera a chave anterior.
func join_room(code: String, key := "") -> void:
	_start("join", code, "")
	_key = key


## Entra para assistir. Sem chave: espectador não tem assento a reocupar, e a
## reconexão só pede de novo para assistir à mesma sala.
func watch_room(code: String) -> void:
	_start("watch", code, "")


## Endereço HTTP derivado do de WebSocket: os dois são o mesmo servidor, e ter
## duas configurações para um endereço só é uma para sair de sincronia.
func rooms_url() -> String:
	if url.is_empty():
		return ""
	var base := url.replace("wss://", "https://").replace("ws://", "http://")
	return base.trim_suffix("/ws") + "/rooms"


## Partidas públicas em andamento, para quem quer assistir.
func live_url() -> String:
	return rooms_url().trim_suffix("/rooms") + "/live" if is_configured() else ""


## Espectador não fala. O servidor já descarta o que ele mandar; recusar aqui
## também garante que nem um bug da camada de cima ponha na rede um `sync` ou
## um `bye` de quem só assiste.
func send(message: Dictionary) -> void:
	if _role == "watch":
		return
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify({"t": "msg", "d": message}))


func leave() -> void:
	_want_link = false
	_room = ""
	_role = ""
	# A chave morre com a sala: guardá-la depois de sair faria a próxima entrada
	# pedir um assento de uma partida que já acabou.
	_key = ""
	_seat = -1
	_present = PackedInt32Array()
	# Sair **avisando o servidor**, e não só fechando o socket.
	#
	# O `leave` do protocolo devolve a cadeira na hora: o servidor libera o
	# assento e manda `peer_left` para os outros. Fechar o socket faz a mesma
	# coisa — mas só quando o fechamento chega, e ele pode não chegar tão cedo.
	# `close()` inicia um aperto de mão que precisa de `poll()` para sair, e a
	# linha seguinte desta função desliga o processamento: num celular o servidor
	# ficava esperando o TCP morrer sozinho, e até lá a sala continuava contando
	# alguém que já tinha desistido.
	#
	# Sintoma do outro lado: "Aguardando: 2 de 4 jogadores" numa sala com um.
	#
	# O `bye` da camada de cima continua indo antes deste, e são coisas
	# diferentes: aquele diz "não me esperem de volta" para a **partida**, este
	# diz "a cadeira é de vocês" para o **servidor**.
	# A saída é anunciada na hora; o socket fecha alguns quadros depois.
	_set_state(State.OFFLINE)
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify({"t": "leave"}))
		# Um `poll()` só **não basta**. `send_text` enfileira; quem escreve na rede
		# é o `poll`, e uma escrita parcial de TLS precisa de mais de um. Fechando
		# no mesmo fôlego, o `leave` era descartado e a cadeira só era devolvida
		# quando o TCP morresse sozinho — no celular, uns dois segundos.
		#
		# O nó sobrevive à troca de tela (mora no autoload `Pairing`), então
		# continuar processando por um instante é seguro. É a única função do app
		# que fecha devagar de propósito.
		_flush_timer = 0.0
		set_process(true)
		return
	_close_socket()
	set_process(false)


# --- ciclo de vida do socket -------------------------------------------------


func _start(role: String, code: String, game_id: String) -> void:
	leave()
	_refusal = ""
	if not is_configured():
		failed.emit("Servidor de partidas on-line não configurado neste build.")
		return
	_role = role
	_room = code.to_upper()
	_game = game_id
	_want_link = true
	_retry_index = 0
	_down_timer = 0.0
	_set_state(State.CONNECTING)
	set_process(true)
	_open_socket()


func _open_socket() -> void:
	_close_socket()
	_socket = WebSocketPeer.new()
	var error := _socket.connect_to_url(url)
	if error != OK:
		_socket = null
		_drop("Não foi possível abrir a conexão com o servidor (erro %d)." % error)
		return
	_hello_sent = false
	_connect_timer = 0.0
	_ping_timer = 0.0
	_silence_timer = 0.0
	# Cancela uma despedida em curso. Sem isto, entrar noutra sala logo depois de
	# sair de uma deixaria o temporizador da anterior fechando o socket **novo**
	# um décimo de segundo depois de ele abrir — e o sintoma seria uma entrada que
	# falha só quando se é rápido.
	_flush_timer = -1.0


func _close_socket() -> void:
	if _socket != null:
		_socket.close()
		_socket = null


func _process(delta: float) -> void:
	if _flush_timer >= 0.0:
		_flush_despedida(delta)
		return
	if _socket == null:
		_tick_retry(delta)
		return

	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		_connect_timer += delta
		if _connect_timer > CONNECT_TIMEOUT:
			_drop("O servidor de partidas não respondeu.")
		return
	if state == WebSocketPeer.STATE_OPEN:
		_tick_open(delta)
		return

	# Fechando ou fechado. O servidor manda o motivo e fecha no mesmo fôlego
	# (`{"t":"error"}` seguido de `close`), então a recusa já está na fila quando
	# chegamos aqui — e ignorá-la era o que transformava "nenhuma partida com
	# esse código" em "conexão instável" e noventa segundos de retentativa.
	_drain()
	if _socket == null:
		return
	if state == WebSocketPeer.STATE_CLOSED:
		_on_socket_closed()


## Recusa do servidor: sala inexistente, sala cheia, código inválido. O motivo
## viaja também no código de fechamento, então mesmo que o frame de erro se
## perca dá para dizer o que houve — e, sobretudo, para **não** insistir.
## Repetir a mesma pergunta a cada meio segundo por um minuto e meio só rende a
## mesma resposta.
func _on_socket_closed() -> void:
	var reason := _socket.get_close_reason()
	if _socket.get_close_code() == CLOSE_POLICY:
		_refusal = reason
		_want_link = false
		_close_socket()
		set_process(false)
		_set_state(State.OFFLINE)
		failed.emit(ERROR_TEXT.get(reason, "O servidor recusou a conexão (%s)." % reason))
		return
	_drop("A conexão com o servidor caiu.")


## Empurra o `leave` para a rede e só então fecha.
##
## Custa alguns quadros e devolve a cadeira imediatamente do lado do servidor —
## que é o que a tela de quem abriu a sala está esperando para dizer "1 de 4".
##
## É um tempo fixo, e não uma espera pela fila esvaziar: `WebSocketPeer` não conta
## de forma confiável o que ainda falta sair, e alguns quadros de `poll` são o
## bastante para uma escrita local. O teto vale também para o caso em que a rede
## já caiu e o `leave` não vai sair de jeito nenhum — ali insistir seria segurar
## um socket morto.
func _flush_despedida(delta: float) -> void:
	_flush_timer += delta
	if _socket != null:
		_socket.poll()
	if _flush_timer < FLUSH_LIMIT:
		return
	_flush_timer = -1.0
	_close_socket()
	set_process(false)


func _drain() -> void:
	while _socket != null and _socket.get_available_packet_count() > 0:
		_silence_timer = 0.0
		var text := _socket.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_handle(parsed)
		else:
			push_warning("Mensagem do relay ilegível: %s" % text)


func _tick_open(delta: float) -> void:
	# O hello é reenviado a cada abertura, inclusive nas reconexões: é ele que
	# reocupa o assento na sala que o servidor manteve de pé.
	if not _hello_sent:
		_send_hello()

	_drain()
	if _socket == null:
		return

	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		_socket.send_text(JSON.stringify({"t": "ping"}))

	_silence_timer += delta
	if _silence_timer > STALE_AFTER:
		# Sem `pong` há tempo demais. O socket ainda se diz aberto, mas não está.
		_drop("Sem resposta do servidor.")


func _send_hello() -> void:
	if _role == "host":
		_socket.send_text(JSON.stringify({
			"t": "host",
			"room": _room,
			"game": _game,
			"listed": _listed,
			"tc": _time_control,
			"seats": _capacity,
			"name": _host_name,
		}))
	elif _role == "watch":
		_socket.send_text(JSON.stringify({"t": "watch", "room": _room}))
	else:
		# A chave só existe a partir da segunda entrada, e é ela que devolve o
		# mesmo assento. Sem ela o servidor senta quem chega no primeiro livre —
		# certo na primeira vez, errado numa mesa com dois buracos abertos.
		_socket.send_text(JSON.stringify({"t": "join", "room": _room, "key": _key}))
	_hello_sent = true
	_set_state(State.WAITING)


func _handle(message: Dictionary) -> void:
	match str(message.get("t", "")):
		"joined":
			_retry_index = 0
			_down_timer = 0.0
			_seat = int(message.get("seat", 0))
			_capacity = int(message.get("seats", MIN_SEATS))
			_key = str(message.get("key", ""))
			var before := _present
			_present = PackedInt32Array(message.get("present", []))
			seated.emit(_seat, _capacity)
			_sync_state()
			watchers_changed.emit(int(message.get("watchers", 0)))
			# Quem já estava sentado quando chegamos. Numa reconexão a lista vem
			# igual à de antes e nada é anunciado duas vezes.
			for seat_index in _present:
				if seat_index != _seat and not before.has(seat_index):
					peer_present.emit(seat_index)
		"watching":
			_retry_index = 0
			_down_timer = 0.0
			_capacity = int(message.get("seats", MIN_SEATS))
			_present = PackedInt32Array(message.get("present", []))
			_sync_state()
			watching.emit(str(message.get("game", "")), _capacity)
		"watchers":
			watchers_changed.emit(int(message.get("n", 0)))
		"peer":
			var arriving := int(message.get("seat", -1))
			if arriving >= 0 and not _present.has(arriving):
				_present.append(arriving)
			_sync_state()
			peer_present.emit(arriving)
			peer_arrived.emit(arriving)
		"peer_left":
			# Alguém caiu, mas a sala continua de pé e ele pode voltar. Só a
			# camada de cima sabe se vale esperar ou encerrar a partida.
			var leaving := int(message.get("seat", -1))
			var at := _present.find(leaving)
			if at >= 0:
				_present.remove_at(at)
			_sync_state()
			peer_gone.emit(leaving)
		"msg":
			var payload: Variant = message.get("d")
			if payload is Dictionary:
				message_received.emit(payload, int(message.get("from", -1)))
		"pong":
			pass
		"error":
			var reason := str(message.get("reason", ""))
			_refusal = reason
			# Recusa do servidor não se resolve tentando de novo.
			_want_link = false
			set_process(false)
			_close_socket()
			_set_state(State.OFFLINE)
			failed.emit(ERROR_TEXT.get(reason, str(message.get("detail", "Erro no servidor."))))


## Ligado é **mesa cheia**, e não "tem mais alguém". Com dois assentos as duas
## definições coincidiam; com quatro, uma partida que começasse com três na sala
## seria uma partida que ninguém pediu.
func _sync_state() -> void:
	_set_state(State.LINKED if _present.size() >= _capacity else State.WAITING)


# --- reconexão ---------------------------------------------------------------


## Uma queda não é um erro enquanto a sala existir do outro lado. O jogo congela,
## o rótulo muda, e a partida continua de onde parou se conseguirmos voltar.
func _drop(reason: String) -> void:
	_close_socket()
	if not _want_link:
		_set_state(State.OFFLINE)
		set_process(false)
		return

	# A lista de presentes vale para a conexão que caiu; o servidor manda a
	# atual no `joined` da volta. A chave e o assento sobrevivem de propósito —
	# são eles que trazem de volta o mesmo lugar.
	_present = PackedInt32Array()
	_set_state(State.RECONNECTING)
	_retry_timer = RETRY_DELAYS[mini(_retry_index, RETRY_DELAYS.size() - 1)]
	_retry_index += 1
	push_warning("Relay: %s Tentando de novo em %.1fs." % [reason, _retry_timer])


func _tick_retry(delta: float) -> void:
	if not _want_link:
		set_process(false)
		return

	_down_timer += delta
	if _down_timer > GIVE_UP_AFTER:
		_want_link = false
		set_process(false)
		_set_state(State.OFFLINE)
		failed.emit("Não foi possível reconectar ao servidor de partidas.")
		return

	_retry_timer -= delta
	if _retry_timer <= 0.0:
		_open_socket()


func _set_state(next: State) -> void:
	if _state == next:
		return
	_state = next
	state_changed.emit(next)
