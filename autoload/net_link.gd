extends Node

## Autoload `Net`: o link entre os dois jogadores.
##
## Um caminho só: **a sala no relay** (`net/relay_bridge.gd`). Os dois aparelhos
## discam para fora, para um servidor comum, e o código de 6 caracteres é o nome
## da sala. Funciona de qualquer lugar com internet — um no Wi-Fi de casa, o
## outro no 4G — e é o único arranjo que atravessa NAT sem malabarismo.
##
## O que trafega é um dicionário por evento. Os dois aparelhos rodam o mesmo
## ruleset determinístico e validam cada lance recebido contra a própria lista de
## lances legais, então nenhum lado precisa confiar no tabuleiro do outro — nem
## no relay no meio, que por isso pode ser um servidor burro sem regra de jogo.
##
## **Houve outros dois caminhos, e os dois saíram.**
##
## O *Nearby Connections* ligava Bluetooth e Wi-Fi por conta própria — só de
## abrir a tela de entrar numa partida o Wi-Fi era ligado à força — e pedia
## permissão de localização. Um jogo de tabuleiro não justifica mexer nos rádios
## de quem está jogando.
##
## O *ENet sobre IP* ligava os dois aparelhos direto, com descoberta por UDP na
## rede local e um hotspot como reserva. Funcionava, e mesmo assim atrapalhava:
## quando o anfitrião aparecia na rede local, o convidado gastava três tentativas
## de conexão a endereços que o Wi-Fi doméstico costuma bloquear (isolamento de
## clientes) antes de chegar ao relay — e a tela relatava endereços IP, que não é
## o que alguém quer ler para entrar numa sala. Um caminho a mais só vale o preço
## quando alcança alguém que os outros não alcançam; este não alcançava.

signal opponent_joined(remote_side: int)
## A mesa encheu e todo mundo se apresentou. É o `opponent_joined` dos jogos de
## mais de dois: com quatro na sala, "o oponente chegou" não é um evento — o que
## importa é a mesa estar pronta, e quem começa é regra do jogo.
##
## Os dois existem porque respondem coisas diferentes: o de dois carrega a cor
## do outro, que é o que xadrez e damas precisam saber. Aqui a identidade de
## cada um é o próprio assento.
signal table_ready(seats: int)
signal opponent_left
## Um assento se desfez numa mesa de **mais de dois**, e a partida continua sem
## ele.
##
## É o `opponent_left` das mesas grandes, e existe porque aquele encerra a
## partida — o que numa mesa de seis significa que um 4G caindo acaba o jogo das
## outras cinco pessoas. Aqui a cadeira vira máquina e os que ficaram seguem
## jogando, que é a mesma saída que a sala oferece quando ela não enche.
##
## Numa mesa de dois não é emitido: lá não sobra mesa para continuar.
signal seat_left(seat: int)
## `data["seat"]` é **quem mandou**, carimbado pelo servidor.
##
## Vai junto porque a legalidade do lance não responde de quem ele é: numa mesa
## de quatro, um lance legal para o jogador da vez é legal olhando só o tabuleiro,
## venha ele de quem vier. Sem este campo, qualquer assento joga a vez de
## qualquer outro.
## Alguém se apresentou, e os cartões da mesa precisam ser repintados.
##
## Os nomes chegam **depois** da tela: quem entra anuncia o dele no `ready`, quem
## volta no `resumed`, e os dois podem cair no meio de uma partida já desenhada.
## Sem este aviso o cartão só se corrigia no lance seguinte — e numa mesa parada
## esperando alguém, nunca: era exatamente a hora em que se quer saber quem
## chegou.
##
## Sem argumento de propósito. Quem escuta redesenha a mesa inteira, que é o que
## faria de qualquer jeito — mandar o assento levaria cada tela a implementar uma
## atualização parcial para pintar quatro rótulos.
signal names_changed
## A lista de cadeiras de máquina mudou no meio da partida.
##
## Ela muda nos dois sentidos: uma cadeira **vira** máquina quando alguém some de
## vez ([method _drop_seat]), e **deixa** de ser quando um humano senta nela —
## o caso de quem entra numa sala que começou com bots, ou de quem volta depois
## de ter sido dado como perdido.
##
## As cenas guardam a própria cópia da lista, porque a consultam a cada tique de
## decisão. Sem este aviso a cópia envelhece: o jogador novo continua sendo jogado
## pela máquina, e o cartão dele continua escrito "(bot)" com uma pessoa sentada
## ali.
signal bots_changed
## Uma cadeira de máquina voltou a ser de gente: quem tinha caído voltou, ou
## alguém sentou numa mesa que começou com bots. Emitido depois de
## `bots_changed`, com a lista já atualizada — quem escuta lê o nome de gente, e
## não o do bot.
##
## É o par de `seat_left`. Sem ele, a volta era silenciosa: o cartão perdia o
## "(bot)" e ninguém na mesa ficava sabendo que a pessoa estava de volta.
signal seat_returned(seat: int)
signal move_received(data: Dictionary)
signal join_failed(reason: String)
## Revanche é convite, não ordem: quem pede espera, e quem recebe decide. Antes
## um toque em "Revanche" reiniciava a partida dos dois lados na hora, e o outro
## jogador era arrastado para um tabuleiro novo sem ter sido consultado.
signal rematch_requested
signal rematch_accepted
signal rematch_declined
## O transporte caiu mas a sessão ainda pode voltar. O tabuleiro deve congelar e
## dizer isso, não declarar a partida encerrada.
signal link_lost
## De volta na mesma sessão. Os dois lados trocam a lista de lances em seguida.
signal link_restored
signal sync_received(moves: Array, clocks: Array)
## A frota do oponente, na batalha naval. Chega uma vez por partida, antes do
## primeiro tiro — e de novo depois de uma reconexão, porque ela não está na
## lista de lances e portanto o replay do `sync` não a reconstrói.
signal fleet_received(cells: PackedInt32Array)
## O anfitrião não conseguiu abrir a sala. Sem sala o código na tela não leva a
## lugar nenhum, então isto é fatal para a partida — e quem precisa saber é quem
## tentou abrir.
signal relay_unavailable(reason: String)

