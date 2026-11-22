class_name MatchLog
extends RefCounted

## Uma partida do histórico (`Prefs.history`), em qualquer jogo.
##
## Até a 1.58 só o xadrez entrava no histórico, porque ele existia para abrir a
## revisão. Agora toda partida que termina entra, e o xadrez continua levando os
## lances (`moves`) que a revisão e o treino leem. É `moves` que separa as
## partidas revisáveis das outras, e não o nome do jogo: as partidas de xadrez
## gravadas antes desta versão não têm o campo `game`.
##
## Só regras, sem autoload: quem grava é `Game.record_result`, que sabe o jogo, o
## modo e contra quem.

const WIN := "win"
const LOSS := "loss"
const DRAW := "draw"


## A linha nova. `mood` é o `ResultHeader.Mood` de quem joga neste aparelho, ou
## -1 quando a partida parou sem vencedor (alguém saiu). No mesmo aparelho não há
## "eu" contra alguém, e o resultado fica vazio.
static func entry(game_id: StringName, hotseat: bool, mode_name: String, mood: int, against: String, stats: Array, started: int, now: int) -> Dictionary:
	return {
		"at": now,
		"started": started,
		"game": String(game_id),
		"mode": mode_name,
		"result": "" if hotseat else result_of(mood),
		"against": against,
		"detail": summary(stats),
	}


## Na ordem de `ResultHeader.Mood` (WIN, DRAW, LOSS). Pelo índice, e não pelo
## enum: o `ResultHeader` puxa telas que usam autoload, e este arquivo roda nos
## testes sem eles (`tests/test_runner.gd`). O `scene_probe` confere a ordem.
const MOODS := [WIN, DRAW, LOSS]


static func result_of(mood: int) -> String:
	return MOODS[mood] if mood >= 0 and mood < MOODS.size() else ""


## "Vitória", "Derrota", "Empate", ou vazio (mesmo aparelho, abandono, partida
## antiga sem o campo).
static func result_text(game: Dictionary) -> String:
	match str(game.get("result", "")):
		WIN:
			return "Vitória"
		LOSS:
			return "Derrota"
		DRAW:
			return "Empate"
	return ""


## O jogo da linha. As de antes da 1.59 eram todas de xadrez.
static func game_of(game: Dictionary) -> StringName:
	return StringName(str(game.get("game", "chess")))


## A mesma partida já está na frente do histórico: o painel de fim reabre
## (convite de revanche, oponente que sai) e o fim pode chegar duas vezes pela
## rede. A revanche zera o começo (`Game.restart_match`), então ela é outra.
static func same_match(last: Dictionary, game_id: StringName, started: int) -> bool:
	return started > 0 and int(last.get("started", -1)) == started and game_of(last) == game_id


## Os números do cartão de fim numa linha: "4:12 duração · 32 jogadas".
static func summary(stats: Array) -> String:
	var parts := PackedStringArray()
	for stat: Array in stats:
		parts.append("%s %s" % [stat[0], stat[1]])
	return " · ".join(parts)


## Só as partidas que a revisão sabe abrir.
static func reviewable(games: Array) -> Array:
	return games.filter(func(game: Dictionary) -> bool: return game.has("moves"))
