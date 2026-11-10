class_name Training
extends RefCounted

## O baralho do treino: os erros do jogador nas partidas revisadas, de volta
## como desafio até ele acertar de primeira várias vezes seguidas.
##
## Repetição espaçada à Leitner. Acertou limpo (sem dica, sem desistir), o
## cartão volta em 1, 3, 7, 14 e depois 30 dias; errou, volta amanhã e recomeça
## a escada. Leitner e não SM-2 porque o desafio só tem duas respostas — resolveu
## ou não —, e é o que o SM-2 faria com elas, com três números a mais por cartão.
##
## Um cartão é um dicionário, pronto para o `ConfigFile`:
##
##   {"prefix": "e2e4 e7e5 …", "played": "g8f6", "best": "g7g6",
##    "best_san": "g6", "score": 62.0, "mate": false,
##    "box": 0, "due": 0, "at": 1730000000}
##
## `prefix` são os lances em UCI até a posição do erro — não FEN: o projeto não
## lê FEN, e refazer os lances é o que a revisão já faz. Quem joga é quem tem a
## vez depois deles. `score` é a vitória esperada de quem joga ali, a régua do
## desafio "ache um lance melhor"; `mate` diz que o desafio é achar o mate.
## `at` é a partida de onde ele saiu (o `at` do histórico).

const INTERVAL_DAYS := [1, 3, 7, 14, 30]
const DAY := 86400
## ~150 bytes por cartão sem o prefixo, ~5 por lance dele: 200 cartões cabem
## em poucas dezenas de KB no arquivo de preferências.
const LIMIT := 200


## Os erros de `sides` numa partida analisada (`GameReview.analyse`): erro,
## erro grave e mate perdido — a régua do "Próximo erro" da revisão. Vencem na
## hora: o erro é de agora, e o treino é o lugar de pagar por ele.
static func cards_from(entries: Array, sides: Array, at: int) -> Array:
	var out := []
	var prefix := PackedStringArray()
	for entry in entries:
		if (
			entry["side"] in sides
			and str(entry["best"]) != ""
			and (entry["missed_mate"] or entry["verdict"] >= GameReview.Verdict.MISTAKE)
		):
			out.append({
				"prefix": " ".join(prefix),
				"played": entry["uci"],
				"best": entry["best"],
				"best_san": entry["best_san"],
				"score": float(entry["score"]),
				"mate": bool(entry["missed_mate"]),
				"box": 0,
				"due": 0,
				"at": at,
			})
		prefix.append(entry["uci"])
	return out


## O cartão depois de uma tentativa. `clean` é ter resolvido sem dica e sem
## desistir; qualquer outra coisa conta como errar.
static func grade(card: Dictionary, clean: bool, now: int) -> Dictionary:
	var out := card.duplicate()
	var box := int(card["box"])
	if clean:
		out["due"] = now + int(INTERVAL_DAYS[box]) * DAY
		out["box"] = mini(box + 1, INTERVAL_DAYS.size() - 1)
	else:
		out["due"] = now + int(INTERVAL_DAYS[0]) * DAY
		out["box"] = 0
	return out


## Os vencidos, o mais atrasado primeiro.
static func due(deck: Array, now: int) -> Array:
	var out := deck.filter(func(card): return int(card["due"]) <= now)
	out.sort_custom(func(a, b): return int(a["due"]) < int(b["due"]))
	return out


## O mesmo erro na mesma posição é o mesmo cartão: revisar a partida de novo não
## duplica, e o cartão que já subiu de caixa não volta ao começo.
static func key(card: Dictionary) -> String:
	return "%s|%s" % [card["prefix"], card["played"]]


## `fresh` entra no fim de `deck` sem repetir cartão. Passou de `LIMIT`, sai o
## mais aprendido (caixa mais alta) e, entre eles, o de partida mais antiga.
static func merge(deck: Array, fresh: Array) -> Array:
	var out := deck.duplicate()
	var seen := {}
	for card in out:
		seen[key(card)] = true
	for card in fresh:
		if not seen.has(key(card)):
			seen[key(card)] = true
			out.append(card)
	while out.size() > LIMIT:
		var drop := 0
		for i in out.size():
			var a: Dictionary = out[i]
			var b: Dictionary = out[drop]
			if int(a["box"]) > int(b["box"]) or (int(a["box"]) == int(b["box"]) and int(a["at"]) < int(b["at"])):
				drop = i
		out.remove_at(drop)
	return out


## A cor de quem jogou uma partida do histórico, ou -1 no mesmo aparelho, onde
## os dois lados são de quem segura o aparelho. Partida gravada antes do campo
## `hotseat` fica com a cor gravada: brancas.
static func played(game: Dictionary) -> int:
	return -1 if game.get("hotseat", false) else int(game.get("side", Board.Side.WHITE))


## Os lados que eram do dono do aparelho numa partida do histórico.
static func sides(game: Dictionary) -> Array:
	var side := played(game)
	return [Board.Side.WHITE, Board.Side.BLACK] if side < 0 else [side]


## Uma análise de `game` chegou: os erros vão para o baralho, e a partida, se a
## análise foi até o fim, sai da fila do "Analisar partidas novas". Análise
## cortada no meio (o motor caiu) ainda rende os cartões que achou.
static func collect(game: Dictionary, entries: Array) -> void:
	if game.is_empty() or entries.is_empty():
		return
	var at := int(game["at"])
	Prefs.set_training(merge(Prefs.training(), cards_from(entries, sides(game), at)))
	if entries.size() == (game.get("moves", []) as Array).size():
		Prefs.mark_analysed(at)


## A posição do desafio: os lances do cartão refeitos desde a inicial. `null`
## se algum não for legal — cartão de uma versão com outra regra, ou estragado.
static func position(card: Dictionary) -> MatchState:
	var rules := ChessRules.new()
	var state := rules.initial_state()
	for uci in str(card["prefix"]).split(" ", false):
		var move := rules.move_from_uci(state, uci)
		if move == null:
			return null
		rules.apply_move(state, move)
	return state


## As partidas do histórico que ainda não passaram pela análise inteira.
static func pending(games: Array) -> Array:
	return games.filter(func(game): return not game.get("analysed", false))