const HOST_SIDE := Board.Side.WHITE

## Um pouco além da carência da sala no servidor (90s). Se o outro lado não
## voltou até aqui, a sala já não o espera mais, e continuar dizendo
## "reconectando" seria prometer uma volta que o servidor não pode entregar.
##
## É a rede de segurança do `bye`: quem sai avisa, mas quem tem o app encerrado
## pelo sistema, fica sem bateria ou perde a rede de vez não avisa nada.
##
## Só numa mesa de **dois**. Numa maior não há espera a limitar: a cadeira de quem
## some vira máquina na hora (ver [method _on_relay_peer_gone]).
const ABSENCE_LIMIT := 95.0

## Teto de lances num `sync` recebido. A partida mais longa que este app produz —
## Metrópole até a falência, com seis — não passa de alguns milhares de linhas de
## histórico, e cada uma é revalidada e reaplicada do outro lado.
const SYNC_LIMIT := 20000

var is_host := false
var connected := false
var local_side := Board.Side.WHITE
## Nosso lugar na mesa (0 é quem abriu) e quantos lugares ela tem.
##
## Num jogo de dois, o assento **é** a cor: 0 joga de brancas. Num de quatro, o
## assento é a identidade inteira — a cor do Ludo é o próprio índice —, e
## `local_side` deixa de significar alguma coisa. Por isso os dois campos
## convivem em vez de um tentar servir aos dois casos.
var local_seat := 0
var seats := 2
## Assentos que uma máquina joga: os que ninguém ocupou quando quem abriu começou
## sem esperar a mesa encher, e os de quem caiu numa mesa de mais de dois, até ele
## voltar. A lista viaja no `welcome` e no `resume` — todo mundo precisa saber
## quais cores são de máquina, e **quem** as joga tem de ser um aparelho só.
##
## Esse aparelho é o menor assento humano ([method bot_driver]). Dois aparelhos
## rolando o dado do mesmo bot dariam dois lances diferentes para a mesma vez, e
## as partidas divergem no primeiro deles.
var bot_seats := PackedInt32Array()
var game_id := &"chess"
## Índice em `Game.TIME_CONTROLS`. O anfitrião preenche antes de abrir a sala e o
## convidado recebe no `welcome`: dois relógios diferentes não seriam a mesma
## partida, então esta é a única resposta possível.
var time_control := 0
## Um número por jogo, decidido por quem abre e entregue a todos no `welcome`.
##
## Hoje é o limite de rodadas de Metrópole, que é o que separa uma partida de
## meia hora de uma de três — e duas mesas com limites diferentes não seriam a
## mesma partida, exatamente como dois relógios diferentes.
##
## Genérico de propósito, e sem nome de jogo: este arquivo não conhece jogo
## nenhum, e o dia em que outro precisar de um número seu, o campo já existe. O
## que ele **não** é é um canal de configuração — uma segunda coisa a sincronizar
## seria uma segunda coisa que pode chegar errada, e a partida em si continua
## viajando inteira dentro dos lances.
var option := 0

## Histórico que chegou antes de existir tela para recebê-lo. Ver o tratador de
## `sync` e [method claim_sync].
var _pending_sync := {}

var _expected_code := ""
var _relay_wired := false
var _relay: RelayBridge = null
## Verdadeiro depois que os dois lados completaram um aperto de mão. Uma
## reconexão posterior retoma a mesma partida em vez de começar outra.
var _session_started := false
## O oponente foi embora para valer. Impede que a ausência seja anunciada duas
## vezes — pelo `bye` e depois pelo `peer_left` que vem logo atrás dele.
var _opponent_gone := false
## Invalida a contagem de ausência em curso. Cada sumiço abre uma contagem nova;
## a volta do oponente, ou uma saída nossa, descarta a que estava correndo.
var _absence_token := 0
## Assentos que já responderam ao `welcome`. Só o assento 0 usa: é ele que sabe
## quando a mesa inteira está pronta. Num jogo de dois isto tem um elemento e a
## conta é a mesma de sempre.
var _ready_seats := {}


