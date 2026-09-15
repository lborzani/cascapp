class_name BomberRoom
extends RefCounted

## Uma sala de Bomberman no servidor: a mesa, a simulação autoritativa, e as
## caixas de entrada de quem está sentado.
##
## Mora no servidor e em lugar nenhum mais. O cliente não tem sala — ele tem um
## assento e um fio, e prevê a partida em cima dos snapshots que esta sala manda.
##
## É a irmã do `net/room.gd` do streetVolley, com três diferenças que vêm do jogo:
## a mesa é de dois a quatro (e não sempre quatro); o comando é um byte
## ([BomberRules]) em vez de um objeto; e a partida **acaba** — alguém vence, e a
## sala para de simular.
##
## ## Assento vazio é máquina, calculada aqui
##
## Um assento sem ninguém — vazio desde o início ou abandonado no meio — não fica
## parado: [BomberBot] joga por ele. Como o bot é determinístico e sem `randi()`,
## o servidor calcula o comando dele sozinho, e o cliente calcula o mesmo comando
## na predição. É a mesma propriedade que o lockstep usava, agora sem o lockstep.
##
## ## Quando o comando não chegou
##
## Repete o último **movimento** conhecido, e não é chute: um dedo parado é a
## hipótese mais provável a um tique de distância. Mas o **bit de bomba é
## descartado** no repeat — repetir a última tecla plantaria uma bomba nova a cada
## tique faltante, e uma sala que solta bombas-fantasma por causa de um pacote
## perdido é pior que o soluço que o repeat evita. É a contraparte, no servidor, do
## mesmo cuidado que o predictor tem no cliente.
##
## Ao contrário do lockstep do outro projeto, a simulação **não para** esperando o
## byte: segue e corrige quando ele chega — e um byte velho demais é passado
## ([constant BomberProtocol.INPUT_GRACE]).

const NAME_LIMIT := 12

var code := ""
## Peer de cada assento, ou 0 pra vazio. O tamanho é o da mesa (2 a 4).
var seats := PackedInt32Array()
## O nome de quem está sentado, ou string vazia pra assento de máquina. É o que
## viaja pros clientes no lugar dos peers.
var names := PackedStringArray()
var state: BomberState = null
var running := false
## A partida acabou porque alguém venceu (ou a mesa esvaziou de gente). A sala para
## de simular, mas continua mandando o último estado pra quem chegar atrasado ver o
## resultado.
var finished := false
## Quem venceu, ou −1 enquanto a partida corre. Empate é −2 (todos caíram no mesmo
## tique). Ver [method BomberRules.winner].
var winner := -1

var _rules := BomberRules.new()
var _bot := BomberBot.new()
## Comando conhecido por assento e por tique.
var _inbox: Array[Dictionary] = []
## Último comando conhecido de cada assento, ou −1 se nenhum ainda.
var _last := PackedInt32Array()
## As últimas linhas de comando que a sala aplicou, pros clientes reexecutarem o
## passado com o que **de fato** aconteceu em vez de um chute.
var _used: Array = []


## `format` é o tamanho da mesa (2 a 4). A semente é do servidor, não do cliente:
## dois clientes com sementes diferentes montariam mapas diferentes, e a
## divergência apareceria como um jogador atravessando uma parede que só existe na
## tela do outro.
func _init(room_code: String, format: int, match_seed: int) -> void:
	code = room_code
	var count := clampi(format, 2, 4)
	state = _rules.initial_state(count, match_seed)
	seats = PackedInt32Array()
	names = PackedStringArray()
	_last = PackedInt32Array()
	for index in count:
		seats.append(0)
		names.append("")
		_inbox.append({})
		_last.append(-1)


func seat_count() -> int:
	return seats.size()


func occupied() -> int:
	var count := 0
	for peer in seats:
		if peer != 0:
			count += 1
	return count


func full() -> bool:
	return occupied() >= seats.size()


## Senta alguém no primeiro assento livre. Devolve o assento, ou −1 se lotou.
func seat_for(peer: int, wanted_name: String) -> int:
	for index in seats.size():
		if seats[index] == 0:
			seats[index] = peer
			names[index] = _clean(wanted_name, index)
			return index
	return -1


func seat_of(peer: int) -> int:
	for index in seats.size():
		if seats[index] == peer:
			return index
	return -1


## Solta um assento quando o peer cai. O assento vira máquina — o bot assume dali
## em diante, e a partida dos outros não para.
func release(peer: int) -> int:
	var index := seat_of(peer)
	if index >= 0:
		seats[index] = 0
		names[index] = ""
		_inbox[index].clear()
		_last[index] = -1
		# A mesa esvaziou de gente: não há partida a continuar contra bots num
		# servidor. Quem sobrar recebe o fim.
		if running and occupied() == 0:
			finished = true
			running = false
	return index


