class_name GameReview
extends RefCounted

## Revisão de uma partida de xadrez pelo Stockfish em força total.
##
## O Stockfish não revisa partida — ele só dá nota a posição. A revisão é esta
## camada: nota antes e depois de cada lance, e o lance julgado pelo quanto ele
## custou em **chance de vitória**, não em peões. Perder dois peões com a
## partida ganha não muda nada; com a partida igual, decide. As faixas são as
## do Lichess.
##
## `analyse` é bloqueante (uma busca por posição) e roda na thread de quem
## chama; `progress` é lido pela tela a cada quadro.

enum Verdict { BEST, GOOD, INACCURACY, MISTAKE, BLUNDER }

const SYMBOL := {
	Verdict.BEST: "!",
	Verdict.GOOD: "",
	Verdict.INACCURACY: "?!",
	Verdict.MISTAKE: "?",
	Verdict.BLUNDER: "??",
}
const LABEL := {
	Verdict.BEST: "Melhor lance",
	Verdict.GOOD: "Bom lance",
	Verdict.INACCURACY: "Imprecisão",
	Verdict.MISTAKE: "Erro",
	Verdict.BLUNDER: "Erro grave",
}

## Queda, em pontos percentuais de vitória esperada, a partir da qual o lance
## vira imprecisão, erro e erro grave.
const INACCURACY_DROP := 10.0
const MISTAKE_DROP := 20.0
const BLUNDER_DROP := 30.0

## Por posição. Uma partida de 40 lances são 81 buscas: ~25 s no celular.
const MOVETIME_MS := 300

var progress := 0
var total := 0
var _abandoned := false


## Vitória esperada de quem tem a vez, de 0 a 100: vitória vale um, empate meio.
## Vem do WDL do próprio Stockfish, que já é calibrado em partidas reais — e
## cobre o mate sem caso especial (mate é `1000 0 0`).
static func expected(wdl: Array) -> float:
	return (float(wdl[0]) + float(wdl[1]) * 0.5) / 10.0


## Precisão de um lance, de 0 a 100, pela fórmula do Lichess: cai depressa com
## a vitória esperada que o lance jogou fora. Lance que não perdeu nada vale 100.
static func move_accuracy(before: float, after: float) -> float:
	if after >= before:
		return 100.0
	return clampf(103.1668 * exp(-0.04354 * (before - after)) - 3.1669, 0.0, 100.0)


## Precisão da partida de um lado, ou -1 se ele não jogou. A média harmônica
## pesa os erros (um lance a 10% derruba a nota de verdade) e a aritmética
## segura uma partida longa e limpa; o Lichess mistura as duas.
##
## ponytail: sem os pesos por volatilidade do Lichess (janela deslizante); a
## nota sai um pouco diferente da de lá em partidas que oscilam muito.
static func accuracy(entries: Array, side: int) -> float:
	var total := 0.0
	var inverse := 0.0
	var count := 0
	for entry in entries:
		if entry["side"] != side:
			continue
		var value := maxf(move_accuracy(entry["score"], entry["after"]), 0.5)
		total += value
		inverse += 1.0 / value
		count += 1
	if count == 0:
		return -1.0
	return (total / count + count / inverse) / 2.0


## `before` e `after` são a vitória esperada de **quem jogou**, antes e depois.
static func classify(before: float, after: float, is_best: bool) -> Verdict:
	if is_best:
		return Verdict.BEST
	var drop := before - after
	if drop >= BLUNDER_DROP:
		return Verdict.BLUNDER
	if drop >= MISTAKE_DROP:
		return Verdict.MISTAKE
	if drop >= INACCURACY_DROP:
		return Verdict.INACCURACY
	return Verdict.GOOD


## Havia mate forçado para quem jogou (`mate_before` > 0) e o lance o deixou
## escapar. `mate_after` é do ponto de vista do **adversário**: enquanto o mate
## continua de pé ele é negativo, mesmo que mais longo — trocar um mate em 2 por
## um em 3 não é perder o mate.
static func missed_mate(mate_before: int, mate_after: int, delivered: bool) -> bool:
	return mate_before > 0 and not keeps_mate(mate_after, delivered)