## Resolvido por caminho, e não pelo identificador do autoload `Pairing`: este
## script precisa compilar onde autoloads não existem, como o runner headless.
##
## Um filho direto ganha do autoload. É assim que os testes headless levantam
## dois links no mesmo processo — `/root/Pairing` é um nó só e serviria a um.
func _relay_bridge() -> RelayBridge:
	if _relay == null:
		_relay = get_node_or_null("RelayBridge") as RelayBridge
	if _relay == null:
		_relay = get_node_or_null("/root/Pairing/RelayBridge") as RelayBridge
	return _relay


## Sair avisa antes de fechar. Um socket que simplesmente some é indistinguível
## de uma queda de rede, e o outro lado ficaria em "reconectando" esperando uma
## volta que não vem — foi exatamente esse o sintoma: quem ficava na partida
## nunca via "o oponente saiu".
func leave() -> void:
	if connected:
		_send_direct({"t": "bye"})
	_close_relay()
	is_host = false
	connected = false
	_session_started = false
	_opponent_gone = false
	_absence_token += 1
	_expected_code = ""
	_ready_seats = {}
	player_names = {}
	_pending_sync = {}


## `clocks` é `[brancas, pretas]` em segundos, ou vazio sem relógio.
##
## Os dois relógios viajam, não só o de quem jogou, e isso é exatamente certo: o
## lado que **não** está para jogar não correu em nenhum dos dois aparelhos desde
## a última troca, então a cópia que o adversário tem dele está atual. Uma
## mensagem por lance zera a deriva dos dois.
func send_move(data: Dictionary, index: int, clocks: Array = []) -> void:
	# `n` é o índice do lance na partida. Torna o lance idempotente, que é o que
	# impede uma reconexão de reaplicar um lance que o outro lado já tem.
	_send({
		"t": "move",
		"p": Array(data.get("p", [])),
		"pr": data.get("pr", 0),
		"n": index,
		"c": clocks,
	})


## O mar posicionado, casa a casa.
##
## Mandar a frota inteira dá ao adversário a informação que o jogo esconde, e
## isso é aceito de propósito: é o **desenho** que esconde, não o modelo. A
## alternativa — guardar o segredo de verdade e responder tiro a tiro "acertou" —
## obrigaria a confiar na resposta do outro lado, que é uma porta bem maior para
## trapaça do que um cliente modificado que espia. E quebraria a reconexão, que
## reconstrói a partida repetindo lances em cima de uma posição conhecida.
func send_fleet(cells: PackedInt32Array) -> void:
	_send({"t": "fleet", "f": Array(cells)})


func send_rematch() -> void:
	_send({"t": "rematch"})


func send_rematch_accept() -> void:
	_send({"t": "rematch_ok"})


func send_rematch_decline() -> void:
	_send({"t": "rematch_no"})


## A lista de lances inteira, mandada pelos dois lados depois de uma reconexão.
## Quem estiver atrás replaya a diferença; os dois rodam o mesmo ruleset
## determinístico, então a posição é reconstruída em vez de transferida.
func send_sync(moves: Array, clocks: Array = []) -> void:
	_send({"t": "sync", "m": moves, "c": clocks})


## Puxa o histórico que chegou cedo demais, se houver.
##
## Toda cena de partida chama isto **depois** de se ligar em `sync_received` e de
## montar o próprio estado inicial. É a outra metade da correção de quem entra
## numa partida em curso: sem ela o histórico chega antes da cena e some, e o
## recém chegado joga um tabuleiro no início contra três que estão no meio.
func claim_sync() -> void:
	if _pending_sync.is_empty():
		return
	var pending := _pending_sync
	_pending_sync = {}
	sync_received.emit(pending["m"], pending["c"])


func _send(message: Dictionary) -> void:
	if not connected:
		return
	_send_direct(message)


## Usado também durante o aperto de mão, antes de `connected` valer.
func _send_direct(message: Dictionary) -> void:
	if _relay_bridge() != null:
		_relay_bridge().send(message)


