class_name ChatLog
extends RefCounted

## O chat de uma partida: o que se pode dizer, o que já foi dito e quem está calado.
##
## Não conhece rede. `Net` pergunta aqui antes de mandar e passa por aqui tudo o
## que recebe; a tela lê [member entries] e escuta o `Net.chat_received`.
##
## Quem recebe limpa tudo de novo, mesmo o que o app já limpou ao mandar: o relay
## repassa o envelope sem abrir, e um cliente modificado manda o que quiser. Pela
## mesma razão o assento de quem falou é o `from` carimbado pelo servidor, e
## nunca um campo da mensagem.

enum Kind { EMOTE, PHRASE, TEXT }

## Reações rápidas. O que viaja é o índice, então a lista só cresce no fim:
## trocar a ordem faria um aparelho com a versão antiga mostrar outro emote.
const EMOTES := ["👍", "😂", "😮", "😢", "😡", "🔥", "👏", "🤔"]
## Frases prontas. Mesma regra: só cresce no fim. Viajam pelo índice para quem
## recebe saber que vieram da lista fechada, e não de um texto digitado.
const PHRASES := ["Oi!", "Boa!", "Bem jogado!", "Ops!", "Pensa logo!", "GG"]

const TEXT_LIMIT := 120
## Espera entre duas mensagens deste aparelho. O relay derruba quem passa de 40
## mensagens por segundo (`rate_limited`), e quem cai perde a partida: sem esta
## espera, apertar o emote sem parar seria um jeito de abandonar o jogo.
const COOLDOWN_MS := 1500
## Teto por assento ao receber. Um cliente modificado ignora a espera de cima, e
## quem recebe não precisa ver a enxurrada.
const BURST := 5
const BURST_WINDOW_MS := 5000
const HISTORY_LIMIT := 50
## O assento da plateia. Espectador não tem assento: o relay carimba a conversa
## dele com este `from`, e o apelido viaja dentro da mensagem (`n`).
##
## ponytail: a plateia inteira divide um [constant BURST]. Basta para até oito
## espectadores; separar por apelido seria confiar num campo que eles escolhem.
const AUDIENCE := -1
const NAME_LIMIT := 20

## `{"seat", "kind", "id", "text"}`, da mais antiga à mais nova. `text` já é o
## que se mostra: o emoji, a frase ou o texto limpo. `id` é o índice do emote ou
## da frase, e -1 no texto livre. Da plateia ([constant AUDIENCE]) vem também
## `name`, o apelido de quem assiste. `Net` marca `mine` no que saiu daqui.
var entries := []

var _muted := {}
var _last_sent := -COOLDOWN_MS
## Por assento, quando chegaram as mensagens aceitas na janela do [constant BURST].
var _recent := {}


func can_send(now: int) -> bool:
	return now - _last_sent >= COOLDOWN_MS


## O que este aparelho vai dizer, já limpo e guardado. Vazio quando ainda está na
## espera ou quando não sobra nada a dizer.
func say(seat: int, body: Dictionary, now: int) -> Dictionary:
	if not can_send(now):
		return {}
	var entry := read(seat, body)
	if entry.is_empty():
		return {}
	_last_sent = now
	_add(entry)
	return entry


## O que chegou de `seat`, já limpo e guardado. Vazio quando o assento está
## calado, passou do teto ou mandou algo que não vale.
func receive(seat: int, body: Dictionary, now: int) -> Dictionary:
	if _muted.has(seat):
		return {}
	var recent: Array = _recent.get(seat, []).filter(
		func(at: int) -> bool: return now - at < BURST_WINDOW_MS
	)
	_recent[seat] = recent
	if recent.size() >= BURST:
		return {}
	var entry := read(seat, body)
	if entry.is_empty():
		return {}
	recent.append(now)
	_add(entry)
	return entry


## Silencia o assento até o fim da partida, e apaga o que ele já disse.
func mute(seat: int) -> void:
	_muted[seat] = true
	entries = entries.filter(func(entry: Dictionary) -> bool: return entry["seat"] != seat)


func is_muted(seat: int) -> bool:
	return _muted.has(seat)


## A mensagem do envelope (`e`, `q` ou `s`) virada entrada. Vazio se não vale.
static func read(seat: int, body: Dictionary) -> Dictionary:
	var entry := _read(seat, body)
	if not entry.is_empty() and seat == AUDIENCE:
		entry["name"] = clean(body.get("n")).substr(0, NAME_LIMIT).strip_edges()
	return entry


static func _read(seat: int, body: Dictionary) -> Dictionary:
	if body.has("e"):
		var emote := _index(body["e"], EMOTES.size())
		if emote < 0:
			return {}
		return {"seat": seat, "kind": Kind.EMOTE, "id": emote, "text": EMOTES[emote]}
	if body.has("q"):
		var phrase := _index(body["q"], PHRASES.size())
		if phrase < 0:
			return {}
		return {"seat": seat, "kind": Kind.PHRASE, "id": phrase, "text": PHRASES[phrase]}
	var text := clean(body.get("s"))
	if text.is_empty():
		return {}
	return {"seat": seat, "kind": Kind.TEXT, "id": -1, "text": text}


## A entrada de volta ao envelope, para mandar.
static func wire(entry: Dictionary) -> Dictionary:
	var out := {"t": "chat"}
	match int(entry["kind"]):
		Kind.EMOTE:
			out["e"] = entry["id"]
		Kind.PHRASE:
			out["q"] = entry["id"]
		_:
			out["s"] = entry["text"]
	if entry.has("name"):
		out["n"] = entry["name"]
	return out


## Uma linha só, sem caracteres de controle, sem os que invertem a direção do
## texto e com no máximo [constant TEXT_LIMIT] caracteres.
##
## Quebra de linha e tabulação viram espaço, e espaços seguidos viram um: o
## balão tem uma linha, e uma mensagem feita de quebras empurraria a mesa para
## fora da tela. Os controles de direção (U+202E e parentes) saem de vez, porque
## servem para fazer o texto parecer outro.
static func clean(raw: Variant) -> String:
	if not raw is String:
		return ""
	# Corta antes de varrer: o que passa muito do limite não chega à tela de
	# qualquer jeito, e varrer um texto enorme custa à toa.
	var source := (raw as String).substr(0, TEXT_LIMIT * 4)
	var out := ""
	var pending_space := false
	for i in source.length():
		var code := source.unicode_at(i)
		if code <= 0x20 or (code >= 0x7F and code <= 0xA0) or code == 0x2028 or code == 0x2029:
			pending_space = not out.is_empty()
			continue
		if code == 0x061C or code == 0x200E or code == 0x200F \
				or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069):
			continue
		if pending_space:
			out += " "
			pending_space = false
		out += String.chr(code)
	return out.substr(0, TEXT_LIMIT).strip_edges()


## Inteiro em `0..size-1`, ou -1. O JSON entrega número como float, e um cliente
## modificado pode mandar texto, fração ou negativo.
static func _index(raw: Variant, size: int) -> int:
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return -1
	var value := float(raw)
	if value != floorf(value) or value < 0.0 or value >= size:
		return -1
	return int(value)


func _add(entry: Dictionary) -> void:
	entries.append(entry)
	if entries.size() > HISTORY_LIMIT:
		entries.pop_front()
