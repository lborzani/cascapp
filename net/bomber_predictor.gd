class_name BomberPredictor
extends RefCounted

## A simulação do cliente de Bomberman: anda na frente do servidor e se corrige
## quando ele discorda.
##
## É a irmã do `net/predictor.gd` do streetVolley, e o motivo de existir é o
## mesmo: sem previsão, o dedo aperta, o comando viaja, o servidor aplica e o
## resultado volta — e só então o boneco se mexe. Aqui o cliente aplica o próprio
## comando **no tique em que ele acontece** e descobre depois se estava certo.
##
## ## Por que um jogo de grade precisa de mais cuidado que o volei
##
## No volei, o objeto que decide o ponto é a bola, e a bola não recebe entrada —
## prever é exato. No Bomberman **tudo** que se move é dirigido por um dedo, e o
## objeto que decide a partida — a bomba — é uma ação instantânea. Prever a bomba
## de um adversário e errar planta uma bomba-fantasma que o servidor vai desmentir,
## e uma bomba que aparece e some é pior que um boneco que escorrega.
##
## Por isso a predição é assimétrica:
##
## - **o próprio assento**: aplicado inteiro, na hora. É perfeito — o dedo é
##   conhecido, então a reexecução nunca o corrige.
## - **assento de máquina**: roda o [BomberBot], que é determinístico e sem
##   `randi()`. A decisão local bate com a do servidor, bombas inclusas.
## - **humano remoto, tique já confirmado**: o comando verdadeiro, que o servidor
##   devolveu ([method note]).
## - **humano remoto, tique ainda não chegado**: repete o **movimento** conhecido,
##   mas **descarta a bomba**. Bomba de outro só entra na simulação quando o
##   servidor a confirma. É o mesmo cuidado que a sala tem no servidor.
##
## ## Reexecutar não é adivinhar
##
## O servidor devolve os comandos que **usou**. Quando um snapshot descreve o tique
## 400 e o cliente já está no 410, ele volta ao 400 e refaz os dez tiques com os
## comandos verdadeiros de quem já os mandou, e com o próprio dedo, que nunca
## esqueceu. O que sobra de chute é só o que ainda não chegou — poucos tiques, e
## sempre os mais novos.
##
## `RefCounted` puro, como tudo em `core/`: a predição é exercida num teste
## headless sem tela, sem rede e sem celular.

## Tiques de histórico guardados. Dois segundos cobre qualquer atraso que ainda
## valha a pena reconciliar — mais velho que isso, o servidor já nem aceitaria o
## comando ([constant BomberProtocol.INPUT_GRACE]).
const MEMORY := 60

## O estado que a tela desenha, e o de um tique atrás pra interpolar entre os dois.
var state: BomberState = null
var previous: BomberState = null
var tick := 0

## Quantos tiques a última reconciliação refez, e o quanto ela mexeu no próprio
## boneco, em unidades. Servem pra medir: uma previsão que corrige o próprio dedo
## está mentindo pro jogador, e `drift` do assento local tem de ser zero.
var replayed := 0
var drift := 0

## Quanto a última reconciliação mexeu em cada boneco, em unidades. Serve pra tela
## **absorver** o erro em vez de estalar — o desenho escorrega até a verdade em
## alguns quadros em vez de saltar.
var correction: Array[Vector2i] = []

var _rules: BomberRules = null
var _bot := BomberBot.new()
var _seat := 0
## Comando local por tique.
var _mine := {}
## Comando conhecido de cada assento por tique, o que o servidor devolveu.
var _known: Array[Dictionary] = [{}, {}, {}, {}]
## Último comando conhecido de cada assento, ou −1.
var _last := PackedInt32Array([-1, -1, -1, -1])
var _is_bot := [false, false, false, false]


func _init(rules: BomberRules, seat: int) -> void:
	_rules = rules
	_seat = seat


## Quais assentos são máquina. Nome vazio é máquina — o servidor garante que gente
## sempre tem nome. Muda a forma de prever o que ainda não chegou: pra um bot,
## rodar o [BomberBot] devolve a mesma decisão que o servidor tomou; pra uma
## pessoa, o melhor chute é que ela siga andando pro mesmo lado.
func note_seats(names: PackedStringArray) -> void:
	for index in mini(names.size(), _is_bot.size()):
		_is_bot[index] = names[index] == ""


## O primeiro estado, ou um salto pra frente quando o cliente ficou atrás.
func adopt(snapshot: BomberState) -> void:
	state = snapshot.clone()
	previous = snapshot.clone()
	tick = snapshot.tick
	replayed = 0
	drift = 0


## Um tique adiante, com o comando do dedo agora.
func advance(local: int) -> void:
	if state == null:
		return
	tick += 1
	_mine[tick] = local
	previous = state.clone()
	_rules.step(state, _row_for(tick))
	_forget()


## O que o servidor de fato aplicou, pra reexecução parar de ser chute. `rows` é um
## Array de [PackedByteArray], uma linha por tique, um comando por assento.
func note(first_tick: int, rows: Array) -> void:
	for offset in rows.size():
		var at := first_tick + offset
		var row: PackedByteArray = rows[offset]
		for seat in mini(row.size(), _known.size()):
			_known[seat][at] = row[seat]


## O servidor discordou. Volta ao que ele disse e refaz o caminho até aqui.
## Devolve quantos tiques foram refeitos.
func reconcile(snapshot: BomberState) -> int:
	if state == null or snapshot.tick >= tick:
		# O servidor está à frente: não há o que reexecutar, e insistir no estado
		# local seria preferir a previsão à verdade.
		adopt(snapshot)
		return 0

	var before: Array[Vector2i] = []
	for one in state.players:
		before.append(Vector2i(one.x, one.y))

	var target := tick
	state = snapshot.clone()
	var at := snapshot.tick
	while at < target:
		at += 1
		# `previous` é o estado um tique antes do fim, na linha do tempo nova — pra
		# a interpolação da tela ter o par certo e não estalar na correção.
		if at == target:
			previous = state.clone()
		_rules.step(state, _row_for(at))

	tick = target
	replayed = target - snapshot.tick

	correction = []
	for seat in state.players.size():
		var now := Vector2i(state.players[seat].x, state.players[seat].y)
		correction.append(now - before[seat] if seat < before.size() else Vector2i.ZERO)
	drift = correction[_seat].length() if _seat < correction.size() else 0
	return replayed


## O comando de cada assento neste tique, como uma linha pra [method BomberRules.step].
func _row_for(at: int) -> PackedByteArray:
	var row := PackedByteArray()
	var count := state.players.size()
	row.resize(count)
	for seat in count:
		row[seat] = _command_for(seat, at)
	return row


func _command_for(seat: int, at: int) -> int:
	if seat == _seat:
		return _mine.get(at, 0)

	var known: Dictionary = _known[seat]
	if known.has(at):
		_last[seat] = known[at]
		return known[at]

	if _is_bot[seat]:
		return _bot.decide(state, seat)

	if _last[seat] >= 0:
		# Humano remoto sem o byte: repete o movimento, nunca a bomba. Bomba de
		# outro só aparece quando o servidor a confirma.
		return _last[seat] & ~BomberRules.IN_BOMB
	return 0


func _forget() -> void:
	var limit := tick - MEMORY
	for at in _mine.keys():
		if at < limit:
			_mine.erase(at)
	for known in _known:
		for at in known.keys():
			if at < limit:
				known.erase(at)
