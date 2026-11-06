/// <reference path="../pb_data/types.d.ts" />

// O resultado de uma partida de xadrez online, mandado pelo relay depois de
// conferir os dois lados (ver `relay/src/ratings.ts`). Muda o Elo das duas
// contas e guarda a partida em `chess_games`, numa transação só.
//
// Só o relay chama: o pedido traz o segredo compartilhado no cabeçalho
// `X-Cascapp-Relay`, que precisa bater com `CASCAPP_RELAY_SECRET` do ambiente.
// Sem a variável a rota recusa tudo — melhor sem Elo que Elo de qualquer um.
//
// Corpo: {key, white, black, result: "white"|"black"|"draw", plies}, com
// `white`/`black` os ids das contas. Resposta: {white: {elo, delta}, black: {...}}.
routerAdd("POST", "/api/cascapp/chess-result", (e) => {
  const elo = require(`${__hooks}/elo.js`)
  const secret = $os.getenv("CASCAPP_RELAY_SECRET")
  const sent = e.request.header.get("X-Cascapp-Relay")
  if (secret === "" || !$security.equal(sent, secret)) {
    return e.json(403, { message: "Só o relay registra resultado." })
  }

  const body = e.requestInfo().body
  const key = String(body.key || "")
  const result = String(body.result || "")
  const plies = Number(body.plies)
  if (key === "" || key.length > 200 || !["white", "black", "draw"].includes(result) ||
      !Number.isInteger(plies) || plies < 0 || body.white === body.black) {
    return e.json(400, { message: "Resultado inválido." })
  }

  let reply = null
  try {
    e.app.runInTransaction((tx) => {
      // Repetido: devolve o que foi gravado, sem contar de novo.
      try {
        const old = tx.findFirstRecordByData("chess_games", "key", key)
        reply = elo.replyOf(old)
        return
      } catch (_) {}

      const white = tx.findRecordById("users", String(body.white))
      const black = tx.findRecordById("users", String(body.black))
      const score = result === "white" ? 1 : result === "black" ? 0 : 0.5
      const whiteDelta = elo.delta(white, black, score)
      const blackDelta = elo.delta(black, white, 1 - score)
      for (const [record, change] of [[white, whiteDelta], [black, blackDelta]]) {
        record.set("elo_chess", elo.ratingOf(record) + change)
        record.set("games_chess", record.getInt("games_chess") + 1)
        tx.saveNoValidate(record)
      }
  
      const game = new Record(tx.findCollectionByNameOrId("chess_games"))
      game.set("key", key)
      game.set("white", white.id)
      game.set("black", black.id)
      game.set("result", result)
      game.set("plies", plies)
      game.set("white_elo", white.getInt("elo_chess"))
      game.set("white_delta", whiteDelta)
      game.set("black_elo", black.getInt("elo_chess"))
      game.set("black_delta", blackDelta)
      tx.save(game)
      reply = elo.replyOf(game)
    })
  } catch (_) {
    // Conta que não existe (apagada no meio da partida): nada muda.
    return e.json(400, { message: "Conta não encontrada." })
  }
  return e.json(200, reply)
})