## Ponto único do protocolo.
##
## `from_seat` vem do servidor, não da mensagem: o relay carimba o remetente ao
## repassar (`relay_bridge.gd`), então ele é a única coisa aqui que um cliente
## modificado não consegue forjar. É por isso que ele viaja adiante em vez de
## ser descartado.
func _handle_message(message: Dictionary, from_seat: int) -> void:
	match str(message.get("t", "")):
		"welcome":
			_on_welcome(message)
		"ready":
			# O assento vem do **servidor** e não da mensagem: o campo `seat` que o
			# convidado manda serve à contagem do aperto de mão, mas guardar o nome
			# por ele deixaria qualquer um renomear o vizinho.
			_remember_name(from_seat, message.get("name"))
			_on_ready(int(message.get("seat", 1)))
		"resume":
			# A lista inteira vem de volta: quem reabriu o app perdeu os nomes que
			# aprendeu, e o `resume` é o único aperto de mão que ele vê.
			_remember_names(message.get("names"))
			# O relay entrega a mesma mensagem à mesa inteira, e quem responde é só
			# quem voltou: um `resumed` de quem nunca saiu faria quem recebeu mandar
			# o histórico inteiro uma vez por aparelho da mesa.
			if not _session_started:
				# Nunca esteve nesta partida — ou esteve, e o processo morreu. Para ele
				# o `resume` **é** o convite, e a tela de entrar só sai do lugar com o
				# `table_ready`.
				_mark_connected()
				_send_direct({"t": "resumed", "name": player_name})
				_adopt_table(message)
				if seats == 2:
					opponent_joined.emit(Board.opponent(local_side))
				else:
					table_ready.emit(seats)
			elif not connected:
				# Caiu e voltou com a partida em memória: o `resume` é o aviso de que
				# o link voltou, mais a lista de máquinas, que mudou enquanto ele
				# estava fora.
				_mark_connected()
				_send_direct({"t": "resumed", "name": player_name})
				_adopt_bots(message)
				link_restored.emit()
			else:
				# Outro assento voltou. Daqui só muda quem é máquina — e quem dirige
				# os bots precisa saber para parar de jogar por uma cadeira que
				# acabou de receber gente.
				_adopt_bots(message)
		"resumed":
			# O nome é de todos: quem voltou se apresenta à mesa inteira, e não só a
			# quem o recebeu.
			_remember_name(from_seat, message.get("name"))
			# O histórico sai de quem recebeu, e de mais ninguém.
			if _session_started and _greeter(from_seat) == local_seat:
				_mark_connected()
				link_restored.emit()
		"move":
			move_received.emit({
				"p": _packed(message.get("p")),
				"pr": int(message.get("pr", 0)),
				"n": int(message.get("n", -1)),
				"c": _list(message.get("c")),
				"seat": from_seat,
			})
		"sync":
			var history := _list(message.get("m"))
			# Teto no histórico recebido. Ele é replayado lance a lance do outro
			# lado, e uma lista de um milhão de entradas trava o aparelho por
			# minutos — a partida mais longa possível não passa de alguns milhares.
			if history.size() > SYNC_LIMIT:
				push_warning("Histórico recebido grande demais (%d); ignorado." % history.size())
				return
			var clocks := _list(message.get("c"))
			# Guardado quando ainda não há tela para receber.
			#
			# Quem entra numa partida em curso responde o `resume` na hora, e o
			# anfitrião devolve o histórico em poucos milissegundos — antes de a
			# cena da partida existir, porque ela só é montada depois do
			# `table_ready`. Emitido no vazio, o histórico se perdia e o recém
			# chegado abria um tabuleiro no início enquanto os outros jogavam.
			if sync_received.get_connections().is_empty():
				_pending_sync = {"m": history, "c": clocks}
				return
			sync_received.emit(history, clocks)
		"fleet":
			fleet_received.emit(_packed(message.get("f")))
		"rematch":
			rematch_requested.emit()
		"rematch_ok":
			rematch_accepted.emit()
		"rematch_no":
			rematch_declined.emit()
		"bye":
			_drop_seat(from_seat)


## Uma lista vinda da rede, ou vazia.
##
## O que chega aqui saiu de um `JSON.parse_string`, então o **tipo** de cada
## campo é escolha de quem mandou: um `"p"` que venha texto ou número faz a
## conversão direta virar erro de execução no meio do tratador de mensagem. Os
## dois converters abaixo existem só para isso — o conteúdo continua sendo
## conferido pelas regras do jogo, que é onde essa conferência pertence.
static func _list(value: Variant) -> Array:
	return Array(value) if value is Array else []


## Elemento a elemento, e não `PackedInt32Array(array)`: a conversão em bloco
## também é erro de execução quando **um** item não é número, e um lance com uma
## string no meio é exatamente o que um cliente adulterado manda. Lista suja
## inteira vira vazia, e as regras recusam a vazia como recusariam qualquer
## caminho impossível.
static func _packed(value: Variant) -> PackedInt32Array:
	var numbers := PackedInt32Array()
	for item in _list(value):
		if not (item is int or item is float):
			return PackedInt32Array()
		numbers.append(int(item))
	return numbers


## Um assento se desfez para valer. Numa mesa de dois isso acaba a partida; numa
## mesa maior, a cadeira vira máquina e quem ficou continua jogando.
##
## A diferença não é de grau. `opponent_left` foi escrito quando toda sala tinha
## dois lugares, e aplicá-lo a uma mesa de seis significa que um 4G caindo acaba
## o jogo das outras cinco pessoas — que é o que acontecia até aqui, porque o
## assento de quem sumiu chegava e era descartado.
## Tira uma cadeira da lista de máquinas. É o inverso de [method _drop_seat], e
## acontece quando um humano senta nela.
func _release_bot_seat(seat: int) -> void:
	var at := bot_seats.find(seat)
	if at < 0:
		return
	bot_seats.remove_at(at)
	bots_changed.emit()
	seat_returned.emit(seat)


func _drop_seat(seat: int) -> void:
	if seats <= 2:
		_end_session()
		return
	if seat < 0 or bot_seats.has(seat):
		return
	bot_seats.append(seat)
	# A sessão **não** cai: os outros continuam. E `connected` volta, porque a
	# ausência tinha congelado a mesa esperando uma volta que não veio.
	connected = true
	# `seat_left` **antes** de `bots_changed`. Quem escuta os dois guarda a própria
	# cópia da lista e a relê no `bots_changed`; na ordem inversa o aviso de saída
	# já lia a cadeira como máquina e dizia "Jogador 3 (bot) saiu".
	seat_left.emit(seat)
	bots_changed.emit()


