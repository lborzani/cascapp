// Comum às rotas da loja (ver `pb_migrations/1763300000_loja.js`). Sem
// `.pb.js` no nome: não é carregado sozinho, só por `require`. As funções de
// cima não usam nada do PocketBase, e `pocketbase/loja.test.js` as testa no Node.

// O catálogo mora na coleção `shop_items` (ver
// `pb_migrations/1764000000_shop_items.js`), editada no painel admin. Item sem
// registro lá é grátis (as cores, por exemplo). O visual (nome, arquivo, tipo)
// mora no app, em `core/cosmetics.gd`.

// O catálogo a partir das linhas da coleção: `prices` só com o que está à venda
// (ativo e não exclusivo), `paid` com todo item que precisa estar no `owned`
// para ser equipado e `exclusive` com os que só saem por missão.
function catalogOf(rows) {
  const prices = {}
  const paid = []
  const exclusive = []
  for (const row of rows) {
    paid.push(row.item)
    if (row.exclusive) {
      exclusive.push(row.item)
    } else if (row.active) {
      prices[row.item] = row.price
    }
  }
  return { prices, paid, exclusive }
}

// O catálogo lido do banco, a cada pedido: a coleção é pequena e o admin quer
// ver a mudança na hora.
function loadCatalog(app) {
  return catalogOf(app.findAllRecords("shop_items").map((record) => ({
    item: record.getString("item"),
    price: record.getInt("price"),
    exclusive: record.getBool("exclusive"),
    active: record.getBool("active"),
  })))
}

const DAILY = 50
// Por partida terminada contra bot ou online, pelo desfecho de quem pede.
const REWARDS = { win: 25, draw: 15, loss: 10 }
// ponytail: o app conta o próprio desfecho e o servidor confia, só limitando o
// total do dia. Para fechar de vez, o relay arbitra o prêmio online, como já
// faz com o Elo do xadrez (`relay/src/ratings.ts`).
const REWARD_CAP = 300
const GAMES = ["chess", "checkers", "battleship", "ludo", "monopoly", "uno", "pool", "bowling"]
const LOOK_SLOTS = 12

// O dia de Brasília (UTC-3, sem horário de verão desde 2019), "AAAA-MM-DD".
function brDay(ms) {
  return new Date(ms - 3 * 3600 * 1000).toISOString().slice(0, 10)
}

// Quanto pagar por uma partida, dado o que já foi pago hoje. `null` quando o
// pedido é inválido.
function rewardFor(game, result, earnedToday) {
  if (!GAMES.includes(game) || !(result in REWARDS)) {
    return null
  }
  return Math.max(0, Math.min(REWARDS[result], REWARD_CAP - earnedToday))
}

// O primeiro item pago (`paid`, do catálogo) do visual que não está em
// `owned`, ou "" quando o visual é válido. `null` quando o formato está errado.
function lookProblem(look, owned, paid) {
  if (look === null || typeof look !== "object" || Array.isArray(look)) {
    return null
  }
  const slots = Object.keys(look)
  if (slots.length > LOOK_SLOTS) {
    return null
  }
  for (const slot of slots) {
    const item = look[slot]
    if (typeof item !== "string" || slot.length > 20 || item.length > 40) {
      return null
    }
    if (paid.includes(item) && !owned.includes(item)) {
      return item
    }
  }
  return ""
}

// Um campo JSON do registro, já decodificado.
function jsonOf(record, name, fallback) {
  const raw = record.getString(name)
  if (raw === "" || raw === "null") {
    return fallback
  }
  try {
    return JSON.parse(raw)
  } catch (_) {
    return fallback
  }
}

function wallet(record) {
  return {
    coins: record.getInt("coins"),
    owned: jsonOf(record, "owned", []),
    look: jsonOf(record, "look", {}),
    // Para o app ignorar a resposta que chega depois de uma mais nova.
    updated: record.getString("updated"),
  }
}

module.exports = { catalogOf, loadCatalog, DAILY, REWARDS, REWARD_CAP, GAMES, brDay, rewardFor, lookProblem, jsonOf, wallet }