## Nome vazio vira um padrão com o número do assento. Um humano **sempre** tem
## nome, e é isso que deixa "nome vazio" significar máquina sem ambiguidade.
##
## O corte de caracteres de controle **não** é zelo excessivo, e é a mesma regra
## que o relay aplica em `cleanName` (`relay/src/protocol.ts`) pelo mesmo motivo:
## esta string sai do teclado de uma pessoa e vai desenhada para a tela de todas
## as outras da sala, e quem a manda é um peer qualquer — cliente adulterado é a
## hipótese normal, não a exótica. Uma quebra de linha aqui estica a lista de
## assentos para fora do cartão no lobby de quem nem escolheu o nome.
##
## Não há escape de HTML porque não há HTML: quem desenha é `draw_string` num
## `Control`, e ali uma tag é literalmente o texto "<b>".
func _clean(wanted: String, index: int) -> String:
	var printable := ""
	for character in wanted:
		var point := character.unicode_at(0)
		if point >= 0x20 and point != 0x7f:
			printable += character
	var clean := printable.strip_edges().substr(0, NAME_LIMIT)
	return "Jogador %d" % (index + 1) if clean == "" else clean


## Guarda os comandos que chegaram, dentro da janela em que eles ainda servem.
##
## Ignora o que é velho demais pra ser aplicado: reescrever um tique que já foi
## seria mudar uma jogada que todo mundo já viu. E ignora o que está adiantado
## demais, que é a mesma pergunta pelo outro lado — com uma diferença de
## consequência.
##
## O teto de cima **não é** simetria por elegância: o tique vem do cliente, num
## `s32`, e sem ele um número absurdo entrava na caixa de entrada e não saía mais.
## [method _forget_before] varre o que ficou para trás do tique atual, e nada que
## esteja à frente dele fica para trás; [method _command_for] procura pelo tique
## do passo seguinte, que nunca alcança dois bilhões. O comando não era usado,
## não era apagado, e a cada varredura era percorrido de novo — memória e CPU
## crescendo juntas, num servidor com a porta aberta para a internet.
func receive(peer: int, first_tick: int, commands: PackedByteArray) -> void:
	var index := seat_of(peer)
	if index < 0:
		return
	var floor_tick := state.tick - BomberProtocol.INPUT_GRACE
	var ceiling_tick := state.tick + BomberProtocol.INPUT_LEAD
	for offset in commands.size():
		var at := first_tick + offset
		if at < floor_tick or at > ceiling_tick:
			continue
		_inbox[index][at] = commands[offset]


## Um tique da simulação autoritativa. Junta o comando de cada assento, anda, e
## para se a partida acabou.
func step() -> void:
	if not running:
		return
	var next := state.tick + 1
	var commands := PackedByteArray()
	commands.resize(seats.size())
	for index in seats.size():
		commands[index] = _command_for(index, next)
	_rules.step(state, commands)

	_used.append({"tick": state.tick, "row": commands})
	while _used.size() > BomberProtocol.FRAME + BomberProtocol.HISTORY:
		_used.pop_front()

	_forget_before(state.tick - BomberProtocol.INPUT_GRACE)

	var champion := _rules.winner(state)
	if champion != -1:
		winner = champion
		finished = true
		running = false


## O que mandar pros clientes: o tique da linha mais antiga guardada, e as linhas.
## Vazio enquanto a partida ainda não deu um passo.
func recent_commands() -> Dictionary:
	if _used.is_empty():
		return {}
	var rows: Array = []
	for entry in _used:
		rows.append(entry["row"])
	return {"tick": _used[0]["tick"], "rows": rows}


## O comando de um assento neste tique: o verdadeiro se chegou; senão o último
## **movimento** conhecido (sem o bit de bomba); senão nada. Assento vazio é bot.
func _command_for(index: int, at: int) -> int:
	if seats[index] == 0:
		return _bot.decide(state, index)
	var box := _inbox[index]
	if box.has(at):
		_last[index] = box[at]
		return box[at]
	if _last[index] >= 0:
		# Repete o movimento, nunca a bomba: um byte perdido não é uma bomba nova.
		return _last[index] & ~BomberRules.IN_BOMB
	return 0


func _forget_before(limit: int) -> void:
	for box in _inbox:
		for at in box.keys():
			if at < limit:
				box.erase(at)