## Este aparelho é o que joga pelos bots: o **menor assento que ainda é humano**.
##
## Era "o assento 0, sempre", e isso deixou de bastar quando um assento pode
## virar máquina no meio da partida — se quem sai é o 0, ninguém sobra para rolar
## o dado das máquinas e a mesa para de andar sozinha.
##
## Continua sendo um aparelho só, que é o que importa: dois rolando o dado do
## mesmo bot dariam dois lances para a mesma vez.
func bot_driver() -> int:
	for seat in seats:
		if not bot_seats.has(seat):
			return seat
	return 0


func drives_bots() -> bool:
	return local_seat == bot_driver()


## O oponente foi embora e não volta. Diferente de `link_lost`, que congela o
## tabuleiro esperando uma reconexão.
func _end_session() -> void:
	if _opponent_gone:
		return
	_opponent_gone = true
	connected = false
	_absence_token += 1
	opponent_left.emit()


func _mark_connected() -> void:
	connected = true
	_session_started = true


## Tudo o que os outros precisam para jogar a mesma partida: qual jogo, quantos
## são e em que ritmo.
##
## `side` continua indo, e só é lido em mesa de dois: lá o assento e a cor são a
## mesma coisa dita de duas formas, e quem recebe usa a que já usava. Numa mesa
## de quatro a cor de cada um é o próprio assento, e um campo com uma cor só não
## teria como responder pelos três.
func _welcome() -> Dictionary:
	return {
		"t": "welcome",
		"code": _expected_code,
		"game": String(game_id),
		"side": Board.opponent(HOST_SIDE),
		"seats": seats,
		"bots": Array(bot_seats),
		"tc": time_control,
		"opt": option,
		"names": _name_list(),
	}


# --- nomes --------------------------------------------------------------------


## Quem é quem na mesa: assento → nome escolhido no aparelho de cada um.
##
## Até aqui cada aparelho só sabia o **próprio** nome, e todos os outros eram
## "Oponente" ou "Jogador 3" — numa mesa de seis, cinco desconhecidos numerados.
##
## Quem anuncia é cada um, e o anúncio vai junto do aperto de mão que já existia:
## quem abre manda a lista inteira no `welcome`, e quem entra devolve o próprio
## nome no `ready`. Como o relay entrega a mensagem a **todos** os presentes, o
## `ready` de um convidado também chega aos outros convidados — não é preciso o
## anfitrião repassar nada.
##
## Não é um segundo canal a sincronizar: se um nome se perder, a partida continua
## exatamente igual e o cartão volta a dizer "Jogador 3". Nome é enfeite, e é por
## isso que ele pode viajar por fora do histórico de lances.
var player_names := {}

## Como **este** aparelho se apresenta.
##
## Campo, e não uma leitura de `Prefs` na hora de mandar. Os dois motivos:
##
## - este arquivo é transporte, e o resto da configuração de sessão já mora aqui
##   como campo (`game_id`, `time_control`, `option`). Ir buscar preferência de
##   app no meio do protocolo é a camada errada perguntando;
## - `Prefs` é **estático**, um cache por processo. Os testes de rede levantam
##   quatro links no mesmo processo, e com a leitura direta os quatro se
##   apresentavam com o último nome gravado — o que fez o primeiro teste destes
##   sair com os nomes trocados entre si.
##
## Preenchido em `host_relay`/`join_relay` a partir do `Prefs` quando ninguém o
## escreveu, que é o caso do app. Ali não tem como esquecer.
var player_name := ""


## Como este assento se chama, ou vazio se ninguém disse.
func name_of(seat: int) -> String:
	return str(player_names.get(seat, ""))


func _name_list() -> Array:
	var pairs := []
	for seat in player_names:
		pairs.append([seat, player_names[seat]])
	return pairs


func _remember_name(seat: int, raw: Variant) -> void:
	var clean := _clean_name(raw)
	if seat < 0 or clean.is_empty():
		return
	if str(player_names.get(seat, "")) == clean:
		return
	player_names[seat] = clean
	names_changed.emit()


func _remember_names(raw: Variant) -> void:
	for entry in _list(raw):
		if entry is Array and (entry as Array).size() == 2:
			_remember_name(int(entry[0]), entry[1])


## Nome vindo da rede, limpo antes de ser exibido.
##
## O que chega aqui é texto escolhido por **outra pessoa** e desenhado na nossa
## tela. Sem limite de tamanho ele estica um cartão até estourar a coluna; com
## quebra de linha ou caractere de controle ele empurra o resto da faixa para
## fora do lugar. Corta no mesmo limite do campo local e descarta tudo o que não
## for imprimível.
##
## O que isto **não** resolve é alguém se chamar como outro — apelido é apelido, e
## nenhuma limpeza distingue homônimo de impostor.
static func _clean_name(raw: Variant) -> String:
	if not (raw is String):
		return ""
	var text := ""
	for character in (raw as String):
		if character.unicode_at(0) >= 32:
			text += character
	return text.strip_edges().substr(0, Prefs.NAME_LIMIT)