## A régua do desafio "ache um lance melhor": o lance não jogou fora vitória
## esperada a ponto de virar imprecisão. Vale qualquer lance bom, não só o do
## motor — em muita posição há dois ou três que seguram.
static func holds(before: float, after: float) -> bool:
	return before - after < INACCURACY_DROP


## O lance deu o mate ou deixou o adversário sem saída (`mate_after` negativo,
## do ponto de vista dele). É a régua do desafio "encontre o mate": vale
## qualquer caminho, não só o que o motor escolheu.
static func keeps_mate(mate_after: int, delivered: bool) -> bool:
	return delivered or mate_after < 0


## A partida inteira do ponto de vista das brancas: a vitória esperada delas em
## cada posição, da inicial (`[0]`) à que ficou depois do último lance analisado
## (`[entries.size()]`). As entradas guardam a nota de **quem jogou**; aqui ela é
## virada quando quem jogou foram as pretas. Vazia sem análise.
static func white_curve(entries: Array) -> Array:
	if entries.is_empty():
		return []
	var first: Dictionary = entries[0]
	var curve := [_white(first["score"], first["side"])]
	for entry in entries:
		curve.append(_white(entry["after"], entry["side"]))
	return curve


static func _white(score: float, side: int) -> float:
	return score if side == Board.Side.WHITE else 100.0 - score


## Uma entrada por lance de `history`:
##
##   {"san", "uci", "side", "fen", "best", "best_san", "score", "after",
##    "verdict", "mate", "missed_mate"}
##
## `score`/`after` são a vitória esperada de quem jogou. `fen` e `mate` são da
## posição antes do lance — é dela que o puzzle de mate perdido parte. Vazio
## quando o motor não sobe.
func analyse(history: Array) -> Array:
	var engine := Stockfish.new()
	if not engine.start():
		return []
	engine.set_strength(0)
	var rules := ChessRules.new()
	var state := rules.initial_state()
	total = history.size()
	progress = 0
	var out := []
	var seen := look(engine, rules, state)
	for data in history:
		if _abandoned or seen.is_empty():
			break
		var move := rules.move_from_uci(state, rules.uci(Move.from_dict(data)))
		if move == null:
			break
		var entry := {
			"san": rules.notation(state, move),
			"uci": rules.uci(move),
			"side": state.side_to_move,
			"fen": rules.fen(state),
			"best": seen["best"],
			"best_san": "",
			"score": seen["score"],
			"mate": seen["mate"],
		}
		var best_move := rules.move_from_uci(state, str(seen["best"]))
		if best_move != null:
			entry["best_san"] = rules.notation(state, best_move)

		rules.apply_move(state, move)
		var after := look(engine, rules, state)
		if after.is_empty():
			break
		entry["after"] = 100.0 - float(after["score"])
		entry["verdict"] = classify(entry["score"], entry["after"], entry["uci"] == entry["best"])
		entry["missed_mate"] = missed_mate(entry["mate"], after["mate"], after["mated"])
		out.append(entry)
		seen = after
		progress += 1
	engine.quit()
	return out


## Pede para parar no próximo lance. Quem chama ainda espera a thread — no
## máximo uma busca, `MOVETIME_MS`.
func abandon() -> void:
	_abandoned = true


## Nota da posição para quem tem a vez. Posição terminal não vai ao motor (ele
## responde `bestmove (none)` sem nota útil): mate é 0, empate 50.
static func look(engine: Stockfish, rules: ChessRules, state: MatchState) -> Dictionary:
	match rules.outcome(state):
		Ruleset.Outcome.WHITE_WINS, Ruleset.Outcome.BLACK_WINS:
			return {"score": 0.0, "mate": 0, "best": "", "mated": true}
		Ruleset.Outcome.DRAW:
			return {"score": 50.0, "mate": 0, "best": "", "mated": false}
	var seen := engine.search(rules.fen(state), MOVETIME_MS)
	if seen.is_empty():
		return {}
	return {"score": expected(seen["wdl"]), "mate": seen["mate"], "best": seen["best"], "mated": false}