## Começa sem esperar a mesa encher: os assentos vazios viram máquina.
##
## Só quem abriu pode, e só antes de começar. É a resposta para a sala que não
## enche — três amigos numa mesa de quatro esperando um quarto que não vem —, e
## a alternativa era desfazer a sala e recomeçar em outro modo.
func start_with_bots(empty_seats: PackedInt32Array) -> void:
	if not is_host or _session_started or empty_seats.is_empty():
		return
	bot_seats = empty_seats
	_send_direct(_welcome())


## A descrição da mesa, aplicada a partir do que o anfitrião mandou.
##
## Extraída porque **dois** apertos de mão a entregam: o `welcome` de quem chega
## numa sala que ainda enche, e o `resume` de quem chega numa partida já em curso.
## Enquanto isso morava só dentro do `welcome`, o segundo caso ficava sem jogo,
## sem número de assentos e sem saber quais cadeiras são de máquina — e a tela de
## entrar não tinha o que abrir.
## Só a lista de cadeiras de máquina. É o único campo da mesa que muda depois de
## a partida começar, e por isso é o único que vale reaplicar num `resume` a quem
## já estava jogando.
func _adopt_bots(message: Dictionary) -> void:
	if not message.has("bots"):
		return
	var arriving := PackedInt32Array(message.get("bots", []))
	if arriving == bot_seats:
		return
	var released := PackedInt32Array()
	for seat in bot_seats:
		if not arriving.has(seat):
			released.append(seat)
	bot_seats = arriving
	bots_changed.emit()
	for seat in released:
		seat_returned.emit(seat)


func _adopt_table(message: Dictionary) -> void:
	game_id = StringName(str(message.get("game", game_id)))
	seats = int(message.get("seats", 2))
	bot_seats = PackedInt32Array(message.get("bots", []))
	time_control = int(message.get("tc", 0))
	option = int(message.get("opt", 0))
	_remember_names(message.get("names"))
	# A cor sai do **nosso assento**, e não do campo `side` da mensagem.
	#
	# `side` descreve o convidado, porque quem mandava a mesa era sempre o
	# anfitrião. Agora quem recebe um assento de volta é quem ficou, e numa mesa de
	# dois o anfitrião que caiu é recebido pelo convidado: lido do campo, ele
	# voltava jogando com as peças do outro. O assento vem do servidor antes de
	# qualquer mensagem, e para um convidado as duas respostas são a mesma.
	if seats == 2:
		local_side = HOST_SIDE if local_seat == 0 else Board.opponent(HOST_SIDE)


## O aperto de mão, do lado de quem chegou. O código prova que se entrou *nesta*
## sala; divergência é recusada em vez de jogada.
func _on_welcome(message: Dictionary) -> void:
	if is_host:
		return
	if str(message.get("code", "")) != _expected_code:
		join_failed.emit("Código incorreto.")
		leave()
		return
	_adopt_table(message)
	_mark_connected()
	# O assento vai na resposta: quem abriu precisa saber **quem** respondeu para
	# contar até a mesa inteira. Numa mesa de dois a conta é a mesma de sempre.
	#
	# O nome vai junto, e o relay entrega a **todos** — então este `ready` é o que
	# apresenta este jogador aos outros convidados também, não só a quem abriu.
	_send_direct({"t": "ready", "seat": local_seat, "name": player_name})
	if seats == 2:
		opponent_joined.emit(Board.opponent(local_side))
	else:
		table_ready.emit(seats)


## Resposta ao `welcome`, contada por quem abriu. A partida começa quando todos
## os outros assentos responderam — com dois, no primeiro; com quatro, no
## terceiro. Começar antes seria começar sem alguém que a sala está esperando.
func _on_ready(seat: int) -> void:
	if not is_host:
		return
	_ready_seats[seat] = true
	# Só os humanos respondem. Esperar por um assento de máquina seria esperar
	# para sempre, que é o que acontecia antes de a conta descontar os bots.
	if _ready_seats.size() < seats - 1 - bot_seats.size():
		return
	if connected:
		return
	_mark_connected()
	if seats == 2:
		opponent_joined.emit(Board.opponent(HOST_SIDE))
	else:
		table_ready.emit(seats)


# --- sala no relay ------------------------------------------------------------


func relay_available() -> bool:
	return _relay_bridge() != null and _relay_bridge().is_configured()


## `seats` é a capacidade da mesa. Sai do catálogo (`Game.players_of`) e não
## daqui: quantos jogadores um jogo tem é regra dele, e este arquivo não conhece
## jogo nenhum.
func host_relay(id: StringName, code: String, listed := false, seats := 2) -> void:
	if not _wire_relay():
		relay_unavailable.emit("Servidor de partidas indisponível neste build.")
		return
	is_host = true
	game_id = id
	local_side = HOST_SIDE
	local_seat = 0
	self.seats = seats
	bot_seats = PackedInt32Array()
	_ready_seats = {}
	_expected_code = code
	_default_name()
	# Depois do `_default_name()`: o apelido que vai para a lista é o mesmo que os
	# outros jogadores vão ver no cartão durante a partida, e lê-lo antes mandaria
	# vazio para quem nunca escreveu um nome.
	_relay_bridge().host_room(code, id, listed, time_control, seats, player_name)


## A chave do assento que o servidor nos deu, ou vazio fora de sala. `Game` a
## guarda em disco para a volta depois de o processo morrer.
func seat_key() -> String:
	return _relay_bridge().seat_key() if _relay_bridge() != null else ""


## A partida acabou para este aparelho porque **o outro** foi embora — numa mesa de
## dois. Diferente de uma queda nossa, que ainda tem para onde voltar.
func session_ended() -> bool:
	return _opponent_gone


## Código da sala desta partida, ou vazio fora de rede.
##
## `_expected_code` já existia como a conferência de quem entra na sala certa; o
## que faltava era alguém poder **ler** o código depois. A tela de partida mostra
## para o caso de um aparelho cair: quem caiu volta digitando isto, e sem ele o
## código só existia na tela de pareamento, que ninguém vê mais depois que a
## partida começa.
func room_code() -> String:
	return _expected_code


## Endereço da lista pública de salas, ou vazio sem relay configurado.
func rooms_url() -> String:
	return _relay_bridge().rooms_url() if _relay_bridge() != null else ""


func join_relay(code: String, id: StringName, key := "") -> void:
	if not _wire_relay():
		join_failed.emit("Servidor de partidas indisponível neste build.")
		return
	is_host = false
	game_id = id
	# A capacidade real vem do `welcome`: quem entra não sabe de que tamanho é a
	# mesa até quem abriu contar. Dois é o palpite que vale para três dos quatro
	# jogos, e ele é substituído antes de qualquer partida começar.
	seats = 2
	bot_seats = PackedInt32Array()
	_ready_seats = {}
	_expected_code = code
	_default_name()
	_relay_bridge().join_room(code, key)


## Preenche o nome com o dos ajustes quando ninguém o escreveu.
##
## Nos dois pontos em que uma sessão nasce, e não numa terceira função que cada
## tela nova teria de lembrar de chamar. `Prefs.player_name()` nunca devolve
## vazio — ele tem um padrão —, então vazio aqui significa "ninguém escreveu", e
## é só nesse caso que o campo é preenchido: os testes de rede escrevem o deles
## antes, e não querem o do arquivo.
func _default_name() -> void:
	if player_name.is_empty():
		player_name = Prefs.player_name()


func _wire_relay() -> bool:
	if _relay_wired:
		return true
	if _relay_bridge() == null:
		return false
	_relay_wired = true
	_relay_bridge().seated.connect(_on_relay_seated)
	_relay_bridge().peer_present.connect(_on_relay_peer_present)
	_relay_bridge().peer_arrived.connect(_on_relay_peer_arrived)
	_relay_bridge().peer_gone.connect(_on_relay_peer_gone)
	_relay_bridge().message_received.connect(_handle_message)
	_relay_bridge().failed.connect(_on_relay_failed)
	_relay_bridge().state_changed.connect(_on_relay_state_changed)
	return true


## Nosso lugar, confirmado pelo servidor — inclusive depois de uma reconexão,
## quando ele vem igual.
##
## Num jogo de dois o assento **é** a cor, e derivá-la aqui é ter uma fonte só:
## antes quem abria escrevia a sua em `host_relay` e quem entrava lia a do
## `welcome`, e as duas podiam discordar se o aperto de mão mudasse.
##
## `is_host` **não** sai daqui. Ele é o papel no aperto de mão — quem abriu a sala
## e manda o `welcome` —, e é decidido por quem chamou `host_relay`. Derivado do
## assento, o anfitrião que caía e voltava pelo código sentava no 0, se achava
## dono de uma sala por abrir e mandava um `welcome` novo: partida nova, com outra
## semente, enquanto os outros três seguiam na antiga.
func _on_relay_seated(seat: int, capacity: int) -> void:
	local_seat = seat
	seats = capacity
	# O próprio nome entra na lista aqui, e não no aperto de mão: é aqui que este
	# aparelho descobre **qual assento ele é**, e sem isso quem abre mandaria um
	# `welcome` sem se apresentar.
	_remember_name(seat, player_name)
	if seats == 2:
		local_side = HOST_SIDE if seat == 0 else Board.opponent(HOST_SIDE)


## Alguém sentou. Só quem abriu reage: é dele o `welcome`.
##
## E ele espera a **mesa encher**. Com dois assentos isso acontecia na primeira
## chegada, e por isso a espera nunca existiu; com quatro, apresentar a partida
## ao segundo que chega faria dois jogarem enquanto os outros dois ainda estão
## entrando.
func _on_relay_peer_present(_seat: int) -> void:
	# Voltou dentro da carência: a contagem de ausência em curso perde a validade.
	_absence_token += 1
	# Depois de a partida começar, quem chega é recebido em
	# [method _on_relay_peer_arrived] — e por quem ficou, não por quem abriu.
	if not is_host or _session_started:
		return
	if _relay_bridge() != null and _relay_bridge().seats_taken() < seats:
		return
	_send_direct(_welcome())


## Alguém chegou com a partida em curso: quem voltou de uma queda, ou quem senta
## numa cadeira de máquina. Um aparelho só responde — ver [method _greeter].
func _on_relay_peer_arrived(seat: int) -> void:
	# Numa mesa de dois que já acabou para quem ficou, receber de volta abriria
	# uma partida do lado de lá contra uma tela de "a partida acabou" do lado de cá.
	if not _session_started or _opponent_gone or _greeter(seat) != local_seat:
		return
	# Um humano sentando numa cadeira de máquina a **retoma**.
	#
	# Vale para quem volta e para quem chega pela primeira vez numa mesa que
	# começou com bots. Sem esta linha ele entrava e continuava sendo jogado pela
	# máquina, com "(bot)" escrito no cartão e uma pessoa sentada ali — e o
	# aparelho que dirige os bots seguiria jogando por ele.
	#
	# A lista atualizada sai no `resume` logo abaixo, que o relay entrega a
	# **todos**: quem dirige as máquinas precisa parar de jogar por esta cadeira
	# no mesmo instante em que ela deixa de ser de máquina.
	_release_bot_seat(seat)
	# O `resume` carrega a **mesa inteira**, e não só os nomes.
	#
	# Ele nasceu para o aparelho que perdeu o Wi-Fi e voltou: aquele ainda tem
	# tudo em memória e só precisa saber que o link voltou. Mas o mesmo `resume` é
	# o que chega a quem **teve o app fechado e entrou de novo**, e esse não sabe
	# nada — nem qual jogo, nem de quantos é a mesa, nem quais cadeiras são de
	# máquina. Sem os campos ele sentava e ficava parado na tela de entrar, porque
	# nada dizia a ele que havia partida para abrir.
	var returning := _welcome()
	returning["t"] = "resume"
	_send_direct(returning)


## Quem recebe um assento que chega no meio da partida: o **menor assento humano
## presente na sala**, sem contar quem está chegando.
##
## Era "quem abriu a sala, sempre", e isso deixava sem resposta justamente o caso
## em que quem abriu é quem caiu: ninguém mais sabia receber, e ele voltava para
## uma sala muda. Todo aparelho que está na partida tem a mesa inteira em
## memória — jogo, semente, ritmo, máquinas e nomes —, então qualquer um pode
## descrevê-la. O que precisa ser único é **quem** descreve, e "o menor presente"
## é uma conta que todos fazem igual sem combinar nada.
##
## Presença vem do relay e não de `bot_seats` sozinha: numa mesa de dois quem cai
## não vira máquina, e é só a presença que diz que ele não está.
##
## -1 quando não sobrou ninguém para receber.
func _greeter(arriving: int) -> int:
	var present := PackedInt32Array()
	if _relay_bridge() != null:
		present = _relay_bridge().present_seats()
	for seat in seats:
		if seat == arriving or bot_seats.has(seat):
			continue
		if seat == local_seat or present.has(seat):
			return seat
	return -1


## O outro lado sumiu sem avisar. A sala fica de pé no servidor durante a
## carência, então isto congela a partida em vez de encerrá-la — mas só até a
## carência acabar. Sem esse limite o tabuleiro ficava em "reconectando" para
## sempre, que é o que acontecia quando o oponente fechava o app.
##
## Numa mesa de **mais de dois** não há espera: a cadeira vira máquina na hora, e
## volta a ser de quem caiu quando ele voltar ([method _on_relay_peer_arrived]).
## Congelar três pessoas por até noventa segundos à espera de uma é o 4G de uma
## acabando o jogo das outras — e trocar de Wi-Fi para dados custa ao bot, no
## máximo, uma jogada que o histórico entrega de volta para quem voltou.
##
## Numa mesa de dois a espera continua: ali não sobra partida para uma máquina
## preservar, e um bot jogando no lugar de quem caiu decidiria o resultado de um
## contra um.
func _on_relay_peer_gone(seat: int) -> void:
	if _opponent_gone or not _session_started or bot_seats.has(seat):
		return
	if seats > 2:
		_drop_seat(seat)
		return
	if connected:
		connected = false
		link_lost.emit()

	_absence_token += 1
	var token := _absence_token
	await get_tree().create_timer(ABSENCE_LIMIT).timeout
	# O token muda se o oponente voltou, se saímos, ou se o `bye` chegou nesse
	# meio tempo. Só a contagem ainda válida desfaz o assento.
	if token == _absence_token and not connected:
		_drop_seat(seat)


func _on_relay_state_changed(state: RelayBridge.State) -> void:
	if state == RelayBridge.State.RECONNECTING and connected:
		connected = false
		link_lost.emit()


## A ponte só desiste depois de esgotar a janela de reconexão, então quando isto
## chega no meio da partida o oponente realmente foi embora.
func _on_relay_failed(reason: String) -> void:
	if _session_started:
		connected = false
		opponent_left.emit()
	elif is_host:
		push_warning("Não foi possível abrir a sala: %s" % reason)
		relay_unavailable.emit(reason)
	else:
		join_failed.emit(reason)


func _close_relay() -> void:
	if _relay_wired and _relay_bridge() != null:
		_relay_bridge().leave()
